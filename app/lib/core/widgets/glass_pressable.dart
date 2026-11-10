import 'package:flutter/material.dart';

import '../motion.dart';

/// 玻璃按压反馈：给任意可点条目统一「Q弹缩放 + 水波纹浮于玻璃之上」。
///
/// 根因说明：`ListTile`/`InkWell` 的水波纹默认画在 Scaffold 的 `Material` 上，被
/// `GlassTile`/`GlassPanel` 那层不透明玻璃 `Container` 挡在后面，看起来像「没反馈」。
/// 本组件在玻璃之上再垫一层透明 `Material`，让波纹可见，同时叠加 Q 弹按压缩放。
class GlassPressable extends StatefulWidget {
  const GlassPressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
  });

  final Widget child;

  /// 可选的点击回调。给了它，这一层会自己垫一个 `InkWell`（波纹照样浮在玻璃上）；
  /// 不给则维持原行为 —— child 自己就是可点件（`ListTile` 等）。**两者别同时给**，
  /// 否则一次点击会有两层水波纹。
  final VoidCallback? onTap;

  final double pressedScale;

  @override
  State<GlassPressable> createState() => _GlassPressableState();
}

class _GlassPressableState extends State<GlassPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return QScale(
      pressed: _pressed,
      scale: widget.pressedScale,
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: Material(
          color: Colors.transparent,
          child: widget.onTap == null
              ? widget.child
              : InkWell(onTap: widget.onTap, child: widget.child),
        ),
      ),
    );
  }
}
