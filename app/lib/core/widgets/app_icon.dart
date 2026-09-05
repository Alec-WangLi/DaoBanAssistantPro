import 'package:flutter/material.dart';

/// 统一图标包装：默认 outlined 线性 + 统一尺寸，杜绝到处 `Icon(... size: n)`。
class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.icon, this.size = 20, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Icon(icon, size: size, color: color);
}