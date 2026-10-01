// `GlassSwitch` 接上液态档之后的护栏。
//
// 「关掉液态档时与改之前逐像素相同」不在这里验 —— 开关长在七个界面里，那条由
// `tool/visual` 的整屏逐像素比兜着。这里钉几件单屏照不出来的事。
//
// v0.10.10 把「按住时只往纵向拉长」换成了「与底栏 / 分段器同一套升程」。**2026-10-01
// 用户又推翻了那一版**（「滑块放大得也不好看……现在感觉就变成一个大圆，不是很好看，
// 还得往上下拉长一点」），答的是「右」：纵向拉长、横向只放 2px（放多了端头就快成圆）。所以第二条这一轮
// **又翻了一次**（「宽度也要长」→「纵向拉长」）—— 每次翻都是设计改了，不是放松。
//
// 几条都走**几何与配置**断言（`LiquidLens.shape` / `showRingCore` / `fill`），
// 不光栅化：那几件事在这里是「接线对不对」，形状与配色本身由 `liquid_lens_test`
// 那 60 多条守着。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens_metrics.dart';
import 'package:shiftassistantpro/core/theme/app_theme.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';
import 'package:shiftassistantpro/core/widgets/liquid_track.dart';

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

  testWidgets('开关这一枚的四个数：纵向拉长 / 收窄的彩边 / 更低的速度门', (tester) async {
    // 用户 2026-10-01 拍的板：形状那条答的是「右」（纵向拉长），
    // 彩边那条答的是「该缩小就缩小」，速度门是这一轮量出来的（见 §3.3）。
    await pumpSwitch(tester, liquid: true);
    final LiquidTrack track =
        tester.widget<LiquidTrack>(find.byType(LiquidTrack).first);
    final LiquidLensMetrics m = track.metrics!;
    expect(m.protrude, closeTo(9, 0.001));
    expect(m.liftWidth, closeTo(2, 0.001));
    expect(m.rimScale, closeTo(0.25, 0.001),
        reason: '彩边没收到与底栏同一个占比（内晕往里的厚度）');
    expect(m.velocityRef, closeTo(180, 0.001),
        reason: '速度门还是全局那一档 —— 25px 的轨道上尾巴积不起来');
  });

  testWidgets('静止：钮是一枚圆球（宽 ≈ 高），坐在轨道里', (tester) async {
    await pumpSwitch(tester, liquid: true);
    // 轨道 56×30、内缩 3 → 每格 (56−6)/2 = 25；钮高 = 30−6 = 24
    expect(lensOf(tester).shape.width, closeTo(25, 0.5));
    expect(lensOf(tester).shape.height, closeTo(24, 0.5));
    expect((lensOf(tester).shape.width - lensOf(tester).shape.height).abs(),
        lessThan(2.5),
        reason: '静止时钮不是圆的 —— 共享件把它变成了胶囊');
  });

  testWidgets('按住：钮**纵向拉长**（横向只放 2px，不是不放）', (tester) async {
    // 三段历史：v0.10.9「只长个儿、不变宽」→ v0.10.10「纵横一起长」（读起来是个
    // 大圆）→ 本轮「纵向拉长为主 + 横向只放 2px」（用户 2026-10-01 答的「右」，
    // 随后真机反馈「上下有点尖尖的」—— 端头是椭圆，宽高比越小越圆）。
    // 于是开关的升程量**与另两处分了家** —— 这是有意的设计改动，不是回归。
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
    expect(after.height, greaterThan(before.height + 12),
        reason: '纵向没拉长多少（${before.height} → ${after.height}）');
    expect(after.width, closeTo(before.width + 2, 1.0),
        reason: '横向该只放 2px（${before.width} → ${after.width}）—— '
            '放多了端头就快成圆，缩回去又会让上下更尖');
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

  // ── 轨道色跟着滴走（v0.10.13）─────────────────────────────────────────────
  //
  // 用户 2026-10-01：「开着的时候，背景是蓝色；关上的时候背景是空的……拖动的时候，
  // 能不能也把背景色的变化做出来？」原先那层色读的是 `widget.value` —— 那个值在
  // 松手那一刻才翻，于是**整段拖动颜色一动不动、松手才跳一下**（而滴还在弹簧上
  // 慢慢滑，两者根本不同步）。
  //
  // 这里量的是**光栅化像素**，不是接线：那件事的判据就是「拖动中滴左边有色、
  // 右边没有色」——只看「传了个函数进去」证明不了它跟着走。

  const int rw = 200; // 画布 200×120，开关 56×30 居中 → 盒子 x ∈ [72, 128]
  const int rh = 120;

  /// 光栅化一枚开关（可先做一段手势），返回 RGBA 像素。
  Future<List<int>> raster(
    WidgetTester tester, {
    bool value = false,
    List<bool>? calls,
    Future<void> Function(WidgetTester t)? before,
  }) async {
    liquidGlassActive.value = true;
    addTearDown(() => liquidGlassActive.value = false);

    tester.view.physicalSize = const Size(rw * 1.0, rh * 1.0);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GlobalKey key = GlobalKey();
    bool v = value;
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        // 用**真主题**：主色纱的蓝度由它定，默认的 Material 紫算出来差一倍多。
        theme: buildLightTheme(),
        home: Material(
          child: Center(
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) =>
                  GlassSwitch(
                value: v,
                onChanged: (bool x) {
                  calls?.add(x);
                  setState(() => v = x);
                },
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    if (before != null) await before(tester);

    late List<int> px;
    await tester.runAsync(() async {
      final RenderRepaintBoundary b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await b.toImage(pixelRatio: 1.0);
      final ByteData? d =
          await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      px = d!.buffer.asUint8List().toList();
    });
    return px;
  }

  /// 某一点的「蓝度」= b − r。轨道被主色染上之后它会显著大于 0；没染就是 0 上下。
  int blueness(List<int> px, int x, int y) {
    final int i = (y * rw + x) * 4;
    return px[i + 2] - px[i];
  }

  testWidgets('拖动中：轨道色跟着**滴的位置**走，而不是等松手才跳', (tester) async {
    final List<bool> calls = <bool>[];
    late TestGesture g;
    bool released = false;
    final List<int> px = await raster(
      tester,
      calls: calls,
      before: (WidgetTester t) async {
        g = await t.startGesture(const Offset(90, 60));
        addTearDown(() {
          if (released) return Future<void>.value();
          return g.up();
        });
        for (int i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 30)); // 过按住闸门
        }
        // 拖 +32.5px。⚠️ **要扣掉 `kTouchSlop`（18px）** —— 识别器赢下竞技场之前
        // 那 18px 是空走的，所以有效位移 14.5px = 0.58 格。
        for (int i = 0; i < 13; i++) {
          await g.moveBy(const Offset(2.5, 0));
          await t.pump(const Duration(milliseconds: 16));
        }
      },
    );

    expect(calls, isEmpty,
        reason: '前提错了：这一拖把值翻过去了，这条用例就证明不了「跟着位置走」');

    // 采样点都在胶囊里、也都在滴的两侧之外：
    // 滴心 = 3 + 0.58×25 + 12.5 = 30（全局 102），半宽 13.5 → 占 [88.5, 115.5]；
    // 色带的边界在 36.5，过渡带是 [24, 49]（全局 [96, 121]）。
    final int left = blueness(px, 80, 60);
    final int right = blueness(px, 122, 60);
    expect(left, greaterThan(20), reason: '滴左边的轨道一点色都没有（蓝度 $left）');
    expect(left - right, greaterThan(20),
        reason: '两端一样蓝（左 $left / 右 $right）—— 那是「整条一起淡」，'
            '不是「跟着滴漫过去」');
    expect(right, lessThan(12), reason: '滴右边的轨道也被染上了（蓝度 $right）');

    await g.up();
    released = true;
    await tester.pumpAndSettle();
  });

  testWidgets('静止：关 = 一点色都没有；开 = 左端有色（过渡带扫出了轨道外）',
      (tester) async {
    // 两个端点都得是干净的 —— 色带边界是从轨道**外面**扫到**外面**的。
    // 关着的时候滴停在左端（占全局 75~100），所以只能量右端。
    //
    // ⚠️ **这一条没有「老 vs 新」的鉴别力**（把输入换回读 `widget.value` 它照样绿 ——
    // 老写法在两个端点上也成立），它守的是**新实现的端点**：过渡带一旦只扫到轨道
    // 中间，「开着」那一档的右端就会永远缺一截色。有鉴别力的是上一条。
    final List<int> off = await raster(tester);
    expect(blueness(off, 122, 60), lessThan(12),
        reason: '关着的时候轨道右端就有色（${blueness(off, 122, 60)}）');

    // 开着的时候滴停在右端（占 100~125），所以只能量左端。
    final List<int> on = await raster(tester, value: true);
    expect(blueness(on, 80, 60), greaterThan(20),
        reason: '开着的时候轨道左端没有色（${blueness(on, 80, 60)}）—— '
            '过渡带没有扫到轨道外面去');
  });
}
