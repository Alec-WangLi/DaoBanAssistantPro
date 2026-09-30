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
