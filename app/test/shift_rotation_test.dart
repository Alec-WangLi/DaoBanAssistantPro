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
  test('alarmFallsOnPreviousDay：钟点晚于上班钟点才算前一天', () {
    expect(
        alarmFallsOnPreviousDay(
            const ShiftClass(name: '夜班', startMinute: 0, endMinute: 480),
            const ShiftAlarm(minute: 1380)),
        isTrue);

    // 内置 12 小时制夜班：20:30 上班、19:30 响铃 —— 当天，没有歧义。
    expect(
        alarmFallsOnPreviousDay(
            const ShiftClass(name: '夜班', startMinute: 1230, endMinute: 510),
            const ShiftAlarm(minute: 1170)),
        isFalse);

    // 钟点相同：就是上班那一刻本身，算当天。
    expect(
        alarmFallsOnPreviousDay(
            const ShiftClass(name: '白班', startMinute: 480, endMinute: 1020),
            const ShiftAlarm(minute: 480)),
        isFalse);

    // 判断不了的：缺上班时间 —— 按当天（不瞎挪一天）。
    expect(
        alarmFallsOnPreviousDay(
            const ShiftClass(name: '夜班'), const ShiftAlarm(minute: 1380)),
        isFalse);
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

  group('班组错位：撞班检测与均分', () {
    // 用户报的那套：五班三倒的 10 天一轮（白白中中休夜夜休休休），
    // 但各班组仍按 5 天一轮时的 1 天错开 —— 每个班连排两天，于是天天撞。
    final anchor = DateTime.utc(2026, 9, 21);
    ShiftSchedule tenDay({required List<int> offsets}) => ShiftSchedule(
          name: '测试',
          anchorDate: anchor,
          classes: const [
            ShiftClass(id: 1, name: '白班', abbr: '白', startMinute: 510, endMinute: 1230),
            ShiftClass(id: 2, name: '中班', abbr: '中', startMinute: 990, endMinute: 1440),
            ShiftClass(id: 3, name: '夜班', abbr: '夜', startMinute: 0, endMinute: 480),
            ShiftClass(id: 4, name: '休班', abbr: '休', isRest: true),
          ],
          cycle: const [0, 0, 1, 1, 3, 2, 2, 3, 3, 3],
          teamCount: 5,
          teamNames: const ['一班', '二班', '三班', '四班', '五班'],
          ourTeamIndex: 0,
          teamOffsets: offsets,
        );

    test('1 天错开的五个班组在 10 天周期上天天撞', () {
      final clashes = crewClashes(tenDay(offsets: const [0, 1, 2, 3, 4]));
      expect(clashes, hasLength(12), reason: '10 天里 9 天有撞班，共 12 对');
      expect(clashes.map((c) => c.cycleDay).toSet(),
          {1, 2, 3, 4, 5, 6, 8, 9, 10});
      // 用户截图里那张信息卡：一班二班同白、三班四班同中 —— 正是第 1 天。
      final day1 = clashes.where((c) => c.cycleDay == 1).toList();
      expect(day1.map((c) => (c.teamA, c.teamB, c.shift.name)).toSet(),
          {(0, 1, '白班'), (2, 3, '中班')});
    });

    test('按均分规则重排之后一对都不撞', () {
      expect(crewClashes(tenDay(offsets: evenTeamOffsets(10, 5))), isEmpty);
      expect(evenTeamOffsets(10, 5), [0, 2, 4, 6, 8]);
    });

    test('均分时「我们班组」的周期起始日不动', () {
      // 我们班组是第 2 个（下标 1），原错位是 1：均分后它还得是 1，
      // 否则用户自己的排班会被这条修复顺手改掉。整组一起平移，
      // 所以别的班组可能出现负错位 —— 域里与界面都按「基准日 − 错位」算，负值合法。
      final even = evenTeamOffsets(10, 5, keepIndex: 1, keepOffset: 1);
      expect(even[1], 1);
      expect(crewClashes(tenDay(offsets: even)), isEmpty);
      expect(even, [-1, 1, 3, 5, 7]);
    });

    test('休息班不算撞班，空白表返回空', () {
      final two = ShiftSchedule(
        name: '测试',
        anchorDate: anchor,
        classes: const [
          ShiftClass(id: 1, name: '白班', startMinute: 480, endMinute: 1080),
          ShiftClass(id: 2, name: '休班', isRest: true),
        ],
        cycle: const [0, 1],
        teamCount: 2,
        teamNames: const ['一班', '二班'],
        ourTeamIndex: 0,
        teamOffsets: const [0, 0], // 完全重叠：只该在白班那天报一次
      );
      expect(crewClashes(two), hasLength(1));
      expect(crewClashes(two).single.shift.name, '白班');

      final blank = ShiftSchedule(
        name: '跟随法定节假日',
        anchorDate: anchor,
        classes: const [],
        cycle: const [],
      );
      expect(crewClashes(blank), isEmpty);
    });

    test('正常的四班两倒不误报', () {
      expect(crewClashes(defaultSchedule()), isEmpty);
    });
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

  group('ShiftAlarm：班次上的多个闹钟', () {
    const shift = ShiftClass(
      name: '白班',
      startMinute: 8 * 60,
      endMinute: 20 * 60,
      alarmEnabled: true,
      alarms: [
        ShiftAlarm(minute: 6 * 60 + 30, label: '起床'),
        ShiftAlarm(minute: 12 * 60 + 30, label: '午休'),
      ],
    );

    test('alarms 默认空表，且带着 label 一起比相等', () {
      const bare = ShiftClass(name: '休班', isRest: true);
      expect(bare.alarms, isEmpty);
      expect(shift.alarms, hasLength(2));
      expect(shift.alarms.first.label, '起床');
      expect(shift.alarms.first,
          const ShiftAlarm(minute: 6 * 60 + 30, label: '起床'));
      expect(shift.alarms.first == const ShiftAlarm(minute: 6 * 60 + 30),
          isFalse, reason: '名字不同就是不同的闹钟（响铃标题与列表行都靠它）');
    });

    test('闹钟列表参与 ShiftClass 的相等判定', () {
      final same = ShiftClass(
        name: shift.name,
        startMinute: shift.startMinute,
        endMinute: shift.endMinute,
        alarmEnabled: true,
        alarms: const [
          ShiftAlarm(minute: 6 * 60 + 30, label: '起床'),
          ShiftAlarm(minute: 12 * 60 + 30, label: '午休'),
        ],
      );
      final other =
          shift.copyWith(alarms: const [ShiftAlarm(minute: 6 * 60 + 30)]);
      expect(same, equals(shift));
      expect(same.hashCode, shift.hashCode);
      expect(other == shift, isFalse, reason: '少一个闹钟就不是同一个班次定义');
    });
  });

  group('闹钟落在哪天：窗口内算当天（spec §4）', () {
    bool prev(int? start, int? end, int alarm) => alarmFallsOnPreviousDay(
          ShiftClass(name: '班', startMinute: start, endMinute: end),
          ShiftAlarm(minute: alarm),
        );

    test('白班 08:00–20:00：起床当天、午休也当天（旧规则会把午休排到前一天）', () {
      expect(prev(8 * 60, 20 * 60, 6 * 60 + 30), isFalse,
          reason: '窗外早于上班 → 当天');
      expect(prev(8 * 60, 20 * 60, 12 * 60 + 30), isFalse, reason: '窗内 → 当天');
    });

    test('零点班 00:00–08:00：23:00 前一天，班中 03:00 当天', () {
      // 用户 2026-09-21 点名问的就是这一条。
      expect(prev(0, 8 * 60, 23 * 60), isTrue, reason: '窗外晚于上班 → 前一天');
      expect(prev(0, 8 * 60, 3 * 60), isFalse, reason: '班中补觉 → 当天');
      expect(prev(0, 8 * 60, 7 * 60 + 30), isFalse, reason: '窗内 → 当天');
    });

    test('20:00–次日 08:00 的夜班：19:00 与 02:00 都当天', () {
      expect(prev(20 * 60, 8 * 60 + 1440, 19 * 60), isFalse);
      expect(prev(20 * 60, 8 * 60 + 1440, 2 * 60), isFalse);
    });

    // ⚠️ 上面那条用的是**累计式**（endMinute 越过 1440 继续加），而内置 12 小时制
    // 模板与编辑器实际产出的是**回绕式**（endMinute < startMinute）——
    // `span = e - s` 在那种存法下是**负的**，窗口判据会静默失效、班中闹钟又回到
    // 前一天。这条（独立审查抓出来的）就钉这个。
    test('回绕式存法的跨午夜班（20:30 → 08:30 存成 510）也算得对', () {
      expect(prev(20 * 60 + 30, 8 * 60 + 30, 22 * 60), isFalse,
          reason: '22:00 落在值班窗口内 → 当天（不是前一天晚上 22:00）');
      expect(prev(20 * 60 + 30, 8 * 60 + 30, 2 * 60), isFalse,
          reason: '凌晨 2 点也在窗口内');
      expect(prev(20 * 60 + 30, 8 * 60 + 30, 19 * 60), isFalse,
          reason: '19:00 早于上班钟点 → 当天');
    });

    test('两种存法同解：回绕式与累计式在每个钟点上答案一致', () {
      const start = 20 * 60 + 30;
      const endWrapped = 8 * 60 + 30;
      const endAccumulated = endWrapped + 1440;
      for (final alarm in [
        19 * 60,
        20 * 60,
        20 * 60 + 29,
        20 * 60 + 30,
        22 * 60,
        2 * 60,
        8 * 60,
        8 * 60 + 30,
        12 * 60,
      ]) {
        expect(prev(start, endWrapped, alarm),
            prev(start, endAccumulated, alarm),
            reason: '钟点 $alarm：两种存法必须同解（模板存回绕式、24 小时值班存累计式）');
      }
    });

    test('边界：正好等于上班时刻 → 当天', () {
      expect(prev(8 * 60, 20 * 60, 8 * 60), isFalse);
    });

    test('边界：正好等于下班时刻 / 下班之后 —— 与旧规则逐字相同', () {
      // 00:00 班的 08:00：窗外且晚于上班钟点 → 前一天（旧规则同）
      expect(prev(0, 8 * 60, 8 * 60), isTrue);
      // 20:00 班的 08:00：窗外、早于上班钟点 → 当天（旧规则同）
      expect(prev(20 * 60, 8 * 60 + 1440, 8 * 60), isFalse);
      expect(prev(0, 8 * 60, 22 * 60), isTrue, reason: '下班之后的钟点仍是前一天');
    });

    test('24 小时值班：全天都算当天', () {
      expect(prev(8 * 60, 8 * 60 + 1440, 7 * 60), isFalse);
      expect(prev(8 * 60, 8 * 60 + 1440, 12 * 60), isFalse);
      expect(prev(8 * 60, 8 * 60 + 1440, 22 * 60), isFalse);
    });

    test('没填时间：判不了，一律当天', () {
      expect(prev(null, null, 23 * 60), isFalse, reason: '上班时间没填 —— 不瞎挪一天');
      expect(prev(8 * 60, null, 12 * 60 + 30), isTrue,
          reason: '下班时间没填 → 窗口算不出，退回旧规则：12:30 晚于 08:00 → 前一天');
      expect(prev(8 * 60, null, 6 * 60 + 30), isFalse, reason: '退回旧规则：早于上班 → 当天');
      expect(prev(8 * 60, null, 21 * 60), isTrue, reason: '退回旧规则：21:00 晚于 08:00 → 前一天');
    });
  });
}
