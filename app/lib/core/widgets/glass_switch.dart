import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../haptics.dart';

/// 玻璃开关：圆钮 + 玻璃轨道 + Q弹回弹（easeOutBack 过冲）。
///
/// 用于替换系统 Switch / Checkbox，统一「液态玻璃 + Q弹」设计语言。
class GlassSwitch extends StatelessWidget {
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
  ///
  /// ⚠️ **它没有跟着液态档一起回退，是有意的**（v0.10.3 把液态档收拢到底栏）：
  /// 「这台机器打不开那个效果」与「那个效果作用于哪里」无关，低内存机器上那一行
  /// 仍然是灰的。护栏在 `test/glass_switch_test.dart`。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = activeColor ?? Theme.of(context).colorScheme.primary;
    final thumbSize = height - 6;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              Haptics.select();
              onChanged(!value);
            }
          : null,
      child: AnimatedContainer(
        duration: AppTokens.durMed,
        curve: Curves.easeOutCubic,
        width: width,
        height: height,
        padding: const EdgeInsets.all(AppTokens.padChipV),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          color: !enabled
              ? AppTokens.glassBorder(isDark).withValues(alpha: 0.25)
              : value
                  ? accent
                  : AppTokens.glassBorder(isDark).withValues(alpha: 0.6),
          border: Border.all(
            color: !enabled
                ? AppTokens.glassBorder(isDark).withValues(alpha: 0.5)
                : value
                    ? accent.withValues(alpha: 0.55)
                    : AppTokens.glassBorder(isDark),
          ),
        ),
        child: AnimatedAlign(
          duration: AppTokens.durMed,
          curve: Curves.easeOutBack,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: thumbSize,
            height: thumbSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  enabled ? Colors.white : Colors.white.withValues(alpha: 0.55),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
