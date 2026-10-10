import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/frame_notifier.dart';
import '../../core/glass/liquid_lens.dart';

/// 这一格的**内容**被透镜边缘挤成什么样 —— 液态档才有。
///
/// 用二维版 `lensIconWarp2d`（一维版只认 x，给底栏 / 分段器那种「一排」的控件）。
///
/// ⚠️ 半宽半高取**静止那一档**（内盒的一半），**不是**「满升程 + 满形变」那一档。
/// 一维版那边两者只差约 5%（照最大值取无所谓），而这里从静止到满形变，透镜的宽会从
/// 52 涨到 74（**+43%**）—— 照最大值取的话，`t` 会把**静止时**的相邻格子也算成
/// 「在透镜里」，于是日历的常态画面上就带着一层变形（**逐张比基线时当场抓到的**：
/// 差异掩码里相邻两格的字整片亮起）。照静止那一档取，静止时相邻格子 `t ≈ 2.2`、
/// 权重见底、一层都不套；拖动到两格之间时 `t ≈ 1.08`、权重 ≈ 0.97 —— 正好。
///
/// 恒等时返回 `null`：调用点据此**一层恒等的 `Transform` 都不套**（它也是要付代价的）。
///
/// [inset] 就是屏幕那个 `_cellInset`（格子与玻璃块统一内缩）—— 它住在界面层，
/// 所以由调用点传进来，不从这一层去猜。
Matrix4? cellWarpFor({
  required Offset cellCenter,
  required Offset lensCenter,
  required double cellW,
  required double cellH,
  required double inset,
}) {
  final double hw = (cellW - 2 * inset) / 2;
  final double hh = (cellH - 2 * inset) / 2;
  final ({double scaleRadial, double scaleTangent, double dx, double dy,
      double angle}) w = lensIconWarp2d(
    itemCenterX: cellCenter.dx,
    itemCenterY: cellCenter.dy,
    lensCenterX: lensCenter.dx,
    lensCenterY: lensCenter.dy,
    lensHalfWidth: hw,
    lensHalfHeight: hh,
  );
  if (w.scaleRadial == 1.0 && w.dx == 0.0 && w.dy == 0.0) return null;
  // 沿径向压扁、垂直方向拉长，再朝远离透镜中心的方向推一点。
  return Matrix4.identity()
    ..translateByDouble(w.dx, w.dy, 0, 1)
    ..rotateZ(w.angle)
    ..scaleByDouble(w.scaleRadial, w.scaleTangent, 1, 1)
    ..rotateZ(-w.angle);
}

/// 把「被透镜挤」这件事挂在**某一格的内容**上。
///
/// **它只重算矩阵，不重建内容。** 那一层 42 格的每帧重建（实测 436 个 widget/帧）
/// 就是这么消掉的：透镜每帧都在动，而格子内容（三行字 + 班次胶囊 + 卡片装饰）跟它
/// 一点关系都没有 —— 把内容当 `child` 传进 `ValueListenableBuilder`，`child` 是同一个
/// 实例，元素不会重建，重建的只有那个闭包与一个 `Transform`。
///
/// ⚠️ **别把内容写成 builder 里的临时变量** —— 那等于每帧重建整格，正是要消掉的东西
/// （`lens_warp_scope_test.dart` 里「格子内容一次都不重建」那条钉着它）。
///
/// ⚠️ **它不读档位**（`liquidGlassActive`）—— 标准档压根不该套这一层，判据归调用点
/// （`calendar_screen.dart` 在名单里，这个文件不在）。
///
/// ⚠️ 底下走的是 [FrameBuilder] 而不是 `ValueListenableBuilder` —— 后者把值缓存在
/// State 里、只靠 listener 刷新，于是**静默写**（帧内、布局阶段那一处）写进去的中心
/// 它看不到。理由与现场在 `frame_notifier.dart` 与 `frame_notifier_test.dart` 里。
class LensWarpScope extends StatelessWidget {
  const LensWarpScope({
    super.key,
    required this.center,
    required this.cellCenter,
    required this.cellW,
    required this.cellH,
    required this.inset,
    required this.child,
  });

  /// 这一帧挤压场的中心（`null` = 一层都不套）。
  ///
  /// 用 [ValueListenable] 而不是 `Offset?`：父层每帧写它，而写在 `LayoutBuilder`
  /// 的**布局阶段**那一处只能走「静默写」（见 [FrameNotifier]）。
  final ValueListenable<Offset?> center;

  /// 这一格的中心（格层坐标）。
  final Offset cellCenter;

  final double cellW;
  final double cellH;

  /// 格子与玻璃块统一内缩（`AppTokens.gapHair`）。
  final double inset;

  /// 已经建好的格子内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FrameBuilder<Offset?>(
      listenable: center,
      child: child,
      builder: (BuildContext context, Offset? c, Widget? child) {
        if (c == null) return child!;
        final Matrix4? m = cellWarpFor(
          cellCenter: cellCenter,
          lensCenter: c,
          cellW: cellW,
          cellH: cellH,
          inset: inset,
        );
        return m == null
            ? child!
            : Transform(
                alignment: Alignment.center, transform: m, child: child);
      },
    );
  }
}
