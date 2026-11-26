import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 顶部栏那种**紧凑玻璃胶囊**：年月、「今天」，以及各页标题行右侧的动作入口。
///
/// 与 [GlassButton] 的分工：那个 56dp 高、圆角 `radiusM`、带镜面高光，给「新建 /
/// 测试」这类主操作；这个是 40dp 级的**栏内控件**，圆角 `radiusL`、阴影更薄。
///
/// **[height] 只有两档，别各自再定一个数**：
///   - **栏内控件（顶栏年月 / 「今天」/ 标题行入口）用默认 40**；
///   - **紧凑入口（分组标题旁、列表行 trailing 那种）用 36**
///     （待办页的「重复待办」「已完成 N 条」、模板选择的「管理」、权限卡的
///     「去开启」都在这一档）。
/// 这个件**没有额外的命中扩展** —— 命中区就是 `Container(height:)` 这么高，所以
/// 别为了「看着小一点」把唯一的入口收到 32（原来那些是 `TextButton`，M3 默认
/// `minimumSize` 40 + `padded` 命中 = 48dp）。要收紧观感就收内边距 / 字号。
///
/// **[accent] = true 是实心主色渐变 + 投影**，内容一律用白（写 `Colors.white`，
/// 别跟着 `colorScheme.primary` —— 那是主色字压在主色底上）。这个变体原来的底是
/// 「主色 30% 透明度 + 主色字」，实测对比度浅色 3.0:1 / 深色 2.7:1，都低于 AA；
/// 改成实心后 5.3:1（渐变深处 7:1），也与主按钮的实心主色形态一致。
///
/// ⚠️ **内容必须显式写白**：底色走 `solidAccent`（按需压深），而**字色跟着主题
/// 走的话，浅色档就是「近黑字压深底」** —— 用户 2026-10-15 真机报的那条就是这么
/// 来的（底栏与分段器）。浅色档下 `colorScheme.primary` 只会更暗，别拿它当字色。
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    this.onTap,
    required this.child,
    this.accent = false,
    this.emphasis = false,
    this.height = 40,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  });

  final VoidCallback? onTap;
  final Widget child;

  /// 实心主色（强调）还是白玻璃（次要）。
  final bool accent;

  /// 白玻璃里的**亮一档**（见 [AppTokens.glassTintEmphasis]）。
  ///
  /// 统计页的期间条用它：深色下默认档压成暗灰，用户报过「颜色看着有点暗」。
  /// 与 [accent] 互斥语义（那个是实心主色），同时给以 [accent] 为准。
  final bool emphasis;

  final double height;

  /// 内容内边距。给期间条的圆形箭头钮用 `symmetric(horizontal: spaceMd)`
  /// —— 20 的图标 + 12×2 = 44，正好是 D15 的命中区，不必新立一枚圆钮件。
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    // 实心那一档用**深一档的主色**（`solidAccent`）：白字压在原主色上，
    // teal / orange / rose 三颗到不了 AA（见那个常量的文档）。
    final solid = AppTokens.solidAccent(primary);
    final decoration = accent
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusL),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                solid,
                Color.lerp(solid, Colors.black, 0.18)!,
              ],
            ),
            border: Border.all(color: solid),
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
              colors: emphasis
                  ? AppTokens.glassTintEmphasis(isDark)
                  : AppTokens.glassChipTint(isDark),
            ),
            border: Border.all(
              color: emphasis
                  ? AppTokens.glassBorderEmphasis(isDark)
                  : AppTokens.glassChipBorder(isDark),
            ),
            boxShadow: [
              BoxShadow(
                color: AppTokens.glassChipShadow(isDark),
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
          padding: padding,
          alignment: Alignment.center,
          decoration: decoration,
          child: child,
        ),
      ),
    );
  }
}
