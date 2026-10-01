// 竖直那一档的轮廓护栏。
//
// 它原来是把「上圆 + 下圆 + 中矩形」**并**成一条路径：填色对，但描边会把三段边界
// 全画出来 —— 四层光谱全是描边，于是钮的内部出现横线与内侧弧（用户 2026-10-01：
// 「彩边穿到滑块里边了，而且还不规则，也不贴边」）。
//
// v0.10.10 的开关按住时宽 29.69 < 高 33.38，**真机上一直在踩**；底栏在窄窗下同样。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens_metrics.dart';

void main() {
  /// 开关那一档的尺寸：itemW 25 / capsuleH 30 / pad 3。
  LiquidLensShape vertical({
    double velocity = 0,
    double stretch = 0,
    double motion = 0,
    double rimScale = 0.46875,
  }) =>
      LiquidLensShape.of(
        itemW: 25,
        capsuleH: 30,
        pad: 3,
        centerPage: 0,
        lift: 1,
        velocity: velocity,
        stretch: stretch,
        motion: motion,
        // 开关这一版的四个数（protrude 9 / liftWidth −2）—— 这一档正是因为
        // 纵向拉长才落进竖直分支，用旧那套（4.69/4.69）在满拉伸时会跑回横向档。
        metrics: LiquidLensMetrics(
          protrude: 9,
          liftWidth: -2,
          rimScale: rimScale,
        ),
      );

  /// v0.10.10 开关那一套量（`forCapsule(30)`）：宽 29.69 < 高 33.38 也是竖直档，
  /// 但两条接缝落在中心上下 1.85px 处 —— 光栅化那条要用它才好取样。
  LiquidLensShape verticalOld({
    double motion = 0,
    double rimScale = 0.46875,
  }) =>
      LiquidLensShape.of(
        itemW: 25,
        capsuleH: 30,
        pad: 3,
        centerPage: 0,
        lift: 1,
        velocity: 0,
        motion: motion,
        metrics: LiquidLensMetrics(
          protrude: 30 * 0.15625,
          liftWidth: 30 * 0.15625,
          rimScale: rimScale,
        ),
      );

  test('竖直档是**一条**闭合子路径（并三个子路径会把描边画进钮里）', () {
    final s = vertical();
    expect(s.width, lessThan(s.height), reason: '这一档本该是竖直的，不然这条白测');
    expect(s.toPath().computeMetrics().length, 1,
        reason: '轮廓不止一条子路径 —— 描边会把它内部的接缝也画出来');
  });

  test('竖直档的**轮廓本身**读前缘/后缘：细的那一头真的更窄', () {
    // 只断言 `leftRadius != rightRadius` 是不够的 —— 那两个 getter 在改之前就是对的，
    // **是 `toPath()` 没用它们**。所以这里探路径本身：
    // 两半径不等时轮廓**不可能**是左右镜像的。
    //
    // ⚠️ 收尾必须是**纵向拉伸**而不是旋转 —— 旋转会把前后缘搬到上下两头，
    // 于是「头大尾轻」变成「上大下小」，而用户要的是左右（见 `_verticalStretched`）。
    final s = vertical(stretch: 1, velocity: AppTokens.lensVelocityRef);
    expect(s.width, lessThan(s.height), reason: '这一档本该是竖直的');
    expect(s.leftRadius, lessThan(s.rightRadius),
        reason: '向右拖 → 后缘在左、前缘在右');

    final Path p = s.toPath();
    // 中轴两侧**等高**的两个点：粗的那一头（前缘在右）在这个高度还是实的，
    // 细的那一头已经收进去了。改之前两端半径相等、轮廓左右镜像，两个都在里面。
    final double dx = s.width * 0.43;
    final double dy = s.height * 0.26;
    expect(p.contains(Offset(s.centerX + dx, s.centerY + dy)), isTrue,
        reason: '粗的那一头在这个高度该还是实的');
    expect(p.contains(Offset(s.centerX - dx, s.centerY + dy)), isFalse,
        reason: '轮廓左右镜像 —— 它没读前后缘（还是等半径那两个圆）');

    // 向左拖镜像过来。
    final LiquidLensShape mirror =
        vertical(stretch: 1, velocity: -AppTokens.lensVelocityRef);
    final Path mp = mirror.toPath();
    expect(mp.contains(Offset(mirror.centerX - dx, mirror.centerY + dy)), isTrue);
    expect(mp.contains(Offset(mirror.centerX + dx, mirror.centerY + dy)),
        isFalse);
  });

  test('竖直档：两半径相等时是一枚**左右对称的竖椭圆**', () {
    final s = vertical();
    expect(s.leftRadius, closeTo(s.rightRadius, 0.001));
    final Path p = s.toPath();
    final Rect b = p.getBounds();
    expect(b.width, closeTo(s.width, 0.5), reason: '包围盒宽不等于 width');
    expect(b.height, closeTo(s.height, 0.5), reason: '包围盒高不等于 height');
    for (final double dy in <double>[-12, -6, 0, 6, 12]) {
      final double y = s.centerY + dy;
      expect(p.contains(Offset(s.centerX - 8, y)),
          p.contains(Offset(s.centerX + 8, y)),
          reason: 'dy=$dy 处左右不对称 —— 两半径相等却不是镜像的');
    }
  });

  test('宽 == 高（正圆那一档）不塌：路径非空、面积 > 0、中心在里面', () {
    // 两个等半径圆、圆心距恰好等于 2r 时 d = 0，`mx = (rl − rr) / d` 就是 0/0。
    // itemW 24 / capsuleH 30 / pad 3 / lift 0 → 宽 24、高 24，正好相等。
    final s = LiquidLensShape.of(
        itemW: 24, capsuleH: 30, pad: 3, centerPage: 0, lift: 0, velocity: 0);
    expect(s.width, closeTo(s.height, 0.001), reason: '这一档本该是正圆，不然白测');
    final p = s.toPath();
    expect(p.getBounds().isEmpty, isFalse);
    expect(p.computeMetrics().length, 1);
    expect(p.contains(Offset(s.centerX, s.centerY)), isTrue);
  });

  testWidgets('光栅化：彩边**不往钮里加任何东西**（钮内部一个像素都不变）',
      (tester) async {
    // 并集那版会在两个圆心的高度各留下一条横线。判据用「彩边开 / 彩边关」两帧做差，
    // 不是直接量色度：钮的填充本身就是彩色的（0xFF5B5BD6），量色度会把填充也算进去、
    // 恒红。做差之后剩下的**只有跟着 `rimScale` 走的那些层**，而它们该全落在轮廓上。
    //
    // ⚠️ 两处取样上的讲究：
    //   · **用旧那套几何**（protrude/liftWidth 都是 `30 × 0.15625`）：宽 29.69 < 高 33.38
    //     时 `_cap = 14.84`、`gap = 1.85` —— 两条接缝就在中心上下 1.85px 处，
    //     一个 ±4 的小框就能把它们圈住。换成开关那套（23 × 42）接缝跑到 ±9.5，
    //     那个位置已经在**浮起阴影**的射程里（它也乘 `rimScale`），量出来是阴影。
    //   · 框只取 ±4：离上下轮廓 12.7px、离左右轮廓 10.8px，两层内晕（k=0.47 时
    //     往里伸约 4px）与阴影（模糊 4.69px）都够不到。
    final LiquidLensShape on = verticalOld(motion: 1);
    final LiquidLensShape off = verticalOld(motion: 1, rimScale: 0.001);
    final List<int> a = await _shot(tester, on);
    final List<int> b = await _shot(tester, off);

    const int w = 200;
    const double boxW = 48;
    const double boxH = 30;
    final int cx = ((w - boxW) / 2 + on.centerX).round();
    final int cy = ((120 - boxH) / 2 + on.centerY).round();
    int worst = 0;
    for (int y = cy - 4; y <= cy + 4; y++) {
      for (int x = cx - 4; x <= cx + 4; x++) {
        final int i = (y * w + x) * 4;
        for (int c = 0; c < 3; c++) {
          final int d = (a[i + c] - b[i + c]).abs();
          if (d > worst) worst = d;
        }
      }
    }
    expect(worst, lessThan(4),
        reason: '彩边在钮内部留下了 $worst 级差异 —— 描边把内部接缝画出来了');
  });
}

/// 在一张 200×120 的画布上把一枚 48×30 的透镜渲出来。
Future<List<int>> _shot(WidgetTester tester, LiquidLensShape shape) async {
  const int w = 200;
  const int h = 120;
  tester.view.physicalSize = Size(w.toDouble(), h.toDouble());
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        child: Center(
          child: SizedBox(
            width: 48,
            height: 30,
            child: LiquidLens(
              size: const Size(48, 30),
              outline: shape,
              lift: 1,
              isDark: true,
              accent: const Color(0xFF5B5BD6),
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
    final ByteData? d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    px = d!.buffer.asUint8List().toList();
  });
  return px;
}
