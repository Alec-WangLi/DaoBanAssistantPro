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

  /// 推 [frames] 帧，并且**每帧都把速度再喂一次**。
  ///
  /// 真机上父层每来一个指针事件就重建一次（拖动中几乎每帧一次），所以「手指在动」
  /// 在这枚块看来就是「每帧都有新采样」。用例里不喂的话，它按「手指停住了」处理 ——
  /// 那是**对的**行为（速度该自己收回去），只是不是这两条用例要测的东西。
  Future<void> dragFrames(WidgetTester tester, int frames, Offset velocity) async {
    for (int i = 0; i < frames; i++) {
      await mount(tester, liftTarget: 1, dragging: true, velocity: velocity);
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

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
    await dragFrames(tester, 20, const Offset(600, 0));
    final LiquidLensShape x = shapeOf(tester);
    await dragFrames(tester, 20, const Offset(0, 600));
    final LiquidLensShape y = shapeOf(tester);
    expect(x.width, greaterThan(y.width), reason: '横着拖那份没有拉宽');
    expect(y.height, greaterThan(x.height), reason: '竖着拖那份没有拉高');
  });

  testWidgets('环是渐入渐出的，不是一动就满', (tester) async {
    await mount(tester,
        liftTarget: 1, dragging: true, velocity: const Offset(600, 0));
    await tester.pump(const Duration(milliseconds: 110));
    final double early = shapeOf(tester).motion;
    await dragFrames(tester, 20, const Offset(600, 0));
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

  // ── 速度是外面喂进来的，而外面那份**松手之后就不再更新了** ────────────────
  //
  // 这两条是独立审查抓出来的：父层那份 `_vx/_vy` 在松手之后**故意不归零**
  // （要留给这枚块自己衰减），但它会**在每一次重建时**被原样传进来 ——
  // 于是「拖完再点一下日期」那一帧，陈旧的速度会被重新灌回来，
  // 那枚块自己拉长一下、彩边再亮一下（点按是日历上最常见的动作）。
  testWidgets('松手之后再重建（下一次点按）不会把陈旧的速度灌回来', (tester) async {
    await mount(tester,
        liftTarget: 1, dragging: true, velocity: const Offset(600, 0));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 松手那一帧：父层把最后的速度交回来（它不会归零）。
    await mount(tester, liftTarget: 0, velocity: const Offset(600, 0));
    for (int i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(shapeOf(tester).motion, closeTo(0, 0.02), reason: '前提：这时该已经熄了');

    // 下一次点按：父层照旧把那一栏**陈旧**的速度传进来。
    await mount(tester, liftTarget: 0, velocity: const Offset(600, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(shapeOf(tester).width,
        closeTo(box.width - 2 * AppTokens.gapHair, 1),
        reason: '陈旧的速度被重新灌回来了 —— 点一下日期，那枚块会自己拉长一下');
  });

  testWidgets('按住不动（没有新的速度采样）时，形变自己收回去', (tester) async {
    // 量的是 `stretch`（形变强度）而不是宽度：宽度里还叠着按住那 12px 的鼓出，
    // 那点余量会把这条的鉴别力吃掉。
    await mount(tester,
        liftTarget: 1, dragging: true, velocity: const Offset(600, 0));
    await tester.pump(const Duration(milliseconds: 16));
    final double early = shapeOf(tester).stretch;
    expect(early, greaterThan(0.4), reason: '前提：刚喂过速度，形变该起来了');
    // 之后一帧采样都不来：手指按在原地，指针事件不再产生。
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(shapeOf(tester).stretch, lessThan(early - 0.2),
        reason: '手指停住了，形变却一直挂着 —— 速度没有随时间衰减');
  });
}
