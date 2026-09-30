// app/lib/features/home/glass_nav_bar.dart
//
// 底部导航的悬浮玻璃胶囊。
//
// 从 `home_shell.dart` 抽出来的（v0.10.3）：液态档那一半还要再进来两百多行，
// 而底栏是**唯一**两个档位渲染不同的地方 —— 抽出来之后「两棵树」并排待在一个
// 文件里，读的人一眼就能看出标准档与液态档各自长什么样。
//
// 这次抽取是**纯搬移**，行为一字不变（验收是工装出图逐像素相同）。

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
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

class _GlassNavBarState extends State<GlassNavBar> {
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

  PageController get controller => widget.controller;
  List<(IconData, String)> get items => widget.items;

  @override
  void initState() {
    super.initState();
    _committedIndex = controller.initialPage;
    _visualPage = _committedIndex.toDouble();
    // 外部程序化切页（点了待办提醒的通知 → 跳到待办页）不经过这里的手势处理，
    // 所以还要听控制器：不听的话页面已经翻过去了、底部高亮还停在原来那一格。
    controller.addListener(_syncFromController);
  }

  @override
  void dispose() {
    controller.removeListener(_syncFromController);
    super.dispose();
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
    setState(() {
      _pressed = true;
      _previewIndex = i;
      _visualPage = i.toDouble();
    });
  }

  // 拖动开始：记录抓取偏移，切换到连续跟手（不跳）
  void _dragStart(double dx, double itemW) {
    _grabOffset = dx / itemW - _visualPage;
    _dragUpdate(dx, itemW);
  }

  // 拖动中：1:1 跟手（连续小数位置），高亮跟随最近功能区
  void _dragUpdate(double dx, double itemW) {
    final p = _clampPage(dx / itemW - _grabOffset);
    setState(() {
      _pressed = true;
      _dragging = true;
      _previewIndex = _nearestIndex(p);
      _visualPage = p;
    });
  }

  // 松手：吸附到最近功能区并切换页面
  void _release() {
    final target = _nearestIndex(_visualPage);
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

  // 取消：仅当真正处于拖动中才回退（点按结束触发的 onCancel 不回退）
  void _cancel() {
    if (!_dragging) return;
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
    final inactiveColor = AppTokens.navInactiveForeground(context, isDark: isDark);
    final fg = AppTokens.navForeground(isDark, activeColor); // 滑块上选中项前景
    final selectedIndex = _previewIndex ?? _committedIndex;

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
          // 位置：与标准档那张 `AnimatedPositioned` **同一套时长曲线**（拖动中
          // 零时长跟手）—— 上一版 painter 读的是原始 `_visualPage`，于是标准档
          // 滑过去、液态档瞬移（用户反馈的第 6 条）。
          tween: Tween<double>(begin: 0, end: _visualPage),
          duration: _dragging ? Duration.zero : AppTokens.durFast,
          curve: Curves.easeOutCubic,
          builder: (context, page, _) => TweenAnimationBuilder<double>(
            // 鼓起：与标准档那张 `AnimatedScale` 同一套（durMed / easeOutBack）。
            tween: Tween<double>(begin: 0, end: _pressed ? 1.0 : 0.0),
            duration: AppTokens.durMed,
            curve: Curves.easeOutBack,
            builder: (context, swell, __) => GlassRim(
              radius: capsuleH / 2,
              isDark: isDark,
              // 底栏是小控件，同一圈宽度在这里相对更显眼，单收一档。
              compact: true,
              // 「光跟随滑块」：光源位置 + 轨道几何，交给 painter 按实际尺寸换算。
              // 1.22 与下面那张 AnimatedScale 的按下缩放是同一个值（本仓既有的字面量）。
              sliderIndex: page + 0.5,
              tabCount: items.length,
              trackPad: _innerPad,
              sliderScale: 1 + 0.22 * swell,
              // 探针：透镜凸出胶囊、本体由 GlassRim 画在胶囊之下（见那边的说明）。
              // 凸出量 0 = 不凸，等于原来那个躺在胶囊里的滑块。
              lensFill: activeColor,
              // 凸出量跟着 `swell` 走：**静止时是 0** —— 上一版写死成
              // `AppTokens.navLensProtrude`，于是没按住的时候滑块就比胶囊大
              // （用户 2026-10-01 反馈的第 1 条）。
              lensProtrude: AppTokens.navLensProtrude * swell.clamp(0.0, 1.0),
              child: ClipRRect(
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
                          onTapDown: (d) => _press(d.localPosition.dx, itemW),
                          onTapUp: (_) => _release(),
                          onTapCancel: () {},
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
                                    // 探针下把外观全摘掉 —— 那一档的滑块由 GlassRim 画在
                                    // 胶囊**之下**、并凸出胶囊之外（见那边的说明）。
                                    // 用「摘装饰」而不是「不渲染」：探测脚本靠
                                    // `nav-highlight` 这个 key 找它的位置来起手拖动。
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(AppTokens.radiusL),
                                      gradient: liquidGlassActive.value
                                          ? null
                                          : LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: AppTokens
                                                  .accentGradient(activeColor)
                                                  .colors,
                                            ),
                                      border: liquidGlassActive.value
                                          ? null
                                          : Border.all(
                                              color: Colors.white.withValues(
                                                  alpha: isDark ? 0.28 : 0.85),
                                            ),
                                      boxShadow: liquidGlassActive.value
                                          ? null
                                          : <BoxShadow>[
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
                              Row(
                                children: List.generate(items.length, (i) {
                                  final selected = i == selectedIndex;
                                  return Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // 导航项图标：常规态归 iconLg（规格 §3.6，出图对比：
                                        // 24 在 64dp 胶囊里站得住、20 偏小）。矮屏 52dp
                                        // 胶囊的竖向预算更小，回落到 iconMd —— 这是原设计
                                        // （`isShort ? 20 : 22`）「矮屏用小一号图标」的忠实
                                        // 翻译，属同一角色按布局档位的个别变化：不新增令牌，
                                        // 也不违背「导航项归 iconLg」。
                                        AppIcon(
                                          items[i].$1,
                                          size: isShort
                                              ? AppTokens.iconMd
                                              : AppTokens.iconLg,
                                          color: selected ? fg : inactiveColor,
                                        ),
                                        const SizedBox(height: AppTokens.gapHair),
                                        Text(
                                          items[i].$2,
                                          // 迁移前的基线字号是 10（现为 tinyLabel 11/w400）；
                                          // 未选中 w500、选中 w700，两个分支都由这里显式给字重，按规格走 copyWith。
                                          style: AppTokens.tinyLabel.copyWith(
                                            fontWeight: selected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: selected ? fg : inactiveColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ),
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
      ),
    );
  }
}
