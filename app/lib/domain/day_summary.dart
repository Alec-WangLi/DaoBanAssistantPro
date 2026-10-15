// 「某一天 / 某一个班次」在**界面上怎么说**—— 日历信息卡与桌面小组件快照共用这一份。
//
// 为什么单独抽出来：这两处以前各写一份（`calendar_screen.dart` 里的私有 `_alarmText`
// 与 `_computeMonthTally`），而桌面那份是**照着 App 抄**的。抄的那一份一定会漂 ——
// 班次闹钟的三档落点（前一天 / 当天 / 次日）在 v0.11.1 才刚改过，两处各写一遍就是
// 两个 bug 源，而且分岔时**不报错**，只是「卡片上写的和 App 里写的不是一回事」。
//
// 纯 Dart，不依赖 Flutter 渲染，可以直接单测。
library;

import '../core/l10n.dart';
import 'schedule_chain.dart';
import 'shift_rotation.dart';

/// 「这个班次挂没挂联动闹钟」—— 日历格子左上角那个点与 [alarmNote] **共用这一份
/// 判据**。两处各写一遍的话，哪天规则变了就会出现「格子上有点、信息卡却写着
/// 未开启」这种自相矛盾的画面，而它不会报错。
bool shiftHasAlarms(ShiftClass t) => t.alarmEnabled && t.alarms.isNotEmpty;

/// 班次那一行的备注：休班 / 未开启 / 「闹钟 07:00」（不落在班次**当天**的带
/// 「前一天 / 次日」标记）。
///
/// 那句标记不能省：不标的话，这一行会跟前面的「00:00 – 08:00」读成同一天的两件事
/// （00:00 上班的夜班配 23:00、16:30–次日 00:30 的中班配 00:15 都是这一类）。
String alarmNote(ShiftClass t) {
  if (t.isRest) return L10n.restNoAlarm;
  if (!shiftHasAlarms(t)) return L10n.alarmOff;
  final alarm = t.alarms.first;
  final clock = formatClock(alarm.minute);
  final shown = switch (alarmDayAnchor(t, alarm)) {
    AlarmDayAnchor.prev => L10n.clockPrevDay(clock),
    AlarmDayAnchor.next => L10n.clockNextDay(clock),
    AlarmDayAnchor.same => clock,
  };
  // 多条的只写首条 + 「等 N 个」：这一行本来就是 `maxLines: 1` + 省略号，把每条
  // 时刻都铺开会把后面的内容挤掉 —— 而卡片是**定高**的，多一行就顶高卡片、
  // 连带把日历网格挤矮（`info_card_metrics.dart` 那边的前提）。
  return t.alarms.length == 1
      ? L10n.alarmAt(shown)
      : L10n.alarmFirstOfMany(shown, t.alarms.length);
}

/// [month] 那个月按**班次简称累加**的天数串：「本月 大休13 · 白7 · 上夜6 · 下夜5」。
///
/// **按简称累加、不按 `classes` 下标计数**：跨时段的一个月里两套方案的班次定义
/// 不同，按下标数会把 A 的第 0 个班次和 B 的第 0 个班次算成同一个 —— 数字会错得
/// 看不出来（实测会显示成 `丙30`，加总不再是 30）。跨方案时同名的「休」合并成
/// 一个数，本来就该合。
///
/// 没有排班、或整月都没有班次（空白表跟随法定节假日）时返回 `null` —— 调用点
/// 据此**不画那一行**，而不是画一句空话。
String? monthTallyFor(ScheduleChain? chain, DateTime month) {
  if (chain == null) return null;
  final counts = <String, int>{};
  final days = DateTime(month.year, month.month + 1, 0).day;
  for (var d = 1; d <= days; d++) {
    final shift = chain.shiftOn(DateTime(month.year, month.month, d));
    if (shift == null) continue;
    counts.update(shift.shortLabel, (n) => n + 1, ifAbsent: () => 1);
  }
  if (counts.isEmpty) return null;
  final parts = [for (final e in counts.entries) '${e.key}${e.value}'];
  return '${L10n.monthTally} ${parts.join(' · ')}';
}
