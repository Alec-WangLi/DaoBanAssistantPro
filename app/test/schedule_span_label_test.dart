// app/test/schedule_span_label_test.dart
//
// 「排班时段」相关的两句纯文案。
//
// 身份标签那**三种**说法不能混（其余时间 / 已排入时段 / 未使用）—— 混了用户就看
// 不懂「这套方案到底在不在时间线上」；日期说法那**四种**形态各有各的读法，其中
// 「两端都空」是段表独立之后才可能出现的（一套方案一直用）。
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/schedule_span_label.dart';

ShiftScheduleRow _row({bool isCurrent = false}) => ShiftScheduleRow(
      id: 1,
      name: 'A',
      anchorDate: DateTime.utc(2026, 1, 1),
      isCurrent: isCurrent,
      teamCount: 4,
      teamNames: '一班,二班,三班,四班',
      ourTeamIndex: 0,
      teamOffsets: '0,1,2,3',
    );

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

void main() {
  setUp(() async {
    L10n.locale = 'zh';
    await initializeDateFormatting('zh');
  });

  group('scheduleRoleLabel —— 四种身份', () {
    test('一个段都没有 → 「正在使用」（说「其余时间」会被读成「默认？」）', () {
      // 2026-09-30 用户反馈：「它说『其余时间 五班三倒』，那其实是默认一直都是
      // 五班三倒吗？」—— 没有「这一段」，「其余」就没有着落。
      expect(
          scheduleRoleLabel(_row(isCurrent: true),
              spanCount: 0, isCurrent: true, hasPeriods: false),
          L10n.inUseNow);
    });

    test('是「其余时间」→ 其余时间（**哪怕它也在时间线上**）', () {
      expect(scheduleRoleLabel(_row(isCurrent: true), spanCount: 0, isCurrent: true),
          L10n.remainingTime);
      expect(scheduleRoleLabel(_row(isCurrent: true), spanCount: 3, isCurrent: true),
          L10n.remainingTime,
          reason: '既是其余时间又在段里 —— 说「其余时间」就够，段由上面那条时间线列');
    });

    test('被时段引用（不是其余时间）→ 已排入时段', () {
      expect(scheduleRoleLabel(_row(), spanCount: 2, isCurrent: false),
          L10n.onTimeline);
    });

    test('既不是其余时间、也没被引用 → 未使用', () {
      expect(scheduleRoleLabel(_row(), spanCount: 0, isCurrent: false),
          L10n.unusedSchedule);
    });
  });

  group('spanRangeLabel —— 四种形态', () {
    test('两端都有 → 「起 ～ 止」', () {
      expect(
        spanRangeLabel(_d(2026, 1, 1), _d(2026, 6, 30)),
        L10n.effectiveRangeSpan(
            L10n.monthDay(_d(2026, 1, 1)), L10n.monthDay(_d(2026, 6, 30))),
      );
    });

    test('只设起点 → 「X 起」（= 一直持续）', () {
      expect(spanRangeLabel(_d(2026, 7, 1), null),
          L10n.effectiveFromDate(L10n.monthDay(_d(2026, 7, 1))));
    });

    test('只设终点 → 「到 X」（= 不限起点）', () {
      expect(spanRangeLabel(null, _d(2026, 6, 30)),
          L10n.effectiveUntilDate(L10n.monthDay(_d(2026, 6, 30))));
    });

    test('两端都空 → 「一直」（段表独立之后才可能的形态）', () {
      expect(spanRangeLabel(null, null), L10n.spanAlways);
    });
  });

  test('spanCountOf：按**方案** id 数，不是按段 id', () {
    final spans = [
      const ScheduleSpanRow(
          id: 11, scheduleId: 3, startDate: null, endDate: null),
      const ScheduleSpanRow(
          id: 12, scheduleId: 3, startDate: null, endDate: null),
      const ScheduleSpanRow(
          id: 13, scheduleId: 11, startDate: null, endDate: null),
    ];
    expect(spanCountOf(spans, 3), 2);
    expect(spanCountOf(spans, 11), 1, reason: '段 id 11 不该被算进去');
    expect(spanCountOf(spans, 5), 0);
  });
}
