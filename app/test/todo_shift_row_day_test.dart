// app/test/todo_shift_row_day_test.dart
//
// 按班次系列的「行挂哪天」：生成器落库 + 旧数据迁移的纯函数。
//
// 2026-11-09 用户拍板：跨午夜班次的待办**行挂班次那天**，提醒仍按三档落点响。
// 于是「发生日」与「提醒时刻」彻底分开：
//   · 行 `date` = 发生日（班次那天）；
//   · 提醒时刻 = `alarmDayAnchor` 落点，可能次日 / 前一天；
//   · 行副标题负责把「次日 02:00」说清楚（见 `todo_shift_marker_test.dart`）。
//
// `legacyDisplayDayForMigration` 只服务旧数据迁移与「以后不再重复」的解绑，
// 新行不许再用它。
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

  group('legacyDisplayDayForMigration', () {
    final occ = DateTime.utc(2026, 9, 23);

    test('夜班 + 00:00：旧显示日落在次日', () {
      final s = _series(
          repeat: RecurRepeat.shift,
          timeMinute: 0,
          shiftNames: const ['夜班']);
      final fire = upcomingFireTimes(s,
          from: occ, clockMinute: s.timeMinute!, shiftOn: (d) => _night);
      expect(fire.first, DateTime(2026, 9, 24, 0, 0),
          reason: '先确认提醒确实落在次日，再谈旧显示日');
      expect(legacyDisplayDayForMigration(s, occ, shift: _night),
          DateTime.utc(2026, 9, 24));
    });

    test('夜班 + 09:00：旧显示日仍在次日', () {
      final s = _series(
          repeat: RecurRepeat.shift,
          timeMinute: 9 * 60,
          shiftNames: const ['夜班']);
      expect(legacyDisplayDayForMigration(s, occ, shift: _night),
          DateTime.utc(2026, 9, 24));
    });

    test('白班 + 09:00：旧显示日不动', () {
      final s = _series(
          repeat: RecurRepeat.shift,
          timeMinute: 9 * 60,
          shiftNames: const ['白班']);
      expect(legacyDisplayDayForMigration(s, occ, shift: _day),
          DateTime.utc(2026, 9, 23));
    });

    test('零点班 + 23:00：旧显示日落前一天', () {
      final s = _series(
          repeat: RecurRepeat.shift,
          timeMinute: 23 * 60,
          shiftNames: const ['零点班']);
      expect(legacyDisplayDayForMigration(s, occ, shift: _zero),
          DateTime.utc(2026, 9, 22));
    });

    test('三道闸门任一不成立 → 退回发生日本身', () {
      final shiftRule = _series(
          repeat: RecurRepeat.shift,
          timeMinute: 0,
          shiftNames: const ['夜班']);
      expect(legacyDisplayDayForMigration(shiftRule, occ),
          DateTime.utc(2026, 9, 23),
          reason: '那天没有班次（shift == null）');
      final noClock =
          _series(repeat: RecurRepeat.shift, shiftNames: const ['夜班']);
      expect(legacyDisplayDayForMigration(noClock, occ, shift: _night),
          DateTime.utc(2026, 9, 23),
          reason: '系列没设钟点 —— 全天提醒的钟点是策略值，不参与落点');
      final daily = _series(repeat: RecurRepeat.daily, timeMinute: 0);
      expect(legacyDisplayDayForMigration(daily, occ, shift: _night),
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

    test('夜班 + 00:00：行挂 9/23（班次日），提醒仍在 9/24 00:00', () async {
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
      expect(dayNumber(rows.single.date), dayNumber(DateTime(2026, 9, 23)),
          reason: '行属于班次，不跟着提醒走');
      expect(isPendingTodoOn(rows.single, DateTime(2026, 9, 23)), true,
          reason: '徽章也跟着行日期走：班次日');
      final s = (await repo.listRecurringTodos()).single;
      expect(
          upcomingFireTimes(s,
                  from: DateTime(2026, 9, 23, 20),
                  clockMinute: 0,
                  shiftOn: (d) => d.day == 23 ? _night : null)
              .first,
          DateTime(2026, 9, 24, 0, 0));
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
      expect(rows, hasLength(1));
      expect(dayNumber(rows.single.date), dayNumber(DateTime(2026, 9, 23)),
          reason: '9/24 是休班，occurrence 仍是 9/23 —— 不动');

      // 9/25 又是夜班：这一次属于 9/25，那条要往前顺延。
      await repo.advanceRecurringTodos(today: DateTime(2026, 9, 25));
      rows = await repo.listEvents();
      expect(rows, hasLength(1));
      expect(dayNumber(rows.single.date), dayNumber(DateTime(2026, 9, 25)),
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
