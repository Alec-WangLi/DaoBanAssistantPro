import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../glass/glass.dart';
import 'app_colors.dart';

/// 缓慢流动的中性渐变光晕背景（液态玻璃氛围感）。
///
/// 用法一律是 `Scaffold(backgroundColor: <平坦底色>, body: FlowingBackground(child: …))`
/// —— 它**自己不画底色**，只在底色上叠三团缓慢漂移的光斑。玻璃卡片压在一块纯色上时
/// 其实是没东西可磨的（只剩高光与白描边撑着，看起来「素」而不是「润」），这一层就是
/// 给玻璃一层可以透的**弱结构**。
///
/// [intensity] 是光斑透明度的倍率：响铃界面是主角、用满（1.0）；日历页是天天看着的
/// 一页、且一大半被 92% 不透明的格子盖住，调弱一档更耐看。
///
/// [freezeWhenBlurDisabled] 为真时，「高级材质」一关（[glassBlurDisabled]）就**停下**，
/// 只留当前这一帧。那个开关的语义是「这台机器不做贵的合成」，而背景只要还在动，页面上
/// 每一层 `BackdropFilter` 就得每帧重算 —— 模糊都关了却继续推动背景，等于把省下来的
/// 又花回去。默认 false：响铃界面只出现几秒、光晕本来就是它的主角，没必要改它。
///
/// **驱动方式是按毫秒级的定时器，不是 `AnimationController..repeat()`** —— 这一条是
/// 这个类最要紧的地方，别改回去：
///   · 26 秒一个来回、位移只有 46dp（约 1.8dp/秒）。按帧（60fps）重画，每帧动 0.03dp，
///     没有任何人看得出来；而代价是**整页永久不空闲**：`CustomPaint` 每帧重绘，压在它
///     上面的每一层 `BackdropFilter` 就每帧重算。日历页是长时间停留的一页，这就是白烧
///     电。按最慢那一档时长更新（约 1dp/步）观感与逐帧完全一致，合成开销降到 1/24。
///   · 60fps 的 `repeat()` 还会让 `pumpAndSettle` **永远等不到停**（帧队列永远非空），
///     整个日历的 widget 测试套件都得改成逐帧推进才能跑 —— 低频驱动下它是正常的。
class FlowingBackground extends StatefulWidget {
  const FlowingBackground({
    super.key,
    required this.child,
    this.intensity = 1.0,
    this.freezeWhenBlurDisabled = false,
  });

  final Widget child;
  final double intensity;
  final bool freezeWhenBlurDisabled;

  @override
  State<FlowingBackground> createState() => _FlowingBackgroundState();
}

class _FlowingBackgroundState extends State<FlowingBackground> {
  /// 一个来回的总时长（与从前 `AnimationController` 的 26 秒一致）。
  static const Duration _period = Duration(seconds: 26);

  /// 每次推进的间隔。借最慢那一档时长令牌（`design_tokens_test` 不许界面层写时长
  /// 字面量）—— 它只是个**采样步长**、不是过渡时长，值在这一档上下差几十毫秒对观感
  /// 毫无影响（每步位移不到 1dp），所以没必要为它另立一档令牌。
  static const Duration _tick = AppTokens.durSlow;

  double _t = 0; // 0..1 的循环位置
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    glassBlurDisabled.addListener(_syncRun);
    _syncRun();
  }

  void _syncRun() {
    final frozen = widget.freezeWhenBlurDisabled && glassBlurDisabled.value;
    if (frozen) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(_tick, (_) {
      // `setState` 只重建这一层：内容是以 `widget.child` 传进来的**同一个实例**，
      // 元素会被复用、不会连带重建（整页 42 格 + 信息卡的重建代价一点都不沾）。
      setState(() {
        _t = (_t + _tick.inMilliseconds / _period.inMilliseconds) % 1.0;
      });
    });
  }

  @override
  void dispose() {
    glassBlurDisabled.removeListener(_syncRun);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WavePainter(_t, widget.intensity),
      child: widget.child,
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t, this.intensity);

  final double t;

  /// 光斑透明度的倍率，1.0 = 响铃界面那一档。
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final blobs = <(Offset, double, Color, double)>[
      (Offset(size.width * 0.15, size.height * 0.12), 200, Colors.white, 0.0),
      (Offset(size.width * 0.88, size.height * 0.32), 240, AppColors.bgBlob, 1.3),
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
            color.withValues(alpha: 0.26 * intensity),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.t != t || old.intensity != intensity;
}
