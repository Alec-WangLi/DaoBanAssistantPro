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
import 'package:shiftassistantpro/features/widget/widget_service.dart';
import 'package:shiftassistantpro/state/app_settings.dart';
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

Future<void> _pumpShell(WidgetTester tester, {AppDatabase? db}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // 调用方可以先把库建好、往里种东西，再传进来挂壳 —— 启动就绪闸只在三个流
  // 第一次到齐时跑一次，挂完壳再种就赶不上了。
  final database = db ??
      AppDatabase.forTesting(
          NativeDatabase.opened(sqlite3.sqlite3.openInMemory()));
  addTearDown(database.close);

  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(database)],
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
    // 快照去重的「上一份」是模块级状态 —— 不清会漏给下一个用例（表现是这一条
    // 的推送被上一条留下的键挡掉，而单跑这一条却是绿的）。
    WidgetService.resetPushCache();
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
  // 下一次触发可能要等到改排班或重启桌面。所以切回前台时**再算一次**，等于给一次重试。
  //
  // 2026-10-10 起「再算一次」与「再推一次」分了家：`push` 自己按**内容**去重
  // （同一份内容不推第二遍 —— 回前台时什么都没改是常态，不该白付一次 224 天构建、
  // 48KB 编码、跨端，以及原生侧全部实例的重渲染）。于是这一对用例钉**意图**的两头：
  // 没变就不推、推失败才重试。
  testWidgets('回前台会重算快照，但内容没变就不重复推', (tester) async {
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

    // 先退后台，再把计数器清了 —— 冷启动那几次推送也已经发生（首帧后 + 三个
    // provider 到齐，后者被 340ms 尾去抖合并过），别把它们算进来。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _pumpFrames(tester, frames: 4);
    calls.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpFrames(tester);

    expect(calls.where((m) => m == 'widgetPushSnapshot'), isEmpty,
        reason: '内容一个字节都没变，就不该再推 —— 去重省掉的正是这一份白付');

    await _disposeShell(tester);
  });

  testWidgets('上一次推失败：回前台必须重试一次', (tester) async {
    const channel = MethodChannel('com.daoban.shiftassistantpro/settings');
    final calls = <String>[];
    var failPush = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'widgetPushSnapshot' && failPush) {
        throw PlatformException(code: 'boom');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    // 首帧 + 三个 provider 那几次全失败（去重不许把失败的记成已推）
    await _pumpShell(tester);
    expect(calls.where((m) => m == 'widgetPushSnapshot'), isNotEmpty,
        reason: '前提：冷启动那几次确实试过推');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _pumpFrames(tester, frames: 4);
    calls.clear();
    failPush = false;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpFrames(tester);

    expect(calls.where((m) => m == 'widgetPushSnapshot'), isNotEmpty,
        reason: '上一次没推成功，回前台必须再试 —— 「我明明打开过 App，桌面却没变」'
            '那条反馈的出口就在这里');

    await _disposeShell(tester);
  });

  // ── 快照的推送触发条件（v0.10.22 收窄 `select` 时砍漏了一条）───────────────
  //
  // `home_shell` 用 `ref.listenManual(appSettingsProvider…)` 推快照，而**快照里带着
  // 主题档与主色**（`widget_snapshot.dart` 的 `themeMode` / `accent`，原生渲染端拿它们
  // 决定今日高亮、胶囊配色与深色判定）。把它收窄成 `select((s) => s.language)` 之后，
  // **换主色、换主题档都不再重推** —— 桌面那张卡停在旧配色上，而 App 里已经变了。
  // 与 v0.10.21 修过的「换语言不重推」是同一类**静默**失效（界面上看不出来）。
  testWidgets('换主色：必须重推快照', (tester) async {
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
    calls.clear();

    ProviderScope.containerOf(tester.element(find.byType(HomeShell)),
            listen: false)
        .read(appSettingsProvider.notifier)
        .setAccentIndex(3);
    await _pumpFrames(tester); // 340ms 尾去抖

    expect(calls.where((m) => m == 'widgetPushSnapshot'), isNotEmpty,
        reason: '换了主色没重推 —— 桌面小组件还停在旧配色上，而 App 里已经变了');

    await _disposeShell(tester);
  });

  testWidgets('启动就绪闸顺手裁一次归档：老库里积了 105 条已完成 → 只剩 100',
      (tester) async {
    // 老库（升级上来、或者长期用下来）里早积了一堆已完成的待办 —— 截断放在启动闸
    // 里就是为了兜住它。勾选那一刻**不**裁：那会让「勾一条去年的待办」当场消失，
    // 「先划掉再收走」那一趟反馈就没了。
    final db = AppDatabase.forTesting(
        NativeDatabase.opened(sqlite3.sqlite3.openInMemory()));
    final repo = AppRepository(db);
    await repo.ensureSeeded();
    for (var i = 0; i < 105; i++) {
      await repo.addEvent(title: 'd$i', date: DateTime.utc(2026, 1, 1 + i));
    }
    // `addEvent` 回的是行 id，不是行 —— 勾选要一个 `ScheduleEvent`，读回来再勾。
    for (final e in await repo.listEvents()) {
      await repo.setEventCompleted(e, true);
    }

    await _pumpShell(tester, db: db);

    expect(
        (await repo.listEvents()).where((e) => e.isCompleted), hasLength(100),
        reason: '启动闸没裁 —— 归档会无限长下去');
    await _disposeShell(tester);
  });
}
