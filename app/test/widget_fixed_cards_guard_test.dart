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

  // 这条是 2026-09-29 用户反馈的护栏：把「前夜改成休班之后，桌面小组件的字**重影**」
  // （OPPO / vivo 等机型，开发机上复现不出来）。
  //
  // 根因在宿主的 **reapply** 路径：桌面收到同一个布局 id 的 RemoteViews 时，不会重新
  // inflate，而是把整串动作在**已经在的那棵视图树**上重放一遍，而 `AppWidgetHostView`
  // **不会**替你清空子视图。于是每渲染一次就往同一个容器里再 addView 一个格子，
  // 分子视图在 FrameLayout / LinearLayout 里**叠在一起**（格子根是 match_parent，
  // 不是把后者挤开）。内容一样时看不出来（只是稍微糊一点、胶囊深一档），一旦某格的
  // 内容变了 —— 比如按天改班把「前夜」改成「休班」—— 旧层的字就露出来了。
  //
  // 为什么只有部分机型中招：新一些的 AOSP / 启动器会**回收**已加进去的子视图
  // （`canRecycleView`，Android 12 起进了 CTS），刚好把这个缺陷盖住；旧框架与厂商
  // 分叉会老老实实再加一个。所以「开发机上没问题」**不能**当作这条不存在。
  //
  // `RemoteViews.addView` 的官方文档写的就是这条：宿主可能回收布局，
  // 要用 `removeAllViews(int)` 清掉已有的子视图。
  test('每处 addView 的容器都先被 removeAllViews 清过', () {
    final kt = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
    // 取每处 `addView(<容器>, ...)` 的第一个实参（容器表达式）。
    final containers = RegExp(r'addView\(([^,]+),\s')
        .allMatches(kt)
        .map((m) => m.group(1)!.trim())
        .toList();
    // 先确认这条护栏自己没瞎：扫不到东西时它必须红，而不是静默通过。
    expect(containers.length, greaterThanOrEqualTo(4),
        reason: '只扫到 ${containers.length} 处 addView —— 要么渲染器被重构了，'
            '要么这条正则匹配不到新的写法，两种情况都要人来重新对一遍');
    for (final c in containers) {
      final add = kt.indexOf('addView($c,');
      final clear = kt.indexOf('removeAllViews($c)');
      expect(add, greaterThanOrEqualTo(0),
          reason: '正则取到的容器名 $c 在文件里找不到对应的 addView 调用 —— '
              '这条护栏自己跟源码对不上了，先修它');
      // **顺序是这条不变量的一半，别只查「出现过」。** 先加后清同样是坏的：
      // 那会把刚填进去的子视图又清掉，槽位渲染成空的。而且写成「顺序反了」时
      // 「文件里出现过 removeAllViews(x)」照样成立 —— 那种检查抓不到它。
      expect(clear, greaterThanOrEqualTo(0),
          reason: '容器 $c 被 addView 塞了子视图，却从没被 removeAllViews 清过 —— '
              '宿主 reapply 时每刷一次就叠一层，症状是内容变化后出现重影');
      expect(clear, lessThan(add),
          reason: '容器 $c 的 removeAllViews 出现在了它的 addView **之后** —— '
              '先加后清会把刚填进去的那份又清掉，槽位渲染成空的');
    }
  });
  // 锚点是**每个实例一份**的落盘状态（「这张卡现在翻到哪个月」）。它的失效方式是
  // **静默**的：删卡时不清，系统把 widgetId 复用给下一张卡，新卡一上来就停在上一张
  // 卡翻到的月份上 —— 不报错、不崩，只是「我的小组件怎么是 11 月？」。
  //
  // 这条只能扫源码：Kotlin 在这个仓库里没有可跑的测试目标（真机是唯一的眼睛，
  // 所以它同时出现在实施计划的真机清单里）。
  test('翻月锚点：删卡要清、键名只有一处拼', () {
    final base = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/ShiftWidgetBase.kt');
    expect(base.contains('clearMonthAnchors'), true,
        reason: 'ShiftWidgetBase.onDeleted 必须清掉被删实例的月份锚点 —— '
            'widgetId 会被系统复用，不清就是「新卡片继承上一张卡的月份」');

    final store = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetStore.kt');
    expect(store.contains(r'"month_$widgetId"'), true,
        reason: '锚点的键名必须由一处拼出来（month_<widgetId>），'
            '读写各拼一遍迟早会出现「写的和读的不是一个键」这种静默失效');
  });
}
