import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'liquid_lens_metrics.dart';

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
    this.omega = AppTokens.lensSlideOmega,
    this.zeta = AppTokens.lensSlideZeta,
  });

  /// 固有频率（rad/s）与阻尼比。**可写** —— 提起与落下用两条不同的弹簧，
  /// 调用点在两个相位之间改这两个数（Apple 自己也是这么分的，见令牌表的说明）。
  double omega;
  double zeta;

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
    final double damping = 2 * zeta * omega;
    final double a =
        -omega * omega * (value - target) - damping * velocity;
    velocity += a * capped;
    value += velocity * capped;
  }
}

/// 一帧的透镜速度（px/s，带符号）：**位置的真实帧间差分 ÷ 真实 dt**，再走一道低通。
///
/// 抽成纯函数，是为了让「**同一段位移在任何帧率下都算出同一个速度**」这条性质
/// 可以被直接断言 —— 它原来是被破坏的。
///
/// 破坏它的是分母上那个 `max(dt, 16ms)` 地板（本意只是防「除以一个极小的 dt」）：
/// **16ms 正好是一帧 60Hz**，于是在 120Hz（dt ≈ 8.33ms）上 dt 被抬到 16ms，
/// 算出来的速度**恒为真实值的一半**；而帧间隔一旦在 8.33 / 16.7 之间跳
/// （可变刷新率），同一个手指速度会算出两个不同的拉伸量 —— 那就是用户
/// 2026-10-01 说的「像帧率不够」。ticker 的时间戳不会是 0；真为 0 就返回上一帧的值，
/// 别拿一个假的 dt 去凑。
///
/// [deltaPage] 是位置变化，单位是「格」（与 [LiquidLensSpring.value] 同一套）。
double lensVelocityStep({
  required double deltaPage,
  required double itemW,
  required Duration dt,
  required double previous,
}) {
  final double seconds = dt.inMicroseconds / 1e6;
  if (seconds <= 0) return previous;
  final double raw = deltaPage * itemW / seconds;
  // 低通：原始帧间差分抖得厉害（拖动时位置是 1:1 从指针事件给的，事件不按帧到达）。
  return previous * 0.6 + raw * 0.4;
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
    required this.motion,
    required this.movingRight,
    required this.rimScale,
  });

  /// 从手势状态算出这一帧的形状。
  ///
  /// [centerPage] 以「格」为单位、可为小数（跟手时是连续值）；[lift] 是升程
  /// 0..1；[velocity] 是 px/s，**带符号**（正 = 向右），只用来定方向与光谱环的门。
  /// [stretch] 是形变强度 0..1；不给就按瞬时速度现推（单测与「没有弹簧」的调用点
  /// 走这条），给了就用它 —— 底栏那条**弹簧驱动**的形变走这条。
  ///
  /// [motion] 是光谱环／光晕的门 0..1。同样：不给就按瞬时速度现推，给了就用它 ——
  /// 底栏那条**弹簧驱动**的渐入渐出走这条（用户 2026-10-01：「彩边出现得太突然了」）。
  ///
  /// **这几个量必须分开**：形变要跟速度走（那是头大尾小），环的门要「一动就满」，
  /// 而亮度要有渐入渐出。拿同一个量喂三处就只能三选一 —— 而用户三轮说的正是
  /// 这三件事。
  factory LiquidLensShape.of({
    required double itemW,
    required double capsuleH,
    required double pad,
    required double centerPage,
    required double lift,
    required double velocity,
    double? stretch,
    double? motion,
    LiquidLensMetrics? metrics,
  }) {
    // 两个外扩量是**每个面各自的观感**（见 `LiquidLensMetrics` 的说明）。不给时用
    // 底栏那档的常量 —— 那正是抽共享件之前的行为，所以既有调用点的渲染一个像素都不变。
    final LiquidLensMetrics m = metrics ??
        const LiquidLensMetrics(
          protrude: AppTokens.navLensProtrude,
          liftWidth: AppTokens.lensLiftWidth,
        );
    // 形变强度 0..1：拉伸与压缩都用它一个量。
    final double s = (stretch ?? (velocity.abs() / AppTokens.lensVelocityRef))
        .clamp(0.0, 1.0);
    // 光谱环的门：**「动不动」，不是「多快」**（用户 2026-10-01：「一动就直接达到
    // 满效果」）。60px/s 就封顶，那以下按比例淡入只是为了慢速收尾时不眨一下。
    final double glow =
        (motion ?? (velocity.abs() / AppTokens.lensRingFullSpeed))
            .clamp(0.0, 1.0);
    return LiquidLensShape._(
      centerX: pad + (centerPage + 0.5) * itemW,
      // 外扩与形变都**加在/乘在基准尺寸上，不互相乘** —— 见下面 height 的说明。
      // 两个外扩量来自 [m]：底栏取「横向与纵向同量级」（纵横一起长才读得出体积），
      // 而开关取 `liftWidth: 0` —— 只长个儿不变宽（iOS 26 那种形状变化）。
      width: itemW * (1 + AppTokens.lensStretch * s) + m.liftWidth * lift,
      // ⚠️ **凸出必须加在「压扁之后」的基准上，不许乘进形变里。**
      //
      // 原式 `(基准 + 2·凸出·lift) × (1 − 0.12·s)` 把压扁乘在了凸出上：lift=1 /
      // 700px/s 时高 63.4，而胶囊高 64 —— 透镜整个沉回胶囊里面，按住拖动时
      // 「一枚浮起来的玻璃滴」直接掉回「一枚躺着药丸」。**「按住」这个动作的全部
      // 读感就在那零点几个像素上。** 实测见 `test/liquid_lens_test.dart` 的扫描。
      height: (capsuleH - 2 * pad) * (1 - AppTokens.lensSquash * s) +
          2 * m.protrude * lift,
      capsuleH: capsuleH,
      stretch: s,
      motion: glow,
      movingRight: velocity > 0,
      rimScale: m.rimScale,
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

  /// 归一化形变强度 0..1，决定端头的不对称程度。
  final double stretch;

  /// 光谱环的门 0..1 —— **「在动」的程度，不是「多快」**。
  ///
  /// 和 [stretch] 分家是刻意的：形变要跟速度走（头大尾小），环却要「一动就满」。
  /// 喂同一个量就只能二选一 —— 而用户 2026-10-01 两次说的正是这两件事。
  final double motion;

  /// 这一帧是否在向右移动（决定哪一端是「前缘」）。静止时为 false，
  /// 但那时两端半径相等，所以取哪一边都一样。
  final bool movingRight;

  /// 四层光谱与浮起阴影的**整体缩放**（见 `LiquidLensMetrics.rimScale`）。
  /// 1.0 = 底栏那一档，也就是那四个宽度被量出来的尺子。
  final double rimScale;

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

    // **退化档：`宽 <= 高`**（独立审查抓出来的 Critical）。
    //
    // 这时水平胶囊**数学上不成立**：前后缘半径之差（`0.35·s·_cap`）恰好等于圆心距
    // `d`（`width − rl − rr`），于是 `mx` 正好是 **1** —— 外公切线塌成一条**竖线**，
    // 而右端那段圆弧的扫描角正好是 **2π**。**`Path.arcTo` 在扫描角为 2π 时什么都不
    // 画**（`sky_engine/lib/ui/painting.dart` 的文档写着），实测整条路径面积为 0、
    // `getBounds()` 退化成 `Rect.zero`：**透镜整个消失**，而死区边界由浮点舍入决定 ——
    // 表现是拖动中**一闪一没**。
    //
    // 哪些尺寸会掉进来：`itemW + 10·lift <= 52 + 20·lift`，也就是 `itemW` 小于约 62
    // 的窗口。**200×400 那个工装档（itemW 39）在 lift=1 时一半的速度都在死区里。**
    //
    // 改成**竖直的胶囊**：把上面那套闭式解按目标宽搭好、再**纵向拉伸**到目标高
    // （见 `_verticalStretched`）。宽度与高度都保住了 —— 于是「按住时凸出胶囊」这个
    // 信号在窄窗里照样成立，比退成一枚圆团更好（圆团会把高度一起丢掉）。
    //
    // 这条构造**天然带两个半径**，而且前后缘还在**左右**，所以竖直档也读得到
    // 头大尾轻 —— 上一版是「上圆 + 下圆 + 中矩形」并起来的，那两个半径在那儿
    // 是算了但没用。
    //
    // ⚠️ **上一版并三个子路径还有个更贵的代价**：填色对，**描边会把三段边界全画
    // 出来**，包括互相重叠的内部接缝。四层光谱全是描边，于是在钮的内部留下横线
    // 与内侧弧 —— 用户 2026-10-01：「彩边穿到滑块里边了，而且还不规则，也不贴边」。
    // 转出来的是一条**闭合子路径**，没有这个问题。
    if (width <= height) {
      // ⚠️ **别直接把 `_cap`（= 宽/2）交给它。** 拉伸**不能**把两端的圆变回来：
      // 局部那两个圆要是各占满半宽（`rl + rr ≥ 宽`），尾部整个落进头部圆里，
      // 轮廓退化成**一个圆**、尾巴消失 —— 而且 `mx` 会正好等于 1，踩 `arcTo`
      // 扫 2π 那个坑。留出尾部收缩的余量，`stretch = 0` 时余量归零（局部是个
      // 正圆，靠 `_verticalStretched` 里那道 `d` 钳位兜住）。
      final double capV = width / 2 * (1 - 0.175 * stretch);
      final double thin = capV * (1 - 0.35 * stretch);
      return _verticalStretched(
        centerX: centerX,
        cy: cy,
        w: width,
        h: height,
        rl: movingRight ? thin : capV,
        rr: movingRight ? capV : thin,
      );
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
    this.fill,
    this.showRingCore = true,
    this.showRefractedEdge = true,
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

  /// 本体填充。不给 = `AppTokens.accentGradient(accent)`（主色玻璃滴）。
  ///
  /// **开关那一档要给白色玻璃** —— 它那枚钮是**白的**（压在淡染轨道上，主色玻璃滴
  /// 会糊成一片）。底栏与分段器用默认值。
  final List<Color>? fill;

  /// 压在轮廓上的那条白芯。**白本体的那一档要关掉它** —— 白上画白等于没画，
  /// 反而把轮廓读没了。
  final bool showRingCore;

  /// 把容器的边「折进来」那条线（见 [_LensBodyPainter._paintRefractedCapsuleEdge]）。
  ///
  /// 小控件上要关掉：它画的是**容器**的上下沿在透镜里的弯折，而开关的钮只有 22px
  /// 宽，那几道弧读起来是乱线。
  final bool showRefractedEdge;

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
            shape: shape,
            origin: origin,
            isDark: isDark,
            accent: accent,
            fill: fill,
            showRingCore: showRingCore,
            showRefractedEdge: showRefractedEdge),
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
      // ①b 外溢光晕：**同样在裁剪之外** —— 本体画不到轮廓外面（那正是「只往内散」
      // 的实现方式），所以往外那一份只能单开一层。
      Positioned(
        left: -m,
        top: -m,
        width: box.width,
        height: box.height,
        child: IgnorePointer(
          child: CustomPaint(
            painter: _LensGlowPainter(
                shape: shape, origin: origin, lift: lift, accent: accent),
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

/// **竖直**的两半径胶囊 —— 用的是同一套闭式解，但收尾是**纵向拉伸**，不是旋转。
///
/// ⚠️ **别改成「整体转 90°」。** 转过之后局部坐标的「左右两端」会落到屏幕的上下
/// 两头去 —— 于是「头大尾轻」变成「上大下小」。用户 2026-10-01 把这一条说得很死：
/// 「头重脚轻肯定不能是上下的，肯定要左右」。**拉伸**则两样都保住：先在横着的坐标系
/// 里按**目标宽**搭一枚两半径胶囊（前后缘还在左右），再把它纵向拉长到目标高。
///
/// 落在屏幕上就是「两枚高低不同的椭圆 + 外公切线」：静止（两半径相等）时是一枚
/// **竖着的椭圆**，拖动时一端粗一端细 —— 上下拉长与左右头重脚轻同时成立。
///
/// 另一条好处：线性拉伸出来的路径 `getBounds()` 是紧的（旋转那版会松一截 —— 同一份
/// 构造在**横向**档上也是松的，见 `test/liquid_lens_vertical_test.dart` 的说明）。
Path _verticalStretched({
  required double centerX,
  required double cy,
  required double w,
  required double h,
  required double rl,
  required double rr,
}) {
  // 局部坐标系：**竖直中轴在 y = 0**（这样拉伸之后才不用再挪一次），横向铺满 [0, w]。
  final Offset c1 = Offset(rl, 0);
  final Offset c2 = Offset(w - rr, 0);
  // ⚠️ **圆心距要钳一个正的下限。** 两个**等半径**的圆、圆心距又恰好等于 `2r` 时
  // （局部是个正圆）`d = 0`，而 `(rl − rr) / d` 就是 `0 / 0`。钳住之后
  // `mx = 0`、`my = 1`、`theta = π/2`：外公切线是一条竖直线、两端圆弧各扫 π ——
  // 精确，也不碰 `arcTo` 扫过 2π 那个坑（见 `toPath()` 顶上那段）。
  final double d = math.max(0.01, c2.dx - c1.dx);
  final double mx = ((rl - rr) / d).clamp(-1.0, 1.0);
  final double my = math.sqrt(math.max(0.0, 1 - mx * mx));
  final double theta = math.atan2(my, mx);

  final Path p = Path()
    ..moveTo(c1.dx + rl * mx, -rl * my)
    ..lineTo(c2.dx + rr * mx, -rr * my)
    ..arcTo(Rect.fromCircle(center: c2, radius: rr), -theta, 2 * theta, false)
    ..lineTo(c1.dx + rl * mx, rl * my)
    ..arcTo(Rect.fromCircle(center: c1, radius: rl), theta,
        2 * (math.pi - theta), false)
    ..close();

  // 纵向拉长到目标高，再搬到透镜中心。局部 (x, y) → 屏幕
  // (centerX − w/2 + x, cy + sy·y)。
  final double capV = math.max(rl, rr);
  final double sy = h / (2 * capV);
  return p.transform(Float64List.fromList(<double>[
    1, 0, 0, 0, //
    0, sy, 0, 0, //
    0, 0, 1, 0, //
    centerX - w / 2, cy, 0, 1,
  ]));
}

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
    // 偏移与模糊都跟着透镜尺寸缩：小控件上照 64 高那档的量投，会得到一圈比钮还大的
    // 灰晕（与彩边同一个毛病）。
    final double k = shape.rimScale;
    canvas.drawPath(
      _lensPath(shape, origin).shift(Offset(0, (2 + 3 * lift) * k)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08 + 0.14 * lift)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, (5 + 5 * lift) * k),
    );
  }

  @override
  bool shouldRepaint(_LensShadowPainter old) =>
      old.lift != lift ||
      old.origin != origin ||
      old.shape.centerX != shape.centerX ||
      old.shape.width != shape.width ||
      old.shape.height != shape.height ||
      old.shape.leftRadius != shape.leftRadius ||
      old.shape.rightRadius != shape.rightRadius;
}

/// **外溢光晕**：透镜轮廓**之外**那一圈彩色。
///
/// 必须是单独一层：本体挂在 `ClipPath` 底下，外面根本画不出来 —— 那正是「只往内散」
/// 的实现方式。这一层与浮起阴影同一层位（都在裁剪之外）。
///
/// 用户 2026-10-01：「往外也散一点」。真的折射会在玻璃边外侧留下一条亮边，
/// 代价是那枚水滴的轮廓会被一圈很淡的颜色裹住 —— 那是**有意**的。
///
/// 门与光谱环**共用**（`motion`）：不按就不散，静止时轮廓外一个彩色像素都没有。
class _LensGlowPainter extends CustomPainter {
  const _LensGlowPainter({
    required this.shape,
    required this.origin,
    required this.lift,
    required this.accent,
  });

  final LiquidLensShape shape;
  final Offset origin;
  final double lift;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (shape.motion <= 0.05) return;
    final Path p = _lensPath(shape, origin);
    final double k = shape.rimScale;
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppTokens.lensGlowWidth * k
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, AppTokens.lensGlowBlur * k)
        ..shader = spectralSweep(
          accent: accent,
          alpha: 0.28 * shape.motion,
          floor: 0.36,
          span: 0.64,
          pow2: false,
          // 与里面那两层再错一个色相：三层叠起来才是「摊开的光谱」。
          hueLag: -12,
        ).createShader(p.getBounds()),
    );
  }

  @override
  bool shouldRepaint(_LensGlowPainter old) =>
      old.lift != lift ||
      old.accent != accent ||
      old.origin != origin ||
      old.shape.centerX != shape.centerX ||
      old.shape.width != shape.width ||
      old.shape.height != shape.height ||
      old.shape.leftRadius != shape.leftRadius ||
      old.shape.rightRadius != shape.rightRadius ||
      old.shape.motion != shape.motion;
}

/// 胶囊那条边被透镜**折进去**的那一帧几何。纯函数 —— `null` = 这一帧不画。
///
/// **为什么要有这个函数**：这段逻辑原先整个住在 painter 里，于是它的失败方式
/// （在哪些 (lift, 速度) 上不画）**只有出图才看得见**。抽出来之后它可以被扫一遍
/// 参数空间 —— 而扫出来的是一个硬缺陷：
///
/// 原早退条件是「**两个端头半径都**大于胶囊半高」，可速度一上来后缘半径
/// （`×(1 − 0.35·stretch)`）必然先掉下去，于是**整条折边被一票否决**。实测
/// lift=1 时超过约 150px/s 它就完全消失，而常态拖动是 300~1000px/s ——
/// 也就是说这个效果**只在「按住而且手指不动」时存在**，恰好是唯一不会去拖的状态。
///
/// 现在两处都改成连续的：
///   · 门开在「**至少一端**够到」（`reach = max(rl, rr) − cy > 0`）；
///   · 够不到的那一端把半径**钳到刚好相切**，交点连续地退化成 0，而不是整条不画；
///   · 再按 [AppTokens.lensEdgeFade] 让不透明度**随凸出量淡入** —— 于是它既不会
///     在高速下开天窗，也不会「啪」地出现或消失。
({double xL, double xR, double bow, double fade})? refractedCapsuleEdge(
    LiquidLensShape shape) {
  final double cy = shape.centerY;
  final double rl = shape.leftRadius;
  final double rr = shape.rightRadius;

  // 凸出量取**较大的那一端**：前缘总是先够到，后缘因为被压扁会晚一步。
  final double reach = math.max(rl, rr) - cy;
  if (reach <= 0) return null;

  // 钳到相切：`r = cy` 时 `sqrt(r² − cy²) = 0`，端点落在端头圆的竖直切线上。
  // 于是 r 从 cy 上方往下掉时，那一端是**连续地往回收**，不是整条消失。
  final double sL = math.sqrt(math.max(0, rl * rl - cy * cy));
  final double sR = math.sqrt(math.max(0, rr * rr - cy * cy));
  final double xL = shape.centerX - shape.width / 2 + rl - sL;
  final double xR = shape.centerX + shape.width / 2 - rr + sR;
  // 纯防御：可达区间（lift ≥ 0.6）里这个跨度约 35~74，够不着。
  if (xR - xL < 2) return null;

  return (
    xL: xL,
    xR: xR,
    // 鼓多少：凸出越多越明显，但封顶 —— 鼓过头就成了「透镜里有个钩子」。
    bow: math.min(8, reach * 0.9 + 3),
    fade: (reach / AppTokens.lensEdgeFade).clamp(0.0, 1.0),
  );
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
    required this.fill,
    required this.showRingCore,
    required this.showRefractedEdge,
  });

  final List<Color>? fill;
  final bool showRingCore;
  final bool showRefractedEdge;

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
        ..shader = (fill == null
                ? AppTokens.accentGradient(accent)
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: fill!))
            .createShader(p.getBounds()),
    );
    // 静止时**连画都不画**：不是「画一层透明的」，而是这一整趟省掉。
    // 门用 `motion`（「在动」）而不是 `stretch`（「多快」）—— 见 `motion` 的说明。
    if (shape.motion > 0.05) {
      // 顺序要紧：**光晕在下、彩线在上**。反过来的话那条细线会浮在光晕外面，
      // 又读回「贴了一层彩带」。
      _paintHalo(canvas, p);
      _paintSpectralRing(canvas, p);
    }
    // 白色高光芯压在环上 —— **这一层是「读作光」的关键**：一条纯彩色的环读起来是
    // 「贴了一圈彩虹贴纸」，而「一圈被点亮的玻璃边」需要一条白芯把颜色挤到两侧去。
    // 浅色 0.85 → 0.70、宽 1.2 → 1.0（2026-10-01）：它自己也是一条硬边，收一档
    // 免得又把「彩带」的读感带回来。
    if (showRingCore) {
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = AppTokens.lensRingCoreWidth * shape.rimScale
          ..color = Colors.white.withValues(alpha: isDark ? 0.28 : 0.70),
      );
    }
    // 白芯**不跟速度走**：它不是折射，是这块玻璃自己的边（标准档那枚滑块也有一条
    // 同样明度的白边）。收掉它的话静止时透镜就没有轮廓了。
    if (showRefractedEdge) _paintRefractedCapsuleEdge(canvas);
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
  ///
  /// 这一帧**画不画、画多鼓、多淡**全由 [refractedCapsuleEdge] 那个纯函数定
  /// （它是可单测的，说明也在那边）。
  void _paintRefractedCapsuleEdge(Canvas canvas) {
    final ({double xL, double xR, double bow, double fade})? e =
        refractedCapsuleEdge(shape);
    if (e == null) return;

    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      // 乘 `fade`：凸出 0 → lensEdgeFade 走 0 → 满。**这是「不再啪地出现」的
      // 全部依据** —— 门一开就给满亮度的话，观感还是断的。
      ..color = Colors.white
          .withValues(alpha: (isDark ? 0.45 : 0.62) * e.fade);
    for (final bool top in <bool>[true, false]) {
      final double edgeY = top ? 0 : shape.capsuleH;
      // 路径按**胶囊局部坐标**建，画之前搬回画布坐标 —— 与 `_lensPath` 同一套
      // （漏掉这一步，折线会整条画到胶囊上头 24px 去，而且**只看图不太看得出来**：
      // 那条线会落在透镜凸出的顶部，读起来像一圈高光，不像「边被折了」）。
      canvas.drawPath(
        (Path()
              ..moveTo(e.xL, edgeY)
              ..quadraticBezierTo(
                  shape.centerX, edgeY + (top ? e.bow : -e.bow), e.xR, edgeY))
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
      // **`motion` 必须比**：形状可以一模一样而环的明暗在变（同样的几何、
      // 速度从 0 到 60）。漏掉它，环就会卡在上一帧的亮度上不动。
      old.shape.motion != shape.motion ||
      old.origin != origin ||
      old.isDark != isDark ||
      old.accent != accent ||
      !listEquals(old.fill, fill) ||
      old.showRingCore != showRingCore ||
      old.showRefractedEdge != showRefractedEdge;
  /// **折射光晕**：同一条扫掠渐变，画得又宽又糊 —— 这是「光晕」而不是「彩带」的
  /// 全部来源。
  ///
  /// 用户 2026-10-01：「现在给我的感觉就像在这个滑块的边缘加了一层彩带一样。
  /// 我们想要的是加一层折射的光晕。」拆开就是四件事：等宽 → 从边缘**向内衰减**、
  /// 等亮 → 亮在边缘、**硬边** → 糊开、贴在表面 → 在玻璃**里面**。这一层办后三件，
  /// [AppTokens.lensRingWidth] 那条细线办「边缘那一下」。
  ///
  /// 它挂在本体那层 `ClipPath` 底下，所以外半边被裁掉 —— **只往轮廓里面散**。
  /// 往外那一份由 [_LensGlowPainter] 单开一层负责（本体画不到轮廓外面）。
  ///
  /// 两层、色相各偏一点（−30° 与 +22°）：真色散会把光谱**摊开**，同一处边缘能
  /// 同时看到相邻的两个色调。一层的话仍然只是「一个颜色一个位置」。
  void _paintHalo(Canvas canvas, Path p) {
    final Rect b = p.getBounds();
    final double k = shape.rimScale;
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppTokens.lensHaloWidth * k
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, AppTokens.lensHaloBlur * k)
        ..shader = spectralSweep(
          accent: accent,
          alpha: 0.42 * shape.motion,
          floor: 0.36,
          span: 0.64,
          pow2: false,
          hueLag: -30,
        ).createShader(b),
    );
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppTokens.lensHaloInnerWidth * k
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, AppTokens.lensHaloInnerBlur * k)
        ..shader = spectralSweep(
          accent: accent,
          alpha: 0.52 * shape.motion,
          floor: 0.40,
          span: 0.60,
          pow2: false,
          hueLag: 22,
        ).createShader(b),
    );
  }

  /// 光谱环：沿透镜轮廓走一圈**色相**，左上略亮。
  ///
  /// **为什么是「画」而不是「算」**：色散只把**已经存在**的颜色分开 —— 主色是青的，
  /// 折射出来的还是青的，变不出彩虹。iOS 底栏那圈彩虹来自它背后那块彩色背景
  /// （照片、图标、彩色内容），而本 App 的底色是刻意的极简黑白。想在这里看见彩色，
  /// 只能画出来。这也正是 `liquid_glass_widgets` 给 iOS 26 那档校准**主动把色散关成
  /// 0** 的原因（它自己的注释写着「真实的 iOS UI 玻璃几乎没有虹彩」）—— 我们比它
  /// 更显眼，因为我们是**刻意**让它显眼的。
  ///
  /// 颜色锚在 `accent` 的**色相**上：绕一圈走 300°，于是它既「五颜六色」又始终
  /// 属于这个主题。
  void _paintSpectralRing(Canvas canvas, Path lensPath) {
    canvas.drawPath(
      lensPath,
      Paint()
        ..style = PaintingStyle.stroke
        // 跟着透镜尺寸缩（见 `rimScale`）：不缩的话这条 2.4px 的线在小钮上会与那两层
        // 光晕一起把钮整个盖住。
        ..strokeWidth = AppTokens.lensRingWidth * shape.rimScale
        ..shader = spectralSweep(
          accent: accent,
          // **整体乘的是「动不动」而不是「多快」**（用户 2026-10-01：「彩色边缘
          // 不明显，还是恢复成一动就直接达到满效果吧」）。乘的是 `motion` 而不是
          // `stretch` —— 形变要跟速度走，彩边只问「在不在动」。
          alpha: shape.motion,
          // 底面 0.58：原来是 `0.06 + 0.86·toward²`，右下那两个方向实际只有
          // 0.06~0.08 —— 等于没有颜色（用户 2026-10-01：「只有左边和上边有彩边，
          // 右边和下边缘都没有」）。抬上来之后**四面八方都有色**，左上只是略亮。
          floor: 0.58,
          span: 0.42,
          pow2: true,
        ).createShader(lensPath.getBounds()),
    );
  }
}

/// 沿透镜轮廓走一圈的**色相**渐变 —— 光谱环、两层光晕、外溢那一层共用同一份。
///
/// `SweepGradient` 的角度从 **+x（正右）** 起算、屏幕上顺时针，于是
/// `t = 0` 是右边、`0.25` 下、`0.5` 左、`0.75` 上。亮度峰值锚在 **225°（左上）**，
/// 因为光是从左上来的。
///
/// **[floor] / [span] 决定「最暗那个方向有多亮」，而这一对数是踩过坑的。**
/// 原先是 `0.06 + 0.86·toward²`，`toward` 峰值锚在 225° **且又平方一次** ——
/// 代进八个方位：左上 **0.92** / 左 0.69 / 上 0.69 / 右上 0.28 / 左下 0.28 /
/// 右 **0.08** / 下 **0.08** / 右下 **0.06**。后三档等于没有颜色。
///
/// 用户 2026-10-01 报的「不管往左滑还是往右滑，感觉只有左边和上边有彩边」就是它，
/// 而且**与往哪边滑无关**（用户观察到的正是这一点）—— 这圈颜色画在**固定的屏幕
/// 方位**上，不跟运动方向走。护栏在 `test/liquid_lens_test.dart` 的
/// 「彩边四面八方都有颜色」。
///
/// [hueLag] 是相对主色的整体色相偏移，用来把两层光晕**错开成光谱**。
SweepGradient spectralSweep({
  required Color accent,
  required double alpha,
  required double floor,
  required double span,
  required bool pow2,
  double hueLag = 0,
  int steps = 24,
}) {
  final HSLColor base = HSLColor.fromColor(accent);
  final List<Color> colors = <Color>[];
  final List<double> stops = <double>[];
  for (int i = 0; i <= steps; i++) {
    final double t = i / steps;
    final double toward = (1 + math.cos((t * 360 - 225) * math.pi / 180)) / 2;
    final double w = pow2 ? toward * toward : toward;
    colors.add(HSLColor.fromAHSL(
      (floor + span * w).clamp(0.0, 1.0) * alpha,
      (base.hue + hueLag + 300 * t) % 360, // 走色相，但绕回主色
      base.saturation.clamp(0.55, 0.95),
      0.66,
    ).toColor());
    stops.add(t);
  }
  return SweepGradient(colors: colors, stops: stops);
}

/// 胶囊那一圈**方向性边光**。
///
/// 从 `glass.dart` 搬过来的（v0.10.3）：那一版里它和一个 painter 画透镜本体混在一起，
/// 而透镜现在已经由 [LiquidLens] 负责 —— 留下的只有「静止的玻璃面上那圈光」。
///
/// 一圈**方向性**描边（左上高光 → 右下收边）。浅色档的配方是「左上高光 + 右下轻收」
/// 而不是「一圈白」—— 白光照白底**结构性地**看不见，这是量出来的。
///
/// ⚠️ **它原来还画第二条东西：「光跟随滑块」的亮带**（滑块所在那一段胶囊边亮起来，
/// 深色下白 @0.95 + 模糊 3 + 加宽 1.4 倍）。2026-10-01 拆掉了 —— 用户原话：
/// 「中间边缘怎么都会发光啊？尤其是在深色模式下很明显」。它在这几个面上都不成立：
/// 滴几乎填满胶囊高，亮带只剩**溢出到胶囊外**的那半截能看见，读起来像「边缘漏了个
/// 光斑」；而它本来想提示的「药丸在哪儿」本来就不需要提示，药丸自己就是画面里最大
/// 那块颜色。护栏见 `test/liquid_track_test.dart` 的「边光是水平均匀的」。
class CapsuleRimPainter extends CustomPainter {
  const CapsuleRimPainter({
    required this.radius,
    required this.isDark,
    this.compact = false,
  });

  final double radius;
  final bool isDark;

  /// 小控件（底栏胶囊）用更细的一圈：同一个宽度在小控件上相对更显眼。
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final double width = AppTokens.glassRimProbeWidth(isDark, compact: compact);
    final RRect rrect = RRect.fromRectAndRadius(
      rect.deflate(width / 2),
      Radius.circular(radius),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        // **轴是竖直的，不是对角。** 对角那版（`topLeft → bottomRight`）在近方形的
        // 卡片上读作「左上高光 + 右下收边」—— 它本来就是照卡片量的；但在 6:1 的
        // 底栏胶囊上渐变轴几乎就是水平的，于是退化成**左端纯白、右端 10% 黑**。
        // 实测（浅色 / 液态档 / 底栏）：左缘 `rgb(251,250,251)`、
        // 右缘 `rgb(203,199,204)` —— 就是用户报的「左边很浅、几乎看不清胶囊，
        // 右边有镜片效果」。
        //
        // 竖直之后 t 只跟 **y** 有关，**左右结构性地完全一致**，且与宽高比无关。
        // 别改回对角 —— `test/glass_tier_test.dart` 里有一条光栅化护栏钉着。
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const <double>[0.0, 0.45, 1.0],
          colors: AppTokens.glassRimProbe(isDark),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(CapsuleRimPainter old) =>
      old.radius != radius ||
      old.isDark != isDark ||
      old.compact != compact;
}

/// 一枚图标（连同它下面那行文字）被**透镜边缘**影响的那一帧。
///
/// **峰值在边缘、不在中心**（用户 2026-10-01 指出的）：厚透镜**中间是平的**、
/// 只有边缘那圈曲率在折光 —— 一块平板玻璃压上去什么都不扭曲。所以图标躺在透镜
/// 正中时几乎不变形，进到内部之后反而看得清；只有**透镜的边缘（那圈彩边）扫过
/// 它**的时候才被挤一下。开源实现里那个 `circle` 衰减曲线的注释写的就是这件事
/// （「峰值在 rim，做那种利落的压缩环」）。
///
/// 纯函数，好单测。返回的是要套在这个图标上的仿射参数：
/// 横向压扁 / 纵向拉长（面积近似守恒 = 「被挤过去」），再朝远离透镜中心的方向推。
({double scaleX, double scaleY, double dx}) lensIconWarp({
  required double iconCenterX,
  required double lensCenterX,
  required double lensHalfWidth,
}) {
  // 半宽非正（还没布局 / 退化档）就什么都不做 —— 别让调用点去判。
  if (lensHalfWidth <= 0) return (scaleX: 1.0, scaleY: 1.0, dx: 0.0);
  // t = 到透镜中心的距离 ÷ 半宽。**t = 1 就是透镜的边缘。**
  final double t = (iconCenterX - lensCenterX).abs() / lensHalfWidth;
  final double u = (t - 1) / AppTokens.lensIconRingSigma;
  final double w = math.exp(-u * u);
  // 权重小到看不见就别造一个几乎恒等的矩阵 —— 那会让这个图标每帧都重绘。
  if (w < 0.01) return (scaleX: 1.0, scaleY: 1.0, dx: 0.0);
  final double pinch = AppTokens.lensIconPinch * w;
  return (
    scaleX: 1 - pinch,
    scaleY: 1 + pinch,
    dx: (iconCenterX >= lensCenterX ? 1 : -1) * AppTokens.lensIconPush * w,
  );
}
