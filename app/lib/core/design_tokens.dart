// app/lib/core/design_tokens.dart
import 'package:flutter/material.dart';

/// 设计令牌单一事实来源。所有组件的颜色/圆角/间距/动效/玻璃配方/排版一律引用这里，
/// 禁止在 feature 层内联 magic number。
class AppTokens {
  AppTokens._();

  // ── 颜色：中性背景 + 文字（明/暗各一套） ──
  static const Color bgLight = Color(0xFFF5F6FA);
  static const Color bgDark = Color(0xFF0B0B10);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF16161E);
  static const Color inkLight = Color(0xFF111118);
  static const Color inkDark = Color(0xFFF2F2F7);
  static const Color inkMutedLight = Color(0xFF6E6E82);
  static const Color inkMutedDark = Color(0xFF9A9AB0);

  // ── 语义色 ──
  static const Color danger = Color(0xFFE53935);
  static const Color success = Color(0xFF4ADE80);
  static const Color holiday = Color(0xFFE53935);

  // ── 圆角 ──
  static const double radiusS = 12;
  static const double radiusM = 16;
  static const double radiusL = 22;
  static const double radiusXL = 28;

  // ── 间距（4px 栅格） ──
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 20;

  // ── 玻璃模糊 sigma ──
  static const double blurChip = 12;
  static const double blurCard = 18;
  static const double blurPanel = 24;

  // ── 时长（非弹簧过渡） ──
  static const Duration durFast = Duration(milliseconds: 120);
  static const Duration durMed = Duration(milliseconds: 220);
  static const Duration durSlow = Duration(milliseconds: 340);

  // ── Q 弹弹簧 + 缩放 ──
  static const SpringDescription qSpring =
      SpringDescription(mass: 1, stiffness: 400, damping: 16);
  static const double pressScale = 0.96;
  static const double pillGrow = 1.06;

  // ── 排版（system 字体） ──
  //
  // 全 App 实际只用到这四档：16 输入框与卡片标题 / 14 行内主文字 /
  // 13 次要标签 / 12 微字。令牌里**只留这四档** —— 多留一档就迟早有人
  // 顺手用上，档位又散了。
  static const double fontDisplayXl = 84;
  static const double fontDisplay = 28;
  static const double fontTitle = 20;
  static const double fontHeading = 18;
  static const double fontLead = 16;
  static const double fontBody = 14;
  static const double fontSupport = 13;
  static const double fontCaption = 12;

  /// 强调色渐变（按钮/导航选中/填充条用）：顶 0.85 → 底 0.50。
  static LinearGradient accentGradient(Color accent) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: 0.85),
          accent.withValues(alpha: 0.50),
        ],
      );

  // ── 玻璃配方（统一，两档：glassTint 胶囊/按钮、glassSurface 卡片/面板） ──
  // 顶层 alpha 更高；blurOn=false（低端机/关高级材质）时整体更实。
  static List<Color> glassTint(bool isDark, bool blurOn) => isDark
      ? [
          Colors.white.withValues(alpha: blurOn ? 0.16 : 0.22),
          Colors.white.withValues(alpha: blurOn ? 0.07 : 0.12),
        ]
      : [
          Colors.white.withValues(alpha: blurOn ? 0.80 : 0.90),
          Colors.white.withValues(alpha: blurOn ? 0.45 : 0.72),
        ];

  static List<Color> glassSurface(bool isDark, bool blurOn) => isDark
      ? [
          Colors.white.withValues(alpha: blurOn ? 0.11 : 0.16),
          Colors.white.withValues(alpha: blurOn ? 0.04 : 0.08),
        ]
      : [
          Colors.white.withValues(alpha: blurOn ? 0.70 : 0.82),
          Colors.white.withValues(alpha: blurOn ? 0.34 : 0.60),
        ];

  static Color glassBorder(bool isDark) =>
      Colors.white.withValues(alpha: isDark ? 0.16 : 0.90);

  static List<Color> glassHighlight(bool isDark) => [
        Colors.white.withValues(alpha: isDark ? 0.18 : 0.55),
        Colors.white.withValues(alpha: 0.0),
      ];

  static double glassHighlightStop(bool isDark) => isDark ? 0.28 : 0.30;

  static BoxShadow glassShadow(bool isDark) => BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
        blurRadius: 28,
        offset: const Offset(0, 10),
      );

  // ── 底部悬浮导航胶囊（半透明磨砂玻璃：真实模糊 + 通透白 tint，内容滑过若隐若现） ──
  static List<Color> navFill(bool isDark) => isDark
      ? [
          Colors.white.withValues(alpha: 0.09),
          Colors.white.withValues(alpha: 0.035),
        ]
      : [
          Colors.white.withValues(alpha: 0.56),
          Colors.white.withValues(alpha: 0.24),
        ];

  /// 胶囊描边：亮色转深色细线勾勒轮廓（白底上白描边会隐身），暗色保持白描边。
  static Color navBorder(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.16)
      : inkLight.withValues(alpha: 0.14);

  /// 胶囊滑块选中项前景（图标/文字）：浅色模式滑块被白底冲淡，恒用深字；
  /// 暗色模式按明度选黑/白——当前 5 个主题色均低于 0.45 阈值，走白字。
  static Color navForeground(bool isDark, Color accent) {
    if (!isDark) return inkLight;
    return accent.computeLuminance() > 0.45 ? inkLight : inkDark;
  }

  // ── 文字可读性 ──

  /// WCAG 对比度（1:1 ~ 21:1）。要求两个颜色都是不透明的，才等于屏幕上的观感。
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// 把「班次色」调成当**文字**用可读的版本：只动明度，不动色相。
  ///
  /// 班次色是给色块和圆点用的强色，直接拿来当小号文字色会明显不够看——
  /// 模板里的橙 `#FF9F0A` 压在白底上只有 2.06:1、灰 `#9AA0B4` 只有 2.60:1，
  /// 12px 的字基本读不出来（WCAG AA 对普通文字要求 4.5:1）。这两个颜色
  /// 在日历格子里就是「中」「休」两个字，等于每天都少看一档信息。
  ///
  /// 做法：在浅色底上朝黑压、在深色底上朝白提，够到 [target] 就停。所以压在
  /// 底上的字读得清，同时因为色相没动，还认得出是哪个班次。
  static Color inkFor(Color color, Color background, {double target = 4.5}) {
    // 每个格子每次 build 都算一遍的话，一屏 42 格 × 十几轮 pow 是白白烧 CPU
    // （拖动时每帧都要重算），班次色又是有限的几种，缓存掉。
    return _inkCache.putIfAbsent(
      Object.hash(color.toARGB32(), background.toARGB32(), target),
      () => _computeInk(color, background, target),
    );
  }

  static final Map<int, Color> _inkCache = {};

  static Color _computeInk(Color color, Color background, double target) {
    if (contrastRatio(color, background) >= target) return color;
    final toward =
        background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    // 一档 4%，最多到 72%：再深就基本等于纯黑/纯白，色相也留不住了。
    for (var t = 0.08; t < 0.72; t += 0.04) {
      final candidate = Color.lerp(color, toward, t)!;
      if (contrastRatio(candidate, background) >= target) return candidate;
    }
    return Color.lerp(color, toward, 0.72)!;
  }

  /// 实心色块上的可读文字色：白或黑，取对比度更高的一侧。
  ///
  /// 恒有 max(白, 黑) ≥ 4.58:1 —— 两条曲线在亮度 0.179 处交叉，交叉点上
  /// 各是 4.58。所以这个二选一对**任何**底色都能过 WCAG AA，不需要像
  /// [inkFor] 那样逐档逼近。
  ///
  /// 不能拿 [inkFor] 代劳：那个是「把一个前景色调到在给定背景上可读」，
  /// 朝黑还是朝白由**背景**明暗决定；这里是「底色已定，白黑二选一」，
  /// 方向必须由底色与黑白两色的对比度决定。拿 `inkFor(白, 橙)` 会得到
  /// 白色本身（它朝白逼近），而橙底白字只有 2.23:1。
  static Color onSolid(Color background) =>
      contrastRatio(Colors.white, background) >=
              contrastRatio(Colors.black, background)
          ? Colors.white
          : Colors.black;
}