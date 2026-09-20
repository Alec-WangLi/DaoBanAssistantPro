import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

void main() {
  setUp(() {
    // 本文件断言的是 defaultSchedule() 的**中文**取值（它按当前语言生成），
    // 所以语言必须显式钉死 —— 别再让它隐式依赖 L10n.locale 的初值。
    L10n.locale = 'zh';
  });

  test('daysBetween 整日差', () {
    expect(daysBetween(DateTime(2025, 1, 1), DateTime(2025, 1, 6)), 5);
    expect(daysBetween(DateTime(2025, 1, 6), DateTime(2025, 1, 1)), -5);
    expect(daysBetween(DateTime(2025, 1, 6), DateTime(2025, 1, 6)), 0);
  });

  test('四班两倒周期正确（白班→上夜班→下夜班→大休）', () {
    final s = defaultSchedule();
    expect(s.cycleLength, 4);
    expect(s.shiftOn(DateTime(2025, 1, 6))!.name, '白班'); // 锚点
    expect(s.shiftOn(DateTime(2025, 1, 7))!.name, '上夜班');
    expect(s.shiftOn(DateTime(2025, 1, 8))!.name, '下夜班');
    expect(s.shiftOn(DateTime(2025, 1, 9))!.name, '大休');
    expect(s.shiftOn(DateTime(2025, 1, 10))!.name, '白班');
  });

  test('负偏移回绕（锚点之前）', () {
    final s = defaultSchedule();
    expect(s.shiftOn(DateTime(2025, 1, 5))!.name, '大休');
    expect(s.shiftOn(DateTime(2025, 1, 4))!.name, '下夜班');
    expect(s.shiftOn(DateTime(2025, 1, 3))!.name, '上夜班');
    expect(s.shiftOn(DateTime(2025, 1, 2))!.name, '白班');
  });

  test('跨午夜判断', () {
    final s = defaultSchedule();
    expect(s.shiftOn(DateTime(2025, 1, 7))!.crossesMidnight, isTrue); // 上夜班
    expect(s.shiftOn(DateTime(2025, 1, 6))!.crossesMidnight, isFalse); // 白班
  });

  test('休息日标记', () {
    final s = defaultSchedule();
    expect(s.shiftOn(DateTime(2025, 1, 8))!.isRest, isTrue); // 下夜班
    expect(s.shiftOn(DateTime(2025, 1, 9))!.isRest, isTrue); // 大休
    expect(s.shiftOn(DateTime(2025, 1, 6))!.isRest, isFalse); // 白班
  });

  // 响铃落在上班前一天：判据是「响铃钟点晚于上班钟点」。00:00 上班的夜班配
  // 23:00 响铃就是它（排到班次当天的话，响铃时这个班已经结束 15 小时）。
  test('alarmPreviousDay：钟点晚于上班钟点才算前一天', () {
    const midnight =
        ShiftClass(name: '夜班', startMinute: 0, endMinute: 480, alarmMinute: 1380);
    expect(midnight.alarmPreviousDay, isTrue);

    // 内置 12 小时制夜班：20:30 上班、19:30 响铃 —— 当天，没有歧义。
    const evening = ShiftClass(
        name: '夜班', startMinute: 1230, endMinute: 510, alarmMinute: 1170);
    expect(evening.alarmPreviousDay, isFalse);

    // 钟点相同：就是上班那一刻本身，算当天。
    const same =
        ShiftClass(name: '白班', startMinute: 480, endMinute: 1020, alarmMinute: 480);
    expect(same.alarmPreviousDay, isFalse);

    // 判断不了的两种：缺上班时间 / 缺响铃时间。
    expect(
        const ShiftClass(name: '夜班', alarmMinute: 1380).alarmPreviousDay, isFalse);
    expect(
        const ShiftClass(name: '夜班', startMinute: 0).alarmPreviousDay, isFalse);
  });

  test('多班组错开（四班两倒 4 个班）', () {
    final s = defaultSchedule();
    expect(s.teamCount, 4);
    expect(s.teamNames, ['一班', '二班', '三班', '四班']);
    expect(s.ourTeamIndex, 0);
    // 锚点日（我们=一班 白班）：一班白班、二班上夜班、三班下夜班、四班大休
    final anchor = DateTime(2025, 1, 6);
    expect(s.teamShift(0, anchor)!.name, '白班');
    expect(s.teamShift(1, anchor)!.name, '上夜班');
    expect(s.teamShift(2, anchor)!.name, '下夜班');
    expect(s.teamShift(3, anchor)!.name, '大休');
    // 我们班组的班次 = shiftOn
    expect(s.shiftOn(anchor)!.name, s.teamShift(0, anchor)!.name);
    // 次日错开：一班上夜班、二班下夜班、三班大休、四班白班
    final next = DateTime(2025, 1, 7);
    expect(s.teamShift(0, next)!.name, '上夜班');
    expect(s.teamShift(1, next)!.name, '下夜班');
    expect(s.teamShift(2, next)!.name, '大休');
    expect(s.teamShift(3, next)!.name, '白班');
  });

  test('图层：周期引用的是班次定义，不是每天一行', () {
    final s = ShiftSchedule(
      name: '白白夜夜休休',
      anchorDate: DateTime.utc(2025, 1, 6),
      classes: const [
        ShiftClass(name: '白班', abbr: '白'),
        ShiftClass(name: '夜班', abbr: '夜'),
        ShiftClass(name: '休班', abbr: '休', isRest: true),
      ],
      cycle: const [0, 0, 1, 1, 2, 2],
      teamCount: 3,
      teamNames: const ['一班', '二班', '三班'],
      teamOffsets: const [0, 2, 4],
    );
    expect(s.cycleLength, 6);
    expect(s.classes.length, 3);
    expect(s.shiftOn(DateTime.utc(2025, 1, 6))!.name, '白班');
    expect(s.shiftOn(DateTime.utc(2025, 1, 8))!.name, '夜班');
    expect(s.shiftOn(DateTime.utc(2025, 1, 11))!.name, '休班');
  });

  test('格子简称：显式 abbr 优先，为空时按名称推断', () {
    expect(const ShiftClass(name: '早班', abbr: '早').shortLabel, '早');
    expect(const ShiftClass(name: '早班').shortLabel, '白'); // 旧的推断行为
    expect(const ShiftClass(name: '大夜').shortLabel, '夜');
    expect(const ShiftClass(name: '休班', isRest: true).shortLabel, '休');
    expect(const ShiftClass(name: '').shortLabel, '·');
    // emoji 开头：应取到完整字素簇，不能切成半个代理对
    expect(const ShiftClass(name: '🔥白班').shortLabel, '白'); // 含「白」走推断
    expect(const ShiftClass(name: '🔥').shortLabel, '🔥');
    expect(const ShiftClass(name: '👨‍👩‍👧').shortLabel, '👨‍👩‍👧');
  });

  test('24 小时值班跨午夜', () {
    const duty = ShiftClass(name: '值班', startMinute: 8 * 60, endMinute: 32 * 60);
    expect(duty.crossesMidnight, isTrue);
    const mid = ShiftClass(name: '中班', startMinute: 16 * 60, endMinute: 24 * 60);
    expect(mid.crossesMidnight, isFalse); // 16:00–24:00 不算跨午夜
  });

  test('endClockMinute / endsNextDay：把「结束落在次日」变成一个概念', () {
    // 值班 24 小时：08:00 → 次日 08:00
    const duty = ShiftClass(name: '值班', startMinute: 8 * 60, endMinute: 32 * 60);
    expect(duty.endClockMinute, 8 * 60);
    expect(duty.endsNextDay, isTrue);
    expect(duty.crossesMidnight, isTrue);

    // 中班 16:00 → 24:00：24:00 与「次日 00:00」是同一时刻，两种判定都算跨日
    const mid = ShiftClass(name: '中班', startMinute: 16 * 60, endMinute: 24 * 60);
    expect(mid.endClockMinute, 0);
    expect(mid.endsNextDay, isTrue);
    expect(mid.crossesMidnight, isFalse); // 显示上按当日 24:00 处理

    // 上夜班 20:30 → 次日 08:30：靠 e < s 判定
    const night =
        ShiftClass(name: '上夜班', startMinute: 20 * 60 + 30, endMinute: 8 * 60 + 30);
    expect(night.endClockMinute, 8 * 60 + 30);
    expect(night.endsNextDay, isTrue);

    // 白班 08:30 → 20:30：当天结束
    const day =
        ShiftClass(name: '白班', startMinute: 8 * 60 + 30, endMinute: 20 * 60 + 30);
    expect(day.endClockMinute, 20 * 60 + 30);
    expect(day.endsNextDay, isFalse);

    // 时间为空（休班）
    const rest = ShiftClass(name: '休班', isRest: true);
    expect(rest.endClockMinute, isNull);
    expect(rest.endsNextDay, isFalse);
  });

  group('按天改班覆盖', () {
    /// 拿默认「四班两倒」当底，只换 dayOverrides。
    ShiftSchedule withOverrides(Map<int, int> overrides) {
      final base = defaultSchedule();
      return ShiftSchedule(
        name: base.name,
        anchorDate: base.anchorDate,
        classes: base.classes,
        cycle: base.cycle,
        teamCount: base.teamCount,
        teamNames: base.teamNames,
        ourTeamIndex: base.ourTeamIndex,
        teamOffsets: base.teamOffsets,
        dayOverrides: overrides,
      );
    }

    final day = DateTime(2026, 9, 20);

    test('覆盖命中：那天返回覆盖的班次', () {
      final s = withOverrides({dayNumber(day): 3});
      final bare = withOverrides(const {});
      expect(s.shiftOn(day)!.name, isNot(bare.shiftOn(day)!.name),
          reason: '这天应当换成了别的班');
      expect(s.shiftOn(day)!.name, bare.classes[3].name);
    });

    test('没被覆盖的日子仍是轮转结果', () {
      // 覆盖值取 1（上夜班），**不能取 3**：那天轮转是 `622 % 4 = 2`（下夜班）、
      // 次日是 `623 % 4 = 3`（大休），取 3 的话「覆盖值」与「次日的轮转值」正好
      // 是同一个下标 —— 一个把日键丢掉、永远返回 `classes[ov]` 的实现也能过。
      final s = withOverrides({dayNumber(day): 1});
      final bare = withOverrides(const {});
      final next = day.add(const Duration(days: 1));
      expect(s.shiftOn(next)!.name, bare.shiftOn(next)!.name);
      expect(s.shiftOn(next)!.name, isNot(s.shiftOn(day)!.name),
          reason: '次日没被覆盖，得是它自己的轮转班次，不是覆盖值照抄一天');
    });

    test('下标越界回退到轮转，不抛异常', () {
      final s = withOverrides({dayNumber(day): 99});
      final bare = withOverrides(const {});
      expect(s.shiftOn(day)!.name, bare.shiftOn(day)!.name);
    });

    test('teamShift 不受覆盖影响（其他班组仍是纯轮转）', () {
      final s = withOverrides({dayNumber(day): 3});
      final bare = withOverrides(const {});
      for (var t = 0; t < 4; t++) {
        expect(s.teamShift(t, day)!.name, bare.teamShift(t, day)!.name,
            reason: '第 $t 组不该被「我」的覆盖改掉');
      }
    });

    test('空白表方案忽略覆盖（无周期 → 仍是 null）', () {
      final blank = ShiftSchedule(
        name: '跟随法定节假日',
        anchorDate: DateTime.utc(2025, 1, 6),
        classes: const [],
        cycle: const [],
        dayOverrides: {dayNumber(day): 0},
      );
      expect(blank.shiftOn(day), isNull);
    });

    test('ShiftClass 带 id 时按 id 区分身份', () {
      const a = ShiftClass(id: 1, name: '白班');
      const b = ShiftClass(id: 2, name: '白班');
      const noId = ShiftClass(name: '白班');
      expect(a, isNot(b), reason: '内容相同但 id 不同 = 两个不同实体');
      expect(a, isNot(noId));
      expect(a.copyWith(abbr: '白').id, 1, reason: 'copyWith 必须保住 id');
    });
  });
}
