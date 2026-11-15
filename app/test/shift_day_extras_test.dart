// app/test/shift_day_extras_test.dart
//
// 日级请假 / 加班表：写入 / 覆盖 / 清除、重置连带清空、表变化能推给 watch。
//
// 这张表是全局的（只有 `day` 一个键），与按天改班覆盖不同 —— 所以这里不建排班
// 也能测；`clearAll` 会顺带重建种子，断言只数 extras 表本身。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/day_extra.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

void main() {
  late AppDatabase db;
  late AppRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppRepository(db);
  });

  tearDown(() => db.close());

  final day = dayNumber(DateTime.utc(2026, 11, 12));

  test('写入 / 覆盖 / 清除，请假与加班可以并存', () async {
    await repo.setDayExtra(day, DayExtraKind.leave, 240);
    expect((await repo.listDayExtras())[day]!.leaveMinutes, 240);

    // 同一天再写一次是更新，不是插第二条。
    await repo.setDayExtra(day, DayExtraKind.leave, 480);
    expect((await repo.listDayExtras())[day]!.leaveMinutes, 480);

    await repo.setDayExtra(day, DayExtraKind.overtime, 120);
    final both = (await repo.listDayExtras())[day]!;
    expect(both.leaveMinutes, 480);
    expect(both.overtimeMinutes, 120);

    await repo.clearDayExtra(day, DayExtraKind.leave);
    final after = (await repo.listDayExtras())[day]!;
    expect(after.leaveMinutes, 0);
    expect(after.overtimeMinutes, 120);
  });

  test('minutes <= 0 等于清除', () async {
    await repo.setDayExtra(day, DayExtraKind.leave, 240);
    await repo.setDayExtra(day, DayExtraKind.leave, 0);
    expect((await repo.listDayExtras())[day], isNull);
  });

  test('clearAll 清掉 extras', () async {
    await repo.setDayExtra(day, DayExtraKind.leave, 240);
    await repo.clearAll();
    expect((await repo.listDayExtras())[day], isNull);
  });

  test('表格变化会推给 watch', () async {
    final values = <List<ShiftDayExtra>>[];
    final sub = db.select(db.shiftDayExtras).watch().listen(values.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(Duration.zero);
    await repo.setDayExtra(day, DayExtraKind.leave, 240);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(values.last.single.minutes, 240);
    expect(values.last.single.kind, DayExtraKind.leave.index);
  });
}
