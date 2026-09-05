import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 玻璃圆角输入框装饰：统一所有 TextField 的风格。
InputDecoration glassInputDecoration(BuildContext context, String label,
    {bool isDense = false}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final borderColor = AppTokens.glassBorder(isDark).withValues(alpha: 0.8);
  return InputDecoration(
    labelText: label,
    isDense: isDense,
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
