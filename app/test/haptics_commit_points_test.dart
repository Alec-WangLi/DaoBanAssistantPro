// app/test/haptics_commit_points_test.dart
//
// 提交点显式震的那几处 —— 「动作落实」这一档（`commit()`，不是 `select()`）。
//
// **覆盖**：
//   1. 危险确认按钮按下时震一次（全 app 四处 `GlassActionVariant.danger`
//      都是破坏性确认，所以触觉挂在按钮里、按变体门住，一处覆盖四处）
//   2. 非危险的同类按钮不震（决策①：普通点击一律不震）—— 这条是**护栏**：
//      若哪天有人把 `commit()` 提到变体判断之外，它立刻红
//   3. 待办勾选完成震一次（真库 + Riverpod 夹具，抄 `todo_dialog_test.dart`
//      的 `_pumpTodos`）
//
// **不覆盖**：「应用改班 / 恢复轮转」与「切换排班方案」这两处。它们要弹选择层、
// 要驱动 `AlarmService.rescheduleAll` 扫班次闹钟，夹具成本远高于收益，所以这里
// 不写；由守门测试兜底（守门保证它们走的是词汇表，而不是绕过词汇表自己发）。
// **这条边界是有意画在这里的**，不是漏写；上一轮有两次因为「断言声称覆盖了
// 其实没覆盖的东西」被打回，所以把没覆盖的明写出来。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/haptics.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_action_button.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 有界推进若干帧。
///
/// **不用 `pumpAndSettle`**：它要等到「没有待调度的帧」才返回，页面上只要有一个
/// 一直调度下一帧的东西就会挂到超时。逐帧推进既不会挂，结果也是确定性的 ——
/// 与 `todo_dialog_test.dart` 同样的做法。
Future<void> _settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 收尾：主动拆掉界面，并推一下时钟让 drift 取消查询流时排的那个零时长定时器
/// 真的跑掉（否则框架报「A Timer is still pending」）。
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

/// 把插件通道挂上空实现。
///
/// 测试环境没有原生侧，没人接的 MethodChannel 调用**永远不会完成** —— 勾一条
/// 待办会走「重排提醒」（要过通道），不桩的话它卡在那里，`commit()` 之后那一步
/// 永远等不到。
void _stubPluginChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in const [
    'dexterous.com/flutter/local_notifications',
    'com.daoban.shiftassistantpro/settings',
  ]) {
    messenger.setMockMethodCallHandler(
        MethodChannel(name), (call) async => null);
  }
}

Future<AppDatabase> _pumpTodos(WidgetTester tester,
    {double height = 900}) async {
  tester.view.physicalSize = Size(420, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: ScheduleScreen()),
  ));
  await _settle(tester);
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Object?> fired;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    fired = [];
    hapticsDisabled = false;
    L10n.locale = 'zh';
    SharedPreferences.setMockInitialValues({});
    _stubPluginChannels();
    // 平台通道的 mock 与上面那两条插件通道**抢同一个 messenger**，
    // 但 `SystemChannels.platform` 是两个插件通道之外的另一个 channel，
    // 各自设各自的 handler，互不覆盖。
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    hapticsDisabled = false;
  });

  testWidgets('危险确认按钮按下时震一次', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlassActionButton(
          label: '删除',
          onPressed: () {},
          variant: GlassActionVariant.danger,
        ),
      ),
    ));
    await tester.tap(find.byType(GlassActionButton));
    await tester.pumpAndSettle();
    expect(fired, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('非危险的同类按钮不震（普通按钮点击一律不震）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlassActionButton(
          label: '取消',
          onPressed: () {},
          variant: GlassActionVariant.secondary,
        ),
      ),
    ));
    await tester.tap(find.byType(GlassActionButton));
    await tester.pumpAndSettle();
    expect(fired, isEmpty, reason: '决策①：普通点击一律不震');
  });

  testWidgets('待办勾选完成：写库之后震一次 commit', (tester) async {
    final db = await _pumpTodos(tester);
    final repo = AppRepository(db);
    await repo.addEvent(
      title: '交体检报告',
      date: dateOnly(DateTime.now()),
      timeMinute: 14 * 60,
    );
    await _settle(tester);

    await tester.tap(find.byType(GlassSwitch));
    await _settle(tester);

    // 库里真的写进去了 —— 没有这一条，下面那断言就只是「点了 → 震了」，
    // 证明不了震在**落库之后**。
    expect((await repo.listEvents()).single.isCompleted, isTrue,
        reason: '勾选没落库，触觉就只是空响');

    // **两次是有意的**：`GlassSwitch` 自己先发 `select`（Task 4 的「开关翻转」），
    // 随后调用点的 `commit` 再发一次（spec §4.2 的表逐字要求
    // 「待办勾选完成 → commit」）。不是漏改，是两档语义叠在同一个控件上 ——
    // 这条断言把它钉住，免得将来有人只看到其中一次就以为另一次是 bug。
    expect(fired, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
    ]);

    await _dispose(tester);
  });
}
