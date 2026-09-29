// app/test/schedule_chain_test.dart
//
// 「某天归哪套方案」的解析 —— 全是纯函数，边界比正例多。
//
// 这些函数错了**不会报错**：只会「某几天显示成另一套班表的班」，而且只有翻到
// 那一天才看得见。所以边界要逐条钉住：闭区间的两端、起点为空、终点为空、
// 重叠时的胜负、以及没有一套覆盖时的兜底。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/schedule_chain.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

/// 一套只有名字不同的方案 —— 断言时靠 name 分辨谁赢。
ShiftSchedule _sched(String name) => ShiftSchedule(
      name: name,
      anchorDate: DateTime.utc(2026, 1, 1),
      classes: [
        ShiftClass(
            name: '$name-白', abbr: '白', startMinute: 480, endMinute: 1080),
        ShiftClass(name: '$name-休', abbr: '休', isRest: true),
      ],
      // 周期 2 天：单数日白班、双数日休班（相对 anchor）。
      cycle: const [0, 1],
    );

DateTime _d(int y, int m, int day) => DateTime.utc(y, m, day);

ScheduleSpan _span(String name, {int id = 1, DateTime? from, DateTime? to}) =>
    ScheduleSpan(id: id, schedule: _sched(name), from: from, to: to);

void main() {
  group('ScheduleSpan.covers —— 闭区间', () {
    test('两端当天**都算**覆盖', () {
      final s = _span('A', from: _d(2026, 1, 1), to: _d(2026, 6, 30));
      expect(s.covers(_d(2026, 1, 1)), isTrue);
      expect(s.covers(_d(2026, 6, 30)), isTrue);
      // 关键的两个「差一天」
      expect(s.covers(_d(2025, 12, 31)), isFalse);
      expect(s.covers(_d(2026, 7, 1)), isFalse);
    });

    test('起点为空 = 不限起点；终点为空 = 一直持续', () {
      final open = _span('A', to: _d(2026, 6, 30));
      expect(open.covers(_d(1999, 1, 1)), isTrue);
      expect(open.covers(_d(2026, 7, 1)), isFalse);

      final forever = _span('A', from: _d(2026, 1, 1));
      expect(forever.covers(_d(2222, 1, 1)), isTrue);
      expect(forever.covers(_d(2025, 12, 31)), isFalse);
    });
  });

  group('ScheduleChain.scheduleOn —— 时段优先、当前方案兜底', () {
    test('没有任何时段 → 一律走 fallback（**老库行为一字不变**）', () {
      final chain = ScheduleChain(fallback: _sched('当前'));
      expect(chain.scheduleOn(_d(2020, 5, 5))!.name, '当前');
      expect(chain.scheduleOn(_d(2030, 5, 5))!.name, '当前');
    });

    test('一段覆盖 → 覆盖的那些天归它，其余归 fallback', () {
      final chain = ScheduleChain(
        spans: [_span('A', from: _d(2026, 1, 1), to: _d(2026, 6, 30))],
        fallback: _sched('当前'),
      );
      expect(chain.scheduleOn(_d(2026, 3, 15))!.name, 'A');
      expect(chain.scheduleOn(_d(2026, 6, 30))!.name, 'A'); // 闭区间
      expect(chain.scheduleOn(_d(2026, 7, 1))!.name, '当前'); // 差一天
    });

    test('两段不重叠 → 各归各的', () {
      final chain = ScheduleChain(spans: [
        _span('A', id: 1, from: _d(2026, 1, 1), to: _d(2026, 6, 30)),
        _span('B', id: 2, from: _d(2026, 7, 1)),
      ]);
      expect(chain.scheduleOn(_d(2026, 6, 30))!.name, 'A');
      expect(chain.scheduleOn(_d(2026, 7, 1))!.name, 'B');
    });

    test('两段重叠 → **起点晚的赢**（与列表顺序无关）', () {
      // 故意把晚起的那段放在**前面**，证明结论不靠装配顺序。
      final early = _span('早', id: 1, from: _d(2026, 1, 1));
      final late = _span('晚', id: 2, from: _d(2026, 7, 1));
      final a = ScheduleChain(spans: [late, early]);
      final b = ScheduleChain(spans: [early, late]);
      expect(a.scheduleOn(_d(2026, 9, 1))!.name, '晚');
      expect(b.scheduleOn(_d(2026, 9, 1))!.name, '晚');
      // 7/1 之前只有早的那段覆盖
      expect(a.scheduleOn(_d(2026, 3, 1))!.name, '早');
    });

    test('起点并列 → id 大的（后建的那套）赢', () {
      final chain = ScheduleChain(spans: [
        _span('先建', id: 3, from: _d(2026, 1, 1)),
        _span('后建', id: 9, from: _d(2026, 1, 1)),
      ]);
      expect(chain.scheduleOn(_d(2026, 5, 1))!.name, '后建');
    });

    test('起点为空的那段算「一直往前」，输给任何有起点的', () {
      final chain = ScheduleChain(spans: [
        _span('不限起点', id: 1, to: _d(2026, 12, 31)),
        _span('七月起', id: 2, from: _d(2026, 7, 1)),
      ]);
      expect(chain.scheduleOn(_d(2026, 3, 1))!.name, '不限起点');
      expect(chain.scheduleOn(_d(2026, 9, 1))!.name, '七月起');
    });

    test('没有一套覆盖、fallback 也是 null → null', () {
      final chain = ScheduleChain(spans: [_span('A', from: _d(2026, 1, 1))]);
      expect(chain.scheduleOn(_d(2025, 1, 1)), isNull);
    });

    test('scheduleIdOn：报出**那天归哪一套的行 id**（写按天覆盖要用）', () {
      final chain = ScheduleChain(
        spans: [
          _span('A', id: 11, from: _d(2026, 1, 1), to: _d(2026, 6, 30)),
          _span('B', id: 22, from: _d(2026, 7, 1)),
        ],
        fallback: _sched('当前'),
        fallbackId: 99,
      );
      expect(chain.scheduleIdOn(_d(2026, 3, 1)), 11);
      expect(chain.scheduleIdOn(_d(2026, 8, 1)), 22);
      // 时段之外 → 兜底那套的 id（老库恒走这一支，与从前一致）
      expect(chain.scheduleIdOn(_d(2025, 1, 1)), 99);
      // 完全没有方案 → null
      expect(const ScheduleChain().scheduleIdOn(_d(2026, 1, 1)), isNull);
    });
  });

  group('ScheduleChain.shiftOn —— 真的问到那一套的班', () {
    test('边界两侧各返回**各自方案**的班次', () {
      final chain = ScheduleChain(spans: [
        _span('A', id: 1, from: _d(2026, 1, 1), to: _d(2026, 6, 30)),
        _span('B', id: 2, from: _d(2026, 7, 1)),
      ]);
      // 周期 2 天：anchor 起第 0 天=白、第 1 天=休。挑两天让两套的班级不同。
      final before = chain.shiftOn(_d(2026, 6, 30));
      final after = chain.shiftOn(_d(2026, 7, 1));
      expect(before!.name, startsWith('A-'));
      expect(after!.name, startsWith('B-'));
    });

    test('hasCycle：空白表不算，只要有**一套**有周期就为真', () {
      final blank = ScheduleChain(
        fallback: ShiftSchedule(
          name: '空白',
          anchorDate: DateTime.utc(2026, 1, 1),
          classes: const [ShiftClass(name: '休息', isRest: true)],
          cycle: const [],
        ),
      );
      expect(blank.hasCycle, isFalse);
      expect(ScheduleChain(fallback: _sched('A')).hasCycle, isTrue);
      // 当前是空表，但链上有一张有周期的
      expect(
        ScheduleChain(spans: [_span('A', from: _d(2026, 1, 1))], fallback: null)
            .hasCycle,
        isTrue,
      );
    });
  });

  group('monthHasOverrideHint —— 逐天问「那天归哪套」', () {
    ShiftSchedule withOverride(String name,
        {required int month, required int day, required int idx}) {
      final base = _sched(name);
      return ShiftSchedule(
        name: base.name,
        anchorDate: base.anchorDate,
        classes: base.classes,
        cycle: base.cycle,
        dayOverrides: {dayNumber(_d(2026, month, day)): idx},
      );
    }

    const month = 9;

    test('覆盖记在归 A 的那天、而这个月归 B → false', () {
      final chain = ScheduleChain(spans: [
        ScheduleSpan(
            id: 1,
            schedule: withOverride('A', month: 8, day: 1, idx: 0),
            from: _d(2026, 8, 1),
            to: _d(2026, 8, 31)),
        // B 管九月，而它自己在这个月**一条覆盖都没有**
        ScheduleSpan(id: 2, schedule: _sched('B'), from: _d(2026, 9, 1)),
      ]);
      expect(chain.monthHasOverrideHint(DateTime.utc(2026, month, 1)), isFalse,
          reason: 'A 那条覆盖在八月；不能因为「链上有一套方案有覆盖」就为真');
    });

    test('覆盖就在这个月里 → true', () {
      final chain = ScheduleChain(spans: [
        ScheduleSpan(
            id: 2,
            schedule: withOverride('B', month: 9, day: 15, idx: 1),
            from: _d(2026, 9, 1)),
      ]);
      expect(chain.monthHasOverrideHint(DateTime.utc(2026, month, 1)), isTrue);
    });

    test('跨方案的月：覆盖记在**归 A 的那几天**上 → true', () {
      // 这才是「逐天问」的意义所在：换了从前那套「只看一套的 dayOverrides」，
      // 这条会漏 —— A 管上半月、B 管下半月，而覆盖在 A 那半边上。
      final chain = ScheduleChain(spans: [
        ScheduleSpan(
            id: 1,
            schedule: withOverride('A', month: 9, day: 10, idx: 1),
            from: _d(2026, 9, 1),
            to: _d(2026, 9, 14)),
        ScheduleSpan(id: 2, schedule: _sched('B'), from: _d(2026, 9, 15)),
      ]);
      expect(chain.monthHasOverrideHint(DateTime.utc(2026, month, 1)), isTrue);
    });

    test('覆盖在**别的月**、同一套方案 → false（按月判定）', () {
      final chain = ScheduleChain(spans: [
        ScheduleSpan(
            id: 2,
            schedule: withOverride('B', month: 10, day: 3, idx: 1),
            from: _d(2026, 10, 1)),
      ]);
      expect(chain.monthHasOverrideHint(DateTime.utc(2026, month, 1)), isFalse);
    });
  });

  group('overlappingSpans —— 只服务于那句提醒', () {
    test('首尾相接**不算**重叠', () {
      final a = _span('A', id: 1, from: _d(2026, 1, 1), to: _d(2026, 6, 30));
      final b = _span('B', id: 2, from: _d(2026, 7, 1));
      expect(overlappingSpans([a, b], a), isEmpty);
      expect(overlappingSpans([a, b], b), isEmpty);
    });

    test('真重叠 → 报出对方', () {
      final a = _span('A', id: 1, from: _d(2026, 1, 1), to: _d(2026, 8, 31));
      final b = _span('B', id: 2, from: _d(2026, 7, 1));
      expect(overlappingSpans([a, b], a).map((s) => s.schedule.name), ['B']);
      expect(overlappingSpans([a, b], b).map((s) => s.schedule.name), ['A']);
    });

    test('两端都空（不参与衔接）的既不算重叠、也不被报出', () {
      final none = _span('未参与', id: 1);
      final a = _span('A', id: 2, from: _d(2026, 1, 1));
      expect(overlappingSpans([none, a], a), isEmpty);
      expect(overlappingSpans([none, a], none), isEmpty);
    });
  });
}
