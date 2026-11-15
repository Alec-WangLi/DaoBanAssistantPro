// app/test/holiday_table_test.dart
//
// 法定节假日表的三件事：
//   1. **仓库里那份 `holidays.json` 必须能被 App 解析** —— 它是自动更新的数据源，
//      手改坏一个逗号，用户那边只会「没有更新」，这里要当场红。
//   2. 坏数据整份拒绝：日期越界 / 首尾颠倒 / 区间重叠都不许进（旧表继续用）。
//   3. 装上新表后，`lunarOf()` 出来的 `holidayName` / `isMakeupWorkday` 必须跟着变 ——
//      它们是**带缓存**的，不重新算就等于没更新。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/holiday_table.dart';
import 'package:shiftassistantpro/domain/lunar_info.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

/// 一份最小可用的远程数据（2027 年元旦）。
String _json({
  Object? schema = 1,
  List<Map<String, Object?>>? years,
}) =>
    jsonEncode({
      'schema': schema,
      'years': years ??
          [
            {
              'year': 2027,
              'spans': [
                {'name': '元旦节', 'start': '2027-01-01', 'end': '2027-01-03'},
              ],
              'makeup': ['2027-01-04'],
            }
          ],
    });

void main() {
  // 全局装表是进程级的，别把别的用例带偏。
  tearDown(() => installHolidayTable(builtinHolidayTable));

  group('仓库里的 holidays.json', () {
    final file = File('../holidays.json');

    test('文件存在且能解析', () {
      expect(file.existsSync(), isTrue,
          reason: '仓库根缺 holidays.json —— 自动更新的第一个通道就没了');
      final table = HolidayTable.parse(file.readAsStringSync());
      expect(table.years, containsAll(<int>[2025, 2026]));
      expect(table.latestYear, greaterThanOrEqualTo(2026));
    });

    test('与内置表逐年一致（远程这份不是另一套数据）', () {
      final remote = HolidayTable.parse(file.readAsStringSync());
      final merged = builtinHolidayTable.mergedWith(remote);
      for (final day in <DateTime>[
        DateTime(2026, 1, 1),
        DateTime(2026, 2, 15),
        DateTime(2026, 10, 1),
        DateTime(2025, 10, 8),
      ]) {
        expect(merged.holidayNameOf(dayNumber(day)),
            builtinHolidayTable.holidayNameOf(dayNumber(day)),
            reason: '$day 的假期名两边对不上');
      }
      expect(builtinHolidayTable.isMakeup(dayNumber(DateTime(2026, 10, 10))),
          isTrue);
      expect(merged.isMakeup(dayNumber(DateTime(2026, 10, 10))), isTrue,
          reason: '调休日在合并之后丢了 —— 日历上的「班」标记会消失');
    });
  });

  group('解析的边界', () {
    test('正常数据', () {
      final t = HolidayTable.parse(_json());
      expect(t.holidayNameOf(dayNumber(DateTime(2027, 1, 2))), '元旦节');
      expect(t.holidayNameOf(dayNumber(DateTime(2027, 1, 4))), isNull,
          reason: '假期之外的日期不该命中');
      expect(t.isMakeup(dayNumber(DateTime(2027, 1, 4))), isTrue);
    });

    test('schema 不认识 → 拒绝', () {
      expect(() => HolidayTable.parse(_json(schema: 2)),
          throwsA(isA<FormatException>()));
    });

    test('日期格式不对 → 拒绝', () {
      expect(
          () => HolidayTable.parse(_json(years: [
                {
                  'year': 2027,
                  'spans': [
                    {'name': '元旦节', 'start': '2027-1-1', 'end': '2027-01-03'},
                  ],
                }
              ])),
          throwsA(isA<FormatException>()));
    });

    test('2 月 30 日这种「日历上不存在」的日期 → 拒绝', () {
      expect(
          () => HolidayTable.parse(_json(years: [
                {
                  'year': 2027,
                  'spans': [
                    {'name': '春节', 'start': '2027-02-30', 'end': '2027-03-02'},
                  ],
                }
              ])),
          throwsA(isA<FormatException>()));
    });

    test('首尾颠倒 → 拒绝', () {
      expect(
          () => HolidayTable.parse(_json(years: [
                {
                  'year': 2027,
                  'spans': [
                    {'name': '元旦节', 'start': '2027-01-05', 'end': '2027-01-01'},
                  ],
                }
              ])),
          throwsA(isA<FormatException>()));
    });

    test('区间重叠 → 拒绝（数据自己打架时日历上说不清是哪天）', () {
      expect(
          () => HolidayTable.parse(_json(years: [
                {
                  'year': 2027,
                  'spans': [
                    {'name': '元旦节', 'start': '2027-01-01', 'end': '2027-01-03'},
                    {'name': '春节', 'start': '2027-01-03', 'end': '2027-01-05'},
                  ],
                }
              ])),
          throwsA(isA<FormatException>()));
    });

    test('年份越界 → 拒绝', () {
      expect(
          () => HolidayTable.parse(_json(years: [
                {
                  'year': 1999,
                  'spans': [
                    {'name': '元旦节', 'start': '1999-01-01', 'end': '1999-01-03'},
                  ],
                }
              ])),
          throwsA(isA<FormatException>()));
    });
  });

  group('合并', () {
    test('远程只覆盖它自己那几年，别的年份保留内置的', () {
      final merged =
          builtinHolidayTable.mergedWith(HolidayTable.parse(_json()));
      expect(merged.latestYear, 2027);
      expect(merged.holidayNameOf(dayNumber(DateTime(2026, 10, 1))), '国庆节',
          reason: '2026 的内置数据不能因为远程只给了 2027 就丢');
      expect(merged.holidayNameOf(dayNumber(DateTime(2027, 1, 1))), '元旦节');
    });

    test('远程改写同一年时整年替换（不是逐条叠加）', () {
      final remote = HolidayTable.parse(jsonEncode({
        'schema': 1,
        'years': [
          {
            'year': 2026,
            'spans': [
              // 故意只留一段：合并后 2026 的其余假期必须消失，
              // 否则「拆区间 / 挪调休日」这类真实改动会留下孤儿条目。
              {'name': '国庆节', 'start': '2026-10-01', 'end': '2026-10-08'},
            ],
            'makeup': <String>[],
          }
        ],
      }));
      final merged = builtinHolidayTable.mergedWith(remote);
      expect(merged.holidayNameOf(dayNumber(DateTime(2026, 2, 16))), isNull,
          reason: '2026 已被整年替换，春节不该还在');
      expect(merged.isMakeup(dayNumber(DateTime(2026, 10, 10))), isFalse,
          reason: '2026 已被整年替换，旧的调休日必须一起消失');
      expect(merged.holidayNameOf(dayNumber(DateTime(2025, 10, 1))), '中秋节·国庆节',
          reason: '2025 没被覆盖，必须留着');
    });
  });

  group('装上之后', () {
    test('lunarOf 的假期名与「班」标记跟着变（缓存要清）', () {
      final day = DateTime(2026, 12, 31);
      expect(lunarOf(day).holidayName, isEmpty,
          reason: '前置：内置表里这一天不是假期');

      installHolidayTable(builtinHolidayTable.mergedWith(HolidayTable.parse(
          jsonEncode({
        'schema': 1,
        'years': [
          {
            'year': 2026,
            'spans': [
              {'name': '元旦节', 'start': '2026-12-31', 'end': '2026-12-31'},
            ],
          }
        ],
      }))));

      expect(holidayNameOf(day), '元旦节');
      expect(lunarOf(day).holidayName, '元旦节',
          reason: '农历缓存没清 —— 装上新表之后界面还是旧的');
    });
  });
}
