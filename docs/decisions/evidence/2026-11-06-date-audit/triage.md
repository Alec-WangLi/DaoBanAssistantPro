# 日期依赖用例：这批到底修了什么（批次 1a/1b/1c 复盘）

作者：开发　日期：2026-11-06　对应提交：`c981ad1`（1a）、`045f3f9`（1b）、`92ab81a`（1c）

## 0. 先量现场

- `git diff --stat 591ff61..HEAD -- app/lib` → **空**（生产代码一行未动）。
- `git diff --stat 591ff61..HEAD -- app/test` → 17 个文件，95 insertions / 64 deletions。
- 实际替换：`DateTime.now()` **64 处** → 63 处 `kAnchor` + 1 处改成 `appNow()`（`app/test/alarm_screen_test.dart` 的 `isAfter(...)`，钉死后两边必须是同一个钟）；另有 5 个文件补了 `useFixedNow()`。
- 全套仍 **1236 条**，`EXPECTED_TESTS` 未动。

## 1. 判别实验：锚点是活的，不是装饰

只改 `app/test/support/fixed_clock.dart:24` 的 `kAnchor`，其余一个字不动，跑全套：

| 锚点 | 结果 |
|---|---|
| `2026-10-15`（现用值） | `+1236: All tests passed!` |
| `2026-01-31` | `+1236: All tests passed!` |
| `2026-02-28` | **2 条红**（`calendar_screen_test.dart`） |
| `2026-03-01` | **8 条红**（`calendar_screen_test.dart` 5、`calendar_chain_test.dart` 1、`info_card_fit_test.dart` 2） |

三条结论：

1. 锚点确实在驱动用例 —— 改它会让 8+2 条翻红，不是摆设。
2. **红的全在我没碰过的三个文件里**；1a/1b/1c 那 17 个文件在四个锚点下都是绿的。
3. 同一份代码在 2 月末 / 3 月初会红，说明这几个文件的断言假定「当前这个月有法定节假日」（10 月有国庆）。

## 2. 反向验证（HEAD 版表达式 + 敌意锚点 + 只补钉死）

做法：`git checkout` 回 HEAD 版测试文件（只补 import 与 `useFixedNow()`，表达式一个字不改），把 `kAnchor` 改成 `2026-01-31` 再跑 —— 此时「用例造数据用的真实今天（2026-11-06）」与「App 以为的今天（01-31）」错开，凡是结果依赖「今天是哪天」的用例必然翻红。

| 批次 | 红 | 落在哪 |
|---|---|---|
| 1a | 8 | `recurring_dialog_test` 4、`recurring_panel_test` 2、`recurring_advance_hooks_test` 2 |
| 1b | 6 | `alarm_screen_test` 4、`monthly_schedule_editor_test` 1、`schedule_timeline_test` 1 |
| 1c | 1 | `widget_push_dedup_test` 1 |

**合计 15 条、7 个文件**。这 15 条证明这些断言不是空转：真表达式 + 错开的今天 = 红。

## 3. 64 处的三种结局

| 类别 | 文件数 | 说明 |
|---|---|---|
| **真修掉（有实证）** | 7 | 上面那 15 条所在的 7 个文件；换掉后同一实验变绿，且旧表达式确实红 |
| **预防性统一（无实证风险）** | 10 | `recurring_panel_narrow_test`、`recurring_screen_test`、`recurring_repository_test`、`alarm_reschedule_budget_test`、`calendar_frame_budget_test`、`day_override_repository_test`、`editable_affordance_test`、`glow_layer_test`、`haptics_commit_points_test`、`todo_shift_marker_test` —— 同一实验下**改前改后都绿**，说明它们的数据与断言都只依赖相对偏移，不受「今天是哪天」影响 |
| **本来就无效（白改）** | 0 | 没有发现「换了等于没换、还增加噪音」的替换；上面 10 个属于同口径统一，不算无效 |

所以对这批的准确表述是：**真正带风险的是 7 个文件 / 15 条用例；其余 10 个文件是预防性统一，不是修 bug。**

## 4. 单独一条真东西：`widget_push_dedup_test.dart`

旧写法：把「今天」调成另一个班次时用 `dateOnly(DateTime.now())`，而快照窗口（224 天）是按 **App 的今天**算的。两者一旦不是同一天，被改的那天就落到窗口外 → 快照内容其实没变 → 指纹不变 → 不重推 → `expect 2` 得 `1`。

用户实际会遇到的形态：如果哪天真出现「App 认为的今天」与「调用方传进来的日期」错开（例如跨天时前台恢复），桌面小组件就会停在旧班次上不刷新。修法是把这条用例的时钟也钉到 `kAnchor`（补 `useFixedNow()`），让「造数据的今天」与「App 的今天」永远是同一个。
这是本批唯一一条**用例本来会挂**、且暴露了真实行为边界的例子。

## 5. 剩余风险（未修，等派单）

`2026-02-28` / `2026-03-01` 锚点下红的那 10 条，属于「断言假定当月有法定节假日」这一类，和批次 2 同族：

- `app/test/calendar_screen_test.dart`：`info-card-holiday-badge` 找不到（3 月无法定节假日）、节假日徽章 AA 对比度、当月统计缓存两条、水带 Transform、横屏画格子。
- `app/test/calendar_chain_test.dart`：「本月统计跨方案合并」拿到 `null`。
- `app/test/info_card_fit_test.dart`：360dp extraLarge / 特大英文 溢出 18.0 / 16.0 dp。

（这一节写于批次 1a/1b/1c 收口时；上面那 10 条后来全部修掉，见下一节 5b。）

## 5b. 那 10 条后来怎么修的（锚点形状族）

`2026-03-01` 锚点下红的 8 条 + `2026-02-28` 下红的 2 条，根子是同一个：**断言假定「当月必有法定节假日 / 必有 31 号 / 一定 5 行」**。修法三类：

1. **钉月份**：需要「这个月有节假日」的用例自己把时钟钉到有节假日的那个月（`_pinNow(DateTime(2026, 10, 3))`），不再指望真实月份；
2. **按几何算**：水带的拖动步长从 `day-card-$startDay` 实测的格子尺寸来（`cell.height`、`cell.width * 0.6`），横屏末格按当月天数算（`DateTime(y, m + 1, 0).day`），不再写死 `Offset(0, 60)` / `day-card-31`；
3. **承认边界、写算式**：`info_card_fit_test` 那两条（6 行月溢出 18dp / 16dp）不放宽成「允许滚」—— 先断言当月是 5 行，另立一条守 6 行月：滚的量必须**恰好等于** `weekdayH + 6×58 − 可用高度`（±1），信息卡自己仍不许滚。格高下限 58 是产品保证线，不动。

条数 1236 → **1237**（+1，就是那条六行月用例；另 8 条只加前置断言，不增不减）。探针量到的数：360×780 extraLarge，10 月 `cardH=274 cellH=57.2 scroll=0`；3 月（6 行）`cardH=260 cellH=58.0 scroll=18`。

---

# 批次 2/3/4 与全程结账（2026-11-06 收尾）

对应提交：`16920df`（批次 2）、`6aa6e63`（批次 3）、`a8370de`（批次 4）。
本节写给将来接手的人看：先把账结清，再谈要不要往 `docs/decisions/` 搬。

## 6. 批次 2/3/4 各自做了什么

**批次 2：6 处「日期形状」敏感的清点。** 逐处在六个刁钻锚点（01-01 / 01-30 / 01-31 / 02-27 / 10-14 周三 / 12-31）下跑过，结论只有一处是**静默空转**：

- `app/test/calendar_frame_budget_test.dart` 的 `_farDay()`：读**真实时钟**选「离今天够远」的一格，而网格画的是锚点那个月。真实今天是 8 号或 22 号时，`±7` 正好落回锚点（15 号）当天 —— 点的是那一格自己，滑行根本不起，「一帧内重建数 ≤ 80」这条断言**恒过**，每月 2 天、约 6.5%，且永远不会报错。改成按锚点算（`_farDayNumber()` 读 `appNow().day`），并加前置断言：要点的那天离今天不足 5 天就报「这条空转了」。
- 另外 5 处（`alarm_screen_test` 的 `+2 天` ×3、`recurring_dialog_test` 的 `.day` / `.weekday`）**本来就自洽**：闹钟页按「今天起的窗口」跨月照列；recurring 的期望值跟着 today 走。

**批次 3：顶栏年月在最宽串下的覆盖。** 原先唯一的怀疑是「只有 9 月才能验到最长月名」，**这条怀疑本身是错的** —— 英文顶栏用的是缩写（`Sep 2026`），实测 `May 2026` 才最宽（86.0dp），中文最宽是两位数月 `2026年12月`（105.1dp）。改法是钉住月份、按实测挑最宽的两串，并且发现原断言在**两行档上根本不生效**：年月外套 `FittedBox(scaleDown)`，挤了不报 `didExceedMaxLines`，只悄悄缩小 —— 于是加 `_shrinkOf()` 量「缩小了多少」（中文 1.0000、英文 0.9941）。这是本批第二个**静默空转**。

**批次 4：四处「真的在用当前时刻」的断言。**

- `app/test/snooze_duration_test.dart:90` / `:104` —— **静默空转**：`snoozeAlarm` 排的是 `appNow().add(...)`，用例基准却写 `DateTime.now()`。默认两者相等，看着没事；把时钟钉住（2026-10-15 09:00）而不动基准，立刻红 `Actual: <-31292.74…>`（差 31322.74 分钟 = 22 天）。
- `app/test/alarm_screen_test.dart:301` —— **静默空转，且源头在生产代码**：新建闹钟的默认钟点取 `TimeOfDay.now()`（真实时钟），默认日期取 `dateOnly(appNow())`。两个时钟一旦不同步，落点就总在「此刻」之后，`nextOnceDate` 的「已过 → 顺延一天」那一支只有在真实时刻恰好 00:00（1/1440 的运行）才走到。已把 `alarm_screen.dart:384` 与 `recurring_fields.dart:331` 改成 `TimeOfDay.fromDateTime(appNow())`；`alarm_ringing_screen.dart:196` 的 `ringClockText(TimeOfDay.now())` 语义就是真实此刻，**保留**。用例侧补两条前置断言：默认钟点必须等于 `appNow()` 的钟点、`nextOnceDate(...)` 必须不等于今天。
- `app/test/event_reminder_test.dart:23` —— **本来就自洽**：`_event()` 的默认 `date` 只有两条用例走到，而它们都在用到日期之前就 `return null` 了。

## 7. 全程清点结账（群规第 10 条的三分类）

`app/test` 共 **95 处** `DateTime.now()`、28 个文件。初筛按形状挑出 61 处，逐批复核时又补上 8 处初筛漏判的（`final t = DateTime.now()` 直接驱动日期的 3 处、顶栏 `L10n.yearMonth(...)` 1 处、`snooze_duration_test` 的基准 2 处、`_farDay()` 1 处、`event_reminder_test` 的默认日期 1 处），**形状敏感合计 69 处**，其余 **26 处**不构成日期窗口（`createdAt` 时间戳、`isAfter(now)` 的即时比较、注释与字符串里的字样）。

| 分类 | 处数 | 用例条数 | 落在哪 |
|---|---|---|---|
| ① **会红**（真会跑挂） | 32 | 23（去重后） | 1a/1b/1c 里「真修掉」的 7 个文件，反向验证红 **15 条**；另有锚点形状族 **8 条**（`calendar_screen_test` 5、`calendar_chain_test` 1、`info_card_fit_test` 2）—— 那 8 条的敏感源不是某处 `DateTime.now()`，而是「断言假定当月有法定节假日 / 当月有 31 号 / 当月 5 行」。**两组无交集，15 + 8 = 23**，见脚注① |
| ② **静默空转**（不报错、什么都没测） | 4 | 5 | `calendar_frame_budget_test` 的 `_farDay()`（8 号 / 22 号，6.5%）；`calendar_header_fit_test` 的 `L10n.yearMonth(DateTime.now())` 与 `didExceedMaxLines` 那条死路；`snooze_duration_test` 的基准 ×2；`alarm_screen_test:301` 的顺延那一支（1/1440，源头是生产代码的 `TimeOfDay.now()` 两行） |
| ③ **本来就自洽** | 33 | — | 1a/1b/1c 里 10 个文件的 32 处（反向验证改前改后都绿，属同口径统一）+ `event_reminder_test:23` 1 处；批次 2 复核的 5 处（`+2 天` ×3、`.day`、`.weekday`）包含在上面那 7 个文件里，单独看也都自洽 |
| 非窗口 | 26 | — | 时间戳 / 即时比较 / 注释 |

**脚注①：为什么 15 条与 8 条可以直接相加（无交集）。** 两组按**文件名**就不相交：

- 15 条的落点是 1a/1b/1c 的 7 个「真修」文件 —— `recurring_dialog_test` 4、`recurring_panel_test` 2、`recurring_advance_hooks_test` 2、`alarm_screen_test` 4、`monthly_schedule_editor_test` 1、`schedule_timeline_test` 1、`widget_push_dedup_test` 1。
- 8 条全部落在另外 3 个文件里（`calendar_screen_test` / `calendar_chain_test` / `info_card_fit_test`），逐个是：
  1. `calendar_chain_test`：「本月统计」跨方案时按简称合并，加总等于月长
  2. `calendar_screen_test`：信息卡：节假日徽章自占一行，农历独占下一行且不再被挤到右边
  3. `calendar_screen_test`：节假日徽章：文字与淡染底要过 AA 对比度
  4. `calendar_screen_test`：液态档那条水带 只挤**流动那一端**：带子内部那些格不套 Transform
  5. `calendar_screen_test`：当月事实缓存 换语言之后「本月统计」那一行跟着换（键里必须含语言）
  6. `calendar_screen_test`：当月事实缓存 调过班之后「本月统计」那一行跟着变（键里必须含排班本身）
  7. `info_card_fit_test`：一屏构图：360dp · extraLarge
  8. `info_card_fit_test`：一屏构图：360dp · 特大 · 英文

原始名单取自 2026-03-01 锚点那次全跑（`work/tmp/mar1.log` 末尾的 `Failing tests:` 段）。另外 `2026-02-28` 那次红的 2 条是这 8 条在另一种月份形状下的子集（同文件、同批断言），修好这 8 条后两个锚点一起转绿 —— **所以 ① 的条数只按 03-01 的 8 条计，不重复累加**。

两条口径上的提醒（将来搬文档时别丢）：
1. **② 比 ① 危险。** ① 会红，红了就有人修；② 绿着，绿得让人以为测过了 —— 这次 5 条里 3 条是靠「把时钟钉住之后突然红了」才暴露的。清点必须按「钉住时钟前 / 后」两遍跑，只看一遍永远发现不了 ②。
2. **③ 不等于「没问题」**：它只说明在试过的六个锚点下都绿。真实风险是「没试到的形状」（闰年 2 月 29、跨年、时区），这部分仍未覆盖。

## 8. 条数时间线：1228 → 1242（+14）

| 条数 | 批次 | 加了什么、为什么 |
|---|---|---|
| 1228 | 基线 | 液态玻璃 ②③ 修复之前的全套条数 |
| 1229 | ②③ 形状 | +1「竖直档是真胶囊：中段宽度恒定、两端正半圆」—— 把 27×42 / r=13.5 写进路径断言，反向验证换回拉伸立刻红 |
| 1230 | ① 边光 | +1「底栏折射开着时不叠 `CapsuleRimPainter`」—— 两圈白光相加 = 0.97 / 202 级，扫源码 + 行为侧数 painter |
| 1233 | ① 边光数值 | +3：令牌层（深色 0.42 / 浅色 ink 0.18 与亮度方向）、像素层（`_probeRimEdge` 量 122 级 / 85 级）、开关弦长 22.45（不是椭圆式 18.90） |
| 1236 | 起手越界 | +3：液态滑块每侧越过容器至少 4dp —— 底栏 64 档、矮屏 52 档、开关 30 槽。规则用 `>= 4`，不钉现状值（先写 `closeTo(4)` 被审查判为 Important，返工过一版） |
| 1237 | 六行月 | +1「六行月滚的量恰好等于格子卡在 58 上的差额」—— 承认边界、把 18dp 写成算式，而不是放宽成「允许滚」 |
| 1239 | 顶栏月名 | +2：中文 `2026年12月` 与英文 `May 2026` 在最宽串下不缩（后者实测缩 0.6%，即 0.9941） |
| 1242 | 时钟护栏 | +3：`app/lib` 里除响铃那句外不许有 `TimeOfDay.now`（扫源码 / 自证剥壳 / 豁免仍在） |

口径：**这 14 条全是护栏，没有一条是「改行为后补个绿」**。每一批都做过反向验证（把修复撤掉必须红），红的位置与原因写在各批的提交信息里。
