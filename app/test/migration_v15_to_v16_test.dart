// app/test/migration_v15_to_v16_test.dart
//
// v15 → v16：班次加 `is_night`（默认 0）、新增 `shift_day_extras` 表。
//
// 两条要紧的断言：旧班的其余字段原样、`is_night` 一律 0（不能把老库的夜班
// 猜成 true —— 名字推断是错的，24 小时值班也跨午夜）；新表真的能写。
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/day_extra.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v15 形态的 `shift_class_rows` DDL（与 v15 的生成代码逐列一致）。
///
/// `from < 16` 只碰这张表，所以 fixture 只建它 —— 迁移分支按倒序跑，from=15
/// 时其余分支不执行。
const _v15ClassSchema = '''
CREATE TABLE shift_class_rows (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  schedule_id INTEGER NOT NULL,
  "order" INTEGER NOT NULL,
  name TEXT NOT NULL,
  abbr TEXT NULL,
  start_minute INTEGER NULL,
  end_minute INTEGER NULL,
  is_rest INTEGER NOT NULL DEFAULT 0,
  color INTEGER NOT NULL DEFAULT 4284186623,
  alarm_enabled INTEGER NOT NULL DEFAULT 0
)
''';

Future<AppDatabase> _openV15() async {
  final raw = sqlite3.sqlite3.openInMemory();
  raw.execute(_v15ClassSchema);
  raw.execute(
    'INSERT INTO shift_class_rows '
    '(id, schedule_id, "order", name, abbr, start_minute, end_minute, '
    'is_rest, color, alarm_enabled) '
    'VALUES (1, 7, 0, ?, ?, 1230, 510, 0, ?, 1)',
    ['上夜班', '夜', 0xFF7A5CFF],
  );
  raw.execute(
    'INSERT INTO shift_class_rows '
    '(id, schedule_id, "order", name, abbr, start_minute, end_minute, '
    'is_rest, color, alarm_enabled) '
    'VALUES (2, 7, 1, ?, ?, NULL, NULL, 1, ?, 0)',
    ['大休', '休', 0xFF5A5F73],
  );
  raw.execute('PRAGMA user_version = 15');
  return AppDatabase.forTesting(NativeDatabase.opened(raw));
}

void main() {
  test('v15 → v16：is_night 默认 0、旧字段原样、新表可写', () async {
    final db = await _openV15();
    addTearDown(db.close);

    final rows = await (db.select(db.shiftClassRows)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    expect(rows.length, 2);

    expect(rows[0].isNight, isFalse, reason: '老库不许猜夜班');
    expect(rows[0].name, '上夜班');
    expect(rows[0].startMinute, 1230);
    expect(rows[0].endMinute, 510);
    expect(rows[0].alarmEnabled, isTrue);
    expect(rows[1].isRest, isTrue);
    expect(rows[1].isNight, isFalse);

    final repo = AppRepository(db);
    final day = dayNumber(DateTime.utc(2026, 11, 12));
    await repo.setDayExtra(day, DayExtraKind.leave, 240);
    expect((await repo.listDayExtras())[day]!.leaveMinutes, 240);
  });
}
