# 桌面小组件胶囊不重合 + 周视图同步 + 按月标签去省略号（设计）

- 日期：2026-10-16
- 起因：用户 v0.11.23 真机测完之后的两条 ——
  1. 「月视图外边每个格子的半透明遮罩，跟里边班次的胶囊又重合了。App 里边其实不重合，有点间隙。然后周视图是不是还没同步优化？」
  2. 「编辑排班按月切法下面，『每月从第几天起』出现了省略号。不要出现这个省略号吧，明明位置空间都还有。」
- 影响版本：v0.11.24 测试版（`X.Y` 由用户定，AI 只动 `Z` 与 `build`）
- 用户对周视图的拍板（2026-10-16）：「一样，你按 App 那套来」—— 即周视图与月历**同一条同步口径**，都照 App 来。

---

## 1. 现状（真机量出来的，不是看出来的）

设备 Redmi K90 Pro Max · 1200×2608 @480dpi = **3×**。

**① 月历胶囊与格子重合。** 沿班次胶囊中线扫一格：桌面这边胶囊占了格子宽的 **95.5%**（左右各只剩 ~1dp）；App 里同一颗只占 **81%**（左右各留约 5dp）。根因是上一版（v0.11.23）把胶囊改成「跟着格子等比缩放」，但**宽度仍是固定比例**（月历 40dp 基准、周条 36dp 基准）—— 格子一缩，它反而比 App 那颗更满。App 那套是**按文字宽窄走**的：`_shiftChip` 是 `AnimatedContainer(padding: horizontal spaceXs(4)×s)` 包着 `FittedBox(Text(cellShift 12×s))`，所以「白」窄、「大休」宽，左右始终有那 4dp 内边距。

**② 周视图一个字都没同步。** 仍是：今天那一列**实心主色块**（不是月历现在的半透明块）、周标题「周一 周二」（不是单字）、胶囊同样占满列宽。v0.11.23 那次有意只动了月历卡。

**③ 按月标签的省略号。** `_monthRow`（`schedule_editor_screen.dart:1316`）把「每月第 N 天起」放在 `Expanded(flex: 3)` 的一列里、文字再套一层 `Flexible(..., overflow: ellipsis)`，右边班次胶囊那一列是 `Expanded(flex: 5)` 的横向滚动列表。标签列被 `flex:3` 硬压到 3/8 宽，而「每月第 31 天起」这种长串（9 个字）塞不下就省略 —— 但右侧胶囊列是**可横向滚动的**，根本不缺那点宽度。没有列头需要对齐（按月段列表是纯列表，无表头）。

---

## 2. 目标 / 非目标 / 反目标

**目标**

- 月历与周条的班次胶囊都改成**按文字宽窄走**（与 App `_shiftChip` 同一条），左右留出与 App 一致的间隙，不再与格子/遮罩重合。
- 周视图与月历**同一套**：今天那一列改**半透明块**、周标题改**单字**、胶囊按文字宽。
- 「每月第 N 天起」不再省略。

**非目标**

- 不动快照协议（仍是 v2，本轮**不新增任何字段**）。
- 不改三张卡的尺寸与注册（`resizeMode="none"` 不变）。
- 不改今天那格/那列的半透明块本身（v0.11.23 刚做，用户认可）。
- 不动今日卡（用户明确「今日卡片目前效果还可以」）。
- 不碰原生侧之外（闹钟、刷新、点击跳转等）。

**反目标**（做成了也算失败）

- 为让胶囊不重合，把它改成「写死更窄的一个数」—— 那只是把 40 换成 32，两字简称（「大休」「上夜」）又会挤，App 里那套是**跟文字走**的，不是更窄的定值。
- 为算文字宽度，把字号/字体常量在 Kotlin 里**另抄一份**—— 两处会静默走样。
- 动 `Paint.setAlpha` 那套 alpha（36/115）—— 那是淡染配方的地基。
- 把今天那列改半透明之后，字还留着 `onSolidInk` 的白字判据（浅底上读不出来，v0.11.23 月历那条刚踩过）。
- 为了消省略号，把标签字号调小一档去迁就宽度。

---

## 3. 关键决定：胶囊宽度用 `Paint.measureText` 现量，不抄字体常量、不加快照字段

桌面胶囊要「按文字宽窄走」，而 `RemoteViews` 在宿主进程渲染、**量不到文字宽度**，能改容器尺寸的 `setViewLayoutWidth` 又要 **API 31**（本仓 minSdk 26）。上一版能绕开它靠的是「位图驱动尺寸」，但位图宽度当时是写死的 40/36dp —— 那正是重合的根因。

**解法**：位图的宽度用 `android.graphics.Paint.measureText()` 在 Kotlin 侧**现量**。理由三条：

1. **用真 Android 字体量**，没有「Flutter 默认字体 vs 设备 MiSans/Roboto」的度量误差 —— 量出来的就是桌面上真正会画出来的那个宽。
2. **不加快照字段**：`shiftAbbr` 已经在快照里，Kotlin 拿它现量即可，协议 v2 一个字不动。
3. **不用 API 31**：量的是位图宽，位图本来就由我们画、由我们喂 `fitXY`。

**公式（与 App `_shiftChip` 逐项对齐）**：

```
chipW = paint.measureText(shiftAbbr) + 2 × padPx      // pad = spaceXs 4dp，同 App
chipH = 胶囊高（月历 18、周条 18，不变）
```

- `paint.textSize` = 胶囊字号（**月历 `cellShift` 基准 12 × `cellScale`；周条 `wg_sc_abbr` 固定 10dp，scale=1**）。
  - ⚠️ **周条没有缩放**：v0.11.23 那轮把 `sp→dp` + 加缩放的是**月历**（行高随 5/6 行月与启动器格子尺寸变），周条是 4×1 定尺寸卡、从头到尾没接 `cardScale`、`weekStrip` 里也没有 `applyScale`。所以周条这条 `paint.textSize = 10dp × density` 直接量，**别为周条现造一个 scale**（那会改变周条从未动过的观感）。
- 布局里胶囊那两层的角色对调：**`TextView`（简称）做宽度驱动者**（`wrap_content` + `paddingHorizontal = 4dp`），**`ImageView` 做 `match_parent`** 贴到 TextView 的宽度上。这样位图宽（量出来的）与 TextView 宽（文字 + 两倍 padding）天然一致，圆角也按真实宽度画、不会被 `fitXY` 拉成椭圆。月历与周条**两处**都这么改。

**LruCache 不炸**：宽度现在由 (字号 × 文字宽) 决定，同一次渲染里「白」与「夜」同宽共一张、只有「大休」这类两字的多一张 —— 一屏仍只有**屈指可数的几张**（16 色 × 2 档宽 ≪ 64）。**别按格子造唯一尺寸**（42 格各一张会把缓存冲爆，AGENTS 里那条）。

**护栏**（`widget_cell_block_guard_test.dart` 或新建一条）：扫 `WidgetChip.tintedChip` / `block` 的月历与周条调用点，断言**胶囊位图宽度来自 `measureText` 而非字面量 40/36**；反向验证：把宽度改回 `dpToPx(context, 40)` 立刻红。

---

## 4. 周视图同步（三条，照 v0.11.23 月历那套原样搬）

**① 今天那一列：实心块 → 半透明块。** `WidgetRenderer.weekStrip` 里 `isToday` 分支把 `WidgetChip.block(...)` 换成 `WidgetChip.glassBlock(snap.accent, colW, colH, 12dp 圆角, 2dp 描边)`（与月历那格**同一支**、同参数）。周条那一列底下**没有独立白卡**（周条是整卡、7 列都在一张卡里），半透明块压在卡自己的近白底上 —— 与月历的「白卡上压半透明块」观感一致，无需再补卡底。

**② 周标题单字。** `weekStrip` 里 `c.setTextViewText(R.id.wg_sc_weekday, d.weekday)` 改成 `snap.weekdays[col]`。快照顶层 `weekdays` 已经是单字、按「周一..周日」排，而周条 7 列恰好就是「本周一..本周日」—— **下标直接对**，不加字段。⚠️ 今日卡那边读 `days[].weekday`（完整「周几」）的**不动**，那是另一条路（v0.11.23 已定）。

**③ 今天那列的字色回到中性。** `weekday`/`day` 现在是 `if (isToday) onSolidInk(...) else muted/ink` —— 半透明块是浅底，`onSolidInk` 对 teal/orange 给白字、读不出来（v0.11.23 月历刚踩过）。改成 `muted` / `ink`（与月历 `_dayCell` 一致）。胶囊简称同理：`if (isToday) onSolidInk(d.color) else ink` → 恒 `ink`，胶囊恒走 `tintedChip`（不再 `isToday` 转实心 —— 「淡染压在实心块上会糊」那条理由没了）。

> 同步口径一句话：**周条今天那一列 = 月历今天那一格**，字色、块、胶囊三处逐项对齐，不改的话两张卡并排时「今天」长相不一致。

> **⚠️ 一条既有的护栏会红，计划必须顺手更新它**：`widget_cell_block_guard_test.dart` 里那条「今天那格的字都过 onSolidInk」在 v0.11.23 被改成断言 `onSolidInk(context, ` 的调用数 `>= 4`（注释写「周条三处 + 今日卡药丸一处」）。本轮把周条三处 `onSolidInk` 全改成中性色后，全文件只剩今日卡药丸那 **1** 处 → `1 < 4` 直接红。这条不是本轮要新增的反向验证，是一条**失效的旧不变量**—— 下界从 4 改成 1（今日卡药丸那一处仍要走 `onSolidInk`，它是白字压主色），并重写那段注释。月历那边的「monthCard 里不许出现 onSolidInk」那条 v0.11.23 已反向，`weekStrip` 里也要有同样一条「不许出现」。

---

## 5. 按月标签去省略号

`_monthRow` 里把「每月第 N 天起」那一列从 `Expanded(flex: 3, ...)` 改成**自然宽度**，右侧班次胶囊列保持 `Expanded` 吃掉剩余宽度（它本来就是横向滚动列表，让出空间零代价）。

- 长串「每月第 31 天起」≈ 9 字 × 13sp ≈ 120dp + 图标 16 + 间距 8 ≈ 144dp；去掉 `flex:3` 的硬压后自然放得下。
- **不调字号**（`labelSecondary` 13 不动）、**不换短串**（「从 N 天起」会丢「每月」的语境）。

### 5.1 ⚠️ 订正：「裸的自然宽」在 200dp 小窗下会溢出（实施时量出来的）

这一节原本写的是「标签 + 编辑图标按内容排，`Flexible` 的 `ellipsis` 去掉」。
**照那样写出来的第一版在 200dp 视口下当场溢出 41px**，本轮新加的小窗用例抓到的：

- 实测：标签自己 **139.3dp**（测试字体是保守上界；每个汉字占满一个 em），
  而那一行**整行只有 142.3dp** —— 再减 8dp 间距与 36dp 删除键，绷不住。
- 也就是说「不 flex 的裸子件」等于把「标签自己就能顶满整行」这件事交给运气。

**最终写法**：外面套一层 `ConstrainedBox(maxWidth:)`，上限 = 这一行让掉其余固定件
之后剩下的宽（`showTime` 为真时直接用自然宽 —— 按那个判据的定义它必然放得下）。
够宽时上限等于自然宽、不裁；真放不下时和里面那层 `Flexible` + `overflow: ellipsis`
一起降级成**省略号** —— 不是溢出、也不是裁字。

**⚠️ 里面那层 `Flexible` 与 `overflow: ellipsis` 必须成对留着**：只留 `Flexible`
而把 `overflow` 去掉，宽不够时结果是**直接裁字**（比省略号更糟）；两个都去掉，
结果就是上面那个 41px 溢出。三种组合只有「成对留着」是对的。

### 5.2 `cycleRowFitsTime` 的 `_dayLabelWidth = 56` 不能照旧

那个纯函数是 `_cycleRow` 与 `_monthRow` **共用**的，内部用 `_dayLabelWidth = 56` 当「标签列宽」去算 `needed = 56 + gap + chips + gap + time`，以此决定 `showTime`。`_cycleRow` 的标签确实是 `SizedBox(width: 56)`（精确），但 `_monthRow` 的标签现在按内容自然宽（「每月第 31 天起」+ 图标 ≈ 144dp）—— **这处不精确是既有的**，本轮改成自然宽度后它更不精确。而 `_monthRow` 末尾那个 `Text(timeText)` 是**不带 Flexible/ellipsis 的裸 Text**，`showTime` 误判成 true 时会在窄窗横向溢出。

**修法**：给 `cycleRowFitsTime` 加一个 `required double dayLabelWidth` 入参 —— `_cycleRow` 传 `_dayLabelWidth`（56，精确不变），`_monthRow` 传**实测的标签宽**（按 `labelSecondary` 量 `L10n.monthlyFromDay(seg.startDay)`，`index > 0` 时再加编辑图标 16 + 间距 4）。这样两条路径各自用真实列宽，`showTime` 判据回到正确。**不要顺手改 `_dayLabelWidth` 本身** —— 那会连 `_cycleRow` 那条精确路径一起改坏。

---

## 6. 验收

1. **真机**（Redmi K90 Pro Max，adb）：月历、周条、今日卡三张 + 编辑排班（按月模式，拖到多段）都出图，浅深两档。
2. **胶囊不重合**：量月历一格，胶囊宽 ≤ 格宽的 **~82%**（与 App 同量级，现状 95.5%）；周条同理。**⚠️ 拿「两字简称」（如「大休」）当上界量** —— `shortLabel` 上限 2 字、fallback 单字，单字简称天然只有 ~50%，拿它量会误判「通过」而漏掉真正逼近间隙的「大休」那档。
3. **周视图与月历「今天」一致**：半透明块、单字周标题、胶囊按文字宽。
4. **标签无省略号**：「每月第 31 天起」完整显示（这是最长的一档，用它当上界）。
5. **单测全绿**（当前 1085，只增不减）；`flutter analyze` 0/0；视觉工装全跑 + 逐张比基线，差异逐条解释（响铃页时钟跳字那几张是已知假象）。
6. 新增/改动的护栏**逐条反向验证过**（把实现改回旧写法看它红）。

## 7. 本轮不做

- 今日卡（用户说效果还可以）。
- 周条今天那一列**底下的白卡**（周条是整卡，没有逐列白卡；半透明块直接压卡底即可，
  与月历观感一致）。⚠️ 因此它与月历那格的**成品不同源**：月历是「不透明页面底 →
  白卡 → 半透明块」，周条是「卡底 → 半透明块」。观感一致、结构不同，看的时候别
  拿一边的像素去解释另一边。
- 三张卡的尺寸、刷新粒度、点击跳转。
- 胶囊在空白表方案下仍是「没班次不画」（v0.9.16 那条，不变）。
- **`_textWidth` / `_chipWidth` 不传 `TextScaler`**：在「大 / 特大」字号档
  （1.1 / 1.2）下这两个量出来的宽会**低估约 10~20%**（用的是 `MediaQuery` 里
  那一档之前的默认缩放）。`cycleRowFitsTime` 因此可能在特大档误判「放得下时间」。
  这是**既有**问题（`_chipWidth` 从写下那天起就是这样），本轮只在自己新算的那一处
  （`dayLabelWidth`）沿用同一口径，没顺手改 —— 改了会一起动到 `_cycleRow` 那条
  路径的行为，要单独验一轮。
- **`_monthRowDeleteWidth = 36` 是从 `glass_delete_button.dart` 的
  `SizedBox(width: 36)` 抄过来的**（那边是几何事实、不是设计令牌，没有可读的出口）。
  它只用来算标签的上限，**没有护栏盯着两边同步** —— 那边改宽度时这里不会红。
  两条都改了才需要真机复看：这里只是「让出多少」的估算，宽一点窄一点只影响
  小窗下省略号的迟早，不影响正确性。

## 8. 相关文件

- `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`（`monthCard` / `weekStrip` / `cardScale`）
- `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetChip.kt`（`tintedChip` / `block` / `glassBlock`）
- `app/android/app/src/main/res/layout/widget_month_cell.xml` / `widget_strip_cell.xml`（胶囊那两层对调）
- `app/lib/features/calendar/schedule_editor_screen.dart`（`_monthRow`）
- `app/lib/features/calendar/calendar_screen.dart`（`_shiftChip` —— 对照基准，不改）
- `app/test/widget_cell_block_guard_test.dart`（护栏）
