# 多排班表按日期衔接 · 设计规格

> 2026-09-29 头脑风暴定稿。**目标版本由用户拍板**（末位 `Z` 归 AI，`X.Y` 归用户）。

## 1. 背景与目标

用户反馈：**「有的用户他有好几个排班表，这排班表都不一样，需要衔接起来。就是说，第一个排班表它的生效时间是从几号到几号，第二个排班表它是从几号到几号，或者一直持续下去。现在我们不是每次只能有一个排班表存在吗？它默认就是永久的。」**

现状：`ShiftScheduleRows.isCurrent` 是**单选的**，全 app 的所有界面（日历、底栏信息卡、闹钟重排、桌面小组件）都只读这一套，而且它管**所有日子** —— 换班组、换项目部、换倒班方式之后，翻回历史看到的全是新班表的班。

**目标**：每套方案可带一个**生效时段**（起 / 止，都可留空），日历、闹钟、桌面小组件**按天**取「那天归哪套」，翻历史看到的是当时的班。

**成功标准**：
- 设两套方案各带时段之后，日历上**跨过边界**那一个月里，边界前的格子是旧班表、边界后的是新班表；翻回更早的月份看到的还是当时那套；闹钟与桌面小组件跟着换（同一天不会两套打架）。
- 没设过时段的用户**行为一字不变**（升级后当天看到的东西与升级前一模一样）。
- 在界面上能一眼看出每套方案实际管哪些日子。

## 2. 已定决策（2026-09-29 拍板）

① **语义 = 按天解析**：每套方案带生效时段，日历 / 闹钟 / 小组件按天取「那天归哪套」。**不是**「到点自动切换当前方案」—— 那个更省事，但翻历史会显示错的班（已否掉）。

② **解析规则 = 时段优先，当前方案兜底**：
   1. 在**设了时段**的方案里，挑**覆盖那天、且起点最晚**的那一套（起点为空的按「一直往前」算，也就是**最不晚**的；起点并列时取列表里靠后的那条，即后建的那套赢）；
   2. 一套都没覆盖那天 → 用**当前方案**（`isCurrent`，就是日历顶栏「切换」换的那套）。
   **「设了时段」= `effectiveFrom` 与 `effectiveTo` 至少有一个非空**；两个都空的方案不参与衔接（只能靠 `isCurrent` 兜底那条路出现）。

③ **入口 = 设在编辑器里**：时段是方案的属性，排在排班编辑器里；日历顶栏那个「切换排班」弹窗升级成**时段视图**（每行显示该方案实际管哪些日子，当前那套标「其余日子」）。

## 3. 为什么这条规则能零风险迁移

`effectiveFrom` / `effectiveTo` 两列**都可空**，语义是「留空 = 不限」与「留空 = 一直持续」。迁移只加两列、**不改任何一行数据**：

- 老库里每套方案两列都是 null → 按 ② 第 1 条，`spans` 为空 → 全都落到第 2 条 → 行为与今天**一字不差**；
- 用户设一条时段 → 那套立刻参与衔接，其余日子仍归当前方案。

代价是规则多一句「当前方案兜底」。这一句由界面负责讲清楚：**切换弹窗里当前那套标「其余日子」，没设时段的非当前方案标「未参与衔接」** —— 用户看一眼就明白当前方案管的是「剩下的」。

## 4. 数据模型（schemaVersion 11 → 12）

### 4.1 `ShiftScheduleRows` 加两列

```dart
/// 生效时段起点（**闭区间**，纯日期，`dateOnly` 口径）；null = 不限起点。
DateTimeColumn get effectiveFrom => dateTime().nullable()();

/// 生效时段终点（**闭区间**，纯日期）；null = 一直持续下去。
DateTimeColumn get effectiveTo => dateTime().nullable()();
```

闭区间是有意的：界面上写「2026年1月1日 ～ 6月30日」时，用户理解的就是**这半年都归它**。相邻两段因此是 `A: ～6/30` + `B: 7/1～`，不重叠。

### 4.2 迁移

```dart
if (from < 12) {
  // 多排班表按日期衔接：两列都可空，老行自动是 null（= 不参与衔接），
  // 于是老库的所见行为一字不变。**不改任何既有行。**
  await m.addColumn(shiftScheduleRows, shiftScheduleRows.effectiveFrom);
  await m.addColumn(shiftScheduleRows, shiftScheduleRows.effectiveTo);
}
```

**必须补 `migration_v11_to_v12_test.dart`**：老方案的行数与两个新列（null）原样、能写能读、`isCurrent` 不变。

⚠️ 与上一轮（v10→v11）不同，这次**不用给更早的迁移 fixture 补 DDL**：那两列加在 `shift_schedule_rows` 上，而这张表从 v1 就存在，每个 fixture 都建过它 —— `ALTER TABLE` 找得到表。**但要在实施时验证一遍**（跑一遍全套迁移测试即可；真红起来再补）。

## 5. 领域层

### 5.1 一个查询面接口（`domain/shift_rotation.dart`）

```dart
/// 「某天什么班」的**唯一**查询面 —— 日历、闹钟、小组件都只依赖它。
///
/// 抽出来是为了让「单套方案」与「按天衔接的多套方案」在调用点无法区分：
/// `planShiftAlarms` / `AlarmService.reschedule` 今天收的是 `ShiftSchedule`，
/// 改成收这个接口之后，传哪一边都对。
abstract class ShiftSource {
  ShiftClass? shiftOn(DateTime date);
}
```

`ShiftSchedule implements ShiftSource`（它本来就有这个方法，加个 implements 即可，零实现改动）。

### 5.2 新文件 `domain/schedule_chain.dart`（纯 Dart，可直接单测）

```dart
/// 一套方案 + 它的生效时段（闭区间；两端都可留空）。
class ScheduleSpan {
  const ScheduleSpan({this.id, required this.schedule, this.from, this.to});

  /// `shift_schedule_rows.id` —— 界面用来跳编辑器 / 删除。
  final int? id;
  final ShiftSchedule schedule;

  /// null = 不限起点（一直往前）。
  final DateTime? from;

  /// null = 一直持续下去。
  final DateTime? to;

  bool covers(DateTime day);
}
```

```dart
/// 「某天归哪套方案」的**唯一**解析处。
///
/// 规则（spec §2 ②，全 app 只有这一份实现）：
///   1. [spans] 里挑「覆盖那天、且起点最晚」的那一条；起点并列时取**列表靠后**的
///      那一条（装配时按 `(from 升序, id 升序)` 排好，于是「后建的那套赢」）。
///   2. 一条都没有 → [fallback]。
///
/// **日期比较一律走 `dayNumber`**：`from`/`to` 由 drift 读回来是**本地** DateTime，
/// 而调用方传进来的日子可能是 UTC 纯日期 —— 直接比 `DateTime` 在东八区就差 8 小时。
class ScheduleChain implements ShiftSource {
  const ScheduleChain({this.spans = const [], this.fallback});

  final List<ScheduleSpan> spans;

  /// 当前方案（`isCurrent`）。管所有没被时段覆盖的日子 —— 老库全靠它。
  final ShiftSchedule? fallback;

  ShiftSchedule? scheduleOn(DateTime day) { ... }

  @override
  ShiftClass? shiftOn(DateTime day) => scheduleOn(day)?.shiftOn(day);

  /// 这个月里有没有被**按天改班**调过的日子（信息卡定高要用）。
  bool monthHasOverrideHint(DateTime month) { ... }
}
```

**`monthHasOverrideHint` 为什么放这儿**：日历那一处原来是 `schedule.dayOverrides.keys.any(...)`，而现在「那天归哪套」是 chain 才知道的事 —— 留在页面里会变成一段手写的逐天循环，与解析规则分家。放进来还能直接单测。

### 5.3 时段重叠的判定（同文件，纯函数）

```dart
/// [self] 之外的、与它时段重叠的那些方案（按 id 升序）。
///
/// 重叠**不是错误**：解析规则按「起点最晚的赢」有确定答案（spec §2 ②）。这条只
/// 服务于界面上那句提醒 —— 用户设完时段要有机会知道「这个月和另一套撞上了」。
List<ScheduleSpan> overlappingSpans(List<ScheduleSpan> all, ScheduleSpan self);
```

留空端的重叠判定：`from == null` 视作极小、`to == null` 视作极大，两段 `[from, to]` 闭区间相交即重叠（**恰好首尾相接不算重叠**：`A.to + 1 天 == B.from` 是正常的衔接）。

## 6. 装配与 provider

### 6.1 新类型 `ActiveSchedules`（`app_repository.dart`）

```dart
/// 时间线上的全部方案，已装配成领域模型。
class ActiveSchedules {
  const ActiveSchedules({required this.all, required this.chain});

  /// 全部方案（按 id 升序），每项都是装配好的单套 [ActiveSchedule]。
  /// 编辑器 / 管理页 / 切换弹窗用。
  final List<ActiveSchedule> all;

  /// 按天解析面。日历 / 闹钟 / 桌面小组件用。
  final ScheduleChain chain;

  /// 当前方案（`isCurrent`）。找不到返回 null。
  ActiveSchedule? get current;

  /// 当前方案的领域模型。
  ShiftSchedule? get currentDomain => current?.toDomain();
}
```

`ActiveSchedule`（单套装配体）**一行不改**。

### 6.2 `watchActiveSchedule()` 加宽

今天的实现只 `watch` `isCurrent` 那一行（`schedQuery.watchSingleOrNull()`），所以要装配多套就得改成 **watch 整张表**：

```dart
final triggers = <Stream<Object?>>[
  select(shiftScheduleRows).watch(),   // ← 从「只盯当前行」改成整表
  select(shiftDayOverrides).watch(),
  select(shiftClassAlarms).watch(),
];
```

装配时对**每一套**方案各调一次现成的 `_loadChildren(row)`（它按 `scheduleId` 过滤，天然是单套的），再拼出 `chain`：

```dart
final chain = ScheduleChain(
  // 参与衔接的 = 设了任一端时段的那些；**没设时段的不参与**（spec §2 ②）。
  spans: [
    for (final a in all)
      if (a.schedule.effectiveFrom != null || a.schedule.effectiveTo != null)
        ScheduleSpan(id: a.schedule.id, schedule: a.toDomain(),
            from: a.schedule.effectiveFrom, to: a.schedule.effectiveTo),
  ]..sort(/* (from 升序, id 升序)，from 为 null 排最前 */),
  fallback: current?.toDomain(),
);
```

**成本**：方案通常 1~3 套，每套的班次/周期/覆盖/闹钟都是小表。整表 watch 让「任何一套动了」都重发这条流 —— 那正是想要的（改历史那套的班次，桌面小组件要跟着变）。重发会触发一次闹钟重排与一次快照推送，两者都是幂等的。

### 6.3 provier 名不动

`activeScheduleProvider` **保留名字**（它就是「当前排班状态」这条流），值类型从 `ActiveSchedule?` 换成 `ActiveSchedules?`。调用点要改的是**取值方式**：

| 站点 | 原来 | 改成 |
|---|---|---|
| `home_shell._pushWidgetSnapshot` | `.value?.toDomain()` | `.value?.chain` |
| `home_shell._tryStartupReschedule` | `.valueOrNull?.toDomain()` | `.valueOrNull?.chain` |
| `alarm_screen` | `.valueOrNull?.toDomain()` | `.valueOrNull?.chain` |
| `calendar_screen` | `.valueOrNull?.toDomain()` | `.valueOrNull?.chain` + `.valueOrNull?.all` |
| `schedule_editor_screen:127` | `active?.toDomain()` | `active?.currentDomain` |
| `schedule_editor_screen:1640` / `management:24` / `calendar:791` | `current?.schedule.id` | `schedules.currentScheduleId` |

最后一行那三处都是「当前方案的行 id」，各写一遍 `current?.schedule.id` 迟早写歪 —— 在 `ActiveSchedules` 上封一个 `int? get currentScheduleId`。

**编辑器不用改行为**：`_save()` 已经是 `makeCurrent: widget.scheduleId == null`（只有新建才接管当前）+ 保存后 `AlarmService.rescheduleAll(repo)`。所以「改了时段」这条路径**天然跟着重排闹钟** —— 时段一改，某些天的班就变了，闹钟必须跟着变，这正是要的。

## 7. 消费者改造清单

**原生侧一个字都不用改**：闹钟与小组件在 Dart 侧本来就是**逐天遍历**（`planShiftAlarms` 的 `for d in 0..days`、`buildWidgetSnapshot` 的 `for i in 0..dayCount`），换一个「按天回答」的源进去即可。`WidgetRenderer.kt` / `AlarmScheduler.kt` 不动。

**一条容易被误报成 bug 的既有语义**：班次闹钟可能落在**前一天**（`alarmFallsOnPreviousDay`，零点班 00:00 上班 + 23:00 响铃 → 排在前一天晚上）。跨时段边界时，这条闹钟会落在**前一天所属那套方案**的日子里 —— 那是**对的**：闹钟属于那个班次，不属于那一天。落哪天由 `shiftAlarmFireAt(date, shift, alarm)` 里**班次自己的日期**决定，与「那天归哪套」无关。别把它「修」成按触发日解析。

| 站点 | 现在 | 改成 |
|---|---|---|
| 日历网格 `schedule?.shiftOn(date)` | 单套 | `chain.shiftOn(date)` |
| 信息卡班次行 `schedule?.shiftOn(_selected)` | 单套 | `chain.shiftOn(_selected)` |
| 信息卡「其他班组」`schedule.teamShift(i, date)` | 单套 | `chain.scheduleOn(date)?.teamShift(i, date)` |
| 信息卡「本月统计」`_monthTally` | 按 `classes` 下标计数 | **按 `shortLabel` 累加**（见 §7.1） |
| `_monthHasOverrideHint` | `schedule.dayOverrides.keys` | `chain.monthHasOverrideHint(_month)` |
| 「调整班次」可点判定 / `canPick` | `schedule.classes.isNotEmpty` | 「起点那天所属方案」的 classes（见 §7.2） |
| 闹钟 `planShiftAlarms(schedule, …)` | `ShiftSchedule` | `ShiftSource`（收 `chain`） |
| 闹钟页「未来 30 天」 | `schedule.shiftOn(date)` | `chain.shiftOn(date)` |
| 小组件 `buildWidgetSnapshot(schedule:)` | `ShiftSchedule?` | `ScheduleChain?`（逐天 + 今日卡按 `scheduleOn(today)`） |
| 信息卡量高 `measureBottomInfoCardHeight(schedule:)` | `ShiftSchedule?` | `ScheduleChain?`（逐日那一段里改问 `scheduleOn(day)`） |

### 7.1 「本月统计」为什么改成按简称累加

那一行现在是「本月 早12 · 午8 · 夜8 · 休6」，按 `classes` 下标计数。跨方案的一个月里两套方案的班次定义不同，按下标数会把两套的班次**按位置混在一起**（A 的第 0 个班次和 B 的第 0 个班次被算成同一个）—— 数字会错得看不出来。

改成**按 `shortLabel` 累加**：跨方案时同名的「休」合并成一个数（本来就该合），「早」「夜」各归各的。一行放得下、口径也对。**只影响跨方案的那个月**，单套方案下逐字与今天相同。

### 7.2 「调整班次」跨时段边界

长按拖选一段日子，这段可能横跨两套方案的边界。**拦住**，不开选择层，直接给一行说明：

> 这段跨了两套排班的生效边界（X月X日起换成「B」），请分开调整。

理由（与「不跨月拖选」同一条）：选择层列的是**某一套的班次定义**，而覆盖表 `{scheduleId, day}` 是按天归属的 —— 放过去只能得到「列了 A 的班次、却只对 A 的日子生效」这种**静默半生效**，正是最难查的那类 bug。拦住是不让用户走进那个状态，代价只是一句话。

### 7.3 「按天改班」覆盖在时段变化后的沉没

覆盖记在 `{scheduleId, day}` 下，那天归谁就查谁的覆盖。把 B 插到中间之后，原来记在 A 名下的那几天**不再生效**（那天整天的班都换了）—— 这是**正确**语义，与既有的「切到别的方案时这套覆盖不生效」完全一致，**不做提示**。

## 8. 界面

### 8.1 排班编辑器：新增「生效时段」一节

排在「周期设置」之后（它是方案的元信息，不是班次配置）。两行：

```
生效时段
  从    2026年1月1日            ✕
  到    一直持续                ✕
```

- 两行都是可点区域，走现成的 `showGlassDatePicker`；未设时显示灰字（从 = 「不限」、到 = 「一直持续」）。
- 右侧一个清除钮（`✕`，只在设了值时出现）—— 把时段清回「不限 / 一直持续」。
- **校验**：`from` 晚于 `to` 时**保存前打回**并给一句说明（`L10n.effectiveRangeInvalid`）。两侧同一天是合法的（只那一天）。
- 保存：`saveSchedule` 加两个可空参数。**注意可空字段的落库必须显式写 `Value(x)`，不能用 `Value.absent()`** —— 后者在「把设好的时段清回不限」这条路径上会静默保留旧值（`ShiftClass` 那条老坑的同一条）。

保存成功后，若与别的方案时段重叠，附一句提示：

> 与「B」的时段重叠，重叠的日子按**开始更晚**的那套算。

（判定走 §5.3 的纯函数；不阻塞保存 —— 重叠有确定答案，只是要让用户知道。）

### 8.2 日历顶栏「切换排班」弹窗 → 时段视图

弹窗、行、选中样式都不动，**副标题**从「N 个班组」改成「时段标签 · N 个班组」：

| 情形 | 标签 |
|---|---|
| 设了两端 | `2026年1月1日 ～ 6月30日` |
| 只设起点 | `2026年7月1日起` |
| 只设终点 | `到 2026年6月30日` |
| 没设时段，且是当前方案 | `其余日子` |
| 没设时段，且不是当前 | `未参与衔接` |

弹窗顶部（标题下）加一行说明：**「没被上面时段覆盖的日子，用标着「其余日子」的那套。」** —— 这一句是把 §2 ② 讲给用户听的唯一一处。

### 8.3 排班管理页

每行副标题在现有的「N 个班组 · 锚点日」后面接上时段标签（同一套格式）。当前标记不变。

### 8.4 日历上不画时段边界

信息卡不加「从这天起换成 X」的徽章 —— 它会牵动 `info_card_metrics` 的定高（多一项要按月预留），而用户要看时段去切换弹窗看就行。写进 §9 明确不做。

## 9. 明确不做

- **独立的「排班时段」时间线页面**（已选「设在编辑器里 + 切换弹窗显示时段」）。
- **自动截断相邻时段**：往中间插一套时**不动**别的方案的时段（不替用户改设置）。重叠由「起点最晚的赢」解析，界面提示。
- **日历上画时段边界**（见 §8.4）。
- **时段的重叠警告弹窗 / 冲突阻止**：只给一句 snack，不拦。
- **时段的「每几周」「例外日」之类**：时段就是两个日期。
- **给时段加「生效中的方案名」徽章到日历格子**：格子已经很挤。
- **改 `ShiftAlarmOverrides`（按天关闹钟）**：它是全局的（只有 `day` 一个主键），跨方案仍成立，不动。
- **模板带时段**：模板存的是**结构**（班次 + 周期 + 错位），时段是实例属性，不进模板。
- **原生侧改动**：一个字不改（§7）。

## 10. 文案（`lib/core/l10n.dart`）

`effectivePeriod`（生效时段）/ `effectiveFrom`（从）/ `effectiveTo`（到）/ `effectiveUnbounded`（不限）/ `effectiveForever`（一直持续）/ `effectiveRangeInvalid`（开始日期晚于结束日期）/ `effectiveRangeSpan(from, to)` / `effectiveFromDate(d)`（X日起）/ `effectiveUntilDate(d)`（到 X日）/ `effectiveRemaining`（其余日子）/ `effectiveNotChained`（未参与衔接）/ `effectiveOutsideHint`（没被上面时段覆盖的日子，用标着「其余日子」的那套）/ `overlappingSpan(name)`（与「X」的时段重叠…）/ `spansTwoSchedules(name)`（这段跨了两套排班的生效边界…）。

**日期串一律复用现成的 `L10n.monthDay` / `L10n.monthDayWeekday`**，不新造格式化。

## 11. 测试

**纯函数**（`schedule_chain_test.dart`）：
- `covers`：闭区间两端**都算覆盖**（`to` 那天算、`to + 1` 不算）；`from` 空 = 不限起点；`to` 空 = 一直持续；两端都空**不参与衔接**（那是 `fallback` 的活）。
- 解析：单段 → 就是它；两段不重叠 → 各归各；两段重叠 → **起点晚的赢**；起点并列 → 列表靠后的赢；没有段覆盖 → `fallback`；`fallback` 也是 null → null。
- `shiftOn`：跨边界那两天各返回**各自方案的班次**（用两套名称不同的方案钉住）。
- `monthHasOverrideHint`：只有 A 有覆盖、而这个月只归 B → false；归 A 的那天在这个月 → true。
- 重叠判定：首尾相接**不算**重叠（`A.to + 1 == B.from`）；留空端按无穷处理。

**迁移**（`migration_v11_to_v12_test.dart`）：老方案的行数、`isCurrent`、两列为 null 原样保留；能写能读（种一个带时段的、一个不带的，读回来各自对）。照惯例**跑一遍全套既有迁移测试**确认没被 `addColumn` 带崩。

**仓库**（`schedule_chain_repository_test.dart`）：
- 只有一套方案（今天的样子）→ `chain.spans` 为空、`scheduleOn(任意一天)` 都是它 —— **这是「老库行为一字不变」的回归测试**。
- 两套带时段 → `scheduleOn(边界前后)` 各归各的。
- `scheduleOn` 与「那天归 A」的 `dayOverrides` 一起用：把 A 的覆盖写在归 A 的那天 → 生效；写在归 B 的那天 → 不生效。
- **流重发**：改非当前方案的时段 → `watchActiveSchedule()` 重发（漏了watch 整表就是「改完不动」，与当年「覆盖表没挂 watch」是同一条）。

**闹钟**（`alarm_plan_test.dart` 补）：60 天窗口跨边界 → 边界前的日子按 A 的班次与闹钟时刻排、边界后的按 B 排；**id 不撞**（同一天只归一套，`序号 × 天数窗口 + 偏移` 天然错开）。

**小组件**（`widget_snapshot_test.dart` 补）：窗口跨边界 → `days[]` 里边界前是 A 的班次名/色、边界后是 B 的；今日卡的 `crews` 与 `adjusted` 取**今天所属方案**。

**界面**（`calendar_chain_test.dart`）：跨边界那个月里点边界前那格与边界后那格，信息卡的班次名不同；「本月统计」跨方案时按简称合并（数一数总天数等于月长）；拖选跨边界被拦住并给出说明。

**守门**：`design_tokens_test` / `haptics_guard_test` 照旧。新界面只许用现成令牌与共享组件；时段两行是可点区域 → 走 `GlassPressable`，**不补触觉**（日期选择器提交点自己会发 `select()`，见 `haptics.dart` 那份名单）。

**视觉工装**（`visual_screens.dart` + 出图）：新增种子（两套方案各带时段、边界落在**本月中间**）与三屏 —— ① 日历跨边界那个月；② 「切换排班」弹窗（时段标签五种形态各出现一次）；③ 编辑器的「生效时段」一节（含设了值与全留空两种）。**看图上要能直接看出边界前后的班次不一样** —— 这是本轮唯一会「看」的眼睛。

## 12. 收尾（照 `AGENTS.md`）

- `PRODUCT_SPEC.md`：排班那一节 + 数据模型表（schemaVersion 11 → 12）+ 迁移行。
- `AGENTS.md`：版本史、「最近改动」、Drift 表清单与 schemaVersion、「关键决策与坑」补三条（**解析规则只有一处** / **没设时段不参与衔接是零迁移风险的关键** / **`ShiftSource` 让单套与多套在调用点无法区分**）。
- `README.md` 的功能清单在下一个正式版那一轮统一核（测试版不动）。
- 发布说明写到 `tools/gh/release-notes-vX.Y.Z.md`。

## 13. 风险与坑（实施时挨个对照）

1. **日期比较一律走 `dayNumber`**：`effectiveFrom` / `effectiveTo` 由 drift 读回来是本地 DateTime，调用方传进来的可能是 UTC 纯日期 —— 直接比 `DateTime` 在东八区差 8 小时，`covers` 会在边界那天静默判错。**这是本功能最可能出错的一处**（`skipThrough` 那条同款坑的第二次）。
2. **`watchActiveSchedule()` 必须 watch 整张 `shift_schedule_rows`**：还盯 `schedQuery.watchSingleOrNull()` 的话，改**非当前**方案的时段/班次**不会重发**这条流 —— 日历、闹钟、小组件全都不动，不报错。与当年「覆盖表没挂 watch」完全同一条。
3. **`ShiftScheduleRowsCompanion` 里写可空列必须显式 `Value(x)`**：`Value.absent()` 在「把时段清回不限」这条路径上会静默保留旧值。
4. **`ActiveSchedules` 聚合对象与 `ActiveSchedule`（单套）是两个类型**，别把单套那个改坏 —— 编辑器 / 管理页 / 模板都依赖它。
5. **`planShiftAlarms` 的入参类型改成 `ShiftSource`**，`AlarmService.reschedule` 的第一参数跟着改；`reschedule` 里用作日志的 `schedule.name` 要换（`ShiftSource` 没有 name）。
6. **`measureBottomInfoCardHeight` 的「逐日取大」多了一个轴**：`showChips`（`teamCount > 1`）现在**逐日不同** —— 一个月里可能有的天有「其他班组」行、有的天没有。原来它是循环外的固定项，要挪进逐日的循环里（或按月取大）。
7. **闹钟页「未来 30 天」也要换成 chain**：30 天内跨边界比 60 天更常见，漏了就是「日历上换了、闹钟页没换」。
8. **测试里的定时器**：`watchActiveSchedule` 从单行 watch 变整表 watch，取消时机可能变 —— 若出现「A Timer is still pending」，照 `calendar_screen_test.dart` 的 `_disposeCalendar` 主动拆树。
9. **时段为空串的写法别混**：「不参与衔接」是**两端都 null**；「不限起点」是**只有 `to` 有值**；「一直持续」是**只有 `from` 有值**。三种状态在 §8.2 的标签里各有各的说法，别合并。
