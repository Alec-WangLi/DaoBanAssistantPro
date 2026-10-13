import 'dart:convert';

import 'monthly_pattern.dart';
import 'shift_rotation.dart';

/// 一套「我的模板」：把某套方案的**结构**存下来，新建排班时可以再选它。
///
/// 结构 = 班次定义 + 周期序列 + 班组错位；**不含**方案名之外的身份、基准日与
/// 按天覆盖 —— 那些是「这一套方案」的事，用模板建出来的新方案自己定
/// （与内置模板同一条约定：新建时基准日 = 今天、「我们班组」= 第 1 组）。
///
/// 保存时班组错位**归一化成「我们班组在第 0 位、错位 0」**：新建排班那条路
/// （`createScheduleFromTemplatePicker`）写死 `ourTeamIndex: 0`，不归一化的话
/// 用模板建出来的方案里「我们班组」会指到别人身上。
class ScheduleTemplate {
  const ScheduleTemplate({
    this.id,
    required this.name,
    required this.classes,
    required this.cycle,
    required this.teamCount,
    required this.teamOffsets,
    this.monthly = false,
    this.monthlySegments = const [],
    this.teamSegOffsets = const [],
  });

  /// 库里的行 id；null = 还没落库。
  final int? id;

  final String name;
  final List<ShiftClass> classes;
  final List<int> cycle;
  final int teamCount;

  /// 班组的**天数**偏移（周期模式用）。
  final List<int> teamOffsets;

  /// 这套模板走按月锚定吗（与 `ShiftSchedule.monthly` 同一条约定：**唯一的模式
  /// 判据**，别用「段表空不空」去猜）。
  final bool monthly;

  /// 按月切法。**存下标**（与 [cycle] 同一条：模板里的班次没有稳定身份）。
  final List<MonthlySegment> monthlySegments;

  /// 班组的**段**偏移（按月模式用）。与 [teamOffsets] 分开，单位不同。
  final List<int> teamSegOffsets;

  int get cycleLength => cycle.length;

  /// 每天同时在上班的班组数（与 `ShiftTemplate.workingTeamsPerDay` 同一口径，
  /// 供选择页卡片上那行「每天在岗 N 个班组」用）。
  int get workingTeamsPerDay {
    if (monthly) {
      // 按月模式：段的长短随月份变，所以取一个**代表性的一天**（每月 1 日）
      // 数一遍就够了 —— 它问的是「这套排法每天大概有几个人在岗」，不是逐日明细。
      if (monthlySegments.isEmpty) return 0;
      var count = 0;
      for (var t = 0; t < teamCount; t++) {
        final offset = t < teamSegOffsets.length ? teamSegOffsets[t] : t;
        final classIndex = monthlyClassIndexOn(monthlySegments, 1, offset);
        if (classIndex == null ||
            classIndex < 0 ||
            classIndex >= classes.length) {
          continue;
        }
        if (!classes[classIndex].isRest) count++;
      }
      return count;
    }
    if (cycle.isEmpty) return 0;
    var count = 0;
    for (var t = 0; t < teamCount; t++) {
      final offset = t < teamOffsets.length ? teamOffsets[t] : t;
      var idx = offset % cycle.length;
      if (idx < 0) idx += cycle.length;
      final classIndex = cycle[idx];
      if (classIndex < 0 || classIndex >= classes.length) continue;
      if (!classes[classIndex].isRest) count++;
    }
    return count;
  }

  /// 从一套方案里取模板；[name] 是模板名。
  ///
  /// 把「我们班组」转到第 0 位并让它的错位变成 0（整组一起平移，班组之间的
  /// 相对错位一个像素都不动）。错位表短于班组数时按 `teamShift` 的回退规则补
  /// （`i - ourTeamIndex`），与域里算出来的结果保持一致。
  ///
  /// **按月那一边同待遇**：段偏移也要整体平移、并相对我们班组归零 —— 只是
  /// 取模的单位是**段数**（段偏移的单位是段，不是天）。不归一化的话，用模板建
  /// 出来的方案里「我们班组」会指到别人身上（周期那条是同一个坑）。
  static ScheduleTemplate fromSchedule(ShiftSchedule s,
      {required String name}) {
    final n = s.teamCount;
    final ours = (s.ourTeamIndex >= 0 && s.ourTeamIndex < n) ? s.ourTeamIndex : 0;
    final offsets = <int>[
      for (var i = 0; i < n; i++)
        i < s.teamOffsets.length ? s.teamOffsets[i] : i - ours,
    ];
    final base = offsets.isEmpty ? 0 : offsets[ours];
    // 先按「我们班组打头」重排，再整体减去它的错位。
    final rotated = <int>[
      for (var i = 0; i < n; i++) offsets[(i + ours) % n],
    ];

    final segCount = s.monthlySegments.length;
    final segOffsets = <int>[
      for (var i = 0; i < n; i++)
        i < s.teamSegOffsets.length ? s.teamSegOffsets[i] : i - ours,
    ];
    final segBase = segOffsets.isEmpty ? 0 : segOffsets[ours];
    final segRotated = <int>[
      for (var i = 0; i < n; i++) segOffsets[(i + ours) % n],
    ];
    // `%` 对正除数恒非负（Dart 的语义），所以负的差值直接取模就对 —— 平移之后
    // 「我们班组」恒为 0，其余落在 0..段数-1。
    final normalizedSegOffsets = segCount == 0
        ? const <int>[]
        : <int>[for (final o in segRotated) (o - segBase) % segCount];

    return ScheduleTemplate(
      name: name,
      classes: s.classes,
      cycle: s.cycle,
      teamCount: n,
      teamOffsets: [for (final o in rotated) o - base],
      monthly: s.monthly,
      monthlySegments: s.monthlySegments,
      teamSegOffsets: normalizedSegOffsets,
    );
  }
}

// ---------------------------------------------------------------------------
// 编解码
//
// 模板整块存进**一列**而不是像方案那样拆成三张表：模板是只读快照，没有按字段
// 查询、没有跨表引用、也不与任何行共享身份 —— 拆表只会多两张表和一整套装配代码
// 与迁移。（方案那边拆表是因为**按天改班的覆盖要引用稳定的 classId**，模板没有
// 这个需求。）
//
// 数字串走逗号分隔（与 `app_repository.dart` 的 joinTeamOffsets 同一写法），
// 班次定义走 JSON（字段多、有三个可空值，CSV 会在空值上变得没法读）。
// 解码一律**容错**：坏数据丢那一条，不让一列坏 JSON 把整个模板库废掉。
// ---------------------------------------------------------------------------

String encodeTemplateCycle(List<int> cycle) => cycle.join(',');

List<int> decodeTemplateCycle(String raw) => decodeTemplateInts(raw);

String encodeTemplateOffsets(List<int> offsets) => offsets.join(',');

List<int> decodeTemplateOffsets(String raw) => decodeTemplateInts(raw);

/// 按月段表 → `startDay:classIndex` 逗号分隔的一串。
///
/// 与 [encodeTemplateCycle] 同一个理由：模板整块存一列、没有跨表引用。
/// 段表要多带一个数（起始日），所以不是纯数字串 —— 冒号分隔。
String encodeTemplateMonthSegments(List<MonthlySegment> segments) =>
    segments.map((s) => '${s.startDay}:${s.classIndex}').join(',');

/// 反向解码。**容错**：解析不出来的那一项**丢掉**（空段、缺冒号、不是数字），
/// 与 [decodeTemplateInts] 同一条口径 —— 一列坏数据不该把整个模板库废掉。
List<MonthlySegment> decodeTemplateMonthSegments(String raw) {
  if (raw.trim().isEmpty) return const [];
  final out = <MonthlySegment>[];
  for (final piece in raw.split(',')) {
    final p = piece.trim();
    if (p.isEmpty) continue;
    final parts = p.split(':');
    if (parts.length != 2) continue;
    final day = int.tryParse(parts[0].trim());
    final classIndex = int.tryParse(parts[1].trim());
    if (day == null || classIndex == null) continue;
    out.add(MonthlySegment(startDay: day, classIndex: classIndex));
  }
  return out;
}

/// 逗号分隔的整数串；空串返回空表，解析不出来的那一段按 0 处理
/// （与 `parseTeamOffsets` 同一条容错口径）。
List<int> decodeTemplateInts(String raw) {
  if (raw.trim().isEmpty) return const [];
  return raw.split(',').map((e) => int.tryParse(e.trim()) ?? 0).toList();
}

/// 班次定义 → JSON 数组。id 不存：模板里的班次不需要稳定身份（按天改班的覆盖
/// 只引用**方案**里的班次，与模板无关），存了反而会与新方案里的自增 id 撞车。
String encodeTemplateClasses(List<ShiftClass> classes) => jsonEncode([
      for (final c in classes)
        {
          'name': c.name,
          'abbr': c.abbr,
          'startMinute': c.startMinute,
          'endMinute': c.endMinute,
          'isRest': c.isRest,
          'color': c.color,
          'alarmEnabled': c.alarmEnabled,
          'alarms': [
            for (final a in c.alarms) {'minute': a.minute, 'label': a.label},
          ],
        }
    ]);

/// JSON 数组 → 班次定义；坏数据返回空表（调用方据此跳过这一条模板）。
List<ShiftClass> decodeTemplateClasses(String raw) {
  if (raw.trim().isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map)
          ShiftClass(
            name: '${e['name'] ?? ''}',
            abbr: e['abbr'] as String?,
            startMinute: (e['startMinute'] as num?)?.toInt(),
            endMinute: (e['endMinute'] as num?)?.toInt(),
            isRest: e['isRest'] == true,
            color: (e['color'] as num?)?.toInt() ?? 0xFF5B7FFF,
            alarmEnabled: e['alarmEnabled'] == true,
            alarms: _decodeAlarms(e),
          ),
    ];
  } catch (_) {
    return const [];
  }
}

/// 班次对象 → 闹钟列表。
///
/// 新格式读 `alarms`；**没有就回退**读旧的两个字段 —— 用户升级前存下的「我的
/// 模板」还在硬盘上，只有 `alarmEnabled` + `alarmMinute`。旧格式里
/// `alarmMinute` 为空 → 空表，**不能退化成「一条 0 点的闹钟」**。
List<ShiftAlarm> _decodeAlarms(Map e) {
  final list = e['alarms'];
  if (list is List) {
    return [
      for (final a in list)
        if (a is Map && a['minute'] is num)
          ShiftAlarm(
            minute: (a['minute'] as num).toInt(),
            label: a['label'] is String ? a['label'] as String : null,
          ),
    ];
  }
  final legacy = e['alarmMinute'];
  if (legacy is num) return [ShiftAlarm(minute: legacy.toInt())];
  return const [];
}
