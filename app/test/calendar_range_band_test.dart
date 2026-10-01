// app/test/calendar_range_band_test.dart
//
// 那枚水带的**弹簧与观感**：漫上来、末端淌过去、沿运动方向鼓出、彩边跟着方向。
//
// ⚠️ 一律走几何与帧调度，**不拿光栅亮度当判据** —— 带子压在白色卡片上，亮度差被卡片
// 自己的底色吃掉（日历页那条「缝隙量不出来」的教训）。
import 'package:flutter/material.dart';
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

  /// 挂一条带子：`from..tipCell` 是同一行里那一段（吸附到格的状态）。
  Future<void> mount(WidgetTester tester,
      {required int tipCell, int from = 2}) async {
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
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
    ));
    await tester.pump();
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
