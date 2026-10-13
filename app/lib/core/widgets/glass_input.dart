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
    // 标签走本项目的次要文字档（13sp），**不用 Material 默认的 16sp**。
    // 两个理由：① 全 app 其他地方的行内标签本来就是 13~14sp，16 是个异类；
    // ② 输入框默认那档在窄字段里根本放不下 —— 编辑器里那些一行并排几个控件的行
    //    （班次名 + 简称 + 删除）字段只有 ~66dp，16sp×特大下「班次名称」会被
    //    `InputDecorator` 静默截成「班次…」。这是设计 §2 的第 2 档降级：缩，不省略。
    labelStyle: AppTokens.labelSecondary,
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
