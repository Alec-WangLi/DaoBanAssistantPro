// app/test/haptics_setting_test.dart
//
// 「触觉反馈」这个开关的三件事：
//   1. 持久化 —— 关掉再重建 notifier，仍然是关的（跟「高级材质」同一套）
//   2. 反灌 —— 它真的会去改 `hapticsDisabled`，否则词汇表根本不知道用户关过
//   3. 界面 —— 页面上真有这一行，且拨动它真的落到上面那个标志上
//   4. 打开的那一刻**补一记确认震** —— 开关自己那记被它正要打开的标志吞掉了
//   5. 关闭时**不补** —— 开关自己那记在标志翻成「关」**之前**就落了地，
//      所以整个关闭动作里只有那一记；notifier 自己再补就是拨一下震两下
// 第 2、3 条是重点：少了哪一处赋值，开关在界面上看着能拨、实际一点作用都没有。
// 第 4、5 条成对：一个钉「补」，一个钉「不补」，两侧都有人看着。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/haptics.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/profile/profile_screen.dart';
import 'package:shiftassistantpro/state/app_settings.dart';

/// 有界推进若干帧。
///
/// **不能用 `pumpAndSettle`**：`ProfileScreen` 里的权限卡在 `initState` 会去调
/// 一串原生插件方法，那些调用在 `flutter_test` 里**不会 resolve**（见
/// `calendar_screen_test.dart` 里同一现象的注释），于是卡片一直停在
/// `CircularProgressIndicator` 的加载态 —— 它是个无限动画，`pumpAndSettle`
/// 会一直等到超时。逐帧推进既不会挂，结果也是确定性的。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 「外观」分区里我们那一个开关：标题文字往上找到最近的 `Row`，开关就在里面。
///
/// 不能直接 `find.byType(GlassSwitch)` —— 同一分区里「高级材质」也是一个，
/// 数出来两个，分不出哪个是哪个。
Finder _hapticsSwitch() => find.descendant(
      of: find
          .ancestor(
            of: find.text(L10n.hapticFeedback),
            matching: find.byType(Row),
          )
          .first,
      matching: find.byType(GlassSwitch),
    );

/// 在平台通道上拦触觉，返回**活的**收集列表。
///
/// 触觉走 `SystemChannels.platform` 的 `HapticFeedback.vibrate`，参数就是那一档
/// 的字符串（`HapticFeedbackType.*`）。返回的 list 由调用方自己 `clear()` / 读，
/// 所以同一个测试里可以在关键动作**前后**分别计数。拆卸由 `addTearDown` 兜。
List<Object?> _captureHaptics() {
  final fired = <Object?>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
    return null;
  });
  addTearDown(() =>
      messenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return fired;
}

void main() {
  // 第 4 条要在平台通道上拦触觉，所以需要 binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    hapticsDisabled = false;
    L10n.locale = 'zh';
  });

  test('默认开着', () async {
    final n = AppSettingsNotifier();
    await pumpEventQueue();
    expect(n.state.hapticsEnabled, isTrue);
    expect(hapticsDisabled, isFalse);
    n.dispose();
  });

  test('关掉之后：状态、持久化、反灌标志三处都跟着走', () async {
    final fired = _captureHaptics();
    final n = AppSettingsNotifier();
    await pumpEventQueue();
    fired.clear(); // 构造里有 `_load()`，与本次关闭无关，先清零

    await n.setHapticsEnabled(false);
    expect(n.state.hapticsEnabled, isFalse);
    expect(hapticsDisabled, isTrue, reason: '词汇表靠这个标志，漏了开关就是摆设');
    // 关闭方向**不补**震：`if (value)` 那道闸门就钉在这里。拿掉它（或写成无条件的
    // `Haptics.select()`）会让这一记在标志还没翻成「关」时发出 —— 真机上就是
    // 每个「关掉触觉」的拨动多响一下。
    expect(fired, isEmpty,
        reason: '关闭不补震：只有开关自己那记，notifier 这边一记都不该有');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('hapticsEnabled'), isFalse, reason: '要能跨启动记住');
    n.dispose();

    // 重建一个 notifier（模拟下次启动）
    hapticsDisabled = false;
    final n2 = AppSettingsNotifier();
    await pumpEventQueue();
    expect(n2.state.hapticsEnabled, isFalse);
    expect(hapticsDisabled, isTrue, reason: '重建时要从设置里把标志反灌回去');
    // 反灌本身也不该出声：启动时读设置就震一下，是另一种「噪音」。
    expect(fired, isEmpty, reason: '`_load()` 只反灌标志，不震');
    n2.dispose();
  });

  test('重新打开时补一记确认震：开关自己那记会被「正要打开的标志」吞掉', () async {
    final fired = _captureHaptics();

    // 先把「关着」放进**持久化**，再构造 notifier —— 真实路径正是如此：`_load()`
    // 读回 `hapticsEnabled == false`，把 `hapticsDisabled` 反灌成 true。
    //
    // 早先这里是在构造之后手写 `hapticsDisabled = true`，但构造里的 `_load()`
    // 紧接着会拿默认的「开」把它覆盖回 false（`app_settings.dart:75`）——
    // 于是构造出来的**根本不是**这条名字说的前置状态，把本项修复的排序改回
    // 错的写法也照样绿（那是本轮评审抓到的第二处「断言立不住」）。走持久化
    // 这条路，前置状态才是真的。
    SharedPreferences.setMockInitialValues({'hapticsEnabled': false});
    final n = AppSettingsNotifier();
    await pumpEventQueue();
    expect(hapticsDisabled, isTrue,
        reason: '前置状态：从持久化的「关」反灌回来，标志此刻必须已是 true');
    fired.clear();

    await n.setHapticsEnabled(true);
    await pumpEventQueue();

    // 打开的那一刻必须补一记：`GlassSwitch.onTap` 那记 `select()` 跑在这一行
    // **之前**，此刻标志还是「关」—— 用户在唯一一次「试这个新开关」的时刻什么
    // 也摸不到。这条断言就是那记补震的执行证据。
    //
    // 它同时钉住**排序**：若 `Haptics.select()` 被挪到 `hapticsDisabled = !value`
    // **之上**，那一记会在标志仍为 true 时被 `_fire` 吞掉，这里就一记都没有。
    expect(fired, ['HapticFeedbackType.selectionClick'],
        reason: '打开时补一记确认震（关闭时不补：那一记由开关自己在标志翻面前发出）');
    expect(hapticsDisabled, isFalse, reason: '补震之后标志要真的落到「开」');
    n.dispose();
  });

  testWidgets('设置页上真有这一行；拨一下，模块标志跟着翻', (tester) async {
    // 页面会读排班（数据区 / 权限卡），所以照 `calendar_screen_test.dart` 的
    // 夹具换掉数据库本身。
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

    await tester.ensureVisible(find.text(L10n.hapticFeedback));
    await _pumpFrames(tester, frames: 4);

    expect(find.text(L10n.hapticFeedback), findsOneWidget);
    expect(find.text(L10n.hapticFeedbackHint), findsOneWidget);
    expect(tester.widget<GlassSwitch>(_hapticsSwitch()).value, isTrue,
        reason: '默认开着，界面要跟设置一致');

    // 拨一下：界面翻面，且**模块标志**真的被写 —— 后者才是词汇表认的东西。
    // 顺手在**拨动前后**数触觉：这一拨是从开到关，该响的只有开关自己那一记
    // （`GlassSwitch.onTap` 的 `select()`）；notifier 那边若也补一记，就会是两记。
    // 拦截器装在拨动前、`pumpWidget` 之后 —— 让构建期的原生调用照旧走默认通道，
    // 只捕获这次拨动。
    final fired = _captureHaptics();
    await tester.tap(_hapticsSwitch());
    await _pumpFrames(tester);

    expect(tester.widget<GlassSwitch>(_hapticsSwitch()).value, isFalse);
    expect(hapticsDisabled, isTrue,
        reason: '拨一下要落到 `hapticsDisabled` 上，否则开关就是个摆设');
    expect(fired, ['HapticFeedbackType.selectionClick'],
        reason: '关掉时**恰好**开关自己那一记；多一记就是「关掉触觉」反而双震');

    // 收尾：主动拆树，让 drift 取消查询流时排的那个零时长定时器跑掉
    //（与 `calendar_screen_test.dart` 的 `_disposeCalendar` 同一件事）。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });
}
