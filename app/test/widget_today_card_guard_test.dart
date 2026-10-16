// app/test/widget_today_card_guard_test.dart
//
// 今日卡那几行的**结构不变量**。Kotlin 在这个仓库里没有可跑的测试目标（真机是
// 唯一的眼睛），所以这一族护栏只能**扫源码**：它们证明不了「画出来好不好看」，
// 只证明「该在的东西都在、该走快照的没写死」。
//
// 与 `widget_cell_block_guard_test.dart` / `widget_fixed_cards_guard_test.dart`
// 同一套路、同一份家法。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';

String _read(String rel) {
  final f = File(rel);
  expect(f.existsSync(), true,
      reason: '$rel 不存在 —— 要么实现还没做，要么这条护栏自己跟源码对不上了');
  return f.readAsStringSync();
}

/// 某个 id 那个视图上写的 `android:textSize="…dp"`。找不到就返回 null
/// （由调用点给出「护栏自己跟源码对不上」的理由，而不是在解析里抛）。
double? _textSizeDp(String xml, String id) {
  final i = xml.indexOf('@+id/$id');
  if (i < 0) return null;
  final end = xml.indexOf('/>', i);
  final block = xml.substring(i, end < 0 ? xml.length : end);
  final m = RegExp(r'android:textSize="([0-9.]+)dp"').firstMatch(block);
  return m == null ? null : double.parse(m.group(1)!);
}

/// 把注释**剥成等长空格**（保留行号、不改变索引），字符串字面量原样留着。
///
/// 必须剥：注释里提到一句「其他班组」不是违规，而注释是解释规则的地方 ——
/// 不剥的话这条护栏会逼着后人不敢在注释里写中文。与 `haptics_guard_test.dart`
/// / `design_tokens_test.dart` 同一套做法。
String _stripComments(String s) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    // 字符串字面量（含 Kotlin 的 """）整段照抄
    if (s[i] == '"') {
      out.write('"');
      i++;
      while (i < s.length && s[i] != '"') {
        if (s[i] == '\\' && i + 1 < s.length) {
          out.write(s[i]);
          i++;
        }
        out.write(s[i]);
        i++;
      }
      if (i < s.length) {
        out.write('"');
        i++;
      }
      continue;
    }
    if (i + 1 < s.length && s[i] == '/' && s[i + 1] == '/') {
      while (i < s.length && s[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (i + 1 < s.length && s[i] == '/' && s[i + 1] == '*') {
      while (i < s.length && !(s[i] == '*' && i + 1 < s.length && s[i + 1] == '/')) {
        out.write(s[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < s.length) {
        out.write('  ');
        i += 2;
      }
      continue;
    }
    out.write(s[i]);
    i++;
  }
  return out.toString();
}

void main() {
  test('今日卡布局有那三个新视图（其他班组标签 / 班次备注 / 本月统计）', () {
    final xml = _read('android/app/src/main/res/layout/widget_today_card.xml');
    for (final id in ['wg_tc_crew_label', 'wg_tc_note', 'wg_tc_tally']) {
      expect(xml.contains('@+id/$id'), true, reason: '$id 不在布局里');
    }
  });

  test('渲染侧读的是快照字段，不是写死的文案', () {
    final kt = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
    expect(kt.contains('d.shiftNote'), true,
        reason: '班次备注要走按日烘焙的 days[].shiftNote —— 挂 todayCard 的话'
            '跨天之后它就消失了（原生跨天只重渲染旧快照，不跑 Dart）');
    expect(kt.contains('snap.otherCrews'), true);
    expect(kt.contains('?.tally'), true);
    // 两个方向都要设满：宿主 `reapply` 只重放新动作，漏设的一边会留着上一次的状态。
    for (final id in ['wg_tc_note', 'wg_tc_tally']) {
      expect(kt.contains('R.id.$id, android.view.View.GONE'), true,
          reason: '$id 少了「隐藏」那一支 —— 没有内容的那天会留一条空白');
    }
  });

  test('Kotlin 里没有用户可见的中文字面量（这一轮新增的那几行也不许有）', () {
    final kt = _stripComments(_read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt'));
    // 自证：剥注释之后代码还在（正则/状态机写歪就成了一句永远为真的空话）
    expect(kt.contains('renderTodayCard'), true, reason: '剥注释剥过头了');
    for (final zh in ['其他班组', '本月', '休息日', '未开启', '前一天', '次日']) {
      expect(kt.contains(zh), false,
          reason: '「$zh」是用户可见文案，必须由 Dart 侧快照下发');
    }
  });

  test('「其他班组」那一行与 App 同一档字号（三处一起对账）', () {
    // 用户 2026-10-16 真机反馈：「『其他班组』那里的字体有点小……如果可以的话，
    // 可以整体再放大一些」。量下来**不是没位置**（卡内上下各还剩约 13dp 富余），
    // 是这一行**写小了一档**：11dp，而 App 同一行 12、这张卡自己的「本月统计」
    // 也是 12 —— App 里「其他班组 / 色块 / 本月统计」本来同一档，是搬到桌面时
    // 这行掉了一级。
    //
    // 这条把**三处**钉在一起：Kotlin 的基准字号、两份布局里的 dp 初值、Dart 令牌。
    // 任何一处单独被改（最典型的是有人调 `design_tokens` 而没回头看桌面），
    // 桌面就与 App 静默分岔 —— 而那种分岔在真机上只能靠肉眼看出来。
    final kt = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
    final m = RegExp(r'applyScale\(v, R\.id\.wg_tc_crew_label, ([0-9.]+)f, s\)')
        .firstMatch(kt);
    expect(m, isNotNull,
        reason: '找不到 wg_tc_crew_label 的 applyScale —— 护栏自己跟源码对不上了');
    expect(double.parse(m!.group(1)!), AppTokens.microText.fontSize,
        reason: '标签的基准字号与 App 的 `microText` 分岔了');

    final card = _read('android/app/src/main/res/layout/widget_today_card.xml');
    expect(_textSizeDp(card, 'wg_tc_crew_label'), AppTokens.microText.fontSize,
        reason: 'widget_today_card.xml 里那个 dp 初值没跟上（它与上面那行要一起改）');

    final chip = _read('android/app/src/main/res/layout/widget_crew_chip.xml');
    expect(_textSizeDp(chip, 'wg_cc_text'), AppTokens.microLabel.fontSize,
        reason: '色块里的文字与 App 的 `microLabel` 分岔了');

    // 自证这条判据有鉴别力：两个令牌**都是 12**，所以「随手写死一个 11」会被抓住，
    // 而「两边都写成别的同一个数」抓不住 —— 那本来就是设计变更，不是分岔。
    expect(AppTokens.microText.fontSize, AppTokens.microLabel.fontSize,
        reason: '两个令牌不再同档了 —— 「其他班组」这一行是按它们同档才对齐的，'
            '重新定档要连带复核桌面这两处');
  });
}
