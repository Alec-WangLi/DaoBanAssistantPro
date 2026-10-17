// app/test/snooze_duration_test.dart
//
// 「贪睡时长」这一项的三件事。缺任何一件，「按用户设的时长贪睡」就不成立：
//   1. 读 —— 没存过、或者存了个不在档位里的值，都要退回 5 分钟
//      （退回而不是当成 0：0 分钟的贪睡等于按下就再响，比不给这一项还糟）
//   2. 排 —— `snoozeAlarm` 排的**真的**是「此刻 + 设置值」
//   3. 界面 —— 设置页有这一行、选了真的写进 prefs；响铃那颗按钮上写着时长
//
// 第 2 条是主护栏。前两条都对、但排的时候没用它，是个很容易犯且**完全静默**的错
// —— 用户在设置里挑了半天，回来发现还是 5 分钟，而没有任何地方报错。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/alarm/alarm_ringing_screen.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';
import 'package:shiftassistantpro/features/profile/profile_screen.dart';

/// 有界推进若干帧。**不能用 `pumpAndSettle`**：响铃页里有常驻动画、设置页的权限卡
/// 会去调一串在测试里永不 resolve 的原生方法（同 `haptics_setting_test.dart`）。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 拦下排闹钟那条通道，返回收到的调用列表。
List<MethodCall> _captureSchedule() {
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('com.daoban.shiftassistantpro/settings');
  messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return calls;
}

/// 从拦到的调用里取「排定时刻」。
DateTime _scheduledFire(List<MethodCall> calls) {
  final call = calls.lastWhere((c) => c.method == 'scheduleNativeAlarm');
  final args = call.arguments as Map;
  return DateTime.fromMillisecondsSinceEpoch(args['millis'] as int);
}

/// 排定时刻距 [ref] 还有几分钟。**用这个而不是 `inMinutes`**：后者会截断，
/// 差一毫秒就能骗过断言（`29.999 分钟` 截成 29，看上去像「少了一分钟」）。
double _minutesAhead(List<MethodCall> calls, DateTime ref) =>
    _scheduledFire(calls).difference(ref).inMilliseconds / 60000.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.locale = 'zh';
  });

  group('读设置', () {
    test('没存过 → 5 分钟（= 这一项出现之前的行为）', () async {
      expect(await AlarmService.snoozeMinutes(), 5);
    });

    test('存过就用存的', () async {
      SharedPreferences.setMockInitialValues({AlarmService.snoozeMinutesKey: 30});
      expect(await AlarmService.snoozeMinutes(), 30);
    });

    test('存了个不在档位里的值 → 退回 5 分钟', () async {
      for (final bad in [0, 7, -5, 999]) {
        SharedPreferences.setMockInitialValues(
            {AlarmService.snoozeMinutesKey: bad});
        expect(await AlarmService.snoozeMinutes(), 5,
            reason: '$bad 分钟不在档位里，属于「设置被改坏了」，要退回默认而不是照排');
      }
    });
  });

  group('「再睡一会」按它排', () {
    test('存了 30 分钟 → 排的就是此刻 + 30 分钟', () async {
      SharedPreferences.setMockInitialValues({AlarmService.snoozeMinutesKey: 30});
      final calls = _captureSchedule();

      final before = DateTime.now();
      await AlarmService.snoozeAlarm(const AlarmRing('早班', '9月15日 周二 · 14:30'));

      // ⚠️ **余量只有 0.02 分钟（1.2 秒），且是必须的**：排定时刻经
      // `millisecondsSinceEpoch` 传过通道，那一下会把 `DateTime` 的**微秒截断**，
      // 所以它可能比「此刻 + 30 分钟」早不到 1 毫秒。而这一条要分辨的是 30 分钟与
      // 「没读到设置、还在用 5 分钟」—— 两者差 25 分钟，余量再放大 1000 倍也掩不住。
      expect(_minutesAhead(calls, before), closeTo(30, 0.02),
          reason: '排定时刻距测试里那一点不足 30 分钟，说明设置没读到');
    });

    test('没设过 → 还是 5 分钟（老行为一个字节不变）', () async {
      final calls = _captureSchedule();

      final before = DateTime.now();
      await AlarmService.snoozeAlarm(const AlarmRing('早班'));

      expect(_minutesAhead(calls, before), closeTo(5, 0.02),
          reason: '没设过就该是 5 分钟 —— 这一项出现之前是写死的，升级上来不许变');
    });

    test('标题与说明原样带过去，号段仍是 99998', () async {
      final calls = _captureSchedule();
      await AlarmService.snoozeAlarm(const AlarmRing('早班', '9月15日 周二 · 14:30'));

      final args = calls
          .lastWhere((c) => c.method == 'scheduleNativeAlarm')
          .arguments as Map;
      expect(args['id'], 99998);
      expect(args['label'], '早班');
      expect(args['detail'], '9月15日 周二 · 14:30',
          reason: '说明丢了的话，续排那一次响铃就只剩标题');
    });
  });

  testWidgets('设置页有这一行；选一档，真的写进 prefs，那一行也跟着变', (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await AppRepository(db).ensureSeeded();

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: ProfileScreen()),
    ));
    await _pumpFrames(tester);

    await tester.ensureVisible(find.text(L10n.snoozeDuration));
    await _pumpFrames(tester, frames: 6);

    expect(find.text(L10n.snoozeDuration), findsOneWidget);
    expect(find.text(L10n.snoozeDurationSubtitle(5)), findsOneWidget,
        reason: '默认那一档要写在副标题上，用户不点开也看得到现在是多少');

    await tester.tap(find.text(L10n.snoozeDuration));
    await _pumpFrames(tester);
    await tester.tap(find.text(L10n.snoozeOptionLabel(15)));
    await _pumpFrames(tester);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getInt(AlarmService.snoozeMinutesKey), 15,
        reason: '选完要真的落盘 —— 不落盘的话响铃那一刻读到的还是旧值');
    expect(find.text(L10n.snoozeDurationSubtitle(15)), findsOneWidget,
        reason: '选完那一行要跟着变（`_RingtoneTile` 那条老规矩：选完自己重读一次）');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('响铃那颗按钮上写着时长', (tester) async {
    SharedPreferences.setMockInitialValues({AlarmService.snoozeMinutesKey: 10});

    await tester.pumpWidget(
        const MaterialApp(home: AlarmRingingScreen(label: '早班')));
    await _pumpFrames(tester, frames: 30);

    expect(find.text(L10n.snoozeWithDuration(10)), findsOneWidget,
        reason: '设了 10 分钟却仍写着干巴巴的「再睡一会」，等于没有反馈');
    expect(find.text(L10n.snooze), findsNothing,
        reason: '两颗都画出来就等于按钮上挂着两句自相矛盾的话');
  });
}
