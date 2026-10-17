// app/test/glass_segment_ink_test.dart
//
// 分段器**选中那一格**的字色。
//
// 起因（v0.11.22）：v0.11.21 把实心主色面换成不透明 + 压深之后，选中格的字色
// 仍然跟着主题走 —— 浅色档下就是「近黑字压深蓝块」，实测 **1.55:1**。
// 出对照图时一眼看得见，而当时一条用例都没照到：`design_tokens_test` 里那条
// 模拟的还是**半透明**滑块（`Color.lerp(bg, accent, 0.6)`），于是它一直是假的绿。
//
// 这一条判的不是「颜色等于白」，而是**「它压在的那块底上够不够读」** ——
// 以后谁再把滑块换个材质，这条照样有鉴别力。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/theme/app_colors.dart';
import 'package:shiftassistantpro/core/theme/app_theme.dart';
import 'package:shiftassistantpro/core/widgets/glass_segment.dart';

/// 某段文字**最终画出来**的颜色：自身样式压在环境的 `DefaultTextStyle` 之上
/// （`Text` 的 `style` 里没写 `color` 时，颜色就是从环境继承的）。
Color? _resolvedColor(WidgetTester tester, String label) {
  final element = tester.element(find.text(label));
  final own = tester.widget<Text>(find.text(label)).style;
  return DefaultTextStyle.of(element).style.merge(own).color;
}

void main() {
  testWidgets('浅色档：分段器选中项的字压在实心主色滑块上，必须够读', (tester) async {
    for (final accent in AppColors.accentPalette) {
      await tester.pumpWidget(MaterialApp(
        theme: buildLightTheme(seed: accent),
        home: Scaffold(
          body: Center(
            child: GlassSegment(
              count: 3,
              selectedIndex: 1,
              onSelected: (_) {},
              itemBuilder: (i, selected) => Text(
                '选项$i',
                // 调用点的写法就是这样的：只给字重、**不给颜色**（颜色由环境决定）。
                style: AppTokens.labelSecondary.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final surface = AppTokens.solidAccent(accent);
      final selected = _resolvedColor(tester, '选项1')!;
      expect(
        AppTokens.contrastRatio(selected, surface),
        greaterThanOrEqualTo(4.5),
        reason: '$accent：选中项的字压在实心滑块上不达 AA（$selected on $surface）',
      );

      // **未选中的那几格不许被一起涂白** —— 它们压在玻璃轨道上，照常吃主题的正文色。
      final unselected = _resolvedColor(tester, '选项0')!;
      expect(unselected, isNot(Colors.white),
          reason: '$accent：未选中项不该跟着变白');
      expect(selected, isNot(unselected),
          reason: '$accent：选中与未选中应该看得出区别');
    }
  });
}
