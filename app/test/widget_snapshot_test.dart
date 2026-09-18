// 桌面小组件快照 —— 纯函数 `buildWidgetSnapshot`。
//
// 为什么这一层值得单独测：整个小组件的正确性都压在它身上。原生侧只是个排版器
// （Kotlin 里一个中文字符串都没有），所以「今天/明天对不对」「跨午夜班次的时间串
// 对不对」「14 天窗口够不够」这些判断一旦错了，真机上表现为「卡片显示别的班的
// 时间」，而且不报错。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/widget/widget_service.dart';
import 'package:shiftassistantpro/features/widget/widget_snapshot.dart';

/// 与 `shift_alarm_decision_test.dart` 同款：班次名写死，用例断言**结构**不论文案。
ShiftSchedule _schedule() => ShiftSchedule(
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
    );

void main() {
  // `L10n.monthDay` 走 `DateFormat(..., 'zh'|'en')`，两种语言的 locale 数据都
  // 要先装好（英文那条用例会在 locale='en' 下生成快照）—— 与
  // `glass_pickers_layout_test.dart` / `shift_template_picker_test.dart` 同款。
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
  });

  setUp(() => L10n.locale = 'zh');

  test('days 恒 14 条，day 逐日递增', () {
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
    );
    final days = s['days']! as List;
    expect(days.length, 14);
    for (var i = 0; i < 14; i++) {
      expect((days[i] as Map)['day'], dayNumber(DateTime(2026, 9, 18 + i)));
    }
  });

  test('空白表（schedule=null）仍产出 14 条空行，并带上空表提示', () {
    final s = buildWidgetSnapshot(
      schedule: null,
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'light',
      accent: 0xFF4F5BE8,
    );
    expect(s['hasSchedule'], false);
    expect(s['emptyHint'], L10n.widgetEmptyHint);
    final days = s['days']! as List;
    expect(days.length, 14);
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
    );
    final d0 = (s['days']! as List).first as Map;
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
    );
    final d0 = (s['days']! as List).first as Map;
    expect((d0['timeRange']! as String).contains('次日'), false);
    expect(d0['timeRange'], '20:30 – 08:30 (next day)');
  });

  test('休班行没有时间串', () {
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: DateTime(2026, 9, 20, 10), // 周期第 2 天 → 休班
      themeMode: 'system',
      accent: 0xFF4F5BE8,
    );
    final d0 = (s['days']! as List).first as Map;
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
    );
    final b = (s['boundaries']! as List).cast<int>();
    expect(b, isNotEmpty);
    for (var i = 1; i < b.length; i++) {
      expect(b[i] > b[i - 1], true, reason: '必须严格递增（已去重）');
    }
    for (final t in b) {
      expect(t > now.millisecondsSinceEpoch, true);
    }
    // 每天都贡献了一个本地零点：14 天里未来还剩 13 个（今天的那个已过）。
    expect(b.where((t) => t > now.millisecondsSinceEpoch).length >= 13, true);
  });

  test('主题模式原样透传，不在这里解析成 light/dark', () {
    for (final mode in ['system', 'light', 'dark']) {
      final s = buildWidgetSnapshot(
        schedule: _schedule(),
        now: DateTime(2026, 9, 18, 10),
        themeMode: mode,
        accent: 0xFF4F5BE8,
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
    );
    final back = jsonDecode(jsonEncode(s)) as Map<String, dynamic>;
    expect(back['v'], kWidgetSnapshotVersion);
    expect(back['days'], hasLength(14));
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
}
