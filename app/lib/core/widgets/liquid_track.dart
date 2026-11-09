import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../glass/glass.dart';
import '../glass/liquid_lens.dart';
import '../glass/liquid_lens_controller.dart';
import '../glass/liquid_lens_metrics.dart';

/// 「**胶囊 + 边光 + 玻璃滴 + 内容**」那棵树 —— 液态档在底栏、分段器、开关三处共用的
/// 那一份。
///
/// 层序是**照底栏抄的、不许调**：「底栏渲染逐像素不变」这条验收全靠它。
///
/// ```
/// ①  胶囊          ClipRRect + GlassBlur + navFill / navBorder
/// ①b 边光           CapsuleRimPainter（静止的，不跟 controller 重建）
/// ②  玻璃滴         LiquidLens（内部还有浮起阴影与外溢光晕两层）
/// ③  内容 + 手势    裁在胶囊里、按 pad 内缩
/// ```
///
/// **它不读档位**（`liquidGlassActive`）—— 那是调用点的事，与本仓既有纪律一致
/// （判据只许出现在 `core/glass/glass.dart` 与各调用点）。
///
/// 每帧重建的只有 ② / ③ 两层（听 [controller]）：胶囊连它的 `BackdropFilter`
/// 不跟着动 —— 这是底栏量出来的一条，别改回「整棵树每帧重建」。
class LiquidTrack extends StatelessWidget {
  const LiquidTrack({
    super.key,
    required this.slots,
    required this.capsuleH,
    required this.pad,
    required this.controller,
    required this.contentBuilder,
    this.metrics,
    this.fill,
    this.showRingCore = true,
    this.showRefractedEdge = true,
    this.clipContent = true,
    this.trackTint,
    this.spectral = true,
    this.refract = false,
    double? contentPad,
  }) : _contentPad = contentPad;

  final int slots;
  final double capsuleH;
  final double pad;
  final LiquidLensController controller;

  /// 内容层。拿到的是**每格宽度**（几何在这里，调用点自己算也得再量一次）。
  final Widget Function(BuildContext context, double itemW) contentBuilder;

  final LiquidLensMetrics? metrics;
  final List<Color>? fill;
  final bool showRingCore;

  /// 把容器上下沿「折进来」那条线。小控件上也要关掉，理由同上。
  final bool showRefractedEdge;

  /// 透镜上那几层**画出来的**光谱（彩线 / 两层内晕 / 外溢）开不开，默认开。
  ///
  /// 三处调用点**都走这个默认值**（底栏 / 分段器 / 开关）。
  ///
  /// ⚠️ 2026-11-05 改的：原来底栏传过 `spectral: false`，理由是「真 iOS 的玻璃几乎
  /// 没有虹彩，那圈彩色只能靠画才看得见，是装饰不是物理」，位置让给 `GlassRefract`
  /// 的逐像素折射。用户实测后否掉了 —— **折射带只有边缘几像素、Skia 回落的机器上
  /// 干脆没有**，于是拖动时那枚滴「没有彩色边缘」，观感反而退了一档。
  /// 现在两件同时画：折射管「背后的东西被弯一点」，彩边管「方向感」。
  /// 这条契约由 `test/glass_refraction_test.dart` 与
  /// `test/liquid_nav_spectral_test.dart` 一起钉住 —— 别再让它们互相让位。
  final bool spectral;

  /// 胶囊那一层用 [GlassRefract]（模糊 **+ 边缘逐像素折射**）而不是 [GlassBlur]。
  /// 默认 `false`，**只有底栏传 `true`**。
  ///
  /// 为什么不无条件换：`GlassRefract` 的三道闸门（平台 / 程序 / 档位）在测试环境里
  /// 恒不过 —— `FragmentProgram` 加载不出 asset 时它退化成 `GlassBlur`，于是
  /// 「逐像素不变」那批用例**看不见**真机上的差别。折射的参数（带 20 / 位移 8）
  /// 是按底栏那枚 64 高的胶囊量的：46 宽的开关上带会被夹到 14、位移 8 相当于
  /// 钮高的 29%，那不是「边缘弯一点」，是整颗钮在抖。
  final bool refract;

  /// 内容层裁在胶囊里。开着的效果与底栏标准档一致（`GestureDetector` 在 `ClipRRect`
  /// 里面，胶囊圆角外那一小块不会穿透到页面内容）。
  final bool clipContent;

  /// 叠在胶囊里的**一层纯色**，开关用它表示「已打开」（主色淡染）；底栏与分段器不给。
  ///
  /// ⚠️ **参数是「滴走完全程的比例」0..1，不是布尔值**，而且必须**每帧重算** ——
  /// 开关的轨道色要跟着**拖动**连续过渡。用户 2026-10-01：「开着的时候，背景是蓝色；
  /// 关上的时候背景是空的……拖动的时候，能不能也把背景色的变化做出来？」
  ///
  /// 喂 `widget.value`（原来是这么写的）只能得到「松手那一刻跳一下」：值在 `onTapUp`
  /// 就翻了，而滴还在弹簧上慢慢滑过去。同样地，读 `controller.page` 也是跳变 ——
  /// `release()` / `snapTo()` 在弹簧还没动的时候就把 `page` 吸附到目标了。要用的是
  /// `controller.position`（弹簧的**当前**位置）。
  ///
  /// 返回 `null`（或全透明）表示这一帧不画。
  final Color? Function(double progress)? trackTint;

  /// 内容层的内缩。不给 = 与几何用同一个 [pad]。
  ///
  /// **分段器要分开给**：它的格子铺满全宽、只有滑块自己内缩 `padChipV`（底栏的格子
  /// 是内缩之后排的）。所以那一边传 `pad: 3, contentPad: 0` —— 滴的大小与标准档那枚
  /// 对齐，而文字位置一动不动。
  final double? _contentPad;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: capsuleH,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final Size size = Size(c.maxWidth, capsuleH);
          final double itemW = (c.maxWidth - 2 * pad) / slots;
          final Widget content = Padding(
            padding: EdgeInsets.all(_contentPad ?? pad),
            child: ListenableBuilder(
              listenable: controller,
              builder: (BuildContext context, Widget? _) =>
                  contentBuilder(context, itemW),
            ),
          );

          return Stack(
            // **必须 Clip.none**：透镜要能画到胶囊外面去。
            clipBehavior: Clip.none,
            children: <Widget>[
              // ① 胶囊：与标准档同一份配方（模糊 + tint + 描边）。
              //
              // 底栏（`refract: true`）把「模糊」换成「模糊 + 边缘折射」
              // （`GlassRefract`）—— 容器边缘那一圈会把背景弯掉，这才是「一块有
              // 厚度的玻璃」与「一块磨砂纸」的分别。三道闸门不过时它退化成同一个
              // `GlassBlur`，所以换与不换只差真机上的那一层。
              //
              // 分段器 / 开关不换：理由见 [refract] 的说明。
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(capsuleH / 2),
                  child: refract
                      ? GlassRefract(
                          // 折射档的模糊比标准档小一半：折射要有结构才看得见，
                          // 理由见 [AppTokens.navRefractSigma]。
                          sigma: AppTokens.navRefractSigma,
                          size: size,
                          radius: capsuleH / 2,
                          child: _capsule(isDark, capsuleH),
                        )
                      : GlassBlur(
                          sigma: AppTokens.blurPanel,
                          child: _capsule(isDark, capsuleH),
                        ),
                ),
              ),
              // ①c 轨道着色（开关的「已打开」）。压在边光**之下**、透镜**之上**
              // 都不是——它要盖住胶囊的底色、又不该盖住边光与透镜，所以放这里。
              //
              // **必须挂在 `ListenableBuilder` 底下**：它每帧都在变（跟着滴走），
              // 而 `LiquidTrack.build()` 只在档位 / 参数变化时重跑。
              if (trackTint != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ListenableBuilder(
                      listenable: controller,
                      builder: (BuildContext context, Widget? _) {
                        final double t = slots <= 1
                            ? 0.0
                            : ((controller.position - 0.5) / (slots - 1))
                                .clamp(0.0, 1.0);
                        final Color? c = trackTint!(t);
                        if (c == null || c.a == 0) {
                          return const SizedBox.shrink();
                        }
                        return CustomPaint(
                          painter: _TrackTintPainter(
                            color: c,
                            radius: capsuleH / 2,
                            progress: t,
                            ramp: itemW,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              // ①b 边光。**不挂在 `ListenableBuilder` 底下** —— 它不读 [controller]
              // （「光跟随滑块」那条亮带 v0.10.11 拆掉了），挂上去只是每帧白重建一个
              // `CustomPaint`。
              //
              // ⚠️ **底栏这一档不叠它**（`refract` 开着时）。底栏另有一层「厚玻璃」
              // 边光 `_CapsuleEdgePainter`（见 `_capsule` 的 foregroundPainter），
              // 两圈画在同一处会相加：v0.12.9 实测合成约 0.97 的白，真机上沿 249
              // 压在 47 的底色上（差 202 级），用户报「太亮、刺眼」。
              // 分段器与开关**没有**第二层，它们照旧只有这一圈，一个像素不变。
              if (!refract)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: CapsuleRimPainter(
                        radius: capsuleH / 2,
                        isDark: isDark,
                        compact: true,
                      ),
                    ),
                  ),
                ),
              // ② 透镜。
              Positioned.fill(
                child: IgnorePointer(
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (BuildContext context, Widget? _) {
                      final double lift = controller.lift;
                      // ⚠️ **彩边与折射是两件事，别再让它们互相让位**（2026-11-05 用户
                      // 原话「底栏那个彩色边缘没有了」）。
                      //
                      // 曾经的写法是「折射活着 → 彩边让位」，理由是「真 iOS 的玻璃几乎
                      // 没有虹彩」。实测下来那是错的：折射带只有边缘那一圈几像素、
                      // 而且 Skia 回落的机器上根本没有（`ImageFilter.shader` 在 Skia 上
                      // 直接抛，见 `glass_refraction.dart` 里「程序就绪不等于这条链能用」），
                      // 于是那枚滴拖动时只剩白芯与折边 —— 用户看到的就是「彩色边没了」。
                      // 现在两件都画：折射负责「背后的东西被弯一点」，彩边负责「方向感」。
                      return LiquidLens(
                        size: size,
                        outline: LiquidLensShape.of(
                          itemW: itemW,
                          capsuleH: capsuleH,
                          pad: pad,
                          // 弹簧存的是**中心**（静止时 = 格号 + 0.5），形状要的是左缘。
                          centerPage: controller.position - 0.5,
                          lift: lift,
                          velocity: controller.velocity,
                          stretch: controller.stretch,
                          motion: controller.motion,
                          metrics: metrics,
                        ),
                        lift: lift,
                        isDark: isDark,
                        accent: accent,
                        fill: fill,
                        showRingCore: showRingCore,
                        showRefractedEdge: showRefractedEdge,
                        // 由调用方决定画不画（`glass_nav_bar` 传 true、分段器 / 开关
                        // 保持各自的默认）。**这里不再读 `liquidRefractionEnabled`** ——
                        // 那条闸门管的是「折射活没活着」，不是「要不要彩边」。
                        spectral: spectral,
                      );
                    },
                  ),
                ),
              ),
              // ③ 内容 + 手势。
              Positioned.fill(
                child: clipContent
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(capsuleH / 2),
                        child: content,
                      )
                    : content,
              ),
            ],
          );
        },
      ),
    );
  }

  /// 胶囊本身（tint + 描边）。模糊与折射两档共用这一份 —— 换档只换外面那层滤镜。
  ///
  /// **对角轴**（不是竖直）—— 与底栏标准档、以及抽这一层之前的液态档逐字一致。
  /// 写反了的症状是深色下胶囊的着色差一档（深色那两档 navFill 的 alpha 差得更大），
  /// 出图逐像素比会当场照出来。
  Widget _capsule(bool isDark, double capsuleH) {
    // 厚边只给底栏那一档：分段器 / 开关保持原样（「一个像素没动」那条验收）。
    return CustomPaint(
      foregroundPainter: refract
          ? _CapsuleEdgePainter(radius: capsuleH / 2, isDark: isDark)
          : null,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(capsuleH / 2),
          border: Border.all(color: AppTokens.navBorder(isDark)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppTokens.navFill(isDark),
          ),
        ),
      ),
    );
  }
}

/// 胶囊那一圈「有厚度的玻璃」——**纯画出来的**，不碰背景。
///
/// 为什么不用背景折射（`GlassRefraction`）承担这一层：那套依赖
/// `FlutterFragCoord` 与 `uSize` 的坐标空间，而真机实测这两者互不自洽
/// （`uSize` 报的是纹理像素、`FlutterFragCoord` 走的却是另一套比例），
/// 于是几何永远对不上，画出来与纯模糊没有分别。**厚度感真正来自这几道描边**
/// —— 它们只用控件自己的尺寸，与渲染后端无关，逐像素可测。
///
/// 层序（由外到内）：厚度暗边 → 主边光 → 冷暖两道的色散细边。
/// 光一律从左上打过来，亮度沿对角轴衰减 —— 与 `accentGradient` 同一个方向，
/// 于是整块玻璃的受光是一致的。
class _CapsuleEdgePainter extends CustomPainter {
  const _CapsuleEdgePainter({required this.radius, required this.isDark});

  final double radius;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect rect = Offset.zero & size;
    // 光从**正上方**打过来：竖直轴、上亮下暗。
    //
    // 为什么不是对角轴（`topLeft → bottomRight`）：胶囊是 6:1 的长条，对角轴在它
    // 上面几乎就是水平的，于是退化成「左端纯白、右端 10% 黑」—— 那条坑
    // `glass_tier_test.dart` 里有专门一条用例守着（左右两条边必须同值）。
    final Shader light = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: AppTokens.capsuleEdgeRim(isDark),
    ).createShader(rect);

    Path ring(double depth) => Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(depth),
          Radius.circular((radius - depth).clamp(0.0, radius)),
        ),
      );

    // ① 厚度：内圈一道很淡的暗边，把「玻璃有厚度」压出来
    canvas.drawPath(
      ring(AppTokens.capsuleEdgeShadowDepth),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppTokens.capsuleEdgeShadowWidth
        ..color = AppTokens.capsuleEdgeShadow(isDark)
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          AppTokens.capsuleEdgeShadowBlur,
        ),
    );

    // ② 主边光：上沿最亮，下沿几乎看不见
    canvas.drawPath(
      ring(AppTokens.capsuleEdgeRimDepth),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppTokens.capsuleEdgeRimWidth
        ..shader = light,
    );
    // ②b 光晕：同一条边再模糊一层 —— 玻璃的边才有厚度，而不是一根线
    canvas.drawPath(
      ring(AppTokens.capsuleEdgeRimDepth),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppTokens.capsuleEdgeGlowWidth
        ..shader = light
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          AppTokens.capsuleEdgeGlowBlur,
        ),
    );

    // ③ 色散：冷暖两道细边错开半像素
    canvas.drawPath(
      ring(AppTokens.capsuleEdgeWarmDepth),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppTokens.capsuleEdgeFringeWidth
        ..color = AppTokens.capsuleEdgeWarm(isDark),
    );
    canvas.drawPath(
      ring(AppTokens.capsuleEdgeCoolDepth),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppTokens.capsuleEdgeFringeWidth
        ..color = AppTokens.capsuleEdgeCool(isDark),
    );
  }

  @override
  bool shouldRepaint(_CapsuleEdgePainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.isDark != isDark;
}

class _TrackTintPainter extends CustomPainter {
  const _TrackTintPainter({
    required this.color,
    required this.radius,
    required this.progress,
    required this.ramp,
  });

  final Color color;
  final double radius;
  final double progress;

  /// 过渡带宽度（取**一个格**宽）。
  final double ramp;

  @override
  void paint(Canvas canvas, Size size) {
    final double edge = -ramp + (size.width + 2 * ramp) * progress;
    final Paint paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(edge - ramp / 2, 0),
        Offset(edge + ramp / 2, 0),
        <Color>[color, color.withValues(alpha: 0)],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_TrackTintPainter old) =>
      old.color != color ||
      old.progress != progress ||
      old.ramp != ramp ||
      old.radius != radius;
}
