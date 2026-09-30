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
// 若把「明天」二字烘进 days[i] 里，那么跨过一次零点、days[i] 变成今天之后，
// 那一格会自称「明天」—— 卡片理直气壮地写错，而且没有任何东西会报错。
// 所以日期固有的东西（`dateShort` / `weekday` / `timeRange`）按日期烘焙，
// 相对的三个词（今天/明天/后天）放在顶层 `labels` 里，由渲染方按当时的日期取。
library;

import '../../core/l10n.dart';
import '../../domain/lunar_info.dart';
import '../../domain/schedule_chain.dart';
import '../../domain/shift_rotation.dart';

/// 快照格式版本。原生按它判断能不能解析 —— 对不上就按「无快照」走降级态。
///
/// v2（2026-09-20）：窗口从「今天起 14 天」改成「按月对齐的绝对窗口」；
/// `days[]` 删 `abbrInk`、增 `lunarShort` / `lunarIsHoliday`；顶层增 `weekdays` / `months`。
/// 换版本号是有意的：升级时旧快照一律解不开 → 渲染占位态，直到第一次 push。
const int kWidgetSnapshotVersion = 2;

/// 窗口的**最大**天数。真正用多少由 [widgetWindow] 算：
/// 「−3 ~ +3 个月」共七个月，各自按 31 天算 → 217，再加末端那 42 格多出来的 41 天
/// 与起点补齐整周最多 6 天 = 231。取 240 留余量，由下面的断言兜住。
/// （2020–2035 逐日实算过，最坏就是 231。）
const int kWidgetSnapshotMaxDays = 240;

/// 快照窗口：`[−3月1日所在周的周一, +3月1日所在周的周一 + 41 天]`。
///
/// 为什么是**整周对齐的七个月**（v0.9.18 从三个月放宽的）：月历小组件画的是**连续的
/// 42 天**，并且能翻月 —— 那张卡能画的每一格都必须有数据，**能翻多远就等于窗口装了
/// 几个月**。放到 ±3 之后，往前能看一个季度，而且「多久不开 App 卡片才会退化」也从
/// 约一个月拉到约三个月。一条用例（`widget_snapshot_test.dart` 的「窗口覆盖…完整
/// 42 格」）把这条性质钉住了，改窗口时它会先红。
///
/// 代价只有快照 JSON 的大小（约 40–50 KB，一天约 140 字节），**协议版本不动**。
///
/// 仍然**含窗口里已经过去的天**：本周条要画得出「上周日~本周六」那种跨月的周，
/// 而翻到过去那几个月时那些天本来就是过去的。
({DateTime from, DateTime to}) widgetWindow(DateTime now) {
  final today = dateOnly(now); // UTC 纯日期，年月日即本地日历日
  // Dart 会把越界的 month 归一：month-3 = 0 → 去年 12 月，month+3 = 16 → 明年 4 月。
  final prevFirst = DateTime(today.year, today.month - 3, 1);
  final nextFirst = DateTime(today.year, today.month + 3, 1);
  final from = DateTime(
      prevFirst.year, prevFirst.month, prevFirst.day - (prevFirst.weekday - 1));
  // **终点是「下月 1 日所在周的周一 + 41 天」，不是「下月最后一天所在周的周日」**：
  // 那张卡画的是**连续 42 天**，起点是「该月 1 日所在周的周一」，而下月自己的 42 格
  // 会越过「下月最后一天所在的那个周日」。反例很好找 —— 下月是 2 月（28 天、1 日是
  // 周日）时，它的 42 格一直排到 3/8，而「2 月最后一天所在周的周日」是 3/1，
  // 差了整整一周。周一起步 42 天必然落在周日（41 mod 7 = 6），所以这里不用再对齐。
  final nextGridStart = DateTime(nextFirst.year, nextFirst.month,
      nextFirst.day - (nextFirst.weekday - 1));
  final to = DateTime(nextGridStart.year, nextGridStart.month,
      nextGridStart.day + 41);
  return (from: from, to: to);
}

/// 生成快照。纯函数：当前时刻由 [now] 传入，不读 `DateTime.now()`。
///
/// [themeMode] 是 `'system' | 'light' | 'dark'` —— **模式，不是解析结果**。
/// 把 `system` 提前解析成 light/dark 存进来，「跟随系统」就变成了「跟随生成快照
/// 那一刻的系统」，用户傍晚切深色模式要等到下次 App 启动才跟上。
///
/// [chain] 而不是 `ShiftSchedule`：窗口是一个多月，**跨时段边界是常态** —— 每天
/// 归哪套方案由链回答。派生的好处是原生侧一个字都不用改（它本来就只是照着
/// `days[]` 排版）。
Map<String, Object?> buildWidgetSnapshot({
  required ScheduleChain? chain,
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
    // 真值：空白表（跟随法定节假日）没有班次定义，这里就是 null —— 卡片上那格
    // 只画日期与农历，**不替它断言今天上不上班**（v0.9.16 用户反馈）。
    // 「这一天有没有班表在管」是另一件事，见顶层 `hasSchedule`。
    final shift = chain?.shiftOn(date);

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
      //
      // 用 `cellLabel`（≤3 字 + 省略号）而不是 `shortLabel`：月历格子与 App 的
      // 日历格子是同一种窄格子（约 40dp、11sp），原生那边是 `maxLines=1` +
      // `ellipsize=end`。喂完整名字的话，「全民国防教育日」这种 7 字节日名会被
      // 原生截成「全民…」，而 App 里的同一天写着「全民国…」—— 同一天两个界面
      // 显示得不一样，而且这一版修的正是「农历显示不全」，桌面那张卡不该漏掉。
      // （今日卡用的是 `lunarFull`，不受影响。）
      'lunarShort': lunar.cellLabel,
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
  // 「其他班组」与「有没有调过班」问的都是**今天所属的那一套** —— 跨时段之后
  // 它可能不是「当前方案」，这正是这一块要改的原因。
  final todaySchedule = chain?.scheduleOn(todayDate);
  final crews = <Map<String, Object?>>[];
  if (todaySchedule != null && !todaySchedule.isBlank) {
    for (var i = 0; i < todaySchedule.teamCount; i++) {
      if (i == todaySchedule.ourTeamIndex) continue; // 只看别人
      final t = todaySchedule.teamShift(i, todayDate);
      if (t == null) continue;
      final name = i < todaySchedule.teamNames.length
          ? todaySchedule.teamNames[i]
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
    'adjusted':
        todaySchedule?.dayOverrides.containsKey(dayNumber(todayDate)) ?? false,
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
    // 「链上有没有**任何一套在用**的方案」—— 空白表（跟随法定节假日）也算，
    // 它整月都画得出「上班 / 休息」。原先问的是 `hasCycle`（「有没有班次可挑」，
    // 那是长按拖选与「调整班次」的闸门口径），于是只有一套法定班次的人，桌面上
    // 写着「还没有排班，点一下去设置」（2026-09-30 用户反馈的同一类错）。
    'hasSchedule': chain?.hasAnySchedule ?? false,
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
