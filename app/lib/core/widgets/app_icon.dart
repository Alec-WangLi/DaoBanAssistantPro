import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 统一图标包装：线性图标 + 三档尺寸。
///
/// 尺寸只从 [AppTokens.iconSm] / [AppTokens.iconMd] / [AppTokens.iconLg] 三档取，
/// 默认中档。`IconTheme` 的全局默认值在本轮一并设成 `iconLg`，所以漏包成
/// `AppIcon` 的图标也仍落在刻度上。
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size = AppTokens.iconMd, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Icon(icon, size: size, color: color);
}
