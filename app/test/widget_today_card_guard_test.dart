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

String _read(String rel) {
  final f = File(rel);
  expect(f.existsSync(), true,
      reason: '$rel 不存在 —— 要么实现还没做，要么这条护栏自己跟源码对不上了');
  return f.readAsStringSync();
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
}
