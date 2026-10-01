// app/test/factory_reset_test.dart
//
// 「清空重置」= **回到第一次安装的样子**（2026-10-01 用户定）。
//
// 起因是查文案时发现的一处**文案与行为不符**：那一行写着「清空重置」，而
// `clearAll()` 只清了排班那半边 —— 自定义闹钟还在、攒的「我的模板」还在，
// 用户重置完发现闹钟照响、模板照在，只会当成 bug。用户的原话是
// 「顾名思义，就是让软件回到第一次安装时的状态」，所以这一轮把**库以外**的几样
// 也一并做掉：我保存的铃声文件、外观那一组设置、首启标记与小组件快照。
//
// 两条用例分别钉两头：
//   · 仓库层 —— `clearAll()` 真的把自定义闹钟与模板一起清了，并且种回默认排班；
//   · 界面层 —— 走一遍「我的 → 清空重置 → 确认」，库 / 设置 / 首启标记 / 铃声
//     全回出厂，且原生那边收到了「全撤」的调用。
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/haptics.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/schedule_template.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/profile/profile_screen.dart';
import 'package:shiftassistantpro/state/app_settings.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 有界推进若干帧。
///
/// **不能用 `pumpAndSettle`**：「我的」页的权限卡在 `initState` 会去调一串原生
/// 插件方法，那些调用在 `flutter_test` 里不会 resolve，卡片一直停在无限动画的
/// 加载态，`pumpAndSettle` 会等到超时（`haptics_setting_test.dart` 同一处坑）。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 24}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 一个能存进「我的模板」的最小方案。
ScheduleTemplate _template() => const ScheduleTemplate(
      name: '我的三班',
      classes: [
        ShiftClass(name: '早', abbr: '早', startMinute: 480, endMinute: 960),
        ShiftClass(name: '休', abbr: '休', isRest: true),
      ],
      cycle: [0, 1],
      teamCount: 2,
      teamOffsets: [0, 1],
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late AppRepository repo;

  setUp(() async {
    L10n.locale = 'zh';
    db = AppDatabase.forTesting(
        NativeDatabase.opened(sqlite3.sqlite3.openInMemory()));
    repo = AppRepository(db);
    await repo.ensureSeeded();
  });
  tearDown(() => db.close());

  test('仓库层：clearAll 连自定义闹钟与「我的模板」一起清，并种回默认排班', () async {
    await repo.addCustomAlarm(hour: 6, minute: 30, repeatType: 1);
    await repo.saveTemplate(_template());
    expect(await repo.listCustomAlarms(), hasLength(1));
    expect(await repo.listTemplates(), hasLength(1));

    await repo.clearAll();

    // 这两条是这一轮补上的（此前只清排班那半边）。
    expect(await repo.listCustomAlarms(), isEmpty,
        reason: '自定义闹钟也要清 —— 「回到第一次安装时的状态」');
    expect(await repo.listTemplates(), isEmpty, reason: '「我的模板」同理');
    expect(await repo.listEvents(), isEmpty);
    expect(await repo.listSchedules(), isNotEmpty,
        reason: '清完要种回默认「四班两倒」，不能留一座空库');
  });

  testWidgets('界面层：确认之后库、外观设置、首启标记一起回到出厂',
      (tester) async {
    // 假装这台机器上已经用了一阵子：外观改过、铃声自选过、首启也走过。
    SharedPreferences.setMockInitialValues({
      'themeMode': 'dark',
      'accentIndex': 3,
      'liquidGlass': true,
      'hapticsEnabled': false,
      'ringtoneUri': 'file:///ringtone/mine.mp3',
      'ringtoneTitle': '我的铃声',
      'onboarded': true,
      'lastSeenVersion': '0.9.19',
    });

    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in const [
      'com.daoban.shiftassistantpro/settings',
      'dexterous.com/flutter/local_notifications',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(
          () => messenger.setMockMethodCallHandler(MethodChannel(name), null));
    }

    await repo.addCustomAlarm(hour: 6, minute: 30, repeatType: 1);
    await repo.saveTemplate(_template());

    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(
        home: Scaffold(body: ProfileScreen()),
      ),
    ));
    await _pumpFrames(tester);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(ProfileScreen)));
    expect(container.read(appSettingsProvider).themeMode, AppThemeMode.dark,
        reason: '前置：预置的深色真的被读进来了（否则下面的断言是假的）');

    // 「清空重置」在折线以下，先滚到它。
    await tester.scrollUntilVisible(find.text(L10n.clearReset), 200,
        scrollable: find.byType(Scrollable).first);
    await _pumpFrames(tester);
    await tester.tap(find.text(L10n.clearReset));
    await _pumpFrames(tester);
    await tester.tap(find.text(L10n.confirmResetAction));
    await _pumpFrames(tester, frames: 40);

    // 库
    expect(await repo.listCustomAlarms(), isEmpty);
    expect(await repo.listTemplates(), isEmpty);
    expect(await repo.listSchedules(), isNotEmpty);

    // 外观设置：内存里回默认，**并且几个模块级标志跟着翻回来**
    // （只改 state 不翻标志的话，「高级材质」「触觉」在界面上看着变了、实际没生效）
    final settings = container.read(appSettingsProvider);
    expect(settings.themeMode, AppThemeMode.system);
    expect(settings.accentIndex, 0);
    expect(settings.liquidGlass, isFalse);
    expect(settings.hapticsEnabled, isTrue);
    expect(liquidGlassEnabled.value, isFalse);
    expect(hapticsDisabled, isFalse);

    // SharedPreferences 整份清掉：外观那几个键、铃声、首启标记、小组件快照都在里面
    final sp = await SharedPreferences.getInstance();
    expect(sp.getKeys(), isEmpty,
        reason: '不整份清的话，重启后外观又变回来、首启弹窗也不再出现');

    // 原生那边：按空库重排 = 把已排的班次闹钟、通知、待办提醒全撤掉
    expect(calls, contains('cancelAllNativeAlarms'),
        reason: '不撤的话重置完到点还会响');
  });

  testWidgets('界面层：点「取消」什么都不清（返回值被当成确认是迁移最容易丢的一条）',
      (tester) async {
    // Review Focus 第 1 条。把 21 处 `showDialog` 换成 `showGlassDialog` 时，每一处的
    // 泛型与 `await` 之后的用法必须原样保留 —— 丢了就是「点了取消却当成确认」，
    // **不报错**（`false` 与「没返回」在 `if (ok == true)` 之外长得一样）。
    // 上面那条只走了「确认」那一侧，这条补上「取消」那一侧。
    SharedPreferences.setMockInitialValues({
      'themeMode': 'dark',
      'onboarded': true,
      'lastSeenVersion': '0.9.19',
    });
    await repo.addCustomAlarm(hour: 6, minute: 30, repeatType: 1);
    await repo.saveTemplate(_template());

    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(
        home: Scaffold(body: ProfileScreen()),
      ),
    ));
    await _pumpFrames(tester);

    await tester.scrollUntilVisible(find.text(L10n.clearReset), 200,
        scrollable: find.byType(Scrollable).first);
    await _pumpFrames(tester);
    await tester.tap(find.text(L10n.clearReset));
    await _pumpFrames(tester);
    await tester.tap(find.text(L10n.cancel));
    await _pumpFrames(tester, frames: 40);

    expect(await repo.listCustomAlarms(), isNotEmpty,
        reason: '点了「取消」，自定义闹钟却没了 —— 返回值被当成了确认');
    expect(await repo.listTemplates(), isNotEmpty,
        reason: '点了「取消」，「我的模板」却没了');
    final container =
        ProviderScope.containerOf(tester.element(find.byType(ProfileScreen)));
    expect(container.read(appSettingsProvider).themeMode, AppThemeMode.dark,
        reason: '点了「取消」，外观却回默认了');
    final sp = await SharedPreferences.getInstance();
    expect(sp.getKeys(), isNotEmpty,
        reason: '点了「取消」，SharedPreferences 却被清空了');
  });
}
