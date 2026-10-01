// app/test/lens_warped_cell_test.dart
//
// 「一格内容被透镜边缘挤一下」那层变换。底栏从 v0.10.4 起就有，v0.10.10 抽成共享件
// 之后分段器也接上 —— 这两条钉的是**抽出来之后**的行为，与底栏那条像素验收互补：
// 像素只证明「底栏没变」，证明不了「这一层真的会挤」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens_controller.dart';
import 'package:shiftassistantpro/core/widgets/lens_warped_cell.dart';

void main() {
  /// 一枚 3 格、每格 100 宽的控制器。`itemW` 同时喂控制器与组件 —— 真实调用点也是
  /// 这样（`setItemW` 与 `LensWarpedCell.itemW` 是同一个数）。
  (LiquidLensController, Widget Function(double iconCenterX)) host({
    int initialSlot = 0,
  }) {
    final LiquidLensController c = LiquidLensController(
      slots: 3,
      pad: 3,
      liftWidth: 6,
      vsync: const TestVSync(),
      initialSlot: initialSlot,
    );
    c.setItemW(100);
    return (c, (double iconCenterX) => Directionality(
          textDirection: TextDirection.ltr,
          child: LensWarpedCell(
            controller: c,
            iconCenterX: iconCenterX,
            lensPad: 3,
            itemW: 100,
            halfWidth: 53,
            child: const SizedBox(width: 20, height: 20),
          ),
        ));
  }

  testWidgets('透镜不在这格附近时：恒等 → 连一层 Transform 都不套', (tester) async {
    // 透镜停在 0 格（中心 x = 3 + 0.5×100 = 53），我们看的是 400 那一格 ——
    // 离了一个半半宽以外，铃形的权重是 exp(-151)，早就在 0.01 那道门之外。
    final (LiquidLensController c, Widget Function(double) build) = host();
    addTearDown(c.dispose);
    await tester.pumpWidget(build(400));
    expect(find.byType(Transform), findsNothing,
        reason: '恒等还套一层 Transform —— 这一格会每帧重绘，而且底栏的逐像素验收'
            '就是靠「不套」才成立的');
  });

  testWidgets('透镜的边缘压在这一格上：横向压窄、纵向拉长、朝远离透镜的方向推', (tester) async {
    // 用户 2026-10-01：「滑块经过文字或者图标的时候，要有弯曲的特效」。
    // 峰值在**边缘**不在中心（厚透镜中间是平的），所以把滴挪到 1.44 格：
    //   滴中心 = 3 + 1.44×100 = 147，离 200 那一格正好一个半宽 53 → t = 1。
    final (LiquidLensController c, Widget Function(double) build) = host();
    addTearDown(c.dispose);
    await tester.pumpWidget(build(200));
    c.snapTo(1.44);
    await tester.pumpAndSettle();

    final Transform t = tester.widget<Transform>(find.byType(Transform));
    expect(t.transform.entry(0, 0), lessThan(1.0), reason: '没压窄');
    expect(t.transform.entry(1, 1), greaterThan(1.0), reason: '没纵向拉长');
    expect(t.transform.entry(0, 3), greaterThan(0),
        reason: '这一格在透镜右侧，应当被往右推');
  });

  testWidgets('推的方向永远朝远离透镜的那一侧（镜像一次）', (tester) async {
    // 同一条几何、把滴挪到这一格的**右边** → 推力必须反向。少了这条，
    // 「按符号取方向」写错成「永远往右推」也照过。
    //   滴中心 = 3 + 2.50×100 = 253（2.50 正好是夹紧的上界），离 200 一个半宽 53。
    final (LiquidLensController c, Widget Function(double) build) = host();
    addTearDown(c.dispose);
    await tester.pumpWidget(build(200));
    c.snapTo(2.50);
    await tester.pumpAndSettle();

    final Transform t = tester.widget<Transform>(find.byType(Transform));
    expect(t.transform.entry(0, 3), lessThan(0),
        reason: '透镜在右边，推力却朝右 —— 方向算反了');
  });
}
