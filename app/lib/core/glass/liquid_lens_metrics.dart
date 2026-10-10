import '../design_tokens.dart';

/// 透镜在**升程满档**时的两个外扩量（逻辑 px），以及**光谱层随尺寸的缩放**。
///
/// 前两个是**每个面各自的观感**，不是全局常量 —— 底栏那套（`navLensProtrude = 10` /
/// `lensLiftWidth = 10`）是照 **64 高**的胶囊量的：在那种比例下「上下各探出 4」读作
/// 「鼓出来一点点」。同样两个数搬到 40 高的分段器、30 高的开关上，就变成「整个胀到
/// 外面」（样图里实测过）。
///
/// 开关的形状在 v0.10.10 与底栏**统一**（用户 2026-10-01 拍板）：不再「只长个儿」，
/// 与另外两处一样纵横一起长。所以它现在也走 [forCapsule]。
class LiquidLensMetrics {
  const LiquidLensMetrics({
    required this.protrude,
    required this.liftWidth,
    this.rimScale = 1.0,
    this.velocityRef = AppTokens.lensVelocityRef,
  });

  /// 按胶囊高度取默认值。
  ///
  /// ⚠️ **底栏不要用它。** 底栏那两个数是**冻住的**（两个高度都用 10 / 10）：
  /// 矮屏那一档胶囊只有 52 高，跟着高度取会变成 8.1，横屏与小窗两档的画面就变了
  /// —— 而「底栏逐像素不变」是抽共享件这一路的验收。护栏在
  /// `test/liquid_lens_test.dart` 的「几何默认值 = 底栏那档」。
  factory LiquidLensMetrics.forCapsule(double capsuleH) => LiquidLensMetrics(
        protrude: capsuleH * AppTokens.lensLiftRatio,
        liftWidth: capsuleH * AppTokens.lensLiftRatio,
        rimScale: capsuleH / AppTokens.lensRimRefCapsuleH,
      );

  /// 满升程时**纵向每侧**探出多少。
  final double protrude;

  /// 满升程时**横向总共**外扩多少。**可以为负** —— 负值 = 边被抽长边收窄
  /// （像一滴被拉起来的水）。
  final double liftWidth;

  /// 四层光谱（环 / 白芯 / 两层内晕 / 外溢）与浮起阴影的**整体缩放**。
  ///
  /// **1.0 = 底栏那一档**：那四个宽度本来就是照 64 高的胶囊量的。不缩放的话，把它们
  /// 原样搬到开关上（钮的基准高只有 24）会出现「**彩边比钮还宽**」—— 用户 2026-10-01
  /// 看到的「像两个半圆一样」正是它。他更早（v0.10.8）已经说过同一条道理：
  /// 「彩边范围一旦太大，就容易造成光污染」。
  ///
  /// ⚠️ **底栏显式传 1.0、不走 [forCapsule]** —— 矮屏那一档只有 52 高，跟着缩会改到
  /// 横屏与小窗的画面。
  final double rimScale;

  /// 形变饱和的速度门（px/s）。**每面各自的数** —— 形变强度走「位置的真实帧间差分
  /// ÷ 它」，而**一格多宽**决定了同一个手势能走几帧：
  ///
  /// | 一格多宽 | 手指速度 | 走几帧 | 峰值形变 |
  /// |---|---|---|---|
  /// | 88px（底栏） | 800 px/s | 7 | 0.77 |
  /// | 88px | 1500 px/s | 4 | 0.81 |
  /// | 25px（开关） | 400 px/s | 4 | 0.27 |
  /// | 25px | 800 px/s | 2 | 0.22 |
  /// | 25px | 1500 px/s | 2 | 0.28 |
  ///
  /// **越快反而越短**（到得更早、走得更少帧）。全局那一档（900）在 25px 的轨道上
  /// 够不着：尾巴该收 35%、实际只收 10%（前缘 15.3 / 后缘 14.3，只差 1px）——
  /// 用户 2026-10-01 报的「形状完全没变」就是它。
  final double velocityRef;
}
