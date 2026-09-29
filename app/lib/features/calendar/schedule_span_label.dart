// app/lib/features/calendar/schedule_span_label.dart
//
// 「这套方案管哪些日子」的**一句话**说法 —— 日历顶栏的切换弹窗与排班管理页共用。
//
// 单独一个文件而不是塞进某一屏：两处都要用，若放其中一屏里就会变成「管理页
// import 日历页」这种别扭的依赖。函数是纯的，单测也轻。
import '../../core/l10n.dart';
import '../../data/app_repository.dart';

/// 一套方案的生效时段标签。
///
/// **两种「没设」的说法不同**，这点很要紧 —— 它决定了用户能不能看懂「谁管哪些
/// 日子」：
///  · 没设时段、又是当前方案 → 「其余日子」（它管的就是剩下那些天）；
///  · 没设时段、又不是当前 → 「未参与衔接」（它在时间线上根本不出现）。
///
/// 这两句加上「没被上面时段覆盖的日子，用标着「其余日子」的那套」
/// （`L10n.effectiveOutsideHint`）就是把解析规则讲给用户听的**全部**（spec §8.2）。
String effectiveRangeLabel(ShiftScheduleRow s, {required bool isCurrent}) {
  final from = s.effectiveFrom;
  final to = s.effectiveTo;
  if (from == null && to == null) {
    return isCurrent ? L10n.effectiveRemaining : L10n.effectiveNotChained;
  }
  if (from == null) return L10n.effectiveUntilDate(L10n.monthDay(to!));
  if (to == null) return L10n.effectiveFromDate(L10n.monthDay(from));
  return L10n.effectiveRangeSpan(L10n.monthDay(from), L10n.monthDay(to));
}
