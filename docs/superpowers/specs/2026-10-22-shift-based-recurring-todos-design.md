# 重复待办：按班次重复 + 每月多选 + 两处小改（设计）

- 日期：2026-10-22
- 起因：用户 v0.12.2 真机测试后的三条反馈（原话）：
  1. 「现在新建待办事项时，选到每周的时候，日期格子挨得太近了。」
  2. 「能不能在固定周期里加入选定班次，联动咱们的排班表？以及每个月哪几天？」并举了两个例子：「每次上夜班那天提醒我带某样东西」「每次白班都要写台账记录」。
  3. 「重复待办的编辑笔图标去掉吧。因为现在有点多余了，你直接点击它就能编辑了，要那个图标干什么？不需要。」
- 用户拍板（2026-10-22）：
  - 一条规则**可以同时勾选多个班次**。
  - 「每月」要**多选几天**：「每月 1 号、15 号分别签两次灭火器检查记录」。
  - 班次匹配**按班次名字**没问题（「班次名字大差不差，最多只是重新打乱了」），但**要在界面上提醒**，否则容易让人混乱。
  - 提醒时间**沿用用户自己设的固定钟点**，不与班次联动（「有的人可能是在下班之前提醒一下自己：今天这固定的活有没有干完」）。
- 影响版本：v0.12.3 测试版（`X.Y` 由用户定，AI 只动 `Z` 与 `build`）

---

## 1. 目标 / 非目标 / 反目标

**目标**

- 重复规则新增第五档「按班次」：从排班表的班次里**多选**，按「那天我们班组的班次」生成待办。
- 「每月」从单选一天改成**多选几天**（1..31）。
- 「每周」的星期格子从会折行的 `Wrap` 改成**一行七个等宽格子**，间距拉开。
- 删掉重复待办面板行尾那颗铅笔图标（整行点进去本来就是编辑）。
- 换排班表 / 调班之后，按班次规则**跟着走**；班次名字找不到时**在界面上说出来**，不静默。

**非目标**

- 不做「班次开始前 N 分钟」这类相对提醒（用户明确不要）。
- 不加「第 N 个周末」「每隔 N 天」「每年」等周期种类。
- 不改一次性待办的任何行为。
- 不改原生 Kotlin（规则仍在 Dart 侧算成绝对时刻表，原生只弹队首、续队尾）。
- 不改桌面小组件、闹钟链路的算法（但会复用它们的解析入口 `ScheduleChain`）。

**反目标**（做成了也算失败）

- 按班次规则靠**班次 id** 匹配 —— id 是每套方案各自的、换表就全变，症状是「换了排班表之后这条待办再也不出现了」且不报错。
- 用 `shortLabel`（简称）匹配 —— 简称是显示用的缩写，用户挑的是完整名字；两份匹配口径也会漂。
- 班次名找不到时静默 —— 用户明确要求提醒（见上）。
- 每月多选按「每个选中的日子各算一次」而不去重 —— 2 月同时选了 30 与 31 会生成**两条同一天**的待办。
- 为了塞下第五档把分段器文字缩小到读不出来，或把「不重复」改成语义不清的图标。
- 把「按班次」做成壳子：只在今天算一次、之后不再跟排班变化。

---

## 2. 规则模型

### 2.1 五档规则

「重复」分段器从四档扩到五档：

| 档位 | 中文 | English | 数据 |
|---|---|---|---|
| 0 | 不重复 | Never | `repeat == null` |
| 1 | 每天 | Daily | `repeatType = 0` |
| 2 | 每周 | Weekly | `repeatType = 1` + `weekdays` 位掩码 |
| 3 | 每月 | Monthly | `repeatType = 2` + `monthDays` 位掩码（新） |
| 4 | 按班次 | By shift | `repeatType = 3` + `shiftNames`（新） |

⚠️ 枚举是 `RecurRepeat { daily, weekly, monthly, shift }`，`repeatType` 仍是枚举下标（0..3）—— 落库 / 读库的映射在 `RecurringSeriesRowX.toDomain()` 与对偶的写入处，只改这两处。

⚠️ **English 的「不重复」从 `Does not repeat` 改成 `Never`**：五档之后那一格只占约 56dp，「Does not repeat」缩到 0.6 倍也只有 8px 高，读不出来。中文「不重复」不变。

### 2.2 按班次：匹配口径

- **选择对象**：排班表里的班次**定义**（`ShiftClass`），按 `name`（完整名字，如「上夜班」）记录。多选。
- **判定**：对某一天 `d`，取 `ScheduleChain.shiftOn(d)?.name`（**我们班组**的班次，已包含按天调班覆盖、多套方案按日期衔接、按月切法）。名字在选中集合里 → 这天是发生日。
- 那天没有班表、或者是一张**空白表**（法定班次，`cycle` 为空）→ `shiftOn` 为 null → 不是发生日。
- 名字比较用 `==`（精确、区分大小写）；不做模糊 / 前缀匹配（「白班」与「白班（长）」是两回事）。
- **跨方案按名字延续**：换排班表后，只要新表里有同名班次，规则照旧生效 —— 这是用户要的语义，也是必须做提示的原因。

### 2.3 发生日查询（领域层）

`domain/recurring_todo.dart` 里四个查询函数各加一个可空入口：

```dart
String? Function(DateTime day)? shiftNameOn
```

- `shiftNameOn == null`：按班次规则一律返回 null（没有排班数据时宁可不出，也不猜）。
- `firstOccurrenceOnOrAfter` / `occurrenceOnOrBefore`：按班次规则**逐天**前后扫描，命中即返回；扫描上界 `_shiftScanDays = 400`（周期最长 60 天，「其余时间」被设成「无」时才可能长期空档；超过 400 天没有匹配就视为无解，返回 null）。
- `nextOccurrenceAfter` / `upcomingFireTimes` 顺着上面的实现走，签名同样透传 `shiftNameOn`。
- `ruleLabel`：按班次返回 `L10n.everyShift(names)` → 中文「每次上夜班、下夜班」，English「On Night, Late」。**不带日期**（提醒正文跨很多次，写死日期第二次就是错的）。

**生成器「只往前、不回退」这条既有不变量，对按班次规则同样保留**（`advanceRecurringTodos` 里那句 `daysBetween(keep.date, occ) > 0`）。它带来一个**明确接受的行为**：

- 如果当前那一行已经生成在「今天」，之后用户换了排班、今天不再是选中的班次 —— 那一行**留在原地**，不会被拽到更早的班次日，也不会被删掉。它是「当时确实该做的一件事」，用户自己勾掉 / 删掉即可。
- 反向（今天从非班次日变成班次日）会正常前移 —— 生成器本来就做这件事。
- **提醒时刻表不受这个影响**：它由系列规则 + 当前排班现算（`rescheduleAll` 时重算），下一次一定落在新排班的班次日上。

不做「按班次规则回退对齐」：那要区分「用户手工挪过的行」与「自动生成的行」，而库里没有这个标记；回退还会把一条待办丢到已经过去的日期上。

### 2.4 每月多选

- `monthDays` 是 **1..31 的位掩码**：`1 << (day - 1)`（与 `weekdays` 同一套路）。
- 某年某月的候选日：对每个选中的日子，**先夹到该月最后一天**，再**去重**。
  - 2 月选了 30 和 31 → 只有 2/28（闰年 2/29）**一天**，不会出两条。
  - 4 月选了 30 和 31 → 只有 4/30 一天。
- `monthDays == 0` 是脏数据（界面不允许清空到最后一天），查询返回 null（照 `weekdays == 0` 的先例）。
- 「至少保留一天」的约束做在多选控件里：点掉最后一个已选项时**不生效**（控件把自己补回去）。按班次同样。**这条与「每周」现有的「允许清空」不一致**，是这一轮有意的收紧 —— 清空的规则会在界面上完全看不出异常地永不触发（`occurrenceOnOrBefore` 返回 null）。每周这一档本轮不顺手改（改它会牵动自定义闹钟共用的 `GlassWeekdayPicker` 语义与既有用例），但**按班次与每月新写的控件从第一天就守住**。

---

## 3. 数据与迁移（schema 14 → 15）

`RecurringSeriesRows` 三处变化：

| 列 | 变化 | 说明 |
|---|---|---|
| `month_days` | **新增** `INTEGER NOT NULL DEFAULT 0` | 每月多选的位掩码 |
| `shift_names` | **新增** `TEXT NULL` | JSON 数组（`["上夜班","下夜班"]`），null / 空数组 = 未选 |
| `month_day` | **删除**（`TableMigration` 重建表） | 迁进 `month_days` 之后不再有消费者；不留死列（照 v10 删 `alarm_minute` 的先例） |

迁移分支 `if (from < 15)`，写法与顺序：

1. ⚠️ **必须排在 `from < 11` 之前**（分支倒序跑、最新一版先跑）。但 `recurring_series_rows` 是 `from < 11` 那段才建的 —— 所以整段要 **`if (from >= 11)` 守卫**（照 v9→v10「只有 v6 及以后才有 shift_class_rows」、v12→v13「只有 v12 才有时段两列」两次先例）。从 v10 及更早升级时，表由 `from < 11` 按**当前 schema** 建出来，新列自带默认值。
2. `m.addColumn(recurringSeriesRows, recurringSeriesRows.monthDays)`
3. `m.addColumn(recurringSeriesRows, recurringSeriesRows.shiftNames)`
4. 把旧数据搬过去（原始 SQL，此时 `month_day` 还在）：
   ```sql
   UPDATE recurring_series_rows
      SET month_days = (1 << (month_day - 1))
    WHERE repeat_type = 2 AND month_day BETWEEN 1 AND 31
   ```
5. `m.alterTable(TableMigration(recurringSeriesRows))` 删掉 `month_day`。
   - ⚠️ **顺序不能反**：`TableMigration` 只拷「新旧表都有的列」。先 `addColumn` 再重建，`month_days` 才会被一并拷过去；反过来先重建，`month_days` 会拿到默认值 0，迁移数据全丢。
6. 改表后跑 `dart run build_runner build --delete-conflicting-outputs`。

**迁移测试**（新文件 `migration_v14_to_v15_test.dart`）：
- 每月 15 号的行 → `monthDays == 1 << 14`；
- 每天 / 每周的行 → `monthDays == 0` 且其余字段原样；
- `shiftNames` 默认空；
- 老库升级后「当前这一次」的生成结果与升级前一致（用 `advanceRecurringTodos` 驱动一遍）。

---

## 4. 按班次的界面

### 4.1 可选班次从哪来

新增 `ScheduleChain.classChoicesFrom(DateTime day)`（`domain/schedule_chain.dart`）：

- 取**从这天起还可能生效**的方案的班次：那天归谁的方案 → 兜底（其余时间）方案 → **时段终点为 null 或 ≥ day** 的各段方案；
- 按 `ShiftClass.name` **去重**（同名只出现一次，颜色取第一次遇到的那个）；
- **时段在 day 之前就结束了的方案不贡献选项** —— 否则用户可以挑到一个只属于过去时段的班次，规则从今往后永远不会命中，而界面上完全看不出来（正是 §1 反目标里那种「壳子规则」）；
- 空白表没有班次定义，天然不贡献选项；
- 整条链一套方案都没有 → 返回空，界面给一句指路（`L10n.shiftRuleNoSchedule`：「还没有排班表，先把班排上再来选班次」）。
- **休班类班次不排除**（`isRest` 一律不过滤）：「每个休息日提醒做某事」是合理用法，用户挑得到就该能用。

加载方式（**不在弹窗里 watch 流**）：

- 待办新建 / 编辑弹窗：`_showAddDialog` / `showEditEventDialog` 本来就是 async，显示弹窗前用 `repo.getActiveSchedules()` 读一次，把 `List<ShiftClass>` 传进 `_EventFields`；
- 系列编辑器（`ConsumerStatefulWidget`）：`initState` 里读一次，`setState` 落进 state；
- 重复待办面板：与列表现有的「一次性读」同一个 Future —— 新增 `recurringPanelProvider`（`FutureProvider.autoDispose`）返回 `(List<RecurringTodo>, ScheduleChain?)`，**不 watch `activeScheduleProvider`**（drift 查询流取消时排的零时长定时器会让弹窗用例报「A Timer is still pending」，`savedTemplatesProvider` 踩过同一个坑）。

### 4.2 班次多选控件

- 一排 `Wrap` 的 `GlassChoiceChip`（label = 班次完整名字，color = 班次色，selected = 已选）。它自己发 `Haptics.select()`，调用点**不再补**。
- 已选但**在 `classChoicesFrom(今天)` 里找不到**的名字：也渲染成一颗 chip（红色调描边 / 打叉的视觉），并在下面给一行提示 `L10n.shiftRuleMissing(names)`：「当前排班表里没有『上夜班』」。判据与可选列表**同一份** —— 两处各算一遍就会出现「列表里没有、却又不提示」。
- chips 下方常驻一句口径说明 `L10n.shiftRuleHint`：「按班次名称匹配；换排班表后，新表里有同名班次就会继续生效。」—— 这就是用户要的「提醒」。
- 切到「按班次」而一个都没选时：默认勾**所选日期（startsOn / 今天）当天的班次**；那天没有班次就勾第一个；一个班次都没有就不勾（配上面的指路）。

### 4.3 规则无效时不许保存

按班次与每月这两档，**保存前必须至少有一项选中**：

- 控件本身不允许点掉最后一项（§2.4），这是第一道闸；
- 但还有两条它管不到的路径：整条链一个班次都没有（新建库 / 只有空白表），以及老库里的脏数据（`monthDays == 0` 的每月系列、`shiftNames` 为空的按班次系列）。所以保存动作再做一次校验：无效时**不关窗、不写库**，在控件下方显示一行对应提示（`L10n.ruleNeedsShift`「先选一个班次」/ `L10n.ruleNeedsMonthDay`「先选一天」）。
- 打开老数据时同样兜底：`monthDays == 0` 的每月系列、`shiftNames` 为空的按班次系列，进弹窗时按上面的默认规则**补一个合法值**（月份取 startsOn 的号数，班次取当天的班次 / 第一个）。
- 选「按班次」而一个班次都没有时，**仍然可选、但保存被上面那行挡住** —— 比把这一档藏起来好：用户看得见这个能力，也看得见为什么现在用不了（指路文案就在下面）。

### 4.4 管理面板

- 行尾那颗铅笔（`editHint`）**删除**，连同 `_row` 里两处提到它的注释。窄窗那一支本来就没有它，不用动。
- 按班次的系列：副标题 `parts` 用 `ruleLabel`（「每次上夜班」）拼现有那串；若选中的名字**一个都不在当前链上**，在末尾追加 `L10n.shiftRuleMissing` 的同款提示（用 `·` 连接会太长，改成第二行或在 `parts` 里换一个短句 —— 构建时按窄窗实测定，见 §9）。
- 「下次 X」由 `nextOccurrenceAfter(s, today, shiftNameOn: chain 的闭包)` 现算。

### 4.5 排班变化之后（所有会改变「那天上什么班」的入口）

v0.12.1 立的规矩（「改动『今天归哪套』的入口必须重排闹钟」）这一轮**再加一步**：这些入口在重排闹钟之前先跑一次 `repo.advanceRecurringTodos(today:)`。

**判据不是「哪几个文件」，而是「这一步有没有改变某天上什么班」**，现有入口至少包括：

- `schedule_management_screen.dart` 的 `_replanAlarms(ref)`（换其余时间 / 增删改时段 / 删方案）；
- **排班编辑器的保存**（`schedule_editor_screen.dart`）：改周期 / 基准日 / 班组错位 / 班次定义（含改名、删班次）；
- **套用模板新建方案**；
- 日历里的「调整班次 / 恢复轮转」（`calendar_screen.dart` 调 `rescheduleAll` 那处）。

理由：按班次规则的「当前这一次」和提醒时刻表都由当天的排班解析而来；改了排班却只重排闹钟，待办列表里那条会停在被改之前的班次日上，且**不报错**。

⚠️ 生成器只往前、不回退（§2.3），所以这一步能保证的是「该出现的会出现」「该前移的会前移」；**已经生成在今天、改完之后今天不再匹配的那一行会留在原地** —— 这是明确接受的行为，测试只断言前移与新增，不断言回退。

---

## 5. 每月多选的界面

- 一个 **31 格、7 列**的数字网格（5 行，最后一行 3 格）。格子等宽铺满、间距 4dp，选中 = 主色实心 + 白字，未选 = 现有淡染胶囊配方。
- 数字走 `FittedBox(scaleDown)`（与 v0.11.12 的字号降级顺序一致：不省略、不裁）。
- 点格子 toggle 一位，`Haptics.select()`；点掉最后一天不生效（见 §2.4）。
- 网格下方一行小字 `L10n.monthDaysHint`：「小月没有的日期会落在当月最后一天；同一天只出现一次。」
- 替换现在那个「每月」`ListTile`（原来点开单选 1..31 的选择层）。`_EventFields` 与系列编辑器的 `monthDay: int` 全部改成 `monthDays: int`。
- 从「每周 / 每天」切到「每月」而 `monthDays == 0` 时，默认勾**所选日期那一天的号数**（与星期档补一天同一个理由：空掩码是脏数据）。

---

## 6. 每周格子（间距）

现状出图（`65_recurring_series_editor_light.png`）：七个 chip 用 `Wrap(spacing: gapIconText = 6)`，在弹窗宽度下折成 **5 + 2 两行**，相邻 chip 只隔 6dp，第二行只剩两个、左边空一大片。

改法：`GlassWeekdayPicker` 内部换成**一行七个等宽格子**：

- 外层 `LayoutBuilder` 拿到可用宽，`Row` 里每个格子 `Expanded`，格子之间固定 4dp 间隙；
- 格子内部居中、横向内边距不再用 `spaceMd`（宽度由等分决定），文字 `FittedBox(scaleDown)`；
- 视觉配方（选中实心主色 / 未选淡染 + 描边、圆角 `radiusL`、`AnimatedContainer` + `durMed`）**一个字段都不改**；
- 320dp 小窗下每格约 37dp，「周一」两个字 13px ≈ 26dp —— 放得下；大字号 / 英文由 `FittedBox` 兜底。

⚠️ 它同时被**自定义闹钟的「每周」**用着（`alarm_screen.dart`），这是有意的：两处是同一个选择行为，不分成两套。改动后两处一起变，工装两屏一起看。

---

## 7. 提醒链路

- `planRecurringReminders(series, from:, shiftNameOn:)`：透传给 `upcomingFireTimes`。
- `AlarmService.rescheduleAll` 已经拿得到 `schedules.chain`，把闭包一起递给 `rescheduleRecurringReminders(series, shiftNameOn:)`。
- 提醒时刻**仍是用户设的固定钟点 + 提前档位**（用户拍板），不跟班次开始时间联动。
- **顺带修一条既有缺口**：待办页里新建 / 编辑重复待办走的是 `_rescheduleReminders` → `rescheduleEventReminders`，而后者跳过 `seriesId != null` 的行 —— 也就是说新加的重复待办**要等下一次 `rescheduleAll`（冷启动等）才排上提醒**。这一轮把它改成同时调用 `rescheduleRecurringReminders`（参数用同一份 series + chain），否则「按班次」新建完当天就可能该响而不响。

---

## 8. 文案（L10n）

| key | 中文 | English |
|---|---|---|
| `repeatNone`（改） | 不重复 | **Never** |
| `repeatShift` | 按班次 | By shift |
| `shiftRuleHint` | 按班次名称匹配；换排班表后，新表里有同名班次就会继续生效 | Matched by shift name — switching schedules keeps it working if the new one has the same name |
| `shiftRuleNoSchedule` | 还没有排班表，先把班排上再来选班次 | No schedule yet — set one up first |
| `shiftRuleMissing` | 当前排班表里没有「{}」 | Not in the current schedule: "{}" |
| `ruleNeedsShift` | 先选一个班次 | Pick at least one shift |
| `ruleNeedsMonthDay` | 先选一天 | Pick at least one day |
| `everyShift` | 每次{} | On {} |
| `everyMonthOnDays` | 每月 {} 号 | Day {} of every month |
| `monthDaysHint` | 小月没有的日期会落在当月最后一天；同一天只出现一次 | Days that don't exist in a month fall on its last day; never twice in one day |

- `everyWeekOn` 现有实现保留。
- 帮助内容（`help_content.dart` 与 `L10n.guide…` 里那句「每天 / 每周几 / 每月某日」）补上「按班次」，FAQ 补一条「怎么让待办跟着班次走」。

---

## 9. 验收

**单测（只增不减，当前 1106）**

- `recurring_todo_test.dart`：按班次前后查询（有/无匹配、跨方案名字、调班覆盖、空白表、`shiftNameOn == null`）；每月多选（1+15、30+31 在 2 月去重、4 月夹到 30、`monthDays == 0`、`startDate` 闸门）。
- `recurring_alarm_plan_test.dart`：按班次系列在 `upcomingFireTimes` 里排出的时刻（用一个假 resolver）。
- `migration_v14_to_v15_test.dart`（见 §3）。
- 仓库层：`advanceRecurringTodos` 在班次日生成当前这一次、调班后跟着换。
- 界面：五档分段器、班次 chips 勾选与保存、缺名提示、每月网格多选保存、面板无铅笔、面板缺名提示。
- 界面：没有可选班次时保存被挡下并显示提示；只属于**已结束时段的方案**的班次**不出现在可选列表**里；老数据（`monthDays == 0`）打开时自动补一个合法值。
- 护栏：切到按班次默认勾当天班次；按班次/每月不能清空最后一项。
- 反向验证：把匹配改成按 id → 换表用例红；把月度去重去掉 → 2 月用例红。

**工装（`app/tool/visual/`）**

- 更新 `65_recurring_series_editor`：五档 + 按班次选中态（含 hint 与缺名态）；
- 新增 `66_recurring_monthly_days`：31 格网格、多选 1/15；
- 更新 `25_recurring_panel`：带一条按班次系列；
- 顺带看 `06_alarm*` 的每周格子（共享件改动）；
- `text_fit_guard_test` 覆盖新屏（320/360 × 四档字号 × 中英）。

**真机（ADB 已连接）**

- 先在真机上量一遍当前星期格子的间距并截图（用户报的现场）；
- 改完装到真机上验：七格一行、按班次勾选与提醒、每月 1/15 两条、面板无铅笔；
- 换排班表后按班次待办与提醒跟着变（与 v0.12.1 的复现路径相同）。

**验收标准**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿；工装逐张过一遍。

---

## 10. 版本与发布

- `0.12.2+177` → **`0.12.3+178`**（测试版，beta 分支）。
- 更新日志 prepend 一条、窗口保持 10 条；`app_info.dart` 同步（`app_info_test` 盯着）。
- AGENTS.md 的版本史与「最近改动」补一条；帮助内容同步。
- 完成后按既有流程构建 APK、提交推送、`scripts/release.ps1` 发 GitHub Release。

---

## 11. 留给构建者的

- 面板里「缺名提示」放第二行还是拼进 `parts` —— 按窄窗实测定（不让它把标题挤没）。
- 按班次 chip 的「缺失」视觉具体长相（红色描边 / 打叉）—— 走既有 danger 配方即可。
- 四个查询函数共享 `shiftNameOn` 的签名细节与扫描上界的实现方式。
- 迁移 SQL 的具体列名以 `build_runner` 生成的为准（`month_day` / `month_days` / `shift_names`）。
