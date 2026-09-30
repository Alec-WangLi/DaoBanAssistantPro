// 透镜的弹簧解算器。
//
// 为什么不用 `TweenAnimationBuilder`：透镜要的不是「从 A 到 B 的一段补间」，
// 而是两样补间给不了的东西 ——
//   · **速度**：拖动时形状要跟着速度拉伸（Q 弹），速度得从解算器里读；
//   · **过冲**：松手落回格子那一下要越过一点再回来，那才是「Q 弹」。
//
// 纯 Dart、没有 widget 依赖，所以可以直接跑 200 步去断言它的行为。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';

void main() {
  test('收敛：从中点出发最终停到目标上', () {
    final s = LiquidLensSpring(target: 100)..value = 0;
    for (int i = 0; i < 200; i++) {
      s.step(const Duration(milliseconds: 16));
    }
    expect(s.value, closeTo(100, 0.5));
    expect(s.isAtRest, isTrue);
  });

  test('过冲：落回时越过目标再回来（这就是 Q 弹的观感来源）', () {
    final s = LiquidLensSpring(target: 100)..value = 0;
    double peak = 0;
    for (int i = 0; i < 200; i++) {
      s.step(const Duration(milliseconds: 16));
      if (s.value > peak) peak = s.value;
    }
    expect(peak, greaterThan(101),
        reason: '没有过冲 —— 那和 easeOut 没有区别，松手那一下就不会有 Q 弹感');
    expect(peak, lessThan(140), reason: '过冲太大（>40%），读起来是「甩过头」');
  });

  test('不发散：目标半路被改写也不炸', () {
    final s = LiquidLensSpring(target: 100);
    for (int i = 0; i < 5; i++) {
      s.step(const Duration(milliseconds: 16));
    }
    s.target = -100; // 连点另一格
    for (int i = 0; i < 200; i++) {
      s.step(const Duration(milliseconds: 16));
    }
    expect(s.value, closeTo(-100, 0.5));
  });

  test('帧间隔封顶：喂一个 1 秒的 dt，位移不超过按 maxStep 算出来的那一步', () {
    final capped = LiquidLensSpring(target: 100)..step(LiquidLensSpring.maxStep);
    final huge = LiquidLensSpring(target: 100)..step(const Duration(seconds: 1));
    expect(huge.value, closeTo(capped.value, 1e-9),
        reason: '掉帧时按真实 dt 积分会让透镜瞬移，还会把数值积爆');
  });

  test('落回时间与标准档的 durFast 相当', () {
    // 这一条钉的是**用户 2026-10-01 反馈的第 6 条**：「滑块的吸附速度很僵硬，
    // 没有之前标准磨砂玻璃状态下那种缓慢优雅」—— 标准档滑过去用的就是
    // `durFast`。弹簧的落回时间必须与它相当，慢出一截就是那条反馈回头。
    //
    // 它同时也是那两个参数的**唯一**有效护栏：`design_tokens` 里那张表是按
    // 「与实现同一套离散格式」扫出来的，连续解的理论公式在这儿会把人带偏
    // （照理论填的 ω=46.3 / ζ=0.72 过冲实测是 0）。
    final s = LiquidLensSpring(target: 100)..value = 0;
    final int steps = AppTokens.durFast.inMilliseconds ~/ 16;
    for (int i = 0; i < steps; i++) {
      s.step(const Duration(milliseconds: 16));
    }
    expect((s.value - 100).abs() / 100, lessThan(0.05),
        reason: '过了 durFast（${AppTokens.durFast.inMilliseconds}ms）还差得远 —— '
            '吸附会比标准档慢一截');
  });
}
