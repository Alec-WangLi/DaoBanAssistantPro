// app/lib/features/stats/stats_charts.dart
//
// 统计页的三张图。**纯 CustomPainter / 布局拼装，不引第三方图表库** ——
// 这套界面的玻璃、圆角、字号全走 AppTokens，图表也得跟着同一套走。
//
// 三张图的分工：
//   · [ShiftDonut]      班次分布：每段一个班次色（与信息卡、弹层用的是同一颗色）。
//   · [CompositionBar]  出勤构成：上班 / 休息 / 整天请假 / 无班次 / 未排班。
//                       这五项**刚好把每一天分完**，不重叠（判据见 `shift_stats.dart`）。
//   · [MonthlyHoursBars] 年视图的 12 个月工时柱。只展示，不挂点击 —— 12 根柱
//                       挤在一行里，每根都撑不到 44dp 命中区（D15），点月份仍走
//                       下面那张 12 行列表。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/l10n.dart';

/// 环形图的一段。
class DonutEntry {
  const DonutEntry({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;
}

/// 班次分布环形图。中心放一个大数字 + 一行小字。
///
/// 入场是**一次性**扫开（`durSlow`）：不做循环动画，切月时也不重播 ——
/// 那会让每次翻月都像加载。
class ShiftDonut extends StatelessWidget {
  const ShiftDonut({
    super.key,
    required this.entries,
    required this.centerValue,
    required this.centerLabel,
  });

  final List<DonutEntry> entries;
  final String centerValue;
  final String centerLabel;

  static const double _size = 132;

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<int>(0, (a, e) => a + e.count);
    final summary = entries.map((e) => '${e.label} ${e.count}').join('，');
    return Semantics(
      label: summary,
      child: SizedBox(
        width: _size,
        height: _size,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : AppTokens.durSlow,
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size.square(_size),
                painter: _DonutPainter(
                  entries: entries,
                  total: total,
                  progress: t,
                  ring: AppTokens.chartRing,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.space2xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(centerValue,
                          style: AppTokens.sectionTitle),
                    ),
                    const SizedBox(height: AppTokens.gapHair),
                    Text(
                      centerLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTokens.microText
                          .copyWith(color: AppTokens.inkMuted(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.entries,
    required this.total,
    required this.progress,
    required this.ring,
  });

  final List<DonutEntry> entries;
  final int total;
  final double progress;
  final double ring;

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || progress <= 0) return;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ring
      ..strokeCap = StrokeCap.butt;
    // 段与段之间留一道很窄的缝：不留的话同色相邻的分不清边界，留宽了又会
    // 在「某一段只有一天」时把它吃掉。
    final gap = entries.length > 1 ? 0.025 : 0.0;
    var start = -math.pi / 2;
    for (final e in entries) {
      final sweep = 2 * math.pi * (e.count / total) * progress;
      if (sweep <= 0) continue;
      final g = math.min(gap, sweep * 0.4);
      paint.color = e.color;
      canvas.drawArc(
        rect.deflate(ring / 2),
        start + g / 2,
        sweep - g,
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.total != total ||
      old.progress != progress ||
      old.ring != ring ||
      old.entries != entries;
}

/// 「出勤构成」的一段。
class CompositionSegment {
  const CompositionSegment({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;
}

/// 100% 分段条 + 图例。五项刚好把每一天分完，所以按天数的比例画即可。
class CompositionBar extends StatelessWidget {
  const CompositionBar({super.key, required this.segments});

  final List<CompositionSegment> segments;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<int>(0, (a, s) => a + s.count);
    final muted = AppTokens.inkMuted(context);
    final visible = segments.where((s) => s.count > 0).toList();
    if (total <= 0 || visible.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.radiusS),
          child: SizedBox(
            height: AppTokens.spaceMd,
            child: Row(
              // **必须 stretch**：横向 Row 的交叉轴是竖向，默认给子件的是松高度，
              // 而 `ColoredBox` 没有子件、松高度下会缩成 0 高 —— 条子整个看不见
              // （出图第一版就是这样：卡片中间一大片空白）。
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in visible)
                  Expanded(
                    flex: s.count,
                    child: ColoredBox(color: s.color),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Wrap(
          spacing: AppTokens.spaceMd,
          runSpacing: AppTokens.spaceXs,
          children: [
            for (final s in visible)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: AppTokens.spaceSm,
                    height: AppTokens.spaceSm,
                    decoration:
                        BoxDecoration(color: s.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: AppTokens.gapIconText),
                  Text(
                    '${s.label} ${L10n.statsDays(s.count)}',
                    style: AppTokens.microText.copyWith(color: muted),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// 年视图的 12 根月度工时柱。
class MonthlyHoursBars extends StatelessWidget {
  const MonthlyHoursBars({super.key, required this.minutes});

  /// 12 个月的实际在岗分钟数（下标 0 = 1 月）。
  final List<int> minutes;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted = AppTokens.inkMuted(context);
    final max = minutes.fold<int>(0, (a, m) => m > a ? m : a);
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 12; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.gapHair),
                child: Column(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor:
                              max == 0 ? 0 : minutes[i] / max,
                          child: Container(
                            decoration: BoxDecoration(
                              color: primary,
                              borderRadius: BorderRadius.circular(
                                  AppTokens.spaceXs),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceXs),
                    Text(
                      '${i + 1}',
                      maxLines: 1,
                      style: AppTokens.microText.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
