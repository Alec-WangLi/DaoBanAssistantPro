import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../layout.dart';
import '../motion.dart';
import '../glass/glass.dart';

/// 液态玻璃按钮。
///
/// [primary]=true 为主色渐变玻璃实心（用于「新建」这类主操作）；
/// false 为白色半透明玻璃描边（用于「测试」这类次操作）。
/// 自带背景模糊、顶部镜面高光与 Q 弹按压缩放。
class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.primary = false,
    this.height = 56,
    this.icon,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool primary;
  final double height;
  final Widget? icon;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    final decoration = widget.primary
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusM),
            gradient: AppTokens.accentGradient(primary),
            border: Border.all(color: primary.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.30),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          )
        : BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusM),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppTokens.glassTint(isDark, true),
            ),
            border: Border.all(color: AppTokens.glassBorder(isDark)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          );

    final contentColor =
        widget.primary ? Colors.white : Theme.of(context).colorScheme.onSurface;

    // 窄档（小窗实测 200 逻辑像素宽）里一个按钮可能只有 79 宽，图标 20 + 间距 6
    // 会直接挤掉文字的位置：闹钟页并排的「新建闹钟 / 测试闹钟」此前各溢出 10px。
    // 省掉图标把宽度让给文字；文字再放不下就走省略号 —— 标签不该撑破按钮。
    //
    // 这里用 Flexible 的前提是调用方给了有界宽度（现在三处都是：Expanded、
    // Positioned(left/right)、Column 的子项）。放进无界的 Row 会触发框架断言。
    final narrow = AppLayout.of(context).isNarrow;
    final showIcon = widget.icon != null && !narrow;

    final childRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showIcon) ...[
          IconTheme(
            data: IconThemeData(color: contentColor, size: 20),
            child: widget.icon!,
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: contentColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: widget.child,
          ),
        ),
      ],
    );

    return QScale(
      pressed: _pressed,
      scale: AppTokens.pressScale,
      child: SizedBox(
        height: widget.height,
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
                    child: Stack(
                      children: [
                        // 顶部镜面高光
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(AppTokens.radiusM),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.center,
                                  colors: [
                                    Colors.white
                                        .withValues(alpha: isDark ? 0.16 : 0.35),
                                    Colors.white.withValues(alpha: 0.0),
                                  ],
                                  stops: const [0.0, 0.28],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Center(child: childRow),
                      ],
                    ),
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
