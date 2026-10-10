# 液态玻璃第二轮（分段器内容扭曲 / 开关重做 / 待办打勾）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把彩边宽度改成跟着透镜尺寸走，给分段器补上「内容被透镜边缘挤」，重做开关（尺寸 / 主色钮 / 升程统一 / 可拖），并把待办从开关换成新做的勾 `GlassCheck`。

**Architecture:** 先补上「彩边随尺寸缩放」这条地基（`rimScale`），否则开关上的一切都会被那圈过宽的光晕盖住。再把底栏那段「格被透镜挤」的仿射变换抽成共享件（底栏逐像素不变是硬验收），分段器接上。然后开关与勾各自接上一套已经成形的液态机制。

**Tech Stack:** Flutter 3.47 / Dart 3.13，Impeller；`CustomPainter` + 阻尼谐振子，无第三方依赖。

**Spec:** `docs/superpowers/specs/2026-10-01-liquid-glass-rollout-2-design.md`

## Global Constraints

- **底栏渲染逐像素不变**：`00_home_shell_*`（5 张）与 `36_home_shell_liquid_*`（5 张）与基线相同。Task 2 的唯一验收。
- **允许变的**（都要逐张看过再接受）：`37_profile_liquid_*` / `42_segment_liquid_*`（分段器彩边缩放）、**所有带开关的屏**（46×28 → 56×30）。已知假象照旧：`08_ringing_*` 的时钟跳字。
- **彩边缩放三处取值**：底栏 `1.0`（冻住）、分段器 `0.625`（40÷64）、开关 `0.469`（30÷64）。
- **白芯（`showRingCore`）在开关与勾上恒为假**，与钮是什么颜色无关。
- 档位判据 `liquidGlassActive` 只许出现在：`lib/core/glass/glass.dart`、`lib/features/home/`、`glass_segment.dart`、`glass_switch.dart`、**新增 `glass_check.dart`**。`lens_warped_cell.dart` **不在名单里**。`test/liquid_scope_guard_test.dart` 的两条断言都要照跑。
- 验收标准：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿（当前 **641**，只增不减）；`flutter test tool/visual/` 全绿（当前 **322**）。
- 版本号：`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 同步（由 `app/test/app_info_test.dart` 把关）；更新日志在 `app/lib/features/profile/app_dialogs.dart`，窗口固定 10 条、**纯文本、不许出现 markdown 标记**。
- 出图存基线用 `python scripts/diff_visual.py <基线目录> app/build/visual`（**从仓库根跑**）；动图用 `python scripts/make_gif.py`（**从仓库根跑**，它按 `app/build/visual/frames` 找帧）。
- **凡是有弹簧的动图出帧必须 16ms、合成用 `--fps 62`；裁剪宽度不缩放、`--colors 256`。**
- **不要跑 `dart format`**（工具链是新版 tall style，会把整个文件重排）。**不要用 `2>&1` 接 `git` / `gh` 的 stderr**（见 AGENTS.md）。

## Review Focus

（规格没写、但一个正常用这款 App 的人会碰到、且最容易出事的地方，最可能的排前面。）

1. **窄窗（200×400）下开关变宽会不会把行挤爆** —— 开关从 46 变 56，待办 / 闹钟 / 我的 / 排班编辑器四处的行 leading 全都变宽。工装的 `failOnOverflow` 会把溢出变成失败，但**只有真出了那一张图才算验过**（Task 4 的 Step 6）。
2. **分段器最靠边那一格的文字被「往外推」顶出格子** —— 扭曲是「压窄 + 往外推 5px」，`Center` 不裁也不报溢出，**这条没有自动信号**（Task 3 的 Step 4 用墨迹包围盒钉住）。
3. **白勾压在主色上**：teal 2.63 / orange 2.55 / rose 4.09，三种主色下不过 AA（AGENTS.md 里那条已知问题）。这一版**沿用既有做法不改**，但要**手工看一眼**（Task 6 的 Step 5）。
4. **抽「格」时把底栏弄坏** —— 抽取同时要保住 `ListenableBuilder(child: cell)` 那个「每帧只重建 Transform、内容 widget 不重建」的性质（Task 2 的 Step 1 与 Step 5）。
5. **`GlassCheck` 在真列表里的行高与对齐** —— 它比被替换掉的开关窄 18px、行高应当是 28 不变；在真待办列表里（Task 6 的 Step 6）核，不是只核孤立控件。

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `app/lib/core/widgets/lens_warped_cell.dart` | **新建**。「一格内容被透镜边缘挤一下」那层 `Transform`。**不读档位。** |
| `app/lib/core/widgets/glass_check.dart` | **新建**。待办那个勾，两档两棵树 + 勾路径两个纯函数。**读档位**。 |
| `app/lib/core/glass/liquid_lens_metrics.dart` | 改：加 `rimScale`。 |
| `app/lib/core/glass/liquid_lens.dart` | 改：`LiquidLensShape` 带 `rimScale`；四层光谱与浮起阴影乘它。 |
| `app/lib/core/design_tokens.dart` | 改：加 `lensRimRefCapsuleH`。 |
| `app/lib/features/home/glass_nav_bar.dart` | 改：`_iconsRow` 里的 `Transform` 换成 `LensWarpedCell`。 |
| `app/lib/core/widgets/glass_segment.dart` | 改：内容层接上 `LensWarpedCell`。 |
| `app/lib/core/widgets/glass_switch.dart` | 改：尺寸、钮、升程、白芯、拖动。 |
| `app/lib/features/schedule/schedule_screen.dart` | 改：待办那一行改用 `GlassCheck`。 |
| `app/test/lens_warped_cell_test.dart` | **新建**。 |
| `app/test/glass_switch_liquid_test.dart` | **新建**。 |
| `app/test/glass_check_test.dart` | **新建**。 |
| `app/test/liquid_lens_test.dart` | 改：`shotLens` 收 `metrics`；加彩边缩放两条。 |
| `app/test/glass_segment_liquid_test.dart` | 改：`shot` 收 `beforeCapture`；加扭曲两条。 |
| `app/test/liquid_scope_guard_test.dart` | 改：允许位置 4 处 → 5 处。 |
| `app/tool/visual/render_screens_test.dart` | 改：补 `44_todo_check` / `45_todo_check_liquid`。 |

---

## Task 1: `rimScale` —— 彩边与浮起阴影随透镜尺寸缩放

**Files:**
- Modify: `app/lib/core/design_tokens.dart`（加 `lensRimRefCapsuleH`）
- Modify: `app/lib/core/glass/liquid_lens_metrics.dart`（加 `rimScale`）
- Modify: `app/lib/core/glass/liquid_lens.dart`（`LiquidLensShape.rimScale` + 五处乘法）
- Test: `app/test/liquid_lens_test.dart`

**Interfaces:**
- Produces:
  - `AppTokens.lensRimRefCapsuleH = 64`
  - `LiquidLensMetrics({required double protrude, required double liftWidth, double rimScale = 1.0})`
  - `LiquidLensMetrics.forCapsule(double capsuleH)` → 同时给 `rimScale: capsuleH / AppTokens.lensRimRefCapsuleH`
  - `LiquidLensShape.rimScale`（由 `metrics` 带出，不给 `metrics` 时 = 1.0）

> ⚠️ **Step 1 是先把已有改动退回去。** 工作区里 `design_tokens.dart` / `liquid_lens.dart` / `liquid_lens_metrics.dart` 这三个文件**已经有一份为了实现这一条而写的改动**（出样图时写的，还没提交、也还没有测试）。TDD 要求 RED 是真的，所以先把它退回 HEAD，靠测试把它重新长出来。**这三份改动的内容与新写的等价，退回不会丢东西。**

- [ ] **Step 1: 把三个文件的改动退回 HEAD，并先存一份基线**

```bash
git checkout -- app/lib/core/design_tokens.dart app/lib/core/glass/liquid_lens.dart app/lib/core/glass/liquid_lens_metrics.dart
git status --short   # 应当只剩 app/tool/gif/tmp_rollout_probe_test.dart 是未跟踪

flutter test tool/visual/render_screens_test.dart
rm -rf build/visual/baseline-rollout-2 && mkdir -p build/visual/baseline-rollout-2
cp build/visual/*.png build/visual/baseline-rollout-2/
```

**`baseline-rollout-2` 是后面每一个「逐像素不变」验收的比对基准，整套计划只建这一次。**

- [ ] **Step 2: 先写失败用例**

`app/test/liquid_lens_test.dart`：先给 `shotLens` 加一个 `LiquidLensMetrics? metrics` 参数（照本文件既有的可选参数写法，透传给 `LiquidLensShape.of`），然后在「透镜几何」组里加两条纯函数用例：

```dart
test('forCapsule 顺带导出彩边缩放；不给 metrics 时是 1.0（底栏那一档）', () {
  expect(LiquidLensMetrics.forCapsule(64).rimScale, closeTo(1.0, 0.001));
  expect(LiquidLensMetrics.forCapsule(40).rimScale, closeTo(0.625, 0.001));
  expect(LiquidLensMetrics.forCapsule(30).rimScale, closeTo(0.46875, 0.001));
  expect(const LiquidLensMetrics(protrude: 10, liftWidth: 10).rimScale, 1.0);
  expect(
      LiquidLensShape.of(
              itemW: 90, capsuleH: 52, pad: 6, centerPage: 0, lift: 1, velocity: 0)
          .rimScale,
      1.0);
});
```

在渲染那一节（`ringArea` 之后）加一条：

```dart
testWidgets('彩边随尺寸缩：rimScale 小一档，带色相的像素面积必须明显更小', (tester) async {
  // 用户 2026-10-01：「既然这个开关是小的，那彩边范围自然也要自适应变小」。
  // 那四个宽度是照 64 高胶囊量的常量；原样搬到 30 高的开关上，内晕（10px）比钮
  // 本身还粗 —— 用户看到的是「像两个半圆一样」。
  const Color accent = Color(0xFF5B5BD6);
  Future<int> areaAt(double rimScale) async {
    final List<int> px = await shotLens(tester,
        lift: 1,
        accent: accent,
        velocity: AppTokens.lensVelocityRef,
        stretch: 1,
        metrics: LiquidLensMetrics(protrude: 10, liftWidth: 10, rimScale: rimScale),
        showRingCore: false,
        showRefractedEdge: false);
    return ringArea(px, accent);
  }
  final int big = await areaAt(1.0);
  final int small = await areaAt(0.469);
  expect(big, greaterThan(0), reason: '满速下一像素彩色都没有 —— 几何假设变了');
  expect(small / big, lessThan(0.75),
      reason: '彩边没跟着尺寸缩（实测 1.0 档 $big、0.469 档 $small）—— '
          '那 10px 的内晕在小控件上比控件本身还粗');
});
```

再加一条钉住「浮起阴影同一组缩」的弱信号：

```dart
testWidgets('外圈那几层（光晕 + 浮起阴影）一起缩：rimScale 小的不透明像素更少', (tester) async {
  // 反向验证：只把四层光谱乘上 rimScale、漏掉阴影，下面这条仍然绿 ——
  // 它能挡住的是「整组都忘了缩」，不是「少缩了其中一层」。要分辨后者只能出图看。
  const Color accent = Color(0xFF5B5BD6);
  Future<int> inked(double rimScale) async {
    final List<int> px = await shotLens(tester,
        lift: 1, accent: accent,
        metrics: LiquidLensMetrics(protrude: 10, liftWidth: 10, rimScale: rimScale));
    int n = 0;
    for (int i = 3; i < px.length; i += 4) {
      if (px[i] > 8) n++;
    }
    return n;
  }
  expect(await inked(0.469), lessThan(await inked(1.0)));
});
```

- [ ] **Step 3: 跑，确认红**

Run: `flutter test test/liquid_lens_test.dart`
Expected: 编译失败（`rimScale` 未定义），或 `shotLens` 不接受 `metrics`。

- [ ] **Step 4: 实现**

`design_tokens.dart`：在 `lensLiftRatio` 之后加

```dart
static const double lensRimRefCapsuleH = 64;
```
（注释写清：它是 `lensHaloWidth` 那四个数的分母；底栏显式传 1.0、不走这条缩放。）

`liquid_lens_metrics.dart`：加 `final double rimScale;`（构造参数默认 `1.0`），`forCapsule` 里补 `rimScale: capsuleH / AppTokens.lensRimRefCapsuleH`。

`liquid_lens.dart`：
- `LiquidLensShape._` 加 `required this.rimScale`，字段与 `of` 里的 `rimScale: m.rimScale`；
- 五处乘上 `shape.rimScale`：`_LensShadowPainter` 的**偏移与模糊**、`_LensGlowPainter` 的 `strokeWidth` 与 `MaskFilter.blur`、`_paintHalo` 两层的宽与模糊、`_paintSpectralRing` 的 `strokeWidth`、白芯那一层的 `strokeWidth`。
- ⚠️ 两个 `const MaskFilter.blur(...)` 会因为左值不再是常量而失去 `const`，那是预期的。

- [ ] **Step 5: 跑，确认绿**

Run: `flutter test test/liquid_lens_test.dart`
Expected: PASS（含既有 60 余条）。

- [ ] **Step 6: 全套 + 出图比对（这一步的行为对底栏必须是零变化）**

```bash
flutter test
flutter test tool/visual/render_screens_test.dart
python ../scripts/diff_visual.py build/visual/baseline-rollout-2 build/visual
```

Expected: 641 + 新增全绿；出图**只有 `37_profile_liquid_*` / `42_segment_liquid_*` 变**（分段器彩边缩放），`00_home_shell_*` 与 `36_home_shell_liquid_*` **十张全在「逐像素相同」里**。

- [ ] **Step 7: 提交**

```bash
git add app/lib/core/design_tokens.dart app/lib/core/glass/liquid_lens.dart app/lib/core/glass/liquid_lens_metrics.dart app/test/liquid_lens_test.dart
git commit -m "feat(glass): 彩边与浮起阴影随透镜尺寸缩放（rimScale）"
```

---

## Task 2: `LensWarpedCell` —— 把「一格被透镜边缘挤」抽成共享件

**Files:**
- Create: `app/lib/core/widgets/lens_warped_cell.dart`
- Modify: `app/lib/features/home/glass_nav_bar.dart`（`_iconsRow` 里那段 `Transform`）
- Test: `app/test/lens_warped_cell_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `LiquidLensMetrics`（本任务不用 `rimScale`，只用到调用点已经算好的 `halfWidth`）。
- Produces:

```dart
class LensWarpedCell extends StatelessWidget {
  const LensWarpedCell({
    super.key,
    required this.controller,   // LiquidLensController
    required this.iconCenterX,  // 这一格内容的中心，**胶囊局部坐标**
    required this.lensPad,      // 透镜位置换算成 px 用（底栏 = innerPad，分段器 = padChipV）
    required this.itemW,        // 每格宽度（**透镜那一套**的格宽）
    required this.halfWidth,    // 透镜半宽（用满升程那个值）
    required this.child,
  });
}
```

行为：内部 `ListenableBuilder(listenable: controller, child: child, ...)`；`lensIconWarp` 返回恒等时**直接返回 `child`**（不套 `Transform`）。

- [ ] **Step 1: 确认基线还在**

```bash
ls build/visual/baseline-rollout-2 | wc -l    # 应当与 build/visual 的图数一致
```

（基线在 Task 1 Step 1 建的，整套计划只有那一份。**不要重建** —— 它必须是所有改动之前的画面。）

- [ ] **Step 2: 写失败用例**

`app/test/lens_warped_cell_test.dart`（新建）：

```dart
testWidgets('透镜不在这格附近时：恒等 → 连一层 Transform 都不套', (tester) async {
  final LiquidLensController c = LiquidLensController(
      slots: 3, pad: 3, liftWidth: 6, vsync: const TestVSync(), initialSlot: 0);
  addTearDown(c.dispose);
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: LensWarpedCell(
      controller: c,
      iconCenterX: 10,          // 紧贴着透镜中心 → t ≈ 0，权重在钟形之外
      lensPad: 3,
      itemW: 100,
      halfWidth: 53,
      child: const SizedBox(width: 20, height: 20),
    ),
  ));
  expect(find.byType(Transform), findsNothing,
      reason: '恒等还套一层 Transform，会让这一格每帧都重绘');
});

testWidgets('透镜的边缘压在这一格上：横向压窄、朝远离透镜的方向推', (tester) async {
  final LiquidLensController c = LiquidLensController(
      slots: 3, pad: 3, liftWidth: 6, vsync: const TestVSync(), initialSlot: 0);
  addTearDown(c.dispose);
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: LensWarpedCell(
      controller: c,
      iconCenterX: 200,         // 右边那一格
      lensPad: 3,
      itemW: 100,
      halfWidth: 53,
      child: const SizedBox(width: 20, height: 20),
    ),
  ));
  // 把透镜挪到它左边一格，让**边缘**正好落在这格内容上。
  c.snapTo(1.0);
  await tester.pump();
  final Transform t = tester.widget<Transform>(find.byType(Transform));
  expect(t.transform.entry(0, 0), lessThan(1.0), reason: '没压窄');
  expect(t.transform.entry(1, 1), greaterThan(1.0), reason: '没纵向拉长');
  expect(t.transform.entry(0, 3), greaterThan(0), reason: '没朝外推');
});
```

- [ ] **Step 3: 跑，确认红**

Run: `flutter test test/lens_warped_cell_test.dart`
Expected: 编译失败（`LensWarpedCell` 未定义）。

- [ ] **Step 4: 实现**

`app/lib/core/widgets/lens_warped_cell.dart` —— 把 `glass_nav_bar.dart` 里 `_iconsRow` 那段（`ListenableBuilder` + `lensIconWarp` + `Transform` + 恒等早退）**原样搬过来**，句柄换成构造参数。不要顺手改数值。

`glass_nav_bar.dart` 的 `_iconsRow`：`Expanded(child: ListenableBuilder(...))` 整段换成

```dart
return Expanded(
  child: LensWarpedCell(
    controller: _lens,
    iconCenterX: lensPad + (i + 0.5) * itemW,
    lensPad: lensPad,
    itemW: itemW,
    halfWidth: (itemW + AppTokens.lensLiftWidth) / 2,
    child: cell,
  ),
);
```
`halfWidth` 用**底栏冻结的** `AppTokens.lensLiftWidth`（10），不是 `forCapsule` 的值。

- [ ] **Step 5: 出图逐像素比**

```bash
flutter test test/lens_warped_cell_test.dart
flutter test tool/visual/render_screens_test.dart
python ../scripts/diff_visual.py build/visual/baseline-rollout-2 build/visual
```
Expected: 新用例绿；出图**与基线逐像素相同，一张都不许变**（包含 `00_home_shell_*` 与 `36_home_shell_liquid_*` 十张）。

> ⚠️ **有任何一张不同就停在这里解决，不要往下走。** 那是「共享件与原实现不等价」的信号。允许的唯一例外是 `37_profile_liquid_*` / `42_segment_liquid_*`（Task 1 的分段器彩边缩放，本来就会变）与响铃页那 5 张的时钟跳字。

- [ ] **Step 6: 全套 + 提交**

```bash
flutter analyze && flutter test
git add app/lib/core/widgets/lens_warped_cell.dart app/lib/features/home/glass_nav_bar.dart app/test/lens_warped_cell_test.dart
git commit -m "refactor(glass): 抽出 LensWarpedCell，底栏改用共享件（逐像素不变）"
```

---

## Task 3: 分段器接上「内容被透镜边缘挤」

**Files:**
- Modify: `app/lib/core/widgets/glass_segment.dart`
- Test: `app/test/glass_segment_liquid_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `LensWarpedCell`。
- Produces: `GlassSegment` 的液态那棵树里，每一格被 `LensWarpedCell` 包住。

- [ ] **Step 1: 写失败用例**

`app/test/glass_segment_liquid_test.dart`：先给 `shot` 加一个 `Future<void> Function(WidgetTester)? beforeCapture` 参数（在 `pumpAndSettle` 之前调用，照 `renderScreen` 同名参数的语义），再加两条：

```dart
testWidgets('滑块扫过某一格时，那一格的文字被压窄（v0.10.10 补上的）', (tester) async {
  // 用户 2026-10-01：「滑块经过文字或者图标的时候，要有弯曲的特效，这个应该跟底栏对齐一下」。
  // 量**最靠右那一格**文字的墨迹宽度：静止时一个值，被边缘扫到时必须明显更窄。
  const int w = 300;
  Future<int> inkWidth({required bool dragged}) async {
    final List<int> px = await shot(tester, liquid: true, width: w,
        selected: 0,
        beforeCapture: dragged
            ? (WidgetTester t) async {
                final Rect box = t.getRect(find.byType(GlassSegment));
                final TestGesture g = await t.startGesture(
                    Offset(box.left + box.width * 0.18, box.center.dy));
                addTearDown(g.up);
                for (int i = 0; i < 20; i++) {
                  await t.pump(const Duration(milliseconds: 30));  // 过长按闸门
                }
                for (int i = 0; i < 40; i++) {
                  await t.moveBy(const Offset(2.5, 0));            // 拖过去
                  await t.pump(const Duration(milliseconds: 16));
                }
                return;
              }
            : null);
    return _inkWidthInCell(px, w, cell: 2);
  }
  final int still = await inkWidth(dragged: false);
  final int moved = await inkWidth(dragged: true);
  expect(moved, lessThan(still * 0.95),
      reason: '滑块扫过去文字纹丝不动（静止 $still、拖后 $moved）—— '
          '分段器的内容层没接上 LensWarpedCell');
});

testWidgets('扭曲不许把最靠边那一格的文字顶出格子', (tester) async {
  // 「被挤」= 压窄 + **往外推 5px**。最靠右那一格右边没有余量，推出去就是溢出。
  // Center 既不裁也不报溢出，**这条没有自动信号**，只能靠墨迹边界量。
  // 断言右边界 ≤ 该格右缘（含 1px 抗锯齿容忍）。
});
```

`_inkWidthInCell` / `_inkRightEdge` 是这两个用例共用的文件内辅助函数：在第 `cell` 格的水平范围、文字所在的那条 y 带里，找「明显暗于背景」的像素，返回它的最左 / 最右 / 宽度。阈值取 `亮度 < 110`（背景 `#F5F6FA` 约 245、主色滴约 110 —— 若滴也落在该带里，改成只数**比滴更暗**的像素，即 `< 90`）。

- [ ] **Step 2: 跑，确认红**

Run: `flutter test test/glass_segment_liquid_test.dart`
Expected: 第一条 FAIL（`moved` 与 `still` 相等）；第二条 PASS 或 FAIL，都可以。

- [ ] **Step 3: 实现**

⚠️ **只在液态那棵树上接**（与底栏同一条规矩：底栏的标准档传 `lensItemW: null`，一个变换都不套）。两处坐标不同构，别硬凑一个式子：

- **格子中心**：两棵树的格子都是**铺满全宽**的（液态那棵 `contentPad: 0`），所以 `cellW = (lensItemW × 格数 + 2 × padChipV) ÷ 格数`，`iconCenterX = (i + 0.5) × cellW`；
- **透镜中心**：液态那棵的滴是 `padChipV + position × lensItemW`。

`glass_segment.dart` 的 `_content` 加一个可选参数，只有液态那棵传：

```dart
Widget _content(int selectedIdx, {double? lensItemW}) {
  // 格子都是铺满全宽的；`lensItemW` 是**滴那一套**的格宽（LiquidTrack 给的），
  // 两者差一个 2×padChipV/格数 的尾巴 —— 硬凑一个式子会让扭曲峰值错开两三像素。
  final double cellW = lensItemW == null
      ? 0
      : lensItemW + 2 * AppTokens.padChipV / widget.count;
  final double halfWidth = lensItemW == null
      ? 0
      : (lensItemW + LiquidLensMetrics.forCapsule(widget.height).liftWidth) / 2;
  return Row(
    children: List<Widget>.generate(widget.count, (int i) {
      final Widget cell = Center(child: widget.itemBuilder(i, i == selectedIdx));
      if (lensItemW == null) return Expanded(child: cell);
      return Expanded(
        child: LensWarpedCell(
          controller: _lens,
          iconCenterX: (i + 0.5) * cellW,
          lensPad: AppTokens.padChipV,
          itemW: lensItemW,
          halfWidth: halfWidth,
          child: cell,
        ),
      );
    }),
  );
}
```
`_buildStandard` 那处调用保持 `_content(selectedIdx)`（不传 `lensItemW`）；`_buildLiquid` 的 `contentBuilder` 里改成 `_content(_lens.previewIndex ?? _committed, lensItemW: itemW)`。

（`lensItemW == null` 时 `cellW` / `halfWidth` 那两个 0 是**死值** —— 用不上，但 Dart 的 `final` 必须先初始化。也可以把两个 helper 提成局部函数只在需要时算；取哪个都行，别把标准档也接上。）

- [ ] **Step 4: 跑，确认绿**（两条都要绿，尤其第二条）

Run: `flutter test test/glass_segment_liquid_test.dart`

- [ ] **Step 5: 全套 + 出图**

```bash
flutter analyze && flutter test
flutter test tool/visual/render_screens_test.dart
python ../scripts/diff_visual.py build/visual/baseline-rollout-2 build/visual
```
Expected: 全绿；**只有液态档那两张带分段器的图变**（`37_profile_liquid*` / `42_segment_liquid*`）—— 因为扭曲**只接在液态那棵树上**（与底栏同一条规矩）。

⚠️ **标准档的分段器屏（`02_editor*` / `03_management*` / `05_todos*` / `06_alarm*` / `37_profile_light|dark|en|small|landscape`）必须逐像素相同。** 它们要是也变了，说明你把标准档那棵也接上了 —— 那是两档观感不一致，不是本任务要的东西。底栏十张同样仍须逐像素相同。

- [ ] **Step 6: 提交**

```bash
git add app/lib/core/widgets/glass_segment.dart app/test/glass_segment_liquid_test.dart
git commit -m "feat(segment): 内容层接上 LensWarpedCell（滑块扫过时文字被边缘挤）"
```

---

## Task 4: `GlassSwitch` 外观 —— 尺寸、主色钮、升程统一、白芯关

**Files:**
- Modify: `app/lib/core/widgets/glass_switch.dart`
- Test: `app/test/glass_switch_liquid_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 的 `LiquidLensMetrics.forCapsule`（带 `rimScale`）。
- Produces: `GlassSwitch({width = 56, height = 30, ...})`。

- [ ] **Step 1: 写失败用例**

`app/test/glass_switch_liquid_test.dart`（新建）。文件顶部固定一个主色，免得跟着主题漂：

```dart
const Color _accent = Color(0xFF5B5BD6);
```

再照 `glass_segment_liquid_test.dart` 的 `shot` 写一个本文件的光栅化辅助 `shotSwitch(tester, {required bool liquid, required bool value, bool hold = false})` —— 一枚 `GlassSwitch(value: value, activeColor: _accent, onChanged: (bool _) {})` 居中，`liquidGlassActive` 由参数拨；`hold: true` 时走 `startGesture` + 推 20 帧 30ms（过长按闸门）。两个测量辅助：`_knobCentre(px)`（钮心那一点的颜色）、`_knobInk(px)`（带主色相且不贴背景的像素的包围盒 → `(宽, 高)`）。文件要 `import 'package:shiftassistantpro/core/glass/liquid_lens.dart';`（第三条断言读 `LiquidLens` 的属性）。

三条用例：

```dart
testWidgets('液态档的钮是主色，不是白的（与分段器那枚要同一件东西）', (tester) async {
  // 用户 2026-10-01：「颜色变浅了，尤其是跟主题模式等，有明显的颜色差别。
  // 理论上它们应该都是一样的」—— 原来钮是 `fill: [white, white]`，材质与分段器的滴根本不同。
  final List<int> px = await shotSwitch(tester, liquid: true, value: false);
  final HSLColor c = HSLColor.fromColor(_knobCentre(px));
  expect((c.hue - HSLColor.fromColor(_accent).hue).abs(), lessThan(20),
      reason: '钮的中心不在主色的色相上 —— 钮还是白的/灰的');
  expect(c.saturation, greaterThan(0.25));
});

testWidgets('白芯是关掉的（它在小钮上会渲成一道横穿钮身的白线）', (tester) async {
  // v0.10.9 关掉白芯的理由是「白上画白等于没画」，那只覆盖了白钮那一档；
  // 钮一改成主色，白芯就回来了 —— 而且在小钮上它渲成一道**横穿钮身的白线**。
  //
  // ⚠️ **这一条断言的是配置，不是像素**，是有意的：白芯的线宽也跟着 `rimScale`
  // 缩到了 0.47px，抗锯齿之后它把像素亮度顶到约 170 —— 落在「钮身不该有近白像素」
  // 这类像素判据的门槛之下，**那种写法没有鉴别力**（自己会把这一条放过去）。
  // 配置断言是完全有鉴别力的：把 `showRingCore` 改回 true 立刻红。
  await shotSwitch(tester, liquid: true, value: false);
  expect(tester.widget<LiquidLens>(find.byType(LiquidLens)).showRingCore, isFalse,
      reason: '白芯开着 —— 在小钮上它是一道横穿钮身的白线');
});

testWidgets('按住时纵横一起长（不再「只往纵向拉长」）', (tester) async {
  // 用户 2026-10-01：「你参考底部导航栏那个滑块……还是优先把它统一起来」。
  final (int w0, int h0) =
      _knobInk(await shotSwitch(tester, liquid: true, value: false));
  final (int w1, int h1) =
      _knobInk(await shotSwitch(tester, liquid: true, value: false, hold: true));
  expect(w1, greaterThan(w0), reason: '宽度没长 —— 那是 v0.10.9 的「只长个儿」');
  expect(h1, greaterThan(h0));
});
```

`_knobInk` = 「明显带主色相且不贴背景」的像素的包围盒（宽、高）。`hold: true` 走 `startGesture` + 推 20 帧 `30ms`（过长按闸门）。

- [ ] **Step 2: 跑，确认红**

Run: `flutter test test/glass_switch_liquid_test.dart`
Expected: 第一条与第三条 FAIL（钮是白的、按住时宽度不变）。**第二条是守卫，它现在就是绿的** —— v0.10.9 已经为白钮把白芯关掉了，本任务要保证把 `fill` 换成主色之后**它仍然是绿的**（这一点正是它存在的理由：那只关掉的一档一换颜色就失效）。

- [ ] **Step 3: 实现**

`glass_switch.dart`：
- 默认 `width` 46 → **56**、`height` 28 → **30**（**两档一起改**：只改液态档的话切档位时控件会跳一下）。
- `_buildLiquid` 的 `LiquidTrack`：删掉 `fill: const <Color>[Colors.white, Colors.white]`（用默认的主色渐变）；`metrics` 从 `const LiquidLensMetrics(protrude: 8, liftWidth: 0)` 改成 `LiquidLensMetrics.forCapsule(widget.height)`；`showRingCore` 保持 `false`。
- 控制器：`liftWidth: LiquidLensMetrics.forCapsule(widget.height).liftWidth`（原来是 0）。
- `_buildStandard` 的 `thumbSize = widget.height - 6` 跟着高度走，不用改。
- 类的文档注释要改：把「钮是白色玻璃球 / 按住时纵向拉长 / 参考 iOS 26」那一段换成新的事实（主色滴、与另两处同一套升程、尺寸 56×30）。

- [ ] **Step 4: 跑，确认绿**

Run: `flutter test test/glass_switch_liquid_test.dart test/glass_switch_test.dart`
Expected: 全绿（`glass_switch_test.dart` 那两条既有的「开着点得动 / 置灰点不动」是触觉与 `enabled` 的护栏，不许改）。

- [ ] **Step 5: 出图逐像素比 + 窄窗（Review Focus 1）**

```bash
flutter test tool/visual/render_screens_test.dart
python ../scripts/diff_visual.py build/visual/baseline-rollout-2 build/visual
```
Expected: **所有带开关的屏都变**（`05_todos*` / `06_alarm*` / `03_management*` / `02_editor_*` / `37_profile*` / `43_switch_liquid*` / `17_getting_started*`）。逐张看过，**特别是 `*_small`（200×400）那几档** —— 开关宽了 10px，`failOnOverflow` 会把溢出变成失败，所以「跑过了」本身就是窄窗没爆的证据。

- [ ] **Step 6: 全套 + 提交**

```bash
flutter analyze && flutter test
git add app/lib/core/widgets/glass_switch.dart app/test/glass_switch_liquid_test.dart
git commit -m "feat(switch): 尺寸 56×30、钮改主色滴、升程与另两处统一"
```

---

## Task 5: `GlassSwitch` 拖动

**Files:**
- Modify: `app/lib/core/widgets/glass_switch.dart`
- Test: `app/test/glass_switch_liquid_test.dart`（加用例）

**Interfaces:**
- Consumes: Task 4 的开关；`LiquidLensController.dragStart / dragUpdate / release`（v0.10.9 已有，签名不变）。

- [ ] **Step 1: 写失败用例**

```dart
testWidgets('拖到另一端松手：值翻转', (tester) async {
  // 用户 2026-10-01：「长按想拖动的时候，它拖不动，好像没有加这个动作」。
  bool? got;
  await pumpSwitch(tester, liquid: true, value: false, onChanged: (bool v) => got = v);
  final Rect box = tester.getRect(find.byType(GlassSwitch));
  final TestGesture g = await tester.startGesture(box.centerLeft + const Offset(12, 0));
  addTearDown(g.up);
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 30));   // 过长按闸门
  }
  for (int i = 0; i < 40; i++) {
    await g.moveBy(const Offset(1.0, 0));                  // 拖到另一端
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  expect(got, isTrue);
});

testWidgets('拖回原处松手：值不变（不许自己抖一下）', ...);   // got 必须仍是 null

testWidgets('点按仍然只拨一下，钮不跟着手指跑', ...);          // v0.10.9 那条护栏的加强版：
                                                              // 在开着的那枚左半边按下 → 钮不动
```

- [ ] **Step 2: 跑，确认红**：前两条 FAIL（`got` 是 null）。**第三条是守卫**（v0.10.9 的 `moveToSlot: false` / `followFinger: false` 已经保证了它），改成拖动之后它必须仍然是绿的 —— 接拖动最容易把「点按不挪钮」一起弄坏。

- [ ] **Step 3: 实现**

`_buildLiquid` 的 `GestureDetector` 上加三个回调（`onTapDown / onTapUp / onTapCancel` 保留原样）：

```dart
onHorizontalDragStart: (DragStartDetails d) {
  _lens.setItemW(itemW);
  _lens.dragStart(d.localPosition.dx);
},
onHorizontalDragUpdate: (DragUpdateDetails d) {
  _lens.setItemW(itemW);
  _lens.dragUpdate(d.localPosition.dx);
},
onHorizontalDragEnd: (DragEndDetails _) {
  // 松手时钮落在哪一端就切到哪一端；落回原处就什么都不做。
  if (_lens.release() != (widget.value ? 1 : 0)) _toggle();
},
```
**不设「必须先按住 110ms」的闸门** —— 那个闸门只管「拉长」这个视觉，不该管能不能拖。

- [ ] **Step 4: 跑，确认绿**

Run: `flutter test test/glass_switch_liquid_test.dart test/glass_switch_test.dart`

- [ ] **Step 5: 全套 + 提交**

```bash
flutter analyze && flutter test
git add app/lib/core/widgets/glass_switch.dart app/test/glass_switch_liquid_test.dart
git commit -m "feat(switch): 支持横向拖动拨动，松手吸附到最近一端"
```

---

## Task 6: `GlassCheck` —— 待办的勾

**Files:**
- Create: `app/lib/core/widgets/glass_check.dart`
- Modify: `app/lib/features/schedule/schedule_screen.dart`（待办那一行）
- Modify: `app/test/liquid_scope_guard_test.dart`（允许位置 4 → 5）
- Test: `app/test/glass_check_test.dart`（新建）
- Modify: `app/tool/visual/render_screens_test.dart`（补两屏）

**Interfaces:**
- Consumes: Task 1 的 `LiquidLensMetrics.forCapsule`、`LiquidLens`、`QScale` / `springTo`（`core/motion.dart`）。
- Produces:

```dart
class GlassCheck extends StatefulWidget {
  const GlassCheck({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.size = 28,
    this.enabled = true,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  final double size;
  final bool enabled;
}

/// 勾的路径（在 [size]×[size] 的方框里）。**纯函数**，好在用例里直接量长度。
Path checkMarkPath(double size);

/// 勾「描到一半」的那一段（[progress] 0..1）。纯函数。
Path checkMarkPathAt(double size, double progress);
```

- [ ] **Step 1: 写失败用例**

`app/test/glass_check_test.dart`（新建）。同样先固定主色 `const Color _accent = Color(0xFF5B5BD6);`，并写一个 `shotCheck(tester, {required bool liquid, required bool value})` 把一枚 `GlassCheck(value: value, activeColor: _accent, onChanged: ...)` 光栅化成 RGBA；`_minLuminance(px)` 取全图最暗亮度，`_maxHueDelta(px, accent)` 沿用 `liquid_lens_test.dart` 那个「离主色最远的色相偏离」写法。四条：

```dart
test('勾是「描出来」的：一半进度恰好是一半长度', () {
  final double full = checkMarkPath(28).computeMetrics().first.length;
  final double half =
      checkMarkPathAt(28, 0.5).computeMetrics().first.length;
  expect(half, closeTo(full / 2, full * 0.02));
  expect(checkMarkPathAt(28, 0).computeMetrics().first.length, closeTo(0, 0.01));
});

testWidgets('两档是两棵树：光栅化像素必须不同', (tester) async {
  // 反过来说：这条要是绿着不动，说明液态档根本没生效（v0.10.1 出过这个岔子）。
});

testWidgets('未勾选时有一圈**看得见**的轮廓', (tester) async {
  // 这一条钉的是一个真犯过的错：描边原来用 `glassBorder(isDark)` —— 它在浅色下是
  // **白色 @0.90**，画在近白的页面上等于没画。判据要能把它照出来。
  final List<int> px = await shot(tester, liquid: false, value: false);
  expect(_minLuminance(px), lessThan(170),
      reason: '未勾选的圆里一个明显暗于背景的像素都没有 —— 那圈描边是白画白');
});

testWidgets('勾上没有彩边', (tester) async {
  // 规格 §4.3：控件太小，理由与开关同（§3.1）。
  final List<int> px = await shot(tester, liquid: true, value: true);
  expect(_maxHueDelta(px, _accent), lessThan(12));
});

testWidgets('点一下：值翻转一次', (tester) async {
  // 顺带钉住 `Haptics.select()` 只发一次（与开关同一档语义）。
});
```

- [ ] **Step 2: 跑，确认红**：编译失败（`checkMarkPath` 未定义）。

- [ ] **Step 3: 实现 `glass_check.dart`**

两棵树，与底栏 / 分段器 / 开关同一套写法（`ValueListenableBuilder<bool>(valueListenable: liquidGlassActive, ...)`）。两档共同的部分：
- 尺寸 `size`（默认 28）的方框；
- `progress` 走**弹簧**（`AnimationController.unbounded` + `springTo(_t, value ? 1 : 0)`，`AppTokens.qSpring`）；
- 触觉 `Haptics.select()`，只在值真的变了时发一次。

**标准档**：`QScale(pressed, scale: AppTokens.pillGrow)` 包一个 `Container`（`BoxShape.circle`），底色 `Color.lerp(glassTint(isDark, true).first, accent, t)`、描边 `Color.lerp(navBorder(isDark).withValues(alpha: 0.45), accent.withValues(alpha: 0.55), t)`，里面是 `CustomPaint(size: Size.square(size), painter: _CheckMarkPainter(progress: t, color: Colors.white))`。

**液态档**：一枚 `LiquidLens`（`itemW = capsuleH = size`、`pad: 0`、`centerPage: 0`、`velocity: 0`、`stretch: 0`、`motion: 0`、`metrics: LiquidLensMetrics.forCapsule(size)`），`lift` 由第二条弹簧驱动（按住 → 1）；`fill` 是 `Color.lerp` 出来的两色：玻璃档用 `glassTint(isDark, true)`，勾上档用 `[accent@0.95, accent@0.82]`（**不用 `accentGradient` 的 0.85/0.50**，理由见规格 §3.4）；`showRingCore: false`、`showRefractedEdge: false`。
外面叠一圈 `_CheckRingPainter`（1.5px、`navBorder(isDark).withValues(alpha: 0.45)` → `accent@0.55`），**环与勾跟着同一个 `lift` 一起放大**（否则按住时圆胀出去、圈留在原地 —— 样图里看得到）。

- [ ] **Step 4: 跑，确认绿**

Run: `flutter test test/glass_check_test.dart`

- [ ] **Step 5: 接进待办页 + 改守门名单**

`schedule_screen.dart` 那一行：`GlassSwitch(value: e.isCompleted, onChanged: (v) async {...})` → `GlassCheck(value: e.isCompleted, onChanged: (v) async {...})`。**回调体一个字不改** —— 那句「这里不加 `Haptics.commit()`」的注释继续成立（`GlassCheck` 自己发 `select()`）。

`liquid_scope_guard_test.dart`：`_allowed` 加 `'lib/core/widgets/glass_check.dart'`；第二条自证断言的期望列表按字典序补上它：

```dart
<String>[
  'lib/core/glass/glass.dart',
  'lib/core/widgets/glass_check.dart',
  'lib/core/widgets/glass_segment.dart',
  'lib/core/widgets/glass_switch.dart',
  'lib/features/home/glass_nav_bar.dart',
],
```

- [ ] **Step 6: 出图：补两屏 + 核真列表（Review Focus 5）**

`render_screens_test.dart` 补两条一次性的屏（照 `42_segment_liquid` / `43_switch_liquid` 的写法）：

- `44_todo_check`：`ScheduleScreen`（标准档），`beforeCapture` 里点一下第一行那个勾 → 图上同时有「勾上」与「没勾」两态，且是在**真列表**里。
- `45_todo_check_liquid`：同上，但 `useLiquidGlassTier()` + `extraPrefs: {'liquidGlass': true}`。

```bash
flutter test tool/visual/render_screens_test.dart
python ../scripts/diff_visual.py build/visual/baseline-rollout-2 build/visual
```
看两张新图：行高不变、勾与标题基线对齐、**删除线与淡色文字照旧**、小窗那一档不出问题。

- [ ] **Step 7: 全套 + 提交**

```bash
flutter analyze && flutter test
git add app/lib/core/widgets/glass_check.dart app/lib/features/schedule/schedule_screen.dart app/test/liquid_scope_guard_test.dart app/test/glass_check_test.dart app/tool/visual/render_screens_test.dart
git commit -m "feat(todo): 待办改用 GlassCheck（两档两棵树）+ 屏单补两屏"
```

---

## Task 7: 收口

**Files:**
- Modify: `app/lib/features/profile/app_dialogs.dart`（更新日志）
- Modify: `app/pubspec.yaml` + `app/lib/core/app_info.dart`（版本号，`Z` +1 → `0.10.10+134`）
- Modify: `AGENTS.md`
- Create: `tools/gh/release-notes-v0.10.10.md`
- Delete: `app/tool/gif/tmp_rollout_probe_test.dart`（探针）

- [ ] **Step 1: 动图搬进正式素材线**

把探针里那四条拍法搬进 `app/tool/gif/render_gifs_test.dart`（分段器扭曲改前改后对照 / 开关按下与拖动 / 待办打勾两档），**出帧 16ms**，合成：

```bash
python scripts/make_gif.py --prefix <prefix> --out work/gif/<name>.gif --crop <裁剪> --width <不缩放> --fps 62 --colors 256
```
出完**看过**再删掉 `app/tool/gif/tmp_rollout_probe_test.dart`。

- [ ] **Step 2: 更新日志**

`app_dialogs.dart` 的 `_changelogZh` / `_changelogEn`：**prepend 一条、删最旧一条**（窗口恒 10 条）、中英版本号列表一致、**纯文本（不许出现 `**` / 反引号 / 行首 `#` / `[文字](链接)`）**。内容写这一版改了什么：分段器滑块扫过时文字被边缘挤、开关重做（更长、主色钮、能拖动）、彩色边缘的宽度现在会随控件大小自适应、待办改成打勾。

- [ ] **Step 3: 版本号**

`pubspec.yaml` 的 `version: 0.10.10+134` 与 `app_info.dart` 的 `appVersion` 同步。

Run: `flutter test test/app_info_test.dart test/changelog_window_test.dart`
Expected: PASS。

- [ ] **Step 4: AGENTS.md**

- 版本史那一行补 `0.10.10(+134)`；
- 「最近改动」加一条，含：彩边宽度是**尺子**问题（照 64 高胶囊量的常量搬到小控件上比控件还粗，症状是「两个半圆」）、浮起阴影同源、白芯按控件尺寸判而不是按颜色判、半透在小控件上读作「颜色变浅」、**动图管线这条定死**（玻璃类动图不缩放 + 256 色 + `--fps 62`）、开关尺寸改动**有意**动了标准档、`GlassCheck` 只替换了一处开关。

- [ ] **Step 5: 全套验收（含 Review Focus 3 的手工那一项）**

```bash
flutter analyze
flutter test
flutter test tool/visual/
python scripts/diff_visual.py app/build/visual/baseline-rollout-2 app/build/visual
```
Expected: 0 issue；全绿；**底栏十张逐像素相同**。

再**手工看一眼**「白勾压在主色上」的对比度：把主色调切到 teal / orange / rose，看 `44_todo_check` 那两张图里的勾还读不读得出来。**这一版不改它**（规格 §9），看的结果写进 `tools/gh/release-notes-v0.10.10.md` 的备注里。

- [ ] **Step 6: 发布（测试版走 `beta` 分支）**

```bash
git push origin beta
git tag v0.10.10 && git push origin v0.10.10
flutter build apk --release --target-platform android-arm64
cp app/build/app/outputs/flutter-apk/app-release.apk dist/倒班助手Pro-v0.10.10.apk
powershell -File scripts/release.ps1 -SkipConfirm   # 它**不构建**，只复制现成的 APK（第 4 步的闸门就是查这个）
```
发完 curl 一次 `main` 上的 `latest.json` 核对版本号（见 AGENTS.md 的「分支与发布」）。

---

## 自检记录

- **规格覆盖**：§2 七条 → Task 2/3（扭曲）、Task 4/5（开关）、Task 6（勾）；§3.1–3.2 两条 → Task 1 的 `rimScale`；§3.3 白芯 → Task 4 Step 1 的**第二条**；§3.4 半透 → Task 6 Step 3 的实现（`fill` 用接近不透明的 `[accent@0.95, accent@0.82]` 而不是 `accentGradient`），**这一条没有独立用例** —— 它是一次取色，样图里看得见，用例断言「勾上时主色够浓」只会重复实现里的那个数；§4.1 → Task 3；§4.2 → Task 4/5；§4.3 → Task 6；§5 结构 → 文件结构表；§6 → 各 Task 的验收步 + Task 6 Step 5/6；§7 动图管线 → Global Constraints + Task 7 Step 1；§8 风险 → Review Focus；§9 不做 → 各 Task 未触及那些文件。
- **Review Focus 五条各自落在哪**：① 窄窗 → Task 4 Step 5（`failOnOverflow`）；② 边格文字顶出 → Task 3 Step 1 第二条；③ 白勾对比度 → Task 7 Step 5 的手工项；④ 底栏被抽坏 → Task 2 Step 5 的停线；⑤ 真列表里的行高 → Task 6 Step 6。
- **三处写计划时才定下来的事**（规格没说死，这里钉住）：
  1. **分段器的扭曲只接液态那棵树** —— 与底栏同一条规矩（底栏标准档传 `lensItemW: null`，一个变换都不套）。判定理由是两棵树的**滑块坐标系不同构**：标准档的滑块中心恰好是 `(page+0.5)×格宽`，液态档的滴中心是 `pad + position×滴格宽`。硬凑一个式子会让峰值错开两三像素。**代价**：标准档那一格不动，两档切换时不会有「扭曲突然出现」的跳变（标准档本来就没有扭曲）。
  2. **`44_todo_check` 拆成两屏**（`44` 标准档 + `45` 液态档）—— 一个 `GlassCheck` 只能读到一个档位，要同时拍到两档只能出两张。
  3. **「白芯关掉了」那条断言写成配置断言而不是像素断言** —— 白芯的线宽跟着 `rimScale` 缩到 0.47px，抗锯齿之后它把像素亮度顶到约 170，落在「钮身不许有近白像素」这类判据的门槛之下，**那种写法自己会把它放过去**。配置断言（`showRingCore == false`）是完全有鉴别力的。
