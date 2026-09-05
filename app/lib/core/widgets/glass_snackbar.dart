import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../glass/glass.dart';

/// 液态玻璃提示条：统一所有 SnackBar 的风格。
///
/// 透明底 + `BackdropFilter` 背景模糊 + 渐变 + 顶部镜面高光 + 主色圆形图标。
/// 通过共享函数一次覆盖所有提示（切换排班 / 保存 / 重置 / 复制日志 / 更新失败等）。
void showGlassSnack(
  BuildContext context,
  String message, {
  IconData? icon,
  Color? iconColor,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final primary = Theme.of(context).colorScheme.primary;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
        content: _GlassSnackContent(
          isDark: isDark,
          icon: icon,
          iconColor: iconColor ?? primary,
          message: message,
        ),
      ),
    );
}

class _GlassSnackContent extends StatelessWidget {
  const _GlassSnackContent({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.message,
  });

  final bool isDark;
  final IconData? icon;
  final Color iconColor;
  final String message;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusL),
      child: GlassBlur(
        sigma: 18,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusL),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppTokens.glassTint(isDark, true),
            ),
            border: Border.all(color: AppTokens.glassBorder(isDark)),
            boxShadow: [AppTokens.glassShadow(isDark)],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusL),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: AppTokens.glassHighlight(isDark),
              stops: const [0.0, 0.28],
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconColor.withValues(alpha: 0.14),
                    border: Border.all(color: iconColor.withValues(alpha: 0.35)),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: AppTokens.fontBody,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
