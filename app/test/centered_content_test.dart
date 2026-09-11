// app/test/centered_content_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/layout.dart';
import 'package:shiftassistantpro/core/widgets/centered_content.dart';

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(
      body: CenteredContent(
        child: SizedBox(height: 100, width: double.infinity, child: Text('x')),
      ),
    ),
  ));
}

void main() {
  testWidgets('宽屏：内容限宽居中', (tester) async {
    await _pump(tester, const Size(1280, 720));

    expect(tester.getSize(find.text('x')).width,
        lessThanOrEqualTo(AppLayout.maxContentWidth));

    // 居中：左右留白相等
    final left = tester.getTopLeft(find.text('x')).dx;
    final right = 1280 - tester.getTopRight(find.text('x')).dx;
    expect((left - right).abs(), lessThan(1));
  });

  testWidgets('窄屏：不介入，内容仍然拉满', (tester) async {
    await _pump(tester, const Size(420, 900));
    expect(tester.getSize(find.text('x')).width, 420);
  });
}
