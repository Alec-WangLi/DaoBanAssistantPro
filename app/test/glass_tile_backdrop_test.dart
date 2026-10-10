// app/test/glass_tile_backdrop_test.dart
//
// **卡片背后是平色，糊了等于没糊 —— 却要付一次 backdrop 渲染通道的钱。**
//
// 真机实测（Redmi K25102RKBEC，屏幕全程 120Hz ⇒ 帧预算 8.33ms）：编辑排班页
// 滑动时 raster p90 **13.10ms**、**13.4%** 的帧掉拍；把卡片的 `BackdropFilter`
// 摘掉之后 p90 **2.37ms**、掉拍约 2%。而**只留模糊（σ 仍 18）p90 是 7.92、
// 只留饱和度矩阵是 8.21** —— 所以贵的是那条渲染通道本身，不是滤镜算什么。
//
// 这个文件钉三件事，缺一条都会悄悄退化：
//   1) `GlassTile` **不挂** `BackdropFilter`；
//   2) 它的填充**仍然是 translucentFill 那一支** —— 摘模糊时顺手把填充换成
//      低端档那支更实的，就是肉眼可见的观感变化（出图比过）；
//   3) 对照：`GlassPanel` 自己**默认仍然挂**（弹层 / 悬浮栏要用）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(body: Center(child: child)),
    );

/// 取 `GlassPanel` 那棵子树里最外层那个带装饰的 `Container` 的 `decoration`。
BoxDecoration _panelDecoration(WidgetTester tester) {
  final Container container = tester.widget<Container>(
    find
        .descendant(
            of: find.byType(GlassPanel), matching: find.byType(Container))
        .first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets('GlassTile 不挂 BackdropFilter', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const GlassTile(child: Text('x'))));
    expect(find.byType(BackdropFilter), findsNothing,
        reason: '卡片一旦挂回 BackdropFilter，这一帧就多一次 backdrop 渲染通道 —— '
            '真机实测编辑排班页 raster p90 会从 2.4ms 涨回 13.1ms、掉拍从 2% 涨回 13%');
  });

  testWidgets('GlassTile 的填充仍是 translucentFill 那一支', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const GlassTile(child: Text('x'))));
    final LinearGradient g = _panelDecoration(tester).gradient! as LinearGradient;
    expect(g.colors, AppTokens.glassSurface(true, true),
        reason: '摘模糊**不许**连带换填充 —— 更实的那支是低端档的补偿配方，'
            '换上去是肉眼可见的观感变化');
  });

  testWidgets('对照：GlassPanel 默认仍然挂 BackdropFilter', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const GlassPanel(child: Text('x'))));
    expect(find.byType(BackdropFilter), findsOneWidget,
        reason: '弹层 / 悬浮栏背后是正文，它们要糊');
  });
}
