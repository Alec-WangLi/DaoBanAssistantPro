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
import 'package:shiftassistantpro/domain/shift_rotation.dart';

RecurringTodo _s({
  RecurRepeat repeat = RecurRepeat.daily,
  DateTime? start,
  int weekdays = 0,
  int monthDays = 1,
  List<String> shiftNames = const [],
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
      monthDays: monthDays,
      shiftNames: shiftNames,
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
          occurrenceOnOrBefore(_s(repeat: RecurRepeat.monthly, monthDays: 1 << 14),
              DateTime.utc(2026, 9, 10)),
          DateTime.utc(2026, 8, 15));
    });

    test('每月 31 号：**2 月落在 28 号**，3 月回到 31 号', () {
      final s = _s(repeat: RecurRepeat.monthly, monthDays: 1 << 30);
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
                  monthDays: 1 << 30,
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


  group('每月多选', () {
    test('每月 1 号与 15 号：前后查询各取最近的一天', () {
      final s = _s(
          repeat: RecurRepeat.monthly, monthDays: (1 << 0) | (1 << 14));
      expect(occurrenceOnOrBefore(s, DateTime.utc(2026, 3, 20)),
          DateTime.utc(2026, 3, 15));
      expect(occurrenceOnOrBefore(s, DateTime.utc(2026, 3, 10)),
          DateTime.utc(2026, 3, 1));
      expect(nextOccurrenceAfter(s, DateTime.utc(2026, 3, 1)),
          DateTime.utc(2026, 3, 15));
    });

    test('2 月选 29/30/31：夹到月末并去重，只出现一天', () {
      final s = _s(
          repeat: RecurRepeat.monthly,
          monthDays: (1 << 28) | (1 << 29) | (1 << 30));
      expect(occurrenceOnOrBefore(s, DateTime.utc(2027, 2, 28)),
          DateTime.utc(2027, 2, 28));
      expect(nextOccurrenceAfter(s, DateTime.utc(2027, 2, 28)),
          DateTime.utc(2027, 3, 29)); // 3 月：29/30/31 各自成立
    });

    test('monthDays == 0 是脏数据，不出发生日', () {
      expect(
          occurrenceOnOrBefore(_s(repeat: RecurRepeat.monthly, monthDays: 0),
              DateTime.utc(2026, 9, 1)),
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


  group('按班次', () {
    final shift = _s(repeat: RecurRepeat.shift, shiftNames: ['上夜班']);
    // 回调返回的是**班次定义**（提醒落点要用起止时间），不再是名字。
    const nightShift = ShiftClass(name: '上夜班', startMinute: 1230, endMinute: 1920);
    const dayShift = ShiftClass(name: '白班', startMinute: 480, endMinute: 1080);
    ShiftClass? night(DateTime d) =>
        d.weekday == DateTime.wednesday ? nightShift : dayShift;

    test('发生日 = 班次名匹配的那天（前后都找）', () {
      expect(
          occurrenceOnOrBefore(shift, DateTime.utc(2026, 9, 25),
              shiftOn: night),
          DateTime.utc(2026, 9, 23));
      expect(
          nextOccurrenceAfter(shift, DateTime.utc(2026, 9, 20),
              shiftOn: night),
          DateTime.utc(2026, 9, 23));
    });

    test('没给 resolver / 名字为空：一律无发生日', () {
      expect(occurrenceOnOrBefore(shift, DateTime.utc(2026, 9, 25)), isNull);
      expect(
          occurrenceOnOrBefore(
              _s(repeat: RecurRepeat.shift, shiftNames: const []),
              DateTime.utc(2026, 9, 25),
              shiftOn: night),
          isNull);
    });

    test('多选：任一班次名命中都算', () {
      final s = _s(repeat: RecurRepeat.shift, shiftNames: ['上夜班', '白班']);
      expect(
          occurrenceOnOrBefore(s, DateTime.utc(2026, 9, 22),
              shiftOn: night),
          DateTime.utc(2026, 9, 22));
    });

    test('起始日之前的班次不算', () {
      final s = _s(
          repeat: RecurRepeat.shift,
          shiftNames: ['上夜班'],
          start: DateTime.utc(2026, 9, 24));
      expect(
          occurrenceOnOrBefore(s, DateTime.utc(2026, 9, 25),
              shiftOn: night),
          isNull);
    });

    test('ruleLabel 用班次名字拼，不带日期', () {
      expect(shift.ruleLabel, L10n.everyShift(['上夜班']));
    });
  });

  group('按班次 · 落点（与班次闹钟同一判据）', () {
    // 夜班 20:30–次日 08:30：回绕式存法 end = 510
    const night = ShiftClass(name: '夜班', startMinute: 1230, endMinute: 510);
    const nightCum = ShiftClass(name: '夜班', startMinute: 1230, endMinute: 1950);
    const zero = ShiftClass(name: '零点班', startMinute: 0, endMinute: 360);
    const duty = ShiftClass(name: '值班', startMinute: 480, endMinute: 1920);
    const rest = ShiftClass(name: '休班', isRest: true);

    // **班次日必须稀疏**：每天都命中时，落点只是把「哪一天的钟点」重新贴了个
    // 标签，整串时刻与「发生日 + 钟点」完全一样 —— 那样的用例改不改实现都绿。
    ShiftClass? Function(DateTime) onDays(
            Map<int, ShiftClass> byDay) =>
        (DateTime d) => byDay[d.day];

    RecurringTodo shiftAt(int clock, {List<String> names = const ['夜班']}) =>
        _s(
            repeat: RecurRepeat.shift,
            shiftNames: names,
            timeMinute: clock,
            advance: 0);

    final only22 = onDays({22: night});
    final only23Zero = onDays({23: zero});

    test('班中钟点 → 次日（不是发生日当天的凌晨）', () {
      final times = upcomingFireTimes(shiftAt(0),
          from: DateTime(2026, 9, 21, 12),
          clockMinute: 0,
          shiftOn: only22);
      // 22 日夜班 20:30–次日 08:30 的 00:00 → 23 日 00:00；改前会是 22 日 00:00。
      expect(times.first, DateTime(2026, 9, 23, 0));
    });

    test('班中后段（07:00）同样落次日', () {
      final times = upcomingFireTimes(shiftAt(7 * 60),
          from: DateTime(2026, 9, 21, 12),
          clockMinute: 7 * 60,
          shiftOn: only22);
      expect(times.first, DateTime(2026, 9, 23, 7));
    });

    test('上班前的 19:00 → 当天', () {
      final times = upcomingFireTimes(shiftAt(19 * 60),
          from: DateTime(2026, 9, 21, 12),
          clockMinute: 19 * 60,
          shiftOn: only22);
      expect(times.first, DateTime(2026, 9, 22, 19));
    });

    test('窗口外的 10:00 离下班更近 → 次日', () {
      final times = upcomingFireTimes(shiftAt(10 * 60),
          from: DateTime(2026, 9, 21, 12),
          clockMinute: 10 * 60,
          shiftOn: only22);
      expect(times.first, DateTime(2026, 9, 23, 10));
    });

    test('零点班 23:00 → 前一天', () {
      final times = upcomingFireTimes(shiftAt(23 * 60, names: const ['零点班']),
          from: DateTime(2026, 9, 21, 12),
          clockMinute: 23 * 60,
          shiftOn: only23Zero);
      expect(times.first, DateTime(2026, 9, 22, 23));
    });

    test('24 小时值班：全天都算当天', () {
      final times = upcomingFireTimes(shiftAt(7 * 60, names: const ['值班']),
          from: DateTime(2026, 9, 21, 12),
          clockMinute: 7 * 60,
          shiftOn: onDays({22: duty}));
      expect(times.first, DateTime(2026, 9, 22, 7));
    });

    test('两种 endMinute 存法同解', () {
      for (final sh in [night, nightCum]) {
        final times = upcomingFireTimes(shiftAt(0),
            from: DateTime(2026, 9, 21, 12),
            clockMinute: 0,
            shiftOn: onDays({22: sh}));
        expect(times.first, DateTime(2026, 9, 23, 0), reason: '$sh');
      }
    });

    test('提醒钟点正好等于下班钟点 → 落到次日那一刻', () {
      final times = upcomingFireTimes(shiftAt(8 * 60 + 30),
          from: DateTime(2026, 9, 21, 12),
          clockMinute: 8 * 60 + 30,
          shiftOn: only22);
      expect(times.first, DateTime(2026, 9, 23, 8, 30));
    });

    test('班次没有上下班时间（休班）→ 落点当天', () {
      final times = upcomingFireTimes(shiftAt(0, names: const ['休班']),
          from: DateTime(2026, 9, 21, 12),
          clockMinute: 0,
          shiftOn: onDays({22: rest}));
      expect(times.first, DateTime(2026, 9, 22, 0));
    });

    test('提前量作用在落点之后（00:00 提前 5 分钟 → 发生日 23:55）', () {
      final s = _s(
          repeat: RecurRepeat.shift,
          shiftNames: const ['夜班'],
          timeMinute: 0,
          advance: 5);
      final times = upcomingFireTimes(s,
          from: DateTime(2026, 9, 21, 12),
          clockMinute: 0,
          shiftOn: only22);
      expect(times.first, DateTime(2026, 9, 22, 23, 55));
    });

    test('from 恰好等于那条提醒、且它属于昨天那次：不能漏', () {
      // 22、23 都是夜班；22 日的 00:15 提醒落在 23 日 00:15，from 正好取这一刻。
      // **两天都要是班次日**：否则 `occurrenceOnOrBefore(from)` 直接就给昨天那次，
      // 「窗口要从昨天起算」这条根本测不出来。相等也算「不早于」。
      final s = _s(
          repeat: RecurRepeat.shift,
          shiftNames: const ['夜班'],
          timeMinute: 15,
          advance: 0);
      final times = upcomingFireTimes(s,
          from: DateTime(2026, 9, 23, 0, 15),
          clockMinute: 15,
          shiftOn: onDays({22: night, 23: night}));
      expect(times.first, DateTime(2026, 9, 23, 0, 15));
    });

    test('相邻两次倒序（21/22 夜班 + 23 零点班，配 07:00）→ 输出必须升序', () {
      // 21 夜班 → 22 日 07:00；22 夜班 → 23 日 07:00；23 零点班 → 22 日 07:00。
      // 扫描顺序是第三天的 22 日、第一天的 22 日、第二天的 23 日 —— 不排序就是倒序队列。
      final times = upcomingFireTimes(shiftAt(7 * 60,
              names: const ['夜班', '零点班']),
          from: DateTime(2026, 9, 20, 12),
          clockMinute: 7 * 60,
          shiftOn: onDays({21: night, 22: night, 23: zero}));
      expect(times.take(2).toList(),
          [DateTime(2026, 9, 22, 7), DateTime(2026, 9, 23, 7)]);
      // 只看前两条抓不到「9/23 之后又冒出 9/22」那种乱序 —— 整条队列都要严格升序。
      for (var i = 1; i < times.length; i++) {
        expect(times[i].isAfter(times[i - 1]), isTrue,
            reason: '队列第 $i 条不在前一条之后：${times[i - 1]} → ${times[i]}');
      }
    });

    test('相邻两次落成同一时刻 → 只排一条', () {
      // 22 日夜班 00:15 → 23 日 00:15（next）；23 日零点班 00:15 → 23 日 00:15（窗口内）。
      // `onDays` 按「几号」匹配，所以下一次同样的一对在 10 月 22/23 日。
      final times = upcomingFireTimes(shiftAt(15,
              names: const ['夜班', '零点班']),
          from: DateTime(2026, 9, 20, 12),
          clockMinute: 15,
          shiftOn: onDays({22: night, 23: zero}));
      expect(times.take(2).toList(),
          [DateTime(2026, 9, 23, 0, 15), DateTime(2026, 10, 23, 0, 15)]);
    });

    test('全天提醒不套落点', () {
      final s =
          _s(repeat: RecurRepeat.shift, shiftNames: const ['夜班'], advance: 0);
      final times = upcomingFireTimes(s,
          from: DateTime(2026, 9, 21, 12),
          clockMinute: 9 * 60,
          shiftOn: only22);
      expect(times.first, DateTime(2026, 9, 22, 9)); // 发生日当天 9 点
    });
  });


  test('规则描述：提醒正文用它，且不带日期', () {
    expect(_s(repeat: RecurRepeat.daily, timeMinute: 9 * 60).ruleLabel, '每天');
    expect(
        _s(repeat: RecurRepeat.weekly, weekdays: _wed).ruleLabel, '每周三');
    expect(_s(repeat: RecurRepeat.monthly, monthDays: 1).ruleLabel, '每月 1 号');
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
