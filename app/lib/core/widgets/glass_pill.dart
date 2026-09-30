import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 顶部栏那种**紧凑玻璃胶囊**：年月、「今天」，以及各页标题行右侧的动作入口。
///
/// 与 [GlassButton] 的分工：那个 56dp 高、圆角 `radiusM`、带镜面高光，给「新建 /
/// 测试」这类主操作；这个是 40dp 级的**栏内控件**，圆角 `radiusL`、阴影更薄。
///
/// **[accent] = true 是实心主色渐变 + 投影**，内容一律用白（写 `Colors.white`，
/// 别跟着 `colorScheme.primary` —— 那是主色字压在主色底上）。这个变体原来的底是
/// 「主色 30% 透明度 + 主色字」，实测对比度浅色 3.0:1 / 深色 2.7:1，都低于 AA；
/// 改成实心后 5.3:1（渐变深处 7:1），也与主按钮的实心主色形态一致。
///
/// **已知遗留**：teal / orange / rose 三种主色下，白字压在这个实心面上仍不达 AA
/// （见 `AGENTS.md` 的「白字压在实心主色上」那条）—— 与 `GlassActionButton` /
/// `GlassButton` 的 primary 是同一个待办，不是这里引入的。
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    this.onTap,
    required this.child,
    this.accent = false,
    this.height = 40,
  });

  final VoidCallback? onTap;
  final Widget child;

  /// 实心主色（强调）还是白玻璃（次要）。
  final bool accent;

  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final decoration = accent
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusL),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primary,
                Color.lerp(primary, Colors.black, 0.18)!,
              ],
            ),
            border: Border.all(color: primary),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: isDark ? 0.45 : 0.28),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          )
        : BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusL),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.22),
                      Colors.white.withValues(alpha: 0.06),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.95),
                      Colors.white.withValues(alpha: 0.55),
                    ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.28 : 0.95),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: decoration,
          child: child,
        ),
      ),
    );
  }
}
