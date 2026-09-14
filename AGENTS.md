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
- 每轮改动收尾：`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 同步。**这条由 `app/test/app_info_test.dart` 盯着** —— 两处不一致直接测试失败（v0.6.6~v0.6.9 曾漏改四轮，代价是「我的」页版本号显示错、升级后的更新弹窗再也不弹）。
- 更新日志在 `app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh` / `_changelogEn`：prepend 新版本、删最旧一条、保持 10 条。**正式版（末位 `Z=0`）发布时，其条目必须重写为「归纳总结版」——合并自上一个正式版以来所有测试版的更新内容；测试版条目一律原样保留，只写自己这版改了什么。**（例：v0.4.0 条目归纳 0.3.1~0.4.0 全部更新；v0.3.0 条目归纳 0.2.1~0.3.0，0.2.4 条目保留至今。）**这三条是长期规则（窗口固定 10 条、正式版归纳、测试版原样），v0.6.11 未改动。**
- 打完版本本地 `git tag vX.Y.Z`。
- 最近历史：0.1.45(+46) → **0.2.0(+47)**（第二大版）→ 0.2.1(+48)~0.2.4(+51) 测试版 → **0.3.0(+52)**（正式稳定版）→ 0.3.1(+53) 测试版 → 0.3.2(+54) 测试版 → 0.3.3(+55) 测试版 → 0.3.4(+56) 测试版 → 0.3.5(+57)~0.3.7(+59) 测试版 → **0.4.0(+60)**（正式稳定版）→ 0.4.1(+61) 测试版 → 0.4.2(+62) 测试版 → 0.4.4(+64)~0.4.9(+69) 测试版 → **0.5.0(+70)**（正式稳定版 · 开源）→ **0.6.0(+71)**（正式稳定版）→ 0.6.1(+72)~0.6.13(+84) 测试版 → **0.7.0(+85)**（正式稳定版 · 当前）。更早见 `git log` 或应用内更新日志。

## 目录架构地图（app/lib）
```
main.dart / app.dart        入口 + 根 Widget（跟随系统深浅主题）
core/theme/                 深空蓝紫配色 + 深浅主题
core/glass/glass.dart        GlassPanel / GlassTile（BackdropFilter 模糊 + 渐变 + 白描边，solid=近实心；`glassBlurDisabled`=低端机自动 + 「高级材质」手动开关取或，列表行默认 `enableBlur:false`；`GlassBlur` 供胶囊/按钮/提示条复用）
core/l10n.dart               L10n 静态 i18n（locale 'zh'/'en'，t(zh,en)，isEn，日期格式 helper）
core/app_info.dart           const appVersion（与 pubspec 同步，由 test/app_info_test.dart 把关）
core/design_tokens.dart      设计语言唯一来源：按**角色**命名的排版 / 明度 / 间距 / 图标 / 圆角 / 时长令牌（界面层只写角色名，不写字面量；由 test/design_tokens_test.dart 守门）
core/widgets/                共享玻璃组件（见下）
domain/shift_rotation.dart   轮换引擎（纯 Dart 可单测）+ dayNumber()/dateOnly()
domain/lunar_info.dart       农历（lunar_plus）
data/                        Drift 表 + app_repository + Riverpod providers + seed
state/app_settings.dart      主题/主色调/语言（Riverpod StateNotifier）
features/calendar/           月历（+ info_card_metrics：底栏信息卡高度的测算） + 排班编辑器 + 排班管理
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
- Drift 表：`ShiftScheduleRows` / `ShiftClassRows`（班次定义）/ `ShiftCycleRows`（周期序列）/ `ScheduleEvents` / `CustomAlarms` / `ShiftAlarmOverrides`（按天覆盖班次闹钟，主键 `day` = 自 epoch 天数，`dayNumber()` 计算）。**当前 schemaVersion = 6**。
- **改 Drift 表后必须重生成**：`dart run build_runner build --delete-conflicting-outputs`。
- 闹钟链路：`setAlarmClock` → `AlarmReceiver` → `AlarmRingService`（前台服务 MediaPlayer + Vibrator + WakeLock + fullScreenIntent）；`MainActivity` 在 `super.onCreate` 前 `setShowWhenLocked`/`setTurnScreenOn`。
- `AlarmService.reschedule` 排**未来 60 天**班次闹钟 + 自定义闹钟（一次性/每天/每周，重复型由原生侧同一 id 续排）；按天覆盖值为 false 的日期跳过。
- 闹钟页 = **未来 30 天**班次闹钟（每条可单独开关、响过自动隐藏）+ 自定义闹钟分区；`Timer.periodic(1min)` + 回到前台重建；响过的一次性自定义闹钟自动删除。
- 已接受的 OS 限制：小米/华为「免解锁弹全屏」受系统限制——屏幕会点亮，但需解锁后关闭（已确认，不要再当 bug 处理）。
- **应用图标是全脚本生成的**：`scripts/icon_gen.py` 出图形（预览落 `work/icon-preview.png`），`scripts/icon_land.py` 落地到 Android / iOS / Web。产物 —— `mipmap-anydpi-v26/ic_launcher.xml`、`drawable-*/ic_launcher_{background,foreground,monochrome}.png`、各尺寸 PNG —— 都是生成物，**别手改**；改图形只改 `icon_gen.py`。几何常量彼此咬合（自适应安全区是**直径 66dp 的圆**，方形符号须内接，边长上限≈画布 43%），改一个要连带验另两个，约束写在常量旁。minSdk 26，真机永远走自适应那套，`mipmap-*/ic_launcher.png` 只是兜底。
- **README / 酷安配图是生成的，别手改 `docs/images/` 里的 PNG**：原始截图由 `app/tool/promo/render_promo_test.dart` 出（复用 `tool/visual/visual_harness.dart`，但用自己的一份屏单和自己的假库 —— 补了待办与自定义闹钟、并把「今天」调到白班，否则拍出来是空屏、「闹钟：未开启」），合成由 `scripts/make_promo_images.py` 做（套机身外框 → `docs/images/`，透明底以便 GitHub 深浅主题都能显示；另出大图与封面到 `work/promo-out/`，不入库）。改配图就改这两个脚本再各跑一次；酷安发帖稿在 `docs/coolapk-post.md`。
- 弹窗遮罩统一 `barrierColor: Colors.black26`（不能太暗）；底部弹层 `GlassPanel(solid:true)`（背景暗、面板不暗）。
- **`SYSTEM_ALERT_WINDOW` 不能删**：代码里没有 `WindowManager.addView`，但「后台弹出界面」权限卡（`AlarmService.checkOverlayPermission`→`Settings.canDrawOverlays`）依赖它在 manifest 声明——删了 App 就从系统「后台弹出界面」列表消失、小米/华为锁屏全屏闹钟可能弹不出。grep 判"未使用"是误判，勿再删。

## 构建 / 测试 / 发布
- 本沙箱：每次 pwsh 先 `. C:\...\shiftassistant\tools\build-env.ps1`（设 JAVA_HOME/ANDROID_HOME/PUB_CACHE 等到 `toolchain/`）。注意 `tools/` 与 `toolchain/` 已 gitignore，**不在 GitHub 仓库内**；他人克隆后按 `BUILD.md` 自装 Flutter/JDK/SDK。
- 改表后：`dart run build_runner build --delete-conflicting-outputs`。
- 验收标准：`flutter analyze` 0 error / 0 warning（约 4 条 info 提示可容忍）；`flutter test` 全绿（当前 141 条，只增不减）。
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
- **v0.7.3**（测试版 · 修「待办添加/保存点了没反应」+ 两处观感）：① **根因是 `GlassDialog` 内容区那句 `ConstrainedBox(maxHeight: constraints.maxHeight - 100)`** —— 在 `Column` 里子组件拿到的是**无界高度**，`constraints.maxHeight` 是无穷，那个上限形同虚设。于是键盘弹起、可用高变小时，内容把底部的操作按钮**挤出面板**：按钮还画在屏幕上，却已经不在弹窗的可点区域内，手指落下去穿到遮罩上 —— **弹窗关闭、什么都没存**。v0.7.2 把「联动闹钟」这一行加进待办弹窗，正好把内容顶过了那条线（真机像素采样：面板底边 y≈1486，按钮画在 1458~1595）。改成 `Flexible + SingleChildScrollView`：内容多了在卡内滚动，按钮永远在面板里。**这条对所有用 `GlassDialog` 的弹窗都成立**（新建闹钟、清空重置、版本更新…），只是它们内容还没多到踩爆。回归测试见 `todo_dialog_test.dart` 的「键盘弹起…」用例 —— 视口取 560 高 + `FakeViewPadding(bottom: 120)` 逼出溢出，断言「按钮底边 ≤ 面板底边」且保存真的写库；**已反向验证过：把修复还原成旧写法，这条用例会红**。排查时的一个教训：`adb shell input tap` 的坐标要按**当帧**测量，键盘弹出/收起会让弹窗整体位移（同一次「点添加」因此时好时坏），别拿上一次的坐标硬套。② 日历格子：`cellShift` 13→12、胶囊左右内边距 6→4（`spaceXs`）、并给胶囊左右各加 4px 硬边距（`_chipSideGap`）—— 两个字时胶囊原本只剩 1.5px 余量、贴着格子边与选中滑块。③ 待办与自定义闹钟列表的删除键改成 `compact: true`（只剩图标、中性色、按下才转红）—— `GlassDeleteButton` 的注释本来就把分工写清楚了：48pt 红圆是给「一屏的主删除动作」的，密集列表该用紧凑形态；另两处（排班管理、编辑器班次行）本来就是紧凑的。另：更新日志是**纯文本渲染**的，别往里写 markdown（此前 v0.7.1/v0.7.2 的条目里混进了 `**`，用户会看到星号，已一并清掉）。
- **v0.7.2**（测试版 · 真机反馈修正 + 待办联动闹钟）：① 日历格子三处调整 —— **日期回到居中**（v0.7.1 把它放在左上角，而格子是圆角矩形、左上角那一小块是切掉的，日期贴着内容框左缘就蹭到圆角外、看着像溢出格子，班组多、格子矮时最明显）；**班次字号调小**（`cellShift` 15→13、缩放上限 1.35→1.25，单字上限 20.25→16.25）；**胶囊里的文字改套 `FittedBox(scaleDown)`**，删掉原来那段「字数 × 基准字号」算可用宽度的写法 —— 那是**零余量**的，两字简称差一点点就退化成「上…」（真机实测），系统字号一放大整串字直接消失（那段算式压根没考虑 `textScaler`）。同时给视觉工装加了 `09_calendar_long_abbr` 变体（把「12 天长周期」那套设成当前方案，简称是「上夜/下夜」两个字），因为内置模板的简称全是单字、单字看不出胶囊放不放得下 —— 这类问题只有看图能发现。② **修「编辑待办」弹窗的提醒档位**：v0.7.1 只改到了「添加」弹窗 —— 两处那段 `onTap` 的换行格式不同，`replace_all` 只命中一个，而我没有核对命中数就当了事（教训：多行块用 `replace_all` 后要 grep 一遍数量）。根治办法是把两个弹窗的字段抽成**一份** `_EventFields`（新增测试 `todo_dialog_test.dart` 钉住「两个弹窗都弹得出档位选择器」，判据是「提前1天」这类只有弹层画得出的标签）。③ **待办「联动闹钟」开关**：DB 加 `schedule_events.alarm_enabled`（schemaVersion 6→7，只有一次 `addColumn`，迁移测试只手抄了 `schedule_events` 一张表的 v6 形态 —— v5→v6 那种重建表式迁移才需要抄全套）；开走到点全屏响铃（`scheduleNativeAlarm`，与班次闹钟同一套），关走普通通知，**二选一**；两者联动（选「不设」顺手关闹钟、开闹钟把「不设」补成「准时」）。闹钟载荷从「一个字符串」扩成 **`AlarmRing{title, detail}`**（原生加 `detail` extra，`AlarmReceiver` 透传给响铃服务与拉起界面的 Intent，`MainActivity` 用 `onAlarmFired` 回一个 map，`getPendingAlarmLabel` 改名 `getPendingAlarm`），响铃界面因此能显示「什么事、几点」。取消待办提醒时**两种 PendingIntent 都要扫**（同一 id 段挂 `AlarmReceiver` 与 `TodoReminderReceiver` 两个目标，只扫一种会留下幽灵闹钟）。真机（Redmi K90 Pro Max，adb）验证过：日历、信息卡「3 项待办」、编辑弹窗弹得出档位选择器、联动开关联动、以及闹钟链路端到端（测试闹钟全屏响铃 + 上滑关闭）。
- **v0.7.1**（测试版 · 日历格子重做 + 自定义铃声 + 待办提醒修复）：三块独立改动。
  **① 日历格子**：班次从 12px 彩字改成**带底色的胶囊**（配方沿用信息卡「其他班组」色块那套：14% 淡染 + 45% 描边 + `radiusS` + `inkFor` 文字），日期降到左上角 13px 当定位标记、农历留在底部；整格内容按 `(cellH − 内缩) / 57` 等比缩放（夹在 1.0–1.35），此前的病是**字固定、格子活** —— 格子长高字不跟着长，格子里近四成是空的。**无班次**的方案（`isBlank`，cycle 为空、`teamShift` 返 null）整月退回原来的居中两行排布（日期钉左上会变成「上角一个日期、底部一个农历、中间空一格」）；格内容宽 < 34（小窗 200 宽只有 21）不画胶囊、退回彩色文字；胶囊字号还要被宽度兜一次底（`min(s×15, 可用宽/字数)`），否则两字简称会显示成「早…」。选中那格的胶囊走**实心 + `onSolid`**，实心态跟**滑块吸附的那一格**走（拖动中取 `_nearestDateFromVisual()`，跟 `_selected` 的话手指滑过的中间格会停在「淡染压在淡主色底上」的糊态）。
  **两个踩出来的坑**：其一，`DateTime.==` 连 `isUtc` 一起比，而 `dateOnly()` 给的是 UTC、网格里逐格构造的是本地日期 —— `date == _selected`／`date == today` **恒为假**，网格里「今天」的日期从来没加粗过（新增 `isSameDay(a,b) => daysBetween(a,b)==0`，别再写 `==`）；其二，选中块的 `boxShadow`（主色 25%）会从半透明填充**内部**透出来，块内实际吃到约 33% 主色，把实心橙胶囊洗成棕 `#C28758` —— 试过改成不透明填充，结果把选中那格的日期/胶囊/农历全糊没了（这一层画在网格之上，必须半透明），最后是**去掉阴影**，只留 2px 主色描边 + 13% 淡染。信息卡定高计算跟着加了一项 `hasTodoHint`（见③）。
  **② 自定义铃声**：系统文件选择器（SAF `ACTION_OPEN_DOCUMENT`）选音频 → 复制进 `filesDir/ringtone/` 存 `file://`。**不存选择器给的 `content://`**：那种授权不持久，重启或清理后失效，而失败发生在响铃那一刻、用户听不到任何错误。`AlarmSound` 把「放哪个音」收成一处，两条响铃链路（`MainActivity.startAlarm` / `AlarmRingService`）共用，并**在自选文件坏掉时回落内置铃声** —— 此前两处都是空 `catch`，等于一个完全不出声的闹钟。注意 `FlutterActivity extends android.app.Activity`（不是 `ComponentActivity`），用不了 `registerForActivityResult`，只能 `startActivityForResult` + `onActivityResult`，且**必须调 super**（插件的授权结果也走那里转发）。文件超 32MB 拒绝并给专门的错误码（「太大」和「读不出来」得在界面上说成两句不同的话）。
  **③ 待办提醒真正生效**：`advanceRemindMinutes` 此前只有建表、写入、当副标题显示三处，**没有任何排定逻辑** —— 用户设了提前提醒、到点什么都不会发生。新增 `TodoReminderReceiver` + `AlarmScheduler.scheduleQuiet`（`setExactAndAllowWhileIdle` 而**不是** `setAlarmClock`：后者会被系统当成真闹钟，状态栏常驻闹钟图标；无精确闹钟权限时退化成非精确而不静默不响），id 段 `20000..21000`。**刻意不走 `flutter_local_notifications` 的 `zonedSchedule`**：它的排定 API 只收 `TZDateTime`，而 `tz.local` 从来没设过（`init` 里只有 `initializeTimeZones()`、依赖里也没有 `flutter_timezone`），照那样排会整体差一个时区偏移且不报错 —— 原生这条走 epoch 毫秒，不碰时区。提醒档位补「准时」并扩到 5/15/30/60/1440 分钟（新增 `showGlassOptionPicker`；选项类型**不能用可空**，否则「选不设」和「点外面关掉」分不开）；增删改勾选待办后立刻调 `rescheduleEventReminders`（只重排待办，不扫上千条班次闹钟），不必等下次开 App。信息卡日期行加「N 项待办」徽章（形状与「今天」徽章对齐、走淡染配方），**不新增行**：这一行本来就有个等高的徽章，卡片高度一像素不动 —— 但定高计算仍要按月预留 `hasTodoHint`，因为行高被字体压紧时（测试字体就是）徽章会比日期字高一点点；窄屏与横屏侧栏都不显示（实测那一行会横向溢出 24px）。顺手把散在 6 处的重排调用收敛成 `AlarmService.rescheduleAll(repo)`（自己读齐排班/自定义闹钟/按天覆盖/待办），`home_shell` 保留用三个流当就绪闸（并补上 `eventsProvider` 的 `ref.listen`，漏了会出现「待办先到、另两个后到，重排跑了但没排待办」）；视觉工装种子库补了待办，否则新徽章在图上根本画不出来。
  **已知未做**：重启手机后待办提醒与班次闹钟一样，要等下一次打开 App 才重排（既有行为，原生侧读 drift 库代价太大）。
- **v0.7.0**（正式稳定版 · 图标、滑块与文案核对）：**应用图标重画**为「日历 + 换班箭头」并补上 Android **自适应图标**三层（background 满幅渐变 / foreground 安全区符号 / monochrome 白剪影给 Android 13+ 主题图标）—— 关键约束是**自适应安全区为直径 66dp 的圆**（画布 108dp），方形符号须按**内接圆**缩到画布约 43%，按外接正方形画会被圆形蒙版削角；图形唯一来源 `scripts/icon_gen.py`，`scripts/icon_land.py` 落地三端，产物全是生成物别手改。**响铃界面上滑关闭滑块加宽**（可见轨道 56→72、触摸热区 112），并修好矮屏溢出（横屏 900×420 溢 4px、小窗 200×400 溢 108px —— 后者是 84px 时钟在 200dp 宽里折成两行顶爆整列；修法是 `AppLayout.isShort` 各收一档 + 时钟 `FittedBox(scaleDown)`），响铃界面同时纳入视觉工装（`08_ringing`）。通知小图标从 `@mipmap/ic_launcher` 改回 `drawable/ic_notification`（插件按 `getIdentifier(name,"drawable",pkg)` 查、且按白剪影渲染，启动器图标两种形态都不适用）。发版前做了一次**用户可见文案核对**，修好三处实质失真：使用帮助把「切换排班」说成在排班管理页（实际全 App 只有日历顶栏 `setCurrentSchedule` 一处能切）、同一段让人去找界面上不存在的「法定班次」（真标签是「跟随法定节假日（无班次）」、「法定班次」只是自动填的方案名）、「编辑待办事项」弹窗整块写死中文（同文件的「添加」弹窗是本地化的）；另修「版本更新」副标题（写「本版本」、实际给 10 条历史）与检查更新弹窗复用「不设」表示「暂无该渠道」。README/BUILD.md 对齐（BUILD.md 的签名说明此前停在「复用 debug 证书」，v0.4.1 就已换独立正式签名）。（v0.6.13 测试版是同一批改动的预发布，不再单列。）
- **v0.6.12**（测试版 · 收口）：底部导航四个图标 20→24（矮屏仍保持 20 —— 那里胶囊更矮，24 会溢出 1px）；`design_tokens_test.dart` 守门收口 —— 扫描前先把注释与字符串剥成等长空格（不再把里面的内容误判为违规）、`Icon(`/带子 widget 的调用按**配对括号**取参、间距类常量（名字含 Pad/Gap/Inset/Spacing）也须落在 4px 栅格上并支持 `// design-tokens-ignore: <理由>` 具名豁免（命中的豁免打进日志，故意不扫要看得见）；扫描目录纳入 `core/theme`，其中配色层 `app_colors.dart` / `app_theme.dart` 显式豁免。令牌自检补一条完整性断言（新增阶梯令牌却漏写自检就红）；`durFlow` 正名为 `durRingEnter`（它是响铃界面的入场动画时长，不是背景光晕的循环）。
- **v0.6.11**（测试版 · 设计语言 v2 收口）：全 App 的排版 / 间距 / 图标收敛到 `core/design_tokens.dart` 的**角色令牌** —— 令牌从「按尺寸命名」（`fontBody` 14 / `fontCaption` 12，挑哪一档靠感觉，于是长出 12.5 / 13.5 / 14.5 / 15 / 22 这些「最像的」值）改成**按用途命名**（页面标题 / 卡片标题 / 行内主文字 / 次要说明 / 微标签，名字直接说明什么时候用）；文字明度收成两档（`inkMuted` 0.62 / `inkFaint` 0.35，此前散着 0.45 / 0.5 / 0.55 / 0.6）；间距归回 4px 栅格并单留一组「光学」微距（`gapHair` / `padChipV` / `gapIconText` / `gapIconTextLg`）；图标收成三档（16 / 20 / 24）；卡片圆角 20→22。新增 `app/test/design_tokens_test.dart` 守门 —— 界面层写死**下面这几类**即测试变红：`fontSize:` / `fontWeight:`、`onSurface` 系的 `.withValues(alpha:)`（文字明度）、`circular(<数字>)`、`Duration(milliseconds: …)`、`Color(0x…)`、`Icon`/`IconThemeData` 的 `size:`、以及落在 4px 栅格外的间距与间距类常量。**它不覆盖**装饰与玻璃配方里的 alpha（`Colors.white.withValues(alpha: …)` 这类）、`Color.fromARGB`、`Duration(seconds:)` —— 别把它读成「一切数值都管」（扫描为整文件级，已补上 `Icon(` 与 `size:` 跨行、三元跨行、`withValues` 跨行三类盲点的用例）。19 个界面 / 组件文件迁完、旧字号令牌删净、迁移期 `_pending` 豁免清空。外观只动了 14 处字号、约 12 处字重各一档。
- **v0.6.10**（测试版 · 版本号与信息卡高度）：修好「我的 → 关于」版本号停在 v0.6.5 的 bug（v0.6.6~v0.6.9 只涨了 pubspec，`app_info.dart` 漏改四轮 —— 连带 `lastSeenVersion` 卡住导致升级后的更新弹窗再也不弹、「检查更新」给已装版本挂下载按钮）；新增 `test/app_info_test.dart` 把「两处同步」从口头约定变成会失败的用例。底栏信息卡不再写死 248，改由 `features/calendar/info_card_metrics.dart` 按**本月实际最满的一天**用 `TextPainter` 实测（固定块 + 节假日徽章 + 农历行数 + 其他班组色块折行数），绝不裁字、网格拿到全部剩余高度；代价是换月时高度可能变一次。更新日志补回 v0.6.6~v0.6.9 并滚掉 v0.6.0 及更早；使用帮助新增「外观」「横屏 · 宽屏 · 小窗」两节。
- **v0.6.6~v0.6.9**：日历信息卡与日期网格的连续微调 —— 格子高度下限从过时的 80 降到实测需求（最后一行不再被卡片压住）；农历描述允许两行；底栏留白 120→84；格子内容随系统字号按需缩放；色条与面板上下对齐；撤掉卡片底部柔光、放开与胶囊的间距；节假日徽章自占一行并与其他班组色块统一配方、对比度过 AA。
- **v0.6.5**：小窗（小米小窗 / 分屏）修好 —— 系统把小窗的「顶部系统栏高度」报成整个窗口高度，每页的顶部安全区把整屏吃掉；按实测尺寸 200×400 重做小窗适配。
- **v0.6.0**（正式稳定版 · 周期排班编辑器）：排班模型重写为**两层轮换模型**——班次定义（配一次，时间/颜色/联动闹钟挂其上）+ 周期序列（长度即周期，1–60 天）；内置 **19 种常见倒班方式模板**，新增排班统一先走「选择你的倒班方式」（`shift_template_picker_screen.dart` 的顶层 `createScheduleFromTemplatePicker`，「我的 → 排班管理 → 新增排班」与「日历 → 切换排班 → 新增排班」两条入口共用）；班组用「周期起始日」表达，编辑器未来 14 天实时预览；持久层拆成 `shift_class_rows` + `shift_cycle_rows`，`schemaVersion 5 → 6` 迁移（旧数据自动升级、重复班次合并）；日历其他班组改色块列表、跨午夜时间文案本地化。
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
