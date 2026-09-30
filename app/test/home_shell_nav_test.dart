// app/test/home_shell_nav_test.dart
//
// 点了待办提醒的通知之后要切到「待办」页（`AlarmService.openTodoRequested`）。
// 这里钉住两件事：页面真的翻过去了，**底部高亮也跟着走了**。
//
// 后半句才是重点：底部导航胶囊的高亮位置是它自己的状态，只在它自己处理手势时
// 更新；外部用 `jumpToPage` 翻页它不会收到通知 —— 那样页面已经切到待办、高亮
// 还停在日历上，看着就像点错了。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/app_info.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 有界推进若干帧。
///
/// **不能用 `pumpAndSettle`**：主壳里有一直调度下一帧的动画（背景光晕等），
/// 它会一直等到超时。逐帧推进既不会挂，结果也是确定性的。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 收尾：主动拆掉界面，并推一下时钟让 drift 取消查询流时排的那个零时长
/// 定时器真的跑掉。
///
/// 不这么做，框架会在测试体结束时自己拆树，随即报
/// 「A Timer is still pending even after the widget tree was disposed」
/// —— drift 的 `StreamQueryStore.markAsClosed` 用 `Timer.run` 延迟清理缓存。
/// （与 `calendar_screen_test.dart` 的 `_disposeCalendar` 同一件事。）
Future<void> _disposeShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: HomeShell()),
  ));
  await _pumpFrames(tester);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    L10n.locale = 'zh';
    // 引导与「版本更新」弹窗都不弹：它们会盖住整个界面。
    SharedPreferences.setMockInitialValues({
      'onboarded': true,
      'lastSeenVersion': appVersion,
    });
  });

  tearDown(() {
    // 这是个全局静态位，不清掉会漏给下一个用例。
    AlarmService.openTodoRequested.value = false;
  });

  testWidgets('待办提醒的通知被点开：切到待办页，底部高亮跟着走', (tester) async {
    await _pumpShell(tester);

    double highlightDx() =>
        tester.getTopLeft(find.byKey(const Key('nav-highlight'))).dx;
    int currentPage() =>
        tester.widget<PageView>(find.byType(PageView)).controller!.page!.round();

    final startDx = highlightDx();
    expect(currentPage(), 0, reason: '默认停在日历页');

    AlarmService.openTodoRequested.value = true;
    await _pumpFrames(tester);

    expect(currentPage(), 2, reason: '应该切到「待办」页');
    expect(highlightDx(), greaterThan(startDx),
        reason: '高亮滑块必须跟着走 —— 页面翻过去了、高亮还停在原处就是这里出的问题');
    expect(AlarmService.openTodoRequested.value, isFalse,
        reason: '请求位要清掉，否则每次重建都会再跳一次');

    await _disposeShell(tester);
  });

  // 一条用户反馈（2026-10-01）的兜底：「装完新版之后，桌面小组件要重启（桌面）才
  // 恢复正常」。根因是**数据只能由 App 算**（原生不查库），所以装完新版确实得先
  // 打开一次 App —— 这句会写进更新简介。但「我打开了、卡片却没变」不该是个死局：
  // 推快照是 fire-and-forget，失败只留一条日志（`WidgetService.push` 的 catch），
  // 下一次触发可能要等到改排班或重启桌面。所以切回前台时再推一次，等于给一次重试。
  testWidgets('从后台切回前台时再推一次小组件快照', (tester) async {
    const channel = MethodChannel('com.daoban.shiftassistantpro/settings');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await _pumpShell(tester);

    // 先退后台，再把计数器清了 —— 冷启动那次推送（首帧后）也已经发生，别把它算进来。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _pumpFrames(tester, frames: 4);
    calls.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpFrames(tester);

    expect(calls.where((m) => m == 'widgetPushSnapshot'), isNotEmpty,
        reason: '切回前台要重推一次快照 —— 这是「打开过 App 卡片却没变」的兜底');

    await _disposeShell(tester);
  });
}
