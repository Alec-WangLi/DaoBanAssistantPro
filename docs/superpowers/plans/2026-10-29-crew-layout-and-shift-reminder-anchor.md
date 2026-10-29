# 班组卡排版 + 重复待办提醒三档落点 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 编辑排班的班组卡按方案 A 收口；重复待办「按班次」的提醒接上班次闹钟的三档落点（前一天 / 当天 / 次日），并在待办行上标出落点。

**Architecture:** 落点判据复用 `alarmDayAnchor`（`domain/shift_rotation.dart`），不新写一份；`recurring_todo.dart` 的回调从「返回班次名」换成「返回 `ShiftClass`」，`upcomingFireTimes` 改为「收集 → 排序 → 去重 → 裁地平线」。界面侧用一个新的系列流 provider 把「系列 + 当天班次」喂给待办行，只做拼装。

**Tech Stack:** Flutter 3.x / Dart、Riverpod、Drift（SQLite）、flutter_test、视觉工装 `app/tool/visual/`。

**Spec:** `docs/superpowers/specs/2026-10-29-crew-layout-and-shift-reminder-anchor-design.md`（执行时先读它，再读本计划）

## Global Constraints

- 分支：测试版在 **beta** 上开发、提交、发布（tag `v0.12.6` 打在 beta 提交上）；`main` 只在正式版时合并。
- 版本：`app/pubspec.yaml` 的 `version: 0.12.6+181` 与 `app/lib/core/app_info.dart` 的 `appVersion` 同步（`app/test/app_info_test.dart` 盯着）。`X.Y` 只能由用户改，本计划只动 `Z` 与 build。
- 验收：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿且只增不减；视觉工装 `flutter test tool/visual/` 全过；改 UI 后必须出图**看**（`render_screens_test.dart`），不看图不算验。
- **不要跑 `dart format`**（工具链的 tall style 会把整文件重排，制造几百行无关 diff）。
- 界面层不许写字号 / 字重 / `circular(<数字>)` / 颜色字面量 / 时长字面量 —— 一律走 `AppTokens`（`design_tokens_test.dart` 守门）。
- 所有用户可见文案走 `L10n`（zh / en 两条都要写）。
- 删除 / 覆盖前先看目标；提交信息按仓库风格（`fix(...)` / `feat(...)` / `test(...)` / `chore(...)`），末尾带 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`。
- 命令统一在 `app/` 目录下执行：`cd app && ../toolchain/flutter/bin/flutter test …`。
- 原生 Kotlin 一行都不改。

## Review Focus

spec 隐含、但没有哪条任务测试直接盯住、最可能咬人的五处（各自已落到下面任务的用例里）：

1. **`endMinute` 的两种存法**：回绕式（夜班 20:30→08:30 存 510）与累计式（20:30→1950）必须给出同一组落点 —— 直接相减在回绕式下是负数，窗口判据会静默失效。→ Task 2。
2. **提醒钟点正好等于下班钟点**（窗口右沿，`[start, end)` 不含 end）：必须落成次日那一刻，而不是被当成窗口内当天。→ Task 2。
3. **班次没有上下班时间**（休班 / 未填时间被选中）：落点退回当天，不瞎挪。→ Task 2。
4. **`from` 恰好等于某条提醒的时刻**：相等也算「不早于」，那条提醒不能被漏排。→ Task 2。
5. **不属于系列 / 系列规则不是按班次的一次性待办**：即使那天是夜班、钟点是 00:00，也**不许**标落点。→ Task 3。

---

### Task 1: 班次回调从「名字」换成「班次定义」（纯重构，行为不变）

**Files:**
- Modify: `app/lib/domain/recurring_todo.dart:182-311`（四个查询函数 + `upcomingFireTimes` + `_matchesShift`）
- Modify: `app/lib/data/app_repository.dart:1108-1113`
- Modify: `app/lib/features/alarm/alarm_service.dart:196-225, 950-960, 1113-1163`
- Modify: `app/lib/features/schedule/recurring_panel.dart:77-96`
- Modify: `app/lib/features/schedule/recurring_series_editor.dart:165-170`
- Modify: `app/lib/features/schedule/schedule_screen.dart:783-790`
- Test: `app/test/recurring_todo_test.dart:269-311`、`app/test/recurring_alarm_plan_test.dart:82-90`

**Interfaces:**
- Produces: 所有查询函数与计划的参数改为 `ShiftClass? Function(DateTime day)? shiftOn`（原 `String? Function(DateTime day)? shiftNameOn` 删除）。

- [ ] **Step 1: 改测试夹具（先看着它编译不过）**

`recurring_todo_test.dart` 的「按班次」组里，把返回名字的闭包换成返回班次定义：

```dart
const _nightShift = ShiftClass(name: '上夜班', startMinute: 1230, endMinute: 1920);
const _dayShift = ShiftClass(name: '白班', startMinute: 480, endMinute: 1080);
ShiftClass? night(DateTime d) =>
    d.weekday == DateTime.wednesday ? _nightShift : _dayShift;
```

把该组里的 `shiftNameOn: night` 全部改成 `shiftOn: night`；`recurring_alarm_plan_test.dart` 里同名的 `night` 闭包照同样方式改（并 `import 'package:shiftassistantpro/domain/shift_rotation.dart';`）。

- [ ] **Step 2: 运行测试确认编译失败**

```bash
cd app && ../toolchain/flutter/bin/flutter test test/recurring_todo_test.dart test/recurring_alarm_plan_test.dart
```

Expected: 编译错误，提示 `shiftOn` 不是已知命名参数。

- [ ] **Step 3: 改签名与调用点**

`recurring_todo.dart`：

```dart
bool _matchesShift(
        RecurringTodo s, DateTime day, ShiftClass? Function(DateTime day)? on) =>
    on != null && s.shiftNames.isNotEmpty && s.shiftNames.contains(on(day)?.name);
```

`firstOccurrenceOnOrAfter` / `occurrenceOnOrBefore` / `nextOccurrenceAfter` / `upcomingFireTimes` 与 `planRecurringReminders` / `rescheduleRecurringReminders` 的参数全部改成 `ShiftClass? Function(DateTime day)? shiftOn`，函数体里的转发同步改名。

调用点改法（都是一行）：

- `app_repository.dart`：`final shiftOn = schedules?.chain.shiftOn;`，`occurrenceOnOrBefore(..., shiftOn: shiftOn)`。
- `alarm_service.dart`：`rescheduleAll` 里 `shiftOn: schedules.chain.shiftOn`；`rescheduleTodoReminders` 里 `final shiftOn = active?.chain.shiftOn;`；`recurringSeriesEditor`/`schedule_screen` 处凡是 `shiftNameOn: chain == null ? null : (d) => chain.shiftOn(d)?.name` 一律简写成 `shiftOn: chain?.shiftOn`；`recurring_panel.dart` 同理（`chain?.shiftOn`）。
- 删除不再需要的 `String? Function(DateTime)` 局部变量声明（类型改用 `final` 推断）。

- [ ] **Step 4: 跑目标测试**

```bash
cd app && ../toolchain/flutter/bin/flutter test test/recurring_todo_test.dart test/recurring_alarm_plan_test.dart test/recurring_repository_test.dart test/advance_recurring_test.dart
```

Expected: 全绿（行为未变 —— `_fireAt` 这一轮还没接落点）。

- [ ] **Step 5: 提交**

```bash
git add -A && git commit -m "refactor(todo): 按班次回调改为返回班次定义"
```

---

### Task 2: 提醒时刻接入三档落点（领域层）

**Files:**
- Modify: `app/lib/domain/recurring_todo.dart:269-311`（`_fireAt` / `upcomingFireTimes`）
- Test: `app/test/recurring_todo_test.dart`（新增 `group('按班次 · 落点')`）、`app/test/recurring_alarm_plan_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `ShiftClass? Function(DateTime day)? shiftOn`。
- Produces: `upcomingFireTimes` 的输出**升序、无相邻重复**；落点由 `alarmDayAnchor(shift, ShiftAlarm(minute: clockMinute))` 决定（仅当 `s.repeat == RecurRepeat.shift` 且 `s.timeMinute != null` 时生效）。

- [ ] **Step 1: 写失败用例**

⚠️ **执行注记（2026-10-29）**：下面最初写的 `only(night)` 让**每天**都是夜班 —— 那种夹具下「落点」只是把钟点重新贴了个日期标签，整串时刻与「发生日 + 钟点」完全一样，用例**永远绿、没有鉴别力**。实施时改成**稀疏班次日**（`onDays({22: night})`），见 `recurring_todo_test.dart` 的「按班次 · 落点」组；`only` 的返回类型也应为 `ShiftClass? Function(DateTime)`。

在 `recurring_todo_test.dart` 新开一组（用 Task 1 的夹具与下面的班次常量）。每条都用 `upcomingFireTimes`（记得给 `advance: 0`，否则提前量会挪时刻）：

```dart
group('按班次 · 落点（与班次闹钟同一判据）', () {
  // 夜班 20:30–次日 08:30：回绕式存法 end = 510
  const night = ShiftClass(name: '夜班', startMinute: 1230, endMinute: 510);
  const nightCum = ShiftClass(name: '夜班', startMinute: 1230, endMinute: 1950);
  const zero = ShiftClass(name: '零点班', startMinute: 0, endMinute: 360);
  const duty = ShiftClass(name: '值班', startMinute: 480, endMinute: 1920); // 24h
  const rest = ShiftClass(name: '休班', isRest: true);
  ShiftClass? only(ShiftClass c) => (DateTime d) => c;

  RecurringTodo shiftAt(int clock, {List<String> names = const ['夜班']}) =>
      _s(repeat: RecurRepeat.shift, shiftNames: names, timeMinute: clock, advance: 0);

  test('班中钟点 → 次日；上班前 / 窗口内白天 → 当天', () {
    final s = shiftAt(0);
    final times = upcomingFireTimes(s, from: DateTime(2026, 9, 21, 20),
        clockMinute: 0, shiftOn: only(night));
    expect(times.first, DateTime(2026, 9, 22, 0)); // 21 日晚班 → 22 日 0 点

    final seven = upcomingFireTimes(shiftAt(7 * 60),
        from: DateTime(2026, 9, 21, 20), clockMinute: 7 * 60, shiftOn: only(night));
    expect(seven.first, DateTime(2026, 9, 22, 7));

    final nineteen = upcomingFireTimes(shiftAt(19 * 60),
        from: DateTime(2026, 9, 21, 12), clockMinute: 19 * 60, shiftOn: only(night));
    expect(nineteen.first, DateTime(2026, 9, 21, 19)); // 上班前 1.5h，当天

    final ten = upcomingFireTimes(shiftAt(10 * 60),
        from: DateTime(2026, 9, 21, 12), clockMinute: 10 * 60, shiftOn: only(night));
    expect(ten.first, DateTime(2026, 9, 22, 10)); // 离下班更近 → 次日
  });

  test('零点班 23:00 → 前一天', () {
    final times = upcomingFireTimes(shiftAt(23 * 60, names: const ['零点班']),
        from: DateTime(2026, 9, 20, 12), clockMinute: 23 * 60, shiftOn: only(zero));
    expect(times.first, DateTime(2026, 9, 20, 23));
  });

  test('24 小时值班：全天都算当天', () {
    final times = upcomingFireTimes(shiftAt(7 * 60, names: const ['值班']),
        from: DateTime(2026, 9, 21, 0), clockMinute: 7 * 60, shiftOn: only(duty));
    expect(times.first, DateTime(2026, 9, 21, 7));
  });

  test('两种 endMinute 存法同解', () {
    for (final sh in [night, nightCum]) {
      final times = upcomingFireTimes(shiftAt(0),
          from: DateTime(2026, 9, 21, 20), clockMinute: 0, shiftOn: only(sh));
      expect(times.first, DateTime(2026, 9, 22, 0));
    }
  });

  test('提醒钟点正好等于下班钟点 → 落到次日那一刻', () {
    final times = upcomingFireTimes(shiftAt(8 * 60 + 30),
        from: DateTime(2026, 9, 21, 20), clockMinute: 8 * 60 + 30, shiftOn: only(night));
    expect(times.first, DateTime(2026, 9, 22, 8, 30));
  });

  test('班次没有上下班时间（休班）→ 落点当天', () {
    final times = upcomingFireTimes(shiftAt(0, names: const ['休班']),
        from: DateTime(2026, 9, 20, 23), clockMinute: 0, shiftOn: only(rest));
    expect(times.first, DateTime(2026, 9, 21, 0));
  });

  test('提前量作用在落点之后（00:00 提前 5 分钟 → 当日 23:55）', () {
    final s = _s(repeat: RecurRepeat.shift, shiftNames: const ['夜班'],
        timeMinute: 0, advance: 5);
    final times = upcomingFireTimes(s, from: DateTime(2026, 9, 21, 20),
        clockMinute: 0, shiftOn: only(night));
    expect(times.first, DateTime(2026, 9, 21, 23, 55));
  });

  test('from 恰好等于那条提醒、且它属于昨天那次：不能漏', () {
    // D=22 与 D+1=23 都是夜班；D 的 00:15 提醒落在 23 日 00:15。
    // from 正好取这一刻：相等也算「不早于」，同时覆盖「窗口要从昨天起算」。
    ShiftClass? everyNight(DateTime d) => night;
    final s = _s(repeat: RecurRepeat.shift, shiftNames: const ['夜班'],
        timeMinute: 15, advance: 0);
    final times = upcomingFireTimes(s, from: DateTime(2026, 9, 23, 0, 15),
        clockMinute: 15, shiftOn: everyNight);
    expect(times.first, DateTime(2026, 9, 23, 0, 15));
  });

  test('相邻两次倒序（夜班 + 零点班混选 07:00）→ 输出必须升序、两条都在', () {
    // 22 日夜班 → 23 日 07:00；23 日零点班 → 22 日 07:00（prev）。原写法会乱序漏响。
    ShiftClass? mixed(DateTime d) =>
        d.day == 22 ? night : (d.day == 23 ? zero : null);
    final s = _s(repeat: RecurRepeat.shift, shiftNames: const ['夜班', '零点班'],
        timeMinute: 7 * 60, advance: 0);
    final times = upcomingFireTimes(s, from: DateTime(2026, 9, 20, 0),
        clockMinute: 7 * 60, shiftOn: mixed);
    expect(times.take(2).toList(),
        [DateTime(2026, 9, 22, 7), DateTime(2026, 9, 23, 7)]);
  });

  test('相邻两次落成同一时刻 → 只排一条', () {
    // 22 日夜班 00:15 → 23 日 00:15（next）；23 日零点班 00:15 → 23 日 00:15（窗口内）。
    ShiftClass? mixed(DateTime d) =>
        d.day == 22 ? night : (d.day == 23 ? zero : null);
    final s = _s(repeat: RecurRepeat.shift, shiftNames: const ['夜班', '零点班'],
        timeMinute: 15, advance: 0);
    final times = upcomingFireTimes(s, from: DateTime(2026, 9, 20, 0),
        clockMinute: 15, shiftOn: mixed);
    expect(times.take(2).toList(), [DateTime(2026, 9, 23, 0, 15)]);
  });

  test('全天提醒不套落点', () {
    final s = _s(repeat: RecurRepeat.shift, shiftNames: const ['夜班'], advance: 0);
    ShiftClass? everyNight(DateTime d) => night;
    final times = upcomingFireTimes(s, from: DateTime(2026, 9, 20, 12),
        clockMinute: 9 * 60, shiftOn: everyNight);
    expect(times.first, DateTime(2026, 9, 21, 9)); // 发生日当天 9 点
  });
});
```

⚠️ 上一条的零点班 `00:15` 落在窗口 `[0, 360)` 内 → `same`；`take(2)` 只有一条，是因为下一条已经是 24 日（`mixed` 之外没有匹配日）。

- [ ] **Step 2: 跑测试确认失败**

```bash
cd app && ../toolchain/flutter/bin/flutter test test/recurring_todo_test.dart
```

Expected: 新增用例红 —— 00:00 落在 21 日 0 点而不是 22 日等。

- [ ] **Step 3: 实现**

`_fireAt` 增加可选班次参数：

```dart
DateTime _fireAt(DateTime occ, int clock, int advance, {ShiftClass? shift}) {
  var delta = 0;
  if (shift != null) {
    delta = switch (alarmDayAnchor(shift, ShiftAlarm(minute: clock))) {
      AlarmDayAnchor.prev => -1,
      AlarmDayAnchor.same => 0,
      AlarmDayAnchor.next => 1,
    };
  }
  return DateTime(occ.year, occ.month, occ.day + delta)
      .add(Duration(minutes: clock - advance));
}
```

`upcomingFireTimes` 重写（签名已含 `shiftOn`）：

```dart
final advance = s.advanceRemindMinutes;
if (advance == null || !s.enabled) return const [];
final shiftRule = s.repeat == RecurRepeat.shift;
final horizon = from.add(Duration(days: days));
final start = shiftRule ? _addDays(dateOnly(from), -1) : from;
final lastOcc = _addDays(dateOnly(from), days + 1);
final candidates = <DateTime>[];
var occ = occurrenceOnOrBefore(s, start, shiftOn: shiftOn) ??
    firstOccurrenceOnOrAfter(s, start, shiftOn: shiftOn);
while (occ != null && daysBetween(dateOnly(occ), lastOcc) >= 0) {
  final shift = shiftRule ? shiftOn?.call(occ) : null;
  final fire = _fireAt(occ, clockMinute, advance, shift: shift);
  if (!fire.isBefore(from)) candidates.add(fire);
  occ = nextOccurrenceAfter(s, occ, shiftOn: shiftOn);
}
candidates.sort();
final out = <DateTime>[];
for (final f in candidates) {
  if (f.isAfter(horizon)) break;
  if (out.isNotEmpty && out.last == f) continue;
  out.add(f);
  if (out.length >= cap) break;
}
return out;
```

**「全天不套落点」落在哪：** `planRecurringReminders` 传的是 `clockMinute: s.timeMinute ?? allDayReminderHour * 60`；所以「有没有设时间」的判据在传参处已经丢了。把 `upcomingFireTimes` 的 `shiftRule` 再加一项 `&& s.timeMinute != null`（即全天提醒不传 shift）——并在 `recurring_todo.dart` 的注释里写明理由（spec §3.5）。

- [ ] **Step 4: 跑测试确认全绿**

```bash
cd app && ../toolchain/flutter/bin/flutter test test/recurring_todo_test.dart test/recurring_alarm_plan_test.dart
```

Expected: PASS。

- [ ] **Step 5: 反向验证**

把 `final shift = ...` 一行临时改成 `final shift = null;` → 落点组红；把 `start` 改回 `from` → 「昨天那次不能漏」红；把 `candidates.sort()` 删掉 → 倒序组红。逐条验完还原。

- [ ] **Step 6: 提交**

```bash
git add -A && git commit -m "feat(todo): 按班次的提醒接入班次闹钟的三档落点"
```

---

### Task 3: 待办行的落点标记

**Files:**
- Modify: `app/lib/domain/recurring_todo.dart`（新增 `todoReminderClockLabel`）
- Modify: `app/lib/data/app_repository.dart`（新增 `recurringSeriesProvider`，放在 `eventsProvider` 之后）
- Modify: `app/lib/features/schedule/schedule_screen.dart:93-99, 336-343, 105-170`（build 里取 chain / 系列表并传给 `_eventTile`）
- Test: 新建 `app/test/todo_shift_marker_test.dart`

**Interfaces:**
- Consumes: Task 2 的落点判据（通过 `alarmDayAnchor`）；`L10n.clockPrevDay` / `L10n.clockNextDay`。
- Produces:
  - `String? todoReminderClockLabel({required int clockMinute, required ShiftClass? shift})` —— 当天落点返回 `null`。
  - `final recurringSeriesProvider = StreamProvider<List<RecurringTodo>>(...)`。

- [ ] **Step 1: 写失败的纯函数用例**

新建 `app/test/todo_shift_marker_test.dart`（先只放纯函数组）：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

void main() {
  setUp(() => L10n.locale = 'zh');
  const night = ShiftClass(name: '夜班', startMinute: 1230, endMinute: 510);

  test('班中钟点标「次日」，上班前标「前一天」，窗口外当天不标', () {
    expect(todoReminderClockLabel(clockMinute: 0, shift: night),
        L10n.clockNextDay('00:00'));
    expect(todoReminderClockLabel(clockMinute: 19 * 60, shift: night), isNull);
    expect(
        todoReminderClockLabel(
            clockMinute: 23 * 60,
            shift: const ShiftClass(name: '零点班', startMinute: 0, endMinute: 480)),
        L10n.clockPrevDay('23:00'));
    expect(todoReminderClockLabel(clockMinute: 0, shift: null), isNull);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd app && ../toolchain/flutter/bin/flutter test test/todo_shift_marker_test.dart
```

Expected: 编译失败（`todoReminderClockLabel` 未定义）。

- [ ] **Step 3: 实现纯函数与 provider**

`recurring_todo.dart`：

```dart
/// 待办提醒的钟点按当天班次落在前一天 / 当天 / 次日时的显示串。
/// 落点在当天、没有班次、或钟点为空时返回 null（不标）。
String? todoReminderClockLabel({
  required int clockMinute,
  required ShiftClass? shift,
}) {
  if (shift == null) return null;
  final clock = formatClock(clockMinute);
  return switch (alarmDayAnchor(shift, ShiftAlarm(minute: clockMinute))) {
    AlarmDayAnchor.prev => L10n.clockPrevDay(clock),
    AlarmDayAnchor.next => L10n.clockNextDay(clock),
    AlarmDayAnchor.same => null,
  };
}
```

`app_repository.dart`（`eventsProvider` 后面）：

```dart
/// 全部重复系列（响应式）。待办列表要按 `seriesId` 查「这条是不是按班次规则、
/// 提醒钟点落在哪天」—— 系列被编辑 / 开关 / 删除时列表要能自己跟上。
final recurringSeriesProvider = StreamProvider<List<RecurringTodo>>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .select(db.recurringSeriesRows)
      .watch()
      .map((rows) => rows.map((r) => r.toDomain()).toList());
});
```

- [ ] **Step 4: 接进待办行（含两道一致性条件）**

`ScheduleScreen.build`：

```dart
final seriesById = {
  for (final s in (ref.watch(recurringSeriesProvider).valueOrNull ?? const <RecurringTodo>[]))
    if (s.id != null) s.id!: s,
};
final chain = ref.watch(activeScheduleProvider).valueOrNull?.chain;
```

把两者传给两处 `_eventTile(...)` 调用（主列表与归档区），`_eventTile` 新签名：

```dart
Widget _eventTile(BuildContext context, WidgetRef ref, ScheduleEvent e,
    {bool archived = false, ScheduleChain? chain, RecurringTodo? series})
```

副标题那一段：

```dart
final seriesClock = (series != null &&
        series.repeat == RecurRepeat.shift &&
        series.timeMinute != null &&
        series.timeMinute == e.timeMinute &&
        e.seriesId != null &&
        chain != null &&
        series.shiftNames.contains(chain.shiftOn(e.date)?.name))
    ? series.timeMinute
    : null;
final timeText = e.timeMinute == null
    ? null
    : (seriesClock == null
        ? _fmt(e.timeMinute!)
        : (todoReminderClockLabel(
                clockMinute: seriesClock, shift: chain!.shiftOn(e.date)) ??
            _fmt(e.timeMinute!)));
```

然后 `if (timeText != null) timeText` 放进副标题列表。

- [ ] **Step 5: 补界面用例（同一文件）**

照 `todo_archive_screen_test.dart` 的夹具（`NativeDatabase.opened` + `_stubPluginChannels` + `_settle` + `_dispose`）写四条：

1. 库里把当前方案换成「今天 = 夜班（20:30–08:30 回绕式）」、加一条 `RecurRepeat.shift` 系列（`shiftNames: ['夜班']`、`timeMinute: 0`、`advance: 0`）、跑 `advanceRecurringTodos(today:)`，pump `ScheduleScreen` → `find.textContaining(L10n.clockNextDay('00:00'))` 命中一条。
2. 同样的一天，但系列是 `RecurRepeat.daily`、`timeMinute: 0` → 页面上没有 `L10n.nextDayMarker` 或「次日前缀」（`find.textContaining('次日')` 为空）。
3. 旧行：系列 `shiftNames: ['白班']`，而那天是夜班；直接插一条带该 `seriesId` 的事件 → 不标（同 2 的断言）。
4. 钟点不一致：系列 `timeMinute: 0`，事件行 `timeMinute: 9*60` → 不标。

⚠️ 事件行要用仓库真入口建（`addRecurringTodo` + `advanceRecurringTodos`；第 3、4 条可以用 `addEvent(..., seriesId: …)` / `updateEvent` 造现场），别直接写 drift 行 —— 字段形状变了用例会静默失效。

- [ ] **Step 6: 跑测试确认全绿**

```bash
cd app && ../toolchain/flutter/bin/flutter test test/todo_shift_marker_test.dart test/todo_archive_screen_test.dart test/recurring_screen_test.dart
```

Expected: PASS。若出现「A Timer is still pending」，说明用例结束前没有按 `_dispose` 拆树 —— 照既有文件补上。

- [ ] **Step 7: 反向验证**

把 `series.shiftNames.contains(...)` 删掉 → 第 3 条红；把 `series.timeMinute == e.timeMinute` 删掉 → 第 4 条红；把整段标记逻辑短路 → 第 1 条红。还原。

- [ ] **Step 8: 提交**

```bash
git add -A && git commit -m "feat(todo): 待办行的提醒时刻标出前一天/次日"
```

---

### Task 4: 系列编辑器说明与帮助文案

**Files:**
- Modify: `app/lib/core/l10n.dart`（`shiftAnchorHint`，放在 `shiftRuleHint` 后）
- Modify: `app/lib/features/schedule/recurring_fields.dart:262-268`
- Modify: `app/lib/features/profile/help_content.dart:196-201`
- Test: `app/test/recurring_rule_picker_test.dart`（新增一条）、`app/test/help_content_test.dart`（若它逐条断言内容则同步）

**Interfaces:**
- Produces: `L10n.shiftAnchorHint`（zh：「提醒落在班次值班时间里时按那天的班次算（跨午夜的班次会落在次日）」；en：「A reminder moment inside the shift's working window follows the shift — cross-midnight shifts land on the next day」）。挂在「按班次」档下方的说明里，与 `shiftRuleHint` 同段。

- [ ] **Step 1: 写失败用例**

`recurring_rule_picker_test.dart`：选到「按班次」后断言 `find.text(L10n.shiftAnchorHint)` 命中；切回「每天」后 `findsNothing`。

- [ ] **Step 2: 跑它确认失败**

```bash
cd app && ../toolchain/flutter/bin/flutter test test/recurring_rule_picker_test.dart
```

Expected: FAIL（未定义 / 找不到）。

- [ ] **Step 3: 实现**

l10n 加 `shiftAnchorHint`；`recurring_fields.dart` 在 `L10n.shiftRuleHint` 那个 `Padding` 之后照同一个 `microText + muted` 再加一条 `Padding(top: spaceXs, child: Text(L10n.shiftAnchorHint, …))`；`help_content.dart` 的「按班次」条目正文末尾补一句：「提醒时刻落在班次的值班时间里（比如夜班的凌晨 0 点）会排在**次日**；不在值班时间里时，按离上班还是离下班近来定。」

- [ ] **Step 4: 跑相关测试**

```bash
cd app && ../toolchain/flutter/bin/flutter test test/recurring_rule_picker_test.dart test/help_content_test.dart test/help_center_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add -A && git commit -m "docs(todo): 按班次提醒的落点说明与帮助"
```

---

### Task 5: 班组卡排版（方案 A）

**Files:**
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart:1779-1929`（`_crewRow`，并新增文件内私有 `_crewValueRow`）
- Test: `app/test/schedule_editor_test.dart`（新增几何用例）

**Interfaces:**
- Produces: `_crewValueRow(BuildContext context, {required IconData icon, required String label, String? value, required Key chevronKey, required Key rowKey, required VoidCallback onTap})`；新增键 `crew-start-row-$i` / `crew-segment-row-$i`；既有键 `crew-name-$i` / `crew-start-chevron-$i` / `crew-segment-chevron-$i` 全部保留。

- [ ] **Step 1: 写失败用例**

`schedule_editor_test.dart`（照「展开班组后：四行班组起始日都有箭头」那条的写法）：

```dart
testWidgets('班组卡：输入框收窄、周期起始日那一行够高好点', (tester) async {
  await _pumpEditor(tester, _domain(), crewExpanded: true);

  final field = tester.getSize(find.ancestor(
      of: find.byKey(const Key('crew-name-0')),
      matching: find.byType(GlassField)));
  expect(field.width, lessThanOrEqualTo(180));

  final row = tester.getSize(find.byKey(const Key('crew-start-row-0')));
  expect(row.height, greaterThanOrEqualTo(44),
      reason: '这一行是整行可点的入口，矮了就成了「又长又矮、点不着」');
});
```

（`GlassField` 已在文件里 import。）

- [ ] **Step 2: 跑它确认失败**

```bash
cd app && ../toolchain/flutter/bin/flutter test test/schedule_editor_test.dart --plain-name '班组卡：输入框收窄'
```

Expected: FAIL（宽度约 255，键不存在）。

- [ ] **Step 3: 改版式**

第一行把 `Expanded(GlassField(...))` 换成：

```dart
Flexible(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 180),
    child: GlassField(/* 原样 */),
  ),
),
const Spacer(),
/* 原「设为我」芯片 */
```

第二行（周期 / 按月两种）统一走新私有方法：

```dart
Widget _crewValueRow(BuildContext context, {
  required IconData icon,
  required String label,
  String? value,
  required Key chevronKey,
  required Key rowKey,
  required VoidCallback onTap,
}) {
  final muted = AppTokens.inkMuted(context);
  final outline = Theme.of(context).colorScheme.outline;
  return Column(children: [
    const SizedBox(height: AppTokens.spaceSm),
    Container(height: 1, color: outline.withValues(alpha: 0.7)),
    GlassPressable(
      child: GestureDetector(
        key: rowKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.gapHair, vertical: AppTokens.spaceMd),
          child: Row(children: [
            AppIcon(icon, size: AppTokens.iconSm, color: muted),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label, style: AppTokens.rowPrimary),
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: AppTokens.spaceSm),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value, style: AppTokens.labelStrong),
                ),
              ),
            ],
            const SizedBox(width: AppTokens.gapHair),
            AppIcon(Icons.chevron_right_outlined,
                key: chevronKey, size: AppTokens.iconSm, color: muted),
          ]),
        ),
      ),
    ),
  ]);
}
```

周期模式调用：`label: L10n.crewCycleStart, value: L10n.yearMonthDay(_crewStartDate(i)), chevronKey: Key('crew-start-chevron-$i'), rowKey: Key('crew-start-row-$i'), onTap: () => _pickCrewStartDate(i), icon: Icons.event_outlined`。

按月模式：`label: L10n.crewSegmentStart(n), value: null, chevronKey: Key('crew-segment-chevron-$i'), rowKey: Key('crew-segment-row-$i'), icon: Icons.format_list_numbered`。

⚠️ 行高：`spaceMd`(12) + 行盒 + `spaceMd` = 约 44；若实测不足 44，把 `vertical` 提到 `spaceMd + gapHair`（14）并在注释里写明是几何下限，不要改令牌。

- [ ] **Step 4: 跑测试**

```bash
cd app && ../toolchain/flutter/bin/flutter test test/schedule_editor_test.dart test/monthly_schedule_editor_test.dart
```

Expected: PASS（含既有的箭头 / 320dp 不溢出 / 折叠副标题用例）。

- [ ] **Step 5: 出图看**

```bash
cd app && ../toolchain/flutter/bin/flutter test tool/visual/render_screens_test.dart --plain-name '排班编辑器 · 班组设置展开'
```

打开 `app/build/visual/67_editor_crew_expanded_*.png` 逐张看（浅 / 深 / 英 / 小窗 / 横屏）：输入框宽度、分隔线、44dp 行、箭头对齐；用 `text_fit_guard_test` 的方法确认没有新截断。

- [ ] **Step 6: 提交**

```bash
git add -A && git commit -m "fix(ui): 班组卡输入框收窄、周期起始日改成加高的值行"
```

---

### Task 6: 工装种子：让「次日 00:00」有图可看

**Files:**
- Modify: `app/tool/visual/visual_harness.dart:747-776`（`seedRecurringTodo` 末尾追加）
- Test: 视觉工装出图 `24_todos_recurring_*` / `25_recurring_panel_*`

- [ ] **Step 1: 追加种子**

在 `seedRecurringTodo` 末尾（`addEvent('交体检报告'…)` 之后）加：

```dart
// 「按班次 · 夜班 · 00:00」：让「次日 00:00」这个落点标记在待办行上有图可看。
// 今天必须落在跨午夜的夜班日上：锚点往前挪一天、三天轮转「白 / 夜 / 休」，
// 于是今天 = 夜班（与 makeMidnightShiftCurrent 同一手法）。
final today0 = dateOnly(DateTime.now());
await repo.saveSchedule(
  name: '夜班 · 提醒落次日',
  anchorDate: DateTime(today0.year, today0.month, today0.day - 1),
  classes: const [
    ShiftClass(name: '白班', abbr: '白', startMinute: 480, endMinute: 1200, color: 0xFF4C8DFF),
    ShiftClass(name: '夜班', abbr: '夜', startMinute: 1230, endMinute: 480, color: 0xFF7A5CFF),
    ShiftClass(name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4),
  ],
  cycle: const [0, 1, 2],
  makeCurrent: true,
  teamCount: 1,
  teamNames: L10n.defaultTeamNames(1),
  ourTeamIndex: 0,
  teamOffsets: const [0],
);
await repo.addRecurringTodo(
  title: '夜班写台账',
  repeat: RecurRepeat.shift,
  startDate: today0,
  shiftNames: const ['夜班'],
  timeMinute: 0,
  advanceRemindMinutes: 0,
);
await repo.advanceRecurringTodos(today: today0);
```

- [ ] **Step 2: 出图并看**

```bash
cd app && ../toolchain/flutter/bin/flutter test tool/visual/render_screens_test.dart --plain-name '待办 · 含重复项' && ../toolchain/flutter/bin/flutter test tool/visual/render_screens_test.dart --plain-name '重复待办 · 管理面板'
```

打开 `app/build/visual/24_todos_recurring_light.png` 与 `25_recurring_panel_light.png`：前者应出现「夜班写台账」一行、副标题带「次日 00:00」；后者多一行「夜班写台账」。

- [ ] **Step 3: 跑字号护栏**

```bash
cd app && ../toolchain/flutter/bin/flutter test tool/visual/text_fit_guard_test.dart
```

Expected: PASS（若新行在窄档被点名，按既有降级顺序处理，不要放宽护栏）。

- [ ] **Step 4: 提交**

```bash
git add -A && git commit -m "test(visual): 屏单补「按班次提醒落次日」的现场"
```

---

### Task 7: 版本、更新日志与文档

**Files:**
- Modify: `app/pubspec.yaml:4`（`version: 0.12.6+181`）
- Modify: `app/lib/core/app_info.dart`（`appVersion = '0.12.6'`）
- Modify: `app/lib/features/profile/app_dialogs.dart`（`_changelogZh` / `_changelogEn` prepend 一条、删最旧、保持 10 条）
- Modify: `AGENTS.md`（版本史一行 + 「最近改动」一条）
- Modify: `PRODUCT_SPEC.md`（按时段的提醒落点条目，如涉及）

- [ ] **Step 1: 版本号两处同步** + 更新日志（测试版条目原样写本版改动，不归纳）
- [ ] **Step 2: 跑守门**

```bash
cd app && ../toolchain/flutter/bin/flutter test test/app_info_test.dart test/changelog_window_test.dart
```

Expected: PASS（10 条窗口、版本单调、首条 = appVersion、无 markdown 标记）。

- [ ] **Step 3: 提交**

```bash
git add -A && git commit -m "chore(release): v0.12.6 文案与版本"
```

---

### Task 8: 全量验收与发布

- [ ] **Step 1: 全量静态检查与测试**

```bash
cd app && ../toolchain/flutter/bin/flutter analyze && ../toolchain/flutter/bin/flutter test && ../toolchain/flutter/bin/flutter test tool/visual/
```

Expected: analyze 0 error / 0 warning；单测全绿（数量只增不减）；工装全绿。

- [ ] **Step 2: 构建 APK（必须在主 checkout，不在 worktree）**

```bash
cd app && ../toolchain/flutter/bin/flutter build apk --release --target-platform android-arm64
```

产物 `app/build/app/outputs/flutter-apk/app-release.apk`；复制到 `dist/倒班助手Pro-v0.12.6.apk`，`aapt2 dump badging` 核对 versionName/versionCode 与包名。

- [ ] **Step 3: 提交、打 tag、推送（beta）**

```bash
git add -A && git commit -m "chore(release): v0.12.6"   # 若还有未提交的产物/文案
git tag v0.12.6 && git push origin beta && git push origin v0.12.6
```

- [ ] **Step 4: GitHub Release**

发布说明先写 `tools/gh/release-notes-v0.12.6.md`，再：

```bash
powershell -File scripts/release.ps1 -SkipConfirm
```

完成后 `curl` 主通道清单核对版本号：

```bash
curl -s https://raw.githubusercontent.com/<owner>/<repo>/main/latest.json
```

（`<owner>/<repo>` 从 `git remote -v` 取。）若脚本的第 8b 步只告警，按 AGENTS.md「分支与发布」那段的规矩手动补 main 上的清单节点。

- [ ] **Step 5: 真机验收（ADB 已连接）**

- 待办页新建「按班次 · 夜班 · 00:00」的系列，`adb shell dumpsys alarm` 里该条提醒的时刻是**次日 00:00**；列表行显示「次日 00:00」。
- 编辑排班 → 班组设置展开：输入框宽度、周期起始日行手感与图上一致。
- 提到的旧行为：每天规则的同一条待办仍是当天 00:00。

---

## 计划自查记录

- **Spec 覆盖**：§2（Task 5）、§3.1–3.4（Task 2）、§3.5 全天（Task 2）、§4.1（Task 3）、§4.2（Task 4）、§4.3（Task 4）、§5 测试与工装（Task 2/3/5/6/7/8）、§6 版本发布（Task 7/8）。§2 的三版候选属过程材料，不需要任务。
- **类型一致**：`shiftOn` 全程是 `ShiftClass? Function(DateTime day)?`；键名 `crew-start-row-$i` / `crew-segment-row-$i` 只在 Task 5 出现；`todoReminderClockLabel` 在 Task 3 定义并使用。
- **Review Focus 五条**都已落到 Task 2 / Task 3 的用例里。
