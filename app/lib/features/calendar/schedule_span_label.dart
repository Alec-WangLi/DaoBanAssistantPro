// app/lib/features/calendar/schedule_span_label.dart
//
// 「排班时段」相关的两句纯文案 —— 日历弹层与排班管理页共用。
//
// 单独一个文件而不是塞进某一屏：两处都要用，若放其中一屏里就会变成「管理页
// import 日历页」这种别扭的依赖。函数是纯的，单测也轻。
import '../../core/l10n.dart';
import '../../data/app_repository.dart';

/// 一套方案在**排班管理列表**里的身份标签。
///
/// **三种身份，别合并**：
///  · [`isCurrent`] → 「其余时间」（它管的正是没被时段覆盖的那些天）；
///  · 被时段引用了（`spanCount > 0`）→ 「已排入时段」；
///  · 都不是 → 「未使用」（它不在时间线上，日历上永远不会出现）。
///
/// **这里不再显示日期范围** —— 段独立成表之后，一套方案可以出现在**多段**上
/// （「9 月临时换、之后换回来」），一句话说不清。范围交给上面那条时间线。
String scheduleRoleLabel(
  ShiftScheduleRow s, {
  required int spanCount,
  required bool isCurrent,
}) {
  if (isCurrent) return L10n.remainingTime;
  if (spanCount > 0) return L10n.onTimeline;
  return L10n.unusedSchedule;
}

/// 这套方案被**多少段**引用 —— [scheduleRoleLabel] 要用。
///
/// 独立成函数是因为两个界面（排班管理列表、日历总览弹层）都要数它，各写一份
/// `where(...).length` 迟早会有一处把字段写错（`scheduleId` 与 `id` 只差三个字母）。
int spanCountOf(List<ScheduleSpanRow> spans, int scheduleId) =>
    spans.where((s) => s.scheduleId == scheduleId).length;

/// 段在时间线上那一段的**日期说法**（「9月1日 ～ 9月30日」/「10月8日 起」/
/// 「到 9月30日」/ 两端都空时「一直」）。
///
/// 收两端而不是收一行：段的来源是 `schedule_span_rows`，而调用点（界面、用例）
/// 手上往往是两个 `DateTime?`。
String spanRangeLabel(DateTime? from, DateTime? to) {
  if (from == null && to == null) return L10n.spanAlways;
  if (from == null) return L10n.effectiveUntilDate(L10n.monthDay(to!));
  if (to == null) return L10n.effectiveFromDate(L10n.monthDay(from));
  return L10n.effectiveRangeSpan(L10n.monthDay(from), L10n.monthDay(to));
}
