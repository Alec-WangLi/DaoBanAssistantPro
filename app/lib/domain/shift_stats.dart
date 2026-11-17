// app/lib/domain/shift_stats.dart
//
// 统计页的唯一算法来源：**纯函数**，不依赖 Flutter，可直接单测。
//
// 三条贯穿本文件的纪律（每一条都对应一次「算错了不报错」的坑）：
//  · 班次时长必须兼容 `endMinute` 的三种真实形态：累计值（>1440）、回绕值
//    （< startMinute）、正好 1440。少一种就会让夜班 / 24 小时班工时静默偏差。
//  · **跨月 / 跨年的夜班整段算在上班开始那天**（12/31 20:30–1/1 08:30 全算 12 月）。
//  · 「未排班」「空白表（跟随法定节假日）」「休息」是三件事，不能合并：
//    空白表没有班次定义，**绝不替它合成上班 / 休息**（v0.9.15 的教训）。
//
// 请假 / 加班是全局日级记录（`DayExtra`），不挂在某套方案上。

import 'day_extra.dart';
import 'lunar_info.dart';
import 'schedule_chain.dart';
import 'shift_rotation.dart';

/// 一个班次的工作时长（分钟）；休息 / 没设时间 / 零长度返回 null。
///
/// `endMinute` 在库里可能存成三种形态，三种都要认：
///   · 累计值：24 小时班 08:00 → 次日 08:00 存成 480 → 1920；
///   · 回绕值：20:30 → 08:30 存成 1230 → 510；
///   · 正好 1440：08:00 → 24:00。
int? shiftDurationMinutes(ShiftClass c) {
  if (c.isRest) return null;
  final s = c.startMinute, e = c.endMinute;
  if (s == null || e == null) return null;
  final raw = e >= s ? e - s : e + 1440 - s;
  return raw > 0 ? raw : null;
}

/// 一个期间（月 / 年 / 自定义区间）的统计结果。
class ShiftStats {
  const ShiftStats({
    this.workDays = 0,
    this.restDays = 0,
    this.unscheduledDays = 0,
    this.blankDays = 0,
    this.missingTimeDays = 0,
    this.normalMinutes = 0,
    this.overtimeMinutes = 0,
    this.leaveMinutes = 0,
    this.fullLeaveDays = 0,
    this.nightShiftDays = 0,
    this.holidayWorkDays = 0,
    this.longestWorkStreak = 0,
    this.longestRestStreak = 0,
    this.classDayCounts = const {},
    this.leaveMinutesByKind = const {},
  });

  /// 出勤天数（整天请假不算）。
  final int workDays;

  /// 休息日天数（`isRest` 班次）。
  final int restDays;

  /// 完全没有班表在管的天数。
  final int unscheduledDays;

  /// 有班表在管、但那天没有班次定义的天数（空白表 = 跟随法定节假日）。
  final int blankDays;

  /// 出勤日里班次没设时间的天数 —— 算出勤、工时记 0，界面要提示。
  final int missingTimeDays;

  /// 正常工时（分钟）：每个出勤班次时长扣掉当天请假后相加。
  final int normalMinutes;

  /// 加班工时（分钟）：日级记录相加，叠在正常工时之外。
  final int overtimeMinutes;

  /// 请假时长（分钟）：日级记录相加（含休息日 / 未排班日的记录）。
  final int leaveMinutes;

  /// 整天请假的天数（请假分钟数 >= 当天班次时长）。
  final int fullLeaveDays;

  final int nightShiftDays;
  final int holidayWorkDays;
  final int longestWorkStreak;
  final int longestRestStreak;

  /// 班次简称 → 天数，与信息卡「本月统计」同口径。
  final Map<String, int> classDayCounts;

  /// 请假类型键 → 请假分钟数。没选类型的旧记录归到
  /// [kUnspecifiedLeaveKind]（见 `domain/day_extra.dart`）。
  final Map<String, int> leaveMinutesByKind;

  /// 实际在岗 = 正常 + 加班。
  int get totalMinutes => normalMinutes + overtimeMinutes;

  /// 平均每班工时（分钟）；零出勤返回 0。
  double get averageMinutesPerWorkDay =>
      workDays == 0 ? 0 : normalMinutes / workDays;

  bool get isEmpty =>
      workDays == 0 &&
      restDays == 0 &&
      unscheduledDays == 0 &&
      blankDays == 0 &&
      leaveMinutes == 0 &&
      overtimeMinutes == 0;

  @override
  String toString() => 'ShiftStats(work=$workDays, rest=$restDays, '
      'normal=$normalMinutes, ot=$overtimeMinutes, leave=$leaveMinutes)';
}

/// 统计 [from]..[to]（闭区间，按 `dayNumber` 口径）。
///
/// [isHoliday] 默认读已安装的法定节假日表；用例传桩函数，避免依赖真实农历数据。
ShiftStats shiftStatsFor({
  required ScheduleChain? chain,
  required DateTime from,
  required DateTime to,
  Map<int, DayExtra> extras = const {},
  bool Function(DateTime)? isHoliday,
}) {
  final start = dayNumber(from);
  final end = dayNumber(to);
  if (end < start) return const ShiftStats();

  var workDays = 0;
  var restDays = 0;
  var unscheduledDays = 0;
  var blankDays = 0;
  var missingTimeDays = 0;
  var normalMinutes = 0;
  var overtimeMinutes = 0;
  var leaveMinutes = 0;
  var fullLeaveDays = 0;
  var nightShiftDays = 0;
  var holidayWorkDays = 0;
  var workRun = 0;
  var restRun = 0;
  var longestWork = 0;
  var longestRest = 0;
  final classDayCounts = <String, int>{};
  final leaveMinutesByKind = <String, int>{};
  // `holidayNameOf` 返回的是假期名字（String?），这里要的是布尔。
  final bool Function(DateTime) holidayOf =
      isHoliday ?? (DateTime d) => holidayNameOf(d) != null;

  for (var n = start; n <= end; n++) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      n * Duration.millisecondsPerDay,
      isUtc: true,
    );
    final extra = extras[n];
    final leave = extra?.leaveMinutes ?? 0;
    final overtime = extra?.overtimeMinutes ?? 0;
    leaveMinutes += leave;
    overtimeMinutes += overtime;
    if (leave > 0) {
      final typeKey = extra?.leaveKind ?? kUnspecifiedLeaveKind;
      leaveMinutesByKind.update(typeKey, (v) => v + leave,
          ifAbsent: () => leave);
    }

    final shift = chain?.shiftOn(date);
    if (shift == null) {
      // 两种情况不能合并：有班表在管（空白表）vs 真的没有班表。
      if (chain?.hasScheduleOn(date) ?? false) {
        blankDays++;
      } else {
        unscheduledDays++;
      }
      // 既不是出勤也不是休息，两段连续都断开。
      workRun = 0;
      restRun = 0;
      continue;
    }

    classDayCounts.update(shift.shortLabel, (v) => v + 1,
        ifAbsent: () => 1);

    if (shift.isRest) {
      restDays++;
      restRun++;
      workRun = 0;
      if (restRun > longestRest) longestRest = restRun;
      continue;
    }

    final duration = shiftDurationMinutes(shift);
    // 没设时间时无法判断「整天」——按出勤算，工时记 0。
    final attended = duration == null || leave < duration;
    if (!attended) {
      // 整天请假：不计出勤、不扣工时（本来就没算），连续两段都断开。
      fullLeaveDays++;
      workRun = 0;
      restRun = 0;
      continue;
    }

    workDays++;
    workRun++;
    restRun = 0;
    if (workRun > longestWork) longestWork = workRun;

    if (duration == null) {
      missingTimeDays++;
    } else {
      final worked = duration - leave;
      normalMinutes += worked > 0 ? worked : 0;
    }
    if (shift.isNight) nightShiftDays++;
    if (holidayOf(date)) holidayWorkDays++;
  }

  return ShiftStats(
    workDays: workDays,
    restDays: restDays,
    unscheduledDays: unscheduledDays,
    blankDays: blankDays,
    missingTimeDays: missingTimeDays,
    normalMinutes: normalMinutes,
    overtimeMinutes: overtimeMinutes,
    leaveMinutes: leaveMinutes,
    fullLeaveDays: fullLeaveDays,
    nightShiftDays: nightShiftDays,
    holidayWorkDays: holidayWorkDays,
    longestWorkStreak: longestWork,
    longestRestStreak: longestRest,
    classDayCounts: Map<String, int>.unmodifiable(classDayCounts),
    leaveMinutesByKind:
        Map<String, int>.unmodifiable(leaveMinutesByKind),
  );
}
