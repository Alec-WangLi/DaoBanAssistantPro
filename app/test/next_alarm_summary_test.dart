// app/test/next_alarm_summary_test.dart
//
// 闹钟页顶部那条「下一次响铃 · 今天 15:00 · 白班 巡视 · 还有 1 小时 12 分」。
//
// 钉两件事：
//  1. **下一次的算法只有一份** —— `nextAlarmInfo` 必须与真正排定走同一批纯函数
//     （`planShiftAlarms` / `_customAlarmRequests`）。另写一份的后果是摘要说 15:00、
//     系统里排的却是别的时间：不报错，比不显示更糟。
//  2. 倒计时的分档文案（分钟 / 小时 / 天）与日期写法（今天 / 明天 / 月日）。
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';

/// 白班 08:30–16:30（闹钟 08:00）+ 大休，两天一轮，基准日 10-15 是白班。
ShiftSchedule _schedule() => ShiftSchedule(
      name: '测试排班',
      anchorDate: DateTime.utc(2026, 10, 15),
      classes: const <ShiftClass>[
        ShiftClass(
          name: '白班',
          startMinute: 510,
          endMinute: 990,
          alarmEnabled: true,
          alarms: <ShiftAlarm>[ShiftAlarm(minute: 480, label: '上班')],
        ),
        ShiftClass(name: '大休', isRest: true),
      ],
      cycle: const <int>[0, 1],
    );

CustomAlarm _daily(int hour, int minute) => CustomAlarm(
      id: 1,
      hour: hour,
      minute: minute,
      repeatType: 1,
      weekdays: 0,
      enabled: true,
    );

void main() {
  setUpAll(() async {
    // `L10n.monthDay` 走 `DateFormat`，没初始化语言数据会抛
    // UninitializedLocaleData（与 `alarm_plan_test.dart` 同一条）。
    await initializeDateFormatting('zh');
  });

  group('nextAlarmInfo：下一次响铃', () {
    test('当天还没到：取今天那条班次闹钟', () {
      final info = nextAlarmInfo(_schedule(), const <CustomAlarm>[],
          now: DateTime(2026, 10, 15, 6, 0));
      expect(info, isNotNull);
      expect(info!.fireAt, DateTime(2026, 10, 15, 8, 0));
      expect(info.label, '白班 · 上班');
    });

    test('今天那条已经过去：跳到下一个上班日（跨过一个休息日）', () {
      final info = nextAlarmInfo(_schedule(), const <CustomAlarm>[],
          now: DateTime(2026, 10, 15, 9, 0));
      expect(info!.fireAt, DateTime(2026, 10, 17, 8, 0));
    });

    test('自定义闹钟更近时取自定义', () {
      final info = nextAlarmInfo(
        _schedule(),
        <CustomAlarm>[_daily(7, 0)],
        now: DateTime(2026, 10, 15, 6, 0),
      );
      expect(info!.fireAt, DateTime(2026, 10, 15, 7, 0));
      expect(info.label, L10n.customAlarmTitle);
    });

    test('班次闹钟更近时取班次（同样在 6 点整比较）', () {
      final info = nextAlarmInfo(
        _schedule(),
        <CustomAlarm>[_daily(9, 0)],
        now: DateTime(2026, 10, 15, 6, 0),
      );
      expect(info!.fireAt, DateTime(2026, 10, 15, 8, 0));
      expect(info.label, '白班 · 上班');
    });

    test('一条都没有时返回 null（空白表 / 全关）', () {
      final blank = ShiftSchedule(
        name: '空白',
        anchorDate: DateTime.utc(2026, 10, 15),
        classes: const <ShiftClass>[],
        cycle: const <int>[],
      );
      expect(nextAlarmInfo(blank, const <CustomAlarm>[],
              now: DateTime(2026, 10, 15, 6, 0)),
          isNull);
    });
  });

  group('倒计时文案', () {
    test('一分钟内说「马上」', () {
      expect(L10n.alarmCountdown(Duration.zero), '马上响');
      expect(L10n.alarmCountdown(const Duration(seconds: 40)), '马上响');
    });

    test('一小时内说分钟', () {
      expect(L10n.alarmCountdown(const Duration(minutes: 5)), '还有 5 分钟');
      expect(L10n.alarmCountdown(const Duration(minutes: 59)), '还有 59 分钟');
    });

    test('一天内说小时 + 分（整点不写 0 分）', () {
      expect(
        L10n.alarmCountdown(const Duration(hours: 1, minutes: 12)),
        '还有 1 小时 12 分',
      );
      expect(L10n.alarmCountdown(const Duration(hours: 2)), '还有 2 小时');
    });

    test('更远只说天 + 小时', () {
      expect(
        L10n.alarmCountdown(const Duration(days: 1, hours: 3)),
        '还有 1 天 3 小时',
      );
      expect(L10n.alarmCountdown(const Duration(days: 2)), '还有 2 天');
    });
  });

  group('日期写法', () {
    final now = DateTime(2026, 10, 15, 9, 0);

    test('今天 / 明天 / 更远给月日', () {
      expect(L10n.alarmDayLabel(DateTime(2026, 10, 15, 20, 0), now), '今天');
      expect(L10n.alarmDayLabel(DateTime(2026, 10, 16, 7, 0), now), '明天');
      expect(L10n.alarmDayLabel(DateTime(2026, 10, 18, 7, 0), now), '10月18日');
    });
  });

  test('摘要整行的拼法', () {
    final line = L10n.nextAlarmLine('今天', '15:00', '白班 · 巡视', '还有 1 小时 12 分');
    expect(line, '下一次响铃 · 今天 15:00 · 白班 · 巡视 · 还有 1 小时 12 分');
  });
}
