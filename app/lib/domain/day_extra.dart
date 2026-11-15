// app/lib/domain/day_extra.dart
//
// 日级「请假 / 加班」的值类型 —— 全局按天记，不挂在某套排班方案上。
//
// 为什么不挂在方案上：请假是「那天我不在」、加班是「那天我多干了」，
// 换一套班表这两个事实仍然成立（与 `ShiftAlarmOverrides` 全局按天的理由相同）。
//
// 一天各最多一条：请假与加班可以同时存在（上午请假、晚上加班是正常排法）。
enum DayExtraKind { leave, overtime }

class DayExtra {
  const DayExtra({this.leaveMinutes = 0, this.overtimeMinutes = 0});

  /// 请假分钟数；<= 0 视为没有。
  final int leaveMinutes;

  /// 加班分钟数；<= 0 视为没有。
  final int overtimeMinutes;

  /// 两样都没有 —— 界面据此不画「假 / 加」标记。
  bool get isEmpty => leaveMinutes <= 0 && overtimeMinutes <= 0;

  @override
  bool operator ==(Object other) =>
      other is DayExtra &&
      other.leaveMinutes == leaveMinutes &&
      other.overtimeMinutes == overtimeMinutes;

  @override
  int get hashCode => Object.hash(leaveMinutes, overtimeMinutes);

  @override
  String toString() =>
      'DayExtra(leave=$leaveMinutes, overtime=$overtimeMinutes)';
}
