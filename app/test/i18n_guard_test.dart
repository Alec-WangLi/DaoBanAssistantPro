// app/test/i18n_guard_test.dart
//
// 守门（D/E12）：**`Text(...)` 的第一个位置参数不许是裸中文字面量。**
//
// E12 一直是「自守」—— 桩理由写得很实在：「12 个 *guard_test 无一扫文案」。
// v0.14.1 复核时实测：`Text('中文')` 这种写法现在**一处都没有**，唯一的真漏
// （`app.dart:31` 的品牌名）早已改成 `L10n.appName`。所以这条护栏是从零开始守，
// 而不是在追债 —— 定得窄一点值得。
//
// **为什么只认 `Text(` 的第一个位置参数**：这是「一定画到屏幕上」且语法上没有
// 歧义的那一类。收宽会产生误报，而误报多了这条就会被写成豁免、然后失效：
//   - `title: '…'` 在双语数据表（`L10nText`）里也是合法位置；
//   - `appendLog('…')` / `logInfo('…')` 是日志，本来就该是给人看的中文；
//   - `'yyyy年M月'` 是日期格式串，不是文案。
//
// **已知盲区（有意不处理，别以为它全守住了）**：
//   - `TextSpan(text: '…')` / `Tooltip(message: '…')` / `hintText: '…'` 等
//     具名参数位，本条不扫；
//   - 拼接出来的文案（`'共' + n + '条'`）、插值里嵌字面量；
//   - `tool/` 与 `test/` 不在扫描范围内（工装里的中文是给看图的人看的）。
//   要扩到这些位置，先把上面每一类的**合法写法**想清楚，否则就是一串豁免。
//
// 规则跑在 `blankNonCode` 上（注释已清成空格），但**字面量内容要从原始源码取**
// —— 那一层正是被清掉的。两份串等长，偏移通用。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

final RegExp _han = RegExp(r'[一-鿿]');
final RegExp _identChar = RegExp(r'[A-Za-z0-9_$]');

/// [start] 处（`Text(` 的 `T`）**紧邻前缀**的标识符。
///
/// 匹配串是 `Text(`，所以完整名字是「前缀 + Text」：前缀为 `L10n` 即
/// `L10nText(` —— 那是双语数据表的合法写法，不是裸文案。
String _identBefore(String code, int start) {
  var j = start - 1;
  while (j >= 0 && _identChar.hasMatch(code[j])) {
    j--;
  }
  return code.substring(j + 1, start);
}

/// 从左引号 [open] 处取出**原始源码**里的字面量内容；不是字面量返回 null。
///
/// `blankNonCode` 只清内容、**保留引号**，所以「下一个引号就是结束引号」在
/// 剥过壳的副本上成立（内容里的转义引号也被清掉了）。三引号按三个一组认。
String? _literalAt(String code, String src, int open) {
  final q = src[open];
  if (q != "'" && q != '"') return null;
  final triple = code.startsWith(q * 3, open);
  final quote = triple ? q * 3 : q;
  final close = code.indexOf(quote, open + quote.length);
  if (close < 0) return null; // 未闭合（源码被截断），当没有
  return src.substring(open + quote.length, close);
}

/// 扫一段源码，返回「`Text(` 的第一个位置参数是含汉字的裸字面量」的位置。
///
/// 拆出「读文件」这一步是为了能用合成文本正反两面钉（与 `design_tokens_test`
/// 的 `_violationsIn` 同一套路）。
List<String> _bareTextLiterals(String path, String src) {
  final String code = blankNonCode(src);
  final List<String> out = <String>[];
  for (final RegExpMatch m in RegExp(r'Text\(\s*').allMatches(code)) {
    if (_identBefore(code, m.start) == 'L10n') continue;
    final int open = m.end;
    if (open >= code.length) continue;
    final String? content = _literalAt(code, src, open);
    if (content == null || !_han.hasMatch(content)) continue;
    final int line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
    // 报告回**原始源码**取那一行，带注释可读（与 design_tokens_test 同一做法）。
    // `lastIndexOf` 的 start 不能是 -1，所以首行单独处理。
    final int lineStart =
        m.start == 0 ? 0 : src.lastIndexOf('\n', m.start - 1) + 1;
    var lineEnd = src.indexOf('\n', m.start);
    if (lineEnd < 0) lineEnd = src.length;
    out.add('$path:$line  ${src.substring(lineStart, lineEnd).trim()}');
  }
  return out;
}

void main() {
  test('lib/ 里没有「Text 直接写中文」的裸文案', () {
    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity
        in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String path = entity.path.replaceAll(r'\', '/');
      offenders.addAll(_bareTextLiterals(path, entity.readAsStringSync()));
    }
    expect(
      offenders,
      isEmpty,
      reason: '这些地方直接把中文写进了 Text()（E12）：\n  ${offenders.join('\n  ')}\n'
          '单个短路走 `t(\'…\')`，成对的双语数据走 `L10nText(\'中文\',\'English\')`。',
    );
  });

  test('自证：该报的报、不该报的不报', () {
    // 正面：裸中文照报。
    expect(_bareTextLiterals('t.dart', "Text('保存')"), hasLength(1));
    // 跨行写法也要报（值分行是这一类最常见的漏检形态）。
    expect(_bareTextLiterals('t.dart', "Text(\n  '保存',\n)"), hasLength(1));
    // 双引号同样算。
    expect(_bareTextLiterals('t.dart', 'Text("保存")'), hasLength(1));

    // 反面一：双语数据表的合法写法。
    expect(_bareTextLiterals('t.dart', "L10nText('保存', 'Save')"), isEmpty);
    // 反面二：走 t() 的就地翻译，第一个参数根本不是字面量。
    expect(_bareTextLiterals('t.dart', "Text(t('保存'))"), isEmpty);
    // 反面三：纯英文不归这条管。
    expect(_bareTextLiterals('t.dart', "Text('Save')"), isEmpty);
    // 反面四：注释里写的不算（剥壳之后就是空格）。
    expect(_bareTextLiterals('t.dart', "// Text('保存')"), isEmpty);
  });
}
