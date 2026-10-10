// app/test/lens_warp_scope_test.dart
//
// 日历那 42 格的「内容被透镜挤」这一层。与 `lens_warped_cell_test.dart` 管的
// 不是一回事：那一份是底栏/分段器用的**一维**共享件，这一份是日历的**二维**版
// （`lensIconWarp2d`）。
//
// 三条算式 + 两条组件行为。最要紧的是最后一条：**换一个中心只重算矩阵，
// 格子内容一次都不重建** —— 那正是这一轮（每帧重建 436 → 几十）的全部依据。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/frame_notifier.dart';
import 'package:shiftassistantpro/features/calendar/lens_warp_scope.dart';

/// 一个 56×72 的格子、内缩 5 —— 半宽 `(56-10)/2 = 23`、半高 `(72-10)/2 = 31`。
/// 透镜的权重是 `exp(-((t-1)/0.45)²)`（`AppTokens.lensIconRingSigma`），
/// `w < 0.01` 就不套那一层 —— 下面几条用例的取点都据此来。
const double _cellW = 56;
const double _cellH = 72;
const double _inset = 5;
const Offset _center = Offset(100, 100);

class _Counter extends StatelessWidget {
  const _Counter(this.onBuild);
  final void Function() onBuild;
  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox(width: 10, height: 10);
  }
}

void main() {
  // ── 算式 ────────────────────────────────────────────────────────────────
  test('透镜正压在格心（t = 0）→ null：静止时那枚块底下的格子不带形变', () {
    expect(
        cellWarpFor(
            cellCenter: _center,
            lensCenter: _center,
            cellW: _cellW,
            cellH: _cellH,
            inset: _inset),
        isNull,
        reason: '静止时权重见底（t = 0 时 w ≈ 0.007 < 0.01）—— 这正是「静止画面'
            '逐像素不变」那条的地基，别把它改成恒等 Transform 套上去');
  });

  test('透镜远在天边 → null（一层 Transform 都不套）', () {
    expect(
        cellWarpFor(
            cellCenter: _center,
            lensCenter: const Offset(4200, 4200),
            cellW: _cellW,
            cellH: _cellH,
            inset: _inset),
        isNull);
  });

  test('透镜边界正好扫过格子的右缘（t = 1）→ 径向压窄、切向拉长、朝外推', () {
    // 半宽 23 ⇒ 透镜中心落在格心右边 23 处时，t 恰好是 1、权重满。
    final Matrix4? m = cellWarpFor(
        cellCenter: _center,
        lensCenter: const Offset(123, 100),
        cellW: _cellW,
        cellH: _cellH,
        inset: _inset);
    expect(m, isNotNull);
    expect(m!.entry(0, 0), lessThan(1.0), reason: '沿径向没压窄');
    expect(m.entry(1, 1), greaterThan(1.0), reason: '切向没拉长');
    expect(m.entry(0, 3), lessThan(0),
        reason: '没朝远离透镜的方向推（透镜在右，内容该往左躲）');
  });

  // ── 组件 ────────────────────────────────────────────────────────────────
  testWidgets('LensWarpScope：中心为 null → 原样返回 child（树上没有 Transform）',
      (tester) async {
    final FrameNotifier<Offset?> n = FrameNotifier<Offset?>(null);
    addTearDown(n.dispose);
    await tester.pumpWidget(MaterialApp(
        home: LensWarpScope(
            center: n,
            cellCenter: _center,
            cellW: _cellW,
            cellH: _cellH,
            inset: _inset,
            child: const Text('内容'))));

    expect(find.byType(Transform), findsNothing);
  });

  testWidgets('中心变了：只重算矩阵，**第二帧起内容一次都不重建**', (tester) async {
    final FrameNotifier<Offset?> n = FrameNotifier<Offset?>(null);
    addTearDown(n.dispose);
    var contentBuilds = 0;
    await tester.pumpWidget(MaterialApp(
        home: LensWarpScope(
            center: n,
            cellCenter: _center,
            cellW: _cellW,
            cellH: _cellH,
            inset: _inset,
            child: _Counter(() => contentBuilds++))));
    expect(contentBuilds, 1, reason: '前提：内容建过一次');

    // 透镜扫过来：这一格从「不套」变成「套」，那个位置上的 widget 类型换了
    // （`Transform` 取代了内容本身），所以内容会被**重挂一次** —— 这一下免不了，
    // 也只会发生一次（透镜进出这一格各一次）。要钉的是**之后每一帧**。
    n.publish(const Offset(123, 100));
    await tester.pump();
    expect(find.byType(Transform), findsWidgets, reason: '这一格该被挤了');
    final int baseline = contentBuilds;

    // 之后每帧只换矩阵
    for (final double x in <double>[125, 120, 118, 121]) {
      n.publish(Offset(x, 100));
      await tester.pump();
    }

    expect(find.byType(Transform), findsWidgets);
    expect(contentBuilds, baseline,
        reason: '透镜扫过时每帧都在重建格子内容 —— 那正是这一轮要消掉的东西'
            '（改前实测整页一帧重建 436 个 widget）');
  });

  testWidgets('帧内静默写：不通知，但下一次 build 读到的就是新值', (tester) async {
    // `LayoutBuilder` 里写只能走 `publishSilently`（不然当场抛 setState during
    // build），而那一刻画面照样要对 —— 靠的正是 VLB 自己在 build 时读 `.value`。
    final FrameNotifier<Offset?> n = FrameNotifier<Offset?>(null);
    addTearDown(n.dispose);
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(builder: (BuildContext context, StateSetter setSt) {
      rebuild = setSt;
      return LensWarpScope(
          center: n,
          cellCenter: _center,
          cellW: _cellW,
          cellH: _cellH,
          inset: _inset,
          child: const Text('内容'));
    })));
    expect(find.byType(Transform), findsNothing);

    n.publishSilently(const Offset(123, 100));
    expect(find.byType(Transform), findsNothing,
        reason: '静默写**不该**触发重建（此刻树上还是老样子）');

    // 下一次由别的原因重建时，读到的必须是新值
    rebuild(() {});
    await tester.pump();
    expect(find.byType(Transform), findsWidgets,
        reason: '重建之后读到的必须是静默写进去的那个值 —— 布局阶段那一处'
            '就是靠这条成立的');
  });
}
