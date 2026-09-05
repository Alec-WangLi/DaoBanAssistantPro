import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/theme/animated_background.dart';
import '../../core/widgets/glass_button.dart';
import 'alarm_service.dart';

/// 全屏响铃界面：深色流动光晕 + 液态玻璃元素 + Q弹入场。
/// 底部「上滑关闭」滑块跟随手指；整屏上滑也可关闭；「再睡一会」玻璃按钮。
/// 铃声由原生前台服务 AlarmRingService 统一播放。
class AlarmRingingScreen extends StatefulWidget {
  const AlarmRingingScreen({super.key, required this.label});

  final String label;

  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen>
    with TickerProviderStateMixin {
  static const double _trackHeight = 190;
  static const double _trackWidth = 56;
  static const double _thumbSize = 46;
  static const double _armThreshold = 0.7;

  late final AnimationController _enter;
  late final Animation<double> _scale;
  late final AnimationController _slide;

  double _bodyDragDy = 0;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
    _scale = CurvedAnimation(parent: _enter, curve: Curves.easeOutBack);
    _slide = AnimationController(
      vsync: this,
      duration: AppTokens.durSlow,
    );
  }

  @override
  void dispose() {
    _enter.dispose();
    _slide.dispose();
    super.dispose();
  }

  void _finish() {
    AlarmService.stopAlarmSound();
    AlarmService.ringingAlarm.value = null;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _snooze() {
    AlarmService.stopAlarmSound();
    AlarmService.snoozeAlarm(widget.label);
    AlarmService.ringingAlarm.value = null;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _onSliderDragUpdate(DragUpdateDetails d) {
    // 直接设值 → 圆钮 1:1 跟随手指，无延迟。
    final v = (_slide.value - d.delta.dy / _trackHeight).clamp(0.0, 1.0);
    _slide.value = v;
  }

  void _onSliderDragEnd(DragEndDetails d) {
    if (_slide.value >= _armThreshold) {
      _finish();
    } else {
      _slide.animateTo(0.0,
          duration: AppTokens.durSlow,
          curve: Curves.easeOutBack);
    }
  }

  void _onBodyDragUpdate(DragUpdateDetails d) {
    setState(() => _bodyDragDy += d.delta.dy);
  }

  void _onBodyDragEnd(DragEndDetails d) {
    if (_bodyDragDy.abs() > 120 || (d.primaryVelocity?.abs() ?? 0) > 800) {
      _finish();
    } else {
      setState(() => _bodyDragDy = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final timeStr = '${now.hourOfPeriod.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: AppTokens.bgDark,
      body: FlowingBackground(
        child: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: _onBodyDragUpdate,
            onVerticalDragEnd: _onBodyDragEnd,
            child: AnimatedOpacity(
              opacity: (1 - _bodyDragDy.abs() / 300).clamp(0.0, 1.0),
              duration: AppTokens.durFast,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    children: [
                      const Spacer(),
                      ScaleTransition(
                        scale: _scale,
                        child: FadeTransition(
                          opacity: _enter,
                          child: Column(
                            children: [
                              Text(
                                timeStr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: AppTokens.fontDisplayXl,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _labelCapsule(),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      _dismissSlider(),
                      const SizedBox(height: 96),
                    ],
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 24,
                    child: GlassButton(
                      primary: true,
                      icon: const Icon(Icons.snooze_outlined),
                      onPressed: _snooze,
                      child: Text(L10n.snooze),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 闹钟标签的玻璃胶囊。
  Widget _labelCapsule() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppTokens.glassTint(true, true),
        ),
        border: Border.all(color: AppTokens.glassBorder(true)),
      ),
      child: Text(
        widget.label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppTokens.inkDark,
          fontSize: AppTokens.fontBody,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 上滑关闭滑块：圆钮跟随手指，拖到阈值即触发关闭，未到位则 Q弹回弹。
  Widget _dismissSlider() {
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _slide,
      builder: (context, _) {
        final p = _slide.value.clamp(0.0, 1.0);
        final armed = p >= _armThreshold;
        final thumbBottom = p * (_trackHeight - _thumbSize);
        final fillHeight = p * _trackHeight;
        return SizedBox(
          width: _trackWidth,
          height: _trackHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: _onSliderDragUpdate,
            onVerticalDragEnd: _onSliderDragEnd,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // 轨道
                Container(
                  width: _trackWidth,
                  height: _trackHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_trackWidth / 2),
                    color: Colors.white.withValues(alpha: 0.08),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14)),
                  ),
                ),
                // 填充（随进度从底部增长）
                Positioned(
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_trackWidth / 2),
                    child: Container(
                      width: _trackWidth,
                      height: fillHeight,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            primary.withValues(alpha: armed ? 0.9 : 0.7),
                            primary.withValues(alpha: armed ? 0.7 : 0.35),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // 圆钮（跟随手指）
                Positioned(
                  bottom: thumbBottom,
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: armed ? 0.6 : 0.3),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      armed
                          ? Icons.check_outlined
                          : Icons.keyboard_arrow_up_outlined,
                      color: armed ? primary : AppTokens.inkMutedDark,
                      size: 28,
                    ),
                  ),
                ),
                // 提示文字（随进度淡出）
                Positioned.fill(
                  child: Center(
                    child: Opacity(
                      opacity: (1 - p * 1.6).clamp(0.0, 1.0),
                      child: Text(
                        L10n.swipeUpToDismiss,
                        style: const TextStyle(
                            color: AppTokens.inkMutedDark,
                            fontSize: AppTokens.fontCaption),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
