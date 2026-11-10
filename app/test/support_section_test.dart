// app/test/support_section_test.dart
//
// 「我的 → 支持」两态：未打赏显示锁，已打赏显示信。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/features/profile/about_section.dart';

void main() {
  setUp(() => L10n.locale = 'zh');

  testWidgets('未支持时显示锁定态', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SupportSection())),
    );
    await tester.pumpAndSettle();

    expect(find.text(L10n.supporterOnly), findsOneWidget);
    expect(find.text(L10n.supportUnlockHint), findsOneWidget);
  });

  testWidgets('已支持时显示解锁态', (tester) async {
    SharedPreferences.setMockInitialValues({'supporterUnlocked': true});
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SupportSection())),
    );
    await tester.pumpAndSettle();

    expect(find.text(L10n.supporterOnly), findsOneWidget);
    expect(find.text(L10n.supportUnlockedHint), findsOneWidget);
  });
}
