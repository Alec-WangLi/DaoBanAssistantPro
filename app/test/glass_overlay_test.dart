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
import 'package:shiftassistantpro/core/widgets/glass_dialog.dart';

void main() {
  /// 装配一个能拿到 `BuildContext` 的宿主，弹出最小的一个 `GlassDialog`。
  ///
  /// 返回那个 `Future` —— 点遮罩 / 按返回键两条用例要拿它的返回值。
  Future<Future<bool?>> openMinimal(WidgetTester tester) async {
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
      builder: (BuildContext _) => const GlassDialog(
        title: '标题',
        content: SizedBox(height: 40),
        actions: <Widget>[],
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
}
