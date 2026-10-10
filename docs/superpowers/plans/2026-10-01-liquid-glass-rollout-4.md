# 液态玻璃第四轮（开关轨道色 / 弹窗凝聚 / 响铃页药丸）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「开关的轨道色跟着拖动走」补上护栏、把二十来个实心面板的入场换成**凝聚 / 消散**并收敛到一个统一入口、把响铃页那枚上滑关闭改成真的玻璃药丸；顺带修掉液态透镜**竖直档**里两处让「折边永不亮」的地基缺陷。

**Architecture:** 三件事各自独立、共享同一批液态透镜原语：
① 开关轨道色（**已实施**，本计划只补护栏）；
② 弹窗 —— 新增 `showGlassDialog` / `showGlassSheet` 两个入口 + 一个自带两条时长的 `PopupRoute`，把 19 处 `showDialog<` 与 9 处 `showModalBottomSheet` 全迁过去，凝聚由 `GlassMaterialize` 一层负责；
③ 响铃页 —— 药丸是 `LiquidLens` + `LiquidLensShape`（**整体转 90°**），与底栏那枚同一族，两条档位两棵树。
竖直档那两处缺陷在 `liquid_lens.dart` 里，是共享件，**底栏与分段器必须逐像素不变**（有专门的验收任务）。

**Tech Stack:** Flutter 3.47 / Dart 3.13、Impeller、无第三方依赖；工装 `app/tool/visual/`（出图）与 `app/tool/gif/`（动图）。

**Spec:** `docs/superpowers/specs/2026-10-01-liquid-glass-rollout-4-design.md`

## Global Constraints

以下每一条对**每个任务**都成立，不再逐条重复：

- **版本**：`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须同步
  （`test/app_info_test.dart` 盯着）。本轮 `0.10.12+136` → **`0.10.13+137`**。
- **更新日志**：`app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh` / `_changelogEn`
  **prepend 新版本、删最旧一条、保持 10 条**；**纯文本**，不许出现 markdown 标记
  （`test/changelog_window_test.dart` 盯着）。
- **判据只许出现在名单里**：`liquidGlassActive` 的位置由
  `test/liquid_scope_guard_test.dart` 扫源码守着，本轮名单 **5 处 → 6 处**（多出响铃页）。
- **设计令牌**：界面层不许写 `Duration(milliseconds: …)` / `fontSize:` / `circular(<数字>)` 字面量
  （`test/design_tokens_test.dart` 扫 `lib/`）。**新时长必须进 `AppTokens`。**
- **触觉**：除 `core/haptics.dart` 外不许出现 `HapticFeedback.`（`test/haptics_guard_test.dart`）。
- **不许跑 `dart format`**（工具链是新版 tall style，一跑就重排整个文件、制造几百行无关 diff）。
- **反向验证的纪律**：临时把实现改回去看护栏变红之后，**必须手工改回来**，
  **绝不用 `git checkout --`** —— 那会把同一文件里刚写的护栏一起丢掉（v0.10.11 踩过）。
- **玻璃类动图一律**：`--width` 取裁剪宽度（不缩放）、`--fps 62`（16ms 出帧）、`--colors ≥ 128`
  （64 色会把那圈折射的彩虹量化没）。判彩边只能看 PNG。

## Review Focus

规格暗示、但**没有哪条任务用它自己的用例覆盖**的五类输入 / 失败模式，按最可能咬人的顺序。
每一条都要落成对应任务里的一步：

1. **迁移 `showDialog` 时把返回值 / 泛型弄丢。** 19 处里有 `showDialog<bool>` 这类，
   调用点 `await` 之后靠返回值分支（确认 vs 取消）。丢了就是「点了取消却当成确认」，
   **不报错**。→ Task 8 Step 5。
2. **换成自定义路由之后，点遮罩 / 按返回键的行为变了。** `DialogRoute` 与裸 `PopupRoute`
   在这两件事上的默认值不同。期望与现在**逐点一致**。→ Task 7 Step 4。
3. **`dialogCloser` 依赖的 `Route.isCurrent` 在自定义路由上仍然成立。** 它是「第二次 pop
   不关掉主界面」的唯一依据（黑屏那个 v0.9.0 反馈）。→ Task 8 Step 6（跑现成的两条用例）。
4. **弹窗几何断言在动画没走完时量。** `GlassMaterialize` 在 `t < 1` 时套着
   `Transform.scale(0.92…)`，中途量会差约 8%。期望所有几何断言都在 `pumpAndSettle` 之后。
   → Task 7 Step 5。
5. **响铃页的矮屏 / 小窗档。** 药丸窄了之后（`_thumbWShort 46`）凸出量只剩 3px 一边、
   折边的 `fade` 也小一截。期望仍然凸出、仍然折边、仍然不压住「再睡一会」。→ Task 5 Step 4。

---

### Task 1: 液态透镜竖直档的两处地基缺陷（护栏 + 反向验证）

**背景**：实现**已经在 `21f89a9` 里了**（原型那一提交）。本任务补护栏，并用反向验证
证明这两条护栏真的有鉴别力 —— 不重写实现。

**Files:**
- Modify: `app/lib/core/glass/liquid_lens.dart`（**只在反向验证那一步临时改，随后手工改回**）
- Test: `app/test/liquid_lens_test.dart`

**Interfaces:**
- Produces: `LiquidLensShape.leftCrossRadius` / `.rightCrossRadius`（`double`）——
  端头圆在**横轴**（`capsuleH` 那一轴）上的**实际**半径；前缘 = `height / 2`，
  后缘 = `height / 2 * (1 - 0.35 * stretch)`。

- [ ] **Step 1: 写三条护栏**

写在 `app/test/liquid_lens_test.dart` 里（该文件已有 `lensIconWarp` 的用例，风格照它）：

```dart
test('竖直档：折边会亮（这条以前永远为 null）', () {
  // 响铃页那枚药丸的几何：局部 itemW 38 / capsuleH 72 / pad 10，满升程
  final shape = LiquidLensShape.of(
    itemW: 38, capsuleH: 72, pad: 10, centerPage: 0,
    lift: 1, velocity: 0,
    metrics: const LiquidLensMetrics(
        protrude: 16, liftWidth: 6, rimScale: 0.7, velocityRef: 300),
  );
  expect(shape.width <= shape.height, isTrue, reason: '前提错了：这一档应当是竖直档');
  final e = refractedCapsuleEdge(shape);
  expect(e, isNotNull, reason: '竖直档的折边算出来是 null —— 边永远折不了');
  expect(e!.fade, greaterThan(0));
});

test('竖直档：折边的弦长是椭圆那条，不是横向那套', () {
  final shape = LiquidLensShape.of(/* 同上 */);
  final e = refractedCapsuleEdge(shape)!;
  final double cy = shape.centerY;
  final double k = 2 * cy / shape.height;
  final double expected = shape.width * math.sqrt(1 - k * k);
  expect(e.xR - e.xL, closeTo(expected, 0.5));
  expect(e.xL + e.xR, closeTo(2 * shape.centerX, 0.5), reason: '两端不对称');
});

test('横向档：横轴半径与原来那个逐值相等（底栏不受影响的可断言形式）', () {
  // 底栏那一档：itemW 88 / capsuleH 64 / pad 4
  for (final double s in <double>[0, 0.5, 1]) {
    final shape = LiquidLensShape.of(
        itemW: 88, capsuleH: 64, pad: 4, centerPage: 0,
        lift: 1, velocity: 0, stretch: s);
    expect(shape.width > shape.height, isTrue, reason: '前提错了：这一档应当是横向档');
    expect(shape.leftCrossRadius, closeTo(shape.leftRadius, 1e-9));
    expect(shape.rightCrossRadius, closeTo(shape.rightRadius, 1e-9));
  }
});
```

- [ ] **Step 2: 跑，确认三条全绿**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: PASS（实现已在 `21f89a9`）

- [ ] **Step 3: 反向验证 —— 把实现临时改回老写法，前两条必须红**

在 `app/lib/core/glass/liquid_lens.dart` 里做两处**手工**改动：

1. `refractedCapsuleEdge` 里 `final double rl = shape.leftCrossRadius;` 改回 `shape.leftRadius;`
   （`rr` 同理）；
2. 把那个 `if (shape.width <= shape.height) { … } else { … }` 整段删掉，
   只留 `else` 分支那两行（老算式）。

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: **FAIL** —— 第 1、2 条红（第 1 条 `Expected: not null`，第 3 条应当仍绿，因为它
量的就是横向档）

- [ ] **Step 4: 手工把两处改回来**

⚠️ **不许 `git checkout --`**：那会把同一个文件里别的东西一起丢掉。

- [ ] **Step 5: 再跑一遍，确认全绿**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/test/liquid_lens_test.dart
git commit -m "test(lens): 竖直档的折边与弦长护栏（反向验证过）"
```

---

### Task 2: `LiquidLens.restEdge`（静止时的边缘高光）

**Files:**
- Modify: `app/lib/core/glass/liquid_lens.dart`
- Test: `app/test/liquid_lens_test.dart`

**Interfaces:**
- Produces: `LiquidLens({… , double restEdge = 0})` —— 0..1 的浓度，**默认 0**。

- [ ] **Step 1: 写两条护栏**

```dart
testWidgets('restEdge = 0：与不带这一层逐字节相同', (tester) async {
  // 光栅化两次（一次 restEdge 默认、一次显式 0），逐字节比 —— 不同的像素必须为 0。
});

testWidgets('restEdge = 1：轮廓上出现白色像素', (tester) async {
  // 沿 shape.toPath() 取一圈采样点，断言其中最亮的一点比同一位置的背景亮 ≥ 20。
});
```

（画布与取像照 `test/glass_switch_liquid_test.dart` 的 `raster()` 写法：`RepaintBoundary` +
`tester.runAsync` + `toByteData(rawRgba)`。）

- [ ] **Step 2: 跑，确认绿**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: PASS

- [ ] **Step 3: 反向验证**

把 `LiquidLens.build` 里 `if (restEdge > 0) Positioned(…)` 那一层**删掉**。
Run: 同上。Expected: **第二条红**（第一条仍绿 —— 它量的是「不加东西」）。
然后**手工改回**。

- [ ] **Step 4: 再跑，确认绿，Commit**

```bash
git add app/lib/core/glass/liquid_lens.dart app/test/liquid_lens_test.dart
git commit -m "test(lens): restEdge 的两条护栏（默认 0 时逐字节不变）"
```

---

### Task 3: 底栏 / 分段器逐像素验收（停线任务）

**这是本轮唯一的「不改代码、只出证据」的任务，但它有停线权**：有差异就停在这里解决，
不往下走。

**Files:**
- 不修改任何源码。产物落 `app/build/visual-baseline/`（gitignored）。

- [ ] **Step 1: 在改动前的提交上开临时 worktree 并出基线**

⚠️ `toolchain/` 是 gitignored 的 —— 新 worktree 里**没有** Flutter，出图要用**主仓库**那套。

```bash
git worktree add ../ss-baseline 34d7684
cd ../ss-baseline/app
../../shiftassistant/toolchain/flutter/bin/flutter test tool/visual/
```

Expected: 出图落 `../ss-baseline/app/build/visual/`。

> `34d7684` 是**开关轨道色那一提交**，在原型（`21f89a9`）之前 —— 也就是
> 「液态透镜还没被动过」的那个状态。

- [ ] **Step 2: 把基线拷过来**

```bash
mkdir -p app/build/visual-baseline
cp -r ../ss-baseline/app/build/visual/. app/build/visual-baseline/
```

- [ ] **Step 3: 在当前工作区重渲一遍**

Run: `cd app && ../toolchain/flutter/bin/flutter test tool/visual/`
Expected: PASS，图落 `app/build/visual/`。

- [ ] **Step 4: 逐张比**

```bash
cd app && python ../scripts/diff_visual.py build/visual-baseline build/visual --threshold 0 --top 60
```

**通过标准分两栏**（这是本任务的核心，别扫一眼就过）：

**必须零差异**（这些一有差异就是回归）：

- 全部**静态**屏，尤其是 `00_home_shell*`、`36_home_shell_liquid*`、
  `42_segment_liquid*`、`38_alarm_liquid*`、`39_todos_liquid*`、`45_todo_check_liquid*`。
  理由：静止时 `lift = 0` → `reach = −pad < 0` → 折边本来就不画，两处修改都够不着它们。
- `46_switch_drag*`：开关自己关着 `showRefractedEdge`，折边不画，**不该有差异**。

**允许差异，但每一张都要能解释**：

- `08_ringing*` —— 本轮改的那一页；
- **`40_nav_lens_dragging_*` / `41_nav_lens_moving_*` 的 `small` / `landscape` 那几档** ——
  那些档下底栏的滴落进**竖直档**（小窗 `itemW 39`，宽度 49 < 高度 64），折边**以前不亮、
  现在亮了**。**这是修好了，不是回归**，但要在报告里逐张写清楚「哪一档、差在哪」。
- 响铃页那几张**时钟跳字**假象（差异框固定为 `(547,494)-(634,623)`）—— 与本轮无关。

- [ ] **Step 5: 有解释不了的差异就停下来解决**

不许「差不多能解释」就往下走。要么找出根因改掉，要么把这一条记进账本、明确它为什么
不是回归（并说清代价）。

- [ ] **Step 6: 删掉临时 worktree**

```bash
git worktree remove ../ss-baseline
```

- [ ] **Step 7: 把结论记下来（Task 11 写进 `AGENTS.md`）**

---

### Task 4: `LensWarpedVertical`（竖着走的透镜也能挤内容）

**Files:**
- Modify: `app/lib/core/widgets/lens_warped_cell.dart`
- Test: `app/test/liquid_lens_test.dart`

**Interfaces:**
- Produces: `LensWarpedVertical({required Listenable listenable, required double itemCenterY, required double Function() lensCenterY, required double halfHeight, required Widget child})` —— 与 `LensWarpedCell` **同一份纯函数** `lensIconWarp`，位移落到 dy、两个缩放互换。

- [ ] **Step 1: 写护栏**

```dart
testWidgets('竖轴：内容在透镜边缘被挤（位移沿 y、缩放互换）', (tester) async {
  // 把 itemCenterY 放在透镜中心正上方一个半高的位置（= 边缘），
  // 断言树上那个 Transform 的 matrix：平移只有 y 分量、且 scaleY < 1 < scaleX。
});

testWidgets('竖轴：内容离透镜很远时一层都不套', (tester) async {
  // 断言树里没有 Transform（「恒等就一层都不套」那条契约）。
});
```

- [ ] **Step 2: 跑，确认红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_lens_test.dart`
Expected: **FAIL** —— `LensWarpedVertical` 还不存在（编译不过也算红，但要说明是这条的原因）

> 说明：这个件是**新加的**，与 Task 1/2 那两处「实现已在原型里」不同 —— 它可以走
> 真·TDD（先红后绿）。

- [ ] **Step 3: 跑绿，Commit**

```bash
git add app/lib/core/widgets/lens_warped_cell.dart app/test/liquid_lens_test.dart
git commit -m "feat(lens): LensWarpedVertical —— 竖着走的透镜也能挤内容"
```

---

### Task 5: 响铃页那枚药丸的几何与色带

**Files:**
- Modify: `app/lib/features/alarm/alarm_ringing_screen.dart`
- Test: `app/test/alarm_ringing_liquid_test.dart`（**新建**）

**Interfaces:**
- Consumes: `LiquidLensShape.leftCrossRadius` / `.rightCrossRadius`（Task 1）、
  `LiquidLens.restEdge`（Task 2）、`refractedCapsuleEdge`（既有）。
- Produces: 常量 `_thumbW = 52` / `_thumbH = 38` / `_thumbWShort = 46` / `_thumbHShort = 33` /
  `_thumbProtrude = 16` / `_thumbLiftWidth = 6`。

- [ ] **Step 1: 写护栏（几何四条）**

```dart
testWidgets('按住：药丸凸出轨道两边', (tester) async {
  // 按住 → 渲一帧 → 取 LiquidLens.shape：断言 shape.height > _trackWidth（72）
});

testWidgets('按住：折边亮着，且 fade 随凸出量走', (tester) async {
  // 断言 refractedCapsuleEdge(shape) 非空、fade > 0
});

testWidgets('静止：药丸的底边就是轨道的底边', (tester) async {
  // 光栅化取药丸（饱和主色）的 bbox 下沿，与轨道 bbox 的下沿比，差 ≤ 1
});

testWidgets('色带接住药丸：两者之间没有缝', (tester) async {
  // 拖到 p ≈ 0.5 → 取「色带的最上沿」与「药丸的最下沿」，差 ≤ 1
});
```

- [ ] **Step 2: 跑，确认绿（实现已在 `21f89a9`）**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/alarm_ringing_liquid_test.dart`
Expected: PASS

- [ ] **Step 3: 反向验证（三条）**

逐条做、逐条改回：

1. `bottom: thumbBottom - (_trackWidth - thumbH) / 2` 的 `-` 改成 `+` → 第 3 条红；
2. `fillHeight = thumbBottom` 改回 `p * trackHeight` → 第 4 条红；
3. `_thumbProtrude` 改成 `6`（即 `protrude < pad`）→ 第 1、2 条红。

- [ ] **Step 4: 小窗档（200×400）—— Review Focus 第 5 条**

```dart
testWidgets('小窗档：仍然凸出、仍然折边', (tester) async {
  // tester.view.physicalSize = Size(200, 400)…
  // 断言 46 + 2*16 = 78 > 72，且折边非空
});
```

Expected: PASS。若这里红了，说明矮屏那一档的参数要单独调（`_thumbProtrudeShort`），
**不要**靠改断言糊过去。

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/alarm/alarm_ringing_screen.dart app/test/alarm_ringing_liquid_test.dart
git commit -m "test(ring): 药丸的几何与色带护栏（凸出 / 折边 / 贴底 / 无缝）"
```

---

### Task 6: 响铃页的两棵树（挂在液态玻璃开关后面）

**Files:**
- Modify: `app/lib/features/alarm/alarm_ringing_screen.dart`
- Modify: `app/test/liquid_scope_guard_test.dart`
- Test: `app/test/alarm_ringing_liquid_test.dart`

**Interfaces:**
- Consumes: `_thumbFace` / `_standardThumb` / `_liquidThumb`（Task 5 所在文件里，
  原型已经写好）。

- [ ] **Step 1: 写护栏**

```dart
testWidgets('标准档：树上没有透镜，走的是一枚实心白药丸', (tester) async {
  liquidGlassActive.value = false;
  // 断言 find.byType(LiquidLens) 为空；且药丸的尺寸与液态档一致（52 × 38）
});

testWidgets('液态档：树上有透镜', (tester) async {
  // 断言 find.byType(LiquidLens) 命中 1
});
```

- [ ] **Step 2: 改判据名单**

`app/test/liquid_scope_guard_test.dart`：`_allowed` 加
`'lib/features/alarm/alarm_ringing_screen.dart'`；**自证那条**的期望列表也加
`'lib/features/alarm/alarm_ringing_screen.dart'`（**按字典序**，在
`lib/features/home/glass_nav_bar.dart` 之前）。

- [ ] **Step 3: 跑两条**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/liquid_scope_guard_test.dart test/alarm_ringing_liquid_test.dart`
Expected: PASS（守门自证那条**必须**跟着一起绿 —— 只改 `_allowed` 不改自证会让它红）

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/alarm/alarm_ringing_screen.dart app/test/liquid_scope_guard_test.dart app/test/alarm_ringing_liquid_test.dart
git commit -m "feat(ring): 那枚上滑关闭的药丸挂在液态玻璃开关后面（两棵树 + 判据名单 5→6）"
```

---

### Task 7: 弹窗的统一入口（`GlassMaterialize` + `_GlassOverlayRoute` + `showGlassDialog`）

**Files:**
- Modify: `app/lib/core/widgets/glass_dialog.dart`
- Modify: `app/lib/core/design_tokens.dart`
- Test: `app/test/glass_overlay_test.dart`（**新建**）

**Interfaces:**
- Produces:
  - `AppTokens.durGlassIn = Duration(milliseconds: 300)`、`AppTokens.durGlassOut = Duration(milliseconds: 200)`
  - `class GlassMaterialize extends StatelessWidget { const GlassMaterialize({required Animation<double> animation, required Widget child}); }`
  - `Future<T?> showGlassDialog<T>({required BuildContext context, required WidgetBuilder builder})`
  - 私有 `class _GlassOverlayRoute<T> extends PopupRoute<T>`：
    `transitionDuration => AppTokens.durGlassIn`、`reverseTransitionDuration => AppTokens.durGlassOut`、
    `barrierDismissible => true`、`barrierColor => Colors.black26`、
    `barrierLabel` 由构造函数传入（`showGlassDialog` 里取
    `MaterialLocalizations.of(context).modalBarrierDismissLabel`）。

- [ ] **Step 1: 令牌先加**

`AppTokens` 里加那两个 `Duration`（**必须进令牌**，否则 `design_tokens_test` 打红），
并写清它们是「弹窗入场 / 退场」而不是别的。

- [ ] **Step 2: 写三条护栏**

```dart
testWidgets('进场比退场慢（两条时长真的分开了）', (tester) async {
  // 开一个 showGlassDialog，记下「面板从透明到完全出现」用了多少帧；
  // 关掉，记下退场用了多少帧。断言进场 > 退场。
});

testWidgets('点遮罩关窗，返回 null', (tester) async {
  // Review Focus 第 2 条
});

testWidgets('按返回键关窗，返回 null', (tester) async {
  // Review Focus 第 2 条
});
```

- [ ] **Step 3: 跑，确认红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/glass_overlay_test.dart`
Expected: **FAIL**（`showGlassDialog` 还不存在）

- [ ] **Step 4: 实现，跑绿**

- [ ] **Step 5: 加一条「动画走完之后树上没有 Transform」的护栏（Review Focus 第 4 条）**

```dart
testWidgets('落定之后：树上没有 Transform / Opacity 包着面板', (tester) async {
  // pumpAndSettle 之后断言面板的祖先里没有 Transform
});
```

- [ ] **Step 6: 跑现成的几何用例，确认没被转场打破**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/glass_dialog_test.dart`
Expected: PASS（它们都在 `pumpAndSettle` 之后量，所以 `t = 1` 那条早退路径会兜住）

- [ ] **Step 7: Commit**

```bash
git add app/lib/core/widgets/glass_dialog.dart app/lib/core/design_tokens.dart app/test/glass_overlay_test.dart
git commit -m "feat(dialog): 弹窗统一入口 —— 两条时长 + 凝聚 / 消散"
```

---

### Task 8: 把 19 处 `showDialog` 迁到统一入口

**Files:**
- Modify（8 个文件，每处把 `showDialog<X>(context: …, builder: …, barrierColor: Colors.black26)`
  换成 `showGlassDialog<X>(context: …, builder: …)`）：
  `app/lib/features/alarm/alarm_screen.dart`、
  `app/lib/features/calendar/schedule_editor_screen.dart`、
  `app/lib/features/calendar/schedule_management_screen.dart`、
  `app/lib/features/calendar/shift_template_picker_screen.dart`、
  `app/lib/features/profile/app_dialogs.dart`、
  `app/lib/features/profile/profile_screen.dart`、
  `app/lib/features/schedule/recurring_panel.dart`、
  `app/lib/features/schedule/schedule_screen.dart`
- Modify: `app/lib/core/widgets/glass_dialog.dart`（**最后一步**拿掉 `_Materialize` 那一层）
- Create: `app/test/glass_overlay_guard_test.dart`

**Interfaces:**
- Consumes: `showGlassDialog`（Task 7）。

- [ ] **Step 1: 写源码扫描护栏**

`app/test/glass_overlay_guard_test.dart`，照 `liquid_scope_guard_test.dart` 那套
（`support/source_scan.dart` 剥壳后扫 `lib/`）：

```dart
test('lib/ 里不再有裸 showDialog / showModalBottomSheet', () {
  // 允许的位置只有 lib/core/widgets/glass_dialog.dart（定义处）
});

test('守门自证：不豁免时命中的恰好是那一个文件', () {
  // 与 liquid_scope_guard_test 的自证同一条理由：只跑前一条的话，
  // 一次扫错目录 / 匹配串打错都会让它恒绿。
});
```

- [ ] **Step 2: 跑，确认红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/glass_overlay_guard_test.dart`
Expected: **FAIL**，名单里应当列出全部 19 + 9 处所在文件。

- [ ] **Step 3: 逐个迁（19 处）**

⚠️ **每处的泛型与 `await` 之后的用法必须原样保留**（Review Focus 第 1 条）。
`barrierColor: Colors.black26` 这一行删掉（入口里统一给了）。

- [ ] **Step 4: 跑全套，确认绿**

Run: `cd app && ../toolchain/flutter/bin/flutter test`
Expected: PASS

- [ ] **Step 5: 补两条「返回值被正确接住」的用例（Review Focus 第 1 条）**

挑两处有返回值的调用点（`schedule_screen.dart` 的删除确认、`profile_screen.dart` 的清空重置），
各写一条：**点「取消」不生效、点「确认」才生效**。

- [ ] **Step 6: 跑 `dialogCloser` 那两条路径（Review Focus 第 3 条）**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/todo_dialog_test.dart`
Expected: PASS（「点两次保存 / 保存后立刻取消」两条都不得黑屏）

- [ ] **Step 7: 拿掉 `GlassDialog` 里那份 `_Materialize`**

⚠️ **必须在 19 处全部迁完之后**再拿 —— 否则还没迁的那些会**同时失去**动画。

- [ ] **Step 8: 再跑全套，确认绿，Commit**

```bash
git add -A app/lib app/test
git commit -m "refactor(dialog): 19 处 showDialog 收敛到 showGlassDialog（凝聚由路由统一驱动）"
```

---

### Task 9: 底部弹层也走统一入口（9 处）

**Files:**
- Modify: `app/lib/core/widgets/glass_dialog.dart`（加 `showGlassSheet`）
- Modify（5 个文件）：`app/lib/core/widgets/glass_pickers.dart`、
  `app/lib/features/calendar/calendar_screen.dart`、
  `app/lib/features/calendar/schedule_editor_screen.dart`、
  `app/lib/features/calendar/shift_override_picker.dart`、
  `app/lib/features/profile/profile_screen.dart`
- Test: `app/test/glass_overlay_test.dart`

**Interfaces:**
- Produces: `Future<T?> showGlassSheet<T>({required BuildContext context, required WidgetBuilder builder})`

**做法**：与弹窗不同 —— 弹层**保留 Material 自带的「从底下升上来」**（那是弹层该有的动作），
所以 `showGlassSheet` 就是 `showModalBottomSheet` + 把内容包一层 `GlassMaterialize`，
**用路由自己的动画驱动**（`ModalRoute.of(context)!.animation`）。

- [ ] **Step 1: 写一条护栏**

```dart
testWidgets('弹层：入场时带上凝聚（模糊 + 缩放），落定后一层不剩', (tester) async {
  // 首帧断言树上 ImageFiltered / Transform 存在；pumpAndSettle 之后断言没有
});
```

- [ ] **Step 2: 跑红 → 实现 → 跑绿**

- [ ] **Step 3: 逐个迁（9 处），跑全套**

Run: `cd app && ../toolchain/flutter/bin/flutter test`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A app/lib app/test
git commit -m "refactor(dialog): 9 处 showModalBottomSheet 收敛到 showGlassSheet（保留上滑 + 加凝聚）"
```

---

### Task 10: 工装屏单与动图

**Files:**
- Modify: `app/tool/visual/visual_screens.dart`（响铃页那一屏的 `screenExtraPrefs` 加
  `'liquidGlass': true`，或新增一屏 `08_ringing_liquid`）
- Modify: `app/tool/gif/render_gifs_test.dart`（本计划写的时候已经有两条新动图了：
  「弹窗 · 凝聚入场」「响铃 · 上滑关闭的玻璃滴」）

- [ ] **Step 1: 响铃页进液态档屏单**

理由：**新界面 / 新形态必须进屏单**（AGENTS.md 那条规矩）。响铃页此前只有标准档一张。

- [ ] **Step 2: 出图，逐张看一遍**

Run: `cd app && ../toolchain/flutter/bin/flutter test tool/visual/`
Expected: PASS，且 `08_ringing_liquid*` 那张上药丸读得出玻璃、轨道那圈边光在。

- [ ] **Step 3: 出动图，看图**

```bash
cd app && ../toolchain/flutter/bin/flutter test tool/gif/ --plain-name '凝聚入场'
cd app && ../toolchain/flutter/bin/flutter test tool/gif/ --plain-name '上滑关闭的玻璃滴'
python scripts/make_gif.py --prefix dialog_condense_light_ --out work/gif/dialog-condense.gif \
    --crop 40,960,800,1500 --width 560 --fps 62 --colors 128
python scripts/make_gif.py --prefix ring_dismiss_light_ --out work/gif/ring-dismiss.gif \
    --crop 322,1240,518,1660 --width 216 --fps 62 --colors 128
```

- [ ] **Step 4: Commit**

```bash
git add app/tool
git commit -m "test(visual): 响铃页补液态档那一屏"
```

---

### Task 11: 收口（版本 / 更新日志 / 记忆 / 验收 / 发布）

**Files:**
- Modify: `app/pubspec.yaml`（`version: 0.10.13+137`）
- Modify: `app/lib/core/app_info.dart`（同步）
- Modify: `app/lib/features/profile/app_dialogs.dart`（`_changelogZh` / `_changelogEn` prepend）
- Modify: `AGENTS.md`（版本史 + 「最近改动」+ 验收数字）
- Create: `tools/gh/release-notes-v0.10.13.md`（gitignored，不入库）

- [ ] **Step 1: 版本号两处同步**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/app_info_test.dart`
Expected: PASS

- [ ] **Step 2: 更新日志**

prepend 一条 v0.10.13、删最旧、保持 10 条；**纯文本**（不许 `**` / 反引号 / 行首 `#` / `[文字](链接)`）。
Run: `cd app && ../toolchain/flutter/bin/flutter test test/changelog_window_test.dart`
Expected: PASS

- [ ] **Step 3: 全量验收**

```bash
cd app && ../toolchain/flutter/bin/flutter analyze          # 期望：No issues found!
cd app && ../toolchain/flutter/bin/flutter test             # 期望：全绿（678 + 本轮新增）
cd app && ../toolchain/flutter/bin/flutter test tool/visual/ # 期望：全绿（329 + 本轮新增）
```

- [ ] **Step 4: 把 Task 3 的结论补进 `AGENTS.md`**

写清「底栏与分段器逐像素不变」是**怎么验的**（基线取在 `34d7684`、逐张比、差异只有哪几类），
以及竖直档那两处缺陷的根因与修法。

- [ ] **Step 5: 发布**

```bash
git tag v0.10.13 && git push origin beta && git push origin v0.10.13
scripts/release.ps1 -SkipConfirm
curl -s https://raw.githubusercontent.com/Alec-WangLi/DaoBanAssistantPro/main/latest.json
```

Expected: `latest.json` 里 prerelease 是 `0.10.13`（**必须 curl 核对**，脚本打印的「发布成功」
只覆盖 Release 上传那一步）。末位非 0 = 测试版，发布说明里别写成正式版。

---

## 自检

**1. 规格覆盖**：规格 §3.1 → 已实施（`34d7684`），本轮无任务（护栏在那一提交里）；
§3.2 → Task 7/8/9；§3.3 → Task 5/6/10 + Task 4（文字）+ Task 2（`restEdge` 的护栏）+
Task 7 之前的接线（`restEdge: 1` 与轨道渐变、边光在原型里，Task 5 Step 1 的光栅护栏会覆盖它们）；
§4 → Task 1；§5 → Task 3；§6 → 各任务里的护栏步骤 + Task 8 Step 1 那条扫描；
§7 → Task 3/5/7 里都留了「有差异就停下来」的位置；§8 → 三个数按规格里写的默认值走
（300 / 200、不压上限、`restEdge = 1`）。

**2. 步骤扫描**：每个「写护栏」都给了测试名与断言，「反向验证」给了**确切的改法**
（改哪一行、改成什么），「跑」给了命令与期望输出。没有「处理边界情况」这类空话。

**3. 类型一致性**：`showGlassDialog` / `showGlassSheet` / `GlassMaterialize` /
`LensWarpedVertical` / `leftCrossRadius` / `restEdge` 在 Task 1/2/4/7 定义，
在 Task 5/7/8/9 消费，名字与签名逐处一致。

**4. Review Focus**：五条各落在一个具体步骤上（见上面的 → 指向）。

**5. 篇幅**：本计划比规格短 —— 每个步骤只决定一件事，代码块只放测试断言与签名。
