// `LiquidTrack` 的护栏：那棵树真的画了透镜、两个开关真的能关掉、窄窗不炸。
//
// 这一件是底栏 / 分段器 / 开关共用的，所以「底栏渲染逐像素不变」那条验收最终压在
// 它身上 —— 用例只钉最容易被改坏的三件事。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
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
    bool showRefractedEdge = true,
    bool fillWhite = false,
    // 「跟随滑块」那条亮带在**浅色下是白压白、结构性地看不见**（实测整个上沿
    // 235~237 一条平的）—— 要量它必须切到深色。
    bool dark = false,
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
        theme: dark ? ThemeData.dark() : null,
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

  testWidgets('胶囊的边光是**水平均匀**的：那条「跟随滑块」的亮带已经拆掉', (tester) async {
    // 用户 2026-10-01：「我发现你这个底部导航栏的液态玻璃滑块，还有主题模式等那些
    // 较长的滑块，中间边缘怎么都会发光啊？尤其是在深色模式下很明显」。
    // 那团光就是 `CapsuleRimPainter` 的 sliderIndex 亮带（深色下白 @0.95、模糊 3、
    // 再加宽 1.4 倍），落在滑块所在的那一段胶囊边上。滴在这几处几乎填满胶囊高，
    // 亮带只剩**溢出到胶囊外**的那半截能看见 —— 读起来像「边缘漏了个光斑」而不是
    // 「边上有光」。三处一起关掉（开关自 v0.10.9 起就关着）。
    //
    // 判据是**同一条边上的横向均匀性**：方向性边光的渐变轴是**竖直**的（v0.10.6
    // 那条修的就是这个），所以左右两端必然等值；亮带一挂上去，滑块那一带就偏亮。
    const int w = 300;
    // **必须在深色下量。** 那条亮带在浅色下是白压白：实测整条上沿 235~237 一条平的，
    // 拆没拆一个样（第一版就是这么写的，绿着不动）。深色下它才现形。
    final List<int> px = await shot(tester, width: w.toDouble(), dark: true);
    // 胶囊竖直居中在画布 120 高里 → 上沿在 y = 40，取 41（落在描边那一两个像素内）。
    // 滑块停在第 0 格：3 格 300 宽、内缩 6 → 每格 96，中心 = 6 + 0.5×96 = 54。
    // 实测（同一行）：
    //   亮带在：x=20 → 40，x=54 → **74**（滑块那一带鼓出来 34 级）
    //   拆掉后：x=20 → 40，x=54 → 39（一条平的缓坡，那是胶囊填充的对角渐变）
    int lum(int x) => red(px, w, x, 41);
    final int bump = lum(54) - lum(20);
    expect(bump, lessThanOrEqualTo(6),
        reason: '滑块那一带的边比左端亮 $bump 级 —— 亮带没拆干净');
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
