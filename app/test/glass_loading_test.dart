import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/widgets/glass_loading.dart';

void main() {
  testWidgets('粗细由 size 推出来，不手写', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GlassLoading())));
    final p = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
    expect(p.strokeWidth, 3.0);
  });

  testWidgets('小号传 24 时粗细是 2.0（与权限卡原来那个一致）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GlassLoading(size: 24))));
    final p = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
    expect(p.strokeWidth, 2.0);
  });
}
