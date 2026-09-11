// app/test/design_tokens_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/theme/app_colors.dart';

double _wcagContrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('圆角/间距/模糊令牌为预期档位', () {
    expect(AppTokens.radiusS, 12);
    expect(AppTokens.radiusM, 16);
    expect(AppTokens.radiusL, 22);
    expect(AppTokens.radiusXL, 28);
    expect(AppTokens.blurChip, 12);
    expect(AppTokens.blurCard, 18);
    expect(AppTokens.blurPanel, 24);
  });

  test('中性背景与语义色非空且区分明暗', () {
    expect(AppTokens.bgLight, isNot(equals(AppTokens.bgDark)));
    expect(AppTokens.inkLight, isNot(equals(AppTokens.inkDark)));
    expect(AppTokens.danger, const Color(0xFFE53935));
  });

  test('accentGradient 用 accent 色：顶 0.85 底 0.50', () {
    final g = AppTokens.accentGradient(const Color(0xFF00C7BE));
    expect(g.colors.first, const Color(0xFF00C7BE).withValues(alpha: 0.85));
    expect(g.colors.last, const Color(0xFF00C7BE).withValues(alpha: 0.50));
  });

  test('玻璃配方随明暗变化（暗色更淡）', () {
    final lightTop = AppTokens.glassTint(false, true).first;
    final darkTop = AppTokens.glassTint(true, true).first;
    expect(lightTop.a, greaterThan(darkTop.a));
  });

  test('navBorder 亮色为深描边、暗色为白描边', () {
    final light = AppTokens.navBorder(false);
    final dark = AppTokens.navBorder(true);
    expect(light.r, lessThan(0.3)); // 深色
    expect(dark.r, greaterThan(0.9)); // 白
    expect(light.a, greaterThan(0.08));
  });

  test('5 个主题色在胶囊滑块上文字对比度 ≥ 4.5', () {
    // 模拟滑块：主题色渐变与玻璃底按 60% 混合（文字所在区域的近似比例）
    const bgLight = Color(0xFFF5F6FA);
    const bgDark = Color(0xFF16161E);
    for (final accent in AppColors.accentPalette) {
      final sliderLight = Color.lerp(bgLight, accent, 0.6)!;
      expect(
        _wcagContrast(AppTokens.navForeground(false, accent), sliderLight),
        greaterThanOrEqualTo(4.5),
        reason: '亮色模式 $accent',
      );
      final sliderDark = Color.lerp(bgDark, accent, 0.6)!;
      expect(
        _wcagContrast(AppTokens.navForeground(true, accent), sliderDark),
        greaterThanOrEqualTo(4.5),
        reason: '暗色模式 $accent',
      );
    }
  });

  test('onSolid：任何底色上的文字对比度都 ≥ 4.5', () {
    // 白/黑两条对比度曲线在亮度 0.179 处交叉，交叉点上各是 4.58:1 ——
    // 所以「取对比度高的一侧」对**任何**底色都能过 AA。
    const samples = <Color>[
      Color(0xFF4C8DFF),
      Color(0xFF7A5CFF),
      Color(0xFF9AA0B4),
      Color(0xFF5A5F73),
      Color(0xFF34C759),
      Color(0xFFFF9F0A),
      Color(0xFFFF375F),
      Color(0xFF00C7BE),
      Color(0xFFFFFFFF),
      Color(0xFF000000),
    ];
    for (final bg in samples) {
      expect(_wcagContrast(AppTokens.onSolid(bg), bg), greaterThanOrEqualTo(4.5),
          reason: '底色 $bg 上取到的文字色不可读');
    }
    for (final accent in AppColors.accentPalette) {
      expect(_wcagContrast(AppTokens.onSolid(accent), accent),
          greaterThanOrEqualTo(4.5),
          reason: '主题色 $accent 上取到的文字色不可读');
    }

    // 钉住几个具体选择：只断言「对比度够」的话，把实现换成恒定白字仍然
    // 会在橙、绿、灰上失败，但在蓝紫上会通过 —— 那说明它没在按底色选。
    expect(AppTokens.onSolid(const Color(0xFF4C8DFF)), Colors.black);
    expect(AppTokens.onSolid(const Color(0xFF7A5CFF)), Colors.black);
    expect(AppTokens.onSolid(const Color(0xFF9AA0B4)), Colors.black);
    expect(AppTokens.onSolid(const Color(0xFFFF9F0A)), Colors.black);
    expect(AppTokens.onSolid(const Color(0xFF5A5F73)), Colors.white);
  });
}