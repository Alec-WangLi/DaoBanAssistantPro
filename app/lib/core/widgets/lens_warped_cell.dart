import 'package:flutter/material.dart';

import '../glass/liquid_lens.dart';
import '../glass/liquid_lens_controller.dart';

/// 「**这一格的内容被透镜边缘挤了一下**」—— 套在每一格外面的一层仿射变换。
///
/// 用户 2026-10-01：「滑块的彩虹边缘碰到图标时，图标和文字也应该适当扭曲」。
/// 底栏从 v0.10.4 起就有这段，v0.10.10 抽出来让**分段器**也用同一份 ——
/// 抄两份迟早走样，与 [LiquidLensController] 同一条理由。
///
/// 变换本身是纯函数 [lensIconWarp]，这里是它的 widget 外壳。这里只做三件事：
///
/// 1. **每帧只重建外面那层 `Transform`** —— `child` 由 `ListenableBuilder` 透传，
///    图标 / 文字那两个 widget 本身不重建（底栏那条的观感与开销都压在这上面）；
/// 2. **恒等就一层都不套** —— `Transform` 的 identity 也是要付代价的；
/// 3. 把「透镜中心在哪儿」的换算收在这里，调用点只报**这一格内容的中心**。
///
/// **它不读档位**（`liquidGlassActive`）—— 那是调用点的事，与本仓既有纪律一致。
///
/// ⚠️ **两处的坐标系不同构**，调用点报 [iconCenterX] 与 [itemW] 时要照自己那边算：
/// 底栏的格子是**内缩之后**排的（`pad + (i+0.5)×itemW`）；分段器的格子**铺满全宽**
/// （`(i+0.5)×内容宽÷格数`）。而 [itemW] 与 [lensPad] 永远是**透镜那一套**的
/// （`LiquidLensShape` 用的那个），两个数相减才有意义。
class LensWarpedCell extends StatelessWidget {
  const LensWarpedCell({
    super.key,
    required this.controller,
    required this.iconCenterX,
    required this.lensPad,
    required this.itemW,
    required this.halfWidth,
    required this.child,
  });

  final LiquidLensController controller;

  /// 这一格内容中心在**胶囊局部坐标**里的 x（与 `LiquidLensShape` 同一套坐标，
  /// 都从胶囊左缘量起，所以两个数可以直接相减）。
  final double iconCenterX;

  /// 透镜位置换算成 px 用的内边距（底栏 = `innerPad`，分段器 = `padChipV`）。
  final double lensPad;

  /// **透镜那一套**的每格宽度。
  final double itemW;

  /// 透镜的半宽，用**满升程**那个值 —— 它随升程只变 ~5%，不值得每帧再算一次；
  /// 而 `lensIconWarp` 的权重本来就是一条软的钟形。
  final double halfWidth;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      child: child,
      builder: (BuildContext context, Widget? child) {
        final ({double scaleX, double scaleY, double dx}) warp = lensIconWarp(
          iconCenterX: iconCenterX,
          lensCenterX: lensPad + controller.position * itemW,
          lensHalfWidth: halfWidth,
        );
        if (warp.scaleX == 1.0 && warp.dx == 0.0) return child!;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(warp.dx, 0, 0, 1)
            ..scaleByDouble(warp.scaleX, warp.scaleY, 1, 1),
          child: child,
        );
      },
    );
  }
}
