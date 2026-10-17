# 班次闹钟三档落点 + 每班 10 条 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让班次联动闹钟的落点从「前一天 / 当天」两档扩到三档（多出「次日」），使中班 16:30–次日 00:30 的 00:15 与 01:00 落在正确的那一天；同时把每班闹钟上限从 6 提到 10。

**Architecture:** 判定收在一个新的纯函数 `alarmDayAnchor(ShiftClass, ShiftAlarm) → AlarmDayAnchor { prev, same, next }`，落点由 `shiftAlarmFireAt` 按锚点偏移建日期；`planShiftAlarms` 与原生 id 算式一个字不动（`offset` 仍按班次那天）。上限改动只涉及一个 Dart 常量与 Kotlin 两处扫描上界。

**Tech Stack:** Flutter / Dart（domain 层纯 Dart，可单测）、Kotlin（RemoteViews 与 AlarmManager 侧无测试目标，靠源码扫描护栏 + 真机）。

**Spec:** `docs/superpowers/specs/2026-10-11-shift-alarm-anchor-and-cap-design.md`

## Global Constraints

- **版本号**：`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须同步（由 `app/test/app_info_test.dart` 盯着）。本轮是**测试版**：`0.11.0+147` → `0.11.1+148`。`X.Y` 不许动。
- **分支**：测试版一律在 `beta` 上做、提交、发布（`main` 只在发正式版时收合并）。
- **验收**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿且**只增不减**（当前 825 条）。
- **界面层不许写数值字面量**（`app/test/design_tokens_test.dart` 守门）：字号 / 字重 / `Color(0x…)` / `Circular(<n>)` / `Duration(milliseconds:)` / `Icon(size:)` / 非 4px 栅格的间距常量。新文案一律走 `L10n`。
- **除 `core/haptics.dart` 外，任何文件不许出现 `HapticFeedback.`。**
- **Drift 表没有任何改动** → 不需要 `dart run build_runner build`。
- **不要跑 `dart format`**（本仓工具链的格式化器会重排整个文件、制造几百行无关 diff）。只跑 `flutter analyze`。
- **`l10n.dart` 有意不 import 领域层**，所以 `alarmLimitReached` 里那个数字是手抄的，改上限时两处一起改。

## Review Focus

以下五类输入是这份规格隐含、而**任何单一任务的测试都不会自动覆盖**的；每一类都在 Task 1 里有对应的用例钉着：

1. **24 小时值班**（`span == 1440`，内置 `duty_24_24/48/72` 用）配的上班前闹钟 —— 期望仍是**班次当天**。没有 §3 那条例外，它会被排到「下班前 1 小时」，而这正是原稿犯的错。
2. **只填了上班时间**（`endMinute == null`）—— 窗口算不出来，期望退回两档、**永远不会是次日**。
3. **累计式 `endMinute`（≥1440）与回绕式（< startMinute）** —— 期望逐钟点同解（内置模板存回绕式、编辑器可产出 24:00）。
4. **正好等于下班钟点的闹钟** —— 期望落在那一刻本身（即次日），不是上班前。
5. **钟点晚于上班钟点的老约定** —— 期望仍是**前一天**（白班 22:00/23:00、00:00 班的 23:00）。

---

### Task 1: 三档锚点的纯规则与落点

**Files:**
- Modify: `app/lib/domain/shift_rotation.dart`（在 `alarmFallsOnPreviousDay` 一带，约 `:84-117`；`maxAlarmsPerShift` 在 `:82` 不动）
- Modify: `app/lib/features/alarm/alarm_service.dart`（`shiftAlarmFireAt`，`:83-90`）
- Test: `app/test/shift_rotation_test.dart`、`app/test/shift_alarm_decision_test.dart`

**Interfaces:**
- Produces:
  - `enum AlarmDayAnchor { prev, same, next }`（`domain/shift_rotation.dart`）
  - `AlarmDayAnchor alarmDayAnchor(ShiftClass shift, ShiftAlarm alarm)`（同文件，纯函数）
  - `shiftAlarmFireAt(DateTime date, ShiftClass shift, ShiftAlarm alarm) → DateTime`（签名不变，语义变三档）
- Consumes: `ShiftClass.startMinute` / `endMinute`、`ShiftAlarm.minute`
- **临时保留** `alarmFallsOnPreviousDay`，实现改成一行委托 `alarmDayAnchor(...) == AlarmDayAnchor.prev`，好让四个界面调用点在 Task 4 之前仍编得过。（Task 4 把它删掉。）

- [ ] **Step 1: 写失败的用例（纯规则）**

在 `app/test/shift_rotation_test.dart` 新增一组。判据**只断言枚举**：

```dart
group('alarmDayAnchor：三档落点', () {
  ShiftClass s(int? start, int? end) =>
      ShiftClass(name: 'x', startMinute: start, endMinute: end);
  const a = ShiftAlarm(minute: 0);

  test('中班 16:30–次日 00:30（回绕式）：班中与下班后都落次日', () {
    final m = s(990, 30);
    expect(alarmDayAnchor(m, ShiftAlarm(minute: 15)), AlarmDayAnchor.next);  // 00:15 班中
    expect(alarmDayAnchor(m, ShiftAlarm(minute: 60)), AlarmDayAnchor.next);  // 01:00 下班后
    expect(alarmDayAnchor(m, ShiftAlarm(minute: 510)), AlarmDayAnchor.same); // 08:30 阈值
    expect(alarmDayAnchor(m, ShiftAlarm(minute: 509)), AlarmDayAnchor.next); // 08:29
    expect(alarmDayAnchor(m, ShiftAlarm(minute: 960)), AlarmDayAnchor.same); // 16:00 上班前
  });

  test('同一条班次：累计式 endMinute 与回绕式同解', () {
    for (final t in [15, 60, 509, 510, 960, 1380]) {
      expect(alarmDayAnchor(s(990, 30), a.copyMinute(t)),
          alarmDayAnchor(s(990, 1470), a.copyMinute(t)),
          reason: '钟点 $t');
    }
  });

  test('夜班 20:30–次日 08:30：班中、正好下班、下班后都落次日', () {
    final n = s(1230, 510);
    expect(alarmDayAnchor(n, ShiftAlarm(minute: 120)), AlarmDayAnchor.next); // 02:00 班中
    expect(alarmDayAnchor(n, ShiftAlarm(minute: 510)), AlarmDayAnchor.next); // 08:30 正好下班
    expect(alarmDayAnchor(n, ShiftAlarm(minute: 540)), AlarmDayAnchor.next); // 09:00 下班后
    expect(alarmDayAnchor(n, ShiftAlarm(minute: 869)), AlarmDayAnchor.next); // 14:29 阈值上
    expect(alarmDayAnchor(n, ShiftAlarm(minute: 870)), AlarmDayAnchor.same); // 14:30 阈值
    expect(alarmDayAnchor(n, ShiftAlarm(minute: 1140)), AlarmDayAnchor.same);// 19:00 上班前
  });

  test('白班 08:00–20:00：晚于上班钟点的仍是前一天', () {
    final d = s(480, 1200);
    expect(alarmDayAnchor(d, ShiftAlarm(minute: 1380)), AlarmDayAnchor.prev); // 23:00
    expect(alarmDayAnchor(d, ShiftAlarm(minute: 1230)), AlarmDayAnchor.prev); // 20:30
    expect(alarmDayAnchor(d, ShiftAlarm(minute: 30)), AlarmDayAnchor.next);   // 00:30 凌晨
    expect(alarmDayAnchor(d, ShiftAlarm(minute: 300)), AlarmDayAnchor.same);  // 05:00
    expect(alarmDayAnchor(d, ShiftAlarm(minute: 480)), AlarmDayAnchor.same);  // 08:00 上班
  });

  test('24 小时值班：全天都算当天（含上班前的 07:00）', () {
    final duty = s(480, 1920);
    for (final t in [0, 420, 480, 720, 1320, 1439]) {
      expect(alarmDayAnchor(duty, ShiftAlarm(minute: t)), AlarmDayAnchor.same,
          reason: '钟点 $t');
    }
  });

  test('边界：没填下班 → 退回两档；没填上班 → 当天', () {
    expect(alarmDayAnchor(s(480, null), ShiftAlarm(minute: 1380)),
        AlarmDayAnchor.prev);
    expect(alarmDayAnchor(s(480, null), ShiftAlarm(minute: 360)),
        AlarmDayAnchor.same);
    expect(alarmDayAnchor(s(null, 1200), ShiftAlarm(minute: 60)),
        AlarmDayAnchor.same);
  });

  test('00:00 班：23:00 仍排前一天', () {
    expect(alarmDayAnchor(s(0, 480), ShiftAlarm(minute: 1380)),
        AlarmDayAnchor.prev);
  });
});
```

> `ShiftAlarm` 没有 `copyMinute`；第二条用例直接用 `ShiftAlarm(minute: t)` 构造，不要新增方法。

- [ ] **Step 2: 跑测试，确认它失败**

Run: `cd app && flutter test test/shift_rotation_test.dart`
Expected: 编译失败 —— `alarmDayAnchor` / `AlarmDayAnchor` 未定义。

- [ ] **Step 3: 实现 `AlarmDayAnchor` 与 `alarmDayAnchor`**

在 `domain/shift_rotation.dart` 里 `alarmFallsOnPreviousDay` 之后加枚举与函数。要点（规格 §3）：

```dart
enum AlarmDayAnchor { prev, same, next }

AlarmDayAnchor alarmDayAnchor(ShiftClass shift, ShiftAlarm alarm) {
  final s = shift.startMinute;
  if (s == null) return AlarmDayAnchor.same;      // 上班没填 → 判不了
  final t = alarm.minute;
  final e = shift.endMinute;
  if (e == null) return t > s ? AlarmDayAnchor.prev : AlarmDayAnchor.same; // 没窗口 → 两档
  final span = e > s ? e - s : e - s + _dayMinutes;
  // 窗口长度到一整天时「上班前」与「班次中」已经合并，保持既有行为
  if (span < _dayMinutes) {
    final rel = ((t - s) % _dayMinutes + _dayMinutes) % _dayMinutes;
    if (rel < span) {
      return s + rel >= _dayMinutes ? AlarmDayAnchor.next : AlarmDayAnchor.same;
    }
  }
  if (t > s) return AlarmDayAnchor.prev;
  final before = s - t;                      // D 落在窗口前多远
  final after = t + _dayMinutes - (s + span); // D+1 落在窗口后多远
  return after < before ? AlarmDayAnchor.next : AlarmDayAnchor.same;
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd app && flutter test test/shift_rotation_test.dart`
Expected: PASS（含既有用例 —— 它们测的还是老函数）。

- [ ] **Step 5: 让 `alarmFallsOnPreviousDay` 委托，好让界面编得过**

把它的函数体换成一行 `=> alarmDayAnchor(shift, alarm) == AlarmDayAnchor.prev;`。注释保留原有的三档规则说明，并补一句「这个布尔是过渡期的兼容层，Task 4 删」。

Run: `cd app && flutter analyze`
Expected: 0 error / 0 warning。

- [ ] **Step 6: 写失败的用例（落点日期）**

在 `app/test/shift_alarm_decision_test.dart` 新增一组。**断言的是日期与时刻，不是那个布尔值**：

```dart
group('shiftAlarmFireAt：三档落点', () {
  ShiftClass s(int? start, int? end) =>
      ShiftClass(name: 'x', startMinute: start, endMinute: end);
  final d = DateTime(2026, 10, 12);

  test('中班 16:30–次日 00:30：00:15 与 01:00 都落在次日', () {
    final m = s(990, 30);
    expect(shiftAlarmFireAt(d, m, const ShiftAlarm(minute: 15)),
        DateTime(2026, 10, 13, 0, 15));
    expect(shiftAlarmFireAt(d, m, const ShiftAlarm(minute: 60)),
        DateTime(2026, 10, 13, 1, 0));
  });

  test('夜班 20:30–次日 08:30：02:00 落在次日', () {
    expect(shiftAlarmFireAt(d, s(1230, 510), const ShiftAlarm(minute: 120)),
        DateTime(2026, 10, 13, 2, 0));
  });

  test('白班 08:00–20:00：23:00 仍落在前一天', () {
    expect(shiftAlarmFireAt(d, s(480, 1200), const ShiftAlarm(minute: 1380)),
        DateTime(2026, 10, 11, 23, 0));
  });

  test('24 小时值班：07:00 仍在班次当天（回归护栏）', () {
    expect(shiftAlarmFireAt(d, s(480, 1920), const ShiftAlarm(minute: 420)),
        DateTime(2026, 10, 12, 7, 0));
  });
});
```

Run: `cd app && flutter test test/shift_alarm_decision_test.dart`
Expected: 前两条那天数的那几例 FAIL（落在当天而不是次日）。

- [ ] **Step 7: 改 `shiftAlarmFireAt` 走锚点**

```dart
DateTime shiftAlarmFireAt(DateTime date, ShiftClass shift, ShiftAlarm alarm) {
  final delta = switch (alarmDayAnchor(shift, alarm)) {
    AlarmDayAnchor.prev => -1,
    AlarmDayAnchor.same => 0,
    AlarmDayAnchor.next => 1,
  };
  return DateTime(date.year, date.month, date.day + delta)
      .add(Duration(minutes: alarm.minute));
}
```

`DateTime(y, m, d + delta)` 而非 `add(Duration(days:))` —— 夏令时会把钟点挪掉一小时，既有注释在案。

- [ ] **Step 8: 跑这两份测试，确认全绿**

Run: `cd app && flutter test test/shift_rotation_test.dart test/shift_alarm_decision_test.dart`
Expected: PASS。

- [ ] **Step 9: 跑全套，确认没有别处被带红**

Run: `cd app && flutter test`
Expected: 全绿。若 `alarm_screen_test` / `calendar_screen_test` 红，看是不是它们断言了「次日那类闹钟不带标记」—— 那是 Task 4 的范围，**现在先不改**，把红的那条记下来。

- [ ] **Step 10: 提交**

```bash
git add app/lib/domain/shift_rotation.dart app/lib/features/alarm/alarm_service.dart app/test/shift_rotation_test.dart app/test/shift_alarm_decision_test.dart
git commit -m "feat(alarm): 闹钟落点扩到三档（前一天/当天/次日）"
```

---

### Task 2: 内置模板不换天的护栏

**Files:**
- Test: `app/test/shift_templates_test.dart`

**Interfaces:**
- Consumes: `alarmDayAnchor`（Task 1）、`shiftTemplateSpecs` / `ShiftTemplateSpec.toClass()`（既有）

- [ ] **Step 1: 写用例**

```dart
test('内置模板的闹钟一条都不换天（三档落点回归护栏）', () {
  final seen = <String>{};
  for (final spec in shiftTemplateSpecs) {
    for (final proto in spec.classes) {
      final c = proto.toClass();
      for (final a in c.alarms) {
        seen.add('${c.startMinute}-${c.endMinute}-${a.minute}'
            '=${alarmDayAnchor(c, a).name}');
      }
    }
  }
  expect(seen, {
    '510-1230-420=same',   // _d12 白班 07:00
    '1230-510-1140=same',  // _n12 夜班 19:00
    '480-960-420=same',    // _e8
    '960-1440-900=same',   // _m8
    '0-480-1380=prev',     // _n8
    '360-720-330=same',    // _e6
    '720-1080-690=same',   // _m6
    '1080-1440-1050=same', // _l6
    '0-360-1380=prev',     // _n6
    '480-1920-420=same',   // _duty 24 小时值班（靠 span>=1440 那条例外）
    '510-1050-450=same',   // _office
  });
});
```

- [ ] **Step 2: 跑它，确认通过**

Run: `cd app && flutter test test/shift_templates_test.dart`
Expected: PASS。**若失败，说明规则打到了某个模板 —— 停下来查 §3，别改这张表。**

- [ ] **Step 3: 反向验证（必须做）**

把 Task 1 Step 3 里那句 `if (span < _dayMinutes)` 的例外临时去掉，重跑：
Expected: `480-1920-420` 变成 `next`，用例当场红。**确认红过之后把例外加回去。**

- [ ] **Step 4: 提交**

```bash
git add app/test/shift_templates_test.dart
git commit -m "test(alarm): 钉住内置模板的闹钟落点不随三档规则漂移"
```

---

### Task 3: 每班闹钟上限 6 → 10

**Files:**
- Modify: `app/lib/domain/shift_rotation.dart:82`（`maxAlarmsPerShift` 与其上方注释）
- Modify: `app/lib/features/alarm/alarm_service.dart:271-277`、`:286-288`（注释里的 `0..400` 与过期行号）
- Modify: `app/lib/core/l10n.dart:513-517`（`alarmLimitReached`）
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/MainActivity.kt:604`、`:620`
- Modify（仅注释）：`AlarmStore.kt:191-192`、`WidgetRenderer.kt:77`、`:125`、`app/test/widget_fixed_cards_guard_test.dart:192`
- Test: `app/test/shift_alarm_decision_test.dart`

**Interfaces:**
- Produces: `maxAlarmsPerShift == 10`；原生扫描上界 `600`

- [ ] **Step 1: 改既有用例的上界断言，先看它红**

`shift_alarm_decision_test.dart:319-331`：用例名里的 `0..400` 改 `0..600`，`:323` 的 `lessThanOrEqualTo(400)` 改 `600`，`:330` 的 `inInclusiveRange(0, 400)` 改 `600`，`:324` 的注释里 `MainActivity.kt:550` 改 `MainActivity.kt:604`。

Run: `cd app && flutter test test/shift_alarm_decision_test.dart`
Expected: FAIL（`10 × 60 = 600` 不 ≤ 400…… 此时常量还是 6，所以先是 `horizon` 仍为 360、`inInclusiveRange` 仍过 —— **真正会红的是改常量之后**。这一步先把断言改到位，红在 Step 3）。

- [ ] **Step 2: 加一条扫源码的护栏**

```dart
test('原生扫描上界容得下 序号 × 天数窗口 的最大 id', () {
  final src = File('android/app/src/main/kotlin/com/daoban/shiftassistantpro/'
          'MainActivity.kt')
      .readAsStringSync();
  final scans = RegExp(r'for \(id in 0\.\.(\d+)\)').allMatches(src).toList();
  expect(scans.length, greaterThanOrEqualTo(2),
      reason: 'cancelAllNativeAlarms 与 cancelAllNotificationAlarms 两处都要扫');
  final maxId = maxAlarmsPerShift * AlarmService.shiftDaysHorizonForTesting - 1;
  for (final m in scans) {
    expect(int.parse(m.group(1)!), greaterThanOrEqualTo(maxId),
        reason: '扫描上界必须覆盖最大 id $maxId');
  }
});
```

Run: `cd app && flutter test test/shift_alarm_decision_test.dart`
Expected: PASS（现在 360-1 vs 400）。

- [ ] **Step 3: 改常量与 Kotlin，再跑**

- `shift_rotation.dart:82`：`const int maxAlarmsPerShift = 10;`，并把上方注释里的 `6 × 60 = 360 ≤ 400` 改成 `10 × 60 = 600 ≤ 600`、行号 `MainActivity.kt:550` 改 `:604`/`:620`。
- `MainActivity.kt:604` 与 `:620`：`for (id in 0..400)` → `for (id in 0..600)`。
- `l10n.dart:516-517`：`'每个班次最多 10 个闹钟'` / `'Up to 10 alarms per shift'`。
- 其余注释里的 `0..400` 一并改 `0..600`（`AlarmStore.kt`、`WidgetRenderer.kt` 两处、`widget_fixed_cards_guard_test.dart:192`）；`alarm_service.dart:275` 的过期行号一并修。

Run: `cd app && flutter analyze && flutter test test/shift_alarm_decision_test.dart test/schedule_editor_test.dart`
Expected: PASS（`schedule_editor_test.dart:1411` 那条用的是常量，跟着走）。

- [ ] **Step 4: 提交**

```bash
git add app
git commit -m "feat(alarm): 每班联动闹钟上限 6 → 10，原生扫描上界同步到 600"
```

---

### Task 4: 三档标记的界面与文案

**Files:**
- Modify: `app/lib/core/l10n.dart`（`clockPrevDay` / `prevDay` 一带，`:532-544`）
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart:715-724`、`:772-791`
- Modify: `app/lib/features/alarm/alarm_screen.dart:296-301`
- Modify: `app/lib/features/calendar/calendar_screen.dart:2756-2771`
- Modify: `app/lib/domain/shift_rotation.dart`（删掉 `alarmFallsOnPreviousDay` 兼容层）

**Interfaces:**
- Consumes: `alarmDayAnchor` / `AlarmDayAnchor`（Task 1）
- Produces（l10n）：
  - `static String clockNextDay(String time)` → `次日 $time` / `$time (next day)`
  - `static String get nextDayMarker` → `次日` / `next day`
  - `static String alarmDayHint(String start, String labeledTime)` → `上班 $start，有一条闹钟排在$labeledTime` / `Shift starts $start — one alarm rings $labeledTime`
  - **删掉** `alarmPrevDayHint`；**不要碰** `nextDay`（`:605`，那是结束时间 chip 在用的前缀、英文带尾空格）

- [ ] **Step 1: 加 l10n，跑既有守门**

新增三个键、删掉 `alarmPrevDayHint`。`nextDay`（`:605`）与 `timeRange` 一个字节都不动。

Run: `cd app && flutter analyze`
Expected: 0 error（此时调用点还引用着被删的键 → 会报 undefined；所以**先加后删**：这一步只加）。

- [ ] **Step 2: 写失败的用例**

在 `app/test/schedule_editor_test.dart` 加一条（照 `:786` 那条的写法）：构造一个 16:30–次日 00:30 的班次、挂 00:15 与 01:00 两条闹钟，断言这两行的 `valueText` 分别是 `L10n.clockNextDay('00:15')` 与 `L10n.clockNextDay('01:00')`；再加一个 08:00–20:00 的班次挂 23:00，断言是 `L10n.clockPrevDay('23:00')`。

Run: `cd app && flutter test test/schedule_editor_test.dart`
Expected: FAIL（现在次日那两行不带标记）。

- [ ] **Step 3: 改四处显示**

四处都是同一个形状 —— 把 `alarmFallsOnPreviousDay(...) ? <前一天标记> : <不标>` 换成按 `alarmDayAnchor` 的三路：

- `schedule_editor_screen.dart:721-724`：`next` → `L10n.clockNextDay(formatClock(...))`，`prev` → `L10n.clockPrevDay(...)`，`same` → `null`。
- `schedule_editor_screen.dart:774-785`：整组小字改走 `L10n.alarmDayHint`，条件改成「有任何一条不是 `same`」，举例取**第一条非 `same`**，标签用 `prev → clockPrevDay` / `next → clockNextDay`。
- `alarm_screen.dart:296-301`：`prev` → `L10n.prevDay`，`next` → `L10n.nextDayMarker`。
- `calendar_screen.dart:2763-2764`：`prev` / `next` 各给一个前缀，`same` 不给。

- [ ] **Step 4: 删掉兼容层并修既有测试**

删掉 `alarmFallsOnPreviousDay` 与 `alarmPrevDayHint`。修 `shift_rotation_test.dart` 里那些用它写的用例 —— 把它们改成断言枚举。同时按规格 §7 修正措辞：`:385-388` 的用例名与 02:00 那一半、`:394-401` 的凌晨 2 点那一半（改成「次日」），`:428` 起那条的注脚收窄到它真正举的形状（00:00 班的 08:00，`t > s`，仍走前一天）。

Run: `cd app && flutter test`
Expected: 全绿。

- [ ] **Step 5: 提交**

```bash
git add app
git commit -m "feat(alarm): 界面上标出「次日」的闹钟，四处显示认三档"
```

---

### Task 5: 视觉工装屏单

**Files:**
- Modify: `app/tool/visual/visual_screens.dart`（`:250-270` 一带）

- [ ] **Step 1: 更新到上限那一屏**

`22_editor_alarm_max` 的 `title` 里那个写死的「（6 个）」改成跟着常量走（或在标题里不再写数字），`count: maxAlarmsPerShift` 保持。

- [ ] **Step 2: 加一屏「三档标记」**

照 `23_alarm_two_per_shift` 的写法加一屏：一条 16:30–次日 00:30 的班次挂 `00:15`（次日）与 `19:00`（当天），另加一条 20:00–08:00 的夜班挂 `23:00`（前一天）。`makeAlarmShowcase` 若没有现成的钩子，就照它现有的 `nightShift: true` 那种开关加一个参数（读一眼 `tool/visual/` 里那个夹具再定）。

- [ ] **Step 3: 出图看图**

Run: `cd app && flutter test tool/visual/`
Expected: 全绿，且新屏画出三档标记。

- [ ] **Step 4: 提交**

```bash
git add app/tool/visual/
git commit -m "test(visual): 补三档闹钟标记与 10 条上限的屏单"
```

---

### Task 6: 版本号、更新日志与发布

**Files:**
- Modify: `app/pubspec.yaml:4`、`app/lib/core/app_info.dart:10`
- Modify: `app/lib/features/profile/app_dialogs.dart`（`_changelogZh` / `_changelogEn`）

- [ ] **Step 1: 版本号**

`0.11.0+147` → `0.11.1+148`，`appVersion` 同步 `'0.11.1'`。

Run: `cd app && flutter test test/app_info_test.dart`
Expected: PASS。

- [ ] **Step 2: 更新日志**

在 `_changelogZh` / `_changelogEn` **prepend** 一条 `0.11.1`，删掉最旧一条，保持**恰好 10 条**；纯文本，**不许出现 markdown 标记**（`changelog_window_test.dart` 守门）。内容要点：闹钟落点多了「次日」一档；**有一类老闹钟的日子会变**（列清楚是哪几类，见规格 §3.2）；每班闹钟上限 6 → 10。

Run: `cd app && flutter test test/changelog_window_test.dart`
Expected: PASS。

- [ ] **Step 3: 全套验收**

Run: `cd app && flutter analyze && flutter test && flutter test tool/visual/`
Expected: `analyze` 0 error / 0 warning；两套测试全绿，用例数**只增不减**。

- [ ] **Step 4: 构建与分发**

先 `. tools/build-env.ps1`（或 `tools\build-env.ps1`），再：

Run: `cd app && flutter build apk --release --target-platform android-arm64`
Expected: `app/build/app/outputs/flutter-apk/app-release.apk`。

复制到 `dist/倒班助手Pro-v0.11.1.apk`，用 `aapt2 dump badging` 核对 versionName `0.11.1` / versionCode `148` / 包名 `com.daoban.shiftassistantpro`。

- [ ] **Step 5: 真机复验（规格 §7）**

装到真机，配一条 16:30–次日 00:30 的班次 + `00:15` 与 `01:00` 两条闹钟：确认闹钟页与日历信息卡都写「次日」、且到点真响。班次里加到第 10 条，确认第 11 条的按钮收掉、说明文案对。

- [ ] **Step 6: 提交并发布**

```bash
git add app pubspec.lock 2>/dev/null; git add app
git commit -m "chore(release): v0.11.1 —— 闹钟三档落点 + 每班 10 条"
git push origin beta
git tag v0.11.1 && git push origin v0.11.1
```

发布说明先写进 `tools/gh/release-notes-v0.11.1.md`，再跑 `scripts/release.ps1 -SkipConfirm`。**发完 curl 一次 `main` 上的 `latest.json` 核对版本号**（清单必须留在 main 上）。

---

## 自查

- **规格覆盖**：§1.1/§1.3 → Task 1；§1.2 → Task 3；§3 全部 → Task 1 + Task 2；§3.2 → Task 4（文案）+ Task 6（更新日志）；§4 → Task 3；§5 → Task 4；§6 → Task 1；§7 → Task 1/2/3/4 + Task 6 Step 5；§8 → Task 5；§9 → 各任务内的实施选择。
- **类型一致**：`AlarmDayAnchor` / `alarmDayAnchor` / `shiftAlarmFireAt` / `maxAlarmsPerShift` / `clockNextDay` / `nextDayMarker` / `alarmDayHint` 在全文同名同签名。
- **Review Focus 的五条**各自落在 Task 1 的用例里（24 小时值班、`endMinute == null`、两种存法同解、正好下班、老约定），并有 Task 2 的差集护栏兜底。
