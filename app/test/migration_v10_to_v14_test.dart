// app/test/migration_v10_to_v14_test.dart
//
// v10 → v14：**一条长链**（中间跨了 v11 的重复待办、v12 的时段两列、v13 的段
// 表、v14 的按月）。
//
// 为什么单开一条：迁移分支按**倒序**跑（`from < 14` → `from < 13` → …），所以从
// v10 升上来时，**新加的列是在后面好几段重建之前先落下的** —— `from < 13` 那段
// 紧接着就用 `TableMigration(shiftScheduleRows)` 把方案表重建了一遍。`from < 14`
// 放错位置（挪到 `from < 13` 之后）在这一条上会现形，在 v13→v14 那条上却看不见。
//
// fixture 里**只建迁移真正碰到的表**（照 v10→v11 那条的先例）：真实 v10 库什么表
// 都有，而这里要钉的是这段代码在长链上的行为。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v10 形态的方案表（只差 v12 加的那两列与 v14 加的两列）。
const _v10ScheduleTable = '''
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

/// v10 形态的待办表（差 v11 的 `series_id`）。
const _v10ScheduleEvents = '''
CREATE TABLE schedule_events (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  date INTEGER NOT NULL,
  time_minute INTEGER,
  advance_remind_minutes INTEGER,
  is_completed INTEGER NOT NULL DEFAULT 0,
  alarm_enabled INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
)
''';

/// 「我的模板」表（v9 建的那张，v14 之前列没变过）。
const _v10CustomTemplates = '''
CREATE TABLE custom_templates (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  classes TEXT NOT NULL,
  cycle TEXT NOT NULL,
  team_count INTEGER NOT NULL,
  team_offsets TEXT NOT NULL,
  created_at INTEGER NOT NULL
)
''';

int _sec(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

Future<AppDatabase> _openV10() async {
  final raw = sqlite3.sqlite3.openInMemory();
  raw.execute(_v10ScheduleTable);
  raw.execute(_v10ScheduleEvents);
  raw.execute(_v10CustomTemplates);

  raw.execute(
    'INSERT INTO shift_schedule_rows '
    '(id, name, anchor_date, is_current, team_count, team_names, '
    'our_team_index, team_offsets) VALUES (1, ?, ?, 1, 5, ?, 2, ?)',
    ['五班四倒', _sec(DateTime.utc(2026, 1, 6)), '甲乙丙丁戊', '0,1,2,3,4'],
  );
  raw.execute(
    'INSERT INTO schedule_events (id, title, date, time_minute, is_completed, '
    'alarm_enabled, created_at) VALUES (1, ?, ?, ?, 0, 1, ?)',
    ['交体检报告', _sec(DateTime.utc(2026, 10, 2)), 17 * 60, _sec(DateTime.utc(2026, 10, 1))],
  );
  raw.execute(
    'INSERT INTO custom_templates '
    '(id, name, classes, cycle, team_count, team_offsets, created_at) '
    'VALUES (1, ?, ?, ?, 3, ?, ?)',
    ['我的三班倒', '[]', '0,1,2', '0,1,2', _sec(DateTime.utc(2026, 2, 1))],
  );

  raw.execute('PRAGMA user_version = 10');
  return AppDatabase.forTesting(NativeDatabase.opened(raw));
}

void main() {
  test('v10 → v14：新列在长链重建里活下来，老数据一个字段都没变', () async {
    final db = await _openV10();
    addTearDown(db.close);

    // 一路升到**最新**（迁移分支全部倒序跑过），所以这里跟的是当前 schemaVersion。
    expect(db.schemaVersion, 14);

    // ① 方案行原样 —— 注意中间被 `TableMigration` 重建过一次
    final rows = await db.select(db.shiftScheduleRows).get();
    expect(rows.length, 1);
    expect(rows.single.name, '五班四倒');
    expect(rows.single.isCurrent, isTrue);
    expect(rows.single.teamCount, 5);
    expect(rows.single.ourTeamIndex, 2);
    expect(rows.single.teamOffsets, '0,1,2,3,4');
    expect(dayNumber(rows.single.anchorDate), dayNumber(DateTime.utc(2026, 1, 6)));

    // ② v14 的两列在**重建之后**依然在，且带着默认值
    expect(rows.single.monthly, isFalse);
    expect(rows.single.teamSegOffsets, '');

    // ③ 待办原样 + v11 的 series_id 为空
    final events = await db.select(db.scheduleEvents).get();
    expect(events.single.title, '交体检报告');
    expect(events.single.alarmEnabled, isTrue);
    expect(events.single.seriesId, isNull);

    // ④ 模板原样 + v14 的三列带着默认值
    final templates = await db.select(db.customTemplates).get();
    expect(templates.single.name, '我的三班倒');
    expect(templates.single.teamCount, 3);
    expect(templates.single.monthly, isFalse);
    expect(templates.single.monthSegments, '');
    expect(templates.single.teamSegOffsets, '');

    // ⑤ 两条新表（v13 的段表、v14 的按月段表）都在，且能写能读
    expect(await db.select(db.scheduleSpanRows).get(), isEmpty);
    expect(await db.select(db.scheduleMonthSegmentRows).get(), isEmpty);
    await db.into(db.scheduleMonthSegmentRows).insert(
          ScheduleMonthSegmentRowsCompanion.insert(
            scheduleId: 1,
            order: 0,
            startDay: 1,
            classId: 99,
          ),
        );
    expect((await db.select(db.scheduleMonthSegmentRows).getSingle()).startDay, 1);

    // ⑥ 新列可写
    await (db.update(db.shiftScheduleRows)..where((t) => t.id.equals(1)))
        .write(const ShiftScheduleRowsCompanion(
      monthly: Value(true),
      teamSegOffsets: Value('0,2,4'),
    ));
    final updated = await db.select(db.shiftScheduleRows).getSingle();
    expect(updated.monthly, isTrue);
    expect(updated.teamSegOffsets, '0,2,4');
  });
}
