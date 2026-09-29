// app/test/calendar_chain_test.dart
//
// 日历整页按天解析：跨时段边界的那个月里，边界前的格子画 A 的班、边界后的画 B 的班，
// 信息卡跟着**选中那天**走，「本月统计」跨方案时按简称合并、加总等于月长。
//
// 每套方案只挂**一个**班次（周期长度 1），所以「哪天归哪套」在格子上一眼可辨：
// A 的简称是「甲」、B 的是「丙」。
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 边界：上半月（1..14）归 A、下半月（15..）归 B。
const int _boundaryDay = 15;

/// 造两套各带时段的方案 + 渲染日历页。
///
/// 时段落在**本月中间**，于是打开日历（默认就是本月）便直接看到衔接。
Future<AppDatabase> _pumpChainedCalendar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  final repo = AppRepository(db);
  final now = DateTime.now();

  Future<int> save(String name, String abbr, {required bool current}) =>
      repo.saveSchedule(
        name: name,
        anchorDate: DateTime.utc(2026, 1, 1),
        classes: [
          ShiftClass(
              name: '$name-班', abbr: abbr, startMinute: 480, endMinute: 1080),
        ],
        cycle: const [0],
        makeCurrent: current,
        teamCount: 1,
        teamNames: const ['我'],
        teamOffsets: const [0],
      );

  final aId = await save('A', '甲', current: true);
  final bId = await save('B', '丙', current: false);
  await repo.setScheduleSpan(aId, to: DateTime(now.year, now.month, 14));
  await repo.setScheduleSpan(bId, from: DateTime(now.year, now.month, _boundaryDay));

  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: CalendarScreen()),
  ));
  await tester.pumpAndSettle();
  return db;
}

/// 某天格子里那个班次胶囊的文字（格子没有班次时这个 key 不存在）。
String _chipLabel(WidgetTester tester, int day) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(ValueKey('day-chip-$day')),
        matching: find.byType(Text)))
    .data!;

/// 信息卡「班次名 · 时间 · 闹钟」那一行的纯文本（三段并成了一段富文本）。
String _shiftLine(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('info-card-shift-line')))
    .textSpan!
    .toPlainText();

Future<void> _tapDay(WidgetTester tester, int day) async {
  await tester.tap(find.text('$day').first);
  await tester.pumpAndSettle();
}

/// 主动拆掉界面并推一下时钟：drift 取消查询流时排的零时长定时器要真的跑掉，
/// 否则框架报「A Timer is still pending...」（与 `calendar_screen_test` 同一套）。
Future<void> _disposeCalendar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('跨时段边界：边界前的格子画 A、边界后的画 B', (tester) async {
    await _pumpChainedCalendar(tester);
    final now = DateTime.now();
    final days = DateTime(now.year, now.month + 1, 0).day;

    // 闭区间：14 日仍归 A、15 日起归 B。
    expect(_chipLabel(tester, 1), '甲');
    expect(_chipLabel(tester, 14), '甲', reason: 'A 的结束日当天仍归 A');
    expect(_chipLabel(tester, _boundaryDay), '丙', reason: 'B 从边界当天起');
    expect(_chipLabel(tester, days), '丙');

    expect(tester.takeException(), isNull);
    await _disposeCalendar(tester);
  });

  testWidgets('信息卡跟着**选中那天**走，不是跟着当前方案', (tester) async {
    await _pumpChainedCalendar(tester);

    // 当前方案是 A（上半月那套）。选边界后的一天，信息卡必须换成 B 的班 ——
    // 这一条正是「整页仍按当前方案画」会漏掉的那个症状。
    await _tapDay(tester, 20);
    expect(_shiftLine(tester), contains('B-班'));
    expect(_shiftLine(tester), isNot(contains('A-班')));

    await _tapDay(tester, 10);
    expect(_shiftLine(tester), contains('A-班'));

    await _disposeCalendar(tester);
  });

  testWidgets('「本月统计」跨方案时按简称合并，加总等于月长', (tester) async {
    await _pumpChainedCalendar(tester);
    final now = DateTime.now();
    final days = DateTime(now.year, now.month + 1, 0).day;

    // 统计行只在装得下的那天画，所以逐天点开找一个画着的日子。
    String? tally;
    for (var d = 1; d <= days && tally == null; d++) {
      await _tapDay(tester, d);
      final f = find.byKey(const Key('info-card-month-tally'));
      if (f.evaluate().isNotEmpty) {
        tally = tester.widget<Text>(f).data;
      }
    }
    expect(tally, isNotNull, reason: '这个月该有画着统计行的日子');
    expect(tally, startsWith(L10n.monthTally));

    // 两套方案各一个班次（甲 / 丙），按简称累加：甲 = 上半月、丙 = 下半月。
    // **不是按 classes 下标数**：那样会把 A 的第 0 个班次和 B 的第 0 个班次算成
    // 同一个，数字会错得看不出来（spec §7.1）。
    final expected = '甲${_boundaryDay - 1} · 丙${days - _boundaryDay + 1}';
    expect(tally!.substring(L10n.monthTally.length).trim(), expected);

    await _disposeCalendar(tester);
  });
}
