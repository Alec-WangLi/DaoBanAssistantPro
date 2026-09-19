// `WidgetTier.pick` 的阈值护栏。
//
// ⚠️ `WidgetTier.pick` **在 Kotlin 侧**（`app/android/app/src/main/kotlin/com/daoban/
// shiftassistantpro/WidgetTier.kt`），Dart 测不到它本人。所以这条测试**读它的源码**
// 把四个常量抠出来，在 Dart 里重跑同一段判定 —— 有人改了阈值就会红。
//
// 为什么值得这么绕：上一版的分档只有三个阈值，而真机高度有七个可达值，结果三个版式
// 被摊到七个高度上、两个版式被拉伸 —— 那正是这一轮返工的全部起因。阈值是纯数字、
// 没有编译期保护，而这套「扫源码」的套路仓库里已有先例
// （`widget_layout_whitelist_test.dart`）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 从 `WidgetTier.kt` 里抠一个 `const val X = 数字`。
int _const(String src, String name) {
  final m = RegExp('const val $name\\s*=\\s*(\\d+)').firstMatch(src);
  expect(m, isNotNull, reason: 'WidgetTier.kt 里找不到 $name —— 是不是改名了？');
  return int.parse(m!.group(1)!);
}

void main() {
  late String src;
  late int compactMax, list3Max, list5Max, fortnightMin, gridMinWidth;

  setUpAll(() {
    final f = File(
      'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetTier.kt',
    );
    expect(f.existsSync(), true, reason: '找不到 ${f.path} —— 测试的工作目录应当是 app/');
    src = f.readAsStringSync();
    compactMax = _const(src, 'COMPACT_MAX_HEIGHT_DP');
    list3Max = _const(src, 'LIST3_MAX_HEIGHT_DP');
    list5Max = _const(src, 'LIST5_MAX_HEIGHT_DP');
    fortnightMin = _const(src, 'FORTNIGHT_MIN_HEIGHT_DP');
    gridMinWidth = _const(src, 'GRID_MIN_WIDTH_DP');
  });

  /// 与 Kotlin 侧 `pick` 逐字同构的判定。
  String pick(int w, int h) {
    if (h >= fortnightMin && w >= gridMinWidth) return 'GRID_FORTNIGHT';
    if (h >= list5Max && w >= gridMinWidth) return 'GRID_WEEK';
    if (h < compactMax) return 'LIST_COMPACT';
    if (h < list3Max) return 'LIST_3';
    if (h < list5Max) return 'LIST_5';
    return 'LIST_5'; // 高够但宽不够：降级为最长列表
  }

  test('四个边界各两侧', () {
    expect(pick(328, compactMax - 1), 'LIST_COMPACT');
    expect(pick(328, compactMax), 'LIST_3');
    expect(pick(328, list3Max - 1), 'LIST_3');
    expect(pick(328, list3Max), 'LIST_5');
    expect(pick(328, list5Max - 1), 'LIST_5');
    expect(pick(328, list5Max), 'GRID_WEEK');
    expect(pick(328, fortnightMin - 1), 'GRID_WEEK');
    expect(pick(328, fortnightMin), 'GRID_FORTNIGHT');
  });

  test('宽度闸门：299dp 不上网格、300dp 上网格', () {
    expect(pick(gridMinWidth - 1, 633), 'LIST_5');
    expect(pick(gridMinWidth, 633), 'GRID_FORTNIGHT');
    expect(pick(gridMinWidth - 1, 348), 'LIST_5');
    expect(pick(gridMinWidth, 348), 'GRID_WEEK');
  });

  test('七档真机实测值逐一落对（2026-09-19 用户拖动演示）', () {
    const measured = <int, String>{
      63: 'LIST_COMPACT',
      158: 'LIST_3',
      253: 'LIST_5',
      348: 'GRID_WEEK',
      443: 'GRID_WEEK',
      538: 'GRID_FORTNIGHT',
      633: 'GRID_FORTNIGHT',
    };
    measured.forEach((heightDp, expected) {
      expect(pick(328, heightDp), expected, reason: '实测 ${heightDp}dp 应当落在 $expected');
    });
  });

  test('阈值取在实测值的相邻中点（任一档离边界至少 40dp）', () {
    expect(compactMax, 110); // (63+158)/2
    expect(list3Max, 205); // (158+253)/2
    expect(list5Max, 300); // (253+348)/2
    expect(fortnightMin, 490); // (443+538)/2
    expect(gridMinWidth, 300);
  });
}
