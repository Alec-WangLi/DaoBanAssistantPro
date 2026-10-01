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
/// 主色淡染表示「已打开」。钮是一枚**白色**玻璃球（不是主色玻璃滴 —— 白球压在淡染
/// 轨道上才读得出），**按住时纵向拉长**：`20 × 22 → 20 × 38`，宽度不变。
///
/// 为什么钮要纵向拉长而不是等比例放大：用户 2026-10-01 的原话是「按住的时候不是要
/// 放大吗？那就要做成往纵向放大，参考 iOS 26 他们的开关液态玻璃那种形状变化」。
/// 那正是 `LiquidLensMetrics` 存在的理由 —— 底栏那套凸出量是照 64 高胶囊量的，
/// 搬到 28 高的轨道上会「整个胀到外面」。
class GlassSwitch extends StatefulWidget {
  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.width = 46,
    this.height = 28,
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
      // 「只长个儿、不变宽」—— 这是这一处的形状契约。
      liftWidth: 0,
      vsync: this,
      initialSlot: widget.value ? 1 : 0,
      // 开关不可拖：提起之后钮**不朝手指走**（见 `followFinger` 的说明）。
      followFinger: false,
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
        metrics: const LiquidLensMetrics(protrude: 8, liftWidth: 0),
        // 钮是**白的** —— 压在淡染轨道上，主色玻璃滴会糊成一片。
        fill: const <Color>[Colors.white, Colors.white],
        // 白上画白等于没画：那条白芯在这里只会把轮廓读没。
        showRingCore: false,
        // 这两层是**底栏特有**的读法，46px 宽的轨道上它们是几道乱线（样图实测）。
        showGlowBand: false,
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
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
