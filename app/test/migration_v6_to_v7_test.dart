// app/test/migration_v6_to_v7_test.dart
//
// v6 → v7 只加了一列：`schedule_events.alarm_enabled`（待办的「联动闹钟」开关），
// 默认 0 = 关，也就是保持旧行为。
//
// 所以这里**只手抄 `schedule_events` 一张表的 v6 形态**，不像 v5→v6 那条用例
// 抄全套 —— 那条迁移会重建表、碰了好几张表，不抄全就测不到；这条只碰一张表，
// 按需要写多少。要验的是三件事：列加出来了、老数据还在、老数据读出来是「关」。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v6 时期的 `schedule_events`：没有 `alarm_enabled`。
/// 班次定义表 —— v6 起就存在，v9→v10 那一步要读它的 `alarm_minute` 搬进新表。
/// fixture 里加它是因为**真实 v6 库一定有这样一张表**（不是为了让断言变松）。
const _v6ClassTable = '''
CREATE TABLE shift_class_rows (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  schedule_id INTEGER NOT NULL,
  "order" INTEGER NOT NULL,
  name TEXT NOT NULL,
  abbr TEXT,
  start_minute INTEGER,
  end_minute INTEGER,
  is_rest INTEGER NOT NULL DEFAULT 0,
  color INTEGER NOT NULL DEFAULT 4284186623,
  alarm_enabled INTEGER NOT NULL DEFAULT 0,
  alarm_minute INTEGER
)
''';

/// 排班方案表 —— 与上面同一类：**v11→v12 会给它加两列**，而迁移分支一律按
/// **倒序**跑（`if (from < 12)` 在 `if (from < 7)` 之前），所以从任何更早的版本
/// 升上来时那两行 `addColumn` 都会执行。真实 v6 库一定有这张表，fixture 就得有。
/// 列是 v6 形态（team_* 三列早在 v2 就加了、team_offsets 在 v4）—— 只差 v12 那两列。
const _v6ScheduleTable = '''
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

const _v6EventsTable = '''
CREATE TABLE schedule_events (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  date INTEGER NOT NULL,
  time_minute INTEGER,
  advance_remind_minutes INTEGER,
  is_completed INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
)
''';

void main() {
  late sqlite3.Database raw;

  setUp(() {
    raw = sqlite3.sqlite3.openInMemory();
    raw.execute(_v6EventsTable);
    raw.execute(_v6ClassTable);
    raw.execute(_v6ScheduleTable);
    raw.execute(
      'INSERT INTO schedule_events '
      '(id, title, date, time_minute, advance_remind_minutes, is_completed, '
      'created_at) VALUES (1, ?, ?, ?, ?, 0, ?)',
      [
        '交体检报告',
        DateTime.utc(2026, 9, 20).millisecondsSinceEpoch ~/ 1000,
        14 * 60 + 30,
        15,
        DateTime.utc(2026, 9, 1).millisecondsSinceEpoch ~/ 1000,
      ],
    );
    raw.execute('PRAGMA user_version = 6');
  });

  tearDown(() => raw.dispose());

  test('v6 → v7：补出 alarm_enabled，老待办保留且默认「关」', () async {
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final rows = await db.select(db.scheduleEvents).get();
    expect(rows, hasLength(1), reason: '老数据要原样留着');

    final e = rows.single;
    expect(e.title, '交体检报告');
    expect(e.timeMinute, 14 * 60 + 30);
    expect(e.advanceRemindMinutes, 15);
    // 默认值就是旧行为：只弹通知，不响闹钟。
    expect(e.alarmEnabled, isFalse);
  });
}
