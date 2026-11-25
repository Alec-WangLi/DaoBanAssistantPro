// app/test/alarm_leave_suppression_test.dart
//
// 整天请假 **不排这天的班次闹钟**；部分请假照常排。
//
// 判据放在 `planShiftAlarms` 里，而不是让界面顺手写一条「按天关闹钟」覆盖：
// 请假是「那天不在岗」的事实，调度器直接读它，就不会出现「请了假、又在闹钟页
// 把那天的开关打开」这种两个开关打架的状态。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';

final _day = DateTime(2026, 9, 20);

/// 每天都是 12 小时白班（08:00–20:00），联动闹钟 07:00。
ShiftSchedule _schedule() => ShiftSchedule(
      name: '测试',
      anchorDate: DateTime.utc(2026, 9, 20),
      classes: const [
        ShiftClass(
            id: 11,
            name: '白班',
            abbr: '白',
            startMinute: 8 * 60,
            endMinute: 20 * 60,
            alarmEnabled: true,
            alarms: [ShiftAlarm(minute: 7 * 60)]),
      ],
      cycle: const [0],
      teamCount: 1,
      teamNames: const ['我'],
      teamOffsets: const [0],
    );

/// 窗口从**昨天**起算（见 `planShiftAlarms`）：起点定在 20 日 06:00 时，
/// 19 日那条 07:00 已经过去、会被 `fireAt.isAfter(from)` 滤掉，20 / 21 日各一条。
List<ShiftAlarmPlan> _plan(Map<int, int> leave) => planShiftAlarms(
      _schedule(),
      from: DateTime(2026, 9, 20, 6),
      days: 3,
      leaveMinutes: leave,
    );

void main() {
  test('请假分钟数正好等于班次时长 → 那天不排，后面一天照排', () {
    expect(_plan({dayNumber(_day): 720}), hasLength(1));
  });

  test('请假超过班次时长 → 那天不排', () {
    expect(_plan({dayNumber(_day): 900}), hasLength(1));
  });

  test('部分请假 → 照常排（差一分钟也要上班）', () {
    expect(_plan({dayNumber(_day): 719}), hasLength(2));
    expect(_plan({dayNumber(_day): 240}), hasLength(2));
  });

  test('没记录 → 照常排', () {
    expect(_plan(const {}), hasLength(2));
  });
}
