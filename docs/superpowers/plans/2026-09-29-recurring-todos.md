# 重复待办（定期重复提醒 + 统一管理）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让「每周三开会」这类待办只设一次，之后按周期自己出现、能勾能删；并在待办页给这些重复项一个统一管理入口。

**Architecture:** 新表 `RecurringTodos` 存**系列定义**，`ScheduleEvents` 加一列 `seriesId` 把「某一次」挂回系列。一个 Dart 侧生成器负责维持「每个系列最多一条未完成的当前行」（到点新建、过期就地顺延、勾过的留成历史）。提醒走**独立号段**（`40000 + 系列 id`），时刻表由 Dart 侧算好、整串递给原生，原生只做「弹队首、续队尾」—— 所以 App 长期不开也不漏，而规则只有一份实现。

**Tech Stack:** Flutter / Dart 3、Riverpod、Drift（SQLite）、Kotlin（AlarmManager + BroadcastReceiver + SharedPreferences）

**Spec:** `docs/superpowers/specs/2026-09-29-recurring-todos-design.md`

## Global Constraints

- **版本号**：`X.Y` 由用户决定，AI 只能动末位 `Z` 与 `build`；`app/pubspec.yaml` 的 `version:` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须同步（`test/app_info_test.dart` 盯着）。
- **改 Drift 表后必须重生成**：`dart run build_runner build --delete-conflicting-outputs`。
- **不许跑 `dart format`**：工具链是新版 tall style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `flutter analyze`。
- **日期一律 `dateOnly()` + `DateTime(y, m, d + n)`**，绝不用 `Duration(days:)`，也绝不用 `DateTime ==` 比「同一天」（用 `isSameDay`）。
- **纯函数不读时钟**：当前时刻 / 今天由调用方注入（照 `planShiftAlarms(from:)`）。
- **界面层不许写字面量**：字号 / 字重 / 颜色 / 圆角 / 时长 / 图标尺寸 / 4px 栅格外的间距一律走 `AppTokens`（`test/design_tokens_test.dart` 守门）。
- **触觉只在 `core/haptics.dart` 里调**，且不许给 `GlassSwitch` / `GlassSegment` / `GlassChoiceChip` / 四个选择器提交点已经发过的位置再补一记（`test/haptics_guard_test.dart` 守门）。
- **弹窗里的异步动作，`pop()` 之前必须用 `glass_dialog.dart` 的 `dialogCloser(context)`**，不许直接 `Navigator.pop`。
- **验收**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿（当前 375 条，**只增不减**）；`flutter test tool/visual/` 全绿（当前 196 条）。
- **提交前先跑测试**，每个任务末尾提交一次。

## Review Focus

以下是 spec 隐含、但没人会主动去试的输入。每一条都要在它归属的那个任务里落成用例：

1. **下午或晚上才打开 App**（当天那次提醒时刻已经过去）—— 期望：提醒仍然被排上，排的是**下一次**，而不是「已过去就不排」导致这条重复待办永远不响。（任务 5）
2. **每月 31 号** —— 期望：2 月落在 28/29 号，3 月回到 31 号，而不是 2 月跳过、或一路停在 28 号。（任务 1）
3. **用户手工把「这一次」改到别的日子**（比如这周的会挪到周五）—— 期望：生成器**不把它拽回来**。（任务 4）
4. **一周甚至两周没打开 App** —— 期望：不冒出一串错过的那几次，列表里只有当前那一条（就地顺延）。（任务 4）
5. **删掉当前那条之后再次打开 App** —— 期望：它**不补回来**（跳过标记），直到下一次到点。（任务 4）

---

### Task 1: 领域层纯函数（`domain/recurring_todo.dart`）

**Files:**
- Create: `app/lib/domain/recurring_todo.dart`
- Test: `app/test/recurring_todo_test.dart`
- Modify: `app/lib/core/l10n.dart`（加规则描述的文案）

**Interfaces:**
- Consumes: `dateOnly` / `daysBetween` / `dayNumber` / `formatClock`（`domain/shift_rotation.dart`）；`L10n.t` / `L10n.weekday(i)` / `L10n.isEn`
- Produces: `enum RecurRepeat { daily, weekly, monthly }`；类 `RecurringTodo`（字段见下，另有两个 getter）；顶层 `occurrenceOnOrBefore(RecurringTodo, DateTime) → DateTime?`、`firstOccurrenceOnOrAfter(RecurringTodo, DateTime) → DateTime?`、`nextOccurrenceAfter(RecurringTodo, DateTime) → DateTime?`、`upcomingFireTimes(RecurringTodo, {required DateTime from, required int clockMinute, int days, int cap}) → List<DateTime>`

- [ ] **Step 1: 先加文案**

在 `app/lib/core/l10n.dart` 的「待办（日程）」那一段（`noEvents` 附近）加：

```dart
  // 重复待办
  static String get repeatNone => t('不重复', 'Does not repeat');
  static String get repeatDaily => t('每天', 'Every day');
  static String get repeatWeekly => t('每周', 'Every week');
  static String get repeatMonthly => t('每月', 'Every month');
  static String everyWeekOn(String days) => t('每周$days', 'Every $days');
  static String everyMonthOnDay(int d) => t('每月 $d 号', 'Day $d of every month');
  static String get repeats => t('重复', 'Repeats');
  static String get startsOn => t('从这天起', 'Starts on');
  /// 提醒正文用的规则描述：`每周三 · 09:00`
  static String ruleWithTime(String rule, String time) =>
      time.isEmpty ? rule : '$rule · $time';
```

- [ ] **Step 2: 写失败的测试**

建 `app/test/recurring_todo_test.dart`：

```dart
// app/test/recurring_todo_test.dart
//
// 重复待办的规则 —— 全是纯函数，边界比正例多。
//
// 这些函数错了**不会报错**：只会「某天该出现却没出现」或者「提醒在错的时候响」，
// 两样都靠界面看不出来。所以边界要逐条钉住：月末、起始日、掩码、以及「从此刻
// 往后算的下一个触发时刻」。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';

RecurringTodo _s({
  RecurRepeat repeat = RecurRepeat.daily,
  DateTime? start,
  int weekdays = 0,
  int monthDay = 1,
  int? timeMinute,
  int? advance,
  int? skipThrough,
  bool enabled = true,
}) =>
    RecurringTodo(
      id: 1,
      title: '周三例会',
      repeat: repeat,
      startDate: start ?? DateTime.utc(2026, 1, 1),
      weekdays: weekdays,
      monthDay: monthDay,
      timeMinute: timeMinute,
      advanceRemindMinutes: advance,
      skipThrough: skipThrough,
      enabled: enabled,
    );

/// 周三 = `DateTime.weekday == 3` → 掩码位 `1 << 2`。
const _wed = 1 << 2;
/// 周一 = 1 → 掩码位 `1 << 0`。
const _mon = 1 << 0;

void main() {
  setUp(() => L10n.locale = 'zh');

  group('occurrenceOnOrBefore —— 不晚于今天的最近一次', () {
    test('每天：就是今天', () {
      expect(occurrenceOnOrBefore(_s(), DateTime.utc(2026, 9, 19)),
          DateTime.utc(2026, 9, 19));
    });

    test('每周三：今天是周二 → 退回上周三', () {
      // 2026-09-22 是周二，最近的一个周三是 09-16
      expect(
          occurrenceOnOrBefore(
              _s(repeat: RecurRepeat.weekly, weekdays: _wed),
              DateTime.utc(2026, 9, 22)),
          DateTime.utc(2026, 9, 16));
    });

    test('每周三：今天正是周三 → 就是今天', () {
      // 2026-09-23 是周三
      expect(
          occurrenceOnOrBefore(
              _s(repeat: RecurRepeat.weekly, weekdays: _wed),
              DateTime.utc(2026, 9, 23)),
          DateTime.utc(2026, 9, 23));
    });

    test('每周一三五（多选）：周三那天退回周一，周日退回周五', () {
      final s = _s(repeat: RecurRepeat.weekly, weekdays: _mon | _wed | (1 << 4));
      expect(occurrenceOnOrBefore(s, DateTime.utc(2026, 9, 23)), // 周三
          DateTime.utc(2026, 9, 23));
      expect(occurrenceOnOrBefore(s, DateTime.utc(2026, 9, 27)), // 周日
          DateTime.utc(2026, 9, 25)); // 周五
    });

    test('每月 15 号：本月 15 号还没到 → 退回上个月 15 号', () {
      expect(
          occurrenceOnOrBefore(
              _s(repeat: RecurRepeat.monthly, monthDay: 15),
              DateTime.utc(2026, 9, 10)),
          DateTime.utc(2026, 8, 15));
    });

    test('每月 31 号：**2 月落在 28 号**，3 月回到 31 号', () {
      final s = _s(repeat: RecurRepeat.monthly, monthDay: 31);
      expect(occurrenceOnOrBefore(s, DateTime.utc(2027, 2, 28)),
          DateTime.utc(2027, 2, 28));
      expect(occurrenceOnOrBefore(s, DateTime.utc(2027, 3, 31)),
          DateTime.utc(2027, 3, 31));
      // 3 月 30 号往回找，最近一次是 2 月 28 号（3 月的 31 号还没到）
      expect(occurrenceOnOrBefore(s, DateTime.utc(2027, 3, 30)),
          DateTime.utc(2027, 2, 28));
    });

    test('起始日之前没有任何发生日', () {
      expect(
          occurrenceOnOrBefore(_s(start: DateTime.utc(2026, 9, 20)),
              DateTime.utc(2026, 9, 19)),
          isNull);
    });

    test('掩码为空（脏数据）→ 不生成，而不是当成每天', () {
      expect(
          occurrenceOnOrBefore(
              _s(repeat: RecurRepeat.weekly, weekdays: 0),
              DateTime.utc(2026, 9, 19)),
          isNull);
    });
  });

  group('nextOccurrenceAfter —— 严格晚于某天', () {
    test('每天：明天', () {
      expect(nextOccurrenceAfter(_s(), DateTime.utc(2026, 9, 19)),
          DateTime.utc(2026, 9, 20));
    });

    test('每周三：周三当天算下一次是下周三（严格晚于）', () {
      expect(
          nextOccurrenceAfter(
              _s(repeat: RecurRepeat.weekly, weekdays: _wed),
              DateTime.utc(2026, 9, 23)),
          DateTime.utc(2026, 9, 30));
    });

    test('每周三、起始日是个周五 → 第一次是下周三，不是那个周五', () {
      expect(
          firstOccurrenceOnOrAfter(
              _s(
                  repeat: RecurRepeat.weekly,
                  weekdays: _wed,
                  start: DateTime.utc(2026, 10, 9)),
              DateTime.utc(2026, 10, 1)),
          DateTime.utc(2026, 10, 14));
    });

    test('每月 31 号：起始日在月中、当月的 31 号还没到 → 下个月 31 号', () {
      expect(
          firstOccurrenceOnOrAfter(
              _s(
                  repeat: RecurRepeat.monthly,
                  monthDay: 31,
                  start: DateTime.utc(2026, 10, 20)),
              DateTime.utc(2026, 10, 1)),
          DateTime.utc(2026, 10, 31));
    });
  });

  group('upcomingFireTimes —— 未来要响的时刻（提醒就靠它）', () {
    test('今天这次已经过去 → **第一条是下一次**，不是空', () {
      // 这条是 spec §5.1 那个坑：下午三点打开 App，今天 09:00 早过去了。
      // 写成「拿当前那一次的日期算时刻、过去就丢」的话，这条重复待办的提醒
      // **永远排不上**，而界面上一点异常都看不出来。
      final s = _s(
          repeat: RecurRepeat.weekly, weekdays: _wed, timeMinute: 9 * 60);
      final times = upcomingFireTimes(s,
          from: DateTime(2026, 9, 23, 15), clockMinute: 9 * 60);
      expect(times.first, DateTime(2026, 9, 30, 9));
    });

    test('今天这次还没到 → 第一条就是今天', () {
      final s = _s(
          repeat: RecurRepeat.weekly, weekdays: _wed, timeMinute: 9 * 60);
      final times = upcomingFireTimes(s,
          from: DateTime(2026, 9, 23, 8), clockMinute: 9 * 60);
      expect(times.first, DateTime(2026, 9, 23, 9));
    });

    test('提前一天的那档：触发时刻落在**前一天**', () {
      final s = _s(
          repeat: RecurRepeat.weekly,
          weekdays: _wed,
          timeMinute: 9 * 60,
          advance: 1440);
      final times = upcomingFireTimes(s,
          from: DateTime(2026, 9, 23, 8), clockMinute: 9 * 60);
      expect(times.first, DateTime(2026, 9, 22, 9));
    });

    test('不提醒（提醒档位为空）→ 空表', () {
      expect(
          upcomingFireTimes(_s(timeMinute: 9 * 60),
              from: DateTime(2026, 9, 23), clockMinute: 9 * 60),
          isEmpty);
    });

    test('停用 → 空表', () {
      final s = _s(
          timeMinute: 9 * 60, advance: 0, enabled: false);
      expect(
          upcomingFireTimes(s, from: DateTime(2026, 9, 23), clockMinute: 9 * 60),
          isEmpty);
    });

    test('每天的那档：180 天就是 180 条，且按时间升序', () {
      final s = _s(timeMinute: 9 * 60, advance: 0);
      final times = upcomingFireTimes(s,
          from: DateTime(2026, 9, 23, 8), clockMinute: 9 * 60);
      expect(times.length, 180);
      for (var i = 1; i < times.length; i++) {
        expect(times[i].isAfter(times[i - 1]), isTrue);
      }
    });

    test('上限生效：cap=3 时只给 3 条', () {
      final s = _s(timeMinute: 9 * 60, advance: 0);
      expect(
          upcomingFireTimes(s,
              from: DateTime(2026, 9, 23, 8), clockMinute: 9 * 60, cap: 3)
              .length,
          3);
    });
  });

  test('规则描述：提醒正文用它，且不带日期', () {
    expect(_s(repeat: RecurRepeat.daily, timeMinute: 9 * 60).ruleLabel, '每天');
    expect(
        _s(repeat: RecurRepeat.weekly, weekdays: _wed).ruleLabel, '每周三');
    expect(
        _s(repeat: RecurRepeat.monthly, monthDay: 1).ruleLabel, '每月 1 号');
    // 掩码为空是脏数据：退回不带星期的说法，而不是拼出一串空的「每周」
    expect(_s(repeat: RecurRepeat.weekly, weekdays: 0).ruleLabel, '每周');
  });
}
```

- [ ] **Step 3: 跑测试确认它红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_todo_test.dart`
Expected: 编译失败 —— `recurring_todo.dart` 还不存在（`Target of URI doesn't exist`）。

- [ ] **Step 4: 写实现**

建 `app/lib/domain/recurring_todo.dart`：

```dart
// 重复待办的规则 —— 纯 Dart，只依赖 intl（经由 `l10n.dart`）与 `shift_rotation.dart`，
// 可直接 dart test。
//
// 三个查询函数**都不读时钟**：当前时刻 / 今天由调用方注入。理由是这套东西的边界
// （月末、跨年、起始日、夏令时）恰好都不在「今天」上，读时钟的写法只能测今天那一
// 个输入。与 `planShiftAlarms(from:)` 同一条理由。
//
// 日期算术一律 `DateTime.utc(y, m, d + n)`：它会把溢出规范化（`d = 0` 指上月最后
// 一天、`m = 13` 指次年 1 月），而 `Duration(days:)` 加的是绝对 24 小时，碰上夏令时
// 切换会把日期挪掉一整天。

import '../core/l10n.dart';
import 'shift_rotation.dart';

/// 重复的周期。
enum RecurRepeat { daily, weekly, monthly }

/// 一个重复待办的**系列定义**（库里 `RecurringTodos` 一行的领域形态）。
class RecurringTodo {
  const RecurringTodo({
    required this.id,
    required this.title,
    required this.repeat,
    required this.startDate,
    this.timeMinute,
    this.advanceRemindMinutes,
    this.alarmEnabled = false,
    this.weekdays = 0,
    this.monthDay = 1,
    this.skipThrough,
    this.enabled = true,
  });

  /// 库里的行 id；null = 还没落库。
  final int? id;
  final String title;
  final RecurRepeat repeat;

  /// 分钟自午夜；null = 全天。
  final int? timeMinute;

  /// 提醒档位：null = 不提醒，0 = 准时，其余为提前的分钟数。
  final int? advanceRemindMinutes;

  /// 到点走**闹钟**（全屏 + 循环铃声）而不是只弹一条通知。
  final bool alarmEnabled;

  /// 每周：`1 << (weekday - 1)`，周一 = 1（与 `DateTime.weekday` 同序，
  /// 也与 `CustomAlarms.weekdays` 同一约定）。
  final int weekdays;

  /// 每月：1..31；该月没有这一天时取该月最后一天。
  final int monthDay;

  /// 首次生效日（纯日期）。
  final DateTime startDate;

  /// 「这次不要了」记到哪天为止（自 epoch 天数，与 `dayNumber` 同口径）；空 = 没跳过。
  final int? skipThrough;

  /// 停用：不再生成、不再续排提醒；**已经出现的那条留着**。
  final bool enabled;

  /// 规则的可读描述（「每周三」「每月 1 号」）。
  ///
  /// **提醒的正文用它，所以它不许带日期** —— 同一条提醒会跨很多次，写死日期
  /// 第二次就是错的。
  String get ruleLabel {
    switch (repeat) {
      case RecurRepeat.daily:
        return L10n.repeatDaily;
      case RecurRepeat.weekly:
        final days = [
          for (var i = 0; i < 7; i++)
            if ((weekdays & (1 << i)) != 0) L10n.weekday(i),
        ];
        // 掩码为空是脏数据（界面上不允许）：退回不带星期的说法，而不是拼出一个
        // 空串让提醒正文变成「 · 09:00」。
        if (days.isEmpty) return L10n.repeatWeekly;
        return L10n.everyWeekOn(days.join(L10n.isEn ? ', ' : '、'));
      case RecurRepeat.monthly:
        return L10n.everyMonthOnDay(monthDay);
    }
  }

  /// `HH:mm`；没设时间返回空串。
  String get timeLabel =>
      timeMinute == null ? '' : formatClock(timeMinute!);

  /// 提醒正文（`每周三 · 09:00`）。没设提醒时返回的是纯规则描述。
  String get ruleWithTime => L10n.ruleWithTime(ruleLabel, timeLabel);

  /// **注意它清不掉可空字段**：`advanceRemindMinutes ?? this.advanceRemindMinutes`
  /// 这种写法没有「传 null 就是清空」的通道 —— 把提醒从「提前 5 分钟」改回「不设」
  /// 时，`copyWith(advanceRemindMinutes: null)` 会**原样保留旧值**，而界面上看不出
  /// 来（那一行只是没变）。要清空就**显式构造**一个 `RecurringTodo(...)`。
  ///
  /// （这是 `shift_rotation.dart` 的 `ShiftClass` 踩过的同一个坑：那边编辑器的
  /// `_editClass` 也是有意不走 `copyWith`，理由写在那里。这里把警告写进方法上，
  /// 免得下一个人从两个地方各挑一半。）
  RecurringTodo copyWith({
    int? id,
    String? title,
    RecurRepeat? repeat,
    int? timeMinute,
    int? advanceRemindMinutes,
    bool? alarmEnabled,
    int? weekdays,
    int? monthDay,
    DateTime? startDate,
    int? skipThrough,
    bool? enabled,
  }) =>
      RecurringTodo(
        id: id ?? this.id,
        title: title ?? this.title,
        repeat: repeat ?? this.repeat,
        timeMinute: timeMinute ?? this.timeMinute,
        advanceRemindMinutes: advanceRemindMinutes ?? this.advanceRemindMinutes,
        alarmEnabled: alarmEnabled ?? this.alarmEnabled,
        weekdays: weekdays ?? this.weekdays,
        monthDay: monthDay ?? this.monthDay,
        startDate: startDate ?? this.startDate,
        skipThrough: skipThrough ?? this.skipThrough,
        enabled: enabled ?? this.enabled,
      );
}

/// 往后 / 往前挪整天。**不能用 `Duration(days:)`** —— 它加的是绝对 24 小时，
/// 夏令时那两天会挪错日期。`DateTime.utc` 会把 `d` 的溢出规范化（`d = 0` = 上月
/// 最后一天，`d = -1` = 上上月最后一天）。
DateTime _addDays(DateTime d, int n) => DateTime.utc(d.year, d.month, d.day + n);

/// 「每月某日」落在某个年月上的**具体日期**：该月没有这一天时取该月最后一天
/// （每月 31 号 → 2 月落在 28/29）。`month` 可以溢出（13 = 次年 1 月）。
DateTime _monthlyIn(int year, int month, int monthDay) {
  // `DateTime.utc(y, m + 1, 0)` 就是「m 月的最后一天」——day = 0 会规范化成上月末。
  final last = DateTime.utc(year, month + 1, 0).day;
  return DateTime.utc(year, month, monthDay <= last ? monthDay : last);
}

bool _matchesWeekday(int weekdays, DateTime d) =>
    (weekdays & (1 << (d.weekday - 1))) != 0;

/// 不早于 [from] 的**第一次**发生日；受 `startDate` 约束，无解返回 null。
DateTime? firstOccurrenceOnOrAfter(RecurringTodo s, DateTime from) {
  final start = dateOnly(s.startDate);
  var base = dateOnly(from);
  if (daysBetween(start, base) < 0) base = start;
  switch (s.repeat) {
    case RecurRepeat.daily:
      return base;
    case RecurRepeat.weekly:
      if (s.weekdays == 0) return null;
      for (var i = 0; i < 7; i++) {
        final c = _addDays(base, i);
        if (_matchesWeekday(s.weekdays, c)) return c;
      }
      return null;
    case RecurRepeat.monthly:
      // 最多找两年：`monthDay` 在 1..31 之内时一定能在 2 个月内找到，
      // 上限只是防御（脏数据里的 0 或 99）。
      for (var i = 0; i < 24; i++) {
        final c = _monthlyIn(base.year, base.month + i, s.monthDay);
        if (daysBetween(base, c) >= 0) return c;
      }
      return null;
  }
}

/// 不晚于 [day] 的**最近一次**发生日；`startDate` 之前返回 null。
DateTime? occurrenceOnOrBefore(RecurringTodo s, DateTime day) {
  final start = dateOnly(s.startDate);
  final d = dateOnly(day);
  if (daysBetween(start, d) < 0) return null;
  switch (s.repeat) {
    case RecurRepeat.daily:
      return d;
    case RecurRepeat.weekly:
      if (s.weekdays == 0) return null;
      for (var back = 0; back < 7; back++) {
        final c = _addDays(d, -back);
        if (_matchesWeekday(s.weekdays, c)) {
          return daysBetween(start, c) >= 0 ? c : null;
        }
      }
      return null;
    case RecurRepeat.monthly:
      for (var back = 0; back < 24; back++) {
        final c = _monthlyIn(d.year, d.month - back, s.monthDay);
        if (daysBetween(c, d) >= 0) {
          return daysBetween(start, c) >= 0 ? c : null;
        }
      }
      return null;
  }
}

/// **严格晚于** [day] 的下一次发生日。
DateTime? nextOccurrenceAfter(RecurringTodo s, DateTime day) =>
    firstOccurrenceOnOrAfter(s, _addDays(dateOnly(day), 1));

/// 某一次发生日的**触发时刻**（本地时间）。
///
/// `occ` 是 UTC 纯日期，要取它的年月日再按本地时区重建 —— 直接在它上面加分钟会
/// 带着 UTC 标志，交给原生算 epoch 毫秒时差一个时区（`eventReminderTime` 里
/// 记的是同一个坑）。
DateTime _fireAt(DateTime occ, int clock, int advance) =>
    DateTime(occ.year, occ.month, occ.day)
        .add(Duration(minutes: clock - advance));

/// 从 [from] 之后开始、未来 [days] 天里这条系列要响的全部时刻，最多 [cap] 条。
///
/// **起点是「不晚于 from 的那一次」，不是「下一次」**：今天这次还没到点的话，它
/// 也算一条（早上八点打开 App，今天九点的提醒该排上）。而它的触发时刻已经过去时
/// 自然被 `!fire.isBefore(from)` 筛掉，循环继续往下走 —— 那正是「下午打开也能排上
/// 下一次」的写法。
///
/// [clockMinute] 是「这次的要响的钟点」：待办没设时间时按几点提醒，是提醒层的
/// 策略（`AlarmService.allDayReminderHour`），不由领域层决定，所以由调用方传进来。
/// 领域层不 import `features/` 下的东西 —— 那会把「纯 Dart 可单测」这条性质打破。
List<DateTime> upcomingFireTimes(
  RecurringTodo s, {
  required DateTime from,
  required int clockMinute,
  int days = 180,
  int cap = 200,
}) {
  final advance = s.advanceRemindMinutes;
  if (advance == null || !s.enabled) return const [];
  final horizon = from.add(Duration(days: days));
  final out = <DateTime>[];
  var occ = occurrenceOnOrBefore(s, from) ?? firstOccurrenceOnOrAfter(s, from);
  while (occ != null && out.length < cap) {
    final fire = _fireAt(occ, clockMinute, advance);
    if (!fire.isBefore(from)) {
      if (fire.isAfter(horizon)) break;
      out.add(fire);
    }
    occ = nextOccurrenceAfter(s, occ);
  }
  return out;
}
```

- [ ] **Step 5: 跑测试确认全绿**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_todo_test.dart`
Expected: PASS（16 条）

- [ ] **Step 6: analyze + 提交**

```bash
cd app && ../toolchain/flutter/bin/flutter analyze
cd .. && git add app/lib/domain/recurring_todo.dart app/lib/core/l10n.dart app/test/recurring_todo_test.dart
git commit -m "feat(todo): 重复待办的规则层（三个纯函数 + 时刻表）"
```

---

### Task 2: 数据模型与迁移（schemaVersion 10 → 11）

**Files:**
- Modify: `app/lib/data/app_database.dart`（新表 + 新列 + `onUpgrade`）
- Modify: `app/lib/data/app_database.g.dart`（`build_runner` 生成，不手改）
- Test: `app/test/migration_v10_to_v11_test.dart`

**Interfaces:**
- Produces: 表 `RecurringTodos`（列 `id / title / timeMinute / advanceRemindMinutes / alarmEnabled / repeatType / weekdays / monthDay / startDate / skipThrough / enabled / createdAt`）；`ScheduleEvents.seriesId`（可空 int）；生成类 `RecurringTodoRow`；`schemaVersion == 11`

- [ ] **Step 1: 写失败的迁移测试**

建 `app/test/migration_v10_to_v11_test.dart`：

```dart
// app/test/migration_v10_to_v11_test.dart
//
// v10 → v11：新增一张 `recurring_todos`（重复待办的系列定义），并给
// `schedule_events` 加一列可空的 `series_id`。
//
// 这是一次**纯新增**的迁移（createTable + addColumn），没有重建表、没有搬数据，
// 所以 fixture 只需要抄 `schedule_events` 一张表的 v10 形态 —— 与 v8→v9 那条
// 「纯新增一张表」的判断一致（v9→v10 那种 alterTable 重建才要抄全套）。
//
// 但「纯新增」不等于「不会丢数据」：addColumn 写歪了、或者新表的 DDL 与生成代码
// 对不上，都是**跑起来才发现**。所以老行要逐条断言还在、值还对。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v10 形态的 `schedule_events`（DDL 与 v10 生成代码逐列一致）。
/// drift 默认把 DateTime 存成 **unix 秒**，所以时间列都是整数。
const _v10ScheduleEvents = '''
CREATE TABLE schedule_events (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  date INTEGER NOT NULL,
  time_minute INTEGER,
  advance_remind_minutes INTEGER,
  is_completed INTEGER NOT NULL DEFAULT 0,
  alarm_enabled INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
)
''';

void main() {
  test('v10 → v11：老待办一条不丢、series_id 为空、新表能写能读', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    raw.execute(_v10ScheduleEvents);
    // 两条老待办：一条未完成、一条已完成，值都写全（迁移把值吞了才看得出来）
    raw.execute(
      'INSERT INTO schedule_events '
      '(id, title, date, time_minute, advance_remind_minutes, is_completed, '
      'alarm_enabled, created_at) VALUES (1, ?, ?, ?, ?, 0, 1, ?)',
      [
        '交体检报告',
        DateTime.utc(2026, 10, 2).millisecondsSinceEpoch ~/ 1000,
        17 * 60,
        60,
        DateTime.utc(2026, 10, 1).millisecondsSinceEpoch ~/ 1000,
      ],
    );
    raw.execute(
      'INSERT INTO schedule_events '
      '(id, title, date, is_completed, created_at) VALUES (2, ?, ?, 1, ?)',
      [
        '上个月总结',
        DateTime.utc(2026, 9, 1).millisecondsSinceEpoch ~/ 1000,
        DateTime.utc(2026, 8, 30).millisecondsSinceEpoch ~/ 1000,
      ],
    );
    raw.execute('PRAGMA user_version = 10');

    // `NativeDatabase.opened` 把「已经建好 v10 表、user_version 也是 10」的句柄
    // 交给 drift —— 迁移在打开时跑。（与 `migration_v9_to_v10_test.dart` 同一套。）
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);
    expect(db.schemaVersion, 11);

    final repo = AppRepository(db);

    // ① 老待办原样保留
    final events = await repo.listEvents();
    expect(events.length, 2);
    final report = events.firstWhere((e) => e.title == '交体检报告');
    expect(report.date, DateTime.utc(2026, 10, 2));
    expect(report.timeMinute, 17 * 60);
    expect(report.advanceRemindMinutes, 60);
    expect(report.alarmEnabled, isTrue);
    expect(report.isCompleted, isFalse);
    expect(report.seriesId, isNull, reason: '老待办不该凭空挂上系列');
    expect(events.firstWhere((e) => e.title == '上个月总结').isCompleted, isTrue);

    // ② 新表在：能写能读
    final id = await repo.addRecurringTodo(
      title: '周三例会',
      repeat: RecurRepeat.weekly,
      startDate: DateTime.utc(2026, 10, 14),
      weekdays: 1 << 2,
      timeMinute: 9 * 60,
      advanceRemindMinutes: 0,
    );
    final series = await repo.listRecurringTodos();
    expect(series.single.id, id);
    expect(series.single.weekdays, 1 << 2);
    expect(series.single.startDate, DateTime.utc(2026, 10, 14));

    // ③ 新列可写：把一条老待办挂上系列
    await repo.updateEvent(report,
        title: report.title, date: report.date, seriesId: id);
    expect((await repo.listEvents())
        .firstWhere((e) => e.id == report.id)
        .seriesId, id);
  });
}
```

- [ ] **Step 2: 跑测试确认它红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/migration_v10_to_v11_test.dart`
Expected: 编译失败 —— `addRecurringTodo` / `listRecurringTodos` / `seriesId` 都还不存在。

- [ ] **Step 3: 加表与列**

在 `app/lib/data/app_database.dart` 的 `ScheduleEvents` 里加一列（放在 `alarmEnabled` 之后）：

```dart
  /// 重复待办：这条行是哪个系列的**某一次**（null = 一次性待办）。
  ///
  /// 不反过来在系列上存「当前行 id」—— 那是个要在新建 / 顺延 / 删除 / 跳过四条
  /// 路径上保持同步的指针，漏一条就指向不存在的行。而「当前那条 = 这个系列里
  /// 未完成的那条」是从数据本身推出来的，天然自愈（spec §3.3）。
  IntColumn get seriesId => integer().nullable()();
```

在同一文件 `CustomTemplates` 之后加新表：

```dart
/// 重复待办表（「每周三开会」这类）。
///
/// 存的是**系列定义**，不是一个一个实例：某一个具体日子由
/// `domain/recurring_todo.dart` 的规则现算，只有「当前这一次」会落到
/// `schedule_events` 里一行（挂 `series_id`）。这样：
///  - 列表里永远只有当前这一次（用户的诉求是「到点才出现」）；
///  - 提醒的号可以按**系列 id** 来发（`40000 + id`），与「越攒越多的行号」脱钩。
class RecurringTodos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();

  /// 分钟自午夜；空 = 全天。
  IntColumn get timeMinute => integer().nullable()();

  /// 提醒档位；空 = 不提醒。语义与 `ScheduleEvents.advanceRemindMinutes` 一致。
  IntColumn get advanceRemindMinutes => integer().nullable()();

  BoolColumn get alarmEnabled => boolean().withDefault(const Constant(false))();

  /// 0 = 每天，1 = 每周（看 [weekdays]），2 = 每月（看 [monthDay]）。
  IntColumn get repeatType => integer().withDefault(const Constant(0))();

  /// 每周：`1 << (weekday - 1)`，周一 = 1。与 `CustomAlarms.weekdays` 同一约定。
  IntColumn get weekdays => integer().withDefault(const Constant(0))();

  /// 每月：1..31；该月没有这一天时取该月最后一天。
  IntColumn get monthDay => integer().withDefault(const Constant(1))();

  /// 首次生效日（纯日期，`dateOnly` 口径）。这一天之前不产生任何发生日。
  DateTimeColumn get startDate => dateTime()();

  /// 「这次不要了」记到哪天为止（自 epoch 天数，与 `dayNumber` 同口径）。
  ///
  /// 没有它就会出现「删不掉」：在列表里删掉当前那条之后，生成器一看「没有未完成
  /// 的行、而这次的发生日还在今天之前」，下一次打开 App 又把它补出来。
  IntColumn get skipThrough => integer().nullable()();

  /// 停用：不再生成、不再顺延、不再排提醒；**已经出现的那条留着**（那是用户还没
  /// 做的一件事，替他删掉他就再也看不见了）。
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime()();
}
```

把它加进 `@DriftDatabase(tables: [...])` 列表（`CustomTemplates` 之后），并把 `schemaVersion` 改成 `11`，在 `onUpgrade` 里加分支：

```dart
          if (from < 11) {
            // 重复待办：纯新增一张表 + 给待办加一列可空的 series_id。
            // 两样都不碰既有数据（addColumn 加可空列时老行自动是 null）。
            await m.createTable(recurringTodos);
            await m.addColumn(scheduleEvents, scheduleEvents.seriesId);
          }
```

- [ ] **Step 4: 重生成 Drift 代码**

Run: `cd app && dart run build_runner build --delete-conflicting-outputs`
Expected: `app/lib/data/app_database.g.dart` 更新（出现 `RecurringTodos` 相关的生成类）

- [ ] **Step 5: 跑测试**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/migration_v10_to_v11_test.dart`
Expected: PASS

- [ ] **Step 6: analyze + 提交**

```bash
cd app && ../toolchain/flutter/bin/flutter analyze
cd .. && git add app/lib/data/app_database.dart app/lib/data/app_database.g.dart app/test/migration_v10_to_v11_test.dart
git commit -m "feat(db): 重复待办表与 series_id（schema 10 → 11）"
```

---

### Task 3: 仓库层（系列 CRUD + 跳过 + providers）

**Files:**
- Modify: `app/lib/data/app_repository.dart`
- Test: `app/test/recurring_repository_test.dart`

**Interfaces:**
- Consumes: 任务 1 的 `RecurringTodo` / `RecurRepeat`；任务 2 的表与列
- Produces:
  - `AppRepository.addRecurringTodo({required String title, required RecurRepeat repeat, required DateTime startDate, int? timeMinute, int? advanceRemindMinutes, bool alarmEnabled, int weekdays, int monthDay}) → Future<int>`
  - `AppRepository.updateRecurringTodo(RecurringTodo s) → Future<void>`
  - `AppRepository.setRecurringEnabled(int id, bool enabled) → Future<void>`
  - `AppRepository.deleteRecurringTodo(int id) → Future<void>`（连带删它的行）
  - `AppRepository.unlinkRecurringSeries(int id) → Future<void>`（**行解绑、一条不删**，系列定义删掉 —— 「以后不再重复」走这条）
  - `AppRepository.listRecurringTodos() → Future<List<RecurringTodo>>`
  - `AppRepository.skipRecurringOccurrence(int seriesId, DateTime occ) → Future<void>`
  - `AppRepository.addEvent(..., int? seriesId)` / `updateEvent(..., int? seriesId)`（新可选参数）
  - `recurringTodosProvider`（`FutureProvider.autoDispose<List<RecurringTodo>>`）

- [ ] **Step 1: 写失败的测试**

建 `app/test/recurring_repository_test.dart`：

```dart
// app/test/recurring_repository_test.dart
//
// 系列那几行的增删改查 + 跳过一次。都是直接对仓库，不经过界面。
//
// 重点在三条容易漏的关联：
//  ① 删系列要**连带删它的行**（否则列表里留下几条永远挂空的「历史」）；
//  ② 把一条待办挂上系列 / 摘下来，`seriesId` 真的落库；
//  ③ `clearAll` 要把新表也清掉（AGENTS 里那条「清空要连带删」的老规矩）。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

void main() {
  late AppDatabase db;
  late AppRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppRepository(db);
    await repo.ensureSeeded();
  });
  tearDown(() => db.close());

  Future<int> addSeries({int weekdays = 1 << 2}) => repo.addRecurringTodo(
        title: '周三例会',
        repeat: RecurRepeat.weekly,
        startDate: DateTime.utc(2026, 10, 14),
        timeMinute: 9 * 60,
        advanceRemindMinutes: 0,
        weekdays: weekdays,
      );

  test('新增之后读得回来，字段逐个对得上', () async {
    final id = await addSeries();
    final s = (await repo.listRecurringTodos()).single;
    expect(s.id, id);
    expect(s.title, '周三例会');
    expect(s.repeat, RecurRepeat.weekly);
    expect(s.weekdays, 1 << 2);
    expect(s.timeMinute, 9 * 60);
    expect(s.advanceRemindMinutes, 0);
    expect(s.startDate, DateTime.utc(2026, 10, 14));
    expect(s.enabled, isTrue);
    expect(s.skipThrough, isNull);
  });

  test('updateRecurringTodo 覆盖全部字段（含把提醒改回「不提醒」）', () async {
    final id = await addSeries();
    final s = (await repo.listRecurringTodos()).single;
    // **显式构造**而不是 `copyWith(advanceRemindMinutes: null)` —— copyWith 是
    // `?? this.x`，没有把可空字段清成 null 的通道，那条断言会假绿（旧值还在）。
    await repo.updateRecurringTodo(RecurringTodo(
      id: id,
      title: '周例会',
      repeat: RecurRepeat.monthly,
      startDate: s.startDate,
      monthDay: 15,
      advanceRemindMinutes: null,
    ));
    final after = (await repo.listRecurringTodos()).single;
    expect(after.title, '周例会');
    expect(after.repeat, RecurRepeat.monthly);
    expect(after.monthDay, 15);
    expect(after.advanceRemindMinutes, isNull, reason: '要能真的清成 null');
  });

  test('停用 / 启用', () async {
    final id = await addSeries();
    await repo.setRecurringEnabled(id, false);
    expect((await repo.listRecurringTodos()).single.enabled, isFalse);
    await repo.setRecurringEnabled(id, true);
    expect((await repo.listRecurringTodos()).single.enabled, isTrue);
  });

  test('跳过这一次：skipThrough 写成那天的 dayNumber', () async {
    final id = await addSeries();
    await repo.skipRecurringOccurrence(id, DateTime.utc(2026, 10, 14));
    expect((await repo.listRecurringTodos()).single.skipThrough,
        dayNumber(DateTime.utc(2026, 10, 14)));
  });

  test('删系列连带删它的行（历史与当前那条都不留）', () async {
    final id = await addSeries();
    await repo.addEvent(
        title: '周三例会',
        date: DateTime.utc(2026, 10, 14),
        seriesId: id);
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 10, 7), seriesId: id);
    expect((await repo.listEvents()).length, 2);

    await repo.deleteRecurringTodo(id);
    expect(await repo.listRecurringTodos(), isEmpty);
    expect(await repo.listEvents(), isEmpty, reason: '系列没了，它的行也该走');
  });

  test('删系列不动别人的行', () async {
    final id = await addSeries();
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 10, 14), seriesId: id);
    await repo.addEvent(title: '交体检报告', date: DateTime.utc(2026, 10, 15));
    await repo.deleteRecurringTodo(id);
    final left = await repo.listEvents();
    expect(left.length, 1);
    expect(left.single.title, '交体检报告');
  });

  test('待办能挂上系列、也能摘下来', () async {
    final id = await addSeries();
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 10, 14), seriesId: id);
    var e = (await repo.listEvents()).single;
    expect(e.seriesId, id);

    await repo.updateEvent(e,
        title: e.title, date: e.date, seriesId: null);
    e = (await repo.listEvents()).single;
    expect(e.seriesId, isNull, reason: '「以后不再重复」= 解绑');
  });

  test('**「以后不再重复」（unlink）把行留着、只解绑并删系列**', () async {
    final id = await addSeries();
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 10, 14), seriesId: id);
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 10, 7), seriesId: id);

    await repo.unlinkRecurringSeries(id);

    expect(await repo.listRecurringTodos(), isEmpty, reason: '系列定义该没了');
    final rows = await repo.listEvents();
    expect(rows.length, 2, reason: '待办一条都不许删 —— 用户说的是「别再自动出现」');
    expect(rows.every((e) => e.seriesId == null), isTrue, reason: '都解绑了');
  });

  test('clearAll 把新表也清掉', () async {
    await addSeries();
    await repo.clearAll();
    expect(await repo.listRecurringTodos(), isEmpty);
  });
}
```

- [ ] **Step 2: 跑测试确认它红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_repository_test.dart`
Expected: 编译失败 —— `addRecurringTodo` 等还不存在。

- [ ] **Step 3: 写实现**

在 `app/lib/data/app_repository.dart` 里：

① `addEvent` / `updateEvent` 各加一个可选参数 `int? seriesId`，并把它写进 companion：

```dart
  Future<int> addEvent({
    required String title,
    required DateTime date,
    int? timeMinute,
    int? advanceRemindMinutes,
    bool alarmEnabled = false,
    int? seriesId,
  }) {
    return db.into(db.scheduleEvents).insert(
          ScheduleEventsCompanion.insert(
            title: title,
            date: dateOnly(date),
            timeMinute: Value(timeMinute),
            advanceRemindMinutes: Value(advanceRemindMinutes),
            alarmEnabled: Value(alarmEnabled),
            seriesId: Value(seriesId),
            createdAt: DateTime.now(),
          ),
        );
  }
```

`updateEvent` 同理加 `int? seriesId` 并写 `seriesId: Value(seriesId)`。

② 在「我的模板」那一段之后加一整段（配套的行转换与 CRUD）：

```dart
/// `RecurringTodos` 一行 → 领域形态。
extension RecurringTodoRowX on RecurringTodoRow {
  RecurringTodo toDomain() => RecurringTodo(
        id: id,
        title: title,
        // 库里存的是 int（0/1/2）。越界值（脏数据 / 将来的第 3 种周期）落回「每天」：
        // 静默当每天比抛异常好，用户至少还能看见这一条并去改它。
        repeat: RecurRepeat.values[
            repeatType >= 0 && repeatType < RecurRepeat.values.length
                ? repeatType
                : 0],
        startDate: startDate,
        timeMinute: timeMinute,
        advanceRemindMinutes: advanceRemindMinutes,
        alarmEnabled: alarmEnabled,
        weekdays: weekdays,
        monthDay: monthDay,
        skipThrough: skipThrough,
        enabled: enabled,
      );
}
```

而 CRUD 方法加在 `AppRepository` 类里（放在 `deleteEvent` 之后）。**先加这个小方法**
（任务 9 的「改完周期对齐」要用它）：

```dart
  /// **只**改某条行的日期。
  ///
  /// 不走 [updateEvent]：那个是全字段覆盖，只传日期会把这条的时间 / 提醒 /
  /// 联动闹钟一起抹成默认值 —— 它名字看着像「更新这一条」，实际语义是「用这组
  /// 字段替换这一条」。目前只有一处用它。
  Future<void> setEventDate(int id, DateTime date) {
    return (db.update(db.scheduleEvents)..where((r) => r.id.equals(id)))
        .write(ScheduleEventsCompanion(date: Value(dateOnly(date))));
  }
```

然后是重复待办那一整段：

```dart
  // ---------------------------------------------------------------------------
  // 重复待办（系列定义）
  //
  // 表里存的是**系列**，不是实例；「当前这一次」是 `schedule_events` 里挂着
  // `seriesId` 的那一行。两者的关系由 `advanceRecurringTodos` 维持。
  // ---------------------------------------------------------------------------

  Future<int> addRecurringTodo({
    required String title,
    required RecurRepeat repeat,
    required DateTime startDate,
    int? timeMinute,
    int? advanceRemindMinutes,
    bool alarmEnabled = false,
    int weekdays = 0,
    int monthDay = 1,
  }) {
    return db.into(db.recurringTodos).insert(
          RecurringTodosCompanion.insert(
            title: title,
            repeatType: Value(repeat.index),
            startDate: dateOnly(startDate),
            timeMinute: Value(timeMinute),
            advanceRemindMinutes: Value(advanceRemindMinutes),
            alarmEnabled: Value(alarmEnabled),
            weekdays: Value(weekdays),
            monthDay: Value(monthDay),
            enabled: const Value(true),
            createdAt: DateTime.now(),
          ),
        );
  }

  /// 覆盖式更新（`RecurringTodo` 全字段）。**`advanceRemindMinutes` 要能写成
  /// null** —— 所以这里逐个 `Value(...)` 显式给，不省事用 `?? this.x` 那套。
  Future<void> updateRecurringTodo(RecurringTodo s) {
    return (db.update(db.recurringTodos)..where((t) => t.id.equals(s.id!)))
        .write(RecurringTodosCompanion(
      title: Value(s.title),
      repeatType: Value(s.repeat.index),
      startDate: Value(dateOnly(s.startDate)),
      timeMinute: Value(s.timeMinute),
      advanceRemindMinutes: Value(s.advanceRemindMinutes),
      alarmEnabled: Value(s.alarmEnabled),
      weekdays: Value(s.weekdays),
      monthDay: Value(s.monthDay),
      skipThrough: Value(s.skipThrough),
      enabled: Value(s.enabled),
    ));
  }

  Future<void> setRecurringEnabled(int id, bool enabled) {
    return (db.update(db.recurringTodos)..where((t) => t.id.equals(id)))
        .write(RecurringTodosCompanion(enabled: Value(enabled)));
  }

  /// 「这次不要了」：记下那天的 `dayNumber`，生成器在那天之前不再补出来。
  ///
  /// 不写这个标记的话，在列表里删掉当前那条之后，下一次打开 App 生成器又会把它
  /// 补出来 —— 用户看到的就是「删不掉」（spec §6.4）。
  Future<void> skipRecurringOccurrence(int seriesId, DateTime occ) {
    return (db.update(db.recurringTodos)..where((t) => t.id.equals(seriesId)))
        .write(RecurringTodosCompanion(
      skipThrough: Value(dayNumber(occ)),
    ));
  }

  /// 删一个系列，**连带删它的行**（当前那条与已完成的历史都算它的）。
  ///
  /// 留下孤儿行的话，列表里会出现几条还原不回去的「历史」；而系列一回来
  /// （用户又建了一个同样的），它们又会莫名其妙地挂上去。
  ///
  /// ⚠️ **「以后不再重复」不能走这个方法**：那会把用户正在编辑的这条待办本身也
  /// 删掉。那种情形用 [unlinkRecurringSeries]。
  Future<void> deleteRecurringTodo(int id) async {
    await db.transaction(() async {
      await (db.delete(db.scheduleEvents)
            ..where((e) => e.seriesId.equals(id)))
          .go();
      await (db.delete(db.recurringTodos)..where((t) => t.id.equals(id))).go();
    });
  }

  /// 「以后不再重复」：**把行解绑、把系列定义删掉，但一条待办都不删。**
  ///
  /// 与 [deleteRecurringTodo] 的差别正是这一条：用户说的是「别再自动出现了」，
  /// 不是「把我这条待办删了」。已完成的那些历史也解绑成普通待办留着 —— 它们本来
  /// 就是做过的事，列表里一直看得见，用户想清自己删。
  Future<void> unlinkRecurringSeries(int id) async {
    await db.transaction(() async {
      await (db.update(db.scheduleEvents)
            ..where((e) => e.seriesId.equals(id)))
          .write(const ScheduleEventsCompanion(seriesId: Value(null)));
      await (db.delete(db.recurringTodos)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<List<RecurringTodo>> listRecurringTodos() async {
    final rows = await (db.select(db.recurringTodos)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows.map((r) => r.toDomain()).toList();
  }

  /// 监听全部重复待办（面板用）。
  Stream<List<RecurringTodo>> watchRecurringTodos() {
    final q = db.select(db.recurringTodos)
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return q.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }
```

③ `clearAll` 里加（**放在删 `schedule_events` 之后**）：

```dart
      // 重复待办的系列定义。它的「行」就是 schedule_events，上面已经删了 ——
      // 这里只清系列本身，漏了的话重启后生成器会照着老系列再建出行来。
      await db.delete(db.recurringTodos).go();
```

④ 文件末尾的 providers 区加：

```dart
/// 全部重复待办（系列定义）。
///
/// **一次性读 + `autoDispose`**，不是流 —— 与 `savedTemplatesProvider` 同一套
/// 理由与坑：用流的话，每条挂这个弹窗的 widget 用例都会在拆树时报
/// 「A Timer is still pending」（drift 取消查询流时排的零时长定时器）。
/// 而 `autoDispose` 是必需的：面板里改完 / 删完之后由调用点 `ref.invalidate`
/// 重读，不 autoDispose 的话第一次的结果会被缓存一整个会话
/// （v0.8.11 那个「存完模板看不到」就是这么来的）。
final recurringTodosProvider =
    FutureProvider.autoDispose<List<RecurringTodo>>((ref) {
  return ref.watch(appRepositoryProvider).listRecurringTodos();
});
```

⑤ `app_repository.dart` 顶部补 `import '../domain/recurring_todo.dart';`。

- [ ] **Step 4: 跑测试确认全绿**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_repository_test.dart`
Expected: PASS（8 条）

- [ ] **Step 5: analyze + 全量测试 + 提交**

```bash
cd app && ../toolchain/flutter/bin/flutter analyze && ../toolchain/flutter/bin/flutter test
cd .. && git add app/lib/data/app_repository.dart app/test/recurring_repository_test.dart
git commit -m "feat(todo): 重复待办系列的仓库层与 provider"
```

---

### Task 4: 生成器（当前那一条的生成与顺延）

**Files:**
- Modify: `app/lib/data/app_repository.dart`
- Test: `app/test/advance_recurring_test.dart`

**Interfaces:**
- Consumes: 任务 1 的 `occurrenceOnOrBefore`；任务 3 的 CRUD
- Produces: `AppRepository.advanceRecurringTodos({required DateTime today}) → Future<void>`

- [ ] **Step 1: 写失败的测试**

建 `app/test/advance_recurring_test.dart`：

```dart
// app/test/advance_recurring_test.dart
//
// 生成器：让每个系列「当前这一次」的样子与今天对齐。
//
// 六种状态各一条 —— 其中三条（不倒退 / 跨两周 / 删完不补）是「错了也不报错」的
// 那类：界面只是某天多出来一条、或者少了一条，没有任何异常。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

/// 2026-09-23 是周三。测试全都以它当「今天」的基准。
final _wed = DateTime.utc(2026, 9, 23);

void main() {
  late AppDatabase db;
  late AppRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppRepository(db);
    await repo.ensureSeeded();
  });
  tearDown(() => db.close());

  /// 一条「每周三 09:00、提前 0 分钟提醒」的系列，起始日就是 9/23。
  Future<int> weekly() => repo.addRecurringTodo(
        title: '周三例会',
        repeat: RecurRepeat.weekly,
        startDate: _wed,
        timeMinute: 9 * 60,
        advanceRemindMinutes: 0,
        weekdays: 1 << 2,
      );

  test('没有未完成的行 → 新建一条，日期是当前这一次', () async {
    final id = await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    final rows = await repo.listEvents();
    expect(rows.length, 1);
    expect(rows.single.seriesId, id);
    expect(rows.single.date, _wed);
    expect(rows.single.isCompleted, isFalse);
    expect(rows.single.title, '周三例会');
    expect(rows.single.timeMinute, 9 * 60);
  });

  test('再跑一次不会多建一条（幂等）', () async {
    await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    await repo.advanceRecurringTodos(today: _wed);
    expect((await repo.listEvents()).length, 1);
  });

  test('过期未勾 → **就地顺延**，行的 id 不变', () async {
    await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    final before = (await repo.listEvents()).single;

    // 下周三
    await repo.advanceRecurringTodos(today: DateTime.utc(2026, 9, 30));
    final after = (await repo.listEvents()).single;
    expect(after.id, before.id, reason: '顺延是改这一条，不是新建一条');
    expect(after.date, DateTime.utc(2026, 9, 30));
    expect(after.isCompleted, isFalse);
  });

  test('跨两周没打开 App → 只顺延到**最近一次**，不补中间那几次', () async {
    await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    // 跳过 9/30，直接到 10/7
    await repo.advanceRecurringTodos(today: DateTime.utc(2026, 10, 7));
    final rows = await repo.listEvents();
    expect(rows.length, 1, reason: '错过的不补，列表里只有当前这一条');
    expect(rows.single.date, DateTime.utc(2026, 10, 7));
  });

  test('**用户手工改到将来 → 不倒退**（这周的会挪到周五）', () async {
    await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    final e = (await repo.listEvents()).single;
    await repo.updateEvent(e, title: e.title, date: DateTime.utc(2026, 9, 25));
    // 生成器再跑（今天还是 9/23，occurrence 是 9/23，行在 9/25）
    await repo.advanceRecurringTodos(today: _wed);
    expect((await repo.listEvents()).single.date, DateTime.utc(2026, 9, 25),
        reason: '生成器只往前顺延，永不回退 —— 否则用户挪的日子会被拽回来');
  });

  test('删掉当前那条（跳过）之后再跑 → **不补回来**', () async {
    final id = await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    final e = (await repo.listEvents()).single;
    // 列表里的「删」= 跳过这一次 + 删掉那一行
    await repo.skipRecurringOccurrence(id, e.date);
    await repo.deleteEvent(e);
    await repo.advanceRecurringTodos(today: _wed);
    expect(await repo.listEvents(), isEmpty, reason: '删了又回来 = 用户眼里的删不掉');
  });

  test('到了下一次 occurrence，跳过标记自然失效、它又出现', () async {
    final id = await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    final e = (await repo.listEvents()).single;
    await repo.skipRecurringOccurrence(id, e.date);
    await repo.deleteEvent(e);

    await repo.advanceRecurringTodos(today: DateTime.utc(2026, 9, 30));
    final rows = await repo.listEvents();
    expect(rows.length, 1);
    expect(rows.single.date, DateTime.utc(2026, 9, 30));
  });

  test('勾过之后（无未完成行）→ 下一次到点新建一条，历史留着', () async {
    await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    final e = (await repo.listEvents()).single;
    await repo.setEventCompleted(e, true);

    await repo.advanceRecurringTodos(today: DateTime.utc(2026, 9, 30));
    final rows = await repo.listEvents();
    expect(rows.length, 2, reason: '完成的那条是历史，新的一次另起一条');
    expect(rows.where((r) => r.isCompleted).length, 1);
    expect(rows.map((r) => r.date),
        containsAll([DateTime.utc(2026, 9, 23), DateTime.utc(2026, 9, 30)]));
  });

  test('停用 → 不新建也不顺延，已经出现的那条留着', () async {
    final id = await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    await repo.setRecurringEnabled(id, false);
    await repo.advanceRecurringTodos(today: DateTime.utc(2026, 10, 7));
    final rows = await repo.listEvents();
    expect(rows.length, 1);
    expect(rows.single.date, _wed, reason: '停用只是不再自动出现，不替你把它收走');
  });

  test('起始日在将来 → 什么都不做', () async {
    await repo.addRecurringTodo(
      title: '下个月开始',
      repeat: RecurRepeat.monthly,
      startDate: DateTime.utc(2026, 10, 1),
      monthDay: 1,
    );
    await repo.advanceRecurringTodos(today: _wed);
    expect(await repo.listEvents(), isEmpty);
  });

  test('多条未完成（脏数据）→ 收敛成一条', () async {
    final id = await weekly();
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 9, 16), seriesId: id);
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 9, 9), seriesId: id);
    await repo.advanceRecurringTodos(today: _wed);
    final live = (await repo.listEvents()).where((r) => !r.isCompleted).toList();
    expect(live.length, 1, reason: '一个系列至多一条未完成的行');
    expect(live.single.date, _wed);
  });
}
```

- [ ] **Step 2: 跑测试确认它红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/advance_recurring_test.dart`
Expected: 编译失败 —— `advanceRecurringTodos` 还不存在。

- [ ] **Step 3: 写实现**

加在 `AppRepository` 的重复待办那一段里：

```dart
  /// 把每个重复待办的「当前这一次」推进到今天该有的样子（spec §4.2）。
  ///
  /// [today] 由调用方注入，**不读 `DateTime.now()`** —— 读时钟的话，月末、跨年、
  /// 起始日这些边界全都测不成（与 `planShiftAlarms(from:)` 同一条理由）。
  ///
  /// 一个事务里做完：这份数据的不变量是「一个系列至多一条未完成的行」，
  /// 中途失败留下两条就破了。
  Future<void> advanceRecurringTodos({required DateTime today}) async {
    await db.transaction(() async {
      final series = await listRecurringTodos();
      final rows = await listEvents();
      for (final s in series) {
        // 停用：不生成也不顺延。已经出现的那条留着 —— 那是用户还没做的一件事。
        if (!s.enabled) continue;

        final occ = occurrenceOnOrBefore(s, today);
        if (occ == null) continue; // 还没到起始日
        // 「这次不要了」：跳过标记与 occurrence 都是「自 epoch 天数」。
        // 直接拿 DateTime 比 int 是拿毫秒去比天数，恒不成立 —— 那就是「删了又回来」。
        if (s.skipThrough != null && dayNumber(occ) <= s.skipThrough!) continue;

        final live = rows
            .where((r) => r.seriesId == s.id && !r.isCompleted)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

        if (live.isEmpty) {
          await db.into(db.scheduleEvents).insert(
                ScheduleEventsCompanion.insert(
                  title: s.title,
                  date: occ,
                  timeMinute: Value(s.timeMinute),
                  advanceRemindMinutes: Value(s.advanceRemindMinutes),
                  alarmEnabled: Value(s.alarmEnabled),
                  seriesId: Value(s.id),
                  createdAt: DateTime.now(),
                ),
              );
          continue;
        }

        // 多条未完成是脏数据：留日期最新的那条，其余按已完成处理（留下痕迹但不再
        // 参与「当前那一条」的判定）。
        for (final extra in live.take(live.length - 1)) {
          await (db.update(db.scheduleEvents)
                ..where((r) => r.id.equals(extra.id)))
              .write(const ScheduleEventsCompanion(isCompleted: Value(true)));
        }
        final keep = live.last;
        // **只往前顺延**：用户手工把这一次改到别的日子（这周的会挪到周五）之后，
        // 生成器不许把它拽回来。所以日期已经晚于 occ 时什么都不做。
        if (daysBetween(keep.date, occ) > 0) {
          await (db.update(db.scheduleEvents)
                ..where((r) => r.id.equals(keep.id)))
              .write(ScheduleEventsCompanion(date: Value(occ)));
        }
      }
    });
  }
```

- [ ] **Step 4: 跑测试确认全绿**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/advance_recurring_test.dart`
Expected: PASS（11 条）

- [ ] **Step 5: analyze + 提交**

```bash
cd app && ../toolchain/flutter/bin/flutter analyze
cd .. && git add app/lib/data/app_repository.dart app/test/advance_recurring_test.dart
git commit -m "feat(todo): 重复待办的生成器（新建 / 就地顺延 / 跳过 / 不倒退）"
```

---

### Task 5: 提醒——Dart 侧的排定计划

**Files:**
- Modify: `app/lib/features/alarm/alarm_service.dart`
- Test: `app/test/recurring_alarm_plan_test.dart`

**Interfaces:**
- Consumes: 任务 1 的 `upcomingFireTimes`；任务 3 的 `listRecurringTodos`
- Produces:
  - `class RecurringAlarmPlan { final int seriesId; final DateTime fireAt; final List<DateTime> repeatTimes; }`
  - `AlarmService.planRecurringReminders(List<RecurringTodo> series, {required DateTime from, int days, int cap}) → List<RecurringAlarmPlan>`（顶层纯函数）
  - `AlarmService.rescheduleRecurringReminders(List<RecurringTodo> series) → Future<void>`
  - `AlarmService.scheduleTodoReminder(..., List<DateTime> repeatTimes = const [])`（新可选参数）
  - `AlarmService.scheduleNativeAlarm(..., List<DateTime> repeatTimes = const [])`（新可选参数，内部走 `repeatType: 3`）

- [ ] **Step 1: 写失败的测试**

建 `app/test/recurring_alarm_plan_test.dart`：

```dart
// app/test/recurring_alarm_plan_test.dart
//
// 「哪些系列要排提醒、排在哪一刻、后面还跟着哪几次」—— 纯函数，不碰通道。
//
// 抽成纯函数是因为它错了**不会报错**：只是提醒在错的时候响、或者根本不响。
// 那两样都靠界面看不出来。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';

RecurringTodo _s({
  int id = 1,
  int? timeMinute = 9 * 60,
  int? advance = 0,
  bool enabled = true,
}) =>
    RecurringTodo(
      id: id,
      title: '周三例会',
      repeat: RecurRepeat.weekly,
      startDate: DateTime.utc(2026, 9, 16),
      weekdays: 1 << 2, // 周三
      timeMinute: timeMinute,
      advanceRemindMinutes: advance,
      enabled: enabled,
    );

void main() {
  test('排的是**下一次**的时刻，不是当前那一次的日期', () {
    // 2026-09-23 是周三，下午三点才打开 App —— 今天九点早过了。
    final plans = planRecurringReminders([_s()], from: DateTime(2026, 9, 23, 15));
    expect(plans.length, 1);
    expect(plans.single.seriesId, 1);
    expect(plans.single.fireAt, DateTime(2026, 9, 30, 9),
        reason: '下午打开也要排上下一次，否则这条重复待办的提醒永远排不上');
  });

  test('队首之外还带着后面几次（原生续排用），且不含队首', () {
    final plans = planRecurringReminders([_s()], from: DateTime(2026, 9, 23, 15));
    expect(plans.single.repeatTimes.first, DateTime(2026, 10, 7, 9));
    expect(plans.single.repeatTimes.contains(DateTime(2026, 9, 30, 9)), isFalse,
        reason: '队首已经单独排了，队列里不能重复带上它');
  });

  test('没设提醒档位 / 停用 → 这个系列不进计划', () {
    expect(planRecurringReminders([_s(advance: null)],
            from: DateTime(2026, 9, 23, 15)),
        isEmpty);
    expect(planRecurringReminders([_s(enabled: false)],
            from: DateTime(2026, 9, 23, 15)),
        isEmpty);
  });

  test('没设时间的按全天那档的钟点（9:00）排', () {
    final plans = planRecurringReminders([_s(timeMinute: null)],
        from: DateTime(2026, 9, 23, 8));
    expect(plans.single.fireAt,
        DateTime(2026, 9, 23, AlarmService.allDayReminderHour, 0));
  });

  test('多个系列各自一条计划', () {
    final plans = planRecurringReminders([_s(id: 1), _s(id: 2)],
        from: DateTime(2026, 9, 23, 15));
    expect(plans.map((p) => p.seriesId).toList(), [1, 2]);
  });

  test('id 为 null（还没落库）的系列跳过，不排', () {
    final s = RecurringTodo(
      id: null,
      title: 'x',
      repeat: RecurRepeat.daily,
      startDate: DateTime.utc(2026, 9, 1),
      timeMinute: 9 * 60,
      advanceRemindMinutes: 0,
    );
    expect(planRecurringReminders([s], from: DateTime(2026, 9, 23, 15)), isEmpty);
  });
}
```

- [ ] **Step 2: 跑测试确认它红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_alarm_plan_test.dart`
Expected: 编译失败 —— `planRecurringReminders` 还不存在。

- [ ] **Step 3: 写实现**

在 `app/lib/features/alarm/alarm_service.dart` 里加（放在 `planShiftAlarms` 之后、`ShiftAlarmPlan` 那个区域附近，配套的风格与注释）：

```dart
/// 一条重复待办提醒的排定计划。
///
/// 队首（[fireAt]）现在排给原生；[repeatTimes] 是它后面还跟着的几次 —— 一起递过去，
/// 由原生在响完之后**弹队首、续队尾**，所以 App 长期不开也不漏。
class RecurringAlarmPlan {
  const RecurringAlarmPlan({
    required this.seriesId,
    required this.fireAt,
    required this.repeatTimes,
  });

  final int seriesId;
  final DateTime fireAt;

  /// [fireAt] 之后的下几次触发时刻（升序，不含 [fireAt]）。
  final List<DateTime> repeatTimes;
}

/// 纯函数：把系列列表算成要排的提醒。**不碰通知通道、不读时钟**。
///
/// 抽出来是为了能直接单测 —— 它错了不会报错，只会**在错的时候提醒**或者
/// **根本不提醒**，两样都靠界面看不出来（与 `planShiftAlarms` 同一条理由）。
///
/// 关键的一条：时刻从 [from] **之后**算起（`upcomingFireTimes` 的语义），不是从
/// 「当前那一次的日期」算起 —— 下午打开 App 时今天那次早过去了，照那一次排等于
/// 永远排不上（spec §5.1）。
List<RecurringAlarmPlan> planRecurringReminders(
  List<RecurringTodo> series, {
  required DateTime from,
  int days = 180,
  int cap = 200,
}) {
  final out = <RecurringAlarmPlan>[];
  for (final s in series) {
    final id = s.id;
    if (id == null) continue; // 还没落库的系列没有稳定的提醒号
    final times = upcomingFireTimes(
      s,
      from: from,
      // 「没设时间按几点提醒」是提醒层的策略，领域层不知道也不该知道。
      clockMinute: s.timeMinute ?? allDayReminderHour * 60,
      days: days,
      cap: cap,
    );
    if (times.isEmpty) continue;
    out.add(RecurringAlarmPlan(
      seriesId: id,
      fireAt: times.first,
      repeatTimes: times.skip(1).toList(),
    ));
  }
  return out;
}

/// 重排全部重复待办的提醒（先清掉这一段的旧记录，再按计划重排）。
///
/// 与 [rescheduleEventReminders] 分工：**带 `seriesId` 的行在那一边被跳过**，
/// 它们的提醒由这里负责 —— 否则同一次会响两声。
static Future<void> rescheduleRecurringReminders(
    List<RecurringTodo> series) async {
  final from = DateTime.now();
  final plans = planRecurringReminders(series, from: from);
  final body = <int, String>{for (final s in series) s.id!: s.ruleWithTime};
  for (final p in plans) {
    final id = _recurringBaseId + p.seriesId;
    final text = body[p.seriesId] ?? '';
    try {
      final s = series.firstWhere((x) => x.id == p.seriesId);
      if (s.alarmEnabled) {
        await scheduleNativeAlarm(
          id,
          p.fireAt,
          s.title,
          detail: text,
          repeatTimes: p.repeatTimes,
        );
      } else {
        await scheduleTodoReminder(
          id,
          p.fireAt,
          title: s.title,
          body: text,
          repeatTimes: p.repeatTimes,
        );
      }
    } catch (e) {
      await appendLog('rescheduleRecurringReminders 排定失败: $e');
    }
  }
}
```

`scheduleTodoReminder` 加参数：

```dart
  static Future<void> scheduleTodoReminder(
    int id,
    DateTime fireAt, {
    required String title,
    required String body,
    List<DateTime> repeatTimes = const [],
  }) async {
    try {
      await _settingsChannel.invokeMethod('scheduleTodoReminder', {
        'id': id,
        'millis': fireAt.millisecondsSinceEpoch,
        'title': title,
        'body': body,
        // 后续几次的绝对时刻。**规则不递过去** —— 原生只做「弹队首、续队尾」，
        // 规则判断全在 Dart 侧（那边有测试），否则就成了第二份实现。
        'repeatTimes':
            [for (final t in repeatTimes) t.millisecondsSinceEpoch],
      });
    } catch (e) {
      await appendLog('scheduleTodoReminder 失败: $e');
    }
  }
```

`scheduleNativeAlarm` 加同样的参数。它的**现有签名**是
`scheduleNativeAlarm(int id, DateTime fireAt, String label, {String? detail, int repeatType = 0, int hour = 0, int minute = 0, int weekdays = 0})`
（那些重复参数是自定义闹钟用的；铃声 URI 不在这里传 —— 原生 handler 自己去
SharedPreferences 读）。只加一个参数、只改一个键：

```dart
  /// 排一条**全屏响铃**的闹钟（班次 / 待办 / 自定义闹钟都走这里）。
  ///
  /// [repeatTimes] 非空时 `repeatType` 一律发 `3`（「时刻表驱动」）—— 原生侧用它
  /// 与自定义闹钟的 0/1/2 区分开：前者响完按队首续排，后者按 `nextDaily` /
  /// `nextWeekly` 重算。**两种续排方式不能混**（重复待办的那些边角在 Dart 侧，
  /// 原生不会算）。
  static Future<void> scheduleNativeAlarm(
    int id,
    DateTime fireAt,
    String label, {
    String? detail,
    int repeatType = 0,
    int hour = 0,
    int minute = 0,
    int weekdays = 0,
    List<DateTime> repeatTimes = const [],
  }) async {
    try {
      await _settingsChannel.invokeMethod('scheduleNativeAlarm', {
        'id': id,
        'millis': fireAt.millisecondsSinceEpoch,
        'label': label,
        'detail': detail,
        'repeatType': repeatTimes.isEmpty ? repeatType : 3,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays,
        // 后续几次的绝对时刻（升序）。规则**不递过去** —— 原生只做
        // 「弹队首、续队尾」，规则判断全在 Dart 侧（那边有测试）。
        'repeatTimes': [
          for (final t in repeatTimes) t.millisecondsSinceEpoch,
        ],
      });
      await logInfo(
          'scheduleNativeAlarm 成功: id=$id, label=$label, repeatType=$repeatType');
    } catch (e) {
      await appendLog('scheduleNativeAlarm 失败: $e');
    }
  }
```

同时：
- `rescheduleEventReminders` 的循环里加一条跳过：`if (e.seriesId != null) continue;`（理由见上面的注释）。
- `rescheduleAll` 里加一行：`await rescheduleRecurringReminders(await repo.listRecurringTodos());`
- 加常量：`static const _recurringBaseId = 40000;`（紧挨 `_eventBaseId`，并把那一段的号段说明补全）

- [ ] **Step 4: 跑测试确认全绿**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_alarm_plan_test.dart && ../toolchain/flutter/bin/flutter test`
Expected: 新用例 PASS；全套仍绿

- [ ] **Step 5: analyze + 提交**

```bash
cd app && ../toolchain/flutter/bin/flutter analyze
cd .. && git add app/lib/features/alarm/alarm_service.dart app/test/recurring_alarm_plan_test.dart
git commit -m "feat(todo): 重复待办提醒的排定计划（下次时刻 + 时刻表）"
```

---

### Task 6: 提醒——原生按时刻表续排

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/AlarmScheduler.kt`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/AlarmStore.kt`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/TodoReminderReceiver.kt`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/AlarmReceiver.kt`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/BootReceiver.kt`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/MainActivity.kt`
- Test: `app/test/recurring_native_guard_test.dart`（源码扫描；原生没有可跑的测试目标）

**Interfaces:**
- Consumes: Dart 侧传来的 `repeatTimes: long[]` 与 `repeatType = 3`
- Produces: `AlarmScheduler.nextPending(millis: Long, queue: LongArray, now: Long) → Pair<Long, LongArray>?`；`AlarmScheduler.scheduleQuiet(..., repeatTimes: LongArray = LongArray(0))`；`AlarmScheduler.schedule(..., repeatTimes: LongArray = LongArray(0))`；`AlarmStore.Quiet.repeatTimes` / `AlarmStore.Entry.repeatTimes`

- [ ] **Step 1: 写源码守门测试（先红）**

建 `app/test/recurring_native_guard_test.dart`：

```dart
// app/test/recurring_native_guard_test.dart
//
// 原生那一段（时刻表续排）**没有可跑的测试目标** —— 这个仓库里没有 Android
// 单元测试的夹具。所以照 `widget_fixed_cards_guard_test.dart` 的老办法：扫源码，
// 把「编译期没有保护、错了又不报错」的几处约定钉住。
//
// 钉的是行为的存在性，不是实现细节：
//  ① 队列的挑选规则只有一处（`nextPending`），不许在接收器里各写一份；
//  ② 安静提醒那条链路响完要续排；
//  ③ 落盘清单要能装下队列（否则重启后重复待办就不响了）；
//  ④ Dart 侧送的 key（`repeatTimes`）与原生读的 key 逐字一致。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final f = File(path);
  expect(f.existsSync(), true, reason: '找不到 $path —— 测试的工作目录应当是 app/');
  return f.readAsStringSync();
}

const _dir = 'android/app/src/main/kotlin/com/daoban/shiftassistantpro';

void main() {
  test('队列的挑选只有一处实现（`AlarmScheduler.nextPending`）', () {
    final scheduler = _read('$_dir/AlarmScheduler.kt');
    expect(scheduler.contains('fun nextPending('), true,
        reason: '挑「第一个还没过的时刻」这件事只能有一份实现');
    // 接收器 / 开机重排里**不许**各自再写一遍筛选逻辑
    for (final f in ['TodoReminderReceiver.kt', 'AlarmReceiver.kt', 'BootReceiver.kt']) {
      final kt = _read('$_dir/$f');
      expect(kt.contains('AlarmScheduler.nextPending('), true,
          reason: '$f 要用队列续排，就得走同一个函数');
    }
  });

  test('安静提醒响完要续排，且续排要走 scheduleQuiet（落盘与排定成对）', () {
    final kt = _read('$_dir/TodoReminderReceiver.kt');
    expect(kt.contains('getLongArrayExtra("repeatTimes")'), true);
    expect(kt.contains('AlarmScheduler.scheduleQuiet('), true,
        reason: '绕开 scheduleQuiet 直接排 = 清单里少一条，重启后就不响了');
  });

  test('落盘清单装得下时刻表（两份清单都要）', () {
    final store = _read('$_dir/AlarmStore.kt');
    expect(store.contains('val repeatTimes: List<Long>'), true,
        reason: 'Quiet 与 Entry 都要带队列，否则重启后重复待办不再续排');
    // JSON 写与读都要有这两个 key
    expect(RegExp(r'put\("repeatTimes"').allMatches(store).length,
        greaterThanOrEqualTo(2),
        reason: '两份清单的写盘各要一处');
    expect(RegExp(r'optJSONArray\("repeatTimes"\)').allMatches(store).length,
        greaterThanOrEqualTo(2),
        reason: '两份清单的读盘各要一处');
  });

  test('原生读的 key 与 Dart 侧送的 key 逐字一致', () {
    final dart = _read('lib/features/alarm/alarm_service.dart');
    expect(dart.contains("'repeatTimes':"), true,
        reason: 'Dart 侧要用这个 key 送时刻表');
    expect(_read('$_dir/AlarmScheduler.kt').contains('putExtra("repeatTimes"'),
        true);
  });

  test('时刻表驱动的响铃用 repeatType = 3 与自定义闹钟区分开', () {
    final dart = _read('lib/features/alarm/alarm_service.dart');
    expect(dart.contains('repeatTimes.isEmpty ? repeatType : 3'), true,
        reason: '队列优先于自定义闹钟的 nextDaily/nextWeekly 续排');
    expect(_read('$_dir/AlarmReceiver.kt').contains('repeatType == 3'), true);
    expect(_read('$_dir/BootReceiver.kt').contains('repeatType == 3'), true,
        reason: '重启后也要按同一条规则重排，否则重启一次就退回按星期重算');
  });
}
```

- [ ] **Step 2: 跑它确认红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_native_guard_test.dart`
Expected: FAIL（五条全红 —— 这些符号都还不存在）

- [ ] **Step 3: `AlarmScheduler` 加队列支持**

```kotlin
    /**
     * 从「本次时刻 + 后续队列」里挑出第一个还没过的时刻，连同剩下的队列。
     *
     * 队列是 Dart 侧算好的（`upcomingFireTimes`，见 `alarm_service.dart` 的
     * `planRecurringReminders`）。**规则判断一律不写在这里**：Kotlin 侧没有可跑的
     * 测试目标，而月末特例 / 多选星期几 / 提前提醒的偏移 / 夏令时这些边角照抄
     * 一份必然与 Dart 侧对不上 —— 症状还是「某天没响」这种不报错的。
     *
     * 全过了（或队列为空、时刻本身也过了）返回 null，由调用方决定「不再续排」。
     */
    fun nextPending(millis: Long, queue: LongArray, now: Long): Pair<Long, LongArray>? {
        val all = LongArray(queue.size + 1)
        all[0] = millis
        System.arraycopy(queue, 0, all, 1, queue.size)
        val idx = all.indexOfFirst { it > now }
        if (idx < 0) return null
        return all[idx] to all.copyOfRange(idx + 1, all.size)
    }
```

`scheduleQuiet` 加参数（默认空数组，既有调用点不受影响）：

```kotlin
    fun scheduleQuiet(
        context: Context,
        id: Int,
        millis: Long,
        title: String,
        body: String,
        repeatTimes: LongArray = LongArray(0)
    ) {
        val op = Intent(context, TodoReminderReceiver::class.java).apply {
            putExtra("id", id)
            putExtra("title", title)
            putExtra("body", body)
            // 后续几次的绝对时刻。空数组表示一次性提醒（既有行为不变）。
            putExtra("repeatTimes", repeatTimes)
        }
        ...
        AlarmStore.putQuiet(
            context,
            AlarmStore.Quiet(
                id = id, millis = millis, title = title, body = body,
                repeatTimes = repeatTimes.toList()
            )
        )
    }
```

`schedule` 同样加 `repeatTimes: LongArray = LongArray(0)`：塞进 operation 的 extras、并写进 `AlarmStore.Entry`。**注意 `showIntent` 那枚 PendingIntent 不用带**（它只负责点通知回 App）。

- [ ] **Step 4: `AlarmStore` 两份清单都带上队列**

```kotlin
    data class Entry(
        val id: Int,
        val millis: Long,
        val label: String,
        val uri: String?,
        val repeatType: Int,
        val hour: Int,
        val minute: Int,
        val weekdays: Int,
        val detail: String?,
        /** 时刻表驱动（`repeatType == 3`）时，后面还跟着的几次点火时刻（升序）。 */
        val repeatTimes: List<Long> = emptyList(),
    )

    data class Quiet(
        val id: Int,
        val millis: Long,
        val title: String,
        val body: String,
        /** 同上：重复待办的提醒靠它续排，空 = 一次性。 */
        val repeatTimes: List<Long> = emptyList(),
    )
```

读盘各加一处（`all()` 与 `allQuiets()`）：

```kotlin
                    repeatTimes = o.optJSONArray("repeatTimes")?.let { a ->
                        (0 until a.length()).map { a.optLong(it, 0L) }
                    }?.filter { it > 0L } ?: emptyList(),
```

写盘各加一处（`write()` 与 `writeQuiets()`）：

```kotlin
                    put("repeatTimes", JSONArray().apply { e.repeatTimes.forEach { put(it) } })
```

并把文件顶部那段号段说明更新成新范围（见任务 7）。

- [ ] **Step 5: 两个接收器 + 开机重排**

`TodoReminderReceiver.onReceive`：

```kotlin
        val title = intent.getStringExtra("title") ?: return
        val body = intent.getStringExtra("body") ?: ""
        val id = intent.getIntExtra("id", 0)
        val queue = intent.getLongArrayExtra("repeatTimes") ?: LongArray(0)
        AlarmLog.info(context, "TodoReminderReceiver: id=$id, title=$title, 队列=${queue.size}")

        // **触发即消费**：先续排（或消费掉）落盘清单里这条。放在最前面是有意的
        // —— 后面每条提前 return（没通知权限等）都算「已经到过点」，留着它只会让
        // 下次重启时 BootReceiver 把一条过期提醒当成新排的。
        //
        // 重复待办在这里就续上了下一次：队首是 Dart 侧算好的下一个时刻，所以
        // **App 长期不开也不会漏**。
        val pending = AlarmScheduler.nextPending(0L, queue, System.currentTimeMillis())
        if (pending == null) {
            AlarmStore.removeQuiet(context, id)
        } else {
            AlarmScheduler.scheduleQuiet(
                context, id, pending.first, title, body, pending.second
            )
        }
        // ↑ 这一段替换掉原来那句 `AlarmStore.removeQuiet(context, id)`
```

`AlarmReceiver`：在「3) 重复闹钟续排下一次」那个 `when` **之前**插入：

```kotlin
        // 3) 续排下一次
        val now = System.currentTimeMillis()
        val queue = intent.getLongArrayExtra("repeatTimes") ?: LongArray(0)
        // 时刻表驱动（重复待办）优先：队首是 Dart 侧算好的下一个时刻。
        // 与下面自定义闹钟的 nextDaily / nextWeekly 是两套，不能混。
        if (repeatType == 3) {
            val pending = AlarmScheduler.nextPending(0L, queue, now)
            if (pending == null) {
                AlarmStore.remove(context, id)
            } else {
                AlarmScheduler.schedule(
                    context, id, pending.first, label, uri,
                    repeatType, hour, minute, weekdays, detail, pending.second
                )
            }
            return
        }
        when (repeatType) { ... 原样不动 ... }
```

`BootReceiver` 的安静提醒那一段：

```kotlin
        for (q in AlarmStore.allQuiets(context)) {
            // 「本次时刻 + 队列」里挑第一个还没过的 —— 重复待办的提醒靠它续排，
            // 一次性提醒（队列为空）走的还是老语义：过期的丢掉、不补。
            val pending = AlarmScheduler.nextPending(
                q.millis, q.repeatTimes.toLongArray(), now
            )
            if (pending == null) {
                AlarmStore.removeQuiet(context, q.id)
                continue
            }
            try {
                AlarmScheduler.scheduleQuiet(
                    context, q.id, pending.first, q.title, q.body, pending.second
                )
                quiets++
            } catch (ex: Exception) { ... }
        }
```

`BootReceiver` 的闹钟那一段：在 `val next = when (e.repeatType) {` 之前加同样的一支（`repeatType == 3` → `nextPending(e.millis, e.repeatTimes.toLongArray(), now)`，为 null 则 `remove` + `continue`，否则 `schedule(..., pending.second)` + `rescheduled++` + `continue`）。

`MainActivity` 的 `scheduleTodoReminder` 与 `scheduleNativeAlarm` 两个 handler：把 `repeatTimes` 从 `call.argument<List<*>>("repeatTimes")` 读出来、转成 `LongArray` 传进去（Dart 的 `List<int>` 过通道之后是 `List<*>`，元素是 `Long` 或 `Int`，要按 `Number` 取 `toLong()`）。

- [ ] **Step 6: 跑守门测试 + 构建**

```bash
cd app && ../toolchain/flutter/bin/flutter test test/recurring_native_guard_test.dart
cd .. && ROOT="$PWD" && export JAVA_HOME="$ROOT/toolchain/jdk" ANDROID_HOME="$ROOT/toolchain/android-sdk" GRADLE_USER_HOME="$ROOT/toolchain/gradle-home" PUB_CACHE="$ROOT/toolchain/pub-cache"
cd app && ../toolchain/flutter/bin/flutter build apk --release --target-platform android-arm64
```
Expected: 守门测试 PASS；APK 构建成功（**这一步同时验证 Kotlin 编译得过**）

- [ ] **Step 7: 提交**

```bash
git add app/android/app/src/main/kotlin app/test/recurring_native_guard_test.dart
git commit -m "feat(alarm): 原生按时刻表续排（重复待办 App 不开也不漏）"
```

---

### Task 7: 号段与取消（顺带修掉一个既有隐患）

**Files:**
- Modify: `AlarmScheduler.kt`、`AlarmStore.kt`、`MainActivity.kt`、`WidgetRenderer.kt`（只改号段说明的注释）
- Test: `app/test/recurring_native_guard_test.dart`（追加两条）

**Interfaces:**
- Produces: `AlarmScheduler.RECURRING_BASE_ID = 40000`；`AlarmScheduler.cancelTodoReminders(context: Context)`（**签名去掉 from/to**）；`AlarmStore.clearEntries(context, from, to)`

- [ ] **Step 1: 追加守门用例（先红）**

在 `recurring_native_guard_test.dart` 的 `main()` 末尾加：

```dart
  test('号段：待办行在 20000 段、重复系列在 40000 段，且互不重叠', () {
    final s = _read('$_dir/AlarmScheduler.kt');
    expect(s.contains('TODO_BASE_ID = 20000'), true);
    expect(s.contains('RECURRING_BASE_ID = 40000'), true);
    // 上界：待办段不许伸进系列段
    expect(s.contains('RECURRING_BASE_ID + 2000'), true,
        reason: '取消与清单清理的范围要覆盖到系列段的上界');
  });

  test('取消改成按落盘清单走，不再盲目扫一大段 id', () {
    final s = _read('$_dir/AlarmScheduler.kt');
    final body = s.substring(s.indexOf('fun cancelTodoReminders'));
    expect(body.contains('AlarmStore.all('), true,
        reason: '先取消清单里记着的那几条');
    expect(body.contains('AlarmStore.allQuiets('), true,
        reason: '两份清单都要（响铃那条走 Entry，安静那条走 Quiet）');
    expect(body.contains('for (i in from until to)'), false,
        reason: '别再扫一大段 —— 号段已经到两万，每勾一次待办都要跑一遍');
  });
```

- [ ] **Step 2: 跑它确认红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_native_guard_test.dart`
Expected: 新增两条 FAIL

- [ ] **Step 3: 改 `AlarmScheduler`**

```kotlin
    /**
     * 待办提醒的原生 id 基址（id = 20000 + 数据库里那一行的自增 id）。
     *
     * **AUTOINCREMENT 永不复用**，所以这个号只增不减。留到 39999（两万槽）：
     * 一个「每天」的重复待办每完成一次就产生一行，两三年就能把一千个号用光，
     * 而从前只留了 1000 —— 越界之后提醒**排得下去、谁也取消不掉**（幽灵提醒）。
     */
    const val TODO_BASE_ID = 20000

    /**
     * 重复待办提醒的原生 id 基址（id = 40000 + 系列的自增 id）。
     *
     * **与待办行的号段分开**是有意的：系列的条数由用户手建，几十条就到头了，而
     * 待办行会越攒越多 —— 两者共用一个自增序列的话，行号迟早把提醒的号挤出去。
     * 留到 41999。
     */
    const val RECURRING_BASE_ID = 40000
```

`cancelTodoReminders` 整个换掉：

```kotlin
    /**
     * 取消全部待办提醒与待办闹钟。
     *
     * **按落盘清单逐个撤，不再盲目扫一大段 id。** 从前扫的是固定 1000 个号，而
     * 现在待办提醒能排到 `RECURRING_BASE_ID` 附近 —— 盲扫会变成几万次
     * `PendingIntent` 操作，而**每勾一次待办都要跑一遍这一段**。
     *
     * 末尾保留一小段盲扫（`TODO_BASE_ID .. +1000`）：只为清掉「升级前排下、清单里
     * 还没有」的陈旧记录。这一段的开销与从前的实现相同。
     */
    fun cancelTodoReminders(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // **两种目标都要取消**：同一条待办按「联动闹钟」开关二选一 —— 开走
        // AlarmReceiver（响铃），关走 TodoReminderReceiver（通知）。两者用的是
        // 同一个 id，只取消一种就会把另一种留成幽灵闹钟，到点还会响。
        val targets = listOf(AlarmReceiver::class.java, TodoReminderReceiver::class.java)
        val upper = RECURRING_BASE_ID + 2000
        val ids = mutableSetOf<Int>()
        // ① 清单里记着的（准确、量小）
        for (e in AlarmStore.all(context)) if (e.id in TODO_BASE_ID until upper) ids.add(e.id)
        for (q in AlarmStore.allQuiets(context)) if (q.id in TODO_BASE_ID until upper) ids.add(q.id)
        // ② 一小段盲扫兜底：旧版本用过、清单里没有的那些
        for (i in 0 until 1000) ids.add(TODO_BASE_ID + i)

        for (id in ids) {
            for (target in targets) {
                try {
                    val pi = PendingIntent.getBroadcast(
                        context, id, Intent(context, target),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    am.cancel(pi)
                } catch (_: Exception) {
                }
            }
        }
        // 两份清单同步清掉这两段（清了之后 Dart 会把要留的重新排一遍）。
        AlarmStore.clearQuiets(context, TODO_BASE_ID, upper)
        AlarmStore.clearEntries(context, TODO_BASE_ID, upper)
    }
```

`MainActivity` 的 `cancelAllTodoReminders` handler 去掉 `from`/`to` 实参（现在只是 `AlarmScheduler.cancelTodoReminders(this)`），注释里的「一千次」改成「几百到几千次」。

- [ ] **Step 4: `AlarmStore` 加 `clearEntries`**

```kotlin
    /** 按 id 区间清闹钟清单（`AlarmScheduler.cancelTodoReminders` 收尾用）。 */
    @Synchronized
    fun clearEntries(context: Context, from: Int, to: Int) {
        try {
            write(context, all(context).filterNot { it.id in from until to })
        } catch (ex: Exception) {
            AlarmLog.error(context, "AlarmStore.clearEntries 失败: ${ex.message}")
        }
    }
```

并把文件顶部与 `WidgetRenderer.kt` 里那段号段说明的注释同步改成新范围（WidgetRenderer 只改注释，不改常量）。

- [ ] **Step 5: 跑测试 + 构建**

```bash
cd app && ../toolchain/flutter/bin/flutter test test/recurring_native_guard_test.dart
cd .. && ROOT="$PWD" && export JAVA_HOME="$ROOT/toolchain/jdk" ANDROID_HOME="$ROOT/toolchain/android-sdk" GRADLE_USER_HOME="$ROOT/toolchain/gradle-home" PUB_CACHE="$ROOT/toolchain/pub-cache"
cd app && ../toolchain/flutter/bin/flutter build apk --release --target-platform android-arm64
```
Expected: 守门测试全绿；APK 构建成功

- [ ] **Step 6: 提交**

```bash
git add app/android/app/src/main/kotlin app/test/recurring_native_guard_test.dart
git commit -m "fix(alarm): 待办提醒号段与取消改成按清单（顺带修掉号池烧穿的隐患）"
```

---

### Task 8: 抽出共享的「星期多选」控件

**Files:**
- Create: `app/lib/core/widgets/glass_weekday_picker.dart`
- Modify: `app/lib/features/alarm/alarm_screen.dart`（改用共享控件）
- Test: `app/test/alarm_screen_test.dart`（**既有用例必须保持全绿**）、`app/test/glass_weekday_picker_test.dart`（新增）

**Interfaces:**
- Produces: `GlassWeekdayPicker({required int value, required ValueChanged<int> onChanged})` —— `value` 是位掩码（`1 << (weekday - 1)`），点一下 toggle 一位并通过 `onChanged` 回新的掩码

- [ ] **Step 1: 写失败的测试**

建 `app/test/glass_weekday_picker_test.dart`：

```dart
// app/test/glass_weekday_picker_test.dart
//
// 星期多选：待办弹窗与闹钟弹窗共用同一个控件。
//
// 抽出来之前它在 `alarm_screen.dart` 的弹窗里是内联的 —— 待办弹窗再抄一份就是
// 第二份实现，而这类「配方」一旦抄歪（缺一位、位序反了）**不会报错**：只是某个
// 星期永远选不上，或者选周三却存在周四。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_weekday_picker.dart';

void main() {
  setUp(() => L10n.locale = 'zh');

  testWidgets('点一下加一位，再点一下减一位；位序是「周一 = 1 << 0」',
      (tester) async {
    var value = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => GlassWeekdayPicker(
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    ));

    // 周三 = 3 = 1 << 2
    await tester.tap(find.text(L10n.weekday(2)));
    await tester.pumpAndSettle();
    expect(value, 1 << 2);

    // 再加周一 = 1 << 0
    await tester.tap(find.text(L10n.weekday(0)));
    await tester.pumpAndSettle();
    expect(value, (1 << 0) | (1 << 2));

    // 再点周三 → 去掉它
    await tester.tap(find.text(L10n.weekday(2)));
    await tester.pumpAndSettle();
    expect(value, 1 << 0);
  });

  testWidgets('七天都在，且顺序是周一到周日', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlassWeekdayPicker(value: 0, onChanged: (_) {}),
      ),
    ));
    for (var i = 0; i < 7; i++) {
      expect(find.text(L10n.weekday(i)), findsOneWidget);
    }
    final xs = [
      for (var i = 0; i < 7; i++) tester.getTopLeft(find.text(L10n.weekday(i))).dx,
    ];
    expect(xs, List.of(xs)..sort(), reason: '从左到右就是周一到周日');
  });
}
```

- [ ] **Step 2: 跑它确认红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/glass_weekday_picker_test.dart`
Expected: 编译失败 —— 控件还不存在

- [ ] **Step 3: 写控件（把 `alarm_screen.dart` 里那段**整块搬过来**）**

要搬的是 `alarm_screen.dart` 里 `_showAlarmDialog` 的 `if (repeatType == 2) Wrap(...)`
那一整块（从这行起，到关闭 `Wrap` 的那个 `),` 为止 —— 它是 `Column` 的 `children: [...]`
里紧邻的下一项）。**逐字搬**，只改三处：

1. `weekdays` → `value`；
2. `setState(() { if (selected) weekdays &= ~bit; else weekdays |= bit; })` →
   `onChanged(selected ? value & ~bit : value | bit)`（**外面那个 `GestureDetector` 的
   `onTap` 要留着**，它才是点击的载体）；
3. `Theme.of(context).brightness == Brightness.dark` 那个 `isDark` 挪进 `build` 里
   （原处它在更外层，搬到控件里之后就地取）。

**视觉一个像素都不许变**：`AnimatedContainer` 的 `duration: AppTokens.durMed`、
`curve: Curves.easeOutBack`、内边距 `spaceMd / spaceSm`、圆角 `radiusL`、选中色
`colorScheme.primary`、未选中浅色 0.72 / 深色 0.08、描边 0.65 / 0.16、文字
`labelSecondary` + 选中 w700 / 未选中 w500 + 选中白字 —— 全部原样。

建 `app/lib/core/widgets/glass_weekday_picker.dart`，内容就是把 `alarm_screen.dart` 的 `Wrap` 那一段（`spacing: AppTokens.gapIconText` … 七个 `AnimatedContainer`）原样搬进一个 `StatelessWidget`，把 `weekdays` 换成 `value`、`setState(() {...})` 换成 `onChanged(新的掩码)`：

```dart
/// 星期多选：一排七个胶囊，点一下 toggle 一位。
///
/// [value] 是位掩码 `1 << (weekday - 1)`（周一 = 1），与 `DateTime.weekday`、
/// `CustomAlarms.weekdays`、`RecurringTodo.weekdays` 同一约定 —— 四处同序是这套
/// 东西能对上的前提，所以**位序写在这里一次**，调用点不许自己移位。
///
/// 待办弹窗（重复待办那条「每周」）与闹钟弹窗（自定义闹钟的「每周」）共用它。
class GlassWeekdayPicker extends StatelessWidget {
  const GlassWeekdayPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: AppTokens.gapIconText,
      children: List.generate(7, (i) {
        final bit = 1 << i;
        final selected = (value & bit) != 0;
        return GestureDetector(
          onTap: () => onChanged(selected ? value & ~bit : value | bit),
          child: AnimatedContainer(
            duration: AppTokens.durMed,
            curve: Curves.easeOutBack,
            padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMd, vertical: AppTokens.spaceSm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.radiusL),
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.72)),
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white.withValues(alpha: isDark ? 0.16 : 0.65),
              ),
            ),
            child: Text(
              L10n.weekday(i),
              // 基线 13px：未选中 w500、选中 w700（与 `alarm_screen` 原来那段同值）。
              style: AppTokens.labelSecondary.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        );
      }),
    );
  }
}
```

**不要在调用点补触觉**：这一档是「选中变了」，而 `AnimatedContainer` 不是共享的触发点 —— 由调用方在 `onChanged` 里判断「真的变了」再 `Haptics.select()`。开工前先读一眼 `core/haptics.dart` 顶部那张名单：如果判定它属于「已经发过」的那一类，就**一记都不要加**，并在注释里写明理由。

- [ ] **Step 4: 让闹钟弹窗改用它**

把 `alarm_screen.dart` 里 `if (repeatType == 2) Wrap(...)` 那一段换成：

```dart
              if (repeatType == 2)
                GlassWeekdayPicker(
                  value: weekdays,
                  onChanged: (v) => setState(() => weekdays = v),
                ),
```

删掉那段内联代码与它专用的局部变量（`isDark` 等只在那一处的话），补 import。

- [ ] **Step 5: 跑既有测试确认没坏**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/alarm_screen_test.dart test/glass_weekday_picker_test.dart`
Expected: 全绿（**闹钟那几条既有用例是这次抽取的安全网**，红了就是搬歪了）

- [ ] **Step 6: analyze + 全量测试 + 提交**

```bash
cd app && ../toolchain/flutter/bin/flutter analyze && ../toolchain/flutter/bin/flutter test
cd .. && git add app/lib/core/widgets/glass_weekday_picker.dart app/lib/features/alarm/alarm_screen.dart app/test/glass_weekday_picker_test.dart
git commit -m "refactor(ui): 星期多选抽成共享控件（待办弹窗要用同一份）"
```

---

### Task 9: 待办弹窗加「重复」那一行

**Files:**
- Modify: `app/lib/features/schedule/schedule_screen.dart`
- Test: `app/test/recurring_dialog_test.dart`

**Interfaces:**
- Consumes: 任务 1 的 `RecurRepeat`；任务 3 的 `addRecurringTodo` / `updateRecurringTodo` / `listRecurringTodos`；任务 8 的 `GlassWeekdayPicker`
- Produces: `_EventFields` 新增字段 `RecurRepeat? repeat` / `int weekdays` / `int monthDay` / `int? seriesId`，以及一个 `Future<void> commit(WidgetRef ref, ScheduleEvent? existing)`（把「新建/更新系列 + 建/更新那条行」这件有分支的事收在一处，供两个弹窗共用）

- [ ] **Step 1: 写失败的测试**

建 `app/test/recurring_dialog_test.dart`：

```dart
// app/test/recurring_dialog_test.dart
//
// 新建 / 编辑待办弹窗里的「重复」那一行。
//
// 重点不在「界面上有这一行」，而在**它落库落成了什么**：
//  ① 选了「每周三」→ 建出一个系列（weekdays 的位没歪）；
//  ② 编辑一条重复的行 → 改的是它背后的系列；
//  ③ 把重复改回「不重复」→ 解绑 + 删系列（行留下来，变成一次性待办）。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';

/// 有界推进若干帧（**不能用 `pumpAndSettle`**：页面上的权限 / 插件调用不会 resolve，
/// 无限动画会让它等到超时 —— 见 `todo_dialog_test.dart` 顶部那段）。
Future<void> _settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  late AppDatabase db;
  late AppRepository repo;

  setUp(() async {
    L10n.locale = 'zh';
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppRepository(db);
    await repo.ensureSeeded();
  });
  tearDown(() => db.close());

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: ScheduleScreen()),
    ));
    await _settle(tester);
  }

  testWidgets('新建：填标题 → 选「每周」→ 勾周三 → 添加，落成一个系列',
      (tester) async {
    await mount(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await _settle(tester);

    await tester.enterText(find.byType(TextField), '周三例会');
    // 重复那一行是四档胶囊
    await tester.tap(find.text(L10n.repeatWeekly));
    await _settle(tester);
    // 选「每周」之后出现星期胶囊
    await tester.tap(find.text(L10n.weekday(2))); // 周三
    await _settle(tester);

    await tester.tap(find.text(L10n.add));
    await _settle(tester);

    final series = await repo.listRecurringTodos();
    expect(series.length, 1);
    expect(series.single.title, '周三例会');
    expect(series.single.weekdays, 1 << 2);
    // 生成器还没跑过：行可能还没有。这条用例只管落库那一步。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('编辑一条重复的行：改的是它背后的系列', (tester) async {
    final id = await repo.addRecurringTodo(
      title: '周三例会',
      repeat: RecurRepeat.weekly,
      startDate: dateOnly(DateTime.now()),
      weekdays: 1 << 2,
    );
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    final e = (await repo.listEvents()).single;

    await mount(tester);
    await tester.tap(find.text('周三例会'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '周例会');
    await tester.tap(find.text(L10n.save));
    await _settle(tester);

    expect((await repo.listRecurringTodos()).single.title, '周例会');
    expect((await repo.listRecurringTodos()).single.id, id);
  });

  testWidgets('把周期从「每周三」改成「每周五」→ 当前那条被对齐到周五',
      (tester) async {
    // spec §4.2 末段：生成器只往前顺延、永不回退，所以**改周期这条路径要自己
    // 把当前那条对齐**。不对齐的话，「每周三」改成「每周五」之后，列表里那条
    // 还停在周三 —— 而下次到点又是周五，中间会错一次。
    final today = dateOnly(DateTime.now());
    await repo.addRecurringTodo(
      title: '周三例会',
      repeat: RecurRepeat.weekly,
      startDate: today,
      weekdays: 1 << 2, // 周三
    );
    await repo.advanceRecurringTodos(today: today);
    final before = (await repo.listEvents()).single;

    await mount(tester);
    await tester.tap(find.text('周三例会'));
    await _settle(tester);
    // 改星期：先去掉周三，再加周五（周五 = 1 << 4）
    await tester.tap(find.text(L10n.weekday(2)));
    await _settle(tester, frames: 4);
    await tester.tap(find.text(L10n.weekday(4)));
    await _settle(tester, frames: 4);
    await tester.tap(find.text(L10n.save));
    await _settle(tester);

    expect((await repo.listRecurringTodos()).single.weekdays, 1 << 4);
    final after = (await repo.listEvents()).single;
    expect(after.id, before.id, reason: '还是那一条，只换了日子');
    expect(after.date.weekday, DateTime.friday,
        reason: '对齐到新规则 —— 生成器不会替我们回退');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('把重复改回「不重复」→ 解绑并删系列，行留下', (tester) async {
    final id = await repo.addRecurringTodo(
      title: '周三例会',
      repeat: RecurRepeat.weekly,
      startDate: dateOnly(DateTime.now()),
      weekdays: 1 << 2,
    );
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));

    await mount(tester);
    await tester.tap(find.text('周三例会'));
    await _settle(tester);
    await tester.tap(find.text(L10n.repeatNone));
    await _settle(tester);
    await tester.tap(find.text(L10n.save));
    await _settle(tester);

    expect(await repo.listRecurringTodos(), isEmpty, reason: '系列该没了');
    final rows = await repo.listEvents();
    expect(rows.length, 1, reason: '行留下来，变成一条普通的一次性待办');
    expect(rows.single.seriesId, isNull);
    expect(id, isNotNull);
  });
}
```

- [ ] **Step 2: 跑它确认红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_dialog_test.dart`
Expected: 找不到 `L10n.repeatWeekly`（文案已在任务 1 加过 → 这步应当**找得到**），但点不动那四档胶囊 —— 界面还没加。第一条用例会红在 `find.text(L10n.repeatWeekly)` 找不到。

- [ ] **Step 3: 改 `_EventFields`**

在 `schedule_screen.dart` 的 `_EventFields` 里加字段与一行：

```dart
  /// 重复周期；null = 不重复。
  RecurRepeat? repeat;

  /// 每周的位掩码（`1 << (weekday - 1)`）。
  int weekdays;

  /// 每月的第几天（1..31）。
  int monthDay;

  /// 这条行属于哪个系列；null = 一次性待办。编辑既有行时带进来。
  int? seriesId;
```

构造函数加对应的可选参数（`this.repeat`、`int weekdays = 0`、`int monthDay = 1`、`this.seriesId`）。

`build(...)` 里在「日期」那一行**之前**插入（顺序：标题 → 重复 → 从哪天起 → 时间 → 提醒 → 联动闹钟）：

```dart
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.repeats),
        trailing: Text(repeat == null
            ? L10n.repeatNone
            : switch (repeat!) {
                RecurRepeat.daily => L10n.repeatDaily,
                RecurRepeat.weekly => L10n.repeatWeekly,
                RecurRepeat.monthly => L10n.repeatMonthly,
              }),
        onTap: () async {
          final picked = await showGlassOptionPicker<int>(
            context,
            title: L10n.repeats,
            options: const [0, 1, 2, 3], // 0 = 不重复，其余 = repeat.index + 1
            labelOf: (v) => switch (v) {
              1 => L10n.repeatDaily,
              2 => L10n.repeatWeekly,
              3 => L10n.repeatMonthly,
              _ => L10n.repeatNone,
            },
            selected: repeat == null ? 0 : repeat!.index + 1,
          );
          if (picked == null) return;
          setState(() {
            repeat = picked == 0 ? null : RecurRepeat.values[picked - 1];
          });
        },
      ),
      if (repeat == RecurRepeat.weekly)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
          child: GlassWeekdayPicker(
            value: weekdays,
            onChanged: (v) => setState(() => weekdays = v),
          ),
        ),
      if (repeat == RecurRepeat.monthly)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(L10n.repeatMonthly),
          trailing: Text('$monthDay'),
          onTap: () async {
            // 复用现成的数值选择器：`showGlassOptionPicker` 收 int，1..31 就是选项
            final picked = await showGlassOptionPicker<int>(
              context,
              title: L10n.repeatMonthly,
              options: [for (var d = 1; d <= 31; d++) d],
              labelOf: (d) => '$d',
              selected: monthDay,
            );
            if (picked != null) setState(() => monthDay = picked);
          },
        ),
```

「日期」那一行的标题改成动态：`Text(repeat == null ? L10n.date : L10n.startsOn)`。

再给 `_EventFields` 加一个把「系列 + 行」一起写库的方法（两个弹窗共用，避免两处各写一遍分支）：

```dart
  /// 把这一组字段落到库里：需要时先建 / 改系列，再建 / 改那条行。
  ///
  /// **收在一处是有意的**：这段有四个分支（新建一次性 / 新建重复 / 编辑一次性 /
  /// 编辑重复），抄两遍必然有一遍漏掉某个分支 —— 而漏掉不会报错，只是「改成重复
  /// 之后不生效」或者「解绑了系列还留着」。
  ///
  /// [existing] 为 null 表示新建。
  Future<void> commit(
    WidgetRef ref, {
    required String title,
    ScheduleEvent? existing,
  }) async {
    final repo = ref.read(appRepositoryProvider);
    var seriesId = this.seriesId;

    if (repeat == null) {
      // 从重复改回不重复：**解绑 + 删系列，一条待办都不删**。
      //
      // 这里**不能**用 `deleteRecurringTodo`（它连带删行）—— 那会把用户正在
      // 编辑的这条待办本身也删掉，而他想要的只是「以后别再自动出现」。
      if (seriesId != null) {
        await repo.unlinkRecurringSeries(seriesId);
        seriesId = null;
      }
    } else if (seriesId == null) {
      // 一次性改成重复（或新建一个重复的）：建系列
      seriesId = await repo.addRecurringTodo(
        title: title,
        repeat: repeat!,
        startDate: date,
        timeMinute: timeMinute,
        advanceRemindMinutes: advance,
        alarmEnabled: alarm,
        weekdays: weekdays,
        monthDay: monthDay,
      );
    } else {
      // 编辑既有系列：覆盖式写回。
      //
      // **显式全字段构造，不用 `copyWith`** —— copyWith 是 `?? this.x`，没有把
      // 可空字段清成 null 的通道，用户把提醒从「提前 5 分钟」改回「不设」时，
      // `advanceRemindMinutes: null` 会被丢掉、旧值原样留着，而界面上看不出来。
      final s = (await repo.listRecurringTodos())
          .firstWhere((x) => x.id == seriesId);
      await repo.updateRecurringTodo(RecurringTodo(
        id: s.id,
        title: title,
        repeat: repeat!,
        startDate: date,
        timeMinute: timeMinute,
        advanceRemindMinutes: advance,
        alarmEnabled: alarm,
        weekdays: weekdays,
        monthDay: monthDay,
        skipThrough: s.skipThrough,
        enabled: s.enabled,
      ));
    }

    if (existing == null) {
      await repo.addEvent(
        title: title,
        date: date,
        timeMinute: timeMinute,
        advanceRemindMinutes: advance,
        alarmEnabled: alarm,
        seriesId: seriesId,
      );
    } else {
      await repo.updateEvent(existing,
          title: title,
          date: date,
          timeMinute: timeMinute,
          advanceRemindMinutes: advance,
          alarmEnabled: alarm,
          seriesId: seriesId);
    }

    // 改完周期要把「当前这一次」对齐到新规则的最近一次发生日（spec §4.2 末段）。
    //
    // **这一步生成器不会替我们做**：它只往前顺延、永不回退（用户手工把这一次
    // 挪到别的日子时不许被拽回来），而「把每周三改成每周五」恰恰需要回退。
    // 两条路径的分工写在这里，免得后人把哪一边当成 bug 去改。
    if (seriesId != null) {
      final s = (await repo.listRecurringTodos())
          .firstWhere((x) => x.id == seriesId);
      final occ = occurrenceOnOrBefore(s, dateOnly(DateTime.now()));
      if (occ != null) {
        for (final r in (await repo.listEvents())
            .where((e) => e.seriesId == seriesId && !e.isCompleted)) {
          if (!isSameDay(r.date, occ)) await repo.setEventDate(r.id, occ);
        }
      }
    }
  }
```

> **注意**：`copyWith` 对可空字段是 `?? this.x`，**清不掉** `advanceRemindMinutes`（提醒改回「不设」时）。`RecurringTodo.copyWith` 因此要照 `schedule_editor_screen.dart` 里 `_editClass` 的老办法处理 —— **不要**指望 `copyWith(null)` 能清空。最省事的做法是别用 `copyWith`，直接 `RecurringTodo(...)` 全字段构造一遍（字段就十来个，写全了反而没有陷阱）。

- [ ] **Step 4: 两个弹窗改用 `commit`**

`_showAddDialog` 的「添加」回调改成：

```dart
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) return;
                    await fields.commit(ref, title: title);
                    await _rescheduleReminders(ref);
                    close();
```

`_showEditDialog` 的 `_EventFields(...)` 构造里带上 `repeat: <该系列>、weekdays: ...、monthDay: ...、seriesId: e.seriesId` —— 系列得先查出来：在 `_showEditDialog` 开头 `final series = e.seriesId == null ? null : (await ...)`。因为 `_showEditDialog` 目前是同步方法，把它改成 `Future<void>` 并在调用点 `await`（`_eventTile` 的 `onTap` 已经是 `async`）。

「保存」回调改成：

```dart
                    await ref.read(appRepositoryProvider); // 保持原有 import 结构
                    await fields.commit(ref, title: title, existing: e);
                    await _rescheduleReminders(ref);
                    close();
```

- [ ] **Step 5: 跑测试**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_dialog_test.dart`
Expected: PASS（3 条）

- [ ] **Step 6: analyze + 全量 + 提交**

```bash
cd app && ../toolchain/flutter/bin/flutter analyze && ../toolchain/flutter/bin/flutter test
cd .. && git add app/lib/features/schedule/schedule_screen.dart app/test/recurring_dialog_test.dart
git commit -m "feat(todo): 新建/编辑弹窗加「重复」那一行"
```

---

### Task 10: 列表标记 + 「删当前那条 = 这次不要了」

**Files:**
- Modify: `app/lib/features/schedule/schedule_screen.dart`
- Test: `app/test/recurring_screen_test.dart`

**Interfaces:**
- Consumes: 任务 3 的 `skipRecurringOccurrence`；任务 9 的 `_EventFields.commit`
- Produces: 列表行上的 ↻ 标记；删除当前那条时的确认与跳过

- [ ] **Step 1: 写失败的测试**

建 `app/test/recurring_screen_test.dart`：

```dart
// app/test/recurring_screen_test.dart
//
// 列表上的两件事：重复项有标记；删掉当前那条 = 「这次不要了」（不是删系列、
// 也不会被生成器补回来）。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/app_icon.dart';
import 'package:shiftassistantpro/core/widgets/glass_delete_button.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';

Future<void> _settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  late AppDatabase db;
  late AppRepository repo;

  setUp(() async {
    L10n.locale = 'zh';
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppRepository(db);
    await repo.ensureSeeded();
  });
  tearDown(() => db.close());

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: ScheduleScreen()),
    ));
    await _settle(tester);
  }

  Future<int> seed() async {
    final id = await repo.addRecurringTodo(
      title: '周三例会',
      repeat: RecurRepeat.weekly,
      startDate: dateOnly(DateTime.now()),
      weekdays: 1 << (DateTime.now().weekday - 1),
    );
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    return id;
  }

  testWidgets('重复项那一行带循环标记', (tester) async {
    await seed();
    await mount(tester);
    expect(
      find.descendant(
          of: find.byType(GlassTile), matching: find.byIcon(Icons.repeat)),
      findsOneWidget,
    );
  });

  testWidgets('删掉当前那条：确认之后系列还在，只是**这一次**不要了',
      (tester) async {
    final id = await seed();
    await mount(tester);

    await tester.tap(find.byType(GlassDeleteButton));
    await _settle(tester);
    // 确认框里说的是「这一次」，不是删整个系列
    expect(find.text(L10n.skipThisOccurrence), findsOneWidget);
    await tester.tap(find.text(L10n.skipThisOccurrence));
    await _settle(tester);

    expect((await repo.listRecurringTodos()).single.id, id, reason: '系列要留着');
    expect(await repo.listEvents(), isEmpty);

    // 再跑一次生成器：不该补回来（这就是「删不掉」的那条护栏）
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    expect(await repo.listEvents(), isEmpty);
  });

  testWidgets('确认框里的另一条路：删掉整个系列', (tester) async {
    await seed();
    await mount(tester);
    await tester.tap(find.byType(GlassDeleteButton));
    await _settle(tester);
    await tester.tap(find.text(L10n.deleteWholeSeries));
    await _settle(tester);
    expect(await repo.listRecurringTodos(), isEmpty);
    expect(await repo.listEvents(), isEmpty);
  });
}
```

- [ ] **Step 2: 跑它确认红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_screen_test.dart`
Expected: FAIL —— 找不到 `Icons.repeat`（还没加）。先在 `l10n.dart` 补两条文案：

```dart
  static String get skipThisOccurrence => t('只这一次不要了', 'Skip this one');
  static String get deleteWholeSeries => t('删除整个重复', 'Delete the whole repeat');
  static String get deleteRecurringTitle => t('这条待办是重复的', 'This todo repeats');
  static String deleteRecurringContent(String name) => t(
      '「$name」会每周/每月自己出现。你可以只跳过这一次，也可以把它以后都不再出现。',
      '"$name" comes back on its own. You can skip just this one, or stop it for good.');
```

- [ ] **Step 3: 改列表行**

`_eventTile` 的副标题那一行里，在铃铛之前加循环标记：

```dart
                    // 重复项：一眼看出「这不是一次性待办」。已完成的不给 ——
                    // 那一条是历史，标着「它会再来」反而让人以为还没完。
                    if (e.seriesId != null && !e.isCompleted) ...[
                      const SizedBox(width: AppTokens.gapIconText),
                      AppIcon(Icons.repeat,
                          size: AppTokens.iconSm,
                          color: AppTokens.inkMuted(context)),
                    ],
```

删除键的 `onPressed` 换成：

```dart
            onPressed: () async {
              final seriesId = e.seriesId;
              if (seriesId == null) {
                // 一次性待办：照旧直接删（一个字都不用问）
                await ref.read(appRepositoryProvider).deleteEvent(e);
              } else {
                final choice = await _askDeleteRecurring(context, e.title);
                if (choice == null || !context.mounted) return;
                final repo = ref.read(appRepositoryProvider);
                if (choice == _DeleteChoice.series) {
                  await repo.deleteRecurringTodo(seriesId);
                } else {
                  // 只跳过这一次：记下这次的日子，生成器在那天之前不再补
                  await repo.skipRecurringOccurrence(seriesId, e.date);
                  await repo.deleteEvent(e);
                }
              }
              await _rescheduleReminders(ref);
            },
```

配套：

```dart
enum _DeleteChoice { once, series }

/// 删一条重复待办时的二选一。
///
/// 必须问：直接删掉的话，生成器下一次打开 App 又会把它补出来（用户看到的是
/// 「删不掉」）；而直接删整个系列又会把「我这周不做」变成「以后都不做了」。
Future<_DeleteChoice?> _askDeleteRecurring(BuildContext context, String name) {
  return showDialog<_DeleteChoice>(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) => GlassDialog(
      title: L10n.deleteRecurringTitle,
      content: Text(L10n.deleteRecurringContent(name)),
      actions: [
        GlassActionButton(
          onPressed: () => Navigator.pop(context, _DeleteChoice.once),
          label: L10n.skipThisOccurrence,
        ),
        const SizedBox(width: 8),
        GlassActionButton(
          variant: GlassActionVariant.danger,
          onPressed: () => Navigator.pop(context, _DeleteChoice.series),
          label: L10n.deleteWholeSeries,
        ),
      ],
    ),
  );
}
```

**注意按钮不用 `dialogCloser`**：这两个回调都是同步 `pop`（不 await 任何东西），不存在「await 之后关窗」那条路径。只有**保存类**的异步动作才需要它。

- [ ] **Step 4: 跑测试**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_screen_test.dart`
Expected: PASS（3 条）

- [ ] **Step 5: analyze + 全量 + 提交**

```bash
cd app && ../toolchain/flutter/bin/flutter analyze && ../toolchain/flutter/bin/flutter test
cd .. && git add app/lib/features/schedule/schedule_screen.dart app/lib/core/l10n.dart app/test/recurring_screen_test.dart
git commit -m "feat(todo): 列表里的重复标记与「只这一次不要了」"
```

---

### Task 11: 管理面板

**Files:**
- Create: `app/lib/features/schedule/recurring_panel.dart`
- Modify: `app/lib/features/schedule/schedule_screen.dart`（标题行加入口）
- Test: `app/test/recurring_panel_test.dart`

**Interfaces:**
- Consumes: `recurringTodosProvider`；任务 3 的 `setRecurringEnabled` / `deleteRecurringTodo` / `listRecurringTodos`
- Produces: `Future<void> showRecurringTodosDialog(BuildContext context)`（顶层函数，只收 `context` —— 这样视觉工装能直接把它塞进 `_DialogHost`）

- [ ] **Step 1: 写失败的测试**

建 `app/test/recurring_panel_test.dart`：

```dart
// app/test/recurring_panel_test.dart
//
// 管理面板：入口在待办页标题那一行；面板里能停用、能删、能看到下一次什么时候。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_delete_button.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';

Future<void> _settle(WidgetTester tester, {int frames = 24}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  late AppDatabase db;
  late AppRepository repo;

  setUp(() async {
    L10n.locale = 'zh';
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppRepository(db);
    await repo.ensureSeeded();
  });
  tearDown(() => db.close());

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: ScheduleScreen()),
    ));
    await _settle(tester);
  }

  Future<int> seed() => repo.addRecurringTodo(
        title: '周三例会',
        repeat: RecurRepeat.weekly,
        startDate: dateOnly(DateTime.now()),
        weekdays: 1 << 2,
        timeMinute: 9 * 60,
      );

  testWidgets('标题旁有入口；点开能看到系列的周期与下一次', (tester) async {
    await seed();
    await mount(tester);

    await tester.tap(find.text(L10n.recurring));
    await _settle(tester);

    expect(find.text('周三例会'), findsWidgets);
    expect(find.textContaining(L10n.repeatWeekly), findsWidgets);
    expect(find.textContaining(L10n.nextTime('').trim()), findsWidgets);
  });

  testWidgets('面板里停用之后，系列真的落了库', (tester) async {
    await seed();
    await mount(tester);
    await tester.tap(find.text(L10n.recurring));
    await _settle(tester);

    await tester.tap(find.byType(GlassSwitch));
    await _settle(tester);
    expect((await repo.listRecurringTodos()).single.enabled, isFalse);
  });

  testWidgets('面板里删除要确认，确认后系列与它的行都没了', (tester) async {
    final id = await seed();
    await mount(tester);
    await tester.tap(find.text(L10n.recurring));
    await _settle(tester);

    await tester.tap(find.byType(GlassDeleteButton));
    await _settle(tester);
    await tester.tap(find.text(L10n.delete));
    await _settle(tester);

    expect(await repo.listRecurringTodos(), isEmpty);
    expect(id, isNotNull);
  });

  testWidgets('一条都没有时给一行空态说明', (tester) async {
    await mount(tester);
    await tester.tap(find.text(L10n.recurring));
    await _settle(tester);
    expect(find.text(L10n.recurringEmpty), findsOneWidget);
  });
}
```

先在 `l10n.dart` 补：

```dart
  static String get recurring => t('重复待办', 'Repeating');
  static String get recurringEmpty =>
      t('还没有重复待办。新建待办时把「重复」选上，它就会自己按期出现。',
          'No repeating todos yet. Pick a repeat when adding one and it comes back on its own.');
  static String nextTime(String d) => t('下次 $d', 'Next $d');
```

- [ ] **Step 2: 跑它确认红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_panel_test.dart`
Expected: FAIL —— 找不到入口文案

- [ ] **Step 3: 写面板**

```dart
// 重复待办的管理面板：列出全部系列，能改 / 停用 / 删。
//
// 形态是**弹窗**不是整页（照「我的模板」那个管理弹窗那套配方）：系列通常只有
// 几个，为它单开一页反而要多一次进出。
//
// 数据走 `recurringTodosProvider`（一次性读 + autoDispose）——**用流的话每条挂
// 这个弹窗的 widget 用例都会在拆树时报「A Timer is still pending」**
// （drift 取消查询流时排的零时长定时器），而且面板是个短命弹层，没必要挂流。
// 页内改 / 删之后由 `ref.invalidate` 重读。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/glass_delete_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_switch.dart';
import '../../data/app_repository.dart';
import '../../domain/recurring_todo.dart';
import 'schedule_screen.dart';

/// 弹出「重复待办」管理面板。
///
/// **只收 `context`**：视觉工装要把弹层塞进 `_DialogHost` 才拍得到（弹层是命令式
/// 的、没有可渲染的 widget），而那个薄壳只给 context。里面用 `Consumer` 取
/// provider，所以不需要外传 `ref`。
Future<void> showRecurringTodosDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) => const GlassDialog(
      title: L10n.recurring,
      showClose: true,
      content: _RecurringList(),
      actions: [],
    ),
  );
}

class _RecurringList extends ConsumerWidget {
  const _RecurringList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recurringTodosProvider);
    final series = async.valueOrNull;
    if (series == null) {
      return const Padding(
        padding: EdgeInsets.all(AppTokens.spaceLg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (series.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Text(
          L10n.recurringEmpty,
          style: AppTokens.rowSecondary
              .copyWith(color: AppTokens.inkMuted(context)),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [for (final s in series) _row(context, ref, s)],
    );
  }

  /// 一行一个系列。行的配方**逐字照排班管理页**（`GlassTile(enableBlur: false,
  /// padding: EdgeInsets.zero)` + `GlassPressable` + `ListTile` + 尾部紧凑删除钮）
  /// —— 那是全 app 的列表行做法，抄最近的同类件。
  Widget _row(BuildContext context, WidgetRef ref, RecurringTodo s) {
    final today = dateOnly(DateTime.now());
    final next = occurrenceOnOrBefore(s, today) ?? nextOccurrenceAfter(s, today);
    final parts = [
      s.ruleLabel,
      if (s.timeLabel.isNotEmpty) s.timeLabel,
      if (next != null) L10n.nextTime(L10n.monthDay(next)),
    ];
    return GlassTile(
      enableBlur: false,
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: EdgeInsets.zero,
      child: GlassPressable(
        child: ListTile(
          leading: AppIcon(Icons.repeat,
              size: AppTokens.iconMd,
              color: s.enabled
                  ? Theme.of(context).colorScheme.primary
                  : AppTokens.inkMuted(context)),
          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(parts.join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassSwitch(
                value: s.enabled,
                onChanged: (v) => _setEnabled(ref, s, v),
              ),
              GlassDeleteButton(
                compact: true,
                onPressed: () => _delete(context, ref, s),
              ),
            ],
          ),
          onTap: () => _edit(context, ref, s),
        ),
      ),
    );
  }

  /// 停用 / 启用。
  ///
  /// 两边都要跑一次生成器：**启用之后要让「当前这一次」立刻出现在列表里**，
  /// 停用之后要把那一串提醒撤掉（不然它还会照响）。
  Future<void> _setEnabled(WidgetRef ref, RecurringTodo s, bool v) async {
    final repo = ref.read(appRepositoryProvider);
    await repo.setRecurringEnabled(s.id!, v);
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    await AlarmService.rescheduleAll(repo);
    ref.invalidate(recurringTodosProvider);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, RecurringTodo s) async {
    final repo = ref.read(appRepositoryProvider);
    final row = (await repo.listEvents())
        .where((e) => e.seriesId == s.id && !e.isCompleted)
        .toList();
    if (row.isEmpty) {
      // 没有「当前这一次」就没地方挂那个编辑弹窗（它编的是**行**，顺带写回系列）。
      // 不另做一个只编系列的界面：那种情况很少（起始日在将来 / 刚跳过），
      // 明说一句比多一套界面划算。
      if (context.mounted) {
        showGlassSnack(context, L10n.recurringNoCurrent, icon: Icons.info_outline);
      }
      return;
    }
    await showEditEventDialog(context, ref, row.single);
    ref.invalidate(recurringTodosProvider);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, RecurringTodo s) async {
    final n = (await ref.read(appRepositoryProvider).listEvents())
        .where((e) => e.seriesId == s.id)
        .length;
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => GlassDialog(
        title: L10n.deleteRecurringTitle,
        content: Text(L10n.deleteSeriesContent(s.title, n)),
        actions: [
          GlassActionButton(
            onPressed: () => Navigator.pop(context, false),
            label: L10n.cancel,
          ),
          const SizedBox(width: 8),
          GlassActionButton(
            variant: GlassActionVariant.danger,
            onPressed: () => Navigator.pop(context, true),
            label: L10n.delete,
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(appRepositoryProvider);
    await repo.deleteRecurringTodo(s.id!);
    await AlarmService.rescheduleAll(repo);
    ref.invalidate(recurringTodosProvider);
  }
}
```

配套补三条文案与两个 import：

```dart
  static String get recurringNoCurrent => t(
      '这个重复现在没有「下一次」（起始日在将来，或这一次刚被你跳过）',
      'This repeat has no current occurrence right now (it starts later, or you just skipped this one)');
  static String deleteSeriesContent(String name, int n) => n == 0
      ? t('「$name」以后不会再自己出现了。', '"$name" will no longer come back on its own.')
      : t('「$name」以后不会再自己出现了，已经出现的 $n 条（含已完成的历史）也会一起删掉。',
          '"$name" will no longer come back, and its $n existing entries (including completed history) will be deleted.');
```

`recurring_panel.dart` 还要 `import '../alarm/alarm_service.dart';`（`rescheduleAll`）与
`import '../../core/widgets/glass_action_button.dart';`、`import '../../core/widgets/glass_snackbar.dart';`。

- [ ] **Step 3b: 把编辑弹窗提成顶层函数**

`schedule_screen.dart` 里的 `void _showEditDialog(BuildContext context, WidgetRef ref, ScheduleEvent e)`
**搬出 `_ScheduleScreenState` 类**，变成同文件顶层的
`Future<void> showEditEventDialog(BuildContext context, WidgetRef ref, ScheduleEvent e)`；
类里原来的两处调用（列表行 `onTap`）改成调这个顶层函数。

私有类 `_EventFields` 是**库级私有**，同文件顶层的函数照样能用，所以这次搬家不用改它的可见性。

- [ ] **Step 4: 接入入口**

`schedule_screen.dart` 的标题那一行改成：

```dart
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Text(L10n.titleTodo, style: AppTokens.pageTitle),
                  const Spacer(),
                  // 与「选择你的倒班方式」页里分组标题旁那个「管理」同一套写法：
                  // 一个文字按钮，不抢标题。
                  GlassPressable(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.spaceSm,
                          vertical: AppTokens.spaceXs),
                      child: Text(L10n.recurring,
                          style: AppTokens.labelSecondary.copyWith(
                              color: Theme.of(context).colorScheme.primary)),
                    ),
                  ),
                ],
              ),
            ),
```

`onTap: () => showRecurringTodosDialog(context)`（外面包一层 `GestureDetector`）。**待办页要从 `ConsumerWidget` 变成 `ConsumerStatefulWidget`**：任务 12 要挂 lifecycle observer，一次改到位。

- [ ] **Step 5: 跑测试**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_panel_test.dart`
Expected: PASS（4 条）

- [ ] **Step 6: analyze + 全量 + 提交**

```bash
cd app && ../toolchain/flutter/bin/flutter analyze && ../toolchain/flutter/bin/flutter test
cd .. && git add app/lib/features/schedule/recurring_panel.dart app/lib/features/schedule/schedule_screen.dart app/lib/core/l10n.dart app/test/recurring_panel_test.dart
git commit -m "feat(todo): 重复待办的管理面板"
```

---

### Task 12: 生成器的三个触发点

**Files:**
- Modify: `app/lib/features/home/home_shell.dart`
- Modify: `app/lib/features/schedule/schedule_screen.dart`（回到前台）
- Test: `app/test/recurring_advance_hooks_test.dart`

**Interfaces:**
- Consumes: 任务 4 的 `advanceRecurringTodos`
- Produces: 启动闸 / 回前台 / 改完系列之后都会跑一次生成器

- [ ] **Step 1: 写失败的测试**

建 `app/test/recurring_advance_hooks_test.dart`：

```dart
// app/test/recurring_advance_hooks_test.dart
//
// 生成器要在三个时点跑：App 启动、回到前台、改完系列之后。
//
// 漏掉「回到前台」的后果最隐蔽：App 一直没关、跨过午夜之后列表不会动 ——
// 因为列表是 drift 流，**不写库就不会重发**。用户看到的是「昨天的日期还在那儿」。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';

Future<void> _settle(WidgetTester tester, {int frames = 24}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  late AppDatabase db;
  late AppRepository repo;

  setUp(() async {
    L10n.locale = 'zh';
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppRepository(db);
    await repo.ensureSeeded();
  });
  tearDown(() => db.close());

  testWidgets('打开待办页会把「当前这一次」补齐（启动/进页面都算）',
      (tester) async {
    await repo.addRecurringTodo(
      title: '周三例会',
      repeat: RecurRepeat.daily,
      startDate: dateOnly(DateTime.now()),
      timeMinute: 9 * 60,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: ScheduleScreen()),
    ));
    await _settle(tester);
    expect((await repo.listEvents()).length, 1, reason: '进页面就该看到今天这一条');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('回到前台会再跑一次（跨过午夜的那条路径）', (tester) async {
    // 造一条「昨天的」当前行，模拟 App 一直开着跨过了午夜
    final id = await repo.addRecurringTodo(
      title: '周三例会',
      repeat: RecurRepeat.daily,
      startDate: dateOnly(DateTime.now().subtract(const Duration(days: 5))),
      timeMinute: 9 * 60,
    );
    await repo.advanceRecurringTodos(
        today: dateOnly(DateTime.now().subtract(const Duration(days: 1))));

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: ScheduleScreen()),
    ));
    await _settle(tester);
    // 模拟「回到前台」
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);

    final rows = await repo.listEvents();
    expect(rows.single.date, dateOnly(DateTime.now()),
        reason: '回到前台要顺延到今天，否则界面上一直挂着昨天的日期');
    expect(rows.single.seriesId, id);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });
}
```

- [ ] **Step 2: 跑它确认红**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_advance_hooks_test.dart`
Expected: FAIL（两条 —— 页面没跑生成器）

- [ ] **Step 3: 待办页挂钩**

`ScheduleScreen` 改成 `ConsumerStatefulWidget`，State 里：

```dart
class _ScheduleScreenState extends ConsumerState<ScheduleScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 首帧之前不能写库（还没挂进树），但也不用等到帧后：这一下是纯数据操作，
    // 写完 drift 流会把列表重发一次。
    WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台要补跑一次：App 没关、跨过午夜的情况下，drift 流不会自己重发，
    // 界面上会一直挂着昨天的日期（与 `alarm_screen` 重建「今天」是同一个场景）。
    if (state == AppLifecycleState.resumed) _advance();
  }

  Future<void> _advance() async {
    final repo = ref.read(appRepositoryProvider);
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    await _rescheduleReminders(ref);
  }
  ...
}
```

`build` 里原来用 `ref.watch(...)` 的地方不变（`ConsumerState` 有 `ref`）。原来 `ScheduleScreen extends ConsumerWidget` 的 `build(context, ref)` 签名改成 `build(context)`。

- [ ] **Step 4: 壳子挂钩（启动闸）**

`home_shell.dart` 的 `_tryStartupReschedule` 里，**在排提醒之前**先跑生成器：

```dart
  Future<void> _tryStartupReschedule() async {
    if (_startupRescheduled) return;
    final sched = ref.read(activeScheduleProvider).valueOrNull?.toDomain();
    final alarms = ref.read(customAlarmsProvider).valueOrNull;
    final events = ref.read(eventsProvider).valueOrNull;
    if (sched == null || alarms == null || events == null) return;
    _startupRescheduled = true;
    final repo = ref.read(appRepositoryProvider);
    // **先生成、再重排**：重复待办的提醒要按「今天该有的那一条」来排，
    // 顺序反了会拿上一轮的日期去算。
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    final overrides = await repo.listShiftAlarmOverrides();
    // 待办要**重新读一次**：上面那几个流里拿到的 `events` 是生成**之前**的快照，
    // 直接用它排会漏掉刚建出来的那几条（而重复待办的提醒本来就走另一条链路，
    // 但一次性待办的那几条不能少）。
    AlarmService.reschedule(
      sched,
      alarms,
      overrides: overrides,
      events: await repo.listEvents(),
    );
  }
```

> 注意 `reschedule` 的 `events` 参数是上面读到的那个流值 —— 它可能是**生成之前**的。把这一行改成重新读一次：`await row.listEvents()`（`repo.listEvents()`），保证排的是刚生成完的那份。

- [ ] **Step 5: 跑测试**

Run: `cd app && ../toolchain/flutter/bin/flutter test test/recurring_advance_hooks_test.dart test/home_shell_nav_test.dart`
Expected: 全绿

- [ ] **Step 6: analyze + 全量 + 提交**

```bash
cd app && ../toolchain/flutter/bin/flutter analyze && ../toolchain/flutter/bin/flutter test
cd .. && git add app/lib/features/home/home_shell.dart app/lib/features/schedule/schedule_screen.dart app/test/recurring_advance_hooks_test.dart
git commit -m "feat(todo): 生成器的三个触发点（启动 / 回前台 / 进页面）"
```

---

### Task 13: 视觉工装

**Files:**
- Modify: `app/tool/visual/visual_harness.dart`（加种子）
- Modify: `app/tool/visual/visual_screens.dart`（两屏）
- Modify: `app/tool/visual/render_screens_test.dart`（一屏交互式）

**Interfaces:**
- Consumes: 任务 11 的 `showRecurringTodosDialog`；视觉工装既有的 `_DialogHost`
- Produces: `21_todos_recurring`、`22_recurring_panel`、`23_todo_dialog_weekly` 三张图

- [ ] **Step 1: 加种子数据**

`visual_harness.dart` 里加（照 `seedMyTemplates` 的写法）：

```dart
/// 给待办页预置一条重复待办 + 一条普通待办，让「有重复项」那个状态画得出来。
///
/// 不预置的话待办页是空态，新加的循环标记、管理入口一个都拍不到。
Future<void> seedRecurringTodo(AppDatabase db) async {
  final repo = AppRepository(db);
  final today = dateOnly(DateTime.now());
  final id = await repo.addRecurringTodo(
    title: '周三例会',
    repeat: RecurRepeat.weekly,
    startDate: today,
    weekdays: 1 << (today.weekday - 1),
    timeMinute: 9 * 60,
    advanceRemindMinutes: 0,
  );
  await repo.advanceRecurringTodos(today: today);
  await repo.addEvent(
      title: '交体检报告',
      date: today,
      timeMinute: 17 * 60,
      advanceRemindMinutes: 60);
  // id 只用来确认种子生效，不用在断言里
  assert(id > 0);
}
```

- [ ] **Step 2: 加两屏**

`visual_screens.dart` 的 `visualScreens` 列表里加（放在 `05_todos` 之后）：

```dart
  (
    // 「今天有一条重复待办」的待办页：循环标记 + 标题旁的「重复」入口都在这屏。
    slug: '21_todos_recurring',
    title: '待办 · 含重复项',
    build: (db) async {
      await seedRecurringTodo(db);
      return const ScheduleScreen();
    },
    needsOnboardingPrefs: false,
  ),
  (
    // 管理面板是**弹层**（命令式、没有可渲染的 widget），要一层薄壳把它弹出来
    // —— 与 `_DialogHost` 那两张（开始使用 / 使用帮助）同一套路。
    slug: '22_recurring_panel',
    title: '重复待办 · 管理面板',
    build: (db) async {
      await seedRecurringTodo(db);
      return const _DialogHost(showRecurringTodosDialog);
    },
    needsOnboardingPrefs: false,
  ),
```

（`_DialogHost` 的构造是 `_DialogHost(this.show)`，类型是 `void Function(BuildContext)` —— `showRecurringTodosDialog` 返回 `Future<void>`，**包一层** `(c) => showRecurringTodosDialog(c)` 或把它改成 `void Function` 可接受的形式；`_DialogHost` 里那句 `widget.show(context)` 对返回 Future 的函数不 await 也没问题。）

- [ ] **Step 3: 加交互式那一屏**

`render_screens_test.dart` 末尾加（照「日历 · 点开某天」的 `beforeCapture` 写法）。
这个文件目前**没有** import `core/l10n.dart`，记得补上（要用 `L10n.repeatWeekly`）：

```dart
  // 新建弹窗里选了「每周」的样子：星期胶囊那一排的间距、选中态只有看图才知道
  // 对不对。它是**内部状态**（`_EventFields` 不是公开的），只能靠首帧之后真点。
  // 同理它没进 `visualScreens`（记录类型加可选字段要改全部 24 条），对比度审计
  // 因此不覆盖这一张 —— 这屏用的全是既有令牌与既有配色。
  visualTest('待办 · 新建弹窗选了每周', (tester) async {
    failOnOverflow(tester);
    final db = await freshDb();
    await renderScreen(
      tester,
      name: '23_todo_dialog_weekly',
      home: const ScheduleScreen(),
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      beforeCapture: (t) async {
        await t.tap(find.byType(FloatingActionButton));
        await settleVisual(t);
        await t.tap(find.text(L10n.repeatWeekly));
        await settleVisual(t);
      },
    );
  });
```

- [ ] **Step 4: 出图并看图**

Run: `cd app && ../toolchain/flutter/bin/flutter test tool/visual/render_screens_test.dart`
然后**逐张看** `app/build/visual/21_todos_recurring_light.png`、`22_recurring_panel_light.png`、`23_todo_dialog_weekly_light.png`：
- 循环标记的大小与颜色是否与旁边的小铃铛同一档（`iconSm` + `inkMuted`）
- 标题旁的「重复」入口有没有抢标题、有没有贴边
- 面板里副标题的「每周三 · 09:00 · 下次 10月21日」在 400dp 宽下有没有被截
- 星期胶囊那一排在弹窗里会不会挤（7 个 × 内边距 + 间距）

Expected: 三张图都符合预期；`failOnOverflow` 不报

- [ ] **Step 5: 跑工装全套 + 对比度审计**

Run: `cd app && ../toolchain/flutter/bin/flutter test tool/visual/`
Expected: 全绿（含对比度审计）

- [ ] **Step 6: 提交**

```bash
git add app/tool/visual app/test
git commit -m "test(visual): 待办含重复项 / 管理面板 / 新建弹窗三张图"
```

---

### Task 14: 文档与收尾

**Files:**
- Modify: `PRODUCT_SPEC.md`、`AGENTS.md`
- Create: `tools/gh/release-notes-v<新版本>.md`（版本号由用户定 `X.Y`，AI 只动末位）
- Modify: `app/pubspec.yaml`、`app/lib/core/app_info.dart`、`app/lib/features/profile/app_dialogs.dart`

- [ ] **Step 1: 版本号 + 更新日志**

- `app/pubspec.yaml` 的 `version:` 末位 +1、`build` +1；`app/lib/core/app_info.dart` 的 `appVersion` 同步（`app_info_test.dart` 盯着）。
- `app_dialogs.dart` 的 `_changelogZh` / `_changelogEn` **prepend** 新版本的条目、**删掉最旧一条**（窗口恒 10 条）——
  `test/changelog_window_test.dart` 会自动验：zh/en 各 10 条、版本号严格递减、首条等于 `appVersion`。
- 条目内容只写用户看得见的：重复待办（每天 / 每周几 / 每月某日）、到点自己出现、勾过的留成历史、到点顺延、提醒 App 不开也照响、待办页的管理入口。

- [ ] **Step 2: `PRODUCT_SPEC.md`**

- §2「待办日程」那一节：补重复待办这一段（四种周期里选三种、当前那一条的生成与顺延规则、跳过语义、与提醒的关系）。
- §4 数据模型：表清单加 `RecurringTodos`、`ScheduleEvents` 加 `seriesId`、`schemaVersion = 10` **改成 11**，并补一行 v10 → v11 的迁移说明。
- 抬头版本号与「功能范围（现状 vX.Y.Z）」。

- [ ] **Step 3: `AGENTS.md`**

- 版本史追加一条。
- 「最近改动」加 v 新版本那一节（写清：四个已定决策、生成器的六条规则、「提醒排下一次不排这一条」这个坑、时刻表为什么放 Dart 侧、号段与取消的改动）。
- 「关键决策与坑」补三条（照 spec §11 的头三条展开）：
  1. **重复待办的提醒排的是「下一次的触发时刻」，不是当前那一条的日期**；
  2. **规则不复制进 Kotlin**：时刻表在 Dart 侧算好，原生只做「弹队首、续队尾」；`repeatType = 3` 是它与自定义闹钟的分界；
  3. **生成器只往前顺延、永不回退**，所以「改周期」这条路径要自己把当前那条对齐（别当 bug 改）。
- Drift 表清单加 `RecurringTodos`，`schemaVersion = 10` 改成 11。
- 验收标准里的测试条数按实际更新。

- [ ] **Step 4: 发布说明**

`tools/gh/release-notes-v<版本>.md`：照 `release-notes-v0.9.9.md` 那套结构（一句话开场 / 新增 / 修复 / 说明），只写用户看得见的东西 + 「已知取舍」（App 长期不开也不漏提醒是靠原生续排；停用不会收走已经出现的那一条）。

- [ ] **Step 5: 全量验证**

```bash
cd app && ../toolchain/flutter/bin/flutter analyze && ../toolchain/flutter/bin/flutter test && ../toolchain/flutter/bin/flutter test tool/visual/
```
Expected: `No issues found!`；两条测试全绿

- [ ] **Step 6: 构建 + 提交**

```bash
cd .. && ROOT="$PWD" && export JAVA_HOME="$ROOT/toolchain/jdk" ANDROID_HOME="$ROOT/toolchain/android-sdk" GRADLE_USER_HOME="$ROOT/toolchain/gradle-home" PUB_CACHE="$ROOT/toolchain/pub-cache"
cd app && ../toolchain/flutter/bin/flutter build apk --release --target-platform android-arm64
cd .. && cp app/build/app/outputs/flutter-apk/app-release.apk "dist/倒班助手Pro-v<版本>.apk"
AAPT=$(ls toolchain/android-sdk/build-tools/*/aapt2.exe | head -1) && "$AAPT" dump badging "dist/倒班助手Pro-v<版本>.apk" | head -1
git add -A && git commit -m "chore(release): v<版本>（重复待办）"
```

---

## 执行完的收尾清单（照 `AGENTS.md`）

- [ ] `git push origin beta` → `git tag v<版本> && git push origin v<版本>` → `scripts/release.ps1 -SkipConfirm`
      （**必须先设 `GH_CONFIG_DIR=C:\Users\Alec\AppData\Roaming\GitHub CLI`**，否则 `gh` 找不到登录态）
- [ ] 发完 `curl` 一次 `main` 上的 `latest.json` 核对版本号
- [ ] 真机验证（本机没有测试目标的那几处）：新建一个「每周三 09:00」→ 看列表里出现、看闹钟页不出现它、改手机日期到下周看它顺延、删当前那条再进页面看不复活
