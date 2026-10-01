# 日历选中块的液态玻璃化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让日历网格上那枚选中块在液态档下变成一枚真正的玻璃透镜（按住四面鼓出、拖动沿运动方向形变、
边缘挤过格子里的字），而**标准档逐像素不变**。

**Architecture:** 共享的透镜几何族加两维（`cornerR` 圆角半径、`stretchY` 纵向形变），默认值保持今天的行为；
新增一个只用三个输入（在哪儿 / 按住没有 / 拖动速度）的 `CalendarLens` 部件，把升程弹簧、环的弹簧、
速度低通与 ticker 全关在里面；`calendar_screen.dart` 只在 `_glassBlock` 与 `AnimatedScale` 两处按档位分叉，
并把速度喂下去。挤字用一个新的二维纯函数（一维版是它在 `dy = 0` 时的特例），
套在**每格的内容**上（卡片本身不动）。

**Tech Stack:** Flutter 3.47 / Dart 3.13、Impeller、无第三方依赖。工具链在 `toolchain/`（已 gitignore）——
`flutter` 的路径是 `toolchain/flutter/bin/flutter`。

**Spec:** `docs/superpowers/specs/2026-10-01-liquid-glass-rollout-5-design.md`（规格是权威，计划是它的论证；
两者冲突时以规格为准，并把裁定记进账本）

## Global Constraints

- 版本 `0.10.14+138` → **`0.10.15+139`**；`app/pubspec.yaml` 的 `version` 与
  `app/lib/core/app_info.dart` 的 `appVersion` **两处同步**（`test/app_info_test.dart` 盯着）。
- 更新日志（`app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh` / `_changelogEn`）：
  prepend 一条、删最旧一条、窗口恒 10 条；**纯文本渲染，不许出现 markdown 标记**（`changelog_window_test` 盯着）。
- 测试版走 `beta` 分支（当前就在 `beta`）。
- 界面层不许写 `Duration(milliseconds: …)` / `fontSize:` / `Color(0x…)` 等字面量（`design_tokens_test` 守门）——
  新时长与新常量一律进 `AppTokens`。
- **不要跑 `dart format`**：本仓的工具链是新版格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `analyze`。
- 验收：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿（当前 **706** 条，只增不减）；
  `flutter test tool/visual/` 全绿（当前 **337** 条）。
- 每个 task 结束都要 `git commit`（消息用中文，结尾带 `Co-Authored-By:` 行）。

## Review Focus

规格里没有明说、但**最可能咬到用户**的五类输入 —— 每一类都在下面的 task 里配了会红的用例：

1. **标准档被污染**：改的是共享件与同一个 `_gridBody`，任何一处默认值没守住，标准档那枚块就跟着变。
   （Task 1 / 2 / 3 各有「默认值 = 今天」的用例，Task 8 有逐像素比。）
2. **落定过冲把透镜缩到比格子还小**：Unlift 的过冲会让 `lift < 0`（约 −0.095），
   那时形状比内盒还小、卡片会露出来。规格认了这个量（约 1.1px），但**形状不能崩**。
   （Task 4。）
3. **窄格子上 `cornerR` 比半宽还大**：小窗（200×400）里格宽只有约 25，`cornerR = 16 > 25/2` ——
   必须自动退回胶囊那支，而不是画出一个畸形的圆角方。（Task 1 / 6。）
4. **拖到本月之外的空白格**：`_nearestDateFromVisual()` 返回 `null`，块停在原地但跟手的那套状态还在。
   （Task 6。）
5. **系统字号放大 + 挤字叠加**：格子里的字本来就被 `FittedBox` 缩，外面再套一层 `Transform` 会不会把字挤出格子？
   （Task 3 的纯函数 + Task 6 的「布局不变」用例。）

---

### Task 0: 清场 + 渲一份改动前的基线

探针（上一轮为选型做的一次性代码）还在工作区里没提交。**实施前必须先清掉** ——
否则「标准档逐像素不变」这条验收拿不到干净的起点。

**Files:**
- Delete: `app/tool/visual/tmp_calendar_lens_probe.dart`
- Restore（丢弃工作区的改动）: `app/lib/core/design_tokens.dart`、`app/lib/core/glass/liquid_lens.dart`、`app/lib/features/calendar/calendar_screen.dart`

**Interfaces:**
- Consumes: 无从（第一个 task）
- Produces: `work/baseline5/`（改动前的全套出图，Task 8 逐张比它）

- [ ] **Step 1: 确认工作区里只有探针那四处**

Run: `git status --short`
Expected: 只有 ` M app/lib/core/design_tokens.dart`、` M app/lib/core/glass/liquid_lens.dart`、
` M app/lib/features/calendar/calendar_screen.dart`、`?? app/tool/visual/tmp_calendar_lens_probe.dart` 四行。

- [ ] **Step 2: 丢弃它们**

```bash
git checkout -- app/lib/core/design_tokens.dart app/lib/core/glass/liquid_lens.dart app/lib/features/calendar/calendar_screen.dart
rm app/tool/visual/tmp_calendar_lens_probe.dart
git status --short
```
Expected: 干净（无输出）。

- [ ] **Step 3: 在临时 worktree 里渲基线**

```bash
git worktree add ../shiftassistant-baseline5 dea3d57
cd ../shiftassistant-baseline5/app && ../../shiftassistant/toolchain/flutter/bin/flutter test tool/visual/render_screens_test.dart 2>&1 | tail -3
```
Expected: `All tests passed!`（渲染物落 `../shiftassistant-baseline5/app/build/visual/`）。

- [ ] **Step 4: 把基线搬出来，删掉 worktree**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
rm -rf work/baseline5 && mkdir -p work/baseline5
cp ../shiftassistant-baseline5/app/build/visual/*.png work/baseline5/
git worktree remove --force ../shiftassistant-baseline5
ls work/baseline5 | wc -l
```
Expected: 一个远大于 100 的数（与 `render_screens_test` 的屏数一致）。

---

### Task 1: 共享件 —— `cornerR`（圆角方那一支）

**Files:**
- Modify: `app/lib/core/glass/liquid_lens.dart`（`LiquidLensShape._` 的字段、`.of` 的入参、`_cap`、`toPath()` 的第三条分支、新增 `_roundedRect`）
- Test: `app/test/liquid_lens_test.dart`（追加一组）

**Interfaces:**
- Consumes: 无
- Produces: `LiquidLensShape.of({… double cornerR = double.infinity})`；只读字段 `LiquidLensShape.cornerR`

- [ ] **Step 1: 写失败用例**

追加到 `app/test/liquid_lens_test.dart`（同一份 `shape(...)` 夹具写法，参数照下面给）：

```dart
group('圆角方那一支（cornerR）', () {
  // 日历的格子：内盒 52 × 81、圆角 16。
  LiquidLensShape s({double cornerR = double.infinity}) => LiquidLensShape.of(
      itemW: 52, capsuleH: 85, pad: 2, centerPage: 0,
      lift: 0, velocity: 0, stretch: 0, cornerR: cornerR);

  test('不给 cornerR：还是今天那枚胶囊（半径 = min(高,宽)/2）', () {
    expect(s().leftRadius, closeTo(26, 0.01)); // min(81, 52) / 2
  });

  test('给了 cornerR：端头半径就是它，轮廓是那个矩形', () {
    final LiquidLensShape sh = s(cornerR: 16);
    expect(sh.leftRadius, closeTo(16, 0.01));
    final Rect b = sh.toPath().getBounds();
    expect(b.width, closeTo(52, 0.01));
    expect(b.height, closeTo(81, 0.01));
  });

  test('圆角方那一支的四角是**真圆**（不是被纵向拉长的椭圆）', () {
    final LiquidLensShape sh = s(cornerR: 16);
    final Rect b = sh.toPath().getBounds();
    // 45° 那一点：真圆的角上 = (r(1−1/√2), r(1−1/√2))；椭圆（竖直档那支会把
    // 半径 26 纵向拉成 40.5）会落在 (4.7, 11.9) —— 差 2.9px，用 0.6 的容差分得开。
    final double k = 16 * (1 - math.sqrt(2) / 2);
    final Offset p = Offset(b.left + k, b.top + k);
    expect(sh.toPath().contains(p + const Offset(0.6, 0.6)), isTrue);
    expect(sh.toPath().contains(p - const Offset(0.6, 0.6)), isFalse);
  });

  test('cornerR 比半宽还大时自动退回胶囊那支（小窗的格宽只有 25）', () {
    // 小窗 200×400：cellW ≈ 25，内盒 21 宽 —— cornerR 16 > 21/2，四角会互相吞掉。
    final LiquidLensShape sh = LiquidLensShape.of(
        itemW: 21, capsuleH: 40, pad: 2, centerPage: 0,
        lift: 0, velocity: 0, cornerR: 16);
    expect(sh.leftRadius, closeTo(21 / 2, 0.01));
    expect(sh.toPath().getBounds().height, closeTo(36, 0.01));
  });
});
```

（文件顶部若没有 `import 'dart:math' as math;` 就补上。）

- [ ] **Step 2: 跑它，确认失败**

Run: `../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: 编译失败 —— `No named parameter with the name 'cornerR'`。

- [ ] **Step 3: 实现**

在 `LiquidLensShape` 上：

1. 私有构造加 `required this.cornerR`；`.of` 加入参 `double cornerR = double.infinity` 并透传。
2. 新增只读字段 `cornerR`（文档见规格 §5.1：默认 ∞ = 今天的行为）。
3. `_cap` 改成 `math.min(cornerR, math.min(height, width) / 2)`。
4. `toPath()` 在最前面插入第三条分支 —— `2 * _cap < math.min(width, height) - 0.01` 时
   返回 `_roundedRect(centerX:…, cy:…, w: width, h: height, rl: _cap, rr: _cap)`；
   `cornerR = ∞` 时 `2·_cap == min(高,宽)`，这条**永远不会进**（既有的横向 / 竖直两支一位不动）。
5. 新增顶层私有函数 `Path _roundedRect({required double centerX, required double cy,
   required double w, required double h, required double rl, required double rr})`：
   从左下角起的四个角，每角 `lineTo` 到切点 + `arcToPoint(radius: Radius.circular(r))`，
   四条边是直线。**不要**复用竖直档的 `_verticalStretched` —— 它会把四个角拉成椭圆。

- [ ] **Step 4: 跑它，确认通过**

Run: `../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: PASS（含既有的那几十条）。

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/glass/liquid_lens.dart app/test/liquid_lens_test.dart
git commit -m "feat(glass): 透镜几何族加 cornerR（圆角方那一支，默认 = 今天的胶囊）"
```

---

### Task 2: 共享件 —— `stretchY`（纵向那一份形变）

**Files:**
- Modify: `app/lib/core/glass/liquid_lens.dart`（`.of` 的入参 + 宽高两条算式）
- Test: `app/test/liquid_lens_test.dart`（追加一组）

**Interfaces:**
- Consumes: Task 1 的 `.of`（同一处改）
- Produces: `LiquidLensShape.of({… double? stretchY})`

- [ ] **Step 1: 写失败用例**

```dart
group('纵向形变（stretchY）', () {
  LiquidLensShape s({required double sx, double? sy}) => LiquidLensShape.of(
      itemW: 88, capsuleH: 64, pad: 10, centerPage: 0, lift: 1, velocity: 0,
      stretch: sx, stretchY: sy,
      metrics: const LiquidLensMetrics(protrude: 10, liftWidth: 10, rimScale: 1));

  test('不给 stretchY：宽高与今天逐字相同', () {
    final LiquidLensShape sh = s(sx: 1);
    expect(sh.width, closeTo(88 * (1 + AppTokens.lensStretch) + 10, 0.001));
    expect(sh.height, closeTo(44 * (1 - AppTokens.lensSquash) + 20, 0.001));
  });

  test('纵向那一份独立：给 vy 时高变高、宽变窄，且不影响横向那一条', () {
    final LiquidLensShape x = s(sx: 1, sy: 0);
    final LiquidLensShape y = s(sx: 0, sy: 1);
    expect(x.width, greaterThan(y.width));
    expect(y.height, greaterThan(x.height));
  });
});
```

- [ ] **Step 2: 跑它，确认失败**

Run: `../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: FAIL —— `No named parameter with the name 'stretchY'`。

- [ ] **Step 3: 实现**

`.of` 里加 `double? stretchY`，取 `final double sy = (stretchY ?? 0).clamp(0.0, 1.0);`，
两条算式改成对称的（规格 §5.2）：

```
width  = itemW·(1 + lensStretch·s − lensSquash·sy) + liftWidth·lift
height = (capsuleH − 2·pad)·(1 + lensStretch·sy − lensSquash·s) + 2·protrude·lift
```

`sy = 0` 时两条**逐字退回**今天的样子（这就是第一条用例钉的东西）。算式先抽成局部变量
`w` / `h` 再传进私有构造，`shouldRepaint` 那几个比较器不用动（它们比的是 `width` / `height`）。

- [ ] **Step 4: 跑它，确认通过**

Run: `../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/glass/liquid_lens.dart app/test/liquid_lens_test.dart
git commit -m "feat(glass): 透镜形变分横纵两份（stretchY 不给 = 今天）"
```

---

### Task 3: 二维挤字纯函数 `lensIconWarp2d`

**Files:**
- Modify: `app/lib/core/glass/liquid_lens.dart`（挨着 `lensIconWarp` 加）
- Test: `app/test/liquid_lens_test.dart`（追加一组）

**Interfaces:**
- Consumes: `lensIconWarp`（一维版，不动它）
- Produces:
  ```dart
  ({double scaleRadial, double scaleTangent, double dx, double dy, double angle})
      lensIconWarp2d({
    required double itemCenterX, required double itemCenterY,
    required double lensCenterX, required double lensCenterY,
    required double lensHalfWidth, required double lensHalfHeight,
  });
  ```

- [ ] **Step 1: 写失败用例**

```dart
group('二维挤字（lensIconWarp2d）', () {
  test('dy = 0 时与一维版逐点相同（底栏与分段器不改字，靠的就是这条）', () {
    for (final double dx in <double>[0, 12, 34, 60, 90]) {
      final ({double scaleX, double scaleY, double dx}) a =
          lensIconWarp(iconCenterX: 60 + dx, lensCenterX: 60, lensHalfWidth: 44);
      final ({double scaleRadial, double scaleTangent, double dx, double dy, double angle}) b =
          lensIconWarp2d(itemCenterX: 60 + dx, itemCenterY: 100,
              lensCenterX: 60, lensCenterY: 100,
              lensHalfWidth: 44, lensHalfHeight: 44);
      expect(b.scaleRadial, closeTo(a.scaleX, 1e-9));
      expect(b.scaleTangent, closeTo(a.scaleY, 1e-9));
      expect(b.dx, closeTo(a.dx, 1e-9));
      expect(b.dy, closeTo(0, 1e-9));
      expect(b.angle, closeTo(0, 1e-9));
    }
  });

  test('正中心不挤（t = 0 权重见底）', () {
    final r = lensIconWarp2d(itemCenterX: 100, itemCenterY: 100,
        lensCenterX: 100, lensCenterY: 100,
        lensHalfWidth: 44, lensHalfHeight: 44);
    expect(r.scaleRadial, 1.0);
    expect(r.dx, 0.0);
    expect(r.dy, 0.0);
  });

  test('峰值在边缘（t = 1 落在轮廓上）', () {
    double pinchAt(double t) => 1 - lensIconWarp2d(
        itemCenterX: 44 * t, itemCenterY: 0, lensCenterX: 0, lensCenterY: 0,
        lensHalfWidth: 44, lensHalfHeight: 44).scaleRadial;
    expect(pinchAt(1), greaterThan(pinchAt(0.6)));
    expect(pinchAt(1), greaterThan(pinchAt(1.4)));
  });

  test('纯竖直偏移：方向朝上、径向压扁', () {
    final r = lensIconWarp2d(itemCenterX: 0, itemCenterY: 40,
        lensCenterX: 0, lensCenterY: 0, lensHalfWidth: 44, lensHalfHeight: 44);
    expect(r.angle, closeTo(math.pi / 2, 1e-6));
    expect(r.scaleRadial, lessThan(1));
    expect(r.scaleTangent, greaterThan(1));
    expect(r.dy, greaterThan(0));
  });
});
```

- [ ] **Step 2: 跑它，确认失败**

Run: `../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: FAIL —— `lensIconWarp2d` isn't defined。

- [ ] **Step 3: 实现**

算法（照规格 §6）：`t = √(((cx−lx)/hw)² + ((cy−ly)/hh)²)`；`u = (t−1)/AppTokens.lensIconRingSigma`；
`w = exp(−u²)`；`w < 0.01` 直接返回恒等（`scaleRadial = scaleTangent = 1`、`dx = dy = angle = 0`）；
否则 `pinch = AppTokens.lensIconPinch·w`、`push = AppTokens.lensIconPush·w`，
`angle = atan2(dy, dx)`，`scaleRadial = 1 − pinch`、`scaleTangent = 1 + pinch`、
`dx = push·cos(angle)·sign`、`dy = push·sin(angle)·sign`。

⚠️ **符号与一维版对齐**：一维版是 `dx = (iconCenterX >= lensCenterX ? 1 : −1) · push · w` ——
也就是**朝远离透镜中心的方向推**。二维版按 `sign(dx)` / `sign(dy)` 各自取号，
`dy = 0` 时才与一维版逐位相同（第一条用例会照出来）。

- [ ] **Step 4: 跑它，确认通过**

Run: `../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/glass/liquid_lens.dart app/test/liquid_lens_test.dart
git commit -m "feat(glass): 挤字补二维版（一维版是它 dy=0 的特例）"
```

---

### Task 4: `CalendarLens` 部件 —— 形状与升程

**Files:**
- Create: `app/lib/features/calendar/calendar_lens.dart`
- Test: `app/test/calendar_lens_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 / 2 的 `LiquidLensShape.of`（`cornerR` / `stretchY`）、`LiquidLens`、
  `LiquidLensSpring`、`AppTokens` 的 `lensLiftOmega` / `lensLiftZeta` / `lensDropOmega` / `lensDropZeta`
- Produces:
  ```dart
  class CalendarLens extends StatefulWidget {
    const CalendarLens({
      super.key,
      required this.size,        // 格子盒（cellW × cellH）
      required this.liftTarget,  // 1 = 按住 / 拖动中，0 = 松手
      required this.dragging,    // 手指还在不在
      required this.velocity,    // 拖动速度采样（px/s，逻辑像素）
      required this.isDark,
      required this.accent,
    });
  }
  ```
  它内部固定：内盒 = `size` 内缩 `AppTokens.gapHair`、`cornerR = AppTokens.radiusM`、
  `protrude = 6`、`liftWidth = 12`、`rimScale = size.height / AppTokens.lensRimRefCapsuleH`

- [ ] **Step 1: 写失败用例**

```dart
// app/test/calendar_lens_test.dart
//
// `CalendarLens` 是日历那枚液态玻璃块的全部：升程弹簧、环的弹簧、速度低通与 ticker
// 都关在里面，外面只喂三个数（在哪儿 / 按住没有 / 拖动速度）。这里钉它的**几何**。
//
// ⚠️ 一律走几何与帧调度，**不拿光栅亮度当判据**：那枚块压在白色卡片上，
// 亮度差被卡片自己的底色吃掉（日历页那条「缝隙量不出来」的教训）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/features/calendar/calendar_lens.dart';

void main() {
  const Size box = Size(56.6, 85); // 400dp 宽屏上的格子
  const double innerH = 85 - 2 * 2; // 内盒高 = 盒子内缩 gapHair 各 2

  Future<void> mount(WidgetTester tester,
      {required double liftTarget, bool dragging = false, Offset velocity = Offset.zero}) async {
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
        child: SizedBox(
          width: box.width,
          height: box.height,
          child: CalendarLens(
            size: box, liftTarget: liftTarget, dragging: dragging,
            velocity: velocity, isDark: false,
            accent: const Color(0xFF4C8DFF),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  LiquidLensShape shapeOf(WidgetTester tester) =>
      tester.widget<LiquidLens>(find.byType(LiquidLens)).shape;

  testWidgets('静止：透镜正好覆盖格子内盒，升程为 0', (tester) async {
    await mount(tester, liftTarget: 0);
    final LiquidLens lens = tester.widget<LiquidLens>(find.byType(LiquidLens));
    expect(lens.lift, closeTo(0, 0.01));
    expect(shapeOf(tester).height, closeTo(innerH, 0.01));
    expect(shapeOf(tester).width, closeTo(box.width - 4, 0.01));
  });

  testWidgets('按住：四面各鼓出 protrude，且**与速度无关**', (tester) async {
    for (final Offset v in <Offset>[Offset.zero, const Offset(900, 0)]) {
      await mount(tester, liftTarget: 1, dragging: true, velocity: v);
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        shapeOf(tester).height - innerH,
        closeTo(2 * 6, 0.6), // 2 × protrude
        reason: '凸出量被形变吃掉了（速度 $v）—— v0.10.6 那条乘法顺序的坑',
      );
    }
  });

  testWidgets('落定：过冲到负升程时形状仍然合法（不崩、面积为正）', (tester) async {
    await mount(tester, liftTarget: 1);
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 松手 → Unlift 的过冲会把升程带到 0 以下。
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester, liftTarget: 0);
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final Rect b = shapeOf(tester).toPath().getBounds();
      expect(b.width, greaterThan(0));
      expect(b.height, greaterThan(0));
    }
  });

  testWidgets('静止之后没有在跑的 ticker', (tester) async {
    await mount(tester, liftTarget: 0);
    await tester.pumpAndSettle(); // 有常驻动画的话这里直接超时
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
```

- [ ] **Step 2: 跑它，确认失败**

Run: `../toolchain/flutter/bin/flutter test test/calendar_lens_test.dart`
Expected: FAIL —— `calendar_lens.dart` 不存在。

- [ ] **Step 3: 实现 `CalendarLens`**

要点（其余照现有部件的写法）：

- `SingleTickerProviderStateMixin` + 一个 `Ticker`，`_syncTicker()` 按「两条弹簧都 `isAtRest`」起停
  （环那条弹簧 Task 5 才加，先留一个 `_ring` 占位或者直接写死静止）。
- `_lift`：`LiquidLensSpring(target: widget.liftTarget, …)`；`didUpdateWidget` 里
  `target` 变了就**按方向换那两条参数**（0 → 1 用 `lensLiftOmega / lensLiftZeta`，
  1 → 0 用 `lensDropOmega / lensDropZeta`）。
- 每帧 `setState` 用 `_lift.value` 算 `LiquidLensShape.of(itemW: size.width - 2·gapHair,
  capsuleH: size.height, pad: gapHair, centerPage: 0, lift: _lift.value, velocity: …,
  metrics: LiquidLensMetrics(protrude: 6, liftWidth: 12, rimScale: size.height / lensRimRefCapsuleH,
  velocityRef: 400), cornerR: AppTokens.radiusM)`。
- 本体那一层与 2px 主色描边：`LiquidLens(…, fill: [accent 0.22, accent 0.10],
  showRefractedEdge: false)`，上面再压一层 `CustomPaint` 画 `shape.toPath()` 的 2px 主色描边
  （与标准档那枚块一样的识别符号）。
- **不要**读 `liquidGlassActive`（判据只许出现在调用点，`liquid_scope_guard_test` 盯着）。

- [ ] **Step 4: 跑它，确认通过**

Run: `../toolchain/flutter/bin/flutter test test/calendar_lens_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/calendar_lens.dart app/test/calendar_lens_test.dart
git commit -m "feat(calendar): 液态档那枚块的形状与升程（弹簧 + ticker 关在部件里）"
```

---

### Task 5: 速度 → 形变 + 光谱环

**Files:**
- Modify: `app/lib/features/calendar/calendar_lens.dart`
- Test: `app/test/calendar_lens_test.dart`（追加一组）

**Interfaces:**
- Consumes: Task 4 的 `CalendarLens`（同一个类的下一半）
- Produces: `CalendarLens.velocity` / `CalendarLens.dragging` 的最终语义 ——
  拖动中按采样值走；`dragging` 转 false 之后按每帧 ×0.72 衰减到 0

- [ ] **Step 1: 写失败用例**

```dart
group('拖动中的形变与光谱环', () {
  testWidgets('横向速度拉宽压矮、纵向速度拉高收窄', (tester) async {
    await mount(tester, liftTarget: 1, dragging: true, velocity: const Offset(600, 0));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final LiquidLensShape x = shapeOf(tester);
    await mount(tester, liftTarget: 1, dragging: true, velocity: const Offset(0, 600));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final LiquidLensShape y = shapeOf(tester);
    expect(x.width, greaterThan(y.width));
    expect(y.height, greaterThan(x.height));
  });

  testWidgets('环是渐入渐出的，不是一动就满', (tester) async {
    await mount(tester, liftTarget: 1, dragging: true, velocity: const Offset(600, 0));
    await tester.pump(const Duration(milliseconds: 110));
    final double early = shapeOf(tester).motion;
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(early, lessThan(0.9), reason: '彩边一上来就满 —— 渐入那条弹簧没接上');
    expect(shapeOf(tester).motion, greaterThan(0.95));
  });

  testWidgets('松手之后速度衰减到 0、环熄灭（静止时没有彩色像素）', (tester) async {
    await mount(tester, liftTarget: 1, dragging: true, velocity: const Offset(600, 0));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await mount(tester, liftTarget: 0, dragging: false);
    for (int i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(shapeOf(tester).motion, closeTo(0, 0.02));
    expect(shapeOf(tester).width, closeTo(box.width - 4, 0.5));
  });
});
```

- [ ] **Step 2: 跑它，确认失败**

Run: `../toolchain/flutter/bin/flutter test test/calendar_lens_test.dart`
Expected: FAIL —— `motion` 恒为 0 / 宽高不随速度变。

- [ ] **Step 3: 实现**

- **速度**：拖动中每帧把 `_vx/_vy` 低通到 `widget.velocity`（`_vx = _vx*0.6 + v*0.4`）；
  `dragging` 转 false 之后每帧 `× 0.72` 直到小于 1。
- **形变**：`stretch = (|vx|/400).clamp(0,1)`、`stretchY = (|vy|/400).clamp(0,1)` 传给 `of`。
- **环**：新增 `_ring = LiquidLensSpring(target: …, omega: AppTokens.lensLitOmega, zeta: AppTokens.lensLitZeta)`；
  目标 = 「合速度 > 0」；落到 0 时换成 `lensUnlitOmega / lensUnlitZeta`；
  `motion: _ring.value.clamp(0, 1)` 传给 `of`（**不给速度让它自己现推** —— 那会一跳到底）。
- **`_syncTicker` 必须带上 `_ring`**：漏掉它，彩边会被冻在屏幕上（v0.10.8 记过）。

- [ ] **Step 4: 跑它，确认通过**

Run: `../toolchain/flutter/bin/flutter test test/calendar_lens_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/calendar_lens.dart app/test/calendar_lens_test.dart
git commit -m "feat(calendar): 拖动形变按速度分量走，彩边渐入渐出"
```

---

### Task 6: 接进日历（两棵树 + 喂速度 + 二维挤字）

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`（`_gridBody` 的 `AnimatedScale`、
  `_glassBlock`、`onPanStart/onPanUpdate/onPanEnd`、`_dayRows`、`_dayCell`）
- Test: `app/test/calendar_screen_test.dart`（追加一组）

**Interfaces:**
- Consumes: Task 3 的 `lensIconWarp2d`、Task 4 / 5 的 `CalendarLens`、`lensVelocityStep`
- Produces: 无（叶子）

- [ ] **Step 1: 写失败用例**

```dart
group('液态档那枚块', () {
  testWidgets('标准档与液态档是两棵树（标准档一点没变）', (tester) async {
    await pumpCalendar(tester, liquid: false);
    expect(find.byType(LiquidLens), findsNothing);
    await pumpCalendar(tester, liquid: true);
    expect(find.byType(CalendarLens), findsOneWidget);
  });

  testWidgets('液态档按住的倍率恒为 1.0（按住那个动作由鼓出承担）', (tester) async {
    await pumpCalendar(tester, liquid: true);
    await tester.startGesture(tester.getCenter(
        find.byKey(ValueKey('day-card-${DateTime.now().day}'))));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_blockScale(tester), 1.0);
  });

  testWidgets('挤字只变换绘制、不改布局', (tester) async {
    await pumpCalendar(tester, liquid: true);
    final Size before = tester.getSize(find.byKey(ValueKey('day-card-2')));
    await tester.startGesture(…); // 按住在 1 号那格 → 2 号格的内容被挤
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getSize(find.byKey(ValueKey('day-card-2'))), before);
  });

  testWidgets('小窗 200×400：不崩，且形状自动退回胶囊那支', (tester) async {
    await pumpCalendar(tester, liquid: true, size: const Size(200, 400));
    // 格宽只有约 25 —— cornerR(16) 比半宽还大，`_cap` 被钳住、走竖直档。
    expect(tester.takeException(), isNull);
    expect(find.byType(CalendarLens), findsOneWidget);
  });

  testWidgets('拖到本月之外的空白格：不崩、块照旧跟手', (tester) async {
    await pumpCalendar(tester, liquid: true);
    // 从今天那格往右拖出网格（今天在 10 月 1 日 = 第 0 行第 3 列，往右 4 格出界）。
    final TestGesture g = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('day-card-${DateTime.now().day}'))));
    for (int i = 0; i < 20; i++) {
      await g.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(CalendarLens), findsOneWidget);
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
  });
});
```

（`pumpCalendar` 是既有夹具，加 `bool liquid` 与 `Size size` 两个可选参数：
`liquidGlassActive.value = liquid` + `addTearDown(() => liquidGlassActive.value = false)`；
`_blockScale` 是文件里现成的助手。）

- [ ] **Step 2: 跑它，确认失败**

Run: `../toolchain/flutter/bin/flutter test test/calendar_screen_test.dart`
Expected: FAIL —— `pumpCalendar` 没有 `liquid` 参数 / 找不到 `CalendarLens`。

- [ ] **Step 3: 实现**

1. **分档**：`_gridBody` 与 `_glassBlock` 各分一次叉 ——
   - `AnimatedScale(scale: _pressed && !liquidGlassActive.value ? 1.22 : 1.0, …)`；
   - `_glassBlock` 在 `liquidGlassActive.value` 为真时返回 `CalendarLens(size: Size(cellW, cellH),
     liftTarget: (_pressed || _dragActive) ? 1 : 0, dragging: _dragActive,
     velocity: Offset(_vx, _vy), isDark: …, accent: …)`。
   两处**都要**读档位，但它们都在同一个文件、同一棵子树里，语义一致。
2. **速度**：State 里加 `_vx / _vy / _lastStamp / _lastVisualCol / _lastVisualRow`；
   `onPanUpdate` 里照响铃页那枚药丸的写法算 —— **只在帧戳真的变了时才算**
   （`SchedulerBinding.instance.currentSystemFrameTimeStamp` 与上一帧不同；同一帧 rebuild
   多次是常态，第二遍进来位移已被吃掉、会算出 0），算式用 `lensVelocityStep`，
   `itemW` 传 `cellW`；`onPanEnd` 把 `_vx / _vy` 归零（之后的衰减交给 `CalendarLens`）。
3. **挤字**：`_dayRows` 里按透镜中心（`blockLeft + cellW/2`、`blockTop + cellH/2`）算每格的
   `Matrix4? warp`，**只在液态档算**；半径用**满升程 + 满形变**那两个值：

   ```
   hw = ((cellW − 2·gapHair)·(1 + lensStretch) + 2·protrude) / 2
   hh = ((cellH − 2·gapHair)·(1 + lensStretch) + 2·protrude) / 2
   ```

   矩阵按 `translate(dx, dy) ∘ rotate(angle) ∘ scale(scaleRadial, scaleTangent) ∘ rotate(−angle)`
   拼（`Matrix4.identity()..translateByDouble(…)..rotateZ(…)..scaleByDouble(…)..rotateZ(…)`）。
   `_dayCell` 加命名参数 `Matrix4? warp`，把**内容那一层**（`FittedBox` 外面）包进
   `Transform(alignment: Alignment.center, transform: warp)`；`warp == null` 时**一层都不套**。
4. **空白格**：`_nearestDateFromVisual()` 返回 null 时（拖到本月之外）照旧 ——
   `CalendarLens` 只认位置与速度，不认「那格是不是本月的」。

- [ ] **Step 4: 跑它，确认通过**

Run: `../toolchain/flutter/bin/flutter test test/calendar_screen_test.dart`
Expected: PASS（含既有的全部日历用例 —— **`_blockScale` 那条按住 1.22 的必须还绿**，
它跑在标准档上）。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_screen_test.dart
git commit -m "feat(calendar): 选中块按档位分两棵树，拖动喂速度、内容被挤"
```

---

### Task 7: 判据名单 6 → 7

**Files:**
- Modify: `app/test/liquid_scope_guard_test.dart`
- Test: 同上（这条守门自己就是测试）

**Interfaces:**
- Consumes: Task 6 在 `calendar_screen.dart` 里读 `liquidGlassActive`
- Produces: 无

- [ ] **Step 1: 改两条断言**

`_allowed` 加 `'lib/features/calendar/calendar_screen.dart',`（放到 `alarm_ringing_screen.dart` 之前，
顺序不影响结果 —— 前缀匹配）；自证那条的期望列表加同一行（**按字典序**：
`lib/features/alarm/…` < `lib/features/calendar/…` < `lib/features/home/…`）。

⚠️ **`calendar_lens.dart` 不进名单** —— 它不读档位（与 `liquid_track.dart` 同一条纪律）。
名单里多写一处也是一种错误。

- [ ] **Step 2: 跑它，确认通过**

Run: `../toolchain/flutter/bin/flutter test test/liquid_scope_guard_test.dart`
Expected: PASS。若第一条红：真有文件在允许的位置之外读了它；若自证那条红：名单与 `_allowed` 不同步。

- [ ] **Step 3: 提交**

```bash
git add app/test/liquid_scope_guard_test.dart
git commit -m "test(guard): 液态档判据名单 6 → 7（日历那枚块）"
```

---

### Task 8: 屏单三张 + 出图 + 标准档逐像素验收

**Files:**
- Modify: `app/tool/visual/visual_screens.dart`（新增一屏 + `screenExtraPrefs`）
- Modify: `app/tool/visual/render_screens_test.dart`（两个带手势的屏）

**Interfaces:**
- Consumes: Task 0 的 `work/baseline5/`、Task 6 的两棵树
- Produces: 无（验收）

- [ ] **Step 1: 加屏单**

`visualScreens` 追加一条 `48_calendar_lens`（`title: '日历 · 液态档选中块'`、`build: (db) async => const CalendarScreen()`）；
`screenExtraPrefs` 的 switch 加上 `'48_calendar_lens' || '49_calendar_lens_press' || '50_calendar_lens_drag'`。

`render_screens_test.dart` 里照 `01_calendar_day_selected` 的写法加两个 `visualTest`：
`49_calendar_lens_press`（`beforeCapture` 里 `startGesture` 按住今天那格）与
`50_calendar_lens_drag`（按住后分 8 步 `moveBy` 半格，**不松手**）——
两者都要 `extraPrefs: {'liquidGlass': true}`，并在 `beforeCapture` 之前
`useLiquidGlassTier()`（屏单循环里那条 v0.10.13 的教训：不读 provider 的屏要手动拨档；
日历页会读 provider，prefs 就够 —— 但两处都写最稳）。

- [ ] **Step 2: 出图**

Run: `../toolchain/flutter/bin/flutter test tool/visual/render_screens_test.dart 2>&1 | tail -3`
Expected: `All tests passed!`

- [ ] **Step 3: 看这三张图**

用 Read 打开 `app/build/visual/48_calendar_lens_light.png`、`49_calendar_lens_press_light.png`、
`50_calendar_lens_drag_light.png`（各再看一眼 `_dark`）。
Expected: 静止那张与 `01_calendar` 几乎一样；按住那张四面鼓出；拖动那张有彩边。
**看出来的问题就是问题 —— 这一屏此前没有任何眼睛。**

顺手量一下「液态档静止帧 vs 标准档那枚」的差：预期**格内平均约 17/255**、
最大 164（那几列是 2px 描边从「画在框内侧」变成「压在轮廓线上」，差 1px）。
这是**有意**的差别（规格 §8 第 2 条记着），不是回归 —— 但要是量出比这大得多，
说明填充或描边接错了。

- [ ] **Step 4: 与基线逐张比（标准档不许变）**

```bash
python scripts/diff_visual.py --a work/baseline5 --b app/build/visual
```
Expected: 差异名单里**只剩本轮有意改的那几张**（48 / 49 / 50 与它们的两字简称 / 已调整等变体）。
**有任何一张别的图不同就停在这里解决，不往下走。**

- [ ] **Step 5: 提交**

```bash
git add app/tool/visual/visual_screens.dart app/tool/visual/render_screens_test.dart
git commit -m "test(visual): 日历液态档选中块三屏（静止 / 按住 / 拖动中）"
```

---

### Task 9: 收尾（版本号 / 更新日志 / AGENTS.md / 全量）

**Files:**
- Modify: `app/pubspec.yaml`、`app/lib/core/app_info.dart`、`app/lib/features/profile/app_dialogs.dart`、`AGENTS.md`

**Interfaces:**
- Consumes: 前面全部
- Produces: 可发布的提交

- [ ] **Step 1: 版本号两处同步**

`app/pubspec.yaml` 的 `version: 0.10.15+139`；`app/lib/core/app_info.dart` 的 `appVersion = '0.10.15'`。

- [ ] **Step 2: 更新日志 prepend 一条**

`_changelogZh` / `_changelogEn` 各 prepend 一条（删最旧一条、窗口仍 10 条），**纯文本、无 markdown 标记**。

- [ ] **Step 3: `AGENTS.md` 补 v0.10.15**

版本史那一长行末尾追加；「最近改动」区新增一整条，写清：形状为什么选 A、两条被否掉的效果及理由、
共享件加的两维、以及验收数字。

- [ ] **Step 4: 全量验收**

Run: `../toolchain/flutter/bin/flutter analyze && ../toolchain/flutter/bin/flutter test 2>&1 | tail -3 && ../toolchain/flutter/bin/flutter test tool/visual/ 2>&1 | tail -3`
Expected: analyze 0 issue；`flutter test` 全绿（706 + 本轮新增）；`tool/visual` 全绿（337 + 新增屏）。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "chore(release): v0.10.15（日历选中块的液态玻璃化）"
```

---

### Task 10: 发布 + 装真机

**Files:** 无（产物落 `dist/`）

**Interfaces:**
- Consumes: Task 9 的提交
- Produces: GitHub Release + 真机上的新版

- [ ] **Step 1: 构建**

```bash
cd app && ../toolchain/flutter/bin/flutter build apk --release --target-platform android-arm64
```
Expected: `app/build/app/outputs/flutter-apk/app-release.apk`（约 21MB）。

- [ ] **Step 2: 分发 + 校验**

```bash
mkdir -p ../dist && cp build/app/outputs/flutter-apk/app-release.apk ../dist/倒班助手Pro-v0.10.15.apk
"$ANDROID_HOME"/build-tools/*/aapt2 dump badging ../dist/倒班助手Pro-v0.10.15.apk | head -1
```
Expected: `package: name='com.daoban.shiftassistantpro' versionCode='139' versionName='0.10.15'`。

（先 `. tools/build-env.ps1` 之类的环境变量设定照本仓惯例；`$ANDROID_HOME` 指向 `toolchain/`。）

- [ ] **Step 3: 推送 + 打标签 + 发布**

```bash
git push origin beta && git tag v0.10.15 && git push origin v0.10.15
pwsh -File scripts/release.ps1 -SkipConfirm
```
发布说明先写到 `tools/gh/release-notes-v0.10.15.md`（脚本会自动复用）。
⚠️ **`release.ps1` 不构建 APK**，它只复制现成的 —— Step 1 必须先跑。
⚠️ 只有在 dot-source 了 `build-env.ps1` 的会话里才设 `GH_CONFIG_DIR`（否则反而弄坏登录态）。

- [ ] **Step 4: 核对 main 上的发布清单**

```bash
curl -s https://raw.githubusercontent.com/Alec-WangLi/DaoBanAssistantPro/main/latest.json | head -5
```
Expected: 里面有 `0.10.15`。**脚本打印的「发布成功」只覆盖 Release 上传那一步**，这一步不能省。

- [ ] **Step 5: 装到真机**

```bash
adb install -r dist/倒班助手Pro-v0.10.15.apk && adb shell dumpsys package com.daoban.shiftassistantpro | grep versionName
```
Expected: `versionName=0.10.15`。（没接设备时跳过，并在交付说明里写明「未装」——别当成已验。）

- [ ] **Step 6: 真机上量一次帧时间（规格 §10 要求，不靠估）**

打开「我的 → 外观 → 液态玻璃」，回日历**按住并来回拖**十几秒，然后：

```bash
adb shell dumpsys gfxinfo com.daoban.shiftassistantpro reset
# （在真机上拖十来秒）
adb shell dumpsys gfxinfo com.daoban.shiftassistantpro | grep -A 4 "Janky frames"
```
Expected: 掉帧比例与标准档**同一量级**（先关掉液态玻璃录一次当对照）。
本轮新增的是 42 次矩阵计算 + 几个 `Transform`，以及静止时多一层 `ClipPath` ——
若掉帧明显变差，先看是不是 `CalendarLens` 在静止时还在推帧。
