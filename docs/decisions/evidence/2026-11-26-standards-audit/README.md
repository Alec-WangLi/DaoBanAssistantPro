# 规范审计 · 2026-11-26

> 对应提交：v0.14.1（beta）。复核对象：`2026-11-08-standards-audit` 留下的 10 条待补护栏。
> 本文只记**证据与判定**，规范正文在 `docs/standards/`。

## 1. 判定表

| 2026-11-08 待办 | 实测（2026-11-26） | 判定 |
|---|---|---|
| 1. `clock_guard_test` 扩到 `test/` + `tool/` | 仍 `Directory('lib')` 写死 | **仍开着** |
| 2. i18n 守门 + `app.dart` 品牌名 | 品牌名已是 `L10n.appName`；守门已补 `i18n_guard_test` | **已关** |
| 3. 屏单对照 | 已补 `visual_coverage_test` | **已关** |
| 4. `liquid_scope_guard` 补三个 needle | 改成每标志一张范围表（见 §3） | **已关（换了解法）** |
| 5. `app_info` 加 `appBuild` | 已加，`app_info_test` 同时校验 `+build` | **已关** |
| 6. `glass_tier_test` 补像素差 = 0 | 仍全是结构/状态断言 | **仍开着** |
| 7. `recurring_fields` 的 AA 违规 | 已改 `solidAccent` + `onSolid`，并补渲染用例 | **已关** |
| 8. 收第四套玻璃配方 | `glass_pill.dart`、`calendar_screen.dart` 仍手写 | **仍开着** |
| 9. `visual_coverage_test` | 同 3 | **已关** |
| 10. `solidAccent` 调用点扫描 | 静态扫不出，改成一页一条渲染用例 | **仍开着（换了标准）** |

## 2. 这一轮新查出来的（不在原清单里）

### 2.1 屏单静默漏了两屏

`lib/features` 下 15 个 `*_screen.dart`，`visual_screens.dart` 只覆盖 13 个 ——
`BackupScreen` 与 `LogScreen` 从 v0.14.0 起就没进屏单。两件事都照常绿，因为
**漏掉不报错**。已补 `82_backup` / `83_log`，并补护栏 `visual_coverage_test`。

### 2.2 档位标志四个，护栏只管一个

规范写「液态档的判据只许出现在定义处 + 六个文件」，护栏的 needle 是 `liquidGlassActive`。
另外三个标志的实测读取点：

| 标志 | 语义 | 代码读取点（剥注释后） |
|---|---|---|
| `liquidGlassEnabled` | 用户开关 | `core/glass/glass.dart`、`state/app_settings.dart` |
| `glassBlurDisabled` | 省电档 | `core/glass/glass.dart`、`core/theme/animated_background.dart` |
| `liquidRefractionEnabled` | 折射闸门 | `core/glass/glass.dart` |

**为什么不能塞进同一张名单**：它们不是同一件事。`animated_background.dart` 读省电档是
正当的（省电档要停背景动效），塞进同一张名单只会靠扩大豁免变绿。改法是每个标志一张
范围表（`liquid_scope_guard_test.dart` 的 `_flagScopes`）+ 常驻证据用例。

### 2.3 E14 台账在漂

件数没变（8 件），但行数：

| 文件 | 2026-11-08 | 2026-11-26 | 变化 |
|---|---|---|---|
| `alarm_service.dart` | 1200 | 1776 | +48% |
| `l10n.dart` | 1147 | 1688 | +47% |
| `app_repository.dart` | 1468 | 1717 | +17% |
| `calendar_screen.dart` | 3196 | 3342 | +5% |
| `schedule_screen.dart` | 986 | 1051 | +7% |
| `schedule_editor_screen.dart` | 2532 | 2545 | +1% |
| `profile_screen.dart` | 1096 | 1088 | −1% |
| `liquid_lens.dart` | 1390 | 1390 | 0 |

结论：台账写死行数是 §5.2 自己禁止的写法 —— 它已经漂了一次。已改成「实测快照，不是契约」。

### 2.4 玻璃配方的透明度没有归口

`lib` 里 `withValues(alpha: …)` 有 **45 种不同取值**。`design_tokens_test` 明说玻璃配方
（`blur*` / `glass*`）**有意**不进令牌阶梯 —— 于是「两档玻璃」之外长出了手抄的第三、四套：
`glass_pill.dart`（白 0.95/0.55、深 0.22/0.06）、`calendar_screen.dart`（白 0.98/0.95/0.55）、
`schedule_screen.dart:157`（白 0.98）。三处看着是同一件事抄了三遍，值还不一样。**仍开着。**

## 3. 复现命令

```bash
# 屏单覆盖
bash tools/flutter-test.sh test/visual_coverage_test.dart
# 档位标志范围
bash tools/flutter-test.sh test/liquid_scope_guard_test.dart
# i18n 裸文案
bash tools/flutter-test.sh test/i18n_guard_test.dart
# 月网格 AA
bash tools/flutter-test.sh test/recurring_month_grid_ink_test.dart
# 规范层自检（断链 / 编号 / 体积）
python scripts/standards_check.py
# E14 台账行数
cd app && find lib -name '*.dart' -print0 | xargs -0 wc -l | sort -rn | awk '$1>800 && $2!="total"'
```
