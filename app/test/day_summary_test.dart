// `domain/day_summary.dart` —— 「某一天 / 某一个班次在界面上怎么说」。
//
// 这一份是**日历信息卡与桌面小组件快照共用的**，所以它值得单独测：两处各写一遍
// 的时候分岔**不报错**，只表现成「桌面上写的和 App 里写的不是一回事」。
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/day_summary.dart';
import 'package:shiftassistantpro/domain/schedule_chain.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

ShiftClass _cls({
  String name = '白班',
  String abbr = '白',
  int? start = 8 * 60,
  int? end = 20 * 60,
  bool isRest = false,
  bool alarmEnabled = true,
  List<ShiftAlarm> alarms = const [],
}) =>
    ShiftClass(
      name: name,
      abbr: abbr,
      startMinute: start,
      endMinute: end,
      isRest: isRest,
      alarmEnabled: alarmEnabled,
      alarms: alarms,
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
  });
  setUp(() => L10n.locale = 'zh');

  group('alarmNote', () {
    test('休班：写「休息日 · 不响闹钟」', () {
      expect(alarmNote(_cls(isRest: true, alarms: const [])), L10n.restNoAlarm);
    });

    test('总开关关着 / 没挂闹钟：写「未开启」', () {
      expect(alarmNote(_cls(alarmEnabled: false)), L10n.alarmOff);
      expect(alarmNote(_cls(alarms: const [])), L10n.alarmOff);
    });

    test('挂了一个：写「闹钟 HH:MM」', () {
      expect(alarmNote(_cls(alarms: const [ShiftAlarm(minute: 7 * 60)])),
          L10n.alarmAt('07:00'));
    });

    test('挂多个：写首条 + 「等 N 个」', () {
      final t = _cls(alarms: const [
        ShiftAlarm(minute: 7 * 60),
        ShiftAlarm(minute: 18 * 60),
        ShiftAlarm(minute: 19 * 60),
      ]);
      // 只写首条 —— 这一行在卡片上是 maxLines: 1，铺开会把后面的内容挤掉。
      expect(alarmNote(t), L10n.alarmFirstOfMany('07:00', 3));
    });

    test('不落在班次**当天**的钟点必须带标记', () {
      // 00:00 上班 + 23:00 响铃：那个钟点只可能是**前一天**晚上。
      // 不标的话，这一行会跟前面的「00:00 – 08:00」读成同一天的两件事。
      final prev = _cls(start: 0, end: 8 * 60, alarms: const [ShiftAlarm(minute: 23 * 60)]);
      expect(alarmNote(prev), contains('前一天'));

      // 16:30–次日 00:30 的中班 + 00:15：落在**次日**凌晨。
      final next =
          _cls(start: 16 * 60 + 30, end: 30, alarms: const [ShiftAlarm(minute: 15)]);
      expect(alarmNote(next), contains('次日'));
    });

    test('钟点就落在值班窗口里：按当天，不带标记', () {
      final same = _cls(start: 8 * 60, end: 20 * 60, alarms: const [ShiftAlarm(minute: 9 * 60)]);
      expect(alarmNote(same), L10n.alarmAt('09:00'));
    });
  });

  group('monthTallyFor', () {
    ShiftSchedule sched() => ShiftSchedule(
          name: '测试',
          anchorDate: DateTime.utc(2026, 9, 18),
          classes: const [
            ShiftClass(id: 1, name: '白班', abbr: '白', color: 0xFF4C8DFF),
            ShiftClass(id: 2, name: '夜班', abbr: '夜', color: 0xFF7A5CFF),
            ShiftClass(id: 3, name: '休班', abbr: '休', isRest: true, color: 0xFF5A5F73),
          ],
          cycle: const [0, 1, 2],
        );

    test('没有链 / 空白表：返回 null（调用点据此**不画那一行**）', () {
      expect(monthTallyFor(null, DateTime(2026, 10)), isNull);
      // 空白表 = 跟随法定节假日，cycle 为空 ⟹ 整月没有班次定义。
      final blank = ShiftSchedule(
        name: '法定班次',
        anchorDate: DateTime.utc(2026, 9, 18),
        classes: const [],
        cycle: const [],
      );
      expect(monthTallyFor(ScheduleChain(fallback: blank), DateTime(2026, 10)),
          isNull);
    });

    test('按月排：加总等于当月天数，且前缀是「本月」', () {
      final s = monthTallyFor(
          ScheduleChain(fallback: sched()), DateTime(2026, 10));
      expect(s, isNotNull);
      expect(s!, startsWith('${L10n.monthTally} '));
      final nums = RegExp(r'(\d+)$', multiLine: true)
          .allMatches(s.split(' · ').join('\n'))
          .map((m) => int.parse(m.group(1)!))
          .toList();
      expect(nums.reduce((a, b) => a + b), 31, reason: '10 月有 31 天');
    });

    test('**按简称累加**：两套方案的同一个下标不会合并成一个数', () {
      // 这套的左下角就是「按下标数会算错」那条 —— 这里只钉住「不同简称分开计」，
      // 跨方案的完整用例在 widget_snapshot_test.dart 那边。
      final s = monthTallyFor(
          ScheduleChain(fallback: sched()), DateTime(2026, 10))!;
      // 三个班次简称各出现一次，不重复
      for (final abbr in ['白', '夜', '休']) {
        expect(abbr.allMatches(s).length, 1);
      }
    });
  });
}
