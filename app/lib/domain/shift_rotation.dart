// 排班轮换引擎 —— 纯 Dart，无 Flutter 依赖，可直接 dart test。
//
// 两层模型：
//   classes —— 班次定义（白班/上夜班/休班…），一个班次只定义一次
//   cycle   —— 周期序列，长度即周期，元素是 classes 的下标
//
// 核心公式：
//   某班组某天的班次 = classes[ cycle[ (目标日 − 基准日 + 班组偏移) mod 周期 ] ]

import 'package:characters/characters.dart';

// `defaultSchedule()` 的文案要按当前语言生成。`l10n.dart` 只依赖 intl
// （纯 Dart），所以本文件「无 Flutter 依赖、可直接 dart test」的性质不变。
import '../core/l10n.dart';
import 'monthly_pattern.dart';

/// 小时+分钟 → 分钟自午夜（0..1439）。
int toMinutes(int hour, int minute) => hour * 60 + minute;

/// 两个日期之间的"整日"差，用 UTC 日期整数计算，规避时区/夏令时。
int daysBetween(DateTime a, DateTime b) {
  final da = DateTime.utc(a.year, a.month, a.day);
  final db = DateTime.utc(b.year, b.month, b.day);
  return db.difference(da).inDays;
}

/// 取 UTC 的"纯日期"（时间归零）。
DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// 某天是当月的第几天（1..31）—— 按月切法的入参。
///
/// 走 [dateOnly] 而不是裸的 `date.day`：与全仓「日期比较一律走 dayNumber /
/// dateOnly」同一条纪律。透进来的日子可能是 UTC 纯日期、也可能带本地时分，
/// 统一归零之后取日号，两种都对。
int dayOfMonth(DateTime date) => dateOnly(date).day;

/// 两个 DateTime 是不是同一天。
///
/// **不能写成 `a == b`**：`DateTime.==` 连 `isUtc` 一起比，而 [dateOnly] 给的是
/// UTC 日期、日历网格里逐格构造的是本地日期 —— 同一天也会判成不等。日历上
/// 「今天加粗」与「选中那格的胶囊实心」都靠这个判断，用 `==` 会静默失效
/// （网格里的「今天」因此从来没加粗过）。
bool isSameDay(DateTime a, DateTime b) => daysBetween(a, b) == 0;

/// 纯日期 → 自 epoch 的天数（按天闹钟覆盖表的主键）。
int dayNumber(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  return d.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

/// 分钟数 → `HH:mm`，供日历与编辑器共用。1440 恰好显示为 `24:00`。
///
/// [minutes] 可以超过 1440（跨过午夜后继续累加），调用方负责先减掉 1440
/// 并自行补「次日」前缀。
String formatClock(int minutes) {
  if (minutes == 1440) return '24:00';
  final m = minutes % 1440;
  final h = (m ~/ 60).toString().padLeft(2, '0');
  return '$h:${(m % 60).toString().padLeft(2, '0')}';
}

/// 一个班次上的**一条**联动闹钟。
///
/// [minute] 是钟面值（0..1439，分钟自午夜）。[label] 是可选名字（「起床」「午休」），
/// 为空时响铃标题退回「白班提醒」。名字的空白由**输入侧**（编辑器）负责 trim，
/// 值类型本身不做归一化 —— 它是纯数据，跟库里存的一致。
class ShiftAlarm {
  const ShiftAlarm({required this.minute, this.label});

  final int minute;
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is ShiftAlarm && other.minute == minute && other.label == label;

  @override
  int get hashCode => Object.hash(minute, label);

  @override
  String toString() => 'ShiftAlarm($minute${label == null ? '' : ', $label'})';
}

/// 一个班次最多挂几个联动闹钟。
///
/// **不是产品口味，是原生 id 空间的硬上限**：原生 id 是
/// `序号 × 天数窗口 + 天数偏移`（见 `alarm_service.dart` 的 `_shiftDaysHorizon`），
/// Kotlin 侧 `cancelAllNativeAlarms` / `cancelAllNotificationAlarms` 扫的是
/// `0..600`（`MainActivity.kt:604` 与 `:620`）。
/// 10 × 60 = 600 ≤ 600 刚好放得下。**改这个数或改天数窗口，必须同时改另一边。**
const int maxAlarmsPerShift = 10;

/// 一条闹钟的钟点落在**班次当天那一圈钟点**的哪一边。
enum AlarmDayAnchor {
  /// 班次**前一天**的那个钟点。
  prev,

  /// **班次当天**。
  same,

  /// 班次**次日**的那个钟点。
  next,
}

/// 某条闹钟落在**前一天 / 班次当天 / 次日**的哪一档。
///
/// 规则（spec `2026-10-11-shift-alarm-anchor-and-cap-design.md` §3）：
///   ① 钟点落在**值班窗口内** → 窗口里那一次**出现**所在的那一天。窗口跨过午夜
///      时，落在午夜之后那一段的出现在**次日** —— 16:30–次日 00:30 的 00:15
///      就是它（从前被静默排到班次当天凌晨，比上班早 16 小时）。
///   ② 否则钟点**晚于上班钟点** → **前一天**。00:00 上班、23:00 响铃排前一天的
///      23:00 —— 排在班次当天就已经是班后 15 小时。**这是 v0.8.9 立起来的既有
///      约定，这一版不动它。**
///   ③ 否则 → **当天与次日里离窗口更近的那一个**。这就是「下班之后的闹钟」：
///      16:30–次日 00:30 的 01:00 落在**次日** 01:00（从前落在上班前 15 个半小时）。
///      两边一样近时取**当天**。
///
/// **窗口长到一整天时（24 小时值班，`span == 1440`）一律算当天**：那时候任何钟点
/// 都落在窗口内，「上班之前」与「班次之中」在模型上已经合并（既有行为就是「全天
/// 都算当天」，内置的 `duty_24_24/48/72` 三个模板靠它维持原样）。没有这一条，
/// 那些模板配的 07:00 上班提醒会被第 ① 档判成次日 —— 从「上班前 1 小时」变成
/// 「下班前 1 小时」。护栏是 `shift_rotation_test` 的「24 小时值班：全天都算当天」
/// 与 `shift_templates_test` 的模板差集用例。
///
/// 时间没填：上班没填 → 判不了，按当天（不瞎挪一天）；下班没填 → 窗口算不出，
/// 退回两档（只按上班钟点判），**永远不会是次日**。
AlarmDayAnchor alarmDayAnchor(ShiftClass shift, ShiftAlarm alarm) {
  final s = shift.startMinute;
  if (s == null) return AlarmDayAnchor.same;
  final t = alarm.minute;
  final e = shift.endMinute;
  if (e == null) return t > s ? AlarmDayAnchor.prev : AlarmDayAnchor.same;
  // 值班时长。**班次有两种存法**：累计式（24 小时值班 480 → 1920）与回绕式
  // （夜班 20:30 → 08:30 存成 510 < 1230 —— 内置 12 小时制模板与编辑器产出的
  // 都是这一种）。所以要补一天再减：直接 `e - s` 在回绕式下**是负的**，窗口
  // 判据会静默失效、班中闹钟又回到前一天（独立审查抓出来的；`shift_rotation_test`
  // 里「回绕式存法的跨午夜班」与「两种存法同解」两条是它的护栏）。
  final span = e > s ? e - s : e - s + _dayMinutes;
  if (span >= _dayMinutes) return AlarmDayAnchor.same; // 24 小时值班：见上
  // `rel` = 钟点 t 在上班之后**最近那一次**出现距上班多少分钟。
  final rel = ((t - s) % _dayMinutes + _dayMinutes) % _dayMinutes;
  if (rel < span) {
    // 窗口内：那一次出现在 `s + rel`。跨过午夜就是次日。
    return s + rel >= _dayMinutes ? AlarmDayAnchor.next : AlarmDayAnchor.same;
  }
  if (t > s) return AlarmDayAnchor.prev;
  final before = s - t; // 当天那一次落在窗口**之前**多远
  final after = t + _dayMinutes - (s + span); // 次日那一次落在窗口**之后**多远
  return after < before ? AlarmDayAnchor.next : AlarmDayAnchor.same;
}

const int _dayMinutes = 1440;

/// 两个闹钟列表逐条相等（本文件不引 Flutter，拿不到 `listEquals`）。
bool _sameAlarms(List<ShiftAlarm> a, List<ShiftAlarm> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 班次定义：一个班次只定义一次，周期里的每一天引用它。
class ShiftClass {
  const ShiftClass({
    this.id,
    required this.name,
    this.abbr,
    this.startMinute,
    this.endMinute,
    this.isRest = false,
    this.color = 0xFF5B7FFF,
    this.alarmEnabled = false,
    this.alarms = const [],
  });

  /// 库里的行 id；null = 还没落库的新班次。
  ///
  /// **这个字段是「按天改班」能成立的前提**：覆盖表引用的是班次定义，而
  /// `saveSchedule` 从前每次保存都把班次行删光重建、id 全变 —— 有了稳定 id，
  /// 覆盖才指得住（spec §4）。
  final int? id;

  /// 班次名（自由文本），如 白班 / 上夜班 / 下夜班 / 大休。
  final String name;

  /// 日历格子里的 1~2 字简称；为空时按 [name] 推断。
  final String? abbr;

  /// 工作开始时间（分钟自开始日午夜）。
  final int? startMinute;

  /// 工作结束时间（分钟自开始日午夜）；跨过午夜后继续累加，
  /// 因此 24 小时班的值班是 480 → 1920（08:00 → 次日 08:00）。
  final int? endMinute;

  /// 是否休息日（不响联动闹钟）。
  final bool isRest;

  /// 日历格子的 ARGB 颜色。
  final int color;

  /// 联动闹钟总开关：关掉**不清空** [alarms]（用户手滑关一下不该丢配置）。
  final bool alarmEnabled;

  /// 这个班次的联动闹钟（有序）。
  ///
  /// **顺序就是原生 id 里的「序号」**（见 `alarm_service.dart` 的 `_shiftDaysHorizon`）——
  /// 所以用户在编辑页里调整顺序会让闹钟换号（可接受：编辑之后必然重排、`cancelAll`
  /// 先跑），但**重排本身绝不能重新编号**。上限 [maxAlarmsPerShift]。
  final List<ShiftAlarm> alarms;

  /// 工作窗口是否跨过午夜。
  bool get crossesMidnight {
    final s = startMinute, e = endMinute;
    if (s == null || e == null) return false;
    return e < s || e > 1440;
  }

  /// 结束时间的钟面值（0..1439）；跨到次日时已减掉 1440。
  int? get endClockMinute => endMinute == null ? null : endMinute! % 1440;

  /// 结束时间是否落在次日（含 24:00 与 24 小时班）。
  bool get endsNextDay {
    final s = startMinute, e = endMinute;
    if (s == null || e == null) return false;
    return e >= 1440 || e < s;
  }

  /// 日历格子显示的简称：优先用 [abbr]，为空时按名称推断。
  ///
  /// 用 `characters.first`（整字素簇）而不是 `substring(0, 1)`：
  /// 后者会把 emoji 等增补平面字符切成半个代理对，旧代码用的就是前者。
  String get shortLabel {
    final a = abbr?.trim();
    if (a != null && a.isNotEmpty) return a;
    if (isRest) return '休';
    if (name.contains('白') || name.contains('早')) return '白';
    if (name.contains('夜')) return '夜';
    return name.isEmpty ? '·' : name.characters.first;
  }

  ShiftClass copyWith({
    int? id,
    String? name,
    String? abbr,
    int? startMinute,
    int? endMinute,
    bool? isRest,
    int? color,
    bool? alarmEnabled,
    List<ShiftAlarm>? alarms,
  }) {
    return ShiftClass(
      id: id ?? this.id,
      name: name ?? this.name,
      abbr: abbr ?? this.abbr,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      isRest: isRest ?? this.isRest,
      color: color ?? this.color,
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      alarms: alarms ?? this.alarms,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShiftClass &&
      other.id == id &&
      other.name == name &&
      other.abbr == abbr &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute &&
      other.isRest == isRest &&
      other.color == color &&
      other.alarmEnabled == alarmEnabled &&
      _sameAlarms(other.alarms, alarms);

  @override
  int get hashCode => Object.hash(id, name, abbr, startMinute, endMinute,
      isRest, color, alarmEnabled, Object.hashAll(alarms));

  @override
  String toString() => 'ShiftClass($name, rest=$isRest)';
}

/// 「某天什么班」的**唯一**查询面 —— 日历、闹钟、桌面小组件都只依赖它。
///
/// 抽出来是为了让「单套方案」与「按天衔接的多套方案」（`ScheduleChain`，
/// 见 `schedule_chain.dart`）在调用点**无法区分**：`planShiftAlarms` /
/// `AlarmService.reschedule` 从前收的是 `ShiftSchedule`，改成收这个接口之后
/// 传哪一边都对，而调用点拿到的就是「一个能回答某天什么班的东西」。
abstract class ShiftSource {
  /// 某天的班次；那天没有班次（空白表 / 无方案）返回 null。
  ShiftClass? shiftOn(DateTime date);

  /// 日志用的一行描述。**不是用户可见文案**（Kotlin 的日志串本来就是中文，
  /// 仓库既有惯例）。
  String get label;
}

/// 一套排班方案（班次定义 + 轮换规则 + 多班组）。
///
/// **两种锚定方式，由 [monthly] 二选一**（spec §3.5）：
///   · `monthly == false`（默认）—— **连续周期**：离 [anchorDate] 多少天 mod [cycle]
///     长度。`cycle` 是唯一的规则来源。
///   · `monthly == true` —— **按月归零**：[monthlySegments] 是「每月的第 N 天起换成
///     哪个班次」，每月 1 号必然落在第一段。`cycle` 在这条路上**不被读取**。
///
/// ⚠️ **[monthly] 是这个模式唯一的判据。** 别用 `monthlySegments.isEmpty` 或
/// `cycle.isEmpty` 去猜当前是哪种模式 —— 因为「切换模式不丢数据」这条约定决定了
/// **两边可以同时非空**（用户切到按月、又切回按周期之后，段表还留在库里而
/// `monthly == false`）。拿数据去猜的后果是日历**无视用户的选择**继续按月算，
/// 不报错、只在月份边界上错一天。
class ShiftSchedule implements ShiftSource {
  const ShiftSchedule({
    required this.name,
    required this.anchorDate,
    required this.classes,
    required this.cycle,
    this.teamCount = 4,
    this.teamNames = const ['一班', '二班', '三班', '四班'],
    this.ourTeamIndex = 0,
    this.teamOffsets = const [],
    this.dayOverrides = const {},
    this.monthly = false,
    this.monthlySegments = const [],
    this.teamSegOffsets = const [],
  });

  /// 空白表（跟随法定节假日）：**当前这一边**没有内容。
  ///
  /// 不能写成「两边都空」也不能只看 `cycle`：按月模式下周期本来就是空的，那样
  /// 每一套按月方案都会被当成空白表 —— 日历整月不画胶囊、桌面小组件写「还没有排班」。
  bool get isBlank => monthly ? monthlySegments.isEmpty : cycle.isEmpty;

  final String name;

  /// 基准日：各班组在此日期的周期位置由 [teamOffsets] 显式指定。
  ///
  /// **按月模式不读它**（按月不用基准日，1 号恒等于第一段）。它仍在，因为库里
  /// 那一列不是可空的 —— 那套方案的基准日原样留着，切回周期模式就用得上。
  final DateTime anchorDate;

  /// 班次定义。
  final List<ShiftClass> classes;

  /// 周期序列：长度即周期，元素是 [classes] 的下标。
  ///
  /// **按月模式下不读它**（见 [monthly]）。切换模式时两边各存各的，所以它不会
  /// 因为切到按月就被清掉。
  final List<int> cycle;

  /// 按月切法：一段 = 「每月的第 N 天起 → 某个班次」，第一段恒从 1 起。
  ///
  /// 只在 [monthly] 为真时生效。设了它的方案**同时**可以留着 [cycle] —— 那是
  /// 「切回去不丢数据」这条约定的代价，判据一律看 [monthly]。
  final List<MonthlySegment> monthlySegments;

  /// 各班组在**按月切法里的段偏移**（长度与 [teamCount] 一致）。
  ///
  /// **单位是「段」，不是天** —— 这正是它与 [teamOffsets] 分开成两个字段的原因：
  /// 同一个列里让单位的含义随模式变，是读代码的人要先去别处查标志位才知道自己
  /// 读到什么的那类静默错误。按月模式下组 i 在某天的班次 = 段序列**旋转**
  /// `teamSegOffsets[i]` 格，于是所有班组都在同一天换班、只是换到不同的班次上
  /// （spec §3.3）。
  final List<int> teamSegOffsets;

  /// 这套方案走按月锚定吗。**唯一的模式判据**（见类文档）。
  final bool monthly;

  /// 班组数。
  final int teamCount;

  /// 班组名（长度与 teamCount 一致）。
  final List<String> teamNames;

  /// 我们是第几个班组。
  final int ourTeamIndex;

  /// 每个班组相对基准日的天数偏移（长度与 teamCount 一致）；
  /// 为空时回退到旧的「按 ourTeamIndex 错开」逻辑。
  final List<int> teamOffsets;

  /// 按天改班覆盖：`dayNumber(日期) → classes 下标`。
  ///
  /// 与其他班次查询**同口径**（存的是下标，不是 classId）—— 库里存 classId，
  /// 由 `ActiveSchedule.toDomain()` 转换过来。
  ///
  /// 只作用于**我们班组**：[teamShift] 不查它。
  final Map<int, int> dayOverrides;

  int get cycleLength => cycle.length;

  @override
  String get label => name;

  /// 我们班组的班次：先查按天覆盖，没有覆盖才按轮转算。
  ///
  /// **覆盖只在 `shiftOn` 这一层生效**，所以四个消费者 —— 日历格子、底栏
  /// 信息卡、闹钟重排（`AlarmService.reschedule`）、闹钟页「未来 30 天」 ——
  /// 全都自动跟着走。而 [teamShift] 不查覆盖，「查看其他班组」看到的仍是纯
  /// 轮转，别人的班不会被我的调整改掉。
  ///
  /// 覆盖下标越界（班次被删、历史脏数据）时**回退到轮转**，不抛异常。
  /// 空白表（无周期）仍返回 null，覆盖不改变这一点。
  @override
  ShiftClass? shiftOn(DateTime date) {
    final ov = dayOverrides[dayNumber(date)];
    if (ov != null && ov >= 0 && ov < classes.length) return classes[ov];
    return teamShift(ourTeamIndex, date);
  }

  /// 指定班组在某天的班次；那天没有班次（空白表 / 无方案）返回 null。
  ///
  /// **判据是 [monthly] 这个标志，不是「段表空不空」**（见类文档）。
  ShiftClass? teamShift(int teamIndex, DateTime date) {
    if (monthly) {
      final n = monthlySegments.length;
      if (n == 0) return null; // 半配置 / 空白表：与「周期为空」同一条路
      final off = (teamIndex >= 0 && teamIndex < teamSegOffsets.length)
          ? teamSegOffsets[teamIndex]
          : teamIndex - ourTeamIndex; // 回退：与 teamOffsets 那条同一条纪律
      final classIndex =
          monthlyClassIndexOn(monthlySegments, dayOfMonth(date), off);
      // 越界只有一条出路：返回 null。按月模式下**没有周期可以退**，所以这里
      // 不能写成「回退到轮转」—— 那句话在周期模式里成立、写在这里是句空话。
      if (classIndex == null ||
          classIndex < 0 ||
          classIndex >= classes.length) {
        return null;
      }
      return classes[classIndex];
    }
    if (cycle.isEmpty) return null;
    final base = (teamIndex >= 0 && teamIndex < teamOffsets.length)
        ? teamOffsets[teamIndex]
        : teamIndex - ourTeamIndex; // 回退：旧的按班组错开
    final offset = daysBetween(anchorDate, date) + base;
    var idx = offset % cycleLength;
    if (idx < 0) idx += cycleLength;
    final classIndex = cycle[idx];
    if (classIndex < 0 || classIndex >= classes.length) return null;
    return classes[classIndex];
  }
}

/// 两个班组在周期上的**同一天**被排到同一个工作班次。
///
/// 「撞班」是班组错位（[ShiftSchedule.teamOffsets]）与周期长度不匹配的症状。
/// 2026-09-21 的用户反馈就是它：把五班三倒从 5 天一轮改成 10 天一轮（每个班连排
/// 两天），而各班组仍按 1 天错开 —— 于是同一天有两个班组上同样的班。
class CrewClash {
  const CrewClash({
    required this.cycleDay,
    required this.teamA,
    required this.teamB,
    required this.shift,
  });

  /// 周期内第几天（**1 起**，与界面上的「第 N 天」同一口径）。
  ///
  /// **按月模式下装的是当日号数（1..31）** —— 含义由模式决定，见 [crewClashes]。
  final int cycleDay;

  /// 相撞的两个班组下标，[teamA] 恒小于 [teamB]。
  final int teamA;
  final int teamB;

  /// 撞在一起的那个班次。
  final ShiftClass shift;
}

/// 扫**一个完整周期**，列出「两个班组同一天上同一个班」的日子。
///
/// 只扫一个周期就够：班组错位是常数偏移，整张表以周期长度重复。
/// 判等用 `identical` —— 同一份 [ShiftSchedule] 里 `teamShift` 返回的是
/// `classes` 里同一个实例，用 `==` 会把内容相同的两个**不同班次定义**也认成撞班。
///
/// 休息班次不算撞（两个班组同时休是正常的），空白表（无周期 / 无班次定义）返回空表。
///
/// **按月模式走另一条路**（[_monthlyCrewClashes]）：那句话在那边不成立 —— 一个月的
/// 长度在 28~31 之间变，没有「一个周期」可扫。两条分支的判据都是 [CrewClash.cycleDay]
/// 之外的那一套（非休班 + `identical`），所以「什么算撞班」两边是同一个定义。
List<CrewClash> crewClashes(ShiftSchedule s) {
  if (s.classes.isEmpty) return const [];
  if (s.monthly) return _monthlyCrewClashes(s);
  if (s.cycle.isEmpty) return const [];
  final out = <CrewClash>[];
  for (var k = 0; k < s.cycleLength; k++) {
    final date = s.anchorDate.add(Duration(days: k));
    final working = <int, ShiftClass>{};
    for (var t = 0; t < s.teamCount; t++) {
      final sc = s.teamShift(t, date);
      if (sc == null || sc.isRest) continue;
      working[t] = sc;
    }
    final teams = working.keys.toList()..sort();
    for (var i = 0; i < teams.length; i++) {
      for (var j = i + 1; j < teams.length; j++) {
        if (identical(working[teams[i]], working[teams[j]])) {
          out.add(CrewClash(
            cycleDay: k + 1,
            teamA: teams[i],
            teamB: teams[j],
            shift: working[teams[i]]!,
          ));
        }
      }
    }
  }
  return out;
}

/// 按月模式的撞班扫描。
///
/// **它没有「一个周期」可扫**：一个月的长度在 28~31 之间变，要盖住全部形状得扫
/// 满**四年**（含闰年 2 月 29）。从 2020-01-01 起逐日扫 1461 天，按**当日号数**
/// 去重后报出来 —— 一个「班组数比段数还多」的配置在这四年里天天撞，去重之后
/// 每个号数只报一条。
///
/// ⚠️ [CrewClash.cycleDay] 装的是**当日号数**（不是「周期内第几天」）。它是各种
/// 月长的**并集**，所以界面上**不能拿它的条数当天数说**（spec §5.2）——
/// 编辑器的按月提示因此是一句不带数字的话。
List<CrewClash> _monthlyCrewClashes(ShiftSchedule s) {
  final out = <CrewClash>[];
  final seen = <(int, int, int)>{}; // (当日号数, 班A, 班B)
  var day = DateTime.utc(2020, 1, 1); // 闰年，保证 2/29 会出现
  for (var i = 0; i < 1461; i++) {
    final dom = day.day;
    final working = <int, ShiftClass>{};
    for (var t = 0; t < s.teamCount; t++) {
      final sc = s.teamShift(t, day);
      if (sc == null || sc.isRest) continue;
      working[t] = sc;
    }
    final teams = working.keys.toList()..sort();
    for (var a = 0; a < teams.length; a++) {
      for (var b = a + 1; b < teams.length; b++) {
        if (!identical(working[teams[a]], working[teams[b]])) continue;
        if (!seen.add((dom, teams[a], teams[b]))) continue;
        out.add(CrewClash(
          cycleDay: dom,
          teamA: teams[a],
          teamB: teams[b],
          shift: working[teams[a]]!,
        ));
      }
    }
    day = DateTime.utc(day.year, day.month, day.day + 1);
  }
  return out;
}

/// 班组错位的**均分**规则：第 i 个班组落在周期的 `i × 周期长度 ÷ 班组数` 天处
/// （四舍五入）。
///
/// 这不是新发明的规则 —— **全部内置多班组模板的 `teamOffsets` 都是它算出来的**
/// （四班两倒 4/4 → 0/1/2/3、两班倒 14/2 → 0/7、DuPont 28/4 → 0/7/14/21、
/// 五班四倒 5/5 → 0/1/2/3/4……），由 `shift_templates_test.dart` 逐条守着。
/// 用它把「周期长度改了、各班组还按老间隔错开」造成的撞班一次抹平。
///
/// [keepIndex] / [keepOffset] 指定一个**保持不动**的班组（通常是「我们班组」）：
/// 均分是为了让别人不再和自己撞班，不该顺手把用户自己的周期起始日挪走。
///
/// **按月模式也用它，只是把 [cycleLength] 传成「段数」** —— 那条路上班组的错位
/// 单位是段（`ShiftSchedule.teamSegOffsets`，spec §3.3），而「第 i 组落在
/// `i × n ÷ 班组数` 处」这条规则两边同形。别为它另写一份。
///
/// 班组数多于周期天数时，整数错位必然有重复（抽屉原理）—— 那是配置本身的问题，
/// 不是这条规则能救的。
List<int> evenTeamOffsets(
  int cycleLength,
  int teamCount, {
  int keepIndex = 0,
  int keepOffset = 0,
}) {
  if (cycleLength <= 0 || teamCount <= 0) return const [];
  final evenly = <int>[
    for (var i = 0; i < teamCount; i++) (i * cycleLength / teamCount).round(),
  ];
  final shift = (keepIndex >= 0 && keepIndex < teamCount)
      ? keepOffset - evenly[keepIndex]
      : 0;
  return <int>[for (final e in evenly) e + shift];
}

/// 默认「四班两倒」配置：白班 → 上夜班 → 下夜班 → 大休（4 天周期），4 个班组错开。
///
/// 名称与班次名按**当前语言**生成：返回值有三条落库/入界面路径 ——
/// `seedIfEmpty` 首启播种、「我自己排」进编辑器、编辑器从空白表切回普通表。
/// 英文界面下这三条路都不该产出中文，所以文案不能硬编码。
ShiftSchedule defaultSchedule() {
  final anchor = DateTime.utc(2025, 1, 6); // 占位基准日（我们班组的第 1 天）
  return ShiftSchedule(
    name: L10n.t('四班两倒', '4-crew 2-shift'),
    anchorDate: anchor,
    teamCount: 4,
    teamNames: L10n.defaultTeamNames(4),
    ourTeamIndex: 0,
    teamOffsets: const [0, 1, 2, 3],
    cycle: const [0, 1, 2, 3],
    classes: [
      ShiftClass(
        name: L10n.t('白班', 'Day shift'),
        abbr: L10n.t('白', 'D'),
        startMinute: 8 * 60 + 30,
        endMinute: 20 * 60 + 30,
        color: 0xFF4C8DFF,
        alarmEnabled: true,
        alarms: const [ShiftAlarm(minute: 7 * 60)],
      ),
      ShiftClass(
        name: L10n.t('上夜班', 'Night shift'),
        abbr: L10n.t('夜', 'N'),
        startMinute: 20 * 60 + 30,
        endMinute: 8 * 60 + 30,
        color: 0xFF7A5CFF,
        alarmEnabled: true,
        alarms: const [ShiftAlarm(minute: 19 * 60 + 30)],
      ),
      ShiftClass(
        name: L10n.t('下夜班', 'Off after nights'),
        abbr: L10n.t('休', 'O'),
        isRest: true,
        color: 0xFF9AA0B4,
      ),
      ShiftClass(
        name: L10n.t('大休', 'Long rest'),
        abbr: L10n.t('休', 'R'),
        isRest: true,
        color: 0xFF5A5F73,
      ),
    ],
  );
}
