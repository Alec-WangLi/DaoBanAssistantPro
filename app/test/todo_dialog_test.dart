// app/test/todo_dialog_test.dart
//
// 待办弹窗的两处行为：
//
//   1. **「添加」与「编辑」两个弹窗必须是同一套字段**。v0.7.1 就是在这里出的
//      岔子：两处各写了一遍，改提醒档位时只改到「添加」，编辑弹窗还停在旧的两档
//      开关上 —— 点它只会在「不设 / 15 分钟」之间跳。判据是选择器里的那些档位
//      标签（「提前1天」这类）只有弹层才画得出来，两档开关永远不会有。
//   2. **提醒档位与「联动闹钟」开关联动**：开闹钟要补一个可响的时点，选「不设」
//      要顺手把闹钟关掉，否则开关开着却没有时刻，用户以为它会响而它永远不会。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_action_button.dart';
import 'package:shiftassistantpro/core/widgets/glass_dialog.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 有界推进若干帧。
///
/// **不用 `pumpAndSettle`**：它要等到「没有待调度的帧」才返回，页面上只要有一个
/// 一直调度下一帧的东西就会挂到超时（默认 10 分钟）。逐帧推进既不会挂，结果也是
/// 确定性的 —— 与视觉工装同样的做法。800ms 的假时钟足够走完弹窗与弹层的动画。
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

/// 打开某条待办的编辑弹窗。
Future<void> _openEdit(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await _settle(tester);
  expect(find.text(L10n.editEvent), findsOneWidget);
}

/// 弹窗里的那个开关（列表行上也有一个「完成」开关，所以按弹窗范围取）。
Finder _alarmSwitch() => find.descendant(
    of: find.byType(GlassDialog), matching: find.byType(GlassSwitch));

bool _switchOn(WidgetTester tester) =>
    tester.widget<GlassSwitch>(_alarmSwitch()).value;

/// 把插件通道挂上空实现。
///
/// 测试环境没有原生侧，没人接的 MethodChannel 调用**永远不会完成** ——
/// 保存链路里有「重排提醒」这一步（要过通道），不桩的话它卡在那里，
/// 弹窗就永远关不掉，测出来的失败像是保存坏了。与视觉工装
/// （`tool/visual/visual_harness.dart` 的 `stubPluginChannels`）同一件事。
///
/// [delay] 是给「保存链路还在飞」那两条用例准备的：真机上这段链路要过原生
/// 通道，几十到几百毫秒；测试环境里通道是桩、库在内存，**几微秒就跑完**。
/// 不撑开这个窗口，第二次点击就落在窗口之外，测出来的是「慢点两下」。
void _stubPluginChannels({Duration delay = Duration.zero}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in const [
    'dexterous.com/flutter/local_notifications',
    'com.daoban.shiftassistantpro/settings',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      return null;
    });
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    L10n.locale = 'zh';
    SharedPreferences.setMockInitialValues({});
    _stubPluginChannels();
  });

  testWidgets('编辑弹窗：提醒档位弹得出选择器（v0.7.1 只会在两档之间跳）',
      (tester) async {
    final db = await _pumpTodos(tester);
    await AppRepository(db).addEvent(
      title: '交体检报告',
      date: dateOnly(DateTime.now()),
      timeMinute: 14 * 60,
      advanceRemindMinutes: 15,
    );
    await _settle(tester);
    await _openEdit(tester, '交体检报告');

    await tester.tap(find.text(L10n.advanceRemindOptional));
    await _settle(tester);

    // 这些标签只有档位弹层画得出来。
    expect(find.text(L10n.remindOptionLabel(0)), findsOneWidget); // 准时
    expect(find.text(L10n.remindOptionLabel(1440)), findsOneWidget); // 提前1天
    expect(find.text(L10n.remindOptionLabel(30)), findsOneWidget); // 提前30分钟

    await tester.tap(find.text(L10n.remindOptionLabel(1440)));
    await _settle(tester);
    // 选完落到那一行上（弹层已关，剩下这一处）。
    expect(find.text(L10n.remindOptionLabel(1440)), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('添加弹窗：提醒档位同样弹得出选择器', (tester) async {
    await _pumpTodos(tester);

    await tester.tap(find.byIcon(Icons.add_outlined));
    await _settle(tester);
    expect(find.text(L10n.addEvent), findsOneWidget);

    await tester.tap(find.text(L10n.advanceRemindOptional));
    await _settle(tester);
    expect(find.text(L10n.remindOptionLabel(1440)), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('联动闹钟开关：开时补「准时」，选「不设」时自动关', (tester) async {
    final db = await _pumpTodos(tester);
    await AppRepository(db).addEvent(
      title: '交体检报告',
      date: dateOnly(DateTime.now()),
      timeMinute: 14 * 60,
    );
    await _settle(tester);
    await _openEdit(tester, '交体检报告');

    expect(_switchOn(tester), isFalse, reason: '默认只弹通知');
    expect(find.text(L10n.remindOptionLabel(L10n.remindNone)), findsOneWidget,
        reason: '一开始没设提醒');

    // 开闹钟 → 提醒自动补成「准时」
    await tester.tap(_alarmSwitch());
    await _settle(tester);
    expect(_switchOn(tester), isTrue);
    expect(find.text(L10n.remindOptionLabel(0)), findsOneWidget,
        reason: '开着闹钟却没有可响的时刻，等于开关是假的');

    // 再把提醒设成「不设」→ 闹钟跟着关
    await tester.tap(find.text(L10n.advanceRemindOptional));
    await _settle(tester);
    await tester.tap(find.text(L10n.remindOptionLabel(L10n.remindNone)).last);
    await _settle(tester);
    expect(_switchOn(tester), isFalse,
        reason: '「不设」的意思就是别提醒我，闹钟不该还开着');

    // 存下去：库里那条待办的两个字段要自洽（没有提醒就没有闹钟）
    await tester.tap(find.text(L10n.save));
    await _settle(tester);
    final saved = (await AppRepository(db).listEvents()).single;
    expect(saved.advanceRemindMinutes, isNull);
    expect(saved.alarmEnabled, isFalse);

    await _dispose(tester);
  });

  testWidgets('键盘弹起把可用高压掉一大截时，保存按钮仍在弹窗里、点得动',
      (tester) async {
    // v0.7.2 真机上「填好了点添加 / 点保存没反应、待办也没出现」就是这个：
    // 弹窗内容把底部的操作按钮**挤出面板** —— 按钮还画在屏幕上，却已经不在
    // 弹窗的可点区域内，手指点下去穿到遮罩上，于是弹窗关闭、什么都没存。
    // 根因是内容区那句 `maxHeight - 100` 在 Column 里拿到的是无穷高度，形同虚设。
    // 视口取矮一些：要复现的是「可用高度装不下弹窗内容」，
    // 高屏上得把键盘模拟得极端夸张才逼得出来，不如直接用一个矮视口。
    final db = await _pumpTodos(tester, height: 560);
    await AppRepository(db).addEvent(
      title: '旧标题',
      date: dateOnly(DateTime.now()),
      timeMinute: 14 * 60,
    );
    await _settle(tester);

    // 模拟键盘占掉底部一块（**逻辑像素**；真机 2608 物理高、dpr 3，键盘约 327 逻辑）。
    // 560 高的视口 + 120 的键盘 = 可用 360，装不下这个弹窗（内容约 450）——
    // 正是真机上「键盘弹起 + 弹窗内容多」的那个场景。
    tester.view.viewInsets = const FakeViewPadding(bottom: 120);
    addTearDown(tester.view.resetViewInsets);

    await _openEdit(tester, '旧标题');

    final panel = tester.getRect(find.byKey(const Key('glass-dialog-panel')));
    final button = tester.getRect(find
        .ancestor(
            of: find.text(L10n.save), matching: find.byType(GlassActionButton))
        .first);
    expect(button.bottom, lessThanOrEqualTo(panel.bottom),
        reason: '按钮被挤出面板之后就点不到了 —— 手指会点到遮罩上，弹窗白关一次');
    expect(tester.takeException(), isNull);

    // 真改一个字段再存：只断言「点得到」不够，要断言保存确实走完了
    await tester.enterText(find.byType(TextField), '新标题');
    await _settle(tester);
    await tester.tap(find.text(L10n.save));
    await _settle(tester);

    // 保存链路里若有异常，会以未处理异步错误的形式在这里浮出来
    final err = tester.takeException();
    expect(err, isNull, reason: '保存过程中抛了异常：$err');

    expect((await AppRepository(db).listEvents()).single.title, '新标题',
        reason: '保存没生效就说明按钮还是点不到（或保存链路断了）');
    expect(find.text(L10n.editEvent), findsNothing, reason: '保存后弹窗该关掉');

    await _dispose(tester);
  });

  // ---------------------------------------------------------------------
  // 弹窗动作被连点 / 被抢跑：v0.9.0 用户反馈「快速点击添加 → 整屏纯黑，但没卡死」
  // （2026-09-21 真机复现：小米 25102RKBEC + release 包，屏幕全黑、`mCurrentFocus`
  // 仍是 MainActivity、无崩溃无 ANR，信息卡上的待办数 +2）。
  //
  // 根因是**这段窗口里按钮照旧能点**：保存链路是异步的（写库 + 重排提醒要过原生
  // 通道），第二次点击又跑了一遍整条链路，于是 pop 了两次 —— 第一次关掉弹窗，
  // 第二次把 App 唯一剩下的那层路由也弹掉了，Navigator 一条路由不剩就是全黑。
  // release 包剥掉断言，所以既不报错也不崩。
  testWidgets('连点两次「添加」：只存一条，且不会把最后一层路由也弹掉',
      (tester) async {
    // 把保存链路的窗口撑开（理由见 `_stubPluginChannels` 的 [delay]）。
    _stubPluginChannels(delay: const Duration(milliseconds: 300));
    final db = await _pumpTodos(tester);

    await tester.tap(find.byIcon(Icons.add_outlined));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '连点测试');
    await _settle(tester);

    // 两次点击之间**故意不 pump**：真机上那两次相隔几十毫秒，而第一次的保存
    // 链路还在 await 里 —— 中间一 pump 就等于把窗口让过去了，测不出问题。
    await tester.tap(find.text(L10n.add));
    await tester.tap(find.text(L10n.add));
    await _settle(tester);

    expect((await AppRepository(db).listEvents()).length, 1,
        reason: '连点两次不该落两条待办');
    expect(find.text(L10n.titleTodo), findsOneWidget,
        reason: '页面还在 —— 第二次 pop 弹掉的是最后一层路由，那是整屏黑屏');

    await _dispose(tester);
  });

  // 另一条通往同一个黑屏的路径：**两条不同的路径各 pop 一次**。
  // 「添加」的保存链路还在 await 里时点「取消」，取消先把弹窗 pop 掉，
  // 添加那条链路的 pop 随后落到 App 最后一层路由上 —— 同样全黑。
  // 这一条**只锁按钮挡不住**（两次点击落在两颗不同的按钮上），必须再有一道
  // 「pop 之前确认自己这层还是最上层」的护栏。
  testWidgets('点完「添加」立刻点「取消」：不黑屏', (tester) async {
    // 同「连点」那条：窗口不撑开，「取消」只会点在已经关掉的弹窗上（找不到
    // 而直接报错），根本走不到要验的那条路径。
    _stubPluginChannels(delay: const Duration(milliseconds: 300));
    final db = await _pumpTodos(tester);

    await tester.tap(find.byIcon(Icons.add_outlined));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '抢跑测试');
    await _settle(tester);

    await tester.tap(find.text(L10n.add));
    await tester.tap(find.text(L10n.cancel));
    await _settle(tester);

    expect(find.text(L10n.titleTodo), findsOneWidget,
        reason: '「取消」抢在保存链路前面 pop 掉弹窗之后，保存链路那次 pop 必须跳过');
    expect((await AppRepository(db).listEvents()).length, 1,
        reason: '「添加」一点下去就落库了，随后的「取消」追不回来 —— 这是**有意的边界**：'
            '这道护栏要挡的是黑屏，不是这条已经发生的写入');

    await _dispose(tester);
  });

  testWidgets('联动闹钟开关：存得进库、列表行上带铃铛', (tester) async {
    final db = await _pumpTodos(tester);
    await AppRepository(db).addEvent(
      title: '交体检报告',
      date: dateOnly(DateTime.now()),
      timeMinute: 14 * 60,
    );
    await _settle(tester);
    await _openEdit(tester, '交体检报告');

    await tester.tap(_alarmSwitch());
    await _settle(tester);
    await tester.tap(find.text(L10n.save));
    await _settle(tester);

    final saved = (await AppRepository(db).listEvents()).single;
    expect(saved.alarmEnabled, isTrue);
    expect(saved.advanceRemindMinutes, 0, reason: '自动补的「准时」');

    // 列表行上那个小铃铛
    expect(find.byIcon(Icons.alarm_outlined), findsOneWidget);

    await _dispose(tester);
  });
}
