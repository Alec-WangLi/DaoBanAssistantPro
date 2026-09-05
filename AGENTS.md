# AGENTS.md — 倒班助手Pro 项目记忆（AI 开工必读）

> 本文件是给 AI 编码助手看的「项目大脑」。每次新对话，先按下面 SOP 走一遍再动手。

## 开工 SOP（每次新对话必须先执行，不要跳过）
1. 读本文件（项目全貌、约定、坑都在这里）。
2. 跑 `git log --oneline -15` 和 `git tag`，看最近改了什么、当前到哪个版本。
3. 读 `app/pubspec.yaml` 顶部的 `version:`（唯一版本号来源，与 `app/lib/core/app_info.dart` 同步）。
4. 之后再开始改代码。

## 一句话
倒班助手Pro —— Flutter 本地离线排班助手，包名 `com.daoban.shiftassistantpro`。自研排班引擎，轮转规则（四班两倒等）按倒班行业通用轮转规则独立实现。设计语言：**简洁 + 液态玻璃（磨砂模糊）+ Q弹动画**。

## 版本号规则（重要，务必遵守）
- 版本号形如 `X.Y.Z+build`。**`X.Y` 由用户决定，AI 只能改最后一位 `Z`（以及 `build` 同步 +1）**。
- 每轮改动收尾：`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 同步。
- 更新日志在 `app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh` / `_changelogEn`：prepend 新版本、删最旧一条、保持 10 条。**正式版（末位 `Z=0`）发布时，其条目必须重写为「归纳总结版」——合并自上一个正式版以来所有测试版的更新内容；测试版条目一律原样保留，只写自己这版改了什么。**（例：v0.4.0 条目归纳 0.3.1~0.4.0 全部更新；v0.3.0 条目归纳 0.2.1~0.3.0，0.2.4 条目保留至今。）
- 打完版本本地 `git tag vX.Y.Z`。
- 最近历史：0.1.45(+46) → **0.2.0(+47)**（第二大版）→ 0.2.1(+48)~0.2.4(+51) 测试版 → **0.3.0(+52)**（正式稳定版）→ 0.3.1(+53) 测试版 → 0.3.2(+54) 测试版 → 0.3.3(+55) 测试版 → 0.3.4(+56) 测试版 → 0.3.5(+57)~0.3.7(+59) 测试版 → **0.4.0(+60)**（正式稳定版）→ 0.4.1(+61) 测试版 → 0.4.2(+62) 测试版 → 0.4.4(+64)~0.4.9(+69) 测试版 → **0.5.0(+70)**（正式稳定版 · 开源）（当前）。更早见 `git log` 或应用内更新日志。

## 目录架构地图（app/lib）
```
main.dart / app.dart        入口 + 根 Widget（跟随系统深浅主题）
core/theme/                 深空蓝紫配色 + 深浅主题
core/glass/glass.dart        GlassPanel / GlassTile（BackdropFilter 模糊 + 渐变 + 白描边 + 高光，solid=近实心；`glassBlurDisabled`=低端机自动 + 「高级材质」手动开关取或，列表行默认 `enableBlur:false`；`GlassBlur` 供胶囊/按钮/提示条复用）
core/l10n.dart               L10n 静态 i18n（locale 'zh'/'en'，t(zh,en)，isEn，日期格式 helper）
core/app_info.dart           const appVersion（与 pubspec 同步）
core/widgets/                共享玻璃组件（见下）
domain/shift_rotation.dart   轮换引擎（纯 Dart 可单测）+ dayNumber()/dateOnly()
domain/lunar_info.dart       农历（lunar_plus）
data/                        Drift 表 + app_repository + Riverpod providers + seed
state/app_settings.dart      主题/主色调/语言（Riverpod StateNotifier）
features/calendar/           月历 + 排班编辑器 + 排班管理
features/alarm/              闹钟页 + AlarmService（原生联动）+ 响铃界面
features/schedule/           待办/日程
features/home/               底部导航壳（PageView + 悬浮玻璃胶囊）
features/profile/            我的页 + 权限卡 + app_dialogs（更新日志/使用引导）
```

## 共享玻璃组件（core/widgets/）
- `GlassSegment` 胶囊滑块 · `GlassSwitch` Q弹开关 · `GlassDialog` 通用弹窗 · `GlassButton` 主色玻璃实心按钮
- `GlassActionButton`（primary / secondary / danger 变体）· `GlassPressable`（统一玻璃触摸反馈）· `GlassDeleteButton`（红色调圆形玻璃删除钮）+ `dangerButtonStyle`（危险红确认按钮）
- `glass_pickers.dart` `showGlassTimePicker` / `showGlassDatePicker` / `showGlassMonthPicker`（底部玻璃弹层，已用 `solid:true`）
- `glass_snackbar.dart` `showGlassSnack(context, msg, {icon, iconColor})`（提示条玻璃化）
- `glass_input.dart` `glassInputDecoration(context, label)`

## 关键决策与坑
- 状态 Riverpod；数据 Drift（SQLite，纯本地离线，无后端）；农历 lunar_plus；通知 flutter_local_notifications。
- Drift 表：`ShiftScheduleRows` / `ShiftTypeRows` / `ScheduleEvents` / `CustomAlarms` / `ShiftAlarmOverrides`（按天覆盖班次闹钟，主键 `day` = 自 epoch 天数，`dayNumber()` 计算）。**当前 schemaVersion = 5**。
- **改 Drift 表后必须重生成**：`dart run build_runner build --delete-conflicting-outputs`。
- 闹钟链路：`setAlarmClock` → `AlarmReceiver` → `AlarmRingService`（前台服务 MediaPlayer + Vibrator + WakeLock + fullScreenIntent）；`MainActivity` 在 `super.onCreate` 前 `setShowWhenLocked`/`setTurnScreenOn`。
- `AlarmService.reschedule` 排**未来 60 天**班次闹钟 + 自定义闹钟（一次性/每天/每周，重复型由原生侧同一 id 续排）；按天覆盖值为 false 的日期跳过。
- 闹钟页 = **未来 30 天**班次闹钟（每条可单独开关、响过自动隐藏）+ 自定义闹钟分区；`Timer.periodic(1min)` + 回到前台重建；响过的一次性自定义闹钟自动删除。
- 已接受的 OS 限制：小米/华为「免解锁弹全屏」受系统限制——屏幕会点亮，但需解锁后关闭（已确认，不要再当 bug 处理）。
- 弹窗遮罩统一 `barrierColor: Colors.black26`（不能太暗）；底部弹层 `GlassPanel(solid:true)`（背景暗、面板不暗）。
- **`SYSTEM_ALERT_WINDOW` 不能删**：代码里没有 `WindowManager.addView`，但「后台弹出界面」权限卡（`AlarmService.checkOverlayPermission`→`Settings.canDrawOverlays`）依赖它在 manifest 声明——删了 App 就从系统「后台弹出界面」列表消失、小米/华为锁屏全屏闹钟可能弹不出。grep 判"未使用"是误判，勿再删。

## 构建 / 测试 / 发布
- 本沙箱：每次 pwsh 先 `. C:\...\shiftassistant\tools\build-env.ps1`（设 JAVA_HOME/ANDROID_HOME/PUB_CACHE 等到 `toolchain/`）。注意 `tools/` 与 `toolchain/` 已 gitignore，**不在 GitHub 仓库内**；他人克隆后按 `BUILD.md` 自装 Flutter/JDK/SDK。
- 改表后：`dart run build_runner build --delete-conflicting-outputs`。
- 验收标准：`flutter analyze` 0 error / 0 warning（约 7 条 info 提示可容忍）；`flutter test` 6/6。
- 构建：`flutter build apk --release --target-platform android-arm64` → `app/build/app/outputs/flutter-apk/app-release.apk`（**切 arm64 单 ABI**，APK 从 ~60MB 降到 ~21MB；仅 64 位设备）。
- 分发：复制到 `dist/倒班助手Pro-vX.Y.Z.apk`，用 `aapt2 dump badging` 校验 versionName/versionCode 与包名。
- 一键发布（GitHub Releases）：`scripts/release.ps1`。
- **正式签名**：release 用独立 keystore `app/android/keystore/release.jks`，口令在 `app/android/key.properties`（storeFile/storePassword/keyAlias/keyPassword），二者均 gitignore 不入库、**务必本地备份**（丢了无法再发可覆盖升级的包）。`key.properties` 缺失时 `build.gradle.kts` 自动回退 debug 证书便于本机调试。
- **检查更新（公开仓库）**：`UpdateChecker` 无鉴权拉 GitHub API `/releases`（未认证限 60 次/小时/IP），按语义版本自行计算「最新正式版 + 最新测试版」双通道展示；`downloadApk` 直接经 `browser_download_url` 下载安装。
- `dist/`、`*.apk`、`*.aab` 均 gitignore，不进仓库。

## 工作流
- 已升级为 **Superpowers 技能驱动**：新功能/改 UI → `brainstorming` 先磨需求；报 Bug → `systematic-debugging` 先根因后修复；写码 → `test-driven-development`；收尾 → `verification-before-completion` + `requesting-code-review`；多步/架构级 → `writing-plans` → `executing-plans`。
- 旧的 `/grill-me` 已被 `brainstorming` 取代，仅作轻量备胎。
- 用户偏好「全按推荐」、少磨叽；但涉及方案选型仍要给带推荐答案的方向、确认后再动手。
- 发布收尾：commit + `git tag vX.Y.Z` + `git push`（分支 + tag）之后，再跑 `scripts\release.ps1 -SkipConfirm` 把 APK 挂到 GitHub Release；发布说明先写到 `tools\gh\release-notes-vX.Y.Z.md`（脚本会自动复用），末位非 0 自动标为「预发布测试版」。

## 最近改动
- **v0.5.0**（正式稳定版 · 开源）：仓库公开（MIT）；更新检查去令牌，改用无鉴权公开 API，直接经 `browser_download_url` 下载安装。
- **v0.4.4~v0.4.9**：视觉迭代——极简黑白背景 + 悬浮玻璃胶囊导航 + 5 色主色统一直线图标与弹簧动效；应用图标重绘；日历今日卡避让胶囊；胶囊通透度、浅色可见性与主色对比度逐版微调。
- **v0.4.3**：排班编辑「班次名称」与标题行间距修复；响铃界面时间改粗体 + 「上滑关闭」改为跟随手指的滑块（阈值触发 / 未到位回弹）；新增「高级材质」开关（`appSettings.advancedMaterial`，默认开，关=全 App 去真实模糊，`glassBlurDisabled` 升级为 `ValueNotifier` + `lowEndDevice`/`advancedMaterialDisabled` 双来源，`GlassBlur` 统一胶囊/按钮/提示条模糊点）。
- **v0.4.2**：恢复 v0.4.1 误删的 `SYSTEM_ALERT_WINDOW`（「后台弹出界面」权限卡依赖它，见「关键决策与坑」）；使用帮助按最新版重写为 6 条；响铃界面液态玻璃化（`FlowingBackground` 流动光晕 + 玻璃胶囊标签 + `GlassButton` 再睡一会 + Q弹入场）。
- **v0.4.1**：发布切 **arm64 单 ABI**（APK 60.8→~21MB）；玻璃模糊全局降级 `glassBlurDisabled`（低端机内存<4GB 自动关，`main()` 经 `AlarmService.getTotalRamBytes` 判定）+ 闹钟/待办/我的/排班列表行 `enableBlur:false` 去逐行模糊；安全——release 换独立正式签名（脱离 debug 证书，**换签名后旧版需卸载重装**）、`AndroidManifest` 关 `allowBackup`、删未用 `SYSTEM_ALERT_WINDOW` 权限、`update_checker.downloadApk` 文件名 basename 消毒。
- **v0.4.0**（正式稳定版）：更新日志条目归纳 0.3.1~0.4.0 全部更新；待办完成态**字体变暗**（alpha 0.45）+ 删除线并存；提示条全面液态玻璃化（`glass_snackbar.dart` `showGlassSnack`）。
- **v0.3.7**：排班编辑器新增「法定班次」空白表（`_followHoliday`：跟随法定节假日、无周期轮换，班组收敛为「我」）；「班」调休标记改为农历行内联；统一玻璃触摸反馈（`GlassPressable`）+ 弹窗按钮玻璃化（`GlassActionButton` primary/secondary/danger、✕ 关闭）。
- **v0.3.6**：检查更新「去下载」改**应用内下载并安装**（`UpdateChecker.downloadApk` → `AlarmService.installApk` → MainActivity FileProvider 拉起系统安装器）；修复日历格子文字偏移与重启 StaleDataException 崩溃。
- **v0.3.5**：新建闹钟时间默认改为此刻（不再固定 7:00）；日历法定节假日整段标红——`lunar_info.dart` 内置 2025/2026 官方放假安排表（`_holidaySpans` / `_makeupDays`，**每年国务院发布下一年安排后需追加**），调休上班日打「班」小标记；今日信息卡法定节假日加红色胶囊标签；检查更新面板补「当前版本/正式版/测试版」小字说明。
- **v0.3.4**：检查更新改为直接拉 GitHub Releases `/releases` 列表、按语义版本自行计算最新版；删除无效的 `latest.json` 清单方案。
- **v0.3.3**：更新日志全量改为逐条要点排版；闹钟页「新建/测试」按钮新增共享组件 `GlassButton`（主色玻璃实心 + 白色玻璃描边，模糊/高光/Q 弹按压）。
- **v0.3.2**：更新日志结构修正——v0.3.0（正式版）条目重写为归纳总结版（含 0.2.1~0.3.0 全部更新），0.2.1~0.2.4 测试版条目恢复原样保留（正式版归纳规则已写入「版本号规则」）；日历格子加高（`_aspect` 0.85→0.78）+ 日期 18/班次 12/农历 11/星期 13（仅 `calendar_screen.dart`，网格自动滚动兜底）。
- **v0.3.1**：检查更新改查 `/releases` 全列表、按语义版本自己算「最新正式版 + 最新测试版」；面板双通道（正式版/测试版）各自可「去下载」；自动检查仍只对正式版弹窗；网络/限流异常提示更明确。
- **v0.3.0**（正式稳定版）：日历顶栏统一 40px 高（圆形钮重写为显式 40×40，去 IconButton 48px 热区）+ 年月跳转选择器（`showGlassMonthPicker`：年份滚轮 + 4×3 月份网格，底部玻璃弹层）；更新日志的 v0.3.0 条目归纳 0.2.1~0.3.0 全部更新（0.2.1~0.2.4 测试版条目保留）。
- **v0.2.4**：闹钟页 [新建/测试] 改用待办 FAB 同款定位（`FloatingActionButtonLocation` -76 偏移，底边对齐）；日历「切换」改纯图标钮、年月完整显示；新增「检查更新」（GitHub `/releases/latest` 只认正式版 0.X.0，我的页手动 + 冷启动每日一次静默，发现新版弹窗跳下载页；需 `INTERNET` 权限 + `UpdateChecker`）。
- **v0.2.0**：使用引导图标化 + 全面统一液态玻璃（输入框/下拉/FAB/筛选/提示条）。

## 跨端规划备忘（未来，勿与当前 Android 版混谈）
- 目标：Windows / iOS / 鸿蒙 多端。Flutter 本身跨端，但**闹钟/通知是 Android 专属**，跨端需按平台重做：
  - **iOS**：flutter_local_notifications 可用；无前台服务/全屏 intent，锁屏响铃体验弱（Critical Alert 能力受限）；无精确闹钟。
  - **Windows**：flutter_local_notifications 通知支持有限，无闹钟前台服务；`MainActivity` 的 MethodChannel（openAppSettings/openUrl/installApk/playRingtone/startAlarm 等）需按 Windows 实现。
  - **鸿蒙**：HarmonyOS NEXT（纯鸿蒙）需用 OpenHarmony 的 Flutter 分支（flutter_ohos）重建；`flutter_local_notifications` / `drift`(sqlite3) / `path_provider` / MethodChannel / FileProvider 都要找 OHOS 对应物或重写。
- 本轮（v0.4.1）改动全部是纯 Dart 或 Android 清单级，**不给跨端留坑**。启动跨端时单独 `/grill-me` 一轮评估。

## 相关文档
- `README.md`（对外介绍）、`BUILD.md`（构建指南）、`PRODUCT_SPEC.md`（产品规格）、`LICENSE`（MIT）。
