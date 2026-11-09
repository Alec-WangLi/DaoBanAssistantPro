# 规范层 · 入口

> 本目录是**应然层**：现在必须怎么做。**事实**在代码里，**为什么**在 `docs/decisions/` 与
> `docs/changelog/`（要查历史才去，别当必读）。
>
> 三份文件，只有这三份：
> - `README.md`（本文件）——怎么用这套东西、谁守门、怎么改它。
> - `design-principles.md`——动 UI / 视觉 / 玻璃 / 触觉 / 动效读它，编号 **D1–D16**。
> - `dev-standards.md`——写任何代码、跑任何门禁读它，编号 **E1–E17**。

## 1. 三层分工与裁决顺序

| 层 | 在哪 | 回答什么 | 什么时候读 |
|---|---|---|---|
| 事实 | `app/lib`、`app/test`、`app/tool` | 现在是什么 | 开工一条命令拿现场，**不通读** |
| 规范 | 本目录 | 必须怎么做 | 写代码 / 动 UI 之前 |
| 决策 | `docs/decisions/`（按主题）、`docs/changelog/`（按版本） | 为什么这样、当时踩了什么坑、什么路已被否掉 | 只在要判重、要推翻结论时挑一个文件读 |

**冲突裁决顺序**（自上而下，先命中先算）：

1. **决策层里"已否决"的结论 > 规范层**。规范写"该这样"、决策层记着"这样试过，实测否掉了" ——
   按决策层办（带证据的那条），并回来改规范。
2. **规范层内部冲突 → 更具体的赢**。专用条目（D5 液态档）压通用条目（D1 令牌）；页面级例外压全局口径。
3. **代码与规范冲突 → 不许默认"以代码为准"**。先判是代码漂移还是规范过期：有测试/实测证据
   证明现有做法更对的，改规范并留一条证据；否则改代码。两边都不许"就这样吧"。

## 2. 每条规则的写法（五段，缺一段就是没写完）

**原则 → 落到哪 → 谁守门 → 例外与豁免 → 反模式**

- **谁守门**只许三种强度，且必须点名具体文件与它断言了什么：
  - **机器拦**：`test/<名>_test.dart` / `scripts/<名>.py`，不通过就红。要写清**它断言了什么**，
    而不是只写"有测试"。
  - **半机器**：有护栏但只覆盖一部分。**必须写清盲区**（哪一类改动它拦不住）——这是本规范层
    最容易被写成谎话的地方，写成"机器拦"而实际只守一半，等于教 agent 闭眼过。
  - **自守**：机器不拦，只有人守。全目录的自守条目集中在 §4，**那是漂移高发区**。
- **例外与豁免**单独成段，不再塞进"反模式"。豁免一律**具名可查**：豁免注释必须带理由
  （`// design-tokens-ignore: <理由>`）、白名单必须每条写为什么（见 D16）。
- **反模式**写"错在哪、历史上怎么栽的"，一句话一个，不要写成散文。

## 3. 编号与引用

- 设计 `D1…D16`，工程 `E1…E17`。全局唯一、**不复用、不重排**；废弃条目标 `~~D8~~（并入 D9）`，编号留着。
- 提交信息、代码注释、评审意见统一写 `D5` / `E11`。例：
  `// 液态档判据只许在名单内（D5）`。
- 新增条目前提：**至少有一条可复现的核查动作**（护栏测试，或一条能贴进报告的命令 + 期望输出）。
  连核查动作都写不出来的，是口号，不进规范层。

## 4. 守门矩阵（谁是机器、谁是人）

| 编号 | 规则一句话 | 护栏 | 强度 |
|---|---|---|---|
| D1 | 令牌唯一来源，界面层不写字面量 | `test/design_tokens_test.dart` | 半机器（4 目录 / 89 文件中 62 个；EdgeInsetsDirectional、`Duration(seconds:)`、条件表达式 fontWeight 不扫） |
| D2 | 层级只靠字号/字重/明度 | `design_tokens_test`（禁 alpha 字面量）+ 角色令牌 | 半机器（`navInactiveForeground` 在扫描网外） |
| D3 | 白字压实心主色按需压到刚过 AA | `design_tokens_test`（4.5 判）+ `glass_segment_ink_test`（渲真件读字色） | 半机器（只测纯函数、不查调用点；`recurring_fields.dart:432-453` 是已知硬违规） |
| D4 | 玻璃两档；省电档结构/交互一字不变 | `glass_tier_test` | 半机器（结构+反方向像素；**没有"两档逐像素相同"的断言**；另有第四套手抄配方待收） |
| D5 | 液态档判据只许定义处 + 6 个文件 | `liquid_scope_guard_test` | 半机器（needle 只有 `liquidGlassActive`；开关真源不匹配；实测 12 处读取） |
| D6 | 触觉三档、不重复震 | `haptics_guard_test` + `haptics_commit_points_test` | 机器拦 |
| D7 | 可编辑暗示只用三种视觉语言 | `editable_affordance_test`（按页钉） | 半机器（新页面不在名单内） |
| D8 | 新界面必须进视觉工装屏单 | 无 | 自守 |
| D9 | 弹簧两条方向分开、离散格式扫数 | `liquid_lens_test` | 半机器（只钉 Lift/Drop 不对称；Lit/Unlit 未钉） |
| D10 | 玻璃不采样玻璃；uniform 0 不是你的 | `glass_refraction_test` | 机器拦 |
| D11 | 班次色可读性 = 描边对比度 ≥1.3501 | `shift_palette_test`（16 颗 × 4 卡底） | 机器拦 |
| D12 | 正文禁截断；单行溢出只许 ellipsis | `tool/visual/text_fit_guard_test.dart` | 机器拦 |
| D13 | 字号自管，系统 textScaler 整层替换 | 无（靠 D12 的 320 宽矩阵兜底） | 自守 |
| D14 | 24 小时制写死，1440 显示 `24:00` | `shift_rotation` 相关用例 | 半机器 |
| D15 | 命中区 44dp，视觉尺寸与命中区分离 | `press_feedback_guard_test` 等 | 半机器 |
| D16 | 豁免必须具名可查 | `design_tokens_test` 的豁免解析 + 评审 | 半机器 |
| E1 | 版本号 X.Y 用户定，AI 只改 Z | `app_info_test` | 半机器（`+build` 无守门） |
| E2 | 改"今天归哪套"必须重排闹钟 | `day_override_repository_test`（间接） | 自守 |
| E3 | saveSchedule 按 id 增量 upsert | 无 | 自守 |
| E4 | 改 Drift 表后必须重生成 | `ci.yml` 禁旧参数 | 半机器（漏生成能否被 CI 抓住取决于编译） |
| E5 | 日期/时钟走 `appNow()` + `kAnchor` | `clock_guard_test` + `time_of_day_guard_test` | 半机器（只扫 `lib`） |
| E6 | 开工报技能；收尾过 verification | `scripts/verify-done.sh` | 半机器（"报技能"自守） |
| E7 | 扫源码/扫文档先剥注释与围栏 | `test/support/source_scan.dart` | 机器拦（模板可复用） |
| E8 | 改 UI 后跑视觉工装出图 | 无 | 自守 |
| E9 | 发布分支纪律；latest.json 只同步本次通道 | `scripts/release.ps1` 第 8b 步 | 机器拦（发完核对自守） |
| E10 | 不跑 dart format；不并发跑 flutter test | 无 | 自守 |
| E11 | 测试条数只增不减，EXPECTED_TESTS 同步 | `.github/workflows/ci.yml` | 机器拦 |
| E12 | 用户可见文案走 L10n | 无（`blankNonCode` 基建现成） | 自守 |
| E13 | await 后必检 mounted；catch 不许空吞 | 无 | 自守 |
| E14 | 单文件 ≤800 行（非生成物） | 无（台账在条目内） | 自守 |
| E15 | 注释中文、写"为什么"、文件头写全路径 | 无 | 自守 |
| E16 | 测试按 `stem_test` / 行为命名分工 | 无 | 自守 |
| E17 | 仓库卫生：worktree 与派生产物 | `.gitignore` | 自守（`prune` 不回收，只能 `remove`） |
| D17 | 弹层只走三入口；破坏性动作红 + 具名确认 | 无（裸 `showDialog` 现 0 处） | 半机器 |
| E18 | 新代码先答落点四问 | 无 | 自守 |
| E19 | 抽件不改行为；同一算式只许一处 | 无 | 自守 |

**自守条目共 14 条**（D8、D13、E2、E3、E8、E10、E12、E13、E14、E15、E16、E17、E18、E19），
按"每条上线前必须人工过一遍"处理；任何一条想要护栏，先补护栏，再把它从这里删掉 —— **矩阵是台账，
不是奖状**。

## 5. 维护纪律

1. **改规范 = 改三处**：条目正文 + §4 矩阵行 + `AGENTS.md` 的引用（若路径或读法变了）。漏一处即为漂移。
2. **数字不钉死**。条数、屏数、调用点数一律写"认 `flutter test` 尾行 `+N`"或"以本文 §4 为准"。
   历史教训：文档钉死"当前 1242 条""视觉工装 1284 条"，一次改动就让整句话变成假话。
3. **加条目要比改代码更难**。新条目必须带：一条可复现核查动作、至少 3 处现有证据（证明它已是惯例）、
   一段"违反它会怎样"。
4. **每版发版前或每季度**做一次规范审计：逐条核对矩阵强度，证据落
   `docs/decisions/evidence/<YYYY-MM-DD>-standards-audit/README.md`（照 `2026-11-08-standards-audit` 的格式：
   判定表 + 漂移清单 + 复现命令 + 日期与对应提交）。审计发现的漂移当次修完，不留到下次。
5. **规范层体积红线**：三份文件合计 **≤ 56 KB**（2026-11-08 审计后实测以 `standards_check.py` 输出为准）。
   每版审计时复核一次；超了说明在写历史，把细节搬去 `docs/decisions/`。
6. **护栏自检**：`python scripts/standards_check.py`——断言三份文件里引用的每个路径都真实存在、
   §4 矩阵的行数与条目数一致（D/E 编号不缺不重）。改完规范层跑一次，红了就是写了不存在的东西。

## 6. 现状与待办（2026-11-08 审计结论）

审计证据：`docs/decisions/evidence/2026-11-08-standards-audit/README.md`。当场做了什么、还剩什么：

- 做了：11+11 条重写为统一五段式；补 D12–D16、E12–E17 六条已成事实但未成文的约定；
  修掉 4 处"文档说得比护栏强"的低报/高报（D2、D4、D6、D7）与 3 处过期数字（E8、E9、E10）。
- 待补护栏（按收益排序，**补完把矩阵强度升级并删掉对应盲区**）：
  1. `clock_guard_test` 扫描根扩到 `test/` 与 `tool/`（实测 `test` 侧 22 处 / 10 文件、`tool` 侧 21 处 / 5 文件）。
  2. i18n 守门（`blankNonCode` 现成）+ 把 `app.dart:31` 的品牌名补进 `l10n`（旧口径"4 处真漏"已复核收敛）。
  3. 屏单对照（扫 `lib/features/**/*_screen.dart` 与 `visual_screens.dart`）。
  4. `liquid_scope_guard_test` 补 `liquidGlassEnabled` / `glassBlurDisabled` / `liquidRefractionEnabled` 三个 needle。
  5. `app_info` 加 `const appBuild`，让 `+build` 有守门。
  6. `glass_tier_test` 补"`blurOn=false` vs `true` 整帧像素差 = 0"。
  7. `recurring_fields.dart:432-453` 的选中方块改走 `solidAccent` + `onSolid`（D3 的 AA 硬违规）。
  8. 收掉第四套玻璃配方：`glass_pill.dart:71-96` 与 `calendar_screen.dart:1117-1142` 回令牌。
  9. `visual_coverage_test`：`lib/features/**/*_screen.dart` 必须在屏单里，并补 `RecurringRulePicker` /
     `EventTimingPicker` 两条 slug。
  10. `solidAccent` 调用点扫描（D3 的盲区就是"只测纯函数"）。
