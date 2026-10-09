# 动画与流畅性 · 第一轮（每帧重建的收口）设计

- 日期：2026-10-10
- 起点：v0.10.19 真机测完之后的用户提问 ——「APP 内所有动画、所有界面动画的流畅性，
  以及功耗、后台功耗占用，有没有优化空间？尤其是流畅性。」
- 这一轮的结论来自**一次只读排查 + 四个一次性探针**（`app/tool/probe/`，不随这一轮入库，
  跑完即删）。规格里出现的每一个数字都是量出来的，不是估的。

## 1. 目标

把「每一帧到底做了多少事」降下来。**不改任何观感、不动任何交互语义、不碰原生侧**——
这一轮只做「同样一帧画得更少」这件事。

## 2. 实测基线（这一轮的全部依据）

| 指标 | 量出来的值 | 怎么量的 |
|---|---|---|
| 液态档**一帧重建的 widget 数** | **436** | `debugOnRebuildDirtyWidget`，点日期起飞行 |
| 标准档同一场景 | **6** | 同上 |
| `lunarOf()` 单次 | **22~41 µs** | 纯 Dart 计时 |
| 一屏 42 格 lunar 转换 | **1.47 ms** | 同上 |
| 光晕 tick 那一帧重绘的绘制节点 | **139**（静止帧 0） | `debugOnProfilePaint` |
| 光晕 tick 的显示列表录制 | **≈1.2 ms**（宿主） | 60 帧平均 94µs vs 冻住 34µs |
| 一次 `rescheduleAll` 的跨端调用 | **101** 次（46 排闹钟 + **48 日志**） | 假通道计数 |
| `buildWidgetSnapshot`（224 天） | **46 ms**，47.7 KB | 纯 Dart 计时 |
| `tz.initializeTimeZones(latest_all)` | **21 ms**（宿主），在首帧之前 | 纯 Dart 计时 |
| 切 tab | 非当前页**被销毁**，切回重建 | 按类型断言页面在不在树上 |

三处结论：

1. **最大的一处在日历页**：液态档把每帧动画状态（`_flightPos` / `_vx` / `_vy` /
   `_rangeTipPos`）放进了整页的 `State`，于是「点日期起飞行」「按住拖块」「长按拖选」
   这三种交互**全程每帧重建整页**（顶栏 + 42 格 + 信息卡）。
2. **其次是三个「每次重建都要重算」的东西**：农历转换（42 次）、本月统计 / 有无排班 /
   有无调班（约 93 次链查询）、一个 `TextPainter`。
3. **光晕背景每 340ms 让整页重绘一次**：`CustomPaint` 底下没有 `RepaintBoundary`。

## 3. 范围与档位

- **A 档（低风险，改完基本零风险）**：`lunarOf` 缓存 · 删掉每闹钟一条日志 ·
  小组件快照缓存/去抖/不重复推 · 启动去掉 `tz.initializeTimeZones`。
- **B 档（结构性，这一轮的核心）**：每帧状态外置 · 42 格挤压场改成「只重算矩阵」·
  光晕改成自己一层（不再让整页跟着重画）+ 交互时暂停 · 那五样按月缓存。
- **不在这一轮**：见 §7。

⚠️ **启动去掉 `tz.initializeTimeZones` 需要先核实**：`alarm_service.dart` 顶部导入的是
`timezone/data/latest_all.dart`，而全仓没有任何 `zonedSchedule` / `TZDateTime` 调用。
实施第一步就是核实这一点（grep 一次），确认后再删；**不确认不许删**。

## 4. 设计

### 4.1 每帧状态外置（B 档核心）

**现状**：`_flightPos` / `_vx` / `_vy` / `_rangeTipPos` 是 `_CalendarScreenState` 的字段，
每帧 `setState`（`calendar_screen.dart:521` 飞行 tick、`:1211` 拖动、`:1347` 带子末端回调）
⇒ 整页 `build()` 重跑 ⇒ 436 个 element 重建。

**新设计**：两个 `ValueNotifier`，**只在动画进行中写**。

```dart
/// 那枚块这一帧的状态：在哪、多快、速度是不是「活的」。
/// 不可变；每帧换一个新实例（`ValueNotifier` 默认按 `==` 比，换实例就一定通知）。
class BlockFrame {
  const BlockFrame({required this.pos, required this.velocity, required this.live});
  final Offset pos;       // 块左上角（格层坐标）
  final Offset velocity;  // px/s
  final bool live;        // 这一帧的速度有没有来源：手指在拖 / 块自己在滑
}

/// 挤压场的中心（`null` = 一层都不套）。42 格那一层读它。
final ValueNotifier<Offset?> _lensCenter = ValueNotifier<Offset?>(null);
```

**写入点**：两个 notifier 由**同一个**私有方法发布（`_publishFrame(...)`），调用点是
`_onFlightTick`、`onPanUpdate`（每帧）；`onPanStart`（`live = true`）、`onPanEnd`
（`live = false`，**速度不归零** —— 留给透镜自己衰减，这是 v0.10.15 的裁定）。
「只有一处发布」是为了让两个 notifier 不可能各说各话。

**读取点只有两处**：

- **块那一层**：`ValueListenableBuilder<BlockFrame>`，把透镜本体当 `child:` 传进去 ——
  每帧重建的只有那个闭包、一个 `Positioned` 与一个内层 `Stack`。
- **42 格那一层**：见 4.2。

**四条纪律（实施时照着做，缺一条都会出问题）**：

1. **`Stack` 的孩子必须是 `Positioned`。** 把 `ValueListenableBuilder` 直接塞进
   `_gridBody` 那个 `Stack` 里，它就成了「非定位孩子」，布局当场错。做法是：外层用
   `Positioned.fill` 包住 `ValueListenableBuilder`，builder 返回一个**内层 `Stack`**
   （`clipBehavior: Clip.none`，让透镜照旧能鼓到格子外），里面才是 `Positioned`。
   外层那个 Stack 的裁剪行为因此与今天**一字不差**（今天也只有它在裁）。
2. **`CalendarLens` 的接口一个字都不动。** 它仍然每帧收到新 props
   （`liftTarget` / `velocityLive` / `velocity`），`didUpdateWidget` 里那套 v0.10.16 的
   裁定（拖动中低通接收、松手那一帧接一次、**其余情况什么都不做**）**完全不碰**。
   这一轮动的是「谁重建」，不是「透镜怎么算」。透镜自己每帧的 `setState`（只重建它自己
   那 ~15 个 widget）照旧 —— 那点代价是它该付的。
3. **静止时一个字节都不写。** 与 `_syncBlockFlight` 今天那句「目标没变就 return」同一条
   纪律（`:469`）。写了就会让 42 格每帧都算一遍矩阵；虽然便宜，但没有理由付。
4. **只在「帧间」发布。** Ticker 回调、指针回调、带子的每帧回调都在帧外，通知（⇒
   `ValueListenableBuilder` 的 `setState`）在那些地方是安全的。但 `_syncBlockFlight`
   是在 **`LayoutBuilder` 的回调里**跑的，而那个回调发生在**布局阶段** —— 在那里写
   `ValueNotifier` 会当场报「setState() called during build」（首次出现那枚块、换月
   之后重新落位，都会走到这一支）。所以发布器要提供**两种写法**：
   `publish(...)`（帧间：记值 + 通知）与 `publishSilently(...)`（帧内：**只记值**）。
   帧内那一支**不需要通知也不会晚一帧** —— `ValueListenableBuilder` 自己在 build 时读
   `.value`，而块那一层与 42 格那一层都排在同一个 `_gridBody` 里、在它之后建。

### 4.2 那 42 格的挤压场（`LensWarpScope`）

**现状**：`_dayRows` 每帧给 42 格各算一个 `Matrix4` 并把 `warp` 传进 `_dayCell`
（`:1417`、`:1704`）；因为父层每帧重建，42 格的**内容**（三行字 + 班次胶囊 + 卡片装饰）
跟着一起重建。而内容是**与透镜无关**的。

**新设计**：把「这一格的内容」当 `child` 放进一个 `ValueListenableBuilder`：

```dart
ValueListenableBuilder<Offset?>(
  valueListenable: _lensCenter,
  child: fittedContent,          // ← 只建一次，每帧复用
  builder: (_, center, child) {
    if (center == null) return child!;
    final m = cellWarpFor(
        cellCenter: ..., lensCenter: center, cellW: ..., cellH: ...);
    // 恒等 → **一层 Transform 都不套**（与今天 `warp == null` 同一条规则）
    return m == null ? child! : Transform(alignment: Alignment.center, transform: m, child: child);
  },
)
```

- `_cellWarp`（`:1467`）从 State 方法**挪成顶层纯函数** `cellWarpFor(...)`（可单测），
  `_cellInset` 这类屏幕常量作为参数传进去。
- 每帧代价：从「436 个 element 重建」降到「42 个闭包 + 42 次矩阵算式 + 少数几个
  `Transform` widget 构造」。**格子内容一个字都不重建。**
- `ValueListenableBuilder` 的 `child:` 语义（同一个实例 ⇒ 子树不重建）是这个方案的全部
  依据 —— 别把内容写成 builder 里的临时变量。

### 4.3 光晕背景（两处改动）

**现状**：`FlowingBackground` 的 `CustomPaint(painter:, child: 整页)` 是页面的祖先，
每 340ms 一次 tick ⇒ 实测 **139** 个绘制节点重绘（含 2 层 `BackdropFilter` 重算）。
它带来的是「每 340ms 一次的固定掉帧节拍」，拖动时最容易感觉到。

**(a) 让光晕**自己一层 —— 不是给页面内容加 `RepaintBoundary`，而是把 `FlowingBackground`
改成一个 `Stack`：光晕是 `Positioned.fill(RepaintBoundary(CustomPaint(...)))`，页面内容
是它的**兄弟**（排在后面 ⇒ 仍在光晕之上，与今天「painter 先画、child 后画」的层序一字
不差）。光晕动 ⇒ 只有它自己那一层重新录制（实测那 139 → 个位数），页面内容的 layer 被
直接复用。

⚠️ **为什么不给页面内容加 `RepaintBoundary`**：`BackdropFilter` 的后台是「它之下画过的
东西」，而「边界之外的东西动了、压在边界里的模糊跟不跟得上」在引擎里有历史问题 ——
一旦跟不上，表现就是**玻璃里的模糊被冻住**（页面在动、玻璃里的底色不动），那是实打实的
观感下降。兄弟层这个形式不依赖那条行为：光晕与页面是同级的两个 layer，光晕一变整棵树
就重合成，模糊读到的一定是新的光晕。

⚠️ **说清楚 (a) 省的是什么**：它只吃掉 UI 线程那份（约 1.2ms/次的重绘录制）。压在光晕
上面的模糊**仍然会被合成器重算**（那是 GPU 的事）。要连 GPU 那份一起省，只能让光晕别动
（见 §7 的观感项）。

**验收上这件事必须单独看一眼**（§6.2）：出图核对「光晕在动的时候，压在它上面的玻璃
（信息卡 / 顶栏胶囊 / 底栏胶囊）里的模糊要跟着动」。逐像素基线能抓到大体不对，但这类
「该动的没动」在静止单帧上不一定现形，所以要专门取两帧、隔 340ms、比玻璃**内部**的变化。

**(b) `pauseWhen`**：新增可选参数 `ValueListenable<bool>? pauseWhen` —— 日历页在
「有东西在动」（拖动 / 飞行 / 带子 / 换月）时把光晕的定时器停掉，动完再起。
`_t` 在这个期间**不推进** ⇒ 恢复时不跳（不是归零重来）。

- 日历页要有一个 `ValueNotifier<bool> _interacting` 作为它的源。
- 与既有的 `freezeWhenBlurDisabled` 是**两件事**，两条判断在 `_syncRun` 里各写各的。
- 默认 `null` ⇒ 响铃界面那一处行为一字不变。

### 4.4 那五样按月缓存

**现状**：每次重建都要重算（都与选中哪天无关，只跟月份 / 链 / 宽度 / 语言 / 系统字号 /
今日待办 / 有没有调班有关）：

| 什么 | 代价 |
|---|---|
| `_monthTally(chain)`（`:213`） | 循环整月 × `shiftOn` |
| `_monthHasNoSchedule(chain, _month)`（`:1077`） | 循环整月 × `hasScheduleOn` |
| `chain.monthHasOverrideHint(_month)` | 循环整月 × `scheduleOn` |
| `infoCardTallyFits(...)`（`:2438`） | 新排一个 `TextPainter` |
| `_monthHasPendingTodos`（`:145`） | 扫全部待办 |

**新设计**：这五样的结果并进一个按月缓存的小对象，**键沿用 `_cardMetricsFor`
（`:171`）那串 key** —— 它已经包含了需要的每一项（年月 / 宽度 / 语言 / 系统字号 /
`chain.cacheKey` / hasTodoHint / hasOverrideHint）。取用点改成读缓存。

⚠️ 两条纪律：
- `chain.cacheKey` **必须在键里**（跨时段时链一变，这五样全变）。
- `hasTodoHint` / `hasOverrideHint` 也在键里，而它们正是后两样（待办徽章、调班标记）的
  判据 —— 于是「键变了就重量」这件事自洽，不需要额外的失效逻辑。

### 4.5 `lunarOf` 缓存（A 档）

- `lunar_info.dart` 加模块级缓存，键 = `dayNumber(date)`（自 epoch 天数）。
- **已核实**：`LunarInfo` 与语言无关 —— 节日名来自 `lunar_plus` 与内置的官方放假表，
  `shortLabel` / `cellLabel` / `fullDescription` 都不读 `L10n`。所以键里不需要语言。
- 上界 `_lunarCacheMax = 1024`，超了整个清掉（**不做 LRU**：请求天然按天聚集，
  清一次最多多付一屏 42 次；做 LRU 反而多一套要维护、要测的东西）。
- 受益面不止日历：`measureBottomInfoCardHeight`（整月）、`buildWidgetSnapshot`（224 天）
  走的是同一个函数。

### 4.6 删掉「每排一个闹钟就跨一次端记日志」（A 档）

`scheduleNativeAlarm`（`alarm_service.dart:526`）在每次 `invokeMethod` **之后再**
`await logInfo(...)` —— 实测一次 `rescheduleAll` 的 101 次跨端调用里 **48 次是它**。

改为：`reschedule` 收尾打**一条**汇总（排了几条、跳过几条、耗时）；单条失败仍然逐条记
（那本来就是异常路径，不砍）。

### 4.7 小组件快照（A 档）

**现状**：224 天同步构建（实测 **46 ms**）+ 47.7 KB `jsonEncode`，触发点 = 首帧 /
**每次回到前台** / 排班变 / 外观设置变（含换主色）/ 勾一条待办。

四件事：

- **(a) 农历缓存**（4.5）直接省掉其中约 7ms。
- **(b) 按天缓存**：`days[]` 只跟（链指纹、窗口两端、语言、今天）有关，与主题/主色无关
  —— 缓存它（键就取这四项），外观变化时只重新着色 + 重新 `jsonEncode`。（色号**在**
  days 里，所以「重新着色」这一步省不掉；省掉的是农历转换与字符串格式化。）
- **(c) 同一份 JSON 不重复推**：`WidgetService.push` 里比一下上次推出去的字符串，
  一样就跳过（省掉一次跨端 + 原生侧的全量重渲染）。⚠️ **「上次推出去的」这一份只在
  真的推成功之后才记** —— 失败也记的话，那条「装完新版先打开一次 App」的兜底重试就
  永远不会再试了（推失败是 fire-and-forget，只留一条日志）。
- **(d) 触发去抖**：`home_shell` 那几路 `ref.listenManual` 合并成**一处 300ms 尾去抖**
  （一次保存排班会让好几个 provider 连续发）。

⚠️ **回到前台那一次推要保留** —— 它是「装完新版必须打开一次 App」那条的兜底重试
（v0.9.18 定的）。只是它变便宜了。

## 5. 交互与观感：只有一处变了

这一轮那八件事都是「**同一个数不再重算**」，按定义输出不变 —— 没有一处降低精度、缩短
时长、减少层数、减少每帧的步数。§6.2 的逐像素基线就是这条断言的证据。

**唯一一处会改变可观察行为的是光晕的暂停**（§4.3b）。代价说清楚：

- 只在**日历页**、只在「有东西在动」的那几百毫秒里停；动完接着走，**不跳回**。
- 日历页的光晕本来就极淡（强度 0.65，格底浅色 92% 白、深色只有 6% 白），而拖动时眼睛
  在那枚块上 —— 这一点在观感上基本读不出来。
- 反过来看：今天拖动时**每 340ms 有一次固定掉帧**（光晕 tick 撞上拖动帧）。暂停把它拿
  掉，拖动反而更顺。
- 响铃界面（光晕是主角那一处，`freezeWhenBlurDisabled` 为 false）**一个字都不改**。

不发散的三条：

- 点日期 / 点「今天」的飞行、按住拖块、长按拖选、换月，**手感逐帧与今天相同**：同一套
  曲线、同一套弹簧、同一条速度算式（`lensVelocityStep`）、同样的触觉点。
- 光晕的**频率、强度、光斑数量、颜色**一个字不改。
- `CalendarLens` 的几何（凸出 6 / 横向外扩 12 / 速度门 400 / 圆角 `radiusM`）不动。

## 6. 验收

### 6.1 探针（前后对比，跑完即删）

| 指标 | 今天 | 这一轮的目标 |
|---|---|---|
| 液态档一帧重建的 widget 数 | 436 | **≤ 80** |
| 一屏 42 格 lunar 转换 | 1.47 ms | **≈ 0**（第二次起） |
| 光晕 tick 那一帧重绘的绘制节点 | 139 | **≤ 8** |
| 一次 `rescheduleAll` 的跨端调用 | 101 | **≤ 55** |
| 同一份快照重复推 | 每次都推 | **0 次** |
| `buildWidgetSnapshot` | 46 ms | **≤ 15 ms** |

### 6.2 像素基线

`tool/visual/` 全量出图，与 v0.10.19 基线**逐张比**：

- **标准档一张都不许变。**
- 液态档只许在**已经解释过的**地方出现差异；出现新差异就逐张写进账本，写不出理由就是
  回归，不许放宽阈值糊过去。
- 已知的假差异（响铃页时钟跳字、跨天「今天」位移）照旧按老规矩剔除。
- **另加一条专项核对**：光晕在动时，压在它上面的玻璃里的模糊要**跟着动**（§4.3a 那条的
  反向风险）。做法：同一位置隔 340ms 取两帧，比**玻璃内部**的像素 —— 必须不同；
  冻住就说明那一层的隔离放错了位置。

### 6.3 既有护栏

`flutter test` 全绿（当前 **773** 条，只增不减）；`flutter analyze` 0 error / 0 warning。

### 6.4 新增护栏（这一轮的成果必须被钉住，不然三个月后又长回去）

照仓库既有的「扫源码 / 假通道守门」套路：

1. **「日历一帧重建的 widget 数 ≤ 80」** —— 用 `debugOnRebuildDirtyWidget`，在液态档起
   一次飞行后逐帧数。**必须反向验证**：把那几个值塞回 `State` 里，这条用例要立刻红。
2. **「`rescheduleAll` 的跨端调用次数 ≤ 55」** —— 假通道计数，反向验证同上。
3. **「同一份快照 JSON 不重复推」** —— 假通道计数 `widgetPushSnapshot`，连推两次同样的
   数据，只许发一次。

## 7. 非目标（这一轮明确不做）

- **切 tab 保活**（`PageView` 销毁非当前页）。它牵动内存常驻与四个页面的生命周期，
  是独立的一轮；这一轮不动它。
- **原生与功耗那一档**：`AlarmStore` 批量写、响铃服务自停与超时、小组件改非精确闹钟。
  碰闹钟语义、要真机验证，单独一轮。
- **观感取舍项**（要用户先拍板）：光晕刷新间隔 340ms → 700ms、光斑 3 → 2、
  信息卡那层 `BackdropFilter` 的 sigma、液态档彩边那四层模糊的层数。
- `L10n` 里 `DateFormat` 每次新建（月标题那几处）；`appSettingsProvider` 收窄成 `select`
  （现在换个触觉开关会重建整页）。两条都是「量到再说」。

## 8. 风险与代价

- **`CalendarLens` 的 v0.10.16 语义不许碰**（拖动中低通接收、松手那一帧接一次、其余不做）
  —— 这正是不把「速度」也做成 listenable 的原因：那会重写这套语义，而它已经踩过一次
  （「拖完再点一下日期，那枚块自己抽一下」）。
- **`Stack` 的孩子必须是 `Positioned`**（4.1 纪律 1）—— 漏了会当场布局错，工装出图看得见。
- **液态档的静止画面必须逐像素不变**：静止时 `_cellWarp` 的权重见底、返回 `null`、
  一层 `Transform` 都不套 —— 这条规则与今天完全一致，但实施时容易「顺手」改成恒等
  `Transform`。

## 9. 已定的两处与未定的一处

已定（实施时照此办，不必再问）：

1. `LensWarpScope` **放新文件** `features/calendar/lens_warp_scope.dart` —— 它是一个独立
   的单元（一句职责：把挤压场挂在格子上），能被单测直接驱动；挤进 2690 行的
   `calendar_screen.dart` 只会让它更难被看见。
2. 那五样按月缓存**单开一个小对象**（`_MonthFacts`），不并进 `InfoCardMetrics` ——
   后者的职责是「高度」，塞进去它会变成杂物袋。

未定（量到再定）：

3. §4.7(d) 的去抖时长（起草时写 300ms）以实测为准。
