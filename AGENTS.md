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
| 排班模型 / 时段 / 覆盖 / 空白表 / 解析 | `docs/decisions/schedule.md` |
| 闹钟 / 响铃 / 原生侧 | `docs/decisions/alarm.md` |
| 待办 / 重复待办 / 归档 | `docs/decisions/todo.md` |
| 液态玻璃 / 着色器 / 共享玻璃件 | `docs/decisions/glass.md` |
| 桌面小组件 / RemoteViews | `docs/decisions/widget.md` |
| 颜色 / 布局 / 弹窗 / 触觉 / 字号 / 视觉工装 | `docs/decisions/ui-rules.md` |

## 技能纪律（2026-11-06 用户拍板；此前多次「该用没用」，靠记忆汇报）

> 触发这次立规矩的事实：v0.12.8~v0.12.10 三轮工作里，`skill` 工具调用 **0 次**，而其中至少有 4 处本该用（TDD、系统化排障、写计划、收尾前验证）。结论不是"技能不重要"，而是"没有强制动作 → 一定忘"。

**规矩一：开工先报技能。** 动第一行代码之前，先说一句「这次用 X、Y，因为……」。说不出来就是没想过 —— 那也要说「这次不需要，因为……」。**这句话是给用户看的，用户可以当场否决。**

**规矩二：收尾前强制过 `verification-before-completion`。** 说"好了/修完了/全绿"之前，必须有本回合跑出来的原始输出作证据（测试尾行、analyze 的 issues 计数、curl 回来的 JSON）。**"我记得跑过了"不算证据。**

**规矩三：新类型的活先扫一眼能力库。** 遇到没见过的工作类型，先看 `~/.dsh/skills/`（约 29 个；`implement` `to-tickets` `test-driven-development` `systematic-debugging` `verification-before-completion` `code-review` `writing-for-agents` `wait-what` `grilling` `stop-slop` 与本项目最相关），再判断要不要用 `learn` / `find-skills` 去外面搜。**搜到有用的报给用户，不擅自安装。**

**规矩四：不许用 `capability-router` 插件。** 用户 2026-11-06 明确：「这个插件已经落伍了，所以我才不启用它」—— 能力匹配靠规则一，不靠那个插件。

## 一句话
倒班助手Pro —— Flutter 本地离线排班助手，包名 `com.daoban.shiftassistantpro`。自研排班引擎，轮转规则（四班两倒等）按倒班行业通用轮转规则独立实现。设计语言：**简洁 + 液态玻璃（磨砂模糊）+ Q弹动画**。

## 版本号规则（重要，务必遵守）
- 版本号形如 `X.Y.Z+build`。**`X.Y` 由用户决定，AI 只能改最后一位 `Z`（以及 `build` 同步 +1）**。
- 每轮改动收尾：`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 同步。**这条由 `app/test/app_info_test.dart` 盯着** —— 两处不一致直接测试失败（v0.6.6~v0.6.9 曾漏改四轮，代价是「我的」页版本号显示错、升级后的更新弹窗再也不弹）。
- 更新日志在 `app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh` / `_changelogEn`：prepend 新版本、删最旧一条、保持 10 条。**正式版（末位 `Z=0`）发布时，其条目必须重写为「归纳总结版」——合并自上一个正式版以来所有测试版的更新内容；测试版条目一律原样保留，只写自己这版改了什么。**（例：v0.4.0 条目归纳 0.3.1~0.4.0 全部更新；v0.3.0 条目归纳 0.2.1~0.3.0，0.2.4 条目保留至今。）**这三条是长期规则（窗口固定 10 条、正式版归纳、测试版原样），v0.6.11 未改动。**
- 打完版本本地 `git tag vX.Y.Z`。
- **完整版本史不在本文件**：版本号链见 `docs/changelog/version-history.md`，每版改了什么见 `docs/changelog/v0.X.md`。判重时 `grep` 版本号即可，**不要通读**。

## 分支与发布（2026-09-21 用户定，从 0.9.4 起照此办）

- **测试版（末位 `Z ≠ 0`）一律在 `beta` 分支上做、提交、发布**：`git checkout beta` → 提交 → `git push origin beta` → `git tag vX.Y.Z && git push origin vX.Y.Z` → `scripts/release.ps1 -SkipConfirm`。**tag 打在 beta 的提交上没问题**（预发布本来就不占 Releases 页的 Latest）。
- **`main` 只在发正式版（`Z = 0`）时收一次合并**：`beta` → `main` 用 `--no-ff`（留一条合并记录），正式版的 tag 打在 **main** 上。
- **`latest.json` 必须留在 `main` 上**：App 的**主**更新通道读的是 `raw.githubusercontent.com/<owner>/<repo>/main/latest.json`（`update_checker.dart`），而 `release.ps1` 第 7 步是把它提交到**当前分支**的。**这一步从 2026-09-21 起由脚本自动做**（第 7b 步：当前分支不是 main 时，切到 main、取这份清单、提交、推送、再切回来；失败只告警 + 打出手动命令，不让已成功的发布变成「失败」）。**7b 步曾经必然失败，2026-09-23 已修。** v0.9.4 与 v0.9.5 两次发布两次都挂在这一行、两次都是手动补的 main。根因既不是锁文件也不是网络：脚本顶部的 `$ErrorActionPreference = 'Stop'` 下，`git checkout … 2>&1 | Out-Null` 会把 git 写在 **stderr** 上的常规提示（「Switched to branch 'main'」）包成 `NativeCommandError` **抛出来** —— git 明明成功了也照抛，所以只要分支切成功就必挂。2026-09-23 实测（PowerShell 5.1）：带 `2>&1` 必抛、不带不抛、`2>$null` 也抛。修法是那一段临时放宽成 `Continue`（成败仍看本来就逐个查的 `$LASTEXITCODE`），`finally` 里还原。**`git` / `gh` 这类原生命令的 stderr 上写的都是常规输出，别用 `2>&1` 去接** —— 第 7 步（发布验证）也中过同一条，已一并改掉（那里还多一层：`ConvertFrom-Json` 更不该吃 stderr，gh 真失败时那串错误文本会被喂进 JSON 解析，报出的是「解析失败」而不是「gh 失败」）。当时看到的两个 0 字节残留锁 `.git/AUTO_MERGE.lock` / `.git/packed-refs.lock` 是脚本中途抛异常留下的**症状**，不是病因。

  **发完仍要 curl 一次 main 上的 `latest.json` 核对版本号** —— 脚本打印的「发布成功」只覆盖 Release 上传那一步。万一这一步又失败（它只告警、不影响发布本身），手动补 —— ⚠️ **只改本次发布那个通道那一个节点（+ `updatedAt`），别整份覆盖**：
  ```bash
  git checkout main \
    && git commit -am "chore(release): 更新发布清单至 vX.Y.Z（同步 beta）" \
    && git push origin main && git checkout beta
  ```
  （手动补之前先确认没有 git.exe 在跑，并把残留的 `.git/AUTO_MERGE.lock` / `.git/packed-refs.lock` 删掉，否则会报「Another git process seems to be running」。）
  不这么做的话，App 读到的主通道清单会停在旧版本，表现是「明明有更新的测试版，却说已是最新」。**v0.9.4 起这条清单是首选通道**（以前只是 GitHub API 的兜底），所以这一步比过去更要紧。

  **⚠️ 这段（脚本里现标作第 8b 步，从前叫 7b）原先写的是 `git checkout <分支> -- latest.json` —— 把当前分支的整份清单搬到 main，那是错的，2026-10-13 已改成「切到 main 后读 main 自己那份，只写本次发布那个通道的字段」。** 根因：**正式版在 main 上发、测试版在 beta 上发**，而 beta 那份的 `stable` 永远停在它自己上次见到的旧值 —— 于是**每在 beta 发一次测试版，就把 main 上正确的 `stable` 覆盖回去一次**。v0.11.0 就是这么丢的：`8d25b78`（在 main 上）把 stable 写成 0.11.0，紧接着的 `972192f`（v0.11.1 同步 beta）整份搬过来，stable 退回 **0.10.0** 并一直卡在那里 —— Releases 页上 v0.11.0 明明标着 Latest、资产也在，只有 `latest.json` 的 stable 是错的（2026-10-13 由用户发现）。判据记牢：**Release 标得对不对看 Releases 页，`latest.json` 对不对只能 curl 那一份 —— 两者会各自独立地错。** 修完 main 与 beta 两份都补成了 stable=0.11.0。
- 历史注记：**0.9.1 / 0.9.2 / 0.9.3 三个测试版是直接在 main 上发的**（那时还没定这条规矩）；从这之后的测试版走 beta。

### main 的 CI：已随 v0.13.0 收敛（2026-11-10 复核，旧结论作废）

2026-11-06 记过「main 连续四次红、根因是比 beta 少 148 行 `ensureVisualFonts()`」。**这条已经不成立：** v0.13.0 把 beta 整体合进了 main，`app/tool/visual/visual_harness.dart` 在 main 与 beta 逐字节相同（`git diff --stat origin/main origin/beta -- app/tool/visual/visual_harness.dart` 空输出），main 最新提交 `449f2d9` 的 CI 是 success。**以后看到 main 的 CI 红，按真 bug 查，别再往这条旧结论上靠。**

- **`ci.yml` 的 `EXPECTED_TESTS` 仍然是分支相关项，不是常量**：main 与 beta 现在都是 1257（v0.13.0 合并后两边同一份代码），但 beta 下一次加用例后两边会再次分开，改一边要记得另一边。**基线只认 CI 日志里那行「用例数 N」**，推算值不能当基线（2026-11-06 按「1242 − 113」推成 1129，实测 1096）。
- **`visual.yml`（每日视觉巡场）已于 2026-11-10 恢复**（`gh workflow enable visual.yml` + 手动 dispatch 一次，run `42652960542`）：**1284 条断言全过、写出 337 张图、artifact 89.9 MB**，不是当初那种 0 张图的假绿。判绿**不能只看结论** —— `continue-on-error: true` 是设计取舍，结论永远是 success。**数图不用下载 89 MB 的 artifact**：`gh run view <id> --log | grep -aoE 'build/visual/[^ ]+\.png' | sort -u | wc -l`，出图那一步逐张打了路径。


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
core/haptics.dart            触觉词汇表：三档 `Haptics.select()/commit()/modeEnter()` + 模块级 `hapticsDisabled`（与 `liquidGlassEnabled` 同路，一处赋值全 app 生效）；挂动作不挂按压；除本文件外不许调 `HapticFeedback.*`，由 test/haptics_guard_test.dart 守门
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

> 全部 ~90 条已按主题搬进 `docs/decisions/`（7 个文件，原文一字未改）。这里只留**动手前必看**的 12 条 —— 每一条都对应一次真实事故。

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
- 本沙箱：每次 pwsh 先 `. C:\...\shiftassistant\tools\build-env.ps1`（设 JAVA_HOME/ANDROID_HOME/PUB_CACHE 等到 `toolchain/`）。注意 `tools/` 与 `toolchain/` 已 gitignore，**不在 GitHub 仓库内**；他人克隆后按 `BUILD.md` 自装 Flutter/JDK/SDK。
- 改表后：`dart run build_runner build`。⚠️ **别再带 `--delete-conflicting-outputs`** —— build_runner 2.15.1 起这个参数已被移除，传了会被静默忽略（日志里只有一句 `These options have been removed and were ignored`），删除冲突输出现在是默认行为。
- 验收标准：`flutter analyze` 0 error / 0 warning（约 4 条 info 提示可容忍）；`flutter test` 全绿（条数见 `.github/workflows/ci.yml` 的 `EXPECTED_TESTS`，只增不减、必须同步改；别在文档里另抄一个数）。⚠️ **日历页的「今天」走 `core/clock.dart` 的 `appNow()`**（不要直接写 `DateTime.now()`）：用例用 `test/support/fixed_clock.dart` 的 `useFixedNow()` 把它钉在 2026-10-15，**期望值也一律用 `appNow()` 算** —— 否则用例会随真实月份漂移（2026-11-05 一次红了 10 条）。视觉工装另算：`flutter test tool/visual/`（数量随屏单增长，认尾行 `+N`，别写死）。
- 构建：`flutter build apk --release --target-platform android-arm64` → `app/build/app/outputs/flutter-apk/app-release.apk`（**切 arm64 单 ABI**，APK 从 ~60MB 降到 ~21MB；仅 64 位设备）。
- 分发：复制到 `dist/倒班助手Pro-vX.Y.Z.apk`，用 `aapt2 dump badging` 校验 versionName/versionCode 与包名。
- 一键发布（GitHub Releases）：`scripts/release.ps1`。
- **正式签名**：release 用独立 keystore `app/android/keystore/release.jks`，口令在 `app/android/key.properties`（storeFile/storePassword/keyAlias/keyPassword），二者均 gitignore 不入库、**务必本地备份**（丢了无法再发可覆盖升级的包）。`key.properties` 缺失时 `build.gradle.kts` 自动回退 debug 证书便于本机调试。
  ⚠️ **那条「自动回退」的代价是「静默」—— 2026-10-13 真踩过一次。** v0.11.16 的 APK 是在一个 **git worktree** 里构建的，而 worktree 是一次干净 checkout、**既没有 key.properties 也没有 release.jks**（两者都 gitignore），于是它被 **debug 证书**签了名。包照常发了出去，版本号 / 资产 / `latest.json` / 清单**全对**，用户一装就报 `Couldn't install (-7)` — **Conflicting app signatures**，只能卸载重装。**一句话：要发的 APK 只能在主 checkout 里构建**（`dist/`、`tools/`、`toolchain/` 也都只在那儿）。
  现在 `release.ps1` 的一致性校验里多一条**签名校验**：① `app/android/key.properties` 必须存在；② 用 `apksigner verify --print-certs` 取 APK 的证书 SHA-256，与 `keytool -list -v -keystore release.jks` 那一枚**逐位比**（不拿 DN 比 —— DN 是人填的、可以重名；实测 release 那枚是 `265d09b2…ce893`）。⚠️ **2026-11-05 起默认硬拦（v0.12.10）**：工具不全 / 吐不出摘要 → 默认 `throw`，要跳过必须显式 `-SkipSignCheck`；摘要对不上**任何情况都不放行**（无口子）。这一节还搬出了 `if (-not $SkipVerify)` —— 以前加 `-SkipVerify` 会把签名校验整段静默关掉。**别再把这条当「保险」**：v0.12.9 那次 418B 占位稿就是被「只是保险、不必需」的旧说法放过去的。**两条路径都验过**：拿 worktree 里那份 debug 签名的 APK 当反例，脚本退出码 1 并把两枚摘要一起打出来。
- **检查更新（公开仓库）**：`UpdateChecker` 无鉴权，三条通道依次回退：**官网清单**（`siteBase/latest.json`）→ 仓库根目录 `latest.json` → GitHub API `/releases`。官网排第一是因为它才是国内用户的快通道，以前 GitHub 那条先试，国内往往要等满 8 秒超时才回退。**API 不当主通道**：未认证限 60 次/小时/IP，共享出口很容易耗尽（实测常年 403），拿它优先等于大部分时间都在走回退。两条**在不同域名**上，只被墙了一个的网络也兜得住。按语义版本自行计算「最新正式版 + 最新测试版」双通道展示；`downloadApk` 直接经 `browser_download_url` 下载安装。连不上时的提示直说「国内需要开代理或加速器」（`showUpdateFailedDialog`，走弹窗不走 2 秒的 snack）。
- **官网与下载镜像（2026-11-10 用户选 A 档）**：`site/` 是一页静态官网，和 APK 放在同一个域上 —— `https://daoban-shift.pages.dev`（Cloudflare Pages，项目名 `daoban-shift`）。**APK 不进仓库**（`dist/` 本来就 gitignore），部署时由 `scripts/build_site.py` 从 `dist/` 取一份放进 `_site/download/`。
  - **部署走本机，不走 CI**：`scripts/release.ps1` 第 9 步跑 `build_site.py --base <siteBase> --channel <stable|prerelease>` + `npx wrangler pages deploy _site`。凭据是 `npx wrangler login` 一次之后的 OAuth token（存在 `%APPDATA%\xdg.config\.wrangler\config\default.toml`），**不需要 GitHub secrets**。换机器发版要重新 login。
  - ⚠️ **`build-env.ps1` 把 `APPDATA` 重定向到 `toolchain\`，而 wrangler 的登录态在真实的 `%APPDATA%\xdg.config\.wrangler`**。不指回去就报 "In a non-interactive environment, it's necessary to set a CLOUDFLARE_API_TOKEN" 直接失败 —— 2026-11-10 发 v0.13.1 时踩到：发布本身成功，站点没更新。`release.ps1` 第 9 步现在临时把 `APPDATA` 指回真实目录，与 gh 的 `GH_CONFIG_DIR` 是同一类修法。
  - **两个通道的 APK 都要镜像**：清单里点到名的版本，`dist/` 有就都放进 `_site/download/`（正式版 + 测试版，约 46MB）。只带正式版是不够的 —— 发测试版时 `prerelease` 那条会因为没有文件而退回 GitHub，国内用户又得开代理，正是这套东西要解决的问题。`--channel` 决定哪一端以工作区刚写好的清单为准，另一端取 `origin/main` 的权威值。落盘用清单里的 `asset` 名（ASCII），不是 `dist/` 里的中文文件名。
  - **域名只有一处出处**：`UpdateChecker.siteBase`。`release.ps1` 用正则从那个文件读，`build_site.py --base` 负责把清单里的相对地址拼成绝对地址。改域名 = 改这一个常量 + 在 Pages 里绑好新域名。
  - **页面是纯静态 HTML/CSS**，不引任何框架、外部字体或 CDN（国内打开要快，也不给别人当依赖）。深色 / 浅色两套跟随系统，**只换 `:root` 里的语义变量，版式、字号、间距一个不动**；新加颜色必须走变量，写死 `rgba()` 就会在另一套主题里露馅。动效只有一个 `IntersectionObserver` 做一次性入场 + 首屏三台机器的轻微视差，两者都尊重 `prefers-reduced-motion`。改版时先 `python scripts/build_site.py` 再 `.claude/launch.json` 里的 `site` 预览，逐段截图核对。**`build_site.py` 的 `PNGS` / `SHOTS` 列表必须与 `index.html` 同步** —— 少一张图就是线上裂图，多一张就是白传。
  - ⚠️ **Cloudflare 2026 年已把新建 Pages 项目并进 Workers**：`npx wrangler pages project create` 现在建出来的是 **Worker**（域名 `*.workers.dev`），`wrangler pages deploy` 会报 "project does not exist"。本项目那个经典 Pages 项目是用 API 建的（`POST /accounts/<id>/pages/projects`）。**别用 `pages project create` 重建**，会又得到一个 Worker。
  - ⚠️ **Pages 单文件上限 25 MiB，当前 APK 22.05 MiB** —— 再涨约 3 MiB 就超。`build_site.py` 里有 `25 * 1024 * 1024` 的硬闸，超了直接退出并提示改放 Cloudflare R2（免费 10GB 存储 + 零出口费）。
  - 免备案的代价是走国际线路：比 GitHub 快得多，但不是国内 CDN 那种秒开。要秒开只能备案 + 国内 CDN（B 档，约 ¥200/年，审批 2~3 周）。
- `dist/`、`*.apk`、`*.aab` 均 gitignore，不进仓库。

## 工作流
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

- **v0.13.2(+189) 测试版**：新增「关于」整页（作者 / 版本 / 官网 / 开源仓库 / Issues / 隐私）与「支持」打赏（支付宝一键、微信扫码；5 / 10 / 20 元或自定义）；文案审校去掉「国内需开代理」「连不上 GitHub」等已过时的更新检查说明；屏单加 `68_about` / `69_donate` / `70_profile_about_cards` / `71_donate_qr`。
- **v0.13.1(+188) 测试版**：官网与国内下载镜像上线（`https://daoban-shift.pages.dev`，正式版 / 测试版两个 APK 都在站上）；「检查更新」改三通道（官网清单 → 仓库清单 → GitHub API），国内不再先卡满 8 秒超时；官网标明仅支持 Android；发版脚本第 9 步自动同步站点。
- **v0.13.0(+187) 正式稳定版**：小组件跟随系统深浅色（API 31+ `setColorInt` + `drawable-night`，宿主重新应用；API < 31 烤死）；重复待办行挂发生日 + 旧数据一次性迁移（行与水位线）+ 打勾不再响 + 冷启动重排 + 解绑保时刻；排班管理 / 编辑排班的箭头去掉；README / 配图 / 四张 GIF 重出。
> 全量：`docs/changelog/v0.13.md` 与 `v0.12.md`（另有 v0.2~v0.11 七个文件、`releases.md` 正式版归纳、`version-history.md` 版本号链）。

## 跨端规划备忘（未来，勿与当前 Android 版混谈）
- 目标：Windows / iOS / 鸿蒙 多端。Flutter 本身跨端，但**闹钟/通知是 Android 专属**，跨端需按平台重做：
  - **iOS**：flutter_local_notifications 可用；无前台服务/全屏 intent，锁屏响铃体验弱（Critical Alert 能力受限）；无精确闹钟。
  - **Windows**：flutter_local_notifications 通知支持有限，无闹钟前台服务；`MainActivity` 的 MethodChannel（openAppSettings/openUrl/installApk/playRingtone/startAlarm 等）需按 Windows 实现。
  - **鸿蒙**：HarmonyOS NEXT（纯鸿蒙）需用 OpenHarmony 的 Flutter 分支（flutter_ohos）重建；`flutter_local_notifications` / `drift`(sqlite3) / `path_provider` / MethodChannel / FileProvider 都要找 OHOS 对应物或重写。
- 本轮（v0.4.1）改动全部是纯 Dart 或 Android 清单级，**不给跨端留坑**。启动跨端时单独 `/grill-me` 一轮评估。

## 相关文档
- `README.md`（对外介绍）、`BUILD.md`（构建指南）、`PRODUCT_SPEC.md`（产品规格）、`LICENSE`（MIT）。
- `docs/changelog/`（版本流水，按大版本）、`docs/decisions/`（逐条决策与坑，按主题）、`docs/release/vX.Y.Z/`（每次发版的酷安稿与配图）。
- `docs/standards/README.md`（规范层入口·守门矩阵）、`docs/standards/design-principles.md`（设计理念·D1–D16）、`docs/standards/dev-standards.md`（开发标准·E1–E17）。改完规范层跑 `python scripts/standards_check.py`。
