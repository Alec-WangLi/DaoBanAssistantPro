import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/glass/liquid_lens.dart';
import '../../core/glass/liquid_lens_metrics.dart';
import '../../core/l10n.dart';
import '../../core/layout.dart';
import '../../core/theme/animated_background.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/lens_warped_cell.dart';
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
  static const double _armThreshold = 0.7;

  /// 那枚「药丸」在**屏幕上**的尺寸（宽 × 高）。
  ///
  /// 用户 2026-10-01：「不做成圆形了，改成类似液态玻璃滑块的样式」—— 它不再是
  /// 一枚圆钮，而是与底栏滑块同一族的胶囊。⚠️ 这两个数在**局部坐标里是反的**
  /// （见 `_liquidThumb` 的说明）。
  static const double _thumbW = 52;
  static const double _thumbH = 38;

  // 矮屏（可用高 < 480：手机横屏、小窗、车机）各收一档。不收的话
  // 900×420 会溢出 4px、200×400 会溢出 108px —— 视觉工装 `tool/visual` 抓到的。
  static const double _trackHeightShort = 132;
  static const double _thumbWShort = 46;
  static const double _thumbHShort = 33;
  // 底部留白至少要盖住「再睡一会」按钮（高 52、离底 24），否则滑块压在按钮上。
  static const double _gapBelow = 96;
  static const double _gapBelowShort = 84;

  late final AnimationController _enter;
  late final Animation<double> _scale;
  late final AnimationController _slide;

  /// 按住那枚滴时的「提起来」0..1。提起 = 放大 + 彩边亮起（与底栏、开关同一套读法）。
  late final AnimationController _thumbLift;

  /// 手指的竖向速度（px/s，**向上为正** = 关闭方向）。形变跟着它走。
  double _thumbVelocity = 0;

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
    _thumbLift = AnimationController(vsync: this, duration: AppTokens.durMed);
  }

  @override
  void dispose() {
    _enter.dispose();
    _slide.dispose();
    _thumbLift.dispose();
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

  void _onSliderDragStart(DragStartDetails d) {
    _thumbLift.forward();
  }

  void _onSliderDragUpdate(DragUpdateDetails d, double trackHeight) {
    // 直接设值 → 圆钮 1:1 跟随手指，无延迟。
    final v = (_slide.value - d.delta.dy / trackHeight).clamp(0.0, 1.0);
    _slide.value = v;
    // 形变要的是**速度**（px/s）。手势事件约 60Hz，`delta.dy` 是这一帧的位移，
    // 负号把「手指向上（关闭方向）」定成正 —— 头大尾小要朝着运动方向。
    _thumbVelocity = -d.delta.dy * 60;
  }

  void _onSliderDragEnd(DragEndDetails d) {
    _thumbLift.reverse();
    _thumbVelocity = 0;
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
    final thumbW = layout.isShort ? _thumbWShort : _thumbW;
    final thumbH = layout.isShort ? _thumbHShort : _thumbH;
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
                        _dismissSlider(trackHeight, thumbW, thumbH),
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

  /// 那枚药丸（含图标）。**两条档位两棵树** —— 与底栏 / 分段器 / 开关同一套写法：
  /// 关掉液态玻璃时走 [_standardThumb]，**形状与尺寸一模一样、只有材质不同**
  /// （两档的尺寸一起改是有意的：只改一档会让切档位时控件跳一下）。
  ///
  /// 判据只在这里读，位置登记在 `test/liquid_scope_guard_test.dart` 的名单里。
  Widget _thumbFace(Color primary, double thumbW, double thumbH, bool armed) {
    return ValueListenableBuilder<bool>(
      valueListenable: liquidGlassActive,
      builder: (BuildContext context, bool liquid, Widget? _) => Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          if (liquid)
            _liquidThumb(primary, thumbW, thumbH)
          else
            _standardThumb(primary, thumbW, thumbH, armed),
          AppIcon(
            armed ? Icons.check_outlined : Icons.keyboard_arrow_up_outlined,
            // 液态档那枚是主色玻璃，图标只能走白（与底栏选中项同一个取舍）；
            // 标准档那枚是实心白，白图标会隐身 —— 用的是它原来那两个颜色。
            color: liquid
                ? Colors.white
                : (armed ? primary : AppTokens.inkMutedDark),
            size: AppTokens.iconLg,
          ),
        ],
      ),
    );
  }

  /// **标准档**：同一枚药丸，实心白 + 主色辉光。
  ///
  /// 形状跟着一起改成药丸（原来是一枚圆钮）—— 两档尺寸必须一致，否则切档位时
  /// 控件会跳一下；尺寸由 [_thumbW] / [_thumbH] 一处说了算。
  Widget _standardThumb(
      Color primary, double thumbW, double thumbH, bool armed) {
    return Container(
      width: thumbW,
      height: thumbH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(thumbH / 2),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: armed ? 0.6 : 0.3),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }

  /// 按住时往**左右**各鼓出去多少（px）。这一条就是「凸出轨道」——
  /// 药丸宽 52、轨道宽 72，鼓满时 52 + 2×16 = 84，比轨道多出 6px 一边。
  static const double _thumbProtrude = 16;

  /// 按住时往**上下**长多少（px）。⚠️ 这个量是**合计**、不是每侧（`LiquidLensMetrics`
  /// 的约定：`protrude` 是每侧、`liftWidth` 是总共）—— 药丸高 38 → **44**。
  static const double _thumbLiftWidth = 6;

  /// 那枚竖直的药丸。
  ///
  /// **整体转 90° 是有原因的，不是取巧。** 这一族形状（`LiquidLensShape`）的
  /// 「沿运动方向拉长」与「后缘收细（头大尾轻）」**都写死在局部 x 轴上** ——
  /// 底栏与开关的运动本来就是横向的，所以那两处天然对齐；而这枚滴是**竖着走**的，
  /// 不转的话拉长会长在左右、头大尾轻根本读不出来。
  ///
  /// 转过来之后，局部 x = 屏幕的**上下**、局部 y = 屏幕的**左右**：
  ///
  /// | 参数 | 在屏幕上是什么 |
  /// |---|---|
  /// | `itemW` | 药丸的**高**（静止 38，按住时长到 44） |
  /// | `capsuleH − 2·pad` | 药丸的**宽**（静止 52） |
  /// | `capsuleH` | **轨道的宽**（72）—— 折边那两条边线就画在它的两端 |
  /// | `pad` | (轨道宽 − 药丸宽) / 2 |
  /// | `protrude` | 按住时往**左右**鼓出去多少 = 凸出轨道（**每侧**） |
  /// | `liftWidth` | 按住时往**上下**长多少（**合计**） |
  ///
  /// ⚠️ **`capsuleH` 必须给轨道的宽、`pad` 必须给 `(72 − 药丸宽) / 2`** —— 折边
  /// （`refractedCapsuleEdge`）的两条边线画在 `capsuleH` 的两端，给错了就折在空气里。
  /// 而 `protrude` 要足够大（`protrude > pad`）药丸才真的**凸出轨道**。
  /// 用户 2026-10-01：「长按它放大后应该是大过下面的滑轨吧？你看咱们其他地方的
  /// 滑块，不都是这样的吗？那些滑轨的边缘会被折弯」。
  Widget _liquidThumb(Color primary, double thumbW, double thumbH) {
    final double pad = (_trackWidth - thumbW) / 2;
    const LiquidLensMetrics metrics = LiquidLensMetrics(
      protrude: _thumbProtrude,
      liftWidth: _thumbLiftWidth,
      rimScale: 0.7,
      // 这一面一格只有 38px 高，与开关同一条理由：全局 900 在这个尺度上够不着，
      // 尾巴该收 35%、实际只收 10%。
      velocityRef: 300,
    );
    return Transform.rotate(
      // `-π/2` 让局部 +x 指向屏幕**上方**（关闭方向）—— 于是前缘在上、后缘在下，
      // 尾巴拖在下面收细。
      angle: -math.pi / 2,
      child: SizedBox(
        // 局部盒：宽 = 药丸高 + 两侧内缩（几何要居中在盒里），高 = **轨道的宽**。
        width: 2 * pad + thumbH,
        height: _trackWidth,
        child: LiquidLens(
          size: Size(2 * pad + thumbH, _trackWidth),
          shape: LiquidLensShape.of(
            itemW: thumbH,
            capsuleH: _trackWidth,
            pad: pad,
            centerPage: 0,
            lift: _thumbLift.value,
            velocity: _thumbVelocity,
            metrics: metrics,
          ),
          lift: _thumbLift.value,
          isDark: true,
          accent: primary,
          // 白芯在药丸上是坏读法：它会渲成一道横穿钮身的白线（与开关同一条理由）。
          showRingCore: false,
          // **静止时也要有一圈边缘高光。** 光谱那几层全被「静止时一个彩色像素都
          // 没有」关着（那是底栏定的，底栏那枚旁边有图标和胶囊衬着、不缺这一圈），
          // 而这一枚孤零零挂在深色页面上 —— 关了它静止时就只剩一块平色
          // （用户 2026-10-01：「它会立刻读成玻璃而不是漆」）。
          restEdge: 1,
        ),
      ),
    );
  }

  /// 上滑关闭滑块：药丸跟随手指，拖到阈值即触发关闭，未到位则 Q弹回弹。
  Widget _dismissSlider(double trackHeight, double thumbW, double thumbH) {
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_slide, _thumbLift]),
      builder: (context, _) {
        final p = _slide.value.clamp(0.0, 1.0);
        final armed = p >= _armThreshold;
        final thumbBottom = p * (trackHeight - thumbH);
        // ⚠️ **色带要**贴住药丸的底边**，不是「按进度铺满轨道」**。原来写的是
        // `p * trackHeight`，而药丸的底边在 `p * (trackHeight − thumbH)` ——
        // 两者相差 `p × thumbH`，拉到顶时整整差了药丸一整个高度，中间空出一段
        // （用户 2026-10-01 看原型：「它后面跟着的色带好像缝隙有点大」）。
        // 贴住之后两支读成一个东西：药丸**拖着**色带走。
        final fillHeight = thumbBottom;
        return SizedBox(
          width: _hitWidth,
          height: trackHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: _onSliderDragStart,
            onVerticalDragUpdate: (d) => _onSliderDragUpdate(d, trackHeight),
            onVerticalDragEnd: _onSliderDragEnd,
            // 视觉居中在更宽的热区里；两类子控件都按 _trackWidth 定宽，
            // 所以轨道、填充、圆钮的相对位置不受热区宽度影响。
            child: Center(
              child: SizedBox(
                width: _trackWidth,
                height: trackHeight,
                child: Stack(
                  // ⚠️ **`Clip.none` 不能省**：按住时药丸要**凸出轨道左右两条边**
                  // （凸出量 6px），默认的 `Clip.hardEdge` 会把它齐刷刷切掉 ——
                  // 而那一刀正好落在折边上，看起来就是「药丸被夹扁了」。
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    // 轨道
                    Container(
                      width: _trackWidth,
                      height: trackHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_trackWidth / 2),
                        // **下浓上透的竖直渐变**，不是一层平色：190px 的轨道里药丸只占
                        // 38，上面八成是空的 —— 平色读起来就是「一根空管子」。垫一层
                        // 之后「这里有一段行程」在**静止时**就看得见
                        // （用户 2026-10-01 看原型提的第二条建议）。
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.03),
                            Colors.white.withValues(alpha: 0.14),
                          ],
                        ),
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
                    // 轨道那圈**边光** —— 与底栏 / 分段器 / 开关的胶囊同一件
                    // （`CapsuleRimPainter`）。补它的理由：那三处的轨道都是「玻璃」，
                    // 这里此前只有一条描边，摆在一起就比它们单薄一档
                    // （用户 2026-10-01 看原型：「感觉还差点意思」）。
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: CapsuleRimPainter(
                            radius: _trackWidth / 2,
                            isDark: true,
                            compact: true,
                          ),
                        ),
                      ),
                    ),
                    // 药丸（跟随手指）—— 液态档下是一枚**真的玻璃滴**：按住提起来、
                    // 跟着手指的速度沿**竖直**方向拉长、后缘收细，与底栏 / 分段器 /
                    // 开关是同一件东西。
                    //
                    // ⚠️ 外面那层 `Stack` **必须 `Clip.none`** —— 提起之后滴比它的
                    // 盒子大，默认的 `Clip.hardEdge` 会把凸出来的那圈连彩边一起切掉。
                    Positioned(
                      // 盒子取**轨道的宽**（旋转前后都要装得下，且折边那两条边线要落在
                      // 轨道左右两条边上）；药丸居中在盒里，所以盒底要比药丸的底边
                      // **再低半格** —— 写反成 `+` 的话药丸会浮在轨道底上方 34px
                      // （用户看原型时那句「缝隙有点大」有一半是它）。
                      bottom: thumbBottom - (_trackWidth - thumbH) / 2,
                      child: SizedBox(
                        width: _trackWidth,
                        height: _trackWidth,
                        child: _thumbFace(primary, thumbW, thumbH, armed),
                      ),
                    ),
                    // 提示文字（随进度淡出）—— **也要被透镜挤一下**：它就躺在药丸
                    // 经过的那条路上（用户 2026-10-01：「如果这个滑轨上面有字，
                    // 记得这个字是不是也得扭曲效果」）。竖着走的透镜用竖轴那一份。
                    Positioned.fill(
                      child: Center(
                        child: LensWarpedVertical(
                          listenable:
                              Listenable.merge(<Listenable>[_slide, _thumbLift]),
                          itemCenterY: trackHeight / 2,
                          lensCenterY: () =>
                              trackHeight - (thumbBottom + thumbH / 2),
                          halfHeight: (thumbH + 2 * _thumbLiftWidth) / 2,
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
