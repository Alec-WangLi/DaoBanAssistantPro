// app/lib/core/widgets/glass_step_button.dart
//
// 「上一个 / 下一个」的圆钮：统计页期间条与日期选择弹层共用。
//
// 为什么是一个具名件：这段配方（`GlassPill(emphasis, 44)` + `AppIcon(iconMd)` +
// 12×2 内边距 = 44×44 命中区）原先手写在 `stats_period_header.dart` 的 `_stepPill`；
// 日期选择器再抄一遍就是第二份。D4 已经有一处「第四套配方」的欠账，别再加。
//
// **图标色自己给，不由调用点各写一遍**：裸 `Icon` 不给 color 时落到
// `IconThemeData.fallback` 的纯黑，深色下就是黑压黑 —— 2026-11-23 issue #7
// 报的「左右箭头和背景融在一起」就是这一条（统计页期间条当天改过，弹层里漏了）。
// 判据按「压在什么底上」：深色取 `onSurface`（近白）；浅色取压过的主色
// （浅色玻璃上写纯白等于把箭头擦掉，D3 的反面）。
import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'app_icon.dart';
import 'glass_pill.dart';

class GlassStepButton extends StatelessWidget {
  const GlassStepButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.ink,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// 覆盖图标色；不给就按主题取（深色近白 / 浅色压过的主色）。
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = ink ??
        (isDark
            ? Theme.of(context).colorScheme.onSurface
            : AppTokens.solidAccent(Theme.of(context).colorScheme.primary));
    // 20 的图标 + 12×2 的内边距 = 44，命中区正好 44×44（D15）。
    // 复用 `GlassPill` 而不是新造一枚圆钮件：圆角 `radiusL`(22) 在 44 高处
    // 正好是正圆，而新件必然再抄一套玻璃配方。
    return GlassPill(
      onTap: onTap,
      emphasis: true,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
      child: AppIcon(icon, size: AppTokens.iconMd, color: color),
    );
  }
}
