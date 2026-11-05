// app/test/liquid_nav_spectral_test.dart
//
// 底栏那枚液态胶囊的**彩色边缘恒开** —— 它不再看「折射活没活着」的脸色。
//
// 2026-11-05 用户报「底栏那个彩色边缘没有了」。原来的写法是
// `spectral: refract ? !refractLive : spectral`：「折射活着就让彩边让位」。
// 那条推理的两个前提都不成立 ——
//   1. 折射带只有边缘那几像素，撑不起「方向感」；
//   2. Skia 回落的机器上折射**根本不存在**（`ImageFilter.shader` 在 Skia 上直接抛，
//      见 `core/glass/glass_refraction.dart` 的「程序就绪不等于这条链能用」），
//      于是拖动时只剩白芯与折边。
//
// 现在两件同时画：折射管「背后的东西被弯一点」，彩边管「方向感」。
//
// 为什么这条要**渲真的 `GlassNavBar`** 而不是像 `glass_refraction_test.dart` 那样
// 手搭一个 `LiquidTrack`：手搭的那份参数是抄的，抄错了照样绿。这里从底栏本身出发，
// 走它自己的档位判据与参数，测的是用户真正看到的那棵树。
//
// ⚠️ 档位必须走 `liquidGlassEnabled` + `recomputeGlassTiers()`（生产那条路），
// **不能直接 poke `liquidGlassActive`** —— `glass.dart` 在「折射位开着但程序没就绪」
// 时会 `scheduleMicrotask(recomputeGlassTiers)` 把它翻回去，于是液态档整个塌掉、
// `LiquidLens` 根本不在树上（第一次写这条用例就撞上：`Bad state: No element`）。
// `GlassRefraction.available` 在 Skia 上恒 false，所以这里能验的是「折射没挂上」
// 那一档；「折射活着」那一档由 `glass_refraction_test.dart` 里那条翻转用例直接
// 驱动 notifier 覆盖。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/features/home/glass_nav_bar.dart';

import 'support/source_scan.dart';

void main() {
  testWidgets('底栏胶囊的 spectral 恒 true —— 不随折射位变化', (tester) async {
    liquidGlassEnabled.value = true;
    recomputeGlassTiers();
    addTearDown(() {
      liquidGlassEnabled.value = false;
      recomputeGlassTiers();
    });
    expect(liquidGlassActive.value, isTrue, reason: '前提：液态档没生效');

    final controller = PageController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: GlassNavBar(
            controller: controller,
            items: const <(IconData, String)>[
              (Icons.calendar_month_outlined, '日历'),
              (Icons.alarm_outlined, '闹钟'),
              (Icons.check_circle_outline, '待办'),
              (Icons.person_outline, '我的'),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final lens = tester.widget<LiquidLens>(find.byType(LiquidLens));
    expect(
      lens.spectral,
      isTrue,
      reason: '底栏胶囊把彩边收掉了 —— 这正是用户 2026-11-05 报的'
          '「彩色边缘没有了」。彩边与折射是两个图层，谁也不替谁。',
    );

    // 反过来也验一次：彩边**不再看折射那一位**。
    //
    // 这条不能靠「把 `liquidRefractionEnabled` 翻成 true 再读 widget」来验 ——
    // `glass.dart` 会在下一个微任务里把档位翻回去（折射程序在 Skia 上根本没就绪），
    // 于是 `LiquidLens` 直接不在树上，断言只能写成 `if (…) { … }` 那种**会随环境
    // 变空话**的形状（第一版就是这么写的，独立审查指出来了）。
    // 判据改成扫源码：`LiquidTrack` 里**根本不许出现**这个 notifier。
    final track = blankNonCode(
        File('lib/core/widgets/liquid_track.dart').readAsStringSync());
    expect(
      track.contains('liquidRefractionEnabled'),
      isFalse,
      reason: '`LiquidTrack` 又去读折射那一位了 —— 彩边一旦跟着它走，'
          'Skia 回落的机器上拖动时就只剩白芯与折边（用户 2026-11-05 报的那条）',
    );
  });
}
