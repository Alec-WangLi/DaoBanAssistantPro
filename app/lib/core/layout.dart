// app/lib/core/layout.dart
import 'package:flutter/material.dart';

/// 布局分档。三个判据**彼此独立** —— 手机横屏是「宽且矮」，车机是「宽且不矮」，
/// 小窗常常「又窄又矮」，用单一档位枚举表达不了：硬套会立刻需要
/// `compactButWide` 这种名字，等于把布尔值藏起来，还多一层要维护的映射。
class AppLayout {
  const AppLayout({
    required this.isNarrow,
    required this.isShort,
    required this.isWide,
    required this.availableWidth,
    required this.availableHeight,
  });

  /// 可用宽 < 360：小窗、分屏。
  final bool isNarrow;

  /// 可用高 < 480：手机横屏、小窗。
  final bool isShort;

  /// 可用宽 >= 720：平板、车机、手机横屏。
  final bool isWide;

  /// 扣掉键盘与系统栏之后的可用区域。
  final double availableWidth;
  final double availableHeight;

  /// 宽屏下内容的最大宽度。表单在 1280 宽的车机上拉满整屏会难以阅读：
  /// 「标签在左、值在右」的行会两端离得太远。
  static const double maxContentWidth = 720;

  static const double _narrowWidth = 360;
  static const double _shortHeight = 480;
  static const double _wideWidth = 720;

  /// 用**可用区域**判定，不是整屏尺寸：键盘（viewInsets）与刘海/系统栏
  /// （viewPadding）都实打实地吃掉空间。不扣掉就会把「键盘占了半屏」
  /// 误判成「屏幕变矮」，而这两件事该有完全不同的处置。
  static AppLayout of(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width - mq.viewInsets.horizontal;
    final h = mq.size.height - mq.viewInsets.vertical - mq.viewPadding.vertical;
    return AppLayout(
      isNarrow: w < _narrowWidth,
      isShort: h < _shortHeight,
      isWide: w >= _wideWidth,
      availableWidth: w,
      availableHeight: h,
    );
  }
}
