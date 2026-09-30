import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 液态档的透镜：弹簧解算器（本文件）→ 水滴几何 → 渲染。
///
/// 这一层是**参数化**的：给它一帧的状态，它算出那一帧的形状；它**不读**
/// `liquidGlassActive` —— 档位判据只在 `features/home/` 里读（由
/// `test/liquid_scope_guard_test.dart` 守着）。这样它既能被单测直接驱动，
/// 也不会在没人留意的时候自己长到别的玻璃面上。

/// 一维阻尼谐振子。
///
/// 为什么不用 `TweenAnimationBuilder`：透镜要的不是「从 A 到 B 的一段补间」，
/// 而是两样补间给不了的东西 ——
///   · **速度**：拖动时形状要跟着速度拉伸（Q 弹），速度得从解算器里读；
///   · **过冲**：松手落回格子那一下要越过一点再回来，那才是「Q 弹」。
class LiquidLensSpring {
  LiquidLensSpring({
    required this.target,
    this.value = 0,
    this.velocity = 0,
  });

  /// 当前位置与速度。都是公开可写的 —— 拖动时调用点会**直接**按住它们跟手走
  /// （那时不该再让弹簧插一脚），松手再交回给 [step]。
  double value;
  double velocity;
  double target;

  /// 一步积分允许的最大时间跨度。
  ///
  /// **掉帧时必须封顶**。两个理由，第二个才是硬的：① 按真实 dt 积分会让透镜在
  /// 卡顿的那一帧里「瞬移」过去；② 半隐式欧拉在 `dt > 2 / ω` 时就开始失稳，
  /// 而 `ω = 38` 那个门槛只有 **53ms** —— 现实里随便卡一下就跨过去了。
  /// 封顶的代价只是掉帧期间动画走得慢一点，那正是我们想要的。
  ///
  /// 值住在 `AppTokens` 里，因为**令牌守门不许 `lib/core/glass/` 出现
  /// `Duration(milliseconds: …)` 字面量**（`design_tokens_test`）。它不是过渡时长，
  /// 是积分步长的上限 —— 但守门扫的是写法，不是语义，所以照样得进令牌表。
  static const Duration maxStep = AppTokens.lensMaxStep;

  /// 静止判据：位移与速度都足够小。调用点据此决定还要不要再推帧
  /// （不推帧 = 这个控件一帧都不多画）。
  bool get isAtRest => (value - target).abs() < 0.01 && velocity.abs() < 1;

  /// 推进一步。半隐式欧拉：**先更新速度、再用新速度更新位置**。
  ///
  /// 不用显式欧拉（`value += velocity * dt` 之后再更新速度）：那个写法在
  /// 欠阻尼下会往系统里注入能量，几步就把弹簧积发散 —— 而发散的观感是
  /// 「透镜飞出去」，不是「有点抖」。
  void step(Duration dt) {
    final double capped =
        (dt.inMicroseconds < maxStep.inMicroseconds ? dt.inMicroseconds
            : maxStep.inMicroseconds) /
            1e6;
    const double omega = AppTokens.lensOmega;
    const double damping = 2 * AppTokens.lensZeta * omega;
    final double a =
        -omega * omega * (value - target) - damping * velocity;
    velocity += a * capped;
    value += velocity * capped;
  }
}

/// 透镜在**胶囊局部坐标**里的一帧几何。纯数据 + 纯函数，不依赖任何 widget。
///
/// 坐标原点 = 胶囊的左上角；`y = capsuleH / 2` 是竖直中轴。
///
/// **必须记住 [capsuleH]**：按住时透镜比胶囊高，`toPath()` 要竖直居中在那条中轴上
/// —— 按自己的 `height / 2` 居中的话，凸出会全部跑到下面去（上面一点不露）。
class LiquidLensShape {
  LiquidLensShape._({
    required this.centerX,
    required this.width,
    required this.height,
    required this.capsuleH,
    required this.stretch,
    required this.movingRight,
  });

  /// 从手势状态算出这一帧的形状。
  ///
  /// [centerPage] 以「格」为单位、可为小数（跟手时是连续值）；[lift] 是升程
  /// 0..1；[velocity] 是 px/s，**带符号**（正 = 向右）。
  factory LiquidLensShape.of({
    required double itemW,
    required double capsuleH,
    required double pad,
    required double centerPage,
    required double lift,
    required double velocity,
  }) {
    // 速度归一化到 0..1：拉伸与压缩都用它，所以「甩多快」只有一个量。
    final double s =
        (velocity.abs() / AppTokens.lensVelocityRef).clamp(0.0, 1.0);
    return LiquidLensShape._(
      centerX: pad + (centerPage + 0.5) * itemW,
      // 外扩取**横向与纵向同量级**（见 lensLiftWidth 的说明）；
      // 再叠速度带来的拉伸与压缩 —— 沿运动方向拉长、垂直方向压扁，
      // 近似面积守恒，读起来才像液体而不是橡皮。
      width: (itemW + AppTokens.lensLiftWidth * lift) * (1 + 0.20 * s),
      height: (capsuleH - 2 * pad + 2 * AppTokens.navLensProtrude * lift) *
          (1 - 0.12 * s),
      capsuleH: capsuleH,
      stretch: s,
      movingRight: velocity > 0,
    );
  }

  /// 透镜中心相对胶囊左缘的 x（含 [pad]）。
  final double centerX;

  /// 透镜的标称宽 / 高。**宽高是标称值**，实际轮廓的高度可能小于 [height]
  /// （见 [_cap] 的说明）。
  final double width;
  final double height;

  /// 它所依附的胶囊的高度。`toPath()` 竖直居中于它的中轴。
  final double capsuleH;

  /// 归一化速度 0..1，决定端头的不对称程度。
  final double stretch;

  /// 这一帧是否在向右移动（决定哪一端是「前缘」）。静止时为 false，
  /// 但那时两端半径相等，所以取哪一边都一样。
  final bool movingRight;

  /// 竖直中轴。透镜与胶囊**共用**这一条。
  double get centerY => capsuleH / 2;

  /// 端头圆的半径上限。
  ///
  /// 取 `min(高, 宽) / 2` 而不是 `高 / 2`，是**窄窗下的兜底**：透镜的宽是
  /// `itemW + 10·lift`，而小窗（200×400）里 `itemW` 只有 39 —— 按住时它反而
  /// 比高（60）还矮。水平胶囊在「宽 < 高」时**数学上不成立**（两个端头圆会
  /// 重叠，外公切线不存在），那时退回一枚圆团：形状仍然合法、仍然跟手、
  /// 仍然有弹簧，只是**凸出胶囊那件事在那样的宽度下做不到**。
  ///
  /// 顺带一个好处：`leftRadius + rightRadius <= min(高, 宽) <= 宽` **恒成立**，
  /// 因此不需要另外再做一次钳制，也不存在「圆重叠」这个失败态。
  double get _cap => math.min(height, width) / 2;

  /// 前缘半径（运动方向上那一端）与后缘半径。
  ///
  /// 只有**后缘**变小，前缘保持满半径。计划里写的是「前缘 1.25×、后缘 0.85×」——
  /// 那样两端半径都会超过 `height / 2`，于是形状的实际高度大于 `height`，
  /// 「按住时高 = 基准 + 2×凸出」这条契约就守不住了。改成只收后缘，形状高度
  /// 恒等于 `2 × _cap`，不变量成立且不对称为 35%（观感与计划里那 40% 同量级）。
  double get _leading => _cap;
  double get _trailing => _cap * (1 - 0.35 * stretch);

  double get leftRadius => movingRight ? _trailing : _leading;
  double get rightRadius => movingRight ? _leading : _trailing;

  /// 轮廓：两端是**圆心同在水平中轴、半径可以不同**的圆，中间用两段**外公切线**
  /// 连起来。半径相等时退化成标准胶囊。
  ///
  /// 用闭式解而不是贝塞尔近似，是为了让「半径相等 ⇒ 就是胶囊」这条性质**精确**
  /// 成立 —— 单测据此直接断言，而近似写法只能断言「差不多」。
  Path toPath() {
    final double rl = leftRadius;
    final double rr = rightRadius;
    final double cy = centerY;
    final Offset c1 = Offset(centerX - width / 2 + rl, cy);
    final Offset c2 = Offset(centerX + width / 2 - rr, cy);
    final double d = c2.dx - c1.dx;

    // 外公切线：两端半径到切点的那条单位向量 m 满足 `(c2 − c1) · m = rl − rr`，
    // 于是 `m.x = (rl − rr) / d`、`m.y = ±√(1 − m.x²)`。
    //
    // `d` 可能为 0 —— 窄窗下 `width == min(高,宽)`，两端半径已经撑满整个宽度，
    // 两圆同心且 rl == rr，形状就是一个**正圆**。这一档单开一条 `addOval`：
    // 走通用分支的话，左端那段圆弧的扫描角正好是 **2π**，而 **`Path.arcTo` 在
    // 扫描角为 ±2π 时什么都不画**（实测：整个路径是空的、`getBounds()` 退化成
    // `Rect.zero`）。这条分支同时避开了 `(rl − rr) / 0` 的 0/0。
    if (d.abs() < 1e-9) {
      return Path()
        ..addOval(Rect.fromCircle(center: Offset(centerX, cy), radius: _cap));
    }

    final double mx = ((rl - rr) / d).clamp(-1.0, 1.0);
    final double my = math.sqrt(math.max(0.0, 1 - mx * mx));
    final double theta = math.atan2(my, mx);

    final Path p = Path()
      // 上切线：左圆 → 右圆
      ..moveTo(c1.dx + rl * mx, cy - rl * my)
      ..lineTo(c2.dx + rr * mx, cy - rr * my)
      // 绕过右端（角度从 −θ 走到 +θ，途中经过 0 = 最右点）
      ..arcTo(Rect.fromCircle(center: c2, radius: rr), -theta, 2 * theta, false)
      // 下切线：右圆 → 左圆
      ..lineTo(c1.dx + rl * mx, cy + rl * my)
      // 绕过左端（角度从 +θ 走到 −θ，途中经过 π = 最左点）
      ..arcTo(Rect.fromCircle(center: c1, radius: rl), theta,
          2 * (math.pi - theta), false)
      ..close();
    return p;
  }
}

/// 透镜给自己留的一圈画布余量。
///
/// **为什么需要**：`ClipPath` 与 `BackdropFilter` 都只在自己的**布局边界**内生效 ——
/// 透镜按住时会凸出胶囊，画布若就只有胶囊那一格大，凸出来的部分会被裁掉，而
/// 「凸出」正是这一档的全部。客观需要的余量是 `navLensProtrude − pad`（= 4px），
/// 这里给到 24 是留够动画期间的中间态，也免得将来调参刚好卡在边界上。
const double _lensCanvasPad = 24;

/// 液态档的那枚透镜：会凸出胶囊、会形变、边缘带彩色光的一枚玻璃滴。
///
/// **它是一个参数化的 widget** —— 给它一帧几何、一个升降程度、一个主色，它就把
/// 那一帧画出来。它**不读** `liquidGlassActive`（档位判据只在 `features/home/`
/// 里读，由 `test/liquid_scope_guard_test.dart` 守着），因此既能被单测直接驱动，
/// 也不会在没人留意的时候自己长到别的玻璃面上。
class LiquidLens extends StatelessWidget {
  const LiquidLens({
    super.key,
    required this.size,
    required this.shape,
    required this.lift,
    required this.isDark,
    required this.accent,
  });

  /// 它依附的那块胶囊的完整尺寸（局部坐标的边界，原点在胶囊左上角）。
  final Size size;

  /// 这一帧的几何。
  final LiquidLensShape shape;

  /// 升程 0..1。**0 时一个像素都不画**（连阴影都不画）—— 这是「静止时不凸出」
  /// 与「与标准档逐像素相同」的保证。
  final double lift;

  final bool isDark;

  /// 主色：本体的渐变与（Task 7 的）光谱环都锚在它上面。
  final Color accent;

  @override
  Widget build(BuildContext context) {
    const double m = _lensCanvasPad;
    final Size box = Size(size.width + 2 * m, size.height + 2 * m);
    const Offset origin = Offset(m, m);

    final Widget body = ClipPath(
      clipper: _LensClipper(shape: shape, origin: origin),
      child: CustomPaint(
        size: box,
        painter: _LensBodyPainter(
            shape: shape, origin: origin, isDark: isDark, accent: accent),
      ),
    );

    return Stack(clipBehavior: Clip.none, children: <Widget>[
      // ① 浮起阴影：**在裁剪之外**。被裁掉的阴影会被切平，读不出「浮起来」。
      Positioned(
        left: -m,
        top: -m,
        width: box.width,
        height: box.height,
        child: IgnorePointer(
          child: CustomPaint(
            painter:
                _LensShadowPainter(shape: shape, origin: origin, lift: lift),
          ),
        ),
      ),
      // ② 本体：被轮廓裁住。
      Positioned(
        left: -m,
        top: -m,
        width: box.width,
        height: box.height,
        child: IgnorePointer(child: body),
      ),
    ]);
  }
}

/// 把绘制坐标系从「这块画布」搬回「胶囊左上角」。
///
/// 两处都要用，且**必须是同一份** —— 裁剪用的路径与画本体用的路径差一个像素，
/// 观感就是「一圈描边糊在轮廓外」。
Path _lensPath(LiquidLensShape shape, Offset origin) =>
    shape.toPath().shift(origin);

class _LensClipper extends CustomClipper<Path> {
  const _LensClipper({required this.shape, required this.origin});

  final LiquidLensShape shape;
  final Offset origin;

  @override
  Path getClip(Size size) => _lensPath(shape, origin);

  @override
  bool shouldReclip(_LensClipper old) =>
      old.shape.centerX != shape.centerX ||
      old.shape.width != shape.width ||
      old.shape.height != shape.height ||
      old.shape.leftRadius != shape.leftRadius ||
      old.shape.rightRadius != shape.rightRadius ||
      old.origin != origin;
}

/// 透镜浮起时投在胶囊上的影子。**升程为 0 时一个像素都不画**。
class _LensShadowPainter extends CustomPainter {
  const _LensShadowPainter({
    required this.shape,
    required this.origin,
    required this.lift,
  });

  final LiquidLensShape shape;
  final Offset origin;
  final double lift;

  @override
  void paint(Canvas canvas, Size size) {
    if (lift <= 0.01) return;
    // 影子往下偏一点、越浮越深越散 —— 「浮起来」这件事几乎全靠它。
    canvas.drawPath(
      _lensPath(shape, origin).shift(Offset(0, 2 + 3 * lift)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08 + 0.14 * lift)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 + 5 * lift),
    );
  }

  @override
  bool shouldRepaint(_LensShadowPainter old) =>
      old.lift != lift ||
      old.shape.centerX != shape.centerX ||
      old.shape.width != shape.width ||
      old.shape.height != shape.height ||
      old.shape.leftRadius != shape.leftRadius ||
      old.shape.rightRadius != shape.rightRadius;
}

/// 透镜本体：主色**半透明**渐变 + 一圈白描边。
///
/// **用的就是标准档那枚滑块的同一套配方**（`AppTokens.accentGradient`）。这一条
/// 不只是好看：换成不透明主色会把导航选中项的白字对比度从 4.7~8.2 压到
/// 2.35~4.43 —— 五种主色在深色下**全部跌破 AA**（v0.10.1 的独立审查算出来的）。
class _LensBodyPainter extends CustomPainter {
  const _LensBodyPainter({
    required this.shape,
    required this.origin,
    required this.isDark,
    required this.accent,
  });

  final LiquidLensShape shape;
  final Offset origin;
  final bool isDark;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Path p = _lensPath(shape, origin);
    canvas.drawPath(
      p,
      Paint()
        ..shader =
            AppTokens.accentGradient(accent).createShader(p.getBounds()),
    );
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: isDark ? 0.28 : 0.85),
    );
    _paintRefractedCapsuleEdge(canvas);
  }

  /// 胶囊那条边被透镜**折进去**。
  ///
  /// 真实折射应该是逐像素把底下的东西扭曲 —— 那要 shader，而且**要透镜在屏幕上的
  /// 绝对位置**（`ImageFilter.matrix` 的坐标空间永远是根坐标，四条探针验过：
  /// `Positioned` 的偏移、`Transform.translate`、`BackdropGroup` 都搬不动它）。
  /// 底栏外面又套着一层会动的 `QScale`，所以那条路不划算。
  ///
  /// 换成**自己画**：透镜凸出胶囊时，胶囊那条边在透镜里不再是直线，而是朝透镜
  /// 中心鼓一段。在 1px 的宽度上，这与真折射读起来是同一件事，而且完全可控。
  void _paintRefractedCapsuleEdge(Canvas canvas) {
    final double cy = shape.centerY;
    final double rl = shape.leftRadius;
    final double rr = shape.rightRadius;
    // 两个端头圆都够得着胶囊上下沿才有边可折。够不着 = 没凸出，那就什么都不画
    // （静止时透镜躺平在胶囊里，走的就是这一支）。
    if (rl <= cy || rr <= cy) return;

    // 透镜轮廓与胶囊上下沿的两个交点。（轮廓关于中轴上下对称，所以上下沿共用
    // 同一对 x。）
    final double sL = math.sqrt(rl * rl - cy * cy);
    final double sR = math.sqrt(rr * rr - cy * cy);
    final double xL = shape.centerX - shape.width / 2 + rl - sL;
    final double xR = shape.centerX + shape.width / 2 - rr + sR;
    if (xR - xL < 4) return;

    // 鼓多少：凸出越多越明显，但封顶 —— 鼓过头就成了「透镜里有个钩子」。
    final double bow = math.min(8, (rl - cy) * 0.9 + 3);
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: isDark ? 0.45 : 0.62);
    for (final bool top in <bool>[true, false]) {
      final double edgeY = top ? 0 : shape.capsuleH;
      // 路径按**胶囊局部坐标**建，画之前搬回画布坐标 —— 与 `_lensPath` 同一套
      // （漏掉这一步，折线会整条画到胶囊上头 24px 去，而且**只看图不太看得出来**：
      // 那条线会落在透镜凸出的顶部，读起来像一圈高光，不像「边被折了」）。
      canvas.drawPath(
        (Path()
              ..moveTo(xL, edgeY)
              ..quadraticBezierTo(
                  shape.centerX, edgeY + (top ? bow : -bow), xR, edgeY))
            .shift(origin),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_LensBodyPainter old) =>
      old.shape.centerX != shape.centerX ||
      old.shape.width != shape.width ||
      old.shape.height != shape.height ||
      old.shape.leftRadius != shape.leftRadius ||
      old.shape.rightRadius != shape.rightRadius ||
      old.origin != origin ||
      old.isDark != isDark ||
      old.accent != accent;
}
