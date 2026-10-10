# 液态玻璃第三轮 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把透镜竖直那一档的轮廓从「三个子路径并起来」换成一条闭式外公切线构造 —— 一处同时修好「彩边穿进钮里」与「纵向拉长时头大尾轻画不出来」，再把彩边量、速度门、取消语义与那条亮带收口。

**Architecture:** `LiquidLensShape.toPath()` 的两个朝向共用同一套闭式解（竖直那档整体转 90°）；`LiquidLensMetrics` 增一个每面的速度门；`LiquidLensController` 的 `_syncTicker` 先刷新意图再判静止。三个界面件（底栏 / 分段器 / 开关）只改参数与一处取消回调。

**Tech Stack:** Flutter 3.47 / Dart 3.13，Impeller，无第三方依赖。

**Spec:** `docs/superpowers/specs/2026-10-01-liquid-glass-rollout-3-design.md`

## Global Constraints

- **版本号**：`app/pubspec.yaml` 的 `version:` 与 `app/lib/core/app_info.dart` 的 `appVersion` 同步改成 **`0.10.11+135`**（`app/test/app_info_test.dart` 盯着）。
- **标准档（`liquidGlassActive == false`）必须逐像素不变** —— 覆盖全部 `00_home_shell_*` 与各页标准档。液态档本轮**允许**变。
- **验收**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿，**条数只增不减**；`flutter test tool/visual/` 全绿。
- **不跑 `dart format`**（工具链是新版 tall style，一跑就重排整个文件）。
- **动图管线**：16ms 一帧、`--fps 62`、`--width` 取裁剪宽度（**不缩放**）、`--colors 256`。
- **判断彩边的量用 PNG，不要用 GIF**（256 色抖动会把一圈渐变彩虹抖成杂点，本轮已经因此误判过一次）。
- **每个「新建」文件先核实它在不在**（v0.10.10 把一份已存在的测试文件当新建 Overwrite 掉，毁了 4 条护栏）。
- 改动收尾时 `AGENTS.md` 的「最近改动」与版本史、`app_dialogs.dart` 的 `_changelogZh` / `_changelogEn` 一起更新（测试版条目只写自己这版改了什么，窗口恒 10 条）。

## Review Focus

规格暗示、但**没有哪条任务的用例直接跑过**的输入类别，最可能咬到使用者的五条（按可能性排序）：

1. **`宽 == 高` 的正圆档**：两个等半径圆、圆心距恰好等于 `2r` → `d = 0`、`mx = 0/0`。任何一档的动画中途都会扫过它（不是只有某一个面才碰得到）。
2. **窄窗（200×400）下底栏按住**：`itemW 39` → 宽 49 < 高 78，**一直在竖直档**；换了构造之后要确认没退化、也没变样。
3. **分段器在窄窗下**按住：格子更小，同样落在竖直档。
4. **取消的两条路径**：`onTapCancel`（竖直滑走）与 `onHorizontalDragCancel`（拖动被系统打断）都会走到取消 —— 回退逻辑要两条都对。
5. **速度门调低之后松手**：`_velocityPx` 衰减到尾巴收回要多久；调得太低会不会「慢速拖动时尾巴一直挂着不走」。

---

### Task 1: 竖直档改用闭式外公切线构造

**Files:**
- Modify: `app/lib/core/glass/liquid_lens.dart`（`toPath()` 的 `width <= height` 那一支，约 267–275 行；新增顶层私有 `_verticalTwoRadius`）
- Create: `app/test/liquid_lens_vertical_test.dart`

**Interfaces:**
- Consumes: 无（`LiquidLensShape.of` 的签名不变）
- Produces: `LiquidLensShape.toPath()` —— `宽 < 高` 时返回**一条闭合子路径**（`computeMetrics().length == 1`），两端半径为既有的 `leftRadius` / `rightRadius`

- [ ] **Step 1: 写失败用例**

新建 `app/test/liquid_lens_vertical_test.dart`：

```dart
// 竖直那一档的轮廓护栏。
//
// 它原来是把「上圆 + 下圆 + 中矩形」**并**成一条路径：填色对，但描边会把三段边界
// 全画出来 —— 四层光谱全是描边，于是钮的内部出现横线与内侧弧（用户 2026-10-01：
// 「彩边穿到滑块里边了，而且还不规则，也不贴边」）。
//
// v0.10.10 的开关按住时宽 29.69 < 高 33.38，**真机上一直在踩**；底栏在窄窗下同样。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens_metrics.dart';

void main() {
  /// 开关那一档的尺寸：itemW 25 / capsuleH 30 / pad 3。
  LiquidLensShape vertical({double velocity = 0, double stretch = 0}) =>
      LiquidLensShape.of(
        itemW: 25,
        capsuleH: 30,
        pad: 3,
        centerPage: 0,
        lift: 1,
        velocity: velocity,
        stretch: stretch,
        metrics: LiquidLensMetrics.forCapsule(30),
      );

  test('竖直档是**一条**闭合子路径（并三个子路径会把描边画进钮里）', () {
    final s = vertical();
    expect(s.width, lessThan(s.height), reason: '这一档本该是竖直的，不然这条白测');
    expect(s.toPath().computeMetrics().length, 1,
        reason: '轮廓不止一条子路径 —— 描边会把它内部的接缝也画出来');
  });

  test('竖直档也读前缘/后缘：拉伸时两端半径不一样', () {
    final s = vertical(stretch: 1);
    expect(s.width, lessThan(s.height), reason: '这一档本该是竖直的');
    expect(s.rightRadius, greaterThan(s.leftRadius));
    expect(s.leftRadius, closeTo(s.width / 2, 0.001));
  });

  test('竖直档：两半径相等时精确退化成胶囊（与横向档同一条性质）', () {
    final s = vertical();
    expect(s.leftRadius, closeTo(s.rightRadius, 0.001));
    expect(s.leftRadius, closeTo(s.width / 2, 0.001));
  });

  test('宽 == 高（正圆那一档）不塌：路径非空、面积 > 0、中心在里面', () {
    // 两个等半径圆、圆心距恰好等于 2r 时 d = 0，`mx = (rl − rr) / d` 就是 0/0。
    // itemW 24 / capsuleH 30 / pad 3 / lift 0 → 宽 24、高 24，正好相等。
    final s = LiquidLensShape.of(
        itemW: 24, capsuleH: 30, pad: 3, centerPage: 0, lift: 0, velocity: 0);
    expect(s.width, closeTo(s.height, 0.001), reason: '这一档本该是正圆，不然白测');
    final p = s.toPath();
    expect(p.getBounds().isEmpty, isFalse);
    expect(p.computeMetrics().length, 1);
    expect(p.contains(Offset(s.centerX, s.centerY)), isTrue);
  });

  testWidgets('光栅化：竖直档的中轴上没有横向的彩色线', (tester) async {
    // 几何断言（子路径只有一条）已经能抓住它，但这一条钉的是**看得到的那件事**：
    // 并集那版会在两个圆心的高度各留下一条横线，而那些高度落在竖直中轴上。
    final LiquidLensShape shape = vertical();
    final List<int> px = await _shot(tester, shape);
    const int w = 200;
    final int cx = shape.centerX.round() + 12; // 画布留了 12px 边距
    final int yTop = (shape.centerY - shape.height / 2).round() + 12 + 6;
    final int yBot = (shape.centerY + shape.height / 2).round() + 12 - 6;
    for (int y = yTop; y <= yBot; y++) {
      final int i = (y * w + cx) * 4;
      final int r = px[i], g = px[i + 1], b = px[i + 2];
      final int spread =
          [r, g, b].reduce((a, b) => a > b ? a : b) -
              [r, g, b].reduce((a, b) => a < b ? a : b);
      expect(spread, lessThan(30),
          reason: 'y=$y 处中轴上有彩色像素 (r$r g$g b$b) —— 描边把内部接缝画出来了');
    }
  });
}

/// 在一张窄画布上把一枚竖直档的透镜渲出来（`motion = 1`，彩边满档）。
Future<List<int>> _shot(WidgetTester tester, LiquidLensShape shape) async {
  const int w = 200;
  const int h = 120;
  tester.view.physicalSize = const Size(w.toDouble(), h.toDouble());
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        child: Center(
          child: SizedBox(
            width: 48,
            height: 30,
            child: LiquidLens(
              size: const Size(48, 30),
              shape: shape,
              lift: 1,
              isDark: true,
              accent: const Color(0xFF5B5BD6),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();

  late List<int> px;
  await tester.runAsync(() async {
    final RenderRepaintBoundary b =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image img = await b.toImage(pixelRatio: 1.0);
    final ByteData? d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    px = d!.buffer.asUint8List().toList();
  });
  return px;
}
```

- [ ] **Step 2: 跑，确认它红**

Run: `flutter test test/liquid_lens_vertical_test.dart`
Expected: 第一条与最后一条 **FAIL**（`computeMetrics().length` 是 **3**），第二条 **FAIL**（竖直档两半径永远相等）。

- [ ] **Step 3: 实现**

在 `app/lib/core/glass/liquid_lens.dart` 里：

① `toPath()` 的 `if (width <= height)` 那一支整个换成：

```dart
    if (width <= height) {
      final double r = width / 2;
      return _verticalTwoRadius(
        centerX: centerX,
        cy: cy,
        w: width,
        h: height,
        rTop: leftRadius,
        rBot: rightRadius,
      );
    }
```

（**注意方向**：转过去之后，局部坐标的「左端」落在屏幕的**上端**，所以 `rTop` 收 `leftRadius`。
向右拖时右端是前缘，转 90° 后落在下端 —— 于是「头大尾轻」在竖着的时候读作「下大上小」。）

② 在 `_lensPath` 旁边加顶层私有函数：

```dart
/// 竖直的两半径胶囊 —— 用的是**同一个闭式解**，只是把那个横着的形状整体转 90°。
///
/// 重推一遍外公切线（把 x/y 换过来）容易在符号上出错，转置则天然精确。而且转出来的
/// 是**一条闭合子路径** —— 原先那版 `addOval × 2 + addRect` 是三条，填色没问题，
/// **描边会把内部接缝也画出来**（四层光谱全是描边）。
Path _verticalTwoRadius({
  required double centerX,
  required double cy,
  required double w,
  required double h,
  required double rTop,
  required double rBot,
}) {
  // 局部坐标系里「宽 = 转过去之后的高、高 = 转过去之后的宽」。
  final double len = h;
  final double thick = w;
  final double cx0 = len / 2;
  final double cy0 = thick / 2;
  final Offset c1 = Offset(cx0 - len / 2 + rTop, cy0);
  final Offset c2 = Offset(cx0 + len / 2 - rBot, cy0);
  // ⚠️ **钳一个正的下限**：两半径相等、圆心距又恰好等于 2r 时（形状是正圆）
  // `d = 0`，`(rTop − rBot) / d` 就是 0/0。钳住之后 mx = 0、my = 1、theta = π/2，
  // 外公切线是一条竖直线、两端圆弧各扫 π —— 不碰 `arcTo` 扫 2π 那个坑。
  final double d = math.max(0.01, c2.dx - c1.dx);
  final double mx = ((rTop - rBot) / d).clamp(-1.0, 1.0);
  final double my = math.sqrt(math.max(0.0, 1 - mx * mx));
  final double theta = math.atan2(my, mx);
  final Path p = Path()
    ..moveTo(c1.dx + rTop * mx, cy0 - rTop * my)
    ..lineTo(c2.dx + rBot * mx, cy0 - rBot * my)
    ..arcTo(Rect.fromCircle(center: c2, radius: rBot), -theta, 2 * theta, false)
    ..lineTo(c1.dx + rTop * mx, cy0 + rTop * my)
    ..arcTo(Rect.fromCircle(center: c1, radius: rTop), theta,
        2 * (math.pi - theta), false)
    ..close();
  // 局部 (x, y) → 屏幕 (centerX − (y − cy0), cy + (x − cx0))
  return p.transform(Float64List.fromList(<double>[
    0, 1, 0, 0, //
    -1, 0, 0, 0, //
    0, 0, 1, 0, //
    centerX + cy0, cy - cx0, 0, 1,
  ]));
}
```

③ 文件顶部加 `import 'dart:typed_data';`

④ **删掉** `addOval × 2 + addRect` 那三行与它们上面那段「退化档」的注释里的**做法描述**
（把「改成竖直的胶囊：两端是半径 `宽/2` 的半圆……用 `addOval + addRect` 而不是 `arcTo`」
改写成现在这条路的理由，**`Path.arcTo` 扫 2π 那个坑的记述要留着** —— 它是为什么这条
构造要钳 `d` 的依据）。

- [ ] **Step 4: 跑，确认它绿**

Run: `flutter test test/liquid_lens_vertical_test.dart`
Expected: 5 条全过。

- [ ] **Step 5: 新旧轮廓对拍（那条兜底分支一直在用，外形不许变）**

写一个**临时探针**（跑完即删，放 `app/tool/visual/` 下），对
`lift ∈ {0, 0.5, 1} × stretch ∈ {0, 0.5, 1}` 这 9 组几何，各打印**新旧两版**的
`getBounds()` 与面积。旧版就是 Step 3 里删掉的 `addOval × 2 + addRect`。

判据：**包围盒宽高一致**；**面积差 < 2%**（并集那版内部有重叠，面积会略偏大 ——
所以这里比的不是「一模一样」，而是「外形相符」）。差得多的那一组要查清楚再往下走。

**对拍完把探针删掉**（`git status` 要干净）。

- [ ] **Step 6: 反向验证**

把 Step 3 ① 那一支临时改回 `addOval × 2 + addRect`（保留 `_verticalTwoRadius` 不删），重跑：
Expected: 第 1 条（子路径数）与第 5 条（中轴上的彩色线）**必须红**。改回来。

- [ ] **Step 7: 跑既有那条窄窗用例**

Run: `flutter test test/liquid_lens_test.dart`
Expected: 全绿 —— 其中 `窄窗：两端圆不许重叠（外公切线必须存在），且形状仍闭合`
（itemW 39 / capsuleH 64 / lift 1，宽 49 < 高 78）现在走的是**新**构造，必须照样过。

- [ ] **Step 8: 提交**

```bash
git add app/lib/core/glass/liquid_lens.dart app/test/liquid_lens_vertical_test.dart
git commit -m "fix(lens): 竖直档改用闭式外公切线构造 —— 轮廓从三条子路径收成一条"
```

---

### Task 2: `velocityRef` 下放 + 开关的四个数

**Files:**
- Modify: `app/lib/core/glass/liquid_lens_metrics.dart`
- Modify: `app/lib/core/glass/liquid_lens_controller.dart`（构造函数与 `_onTick`）
- Modify: `app/lib/core/widgets/glass_switch.dart`（`metrics` 那两处）
- Test: `app/test/liquid_lens_test.dart`（metrics 组）、`app/test/glass_switch_liquid_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `toPath()`（尾巴要在竖直档里画得出来才有意义）
- Produces:
  - `LiquidLensMetrics({..., double velocityRef = AppTokens.lensVelocityRef})`，字段 `final double velocityRef`
  - `LiquidLensController({..., double velocityRef = AppTokens.lensVelocityRef})`

- [ ] **Step 1: 写失败用例**

① 在 `app/test/liquid_lens_test.dart` 的 metrics 组里（`forCapsule 顺带导出彩边缩放` 那条后面）加：

```dart
    test('velocityRef 默认就是全局那一档（底栏与分段器必须不变）', () {
      expect(const LiquidLensMetrics(protrude: 10, liftWidth: 10).velocityRef,
          AppTokens.lensVelocityRef);
      expect(LiquidLensMetrics.forCapsule(30).velocityRef,
          AppTokens.lensVelocityRef);
    });
```

② 在 `app/test/glass_switch_liquid_test.dart` 里加（`_lensOf` 见到什么就照着写，
它现有的取法是从树上找 `LiquidLens` / `LiquidTrack`）：

```dart
  testWidgets('开关的四个数：纵向拉长 / 收窄的彩边 / 更低的速度门', (tester) async {
    // 「上下拉伸」是用户 2026-10-01 拍的板（原话：「右」）；
    // 速度门下放是因为开关一格只有 25px —— 全局 900px/s 下尾巴只积到 0.28。
    final LiquidTrack track = tester.widget<LiquidTrack>(
        find.byType(LiquidTrack).first);
    expect(track.metrics!.protrude, closeTo(9, 0.001));
    expect(track.metrics!.liftWidth, closeTo(-2, 0.001));
    expect(track.metrics!.rimScale, closeTo(0.25, 0.001));
    expect(track.metrics!.velocityRef, closeTo(180, 0.001));
  });
```

（这条用例要挂在一枚**液态档**的 `GlassSwitch` 上：照该文件已有用例的
`useLiquidGlassTier()` + 起手式来，用 `find.byType(LiquidTrack)` 从树上取那个 widget
读它的 `metrics`。文件末尾要 `tearDown(useStandardGlassTier)`，别把档位漏给下一条。）

③ 在 `app/test/liquid_lens_controller_test.dart` 里加**速度门真的能让尾巴收掉**：

```dart
  testWidgets('速度门调低之后，慢速拖动也积得起形变；松手会收回去', (tester) async {
    // 规格 §3.3：一格 25px 的轨道上，全局 900px/s 的峰值形变只有 0.22~0.28。
    // 这一条同时钉两头：够得着，以及**松手之后不留在那儿**。
    final c = LiquidLensController(
      slots: 2,
      pad: 3,
      liftWidth: 25 * 0.15625,
      vsync: const TestVSync(),
      initialSlot: 1,
      velocityRef: 180,
    )..setItemW(25);
    addTearDown(c.dispose);

    c.dragStart(25 * 1.5);
    for (int i = 0; i < 8; i++) {
      c.dragUpdate(25 * 1.5 - 3 * (i + 1));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(c.stretch, greaterThan(0.7),
        reason: '慢速拖动只积到 ${c.stretch} —— 速度门没接上');

    c.release();
    for (int i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(c.stretch, lessThan(0.05), reason: '松手之后尾巴还挂着（${c.stretch}）');
  });
```

- [ ] **Step 2: 跑，确认它红**

Run: `flutter test test/liquid_lens_test.dart test/glass_switch_liquid_test.dart test/liquid_lens_controller_test.dart`
Expected: 三条都 FAIL（`velocityRef` 不存在 / 四个数还是旧的）。

- [ ] **Step 3: 实现**

① `liquid_lens_metrics.dart`：

```dart
  const LiquidLensMetrics({
    required this.protrude,
    required this.liftWidth,
    this.rimScale = 1.0,
    this.velocityRef = AppTokens.lensVelocityRef,
  });

  /// 形变饱和的速度门（px/s）。**每面各自的数** —— 形变强度走「位置的真实帧间差分
  /// ÷ 它」，而**一格多宽**决定了同一个手势能走几帧：底栏一格 88px，800px/s 走 7 帧、
  /// 峰值形变 0.77；开关一格 25px，同样 800px/s 只走 2 帧、峰值 0.22（越快反而越短）。
  /// 全局那一档（900）在 25px 的轨道上够不着，尾巴该收 35% 实际只收 10%。
  final double velocityRef;
```

② `liquid_lens_controller.dart`：构造函数加 `this.velocityRef = AppTokens.lensVelocityRef`（放在
`followFinger` 后面），加字段，`_onTick` 里把 `AppTokens.lensVelocityRef` 换成 `velocityRef`。

③ `glass_switch.dart` 的两处 `LiquidLensMetrics.forCapsule(widget.height)` 换成：

```dart
  /// 开关这一枚的四个数（用户 2026-10-01 拍的板）。
  static const LiquidLensMetrics _metrics = LiquidLensMetrics(
    // 纵向拉长（满升程约 23 × 42）—— 原话：「右」。
    protrude: 9,
    liftWidth: -2,
    // 彩边：内晕往轮廓里伸进去的**占比**与底栏对齐（底栏 8%，`30/64 = 0.469` 时开关是 16%）。
    rimScale: 0.25,
    // 一格只有 25px，全局 900 会把尾巴掐掉三分之二。
    velocityRef: 180,
  );
```

（`initState` 里那个 `liftWidth:` 参数与 `_buildLiquid` 里那个 `metrics:` 都换成 `_metrics`。）

- [ ] **Step 4: 跑，确认它绿**

Run: `flutter test test/liquid_lens_test.dart test/glass_switch_liquid_test.dart test/liquid_lens_controller_test.dart`
Expected: 全过 —— **除了**下面 Step 5 那条。

- [ ] **Step 5: 更新被这一改动作废的既有用例**

`app/test/glass_switch_liquid_test.dart` 的 `按住：钮**纵横一起长**（与底栏 / 分段器同一套升程）`
现在不成立了（`liftWidth: -2` → 按住时反而窄 2px）。改成：

```dart
  testWidgets('按住：钮**纵向拉长**（横向不外扩，反而收 2px）', (tester) async {
    // v0.10.10 那条「与另两处同一套 forCapsule」已被用户 2026-10-01 推翻：
    // 「看起来还是得做成上下拉伸的……现在感觉就变成一个大圆」。
    // 于是开关的升程量与另两处**分了家** —— 这是有意的，不是回归。
    ...
    expect(held.height, greaterThan(rest.height) * 1.3);
    expect(held.width, lessThanOrEqualTo(rest.width));
  });
```

Run: `flutter test test/glass_switch_liquid_test.dart`
Expected: 全过。

- [ ] **Step 6: 反向验证**

把 `glass_switch.dart` 的 `velocityRef` 换回 `AppTokens.lensVelocityRef`，重跑 Step 1 ②：
Expected: FAIL。改回来。

- [ ] **Step 7: 提交**

```bash
git add app/lib/core/glass/liquid_lens_metrics.dart \
        app/lib/core/glass/liquid_lens_controller.dart \
        app/lib/core/widgets/glass_switch.dart \
        app/test/liquid_lens_test.dart app/test/glass_switch_liquid_test.dart
git commit -m "feat(switch): 纵向拉长 + 彩边收到 0.25 + 速度门下放到每面"
```

---

### Task 3: 升程冻死（用户报的第三条）

**Files:**
- Modify: `app/lib/core/glass/liquid_lens_controller.dart`
- Test: `app/test/liquid_lens_controller_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `velocityRef`（同一文件，顺序在后）
- Produces: 私有 `_retarget()`；`_syncTicker()` 的行为（**先刷新 `_lift.target` 再判静止**）

- [ ] **Step 1: 写失败用例**

在 `app/test/liquid_lens_controller_test.dart` 末尾加：

```dart
  testWidgets('按住够久再竖直滑走：升程**必须落回来**（它原来冻在满档）', (tester) async {
    // 用户 2026-10-01：「长按这些滑块，手指快速上下滑动页面时，滑块会定格在放大的
    // 那个瞬间，需要再次点击一下滑块，才会恢复正常」。
    //
    // 根因：`_syncTicker()` 拿 `_lift.isAtRest` 判「还要不要推帧」，而它比的是
    // `value` 与 `target` —— **`target` 只在 `_onTick` 里刷新**。`tapCancel()` 翻完
    // 状态立刻判，此时 `value == target == 1`，判成「已静止」→ 停 ticker →
    // `target` 永远停在 1。
    //
    // **按得够久是复现的关键**：400ms 时升程弹簧速度还没落到 1 以下、不算静止，
    // ticker 照跑，于是自愈 —— 它在真机上只在「弹簧停稳之后再滑」时出现。
    final c = make();
    c.press(itemW + itemW / 2);
    await advance(tester, 1200); // 升程彻底停稳
    expect(c.lift, closeTo(1, 0.001), reason: '这一档本该已经提满了');

    c.tapCancel();
    await advance(tester, 800);
    expect(c.lift, lessThan(0.01), reason: '升程冻在 ${c.lift} —— ticker 被提前停了');

    await settleToRest(tester);
  });
```

- [ ] **Step 2: 跑，确认它红**

Run: `flutter test test/liquid_lens_controller_test.dart`
Expected: FAIL，`升程冻在 1.0`。

- [ ] **Step 3: 实现**

在 `liquid_lens_controller.dart` 里抽出：

```dart
  /// 按**当前意图**刷新各个目标。
  ///
  /// ⚠️ **`_lift.target` 不许只在 `_onTick` 里写。** `_syncTicker()` 要用
  /// `_lift.isAtRest` 判「还要不要推帧」，而那个判据比的是 `value` 与 `target` ——
  /// 意图在两次 tick 之间翻掉时（`tapCancel` / `release` / `cancel` 都会），
  /// `target` 还是旧的「1」，于是 `value == target` 成立、被判成静止、**ticker 被停掉**，
  /// `_onTick` 再也不跑、`target` 也就永远停在 1：升程冻死在满档。
  /// （用户 2026-10-01 报的「滑块定格在放大的那个瞬间，要再点一下才恢复」。）
  void _retarget() {
    _lift.target = _liftTarget;
  }
```

`_onTick` 开头把 `_lift.target = _liftTarget;` 换成 `_retarget();`，
`_syncTicker()` 里把 `final bool needed = ...` 前面加上 `_retarget();`。

- [ ] **Step 4: 跑，确认它绿**

Run: `flutter test test/liquid_lens_controller_test.dart`
Expected: 全过（含既有那 10 条）。

- [ ] **Step 5: 反向验证**

把 `_syncTicker()` 里那行 `_retarget();` 删掉，重跑：Expected: 新用例 FAIL（冻在 1.0）。加回来。

- [ ] **Step 6: 提交**

```bash
git add app/lib/core/glass/liquid_lens_controller.dart app/test/liquid_lens_controller_test.dart
git commit -m "fix(lens): \`_syncTicker\` 先刷新意图再判静止 —— 升程不再冻在满档"
```

---

### Task 4: 取消 = 当作没点过（行为改动）

**Files:**
- Modify: `app/lib/core/glass/liquid_lens_controller.dart`（`tapCancel`）
- Modify: `app/lib/core/widgets/glass_segment.dart`（`_buildStandard` / `_buildLiquid` 的 `onTapCancel`）
- Modify: `app/lib/features/home/glass_nav_bar.dart`（`_onTapCancel`）
- Test: `app/test/liquid_lens_controller_test.dart`、`app/test/glass_segment_liquid_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `_retarget()`
- Produces: `bool LiquidLensController.tapCancel()`（返回「是否真的做过什么」；
  调用点在为真时自己 `snapTo(已提交那一格 + 0.5)`）

- [ ] **Step 1: 改既有那条用例（它现在钉的是反的行为）**

`app/test/liquid_lens_controller_test.dart` 的
`取消：只有真正在拖才回退，点按被取消不回退` 改成：

```dart
  testWidgets('点按被取消：位置**也**回到已提交那一格，preview 清掉', (tester) async {
    // 规格 §4.5 第 2 条（**行为改动**）：取消的语义是「当作没点过」。
    // 原来只取消「按住」，于是滴留在手指按下那一格、而页面并没有切 ——
    // 用户看到的正是「滑块定格」（他说「需要再次点击一下滑块，才会恢复正常」）。
    final c = make(initialSlot: 2);
    c.press(itemW * 3 + itemW / 2);
    await advance(tester, 48);
    expect(c.previewIndex, 3);

    expect(c.tapCancel(), isTrue, reason: '按过之后取消，应当报告「真的取消了」');
    expect(c.pressed, isFalse);
    expect(c.previewIndex, isNull, reason: 'preview 没清 —— 分段器的高亮会停在那儿');

    await settleToRest(tester);
  });
```

（`snapTo` 那一步是**调用点**的事，控制器只管报告；底栏 / 分段器的回退另有用例。）

- [ ] **Step 2: 跑，确认它红**

Run: `flutter test test/liquid_lens_controller_test.dart`
Expected: FAIL（`tapCancel()` 现在返回 `void`、`previewIndex` 也不清）。

- [ ] **Step 3: 实现**

`tapCancel()` 改成：

```dart
  /// 点按被取消（在容器上按下之后竖直滑走之类）。
  ///
  /// **返回「是否真的取消掉了什么」** —— 调用点据此把位置交还给「已提交的那一格」
  /// （只有调用点知道那是哪一格）。取消的语义是**当作没点过**：`press(moveToSlot: true)`
  /// 已经把滴滑到手指那一格了，不回退的话它会留在那儿，而页面并没有切 ——
  /// 那正是用户说的「滑块定格」。
  ///
  /// ⚠️ 不能复用 [cancel]：那个有个「没在拖就早退」的闸门。
  bool tapCancel() {
    final bool wasActive = _pressed || _dragging;
    _endHold();
    if (!_dragging) {
      _pressed = false;
      _previewIndex = null;
      notifyListeners();
    } else {
      cancel();
    }
    _syncTicker();
    return wasActive;
  }
```

`glass_nav_bar.dart`：

```dart
  /// 点按被取消（在胶囊上按下之后竖直滑走之类）→ **当作没点过**：
  /// 按住态清掉，滴也回到已提交的那一格（不回退的话它会停在手指按下那一格，
  /// 而页面并没有切）。
  void _onTapCancel() {
    if (_lens.tapCancel()) _lens.snapTo(_committedIndex + 0.5);
  }
```

`glass_segment.dart` 两棵树里的 `onTapCancel: () => _lens.tapCancel()` 都改成
`onTapCancel: _onTapCancel`，并加：

```dart
  void _onTapCancel() {
    if (_lens.tapCancel()) _lens.snapTo(_committed + 0.5);
  }
```

（`glass_switch.dart` 的 `onTapCancel: _lens.tapCancel` **不动** —— 它
`press(moveToSlot: false)`，按下本来就不挪钮，没得回退；返回类型改成 `bool` 之后
这个 tear-off 照样合法。）

- [ ] **Step 4: 跑，确认它绿**

Run: `flutter test test/liquid_lens_controller_test.dart test/glass_segment_liquid_test.dart test/glass_tier_test.dart`
Expected: 全过。若 `glass_tier_test.dart` 里那条「点按被取消之后不再算按住」因为回退而
观察到的位置变了，**按新语义改断言，不要改回退**。

**取消有两条路径，两条都要走一遍**：`onTapCancel`（竖直滑走 → 本任务改的这条）与
`onHorizontalDragCancel`（拖动中途被系统打断 → `_cancel()`，**没改**）。后者底栏 / 分段器
/ 开关各有一条既有用例（开关那条叫「拖到一半被系统打断（PointerCancel）：按「松手」
处理，逻辑页不留残值」），Step 4 这条命令必须把它们一起跑绿 —— 回退逻辑动过之后，
「谁在什么时候回退」很容易被连带改坏。

- [ ] **Step 5: 加一条端到端的**

在 `app/test/glass_segment_liquid_test.dart` 里加：

```dart
  testWidgets('点按之后竖直滑走：滴回到已提交那一格', (tester) async {
    // 控制器那一条只证明它报告了「该回退」；这一条证明调用点真的回退了。
    // 几何断言：滑走并静下来之后，滴的中心仍在**已提交那一格**的中心。
    ...
  });
```

（`shot` / `cellScales` 那套夹具已经在了；取 `LiquidLens` 的 `shape.centerX` 与
`已提交格中心` 比，容差 0.5px。）

Run: `flutter test test/glass_segment_liquid_test.dart` → 全过。

- [ ] **Step 6: 提交**

```bash
git add app/lib/core/glass/liquid_lens_controller.dart \
        app/lib/core/widgets/glass_segment.dart app/lib/features/home/glass_nav_bar.dart \
        app/test/liquid_lens_controller_test.dart app/test/glass_segment_liquid_test.dart
git commit -m "fix(lens): 点按被取消 = 当作没点过（滴回到已提交那一格，preview 清掉）"
```

---

### Task 5: 关掉「跟随滑块的亮带」

**Files:**
- Modify: `app/lib/core/widgets/liquid_track.dart`
- Modify: `app/lib/core/glass/liquid_lens.dart`（`CapsuleRimPainter`）
- Modify: `app/lib/core/widgets/glass_switch.dart`（去掉显式 `showGlowBand: false`）
- Test: `app/test/liquid_track_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `LiquidTrack` 不再有 `showGlowBand`；`CapsuleRimPainter` 不再有
  `sliderIndex` / `tabCount` / `trackPad`

- [ ] **Step 1: 改那条既有用例，先让它红**

`app/test/liquid_track_test.dart` 的
`showGlowBand：关掉的是**那条光带**，不是整圈边光` 整条换成：

```dart
  testWidgets('胶囊的边光是**水平均匀**的：那条「跟随滑块」的亮带已经拆掉', (tester) async {
    // 用户 2026-10-01：「中间边缘怎么都会发光啊？尤其是在深色模式下很明显」——
    // 那团光就是 `CapsuleRimPainter` 的 sliderIndex 亮带（深色下白 @0.95、模糊 3、
    // 再加宽 1.4 倍），它落在滑块所在的那一段胶囊边上。滴在这两处几乎填满胶囊高，
    // 亮带只剩溢出到胶囊外的那半截能看见，读起来像「边缘漏了个光斑」。
    // 三处一起关掉（开关自 v0.10.9 起就关着）。
    const int w = 300;
    final List<int> px = await shot(tester, width: w.toDouble());
    // 取胶囊**上沿**那一行（画布 120 高、胶囊竖直居中在 40..80，所以上沿在 y=41）。
    int lum(int x) => red(px, w, x, 41);
    // 滑块在第 0 格 → 老实现会在那一带点亮。左右两端都得一样亮。
    final int near = lum(40);
    final int far = lum(260);
    expect((near - far).abs(), lessThanOrEqualTo(4),
        reason: '胶囊边上还有一段更亮（$near vs $far）—— 亮带没拆干净');
  });
```

（`shot` 的 `showGlowBand` 参数、`fluid` 那两个默认值一并删掉。）

- [ ] **Step 2: 跑，确认它红**

Run: `flutter test test/liquid_track_test.dart`
Expected: FAIL（亮带还在，`shot` 的默认 `showGlowBand: true` 会把它画出来）。
**若它居然是绿的**：说明取样的那一行没落在亮带上 —— 换一行/换两端重取，
直到它在**拆之前**红。判据是「同一行上，滑块那一带比远端明显更亮」。

- [ ] **Step 3: 实现**

① `liquid_lens.dart` 的 `CapsuleRimPainter`：删掉 `sliderIndex` / `tabCount` / `trackPad`
三个字段与构造参数、删掉 `paint` 里从 `final double? index = sliderIndex;` 起的**整段**
（到 `canvas.drawRRect(rrect, ...glow...)` 收尾），`shouldRepaint` 里那三个比较一并删掉，
类的文档注释改成只描述方向性边光。

② `liquid_track.dart`：删掉 `showGlowBand` 字段与构造参数；
`sliderIndex:` 那一行整个删掉；`CapsuleRimPainter(...)` 只留 `radius` / `isDark` / `compact`。
注释里「`sliderIndex: null` = 只画边光」那段跟着走。

③ `glass_switch.dart`：删掉 `showGlowBand: false,` 那一行
（**`showRefractedEdge: false` 留着** —— 那是另一件事）。

- [ ] **Step 4: 跑，确认它绿**

Run: `flutter test test/liquid_track_test.dart test/liquid_lens_test.dart test/glass_tier_test.dart`
Expected: 全过。

- [ ] **Step 5: 反向验证**

把 `CapsuleRimPainter` 里那段亮带**只恢复成无条件画**（`sliderIndex` 用
`controller.position`），重跑 Step 1：Expected: FAIL。删掉。

- [ ] **Step 6: 提交**

```bash
git add app/lib/core/widgets/liquid_track.dart app/lib/core/glass/liquid_lens.dart \
        app/lib/core/widgets/glass_switch.dart app/test/liquid_track_test.dart
git commit -m "fix(lens): 拆掉「跟随滑块」的亮带（三处都画得太满，只剩溢出那半截）"
```

---

### Task 6: 屏单与动图

**Files:**
- Modify: `app/tool/visual/render_screens_test.dart`（`43_switch_liquid_*` 补「拖动中」那一态）
- Modify: `app/tool/gif/render_gifs_test.dart`（开关「按住 → 拖动 → 松手」动图）

**Interfaces:**
- Consumes: 前面五个任务的全部产物
- Produces: 无（工装产出素材）

- [ ] **Step 1: 屏单补「拖动中」**

`43_switch_liquid_${variant.suffix}` 现在拍的是**按住**。再补一组
`46_switch_drag_${variant.suffix}`：同一个 `_SwitchHost`，`beforeCapture` 里先把
`kTouchSlop` 走掉（**第一版每帧只走 3px、六帧才 18px，识别器压根没收下这次拖动，
两张图逐字节相同** —— 这个坑本轮已经踩过一次），再每帧 3px 拖到一半，
`settleAfterCapture: false` 取「还在动」的那一帧。

Run: `flutter test tool/visual/render_screens_test.dart`
Expected: 全绿，`build/visual/` 里出现 `46_switch_drag_*`。

- [ ] **Step 2: 动图**

在 `tool/gif/render_gifs_test.dart` 里加一条：一枚开关「按住 → 拖动 → 松手」，
浅 / 深各一条，`step: 16ms`、`count` 覆盖全过程。
合成：

```bash
python scripts/make_gif.py --prefix sw_drag_dark_ --out work/gif/switch-drag-dark.gif \
  --crop <裁剪框> --width <裁剪宽度> --fps 62 --colors 256
```

（`--width` 取**裁剪宽度**，不缩放；判断彩边的量用 PNG，不要用 GIF。）

- [ ] **Step 3: 出图逐张核对**

Run: `flutter test tool/visual/` 然后逐张看图，重点五类：
① `43_switch_liquid_*`（按住：纵向拉长的滴，彩边贴着边、钮里没有横线）；
② `46_switch_drag_*`（拖动中：头大尾轻显出来了）；
③ 底栏与分段器的液态档（亮带拆掉之后的观感）：`36_home_shell_liquid_*` /
`37_profile_liquid_*` / `42_segment_liquid_*`；
④ **窄窗（`*_small`）**：底栏（itemW 39，宽 49 < 高 78）与分段器都在竖直档上，
这一档必须单看 —— 它本来就在踩同一条兜底分支；
⑤ 标准档全部（**必须与基线逐像素相同**，不接受「差异名单里没印出来」当结论）。

- [ ] **Step 4: 提交**

```bash
git add app/tool/visual/render_screens_test.dart app/tool/gif/render_gifs_test.dart
git commit -m "test(visual): 屏单补开关「拖动中」，动图补一条拖动全过程"
```

---

### Task 7: 收口

**Files:**
- Modify: `app/pubspec.yaml`、`app/lib/core/app_info.dart`、`app/lib/features/profile/app_dialogs.dart`、`AGENTS.md`
- Create: `tools/gh/release-notes-v0.10.11.md`

- [ ] **Step 1: 版本号**

`app/pubspec.yaml` 的 `version:` 与 `app/lib/core/app_info.dart` 的 `appVersion`
同步改成 `0.10.11+135`。

Run: `flutter test test/app_info_test.dart` → 全过。

- [ ] **Step 2: 更新日志**

`app_dialogs.dart` 的 `_changelogZh` / `_changelogEn` **prepend** 一条 0.10.11
（测试版条目只写自己这版改了什么；删最旧一条；窗口恒 10 条）。
**更新日志是纯文本渲染的，不许出现 markdown 标记**（`**` / 反引号 / 行首 `#` /
`[文字](链接)`）—— `changelog_window_test.dart` 盯着。

Run: `flutter test test/changelog_window_test.dart` → 全过。

- [ ] **Step 3: AGENTS.md**

「最近改动」加 v0.10.11 一条；版本史那行接上 `→ 0.10.11(+135) 测试版（…）`。

- [ ] **Step 4: 全量验收**

```bash
flutter analyze
flutter test
flutter test tool/visual/
```

Expected: `No issues found`；测试**全绿且条数只增不减**（改前是 663，工装 324）；
出图里标准档与基线逐像素相同。

- [ ] **Step 5: 提交**

```bash
git add app/pubspec.yaml app/lib/core/app_info.dart \
        app/lib/features/profile/app_dialogs.dart AGENTS.md \
        tools/gh/release-notes-v0.10.11.md
git commit -m "chore(release): v0.10.11（竖直档轮廓 / 彩边收窄 / 升程不再冻死）"
```

---

## 收尾（不在任务里，执行者按仓库既有流程走）

测试版走 `beta` 分支：提交 → `git push origin beta` → `git tag v0.10.11 && git push origin v0.10.11`
→ `scripts/release.ps1 -SkipConfirm` → **curl 一次 main 上的 `latest.json` 核对版本号**。
`gh` 若报未登录：根因是 `tools/build-env.ps1` 把 `APPDATA` 重定向进了 `toolchain/`，
source 之后把 `GH_CONFIG_DIR` 指回真实目录即可。
