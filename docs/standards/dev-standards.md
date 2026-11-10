# 开发标准 · 规范层（E1–E17）

> **应然**：写任何代码前先读本文件，一条都不能漏。环境/编码/路径/脚本那摊在全局
> `CLAUDE.md`；纪律（报技能/收尾验证）、版本与发布流程在 `AGENTS.md`。本文件只收
> 「写代码」这一层的硬规则。为什么、当时踩了什么坑，在 `docs/decisions/`（按主题）与
> `docs/changelog/`（按版本）——要查历史才去。
>
> 每条五段：**原则 → 落到哪 → 谁守门 → 例外与豁免 → 反模式**。强度口径见 `README.md` §2、§4；
> 矩阵里标 **自守** 的条目只有你在守——漂移高发点。

## 规则

### E1. 版本号 X.Y 用户定，AI 只改 Z（build 同步 +1）
- **原则**：版本号 `X.Y.Z+build`，`X.Y` 只有用户能改，AI 只能改 `Z`（`build` 同步 +1）；
  `app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须一致。
- **落到哪**：`app/pubspec.yaml:4`（唯一来源）+ `app/lib/core/app_info.dart:10`。
- **谁守门**：`app/test/app_info_test.dart`——**半机器**：`pubspec` 用
  `^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$` 抓两个数，但只比 `group(1)`，
  `+build` 仅断言 `greaterThan(0)`，所以 `+185` 写错也没有测试红（`app_info.dart` 里没有 build 常量可比）。
- **例外与豁免**：`build` 单向流向 `app/android/app/build.gradle.kts:38-39`；`X.Y` 的改动只发生在发版那一次，
  由用户拍板，AI 不许"顺手对齐"。
- **反模式**：擅自升 `X.Y`；或只改一处漏另一处（v0.6.6~0.6.9 漏改四轮，「我的」页版本号错、更新弹窗再也不弹）。

### E2. 改「今天归哪套」必须重排闹钟
- **原则**：排班结构一变（换其余时间 / 增删段 / 删方案 / 编辑保存 / 日历调班），立刻
  `AlarmService.replanAfterScheduleChange`（内部先 `advanceRecurringTodos` 再整链 `rescheduleAll`），
  不能只写库。
- **落到哪**：`features/alarm/alarm_service.dart:1166`（`replanAfterScheduleChange`）→
  `:1167 advanceRecurringTodos(today: dateOnly(appNow()))` + `:1168 rescheduleAll()`。
  现存调用点：`calendar_screen.dart:1223`、`schedule_editor_screen.dart:2340`、
  `schedule_management_screen.dart:237`（wrapper，上游 `:219` 删方案、`:367` 换方案、`:386` 换其余时间、
  `:494` 删段、`:535` 增改段）。
- **谁守门**：**自守**（`day_override_repository_test.dart:47-53` 只间接守着"调班后会重算"这一条链路）。
- **例外与豁免**：新建方案时 `schedule_management_screen.dart:190` 自己不重排，靠随后的编辑器 `:2340` 兜住——
  这条隐性依赖就是例外本身：**新入口必须在写完库后自己调一次**，别指望下游编辑器。
- **反模式**：只写库不重排（v0.12.1 真机：当天白班，19:30 响了「上夜班」的闹钟）。

### E3. saveSchedule 按 id 增量更新，不删光重建
- **原则**：保存排班必须**按 id 增量 upsert**，不删光再插——删光重建会换掉全部班次 id，
  按天改班（覆盖表）立刻指飞，且不报错。
- **落到哪**：`data/app_repository.dart`——`:689-700`（`update(shiftScheduleRows)..where(id.equals)`）、
  `:733-747`（`if (c.id != null)` 则 update，否则 `:749` insert）、`:786-793` 清悬空行。
- **谁守门**：**自守**。
- **例外与豁免**：**周期/段表整组删了重建**（`:713-718`）与**闹钟整组重写**（`:769-781`）是允许的：
  这两类 id 不被任何外部表持有，重建不会指飞。允许的边界只有这两处，别把班次也归进"整组重建"。
- **反模式**：清空再批量插入（覆盖表、待办引用、小组件快照会一起指飞）。

### E4. 改 Drift 表后必须重生成
- **原则**：改了表定义或迁移，跑 `dart run build_runner build`；**别带 `--delete-conflicting-outputs`**
  （build_runner 2.15.1 起已移除该参数、静默忽略，带上会让人以为"删过冲突"了）。
- **落到哪**：`app/lib/data/`（生成物 `app_database.g.dart` 入库，跟源码一起提交）。
- **谁守门**：**半机器**：`ci.yml:67-69` 明写禁止旧参数，脚本侧 0 处残留；但"改了表没重生成"只能靠
  编译或迁移用例暴露，没有专门护栏。
- **例外与豁免**：`app/pubspec.yaml` 约束 `^2.4.13`，锁文件实解析 **2.15.1**；`docs/superpowers/plans|specs`
  里的 20 处旧命令（11 份 plan）是**历史档案，不改**（改了就是伪造当时的记录）。
- **反模式**：只改 `.drift.dart` 不重生成（表定义与迁移对不上）。

### E5. 日期/时钟走 appNow() + kAnchor
- **原则**：一切"现在几点/今天几号"走 `core/clock.dart` 的 `appNow()`；用例里再叠
  `test/support/fixed_clock.dart` 的 `kAnchor`（`2026-10-15`），不直接 `DateTime.now()` / `TimeOfDay.now()`。
- **落到哪**：`core/clock.dart:24`（`appNow`，lib 内 45 次 / 14 文件）+
  `test/support/fixed_clock.dart:29`（`kAnchor`）。
- **谁守门**：`clock_guard_test`（`:63` lib 除 `clock.dart` 无 `DateTime.now`、`:72` 剥壳自证、`:82` 接缝仍在）+
  `time_of_day_guard_test`（`:63`/`:74`/`:84`）——**半机器：两个都只扫 `lib/`**。
- **例外与豁免**：`features/alarm/alarm_ringing_screen.dart:196` 的 `TimeOfDay.now()` 是刻意豁免
  （响铃页时钟必须真实时间，`time_of_day_guard_test` 守）；`lib` 里 `DateTime.now` 的 4 处全是注释。
- **反模式**：直接 `DateTime.now()`——用例随真实月份漂移（2026-11-05 一次红 10 条）。
  **现状风险**：扫描网外实测 `app/test` **22 处 / 10 文件**、`app/tool/visual` **21 处 / 5 文件**真实时钟
（复核：`work/verify_numbers.py`；见 `README.md` §6 待办 1）。

### E6. 开工先报技能；收尾过 verification-before-completion
- **原则**：动第一行代码前说「这次用 X、Y，因为……」；说「好了/全绿」前必须有**本回合原始输出**作证据
  （测试尾行 `+N`、analyze 的 issues 计数、`curl` 回来的 JSON）。
- **落到哪**：每轮开工/收尾（`AGENTS.md` 技能纪律）；`scripts/verify-done.sh`（commit 前 analyze 必绿，
  `--full` 加全套测试）。
- **谁守门**：`scripts/verify-done.sh` 由 `.claude/settings.json` 的 PreToolUse 钩子挂在 `git commit*` 上——**半机器**：
  钩子过滤键写成 `"if": "Bash(git commit*)"`，这不在 hooks handler 的公开 schema 内（只有
  `type`/`command`/`timeout`），**是否真按命令过滤尚未实机验证**；被忽略的话每次 Bash 都会跑一次 `--full`。
  「报技能」**自守**。
- **例外与豁免**：`gates-template/verify-done.sh` 是**参数化模板**（`ANALYZE_CMD`/`TEST_CMD`/`WORKDIR`/
  `CODE_DIRS`/`DOC_DIRS`），`scripts/verify-done.sh` 是**硬编码实装**（`toolchain/PUB_CACHE/TMP/遥测`）——
  两者分化是**有意设计**（`gates-template/README.md:4,21-23,35-36`），不是漂移，别去"对齐"它。
  **陷阱**：`gates-template/install.sh:16` 会无条件 `cp`，在别的项目里跑会覆盖实装版。
- **反模式**：「我记得跑过了」当证据；该用 TDD/系统化排障却没触发 skill（v0.12.8~0.12.10 三轮 skill 调用 0 次）。

### E7. 扫源码/扫文档的断言，先剥注释与代码块
- **原则**：所有 `contains` 式护栏，必须先在剥掉注释/字符串/围栏代码块的副本上扫，否则注释里提一句、
  或文档"举例说明"就喂绿。**剥壳本身要被自证**：剥过头会恒绿，所以护栏要带一条"接缝仍在"的断言
  和一条"扫到的文件数 > 下限"的兜底。
- **落到哪**：`test/support/source_scan.dart:38` 的 `blankNonCode()`（21 个测试在用）+
  `scripts/link_check.py`（已剥围栏代码块）。
- **谁守门**：模板即护栏——新写护栏照抄三条式（扫 → 剥 → 自证）；`clock_guard_test.dart:72/:78-79` 是范本
  （"剥壳过头会恒绿" + `scanned > 50` 兜底）。
- **例外与豁免**：扫生成物、扫二进制、扫 `docs/` 的表格不算在内（没有"举例"歧义）。
- **反模式**：扫含注释的原文（一次误报 6 条，全是被人写出来讲解 markdown 的写法）。

### E8. 改 UI 后跑视觉工装出图
- **原则**：动了 UI/视觉/布局，跑 `flutter test tool/visual/` 出图看，不只靠单测。
- **落到哪**：`app/tool/visual/`（`render_screens_test.dart` 是"屏单 × 变体"矩阵，`visual_harness.dart` 是工装本体）。
- **谁守门**：**自守**（`.github/workflows/visual.yml` 只有定时任务 + `workflow_dispatch`，
  `continue-on-error: true`，不进 PR 门禁）。
- **例外与豁免**：**条数不许写进文档**。矩阵是"49 条屏单 × 若干变体"，`testWidgets` 只有 5 个、展开后上千条；
  要数字就认尾行 `+N`。（历史教训：文档写"当前 1284 条"，一次加屏就过期。）
- **反模式**：只跑单测就说「改好了」（令牌守门看不出布局/观感问题）。

### E9. 发布分支纪律 + latest.json 只同步本次通道
- **原则**：测试版只在 `beta` 做/发，`main` 只在发正式版时 `--no-ff` 合并；发完只把「本次发布那个通道」
  写回 main 的 `latest.json`（+`updatedAt`），**别整份覆盖**。
- **落到哪**：`scripts/release.ps1`——第 8 步 `:394-429`、**第 8b 步 `:431`**（latest.json）、
  通道判定 `:448`、`Add-Member -Force` `:487`（另一通道原样保留，`:438-444` 记着 v0.11.0 事故）。
- **谁守门**：脚本自做（签名是硬拦：`:188`、`:204-211`、`:237-243`、`:248` 全部 `throw`，只有 `-SkipSignCheck`
  放行；`:172-176` 已把签名段移出 `-SkipVerify` 之外）；发完 `curl main/latest.json` 核对 **自守**。
- **例外与豁免**：`2>&1` 只在 `git`/`gh` 的**结果判定**处禁用；`release.ps1` 里 `:465/:475/:477/:513` 的 `2>&1`
  是有意例外（`:462-463` 用 `Continue` + 查 `$LASTEXITCODE`）。步骤号 `[4/6]`(`:172`) 与 `[8/8]`(`:419`) 自相矛盾，
  是待修的文案漂移，不影响流程。
- **反模式**：整份覆盖 main 的清单（v0.11.0 的 stable 被 beta 旧值打回 0.10.0）。

### E10. 不跑 dart format；不并发跑 flutter test
- **原则**：不要 `dart format`（工具链 tall style，一跑重排整文件、几百行无关 diff）；
  同一台机器不许同时跑两份 `flutter test`（抢 `build/test_cache/`，不是报错而是某几条莫名红）。
- **落到哪**：全仓库（无 `.editorconfig`、`analysis_options.yaml` 无 `formatter` 段、CI 0 处 format 检查）。
- **谁守门**：**自守**。`tools/flutter-test.sh:14-23` 只设 `PATH`/`PUB_CACHE`/`TMP`，**没有锁**。
- **例外与豁免**：手工对齐单行的缩进可以；`app/lib/features/calendar/schedule_management_screen.dart:383-384`
  与 `:532-533` 就是"两种缩进被有意保留"的证据（没跑过格式化）。
- **反模式**：收尾前 `dart format`「顺手格式化」；起测试前不清点 `dart.exe`/`flutter_tester` 进程
  （2026-11-06：全套 38s→10min、calendar_day_cell_test 挂两条，单跑全绿）。

### E11. 测试条数只增不减；EXPECTED_TESTS 同步
- **原则**：`flutter test`（即 `app/test/`）条数只增不减；改了条数同步 `.github/workflows/ci.yml` 的
  `EXPECTED_TESTS`（beta 填 beta 的值、main 填 main 的值）。
- **落到哪**：`.github/workflows/ci.yml` 的 `EXPECTED_TESTS`（beta / main 各有一个值，随分支变化；改一边记得另一边）。
- **谁守门**：CI 守卫——统计法 `:133-147`：`set -o pipefail` → `flutter test --reporter expanded 2>&1 | tee` →
  取 `^[0-9]{2}:[0-9]{2} \+[0-9]+` 的最后一条 → 严格相等比较——**机器拦**。
- **例外与豁免**：删测试必须同时下调 `EXPECTED_TESTS` 并在提交信息里写为什么删（"只增不减"是默认，不是铁律）。
- **反模式**：按缩进 `grep -c '^  testWidgets('` 清点条数（缩进不一，数出 0 或漏一半）——看尾行 `+N`。

### E12. 用户可见文案一律走 L10n
- **原则**：用户能看到的每一句中文/英文都必须走 `core/l10n.dart`：单个短串用 `t('…')`，
  成对数据用 `L10nText('中文','English')`（双语数据表）。**禁止**：可达 UI 里的裸中文字面量、
  以及内联 `L10n.isEn ? '…' : '…'` 三元（加第三种语言时必失守）。
- **落到哪**：三条路**不许混**：①整句话 → `L10nText('中文','English')` 表（`domain/shift_templates.dart`、
  `features/profile/help_content.dart`）②要拼装/带参数的句子 → `core/l10n.dart` 的 `static String fn`
  （如 `shift_rotation.dart:598-632` 的 9 处拼接）③单个短串 → `t('…')`（307 个 getter + 62 个 fn，
  `lib` 内 353 处 `t('` 调用）。
  语言只有 **zh/en 两种**（`l10n.dart:24-27`）；英文缺译文**有意不回退中文**（`:11-16`）。
- **谁守门**：**自守**（12 个 `*guard_test.dart` 无一扫文案；`source_scan.dart` 的 `blankNonCode()` 现成，
  接一条文案守门是顺手事——见 `README.md` §6 待办 2）。
- **例外与豁免**（当前 278 处中文字面量 / 19 文件，绝大多数是这三类，**不算违规**）：
  ①日志（`appendLog`/`logInfo`，如 `alarm_service.dart:358`）；②量具（量行高/宽用的占位串，
  如 `calendar_screen.dart:59`、`info_card_metrics.dart`）；③双语数据表本身（`L10nText`）。
  **真漏（2026-11-08 复核后只剩 1 处）**：`app.dart:31` 的品牌名。旧清单里的 `calendar_screen.dart:1928/:2938`、
  `widget_service.dart:119/:149`、`lunar_info.dart:9-19` 已被种子用例收敛，**别再按旧清单排活**；
  复核用 `work/audit/scan_literals.py`（复刻守门的剥注释判据）。
- **反模式**：写「先这样，回头统一国际化」——回头就是永远（现状 278 处、零护栏）。

### E13. await 之后还要碰 context/setState 才检 mounted；静默降级必须写明理由
- **原则（mounted）**：`await` 之后**还要用** `setState` / `context` / `ScaffoldMessenger`，先
  `if (!mounted) return;`（`State` 内）或 `if (!context.mounted) return;`（拿 `context` 时）；弹层的
  builder 闭包同样算（弹层可以在写库/选时间的窗口里被手势关掉）。**没有后续 context 依赖的 `await` 不必检**
  —— 全库 `mounted` 33 处 vs `await` 496 处，逐 await 加会全线误报。
- **原则（异常）**：插件/HTTP/原生回调这类**副作用调用允许静默降级**：抓住 → 返安全默认值 → 写原生日志，
  **不 rethrow、不弹窗**。但 `catch` 里必须写清"为什么静默"——实测 `lib` 内 `catch (_)` **52 处**、
  其中 **33 处是空块**、`rethrow` **0** 处；新代码要求带注释（复核脚本：`work/verify_numbers.py`）。
- **落到哪**：正例 `profile_screen.dart:750/:812/:891`、`schedule_management_screen.dart:182/192`；
  反例 `alarm_screen.dart:421-424`（`await showGlassTimePicker` 后直接 `setState`）、`schedule_screen.dart:590-596`、`:930-938`；
  静默降级范本 `features/alarm/alarm_service.dart`（实测 24 处空 catch，原生侧在部分机型必抛，噪音日志会淹没真故障）。
- **谁守门**：**自守**（无护栏；`unawaited(` 全库仅 `core/haptics.dart:52` 一处，说明"有意不等待"本就少见）。
- **反模式**：`catch (_) {}` 一把梭而不写理由（读代码的人分不清"刻意降级"与"漏了"）；
  或反过来给 496 个 `await` 全加 `if (!mounted)`，把守则变成噪声。

### E14. 单文件 ≤800 行（非生成物），超了先拆
- **原则**：一个 `.dart` 文件超过 **800 行**就说明它至少有 3 件事；要么当次拆，要么在下面的台账里登记
  "为什么先不拆 + 拆法"。**台账只减不增**：新增超限文件必须在同一个提交里说明理由，否则评审驳回。
- **落到哪**：`app/lib`（生成物 `data/app_database.g.dart` 不受限，它跟表定义走）。
- **谁守门**：**自守**（没有行数护栏；`wc -l` 一眼可见，评审时点名）。
- **例外与豁免（既存台账，2026-11-08 实测 **8 件**，只减不增）**：
  | 文件 | 行数 | 已知拆法 |
  |---|---|---|
  | `features/calendar/calendar_screen.dart` | 3196 | ①`_infoCard`（`:2398-2930`，单方法 532 行）抽 `info_card_view.dart` ②`_syncBlockFlight/_onFlightTick/_stopFlight`（`:670-760`）抽 `block_flight.dart` ③网格/日格抽 `calendar_grid.dart` |
  | `features/calendar/schedule_editor_screen.dart` | 2532 | 按卡拆：`_classesCard` / `_cycleCard`+`_monthlyBody` / `_crewCard`+`_followHolidayCard`，控制器留壳 |
  | `data/app_repository.dart` | 1468 | 按聚合拆（schedule / todo / alarm / override） |
  | `core/glass/liquid_lens.dart` | 1390 | 已按绘制/物理分层，暂不动 |
  | `features/alarm/alarm_service.dart` | 1200 | 调度决策与原生通道分家 |
  | `core/l10n.dart` | 1147 | 纯静态表：按族拆文件（`l10n_perm.dart` / `l10n_widget.dart` / `l10n_help.dart`），零风险 |
  | `features/profile/profile_screen.dart` | 1096 | 许可证/帮助页外链内容抽 `*_content.dart` |
  | `features/schedule/schedule_screen.dart` | 986 | 编辑器与列表分离 |
- **反模式**：往已经 3000 行的文件里再塞一个特性（`calendar_screen.dart` 已有两条 banner 在往里加）。

> `core/design_tokens.dart` 757 行（非空 683）**未超线**，故不在台账里；但 `:431-669` 那 238 行是底栏胶囊边光的
> **绘制配方**（`capsuleEdgeRim/Shadow/Warm/Cool`），本该住在 `core/glass/` —— 不算违规，算 D1 的落点债。

### E15. 注释写"为什么"；文件头写全路径；不拿 TODO 记账
- **原则**：注释一律**中文**，写"为什么这么做、踩过什么坑、这里的契约是什么"，不写"这行在做什么"。
  文件头第一行写**完整相对路径**（`// app/lib/core/clock.dart`），让 grep 与 patch 都对得上。
  **这条按目录分级**：`app/test`（130/158）与 `app/tool`（11/11）是硬要求；`app/lib` 只有 14/89 有，
  新写的 lib 文件要求带、存量不追。
  **不许裸写计数**：注释里的"全 app N 处"要么改成"见 `xxx_test` 的名单"，要么由测试断言（反例见 D17）。
  **不用 `TODO/FIXME` 记账**——本仓库欠账由散文注释 + `docs/decisions/` 承载（实测 lib/test 里
  `TODO|FIXME|HACK|XXX` 共 **0** 处，保持它）。
- **落到哪**：`core/clock.dart:1-19`（病历式文件头范本）、`test/time_of_day_guard_test.dart:6-17`、
  `calendar_screen.dart:48-56`（"量行高必须 merge 环境样式，否则矮 7dp，v0.11.12 栽过"）。
- **谁守门**：**自守**。
- **例外与豁免**：只给测试用的钩子放文件尾并注释说明（现存 `schedule_editor_screen.dart:2447/2452/2458`
  的 `cycleChipKey`/`monthRowDayKey`/`monthRowDeleteKey`、`l10n.dart:43/:46` 的 `debugDateFormatCache*`）；
  新增这类符号优先用 `@visibleForTesting`。
- **反模式**：写 `// TODO: 优化`（这个仓库不认，谁写的谁修）；英文段落式注释（全库仅 39 行无中文注释，
  基本都是路径头与 `// ignore:` 指令）。

### E16. 测试按"一文件一行为"分工，护栏用三条式模板
- **原则**：测某个 lib 文件的行为，文件名用 `stem_test.dart`（与 lib 同名）；测**跨文件契约**
  （护栏、视觉矩阵、可访问性）用行为命名（`*_guard_test` / `no_bare_text_button_test` / `text_fit_guard_test`）。
  新用例优先前者。护栏测试一律三条式：**扫 → 剥 → 自证**（见 E7）。
- **落到哪**：`app/test/`（158 文件平铺；153 个用例文件里 46 个与 lib 同 stem（30%）、**107 个按行为命名（70%）**
  —— 所以这是**分工**，不是强制：测单个文件的内部行为用 `stem_test`，测跨文件契约用行为名）+
  `test/support/` 五个 helper：
  `calendar_test_support.dart`（15 个测试用，`templateOf`/`pinNow`/`chipPattern`）、
  `source_scan.dart`（21 个）、`fixed_clock.dart`（28 个）、`plugin_channels.dart`（5 个，挂空 MethodChannel）、
  `cjk.dart`（4 个）。
- **谁守门**：**自守**。配套约定：护栏测试文件名含 `_guard`（现存 12 个，其中 10 个带"剥壳自证"断言，
  缺自证的是 `recurring_native_guard_test` 与 `widget_fixed_cards_guard_test`）。
- **例外与豁免**：既能当"一文件一行为"又能当契约的，归契约命名；`support/` 里只放**被 3 个以上测试**
  复用的东西（一次性 helper 留在用例文件内）。测试启动样板（`ProviderScope` + `SharedPreferences.setMockInitialValues`）
  目前 22 个文件各写一遍——新写的请先看有没有现成的 `_pumpApp`/`_pumpCalendar`，别再造第四份。
- **反模式**：`skip:` 挂红（实测 0 处，保持）；`// ignore: avoid_print` 越摊越多（现存 10 处全在
  会打印诊断的探针/护栏里，是例外不是许可）。

### E17. 仓库卫生：worktree 与派生产物不进仓库
- **原则**：临时工作树开在**仓库外**（`..\_wt-*`），用完 `git worktree remove`；`build/`、
  `visual-baseline-*`、抓图输出等派生产物不留在工作树里。单文件 > 300 KB 入库必须在
  `docs/decisions/evidence/` 里写清用途（照 `2026-11-06-date-audit` 的表格格式）。
- **落到哪**：`.gitignore` + `git worktree list`（开工清点时顺手看一眼）。
- **谁守门**：**自守**（`.gitignore` 不排除 `.claude/worktrees/`；本机只靠 `.git/info/exclude:7` 遮着，**该文件不入库** ——
  别人 clone 下来立刻就看见那 764 MB，而你能看见的 `git status` 永远是干净的）。
  **`git worktree prune` 不回收**：目录还在就不会被 prune（`--dry-run` 无输出即证明），只能用 `git worktree remove`。
- **例外与豁免**：**同时存在 ≤3 个** worktree，且不许建在仓库目录内（`..\_wt-*`）；只有在主 checkout 里能出发布包
  （worktree 里的构建会被 debug 证书签名，见 `AGENTS.md`）；证据目录允许留原始日志，但单文件 ≤300 KB、超了只搬关键行。
- **入库大件白名单（三类）**：①`docs/images/` ②`docs/release/*/images/`（发布 GIF/PNG）③`app/test/fonts/`
  （两个 otf，`ui-rules.md:38` 刻意入库）。现状：被跟踪的 >300 KB 文件 **31 个 / 30.2 MB**（`docs/images` 15、
  `docs/release` 14、`app/test/fonts` 2，最大 `docs/images/v0120-archive.gif` 4.7 MB），全在这三类；新增当次写理由。
- **同一脚本只许一份**：`gates-template/` 与 `scripts/` 下的同名脚本必须**字节一致**。现在只有
  `consolidate-memory.sh` 全等，`onboard.sh` 与 `verify-done.sh` 已漂 —— 漂掉的正是 E6 的守门段（1023 B）。
- **反模式**：当前实例——`.claude/worktrees/ecstatic-gates-be8970`（分支 `beta-0.11.16`，提交 `5b54852`）**764.4 MB**
  在仓库里躺了几周，里面还有 `app/build/` 与 `visual-baseline-*`。

### E18. 新代码先答「落点四问」
- **原则**：写文件之前先答四问：①只有这一页用 → 留在 `features/<域>/` 同目录（私有 `_xxx.dart`）
  ②第二页也要用 → 进 `core/widgets/` ③是纯逻辑、不带 Widget → 独立文件（`core/` 或 `domain/`）
  ④是页面 → `features/<域>/<name>_screen.dart`。**`domain/` 不许 import `features/`**。
- **落到哪**：`lib/features` 现有 10 屏 + 19 个私有件；`lib/core/widgets` 25 件；
  `AGENTS.md:88-100` 只描述职责、不判落点。
- **谁守门**：**自守**（没有目录归属断言；`domain/` 反向依赖由编译期循环兜住）。
- **例外与豁免**：`test/support/` 与 `tool/visual/` 是测试专用落点，不进 lib 判据。
- **反模式**：把一次性 widget 塞进 `core/widgets` —— 下一个 agent 会当它是公共件，改它时怕改坏。

### E19. 抽件不改行为；同一算式只许一处
- **原则**：「抄到第三处就抽」：同一段配方/算式出现第三次必须抽成具名函数再复用；**抽出时只搬不改**
  （数值一个不动），行为一改就另开一次改动并写明理由。
- **落到哪**：`core/layout.dart:187`（"抄到第三处就抽"的原始出处）；`alarm_service.dart:97-98/187/372/914`
  （为能单测而抽成纯函数）；`liquid_lens_controller.dart:11-12`（"数值一个没改"）；`day_summary.dart:3`、
  `glass_title_row.dart:8-9`。
- **谁守门**：**自守**（重复检测没有机器判据，`jscpd` 类工具未接入）。
- **例外与豁免**：为保"两档逐像素不变"而刻意保留的省电/液态两套分支（见 D4）不算重复。
- **反模式**：抽件时顺手"优化"了数值 → 视觉 diff 说不清是哪次改动造成的（D4 那第四套手抄配方就是这么来的，抄出去就再没回去）。
