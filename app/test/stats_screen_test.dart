// app/test/stats_screen_test.dart
//
// 统计页：默认本月、切年、空排班、指标与年视图下钻。
//
// 期望值不拿 `shiftStatsFor` 反算（那就成了拿同一个函数验证自己）：夹具是
// 10 月 1 日起「上一天白班、休一天」的 2 天循环，31 天里 16 天白班（12 小时）、
// 15 天休息；再在 10/15 记 4 小时请假 → 正常工时 16×12h − 4h = 188h。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_segment.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/day_extra.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/stats/stats_charts.dart';
import 'package:shiftassistantpro/features/stats/stats_screen.dart';

import 'support/fixed_clock.dart';

/// 触觉原生通道名，与 `MainActivity.kt` 的 `hapticsChannel` 一致。
const MethodChannel _hapticsChannel =
    MethodChannel('com.daoban.shiftassistantpro/haptics');

Future<AppDatabase> _seed(WidgetTester tester) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final repo = AppRepository(db);
  await repo.saveSchedule(
    name: '四班两倒',
    anchorDate: DateTime.utc(2026, 10, 1),
    classes: const [
      ShiftClass(
          name: '白班',
          abbr: '白',
          startMinute: 8 * 60,
          endMinute: 20 * 60),
      ShiftClass(name: '休息', abbr: '休', isRest: true),
    ],
    cycle: const [0, 1],
    makeCurrent: true,
    teamCount: 1,
    teamNames: const ['我'],
    teamOffsets: const [0],
  );
  return db;
}

Future<void> _pump(WidgetTester tester, AppDatabase db,
    {Size size = const Size(420, 1400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    // 每个用例换一份库 → 换一个 key：`pumpWidget` 同类型同位置会**复用**
    // `ProviderScope` 的 element，容器里的 override 不会跟着换，于是后面的用例
    // 读到的还是前一个用例的库。
    key: ValueKey(db),
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: StatsScreen()),
  ));
  await tester.pumpAndSettle();
}

/// drift 的查询流在取消时用 `Timer.run` 排一个零时长定时器清理缓存，而 widget
/// 测试在测试体结束**立刻**校验「没有待处理的定时器」—— 不先把它跑掉，每条用例
/// 都会报 `A Timer is still pending`（与 `disposeCalendar` 同一套处置）。
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  useFixedNow();
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('默认打开本月，能切到年', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, db);

    expect(find.text(L10n.yearMonth(DateTime(2026, 10, 1))), findsWidgets);

    await tester.tap(find.descendant(
        of: find.byType(GlassSegment),
        matching: find.text(L10n.statsYear)));
    await tester.pumpAndSettle();

    expect(find.text(L10n.statsYearLabel(2026)), findsWidgets);
    expect(find.byKey(const Key('stats-month-hours-1')), findsOneWidget);
    expect(find.byKey(const Key('stats-month-hours-12')), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('指标：正常工时扣请假、上班 / 休息天数', (tester) async {
    final db = await _seed(tester);
    await AppRepository(db).setDayExtra(
        dayNumber(DateTime.utc(2026, 10, 15)), DayExtraKind.leave, 240);
    await _pump(tester, db);

    final total = tester.widget<Text>(find.byKey(const Key('stats-total-hours')));
    expect(total.data, '188小时');
    expect(find.textContaining(L10n.extraLeaveLine(240)), findsOneWidget);
    expect(find.text('16天'), findsWidgets);
    expect(find.text('15天'), findsWidgets);

    await _dispose(tester);
  });

  testWidgets('没有任何班表在管：空态与零值，不抛异常', (tester) async {
    // 空库会被 `activeScheduleProvider` 的 `seedIfEmpty` 播种成默认方案 ——
    // 要造「没有班表在管」，就存一套**非当前**方案：表非空、不会播种，而
    // `chain.fallback` 与段都为空。
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await AppRepository(db).saveSchedule(
      name: '未使用',
      anchorDate: DateTime.utc(2026, 10, 1),
      classes: const [
        ShiftClass(name: '白班', abbr: '白', startMinute: 480, endMinute: 1200)
      ],
      cycle: const [0],
      makeCurrent: false,
      teamCount: 1,
      teamNames: const ['我'],
      teamOffsets: const [0],
    );
    await _pump(tester, db);

    expect(find.text(L10n.statsNoSchedule), findsWidgets);
    final total = tester.widget<Text>(find.byKey(const Key('stats-total-hours')));
    expect(total.data, '0小时');
    expect(tester.takeException(), isNull);

    await _dispose(tester);
  });

  testWidgets('年视图点某月切回该月', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, db);
    await tester.tap(find.descendant(
        of: find.byType(GlassSegment),
        matching: find.text(L10n.statsYear)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('stats-month-hours-3')));
    await tester.pumpAndSettle();

    expect(find.text(L10n.yearMonth(DateTime(2026, 3, 1))), findsWidgets);
    expect(find.byKey(const Key('stats-month-hours-3')), findsNothing);

    await _dispose(tester);
  });

  testWidgets('320 宽：指标卡与年视图不溢出', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, db, size: const Size(320, 900));
    await tester.tap(find.descendant(
        of: find.byType(GlassSegment),
        matching: find.text(L10n.statsYear)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await _dispose(tester);
  });

  testWidgets('图形统计：环形图 + 出勤构成条 + 年视图柱状图', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, db);

    expect(find.byType(ShiftDonut), findsOneWidget);
    expect(find.byType(CompositionBar), findsOneWidget);
    expect(find.textContaining('%'), findsWidgets,
        reason: '图例要带占比');
    expect(find.text(L10n.statsComposition), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byType(GlassSegment),
        matching: find.text(L10n.statsYear)));
    await tester.pumpAndSettle();
    expect(find.byType(MonthlyHoursBars), findsOneWidget);
    expect(find.text(L10n.statsMonthlyHours), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('请假构成按类型列出；没类型的旧记录归「未分类」', (tester) async {
    final db = await _seed(tester);
    final repo = AppRepository(db);
    await repo.setDayExtra(
      dayNumber(DateTime.utc(2026, 10, 15)),
      DayExtraKind.leave,
      240,
      leaveKind: 'annual',
    );
    await repo.setDayExtra(
      dayNumber(DateTime.utc(2026, 10, 16)),
      DayExtraKind.leave,
      120,
    );
    await _pump(tester, db);

    expect(find.text(L10n.statsLeaveKinds), findsOneWidget);
    expect(find.text(L10n.leaveKindLabel('annual')!), findsOneWidget);
    expect(find.text(L10n.statsLeaveUnspecified), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('统计口径卡默认收起，点开后列出规则', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, db);

    expect(find.text(L10n.statsMethod), findsOneWidget);
    expect(find.text(L10n.statsMethodLines.first), findsNothing);

    await tester.tap(find.byKey(const Key('stats-method-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining(L10n.statsMethodLines.first), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('不再有「排班时段」入口；导出按钮可打开导出弹层', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, db);

    expect(find.byKey(const Key('stats-schedule-link')), findsNothing,
        reason: '2026-11-17 用户拍板：统计页不再保留排班时段入口');
    expect(find.text(L10n.statsExport), findsOneWidget);

    await tester.tap(find.text(L10n.statsExport));
    await tester.pumpAndSettle();
    expect(find.text(L10n.exportTitle), findsOneWidget);
    expect(find.text(L10n.exportGenerate), findsOneWidget);

    // 关掉弹层（取消），别让后面清树时还有一层路由。
    await tester.tap(find.text(L10n.cancel));
    await tester.pumpAndSettle();

    await _dispose(tester);
  });

  testWidgets('年视图点年份弹出年份选择器，拨一年确认后切到该年', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, db);
    await tester.tap(find.descendant(
        of: find.byType(GlassSegment),
        matching: find.text(L10n.statsYear)));
    await tester.pumpAndSettle();

    await tester.tap(find.text(L10n.statsYearLabel(2026)));
    await tester.pumpAndSettle();
    expect(find.text(L10n.jumpToYear), findsOneWidget,
        reason: '2026-11-23 用户反馈：年份不该只能靠左右箭头切');

    // 滚轮往上拨一格 = 下一年（itemExtent 40）。
    await tester.drag(find.byType(CupertinoPicker), const Offset(0, -40));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();

    expect(find.text(L10n.statsYearLabel(2027)), findsWidgets,
        reason: '确认后页头应该换到 2027 年');
    expect(find.byKey(const Key('stats-month-hours-1')), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('翻月 / 跳今天：一次操作恰好一记 select，原地不动不震', (tester) async {
    final fired = <Object?>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_hapticsChannel, (call) async {
      if (call.method == 'play') fired.add(call.arguments);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_hapticsChannel, null));

    final db = await _seed(tester);
    await _pump(tester, db);

    await tester.tap(find.byIcon(Icons.chevron_right_outlined));
    await tester.pumpAndSettle();
    expect(fired, ['select'], reason: '翻到 11 月：一次期间变化一记');

    await tester.tap(find.byIcon(Icons.chevron_left_outlined));
    await tester.pumpAndSettle();
    expect(fired, ['select', 'select'], reason: '翻回 10 月：仍是每操作一记');

    // 已经在 10 月，点「本月」不携带新信息 —— 不许震（与日历 ``_today`` 同一条）。
    await tester.tap(find.text(L10n.statsThisMonth));
    await tester.pumpAndSettle();
    expect(fired, ['select', 'select'], reason: '原地跳今天不该震');

    // 年视图点某个月下钻：从前这里是裸 setState（不震），现在也走一记 select。
    await tester.tap(find.descendant(
        of: find.byType(GlassSegment),
        matching: find.text(L10n.statsYear)));
    await tester.pumpAndSettle();
    final afterMode = fired.length; // GlassSegment 自己那一记
    await tester.tap(find.byKey(const Key('stats-month-hours-3')));
    await tester.pumpAndSettle();
    expect(fired.length, afterMode + 1, reason: '下钻到某月恰好一记 select');

    await _dispose(tester);
  });
}
