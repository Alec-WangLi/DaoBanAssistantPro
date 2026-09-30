import 'dart:ui' show BlurStyle, ImageFilter, MaskFilter;

import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 低端机自动降级标志（物理内存 < 4GB，main() 设置）。**语义不变**：强制省电档。
bool lowEndDevice = false;

/// 「我的 → 外观 → 液态玻璃」开关（默认关）。用户意愿。
final ValueNotifier<bool> liquidGlassEnabled = ValueNotifier<bool>(false);

/// 省电档生效中。**只由 [lowEndDevice] 触发** —— 用户不能手动选它。
/// 用 ValueNotifier 让开关变更时所有玻璃组件实时重建。
final ValueNotifier<bool> glassBlurDisabled = ValueNotifier<bool>(false);

/// 液态档生效中。
///
/// 判据只有两个条件，**没有 shader 能力检查** —— 因为这个档里没有 shader：
/// 实测折射在平背景上 ≤1/255（本 App 的底色是刻意的极简黑白），
/// 看得见的那一层是「加色」的边缘光与透镜，而它用 `CustomPainter` 就够。
/// 于是计划里那条 shader 构建链、以及 Impeller / GLES / Windows 三个坑，
/// 一个都不用碰。
final ValueNotifier<bool> liquidGlassActive = ValueNotifier<bool>(false);

/// 重新计算两个档位（main() 与「外观」开关变更时调用）。
void recomputeGlassTiers() {
  glassBlurDisabled.value = lowEndDevice;
  liquidGlassActive.value = !lowEndDevice && liquidGlassEnabled.value;
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

/// 液态档：给玻璃面叠一圈方向性边缘光 + 跟随滑块的透镜。
///
/// **这一层就是「液态玻璃」的全部**。它不采样背景（折射只发生在「玻璃 ↔ 背景」的
/// 边界上，而本 App 的底色是刻意的极简黑白 —— 实测采样类的效果在这里 ≤1/255），
/// 靠的是**加色**：边缘光、透镜的凸起与光晕。浅色下白光看不见，所以那一档的配方
/// 是「左上高光 + 右下轻收」的立体边；深色下才是被点亮的玻璃边。
/// 配方见 `AppTokens.glassRimProbe*`（名字里的 Probe 是历史，值与调法是量的结果）。
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
    this.lensFill,
    this.lensProtrude = 0,
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

  /// 透镜的填充色（通常传主色）。
  final Color? lensFill;

  /// 透镜凸出容器多少。**0 = 不凸**（等于原来那个躺在胶囊里的滑块）。
  final double lensProtrude;

  @override
  Widget build(BuildContext context) {
    // 液态档才叠这一层。用 ValueListenableBuilder 而不是读一次布尔值 ——
    // 「外观」里那个开关一翻，全 app 的玻璃面都要跟着重建。
    return ValueListenableBuilder<bool>(
      valueListenable: liquidGlassActive,
      builder: (BuildContext context, bool on, Widget? child) =>
          on ? _lit() : child!,
      child: child,
    );
  }

  Widget _lit() {
    return Stack(
      // **必须 Clip.none**：透镜要能画到胶囊外面去。
      // 默认的 hardEdge 会把溢出的部分裁掉，那就退回「光只能在胶囊内部打转」，
      // 而折射恰恰只发生在「玻璃 ↔ 背景」的边界上。
      clipBehavior: Clip.none,
      children: <Widget>[
        // ① 透镜**本体**：画在 child **之下**。
        //
        // 位置放在下面是有意的：child 里是胶囊（半透明填充 + 被裁剪的模糊），
        // 透镜压在它下面 → 胶囊内的部分会透过玻璃透出来（正是「玻璃后面有东西」的
        // 观感），探出胶囊的那圈则是清晰的一枚玻璃；而图标在 child 里，仍压在透镜之上。
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _RimPainter(
                radius: radius,
                colors: AppTokens.glassRimProbe(isDark),
                width: AppTokens.glassRimProbeWidth(isDark, compact: compact),
                glow: AppTokens.glassRimProbeGlow(isDark),
                isDark: isDark,
                sliderIndex: sliderIndex,
                tabCount: tabCount,
                trackPad: trackPad,
                sliderScale: sliderScale,
                lensFill: lensFill,
                lensProtrude: lensProtrude,
                paintCore: true,
              ),
            ),
          ),
        ),
        child,
        // ② 边缘光与光晕：画在 child **之上**。
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _RimPainter(
                radius: radius,
                colors: AppTokens.glassRimProbe(isDark),
                width: AppTokens.glassRimProbeWidth(isDark, compact: compact),
                glow: AppTokens.glassRimProbeGlow(isDark),
                isDark: isDark,
                sliderIndex: sliderIndex,
                tabCount: tabCount,
                trackPad: trackPad,
                sliderScale: sliderScale,
                lensFill: lensFill,
                lensProtrude: lensProtrude,
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
    required this.isDark,
    this.sliderIndex,
    this.tabCount,
    this.trackPad = 0,
    this.sliderScale = 1,
    this.lensFill,
    this.lensProtrude = 0,
    this.paintCore = false,
  });

  final double radius;
  final List<Color> colors;
  final double width;
  final Color glow;
  final bool isDark;
  final double? sliderIndex;
  final int? tabCount;
  final double trackPad;
  final double sliderScale;
  final Color? lensFill;
  final double lensProtrude;

  /// true = 只画透镜本体（下面那一趟）；false = 只画边缘光与光晕（上面那一趟）。
  final bool paintCore;

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

    // 透镜的几何。**高度故意大于胶囊** —— 滑块原来只有 `capsuleH - 2 * trackPad`
    // 高、整个躺在胶囊里，它的边是「玻璃对玻璃」，而折射只发生在「玻璃 ↔ 背景」的
    // 边界上（Apple 那条禁令「玻璃不能采样玻璃」说的就是这件事）。iOS 26 的开关与
    // 标签栏选中态都是**凸出容器**的：「按住时它变成一个更大、玻璃般的凸起，移动时
    // 折射光线」（Macworld 对开关的描述）。凸出来，那圈亮边才有一条真实的边界可依附。
    final double lensW = itemW * sliderScale;
    final double lensH = size.height - 2 * trackPad + 2 * lensProtrude;
    final RRect lensRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, size.height / 2),
        width: lensW,
        height: lensH,
      ),
      Radius.circular(lensH / 2),
    );

    // 下面那一趟只画透镜**本体** —— 它被压在 `child` 之下（于是胶囊内的部分透过
    // 半透明填充透出来、探出胶囊的部分是清晰的一枚玻璃），画完就结束。
    if (paintCore) {
      // 没给填充色就不画本体（调用点一定会给）。**这里不放兜底色** ——
      // `lib/core/glass` 在令牌守门的扫描范围内，一个 `Color(0x…)` 字面量就让它红。
      final Color? base = lensFill;
      if (base == null) return;
      // **用标准档那枚滑块的同一套配方**：主色**半透明**渐变 + 同明度的白描边。
      //
      // 早先这里是「不透明主色 + 1px 白环」—— 两个后果：① 静止时它与标准档长得
      // 不一样（用户 2026-10-01「很丑」的一部分）；② 不透明主色把导航选中项的
      // 白字对比度从 4.7~8.2 推到 2.35~4.43，**五种主色在深色下全部跌破 AA**
      // （独立审查算出来的）。换成半透明渐变之后它与标准档一致，对比度也回来了。
      final Color fill = base;
      canvas.drawRRect(
        lensRRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppTokens.accentGradient(fill).colors,
          ).createShader(lensRRect.outerRect),
      );
      canvas.drawRRect(
        lensRRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: isDark ? 0.28 : 0.85),
      );
      return;
    }

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

    // ② 透镜的**边缘光**：一圈被光击中的晕 + 一条硬边。
    //
    // 只有硬边的时候读作「这个控件加了描边」；加了外圈模糊的晕之后才读作
    // 「光聚在这里」—— 这一层是整个效果里最接近「折射」的观感来源。
    canvas.drawRRect(
      lensRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            glow.withValues(alpha: 0.60),
            glow.withValues(alpha: 0.10),
          ],
        ).createShader(rect),
    );
    canvas.drawRRect(
      lensRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            glow.withValues(alpha: 0.95),
            glow.withValues(alpha: 0.25),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius ||
      old.colors != colors ||
      old.width != width ||
      old.sliderIndex != sliderIndex ||
      old.tabCount != tabCount ||
      old.trackPad != trackPad ||
      old.sliderScale != sliderScale ||
      old.lensFill != lensFill ||
      old.lensProtrude != lensProtrude;
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
