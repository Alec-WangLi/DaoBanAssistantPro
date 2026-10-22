# 重复待办：按班次重复 + 每月多选 + 两处小改 —— 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让重复待办可以按「排班表里的班次」重复、每月可多选几天，并把星期选择器排成一行、去掉重复待办面板行尾的铅笔。

**Architecture:** 领域层给四个发生日查询函数加一个 `shiftNameOn` 回调（班组那天的班次名），按班次规则逐天扫描求发生日；提醒链路把 `ScheduleChain` 的闭包透传给同一套函数。数据库新增 `month_days` 位掩码与 `shift_names` JSON 两列、删掉旧的 `month_day`（schema 15）。界面集中在 `recurring_fields.dart` 的两个共享件里，两条入口（待办弹窗、系列编辑器）只做接线。

**Tech Stack:** Flutter / Dart、Riverpod、Drift（SQLite）、intl、项目自有的 `AppTokens` 设计令牌与玻璃组件。

**Spec:** `docs/superpowers/specs/2026-10-22-shift-based-recurring-todos-design.md`

## Global Constraints

- 版本号 `0.12.2+177` → **`0.12.3+178`**（`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 同步；`app_info_test.dart` 盯着）。
- **只改测试，不删测试**：现有 1106 条，新增用例只增不减；现有用例因字段改名（`monthDay` → `monthDays`）必须同步修改，不允许整条删除。
- `flutter analyze` 必须 0 error / 0 warning；`flutter test` 全绿。
- **不要跑 `dart format`** —— 工具链是新版 tall style，一跑就重排整个文件、制造几百行无关 diff。
- 源码与文本 UTF-8（无 BOM）；代码注释用中文，解释「为什么」，不复述代码。
- 界面层只写角色令牌（`AppTokens` / `L10n`），不写字面量字号、颜色、间距、时长；触觉只挂在动作上，且**共享控件已经发过的不许在调用点再补**。
- 日期比较一律走 `dayNumber` / `isSameDay`（drift 读回来是本地 DateTime，直接比 `DateTime` 会差时区）。
- 改 Drift 表后必须 `dart run build_runner build --delete-conflicting-outputs`，生成物（`app_database.g.dart`）一起提交。
- 所有用户可见钟点保持 24 小时制。
- 提交在 **beta** 分支；构建 APK 只能在主 checkout（worktree 会静默回退 debug 签名）。

## Review Focus

复核时最容易咬到用户、而普通单测不一定覆盖的五个输入 / 状态，各自落在指定任务里：

1. **2 月同时选了 29 / 30 / 31**：必须只生成一天（夹到月末再按日期去重），不能同一天冒两条 —— Task 2。
2. **只属于「已经结束的时段」的班次**：不能出现在可选列表里（否则选中一条从今往后永不触发的规则） —— Task 4。
3. **班次被改名 / 删除之后**：规则不崩、面板明确写出「当前排班表里没有『X』」 —— Task 4（可选列表）与 Task 12（面板提示）。
4. **库里没有任何排班 / 只有空白表**：选「按班次」后保存被挡下并给提示，不产生一条永不触发的规则 —— Task 8（控件）与 Task 10 / 11（保存校验）。
5. **按天调班把某天改成 / 改离所选班次**：发生日跟着覆盖走（`ScheduleChain.shiftOn` 已包含覆盖，测试钉住这一点） —— Task 3 与 Task 5。

---

### Task 1: schema 15 —— 新增 `month_days` / `shift_names`，删掉 `month_day`

**Files:**
- Modify: `app/lib/data/app_database.dart`（`RecurringSeriesRows`、`schemaVersion`、`onUpgrade`）
- Test: `app/test/migration_v14_to_v15_test.dart`（新建）
- Generated: `app/lib/data/app_database.g.dart`（build_runner）

**Interfaces:**
- Produces: `RecurringSeriesRows.monthDays`（`IntColumn`，默认 0）、`RecurringSeriesRows.shiftNames`（可空 `TextColumn`）；`schemaVersion == 15`；`monthDay` 列从表定义里删除。

- [ ] **Step 1: 写迁移测试（先让它红）**

在 `migration_v14_to_v15_test.dart` 里用 `sqlite3.openInMemory()` 建一张 **v14 形态**的 `recurring_series_rows`（列：`id, title, time_minute, advance_remind_minutes, alarm_enabled, repeat_type, weekdays, month_day, start_date, skip_through, enabled, created_at`），种三行：每月 15 号、每天、每周一；`PRAGMA user_version = 14`。用 `AppDatabase.forTesting(NativeDatabase.opened(raw))` 打开，断言：

```dart
final rows = await db.select(db.recurringSeriesRows).get();
expect(rows[0].monthDays, 1 << 14);   // 每月 15 号 → 第 15 位
expect(rows[1].monthDays, 0);         // 每天
expect(rows[2].monthDays, 0);         // 每周
expect(rows.every((r) => r.shiftNames == null), isTrue);
final cols = await db.customSelect('PRAGMA table_info(recurring_series_rows)').get();
expect(cols.map((c) => c.data['name']), isNot(contains('month_day')));
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd app && flutter test test/migration_v14_to_v15_test.dart`
Expected: 编译失败 / `monthDays` 不存在。

- [ ] **Step 3: 改表定义与迁移**

`RecurringSeriesRows`：删 `monthDay`，加

```dart
IntColumn get monthDays => integer().withDefault(const Constant(0))();
TextColumn get shiftNames => text().nullable()();
```

`schemaVersion => 15`；`onUpgrade` 在最前面插一段：

```dart
if (from < 15) {
  // ⚠️ 必须排在 from < 11 之前；但表是 from < 11 那段才建的，所以先判版本。
  // ⚠️ addColumn 必须在 alterTable 之前：TableMigration 只拷「新旧表都有的列」，
  //    先重建的话 month_days 会拿到默认值 0、迁移数据全丢。
  if (from >= 11) {
    await m.addColumn(recurringSeriesRows, recurringSeriesRows.monthDays);
    await m.addColumn(recurringSeriesRows, recurringSeriesRows.shiftNames);
    await customStatement(
      'UPDATE recurring_series_rows '
      'SET month_days = (1 << (month_day - 1)) '
      'WHERE repeat_type = 2 AND month_day BETWEEN 1 AND 31',
    );
    await m.alterTable(TableMigration(recurringSeriesRows));
  }
}
```

跑 `dart run build_runner build --delete-conflicting-outputs`。

- [ ] **Step 4: 跑迁移测试与既有迁移测试**

Run: `cd app && flutter test test/migration_v14_to_v15_test.dart test/migration_v13_to_v14_test.dart test/migration_v10_to_v14_test.dart test/migration_v11_to_v13_test.dart`
Expected: 全 PASS（老版本 fixture 因 `from >= 11` 守卫跳过新分支；v10 及更早由 `from < 11` 按当前 schema 建表）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/data/app_database.dart app/lib/data/app_database.g.dart app/test/migration_v14_to_v15_test.dart
git commit -m "feat(db): 重复待办加 month_days / shift_names（schema 15）"
```

---

### Task 2: 领域层 —— 每月多选（`monthDays` 位掩码）

**Files:**
- Modify: `app/lib/domain/recurring_todo.dart`
- Modify: `app/lib/core/l10n.dart`（本任务新增全部新文案键，后续任务直接使用）
- Test: `app/test/recurring_todo_test.dart`

**Interfaces:**
- Produces:
  - `RecurringTodo.monthDays`（`int` 位掩码，构造参数同名），`monthDay` 删除。
  - `L10n.everyMonthOnDays(List<int> days)`、`L10n.monthDaysHint`、`L10n.repeatShift`、`L10n.shiftRuleHint`、`L10n.shiftRuleNoSchedule`、`L10n.shiftRuleMissing(List<String> names)`、`L10n.everyShift(List<String> names)`、`L10n.ruleNeedsShift`、`L10n.ruleNeedsMonthDay`；`L10n.repeatNone` 英文改 `Never`。

- [ ] **Step 1: 写失败用例**

在 `recurring_todo_test.dart` 增两组：

```dart
group('每月多选', () {
  test('每月 1 号与 15 号：前后查询各取最近的一天', () {
    final s = _s(repeat: RecurRepeat.monthly,
        monthDays: (1 << 0) | (1 << 14));
    expect(occurrenceOnOrBefore(s, DateTime.utc(2026, 3, 20)),
        DateTime.utc(2026, 3, 15));
    expect(occurrenceOnOrBefore(s, DateTime.utc(2026, 3, 10)),
        DateTime.utc(2026, 3, 1));
    expect(nextOccurrenceAfter(s, DateTime.utc(2026, 3, 1)),
        DateTime.utc(2026, 3, 15));
  });

  test('2 月选 29/30/31：夹到月末并去重，只出现一天', () {
    final s = _s(repeat: RecurRepeat.monthly,
        monthDays: (1 << 28) | (1 << 29) | (1 << 30));
    expect(occurrenceOnOrBefore(s, DateTime.utc(2027, 2, 28)),
        DateTime.utc(2027, 2, 28));
    expect(nextOccurrenceAfter(s, DateTime.utc(2027, 2, 28)),
        DateTime.utc(2027, 3, 29)); // 3 月：29/30/31 各自成立
  });

  test('monthDays == 0 是脏数据，不出发生日', () {
    expect(occurrenceOnOrBefore(
        _s(repeat: RecurRepeat.monthly, monthDays: 0), DateTime.utc(2026, 9, 1)),
        isNull);
  });

  test('ruleLabel 拼出多天', () {
    expect(
      _s(repeat: RecurRepeat.monthly, monthDays: (1 << 0) | (1 << 14))
          .ruleLabel,
      L10n.everyMonthOnDays([1, 15]),
    );
  });
});
```

现有所有 `monthDay: d` 的构造改写成 `monthDays: 1 << (d - 1)`（含 `_s` 辅助函数的默认值）。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd app && flutter test test/recurring_todo_test.dart`
Expected: 编译失败（`monthDays` 未定义）。

- [ ] **Step 3: 实现**

`RecurringTodo`：字段与构造参数改名；`copyWith` 同步。新增私有辅助：

```dart
List<int> _monthDaysOf(int mask) =>
    [for (var d = 1; d <= 31; d++) if ((mask & (1 << (d - 1))) != 0) d];

/// 某年某月里，多选日夹到月末并去重后的日期（升序）。month 可溢出。
List<DateTime> _monthlyCandidates(int year, int month, int mask) {
  final last = DateTime.utc(year, month + 1, 0).day;
  final days = <int>{
    for (final d in _monthDaysOf(mask)) d <= last ? d : last,
  }.toList()..sort();
  return [for (final d in days) DateTime.utc(year, month, d)];
}
```

`firstOccurrenceOnOrAfter` / `occurrenceOnOrBefore` 的 monthly 分支改用候选列表：前者逐月（0..23）找第一个 `daysBetween(base, c) >= 0` 的；后者逐月倒找最后一个 `daysBetween(c, d) >= 0` 且不早于 `startDate` 的；`monthDays == 0` 返回 null。`ruleLabel` 的 monthly 分支用 `L10n.everyMonthOnDays(_monthDaysOf(monthDays))`（为空时退回 `L10n.repeatMonthly`）。

L10n 新键（中 / 英）按 spec §8 的表格逐字添加；`repeatNone` 英文改 `Never`。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd app && flutter test test/recurring_todo_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/domain/recurring_todo.dart app/lib/core/l10n.dart app/test/recurring_todo_test.dart
git commit -m "feat(todo): 每月重复支持多选日期"
```

---

### Task 3: 领域层 —— 按班次重复

**Files:**
- Modify: `app/lib/domain/recurring_todo.dart`
- Test: `app/test/recurring_todo_test.dart`

**Interfaces:**
- Produces:
  - `enum RecurRepeat { daily, weekly, monthly, shift }`
  - `RecurringTodo.shiftNames`（`List<String>`，构造参数同名，默认 `const []`）
  - `String? Function(DateTime day)?` 形式的 `shiftNameOn` 可选参数，加到 `firstOccurrenceOnOrAfter` / `occurrenceOnOrBefore` / `nextOccurrenceAfter` / `upcomingFireTimes`。

- [ ] **Step 1: 写失败用例**

```dart
group('按班次', () {
  final shift = _s(repeat: RecurRepeat.shift, shiftNames: ['上夜班']);
  String? night(DateTime d) => d.weekday == DateTime.wednesday ? '上夜班' : '白班';

  test('发生日 = 班次名匹配的那天（前后都找）', () {
    expect(occurrenceOnOrBefore(shift, DateTime.utc(2026, 9, 25), shiftNameOn: night),
        DateTime.utc(2026, 9, 23));
    expect(nextOccurrenceAfter(shift, DateTime.utc(2026, 9, 20), shiftNameOn: night),
        DateTime.utc(2026, 9, 23));
  });

  test('没给 resolver / 名字为空：一律无发生日', () {
    expect(occurrenceOnOrBefore(shift, DateTime.utc(2026, 9, 25)), isNull);
    expect(occurrenceOnOrBefore(
        _s(repeat: RecurRepeat.shift, shiftNames: const []),
        DateTime.utc(2026, 9, 25), shiftNameOn: night), isNull);
  });

  test('多选：任一班次名命中都算', () {
    final s = _s(repeat: RecurRepeat.shift, shiftNames: ['上夜班', '白班']);
    expect(occurrenceOnOrBefore(s, DateTime.utc(2026, 9, 22), shiftNameOn: night),
        DateTime.utc(2026, 9, 22));
  });

  test('ruleLabel 用班次名字拼，不带日期', () {
    expect(shift.ruleLabel, L10n.everyShift(['上夜班']));
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd app && flutter test test/recurring_todo_test.dart --plain-name 按班次`
Expected: `RecurRepeat.shift` 不存在。

- [ ] **Step 3: 实现**

```dart
/// 按班次规则向后 / 向前扫描的上界。周期最长 60 天；「其余时间 = 无」时
/// 可能出现很长的空档，400 天足够覆盖一个完整轮转季。
const int _shiftScanDays = 400;
```

- `_matchesShift(s, day, shiftNameOn)`：`shiftNameOn == null || s.shiftNames.isEmpty` 返回 false；否则 `s.shiftNames.contains(shiftNameOn(day))`。
- `firstOccurrenceOnOrAfter`：`repeat == shift` 时从 `base` 起 `i <= _shiftScanDays` 逐天找（`_addDays`），命中返回 `c`；找不到 null。
- `occurrenceOnOrBefore`：从 `d` 向前扫，遇到 `daysBetween(start, c) < 0` 或扫满 400 天返回 null。
- `nextOccurrenceAfter` / `upcomingFireTimes` 把 `shiftNameOn` 透传下去。
- `ruleLabel` 的 shift 分支 `L10n.everyShift(shiftNames)`；`shiftNames` 为空时退回 `L10n.repeatShift`。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd app && flutter test test/recurring_todo_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/domain/recurring_todo.dart app/test/recurring_todo_test.dart
git commit -m "feat(todo): 按班次重复的发生日查询"
```

---

### Task 4: `ScheduleChain.classChoicesFrom`

**Files:**
- Modify: `app/lib/domain/schedule_chain.dart`
- Test: `app/test/schedule_chain_test.dart`

**Interfaces:**
- Produces: `List<ShiftClass> classChoicesFrom(DateTime day)` —— 按名字去重、按「那天归谁的方案 → 兜底 → 时段终点 ≥ day 的段」顺序收集。

- [ ] **Step 1: 写失败用例**

```dart
test('classChoicesFrom：今天起的方案并集、按名字去重，已结束时段的方案不贡献选项', () {
  final chain = ScheduleChain(
    fallback: _schedule(name: '主表', classes: ['白班', '夜班']),
    spans: [
      _span(schedule: _schedule(name: '旧表', classes: ['白班', '旧夜班']),
          from: DateTime.utc(2026, 1, 1), to: DateTime.utc(2026, 8, 31)),
      _span(schedule: _schedule(name: '新表', classes: ['白班', '新夜班']),
          from: DateTime.utc(2026, 10, 1)),
    ],
  );
  final names = chain
      .classChoicesFrom(DateTime.utc(2026, 9, 15))
      .map((c) => c.name)
      .toList();
  expect(names, ['白班', '夜班', '新夜班']); // 旧夜班不出现、白班只出现一次
});
```

（`_schedule` / `_span` 用测试文件里已有的辅助或按 `ShiftSchedule` 的构造参数补。）

- [ ] **Step 2: 跑测试确认失败**

Run: `cd app && flutter test test/schedule_chain_test.dart --plain-name classChoicesFrom`
Expected: 方法不存在。

- [ ] **Step 3: 实现**

```dart
/// 从 [day] 起**还可能生效**的方案里的班次（按名字去重）。
///
/// 已结束时段的方案（`to < day`）不参与 —— 选中那种班次等于造一条从今往后
/// 永不触发的规则，而界面上完全看不出来。
List<ShiftClass> classChoicesFrom(DateTime day) {
  final out = <ShiftClass>[];
  final seen = <String>{};
  void add(ShiftSchedule? s) {
    if (s == null) return;
    for (final c in s.classes) {
      if (seen.add(c.name)) out.add(c);
    }
  }
  add(scheduleOn(day));
  add(fallback);
  for (final s in spans) {
    if (s.to == null || dayNumber(s.to!) >= dayNumber(day)) add(s.schedule);
  }
  return out;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd app && flutter test test/schedule_chain_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/domain/schedule_chain.dart app/test/schedule_chain_test.dart
git commit -m "feat(schedule): 提供从某天起可选的班次列表"
```

---

### Task 5: 仓库层 —— 映射、写入、生成器、面板数据

**Files:**
- Modify: `app/lib/data/app_repository.dart`
- Test: `app/test/recurring_repository_test.dart`、`app/test/advance_recurring_test.dart`

**Interfaces:**
- Produces:
  - `RecurringSeriesRowX.toDomain()` 带出 `monthDays` 与 `shiftNames`（JSON 解码失败按空列表处理）。
  - `addRecurringTodo({..., int monthDays = 0, List<String> shiftNames = const []})`
  - `updateRecurringTodo(RecurringTodo s)` 写入两列。
  - `advanceRecurringTodos` 内部用 `getActiveSchedules()?.chain.shiftOn(d)?.name` 作为 `shiftNameOn`。
  - `class RecurringPanelData { final List<RecurringTodo> series; final ScheduleChain? chain; }`
  - `final recurringPanelProvider = FutureProvider.autoDispose<RecurringPanelData>(...)`

- [ ] **Step 1: 写失败用例**

`recurring_repository_test.dart`：

```dart
test('按班次系列：链上那天是上夜班时生成当前这一次', () async {
  // 建一套今天=上夜班的排班（复用现有 seedSchedule / addRecurringTodo 辅助）
  final id = await repo.addRecurringTodo(
    title: '带工牌', repeat: RecurRepeat.shift, startDate: dateOnly(today),
    shiftNames: ['上夜班']);
  await repo.advanceRecurringTodos(today: today);
  final live = (await repo.listEvents()).where((e) => e.seriesId == id);
  expect(live.single.date, dayNumber(dateOnly(today)));
});
```

`advance_recurring_test.dart`：加一条「当天排班改成休班之后，按班次规则不再生成新行（已有行留在原地）」。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd app && flutter test test/recurring_repository_test.dart`
Expected: 参数 `shiftNames` 不存在 / 生成器不认 shift。

- [ ] **Step 3: 实现**

- `toDomain`：`monthDays: monthDays`，`shiftNames: (shiftNames == null || shiftNames!.isEmpty) ? const [] : (jsonDecode(shiftNames!) as List).cast<String>()`，`jsonDecode` 失败吞掉返回 `const []`（脏数据不崩）。
- 写入两列：`monthDays: Value(s.monthDays)`、`shiftNames: Value(s.shiftNames.isEmpty ? null : jsonEncode(s.shiftNames))`。
- `advanceRecurringTodos` 开头：

```dart
final schedules = await getActiveSchedules();
final shiftNameOn = schedules == null
    ? null
    : (DateTime d) => schedules.chain.shiftOn(d)?.name;
```

  然后 `occurrenceOnOrBefore(s, today, shiftNameOn: shiftNameOn)`。
- 新增 `RecurringPanelData` 与 `recurringPanelProvider`（放在 `recurringTodosProvider` 旁边），一次读系列 + `getActiveSchedules()`。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd app && flutter test test/recurring_repository_test.dart test/advance_recurring_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/data/app_repository.dart app/test/recurring_repository_test.dart app/test/advance_recurring_test.dart
git commit -m "feat(todo): 仓库层支持按班次与每月多选的读写"
```

---

### Task 6: 提醒链路 —— `shiftNameOn` 透传 + 待办页补排重复提醒

**Files:**
- Modify: `app/lib/features/alarm/alarm_service.dart`
- Test: `app/test/recurring_alarm_plan_test.dart`

**Interfaces:**
- Produces:
  - `planRecurringReminders(..., {String? Function(DateTime day)? shiftNameOn})`
  - `rescheduleRecurringReminders(List<RecurringTodo> series, {String? Function(DateTime day)? shiftNameOn})`
  - `rescheduleTodoReminders(AppRepository repo)` —— 一次性 + 重复提醒一起排（待办页增删改后调用）。
  - `replanAfterScheduleChange(AppRepository repo)` —— 先 `advanceRecurringTodos` 再 `rescheduleAll`。

- [ ] **Step 1: 写失败用例**

`recurring_alarm_plan_test.dart`：

```dart
test('按班次系列：只在接班次的日子排提醒', () {
  final series = _s(
    id: 7, repeat: RecurRepeat.shift, shiftNames: ['上夜班'],
    timeMinute: 7 * 60, advance: 0);
  String? night(DateTime d) => d.weekday == DateTime.wednesday ? '上夜班' : '白班';
  final plans = planRecurringReminders([series],
      from: DateTime(2026, 9, 21, 8), shiftNameOn: night);
  expect(plans.single.fireAt, DateTime(2026, 9, 23, 7));
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd app && flutter test test/recurring_alarm_plan_test.dart --plain-name 按班次`
Expected: 参数不存在。

- [ ] **Step 3: 实现**

- `planRecurringReminders` / `rescheduleRecurringReminders` 各加可选参数并透传。
- `rescheduleAll` 里 `await rescheduleRecurringReminders(..., shiftNameOn: (d) => schedules.chain.shiftOn(d)?.name);`
- `rescheduleTodoReminders(repo)`：读 `getActiveSchedules()` 与 `listRecurringTodos()`，先 `rescheduleEventReminders(await repo.listEvents())`，再 `rescheduleRecurringReminders(series, shiftNameOn: ...)`。
- `replanAfterScheduleChange(repo)`：`await repo.advanceRecurringTodos(today: dateOnly(DateTime.now())); await rescheduleAll(repo);`

- [ ] **Step 4: 跑测试**

Run: `cd app && flutter test test/recurring_alarm_plan_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/alarm/alarm_service.dart app/test/recurring_alarm_plan_test.dart
git commit -m "feat(alarm): 重复提醒按班次解析 + 待办页补排重复提醒"
```

---

### Task 7: 星期选择器 —— 一行七格等宽

**Files:**
- Modify: `app/lib/core/widgets/glass_weekday_picker.dart`
- Test: `app/test/glass_weekday_picker_test.dart`（新建）

**Interfaces:**
- Produces: 控件外观变化；对外 API（`value` / `onChanged`）不变。

- [ ] **Step 1: 写失败用例**

```dart
testWidgets('七个星期格子在 360dp 下排成一行、等宽、间距 ≥ 4', (tester) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(
      child: SizedBox(width: 320, child: GlassWeekdayPicker(value: 0, onChanged: _noop))))));
  final rects = [
    for (var i = 0; i < 7; i++)
      tester.getRect(find.byType(AnimatedContainer).at(i)),
  ];
  expect(rects.map((r) => r.top).toSet().length, 1); // 同一行
  for (var i = 1; i < 7; i++) {
    expect(rects[i].left - rects[i - 1].right, greaterThanOrEqualTo(4));
  }
  expect(rects.first.width, closeTo(rects.last.width, 0.01));
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd app && flutter test test/glass_weekday_picker_test.dart`
Expected: 出现两个 top（折成两行）。

- [ ] **Step 3: 实现**

把 `Wrap` 换成 `Row`：每个格子 `Expanded`，格子之间 `SizedBox(width: 4)`；`AnimatedContainer` 的 `horizontal` 内边距去掉、改为内容居中；文字外包 `FittedBox(fit: BoxFit.scaleDown)`。视觉配方（选中实心主色、未选淡染 + 描边、圆角 `radiusL`、`durMed`）逐字保留。补一条注释：`它同时被自定义闹钟的「每周」浮层用着，两处同一套行为。`

- [ ] **Step 4: 跑测试确认通过**

Run: `cd app && flutter test test/glass_weekday_picker_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/widgets/glass_weekday_picker.dart app/test/glass_weekday_picker_test.dart
git commit -m "style(todo): 星期选择器改成一行七格等宽"
```

---

### Task 8: 规则选择器 —— 五档 + 按班次 chips

**Files:**
- Modify: `app/lib/features/schedule/recurring_fields.dart`
- Test: `app/test/recurring_dialog_test.dart`

**Interfaces:**
- Produces:

```dart
class RecurRuleValue {
  const RecurRuleValue({
    required this.repeat,
    this.weekdays = 0,
    this.monthDays = 0,
    this.shiftNames = const [],
  });
  final RecurRepeat? repeat;
  final int weekdays;
  final int monthDays;
  final List<String> shiftNames;
}

class RecurringRulePicker extends StatelessWidget {
  const RecurringRulePicker({
    super.key,
    required this.value,
    required this.shiftChoices,
    required this.fallbackDay,
    required this.fallbackShiftName,
    required this.onChanged,
    this.validationMessage,
  });
}
```

- [ ] **Step 1: 写失败用例**

```dart
testWidgets('五档规则：切到按班次后列出班次、勾选后回传名字', (tester) async {
  RecurRuleValue? out;
  await pumpDialog(tester, RecurringRulePicker(
    value: const RecurRuleValue(repeat: RecurRepeat.daily),
    shiftChoices: [白班, 上夜班],   // ShiftClass 夹具
    fallbackDay: DateTime(2026, 9, 23),
    fallbackShiftName: '白班',
    onChanged: (v) => out = v,
  ));
  await tester.tap(find.text(L10n.repeatShift));
  await tester.pumpAndSettle();
  expect(find.text('白班'), findsOneWidget);
  expect(find.text(L10n.shiftRuleHint), findsOneWidget);
  await tester.tap(find.text('上夜班'));
  await tester.pumpAndSettle();
  expect(out!.shiftNames, contains('上夜班'));
});

testWidgets('没有任何班次时给指路，validationMessage 会显示', (tester) async {
  await pumpDialog(tester, RecurringRulePicker(
    value: const RecurRuleValue(repeat: RecurRepeat.shift),
    shiftChoices: const [],
    fallbackDay: DateTime(2026, 9, 23),
    fallbackShiftName: null,
    onChanged: (_) {},
    validationMessage: L10n.ruleNeedsShift,
  ));
  expect(find.text(L10n.shiftRuleNoSchedule), findsOneWidget);
  expect(find.text(L10n.ruleNeedsShift), findsOneWidget);
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd app && flutter test test/recurring_dialog_test.dart --plain-name 五档规则`
Expected: 构造参数不存在。

- [ ] **Step 3: 实现**

- `GlassSegment(count: 5, ...)`，项依次 `repeatNone / repeatDaily / repeatWeekly / repeatMonthly / repeatShift`；切到 weekly 补星期（现有逻辑）；切到 monthly 且 `monthDays == 0` 补 `1 << (fallbackDay.day - 1)`；切到 shift 且 `shiftNames` 为空时选 `fallbackShiftName`（不在 choices 里则取第一个，choices 为空则不选）。
- shift 分支：`Wrap` + `GlassChoiceChip`（可选班次）；缺名（`shiftNames` 里不在 `shiftChoices` 名字集合里的）用 `Theme.of(context).colorScheme.error` 渲染成已选 chip；下方依次是 `L10n.shiftRuleHint`、缺名提示 `L10n.shiftRuleMissing`、无班次指路 `L10n.shiftRuleNoSchedule`（按条件显示）。
- `validationMessage != null` 时在最后显示一行 error 色小字。
- 每颗 chip 的点击只调用 `onChanged`，**不再补触觉**（`GlassChoiceChip` 自己发）。
- 每月分支暂时保留旧的单日 `ListTile`（Task 9 替换），但读写 `monthDays`。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd app && flutter test test/recurring_dialog_test.dart --plain-name 五档规则`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/schedule/recurring_fields.dart app/test/recurring_dialog_test.dart
git commit -m "feat(todo): 规则选择器加按班次一档"
```

---

### Task 9: 每月多选网格

**Files:**
- Modify: `app/lib/features/schedule/recurring_fields.dart`
- Test: `app/test/recurring_dialog_test.dart`

**Interfaces:**
- Consumes: `RecurRuleValue.monthDays`。
- Produces: 每月分支换成 31 格网格；点掉最后一天不生效。

- [ ] **Step 1: 写失败用例**

```dart
testWidgets('每月多选 1 与 15、点掉最后一天不生效', (tester) async {
  RecurRuleValue? out;
  await pumpDialog(tester, RecurringRulePicker(
    value: const RecurRuleValue(repeat: RecurRepeat.monthly, monthDays: 1),
    shiftChoices: const [], fallbackDay: DateTime(2026, 9, 23),
    fallbackShiftName: null, onChanged: (v) => out = v,
  ));
  await tester.tap(find.widgetWithText(InkWell, '15')); // 网格格子的实际类型按实现取
  await tester.pumpAndSettle();
  expect(out!.monthDays, (1 << 0) | (1 << 14));
  await tester.tap(find.widgetWithText(InkWell, '1'));
  await tester.tap(find.widgetWithText(InkWell, '15'));
  await tester.pumpAndSettle();
  expect(out!.monthDays, isNot(0)); // 最后一个不许被点掉
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd app && flutter test test/recurring_dialog_test.dart --plain-name 每月多选`
Expected: 找不到网格。

- [ ] **Step 3: 实现**

私有 `_MonthDayGrid({required int value, required ValueChanged<int> onChanged})`：

- `Column` × 5 行、每行 `Row` × 7 个 `Expanded` 格子；格子 `AnimatedContainer`（选中 = 主色实心 + 白字，未选 = 现有淡染 + 描边，圆角 `radiusS`），`FittedBox(scaleDown)` 包数字；
- 点击：`Haptics.select()`；若点击的是最后一个已选项（`value` 只有这一位），不回调；
- 网格下方 `L10n.monthDaysHint` 小字。
- 去掉旧的每月 `ListTile` 与 `showGlassOptionPicker` 调用。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd app && flutter test test/recurring_dialog_test.dart`
Expected: PASS（含原有重复弹窗用例，需同步 `monthDays` 字段）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/schedule/recurring_fields.dart app/test/recurring_dialog_test.dart
git commit -m "feat(todo): 每月重复改成多选网格"
```

---

### Task 10: 系列编辑器接线

**Files:**
- Modify: `app/lib/features/schedule/recurring_series_editor.dart`
- Test: `app/test/recurring_panel_test.dart`、`app/test/recurring_dialog_test.dart`

**Interfaces:**
- Consumes: `RecurRuleValue`、`recurringPanelProvider` 之外的 `repo.getActiveSchedules()`、`ScheduleChain.classChoicesFrom`、`occurrenceOnOrBefore(..., shiftNameOn:)`。

- [ ] **Step 1: 写失败用例**

```dart
testWidgets('系列编辑器：改每月多选并保存，库里是新的掩码', (tester) async { ... });
testWidgets('系列编辑器：按班次且没选班次时保存被挡下、提示可见', (tester) async {
  // 打开一个 shiftNames 为空的系列，点保存
  expect(find.text(L10n.ruleNeedsShift), findsOneWidget);
  // 库里仍未写入/仍未关闭
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd app && flutter test test/recurring_panel_test.dart --plain-name 系列编辑器`
Expected: 失败。

- [ ] **Step 3: 实现**

- state 增加 `_monthDays`、`_shiftNames`、`_shiftChoices`、`_fallbackShiftName`、`_validation`；`initState` 里 `repo.getActiveSchedules()` 读一次并 `setState`（用 `mounted` 守卫）。
- `RecurringRulePicker` 传入上述值；`onChanged` 更新 state 并清掉 `_validation`。
- `_save`：先校验（shift 且 `shiftNames.isEmpty` → `L10n.ruleNeedsShift`；monthly 且 `monthDays == 0` → `L10n.ruleNeedsMonthDay`），无效只 `setState` 显示提示、不写库不关窗。
- `ruleChanged` 增加 `_monthDays != widget.series.monthDays || !listEquals(_shiftNames, widget.series.shiftNames)`。
- 对齐：`occurrenceOnOrBefore(s, today, shiftNameOn: chain == null ? null : (d) => chain.shiftOn(d)?.name)`。
- 打开老数据时补齐：`monthDays == 0` → `1 << (fallbackDay.day - 1)`；shift 且空 → 默认班次（同控件逻辑）。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd app && flutter test test/recurring_panel_test.dart test/recurring_dialog_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/schedule/recurring_series_editor.dart app/test/recurring_panel_test.dart app/test/recurring_dialog_test.dart
git commit -m "feat(todo): 系列编辑器支持按班次与每月多选"
```

---

### Task 11: 待办新建 / 编辑弹窗接线

**Files:**
- Modify: `app/lib/features/schedule/schedule_screen.dart`
- Test: `app/test/recurring_dialog_test.dart`、`app/test/recurring_screen_test.dart`

**Interfaces:**
- Consumes: `RecurRuleValue`、`recurringPanelProvider` 之外的一次性读、`AlarmService.rescheduleTodoReminders(repo)`。

- [ ] **Step 1: 写失败用例**

```dart
testWidgets('新建待办选每月 1/15：保存后系列与当前这一次都在', (tester) async { ... });
testWidgets('新建待办选按班次、没选班次时保存被挡下', (tester) async { ... });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd app && flutter test test/recurring_dialog_test.dart --plain-name 新建待办`
Expected: 失败。

- [ ] **Step 3: 实现**

- `_EventFields` 字段：`int monthDays`、`List<String> shiftNames`、`List<ShiftClass> shiftChoices`、`String? fallbackShiftName`；构造参数同步；`build` 传 `RecurRuleValue`。
- `_showAddDialog` 改 `async`：先 `repo.getActiveSchedules()` 取 choices / 当天班次，再 `showGlassDialog`。
- `showEditEventDialog` 同样读 choices（它已经 async）。
- `commit`：`addRecurringTodo` / `updateRecurringTodo` 传 `monthDays`、`shiftNames`；对齐时带 `shiftNameOn`（读一次 `getActiveSchedules()`）。
- `_rescheduleReminders` 改成 `await AlarmService.rescheduleTodoReminders(repo);`（一次性 + 重复一起排）。
- 保存校验与系列编辑器同一套（提示显示在规则控件下方）。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd app && flutter test test/recurring_dialog_test.dart test/recurring_screen_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/schedule/schedule_screen.dart app/test/recurring_dialog_test.dart app/test/recurring_screen_test.dart
git commit -m "feat(todo): 待办弹窗支持按班次与每月多选"
```

---

### Task 12: 重复待办面板 —— 去铅笔、按班次的下一次与缺名提示

**Files:**
- Modify: `app/lib/features/schedule/recurring_panel.dart`
- Test: `app/test/recurring_panel_test.dart`、`app/test/recurring_panel_narrow_test.dart`

**Interfaces:**
- Consumes: `recurringPanelProvider`（Task 5）。

- [ ] **Step 1: 写失败用例**

```dart
testWidgets('面板行尾不再有铅笔图标', (tester) async { ... expect(find.byIcon(Icons.edit_outlined), findsNothing); });
testWidgets('按班次系列：当前排班表没有这个班次时给出提示', (tester) async { ... });
testWidgets('按班次系列：下次时间按班次算', (tester) async { ... });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd app && flutter test test/recurring_panel_test.dart`
Expected: 失败。

- [ ] **Step 3: 实现**

- 删掉 `editHint` getter 与两处相关注释。
- `_RecurringList` 改看 `recurringPanelProvider`；`_row` 接收 `ScheduleChain? chain`。
- `next = nextOccurrenceAfter(s, today, shiftNameOn: chain == null ? null : (d) => chain.shiftOn(d)?.name)`。
- 缺名：`missing = s.shiftNames.where((n) => !chain.classChoicesFrom(today).any((c) => c.name == n))`；非空时在标题行下方加一行 error 色 `L10n.shiftRuleMissing(missing)`（`maxLines: 2`）。
- 窄窗分支同步（两行版式里那行提示放在 texts 里）。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd app && flutter test test/recurring_panel_test.dart test/recurring_panel_narrow_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/schedule/recurring_panel.dart app/test/recurring_panel_test.dart app/test/recurring_panel_narrow_test.dart
git commit -m "feat(todo): 面板按班次显示下一次与缺名提示，去掉铅笔"
```

---

### Task 13: 排班变化的入口统一走 `replanAfterScheduleChange`

**Files:**
- Modify: `app/lib/features/calendar/schedule_management_screen.dart`
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Test: `app/test/recurring_advance_hooks_test.dart`

**Interfaces:**
- Consumes: `AlarmService.replanAfterScheduleChange(repo)`（Task 6）。

- [ ] **Step 1: 写失败用例**

在 `recurring_advance_hooks_test.dart` 增一条：在排班管理页换「其余时间」后，按班次系列在当天的行立刻出现（或 `advanceRecurringTodos` 被调用）。判据落在**数据库结果**上，不落在「有没有调用某个函数」。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd app && flutter test test/recurring_advance_hooks_test.dart`
Expected: 失败。

- [ ] **Step 3: 实现**

把三处 `AlarmService.rescheduleAll(repo)` 换成 `AlarmService.replanAfterScheduleChange(repo)`：
- `schedule_management_screen.dart` 的 `_replanAlarms`；
- `schedule_editor_screen.dart` 保存（约 2221 行）；
- `calendar_screen.dart` 应用改班 / 恢复轮转（约 1222 行）。

其余调用点不动（闹钟页、我的页、设置变化都没有改「某天上什么班」）。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd app && flutter test test/recurring_advance_hooks_test.dart test/schedule_management_test.dart test/schedule_editor_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/calendar/schedule_management_screen.dart app/lib/features/calendar/schedule_editor_screen.dart app/lib/features/calendar/calendar_screen.dart app/test/recurring_advance_hooks_test.dart
git commit -m "fix(todo): 改排班后同步重算按班次待办"
```

---

### Task 14: 文案、帮助、更新日志、版本号

**Files:**
- Modify: `app/lib/core/l10n.dart`（`guide...` 里那句「每天 / 每周几 / 每月某日」）
- Modify: `app/lib/features/profile/help_content.dart`（FAQ 补一条）
- Modify: `app/lib/features/profile/app_dialogs.dart`（更新日志 prepend、保持 10 条）
- Modify: `app/lib/core/app_info.dart`、`app/pubspec.yaml`
- Test: `app/test/changelog_window_test.dart`、`app/test/app_info_test.dart`

- [ ] **Step 1: 改文案与版本**

- `guide` 那句改成「每天 / 每周几 / 每月哪几天 / 按班次」；
- `help_content.dart` 按「我想办一件事」加一条：怎么让待办跟着班次走（去待办页 → 新建 → 重复 → 按班次 → 勾班次）；
- 更新日志 prepend `0.12.3` 条目（测试版原样、不归纳），删最旧一条；
- `pubspec.yaml` → `0.12.3+178`，`app_info.dart` → `0.12.3`。

- [ ] **Step 2: 跑护栏**

Run: `cd app && flutter test test/changelog_window_test.dart test/app_info_test.dart`
Expected: PASS。

- [ ] **Step 3: Commit**

```bash
git add app/lib/core/l10n.dart app/lib/core/app_info.dart app/lib/features/profile/help_content.dart app/lib/features/profile/app_dialogs.dart app/pubspec.yaml
git commit -m "chore(release): v0.12.3 文案与版本"
```

---

### Task 15: 视觉工装

**Files:**
- Modify: `app/tool/visual/visual_screens.dart`
- Generated: `app/build/visual/*.png`

- [ ] **Step 1: 更新屏单**

- `65_recurring_series_editor`：seed 一条按班次系列（上夜班 + 下夜班），打开后停在「按班次」；
- 新增 `66_recurring_monthly_days`：seed 每月 1/15 的系列，打开后拍网格；
- `25_recurring_panel`：seed 至少一条按班次系列（含缺名的那一档单独一条屏或变体）。

- [ ] **Step 2: 出图并看图**

Run: `cd app && flutter test tool/visual/`
Expected: 全 PASS；逐张打开 `65/66/25` 与 `06_alarm*`（共享星期选择器）的浅色 / 深色 / 英文 / 小窗图，确认没有折行、溢出、对比度问题。

- [ ] **Step 3: 跑字号护栏**

Run: `cd app && flutter test tool/visual/text_fit_guard_test.dart`
Expected: 0 失败；新屏在 320/360 × 四档字号 × 中英下无截断。若报出省略，按 v0.11.12 的降级顺序（折行 > 按宽缩小 > 换短串）修。

- [ ] **Step 4: Commit**

```bash
git add app/tool/visual/visual_screens.dart
git commit -m "test(visual): 按班次与每月多选的工装屏"
```

---

### Task 16: 全量验收、真机、发版

- [ ] **Step 1: 静态检查与全量测试**

Run: `cd app && flutter analyze`
Expected: 0 error / 0 warning。
Run: `cd app && flutter test`
Expected: 全绿（1106 + 新增）。

- [ ] **Step 2: 真机验收（ADB 已连接）**

先量现状并截图（work/adb-shots），构建安装：

```bash
cd app && flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

在真机上验：七格一行、按班次新建 + 勾选 + 提醒时间、每月 1/15 两条、系列编辑器改规则、面板无铅笔、换排班表后按班次待办跟着变。设备锁屏时请用户解锁。

- [ ] **Step 3: 更新 AGENTS.md**

补版本史一条与「最近改动」一段（含三条用户反馈、匹配口径、迁移与验证数字）。

- [ ] **Step 4: 提交、打 tag、发布**

```bash
git add -A && git commit -m "docs(agents): v0.12.3 记录" && git tag v0.12.3
git push origin beta && git push origin v0.12.3
scripts/release.ps1 -SkipConfirm
```

发布说明先写到 `tools/gh/release-notes-v0.12.3.md`。发完 curl `latest.json` 核对 `latest.json` 的 beta 通道版本；若 8b 步失败按 AGENTS 的手动流程补 main。

---

## Self-Review

**Spec coverage**

- §2.1 五档 / English 文案 → Task 2、Task 8。
- §2.2 匹配口径 / 空白表 / 跨方案 → Task 3、Task 4、Task 5。
- §2.3 查询函数与扫描上界、前移不变量 → Task 3、Task 5。
- §2.4 每月多选 / 至少一天 / 去重 → Task 2、Task 9。
- §3 schema 15 与迁移 → Task 1。
- §4.1 可选班次来源 → Task 4；加载方式 → Task 10、11、12。
- §4.2 班次 chips / 缺名 / 口径说明 / 默认勾选 → Task 8。
- §4.3 保存校验与老数据补齐 → Task 10、11（控件在 Task 8 显示提示）。
- §4.4 面板去铅笔 / 缺名 / 下次 → Task 12。
- §4.5 排班变化入口 → Task 13。
- §5 每月网格 → Task 9。
- §6 星期格子 → Task 7。
- §7 提醒链路与既有缺口 → Task 6。
- §8 文案 → Task 2（键）/ Task 14（帮助）。
- §9 验收 → 各任务用例 + Task 15 / 16。
- §10 版本发布 → Task 14 / 16。

**Step scan**：每一步都指向一个可执行的命令或一个明确的改动；没有「适当处理」「加上验证」这类空话。测试断言带具体值（掩码、日期、文案键）。

**Type consistency**：`monthDays` / `shiftNames` / `shiftNameOn` / `classChoicesFrom` / `RecurRuleValue` / `recurringPanelProvider` / `rescheduleTodoReminders` / `replanAfterScheduleChange` 在前后任务中同名同签名。

**Review Focus 对应**：1 → Task 2 用例；2 → Task 4 用例；3 → Task 12 用例 + Task 4 列表判据；4 → Task 8 提示 + Task 10/11 校验；5 → Task 3 / 5 的 `shiftOn` 用例。

**Proportion**：计划约 600 行、spec 约 260 行；代码块以签名与测试断言为主，没有抄实现正文。
