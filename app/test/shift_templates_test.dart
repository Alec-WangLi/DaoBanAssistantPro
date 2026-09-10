import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';

void main() {
  test('模板库非空且 id 唯一', () {
    expect(shiftTemplates, isNotEmpty);
    final ids = shiftTemplates.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('每个模板结构自洽', () {
    for (final t in shiftTemplates) {
      final why = '模板 ${t.id}';
      expect(t.cycle, isNotEmpty, reason: why);
      expect(t.classes, isNotEmpty, reason: why);
      expect(t.teamCount, greaterThanOrEqualTo(1), reason: why);
      expect(t.teamOffsets.length, t.teamCount, reason: why);
      expect(t.title.trim(), isNotEmpty, reason: why);
      expect(t.subtitle.trim(), isNotEmpty, reason: why);
      expect(t.aliases, isNotEmpty, reason: why);
      for (final i in t.cycle) {
        expect(i, inInclusiveRange(0, t.classes.length - 1), reason: why);
      }
      for (final c in t.classes) {
        if (c.isRest) {
          expect(c.alarmEnabled, isFalse, reason: '$why：休息班次不该开联动闹钟');
        } else {
          expect(c.startMinute, isNotNull, reason: '$why：工作班次必须有时间');
          expect(c.endMinute, isNotNull, reason: '$why：工作班次必须有时间');
          expect(c.alarmMinute, isNotNull, reason: '$why：工作班次必须带建议闹钟');
        }
      }
    }
  });

  test('多班组模板每天上班组数恒定且符合预期', () {
    // 只有轮转型模板（班组数 > 1）才要求每天人数恒定；
    // 常白 / 做X休Y 是单人班表，人数本来就按天变化。
    const expected = <String, int>{
      'day_night_rest_rest': 2,
      'white_white_night_night_rest_rest': 2,
      'white_white_rest_rest_night_night_rest_rest': 2,
      'two_shift_weekly': 2,
      'dupont': 2,
      'four_crew_three_shift': 3,
      'five_crew_three_shift': 3,
      'six_crew_three_shift': 3,
      'five_crew_four_shift': 4,
      'six_crew_four_shift': 4,
      'duty_24_24': 1,
      'duty_24_48': 1,
      'duty_24_72': 1,
    };
    for (final t in shiftTemplates.where((t) => t.teamCount > 1)) {
      final want = expected[t.id];
      expect(want, isNotNull, reason: '模板 ${t.id} 缺预期上班组数');
      expect(t.workingTeamsPerDay, want, reason: '模板 ${t.id} 上班组数不符');
    }
  });

  test('findTemplate 能按 id 取到', () {
    expect(findTemplate('dupont')?.cycle.length, 28);
    expect(findTemplate('不存在'), isNull);
  });
}
