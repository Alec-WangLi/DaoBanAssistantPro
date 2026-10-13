// app/test/schedule_management_test.dart
//
// 排班管理页里每一套方案那一行。
//
// 按月方案的 `anchorDate` 是个**不再被读取的历史值**（按月不用基准日，每月 1 号
// 恒等于第一段），把它印出来就是「界面上写着一个其实不生效的值」—— 这个仓库反复
// 清的就是这类东西。所以按月那一行改印切法摘要。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/monthly_pattern.dart';
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

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
  });
  setUp(() => L10n.locale = 'zh');

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
}
