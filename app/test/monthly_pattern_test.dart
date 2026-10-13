import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/monthly_pattern.dart';

void main() {
  // 用户那张表：一个月三段，1–10 中、11–20 白、21–月底 夜。
  const three = [
    MonthlySegment(startDay: 1, classIndex: 0),
    MonthlySegment(startDay: 11, classIndex: 1),
    MonthlySegment(startDay: 21, classIndex: 2),
  ];

  test('用户那张表：每个月的第 1 / 11 / 21 天各换一次段', () {
    expect(segmentIndexOn(three, 1), 0);
    expect(segmentIndexOn(three, 10), 0);
    expect(segmentIndexOn(three, 11), 1);
    expect(segmentIndexOn(three, 20), 1);
    expect(segmentIndexOn(three, 21), 2);
    expect(segmentIndexOn(three, 31), 2);
  });

  test('月长不等是本职：2 月的 28 号同样落在第三段（最后剩下的都是它）', () {
    expect(segmentIndexOn(three, 28), 2);
    expect(segmentIndexOn(three, 29), 2);
    expect(segmentIndexOn(three, 30), 2);
  });

  test('单段 = 整月一个班次', () {
    const one = [MonthlySegment(startDay: 1, classIndex: 3)];
    for (var d = 1; d <= 31; d++) {
      expect(segmentIndexOn(one, d), 0);
      expect(monthlyClassIndexOn(one, d, 0), 3);
    }
  });

  test('空表：segmentIndexOn 返回 -1、monthlyClassIndexOn 返回 null', () {
    expect(segmentIndexOn(const [], 5), -1);
    expect(monthlyClassIndexOn(const [], 5, 0), isNull);
  });

  test('班组按段错开：段内绕回来', () {
    expect(monthlyClassIndexOn(three, 5, 0), 0); // 甲：第 1 段
    expect(monthlyClassIndexOn(three, 5, 1), 1); // 乙：第 2 段
    expect(monthlyClassIndexOn(three, 5, 2), 2); // 丙：第 3 段
    // 25 号在第 3 段：乙绕回第 1 段、丙绕回第 2 段
    expect(monthlyClassIndexOn(three, 25, 0), 2);
    expect(monthlyClassIndexOn(three, 25, 1), 0);
    expect(monthlyClassIndexOn(three, 25, 2), 1);
  });

  test('负的段偏移也绕得对（Dart 的 % 对正除数恒非负）', () {
    expect(monthlyClassIndexOn(three, 5, -1), 2);
    expect(monthlyClassIndexOn(three, 5, -3), 0);
  });

  test('defaultMonthlySegments：1 段退化成 [(1, 0)]', () {
    expect(defaultMonthlySegments(1),
        const [MonthlySegment(startDay: 1, classIndex: 0)]);
  });

  test('defaultMonthlySegments：把 31 天均分、第 i 段指向第 i 个班次', () {
    expect([for (final s in defaultMonthlySegments(3)) s.startDay], [1, 11, 22]);
    expect([for (final s in defaultMonthlySegments(4)) s.startDay], [1, 9, 17, 24]);
    expect(defaultMonthlySegments(3).map((s) => s.classIndex), [0, 1, 2]);
  });

  test('defaultMonthlySegments：1..31 段都合法、最后一段不越过 31 号', () {
    for (var n = 1; n <= 31; n++) {
      final segs = defaultMonthlySegments(n);
      expect(segs.length, n, reason: 'n=$n');
      expect(validMonthlySegments(segs), isTrue, reason: 'n=$n → $segs');
      expect(segs.last.startDay, lessThanOrEqualTo(31), reason: 'n=$n');
      expect(segs.first.startDay, 1, reason: 'n=$n');
    }
    expect(defaultMonthlySegments(0), isEmpty);
  });

  test('validMonthlySegments：五种形状', () {
    expect(validMonthlySegments(const []), isFalse); // 空
    expect(
      validMonthlySegments(
          const [MonthlySegment(startDay: 2, classIndex: 0)]),
      isFalse, // 第一段不从 1 起
    );
    expect(
      validMonthlySegments(const [
        MonthlySegment(startDay: 1, classIndex: 0),
        MonthlySegment(startDay: 1, classIndex: 1),
      ]),
      isFalse, // 不严格递增
    );
    expect(
      validMonthlySegments(
          const [MonthlySegment(startDay: 32, classIndex: 0)]),
      isFalse, // 越界
    );
    expect(validMonthlySegments(three), isTrue);
  });

  test('MonthlySegment 的值相等（列表比较靠它）', () {
    expect(const MonthlySegment(startDay: 11, classIndex: 1),
        const MonthlySegment(startDay: 11, classIndex: 1));
    expect(const MonthlySegment(startDay: 11, classIndex: 1).hashCode,
        const MonthlySegment(startDay: 11, classIndex: 1).hashCode);
    expect(const MonthlySegment(startDay: 11, classIndex: 1),
        isNot(const MonthlySegment(startDay: 12, classIndex: 1)));
  });
}
