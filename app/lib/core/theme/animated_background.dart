import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
/// [freezeWhenBlurDisabled] 为真时，省电档一开（[glassBlurDisabled]）就**停下**，
/// 只留当前这一帧。那个档的语义是「这台机器不做贵的合成」，而背景只要还在动，页面上
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
    this.pauseWhen,
  });

  final Widget child;
  final double intensity;
  final bool freezeWhenBlurDisabled;

  /// 这个为真时**把光晕停住**（`_t` 不推进 ⇒ 恢复时从原处续上、不跳回）。
  ///
  /// 日历页拿它传「有东西在动」（拖动 / 滑行 / 多选拖选）：那些交互本来每帧都在画，
  /// 而光晕每 340ms 插进来一帧就是**一次固定掉帧**。默认 `null` ⇒ 行为不变
  /// （响铃界面那一处不传）。
  ///
  /// ⚠️ 它与 [freezeWhenBlurDisabled] 是**两件事**（一个问「机器做不做贵的合成」、
  /// 一个问「此刻有没有别的东西在动」），`_syncRun` 里各判各的。
  final ValueListenable<bool>? pauseWhen;

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
    widget.pauseWhen?.addListener(_syncRun);
    _syncRun();
  }

  @override
  void didUpdateWidget(FlowingBackground old) {
    super.didUpdateWidget(old);
    if (old.pauseWhen != widget.pauseWhen) {
      old.pauseWhen?.removeListener(_syncRun);
      widget.pauseWhen?.addListener(_syncRun);
      _syncRun();
    }
  }

  void _syncRun() {
    final frozen = (widget.freezeWhenBlurDisabled && glassBlurDisabled.value) ||
        (widget.pauseWhen?.value ?? false);
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
    widget.pauseWhen?.removeListener(_syncRun);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // **光晕自己一层**（`Stack` 里的兄弟层），不是「给页面内容加一层
    // `RepaintBoundary`」。两个理由：
    //
    // ① 层序与从前一字不差：原来 `CustomPaint(painter:, child:)` 就是「先画光晕、
    //    再画 child」，这里光晕仍是先画的兄弟 ⇒ 画面不变（`glow_layer_test` 与
    //    `tool/visual` 的逐张比都盯着）。
    // ② 给 child 加边界会把这条链变成「边界里的模糊看不看得见边界外的变化」——
    //    引擎在这件事上有历史问题，一旦跟不上，表现就是**玻璃里的模糊被冻住**
    //    （页面在动、玻璃里的底色不动），那是实打实的观感下降。兄弟层不依赖那条
    //    行为：光晕一变整棵树就重合成，压在它上面的模糊读到的一定是新的光晕。
    //
    // 效果：那一帧只重新录制光晕自己这一层（实测「被画过的绘制节点」139 → 个位数）。
    // 注意它省的是 **UI 线程**那份重绘录制；压在光晕上面的 `BackdropFilter` 仍然会
    // 被合成器重算（那是 GPU 的事）—— 要连那份一起省，只能让光晕别动。
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              key: const Key('flowing-background'),
              painter: _WavePainter(_t, widget.intensity),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t, this.intensity);

  final double t;

  /// 光晕走到哪一相位（0..1）。给用例读的 —— 「拖动中它停、松手后接着走」
  /// 只有这一个可断言的口子。
  @visibleForTesting
  double get debugPhase => t;

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
