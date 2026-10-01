// `GlassSegment` 接上液态档之后的护栏。
//
// 「关掉液态档时与改之前逐像素相同」不在这里验 —— 分段器长在各页里（闹钟 / 我的 /
// 排班编辑器 / 待办），那条由 `tool/visual` 的整屏逐像素比兜着（见计划的 Task 6
// Step 6）。这里只钉三件单屏照不出来的事。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/widgets/glass_segment.dart';

void main() {
  const double h = 44;

  Future<List<int>> shot(
    WidgetTester tester, {
    required bool liquid,
    double width = 300,
    int selected = 0,
  }) async {
    liquidGlassActive.value = liquid;
    addTearDown(() => liquidGlassActive.value = false);

    tester.view.physicalSize = Size(width, 120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: width,
              height: h,
              child: GlassSegment(
                count: 3,
                selectedIndex: selected,
                height: h,
                onSelected: (int _) {},
                itemBuilder: (int i, bool sel) => Text('$i',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
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

  testWidgets('两档是两棵树：光栅化像素必须不同', (tester) async {
    // 反过来说：这条要是绿着不动，说明「液态档」根本没生效 —— v0.10.1 出过这个岔子
    // （工装那两张「液态档」基线图与标准档逐字节相同）。
    final List<int> off = await shot(tester, liquid: false);
    final List<int> on = await shot(tester, liquid: true);
    int differing = 0;
    for (int i = 0; i < off.length; i++) {
      if (off[i] != on[i]) differing++;
    }
    expect(differing, greaterThan(0), reason: '开了液态档却一个像素都没变');
  });

  testWidgets('浅色档：胶囊左右两条边同值（液态档的边光是竖直的）', (tester) async {
    const int w = 300;
    // ⚠️ **选中中间那一格**：分段器铺满整行，选中第 0 格时那枚滴就压在左端上，
    // 量到的「左端」是滴而不是胶囊的边（底栏因为外面还有 outerPad 留白，两端是空的
    // —— 所以那条用例的取法在这里不适用）。
    final List<int> px =
        await shot(tester, liquid: true, width: w.toDouble(), selected: 1);
    const int y = 60; // 画布 120 高，胶囊竖直居中
    int darkest(int from, int to) {
      int v = 255;
      for (int x = from; x <= to; x++) {
        if (red(px, w, x, y) < v) v = red(px, w, x, y);
      }
      return v;
    }

    final int left = darkest(0, 6);
    final int right = darkest(w - 7, w - 1);
    expect((left - right).abs(), lessThanOrEqualTo(4),
        reason: '左右两条边差 $left vs $right —— 边光又在按对角走了');
  });

  testWidgets('窄窗（200 宽、3 格）：透镜还在第一格上', (tester) async {
    // 胶囊窄到一定程度会落进 `toPath()` 的退化分支（宽 <= 高）。底栏在那里栽过一次
    // Critical（透镜整个消失、还一闪一没），所以这一档必须钉住。
    const int w = 200;
    final List<int> px = await shot(tester, liquid: true, width: w.toDouble());
    const double itemW = 200 / 3;
    final int x0 = (itemW / 2).round();
    final int x2 = (itemW * 2.5).round();
    expect((red(px, w, x0, 52) - red(px, w, x2, 52)).abs(), greaterThan(20),
        reason: '窄窗下第一格与最后一格一样 —— 透镜消失了');
  });
}
