// app/test/widget_theme_follow_test.dart
//
// 桌面小组件「跟随系统深浅色」的结构护栏。
//
// 为什么扫源码：这条能力的关键不在某一处算式，而在**四份资源 + 两个 API 分档 +
// 两个接收器**是否同时到位。少一样都不会报错，只会在某台机器上表现为「不跟随」
// 或「背景翻了字没翻」。Kotlin 侧没有可跑的测试目标，所以用与
// `widget_fixed_cards_guard_test.dart` 同一套路：剥注释/字符串后扫源码。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

String _read(String path) => File(path).readAsStringSync();

const String _kt = 'android/app/src/main/kotlin/com/daoban/shiftassistantpro';

void main() {
  test('跟随系统的四份资源在 drawable/ 与 drawable-night/ 都有', () {
    for (final name in [
      'widget_card_auto',
      'widget_page_auto',
      'widget_cell_auto',
      'widget_dot_empty',
    ]) {
      expect(File('android/app/src/main/res/drawable/$name.xml').existsSync(),
          true, reason: '缺 $name.xml');
      expect(
          File('android/app/src/main/res/drawable-night/$name.xml').existsSync(),
          true,
          reason: '缺 drawable-night/$name.xml');
    }
  });

  test('中性文字色走 setColorInt，且只在 API 31+ 用 -night', () {
    final kt = blankNonCode(_read('$_kt/WidgetRenderer.kt'));
    expect(kt.contains('setColorInt'), true, reason: '文字色必须日夜双值');
    expect(kt.contains('Build.VERSION_CODES.S'), true,
        reason: 'API < 31 没有 setColorInt，必须版本分档');
    expect(kt.contains('private fun auto('), true,
        reason: '背景也必须走同一个 API 分档 —— 只翻背景不翻字比不翻更糟');
    // 剥壳之后只许剩：helper 的兜底 1 处 + 3 处纯主色/班次色的字。
    expect(RegExp(r'\.setTextColor\(').allMatches(kt).length,
        lessThanOrEqualTo(4),
        reason: '中性色不许再走裸 setTextColor —— 那样系统切色不会跟');
  });

  test('manifest 不再声明 CONFIGURATION_CHANGED', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    expect(manifest.contains('CONFIGURATION_CHANGED'), false,
        reason: '隐式广播收不到，留着是死代码');
  });

  test('MainActivity 保留运行时接收器并成对注销', () {
    final kt = blankNonCode(_read('$_kt/MainActivity.kt'));
    expect(kt.contains('Intent.ACTION_CONFIGURATION_CHANGED'), true);
    expect(kt.contains('registerReceiver'), true);
    expect(kt.contains('unregisterReceiver'), true);
  });
}
