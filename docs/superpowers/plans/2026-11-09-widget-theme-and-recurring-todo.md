# 小组件跟随深浅色 + 重复待办挂班次那天 —— 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 桌面三张卡在 App 主题为「跟随系统」时自动切深浅色；重复待办的行挂回发生日（班次那天），打勾 / 删除后提醒真正停止。

**Architecture:** 小组件把颜色改成「主题感知」——API 31+ 用 `setColorInt` 日夜双值 + `-night` drawable，由桌面在配置变化时重新应用；App 存活时运行时接收器兜底。重复待办把「发生日」与「提醒时刻」彻底分开：行日期 = 发生日，提醒仍按 `alarmDayAnchor` 落点；`skipThrough` 同时被生成器与排提醒读取。

**Tech Stack:** Flutter / Dart、Drift、Riverpod、Kotlin / RemoteViews、Android AppWidget。

**Spec:** `docs/superpowers/specs/2026-11-09-widget-theme-and-recurring-todo-design.md`

## Global Constraints

- 版本：`0.12.10+185` → `0.12.11+186`；`X.Y` 由用户定，只动 `Z` 与 `build`。
- 不改表结构、不跑 `build_runner`、不升 schemaVersion。
- 用例里的日期/时钟一律走 `appNow()` + `kAnchor`；不写 `DateTime.now()`。
- 扫源码的断言一律用 `test/support/source_scan.dart` 的 `blankNonCode()`（会剥注释与字符串）。
- Kotlin 用户可见文案全部来自快照；中文字面量只允许出现在 `AlarmLog` 日志里。
- 发布构建只能在主 checkout 做（`app/android/keystore/release.jks` 与 `key.properties` 不在 worktree 里）。
- `flutter analyze` 0 error / 0 warning；`flutter test` 全绿；`EXPECTED_TESTS` 按尾行 `+N` 改，不推算。
- 不跑 `dart format`（会重排整个文件）。

## Review Focus

- **勾错了 → 撤销 / 取消勾选**：那一次的提醒必须回来，不能留下一个永远不响的水位线。
- **「以后不再重复」**：跨午夜系列解绑成一次性后，提醒的绝对时刻不能挪 24 小时。
- **冷启动**：重复待办的提醒不能在启动重排里被取消后不再排回来。
- **旧归档行**：升级后不能显示「11月10日 · 上夜班 · 次日 02:00」这种指错发生日的标记。
- **API < 31**：不能出现「背景翻了、字没翻」的半翻卡片。

---

## Task 1: 小组件主题感知（收口诊断代码）

**Files:**
- Modify: `android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`
- Modify: `android/app/src/main/kotlin/com/daoban/shiftassistantpro/MainActivity.kt`
- Modify: `android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRefreshReceiver.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/main/res/drawable/widget_dot_empty.xml`
- Create: `android/app/src/main/res/drawable-night/widget_dot_empty.xml`
- Test: `test/widget_theme_follow_test.dart`

**Interfaces:**
- Consumes: 现有的 `WidgetRenderer.isDark(context, themeMode)`、`ShiftWidgets.refreshAll(context)`。
- Produces: `WidgetRenderer` 内部私有 `themedColor(rv, id, system, dark, light, night)` 与 `cardBackground/pageBackground/cellBackground(system, dark): Int`；不对外暴露。

- [ ] **Step 1: 写失败用例**

创建 `test/widget_theme_follow_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

String _read(String path) => File(path).readAsStringSync();

const String _kt = 'android/app/src/main/kotlin/com/daoban/shiftassistantpro';

void main() {
  test('跟随系统的四份资源在 drawable/ 与 drawable-night/ 都有', () {
    for (final name in [
      'widget_card_auto',
      'widget_page_auto',
      'widget_cell_auto',
      'widget_dot_empty',
    ]) {
      expect(File('android/app/src/main/res/drawable/$name.xml').existsSync(),
          true, reason: '缺 $name.xml');
      expect(
          File('android/app/src/main/res/drawable-night/$name.xml').existsSync(),
          true,
          reason: '缺 drawable-night/$name.xml');
    }
  });

  test('中性文字色走 setColorInt，且只在 API 31+ 用 -night', () {
    final kt = blankNonCode(_read('$_kt/WidgetRenderer.kt'));
    expect(kt.contains('setColorInt'), true, reason: '文字色必须日夜双值');
    expect(kt.contains('Build.VERSION_CODES.S'), true,
        reason: 'API < 31 没有 setColorInt，必须版本分档');
    // 剥壳之后只许剩：helper 的兜底 1 处 + 3 处纯主色/班次色的字。
    expect(RegExp(r'\.setTextColor\(').allMatches(kt).length,
        lessThanOrEqualTo(4),
        reason: '中性色不许再走裸 setTextColor —— 那样系统切色不会跟');
  });

  test('manifest 不再声明 CONFIGURATION_CHANGED', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    expect(manifest.contains('CONFIGURATION_CHANGED'), false,
        reason: '隐式广播收不到，留着是死代码');
  });

  test('MainActivity 保留运行时接收器并成对注销', () {
    final kt = blankNonCode(_read('$_kt/MainActivity.kt'));
    expect(kt.contains('Intent.ACTION_CONFIGURATION_CHANGED'), true);
    expect(kt.contains('registerReceiver'), true);
    expect(kt.contains('unregisterReceiver'), true);
  });
}
```

- [ ] **Step 2: 跑用例确认失败**

Run: `cd app && flutter test test/widget_theme_follow_test.dart`
Expected: FAIL —— 缺 `widget_dot_empty` 两份、`Build.VERSION_CODES.S` 还没进背景 helper、manifest 还留着 intent-filter。

- [ ] **Step 3: 实现**

1. 新建 `drawable/widget_dot_empty.xml` 与 `drawable-night/widget_dot_empty.xml`：`<shape android:shape="oval">` + `<solid>`，亮色用 `@color/wg_empty_light`、暗色用 `@color/wg_empty_dark`（12dp 圆点，无需描边）。
2. `WidgetRenderer.kt` 的三个背景 helper 改成：

```kotlin
private fun auto(system: Boolean): Boolean =
    system && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

private fun cardBackground(system: Boolean, dark: Boolean): Int =
    if (auto(system)) R.drawable.widget_card_auto
    else if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light
// pageBackground / cellBackground 同形
```

3. `renderTodayCard` 里「没班次」的圆点：`auto(system)` 时改走
   `v.setImageViewResource(R.id.wg_tc_dot, R.drawable.widget_dot_empty)`；
   否则保留现在的 `WidgetChip.circle(...)` 烤位图。`d.hasShift` 那一支不变。
4. 删 `WidgetRefreshReceiver.kt` 的 `Intent.ACTION_CONFIGURATION_CHANGED` 分支；
   删 `AndroidManifest.xml` 里 `WidgetRefreshReceiver` 的 intent-filter。
5. 保留 `MainActivity.kt` 的运行时注册/注销（诊断版已有）。
6. 把 `WidgetRenderer.kt` 顶部「纪律 2」改成：2026-11-09 实测 MIUI 宿主会重新应用 RemoteViews，`-night` 在 API 31+ 可用；API < 31 仍不走 `-night`。

- [ ] **Step 4: 跑用例确认通过**

Run: `cd app && flutter test test/widget_theme_follow_test.dart`
Expected: PASS（4 条）。

- [ ] **Step 5: 真机复验**

```bash
export JAVA_HOME="$PWD/toolchain/jdk" ANDROID_HOME="$PWD/toolchain/android-sdk" GRADLE_USER_HOME="$PWD/toolchain/gradle-home" PUB_CACHE="$PWD/toolchain/pub-cache" TEMP="$PWD/tools/tmp" TMP="$PWD/tools/tmp" PATH="$PWD/toolchain/flutter/bin:$PWD/toolchain/jdk/bin:$PWD/toolchain/android-sdk/platform-tools:$PATH"
cd app && flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am force-stop com.daoban.shiftassistantpro
adb shell cmd uimode night no && adb exec-out screencap -p > ../tools/tmp/t1-light.png
adb shell cmd uimode night yes && adb exec-out screencap -p > ../tools/tmp/t1-dark.png
adb shell cmd uimode night auto
```

Expected: 两次截图三张卡都跟着变；`adb logcat -d -s ShiftAssistant:D` 在 force-stop 后切换**没有任何**本 App 日志。

- [ ] **Step 6: Commit**

```bash
git add app/android app/test/widget_theme_follow_test.dart
git commit -m "feat(widget): 跟随系统深浅色——主题感知渲染 + 运行时兜底"
```

---

## Task 2: 行日期 = 发生日 + 一次性迁移

**Files:**
- Modify: `lib/domain/recurring_todo.dart`（`todoDisplayDay` → `legacyDisplayDayForMigration`）
- Modify: `lib/data/app_repository.dart`（`advanceRecurringTodos`、新增 `migrateLegacyRecurringRowDays`）
- Create: `lib/core/migration_flags.dart`
- Modify: `lib/features/home/home_shell.dart`
- Test: `test/todo_shift_row_day_test.dart`（重写）、`test/todo_migration_test.dart`（新建）

**Interfaces:**
- Produces:
  - `DateTime legacyDisplayDayForMigration(RecurringTodo s, DateTime occ, {ShiftClass? shift})`
  - `Future<void> AppRepository.migrateLegacyRecurringRowDays()`
  - `Future<bool> legacyRecurringRowDayMigrated()` / `Future<void> markLegacyRecurringRowDayMigrated()`（`lib/core/migration_flags.dart`）

- [ ] **Step 1: 重写/新增失败用例**

`test/todo_shift_row_day_test.dart` 的生成器组改成：

```dart
test('夜班 + 00:00：行挂 9/23（班次日），提醒仍在 9/24 00:00', () async {
  await repo.addRecurringTodo(
    title: '交班记录',
    repeat: RecurRepeat.shift,
    startDate: DateTime(2026, 9, 23),
    shiftNames: const ['夜班'],
    timeMinute: 0,
    advanceRemindMinutes: 0,
  );
  await repo.advanceRecurringTodos(today: DateTime(2026, 9, 23));
  final rows = await repo.listEvents();
  expect(rows, hasLength(1));
  expect(dayNumber(rows.single.date), dayNumber(DateTime(2026, 9, 23)),
      reason: '行属于班次，不跟着提醒走');
  final s = (await repo.listRecurringTodos()).single;
  expect(
      upcomingFireTimes(s,
              from: DateTime(2026, 9, 23, 20),
              clockMinute: 0,
              shiftOn: (d) => d.day == 23 ? _night : null)
          .first,
      DateTime(2026, 9, 24, 0, 0));
});

test('反复推进不会多插一行（9/23 → 9/25）', () async {
  await repo.addRecurringTodo(/* 同上 */);
  await repo.advanceRecurringTodos(today: DateTime(2026, 9, 23));
  await repo.advanceRecurringTodos(today: DateTime(2026, 9, 24));
  expect(dayNumber((await repo.listEvents()).single.date), dayNumber(DateTime(2026, 9, 23)));
  await repo.advanceRecurringTodos(today: DateTime(2026, 9, 25));
  expect(dayNumber((await repo.listEvents()).single.date), dayNumber(DateTime(2026, 9, 25)));
});
```

新建 `test/todo_migration_test.dart`：

```dart
test('旧行 9/24 迁回发生日 9/23；手工挪到 9/25 的行不动', () async {
  final sid = await repo.addRecurringTodo(
    title: '交班记录', repeat: RecurRepeat.shift,
    startDate: DateTime(2026, 9, 23), shiftNames: const ['夜班'],
    timeMinute: 0, advanceRemindMinutes: 0,
  );
  Future<int> insert(DateTime d, {bool done = false}) =>
      db.into(db.scheduleEvents).insert(ScheduleEventsCompanion.insert(
            title: '交班记录', date: d,
            timeMinute: const Value(0),
            advanceRemindMinutes: const Value(0),
            seriesId: Value(sid), isCompleted: Value(done),
            createdAt: appNow(),
          ));
  final oldId = await insert(DateTime.utc(2026, 9, 24), done: true);
  final manualId = await insert(DateTime.utc(2026, 9, 27));

  await repo.migrateLegacyRecurringRowDays();

  final rows = {for (final r in await repo.listEvents()) r.id: r};
  expect(dayNumber(rows[oldId]!.date), dayNumber(DateTime(2026, 9, 23)),
      reason: '归档行也要迁 —— 否则班次标记会指到错误的发生日');
  expect(dayNumber(rows[manualId]!.date), dayNumber(DateTime(2026, 9, 27)),
      reason: '不是旧显示日的行（手工挪过）不许动');
  expect(isPendingTodoOn(rows[manualId]!, DateTime(2026, 9, 27)), true,
      reason: '徽章跟着行日期走：跨午夜待办挂在班次日');
});

test('迁移标记只置位一次', () async {
  SharedPreferences.setMockInitialValues({});
  expect(await legacyRecurringRowDayMigrated(), false);
  await markLegacyRecurringRowDayMigrated();
  expect(await legacyRecurringRowDayMigrated(), true);
});
```

（`useFixedNow()`、`appNow()`、`kAnchor`、`SharedPreferences.setMockInitialValues` 照 `test/alarm_reschedule_budget_test.dart` 的搭法。）

- [ ] **Step 2: 跑用例确认失败**

Run: `cd app && flutter test test/todo_shift_row_day_test.dart test/todo_migration_test.dart`
Expected: FAIL —— 行日期还是 9/24；`migrateLegacyRecurringRowDays` 不存在。

- [ ] **Step 3: 实现**

1. `recurring_todo.dart`：把 `todoDisplayDay` 改名为 `legacyDisplayDayForMigration`，正文不变，KDoc 改成「只给一次性迁移与解绑用，新行不要用」。
2. `app_repository.dart` 的 `advanceRecurringTodos`：
   - 删除 `final day = todoDisplayDay(...)`；
   - 插入行用 `date: occ`；
   - 顺延比较改回 `daysBetween(keep.date, occ) > 0`，写 `date: Value(occ)`。
3. 新增迁移（放在 `advanceRecurringTodos` 附近）：
   - 读 `getActiveSchedules()` 取 `shiftOn`；
   - 事务里对每个 `repeat == shift && timeMinute != null` 的系列，遍历它**所有**行（含归档）；
   - 对 `d in [-1, 0, 1]` 构造 `occ = DateTime.utc(row.date.year, row.date.month, row.date.day + d)`，若 `shiftOn(occ)` 的班次名在 `s.shiftNames` 里，且 `dayNumber(legacyDisplayDayForMigration(s, occ, shift: shift)) == dayNumber(row.date)`，收进候选；
   - **恰好一个**候选且不等于 `row.date` → 写回候选日；多个候选 → 不动，`AlarmLog` 不需要（Dart 层用 `debugPrint` 或直接跳过）。
4. `lib/core/migration_flags.dart`：两个函数，键 `recurringRowDayMigratedV1`。
5. `home_shell._tryStartupReschedule`：在 `advanceRecurringTodos` **之前**加

```dart
if (!await legacyRecurringRowDayMigrated()) {
  await repo.migrateLegacyRecurringRowDays();
  await markLegacyRecurringRowDayMigrated();
}
```

- [ ] **Step 4: 跑用例确认通过**

Run: `cd app && flutter test test/todo_shift_row_day_test.dart test/todo_migration_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib app/test/todo_shift_row_day_test.dart app/test/todo_migration_test.dart
git commit -m "fix(todo): 行挂回发生日——按班次的重复待办不再跟着提醒走"
```

---

## Task 3: 排提醒读 skipThrough + 取消勾选还回来

**Files:**
- Modify: `lib/domain/recurring_todo.dart`（`upcomingFireTimes`）
- Modify: `lib/data/app_repository.dart`（`setEventCompleted`）
- Modify: `lib/features/schedule/schedule_screen.dart`（`_restoreCompleted`）
- Test: `test/recurring_alarm_plan_test.dart`（加）、`test/recurring_uncheck_test.dart`（新建）

**Interfaces:**
- Consumes: Task 2 的 `dayNumber` 口径（行日期 = 发生日）。
- Produces: `upcomingFireTimes` 跳过 `dayNumber(occ) <= skipThrough` 的发生日。

- [ ] **Step 1: 写失败用例**

`test/recurring_alarm_plan_test.dart` 加：

```dart
test('skipThrough 覆盖到的那一次不排', () {
  final s = _s(repeat: RecurRepeat.daily, timeMinute: 9 * 60).copyWith(
      skipThrough: dayNumber(DateTime(2026, 9, 23)));
  final plans = planRecurringReminders([s], from: DateTime(2026, 9, 23, 8));
  expect(plans.single.fireAt, DateTime(2026, 9, 24, 9));
});
```

新建 `test/recurring_uncheck_test.dart`：建一个 daily 系列（`timeMinute: 23 * 60`、`advanceRemindMinutes: 0`），`advanceRecurringTodos(today: dateOnly(kAnchor))` 拿到行。用 `from: DateTime(2026, 9, 23, 8)` 算计划（今天 23:00 还没到）：

- `setEventCompleted(row, true)` 后：计划队首是 9/24 23:00；
- 读系列，`skipThrough == dayNumber(9/23)`；
- `setEventCompleted(row, false)` 后：`skipThrough == null`，计划队首回到 9/23 23:00。

- [ ] **Step 2: 跑用例确认失败**

Run: `cd app && flutter test test/recurring_alarm_plan_test.dart test/recurring_uncheck_test.dart`
Expected: FAIL —— 计划仍包含被跳过的那次；取消勾选后水位线还在。

- [ ] **Step 3: 实现**

1. `upcomingFireTimes` 的 `while` 循环开头：

```dart
if (s.skipThrough != null && dayNumber(occ) <= s.skipThrough!) {
  occ = nextOccurrenceAfter(s, occ, shiftOn: shiftOn);
  continue;
}
```

2. `setEventCompleted` 在 `!done && sid != null` 时：读系列行，若 `skipThrough == dayNumber(e.date)`，写成 `Value(null)`；更高则不动。
3. `schedule_screen._restoreCompleted` 改为 `await AlarmService.rescheduleTodoReminders(repo);`（不再只排一次性）。

- [ ] **Step 4: 跑用例确认通过**

Run: `cd app && flutter test test/recurring_alarm_plan_test.dart test/recurring_uncheck_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib app/test/recurring_alarm_plan_test.dart app/test/recurring_uncheck_test.dart
git commit -m "fix(todo): 打勾后不再响——排提醒读 skipThrough，取消勾选清水位线"
```

---

## Task 4: 冷启动把重复提醒排回来

**Files:**
- Modify: `lib/features/home/home_shell.dart`
- Test: `test/startup_reschedule_guard_test.dart`（新建）

**Interfaces:**
- Consumes: `AlarmService.rescheduleAll(AppRepository)`（已存在，= `reschedule` + `rescheduleRecurringReminders`）。

- [ ] **Step 1: 写失败用例**

```dart
test('冷启动路径必须走 rescheduleAll，不能只走 reschedule', () {
  final src = blankNonCode(
      File('lib/features/home/home_shell.dart').readAsStringSync());
  expect(src.contains('AlarmService.rescheduleAll('), true);
  expect(src.contains('AlarmService.reschedule('), false,
      reason: 'reschedule 会取消重复待办提醒却不排回来');
});
```

- [ ] **Step 2: 跑用例确认失败**

Run: `cd app && flutter test test/startup_reschedule_guard_test.dart`
Expected: FAIL —— 现在调的是 `AlarmService.reschedule(`。

- [ ] **Step 3: 实现**

`_tryStartupReschedule` 末尾把 `AlarmService.reschedule(chain, alarms, overrides: ..., events: ...)` 换成 `await AlarmService.rescheduleAll(repo);`；删掉不再使用的 `overrides` 读取与 `events` 二次读取（`chain` / `alarms` / `events` 顶部的就绪判断保留）。

- [ ] **Step 4: 跑用例确认通过**

Run: `cd app && flutter test test/startup_reschedule_guard_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/home/home_shell.dart app/test/startup_reschedule_guard_test.dart
git commit -m "fix(alarm): 冷启动把重复待办提醒排回来"
```

---

## Task 5: 解绑保持一次性提醒的绝对时刻

**Files:**
- Modify: `lib/data/app_repository.dart`（`unlinkRecurringSeries`）
- Test: `test/recurring_unlink_test.dart`（新建）

**Interfaces:**
- Consumes: `legacyDisplayDayForMigration`（Task 2）、`eventReminderTime(ScheduleEvent)`。

- [ ] **Step 1: 写失败用例**

```dart
test('夜班 02:00 的系列解绑后，一次性提醒仍在次日 02:00', () async {
  final sid = await repo.addRecurringTodo(
    title: '写台账', repeat: RecurRepeat.shift,
    startDate: DateTime(2026, 9, 23), shiftNames: const ['夜班'],
    timeMinute: 2 * 60, advanceRemindMinutes: 0,
  );
  await repo.advanceRecurringTodos(today: DateTime(2026, 9, 23));
  await repo.unlinkRecurringSeries(sid);
  final row = (await repo.listEvents()).single;
  expect(row.seriesId, isNull);
  expect(AlarmService.eventReminderTime(row), DateTime(2026, 9, 24, 2, 0),
      reason: '解绑不能把提醒挪 24 小时');
});
```

- [ ] **Step 2: 跑用例确认失败**

Run: `cd app && flutter test test/recurring_unlink_test.dart`
Expected: FAIL —— 现在 `eventReminderTime` 是 9/23 02:00（早 24 小时）。

- [ ] **Step 3: 实现**

`unlinkRecurringSeries(id)`：解绑前读出系列与 `chain`，找该系列**未完成**的那一行；若系列是 `repeat == shift && timeMinute != null`，把行日期改成 `legacyDisplayDayForMigration(s, 行日期, shift: chain?.shiftOn(行日期))`（与当前不同才写）。然后照旧解绑全部行、删系列。

- [ ] **Step 4: 跑用例确认通过**

Run: `cd app && flutter test test/recurring_unlink_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/data/app_repository.dart app/test/recurring_unlink_test.dart
git commit -m "fix(todo): 解绑重复系列时保住一次性提醒的绝对时刻"
```

---

## Task 6: 行副标题加「班次名 · 次日」

**Files:**
- Modify: `lib/features/schedule/schedule_screen.dart`（`_eventTile` 的 `subtitle`）
- Test: `test/todo_shift_marker_test.dart`（改）

**Interfaces:**
- Consumes: 现有的 `markedClock` / `shift` / `todoReminderClockLabel` 四道闸门。

- [ ] **Step 1: 改失败用例**

把「按班次 + 夜班 + 00:00」那条改成：

```dart
expect(find.textContaining(L10n.monthDayWeekday(dateOnly(kAnchor))), findsOneWidget,
    reason: '行挂在班次那天');
expect(
    find.textContaining('夜班 · ${L10n.clockNextDay('00:00')}'), findsOneWidget,
    reason: '副标题把班次名与提醒落点一起写清楚；标题「夜班写台账」不会匹配到这一段');
```

- [ ] **Step 2: 跑用例确认失败**

Run: `cd app && flutter test test/todo_shift_marker_test.dart`
Expected: FAIL —— 行还在次日、没有班次名。

- [ ] **Step 3: 实现**

`subtitle` 的列表改成：

```dart
final subtitle = [
  L10n.monthDayWeekday(e.date),
  if (markedClock != null && shift != null) shift.name,
  if (timeText != null) timeText,
  if (e.advanceRemindMinutes != null)
    L10n.remindOptionLabel(e.advanceRemindMinutes!),
].join(' · ');
```

`markedClock` 的四道闸门不动。

- [ ] **Step 4: 跑用例确认通过**

Run: `cd app && flutter test test/todo_shift_marker_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/schedule/schedule_screen.dart app/test/todo_shift_marker_test.dart
git commit -m "feat(todo): 行副标题标出班次名与次日提醒"
```

---

## Task 7: 版本、文档、全套验证、发布

**Files:**
- Modify: `app/pubspec.yaml`、`app/lib/core/app_info.dart`
- Modify: `app/lib/features/profile/app_dialogs.dart`
- Modify: `.github/workflows/ci.yml`（`EXPECTED_TESTS`）
- Modify: `docs/decisions/widget.md`、`docs/decisions/todo.md`
- Modify: `docs/changelog/v0.12.md`
- 已新增：spec 与 plan 两份

**Steps:**

- [ ] **Step 1: 版本号**

`version: 0.12.11+186`；`appVersion = '0.12.11'`。

- [ ] **Step 2: 更新日志**

`_changelogZh/_changelogEn` prepend v0.12.11 一条（小组件跟随系统、重复待办日期与提醒），删最旧一条、保持 10 条。

- [ ] **Step 3: 决策记录**

- `docs/decisions/widget.md` 末尾加：2026-11-09 实测（AOSP 不重应用、MIUI 会；manifest 死路；API 31+ 用 `setColorInt`/`-night`，<31 烤死）。
- `docs/decisions/todo.md` 末尾加：行挂发生日（撤销 2026-11-05「行跟着提醒走」）；`skipThrough` 生成器与排提醒都要读；取消勾选清水位线；解绑改日期；冷启动走 `rescheduleAll`。

- [ ] **Step 4: 全套验证**

```bash
cd app && flutter analyze
cd app && flutter test
```

Expected: analyze 0 error / 0 warning；全套全绿。记下尾行 `+N`。

- [ ] **Step 5: 同步 EXPECTED_TESTS**

把 `.github/workflows/ci.yml` 的 `EXPECTED_TESTS` 改成 Step 4 尾行的实际数（不推算）。

- [ ] **Step 6: 构建与真机复验**

```bash
export JAVA_HOME="$PWD/toolchain/jdk" ANDROID_HOME="$PWD/toolchain/android-sdk" GRADLE_USER_HOME="$PWD/toolchain/gradle-home" PUB_CACHE="$PWD/toolchain/pub-cache" TEMP="$PWD/tools/tmp" TMP="$PWD/tools/tmp" PATH="$PWD/toolchain/flutter/bin:$PWD/toolchain/jdk/bin:$PWD/toolchain/android-sdk/platform-tools:$PATH"
cd app && flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

真机检查：① 三张卡切深浅色自动翻转（App 进程杀掉后）；② 夜班 02:00 的重复待办在班次日出现、副标题「上夜班 · 次日 02:00」；③ 勾选后到次日照常不响。

- [ ] **Step 7: 提交、tag、发布**

⚠️ 工作区里还有**上一次规范层工作**的未提交改动（`AGENTS.md`、`BUILD.md`、`docs/standards/*`、`scripts/standards_check.py`、`visual.yml`）。**不要 `git add -A`** —— 只加本轮路径。`ci.yml` 里那一条注释改动（去掉写死的 1284）是上一次留下的，会让本轮一起带上；它只改注释，可以接受，交付说明里讲一句。

```bash
git add app/pubspec.yaml app/lib/core/app_info.dart app/lib/core/migration_flags.dart \
  app/lib/domain/recurring_todo.dart app/lib/data/app_repository.dart \
  app/lib/features/home/home_shell.dart app/lib/features/schedule/schedule_screen.dart \
  app/lib/features/profile/app_dialogs.dart app/android .github/workflows/ci.yml \
  app/test docs/decisions/widget.md docs/decisions/todo.md docs/changelog/v0.12.md \
  docs/superpowers/specs/2026-11-09-widget-theme-and-recurring-todo-design.md \
  docs/superpowers/plans/2026-11-09-widget-theme-and-recurring-todo.md
git commit -m "chore(release): v0.12.11"
git tag v0.12.11
git push origin beta
git push origin v0.12.11
scripts/release.ps1 -SkipConfirm
```

发完 `curl` 一次 `raw.githubusercontent.com/.../main/latest.json`，核对 beta 通道版本号。

---

## Self-Review

**Spec coverage**

- §2 小组件主题感知：Task 1（含 API 分档、空圆点、manifest 删除、运行时接收器、真机复验）。
- §3.1–3.2 行 = 发生日：Task 2。
- §3.3 一次性迁移（含归档行）：Task 2。
- §3.4 打勾不响 + 取消勾选还回来：Task 3。
- §3.5 水位线口径：Task 2/3。
- §3.6 副标题班次名 + 次日：Task 6。
- §3.9A 冷启动：Task 4。
- §3.9B 解绑保时刻：Task 5。
- §3.8 徽章跟行日期：Task 2 的 `isPendingTodoOn` 断言（生成器用例已间接覆盖；Task 2 Step 1 可加一条 `expect(isPendingTodoOn(rows.single, DateTime(2026,9,23)), true)`）。
- §5 测试：每个 Task 的 Step 1/4。
- §6 发布：Task 7。

**Review Focus 对应**

- 勾错撤销 → Task 3 的 uncheck 用例。
- 解绑 24 小时 → Task 5。
- 冷启动 → Task 4。
- 旧归档行 → Task 2 的迁移用例（含 `done: true` 行）。
- API < 31 半翻 → Task 1 的 `Build.VERSION_CODES.S` 守卫 + 真机（设备是 31+，<31 只能靠源码守卫；真机不可覆盖，接受并在交付说明里讲明）。
