import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:lunar_plus/lunar.dart';

import 'holiday_table.dart';
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

/// 日历格子里农历那一行最多显示几个字（见 [LunarInfo.cellLabel]）。
///
/// 3 是按格子的实际内容宽（400dp 手机上约 44dp）与设计字号（`tinyLabel` 11 ×
/// 格子缩放上限 1.25 ≈ 13.75）算出来的，不要凭感觉调大。
///
/// ⚠️ **它是个「格子几何」的函数，却住在领域层** —— 领域层看不见
/// `calendar_screen.dart` 里那些与之咬合的常量（`_cellDesignH` / `_cellMaxScale` /
/// `_chipMinContentW`）。所以**改动任何一处格子几何或那一档字号令牌，都要回来重算
/// 这个数**，否则它会无声地失准：调大了白缩（字被缩得没必要地小）、调小了字又
/// 放不下。之所以仍放在这里而不是做成界面层的参数：截断的结果是纯数据，放在这一层
/// 才能被 `lunar_cell_label_test.dart` 直接断言。
const int _cellLabelMaxChars = 3;

/// 当前生效的法定节假日表：内置表，或被远程 `holidays.json` 按年份覆盖过的版本。
///
/// **为什么是可变状态**（2026-11-15）：这张表现在会自动更新（见 `core/holiday_sync.dart`）。
/// 界面上所有读日期的地方仍然走同步的 [lunarOf] —— 表是**在启动时和刷新后整体换掉**
/// 的，不是每次查询都去问网络，所以调用点一个字都不用改。
HolidayTable _installedHolidayTable = builtinHolidayTable;

/// 当前生效的节假日表（只读用途：界面显示「已覆盖至哪一年」）。
HolidayTable get installedHolidayTable => _installedHolidayTable;

/// 装上新的表并**清掉农历缓存** —— `LunarInfo` 里存着 `holidayName` /
/// `isMakeupWorkday` 的算好结果，不清的话日历上会继续显示旧表。
///
/// 调用方随后要自己通知界面重建（见 `core/holiday_sync.dart` 的
/// `holidayDataRevision`）。
void installHolidayTable(HolidayTable table) {
  _installedHolidayTable = table;
  lunarCacheClear();
}

/// 该日期所在法定节假日的名称（非假期返回 null）。
String? holidayNameOf(DateTime date) =>
    _installedHolidayTable.holidayNameOf(dayNumber(date));

/// 该日期是否为调休上班日。
bool isMakeupWorkdayOf(DateTime date) =>
    _installedHolidayTable.isMakeup(dayNumber(date));

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

  /// 日历**格子**里那一行小字：在 [shortLabel] 之上多一道长度上限。
  ///
  /// 格子的内容宽只有 44dp 上下（400dp 的手机），设计尺寸下装得下 3 个字。而
  /// [festivals] 里混着 `getOtherFestivals()` 那些很长的名字（「全民国防教育日」
  /// 7 个字）—— 格子那一层的 `FittedBox` 会把它缩到 0.46 倍、约 6px，**完整，
  /// 但没人看得见**，比截断更糟。所以在这里截到 3 个字并补省略号。
  ///
  /// **3 个字及以内（`元宵` / `财神节` / `廿一`，也就是绝大多数）一个字都不动。**
  /// 2026-09-29 用户反馈被截成「财…」「地…」的正是这一批 —— 那是格子那一层缺
  /// `FittedBox` 造成的，与这道上限无关，别把两者混起来。
  ///
  /// 信息卡有地方，用的一直是完整的 [shortLabel]。
  String get cellLabel {
    final s = shortLabel;
    if (s.characters.length <= _cellLabelMaxChars) return s;
    return '${s.characters.take(_cellLabelMaxChars)}…';
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

/// `lunarOf` 的缓存上界。到了就**整个清掉**，不做 LRU —— 请求天然按天聚集
/// （一屏 42 天、一次快照 224 天），清一次最多多付一屏的代价；而 LRU 要多一套
/// 要维护、要测的东西。
const int _lunarCacheMax = 1024;

/// `lunarOf` 的记忆化。**键 = [dayNumber]（自 epoch 的天数）**。
///
/// `LunarInfo` 与语言无关（节日名来自 `lunar_plus` 与内置的官方放假表，
/// `shortLabel` / `cellLabel` / `fullDescription` 都不读 `L10n`），所以键里不需要语言。
final Map<int, LunarInfo> _lunarCache = <int, LunarInfo>{};

@visibleForTesting
int lunarCacheEntryCount() => _lunarCache.length;

/// 清空农历缓存。**生产代码也会调它**（[installHolidayTable]）——
/// 节假日表换了之后，缓存里那些算好的 `holidayName` 必须作废。
void lunarCacheClear() => _lunarCache.clear();

/// 某一天的农历信息。**带缓存**（见 [_lunarCache] 的说明）。
LunarInfo lunarOf(DateTime date) {
  final key = dayNumber(date);
  final hit = _lunarCache[key];
  if (hit != null) return hit;
  if (_lunarCache.length >= _lunarCacheMax) _lunarCache.clear();
  final info = _computeLunar(date);
  _lunarCache[key] = info;
  return info;
}

/// 真正算一次（原样搬过来，一个字没改）。
LunarInfo _computeLunar(DateTime date) {
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
