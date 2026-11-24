// app/test/migration_v17_to_v18_test.dart
//
// v17 → v18：新增 `shift_day_notes`（按天调班备注）。
//
// 纯新增一张表，一行既有数据都不碰 —— 要紧的是它**真的建出来了**、能写能改能删，
// 而不是「迁移没抛异常」就算过。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

Future<AppDatabase> _openV17() async {
  final raw = sqlite3.sqlite3.openInMemory();
  raw.execute('PRAGMA user_version = 17');
  return AppDatabase.forTesting(NativeDatabase.opened(raw));
}

void main() {
  test('v17 → v18：调班备注表建得出来、能写能改、空白等于清除', () async {
    final db = await _openV17();
    addTearDown(db.close);

    expect(db.schemaVersion, 18);
    final repo = AppRepository(db);
    final day = dayNumber(DateTime.utc(2026, 11, 28));

    expect(await repo.listDayNotes(), isEmpty, reason: '老库不该凭空有备注');

    await repo.setDayNote(day, '跟张三换了班');
    expect((await repo.listDayNotes())[day], '跟张三换了班');

    // 写入要 trim（输入框来的原文可能带首尾空白）。
    await repo.setDayNote(day, '  改了口径  ');
    expect((await repo.listDayNotes())[day], '改了口径');

    // 同一天再写是覆盖，不是两行。
    await repo.setDayNote(day, '第二次');
    expect((await repo.listDayNotes()).length, 1);

    // 空白（含只有空格的）等于清除。
    await repo.setDayNote(day, '   ');
    expect(await repo.listDayNotes(), isEmpty);
  });
}
