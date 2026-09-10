import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v5 时期的表结构（迁移前的形态）。
const _v5Schema = <String>[
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
  CREATE TABLE shift_type_rows (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    schedule_id INTEGER NOT NULL,
    "order" INTEGER NOT NULL,
    name TEXT NOT NULL,
    start_minute INTEGER,
    end_minute INTEGER,
    is_rest INTEGER NOT NULL DEFAULT 0,
    color INTEGER NOT NULL DEFAULT 4284186623,
    alarm_enabled INTEGER NOT NULL DEFAULT 0,
    alarm_minute INTEGER
  )
  ''',
  '''
  CREATE TABLE schedule_events (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    date INTEGER NOT NULL,
    time_minute INTEGER,
    advance_remind_minutes INTEGER,
    is_completed INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE custom_alarms (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    hour INTEGER NOT NULL,
    minute INTEGER NOT NULL,
    repeat_type INTEGER NOT NULL DEFAULT 1,
    once_date INTEGER,
    weekdays INTEGER NOT NULL DEFAULT 0,
    enabled INTEGER NOT NULL DEFAULT 1
  )
  ''',
  '''
  CREATE TABLE shift_alarm_overrides (
    day INTEGER NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (day)
  )
  ''',
];

class _LegacyRow {
  const _LegacyRow(this.name, this.start, this.end, this.isRest, this.color,
      this.alarmOn, this.alarm);
  final String name;
  final int? start;
  final int? end;
  final int isRest;
  final int color;
  final int alarmOn;
  final int? alarm;
}

/// 手抄的 12 天周期：白×4 休×2 上夜×4 下夜×1 休×1。
/// 四行「白班」字段完全相同 —— 迁移后应合并成 1 个班次定义。
const _legacyTwelveDays = <_LegacyRow>[
  _LegacyRow('白班', 510, 1230, 0, 0xFF4C8DFF, 1, 420),
  _LegacyRow('白班', 510, 1230, 0, 0xFF4C8DFF, 1, 420),
  _LegacyRow('白班', 510, 1230, 0, 0xFF4C8DFF, 1, 420),
  _LegacyRow('白班', 510, 1230, 0, 0xFF4C8DFF, 1, 420),
  _LegacyRow('休班', null, null, 1, 0xFFFF9F0A, 0, null),
  _LegacyRow('休班', null, null, 1, 0xFFFF9F0A, 0, null),
  _LegacyRow('上夜班', 1230, 510, 0, 0xFF7A5CFF, 1, 1170),
  _LegacyRow('上夜班', 1230, 510, 0, 0xFF7A5CFF, 1, 1170),
  _LegacyRow('上夜班', 1230, 510, 0, 0xFF7A5CFF, 1, 1170),
  _LegacyRow('上夜班', 1230, 510, 0, 0xFF7A5CFF, 1, 1170),
  _LegacyRow('下夜班', null, null, 1, 0xFF9AA0B4, 0, null),
  _LegacyRow('休班', null, null, 1, 0xFFFF9F0A, 0, null),
];

// DateTime.utc 没有 const 构造，brief 里的 `const` 是笔误，值保持不变。
final _anchor = DateTime.utc(2025, 1, 6);

ShiftClass _toClass(_LegacyRow r) => ShiftClass(
      name: r.name,
      startMinute: r.start,
      endMinute: r.end,
      isRest: r.isRest != 0,
      color: r.color,
      alarmEnabled: r.alarmOn != 0,
      alarmMinute: r.alarm,
    );

void main() {
  late sqlite3.Database raw;

  setUp(() {
    raw = sqlite3.sqlite3.openInMemory();
    for (final ddl in _v5Schema) {
      raw.execute(ddl);
    }
    raw.execute(
      'INSERT INTO shift_schedule_rows '
      '(id, name, anchor_date, is_current, team_count, team_names, '
      'our_team_index, team_offsets) VALUES (1, ?, ?, 1, 1, ?, 0, ?)',
      [
        'B班',
        _anchor.millisecondsSinceEpoch ~/ 1000,
        '我',
        '0',
      ],
    );
    for (var i = 0; i < _legacyTwelveDays.length; i++) {
      final r = _legacyTwelveDays[i];
      raw.execute(
        'INSERT INTO shift_type_rows '
        '(schedule_id, "order", name, start_minute, end_minute, is_rest, '
        'color, alarm_enabled, alarm_minute) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?)',
        [i, r.name, r.start, r.end, r.isRest, r.color, r.alarmOn, r.alarm],
      );
    }
    raw.execute('PRAGMA user_version = 5');
  });

  tearDown(() => raw.dispose());

  test('v5 → v6 迁移后逐日等价，且重复班次合并成一个定义', () async {
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final migrated = await AppRepository(db).getScheduleDomain(1);
    expect(migrated, isNotNull);

    // 基准日原样保留
    expect(migrated!.anchorDate.year, 2025);
    expect(migrated.anchorDate.month, 1);
    expect(migrated.anchorDate.day, 6);

    // 12 天周期 + 4 个定义（白班 / 休班 / 上夜班 / 下夜班）
    expect(migrated.cycleLength, 12);
    expect(migrated.classes.map((c) => c.name).toList(),
        ['白班', '休班', '上夜班', '下夜班']);
    expect(migrated.classes.where((c) => c.name == '白班').length, 1);

    // 迁移前的等价模型：老表就是「每天一行」
    final before = ShiftSchedule(
      name: 'B班',
      anchorDate: _anchor,
      classes: _legacyTwelveDays.map(_toClass).toList(),
      cycle: List.generate(_legacyTwelveDays.length, (i) => i),
      teamCount: 1,
      teamNames: const ['我'],
      ourTeamIndex: 0,
      teamOffsets: const [0],
    );

    for (var d = -30; d <= 60; d++) {
      final date = _anchor.add(Duration(days: d));
      final a = before.shiftOn(date);
      final b = migrated.shiftOn(date);
      final why = '第 $d 天不一致';
      expect(b?.name, a?.name, reason: why);
      expect(b?.startMinute, a?.startMinute, reason: why);
      expect(b?.endMinute, a?.endMinute, reason: why);
      expect(b?.isRest, a?.isRest, reason: why);
      expect(b?.color, a?.color, reason: why);
      expect(b?.alarmEnabled, a?.alarmEnabled, reason: why);
      expect(b?.alarmMinute, a?.alarmMinute, reason: why);
    }
  });

  test('迁移后旧的 shift_type_rows 表已删除', () async {
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await AppRepository(db).getScheduleDomain(1); // 触发迁移
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='shift_type_rows'")
        .get();
    expect(rows, isEmpty);
  });

  test('空方案（跟随法定节假日）迁移后仍为空', () async {
    raw.execute(
      'INSERT INTO shift_schedule_rows '
      '(id, name, anchor_date, is_current, team_count, team_names, '
      'our_team_index, team_offsets) VALUES (2, ?, ?, 0, 1, ?, 0, ?)',
      ['法定节假日', _anchor.millisecondsSinceEpoch ~/ 1000, '我', '0'],
    );
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);
    final blank = await AppRepository(db).getScheduleDomain(2);
    expect(blank, isNotNull);
    expect(blank!.isBlank, isTrue);
    expect(blank.shiftOn(_anchor), isNull);
  });
}
