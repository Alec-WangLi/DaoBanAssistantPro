// app/test/schedule_management_test.dart
//
// 排班管理页里每一套方案那一行。
//
// 按月方案的 `anchorDate` 是个**不再被读取的历史值**（按月不用基准日，每月 1 号
// 恒等于第一段），把它印出来就是「界面上写着一个其实不生效的值」—— 这个仓库反复
// 清的就是这类东西。所以按月那一行改印切法摘要。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_delete_button.dart';
import 'package:shiftassistantpro/core/widgets/glass_dialog.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/monthly_pattern.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/calendar/schedule_management_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 按月方案那套的基准日：**故意选一个与真实排班无关的日子** —— 它只证明
/// 「这一行没有把它印出来」。
final _monthlyAnchor = DateTime.utc(2020, 7, 15);

Future<AppDatabase> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  final repo = AppRepository(db);
  // 一套周期方案（「其余时间」）
  await repo.saveSchedule(
    name: '四班两倒',
    anchorDate: DateTime.utc(2026, 1, 6),
    classes: const [ShiftClass(name: '白班', abbr: '白')],
    cycle: const [0],
    makeCurrent: true,
    teamCount: 1,
    teamNames: const ['我'],
    teamOffsets: const [0],
  );
  // 一套按月方案
  await repo.saveSchedule(
    name: '按月三班倒',
    anchorDate: _monthlyAnchor,
    classes: const [
      ShiftClass(name: '中班', abbr: '中'),
      ShiftClass(name: '白班', abbr: '白'),
      ShiftClass(name: '夜班', abbr: '夜'),
    ],
    cycle: const [],
    monthly: true,
    monthSegments: const [
      MonthlySegment(startDay: 1, classIndex: 0),
      MonthlySegment(startDay: 11, classIndex: 1),
      MonthlySegment(startDay: 21, classIndex: 2),
    ],
    makeCurrent: false,
    teamCount: 3,
    teamNames: const ['甲班', '乙班', '丙班'],
    teamOffsets: const [],
    teamSegOffsets: const [0, 1, 2],
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: ScheduleManagementScreen()),
  ));
  await tester.pumpAndSettle();
  return db;
}

/// 主动拆掉界面并推一下时钟：drift 取消查询流时排的零时长定时器要真的跑掉，
/// 否则框架报「A Timer is still pending…」（与 `schedule_timeline_test` 同一套）。
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

/// 造 [count] 套方案并挂上管理页（视口给定）。
///
/// **条数要真的撑破视口** —— 太少了列表滚不动，「滑到底」那条用例就成了一句
/// 永远为真的空话（v0.9.18 的教训：夹具 1200 高、12 条待办根本滚不动，把留白
/// 改回旧值照样绿）。这一页 12 套方案在三个视口下都滚得动（用例里有断言）。
Future<AppDatabase> _pumpMany(WidgetTester tester, Size size,
    {int count = 12}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  final repo = AppRepository(db);
  for (var i = 0; i < count; i++) {
    await repo.saveSchedule(
      name: '方案 $i',
      anchorDate: DateTime.utc(2026, 1, 6),
      classes: const [ShiftClass(name: '白班', abbr: '白')],
      cycle: const [0],
      makeCurrent: i == 0,
      teamCount: 1,
      teamNames: const ['我'],
      teamOffsets: const [0],
    );
  }

  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: ScheduleManagementScreen()),
  ));
  await tester.pumpAndSettle();
  return db;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
  });
  setUp(() {
    L10n.locale = 'zh';
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('按月那一行印切法摘要，不印基准日；周期那一行照旧', (tester) async {
    await _pump(tester);

    expect(find.text('按月三班倒'), findsOneWidget);
    expect(find.textContaining(L10n.scheduleMonthlySummary(3)), findsOneWidget,
        reason: '按月方案那一行要说「每月几段」');
    expect(
        find.textContaining(L10n.monthDay(_monthlyAnchor)), findsNothing,
        reason: '按月不用基准日，印出来就是个不生效的值');

    // 周期那一行原样：仍然印基准日
    expect(find.textContaining(L10n.monthDay(DateTime.utc(2026, 1, 6))),
        findsOneWidget);
    expect(find.textContaining(L10n.scheduleMonthlySummary(0)), findsNothing);

    await _dispose(tester);
  });

  testWidgets('班组数照旧印（切法摘要加在它后面，不是替掉它）', (tester) async {
    await _pump(tester);
    expect(find.textContaining(L10n.teamCountN(3)), findsOneWidget);
    expect(find.textContaining(L10n.teamCountN(1)), findsOneWidget);
    await _dispose(tester);
  });

  // ── 底部那颗「新增排班」落在哪儿 ──
  //
  // 2026-10-15 用户真机反馈：「排班管理的新增排班按钮位置看着有点偏高」。根因是
  // 它用了 tab 页（闹钟页）那条**抬到底部导航胶囊之上**的落点 —— 而那 76dp 是给
  // 胶囊让位的，这一页是 push 出来的整页、底下什么都没有，于是白让一条。
  // 症状是**静默**的：按钮照旧能点，只是浮在半空、底下空一片。
  testWidgets('「新增排班」贴着屏幕底部（这一页底下没有导航胶囊，不该再抬 76）',
      (tester) async {
    await _pump(tester);
    final h = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final bar = tester.getRect(find.byKey(const Key('management-action-bar')));
    expect(bar.height, 56);
    expect(bar.bottom, closeTo(h - 16, 0.5),
        reason: '按钮条底边距屏底 16（FAB 的标准边距）—— 抬 76 是页面底下真有'
            '导航胶囊时才有的事（闹钟页仍在那一档）');
    await _dispose(tester);
  });

  // ── 底部那颗「新增排班」不能挡住最后一行的删除键 ──
  //
  // 排班管理页此前**没有**任何几何用例，这是第一条。它的主操作原先挂在 ListView
  // 的**最后一个孩子**上（只有一两套方案时悬在页面中间、下面一大片空白），改成
  // 与闹钟页同款的**悬浮按钮条**之后，正文不给自己留位置就会被压住：列表一多，
  // 最后一行正好落在它下面，「删除」就点不到了。症状是**静默**的（界面上看不出
  // 「还得再往上滑一点」，用户只知道「点了没反应」）。
  //
  // 判据走**几何 + 命中测试**而不是「列表 padding 是多少」：后者换个写法（把留白
  // 挪进某一项的 margin）就失效，这条要守的是「那一行到底点不点得到」。
  // 三个视口各跑一遍（Review Focus #4）：竖屏 420×900、小窗 200×400、横屏 900×420。
  for (final size in const [Size(420, 900), Size(200, 400), Size(900, 420)]) {
    testWidgets(
        '滑到底：最后一行的删除键整个抬到按钮条之上，且中心真的打得中（${size.width.toInt()}×${size.height.toInt()}）',
        (tester) async {
      await _pumpMany(tester, size);

      // 先确认夹具真的撑破了视口 —— `maxScrollExtent > 0` 才有「滑到底」可言。
      // 不加这一道的话，哪天这页变短了、夹具滚不动了，下面那条断言会变成空话。
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(position.maxScrollExtent, greaterThan(0),
          reason: '夹具必须真的撑破视口 —— 滚不动这条用例就是一句空话');

      // 滑到用户能滑到的最下面那一屏。
      //
      // **一次拖不到底**：`ListView(children:)` 是**惰性**建行的，一开始
      // `maxScrollExtent` 只是**估**出来的，滑下去新行建出来之后它还会变大
      // （实测 200×400 下一次性拖 −8000 只走了 2136 / 3478）。所以要反复拖、
      // 每步之后重新看 extent，直到真的到底。
      for (var i = 0; i < 8 && position.pixels < position.maxScrollExtent; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -1600));
        await tester.pumpAndSettle();
      }
      // 到底了才谈得上「最后一行的删除键在哪儿」—— 没到底这条用例就测错了位置。
      expect(position.pixels, greaterThanOrEqualTo(position.maxScrollExtent - 0.5),
          reason: '必须真的滑到底（max=${position.maxScrollExtent}）');

      final barTop = tester
          .getRect(find.byKey(const Key('management-action-bar')))
          .top;
      final buttons = find.byType(GlassDeleteButton);
      final last = tester.getRect(buttons.last);

      expect(last.bottom, lessThanOrEqualTo(barTop),
          reason: '最后一行的删除键底边（${last.bottom}）应当在按钮条的顶边'
              '（$barTop）之上 —— 被压住就点不到了');

      // **主判据**：在它自己的中心做一次命中测试，它必须真的在命中路径里。
      // 只断言几何的话，「被别的层吃掉手势」这类照样漏。
      final hit = tester.hitTestOnBinding(last.center);
      expect(
          hit.path.any((e) => e.target == tester.renderObject(buttons.last)),
          isTrue,
          reason: '删除键的中心得真的打得中 —— 被按钮条盖住时命中的是按钮条');

      await _dispose(tester);
    });
  }

  // ── 改动排班结构之后必须重排原生闹钟 ──
  //
  // 用户 2026-10-18 真机反馈：「今天是白班，晚上 19:30 却响了上夜班的闹钟」。
  // 根因：排班管理页换「其余时间」/ 增删改时段 / 删方案只写库，**不重排原生
  // 闹钟** —— 日历立刻跟上（它 watch 着库），旧计划里的班次闹钟却照旧在原定时刻
  // 响。在真机上复现过：把「全部日子」切到另一套（那天是上夜班）再切回来，日历
  // 变了、系统里已排的闹钟一条没变。
  //
  // 判据落在**真正发往原生的跨端调用**上：`rescheduleAll` 一进来就整段取消再
  // 重排，`cancelAllNativeAlarms` 是它绕不过去的一步。
  group('改动排班结构要重排闹钟', () {
    late Map<String, int> calls;

    void installChannelSpy() {
      calls = <String, int>{};
      const settings = MethodChannel('com.daoban.shiftassistantpro/settings');
      // flutter_local_notifications 的通道也要接上：`rescheduleAll` 第一件事是
      // `_plugin.cancelAll()`，而 flutter_test 里没人接的通道调用**永远不 resolve**
      // （`calendar_screen_test` 里记过同一条），重排就卡在那儿、后面的原生取消
      // 一次都发不出去。
      const notifications =
          MethodChannel('dexterous.com/flutter/local_notifications');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(settings, (call) async {
        calls[call.method] = (calls[call.method] ?? 0) + 1;
        return null;
      });
      messenger.setMockMethodCallHandler(notifications, (call) async => null);
      addTearDown(() {
        messenger.setMockMethodCallHandler(settings, null);
        messenger.setMockMethodCallHandler(notifications, null);
      });
    }

    int reschedules() => calls['cancelAllNativeAlarms'] ?? 0;

    testWidgets('换「其余时间」到另一套：立刻重排', (tester) async {
      installChannelSpy();
      await _pump(tester);
      expect(reschedules(), 0, reason: '只是挂着这一页，不该动系统闹钟');
      calls.clear();

      await tester.tap(find.text(L10n.allDates));
      await tester.pumpAndSettle();
      expect(find.byType(GlassDialog), findsOneWidget,
          reason: '点「全部日子」那行要先真的弹出选择层，选项才点得到');
      await tester.tap(find.descendant(
          of: find.byType(GlassDialog), matching: find.text('按月三班倒')));
      await tester.pumpAndSettle();

      expect(reschedules(), greaterThanOrEqualTo(1),
          reason: '换完其余时间不重排的话，旧方案里的班次闹钟照旧会在错的晚上响'
              '（正是用户 2026-10-18 报的那条）');
      await _dispose(tester);
    });


    testWidgets('换「其余时间」到另一套：按班次的待办也跟着重算', (tester) async {
      installChannelSpy();
      final db = await _pump(tester);
      final repo = AppRepository(db);

      // 加一套「每天都是夜班」的方案，并建一条「每次夜班带工牌」的待办。
      await repo.saveSchedule(
        name: '每天夜班',
        anchorDate: dateOnly(DateTime.now()),
        classes: const [ShiftClass(name: '夜班', abbr: '夜')],
        cycle: const [0],
        makeCurrent: false,
        teamCount: 1,
        teamNames: const ['我'],
        teamOffsets: const [0],
      );
      final sid = await repo.addRecurringTodo(
        title: '带工牌',
        repeat: RecurRepeat.shift,
        startDate: dateOnly(DateTime.now()),
        shiftNames: const ['夜班'],
      );
      // 当前是「四班两倒」（每天白班）→ 夜班规则今天没有发生日。
      await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
      expect((await repo.listEvents()).where((e) => e.seriesId == sid),
          isEmpty);
      await tester.pumpAndSettle();

      await tester.tap(find.text(L10n.allDates));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(GlassDialog), matching: find.text('每天夜班')));
      await tester.pumpAndSettle();

      final rows = (await repo.listEvents()).where((e) => e.seriesId == sid);
      expect(rows.length, 1,
          reason: '换完其余时间，按班次的当前这一次要立刻跟上 —— '
              '只重排闹钟的话列表里什么都不会变');
      await _dispose(tester);
    });

    testWidgets('新增排班时段：立刻重排', (tester) async {
      installChannelSpy();
      await _pump(tester);
      calls.clear();

      await tester.tap(find.text(L10n.addSpan));
      await tester.pumpAndSettle();
      await tester.tap(find.text(L10n.save));
      await tester.pumpAndSettle();

      expect(reschedules(), greaterThanOrEqualTo(1),
          reason: '时段一加，「今天归哪套」就变了 —— 闹钟得跟着重排');
      await _dispose(tester);
    });

    testWidgets('删除一套排班：立刻重排', (tester) async {
      installChannelSpy();
      await _pump(tester);
      calls.clear();

      await tester.tap(find.byType(GlassDeleteButton).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(L10n.delete));
      await tester.pumpAndSettle();

      expect(reschedules(), greaterThanOrEqualTo(1),
          reason: '删掉一套（尤其是正在用的那套）之后，其余日子会交给别的方案，'
              '旧计划的闹钟必须被撤掉');
      await _dispose(tester);
    });
  });
}
