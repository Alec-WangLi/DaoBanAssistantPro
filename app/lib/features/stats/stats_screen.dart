// app/lib/features/stats/stats_screen.dart
//
// 统计页：按月 / 按年浏览排班工时、休息、请假、加班等。
//
// 它是一个**只读**页面：所有数字都从 `ScheduleChain` + 日级 extras 现算
// （`domain/shift_stats.dart`），没有统计表、也没有缓存。年视图最多 366 天 ×
// 两次查表，量级可以忽略；真要缓存也只能用 `chain.rotationKey`（不是 `cacheKey`，
// 那个不含按天覆盖，v0.10.20 栽过）。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/layout.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/widgets/glass_loading.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_pill.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_segment.dart';
import '../../data/app_repository.dart';
import '../../domain/day_extra.dart';
import '../../domain/schedule_chain.dart';
import '../../domain/shift_rotation.dart';
import '../../domain/shift_stats.dart';
import '../calendar/schedule_timeline_sheet.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key, this.initialYearMode = false});

  /// 打开时直接进年视图 —— 只给视觉工装的屏单用（年视图有一套 12 行布局，
  /// 没有交互钩子就永远拍不到它）。生产路径一律从月视图进。
  @visibleForTesting
  final bool initialYearMode;

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  late DateTime _month;
  late int _year;
  bool _yearMode = false;

  @override
  void initState() {
    super.initState();
    final n = appNow();
    _month = DateTime(n.year, n.month, 1);
    _year = n.year;
    _yearMode = widget.initialYearMode;
  }

  void _prev() => setState(() {
        if (_yearMode) {
          _year--;
        } else {
          _month = DateTime(_month.year, _month.month - 1, 1);
        }
      });

  void _next() => setState(() {
        if (_yearMode) {
          _year++;
        } else {
          _month = DateTime(_month.year, _month.month + 1, 1);
        }
      });

  void _today() {
    final n = appNow();
    setState(() {
      _month = DateTime(n.year, n.month, 1);
      _year = n.year;
    });
  }

  Future<void> _pickMonth() async {
    final picked = await showGlassMonthPicker(context, initialMonth: _month);
    if (picked == null || !mounted) return;
    setState(() => _month = DateTime(picked.year, picked.month, 1));
  }

  void _switchMode(int index) {
    setState(() {
      _yearMode = index == 1;
      if (_yearMode) _year = _month.year;
    });
  }

  @override
  Widget build(BuildContext context) {
    final schedules = ref.watch(activeScheduleProvider);
    final extras =
        ref.watch(dayExtrasProvider).valueOrNull ?? const <int, DayExtra>{};
    final chain = schedules.valueOrNull?.chain;

    final from = _yearMode ? DateTime(_year, 1, 1) : _month;
    final to = _yearMode
        ? DateTime(_year, 12, 31)
        : DateTime(_month.year, _month.month + 1, 0);
    final stats = shiftStatsFor(
      chain: chain,
      from: from,
      to: to,
      extras: extras,
    );
    final months = _yearMode
        ? [
            for (var m = 1; m <= 12; m++)
              shiftStatsFor(
                chain: chain,
                from: DateTime(_year, m, 1),
                to: DateTime(_year, m + 1, 0),
                extras: extras,
              ),
          ]
        : const <ShiftStats>[];

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(L10n.statistics),
        ),
      ),
      body: schedules.isLoading && chain == null
          ? const GlassLoading()
          : CenteredContent(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.paddingOf(context).bottom + 24,
                ),
                children: [
                  _periodSelector(context),
                  const SizedBox(height: AppTokens.spaceMd),
                  _summaryCard(context, chain, stats),
                  const SizedBox(height: AppTokens.spaceMd),
                  _metricGrid(context, stats),
                  if (_yearMode) ...[
                    const SizedBox(height: AppTokens.spaceMd),
                    _monthsCard(context, months),
                  ],
                  const SizedBox(height: AppTokens.spaceMd),
                  _distributionCard(context, chain, stats),
                  const SizedBox(height: AppTokens.spaceMd),
                  _factsCard(context, stats),
                  ..._notes(context, stats),
                ],
              ),
            ),
    );
  }

  Widget _periodSelector(BuildContext context) {
    final title = _yearMode ? L10n.statsYearLabel(_year) : L10n.yearMonth(_month);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassSegment(
          count: 2,
          selectedIndex: _yearMode ? 1 : 0,
          onSelected: _switchMode,
          itemBuilder: (i, selected) => Center(
            child: Text(
              i == 0 ? L10n.statsMonth : L10n.statsYear,
              style: AppTokens.labelSecondary.copyWith(
                color: selected
                    ? Colors.white
                    : AppTokens.inkMuted(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Row(
          children: [
            GlassPill(
              onTap: _prev,
              child: const AppIcon(Icons.chevron_left_outlined),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: GlassPill(
                onTap: _yearMode ? null : _pickMonth,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(title, style: AppTokens.titleStrong),
                ),
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            GlassPill(
              onTap: _next,
              child: const AppIcon(Icons.chevron_right_outlined),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceSm),
        // 靠右用 Row + `mainAxisAlignment.end`，**不要用 `Align`**：`Align` 给子件
        // 的是有界宽度，而 `GlassPill` 里的 Container 带 `alignment`、在有界约束下
        // 会撑满整行（出图里那颗「本月」就这样成了一条通栏按钮）。Row 给非 flex
        // 子件无界宽度，pill 才会按内容收缩。
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            GlassPill(
              accent: true,
              onTap: _today,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppIcon(Icons.today_outlined,
                      size: AppTokens.iconMd, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    _yearMode ? L10n.statsThisYear : L10n.statsThisMonth,
                    style: AppTokens.labelStrong.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard(
      BuildContext context, ScheduleChain? chain, ShiftStats stats) {
    final narrow = AppLayout.of(context).isNarrow;
    final muted = AppTokens.inkMuted(context);
    final scheduleName = chain?.scheduleOn(appNow())?.name;
    return GlassTile(
      padding: EdgeInsets.all(narrow ? AppTokens.spaceMd : AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L10n.statsActual,
              style: AppTokens.rowSecondary.copyWith(color: muted)),
          const SizedBox(height: AppTokens.spaceXs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              L10n.durationText(stats.totalMinutes),
              key: const Key('stats-total-hours'),
              style: AppTokens.bigNumber,
            ),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            L10n.statsBreakdownLine(
                stats.normalMinutes, stats.overtimeMinutes, stats.leaveMinutes),
            maxLines: 2,
            style: AppTokens.microText.copyWith(color: muted),
          ),
          if (chain == null || !chain.hasAnySchedule) ...[
            const SizedBox(height: AppTokens.spaceXs),
            Text(L10n.statsNoSchedule,
                style: AppTokens.microText.copyWith(color: muted)),
          ],
          if (scheduleName != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            GlassPressable(
              child: GestureDetector(
                key: const Key('stats-schedule-link'),
                behavior: HitTestBehavior.opaque,
                onTap: () => showScheduleTimelineSheet(context, ref),
                child: Row(
                  children: [
                    AppIcon(Icons.calendar_month_outlined,
                        size: AppTokens.iconSm, color: muted),
                    const SizedBox(width: AppTokens.gapIconText),
                    Expanded(
                      child: Text(
                        L10n.statsUsingSchedule(scheduleName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTokens.microText.copyWith(color: muted),
                      ),
                    ),
                    AppIcon(Icons.chevron_right_outlined,
                        size: AppTokens.iconSm, color: muted),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricGrid(BuildContext context, ShiftStats stats) {
    final tiles = <(String, String)>[
      (L10n.statsWorkDays, L10n.statsDays(stats.workDays)),
      (L10n.statsRestDays, L10n.statsDays(stats.restDays)),
      (L10n.statsLeave, L10n.durationText(stats.leaveMinutes)),
      (L10n.statsOvertime, L10n.durationText(stats.overtimeMinutes)),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 520 ? 4 : 2;
        const gap = AppTokens.spaceSm;
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += cols) {
          final end = math.min(i + cols, tiles.length);
          rows.add(Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < cols; j++) ...[
                    if (j > 0) const SizedBox(width: gap),
                    Expanded(
                      child: j < end - i
                          ? _metricTile(context, tiles[i + j])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ));
        }
        return Column(children: rows);
      },
    );
  }

  Widget _metricTile(BuildContext context, (String, String) tile) {
    final muted = AppTokens.inkMuted(context);
    return GlassTile(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tile.$1,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTokens.microText.copyWith(color: muted)),
          const SizedBox(height: AppTokens.spaceXs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(tile.$2, style: AppTokens.sectionTitle),
          ),
        ],
      ),
    );
  }

  Widget _monthsCard(BuildContext context, List<ShiftStats> months) {
    final muted = AppTokens.inkMuted(context);
    return GlassTile(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd, vertical: AppTokens.spaceSm),
      child: Column(
        children: [
          for (var m = 1; m <= 12; m++)
            GlassPressable(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _yearMode = false;
                  _month = DateTime(_year, m, 1);
                }),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Text(L10n.statsMonthShort(m),
                                style: AppTokens.labelSecondary),
                          ),
                          Expanded(
                            child: Text(
                              L10n.durationText(months[m - 1].totalMinutes),
                              key: Key('stats-month-hours-$m'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTokens.labelStrong,
                            ),
                          ),
                          const SizedBox(width: AppTokens.spaceXs),
                          AppIcon(Icons.chevron_right_outlined,
                              size: AppTokens.iconSm, color: muted),
                        ],
                      ),
                      // 上班 / 休息另起一行：320 宽 + 特大 + 英文时，和工时挤一行的
                      // 那串要横溢 4px（工装当场报红）。换成两行谁都不省略。
                      Padding(
                        padding: const EdgeInsets.only(left: 44),
                        child: Text(
                          '${L10n.statsWorkDays} ${L10n.statsDays(months[m - 1].workDays)}'
                          ' · ${L10n.statsRestDays} ${L10n.statsDays(months[m - 1].restDays)}',
                          style: AppTokens.microText.copyWith(color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _distributionCard(
      BuildContext context, ScheduleChain? chain, ShiftStats stats) {
    final muted = AppTokens.inkMuted(context);
    final colors = _labelColors(chain);
    final entries = stats.classDayCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return GlassTile(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L10n.statsBreakdown, style: AppTokens.titleStrong),
          const SizedBox(height: AppTokens.spaceSm),
          if (entries.isEmpty)
            Text(L10n.statsNoSchedule,
                style: AppTokens.rowSecondary.copyWith(color: muted))
          else
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(top: AppTokens.gapHair),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Color(colors[e.key] ?? 0xFF9AA0B4),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppTokens.gapIconText),
                    Expanded(
                      child: Text(e.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTokens.rowSecondary),
                    ),
                    Text(L10n.statsDays(e.value),
                        style: AppTokens.labelSecondary),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _factsCard(BuildContext context, ShiftStats stats) {
    return GlassTile(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: Column(
        children: [
          _factRow(context, L10n.statsHolidayWork,
              L10n.statsDays(stats.holidayWorkDays)),
          _factRow(
              context, L10n.statsNightShifts, L10n.statsDays(stats.nightShiftDays)),
          _factRow(context, L10n.statsLongestWork,
              L10n.statsDays(stats.longestWorkStreak)),
          _factRow(context, L10n.statsLongestRest,
              L10n.statsDays(stats.longestRestStreak)),
        ],
      ),
    );
  }

  Widget _factRow(BuildContext context, String label, String value) {
    final muted = AppTokens.inkMuted(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.gapHair),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                maxLines: 2, style: AppTokens.rowSecondary.copyWith(color: muted)),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Text(value, style: AppTokens.labelStrong),
        ],
      ),
    );
  }

  List<Widget> _notes(BuildContext context, ShiftStats stats) {
    final muted = AppTokens.inkMuted(context);
    final lines = <String>[
      if (stats.unscheduledDays > 0)
        '${L10n.statsUnscheduled} ${L10n.statsDays(stats.unscheduledDays)}',
      if (stats.blankDays > 0)
        '${L10n.statsBlankDays} ${L10n.statsDays(stats.blankDays)}',
    ];
    return [
      if (lines.isNotEmpty) ...[
        const SizedBox(height: AppTokens.spaceSm),
        Text(lines.join(' · '),
            style: AppTokens.microText.copyWith(color: muted)),
      ],
      if (stats.blankDays > 0) ...[
        const SizedBox(height: AppTokens.spaceXs),
        Text(L10n.statsBlankHint,
            style: AppTokens.microText.copyWith(color: muted)),
      ],
      if (stats.missingTimeDays > 0) ...[
        const SizedBox(height: AppTokens.spaceXs),
        Text(L10n.statsMissingTime(stats.missingTimeDays),
            style: AppTokens.microText.copyWith(color: muted)),
      ],
    ];
  }

  /// 班次简称 → 色号。跨时段的一个月里两套方案可能有同名班次，取第一个。
  Map<String, int> _labelColors(ScheduleChain? chain) {
    final out = <String, int>{};
    void add(ShiftSchedule? s) {
      for (final c in s?.classes ?? const <ShiftClass>[]) {
        out.putIfAbsent(c.shortLabel, () => c.color);
      }
    }

    for (final s in chain?.spans ?? const <ScheduleSpan>[]) {
      add(s.schedule);
    }
    add(chain?.fallback);
    return out;
  }
}
