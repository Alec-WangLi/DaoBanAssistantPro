// 三张固定卡的结构护栏 —— 扫源码，把「编译期没有保护」的三处约定钉住。
//
// 为什么需要它：这一版把「尺寸分档」换成了「三张各自注册的固定卡」，而三处关键约定
// 都是字符串/数字，编译器一点忙都帮不上：
//   ① 月历 42 个槽位的 id 是 `wg_m_slot1..42`，Kotlin 侧靠
//      `getIdentifier("wg_m_slot${i + 1}")` 拼名字 —— 差一个下标就**静默**空掉一格，
//      编译、构建、logcat 全都不报错（`getIdentifier` 返回 0 时 setViewVisibility
//      静默失败）。这一条是审查专门点名的推理陷阱：**「构建过了」不能证明槽位 id 齐全**。
//   ② manifest 里必须有四个 receiver，少一个那张卡在 release（开 R8）里整个消失。
//   ③ 三份 `*_info.xml` 的 `minWidth`/`minHeight` 必须与 `targetCellWidth/Height`
//      同源（Android 12 以下只认前者，折算公式 `70n - 30`）。
//
// 上一版的同类护栏（`widget_tier_thresholds_test.dart`）随 `WidgetTier.kt` 一起删掉了，
// 这一份是它的等价物：同样走「扫源码 + 在 Dart 里重跑同一套判定」的套路
// （仓库里 `widget_layout_whitelist_test.dart` 是这套路的先例）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final f = File(path);
  expect(f.existsSync(), true, reason: '找不到 $path —— 测试的工作目录应当是 app/');
  return f.readAsStringSync();
}

/// Android 12 以下的折算公式：n 个格子对应 `70n - 30` dp。
int _cellsToDp(int n) => 70 * n - 30;

void main() {
  test('月历 42 个槽位 id 齐全、连续、唯一，且与 Kotlin 拼名规则逐字一致', () {
    final xml = _read('android/app/src/main/res/layout/widget_month_card.xml');
    final ids = RegExp(r'@\+id/wg_m_slot(\d+)')
        .allMatches(xml)
        .map((m) => int.parse(m.group(1)!))
        .toList()
      ..sort();
    expect(ids.length, 42, reason: '月历是 6 行 × 7 列 = 42 格');
    expect(ids.toSet().length, 42, reason: '槽位 id 有重复');
    expect(ids, List.generate(42, (i) => i + 1));

    final kt = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
    // 这条检查**故意**脆：循环变量一改名（i → slot）它就会红，而那是假警报 ——
    // 拼名规则没变，只是承接它的字面量换了写法。**不要**改成宽容的正则去消这个红：
    // `"wg_m_slot${i + 1}"` 是它与布局 `wg_m_slot1..42` 逐字对齐的唯一凭据。
    expect(kt.contains(r'"wg_m_slot${i + 1}"'), true,
        reason: 'Kotlin 的槽位名拼法必须与布局里的 id 逐字一致');

    final m = RegExp(r'REQ_SLOTS_PER_WIDGET\s*=\s*(\d+)').firstMatch(kt);
    expect(m, isNotNull, reason: 'WidgetRenderer.kt 里找不到 REQ_SLOTS_PER_WIDGET');
    expect(int.parse(m!.group(1)!), greaterThanOrEqualTo(43),
        reason: 'Root + 42 格 = 43 个槽位；基数不够时末格会进位撞上下一个实例的 Root');
  });

  test('三张卡的 provider 与刷新广播都在 manifest 里显式声明', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    for (final cls in [
      '.WeekStripWidgetProvider',
      '.TodayCardWidgetProvider',
      '.MonthWidgetProvider',
      '.WidgetRefreshReceiver',
    ]) {
      expect(manifest.contains('android:name="$cls"'), true,
          reason: 'release 开 R8，只被代码引用的类会被裁掉 —— $cls 必须显式声明');
    }
    for (final info in [
      'widget_week_strip_info',
      'widget_today_info',
      'widget_month_info',
    ]) {
      expect(manifest.contains('@xml/$info'), true,
          reason: '缺 $info 的 meta-data 时那张卡拿不到 appwidget-provider 声明');
    }
  });

  test('三份 info.xml：不可拉伸，且 min 尺寸与 targetCell 同源（70n-30）', () {
    // (文件, 格宽, 格高)
    const cards = [
      ('widget_week_strip_info.xml', 4, 1),
      ('widget_today_info.xml', 4, 3),
      ('widget_month_info.xml', 4, 5),
    ];
    for (final (file, w, h) in cards) {
      final xml = _read('android/app/src/main/res/xml/$file');
      expect(xml.contains('android:resizeMode="none"'), true,
          reason: '$file 必须是固定尺寸 —— 这是本轮重做的核心');
      expect(xml.contains('android:targetCellWidth="$w"'), true,
          reason: '$file 的 targetCellWidth 应当是 $w');
      expect(xml.contains('android:targetCellHeight="$h"'), true,
          reason: '$file 的 targetCellHeight 应当是 $h');
      expect(xml.contains('android:minWidth="${_cellsToDp(w)}dp"'), true,
          reason: '$file 的 minWidth 应当是 ${_cellsToDp(w)}dp（Android 12 以下只认它）');
      expect(xml.contains('android:minHeight="${_cellsToDp(h)}dp"'), true,
          reason: '$file 的 minHeight 应当是 ${_cellsToDp(h)}dp');
    }
  });
}
