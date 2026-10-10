# 拖选那条水带 实施计划（第六轮 · 液态玻璃推广）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把日历上「长按拖选一段日子」那层逐格 14% 淡染，在液态档换成**一枚真的水带**：
同一行内整条（缝被盖住）、两个真端头圆、按住时漫上来、末端走弹簧淌到新的一格、
只有流动那一端挤字、彩边跟着末端方向亮。

**Architecture:** 网格之上多一层（与那枚选中块同一层位）。形状是**纯函数**
（区间 → 每行一段 → 多段圆角矩形的并集），材质与那枚块共用一份 —— 为此先把
「轮廓」这一维从 `LiquidLensShape` 里抽出来（`LiquidLensOutline`），
四个既有调用点一个字不改。标准档那棵树逐像素不变。

**Tech Stack:** Flutter 3.47 / Dart 3.13，Impeller，无第三方依赖。
工具链在 `toolchain/`（gitignored）：`toolchain/flutter/bin/flutter`。
**不要跑 `dart format`**（新版 tall style 会重排整个文件、制造几百行无关 diff）。

**Spec:** `docs/superpowers/specs/2026-10-01-liquid-glass-range-band-design.md`
（形状 A 是用户在 A/B/C 对照图上选的；被否掉的 B/C 理由在 spec §9）

## Global Constraints

- **标准档逐像素不变**：今天那排逐格 14% 淡染与 `day-range-N` 两个 key 原样留着。
  每个任务收尾都要能回答这一条（改到 UI 的任务跑一次逐张比基线）。
- **判据只许在 `calendar_screen.dart` 那一个调用点读** `liquidGlassActive.value`；
  新抽的两个文件（`range_band.dart` / `calendar_range_band.dart`）**都不读** ——
  `test/liquid_scope_guard_test.dart` 的名单**不变**。
- **界面层不许写数值字面量**（`test/design_tokens_test.dart` 守门）：`Duration(milliseconds:)`
  / `fontSize:` / `Color(0x…)` / 落在 4px 栅格外的间距。要新常量就进
  `core/design_tokens.dart`，并补上令牌自检那条。
- **端头半径 = `AppTokens.radiusM`（16）**；**带子的高度不形变**（spec §4.5：渠道里的水）。
- **交互契约一行不改**：长按进多选态、每进一格震一次、松手弹同一个选择层、不跨月、
  空白表方案不入口。**状态仍是吸附到格**（末端淌过去只是观感）。
- 版本 `0.10.17+141` → **`0.10.18+142`**（末位非 0 = 测试版 → 走 `beta` 分支 + `release.ps1`）。
- 验收门槛：`flutter analyze` 干净；`flutter test` 全绿（当前 **746**，只增不减）；
  `flutter test tool/visual/` 全绿（当前 **348**）。
- 一次性探针 `app/tool/probe/range_band_probe_test.dart` **进 Task 5 时删掉**，不进仓库。

## Review Focus

计划里的用例照不到、但真机上一定会遇到的输入，按可能咬人的顺序：

1. **区间正好落在月末**（比如 10/28–11/2 这种「跨月」其实被拦住了，但 10/25–10/31
   会横跨两个行尾）—— 段数与角必须还对得上。
2. **区间整行满**（周日到周六恰好一周）：那一行的段两端都**不该**是圆的（它两头都连着下一行）。
3. **往回拖**（手指从起点往回走）：动的那一头换成起端，圆角与「挤字」都跟着换边。
4. **长按落在周标题 / 空白格上**：不进多选态（既有行为），此时**一层带子都不许画**。
5. **拖选时系统把手指取消**（来电话）：带子与范围淡染都要收干净（既有 `_clearGestureState`）。

每条都要在对应任务里落成一条用例 —— 见 Task 2 / Task 4。

---

### Task 1: 共享件 —— 把「轮廓」这一维抽出来（不改任何行为）

**Files:**
- Modify: `app/lib/core/glass/liquid_lens.dart`
- Test: `app/test/liquid_lens_test.dart`

**Interfaces:**
- Produces:
  ```dart
  /// 一块玻璃的**轮廓**：四层光谱与浮起阴影只认它，不认这个轮廓是怎么来的。
  abstract class LiquidLensOutline {
    /// 画布坐标里的轮廓（已含 24px 画布余量那个 `origin` 偏移）。
    Path paintPath(Offset origin);

    /// 「容器那条边被折进来」那一圈线（画布坐标）。`null` = 这一族没有这回事。
    Path? refractedEdgePath(Offset origin);

    /// `shouldRepaint` 用的**值可比**指纹（Dart 记录：结构相等）。
    Object get outlineStamp;

    double get motion;
    double get motionAngleDeg;
    double get rimScale;
  }
  ```
  `class LiquidLensShape implements LiquidLensOutline`（`outlineStamp` =
  `(centerX, width, height, leftRadius, rightRadius)` —— **就是今天三个 `shouldRepaint`
  比的那五个字段，一个不多一个不少**）。
  `LiquidLens({required LiquidLensOutline outline, ...})`（字段名从 `shape` 改成 `outline`）。
- 为什么要有 `outlineStamp`：`Path` 没有值相等，轮廓对象又每帧新建 —— 拿对象比会让
  「静止时也每帧重画一遍」。今天的五个字段刚好就是「几何变了没」的充分判据。

- [ ] **Step 1: 写会红的用例 —— 一个「外来的轮廓」也能穿这套材质**

```dart
// app/test/liquid_lens_test.dart（新 group：'轮廓这一维'）
testWidgets('外来的轮廓也能穿这套材质：填充跟着它、彩边贴着它', (tester) async {
  // 今天四层光谱全绑死在 LiquidLensShape.toPath() 上 —— 这个 group 钉的是
  // 「轮廓可以是别的东西」（拖选那条水带就是第二个实现）。
  final Rect r = Rect.fromLTWH(40, 30, 160, 60);
  final List<int> shot = await shotOutlineLens(tester, outline: _RectOutline(r));
  expect(brightestInside(shot, r.center), greaterThan(brightestOutside(shot, r)),
      reason: '填充没跟着外来轮廓走');
  expect(nonTransparentOn(shot, r.topLeft + const Offset(0.5, 30)).isNotEmpty, isTrue,
      reason: '彩边没贴在外来轮廓上');
});
```

（`shotOutlineLens` 是 `shotLens` 的姊妹：同一个画布、同一套取像，只是把 `shape` 换成
传进来的 `outline`；`_RectOutline` 是测试里那个最小实现，`motion: 1`、`motionAngleDeg: 0`、
`rimScale: 1`。）

- [ ] **Step 2: 跑它，看着它红**

Run: `flutter test test/liquid_lens_test.dart --plain-name "外来的轮廓"`
Expected: 编译失败 —— `LiquidLensOutline` / `LiquidLens.outline` 不存在。

- [ ] **Step 3: 实现这一抽**

在 `liquid_lens.dart` 里：
1. 新增 `LiquidLensOutline`（上面的接口）。
2. `LiquidLensShape implements LiquidLensOutline`，并加：
   ```dart
   @override
   Path paintPath(Offset origin) => toPath().shift(origin);

   @override
   Object get outlineStamp =>
       (centerX, width, height, leftRadius, rightRadius);

   /// 今天那圈折线：两条子路径（胶囊上下沿各一条）合在一个 `Path` 里。
   @override
   Path? refractedEdgePath(Offset origin) { ... }   // 从 _LensBodyPainter 搬过来
   ```
3. `LiquidLens` 的字段 `shape` → `outline`（类型换成接口），五处 `_lensPath(shape, origin)`
   改成 `outline.paintPath(origin)`，然后**删掉** `_lensPath`（它是那五处的唯一实现）。
4. 四个 painter 与 clipper 的字段类型换成接口；它们的 `shouldRepaint` /
   `shouldReclip` 里那五条 `old.shape.xxx != shape.xxx` 收成一条
   `old.outline.outlineStamp != outline.outlineStamp`，`motion` / `motionAngleDeg`
   那两条照旧比接口上的同名字段。
5. `_paintRefractedCapsuleEdge` 改成画 `outline.refractedEdgePath(origin)`（`null` 就返回）——
   **路径的建法一字不动**（`refractedCapsuleEdge(shape)` 与 `shape.capsuleH` /
   `shape.centerX` 全部搬进 `LiquidLensShape.refractedEdgePath` 里）。

⚠️ 三个 `shouldRepaint` 今天比的字段**不完全一样**（`_LensEdgePainter` 比三个、
`_LensClipper` / `_LensShadowPainter` / `_LensBodyPainter` 比五个）—— 统一成
`outlineStamp` 之后，前者的重画条件**变宽**（多比了半径）。这是**允许**的：宽了只意味着
「偶尔多画一帧」，而收窄才会留下「该画没画」的坑。**别为了「与今天逐字一样」把它拆回去。**

- [ ] **Step 4: 跑全套，确认没退化**

Run: `flutter test test/liquid_lens_test.dart`
Expected: 全绿（含新 group）。

- [ ] **Step 5: 逐像素比一次 —— 四个既有调用点一处都不许变**

```bash
flutter test tool/visual/            # 先渲当前这一版
python ../scripts/diff_visual.py app/build/visual/baseline-v01017 app/build/visual \
    --filter home_shell
```
Expected: `00_home_shell*` / `36_home_shell_liquid*` / `42_segment_liquid*` /
`43_switch_liquid*` / `46_switch_drag*` / `47_ringing_liquid*` **逐像素相同**。
（基线是 v0.10.17 那一轮渲的，就在 `app/build/visual/baseline-v01017/`。若它没了，
在 `137a6bf` 上开临时 worktree 重渲一遍再比。）

⚠️ **这一比就是 spec 护栏表里那条「轮廓默认值 = 今天」的可断言形式** ——
`LiquidLensShape` 是唯一的默认实现，它要是被抽歪了一个像素，这六组屏会当场红。
比之前先确认基线那份的 `34_app_info*` 是 v0.10.16 那一版（版本号那几张本来就不同）。

- [ ] **Step 6: Commit**

```bash
git add app/lib/core/glass/liquid_lens.dart app/test/liquid_lens_test.dart
git commit -m "refactor(glass): 把「轮廓」从 LiquidLensShape 里抽成 LiquidLensOutline（四层材质与它解耦）"
```

---

### Task 2: 纯几何 —— `range_band.dart`

**Files:**
- Create: `app/lib/features/calendar/range_band.dart`
- Test: `app/test/range_band_test.dart`

**Interfaces:**
- Consumes: `AppTokens.gapHair`、`AppTokens.radiusM`、`daysBetween`（`domain/shift_rotation.dart`）。
- Produces:
  ```dart
  /// 拖选区间 → **每行一段**（行号 + 该行的起止列，闭区间）。
  /// [from] / [to] 谁前谁后都认（内部归一成正序）。
  List<({int row, int firstCol, int lastCol})> rangeRowRuns({
    required DateTime from,
    required DateTime to,
    required DateTime month,
  });

  /// 每行一段 → 一条带子。`tip…` 是**会动的那一端**的连续位置（列可为小数）。
  Path rangeBandPath({
    required List<({int row, int firstCol, int lastCol})> runs,
    required double cellW,
    required double cellH,
    required double hPad,
    required double weekdayH,
    required double inset,
    required double endRadius,
    required bool movingEnd,       // true = 动的是终点（右）；false = 动的是起点（左）
    double? tipCol,                // 那一端的连续列（含鼓出），null = 按整格
  });
  ```
- 几何逐条写在 spec §4.2 / §4.3：
  - 段的矩形 = `left/hPad + firstCol·cellW + inset` …（四边见 spec §4.2），
    **于是相邻两格之间那 4px 的缝被这一段盖住**。
  - 角：`runs.first` 的左两角、`runs.last` 的右两角 = `endRadius`；其余（跨行那两头）= 0。
  - `tipCol` 给的是**小数**：`movingEnd` 为真时它替换**最后一段**的右缘，
    为假时替换**第一段**的左缘（`left = tipCol·cellW + hPad + inset`，右缘同理 − inset）。

- [ ] **Step 1: 写会红的用例**

```dart
// app/test/range_band_test.dart
const double cellW = 56.5714, cellH = 85, hPad = 12, weekdayH = 26, inset = 2;
const double endR = 16;

List<({int row, int firstCol, int lastCol})> runs(DateTime a, DateTime b) =>
    rangeRowRuns(from: a, to: b, month: DateTime(2026, 10));

test('跨周：按行拆成两段，各行的起止列都对', () {
  // 2026-10-01 是周四（leading = 3）；10/1 在第 0 行第 3 列
  expect(runs(DateTime(2026, 10, 2), DateTime(2026, 10, 12)),
      <({int row, int firstCol, int lastCol})>[
        (row: 0, firstCol: 4, lastCol: 6),
        (row: 1, firstCol: 0, lastCol: 4),
      ]);
});

test('同周内：一段', () { ... (row: 0, firstCol: 3, lastCol: 5) ... });

test('单天：一段一格', () { ... (row: 0, firstCol: 3, lastCol: 3) ... });

test('跨三行：中间那行是**整行满**', () {
  // 10/2（第 0 行第 4 列）→ 10/20（第 3 行第 1 列）
  ... (row: 1, firstCol: 0, lastCol: 6) ... (row: 2, firstCol: 0, lastCol: 6) ...
});

test('起点终点倒过来也认（内部归一成正序）', () { ... 与正序逐值相同 ... });

test('同一行内是一整块：两格之间那道缝也说「在里面」', () {
  // 这是这一轮的核心断言 —— 格与格之间那 4px 的缝**不属于任何一格**，
  // 逐格各画一块的写法在这一条上必红（那正是今天的样子）。
  final Path p = rangeBandPath(runs: runs(DateTime(2026, 10, 2), DateTime(2026, 10, 5)),
      cellW: cellW, cellH: cellH, hPad: hPad, weekdayH: weekdayH,
      inset: inset, endRadius: endR, movingEnd: true);
  final double gapX = hPad + 5 * cellW;               // 第 4 格与第 5 格之间那条缝
  expect(p.contains(Offset(gapX, weekdayH + cellH / 2)), isTrue,
      reason: '缝还是空的 —— 那还是「一排小色块」，不是一条带子');
});

test('月末那一行是残行（10/26–10/31 只占 6 列）也照拆', () {
  expect(runs(DateTime(2026, 10, 27), DateTime(2026, 10, 30)),
      <({int row, int firstCol, int lastCol})>[(row: 4, firstCol: 1, lastCol: 4)]);
});
```

```dart
test('四种角：两个真端头圆、跨行两头平', () {
  final Path p = rangeBandPath(runs: runs(DateTime(2026, 10, 2), DateTime(2026, 10, 12)),
      cellW: cellW, cellH: cellH, hPad: hPad, weekdayH: weekdayH,
      inset: inset, endRadius: endR, movingEnd: true);
  // 用 computeMetrics 拿长度不方便，直接比几个探针点的内/外：
  // 起点那一侧左缘往外 1px 处应当**在路径外**（圆角切掉的角），
  // 而贴左边中点往内 1px 应当**在路径内**。
  final Rect r0 = bandRect(row: 0, firstCol: 4, lastCol: 6);
  expect(p.contains(Offset(r0.left - 1, r0.center.dy)), isTrue);
  expect(p.contains(Offset(r0.left + 1, r0.top + 1)), isFalse); // 角被圆掉了
  expect(p.contains(Offset(r0.right + 1, r0.top + 1)), isTrue); // 跨行那侧是方角
});

test('同周内：两端都圆', () { ... 左缘角在外、右缘角也在外 ... });

test('跨行两头切平：两段的缝里没有空隙', () {
  // 第 0 行段的**右缘**与第 1 行段的**左缘**之间不允许出现透明的横带
  // （取两段之间那条水平线上的一排探针，全部 p.contains）。
});

test('末端是连续的：给一个小数 col，该段的边缘就跟着走', () {
  final Path a = rangeBandPath(..., movingEnd: true, tipCol: 2.0);
  final Path b = rangeBandPath(..., movingEnd: true, tipCol: 2.6);
  expect(b.getBounds().right, greaterThan(a.getBounds().right + cellW * 0.5));
  expect(runs(b).length, runs(a).length, reason: '同一行内不该多出一段');
});

test('往回拖：动的那一头换成起端', () {
  final Path p = rangeBandPath(..., movingEnd: false, tipCol: 1.5);
  expect(p.getBounds().left, closeTo(hPad + 1.5 * cellW + inset, 0.01));
});
```

- [ ] **Step 2: 跑它，看着它红**

Run: `flutter test test/range_band_test.dart`
Expected: 编译失败 —— `range_band.dart` 还不存在。

- [ ] **Step 3: 实现 `range_band.dart`**

`rangeRowRuns`：按 `slot = leading + day - 1` 逐天分组，取每行 min/max 列
（`leading`/`daysInMonth` 由 `month` 现算，与 `calendar_screen.dart` 的 `_leading` /
`_daysInMonth` 同一个算式 —— **两处必须同源**，Task 4 里那条集成用例顺带钉它）。
`rangeBandPath`：每段一个 `RRect.fromRectAndCorners`（四种角见上），
`movingEnd` 那一侧的那一段用 `tipCol` 覆盖该侧边缘。

- [ ] **Step 4: 跑它，看着它绿**

Run: `flutter test test/range_band_test.dart`
Expected: PASS（8 条）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/calendar/range_band.dart app/test/range_band_test.dart
git commit -m "feat(calendar): 拖选水带的几何（区间→每行一段；两个真端头圆、跨行两头平）"
```

---

### Task 3: 那枚水带的 widget —— `calendar_range_band.dart`

**Files:**
- Create: `app/lib/features/calendar/calendar_range_band.dart`
- Test: `app/test/calendar_range_band_test.dart`

**Interfaces:**
- Consumes: `LiquidLens`（Task 1 的 `outline` 参数）、`rangeRowRuns` / `rangeBandPath`（Task 2）、
  `LiquidLensSpring`、`lensVelocityStep`、`spectralSweepRestAnchor`。
- Produces:
  ```dart
  class CalendarRangeBand extends StatefulWidget {
    const CalendarRangeBand({
      super.key,
      required this.size,          // 网格盒（含 _hPad × _weekdayH 的偏移空间）
      required this.cellW,
      required this.cellH,
      required this.hPad,
      required this.weekdayH,
      required this.runs,          // 吸附到格的那几段（Task 2）
      required this.movingEnd,     // true = 动的是终点
      required this.tipCell,       // 吸附到格的那一列（**整数**）
      required this.accent,
      required this.isDark,
    });

    /// 末端鼓出的上限（px）。满速时末端往前多探这么多。
    static const double maxBulge = 8;
    /// 形变饱和的速度门（px/s）。与那枚块同一个数（格子宽一样）。
    static const double velocityRef = 400;
    static const double protrude = 6;
    static const double liftWidth = 2 * protrude;
  }
  ```
- 内部四件事（都关在这个 widget 里）：
  1. **升程**：按下 0 → 1（Lift / Unlift 两条弹簧，借 `CalendarLens` 那套 token），
     长按那一刻整条漫上来。
  2. **末端**：一条 `LiquidLensSpring` 追 `tipCell`（ω/ζ 借 `AppTokens.lensSlideOmega/Zeta`），
     每帧算出连续列；**速度用帧间差分 ÷ 真实帧间隔**（`lensVelocityStep`），
     这就是彩边的门与方向。
  3. **鼓出**：`bulge = clamp(|速度| / velocityRef, 0, 1) * maxBulge`，**过一条弹簧**
     （借 `lensStretchOmega/Zeta`）再作为 `rangeBandPath` 的 `tipCol` 喂进去（`tipPos + bulge / cellW`）。
  4. **光**：`motionAngleDeg` = 末端速度方向（`atan2`），门以下保持上一次的方向；
     `motion` 走亮起 / 熄灭两条弹簧（与那枚块同一套 token）。
- 画法：`Positioned.fill(child: LiquidLens(outline: _BandOutline(...), lift: _lift.value,
  fill: [accent 0.22, accent 0.10], showRefractedEdge: false, isDark: …, accent: …))`
  ＋ 上面压一层 2px 主色描边（与 `CalendarLens` 的 `_LensStrokePainter` 同一个写法）。
  `_BandOutline` 实现 `LiquidLensOutline`：`paintPath(origin)` = `rangeBandPath(...).shift(origin)`，
  `refractedEdgePath` 返回 `null`，`outlineStamp` = `(runs 的列表 + 这一帧的连续末端 tipPos)`，
  `rimScale = (cellH - 2 * inset) / AppTokens.lensRimRefCapsuleH`。
- **静止就把 ticker 停掉**：判据要把升程、末端、鼓出、光**四条弹簧全列上**
  （漏一条就是「彩边冻在屏幕上」或「`pumpAndSettle` 永远等不到停」——日历页 v0.9.8 的老账）。

- [ ] **Step 1: 写会红的用例**

```dart
// app/test/calendar_range_band_test.dart
// 一律走几何与帧调度，不拿光栅亮度当判据（那枚块压在白卡上，亮度差被底色吃掉）。
testWidgets('末端沿运动方向鼓出去，但**高度不变**', (tester) async {
  // ⚠️ 鼓出**没法从路径包围盒里抠出来**：末端一边淌一边鼓，包围盒里两件事叠在一起。
  // 所以判据读 `outlineStamp`（那一帧的几何指纹：段 + 连续末端 + 鼓出量）——
  // 它就是这一帧画出来的东西的同源数据，不是另加一个测试钩子。
  await mount(tester, tipCell: 3);
  await tester.pumpAndSettle();
  expect(bulge(tester), closeTo(0, 0.01), reason: '静止时不该有鼓出');
  expect(bandBounds(tester).height, closeTo(cellH - 2 * inset, 0.01));

  for (int i = 0; i < 4; i++) {       // 3 → 4 → 5 → 6，每帧喂一格
    await mount(tester, tipCell: 3 + i);
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(bulge(tester), greaterThan(1),
      reason: '末端没有沿运动方向鼓出去（没接上 / 门太大）');
  expect(bandBounds(tester).height, closeTo(cellH - 2 * inset, 0.01),
      reason: '带子高度动了 —— 它是渠道里的水，一变形就会露出格子的上下沿（spec §4.5）');
});

testWidgets('彩边的亮峰跟着末端方向（往右 0°、往左 180°）', (tester) async { ... });

testWidgets('末端是**淌**过去的：给它一个新目标，中途停在两点之间', (tester) async { ... });

testWidgets('静止之后没有在跑的 ticker', (tester) async {
  await mount(tester, tipCell: 3);
  await tester.pumpAndSettle();
  expect(tester.binding.hasScheduledFrame, isFalse);
});
```

- [ ] **Step 2: 跑它，看着它红**

Run: `flutter test test/calendar_range_band_test.dart`
Expected: 编译失败（文件还不存在）。

- [ ] **Step 3: 实现**

- [ ] **Step 4: 跑它，看着它绿**

Run: `flutter test test/calendar_range_band_test.dart`
Expected: PASS（4 条）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/calendar/calendar_range_band.dart app/test/calendar_range_band_test.dart
git commit -m "feat(calendar): 拖选水带那枚 widget（漫上来 / 末端淌过去 / 沿运动方向鼓出）"
```

---

### Task 4: 接进日历 —— 两棵树 + 挤压场

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Test: `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: `CalendarRangeBand`（Task 3）、`rangeRowRuns`（Task 2）。
- 调用点只有两处：
  1. `_buildGrid` 里那个 `Stack`：网格 `Column` **之后**、那枚选中块**之前**加
     `if (showBand && liquidGlassActive.value) Positioned.fill(child: CalendarRangeBand(...))`。
     `showBand = _rangeAnchor != null && _rangeFocus != null`。
  2. `lensCenter`：液态档且在多选态时，取**流动那一端**那一格的中心
     （`_rangeFocus` 所在格 —— 往回拖时它就是起端，因为锚点固定、动的是 focus）。

- [ ] **Step 1: 写会红的用例**

```dart
// app/test/calendar_screen_test.dart（新 group：'液态档那条水带'）
/// 长按第 [from] 天、拖到第 [to] 天（可再拖 [extraCells] 格，把末端停在两格之间）。
/// **不松手** —— 松手就弹选择层，带子也没了。
Future<void> longPressDrag(WidgetTester tester,
    {required int from, required int to, double extraCells = 0}) async { ... }

testWidgets('液态档：多选态不画逐格淡染，改用一枚带子', (tester) async {
  await _pumpCalendar(tester, 'day_night_rest_rest', liquid: true);
  await longPressDrag(tester, from: 8, to: 15);          // 跨周那一段
  expect(find.byKey(const ValueKey('day-range-10')), findsNothing,
      reason: '液态档还在逐格画淡染 —— 那就不叫「连成一条」了');
  expect(find.byType(CalendarRangeBand), findsOneWidget);
});

testWidgets('标准档：还是逐格淡染（对照组，一个字没改）', (tester) async {
  await _pumpCalendar(tester, 'day_night_rest_rest');
  await longPressDrag(tester, from: 8, to: 15);
  expect(find.byKey(const ValueKey('day-range-10')), findsOneWidget);
  expect(find.byType(CalendarRangeBand), findsNothing);
});

testWidgets('只挤**流动那一端**：带子内部那些格不套 Transform', (tester) async {
  await _pumpCalendar(tester, 'day_night_rest_rest', liquid: true);
  // ⚠️ 要拖到**两格之间**再取样：挤压场只够到一格的半径（t≈2.15 就出局），
  // 末端停在格正中时连它自己那一格都不套 Transform（t≈0）。既有的
  // 「挤字只变换绘制」那条也是这么拖的（半格）。
  await longPressDrag(tester, from: 8, to: 15, extraCells: 0.5);
  expect(warped(tester, day: 15) || warped(tester, day: 16), isTrue,
      reason: '流动那一端旁边那一格没被挤 —— 挤压场没跟着末端走');
  expect(warped(tester, day: 10), isFalse,
      reason: '带子内部（已经圈住的日子）也被挤了 —— spec §4.5：那里面不该动');
});

testWidgets('长按落在周标题 / 空白格：一层带子都不画', (tester) async { ... });

testWidgets('拖选被系统取消：带子与范围淡染一起收干净', (tester) async {
  // 借既有的 `_clearGestureState` 路径（长按开始 → 系统取消）
  expect(find.byType(CalendarRangeBand), findsNothing);
});

testWidgets('松手之后静止：没有待处理的帧', (tester) async {
  ... await tester.pumpAndSettle();
  expect(tester.binding.hasScheduledFrame, isFalse);
});
```

- [ ] **Step 2: 跑它，看着它红**

Run: `flutter test test/calendar_screen_test.dart --plain-name "水带"`
Expected: 前三条与末条 FAIL（`CalendarRangeBand` 不存在 / 液态档还在逐格淡染）。

- [ ] **Step 3: 接线**

- [ ] **Step 4: 跑它，看着它绿**

Run: `flutter test test/calendar_screen_test.dart`
Expected: PASS（含既有 76 条）。

- [ ] **Step 5: 全套 + 逐像素比**

```bash
flutter test                    # 全绿（应 > 746）
flutter test tool/visual/ && python ../scripts/diff_visual.py \
    app/build/visual/baseline-v01017 app/build/visual
```
Expected: 只有 `34_app_info_*`（版本号，Task 5 才会变）、`08_ringing_*`（时钟跳字）
与**带子的屏**有差异；**标准档一张都不许变**。

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_screen_test.dart
git commit -m "feat(calendar): 液态档的拖选换成那枚水带（标准档仍是逐格淡染）"
```

---

### Task 5: 工装（一屏 + 一条动图）+ 基线比对 + 删探针

**Files:**
- Modify: `app/tool/visual/render_screens_test.dart`、`app/tool/gif/render_gifs_test.dart`
- Delete: `app/tool/probe/range_band_probe_test.dart`（以及 `app/build/probe/`）

**Interfaces:** 只消费 Task 4 的界面。

- [ ] **Step 1: 新增一屏 `52_calendar_range_band`**

与 `51_calendar_lens_flight` 同一个写法（`extraPrefs: {'liquidGlass': true}`，
`settleAfterCapture: false`）：`beforeCapture` 里长按某一格 → 拖到跨周的第十天 →
**别松手**（松手就弹选择层，带子也没了）。捕获那一刻手指仍在屏幕上。

- [ ] **Step 2: 出一条 GIF**

`tool/gif/` 加「日历 · 长按拖选一条水带 · light/dark」：`count: 46`、`step: 16ms`、
`onFrame` 里用 `startGesture` + 每帧 `moveBy` 走 10 格（跨周），最后松手 ——
**前 12 帧按住不动**（拍「漫上来」），中段拖动（拍「末端淌 + 鼓出 + 彩边」），
`i == 40` 松手（拍落回去）。

- [ ] **Step 3: 渲一版看图**

```bash
flutter test tool/gif/render_gifs_test.dart --plain-name "水带"
python scripts/make_gif.py --prefix calendar_band_light_ --out work/gif/cal-band-light.gif \
    --crop 0,210,840,1100 --width 740 --fps 62 --colors 256
```
Expected: 出图；**用眼睛看**三件事 —— 缝真的被盖住了、跨周那两头是平的、末端比身体鼓一点。

- [ ] **Step 4: 删探针**

```bash
rm -rf app/tool/probe app/build/probe
git status --short          # 探针不该出现在仓库里
```

- [ ] **Step 5: Commit**

```bash
git add app/tool/visual/render_screens_test.dart app/tool/gif/render_gifs_test.dart
git commit -m "test(visual): 拖选水带进工装（一屏 + 一条动图）；删掉一次性探针"
```

---

### Task 6: 收尾 —— 版本 / 更新日志 / AGENTS / 发版

**Files:**
- Modify: `app/pubspec.yaml`、`app/lib/core/app_info.dart`、
  `app/lib/features/profile/app_dialogs.dart`、`AGENTS.md`
- Create: `tools/gh/release-notes-v0.10.18.md`

- [ ] **Step 1: 版本号两处同步**

`app/pubspec.yaml` 的 `version: 0.10.17+141` → `0.10.18+142`；
`app/lib/core/app_info.dart` 的 `appVersion = '0.10.17'` → `'0.10.18'`。
Run: `flutter test test/app_info_test.dart`
Expected: PASS（两处不一致会当场红）。

- [ ] **Step 2: 更新日志 prepend 0.10.18（窗口仍 10 条、中英同步）**

`_changelogZh` / `_changelogEn` 各 prepend 一条、删掉最旧的（`v0.10.8`）。
**纯文本渲染，不许写 markdown 标记。**
Run: `flutter test test/changelog_window_test.dart`
Expected: PASS（条数、版本递减、中英一致、无 markdown 四条）。

- [ ] **Step 3: AGENTS.md**

- 「版本号规则」那条历史链尾加 `→ 0.10.18(+142) 测试版（拖选那条水带…）`；
- 「最近改动」加一条 v0.10.18：形状 A 与 B/C 被否的理由、轮廓那一抽、
  「末端淌过去但状态仍是吸附到格」、以及**这一轮踩到的坑**（要真踩到了才写）；
- 「验收标准」那条的数字改成实测值。

- [ ] **Step 4: 发版**

```bash
git add -A && git commit -m "chore(release): v0.10.18（拖选那条水带）"
git tag v0.10.18 && git push origin beta && git push origin v0.10.18
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/release.ps1 -SkipConfirm
curl -s https://raw.githubusercontent.com/Alec-WangLi/DaoBanAssistantPro/main/latest.json
```
Expected: Release 页出现 v0.10.18（预发布）；`latest.json` 的 `prerelease.version == "0.10.18"`；
`dist/倒班助手Pro-v0.10.18.apk` 存在（跑完 `aapt2 dump badging` 核 versionCode 142）。

---

## 收尾（两个任务之外的固定动作）

- 全套 `flutter test` + `flutter test tool/visual/` + `flutter analyze` 各跑一遍，数字进 AGENTS。
- **逐张比基线**：`python scripts/diff_visual.py app/build/visual/baseline-v01017 app/build/visual`，
  差异逐张解释（标准档一张都不许变）。
- 出图给用户看（那屏 + 那条 GIF）。
- 独立审查（全新上下文跑整个分支）——抓出的 Critical / Important 一轮修完，Minor 记账。
