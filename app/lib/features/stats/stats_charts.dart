// app/lib/features/stats/stats_charts.dart
//
// 统计页的三张图。**纯 CustomPainter / 布局拼装，不引第三方图表库** ——
// 这套界面的玻璃、圆角、字号全走 AppTokens，图表也得跟着同一套走。
//
// 三张图的分工：
//   · [ShiftDonut]       班次分布：每段一个班次色（与信息卡、弹层用的是同一颗色）。
//   · [CompositionBar]   出勤构成：上班 / 休息 / 整天请假 / 无班次 / 未排班。
//                        这五项**刚好把每一天分完**，不重叠（判据见 `shift_stats.dart`）。
//   · [MonthlyHoursBars] 年视图的 12 个月工时柱。只展示，不挂点击 —— 12 根柱
//                        挤在一行里，每根都撑不到 44dp 命中区（D15），点月份仍走
//                        下面那张 12 行列表。
//
// v0.13.19 精修（2026-11-23 用户「图表做得漂亮一点」）：
//   · 环图：加底轨、圆头分段、按**像素**算缝隙（见 [debugDonutArcs] 的注释）。
//   · 构成条：段与段之间留 2px 缝，两端由外层圆角收口。
//   · 柱图：底轨 + 顶圆角渐变柱 + 均值虚线 + 当月高亮 + 一次性生长。
// 三张图的入场动画都是**一次性**的：不循环、不随期间切换重播（重播会被读成
// 「在加载」）。`disableAnimations` 时一律零时长。
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
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

/// 百分比文案：≥10% 取整，否则保留一位小数（环图与构成条共用）。
///
/// 小于 10% 的那几档取整会变成「0%」或「1%」，把一个真实存在的班次读成不存在。
String statsPercentText(int value, int total) {
  final pct = total == 0 ? 0.0 : value * 100 / total;
  return pct >= 10 ? '${pct.round()}%' : '${pct.toStringAsFixed(1)}%';
}

/// 环图分段的角坐标（起点 + 扫过的弧度）。
///
/// 抽成纯函数是为了单测「只有一天的那段不许被缝隙吃掉」—— 这是圆头描边 + 缝隙
/// 这套几何最容易出错的地方，而它只在某几个月才出现，出图未必撞得上。
///
/// **缝隙按像素折角**：圆头描边会各自向端点外长 `ring / 2`，所以两段之间想留出
/// `gapPx` 的可见缝，弧端点的角间隙必须是 `(ring + gapPx) / 半径`。少加 `ring`
/// 那一项，两个圆头正好相切，「呼吸」实际是 0（2026-11-23 评审当场算出来的）。
/// 段太小时把缝隙夹到它自己的 45%，剩下的弧长仍能画成一粒圆点。
@visibleForTesting
List<({double start, double sweep})> debugDonutArcs({
  required List<int> counts,
  required double radius,
  required double ring,
  double gapPx = AppTokens.chartSegmentGap,
  double progress = 1,
}) {
  final total = counts.fold<int>(0, (a, c) => a + c);
  final out = <({double start, double sweep})>[];
  if (total <= 0 || progress <= 0 || radius <= 0) return out;
  final gapAngle = counts.length > 1 ? (ring + gapPx) / radius : 0.0;
  var start = -math.pi / 2;
  for (final count in counts) {
    final raw = 2 * math.pi * (count / total) * progress;
    if (raw <= 0) continue;
    final gap = math.min(gapAngle, raw * 0.45);
    out.add((start: start + gap / 2, sweep: raw - gap));
    start += raw;
  }
  return out;
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
    final visible = entries.where((e) => e.count > 0).toList();
    final total = visible.fold<int>(0, (a, e) => a + e.count);
    final summary = visible.map((e) => '${e.label} ${e.count}').join('，');
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
                  entries: visible,
                  total: total,
                  progress: t,
                  ring: AppTokens.chartRing,
                  track: AppTokens.chartTrack(context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceSm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(centerValue,
                          style: AppTokens.bigNumber
                              .copyWith(fontFeatures: AppTokens.tabularFigures)),
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
    required this.track,
  });

  final List<DonutEntry> entries;
  final int total;
  final double progress;
  final double ring;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rect = Offset.zero & size;
    final radius = (size.shortestSide - ring) / 2;
    if (radius <= 0) return;

    // 底轨：空段与一个月里只有一两天的那几档也有「槽」，总量因此读得出来。
    canvas.drawCircle(
      rect.center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring
        ..color = track,
    );
    if (total <= 0) return;

    final arcs = debugDonutArcs(
      counts: [for (final e in entries) e.count],
      radius: radius,
      ring: ring,
      progress: progress,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ring
      // 单段（例如整个月只有一种班）用平头画整圈：圆头会在 12 点方向叠出小瓣。
      ..strokeCap = entries.length > 1 ? StrokeCap.round : StrokeCap.butt;
    final arcRect = rect.deflate(ring / 2);
    for (var i = 0; i < arcs.length; i++) {
      paint.color = entries[i].color;
      canvas.drawArc(arcRect, arcs[i].start, arcs[i].sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.total != total ||
      old.progress != progress ||
      old.ring != ring ||
      old.track != track ||
      !listEquals(old.entries.map((e) => e.count).toList(),
          entries.map((e) => e.count).toList()) ||
      !listEquals(old.entries.map((e) => e.color).toList(),
          entries.map((e) => e.color).toList());
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
///
/// 段与段之间留 2px 缝、两端由外层圆角收口 —— 首尾相接的五块色块读不出「分段」，
/// 而缝隙让每一段自己立得住。
class CompositionBar extends StatelessWidget {
  const CompositionBar({super.key, required this.segments});

  final List<CompositionSegment> segments;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<int>(0, (a, s) => a + s.count);
    final muted = AppTokens.inkMuted(context);
    final visible = segments.where((s) => s.count > 0).toList();
    if (total <= 0 || visible.isEmpty) return const SizedBox.shrink();
    final summary = visible.map((s) => '${s.label} ${s.count}').join('，');
    return Semantics(
      label: summary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: AppTokens.pillOf(AppTokens.spaceMd),
            child: SizedBox(
              height: AppTokens.spaceMd,
              child: Row(
                // **必须 stretch**：横向 Row 的交叉轴是竖向，默认给子件的是松高度，
                // 而 `ColoredBox` 没有子件、松高度下会缩成 0 高 —— 条子整个看不见
                // （出图第一版就是这样：卡片中间一大片空白）。
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < visible.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppTokens.gapHair),
                    Expanded(
                      flex: visible[i].count,
                      child: ColoredBox(color: visible[i].color),
                    ),
                  ],
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
                      '${s.label} ${L10n.statsDays(s.count)} · '
                      '${statsPercentText(s.count, total)}',
                      style: AppTokens.microText.copyWith(
                        color: muted,
                        fontFeatures: AppTokens.tabularFigures,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 年视图的 12 根月度工时柱。
///
/// 底轨 + 顶圆角渐变柱 + 均值虚线（只统计工时 > 0 的月份）+ 当月高亮。
/// 一次性从基线长出来；`key` 绑分钟数组，切年才重播（切月不重播）。
class MonthlyHoursBars extends StatelessWidget {
  const MonthlyHoursBars({
    super.key,
    required this.minutes,
    this.highlightIndex,
  });

  /// 12 个月的实际在岗分钟数（下标 0 = 1 月）。
  final List<int> minutes;

  /// 当前月（1..12）：只有正在看的年份就是今年时才传。
  final int? highlightIndex;

  /// 柱区高度（画布）。数字落在 4px 栅格上（D1 的间距扫描只查间距，这里是几何）。
  static const double _chartH = 140;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted = AppTokens.inkMuted(context);
    final track = AppTokens.chartTrack(context);
    final line = AppTokens.inkFaint(context);
    final max = minutes.fold<int>(0, (a, m) => m > a ? m : a);
    final positive = minutes.where((m) => m > 0).toList();
    final average = positive.isEmpty
        ? 0.0
        : positive.reduce((a, b) => a + b) / positive.length;
    return TweenAnimationBuilder<double>(
      key: ValueKey(minutes.join(',')),
      tween: Tween<double>(begin: 0, end: 1),
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : AppTokens.durSlow,
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Column(
        children: [
          SizedBox(
            height: _chartH,
            child: CustomPaint(
              size: Size.infinite,
              painter: _BarsPainter(
                minutes: minutes,
                progress: t,
                primary: primary,
                track: track,
                line: line,
                average: average,
                highlight: highlightIndex,
                max: max,
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Row(
            children: [
              for (var i = 0; i < 12; i++)
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${i + 1}',
                      style: (i + 1 == highlightIndex
                              ? AppTokens.microStrong.copyWith(color: primary)
                              : AppTokens.microText.copyWith(color: muted))
                          .copyWith(fontFeatures: AppTokens.tabularFigures),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.minutes,
    required this.progress,
    required this.primary,
    required this.track,
    required this.line,
    required this.average,
    required this.highlight,
    required this.max,
  });

  final List<int> minutes;
  final double progress;
  final Color primary;
  final Color track;
  final Color line;
  final double average;
  final int? highlight;
  final int max;

  @override
  void paint(Canvas canvas, Size size) {
    if (minutes.length != 12 || progress <= 0) return;
    final slotW = size.width / 12;
    final barW = math.min(slotW * 0.62, 18.0);
    const radius = Radius.circular(AppTokens.spaceXs);
    final trackPaint = Paint()..color = track;
    final barPaint = Paint();
    final rects = <Rect>[];

    for (var i = 0; i < 12; i++) {
      final cx = slotW * (i + 0.5);
      final full = Rect.fromCenter(
        center: Offset(cx, size.height / 2),
        width: barW,
        height: size.height,
      );
      rects.add(full);
      canvas.drawRRect(
        RRect.fromRectAndRadius(full, radius),
        trackPaint,
      );
    }
    if (max > 0) {
      for (var i = 0; i < 12; i++) {
        final value = minutes[i];
        if (value <= 0) continue;
        final h = size.height * (value / max) * progress;
        if (h <= 0) continue;
        final rect = Rect.fromLTWH(
          rects[i].left,
          size.height - h,
          barW,
          h,
        );
        final base = i + 1 == highlight
            ? primary
            : primary.withValues(alpha: 0.55);
        barPaint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            base,
            base.withValues(alpha: base.a * 0.72),
          ],
        ).createShader(rect);
        // 顶圆角、底平：柱子是「从基线长出来的」，底部圆角会让它浮起来。
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: radius,
            topRight: radius,
          ),
          barPaint,
        );
      }
    }

    // 均值虚线画在柱体之上，否则被最高的那根盖掉一半。
    if (max > 0 && average > 0) {
      final y = size.height * (1 - average / max * progress);
      final paint = Paint()
        ..color = line
        ..strokeWidth = 1;
      const dash = 4.0;
      const step = 8.0;
      for (var x = 0.0; x < size.width; x += step) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + dash, size.width), y),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) =>
      !listEquals(old.minutes, minutes) ||
      old.progress != progress ||
      old.primary != primary ||
      old.track != track ||
      old.line != line ||
      old.average != average ||
      old.highlight != highlight ||
      old.max != max;
}
