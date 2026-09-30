// 重复待办的规则 —— 纯 Dart，只依赖 intl（经由 `l10n.dart`）与 `shift_rotation.dart`，
// 可直接 dart test。
//
// 几个查询函数**都不读时钟**：当前时刻 / 今天由调用方注入。理由是这套东西的边界
// （月末、跨年、起始日、夏令时）恰好都不在「今天」上，读时钟的写法只能测今天那一
// 个输入。与 `planShiftAlarms(from:)` 同一条理由。
//
// 日期算术一律 `DateTime.utc(y, m, d + n)`：它会把溢出规范化（`d = 0` 指上月最后
// 一天、`m = 13` 指次年 1 月），而 `Duration(days:)` 加的是绝对 24 小时，碰上夏令时
// 切换会把日期挪掉一整天。

import '../core/l10n.dart';
import 'shift_rotation.dart';

/// 重复的周期。
enum RecurRepeat { daily, weekly, monthly }

/// 一个重复待办的**系列定义**（库里 `RecurringTodos` 一行的领域形态）。
class RecurringTodo {
  const RecurringTodo({
    required this.id,
    required this.title,
    required this.repeat,
    required this.startDate,
    this.timeMinute,
    this.advanceRemindMinutes,
    this.alarmEnabled = false,
    this.weekdays = 0,
    this.monthDay = 1,
    this.skipThrough,
    this.enabled = true,
  });

  /// 库里的行 id；null = 还没落库。
  final int? id;

  final String title;
  final RecurRepeat repeat;

  /// 分钟自午夜；null = 全天。
  final int? timeMinute;

  /// 提醒档位：null = 不提醒，0 = 准时，其余为提前的分钟数。
  final int? advanceRemindMinutes;

  /// 到点走**闹钟**（全屏 + 循环铃声）而不是只弹一条通知。
  final bool alarmEnabled;

  /// 每周：`1 << (weekday - 1)`，周一 = 1（与 `DateTime.weekday` 同序，
  /// 也与 `CustomAlarms.weekdays` 同一约定）。
  final int weekdays;

  /// 每月：1..31；该月没有这一天时取该月最后一天。
  final int monthDay;

  /// 首次生效日（纯日期）。这一天之前不产生任何发生日。
  final DateTime startDate;

  /// 「这次不要了」记到哪天为止（自 epoch 天数，与 `dayNumber` 同口径）；
  /// 空 = 没跳过。
  final int? skipThrough;

  /// 停用：不再生成、不再顺延、不再排提醒；**已经出现的那条留着**。
  final bool enabled;

  /// 规则的可读描述（「每周三」「每月 1 号」）。
  ///
  /// **提醒的正文用它，所以它不许带日期** —— 同一条提醒会跨很多次，写死日期
  /// 第二次就是错的。
  String get ruleLabel {
    switch (repeat) {
      case RecurRepeat.daily:
        return L10n.repeatDaily;
      case RecurRepeat.weekly:
        final days = [
          for (var i = 0; i < 7; i++)
            if ((weekdays & (1 << i)) != 0) i,
        ];
        // 掩码为空是脏数据（界面上不允许）：退回不带星期的说法，而不是拼出一个
        // 空串让提醒正文变成「 · 09:00」。
        if (days.isEmpty) return L10n.repeatWeekly;
        return L10n.everyWeekOn(days);
      case RecurRepeat.monthly:
        return L10n.everyMonthOnDay(monthDay);
    }
  }

  /// `HH:mm`；没设时间返回空串。
  String get timeLabel => timeMinute == null ? '' : formatClock(timeMinute!);

  /// 提醒正文（`每周三 · 09:00`）。
  String get ruleWithTime => L10n.ruleWithTime(ruleLabel, timeLabel);

  /// **注意它清不掉可空字段**：`advanceRemindMinutes ?? this.advanceRemindMinutes`
  /// 这种写法没有「传 null 就是清空」的通道 —— 把提醒从「提前 5 分钟」改回「不设」
  /// 时，`copyWith(advanceRemindMinutes: null)` 会**原样保留旧值**，而界面上看不出
  /// 来（那一行只是没变）。要清空就**显式构造**一个 `RecurringTodo(...)`。
  ///
  /// （这是 `shift_rotation.dart` 的 `ShiftClass` 踩过的同一个坑：那边编辑器的
  /// `_editClass` 也是有意不走 `copyWith`，理由写在那里。这里把警告写在方法上，
  /// 免得下一个人从两个地方各挑一半。）
  RecurringTodo copyWith({
    int? id,
    String? title,
    RecurRepeat? repeat,
    int? timeMinute,
    int? advanceRemindMinutes,
    bool? alarmEnabled,
    int? weekdays,
    int? monthDay,
    DateTime? startDate,
    int? skipThrough,
    bool? enabled,
  }) =>
      RecurringTodo(
        id: id ?? this.id,
        title: title ?? this.title,
        repeat: repeat ?? this.repeat,
        timeMinute: timeMinute ?? this.timeMinute,
        advanceRemindMinutes: advanceRemindMinutes ?? this.advanceRemindMinutes,
        alarmEnabled: alarmEnabled ?? this.alarmEnabled,
        weekdays: weekdays ?? this.weekdays,
        monthDay: monthDay ?? this.monthDay,
        startDate: startDate ?? this.startDate,
        skipThrough: skipThrough ?? this.skipThrough,
        enabled: enabled ?? this.enabled,
      );

  @override
  String toString() => 'RecurringTodo($title, $repeat)';
}

/// 往后 / 往前挪整天。**不能用 `Duration(days:)`** —— 它加的是绝对 24 小时，
/// 夏令时那两天会挪错日期。`DateTime.utc` 会把 `d` 的溢出规范化（`d = 0` = 上月
/// 最后一天，`d = -1` = 上上月最后一天）。
DateTime _addDays(DateTime d, int n) => DateTime.utc(d.year, d.month, d.day + n);

/// 「每月某日」落在某个年月上的**具体日期**：该月没有这一天时取该月最后一天
/// （每月 31 号 → 2 月落在 28/29）。`month` 可以溢出（13 = 次年 1 月）。
DateTime _monthlyIn(int year, int month, int monthDay) {
  // `DateTime.utc(y, m + 1, 0)` 就是「m 月的最后一天」—— day = 0 会规范化成上月末。
  final last = DateTime.utc(year, month + 1, 0).day;
  return DateTime.utc(year, month, monthDay <= last ? monthDay : last);
}

bool _matchesWeekday(int weekdays, DateTime d) =>
    (weekdays & (1 << (d.weekday - 1))) != 0;

/// 不早于 [from] 的**第一次**发生日；受 `startDate` 约束，无解返回 null。
DateTime? firstOccurrenceOnOrAfter(RecurringTodo s, DateTime from) {
  final start = dateOnly(s.startDate);
  var base = dateOnly(from);
  if (daysBetween(start, base) < 0) base = start;
  switch (s.repeat) {
    case RecurRepeat.daily:
      return base;
    case RecurRepeat.weekly:
      if (s.weekdays == 0) return null;
      for (var i = 0; i < 7; i++) {
        final c = _addDays(base, i);
        if (_matchesWeekday(s.weekdays, c)) return c;
      }
      return null;
    case RecurRepeat.monthly:
      // 最多找两年：`monthDay` 在 1..31 之内时一定能在 2 个月内找到，
      // 上限只是防御（脏数据里的 0 或 99）。
      for (var i = 0; i < 24; i++) {
        final c = _monthlyIn(base.year, base.month + i, s.monthDay);
        if (daysBetween(base, c) >= 0) return c;
      }
      return null;
  }
}

/// 不晚于 [day] 的**最近一次**发生日；`startDate` 之前返回 null。
DateTime? occurrenceOnOrBefore(RecurringTodo s, DateTime day) {
  final start = dateOnly(s.startDate);
  final d = dateOnly(day);
  if (daysBetween(start, d) < 0) return null;
  switch (s.repeat) {
    case RecurRepeat.daily:
      return d;
    case RecurRepeat.weekly:
      if (s.weekdays == 0) return null;
      for (var back = 0; back < 7; back++) {
        final c = _addDays(d, -back);
        if (_matchesWeekday(s.weekdays, c)) {
          return daysBetween(start, c) >= 0 ? c : null;
        }
      }
      return null;
    case RecurRepeat.monthly:
      for (var back = 0; back < 24; back++) {
        final c = _monthlyIn(d.year, d.month - back, s.monthDay);
        if (daysBetween(c, d) >= 0) {
          return daysBetween(start, c) >= 0 ? c : null;
        }
      }
      return null;
  }
}

/// **严格晚于** [day] 的下一次发生日。
DateTime? nextOccurrenceAfter(RecurringTodo s, DateTime day) =>
    firstOccurrenceOnOrAfter(s, _addDays(dateOnly(day), 1));

/// 某一次发生日的**触发时刻**（本地时间）。
///
/// `occ` 是 UTC 纯日期，要取它的年月日再按本地时区重建 —— 直接在它上面加分钟会
/// 带着 UTC 标志，交给原生算 epoch 毫秒时差一个时区（`eventReminderTime` 里
/// 记的是同一个坑）。
DateTime _fireAt(DateTime occ, int clock, int advance) =>
    DateTime(occ.year, occ.month, occ.day).add(Duration(minutes: clock - advance));

/// 从 [from] 之后开始、未来 [days] 天里这条系列要响的全部时刻，最多 [cap] 条。
///
/// **起点是「不晚于 from 的那一次」，不是「下一次」**：今天这次还没到点的话，它
/// 也算一条（早上八点打开 App，今天九点的提醒该排上）。而它的触发时刻已经过去时
/// 自然被 `!fire.isBefore(from)` 筛掉，循环继续往下走 —— 那正是「下午打开也能排上
/// 下一次」的写法。
///
/// [clockMinute] 是「这次要响的钟点」：待办没设时间时按几点提醒，是提醒层的策略
/// （`AlarmService.allDayReminderHour`），不由领域层决定，所以由调用方传进来。
/// 领域层不 import `features/` 下的东西 —— 那会把「纯 Dart 可单测」这条性质打破。
List<DateTime> upcomingFireTimes(
  RecurringTodo s, {
  required DateTime from,
  required int clockMinute,
  int days = 180,
  int cap = 200,
}) {
  final advance = s.advanceRemindMinutes;
  if (advance == null || !s.enabled) return const [];
  final horizon = from.add(Duration(days: days));
  final out = <DateTime>[];
  var occ = occurrenceOnOrBefore(s, from) ?? firstOccurrenceOnOrAfter(s, from);
  while (occ != null && out.length < cap) {
    final fire = _fireAt(occ, clockMinute, advance);
    if (!fire.isBefore(from)) {
      if (fire.isAfter(horizon)) break;
      out.add(fire);
    }
    occ = nextOccurrenceAfter(s, occ);
  }
  return out;
}
