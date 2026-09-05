# 倒班助手Pro · 产品与技术规格（现状规格 · v0.5.0）

> 本文档是**唯一权威规格**，反映当前实现现状（v0.5.0 正式稳定版）。早期「MVP 确认稿」的功能已随 0.2~0.5 各版演进并入正文，不再单列历史章节。

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

## 2. 功能范围（现状 v0.5.0）

### 排班日历
1. **通用轮换引擎**：任意周期长度 / 任意班次组合 / 任意班组数量；轮换算法为纯函数，某天班次由（日期 − 锚点日）与班次序列取模得出，天数差用 UTC 日期整数，避免时区问题。
2. **月视图**：每日班次按颜色区分、今日高亮；上/下月翻页、一键回今天、**年月跳转选择器**（年份滚轮 + 4×3 月份网格）。
3. **农历 + 法定节假日**：每格显示农历日 / 节气 / 节日；**法定节假日整段标红**（`lunar_info.dart` 内置 2025/2026 国务院放假安排表 `_holidaySpans` / `_makeupDays`，**每年国务院发布次年安排后需追加**）；**调休上班日带「班」标记**；点选某天展示干支、生肖等完整农历。
4. **法定班次（空白表）**：方案可设为跟随法定节假日、无周期轮换（节假日自动休班），班组收敛为「我」。
5. **多套排班方案**并存、一键切换、增删改管理；锚点日决定整表相位。
6. **多班组视图**：可查看其他班组某天班次，便于交接班对照。

### 联动班次闹钟
7. 每个班次独立设置响铃时间与开关；`AlarmService.reschedule` 按排班自动排定**未来 60 天**并自动续排。
8. **未来 30 天预览列表**：每条可单独开关（写入按天覆盖表 `ShiftAlarmOverrides`，主键 `day` = 自 epoch 天数，由 `dayNumber()` 计算），响过后自动隐藏；`Timer.periodic(1min)` + 回前台重建刷新。
9. **自定义闹钟**：一次性 / 每天 / 每周（多选星期，位掩码）；重复型由原生侧同一 id 续排；新建默认时间即此刻。
10. **可靠响铃**：系统精确闹钟（`setAlarmClock`）+ 前台服务（`AlarmRingService`：MediaPlayer + Vibrator + WakeLock + fullScreenIntent）+ 全屏响铃界面（贪睡 5 分钟 / 上滑关闭）；铃声内置或系统可选、可试听；**测试闹钟**一键排定 10 秒后响。
11. 已接受的 OS 限制：小米/华为「免解锁弹全屏」受限——屏幕会点亮，但需解锁后关闭（已确认，不再当 bug 处理）。

### 待办日程
12. 事件 = 标题 + 日期 + 可选时间 + 可选提前提醒（固定 15 分钟开关）；完成勾选后**字体变暗 + 删除线**并存。

### 我的 / 设置
13. **检查更新**：`UpdateChecker` 无鉴权拉公开仓库 GitHub API `/releases`（未认证限 60 次/小时/IP），自行按语义版本计算「最新正式版 + 最新测试版」并双通道展示；冷启动每日一次静默检查，**仅发现更新的正式版时弹窗**。
14. **应用内下载并安装 APK**：`downloadApk`（直接经 `browser_download_url` 流式下载）→ `installApk` → FileProvider 拉起系统安装器。
15. **权限检测卡**（6 项 / 3 组）：通知、闹钟和提醒（精确闹钟）、后台弹出界面、全屏通知、自启动（系统不可检测，恒「去查看」引导）、电池优化；未开启项一键跳转系统设置。
16. **日志查看**：只记录错误/崩溃（普通信息走 Logcat），`AlarmLog.kt` 按 256KB 自动裁剪；可查看 / 复制 / 清空。
17. 主题跟随系统 / 浅色 / 深色三档；5 种主色调；中 / English 双语；首次使用引导 + 每次更新弹更新说明。

**明确不做（现状仍成立）**：换班/请假覆盖、桌面小组件、云同步/备份/数据导入导出、工资/补贴记账、广告、商店上架、IM/天气/组织/好友。

## 3. 班次模型（默认配置，引擎通用）

四班两倒，4 天一个周期（App 内可改，引擎不绑定该配置）：

| 顺序 | 班次名 | 时间 | 是否工作 | 联动闹钟 |
|---|---|---|---|---|
| 1 | 白班 | 8:30–20:30 | 是 | 7:00 |
| 2 | 上夜班 | 20:30–次日 8:30（记在开始那天） | 是 | 19:30 |
| 3 | 下夜班 | 无（早 8:30 下班即休） | 休 | 否 |
| 4 | 大休 | 无 | 休 | 否 |

- 锚点日 = 自己班组「白班」的那一天，编辑器中为每个班组指定锚点日各自班次（`teamOffsets`）。
- 「法定班次」型方案（空白表）：`shiftTypes` 为空、跟随法定节假日，不做轮换。

## 4. 数据模型（Drift · schemaVersion = 5）

| 表 | 关键字段 / 说明 |
|---|---|
| `ShiftScheduleRows` | 排班方案：id、name、cycleLength、anchorDate + 班组配置（班组数 / 班组名 / 锚点日各班次下标 / 我们的班组） |
| `ShiftTypeRows` | 班次类型：scheduleId、order、name、startTime?、endTime?、crossesMidnight、isRest、color、alarmEnabled、alarmTime?、advanceMinutes、snoozeEnabled、snoozeMinutes |
| `ScheduleEvents` | 待办日程：title、date、time?、advanceRemindMinutes?、isCompleted、createdAt |
| `CustomAlarms` | 自定义闹钟：一次性 / 每天 / 每周（星期位掩码）等 |
| `ShiftAlarmOverrides` | 按天覆盖班次闹钟开关：主键 `day`（自 epoch 天数），false 的日期重排时跳过 |

> 某天的班次**不落库**，按锚点日实时计算（为未来「换班/请假覆盖」留余地）。
> **改表后必须重生成**：`dart run build_runner build --delete-conflicting-outputs`。

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
- 共享组件（`core/widgets/`）：GlassSegment（胶囊滑块）、GlassSwitch（Q弹开关）、GlassDialog、GlassButton（主色实心 + 玻璃描边）、GlassActionButton（primary / secondary / danger）、GlassPressable（统一玻璃触摸反馈）、GlassDeleteButton + `dangerButtonStyle`、玻璃弹层选择器（`showGlassTimePicker` / `showGlassDatePicker` / `showGlassMonthPicker`，底部 `solid` 近实心）、`glassInputDecoration`、`showGlassSnack`（提示条玻璃化）。
- 主题 token：**深空蓝紫渐变**；跟随系统深浅双套；5 种主色调（`AppColors.accentPalette`）；中英双语（L10n）。
- 性能策略：API 31+ 真实时模糊，26–30 假玻璃降级（半透明 + 饱和 + 高光）；弹窗遮罩统一 `barrierColor: Colors.black26`；底部弹层 `GlassPanel(solid: true)`。

## 7. 版本与发布链路（现状）

- 版本号唯一来源 `app/pubspec.yaml`（`X.Y.Z+build`），与 `app/lib/core/app_info.dart` 的 `appVersion` 同步；末位 `Z=0` 为正式版（条目需归纳为总结版），非 0 为测试版（条目原样保留）。
- 应用内更新：`UpdateChecker` 无鉴权请求公开仓库 `/releases`（未认证限 60 次/小时）；APK 直接经 `browser_download_url` 下载安装。
- 本地发布：`scripts/release.ps1`（读版本号 → 校验 → 按末位自动标正式/预发布 → 上传 GitHub Release；发布说明写到 `tools\gh\release-notes-vX.Y.Z.md` 自动复用）；APK 产出 `dist/倒班助手Pro-vX.Y.Z.apk`（`dist/`、`*.apk` 均不入库）。
- 验收标准：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿。

