// 常见倒班方式模板 —— 纯 Dart 常量数据，无 Flutter 依赖，不入库。
//
// 模板只是一份「配方」：选中后生成的就是一个普通排班方案，
// 用户可以随意改，数据库里没有「模板」这个概念。
//
// 周期结构（几天一循环、每天几个班、几个班组错开）是模板要负责摆对的；
// 具体到几点几分各厂差异很大，这里只填常见值，用户可改。

import 'shift_rotation.dart';

class ShiftTemplate {
  const ShiftTemplate({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.aliases,
    required this.group,
    required this.classes,
    required this.cycle,
    this.teamCount = 1,
    this.teamOffsets = const [0],
  });

  final String id;

  /// 人话主标题（给不懂术语的人看）。
  final String title;

  /// 行话副标题（给会搜「四班三倒」的人看）。
  final String subtitle;

  /// 搜索词。
  final List<String> aliases;

  /// 分组：12 小时制 / 8 小时制 / 6 小时制 / 值班制 / 常白。
  final String group;

  /// 班次定义。
  final List<ShiftClass> classes;

  /// 周期序列（元素是 [classes] 的下标）。
  final List<int> cycle;

  final int teamCount;
  final List<int> teamOffsets;

  int get cycleLength => cycle.length;

  /// 每天同时在上班的班组数（轮转型模板应当每天都一样）。
  int get workingTeamsPerDay {
    var count = 0;
    for (var t = 0; t < teamCount; t++) {
      final offset = t < teamOffsets.length ? teamOffsets[t] : t;
      final idx = offset % cycle.length;
      if (idx < 0) continue;
      if (!classes[cycle[idx]].isRest) count++;
    }
    return count;
  }
}

/// 界面上分组的显示顺序。
const shiftTemplateGroups = <String>[
  '12 小时制',
  '8 小时制',
  '6 小时制',
  '值班制',
  '常白',
];

// ---------------------------------------------------------------------------
// 共用班次
// ---------------------------------------------------------------------------

// 12 小时制
const _d12 = ShiftClass(
    name: '白班', abbr: '白', startMinute: 8 * 60 + 30, endMinute: 20 * 60 + 30,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 7 * 60);
const _n12 = ShiftClass(
    name: '夜班', abbr: '夜', startMinute: 20 * 60 + 30, endMinute: 8 * 60 + 30,
    color: 0xFF7A5CFF, alarmEnabled: true, alarmMinute: 19 * 60);

// 8 小时制
const _e8 = ShiftClass(
    name: '早班', abbr: '早', startMinute: 8 * 60, endMinute: 16 * 60,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 7 * 60);
const _m8 = ShiftClass(
    name: '中班', abbr: '中', startMinute: 16 * 60, endMinute: 24 * 60,
    color: 0xFFFF9F0A, alarmEnabled: true, alarmMinute: 15 * 60);
const _n8 = ShiftClass(
    name: '夜班', abbr: '夜', startMinute: 0, endMinute: 8 * 60,
    color: 0xFF7A5CFF, alarmEnabled: true, alarmMinute: 23 * 60);

// 6 小时制
const _e6 = ShiftClass(
    name: '早班', abbr: '早', startMinute: 6 * 60, endMinute: 12 * 60,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 5 * 60 + 30);
const _m6 = ShiftClass(
    name: '中班', abbr: '中', startMinute: 12 * 60, endMinute: 18 * 60,
    color: 0xFFFF9F0A, alarmEnabled: true, alarmMinute: 11 * 60 + 30);
const _l6 = ShiftClass(
    name: '晚班', abbr: '晚', startMinute: 18 * 60, endMinute: 24 * 60,
    color: 0xFF00C7BE, alarmEnabled: true, alarmMinute: 17 * 60 + 30);
const _n6 = ShiftClass(
    name: '夜班', abbr: '夜', startMinute: 0, endMinute: 6 * 60,
    color: 0xFF7A5CFF, alarmEnabled: true, alarmMinute: 23 * 60);

// 24 小时值班：08:00 → 次日 08:00（endMinute 跨过午夜继续累加）
const _duty = ShiftClass(
    name: '值班', abbr: '值', startMinute: 8 * 60, endMinute: 32 * 60,
    color: 0xFFFF375F, alarmEnabled: true, alarmMinute: 7 * 60);

// 常白
const _office = ShiftClass(
    name: '白班', abbr: '白', startMinute: 8 * 60 + 30, endMinute: 17 * 60 + 30,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 7 * 60 + 30);

// 休息
const _rest = ShiftClass(name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4);
const _restGrey =
    ShiftClass(name: '休息', abbr: '休', isRest: true, color: 0xFF5A5F73);

// ---------------------------------------------------------------------------
// 模板库
// ---------------------------------------------------------------------------

final List<ShiftTemplate> shiftTemplates = [
  // -------- 12 小时制 --------
  const ShiftTemplate(
    id: 'day_night_rest_rest',
    title: '上一天白班、一天夜班，然后休两天',
    subtitle: '白夜休休 · 四班两倒',
    aliases: ['白夜休休', '四班两倒', '4班2倒', '两班倒'],
    group: '12 小时制',
    classes: [_d12, _n12, _rest],
    cycle: [0, 1, 2, 2],
    teamCount: 4,
    teamOffsets: [0, 1, 2, 3],
  ),
  const ShiftTemplate(
    id: 'white_white_night_night_rest_rest',
    title: '白班两天、夜班两天，然后休两天',
    subtitle: '白白夜夜休休 · 三班两倒',
    aliases: ['白白夜夜休休', '三班两倒', '3班2倒'],
    group: '12 小时制',
    classes: [_d12, _n12, _rest],
    cycle: [0, 0, 1, 1, 2, 2],
    teamCount: 3,
    teamOffsets: [0, 2, 4],
  ),
  const ShiftTemplate(
    id: 'white_white_rest_rest_night_night_rest_rest',
    title: '上两天白班休两天，再上两天夜班休两天',
    subtitle: '白白休休夜夜休休',
    aliases: ['白白休休夜夜休休', '四班两倒'],
    group: '12 小时制',
    classes: [_d12, _n12, _rest],
    cycle: [0, 0, 2, 2, 1, 1, 2, 2],
    teamCount: 4,
    teamOffsets: [0, 2, 4, 6],
  ),
  const ShiftTemplate(
    id: 'two_shift_weekly',
    title: '白班、夜班各上一整周，每周倒一次',
    subtitle: '上 12 休 12 · 两班倒',
    aliases: ['两班倒', '上12休12', '两班两倒', '一周一倒'],
    group: '12 小时制',
    classes: [_d12, _n12],
    cycle: [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1],
    teamCount: 2,
    teamOffsets: [0, 7],
  ),
  const ShiftTemplate(
    id: 'dupont',
    title: '四夜三休、三白一休、三夜三休、四白，再连休七天',
    subtitle: 'DuPont · 28 天周期',
    aliases: ['dupont', '杜邦', '28天', '四班两倒'],
    group: '12 小时制',
    classes: [_d12, _n12, _rest],
    cycle: [
      1, 1, 1, 1, 2, 2, 2, 0, 0, 0, 2, 1, 1, 1,
      2, 2, 2, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2, 2,
    ],
    teamCount: 4,
    teamOffsets: [0, 7, 14, 21],
  ),

  // -------- 8 小时制 --------
  const ShiftTemplate(
    id: 'four_crew_three_shift',
    title: '早班两天、中班两天、夜班两天，然后休两天',
    subtitle: '四班三倒 · 四班三运转',
    aliases: ['四班三倒', '四班三运转', '早晚中', '8小时'],
    group: '8 小时制',
    classes: [_e8, _m8, _n8, _rest],
    cycle: [0, 0, 1, 1, 2, 2, 3, 3],
    teamCount: 4,
    teamOffsets: [0, 2, 4, 6],
  ),
  const ShiftTemplate(
    id: 'five_crew_three_shift',
    title: '早班、中班、夜班各一天，然后休两天',
    subtitle: '五班三倒',
    aliases: ['五班三倒', '5班3倒'],
    group: '8 小时制',
    classes: [_e8, _m8, _n8, _rest],
    cycle: [0, 1, 2, 3, 3],
    teamCount: 5,
    teamOffsets: [0, 1, 2, 3, 4],
  ),
  const ShiftTemplate(
    id: 'six_crew_three_shift',
    title: '上一天班休两天，早中夜轮着来',
    subtitle: '六班三倒',
    aliases: ['六班三倒', '6班3倒'],
    group: '8 小时制',
    classes: [_e8, _m8, _n8, _rest],
    cycle: [0, 3, 1, 3, 2, 3],
    teamCount: 6,
    teamOffsets: [0, 1, 2, 3, 4, 5],
  ),

  // -------- 6 小时制 --------
  const ShiftTemplate(
    id: 'five_crew_four_shift',
    title: '早中晚夜各一天，然后休一天',
    subtitle: '五班四倒',
    aliases: ['五班四倒', '5班4倒', '6小时'],
    group: '6 小时制',
    classes: [_e6, _m6, _l6, _n6, _rest],
    cycle: [0, 1, 2, 3, 4],
    teamCount: 5,
    teamOffsets: [0, 1, 2, 3, 4],
  ),
  const ShiftTemplate(
    id: 'six_crew_four_shift',
    title: '早中晚夜各一天，然后休两天',
    subtitle: '六班四倒',
    aliases: ['六班四倒', '6班4倒'],
    group: '6 小时制',
    classes: [_e6, _m6, _l6, _n6, _rest],
    cycle: [0, 1, 2, 3, 4, 4],
    teamCount: 6,
    teamOffsets: [0, 1, 2, 3, 4, 5],
  ),

  // -------- 值班制 --------
  const ShiftTemplate(
    id: 'duty_24_24',
    title: '上 24 小时，休 24 小时',
    subtitle: '上 24 休 24',
    aliases: ['上24休24', '24小时', '值班'],
    group: '值班制',
    classes: [_duty, _restGrey],
    cycle: [0, 1],
    teamCount: 2,
    teamOffsets: [0, 1],
  ),
  const ShiftTemplate(
    id: 'duty_24_48',
    title: '上 24 小时，休 48 小时',
    subtitle: '上 24 休 48',
    aliases: ['上24休48', '上1休2', '值班'],
    group: '值班制',
    classes: [_duty, _restGrey],
    cycle: [0, 1, 1],
    teamCount: 3,
    teamOffsets: [0, 1, 2],
  ),
  const ShiftTemplate(
    id: 'duty_24_72',
    title: '上 24 小时，休 72 小时',
    subtitle: '上 24 休 72',
    aliases: ['上24休72', '上1休3', '值班'],
    group: '值班制',
    classes: [_duty, _restGrey],
    cycle: [0, 1, 1, 1],
    teamCount: 4,
    teamOffsets: [0, 1, 2, 3],
  ),

  // -------- 常白 --------
  const ShiftTemplate(
    id: 'standard_week',
    title: '周一到周五上班，周末休息',
    subtitle: '长白班 · 双休',
    aliases: ['长白班', '行政班', '双休', '朝九晚五', '周末双休'],
    group: '常白',
    classes: [_office, _restGrey],
    cycle: [0, 0, 0, 0, 0, 1, 1],
  ),
  const ShiftTemplate(
    id: 'big_small_week',
    title: '这周休一天，下周休两天',
    subtitle: '大小周',
    aliases: ['大小周', '大周小周'],
    group: '常白',
    classes: [_office, _restGrey],
    cycle: [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1],
  ),
  const ShiftTemplate(
    id: 'work_1_rest_1',
    title: '上一天休一天',
    subtitle: '做一休一',
    aliases: ['做一休一', '上一休一'],
    group: '常白',
    classes: [_d12, _rest],
    cycle: [0, 1],
  ),
  const ShiftTemplate(
    id: 'work_2_rest_2',
    title: '上两天休两天',
    subtitle: '做二休二',
    aliases: ['做二休二', '上二休二'],
    group: '常白',
    classes: [_d12, _rest],
    cycle: [0, 0, 1, 1],
  ),
  const ShiftTemplate(
    id: 'work_4_rest_2',
    title: '上四天休两天',
    subtitle: '做四休二',
    aliases: ['做四休二', '上四休二'],
    group: '常白',
    classes: [_d12, _rest],
    cycle: [0, 0, 0, 0, 1, 1],
  ),
  const ShiftTemplate(
    id: 'work_6_rest_1',
    title: '上六天休一天',
    subtitle: '做六休一',
    aliases: ['做六休一', '上六休一', '单休'],
    group: '常白',
    classes: [_office, _restGrey],
    cycle: [0, 0, 0, 0, 0, 0, 1],
  ),
];

ShiftTemplate? findTemplate(String id) {
  for (final t in shiftTemplates) {
    if (t.id == id) return t;
  }
  return null;
}
