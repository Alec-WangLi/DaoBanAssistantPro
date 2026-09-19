// 桌面小组件快照 —— 纯函数 `buildWidgetSnapshot`。
//
// 为什么这一层值得单独测：整个小组件的正确性都压在它身上。原生侧只是个排版器
// （Kotlin 里一个中文字符串都没有），所以「今天/明天对不对」「跨午夜班次的时间串
// 对不对」「按月窗口够不够」这些判断一旦错了，真机上表现为「卡片显示别的班的
// 时间」，而且不报错。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/widget/widget_service.dart';
import 'package:shiftassistantpro/features/widget/widget_snapshot.dart';

/// 与 `shift_alarm_decision_test.dart` 同款：班次名写死，用例断言**结构**不论文案。
ShiftSchedule _schedule({Map<int, int> overrides = const {}}) => ShiftSchedule(
      name: '测试',
      anchorDate: DateTime.utc(2026, 9, 18),
      classes: const [
        ShiftClass(
            id: 11,
            name: '白班',
            abbr: '白',
            startMinute: 8 * 60 + 30,
            endMinute: 20 * 60 + 30,
            color: 0xFF4C8DFF),
        ShiftClass(
            id: 12,
            name: '夜班',
            abbr: '夜',
            startMinute: 20 * 60 + 30,
            endMinute: 8 * 60 + 30,
            color: 0xFF7A5CFF),
        ShiftClass(id: 13, name: '休班', abbr: '休', isRest: true, color: 0xFF5A5F73),
      ],
      cycle: const [0, 1, 2],
      dayOverrides: overrides,
    );

/// 取快照里某一天的那一行。
///
/// v2 起窗口是「按月对齐的绝对窗口」，含**过去**的天 —— `days[0]` 不再是今天，
/// 所以凡是指名某一天的用例都得按日期找行，不能再拿下标当日期用。
Map _rowOf(Map snapshot, DateTime date) => (snapshot['days']! as List)
    .cast<Map>()
    .firstWhere((r) => r['day'] == dayNumber(date));

void main() {
  // `L10n.monthDay` 走 `DateFormat(..., 'zh'|'en')`，两种语言的 locale 数据都
  // 要先装好（英文那条用例会在 locale='en' 下生成快照）—— 与
  // `glass_pickers_layout_test.dart` / `shift_template_picker_test.dart` 同款。
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
  });

  setUp(() => L10n.locale = 'zh');

  test('窗口 = [min(本月1日, 本周一), 下月最后一天]，且恒包含今天', () {
    for (final now in [
      DateTime(2026, 9, 20, 10),
      DateTime(2026, 10, 1, 0, 5), // 跨月当天
      DateTime(2026, 12, 31, 23, 55), // 年末
      DateTime(2027, 2, 14, 12),
    ]) {
      final s = buildWidgetSnapshot(
        schedule: null,
        now: now,
        themeMode: 'system',
        accent: 0xFF4F5BE8,
        todayTodoCount: 0,
      );
      final days = (s['days']! as List).cast<Map>();
      final first = days.first['day'] as int;
      final last = days.last['day'] as int;

      final monthStart = dayNumber(DateTime(now.year, now.month, 1));
      final weekMonday =
          dayNumber(DateTime(now.year, now.month, now.day - (now.weekday - 1)));
      expect(first, monthStart < weekMonday ? monthStart : weekMonday,
          reason: '窗口起点应当是「本月1日」与「本周一」里更早的那个（now=$now）');
      expect(last, dayNumber(DateTime(now.year, now.month + 2, 0)),
          reason: '窗口终点应当是本月的下一个月最后一天（now=$now）');

      // 恒包含今天，且 day 逐日递增
      final today = dayNumber(now);
      expect(days.any((d) => d['day'] == today), true,
          reason: '窗口必须包含今天（now=$now）');
      for (var i = 1; i < days.length; i++) {
        expect(days[i]['day'], (days[i - 1]['day'] as int) + 1);
      }
      expect(days.length, lessThanOrEqualTo(68));

      // 月份表必须一路滚到窗口终点的那个月 —— 年末那条（now = 2026-12-31）因此
      // 必须给出 2027-1，而不是停在 12 月。原生日历的月份标题是「查不到就隐藏
      // 整行」，rolling 一停整条标题就消失了，而不会有任何东西报错。
      final window = widgetWindow(now);
      final months = (s['months']! as List).cast<Map>();
      expect(months.first['y'], window.from.year, reason: '首个标题（now=$now）');
      expect(months.first['m'], window.from.month);
      expect(months.last['y'], window.to.year,
          reason: '末个标题的年份应当是 ${window.to.year}（now=$now）');
      expect(months.last['m'], window.to.month,
          reason: '末个标题的月份应当是 ${window.to.month}（now=$now）');

      // 农历完整描述要印在 4×3 今日卡上（`renderTodayCard` 的 wg_tc_lunar），
      // 空串会让那一行变成一条空白。
      expect(((s['todayCard']! as Map)['lunarFull'] as String), isNotEmpty,
          reason: '今日卡的完整农历不能是空串（now=$now）');
    }
  });

  test('窗口含过去的天：9/20 的窗口起点是 9/1（本月 1 日比本周一 9/14 更早）', () {
    final s = buildWidgetSnapshot(
      schedule: null,
      now: DateTime(2026, 9, 20, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    final days = (s['days']! as List).cast<Map>();
    final todayIndex =
        days.indexWhere((d) => d['day'] == dayNumber(DateTime(2026, 9, 20)));
    expect(todayIndex, greaterThan(0), reason: '今天不在第一项 —— 窗口里应当有更早的天');
  });

  test('days 每条都带农历；weekdays 七条、months 覆盖窗口的月', () {
    final s = buildWidgetSnapshot(
      schedule: null,
      now: DateTime(2026, 10, 1, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    final days = (s['days']! as List).cast<Map>();
    for (final d in days) {
      expect(d['lunarShort'], isA<String>());
      expect((d['lunarShort'] as String), isNotEmpty);
      expect(d['lunarIsHoliday'], isA<bool>());
      expect(d.containsKey('abbrInk'), false, reason: 'abbrInk 已删 —— 胶囊文字改走 wg_ink_*');
    }
    expect((s['weekdays']! as List).length, 7);
    expect((s['weekdays']! as List).first, L10n.weekday(0));

    // 2026-10-01 是周四 → 窗口从 9/28（周一）起、到 11/30 止，覆盖 9/10/11 三个月
    final months = (s['months']! as List).cast<Map>();
    expect(months.map((m) => '${m['y']}-${m['m']}').toList(),
        ['2026-9', '2026-10', '2026-11']);
    expect(months.first['title'], L10n.yearMonth(DateTime(2026, 9)));
  });

  test('协议版本是 2', () {
    final s = buildWidgetSnapshot(
      schedule: null,
      now: DateTime(2026, 9, 20, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    expect(s['v'], 2);
  });

  test('空白表（schedule=null）仍按窗口天数产出空行，并带上空表提示', () {
    final now = DateTime(2026, 9, 18, 10);
    final s = buildWidgetSnapshot(
      schedule: null,
      now: now,
      themeMode: 'light',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    expect(s['hasSchedule'], false);
    expect(s['emptyHint'], L10n.widgetEmptyHint);
    final window = widgetWindow(now);
    final days = s['days']! as List;
    expect(days.length, dayNumber(window.to) - dayNumber(window.from) + 1);
    for (final d in days) {
      final m = d as Map;
      expect(m['hasShift'], false);
      expect(m['timeRange'], isNull);
      expect(m['color'], 0);
    }
  });

  test('空白表方案（schedule 非 null 但 isBlank）也算「没有排班」', () {
    final blank = ShiftSchedule(
      name: '跟随法定节假日',
      anchorDate: DateTime.utc(2026, 9, 18),
      classes: const [],
      cycle: const [],
    );
    final s = buildWidgetSnapshot(
      schedule: blank,
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    expect(s['hasSchedule'], false);
  });

  test('跨午夜班次的时间串由 L10n.timeRange 产出，不拼前缀', () {
    final s = buildWidgetSnapshot(
      // 9/19 在 3 天周期里是第 1 天 → 夜班（20:30 → 次日 08:30）
      schedule: _schedule(),
      now: DateTime(2026, 9, 19, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    final d0 = _rowOf(s, DateTime(2026, 9, 19));
    expect(d0['shiftName'], '夜班');
    expect(d0['timeRange'], L10n.timeRange('20:30', '08:30', true));
  });

  test('英文界面下跨午夜不露出中文', () {
    L10n.locale = 'en';
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: DateTime(2026, 9, 19, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    final d0 = _rowOf(s, DateTime(2026, 9, 19));
    expect((d0['timeRange']! as String).contains('次日'), false);
    expect(d0['timeRange'], '20:30 – 08:30 (next day)');
  });

  test('24 小时班（08:00 → 24:00）的结束落在次日零点，不误加一天', () {
    final s = buildWidgetSnapshot(
      schedule: ShiftSchedule(
        name: '测试',
        anchorDate: DateTime.utc(2026, 9, 18),
        classes: const [
          ShiftClass(
              id: 21,
              name: '全天班',
              abbr: '全',
              startMinute: 8 * 60,
              endMinute: 24 * 60,
              color: 0xFF4C8DFF),
        ],
        cycle: const [0],
      ),
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    final d0 = _rowOf(s, DateTime(2026, 9, 18));
    // `endMinute == 1440` 走的是 `widget_snapshot.dart` 里那条专门注释过的分支：
    // 「endMinute ≥ 1440 —— 本身就落在次日，加了反而过头」，所以不再 +1 天。
    // 格式上 1440 印成 24:00，且 `endsNextDay`（e ≥ 1440）为真 → 带「次日」。
    expect(d0['shiftName'], '全天班');
    expect(d0['timeRange'], L10n.timeRange('08:00', '24:00', true));

    // 结束「边界」＝次日零点。窗口最后一天（10/31）的同一个 24 小时班结束在
    // 11/1 00:00；若误按跨午夜那条 +1 天，会跑到 11/2 00:00，`b.last` 会露馅。
    final b = (s['boundaries']! as List).cast<int>();
    expect(b.contains(DateTime(2026, 9, 19).millisecondsSinceEpoch), true);
    expect(b.last, DateTime(2026, 11, 1).millisecondsSinceEpoch,
        reason: '10/31 的 24 小时班结束在 11/1 00:00；误加一天会变成 11/2');
  });

  test('按天改班反映到快照里（快照走 shiftOn，不是 teamShift）', () {
    // 「引擎留在 Dart」的核心理由：快照必须走 `shiftOn`（查按天覆盖），
    // 而不是 `teamShift`（纯轮转）——否则日历上按天改的班在桌面上看不到。
    // 这条把它钉住。
    final withOverride = ShiftSchedule(
      name: '测试',
      anchorDate: DateTime.utc(2026, 9, 18),
      classes: const [
        ShiftClass(
            id: 11,
            name: '白班',
            abbr: '白',
            startMinute: 8 * 60 + 30,
            endMinute: 20 * 60 + 30,
            color: 0xFF4C8DFF),
        ShiftClass(
            id: 12,
            name: '夜班',
            abbr: '夜',
            startMinute: 20 * 60 + 30,
            endMinute: 8 * 60 + 30,
            color: 0xFF7A5CFF),
        ShiftClass(id: 13, name: '休班', abbr: '休', isRest: true, color: 0xFF5A5F73),
      ],
      cycle: const [0, 1, 2],
      // 9/19 本按轮转是夜班，被按天改成休班（覆盖存的是 classes **下标**，2 = 休班）。
      dayOverrides: {dayNumber(DateTime(2026, 9, 19)): 2},
    );
    final s = buildWidgetSnapshot(
      schedule: withOverride,
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    // 9/19：纯轮转视角是夜班，覆盖把它改成了休班。
    final overridden = _rowOf(s, DateTime(2026, 9, 19));
    expect(overridden['shiftName'], '休班');
    expect(overridden['isRest'], true);
    // 未覆盖的 9/18 不受影响（仍是白班）。
    expect(_rowOf(s, DateTime(2026, 9, 18))['shiftName'], '白班');

    // 反证：不带覆盖的同一方案里 9/19 是夜班 —— 差异确实来自覆盖。
    final plain = buildWidgetSnapshot(
      schedule: _schedule(),
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    expect(_rowOf(plain, DateTime(2026, 9, 19))['shiftName'], '夜班');
  });

  test('休班行没有时间串', () {
    final restDay = DateTime(2026, 9, 20); // 周期第 2 天 → 休班
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: restDay,
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    final d0 = _rowOf(s, restDay);
    expect(d0['isRest'], true);
    expect(d0['timeRange'], isNull);
  });

  test('boundaries 升序、无重复、都是未来时刻', () {
    final now = DateTime(2026, 9, 18, 10);
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: now,
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    final b = (s['boundaries']! as List).cast<int>();
    expect(b, isNotEmpty);
    for (var i = 1; i < b.length; i++) {
      expect(b[i] > b[i - 1], true, reason: '必须严格递增（已去重）');
    }
    for (final t in b) {
      expect(t > now.millisecondsSinceEpoch, true);
    }
    // 窗口里每一天都贡献了**次日**的本地零点；过去那几天的零点已经来过、不进
    // boundaries，所以留下的这些全在未来（至少还有旧版 14 天窗口那么多条）。
    // 原稿这里的注释写反了，Task 1 实做时发现。
    expect(b.where((t) => t > now.millisecondsSinceEpoch).length >= 14, true);
  });

  test('主题模式原样透传，不在这里解析成 light/dark', () {
    for (final mode in ['system', 'light', 'dark']) {
      final s = buildWidgetSnapshot(
        schedule: _schedule(),
        now: DateTime(2026, 9, 18, 10),
        themeMode: mode,
        accent: 0xFF4F5BE8,
        todayTodoCount: 0,
      );
      expect(s['themeMode'], mode);
    }
  });

  test('快照可以 JSON 往返（原生按 org.json 解析，类型错了会静默变默认值）', () {
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    final back = jsonDecode(jsonEncode(s)) as Map<String, dynamic>;
    expect(back['v'], kWidgetSnapshotVersion);
    expect(back['days'], hasLength((s['days']! as List).length));
    expect(back['boundaries'], isA<List>());
    final d0 = (back['days'] as List).first as Map<String, dynamic>;
    expect(d0['day'], isA<int>());
    expect(d0['hasShift'], isA<bool>());
    expect(d0['color'], isA<int>());
  });

  test('epochDay ↔ DateTime 换算：与 dayNumber 互为逆运算', () {
    for (final d in [
      DateTime(2026, 9, 18),
      DateTime(2026, 1, 1),
      DateTime(2026, 12, 31),
      DateTime(2027, 2, 28),
    ]) {
      expect(dayNumber(WidgetService.dateFromEpochDay(dayNumber(d))), dayNumber(d));
    }
  });

  test('labels 按偏移提供相对文案 —— 不变量 B 的契约', () {
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    final labels = s['labels']! as Map;
    expect(labels['today'], L10n.widgetToday);
    expect(labels['tomorrow'], L10n.widgetTomorrow);
    expect(labels['dayAfter'], L10n.widgetDayAfter);
    // 关键：这三个词**不在** days[] 里 —— 若有人把它们烘进 days[i]，
    // 跨天之后 days[i] 会自称「明天」。这条断言把「相对文案只在顶层」钉住。
    for (final word in [
      L10n.widgetToday,
      L10n.widgetTomorrow,
      L10n.widgetDayAfter,
    ]) {
      for (final d in s['days']! as List) {
        expect((d as Map).values, isNot(contains(word)));
      }
    }
  });

  test('todayCard 带出农历、其他班组、待办数，且不含我们班组', () {
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 3,
    );
    final tc = s['todayCard']! as Map;
    expect(tc['day'], dayNumber(DateTime(2026, 9, 18)));
    expect(tc['todoCount'], 3);
    expect(tc['todoBadge'], L10n.todoCount(3)); // todayTodoCount: 3 时
    expect(tc['lunarShort'], isA<String>());
    expect(tc['lunarShort'], isNotEmpty);
    expect(tc['lunarIsHoliday'], isA<bool>());
    expect(tc['adjusted'], false);

    // 其他班组：`_schedule()` 没设 teamCount/teamOffsets，走默认的 4 个班组、
    // ourTeamIndex=0，所以「其他班组」应当是 3 个，且名字里不含我们那个。
    final crews = (tc['crews']! as List).cast<Map>();
    expect(crews.length, 3);
    for (final c in crews) {
      expect(c['name'], isA<String>());
      expect(c['name'], isNotEmpty);
      expect(c['abbr'], isA<String>());
      expect(c['color'], isA<int>());
      expect(c['name'], isNot(crews.isEmpty ? '' : '一班'));
    }
  });

  test('班组数为 1 时 crews 是空数组（今日卡片会整块隐藏）', () {
    final solo = ShiftSchedule(
      name: '单人',
      anchorDate: DateTime.utc(2026, 9, 18),
      classes: const [
        ShiftClass(id: 11, name: '白班', abbr: '白', startMinute: 480, endMinute: 1200),
      ],
      cycle: const [0],
      teamCount: 1,
      teamNames: const ['我自己'],
      ourTeamIndex: 0,
      teamOffsets: const [0],
    );
    final s = buildWidgetSnapshot(
      schedule: solo,
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    expect((s['todayCard']! as Map)['crews'], isEmpty);
  });

  test('今天被按天改班覆盖时 adjusted 为 true', () {
    final s = buildWidgetSnapshot(
      // 9/18 在 3 天周期里是第 0 天 → 白班；覆盖成 classes[2]（休班）
      schedule: _schedule(overrides: {dayNumber(DateTime(2026, 9, 18)): 2}),
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    expect((s['todayCard']! as Map)['adjusted'], true);
  });

  test('没有待办时 todoBadge 为 null（原生据此隐藏徽章）', () {
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    expect((s['todayCard']! as Map)['todoBadge'], isNull);
  });
}
