// 排班轮换引擎 —— 纯 Dart，无 Flutter 依赖，可直接 dart test。
//
// 核心公式（自研四班轮转引擎）：
//   某班组某天的班次 = shiftTypes[ (目标日 - 锚点日 + 班组偏移) mod cycle ]
//   其中"我们"班组的偏移 = ourTeamIndex，锚点日 = 我们班组的白班日。

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

/// 轮换周期中的一种班次类型。
class ShiftType {
  const ShiftType({
    required this.order,
    required this.name,
    this.startMinute,
    this.endMinute,
    this.isRest = false,
    this.color = 0xFF5B7FFF,
    this.alarmEnabled = false,
    this.alarmMinute,
  });

  /// 在周期中的位置（0 起）。
  final int order;

  /// 班次名（自由文本），如 白班 / 上夜班 / 下夜班 / 大休。
  final String name;

  /// 工作开始时间（分钟自午夜）；休息班次为 null。
  final int? startMinute;

  /// 工作结束时间；若 end < start 表示跨午夜。
  final int? endMinute;

  /// 是否休息日（不响联动闹钟）。
  final bool isRest;

  /// 日历格子的 ARGB 颜色。
  final int color;

  /// 联动闹钟是否开启。
  final bool alarmEnabled;

  /// 联动闹钟响铃时间（分钟自午夜）；null 表示未设。
  final int? alarmMinute;

  /// 工作窗口是否跨午夜。
  bool get crossesMidnight =>
      startMinute != null && endMinute != null && endMinute! < startMinute!;

  ShiftType copyWith({
    int? order,
    String? name,
    int? startMinute,
    int? endMinute,
    bool? isRest,
    int? color,
    bool? alarmEnabled,
    int? alarmMinute,
  }) {
    return ShiftType(
      order: order ?? this.order,
      name: name ?? this.name,
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
      other is ShiftType &&
      other.order == order &&
      other.name == name &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute &&
      other.isRest == isRest &&
      other.color == color &&
      other.alarmEnabled == alarmEnabled &&
      other.alarmMinute == alarmMinute;

  @override
  int get hashCode => Object.hash(
      order, name, startMinute, endMinute, isRest, color, alarmEnabled, alarmMinute);

  @override
  String toString() => 'ShiftType($order:$name, rest=$isRest)';
}

/// 一套排班方案（一个轮换周期 + 多班组）。
class ShiftSchedule {
  const ShiftSchedule({
    required this.name,
    required this.anchorDate,
    required this.shiftTypes,
    this.teamCount = 4,
    this.teamNames = const ['一班', '二班', '三班', '四班'],
    this.ourTeamIndex = 0,
    this.teamOffsets = const [],
  });

  /// 空白表（跟随法定节假日）：无任何班次轮换。
  bool get isBlank => shiftTypes.isEmpty;

  final String name;

  /// 锚点日：各班组在此日期的班次由 [teamOffsets] 显式指定。
  final DateTime anchorDate;

  /// 有序班次列表，长度即周期。
  final List<ShiftType> shiftTypes;

  /// 班组数。
  final int teamCount;

  /// 班组名（长度与 teamCount 一致）。
  final List<String> teamNames;

  /// 我们是第几个班组。
  final int ourTeamIndex;

  /// 每个班组在锚点日的班次下标（长度与 teamCount 一致）；
  /// 为空时回退到旧的「按 ourTeamIndex 错开」逻辑。
  final List<int> teamOffsets;

  int get cycleLength => shiftTypes.length;

  /// 我们班组的班次；空白表（无班次）返回 null。
  ShiftType? shiftOn(DateTime date) => teamShift(ourTeamIndex, date);

  /// 指定班组在某天的班次；空白表（无班次）返回 null。
  ShiftType? teamShift(int teamIndex, DateTime date) {
    if (shiftTypes.isEmpty) return null;
    final base = (teamIndex >= 0 && teamIndex < teamOffsets.length)
        ? teamOffsets[teamIndex]
        : teamIndex - ourTeamIndex; // 回退：旧的按班组错开
    final offset = daysBetween(anchorDate, date) + base;
    var idx = offset % cycleLength;
    if (idx < 0) idx += cycleLength;
    return shiftTypes[idx];
  }
}

/// 默认「四班两倒」配置：白班 → 上夜班 → 下夜班 → 大休（4 天周期），4 个班组错开。
ShiftSchedule defaultSchedule() {
  final anchor = DateTime.utc(2025, 1, 6); // 占位锚点（我们班组的白班日）
  return ShiftSchedule(
    name: '四班两倒',
    anchorDate: anchor,
    teamCount: 4,
    teamNames: const ['一班', '二班', '三班', '四班'],
    ourTeamIndex: 0,
    teamOffsets: const [0, 1, 2, 3],
    shiftTypes: [
      ShiftType(
        order: 0,
        name: '白班',
        startMinute: toMinutes(8, 30),
        endMinute: toMinutes(20, 30),
        color: 0xFF4C8DFF,
        alarmEnabled: true,
        alarmMinute: toMinutes(7, 0),
      ),
      ShiftType(
        order: 1,
        name: '上夜班',
        startMinute: toMinutes(20, 30),
        endMinute: toMinutes(8, 30),
        color: 0xFF7A5CFF,
        alarmEnabled: true,
        alarmMinute: toMinutes(19, 30),
      ),
      ShiftType(order: 2, name: '下夜班', isRest: true, color: 0xFF9AA0B4),
      ShiftType(order: 3, name: '大休', isRest: true, color: 0xFF5A5F73),
    ],
  );
}
