// app/test/glass_button_radius_test.dart
//
// v0.12.0 给 GlassButton 加了圆角参数，唯一目的是让编辑页那颗「保存并重排闹钟」
// 用它而不是用 Material 的 FilledButton（那颗是 48 高的胶囊，而 GlassButton 默认
// 56 高 + radiusM）。**默认值必须等于加参数之前的行为** —— 不然三个既有调用点
// （闹钟页 ×2、响铃页 ×1）会被一起改掉。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/widgets/glass_button.dart';

Future<void> _pump(WidgetTester tester, {double? radius}) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: GlassButton(
              onPressed: () {}, radius: radius ?? AppTokens.radiusM,
              child: const Text('保存')))));
}

/// 按钮那层填充装饰挂在 `Ink` 上（`GlassButton` 里没有 `Container`，构件是
/// `QScale → SizedBox → ClipRRect → GlassBlur → Material → InkWell → Ink`）。
BoxDecoration? _buttonDecoration(WidgetTester tester) {
  final ink = tester.widget<Ink>(find.descendant(
      of: find.byType(GlassButton), matching: find.byType(Ink)).first);
  return ink.decoration as BoxDecoration?;
}

void main() {
  testWidgets('不传 radius 时圆角就是 radiusM', (tester) async {
    await _pump(tester);
    expect(_buttonDecoration(tester)?.borderRadius,
        BorderRadius.circular(AppTokens.radiusM));
  });

  testWidgets('传了半径就按传的来（48 高的胶囊 = 24）', (tester) async {
    // 编辑页那颗保存胶囊的圆角 = `AppTokens.pillOf(48)` 的半径 = 24。
    final pillRadius = AppTokens.pillOf(48).topLeft.x;
    await _pump(tester, radius: pillRadius);
    expect(_buttonDecoration(tester)?.borderRadius,
        BorderRadius.circular(pillRadius));
  });
}
