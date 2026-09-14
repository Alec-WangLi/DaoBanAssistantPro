import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/layout.dart';
import '../../core/theme/animated_background.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/glass_button.dart';
import 'alarm_service.dart';

/// 全屏响铃界面：深色流动光晕 + 液态玻璃元素 + Q弹入场。
/// 底部「上滑关闭」滑块跟随手指；整屏上滑也可关闭；「再睡一会」玻璃按钮。
/// 铃声由原生前台服务 AlarmRingService 统一播放。
class AlarmRingingScreen extends StatefulWidget {
  const AlarmRingingScreen({super.key, required this.label, this.detail});

  final String label;

  /// 标题下面那行说明。待办的「联动闹钟」用它交代「什么事、几点」
  /// （如「9月15日 周二 · 14:30」），班次/自定义闹钟不带，只显示标题。
  final String? detail;

  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen>
    with TickerProviderStateMixin {
  static const double _trackHeight = 190;
  static const double _trackWidth = 72;
  // 热区比轨道宽：轨道是看得见的胶囊，热区是手指真正要戳中的范围。
  // 整屏本身已经可以上滑关闭（见 build 里那层铺满的 GestureDetector），
  // 但滑块是屏幕上唯一写着「上滑关闭」的地方，手指会往它上面落，所以单独放宽。
  static const double _hitWidth = 112;
  static const double _thumbSize = 46;
  static const double _armThreshold = 0.7;

  // 矮屏（可用高 < 480：手机横屏、小窗、车机）各收一档。不收的话
  // 900×420 会溢出 4px、200×400 会溢出 108px —— 视觉工装 `tool/visual` 抓到的。
  static const double _trackHeightShort = 132;
  static const double _thumbSizeShort = 40;
  // 底部留白至少要盖住「再睡一会」按钮（高 52、离底 24），否则滑块压在按钮上。
  static const double _gapBelow = 96;
  static const double _gapBelowShort = 84;

  late final AnimationController _enter;
  late final Animation<double> _scale;
  late final AnimationController _slide;

  double _bodyDragDy = 0;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: AppTokens.durRingEnter,
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
    // 说明也要跟着续排，否则再睡一会之后那一次就只剩标题了。
    AlarmService.snoozeAlarm(AlarmRing(widget.label, widget.detail));
    AlarmService.ringingAlarm.value = null;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _onSliderDragUpdate(DragUpdateDetails d, double trackHeight) {
    // 直接设值 → 圆钮 1:1 跟随手指，无延迟。
    final v = (_slide.value - d.delta.dy / trackHeight).clamp(0.0, 1.0);
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
    final layout = AppLayout.of(context);
    final trackHeight = layout.isShort ? _trackHeightShort : _trackHeight;
    final thumbSize = layout.isShort ? _thumbSizeShort : _thumbSize;
    final gapBelow = layout.isShort ? _gapBelowShort : _gapBelow;

    final now = TimeOfDay.now();
    final timeStr = '${now.hourOfPeriod.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    // 屏蔽系统返回手势：响铃界面是压在 App 主界面之上的一层路由，而这一层可能正
    // 盖在锁屏上（见 MainActivity 的 setShowWhenLocked）。一次返回就退回主界面 =
    // 锁屏下把 App 内容露出来，所以这里只留「上滑关闭」与「再睡一会」两个显式出口
    // —— 它们走 `_finish`/`_snooze` 里的 `Navigator.pop`，不受 `canPop` 约束。
    return PopScope(
      canPop: false,
      child: Scaffold(
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
                                // 窄屏（小窗 200dp）下 84px 的「06:30」会折成两行、
                                // 把整列顶爆。scaleDown 只在放不下时才缩，常规屏不受影响。
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppTokens.space2xl),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      timeStr,
                                      maxLines: 1,
                                      // 84/w800/h1 都在 ringClock 里，不再写行内字重。
                                      style: AppTokens.ringClock.copyWith(
                                        color: Colors.white,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _labelCapsule(),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        _dismissSlider(trackHeight, thumbSize),
                        SizedBox(height: gapBelow),
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
      ),
    );
  }

  /// 闹钟标签的玻璃胶囊：标题一行，待办的联动闹钟再加一行说明。
  Widget _labelCapsule() {
    final detail = widget.detail;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceLg, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppTokens.glassTint(true, true),
        ),
        border: Border.all(color: AppTokens.glassBorder(true)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label,
            textAlign: TextAlign.center,
            style: AppTokens.rowPrimary.copyWith(color: AppTokens.inkDark),
          ),
          // 说明走这一屏既有的次要文字色（上滑滑块的提示字用的也是它）。
          if (detail != null) ...[
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: AppTokens.microText
                  .copyWith(color: AppTokens.inkMutedDark),
            ),
          ],
        ],
      ),
    );
  }

  /// 上滑关闭滑块：圆钮跟随手指，拖到阈值即触发关闭，未到位则 Q弹回弹。
  Widget _dismissSlider(double trackHeight, double thumbSize) {
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _slide,
      builder: (context, _) {
        final p = _slide.value.clamp(0.0, 1.0);
        final armed = p >= _armThreshold;
        final thumbBottom = p * (trackHeight - thumbSize);
        final fillHeight = p * trackHeight;
        return SizedBox(
          width: _hitWidth,
          height: trackHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) => _onSliderDragUpdate(d, trackHeight),
            onVerticalDragEnd: _onSliderDragEnd,
            // 视觉居中在更宽的热区里；两类子控件都按 _trackWidth 定宽，
            // 所以轨道、填充、圆钮的相对位置不受热区宽度影响。
            child: Center(
              child: SizedBox(
                width: _trackWidth,
                height: trackHeight,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // 轨道
                    Container(
                      width: _trackWidth,
                      height: trackHeight,
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
                        width: thumbSize,
                        height: thumbSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  primary.withValues(alpha: armed ? 0.6 : 0.3),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: AppIcon(
                          armed
                              ? Icons.check_outlined
                              : Icons.keyboard_arrow_up_outlined,
                          color: armed ? primary : AppTokens.inkMutedDark,
                          size: AppTokens.iconLg,
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
                            style: AppTokens.microText
                                .copyWith(color: AppTokens.inkMutedDark),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
