import 'dart:async' show scheduleMicrotask;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'glass_refraction.dart';

/// 低端机自动降级标志（物理内存 < 4GB，main() 设置）。**语义不变**：强制省电档。
bool lowEndDevice = false;

/// 「我的 → 外观 → 液态玻璃」开关（默认关）。用户意愿。
final ValueNotifier<bool> liquidGlassEnabled = ValueNotifier<bool>(false);

/// 省电档生效中。**只由 [lowEndDevice] 触发** —— 用户不能手动选它。
/// 用 ValueNotifier 让开关变更时所有玻璃组件实时重建。
final ValueNotifier<bool> glassBlurDisabled = ValueNotifier<bool>(false);

/// 液态档生效中。
///
/// 判据只有两个条件，**没有 shader 能力检查** —— 这个档的**绘制**部分（透镜、
/// 边光、滑块）全用 `CustomPainter`，与 runtime effect 无关。
///
/// 逐像素的**边缘折射**是另一件事，它有自己的闸门 [liquidRefractionEnabled] ——
/// 两者分开的理由：折射依赖 `FragmentProgram` 加载成功，而加载是异步的，
/// 首帧必然不可用。把两件事捆在一个 notifier 里，会让「液态档」在启动瞬间
/// 闪一下档位，那会把底栏那棵树整棵重建两次。
final ValueNotifier<bool> liquidGlassActive = ValueNotifier<bool>(false);

/// 边缘折射生效中：液态档 + 着色器程序已就绪 + 非省电档。
///
/// 关着的时候 [GlassRefract] 只挂模糊，与今天逐像素一致 —— 这是「新能力默认不可见」
/// 的落点。
///
/// 由 [recomputeGlassTiers] 统一算，**别在别处直接改它**：`FragmentProgram` 加载完成
/// 之后要再调一次 [recomputeGlassTiers]，否则这一位会一直停在 false。
final ValueNotifier<bool> liquidRefractionEnabled = ValueNotifier<bool>(false);

/// 重新计算档位（main()、外观开关变更、着色器加载完成后调用）。
void recomputeGlassTiers() {
  glassBlurDisabled.value = lowEndDevice;
  liquidGlassActive.value = !lowEndDevice && liquidGlassEnabled.value;
  liquidRefractionEnabled.value =
      liquidGlassActive.value && GlassRefraction.available;
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
///
/// **别指望靠简化这个 filter 省钱**：真机上量过 —— 同一段滑动，只留模糊（σ 仍 18）
/// raster p90 是 7.92ms、只留饱和度是 8.21ms，而**整条 `BackdropFilter` 摘掉是 2.37ms**。
/// 贵的是那条渲染通道本身，不是滤镜算什么。
ImageFilter glassFilter(double sigma) => ImageFilter.compose(
      outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      inner: AppTokens.glassSaturation,
    );

/// 液态玻璃面板。
///
/// 效果构成（与调研结论一致）：
///   1) 背景模糊（[BackdropFilter] + `ImageFilter.blur`）—— **只在背后真有东西会动
///      的时候才挂**，见 [blurBackdrop]
///   2) 半透明渐变着色（近似饱和度提升）
///   3) 顶部镜面高光描边（liquid 边缘光）
///
/// **这个件上有两件互相独立的事，别把它们当成一件：**
///   · [translucentFill] —— 用哪**支填充**（观感）
///   · [blurBackdrop]    —— 挂不挂那条 backdrop **渲染通道**（代价）
///
/// 它们从前捆在一个叫 `enableBlur` 的开关上。捆着的时候，「卡片不糊」只能靠换成
/// 更实的那支填充来换，而那**肉眼可见**；拆开之后卡片可以「不糊、但仍是原来那支
/// 半透填充」，逐像素几乎不变（真机实测全屏 ≥4 的像素 0.43%、≥8 的 0.01%）。
///
/// 真·折射/液滴 shader 作为后续增强（FragmentProgram）叠加。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
    this.blurSigma = AppTokens.blurPanel,
    this.translucentFill = true,
    this.blurBackdrop = true,
    this.solid = false,
    this.padding,
    this.margin,
    this.onTap,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;

  /// 用哪一支填充：`true` = 半透那支（配模糊用）；`false` = 更实的那支
  /// （低端档的补偿配方 / 密集列表用）。
  ///
  /// ⚠️ **它只管观感，不管糊不糊** —— 那件事归 [blurBackdrop]。
  final bool translucentFill;

  /// 要不要真的挂 [BackdropFilter]。
  ///
  /// `false` = 只画填充 / 描边 / 阴影。**背后是平色时糊了等于没糊**，却要付一次
  /// backdrop 渲染通道的钱 —— 真机上那是整帧最贵的一笔（编辑排班页 raster p90
  /// **13.10ms → 2.37ms**、掉拍帧 13.4% → 2%）。[GlassTile]（页面里的卡片）恒为 false。
  final bool blurBackdrop;

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
    final translucent = translucentFill && !blurDisabled;
    final fill = solid
        ? [surface, surface]
        : AppTokens.glassSurface(isDark, translucent);
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

    // **裁不裁这一圈，跟的是「填充那一支」，不是「挂不挂模糊」。**
    //
    // 它本来是 `blurOn`（模糊开着才裁）—— 摘掉卡片的 `BackdropFilter` 之后这个条件
    // 其实已经没有存在理由了，但**不能顺手删**：`ClipRRect` 同时把 panel 的
    // `boxShadow` 裁进了圆角矩形内（全 app 因此有两套卡片观感 —— 带模糊的没有阴影，
    // `translucentFill: false` 的与 `solid` 的有）。删了卡片会突然长出一圈阴影，
    // 那是**肉眼可见**的改动，属于观感决定、要单独拍板（spec §3.2 已裁定这一轮保持现状）。
    final clipPanel = !solid && translucentFill && !blurDisabled;
    final blurOn = !solid && blurBackdrop && !blurDisabled;
    if (clipPanel || blurOn) {
      panel = ClipRRect(
        borderRadius: borderRadius,
        child: blurOn
            ? BackdropFilter(filter: glassFilter(blurSigma), child: panel)
            : panel,
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

/// 液态玻璃圆角容器（无内边距快捷版）—— **页面里的卡片**。
///
/// ⚠️ **它永远不挂 `BackdropFilter`**（`blurBackdrop: false`）：卡片坐在页面上，
/// 背后是一块**平色**，糊了等于没糊，却要付一次 backdrop 渲染通道的钱 ——
/// 真机上那是整帧最贵的一笔（编辑排班页 raster p90 13.10ms → 2.37ms）。
/// 这其实是 v0.4.1 对「列表行」做过的同一件事，卡片当时被漏下了。
///
/// **真要一个会糊的面（背后是正文 / 会滚动的正文），用 [GlassPanel]。**
class GlassTile extends StatelessWidget {
  const GlassTile({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppTokens.radiusL)),
    this.padding,
    this.margin,
    this.translucentFill = true,
    this.onTap,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// 见 [GlassPanel.translucentFill] —— 只管**填充那一支**，与糊不糊无关。
  final bool translucentFill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: borderRadius,
      padding: padding,
      margin: margin,
      translucentFill: translucentFill,
      blurBackdrop: false,
      onTap: onTap,
      blurSigma: AppTokens.blurCard,
      child: child,
    );
  }
}

/// 仅在省电档关闭（[glassBlurDisabled]=false）时应用背景模糊；关闭时直接渲染 child。
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

/// 会**弯**的 [GlassBlur]：同一笔模糊，外加容器边缘那一圈逐像素折射。
///
/// 与 [GlassBlur] 的关系是「升级版」而不是「替代品」—— 三道闸门任何一道不过
/// （非移动端 / 程序没加载出来 / 档位关着），它构造出的滤镜与 [GlassBlur]
/// **逐字节相同**，画面也一样。于是调用点可以无条件换过来。
///
/// ## 尺寸必须由调用点给
///
/// 折射要知道容器的形状（宽高 + 圆角半径）才能算出「哪一圈该弯」。这两样在
/// `LayoutBuilder` 里天然就有，所以不让它自己去量 —— 自己去量要么多一层
/// `LayoutBuilder`（多一次布局），要么在 `paint` 里量（那时已经晚了）。
///
/// ## 滤镜对象要缓存
///
/// `BackdropFilter` 每换一个 `filter` 实例就重抓一次 backdrop。这里把
/// [GlassRefraction.filter] 的结果按「尺寸 + 档位」缓存起来，参数不变时
/// 一帧都不会重抓。
class GlassRefract extends StatefulWidget {
  const GlassRefract({
    super.key,
    required this.sigma,
    required this.size,
    required this.radius,
    required this.child,
  });

  /// 模糊强度，语义与 [GlassBlur] 完全一致。
  final double sigma;

  /// 容器尺寸（逻辑像素）。折射只在容器边缘一圈生效。
  final Size size;

  /// 容器圆角半径（逻辑像素）。胶囊就是 `高度 / 2`。
  final double radius;

  final Widget child;

  @override
  State<GlassRefract> createState() => _GlassRefractState();
}

class _GlassRefractState extends State<GlassRefract> {
  ImageFilter? _cached;
  Size? _cachedSize;
  double? _cachedRadius;
  double? _cachedDpr;
  double? _cachedSigma;
  bool? _cachedRefract;

  /// 每帧都会走这里，所以缓存键要比 `==` 便宜 —— 直接比字段。
  ///
  /// **dpr 也是键**：折射的尺寸在 shader 里一律是设备像素，`dpr` 一变
  /// （分屏 / 折叠屏换形态 / 显示大小改档）不重建的话，边缘那一圈会按旧比例
  /// 弯，而且错得不明显 —— 只是「看起来没那么透」。
  ///
  /// **sigma 也是键**：退化那条路（折射没挂上）直接把它交给 `glassFilter`，
  /// 父级只改 sigma、其余不变时若还复用旧滤镜，模糊就永远停在旧档上。
  ImageFilter _filterFor(bool refract, double dpr) {
    if (_cached != null &&
        _cachedSize == widget.size &&
        _cachedRadius == widget.radius &&
        _cachedDpr == dpr &&
        _cachedSigma == widget.sigma &&
        _cachedRefract == refract) {
      return _cached!;
    }
    final ImageFilter? built = refract
        ? GlassRefraction.filter(
            size: widget.size,
            dpr: dpr,
            radius: widget.radius,
            blur: glassFilter(widget.sigma),
          )
        : null;
    if (built == null && refract && liquidRefractionEnabled.value) {
      // 折射没挂上（程序还没就绪 / 后端不支持 —— 后者已经在 `filter` 里把
      // `_program` 清掉了）。档位位得跟着翻回去，否则它会一直骗下游「折射活着」：
      // 底栏那圈彩边是折射的**替身**，替身只在折射真的挂上时才让位。若这里不翻，
      // Impeller 回落到 Skia 的机型上就是「彩边没了、折射也没来」，净退化。
      //
      // 走微任务而不是直接赋值 —— 这里是 `build`，改通知器会在构建期
      // markNeedsBuild。只翻一次：`recomputeGlassTiers()` 之后再进来时
      // `liquidRefractionEnabled.value` 已经是 false，不会自我循环。
      scheduleMicrotask(recomputeGlassTiers);
    }
    final ImageFilter result = built ?? glassFilter(widget.sigma);
    _cached = result;
    _cachedSize = widget.size;
    _cachedRadius = widget.radius;
    _cachedDpr = dpr;
    _cachedSigma = widget.sigma;
    _cachedRefract = refract;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final double dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    return ValueListenableBuilder<bool>(
      valueListenable: glassBlurDisabled,
      builder: (BuildContext context, bool disabled, Widget? child) {
        if (disabled) return child!;
        return ValueListenableBuilder<bool>(
          valueListenable: liquidRefractionEnabled,
          builder: (BuildContext context, bool refract, Widget? child) =>
              BackdropFilter(filter: _filterFor(refract, dpr), child: child!),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
