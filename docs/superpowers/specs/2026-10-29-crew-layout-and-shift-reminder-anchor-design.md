# 班组卡排版收口 + 重复待办提醒的三档落点（设计）

- 日期：2026-10-29
- 起因：用户 v0.12.5 真机测试后的两条反馈（原话）：
  1. 「编辑排班里的班组设置，界面有点不太美观，或者说排版有点问题：① 班组名的编辑框有点太长。② 下边的周期起始日又长又矮，让人感觉不太好点到。」
  2. 「重复待办里，现在假如我上夜班，时间是晚上 8:30 到第二天早上 8:30，我想让它凌晨 0 点提醒我写台账。但是弄完之后，它竟然是在上班当天的凌晨 0 点提醒。像这块该怎么优化？」
- 用户拍板：
  - 重复待办「按班次」的提醒**接上班次闹钟那套完整的三档落点**（前一天 / 当天 / 次日），不是只修「钟点落在值班时间里」那一档。
  - 班组卡排版从三版候选（见 §2，已出工装图并排看过）里选 **方案 A**：输入框收窄 + 日期变成一条加高的整行值行。
- 影响版本：v0.12.6 测试版（`X.Y` 由用户定，AI 只动 `Z` 与 `build`）

---

## 1. 目标 / 非目标 / 反目标

**目标**

- 班组卡的「班组名」输入框不再占大半行；「周期起始日」那一行不再又长又矮、点起来发虚。
- 重复待办（「按班次」规则）的提醒时刻按**那天的班次值班窗口**落在前一天 / 当天 / 次日，与班次联动闹钟同一条判据、同一个实现。
- 待办列表那一行的时刻带上落点标记（「次日 00:00」/「前一天 23:00」），与闹钟列表、日历信息卡的说法一致。

**非目标**

- 不改班次联动闹钟的任何行为（这一轮是**调用**它，不是改它）。
- 不改「每天 / 每周 / 每月」三档重复规则的提醒时刻（它们没有班次上下文，照旧「发生日 + 钟点」）。
- 不改待办**发生日**（「当前这一次」仍然生成在上班那一天）；只改**提醒**落在哪天。
- 不改原生 Kotlin —— 时刻表仍在 Dart 侧算成绝对时刻，原生只弹队首、续队尾。
- 不做「按班次开始时间相对提醒」（用户 v0.12.3 明确不要）。
- 不动班组卡以外的编辑器版式。

**反目标**（做成了也算失败）

- 提醒落点与班次闹钟各写一份算式 —— 两份迟早对不上，症状是「闹钟标着次日、待办提醒却在当天」且不报错。
- 只改排定、不改显示 —— 待办行写着「00:00」，实际在次日 0 点响，等于把同一个误会从设置挪到了列表。
- 把「按班次」的发生日也挪到提醒那天 —— 待办属于那个班次，只应在班次日出现。
- 为了收窄输入框让班组名编辑在窄窗里变成一两个像素（收窄要有下限意识，见 §2）。
- 调整每一档落点时顺手「优化」`alarmDayAnchor` 的既有规则（24 小时值班、回绕式 `endMinute` 等都有护栏用例钉着）。

---

## 2. 班组卡排版（方案 A）

### 2.1 现状与问题

`_crewRow` 现在是两行：第一行 `Expanded(GlassField)` + 「设为我」芯片，输入框吃到约六成宽；第二行是一条 `Padding(vertical: spaceXs)` 的整行 —— 高约 38dp、整行可点但看着只有一行小字，用户读成「又长又矮」。

三版候选（一次性探针 `app/tool/probe/`，跑完即删，图在 `app/build/visual/probe/`）：

| 方案 | 输入框 | 周期起始日 | 结论 |
|---|---|---|---|
| A | 封顶（`Flexible` + `maxWidth: 180`，与 `Spacer` 各分剩余空间） | 44dp 整行值行：细分隔线 + 标签左 / 日期右 + 箭头 | **用户选它** |
| B | 同上 | 自然宽玻璃胶囊（40dp） | 卡内多一层玻璃阴影，在「我的班」浅紫底上偏抢眼 |
| C | 不动 | 同 B | 只修一半，输入框仍太长 |

### 2.2 采用的版式

第一行：

```dart
Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
  Flexible(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 180),
    child: GlassField(...现有 TextField...),
  )),
  const Spacer(),
  /* 现有「设为我 / 我的班」芯片，原样 */
])
```

- 实测效果（420dp 画布）：输入框约 **132dp**（`Flexible` 与 `Spacer` 各分剩余宽，封顶 180），芯片贴右缘。
- 窄窗下 `Flexible` 先缩：320dp 时输入框约 96dp、200dp 小窗约 36dp —— 小窗本来就有多处降级，这里不新增保护（既有用例只保证 320）。
- 为什么不用 `Expanded`：`Expanded` 是紧约束，会把 `ConstrainedBox` 的 180 上限顶掉。

第二行（周期 / 按月两种内容，**同一套几何**）：

```dart
const SizedBox(height: AppTokens.spaceSm),
Container(height: 1, color: outline.withValues(alpha: 0.7)),   // 细分隔线
GlassPressable(child: GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: () => _pickCrewStartDate(i),
  child: Padding(
    padding: EdgeInsets.symmetric(horizontal: AppTokens.gapHair, vertical: AppTokens.spaceMd),
    child: Row(children: [
      AppIcon(Icons.event_outlined, size: iconSm, color: muted),
      SizedBox(width: spaceSm),
      Text(L10n.crewCycleStart, style: AppTokens.rowPrimary),
      Spacer(),
      Text(L10n.yearMonthDay(_crewStartDate(i)), style: AppTokens.labelStrong),
      SizedBox(width: gapHair),
      AppIcon(Icons.chevron_right_outlined, key: Key('crew-start-chevron-$i'), size: iconSm, color: muted),
    ]),
  ),
))
```

- 行高 = 12 + 行盒 + 12 ≈ **44dp**，满足「好点到」；日期贴右缘，与全 app 的「标签—值—箭头」值行（`GlassValueRow` 一族）同一读法。
- **按月模式**（`_monthly`）照同一套几何：图标换 `format_list_numbered`，内容保留现有的整串 `L10n.crewSegmentStart(n)`（左对齐，不加右值），箭头 key 仍是 `crew-segment-chevron-$i`。
- 抽一个文件内的私有 `_crewValueRow({icon, label, value?, key, onTap})` 给两种模式共用，避免两处各写一份高度与间距。
- 键与文案全部保留（`crew-name-$i`、`crew-start-chevron-$i`、`crew-segment-chevron-$i`、`L10n.crewCycleStart`、`L10n.crewSegmentStart`），既有用例不用改断言。
- 班组卡以外的行（班组数 ±、撞班提示、说明文字）一个像素不动。

---

## 3. 重复待办提醒：三档落点

### 3.1 判据：直接复用 `alarmDayAnchor`

夜班 20:30–次日 08:30（回绕式存法 `start=1230, end=510`）下的落点：

| 提醒钟点 | 落点 | 依据（`alarmDayAnchor` 的档位） |
|---|---|---|
| 00:00 / 03:00 / 07:00 | **次日** | ① 钟点落在值班窗口内，跨过午夜 → 次日 |
| 23:00 / 19:00 | **当天** | ① 窗口内 / ③ 离当天更近（19:00 距上班 1.5h，次日 19:00 距下班 10.5h） |
| 10:00 | **次日** | ③ 次日 10:00 距下班 1.5h，当天 10:00 距上班 10.5h |
| 凌晨班 00:00–08:00 配 23:00 | **前一天** | ② 钟点晚于上班钟点 |
| 24 小时值班（span ≥ 1440） | **当天** | 既有例外，内置值班模板靠它维持原样 |

**不新写判据**：调用 `alarmDayAnchor(shift, ShiftAlarm(minute: clock))`，取出的 `AlarmDayAnchor` 只用来偏移日期。这样「闹钟落在哪天」与「待办提醒落在哪天」在结构上不可能分岔。

### 3.2 回调从「班次名」扩成「班次定义」

`recurring_todo.dart` 四个查询函数与 `upcomingFireTimes` 的参数：

```dart
// 旧：String? Function(DateTime day)? shiftNameOn
// 新：
ShiftClass? Function(DateTime day)? shiftOn
```

- `_matchesShift` 改成 `s.shiftNames.contains(on(day)?.name)` —— 匹配口径（按名字）**不变**，只是顺手多拿到整份定义。
- 全部调用点改成直接把 `chain.shiftOn` 传进去（签名相同，写法更短）：`app_repository.dart`（生成器）、`alarm_service.dart`（`planRecurringReminders` / `rescheduleAll` / `rescheduleTodoReminders`）、`recurring_panel.dart`、`recurring_series_editor.dart`、`schedule_screen.dart`，以及三个测试文件里的假 resolver。
- 领域层本来就 `import 'shift_rotation.dart'`，没有任何新依赖。

### 3.3 `upcomingFireTimes` 的两处实现细节（**这一节的坑最容易静默**）

**(a) 扫描窗口要从「前一天」起算。** 现状是：

```dart
var occ = occurrenceOnOrBefore(s, from) ?? firstOccurrenceOnOrAfter(s, from);
```

当落点是**次日**时，昨天那个班次的提醒可能还在未来：连续两个夜班日 D 与 D+1，D 的提醒落在 D+1 00:15；用户在 D+1 00:05 打开 App（重排）时，`occurrenceOnOrBefore(D+1)` 拿到的是 D+1 这一次，**D 那条还差 10 分钟的提醒被漏掉**。所以「按班次」规则从 `from − 1 天` 起算（提前的那个 occurrence 的提醒若已过去，会被 `!fire.isBefore(from)` 自然筛掉）：

```dart
final start = s.repeat == RecurRepeat.shift ? _addDays(dateOnly(from), -1) : from;
```

（与 v0.11.2 `planShiftAlarms` 窗口「从昨天起算」是同一条教训：落点可以落在 occurrence 之外时，窗口必须多罩一天。）

**(b) 相邻两次可能落成同一个时刻、也可能**倒序**，必须整表排序后再按相邻去重。**

- 相等的情形：D 是夜班（00:15 → 次日 D+1 00:15），D+1 是白班（00:15 → 当天 D+1 00:15）。
- **倒序的情形（独立审查给出的反例，前提「序列非递减」不成立）**：同一条系列同时选了 20:30–08:30 的夜班与 00:00–06:00 的零点班，都配 07:00 —— D 是夜班 → `next`（D+1 07:00）；D+1 是零点班 → `prev`（D 07:00）。相邻两次的触发时刻差一整天、方向是倒退。
- 后果不是「不整齐」：原生 `AlarmScheduler.nextPending` 只弹队首、之后按 `indexOfFirst { it > now }` 续队尾 —— **排在队首之后、时刻却更早的那一条永远不会被排上**，静默不响。
- 所以改为：**收集全部候选（只筛 `!fire.isBefore(from)`，不提前 `break` 地平线）→ 排序 → 与上一条相等则跳过 → 再裁地平线（`fire.isAfter(horizon)` 丢弃）→ 取前 `cap` 条**。循环的终止条件改成「occurrence 已超出 `from + days + 1`」（落点最多偏一天）。

```dart
final candidates = <DateTime>[];
... for each occ (occ 不超出 from + days + 1):
      final fire = _fireAt(...);
      if (!fire.isBefore(from)) candidates.add(fire);
candidates.sort();
final out = <DateTime>[];
for (final f in candidates) {
  if (f.isAfter(horizon)) break;          // 已排序，可以 break
  if (out.isEmpty || f != out.last) out.add(f);
  if (out.length >= cap) break;
}
```

回归用例：上面那组「夜/零混选」必须排成升序，且两次提醒都在结果里。

### 3.4 提前提醒与落点的次序

**先定落点，再减提前量**：`fire = DateTime(occ + delta 天) + (clock − advance)`。00:00 + 提前 5 分钟 → 次日 00:00 减 5 分钟 = 当天 23:55（仍在夜班里）；若先减再定落点，00:00 会先变成 23:55、再按 23:55 落到当天，提醒会跑到上班前 —— 判据必须作用在**用户设的钟点**上。

### 3.5 其它规则不变

- 每天 / 每周 / 每月：`delta = 0`，行为逐字不变（不传班次，`_fireAt` 走原来的算式）。
- **「全天提醒」（`timeMinute == null`）：不做落点，`delta = 0`，留在发生日。** 这一类排定时用的钟点（`allDayReminderHour` = 9:00）是**我们的策略值、不是用户选的时刻** —— 拿它去套值班窗口会改变一整类待办的真实响铃时刻（零点班 00:00–06:00 的 09:00 会按规则 ② 落到**前一天** 09:00，比待办行出现还早 15 小时），而界面上不显示时刻、用户没有任何线索。落点只作用于**用户明确设了钟点**的系列。
- 落点不影响**发生日**：待办行仍生成在上班那天，`advanceRecurringTodos` / `skipThrough` / 拒收跨系列等逻辑一概不动。

---

## 4. 界面上的说法

### 4.1 待办列表行：带落点的时刻

`_eventTile` 的副标题现在是 `[月日周几, HH:mm, 提醒档位]`。第二格改成：

- 条件（**全部满足才标，否则老老实实显示原钟点**）：
  1. `e.seriesId != null` 且能查到系列；
  2. `series.repeat == RecurRepeat.shift`；
  3. `series.timeMinute != null`，且 **`e.timeMinute == series.timeMinute`** —— 排定用的是系列那份钟点、这一格印的是行里的那份，两份不一致（脏数据）时宁可不标，也不让标签与真正响的时刻各说各话；
  4. `chain?.shiftOn(e.date)` 非空，且 **`series.shiftNames.contains(shift.name)`** —— 改排班后生成器「只往前不回退」，会留下发生在今天、而今天已不是这条系列所选班次的旧行；那种行排定侧**根本不会排提醒**，标一个从无关班次算出来的落点就是显示侧的静默分岔（独立审查指出）。
- 按上述条件取 `AlarmDayAnchor`：`prev → L10n.clockPrevDay(clock)`、`next → L10n.clockNextDay(clock)`、`same → clock`。
- 复用既有的 `L10n.clockPrevDay/clockNextDay`（闹钟列表与日历信息卡用的就是它们），中文「次日 00:00」、英文「00:00 (next day)」。
- 落点标记的是**提醒钟点**，不是待办自身的日子；提前档位（`提醒档位` 那一格）照旧跟在后面，二者组合读起来是「次日 00:00 · 提前 5 分钟」。

**数据从哪来**（现在这一页没有系列与链）：

- `app_repository.dart` 新增 `recurringSeriesProvider`（`StreamProvider<List<RecurringTodo>>`，watch `recurringSeriesRows` 表并 `toDomain()`）—— 与 `eventsProvider` 同一套路；系列被编辑 / 开关 / 删除时列表自动跟上，不用逐个调用点 `invalidate`。
- `ScheduleScreen.build` 加 `ref.watch(activeScheduleProvider)` 与 `recurringSeriesProvider`，在 build 里建 `Map<int, RecurringTodo>` 与 `chain` 传给 `_eventTile`。
- 判据抽成一个纯函数放在 `domain/recurring_todo.dart`（或 `day_summary.dart`）：

  ```dart
  /// 待办提醒的钟点落点文案：null = 不标（非按班次 / 没有班次 / 没设时间）。
  String? todoClockLabel({
    required int clockMinute,
    required ShiftClass? shift,
  }) => shift == null ? null : switch (alarmDayAnchor(shift, ShiftAlarm(minute: clockMinute))) {...};
  ```

  纯函数可单测，界面只做拼装。

**为什么标在列表行、不标在系列编辑器/面板**：编辑器里同时可能选中几个窗口不同的班次，写死「次日」会是谎话；列表行上每一天的班次是确定的，那里标得准。面板的「下次 X」指的是待办的**发生日**，本来就没错，不动。

### 4.2 系列编辑器的说明

「按班次」那一档下面已有两行小字（匹配口径 hint + 缺名提示）。在 `shiftRuleHint` 之后补一句 `L10n.shiftAnchorHint`：

> 提醒落在班次值班时间里时按那天的班次算（跨午夜的班次会落在次日）。

只在这一档显示（与 `shiftRuleHint` 同一段条件），窄窗折行由既有 `microText` + 字宽兜底，`text_fit_guard` 会盯着。

### 4.3 帮助

`help_content.dart` 的「按班次」FAQ 补一句：「提醒时刻落在班次的值班时间里（比如夜班的凌晨 0 点），会按值班时间排在**次日**；钟点不在值班时间里时，按离上班 / 下班哪边近来定。」

---

## 5. 测试与工装

**纯函数 / 领域层**

- `recurring_todo_test.dart`：
  - 夜班 20:30–次日 08:30 下 00:00 / 03:00 / 07:00 → 次日；19:00 / 23:00 → 当天；10:00 → 次日；
  - 零点班（00:00–08:00）23:00 → 前一天；
  - 24 小时值班 → 当天；
  - 每天 / 每周规则即使那天有夜班也**不带落点**（`delta = 0`）；
  - 提前 5 分钟：00:00 → 次日 00:00 再减 5 → 当天 23:55；
  - **(a)** `from` = D+1 00:05（D 与 D+1 都是夜班）时，D 的提醒（D+1 00:15）仍在结果里；
  - **(b)** 夜班次日接白班：两次落成同一时刻时只排一条；
  - **(c)** 夜班 + 零点班混选、都配 07:00：结果**升序**、两条都在（评审给出的倒序反例）；
  - **(d)** 全天提醒（`timeMinute == null`）在按班次规则下仍是发生日当天、不套落点。
- `recurring_alarm_plan_test.dart`：按班次系列 + 假 resolver 的时刻表包含落点偏移。
- 反向验证：把 `_fireAt` 的 delta 去掉 → 夜班 00:00 与 (a)(b) 用例红；把窗口从 `from-1` 改回 `from` → (a) 红。

**界面**

- 待办列表：库里有「按班次 · 夜班 · 00:00 提醒」的系列且有当前 occurrence → 副标题含「次日 00:00」；同样一条用每天规则则不标（反向验证：条件去掉 `repeat == shift` → 第二条红）。
- 待办列表：改排班后留下的旧行（今天的班次不在该系列的 `shiftNames` 里）**不标**落点；系列钟点与行钟点不一致的脏数据同样不标（反向验证：去掉名字包含判断 → 旧行那条红）。
- 按月的班组卡：仍是「从第 N 段开始」，箭头键仍在（`monthly_schedule_editor_test` 现有断言不变）。
- 320dp 班组卡展开不溢出（现有用例）。
- `schedule_editor_test` 新增一条几何断言：周期起始日那一行的可点高度 ≥ 44dp（`tester.getSize` 命中容器），把「好点到」钉成数字。

**工装**

- `67_editor_crew_expanded` 重出，浅 / 深 / 英 / 小窗 / 横屏各档看一眼（输入框宽度、分隔线、44dp 行）。
- `24_todos_recurring` / `25_recurring_panel` 的种子补一条「按班次 · 夜班 · 00:00」系列（`seedRecurringTodo` 里加），让「次日 00:00」在图上**有眼睛看着**。
- `text_fit_guard` 覆盖新提示行与新副标题。

**真机**

- 用户的夜班 20:30–08:30 + 00:00 台账：新建后 `dumpsys alarm` 里该条提醒的时刻是**次日 00:00**；
- 待办列表行显示「次日 00:00」；班组卡新版式在真机上看一眼间距与手感。

**验收标准**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿（只增不减）；工装全过；修复前后对照图归入交付说明。

---

## 6. 版本与发布

- `0.12.5+180` → **`0.12.6+181`**（测试版，beta 分支）。
- 更新日志 prepend 一条、窗口保持 10 条；`app_info.dart` 同步；AGENTS.md 版本史与「最近改动」补一条。
- 收尾按既有流程：`flutter analyze` / `flutter test` / 工装 → 构建 APK → 提交推送 → `scripts/release.ps1` → curl `latest.json` 核对。

---

## 7. 留给构建者的

- 班组卡那个文件内私有 `_crewValueRow` 的参数形状（图标、标签、可选值、键、回调），按两种模式共用的最小面来定。
- `recurringSeriesProvider` 放在 `app_repository.dart` 的 providers 区，具体用 `watch()` 还是 `watchSingle` 风格的映射实现，按 drift 生成的 API 写。
- `todoClockLabel` 放 `recurring_todo.dart` 还是 `day_summary.dart`（两处都不引 Flutter；建议 `recurring_todo.dart`，因为它的输入全是这一套类型）。
- 帮助文本的措辞长度 —— 按 `help_content` 既有条目的长度对齐。
