// app/test/empty_state_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/widgets/empty_state.dart';

void main() {
  testWidgets('一句话 + 统一的次要文字色', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: EmptyState('近 30 天无班次闹钟'))));
    final text = tester.widget<Text>(find.text('近 30 天无班次闹钟'));
    expect(text.style?.fontSize, AppTokens.rowSecondary.fontSize);
  });

  testWidgets('四处留白统一是 spaceLg（此前 16/24 两种都有）', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: EmptyState('近 30 天无班次闹钟'))));
    final padding = tester.widget<Padding>(find.byType(Padding).first);
    expect(padding.padding, const EdgeInsets.all(AppTokens.spaceLg));
  });
}
