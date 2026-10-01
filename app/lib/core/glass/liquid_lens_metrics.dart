import '../design_tokens.dart';

/// 透镜在**升程满档**时的两个外扩量（逻辑 px）。
///
/// 它们是**每个面各自的观感**，不是全局常量 —— 底栏那套（`navLensProtrude = 10` /
/// `lensLiftWidth = 10`）是照 **64 高**的胶囊量的：在那种比例下「上下各探出 4」读作
/// 「鼓出来一点点」。同样两个数搬到 40 高的分段器、28 高的开关上，就变成「整个胀到
/// 外面」（样图里实测过）。
///
/// 而开关要的更不是等比例 —— 用户 2026-10-01 的原话是「往纵向放大，参考 iOS 26 他们
/// 的开关液态玻璃那种形状变化」，所以它传 `protrude: 8, liftWidth: 0`：**只长个儿，
/// 不变宽**。这种「两个方向各自多少」的表达能力，就是这两个数必须成为参数的理由。
class LiquidLensMetrics {
  const LiquidLensMetrics({required this.protrude, required this.liftWidth});

  /// 按胶囊高度取默认值。
  ///
  /// ⚠️ **底栏不要用它。** 底栏那两个数是**冻住的**（两个高度都用 10 / 10）：
  /// 矮屏那一档胶囊只有 52 高，跟着高度取会变成 8.1，横屏与小窗两档的画面就变了
  /// —— 而「底栏逐像素不变」是抽共享件这一路的验收。护栏在
  /// `test/liquid_lens_test.dart` 的「几何默认值 = 底栏那档」。
  factory LiquidLensMetrics.forCapsule(double capsuleH) => LiquidLensMetrics(
        protrude: capsuleH * AppTokens.lensLiftRatio,
        liftWidth: capsuleH * AppTokens.lensLiftRatio,
      );

  /// 满升程时**纵向每侧**探出多少。
  final double protrude;

  /// 满升程时**横向总共**外扩多少。**可以为负** —— 负值 = 边被抽长边收窄
  /// （像一滴被拉起来的水）。
  final double liftWidth;
}
