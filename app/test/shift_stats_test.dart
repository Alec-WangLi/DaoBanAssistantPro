// app/test/shift_stats_test.dart
//
// 统计口径的纯函数。这里每一条都对应一个「算错了不会报错、只会显示一个错数字」
// 的边界：`endMinute` 的三种真实形态、跨月夜班归哪个月、整天 / 部分请假、
// 空白表与未排班、缺时间、节假日、夜班、连续天数。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/day_extra.dart';
import 'package:shiftassistantpro/domain/schedule_chain.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_stats.dart';

ShiftClass _work(String name,
        {int start = 480,
        int end = 1200,
        String? abbr,
        bool night = false}) =>
    ShiftClass(
        name: name,
        abbr: abbr,
        startMinute: start,
        endMinute: end,
        isNight: night);

ShiftClass _rest(String name, {String? abbr}) =>
    ShiftClass(name: name, abbr: abbr, isRest: true);

ShiftSchedule _sched(List<ShiftClass> classes, List<int> cycle,
        {DateTime? anchor}) =>
    ShiftSchedule(
      name: 't',
      anchorDate: anchor ?? DateTime.utc(2026, 11, 1),
      classes: classes,
      cycle: cycle,
      teamCount: 1,
      teamNames: const ['一班'],
      ourTeamIndex: 0,
      teamOffsets: const [0],
    );

ScheduleChain _chain(ShiftSchedule s) => ScheduleChain(fallback: s);

ShiftStats _stats(ScheduleChain? chain,
        {required DateTime from,
        required DateTime to,
        Map<int, DayExtra> extras = const {},
        bool Function(DateTime)? isHoliday}) =>
    shiftStatsFor(
      chain: chain,
      from: from,
      to: to,
      extras: extras,
      isHoliday: isHoliday ?? (_) => false,
    );

DateTime _d(int y, int m, int day) => DateTime.utc(y, m, day);

void main() {
  test('endMinute 三种真实形态都能算对', () {
    expect(shiftDurationMinutes(_work('24h', start: 480, end: 1920)), 1440);
    expect(shiftDurationMinutes(_work('夜', start: 1230, end: 510)), 720);
    expect(shiftDurationMinutes(_work('到24点', start: 480, end: 1440)), 960);
    expect(shiftDurationMinutes(_rest('休')), isNull);
    expect(shiftDurationMinutes(const ShiftClass(name: '没设时间')), isNull);
  });

  test('整月：上班 / 休息天数、工时、平均、夜班、班次分布', () {
    final s = _sched([
      _work('白班', abbr: '白'),
      _work('上夜班', abbr: '夜', start: 1200, end: 480, night: true),
      _rest('下夜班', abbr: '下'),
      _rest('大休', abbr: '休'),
    ], const [0, 1, 2, 3]);

    final r = _stats(_chain(s), from: _d(2026, 11, 1), to: _d(2026, 11, 30));

    expect(r.workDays, 16);
    expect(r.restDays, 14);
    expect(r.normalMinutes, 16 * 720);
    expect(r.averageMinutesPerWorkDay, 720);
    expect(r.nightShiftDays, 8);
    expect(r.classDayCounts, {'白': 8, '夜': 8, '下': 7, '休': 7});
  });

  test('跨月夜班整段算在上班那天', () {
    // 12/31 是夜班（20:30–次日 08:30），1/1 是休息。
    final s = _sched([
      _work('夜', start: 1230, end: 510, night: true),
      _rest('休'),
    ], const [0, 1], anchor: _d(2026, 12, 31));
    final chain = _chain(s);

    final dec31 = _stats(chain, from: _d(2026, 12, 31), to: _d(2026, 12, 31));
    final jan1 = _stats(chain, from: _d(2027, 1, 1), to: _d(2027, 1, 1));

    expect(dec31.normalMinutes, 720);
    expect(dec31.workDays, 1);
    expect(jan1.normalMinutes, 0);
    expect(jan1.workDays, 0);
    expect(jan1.restDays, 1);
  });

  test('整天请假不计出勤，也不重复扣工时', () {
    final s = _sched([_work('白'), _rest('休')], const [0, 1]);
    final r = _stats(
      _chain(s),
      from: _d(2026, 11, 1),
      to: _d(2026, 11, 1),
      extras: {
        dayNumber(_d(2026, 11, 1)): const DayExtra(leaveMinutes: 720),
      },
    );

    expect(r.workDays, 0);
    expect(r.normalMinutes, 0);
    expect(r.leaveMinutes, 720);
    expect(r.fullLeaveDays, 1);
  });

  test('部分请假仍算出勤，工时按差额算', () {
    final s = _sched([_work('白'), _rest('休')], const [0, 1]);
    final r = _stats(
      _chain(s),
      from: _d(2026, 11, 1),
      to: _d(2026, 11, 1),
      extras: {
        dayNumber(_d(2026, 11, 1)): const DayExtra(leaveMinutes: 240),
      },
    );

    expect(r.workDays, 1);
    expect(r.normalMinutes, 480);
    expect(r.leaveMinutes, 240);
    expect(r.fullLeaveDays, 0);
  });

  test('休息日加班只加加班时长，不改出勤 / 休息天数', () {
    final s = _sched([_work('白'), _rest('休')], const [0, 1]);
    final r = _stats(
      _chain(s),
      from: _d(2026, 11, 2),
      to: _d(2026, 11, 2),
      extras: {
        dayNumber(_d(2026, 11, 2)): const DayExtra(overtimeMinutes: 240),
      },
    );

    expect(r.workDays, 0);
    expect(r.restDays, 1);
    expect(r.overtimeMinutes, 240);
    expect(r.totalMinutes, 240);
  });

  test('空白表算「无班次」，不算休息也不算未排班', () {
    final blank = ShiftSchedule(
      name: '法定节假日',
      anchorDate: _d(2026, 1, 1),
      classes: const [],
      cycle: const [],
    );
    final r = _stats(_chain(blank),
        from: _d(2026, 11, 1), to: _d(2026, 11, 3));

    expect(r.blankDays, 3);
    expect(r.unscheduledDays, 0);
    expect(r.restDays, 0);
  });

  test('没有任何班表才算「未排班」', () {
    final r = _stats(null, from: _d(2026, 11, 1), to: _d(2026, 11, 3));
    expect(r.unscheduledDays, 3);
    expect(r.blankDays, 0);
    expect(r.restDays, 0);
  });

  test('没设时间的班次算出勤，但工时记 0 并单独计数', () {
    final s = _sched([const ShiftClass(name: '白')], const [0]);
    final r = _stats(_chain(s),
        from: _d(2026, 11, 1), to: _d(2026, 11, 1));

    expect(r.workDays, 1);
    expect(r.missingTimeDays, 1);
    expect(r.normalMinutes, 0);
  });

  test('节假日上班与夜班只数出勤日', () {
    final s = _sched([
      _work('夜', start: 1200, end: 480, night: true),
      _work('白'),
    ], const [0, 1]);
    final r = _stats(
      _chain(s),
      from: _d(2026, 11, 1),
      to: _d(2026, 11, 2),
      isHoliday: (d) => d.day == 1,
    );

    expect(r.workDays, 2);
    expect(r.nightShiftDays, 1);
    expect(r.holidayWorkDays, 1);
  });

  test('最长连班 / 最长连休在未排班处断开', () {
    // 11/1–11/3：上班、上班、休息；11/4 未排班；11/5 上班；11/6–11/7 未排班。
    final a = ShiftSchedule(
      name: 'A',
      anchorDate: _d(2026, 11, 1),
      classes: [_work('白'), _rest('休')],
      cycle: const [0, 0, 1],
      teamCount: 1,
      teamNames: const ['一班'],
      teamOffsets: const [0],
    );
    final b = ShiftSchedule(
      name: 'B',
      anchorDate: _d(2026, 11, 5),
      classes: [_work('白')],
      cycle: const [0],
      teamCount: 1,
      teamNames: const ['一班'],
      teamOffsets: const [0],
    );
    final chain = ScheduleChain(spans: [
      ScheduleSpan(
          id: 1, scheduleId: 1, schedule: a, from: _d(2026, 11, 1), to: _d(2026, 11, 3)),
      ScheduleSpan(
          id: 2, scheduleId: 2, schedule: b, from: _d(2026, 11, 5), to: _d(2026, 11, 5)),
    ]);

    final r = _stats(chain, from: _d(2026, 11, 1), to: _d(2026, 11, 7));

    expect(r.unscheduledDays, 3);
    expect(r.longestWorkStreak, 2);
    expect(r.longestRestStreak, 1);
  });

  test('零出勤时平均工时返回 0，不抛异常', () {
    final r = _stats(null, from: _d(2026, 11, 1), to: _d(2026, 11, 1));
    expect(r.workDays, 0);
    expect(r.averageMinutesPerWorkDay, 0);
  });

  test('请假按类型汇总；没类型的旧记录归「未分类」', () {
    final s = _sched([_work('白班', abbr: '白')], const [0]);
    final extras = {
      dayNumber(_d(2026, 11, 2)):
          const DayExtra(leaveMinutes: 240, leaveKind: 'annual'),
      dayNumber(_d(2026, 11, 3)):
          const DayExtra(leaveMinutes: 120, leaveKind: 'personal'),
      dayNumber(_d(2026, 11, 4)): const DayExtra(leaveMinutes: 60),
    };

    final r = _stats(_chain(s),
        from: _d(2026, 11, 1), to: _d(2026, 11, 5), extras: extras);

    expect(r.leaveMinutes, 420);
    expect(r.leaveMinutesByKind['annual'], 240);
    expect(r.leaveMinutesByKind['personal'], 120);
    expect(r.leaveMinutesByKind[kUnspecifiedLeaveKind], 60);
    expect(r.leaveMinutesByKind.length, 3);
  });
}
