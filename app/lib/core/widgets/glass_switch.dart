import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../glass/glass.dart';
import '../glass/liquid_lens_controller.dart';
import '../glass/liquid_lens_metrics.dart';
import '../haptics.dart';
import 'liquid_track.dart';

/// 玻璃开关：圆钮 + 玻璃轨道 + Q弹回弹。
///
/// 用于替换系统 Switch / Checkbox，统一「液态玻璃 + Q弹」设计语言。
///
/// **两条档位两棵树**（与底栏、分段器同一套写法）：关掉液态玻璃时走 [_buildStandard]，
/// 与加这一档之前**逐像素相同**。置灰（[enabled] `false`）**一律走标准档那棵** ——
/// 它的语义是「这台机器打不开那个效果」，与「那个效果作用于哪里」无关。
///
/// ## 液态档这一棵长什么样
///
/// 轨道**玻璃化**（`GlassBlur` + `navFill` / `navBorder`），**开的时候**在玻璃里叠一层
/// 主色淡染表示「已打开」。钮是一枚**主色玻璃滴** —— 与底栏、分段器**同一件东西**
/// （用户 2026-10-01：「颜色变浅了，尤其是跟主题模式等，有明显的颜色差别。理论上
/// 它们应该都是一样的」；原来它是白球，材质与另两处根本不同）。
///
/// 升程也**与另两处统一**（`LiquidLensMetrics.forCapsule`，纵横一起长）。
/// v0.10.9 那版传的是 `protrude: 8, liftWidth: 0`「只长个儿」—— 那一版是照用户
/// 当时「参考 iOS 26 往纵向放大」做的，2026-10-01 他自己推翻了：
/// 「你参考底部导航栏那个滑块……还是优先把它统一起来」。
class GlassSwitch extends StatefulWidget {
  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.width = 56,
    this.height = 30,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  final double width;
  final double height;

  /// 置灰并不可交互。给「这台设备不支持」的场景用（见「我的 → 外观 → 液态玻璃」
  /// 在低内存机器上的处理）—— 那时候开关若还能拨动，用户会得到一个「拨了没反应」
  /// 的开关，比直接说不可用更糟。
  ///
  /// ⚠️ **它没有跟着液态档一起回退，是有意的**（v0.10.3 把液态档收拢到底栏）：
  /// 「这台机器打不开那个效果」与「那个效果作用于哪里」无关，低内存机器上那一行
  /// 仍然是灰的。护栏在 `test/glass_switch_test.dart`。
  final bool enabled;

  @override
  State<GlassSwitch> createState() => _GlassSwitchState();
}

class _GlassSwitchState extends State<GlassSwitch>
    with SingleTickerProviderStateMixin {
  /// 开关这一枚的四个数（用户 2026-10-01 拍的板）。
  ///
  /// ⚠️ **写死的，不再跟 `widget.height` 走。** 全仓九个调用点都用默认的 56 × 30
  /// （没人传过 `height`），而 `velocityRef` 是绝对速度（px/s）、`liftWidth: -2`
  /// 也是绝对值 —— 它们本来就没法按高度等比推出来，留着 `forCapsule` 只会给出
  /// 一个「看起来会自适应、其实一半是硬的」的假象。要改尺寸的话这四个数一起重算。
  static const LiquidLensMetrics _metrics = LiquidLensMetrics(
    // 纵向拉长（满升程约 23 × 42）—— 用户原话：「右」。
    // v0.10.10 那版是 `forCapsule(30)`（纵横一起长），读起来是个大圆。
    protrude: 9,
    liftWidth: -2,
    // 彩边：内晕往轮廓里伸进去的**占比**与底栏对齐。底栏 8%，而 `30/64 = 0.469`
    // 时开关是 16%（钮只有 23 宽，同一份绝对宽度占掉两倍）。
    rimScale: 0.25,
    // 一格只有 25px，全局 900 会把尾巴掐掉三分之二（峰值形变 0.22~0.28）。
    velocityRef: 180,
  );

  late final LiquidLensController _lens;

  double _lastPage = 0;
  bool _lastPressed = false;
  int? _lastPreview;

  @override
  void initState() {
    super.initState();
    _lastPage = widget.value ? 1 : 0;
    _lens = LiquidLensController(
      slots: 2,
      // 内缩 = `padChipV`（3）—— 标准档那棵树用的也是它，且钮径 `height - 6` 的
      // 内缩正好是 (28 − 22) / 2 = 3，两棵树的钮一样大。
      pad: AppTokens.padChipV,
      liftWidth: _metrics.liftWidth,
      vsync: this,
      initialSlot: widget.value ? 1 : 0,
      // 开关不可拖：提起之后钮**不朝手指走**（见 `followFinger` 的说明）。
      followFinger: false,
      velocityRef: _metrics.velocityRef,
    );
    _lens.addListener(_onLensChanged);
  }

  @override
  void dispose() {
    _lens.removeListener(_onLensChanged);
    _lens.dispose();
    super.dispose();
  }

  void _onLensChanged() {
    if (_lens.page == _lastPage &&
        _lens.pressed == _lastPressed &&
        _lens.previewIndex == _lastPreview) {
      return;
    }
    _lastPage = _lens.page;
    _lastPressed = _lens.pressed;
    _lastPreview = _lens.previewIndex;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(GlassSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外面把 value 改了（或者我们刚点了它）→ 钮滑到那一端。
    if (oldWidget.value != widget.value) {
      _lens.snapTo(widget.value ? 1.5 : 0.5);
    }
  }

  void _toggle() {
    if (!widget.enabled) return;
    Haptics.select();
    widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = widget.activeColor ?? Theme.of(context).colorScheme.primary;
    final double thumbSize = widget.height - 6;

    // 档位判据只在这里读。**置灰一律走标准档** —— 见 [GlassSwitch.enabled]。
    return ValueListenableBuilder<bool>(
      valueListenable: liquidGlassActive,
      builder: (BuildContext context, bool liquid, Widget? _) =>
          (liquid && widget.enabled)
              ? _buildLiquid(context, isDark, accent)
              : _buildStandard(isDark, accent, thumbSize),
    );
  }

  /// **标准档**：加液态档之前那一棵，一个字都没改。
  Widget _buildStandard(bool isDark, Color accent, double thumbSize) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? _toggle : null,
      child: AnimatedContainer(
        duration: AppTokens.durMed,
        curve: Curves.easeOutCubic,
        width: widget.width,
        height: widget.height,
        padding: const EdgeInsets.all(AppTokens.padChipV),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.height / 2),
          color: !widget.enabled
              ? AppTokens.glassBorder(isDark).withValues(alpha: 0.25)
              : widget.value
                  ? accent
                  : AppTokens.glassBorder(isDark).withValues(alpha: 0.6),
          border: Border.all(
            color: !widget.enabled
                ? AppTokens.glassBorder(isDark).withValues(alpha: 0.5)
                : widget.value
                    ? accent.withValues(alpha: 0.55)
                    : AppTokens.glassBorder(isDark),
          ),
        ),
        child: AnimatedAlign(
          duration: AppTokens.durMed,
          curve: Curves.easeOutBack,
          alignment: widget.value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: thumbSize,
            height: thumbSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.enabled
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.55),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// **液态档**：玻璃轨道 + 一枚按住会纵向拉长的白玻璃钮。
  Widget _buildLiquid(BuildContext context, bool isDark, Color accent) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: LiquidTrack(
        slots: 2,
        capsuleH: widget.height,
        pad: AppTokens.padChipV,
        controller: _lens,
        metrics: _metrics,
        // 白芯在小钮上是坏的：它会渲成一道**横穿钮身的白线**（放大看很清楚）。
        // v0.10.9 关掉它的理由是「白上画白等于没画」—— 那按的是**钮的颜色**，
        // 于是钮一改成主色它就带着缺陷回来了。这里按**控件尺寸**判，与颜色无关。
        showRingCore: false,
        // 这一层是**底栏特有**的读法，46px 宽的轨道上它是几道乱线（样图实测）。
        showRefractedEdge: false,
        // 「已打开」= 玻璃里叠一层主色淡染。
        trackTint: widget.value ? accent.withValues(alpha: 0.35) : null,
        contentBuilder: (BuildContext context, double itemW) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          // ⚠️ **先 `setItemW`**：不给的话控制器里的每格宽度还是默认的 1，
          // `press` 拿它去算「手指在第几格」会算出几十格，钮被甩出轨道外面。
          onTapDown: (d) {
            _lens.setItemW(itemW);
            // **`moveToSlot: false`** —— 开关点哪儿都只是拨一下，钮不跟着手指跑。
            _lens.press(d.localPosition.dx, moveToSlot: false);
          },
          onTapUp: (_) {
            _lens.release();
            _toggle();
          },
          onTapCancel: _lens.tapCancel,
          // **拖动**（用户 2026-10-01：「长按想拖动的时候，它拖不动，好像没有加这个
          // 动作」）。松手时钮落在哪一端就切到哪一端；拖回原处则什么都不做。
          //
          // **不设「必须先按住 110ms」的闸门**：那个闸门只管「拉长」这个视觉，
          // 不该管能不能拖。`press` 那边仍然是 `moveToSlot: false`、控制器仍然是
          // `followFinger: false` —— 点按不挪钮，只有真横向拖起来才走。
          onHorizontalDragStart: (DragStartDetails d) {
            _lens.setItemW(itemW);
            _lens.dragStart(d.localPosition.dx);
          },
          onHorizontalDragUpdate: (DragUpdateDetails d) {
            _lens.setItemW(itemW);
            _lens.dragUpdate(d.localPosition.dx);
          },
          onHorizontalDragEnd: (DragEndDetails _) {
            if (_lens.release() != (widget.value ? 1 : 0)) _toggle();
          },
          onHorizontalDragCancel: _lens.cancel,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
