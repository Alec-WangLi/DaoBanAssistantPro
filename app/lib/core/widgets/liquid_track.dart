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

  /// 内容层裁在胶囊里。开着的效果与底栏标准档一致（`GestureDetector` 在 `ClipRRect`
  /// 里面，胶囊圆角外那一小块不会穿透到页面内容）。
  final bool clipContent;

  /// 叠在胶囊里的**一层纯色**。开关用它表示「已打开」（主色淡染）；
  /// 底栏与分段器不给。
  final Color? trackTint;

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
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(capsuleH / 2),
                  child: GlassBlur(
                    sigma: AppTokens.blurPanel,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(capsuleH / 2),
                        border: Border.all(color: AppTokens.navBorder(isDark)),
                        // **对角轴**（不是竖直）—— 与底栏标准档、以及抽这一层
                        // 之前的液态档逐字一致。写反了的症状是深色下胶囊的
                        // 着色差一档（深色那两档 navFill 的 alpha 差得更大），
                        // 出图逐像素比会当场照出来。
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: AppTokens.navFill(isDark),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // ①c 轨道着色（开关的「已打开」）。压在边光**之下**、透镜**之上**
              // 都不是——它要盖住胶囊的底色、又不该盖住边光与透镜，所以放这里。
              if (trackTint != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(capsuleH / 2),
                        color: trackTint,
                      ),
                    ),
                  ),
                ),
              // ①b 边光。**不挂在 `ListenableBuilder` 底下** —— 它不读 [controller]
              // （「光跟随滑块」那条亮带 v0.10.11 拆掉了），挂上去只是每帧白重建一个
              // `CustomPaint`。
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
                      return LiquidLens(
                        size: size,
                        shape: LiquidLensShape.of(
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
}
