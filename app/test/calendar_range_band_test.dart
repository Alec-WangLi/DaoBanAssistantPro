// app/test/calendar_range_band_test.dart
//
// 那枚水带的**弹簧与观感**：漫上来、末端淌过去、沿运动方向鼓出、彩边跟着方向。
//
// ⚠️ 一律走几何与帧调度，**不拿光栅亮度当判据** —— 带子压在白色卡片上，亮度差被卡片
// 自己的底色吃掉（日历页那条「缝隙量不出来」的教训）。
import 'dart:ui' as ui;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/features/calendar/calendar_range_band.dart';

void main() {
  const double cellW = 56.5714;
  const double cellH = 85;
  const double hPad = 12;
  const double weekdayH = 26;
  const double gridW = 7 * cellW + 2 * hPad;
  const double gridH = weekdayH + 5 * cellH;
  const double innerH = cellH - 2 * AppTokens.gapHair;

  /// 取像用的 key（**每帧新建**：要的是这一帧画出来的像素，不是缓存层）。
  final GlobalKey shotKey = GlobalKey();

  /// 挂一条带子：`from..tipCell` 是同一行里那一段（吸附到格的状态）。
  Future<void> mount(WidgetTester tester,
      {required int tipCell, int from = 2}) async {
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
        child: RepaintBoundary(
          key: shotKey,
          child: SizedBox(
          width: gridW,
          height: gridH,
          child: CalendarRangeBand(
            size: const Size(gridW, gridH),
            cellW: cellW,
            cellH: cellH,
            hPad: hPad,
            weekdayH: weekdayH,
            runs: <({int row, int firstCol, int lastCol})>[
              (row: 0, firstCol: from, lastCol: tipCell),
            ],
            movingEnd: true,
            tipCell: tipCell,
            accent: const Color(0xFF4C8DFF),
            isDark: false,
          ),
        ),
        ),
      ),
    ));
    await tester.pump();
  }

  /// 这一帧**画出来的本体**有多大（`Rect` 为空 = 一个像素都没画）。
  ///
  /// ⚠️ 两处讲究，都是被空话坑出来的：
  /// · **必须取像素、不能读轮廓数据**：轮廓是「该画成什么样」，而这里要问的是
  ///   「画家到底重画了没有」—— 指纹漏一个量时数据是对的、屏幕上是旧的（独立审查
  ///   抓到的那个 Important 就是这么漏过去的）。
  /// · **必须按不透明度门槛只取本体**：浮起阴影本来就跟着升程涨，而它在轮廓之外、
  ///   面积更大 —— 取「所有非透明像素」的包围盒，量到的是影子（第一版就是这么写的，
  ///   照出来永远是绿的）。本体那层填充的 alpha 是 0.85 → 0.50，而阴影最多 0.22，
  ///   中间空得很。
  Future<Rect> paintedBounds(WidgetTester tester,
      {int minAlpha = 100}) async {
    final RenderRepaintBoundary b =
        shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late Rect r;
    await tester.runAsync(() async {
      final ui.Image img = await b.toImage(pixelRatio: 1.0);
      final ByteData data =
          (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      img.dispose();
      final Uint8List px = data.buffer.asUint8List();
      int x0 = 1 << 30, y0 = 1 << 30, x1 = -1, y1 = -1;
      for (int y = 0; y < gridH.round(); y++) {
        for (int x = 0; x < gridW.round(); x++) {
          if (px[(y * gridW.round() + x) * 4 + 3] < minAlpha) continue;
          if (x < x0) x0 = x;
          if (y < y0) y0 = y;
          if (x > x1) x1 = x;
          if (y > y1) y1 = y;
        }
      }
      r = x1 < 0 ? Rect.zero : Rect.fromLTRB(x0.toDouble(), y0.toDouble(), x1.toDouble(), y1.toDouble());
    });
    return r;
  }

  RangeBandOutline outlineOf(WidgetTester tester) =>
      tester.widget<LiquidLens>(find.byType(LiquidLens)).outline
          as RangeBandOutline;

  Rect boundsOf(WidgetTester tester) =>
      outlineOf(tester).paintPath(Offset.zero).getBounds();

  testWidgets('长按那一刻整条**漫上来**：升程从 0 涨到 1，几何四面各鼓出去',
      (tester) async {
    await mount(tester, tipCell: 3);
    final double early = boundsOf(tester).height;
    await tester.pumpAndSettle();
    final double settled = boundsOf(tester).height;
    expect(early, lessThan(settled - 4),
        reason: '一挂上来就满 —— 没有「漫上来」那一下');
    expect(settled, closeTo(innerH + 2 * CalendarRangeBand.protrude, 0.2),
        reason: '按住时四面各鼓 protrude（与那枚单格块同一个数）');
  });

  testWidgets('按住那一下**画出来的**四面鼓出去（不是只有轮廓数据鼓）', (tester) async {
    // 独立审查抓到的那个 Important：`outlineStamp` 里原先没有 `inflate` ——
    // 几何数据变了、戒指（指纹）没变 → 画家判定「不用重画」→ **屏幕上什么都不动**，
    // 只有阴影那一层在涨（它的 painter 自己有 `lift` 字段）。旧那条用例读的是
    // `paintPath(...)` 的数据，所以照不出来。
    await mount(tester, tipCell: 3);
    final Rect early = await paintedBounds(tester); // 升程刚起步
    await tester.pumpAndSettle(); // 升程到 1
    final Rect settled = await paintedBounds(tester);
    expect(settled.width, greaterThan(early.width + 6),
        reason: '按住之后**画出来的**没有变宽 —— 指纹漏了升程那一维（只有轮廓数据鼓了）');
    expect(settled.height, greaterThan(early.height + 6),
        reason: '同上（纵向）');
  });

  testWidgets('末端沿运动方向鼓出去，但**高度不变**', (tester) async {
    // ⚠️ 鼓出没法从包围盒里抠出来：末端一边淌一边鼓，两件事叠在一起。所以判据读
    // `RangeBandOutline.bulge`（那一帧的几何指纹之一），它是同源数据、不是测试钩子。
    await mount(tester, tipCell: 3);
    await tester.pumpAndSettle();
    expect(outlineOf(tester).bulge, closeTo(0, 0.01), reason: '静止时不该有鼓出');
    final double restH = boundsOf(tester).height;

    for (int i = 1; i <= 4; i++) {
      await mount(tester, tipCell: 3 + i);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(outlineOf(tester).bulge, greaterThan(1),
        reason: '末端没有沿运动方向鼓出去（没接上 / 门太大）');
    expect(boundsOf(tester).height, closeTo(restH, 0.2),
        reason: '带子高度动了 —— 它是渠道里的水，一变形就会露出格子的上下沿（spec §4.5）');
  });

  testWidgets('彩边的亮峰跟着末端方向（往右 0°、往左 180°）', (tester) async {
    for (int i = 1; i <= 6; i++) {
      await mount(tester, tipCell: 2 + i);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(outlineOf(tester).motion, greaterThan(0.5),
        reason: '末端在动，彩边却没亮');
    expect(outlineOf(tester).motionAngleDeg, closeTo(0, 1),
        reason: '往右淌，亮峰没挪到正右');

    for (int i = 1; i <= 6; i++) {
      await mount(tester, tipCell: 6 - i);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(outlineOf(tester).motionAngleDeg, closeTo(180, 1),
        reason: '往左淌，亮峰没挪到正左');
  });

  testWidgets('末端是**淌**过去的：给它一个新目标，中途停在两点之间', (tester) async {
    await mount(tester, tipCell: 2);
    await tester.pumpAndSettle();
    await mount(tester, tipCell: 6);
    await tester.pump(const Duration(milliseconds: 16));
    final double early = outlineOf(tester).tipPos;
    expect(early, greaterThan(2.05), reason: '动都不动 —— 弹簧没接上');
    expect(early, lessThan(5.9), reason: '一帧就到位了 —— 那是瞬移，不是淌');
    await tester.pumpAndSettle();
    expect(outlineOf(tester).tipPos, closeTo(6, 0.02));
  });

  testWidgets('静止之后没有在跑的 ticker', (tester) async {
    await mount(tester, tipCell: 3);
    await tester.pumpAndSettle(); // 有常驻动画的话这里直接超时
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
