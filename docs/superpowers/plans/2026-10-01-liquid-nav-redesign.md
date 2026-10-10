# 底栏液态玻璃重做 · 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把底栏的液态档从「给滑块贴一层光」改成「一枚独立、会动、会形变的玻璃滴」——按住吸附到手指并放大、拖动时形状跟着速度形变、边缘带一圈以主色为锚的彩色折射光，且透镜里能看见底下的胶囊被放大。

**Architecture:** 底栏 `build` 里直接分叉成**两棵树**：标准档走今天那段代码（一个字符不动），液态档走新的三层树（胶囊 / 透镜 / 图标）。透镜由一个自写的阻尼谐振子驱动，几何是一枚「两端半径不同的圆 + 外公切线」的水滴；「弯掉底下的东西」用 SDK 自带的 `ImageFilter.matrix` 在透镜形状里放大背景（零 shader）。手势与动画状态机两档共用，一行不改 —— 交互契约因此结构上不可能不一致。

**Tech Stack:** Flutter 3.47.2 stable / Dart 3.13.2 · `dart:ui` 的 `ImageFilter.matrix` / `ClipPath` / `CustomPainter` · 现有 `AppTokens` 令牌体系 · `app/tool/visual` 工装 + `scripts/make_gif.py`。

**Spec:** `docs/superpowers/specs/2026-10-01-liquid-nav-redesign-design.md`

## Global Constraints

- **版本**：本轮目标 `0.10.3+127`。`app/pubspec.yaml` 的 `version:` 与 `app/lib/core/app_info.dart` 的 `appVersion` **两处同步**（`app/test/app_info_test.dart` 盯着）。`X.Y` 归用户，`Z` 与 `build` 归实现者。分支 **`beta`**。
- **标准档一个像素都不许变**：`00_home_shell_*` 等标准档工装图与改动前逐像素相同。液态档换的**只有视觉** —— 交互契约（点按即切页 / 长按吸附不切页 / 松手才提交）两档一字不差。
- **不引入任何新依赖**，不新增 shader 构建链，不动 `pubspec.yaml` 的 `dependencies` 与 `shaders:`。
- **`lib/core/glass/` 在 `design_tokens_test` 的扫描范围内**：新代码不许出现 `Color(0x…)` 字面量、`fontSize:` / `fontWeight:`、`Duration(milliseconds: …)`、`circular(<数字>)`、以及不在 4px 栅格上的**间距类**常量（名字含 Pad / Gap / Inset / Spacing）。所有数值进 `AppTokens`；主色走 `Theme.of(context).colorScheme.primary`，白/黑走既有的 `Colors.white/black.withValues(alpha:)` 豁免路径。
- **`liquidGlassActive` 只许出现在 `core/glass/glass.dart`（定义处）与 `features/home/` 下**（由本计划的护栏用例强制）。
- 跑测试一律 `cd app && ../toolchain/flutter/bin/flutter test <path>`；`pubspec` 改了先跑一次让依赖解析完。
- 收尾：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿（当前 555 条，只增不减）；`flutter test tool/visual/` 全绿。

## Review Focus

| # | 会咬人的输入 / 条件 | 合理的人会期望什么 |
|---|---|---|
| 1 | **窄窗**（工装的 200×400）：`itemW ≈ 39`，而静止时两端圆的半径各是 `h/2 = 20` —— 两个圆在形状里**重叠**，外公切线不存在 | 透镜仍然是一枚正常的胶囊；几何构造在任何宽度下都不许抛异常或画出乱形 |
| 2 | **点按被取消**（在胶囊上按下后竖直滑动）：`onTapCancel` 现在是个空回调，`_pressed` 会**永远卡在 true** | 透镜落回原处、不再凸出；胶囊也回到常态 |
| 3 | **短屏 / 横屏**（`AppLayout.isShort`，胶囊高 52 而不是 64）：透镜的每一处几何都按 `capsuleH` 算 | 矮屏上透镜该凸出多少、凸出后会不会顶出可视区，都要按那一档算，不是照抄 64 的结论 |
| 4 | **连续快速点按两个不同的 tab**：弹簧跑在半路时目标被第二次改写 | 平滑地改道，不抖、不发散、不出现「先冲过头再倒回来」的反复 |
| 5 | **换主色**（五种里 teal 2.63:1 / orange 2.55:1 本来就不达 AA）：光谱环锚在主色上，会改变透镜背后那层的明度 | 导航选中项的白字仍然是可读的；不达标时要按 `AppTokens.onSolid` 的路子处理，而不是放着 |

---

### Task 1: 把液态档收拢到底栏

液态档现阶段只作用于底栏。把四个共享玻璃件上的液态效果摘掉，并删掉随之变成死代码的那部分。

**Files:**
- Modify: `app/lib/core/glass/glass.dart:118-129`（`GlassPanel` 里的 `GlassRim` 包裹）
- Modify: `app/lib/core/glass/glass.dart:271-330, 524-579`（删 `GlassLensGlow` 与 `_LensGlowPainter`）
- Modify: `app/lib/core/widgets/glass_pill.dart:88-105`（回退到 `git show v0.10.0:app/lib/core/widgets/glass_pill.dart` 的形态）
- Modify: `app/lib/core/widgets/glass_segment.dart:125-215`
- Modify: `app/lib/core/widgets/glass_switch.dart:36-197`
- Modify: `app/lib/core/design_tokens.dart`（删 `segmentLensProtrude`、`switchLensProtrude`）
- Create: `app/test/liquid_scope_guard_test.dart`

**Interfaces:**
- Consumes: 无。
- Produces: `GlassRim` / `_RimPainter` **保留在 `glass.dart`**（底栏还在用，Task 9 才删）；`GlassLensGlow` / `_LensGlowPainter` 删除。`AppTokens.navLensProtrude` 保留。

- [ ] **Step 1: 先冻结标准档基线**

```bash
cd app && ../toolchain/flutter/bin/flutter test tool/visual/render_screens_test.dart
mkdir -p build/visual/baseline-v0102 && cp build/visual/*.png build/visual/baseline-v0102/
```

Expected: 全部通过，`app/build/visual/` 下生成 181+ 张 PNG，副本落在 `baseline-v0102/`。

**先确认这些图确实是改动前渲的**（v0.10.1 那轮吃过「基线本身早于目标版本」的假差异）：`git status` 现在应当只有 spec 与探针两个文件是新增的，`lib/` 无改动。

- [ ] **Step 2: 摘掉四处调用 + 删掉立刻变成死代码的部分**

按下面的清单逐处改。**`glass_segment.dart` 与 `glass_switch.dart` 可以直接对着 `git diff v0.10.0 HEAD -- <file>` 回退**，只有两处例外要记住：

1. `glass_segment.dart` 的拖动状态机（`_press` / `_dragStart` / `_dragUpdate` / `_release` / `_cancel` / `_visual` / `_dragging`）**是 v0.10.0 就有的，不要动** —— 只删 `liquid` / `protrude` / `thumbH` 三个变量、`GlassRim` 包裹层、`GlassLensGlow` 包裹层，以及 `AnimatedPositioned` 的 `top` / `bottom` 从 `inset - protrude` 回到 `inset`。
2. `glass_switch.dart` 的 **`enabled` 参数要保留**（v0.10.0 没有它，是 v0.10.2 新增的；`profile_screen.dart` 传 `!lowEndDevice`，低内存机器那一行要置灰）。要删的是：`_pressed` / `_dragT` / `_t` / `tFor` / `endDrag`、五个 `onHorizontalDrag*` 与三个 `onTap*` 回调里的 liquid 三元、`liquid` / `swelled` / `protrude` 变量、`knob()` 里 `swelled ? … : …` 的每一处分支（回到「白圆 + `enabled` 决定透明度」），以及 `child:` 那个 `swelled ? Stack(...) : AnimatedAlign(...)` 三元（只留 `AnimatedAlign`，`_t` 换成 `widget.value ? 1.0 : 0.0`，`duration` 回到 `AppTokens.durMed`）。

`glass.dart` 里 `GlassPanel` 的 `_build` 去掉 `if (!solid && blurOn) { panel = GlassRim(...); }` 整段（连带它上面那 12 行注释一起删）。`GlassLensGlow` 与 `_LensGlowPainter` **整个类删掉**。

`design_tokens.dart` 删 `segmentLensProtrude` 与 `switchLensProtrude` 两个常量（连注释），**保留 `navLensProtrude` 与四个 `glassRimProbe*`**。

- [ ] **Step 3: 写源码护栏 `app/test/liquid_scope_guard_test.dart`**

```dart
// 液态档的**作用范围**护栏。
//
// 2026-10-01 用户拍板：「咱们先把这个液态玻璃应用到底部导航栏，之前修改的其他
// 地方先暂时不动。」这条护栏把那个决定变成会失败的用例 —— 将来有人往别的玻璃面
// 搬液态效果而没想清楚，这里会先红，而不是等到用户看见一排描了边的列表行。
//
// 扫描前先剥注释与字符串（同 `haptics_guard_test` 的规矩）：上面这段话里就有
// `liquidGlassActive` 这个词，不剥的话这条用例自己会把自己的注释判成违规。

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 把注释与字符串字面量换成等长的空格，行号与列号因此不变。
String _stripCommentsAndStrings(String src) { /* 与 haptics_guard_test 同一份实现 */ }

void main() {
  test('液态档的判据只许出现在 glass.dart（定义处）与 features/home/ 下', () {
    final List<String> offenders = <String>[];
    for (final FileSystemEntity e
        in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String p = e.path.replaceAll(r'\', '/');
      if (p.endsWith('lib/core/glass/glass.dart')) continue; // 定义处
      if (p.startsWith('lib/features/home/')) continue;      // 唯一的使用处
      if (_stripCommentsAndStrings(e.readAsStringSync())
          .contains('liquidGlassActive')) {
        offenders.add(p);
      }
    }
    expect(offenders, isEmpty,
        reason: '这些文件读了 liquidGlassActive，但液态档现阶段只作用于底栏：$offenders');
  });
}
```

- [ ] **Step 4: 跑护栏，预期失败**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_scope_guard_test.dart`
Expected: FAIL —— `lib/features/home/home_shell.dart` 出现在 offenders 里（它还在读 `liquidGlassActive`）。这是**故意**的：底栏是唯一允许的位置，但它这一版还是老的写法，Task 8 会把它改成走新模块。

把护栏里那行 `if (p.startsWith('lib/features/home/')) continue;` 保留 —— 上面这条失败说明护栏确实在扫、且扫得到。

- [ ] **Step 5: 跑全套测试，修好被牵连的既有用例**

Run: `cd app && ../toolchain/flutter/bin/flutter test`
Expected: 除了 Step 4 那条新护栏，其余全绿。`glass_segment` / `glass_switch` 相关的既有用例若因为删掉液态分支而变红，**按标准档的行为修断言**（例如「按住时把手凸出轨道」这类断言直接删掉，因为它描述的行为已经不存在了）—— **不许为了让用例变绿而放宽断言的鉴别力**。

- [ ] **Step 6: 出图比对，确认标准档没被碰**

Run: `cd app && ../toolchain/flutter/bin/flutter test tool/visual/render_screens_test.dart`

然后逐像素比 `app/build/visual/*.png` 与 `app/build/visual/baseline-v0102/*.png`（写个一次性脚本，或复用仓库既有的比对方式）。Expected: **所有标准档的图逐像素相同**；`37_profile_liquid_*` / `38_alarm_liquid_*` / `39_todos_liquid_*` 变成与各自标准档图一致（这些屏本来就该只在底栏上有差别）；`36_home_shell_liquid_*` 有差异（底栏的液态边光还在，且 Task 8 之后还会再变）。

- [ ] **Step 7: Commit**

```bash
git add app/lib app/test/liquid_scope_guard_test.dart
git commit -m "refactor(glass): 液态档收拢到底栏一处"
```

---

### Task 2: 把底栏抽成独立文件（纯搬移）

底栏现在住在 `home_shell.dart`（640 行）里。液态档那一半还要再进来两百多行 —— 先把它搬出去，让「两棵树」并排待在一个文件里。**这是一次纯搬移，行为一字不变。**

**Files:**
- Create: `app/lib/features/home/glass_nav_bar.dart`
- Modify: `app/lib/features/home/home_shell.dart:276-620`（把 `_GlassNavBar` 与 `_GlassNavBarState` 整段移走）

**Interfaces:**
- Consumes: `AppTokens`、`AppLayout`、`QScale`、`GlassBlur`、`GlassRim`、`AppIcon`。
- Produces: `class GlassNavBar extends StatefulWidget`（原来是私有的 `_GlassNavBar`，搬出去要变成公开的名字），构造签名不变：`GlassNavBar({super.key, required PageController controller, required List<(IconData, String)> items})`。`home_shell.dart` 的 `bottomNavigationBar:` 改成 `GlassNavBar(...)`，`Key('glass-nav-bar')` 保留。

- [ ] **Step 1: 搬移**

整段剪切，**不要顺手改任何一行**（包括注释缩进）。`_GlassNavBarState` 私有，跟过去之后名字不用改。删掉 `home_shell.dart` 里因此变成未使用的 import。

- [ ] **Step 2: 确认没有遗留引用**

Run: `cd app && grep -rn "_GlassNavBar" lib/`
Expected: 无输出。

- [ ] **Step 3: 跑测试**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/home_shell_nav_test.dart test/home_shell_nav_test.dart && ../toolchain/flutter/bin/flutter analyze`
Expected: 通过，0 issue。

- [ ] **Step 4: 出图比对，确认逐像素不变**

Run: `cd app && ../toolchain/flutter/bin/flutter test tool/visual/render_screens_test.dart`

与 `baseline-v0102/` 比。Expected: **`00_home_shell_*` 与基线逐像素相同** —— 纯搬移的验收就是这个。

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/home
git commit -m "refactor(home): 底栏抽成 features/home/glass_nav_bar.dart（纯搬移）"
```

---

### Task 3: 弹簧解算器

透镜由真弹簧驱动而不是补间动画 —— 买的是**速度**（形变要读它）和**过冲**（落回格子那一下）。纯 Dart，可以单独测。

**Files:**
- Create: `app/lib/core/glass/liquid_lens.dart`
- Create: `app/test/liquid_lens_test.dart`
- Modify: `app/lib/core/design_tokens.dart`（新增 `lensOmega` / `lensZeta`）

**Interfaces:**
- Consumes: 无。
- Produces: `class LiquidLensSpring`，签名：

```dart
class LiquidLensSpring {
  LiquidLensSpring({required double target, double value = 0, double velocity = 0});
  double value;
  double velocity;
  double target;
  /// 一步最小二乘积分。dt 超过 [maxStep] 时**按 maxStep 处理**（不是按 dt）。
  void step(Duration dt);
  bool get isAtRest; // |value - target| < 0.01 且 |velocity| < 1
  static const Duration maxStep = Duration(milliseconds: 48);
}
```

`omega` 与 `zeta` 从 `AppTokens.lensOmega` / `AppTokens.lensZeta` 读（`d = 2 * zeta * omega`，`a = -omega² * (value - target) - d * velocity`）。

- [ ] **Step 1: 写失败的测试**

`app/test/liquid_lens_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';

void main() {
  test('收敛：从中点出发最终停到目标上', () {
    final s = LiquidLensSpring(target: 100)..value = 0;
    for (int i = 0; i < 200; i++) {
      s.step(const Duration(milliseconds: 16));
    }
    expect(s.value, closeTo(100, 0.5));
    expect(s.isAtRest, isTrue);
  });

  test('过冲：落回时越过目标再回来（这就是 Q 弹的观感来源）', () {
    final s = LiquidLensSpring(target: 100)..value = 0;
    double peak = 0;
    for (int i = 0; i < 200; i++) {
      s.step(const Duration(milliseconds: 16));
      if (s.value > peak) peak = s.value;
    }
    expect(peak, greaterThan(101),
        reason: '没有过冲 —— 那和 easeOut 没有区别，松手那一下就不会有 Q 弹感');
    expect(peak, lessThan(140), reason: '过冲太大（>40%），读起来是「甩过头」');
  });

  test('不发散：目标半路被改写也不炸', () {
    final s = LiquidLensSpring(target: 100);
    for (int i = 0; i < 5; i++) {
      s.step(const Duration(milliseconds: 16));
    }
    s.target = -100; // 连点另一格
    for (int i = 0; i < 200; i++) {
      s.step(const Duration(milliseconds: 16));
    }
    expect(s.value, closeTo(-100, 0.5));
  });

  test('帧间隔封顶：喂一个 1 秒的 dt，位移不超过按 maxStep 算出来的那一步', () {
    final capped = LiquidLensSpring(target: 100)..step(LiquidLensSpring.maxStep);
    final huge = LiquidLensSpring(target: 100)..step(const Duration(seconds: 1));
    expect(huge.value, closeTo(capped.value, 1e-9),
        reason: '掉帧时按真实 dt 积分会让透镜瞬移，还会把数值积爆');
  });
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: FAIL —— `liquid_lens.dart` 不存在，编译不过。

- [ ] **Step 3: 实现**

在 `app/lib/core/glass/liquid_lens.dart` 写 `LiquidLensSpring`。**先用半隐式欧拉**（`velocity += a * dt; value += velocity * dt`），`dt` 取 `min(dt, maxStep)` 的秒数。`AppTokens` 加：

```dart
/// 透镜弹簧：ω ≈ 2π × 1.8 Hz、ζ = 0.85（欠阻尼一点点 → 有可感的过冲）。
static const double lensOmega = 11.3;
static const double lensZeta = 0.85;
```

**参数按这两条调，别凭手感**：过冲过不了测试就调 `lensZeta`；落回太慢就调 `lensOmega`。落回时间要与标准档的 `durFast`（`AppTokens.durFast`）相当 —— 先把它的值量出来，再回头核一遍。

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: PASS（4 条）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/glass/liquid_lens.dart app/lib/core/design_tokens.dart app/test/liquid_lens_test.dart
git commit -m "feat(glass): 透镜的弹簧解算器"
```

---

### Task 4: 透镜几何

一枚水滴：两端是**圆心同在水平中轴、半径可以不同**的圆，中间用两段**外公切线**连起来；半径相等时退化成标准胶囊。全程闭式解，不是贝塞尔近似 —— 这样「半径相等 ⇒ 胶囊」这条性质可以被直接断言。

**Files:**
- Modify: `app/lib/core/glass/liquid_lens.dart`
- Modify: `app/test/liquid_lens_test.dart`
- Modify: `app/lib/core/design_tokens.dart`（新增 `lensLiftWidth` / `lensVelocityRef`）

**Interfaces:**
- Consumes: `AppTokens.navLensProtrude`、`AppTokens.lensLiftWidth`、`AppTokens.lensVelocityRef`。
- Produces:

```dart
/// 透镜在**胶囊局部坐标**里的一帧几何。纯数据 + 纯函数，不依赖任何 widget。
class LiquidLensShape {
  /// 从手势状态算出这一帧的形状。
  factory LiquidLensShape.of({
    required double itemW,
    required double capsuleH,
    required double pad,
    required double centerPage, // 以「格」为单位的中心位置（可为小数）
    required double lift,       // 0..1
    required double velocity,   // px/s，带符号（正 = 向右）
  });

  double get centerX;
  double get width;
  double get height;
  /// **必须存下来**：透镜铺在胶囊那一格里（`LiquidLens` 的 `size.height == capsuleH`），
  /// 而按住时 `height > capsuleH` —— `toPath()` 要**竖直居中于 `capsuleH / 2`**，
  /// 按自己的 `height / 2` 居中的话凸出会全部跑到下面去。
  double get capsuleH;
  double get leftRadius;
  double get rightRadius;
  Path toPath();
}
```

`centerX = pad + (centerPage + 0.5) * itemW`；`height = (capsuleH - 2 * pad) + 2 * navLensProtrude * lift`；`width = itemW + lensLiftWidth * lift`，再乘速度带来的拉伸。

**端头半径的钳制是这个任务的核心**，见 Step 1。

- [ ] **Step 1: 写失败的测试（先把钳制那条摆上）**

追加到 `app/test/liquid_lens_test.dart`：

```dart
group('透镜几何', () {
  const double itemW = 85, capsuleH = 64, pad = 6;
  LiquidLensShape rest() => LiquidLensShape.of(
      itemW: itemW, capsuleH: capsuleH, pad: pad,
      centerPage: 0, lift: 0, velocity: 0);

  test('静止：是一枚胶囊（两端半径相等、且等于高的一半）', () {
    final s = rest();
    expect(s.width, closeTo(itemW, 0.01));
    expect(s.height, closeTo(capsuleH - 2 * pad, 0.01));
    expect(s.leftRadius, closeTo(s.rightRadius, 0.001));
    expect(s.leftRadius, closeTo(s.height / 2, 0.001));
  });

  test('按住：高度 = 基准 + 2 × navLensProtrude（凸出胶囊）', () {
    final s = LiquidLensShape.of(
        itemW: itemW, capsuleH: capsuleH, pad: pad,
        centerPage: 0, lift: 1, velocity: 0);
    expect(s.height,
        closeTo(capsuleH - 2 * pad + 2 * AppTokens.navLensProtrude, 0.01));
    expect(s.height, greaterThan(capsuleH), reason: '按住时要高于胶囊才叫凸出');
  });

  test('拖动：沿运动方向拉伸、垂直方向压缩（面积近似守恒）', () {
    final s = LiquidLensShape.of(
        itemW: itemW, capsuleH: capsuleH, pad: pad,
        centerPage: 1, lift: 1, velocity: AppTokens.lensVelocityRef);
    expect(s.width, greaterThan(itemW));
    expect(s.height, lessThan(capsuleH - 2 * pad + 2 * AppTokens.navLensProtrude));
  });

  test('拖动：前缘比后缘圆（向右拖时右端半径更大），向左拖镜像', () {
    final right = LiquidLensShape.of(
        itemW: itemW, capsuleH: capsuleH, pad: pad,
        centerPage: 1, lift: 1, velocity: AppTokens.lensVelocityRef);
    expect(right.rightRadius, greaterThan(right.leftRadius));

    final left = LiquidLensShape.of(
        itemW: itemW, capsuleH: capsuleH, pad: pad,
        centerPage: 1, lift: 1, velocity: -AppTokens.lensVelocityRef);
    expect(left.leftRadius, greaterThan(left.rightRadius));
  });

  test('窄窗：两端圆不许重叠（外公切线必须存在），且形状仍闭合', () {
    // 工装的小窗是 200×400：可用宽 = 200 − 2×16 = 168，扣掉 pad ×2 后
    // trackW = 156，n = 4 → itemW = 39；而静止时两端半径各是 h/2 = 20，
    // 两者相加 40 > 39 —— 圆重叠，外公切线不存在。这不是假想的，是算出来的。
    final s = LiquidLensShape.of(
        itemW: 39, capsuleH: 64, pad: 6, centerPage: 1, lift: 1, velocity: 0);
    expect(s.leftRadius + s.rightRadius, lessThanOrEqualTo(s.width + 0.001),
        reason: '两个端头圆重叠了 —— 外公切线不存在，Path 会画出乱形');
    expect(s.toPath().getBounds().isEmpty, isFalse);
  });
});
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: FAIL —— `LiquidLensShape` 未定义。

- [ ] **Step 3: 实现**

在 `liquid_lens.dart` 加 `LiquidLensShape`。要点：

- `stretch = (velocity.abs() / AppTokens.lensVelocityRef).clamp(0.0, 1.0)`（`lensVelocityRef = 1500`，`lensLiftWidth = 10`）。
- `width` 与 `height` 按 spec §5.3 的 `w *= 1 + 0.20·s` / `h *= 1 − 0.12·s` 调，**`height` 的那一次压缩要作用在「按下后」的高度上**（先算 lift 再加 protrude 的顺序会影响断言，按测试写）。
- **端头半径的钳制**：`b = height / 2`，理想的两端半径是 `b · (1 ± 0.25·s·方向)`；然后**必须**再钳一次 `leftRadius + rightRadius <= width` —— 窄窗下不钳就重叠。钳法是各按比例缩到和等于 `width`（保号、保比例），**同时不要破坏「静止时两端相等」那条**（静止时 `s = 0`，两端都是 `b`，钳制只在 `2b > width` 时生效）。
- `toPath()`：两圆的**外公切线**有闭式解（两圆半径差除以圆心距得夹角，再转过去求切点）；用 `Path.arcTo` 走圆弧、`lineTo` 走切线。半径相等时夹角为 0，两段切线自然退化成水平线。

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: PASS（9 条：弹簧 4 + 几何 5）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/glass/liquid_lens.dart app/lib/core/design_tokens.dart app/test/liquid_lens_test.dart
git commit -m "feat(glass): 透镜的水滴几何（外公切线构造 + 窄窗钳制）"
```

---

### Task 5: 透镜的渲染（形状 + 着色 + 阴影，先不放大、先不光谱环）

`LiquidLens` 是一个**参数化**的 widget：给它一帧几何、一个升降程度、一个主色，它就把那枚玻璃滴画出来。它**不读 `liquidGlassActive`** —— 档位判据只在 `features/home/` 里读（护栏用例管着）。

**Files:**
- Modify: `app/lib/core/glass/liquid_lens.dart`
- Modify: `app/test/liquid_lens_test.dart`
- Modify: `app/lib/core/design_tokens.dart`（`lensShadow` / `lensBodyFill`）

**Interfaces:**
- Consumes: `LiquidLensShape`（Task 4）。
- Produces:

```dart
class LiquidLens extends StatelessWidget {
  const LiquidLens({
    super.key,
    required this.size,          // 胶囊的完整尺寸（局部坐标的边界）
    required this.shape,         // 这一帧的几何
    required this.lift,          // 0..1
    required this.isDark,
    required this.accent,        // 主色
    required this.magnifyScale,  // 1.0 = 不放大（Task 6 接）
  });
}
```

- [ ] **Step 1: 写失败的测试（光栅化，不是「有没有画东西」）**

追加。先写一个取像帮手（取像放 `tester.runAsync`，同 `glass_tier_test.dart` 的 `shot()`）：

```dart
/// 光栅化「一枚透镜盖在一块胶囊底上」，返回原始 RGBA。
Future<List<int>> _shotLens(
  WidgetTester tester, {
  required Size canvas,
  required Size capsule,
  required double lift,
  required Color accent,
  double velocity = 0,
  double magnifyScale = 1.0,
  int lineAtX = -1, // >= 0 时在胶囊底上画一条 2px 黑竖线（放大层的用例要用）
}) async {
  final GlobalKey key = GlobalKey();
  final shape = LiquidLensShape.of(
      itemW: capsule.width, capsuleH: capsule.height, pad: 0,
      centerPage: 0, lift: lift, velocity: velocity);
  final double top = (canvas.height - capsule.height) / 2;
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: canvas,
          child: Stack(clipBehavior: Clip.none, children: <Widget>[
            Positioned(left: 0, top: top, width: capsule.width, height: capsule.height,
              child: ColoredBox(color: const Color(0xFFF5F6FA),
                child: lineAtX < 0 ? null : CustomPaint(painter: _LinePainter(lineAtX))),
            ),
            Positioned(left: 0, top: top, width: capsule.width, height: capsule.height,
              child: LiquidLens(size: capsule, shape: shape, lift: lift, isDark: false,
                accent: accent, magnifyScale: magnifyScale)),
          ])))
    )));
  await tester.pumpAndSettle();
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late List<int> bytes;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
    bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer.asUint8List().toList();
    image.dispose();
  });
  return bytes;
}

int _alpha(List<int> px, int w, int x, int y) => px[(y * w + x) * 4 + 3];
```

```dart
const Size _canvas = Size(200, 120);
const Size _capsule = Size(120, 64);

testWidgets('按住时透镜凸出胶囊：外框之外上下各有非透明像素', (tester) async {
  final px = await _shotLens(tester, canvas: _canvas, capsule: _capsule,
      lift: 1, accent: const Color(0xFF12B5A5));
  final int top = ((_canvas.height - _capsule.height) / 2).round();
  expect(_alpha(px, 200, 60, top - 2), greaterThan(0), reason: '没凸出胶囊上沿');
  expect(_alpha(px, 200, 60, top + 64 + 1), greaterThan(0), reason: '没凸出胶囊下沿');
});

testWidgets('静止时不凸出：胶囊外框之外全是透明的', (tester) async {
  // 与上一条是一对 —— 缺了它，上一条可能因为别的原因（比如阴影）变绿。
  final px = await _shotLens(tester, canvas: _canvas, capsule: _capsule,
      lift: 0, accent: const Color(0xFF12B5A5));
  final int top = ((_canvas.height - _capsule.height) / 2).round();
  expect(_alpha(px, 200, 60, top - 2), 0);
  expect(_alpha(px, 200, 60, top + 64 + 1), 0);
});
```

`_LinePainter` 照抄 `test/lens_magnify_probe_test.dart` 的 `_BarPainter`（白底 + 一条 2px 黑竖线），Task 6 要用。

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: FAIL —— `LiquidLens` 未定义。

- [ ] **Step 3: 实现**

`LiquidLens` 的 `build` 是三层（**顺序不能换**）：

```dart
Stack(clipBehavior: Clip.none, children: <Widget>[
  // ① 浮起阴影：在**裁剪之外**（被裁掉的阴影会被切平）
  Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _LensShadowPainter(...)))),
  // ② 本体：被轮廓裁住
  Positioned.fill(child: IgnorePointer(child: ClipPath(
    clipper: _LensClipper(shape),
    child: CustomPaint(painter: _LensBodyPainter(...)),
  ))),
])
```

- `_LensClipper extends CustomClipper<Path>`：`getClip` 返回 `shape.toPath()`；`shouldReclip` 比较 `shape` 的四个数值（`centerX` / `width` / `height` / 两端半径），**别返回 `true` 常量** —— 那会让每一帧都重建裁剪。
- `_LensShadowPainter`：把 `shape.toPath()` 下移几个像素，用 `MaskFilter.blur`，颜色 `Colors.black.withValues(alpha: 0.10 + 0.14 * lift)`。
- `_LensBodyPainter`：用 `AppTokens.accentGradient(accent)` **同标准档那枚滑块一样的半透明配方**填一遍（对比度靠它保住，别改成不透明主色），再叠一条 1px 的白描边（`isDark ? 0.28 : 0.85`）。

`AppTokens` 新增两个函数（数值看图调，实现时给初值即可）：

```dart
/// 透镜浮起时投在胶囊上的阴影。
static BoxShadow lensShadow(bool isDark, double lift) => ...;
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: PASS。若「凸出」那条不过，先查 `shape.toPath()` 的坐标原点 —— 透镜与胶囊必须共用同一套局部坐标（`centerX` 已经含了 `pad`）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/glass/liquid_lens.dart app/lib/core/design_tokens.dart app/test/liquid_lens_test.dart
git commit -m "feat(glass): 透镜本体（轮廓裁剪 + 半透明主色 + 浮起阴影）"
```

---

### Task 6: 放大层 —— 让透镜真的把底下的胶囊弯掉

这是「像一块玻璃」与「像一枚漂亮贴纸」的分界。用 SDK 自带的 `ImageFilter.matrix`，零 shader。

**Files:**
- Modify: `app/lib/core/glass/liquid_lens.dart`
- Modify: `app/test/liquid_lens_test.dart`
- Modify: `app/lib/core/design_tokens.dart`（新增 `lensMagnify`）

**Interfaces:**
- Consumes: `LiquidLensShape.toPath()`、`AppTokens.lensMagnify`。
- Produces: `LiquidLens.magnifyScale` 真正接上（默认 `AppTokens.lensMagnify`）。

- [ ] **Step 1: 写失败的测试**

素材用 Task 5 那个 `_shotLens` 的 `lineAtX` 参数（胶囊底上一条 2px 黑竖线）。几何：画布 200×120、胶囊 120×64 居中，**透镜中心 x = 60**。线画在 **x = 40**（相对中心 −20）；**2× 放大后它会落到 x = 20**，20px 的位移，不会看错。

```dart
/// 在 [x0, x1) 这一段里找最暗的那一列（灰阶取 R 通道，素材是黑白）。
int _darkestColumn(List<int> px, int width, int x0, int x1, int y) {
  int best = x0, bestV = 256;
  for (int x = x0; x < x1; x++) {
    final int v = px[(y * width + x) * 4];
    if (v < bestV) { bestV = v; best = x; }
  }
  return best;
}

testWidgets('放大层：透镜里的线被搬走了（采到的是被放大的胶囊）', (tester) async {
  const int y = 60; // 画布垂直中心
  final plain = await _shotLens(tester, canvas: _canvas, capsule: _capsule,
      lift: 0, accent: const Color(0xFF12B5A5), lineAtX: 40, magnifyScale: 1.0);
  final zoomed = await _shotLens(tester, canvas: _canvas, capsule: _capsule,
      lift: 0, accent: const Color(0xFF12B5A5), lineAtX: 40, magnifyScale: 2.0);

  // 两次都只扫**透镜之内**（x ∈ [0,120)）：不放大时线在 40，放大 2× 时在 20。
  expect(_darkestColumn(plain, 200, 0, 120, y), closeTo(40, 2),
      reason: '不放大时透镜里看不到那条线 —— 透镜读不到同层更早画的胶囊');
  expect(_darkestColumn(zoomed, 200, 0, 120, y), closeTo(20, 3),
      reason: '放大没生效，或者矩阵方向反了（÷2 会把线推到 70 附近）');
});
```

`magnifyScale` 传 2.0 而不是 `AppTokens.lensMagnify`（1.10）是有意的：**1.10 只挪 2px，判别力不够**；这条测的是「矩阵接对了没有」，不是「倍率好不好看」。

**这条必须与 `lens_magnify_probe_test.dart` 并存**：探针证明的是**引擎行为**（backdrop 含同层更早的内容、矩阵方向、放大只读自身范围），这一条证明的是**我们把那个行为接对了**。两条都可能单独失败，失败的含义完全不同。

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: FAIL —— 透镜内外的线位置相同（还没接放大层）。

- [ ] **Step 3: 实现**

把②那一层从 `CustomPaint` 改成：

```dart
ClipPath(
  clipper: _LensClipper(shape),
  child: BackdropFilter(
    filter: magnifyScale <= 1.0 ? ImageFilter.blur(sigmaX: 0, sigmaY: 0)
      : ImageFilter.matrix(
          _zoomAbout(Offset(shape.centerX, centerY), magnifyScale).storage,
          filterQuality: FilterQuality.high),
    child: CustomPaint(painter: _LensBodyPainter(...)),
  ),
)
```

`_zoomAbout` 照抄探针里的那个（`translate(c) · scale(s) · translate(-c)`）。`AppTokens.lensMagnify = 1.10`。

**`centerY` 是 `shape.capsuleH / 2`**（胶囊的竖直中心），**不是 `shape.height / 2`** —— 按住时透镜比胶囊高，`toPath()` 是竖直居中在 `capsuleH / 2` 上的（见 Task 4 的 Interfaces 说明），放大中心必须与它同一处，否则透镜会偏心。

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart test/lens_magnify_probe_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/glass/liquid_lens.dart app/lib/core/design_tokens.dart app/test/liquid_lens_test.dart
git commit -m "feat(glass): 透镜的放大层（ImageFilter.matrix，零 shader）"
```

---

### Task 7: 光谱环 —— 以主色为锚走色相

**Files:**
- Modify: `app/lib/core/glass/liquid_lens.dart`
- Modify: `app/test/liquid_lens_test.dart`
- Modify: `app/lib/core/design_tokens.dart`（环的宽度与配色配方）

**Interfaces:**
- Consumes: `LiquidLensShape.toPath()`、`accent`。
- Produces: `_LensBodyPainter` 多画一层环（`LiquidLens` 的公开签名不变）。

- [ ] **Step 1: 写失败的测试**

**注意别写成「两张图的像素不同」** —— 那个断言没有鉴别力：本体那层 `accentGradient` 本来就是拿主色染的，换主色它自己就会变。要钉的是**色相走没走**：

```dart
/// 透镜范围内，色相离 [from] 最远的那个像素偏了多少度。
/// 只算**饱和度 > 0.25 且不透明**的像素 —— 白色高光芯的色相是不稳的。
double _maxHueDelta(List<int> px, Color from) {
  final double base = HSLColor.fromColor(from).hue;
  double worst = 0;
  for (int i = 0; i < px.length; i += 4) {
    if (px[i + 3] < 128) continue;
    final HSLColor c =
        HSLColor.fromColor(Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]));
    if (c.saturation < 0.25) continue;
    double d = (c.hue - base).abs() % 360;
    if (d > 180) d = 360 - d;
    if (d > worst) worst = d;
  }
  return worst;
}

testWidgets('光谱环走色相：透镜上至少有像素的色相离主色 30° 以上', (tester) async {
  // teal（约 175°）。本体那层染色无论多浓，色相都贴着主色（偏离 ≈ 0）；
  // 只有真走了色相的环才会把它顶到 30° 以上。
  const accent = Color(0xFF12B5A5);
  final px = await _shotLens(tester, canvas: _canvas, capsule: _capsule,
      lift: 1, accent: accent);
  expect(_maxHueDelta(px, accent), greaterThan(30),
      reason: '整枚透镜的色相都贴着主色 —— 那是「给主色加了个亮边」，不是走色相');
});
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: FAIL —— 两张图相同（还没画环；本体的 `accentGradient` 只用了主色的 alpha 通道，色相差异在这一层看不出来）。

- [ ] **Step 3: 实现**

在 `_LensBodyPainter` 的**最后**画两层（顺序不能换）：

1. **彩色环**：`Paint()..style = stroke ..strokeWidth = ringWidth ..shader = SweepGradient(center: 透镜中心, colors: [...], stops: [...]).createShader(shape.toPath().getBounds())`，沿 `shape.toPath()` 描边。色相从 `HSLColor.fromColor(accent).hue` 出发、按 stop 走一遍邻近色；**透明度峰值钉在左上**（`SweepGradient` 的角度从 `Alignment.center` 的正右方起算，左上约 225°）—— 所以 alpha 在那一带最大，往右下渐隐到接近 0。
2. **白色高光芯**：同一条 path 再描一遍，更细，用 `LinearGradient(topLeft → bottomRight)` 从 `Colors.white.withValues(alpha: 0.95)` 渐隐到 `0.15`。**这一层让环读作「被点亮的玻璃边」而不是「贴了一圈彩虹」**。

`AppTokens` 新增（名字不要含 Pad / Gap / Inset / Spacing，免得被 4px 栅格那条规则拦下）。

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart && ../toolchain/flutter/bin/flutter analyze`
Expected: PASS，0 issue。若 `design_tokens_test` 报 `Color(0x…)` 或非法圆角，把那些数值挪进 `AppTokens`。

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/glass/liquid_lens.dart app/lib/core/design_tokens.dart app/test/liquid_lens_test.dart
git commit -m "feat(glass): 透镜的光谱环（以主色为锚 + 白色高光芯）"
```

---

### Task 8: 把它接到底栏上 —— 两棵树分叉

**Files:**
- Modify: `app/lib/features/home/glass_nav_bar.dart`
- Modify: `app/test/glass_tier_test.dart`
- Modify: `app/test/home_shell_nav_test.dart`

**Interfaces:**
- Consumes: `LiquidLens`、`LiquidLensShape`、`LiquidLensSpring`（Task 3-7）。
- Produces: `_GlassNavBarState` 新增

```dart
Widget _buildStandard(BuildContext context);   // 今天那段代码，逐字搬进来
Widget _buildLiquid(BuildContext context);     // 三层树
double get _liftTarget;                        // (_dragging || _heldLongEnough) ? 1 : 0
```

以及两个新的状态位：`double _fingerInnerX`（手指在**已扣 pad 的内层坐标**里的 x）与 `bool _heldLongEnough`（由 `_press` 起的一个 110ms 定时器置位，`_release` / `_cancel` 里取消）。

- [ ] **Step 1: 先写交互契约的测试（它在标准档下此刻就该绿）**

追加到 `app/test/glass_tier_test.dart`。**液态档必须走 prefs 而不是模块级标志** —— 屏幕一 `ref.watch(appSettingsProvider)` 就会建 notifier、`_load()` 读 prefs，把标志覆盖回去（v0.10.1 那轮踩过：工装那两张「液态档」基线图与标准档逐字节相同）。

```dart
/// 按给定的液态档设置 pump 一次主壳。`size` 用来测短屏那一档。
Future<void> _pumpShell(WidgetTester tester,
    {required bool liquid, Size size = const Size(420, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{
    'onboarded': true, 'lastSeenVersion': appVersion, 'liquidGlass': liquid,
  });
  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: HomeShell()),
  ));
  // **不能用 pumpAndSettle**：主壳里有一直调度下一帧的动画，会等到超时。
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 拆树并推一下时钟，让 drift 取消查询流时排的零时长定时器跑掉
/// （同 `home_shell_nav_test.dart` 的 `_disposeShell`）。
Future<void> _disposeShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

testWidgets('交互契约两档一致：按住期间页面不动、松手才提交，两档完全相同',
    (tester) async {
  Future<(List<int> duringHold, int afterRelease)> run(
      {required bool liquid}) async {
    await _pumpShell(tester, liquid: liquid);
    final PageController c =
        tester.widget<PageView>(find.byType(PageView)).controller!;
    final Rect nav = tester.getRect(find.byKey(const Key('glass-nav-bar')));
    // 第 3 格的位置：外 24 + 内 6 + 3.5 × itemW。
    final TestGesture g = await tester.startGesture(
        Offset(nav.left + nav.width * 0.85, nav.center.dy));
    final List<int> during = <int>[];
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 40)); // 共 400ms
      during.add(c.page!.round());
    }
    await g.up();
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    final int after = c.page!.round();
    await _disposeShell(tester);
    return (during, after);
  }

  final (List<int> stdDuring, int stdAfter) = await run(liquid: false);
  final (List<int> liqDuring, int liqAfter) = await run(liquid: true);

  expect(stdDuring, everyElement(0), reason: '按住期间页面就不该动');
  expect(liqDuring, stdDuring, reason: '两档按住期间的页面位置不一样');
  expect(liqAfter, 3, reason: '松手要落在滑块最终所在的那一格');
  expect(liqAfter, stdAfter, reason: '两档的提交终值不一样 —— 液态档换的应该只有视觉');
});
```

这条在 Task 8 动手前就应当**通过**（手势层一行没改）—— 它的作用是钉住「改完也得还是这样」。若它现在不通过，先查是不是测试自己写错了。

- [ ] **Step 2: 跑，确认通过**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/glass_tier_test.dart`
Expected: PASS。

- [ ] **Step 3: 拆两棵树**

`build` 现在开头那七行取上下文的语句（`isDark` / `isShort` / `capsuleH` / `outerPad` / `activeColor` / `inactiveColor` / `fg` / `selectedIndex`）**原样留在 `build` 里**，然后包一层分派：

```dart
return ValueListenableBuilder<bool>(
  valueListenable: liquidGlassActive,
  builder: (BuildContext context, bool liquid, Widget? _) => liquid
      ? _buildLiquid(context, isDark, isShort, capsuleH, outerPad,
          activeColor, inactiveColor, fg, selectedIndex)
      : _buildStandard(context, isDark, isShort, capsuleH, outerPad,
          activeColor, inactiveColor, fg, selectedIndex),
);
```

两个 `_buildXxx` 都按这个具名参数表接收（**别让它们各自再读一次 `Theme` / `AppLayout`** —— 那样两档就可能因为读取时机不同而分叉）。

**`_buildStandard` 就是把今天 `build` 里 `return QScale(...)` 到结尾那一段原封不动搬进去**（连注释一起）。`_buildLiquid` 写三层：

```dart
QScale(pressed: _pressed, scale: AppTokens.pillGrow,
  child: SafeArea(top: false, left: false, right: false,
    child: Padding(padding: EdgeInsets.symmetric(horizontal: outerPad),
      child: SizedBox(height: capsuleH,
        child: Stack(clipBehavior: Clip.none, children: <Widget>[
          // ① 胶囊：GlassRim 包住今天那个 ClipRRect > GlassBlur > Container
          // ② 透镜：Positioned.fill > IgnorePointer > LiquidLens(...)
          // ③ 图标 + 手势：与标准档同一段 Row / GestureDetector，
          //    外面套 Padding(all(_innerPad))
        ])))));
```

**指针位置**：`_press` / `_dragUpdate` 里把 `_fingerInnerX` 记下来（它们拿到的 `d.localPosition.dx` 已经是内层坐标）。透镜中心 = `_innerPad + (跟手权重用升程混过的位置)`。

**升程**：`_liftTarget` 见上；`_heldLongEnough` 用 `Timer(AppTokens.lensHoldDelay, ...)` 置位。弹簧每帧用 `Ticker` 推（`SingleTickerProviderStateMixin`），只在 `!_spring.isAtRest || !_posSpring.isAtRest` 时跑。

**顺手修掉一个既有缺陷**：`onTapCancel: () {}` 现在是**空回调**，于是「在胶囊上按下、然后竖直滑走」会让 `_pressed` **永远卡在 true** —— 标准档下只是胶囊一直大 1.06×，液态档下**透镜会永远提着凸在外面**，一眼就看得出来。改成在 `onTapCancel` 里清 `_pressed`（`onHorizontalDragCancel` 那条 `_cancel` 有 `if (!_dragging) return;` 的早退，**不能直接复用**）。同时取消 `_heldLongEnough` 那个定时器。

- [ ] **Step 4: 写「两棵树真的分叉了」的护栏**

追加到 `app/test/glass_tier_test.dart`（两条分开写，各自拆树，别在一个用例里 pump 两次）：

```dart
testWidgets('标准档的底栏树里没有透镜', (tester) async {
  await _pumpShell(tester, liquid: false);
  expect(find.byType(LiquidLens), findsNothing, reason: '标准档里混进了液态档的元素');
  await _disposeShell(tester);
});

testWidgets('液态档的底栏树里有透镜', (tester) async {
  await _pumpShell(tester, liquid: true);
  expect(find.byType(LiquidLens), findsOneWidget);
  await _disposeShell(tester);
});
```

- [ ] **Step 5: 写那几条手感用例**

追加到同一处。几何一律从 `LiquidLens` 的 `shape` 读 —— **不要去数像素**，这几条要的是几何，不是观感。

```dart
LiquidLens _lens(WidgetTester tester) =>
    tester.widget<LiquidLens>(find.byType(LiquidLens));

/// 第 3 格的位置（外 24 + 内 6 + 3.5 × itemW）。
Offset _lastTab(WidgetTester tester) {
  final Rect nav = tester.getRect(find.byKey(const Key('glass-nav-bar')));
  return Offset(nav.left + nav.width * 0.85, nav.center.dy);
}

testWidgets('点按换页：透镜是滑过去的，不是瞬移过去的', (tester) async {
  await _pumpShell(tester, liquid: true);
  final double startX = _lens(tester).shape.centerX;
  final TestGesture g = await tester.startGesture(_lastTab(tester));
  await tester.pump(const Duration(milliseconds: 30)); // 远短于 lensHoldDelay
  final double midX = _lens(tester).shape.centerX;
  await g.up();
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
  final double endX = _lens(tester).shape.centerX;

  expect(midX, greaterThan(startX + 5), reason: '按下之后透镜没动 —— 那是瞬移');
  expect(midX, lessThan(endX - 5), reason: '按下就到位了 —— 那不叫滑过去');
  await _disposeShell(tester);
});

testWidgets('点按不提起：全程高度不超过胶囊', (tester) async {
  await _pumpShell(tester, liquid: true);
  // 用透镜自己的 `size.height`（= 胶囊高），**不要用 `getRect(导航栏)`** ——
  // 底栏外面套着 `QScale`，按下时整棵被放大 6%，`getRect` 量到的不是胶囊高。
  final double capsuleH = _lens(tester).size.height;
  final TestGesture g = await tester.startGesture(_lastTab(tester));
  for (int i = 0; i < 3; i++) {              // 3 × 30ms = 90ms < lensHoldDelay
    await tester.pump(const Duration(milliseconds: 30));
    expect(_lens(tester).shape.height, lessThanOrEqualTo(capsuleH + 0.5),
        reason: '快速点按不该把透镜提起来 —— 凸出胶囊是「按住」的专属信号');
  }
  await g.up();
  await _disposeShell(tester);
});

testWidgets('按住才提起：超过 lensHoldDelay 之后高度必须超过胶囊', (tester) async {
  await _pumpShell(tester, liquid: true);
  // 用透镜自己的 `size.height`（= 胶囊高），**不要用 `getRect(导航栏)`** ——
  // 底栏外面套着 `QScale`，按下时整棵被放大 6%，`getRect` 量到的不是胶囊高。
  final double capsuleH = _lens(tester).size.height;
  final TestGesture g = await tester.startGesture(_lastTab(tester));
  for (int i = 0; i < 20; i++) {             // 600ms
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(_lens(tester).shape.height, greaterThan(capsuleH + 2),
      reason: '按住 600ms 了还没凸出胶囊');
  await g.up();
  await _disposeShell(tester);
});

testWidgets('短屏：几何按矮胶囊（52）算，凸出仍然成立', (tester) async {
  await _pumpShell(tester, liquid: true, size: const Size(900, 420));
  final double capsuleH = _lens(tester).size.height;
  expect(capsuleH, closeTo(52, 1), reason: '这一档的胶囊该是 52 高');
  final TestGesture g = await tester.startGesture(_lastTab(tester));
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(_lens(tester).shape.height, greaterThan(capsuleH + 2),
      reason: '矮屏下没凸出 —— 几何多半照抄了 64 的结论');
  await g.up();
  await _disposeShell(tester);
});

testWidgets('点按被取消（竖直滑走）：透镜落回，不许卡在提起状态', (tester) async {
  await _pumpShell(tester, liquid: true);
  final double capsuleH = _lens(tester).size.height;
  final Rect nav = tester.getRect(find.byKey(const Key('glass-nav-bar')));
  final TestGesture g = await tester.startGesture(nav.center);
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(_lens(tester).shape.height, greaterThan(capsuleH),
      reason: '这一步该是提起的');

  await g.moveBy(const Offset(0, -80)); // 竖直滑走 → 点按被取消
  await g.up();
  for (int i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(_lens(tester).shape.height, closeTo(capsuleH - 12, 1),
      reason: '_pressed 卡在 true —— 透镜永远提着凸在外面');
  await _disposeShell(tester);
});
```

`nav.height - 12` 是静止时的高度（`capsuleH − 2 × pad`，`pad = AppTokens.gapIconText = 6`）。

- [ ] **Step 6: 跑全部相关测试**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/glass_tier_test.dart test/home_shell_nav_test.dart test/liquid_lens_test.dart test/liquid_scope_guard_test.dart`
Expected: PASS。**Task 1 里那条 `liquid_scope_guard_test` 的失败此时应当转绿**（`home_shell.dart` 不再读 `liquidGlassActive`，改由 `glass_nav_bar.dart` 读，而它在 `features/home/` 下）。

- [ ] **Step 7: 出图 + 出 GIF 自查**

Run: `cd app && ../toolchain/flutter/bin/flutter test tool/visual/render_screens_test.dart && ../toolchain/flutter/bin/flutter test tool/gif/render_gifs_test.dart`

与 `baseline-v0102/` 比：**标准档的图必须逐像素相同**，`36_home_shell_liquid_*` 应当明显不同。

再合成 GIF 看动得对不对：

```bash
python scripts/make_gif.py --prefix drag_liquid_dark_ --out work/gif/nav-drag.gif --width 620 --fps 13 --colors 96
```

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/home app/test
git commit -m "feat(home): 底栏拆成两棵树，液态档接上透镜"
```

---

### Task 9: 边光搬进新模块，删掉旧的两个类

底栏的胶囊在液态档下还要有一圈边光与「光跟随滑块」的窄亮带。把 `glass.dart` 里那套画法搬进新模块，然后删掉旧类 —— `glass.dart` 从此只剩下标准档与档位标志。

**Files:**
- Modify: `app/lib/core/glass/liquid_lens.dart`（新增 `CapsuleRimPainter`）
- Modify: `app/lib/core/glass/glass.dart`（删 `GlassRim` / `_RimPainter`）
- Modify: `app/lib/features/home/glass_nav_bar.dart`

**Interfaces:**
- Consumes: `AppTokens.glassRimProbe` / `glassRimProbeWidth` / `glassRimProbeGlow`（**保留**）。
- Produces: `class CapsuleRimPainter extends CustomPainter`，构造参数：`{required double radius, required bool isDark, required bool compact, double? sliderIndex, int? tabCount, double trackPad = 0}`。

- [ ] **Step 1: 搬移 `_RimPainter`**

把它从 `glass.dart` 复制到 `liquid_lens.dart`，改名为 `CapsuleRimPainter`，**删掉透镜那一段**（`paintCore` 分支、`lensFill`、`lensProtrude`、`sliderScale`、`lensRRect` 以及「透镜的边缘光」那两次 `drawRRect`）—— 那些现在由 `LiquidLens` 负责。留下的只有：胶囊那一圈方向性描边 + 「光跟随滑块」的窄亮带。

- [ ] **Step 2: 换掉底栏的用法**

`_buildLiquid` 的 ① 那一层从 `GlassRim(radius: …, isDark: …, compact: true, child: …)` 改成：

```dart
Stack(clipBehavior: Clip.none, children: <Widget>[
  ClipRRect(borderRadius: BorderRadius.circular(capsuleH / 2),
    child: GlassBlur(sigma: AppTokens.blurPanel, child: Container(/* 胶囊填充 + 描边 */))),
  Positioned.fill(child: IgnorePointer(child: CustomPaint(
    painter: CapsuleRimPainter(radius: capsuleH / 2, isDark: isDark, compact: true,
      sliderIndex: page + 0.5, tabCount: items.length, trackPad: _innerPad)))),
])
```

- [ ] **Step 3: 删掉旧类并确认无引用**

Run: `cd app && grep -rn "GlassRim\|GlassLensGlow\|_RimPainter\|_LensGlowPainter" lib/`
Expected: 无输出。

- [ ] **Step 4: 跑全套 + analyze**

Run: `cd app && ../toolchain/flutter/bin/flutter test && ../toolchain/flutter/bin/flutter analyze`
Expected: 全绿（当前 555 条 + 本计划新增的），0 issue。

- [ ] **Step 5: 出图比对**

Run: `cd app && ../toolchain/flutter/bin/flutter test tool/visual/render_screens_test.dart`

与 `baseline-v0102/` 比：**标准档逐像素相同**。`36_home_shell_liquid_*` 应当与 Task 8 那版几乎一致（边光的画法没变，只是换了个类名和文件）。

- [ ] **Step 6: Commit**

```bash
git add app/lib
git commit -m "refactor(glass): 边光搬进 liquid_lens，glass.dart 只剩标准档"
```

---

### Task 10: 屏单、动图、真机、文案、发版

**Files:**
- Modify: `app/tool/visual/visual_screens.dart`
- Modify: `app/tool/gif/render_gifs_test.dart`
- Modify: `app/lib/core/l10n.dart`
- Modify: `app/pubspec.yaml`、`app/lib/core/app_info.dart`、`app/lib/features/profile/app_dialogs.dart`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: 前九个任务的全部产物。
- Produces: 无（收尾）。

- [ ] **Step 1: 工装补一屏「按住拖到一半」**

`visual_screens.dart` 的屏单加一条 `40_nav_lens_dragging`（`HomeShell`，液态档），在 `render_screens_test.dart` 里用 `beforeCapture` 起手拖动并**停在中途不松手**，然后取像。静止帧拍不到凸出与形变，这一屏专门补那个。

- [ ] **Step 2: 动图补一条「点按换页」**

`tool/gif/render_gifs_test.dart` 在现有的「底栏拖动」之外再加一条：从第 0 格快速点按第 3 格，出 24 帧左右。两条并排 —— 拖动是「提起 + 形变」，点按是「不提起、滑过去」，正好是一对反例。

- [ ] **Step 3: 合成 GIF 交给用户**

```bash
python scripts/make_gif.py --prefix nav_tap_liquid_dark_ --out work/gif/nav-tap.gif --width 620 --fps 13 --colors 96
python scripts/make_gif.py --prefix drag_liquid_dark_ --out work/gif/nav-drag.gif --width 620 --fps 13 --colors 96
```

两条都用 `SendUserFile` 发给用户 —— **动图是这一版的第一交付物**。

- [ ] **Step 4: 真机验放大层与性能**

装到用户那台小米上（`adb devices` 先确认连着），验三件：

1. **放大层在 Impeller 下真的生效**（探针只在 `flutter test` 里验过）—— 看透镜里胶囊那条描边有没有被弯掉；
2. 动画期间 `flutter run --profile` 看帧时间有没有掉出预算；
3. 五种主色各切一遍，**量导航选中项白字的对比度**（`AGENTS.md` 那条「只有 primary/sky 过 AA」是同源问题）。不达标的按 `AppTokens.onSolid` 的路子处理，或者把光谱环的明度压下去 —— **不许放着不管**。

若放大层在真机上不稳，**单独摘掉它**（`magnifyScale` 传 1.0 即可），几何与光谱环不受影响。

- [ ] **Step 5: 改文案**

`l10n.dart` 的 `liquidGlassHint` 现在写的是「玻璃边缘带光、按下时鼓起成透镜；关掉更省电」—— 「玻璃边缘带光」其他几处已经没有了。改成描述**底栏**的实际效果，中英两份都改；`clearAll` 确认框与使用帮助里点到这个名字的地方一并核。

- [ ] **Step 6: 版本与更新日志**

`app/pubspec.yaml` → `version: 0.10.3+127`；`app/lib/core/app_info.dart` → `appVersion = '0.10.3'`；`app_dialogs.dart` 的 `_changelogZh` / `_changelogEn` prepend 一条 0.10.3（测试版条目原样写自己改了什么，**不许出现 markdown 标记**），窗口保持 10 条。

- [ ] **Step 7: 跑全套 + 出最终图**

Run: `cd app && ../toolchain/flutter/bin/flutter analyze && ../toolchain/flutter/bin/flutter test && ../toolchain/flutter/bin/flutter test tool/visual/`
Expected: analyze 0 issue；两套测试全绿。

- [ ] **Step 8: `AGENTS.md`**

改三处：「目录架构地图」里 `core/glass/glass.dart` 那一行的描述（`GlassRim` 已删、液态档移到 `features/home/`）；「共享玻璃组件」一节里带液态描述的条目；「最近改动」补 v0.10.3 条目（含这一版的三条决策、两棵树的结构、探针结论、以及「凸出胶囊 = 提起的专属信号」这条契约）。

- [ ] **Step 9: 构建 + 发布**

```bash
cd app && ../toolchain/flutter/bin/flutter build apk --release --target-platform android-arm64
```

用 `aapt2 dump badging` 校验 `versionName='0.10.3'` / `versionCode='127'`，复制到 `dist/倒班助手Pro-v0.10.3.apk`，发布说明写到 `tools/gh/release-notes-v0.10.3.md`，然后

```bash
pwsh scripts/release.ps1 -SkipConfirm
```

发完 **curl 一次 `main` 上的 `latest.json` 核对**（脚本打印的「发布成功」只覆盖 Release 上传那一步）。

- [ ] **Step 10: Commit**

```bash
git add -A && git commit -m "chore(release): v0.10.3（底栏液态玻璃重做）"
git tag v0.10.3 && git push origin beta && git push origin v0.10.3
```

---

## Self-Review

**Spec coverage：** §5.0 交互契约 → Task 8 Step 1/5；§5.1 两棵树 → Task 8 Step 3/4；§5.2 三层树 → Task 8 Step 3；§5.3 几何与弹簧 → Task 3/4；§5.4 光（放大 + 光谱环 + 阴影）→ Task 5/6/7；§5.5 摘掉其他几处 → Task 1；§6 分阶段 → Task 1（阶段 1）/ 2-7（阶段 2、3）/ 8（阶段 3 收口）/ 10（阶段 4）；§7 测试与工装 → 每个任务的测试步骤 + Task 10 Step 1/2；§9 风险 1（真机 Impeller）→ Task 10 Step 4；风险 8（量纲）→ Task 8 Step 3 的「指针位置」；§11 收尾 → Task 10。**无遗漏。**

**Type consistency：** `LiquidLensShape.of(...)` 的具名参数在 Task 4 定义、Task 5/6/7 使用；`LiquidLens` 的六个具名参数在 Task 5 定义、Task 6 接上 `magnifyScale`、Task 8 装配；`CapsuleRimPainter` 在 Task 9 定义并使用。`AppTokens` 新增的名字每个只在一处定义。

**Review Focus 落点：** ①窄窗（端头圆重叠）→ Task 4 Step 1 的第五条用例；②点按被取消后 `_pressed` 卡住 → Task 8 Step 3（修 `onTapCancel`）+ Step 5 的最后一条用例；③短屏几何 → Task 8 Step 5 的「短屏」用例，外加 Task 10 Step 1 的屏单在 200×400 下出图；④连点改道 → Task 3 的「不发散」用例；⑤换主色的色相与对比度 → Task 7 Step 1 的色相用例，外加 Task 10 Step 4 的真机对比度实测。

**两处实现细节没写进步骤、但实现者一定要处理**：`glass_tier_test.dart` 加了 `_pumpShell` 之后要补 `drift/native`、`sqlite3`、`shared_preferences`、`app_info`、`home_shell`、`data/app_repository` 几个 import（照 `home_shell_nav_test.dart` 顶上那段抄）；`render_screens_test.dart` 里那屏「按住拖到一半」的 `beforeCapture` 要起手拖动后**不松手**就取像（松手就拍不到凸出）。
