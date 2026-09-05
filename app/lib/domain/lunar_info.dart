import 'package:lunar_plus/lunar.dart';

import 'shift_rotation.dart';

/// 法定节假日名称（用于红色高亮）。清明节通过节气「清明」判断。
const _legalHolidays = {
  '元旦节',
  '春节',
  '劳动节',
  '端午节',
  '中秋节',
  '国庆节',
};

/// 一条法定节假日区间（含首尾两天，国务院官方放假安排）。
class _HolidaySpan {
  const _HolidaySpan(this.name, this.startDay, this.endDay);

  final String name;
  final int startDay; // 自 epoch 天数（含）
  final int endDay; // 自 epoch 天数（含）
}

/// 国务院官方「法定节假日」整段区间（2025 / 2026）。
///
/// lunar_plus 只在单日（如 10-01 国庆节当天）返回节日名，这里补上整段放假区间，
/// 让整段假期都能标红。**每年国务院发布下一年安排后需在此追加**（数据见 gov.cn
/// 「国务院办公厅关于部分节假日安排的通知」）。
final List<_HolidaySpan> _holidaySpans = [
  // 2026
  _HolidaySpan('元旦节', dayNumber(DateTime(2026, 1, 1)), dayNumber(DateTime(2026, 1, 3))),
  _HolidaySpan('春节', dayNumber(DateTime(2026, 2, 15)), dayNumber(DateTime(2026, 2, 23))),
  _HolidaySpan('清明节', dayNumber(DateTime(2026, 4, 4)), dayNumber(DateTime(2026, 4, 6))),
  _HolidaySpan('劳动节', dayNumber(DateTime(2026, 5, 1)), dayNumber(DateTime(2026, 5, 5))),
  _HolidaySpan('端午节', dayNumber(DateTime(2026, 6, 19)), dayNumber(DateTime(2026, 6, 21))),
  _HolidaySpan('中秋节', dayNumber(DateTime(2026, 9, 25)), dayNumber(DateTime(2026, 9, 27))),
  _HolidaySpan('国庆节', dayNumber(DateTime(2026, 10, 1)), dayNumber(DateTime(2026, 10, 7))),
  // 2025
  _HolidaySpan('元旦节', dayNumber(DateTime(2025, 1, 1)), dayNumber(DateTime(2025, 1, 1))),
  _HolidaySpan('春节', dayNumber(DateTime(2025, 1, 28)), dayNumber(DateTime(2025, 2, 4))),
  _HolidaySpan('清明节', dayNumber(DateTime(2025, 4, 4)), dayNumber(DateTime(2025, 4, 6))),
  _HolidaySpan('劳动节', dayNumber(DateTime(2025, 5, 1)), dayNumber(DateTime(2025, 5, 5))),
  _HolidaySpan('端午节', dayNumber(DateTime(2025, 5, 31)), dayNumber(DateTime(2025, 6, 2))),
  _HolidaySpan('中秋节·国庆节', dayNumber(DateTime(2025, 10, 1)), dayNumber(DateTime(2025, 10, 8))),
];

/// 调休上班日（假期里被调成上班的周末），日历上打「班」小标记。
final Set<int> _makeupDays = {
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
};

/// 该日期所在法定节假日的名称（非假期返回 null）。
String? holidayNameOf(DateTime date) {
  final d = dayNumber(date);
  for (final s in _holidaySpans) {
    if (d >= s.startDay && d <= s.endDay) return s.name;
  }
  return null;
}

/// 该日期是否为调休上班日。
bool isMakeupWorkdayOf(DateTime date) => _makeupDays.contains(dayNumber(date));

/// 某天的农历/节日/节气信息（数据源 lunar_plus，与 6tail lunar-java 同源）。
///
/// [festivals] 是"大节日"（农历传统 + 农历其他 + 公历正式），显示在日期格子上；
/// [otherFestivals] 是"小日子"（公历纪念日等），只显示在今日信息卡。
class LunarInfo {
  const LunarInfo({
    required this.monthChinese,
    required this.dayChinese,
    required this.jieQi,
    required this.festivals,
    required this.otherFestivals,
    required this.yearGanZhi,
    required this.dayGanZhi,
    required this.shengXiao,
    required this.holidayName,
    required this.isMakeupWorkday,
  });

  final String monthChinese; // 正月
  final String dayChinese; // 初一
  final String jieQi; // 节气（无则为空串）
  final List<String> festivals; // 大节日：农历传统 + 农历其他 + 公历正式
  final List<String> otherFestivals; // 小日子：公历纪念日等
  final String yearGanZhi; // 乙巳
  final String dayGanZhi; // 日干支
  final String shengXiao; // 蛇
  final String holidayName; // 所在法定节假日名称（非假期为空串）
  final bool isMakeupWorkday; // 是否调休上班日

  bool get isLegalHoliday =>
      holidayName.isNotEmpty ||
      festivals.any(_legalHolidays.contains) ||
      jieQi == '清明';

  /// 法定节假日名称（用于信息卡标签）：优先官方区间名，其次单日节日名/清明。
  String get legalHolidayName {
    if (holidayName.isNotEmpty) return holidayName;
    if (jieQi == '清明') return '清明节';
    for (final f in festivals) {
      if (_legalHolidays.contains(f)) return f;
    }
    return '';
  }

  /// 格子里的一行小字：大节日优先 → 节气 → 农历日。
  String get shortLabel {
    if (festivals.isNotEmpty) return festivals.first;
    if (jieQi.isNotEmpty) return jieQi;
    return dayChinese;
  }

  /// 详情里的完整农历描述（含小日子）。
  String get fullDescription {
    final parts = <String>[
      '农历 $yearGanZhi年 $monthChinese$dayChinese',
      if (shengXiao.isNotEmpty) '生肖$shengXiao',
      if (dayGanZhi.isNotEmpty) '日干支$dayGanZhi',
      if (jieQi.isNotEmpty) '节气$jieQi',
      if (festivals.isNotEmpty) festivals.join('、'),
      if (otherFestivals.isNotEmpty) otherFestivals.join('、'),
    ];
    return parts.join(' · ');
  }
}

LunarInfo lunarOf(DateTime date) {
  final solar = Solar.fromYmd(date.year, date.month, date.day);
  final lunar = solar.getLunar();
  final festivals = <String>[
    ...lunar.getFestivals(), // 农历传统节日（春节/中秋…）
    ...lunar.getOtherFestivals(), // 农历其他节日（中元节/下元节/寒衣节…）
    ...solar.getFestivals(), // 公历正式节日（国庆节/元旦节/劳动节…）
  ];
  final otherFestivals = solar.getOtherFestivals(); // 公历纪念日小日子
  return LunarInfo(
    monthChinese: lunar.getMonthInChinese(),
    dayChinese: lunar.getDayInChinese(),
    jieQi: lunar.getJieQi(),
    festivals: festivals,
    otherFestivals: otherFestivals,
    yearGanZhi: lunar.getYearInGanZhi(),
    dayGanZhi: lunar.getDayInGanZhi(),
    shengXiao: lunar.getYearShengXiao(),
    holidayName: holidayNameOf(date) ?? '',
    isMakeupWorkday: isMakeupWorkdayOf(date),
  );
}
