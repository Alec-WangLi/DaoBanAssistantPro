// app/lib/features/stats/stats_screen.dart
//
// 统计页：按月 / 按年浏览排班工时、休息、请假、加班等。
//
// 它是一个**只读**页面：所有数字都从 `ScheduleChain` + 日级 extras 现算
// （`domain/shift_stats.dart`），没有统计表、也没有缓存。年视图最多 366 天 ×
// 两次查表，量级可以忽略；真要缓存也只能用 `chain.rotationKey`（不是 `cacheKey`，
// 那个不含按天覆盖，v0.10.20 栽过）。
//
// v0.13.17 起：班次分布改环形图、加出勤构成条、年视图加月度柱状图、底部加
// 「统计口径」说明，并支持按自定义区间 / 字段导出 CSV（`export_sheet.dart`）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/clock.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/haptics.dart';
import '../../core/l10n.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/widgets/glass_loading.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../data/app_repository.dart';
import '../../domain/day_extra.dart';
import '../../domain/schedule_chain.dart';
import '../../domain/shift_rotation.dart';
import '../../domain/shift_stats.dart';
import '../backup/backup_io.dart';
import 'export_sheet.dart';
import 'stats_charts.dart';
import 'stats_period_header.dart';
import 'stats_section_header.dart';
import 'stats_summary.dart';

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

  /// 底部「统计口径」卡展开状态。默认收起：它是解释，不是正文。
  bool _showMethod = false;

  @override
  void initState() {
    super.initState();
    final n = appNow();
    _month = DateTime(n.year, n.month, 1);
    _year = n.year;
    _yearMode = widget.initialYearMode;
  }

  /// 期间切换的**唯一入口**：翻月 / 翻年 / 「今天」/ 两个选择器全部汇到这里。
  ///
  /// **触觉挂在这一处**（与日历的 `_setMonth` 同一条裁决）：一次期间变化恰好
  /// 一记 `select()`。箭头、选择器、今天各自都不许再补 —— 两处都挂就是一次
  /// 操作两响（D6）。没变（例如在 10 月点「本月」、或选择器里选回原月份）
  /// 就什么都不发生，也不震：那一步没携带任何新信息。
  void _setPeriod({DateTime? month, int? year}) {
    final changed = year != null ? year != _year : month != _month;
    if (!changed) return;
    setState(() {
      if (year != null) {
        _year = year;
      } else {
        _month = month!;
      }
    });
    Haptics.select();
  }

  void _prev() {
    if (_yearMode) {
      _setPeriod(year: _year - 1);
    } else {
      _setPeriod(month: DateTime(_month.year, _month.month - 1, 1));
    }
  }

  void _next() {
    if (_yearMode) {
      _setPeriod(year: _year + 1);
    } else {
      _setPeriod(month: DateTime(_month.year, _month.month + 1, 1));
    }
  }

  void _today() {
    final n = appNow();
    final month = DateTime(n.year, n.month, 1);
    if (month == _month && n.year == _year) return;
    setState(() {
      _month = month;
      _year = n.year;
    });
    Haptics.select();
  }

  Future<void> _pickMonth() async {
    final picked = await showGlassMonthPicker(context, initialMonth: _month);
    if (picked == null || !mounted) return;
    _setPeriod(month: DateTime(picked.year, picked.month, 1));
  }

  /// 年视图里点年份：弹年份滚轮。从前这里只有 ‹ › 两条路，跨十年要点十下。
  Future<void> _pickYear() async {
    final picked = await showGlassYearPicker(context, initialYear: _year);
    if (picked == null || !mounted) return;
    _setPeriod(year: picked);
  }

  void _switchMode(int index) {
    setState(() {
      _yearMode = index == 1;
      if (_yearMode) _year = _month.year;
    });
  }

  /// 年视图里点某个月：切回月视图并落到那个月。与 `_setPeriod` 同一口径 ——
  /// 一次期间变化一记 `select()`（从前这里是裸 `setState`，买了震动却没卖）。
  void _drillToMonth(int month) {
    setState(() {
      _yearMode = false;
      _month = DateTime(_year, month, 1);
    });
    Haptics.select();
  }

  @override
  Widget build(BuildContext context) {
    final now = appNow();
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
                  StatsPeriodHeader(
                    yearMode: _yearMode,
                    title: _yearMode
                        ? L10n.statsYearLabel(_year)
                        : L10n.yearMonth(_month),
                    onModeChanged: _switchMode,
                    onPrev: _prev,
                    onNext: _next,
                    onPickPeriod: _yearMode ? _pickYear : _pickMonth,
                    onExport: _openExport,
                    onToday: _today,
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  StatsSummaryCard(
                    stats: stats,
                    hasSchedule: chain != null && chain.hasAnySchedule,
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  StatsMetricGrid(stats: stats),
                  const SizedBox(height: AppTokens.spaceMd),
                  _compositionCard(context, stats),
                  if (_leaveKinds(stats).isNotEmpty) ...[
                    const SizedBox(height: AppTokens.spaceMd),
                    _leaveKindsCard(context, stats),
                  ],
                  const SizedBox(height: AppTokens.spaceMd),
                  _distributionCard(context, chain, stats),
                  if (_yearMode) ...[
                    const SizedBox(height: AppTokens.spaceMd),
                    _monthlyHoursCard(context, months,
                        now.year == _year ? now.month : null),
                    const SizedBox(height: AppTokens.spaceMd),
                    _monthsCard(context, months),
                  ],
                  const SizedBox(height: AppTokens.spaceMd),
                  _factsCard(context, stats),
                  const SizedBox(height: AppTokens.spaceMd),
                  _methodCard(context),
                  ..._notes(context, stats),
                ],
              ),
            ),
    );
  }

  /// 打开导出弹层。默认区间是**当前正在看的那一段**，弹层里可以改。
  ///
  /// 弹层只拼 CSV；落盘与系统「保存到」在这里做（`BackupIo` 走的是备份那条
  /// SAF 通道）。生成的是临时文件 —— 用户选完位置后系统会复制过去。
  ///
  /// **默认区间不越过今天**（issue #13，2026-11-28）：看当月时这一段本来就是
  /// 「到月底」，而月底是未来 —— 导出的是已经发生的事，未来那几天既没数据，
  /// 用户也说「计划赶不上变化，不准」。区间整个落在未来（翻到了下个月）时两头
  /// 一起夹到今天，别让 `from > to`。
  Future<void> _openExport() async {
    final periodFrom = _yearMode ? DateTime(_year, 1, 1) : _month;
    final periodTo = _yearMode
        ? DateTime(_year, 12, 31)
        : DateTime(_month.year, _month.month + 1, 0);
    final today = dateOnly(appNow());
    final to = periodTo.isAfter(today) ? today : periodTo;
    final from = periodFrom.isAfter(to) ? to : periodFrom;
    final result = await showStatsExportSheet(
      context,
      chain: ref.read(activeScheduleProvider).valueOrNull?.chain,
      extras: ref.read(dayExtrasProvider).valueOrNull ?? const {},
      from: from,
      to: to,
    );
    if (result == null || !mounted) return;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${result.fileName}');
      await file.writeAsString(result.csv, encoding: utf8);
      final uri = await BackupIo.save(
        suggestedName: result.fileName,
        sourcePath: file.path,
        mime: 'text/csv',
      );
      if (!mounted) return;
      showGlassSnack(
        context,
        uri == null
            ? L10n.exportCancelled
            : '${L10n.exportDone} · ${result.rowCount}',
      );
    } catch (_) {
      if (!mounted) return;
      showGlassSnack(context, L10n.exportFailed,
          icon: Icons.error_outline);
    }
  }

  /// 出勤构成：上班 / 休息 / 整天请假 / 无班次 / 未排班。
  ///
  /// 这五项**刚好把区间里的每一天分完**（判据见 `shift_stats.dart` 的逐日分支），
  /// 所以按天数画 100% 条不会重叠、也不会漏。
  Widget _compositionCard(BuildContext context, ShiftStats stats) {
    final primary = Theme.of(context).colorScheme.primary;
    final segments = <CompositionSegment>[
      CompositionSegment(
          label: L10n.statsWorkDays,
          count: stats.workDays,
          color: primary),
      CompositionSegment(
          label: L10n.statsRestDays,
          count: stats.restDays,
          color: AppTokens.inkMuted(context)),
      CompositionSegment(
          label: L10n.statsFullLeave,
          count: stats.fullLeaveDays,
          color: AppTokens.chartLeave),
      CompositionSegment(
          label: L10n.statsBlankDays,
          count: stats.blankDays,
          color: AppTokens.chartBlank),
      CompositionSegment(
          label: L10n.statsUnscheduled,
          count: stats.unscheduledDays,
          color: AppTokens.chartUnscheduled),
    ];
    return GlassTile(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatsSectionHeader(
            icon: Icons.percent,
            title: L10n.statsComposition,
            iconColor: primary,
          ),
          const SizedBox(height: AppTokens.spaceMd),
          CompositionBar(segments: segments),
        ],
      ),
    );
  }

  /// 请假构成（按类型）。没选类型的旧记录归到「未分类」。
  List<MapEntry<String, int>> _leaveKinds(ShiftStats stats) {
    final entries = stats.leaveMinutesByKind.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  Widget _leaveKindsCard(BuildContext context, ShiftStats stats) {
    final muted = AppTokens.inkMuted(context);
    final entries = _leaveKinds(stats);
    final maxMinutes = entries.isEmpty ? 0 : entries.first.value;
    return GlassTile(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatsSectionHeader(
            icon: Icons.event_note_outlined,
            title: L10n.statsLeaveKinds,
            iconColor: AppTokens.chartLeave,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceSm),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: AppTokens.spaceSm,
                        height: AppTokens.spaceSm,
                        decoration: const BoxDecoration(
                            color: AppTokens.chartLeave, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: AppTokens.gapIconText),
                      Expanded(
                        child: Text(
                          e.key == kUnspecifiedLeaveKind
                              ? L10n.statsLeaveUnspecified
                              : (L10n.leaveKindLabel(e.key) ?? e.key),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTokens.rowSecondary.copyWith(color: muted),
                        ),
                      ),
                      Text(
                        L10n.durationText(e.value),
                        style: AppTokens.labelSecondary
                            .copyWith(fontFeatures: AppTokens.tabularFigures),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceXs),
                  // 占比细条：同一档琥珀色只按长度说话，不按类型再分颜色。
                  ClipRRect(
                    borderRadius: AppTokens.pillOf(AppTokens.spaceXs),
                    child: SizedBox(
                      height: AppTokens.spaceXs,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ColoredBox(
                                color: AppTokens.chartTrack(context)),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: maxMinutes == 0
                                  ? 0
                                  : e.value / maxMinutes,
                              heightFactor: 1,
                              child: const ColoredBox(
                                  color: AppTokens.chartLeave),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.spaceSm),
            child: StatsSectionHeader(
              icon: Icons.calendar_month_outlined,
              title: L10n.statsByMonth,
              iconColor: Theme.of(context).colorScheme.primary,
            ),
          ),
          for (var m = 1; m <= 12; m++)
            GlassPressable(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _drillToMonth(m),
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
                              style: AppTokens.labelStrong.copyWith(
                                  fontFeatures: AppTokens.tabularFigures),
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

  /// 年视图的 12 根柱。只展示，点月份走下面那张列表（D15：12 根柱挤不出一颗
  /// 44dp 的命中区）。
  Widget _monthlyHoursCard(
      BuildContext context, List<ShiftStats> months, int? highlightIndex) {
    final muted = AppTokens.inkMuted(context);
    final positive = [for (final m in months) m.totalMinutes]
        .where((v) => v > 0)
        .toList();
    final average = positive.isEmpty
        ? 0
        : (positive.reduce((a, b) => a + b) / positive.length).round();
    return GlassTile(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatsSectionHeader(
            icon: Icons.bar_chart_rounded,
            title: L10n.statsMonthlyHours,
            iconColor: Theme.of(context).colorScheme.primary,
            // 均值虚线的口径就写在这一行：只统计工时 > 0 的月份（空月不拉低均值）。
            trailing: positive.isEmpty
                ? null
                : Text(
                    '${L10n.statsAverage} ${L10n.durationText(average)}',
                    style: AppTokens.microText.copyWith(
                      color: muted,
                      fontFeatures: AppTokens.tabularFigures,
                    ),
                  ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          MonthlyHoursBars(
            minutes: [for (final m in months) m.totalMinutes],
            highlightIndex: highlightIndex,
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
    final total = entries.fold<int>(0, (a, e) => a + e.value);
    final donutEntries = [
      for (final e in entries)
        DonutEntry(
          label: e.key,
          count: e.value,
          color: Color(colors[e.key] ?? AppTokens.chartBlank.toARGB32()),
        ),
    ];
    final legend = entries.map((e) {
      return Padding(
        padding: const EdgeInsets.only(top: AppTokens.gapHair),
        child: Row(
          children: [
            Container(
              width: AppTokens.spaceSm,
              height: AppTokens.spaceSm,
              decoration: BoxDecoration(
                color: Color(colors[e.key] ?? AppTokens.chartBlank.toARGB32()),
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
            const SizedBox(width: AppTokens.spaceXs),
            Text(
              '${L10n.statsDays(e.value)} · '
              '${statsPercentText(e.value, total)}',
              style: AppTokens.microText.copyWith(
                color: muted,
                fontFeatures: AppTokens.tabularFigures,
              ),
            ),
          ],
        ),
      );
    }).toList();

    return GlassTile(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatsSectionHeader(
            icon: Icons.donut_small,
            title: L10n.statsBreakdown,
            iconColor: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          if (entries.isEmpty)
            Text(L10n.statsNoSchedule,
                style: AppTokens.rowSecondary.copyWith(color: muted))
          else
            LayoutBuilder(
              builder: (context, c) {
                // 窄屏上下排（环居中、图例在下面），宽屏左右排。两档都留够
                // 图例的宽度 —— 班次简称后面还要放天数和占比。
                if (c.maxWidth < 360) {
                  return Column(
                    children: [
                      Center(
                        child: ShiftDonut(
                          entries: donutEntries,
                          centerValue: L10n.statsDays(stats.workDays),
                          centerLabel: L10n.statsWorkDaysCenter,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      ...legend,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ShiftDonut(
                      entries: donutEntries,
                      centerValue: L10n.statsDays(stats.workDays),
                      centerLabel: L10n.statsWorkDaysCenter,
                    ),
                    const SizedBox(width: AppTokens.spaceLg),
                    Expanded(child: Column(children: legend)),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _factsCard(BuildContext context, ShiftStats stats) {
    return GlassTile(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatsSectionHeader(
            icon: Icons.insights,
            title: L10n.statsFacts,
            iconColor: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _factRow(context, Icons.celebration_outlined, L10n.statsHolidayWork,
              L10n.statsDays(stats.holidayWorkDays)),
          _factRow(context, Icons.nightlight_outlined, L10n.statsNightShifts,
              L10n.statsDays(stats.nightShiftDays)),
          _factRow(context, Icons.trending_up, L10n.statsLongestWork,
              L10n.statsDays(stats.longestWorkStreak)),
          _factRow(context, Icons.trending_down, L10n.statsLongestRest,
              L10n.statsDays(stats.longestRestStreak)),
        ],
      ),
    );
  }

  Widget _factRow(
      BuildContext context, IconData icon, String label, String value) {
    final muted = AppTokens.inkMuted(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.gapHair),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.gapHair),
            child: AppIcon(icon, size: AppTokens.iconSm, color: muted),
          ),
          const SizedBox(width: AppTokens.gapIconText),
          Expanded(
            child: Text(label,
                maxLines: 2, style: AppTokens.rowSecondary.copyWith(color: muted)),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Text(value,
              style: AppTokens.labelStrong
                  .copyWith(fontFeatures: AppTokens.tabularFigures)),
        ],
      ),
    );
  }

  /// 底部「统计口径」卡：默认收起，点开逐条列规则。
  Widget _methodCard(BuildContext context) {
    final muted = AppTokens.inkMuted(context);
    return GlassTile(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassPressable(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showMethod = !_showMethod),
              // 整行补到 44 的命中区（D15）—— 从前只有一行字高，点起来偏窄。
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  key: const Key('stats-method-toggle'),
                  children: [
                    AppIcon(Icons.info_outline,
                        size: AppTokens.iconSm, color: muted),
                    const SizedBox(width: AppTokens.gapIconText),
                    Expanded(
                      child: Text(L10n.statsMethod,
                          style: AppTokens.titleStrong),
                    ),
                    const SizedBox(width: AppTokens.spaceSm),
                    AnimatedRotation(
                      turns: _showMethod ? 0.5 : 0,
                      duration: AppTokens.durFast,
                      child: AppIcon(Icons.expand_more,
                          size: AppTokens.iconSm, color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showMethod) ...[
            const SizedBox(height: AppTokens.spaceSm),
            for (final line in L10n.statsMethodLines)
              Padding(
                padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                child: Text(
                  '· $line',
                  style: AppTokens.microText.copyWith(color: muted),
                ),
              ),
          ],
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
