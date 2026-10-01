import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../glass/glass.dart';
import '../glass/liquid_lens.dart';
import '../glass/liquid_lens_metrics.dart';
import '../haptics.dart';
import '../motion.dart';

/// 勾的路径（在 [size]×[size] 的方框里）。**纯函数**，好在用例里直接量长度。
Path checkMarkPath(double size) => Path()
  ..moveTo(size * 0.26, size * 0.52)
  ..lineTo(size * 0.44, size * 0.69)
  ..lineTo(size * 0.75, size * 0.33);

/// 勾「描到一半」的那一段。[progress] 0 = 一笔没画（空路径）、1 = 整笔。
///
/// **为什么是「描」不是「缩放」**：勾这个动作读起来要像**被写上去**，缩放只是弹一下。
Path checkMarkPathAt(double size, double progress) {
  final Path full = checkMarkPath(size);
  final double p = progress.clamp(0.0, 1.0);
  if (p <= 0) return Path();
  final ui.PathMetric m = full.computeMetrics().first;
  return m.extractPath(0, m.length * p);
}

/// 待办的勾：**空心环 → 主色实心 + 白勾**，两档两棵树。
///
/// 用户 2026-10-01：「我看别的设计语言都是用打勾的样式。记得咱们之前把它做成开关了，
/// 其实这不符合待办事项的逻辑：弄完之后打勾，给一个删除线表达……但是打勾的话，
/// 要融入咱们的设计理念，尤其是现在要区分液态玻璃开启和关闭两种适配状态。」
///
/// ## 两档
///
/// - **标准档**：静态玻璃圆 + `QScale` 按压，勾按进度描出来、底色同时渐变。
/// - **液态档**：一枚**会凸出来**的玻璃滴（`forCapsule`，与底栏 / 分段器 / 开关同一套
///   升程），按住时长个儿；勾与环跟着同一个 `lift` 一起放大 —— 不跟的话按住时
///   圆胀出去、圈留在原地。
///
/// **没有彩边**：控件太小，那四层光谱（照 64 高胶囊量的）摆到 28dp 上比控件还粗，
/// 与开关同一条理由（见 `LiquidLensMetrics.rimScale`）。
///
/// **勾上时的底色接近不透明**：在 28dp 上「透出来的那部分」占了大半，用
/// `accentGradient`（0.85 → 0.50）整枚会比标准档那枚实心淡一大截 —— 那正是用户
/// 这一轮报的「颜色变浅了」。底色**本身就是状态**，不能靠半透来读。
///
/// 触觉走 `Haptics.select()`，与开关同一档语义；**只在值真的变了时发一次**。
class GlassCheck extends StatefulWidget {
  const GlassCheck({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.size = 28,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;

  /// 直径。默认 28 —— 与原来那枚开关同高，待办行的高度不变。
  final double size;

  final bool enabled;

  @override
  State<GlassCheck> createState() => _GlassCheckState();
}

class _GlassCheckState extends State<GlassCheck>
    with TickerProviderStateMixin {
  /// 0 = 空环 · 1 = 勾满。**走弹簧**（过冲的那一下就是「Q 弹」）。
  late final AnimationController _t = AnimationController.unbounded(
      vsync: this, value: widget.value ? 1.0 : 0.0);

  /// 升程（液态档那枚滴凸出多少）。标准档不用它。
  late final AnimationController _lift =
      AnimationController.unbounded(vsync: this, value: 0.0);

  bool _pressed = false;

  @override
  void dispose() {
    _t.dispose();
    _lift.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GlassCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      springTo(_t, widget.value ? 1.0 : 0.0);
    }
  }

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
    springTo(_lift, v ? 1.0 : 0.0);
  }

  void _toggle() {
    if (!widget.enabled) return;
    // 「选中变了」正是这一档的语义（与开关同一处）。
    Haptics.select();
    widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent =
        widget.activeColor ?? Theme.of(context).colorScheme.primary;

    return ValueListenableBuilder<bool>(
      valueListenable: liquidGlassActive,
      builder: (BuildContext context, bool liquid, Widget? _) => liquid
          ? _buildLiquid(context, isDark, accent)
          : _buildStandard(context, isDark, accent),
    );
  }

  /// **标准档**：静态玻璃圆 + Q 弹按压。
  Widget _buildStandard(BuildContext context, bool isDark, Color accent) {
    return AnimatedBuilder(
      animation: _t,
      builder: (BuildContext context, Widget? _) {
        final double t = _t.value.clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
          onTapUp: widget.enabled
              ? (_) {
                  _setPressed(false);
                  _toggle();
                }
              : null,
          onTapCancel: () => _setPressed(false),
          child: QScale(
            pressed: _pressed,
            scale: AppTokens.pillGrow,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                painter: _CheckPainter(
                  progress: t,
                  // ⚠️ 描边**不能**用 `glassBorder(isDark)` —— 它在浅色下是
                  // 白色 @0.90，画在近白的页面上等于没画（这条真犯过）。
                  // `navBorder` 是「浅色下一道深线、深色下一道亮线」那一档。
                  ringColor: Color.lerp(
                      AppTokens.navBorder(isDark).withValues(alpha: 0.45),
                      accent.withValues(alpha: 0.55),
                      t)!,
                  fillColor: Color.lerp(
                      AppTokens.glassTint(isDark, true).first, accent, t)!,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// **液态档**：一枚按住会凸出来的玻璃滴 + 跟着一起长的勾。
  Widget _buildLiquid(BuildContext context, bool isDark, Color accent) {
    final LiquidLensMetrics metrics =
        LiquidLensMetrics.forCapsule(widget.size);
    final double d = widget.size;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_t, _lift]),
      builder: (BuildContext context, Widget? _) {
        final double t = _t.value.clamp(0.0, 1.0);
        final double lift = _lift.value.clamp(0.0, 1.0);
        final List<Color> tint = AppTokens.glassTint(isDark, true);
        // 勾上的底色**接近不透明**（见类文档）：状态由它承担，不能靠半透读。
        final double grow = (d + 2 * metrics.protrude * lift) / d;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
          onTapUp: widget.enabled
              ? (_) {
                  _setPressed(false);
                  _toggle();
                }
              : null,
          onTapCancel: () => _setPressed(false),
          // ⚠️ **必须有一个定尺的盒子**：待办那一行是个 `Row`，而 `Row` 给非 flex
          // 子项的**主轴约束是无界的** —— 直接放 `Stack` 会抛
          // 「A Stack requires bounded constraints」。滴凸出框外是允许的：
          // `SizedBox` 不裁剪、`Stack` 又是 `Clip.none`。
          child: SizedBox(
            width: d,
            height: d,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: <Widget>[
              LiquidLens(
                size: Size(d, d),
                outline: LiquidLensShape.of(
                  itemW: d,
                  capsuleH: d,
                  pad: 0,
                  centerPage: 0,
                  lift: lift,
                  velocity: 0,
                  stretch: 0,
                  // 勾没有滑动，所以彩边那道门恒为 0 —— 与规格 §4.3 一致。
                  motion: 0,
                  metrics: metrics,
                ),
                lift: lift,
                isDark: isDark,
                accent: accent,
                fill: <Color>[
                  Color.lerp(tint[0], accent.withValues(alpha: 0.95), t)!,
                  Color.lerp(tint[1], accent.withValues(alpha: 0.82), t)!,
                ],
                // 白芯在小控件上是坏的（横穿钮身的一道白线），与开关同一条判据。
                showRingCore: false,
                showRefractedEdge: false,
              ),
              // 环与勾**跟着同一个 `lift` 一起放大** —— 不跟的话，按住时圆胀出去、
              // 圈和勾留在原地。
              Transform.scale(
                scale: grow,
                child: SizedBox(
                  width: d,
                  height: d,
                  child: CustomPaint(
                    painter: _CheckPainter(
                      progress: t,
                      ringColor: Color.lerp(
                          AppTokens.navBorder(isDark).withValues(alpha: 0.45),
                          accent.withValues(alpha: 0.55),
                          t)!,
                      // 液态档的底色由那枚滴承担，环只描边。
                      fillColor: null,
                    ),
                  ),
                ),
              ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 画那枚圆：可选的底色 + 环 + 按进度描出来的勾。
class _CheckPainter extends CustomPainter {
  const _CheckPainter({
    required this.progress,
    required this.ringColor,
    required this.fillColor,
  });

  final double progress;
  final Color ringColor;

  /// 底填充。**`null` = 只描边不填底**（液态档：底色由那枚滴承担）。
  final Color? fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = math.min(size.width, size.height);
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double r = s / 2 - 0.75;

    if (fillColor != null) {
      // 玻璃底：**一点淡填充**，让「空环」在深色下也不是一个空心洞。
      canvas.drawCircle(c, r, Paint()..color = fillColor!);
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = ringColor,
    );

    if (progress > 0.01) {
      canvas.drawPath(
        checkMarkPathAt(s, progress),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.115
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: (progress * 1.6).clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress ||
      old.ringColor != ringColor ||
      old.fillColor != fillColor;
}
