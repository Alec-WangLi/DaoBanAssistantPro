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

  test('图层：周期引用的是班次定义，不是每天一行', () {
    final s = ShiftSchedule(
      name: '白白夜夜休休',
      anchorDate: DateTime.utc(2025, 1, 6),
      classes: const [
        ShiftClass(name: '白班', abbr: '白'),
        ShiftClass(name: '夜班', abbr: '夜'),
        ShiftClass(name: '休班', abbr: '休', isRest: true),
      ],
      cycle: const [0, 0, 1, 1, 2, 2],
      teamCount: 3,
      teamNames: const ['一班', '二班', '三班'],
      teamOffsets: const [0, 2, 4],
    );
    expect(s.cycleLength, 6);
    expect(s.classes.length, 3);
    expect(s.shiftOn(DateTime.utc(2025, 1, 6))!.name, '白班');
    expect(s.shiftOn(DateTime.utc(2025, 1, 8))!.name, '夜班');
    expect(s.shiftOn(DateTime.utc(2025, 1, 11))!.name, '休班');
  });

  test('格子简称：显式 abbr 优先，为空时按名称推断', () {
    expect(const ShiftClass(name: '早班', abbr: '早').shortLabel, '早');
    expect(const ShiftClass(name: '早班').shortLabel, '白'); // 旧的推断行为
    expect(const ShiftClass(name: '大夜').shortLabel, '夜');
    expect(const ShiftClass(name: '休班', isRest: true).shortLabel, '休');
    expect(const ShiftClass(name: '').shortLabel, '·');
    // emoji 开头：应取到完整字素簇，不能切成半个代理对
    expect(const ShiftClass(name: '🔥白班').shortLabel, '白'); // 含「白」走推断
    expect(const ShiftClass(name: '🔥').shortLabel, '🔥');
    expect(const ShiftClass(name: '👨‍👩‍👧').shortLabel, '👨‍👩‍👧');
  });

  test('24 小时值班跨午夜', () {
    const duty = ShiftClass(name: '值班', startMinute: 8 * 60, endMinute: 32 * 60);
    expect(duty.crossesMidnight, isTrue);
    const mid = ShiftClass(name: '中班', startMinute: 16 * 60, endMinute: 24 * 60);
    expect(mid.crossesMidnight, isFalse); // 16:00–24:00 不算跨午夜
  });
}
