// app/test/lunar_info_cache_test.dart
//
// `lunarOf` 的记忆化。为什么要它：日历一屏 42 格、**每重建一次就要调 42 次**
// （实测 22~41µs/次 ⇒ 一次整屏重建 1.47ms），而屏幕上的农历在同一个月里永远不变；
// 桌面小组件那条链路一次快照更是 224 次。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/lunar_info.dart';

void main() {
  setUp(lunarCacheClear);

  test('同一个日期返回同一个实例（缓存命中）', () {
    final a = lunarOf(DateTime(2026, 10, 1));
    final b = lunarOf(DateTime(2026, 10, 1));
    expect(identical(a, b), isTrue,
        reason: '没缓存的话每次都是新造的 LunarInfo —— 42 格一屏就是 42 次日月换算');
  });

  test('缓存有上界：塞过 1024 天之后不许再涨', () {
    // 反向验证过：把超界那句 clear() 删掉，这条立刻红（1025 > 1024）。
    for (var i = 0; i < 1025; i++) {
      lunarOf(DateTime.utc(2020, 1, 1).add(Duration(days: i)));
    }
    expect(lunarCacheEntryCount(), lessThanOrEqualTo(1024));
  });

  test('缓存不许改坏值：同一个日期两次拿到的内容逐字段相同', () {
    final first = lunarOf(DateTime(2026, 2, 17));
    lunarCacheClear();
    final second = lunarOf(DateTime(2026, 2, 17));
    expect(second.monthChinese, first.monthChinese);
    expect(second.dayChinese, first.dayChinese);
    expect(second.jieQi, first.jieQi);
    expect(second.festivals, first.festivals);
    expect(second.shortLabel, first.shortLabel);
    expect(second.cellLabel, first.cellLabel);
    expect(second.fullDescription, first.fullDescription);
    expect(second.isLegalHoliday, first.isLegalHoliday);
  });

  test('键是「哪一天」而不是「哪一个 DateTime 对象」', () {
    // 本地日期与 UTC 纯日期指同一天时必须命中同一条
    // （日历网格逐格构造的是本地日期，`dateOnly` 给的是 UTC —— 混用是这一族的老坑）。
    final local = DateTime(2026, 10, 1, 23, 30);
    final utc = DateTime.utc(2026, 10, 1);
    expect(identical(lunarOf(local), lunarOf(utc)), isTrue);
  });
}
