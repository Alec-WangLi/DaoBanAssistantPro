// app/test/glass_button_disabled_test.dart
//
// v0.12.0 把编辑页那颗「保存并重排闹钟」从 Material `FilledButton` 换成了自家的
// `GlassButton` —— 顺带失掉了 `FilledButton` 自带的禁用变灰，而编辑页在保存中正
// 会传 `onPressed: null`。所以 `GlassButton` 必须自己补上禁用态：**整体压暗** +
// **按下不形变**。这两条是这一版的收口，谁把禁用态删掉它们就红。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/motion.dart';
import 'package:shiftassistantpro/core/widgets/glass_button.dart';

Future<void> _pump(WidgetTester tester, {required VoidCallback? onPressed}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: GlassButton(onPressed: onPressed, child: const Text('保存')),
    ),
  ));
}

QScale _qscale(WidgetTester tester) => tester.widget<QScale>(find.descendant(
    of: find.byType(GlassButton), matching: find.byType(QScale)));

void main() {
  testWidgets('onPressed 为 null：整体压暗（多出一层 Opacity）', (tester) async {
    await _pump(tester, onPressed: null);
    final op = tester.widget<Opacity>(find
        .descendant(
            of: find.byType(GlassButton), matching: find.byType(Opacity))
        .first);
    expect(op.opacity, lessThan(1.0));
  });

  testWidgets('onPressed 为 null：按下去也不弹（QScale.pressed 恒 false）',
      (tester) async {
    await _pump(tester, onPressed: null);
    final g =
        await tester.startGesture(tester.getCenter(find.byType(GlassButton)));
    await tester.pump();
    expect(_qscale(tester).pressed, isFalse);
    await g.up();
  });

  // 对照：非 null 时按下**会**弹。没有它，上一条即使把整段按压逻辑删掉也照样绿。
  testWidgets('onPressed 非 null：按下会弹（对照，证明上一条有鉴别力）',
      (tester) async {
    await _pump(tester, onPressed: () {});
    final g =
        await tester.startGesture(tester.getCenter(find.byType(GlassButton)));
    await tester.pump();
    expect(_qscale(tester).pressed, isTrue);
    await g.up();
  });
}
