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
    this.pressedScale = 0.97,
  });

  final Widget child;
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
          child: widget.child,
        ),
      ),
    );
  }
}
