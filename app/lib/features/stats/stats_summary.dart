// app/lib/features/stats/stats_summary.dart
//
// 统计页的「实际在岗」大数字卡与四格指标卡。
//
// 从 `stats_screen.dart` 拆出来是 E14 的要求（那个文件超了 800 行），**行为与
// 文案一字未改**：主数字仍带 `Key('stats-total-hours')`，四格的数值仍走
// `L10n.statsDays` / `L10n.durationText`（`stats_screen_test` 直接读它们）。
//
// v0.13.19 的视觉改动只有两处：①四个标签前各加一颗语义色图标（图标在前）；
// ②数字用等宽字形，翻月/翻年时不跳位。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/layout.dart';
import '../../core/widgets/app_icon.dart';
import '../../domain/shift_stats.dart';

/// 「实际在岗」大数字卡。
class StatsSummaryCard extends StatelessWidget {
  const StatsSummaryCard({
    super.key,
    required this.stats,
    required this.hasSchedule,
  });

  final ShiftStats stats;
  final bool hasSchedule;

  @override
  Widget build(BuildContext context) {
    final narrow = AppLayout.of(context).isNarrow;
    final muted = AppTokens.inkMuted(context);
    return GlassTile(
      padding: EdgeInsets.all(narrow ? AppTokens.spaceMd : AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(Icons.schedule_outlined,
                  size: AppTokens.iconSm, color: muted),
              const SizedBox(width: AppTokens.gapIconText),
              Expanded(
                child: Text(L10n.statsActual,
                    style: AppTokens.rowSecondary.copyWith(color: muted)),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              L10n.durationText(stats.totalMinutes),
              key: const Key('stats-total-hours'),
              style: AppTokens.bigNumber
                  .copyWith(fontFeatures: AppTokens.tabularFigures),
            ),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            L10n.statsBreakdownLine(
                stats.normalMinutes, stats.overtimeMinutes, stats.leaveMinutes),
            maxLines: 2,
            style: AppTokens.microText.copyWith(color: muted),
          ),
          if (!hasSchedule) ...[
            const SizedBox(height: AppTokens.spaceXs),
            Text(L10n.statsNoSchedule,
                style: AppTokens.microText.copyWith(color: muted)),
          ],
        ],
      ),
    );
  }
}

/// 上班 / 休息 / 请假 / 加班四格。
class StatsMetricGrid extends StatelessWidget {
  const StatsMetricGrid({super.key, required this.stats});

  final ShiftStats stats;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted = AppTokens.inkMuted(context);
    final tiles = <(IconData, Color, String, String)>[
      (
        Icons.work_outline,
        primary,
        L10n.statsWorkDays,
        L10n.statsDays(stats.workDays)
      ),
      (
        Icons.weekend_outlined,
        muted,
        L10n.statsRestDays,
        L10n.statsDays(stats.restDays)
      ),
      (
        Icons.event_busy_outlined,
        AppTokens.chartLeave,
        L10n.statsLeave,
        L10n.durationText(stats.leaveMinutes)
      ),
      (
        Icons.more_time,
        AppTokens.chartOvertime,
        L10n.statsOvertime,
        L10n.durationText(stats.overtimeMinutes)
      ),
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
                          ? _MetricTile(tile: tiles[i + j])
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
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.tile});

  final (IconData, Color, String, String) tile;

  @override
  Widget build(BuildContext context) {
    final muted = AppTokens.inkMuted(context);
    return GlassTile(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 图标在前、标签其次、数值最重 —— 与分节标题同一套阅读顺序。
          Row(
            children: [
              AppIcon(tile.$1, size: AppTokens.iconSm, color: tile.$2),
              const SizedBox(width: AppTokens.gapIconText),
              Expanded(
                child: Text(tile.$3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTokens.microText.copyWith(color: muted)),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(tile.$4,
                style: AppTokens.sectionTitle
                    .copyWith(fontFeatures: AppTokens.tabularFigures)),
          ),
        ],
      ),
    );
  }
}
