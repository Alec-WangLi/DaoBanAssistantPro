// app/lib/core/motion.dart
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'design_tokens.dart';

/// 让 [controller] 从当前值以弹簧物理弹到 [target]（Q 弹过冲，替换 easeOutBack+固定时长）。
void springTo(AnimationController controller, double target) {
  final sim = SpringSimulation(
    AppTokens.qSpring,
    controller.value,
    target,
    controller.velocity,
  );
  controller.animateWith(sim);
}

/// Q 弹缩放组件：按下时从 1.0 弹到 [scale]，松手弹回 1.0。
class QScale extends StatefulWidget {
  const QScale({
    super.key,
    required this.pressed,
    required this.scale,
    required this.child,
  });

  final bool pressed;
  final double scale;
  final Widget child;

  @override
  State<QScale> createState() => _QScaleState();
}

class _QScaleState extends State<QScale> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController.unbounded(vsync: this, value: 1.0);

  @override
  void didUpdateWidget(covariant QScale old) {
    super.didUpdateWidget(old);
    if (old.pressed != widget.pressed) {
      springTo(_c, widget.pressed ? widget.scale : 1.0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _c, child: widget.child);
}