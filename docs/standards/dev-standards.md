# 开发标准 · 规范层（写给 agent）

> **应然**：写任何代码前先读本文件，一条都不能漏。环境/编码/路径/脚本那摊在全局
> `CLAUDE.md`；纪律（报技能/收尾验证）、版本与发布流程在 `AGENTS.md`。本文件只收
> 「写代码」这一层的硬规则。为什么、当时踩了什么坑，在 `docs/decisions/`（按主题）与
> `docs/changelog/`（按版本）——要查历史才去。
>
> 每条四段：**原则 → 落到哪 → 谁守门 → 反模式**。「谁守门」标 **自守** 的，机器不拦、
> 只有你在守——漂移高发点。

## 规则

### 1. 版本号 X.Y 用户定，AI 只改 Z
- **原则**：版本号 `X.Y.Z+build`，`X.Y` 只有用户能改，AI 只能改 `Z`（build 同步 +1）；`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 一致。
- **落到哪**：`app/pubspec.yaml` + `app/lib/core/app_info.dart`。
- **谁守门**：`app_info_test`（不一致直接红）。
- **反模式**：擅自升 `X.Y`；或只改一处漏另一处（v0.6.6~0.6.9 漏改四轮，「我的」页版本号错、更新弹窗再也不弹）。

### 2. 改「今天归哪套」必须重排闹钟
- **原则**：排班结构一变（换其余时间/增删段/删方案/编辑保存/日历调班），立刻 `AlarmService.replanAfterScheduleChange`（先 `advanceRecurringTodos` 再整链重排），不能只写库。
- **落到哪**：`features/alarm/alarm_service.dart` 的 `replanAfterScheduleChange`。
- **谁守门**：**自守**。
- **反模式**：只写库不重排（v0.12.1 真机：当天白班，19:30 响了「上夜班」的闹钟）。

### 3. saveSchedule 按 id 增量更新，不删光重建
- **原则**：保存排班必须增量 upsert，不删光再插——删光重建会换掉全部班次 id，按天改班（覆盖表）立刻指飞，且不报错。
- **落到哪**：排班保存路径（repository）。
- **谁守门**：**自守**。
- **反模式**：清空再批量插入。

### 4. 改 Drift 表后必须重生成
- **原则**：改了表定义或迁移，跑 `dart run build_runner build`（别带 `--delete-conflicting-outputs`，build_runner 2.15.1 起已移除、静默忽略）。
- **落到哪**：`app/lib/data/`。
- **谁守门**：**自守**。
- **反模式**：只改 `.drift.dart` 不重生成（表定义与迁移对不上）。

### 5. 日期/时钟走 appNow() + kAnchor
- **原则**：用例里的日期/时钟一律 `core/clock.dart` 的 `appNow()` + `test/support/fixed_clock.dart` 的 `kAnchor`，不直接 `DateTime.now()` / `TimeOfDay.now()`。
- **落到哪**：日历页「今天」、一切按天算的入口。
- **谁守门**：`useFixedNow()` 支撑，纪律 **自守**（「静默空转」比「会红」更危险）。
- **反模式**：直接 `DateTime.now()`——用例随真实月份漂移（2026-11-05 一次红 10 条）。

### 6. 开工先报技能；收尾过 verification-before-completion
- **原则**：动第一行代码前说「这次用 X、Y，因为……」；说「好了/全绿」前必须有本回合原始输出作证据（测试尾行、analyze 计数、curl 的 JSON）。
- **落到哪**：每轮开工/收尾（`AGENTS.md` 技能纪律）。
- **谁守门**：`scripts/verify-done.sh`（commit 前 analyze 必绿，--full 加全套测试）；「报技能」**自守**。
- **反模式**：「我记得跑过了」当证据；该用 TDD/系统化排障却没触发 skill（v0.12.8~0.12.10 三轮 skill 调用 0 次）。

### 7. 扫源码/扫文档的断言，先剥注释与代码块
- **原则**：`contains` 扫源码的护栏，先在剥掉注释/字符串/围栏代码块的副本上扫，否则注释提一句、或文档「举例说明」就喂绿；反向验证才作数。
- **落到哪**：所有 `*_guard_test.dart` / `scripts/link_check.py`。
- **谁守门**：**自守**（`link_check.py` 已剥，新写护栏要照做）。
- **反模式**：扫含注释的原文（一次误报 6 条，全是被人写出来讲解 markdown 的写法）。

### 8. 改 UI 后跑视觉工装出图
- **原则**：动了 UI/视觉/布局，跑 `flutter test tool/visual/`（当前 1284 条）出图看，不只靠单测。
- **落到哪**：`app/tool/visual/`。
- **谁守门**：**自守**。
- **反模式**：只跑单测就说「改好了」（令牌守门看不出布局/观感问题）。

### 9. 发布分支纪律 + latest.json 只同步本次通道
- **原则**：测试版只在 `beta` 做/发，`main` 只在发正式版时 `--no-ff` 合并；发完只把「本次发布那个通道」写回 main 的 `latest.json`（+`updatedAt`），别整份覆盖。
- **落到哪**：`scripts/release.ps1`（第 8b 步）。
- **谁守门**：脚本自做；发完 `curl main/latest.json` 核对 **自守**。
- **反模式**：整份覆盖 main 的清单（v0.11.0 的 stable 被 beta 旧值打回 0.10.0）；`git`/`gh` 输出用 `2>&1` 接（stderr 常规提示被包成异常）。

### 10. 不跑 dart format；不并发跑 flutter test
- **原则**：不要 `dart format`（工具链 tall style，一跑重排整文件、几百行无关 diff）；同一台机器不许同时跑两份 `flutter test`（抢 `build/test_cache/`，不是报错而是某几条莫名红）。
- **落到哪**：全仓库。
- **谁守门**：**自守**。
- **反模式**：收尾前 `dart format`「顺手格式化」；起测试前不清点 `dart.exe`/`flutter_tester` 进程（2026-11-06：全套 38s→10min、calendar_day_cell_test 挂两条，单跑全绿）。

### 11. 测试条数只增不减；EXPECTED_TESTS 同步
- **原则**：`flutter test` 当前 1242 条只增不减；改了条数同步 `.github/workflows/ci.yml` 的 `EXPECTED_TESTS`（beta 填 beta、main 填 main）。
- **落到哪**：`.github/workflows/ci.yml`。
- **谁守门**：CI 守卫。
- **反模式**：按缩进 `grep -c '^  testWidgets('` 清点条数（缩进不一，数出 0 或漏一半）——用 `^ +(testWidgets|test)\(` 或看 `flutter test` 尾行 `+N`。
