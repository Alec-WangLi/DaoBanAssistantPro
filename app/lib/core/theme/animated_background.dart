import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 缓慢流动的中性渐变光晕背景（液态玻璃氛围感）。
class FlowingBackground extends StatefulWidget {
  const FlowingBackground({super.key, required this.child});

  final Widget child;

  @override
  State<FlowingBackground> createState() => _FlowingBackgroundState();
}

class _FlowingBackgroundState extends State<FlowingBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 26))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _WavePainter(_controller.value),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final blobs = <(Offset, double, Color, double)>[
      (Offset(size.width * 0.15, size.height * 0.12), 200, Colors.white, 0.0),
      (Offset(size.width * 0.88, size.height * 0.32), 240, const Color(0xFFB9BECF), 1.3),
      (Offset(size.width * 0.55, size.height * 0.9), 280, Colors.white, 2.1),
    ];
    for (final b in blobs) {
      final (base, radius, color, phase) = b;
      final drift = Offset(
        math.sin((t + phase) * 2 * math.pi) * 46,
        math.cos((t + phase) * 2 * math.pi) * 34,
      );
      final center = base + drift;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.26),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.t != t;
}
