// app/test/day_extra_test.dart
//
// 日级请假/加班的**值类型**。它只是两个分钟数的容器；这里钉住的只有两件事：
// 「空」的判据（决定界面上画不画标记）与相等性（决定 provider 会不会白白重发）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/day_extra.dart';

void main() {
  test('空值判定：两个字段都 <= 0 才算空', () {
    expect(const DayExtra().isEmpty, isTrue);
    expect(const DayExtra(leaveMinutes: 1).isEmpty, isFalse);
    expect(const DayExtra(overtimeMinutes: 1).isEmpty, isFalse);
    expect(const DayExtra(leaveMinutes: -5).isEmpty, isTrue);
  });

  test('相等性按两个字段', () {
    expect(const DayExtra(leaveMinutes: 240),
        const DayExtra(leaveMinutes: 240));
    expect(const DayExtra(leaveMinutes: 240),
        isNot(const DayExtra(leaveMinutes: 480)));
    expect(const DayExtra(leaveMinutes: 240).hashCode,
        const DayExtra(leaveMinutes: 240).hashCode);
  });
}
