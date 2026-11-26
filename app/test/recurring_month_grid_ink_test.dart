// app/test/recurring_month_grid_ink_test.dart
//
// 「重复待办」里每月多选的那 31 格：**选中日压在什么底色上、字够不够读**。
//
// 起因（v0.14.1）：D3 规定实心主色面一律走 `solidAccent` 压深 + `onSolid` 取字色，
// 但这条只在 `glass_check` / `glass_pill` / `glass_switch` 等共享件里落实了 ——
// `recurring_fields.dart` 的月网格是**页面内自己画的**，直接用 `primary` 当底、
// `Colors.white` 当字。默认那颗蓝 5.26:1 看不出来，选 teal / orange 时只有
// 2.63 / 2.55，白字糊在块上。`design_tokens_test` 里那条 AA 用例钉的是配方
// （压深之后过线），钉不到调用点 —— 这正是 D3 的已知盲区。
//
// 这一条判的不是「颜色等于白」，而是**「它压在那块底上够不够读」**：以后谁把这块
// 换成别的材质，用例照样有鉴别力（与 `glass_segment_ink_test.dart` 同一套路）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/theme/app_colors.dart';
import 'package:shiftassistantpro/core/theme/app_theme.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/features/schedule/recurring_fields.dart';

/// 某段文字**最终画出来**的颜色：自身样式压在环境的 `DefaultTextStyle` 之上。
Color? _resolvedColor(WidgetTester tester, String label) {
  final element = tester.element(find.text(label));
  final own = tester.widget<Text>(find.text(label)).style;
  return DefaultTextStyle.of(element).style.merge(own).color;
}

/// 离这段文字最近的、带实心底色的那个 [AnimatedContainer] 的装饰。
///
/// 用「最近的有色祖先」而不是写死某个 key：网格的层级一改（多包一层 padding /
/// FittedBox），用例不该跟着红。
BoxDecoration _chipDecoration(WidgetTester tester, String label) {
  final ancestors = tester.widgetList<AnimatedContainer>(
    find.ancestor(
      of: find.text(label),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return ancestors
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .firstWhere((d) => d.color != null);
}

Widget _host(Color accent) => MaterialApp(
      theme: buildLightTheme(seed: accent),
      home: Scaffold(
        body: SingleChildScrollView(
          child: RecurringRulePicker(
            // 1 << 14 = 第 15 天。
            value: const RecurRuleValue(
              repeat: RecurRepeat.monthly,
              monthDays: 1 << 14,
            ),
            shiftChoices: const [],
            fallbackDay: DateTime(2026, 10, 15),
            fallbackShiftName: null,
            onChanged: (_) {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('每月多选格：选中日的白字压在实心主色上，必须过 AA', (tester) async {
    for (final accent in AppColors.accentPalette) {
      await tester.pumpWidget(_host(accent));
      await tester.pumpAndSettle();

      final chip = _chipDecoration(tester, '15');
      final ink = _resolvedColor(tester, '15')!;

      expect(
        AppTokens.contrastRatio(ink, chip.color!),
        greaterThanOrEqualTo(4.5),
        reason: '$accent：第 15 天的字压在选中块上不达 AA（$ink on ${chip.color}）',
      );
    }
  });

  testWidgets('选中日的底色必须是压深后的实心主色，不是原始 primary', (tester) async {
    // 只断言「对比度够」是不够的：把字换成黑色也能让上面那条过，但那就不是
    // 设计语言里的做法了。这条钉住**用的是哪个配方**。
    for (final accent in AppColors.accentPalette) {
      await tester.pumpWidget(_host(accent));
      await tester.pumpAndSettle();

      final chip = _chipDecoration(tester, '15');
      expect(
        chip.color,
        AppTokens.solidAccent(accent),
        reason: '$accent：选中块没走 solidAccent（D3）',
      );
      expect(
        _resolvedColor(tester, '15'),
        AppTokens.onSolid(AppTokens.solidAccent(accent)),
        reason: '$accent：选中日的字没走 onSolid（D3）',
      );
    }
  });

  testWidgets('未选中的日子保持原样：不吃主色、也不跟着变白', (tester) async {
    await tester.pumpWidget(_host(AppColors.accentPalette.first));
    await tester.pumpAndSettle();

    final selected = _chipDecoration(tester, '15');
    final unselected = _chipDecoration(tester, '16');
    expect(unselected.color, isNot(selected.color),
        reason: '未选中的格子不该被一起涂成实心主色');
    expect(_resolvedColor(tester, '16'), isNot(Colors.white),
        reason: '未选中的字照常吃主题的正文色');
  });
}
