// GlassTitleRow —— 弹窗 / 弹层共用的标题行。
//
// 这一件是从 `GlassDialog` 里抽出来的（v0.12.0），抽出来本身不改观感；
// 两条用例只钉它自己的两个契约：副标题可选、以及标题的默认排版角色。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/widgets/glass_title_row.dart';

void main() {
  testWidgets('传了 subtitle 就排在标题下面，不传就只有标题', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: GlassTitleRow(title: '调整班次', subtitle: Text('10月13日')))));
    expect(find.text('调整班次'), findsOneWidget);
    expect(find.text('10月13日'), findsOneWidget);
    final t = tester.getRect(find.text('调整班次'));
    final s = tester.getRect(find.text('10月13日'));
    expect(t.bottom, lessThanOrEqualTo(s.top));

    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: GlassTitleRow(title: '调整班次'))));
    expect(find.text('10月13日'), findsNothing);
  });

  testWidgets('titleStyle 不给时默认 titleStrong', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: GlassTitleRow(title: '调整班次'))));
    final text = tester.widget<Text>(find.text('调整班次'));
    expect(text.style?.fontSize, AppTokens.titleStrong.fontSize);
  });
}
