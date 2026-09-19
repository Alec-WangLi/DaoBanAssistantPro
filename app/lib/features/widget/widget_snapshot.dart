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

import '../../core/l10n.dart';
import '../../domain/lunar_info.dart';
import '../../domain/shift_rotation.dart';

/// 快照格式版本。原生按它判断能不能解析 —— 对不上就按「无快照」走降级态。
///
/// v2（2026-09-20）：窗口从「今天起 14 天」改成「按月对齐的绝对窗口」；
/// `days[]` 删 `abbrInk`、增 `lunarShort` / `lunarIsHoliday`；顶层增 `weekdays` / `months`。
/// 换版本号是有意的：升级时旧快照一律解不开 → 渲染占位态，直到第一次 push。
const int kWidgetSnapshotVersion = 2;

/// 窗口的**最大**天数。真正用多少由 [widgetWindow] 算：
/// 「本月 + 下月」最多 62 天，再加本周一到月末最多 6 天补齐 → 68。
const int kWidgetSnapshotMaxDays = 68;

/// 快照窗口：`[min(本月 1 日, 今天所在周的周一), 下月最后一天]`。
///
/// 为什么不是「今天起 N 天」：月历要本月完整 + 前后补齐格，且**跨月那一刻**
/// （10 月 1 日零点）原生手上必须有 10 月的数据 —— 跨天刷新只能对表右移，
/// 变不出新月份，窗口里不预装下月的话桌面就是一张空月。
/// 起点取「本周一」是为了 4×1 本周条（今天可能是周日，本周一在 6 天前）。
({DateTime from, DateTime to}) widgetWindow(DateTime now) {
  final today = dateOnly(now); // UTC 纯日期，年月日即本地日历日
  final monthStart = DateTime(today.year, today.month, 1);
  final weekMonday =
      DateTime(today.year, today.month, today.day - (today.weekday - 1));
  final from = monthStart.isBefore(weekMonday) ? monthStart : weekMonday;
  // `DateTime(y, m + 2, 0)` = 下个月的最后一天（Dart 会把 day=0 归一成上月末）。
  final to = DateTime(today.year, today.month + 2, 0);
  return (from: from, to: to);
}

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

  final window = widgetWindow(now);
  final dayCount = dayNumber(window.to) - dayNumber(window.from) + 1;
  assert(dayCount <= kWidgetSnapshotMaxDays, '窗口算出来 $dayCount 天，超出上限');

  for (var i = 0; i < dayCount; i++) {
    // 本地日历日。`window.from` 是 UTC 纯日期取年月日重建成**本地**零点，
    // 这样下面减出来的毫秒数才落在用户所在时区的正确钟点上。
    final date = DateTime(window.from.year, window.from.month, window.from.day + i);
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

    final lunar = lunarOf(date);
    days.add({
      'day': dayNumber(date),
      'weekday': L10n.weekday(date.weekday - 1),
      'dateShort': L10n.monthDay(date),
      'hasShift': shift != null,
      'isRest': shift?.isRest ?? true,
      'shiftName': shift?.name ?? '',
      'shiftAbbr': shift?.shortLabel ?? '',
      'color': shift?.color ?? 0,
      'timeRange': timeRange,
      // 月历格子的第三行。原生不查农历（那是 Dart 侧的事），所以按日期烘焙。
      'lunarShort': lunar.shortLabel,
      'lunarIsHoliday': lunar.isLegalHoliday,
      // v1 的 `abbrInk`（`AppTokens.onSolid` 算出的胶囊字色）在本版**删掉**：
      // 胶囊底从实心班次色改成 14% 淡染后，`onSolid` 给的黑/白字在淡染底上是错的
      // （深色班次的淡染底接近白，它却会给白字）。字色改走原生 `wg_ink_*`。
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
          // 兜底走既有的 L10n.defaultTeamName —— 它自己的注释写着「唯一来源…
          // 免得两处各写一份、英文界面下漏出中文」。不要学 App 的信息卡内联写
          // `i + 1` + 中英三元（那是既有的疤，别再抄一份）。
          : L10n.defaultTeamName(i);
      crews.add({'name': name, 'abbr': t.shortLabel, 'color': t.color});
    }
  }
  final todayCard = {
    'day': dayNumber(todayDate),
    'lunarShort': lunar.shortLabel,
    'lunarIsHoliday': lunar.isLegalHoliday,
    'lunarFull': lunar.fullDescription,
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
    'weekdays': List.generate(7, L10n.weekday),
    'months': _monthsInWindow(window.from, window.to),
    'todayCard': todayCard,
  };
}

/// 窗口覆盖到的月份（含起止月），升序。月历标题行按「年-月」查它。
List<Map<String, Object?>> _monthsInWindow(DateTime from, DateTime to) {
  final out = <Map<String, Object?>>[];
  var y = from.year, m = from.month;
  while (y < to.year || (y == to.year && m <= to.month)) {
    out.add({'y': y, 'm': m, 'title': L10n.yearMonth(DateTime(y, m))});
    if (++m > 12) {
      m = 1;
      y++;
    }
  }
  return out;
}
