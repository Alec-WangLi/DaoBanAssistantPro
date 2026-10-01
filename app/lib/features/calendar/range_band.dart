// app/lib/features/calendar/range_band.dart
//
// 拖选那条水带的**几何**：纯函数，不依赖任何 widget。
//
// 为什么单独一个文件：这条带子的形状有四种角（两个真端头圆、跨行两头平）、
// 跨周 / 同周 / 单天 / 跨三行 / 月末残行五种情形 —— 全是纯几何，抽出来就能逐条断言，
// 不必每次去挂整张日历。widget 那一层（`calendar_range_band.dart`）只剩弹簧与材质。
//
// **「一条带子」这句话的几何含义**：同一行内那一段是**一个矩形**（从该行第一个选中格的
// 外缘铺到最后一个），于是格与格之间那 4px 的缝**被它盖住**。今天是逐格各画一块 14%
// 淡染，而缝不属于任何一格 —— 谁也盖不住它，那就是「一排小色块」的来源。
import 'dart:ui';

import '../../domain/shift_rotation.dart';

/// 拖选区间 → **每行一段**（行号 + 该行的起止列，闭区间）。
///
/// [from] / [to] 谁前谁后都认（内部归一成正序）。**调用点保证不跨月** —— 跨月的输入
/// 不在这一版的语义里（手势层就拦住了：`adjustDays` 那句「请分开调整」）。
///
/// 区间是连续的，所以**每行内部那几列也一定连续**：不需要处理跳格。
List<({int row, int firstCol, int lastCol})> rangeRowRuns({
  required DateTime from,
  required DateTime to,
  required DateTime month,
}) {
  // 与 `calendar_screen.dart` 的 `_leading` / `daysInMonth` 同一个算式 —— 两处必须同源，
  // 否则带子会整体错一格（集成用例那边钉着）。
  final int leading = DateTime(month.year, month.month, 1).weekday - 1;
  final bool forward = daysBetween(from, to) >= 0;
  final DateTime lo = forward ? from : to;
  final DateTime hi = forward ? to : from;

  final Map<int, List<int>> byRow = <int, List<int>>{};
  for (int day = lo.day; day <= hi.day; day++) {
    final int slot = leading + day - 1;
    byRow.putIfAbsent(slot ~/ 7, () => <int>[]).add(slot % 7);
  }
  final List<int> rows = byRow.keys.toList()..sort();
  return <({int row, int firstCol, int lastCol})>[
    for (final int r in rows)
      // 逐天推进，所以每行那几列是升序的：first / last 就是两端。
      (row: r, firstCol: byRow[r]!.first, lastCol: byRow[r]!.last),
  ];
}

/// 每行一段 → 一条带子（多段圆角矩形的并集）。
///
/// **四种角**（用户 2026-10-01 在 A/B/C 对照图上选的 A）：
/// · 区间**起点**那一侧的上下两角 = [endRadius]；
/// · 区间**终点**那一侧的上下两角 = [endRadius]；
/// · **跨行那两头**（上一段的末端 / 下一段的起端）= 0（切平）。
///
/// 于是同周内的区间是一枚两端都圆的带子，跨周的是「几段、只有最外两头圆」。
///
/// [tipCol] 是**会动的那一端**的连续位置，单位是「格」：整数 `k` = 正好吸在 k 那一格的
/// 外缘，`k + 0.5` = 那一端又淌出去半格（widget 那层把「鼓出」也换算进来加在这儿）。
/// `null` = 两端都按整格（静止帧）。哪一端会动由 [movingEnd] 说：
/// `true` = 终点（右）、`false` = 起点（左）。
Path rangeBandPath({
  required List<({int row, int firstCol, int lastCol})> runs,
  required double cellW,
  required double cellH,
  required double hPad,
  required double weekdayH,
  required double inset,
  required double endRadius,
  required bool movingEnd,
  double? tipCol,
}) {
  final Path path = Path();
  for (int i = 0; i < runs.length; i++) {
    final ({int row, int firstCol, int lastCol}) run = runs[i];
    final bool isFirst = i == 0;
    final bool isLast = i == runs.length - 1;

    double left = hPad + run.firstCol * cellW + inset;
    double right = hPad + (run.lastCol + 1) * cellW - inset;
    // 会动的那一端：**只改那一侧的位置**，角度的规矩不变（它仍是区间的真端头）。
    if (tipCol != null) {
      if (movingEnd && isLast) {
        right = hPad + (tipCol + 1) * cellW - inset;
      } else if (!movingEnd && isFirst) {
        left = hPad + tipCol * cellW + inset;
      }
    }

    path.addRRect(RRect.fromRectAndCorners(
      Rect.fromLTRB(left, weekdayH + run.row * cellH + inset, right,
          weekdayH + (run.row + 1) * cellH - inset),
      topLeft: Radius.circular(isFirst ? endRadius : 0),
      bottomLeft: Radius.circular(isFirst ? endRadius : 0),
      topRight: Radius.circular(isLast ? endRadius : 0),
      bottomRight: Radius.circular(isLast ? endRadius : 0),
    ));
  }
  return path;
}
