# 证据 · 2026-11-08 规范层审计（beta / v0.12.10+185）

本目录是 `docs/standards/` 三份文件的原始凭据。有人质疑规范层里的判定强度、盲区、行数、条数时，
从这里往回查。**规范层写「应然」，本文件记「实然」**——两边不一致就是漂移。

审计对象：分支 `beta`，HEAD `f812718`（2026-11-06 18:37:51 +0800），`app/pubspec.yaml` `version: 0.12.10+185`。
审计方式：只读。逐条核对 `docs/standards/design-principles.md`（11 条）与 `docs/standards/dev-standards.md`（11 条），
外加横切体检（体量/命名/i18n/注释/异步/重复/测试组织/依赖死码）与门禁链核对。

## 文件

| 文件 | 是什么 |
|---|---|
| `0-crosscheck.md` | 横切体检原始结论留档：体量台账（>800 行 9 个文件 + 单方法 532 行）、命名（`show*` 62 / `open*` 11 的未文档化分工、3 处真异名）、i18n（278 处中文字面量 / 19 文件 / 4 处真漏）、注释（`TODO|FIXME|HACK` 实测 **0**）、异步（`catch (_)` 52 处、空 `catch` 27 处、2 处 `setState`-after-await）、重复（文字测量 3 实现 7 站点、`isDark` 15 文件、22 份测试启动样板）、测试组织（46/89 有 `stem_test.dart`）、依赖（`path`/`cupertino_icons` 零使用、`timezone` 隐式依赖、死代码 0） |
| `1-design-audit.md` | 设计层 11 条逐条判定与证据（每条：文档声称 / 代码实况 / 证据行 / 建议） |
| `2-engineering-audit.md` | 工程层 11 条逐条判定与证据（含门禁脚本、`release.ps1` 第 8b 步、`EXPECTED_TESTS` 统计法） |

> 注：`1-`/`2-` 两份是本轮两位审计员的回报原文归档（`work/audit/` 下另有 `scan_literals.py`/`scan_out.json`
> 是字面量扫描的中间产物）。归档在 `work/` 是为了不进仓库版本库；规范层的判定以本文表格为准。

## 一页结论

**22 条里：一致 15、半机器（文档说得比护栏强）4、自守被低报 1、缺守门 5、文本过期 3。**
新增条目 8 条（D12–D16 五条设计、E12–E17 六条工程中 4 条补齐既有事实，共 33 条）。

### A. 文档高报（写着机器拦，实际只守一半）——已在本轮改文档

| 条目 | 文档原话 | 实况 | 处置 |
|---|---|---|---|
| D4 | `glass_tier_test` 做「两档逐像素一致」 | **没有这个断言**：省电档只做结构断言（`GlassBlur` 不挂 `BackdropFilter`），像素断言只有反方向一条（液态关/开 `differing>0`，`glass_tier_test.dart:163-183,505-522`） | 改为「半机器」，盲区入档；补断言列入待办 6 |
| D5 | 判据只许 `glass.dart` + 6 调用点 | 名单与文档逐条一致，但 needle 只有 `liquidGlassActive`；开关真源 `state/app_settings.dart:110-124,156-161,193` 写的是 `liquidGlassEnabled`，不在名单也匹配不到 | 改为「半机器」，并把"唯一写入点"写进正文；补 needle 列入待办 4 |
| D9 | 守门 `liquid_lens_test` | 只钉 `Lift vs Drop` 不对称；`lensLit`/`lensUnlit` 在 `test/`+`tool/` **零命中** | 改为「半机器」 |
| E1 | `app_info_test` 守版本一致 | 正则抓了 `+build`（`app_info_test.dart:22`），但只比 `group(1)`，build 仅 `greaterThan(0)`（`:31`/`:35`）；`app_info.dart` 无 build 常量 | 改为「半机器」；`const appBuild` 列入待办 5 |

### B. 文档低报（写着自守，其实有护栏）——已在本轮改文档

| 条目 | 文档原话 | 实况 |
|---|---|---|
| D2 | 明度 alpha **自守** | `design_tokens_test` 明禁 `onSurface.withValues(alpha:)` 字面量（`:529-532,:103`），alpha 是被守的；只有 `navInactiveForeground`（0.72/0.55，`design_tokens.dart:663-668`）在扫描网外 |
| D6 | 「不重复震」**自守** | `haptics_commit_points_test.dart:12-20` 是常驻用例 |
| D7 | 值行一律 `GlassValueRow`，**自守** | `editable_affordance_test.dart:5-10` 按页面钉了三种视觉语言；8 处真实调用点已核实；旧 `_labelValueRow` 已从 `lib` 消失（`test/label_value_row_test.dart:3` 的描述过期，待修） |

### C. 文本过期（数字/条目与事实对不上）——已在本轮改文档

| 条目 | 过期处 | 实况 |
|---|---|---|
| E8 | 「`flutter test tool/visual/`（当前 1284 条）」 | `tool/visual` 只有 5 个 `testWidgets`，展开成「49 条屏单 × 变体」的矩阵，条数随屏单增长。**改为"认尾行 +N，不写数字"** |
| E9 | 「`git`/`gh` 输出用 `2>&1` 接」的反模式 | 已过时：`release.ps1:462-463` 改用 `Continue` + 查 `$LASTEXITCODE`；`:465/:475/:477/:513` 的 `2>&1` 是有意例外。另步骤号 `[4/6]`(`:172`) 与 `[8/8]`(`:419`) 自相矛盾（待修文案） |
| E10 | 反模式"不清点进程" | 现状无锁：`tools/flutter-test.sh:14-23` 只设 `PATH/PUB_CACHE/TMP` |
| E6 | `gates-template/` 与实装"已漂移" | **不是漂移**：模板是参数化（`ANALYZE_CMD`/`TEST_CMD`/…），实装是硬编码，分化是有意设计（`gates-template/README.md:4,21-23,35-36`）。`consolidate-memory.sh` 两份 IDENTICAL；`onboard.sh` 有差异。**真陷阱**：`install.sh:16` 无条件 `cp` 会覆盖实装版 |

### D. 已成事实但未成文（本轮新增条目）

设计层：D12 正文禁截断 + 单行只许 ellipsis（`kDeliberateEllipsis` 空表白名单 + 两条判据 + 四维矩阵）；
D13 字号自管、`textScaler` 整层替换（`app.dart:54`）；D14 24 小时制写死、1440→`24:00`（`shift_rotation.dart:51`）；
D15 命中区 44dp、视觉与命中分离（`glass_choice_chip.dart:37-39`、`glass_segment.dart:37`、`glass_pickers.dart:90`）；
D16 豁免必须具名可查（`design_tokens_test.dart:386` 要求带理由）。

工程层：E12 用户可见文案走 L10n（禁裸中文、禁内联 `L10n.isEn ? :`）；E13 await 后必检 `mounted`、catch 不许空吞；
E14 单文件 ≤800 行 + 只减不增台账；E15 注释写"为什么"、文件头写全路径、不拿 TODO 记账；E16 测试 `stem_test` / 行为命名分工；
E17 仓库卫生（worktree 与派生产物）。

### E. 仓库卫生（本轮唯一"现在就坏了"的事实）

`git worktree list` 4 条，其中 `C:/…/shiftassistant/.claude/worktrees/ecstatic-gates-be8970`
（分支 `beta-0.11.16`，`5b54852`）**764.4 MB** 在仓库内，含 `app/build/` 与 `visual-baseline-*`；
另有 `_wt-baseline-1002`（detached `137a6bf`）与 `../wt-main-fonts`（detached `a2206e0`）。
`.gitignore` 不排除 `.claude/worktrees/`，`.claude/settings.json` 是唯一被跟踪的 `.claude` 文件。
→ 规则写进 E17；清理动作见待办（需用户点头删 764 MB）。

### F. 复核过的硬数字（本轮实测，别再抄旧值）

- `flutter analyze` → `No issues found!`（exit 0，经 `tools/build-env.ps1`）。
- `flutter test`（`app/`，须 `PUB_CACHE`+`TMP`/`TEMP` 指向仓库内，否则报
  `null. The flutter tool cannot access the file or directory.`）→ 尾行 `00:36 +1242: All tests passed!`（exit 0），
  与 `ci.yml` 的 `EXPECTED_TESTS: '1242'` 一致。
- `app/lib` 89 个 dart 文件 / 36,513 行；`app/test` 158 文件 / 31,629 行。
- 计数器不可信：`grep '^\s+(testWidgets|test)\('` 只数出 1226 —— 印证 E11。

## 怎么复现

```bash
# 0. 环境（不设这三行会撞 "null. The flutter tool cannot access…"）
. tools/build-env.ps1                       # PATH / FLUTTER_ROOT
export PUB_CACHE="$PWD/toolchain/pub-cache" # Windows: $env:PUB_CACHE
export TMP="$PWD/work/tmp" TEMP="$PWD/work/tmp"

# 1. 条数与全绿
cd app && flutter test 2>&1 | tail -3        # 期望：+1242: All tests passed!

# 2. 单文件行数（E14 台账）
wc -l lib/features/calendar/calendar_screen.dart lib/core/l10n.dart   # 3196 / 1147

# 3. 设计层盲区（D1/D2）
grep -rn "EdgeInsetsDirectional" lib | wc -l                 # 扫不到 ≠ 不存在
grep -rn "Duration(seconds:" lib/core/widgets | wc -l         # 不报

# 4. i18n 真漏（E12）
grep -n "L10n.isEn ?" lib/features/calendar/calendar_screen.dart

# 5. 时钟扫描网（E5）
grep -rn "DateTime.now()" test tool | wc -l                   # 19 + 20+，均不在 clock_guard 网内

# 6. 仓库卫生（E17）
git worktree list && du -sh .claude/worktrees/* 2>/dev/null | sort -h | tail -3
```

## 日期

2026-11-08。对应提交：本次规范层统一（`docs/standards/README.md` 新建、`design-principles.md` D1–D16、
`dev-standards.md` E1–E17、`AGENTS.md` SOP 第 4 步改指入口）——**纯文档改动，不进 TDD 循环**，
验证证据 = 上述第 1、2 条命令的原始输出 + `scripts/link_check.py` 通过。
上一轮规范层的起点：`f3b9588`（立规范层）、`0f17b0f`（收口三处漂移）。

---

# 第二轮校准（同日，三份深审回报后）

第一轮由 11+11 条重写为 D1–D16 / E1–E17；第二轮是**用三位审计员的实测事实反过来修条文**——
规范只认实测，不认"审计员说"。三份原始回报（只读审计，未改源码）：

| 文件 | 体量 | 管什么 |
|---|---|---|
| `work/audit/A-design.md` | 680 行 | D1–D11 逐条 + 五类真漏洞（P1–P11） |
| `work/audit/B-engineering.md` | 571 行 | E1–E17 逐条 + 门禁链路三问 |
| `work/audit/C-gaps.md` | 约 400 行 | 已成事实但未成文的约定（G1–G9）+ 仓库卫生 |
| `work/audit/0-crosscheck.md` | — | 横切体检：体量、命名、i18n、异常 |

## 三位审计员口径冲突处，一律以本机复核为准

复核脚本 `work/verify_numbers.py`（剥注释后统计），实测输出：

| 项目 | 实测 | 审计员口径 | 采信 |
|---|---|---|---|
| `lib` 内 `catch (_)` | **52 处**，其中**空块 33 处**，`rethrow` **0** | C 说 52/27、B 说空 catch 24 | 52 / 33 |
| `alarm_service.dart` 空 catch | **24 处** | 文档原写 26 | 24 |
| `app/test` 真实时钟 | **22 处 / 10 文件** | 原写 19 处；B 说 54 处/17 文件 | 22 / 10 |
| `app/tool/visual` 真实时钟 | **21 处 / 5 文件** | 原写 20+ 处 | 21 / 5 |
| `lib` 文件头全路径 | **14 / 89** | B 说 14/88，一致 | 14/89 |
| `app/test`、`app/tool` 文件头 | **130/158、11/11** | 一致 | 采信 |
| `l10n` getter / fn / `t('` 调用 | **307 / 62 / 353** | 原写 397 处 t(；B 说 406 | 353 |
| 被跟踪 >300 KB | **31 个 / 30.2 MB**（docs/images 15、docs/release 14、app/test/fonts 2，最大 4.7 MB gif） | C 说 24 个、B 说 31 个 | 31 |
| `docs/superpowers` 里旧 `--delete-conflicting-outputs` | **20 处 / 11 份 plan** | 原写 12 处 | 20 |

## 这一轮改了什么（共 34 处补丁 + 4 处活跃文件）

- **修掉两条写反的规则**（审计员点名、最危险）：
  - E13 原写"`await` 后必检 mounted"→ 全库 `mounted` 33 处 vs `await` 496 处，逐 await 加会全线误报。
    改为"**await 之后还要碰 context/setState 才检**"。
  - E13 原写"`catch` 不许空吞"→ 与 52 处**刻意的静默降级**正相反。改为"副作用调用允许静默降级 + 必须写清理由"。
- **补齐事实**：E14 台账从 9 行收成 8 行（`design_tokens.dart` 757 行未超线，移出台账、记为 D1 的落点债）；
  E15 文件头规则**分级**（test/tool 硬要求、lib 新文件要求、存量不追）；E16 说明 46 vs 107 是**分工**不是强制；
  E17 补"`prune` 不回收"、worktree ≤3 且不许建仓库内、大件三类白名单、`gates-template` 同名脚本必须字节一致。
- **补掉文档高报**：D3 记「只测纯函数不查调用点」+ `recurring_fields.dart:432-453` 的 AA 硬违规；
  D4 记第四套手抄配方（`glass_pill.dart:71-96`）；D5"6 个调用点"→"6 个文件 / 12 处读取"；
  D7 四处例外→**五处**；D8 补两条从未进单的弹层；D9 令牌名照实（12 个标量，没有 `lensLift*`）；
  D10 反模式数值 8 → **12**（`_bendLogic`），并注明 `sanitizeGeometry` 只夹 band。
- **新增三条**（都带证据，不是发明）：D17 弹层三入口 + 破坏性动作红；E18 新代码落点四问；E19 抽件不改行为。
- **顺手修掉 4 个活跃文件里写死的「1284 条」**（`ci.yml:18`、`visual.yml:17`、`AGENTS.md:150`、`BUILD.md:66`）
  ——规范自己禁止写死条数，这四处正是反例；`AGENTS.md:150` 的「当前 1242 条」也改成"见 ci.yml 的 `EXPECTED_TESTS`"。
- **`scripts/standards_check.py` 加强**：路径解析新增 `core|features|domain|data|state` 前缀与
  `app/lib`、`app/test`、`app/tool` 三个根 —— 原来的正则只认 `lib/test/tool/...` 开头，
  `features/calendar/recurring_fields.dart` 这类写法**根本没被检查**（假绿）。

## 本轮验证

```
$ python scripts/standards_check.py
规范层 3 份，合计 54.8 KB（红线 56 KB）
路径全部存在，矩阵与条目一一对应。            # exit 0

$ python work/verify_numbers.py               # 上表全部数字的出处
```

矩阵 36 行 = D 17 条 + E 19 条（`Select-String '^\| [DE]\d+ \|'` 与 `^### [DE]\d+\.` 双计数一致）。
