import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/liquid_lens.dart';
import '../../core/glass/liquid_lens_metrics.dart';

/// 日历那枚选中块在**液态档**下的样子：一枚会鼓起来、会跟着拖动形变的玻璃透镜。
///
/// 它只认三个输入 —— **在哪儿**（由外面的 `AnimatedPositioned` 摆）、**按住没有**
/// （[liftTarget]）、**拖动速度**（[velocity]）—— 其余全关在里面：升降两条弹簧、
/// 环的门那条弹簧、速度的低通与松手后的衰减、以及那个只在动的时候才跑的 `Ticker`。
///
/// **它不读档位**（`liquidGlassActive`）—— 判据只许出现在调用点，与本仓既有纪律
/// 一致（`liquid_scope_guard_test` 扫源码守着）。
///
/// 几何（照规格 §4.1）：透镜 = 格子内缩 [AppTokens.gapHair]、圆角
/// [AppTokens.radiusM]（**与卡片同源**，否则四个角会各露一条月牙 —— v0.7.3 的教训）。
class CalendarLens extends StatefulWidget {
  const CalendarLens({
    super.key,
    required this.size,
    required this.liftTarget,
    required this.dragging,
    required this.velocity,
    required this.isDark,
    required this.accent,
  });

  /// 格子盒（`cellW × cellH`）—— 透镜在它内缩 `gapHair` 处，与卡片严丝合缝。
  final Size size;

  /// 1 = 按住 / 拖动中，0 = 松手。走的是 Apple 那两条弹簧（提起 ω=23.3，
  /// 落下 ω=12.6）—— 落下更从容，落定那一下还会**过冲到比格子略小**约 1px。
  ///
  /// 它替掉的是标准档那个 1.22 的等比放大：两个叠在一起就重了（图上看过），
  /// 「按住」这个动作改由「四面鼓出 + 浮起阴影」承担。
  final double liftTarget;

  /// 手指还在不在。松手之后速度由本部件自己衰减。
  final bool dragging;

  /// 这一帧的拖动速度（px/s，逻辑像素）。二维都认：横向拉宽、纵向拉高。
  final Offset velocity;

  final bool isDark;
  final Color accent;

  /// 按住时**每侧**鼓出多少（逻辑 px）。格子缝只有 4px，所以鼓出去会压到邻居边上。
  static const double protrude = 6;

  /// 满升程时**横向总共**外扩多少。与 [protrude] 同量级 —— 纵横一起长才读得出体积。
  static const double liftWidth = 2 * protrude;

  /// 形变饱和的速度门（px/s）。格子宽 56.6：比开关的 25 宽、比底栏的 88 窄，取中间。
  static const double velocityRef = 400;

  @override
  State<CalendarLens> createState() => _CalendarLensState();
}

class _CalendarLensState extends State<CalendarLens>
    with SingleTickerProviderStateMixin {
  /// 升程。目标由 [CalendarLens.liftTarget] 给，两条弹簧参数在提起 / 落下之间切。
  ///
  /// `late final` + 在 `initState` 里建：初值要读 `widget`，而**字段初始化器里
  /// 读不到它**（那时 framework 还没把 widget 装上）。踩过一次：写成字段初始化器
  /// 里的 `target: 0`，于是按住时挂上来的这一枚**目标永远是 0**、升程一动不动。
  late final LiquidLensSpring _lift;

  /// 光谱环／光晕的门。**它走自己的一条弹簧**（亮起 ω=26、熄灭 ω=12，与底栏同一套）——
  /// 直接拿速度当门的话，拖动启动那一帧彩边是「啪」地亮起来的（v0.10.8 的老毛病）；
  /// 而熄灭要比亮起慢，不然停手那一下颜色会「啪」地没。
  late final LiquidLensSpring _ring;

  /// 拖动速度的低通值（松手之后逐帧衰减到 0）。
  double _vx = 0;
  double _vy = 0;

  Ticker? _ticker;
  Duration _lastStamp = Duration.zero;

  @override
  void initState() {
    super.initState();
    // `value` 也一并就位：切档位 / 重建时这一枚块是新挂上去的，而手指可能还按着
    // —— 那时不该从 0 再弹一次（那会读成「抖了一下」）。
    _lift = LiquidLensSpring(
      target: widget.liftTarget,
      value: widget.liftTarget,
      omega: _liftOmegaFor(widget.liftTarget > 0),
      zeta: _liftZetaFor(widget.liftTarget > 0),
    );
    _ring = LiquidLensSpring(
      target: 0,
      omega: AppTokens.lensUnlitOmega,
      zeta: AppTokens.lensUnlitZeta,
    );
    // 挂载时就把这一帧的速度吃进来 —— 与 `didUpdateWidget` 那条同一个道理：
    // **不能只更新读**。只读更新那一侧的话，带着速度挂上来的这一枚（切档位、
    // 重建）会停在「没在动」上，彩边永远不亮。
    if (widget.dragging) {
      _vx = widget.velocity.dx;
      _vy = widget.velocity.dy;
    }
    _retargetRing();
    // ⚠️ **首次挂载也要推帧。** 只在 `didUpdateWidget` 里起 ticker 是不够的：
    // 挂上来的第一帧没有任何人推，弹簧就永远停在初值上。
    _syncTicker();
  }

  /// 提起与落下是两条不同的弹簧（Apple 的 Lift / Unlift）—— 落下更从容。
  /// 写成同一个 ω 的话，松手那一下会「啪」地弹回去。
  static double _liftOmegaFor(bool up) =>
      up ? AppTokens.lensLiftOmega : AppTokens.lensDropOmega;
  static double _liftZetaFor(bool up) =>
      up ? AppTokens.lensLiftZeta : AppTokens.lensDropZeta;

  /// 环的门：**「动不动」，不是「多快」**（60px/s 就封顶）—— 那以下按比例淡入
  /// 只是为了慢速收尾时不眨一下；而**渐变本身**由 [_ring] 那条弹簧给。
  void _retargetRing() {
    final bool moving =
        math.max(_vx.abs(), _vy.abs()) > AppTokens.lensRingFullSpeed;
    _ring
      ..target = moving ? 1 : 0
      ..omega = moving ? AppTokens.lensLitOmega : AppTokens.lensUnlitOmega
      ..zeta = moving ? AppTokens.lensLitZeta : AppTokens.lensUnlitZeta;
  }

  @override
  void didUpdateWidget(CalendarLens old) {
    super.didUpdateWidget(old);
    if (widget.liftTarget != old.liftTarget) {
      _lift
        ..target = widget.liftTarget
        ..omega = _liftOmegaFor(widget.liftTarget > 0)
        ..zeta = _liftZetaFor(widget.liftTarget > 0);
    }
    if (widget.dragging) {
      // 拖动中：把外面这一帧的采样低通进来（外面已经做过帧间差分）。
      _vx = _vx * 0.6 + widget.velocity.dx * 0.4;
      _vy = _vy * 0.6 + widget.velocity.dy * 0.4;
    } else {
      // 松手：只记下最后一次速度，衰减交给 ticker ——
      // 外面每帧都会重建，这里不能把它当成「新的采样」一直续命。
      _vx = widget.velocity.dx;
      _vy = widget.velocity.dy;
    }
    _retargetRing();
    _syncTicker();
  }

  /// 还有东西在动就推帧，全静止就**把 ticker 停掉**。
  ///
  /// ⚠️ 日历页吃过大亏（v0.9.8）：常驻动画让帧队列永远非空，整套 widget 测试在
  /// `pumpAndSettle` 上集体超时。停的条件要把**参与动画的每一个量**都列上。
  void _syncTicker() {
    final bool busy =
        !_lift.isAtRest || !_ring.isAtRest || _vx.abs() > 1 || _vy.abs() > 1;
    if (busy) {
      if (_ticker == null) {
        _lastStamp = Duration.zero;
        _ticker = createTicker(_onTick)..start();
      }
    } else {
      _ticker?.dispose();
      _ticker = null;
    }
  }

  void _onTick(Duration elapsed) {
    // 第一帧（或 ticker 被重建之后的第一帧）没有上一帧可比 —— 按**一帧 60Hz** 算。
    // 用 `LiquidLensSpring.maxStep` 而不是写个 `Duration(milliseconds: 16)`：
    // 那正是同一个量（积分步长的上限就是按一帧 60Hz 取的），而且界面层不许写时长
    // 字面量（`design_tokens_test` 守着）。
    Duration dt = _lastStamp == Duration.zero
        ? LiquidLensSpring.maxStep
        : elapsed - _lastStamp;
    if (dt <= Duration.zero) dt = LiquidLensSpring.maxStep;
    _lastStamp = elapsed;

    _lift.step(dt);
    _ring.step(dt);
    if (!widget.dragging) {
      _vx *= 0.72;
      _vy *= 0.72;
      // 速度衰减到门以下时环开始熄灭（熄灭那条比亮起慢得多，见 [_retargetRing]）。
      _retargetRing();
    }
    if (mounted) setState(() {});
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LiquidLensShape shape = LiquidLensShape.of(
      itemW: widget.size.width - 2 * AppTokens.gapHair,
      capsuleH: widget.size.height,
      pad: AppTokens.gapHair,
      centerPage: 0,
      lift: _lift.value,
      // 只有 `movingRight` 读它（胶囊那两条分支用的），圆角方那支不看方向 ——
      // 传进去是为了「这一帧确实在往哪边走」这件事在形状里留个记录。
      velocity: _vx,
      // 二维：按速度分量各拉各的（横着拖拉宽压矮、竖着拖拉高收窄）。
      stretch: (_vx.abs() / CalendarLens.velocityRef).clamp(0.0, 1.0),
      stretchY: (_vy.abs() / CalendarLens.velocityRef).clamp(0.0, 1.0),
      motion: _ring.value.clamp(0.0, 1.0),
      metrics: LiquidLensMetrics(
        protrude: CalendarLens.protrude,
        liftWidth: CalendarLens.liftWidth,
        rimScale: widget.size.height / AppTokens.lensRimRefCapsuleH,
        velocityRef: CalendarLens.velocityRef,
      ),
      cornerR: AppTokens.radiusM,
    );

    return SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: Stack(
        // 透镜要能画到格子外面去（按住时四面都鼓出去）。
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: LiquidLens(
              size: widget.size,
              shape: shape,
              lift: _lift.value,
              isDark: widget.isDark,
              accent: widget.accent,
              // 本体填充**不能用默认那档**（0.85 → 0.50）：它会把选中那格的
              // 实心班次胶囊洗掉色相（橙会洗成棕）。这一道是极淡的斜向渐变，
              // 与标准档那层平 14% 的浓度同量级（实测胶囊中心差 3~5/255）。
              fill: <Color>[
                widget.accent.withValues(alpha: 0.22),
                widget.accent.withValues(alpha: 0.10),
              ],
              // 日历没有「胶囊的边」可折 —— 折边在方形格子上不成立（规格 §9）。
              showRefractedEdge: false,
            ),
          ),
          // 2px 主色描边：与标准档那枚块同一个识别符号（「这一天被选中」）。
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _LensStrokePainter(shape: shape, color: widget.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 压在透镜轮廓上的那圈 2px 主色描边。
///
/// 坐标与 `LiquidLensShape` 同一套（原点 = 格子盒的左上角）—— **不要再 shift**
/// `LiquidLens` 内部那 24px 的画布余量是它自己的事，这一层是格子盒里的一层。
class _LensStrokePainter extends CustomPainter {
  const _LensStrokePainter({required this.shape, required this.color});

  final LiquidLensShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      shape.toPath(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_LensStrokePainter old) =>
      old.color != color ||
      old.shape.centerX != shape.centerX ||
      old.shape.width != shape.width ||
      old.shape.height != shape.height;
}
