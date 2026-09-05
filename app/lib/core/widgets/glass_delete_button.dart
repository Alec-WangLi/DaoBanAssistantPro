import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../l10n.dart';

/// 统一「删除」按钮：红色调圆形玻璃底 + 删除图标，替换散落的裸删除 IconButton。
class GlassDeleteButton extends StatelessWidget {
  const GlassDeleteButton({super.key, required this.onPressed, this.tooltip});

  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
