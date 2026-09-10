// app/test/save_schedule_current_test.dart
//
// 「新增排班」这条被文档推荐的路径不能产生两行 isCurrent。
//
// 我的 → 排班管理 → 新增排班 走的是
// createScheduleFromTemplatePicker(makeCurrent: false)
// （schedule_management_screen.dart 的 _addSchedule）。saveSchedule 若把
// isCurrent 写死成 true，就会跳过「清掉其他当前行」的分支 —— 新行与原有
// 当前行同时为 true，watchActiveSchedule() 里的 watchSingleOrNull() 会
// 往流里推一个错误，activeScheduleProvider 报错，日历直接白屏。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _classes = [
  ShiftClass(name: '白班', abbr: '白', startMinute: 8 * 60, endMinute: 20 * 60),
  ShiftClass(name: '休班', abbr: '休', isRest: true),
];

void main() {
  late sqlite3.Database raw;
  late AppDatabase db;
  late AppRepository repo;

  setUp(() {
    raw = sqlite3.sqlite3.openInMemory();
    db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    repo = AppRepository(db);
  });

  tearDown(() => db.close());

  Future<List<ShiftScheduleRow>> currentRows() {
    return (db.select(db.shiftScheduleRows)
          ..where((s) => s.isCurrent.equals(true)))
        .get();
  }

  Future<int> saveB({required bool makeCurrent}) {
    return repo.saveSchedule(
      name: 'B',
      anchorDate: DateTime.utc(2025, 6, 1),
      classes: _classes,
      cycle: const [0, 1],
      makeCurrent: makeCurrent,
    );
  }

  test('makeCurrent:false 新建方案后仍恰好一行 isCurrent，且流不报错、仍指向 A',
      () async {
    await repo.ensureSeeded();
    final a = (await repo.listSchedules()).single;
    expect(a.isCurrent, isTrue, reason: '种子方案应当是当前方案');

    await saveB(makeCurrent: false);

    // 直接查表：恰好一行当前。
    expect(await currentRows(), hasLength(1),
        reason: '两行 isCurrent = true 会让 watchSingleOrNull 往流里推错');

    // 真正的用户可见症状：watchActiveSchedule 不抛错，且仍指向原来的 A。
    final active = await db.watchActiveSchedule().first;
    expect(active, isNotNull);
    expect(active!.schedule.id, a.id,
        reason: 'makeCurrent:false 不该把新方案 B 变成当前方案');
  });

  test('makeCurrent:true 新建方案后仍恰好一行 isCurrent，当前行切到 B', () async {
    await repo.ensureSeeded();
    final a = (await repo.listSchedules()).single;

    final bId = await saveB(makeCurrent: true);

    final current = await currentRows();
    expect(current, hasLength(1), reason: '切当前方案也必须保持唯一');
    expect(current.single.id, bId);
    expect(current.single.id, isNot(a.id));

    final active = await db.watchActiveSchedule().first;
    expect(active!.schedule.id, bId);
  });
}
