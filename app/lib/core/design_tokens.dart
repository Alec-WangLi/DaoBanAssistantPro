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

  /// 胶囊圆角：高度的一半。用于导航胶囊、开关轨道、分段滑块，以及
  /// 信息卡左侧那根 6dp 色条这类「细长条」。
  static BorderRadius pillOf(double height) =>
      BorderRadius.all(Radius.circular(height / 2));

  // ── 间距：两套刻度 ──
  //
  // 「节奏」用于分隔两个**板块**：页面留白、区块间距、卡片内边距、列表行。
  // 4px 栅格。判据是「这个间距在分隔板块，还是在贴合一个控件内部的两个元素」。
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 20;
  static const double space2xl = 24;
  static const double space3xl = 32;

  // 「光学」用于**一个控件内部**两个元素的贴合：图标与文字之间、小胶囊的
  // 上下内边距。硬套 4px 会让图标显得脱开、胶囊显得臃肿，所以单独留四档。
  static const double gapHair = 2;
  static const double padChipV = 3;
  static const double gapIconText = 6;
  static const double gapIconTextLg = 10;

  // ── 玻璃模糊 sigma ──
  static const double blurCard = 18;
  static const double blurPanel = 24;

  // ── 时长（非弹簧过渡） ──
  static const Duration durFast = Duration(milliseconds: 120);
  static const Duration durMed = Duration(milliseconds: 220);
  static const Duration durSlow = Duration(milliseconds: 340);

  /// 响铃界面的**入场动画**时长：一次性控制器（`alarm_ringing_screen.dart` 里
  /// `_enter.forward()`），驱动 FadeTransition / ScaleTransition 的淡入与放大。
  ///
  /// 注意它**不是**背景光晕的循环周期 —— 真正的光晕循环是
  /// `core/theme/animated_background.dart` 里另一个 26s 的 `repeat()`，
  /// 本轮未纳入令牌（范围外）。
  static const Duration durRingEnter = Duration(milliseconds: 650);

  // ── Q 弹弹簧 + 缩放 ──
  static const SpringDescription qSpring =
      SpringDescription(mass: 1, stiffness: 400, damping: 16);
  static const double pressScale = 0.96;
  static const double pillGrow = 1.06;

  // ── 排版：角色令牌 ──
  //
  // 令牌即完整样式（字号 + 字重 + 行高）。界面层只写角色名，不写 fontSize /
  // fontWeight；颜色由调用处 `copyWith(color:)` 覆盖 —— 同一个角色在不同底色上
  // （尤其班次色块）要取不同的可读色，所以颜色不进令牌。
  //
  // 名字说的是「什么时候用它」，不是「它多大」。这也是为什么不再按
  // fontLead / fontBody 那样按尺寸命名：按尺寸命名会让人挑「最像的那个大小」，
  // 12.5 / 13.5 / 14.5 / 15 / 22 就是这么来的。
  //
  // 一个角色内的个别变化走 `copyWith`，不另立令牌（格子里的「今天」加粗、
  // 选择器选中项加粗、导航标签选中态、调休日「班」标记转主色）。
  static const TextStyle ringClock =
      TextStyle(fontSize: 84, fontWeight: FontWeight.w800, height: 1.0);
  static const TextStyle pageTitle =
      TextStyle(fontSize: 28, fontWeight: FontWeight.w700);
  static const TextStyle bigNumber =
      TextStyle(fontSize: 24, fontWeight: FontWeight.w700);
  static const TextStyle dialogTitle =
      TextStyle(fontSize: 20, fontWeight: FontWeight.w600);
  static const TextStyle sectionTitle =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
  static const TextStyle cellDate =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.15);

  /// 日历格子上「有班次」那套排布用的日期字号。
  ///
  /// 有班次时日期不再是格子里的主角 —— 班次胶囊才是，所以日期降成左上角的
  /// 定位标记，比无班次排布里的 [cellDate] 小一档。字号差别也是这排布的
  /// 一部分：日期一缩小、胶囊一放大，「这格是什么班」一眼就出来了。
  static const TextStyle cellDateSm =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.15);

  /// 日历格子里班次胶囊的文字。整格内容会按格子高度等比缩放，这是基准值。
  ///
  /// 用 w700 而不是更重的字重：设计规格把 w800 留给响铃大时钟与「今天」徽章，
  /// 胶囊靠**字号 + 底色**取得分量，不靠再压一档字重。
  ///
  /// 13 是 v0.7.2 从 15 调下来的；12 是 v0.7.3 再收一档 —— 两个字时胶囊仍会
  /// 顶到格子邊（左右只剩 1.5px），连滑块一起看很挤。
  static const TextStyle cellShift =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.15);

  static const TextStyle titleStrong =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
  static const TextStyle labelStrong =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
  static const TextStyle rowPrimary =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
  static const TextStyle rowSecondary =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
  static const TextStyle labelSecondary =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const TextStyle microStrong =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.15);
  static const TextStyle microLabel =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
  static const TextStyle microText =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
  static const TextStyle tinyLabel =
      TextStyle(fontSize: 11, fontWeight: FontWeight.w400, height: 1.15);

  /// 按比例放大/缩小一个角色令牌，其余属性（字重、行高）原样保留。
  ///
  /// 给**日历格子**用：格子的高度是按剩余空间算出来的，同一台设备上会随月份
  /// 行数、信息卡高度浮动，而字号是写死的 —— 格子长高、字不跟着长，格子里就
  /// 空出一大块，字看着就小。所以格子里的字要按格子尺寸等比缩放。
  ///
  /// 缩放系数由调用方按格子高度算好并夹住上下限，这里只做派生。字号走
  /// `t.fontSize! * s` 而不是字面量，是守门测试要求的（`fontSize:` 后跟数字
  /// 直接报红，见 `design_tokens_test.dart`）。
  static TextStyle scaled(TextStyle t, double s) =>
      t.copyWith(fontSize: t.fontSize! * s);

  // ── 图标尺寸：三档 ──
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;

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

  /// 导航胶囊上**未选中**项的前景（图标与文字）。
  ///
  /// 与 [navForeground] 同一族的「前景色已定」情形：胶囊是磨砂玻璃、压在任意
  /// 内容之上，对比度要求与页面正文不同，所以不并入 inkMuted / inkFaint 那两档
  /// （规格 §3.3 已为这类情形留了口子）。暗色下底更透，故取值比亮色更实。
  static Color navInactiveForeground(BuildContext context,
          {required bool isDark}) =>
      Theme.of(context)
          .colorScheme
          .onSurface
          .withValues(alpha: isDark ? 0.72 : 0.55);

  // ── 文字明度：两档 ──
  //
  // 「层级只靠字号、字重、明度」里的明度就是这一层。此前它没有令牌，于是
  // 次要文字散着 0.45 / 0.5 / 0.55 / 0.6 四种 alpha —— 同一个角色被调了不同值。
  // 压在主色胶囊上的次要白字不归这两档（那是「前景色已定」的情形）。

  /// 次要文字的透明度。0.62 在浅色底上过 WCAG AA 4.5:1 —— 页面底 `#F5F6FA`
  ///（最坏浅底）**4.70:1**，卡片 `#FFFFFF` 4.83:1，连最悲观的略暗玻璃卡
  /// `#EEF0F4` 也有 4.59:1。0.55 与 0.60 都不够（最坏 3.72:1 / 4.33:1），
  /// 所以本轮从 0.55 一路提到 0.62。暗色底上 0.55 起就已过。
  ///
  /// 数字按主题**真实的** `onSurface` 算：浅色走 `ColorScheme.fromSeed` 得到
  /// **`#1A1B20`**（不是 `inkLight` `#111118`）。早前照 `#111118` 估的
  /// 「0.55=4.06 / 0.60=4.78」对本 App 不成立 —— onSurface 更亮，整条曲线下移。
  static const double inkMutedAlpha = 0.62;

  /// 更淡那档的透明度。用于**禁用态 / 占位 / 待办已完成** —— 低对比正是它的
  /// 用途（已完成的删除线承载语义），因此**有意低于 AA**（0.35 → 页面底 2.16:1），
  /// 是明确豁免而不是漏网。
  static const double inkFaintAlpha = 0.35;

  static Color inkMuted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface
          .withValues(alpha: inkMutedAlpha);

  static Color inkFaint(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface
          .withValues(alpha: inkFaintAlpha);

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