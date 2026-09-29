// app/test/lunar_cell_label_test.dart
//
// 日历格子里那行农历小字的两条边界：
//  1. **长节日名截到 3 个字**，而信息卡用的 `shortLabel` 保持完整 —— 两个口径
//     必须分开，否则要么格子里出现 6px 的糊字，要么信息卡跟着断了半截。
//  2. **3 个字及以内一个字都不动。** 这一条是重点：用户 2026-09-29 反馈被截成
//     「财…」「地…」的正是这批 2~3 字的名字，原因是格子那一层缺 `FittedBox`，
//     不是长度上限的问题 —— 补上限时手一抖写小（比如截到 2 个字），就把没病的
//     那批一起治了，而且看图才发现得了。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/lunar_info.dart';

void main() {
  test('长节日名截到 3 个字，`shortLabel` 仍是完整的', () {
    // 2026-09-19 是「全民国防教育日」（7 个字），来自 `getOtherFestivals()`
    // —— 这一批名字就是这道上限存在的理由。
    final d = lunarOf(DateTime(2026, 9, 19));
    expect(d.shortLabel, '全民国防教育日', reason: '前置：这天确实是那个长名字');
    expect(d.cellLabel, '全民国…',
        reason: '格子放不下 7 个字；交给 FittedBox 缩会变成约 6px 的糊字');
  });

  test('3 个字及以内的名字一个字都不动', () {
    // 财神节（3 字）与廿一（2 字）—— 这两种正是用户截图里被截成「财…」「廿一」
    // 的那一批，长度上限不该碰它们。
    expect(lunarOf(DateTime(2026, 9, 3)).cellLabel, '财神节');
    expect(lunarOf(DateTime(2026, 9, 2)).cellLabel, '廿一');
    // 两个口径在短名字上必须一致（`cellLabel` 只加了一道上限，没有别的改动）。
    expect(lunarOf(DateTime(2026, 9, 3)).shortLabel, '财神节');
    expect(lunarOf(DateTime(2026, 10, 1)).cellLabel, '国庆节');
  });
}
