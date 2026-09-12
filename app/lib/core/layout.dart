// app/lib/core/layout.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 系统栏内边距的合理上限比例。
///
/// 真实的系统栏占不到窗口的四分之一：竖屏状态栏 48 / 869 ≈ 6%，手机横屏
/// 48 / 420 ≈ 11%，小窗里干脆没有系统栏。
const double _maxInsetRatio = 0.25;

double _saneInset(double value, double dimension) =>
    value > dimension * _maxInsetRatio ? 0 : value;

/// 把系统栏内边距收敛回合理区间。
///
/// **为什么需要**：小米小窗（HyperOS）会把 `viewPadding.top` 报成**整个窗口的
/// 高度**。实测（Redmi K90 Pro Max，1200×2608 @480dpi，小窗给应用 200×400）：
///
/// ```
/// win=199.7x400.0 dpr=3.0 pad(t400.0,b22.7) vpad(t400.0,b22.7) view=599x1200
/// ```
///
/// `padding.top` 与 `viewPadding.top` 都等于 400 —— 正好是这个窗口的高度。
/// 于是每一个没关掉顶部安全区的 `SafeArea` 都会把整屏让给它：日历页正文的
/// 可用高度变成 **0**，整页只剩 Scaffold 背景色。用户看到的就是
/// 「小窗里只看得到底部那条胶囊，页面内容全黑」。
///
/// 底部导航胶囊之所以还在，是因为它本来就写了 `SafeArea(top: false, …)` ——
/// 这反过来正好印证了成因。
///
/// 不夹 `viewInsets`：那个是键盘高度，占半屏是正常的。
///
/// 超过上限的值**归零**而不是夹到上限：这类值不是「偏大的系统栏」，是系统
/// 报错了，位置也不可能对；夹到 25% 只会白白留一条百来像素的空白。
MediaQueryData sanitizeSystemInsets(MediaQueryData mq) {
  EdgeInsets fix(EdgeInsets v) => EdgeInsets.fromLTRB(
        _saneInset(v.left, mq.size.width),
        _saneInset(v.top, mq.size.height),
        _saneInset(v.right, mq.size.width),
        _saneInset(v.bottom, mq.size.height),
      );

  final viewPadding = fix(mq.viewPadding);
  final insets = mq.viewInsets;
  return mq.copyWith(
    viewPadding: viewPadding,
    // padding 按框架约定由 viewPadding 与 viewInsets 推出（两者之差的非负部分）。
    // 只改 viewPadding 而不重算 padding，SafeArea 读到的还是那个畸形值。
    padding: EdgeInsets.fromLTRB(
      math.max(0, viewPadding.left - insets.left),
      math.max(0, viewPadding.top - insets.top),
      math.max(0, viewPadding.right - insets.right),
      math.max(0, viewPadding.bottom - insets.bottom),
    ),
  );
}

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
