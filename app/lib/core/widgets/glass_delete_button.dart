import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../l10n.dart';

/// 统一「删除」按钮：红色调圆形玻璃底 + 删除图标，替换散落的裸删除 IconButton。
class GlassDeleteButton extends StatelessWidget {
  const GlassDeleteButton({
    super.key,
    required this.onPressed,
    this.tooltip,
    this.compact = false,
  });

  final VoidCallback? onPressed;
  final String? tooltip;

  /// 紧凑变体：**只留图标**，没有圆形底色、描边与投影，用在列表行/卡片行尾。
  ///
  /// 完整形态（默认）是个 48pt 的红圆，适合作为一屏的主删除动作；
  /// 放进密集的表单行或列表里会盖过主体内容，这时用紧凑形态降噪。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (compact) {
      return IconButton(
        tooltip: tooltip ?? L10n.delete,
        onPressed: onPressed,
        icon: const Icon(Icons.delete_outlined, size: 18),
        // 去掉填充后图标不用压暗，否则在深色底上会糊掉
        color: AppTokens.danger,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        visualDensity: VisualDensity.compact,
      );
    }
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppTokens.danger.withValues(alpha: 0.32),
                  AppTokens.danger.withValues(alpha: 0.12),
                ]
              : [
                  AppTokens.danger.withValues(alpha: 0.15),
                  AppTokens.danger.withValues(alpha: 0.05),
                ],
        ),
        border: Border.all(
          color: AppTokens.danger.withValues(alpha: isDark ? 0.55 : 0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTokens.danger.withValues(alpha: isDark ? 0.28 : 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IconButton(
        tooltip: tooltip ?? L10n.delete,
        onPressed: onPressed,
        icon: const Icon(Icons.delete_outlined, size: 20),
        color: AppTokens.danger,
      ),
    );
  }
}
