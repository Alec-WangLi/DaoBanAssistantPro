// app/test/range_band_test.dart
//
// 拖选那条水带的**几何**：区间 → 每行一段，每段一个圆角矩形。
//
// 这一轮的核心断言是「**同一行内是一整块**」（两格之间那道 4px 的缝也说「在里面」）——
// 格与格之间的缝不属于任何一格，所以逐格各画一块的写法在那条上必红，而那正是今天的样子。
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/features/calendar/range_band.dart';

void main() {
  // 400dp 宽屏上的日历几何（与 `calendar_screen.dart` 同源）。
  const double cellW = 56.5714;
  const double cellH = 85;
  const double hPad = 12;
  const double weekdayH = 26;
  const double inset = 2;
  const double endR = 16;
  final DateTime month = DateTime(2026, 10); // 2026-10-01 是周四 → 第 0 行第 3 列

  List<({int row, int firstCol, int lastCol})> runs(DateTime a, DateTime b) =>
      rangeRowRuns(from: a, to: b, month: month);

  /// 某一段该占的矩形（这是**规格**，不是从实现里抄的）。
  Rect rect(int row, int firstCol, int lastCol) => Rect.fromLTRB(
        hPad + firstCol * cellW + inset,
        weekdayH + row * cellH + inset,
        hPad + (lastCol + 1) * cellW - inset,
        weekdayH + (row + 1) * cellH - inset,
      );

  Path band(List<({int row, int firstCol, int lastCol})> r,
          {bool movingEnd = true, double? tipCol}) =>
      rangeBandPath(
          runs: r,
          cellW: cellW,
          cellH: cellH,
          hPad: hPad,
          weekdayH: weekdayH,
          inset: inset,
          endRadius: endR,
          movingEnd: movingEnd,
          tipCol: tipCol);

  // ── 区间 → 每行一段 ──────────────────────────────────────────────────
  test('跨周：按行拆成两段，各行的起止列都对', () {
    expect(runs(DateTime(2026, 10, 2), DateTime(2026, 10, 9)),
        <({int row, int firstCol, int lastCol})>[
          (row: 0, firstCol: 4, lastCol: 6),
          (row: 1, firstCol: 0, lastCol: 4),
        ]);
  });

  test('同周内：一段', () {
    expect(runs(DateTime(2026, 10, 2), DateTime(2026, 10, 4)),
        <({int row, int firstCol, int lastCol})>[(row: 0, firstCol: 4, lastCol: 6)]);
  });

  test('单天：一段一格', () {
    expect(runs(DateTime(2026, 10, 2), DateTime(2026, 10, 2)),
        <({int row, int firstCol, int lastCol})>[(row: 0, firstCol: 4, lastCol: 4)]);
  });

  test('跨三行：中间那行是**整行满**（周一到周日七个格子都在里面）', () {
    expect(runs(DateTime(2026, 10, 2), DateTime(2026, 10, 20)),
        <({int row, int firstCol, int lastCol})>[
          (row: 0, firstCol: 4, lastCol: 6),
          (row: 1, firstCol: 0, lastCol: 6),
          (row: 2, firstCol: 0, lastCol: 6),
          (row: 3, firstCol: 0, lastCol: 1),
        ]);
  });

  test('月末那一行是残行（10/26–10/31 只占 6 列）也照拆', () {
    expect(runs(DateTime(2026, 10, 27), DateTime(2026, 10, 30)),
        <({int row, int firstCol, int lastCol})>[(row: 4, firstCol: 1, lastCol: 4)]);
  });

  test('起点终点倒过来也认（内部归一成正序）', () {
    expect(runs(DateTime(2026, 10, 9), DateTime(2026, 10, 2)),
        runs(DateTime(2026, 10, 2), DateTime(2026, 10, 9)));
  });

  // ── 每段那个矩形 ────────────────────────────────────────────────────
  test('同一行内是一整块：两格之间那道**缝**也说「在里面」', () {
    // 这是这一轮的核心断言。今天那排逐格 14% 淡染在这一条上必红：
    // 缝（4px）不属于任何一格，谁也盖不住它。
    final Path p = band(runs(DateTime(2026, 10, 2), DateTime(2026, 10, 5)));
    final Rect r = rect(0, 4, 6);
    const double gap1 = hPad + 5 * cellW; // 第 4 格与第 5 格之间那条缝的中心
    const double gap2 = hPad + 6 * cellW; // 第 5 格与第 6 格之间
    for (final double x in <double>[gap1, gap2]) {
      expect(p.contains(Offset(x, r.center.dy)), isTrue,
          reason: 'x=$x 那道缝还是空的 —— 那还是「一排小色块」，不是一条带子');
    }
    // 而带子之外（左边那一格、右边那一格）不许被算进去。
    expect(p.contains(Offset(hPad + 3 * cellW + inset * 2, r.center.dy)), isFalse);
    expect(p.contains(Offset(hPad + 7 * cellW, r.center.dy)), isFalse);
  });

  test('四种角：两个真端头圆、跨行两头平', () {
    final r = runs(DateTime(2026, 10, 2), DateTime(2026, 10, 9));
    final Path p = band(r);
    final Rect r0 = rect(0, 4, 6); // 区间起点在这一段的左边
    final Rect r1 = rect(1, 0, 4); // 区间终点在这一段的右边

    // 真起点（左缘）：角被圆掉了 —— 贴着角的那点在轮廓外、左缘中点在里。
    expect(p.contains(Offset(r0.left + 1, r0.top + 1)), isFalse,
        reason: '起点的左上角没被圆掉');
    expect(p.contains(Offset(r0.left + 0.5, r0.center.dy)), isTrue,
        reason: '起点左缘中点都不在里面 —— 那一段的位置算错了');

    // 跨行那两头（第 0 行右缘 / 第 1 行左缘）：**切平** —— 贴着角那点也在里面。
    expect(p.contains(Offset(r0.right - 0.5, r0.top + 0.5)), isTrue,
        reason: '第 0 行右缘的角被圆掉了 —— 跨行处该是平的');
    expect(p.contains(Offset(r1.left + 0.5, r1.top + 0.5)), isTrue,
        reason: '第 1 行左缘的角被圆掉了 —— 跨行处该是平的');

    // 真终点（第 1 行右缘）：圆。
    expect(p.contains(Offset(r1.right - 0.5, r1.top + 0.5)), isFalse,
        reason: '终点的右上角没被圆掉');
    expect(p.contains(Offset(r1.right - 0.5, r1.center.dy)), isTrue);
  });

  test('同周内：两端都圆', () {
    final Path p = band(runs(DateTime(2026, 10, 2), DateTime(2026, 10, 4)));
    final Rect r = rect(0, 4, 6);
    expect(p.contains(Offset(r.left + 1, r.top + 1)), isFalse);
    expect(p.contains(Offset(r.right - 1, r.top + 1)), isFalse);
  });

  // ── 会动的那一端是**连续**的 ────────────────────────────────────────
  //
  // ⚠️ 这两条一律用**同周区间**：跨周时另一端那一段会伸到网格的左右边缘，
  // `Path.getBounds()` 量到的是那一段 —— 末端那一侧根本量不出来（第一版就是这么错的）。
  test('末端淌出去：给一个小数 tipCol，那一端的外缘就跟着走', () {
    final r = runs(DateTime(2026, 10, 2), DateTime(2026, 10, 4)); // 单段 (0,4,6)
    final Path snapped = band(r, tipCol: 6);
    final Path flowed = band(r, tipCol: 6.6);
    expect(snapped.getBounds().right, closeTo(rect(0, 4, 6).right, 0.01),
        reason: '整数 tipCol 就该正好吸在那一格的外缘');
    expect(flowed.getBounds().right,
        closeTo(snapped.getBounds().right + cellW * 0.6, 0.01));
    // 另一端（起点）不动。
    expect(flowed.getBounds().left, closeTo(snapped.getBounds().left, 0.01));
  });

  test('往回拖：会动的那一头换成起端（左缘跟 tipCol 走）', () {
    final r = runs(DateTime(2026, 10, 2), DateTime(2026, 10, 4));
    final Path p = band(r, movingEnd: false, tipCol: 4.5);
    expect(p.getBounds().left, closeTo(hPad + 4.5 * cellW + inset, 0.01));
    // 另一头（终点）不动。
    expect(p.getBounds().right, closeTo(rect(0, 4, 6).right, 0.01));
  });

  test('按住那一圈：inflate 把每一段四面各推出去，**端头半径不跟着放大**', () {
    final r = runs(DateTime(2026, 10, 2), DateTime(2026, 10, 4));
    final Path flat = rangeBandPath(
        runs: r,
        cellW: cellW,
        cellH: cellH,
        hPad: hPad,
        weekdayH: weekdayH,
        inset: inset,
        endRadius: endR,
        movingEnd: true);
    final Path lifted = rangeBandPath(
        runs: r,
        cellW: cellW,
        cellH: cellH,
        hPad: hPad,
        weekdayH: weekdayH,
        inset: inset,
        endRadius: endR,
        movingEnd: true,
        inflate: 6);
    expect(lifted.getBounds().width, closeTo(flat.getBounds().width + 12, 0.01));
    expect(lifted.getBounds().height, closeTo(flat.getBounds().height + 12, 0.01));
    // 端头半径仍是 endR：角上那点仍在轮廓外（放大半径的话它会被吞进去）。
    final Rect b = flat.getBounds();
    expect(lifted.contains(Offset(b.left - 5, b.top - 5)), isFalse,
        reason: '端头半径跟着放大了 —— 长出来的该是体积，不是圆角');
  });

  test('两段之间不会漏出天窗（跨行处上下两段严丝合缝）', () {
    // 第 0 行的下缘与第 1 行的上缘之间只隔一条 4px 的缝 —— 那一条本来就该是空的
    // （两段是各自成段的），但不许比 4px 更宽：验两段的边界值。
    final r = runs(DateTime(2026, 10, 2), DateTime(2026, 10, 9));
    final Path p = band(r);
    expect(rect(0, 4, 6).bottom, closeTo(weekdayH + cellH - inset, 0.01));
    expect(rect(1, 0, 4).top, closeTo(weekdayH + cellH + inset, 0.01));
    expect(
        p.contains(const Offset(hPad + 5 * cellW, weekdayH + cellH)), isFalse,
        reason: '跨行那条缝被盖住了 —— 两段该各自成段（用户选的 A）');
  });
}
