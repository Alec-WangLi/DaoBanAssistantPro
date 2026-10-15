import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 玻璃圆角输入框装饰：统一所有 `TextField` 的风格。
///
/// **这里不再有「标签」** —— 标签由 [GlassField] 画在框的上方（原因写在那个件的
/// 文档里：Material 的浮动标签在用户真机上被压成了半截）。这个函数只管框本身：
/// 圆角、描边、填充、聚焦描边宽度。
///
/// 调用点因此长这样：
///
/// ```dart
/// GlassField(
///   label: L10n.title,
///   child: TextField(
///     controller: ctrl,
///     decoration: glassInputDecoration(context),
///   ),
/// )
/// ```
InputDecoration glassInputDecoration(BuildContext context,
    {bool isDense = false}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final borderColor = AppTokens.glassBorder(isDark).withValues(alpha: 0.8);
  return InputDecoration(
    isDense: isDense,
    // 提示语（打字前显示在框里的那行灰字）用与标签同一档 —— 它们在这套设计里
    // 是同一个角色，只是出现的位置不同。宽度不够时（编辑器里一行并排几个控件）
    // 它自己也跟着收，别用 Material 默认的 16sp。
    hintStyle: AppTokens.labelSecondary,
    filled: true,
    fillColor: AppTokens.glassSurface(isDark, true).first,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusM),
      borderSide: BorderSide(color: borderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusM),
      borderSide: BorderSide(color: borderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusM),
      borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary, width: 1.6),
    ),
  );
}
