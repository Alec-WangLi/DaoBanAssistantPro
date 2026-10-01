// app/test/calendar_lens_test.dart
//
// `CalendarLens` 是日历那枚液态玻璃块的全部：升程弹簧、环的弹簧、速度低通与 ticker
// 都关在里面，外面只喂三个数（在哪儿 / 按住没有 / 拖动速度）。这里钉它的**几何**。
//
// ⚠️ 一律走几何与帧调度，**不拿光栅亮度当判据**：那枚块压在白色卡片上，
// 亮度差被卡片自己的底色吃掉（日历页那条「缝隙量不出来」的教训）。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens_metrics.dart';
import 'package:shiftassistantpro/features/calendar/calendar_lens.dart';

void main() {
  const Size box = Size(56.6, 85); // 400dp 宽屏上的格子
  const double innerH = 85 - 2 * AppTokens.gapHair; // 内盒高

  Future<void> mount(
    WidgetTester tester, {
    required double liftTarget,
    bool dragging = false,
    Offset velocity = Offset.zero,
  }) async {
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
        child: SizedBox(
          width: box.width,
          height: box.height,
          child: CalendarLens(
            size: box,
            liftTarget: liftTarget,
            dragging: dragging,
            velocity: velocity,
            isDark: false,
            accent: const Color(0xFF4C8DFF),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  LiquidLens lensOf(WidgetTester tester) =>
      tester.widget<LiquidLens>(find.byType(LiquidLens));
  LiquidLensShape shapeOf(WidgetTester tester) => lensOf(tester).shape;

  testWidgets('静止：透镜正好覆盖格子内盒，升程为 0', (tester) async {
    await mount(tester, liftTarget: 0);
    expect(lensOf(tester).lift, closeTo(0, 0.01));
    expect(shapeOf(tester).height, closeTo(innerH, 0.01));
    expect(shapeOf(tester).width, closeTo(box.width - 2 * AppTokens.gapHair, 0.01));
    expect(shapeOf(tester).motion, closeTo(0, 0.01));
  });

  testWidgets('按住：凸出**加在压扁之后**，加的量恰好是 2 × protrude',
      (tester) async {
    // v0.10.6 那条乘法顺序的坑：`(基准 + 2·凸出·lift) × (1 − 压扁)` 会把凸出也压掉 ——
    // 按住时透镜整个沉回格子里，「按住」这个动作的全部读感就没了。
    //
    // ⚠️ **判据得比在「压扁之后的那条基准」上**，不能比在内盒高上：速度一上来基准
    // 本来就该变矮（那是形变，不是 bug）。内盒高只对零速度成立。
    for (final Offset v in <Offset>[Offset.zero, const Offset(900, 0)]) {
      await mount(tester, liftTarget: 1, dragging: true, velocity: v);
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final LiquidLens lens = lensOf(tester);
      // ⚠️ 基准要用**形状自己那一份形变强度**：外面喂进来的速度会先过一次低通，
      // 拿原始采样去反推会差一档（900 进来的实际是 0.9，不是 1.0）。
      final double base =
          innerH * (1 - AppTokens.lensSquash * lens.shape.stretch);
      expect(
        lens.shape.height - base,
        closeTo(2 * CalendarLens.protrude * lens.lift, 0.6),
        reason: '凸出被形变吃掉了（速度 $v）—— v0.10.6 那条乘法顺序的坑',
      );
    }
  });

  test('负升程（落定的过冲）不会把形状画崩', () {
    // 落定那一下升程会短暂走到 0 以下（Unlift 是欠阻尼的）。实测**只到 −0.006** ——
    // `LiquidLensSpring.isAtRest` 的门（|位移| < 0.01）在真正的最低点之前就把它停了，
    // 所以肉眼看不到「缩了一下」（放大 12 倍也只有 0.07px）。
    // 这里直接把负升程喂进形状，钉住那条路径不会画出非法轮廓。
    final LiquidLensShape sh = LiquidLensShape.of(
        itemW: 52,
        capsuleH: 85,
        pad: AppTokens.gapHair,
        centerPage: 0,
        lift: -0.05,
        velocity: 0,
        stretch: 0,
        cornerR: AppTokens.radiusM,
        // 用日历那一套（默认那套是底栏的 10 / 10）。
        metrics: const LiquidLensMetrics(
            protrude: CalendarLens.protrude,
            liftWidth: CalendarLens.liftWidth));
    final Rect b = sh.toPath().getBounds();
    expect(b.width, closeTo(52 - CalendarLens.liftWidth * 0.05, 0.01));
    expect(b.height, closeTo(81 - 2 * CalendarLens.protrude * 0.05, 0.01));
  });

  testWidgets('落定：走完整段回落，形状全程合法', (tester) async {
    await mount(tester, liftTarget: 1);
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // ⚠️ **原地重建**，不是拆了再挂：同位置同类型 → State 保住，「目标翻成 0」才走得到
    // Unlift 那条弹簧的下落。（拆树重挂会让升程从初值重新开始，这条就测不到下落。）
    await mount(tester, liftTarget: 0);
    double lowest = 1;
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final LiquidLens lens = lensOf(tester);
      lowest = math.min(lowest, lens.lift);
      final Rect b = lens.shape.toPath().getBounds();
      expect(b.width, greaterThan(0));
      expect(b.height, greaterThan(0));
    }
    expect(lowest, lessThan(0.5), reason: '这条没走完下落 —— 它测不到要测的那条路径');
  });

  testWidgets('静止之后没有在跑的 ticker', (tester) async {
    await mount(tester, liftTarget: 0);
    await tester.pumpAndSettle(); // 有常驻动画的话这里直接超时
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('横向速度拉宽压矮、纵向速度拉高收窄', (tester) async {
    await mount(tester,
        liftTarget: 1, dragging: true, velocity: const Offset(600, 0));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final LiquidLensShape x = shapeOf(tester);
    await mount(tester,
        liftTarget: 1, dragging: true, velocity: const Offset(0, 600));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final LiquidLensShape y = shapeOf(tester);
    expect(x.width, greaterThan(y.width), reason: '横着拖那份没有拉宽');
    expect(y.height, greaterThan(x.height), reason: '竖着拖那份没有拉高');
  });

  testWidgets('环是渐入渐出的，不是一动就满', (tester) async {
    await mount(tester,
        liftTarget: 1, dragging: true, velocity: const Offset(600, 0));
    await tester.pump(const Duration(milliseconds: 110));
    final double early = shapeOf(tester).motion;
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(early, lessThan(0.9), reason: '彩边一上来就满 —— 渐入那条弹簧没接上');
    expect(shapeOf(tester).motion, greaterThan(0.95));
  });

  testWidgets('松手之后速度衰减到 0、环熄灭（静止时一点彩色都没有）',
      (tester) async {
    await mount(tester,
        liftTarget: 1, dragging: true, velocity: const Offset(600, 0));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 松手：目标翻 0、不再喂速度（外面那一帧把最后的速度交回来）。
    await mount(tester, liftTarget: 0, velocity: const Offset(600, 0));
    for (int i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(shapeOf(tester).motion, closeTo(0, 0.02));
    expect(shapeOf(tester).width,
        closeTo(box.width - 2 * AppTokens.gapHair, 0.5));
  });
}
