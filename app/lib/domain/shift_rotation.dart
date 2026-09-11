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

/// 班次定义：一个班次只定义一次，周期里的每一天引用它。
class ShiftClass {
  const ShiftClass({
    required this.name,
    this.abbr,
    this.startMinute,
    this.endMinute,
    this.isRest = false,
    this.color = 0xFF5B7FFF,
    this.alarmEnabled = false,
    this.alarmMinute,
  });

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

  /// 联动闹钟是否开启。
  final bool alarmEnabled;

  /// 联动闹钟响铃时间（分钟自午夜）；null 表示未设。
  final int? alarmMinute;

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
    String? name,
    String? abbr,
    int? startMinute,
    int? endMinute,
    bool? isRest,
    int? color,
    bool? alarmEnabled,
    int? alarmMinute,
  }) {
    return ShiftClass(
      name: name ?? this.name,
      abbr: abbr ?? this.abbr,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      isRest: isRest ?? this.isRest,
      color: color ?? this.color,
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      alarmMinute: alarmMinute ?? this.alarmMinute,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShiftClass &&
      other.name == name &&
      other.abbr == abbr &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute &&
      other.isRest == isRest &&
      other.color == color &&
      other.alarmEnabled == alarmEnabled &&
      other.alarmMinute == alarmMinute;

  @override
  int get hashCode => Object.hash(name, abbr, startMinute, endMinute, isRest,
      color, alarmEnabled, alarmMinute);

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

  int get cycleLength => cycle.length;

  /// 我们班组的班次；空白表（无周期）返回 null。
  ShiftClass? shiftOn(DateTime date) => teamShift(ourTeamIndex, date);

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
        alarmMinute: 7 * 60,
      ),
      ShiftClass(
        name: L10n.t('上夜班', 'Night shift'),
        abbr: L10n.t('夜', 'N'),
        startMinute: 20 * 60 + 30,
        endMinute: 8 * 60 + 30,
        color: 0xFF7A5CFF,
        alarmEnabled: true,
        alarmMinute: 19 * 60 + 30,
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
