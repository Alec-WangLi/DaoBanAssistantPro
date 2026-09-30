import 'dart:ui' show BlurStyle, ImageFilter, MaskFilter;

import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 低端机自动降级标志（物理内存 < 4GB，main() 设置）。
bool lowEndDevice = false;

/// 用户手动关闭「高级材质」标志（「我的 → 外观」开关控制）。
bool advancedMaterialDisabled = false;

/// 玻璃真实模糊总开关（低端机自动 + 用户手动 取或）。
/// 用 ValueNotifier 让开关变更时所有玻璃组件实时重建。
final ValueNotifier<bool> glassBlurDisabled = ValueNotifier<bool>(false);

/// 重新计算 [glassBlurDisabled]（main() 与「高级材质」开关变更时调用）。
void recomputeGlassBlur() {
  final disabled = lowEndDevice || advancedMaterialDisabled;
  glassBlurDisabled.value = disabled;
}

/// 玻璃的完整 filter：**模糊 + 真实饱和度**，合成一个 filter 而不是叠两层
/// `BackdropFilter`（两层 = 两次 backdrop 抓取）。
///
/// `ImageFilter.compose` 的语义是 `result = outer(inner(source))`，所以这里是
/// 「先把背景提饱和、再糊」（`sky_engine/lib/ui/painting.dart` 的 compose 文档）。
///
/// 为什么要有这个函数、而不是各处直接写 `ImageFilter.blur`：它是**唯一**一处
/// 「背景怎么处理」的装配点 —— 阶段 2 的液态档要在这里按档位分叉。散着写的话，
/// 那一步就得满仓库找 `BackdropFilter`。
ImageFilter glassFilter(double sigma) => ImageFilter.compose(
      outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      inner: AppTokens.glassSaturation,
    );

// ---------------------------------------------------------------------------
// 探针（临时，不是产品代码）
// ---------------------------------------------------------------------------
//
// 要回答的问题：**在不碰标准档的前提下，靠「加色」的那一层（边缘光 / 主色着色）
// 能不能让液态档明显好看？**
//
// 为什么值得单独探：实测已证折射在平背景上看不见（≤1/255，见台账）。而边缘光与
// 着色是**加上去的**、不采样背景，所以它是平背景上唯一还可能看得见的一层 ——
// 但「可能」不等于「能」，得看图。
//
// 结论出来后这一段要么删掉、要么按结论重做。

/// 探针：给玻璃面叠一圈方向性边缘光（见 [GlassRim]）。
bool glassProbeRim = false;

/// 液态玻璃面板。
///
/// 效果构成（与调研结论一致）：
///   1) 背景模糊（BackdropFilter + ImageFilter.blur）
///   2) 半透明渐变着色（近似饱和度提升）
///   3) 顶部镜面高光描边（liquid 边缘光）
///
/// 低端降级：`enableBlur=false` 时用更不透明的填充代替真实背景模糊。
/// 真·折射/液滴 shader 作为后续增强（FragmentProgram）叠加。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
    this.blurSigma = AppTokens.blurPanel,
    this.enableBlur = true,
    this.solid = false,
    this.padding,
    this.margin,
    this.onTap,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;

  /// 是否启用真实背景模糊（API31+ 或性能充足时为 true）。
  final bool enableBlur;

  /// 近实心模式：底部弹层等场景用。背景遮罩照常变暗，但面板本身用
  /// 不透明的 [Theme.colorScheme.surface] 作底，不再半透明透出遮罩的暗色。
  final bool solid;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: glassBlurDisabled,
      builder: (context, blurDisabled, _) => _build(context, blurDisabled),
    );
  }

  Widget _build(BuildContext context, bool blurDisabled) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final blurOn = enableBlur && !blurDisabled;
    final fill = solid
        ? [surface, surface]
        : AppTokens.glassSurface(isDark, blurOn);
    final fillGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: fill,
    );
    final borderColor = AppTokens.glassBorder(isDark);

    Widget panel = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: borderColor, width: 1),
        gradient: fillGradient,
        boxShadow: [AppTokens.glassShadow(isDark)],
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppTokens.spaceXl),
        child: Material(color: Colors.transparent, child: child),
      ),
    );

    if (!solid) {
      panel = GlassRim(
        radius: borderRadius.topLeft.x,
        isDark: isDark,
        child: panel,
      );
    }

    if (blurOn && !solid) {
      panel = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: glassFilter(blurSigma),
          child: panel,
        ),
      );
    }
    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: panel,
        ),
      );
    }
    return panel;
  }
}

/// 探针：给任意玻璃面叠一圈方向性边缘光。**不是产品代码**（见 [glassProbeRim]）。
///
/// 第一轮只打在 `GlassPanel` 上，于是同一屏里只有信息卡有边、顶栏与底栏胶囊没有 ——
/// 看着像「这张卡被选中了」。观感问题出在**不一致**，不在描边本身，所以做成通用的。
///
/// 画在**之上**（`foregroundPainter`），而不是拿 `padding` 围一圈 —— 后者会把面板
/// 缩小、里面的文字跟着位移，量出来的差异里混进的是「位移」而不是「描边」
/// （第一版就是这么把自己测糊的：整块 90% 的像素都在变，看着像巨大效果）。
/// Flutter 既没有渐变描边、也没有渐变版的 `Border`，所以只能走 `CustomPainter`。
class GlassRim extends StatelessWidget {
  const GlassRim({
    super.key,
    required this.radius,
    required this.isDark,
    required this.child,
    this.compact = false,
    this.sliderIndex,
    this.tabCount,
    this.trackPad = 0,
    this.sliderScale = 1,
  });

  final double radius;
  final bool isDark;
  final Widget child;

  /// 小控件（底栏胶囊）用更细的一圈。
  final bool compact;

  /// 滑块中心位置，**以「功能区」为单位**（第 2 格的中间 = 1.5）。null = 不做光的响应。
  final double? sliderIndex;

  /// 功能区个数。
  final int? tabCount;

  /// 胶囊内边距（滑块轨道两侧的留白），用来把 [sliderIndex] 换算成真实像素。
  final double trackPad;

  /// 滑块当前的缩放（按下时 >1），让亮边跟得上它的大小。
  final double sliderScale;

  @override
  Widget build(BuildContext context) {
    if (!glassProbeRim) return child;
    return Stack(
      children: <Widget>[
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _RimPainter(
                radius: radius,
                colors: AppTokens.glassRimProbe(isDark),
                width: AppTokens.glassRimProbeWidth(isDark, compact: compact),
                glow: AppTokens.glassRimProbeGlow(isDark),
                sliderIndex: sliderIndex,
                tabCount: tabCount,
                trackPad: trackPad,
                sliderScale: sliderScale,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 边缘光 + 「光跟随滑块」。
///
/// 后半段**不是折射** —— 折射是逐像素扭曲背景（要 shader，且在平背景上看不见）。
/// 这里做的是「光的响应」：光源（滑块）经过时，它附近那一段玻璃边亮起来，
/// 滑块自己也带一圈被光击中的边。平背景上能被看见的只有这一类。
class _RimPainter extends CustomPainter {
  _RimPainter({
    required this.radius,
    required this.colors,
    required this.width,
    required this.glow,
    this.sliderIndex,
    this.tabCount,
    this.trackPad = 0,
    this.sliderScale = 1,
  });

  final double radius;
  final List<Color> colors;
  final double width;
  final Color glow;
  final double? sliderIndex;
  final int? tabCount;
  final double trackPad;
  final double sliderScale;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final RRect rrect = RRect.fromRectAndRadius(
      rect.deflate(width / 2),
      Radius.circular(radius),
    );
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    canvas.drawRRect(
      rrect,
      stroke
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const <double>[0.0, 0.45, 1.0],
          colors: colors,
        ).createShader(rect),
    );

    final double? index = sliderIndex;
    final int? count = tabCount;
    if (index == null || count == null || count <= 1 || size.width <= 0) return;

    final double itemW = (size.width - 2 * trackPad) / count;
    final double centerX = trackPad + index * itemW;

    // ① 玻璃边在滑块那一带亮起来：横向一条**窄**亮带。
    //    第一版做成 ±0.16 的宽带，结果和底色融了、看不出「跟着走」—— 收窄才有指向性。
    final double h = (centerX / size.width).clamp(0.0, 1.0);
    const double band = 0.085;
    double lo = h - band;
    if (lo < 0) lo = 0;
    double hi = h + band;
    if (hi > 1) hi = 1;
    if (hi - lo > 0.02) {
      double mid = h;
      if (mid < lo + 0.01) mid = lo + 0.01;
      if (mid > hi - 0.01) mid = hi - 0.01;
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 1.4
          // 边缘光也要有晕 —— 一条硬线读作「描边」，一圈晕才读作「光」。
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
          ..shader = LinearGradient(
            colors: <Color>[
              glow.withValues(alpha: 0),
              glow,
              glow.withValues(alpha: 0),
            ],
            stops: <double>[lo, mid, hi],
          ).createShader(rect),
      );
    }

    // ② 滑块自身：**一圈被光击中的晕 + 一条硬边**。
    //
    // 只有硬边的时候读作「这个控件加了描边」；加了外圈模糊的晕之后才读作
    // 「光聚在这里」—— 这一层是整个效果里最接近「折射」的观感来源。
    final double sliderW = itemW * sliderScale;
    final double sliderH = size.height - 2 * trackPad;
    final RRect sliderRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, size.height / 2),
        width: sliderW,
        height: sliderH,
      ),
      Radius.circular(sliderH / 2),
    );
    final Paint sliderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          glow.withValues(alpha: 0.95),
          glow.withValues(alpha: 0.25),
        ],
      ).createShader(rect);
    // 晕：粗、模糊、淡
    canvas.drawRRect(
      sliderRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            glow.withValues(alpha: 0.55),
            glow.withValues(alpha: 0.10),
          ],
        ).createShader(rect),
    );
    // 硬边压在晕上
    canvas.drawRRect(sliderRRect, sliderPaint);
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius ||
      old.colors != colors ||
      old.width != width ||
      old.sliderIndex != sliderIndex ||
      old.tabCount != tabCount ||
      old.trackPad != trackPad ||
      old.sliderScale != sliderScale;
}

/// 液态玻璃圆角容器（无内边距快捷版）。
class GlassTile extends StatelessWidget {
  const GlassTile({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppTokens.radiusL)),
    this.padding,
    this.margin,
    this.enableBlur = true,
    this.onTap,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool enableBlur;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: borderRadius,
      padding: padding,
      margin: margin,
      enableBlur: enableBlur,
      onTap: onTap,
      blurSigma: AppTokens.blurCard,
      child: child,
    );
  }
}

/// 仅在「高级材质」开启（[glassBlurDisabled]=false）时应用背景模糊；关闭时直接渲染 child。
/// 供玻璃按钮、提示条等非 GlassPanel 的模糊点复用，统一受「高级材质」控制。
class GlassBlur extends StatelessWidget {
  const GlassBlur({super.key, required this.sigma, required this.child});

  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: glassBlurDisabled,
      builder: (context, disabled, child) {
        if (disabled) return child!;
        return BackdropFilter(
          filter: glassFilter(sigma),
          child: child!,
        );
      },
      child: child,
    );
  }
}
