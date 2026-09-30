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

/// 周五 = 5 → 掩码位 `1 << 4`。
const _fri = 1 << 4;

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
          occurrenceOnOrBefore(_s(repeat: RecurRepeat.weekly, weekdays: _wed),
              DateTime.utc(2026, 9, 22)),
          DateTime.utc(2026, 9, 16));
    });

    test('每周三：今天正是周三 → 就是今天', () {
      // 2026-09-23 是周三
      expect(
          occurrenceOnOrBefore(_s(repeat: RecurRepeat.weekly, weekdays: _wed),
              DateTime.utc(2026, 9, 23)),
          DateTime.utc(2026, 9, 23));
    });

    test('每周一三五（多选）：周三那天是周三，周日退回周五', () {
      final s = _s(repeat: RecurRepeat.weekly, weekdays: _mon | _wed | _fri);
      expect(occurrenceOnOrBefore(s, DateTime.utc(2026, 9, 23)), // 周三
          DateTime.utc(2026, 9, 23));
      expect(occurrenceOnOrBefore(s, DateTime.utc(2026, 9, 27)), // 周日
          DateTime.utc(2026, 9, 25)); // 周五
    });

    test('每月 15 号：本月 15 号还没到 → 退回上个月 15 号', () {
      expect(
          occurrenceOnOrBefore(_s(repeat: RecurRepeat.monthly, monthDay: 15),
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
          occurrenceOnOrBefore(_s(repeat: RecurRepeat.weekly, weekdays: 0),
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
          nextOccurrenceAfter(_s(repeat: RecurRepeat.weekly, weekdays: _wed),
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
          repeat: RecurRepeat.weekly,
          weekdays: _wed,
          timeMinute: 9 * 60,
          advance: 0);
      final times = upcomingFireTimes(s,
          from: DateTime(2026, 9, 23, 15), clockMinute: 9 * 60);
      expect(times.first, DateTime(2026, 9, 30, 9));
    });

    test('今天这次还没到 → 第一条就是今天', () {
      final s = _s(
          repeat: RecurRepeat.weekly,
          weekdays: _wed,
          timeMinute: 9 * 60,
          advance: 0);
      final times = upcomingFireTimes(s,
          from: DateTime(2026, 9, 23, 8), clockMinute: 9 * 60);
      expect(times.first, DateTime(2026, 9, 23, 9));
    });

    test('提前一天的那档：触发时刻落在**前一天**', () {
      // 周三 09:00 的会、提前一天提醒 → 那一条排在**周二** 09:00。
      // 取一个「本周二早上」当 from：本次（周三 9/23）的提醒时刻 9/22 09:00
      // 还没到，所以第一条就是它。
      final s = _s(
          repeat: RecurRepeat.weekly,
          weekdays: _wed,
          timeMinute: 9 * 60,
          advance: 1440);
      final times = upcomingFireTimes(s,
          from: DateTime(2026, 9, 22, 8), clockMinute: 9 * 60);
      expect(times.first, DateTime(2026, 9, 22, 9));
      expect(times.first.weekday, DateTime.tuesday);
    });

    test('不提醒（提醒档位为空）→ 空表', () {
      expect(
          upcomingFireTimes(_s(timeMinute: 9 * 60),
              from: DateTime(2026, 9, 23), clockMinute: 9 * 60),
          isEmpty);
    });

    test('停用 → 空表', () {
      final s = _s(timeMinute: 9 * 60, advance: 0, enabled: false);
      expect(
          upcomingFireTimes(s, from: DateTime(2026, 9, 23), clockMinute: 9 * 60),
          isEmpty);
    });

    test('每天的那档：180 天就是 180 条，且按时间升序', () {
      // 2026-01-01 起每天 09:00，从 2026-09-23 08:00 往后数
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
    expect(_s(repeat: RecurRepeat.monthly, monthDay: 1).ruleLabel, '每月 1 号');
    // 多选：拼成「每周一、三、五」而不是「每周周一、周三、周五」
    expect(_s(repeat: RecurRepeat.weekly, weekdays: _mon | _wed | _fri).ruleLabel,
        '每周一、三、五');
    // 掩码为空是脏数据：退回不带星期的说法，而不是拼出一串空的「每周」
    expect(_s(repeat: RecurRepeat.weekly, weekdays: 0).ruleLabel, '每周');
    // 带时间的整串
    expect(_s(repeat: RecurRepeat.weekly, weekdays: _wed, timeMinute: 9 * 60)
        .ruleWithTime, '每周三 · 09:00');
  });
}
