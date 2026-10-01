// `GlassSwitch` 接上液态档之后的护栏。
//
// 「关掉液态档时与改之前逐像素相同」不在这里验 —— 开关长在七个界面里，那条由
// `tool/visual` 的整屏逐像素比兜着。这里钉三件单屏照不出来的事。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';

void main() {
  Future<void> pumpSwitch(
    WidgetTester tester, {
    required bool liquid,
    bool value = false,
    bool enabled = true,
  }) async {
    liquidGlassActive.value = liquid;
    addTearDown(() => liquidGlassActive.value = false);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Center(
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => GlassSwitch(
              value: value,
              enabled: enabled,
              onChanged: (bool v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  LiquidLens lensOf(WidgetTester tester) =>
      tester.widget<LiquidLens>(find.byType(LiquidLens));

  testWidgets('静止：钮是一枚圆球（宽 ≈ 高），坐在轨道里', (tester) async {
    await pumpSwitch(tester, liquid: true);
    // 轨道 46×28、内缩 3 → 每格 (46−6)/2 = 20；钮高 = 28−6 = 22
    expect(lensOf(tester).shape.width, closeTo(20, 0.5));
    expect(lensOf(tester).shape.height, closeTo(22, 0.5));
    expect((lensOf(tester).shape.width - lensOf(tester).shape.height).abs(),
        lessThan(2.5),
        reason: '静止时钮不是圆的 —— 共享件把它变成了胶囊');
  });

  testWidgets('按住：钮**纵向**拉长，宽度不变', (tester) async {
    // 用户 2026-10-01：「按住的时候不是要放大吗？那就要做成往纵向放大，
    // 参考 iOS 26 他们的开关液态玻璃那种形状变化」。
    await pumpSwitch(tester, liquid: true);
    final Size before = Size(lensOf(tester).shape.width,
        lensOf(tester).shape.height);

    final Rect box = tester.getRect(find.byType(GlassSwitch));
    final TestGesture g = await tester.startGesture(box.center);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16)); // 320ms，过按住闸门
    }

    final Size after = Size(lensOf(tester).shape.width,
        lensOf(tester).shape.height);
    expect(after.height, greaterThan(28),
        reason: '按住之后钮没有高过轨道（${after.height}）—— 没有「被抽出来」');
    expect(after.height, greaterThan(before.height + 10));
    expect(after.width, closeTo(before.width, 0.5),
        reason: '宽度也变了（${before.width} → ${after.width}）—— 要的是只长个儿');
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('置灰：即使液态档开着也走标准档那棵（树上没有透镜）', (tester) async {
    // 「这台机器打不开那个效果」与「那个效果作用于哪里」无关 —— 低内存机器上
    // 「我的 → 外观 → 液态玻璃」那一行仍然是灰的。
    await pumpSwitch(tester, liquid: true, enabled: false);
    expect(find.byType(LiquidLens), findsNothing,
        reason: '置灰态跟着液态档一起换树了');
  });

  testWidgets('标准档：树上没有透镜（两棵树真的分开了）', (tester) async {
    await pumpSwitch(tester, liquid: false);
    expect(find.byType(LiquidLens), findsNothing);
  });
}
