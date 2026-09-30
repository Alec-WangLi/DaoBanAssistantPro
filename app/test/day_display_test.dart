// app/test/day_display_test.dart
//
// 「这一天在界面上画成什么」—— 空白表（跟随法定节假日）那一档。
//
// 这条链当初断在**判据**上：`shiftOn` 对空白表恒为 null，于是日历整月盖着
// 「这段时间没有排班」、桌面小组件写「还没有排班」，而用户明明排了班
// （2026-09-30 真机反馈）。这里把「空白表 = 每天都画得出东西」钉死。
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/day_display.dart';
import 'package:shiftassistantpro/domain/schedule_chain.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

ShiftSchedule _blank({String name = '法定班次'}) => ShiftSchedule(
      name: name,
      anchorDate: DateTime.utc(2026, 1, 1),
      classes: const [],
      cycle: const [],
    );

ShiftSchedule _rotating() => ShiftSchedule(
      name: '四班两倒',
      anchorDate: DateTime.utc(2026, 1, 1),
      classes: const [
        ShiftClass(name: '白班', abbr: '白', color: 0xFF4C8DFF),
        ShiftClass(name: '休班', abbr: '休', color: 0xFF9AA0B4, isRest: true),
      ],
      cycle: const [0, 1],
    );

void main() {
  setUpAll(() async => initializeDateFormatting('zh'));
  setUp(() => L10n.locale = 'zh');

  test('空白表：法定节假日写「休息」，其余日子写「上班」', () {
    // 2026 国庆 10/1~10/7（`lunar_info.dart` 的内置放假表）。
    final holiday = blankDayChip(DateTime(2026, 10, 1));
    expect(holiday.name, L10n.rest);
    expect(holiday.shortLabel, L10n.restShort);
    expect(holiday.isRest, isTrue, reason: '休这一天是「休息」，不是「上班」');

    final workday = blankDayChip(DateTime(2026, 9, 18));
    expect(workday.name, L10n.workday);
    expect(workday.shortLabel, L10n.workdayShort);
    expect(workday.isRest, isFalse);
  });

  test('空白表：调休上班日照样写「上班」', () {
    // 2026-09-20 是调休上班日（中秋假里被调成上班的那个周末）。
    expect(blankDayChip(DateTime(2026, 9, 20)).isRest, isFalse);
  });

  test('空白表那两天没有时间、没有闹钟、也不带库里的 id', () {
    // 合成出来的**不是库里的班次**：它只回答「画什么」。
    // 有了时间或闹钟，闹钟链就会把它当真班次排一遍。
    final c = blankDayChip(DateTime(2026, 9, 18));
    expect(c.id, isNull);
    expect(c.startMinute, isNull);
    expect(c.endMinute, isNull);
    expect(c.alarms, isEmpty);
    expect(c.endsNextDay, isFalse);
  });

  test('有周期的方案：原样返回那天的班次（同一个实例）', () {
    final s = _rotating();
    final chain = ScheduleChain(fallback: s, fallbackId: 1);
    final day = DateTime(2026, 9, 18);
    expect(identical(displayShiftOn(chain, day), s.shiftOn(day)), isTrue);
  });

  test('其余时间为「无」且没有段 → null（这才是真的「没有排班」）', () {
    expect(displayShiftOn(null, DateTime(2026, 9, 18)), isNull);
    expect(
        displayShiftOn(
            const ScheduleChain(spans: [], fallback: null), DateTime(2026, 9, 18)),
        isNull);
  });

  test('一条链上：段内是空白表、段外是普通方案 → 逐天各归各的', () {
    // 9/15 起换成法定班次，9 月剩下的日子归它；之前归「其余时间」那套。
    final blank = _blank();
    final chain = ScheduleChain(
      spans: [
        ScheduleSpan(
            id: 1,
            scheduleId: 2,
            schedule: blank,
            from: DateTime.utc(2026, 9, 15)),
      ],
      fallback: _rotating(),
      fallbackId: 1,
    );

    expect(displayShiftOn(chain, DateTime(2026, 9, 14))!.name,
        _rotating().shiftOn(DateTime(2026, 9, 14))!.name,
        reason: '14 日仍归「其余时间」那套（照它的轮转走）');
    expect(displayShiftOn(chain, DateTime(2026, 9, 18))!.name, L10n.workday,
        reason: '18 日归段内的法定班次');
    expect(displayShiftOn(chain, DateTime(2026, 10, 1))!.name, L10n.rest,
        reason: '10/1 归段内那套，且是法定节假日');
  });

  test('hasAnySchedule：空白表也算「排过班」，hasCycle 仍不算', () {
    // 两个 getter 的分工见 `schedule_chain.dart` —— 桌面小组件的空态用前者。
    final onlyBlank = ScheduleChain(fallback: _blank());
    expect(onlyBlank.hasAnySchedule, isTrue);
    expect(onlyBlank.hasCycle, isFalse);

    const empty = ScheduleChain();
    expect(empty.hasAnySchedule, isFalse);
    expect(empty.hasCycle, isFalse);
  });
}
