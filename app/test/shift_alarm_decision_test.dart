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
// 顺带钉住 `offset` 与「序号」：原生 id 是 `序号 × 天数窗口 + 天数偏移`，跳过某天
// 时**不能**重新编号 —— 否则闹钟会集体换个号。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
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
            alarms: [ShiftAlarm(minute: 7 * 60)]),
        ShiftClass(
            id: 12,
            name: '夜班',
            abbr: '夜',
            startMinute: 20 * 60,
            endMinute: 8 * 60,
            alarmEnabled: true,
            alarms: [ShiftAlarm(minute: 19 * 60 + 30)]),
        ShiftClass(id: 13, name: '休班', abbr: '休', isRest: true),
      ],
      cycle: const [0, 2],
      teamCount: 1,
      teamNames: const ['我'],
      teamOffsets: const [0],
      dayOverrides: overrides,
    );

/// 只排一个「夜班」的方案（每天都上班）。
///
/// 默认就是用户报的那个配置（00:00 上班、23:00 响铃）—— 响铃钟点**晚于**上班
/// 钟点，意味着它指的是前一天晚上：排在班次当天 23:00 的话，响铃那一刻这个班
/// 已经结束 15 小时了。
ShiftSchedule _nightOnlySchedule(
        {int? startMinute = 0, int? alarmMinute = 23 * 60}) =>
    ShiftSchedule(
      name: '测试',
      anchorDate: DateTime.utc(2026, 9, 20),
      classes: [
        ShiftClass(
            id: 21,
            name: '夜班',
            abbr: '夜',
            startMinute: startMinute,
            endMinute: startMinute == null ? null : startMinute + 8 * 60,
            alarmEnabled: true,
            alarms: alarmMinute == null
                ? const []
                : [ShiftAlarm(minute: alarmMinute)]),
      ],
      cycle: const [0],
      teamCount: 1,
      teamNames: const ['我'],
      teamOffsets: const [0],
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

  // 响铃钟点晚于上班钟点时，那个钟点只可能是**前一天晚上**的 —— 见
  // `ShiftClass.alarmPreviousDay`。用户报的「夜班 24 点上班、响铃 23:00」
  // 就是这一档：排到当天的话，响铃时这个班已经结束 15 小时。
  group('响铃钟点晚于上班钟点：排在上班前一天', () {
    test('00:00 上班 + 23:00 响铃 → 前一天 23:00', () {
      // 起点日 9/19 12:00：9/19 那天的闹钟（9/18 23:00）已经过去，只剩 9/20 的。
      final plans = planShiftAlarms(_nightOnlySchedule(),
          from: DateTime(2026, 9, 19, 12), days: 2);
      expect(plans, hasLength(1));
      expect(plans.single.fireAt, DateTime(2026, 9, 19, 23),
          reason: '班次在 9/20 凌晨上班，闹钟要排在 9/19 晚上 23:00');
      expect(plans.single.offset, 1,
          reason: '排定时刻前移一天，但 offset / 原生 id 仍按班次那一天算');
    });

    test('早于上班钟点的响铃不受影响：仍是班次当天', () {
      // 20:30 上班、19:30 响铃（内置 12 小时制夜班那档）：钟点早于上班钟点，
      // 没有「前一天」的歧义，排的还是班次当天。
      final plans = planShiftAlarms(
          _nightOnlySchedule(
              startMinute: 20 * 60 + 30, alarmMinute: 19 * 60 + 30),
          from: DateTime(2026, 9, 20, 6),
          days: 1);
      expect(plans.single.fireAt, DateTime(2026, 9, 20, 19, 30));
    });

    test('钟点相同：算当天', () {
      final plans = planShiftAlarms(_nightOnlySchedule(alarmMinute: 0),
          from: DateTime(2026, 9, 19, 12), days: 2);
      expect(plans.single.fireAt, DateTime(2026, 9, 20),
          reason: '「不晚于上班时刻的最近一次该钟点」就是上班那一刻本身');
    });

    test('没填上班时间：无从判断，仍按当天（不瞎挪一天）', () {
      final plans = planShiftAlarms(_nightOnlySchedule(startMinute: null),
          from: DateTime(2026, 9, 20, 6), days: 1);
      expect(plans.single.fireAt, DateTime(2026, 9, 20, 23));
    });
  });

  group('一条班次挂多个闹钟（spec §6）', () {
    ShiftSchedule twoAlarms() => ShiftSchedule(
          name: '测试',
          anchorDate: DateTime.utc(2026, 9, 20),
          classes: const [
            ShiftClass(
              id: 31,
              name: '白班',
              abbr: '白',
              startMinute: 8 * 60,
              endMinute: 20 * 60,
              alarmEnabled: true,
              alarms: [
                ShiftAlarm(minute: 6 * 60 + 30, label: '起床'),
                ShiftAlarm(minute: 12 * 60 + 30, label: '午休'),
              ],
            ),
          ],
          cycle: const [0],
          teamCount: 1,
          teamNames: const ['我'],
          teamOffsets: const [0],
        );

    test('两个闹钟各一条 plan，序号 0/1，都落在班次当天', () {
      final plans = planShiftAlarms(twoAlarms(),
          from: DateTime(2026, 9, 20, 5), days: 1);
      expect(plans, hasLength(2));
      expect(plans[0].alarmIndex, 0);
      expect(plans[0].fireAt, DateTime(2026, 9, 20, 6, 30));
      expect(plans[1].alarmIndex, 1);
      expect(plans[1].fireAt, DateTime(2026, 9, 20, 12, 30),
          reason: '午休落在值班窗口内 → 班次当天（旧规则会排到前一天中午）');
      expect(plans[0].alarm.label, '起床');
    });

    test('零点班：起床在前一天、班中补觉在当天，两条各归各的', () {
      final s = ShiftSchedule(
        name: '测试',
        anchorDate: DateTime.utc(2026, 9, 20),
        classes: const [
          ShiftClass(
            id: 32,
            name: '夜班',
            abbr: '夜',
            startMinute: 0,
            endMinute: 8 * 60,
            alarmEnabled: true,
            alarms: [
              ShiftAlarm(minute: 23 * 60, label: '起床'),
              ShiftAlarm(minute: 3 * 60, label: '补觉'),
            ],
          ),
        ],
        cycle: const [0],
        teamCount: 1,
        teamNames: const ['我'],
        teamOffsets: const [0],
      );
      final plans =
          planShiftAlarms(s, from: DateTime(2026, 9, 19, 12), days: 2);
      // 9/19 那天的班：起床 9/18 23:00（已过去，跳过）、补觉 9/19 03:00（已过去）
      // 9/20 那天的班：起床 9/19 23:00、补觉 9/20 03:00
      expect(plans.map((p) => p.fireAt).toList(),
          [DateTime(2026, 9, 19, 23), DateTime(2026, 9, 20, 3)]);
      expect(plans.map((p) => p.offset).toList(), [1, 1],
          reason: 'offset 仍按班次那一天算');
      expect(plans.map((p) => p.alarmIndex).toList(), [0, 1]);
    });

    test('按天关闹钟：那天这个班次的闹钟一个都不排', () {
      expect(
          planShiftAlarms(twoAlarms(),
              from: DateTime(2026, 9, 20, 5),
              days: 1,
              overrides: {dayNumber(DateTime(2026, 9, 20)): false}),
          isEmpty);
    });

    // 闹钟页「未来 30 天」那一行留不留：**不能只看第一条**（独立审查抓出来的）。
    test('首条已响、后面还有 → 仍然算「有没响的」，整行不能藏', () {
      final t = twoAlarms().classes.first; // 白班 08:00–20:00，06:30 + 12:30
      final date = DateTime(2026, 9, 20);
      expect(hasPendingShiftAlarm(t, date, DateTime(2026, 9, 20, 9)), isTrue,
          reason: '06:30 响过了，但 12:30 还没到 —— 只看第一条会把整行（'
              '连那一行的「按天关闹钟」开关）一起藏掉，用户当天再也关不掉剩下那条');
      expect(hasPendingShiftAlarm(t, date, DateTime(2026, 9, 20, 13)), isFalse,
          reason: '两条都响过 → 这时才可以藏');
    });

    test('零点班：起床在前一晚已响，班中 03:00 还没到 → 仍算「有」', () {
      const night = ShiftClass(
        name: '夜班',
        abbr: '夜',
        startMinute: 0,
        endMinute: 8 * 60,
        alarmEnabled: true,
        alarms: [
          ShiftAlarm(minute: 23 * 60, label: '起床'),
          ShiftAlarm(minute: 3 * 60, label: '补觉'),
        ],
      );
      // 9/20 那天的班：起床 9/19 23:00、补觉 9/20 03:00
      expect(hasPendingShiftAlarm(night, DateTime(2026, 9, 20),
          DateTime(2026, 9, 19, 23, 30)), isTrue,
          reason: '起床已经响过，但 03:00 还有三个半小时');
      expect(hasPendingShiftAlarm(night, DateTime(2026, 9, 20),
          DateTime(2026, 9, 20, 4)), isFalse);
    });

    test('原生 id 的算式：序号 × 天窗口 + 天数偏移，且落在 0..400 里', () {
      // 这条把 `reschedule` 的 id 算式抄成纯断言 —— 它是「上限 6」的由来。
      final horizon =
          maxAlarmsPerShift * AlarmService.shiftDaysHorizonForTesting;
      expect(horizon, lessThanOrEqualTo(400),
          reason: 'Kotlin 侧 cancelAllNativeAlarms 只扫 0..400（MainActivity.kt:550）');
      final plans = planShiftAlarms(twoAlarms(),
          from: DateTime(2026, 9, 20, 5), days: 3);
      for (final p in plans) {
        final id = p.alarmIndex * AlarmService.shiftDaysHorizonForTesting +
            p.offset;
        expect(id, inInclusiveRange(0, 400));
      }
      // 同一天两个闹钟必须拿到不同的 id（序号把它们分开）
      final ids = plans
          .where((p) => p.offset == 0)
          .map((p) =>
              p.alarmIndex * AlarmService.shiftDaysHorizonForTesting + p.offset)
          .toSet();
      expect(ids, hasLength(2));
    });

    test('重排两次得到同一批 id（序号不能自己变）', () {
      final a = planShiftAlarms(twoAlarms(),
              from: DateTime(2026, 9, 20, 5), days: 5)
          .map((p) => p.alarmIndex * 1000 + p.offset)
          .toList();
      final b = planShiftAlarms(twoAlarms(),
              from: DateTime(2026, 9, 20, 5), days: 5)
          .map((p) => p.alarmIndex * 1000 + p.offset)
          .toList();
      expect(a, b, reason: '同一份数据重排两次必须一致，否则用户设过的响铃记录会错位');
    });
  });

  // 响铃标题：班次名 + 这条闹钟自己的名字。**名字的边界要钉住** —— 只填空格的
  // 名字不能拼成「白班 · 」（屏上会留一个悬着的「·」），也不能把「提醒」拼两遍。
  group('响铃标题（L10n.shiftAlarmTitle）', () {
    tearDown(() => L10n.locale = 'zh');

    test('没名字 → 「白班提醒」（与只有一条闹钟那会儿逐字一致）', () {
      expect(L10n.shiftAlarmTitle('白班', null), '白班提醒');
    });

    test('有名字 → 「白班 · 午休」', () {
      expect(L10n.shiftAlarmTitle('白班', '午休'), '白班 · 午休');
    });

    test('只填空格 / 空串 → 当没填，不留一个悬着的「·」', () {
      expect(L10n.shiftAlarmTitle('白班', '   '), '白班提醒');
      expect(L10n.shiftAlarmTitle('白班', ''), '白班提醒');
    });

    test('两端带空格 → 用 trim 过的名字', () {
      expect(L10n.shiftAlarmTitle('白班', ' 起床 '), '白班 · 起床');
    });

    test('英文界面：无名那条不再露出中文', () {
      L10n.locale = 'en';
      expect(L10n.shiftAlarmTitle('Day shift', null), 'Day shift alarm');
      expect(L10n.shiftAlarmTitle('Day shift', 'Nap'), 'Day shift · Nap');
    });
  });
}
