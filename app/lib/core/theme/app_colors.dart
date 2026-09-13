import 'package:flutter/material.dart';

/// 强调色（主色调）5 色候选 + 班次数据色。
/// 中性背景 / 语义色 / 圆角 / 动效 / 玻璃配方见 `design_tokens.dart`。
class AppColors {
  AppColors._();

  // 主色（默认深蓝紫，仅作「强调色」，不再当背景氛围）
  static const Color primary = Color(0xFF4F5BE8);

  // 主色调候选（「我的」页可选，与下方 accentPalette 顺序一致）
  static const Color sky = Color(0xFF0B6FE6);
  static const Color teal = Color(0xFF00B3A6);
  static const Color orange = Color(0xFFF08800);
  static const Color rose = Color(0xFFE83567);
  static const List<Color> accentPalette = [primary, sky, teal, orange, rose];

  // 班次数据色（与 domain 默认一致，属「内容」非「装饰」，保留）
  static const int shiftDay = 0xFF4C8DFF; // 白班
  static const int shiftNight = 0xFF7A5CFF; // 上夜班
  static const int shiftAfterNight = 0xFF9AA0B4; // 下夜班
  static const int shiftRest = 0xFF5A5F73; // 大休

  /// 响铃背景中间那团光斑的颜色。中性偏冷的浅蓝灰 ——
  /// 它只在 `FlowingBackground` 里用，不参与主题主色，也不随明暗切换。
  static const Color bgBlob = Color(0xFFB9BECF);
}