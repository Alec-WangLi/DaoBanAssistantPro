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
/// Kotlin 侧 `cancelAllNativeAlarms` 扫的是 `0..400`（`MainActivity.kt:550`）。
/// 6 × 60 = 360 ≤ 400 刚好放得下。**改这个数或改天数窗口，必须同时改另一边。**
const int maxAlarmsPerShift = 6;

/// 响铃钟点是否落在上班的**前一天**。
///
/// 判据（Task 1 先原样搬旧规则，Task 2 再补「窗口内」那一档）：响铃的钟面值晚于
/// 上班的钟面值 —— 那个钟点在同一天里只可能排在上班**之后**（00:00 上班、23:00
/// 响铃 → 当天 23:00 那个班已经结束 15 小时），所以它指的必然是前一天晚上那个钟点。
///
/// 上班时间没填（或钟点相同）时返回 false：前者无从判断，后者「不晚于上班时刻的
/// 最近一次该钟点」就是上班那一刻本身。
bool alarmFallsOnPreviousDay(ShiftClass shift, ShiftAlarm alarm) {
  final s = shift.startMinute;
  if (s == null) return false;
  return alarm.minute > s;
}

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

/// 一套排班方案（班次定义 + 轮换周期 + 多班组）。
class ShiftSchedule {
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
  });

  /// 空白表（跟随法定节假日）：周期为空。
  bool get isBlank => cycle.isEmpty;

  final String name;

  /// 基准日：各班组在此日期的周期位置由 [teamOffsets] 显式指定。
  final DateTime anchorDate;

  /// 班次定义。
  final List<ShiftClass> classes;

  /// 周期序列：长度即周期，元素是 [classes] 的下标。
  final List<int> cycle;

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

  /// 我们班组的班次：先查按天覆盖，没有覆盖才按轮转算。
  ///
  /// **覆盖只在 `shiftOn` 这一层生效**，所以四个消费者 —— 日历格子、底栏
  /// 信息卡、闹钟重排（`AlarmService.reschedule`）、闹钟页「未来 30 天」 ——
  /// 全都自动跟着走。而 [teamShift] 不查覆盖，「查看其他班组」看到的仍是纯
  /// 轮转，别人的班不会被我的调整改掉。
  ///
  /// 覆盖下标越界（班次被删、历史脏数据）时**回退到轮转**，不抛异常。
  /// 空白表（无周期）仍返回 null，覆盖不改变这一点。
  ShiftClass? shiftOn(DateTime date) {
    final ov = dayOverrides[dayNumber(date)];
    if (ov != null && ov >= 0 && ov < classes.length) return classes[ov];
    return teamShift(ourTeamIndex, date);
  }

  /// 指定班组在某天的班次；空白表（无周期）返回 null。
  ShiftClass? teamShift(int teamIndex, DateTime date) {
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
List<CrewClash> crewClashes(ShiftSchedule s) {
  if (s.cycle.isEmpty || s.classes.isEmpty) return const [];
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
