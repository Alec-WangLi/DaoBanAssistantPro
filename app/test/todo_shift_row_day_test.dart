// app/test/todo_shift_row_day_test.dart
//
// 按班次系列的「行挂哪天」：`todoDisplayDay` 纯函数 + 生成器落库两层。
//
// 背景（2026-11-05 用户反馈、Chief 定）：夜班 20:30–次日 08:30 配 0 点的待办，
// 提醒落在**次日** 0 点，而行原先挂在**班次日** —— 用户点开看到「今天」的行、
// 却写着「次日 00:00」，只会觉得系统算错了。行改成跟着提醒走之后，两边是同一个
// 日期，也就不再需要在行上标「次日」。
//
// 这条判据必须与 `planRecurringReminders` 同源（同一个 `alarmDayAnchor`），
// 所以这里的期望值一律由 `_fireAt` 的**外部行为**（排定时刻）反推，不自己另算一遍。
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _night = ShiftClass(name: '夜班', startMinute: 1230, endMinute: 510);
const _day = ShiftClass(name: '白班', startMinute: 480, endMinute: 1200);
const _zero = ShiftClass(name: '零点班', startMinute: 0, endMinute: 480);

RecurringTodo _series({
  required RecurRepeat repeat,
  int? timeMinute,
  List<String> shiftNames = const [],
}) =>
    RecurringTodo(
      id: 1,
      title: '交班记录',
      repeat: repeat,
      startDate: DateTime.utc(2026, 9, 23),
      shiftNames: shiftNames,
      timeMinute: timeMinute,
      advanceRemindMinutes: 0,
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('todoDisplayDay', () {
    final occ = DateTime.utc(2026, 9, 23);

    test('夜班 + 00:00：行落次日（与提醒同一落点）', () {
      final s = _series(
          repeat: RecurRepeat.shift,
          timeMinute: 0,
          shiftNames: const ['夜班']);
      final fire = upcomingFireTimes(s, from: occ, clockMinute: s.timeMinute!, shiftOn: (d) => _night);
      expect(fire.first, DateTime(2026, 9, 24, 0, 0),
          reason: '先确认提醒确实落在次日，再谈行挂哪天');
      expect(todoDisplayDay(s, occ, shift: _night), DateTime.utc(2026, 9, 24));
    });

    test('夜班 + 09:00（上班后、下班前）：行仍在当天', () {
      final s = _series(
          repeat: RecurRepeat.shift,
          timeMinute: 9 * 60,
          shiftNames: const ['夜班']);
      final fire = upcomingFireTimes(s, from: occ, clockMinute: s.timeMinute!, shiftOn: (d) => _night);
      expect(fire.first, DateTime(2026, 9, 24, 9, 0));
      expect(todoDisplayDay(s, occ, shift: _night), DateTime.utc(2026, 9, 24));
    });

    test('白班 + 09:00：行不动（当天上班当天响）', () {
      final s = _series(
          repeat: RecurRepeat.shift,
          timeMinute: 9 * 60,
          shiftNames: const ['白班']);
      expect(todoDisplayDay(s, occ, shift: _day), DateTime.utc(2026, 9, 23));
    });

    test('零点班 + 23:00：行落前一天', () {
      final s = _series(
          repeat: RecurRepeat.shift,
          timeMinute: 23 * 60,
          shiftNames: const ['零点班']);
      // 这里只钉显示日：零点班 00:00–08:00 的 23:00 提醒属于**前一天晚上**。
      // （排定侧 `upcomingFireTimes` 从 9/22 扫起时，9/22 那次已经过去，
      // 队首会是「9/24 那次班、响在 9/23 23:00」—— 那是同一条判据的另一头，
      // 与显示日不是同一个 occurrence，别拿它当期望值。）
      expect(todoDisplayDay(s, occ, shift: _zero), DateTime.utc(2026, 9, 22));
    });

    test('三道闸门任一不成立 → 退回发生日本身', () {
      final shiftRule = _series(
          repeat: RecurRepeat.shift,
          timeMinute: 0,
          shiftNames: const ['夜班']);
      expect(todoDisplayDay(shiftRule, occ), DateTime.utc(2026, 9, 23),
          reason: '那天没有班次（shift == null）');
      final noClock =
          _series(repeat: RecurRepeat.shift, shiftNames: const ['夜班']);
      expect(todoDisplayDay(noClock, occ, shift: _night),
          DateTime.utc(2026, 9, 23),
          reason: '系列没设钟点 —— 全天提醒的钟点是策略值，不参与落点');
      final daily = _series(repeat: RecurRepeat.daily, timeMinute: 0);
      expect(todoDisplayDay(daily, occ, shift: _night),
          DateTime.utc(2026, 9, 23),
          reason: '规则不是按班次');
    });
  });

  group('生成器落库', () {
    late AppDatabase db;
    late AppRepository repo;

    setUp(() async {
      db = AppDatabase.forTesting(
          NativeDatabase.opened(sqlite3.sqlite3.openInMemory()));
      repo = AppRepository(db);
      await repo.ensureSeeded();
      // 2026-09-23 起：夜班 / 休班 两天一轮 ⇒ 9/23 与 9/25 是夜班。
      await repo.saveSchedule(
        name: '夜班轮转',
        anchorDate: DateTime(2026, 9, 23),
        classes: const [
          ShiftClass(name: '夜班', abbr: '夜', startMinute: 1230, endMinute: 510),
          ShiftClass(name: '休班', abbr: '休', isRest: true),
        ],
        cycle: const [0, 1],
        makeCurrent: true,
        teamCount: 1,
        teamNames: const ['我'],
        ourTeamIndex: 0,
        teamOffsets: const [0],
      );
    });
    tearDown(() => db.close());

    test('夜班 + 00:00：行落在次日，班次日没有行', () async {
      await repo.addRecurringTodo(
        title: '交班记录',
        repeat: RecurRepeat.shift,
        startDate: DateTime(2026, 9, 23),
        shiftNames: const ['夜班'],
        timeMinute: 0,
        advanceRemindMinutes: 0,
      );
      await repo.advanceRecurringTodos(today: DateTime(2026, 9, 23));
      final rows = await repo.listEvents();
      expect(rows, hasLength(1));
      expect(dayNumber(rows.single.date), dayNumber(DateTime(2026, 9, 24)),
          reason: '行跟着提醒走：响在 9/24 00:00，行就在 9/24');
    });

    test('反复推进不会多插一行（9/23 → 9/24 → 9/25）', () async {
      await repo.addRecurringTodo(
        title: '交班记录',
        repeat: RecurRepeat.shift,
        startDate: DateTime(2026, 9, 23),
        shiftNames: const ['夜班'],
        timeMinute: 0,
        advanceRemindMinutes: 0,
      );
      await repo.advanceRecurringTodos(today: DateTime(2026, 9, 23));
      await repo.advanceRecurringTodos(today: DateTime(2026, 9, 24));
      var rows = await repo.listEvents();
      expect(rows, hasLength(1),
          reason: '9/24 是休班，occurrence 仍是 9/23，显示日仍是 9/24 —— 不动');
      expect(dayNumber(rows.single.date), dayNumber(DateTime(2026, 9, 24)));

      // 9/25 又是夜班：这一次属于 9/25，显示日 9/26，那条要往前顺延。
      await repo.advanceRecurringTodos(today: DateTime(2026, 9, 25));
      rows = await repo.listEvents();
      expect(rows, hasLength(1));
      expect(dayNumber(rows.single.date), dayNumber(DateTime(2026, 9, 26)),
          reason: '只往前顺延，不新增');
    });

    test('白班 + 09:00：行仍在当天（这一档一个字节没变）', () async {
      await repo.saveSchedule(
        name: '白班',
        anchorDate: DateTime(2026, 9, 23),
        classes: const [
          ShiftClass(name: '白班', abbr: '白', startMinute: 480, endMinute: 1200),
        ],
        cycle: const [0],
        makeCurrent: true,
        teamCount: 1,
        teamNames: const ['我'],
        ourTeamIndex: 0,
        teamOffsets: const [0],
      );
      await repo.addRecurringTodo(
        title: '交班记录',
        repeat: RecurRepeat.shift,
        startDate: DateTime(2026, 9, 23),
        shiftNames: const ['白班'],
        timeMinute: 9 * 60,
        advanceRemindMinutes: 0,
      );
      await repo.advanceRecurringTodos(today: DateTime(2026, 9, 23));
      final rows = await repo.listEvents();
      expect(dayNumber(rows.single.date), dayNumber(DateTime(2026, 9, 23)));
    });
  });
}
