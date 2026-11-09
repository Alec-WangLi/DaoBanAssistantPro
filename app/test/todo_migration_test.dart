// app/test/todo_migration_test.dart
//
// 旧数据一次性迁移：旧版把跨午夜的行挂在「提醒落地日」，新版挂回发生日。
// 迁移必须覆盖**归档行**（否则归档里的班次标记会指到错误的发生日），
// 且不能把用户手工挪到别的日子的行拽回来。
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/clock.dart';
import 'package:shiftassistantpro/core/migration_flags.dart';
import 'package:shiftassistantpro/data/app_database.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/fixed_clock.dart';

void main() {
  useFixedNow();

  setUpAll(() async {
    await initializeDateFormatting('zh');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late AppDatabase db;
  late AppRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(
        NativeDatabase.opened(sqlite3.sqlite3.openInMemory()));
    repo = AppRepository(db);
    await repo.ensureSeeded();
    // 2026-09-23 起：夜班 / 休班 两天一轮 ⇒ 9/23、9/25、9/27 是夜班。
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

  Future<int> insertRow(int seriesId, DateTime day, {bool done = false}) =>
      db.into(db.scheduleEvents).insert(ScheduleEventsCompanion.insert(
            title: '交班记录',
            date: day,
            timeMinute: const Value(0),
            advanceRemindMinutes: const Value(0),
            seriesId: Value(seriesId),
            isCompleted: Value(done),
            createdAt: appNow(),
          ));

  test('旧行 9/24 迁回发生日 9/23；手工挪到 9/27 的行不动', () async {
    final sid = await repo.addRecurringTodo(
      title: '交班记录',
      repeat: RecurRepeat.shift,
      startDate: DateTime(2026, 9, 23),
      shiftNames: const ['夜班'],
      timeMinute: 0,
      advanceRemindMinutes: 0,
    );
    final oldId = await insertRow(sid, DateTime.utc(2026, 9, 24), done: true);
    final manualId = await insertRow(sid, DateTime.utc(2026, 9, 27));

    await repo.migrateLegacyRecurringRowDays();

    final rows = {for (final r in await repo.listEvents()) r.id: r};
    expect(dayNumber(rows[oldId]!.date), dayNumber(DateTime(2026, 9, 23)),
        reason: '归档行也要迁 —— 否则班次标记会指到错误的发生日');
    expect(dayNumber(rows[manualId]!.date), dayNumber(DateTime(2026, 9, 27)),
        reason: '不是旧显示日的行（手工挪过）不许动');
    expect(isPendingTodoOn(rows[manualId]!, DateTime(2026, 9, 27)), true,
        reason: '徽章跟着行日期走：跨午夜待办挂在班次日');
  });

  test('迁移标记只置位一次', () async {
    expect(await legacyRecurringRowDayMigrated(), false);
    await markLegacyRecurringRowDayMigrated();
    expect(await legacyRecurringRowDayMigrated(), true);
  });
}
