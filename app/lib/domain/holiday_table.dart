// app/lib/domain/holiday_table.dart
//
// 法定节假日「数据表」：整段放假区间 + 调休上班日。
//
// 为什么从 `lunar_info.dart` 里搬出来：这张表**不再只随版本更新**了
// （2026-11-15 用户要求「能不能自动更新」）。它现在有两个来源 ——
//   1. 编译进来的内置表（[builtinHolidayTable]），永远可用，离线/被墙也照旧；
//   2. 远程 `holidays.json`（官网 → 仓库 raw），启动时后台拉一次、缓存到本地。
// 于是「解析 / 校验 / 合并」必须是一份**能单测的纯数据逻辑**，不能藏在界面或
// 原生通道里 —— 这一层只管数据，不联网、不读设置。
//
// 校验是**整份通过才认**：任一条日期解析失败、年份越界、区间首尾颠倒、区间
// 互相重叠 → 整份丢弃，继续用旧的。宁可旧，也不能错 —— 这张表直接决定日历上
// 哪天标红、哪天打「班」。
import 'dart:convert';

import 'shift_rotation.dart';

/// 一条法定节假日区间（含首尾两天，国务院官方放假安排）。
class HolidaySpan {
  const HolidaySpan({
    required this.name,
    required this.year,
    required this.startDay,
    required this.endDay,
  });

  final String name;

  /// 这条区间归属的年份（国务院通知按年发布）。
  ///
  /// 合并远程数据时按它整年替换：远程给了 2027，就把内置表里 2027 的全部丢掉，
  /// 而不是逐条比对 —— 逐条比对在「区间被拆成两段」「调休日挪了一天」这些
  /// 真实变化上会留下孤儿条目。
  final int year;

  final int startDay; // 自 epoch 天数（含）
  final int endDay; // 自 epoch 天数（含）

  bool covers(int day) => day >= startDay && day <= endDay;
}

/// 一张法定节假日表。
class HolidayTable {
  const HolidayTable({
    required this.spans,
    required this.makeupDays,
    required this.years,
  });

  /// 按起始日升序排列的放假区间。
  final List<HolidaySpan> spans;

  /// 调休上班日（假期里被调成上班的周末）。
  final Set<int> makeupDays;

  /// 这份表覆盖了哪几年。
  final Set<int> years;

  static const empty =
      HolidayTable(spans: <HolidaySpan>[], makeupDays: <int>{}, years: <int>{});

  /// 数据覆盖到的最后一年（界面显示「已覆盖至 2026 年」用）；空表返回 null。
  int? get latestYear {
    if (years.isEmpty) return null;
    return years.reduce((a, b) => a > b ? a : b);
  }

  /// 该日期所在法定节假日的名称（非假期返回 null）。
  String? holidayNameOf(int day) {
    for (final s in spans) {
      if (s.covers(day)) return s.name;
    }
    return null;
  }

  bool isMakeup(int day) => makeupDays.contains(day);

  /// 用 [newer]（远程）覆盖同年份的条目，其余年份保留自己的。
  HolidayTable mergedWith(HolidayTable newer) {
    if (newer.years.isEmpty) return this;
    final keptSpans =
        spans.where((s) => !newer.years.contains(s.year)).toList();
    final keptMakeup =
        makeupDays.where((d) => !newer.years.contains(_yearOfDay(d))).toSet();
    final merged = HolidayTable(
      spans: <HolidaySpan>[...keptSpans, ...newer.spans],
      makeupDays: <int>{...keptMakeup, ...newer.makeupDays},
      years: <int>{...years, ...newer.years},
    );
    return HolidayTable(
      spans: List<HolidaySpan>.unmodifiable(merged._sortedSpans()),
      makeupDays: Set<int>.unmodifiable(merged.makeupDays),
      years: Set<int>.unmodifiable(merged.years),
    );
  }

  List<HolidaySpan> _sortedSpans() =>
      <HolidaySpan>[...spans]..sort((a, b) => a.startDay.compareTo(b.startDay));

  /// 解析远程 `holidays.json`。
  ///
  /// 格式（`schema` 只认 1）：
  /// ```json
  /// {"schema": 1, "generatedAt": "2026-11-15",
  ///  "years": [{"year": 2027,
  ///             "spans": [{"name": "元旦节", "start": "2027-01-01", "end": "2027-01-03"}],
  ///             "makeup": ["2027-01-04"]}]}
  /// ```
  ///
  /// **任何一条不合法就整份抛 [FormatException]**，调用方据此保留旧表。
  static HolidayTable parse(String body) {
    final Object? root = jsonDecode(body);
    if (root is! Map) throw const FormatException('根节点不是对象');
    final schema = root['schema'];
    if (schema != 1) throw FormatException('不认识的 schema：$schema');
    final rawYears = root['years'];
    if (rawYears is! List || rawYears.isEmpty) {
      throw const FormatException('years 缺失或为空');
    }

    final spans = <HolidaySpan>[];
    final makeup = <int>{};
    final years = <int>{};
    for (final entry in rawYears) {
      if (entry is! Map) throw const FormatException('years 里不是对象');
      final year = entry['year'];
      if (year is! int || year < 2000 || year > 2100) {
        throw FormatException('年份越界：$year');
      }
      if (!years.add(year)) throw FormatException('年份重复：$year');

      final rawSpans = entry['spans'];
      if (rawSpans is! List || rawSpans.isEmpty) {
        throw FormatException('$year 年没有 spans');
      }
      for (final s in rawSpans) {
        if (s is! Map) throw FormatException('$year 的 span 不是对象');
        final name = s['name'];
        if (name is! String || name.trim().isEmpty || name.length > 16) {
          throw FormatException('$year 有个区间名字不合法：$name');
        }
        final start = _parseDay(s['start']);
        final end = _parseDay(s['end']);
        if (start == null || end == null) {
          throw FormatException('$year 的 ${s['name']} 日期格式不对');
        }
        if (end.isBefore(start)) {
          throw FormatException('$year 的 $name 首尾颠倒');
        }
        // 单段放假最长是 8 天（2025 年中秋·国庆）。放宽到 31 天只为兜住
        // 「把整年写成一段」这类明显错误的数据，不表达任何业务口径。
        if (dayNumber(end) - dayNumber(start) > 30) {
          throw FormatException('$year 的 $name 区间过长');
        }
        if (start.year != year && end.year != year) {
          throw FormatException('$year 的 $name 跨到了别的年份');
        }
        spans.add(HolidaySpan(
          name: name,
          year: year,
          startDay: dayNumber(start),
          endDay: dayNumber(end),
        ));
      }

      final rawMakeup = entry['makeup'] ?? const <Object?>[];
      if (rawMakeup is! List) throw FormatException('$year 的 makeup 不是数组');
      for (final m in rawMakeup) {
        final d = _parseDay(m);
        if (d == null || d.year != year) {
          throw FormatException('$year 的调休日不合法：$m');
        }
        makeup.add(dayNumber(d));
      }
    }

    // 区间不许重叠：重叠说明数据自己打架，画到日历上会是哪一天都说不清。
    final sorted = <HolidaySpan>[...spans]
      ..sort((a, b) => a.startDay.compareTo(b.startDay));
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].startDay <= sorted[i - 1].endDay) {
        throw FormatException(
            '区间重叠：${sorted[i - 1].name} 与 ${sorted[i].name}');
      }
    }

    return HolidayTable(
      spans: List<HolidaySpan>.unmodifiable(sorted),
      makeupDays: Set<int>.unmodifiable(makeup),
      years: Set<int>.unmodifiable(years),
    );
  }
}

final _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// `yyyy-MM-dd` → UTC 纯日期；格式或日历上不成立（2 月 30 日）返回 null。
DateTime? _parseDay(Object? value) {
  if (value is! String) return null;
  final m = _datePattern.firstMatch(value.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final dt = DateTime.utc(y, mo, d);
  // `DateTime.utc(2027, 2, 30)` 会滚到 3 月 2 日 —— 靠回读把这种日期挡掉。
  if (dt.year != y || dt.month != mo || dt.day != d) return null;
  return dt;
}

int _yearOfDay(int day) =>
    DateTime.fromMillisecondsSinceEpoch(day * Duration.millisecondsPerDay,
            isUtc: true)
        .year;

/// 国务院官方「法定节假日」整段区间（2025 / 2026）。
///
/// lunar_plus 只在单日（如 10-01 国庆节当天）返回节日名，这里补上整段放假区间，
/// 让整段假期都能标红。
///
/// **这是兜底表，不是唯一来源**：远程 `holidays.json` 到了会按年份覆盖上面
/// 同年的条目（见 [HolidayTable.mergedWith]）。每年国务院发布下一年安排后
/// **仍要在这里追加一次**（数据见 gov.cn「国务院办公厅关于部分节假日安排的通知」）
/// —— 远程连不上的人（离线、内网、被墙）只认这一份。
final HolidayTable builtinHolidayTable = HolidayTable(
  spans: <HolidaySpan>[
    // 2026
    _span('元旦节', 2026, DateTime(2026, 1, 1), DateTime(2026, 1, 3)),
    _span('春节', 2026, DateTime(2026, 2, 15), DateTime(2026, 2, 23)),
    _span('清明节', 2026, DateTime(2026, 4, 4), DateTime(2026, 4, 6)),
    _span('劳动节', 2026, DateTime(2026, 5, 1), DateTime(2026, 5, 5)),
    _span('端午节', 2026, DateTime(2026, 6, 19), DateTime(2026, 6, 21)),
    _span('中秋节', 2026, DateTime(2026, 9, 25), DateTime(2026, 9, 27)),
    _span('国庆节', 2026, DateTime(2026, 10, 1), DateTime(2026, 10, 7)),
    // 2025
    _span('元旦节', 2025, DateTime(2025, 1, 1), DateTime(2025, 1, 1)),
    _span('春节', 2025, DateTime(2025, 1, 28), DateTime(2025, 2, 4)),
    _span('清明节', 2025, DateTime(2025, 4, 4), DateTime(2025, 4, 6)),
    _span('劳动节', 2025, DateTime(2025, 5, 1), DateTime(2025, 5, 5)),
    _span('端午节', 2025, DateTime(2025, 5, 31), DateTime(2025, 6, 2)),
    _span('中秋节·国庆节', 2025, DateTime(2025, 10, 1), DateTime(2025, 10, 8)),
  ],
  makeupDays: <int>{
    // 2026
    dayNumber(DateTime(2026, 1, 4)),
    dayNumber(DateTime(2026, 2, 14)),
    dayNumber(DateTime(2026, 2, 28)),
    dayNumber(DateTime(2026, 5, 9)),
    dayNumber(DateTime(2026, 9, 20)),
    dayNumber(DateTime(2026, 10, 10)),
    // 2025
    dayNumber(DateTime(2025, 1, 26)),
    dayNumber(DateTime(2025, 2, 8)),
    dayNumber(DateTime(2025, 4, 27)),
    dayNumber(DateTime(2025, 9, 28)),
    dayNumber(DateTime(2025, 10, 11)),
  },
  years: const <int>{2025, 2026},
);

HolidaySpan _span(String name, int year, DateTime start, DateTime end) =>
    HolidaySpan(
      name: name,
      year: year,
      startDay: dayNumber(start),
      endDay: dayNumber(end),
    );
