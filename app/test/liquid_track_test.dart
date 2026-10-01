// `LiquidTrack` 的护栏：那棵树真的画了透镜、两个开关真的能关掉、窄窗不炸。
//
// 这一件是底栏 / 分段器 / 开关共用的，所以「底栏渲染逐像素不变」那条验收最终压在
// 它身上 —— 用例只钉最容易被改坏的三件事。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens_controller.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens_metrics.dart';
import 'package:shiftassistantpro/core/widgets/liquid_track.dart';

void main() {
  const double pad = 6;

  /// 装一个 3 格、40 高的轨道并光栅化。返回 (像素, 画布宽)。
  Future<List<int>> shot(
    WidgetTester tester, {
    double width = 300,
    double capsuleH = 40,
    bool showGlowBand = true,
    bool showRefractedEdge = true,
    bool fillWhite = false,
  }) async {
    const int n = 3;
    tester.view.physicalSize = Size(width, 120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final LiquidLensController c = LiquidLensController(
      slots: n,
      pad: pad,
      liftWidth: 6,
      vsync: const TestVSync(),
    );
    addTearDown(c.dispose);
    c.setItemW((width - 2 * pad) / n);

    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: width,
              height: capsuleH,
              child: LiquidTrack(
                slots: n,
                capsuleH: capsuleH,
                pad: pad,
                controller: c,
                metrics: LiquidLensMetrics.forCapsule(capsuleH),
                showGlowBand: showGlowBand,
                showRefractedEdge: showRefractedEdge,
                fill: fillWhite
                    ? const <Color>[Colors.white, Colors.white]
                    : null,
                contentBuilder: (BuildContext ctx, double itemW) => Row(
                  children: List<Widget>.generate(
                    n,
                    (int i) => Expanded(
                      child: Center(
                        child: Text('$i',
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    late List<int> px;
    await tester.runAsync(() async {
      final RenderRepaintBoundary b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await b.toImage(pixelRatio: 1.0);
      final ByteData? d =
          await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      px = d!.buffer.asUint8List().toList();
    });
    return px;
  }

  int red(List<int> px, int w, int x, int y) => px[(y * w + x) * 4];

  testWidgets('透镜真的画了：第一格与最后一格的像素不一样', (tester) async {
    const int w = 300;
    final List<int> px = await shot(tester, width: w.toDouble());
    const double itemW = (300 - 2 * pad) / 3;
    // 取每一格**靠上**那一点（胶囊在 y 40..80，文字在正中；52 避开它）
    final int x0 = (pad + itemW / 2).round();
    final int x2 = (pad + itemW * 2.5).round();
    expect(
      (red(px, w, x0, 52) - red(px, w, x2, 52)).abs(),
      greaterThan(20),
      reason: '第一格和最后一格一样 —— 透镜没画出来（或者画到了别处）',
    );
  });

  testWidgets('showGlowBand：关掉之后树上就没有 CapsuleRimPainter 了', (tester) async {
    bool hasRim() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((CustomPaint p) => p.painter is CapsuleRimPainter);

    await shot(tester, showGlowBand: true);
    expect(hasRim(), isTrue, reason: '开着却没有那条光带 —— 这条测不出东西');
    await shot(tester, showGlowBand: false);
    expect(hasRim(), isFalse, reason: '关了却还在画 —— 开关没接上');
  });

  testWidgets('窄窗（200 宽的胶囊）：不抛异常，且透镜仍占着第一格', (tester) async {
    const int w = 200;
    final List<int> px = await shot(tester, width: w.toDouble());
    const double itemW = (200 - 2 * pad) / 3;
    final int x0 = (pad + itemW / 2).round();
    final int x2 = (pad + itemW * 2.5).round();
    expect((red(px, w, x0, 52) - red(px, w, x2, 52)).abs(), greaterThan(20),
        reason: '窄窗下透镜消失了');
  });

  testWidgets('换 fill 会真的换掉本体（开关那一档是白玻璃）', (tester) async {
    const int w = 300;
    final List<int> tinted = await shot(tester, width: w.toDouble());
    final List<int> white =
        await shot(tester, width: w.toDouble(), fillWhite: true);
    const double itemW = (300 - 2 * pad) / 3;
    final int x0 = (pad + itemW / 2).round();
    final int d = (red(tinted, w, x0, 52) - red(white, w, x0, 52)).abs();
    expect(d, greaterThan(10), reason: '换了 fill 本体却没变（差 $d）—— 参数没透下去');
  });
}
