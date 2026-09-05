import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../motion.dart';
import '../glass/glass.dart';

/// 弹窗/底部弹层的统一玻璃操作按钮样式。
enum GlassActionVariant { primary, secondary, danger }

/// 紧凑玻璃操作按钮：用于弹窗的「取消 / 确定 / 关闭 / 删除」等动作。
/// 自带玻璃渐变 + 顶部高光 + 水波纹 + Q 弹按压，取代散落的裸 `TextButton`/`FilledButton`。
class GlassActionButton extends StatefulWidget {
  const GlassActionButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.variant = GlassActionVariant.secondary,
    this.icon,
  });

  final VoidCallback? onPressed;
  final String label;
  final GlassActionVariant variant;
  final Widget? icon;

  @override
  State<GlassActionButton> createState() => _GlassActionButtonState();
}

class _GlassActionButtonState extends State<GlassActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final BoxDecoration decoration;
    final Color contentColor;
    switch (widget.variant) {
      case GlassActionVariant.primary:
        decoration = BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          gradient: AppTokens.accentGradient(primary),
          border: Border.all(color: primary.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        );
        contentColor = Colors.white;
        break;
      case GlassActionVariant.danger:
        decoration = BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [AppTokens.danger.withValues(alpha: 0.85), AppTokens.danger.withValues(alpha: 0.55)]
                : [AppTokens.danger.withValues(alpha: 0.92), AppTokens.danger.withValues(alpha: 0.70)],
          ),
          border: Border.all(color: AppTokens.danger.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: AppTokens.danger.withValues(alpha: 0.30),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        );
        contentColor = Colors.white;
        break;
      case GlassActionVariant.secondary:
        decoration = BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppTokens.glassTint(isDark, true),
          ),
          border: Border.all(color: AppTokens.glassBorder(isDark)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        );
        contentColor = onSurface;
        break;
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          IconTheme(
            data: IconThemeData(color: contentColor, size: 18),
            child: widget.icon!,
          ),
          const SizedBox(width: 6),
        ],
        Text(
          widget.label,
          style: TextStyle(
            color: contentColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    return QScale(
      pressed: _pressed,
      scale: AppTokens.pressScale,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
        child: GlassBlur(
          sigma: 12,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(AppTokens.radiusM),
              child: Listener(
                onPointerDown: (_) => setState(() => _pressed = true),
                onPointerUp: (_) => setState(() => _pressed = false),
                onPointerCancel: (_) => setState(() => _pressed = false),
                child: Ink(
                  decoration: decoration,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 11),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
