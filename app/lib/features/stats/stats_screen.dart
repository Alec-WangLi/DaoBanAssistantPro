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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

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
import '../../core/widgets/glass_snackbar.dart';
import '../../data/app_repository.dart';
import '../../domain/day_extra.dart';
import '../../domain/schedule_chain.dart';
import '../../domain/shift_rotation.dart';
import '../../domain/shift_stats.dart';
import '../backup/backup_io.dart';
import 'export_sheet.dart';
import 'stats_charts.dart';

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
                    _monthlyHoursCard(context, months),
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
        // 靠右用 `Row` + `mainAxisAlignment.end`，**不要用 `Wrap` / `Align`**：
        // 它们给子件的是**有界宽度**，而 `GlassPill` 里的 Container 带 `alignment`、
        // 在有界约束下会撑满整行（出图里那颗「导出」就这样成了一条通栏按钮，
        // 2026-11-17 出图当场看见）。Row 给非 flex 子件无界宽度，pill 才会按内容
        // 收缩；窄屏（<360）把「导出」的文字也收掉，只留图标 —— 与「今天」同理。
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Tooltip(
              message: L10n.statsExport,
              child: GlassPill(
                onTap: _openExport,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(Icons.file_download_outlined,
                        size: AppTokens.iconMd,
                        color: AppTokens.inkMuted(context)),
                    if (!AppLayout.of(context).isNarrow) ...[
                      const SizedBox(width: AppTokens.spaceXs),
                      Text(L10n.statsExport, style: AppTokens.labelStrong),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
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

  /// 打开导出弹层。默认区间是**当前正在看的那一段**，弹层里可以改。
  ///
  /// 弹层只拼 CSV；落盘与系统「保存到」在这里做（`BackupIo` 走的是备份那条
  /// SAF 通道）。生成的是临时文件 —— 用户选完位置后系统会复制过去。
  Future<void> _openExport() async {
    final from = _yearMode ? DateTime(_year, 1, 1) : _month;
    final to = _yearMode
        ? DateTime(_year, 12, 31)
        : DateTime(_month.year, _month.month + 1, 0);
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

  Widget _summaryCard(
      BuildContext context, ScheduleChain? chain, ShiftStats stats) {
    final narrow = AppLayout.of(context).isNarrow;
    final muted = AppTokens.inkMuted(context);
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
          Text(L10n.statsComposition, style: AppTokens.titleStrong),
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
    return GlassTile(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L10n.statsLeaveKinds, style: AppTokens.titleStrong),
          const SizedBox(height: AppTokens.spaceSm),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.gapHair),
              child: Row(
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
                  Text(L10n.durationText(e.value),
                      style: AppTokens.labelSecondary),
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

  /// 年视图的 12 根柱。只展示，点月份走下面那张列表（D15：12 根柱挤不出一颗
  /// 44dp 的命中区）。
  Widget _monthlyHoursCard(BuildContext context, List<ShiftStats> months) {
    return GlassTile(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L10n.statsMonthlyHours, style: AppTokens.titleStrong),
          const SizedBox(height: AppTokens.spaceMd),
          MonthlyHoursBars(
            minutes: [for (final m in months) m.totalMinutes],
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
      final pct = total == 0 ? 0.0 : e.value * 100 / total;
      return Padding(
        padding: const EdgeInsets.only(top: AppTokens.gapHair),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
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
              '${pct >= 10 ? '${pct.round()}%' : '${pct.toStringAsFixed(1)}%'}',
              style: AppTokens.microText.copyWith(color: muted),
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
          Text(L10n.statsBreakdown, style: AppTokens.titleStrong),
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
              child: Row(
                key: const Key('stats-method-toggle'),
                children: [
                  AppIcon(Icons.info_outline,
                      size: AppTokens.iconSm, color: muted),
                  const SizedBox(width: AppTokens.gapIconText),
                  Expanded(
                    child: Text(L10n.statsMethod,
                        style: AppTokens.rowSecondary.copyWith(color: muted)),
                  ),
                  AppIcon(
                    _showMethod
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: AppTokens.iconSm,
                    color: muted,
                  ),
                ],
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
