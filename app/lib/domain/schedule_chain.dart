// app/lib/domain/schedule_chain.dart
//
// 多排班表按日期衔接：把「某天归哪套方案」这件事收敛到**一个**地方。
//
// 为什么单独一个文件：这条解析规则只要有两份实现，就迟早对不上，而症状是
// 「某几天显示成另一套班表的班」—— 不报错，且只有翻到那一天才看得见。
//
// 两条贯穿本文件的纪律：
//  · **日期比较一律走 `dayNumber`**（自 epoch 的天数）。透进来的日子可能是
//    UTC 纯日期、也可能带本地时分，而 `from`/`to` 由 drift 读回来是**本地**
//    DateTime —— 直接比 `DateTime` 在东八区就差 8 小时，边界那天静默判错。
//  · **三种「空」不能混**：两端都空 = 不参与衔接；只有 `to` = 不限起点；
//    只有 `from` = 一直持续。
library;

import 'shift_rotation.dart';

/// 时间线上的一段（**闭区间**，两端都可留空）。
class ScheduleSpan {
  const ScheduleSpan(
      {this.id, this.scheduleId, required this.schedule, this.from, this.to});

  /// **段**的行 id（`schedule_span_rows.id`）。
  ///
  /// 编辑 / 删除 / `conflictingSpans` 判「是不是自己」都用它。
  final int? id;

  /// **方案**的行 id（`shift_schedule_rows.id`）。[ScheduleChain.scheduleIdOn]
  /// 返回的是它 —— 按天改班的覆盖表主键是 `{scheduleId, day}`，要的是**方案**
  /// 的 id，不是段的。
  ///
  /// **两个 id 别搞混**：混了的症状是覆盖记到错的方案名下（不生效、也不报错）。
  final int? scheduleId;

  final ShiftSchedule schedule;

  /// null = 不限起点（一直往前）。**与「不参与衔接」不是一回事** —— 两端都空的
  /// 方案根本不会出现在 [ScheduleChain.spans] 里。
  final DateTime? from;

  /// null = 一直持续下去。
  final DateTime? to;

  /// 这一天在不在这个时段里。**闭区间：两端当天都算。**
  bool covers(DateTime day) {
    final n = dayNumber(day);
    if (from != null && n < dayNumber(from!)) return false;
    if (to != null && n > dayNumber(to!)) return false;
    return true;
  }

  @override
  String toString() => 'ScheduleSpan(${schedule.name}, $from..$to)';
}

/// 「某天归哪套方案」的**唯一**解析处（spec §2 ②）。
///
/// 规则：
///   1. 在 [spans] 里挑**覆盖那天、且起点最晚**的那一条；起点并列时取 id 大的
///      （后建的那套赢）。
///   2. 一条都没有 → [fallback]（当前方案，管所有没被时段覆盖的日子）。
///
/// **起点为空的按「一直往前」算**，也就是最不晚的那一档 —— 所以「～6月30日」
/// 这种只设终点的时段，会把 6/30 之前全占了，但输给任何有明确起点的段。
///
/// ---- 关于「重叠」----
///
/// **段之间不重叠是界面保证的**（保存前用 [conflictingSpans] 拦下 + 迁移规整过），
/// 所以正常情况下上面第 1 条只有唯一解。实现里那条「起点最晚的赢」因此**退化成
/// 一条防御性的 tiebreak**，只在库里真有重叠（脏数据 / 手工改库）时才会用到；
/// 留着它而不是「取列表里第一个」，是因为后者会让同一条数据换一次装配顺序就换个
/// 答案 —— 那是另一种静默的不确定。
///
/// **别把它的存在读成「重叠是允许的」**（v0.9.12 就是这么做的，代价是用户设了
/// 两套都占 9 月、得到其中一套还说不出为什么）。用户可见的语义已经是唯一解。
class ScheduleChain implements ShiftSource {
  const ScheduleChain({this.spans = const [], this.fallback, this.fallbackId});

  /// 参与衔接的方案（设了任一端时段的那些）。
  final List<ScheduleSpan> spans;

  /// 当前方案（`isCurrent`）。**老库全靠它**：两列都是 null 时 [spans] 为空，
  /// 每天都落到这里，行为与从前一字不差。
  final ShiftSchedule? fallback;

  /// 兜底那套方案的**行 id**。`ShiftSchedule` 是领域模型、不带 id，所以只能由
  /// 装配方（`assembleSchedules`）把它一起递进来。写按天覆盖要用（见 [scheduleIdOn]）。
  final int? fallbackId;

  /// 那天归哪套方案。
  ///
  /// 返回 null 只有一种情况：**那天没有被任何段覆盖，而「其余时间」是「无」**
  /// （用户明确设成了无，或者是还没有任何方案的空白库）—— 那时日历上那些天就是
  /// 没有排班。
  ShiftSchedule? scheduleOn(DateTime day) => _resolve(day).$1;

  /// 那天归哪套方案的**行 id**。
  ///
  /// 写按天改班的覆盖必须用它，**不能用「当前方案 id」**：覆盖表的主键是
  /// `{scheduleId, day}`，把属于另一套方案的那天记在当前方案名下 —— 那条覆盖
  /// 既不会生效、也不会报错，用户看到的是「改了班、日历纹丝不动」。
  /// 老库没有时段时它恒等于当前方案 id，与从前完全一致。
  int? scheduleIdOn(DateTime day) => _resolve(day).$2;

  (ShiftSchedule?, int?) _resolve(DateTime day) {
    ScheduleSpan? best;
    for (final s in spans) {
      if (!s.covers(day)) continue;
      if (best == null || _startsLater(s, best)) best = s;
    }
    // 返回的是**方案**的行 id（不是段的）—— 见 `ScheduleSpan.scheduleId`。
    if (best != null) return (best.schedule, best.scheduleId);
    return (fallback, fallbackId);
  }

  @override
  ShiftClass? shiftOn(DateTime day) => scheduleOn(day)?.shiftOn(day);

  /// 链上有没有「有周期」的方案。
  ///
  /// 空白表（跟随法定节假日、`cycle` 为空）不算 —— 桌面小组件据此决定画不画
  /// 空态提示（与从前 `!schedule.isBlank` 同一口径）。**注意不能只问兜底那套**：
  /// 当前方案可能是空白表，而链上另一套排得满满当当。
  bool get hasCycle =>
      spans.any((s) => !s.schedule.isBlank) ||
      (fallback != null && !fallback!.isBlank);

  /// 这个月里有没有被**按天改班**调过的日子。
  ///
  /// 日历信息卡的定高要用：班次行尾巴上那颗「已调班」胶囊只在被改过的那天画，
  /// 而卡片是**定高**的 —— 高度必须按**月**预留，按天算的话点一天高度变一次、
  /// 上面的网格跟着抖（`info_card_metrics.dart` 整篇就在消灭这件事）。
  ///
  /// **逐天问「那天归哪套、那套有没有覆盖这天」**：一个月可能横跨两套方案，
  /// 被改过的那天可能归另一套 —— 只看兜底那套的 `dayOverrides` 会漏。
  bool monthHasOverrideHint(DateTime month) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    for (var d = 1; d <= days; d++) {
      final date = DateTime(month.year, month.month, d);
      final s = scheduleOn(date);
      if (s != null && s.dayOverrides.containsKey(dayNumber(date))) return true;
    }
    return false;
  }

  /// 信息卡定高缓存键里代表「这条链」的那一段。
  ///
  /// 少了它就会出现「改了班次名、卡片高度没跟着重算」—— 旧高度可能装不下新内容，
  /// 而卡片装不下时**只在卡内静默滚动**（最后一行被裁掉）。
  String get cacheKey => [
        for (final s in spans)
          '${s.id}|${_sourceKey(s.schedule)}|'
              '${s.from?.millisecondsSinceEpoch}|${s.to?.millisecondsSinceEpoch}',
        'f:${_sourceKey(fallback)}',
      ].join(';');

  @override
  String get label {
    final names = [for (final s in spans) s.schedule.name];
    if (fallback != null) names.add(fallback!.name);
    return names.isEmpty ? '—' : names.join(' → ');
  }
}

/// 一套方案里**会影响信息卡高度**的那些特征（组名、班次简称、是否空白表）。
String _sourceKey(ShiftSchedule? s) => s == null
    ? '-'
    : '${s.name}|${s.teamCount}|${s.ourTeamIndex}|${s.isBlank}|'
        '${s.teamNames.join("/")}|${s.classes.map((c) => c.shortLabel).join("/")}';

/// [a] 的起点是否**晚于** [b] 的起点（并列时比 id，大的赢）。
///
/// 起点为空按「一直往前」算，也就是最不晚的 —— 所以它输给任何有起点的段。
bool _startsLater(ScheduleSpan a, ScheduleSpan b) {
  final af = a.from, bf = b.from;
  if (af == null && bf == null) return (a.id ?? 0) >= (b.id ?? 0);
  if (af == null) return false;
  if (bf == null) return true;
  final c = dayNumber(af).compareTo(dayNumber(bf));
  return c != 0 ? c > 0 : (a.id ?? 0) >= (b.id ?? 0);
}

/// [self] 之外的、与它时段重叠的那些段（按起点升序）。
///
/// **重叠是不允许的**：一段代表「这段时间归这套方案」，而一个人一天不可能同时有
/// 两套班 —— 所以界面在保存前拿它拦下并点名（`L10n.spanConflicts`），而不是像
/// v0.9.12 那样允许重叠、再用「起点最晚的赢」默默选一个（那正是「设了两套都占
/// 9 月、出来的是其中一套、还说不出为什么」的根源）。
///
/// **恰好首尾相接不算重叠**（`A.to + 1 天 == B.from` 是正常的衔接）。
/// 留空端按无穷处理；两端都空（不在时间线上）的直接跳过。
List<ScheduleSpan> conflictingSpans(List<ScheduleSpan> all, ScheduleSpan self) {
  bool live(ScheduleSpan s) => s.from != null || s.to != null;
  if (!live(self)) return const [];
  final out = <ScheduleSpan>[];
  for (final s in all) {
    if (identical(s, self)) continue;
    if (s.id != null && s.id == self.id) continue;
    if (!live(s)) continue;
    if (_overlaps(self, s)) out.add(s);
  }
  out.sort(compareSpansByStart);
  return out;
}

/// 段按**起点升序**排（起点为空按「一直往前」排最前；并列按 id）。
///
/// 时间线的显示顺序、装配时的排序、以及 [conflictingSpans] 报出来的顺序都用它 ——
/// 三处必须是同一条，否则「界面上看到的顺序」与「提示里点名的那个」会对不上。
int compareSpansByStart(ScheduleSpan a, ScheduleSpan b) {
  final af = a.from, bf = b.from;
  if (af == null && bf == null) return (a.id ?? 0).compareTo(b.id ?? 0);
  if (af == null) return -1;
  if (bf == null) return 1;
  final c = dayNumber(af).compareTo(dayNumber(bf));
  return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
}

bool _overlaps(ScheduleSpan a, ScheduleSpan b) {
  // 比真实日期大得多的哨兵，够到 22 世纪（`dayNumber` 是自 epoch 的天数）。
  const int far = 1 << 40;
  final aFrom = a.from == null ? -far : dayNumber(a.from!);
  final aTo = a.to == null ? far : dayNumber(a.to!);
  final bFrom = b.from == null ? -far : dayNumber(b.from!);
  final bTo = b.to == null ? far : dayNumber(b.to!);
  return aFrom <= bTo && bFrom <= aTo;
}
