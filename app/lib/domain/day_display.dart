// app/lib/domain/day_display.dart
//
// 「这一天在界面上画成什么」的**唯一**一处实现。
//
// 它与 `ShiftSource.shiftOn` 只差一件事：**空白表（跟随法定节假日）不是「没有
// 排班」**。空白表的 `cycle` 是空的，所以 `shiftOn` 天天返回 null；可对用户来说
// 那套班表是**在用的** —— 法定节假日休息、其余日子上班。
//
// 为什么单独一个文件、而不是各界面各写一份：日历格子、本月统计、桌面小组件三处
// 必须同解，而「同一天两个界面显示得不一样」正是本仓栽过的跟头（v0.9.10 的农历
// 标签：App 里写「全民国…」、桌面写「全民…」）。函数是纯的，单测也轻。
//
// ⚠️ 合成出来的班次**不是库里的班次**：`id` 为 null、没有时间、没有闹钟 —— 它
// 只回答「画什么」。`shiftOn` 保持真值 null 不动，因为两条链都指着它：闹钟链
// （空白表没有钟点可排）与按天改班的闸门（空白表没有班次定义可挑）。
//
// 2026-09-30 用户真机反馈：只有一套法定班次时，日历整月盖着「这段时间没有排班」
// —— 根因就是判据用了 `shiftOn == null`（见 `calendar_screen._monthHasNoShift`）。
import '../core/l10n.dart';
import 'lunar_info.dart';
import 'schedule_chain.dart';
import 'shift_rotation.dart';

/// 空白表那两天的合成色 —— **借内置模板里「白班」与「休班」的颜色**
/// （`shift_templates.dart` 的原型色），不另造色号。
///
/// 借而不是新定：桌面小组件画的是同一个色，两边各定一个迟早会飘
/// （「同一天两个界面颜色不一样」与上一条注释里那个农历问题同一类）。
const int _workdayColor = 0xFF4C8DFF;
const int _restColor = 0xFF9AA0B4;

/// 整条链上，[date] 这一天画成什么。
///
/// **null 只有一种含义：真的没有排班** —— 那段日子没被任何时段覆盖，而「其余
/// 时间」是「无」。日历据此决定要不要盖那层「这段时间没有排班」的指路。
///
/// 有三种情况会走到「有东西可画」：
///   1. 那天归某套方案，且那套那天有班次 → 照常；
///   2. 那天归某套**空白表** → 「上班」/「休息」（见 [blankDayChip]）；
///   3. 那天归某套方案、不是空白表、但那天的班次为空 —— 只有周期里指向了不存在的
///      班次定义这种脏数据才会发生，按「没有排班」处理。
ShiftClass? displayShiftOn(ScheduleChain? chain, DateTime date) {
  final schedule = chain?.scheduleOn(date);
  if (schedule == null) return null;
  final real = schedule.shiftOn(date);
  if (real != null) return real;
  if (!schedule.isBlank) return null;
  return blankDayChip(date);
}

/// 空白表（跟随法定节假日）这一天画成什么。
///
/// 判据与日历信息卡里那一支**同源**（`lunarOf(date).isLegalHoliday`）：法定节假日
/// 写「休息」，其余日子写「上班」。两处判据一旦不同源，就会出现「信息卡说上班、
/// 格子里写着休息」。
///
/// 简称按**格子**给（中文两个字「上班 / 休息」；英文单字母 `W` / `R` —— 与内置
/// 模板里那些英文简称同一条约定，英文全名塞进 40dp 的格子里会被缩放糊掉）。
ShiftClass blankDayChip(DateTime date) {
  final rest = lunarOf(date).isLegalHoliday;
  return ShiftClass(
    name: rest ? L10n.rest : L10n.workday,
    abbr: rest ? L10n.restShort : L10n.workdayShort,
    color: rest ? _restColor : _workdayColor,
    isRest: rest,
  );
}
