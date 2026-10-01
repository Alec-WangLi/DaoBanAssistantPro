import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../glass/glass.dart';
import '../glass/liquid_lens_controller.dart';
import '../glass/liquid_lens_metrics.dart';
import '../haptics.dart';
import '../motion.dart';
import 'lens_warped_cell.dart';
import 'liquid_track.dart';

/// 胶囊分段选择器：与底部导航滑块同款手感。
///
/// - 按下：滑块吸附到手指所在段；
/// - 拖动：1:1 跟手（带抓取偏移），Q弹放大；
/// - 松手：吸附到最近段并提交 [onSelected]。
///
/// **两条档位两棵树**（与底部导航同一套写法）：关掉液态玻璃时走 [_buildStandard]，
/// 与加这一档之前**逐像素相同**。两棵树读**同一个** [LiquidLensController]，于是
/// 「点按即切 / 长按跟手 / 松手才提交」这份交互契约两档一字不差。
///
/// ## 它和底栏的几何不一样（搬的时候最容易踩）
///
/// 底栏的格子是**内缩之后**排的（`pad + (i+0.5)·itemW`，`itemW = (宽 − 2·pad)/格`）；
/// 分段器的格子**铺满全宽**（`(i+0.5)·(宽/格)`），只有滑块自己内缩 `padChipV`。
/// 所以液态那棵树要传 **`pad: 0`** —— 否则整枚滴会比标准档的滑块偏出一小截
/// （最大宽度 300、3 格时偏 4px），两档来回切会看到高亮**横向跳一下**。
class GlassSegment extends StatefulWidget {
  const GlassSegment({
    super.key,
    required this.count,
    required this.selectedIndex,
    required this.onSelected,
    required this.itemBuilder,
    this.height = 44,
  });

  final int count;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 每个分段的内容（index, 是否选中）。
  final Widget Function(int index, bool selected) itemBuilder;
  final double height;

  @override
  State<GlassSegment> createState() => _GlassSegmentState();
}

class _GlassSegmentState extends State<GlassSegment>
    with SingleTickerProviderStateMixin {
  int _committed = 0;

  /// 上一帧那三个标准档也要读的量，用来决定要不要重建（见 `_onLensChanged`）。
  double _lastPage = 0;
  bool _lastPressed = false;
  int? _lastPreview;

  late final LiquidLensController _lens;

  @override
  void initState() {
    super.initState();
    _committed = widget.selectedIndex;
    _lastPage = _committed.toDouble();
    final LiquidLensMetrics m = LiquidLensMetrics.forCapsule(widget.height);
    _lens = LiquidLensController(
      slots: widget.count,
      // 与 `_buildLiquid` 的几何内缩保持一致（夹紧用它）。
      pad: AppTokens.padChipV,
      liftWidth: m.liftWidth,
      vsync: this,
      initialSlot: _committed,
    );
    _lens.addListener(_onLensChanged);
  }

  @override
  void dispose() {
    _lens.removeListener(_onLensChanged);
    _lens.dispose();
    super.dispose();
  }

  /// 逻辑页 / 按下态 / 选中项任一变了就重建 —— **一个都不能漏**，标准档那棵树三个都读。
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

  @override
  void didUpdateWidget(GlassSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外面改了选中项（不是我们拖出来的）→ 跟着走过去
    if (oldWidget.selectedIndex != widget.selectedIndex && !_lens.dragging) {
      _committed = widget.selectedIndex;
      _lens.snapTo(_committed + 0.5);
    }
  }

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

  void _release() {
    final int target = _lens.release();
    setState(() => _committed = target);
    if (target != widget.selectedIndex) {
      // 只有选中项真的变了才震 —— 拖动回原位、点当前段都不该有反馈。
      Haptics.select();
      widget.onSelected(target);
    }
  }

  /// 点按被取消（按下之后竖直滑走之类）→ **当作没点过**。
  ///
  /// 光取消「按住」不够：`press()` 已经把滴挪到手指那一格了，而选中项并没有变，
  /// 于是滑块**定格在那一格**（用户 2026-10-01 报的「滑块定格」，他说
  /// 「需要再次点击一下滑块，才会恢复正常」）。所以真的取消时把它送回已提交那一格。
  void _onTapCancel() {
    if (_lens.tapCancel()) _lens.snapTo(_committed + 0.5);
  }

  void _cancel() {
    if (_lens.cancel()) _lens.snapTo(_committed + 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color activeColor = Theme.of(context).colorScheme.primary;
    final int selectedIdx = _lens.previewIndex ?? _committed;

    // **两条档位两棵树**：判据只在这里读（`liquidGlassActive` 的允许位置见
    // `test/liquid_scope_guard_test.dart`）。
    return ValueListenableBuilder<bool>(
      valueListenable: liquidGlassActive,
      builder: (BuildContext context, bool liquid, Widget? _) => liquid
          ? _buildLiquid(isDark, activeColor, selectedIdx)
          : _buildStandard(isDark, activeColor, selectedIdx),
    );
  }

  /// **标准档**：加液态档之前那一棵，除了状态源换成控制器之外一个字都没改。
  Widget _buildStandard(bool isDark, Color activeColor, int selectedIdx) {
    const inset = AppTokens.padChipV;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, c) {
          final itemW = c.maxWidth / widget.count;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _press(d.localPosition.dx, itemW),
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
                // 玻璃胶囊底
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.height / 2),
                        color: AppTokens.glassTint(isDark, true).first,
                        border: Border.all(
                          color: AppTokens.glassBorder(isDark),
                        ),
                      ),
                    ),
                  ),
                ),
                // 滑块
                AnimatedPositioned(
                  duration:
                      _lens.dragging ? Duration.zero : AppTokens.durFast,
                  curve: Curves.easeOutCubic,
                  left: _lens.page * itemW + inset,
                  top: inset,
                  bottom: inset,
                  width: itemW - inset * 2,
                  child: QScale(
                    pressed: _lens.pressed,
                    scale: AppTokens.pillGrow,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                            (widget.height - inset * 2) / 2),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: AppTokens.accentGradient(activeColor).colors,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.32),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 分段内容
                _content(selectedIdx),
              ],
            ),
          );
        },
      ),
    );
  }

  /// **液态档**：那枚会提起来、会滑、边缘带折射光晕的玻璃滴。
  ///
  /// `pad: 0` —— 见类文档：分段器的格子铺满全宽，与底栏不同构。
  Widget _buildLiquid(bool isDark, Color activeColor, int selectedIdx) {
    return LiquidTrack(
      slots: widget.count,
      capsuleH: widget.height,
      // 几何内缩用 `padChipV`（与标准档那枚滑块的内缩一致），**内容内缩用 0** ——
      // 见 `LiquidTrack.contentPad` 与类文档那段「它和底栏的几何不一样」。
      pad: AppTokens.padChipV,
      contentPad: 0,
      controller: _lens,
      metrics: LiquidLensMetrics.forCapsule(widget.height),
      // 标准档那棵的 `GestureDetector` 没有被裁 —— 这一档也不裁，两档的命中区一致。
      clipContent: false,
      contentBuilder: (BuildContext context, double itemW) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _press(d.localPosition.dx, itemW),
        onTapUp: (_) => _release(),
        onTapCancel: _onTapCancel,
        onHorizontalDragStart: (d) => _dragStart(d.localPosition.dx, itemW),
        onHorizontalDragUpdate: (d) => _dragUpdate(d.localPosition.dx, itemW),
        onHorizontalDragEnd: (_) => _release(),
        onHorizontalDragCancel: _cancel,
        child: _content(_lens.previewIndex ?? _committed, lensItemW: itemW),
      ),
    );
  }

  /// 分段内容。**[lensItemW] 只有液态那棵树传** —— 给了就把每一格套上
  /// [LensWarpedCell]（滑块扫过时文字被边缘挤），与底栏同一条规矩：标准档
  /// 一个变换都不套。
  ///
  /// ⚠️ **两套格宽不一样**，别合成一个数：
  /// - 分段器的**格子**铺满全宽 → `cellW = (透镜格宽×格数 + 2×padChipV) ÷ 格数`；
  /// - **滴**那一套是内缩的 → `padChipV + position × lensItemW`。
  ///
  /// 拿底栏那个式子（`pad + (i+0.5)×itemW`）算中心，300 宽下会得到 52 而不是 50
  /// —— 差 2px 就够让峰值与滴的真实边缘错开。
  Widget _content(int selectedIdx, {double? lensItemW}) {
    final double cellW = lensItemW == null
        ? 0
        : lensItemW + 2 * AppTokens.padChipV / widget.count;
    final double halfWidth = lensItemW == null
        ? 0
        : (lensItemW + LiquidLensMetrics.forCapsule(widget.height).liftWidth) / 2;
    return Row(
      children: List<Widget>.generate(widget.count, (int i) {
        final Widget cell =
            Center(child: widget.itemBuilder(i, i == selectedIdx));
        if (lensItemW == null) return Expanded(child: cell);
        return Expanded(
          child: LensWarpedCell(
            controller: _lens,
            iconCenterX: (i + 0.5) * cellW,
            lensPad: AppTokens.padChipV,
            itemW: lensItemW,
            halfWidth: halfWidth,
            child: cell,
          ),
        );
      }),
    );
  }
}
