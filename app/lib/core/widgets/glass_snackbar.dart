import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../glass/glass.dart';
import 'app_icon.dart';

/// 液态玻璃提示条：统一所有 SnackBar 的风格。
///
/// 透明底 + `BackdropFilter` 背景模糊 + 渐变 + 顶部镜面高光 + 主色圆形图标。
/// 通过共享函数一次覆盖所有提示（切换排班 / 保存 / 重置 / 复制日志 / 更新失败等）。
///
/// [actionLabel] 与 [onAction] 是给「这条提示要能当场反悔」那一类用的（待办勾错了
/// 要能撤销）—— 两个都给了才画那颗动作，**既有调用点一个字都不用改**。
void showGlassSnack(
  BuildContext context,
  String message, {
  IconData? icon,
  Color? iconColor,
  String? actionLabel,
  VoidCallback? onAction,
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
        // 带动作的那一条要留给手指够得着的工夫（2 秒是「看一眼就够」的档，不够点）；
        // 没动作的照旧 2 秒。
        duration: actionLabel == null
            ? const Duration(seconds: 2)
            : const Duration(seconds: 5),
        content: _GlassSnackContent(
          isDark: isDark,
          icon: icon,
          iconColor: iconColor ?? primary,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
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
    this.actionLabel,
    this.onAction,
  });

  final bool isDark;
  final IconData? icon;
  final Color iconColor;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = Theme.of(context).colorScheme.primary;
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
                  child: AppIcon(icon!,
                      size: AppTokens.iconMd, color: iconColor),
                ),
                const SizedBox(width: AppTokens.gapIconTextLg),
              ],
              Expanded(
                child: Text(
                  message,
                  style: AppTokens.rowPrimary.copyWith(color: onSurface),
                ),
              ),
              // 动作走**主色文字**：底是玻璃面，`onSolid` 那套（黑白二选一）在这儿
              // 用不上；与「排班管理」页那些行内动作是同一个配方。字号取 13/w600 的
              // `labelSecondary` —— 它得压得住这条提示，但又不该跟正文一样重。
              if (actionLabel != null) ...[
                const SizedBox(width: AppTokens.gapIconTextLg),
                InkWell(
                  onTap: onAction,
                  borderRadius: BorderRadius.circular(AppTokens.radiusS),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.spaceSm,
                        vertical: AppTokens.spaceXs),
                    child: Text(
                      actionLabel!,
                      style:
                          AppTokens.labelSecondary.copyWith(color: primary),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
