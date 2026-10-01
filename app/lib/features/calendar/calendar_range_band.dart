// app/lib/features/calendar/calendar_range_band.dart
//
// 拖选那条**水带**在液态档下的样子：一枚会漫上来、末端会淌过去的玻璃带子。
//
// 它与那枚单格选中块（`calendar_lens.dart`）是同一族的两个件：形状不同（那枚是
// 单凸的圆角方、这枚是多段圆角矩形的并集），而**材质共用一处**（四层光谱 / 浮起阴影
// 全在 `LiquidLens` + `LiquidLensOutline` 那边）。所以这个文件里没有一行绘制代码 ——
// 只有弹簧、几何与那个轮廓适配器。
//
// 它**不读档位**（`liquidGlassActive`）—— 判据只许出现在调用点（`calendar_screen.dart`），
// 与本仓既有纪律一致（`liquid_scope_guard_test` 扫源码守着）。
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/liquid_lens.dart';
import 'range_band.dart';

/// 那条带子的**轮廓**（[LiquidLensOutline] 的第二个实现）。
///
/// 公开，是为了让用例能直接读这一帧的 `tipPos` / `bulge` —— 那两样**没法从路径里
/// 抠出来**（末端一边淌一边鼓，包围盒里两件事叠在一起）。
class RangeBandOutline implements LiquidLensOutline {
  const RangeBandOutline({
    required this.path,
    required this.stamp,
    required this.tipPos,
    required this.bulge,
    required this.motion,
    required this.motionAngleDeg,
    required this.rimScale,
  });

  /// 画布坐标（`origin` 由 `paintPath` 加）里的轮廓。
  final Path path;

  /// 这一帧的**值可比**指纹：段的结构 + 末端位置 + 鼓出量。
  ///
  /// ⚠️ 段列表本身每帧新建，拿它比会永远判「变了」—— 这里只取首尾两段的五个整数，
  /// 那已经覆盖了「段的结构变了没」。
  final Object stamp;

  /// 末端（会动的那一端）在**格**坐标里的连续位置。
  final double tipPos;

  /// 末端这一帧往前鼓出去多少（px）。
  final double bulge;

  @override
  final double motion;

  @override
  final double motionAngleDeg;

  @override
  final double rimScale;

  @override
  Path paintPath(Offset origin) => path.shift(origin);

  /// 水带没有「容器」—— 没有一条 1px 的边可以折进来。
  @override
  ({Path path, double fade})? refractedEdge(Offset origin) => null;

  @override
  Object get outlineStamp => stamp;
}

/// 拖选那一段日子的水带。
///
/// 它只认四个输入 —— **哪几段**（[runs]）、**哪一头会动**（[movingEnd] / [tipCell]）、
/// **在哪儿**（[cellW] / [cellH] / [hPad] / [weekdayH]）、**什么颜色**。其余全关在里面：
/// 升程弹簧、末端弹簧、鼓出弹簧、彩边的门与方向、以及那个只在动的时候才跑的 `Ticker`。
class CalendarRangeBand extends StatefulWidget {
  const CalendarRangeBand({
    super.key,
    required this.size,
    required this.cellW,
    required this.cellH,
    required this.hPad,
    required this.weekdayH,
    required this.runs,
    required this.movingEnd,
    required this.tipCell,
    required this.accent,
    required this.isDark,
  });

  /// 网格盒（带子的坐标就长在这上面：`hPad` / `weekdayH` 是它内部的偏移）。
  final Size size;
  final double cellW;
  final double cellH;
  final double hPad;
  final double weekdayH;

  /// 吸附到格的那几段（`rangeRowRuns` 给的）。
  final List<({int row, int firstCol, int lastCol})> runs;

  /// 会动的是哪一头：`true` = 终点（右）、`false` = 起点（左，往回拖时）。
  final bool movingEnd;

  /// 会动的那一头**吸附到的列**（整数）。连续位置由里面那条弹簧自己算。
  final int tipCell;

  final Color accent;
  final bool isDark;

  /// 按住时**每侧**鼓出多少（px）。与那枚单格块同一个数 —— 同一族的手感。
  static const double protrude = 6;

  /// 末端沿运动方向最多再鼓出去多少（px）。
  static const double maxBulge = 8;

  /// 鼓出饱和的速度门（px/s）。格子宽与那枚块一样，所以取同一个数。
  static const double velocityRef = 400;

  @override
  State<CalendarRangeBand> createState() => _CalendarRangeBandState();
}

class _CalendarRangeBandState extends State<CalendarRangeBand>
    with SingleTickerProviderStateMixin {
  /// 升程：**挂上来就是从 0 涨到 1** —— 那正是「长按那一刻水漫上来」。
  late final LiquidLensSpring _lift;

  /// 末端（会动的那一头）在格坐标里的连续位置。**它淌过去，状态却仍是吸附到格** ——
  /// 触觉那条契约（每进一格响一次）靠的就是整格的状态，这里只负责好看。
  late final LiquidLensSpring _tip;

  /// 鼓出量（px）。目标由末端速度给，但**过一条弹簧**再交给几何 ——
  /// 直接拿速度现推的话，起步那一帧就鼓满（那枚块 v0.10.6 记过同一个坑）。
  late final LiquidLensSpring _bulge;

  /// 彩边那四层的门：**「动不动」，不是「多快」**。
  late final LiquidLensSpring _ring;

  /// 末端的水平速度（px/s，带符号）—— 帧间差分 ÷ 真实帧间隔（`lensVelocityStep`）。
  double _vx = 0;

  /// 会动的那一头**在哪一行**。它一变就说明区间跨行了 —— 那时末端要**直接跳过去、
  /// 不许淌**：跨行在月历里不是相邻格（从最右列到下一行最左列），让它淌过去会看到
  /// 末端横扫一整行。
  int _tipRow = 0;

  /// 光谱环／光晕的亮峰锚在哪个方位（度）。见 `LiquidLensOutline.motionAngleDeg`。
  double _motionAngle = spectralSweepRestAnchor;

  Ticker? _ticker;
  Duration _lastStamp = Duration.zero;

  int get _targetTipRow =>
      widget.movingEnd ? widget.runs.last.row : widget.runs.first.row;

  @override
  void initState() {
    super.initState();
    _lift = LiquidLensSpring(
        target: 1,
        value: 0,
        omega: AppTokens.lensLiftOmega,
        zeta: AppTokens.lensLiftZeta);
    _tip = LiquidLensSpring(
        target: widget.tipCell.toDouble(),
        value: widget.tipCell.toDouble(),
        omega: AppTokens.lensSlideOmega,
        zeta: AppTokens.lensSlideZeta);
    _bulge = LiquidLensSpring(
        target: 0,
        omega: AppTokens.lensStretchOmega,
        zeta: AppTokens.lensStretchZeta);
    _ring = LiquidLensSpring(
        target: 0,
        omega: AppTokens.lensUnlitOmega,
        zeta: AppTokens.lensUnlitZeta);
    _tipRow = _targetTipRow;
    _syncTicker();
  }

  @override
  void didUpdateWidget(CalendarRangeBand old) {
    super.didUpdateWidget(old);
    // 跨行了：末端**直接跳过去**（见 `_tipRow` 的说明），速度也清掉 —— 那一下不是
    // 「淌」，不该点亮彩边。
    if (_targetTipRow != _tipRow) {
      _tipRow = _targetTipRow;
      _tip.value = widget.tipCell.toDouble();
      _vx = 0;
    }
    // ⚠️ **先把目标刷新，再判「还要不要推帧」** —— `isAtRest` 比的是 `value` 与
    // `target`，而目标原先只在 `_onTick` 里刷新：静止之后再给一个新目标，那一刻
    // `value == target`（都是旧值）→ 判成「已静止」→ ticker 不重启 → **末端一动不动**。
    // 这正是 v0.10.11 在底栏上记过的「升程冻死」，换了个地方再现。
    _retarget();
    _retargetRing();
    _syncTicker();
  }

  /// 把这一帧的**目标**刷进弹簧。`_onTick` 与 `didUpdateWidget` 共用一处 ——
  /// 分成两处写，迟早有一处忘了（上面那条注释就是它的代价）。
  void _retarget() {
    _tip.target = widget.tipCell.toDouble();
  }

  /// 还有东西在动就推帧，全静止就**把 ticker 停掉**。
  ///
  /// ⚠️ 停的条件要把**四条弹簧全列上** —— 漏一条就是「彩边被冻在屏幕上」或者
  /// 「`pumpAndSettle` 再也等不到停」（日历页 v0.9.8 的老账）。
  void _syncTicker() {
    final bool busy = !_lift.isAtRest ||
        !_tip.isAtRest ||
        !_bulge.isAtRest ||
        !_ring.isAtRest;
    if (busy) {
      // ticker 只建一次，之后只 start / stop（`SingleTickerProviderStateMixin`
      // 一个 State 只许 createTicker 一次）。
      _ticker ??= createTicker(_onTick);
      if (!_ticker!.isActive) {
        _lastStamp = Duration.zero;
        _ticker!.start();
      }
    } else {
      _ticker?.stop();
    }
  }

  /// 彩边那几层的门与方向。
  ///
  /// **方向只有 0° / 180°**：末端只在**行内**动（跨行那一下是直接跳的，见 `_tipRow`），
  /// 所以速度永远沿 x。真去 `atan2` 也只是这两个值，不如写清楚。
  void _retargetRing() {
    final bool moving = _vx.abs() > AppTokens.lensRingFullSpeed;
    if (moving) _motionAngle = _vx >= 0 ? 0 : 180;
    _ring
      ..target = moving ? 1 : 0
      ..omega = moving ? AppTokens.lensLitOmega : AppTokens.lensUnlitOmega
      ..zeta = moving ? AppTokens.lensLitZeta : AppTokens.lensUnlitZeta;
  }

  void _onTick(Duration elapsed) {
    Duration dt = _lastStamp == Duration.zero
        ? LiquidLensSpring.maxStep
        : elapsed - _lastStamp;
    if (dt <= Duration.zero) dt = LiquidLensSpring.maxStep;
    _lastStamp = elapsed;

    _lift.step(dt);

    final double before = _tip.value;
    _retarget();
    _tip.step(dt);
    _vx = lensVelocityStep(
        deltaPage: _tip.value - before,
        itemW: widget.cellW,
        dt: dt,
        previous: _vx);

    // 鼓出：目标由速度给，再过一条弹簧（别「啪」地出来）。
    _bulge.target =
        (_vx.abs() / CalendarRangeBand.velocityRef).clamp(0.0, 1.0) *
            CalendarRangeBand.maxBulge;
    _bulge.step(dt);

    _retargetRing();
    _ring.step(dt);

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
    const double inset = AppTokens.gapHair;
    // 末端 = 弹簧的连续位置 + 鼓出（换算成格）。
    final double tipPos =
        _tip.value + _bulge.value / widget.cellW;
    final RangeBandOutline outline = RangeBandOutline(
      path: rangeBandPath(
        runs: widget.runs,
        cellW: widget.cellW,
        cellH: widget.cellH,
        hPad: widget.hPad,
        weekdayH: widget.weekdayH,
        inset: inset,
        endRadius: AppTokens.radiusM,
        movingEnd: widget.movingEnd,
        tipCol: tipPos,
        inflate: CalendarRangeBand.protrude * _lift.value,
      ),
      stamp: (
        widget.runs.length,
        widget.runs.first.row,
        widget.runs.first.firstCol,
        widget.runs.last.row,
        widget.runs.last.lastCol,
        tipPos,
        _bulge.value,
      ),
      tipPos: tipPos,
      bulge: _bulge.value,
      motion: _ring.value.clamp(0.0, 1.0),
      motionAngleDeg: _motionAngle,
      rimScale: (widget.cellH - 2 * inset) / AppTokens.lensRimRefCapsuleH,
    );

    return SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: Stack(
        // 带子要能画到格子外面去（按住时四面都鼓出去）。
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: LiquidLens(
              size: widget.size,
              outline: outline,
              lift: _lift.value,
              isDark: widget.isDark,
              accent: widget.accent,
              // 与那枚单格块同一个配方：极淡的斜向渐变（默认那档 0.85 → 0.50 会把
              // 带子底下那几格的字洗掉）。
              fill: <Color>[
                widget.accent.withValues(alpha: 0.22),
                widget.accent.withValues(alpha: 0.10),
              ],
              // 水带没有「容器的边」可折（见 `RangeBandOutline.refractedEdge`）。
              showRefractedEdge: false,
            ),
          ),
          // 2px 主色描边：与那枚单格块同一个识别符号（「这一段的这些天被选中」）。
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _BandStrokePainter(
                    outline: outline, color: widget.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 压在带子轮廓上的那圈 2px 主色描边（与 `CalendarLens` 的描边同一个写法）。
class _BandStrokePainter extends CustomPainter {
  const _BandStrokePainter({required this.outline, required this.color});

  final RangeBandOutline outline;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      outline.paintPath(Offset.zero),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_BandStrokePainter old) =>
      old.color != color || old.outline.outlineStamp != outline.outlineStamp;
}
