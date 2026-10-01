// 响铃页那枚「上滑关闭」药丸的**几何**护栏（v0.10.13）。
//
// 它是一条**竖着走**的液态滴：整体转 90° 之后，局部 x = 屏幕的上下、局部 y = 屏幕的
// 左右 —— 所以这个文件里凡是读 `shape`，都要记住两个尺寸是**反的**
// （`shape.height` 是屏幕上的**宽**、`shape.width` 是屏幕上的**高**）。
//
// 这里只钉「一眼能看出来的那四件事」：凸出轨道、折边亮着、贴住轨道底、色带接得住。
// 滴本身的形状（端头半径、弦长）由 `liquid_lens_test` 那几十条守着。
//
// ⚠️ **四条全部走几何，一条都不走光栅亮度**。曾经想用「沿中轴扫一列、看有没有一段
// 暗下去」来判「色带与药丸之间有没有缝」，实测判不出来：那条缝会被药丸自己的**外溢
// 光晕**照亮（缝里 61~68，而轨道底色约 45、色带 88）—— 绝对阈值没有鉴别力。
// 换成给轨道与色带各挂一个 `Key`、直接比两条边的位置，既准又快（连光栅化都不用做）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/features/alarm/alarm_ringing_screen.dart';

import 'support/plugin_channels.dart';

void main() {
  /// 与生产代码同一批数：轨道宽 `_trackWidth`、轨道高（正常档）、药丸高 `_thumbH`。
  const double trackW = 72;
  const double trackH = 190;

  /// 装配响铃页；[dragTo] > 0 时把滑块拖到那个进度并**按住不放**。
  ///
  /// [frameStep] 决定「出帧间隔」—— 同一个手指速度下 16ms 与 8ms 各跑一遍，
  /// 用来钉「形变与帧率无关」（见最后那条用例）。
  Future<void> pumpRinging(
    WidgetTester tester, {
    double dragTo = 0,
    Size size = const Size(420, 900),
    bool liquid = true,
    Duration frameStep = const Duration(milliseconds: 16),
  }) async {
    liquidGlassActive.value = liquid;
    addTearDown(() => liquidGlassActive.value = false);
    stubPluginChannels();

    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AlarmRingingScreen(label: '早班'),
    ));
    // 逐帧推：入场动画 650ms，推够 1.3 秒。
    for (int i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    if (dragTo <= 0) return;

    final TestGesture g = await tester
        .startGesture(tester.getRect(find.byType(LiquidLens)).center);
    addTearDown(g.up);
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16)); // 过按住闸门
    }
    // ⚠️ 前 18px（`kTouchSlop`）是空走的：总位移要算成 `18 + 轨道高 × 进度`。
    final double total = 18 + trackH * dragTo;
    // 步数按「总时长固定 640ms」折算 —— 这样 16ms 与 8ms 出帧是**同一个手指速度**，
    // 只有帧率不同（那才是要量的东西）。
    final int steps =
        (640 / frameStep.inMilliseconds).round(); // 16ms → 40；8ms → 80
    for (int i = 0; i < steps; i++) {
      await g.moveBy(Offset(0, -total / steps));
      await tester.pump(frameStep);
    }
  }

  LiquidLensShape shapeOf(WidgetTester tester) =>
      tester.widget<LiquidLens>(find.byType(LiquidLens)).shape;

  /// 药丸在**屏幕上**的底边（转 90° 之后，屏幕上的高 = 局部的宽）。
  double pillBottom(WidgetTester tester) =>
      tester.getRect(find.byType(LiquidLens)).center.dy + shapeOf(tester).width / 2;

  testWidgets('按住：药丸凸出轨道两边（屏幕上的宽 > 轨道的宽）', (tester) async {
    await pumpRinging(tester, dragTo: 0.5);
    expect(tester.widget<LiquidLens>(find.byType(LiquidLens)).lift,
        greaterThan(0.9),
        reason: '前提错了：还没提起来');
    // 转 90° 之后 `shape.height` 是**屏幕上的宽**。
    expect(shapeOf(tester).height, greaterThan(trackW),
        reason: '按住时药丸没有凸出轨道（${shapeOf(tester).height} vs $trackW）—— '
            '用户：「长按它放大后应该是大过下面的滑轨吧？」');
  });

  testWidgets('按住：轨道那两条边被折进透镜里（折边不是 null）', (tester) async {
    await pumpRinging(tester, dragTo: 0.5);
    final e = refractedCapsuleEdge(shapeOf(tester));
    expect(e, isNotNull, reason: '折边算出来是 null —— 轨道那两条边没被折进来');
    expect(e!.fade, greaterThan(0));
  });

  testWidgets('静止：药丸的底边就是轨道的底边（不浮在上面）', (tester) async {
    await pumpRinging(tester);
    final Rect track =
        tester.getRect(find.byKey(const Key('ring-dismiss-track')));
    final double bottom = pillBottom(tester);
    expect((bottom - track.bottom).abs(), lessThan(1.5),
        reason: '药丸浮在轨道底上方 ${track.bottom - bottom}px');
  });

  testWidgets('拖动中：色带接得住药丸（中间的缝 ≤ 1px）', (tester) async {
    await pumpRinging(tester, dragTo: 0.5);
    final Rect fill =
        tester.getRect(find.byKey(const Key('ring-dismiss-fill')));
    final double bottom = pillBottom(tester);
    expect(fill.top, lessThanOrEqualTo(bottom + 1),
        reason: '色带的上沿（${fill.top}）在药丸底边（$bottom）下面 '
            '${fill.top - bottom}px —— 中间空了一段');
  });

  testWidgets('小窗档（200×400）：仍然凸出、仍然折边', (tester) async {
    // 矮屏那一档药丸是 46 宽（`_thumbWShort`），比正常档窄 6px —— 而凸出量还是每侧 16，
    // 于是 46 + 32 = 78 仍然大过 72。这条钉住「小窗下也读得出凸出」。
    await pumpRinging(tester, dragTo: 0.5, size: const Size(200, 400));
    expect(shapeOf(tester).height, greaterThan(trackW),
        reason: '小窗下药丸没凸出轨道（${shapeOf(tester).height} vs $trackW）');
    expect(refractedCapsuleEdge(shapeOf(tester)), isNotNull,
        reason: '小窗下折边是 null');
  });

  testWidgets('两档是两棵树：标准档没有透镜，药丸尺寸却一模一样', (tester) async {
    // 液态档先量一份：转 90°，所以屏幕上的**宽**是 `shape.height`、**高**是 `shape.width`。
    await pumpRinging(tester);
    final LiquidLensShape liq = shapeOf(tester);
    final Size liquidSize = Size(liq.height, liq.width);

    await pumpRinging(tester, liquid: false);
    expect(find.byType(LiquidLens), findsNothing,
        reason: '标准档树上还有透镜 —— 两棵树没真的分开');
    final Rect std = tester.getRect(find.byKey(const Key('ring-dismiss-thumb')));
    expect(std.size, liquidSize,
        reason: '两档药丸尺寸不一致（标准 ${std.size} / 液态 $liquidSize）—— '
            '切档位时控件会跳一下');
  });

  // 帧率无关性：**拆成两条用例**量（同一条用例里连拖两遍会互相干扰 —— 实测两个落点
  // 差了 77px，量到的根本不是同一段位移）。
  double? stretch60;
  double? stretch120;

  testWidgets('形变 @60Hz（基准）', (tester) async {
    await pumpRinging(tester, dragTo: 0.5);
    stretch60 = shapeOf(tester).stretch;
    expect(stretch60, greaterThan(0.3),
        reason: '前提错了：这一拖根本没积起形变（$stretch60）');
  });

  testWidgets('形变 @120Hz：与 60Hz 同一个手指速度，形变该差不多', (tester) async {
    await pumpRinging(tester, dragTo: 0.5,
        frameStep: const Duration(milliseconds: 8));
    stretch120 = shapeOf(tester).stretch;
    expect(stretch60, isNotNull, reason: '基准那条没跑');
    expect((stretch60! - stretch120!).abs(), lessThan(0.12),
        reason: '同一个手指速度，60Hz 算出 $stretch60、120Hz 算出 $stretch120 —— '
            '帧率一变形变就差一档（速度还在用「每帧位移 × 60」算？）');
  });
}
