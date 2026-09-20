# 倒班助手Pro · 产品与技术规格（现状规格 · v0.9.0）

> 本文档是**唯一权威规格**，反映当前实现现状（v0.9.0）。早期「MVP 确认稿」的功能已随 0.2~0.6 各版演进并入正文，不再单列历史章节。

---

## 1. 定位

| 维度 | 决定 |
|---|---|
| 应用名 | 倒班助手Pro |
| 包名 / applicationId | `com.daoban.shiftassistantpro` |
| 框架 | Flutter（Dart），一套代码多端 |
| 发布形态 | 开源（MIT）；GitHub Releases 分发 APK，**不上架应用商店** |
| 更新渠道 | GitHub Releases（公开仓库）+ 应用内检查更新 / 直接下载安装 |
| 数据 | 纯本地离线（Drift/SQLite），无账号、无后端、无云同步 |
| 已交付平台 | **Android**（minSdk 26 = Android 8.0+，出完整版 APK） |
| 冻结 / 未交付 | iOS（无 Mac，冻结，仅保持跨端干净）、鸿蒙（无设备）、Windows（按需插队） |
| 数据迁移 | 手动重录，不做导入脚本 |

## 2. 功能范围（现状 v0.9.0）

### 排班日历
1. **两层轮换模型**：**班次定义**（一个班次只定义一次）+ **周期序列**（长度即周期，元素引用班次定义），周期长度 1–60 天；班组相位由「每班组一个周期起始日」表达。轮换算法为纯函数，某天班次由（日期 − 周期起始日）对周期取模得出，天数差用 UTC 日期整数，避免时区问题。
2. **月视图**：每格的班次是个**带底色的胶囊**（班次色 14% 淡染底 + 45% 描边 + 按底色算可读的文字色），三行**全部居中**（日期 / 班次 / 农历）；格内文字按格子高度等比缩放（1.0–1.25×，格子长高字跟着长），胶囊里的简称再套一层 `FittedBox` 兜底 —— 两个字甚至三个字的简称都不会被截成省略号，系统字号放大也照缩。选中那天的胶囊变**实心**（滑到哪格一眼可见）；**无班次的方案**（跟随法定节假日）只是少画中间那一行；格子太窄（小窗）时胶囊退化为纯色文字。上/下月翻页、一键回今天、**年月跳转选择器**（年份滚轮 + 4×3 月份网格）。
3. **农历 + 法定节假日**：每格显示农历日 / 节气 / 节日；**法定节假日整段标红**（`lunar_info.dart` 内置 2025/2026 国务院放假安排表 `_holidaySpans` / `_makeupDays`，**每年国务院发布次年安排后需追加** —— **当前数据止于 2026-12-31，2027 年及以后尚无数据、日历不会标任何节假日**）；**调休上班日带「班」标记**；点选某天展示干支、生肖等完整农历。
4. **法定班次（空白表）**：方案可设为跟随法定节假日、无周期轮换（节假日自动休班），班组收敛为「我」。
5. **多套排班方案**并存、一键切换、增删改管理；每个班组的「周期起始日」决定整表相位。
6. **多班组视图**：可查看其他班组某天班次，便于交接班对照。**撞班检测**：各班组错位（周期起始日）与周期长度对不上时，同一天会出现两个班组上同一个班 —— 编辑器的「周期设置」卡里直接点名相撞的班组（「有 N 天两个班组上同一个班（三班与四班）」），并给一个「按周期长度均分各组起始日」的动作（**我们班组原地不动**）。均分规则就是内置模板用的那一条：第 i 个班组落在 `i × 周期长度 ÷ 班组数` 天处，由 `shift_templates_test.dart` 对每个模板逐条守着（模板里的错位是人手抄的，抄错了只有这条抓得住）。
7. **内置 20 种常见倒班方式模板**：新建排班时先选一个最接近的倒班方式（白夜休休、白白夜夜休休、四班三倒、五班三倒、六班三倒、五班四倒、六班四倒、上 24 休 24/48/72、长白班、做一休一/二/四、做六休一、大小周、两班倒等），选中即生成一套普通排班方案，可继续自由编辑。 **「我的模板」**：编辑器右上角可把当前这套（**含还没保存的草稿改动**）存成模板，新建排班时排在选择页最前的一组；卡片上副标题按结构现算（「10 天一轮 · 5 个班组」），分组标题旁的「管理」里可改名 / 删除。存的是**结构**（班次定义 + 周期 + 班组错位），不含基准日与按天覆盖 —— 用模板建出的新方案基准日 = 今天、「我们班组」从周期第 1 天开始（与内置模板同一条约定），相位要改在编辑器里点「我这组从这个周期开始」。保存时「我们班组」归一化到第 0 位、错位归零，保证建出来的方案里它还是自己那一组。
8. **编辑器未来 14 天实时预览**：排班编辑器里改任何设置（班次时间 / 周期 / 班组起始日）都能立刻从预览条看到接下来 14 天的班次。**预览有意只显示轮转规则、不叠按天改班**（它要回答的是「按这套规则未来是什么班」，叠上覆盖就看不出规则本身的变化了）；方案存在覆盖时顶部给一行轻提示，说明有几天是单独调整的。
9. **按天改班（换班 / 请假覆盖）**：某一天或连续一段日子可单独指定班次，不动整套轮转 —— 请假挑个休班、跟同事换班就挑对方那个班。**两个入口**：点底栏信息卡上那行班次（改选中的那一天），或在日历网格上**长按拖选**一段连着日期（可跨周、**不跨月**）。选择层列出本方案全部班次定义（色点 + 名称 + 时间，当前那个打勾），范围里已有覆盖时多一条「**恢复轮转**」把某几天清回轮转。被覆盖那天胶囊**右上角一个小圆点**、信息卡标「**已调班**」。覆盖**只作用于我们班组**（其他班组视图仍是纯轮转），联动闹钟自动跟着变（见下）。**空白表方案（跟随法定节假日）不支持** —— 没有班次定义可挑，两个入口都不进。底层一天一行（`ShiftDayOverrides`），一次可写多天。
   **小窗（高 < 480dp）下日历网格不画、只显示今日信息卡**：那个尺寸下网格与卡片都想要的结果是两者都看不清（200×400 里网格只剩两三行、还被压扁）。信息卡在这一档换成「精简但有标记」的形态（日期 + 短农历 + 班次名与时间 + 「已调班」徽章），所以**被调过的日子在小窗里仍然看得出来**。各机型小窗的默认尺寸 400×640（高 640 > 480）不受影响，照常是网格 + 完整卡。

### 联动班次闹钟
10. 每个班次独立设置响铃时间与开关；`AlarmService.reschedule` 按排班自动排定**未来 60 天**并自动续排。**按天改班自动流进闹钟排定**：改成休班那天不排闹钟，改成别的班次就按那个班自己的响铃时间排。这与「按天关闹钟」（`ShiftAlarmOverrides`）**正交**，两条规则各管各的 —— 那天被单独关过闹钟的，改完班之后仍然关着。**响铃时刻取「不晚于上班时刻的最近一次该钟点」**（`shiftAlarmFireAt` / `ShiftClass.alarmPreviousDay`）：响铃钟点晚于上班钟点时排在**前一天**同一钟点 —— 00:00 上班、23:00 响铃的夜班排的是前一天晚上 23:00（排在班次当天就已经是班后 15 小时了）。班次编辑的钟点块写成「前一天 23:00」并补一行说明，闹钟列表行与日历信息卡同样标「前一天」；上班时间没填时无从判断、仍按当天算。原生 id 与 `offset` 始终按**班次那一天**算，不跟着前移的触发时刻走。
11. **未来 30 天预览列表**：每条可单独开关（写入按天覆盖表 `ShiftAlarmOverrides`，主键 `day` = 自 epoch 天数，由 `dayNumber()` 计算），响过后自动隐藏；`Timer.periodic(1min)` + 回前台重建刷新。
12. **自定义闹钟**：一次性 / 每天 / 每周（多选星期，位掩码）；重复型由原生侧同一 id 续排；新建默认时间即此刻。
13. **可靠响铃**：系统精确闹钟（`setAlarmClock`）+ 前台服务（`AlarmRingService`：MediaPlayer + Vibrator + WakeLock + fullScreenIntent）+ 全屏响铃界面（贪睡 5 分钟 / 上滑关闭滑块 —— 可见轨道 72dp、触摸热区 112dp，整屏也可上滑关闭，矮屏 `AppLayout.isShort` 下轨道与底部留白各收一档）；铃声内置、系统可选，**或从手机里挑自己的音频**（系统文件选择器选中后复制进应用私有目录，换回内置/系统时自动删掉副本；自选文件损坏或丢失时回落内置，不会一声不出）、可试听；**测试闹钟**一键排定 10 秒后响。通知小图标统一用 `drawable/ic_notification`（白剪影矢量），原生前台服务与 `flutter_local_notifications` 共用同一个 —— 启动器图标是彩色的 mipmap/自适应图标，不能当通知小图标。**重启重排**：排定时同步落盘一份清单（`AlarmStore`），开机由 `BootReceiver` 排回去 —— 每天/每周的顺延到下一次，一次性且未到点的按原时刻排回，**关机期间已经错过的直接丢掉、不补**；「待办提醒」那条安静链路（`scheduleQuiet` → `TodoReminderReceiver`）走同一套。取消路径必须同步删清单（`AlarmScheduler.cancel` / `cancelAllNativeAlarms` / `cancelTodoReminders`），漏一处就留下一条重启后才现形的「幽灵闹钟」。
14. **小米机型「锁屏/后台弹不出响铃界面」= 少开了一项系统权限，不是 OS 限制**（v0.7.4 起更正 —— 此前这里记的「已接受的 OS 限制：小米/华为免解锁弹全屏受限」是**错的**，当时没接真机调试）：MIUI 把「后台弹出界面」（系统英文界面里叫 `Open new windows while running in the background`）单独设成一项权限，不开时 `ActivityStarterImpl` 会**静默**拒绝从后台拉起 Activity（系统把它降级成 "invisible launch"，连 `onNewIntent` 都不走），**通知那条 `fullScreenIntent` 的 PendingIntent 也一起被拒** —— 所以「靠通知兜底」这条路不存在。它与「显示悬浮窗」（AOSP 的 `SYSTEM_ALERT_WINDOW`，管 AOSP 层的后台启动豁免）、「锁屏显示」（管锁屏下能否顶掉 keyguard）是**三项不同的权限**；后两项 App 能检测或跳转，前者读不到状态、也没法用 adb 授予（MIUI 的 op 常量 `OP_BACKGROUND_START_ACTIVITY` 没进 `AppOpsManager` 的名字表），只能用 `miui.intent.action.APP_PERM_EDITOR` + `extra_pkgname` 跳转引导。实测三项齐备后：退后台会自动拉回前台；锁屏会点亮屏幕并顶掉 keyguard。

### 待办日程
15. 事件 = 标题 + 日期 + 可选时间 + 可选提醒档位（不设 / 准时 / 提前 5 分钟 / 15 分钟 / 30 分钟 / 1 小时 / 1 天）+ **联动闹钟开关**。两者**二选一**：开关关（默认）到点弹**普通通知**（标题 = 待办名，点通知进待办页）；开关开到点走**闹钟**那条链路（全屏 + 循环铃声 + 震动，与班次闹钟同一套），响铃界面除了标题还会显示这条待办的日期时间。两者联动：开着闹钟时提醒不可能是「不设」（界面上选「不设」会顺手关掉闹钟，开闹钟会把「不设」补成「准时」）。增删改与勾选之后立刻重排，不必等下次开 App。当天有待办时，日历底栏信息卡的日期行上显示「N 项待办」（不占新行，卡片高度不变）；列表里开了联动闹钟的那条带一个小铃铛图标。完成勾选后**字体变暗 + 删除线**并存。

### 我的 / 设置
16. **检查更新**：`UpdateChecker` 无鉴权拉公开仓库 GitHub API `/releases`（未认证限 60 次/小时/IP），自行按语义版本计算「最新正式版 + 最新测试版」并双通道展示；冷启动每日一次静默检查，**仅发现更新的正式版时弹窗**。
17. **应用内下载并安装 APK**：`downloadApk`（直接经 `browser_download_url` 流式下载）→ `installApk` → FileProvider 拉起系统安装器。
18. **权限检测卡**（3 组：基础提醒 / 弹出响铃界面 / 后台与开机）：通知、闹钟和提醒（精确闹钟）、显示悬浮窗、全屏通知、自启动、电池优化；**小米机型另加两项** ——「后台弹出界面（小米）」与「锁屏显示（小米）」，分成两行是因为症状不同（退后台不弹 vs 锁屏不弹）。每行副标题写「**不开会怎样**」而不是「要不要开」；自启动与小米那两项系统不提供状态查询，恒显示「去查看」（分别跳 App 信息页 / MIUI 权限页），其余未开启项一键跳转系统设置。
19. **日志查看**：只记录错误/崩溃（普通信息走 Logcat），`AlarmLog.kt` 按 256KB 自动裁剪；可查看 / 复制 / 清空。
20. 主题跟随系统 / 浅色 / 深色三档；5 种主色调；中 / English 双语；首次使用引导 + 每次更新弹更新说明。
21. **触觉反馈**（默认开，「我的 → 外观」里一键关）：**只有三档语义** —— 切换开关 / 胶囊段切换 / 选项胶囊选中 / 选择器提交 / 日历滑块换格 / 长按拖选每进入新的一格（`select()`，「选中变了」）、删除清空类确认 / 应用改班与恢复轮转 / 切换排班方案（`commit()`，「动作落实」）、长按进入日历多选态（`modeEnter()`，「进入一个模式」）。**挂动作不挂按压** —— 普通点击、列表行点击、滚动与选择器滚轮一律不震（信息量一旦稀释到背景噪音里就归零）。没有强度档位，只有开 / 关；关掉即全 app 不震（见 §6「触觉反馈」）。

### 桌面小组件
22. **桌面小组件（三张固定尺寸的卡）**：v0.8.8 起取代 v0.8.6 的五档自适应 —— 三张卡各自**编译期定死尺寸、`resizeMode="none"`**，一张卡只为它自己的尺寸排版，放置后不能再拉伸、运行期不再分档：`WeekStripWidgetProvider` **4×1 本周条**（今天所在那一周的七列：周几 / 日数字 / 班次胶囊）、`TodayCardWidgetProvider` **4×3 今日卡**（照搬 App 底栏信息卡的完整版：日期 + 今天徽章 + 待办徽章 + 完整农历 + 班次行 + 已调班徽章 + 时间 + 其他班组）、`MonthWidgetProvider` **4×5 整月**（月份标题 + 周几行 + 6×7 = 42 格）。旧的 `WidgetTier` 与五档版式（列表 / 网格 / 装配壳七张布局）已**删净**，`onAppWidgetOptionsChanged` 也一并没用了。**换版式会让旧实例失效**：provider 类名换了，系统认不出桌面上原有的小组件，升级后它会消失、必须在桌面重新添加 —— 这点写进了更新日志。三张卡的尺寸两头都声明：Android 12+ 认 `targetCellWidth/Height`，12 以下靠 `minWidth = 70n − 30` 的老公式折算（4 列 → 250dp；1 / 3 / 5 行 → 40 / 180 / 320dp）。这份对应关系、三张卡的 manifest 声明、月历 42 格 id 都**没有编译期保护**，由 `app/test/widget_fixed_cards_guard_test.dart` 扫源码守门（它是删掉的五档阈值护栏的等价物）。
   **走原生 `RemoteViews` 渲染，不是 Flutter**：Dart 侧 `features/widget/widget_snapshot.dart` 产出「已本地化的快照」（**协议 v2**：农历短/全串、周几、月份标题、days/months 双窗口）写进 `SharedPreferences`（`shift_widget`/`snapshot`），原生 `ShiftWidgetBase` 只排版 —— **用户可见文案全部来自 Dart 侧快照**（`L10n` 产出，双语仍只有 `l10n.dart` 一处要维护；Kotlin 侧只有 `AlarmLog` 的日志串是中文，用户可见文案一个字面量都不许出现）。快照窗口是**「本月 + 下月」的绝对窗口**，含窗口里已经过去的天 —— 所以本周条画得出「上周日~本周六」那种跨月的周、月历跨月那一格也不必特殊处理；**跨天自动翻页 + 班次边界刷新**（在 App 里改排班 / 主题 / 语言后启动一次即同步），跨天时原生拿 `LocalDate.now().toEpochDay()` 对表整体右移、不重算，耗尽退化成占位态。月历**渲染哪个月由 `LocalDate.now()` 定**，月份标题从 `snap.months` 按「年-月」查、查不到就隐藏标题行，绝不借相邻月份顶上。三张卡里只有月历有 42 格 —— 42 格共用一张 `widget_month_cell`、每格一个 `RemoteViews` 实例，胶囊是**定尺**的 `WidgetChip.tintedChip` 位图，靠 LruCache 按（颜色, 尺寸）复用。**胶囊一律走 14% 淡染 + 45% 描边**（与 App 日历格同一套配方），文字走中性 `wg_ink_*`；**没班次那格 / 那一列整个不画胶囊**（不拿 `wg_empty_*` 顶 —— `tintedChip` 里 `Paint.setAlpha` 会覆盖颜色字节自带的 alpha）。两条「长在 App 里、搬到桌面上就错」的配方：**月历的格子不带白卡**（App 里每格是白卡，那是垫在 #F5F6FA 中性底上的；桌面上卡底 96% 不透明、42 张叠起来会糊成一片，分区改靠间距与明度）；**「今天」只走主色、不许加粗**（`TextView` 没有 `setTypeface(int)` 重载）。今日卡跨天**降级**而不是硬撑：`todayCard` 里的农历 / 待办数 / 其他班组是**生成那天**的，跨天刷新时原生只能对表右移、重算不了，故 `todayCard.day != 今天` 就把这三样留空、只显示 `days[todayIndex]` 里按日期烘焙的日期 / 班次 / 时间 —— **绝不把旧数据当成今天显示**。
   刷新粒度＝跨天 + 班次边界，不逐分钟（三张卡共用同一个 `WidgetRefreshScheduler` 精确闹钟；`ShiftWidgetBase.onDeleted` 判「三张卡一个实例都不剩」才取消它）。**不动 Drift schema**（快照走 SharedPreferences）。**点整卡开 App、点某一天跳到那天的日历**。**小米 / HyperOS 上入口特殊**：标准 Android 小组件不进原生那一栏，藏在「支持小部件的应用」→「安卓小部件」二级分类里（长按桌面空白 → 添加小部件），README 与更新日志都写明了怎么找；小米桌面会**按资源 id 缓存 drawable**，改了小组件的资源色之后验证前必须先重启桌面（`am force-stop com.miui.home`），否则会误判成「改没生效」。

**明确不做（现状仍成立）**：2-2-3 Pitman 型「固定日班组/夜班组」模式、**周期中间插入删除某一天**、云同步/备份/数据导入导出、工资/补贴记账、广告、商店上架、IM/天气/组织/好友。

**按天改班的边界（本轮有意不做，别再当漏做）**：空白表方案（跟随法定节假日）下不支持按天改班（没有班次定义可挑）、不支持跨月拖选、不支持「从这天起一直……」这种开放式范围、不支持同一天对不同班组分别覆盖、不支持临时自定义一个只用于那天的班次。

## 3. 班次模型（默认配置，引擎通用）

默认「四班两倒」，4 天一个周期（App 内可改，引擎不绑定该配置）。班次定义只需配一次，周期里所有同名单日自动同步时间 / 颜色 / 联动闹钟：

| 顺序 | 班次名 | 简称 | 时间 | 是否工作 | 联动闹钟 |
|---|---|---|---|---|---|
| 1 | 白班 | 白 | 8:30–20:30 | 是 | 7:00 |
| 2 | 上夜班 | 夜 | 20:30–次日 8:30（记在开始那天） | 是 | 19:30 |
| 3 | 下夜班 | 休 | 无（早 8:30 下班即休） | 休 | 否 |
| 4 | 大休 | 休 | 无 | 休 | 否 |

- 格子简称 `abbr` 挂在班次定义上（1~2 字），为空时按班次名推断；冷门班次名也能正确显示。
- 时间用「分钟自开始日午夜」存储：`startMinute` / `endMinute`。**`endMinute` 允许超过 1439**，跨过午夜后继续累加——24 小时值班 = `480 → 1920`（08:00 → 次日 08:00）；`1440` 恰好显示为 `24:00`。
- 班组相位由「每班组一个周期起始日」表达：编辑器中为每个班组指定它的周期第 1 天（持久化为相对基准日的天数偏移 `teamOffsets`）。
- 「法定班次」型方案（空白表）：`classes` 为空、周期为空、跟随法定节假日，不做轮换。

## 4. 数据模型（Drift · schemaVersion = 9）

| 表 | 关键字段 / 说明 |
|---|---|
| `ShiftScheduleRows` | 排班方案：id、name、anchorDate、isCurrent + 班组配置（班组数 / 班组名 / 每班组相对基准日的天数偏移 `teamOffsets` / 我们的班组） |
| `ShiftClassRows` | 班次定义：scheduleId、order、name、abbr?、startMinute?、endMinute?、isRest、color、alarmEnabled、alarmMinute? |
| `ShiftCycleRows` | 周期序列：scheduleId、order、classId（第 N 天用哪个班次定义） |
| `ScheduleEvents` | 待办日程：title、date、timeMinute?、advanceRemindMinutes?、isCompleted、alarmEnabled（联动闹钟）、createdAt |
| `CustomAlarms` | 自定义闹钟：一次性 / 每天 / 每周（星期位掩码）等 |
| `CustomTemplates` | 「我的模板」：name + **整块快照**（classes 走 JSON、cycle / teamOffsets 走逗号分隔）+ teamCount + createdAt。模板是只读快照（没有按字段查询、没有跨表引用、也不与任何行共享身份），所以整块存不拆表；比方案少两张表与一整套装配代码 |
| `ShiftAlarmOverrides` | 按天覆盖班次闹钟开关：主键 `day`（自 epoch 天数），false 的日期重排时跳过 |
| `ShiftDayOverrides` | 按天改班覆盖：复合主键 `{scheduleId, day}`（`day` = 自 epoch 天数），`classId` 指到本方案的某个班次定义；只作用于我们班组 |

> 某天的班次**默认不落库**，按「周期起始日 + 周期序列」实时计算；只有被**按天覆盖**的那些天才在 `ShiftDayOverrides` 里有一行（表里存 `classId`，读时转成 `classes` 下标）。
> **改表后必须重生成**：`dart run build_runner build --delete-conflicting-outputs`。
> **v5 → v6 迁移**：把旧的 `ShiftTypeRows`（每方案一串班次）拆成 `ShiftClassRows` + `ShiftCycleRows`，重复班次合并去重；旧表迁移后删除。
> **v6 → v7 迁移**：`ScheduleEvents` 加一列 `alarm_enabled`（默认 0 = 只弹通知，保持旧行为）。
> **v7 → v8 迁移**：新建 `ShiftDayOverrides` 表（按天改班覆盖）；原有数据一条不丢。
> **v8 → v9 迁移**：新建 `CustomTemplates` 表（「我的模板」）；同为纯新增，原有排班与待办一条不丢。

## 5. 技术选型（实际实现）

| 项 | 选择 |
|---|---|
| 状态管理 | Riverpod（flutter_riverpod ^2.6） |
| 本地数据库 | Drift ^2.20（lock 2.31.0）+ drift_flutter + sqlite3_flutter_libs（纯本地离线） |
| 闹钟调度 | flutter_local_notifications ^17.2.4（精确闹钟）+ **原生 Kotlin**：`AlarmScheduler`(setAlarmClock) / `AlarmReceiver` / `AlarmRingService`(前台服务) / `AlarmLog`；`SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` |
| 农历 | lunar_plus ^1.7（农历 / 节气 / 干支 / 生肖）+ `domain/lunar_info.dart` 内置法定节假日表（2025/2026） |
| 其他 | intl、timezone、shared_preferences、path_provider |
| 平台基线 | Android minSdk 26（8.0+）；compileSdk/targetSdk 随 Flutter stable 默认 |
| 设计 | **自研液态玻璃设计系统**（非第三方玻璃包，见第 6 节） |

## 6. 设计系统（现状）

- 目标：形成「简洁 + 液态玻璃（磨砂模糊）+ Q弹动画」设计语言。
- 材质核心：`core/glass/glass.dart` **GlassPanel / GlassTile**（BackdropFilter 模糊 + 渐变 + 白描边 + 高光；`solid` 近实心；`enableBlur` 低端降级）。
- 共享组件（`core/widgets/`）：GlassSegment（胶囊滑块）、GlassSwitch（Q弹开关）、GlassDialog、GlassButton（主色实心 + 玻璃描边）、GlassActionButton（primary / secondary / danger）、GlassPressable（统一玻璃触摸反馈）、GlassDeleteButton + `dangerButtonStyle`、玻璃弹层选择器（`showGlassTimePicker` / `showGlassDatePicker` / `showGlassMonthPicker` / `showGlassOptionPicker`，底部 `solid` 近实心）、`glassInputDecoration`、`showGlassSnack`（提示条玻璃化）。
- 主题 token：**深空蓝紫渐变**；跟随系统深浅双套；5 种主色调（`AppColors.accentPalette`）；中英双语（L10n）。
- **设计令牌（单一来源）**：`core/design_tokens.dart` 的 `AppTokens` 按**角色**命名 —— 排版（页面标题 / 卡片标题 / 行内主文字 / 次要说明 / 微标签）、文字明度两档（`inkMuted` 0.62 / `inkFaint` 0.35）、间距（4px 栅格节奏 + 一组「光学」微距）、图标三档（16 / 20 / 24）、圆角 / 时长 / 玻璃配方。**其中 `inkMuted` 0.62 是在浅色底上过 WCAG AA 4.5:1 的最低值（最坏浅底 `#F5F6FA` 上 0.62 为 4.70:1；0.55 / 0.60 分别只有 3.72:1 / 4.33:1，均不达标 —— 数字按主题真实的 `onSurface` `#1A1B20` 实算，不是 `#111118`）；`inkFaint` 0.35 则是有意低于 AA 的豁免档** —— 它服务禁用态 / 占位 / 待办已完成，低对比正是它的用途（已完成的语义由删除线承载）。界面层只引用角色名，**不许写下列字面量** —— 字号（`fontSize:`）、字重（`fontWeight:`）、`onSurface` 系的文字明度（`.withValues(alpha: …)`）、圆角（`circular(…)`）、`Duration(milliseconds: …)`、`Color(0x…)`、图标尺寸（`Icon` / `IconThemeData` 的 `size:`）—— 这条由 `app/test/design_tokens_test.dart` 强制（整文件级扫描，写死即测试失败；本轮收口：扫描前先剥离注释与字符串，覆盖带子 widget 的调用与间距类常量，并支持 `// design-tokens-ignore: <理由>` 具名豁免）。**有意不强制**（别把这条测试的拦截面看大了）：装饰 / 玻璃配方里的 alpha（`Colors.white.withValues(alpha: …)` 这类）、`Color.fromARGB(…)`、`Duration(seconds:)` 目前都不在规则内 —— 它只覆盖上面逐项点到的那几类。
- **触觉反馈（单一词汇表）**：`core/haptics.dart` 是全 app 唯一的触觉来源 —— **三档语义**：`Haptics.select()`（选中变了）、`Haptics.commit()`（动作落实 / 这一步不可逆）、`Haptics.modeEnter()`（进入一个模式）。**挂动作不挂按压**：普通点击、列表行点击、滚动与选择器滚轮一律不震（`GlassPressable` 故意不挂 —— 它包的是每一次按压），触觉只出现在「状态真的变了」或「这一步不可逆」的时刻。调用为 fire-and-forget：不 await、异常吞掉，震不震不影响功能。开关是「我的 → 外观」那一个（默认开），走模块级 `hapticsDisabled`（与 `advancedMaterialDisabled` 同一条路，一处赋值全 app 生效，调用点不必各自查设置）。**除 `core/haptics.dart` 外任何文件不许直接调 `HapticFeedback.*`，由 `app/test/haptics_guard_test.dart` 扫源码强制** —— 绕过的那一行不受用户开关控制。**只有三档，没有「危险」第四档，也没有强度设置。**
- **应用图标**：`scripts/icon_gen.py` 是图形唯一来源（符号 = 白日历卡 + 环绕换班箭头；预览落 `work/icon-preview.png`），`scripts/icon_land.py` 落地到 Android / iOS / Web。Android 侧出货**自适应图标**三层 —— background（满幅渐变）/ foreground（安全区内的符号）/ monochrome（白剪影 + alpha 镂空，供 Android 13+「主题图标」上色）。**自适应安全区是直径 66dp 的圆（画布 108dp），方形符号须按内接圆缩，边长上限 ≈ 画布 43%** —— 按外接正方形画会被圆形蒙版削角。minSdk 26，真机永远走自适应那套，`mipmap-*/ic_launcher.png` 只是兜底。**产物都是生成物，改图形只改 `icon_gen.py`**。
- 性能策略：API 31+ 真实时模糊，26–30 假玻璃降级（半透明 + 饱和 + 高光）；弹窗遮罩统一 `barrierColor: Colors.black26`；底部弹层 `GlassPanel(solid: true)`。

## 7. 版本与发布链路（现状）

- 版本号唯一来源 `app/pubspec.yaml`（`X.Y.Z+build`），与 `app/lib/core/app_info.dart` 的 `appVersion` 同步，一致性由 `app/test/app_info_test.dart` 把关；末位 `Z=0` 为正式版（条目需归纳为总结版），非 0 为测试版（条目原样保留）。
- 应用内更新：`UpdateChecker` 无鉴权请求公开仓库 `/releases`（未认证限 60 次/小时）；APK 直接经 `browser_download_url` 下载安装。
- 本地发布：`scripts/release.ps1`（读版本号 → 校验 → 按末位自动标正式/预发布 → 上传 GitHub Release；发布说明写到 `tools\gh\release-notes-vX.Y.Z.md` 自动复用）；APK 产出 `dist/倒班助手Pro-vX.Y.Z.apk`（`dist/`、`*.apk` 均不入库）。
- 验收标准：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿。

