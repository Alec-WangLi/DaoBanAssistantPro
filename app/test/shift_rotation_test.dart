import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

void main() {
  test('daysBetween 整日差', () {
    expect(daysBetween(DateTime(2025, 1, 1), DateTime(2025, 1, 6)), 5);
    expect(daysBetween(DateTime(2025, 1, 6), DateTime(2025, 1, 1)), -5);
    expect(daysBetween(DateTime(2025, 1, 6), DateTime(2025, 1, 6)), 0);
  });

  test('四班两倒周期正确（白班→上夜班→下夜班→大休）', () {
    final s = defaultSchedule();
    expect(s.cycleLength, 4);
    expect(s.shiftOn(DateTime(2025, 1, 6))!.name, '白班'); // 锚点
    expect(s.shiftOn(DateTime(2025, 1, 7))!.name, '上夜班');
    expect(s.shiftOn(DateTime(2025, 1, 8))!.name, '下夜班');
    expect(s.shiftOn(DateTime(2025, 1, 9))!.name, '大休');
    expect(s.shiftOn(DateTime(2025, 1, 10))!.name, '白班');
  });

  test('负偏移回绕（锚点之前）', () {
    final s = defaultSchedule();
    expect(s.shiftOn(DateTime(2025, 1, 5))!.name, '大休');
    expect(s.shiftOn(DateTime(2025, 1, 4))!.name, '下夜班');
    expect(s.shiftOn(DateTime(2025, 1, 3))!.name, '上夜班');
    expect(s.shiftOn(DateTime(2025, 1, 2))!.name, '白班');
  });

  test('跨午夜判断', () {
    final s = defaultSchedule();
    expect(s.shiftOn(DateTime(2025, 1, 7))!.crossesMidnight, isTrue); // 上夜班
    expect(s.shiftOn(DateTime(2025, 1, 6))!.crossesMidnight, isFalse); // 白班
  });

  test('休息日标记', () {
    final s = defaultSchedule();
    expect(s.shiftOn(DateTime(2025, 1, 8))!.isRest, isTrue); // 下夜班
    expect(s.shiftOn(DateTime(2025, 1, 9))!.isRest, isTrue); // 大休
    expect(s.shiftOn(DateTime(2025, 1, 6))!.isRest, isFalse); // 白班
  });

  test('多班组错开（四班两倒 4 个班）', () {
    final s = defaultSchedule();
    expect(s.teamCount, 4);
    expect(s.teamNames, ['一班', '二班', '三班', '四班']);
    expect(s.ourTeamIndex, 0);
    // 锚点日（我们=一班 白班）：一班白班、二班上夜班、三班下夜班、四班大休
    final anchor = DateTime(2025, 1, 6);
    expect(s.teamShift(0, anchor)!.name, '白班');
    expect(s.teamShift(1, anchor)!.name, '上夜班');
    expect(s.teamShift(2, anchor)!.name, '下夜班');
    expect(s.teamShift(3, anchor)!.name, '大休');
    // 我们班组的班次 = shiftOn
    expect(s.shiftOn(anchor)!.name, s.teamShift(0, anchor)!.name);
    // 次日错开：一班上夜班、二班下夜班、三班大休、四班白班
    final next = DateTime(2025, 1, 7);
    expect(s.teamShift(0, next)!.name, '上夜班');
    expect(s.teamShift(1, next)!.name, '下夜班');
    expect(s.teamShift(2, next)!.name, '大休');
    expect(s.teamShift(3, next)!.name, '白班');
  });
}
