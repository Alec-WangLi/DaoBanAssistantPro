// 桌面小组件的快照生成 —— 纯函数，无 Flutter 渲染依赖、不读挂钟、不碰 Channel。
//
// 这个文件是整条链路的**唯一**智能所在：原生侧（Kotlin 的 WidgetRenderer）
// 只是个排版器，它不知道今天是几号、不会算班次、也不会做中英切换。所有判断都在
// 这里出结论，原样贴到桌面上。
//
// 为什么不把轮转规则抄一份到 Kotlin 让原生自己算：两份引擎就是两个 bug 源，
// 而 `shift_rotation.dart` 里 `dayOverrides` 那套语义（覆盖只在 `shiftOn` 这
// 一层生效、`teamShift` 不查覆盖）抄一遍必抄错。
//
// ⚠️ 一条容易腐坏的不变量：**相对文案按「偏移」索引，不按「日期」烘焙**。
// 快照生成于 9/18 时 days[1] 是「明天」；9/19 凌晨跨天刷新后 days[1] 变成了
// 今天 —— 若「明天」二字烘焙在 days[1] 的 `weekday` 里，卡片会理直气壮写错。
// 所以日期固有的东西（`dateShort` / `weekday` / `timeRange`）按日期烘焙，
// 相对的三个词（今天/明天/后天）放在顶层 `labels` 里，由原生按**渲染时的偏移**取。
library;

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../domain/lunar_info.dart';
import '../../domain/shift_rotation.dart';

/// 快照格式版本。原生按它判断能不能解析 —— 对不上就按「无快照」走降级态。
const int kWidgetSnapshotVersion = 1;

/// 快照里带的天数。
///
/// 14 而不是 7，是因为跨天时小组件**不能**重算（它手上只有这份快照），只能拿
/// `LocalDate.now().toEpochDay()` 去 `days` 里对表、整体右移一格。给「App 两周
/// 没打开」留余量；真耗尽了原生退化成占位态。大卡只用到其中 7 天。
const int kWidgetSnapshotDays = 14;

/// 生成快照。纯函数：当前时刻由 [now] 传入，不读 `DateTime.now()`。
///
/// [themeMode] 是 `'system' | 'light' | 'dark'` —— **模式，不是解析结果**。
/// 把 `system` 提前解析成 light/dark 存进来，「跟随系统」就变成了「跟随生成快照
/// 那一刻的系统」，用户傍晚切深色模式要等到下次 App 启动才跟上。
Map<String, Object?> buildWidgetSnapshot({
  required ShiftSchedule? schedule,
  required DateTime now,
  required String themeMode,
  required int accent,
  /// 今日**未完成**待办数。今日卡片上那个「N 项待办」徽章用它。
  /// 快照拿不到待办数据（那是 Drift 里的事），所以由调用方数好传进来。
  required int todayTodoCount,
}) {
  final today = dateOnly(now);
  final nowMs = now.millisecondsSinceEpoch;
  final days = <Map<String, Object?>>[];
  final boundaries = <int>{};

  for (var i = 0; i < kWidgetSnapshotDays; i++) {
    // 本地日历日。`today` 是 UTC 的纯日期，只取它的年月日再重建成**本地**时刻，
    // 这样下面减出来的毫秒数才落在用户所在时区的正确钟点上。
    final date = DateTime(today.year, today.month, today.day + i);
    final dayStart = date;
    final shift = schedule?.shiftOn(date);

    // 本地零点也是边界：跨天要翻页。
    final nextMidnight = DateTime(date.year, date.month, date.day + 1);
    if (nextMidnight.millisecondsSinceEpoch > nowMs) {
      boundaries.add(nextMidnight.millisecondsSinceEpoch);
    }

    String? timeRange;
    if (shift != null && shift.startMinute != null && shift.endMinute != null) {
      final start = dayStart.add(Duration(minutes: shift.startMinute!));
      var end = dayStart.add(Duration(minutes: shift.endMinute!));
      // 结束时间有两种表示法，都要接住：
      //   · endMinute < startMinute —— 跨午夜（20:30 → 08:30，end=510）
      //   · endMinute ≥ 1440      —— 24 小时班 / 24:00（480 → 1920）
      // 前者加一天；后者本身就落在次日，加了反而过头。
      if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
      timeRange = L10n.timeRange(
        formatClock(shift.startMinute!),
        formatClock(shift.endMinute!),
        shift.endsNextDay,
      );
      if (start.millisecondsSinceEpoch > nowMs) {
        boundaries.add(start.millisecondsSinceEpoch);
      }
      if (end.millisecondsSinceEpoch > nowMs) {
        boundaries.add(end.millisecondsSinceEpoch);
      }
    }

    days.add({
      'day': dayNumber(date),
      'weekday': L10n.weekday(date.weekday - 1),
      'dateShort': L10n.monthDay(date),
      'hasShift': shift != null,
      'isRest': shift?.isRest ?? true,
      'shiftName': shift?.name ?? '',
      'shiftAbbr': shift?.shortLabel ?? '',
      'color': shift?.color ?? 0,
      // 胶囊上的字色：底色已定、白黑二选一，交给既有的 [AppTokens.onSolid]
      // （它的注释说明了为什么不能让 `inkFor` 代劳）。
      'abbrInk': shift == null
          ? 0
          : AppTokens.onSolid(Color(shift.color)).toARGB32(),
      'timeRange': timeRange,
    });
  }

  final sorted = boundaries.toList()..sort();

  // 今日卡片的数据。它**按日期烘焙**（农历、待办数、其他班组都是「今天」这一天的），
  // 所以带上自己的 `day` —— 跨天之后原生对表发现对不上，就走降级态而不是把旧数据
  // 当成今天显示（见 spec §6 的 ⚠️）。
  final todayDate = DateTime(today.year, today.month, today.day);
  final lunar = lunarOf(todayDate);
  final crews = <Map<String, Object?>>[];
  if (schedule != null && !schedule.isBlank) {
    for (var i = 0; i < schedule.teamCount; i++) {
      if (i == schedule.ourTeamIndex) continue; // 只看别人
      final t = schedule.teamShift(i, todayDate);
      if (t == null) continue;
      final name = i < schedule.teamNames.length
          ? schedule.teamNames[i]
          : (L10n.isEn ? 'Team ${i + 1}' : '${i + 1}班');
      crews.add({'name': name, 'abbr': t.shortLabel, 'color': t.color});
    }
  }
  final todayCard = {
    'day': dayNumber(todayDate),
    'lunarShort': lunar.shortLabel,
    'lunarIsHoliday': lunar.isLegalHoliday,
    'adjusted': schedule?.dayOverrides.containsKey(dayNumber(todayDate)) ?? false,
    'todoCount': todayTodoCount,
    // 徽章上的**文字**也在这里给全 —— 原生不许有中文字面量，而
    // `'$n 项待办'` / `'$n todos'` 是双语的。没有待办时给 null，原生据此隐藏徽章。
    'todoBadge': todayTodoCount > 0 ? L10n.todoCount(todayTodoCount) : null,
    'crews': crews,
  };

  return {
    'v': kWidgetSnapshotVersion,
    'genAtMs': nowMs,
    'lang': L10n.locale,
    'themeMode': themeMode,
    'accent': accent,
    'hasSchedule': schedule != null && !schedule.isBlank,
    'emptyHint': L10n.widgetEmptyHint,
    'labels': {
      'today': L10n.widgetToday,
      'tomorrow': L10n.widgetTomorrow,
      'dayAfter': L10n.widgetDayAfter,
      'adjusted': L10n.adjusted,
    },
    'boundaries': sorted,
    'days': days,
    'todayCard': todayCard,
  };
}
