// app/test/migration_v8_to_v9_test.dart
//
// v8 → v9 只**新增一张表**：`custom_templates`（「我的模板」）。
// 这条迁移不碰任何既有表的列，所以 fixture 只需要一张 `shift_schedule_rows`
// 来验「老数据还在」，不必像 v5→v6 那条那样抄全套。
//
// 要验三件事：新表建出来了、老排班原样保留、新表真的能写能读（含编解码往返）。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/schedule_template.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v8 时期的 `shift_schedule_rows`（v9 没有改动它）。
const _v8ScheduleTable = '''
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

ShiftSchedule _schedule() => ShiftSchedule(
      name: '我的班',
      anchorDate: DateTime.utc(2026, 9, 21),
      classes: const [
        ShiftClass(
            name: '白班',
            abbr: '白',
            startMinute: 8 * 60 + 30,
            endMinute: 20 * 60 + 30,
            color: 0xFF4C8DFF,
            alarmEnabled: true,
            alarmMinute: 7 * 60),
        ShiftClass(name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4),
      ],
      cycle: const [0, 1],
      teamCount: 2,
      teamNames: const ['一班', '二班'],
      teamOffsets: const [0, 1],
    );

void main() {
  late sqlite3.Database raw;

  setUp(() {
    raw = sqlite3.sqlite3.openInMemory();
    raw.execute(_v8ScheduleTable);
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
    raw.execute('PRAGMA user_version = 8');
  });

  tearDown(() => raw.dispose());

  test('v8 → v9：建出 custom_templates，老排班原样保留', () async {
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final schedules = await db.select(db.shiftScheduleRows).get();
    expect(schedules, hasLength(1), reason: '老排班要原样留着');
    expect(schedules.single.name, '四班两倒');
    expect(schedules.single.teamOffsets, '0,1,2,3');

    // 新表建出来了，而且是空的
    expect(await db.select(db.customTemplates).get(), isEmpty);

    // 而且能写能读：走仓储存一份模板再读回来，编解码一并过一遍
    final repo = AppRepository(db);
    final saved = ScheduleTemplate.fromSchedule(_schedule(), name: '零点班那套');
    await repo.saveTemplate(saved);

    final back = await repo.listTemplates();
    expect(back, hasLength(1));
    expect(back.single.name, '零点班那套');
    expect(back.single.cycle, [0, 1]);
    expect(back.single.teamCount, 2);
    expect(back.single.teamOffsets, [0, 1]);
    expect(back.single.classes.map((c) => c.name), ['白班', '休班']);
    expect(back.single.classes.first.alarmMinute, 7 * 60);
  });
}
