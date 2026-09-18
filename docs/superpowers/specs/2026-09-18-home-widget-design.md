# 桌面小组件（三档尺寸） · 设计规格

- 日期：2026-09-18
- 目标版本：`0.8.4+95`（AI 只改末位 `Z` 与 `build`；`X.Y` 由用户决定）
- 状态：待评审
- 来源：用户反馈（原话：「上回不是说还要加个桌面小组件的功能吗？现在我手机也连接了ADB模式，你看一下怎么实现？」）
- 前置：无。`2026-09-13-design-language-v2-design.md`（令牌与设计理念）是本文视觉部分的裁决依据

---

## 1. 背景与目标

这是 App 第一次把界面画到**自己的进程之外**。

### 1.1 现状

仓库里没有任何小组件代码：没有 `AppWidgetProvider`、没有 `res/xml/appwidget_info.xml`、没有任何 `RemoteViews` 布局，`pubspec.yaml` 里也没有 `home_widget` 之类的桥接插件。原生侧现有 9 个 Kotlin 文件 1822 行，全部是闹钟链路。

### 1.2 三条决定形状的既成事实

1. **Flutter 画不进桌面小组件。** 小组件由启动器进程（本机是 `com.miui.home`）用 `RemoteViews` 渲染，可用视图是一份固定白名单：布局只有 `FrameLayout` / `LinearLayout` / `RelativeLayout` / `GridLayout`（**没有 `ConstraintLayout`**），控件只有 `TextView` / `ImageView` / `Button` / `ProgressBar` / `Chronometer` 等，**白名单之外的子类一律不行**。所以这是**第二套原生 UI**，Flutter 那套设计语言只能逐项翻译，不能复用。
2. **桌面小组件里「真背景模糊」物理上做不到。** `RemoteViews` 采不到壁纸背后是什么。App 里早就有这套模拟配方 —— `AppTokens.glassSurface(isDark, blurOn: false)`（「高级材质」关闭时走的那一路）。
3. **数据不需要后端，且仓库里已有同族范式。** Dart 算好一份快照写进 SharedPreferences，原生读它渲染 —— 这就是 `AlarmStore`（落盘清单）+ `BootReceiver`（重启后按清单重排）已经在用的套路；跨天自动翻页也能挂到现有 `AlarmScheduler` 的「自续排」思路上。

### 1.3 目标

桌面上放一块卡片，一眼看到**今天的班次与时间**；拉到中等尺寸看**未来三天**；拉到最大看**一周一览**。跨天自动翻页，App 里改了排班立刻跟着变，**不打开 App 也不会显示错的班**。

### 1.4 非目标

见 §10。

---

## 2. 四个已定决策（来自 2026-09-18 的头脑风暴）

| # | 决策 | 理由 |
|---|---|---|
| ① | **三档尺寸自适应**：小=今天、中=三天、大=一周 | 用户明确要「三套都要」。桌面小组件的价值就在于用户自己拉大小 |
| ② | **原生近似**，不走 Flutter 位图渲染 | 位图路线换来的是「像素级一致」而非「更接近真玻璃」（事实 2），却要付 3 尺寸 × 明暗 × 双语的缓存与后台引擎代价 |
| ③ | **刷新粒度＝跨天 + 班次边界** | 不做逐分钟倒计时。一天约 3~5 次刷新，省电，且不会被 MIUI 的后台限制掐出「数字卡住不动」 |
| ④ | **深浅色跟随 App 的主题设置** | 不额外出配置页；卡片与 App 永远同调 |

---

## 3. 核心架构：一份由 Dart 预渲染的快照

**一句话：Dart 算好一切，原生只排版。**

### 3.1 快照内容

写在 SharedPreferences（文件 `shift_widget`，键 `snapshot`），与 `AlarmStore` 同族。

```jsonc
{
  "v": 1,                          // 快照格式版本；原生解析不了就按「无快照」处理
  "genAtMs": 1758182400000,        // 生成时刻，诊断用
  "lang": "zh",
  "themeMode": "system",           // system | light | dark —— 注意是「模式」不是解析结果
  "accent": 4284319464,            // 主色 ARGB，大卡「今天」那格描边用
  "hasSchedule": true,
  "emptyHint": "还没有排班，点一下去设置",   // hasSchedule=false 时用
  "labels": { "today": "今天", "tomorrow": "明天", "dayAfter": "后天" },
  "boundaries": [                  // 未来所有「该刷新了」的绝对时刻，升序；见 §6.2
    1758182400000, 1758198600000, 1758268800000
  ],
  "days": [                        // **恒 14 条**，按日期升序，缺的填空行
    {
      "day": 20345,                // LocalDate.toEpochDay()，与 Dart 的 dayNumber() 同口径
      "weekday": "周四",
      "dateShort": "9月18日",
      "hasShift": true,
      "isRest": false,
      "shiftName": "白班",
      "shiftAbbr": "白",
      "color": 4283208703,         // 班次色 ARGB；hasShift=false 时为 0
      "timeRange": "08:30 – 20:30" // 已是完整显示串；跨午夜时为「20:30 – 次日08:30」；
                                   // 无时间时为 null。见下方说明
    }
  ]
}
```

`timeRange` 走**既有的** `L10n.timeRange(start, end, crossesMidnight)`，不新造。那个 helper 的注释写得很清楚为什么整串必须交给 `t()` 而不是拼前缀：

> 中英两种语序不同，所以整串交给 [t] 而不是拼接前缀 —— 直接拼 `'次日'` 会在英文界面下露出中文。

初稿曾把 `startClock` / `endClock` / `nextDayMark` 三个字段分开传给原生、让 Kotlin 去拼「次日」前缀 —— 那正是这条注释警告的坑（英文会拼成 `20:30 – next day 08:30` 而不是 `20:30 – 08:30 (next day)`），且把一条 i18n 规则漏进了不变量 A 说要保持零 i18n 的那一侧。同理砍掉了 `startAtMs` / `endAtMs`：它们当初只为原生算边界而存在，边界改走 `boundaries` 之后就没有消费者了。

### 3.2 两条不变量（这份设计的地基）

**不变量 A：原生零 i18n、零日期格式化、零排班引擎。**

所有「今天 / 白班 / 08:30 / 9月18日 / 周四」都是 Dart 用现成的 `L10n` 生成好的。Kotlin 侧一个中文字符串都不出现（唯一的例外见 §8.4 的降级态，那里刻意不含任何句子）。双语只有 `l10n.dart` 一处要维护。

这也顺带否掉了「把轮转规则抄一份到 Kotlin、让原生自己算」那条路 —— 两份引擎就是两个 bug 源，而 `shift_rotation.dart` 里那套 `dayOverrides` 语义抄一遍必抄错。

**不变量 B：相对文案按「偏移」索引，不按「日期」烘焙。**

这条是踩过才知道的：快照生成于 9/18 时，`days[1]` 是「明天」；9/19 凌晨跨天刷新后 `days[1]` 变成了**今天**，而如果「明天」二字是烘焙在 `days[1]` 里的，卡片就会理直气壮地写错。

所以规则是：

- **日期固有的**（`dateShort` / `weekday` / `shiftName` / `startClock`）→ 按日期烘焙，永不腐坏：9月19日永远是 9月19日。
- **相对的**（今天 / 明天 / 后天）→ 按**渲染时的偏移**从顶层的 `labels` 里取。偏移 0 取 `labels.today`，1 取 `labels.tomorrow`，2 取 `labels.dayAfter`，≥3 直接用该天的 `weekday`。

原生判断「今天」的方式：`LocalDate.now().toEpochDay()` 去 `days` 里找同号的那条。`minSdk = 26`，`java.time` 可直接用，不需要脱糖。

### 3.3 推送时机

新模块 `lib/features/widget/widget_service.dart` 的 `WidgetService.push()` 负责生成并投递。触发点：

| 时机 | 位置 |
|---|---|
| App 启动 | `home_shell.dart` 首帧后（与 `AlarmService.requestPermissions()` 并排） |
| 排班数据变化 | 订阅 `activeScheduleProvider`，每次下发都 push（含按天改班、编辑保存、切换方案） |
| 外观变化 | 主题模式 / 主色 / 语言变更后 |

投递走既有的 `settingsChannel`（`com.daoban.shiftassistantpro/settings`），新增方法 `widgetPushSnapshot`。快照用**普通字符串**传，不传 Map —— 原生只需原样落盘，解析在原生读的时候做。

---

## 4. 原生侧：四个新文件，一个文件一件事

| 文件 | 职责 |
|---|---|
| `ShiftWidgetProvider.kt` | `AppWidgetProvider`。收 `onUpdate` / `onAppWidgetOptionsChanged` / 自定义 `WIDGET_REFRESH` action → 读快照 → 分档 → 渲染 → 排下一次刷新 |
| `WidgetStore.kt` | 快照读写。`AlarmStore` 的同族：解析失败按「无快照」处理并记 `AlarmLog`，一条坏数据不该让整个卡片消失 |
| `WidgetRenderer.kt` | 纯渲染：`(快照, 档位, 尺寸, 明暗) → RemoteViews`。与 Provider 分开是为了可测（§11） |
| `WidgetRefreshScheduler.kt` | 算下一个边界时刻 + 排精确闹钟，排完自续排 |

`WidgetRenderer` 与 `WidgetRefreshScheduler` 都不碰 `Context` 之外的系统状态，逻辑尽量挤成纯函数 —— 这块是**算错了不报错、只显示错**的那类代码，与 `info_card_metrics.dart` 同一性质。

---

## 5. 三档布局与分档

### 5.1 分档规则

纯函数 `WidgetTier.pick(minWidthDp, minHeightDp)`：

| 档 | 条件 | 内容 |
|---|---|---|
| 大 | 宽 ≥ 300 **且** 高 ≥ 260 | `GridLayout` 4×2 迷你日历，第八格空 |
| 中 | 宽 ≥ 220 **且** 高 ≥ 130 | 三行，每行「相对称法 日期 · 班次 · 起止」 |
| 小 | 其余 | 今天一张牌 |

**高度闸门是必要的，不是一个保险**：4×1 那种尺寸宽度轻松过 300，但只有 ~86dp 高，三行装不下会静默裁掉最后一行 —— 这正是 `info_card_metrics.dart` 那条注释里踩过的坑（「卡片装不下时只在卡内静默滚动，用户看到的是最后一行被裁掉」）。

尺寸从 `AppWidgetManager.getAppWidgetOptions(id)` 的 `OPTION_APPWIDGET_MIN_WIDTH` / `MIN_HEIGHT` 取。

**阈值需要真机标定一次**：本机 400dp 宽、MIUI 4 列网格，估算 2×2 ≈ 180×180dp、4×2 ≈ 380×180dp、4×4 ≈ 380×380dp。实施时先用 `AlarmLog.info` 把实测的 `options` 打出来（`AlarmLog.info` 只写 Logcat，adb 直接可读），对着三档各拉一次标定后再定死，不凭估算上线。

### 5.2 逐档内容

**小（今天一张牌）**

```
┌────────────────────────┐
│ 今天 · 周四      9月18日 │
│ ▍白班                   │
│   08:30 – 20:30         │
│ ─────────────────────  │
│ 明天  夜班 20:30–次日08:30│
└────────────────────────┘
```

- 6dp 班次色条（与信息卡左侧那根同宽同配方：`pillOf(6)`）
- 班次名走 `bigNumber`（24 / w700）
- 分隔线 1px，`inkMuted` 的 12% —— 层级只靠明度（设计理念 §3），所以是「浅一档的线」而不是「另一种颜色的线」

**中（未来三天）**：三行，行首 8dp 色点，今天那行班次名加粗。行内 `今天 9月18日 · 白班 · 08:30–20:30`。

**大（一周一览）**：`GridLayout` 4 列 × 2 行，照抄日历页格子配方 —— 上行日期（`cellDateSm` 13/w600），下行班次胶囊（班次色底 + `shiftAbbr`，文字色走 `AppTokens.onSolid`），被「今天」那格主色描边。第八格留空。

「一周」是**从今天起连续 7 天**，不是「本周一到周日」。理由有二：快照的结构本来就是 `days[0] = 今天`（§3.1），换成自然周要额外引入「一周从周几开始」的判断，而那个判断在不同文化下还不一样；且三档之间「从今天起」是统一心智 —— 小卡看今天、中卡看今天起三天、大卡看今天起七天。

> 抄日历页而不是另起一套，是 `AGENTS.md` 与项目记忆里那条「新界面自动融入设计语言」的直接应用：近处有同类件就抄近处的配方。

---

## 6. 刷新链

### 6.1 四个触发点

| 触发 | 路径 |
|---|---|
| App 内数据变化 | Dart `push()` → 原生写盘 + `updateAppWidget` 全部实例 + 重排边界闹钟 |
| 跨天 00:00 | 精确闹钟 → 重渲染（靠 §3.2 不变量 B 自动右移一格） |
| 今天班次的开始 / 结束时刻 | 同上，只影响「进行中 / 已结束」这类状态 |
| 开机 / 装更新 / 刚添加到桌面 / 改尺寸 | `BootReceiver` 补一次重排（与现有闹钟重排并排）+ `onUpdate` / `onAppWidgetOptionsChanged` |

**自续排**：每次刷新后只排「下一个」边界，不一次排一堆 —— 与 `AlarmScheduler` 重复闹钟续排同一个套路。

### 6.2 下一个边界怎么算

**日期算术留在 Dart，原生只做一次线性扫描。**

快照里带 `boundaries` —— 生成时刻起、14 天窗口内所有「该刷新了」的绝对时刻（每天的本地零点 + 各工作班次的 `startAtMs` / `endAtMs`），升序排好。原生：

```
下一个边界 = boundaries 里第一个 > now 的值；都没有就用「下一个本地零点」
```

这样 `nextBoundary` 在原生侧只剩一个 `for` 循环加一行 `LocalDate.now().plusDays(1).atStartOfDay(zone)` 兜底（窗口耗尽时用，`java.time` 一行就够）。**为什么值得这么绕一下**：这几个时刻的算法（本地零点怎么跨时区、跨午夜班次的结束落在次日、休班不产生边界）正是 §11 里那类「算错了不报错」的逻辑 —— 把它放在有 170 条测试的 Dart 侧，比在 Kotlin 里新起一套单测基建划算得多（见 §11 关于原生单测的决定）。

### 6.3 权限退化

用 `setExactAndAllowWhileIdle`；`canScheduleExactAlarms()` 为 false 时（用户在系统里收回了「闹钟和提醒」权限）退化成 `setAndAllowWhileIdle`，绝不抛异常、绝不静默不排。跨天翻页本来就不要求秒级准时，退化后可接受的偏差是「早上看到昨天」而不是「卡片永久停住」。

**`updatePeriodMillis` 设 0** —— 不要系统轮询（它是 30 分钟一次且被系统限流，纯浪费电）。若真机上发现 MIUI 把自排闹钟吃掉，再加 30 分钟轮询兜底；这是留给实测的开关，不预先加。

---

## 7. 交互

| 点哪 | 去哪 |
|---|---|
| 小卡 / 中卡整块、大卡第八格 | 普通启动 `MainActivity`（落到日历页） |
| 大卡某一格 | 启动 `MainActivity` + `EXTRA_WIDGET_DAY = epochDay`，打开 App 并**定位到那天** |

「点某天跳到那天」照抄 `pendingTodoId` 那条既有链路，冷热启动分两路：

- **冷启动**：`MainActivity` 的 companion object 加 `pendingWidgetDay: Long = -1L`，Dart 启动后经 `getWidgetLaunchDay` 读走（与 `getPendingAlarm` / `getPendingTodoId` 同款）。
- **热启动**：`onNewIntent` 里不写静态变量，直接经 channel 推给已经在跑的 Dart（与 `onTodoTapped` 同款）。热启动若走静态变量，正在跑的 Dart 根本不会再去读它 —— 这是既有代码注释里已经写明的那条分界。

Dart 侧新增 `WidgetService.widgetLaunchRequested`（`ValueNotifier<DateTime?>`，与 `openTodoRequested` 同款）。两个消费者：

- `home_shell.dart` —— 若当前不在日历 tab，先切过去（照抄 `_openTodoPage`）
- `calendar_screen.dart` —— 收到后设 `_month = DateTime(d.year, d.month, 1)` 与 `_selected = dateOnly(d)`

---

## 8. 视觉配方（逐项从令牌翻译）

### 8.1 卡片底

**用 App 自己的 surface 色、高不透明度**，不照抄 `AppTokens.glassSurface(isDark, blurOn: false)`：

| | 亮 | 暗 |
|---|---|---|
| 渐变起（左上） | `surfaceLight` 白 97%（`#F7FFFFFF`） | `surfaceDark` 97%（`#F716161E`） |
| 渐变止（右下） | 白 96%（`#F5FFFFFF`） | `surfaceDark` 94%（`#F016161E`） |

做成两张 `<shape>` drawable 静态引用。Android 的 `<gradient android:angle>` 是**逆时针**且 0 = 左→右，所以 Flutter 的 topLeft→bottomRight 对应 `angle=315`。

> **这一处是初稿写错、真机实测才发现的。** 初稿抄的是 `glassSurface(isDark, blurOn: false)`（亮 白 82%→60%、暗 白 16%→8%）—— 那是 App 里「高级材质关闭」时的那一档。它在 App 里成立，是因为它垫在**自己的中性底色**（`bgLight` / `bgDark`）上；而小组件垫的是**任意壁纸**，`RemoteViews` 又采不到壁纸。
>
> 后果在真机上很直接：深色卡（白 16%）叠在浅色壁纸上 ≈ 半透明，配 `inkDark`（近白）文字**几乎读不出来**。2026-09-18 首张真机截图（HyperOS「自定义时段」深色 + 浅色壁纸）确认：结构全对、数据全对，字看不清。
>
> 高不透明度让**对比度主要由卡片自己决定** —— 注意是「主要」不是「无关」，那 3~6% 的透光仍在，写「与壁纸无关」是过头话（`RemoteViews` 采不到壁纸，不该再添一条假保证）。这样 §2 决策 ④ 那个「深浅色跟随 App 主题设置」才真正安全：卡片只是换个底色，不依赖背后是什么。这也符合设计理念第 6 条「**可读性优先于观感**：任何压在色块上的文字必须过 WCAG AA 4.5:1」。
>
> **第二轮（评审实算，改到最终值）**：先定的「亮 95%→88% / 暗 90%→80%」仍不够 —— 透明那一端还透 10~20% 壁纸，`wg_muted_dark`（`#9A9AB0`）叠在 80% 端 + 纯白壁纸上只有 **3.46:1**，**不过 AA**（踩线的是时间串）。故再提到上表的 **94~97%**（壁纸只透 3~6%），最坏情况两头都过 AA：暗 94% + 纯白壁纸 → muted 5.60:1 ✓；亮 96% + 纯黑壁纸 → muted 4.57:1 ✓。真机逐像素复测：暗卡底部 muted 实测 5.95:1。

### 8.2 描边 —— 一处**有意偏离** `glassBorder`

`AppTokens.glassBorder` 在亮色下是白 90%。它在 App 里成立是因为卡片底下是 `bgLight`（#F5F6FA）那层浅灰，白描边能勾出轮廓；**在壁纸上它就是对白底描白边，直接隐身**。

所以小组件走 `navBorder` 那条思路（仓库里同一问题的既有答案，注释原话：「白底上白描边会隐身」）：

- 亮：`inkLight` 14%
- 暗：白 16%

### 8.3 其余

- **圆角** 22dp（`radiusL`，「卡片 · 列表行 · 提示条」那一档）
- **投影**：`setFloat(rootId, "setElevation", 10f)` 让系统画。`<shape>` 做不出 `BoxShadow`，而 9-patch 阴影要出图；elevation 白嫖，暗壁纸上不明显也无所谓
- **色块要任意 ARGB + 圆角** —— 这是本设计里**唯一需要在真机上先验证**的技术点，见 §13.1

### 8.4 不依赖 `-night` 限定符

`RemoteViews` 由**宿主进程** inflate，`-night` 之类的限定符在宿主进程里的解析顺序各家 ROM 不一致。所以：

- 明暗一律在渲染时**显式选资源**（`setBackgroundResource` / `setTextColor`），不靠限定符
- `themeMode == "system"` 时，渲染时读宿主 `Configuration.uiMode` 的 `UI_MODE_NIGHT_*` 现算 —— 这样「跟随系统」永远是新鲜的，用户傍晚切换深色模式不必等下次 push
- `themeMode == "light" | "dark"` 时用快照里烘焙的值

---

## 9. 边界与容错

| 情况 | 表现 |
|---|---|
| 快照不存在（装了 App 但没打开过） | 降级态：App 图标 + `applicationInfo.loadLabel(packageManager)`。**只有图标与系统给的名称，不含任何句子**，所以不变量 A 不为它破例 |
| 快照过期（`LocalDate.now().toEpochDay()` 不在 `days` 里，即 App 超过 14 天没打开） | 同上降级态 |
| `hasSchedule == false`（空白表方案） | 渲染快照里的 `emptyHint`，点击仍开 App |
| 休班 / 无时间的班次 | `timeRange` 为 null，布局按「无时间行」收缩，不显示空白破折号 |
| 跨午夜班次 | `timeRange` 由 `L10n.timeRange` 产出 `20:30 – 次日08:30`（英文 `20:30 – 08:30 (next day)`），原生原样贴 |
| 快照 JSON 解析失败 | 按「无快照」处理 + `AlarmLog.error`（`AlarmStore.all` 的同款作风） |
| 多个小组件实例 | 每次刷新遍历 `getAppWidgetIds`，逐实例按各自 options 分档渲染 |

**为什么快照存 14 天而不是 7 天**：跨天时 widget **不能**重算（不变量 A 的代价），它只能拿 `days` 对表右移。大卡要 7 天，14 天给「App 两周没打开」留余量 —— 而实际上，一个倒班的人几乎每天都会开一次 App 看班表或收闹钟，14 天绰绰有余。

---

## 10. 明确不做

- **逐分钟倒计时**（决策 ③）。MIUI 上很可能被限流成不准时 —— 数字卡住不动比没有更难看
- **小组件配置页**（决策 ④）。不留「长按小组件选显示内容」的口子
- **Flutter 位图渲染整张卡片**（决策 ②）
- **循环滚动动画 / 多个班次轮播**：`RemoteViews` 没有可靠的动画通道
- **锁屏小组件 / 负一屏小组件**：MIUI 的负一屏是自有体系，不接标准 `AppWidgetProvider`
- **`previewImage` 出图**：先只用 `android:previewLayout`（API 31+，本机够），看过 MIUI 选择器里的实际效果再决定要不要出 PNG
- **点大卡某格以外的深度跳转**（比如点班次名直接进编辑器）

---

## 11. 测试与验证

现有测试**只增不减**。

| 层 | 用例 |
|---|---|
| `widget_snapshot_test.dart`（新建，纯 Dart） | `days` 恒 14 条 · 空白表产 `hasSchedule:false` 且 14 条空行 · 休班行 `startAtMs` 为 null · **跨午夜班次 `endAtMs` 落在次日**（`endMinute < startMinute` 与 `endMinute ≥ 1440` 两种表示都要盖到）· 双语 · 按天改班那天反映到快照里 · `themeMode` 原样透传 |
| JSON 往返 | 生成的快照 decode 回来字段齐全、类型正确（原生按 `optXxx` 取，类型错了会静默变默认值） |
| `boundaries`（纯 Dart） | 升序且无重复 · 每天的本地零点都在 · 跨午夜班次的结束落在次日 · 休班不产生 start/end 边界 · 14 天窗口耗尽时只剩零点 · 窗口之外不出现 |

**原生侧不引入 Kotlin 单测基建（本轮的决定，取代初稿的「建议引入」）。**

依据是两条查证：`android/app/src/test/` 源集不存在，且 Gradle 缓存里没有 JUnit —— 引入要走一次网络解析，为一个新子系统铺测试基建的成本不成比例。

更关键的是，原本想盖的两组逻辑已经被 §6.2 分摊掉了：日期算术搬回 Dart，由现成 170 条测试兜底；剩下的 `WidgetTier.pick` 是四次整数比较，**判错了会立刻在真机上表现为「档位不对」**，属于肉眼可见而非静默错误，由本节的阈值标定覆盖。若将来原生逻辑长到「算错看不出来」的量级，再引入不迟。

**真机验证手段**（用户已连 ADB，`adb.exe` 在 `toolchain/android-sdk/platform-tools/`）：

```bash
adb shell am broadcast -a com.daoban.shiftassistantpro.WIDGET_REFRESH -n com.daoban.shiftassistantpro/.ShiftWidgetProvider
```

- `adb exec-out screencap -p > work/widget.png` 截图看图（三档各一张、明暗各一张）
- `adb shell dumpsys appwidget | grep -A5 shiftassistant` 看注册状态与 options
- `adb logcat -s ShiftAssistant` 读 `AlarmLog.info` 打的实测尺寸与刷新时刻

---

## 12. 收尾清单（照 `AGENTS.md`）

- `PRODUCT_SPEC.md`：§2 功能清单补「桌面小组件」；抬头版本号跟着走
- `README.md`：功能清单补一条；配图管线（`scripts/make_update_images.py`）看是否要加一张小组件截图
- `AGENTS.md`：「目录架构地图」加 `lib/features/widget/`；「关键决策与坑」加一条（快照约定 + 不变量 B 那条腐坏坑）；版本史加 `0.8.4(+95)`
- 更新日志（`features/profile/app_dialogs.dart`）：prepend 新版本、删最旧一条、保持 10 条；测试版条目原样写
- `app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 版本号同步（`app_info_test.dart` 盯着）
- 打完版本 `git tag v0.8.4`
- 按项目记忆：构建 APK、提交推送、`release.ps1` 发 Release（注意 `GH_CONFIG_DIR` 那条坑），不等用户测试

---

## 13. 风险与坑（实施时挨个对照）

1. **色块要任意 ARGB + 圆角（本设计唯一的技术未知）。** `<shape>` 只能在布局里静态引用，运行期构造的 `GradientDrawable` **传不进 `RemoteViews`**（官方白名单限制）。方案：按 `(色, 圆角, 尺寸)` 缓存一张小 `Bitmap`，走 `setImageViewBitmap` —— 这是官方文档点名的可行做法，代价是几 KB 内存，一天刷几次可以忽略。**降级方案**：方形色条 + `setInt(viewId, "setBackgroundColor", color)`。实施时先做一张最小验证卡片跑通这条路，再铺开三档布局。
2. **不变量 B（相对文案腐坏）** —— §3.2。这条漏了不报错，只在跨天之后显示错，而且**只在跨天之后**，开发时打开 App 永远看不到。
3. **`ConstraintLayout` 不存在** —— §1.2。写布局时手会习惯性伸向它，报的是运行期 `ClassNotFoundException`，不是编译错误。
4. **高度闸门不是保险** —— §5.1。宽高是**与**关系；只看宽度会让 4×1 走到中档然后静默裁行。
5. **快照是「模式」不是「解析结果」** —— §8.4。把 `system` 提前解析成 `light`/`dark` 存进快照，会让「跟随系统」变成「跟随生成快照那一刻的系统」。
6. **热启动别用静态变量** —— §7。既有代码注释里已写明这条分界，抄的时候别只抄一半。
7. **不要跑 `dart format`** —— 工具链是新版 tall style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `flutter analyze`。
8. **构建环境变量**：bash 里构建必须 `export ANDROID_HOME/JAVA_HOME/GRADLE_USER_HOME` 指向 `toolchain/`，否则 Gradle 会去 `~/.gradle` 下载到超时。
9. **本机 `getprop` 是伪装过的**（`ro.build.version.sdk` 报 21、`release` 报 6.0.1，而实际安装的包 `targetSdk=36`）。判断系统能力时以 `dumpsys package` 与实测行为为准，别信 `getprop`。
10. **MIUI 的「后台弹出界面」权限**与本功能无关，但别在调试时顺手把它当成因 —— 小组件不弹 Activity，只画 RemoteViews。

---

## 14. 修订记录

| 日期 | 变更 |
|---|---|
| 2026-09-18 | 初稿。四个已定决策来自同日头脑风暴；`RemoteViews` 白名单与 drawable 限制经查证后写入 §1.2 与 §13.1 |
| 2026-09-18 | 写实施 plan 时改：§6.2 的边界计算从原生搬回 Dart（快照新增 `boundaries` 字段），§11 随之定下「本轮不引入 Kotlin 单测基建」。触发原因是查证到 `src/test/` 源集不存在且 JUnit 不在 Gradle 缓存里 |
| 2026-09-18 | 同日再改：每日的 `startClock` / `endClock` / `nextDayMark` / `startAtMs` / `endAtMs` 五个字段合并成一个预渲染的 `timeRange`。查证到 `L10n.timeRange` 已存在且其注释明确警告过「拼前缀会在英文界面下露出中文」，初稿那组分字段的写法正踩在那里 |
| 2026-09-18 | 实做期两轮真机/评审回修 §8.1 卡片底：初稿的 `glassSurface(blurOn:false)`（暗 白 16%→8%）在任意壁纸上几乎透明、字读不清，先改 surface 色 95%→88%（暗 90%→80%），评审实算指出透明端仍不过 AA（muted 3.46:1），最终定在 **94~97%**；同时删掉「对比度与壁纸无关」的过头话、改为「主要由卡片自己决定」并写入最坏情况实算 |
| 2026-09-18 | 收尾（Task 8）补记实施 plan 自审的一处差异：§4 的「四个原生新文件」实为**五个** —— `WidgetTier.kt` 独立成文件（`enum WidgetTier` + `pick(widthDp, heightDp)` 只干「分档」这一件事），免得 `WidgetRenderer` 同时管分档与排版两件事 |
