# 桌面小组件胶囊不重合 + 周视图同步 + 按月标签去省略号 · 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让月历格与周条的班次胶囊**按简称的实际文字宽度**画（左右留出与 App 一致的间隙），把周视图与月历的「今天」三处对齐，并让编辑排班里「每月第 N 天起」不再出现省略号。

**Architecture:** 桌面侧不需要新协议、不需要新依赖：胶囊位图的宽度改由 `android.graphics.Paint.measureText()` 在**本进程**用真 Android 字体现量（绕开 `RemoteViews` 量不到文字宽、API 31 才能改容器尺寸这两条限制），布局里把「位图驱动尺寸」翻成「文字驱动尺寸、位图贴上去」。周条照 v0.11.23 月历那一套逐条搬。编辑排班那处是把标签列从硬压的 `Expanded(flex:3)` 放回自然宽度。

**Tech Stack:** Flutter/Dart（编辑排班）+ Android Kotlin（`RemoteViews` / `AppWidget`，minSdk 26）。

**Spec:** `docs/superpowers/specs/2026-10-16-widget-chip-fit-and-week-sync-design.md`

## Global Constraints

- **minSdk 26**：`RemoteViews.setViewLayoutWidth/Height` 是 API 31 才有的，**不许用**（这正是本轮改用 `measureText` 定宽的原因）。
- **不引入任何新依赖**；**不动快照协议**（仍是 v2，本轮不新增任何字段）。
- **Kotlin 在这个仓库里没有可跑的测试目标**：Kotlin 的改动靠 ① Dart 侧扫源码的护栏 ② 真机 adb 出图，两条都不可省。
- **桌面小组件的用户可见文案必须全部来自 Dart 侧快照** —— Kotlin 里**不许出现用户可见的中文字面量**（全仓唯一例外是 `AlarmLog` 的日志串）。
- **每一处往容器 `addView` 之前必须先 `removeAllViews`**（`RemoteViews` 的 `reapply` 不清子视图，漏了就是「内容一变就重影」）。
- **不要跑 `dart format`**（工具链是新版格式化器，一跑就是几百行无关 diff）；只跑 `flutter analyze`。
- **版本号**：`X.Y` 由用户定，AI 只改末位 `Z` 与 `build`；`pubspec.yaml` 与 `lib/core/app_info.dart` 两处必须同步（`app_info_test.dart` 盯着）。
- **验收基线**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿且**只增不减**（当前 **1085** 条）；`flutter test tool/visual/` 全绿 + 逐张比基线，差异逐条解释。
- **分支**：测试版一律在 `beta` 上做与提交。
- 构建前先 `. C:\...\shiftassistant\tools\build-env.ps1`；真机 `toolchain/android-sdk/platform-tools/adb.exe`（设备 `7288a9b0`，1200×2608 @480dpi = **3×**）。

## Review Focus

写测试时逐条对照，每条都要落到某个任务的用例里：

1. **两字简称才是最宽的一档**（「大休」「上夜」）—— 量「胶囊不重合」必须拿它当上界。单字简称（「白」「夜」）天然只有约一半宽，拿它量会误判通过、漏掉真正贴边的那档。
2. **浅主色（teal / orange）下「今天」那格/那列的字**：块是半透明的浅底，字若还走 `onSolidInk` 会给白字、读不出来，而且是**静默**的（默认那颗蓝是对的）。
3. **没有班次的那一格/那一列**（空白表方案，`hasShift == false`）：胶囊两个方向都要设 GONE；今天那一列此时只剩块 + 周几 + 日数字，三者仍要正常（不能因为少了胶囊就错位或留一条空白）。
4. **窄窗（200×400）下的按月行**：标签放回自然宽度之后，`showTime` 判据要拿到**真实的标签宽**，否则会误判成「放得下」、右侧那个不带 `Flexible` 的裸 `Text(timeText)` 横向溢出。
5. **相邻月的格子**（月历 42 天里不属于当月的那些）：日数走 muted、**胶囊照画**，宽度同样按文字走 —— 别只照顾当月那几格。

---

### Task 1: 月历胶囊按文字宽（消掉与格子重合）

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`（新增 `chipWidthPx`；改 `monthCard` 里 `pillW` 的算法）
- Modify: `app/android/app/src/main/res/layout/widget_month_cell.xml`（胶囊那两层角色对调）
- Test: `app/test/widget_cell_block_guard_test.dart`（追加）

**Interfaces:**
- Consumes: 既有的 `dpToPx(context, dp)`（`WidgetRenderer.kt:64`）、`cardScale(slotDp)`（`:115`）、`WidgetChip.tintedChip(color, wPx, hPx)`
- Produces: `private fun chipWidthPx(context: Context, abbr: String, textSizeDp: Float): Int` —— 返回**位图宽度（像素）** = 该简称在 `textSizeDp` 下的排版宽度 + 两侧各 4dp 内边距，**下限 12dp**（防空串量出 0）。Task 2 复用同一个函数。

- [ ] **Step 1: 改既有护栏 + 加新护栏（先看着它红）**

⚠️ **`widget_cell_block_guard_test.dart` 里那条「月历胶囊的尺寸由**位图**驱动，不是布局里写死的 40×18dp」测的正是本轮要反转的东西** —— 它断言布局里 ImageView 那一段含 `wrap_content`、且渲染侧有 `pillW`。本轮之后 ImageView 变 `match_parent`、`pillW` 没了，这条会红。**把它改写成新的事实**（而不是删掉）：胶囊的两层里，**TextView 是宽度驱动者**（`wrap_content` + `layout_gravity="center"` + `paddingHorizontal="4dp"`），ImageView 是 `match_parent`；渲染侧的宽度来自 `chipWidthPx`。

在同文件末尾**另加**一条：

```dart
test('胶囊位图宽度来自**文字现量**，不是写死的比例', () {
  final kt = _read(
      'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
  expect(kt.contains('measureText'), true,
      reason: '胶囊宽度没按简称现量 —— 定值宽度在格子小的时候会顶满格宽，'
          '与格子重合（实测占 95.5%，App 只有 81%）');

  final monthCard = kt.substring(
    kt.indexOf('private fun monthCard('),
    kt.indexOf('private fun stripCellPx('),
  );
  expect(monthCard.contains('chipWidthPx'), true,
      reason: 'monthCard 还在用写死的胶囊宽度');
  expect(monthCard.contains('40f * cellScale'), false,
      reason: '月历胶囊宽度还是「40dp × 缩放」那个定值');
});
```

- [ ] **Step 2: 跑，确认红**

Run: `flutter test test/widget_cell_block_guard_test.dart --plain-name "胶囊位图宽度"`
Expected: **FAIL** —— `measureText` / `chipWidthPx` 都还不存在。

- [ ] **Step 3: 实现 `chipWidthPx`**

在 `WidgetRenderer.kt` 的 `dpToPx` 下面、`cardScale` 附近加：

```kotlin
/**
 * 胶囊位图的**宽度**：按简称在 [textSizeDp] 下的实际排版宽度现量，两侧各留 4dp。
 *
 * 为什么现量而不是定值：定值（v0.11.23 的 `40dp × 缩放`）在格子小的时候会把胶囊
 * 顶到格边 —— 真机上量到占格宽 **95.5%**，而 App 里同一颗只占 **81%**（它走的是
 * `_shiftChip`：`padding: horizontal spaceXs(4) × s` 包着 `FittedBox(Text(cellShift))`，
 * 所以「白」窄、「大休」宽）。用户 2026-10-16：「跟里边班次的胶囊又重合了」。
 *
 * 为什么用 `Paint.measureText` 而不是别的：`RemoteViews` 在**宿主进程**渲染、
 * 量不到文字宽，而能改容器尺寸的 `setViewLayoutWidth` 要 API 31（本仓 minSdk 26）。
 * 本函数跑在**我们自己的进程**里、用的是同一套系统字体，量出来的就是桌面上真正
 * 会画出来的那个宽。实测过与布局里 `TextView` 的测量一致，`fitXY` 再把零头吸收掉。
 *
 * `4dp` 与 App 的 `spaceXs` 同一个数，**有意不乘缩放** —— 布局里
 * `paddingHorizontal` 是固定 dp，两边取同一个值才不会一个宽一个窄。
 */
private fun chipWidthPx(context: Context, abbr: String, textSizeDp: Float): Int {
    val density = context.resources.displayMetrics.density
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = textSizeDp * density }
    val text = paint.measureText(abbr)
    val pad = 4f * density
    return (text + 2 * pad).toInt().coerceAtLeast(dpToPx(context, 12))
}
```

顶部 import 补 `import android.graphics.Paint`。

- [ ] **Step 4: 改 `monthCard` 的 `pillW`**

把这段（约 `WidgetRenderer.kt:706-710`）：

```kotlin
val pillW = (40f * cellScale * cellDensity).toInt().coerceAtLeast(1)
val pillH = (18f * cellScale * cellDensity).toInt().coerceAtLeast(1)
```

改成：

```kotlin
// 宽度**每格各自算**（按该格的简称现量）—— 与 App 一致；高度仍是共用一个。
// LruCache 不会炸：宽度只由 (字号 × 文字宽) 决定，同一次渲染里「白」与「夜」
// 同宽共一张、只有「大休」这类两字的再多一张，一屏仍是屈指可数的几张。
// ⚠️ **别按格子造唯一尺寸**（那才会把 64 条的 LruCache 冲爆）。
val pillH = (18f * cellScale * cellDensity).toInt().coerceAtLeast(1)
val chipTextDp = 12f * cellScale   // = design_tokens.cellShift 12 × 缩放
```

循环里 `WidgetChip.tintedChip(d.color, pillW, pillH)` 改成：

```kotlin
WidgetChip.tintedChip(
    d.color, chipWidthPx(context, d.shiftAbbr, chipTextDp), pillH,
),
```

⚠️ **连带改那条注释**：`if (d.hasShift)` 分支里那句「尺寸恒定（循环外算好的 pillW × pillH）：一格一尺寸会让 `WidgetChip` 的位图缓存失效」现在**只对高度成立**、对宽度是反话 —— 改写成「高度恒定；宽度按各格简称现量（同宽的简称自然共用同一张位图，一屏仍是屈指可数的几张）」。

- [ ] **Step 5: 布局里把两层角色对调**

`widget_month_cell.xml` 的胶囊 `FrameLayout`：`FrameLayout` 保持 `wrap_content × wrap_content`；
- `wg_mc_pill`（ImageView）改成 `match_parent × match_parent`（不再驱动尺寸，改成贴满）；
- `wg_mc_abbr`（TextView）改成 **`wrap_content × wrap_content` + `layout_gravity="center"` + `paddingHorizontal="4dp"`**（它现在是宽度驱动者）。

三处缺一不可：`wrap_content` 让它驱动宽度、`layout_gravity="center"` 让它在比它宽的位图里居中、`paddingHorizontal` 与 Kotlin 侧那 4dp 对齐。把顶部那段旧注释（「位图这一层是尺寸的驱动者」）改写成新的事实。

- [ ] **Step 6: 跑，确认绿**

Run: `flutter test test/widget_cell_block_guard_test.dart`
Expected: PASS（含新加那条）。

- [ ] **Step 7: 真机量「不重合」**

```bash
. tools/build-env.ps1
flutter build apk --release --target-platform android-arm64
toolchain/android-sdk/platform-tools/adb.exe install -r app/build/app/outputs/flutter-apk/app-release.apk
```
打开一次 App（推快照）→ 回桌面 → 翻到月历卡 → `adb exec-out screencap` 截屏。
**判据**：沿胶囊中线扫一格，**用两字简称那格**（如「大休」）量 —— 胶囊宽 ≤ 格宽 × **82%**（改造前 95.5%），左右各能看到一段白卡。浅深两档各一张。

- [ ] **Step 8: Commit**

```bash
git add app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt \
        app/android/app/src/main/res/layout/widget_month_cell.xml \
        app/test/widget_cell_block_guard_test.dart
git commit -m "fix(widget): 月历胶囊宽度按简称现量，不再与格子重合"
```

---

### Task 2: 周条与月历同步（块 / 周标题 / 字色 / 胶囊宽度）

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`（`weekStrip`，约 445-560 行）
- Modify: `app/android/app/src/main/res/layout/widget_strip_cell.xml`（胶囊那两层角色对调，同 Task 1 Step 5）
- Test: `app/test/widget_cell_block_guard_test.dart`（改一条既有断言 + 加一条）

**Interfaces:**
- Consumes: Task 1 的 `chipWidthPx(context, abbr, textSizeDp)`；既有的 `WidgetChip.glassBlock(accent, w, h, radiusPx, strokePx)`、`stripCellPx(context, widgetId)`（返回该列的 `(colW, colH)` 像素尺寸）、`snap.weekdays: List<String>`（顶层，已是单字、按周一起算）
- Produces: 无新符号（只改行为）

- [ ] **Step 1: 改既有护栏 + 加新护栏（先看着它红）**

`widget_cell_block_guard_test.dart` 里那条「月历「今天」那格的字**不许**走 onSolidInk」的下界要改：周条三处也改中性色之后，全文件只剩今日卡药丸那一处。把

```dart
final uses = RegExp(r'onSolidInk\(context, ').allMatches(kt).length;
expect(uses, greaterThanOrEqualTo(4),
    reason: 'onSolidInk 的调用点只剩 $uses 处 —— 周条三处 + 今日卡药丸一处应当凑齐 4 处');
```

改成 `greaterThanOrEqualTo(1)` 并把 reason 改写成「只剩今日卡的『今天』药丸那一处（它仍是白字压实心主色）」。**同一条用例里**再加一段：

```dart
final weekStrip = kt.substring(
  kt.indexOf('private fun weekStrip('),
  kt.indexOf('internal fun monthCovered('),
);
expect(weekStrip.length, greaterThan(500), reason: '没截出 weekStrip —— 护栏自己跟源码对不上了');
expect(weekStrip.contains('onSolidInk(context,'), false,
    reason: '周条今天那列的块也改半透明了，块上字不能走 onSolidInk（浅底上会白字）');
expect(weekStrip.contains('glassBlock'), true, reason: '周条今天那列还是实心块');
expect(weekStrip.contains('snap.weekdays'), true,
    reason: '周标题没换成单字 —— 快照顶层 weekdays 已是单字，与月历表头同一份');
```

- [ ] **Step 2: 跑，确认红**

Run: `flutter test test/widget_cell_block_guard_test.dart`
Expected: **FAIL** —— 周条还在用实心 `block`、还在走 `onSolidInk`、周标题还读 `d.weekday`。

- [ ] **Step 3: 改 `weekStrip` 的四处**

① 块（`isToday` 分支）：`WidgetChip.block(snap.accent, colW, colH, dpToPx(context, 12).toFloat())`
→ `WidgetChip.glassBlock(snap.accent, colW, colH, dpToPx(context, 12).toFloat(), dpToPx(context, 2).toFloat())`。注释改写成「与月历那格同一支、同参数；周条那一列底下没有独立白卡，半透明块直接压在卡自己的近白底上」。

② 周标题文案：`c.setTextViewText(R.id.wg_sc_weekday, d.weekday)`
→ `c.setTextViewText(R.id.wg_sc_weekday, snap.weekdays.getOrNull(col) ?: d.weekday)`。**下标直接对**：`weekdays` 按周一起算、周条 7 列恰好是本周一..本周日。

③ 字色：`wg_sc_weekday` / `wg_sc_day` / `wg_sc_abbr` 三处 `if (isToday) onSolidInk(...) else muted/ink` **全部改成恒 `muted` / `ink` / `ink`**（半透明块是浅底）。

④ 胶囊：`if (isToday) WidgetChip.block(...) else WidgetChip.tintedChip(...)` **整个分支去掉**，恒走 `tintedChip`，宽度用 `chipWidthPx(context, d.shiftAbbr, 10f)`（**周条没有缩放，字号就是布局里那个 10dp** —— v0.11.23 加缩放的是月历，周条从未接 `cardScale`）。

- [ ] **Step 4: 改 `widget_strip_cell.xml`**

与 Task 1 Step 5 逐字同一条改法（三处：`wrap_content` + `layout_gravity="center"` + `paddingHorizontal="4dp"` 给 TextView；`match_parent` 给 ImageView）。

- [ ] **Step 5: 跑，确认绿**

Run: `flutter test test/widget_cell_block_guard_test.dart`
Expected: PASS。

- [ ] **Step 6: 真机三档核**

装包 → 桌面周条卡截图，与月历卡**并排**看：
- 今天那一列是**半透明块**（不是实心）；
- 周标题是**单字**「一 二 … 日」；
- 胶囊窄了、与列边有间隙（同样用**两字简称那一列**量）；
- 浅深两档各一张。
**另核 Review Focus 第 3 条**：空白表方案下（跟随法定节假日）今天那一列只剩块 + 周几 + 日数字，胶囊两个方向都 GONE、不留空白条。这台机的库不是空白表 —— 用编辑排班切一套空白表方案让它当当前方案，看完再切回来。

- [ ] **Step 7: Commit**

```bash
git add app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt \
        app/android/app/src/main/res/layout/widget_strip_cell.xml \
        app/test/widget_cell_block_guard_test.dart
git commit -m "feat(widget): 周条与月历同步（半透明今天块 / 单字周标题 / 胶囊按文字宽）"
```

---

### Task 3: 「每月第 N 天起」不再省略

**Files:**
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`（`_monthRow` 约 1316-1405；`cycleRowFitsTime` 约 2330）
- Test: `app/test/schedule_editor_test.dart`（追加；`_domain` 要能造按月方案）

**Interfaces:**
- Consumes: 既有的 `_textWidth(String, TextStyle)`（`:2306`）、`AppTokens.labelSecondary` / `AppTokens.iconSm` / `AppTokens.spaceXs` / `AppTokens.spaceSm`
- Produces: `bool cycleRowFitsTime({required double rowWidth, required List<String> classNames, required String timeText, required double dayLabelWidth})` —— **新增第 4 个必填参数**；两个调用点各传自己的真实标签宽。

- [ ] **Step 1: 写失败用例**

`schedule_editor_test.dart` 的 `_domain` 加两个参数（默认值保持既有调用点不变）：

```dart
bool monthly = false,
List<MonthlySegment> monthSegments = const [],
```
并透传进 `ShiftSchedule(monthly: monthly, monthlySegments: monthSegments, ...)`。

新用例：

```dart
testWidgets('按月：最长的「每月第 N 天起」完整显示，不省略', (tester) async {
  // 用户 2026-10-16：「编辑排班按月切法下面，『每月从第几天起』出现了省略号」。
  // 标签列原先被 `Expanded(flex: 3)` 硬压到约 3/8 宽，而右侧胶囊列是横向滚动
  // 列表、根本不缺那点宽度。
  await _pumpEditor(
    tester,
    _domain(
      monthly: true,
      monthSegments: const [
        MonthlySegment(startDay: 1, classIndex: 0),
        MonthlySegment(startDay: 31, classIndex: 1), // 最长的那一档
      ],
    ),
    size: const Size(360, 4600), // 真机竖屏宽度：360dp
  );

  final label = find.text(L10n.monthlyFromDay(31));
  expect(label, findsOneWidget);
  final para = tester.renderObject<RenderParagraph>(label);
  expect(para.didExceedMaxLines, false,
      reason: '「每月第 31 天起」被截断了 —— 这一条量的就是用户看到的那处省略号');
});
```

（`RenderParagraph` 来自 `package:flutter/rendering.dart`，需要 import。）

- [ ] **Step 2: 跑，确认红**

Run: `flutter test test/schedule_editor_test.dart --plain-name "按月"`
Expected: **FAIL** —— `didExceedMaxLines` 为 true（或 `RenderParagraph` 找不到，说明文本被换行/裁掉）。**先确认它红**，红的形态记进提交信息。

- [ ] **Step 3: 标签列放回自然宽度**

`_monthRow` 里把

```dart
Expanded(
  flex: 3,
  child: GlassPressable(...),
),
```

改成不再包 `Expanded`（`GlassPressable` 直接作为 Row 的子件，按内容自然宽），并把里层那个 `Flexible(child: Text(..., overflow: TextOverflow.ellipsis))` 的 `Flexible` 与 `overflow` **都去掉**（只剩 `maxLines: 1`）。右侧胶囊那列从 `Expanded(flex: 5, ...)` 改成 `Expanded(...)`（标签不 flex 之后它已经是唯一的弹性子件，`flex: 5` 是句误导）。

- [ ] **Step 4: 给 `cycleRowFitsTime` 加第 4 个参数**

签名加 `required double dayLabelWidth,`，函数体里把 `_dayLabelWidth` 换成它。两个调用点：
- `_cycleRow`（`:1559`）传 `dayLabelWidth: _dayLabelWidth`（56，精确不变）；
- `_monthRow`（`:1329`）传实测宽：

```dart
// 标签列现在是自然宽度，不再等于 _dayLabelWidth(56)。按真实排版量，
// 否则 showTime 会以为前面只占 56dp、误判「放得下时间」—— 而右侧那个
// `Text(timeText)` 不带 Flexible，宽了就是横向溢出（Review Focus 第 4 条）。
final dayLabelWidth = _textWidth(
      L10n.monthlyFromDay(seg.startDay), AppTokens.labelSecondary) +
    (index > 0 ? AppTokens.spaceXs + AppTokens.iconSm : 0);
```

`_dayLabelWidth` 本身**不许改**（周期行那条路径是精确的）。

- [ ] **Step 5: 跑，确认绿 + 补窄窗用例**

Run: `flutter test test/schedule_editor_test.dart`
Expected: PASS。

再加一条覆盖 Review Focus 第 4 条 —— 同一套按月方案，`size: const Size(200, 400)`（本仓的小窗档）：`tester.takeException()` 为 null（`Row` 不横向溢出），且 `find.text(L10n.monthlyFromDay(31))` 仍在。

- [ ] **Step 6: 跑全套 + analyze**

Run: `flutter test && flutter analyze`
Expected: 全绿（1085 → 至少 1087）；`flutter analyze` 无 issue。

- [ ] **Step 7: 真机核**

装包 → 我的 → 排班管理 → 编辑当前方案 → 切到「按月」→ 截图。**判据**：「每月第 N 天起」完整显示（用最后一段那一行）。右滑到底核时，班次胶囊列仍能横向滚动、右侧时间文本没被挤出去。

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/calendar/schedule_editor_screen.dart app/test/schedule_editor_test.dart
git commit -m "fix(editor): 「每月第 N 天起」不再省略；cycleRowFitsTime 按真实标签宽判"
```

---

### Task 4: 收尾（版本号 / 更新日志 / 文档 / 全量验收）

**Files:**
- Modify: `app/pubspec.yaml` 与 `app/lib/core/app_info.dart`（版本号，**同步**）
- Modify: `app/lib/features/profile/app_dialogs.dart`（`_changelogZh` / `_changelogEn`：prepend 一条、删最旧一条、保持 10 条；测试版条目**只写这一版**）
- Modify: `AGENTS.md`（版本史 + 「最近改动」；并把「关键决策与坑」里那条桌面小组件字号缩放的条目补上胶囊宽度那半）
- Modify: `docs/superpowers/specs/2026-10-16-...-design.md` §7（把本轮**没做**的记下来，见下方）

**Interfaces:**
- Consumes: Task 1-3 的成果
- Produces: 可发布的版本

- [ ] **Step 1: 把「本轮不做」补进 spec §7**

至少记两条：① `_textWidth` / `_chipWidth` 不传 `TextScaler`，在「大 / 特大」字号档（1.1 / 1.2）下宽度**低估约 10~20%**，`cycleRowFitsTime` 因此可能误判 —— 这是**既有**问题、本轮只在自己新算的那一处沿用同一口径，没顺手改（改了会一起动到周期行那条路径的行为，要单独验）。② 周条今天那一列底下没有独立白卡（整卡一张），半透明块直接压卡底；与月历「白卡上压块」观感一致但成品不同源。

- [ ] **Step 2: 版本号**

`app/pubspec.yaml` 的 `version:` 与 `app/lib/core/app_info.dart` 的 `appVersion` **同步**改成 `0.11.24+171`（`Z` 与 `build` 由本计划定；`X.Y` 不动）。

- [ ] **Step 3: 更新日志**

`_changelogZh` / `_changelogEn` **各 prepend 一条、各删最旧一条、保持 10 条**。中文条目三句：月历与周条的班次胶囊改成按文字宽窄走（以前是一刀切的定值，格子一小就顶满、跟格子重合）；周条与月历同步（今天那列也变半透明、周标题改单字）；编辑排班「每月第 N 天起」不再省略。

- [ ] **Step 4: AGENTS.md**

版本史加一行 `→ 0.11.24(+171) 测试版（…）`；「最近改动」加一段；「关键决策与坑」里桌面小组件那条补上「胶囊宽度按简称现量（`chipWidthPx`），周条同步」的说明与那条「两字简称才是最宽档」的验收口径。

- [ ] **Step 5: 全量验收**

```bash
flutter analyze
flutter test
flutter test tool/visual/
```
Expected: 0 error / 0 warning；全绿；工装逐张比基线，差异逐条解释（响铃页时钟跳字是已知假象）。⚠️ 编辑排班那几屏（`02_editor_*` / `58_template_picker_monthly_*` 等）会因为标签列宽度变化而位移 —— 逐个确认是本次有意的改动。

- [ ] **Step 6: Commit + tag + 发布**

```bash
git add -A
git commit -m "chore(release): v0.11.24"
git tag v0.11.24 && git push origin beta && git push origin v0.11.24
```
发布说明先写到 `tools\gh\release-notes-v0.11.24.md`；再跑 `scripts\release.ps1 -SkipConfirm`（**必须在主 checkout 里构建** —— worktree 没有 `key.properties` 会静默回退 debug 签名）；最后 curl 一次 main 上的 `latest.json` 核对 prerelease 通道。
