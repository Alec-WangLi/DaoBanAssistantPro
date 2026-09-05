// app/test/app_icon_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/widgets/app_icon.dart';

void main() {
  testWidgets('AppIcon 渲染给定 size', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AppIcon(icon: Icons.alarm_outlined, size: 22),
    ));
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.size, 22);
    expect(icon.icon, Icons.alarm_outlined);
  });
}