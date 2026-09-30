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
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  final double width;
  final double height;

  @override
  State<GlassSwitch> createState() => _GlassSwitchState();
}

class _GlassSwitchState extends State<GlassSwitch> {
  /// 按住中。**只有探针档会用到它**（见下），但它始终记着 —— 关掉探针时
  /// 这个字段只是没人读，不产生任何观感差异。
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent =
        widget.activeColor ?? Theme.of(context).colorScheme.primary;
    final double thumbSize = widget.height - 6;

    // ── 探针（见 `glass.dart` 的 glassProbeRim）────────────────────────────
    // 把手**凸出轨道**、并且做成真玻璃。原来它是一个 22dp 的**不透明白圆**、
    // 顶满轨道内高 —— 于是它的边是「玻璃对玻璃 / 玻璃对轨道填充」，而折射只发生在
    // 「玻璃 ↔ 背景」的边界上（Apple 那条「玻璃不能采样玻璃」）。
    //
    // **凸起只在按住时发生**，这一条是照 iOS 来的：Macworld 的原话是「当你按住并
    // 保持时，它变成一个更大、玻璃般的凸起，移动时折射光线」—— 静止时把手是正常
    // 大小（iOS 26 只是把它从圆形改成了「更宽的椭圆」）。做成静止就变大会显得发胀。
    // 这也与导航滑块一致：那个也是按住才放大。
    final bool probe = glassProbeRim;
    const double innerPad = AppTokens.padChipV;
    final double innerW = widget.width - 2 * innerPad;
    final double innerH = widget.height - 2 * innerPad;
    final bool swelled = probe && _pressed;
    final double thumbW = swelled ? 24 : thumbSize;
    final double thumbH = swelled ? 36 : thumbSize;
    final double protrude = (thumbH - innerH) / 2;

    Widget knob() => Container(
          width: thumbW,
          height: thumbH,
          decoration: BoxDecoration(
            shape: swelled ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: swelled ? BorderRadius.circular(thumbH / 2) : null,
            color:
                swelled ? Colors.white.withValues(alpha: 0.90) : Colors.white,
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
        );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: probe ? (_) => setState(() => _pressed = true) : null,
      onTapUp: probe ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: probe ? () => setState(() => _pressed = false) : null,
      onTap: () {
        Haptics.select();
        widget.onChanged(!widget.value);
      },
      child: AnimatedContainer(
        duration: AppTokens.durMed,
        curve: Curves.easeOutCubic,
        width: widget.width,
        height: widget.height,
        padding: const EdgeInsets.all(innerPad),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.height / 2),
          color: widget.value
              ? accent
              : AppTokens.glassBorder(isDark).withValues(alpha: 0.6),
          border: Border.all(
            color: widget.value
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
                    left: widget.value ? (innerW - thumbW) : 0,
                    top: -protrude,
                    bottom: -protrude,
                    width: thumbW,
                    child: knob(),
                  ),
                ],
              )
            : AnimatedAlign(
                duration: AppTokens.durMed,
                curve: Curves.easeOutBack,
                alignment: widget.value
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: knob(),
              ),
      ),
    );
  }
}
