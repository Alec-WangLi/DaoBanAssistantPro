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

/// 段 id 与**方案** id 默认取同一个值（多数用例不关心两者之别）；
/// 需要分辨它们的地方显式传 `scheduleId`。
ScheduleSpan _span(String name,
        {int id = 1, int? scheduleId, DateTime? from, DateTime? to}) =>
    ScheduleSpan(
        id: id,
        scheduleId: scheduleId ?? id,
        schedule: _sched(name),
        from: from,
        to: to);

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

  group('ScheduleChain.scheduleOn —— 段不重叠 → 唯一解；其余时间兜底', () {
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

    test('重叠**不该出现**（界面禁止）—— 真出现时也必须确定，不随列表顺序变', () {
      // 段之间不重叠是界面保证的（保存前用 `conflictingSpans` 拦）+ 迁移规整过的。
      // 这条守的是万一库里真有脏数据时的**确定性**：结果仍按「起点晚的赢」，而不是
      // 取列表里第一个 —— 后者会让同一条数据换一次装配顺序就换个答案。
      // **别把这条读成「重叠是允许的」**：用户可见的语义已经是唯一解了。
      final early = _span('早', id: 1, from: _d(2026, 1, 1));
      final late = _span('晚', id: 2, from: _d(2026, 7, 1));
      expect(ScheduleChain(spans: [late, early]).scheduleOn(_d(2026, 9, 1))!.name,
          '晚');
      expect(ScheduleChain(spans: [early, late]).scheduleOn(_d(2026, 9, 1))!.name,
          '晚');
    });

    test('其余时间为 null（设成「无」）→ 没段覆盖的日子返回 null', () {
      final chain = ScheduleChain(
        spans: [_span('A', id: 1, from: _d(2026, 9, 1), to: _d(2026, 9, 30))],
        fallback: null,
      );
      expect(chain.scheduleOn(_d(2026, 9, 15))!.name, 'A');
      expect(chain.scheduleOn(_d(2026, 9, 30))!.name, 'A'); // 闭区间
      expect(chain.scheduleOn(_d(2026, 10, 1)), isNull);
      expect(chain.scheduleOn(_d(2026, 8, 31)), isNull);
      expect(chain.shiftOn(_d(2026, 10, 1)), isNull);
    });

    test('其余时间为 null 且没有任何段 → 哪天都是 null，且 hasCycle 为假', () {
      const chain = ScheduleChain();
      expect(chain.scheduleOn(_d(2026, 9, 1)), isNull);
      expect(chain.hasCycle, isFalse, reason: '桌面小组件据此画空态');
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

    test('scheduleIdOn：报出**那天归哪一套方案的行 id**（写按天覆盖要用）', () {
      // **段 id 与方案 id 故意取不同的值** —— 段独立成表之后两者是两回事，混了
      // 的症状是「按天改班记到错的方案名下」（不生效、也不报错）。这样这条才
      // 真的能分辨它返回的是哪一个。
      final chain = ScheduleChain(
        spans: [
          _span('A',
              id: 111, scheduleId: 11, from: _d(2026, 1, 1), to: _d(2026, 6, 30)),
          _span('B', id: 222, scheduleId: 22, from: _d(2026, 7, 1)),
        ],
        fallback: _sched('当前'),
        fallbackId: 99,
      );
      expect(chain.scheduleIdOn(_d(2026, 3, 1)), 11, reason: '不是段 id 111');
      expect(chain.scheduleIdOn(_d(2026, 8, 1)), 22, reason: '不是段 id 222');
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

  group('conflictingSpans —— 重叠**不许有**，界面靠它挡在保存前', () {
    test('首尾相接**不算**重叠（那是正常的衔接）', () {
      final a = _span('A', id: 1, from: _d(2026, 1, 1), to: _d(2026, 6, 30));
      final b = _span('B', id: 2, from: _d(2026, 7, 1));
      expect(conflictingSpans([a, b], a), isEmpty);
      expect(conflictingSpans([a, b], b), isEmpty);
    });

    test('真重叠 → 报出对方', () {
      final a = _span('A', id: 1, from: _d(2026, 1, 1), to: _d(2026, 8, 31));
      final b = _span('B', id: 2, from: _d(2026, 7, 1));
      expect(conflictingSpans([a, b], a).map((s) => s.schedule.name), ['B']);
      expect(conflictingSpans([a, b], b).map((s) => s.schedule.name), ['A']);
    });

    test('多段都撞上时**全部**报出，且按**起点**升序（不是按 id）', () {
      final self = _span('我', id: 9, from: _d(2026, 1, 1), to: _d(2026, 12, 31));
      final all = [
        self,
        // 故意的：起得早的那个 id **更大** —— 这样「按起点」与「按 id」给出相反
        // 的顺序，这条才真的有鉴别力（否则两种排法都能过）。
        _span('早', id: 7, from: _d(2026, 2, 1), to: _d(2026, 3, 31)),
        _span('晚', id: 3, from: _d(2026, 9, 1), to: _d(2026, 10, 31)),
      ];
      expect(
          conflictingSpans(all, self).map((s) => s.schedule.name), ['早', '晚']);
    });

    test('两端都空（不在时间线上）的既不算冲突、也不被报出', () {
      final none = _span('未使用', id: 1);
      final a = _span('A', id: 2, from: _d(2026, 1, 1));
      expect(conflictingSpans([none, a], a), isEmpty);
      expect(conflictingSpans([none, a], none), isEmpty);
    });

    test('自己与自己不算冲突（同一个 id）', () {
      final a = _span('A', id: 1, from: _d(2026, 1, 1));
      expect(conflictingSpans([a], a), isEmpty);
    });
  });
}
