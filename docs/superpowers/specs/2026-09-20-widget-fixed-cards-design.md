# 小组件：固定档位重做（本周条 / 今日卡 / 整月） · 设计规格

- 日期：2026-09-20
- 目标版本：`0.8.8+99`（AI 只改末位 `Z` 与 `build`；`X.Y` 由用户决定）
- 状态：待评审
- 来源：用户真机反馈（v0.8.7 测试）+ 同日两轮头脑风暴
- 前置：`2026-09-18-home-widget-design.md`（地基：链路、不变量、术语沿用）；
  `2026-09-13-design-language-v2-design.md`（视觉裁决依据 —— 理念第 1/2/3 条被本轮直接引用）
- **取代**：`2026-09-19-widget-tier-redesign-design.md`（五档自适应版式；本轮把它整个拆掉）

---

## 1. 背景与目标

### 1.1 用户原话

第一轮（看到竞品 picker 截图后）：

> 咱们这个小部件做的实在是太丑了。我看了一下人家的那个排班助手，它的那个安卓小组件，它是固定的大小……在固定大小的卡片做了好几张，然后每一张都专门优化了它的美观度。那咱们是不是也可以这样啊？

第二轮（追问「不同尺寸下展示什么」时被打断）：

> 得重新考虑一下，在不同尺寸的小组件下面，我们要怎么展示？展示什么内容？反正你现在咱们展示的这些内容的样式，我实在是接受不了，跟咱们的设计理念差别太大了。界面实在是太丑了。

第三轮（给出自己的方案 + 竞品真机截图）：

> 4×1 是显示一周的这个班次。然后这个是 4×4 还是 4×5 不知道，它显示的是一个月的班次。那我们就照着它做呗，我们的日历界面不已经有现成的了吗？那就把日历界面照搬下来不就行了吗？这样不就符合咱们的设计理念了吗？然后呢，还可以针对日历界面的那个今日信息卡片，咱们可以把它做成 4×2 或者 4×3 的。

### 1.2 「丑」不是审美问题，是三处机械原因

对照 `calendar_screen.dart` 与 `work/cc_328x348dp_GRID_WEEK.png`，逐条能指出病根 —— 它们是本设计的全部出发点：

| # | 现象 | 真因 |
|---|---|---|
| 1 | 整片网格是一排**彩色砖** | **信息胶囊被换掉了配方。** App 的配方是 `fill = solid ? 1.0 : 0.14`（`calendar_screen.dart:1199`）—— 班次色 **14% 淡染底 + 45% 同色描边**（`WidgetChip.tintedChip` 已有），只有选中那一格实心。小组件里 `fill` **恒为 1.0**，还配 `onSolid` 的纯黑/纯白字 → 分量重了两三档，撞理念第 1 条「背景中性，强调色只染点」。那段代码自己的注释写着：「同一个『信息胶囊』在应用里只该有一套长相，不因为进了日历就换配方」—— 小组件正好破了这条 |
| 2 | 白卡里再套一张白卡 | **容器套娃 + 层级靠底色深浅。** App 的层级只靠字号/字重/明度（理念第 3 条）、容器是玻璃（第 2 条）；而 RemoteViews **没有背景模糊**，玻璃在桌面退化成「白卡 + 1px 描边」，两层一叠就是空框 |
| 3 | 高尺寸下上下各空一百多 dp | **构图是「把内容摆进去」而不是「为这个尺寸设计」。** 行高/格高固定、内容整体 `center_vertical` —— 443dp 那档的空白（见 `work/cc_328x443dp_GRID_WEEK.png`）不是留白，是没人管的地方 |

### 1.3 目标

- **固定档位、不可拉伸**（对齐竞品）：三张各自注册、各自优化的卡，用户按需要挑一张放桌面
- **视觉回归 App**：胶囊配方、层级手段、今天标记全部照抄日历页现成的配方
- **内容照搬日历界面**：本周条 = 日历的一行 + 表头；整月 = 日历主体；今日卡 = 底栏信息卡
- 每张卡**为它自己的尺寸**排版，不再有「同一版式被拉伸」

### 1.4 非目标

见 §11。

---

## 2. 已定决策

| # | 决策 | 理由 |
|---|---|---|
| ① | **三张固定卡**：4×1 本周条 / 4×3 今日卡 / 4×5 整月；全部 `resizeMode="none"` | 用户 2026-09-20 拍板。对齐竞品「固定大小 + 每张单独优化」 |
| ② | **整月的格子不带白卡** | App 里 42 个格子各是一张白卡（`calendar_screen.dart:1379`），那是因为底下垫着中性底 `#F5F6FA`；桌面上卡底是 96% 不透明、叠 42 张会糊成一片，且正是决策②要拆掉的套娃。竞品的月历格子也是纯文字、零卡片 |
| ③ | **数据窗口从「今天起 14 天」改成「按月的绝对窗口」** | 月历要本月完整 + 前后补齐格；**更要紧的是跨月**：快照里必须已经装着下个月，否则 10 月 1 日零点那次刷新只能右移现有数据、变不出新月份，桌面直接是空月 |
| ④ | **今日卡那档取 4×3，不取 4×2** | 完整信息卡内容约 158dp 高；4×2 系统报 158dp、实渲约 173dp，四周内边距一加就顶满。4×3 报 253dp、实渲约 268dp，卡片能按自己的尺寸舒展 |
| ⑤ | **月历先只出 4×5 一张** | 三行格子（日期 + 胶囊 + 农历）约 59dp/行，6 行要 ~354dp + 表头；4×4 只剩约 51dp/行，装不下。竞品的 4×4 是纯文字格子（无胶囊无农历）才压得下去。4×5 真机出图量完再决定 4×4 值不值得做两行精简版 |
| ⑥ | **刷新机制完全沿用**（跨天零点 + 班次起止边界），不新增「月初」边界 | 月历换月靠的是每日零点那次重渲染：原生按 `LocalDate.now()` 现算「该渲染哪个月」，数据本来就在窗口里 |
| ⑦ | **旧的 `ShiftWidgetProvider` 整个删掉**，桌面上已放置的旧实例失效 | 三张新卡版式与尺寸都不同，把任意尺寸的旧实例映射到其中任何一档，都只会得到一张被裁的卡 —— 那是本仓反复拒绝的「理直气壮地出错」。一次性代价写进更新说明（用户重新添加即可） |
| ⑧ | **picker 缩略图按「结构示意」出**（静态版式、无文字、无假数据） | 见 §8 |

---

## 3. 三张卡的声明（尺寸与格子）

`res/xml/` 下三份 `*_info.xml`，共同字段：

```
android:resizeMode="none"          ← 本轮的核心：不可拉伸
android:widgetCategory="home_screen"
android:updatePeriodMillis="0"     ← 沿用：刷新全走 WidgetRefreshScheduler
android:initialLayout="@layout/widget_placeholder"
```

尺寸两头都声明（minSdk 26：Android 12 以下不认 `targetCell*`，靠 `70n-30` 老公式折算）：

| 卡 | 目录名 | `targetCellWidth/Height` | `minWidth` | `minHeight` | 实测高度（Redmi 25102RKBEC / 400dp / 480dpi） |
|---|---|---|---|---|---|
| 本周条 | `widget_week_strip_info.xml` | 4 / 1 | 250dp | 40dp | 报 63dp，实渲约 78dp |
| 今日卡 | `widget_today_info.xml` | 4 / 3 | 250dp | 180dp | 报 253dp，实渲约 268dp |
| 整月 | `widget_month_info.xml` | 4 / 5 | 250dp | 320dp | 报 443dp，实渲约 458dp |

> 宽度恒 250dp（4 列）：本项目只有一个 Android 版，网格恒 4 列；不声明 2 列形态（见 §11）。
> 高度取的 `70n-30` 是 Android 12 以下的官方折算公式；**这三个数要在真机上核一遍**
> （`targetCellHeight` 生效时，`minHeight` 只影响老系统与部分第三方桌面）。

`resizeMode="none"` 是「不可拉伸」的正式声明；**部分老版本第三方桌面会忽略它**，这与本仓既有的
「小米/HyperOS 上标准小组件藏在二级分类里」属同一类平台边界，写进 README 的已知边界。

---

## 4. 视觉配方（回归 App 的三条）

### 4.1 信息胶囊：淡染，不实心

格子里的班次胶囊一律走 `WidgetChip.tintedChip(color, w, h)`（现成：14% 底 + 45% 描边，
描边宽 = 高度 × 0.08），与 App 的 `_shiftChip` 同配方。

**文字色：走 `wg_ink_*`，不染班次色。** App 用 `AppTokens.inkFor(color, blended)`
（按底色的相对亮度算可读色），本仓已经在今日卡片的「其他班组」胶囊上做过一次**同样的
有意偏离**（`WidgetRenderer` 该处注释：为一行小字在原生复刻一份 luminance 计算不值当），
本轮把它推广成通则 —— 底色是 14% 淡染，混合后≈卡片底，所以「黑字/白字」就够，
且**必然过 AA**（卡片底近不透明，对比度由卡片自己决定）。

> 由此快照里的 `abbrInk`（`onSolid` 生成的胶囊字色）**失去消费者，删掉**。
> `WidgetStore.Day` 的对应字段与解析一并删 —— 留着一个没人用的字段，下一轮会被当成活的。

### 4.2 层级：只有字号、字重、明度

- **不留白卡**：月历格子、本周条格子都不画卡片底（决策②）
- **今日卡自成一卡**：它本来就是一个独立档位，不再被外壳套一层
- 分区靠间距与明度，不靠底色深浅

### 4.3 「今天」标记

沿用既有唯一手段：**日期走主色**（`snap.accent`），**不许加粗** ——
`TextView` 没有 `setTypeface(int)` 重载，`setInt(id, "setTypeface", …)` 会在宿主进程
抛 `ActionException`（该结论在 `widget_cell.xml` 头部注释里，别重踩）。

---

## 5. 各卡版式

### 5.1 4×1 本周条（`widget_week_strip.xml` + `widget_strip_cell.xml`）

抄 App 日历的「周几表头行 + 一行格子」，七列等分：

| 行 | 内容 | 字号 / 尺寸 | 来源 |
|---|---|---|---|
| 1 | 周几（一~日） | 11sp，muted；今天走主色 | `days[i].weekday`（已按日期烘焙） |
| 2 | 日期**日数字**（如「19」） | 15sp，ink；今天走主色 | 原生用 `LocalDate.ofEpochDay(days[i].day).dayOfMonth` 现算 —— **不新增字段**（`dateShort` 是「9月19日」，整串在 46dp 宽的列里排不下） |
| 3 | 班次胶囊 | 高 18dp，淡染配方 | `days[i].color` + `shiftAbbr` |

- 内容是**今天所在的那一周**（周一~周日，与 App 的日历行同构），今天那列走主色
- 点击：整条 → 开 App 日历今天；每一列 → 跳那一天（7 个 requestCode）
- 休班日照常画胶囊（休班是一个班次定义，App 里也这么画）

**高度预算**：卡内 padding 8dp × 2 → 可用约 62dp；三行 15 + 20 + 18 + 间距 4 ≈ 57dp，
**余量仅 5dp**。这正是上一版 63dp 那档被裁掉半行的同一类险 —— 所以规定：
**实施时先真机出图再定稿**；若被裁，退到**两行备选**（周几与日期同行：`一 19`，胶囊单独一行，
约 41dp），不要靠缩字号硬塞。

### 5.2 4×3 今日卡（`widget_today_standalone.xml` + 沿用 `widget_today_card.xml`）

内容与配方照搬现有 `renderTodayCard`（日期行 + 农历 + 班次 + 时间 + 其他班组），
新增一层**只画卡片底**的壳（`widget_today_standalone.xml`：根 `match_parent` + 卡底 + 一个槽位）。

**为 4×3 专门排版**（这是「每张卡单独优化」在今日卡上的落地）—— 大一号的字 + 舒展的行距，
并把**农历那一行换成完整描述**（`LunarInfo.fullDescription`，App 的完整版信息卡用的就是它：
「农历 丙午年 八月初五 · 生肖马 · 日干壬辰 · 国际民主日」，允许两行）。

> 这一条是有意的：4×3 比现在的紧凑档高出约 95dp，**多出来的地方要放真内容，不是把行距摊开**。
> 现在的今日卡只有 `lunarShort`（「初八」）；换成完整描述既是**信息增量**，也是**向 App 的
> 完整版信息卡再靠近一步**（用户要的「照搬」）。放不下时 `maxLines="2"` + `ellipsize`。

| 项 | 现在（紧凑档） | 4×3 档 |
|---|---|---|
| 根 padding | 14dp | 18dp |
| 日期字号 | 18sp | 20sp |
| 班次名字号 | 15sp | 17sp |
| 农历 | `lunarShort` 一行 | `lunarFull` 最多两行，13sp |
| 行间距 | 8dp | 12dp |
| 徽章高 | 20dp | 22dp |
| 左侧色条 | 4×18dp | 4×22dp |

排版后内容约 200dp，4×3 可用约 268dp —— 余下约 68dp 由**上下均匀留白**吃掉，根布局
`gravity="center_vertical"`。**不靠继续放大字号去填满**：字号要能被真机图判定为「舒展」，
而不是「被撑大」。

跨天降级逻辑**逐字不变**（`todayCard.day != 今天` → 隐藏农历/待办/其他班组，只显示
`days[todayIndex]` 的日期/班次/时间）。

### 5.3 4×5 整月（`widget_month_card.xml` + `widget_month_cell.xml`）

```
┌ 卡（根 match_parent，padding 8dp，卡底沿用 widget_card_*） ┐
│ 2026年9月                      ← 月份标题行，13sp muted      │
│ 一  二  三  四  五  六  日      ← 周几行，7 个等宽 11sp muted  │
│ ▢  ▢  ▢  ▢  ▢  ▢  ▢          ← GridLayout columnCount=7     │
│ …（最多 6 行 × 7 列 = 42 个 FrameLayout 槽位）                 │
└────────────────────────────────────────────────────────────┘
```

- **渲染哪个月**：原生取 `LocalDate.now()` 的月，扫 `days[]` 挑出落在该月的天
  （`days[i].day` 是 epochDay，`LocalDate.ofEpochDay(it)` 现算年月 —— `WidgetStore` 已经在
  用 `java.time`，minSdk 26 可用）。**前导空格数**由本月 1 日的星期几现算
- **月份标题**：从快照的 `months` 里按 `年-月` 查；**查不到就隐藏标题行** —— 绝不拿上个月的标题顶上
- **周几行**：7 个静态 `TextView`，文字来自快照（Kotlin 侧不许有中文字面量）
- **每格**（`widget_month_cell.xml`）：日期日数字 16sp（今天走主色，现算同 §5.1）→ 胶囊 18dp 高（淡染配方）→ 农历 11sp（`wg_muted_*`，法定节假日走 `wg_holiday`）

**高度预算**：卡内可用约 442dp − 标题 18 − 周几 15 − 两个间距 8 = 约 401dp；
6 行 × 65.5dp。每格内容 21 + 3 + 18 + 2 + 15 ≈ 59dp ✓ 余约 6dp。

**行数不满 6 时**（多数月份是 5 行）：多余槽位 `GONE`（GridLayout 里 `GONE` 不参与布局，
沿用 v0.8.6 的结论），网格整体在卡内**垂直居中**，上下均匀留白 —— 不为凑满而拉高格子。
真机图上 5 行月与 6 行月**各核一张**。

- 点击：每格 → 跳那天（42 个 requestCode，见 §6.4）；前导空格不设点击

---

## 6. 结构改动

### 6.1 三个 provider + 一个注册表

`ShiftWidgetProvider` 删除，改为：

| 文件 | 作用 |
|---|---|
| `ShiftWidgetBase.kt` | 抽象基类：`onUpdate` / `onAppWidgetOptionsChanged` / `onDeleted` / `onReceive` 的公共实现（内容就是现 `ShiftWidgetProvider` 那四件事，去掉分档） |
| `WeekStripWidgetProvider.kt` / `TodayCardWidgetProvider.kt` / `MonthWidgetProvider.kt` | 三个空壳子类，各自 `override val variant` |
| `ShiftWidgets.kt` | 注册表：`ALL`（三个 `ComponentName`）、`refreshAll(ctx)`、`hasAnyInstance(ctx)`、`scheduleNextRefreshIfNeeded(ctx)`、`cancelRefreshIfNone(ctx)` |
| `WidgetRefreshReceiver.kt` | 刷新广播的落点（`exported=false`，自定义 action 显式组件广播）。刷新闹钟不再指向某一个具体的 provider |

`MainActivity` 的 `widgetPushSnapshot` → `ShiftWidgets.refreshAll`；`BootReceiver` →
`ShiftWidgets.scheduleNextRefreshIfNeeded`；`WidgetRefreshScheduler` 的目标组件改成
`WidgetRefreshReceiver`，`ACTION_REFRESH` 常量随之搬过去。

`onDeleted` 的「最后一个实例才取消刷新」判定要**跨三个 provider**（
`ShiftWidgets.hasAnyInstance`），否则删光本周条会把整月的刷新一起取消。

### 6.2 manifest

三个 `<receiver>`，各自 `android:label`（见 §6.3）、各自的 `android.appwidget.provider`
meta-data，都 `exported="false"`；**每个类都要显式声明**（release 开 R8，只被代码引用的类会被裁）。
`WidgetRefreshReceiver` 一并声明。

### 6.3 三张卡的 picker 名字

picker 里的名字来自 manifest 的 `android:label`，**它在安装时按系统语言解析，跟不了
App 内的语言开关**（这是 Android 的平台边界，本仓现状本来就把 App 名写死在 manifest 里）。

决策：**新建 `res/values/strings.xml` 与 `res/values-en/strings.xml`**，只放三张卡的名字
（`widget_week_strip_name` / `widget_today_name` / `widget_month_name`），随**系统语言**走。
App 名（`android:label`）**本轮不动**（它是产品名，改英文名是另一件事）。

> 三张名字必须不同 —— 竞品那两张月历同名（4×4 / 4×5），用户只能靠缩略图和尺寸徽章区分；
> 我们三张内容完全不同（本周 / 今日 / 整月），同名是找麻烦。

### 6.4 requestCode：每位实例的槽位 32 → 64

月历一格一码，需要 `Root + 42 格 = 43` 个槽位 > 32。**提到 64**
（`Cell(m,c) = B + 64m + 1 + c` 落在 `[64m+1, 64m+63]`，永不为 64 的倍数 —— 与 `Root`
结构性错开，进位碰撞根除的论证不变）。溢出上限从约 6710 万降到约 3350 万，仍够用。
**`AGENTS.md` 那一段要同步改**（它现在写的是「基数 32、上限 6710 万」）。

### 6.5 文件清单

**Kotlin（`app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/`）**

| 动作 | 文件 |
|---|---|
| 新增 | `ShiftWidgetBase.kt`、`ShiftWidgets.kt`、`WidgetRefreshReceiver.kt`、`WeekStripWidgetProvider.kt`、`TodayCardWidgetProvider.kt`、`MonthWidgetProvider.kt` |
| 改写 | `WidgetRenderer.kt`（分档 → 三个 `renderWeekStrip` / `renderTodayCard` / `renderMonth`）、`WidgetStore.kt`（协议 v2 + 新字段）、`WidgetRefreshScheduler.kt`（目标组件换成 `WidgetRefreshReceiver`） |
| 删除 | `ShiftWidgetProvider.kt`、`WidgetTier.kt` |

**布局（`res/layout/`）**

| 动作 | 文件 |
|---|---|
| 新增 | `widget_week_strip.xml`、`widget_strip_cell.xml`、`widget_month_card.xml`、`widget_month_cell.xml`、`widget_today_standalone.xml`、`widget_empty.xml` |
| 改写 | `widget_today_card.xml`（按 §5.2 的 4×3 配方） |
| 沿用 | `widget_placeholder.xml`、`widget_crew_chip.xml` |
| 删除 | `widget_list_compact.xml`、`widget_list.xml`、`widget_row.xml`、`widget_grid_week.xml`、`widget_grid_fortnight.xml`、`widget_cell.xml`、`widget_grid_with_card.xml` |

**资源（`res/xml/`、`res/values/`）**

| 动作 | 文件 |
|---|---|
| 新增 | `widget_week_strip_info.xml`、`widget_today_info.xml`、`widget_month_info.xml`、`values/strings.xml`、`values-en/strings.xml` |
| 删除 | `shift_widget_info.xml` |
| 沿用 | `widget_colors.xml`（不加新色）、`widget_card_light/dark.xml` |

**Dart**：`features/widget/widget_snapshot.dart`（窗口 + 字段 + `v:2`）、
`features/widget/widget_service.dart`（若 push 入参有变）、`test/widget_snapshot_test.dart`（改）、
`test/widget_tier_thresholds_test.dart`（删）。

---

## 7. 快照改造（`widget_snapshot.dart` / `WidgetStore.kt`）

### 7.1 窗口：从「今天起 14 天」改成「按月的绝对窗口」

```
from = min(本月 1 日, 今天所在周的周一)      ← 本周条要能取到周一（今天可能是周日）
to   = 下月最后一天                        ← 跨月时桌面不空
```

天数从 14 涨到 **最多 68**（31 + 31 + 周内补齐 6）。三条随之而来的性质：

1. `days[]` **不再以今天为首**，且含过去的天。原生侧「按 `epochDay` 找今天」的实现
   （`Snapshot.indexOfToday()`）本来就是这样写的，**不改**；`relativeLabel` 用的是
   `index - todayIndex`，**不改**
2. 窗口恒包含今天（`from ≤ today ≤ to`），窗口耗尽 = App 两个多月没打开 → 占位态
3. `boundaries` 只收未来时刻（既有实现），窗口变大只是条数变多

### 7.2 协议版本 `v: 1 → 2`

结构改动太大（窗口语义、`abbrInk` 删除、新字段），必须换版本号 —— 原生对不上就按
「无快照」渲染占位态，正好把升级时的旧快照清干净。两处（Dart `kWidgetSnapshotVersion`、
`WidgetStore.parse` 的 `optInt("v", -1) != 1`）同步改。

### 7.3 字段增删

| 位置 | 变动 | 说明 |
|---|---|---|
| `days[i]` | **删** `abbrInk` | 胶囊文字改走 `wg_ink_*`（§4.1） |
| `days[i]` | **增** `lunarShort`（String）、`lunarIsHoliday`（bool） | 月历格子第三行；节假日走 `wg_holiday` |
| `todayCard` | **增** `lunarFull`（String） | 4×3 档的完整农历描述（`LunarInfo.fullDescription`） |
| 顶层 | **增** `weekdays`: 7 个本地化周几 | 月历表头行（Kotlin 侧不许有中文字面量） |
| 顶层 | **增** `months`: `[{y, m, title}]` | 窗口覆盖的月份标题（`L10n` 产出，如「2026年9月」/「September 2026」） |

`todayCard`、`labels`（今天/明天/后天/已调班）、`emptyHint`、`accent`、`themeMode` 均不变。
`abbrInk` 之外，**`Day` 里其余字段继续供今日卡与本周条使用**。

### 7.4 体积与成本

JSON 从约 4KB 涨到约 20KB（68 天 × 每行 ~10 个短字段 + 边界表约 200 条），
走 SharedPreferences 与 MethodChannel 字符串，量级无碍；生成侧是纯函数，68 次
`shiftOn` + `lunarOf` 是毫秒级。**不预先优化**，实施后量一次真机 push 耗时即可。

---

## 8. picker 缩略图（`previewLayout`）

现状：三张卡都指向 `widget_placeholder`（应用图标 + 名字），不是真实版式。

`previewLayout` 是**静态 inflate**、不跑 RemoteViews 动作 —— 真实版式（`addView` 出来的
格子）映不出来。三条可选路线与取舍：

| 路线 | 代价 |
|---|---|
| **A. 结构示意图**（本轮取它） | 每张卡出一张静态布局：只有形状与色块（网格的方格、本周条的一横排、今日卡的色条与色块），**无文字、无假数据**。好处：零双语问题、不撒谎、一眼能区分三张 |
| B. 真内容的静态布局 | 要写死示例文字（中文）→ 撞双语；写英文 → 中文用户看不懂。两条都要 `values-zh/en` 各一套布局 |
| C. `previewImage` 出 PNG | 一份管线活（`scripts/` 里再加一条），且图会随设计漂移、需要人工维护 |

三张示意图**按真机截图的尺寸比例画**，改版式时一起改。

---

## 9. 迁移与兼容

- 桌面上已放置的旧实例（`ShiftWidgetProvider`）在升级后**失效**，用户重新添加三张卡之一
- 更新说明（`app_dialogs.dart` 的词条）里要写明这一条 —— 用户升级后第一眼就会发现桌面少了东西，
  不写就是让用户自己猜
- 旧快照（`v:1`）不再被解析 → 首次升级后到第一次 push 之前，卡片显示占位态（很短，App 一打开就推）

---

## 10. 边界与容错

| 情况 | 表现 |
|---|---|
| 无快照 / `v` 对不上 / 解析失败 | 三张卡都走 `widget_placeholder`（沿用） |
| 今天不在窗口内（App 两个多月没打开） | 占位态（同上，`indexOfToday() < 0`） |
| `hasSchedule == false` | 空表提示（改用一张共享的 `widget_empty.xml`：根卡底 + 居中提示，三张卡共用） |
| 今日卡跨天（`todayCard.day != 今天`） | 降级态，逐字沿用现有实现 |
| 月历所在月份在 `months` 里查不到标题 | **隐藏标题行**，不从上个月借 |
| 今天所在的月/周在窗口边缘 | 窗口恒包含本月与下月、以及本周的周一（§7.1），不会发生 |
| 某个班组数为 1（无从显示「其他班组」） | 整块隐藏（沿用） |
| 月历 5 行 vs 6 行 | 多余槽位 `GONE`，网格整体居中（§5.3） |

---

## 11. 明确不做

- **4×4 月历**（两行精简版）—— 等 4×5 真机出图量完再定
- **4×2 周条 / 4×6 月历** —— 竞品出 4×4+4×5、4×1+4×2 是两两配对，我们只取每类一种
- **窄于 4 列的形态**（2 列月历、2×2 方卡）—— 本项目只有 4 列网格
- **月历里再附今日卡** —— 4×5 的高度预算里没有它的位置（月历已在 §5.3 用满）
- **月历翻月 / 本周条翻周** —— 桌面小组件不做交互式翻页，`‹ ›` 那种只是装饰（竞品有，我们不做假按钮）
- **天气 / 待办清单 / 打卡按钮** —— 越界
- **小组件配置页**（选班次、选颜色）—— 沿用既有决策
- **跨月时让 Dart 重新生成快照** —— 做不到（App 未必在跑），改用窗口覆盖下月（§7.1）
- **Flutter 位图渲染整卡** —— 沿用既有决策

---

## 12. 测试与验证

现有 265 条测试**只增不减**。

### 12.1 Dart 层

| 文件 | 变动 |
|---|---|
| `widget_snapshot_test.dart` | 改：窗口断言（`from = min(本月1日, 本周一)`、`to = 下月最后一天`、**恒包含今天**、跨月月各一组、天数 ≤ 68）；新字段（`lunarShort` / `lunarIsHoliday` / `weekdays` 七条 / `months` 标题）；`v == 2`；`abbrInk` 已删除（断言不存在） |
| `widget_tier_thresholds_test.dart` | **删**（`WidgetTier.kt` 没了，护栏失去对象） |
| `widget_today_card_staleness_test.dart` | 不动 |
| `widget_layout_whitelist_test.dart` | 不动（它扫目录，新布局自动纳入），但**新布局必须过**：只用 `FrameLayout` / `LinearLayout` / `GridLayout` / `TextView` / `ImageView` |

**不新增**「按估算核高度够不够」的护栏测试 —— 那是假保证（估的 dp 不是实测的 dp，
本仓被这类东西咬过）。高度只认真机截图。

### 12.2 真机（Redmi 25102RKBEC / 400dp / 480dpi）

| # | 验什么 | 判据 |
|---|---|---|
| 1 | **42 格的位图是否撑爆 RemoteViews**（见 §13.1） | 月历卡真机渲染出来、logcat 无 `TransactionTooLargeException` / RemoteViews 告警 |
| 2 | 三张卡各截一张图 | 版式、占比、留白对得上 §5 的预算 |
| 3 | 4×1 的 5dp 余量 | 三行一个不少、不裁切；裁了就换两行备选 |
| 4 | 5 行月与 6 行月各一张 | 网格居中、无空行残留 |
| 5 | 三个 picker 缩略图 | 三张分得清、不误导 |
| 6 | 逐格点击 | 月历 42 格与本周条 7 列都跳到正确那天 |
| 7 | 跨天 | 拨系统时间过零点：本周条翻周、月历翻月（跨月那天亲手拨一次） |
| 8 | 空表态 / 占位态 | 清空排班 / 清掉快照各看一次 |
| 9 | 深浅色 | 三张卡各一张深色图 |
| 10 | 改色后 | **先 `am force-stop com.miui.home` 再验**（小米桌面按资源 id 缓存 drawable） |

采图沿用 `work/cardcap_*.png` 那套（adb 截图 + 裁切），不新增工具。

> **视觉工装的屏单（`app/tool/visual/visual_screens.dart`）本轮不改**：它渲染的是 Flutter
> 界面，而本轮界面全在原生 RemoteViews 里，工装看不见。等价的「眼睛」就是上面的真机卡面截图
> —— 与 v0.8.5~v0.8.7 三版的做法一致。

---

## 13. 收尾

- 版本号两处同步：`app/pubspec.yaml` → `0.8.8+99`、`app/lib/core/app_info.dart` → `0.8.8`
- 更新日志（`app/lib/features/profile/app_dialogs.dart`）prepend `v0.8.8`、删最旧、保持 10 条；
  **要写明「旧小组件会消失、请重新添加」**
- `AGENTS.md`：小组件那一段**整体改写**（五档 → 三张固定卡、窗口、胶囊配方）；requestCode 段
  （基数 32 → 64、上限 6710 万 → 约 3350 万）；版本史加 `0.8.8`
- `README.md` / `PRODUCT_SPEC.md`：小组件条目改写（三张卡、怎么找、不可拉伸）
- 构建、提交推送、`release.ps1` 发 Release（**注意 `GH_CONFIG_DIR`** 要指回真实 AppData）
- **不要跑 `dart format`**（工具链是新版 tall style，一跑就重排整个文件）

---

## 14. 风险与坑

1. ~~42 格的胶囊位图是本轮唯一未验证的技术假设~~ **已真机探针验证（2026-09-20，Task 1，
   Redmi 25102RKBEC / HyperOS）**。探针 = 42 槽 `GridLayout`（7 列 × 6 行）+ 每格一张
   40×18dp 胶囊位图，跑了两档：

   - **42 张颜色各不相同**（最坏情况，无任何去重可能）：parcel **17780 字节**；
     `dumpsys appwidget` 里 `views_bitmap_memory = 1088640`（= 42 × 120 × 54 × 4，
     即 42 张**全数送达宿主**）；logcat **无 `TransactionTooLargeException` /
     `BadParcelableException` / RemoteViews 报错**。**位图是走 ashmem 出带的，不占 binder
     事务** —— 1.09MB 像素数据只换来每张约 164 字节的动作头
     （这个数出自两档之差：`(17780 − 11876) / (42 − 6)`，不是 `17780 / 42`）。
     **但画面只画出 42 格里的 23 格**（`work/probe_month42.png`：格子 1~19 只有数字、
     没有胶囊；20~42 有）。**—— 这一条是单次观测（n=1）：同 payload 重跑了一次，
     只有 `parcel bytes` 与 `views_bitmap_memory` 这两项复现了，「23」这个格数没有第二次截图。**
     宿主侧对应的是 `[REUSE-PROBE] cache HIT->clone`，
     复用键 `com.daoban.shiftassistantpro:2131427407:-1`（cell 布局 2131427407，
     根布局 2131427406）。
   - **只有 6 张不同颜色**（对齐真卡片的 5~6 种班次色）：parcel **11876 字节**；
     `views_bitmap_memory = 155520`（= 6 × 120 × 54 × 4）；**42 格全画出来**
     （`work/p6.png`：7 列 × 6 行、42 个胶囊一个不缺）。这一档同样是**单次观测**。
   - **`GridLayout` 排 42 格在两档里都是干净的 PASS**：7 列 × 6 行，
     顺序与 1..42 的数字全部正确 —— **这条是两档各一张截图（n=2）**，
     也是本轮唯一被重复观测过的结论。

   **结论：月历按淡染胶囊做。** 硬约束是「**同一班次色必须共用同一个 Bitmap 对象**」——
   `WidgetChip` 的 `LruCache` 已按 `color:w:h:radiusPx` 保证这一点，同色只会在宿主里留一份；
   于是**每张卡的不同颜色数要压在个位数**。
   ⚠️ **这条「个位数」是选定的安全余量，不是量出来的阈值**：整轮只采了两个点 ——
   **6 种色（全画出）与 42 种色（只画一部分）**，**7~41 之间一格没测**，
   残缺渲染的边界在哪是未知的。所以：① 别把「6 张能过」读成「个位数以内一定没事」，
   它只是「离已知会坏的 42 远一点」；② 上面那条残缺渲染**只在「不同颜色数很多」时出现，
   而且它是宿主侧的渲染限制，不是 payload 发不出去**。Task 9 的采图清单里**加一条**：
   「6 行月 + 用户全部班次色」整屏截图并逐格核对 —— 自定义班次多的用户颜色种类会变多，
   那才是唯一能把 7~41 这段边界填上的实测机会。

   降级梯子保留在下面备查（**本轮没有**走梯子）：
   ① 静态 `<shape>` + `setBackgroundTintList`（两层：外描边 / 内填充）。
   ⚠️ 本轮想顺带核 `View.setBackgroundTintList` 是不是 `@RemotableViewMethod`，**没核成**：
   SDK 的 `android.jar` 只有 stub（方法体是 `throw new RuntimeException("Stub!")`），
   而 `platforms/android-36/data/annotations.zip` 里**根本没有 `RemotableViewMethod` 这一条**
   （它是 `@hide` 注解，不进外部注解包）。**要用这条梯子必须自己真机验一次。**
   ② 月历格子退回**彩色文字**（不画胶囊）—— App 自己在窄格时就是这么降级的（v0.7.1 有先例），
   代价是浅色主题下对比度要靠卡片底兜
2. **4×1 只有 5dp 余量** —— 上一版「63dp 那档第二行被裁」是同一类病，别靠估算放行。
3. **跨月的月份标题**：`months` 查不到就隐藏，绝不借上个月的（这是本仓「不让卡片理直气壮地
   写错」那条纪律的又一入口）。
4. **requestCode 基数 32 → 64**：论证与 `REQ_SLOTS_PER_WIDGET` 的 KDoc 必须一起更新，
   别留下一个算不平的注释（上一轮刚修过一次同类）。
5. **删掉旧 provider 是用户可见的一次性代价** —— 更新说明必须写，否则用户会以为是 bug。
6. **可见性两个方向都要设满**：三张卡都在同一张布局里被多种状态复用（正常 / 空表 / 降级 /
   行数不满），宿主 `reapply` 时只重放**新**动作，漏设的视图会保持上一次的状态（本仓修过两次）。
7. **`days[]` 变长**：`boundaries` 从约 40 条涨到约 200 条；若真机上 push 有可感延迟，
   先量再改，不预防性优化。
8. 小米桌面按资源 id 缓存 drawable：**改色后验证前先 `am force-stop com.miui.home`**
9. **不要跑 `dart format`**；bash 里构建必须 `export ANDROID_HOME/JAVA_HOME/GRADLE_USER_HOME`
   指向 `toolchain/`
10. **装真机必须 `flutter build apk --release`**（手机上是 release 密钥签的）

---

## 15. 修订记录

| 日期 | 变更 |
|---|---|
| 2026-09-20 | 初稿。三张固定卡与两个尺寸决策来自用户同日三轮反馈；「丑」的三条机械原因由代码与真机截图逐条对上 |
