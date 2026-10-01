// `GlassSegment` 接上液态档之后的护栏。
//
// 「关掉液态档时与改之前逐像素相同」不在这里验 —— 分段器长在各页里（闹钟 / 我的 /
// 排班编辑器 / 待办），那条由 `tool/visual` 的整屏逐像素比兜着（见计划的 Task 6
// Step 6）。这里只钉三件单屏照不出来的事。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/widgets/glass_segment.dart';
import 'package:shiftassistantpro/core/widgets/lens_warped_cell.dart';

void main() {
  const double h = 44;

  Future<List<int>> shot(
    WidgetTester tester, {
    required bool liquid,
    double width = 300,
    int selected = 0,
    String Function(int index)? label,
    Future<void> Function(WidgetTester tester)? beforeCapture,
    // 按住不放时**不能** settle：控制器的 ticker 一直在推帧（`_pressed` 为真），
    // `pumpAndSettle` 永远等不到停。那种用例传 false，改成推固定帧数。
    bool settle = true,
  }) async {
    liquidGlassActive.value = liquid;
    addTearDown(() => liquidGlassActive.value = false);

    tester.view.physicalSize = Size(width, 120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: width,
              height: h,
              child: GlassSegment(
                count: 3,
                selectedIndex: selected,
                height: h,
                onSelected: (int _) {},
                itemBuilder: (int i, bool sel) => Text(label?.call(i) ?? '$i',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    if (beforeCapture != null) await beforeCapture(tester);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

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

  int red(List<int> px, int w, int x, int y) => px[(y * w + x) * 4];

  testWidgets('点按之后竖直滑走：滴**回到已提交那一格**（不是停在手指那一格）',
      (tester) async {
    // 控制器那一条只证明它报告了「该回退」；这一条证明**调用点真的回退了**。
    // 用户 2026-10-01 报的「滑块定格」就是这里：`press()` 已经把滴挪到手指那一格，
    // 而页面并没有切，取消之后它留在那儿。
    //
    // 触发 `onTapCancel` 的办法：**上面挂一个竖直拖动识别器**。`TapGestureRecognizer`
    // 自己不会因为移动而取消（读了 SDK 的 `tap.dart`：它只在竞技场里输给别人时才
    // `_checkCancel`），所以必须有个竞争者把它挤出去。
    liquidGlassActive.value = true;
    addTearDown(() => liquidGlassActive.value = false);

    const int w = 300;
    tester.view.physicalSize = Size(w.toDouble(), 120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Center(
          child: GestureDetector(
            onVerticalDragStart: (_) {},
            child: SizedBox(
              width: w.toDouble(),
              height: h,
              child: GlassSegment(
                count: 3,
                selectedIndex: 0,
                height: h,
                onSelected: (int _) {},
                itemBuilder: (int i, bool sel) => Text('$i'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 3 格 300 宽 → 每格 (300 − 2×3) / 3 = 98；滴中心 = 3 + position × 98。
    final TestGesture g =
        await tester.startGesture(tester.getCenter(find.byType(GlassSegment)));
    bool released = false;
    addTearDown(() {
      if (released) return Future<void>.value();
      return g.up();
    });
    for (int i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.widget<LiquidLens>(find.byType(LiquidLens)).shape.centerX,
        closeTo(150, 6),
        reason: '按下去滴没有滑到手指那一格 —— 这条用例测不到东西');

    for (int i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, -25)); // 竖直滑走 → 点按被挤出竞技场
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (int i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    released = true;

    expect(tester.widget<LiquidLens>(find.byType(LiquidLens)).shape.centerX,
        closeTo(52, 1.0),
        reason: '取消之后滴停在手指那一格 —— 那就是用户说的「滑块定格」'
            '（已提交的第 0 格中心是 52）');
  });

  testWidgets('在**非当前那一格**上按住再横向拖：滴不跳回当前格（抓取偏移的护栏）',
      (tester) async {
    // 点按被**拖动**挤出竞技场时，SDK 的顺序是：先 reject 点按
    // （`GestureArenaManager._resolveInFavorOf` 先逐个 reject 再 accept 赢家 →
    // `TapGestureRecognizer.rejectGesture` → `onTapCancel`），**然后**才
    // `onHorizontalDragStart`。
    //
    // 于是「取消就把滴送回已提交那一格」会在 `dragStart` 读 `_page` **之前**把它改掉，
    // `_grabOffset = dx/itemW − _page` 就按错的 `_page` 算 —— 滴整枚跳到当前格去，
    // 松手提交的也是错的格子。（底栏那条尤其致命：它没有竖直方向的竞争者，
    // `onTapCancel` **只**能从拖动这条路走到。）
    liquidGlassActive.value = true;
    addTearDown(() => liquidGlassActive.value = false);

    const int w = 300;
    tester.view.physicalSize = Size(w.toDouble(), 120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Center(
          child: SizedBox(
            width: w.toDouble(),
            height: h,
            child: GlassSegment(
              count: 3,
              selectedIndex: 0,
              height: h,
              onSelected: (int _) {},
              itemBuilder: (int i, bool sel) => Text('$i'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    double centerX() =>
        tester.widget<LiquidLens>(find.byType(LiquidLens)).shape.centerX;

    // 每格 (300 − 2×3) / 3 = 98；第 2 格的中心 = 3 + 2.5×98 = 248，
    // 当前格（第 0 格）的中心 = 52。
    final TestGesture g = await tester.startGesture(const Offset(248, 60));
    bool released = false;
    addTearDown(() {
      if (released) return Future<void>.value();
      return g.up();
    });
    for (int i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(centerX(), closeTo(248, 6),
        reason: '按下去滴没有滑到手指那一格 —— 这条用例测不到东西');

    await g.moveBy(const Offset(30, 0)); // 超过 kTouchSlop → 横向拖动赢
    await tester.pump(const Duration(milliseconds: 16));

    expect(centerX(), greaterThan(200),
        reason: '拖动一起手滴就跳到了 ${centerX()} —— 它在拖动赢下竞技场的那一刻'
            '被「取消回退」送回了当前格，抓取偏移算错了');
    await g.up();
    released = true;
  });

  testWidgets('两档是两棵树：光栅化像素必须不同', (tester) async {
    // 反过来说：这条要是绿着不动，说明「液态档」根本没生效 —— v0.10.1 出过这个岔子
    // （工装那两张「液态档」基线图与标准档逐字节相同）。
    final List<int> off = await shot(tester, liquid: false);
    final List<int> on = await shot(tester, liquid: true);
    int differing = 0;
    for (int i = 0; i < off.length; i++) {
      if (off[i] != on[i]) differing++;
    }
    expect(differing, greaterThan(0), reason: '开了液态档却一个像素都没变');
  });

  testWidgets('浅色档：胶囊左右两条边同值（液态档的边光是竖直的）', (tester) async {
    const int w = 300;
    // ⚠️ **选中中间那一格**：分段器铺满整行，选中第 0 格时那枚滴就压在左端上，
    // 量到的「左端」是滴而不是胶囊的边（底栏因为外面还有 outerPad 留白，两端是空的
    // —— 所以那条用例的取法在这里不适用）。
    final List<int> px =
        await shot(tester, liquid: true, width: w.toDouble(), selected: 1);
    const int y = 60; // 画布 120 高，胶囊竖直居中
    int darkest(int from, int to) {
      int v = 255;
      for (int x = from; x <= to; x++) {
        if (red(px, w, x, y) < v) v = red(px, w, x, y);
      }
      return v;
    }

    final int left = darkest(0, 6);
    final int right = darkest(w - 7, w - 1);
    expect((left - right).abs(), lessThanOrEqualTo(4),
        reason: '左右两条边差 $left vs $right —— 边光又在按对角走了');
  });

  testWidgets('窄窗（200 宽、3 格）：透镜还在第一格上', (tester) async {
    // 胶囊窄到一定程度会落进 `toPath()` 的退化分支（宽 <= 高）。底栏在那里栽过一次
    // Critical（透镜整个消失、还一闪一没），所以这一档必须钉住。
    const int w = 200;
    final List<int> px = await shot(tester, liquid: true, width: w.toDouble());
    const double itemW = 200 / 3;
    final int x0 = (itemW / 2).round();
    final int x2 = (itemW * 2.5).round();
    expect((red(px, w, x0, 52) - red(px, w, x2, 52)).abs(), greaterThan(20),
        reason: '窄窗下第一格与最后一格一样 —— 透镜消失了');
  });

  // ── v0.10.10：内容被透镜边缘挤 ────────────────────────────────────────────

  /// 把滴拖到「边缘压在第 2 格上」，手指**不松**（松手会吸附回整格，那时扭曲就没了
  /// —— 峰值只在滴处于两格之间时存在）。
  ///
  /// 走「拖到宽度的 [endFraction]」而不是固定像素数：两种画布宽度下都要落在
  /// 「滴在第 1 格与第 2 格之间」那一段里，固定 150px 在 300 宽下正好、在 200 宽下
  /// 会撞上夹紧的上界（那时滴已经贴着右端，离第 2 格中心只剩 2px，格子反而**不扭**）。
  Future<void> dragToward(WidgetTester t, double endFraction) async {
    final Rect box = t.getRect(find.byType(GlassSegment));
    final double startX = box.left + box.width * 0.18;
    final double endX = box.left + box.width * endFraction;
    final TestGesture g = await t.startGesture(Offset(startX, box.center.dy));
    addTearDown(g.up);
    for (int i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 30)); // 过长按闸门
    }
    const int steps = 60;
    for (int i = 0; i < steps; i++) {
      await g.moveBy(Offset((endX - startX) / steps, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> dragOntoCell2(WidgetTester t) => dragToward(t, 0.70);

  List<LensWarpedCell> warpedCells(WidgetTester tester) =>
      tester.widgetList<LensWarpedCell>(find.byType(LensWarpedCell)).toList();

  /// 每一格当前的**横向缩放**（没套 `Transform` 就是 1.0）。
  ///
  /// 不写成「有没有 `Transform`」：那条钟形在静止时尾巴就够到隔壁一格（w ≈ 0.02，
  /// 位移 0.1px）—— 底栏一直是这个行为，不是这一版带进来的。有鉴别力的是
  /// **哪一格被压得明显**。
  List<double> cellScales(WidgetTester tester) => <double>[
        for (final Element e in find.byType(LensWarpedCell).evaluate())
          if (find
              .descendant(
                  of: find.byWidget(e.widget),
                  matching: find.byType(Transform))
              .evaluate()
              .isEmpty)
            1.0
          else
            tester
                .widget<Transform>(find.descendant(
                    of: find.byWidget(e.widget),
                    matching: find.byType(Transform)))
                .transform
                .entry(0, 0),
      ];

  testWidgets('内容层接上了共享的「格」，坐标用**铺满全宽**那一套', (tester) async {
    // 分段器的格子铺满全宽、只有滴自己内缩 padChipV；底栏的格子是内缩之后排的。
    // 抄底栏那个式子（`pad + (i+0.5)×itemW`）会得到 52 / 150 / 248，与这里的
    // 50 / 150 / 250 差 2px —— 铃形的 σ 只有 0.45×半宽 ≈ 24px，2px 就会让峰值
    // 与滴的真实边缘错开。
    await shot(tester, liquid: true, width: 300);
    final List<LensWarpedCell> cells = warpedCells(tester);
    expect(cells.length, 3, reason: '液态档的内容层没接上 LensWarpedCell');
    // itemW = (300 − 2×3)/3 = 98；cellW = 98 + 2×3/3 = 100 → 中心 50 / 150 / 250。
    expect(cells[0].iconCenterX, closeTo(50, 0.5));
    expect(cells[1].iconCenterX, closeTo(150, 0.5));
    expect(cells[2].iconCenterX, closeTo(250, 0.5));
    expect(cells[0].itemW, closeTo(98, 0.5), reason: 'itemW 要给「滴那一套」的值');
  });

  testWidgets('静止时没有哪一格被明显压到；滴的边缘压到哪一格，就压那一格', (tester) async {
    // 用户 2026-10-01：「滑块经过文字或者图标的时候，要有弯曲的特效」。
    // 峰值在**边缘**不在中心（厚透镜中间是平的）—— 所以静止时（滴正对着第 0 格）
    // 谁都不该被明显压窄；拖到两格之间时，被压的必须正好是滴那两条边扫过的那两格。
    await shot(tester, liquid: true, width: 300);
    final List<double> still = cellScales(tester);
    expect(still[0], closeTo(1.0, 0.03), reason: '静止时第 0 格就被压了 —— 权重算成了「中心也压」');
    expect(still[1], closeTo(1.0, 0.03));
    expect(still[2], closeTo(1.0, 0.03));

    await shot(tester, liquid: true, width: 300,
        beforeCapture: dragOntoCell2, settle: false);
    final List<double> moved = cellScales(tester);
    expect(moved[2], lessThan(0.95),
        reason: '滴的边缘压在第 2 格上，它却没被压窄（坐标不同构那条抄错了）');
    expect(moved[1], lessThan(0.95), reason: '滴的另一条边也在第 1 格上');
    expect(moved[0], closeTo(1.0, 0.03), reason: '第 0 格离滴两条边都很远，不该被碰');
  });

  testWidgets('窄窗 + 长标签：被挤之后仍不越出自己那一格', (tester) async {
    // 「被挤」= 压窄 + **往外推**（`lensIconPush` 5px）。格子里没有余量时，
    // 往外推就是溢出 —— 而 `Center` 既不裁也不报溢出，**这条没有自动信号**。
    // 窄窗 200 / 3 格时每格 66.7，最长的标签「跟随系统」约 48px，两边各余约 9px。
    const int w = 200;
    const List<String> labels = <String>['跟随系统', '跟随系统', '跟随系统'];
    final List<int> px = await shot(tester, liquid: true, width: w.toDouble(),
        label: (int i) => labels[i],
        beforeCapture: dragOntoCell2, settle: false);

    // 第 2 格 = x ∈ [133, 200)。文字是近黑的，滴是主色（亮度约 104）——
    // 用 < 70 把文字与滴分开。
    int lo = -1, hi = -1;
    for (int y = 40; y < 80; y++) {
      for (int x = 133; x < w; x++) {
        final int i = (y * w + x) * 4;
        final int lum = (px[i] * 299 + px[i + 1] * 587 + px[i + 2] * 114) ~/ 1000;
        if (lum < 70) {
          if (lo < 0) lo = x;
          hi = x;
        }
      }
    }
    expect(lo, greaterThanOrEqualTo(133), reason: '文字被推出格子左缘');
    expect(hi, lessThan(w), reason: '文字被推出格子右缘（右缘外就是溢出）');
  });
}
