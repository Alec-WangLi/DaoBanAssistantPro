// app/test/migration_v13_to_v14_test.dart
//
// v13 → v14：按月排班。**纯新增** —— 一张段表（`schedule_month_segment_rows`）、
// 方案表两列（`monthly` / `team_seg_offsets`）、模板表三列（`monthly` /
// `month_segments` / `team_seg_offsets`），既有数据一行不碰。
//
// 两条最要紧的断言：
//  ① **老库逐项不变** —— 没有任何一套既有方案会变成按月模式（`monthly` 的默认值
//     是 0，从 v13 及更早升上来时恒为 0）。
//  ② **新列带着默认值到位** —— `monthly = 0`、两个偏移串 = ''，否则读回领域层会
//     在解析空串时走到别的分支。
//
// ⚠️ 迁移分支按**倒序**跑，`from < 13` 那段会 `TableMigration(shiftScheduleRows)`
// 重建方案表。`from < 14` 必须排在它**之前**（先加列，重建时按列名拷数据自然带
// 得过去）。这条由本文件（从 v13 升）与 `migration_v10_to_v14_test.dart`（从 v10
// 升，盖住「新列加完之后后面还有好几段重建在跑」那条组合路径）一起兜住。
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v13 形态的建表 DDL（与 v13 的生成代码逐列一致）。
///
/// 与 v11 那份的差别只有一样：v13 已经把 `effective_from` / `effective_to` 两列
/// 搬进了段表，所以方案表又回到了 v11 的形状。
const _v13Schema = [
  '''
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
''',
  '''
CREATE TABLE schedule_span_rows (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  schedule_id INTEGER NOT NULL,
  start_date INTEGER,
  end_date INTEGER
)
''',
  '''
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
  alarm_enabled INTEGER NOT NULL DEFAULT 0
)
''',
  '''
CREATE TABLE shift_cycle_rows (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  schedule_id INTEGER NOT NULL,
  "order" INTEGER NOT NULL,
  class_id INTEGER NOT NULL
)
''',
  '''
CREATE TABLE shift_class_alarms (
  class_id INTEGER NOT NULL,
  "order" INTEGER NOT NULL,
  minute INTEGER NOT NULL,
  label TEXT,
  PRIMARY KEY (class_id, "order")
)
''',
  '''
CREATE TABLE shift_day_overrides (
  schedule_id INTEGER NOT NULL,
  day INTEGER NOT NULL,
  class_id INTEGER NOT NULL,
  PRIMARY KEY (schedule_id, day)
)
''',
  '''
CREATE TABLE custom_templates (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  classes TEXT NOT NULL,
  cycle TEXT NOT NULL,
  team_count INTEGER NOT NULL,
  team_offsets TEXT NOT NULL,
  created_at INTEGER NOT NULL
)
''',
  // v11 起的重复待办表（本节迁移不碰它，但 v14→v15 会加两列删一列；迁移分支
  // 倒序跑，从 v13 升上来时那一段同样会执行 —— fixture 必须补上真实老库里有的表）。
  '''
CREATE TABLE recurring_series_rows (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  time_minute INTEGER NULL,
  advance_remind_minutes INTEGER NULL,
  alarm_enabled INTEGER NOT NULL DEFAULT 0,
  repeat_type INTEGER NOT NULL DEFAULT 0,
  weekdays INTEGER NOT NULL DEFAULT 0,
  month_day INTEGER NOT NULL DEFAULT 1,
  start_date INTEGER NOT NULL,
  skip_through INTEGER NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
)
''',
];

int _sec(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

/// 开一个 v13 库，种一套「四班两倒」形态的方案（班次 + 周期 + 一条闹钟 +
/// 一条按天覆盖 + 一段时段 + 一条我的模板）。
Future<AppDatabase> _openV13() async {
  final raw = sqlite3.sqlite3.openInMemory();
  for (final ddl in _v13Schema) {
    raw.execute(ddl);
  }

  raw.execute(
    'INSERT INTO shift_schedule_rows '
    '(id, name, anchor_date, is_current, team_count, team_names, '
    'our_team_index, team_offsets) VALUES (1, ?, ?, 1, 4, ?, 1, ?)',
    [
      '炼油三部 · 四班两倒',
      _sec(DateTime.utc(2026, 1, 6)),
      '一班,二班,三班,四班',
      '0,1,2,3',
    ],
  );
  raw.execute(
    'INSERT INTO shift_schedule_rows '
    '(id, name, anchor_date, is_current, team_count, team_names, '
    'our_team_index, team_offsets) VALUES (2, ?, ?, 0, 3, ?, 0, ?)',
    ['备选 · 按月', _sec(DateTime.utc(2025, 12, 1)), '甲班,乙班,丙班', '0,2,4'],
  );

  raw.execute(
    'INSERT INTO shift_class_rows '
    '(id, schedule_id, "order", name, abbr, start_minute, end_minute, '
    'is_rest, color, alarm_enabled) VALUES (1, 1, 0, ?, ?, 510, 1230, 0, ?, 1)',
    ['白班', '白', 0xFF4C8DFF],
  );
  raw.execute(
    'INSERT INTO shift_class_rows '
    '(id, schedule_id, "order", name, abbr, start_minute, end_minute, '
    'is_rest, color, alarm_enabled) VALUES (2, 1, 1, ?, ?, 1230, 510, 0, ?, 1)',
    ['夜班', '夜', 0xFF7A5CFF],
  );
  raw.execute(
    'INSERT INTO shift_class_rows '
    '(id, schedule_id, "order", name, abbr, start_minute, end_minute, '
    'is_rest, color, alarm_enabled) VALUES (3, 1, 2, ?, ?, NULL, NULL, 1, ?, 0)',
    ['休班', '休', 0xFF9AA0B4],
  );

  raw.execute('INSERT INTO shift_cycle_rows (schedule_id, "order", class_id) '
      'VALUES (1, 0, 1), (1, 1, 2), (1, 2, 3), (1, 3, 3)');

  raw.execute(
      'INSERT INTO shift_class_alarms (class_id, "order", minute, label) '
      'VALUES (1, 0, 420, ?), (1, 1, 690, ?)',
      ['起床', '午休']);

  raw.execute(
      'INSERT INTO shift_day_overrides (schedule_id, day, class_id) '
      'VALUES (1, ?, 3)',
      [dayNumber(DateTime.utc(2026, 3, 10))]);

  raw.execute(
      'INSERT INTO schedule_span_rows (id, schedule_id, start_date, end_date) '
      'VALUES (1, 2, ?, NULL)',
      [_sec(DateTime.utc(2026, 9, 1))]);

  raw.execute(
    'INSERT INTO custom_templates '
    '(id, name, classes, cycle, team_count, team_offsets, created_at) '
    'VALUES (1, ?, ?, ?, 4, ?, ?)',
    ['我的四班两倒', '[]', '0,1,2,3', '0,1,2,3', _sec(DateTime.utc(2026, 2, 1))],
  );

  raw.execute('PRAGMA user_version = 13');
  return AppDatabase.forTesting(NativeDatabase.opened(raw));
}

void main() {
  test('v13 → v14：老数据逐项不变，新列带默认值，段表可写可读', () async {
    final db = await _openV13();
    addTearDown(db.close);

    // ① 方案行原样（含那两列新列还没被碰过的证据：值仍是库里的原值）
    final rows = await (db.select(db.shiftScheduleRows)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    expect(rows.length, 2);
    expect(rows[0].name, '炼油三部 · 四班两倒');
    expect(rows[0].isCurrent, isTrue);
    expect(rows[0].ourTeamIndex, 1);
    expect(rows[0].teamOffsets, '0,1,2,3');
    expect(rows[1].name, '备选 · 按月');
    expect(rows[1].isCurrent, isFalse);
    expect(rows[1].teamCount, 3);
    // 比日期一律走 dayNumber：drift 读回来是**本地** DateTime。
    expect(dayNumber(rows[0].anchorDate), dayNumber(DateTime(2026, 1, 6)));

    // ② 新列带着默认值 —— 老库**一套都不该变成按月模式**
    expect(rows[0].monthly, isFalse);
    expect(rows[0].teamSegOffsets, '');
    expect(rows[1].monthly, isFalse);
    expect(rows[1].teamSegOffsets, '');

    // ③ 班次定义 / 周期 / 闹钟 / 按天覆盖 逐项不变
    final classes = await (db.select(db.shiftClassRows)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    expect(classes.map((c) => c.name), ['白班', '夜班', '休班']);
    expect(classes.map((c) => c.abbr), ['白', '夜', '休']);
    expect(classes[2].isRest, isTrue);
    expect(classes[0].alarmEnabled, isTrue);

    final cycle = await (db.select(db.shiftCycleRows)
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    expect(cycle.map((r) => r.classId), [1, 2, 3, 3]);

    final alarms = await (db.select(db.shiftClassAlarms)
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    expect(alarms.map((a) => a.minute), [420, 690]);
    expect(alarms.map((a) => a.label), ['起床', '午休']);

    final overrides = await db.select(db.shiftDayOverrides).get();
    expect(overrides.length, 1);
    expect(overrides.single.day, dayNumber(DateTime.utc(2026, 3, 10)));
    expect(overrides.single.classId, 3);

    // ④ 时段与模板原样（模板那三列也要有默认值）
    final spans = await db.select(db.scheduleSpanRows).get();
    expect(spans.length, 1);
    expect(spans.single.scheduleId, 2);
    expect(spans.single.endDate, isNull);

    final templates = await db.select(db.customTemplates).get();
    expect(templates.single.name, '我的四班两倒');
    expect(templates.single.cycle, '0,1,2,3');
    expect(templates.single.monthly, isFalse);
    expect(templates.single.monthSegments, '');
    expect(templates.single.teamSegOffsets, '');

    // ⑤ 段表建出来了，而且**是空的**（v13 从来没有过按月切法）
    expect(await db.select(db.scheduleMonthSegmentRows).get(), isEmpty);

    // ⑥ 段表现在可写可读
    final segId = await db.into(db.scheduleMonthSegmentRows).insert(
          ScheduleMonthSegmentRowsCompanion.insert(
            scheduleId: 2,
            order: 0,
            startDay: 11,
            classId: 2,
          ),
        );
    final seg = await db.select(db.scheduleMonthSegmentRows).getSingle();
    expect(seg.id, segId);
    expect(seg.scheduleId, 2);
    expect(seg.order, 0);
    expect(seg.startDay, 11);
    expect(seg.classId, 2);

    // ⑦ 新列也可写
    await (db.update(db.shiftScheduleRows)..where((t) => t.id.equals(2)))
        .write(const ShiftScheduleRowsCompanion(
      monthly: Value(true),
      teamSegOffsets: Value('0,1,2'),
    ));
    final updated = await (db.select(db.shiftScheduleRows)
          ..where((t) => t.id.equals(2)))
        .getSingle();
    expect(updated.monthly, isTrue);
    expect(updated.teamSegOffsets, '0,1,2');
  });
}
