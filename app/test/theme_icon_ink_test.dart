// app/test/theme_icon_ink_test.dart
//
// **图标的兜底色是主题给的，不是 `IconThemeData.fallback()` 的纯黑。**
//
// 2026-11-23 统计页修过一次「深色下图标发暗」，当时是逐处显式取色；2026-11-25
// 用户又在「关于倒班助手Pro」里看到同样的黑压黑 —— 因为根主题只写了
// `IconThemeData(size:)`，color 是 null，全库 115 处没给 color 的图标都落到
// fallback 的纯黑。修法收到主题这一处：两档都显式给 `colorScheme.onSurface`。
//
// 这个测试钉三件事：① 两档主题的 iconTheme 都有 color 且是对比够的 onSurface；
// ② 一枚裸 Icon 在深色下的解析结果不再是纯黑；③ 「关于」页（用户报的那一屏）
// 的行图标实际解析到 onSurface。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/theme/app_theme.dart';
import 'package:shiftassistantpro/features/profile/about_screen.dart';

/// WCAG 对比度（图标是「非文本」，门槛 3:1）。
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('两档主题都给图标兜底了 onSurface，且对背景够 3:1', () {
    for (final theme in [buildLightTheme(), buildDarkTheme()]) {
      expect(theme.iconTheme.size, AppTokens.iconLg);
      expect(theme.iconTheme.color, theme.colorScheme.onSurface,
          reason: '没给 color 的图标会落到 fallback 的纯黑（深色下黑压黑）');
      expect(
        _contrast(theme.iconTheme.color!, theme.scaffoldBackgroundColor),
        greaterThanOrEqualTo(3.0),
        reason: '图标对页面底色要过 3:1',
      );
    }
  });

  testWidgets('裸 Icon 在深色主题下解析到 onSurface，不是 fallback 纯黑', (tester) async {
    final theme = buildDarkTheme();
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          final ink = IconTheme.of(context).color;
          expect(ink, theme.colorScheme.onSurface);
          expect(ink, isNot(const IconThemeData.fallback().color),
              reason: 'fallback 是纯黑，深色下就是它让图标消失的');
          return const Icon(Icons.info_outline);
        },
      ),
    ));
  });

  testWidgets('「关于」页在深色下的行图标走 onSurface', (tester) async {
    final theme = buildDarkTheme();
    await tester.pumpWidget(MaterialApp(theme: theme, home: const AboutScreen()));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byIcon(Icons.person_outline).first);
    expect(IconTheme.of(ctx).color, theme.colorScheme.onSurface,
        reason: '这一屏就是用户 2026-11-25 报「图标太暗」的地方');
  });
}
