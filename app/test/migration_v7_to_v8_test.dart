// app/test/migration_v7_to_v8_test.dart
//
// v7 → v8 只**新增一张表**：`shift_day_overrides`（按天改班 / 请假覆盖）。
// 这条迁移不碰任何既有表的列，所以 fixture 只需要一张 `shift_schedule_rows`
// 来验「老数据还在」，不必像 v5→v6 那条那样抄全套（那条会重建表、碰好几张表）。
//
// 要验三件事：新表建出来了、老排班原样保留、新表真的能写能读。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v7 时期的 `shift_schedule_rows`（v8 没有改动它）。
const _v7ScheduleTable = '''
CREATE TABLE shift_schedule_rows (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  anchor_date INTEGER NOT NULL,
  is_current INTEGER NOT NULL DEFAULT 0,
  team_count INTEGER NOT NULL DEFAULT 4,
  team_names TEXT NOT NULL DEFAULT '一班,二班,三班,四班',
  our_team_index INTEGER NOT NULL DEFAULT 0,
  team_offsets TEXT NOT NULL DEFAULT ''
)
''';

void main() {
  late sqlite3.Database raw;

  setUp(() {
    raw = sqlite3.sqlite3.openInMemory();
    raw.execute(_v7ScheduleTable);
    raw.execute(
      'INSERT INTO shift_schedule_rows '
      '(id, name, anchor_date, is_current, team_count, team_names, '
      'our_team_index, team_offsets) VALUES (1, ?, ?, 1, 4, ?, 0, ?)',
      [
        '四班两倒',
        DateTime.utc(2025, 1, 6).millisecondsSinceEpoch ~/ 1000,
        '一班,二班,三班,四班',
        '0,1,2,3',
      ],
    );
    raw.execute('PRAGMA user_version = 7');
  });

  tearDown(() => raw.dispose());

  test('v7 → v8：建出 shift_day_overrides，老排班原样保留', () async {
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final schedules = await db.select(db.shiftScheduleRows).get();
    expect(schedules, hasLength(1), reason: '老排班要原样留着');
    expect(schedules.single.name, '四班两倒');
    expect(schedules.single.teamOffsets, '0,1,2,3');

    // 新表建出来了
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty);

    // 而且能写能读
    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: 1,
            day: 20000,
            classId: 7,
          ),
        );
    final rows = await db.select(db.shiftDayOverrides).get();
    expect(rows, hasLength(1));
    expect(rows.single.day, 20000);
    expect(rows.single.classId, 7);
  });
}
