// app/test/shift_alarm_decision_test.dart
//
// 班次联动闹钟的「排定决策」—— 纯函数 `planShiftAlarms`。
//
// 为什么要把它抽出来单独测：这段逻辑从前长在 `AlarmService.reschedule` 的
// 排定循环里，和 `scheduleNativeAlarm` / `DateTime.now()` 缠在一起。本机没有
// 可运行的原生插件目标（无 Android 设备 / 无 VS 工具链），于是 spec §11 点名
// 要的三条闹钟用例 ——
//   · 覆盖成休班那天不排闹钟
//   · 覆盖成另一个工作班次，按**那个班次自己的** alarmMinute 排
//   · 与「按天关闹钟」（ShiftAlarmOverrides）正交，关着的仍关着
// —— 一条都没有过。抽成不碰插件、不读挂钟的纯函数之后才测得到。
//
// 顺带钉住 `offset`：原生 id 是 `_shiftBaseId + offset`（offset = 距起点日的
// 天数），跳过某天时**不能**重新编号 —— 否则闹钟会集体换个号。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';

/// 起点日：轮转上是「白班」那天。
final _day = DateTime(2026, 9, 20);

/// 两天一循环的小方案：偶数日「白班」（闹钟 07:00）、奇数日「休班」。
///
/// 班次名写死，用例断言的是**结构**而不是文案，所以不经过 `L10n`。
ShiftSchedule _schedule({Map<int, int> overrides = const {}}) => ShiftSchedule(
      name: '测试',
      anchorDate: DateTime.utc(2026, 9, 20),
      classes: const [
        ShiftClass(
            id: 11,
            name: '白班',
            abbr: '白',
            startMinute: 8 * 60,
            endMinute: 20 * 60,
            alarmEnabled: true,
            alarmMinute: 7 * 60),
        ShiftClass(
            id: 12,
            name: '夜班',
            abbr: '夜',
            startMinute: 20 * 60,
            endMinute: 8 * 60,
            alarmEnabled: true,
            alarmMinute: 19 * 60 + 30),
        ShiftClass(id: 13, name: '休班', abbr: '休', isRest: true),
      ],
      cycle: const [0, 2],
      teamCount: 1,
      teamNames: const ['我'],
      teamOffsets: const [0],
      dayOverrides: overrides,
    );

void main() {
  test('基线：工作班那天排一条、休班那天不排', () {
    final plans =
        planShiftAlarms(_schedule(), from: DateTime(2026, 9, 20, 6), days: 2);
    expect(plans, hasLength(1));
    expect(plans.single.shift.name, '白班');
    expect(plans.single.fireAt, DateTime(2026, 9, 20, 7));
    expect(plans.single.offset, 0);
  });

  test('跳过的天照样占号：offset 不能重新编号（原生 id 靠它）', () {
    // 第 1 天改成休班（跳过）、第 2 天改成白班（要排）。排出来的那条 offset
    // 必须是 1 而不是 0 —— 重新编号会让它的原生 id 跟第 1 天撞上。
    final plans = planShiftAlarms(
        _schedule(overrides: {
          dayNumber(_day): 2,
          dayNumber(_day.add(const Duration(days: 1))): 0,
        }),
        from: DateTime(2026, 9, 20, 6),
        days: 2);
    expect(plans, hasLength(1));
    expect(plans.single.offset, 1,
        reason: 'offset 是距起点日的天数，不是「第几条排上的闹钟」');
  });

  test('覆盖成休班：那天不排闹钟', () {
    final plans = planShiftAlarms(_schedule(overrides: {dayNumber(_day): 2}),
        from: DateTime(2026, 9, 20, 6), days: 1);
    expect(plans, isEmpty, reason: '改成休班的那天不该响（spec §11）');
  });

  test('覆盖成另一个工作班次：按那个班次自己的 alarmMinute 排', () {
    // 那天轮转本来是「白班」（07:00）；覆盖成「夜班」（19:30）之后闹钟必须
    // 跟着挪到 19:30 —— 仍按旧班次的时间排就等于没跟上覆盖。
    final plans = planShiftAlarms(_schedule(overrides: {dayNumber(_day): 1}),
        from: DateTime(2026, 9, 20, 6), days: 1);
    expect(plans, hasLength(1));
    expect(plans.single.shift.name, '夜班');
    expect(plans.single.fireAt, DateTime(2026, 9, 20, 19, 30),
        reason: '要按覆盖后那个班次自己的 alarmMinute 排（spec §11）');
  });

  test('与「按天关闹钟」正交：改过班之后那天仍然关着', () {
    final changed = {dayNumber(_day): 1}; // 那天改成夜班
    final muted = {dayNumber(_day): false}; // 同一个方案上「按天关闹钟」

    expect(
        planShiftAlarms(_schedule(overrides: changed),
            from: DateTime(2026, 9, 20, 6), days: 1, overrides: muted),
        isEmpty,
        reason: '关过闹钟的那天，改完班之后仍然关着（spec §11）');

    // 对照组：不关的话同一天要排上 —— 否则上面那条断言可能是假通过。
    expect(
        planShiftAlarms(_schedule(overrides: changed),
            from: DateTime(2026, 9, 20, 6), days: 1),
        hasLength(1));
  });

  test('闹钟时刻已经过去：跳过', () {
    // 白班闹钟 07:00，起点时刻已经是 08:00。
    expect(
        planShiftAlarms(_schedule(), from: DateTime(2026, 9, 20, 8), days: 1),
        isEmpty,
        reason: '已经过去的时刻不必再排（排了也不会响）');

    // 对照组：06:00 时 07:00 还没到，要排。
    expect(
        planShiftAlarms(_schedule(), from: DateTime(2026, 9, 20, 6), days: 1),
        hasLength(1));
  });

  test('空白表（跟随法定节假日）：不排任何闹钟', () {
    final blank = ShiftSchedule(
      name: '跟随法定节假日',
      anchorDate: DateTime.utc(2025, 1, 6),
      classes: const [],
      cycle: const [],
    );
    expect(
        planShiftAlarms(blank, from: DateTime(2026, 9, 20, 6), days: 30),
        isEmpty);
  });
}
