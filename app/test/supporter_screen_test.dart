// app/test/supporter_screen_test.dart
//
// 支持者专属页：第一封来信与「以后还会加」的留坑说明。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/features/profile/supporter_screen.dart';

void main() {
  setUp(() => L10n.locale = 'zh');

  testWidgets('支持者页显示第一封来信与留坑说明', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SupporterScreen()));
    await tester.pumpAndSettle();

    expect(find.text(L10n.supporterLetterTitle), findsOneWidget);
    expect(find.textContaining('谢谢你愿意'), findsOneWidget);
    expect(find.text(L10n.supporterMoreComing), findsOneWidget);
  });
}
