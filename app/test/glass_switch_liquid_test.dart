// `GlassSwitch` 接上液态档之后的护栏。
//
// 「关掉液态档时与改之前逐像素相同」不在这里验 —— 开关长在七个界面里，那条由
// `tool/visual` 的整屏逐像素比兜着。这里钉几件单屏照不出来的事。
//
// v0.10.10 把「按住时只往纵向拉长」换成了「与底栏 / 分段器同一套升程」，所以
// 第二条**从「宽度不变」翻成了「宽度也要长」** —— 那不是放松，是设计改了
// （用户 2026-10-01：「你参考底部导航栏那个滑块……还是优先把它统一起来」）。
//
// 几条都走**几何与配置**断言（`LiquidLens.shape` / `showRingCore` / `fill`），
// 不光栅化：那几件事在这里是「接线对不对」，形状与配色本身由 `liquid_lens_test`
// 那 60 多条守着。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';

void main() {
  /// 返回**这次会话里 `onChanged` 收到的值**（拨了几次、拨成什么）。
  Future<List<bool>> pumpSwitch(
    WidgetTester tester, {
    required bool liquid,
    bool value = false,
    bool enabled = true,
  }) async {
    final List<bool> calls = <bool>[];
    liquidGlassActive.value = liquid;
    addTearDown(() => liquidGlassActive.value = false);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Center(
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => GlassSwitch(
              value: value,
              enabled: enabled,
              onChanged: (bool v) {
                calls.add(v);
                setState(() => value = v);
              },
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return calls;
  }

  LiquidLens lensOf(WidgetTester tester) =>
      tester.widget<LiquidLens>(find.byType(LiquidLens));

  testWidgets('静止：钮是一枚圆球（宽 ≈ 高），坐在轨道里', (tester) async {
    await pumpSwitch(tester, liquid: true);
    // 轨道 56×30、内缩 3 → 每格 (56−6)/2 = 25；钮高 = 30−6 = 24
    expect(lensOf(tester).shape.width, closeTo(25, 0.5));
    expect(lensOf(tester).shape.height, closeTo(24, 0.5));
    expect((lensOf(tester).shape.width - lensOf(tester).shape.height).abs(),
        lessThan(2.5),
        reason: '静止时钮不是圆的 —— 共享件把它变成了胶囊');
  });

  testWidgets('按住：钮**纵横一起长**（与底栏 / 分段器同一套升程）', (tester) async {
    // v0.10.9 那一版是「只长个儿、不变宽」（用户当时要的「参考 iOS 26 往纵向放大」）。
    // 2026-10-01 他自己推翻了：「你参考底部导航栏那个滑块……还是优先把它统一起来」。
    // 所以这一条现在要求**两个方向都长**，反向的那条（宽度不变）已作废删掉。
    await pumpSwitch(tester, liquid: true);
    final Size before =
        Size(lensOf(tester).shape.width, lensOf(tester).shape.height);

    final Rect box = tester.getRect(find.byType(GlassSwitch));
    final TestGesture g = await tester.startGesture(box.center);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16)); // 320ms，过按住闸门
    }

    final Size after =
        Size(lensOf(tester).shape.width, lensOf(tester).shape.height);
    expect(after.height, greaterThan(30),
        reason: '按住之后钮没有高过轨道（${after.height}）—— 没有「被抽出来」');
    expect(after.height, greaterThan(before.height + 4));
    expect(after.width, greaterThan(before.width + 2),
        reason: '宽度没长（${before.width} → ${after.width}）—— 那还是「只长个儿」');
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('钮是**主色玻璃滴**，不是白球（与分段器那枚要同一件东西）', (tester) async {
    // 用户 2026-10-01：「颜色变浅了，尤其是跟主题模式等，有明显的颜色差别。
    // 理论上它们应该都是一样的」—— 原来钮是 `fill: [white, white]`，
    // 材质与分段器那枚主色滴根本不同，整条轨道读起来就淡一档。
    //
    // `fill == null` 就是「没覆盖，用默认的 `accentGradient`」—— 这一条断言的是
    // 接线，不是像素；白色渐变在这里会当场红。
    await pumpSwitch(tester, liquid: true);
    expect(lensOf(tester).fill, isNull,
        reason: '钮的填充被写死了 —— 它应当是默认的主色渐变');
  });

  testWidgets('白芯是关掉的（它在小钮上会渲成一道横穿钮身的白线）', (tester) async {
    // v0.10.9 关掉白芯的理由是「白上画白等于没画」，那只覆盖了**白钮那一档**；
    // 钮一改成主色，白芯就回来了 —— 而且在小钮上它渲成一道横穿钮身的白线。
    // 判据按**控件尺寸**，与钮是什么颜色无关。
    await pumpSwitch(tester, liquid: true);
    expect(lensOf(tester).showRingCore, isFalse,
        reason: '白芯开着 —— 在小钮上它是一道横穿钮身的白线');
  });

  testWidgets('置灰：即使液态档开着也走标准档那棵（树上没有透镜）', (tester) async {
    // 「这台机器打不开那个效果」与「那个效果作用于哪里」无关 —— 低内存机器上
    // 「我的 → 外观 → 液态玻璃」那一行仍然是灰的。
    await pumpSwitch(tester, liquid: true, enabled: false);
    expect(find.byType(LiquidLens), findsNothing,
        reason: '置灰态跟着液态档一起换树了');
  });

  testWidgets('标准档：树上没有透镜（两棵树真的分开了）', (tester) async {
    await pumpSwitch(tester, liquid: false);
    expect(find.byType(LiquidLens), findsNothing);
  });

  // ── 拖动（v0.10.10）─────────────────────────────────────────────────────
  //
  // 用户 2026-10-01：「长按想拖动的时候，它拖不动，好像没有加这个动作」。
  // 原来那个 `GestureDetector` 只有 tap 三件套，一个拖动识别器都没挂。

  testWidgets('按住拖到另一端松手：值翻转', (tester) async {
    final List<bool> calls = await pumpSwitch(tester, liquid: true);
    final Rect box = tester.getRect(find.byType(GlassSwitch));
    late TestGesture g;
    bool released = false;
    g = await tester.startGesture(box.centerLeft + const Offset(18, 0));
    addTearDown(() {
      if (!released) return g.up();
      return Future<void>.value();
    });
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    // ⚠️ **要算上 `kTouchSlop`（18px）**：拖动识别器赢下竞技场之前那 18px 是空走的
    // （探针实测：+30 只有 12px 真的推到了钮上，`centerX` 15.5 → 25.5，没过中点）。
    // 拖 +50 → 有效位移 32px，钮到右端并夹住 → `_page` = 1。
    for (int i = 0; i < 20; i++) {
      await g.moveBy(const Offset(2.5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    released = true;
    await tester.pumpAndSettle();
    expect(calls, <bool>[true], reason: '拖到另一端松手没有把值拨过去');
  });

  testWidgets('按住拖一点点又拖回原处松手：值不变', (tester) async {
    final List<bool> calls = await pumpSwitch(tester, liquid: true);
    final Rect box = tester.getRect(find.byType(GlassSwitch));
    late TestGesture g;
    bool released = false;
    g = await tester.startGesture(box.centerLeft + const Offset(18, 0));
    addTearDown(() {
      if (!released) return g.up();
      return Future<void>.value();
    });
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    // 出去 25px（扣掉 slop 只剩 7px 真的推到了钮上）、再原路拖回来。
    for (int i = 0; i < 10; i++) {
      await g.moveBy(const Offset(2.5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (int i = 0; i < 10; i++) {
      await g.moveBy(const Offset(-2.5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    released = true;
    await tester.pumpAndSettle();
    expect(calls, isEmpty, reason: '拖出去又拖回来，值不该变');
  });

  testWidgets('拖到一半被系统打断（PointerCancel）：按「松手」处理，逻辑页不留残值', (tester) async {
    // 这一条的来历值得记：独立审查报「开关的 `onHorizontalDragCancel` 只调了
    // `cancel()`、没有像分段器与底栏那样 `snapTo(committed + 0.5)`，于是逻辑页
    // 会留残值，下一次拖动刚过 slop 钮就跳」。**前提是错的** —— 探针实测：
    // Flutter 的 `DragGestureRecognizer` 对**已被接受**的拖动收到 PointerCancel 时
    // 走的是 `_checkEnd()`（`_checkCancel()` 只在 `possible` 那一档，
    // 而那一档 `_dragging` 还是 false，`cancel()` 直接早退）。
    // 所以那一刻跑的是 `onHorizontalDragEnd` → `release()`，逻辑页照样被吸附。
    //
    // 于是这里钉的是**真实行为**：被打断 = 按松手处理（交出落点、提交一次），
    // 而且钮停在它该在的那一端，不是停在手指离开的位置。
    final List<bool> calls = await pumpSwitch(tester, liquid: true);
    final Rect box = tester.getRect(find.byType(GlassSwitch));
    final TestGesture g =
        await tester.startGesture(box.centerLeft + const Offset(18, 0));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    for (int i = 0; i < 20; i++) {
      await g.moveBy(const Offset(2.5, 0)); // 拖到右端
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.cancel(); // 系统手势 / 通知栏下拉
    await tester.pumpAndSettle();

    expect(calls, <bool>[true], reason: '被打断的这一次拖动没有被当成松手处理');
    // 右端那一格的格心：3 + 1.5×25 = 40.5。
    expect(lensOf(tester).shape.centerX, closeTo(40.5, 0.5),
        reason: '钮停在了手指离开的位置，而不是吸附到最近那一端');
  });

  testWidgets('点按仍然只拨一下，钮不跟着手指跑（v0.10.9 那条契约）', (tester) async {
    // 接拖动最容易把这一条弄坏：`followFinger` / `moveToSlot` 一旦放开，
    // 在**开着**的那枚开关左半边按住，钮会先跳到左边再跳回来。
    await pumpSwitch(tester, liquid: true, value: true);
    final Rect box = tester.getRect(find.byType(GlassSwitch));
    final double atRest = lensOf(tester).shape.centerX;

    final TestGesture g =
        await tester.startGesture(box.centerLeft + const Offset(10, 0));
    addTearDown(g.up);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30)); // 按住不放
    }
    // 钮心在胶囊局部坐标 3 + 1.5×25 = 40.5（右端）；左端是 3 + 0.5×25 = 15.5。
    expect(lensOf(tester).shape.centerX, closeTo(atRest, 0.5),
        reason: '在左半边按住，钮跑到左边去了 —— 它只该在值真的变了之后才滑');
    expect(atRest, greaterThan(30), reason: '前提错了：开着的时候钮应当在右端');
    // 不在这里显式松手：`addTearDown` 会收掉它（再 up 一次会撞上
    // TestGesture 的 `_isDown` 断言）。
  });
}
