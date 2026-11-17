// app/test/migration_v16_to_v17_test.dart
//
// v16 → v17：`shift_day_extras` 加 `leave_kind` / `note` 两列（都可空）。
//
// 要紧的断言：老记录原样读得出来（类型为空、统计归「未分类」），新列真的能写
// 且能覆盖回 null —— 不是「addColumn 没抛异常」就算过。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/day_extra.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v16 形态的 `shift_day_extras` DDL（v0.13.14 那一版，没有类型与备注）。
const _v16ExtrasSchema = '''
CREATE TABLE shift_day_extras (
  day INTEGER NOT NULL,
  kind INTEGER NOT NULL,
  minutes INTEGER NOT NULL,
  PRIMARY KEY (day, kind)
)
''';

Future<AppDatabase> _openV16() async {
  final raw = sqlite3.sqlite3.openInMemory();
  raw.execute(_v16ExtrasSchema);
  raw.execute(
    'INSERT INTO shift_day_extras (day, kind, minutes) VALUES (?, ?, ?)',
    [dayNumber(DateTime.utc(2026, 11, 12)), DayExtraKind.leave.index, 240],
  );
  raw.execute(
    'INSERT INTO shift_day_extras (day, kind, minutes) VALUES (?, ?, ?)',
    [dayNumber(DateTime.utc(2026, 11, 12)), DayExtraKind.overtime.index, 120],
  );
  raw.execute('PRAGMA user_version = 16');
  return AppDatabase.forTesting(NativeDatabase.opened(raw));
}

void main() {
  test('v16 → v17：旧记录类型为空、备注可写、可再清回 null', () async {
    final db = await _openV16();
    addTearDown(db.close);

    final repo = AppRepository(db);
    final day = dayNumber(DateTime.utc(2026, 11, 12));

    final old = (await repo.listDayExtras())[day]!;
    expect(old.leaveMinutes, 240);
    expect(old.overtimeMinutes, 120);
    expect(old.leaveKind, isNull, reason: '老库不许猜请假类型');
    expect(old.leaveNote, isNull);
    expect(old.overtimeNote, isNull);

    await repo.setDayExtra(
      day,
      DayExtraKind.leave,
      240,
      leaveKind: 'annual',
      note: '年假一天',
    );
    await repo.setDayExtra(
      day,
      DayExtraKind.overtime,
      120,
      note: '替班两小时',
    );
    final written = (await repo.listDayExtras())[day]!;
    expect(written.leaveKind, 'annual');
    expect(written.leaveNote, '年假一天');
    expect(written.overtimeNote, '替班两小时');

    // 显式传 null 要真的把旧值清掉（insertOnConflictUpdate 是整行覆盖）。
    await repo.setDayExtra(day, DayExtraKind.leave, 240);
    final cleared = (await repo.listDayExtras())[day]!;
    expect(cleared.leaveKind, isNull);
    expect(cleared.leaveNote, isNull);
    expect(cleared.overtimeNote, '替班两小时');
  });

  test('v16 → v17：自定义类型键读得回来', () async {
    final db = await _openV16();
    addTearDown(db.close);

    final repo = AppRepository(db);
    final day = dayNumber(DateTime.utc(2026, 11, 13));
    await repo.setDayExtra(
      day,
      DayExtraKind.leave,
      480,
      leaveKind: customLeaveKindKey('育儿假'),
      note: '孩子发烧',
    );

    final row = (await repo.listDayExtras())[day]!;
    expect(customLeaveKindName(row.leaveKind), '育儿假');
    expect(isBuiltInLeaveKind(row.leaveKind), isFalse);
    expect(row.leaveNote, '孩子发烧');
  });
}
