// app/test/schedule_timeline_test.dart
//
// 排班管理页顶部那一节「排班时段」。
//
// 这一节是「某天归哪套」的**唯一**入口（编辑器那一节在 v0.9.13 拆掉了），所以它
// 显示错了没有第二个地方能兜住；而它挡在保存前的重叠校验是这一轮重做的**核心
// 承诺** —— 用户要的是「不许我犯错」，不是「替我选一个」。
import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/calendar/schedule_management_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 建两套方案（A 是「其余时间」）+ 渲染排班管理页。
Future<AppDatabase> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  final repo = AppRepository(db);
  for (final (name, current) in [('四班两倒', true), ('备选A', false)]) {
    await repo.saveSchedule(
      name: name,
      anchorDate: DateTime.utc(2026, 1, 1),
      classes: [
        ShiftClass(name: '$name-白', abbr: '白', startMinute: 480, endMinute: 1080),
      ],
      cycle: const [0],
      makeCurrent: current,
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

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

Future<List<ScheduleSpanRow>> _spans(AppDatabase db) =>
    (db.select(db.scheduleSpanRows)
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .get();

/// 主动拆掉界面并推一下时钟：drift 取消查询流时排的零时长定时器要真的跑掉，
/// 否则框架报「A Timer is still pending…」（与 `calendar_screen_test` 同一套）。
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

/// 弹层里选一天（日期选择层点某天**直接返回**，没有「确定」按钮）。
Future<void> _pickDay(WidgetTester tester, int day) async {
  await tester.tap(find.descendant(
      of: find.byType(BottomSheet), matching: find.text('$day')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() {
    L10n.locale = 'zh';
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('没有段 → 只有「其余时间」一行（指向当前方案）+「添加时段」', (tester) async {
    await _pump(tester);

    expect(find.text(L10n.scheduleTimeline), findsOneWidget);
    expect(find.text(L10n.remainingTime), findsOneWidget);
    expect(find.text('四班两倒'), findsWidgets, reason: '其余时间指向它');
    expect(find.text(L10n.addSpan), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('有段 → 段行排在「其余时间」下面，按起点升序', (tester) async {
    final db = await _pump(tester);
    final repo = AppRepository(db);
    final rows = await repo.listSchedules();
    await repo.addSpan(rows[1].id, from: _d(2026, 9, 1), to: _d(2026, 9, 30));
    await repo.addSpan(rows[1].id, from: _d(2026, 10, 8));
    await tester.pumpAndSettle();

    // 三行都在，且顺序对：其余时间 → 9/1～9/30 → 10/8 起
    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((s) =>
            s == L10n.remainingTime ||
            s.startsWith(L10n.monthDay(_d(2026, 9, 1))) ||
            s.startsWith(L10n.monthDay(_d(2026, 10, 8))))
        .toList();
    expect(labels, [
      L10n.remainingTime,
      L10n.effectiveRangeSpan(
          L10n.monthDay(_d(2026, 9, 1)), L10n.monthDay(_d(2026, 9, 30))),
      L10n.effectiveFromDate(L10n.monthDay(_d(2026, 10, 8))),
    ]);

    await _dispose(tester);
  });

  testWidgets('「其余时间」能设成「无」，也能设回来', (tester) async {
    final db = await _pump(tester);

    await tester.tap(find.text(L10n.remainingTime).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.remainingNone).last);
    await tester.pumpAndSettle();

    expect((await AppRepository(db).getActiveSchedules())!.currentScheduleId,
        isNull);
    // 用 `findsWidgets`：弹层里那个「无」选项可能还挂在关闭动画里。真正的判据
    // 是上面那句状态断言。
    expect(find.text(L10n.remainingNone), findsWidgets, reason: '那一行显示「无」');

    // 再设回来
    await tester.tap(find.text(L10n.remainingTime).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('四班两倒').last);
    await tester.pumpAndSettle();
    expect((await AppRepository(db).getActiveSchedules())!.currentScheduleId,
        isNotNull);

    await _dispose(tester);
  });

  testWidgets('既不是其余时间、也没段的方案带「未使用」', (tester) async {
    await _pump(tester);
    // 它是**列表行副标题**里的一段（「未使用 · 1 个班组 · 1月1日」），所以
    // `find.text` 整串比不中，要用 `textContaining`。
    expect(find.textContaining(L10n.unusedSchedule), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('加一段与已有的段重叠 → 不让写库，并点名撞了谁', (tester) async {
    final db = await _pump(tester);
    final repo = AppRepository(db);
    final rows = await repo.listSchedules();
    final now = DateTime.now();
    await repo.addSpan(rows[1].id,
        from: DateTime(now.year, now.month, 1),
        to: DateTime(now.year, now.month + 1, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text(L10n.addSpan));
    await tester.pumpAndSettle();
    // 起 = 本月 15 日（落在已有那一段里）→ 止留空 = 一直持续 → 必然重叠
    await tester.tap(find.text(L10n.spanFrom));
    await tester.pumpAndSettle();
    await _pickDay(tester, 15);
    await tester.tap(find.text(L10n.save));
    await tester.pumpAndSettle();

    expect(await _spans(db), hasLength(1), reason: '撞上就不该写库');
    expect(find.textContaining('重叠了'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('首尾相接**可以**存（A 到 14 日、新的从 15 日起）', (tester) async {
    final db = await _pump(tester);
    final repo = AppRepository(db);
    final rows = await repo.listSchedules();
    final now = DateTime.now();
    await repo.addSpan(rows[1].id,
        from: DateTime(now.year, now.month, 1),
        to: DateTime(now.year, now.month, 14));
    await tester.pumpAndSettle();

    await tester.tap(find.text(L10n.addSpan));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.spanFrom));
    await tester.pumpAndSettle();
    await _pickDay(tester, 15);
    await tester.tap(find.text(L10n.save));
    await tester.pumpAndSettle();

    final spans = await _spans(db);
    expect(spans, hasLength(2), reason: '相接不算重叠');
    expect(dayNumber(spans.last.startDate!), dayNumber(DateTime(now.year, now.month, 15)));

    await _dispose(tester);
  });

  testWidgets('删掉一段之后它就不在时间线上了', (tester) async {
    final db = await _pump(tester);
    final repo = AppRepository(db);
    final rows = await repo.listSchedules();
    final now = DateTime.now();
    await repo.addSpan(rows[1].id,
        from: DateTime(now.year, now.month, 1),
        to: DateTime(now.year, now.month, 14));
    await tester.pumpAndSettle();

    await tester.tap(find.text(L10n.effectiveRangeSpan(
        L10n.monthDay(DateTime(now.year, now.month, 1)),
        L10n.monthDay(DateTime(now.year, now.month, 14)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.delete));
    await tester.pumpAndSettle();

    expect(await _spans(db), isEmpty);

    await _dispose(tester);
  });

}
