// 「玻璃浮层」统一入口的护栏（v0.10.13）。
//
// 这一轮把 19 处 `showDialog` 与 9 处 `showModalBottomSheet` 收敛到
// `showGlassDialog` / `showGlassSheet` 两个入口，为的是两件事：
//
//   1. **两条时长拿到自己手里** —— `showDialog` 自带的 `DialogRoute` 只有一个 150ms；
//   2. 二十来个实心面板入场时**从模糊里凝出来**（`GlassMaterialize`），而不是被点亮。
//
// 这个文件钉的是「入口本身」的四件事：两条时长真的分开了、点遮罩与返回键的行为与
// 以前一致、落定之后不留常驻的绘制层。**面板的几何**（按钮靠右 / 窄窗折行 / 动作行
// 浮在正文上）由 `glass_dialog_test` 守着，那几条要一直绿。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/widgets/glass_dialog.dart';

void main() {
  /// 装配一个能拿到 `BuildContext` 的宿主，弹出最小的一个 `GlassDialog`。
  ///
  /// 返回那个 `Future` —— 点遮罩 / 按返回键两条用例要拿它的返回值。
  Future<Future<bool?>> openMinimal(
    WidgetTester tester, {
    bool dismissible = true,
    double contentHeight = 40,
  }) async {
    late BuildContext host;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(builder: (BuildContext c) {
        host = c;
        return const SizedBox.expand();
      }),
    ));
    return showGlassDialog<bool>(
      context: host,
      barrierDismissible: dismissible,
      builder: (BuildContext _) => GlassDialog(
        title: '标题',
        content: SizedBox(height: contentHeight),
        actions: const <Widget>[],
      ),
    );
  }

  // 函数体里不能声明 getter —— 用普通函数。
  Finder panel() => find.byKey(const Key('glass-dialog-panel'));

  /// 逐帧推，直到面板的宽度到 [target]（±0.5），返回推了几帧。
  ///
  /// 面板在入场时被 `Transform.scale(0.92 → 1)` 缩着一圈，所以**宽度会一路涨** ——
  /// 涨到目标值就是「入场走完了」。等不到就返回 max（那条断言自然会红）。
  Future<int> framesUntilWidth(
    WidgetTester tester,
    double target, {
    int max = 60,
  }) async {
    for (int i = 1; i <= max; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (panel().evaluate().isEmpty) continue;
      if ((tester.getRect(panel()).width - target).abs() < 0.5) return i;
    }
    return max;
  }

  /// 逐帧推，直到面板从树上消失，返回推了几帧。
  Future<int> framesUntilGone(WidgetTester tester, {int max = 60}) async {
    for (int i = 1; i <= max; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (panel().evaluate().isEmpty) return i;
    }
    return max;
  }

  testWidgets('进场比退场慢 —— 两条时长真的分开了', (tester) async {
    await openMinimal(tester);
    await tester.pumpAndSettle();
    final double settled = tester.getRect(panel()).width;
    // 关掉，回到干净状态。
    Navigator.of(tester.element(panel())).pop();
    await tester.pumpAndSettle();

    // 再开一次，逐帧量进场。
    await openMinimal(tester);
    final int inFrames = await framesUntilWidth(tester, settled);
    Navigator.of(tester.element(panel())).pop();
    final int outFrames = await framesUntilGone(tester);

    // 300ms / 16ms ≈ 19 帧、200ms / 16ms ≈ 13 帧。
    expect(inFrames, closeTo(19, 4), reason: '进场不是 300ms 上下（$inFrames 帧）');
    expect(outFrames, closeTo(13, 4), reason: '退场不是 200ms 上下（$outFrames 帧）');
    expect(inFrames, greaterThan(outFrames),
        reason: '进场没有比退场慢 —— 两条时长没分开（那条 PopupRoute 白写了）');
  });

  testWidgets('点遮罩关窗，返回值是 null', (tester) async {
    final Future<bool?> result = await openMinimal(tester);
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5)); // 左上一角，面板之外 = 遮罩
    await tester.pumpAndSettle();

    expect(panel(), findsNothing, reason: '点了遮罩没关窗');
    expect(await result, isNull);
  });

  testWidgets('按返回键关窗，返回值是 null', (tester) async {
    final Future<bool?> result = await openMinimal(tester);
    await tester.pumpAndSettle();

    // 系统返回键落到 Navigator 上就是这一次 `maybePop`。
    final NavigatorState nav =
        tester.state<NavigatorState>(find.byType(Navigator));
    await nav.maybePop();
    await tester.pumpAndSettle();

    expect(panel(), findsNothing, reason: '按返回键没关窗');
    expect(await result, isNull);
  });

  testWidgets('barrierDismissible: false 时点遮罩不关窗', (tester) async {
    // 「下载进度」那个弹窗就是这样 —— 做到一半不许被点掉。这条是**迁移时差点丢掉**
    // 的行为：原来那一处自己写了 `barrierDismissible: false`，而我给入口写的默认是
    // `true`（写入口的第一版根本没有这个参数，是编译器把它拦下来的）。
    await openMinimal(tester, dismissible: false);
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(panel(), findsOneWidget,
        reason: '点了遮罩却关掉了 —— `barrierDismissible: false` 没传下去');

    // 收尾：把它关掉，免得留一条永远不完成的 future。
    Navigator.of(tester.element(panel())).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('入场中途面板是缩着的、还糊着（几何断言必须在落定之后量）', (tester) async {
    // ⚠️ 这条**不能**写成「落定后树上没有 `Transform`」—— 那个断言是错的：
    // Material 3 的 `StretchingOverscrollIndicator` 会给弹窗正文里那个
    // `SingleChildScrollView` **常驻**加一个 `Transform`（探针实测：它的祖先链是
    // `StretchEffect ← StretchingOverscrollIndicator ← Scrollable ← SingleChildScrollView`），
    // 与我们这层动画毫无关系。
    //
    // 钉真正有鉴别力的那件事：**中途量会差**（Review Focus 第 4 条）——
    // 面板入场时被 `Transform.scale(0.92 → 1)` 缩着一圈，所以中途的宽度必须明显小于
    // 落定后的；落定之后模糊必须收干净（那层 `ImageFiltered` 是常驻 `saveLayer` 的来源）。
    await openMinimal(tester);
    final Finder blur = find.descendant(
        of: find.byType(GlassMaterialize), matching: find.byType(ImageFiltered));

    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16)); // 约 96ms / 进场 300ms
    }
    final double mid = tester.getRect(panel()).width;
    expect(blur, findsWidgets, reason: '入场中途没有模糊 —— 凝聚根本没跑起来');

    await tester.pumpAndSettle();
    final double settled = tester.getRect(panel()).width;
    expect(mid, lessThan(settled - 4),
        reason: '中途量的宽度（$mid）与落定后（$settled）差不多 —— '
            '要么没缩，要么那条「t ≥ 1 直接返回原样子树」的早退坏了');
    expect(blur, findsNothing, reason: '落定之后还留着常驻的模糊层');
  });

  testWidgets('弹窗避开系统栏（原 `showDialog` 默认就避，自写路由第一版漏了它）',
      (tester) async {
    // SDK 的 `DialogRoute` 默认 `useSafeArea: true`（`dialog.dart` 里把 page 包进
    // `SafeArea`），而 `Dialog` 自己**不**避让 —— 所以那条自写路由漏了这一层时，
    // 21 处迁移过去的弹窗全都不再避让状态栏 / 手势条。**独立审查抓出来的真 regression。**
    tester.view.physicalSize = const Size(420 * 2, 900 * 2);
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 120, bottom: 80); // 逻辑 60 / 40
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // ⚠️ **内容必须撑得足够高**：面板是**垂直居中**的，短面板的顶边本来就远在
    // 内边距之下 —— 那样这条断言恒真、没有鉴别力（第一版就是这么写的，反向验证
    // 拿掉 `SafeArea` 它照样绿）。撑高之后顶边由「安全区 + `insetPadding`」决定。
    await openMinimal(tester, contentHeight: 2000);
    await tester.pumpAndSettle();

    final Rect panel = tester.getRect(find.byKey(const Key('glass-dialog-panel')));
    expect(panel.top, greaterThanOrEqualTo(60 - 0.5),
        reason: '弹窗顶到状态栏里去了（面板顶 ${panel.top}，状态栏 60）');
    expect(panel.bottom, lessThanOrEqualTo(900 - 40 + 0.5),
        reason: '弹窗压到手势条下面去了（面板底 ${panel.bottom}，手势条从 860 起）');
  });

  testWidgets('弹层：入场时带着凝聚，落定之后收干净', (tester) async {
    // 弹层与弹窗那一支的差别：**保留 Material 自带的「从底下升上来」**，凝聚叠在面板上
    // —— 所以这里不自己写路由，而是用**弹层自己的路由动画**驱动 `GlassMaterialize`。
    late BuildContext host;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(builder: (BuildContext c) {
        host = c;
        return const SizedBox.expand();
      }),
    ));
    showGlassSheet<void>(
      context: host,
      builder: (BuildContext _) =>
          const GlassPanel(solid: true, child: SizedBox(height: 120)),
    );
    final Finder blur = find.descendant(
        of: find.byType(GlassMaterialize), matching: find.byType(ImageFiltered));

    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16)); // 入场刚起头
    }
    expect(blur, findsWidgets, reason: '弹层入场没有凝聚 —— 那层 GlassMaterialize 没接上');

    await tester.pumpAndSettle();
    expect(blur, findsNothing, reason: '弹层落定之后还留着常驻的模糊层');

    Navigator.of(tester.element(find.byType(GlassPanel))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('弹层：往下拖关闭时**不该**被压暗（凝聚只在入场那一下）', (tester) async {
    // `ModalBottomSheetRoute` 把「下拉关闭」的手势**直接写进路由自己的 animation**
    // （SDK：`animationController.value -= primaryDelta / childHeight`）。如果那层凝聚
    // 跟着路由动画走，把弹层往下拖三成就会把面板压到三成不透明 —— **独立审查抓出来的**。
    // 所以凝聚改由一个自己的一次性控制器驱动，只跑入场。
    late BuildContext host;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(builder: (BuildContext c) {
        host = c;
        return const SizedBox.expand();
      }),
    ));
    showGlassSheet<void>(
      context: host,
      builder: (BuildContext _) =>
          const GlassPanel(solid: true, child: SizedBox(height: 200)),
    );
    await tester.pumpAndSettle();
    final Finder blur = find.descendant(
        of: find.byType(GlassMaterialize), matching: find.byType(ImageFiltered));
    expect(blur, findsNothing, reason: '前提错了：入场那层还没收干净');

    final TestGesture drag =
        await tester.startGesture(tester.getCenter(find.byType(GlassPanel)));
    final Rect before = tester.getRect(find.byType(GlassPanel));
    // 分步拖（一步 120px 走不出像样的拖动更新）。
    for (int i = 0; i < 12; i++) {
      await drag.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final Rect after = tester.getRect(find.byType(GlassPanel));
    expect(after.top, greaterThan(before.top + 20),
        reason: '前提错了：这一拖没把弹层拖下去 —— 那这条用例测不到东西');
    expect(blur, findsNothing,
        reason: '下拉时弹层被重新压暗/糊上了 —— 那层凝聚跟着下拉手势走了');
    await drag.up();
    await tester.pumpAndSettle();
  });
}
