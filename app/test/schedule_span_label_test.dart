// app/test/schedule_span_label_test.dart
//
// 「这套方案管哪些日子」的一句话说法 —— 纯函数，五种形态各一条。
//
// 它错了不会报错，只会**让用户看不懂时间线**：尤其那两种「没设时段」的说法
// 不能混（当前那套是「其余日子」、别的方案是「未参与衔接」），混了就会让人
// 以为一套没设时段的方案也在时间线上占着位置。
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/schedule_span_label.dart';

ShiftScheduleRow _row({DateTime? from, DateTime? to, bool isCurrent = false}) =>
    ShiftScheduleRow(
      id: 1,
      name: 'A',
      anchorDate: DateTime.utc(2026, 1, 1),
      isCurrent: isCurrent,
      teamCount: 4,
      teamNames: '一班,二班,三班,四班',
      ourTeamIndex: 0,
      teamOffsets: '0,1,2,3',
      effectiveFrom: from,
      effectiveTo: to,
    );

void main() {
  setUp(() async {
    L10n.locale = 'zh';
    await initializeDateFormatting('zh');
  });

  test('两端都设 → 「起 ～ 止」', () {
    expect(
      effectiveRangeLabel(
          _row(from: DateTime.utc(2026, 1, 1), to: DateTime.utc(2026, 6, 30)),
          isCurrent: false),
      L10n.effectiveRangeSpan(
          L10n.monthDay(DateTime(2026, 1, 1)), L10n.monthDay(DateTime(2026, 6, 30))),
    );
  });

  test('只设起点 → 「X 起」（= 一直持续）', () {
    expect(
      effectiveRangeLabel(_row(from: DateTime.utc(2026, 7, 1)), isCurrent: false),
      L10n.effectiveFromDate(L10n.monthDay(DateTime(2026, 7, 1))),
    );
  });

  test('只设终点 → 「到 X」（= 不限起点）', () {
    expect(
      effectiveRangeLabel(_row(to: DateTime.utc(2026, 6, 30)), isCurrent: false),
      L10n.effectiveUntilDate(L10n.monthDay(DateTime(2026, 6, 30))),
    );
  });

  test('两端都空 + 是当前方案 → 「其余日子」', () {
    expect(effectiveRangeLabel(_row(), isCurrent: true), L10n.effectiveRemaining);
  });

  test('两端都空 + 不是当前方案 → 「未参与衔接」（**不能**说成其余日子）', () {
    expect(
        effectiveRangeLabel(_row(), isCurrent: false), L10n.effectiveNotChained);
  });
}
