// 透镜的弹簧解算器。
//
// 为什么不用 `TweenAnimationBuilder`：透镜要的不是「从 A 到 B 的一段补间」，
// 而是两样补间给不了的东西 ——
//   · **速度**：拖动时形状要跟着速度拉伸（Q 弹），速度得从解算器里读；
//   · **过冲**：松手落回格子那一下要越过一点再回来，那才是「Q 弹」。
//
// 纯 Dart、没有 widget 依赖，所以可以直接跑 200 步去断言它的行为。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';

void main() {
  test('收敛：从中点出发最终停到目标上', () {
    final s = LiquidLensSpring(target: 100)..value = 0;
    for (int i = 0; i < 200; i++) {
      s.step(const Duration(milliseconds: 16));
    }
    expect(s.value, closeTo(100, 0.5));
    expect(s.isAtRest, isTrue);
  });

  test('过冲：落回时越过目标再回来（这就是 Q 弹的观感来源）', () {
    final s = LiquidLensSpring(target: 100)..value = 0;
    double peak = 0;
    for (int i = 0; i < 200; i++) {
      s.step(const Duration(milliseconds: 16));
      if (s.value > peak) peak = s.value;
    }
    expect(peak, greaterThan(101),
        reason: '没有过冲 —— 那和 easeOut 没有区别，松手那一下就不会有 Q 弹感');
    expect(peak, lessThan(140), reason: '过冲太大（>40%），读起来是「甩过头」');
  });

  test('不发散：目标半路被改写也不炸', () {
    final s = LiquidLensSpring(target: 100);
    for (int i = 0; i < 5; i++) {
      s.step(const Duration(milliseconds: 16));
    }
    s.target = -100; // 连点另一格
    for (int i = 0; i < 200; i++) {
      s.step(const Duration(milliseconds: 16));
    }
    expect(s.value, closeTo(-100, 0.5));
  });

  test('帧间隔封顶：喂一个 1 秒的 dt，位移不超过按 maxStep 算出来的那一步', () {
    final capped = LiquidLensSpring(target: 100)..step(LiquidLensSpring.maxStep);
    final huge = LiquidLensSpring(target: 100)..step(const Duration(seconds: 1));
    expect(huge.value, closeTo(capped.value, 1e-9),
        reason: '掉帧时按真实 dt 积分会让透镜瞬移，还会把数值积爆');
  });

  test('落回时间与标准档的 durFast 相当', () {
    // 这一条钉的是**用户 2026-10-01 反馈的第 6 条**：「滑块的吸附速度很僵硬，
    // 没有之前标准磨砂玻璃状态下那种缓慢优雅」—— 标准档滑过去用的就是
    // `durFast`。弹簧的落回时间必须与它相当，慢出一截就是那条反馈回头。
    //
    // 它同时也是那两个参数的**唯一**有效护栏：`design_tokens` 里那张表是按
    // 「与实现同一套离散格式」扫出来的，连续解的理论公式在这儿会把人带偏
    // （照理论填的 ω=46.3 / ζ=0.72 过冲实测是 0）。
    final s = LiquidLensSpring(target: 100)..value = 0;
    final int steps = AppTokens.durFast.inMilliseconds ~/ 16;
    for (int i = 0; i < steps; i++) {
      s.step(const Duration(milliseconds: 16));
    }
    expect((s.value - 100).abs() / 100, lessThan(0.05),
        reason: '过了 durFast（${AppTokens.durFast.inMilliseconds}ms）还差得远 —— '
            '吸附会比标准档慢一截');
  });

  group('透镜几何', () {
    const double itemW = 85, capsuleH = 64, pad = 6;

    LiquidLensShape at({double lift = 0, double velocity = 0, double page = 0}) =>
        LiquidLensShape.of(
            itemW: itemW,
            capsuleH: capsuleH,
            pad: pad,
            centerPage: page,
            lift: lift,
            velocity: velocity);

    test('静止：是一枚胶囊（两端半径相等、且等于高的一半）', () {
      final s = at();
      expect(s.width, closeTo(itemW, 0.01));
      expect(s.height, closeTo(capsuleH - 2 * pad, 0.01));
      expect(s.leftRadius, closeTo(s.rightRadius, 0.001));
      expect(s.leftRadius, closeTo(s.height / 2, 0.001));
    });

    test('按住：高度 = 基准 + 2 × navLensProtrude（凸出胶囊）', () {
      final s = at(lift: 1);
      expect(s.height,
          closeTo(capsuleH - 2 * pad + 2 * AppTokens.navLensProtrude, 0.01));
      expect(s.height, greaterThan(capsuleH), reason: '按住时要高于胶囊才叫凸出');
    });

    test('拖动：沿运动方向拉伸、垂直方向压缩（面积近似守恒）', () {
      final s = at(lift: 1, velocity: AppTokens.lensVelocityRef);
      expect(s.width, greaterThan(itemW));
      expect(s.height,
          lessThan(capsuleH - 2 * pad + 2 * AppTokens.navLensProtrude));
    });

    test('拖动：前缘比后缘圆（向右拖时右端半径更大），向左拖镜像', () {
      final right = at(lift: 1, velocity: AppTokens.lensVelocityRef);
      expect(right.rightRadius, greaterThan(right.leftRadius));

      final left = at(lift: 1, velocity: -AppTokens.lensVelocityRef);
      expect(left.leftRadius, greaterThan(left.rightRadius));
    });

    test('窄窗：两端圆不许重叠（外公切线必须存在），且形状仍闭合', () {
      // 工装的小窗是 200×400：可用宽 = 200 − 2×16 = 168，扣掉 pad ×2 后
      // trackW = 156，n = 4 → itemW = 39；而按住时透镜高 60 —— **宽比高还小**。
      // 水平胶囊在「宽 < 高」时数学上不成立（两个端头圆会重叠、外公切线不存在），
      // 这不是假想的，是算出来的。
      final s = LiquidLensShape.of(
          itemW: 39,
          capsuleH: 64,
          pad: 6,
          centerPage: 1,
          lift: 1,
          velocity: 0);
      expect(s.leftRadius + s.rightRadius, lessThanOrEqualTo(s.width + 0.001),
          reason: '两个端头圆重叠了 —— 外公切线不存在，Path 会画出乱形');
      expect(s.toPath().getBounds().isEmpty, isFalse);
    });

    test('轮廓落在该落的框里：竖直居中于胶囊中轴，宽度就是 width', () {
      // 这条钉住 `toPath()` 的坐标约定 —— 按住时 height > capsuleH，
      // 若按自己的 height/2 居中，凸出会全部跑到下面去。
      final s = at(lift: 1);
      final bounds = s.toPath().getBounds();
      expect(bounds.center.dy, closeTo(capsuleH / 2, 0.01), reason: '没竖直居中');
      expect(bounds.center.dx, closeTo(s.centerX, 0.01));
      expect(bounds.width, closeTo(s.width, 0.5));
      expect(bounds.height, closeTo(s.height, 0.5));
    });

    test('外壳连成一片：两枚端头圆之间的空隙被切线填上了', () {
      // 反面是「两个端头圆各画一个圈、中间没接上」—— 包围盒照样对，但中间是空的。
      //
      // **探针必须落在两圆之间的空隙里**，不能取形状正中央：拉伸时前缘圆变大，
      // 正中央其实落在**前缘圆内部**，两个圈分开画也照样判真（第一版就是这么
      // 写错的，靠下面第一条断言才看得出来）。
      //
      // 空隙的中点（在水平中轴上）：`c1.dx + rl` 与 `c2.dx − rr` 的均值，
      // 展开后 = `centerX + leftRadius − rightRadius`。
      final s = at(lift: 1, velocity: AppTokens.lensVelocityRef);
      expect(s.rightRadius, greaterThan(s.leftRadius),
          reason: '这一档本该是「前缘大、后缘小」（向右拖 → 右端是前缘），'
              '不然空隙不存在、这条白测');

      final double probeX = s.centerX + s.leftRadius - s.rightRadius;
      final double distanceToLeftCap =
          (probeX - (s.centerX - s.width / 2 + s.leftRadius)).abs();
      final double distanceToRightCap =
          (probeX - (s.centerX + s.width / 2 - s.rightRadius)).abs();
      expect(distanceToLeftCap, greaterThan(s.leftRadius),
          reason: '探针落进了左端圆里 —— 那样 `contains` 为真什么都说明不了');
      expect(distanceToRightCap, greaterThan(s.rightRadius),
          reason: '探针落进了右端圆里 —— 同上');

      final p = s.toPath();
      expect(p.contains(Offset(probeX, s.centerY)), isTrue,
          reason: '两圆之间的空隙是空的 —— 外公切线没把它们连起来');
      expect(p.contains(Offset(s.centerX, s.centerY - s.height / 2 - 2)), isFalse,
          reason: '形状外面那个点被判成在里面 —— 外壳封错了');
    });
  });

  // ── 渲染（光栅化，不是「有没有画东西」）─────────────────────────────────

  const Size canvas = Size(200, 120);
  const Size capsule = Size(120, 64);

  /// 把「一枚透镜盖在一块胶囊底上」光栅化成原始 RGBA。
  ///
  /// [lineAtX] >= 0 时在胶囊底上画一条 2px 黑竖线（放大层的用例要用）。
  Future<List<int>> shotLens(
    WidgetTester tester, {
    required double lift,
    required Color accent,
    double velocity = 0,
    double magnifyScale = 1.0,
    int lineAtX = -1,
  }) async {
    tester.view.physicalSize = canvas;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GlobalKey key = GlobalKey();
    final shape = LiquidLensShape.of(
        itemW: capsule.width,
        capsuleH: capsule.height,
        pad: 0,
        centerPage: 0,
        lift: lift,
        velocity: velocity);
    final double top = (canvas.height - capsule.height) / 2;
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: canvas,
            child: Stack(clipBehavior: Clip.none, children: <Widget>[
              Positioned(
                left: 0,
                top: top,
                width: capsule.width,
                height: capsule.height,
                child: ColoredBox(
                  color: const Color(0xFFF5F6FA),
                  child: lineAtX < 0
                      ? null
                      : CustomPaint(painter: LinePainter(lineAtX)),
                ),
              ),
              Positioned(
                left: 0,
                top: top,
                width: capsule.width,
                height: capsule.height,
                child: LiquidLens(
                  size: capsule,
                  shape: shape,
                  lift: lift,
                  isDark: false,
                  accent: accent,
                  magnifyScale: magnifyScale,
                ),
              ),
            ]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late List<int> bytes;
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List()
          .toList();
      image.dispose();
    });
    return bytes;
  }

  int alphaAt(List<int> px, int x, int y) => px[(y * canvas.width.toInt() + x) * 4 + 3];

  testWidgets('按住时透镜凸出胶囊：外框之外上下各有非透明像素', (tester) async {
    final px = await shotLens(tester,
        lift: 1, accent: const Color(0xFF12B5A5));
    final int top = ((canvas.height - capsule.height) / 2).round();
    expect(alphaAt(px, 60, top - 2), greaterThan(0), reason: '没凸出胶囊上沿');
    expect(alphaAt(px, 60, top - 2), lessThan(255), reason: '凸出来的应该还是玻璃，不是实心块');
    expect(alphaAt(px, 60, top + capsule.height.toInt() + 1), greaterThan(0),
        reason: '没凸出胶囊下沿');
  });

  testWidgets('静止时不凸出：胶囊外框之外全是透明的', (tester) async {
    // 与上一条是一对 —— 缺了它，上一条可能因为别的原因（比如阴影）变绿。
    final px = await shotLens(tester,
        lift: 0, accent: const Color(0xFF12B5A5));
    final int top = ((canvas.height - capsule.height) / 2).round();
    expect(alphaAt(px, 60, top - 2), 0);
    expect(alphaAt(px, 60, top + capsule.height.toInt() + 1), 0);
  });
}

/// 胶囊底上一条 2px 黑竖线（放大层的用例要用）。白底 —— 放大时才看得出位移。
class LinePainter extends CustomPainter {
  const LinePainter(this.x);
  final int x;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, size.height),
        Paint()..color = const Color(0xFF000000));
  }

  @override
  bool shouldRepaint(LinePainter old) => old.x != x;
}
