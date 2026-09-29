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
  int? id = 1,
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
    final plans =
        planRecurringReminders([_s()], from: DateTime(2026, 9, 23, 15));
    expect(plans.length, 1);
    expect(plans.single.seriesId, 1);
    expect(plans.single.fireAt, DateTime(2026, 9, 30, 9),
        reason: '下午打开也要排上下一次，否则这条重复待办的提醒永远排不上');
  });

  test('队首之外还带着后面几次（原生续排用），且不含队首', () {
    final plans =
        planRecurringReminders([_s()], from: DateTime(2026, 9, 23, 15));
    expect(plans.single.repeatTimes.first, DateTime(2026, 10, 7, 9));
    expect(plans.single.repeatTimes.contains(DateTime(2026, 9, 30, 9)), isFalse,
        reason: '队首已经单独排了，队列里不能重复带上它');
    expect(plans.single.repeatTimes.length, greaterThan(1));
  });

  test('没设提醒档位 / 停用 → 这个系列不进计划', () {
    expect(
        planRecurringReminders([_s(advance: null)],
            from: DateTime(2026, 9, 23, 15)),
        isEmpty);
    expect(
        planRecurringReminders([_s(enabled: false)],
            from: DateTime(2026, 9, 23, 15)),
        isEmpty);
  });

  test('没设时间的按全天那档的钟点排', () {
    final plans = planRecurringReminders([_s(timeMinute: null)],
        from: DateTime(2026, 9, 23, 8));
    // `allDayReminderHour` 是 `alarm_service.dart` 的**顶层**常量（不是
    // `AlarmService` 的静态成员）——它与 `eventReminderTime` 里那一档同源。
    expect(plans.single.fireAt, DateTime(2026, 9, 23, allDayReminderHour, 0));
  });

  test('多个系列各自一条计划', () {
    final plans = planRecurringReminders([_s(id: 1), _s(id: 2)],
        from: DateTime(2026, 9, 23, 15));
    expect(plans.map((p) => p.seriesId).toList(), [1, 2]);
  });

  test('id 为 null（还没落库）的系列跳过，不排', () {
    // 提醒的 id 是 `_recurringBaseId + 系列 id`，没有 id 就没有稳定的号。
    expect(
        planRecurringReminders([_s(id: null)],
            from: DateTime(2026, 9, 23, 15)),
        isEmpty);
  });

  test('计划里的时刻都是「从现在往后」且升序（队首 + 队列一起看）', () {
    final plans =
        planRecurringReminders([_s()], from: DateTime(2026, 9, 23, 15));
    final all = [plans.single.fireAt, ...plans.single.repeatTimes];
    for (var i = 1; i < all.length; i++) {
      expect(all[i].isAfter(all[i - 1]), isTrue);
    }
  });
}
