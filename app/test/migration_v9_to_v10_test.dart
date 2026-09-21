// app/test/migration_v9_to_v10_test.dart
//
// v9 → v10：班次闹钟从 `shift_class_rows` 上的一个钟点（`alarm_minute`）搬进新表
// `shift_class_alarms`，并把那一列**删掉**。
//
// 这条迁移比 v8→v9 危险：`alterTable` 会**重建 shift_class_rows**，而
// `shift_cycle_rows.class_id` 与 `shift_day_overrides.class_id` 都指着它的 id ——
// id 一变，周期与按天覆盖集体指飞（不报错，只是那天变成别的班）。所以 fixture
// 要抄全套表，并逐条断言引用还指得对。
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v9 的表（DDL 与 v9 生成代码逐列一致）。
const _v9Tables = [
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
];

int _day(int y, int m, int d) => dayNumber(DateTime.utc(y, m, d));

void main() {
  late sqlite3.Database raw;

  setUp(() {
    raw = sqlite3.sqlite3.openInMemory();
    for (final ddl in _v9Tables) {
      raw.execute(ddl);
    }
    raw.execute(
      'INSERT INTO shift_schedule_rows '
      '(id, name, anchor_date, is_current, team_count, team_names, '
      'our_team_index, team_offsets) VALUES (1, ?, ?, 1, 1, ?, 0, ?)',
      [
        '我的班',
        DateTime.utc(2026, 9, 21).millisecondsSinceEpoch ~/ 1000,
        '我',
        '0',
      ],
    );
    // 白班：开关开着 + 07:00（要搬进新表）
    raw.execute(
      'INSERT INTO shift_class_rows (id, schedule_id, "order", name, abbr, '
      'start_minute, end_minute, is_rest, color, alarm_enabled, alarm_minute) '
      'VALUES (11, 1, 0, ?, ?, ?, ?, 0, 4284186623, 1, ?)',
      ['白班', '白', 8 * 60, 20 * 60, 7 * 60],
    );
    // 夜班：开关**关着**但时间还在（19:30）—— 用户手滑关过开关的情形，
    // 时间必须一起搬过去，不然升级一次配置就没了
    raw.execute(
      'INSERT INTO shift_class_rows (id, schedule_id, "order", name, abbr, '
      'start_minute, end_minute, is_rest, color, alarm_enabled, alarm_minute) '
      'VALUES (12, 1, 1, ?, ?, ?, ?, 0, 4284186623, 0, ?)',
      ['夜班', '夜', 20 * 60, 8 * 60, 19 * 60 + 30],
    );
    // 休班：从来没设过闹钟
    raw.execute(
      'INSERT INTO shift_class_rows (id, schedule_id, "order", name, abbr, '
      'start_minute, end_minute, is_rest, color, alarm_enabled, alarm_minute) '
      'VALUES (13, 1, 2, ?, ?, NULL, NULL, 1, 4284186623, 0, NULL)',
      ['休班', '休'],
    );
    raw.execute('INSERT INTO shift_cycle_rows (schedule_id, "order", class_id) '
        'VALUES (1, 0, 11), (1, 1, 12), (1, 2, 13)');
    // 按天覆盖：把某天换成休班（classId 13）—— 迁移后必须还指着 13
    raw.execute(
      'INSERT INTO shift_day_overrides (schedule_id, day, class_id) '
      'VALUES (1, ?, 13)',
      [_day(2026, 9, 22)],
    );
    raw.execute('PRAGMA user_version = 9');
  });

  tearDown(() => raw.dispose());

  test('v9 → v10：闹钟搬进新表、老排班的周期与按天覆盖仍指得对', () async {
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // 1) 闹钟行搬过来了，连「开关关着但有时间」那条一起
    final rows = await (db.select(db.shiftClassAlarms)
          ..orderBy([(t) => OrderingTerm.asc(t.classId)]))
        .get();
    expect(rows, hasLength(2));
    expect(rows[0].classId, 11);
    expect(rows[0].order, 0);
    expect(rows[0].minute, 7 * 60);
    expect(rows[0].label, isNull);
    expect(rows[1].classId, 12);
    expect(rows[1].minute, 19 * 60 + 30,
        reason: '开关关着但有时间的行也必须搬 —— 只挑 alarm_enabled = 1 就等于把用户配好的时间吞了');

    // 2) 总开关没被动过
    final classes = await (db.select(db.shiftClassRows)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    expect(classes.map((c) => c.id), [11, 12, 13]);
    expect(classes[1].alarmEnabled, isFalse, reason: '关着的开关不能因为迁移被打开');

    // 3) 周期与按天覆盖仍指向同一批 id
    final cycleIds =
        (await db.select(db.shiftCycleRows).get()).map((r) => r.classId).toList();
    expect(cycleIds, [11, 12, 13], reason: 'alterTable 重建表后 classId 不能变');
    final ov = await db.select(db.shiftDayOverrides).get();
    expect(ov.single.classId, 13, reason: '按天覆盖还指着休班那条');

    // 4) 走一遍领域装配：班次带着闹钟出来，覆盖换成 classes 下标
    final active = await db.loadActiveScheduleForTesting();
    final s = active!.toDomain();
    expect(s.classes[0].alarms.single.minute, 7 * 60);
    expect(s.classes[1].alarms.single.minute, 19 * 60 + 30);
    expect(s.classes[1].alarmEnabled, isFalse);
    expect(s.classes[2].alarms, isEmpty);
    expect(s.dayOverrides[_day(2026, 9, 22)], 2, reason: '覆盖装配成 classes 下标');

    // 5) 老列真的没了（没留死列）
    final cols = raw
        .select('PRAGMA table_info(shift_class_rows)')
        .map((r) => r['name'] as String)
        .toList();
    expect(cols, isNot(contains('alarm_minute')));
  });
}
