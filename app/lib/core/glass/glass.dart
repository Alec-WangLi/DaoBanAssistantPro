import 'dart:ui' show ImageFilter;

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
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.blurSigma = 24,
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
        padding: padding ?? const EdgeInsets.all(20),
        child: Material(color: Colors.transparent, child: child),
      ),
    );

    if (blurOn && !solid) {
      panel = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
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

/// 液态玻璃圆角容器（无内边距快捷版）。
class GlassTile extends StatelessWidget {
  const GlassTile({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
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
      blurSigma: 18,
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
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: child!,
        );
      },
      child: child,
    );
  }
}
