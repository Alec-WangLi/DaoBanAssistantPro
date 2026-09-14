// app/test/event_reminder_test.dart
//
// 待办提醒的两处纯逻辑：
//   - 提醒时刻怎么算（`AlarmService.eventReminderTime`）
//   - 提醒档位怎么显示（`L10n.remindOptionLabel`）
//
// 这两样错了都**不会报错**：前者只会在错的时候提醒、后者只是文案不对，靠界面
// 看不出来，所以钉在单测里。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';

/// 造一条待办。[date] 按库里的存法传 `dateOnly(...)`（UTC 纯日期）。
ScheduleEvent _event({
  DateTime? date,
  int? timeMinute,
  int? advance,
  bool completed = false,
  bool alarm = false,
}) {
  final d = date ?? DateTime.now();
  return ScheduleEvent(
    id: 1,
    title: '交体检报告',
    date: dateOnly(d),
    timeMinute: timeMinute,
    advanceRemindMinutes: advance,
    isCompleted: completed,
    alarmEnabled: alarm,
    createdAt: DateTime.now(),
  );
}

void main() {
  setUp(() {
    L10n.locale = 'zh';
  });

  group('eventReminderTime', () {
    test('没设提醒的待办不排（advanceRemindMinutes 为 null）', () {
      // 这个字段以前只被「显示」、从不参与排定 —— 用户设了提前提醒却什么都不
      // 会发生。这一条钉住它现在真的参与了。
      expect(AlarmService.eventReminderTime(_event(advance: null)), isNull);
    });

    test('已完成的待办不排', () {
      expect(
        AlarmService.eventReminderTime(_event(timeMinute: 600, advance: 15, completed: true)),
        isNull,
      );
    });

    test('设了时间：按时间提前算', () {
      final date = DateTime(2026, 9, 20);
      final t = AlarmService.eventReminderTime(
          _event(date: date, timeMinute: 14 * 60 + 30, advance: 15));
      expect(t, DateTime(2026, 9, 20, 14, 15));
    });

    test('没设时间：以当天 09:00 为基准', () {
      final date = DateTime(2026, 9, 20);
      final t = AlarmService.eventReminderTime(
          _event(date: date, timeMinute: null, advance: 60));
      expect(t, DateTime(2026, 9, 20, 8, 0));
      expect(allDayReminderHour, 9, reason: '基准整点改了要一起改这条');
    });

    test('准时（advance 为 0）：就在事件当时', () {
      final date = DateTime(2026, 9, 20);
      final t = AlarmService.eventReminderTime(
          _event(date: date, timeMinute: 20 * 60, advance: 0));
      expect(t, DateTime(2026, 9, 20, 20, 0));
    });

    test('提前一天：落到前一天', () {
      final date = DateTime(2026, 9, 20);
      final t = AlarmService.eventReminderTime(
          _event(date: date, timeMinute: 8 * 60, advance: 24 * 60));
      expect(t, DateTime(2026, 9, 19, 8, 0));
    });

    test('返回的是**本地**时间，不是 UTC', () {
      // 库里的 date 是 `dateOnly` 存的 UTC 纯日期；算出来的时刻直接拿
      // `millisecondsSinceEpoch` 交给原生排定，所以它必须按设备本地时区重建。
      // 忘了这一步的话，提醒会整体差一个时区偏移（东八区差 8 小时），而且
      // 不报错、只是时候不对。
      final date = DateTime(2026, 9, 20);
      final t = AlarmService.eventReminderTime(
          _event(date: date, timeMinute: 12 * 60, advance: 0))!;
      expect(t.isUtc, isFalse, reason: '必须是本地时间');
      expect(t.hour, 12);
      expect(t.millisecondsSinceEpoch,
          DateTime(2026, 9, 20, 12, 0).millisecondsSinceEpoch);
    });
  });

  group('isSameDay', () {
    test('跨 UTC / 本地也要认得出同一天', () {
      // `dateOnly` 给的是 UTC 日期，日历网格里逐格构造的是本地日期。
      // `DateTime.==` 连 `isUtc` 一起比，所以 `==` 在这里恒为假 —— 网格里
      // 「今天加粗」和「选中那格胶囊变实心」都踩过这个坑。
      final utc = dateOnly(DateTime(2026, 9, 14, 23, 30));
      final local = DateTime(2026, 9, 14, 0, 0);
      expect(utc == local, isFalse, reason: '`==` 连 isUtc 一起比，这里是反例本身');
      expect(isSameDay(utc, local), isTrue);
    });

    test('差一天就不是同一天', () {
      expect(isSameDay(DateTime(2026, 9, 14), DateTime(2026, 9, 15)), isFalse);
    });
  });

  group('remindOptionLabel', () {
    test('中文档位文案', () {
      expect(L10n.remindOptionLabel(L10n.remindNone), '不设');
      expect(L10n.remindOptionLabel(0), '准时');
      expect(L10n.remindOptionLabel(5), '提前5分钟');
      expect(L10n.remindOptionLabel(60), '提前1小时');
      expect(L10n.remindOptionLabel(1440), '提前1天');
    });

    test('英文档位文案', () {
      L10n.locale = 'en';
      expect(L10n.remindOptionLabel(L10n.remindNone), 'None');
      expect(L10n.remindOptionLabel(0), 'On time');
      expect(L10n.remindOptionLabel(15), '15 min ahead');
      expect(L10n.remindOptionLabel(60), '1 h ahead');
      expect(L10n.remindOptionLabel(1440), '1 d ahead');
    });

    test('档位表里有「准时」，且哨兵值不在档位表之外', () {
      // 「准时」是特意补的一档：只有「不设 / 提前 15 分钟」时，不想提前的人
      // 只能选「不设」，等于没有提醒。
      expect(L10n.remindOptions, contains(0));
      expect(L10n.remindOptions.first, L10n.remindNone);
      expect(L10n.remindNone, lessThan(0),
          reason: '哨兵必须是个不会跟真实分钟数撞上的值');
    });
  });
}
