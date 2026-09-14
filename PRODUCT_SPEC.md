# 倒班助手Pro · 产品与技术规格（现状规格 · v0.7.2）

> 本文档是**唯一权威规格**，反映当前实现现状（v0.7.2）。早期「MVP 确认稿」的功能已随 0.2~0.6 各版演进并入正文，不再单列历史章节。

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

## 2. 功能范围（现状 v0.7.2）

### 排班日历
1. **两层轮换模型**：**班次定义**（一个班次只定义一次）+ **周期序列**（长度即周期，元素引用班次定义），周期长度 1–60 天；班组相位由「每班组一个周期起始日」表达。轮换算法为纯函数，某天班次由（日期 − 周期起始日）对周期取模得出，天数差用 UTC 日期整数，避免时区问题。
2. **月视图**：每格的班次是个**带底色的胶囊**（班次色 14% 淡染底 + 45% 描边 + 按底色算可读的文字色），三行**全部居中**（日期 / 班次 / 农历）；格内文字按格子高度等比缩放（1.0–1.25×，格子长高字跟着长），胶囊里的简称再套一层 `FittedBox` 兜底 —— 两个字甚至三个字的简称都不会被截成省略号，系统字号放大也照缩。选中那天的胶囊变**实心**（滑到哪格一眼可见）；**无班次的方案**（跟随法定节假日）只是少画中间那一行；格子太窄（小窗）时胶囊退化为纯色文字。上/下月翻页、一键回今天、**年月跳转选择器**（年份滚轮 + 4×3 月份网格）。
3. **农历 + 法定节假日**：每格显示农历日 / 节气 / 节日；**法定节假日整段标红**（`lunar_info.dart` 内置 2025/2026 国务院放假安排表 `_holidaySpans` / `_makeupDays`，**每年国务院发布次年安排后需追加** —— **当前数据止于 2026-12-31，2027 年及以后尚无数据、日历不会标任何节假日**）；**调休上班日带「班」标记**；点选某天展示干支、生肖等完整农历。
4. **法定班次（空白表）**：方案可设为跟随法定节假日、无周期轮换（节假日自动休班），班组收敛为「我」。
5. **多套排班方案**并存、一键切换、增删改管理；每个班组的「周期起始日」决定整表相位。
6. **多班组视图**：可查看其他班组某天班次，便于交接班对照。
7. **内置 19 种常见倒班方式模板**：新建排班时先选一个最接近的倒班方式（白夜休休、白白夜夜休休、四班三倒、五班三倒、六班三倒、五班四倒、六班四倒、上 24 休 24/48/72、长白班、做一休一/二/四、做六休一、大小周、两班倒等），选中即生成一套普通排班方案，可继续自由编辑。
8. **编辑器未来 14 天实时预览**：排班编辑器里改任何设置（班次时间 / 周期 / 班组起始日）都能立刻从预览条看到接下来 14 天的班次。

### 联动班次闹钟
9. 每个班次独立设置响铃时间与开关；`AlarmService.reschedule` 按排班自动排定**未来 60 天**并自动续排。
10. **未来 30 天预览列表**：每条可单独开关（写入按天覆盖表 `ShiftAlarmOverrides`，主键 `day` = 自 epoch 天数，由 `dayNumber()` 计算），响过后自动隐藏；`Timer.periodic(1min)` + 回前台重建刷新。
11. **自定义闹钟**：一次性 / 每天 / 每周（多选星期，位掩码）；重复型由原生侧同一 id 续排；新建默认时间即此刻。
12. **可靠响铃**：系统精确闹钟（`setAlarmClock`）+ 前台服务（`AlarmRingService`：MediaPlayer + Vibrator + WakeLock + fullScreenIntent）+ 全屏响铃界面（贪睡 5 分钟 / 上滑关闭滑块 —— 可见轨道 72dp、触摸热区 112dp，整屏也可上滑关闭，矮屏 `AppLayout.isShort` 下轨道与底部留白各收一档）；铃声内置、系统可选，**或从手机里挑自己的音频**（系统文件选择器选中后复制进应用私有目录，换回内置/系统时自动删掉副本；自选文件损坏或丢失时回落内置，不会一声不出）、可试听；**测试闹钟**一键排定 10 秒后响。通知小图标统一用 `drawable/ic_notification`（白剪影矢量），原生前台服务与 `flutter_local_notifications` 共用同一个 —— 启动器图标是彩色的 mipmap/自适应图标，不能当通知小图标。
13. 已接受的 OS 限制：小米/华为「免解锁弹全屏」受限——屏幕会点亮，但需解锁后关闭（已确认，不再当 bug 处理）。

### 待办日程
14. 事件 = 标题 + 日期 + 可选时间 + 可选提醒档位（不设 / 准时 / 提前 5 分钟 / 15 分钟 / 30 分钟 / 1 小时 / 1 天）+ **联动闹钟开关**。两者**二选一**：开关关（默认）到点弹**普通通知**（标题 = 待办名，点通知进待办页）；开关开到点走**闹钟**那条链路（全屏 + 循环铃声 + 震动，与班次闹钟同一套），响铃界面除了标题还会显示这条待办的日期时间。两者联动：开着闹钟时提醒不可能是「不设」（界面上选「不设」会顺手关掉闹钟，开闹钟会把「不设」补成「准时」）。增删改与勾选之后立刻重排，不必等下次开 App。当天有待办时，日历底栏信息卡的日期行上显示「N 项待办」（不占新行，卡片高度不变）；列表里开了联动闹钟的那条带一个小铃铛图标。完成勾选后**字体变暗 + 删除线**并存。

### 我的 / 设置
15. **检查更新**：`UpdateChecker` 无鉴权拉公开仓库 GitHub API `/releases`（未认证限 60 次/小时/IP），自行按语义版本计算「最新正式版 + 最新测试版」并双通道展示；冷启动每日一次静默检查，**仅发现更新的正式版时弹窗**。
16. **应用内下载并安装 APK**：`downloadApk`（直接经 `browser_download_url` 流式下载）→ `installApk` → FileProvider 拉起系统安装器。
17. **权限检测卡**（6 项 / 3 组）：通知、闹钟和提醒（精确闹钟）、后台弹出界面、全屏通知、自启动（系统不可检测，恒「去查看」引导）、电池优化；未开启项一键跳转系统设置。
18. **日志查看**：只记录错误/崩溃（普通信息走 Logcat），`AlarmLog.kt` 按 256KB 自动裁剪；可查看 / 复制 / 清空。
19. 主题跟随系统 / 浅色 / 深色三档；5 种主色调；中 / English 双语；首次使用引导 + 每次更新弹更新说明。

**明确不做（现状仍成立）**：**日历上直接改某一天（换班/请假覆盖）**、2-2-3 Pitman 型「固定日班组/夜班组」模式、**周期中间插入删除某一天**、桌面小组件、云同步/备份/数据导入导出、工资/补贴记账、广告、商店上架、IM/天气/组织/好友。

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

## 4. 数据模型（Drift · schemaVersion = 7）

| 表 | 关键字段 / 说明 |
|---|---|
| `ShiftScheduleRows` | 排班方案：id、name、anchorDate、isCurrent + 班组配置（班组数 / 班组名 / 每班组相对基准日的天数偏移 `teamOffsets` / 我们的班组） |
| `ShiftClassRows` | 班次定义：scheduleId、order、name、abbr?、startMinute?、endMinute?、isRest、color、alarmEnabled、alarmMinute? |
| `ShiftCycleRows` | 周期序列：scheduleId、order、classId（第 N 天用哪个班次定义） |
| `ScheduleEvents` | 待办日程：title、date、timeMinute?、advanceRemindMinutes?、isCompleted、alarmEnabled（联动闹钟）、createdAt |
| `CustomAlarms` | 自定义闹钟：一次性 / 每天 / 每周（星期位掩码）等 |
| `ShiftAlarmOverrides` | 按天覆盖班次闹钟开关：主键 `day`（自 epoch 天数），false 的日期重排时跳过 |

> 某天的班次**不落库**，按「周期起始日 + 周期序列」实时计算（为未来「换班/请假覆盖」留余地）。
> **改表后必须重生成**：`dart run build_runner build --delete-conflicting-outputs`。
> **v5 → v6 迁移**：把旧的 `ShiftTypeRows`（每方案一串班次）拆成 `ShiftClassRows` + `ShiftCycleRows`，重复班次合并去重；旧表迁移后删除。
> **v6 → v7 迁移**：`ScheduleEvents` 加一列 `alarm_enabled`（默认 0 = 只弹通知，保持旧行为）。

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
- **应用图标**：`scripts/icon_gen.py` 是图形唯一来源（符号 = 白日历卡 + 环绕换班箭头；预览落 `work/icon-preview.png`），`scripts/icon_land.py` 落地到 Android / iOS / Web。Android 侧出货**自适应图标**三层 —— background（满幅渐变）/ foreground（安全区内的符号）/ monochrome（白剪影 + alpha 镂空，供 Android 13+「主题图标」上色）。**自适应安全区是直径 66dp 的圆（画布 108dp），方形符号须按内接圆缩，边长上限 ≈ 画布 43%** —— 按外接正方形画会被圆形蒙版削角。minSdk 26，真机永远走自适应那套，`mipmap-*/ic_launcher.png` 只是兜底。**产物都是生成物，改图形只改 `icon_gen.py`**。
- 性能策略：API 31+ 真实时模糊，26–30 假玻璃降级（半透明 + 饱和 + 高光）；弹窗遮罩统一 `barrierColor: Colors.black26`；底部弹层 `GlassPanel(solid: true)`。

## 7. 版本与发布链路（现状）

- 版本号唯一来源 `app/pubspec.yaml`（`X.Y.Z+build`），与 `app/lib/core/app_info.dart` 的 `appVersion` 同步，一致性由 `app/test/app_info_test.dart` 把关；末位 `Z=0` 为正式版（条目需归纳为总结版），非 0 为测试版（条目原样保留）。
- 应用内更新：`UpdateChecker` 无鉴权请求公开仓库 `/releases`（未认证限 60 次/小时）；APK 直接经 `browser_download_url` 下载安装。
- 本地发布：`scripts/release.ps1`（读版本号 → 校验 → 按末位自动标正式/预发布 → 上传 GitHub Release；发布说明写到 `tools\gh\release-notes-vX.Y.Z.md` 自动复用）；APK 产出 `dist/倒班助手Pro-vX.Y.Z.apk`（`dist/`、`*.apk` 均不入库）。
- 验收标准：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿。

