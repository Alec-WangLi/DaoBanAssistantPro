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

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/glass/liquid_lens_controller.dart';
import '../../core/glass/liquid_lens_metrics.dart';
import '../../core/layout.dart';
import '../../core/motion.dart';
import '../../core/widgets/lens_warped_cell.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/liquid_track.dart';

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

  int _committedIndex = 0; // 已提交（正在显示）的功能区

  /// 上一帧那三个**标准档那棵树也要读**的量，用来决定要不要重建。
  ///
  /// ⚠️ **一个都不能漏**：控制器每帧都会通知，而标准档读 `pressed`（QScale 的按下
  /// 放大）、`page`（高亮块位置）、`previewIndex`（选中项）。只盯 `page` 的话，
  /// 「点按被取消 → pressed 变 false」就不重建 —— 胶囊会一直大着 6%。
  /// 既有护栏 `glass_tier_test.dart` 的「点按被取消之后不再算按住」抓的就是它。
  double _lastPage = 0;
  bool _lastPressed = false;
  int? _lastPreview;

  /// 本控件正在自己驱动页面（`_release` 里那段翻页动画）。
  ///
  /// 用来把「手势翻页」和「外部程序化切页」分开：动画期间控制器会持续上报
  /// 中间位置，若照单全收，滑块会跟着动画往回滑一下再过去，与「松手即吸附」
  /// 的既有手感打架。
  bool _drivingPage = false;

  /// 液态档的全部动画状态：四条弹簧、速度、ticker、手势。
  ///
  /// **状态机两档共用** —— 标准档那棵树也读它（`pressed` 决定 QScale 的按下放大、
  /// `page` 决定高亮块位置、`previewIndex` 决定哪一格是选中态）。于是两档的交互
  /// 契约天然一字不差：它们本来就出自同一份代码。
  ///
  /// 它自己**不读档位** —— 判据只在这里读，这正是本仓那条纪律（`liquidGlassActive`
  /// 只许出现在定义处与调用点）。
  late final LiquidLensController _lens;

  PageController get controller => widget.controller;
  List<(IconData, String)> get items => widget.items;

  @override
  void initState() {
    super.initState();
    _committedIndex = controller.initialPage;
    _lastPage = _committedIndex.toDouble();
    _lens = LiquidLensController(
      slots: widget.items.length,
      pad: _innerPad,
      liftWidth: AppTokens.lensLiftWidth,
      vsync: this,
      initialSlot: _committedIndex,
    );
    _lens.addListener(_onLensChanged);
    // 外部程序化切页（点了待办提醒的通知 → 跳到待办页）不经过这里的手势处理，
    // 所以还要听控制器：不听的话页面已经翻过去了、底部高亮还停在原来那一格。
    controller.addListener(_syncFromController);
  }

  @override
  void dispose() {
    controller.removeListener(_syncFromController);
    _lens.removeListener(_onLensChanged);
    // 控制器自己收它的 `Timer` 与 `Ticker` —— 留着的话 widget 测试会报
    // 「A Timer is still pending」或者 `pumpAndSettle` 永远等不到停。
    _lens.dispose();
    super.dispose();
  }

  /// 逻辑页变了就重建一次 —— 标准档那棵树要靠它定位高亮块。
  ///
  /// **只在真的变了的时候重建**：控制器每帧都会通知（四条弹簧各自在动），而这里
  /// 关心的是「该在哪一格」，不是「弹簧走到哪了」。
  void _onLensChanged() {
    if (_lens.page == _lastPage &&
        _lens.pressed == _lastPressed &&
        _lens.previewIndex == _lastPreview) {
      return;
    }
    _lastPage = _lens.page;
    _lastPressed = _lens.pressed;
    _lastPreview = _lens.previewIndex;
    if (mounted) setState(() {});
  }

  /// 页面被外部改了就跟着对齐高亮。自己驱动的动画不上报（见 [_drivingPage]）。
  void _syncFromController() {
    if (_drivingPage || !controller.hasClients) return;
    final page = controller.page;
    if (page == null) return;
    final i = page.round();
    if (i == _committedIndex && (page - _lastPage).abs() < 0.001) return;
    setState(() {
      _committedIndex = i;
      _lastPage = page;
    });
    // **透镜也要跟着走。** 它的位置是弹簧算的，而这里刚把逻辑页改了 —— 不把它的
    // 目标挪过去、也不把 ticker 拉起来（那时它多半已经停了），透镜就会**永远停在
    // 原来那一格**：页面翻过去了、滑块还在旧地方。标准档那条路有
    // `AnimatedPositioned` 替它演，这一档没有，所以必须显式接上。
    _lens.snapTo(page + 0.5);
  }

  // ── 手势：全部转发给控制器 ───────────────────────────────────────────────
  //
  // **两档共用同一份** —— 于是「点按即切页 / 长按吸附不切页 / 松手才提交」这份交互
  // 契约两档一字不差：它本来就出自同一份代码。

  void _press(double dx, double itemW) {
    _lens.setItemW(itemW);
    _lens.press(dx);
  }

  void _dragStart(double dx, double itemW) {
    _lens.setItemW(itemW);
    _lens.dragStart(dx);
  }

  void _dragUpdate(double dx, double itemW) {
    _lens.setItemW(itemW);
    _lens.dragUpdate(dx);
  }

  // 松手：吸附到最近功能区并切换页面
  void _release() {
    final int target = _lens.release();
    setState(() => _committedIndex = target);
    if (controller.hasClients) {
      _drivingPage = true;
      controller
          .animateToPage(target,
              duration: AppTokens.durMed, curve: Curves.easeOutCubic)
          .whenComplete(() => _drivingPage = false);
    }
  }

  /// 点按被取消（在胶囊上按下之后竖直滑走之类）→ **当作没点过**。
  ///
  /// **这是一个既有缺陷的修复**：`onTapCancel` 原来是个**空回调**，于是按下态会永远
  /// 卡在 true —— 标准档下只是胶囊一直大 6%（大概没人注意过），液态档下就是**透镜
  /// 永远提着凸在胶囊外面**，一眼可见。
  ///
  /// **这一轮又补了一半**：光取消「按住」还不够 —— `press()` 已经把滴挪到手指那一格
  /// 了，而页面并没有切，于是滑块**定格在那一格**（用户 2026-10-01 报的正是它）。
  /// 所以真的取消时把滴送回**已提交的那一格**。
  /// （不能复用 [_cancel]：那个有个「没在拖就早退」的闸门。）
  ///
  /// ⚠️ **回退不能立刻做，要推到下一个微任务。** 点按被**拖动**挤出竞技场时，SDK 的
  /// 顺序是 `GestureArenaManager._resolveInFavorOf` **先逐个 reject、再 accept 赢家**
  /// —— 于是 `onTapCancel` 跑在 `onHorizontalDragStart` **之前**。立刻回退会把 `_page`
  /// 改掉，紧接着 `dragStart` 就按错的 `_page` 算抓取偏移，滴整枚跳到当前格去、
  /// 松手提交的也是错的格子。**底栏尤其致命：它没有竖直方向的竞争者，**
  /// **`onTapCancel` 只可能从拖动这条路走到**（`glass_tier_test` 里那条「点按被取消」
  /// 的用例注释记着这件事）。
  ///
  /// 推一个微任务之后再判一次：那时若已经拖起来（`dragging`），就不该回退。
  void _onTapCancel() {
    if (!_lens.tapCancel()) return;
    scheduleMicrotask(() {
      if (!mounted || _lens.dragging) return;
      _lens.snapTo(_committedIndex + 0.5);
    });
  }

  // 取消：仅当真正处于拖动中才回退（点按结束触发的 onCancel 不回退）
  void _cancel() {
    if (_lens.cancel()) _lens.snapTo(_committedIndex + 0.5);
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
    final selectedIndex = _lens.previewIndex ?? _committedIndex;

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
      pressed: _lens.pressed,
      scale: AppTokens.pillGrow,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: outerPad),
          child: TweenAnimationBuilder<double>(
            // 位置：拖动中零时长跟手。
            tween: Tween<double>(begin: 0, end: _lens.page),
            duration: _lens.dragging ? Duration.zero : AppTokens.durFast,
            curve: Curves.easeOutCubic,
            builder: (context, page, _) => TweenAnimationBuilder<double>(
              // 鼓起：与那张 `AnimatedScale` 同一套（durMed / easeOutBack）。
              tween: Tween<double>(begin: 0, end: _lens.pressed ? 1.0 : 0.0),
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
                                  duration: _lens.dragging
                                      ? Duration.zero
                                      : AppTokens.durFast,
                                  curve: Curves.easeOutCubic,
                                  left: _lens.page * itemW,
                                  top: 0,
                                  bottom: 0,
                                  width: itemW,
                                  child: AnimatedScale(
                                    scale: _lens.pressed ? 1.22 : 1.0,
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
      pressed: _lens.pressed,
      scale: AppTokens.pillGrow,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: outerPad),
          child: LiquidTrack(
            slots: items.length,
            capsuleH: capsuleH,
            pad: _innerPad,
            controller: _lens,
            // ⚠️ **写死 10 / 10，两个高度都用它。** 别改成
            // `LiquidLensMetrics.forCapsule(capsuleH)` —— 矮屏那一档胶囊是 52 高，
            // 跟着取会变成 8.1，横屏（900×420）与小窗两档的画面就变了，而
            // 「底栏逐像素不变」是抽这一层共享件的验收。
            metrics: const LiquidLensMetrics(
              protrude: AppTokens.navLensProtrude,
              liftWidth: AppTokens.lensLiftWidth,
            ),
            contentBuilder: (BuildContext context, double itemW) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _press(d.localPosition.dx, itemW),
              onTapUp: (_) => _release(),
              onTapCancel: _onTapCancel,
              onHorizontalDragStart: (d) => _dragStart(d.localPosition.dx, itemW),
              onHorizontalDragUpdate: (d) =>
                  _dragUpdate(d.localPosition.dx, itemW),
              onHorizontalDragEnd: (_) => _release(),
              onHorizontalDragCancel: _cancel,
              // 图标扭曲是**这一页特有**的（4 个 tab 的图标 + 文字被边缘挤），
              // 所以它留在调用点，不进共享件。
              child: _iconsRow(isShort, fg, inactiveColor, selectedIndex,
                  lensItemW: itemW, lensPad: _innerPad),
            ),
          ),
        ),
      ),
    );
  }

  /// 图标 + 文字那一行。**两棵树共用同一份** —— 它在两档里本来就该一模一样，
  /// 各写一份迟早会长出差异。
  ///
  /// [lensItemW] 给值时 = 液态档：每一格按**透镜边缘**的位置做一次仿射变换
  /// （用户 2026-10-01：「滑块的彩虹边缘碰到图标时，图标和文字也应该适当扭曲」）。
  /// 标准档传 null，**一个变换都不套**（也就不会多出一层 widget）。
  ///
  /// 那层变换的实现在 [LensWarpedCell]（v0.10.10 抽出去给分段器共用）。
  Widget _iconsRow(
    bool isShort,
    Color fg,
    Color inactiveColor,
    int selectedIndex, {
    double? lensItemW,
    double lensPad = 0,
  }) {
    return Row(
      children: List.generate(items.length, (i) {
        final selected = i == selectedIndex;
        final Widget cell = Column(
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
        );
        final double? itemW = lensItemW;
        if (itemW == null) return Expanded(child: cell);

        return Expanded(
          child: LensWarpedCell(
            controller: _lens,
            // 底栏的格子是**内缩之后**排的，所以中心要加上 `lensPad` ——
            // 与 `LiquidLensShape` 用的是同一套坐标（都从胶囊左缘量起）。
            // （分段器那一边的格子铺满全宽，它报的是 `(i+0.5)×内容宽÷格数`。）
            iconCenterX: lensPad + (i + 0.5) * itemW,
            lensPad: lensPad,
            itemW: itemW,
            // 半宽用**底栏冻结的** `lensLiftWidth`（10），不是 `forCapsule` 的值 ——
            // 矮屏那一档胶囊 52 高，跟着取会改到横屏与小窗的画面。
            halfWidth: (itemW + AppTokens.lensLiftWidth) / 2,
            child: cell,
          ),
        );
      }),
    );
  }
}
