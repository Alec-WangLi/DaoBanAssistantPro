// app/lib/features/home/glass_nav_bar.dart
//
// 底部导航的悬浮玻璃胶囊。
//
// 从 `home_shell.dart` 抽出来的（v0.10.3）：液态档那一半还要再进来两百多行，
// 而底栏是**唯一**两个档位渲染不同的地方 —— 抽出来之后「两棵树」并排待在一个
// 文件里，读的人一眼就能看出标准档与液态档各自长什么样。
//
// 这次抽取是**纯搬移**，行为一字不变（验收是工装出图逐像素相同）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/glass/liquid_lens.dart';
import '../../core/layout.dart';
import '../../core/motion.dart';
import '../../core/widgets/app_icon.dart';

/// 悬浮液态玻璃胶囊导航：点击切整数 tab，拖拽跟手、松手停在手指位置。
class GlassNavBar extends StatefulWidget {
  const GlassNavBar({
    super.key,
    required this.controller,
    required this.items,
  });

  final PageController controller;
  final List<(IconData, String)> items;

  @override
  State<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<GlassNavBar>
    with SingleTickerProviderStateMixin {
  static const _outerPad = 24.0;
  static const _innerPad = AppTokens.gapIconText;
  static const _capsuleHeight = 64.0;

  /// 短屏（可用高 < 480）用的紧凑尺寸：横屏下 64 高的胶囊约占可用高度的
  /// 六分之一，而它悬浮在内容之上，太占地方。
  static const _capsuleHeightShort = 52.0;
  static const _outerPadShort = 16.0;

  bool _pressed = false;
  bool _dragging = false; // 是否处于拖动中（区别于点按，取消时据此决定是否回退）
  int _committedIndex = 0; // 已提交（正在显示）的功能区
  int? _previewIndex; // 按下/拖动时预览的功能区（松手才提交）
  double _visualPage = 0; // 滑块左缘位置（以功能区宽度为单位，可为小数）
  double _grabOffset = 0; // 手指相对滑块左缘的抓取偏移（跟手不跳的关键）

  /// 本控件正在自己驱动页面（`_release` 里那段翻页动画）。
  ///
  /// 用来把「手势翻页」和「外部程序化切页」分开：动画期间控制器会持续上报
  /// 中间位置，若照单全收，滑块会跟着动画往回滑一下再过去，与「松手即吸附」
  /// 的既有手感打架。
  bool _drivingPage = false;

  // ── 液态档：透镜 ─────────────────────────────────────────────────────────
  //
  // 透镜由**两个弹簧**驱动，而不是补间动画 —— 买的是速度（拖动时形状要跟着它
  // 拉伸）和过冲（落回格子那一下的 Q 弹）。见 `core/glass/liquid_lens.dart`。

  /// 透镜**中心**的位置，单位是「格」（静止时 = 格号 + 0.5）。
  late final LiquidLensSpring _posSpring;

  /// 升程 0..1。它同时管三件事：放大、凸出胶囊、以及「跟不跟手」。
  late final LiquidLensSpring _liftSpring;

  /// 升程的**目标**：按住够久、或者已经在拖，才提起。
  ///
  /// 这一条是**交互契约**的一部分（用户 2026-10-01）：点一下只是「滑块自动过来
  /// 然后切页」，**不提起**；按住才吸附到手上。凸出胶囊因此成了「按住」的专属信号。
  double get _liftTarget => (_dragging || _heldLongEnough) ? 1.0 : 0.0;

  /// 手指在**内层（已扣 `_innerPad`）坐标**里的 x。升程起来之后透镜朝它走。
  ///
  /// 存内层坐标而不是画布坐标：手势回调本来就给的是内层坐标，换算成画布坐标
  /// 要多加一个 `_innerPad`，而那个数在渲染时才拿得到 —— 存错了量纲的症状是
  /// 「透镜整体偏一格的边距」，很不好查。
  double _fingerInnerX = 0;

  /// 按住超过 `AppTokens.lensHoldDelay` 之后为真。
  bool _heldLongEnough = false;
  Timer? _holdTimer;

  Ticker? _ticker;
  Duration? _lastTick;

  /// 每一格多宽（px）。形变要的速度是 px/s，而弹簧的位置以「格」为单位。
  double _itemW = 1;

  /// 透镜中心上一帧的位置（格），用来算真实速度。
  double _lastLensCenter = 0;

  /// 透镜当前的形变速度（px/s），带了低通 —— 原始帧间差分抖得厉害。
  double _lensVelocityPx = 0;

  PageController get controller => widget.controller;
  List<(IconData, String)> get items => widget.items;

  @override
  void initState() {
    super.initState();
    _committedIndex = controller.initialPage;
    _visualPage = _committedIndex.toDouble();
    _posSpring = LiquidLensSpring(
      target: _committedIndex + 0.5,
      value: _committedIndex + 0.5,
    );
    _liftSpring = LiquidLensSpring(target: 0);
    _ticker = createTicker(_onTick);
    // 外部程序化切页（点了待办提醒的通知 → 跳到待办页）不经过这里的手势处理，
    // 所以还要听控制器：不听的话页面已经翻过去了、底部高亮还停在原来那一格。
    controller.addListener(_syncFromController);
  }

  @override
  void dispose() {
    controller.removeListener(_syncFromController);
    // 两个都**必须**收掉：`Timer` 留着会让 widget 测试报
    // 「A Timer is still pending even after the widget tree was disposed」，
    // 而 `Ticker` 留着会一直调度下一帧（`pumpAndSettle` 永远等不到停）。
    _holdTimer?.cancel();
    _ticker?.dispose();
    super.dispose();
  }

  /// 只在**真的还在动**的时候推帧。
  ///
  /// 这一条是硬要求，不是优化：一个常驻的 `Ticker` 会让帧队列永远非空，
  /// 整个 widget 测试套件都会在 `pumpAndSettle` 上超时（v0.9.8 的日历背景光晕
  /// 就是这么一次红 46 条）。
  void _syncTicker() {
    final bool needed =
        _pressed || !_posSpring.isAtRest || !_liftSpring.isAtRest;
    final Ticker? t = _ticker;
    if (t == null) return;
    if (needed) {
      if (!t.isActive) {
        _lastTick = null;
        t.start();
      }
    } else if (t.isActive) {
      t.stop();
    }
  }

  void _onTick(Duration elapsed) {
    // 第一帧没有上一帧可比 —— 按「一帧」算。用 `lensMaxStep` 而不是另写一个
    // 字面量：它本来就是「一步最多积分多久」，语义正好，也过得了令牌守门
    // （`lib/features/home/` 在扫描范围内，时长字面量会打红）。
    final Duration dt =
        _lastTick == null ? AppTokens.lensMaxStep : elapsed - _lastTick!;
    _lastTick = elapsed;

    _liftSpring.target = _liftTarget;
    _liftSpring.step(dt);

    if (!_dragging) {
      // 位置的目标 = **该去的那一格**，只有升程起来之后才掺进手指的位置。
      // 于是点按换页时透镜照样「滑过去」（标准档今天就是这个行为），只是不提起。
      //
      // ⚠️ **这里一律是「中心」，不是「左缘」。** `_posSpring.value` 存的是透镜
      // **中心**（静止时 = 格号 + 0.5），而 `_visualPage` 是**左缘** —— 两套混了
      // 一个 0.5，弹簧会把透镜一路拽到胶囊最左边（实测：透镜整枚偏出胶囊左端
      // 约 45px）。手指那一侧同理：透镜中心落到手指上 ⇔ `value = 内层x / itemW`。
      final double slotCenter = _visualPage + 0.5;
      final double fingerCenter = _fingerInnerX / _itemW;
      final double t = _liftSpring.value.clamp(0.0, 1.0);
      _posSpring.target = _clampLensCenter(
          slotCenter + (fingerCenter - slotCenter) * t);
      _posSpring.step(dt);
    }

    // 速度取**位置的真实帧间差分**，不是弹簧自己的 `velocity`：拖动时弹簧压根
    // 没参与（位置是 1:1 给的），它自己的速度恒为 0，形变就永远不会发生。
    final double seconds = dt.inMicroseconds / 1e6;
    final double raw = seconds <= 0
        ? 0
        : (_posSpring.value - _lastLensCenter) * _itemW / seconds;
    _lensVelocityPx = _lensVelocityPx * 0.6 + raw * 0.4;
    _lastLensCenter = _posSpring.value;

    if (!_pressed && _posSpring.isAtRest && _liftSpring.isAtRest) {
      _ticker?.stop();
      _lensVelocityPx = 0;
    }
    if (mounted) setState(() {});
  }

  /// 把透镜的**中心**夹在胶囊的横向范围内。
  ///
  /// 纵向凸出是设计（那是「提起」的信号），**横向不是** —— 按下靠左/靠右时透镜会顶出
  /// 胶囊两端、被屏幕切掉一截，读起来像 bug 而不像液体。iOS 那颗选中胶囊同样永远
  /// 在栏内。
  ///
  /// 夹紧量用**满升程**的宽度算：跟着当前升程算的话，按下的过程中夹紧量自己会变，
  /// 观感像被谁推了一下。
  double _clampLensCenter(double v) {
    final double half = (_itemW + AppTokens.lensLiftWidth) / 2;
    final double capsuleW = _itemW * items.length + 2 * _innerPad;
    final double minV = (half - _innerPad) / _itemW;
    final double maxV = (capsuleW - half - _innerPad) / _itemW;
    if (minV > maxV) return v; // 胶囊太窄（小窗），夹不了 —— 那就别夹
    if (v < minV) return minV;
    if (v > maxV) return maxV;
    return v;
  }

  void _armHoldTimer() {
    _holdTimer?.cancel();
    _holdTimer = Timer(AppTokens.lensHoldDelay, () {
      if (!mounted) return;
      _heldLongEnough = true;
      _syncTicker();
    });
  }

  void _endHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _heldLongEnough = false;
  }

  /// 页面被外部改了就跟着对齐高亮。自己驱动的动画不上报（见 [_drivingPage]）。
  void _syncFromController() {
    if (_drivingPage || !controller.hasClients) return;
    final page = controller.page;
    if (page == null) return;
    final i = page.round();
    if (i == _committedIndex && (page - _visualPage).abs() < 0.001) return;
    setState(() {
      _committedIndex = i;
      _visualPage = page;
      _previewIndex = null;
    });
    // **透镜也要跟着走。** 它的位置是弹簧算的，而这里刚把 `_visualPage` 改了 ——
    // 不改弹簧的目标、也不把 Ticker 拉起来（那时它多半已经停了），透镜就会
    // **永远停在原来那一格**：页面翻过去了、滑块还在旧地方。
    // 标准档那条路有 `AnimatedPositioned` 替它演，这一档没有，所以必须显式接上。
    _posSpring.target = page + 0.5;
    _syncTicker();
  }

  int _indexForDx(double dx, double itemW) {
    var i = (dx / itemW).floor();
    if (i < 0) i = 0;
    if (i > items.length - 1) i = items.length - 1;
    return i;
  }

  double _clampPage(double p) {
    if (p < 0) p = 0;
    if (p > items.length - 1) p = (items.length - 1).toDouble();
    return p;
  }

  int _nearestIndex(double p) {
    var i = p.round();
    if (i < 0) i = 0;
    if (i > items.length - 1) i = items.length - 1;
    return i;
  }

  // 点按落下：吸附到手指所在的功能区（整格）
  void _press(double dx, double itemW) {
    final i = _indexForDx(dx, itemW);
    _fingerInnerX = dx;
    _itemW = itemW;
    _armHoldTimer();
    setState(() {
      _pressed = true;
      _previewIndex = i;
      _visualPage = i.toDouble();
    });
    _posSpring.target = i + 0.5;
    _syncTicker();
  }

  // 拖动开始：记录抓取偏移，切换到连续跟手（不跳）
  void _dragStart(double dx, double itemW) {
    _grabOffset = dx / itemW - _visualPage;
    _dragUpdate(dx, itemW);
  }

  // 拖动中：1:1 跟手（连续小数位置），高亮跟随最近功能区
  void _dragUpdate(double dx, double itemW) {
    final p = _clampPage(dx / itemW - _grabOffset);
    _fingerInnerX = dx;
    _itemW = itemW;
    setState(() {
      _pressed = true;
      _dragging = true;
      _previewIndex = _nearestIndex(p);
      _visualPage = p;
    });
    // 拖动是 **1:1 跟手**：位置直接给，弹簧不插一脚 —— 让它插就会拖出一条
    // 橡皮筋尾巴，而「跟手」正是用户要的那种「吸附在手上」。
    _posSpring.value = _clampLensCenter(p + 0.5);
    _syncTicker();
  }

  // 松手：吸附到最近功能区并切换页面
  void _release() {
    final target = _nearestIndex(_visualPage);
    _endHold();
    _posSpring.target = target + 0.5;
    _syncTicker();
    setState(() {
      _pressed = false;
      _dragging = false;
      _previewIndex = null;
      _committedIndex = target;
      _visualPage = target.toDouble();
    });
    if (controller.hasClients) {
      _drivingPage = true;
      controller
          .animateToPage(
        target,
        duration: AppTokens.durMed,
        curve: Curves.easeOutCubic,
      )
          .whenComplete(() => _drivingPage = false);
    }
  }

  /// 点按被取消（在胶囊上按下之后竖直滑走之类）。
  ///
  /// **这是一个既有缺陷的修复**：`onTapCancel` 原来是个**空回调**，于是
  /// `_pressed` 会永远卡在 true —— 标准档下只是胶囊一直大 6%（大概没人注意过），
  /// 液态档下就是**透镜永远提着凸在胶囊外面**，一眼可见。
  ///
  /// 不能复用 [_cancel]：那个有个 `if (!_dragging) return;` 的早退（它是给
  /// 「拖动取消」用的，点按结束触发的 cancel 不该回退页面）。
  void _onTapCancel() {
    _endHold();
    if (!_dragging) {
      setState(() => _pressed = false);
    } else {
      _cancel();
    }
    _syncTicker();
  }

  // 取消：仅当真正处于拖动中才回退（点按结束触发的 onCancel 不回退）
  void _cancel() {
    if (!_dragging) return;
    _endHold();
    _posSpring.target = _committedIndex + 0.5;
    _syncTicker();
    setState(() {
      _pressed = false;
      _dragging = false;
      _previewIndex = null;
      _visualPage = _committedIndex.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isShort = AppLayout.of(context).isShort;
    final capsuleH = isShort ? _capsuleHeightShort : _capsuleHeight;
    final outerPad = isShort ? _outerPadShort : _outerPad;
    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor =
        AppTokens.navInactiveForeground(context, isDark: isDark);
    final fg = AppTokens.navForeground(isDark, activeColor); // 滑块上选中项前景
    final selectedIndex = _previewIndex ?? _committedIndex;

    // **两棵树，不是一棵树上的两处开关。**
    //
    // 标准档那一段（`_buildStandard`）就是 v0.10.2 那段代码原样搬进来的 —— 于是
    // 用户那条硬性要求「关掉液态玻璃不能影响磨砂玻璃」从「比对后证明」变成
    // **结构上不可能**。两条路各自一套，不互相打补丁。
    //
    // 手势与动画状态机两档**共用**（上面那一段），所以交互契约（点按即切页 /
    // 长按吸附不切页 / 松手才提交）两档一字不差 —— 交互由同一份代码产生，
    // 就不可能不一致。
    return ValueListenableBuilder<bool>(
      valueListenable: liquidGlassActive,
      builder: (BuildContext context, bool liquid, Widget? _) => liquid
          ? _buildLiquid(
              isDark: isDark,
              isShort: isShort,
              capsuleH: capsuleH,
              outerPad: outerPad,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              fg: fg,
              selectedIndex: selectedIndex,
            )
          : _buildStandard(
              isDark: isDark,
              isShort: isShort,
              capsuleH: capsuleH,
              outerPad: outerPad,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              fg: fg,
              selectedIndex: selectedIndex,
            ),
    );
  }

  /// **标准档**：今天那棵树。
  ///
  /// 别在这里顺手改东西 —— 它的「不变」就是这一版对用户那条硬性要求的回答。
  /// 唯一的改动是 `onTapCancel` 从空回调换成 [_onTapCancel]（顺手修一个既有缺陷，
  /// 见那边的说明）—— 它不影响任何静止帧，工装的逐像素比对证过。
  Widget _buildStandard({
    required bool isDark,
    required bool isShort,
    required double capsuleH,
    required double outerPad,
    required Color activeColor,
    required Color inactiveColor,
    required Color fg,
    required int selectedIndex,
  }) {
    // 胶囊本体：按下轻微放大，松手弹簧回弹
    return QScale(
      pressed: _pressed,
      scale: AppTokens.pillGrow,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: outerPad),
          child: TweenAnimationBuilder<double>(
            // 位置：拖动中零时长跟手。
            tween: Tween<double>(begin: 0, end: _visualPage),
            duration: _dragging ? Duration.zero : AppTokens.durFast,
            curve: Curves.easeOutCubic,
            builder: (context, page, _) => TweenAnimationBuilder<double>(
              // 鼓起：与那张 `AnimatedScale` 同一套（durMed / easeOutBack）。
              tween: Tween<double>(begin: 0, end: _pressed ? 1.0 : 0.0),
              duration: AppTokens.durMed,
              curve: Curves.easeOutBack,
              builder: (context, swell, __) => ClipRRect(
                borderRadius: BorderRadius.circular(capsuleH / 2),
                child: GlassBlur(
                  sigma: AppTokens.blurPanel,
                  child: Container(
                    height: capsuleH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(capsuleH / 2),
                      border: Border.all(color: AppTokens.navBorder(isDark)),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: AppTokens.navFill(isDark),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(_innerPad),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final itemW = c.maxWidth / items.length;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (d) =>
                                _press(d.localPosition.dx, itemW),
                            onTapUp: (_) => _release(),
                            onTapCancel: _onTapCancel,
                            onHorizontalDragStart: (d) =>
                                _dragStart(d.localPosition.dx, itemW),
                            onHorizontalDragUpdate: (d) =>
                                _dragUpdate(d.localPosition.dx, itemW),
                            onHorizontalDragEnd: (_) => _release(),
                            onHorizontalDragCancel: _cancel,
                            child: Stack(
                              children: [
                                // 滑块：平滑吸附到最近功能区，按下放大、松手弹簧回弹
                                AnimatedPositioned(
                                  key: const Key('nav-highlight'),
                                  duration: _dragging
                                      ? Duration.zero
                                      : AppTokens.durFast,
                                  curve: Curves.easeOutCubic,
                                  left: _visualPage * itemW,
                                  top: 0,
                                  bottom: 0,
                                  width: itemW,
                                  child: AnimatedScale(
                                    scale: _pressed ? 1.22 : 1.0,
                                    duration: AppTokens.durMed,
                                    curve: Curves.easeOutBack,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                            AppTokens.radiusL),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: AppTokens
                                              .accentGradient(activeColor)
                                              .colors,
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                              alpha: isDark ? 0.28 : 0.85),
                                        ),
                                        boxShadow: <BoxShadow>[
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.12),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                _iconsRow(isShort, fg, inactiveColor,
                                    selectedIndex),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// **液态档**：三层 —— 胶囊 / 透镜 / 图标。
  ///
  /// 图标放最上是有意的：24px 的小图标被透镜放大扭曲之后既不好看也不好读，而用户
  /// 要的那圈光本来就是「**透过透镜看胶囊**」，不需要动图标。
  Widget _buildLiquid({
    required bool isDark,
    required bool isShort,
    required double capsuleH,
    required double outerPad,
    required Color activeColor,
    required Color inactiveColor,
    required Color fg,
    required int selectedIndex,
  }) {
    return QScale(
      pressed: _pressed,
      scale: AppTokens.pillGrow,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: outerPad),
          child: LayoutBuilder(
            builder: (context, c) {
              final Size capsuleSize = Size(c.maxWidth, capsuleH);
              final double itemW = (c.maxWidth - 2 * _innerPad) / items.length;
              final double lift = _liftSpring.value.clamp(0.0, 1.0);
              final LiquidLensShape shape = LiquidLensShape.of(
                itemW: itemW,
                capsuleH: capsuleH,
                pad: _innerPad,
                // 弹簧存的是**中心**（静止时 = 格号 + 0.5），形状要的是左缘。
                centerPage: _posSpring.value - 0.5,
                lift: lift,
                velocity: _lensVelocityPx,
              );
              return SizedBox(
                height: capsuleH,
                child: Stack(
                  // **必须 Clip.none**：透镜要能画到胶囊外面去。
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    // ① 胶囊：与标准档同一份配方（模糊 + tint + 描边）。
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(capsuleH / 2),
                        child: GlassBlur(
                          sigma: AppTokens.blurPanel,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(capsuleH / 2),
                              border: Border.all(
                                  color: AppTokens.navBorder(isDark)),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: AppTokens.navFill(isDark),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // ①b 边光 + 「光跟随滑块」。
                    //
                    // 放在透镜**之下**是有意的：透镜是浮在胶囊**之上**的一枚玻璃，
                    // 它盖住的那段边光本来就该被它盖住。而亮带打在胶囊那 1px 描边上，
                    // 静止时透镜（高 52）够不到它，所以照旧看得见。
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: CapsuleRimPainter(
                            radius: capsuleH / 2,
                            isDark: isDark,
                            compact: true,
                            sliderIndex: _posSpring.value,
                            tabCount: items.length,
                            trackPad: _innerPad,
                          ),
                        ),
                      ),
                    ),
                    // ② 透镜：会凸出胶囊、会形变、边缘带光谱环。
                    Positioned.fill(
                      child: IgnorePointer(
                        child: LiquidLens(
                          size: capsuleSize,
                          shape: shape,
                          lift: lift,
                          isDark: isDark,
                          accent: activeColor,
                        ),
                      ),
                    ),
                    // ③ 图标 + 手势。
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(_innerPad),
                        child: LayoutBuilder(
                          builder: (context, t) {
                            final double tw = t.maxWidth / items.length;
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (d) => _press(d.localPosition.dx, tw),
                              onTapUp: (_) => _release(),
                              onTapCancel: _onTapCancel,
                              onHorizontalDragStart: (d) =>
                                  _dragStart(d.localPosition.dx, tw),
                              onHorizontalDragUpdate: (d) =>
                                  _dragUpdate(d.localPosition.dx, tw),
                              onHorizontalDragEnd: (_) => _release(),
                              onHorizontalDragCancel: _cancel,
                              child: _iconsRow(
                                  isShort, fg, inactiveColor, selectedIndex),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 图标 + 文字那一行。**两棵树共用同一份** —— 它在两档里本来就该一模一样，
  /// 各写一份迟早会长出差异。
  Widget _iconsRow(
      bool isShort, Color fg, Color inactiveColor, int selectedIndex) {
    return Row(
      children: List.generate(items.length, (i) {
        final selected = i == selectedIndex;
        return Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 导航项图标：常规态归 iconLg（规格 §3.6，出图对比：24 在 64dp
              // 胶囊里站得住、20 偏小）。矮屏 52dp 胶囊的竖向预算更小，回落到
              // iconMd —— 这是原设计（`isShort ? 20 : 22`）「矮屏用小一号图标」
              // 的忠实翻译，属同一角色按布局档位的个别变化：不新增令牌，
              // 也不违背「导航项归 iconLg」。
              AppIcon(
                items[i].$1,
                size: isShort ? AppTokens.iconMd : AppTokens.iconLg,
                color: selected ? fg : inactiveColor,
              ),
              const SizedBox(height: AppTokens.gapHair),
              Text(
                items[i].$2,
                // 迁移前的基线字号是 10（现为 tinyLabel 11/w400）；
                // 未选中 w500、选中 w700，两个分支都由这里显式给字重，按规格走 copyWith。
                style: AppTokens.tinyLabel.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? fg : inactiveColor,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
