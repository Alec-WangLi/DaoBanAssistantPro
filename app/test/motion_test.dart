// app/test/motion_test.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/motion.dart';

void main() {
  test('qSpring 欠阻尼（阻尼比 < 1，产生 Q 弹过冲）', () {
    final ratio = AppTokens.qSpring.damping /
        (2 * math.sqrt(AppTokens.qSpring.stiffness * AppTokens.qSpring.mass));
    expect(ratio, lessThan(1.0));
    expect(ratio, greaterThan(0.0));
  });

  testWidgets('QScale 按下从 1.0 弹向 scale', (tester) async {
    var pressed = false;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => pressed = !pressed),
        child: QScale(
          pressed: pressed,
          scale: 0.96,
          child: const SizedBox(width: 10, height: 10),
        ),
      ),
    ));

    var scale = tester
        .widget<ScaleTransition>(find.byType(ScaleTransition))
        .scale
        .value;
    expect(scale, closeTo(1.0, 0.001));

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    scale = tester
        .widget<ScaleTransition>(find.byType(ScaleTransition))
        .scale
        .value;
    expect(scale, lessThan(1.0));
  });
}