# AGENTS.md — 倒班助手Pro 项目记忆（AI 开工必读）

> 本文件是给 AI 编码助手看的「项目大脑」。**只放每次开工都要知道的东西**，目标体积 ≤35KB。
> （旧版 405KB，实测被 harness 截断到 64KB、只注入了 15.9% —— 等于 SOP 从来没被完整执行过。）
> 历史细节不在这里：**版本流水** `docs/changelog/`、**逐条决策与坑** `docs/decisions/`。**不要通读那两处。**

## 开工 SOP（每次新对话必须先执行，不要跳过；每步都有成本上限）
1. **读本文件**（一屏，≤35KB）。
2. **一条命令拿现场**：`git log --oneline -8 && git tag | tail -5 && git status --short`，再读 `app/pubspec.yaml` 顶部的 `version:`（唯一版本号来源，与 `app/lib/core/app_info.dart` 同步）。
3. **报技能**（§技能纪律），一句话说清这次用哪几个、为什么。
4. **读规范层**：先读 `docs/standards/README.md`（三层分工、守门矩阵、哪条是自守、裁决顺序），写任何代码读 `docs/standards/dev-standards.md`（E1–E17）；动 UI / 视觉 / 玻璃 / 触觉再读 `docs/standards/design-principles.md`（D1–D16）。**再按任务挑一个 topic 文件**（下表），只读那一个；需要判重时才 `grep` 版本号进 `docs/changelog/`。
5. 之后再开始改代码。

| 你要动的东西 | 读这一个 |
|---|---|
| Drift 表 / 迁移 / Riverpod / 查询 | `docs/decisions/data.md` |
| 排班模型 / 时段 / 覆盖 / 空白表 / 解析 / 法定节假日数据 | `docs/decisions/schedule.md` |
| 闹钟 / 响铃 / 原生侧 | `docs/decisions/alarm.md` |
| 待办 / 重复待办 / 归档 | `docs/decisions/todo.md` |
| 液态玻璃 / 着色器 / 共享玻璃件 | `docs/decisions/glass.md` |
| 桌面小组件 / RemoteViews | `docs/decisions/widget.md` |
| 颜色 / 布局 / 弹窗 / 触觉 / 字号 / 视觉工装 | `docs/decisions/ui-rules.md` |
| 性能测量 / 装测试包 / 动包名 | `docs/decisions/perf-testing.md` |
| 发版 / 分支 / 签名 / 官网部署 | `docs/decisions/release.md` |

## 技能纪律（2026-11-06 用户拍板；此前多次「该用没用」，靠记忆汇报）

> 触发这次立规矩的事实：v0.12.8~v0.12.10 三轮工作里，`skill` 工具调用 **0 次**，而其中至少有 4 处本该用（TDD、系统化排障、写计划、收尾前验证）。结论不是"技能不重要"，而是"没有强制动作 → 一定忘"。

**规矩一：开工先报技能。** 动第一行代码之前，先说一句「这次用 X、Y，因为……」。说不出来就是没想过 —— 那也要说「这次不需要，因为……」。**这句话是给用户看的，用户可以当场否决。**

**规矩二：收尾前强制过 `verification-before-completion`。** 说"好了/修完了/全绿"之前，必须有本回合跑出来的原始输出作证据（测试尾行、analyze 的 issues 计数、curl 回来的 JSON）。**"我记得跑过了"不算证据。**

**规矩三：新类型的活先扫一眼能力库。** 遇到没见过的工作类型，先看 `~/.dsh/skills/`（约 29 个；`implement` `to-tickets` `test-driven-development` `systematic-debugging` `verification-before-completion` `code-review` `writing-for-agents` `wait-what` `grilling` `stop-slop` 与本项目最相关），再判断要不要用 `learn` / `find-skills` 去外面搜。**搜到有用的报给用户，不擅自安装。**

**规矩四：不许用 `capability-router` 插件。** 用户 2026-11-06 明确：「这个插件已经落伍了，所以我才不启用它」—— 能力匹配靠规则一，不靠那个插件。

## 方案闸门（2026-11-10 用户拍板：说「先列一下」≠ 授权动手）

> 触发事实：用户说「你先给我列一下，然后我看一下合不合理」，AI 一边列任务清单一边把代码、用例、版本号、构建、提交、发版一路做完。用户原话：「我不想这样啊。」

- **触发词**：先列一下 / 给我看看 / 出个方案 / 先说方案 / 有哪些 / 合不合理 / 你觉得呢。听到任何一个，**本轮只输出方案**（改哪些文件、怎么改、风险、备选），**不改文件、不跑构建和测试、不升版本、不提交、不发版**，末尾问一句「按这个做吗？」。
- **任务清单不是提案**：`update_plan` 列出来就等于开工了，别拿它当「给用户看方案」。
- **授权只有一种**：用户明确说「开做 / 可以 / 按这个来 / 全按推荐」。**例外**：用户同一句里说「直接做 / 不用问了」。

## 一句话
倒班助手Pro —— Flutter 本地离线排班助手，包名 `com.daoban.shiftassistantpro`。自研排班引擎，轮转规则（四班两倒等）按倒班行业通用轮转规则独立实现。设计语言：**简洁 + 液态玻璃（磨砂模糊）+ Q弹动画**。

## 版本号规则（重要，务必遵守）
- 版本号形如 `X.Y.Z+build`。**`X.Y` 由用户决定，AI 只能改最后一位 `Z`（以及 `build` 同步 +1）**。
- 每轮改动收尾：`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 同步。**这条由 `app/test/app_info_test.dart` 盯着** —— 两处不一致直接测试失败（v0.6.6~v0.6.9 曾漏改四轮，代价是「我的」页版本号显示错、升级后的更新弹窗再也不弹）。
- 更新日志在 `app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh` / `_changelogEn`：prepend 新版本、删最旧一条、保持 10 条。**正式版（末位 `Z=0`）发布时，其条目必须重写为「归纳总结版」——合并自上一个正式版以来所有测试版的更新内容；测试版条目一律原样保留，只写自己这版改了什么。**（例：v0.4.0 条目归纳 0.3.1~0.4.0 全部更新；v0.3.0 条目归纳 0.2.1~0.3.0，0.2.4 条目保留至今。）**这三条是长期规则（窗口固定 10 条、正式版归纳、测试版原样），v0.6.11 未改动。**
- 打完版本本地 `git tag vX.Y.Z`。
- **完整版本史不在本文件**：版本号链见 `docs/changelog/version-history.md`，每版改了什么见 `docs/changelog/v0.X.md`。判重时 `grep` 版本号即可，**不要通读**。

## 分支与发布（2026-09-21 用户定；事故复盘见 `docs/decisions/release.md`）

- **测试版（`Z ≠ 0`）在 `beta` 上做、提交、发布**：commit → `git push origin beta` →
  `git tag vX.Y.Z && git push origin vX.Y.Z` → `pwsh -File tools/_run-release.ps1`
  （它已设好 `GH_CONFIG_DIR`；hand-roll 命令必撞 gh 未认证 —— `build-env.ps1` 把 `APPDATA` 重定向了）。
- **`main` 只在发正式版（`Z = 0`）时收一次合并**（`--no-ff`），正式版 tag 打在 main 上。
- **`latest.json` 的 `stable` 只认 main 上那份**：beta 那份停在旧值是正常的。脚本 8b 步会切到 main、
  **只改本次发布那个通道的字段**再推回 —— **别整份覆盖**（会把 stable 打回旧版，v0.11.0 就是这么丢的）。
- **发完必须 curl 一次 main 的 `latest.json`** 核对版本号：脚本打印的「发布成功」只覆盖 Release 上传那一步。
- `ci.yml` 的 `EXPECTED_TESTS` 是**分支相关项**（beta 与 main 两个数），改一边记得另一边；
  **基线只认 CI 日志里那行「用例数 N」**，推算值不算。
- main 的 CI 已随 v0.13.0 收敛，红了按真 bug 查（旧的「比 beta 少 148 行」结论已作废）。

## 目录架构地图（app/lib）
```
main.dart / app.dart        入口 + 根 Widget（跟随系统深浅主题）
core/theme/                 深空蓝紫配色 + 深浅主题
core/glass/glass.dart        **标准档 + 档位标志**。GlassPanel / GlassTile（BackdropFilter 模糊 + 渐变 + 白描边，solid=近实心）；列表行默认 `enableBlur:false`；`GlassBlur` 供胶囊/按钮/提示条复用。
core/glass/liquid_lens.dart  **液态档的全部**：`LiquidLensSpring`（阻尼谐振子，帧间隔封顶 16ms）→ `LiquidLensShape`（两端半径可不同的圆 + 外公切线 = 水滴）→ `LiquidLens`（轮廓裁剪 + 半透明主色 + 光谱环 + 浮起阴影 + 把胶囊那条边折进去）+ `CapsuleRimPainter`（胶囊的边光与「光跟随滑块」）。
features/home/glass_nav_bar.dart  底栏；**两条档位各一棵树**（`_buildStandard` / `_buildLiquid`），手势与动画状态机两档共用 —— 于是交互契约两档一字不差。
core/l10n.dart               L10n 静态 i18n（locale 'zh'/'en'，t(zh,en)，isEn，日期格式 helper）
core/app_info.dart           const appVersion（与 pubspec 同步，由 test/app_info_test.dart 把关）
core/design_tokens.dart      设计语言唯一来源：按**角色**命名的排版 / 明度 / 间距 / 图标 / 圆角 / 时长令牌（界面层只写角色名，不写字面量；由 test/design_tokens_test.dart 守门）
core/haptics.dart            触觉词汇表：三档 `Haptics.select()/commit()/modeEnter()` + 模块级 `hapticsDisabled`（与 `liquidGlassEnabled` 同路，一处赋值全 app 生效）；挂动作不挂按压；除本文件外不许调 `HapticFeedback.*`，由 test/haptics_guard_test.dart 守门；Android 上它只管路由，出声的是 `android/.../Haptics.kt`（预定义 click，见 `docs/decisions/ui-rules.md`）
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
features/widget/            桌面小组件的快照生成与投递（原生侧见 android/.../ShiftWidgetBase.kt + 三张 `*WidgetProvider.kt`）
```

## 共享玻璃组件（core/widgets/）
- `GlassSegment` 胶囊滑块 · `GlassSwitch` Q弹开关 · `GlassDialog` 通用弹窗 · `GlassButton` 主色玻璃实心按钮。
  **这四个件里，`GlassSegment` 与 `GlassSwitch` 自 v0.10.9 起有液态档**（两条档位两棵树，关掉时与之前逐像素相同）；`GlassDialog` / `GlassButton` 与其余共享玻璃面**仍然只有标准档**。液态档的判据只许出现在 `core/glass/glass.dart`（定义处）与**六个调用点**（`features/home/`、`core/widgets/glass_check.dart`、`core/widgets/glass_segment.dart`、`core/widgets/glass_switch.dart`、`features/alarm/alarm_ringing_screen.dart`、`features/calendar/calendar_screen.dart`）—— 由 `test/liquid_scope_guard_test.dart` 扫源码守着（**名单里没有新抽出来的 `liquid_track.dart` / `liquid_lens_controller.dart`：它们不读档位**）。
  **往别处搬之前先想清楚那一处的观感** —— v0.10.2 就是因为光加到了那些 `enableBlur:false` 的列表行上，用户在闹钟页与待办页各报了一次「边缘有点丑」。判据：那处得同时有 ① 胶囊形的容器 ② 会滑动/会被按住的指示块 ③ 四周有空隙让它凸出去；**静止的玻璃面不加**（静止时这套东西一个像素都不画，加了等于没加）。
- `GlassPill`（**顶部栏那种紧凑玻璃胶囊**：年月、「今天」，以及各页标题行右侧的动作入口。`accent:true` = 实心主色渐变 + 白字，内容一律写 `Colors.white`；默认 40dp 高、圆角 `radiusL`。与 `GlassButton` 的分工是「栏内控件 vs 主操作」，别混用）
- `GlassActionButton`（primary / secondary / danger 变体；`onPressed` 返回 `Future` 时本次动作跑完前不再响应点击）· `GlassPressable`（统一玻璃触摸反馈）· `GlassDeleteButton`（红色调圆形玻璃删除钮）+ `dangerButtonStyle`（危险红确认按钮）· `glass_dialog.dart` 的 `dialogCloser(context)`（弹窗动作在 `await` 之后关窗要用它，见「关键决策与坑」）
- `glass_pickers.dart` `showGlassTimePicker` / `showGlassDatePicker` / `showGlassMonthPicker`（底部玻璃弹层，已用 `solid:true`）
- `glass_snackbar.dart` `showGlassSnack(context, msg, {icon, iconColor})`（提示条玻璃化）
- `glass_input.dart` `glassInputDecoration(context, label)`

## 关键决策与坑（索引）

> 已按主题搬进 `docs/decisions/`（原文一字未改）。这里只留**动手前必看**的那几条 —— 每一条都对应一次真实事故。

1. **改 Drift 表后必须重生成**：`dart run build_runner build`（表定义与迁移都改了才算）。
2. **`saveSchedule` 必须按 id 增量更新，不能删光重建** —— 删光重建会让每次保存都换掉全部班次 id，按天改班（覆盖表）立刻指飞，而且**不报错**。
3. **改动「今天归哪套」的任何入口，必须同时重排闹钟**（`AlarmService.replanAfterScheduleChange`）：日历立刻变，而系统里旧计划排的闹钟照旧在原定时刻响。
4. **`ImageFilter.shader` 的 uniform 0 不是你的** —— 引擎覆写成「输入纹理尺寸」，而滤镜链上游（高斯模糊）会外扩纹理。任何「按容器尺寸归一化」的着色器，都得把容器尺寸另立一个 uniform。详见 `docs/decisions/glass.md`。
5. **`RemoteViews` 只 inflate 一次外层布局** —— 改 padding / 结构 / 层级之后，重推快照无效，必须重启桌面或删卡重加。详见 `docs/decisions/widget.md`。
6. **底部弹层里的输入框：给内容夹高度没用**，得按 `viewInsets.bottom` 把整块面板顶上去。
7. **扫源码的 `contains` 断言必须先把注释剥成空格**（`_stripComments`）—— 注释里出现那个词就能把假护栏喂绿，只有反向验证才发现。
8. **界面上的钟点一律 24 小时制**（`ringClockText`）；`TimeOfDay.hourOfPeriod` 会把 20:10 写成「08:10」。
9. **用例里的日期/时钟一律走 `appNow()` + `kAnchor`**，不许直接 `DateTime.now()` / `TimeOfDay.now()` —— 「静默空转」比「会红」更危险，清点必须钉住时钟前后各跑一遍。详见 `docs/decisions/date-time-in-tests.md`。
10. **扫文档/源码的正则或链接校验，必须先剥掉围栏代码块与行内代码** —— 否则「举例说明」会被当成真问题（2026-11-06 一次误报 6 条：`docs/changelog` 2 条、`docs/superpowers` 4 条，全是 `[文字](链接)` 这种被人故意写出来讲解 markdown 的写法）。工具见 `scripts/link_check.py`。
11. **同一台机器上不许同时跑两份 `flutter test`** —— 两个进程抢同一个 `app/build/test_cache/`，表现**不是报错，而是某几条用例莫名其妙地红**（2026-11-06：一份全套从 38 秒变成 10 分 4 秒、`calendar_day_cell_test.dart` 两条挂掉，单跑又全绿）。跑之前先数进程（`dart.exe` / `dartvm` / `flutter_tester` 应为 0）；**任何 `job_kill`、超时、异常中断之后都要再数一次** —— 父进程没了，它派生的 `dart.exe` / `dartaotruntime.exe` 可能还挂着缓存，`job_output` 里看不出来。**一条红的用例，先排除「当时是不是有人在并发跑」才值得去查。**
12. **清点用例条数不许用 `grep -c '^  testWidgets('`** —— 缩进是 2 格还是 4 格（`group()` 里）不一，会数出 0 或漏一半（2026-11-06 我按 2 格缩进数 `calendar_liquid_test.dart` 得到 0，实际 18）。要么用 `^ +(testWidgets|test)\(`，要么直接看 `flutter test` 尾行的 `+N`。
13. **测性能装包前先保住用户数据** —— `flutter drive` 收尾按 **manifest 包名（namespace）** 卸载，不是 `applicationId`。只改 `applicationId` 做「独立测量包」会把手机上正式安装的包连同 `/data/data` 一起卸掉（2026-11-10 真机事故，数据永久丢失）。改包名必须 `namespace` + `applicationId` 一起改或用独立工程；装前确认备份，装完立刻核对正式包还在。详见 `docs/decisions/perf-testing.md`。

## 症状索引（用户报的现象 → 该读哪一条）

> 人和 AI 都是**拿症状进来的**，不是拿模块名。先在这里定位，再进 topic 文件。

| 症状 / 用户原话 | 去哪 |
|---|---|
| 「点一下它跳一下」（勾选/取消后那一行先消失再回来） | `docs/decisions/todo.md`（乐观写） |
| 「加了就没」（一次性闹钟加完不响） | `docs/decisions/alarm.md`（`alarmDayAnchor`） |
| 「响在上班前 16 小时」/ 夜班提醒落在上班当天凌晨 | `docs/decisions/alarm.md`（三档落点） |
| 「保存之后闹钟还按旧排班响」 | `docs/decisions/alarm.md`（重排入口） |
| 「返回后状态栏图标不恢复」 | `docs/decisions/ui-rules.md`（`statusBarStyleFor`） |
| 「桌面卡片改了看不见」 | `docs/decisions/widget.md`（inflate 一次） |
| 「字被裁一半」/「2026年1…」/ 系统字号放大后截断 | `docs/decisions/ui-rules.md`（字号自管 + 降级顺序） |
| 「胶囊铺满整行」 | `docs/decisions/glass.md`（`GlassPill` + `IntrinsicWidth`） |
| 「弹窗按钮跑到左边」 | `docs/decisions/ui-rules.md`（`Align(centerRight)`） |
| 「键盘把确定挡住」 | `docs/decisions/ui-rules.md`（`viewInsets`） |
| 「最后一行的删除键被悬浮按钮压住」 | `docs/decisions/ui-rules.md`（`kNavCapsuleInset`） |
| 「浅色下黑字看不清」/「胶囊以前颜色更好看」 | `docs/decisions/ui-rules.md`（`solidAccent` / `onSolid`） |
| 「重复待办改不了 / 找不到编辑」 | `docs/decisions/todo.md`（系列编辑器） |
| 「点那个系列就崩」 | `docs/decisions/todo.md`（`live.single` → `live.last`） |
| 「拖完再点日期会抽一下」 | `docs/decisions/glass.md`（陈旧速度灌回） |
| 「一装就报 Conflicting app signatures」 | 本文「构建 / 测试 / 发布」（签名校验） |
| 「下载 APK 很慢 / github.com 打不开」 | 本文「官网与下载镜像」 |
| 「检查更新转圈很久，最后说失败」 | 本文「检查更新」+「官网与下载镜像」（三条通道、两处域名要一致） |

## 构建 / 测试 / 发布

- 本沙箱：pwsh 先 `. tools\build-env.ps1`（JAVA_HOME / ANDROID_HOME / PUB_CACHE 等指到 `toolchain/`）；
  bash 里跑测试用 `bash tools/flutter-test.sh`（它另把 `APPDATA` 指进库内，否则遥测日志写真实目录会被拒）。
  `tools/` 与 `toolchain/` 已 gitignore、**不在 GitHub 仓库内**；他人克隆后按 `BUILD.md` 自装。
- 改表后 `dart run build_runner build`。⚠️ **别再带 `--delete-conflicting-outputs`**（2.15.1 起已移除，传了会被静默忽略）。
- 验收：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿（条数认 `ci.yml` 的 `EXPECTED_TESTS`，只增不减）；
  动 UI 另跑 `flutter test tool/visual/`（条数认尾行 `+N`，别写死）。**Kotlin 侧的 API 等级由 `android-lint.yml`
  守着**（`NewApi`；本地等价 `cd app/android && ./gradlew :app:lintDebug`）—— v0.13.10 那次 HarmonyOS 冷启动闪退，
  `analyze` / `test` 全绿也照样漏了。
- 构建：`flutter build apk --release --target-platform android-arm64` →
  `app/build/app/outputs/flutter-apk/app-release.apk`（arm64 单 ABI，约 23MB，仅 64 位设备）。
  分发：复制到 `dist/倒班助手Pro-vX.Y.Z.apk`，`aapt2 dump badging` 核对 versionName / versionCode / 包名。
- **正式签名**：`app/android/keystore/release.jks` + `app/android/key.properties`（都 gitignore，**务必本地备份**）。
  缺了会**静默**回退 debug 证书，用户一装就报 `Conflicting app signatures` —— **要发的 APK 只能在主 checkout 构建**。
  `release.ps1` 有硬闸：证书 SHA-256 必须等于 `265d09b2…ce893`，对不上任何情况都不放行；工具不全默认 `throw`，
  要跳过必须显式 `-SkipSignCheck`。
- **检查更新**：三条通道依次回退 —— 官网清单（`siteBase/latest.json`）→ 仓库根 `latest.json` → GitHub API。
  官网排第一是因为它是国内快通道；API 未认证限流严重（60 次/小时/IP），不当主通道。**域名只有一处出处**：
  `UpdateChecker.siteBase`。
- **官网**：`site/` 静态页 → `scripts/build_site.py` 从 `dist/` 取 APK 组装 `_site/` → `release.ps1` 第 9 步
  `npx wrangler pages deploy` 发到 `daoban-shift.pages.dev`。**APK 不进仓库**。改版时先 build 再
  `.claude/launch.json` 的 `site` 预览、逐段截图核对。wrangler 登录态 / Pages 25 MiB 上限 /
  Cloudflare 已把新 Pages 并入 Workers 等坑见 `docs/decisions/release.md`。
- `dist/`、`*.apk`、`*.aab` 均 gitignore。

## 工作流
- **辅助信息随版本走（测试版也一样，不要等用户提醒）**：每次升版本或改 UI，同一次提交里同步 `site/index.html` 的更新日志、README 的版本与功能文案、`PRODUCT_SPEC.md` 抬头与能力、帮助页；`BUILD.md` / 规范文档不写死用例数（统一指向 `ci.yml` 的 `EXPECTED_TESTS`）。改 UI 后重跑 promo 图（至少正式版必须）。`app/test/site_copy_test.dart` 检查 site / README / SPEC 是否含当前版本号，漏了 CI 直接红。
- **正式版（末位 `Z=0`）发布前必须过一遍「仓库门面」** —— 用户提过两次，别再漏：
  1. `README.md` 的**文案**：版本号、功能清单逐条对着当前实现核（每次都会过时几处，例：0.8.0 那轮核出「月视图仍写按颜色区分」「铃声仍写只有内置与系统」「schemaVersion 还停在 6」）。
  2. `README.md` 的**配图**：`docs/images/` 里的 `hero.png` 与 `shot-*.png` 全是生成物，**改了 UI 就得重跑** `toolchain/flutter/bin/flutter test tool/promo/render_promo_test.dart` → `python scripts/make_promo_images.py`。只改文字不换图 = README 上挂的还是几个版本前的界面（0.8.0 那轮就漏了，图停在 v0.7.0）。
  3. **GitHub 仓库描述与 topics**（`gh repo edit --description … --add-topic …`）—— 建仓时是空的，正式版顺手维护。
  4. `PRODUCT_SPEC.md` 抬头版本 + 受影响的条目；`docs/changelog/` 补本版一条（正式版另补 `releases.md` 归纳）；`docs/coolapk-post.md` 里对应段落。
- 已升级为 **Superpowers 技能驱动**：新功能/改 UI → `brainstorming` 先磨需求；报 Bug → `systematic-debugging` 先根因后修复；写码 → `test-driven-development`；收尾 → `verification-before-completion` + `requesting-code-review`；多步/架构级 → `writing-plans` → `executing-plans`。
- 旧的 `/grill-me` 已被 `brainstorming` 取代，仅作轻量备胎。
- 用户偏好「全按推荐」、少磨叽；但涉及方案选型仍要给带推荐答案的方向、确认后再动手。
- 发布收尾：commit + `git tag vX.Y.Z` + `git push`（分支 + tag）之后，再跑 `scripts\release.ps1 -SkipConfirm` 把 APK 挂到 GitHub Release；发布说明先写到 `tools\gh\release-notes-vX.Y.Z.md`（脚本会自动复用），末位非 0 自动标为「预发布测试版」。
- ⚠️ **并行跑独立审查 / 开 worktree 时，`git checkout` 会把未提交改动一起冲掉**（2026-10-31 实踩：另起一路跑审查，它一 `checkout`，主工作区那批未提交的液态玻璃改动全没了）。要并行就先 `cp` 一份到 `work/notes/`，或先提交到临时分支。

## 最近改动（只留最近 3 版；完整流水见 `docs/changelog/`）

- **v0.14.4(+219) 测试版**：**闹钟渐响**（用户反馈）—— `AlarmSound.kt` 起播时按开关做 0→1 音量斜坡（100ms/档、20 秒），两条响铃链路共用一个 `Playback` 句柄，停止统一走 `Playback.stop()`（先摘计时器再 release），`VIBRATE_ONLY` 天然跳过、试听不受影响；开关在「我的 → 渐响」默认关，键 `fadeInRingtone`（原生读 `flutter.fadeInRingtone`）。**issue #13**：导出默认区间夹到今天 + `_pickTo` 补 `lastDate`（选择器本来就按 first/last 置灰）。顺带修 `AlarmRingService.onStartCommand` 重入时旧播放器没停的隐患。**底层大修**（原本停在 v0.14.3 未提交）：flutter_local_notifications 17→23、drift 2.20→2.35、AGP 9.1.1、compileSdk 37 —— v23 的 `resolvePlatformSpecificImplementation` 在无原生实现时抛 `LateInitializationError`，收进 `_androidImpl()` / `_cancelAllNotifications()`，否则全套 39 条红。单测 1449 → **1452**。
- **v0.14.2(+217) 测试版**：把 §6 剩下的五条护栏补完，**无用户可见变化**。时钟守门的扫描根扩到 `test/`+`tool/`（43 处 `DateTime.now()` 改走 `appNow()`，放行 `appNow = DateTime.now` 这条还原写法）；`glass_pill` 与 `calendar_screen._circleIcon` 重复的玻璃配方收进 `AppTokens.glassChip*`（**440 张出图逐像素相同**）；新增 `solid_accent_guard_test`（抓到 3 处装饰竖条，已具名豁免）；两个选择器补进屏单（`84`/`85`）；省电档补「中性纯色底两档逐像素相同」断言。单测 1445 → **1448**，出图 450 张。
- **v0.14.0(+215) 正式版**：v0.13 二十七个测试版收口。三样新东西 —— **统计页**（月 / 年、自绘环形图 / 构成条 / 月度工时柱、CSV 导出）、**请假 / 加班**（`shift_day_extras`、类型与备注、整天请假压闹钟）、**数据备份**（`.dshbackup` 导出 / 导入，`NEW_TASK|CLEAR_TASK` 重启不杀进程）；一条老命脉 —— **闹钟不丢**（先排后清、6 小时巡检只往前挪、启动快照 + 退出原因取证、日志整页 + 诊断包）。交付物见 `docs/changelog/v0.14.md`；本版代码侧只动了更新日志 / 帮助文案 + 备份导入的回滚顺序，单测基线 1429 → **1433**。**发布需主 checkout 构建 + 用户真机点头后才打 tag。**
> 全量：`docs/changelog/v0.13.md` 与 `v0.12.md`（另有 v0.2~v0.11 七个文件、`releases.md` 正式版归纳、`version-history.md` 版本号链）。

## 跨端规划备忘（未来，勿与当前 Android 版混谈）
- 2026-09-15 用户砍掉 iOS / 鸿蒙（成本与精力），**优先 Windows 版**；两个平台的成本门槛已澄清过，别再重开。
- 闹钟 / 通知是 Android 专属，换平台要重做：Windows 没有闹钟前台服务，`MainActivity` 的 MethodChannel
  （openAppSettings / openUrl / installApk / playRingtone / startAlarm 等）要按平台实现。
- 本仓的改动一直是纯 Dart 或 Android 清单级，**不给跨端留坑**。

## 相关文档
- `README.md`（对外介绍）、`BUILD.md`（构建指南）、`PRODUCT_SPEC.md`（产品规格）、`LICENSE`（MIT）。
- `docs/changelog/`（版本流水，按大版本）、`docs/decisions/`（逐条决策与坑，按主题）、`docs/release/vX.Y.Z/`（每次发版的酷安稿与配图）。
- `docs/standards/README.md`（规范层入口·守门矩阵）、`docs/standards/design-principles.md`（设计理念·D1–D16）、`docs/standards/dev-standards.md`（开发标准·E1–E17）。改完规范层跑 `python scripts/standards_check.py`。
