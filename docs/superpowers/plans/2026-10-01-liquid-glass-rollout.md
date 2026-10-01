# 液态玻璃推广（分段器 + 开关）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把底栏那档液态玻璃抽成共享件（控制器 + 那棵树 + 几何参数），再铺到 `GlassSegment` 与 `GlassSwitch` 上。

**Architecture:** 先抽出三层 —— `LiquidLensMetrics`（几何参数）、`LiquidLensController`（动画状态机）、`LiquidTrack`（「胶囊 + 边光 + 透镜 + 内容」那棵树）—— 让**底栏先改成调用点并验证逐像素不变**；再让分段器与开关各接上去，各带自己的两棵树（关掉液态档时与现在逐像素相同）。

**Tech Stack:** Flutter 3.47 / Dart 3.13，Impeller；`CustomPainter` + 阻尼谐振子，无第三方依赖。

**Spec:** `docs/superpowers/specs/2026-10-01-liquid-glass-rollout-design.md`

## Global Constraints

- **只做底栏 / `GlassSegment` / `GlassSwitch` 三处**；静态玻璃面、按钮、芯片、选择器、弹层一律不碰。
- **静止时一个彩色像素都不画**（`motion` 那道路门），全 app 不变。
- **彩边只跟「有没有在动」走**，不引入「按住就带彩」。
- **底栏渲染逐像素不变**：`00_home_shell_*`（5 张）与 `36_home_shell_liquid_*`（5 张）与基线相同。
- **两个新控件关掉液态档时逐像素不变**（与底栏 v0.10.3 同一条验收）。
- 档位判据 `liquidGlassActive` 只许出现在：`lib/core/glass/glass.dart`、`lib/features/home/`、`lib/core/widgets/glass_segment.dart`、`lib/core/widgets/glass_switch.dart`。**新抽的两个件不在名单里**（它们不读档位）。`test/liquid_scope_guard_test.dart` 的第一条与「自证」第二条都要照跑。
- 验收标准：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿（当前 **617**，只增不减）；`flutter test tool/visual/` 全绿（当前 **312**）。
- 版本号：`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 同步（由 `app/test/app_info_test.dart` 把关）；更新日志在 `app/lib/features/profile/app_dialogs.dart`，窗口固定 10 条、纯文本、不许出现 markdown 标记。
- 出图存基线用 `python scripts/diff_visual.py <基线目录> app/build/visual`；动图用 `python scripts/make_gif.py`，**凡是有弹簧的动图出帧必须 16ms、合成用 `--fps 60`**。
- **不要跑 `dart format`**（工具链是新版 tall style，会把整个文件重排）。

## Review Focus

（规格没写、但一个正常用这款 App 的人会碰到、且最容易出事的地方，最可能的排前面。）

1. **矮屏底栏**（横屏 900×420 / 小窗 200×400，胶囊 52 高）—— 几何参数化时若让它跟着 `capsuleH` 走，这两档的凸出量会从 10 变成 8.1，**画面会变**。
2. **开关在七个界面里「开」的样子** —— 从实心主色改成玻璃 + 淡染，读感会弱一档；`enabled: false` 的置灰态也得跟着好看。
3. **白色钮上的白芯** —— 白本体的透镜上，`lensRingCoreWidth` 那条白线会消失，轮廓可能整个垮掉。
4. **分段器在窄窗**（200×400）—— 胶囊高 38 而可用宽很窄，会落进 `toPath()` 的退化分支（「宽 <= 高」）。
5. **拖动中的速度与手感** —— 抽控制器时若把某个量喂错（例如 `stretch` 用了弹簧值、`motion` 用了瞬时速度），手感会静默地变差，而单元测试未必照得出来。

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `app/lib/core/glass/liquid_lens_metrics.dart` | **新建**。几何参数（`protrude` / `liftWidth`）与按胶囊高度的默认值。 |
| `app/lib/core/glass/liquid_lens_controller.dart` | **新建**。动画状态机：四条弹簧、速度低通、ticker 起停、手势。不含 widget。 |
| `app/lib/core/widgets/liquid_track.dart` | **新建**。「胶囊 + 边光 + 透镜 + 内容」那棵树，参数化。 |
| `app/lib/core/glass/liquid_lens.dart` | 改：`LiquidLensShape.of` 收 `metrics`；`LiquidLens` 收 `fill`。 |
| `app/lib/features/home/glass_nav_bar.dart` | 改：状态机与那棵树都改用共享件。 |
| `app/lib/core/widgets/glass_segment.dart` | 改：加液态树。 |
| `app/lib/core/widgets/glass_switch.dart` | 改：加液态树（含轨道玻璃化）。 |
| `app/test/liquid_scope_guard_test.dart` | 改：允许位置 2 处 → 4 处。 |

---

## Task 1: 几何参数化 —— `LiquidLensMetrics`

**Files:**
- Create: `app/lib/core/glass/liquid_lens_metrics.dart`
- Modify: `app/lib/core/glass/liquid_lens.dart`（`LiquidLensShape.of` 的签名与 `width` / `height` 两行）
- Modify: `app/lib/core/design_tokens.dart`（加 `lensLiftRatio`）
- Test: `app/test/liquid_lens_test.dart`

**Interfaces:**
- Produces:
  - `class LiquidLensMetrics { const LiquidLensMetrics({required double protrude, required double liftWidth}); final double protrude; final double liftWidth; }`
  - `factory LiquidLensMetrics.forCapsule(double capsuleH)`
  - `LiquidLensShape.of({..., LiquidLensMetrics? metrics})` —— **不给时用常量 `AppTokens.navLensProtrude` / `AppTokens.lensLiftWidth`（10 / 10）**。

- [ ] **Step 1: 先存基线（本任务唯一的「改之前」基准）**

```bash
flutter test tool/visual/render_screens_test.dart
rm -rf build/visual/baseline-v0108 && mkdir -p build/visual/baseline-v0108
cp build/visual/*.png build/visual/baseline-v0108/
```

后面每一个「逐像素不变」的验收都跟这份比。

- [ ] **Step 2: 写失败用例**

在 `app/test/liquid_lens_test.dart` 的「透镜几何」组里加三条：

```dart
test('几何默认值 = 底栏那档（10 / 10）—— 既有调用点的渲染一个字都不许变', () {
  // 这一条是 Task 5「逐像素不变」的地基：不给 metrics 时行为必须与抽之前完全一样。
  final s = LiquidLensShape.of(
      itemW: 90, capsuleH: 52, pad: 6, centerPage: 0, lift: 1, velocity: 0);
  // 矮屏那一档胶囊 52 高，**现在也是 10 / 10** —— 不能跟着高度缩。
  expect(s.height, closeTo(52 - 12 + 2 * AppTokens.navLensProtrude, 0.001));
  expect(s.width, closeTo(90 + AppTokens.lensLiftWidth, 0.001));
});

test('metrics 真的进几何：protrude 只管纵向、liftWidth 只管横向', () {
  final s = LiquidLensShape.of(
      itemW: 90, capsuleH: 28, pad: 3, centerPage: 0, lift: 1, velocity: 0,
      metrics: const LiquidLensMetrics(protrude: 8, liftWidth: 0));
  expect(s.height, closeTo(22 + 16, 0.001));   // 基准 28−6 + 2×8
  expect(s.width, closeTo(20, 0.001));         // itemW = (46−6)/2，横向不外扩
});

test('forCapsule 按高度取，且底栏那一档与常量一致', () {
  expect(LiquidLensMetrics.forCapsule(64).protrude, closeTo(10, 0.001));
  expect(LiquidLensMetrics.forCapsule(40).protrude, closeTo(6.25, 0.001));
});
```

- [ ] **Step 3: 跑，确认红**

Run: `flutter test test/liquid_lens_test.dart`
Expected: 编译失败（`LiquidLensMetrics` 未定义）。

- [ ] **Step 4: 实现**

`app/lib/core/design_tokens.dart` 加：

```dart
/// 透镜外扩 / 凸出相对胶囊高度的比例（10 / 64）。只有 [LiquidLensMetrics.forCapsule]
/// 用它 —— 底栏那两个数**是冻住的**（矮屏胶囊 52 高时现在也是 10/10，跟着缩会改到矮屏渲染）。
static const double lensLiftRatio = 0.15625;
```

`app/lib/core/glass/liquid_lens_metrics.dart`：

```dart
class LiquidLensMetrics { ... }   // 两个 final double + const 构造
// forCapsule: protrude = liftWidth = capsuleH * AppTokens.lensLiftRatio
```

`LiquidLensShape.of` 里把 `width` / `height` 两行改成读 `m`（`metrics ?? const LiquidLensMetrics(protrude: AppTokens.navLensProtrude, liftWidth: AppTokens.lensLiftWidth)`），其余一行不动。

- [ ] **Step 5: 跑，确认绿**

Run: `flutter test test/liquid_lens_test.dart`
Expected: PASS（含既有 40 条）。

- [ ] **Step 6: 全套 + 出图比对（这一步的行为必须是零变化）**

```bash
flutter test
python ../scripts/diff_visual.py build/visual/baseline-v0108 build/visual
```
Expected: 617 全绿；出图 **232 张全部逐像素相同**。

- [ ] **Step 7: 提交**

```bash
git add app/lib/core/glass/liquid_lens_metrics.dart app/lib/core/glass/liquid_lens.dart app/lib/core/design_tokens.dart app/test/liquid_lens_test.dart
git commit -m "refactor(glass): 透镜几何收 LiquidLensMetrics，默认值保持现状"
```

---

## Task 2: `LiquidLensController` —— 把状态机从底栏抽出来

**Files:**
- Create: `app/lib/core/glass/liquid_lens_controller.dart`
- Test: `app/test/liquid_lens_controller_test.dart`

**Interfaces:**
- Produces: `class LiquidLensController extends ChangeNotifier`
  - `LiquidLensController({required int slots})`
  - 只读：`double lift` / `position`（中心，单位「格」）/ `stretch` / `motion` / `velocity` / `bool pressed` / `bool dragging` / `int? previewIndex` / `bool get needsTicks`
  - `void tick(Duration dt, double itemW)`
  - `void press(double localDx, double itemW)` / `dragStart(double localDx, double itemW)` / `dragUpdate(double localDx, double itemW)` / `release()` / `cancel()` / `tapCancel()`
  - `void jumpTo(double slotCenter)` —— 外部程序化切页时把目标挪过去并拉活 ticker
  - `void setBounds(double maxLensHalfWidthPx, double trackWidthPx, double padPx)` —— 夹紧透镜不出轨道两端

**这一版的四个量必须分开**（规格 §3.2，抄错任何一个都会静默地改掉手感）：

| 量 | 来源 |
|---|---|
| `stretch` | **形变弹簧**，目标 = `\|velocity\| / lensVelocityRef` |
| `motion` | **亮度弹簧**（亮起 / 熄灭两条：`lensLitOmega` / `lensUnlitOmega`），目标 = `\|velocity\| / lensRingFullSpeed` |
| `lift` | **升程弹簧**（提起 / 落下两条：`lensLiftOmega` / `lensDropOmega`），目标 = `pressed \|\| dragging` |
| `velocity` | `lensVelocityStep(deltaPage: …, itemW: …, dt: …)` —— **帧率无关**，分母上不许有地板 |

- [ ] **Step 1: 写失败用例**

`app/test/liquid_lens_controller_test.dart`，四条（全部按 16ms 一帧喂，`lensMaxStep` 会把更大的步长封顶）：

```dart
test('点按：不提起，位置滑到目标格', ...);        // press → release，lift 始终 < 0.05
test('长按 + 拖动：提起、跟手、位置不落后', ...);   // press → 等 lensHoldDelay → dragUpdate
test('帧率无关：同一段位移在 8.33ms 与 16.67ms 下速度一致', ...);  // 复用 Task 1 之外已有的 lensVelocityStep 用例思路
test('松手后落回：亮度渐出（160ms 时仍 > 0.4，480ms 时 < 0.1）', ...);
```

- [ ] **Step 2: 跑，确认红** → `flutter test test/liquid_lens_controller_test.dart`，Expected: 编译失败。

- [ ] **Step 3: 实现**

把 `_GlassNavBarState` 里现在这几块**原样搬过来**（不要顺手改数值）：`_syncTicker` / `_onTick` 的整段积分 / `_clampLensCenter` / `_armHoldTimer` / `_endHold` / `_press` / `_dragStart` / `_dragUpdate` / `_release` / `_cancel` / `_onTapCancel` / `_lensTick`。`items.length` 换成 `slots`；`_visualPage` 变成 `position - 0.5` 的派生。

- [ ] **Step 4: 跑，确认绿**

- [ ] **Step 5: 提交**（`git add` 那两个文件，`git commit -m "refactor(glass): 把手势与弹簧状态机抽成 LiquidLensController"`）

---

## Task 3: `LiquidLens` 收 `fill`（本体填充参数化）

**Files:**
- Modify: `app/lib/core/glass/liquid_lens.dart`
- Test: `app/test/liquid_lens_test.dart`

**Interfaces:**
- Produces: `LiquidLens({..., List<Color>? fill})` —— 不给时仍用 `AppTokens.accentGradient(accent).colors`（**默认值保持现状**）。
- 同时给 `_LensBodyPainter` 加 `bool showRingCore`（默认 `true`）—— 白本体的那一档要能关掉白芯。

- [ ] **Step 1: 写失败用例**：`LiquidLens(fill: [白, 白])` 渲出来的本体像素与默认不同；`showRingCore: false` 时静止帧比默认**暗一档**（同点位比）。**反向验证**：两条都要能在把参数去掉时变红。

- [ ] **Step 2: 跑，确认红**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 跑，确认绿** + 全套
- [ ] **Step 5: 提交**

---

## Task 4: `LiquidTrack`

**Files:**
- Create: `app/lib/core/widgets/liquid_track.dart`
- Test: `app/test/liquid_track_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `LiquidLensMetrics`、Task 2 的 `LiquidLensController`、Task 3 的 `LiquidLens(fill:)`。
- Produces:

```dart
class LiquidTrack extends StatefulWidget {
  const LiquidTrack({
    super.key,
    required this.slots,
    required this.capsuleH,
    required this.pad,
    required this.controller,
    required this.contentBuilder,   // Widget Function(BuildContext)
    this.metrics,
    this.fill,                      // 不给 = 主色渐变
    this.showRingCore = true,
    this.showGlowBand = true,       // 底栏 true；开关 false
    this.showRefractedEdge = true,  // 底栏 / 分段器 true；开关 false
  });
}
```

树与 `_buildLiquid` 现在**逐层同序**：① 胶囊（`ClipRRect` + `GlassBlur` + `navFill` / `navBorder`）→ ①b `CapsuleRimPainter` → ② `LiquidLens` → ③ 内容。**顺序不许调** —— 底栏的逐像素验收靠它。

- [ ] **Step 1: 写失败用例**（`app/test/liquid_track_test.dart`）：造一个 3 格、40 高的 `LiquidTrack`，断言 —— 静止时渲染出的像素与「只有胶囊、没有透镜」不同（透镜真的画了）；`showGlowBand: false` 时 `CapsuleRimPainter` 的 `sliderIndex` 为 null；窄窗（宽 200）下不抛异常。
- [ ] **Step 2: 跑，确认红**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 跑，确认绿**
- [ ] **Step 5: 提交**

---

## Task 5: 底栏改用共享件 —— **验收：逐像素不变**

**Files:**
- Modify: `app/lib/features/home/glass_nav_bar.dart`

- [ ] **Step 1: 先存基线**

```bash
flutter test tool/visual/render_screens_test.dart
rm -rf build/visual/baseline-rollout && mkdir -p build/visual/baseline-rollout
cp build/visual/*.png build/visual/baseline-rollout/
```

- [ ] **Step 2: 改 `_buildLiquid` 与 `_GlassNavBarState`**

- `_buildLiquid` 整段换成 `LiquidTrack(slots: items.length, capsuleH: capsuleH, pad: _innerPad, controller: _lens, metrics: const LiquidLensMetrics(protrude: 10, liftWidth: 10), contentBuilder: …)`；内容层里保留 `_iconsRow(..., lensItemW: itemW, lensPad: _innerPad)`（图标扭曲是本页特有的，不进共享件）。
- `_GlassNavBarState` 删掉四条弹簧与 `_onTick` / `_syncTicker` / `_lensTick`，改持一个 `LiquidLensController`；`build` 里的 `ValueListenableBuilder<bool>(liquidGlassActive)` 与「标准档那棵树」**一个字都不动**。
- **`metrics` 必须写死 10 / 10**（不要写 `forCapsule(capsuleH)`）—— 矮屏 52 高那一档现在也是 10/10。

- [ ] **Step 3: 出图逐像素比**

```bash
flutter test tool/visual/render_screens_test.dart
python ../scripts/diff_visual.py build/visual/baseline-rollout build/visual
```
Expected: **232 张全部 0 差异**。

> ⚠️ **有任何一张不同就停在这里解决，不要往下走。** 那是「共享件与原实现不等价」的信号，带着它往下会把问题扩散到另外两个面。允许的唯一例外是响铃页那 5 张的**时钟跳字**（差异框固定在 `(547,494)-(634,623)` 一小块）—— 那是已知假象。

- [ ] **Step 4: 交互契约照跑**

Run: `flutter test test/glass_tier_test.dart test/liquid_lens_controller_test.dart test/liquid_lens_test.dart`
Expected: 全绿（`glass_tier_test` 里「两档交互契约一致」「点按滑动」「长按吸附」「程序化切页」那几条尤其要看）。

- [ ] **Step 5: 全套 + 提交**

```bash
flutter analyze && flutter test
git add app/lib/features/home/glass_nav_bar.dart
git commit -m "refactor(home): 底栏改用 LiquidTrack + LiquidLensController，逐像素不变"
```

---

## Task 6: `GlassSegment` 接上液态档

**Files:**
- Modify: `app/lib/core/widgets/glass_segment.dart`
- Modify: `app/test/liquid_scope_guard_test.dart`（允许位置 2 → 3）
- Test: `app/test/glass_segment_liquid_test.dart`（新建）
- Modify: `app/tool/visual/render_screens_test.dart`（屏单补两屏）

**Interfaces:**
- Consumes: `LiquidTrack` / `LiquidLensController` / `LiquidLensMetrics.forCapsule`。

- [ ] **Step 1: 先存基线**（同 Task 5 Step 1，存成 `baseline-segment`）
- [ ] **Step 2: 写失败用例**

```dart
testWidgets('分段器：液态档与标准档是两棵树', ...);   // 开着与关着光栅化像素必须不同
testWidgets('分段器：关掉液态档时与改之前逐像素相同', ...);  // 用 Step 1 的基线比
testWidgets('分段器：胶囊左右两条边的像素同值（边光是竖直的）', ...);  // 抄 glass_tier_test 那条
testWidgets('分段器：窄窗 200×400 下透镜不消失', ...);   // 断言 toPath 面积 > 0
```

- [ ] **Step 3: 跑，确认红**
- [ ] **Step 4: 实现**：`build` 里按 `liquidGlassActive` 分两棵树；液态那棵用 `LiquidTrack(slots: count, capsuleH: height, pad: AppTokens.padChipV, metrics: LiquidLensMetrics.forCapsule(height), contentBuilder: …)`。**标准档那棵一字不改**（原地抽成 `_buildStandard`）。
- [ ] **Step 5: 跑，确认绿 + 守门**

Run: `flutter test`。Expected: 全绿（守门那条会因为 `glass_segment.dart` 读了档位而红 —— 这时才改名单）。
然后改 `liquid_scope_guard_test.dart` 的 `_allowed` 加 `'lib/core/widgets/glass_segment.dart'`。

- [ ] **Step 6: 出图**：`01_calendar*` / `03_management*` / `05_todos*` / `06_alarm*` 等与基线比；屏单补 `42_segment_liquid`（含小窗那一档）。
- [ ] **Step 7: 提交**

---

## Task 7: `GlassSwitch` 接上液态档（含轨道玻璃化）

**Files:**
- Modify: `app/lib/core/widgets/glass_switch.dart`
- Modify: `app/test/liquid_scope_guard_test.dart`（允许位置 3 → 4）
- Test: `app/test/glass_switch_liquid_test.dart`（新建）
- Modify: `app/tool/visual/render_screens_test.dart`（屏单补两屏）

**Interfaces:**
- Consumes: 同 Task 6。

- [ ] **Step 1: 先存基线**
- [ ] **Step 2: 写失败用例**

```dart
testWidgets('开关：按住时钮的轮廓高度 > 轨道高度，且宽度不变', ...);  // 钉住「只往纵向长」
testWidgets('开关：静止时钮的轮廓宽 ≈ 高（还是圆的）', ...);
testWidgets('开关：关掉液态档时与改之前逐像素相同', ...);
testWidgets('开关：置灰态不跟着液态档回退', ...);   // 既有护栏在 glass_switch_test.dart，照跑
```

- [ ] **Step 3: 跑，确认红**
- [ ] **Step 4: 实现**

- 分两棵树（`_buildStandard` 原地抽出，一字不改）。
- 液态那棵：轨道改成 `GlassBlur` + `navFill` / `navBorder`（圆角 `height/2`），**开的时候叠一层 `accent @ 0.35` 的淡染**；钮用 `LiquidTrack(slots: 2, capsuleH: height, pad: padChipV, metrics: const LiquidLensMetrics(protrude: 8, liftWidth: 0), fill: <白色玻璃那组>， showGlowBand: false, showRefractedEdge: false, showRingCore: ?)`。
- **`showRingCore` 与 `fill` 的最终取值由出图定**（规格 §5.3 留了出口）：白芯在白本体上会消失，先试「收掉白芯 + 给一条极淡的暗边」，不行再换。
- 触觉（`Haptics.select()`）、`enabled` 语义、`AnimatedAlign` 的 `easeOutBack` **一个字都不改**。

- [ ] **Step 5: 跑，确认绿 + 守门**（改名单）
- [ ] **Step 6: 出图**：**七个用到开关的界面逐个核「开」的样子**（闹钟 / 排班编辑器 / 我的 / 重复待办面板 / 待办 / …）。屏单补 `43_switch_liquid`（开 / 关 / 按住 三态，含置灰那一档）。
- [ ] **Step 7: 提交**

---

## Task 8: 收口

**Files:**
- Modify: `app/lib/features/profile/app_dialogs.dart`（更新日志）
- Modify: `app/pubspec.yaml` + `app/lib/core/app_info.dart`（版本号，`Z` +1）
- Modify: `AGENTS.md`
- Create: `tools/gh/release-notes-vX.Y.Z.md`

- [ ] **Step 1: 动图**：`tool/gif/render_gifs_test.dart` 补两条素材（分段器拖动 / 开关按住拉长），**出帧 16ms、`--fps 60`**，发给用户看。
- [ ] **Step 2: 更新日志**：prepend 一条、删最旧一条（窗口 10 条）、中英同步；**纯文本，不许 markdown 标记**。
- [ ] **Step 3: 版本号**：`pubspec.yaml` 与 `app_info.dart` 同步；`flutter test test/app_info_test.dart test/changelog_window_test.dart` 绿。
- [ ] **Step 4: AGENTS.md**：版本史那一行 + 「最近改动」加一条（含：这是抽共享件而不是复制、`metrics` 默认值为什么冻在 10/10、开关的「开」变弱是拍板代价、动图出帧那条规矩）。
- [ ] **Step 5: 全套验收**

```bash
flutter analyze
flutter test
flutter test tool/visual/
python ../scripts/diff_visual.py build/visual/baseline-rollout build/visual
```
Expected: 0 issue；全绿；**底栏两组十张 0 差异**。

- [ ] **Step 6: 发布**（测试版走 `beta` 分支）：`git push origin beta` → `git tag vX.Y.Z` → `git push origin vX.Y.Z` → 先 `flutter build apk --release --target-platform android-arm64` 并把 APK 复制进 `dist/`，**再**跑 `scripts/release.ps1 -SkipConfirm`（它不会替你构建，只会复制现成的 APK）。

---

## 自检记录

- **规格覆盖**：§2 五条拍板 → Task 5/6/7；§3.2 三个量分家 → Task 2 的接口表；§3.3 手感一处实现 → Task 2；§4.1 底栏不变 → Task 5；§4.2 分段器 → Task 6；§4.3 开关 → Task 7；§5.1–5.4 结构 → Task 1–4；§6 守门与工装 → Task 5/6/7/8；§7 风险 → Review Focus + Task 5 的停线规则；§8 不做 → Global Constraints 第一条。
- **Review Focus 五条各自落在哪**：① 矮屏 → Task 1 Step 1 第一条 + Task 5 Step 2 的「必须写死 10/10」；② 开关七个界面 → Task 7 Step 6；③ 白钮白芯 → Task 3 的 `showRingCore` + Task 7 Step 4；④ 分段器窄窗 → Task 6 Step 2 第四条；⑤ 手感喂错量 → Task 2 的接口表 + Step 1 的四条。
