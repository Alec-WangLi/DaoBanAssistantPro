// app/test/widget_cell_block_guard_test.dart
//
// 桌面小组件那几张卡底的**结构不变量**。Kotlin 在这个仓库里没有可跑的测试目标
// （真机是唯一的眼睛），所以这一族护栏只能**扫源码**：它们证明不了「画出来好不好
// 看」，只证明「该在的东西都在、该成对的都成对、两个方向的状态都设满了」。
//
// 与 `widget_fixed_cards_guard_test.dart` 同一套路、同一份家法。
//
// ⚠️ 这一族是**分任务长大**的（见实施计划）：本文件在任务 1 只守资源，
// 任务 2 加月历格那三条，任务 3 扩到周条并把下界提到 6，任务 4 提到 7。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 读一个相对 `app/` 的文件（Dart 测试的工作目录就是 `app/`）。
String _read(String rel) {
  final f = File(rel);
  expect(f.existsSync(), true,
      reason: '$rel 不存在 —— 要么实现还没做，要么这条护栏自己跟源码对不上了');
  return f.readAsStringSync();
}

void main() {
  test('四张资源成对存在：格子卡底与页面底，浅深各一', () {
    for (final base in ['widget_cell', 'widget_page']) {
      for (final tier in ['light', 'dark']) {
        final f = File('android/app/src/main/res/drawable/${base}_$tier.xml');
        expect(f.existsSync(), true,
            reason: '${base}_$tier.xml 不在 —— 少一张就是**某一档静默没有底**'
                '（另一档看不出来，真机上只有把系统切过去才会现形）');
      }
    }
  });

  test('页面底必须不透明（97% 会跌破 AA）', () {
    for (final tier in ['light', 'dark']) {
      final src = _read('android/app/src/main/res/drawable/widget_page_$tier.xml');
      final colors = RegExp(r'#([0-9A-Fa-f]{8})')
          .allMatches(src)
          .map((m) => m.group(1)!.toUpperCase())
          .toList();
      // 自证：扫不到色值时这条护栏是句空话，必须红。
      expect(colors.length, greaterThanOrEqualTo(2),
          reason: '页面底应当有渐变的两端色 —— 只扫到 ${colors.length} 个 8 位色值，'
              '要么资源被改回了单色，要么这条正则跟源码对不上了');
      for (final c in colors) {
        expect(c.substring(0, 2), 'FF',
            reason: '页面底 $tier 档有一个半透明端（#$c）—— 叠黑壁纸时 wg_muted '
                '只有 4.33:1，跌破 AA 4.5。这个数在 spec §5 里算过，别改成 97%');
      }
    }
  });

  test('两张 cell 布局都有「今天」那块 ImageView，且 id 与 Kotlin 引用逐字一致', () {
    void check(String layout, String id) {
      final kt = _read(
          'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
      final xml = _read('android/app/src/main/res/layout/$layout.xml');
      expect(RegExp('android:id="\\@\\+id/$id"').hasMatch(xml), true,
          reason: '$layout.xml 里没有 $id —— 块画不出来，而且**不报错**');
      // 两个方向都要设满：只 setImageViewBitmap 不 setViewVisibility(GONE)，
      // 翻月 / 翻周之后非今天那一格会挂着上一次的块（宿主 reapply 只重放新动作）。
      expect(kt.contains('R.id.$id'), true,
          reason: 'WidgetRenderer.kt 里没引用 $id —— 布局改了、Kotlin 没跟');
      expect(kt.contains('R.id.$id, android.view.View.GONE'), true,
          reason: '$id 没有显式 GONE 那一支 —— 块会残留到别的格子上');
    }

    check('widget_month_cell', 'wg_mc_block');
    check('widget_strip_cell', 'wg_sc_block');
  });

  test('「今天」块的位图尺寸来自 AppWidgetOptions，不是写死的', () {
    final kt = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
    expect(kt.contains('WidgetChip.block('), true, reason: '一处都没用上块原语');
    for (final fn in ['monthCellPx', 'stripCellPx']) {
      final i = kt.indexOf('private fun $fn');
      expect(i, greaterThanOrEqualTo(0), reason: '$fn 不见了');
      final body = kt.substring(i, kt.indexOf('\n    }', i));
      expect(body.contains('OPTION_APPWIDGET_MIN_WIDTH'), true,
          reason: '$fn 没读 AppWidgetOptions —— 尺寸写死的话，5 行月与 6 行月'
              '（格子高差约 18%）里必有一档的圆角被拉变形、四角露出白卡的角尖');
      expect(body.contains('OPTION_APPWIDGET_MIN_HEIGHT'), true,
          reason: '同上，高度那一路');
    }
  });

  test('今天那格的字都过 onSolidInk', () {
    final kt = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
    expect(kt.contains('private fun onSolidInk'), true, reason: 'onSolidInk 不见了');
    // ⚠️ 匹配的是**调用点**（`onSolidInk(context, `），不是 `onSolidInk(` ——
    // 后者会把**函数定义**那一行也算进去（`onSolidInk(context: Context, …)`），
    // 阈值就整体低一格，于是「少了一处分支」正好卡在边界上溜过去。
    final uses = RegExp(r'onSolidInk\(context, ').allMatches(kt).length;
    // ⚠️ 这是一个**下界**（不是精确计数）：它抓的是「漏了一处分支」。
    // 月格三处（日数字 / 农历 / 胶囊简称）+ 周条三处（周几 / 日数字 / 简称）＝ 6。
    // 少一处就是「假期撞上今天时红字压在实心块上读不出来」这类情况。
    expect(uses, greaterThanOrEqualTo(6),
        reason: 'onSolidInk 的**调用点**只有 $uses 处 —— 月格三处 + 周条三处应当凑齐 6 处');
  });
}
