// app/test/l10n_dateformat_cache_test.dart
//
// `L10n` 里那几个日期格式化器的**记忆化**。
//
// 为什么要它：`DateFormat(pattern, locale)` 每次构造都要把模式串解析一遍，
// 而这几处是**每次重建都要调**的 —— 日历一屏就有月标题、完整日期、
// 每一格的日期串；`monthShort` 还在「本月统计」那一行里按班次种类循环。
//
// 与 `lunar_info_cache_test.dart` 同一套路：键是「模式 + 语言」，
// 无上界（模式是代码里的常量，一共就那几条）。
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
  });
  setUp(() {
    L10n.locale = 'zh';
    L10n.debugDateFormatCacheClear();
  });

  test('同一个模式 + 同一个语言：只造一个 DateFormat', () {
    L10n.yearMonth(DateTime(2026, 10, 1));
    L10n.yearMonth(DateTime(2026, 11, 1));
    expect(L10n.debugDateFormatCacheSize(), 1,
        reason: '没缓存的话每调一次就解析一次模式串');
  });

  test('换了语言就是另一个实例', () {
    L10n.yearMonth(DateTime(2026, 10, 1));
    L10n.locale = 'en';
    L10n.yearMonth(DateTime(2026, 10, 1));
    expect(L10n.debugDateFormatCacheSize(), 2,
        reason: '中英是两套词表，混用会让英文界面出现中文月名');
  });

  test('不同的模式各占一条', () {
    L10n.yearMonth(DateTime(2026, 10, 1));
    L10n.monthDay(DateTime(2026, 10, 1));
    expect(L10n.debugDateFormatCacheSize(), 2);
  });

  test('缓存不许改坏值：清掉再拿，串逐字相同', () {
    final String a = L10n.yearMonth(DateTime(2026, 10, 1));
    L10n.debugDateFormatCacheClear();
    final String b = L10n.yearMonth(DateTime(2026, 10, 1));
    expect(b, a);
    expect(a, '2026年10月');
  });
}
