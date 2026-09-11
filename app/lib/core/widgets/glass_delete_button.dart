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

  /// 紧凑变体：去掉投影与描边、缩小图标，用在列表行/卡片行的行尾。
  ///
  /// 完整形态（默认）是个 48pt 的红圆，适合作为一屏的主删除动作；
  /// 放进密集的表单行里会盖过主体内容，这时用紧凑形态降噪。
  final bool compact;

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
                  AppTokens.danger
                      .withValues(alpha: compact ? 0.16 : 0.32),
                  AppTokens.danger.withValues(alpha: compact ? 0.05 : 0.12),
                ]
              : [
                  AppTokens.danger.withValues(alpha: compact ? 0.07 : 0.15),
                  AppTokens.danger.withValues(alpha: compact ? 0.02 : 0.05),
                ],
        ),
        border: compact
            ? null
            : Border.all(
                color:
                    AppTokens.danger.withValues(alpha: isDark ? 0.55 : 0.32),
              ),
        boxShadow: compact
            ? null
            : [
                BoxShadow(
                  color:
                      AppTokens.danger.withValues(alpha: isDark ? 0.28 : 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: IconButton(
        tooltip: tooltip ?? L10n.delete,
        onPressed: onPressed,
        icon: Icon(Icons.delete_outlined, size: compact ? 18 : 20),
        color: compact
            ? AppTokens.danger.withValues(alpha: 0.85)
            : AppTokens.danger,
        padding: compact ? EdgeInsets.zero : null,
        constraints:
            compact ? const BoxConstraints.tightFor(width: 36, height: 36) : null,
        visualDensity: compact ? VisualDensity.compact : null,
      ),
    );
  }
}
