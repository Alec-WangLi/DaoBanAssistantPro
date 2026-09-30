import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../glass/glass.dart';
import '../haptics.dart';

/// 玻璃开关：圆钮 + 玻璃轨道 + Q弹回弹（easeOutBack 过冲）。
///
/// 用于替换系统 Switch / Checkbox，统一「液态玻璃 + Q弹」设计语言。
class GlassSwitch extends StatefulWidget {
  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.width = 46,
    this.height = 28,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  final double width;
  final double height;

  /// 置灰并不可交互。给「这台设备不支持」的场景用（见「我的 → 外观 → 液态玻璃」
  /// 在低内存机器上的处理）—— 那时候开关若还能拨动，用户会得到一个「拨了没反应」
  /// 的开关，比直接说不可用更糟。
  final bool enabled;

  @override
  State<GlassSwitch> createState() => _GlassSwitchState();
}

class _GlassSwitchState extends State<GlassSwitch> {
  /// 按住中。**只有液态档会用到它**（见下），但它始终记着 ——
  /// 关掉液态档时这个字段只是没人读，不产生任何观感差异。
  bool _pressed = false;

  /// 拖动中的位置（0 .. 1）。null = 不在拖。
  double? _dragT;

  /// 当前把手位置（0 = 左、1 = 右）。
  double get _t => _dragT ?? (widget.value ? 1.0 : 0.0);

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent =
        widget.activeColor ?? Theme.of(context).colorScheme.primary;
    final double thumbSize = widget.height - 6;

    // ── 液态档（见 `glass.dart` 的 `liquidGlassActive`）──────────────────────
    // 把手**凸出轨道**、并且做成真玻璃。原来它是一个 22dp 的**不透明白圆**、
    // 顶满轨道内高 —— 于是它的边是「玻璃对玻璃 / 玻璃对轨道填充」，而折射只发生在
    // 「玻璃 ↔ 背景」的边界上（Apple 那条「玻璃不能采样玻璃」）。
    //
    // **凸起只在按住（含拖动）时发生**，这一条是照 iOS 来的：Macworld 的原话是
    // 「当你按住并保持时，它变成一个更大、玻璃般的凸起，移动时折射光线」——
    // 静止时把手是正常大小。做成静止就变大会显得发胀。
    //
    // **拖动也只在液态档开**：标准档的手感与行为一字不动（只 tap、不拖）。
    final bool liquid = liquidGlassActive.value && widget.enabled;
    const double innerPad = AppTokens.padChipV;
    final double innerW = widget.width - 2 * innerPad;
    final double innerH = widget.height - 2 * innerPad;
    final bool swelled = liquid && _pressed;
    final double thumbW = swelled ? 24 : thumbSize;
    final double thumbH = swelled ? 36 : thumbSize;
    final double protrude = (thumbH - innerH) / 2;

    Widget knob() => GlassLensGlow(
          isDark: isDark,
          radius: thumbH / 2,
          // 静止时 swell = 0 → `GlassLensGlow` 一个像素都不画，与标准档逐像素相同。
          swell: swelled ? 1.0 : 0.0,
          child: Container(
            width: thumbW,
            height: thumbH,
            decoration: BoxDecoration(
              shape: swelled ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: swelled ? BorderRadius.circular(thumbH / 2) : null,
              color: swelled
                  ? Colors.white.withValues(alpha: 0.90)
                  : (widget.enabled
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55)),
              border: swelled
                  ? Border.all(color: Colors.white.withValues(alpha: 0.95))
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: swelled ? 0.22 : 0.18),
                  blurRadius: swelled ? 9 : 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
          ),
        );

    // 拖动：把手的**中心**跟着手指走。行程按未鼓起时的宽度算 —— 用鼓起后的宽度
    // 会让行程在按下的那一帧突然变短，手感会跳。纯函数，`setState` 由调用点给。
    double tFor(double dx) {
      final double travel = innerW - thumbSize;
      if (travel <= 0) return _t;
      return ((dx - innerPad - thumbSize / 2) / travel).clamp(0.0, 1.0);
    }

    void endDrag() {
      final bool next = _t >= 0.5;
      setState(() {
        _pressed = false;
        _dragT = null;
      });
      if (next != widget.value) {
        Haptics.select();
        widget.onChanged(next);
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: liquid ? (_) => setState(() => _pressed = true) : null,
      onTapUp: liquid ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: liquid ? () => setState(() => _pressed = false) : null,
      onHorizontalDragStart: liquid
          ? (d) => setState(() {
                _pressed = true;
                _dragT = tFor(d.localPosition.dx);
              })
          : null,
      onHorizontalDragUpdate: liquid
          ? (d) => setState(() => _dragT = tFor(d.localPosition.dx))
          : null,
      onHorizontalDragEnd: liquid ? (_) => endDrag() : null,
      onHorizontalDragCancel: liquid
          ? () => setState(() {
                _pressed = false;
                _dragT = null;
              })
          : null,
      onTap: widget.enabled
          ? () {
              Haptics.select();
              widget.onChanged(!widget.value);
            }
          : null,
      child: AnimatedContainer(
        duration: AppTokens.durMed,
        curve: Curves.easeOutCubic,
        width: widget.width,
        height: widget.height,
        padding: const EdgeInsets.all(innerPad),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.height / 2),
          color: !widget.enabled
              ? AppTokens.glassBorder(isDark).withValues(alpha: 0.25)
              : widget.value
                  ? accent
                  : AppTokens.glassBorder(isDark).withValues(alpha: 0.6),
          border: Border.all(
            color: !widget.enabled
                ? AppTokens.glassBorder(isDark).withValues(alpha: 0.5)
                : widget.value
                    ? accent.withValues(alpha: 0.55)
                    : AppTokens.glassBorder(isDark),
          ),
        ),
        child: swelled
            // 凸起时用**不裁剪的 Stack + AnimatedPositioned**：`AnimatedAlign`
            // 会被容器的高度约束夹回轨道内高，「凸出」就无从谈起。
            ? Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  AnimatedPositioned(
                    duration: AppTokens.durMed,
                    curve: Curves.easeOutBack,
                    left: _t * (innerW - thumbW),
                    top: -protrude,
                    bottom: -protrude,
                    width: thumbW,
                    child: knob(),
                  ),
                ],
              )
            : AnimatedAlign(
                duration: _dragT != null ? Duration.zero : AppTokens.durMed,
                curve: Curves.easeOutBack,
                alignment: Alignment.lerp(
                    Alignment.centerLeft, Alignment.centerRight, _t)!,
                child: knob(),
              ),
      ),
    );
  }
}
