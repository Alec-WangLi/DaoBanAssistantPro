// app/test/widget_font_scale_guard_test.dart
//
// 桌面小组件的字号**不许跟系统字号走**。
//
// 用户 2026-10-15：「桌面小组件仍按系统 sp 排版 —— 系统字号调到 200% 时桌面那张
// 卡还会跟着变大」。真机实测（font_scale=2.0）：今日卡的「20:30 – 次日08:30」
// 下半截被切、「其他班组」整行不见、「1 项待办」徽章右半截出界；周条七列的
// 「周四 / 周五」挤成一团。根因是**卡片尺寸编译期定死（resizeMode="none"）而
// 字号写 `sp`** —— 尺寸不动、字在长，装不下就切。
//
// Kotlin 在这个仓库里没有可跑的测试目标，所以这一族只能扫源码。它证明不了
// 「画出来好不好看」，但 `sp` 这一条是**纯粹的字面量判据**，扫得住。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 会渲染真数据的那 9 张。`widget_preview_*` 是静态缩略图（永远不渲染数据），
/// 按设计豁免 —— 但**这份清单本身就是自证的一部分**，见下面第一条。
const List<String> kWidgetLayouts = [
  'month_card',
  'month_cell',
  'today_card',
  'today_standalone',
  'strip_cell',
  'week_strip',
  'crew_chip',
  'empty',
  'placeholder',
];

String _read(String rel) =>
    File('android/app/src/main/res/layout/widget_$rel.xml').readAsStringSync();

/// XML 注释剥成空格（行号不变）—— 注释里写一句 `sp` 不该算违规。
String _stripXmlComments(String s) => s.replaceAllMapped(
      RegExp(r'<!--.*?-->', dotAll: true),
      (m) => m.group(0)!.replaceAll(RegExp(r'[^\n]'), ' '),
    );

/// Kotlin 注释剥成空格（字符串字面量原样留着）。与 `widget_today_card_guard_test.dart`
/// 同一套做法 —— 注释里提一句 `COMPLEX_UNIT_SP` 是**解释规则**，不是违规。
String _stripKotlinComments(String s) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
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
  test('自证：清单里是 9 张、且 preview 那三张确实不在里面', () {
    expect(kWidgetLayouts, hasLength(9),
        reason: '清单被改短了 —— 那样后面的扫描就会「一个都没扫到」也报绿');
    for (final n in ['preview_month', 'preview_strip', 'preview_today']) {
      expect(kWidgetLayouts.contains(n), false,
          reason: '$n 是静态缩略图，按设计豁免');
    }
  });

  test('这 9 张布局里一个 sp 都没有（含注释之外的每一处 textSize）', () {
    final offenders = <String>[];
    for (final n in kWidgetLayouts) {
      final xml = _stripXmlComments(_read(n));
      final hits = RegExp(r'textSize="[0-9.]+sp"').allMatches(xml).length;
      if (hits > 0) offenders.add('$n ($hits 处)');
    }
    expect(offenders, isEmpty,
        reason: '这些布局还在用 sp：${offenders.join('、')} —— sp 会乘系统字号，'
            '而卡片尺寸是编译期定死的，装不下就切内容。改用 dp，并在渲染侧按格子'
            '尺寸 setTextViewTextSize(COMPLEX_UNIT_DIP, …)。');
  });

  test('渲染侧的缩放机制在位，且用的是 DIP 而不是 SP', () {
    final raw = File(
            'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt')
        .readAsStringSync();
    final kt = _stripKotlinComments(raw);
    // 自证：剥注释之后代码还在
    expect(kt.contains('cardScale'), true, reason: '剥注释剥过头了');
    expect(kt.contains('COMPLEX_UNIT_DIP'), true,
        reason: 'setTextViewTextSize 必须用 COMPLEX_UNIT_DIP —— 用 SP 就等于没脱开');
    expect(kt.contains('COMPLEX_UNIT_SP'), false);
    // 基准字号必须点名出处（写在注释里就够）—— 否则下次调 design_tokens 桌面会静默走样。
    for (final token in ['cellDateSm', 'cellShift', 'tinyLabel', '_cellDesignH']) {
      expect(raw.contains(token), true,
          reason: '基准字号没点名 $token 这个出处');
    }
  });
}
