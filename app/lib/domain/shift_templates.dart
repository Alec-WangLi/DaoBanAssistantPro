// 常见倒班方式模板 —— 纯 Dart 常量数据，无 Flutter 依赖，不入库。
//
// 模板只是一份「配方」：选中后生成的就是一个普通排班方案，
// 用户可以随意改，数据库里没有「模板」这个概念。
//
// 周期结构（几天一循环、每天几个班、几个班组错开）是模板要负责摆对的；
// 具体到几点几分各厂差异很大，这里只填常见值，用户可改。
//
// **两层结构**：`ShiftTemplateSpec` 是语言无关的结构与双语文案，
// `ShiftTemplate` 是读取期视图，按当前语言解析出 `String` 与 `ShiftClass`。
// 之所以要分这两层：班次名与简称会被**写进数据库**（方案建成后归用户），
// 必须在建的时候就是用户的语言；而 `shiftTemplates` 又必须是一次求值、
// 身份稳定的顶层列表（测试用 `same()` 比身份）。

import '../core/l10n.dart';
import 'shift_rotation.dart';

/// 班次在模板中的语义角色。
///
/// 名称与简称按当前语言生成；时间、颜色、闹钟、是否休息仍由原型自带。
///
/// 英文简称取**单字母**：日历格子宽度是按 1~2 个汉字设计的。
/// 「中班」译作 Afternoon（A）而不是 Mid —— 后者首字母 M 会与早班撞车。
enum ShiftRole { day, night, morning, afternoon, evening, duty, off, rest }

const _roleName = <ShiftRole, L10nText>{
  ShiftRole.day: L10nText('白班', 'Day shift'),
  ShiftRole.night: L10nText('夜班', 'Night shift'),
  ShiftRole.morning: L10nText('早班', 'Morning shift'),
  ShiftRole.afternoon: L10nText('中班', 'Afternoon shift'),
  ShiftRole.evening: L10nText('晚班', 'Evening shift'),
  ShiftRole.duty: L10nText('值班', 'Duty'),
  ShiftRole.off: L10nText('休班', 'Off'),
  ShiftRole.rest: L10nText('休息', 'Rest'),
};

const _roleAbbr = <ShiftRole, L10nText>{
  ShiftRole.day: L10nText('白', 'D'),
  ShiftRole.night: L10nText('夜', 'N'),
  ShiftRole.morning: L10nText('早', 'M'),
  ShiftRole.afternoon: L10nText('中', 'A'),
  ShiftRole.evening: L10nText('晚', 'E'),
  ShiftRole.duty: L10nText('值', 'D'),
  ShiftRole.off: L10nText('休', 'O'),
  ShiftRole.rest: L10nText('休', 'R'),
};

/// 班次原型：模板的结构部分。名称与简称由 [role] 按当前语言生成。
class ShiftClassProto {
  const ShiftClassProto({
    required this.role,
    this.startMinute,
    this.endMinute,
    this.isRest = false,
    required this.color,
    this.alarmEnabled = false,
    this.alarmMinute,
  });

  final ShiftRole role;
  final int? startMinute;
  final int? endMinute;
  final bool isRest;
  final int color;
  final bool alarmEnabled;
  final int? alarmMinute;

  ShiftClass toClass() => ShiftClass(
        name: _roleName[role]!.value,
        abbr: _roleAbbr[role]!.value,
        startMinute: startMinute,
        endMinute: endMinute,
        isRest: isRest,
        color: color,
        alarmEnabled: alarmEnabled,
        alarmMinute: alarmMinute,
      );
}

/// 模板的结构 + 双语文案（语言无关的常量）。
class ShiftTemplateSpec {
  const ShiftTemplateSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.aliases,
    required this.groupKey,
    required this.classes,
    required this.cycle,
    this.teamCount = 1,
    this.teamOffsets = const [0],
  });

  final String id;

  /// 人话主标题（给不懂术语的人看）。
  final L10nText title;

  /// 行话副标题（给会搜「四班三倒」的人看）。**同时是新建方案时的方案名**。
  final L10nText subtitle;

  /// 搜索词。中英关键词**都放** —— 搜索不该分语言，中文用户搜「四班三倒」、
  /// 英文用户搜 `4-crew` 都要能中。
  final List<String> aliases;

  /// 分组键（语言无关），显示名走 `L10n.templateGroup`。
  final String groupKey;

  /// 班次原型（结构 + 角色），名称在读取时按语言解析。
  final List<ShiftClassProto> classes;

  /// 周期序列（元素是 [classes] 的下标）。
  final List<int> cycle;

  final int teamCount;
  final List<int> teamOffsets;
}

/// 读取期的模板视图：把原型与双语文案解析成当前语言可直接使用的值。
///
/// 不持有语言状态 —— 所以 [shiftTemplates] 可以在顶层求值一次并长期复用，
/// 而它吐出来的文案始终跟着 `L10n.locale` 走。
class ShiftTemplate {
  const ShiftTemplate(this.spec);

  final ShiftTemplateSpec spec;

  String get id => spec.id;
  String get groupKey => spec.groupKey;
  String get title => spec.title.value;
  String get subtitle => spec.subtitle.value;
  List<String> get aliases => spec.aliases;
  List<ShiftClass> get classes =>
      spec.classes.map((p) => p.toClass()).toList(growable: false);
  List<int> get cycle => spec.cycle;
  int get cycleLength => cycle.length;
  int get teamCount => spec.teamCount;
  List<int> get teamOffsets => spec.teamOffsets;

  /// 每天同时在上班的班组数（轮转型模板应当每天都一样）。
  ///
  /// 读**原型**的 `isRest` —— 「是否休息」是结构字段，不走本地化；而且这个
  /// getter 每次 build 都被卡片调用，让它去分配一份临时的 [classes] 列表
  /// 是白白的开销。
  int get workingTeamsPerDay {
    var count = 0;
    for (var t = 0; t < spec.teamCount; t++) {
      final offset = t < spec.teamOffsets.length ? spec.teamOffsets[t] : t;
      final idx = offset % spec.cycle.length;
      if (idx < 0) continue;
      if (!spec.classes[spec.cycle[idx]].isRest) count++;
    }
    return count;
  }
}

/// 界面上分组的显示顺序（**语言无关键**，显示名走 `L10n.templateGroup`）。
///
/// 每个模板的 `groupKey` 必须落在这个列表里，否则它不会出现在选择页上，
/// 而且是静默消失 —— 由 `shift_template_picker_test.dart` 守着。
const shiftTemplateGroups = <String>[
  'h12',
  'h8',
  'h6',
  'duty',
  'office',
];

// ---------------------------------------------------------------------------
// 共用班次原型
// ---------------------------------------------------------------------------

// 12 小时制
const _d12 = ShiftClassProto(
    role: ShiftRole.day, startMinute: 8 * 60 + 30, endMinute: 20 * 60 + 30,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 7 * 60);
const _n12 = ShiftClassProto(
    role: ShiftRole.night, startMinute: 20 * 60 + 30, endMinute: 8 * 60 + 30,
    color: 0xFF7A5CFF, alarmEnabled: true, alarmMinute: 19 * 60);

// 8 小时制
const _e8 = ShiftClassProto(
    role: ShiftRole.morning, startMinute: 8 * 60, endMinute: 16 * 60,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 7 * 60);
const _m8 = ShiftClassProto(
    role: ShiftRole.afternoon, startMinute: 16 * 60, endMinute: 24 * 60,
    color: 0xFFFF9F0A, alarmEnabled: true, alarmMinute: 15 * 60);
const _n8 = ShiftClassProto(
    role: ShiftRole.night, startMinute: 0, endMinute: 8 * 60,
    color: 0xFF7A5CFF, alarmEnabled: true, alarmMinute: 23 * 60);

// 6 小时制
const _e6 = ShiftClassProto(
    role: ShiftRole.morning, startMinute: 6 * 60, endMinute: 12 * 60,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 5 * 60 + 30);
const _m6 = ShiftClassProto(
    role: ShiftRole.afternoon, startMinute: 12 * 60, endMinute: 18 * 60,
    color: 0xFFFF9F0A, alarmEnabled: true, alarmMinute: 11 * 60 + 30);
const _l6 = ShiftClassProto(
    role: ShiftRole.evening, startMinute: 18 * 60, endMinute: 24 * 60,
    color: 0xFF00C7BE, alarmEnabled: true, alarmMinute: 17 * 60 + 30);
const _n6 = ShiftClassProto(
    role: ShiftRole.night, startMinute: 0, endMinute: 6 * 60,
    color: 0xFF7A5CFF, alarmEnabled: true, alarmMinute: 23 * 60);

// 24 小时值班：08:00 → 次日 08:00（endMinute 跨过午夜继续累加）
const _duty = ShiftClassProto(
    role: ShiftRole.duty, startMinute: 8 * 60, endMinute: 32 * 60,
    color: 0xFFFF375F, alarmEnabled: true, alarmMinute: 7 * 60);

// 常白（与 12 小时制白班同名同色，仅时段不同 —— 故复用同一角色）
const _office = ShiftClassProto(
    role: ShiftRole.day, startMinute: 8 * 60 + 30, endMinute: 17 * 60 + 30,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 7 * 60 + 30);

// 休息
const _rest = ShiftClassProto(
    role: ShiftRole.off, isRest: true, color: 0xFF9AA0B4);
const _restGrey = ShiftClassProto(
    role: ShiftRole.rest, isRest: true, color: 0xFF5A5F73);

// ---------------------------------------------------------------------------
// 模板库
// ---------------------------------------------------------------------------

const List<ShiftTemplateSpec> shiftTemplateSpecs = [
  // -------- 12 小时制 --------
  ShiftTemplateSpec(
    id: 'day_night_rest_rest',
    title: L10nText('上一天白班、一天夜班，然后休两天', 'One day shift, one night shift, then two off'),
    subtitle: L10nText('白夜休休 · 四班两倒', 'Day-Night-Off-Off · 4-crew 2-shift'),
    aliases: ['白夜休休', '四班两倒', '4班2倒', '两班倒', 'day night off off', '4-crew', '2-shift'],
    groupKey: 'h12',
    classes: [_d12, _n12, _rest],
    cycle: [0, 1, 2, 2],
    teamCount: 4,
    teamOffsets: [0, 1, 2, 3],
  ),
  ShiftTemplateSpec(
    id: 'white_white_night_night_rest_rest',
    title: L10nText('白班两天、夜班两天，然后休两天', 'Two day shifts, two night shifts, then two off'),
    subtitle: L10nText('白白夜夜休休 · 三班两倒', '2 days, 2 nights, 2 off · 3-crew 2-shift'),
    aliases: ['白白夜夜休休', '三班两倒', '3班2倒', '2 day 2 night', '3-crew'],
    groupKey: 'h12',
    classes: [_d12, _n12, _rest],
    cycle: [0, 0, 1, 1, 2, 2],
    teamCount: 3,
    teamOffsets: [0, 2, 4],
  ),
  ShiftTemplateSpec(
    id: 'white_white_rest_rest_night_night_rest_rest',
    title: L10nText('上两天白班休两天，再上两天夜班休两天', 'Two days on, two off, then two nights on, two off'),
    subtitle: L10nText('白白休休夜夜休休', '2 day, 2 off, 2 night, 2 off'),
    aliases: ['白白休休夜夜休休', '四班两倒', '4-crew', '2 day 2 off'],
    groupKey: 'h12',
    classes: [_d12, _n12, _rest],
    cycle: [0, 0, 2, 2, 1, 1, 2, 2],
    teamCount: 4,
    teamOffsets: [0, 2, 4, 6],
  ),
  ShiftTemplateSpec(
    id: 'two_shift_weekly',
    title: L10nText('白班、夜班各上一整周，每周倒一次', 'A full week of days, then a full week of nights'),
    subtitle: L10nText('上 12 休 12 · 两班倒', '12 on, 12 off · 2-crew'),
    aliases: ['两班倒', '上12休12', '两班两倒', '一周一倒', '12 on 12 off', 'weekly rotation'],
    groupKey: 'h12',
    classes: [_d12, _n12],
    cycle: [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1],
    teamCount: 2,
    teamOffsets: [0, 7],
  ),
  ShiftTemplateSpec(
    id: 'dupont',
    title: L10nText('四夜三休、三白一休、三夜三休、四白，再连休七天',
        'DuPont rotation: 4 nights, 3 off, 3 days, 1 off, 3 nights, 3 off, 4 days, then 7 off'),
    subtitle: L10nText('DuPont · 28 天周期', 'DuPont · 28-day cycle'),
    aliases: ['dupont', '杜邦', '28天', '四班两倒', '28-day', '4-crew'],
    groupKey: 'h12',
    classes: [_d12, _n12, _rest],
    cycle: [
      1, 1, 1, 1, 2, 2, 2, 0, 0, 0, 2, 1, 1, 1,
      2, 2, 2, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2, 2,
    ],
    teamCount: 4,
    teamOffsets: [0, 7, 14, 21],
  ),

  // -------- 8 小时制 --------
  ShiftTemplateSpec(
    id: 'four_crew_three_shift',
    title: L10nText('早班两天、中班两天、夜班两天，然后休两天',
        'Two mornings, two afternoons, two nights, then two off'),
    subtitle: L10nText('四班三倒 · 四班三运转', '4-crew 3-shift'),
    aliases: ['四班三倒', '四班三运转', '早晚中', '8小时', '4-crew 3-shift', '8-hour'],
    groupKey: 'h8',
    classes: [_e8, _m8, _n8, _rest],
    cycle: [0, 0, 1, 1, 2, 2, 3, 3],
    teamCount: 4,
    teamOffsets: [0, 2, 4, 6],
  ),
  ShiftTemplateSpec(
    id: 'five_crew_three_shift',
    title: L10nText('早班、中班、夜班各一天，然后休两天', 'One morning, one afternoon, one night, then two off'),
    subtitle: L10nText('五班三倒', '5-crew 3-shift'),
    aliases: ['五班三倒', '5班3倒', '5-crew 3-shift', '8-hour'],
    groupKey: 'h8',
    classes: [_e8, _m8, _n8, _rest],
    cycle: [0, 1, 2, 3, 3],
    teamCount: 5,
    teamOffsets: [0, 1, 2, 3, 4],
  ),
  ShiftTemplateSpec(
    id: 'six_crew_three_shift',
    title: L10nText('上一天班休两天，早中夜轮着来', 'One shift on, two off — mornings, afternoons and nights in turn'),
    subtitle: L10nText('六班三倒', '6-crew 3-shift'),
    aliases: ['六班三倒', '6班3倒', '6-crew 3-shift', '8-hour'],
    groupKey: 'h8',
    classes: [_e8, _m8, _n8, _rest],
    cycle: [0, 3, 1, 3, 2, 3],
    teamCount: 6,
    teamOffsets: [0, 1, 2, 3, 4, 5],
  ),

  // -------- 6 小时制 --------
  ShiftTemplateSpec(
    id: 'five_crew_four_shift',
    title: L10nText('早中晚夜各一天，然后休一天', 'One morning, afternoon, evening and night each, then one off'),
    subtitle: L10nText('五班四倒', '5-crew 4-shift'),
    aliases: ['五班四倒', '5班4倒', '6小时', '5-crew 4-shift', '6-hour'],
    groupKey: 'h6',
    classes: [_e6, _m6, _l6, _n6, _rest],
    cycle: [0, 1, 2, 3, 4],
    teamCount: 5,
    teamOffsets: [0, 1, 2, 3, 4],
  ),
  ShiftTemplateSpec(
    id: 'six_crew_four_shift',
    title: L10nText('早中晚夜各一天，然后休两天', 'One morning, afternoon, evening and night each, then two off'),
    subtitle: L10nText('六班四倒', '6-crew 4-shift'),
    aliases: ['六班四倒', '6班4倒', '6-crew 4-shift', '6-hour'],
    groupKey: 'h6',
    classes: [_e6, _m6, _l6, _n6, _rest],
    cycle: [0, 1, 2, 3, 4, 4],
    teamCount: 6,
    teamOffsets: [0, 1, 2, 3, 4, 5],
  ),

  // -------- 值班制 --------
  ShiftTemplateSpec(
    id: 'duty_24_24',
    title: L10nText('上 24 小时，休 24 小时', '24 hours on, 24 hours off'),
    subtitle: L10nText('上 24 休 24', '24 on, 24 off'),
    aliases: ['上24休24', '24小时', '值班', '24 on 24 off', '24-hour duty'],
    groupKey: 'duty',
    classes: [_duty, _restGrey],
    cycle: [0, 1],
    teamCount: 2,
    teamOffsets: [0, 1],
  ),
  ShiftTemplateSpec(
    id: 'duty_24_48',
    title: L10nText('上 24 小时，休 48 小时', '24 hours on, 48 hours off'),
    subtitle: L10nText('上 24 休 48', '24 on, 48 off'),
    aliases: ['上24休48', '上1休2', '值班', '24 on 48 off', '1 on 2 off'],
    groupKey: 'duty',
    classes: [_duty, _restGrey],
    cycle: [0, 1, 1],
    teamCount: 3,
    teamOffsets: [0, 1, 2],
  ),
  ShiftTemplateSpec(
    id: 'duty_24_72',
    title: L10nText('上 24 小时，休 72 小时', '24 hours on, 72 hours off'),
    subtitle: L10nText('上 24 休 72', '24 on, 72 off'),
    aliases: ['上24休72', '上1休3', '值班', '24 on 72 off', '1 on 3 off'],
    groupKey: 'duty',
    classes: [_duty, _restGrey],
    cycle: [0, 1, 1, 1],
    teamCount: 4,
    teamOffsets: [0, 1, 2, 3],
  ),

  // -------- 常白 --------
  ShiftTemplateSpec(
    id: 'standard_week',
    title: L10nText('周一到周五上班，周末休息', 'Monday to Friday, weekends off'),
    subtitle: L10nText('长白班 · 双休', 'Standard week · two days off'),
    aliases: ['长白班', '行政班', '双休', '朝九晚五', '周末双休', 'weekdays', 'weekends off', '9 to 5'],
    groupKey: 'office',
    classes: [_office, _restGrey],
    cycle: [0, 0, 0, 0, 0, 1, 1],
  ),
  ShiftTemplateSpec(
    id: 'big_small_week',
    title: L10nText('这周休一天，下周休两天', 'One day off this week, two days off next'),
    subtitle: L10nText('大小周', 'Alternating weeks'),
    aliases: ['大小周', '大周小周', 'alternating weeks', 'big small week'],
    groupKey: 'office',
    classes: [_office, _restGrey],
    cycle: [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1],
  ),
  ShiftTemplateSpec(
    id: 'work_1_rest_1',
    title: L10nText('上一天休一天', 'One day on, one day off'),
    subtitle: L10nText('做一休一', '1 on, 1 off'),
    aliases: ['做一休一', '上一休一', '1 on 1 off'],
    groupKey: 'office',
    classes: [_d12, _rest],
    cycle: [0, 1],
  ),
  ShiftTemplateSpec(
    id: 'work_2_rest_2',
    title: L10nText('上两天休两天', 'Two days on, two days off'),
    subtitle: L10nText('做二休二', '2 on, 2 off'),
    aliases: ['做二休二', '上二休二', '2 on 2 off'],
    groupKey: 'office',
    classes: [_d12, _rest],
    cycle: [0, 0, 1, 1],
  ),
  ShiftTemplateSpec(
    id: 'work_4_rest_2',
    title: L10nText('上四天休两天', 'Four days on, two days off'),
    subtitle: L10nText('做四休二', '4 on, 2 off'),
    aliases: ['做四休二', '上四休二', '4 on 2 off'],
    groupKey: 'office',
    classes: [_d12, _rest],
    cycle: [0, 0, 0, 0, 1, 1],
  ),
  ShiftTemplateSpec(
    id: 'work_6_rest_1',
    title: L10nText('上六天休一天', 'Six days on, one day off'),
    subtitle: L10nText('做六休一', '6 on, 1 off'),
    aliases: ['做六休一', '上六休一', '单休', '6 on 1 off'],
    groupKey: 'office',
    classes: [_office, _restGrey],
    cycle: [0, 0, 0, 0, 0, 0, 1],
  ),
];

/// 模板列表：**一次求值、身份稳定**（测试用 `same()` 比较元素身份）。
///
/// 元素只持有 spec，不持有语言状态 —— 所以列表可以在顶层缓存，
/// 而 [ShiftTemplate.title] 之类的 getter 每次读取都跟着 `L10n.locale` 走。
final List<ShiftTemplate> shiftTemplates =
    shiftTemplateSpecs.map(ShiftTemplate.new).toList(growable: false);

ShiftTemplate? findTemplate(String id) {
  for (final t in shiftTemplates) {
    if (t.id == id) return t;
  }
  return null;
}
