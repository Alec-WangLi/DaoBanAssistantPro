import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../haptics.dart';
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
            data: IconThemeData(color: contentColor, size: AppTokens.iconMd),
            child: widget.icon!,
          ),
          const SizedBox(width: AppTokens.gapIconText),
        ],
        Text(
          widget.label,
          style: AppTokens.labelStrong.copyWith(color: contentColor),
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
              // `onPressed` 的类型是可空的（`VoidCallback?`），所以整段门住 ——
              // 直接 `widget.onPressed()` 在 null 时会崩。这是**纯防御**，不是
              // 在挡一条活路径：全仓现存调用点都传非空闭包。（`schedule_editor_
              // screen.dart` 里那句 `onPressed: _saving ? null : _save` 是
              // `FilledButton.icon`，不是本组件 —— 曾有人把它记成这里。）
              onTap: widget.onPressed == null
                  ? null
                  : () {
                      // 危险变体 = 破坏性确认（全 app 四处，全是删除/清空类）。
                      // `commit` 表达的是「这一步不可逆」，与普通点击区分开。
                      if (widget.variant == GlassActionVariant.danger) {
                        Haptics.commit();
                      }
                      widget.onPressed!();
                    },
              borderRadius: BorderRadius.circular(AppTokens.radiusM),
              child: Listener(
                onPointerDown: (_) => setState(() => _pressed = true),
                onPointerUp: (_) => setState(() => _pressed = false),
                onPointerCancel: (_) => setState(() => _pressed = false),
                child: Ink(
                  decoration: decoration,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.spaceLg,
                        vertical: AppTokens.spaceMd),
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
