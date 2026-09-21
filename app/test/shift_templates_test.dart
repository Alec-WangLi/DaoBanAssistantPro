import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';

import 'support/cjk.dart';

/// 模板 → 一份可跑的 [ShiftSchedule]（基准日随便钉一天）。
///
/// 只为了能拿 `crewClashes` 去扫 —— 撞班与基准日无关（错位是常数偏移）。
ShiftSchedule _asSchedule(ShiftTemplate t) => ShiftSchedule(
      name: t.title,
      anchorDate: DateTime.utc(2026, 9, 21),
      classes: t.classes,
      cycle: t.cycle,
      teamCount: t.teamCount,
      teamOffsets: t.teamOffsets,
    );

/// 中文文案基线：重构前的实际取值，逐条抄自源码。
///
/// 模板双层化会重排数据，但用户看到的中文一个字都不该变；这张表是
/// 唯一能证明这件事的东西 —— 结构字段由「每个模板结构自洽」那条守着。
const _zhBaseline = <String, (String, String)>{
  'day_night_rest_rest': ('上一天白班、一天夜班，然后休两天', '白夜休休 · 四班两倒'),
  'white_white_night_night_rest_rest': ('白班两天、夜班两天，然后休两天', '白白夜夜休休 · 三班两倒'),
  'white_white_rest_rest_night_night_rest_rest':
      ('上两天白班休两天，再上两天夜班休两天', '白白休休夜夜休休'),
  'two_shift_weekly': ('白班、夜班各上一整周，每周倒一次', '上 12 休 12 · 两班倒'),
  'dupont': ('四夜三休、三白一休、三夜三休、四白，再连休七天', 'DuPont · 28 天周期'),
  'four_crew_three_shift': ('早班两天、中班两天、夜班两天，然后休两天', '四班三倒 · 四班三运转'),
  'five_crew_three_shift': ('早班、中班、夜班各一天，然后休两天', '五班三倒'),
  'five_crew_three_shift_10d': ('早班两天、中班两天、休一天、夜班两天，然后休三天', '五班三倒 · 10 天一轮'),
  'six_crew_three_shift': ('上一天班休两天，早中夜轮着来', '六班三倒'),
  'five_crew_four_shift': ('早中晚夜各一天，然后休一天', '五班四倒'),
  'six_crew_four_shift': ('早中晚夜各一天，然后休两天', '六班四倒'),
  'duty_24_24': ('上 24 小时，休 24 小时', '上 24 休 24'),
  'duty_24_48': ('上 24 小时，休 48 小时', '上 24 休 48'),
  'duty_24_72': ('上 24 小时，休 72 小时', '上 24 休 72'),
  'standard_week': ('周一到周五上班，周末休息', '长白班 · 双休'),
  'big_small_week': ('这周休一天，下周休两天', '大小周'),
  'work_1_rest_1': ('上一天休一天', '做一休一'),
  'work_2_rest_2': ('上两天休两天', '做二休二'),
  'work_4_rest_2': ('上四天休两天', '做四休二'),
  'work_6_rest_1': ('上六天休一天', '做六休一'),
};

/// 中文班次名与简称基线：按模板 id → 「角色名/简称」序列（与 classes 同序）。
const _zhClassBaseline = <String, List<String>>{
  'day_night_rest_rest': ['白班/白', '夜班/夜', '休班/休'],
  'white_white_night_night_rest_rest': ['白班/白', '夜班/夜', '休班/休'],
  'white_white_rest_rest_night_night_rest_rest': ['白班/白', '夜班/夜', '休班/休'],
  'two_shift_weekly': ['白班/白', '夜班/夜'],
  'dupont': ['白班/白', '夜班/夜', '休班/休'],
  'four_crew_three_shift': ['早班/早', '中班/中', '夜班/夜', '休班/休'],
  'five_crew_three_shift': ['早班/早', '中班/中', '夜班/夜', '休班/休'],
  'five_crew_three_shift_10d': ['早班/早', '中班/中', '夜班/夜', '休班/休'],
  'six_crew_three_shift': ['早班/早', '中班/中', '夜班/夜', '休班/休'],
  'five_crew_four_shift': ['早班/早', '中班/中', '晚班/晚', '夜班/夜', '休班/休'],
  'six_crew_four_shift': ['早班/早', '中班/中', '晚班/晚', '夜班/夜', '休班/休'],
  'duty_24_24': ['值班/值', '休息/休'],
  'duty_24_48': ['值班/值', '休息/休'],
  'duty_24_72': ['值班/值', '休息/休'],
  'standard_week': ['白班/白', '休息/休'],
  'big_small_week': ['白班/白', '休息/休'],
  'work_1_rest_1': ['白班/白', '休班/休'],
  'work_2_rest_2': ['白班/白', '休班/休'],
  'work_4_rest_2': ['白班/白', '休班/休'],
  'work_6_rest_1': ['白班/白', '休息/休'],
};

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
          expect(c.alarms, isNotEmpty, reason: '$why：工作班次必须带建议闹钟');
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
      'five_crew_three_shift_10d': 3,
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

  test('每个多班组模板：错位按周期均分、且没有两个班组撞班', () {
    // 这两条是**用户可见**的：错位没铺开（或铺开了但周期里有连排三天的班）
    // 就会出现「同一天两个班组上同一个班」——2026-09-21 有人把五班三倒改成
    // 10 天一轮之后正是这么撞的。「均分」这条规则就是从现有模板反推出来的，
    // 拿它反查模板，手抄错的错位当场就能发现。
    for (final t in shiftTemplates.where((t) => t.teamCount > 1)) {
      final why = '模板 ${t.id}';
      expect(evenTeamOffsets(t.cycleLength, t.teamCount), t.teamOffsets,
          reason: '$why 的错位不是按周期长度均分出来的');
      expect(crewClashes(_asSchedule(t)), isEmpty, reason: '$why 有班组撞班');
    }
  });

  test('findTemplate 能按 id 取到', () {
    expect(findTemplate('dupont')?.cycle.length, 28);
    expect(findTemplate('不存在'), isNull);
  });

  test('中文文案与班次名零回归（基线）', () {
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);
    L10n.locale = 'zh';

    expect(_zhBaseline.length, shiftTemplates.length,
        reason: '模板数量变了就该同步这张基线表');
    expect(_zhClassBaseline.length, shiftTemplates.length);

    for (final t in shiftTemplates) {
      final want = _zhBaseline[t.id]!;
      expect(t.title, want.$1, reason: '模板 ${t.id} 的中文主标题变了');
      expect(t.subtitle, want.$2, reason: '模板 ${t.id} 的中文副标题变了');
      expect(
        t.classes.map((c) => '${c.name}/${c.abbr}').toList(),
        _zhClassBaseline[t.id],
        reason: '模板 ${t.id} 的中文班次名或简称变了',
      );
    }
  });

  test('英文文案与班次名不含中文', () {
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);
    L10n.locale = 'en';

    for (final t in shiftTemplates) {
      final why = '模板 ${t.id}';
      expect(hasCjk(t.title), isFalse, reason: '$why 英文主标题含中文：${t.title}');
      expect(hasCjk(t.subtitle), isFalse,
          reason: '$why 英文副标题含中文：${t.subtitle}');
      for (final c in t.classes) {
        expect(hasCjk(c.name), isFalse, reason: '$why 英文班次名含中文：${c.name}');
        expect(hasCjk(c.abbr!), isFalse, reason: '$why 英文简称含中文：${c.abbr}');
      }
    }
  });

  test('中英文案都非空，别名中英都有', () {
    for (final t in shiftTemplates) {
      expect(t.spec.title.zh.trim(), isNotEmpty, reason: '模板 ${t.id} 中文主标题为空');
      expect(t.spec.title.en.trim(), isNotEmpty, reason: '模板 ${t.id} 英文主标题为空');
      expect(t.spec.subtitle.zh.trim(), isNotEmpty, reason: '模板 ${t.id} 中文副标题为空');
      expect(t.spec.subtitle.en.trim(), isNotEmpty, reason: '模板 ${t.id} 英文副标题为空');
      expect(t.aliases, isNotEmpty, reason: '模板 ${t.id} 没有搜索别名');
    }
  });

  test('英文副标题里没有残留的中文别名', () {
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);
    L10n.locale = 'en';
    // 别名是中英混收的，不参与本地化；这里只确认「别名表里确实有英文词」，
    // 否则英文用户搜什么都搜不到（模板 1~19 的英文关键词由 picker 测试守）。
    for (final t in shiftTemplates) {
      expect(t.aliases.any((a) => !hasCjk(a)), isTrue,
          reason: '模板 ${t.id} 的别名全是中文，英文用户搜不到它');
    }
  });

  // 内置模板的建议闹钟：加多闹钟那轮只把形状从「一个钟点」换成列表，**钟点一个
  // 都没动**（对照过改前那份 commit：11 处逐个一致）。这条把几个代表值钉住，
  // 免得以后顺手改模板时静默改掉用户的默认响铃时刻 —— 班次名跟着语言走，
  // 所以按**下标 / 上班时刻**取班次，不按名字。
  test('内置模板的建议闹钟钟点（代表值）', () {
    ShiftTemplate t(String id) => shiftTemplates.firstWhere((x) => x.id == id);

    // 12 小时制四班两倒：白班 07:00、夜班 19:00（夜班 20:30 上班 → 落在当天）
    final dn = t('day_night_rest_rest').classes;
    expect(dn[0].alarms.single.minute, 7 * 60);
    expect(dn[1].alarms.single.minute, 19 * 60);

    // 8 小时制三班倒：夜班 00:00 上班、23:00 响铃 —— **用户 v0.8.9 报的那一档**
    final eight = t('four_crew_three_shift').classes;
    expect(eight.firstWhere((c) => c.startMinute == 0).alarms.single.minute,
        23 * 60);
  });
}
