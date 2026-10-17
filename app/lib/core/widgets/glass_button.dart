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
///
/// [radius] 是这个按钮四个角的圆角半径。加它**只为**让编辑页那颗 48 高的
/// 「保存并重排闹钟」胶囊也用上自家的件（那颗原来是 Material 的 `FilledButton`，
/// 胶囊圆角恒为高度一半 = 24），**默认值 `radiusM` 等于加参数之前的行为** ——
/// 三个既有调用点（闹钟页 ×2、响铃页 ×1）因此一个像素都不动。别再拿它去改
/// 那些已经定了圆角的点位；它是给「要一颗更高或更矮的胶囊」准备的。
///
/// [padding] 是内容（图标 + 文字）与按钮左右边的内边距。**默认 `EdgeInsets.zero`**，
/// 因为三个既有调用点都是**通栏**的（`Center` 把内容居中），加不加内边距一个像素都
/// 不变。它只对**按内容定宽**的胶囊有用（编辑页那颗外面套了 `IntrinsicWidth`）：
/// 不定宽时空内边距会让文字贴到胶囊两端的圆头上，很难看 —— 那一处传
/// `EdgeInsets.symmetric(horizontal: AppTokens.spaceXl)`。
///
/// **[onPressed] 为 null 是禁用态**：整体压暗（[_disabledOpacity]）、且按压不再
/// 触发 Q 弹缩放 —— 这一条是给编辑页那颗「保存并重排闹钟」准备的（保存中传 null）。
/// 换掉的那颗 Material `FilledButton` 禁用时会自动变灰，换上自家的件之后那层
/// 「变灰」得自己补上，否则按钮看着还能按、按下去却没反应。
/// 既有调用点里只有编辑页会传 null，其余（闹钟页 ×2、响铃页 ×1、排班管理页 ×1）
/// 恒非 null —— 所以这一条对它们是**零像素改动**。
class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.primary = false,
    this.height = 56,
    this.radius = AppTokens.radiusM,
    this.padding = EdgeInsets.zero,
    this.icon,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool primary;
  final double height;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Widget? icon;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

/// 禁用态（`onPressed == null`）整体压暗的不透明度。Material 的 `FilledButton`
/// 禁用时把背景压到 ~12%、文字压到 ~38%；这里用「整体压暗」近似那件事 —— 渐变的
/// 主色底与白字一起变淡，一眼看出「现在按不动」。**是个手感数，不是算出来的**。
const double _disabledOpacity = 0.5;

class _GlassButtonState extends State<GlassButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final enabled = widget.onPressed != null;

    final decoration = widget.primary
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
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
            borderRadius: BorderRadius.circular(widget.radius),
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
            data: IconThemeData(color: contentColor, size: AppTokens.iconMd),
            child: widget.icon!,
          ),
          const SizedBox(width: AppTokens.gapIconText),
        ],
        Flexible(
          child: DefaultTextStyle.merge(
            style: AppTokens.titleStrong.copyWith(color: contentColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: widget.child,
          ),
        ),
      ],
    );

    final button = QScale(
      pressed: _pressed,
      scale: AppTokens.pressScale,
      child: SizedBox(
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: GlassBlur(
            sigma: 12,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onPressed,
                borderRadius: BorderRadius.circular(widget.radius),
                child: Listener(
                  // 禁用态不接收按压：`_pressed` 永不置位 ⇒ QScale 一直停在 1.0，
                  // 按下去不会弹（`InkWell` 的 `onTap` 已经是 null，波纹也不会起）。
                  onPointerDown:
                      enabled ? (_) => setState(() => _pressed = true) : null,
                  onPointerUp:
                      enabled ? (_) => setState(() => _pressed = false) : null,
                  onPointerCancel:
                      enabled ? (_) => setState(() => _pressed = false) : null,
                  child: Ink(
                    decoration: decoration,
                    child: Stack(
                      children: [
                        // 顶部镜面高光
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(widget.radius),
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
                        Center(
                          child: Padding(
                            padding: widget.padding,
                            child: childRow,
                          ),
                        ),
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

    // 禁用态压暗。**启用时不套 `Opacity`** —— 即便 opacity 为 1 它也会多一层
    // 合成，不套才能保证四个恒非 null 的既有调用点逐像素不变。
    return enabled ? button : Opacity(opacity: _disabledOpacity, child: button);
  }
}
