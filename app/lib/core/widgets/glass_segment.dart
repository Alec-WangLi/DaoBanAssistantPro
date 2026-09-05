import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../motion.dart';

/// 胶囊分段选择器：与底部导航滑块同款手感。
///
/// - 按下：滑块吸附到手指所在段；
/// - 拖动：1:1 跟手（带抓取偏移），Q弹放大；
/// - 松手：吸附到最近段并提交 [onSelected]。
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

class _GlassSegmentState extends State<GlassSegment> {
  bool _pressed = false;
  bool _dragging = false;
  int _committed = 0;
  int? _preview;
  double _visual = 0;
  double _grabOffset = 0;

  @override
  void initState() {
    super.initState();
    _committed = widget.selectedIndex;
    _visual = _committed.toDouble();
  }

  @override
  void didUpdateWidget(GlassSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && !_dragging) {
      _committed = widget.selectedIndex;
      _visual = _committed.toDouble();
    }
  }

  double _clampPage(double p) {
    if (p < 0) p = 0;
    if (p > widget.count - 1) p = (widget.count - 1).toDouble();
    return p;
  }

  int _nearestIndex(double p) {
    var i = p.round();
    if (i < 0) i = 0;
    if (i > widget.count - 1) i = widget.count - 1;
    return i;
  }

  void _press(double dx, double itemW) {
    // 点按：吸附到手指「所在」的段（floor），而不是四舍五入到最近段，
    // 否则在段边界附近点按会误判到隔壁段。
    var i = (dx / itemW).floor();
    if (i < 0) i = 0;
    if (i > widget.count - 1) i = widget.count - 1;
    setState(() {
      _pressed = true;
      _preview = i;
      _visual = i.toDouble();
    });
  }

  void _dragStart(double dx, double itemW) {
    _grabOffset = dx / itemW - _visual;
    _dragUpdate(dx, itemW);
  }

  void _dragUpdate(double dx, double itemW) {
    final p = _clampPage(dx / itemW - _grabOffset);
    setState(() {
      _pressed = true;
      _dragging = true;
      _preview = _nearestIndex(p);
      _visual = p;
    });
  }

  void _release() {
    final target = _nearestIndex(_visual);
    setState(() {
      _pressed = false;
      _dragging = false;
      _preview = null;
      _committed = target;
      _visual = target.toDouble();
    });
    if (target != widget.selectedIndex) widget.onSelected(target);
  }

  void _cancel() {
    if (!_dragging) return;
    setState(() {
      _pressed = false;
      _dragging = false;
      _preview = null;
      _visual = _committed.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = Theme.of(context).colorScheme.primary;
    final selectedIdx = _preview ?? _committed;
    const inset = 3.0;

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, c) {
          final itemW = c.maxWidth / widget.count;
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
                  duration: _dragging ? Duration.zero : AppTokens.durFast,
                  curve: Curves.easeOutCubic,
                  left: _visual * itemW + inset,
                  top: inset,
                  bottom: inset,
                  width: itemW - inset * 2,
                  child: QScale(
                    pressed: _pressed,
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
                Row(
                  children: List.generate(widget.count, (i) {
                    return Expanded(
                      child: Center(
                        child: widget.itemBuilder(i, i == selectedIdx),
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
