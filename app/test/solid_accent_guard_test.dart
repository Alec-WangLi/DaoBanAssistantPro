// app/test/solid_accent_guard_test.dart
//
// 守门（D3 的调用点，§6 待补第 10 条）：**实心主色面必须走 `solidAccent`**。
//
// 为什么这条守不住「纯函数」那半边：`design_tokens_test` 里那条 AA 用例钉的是
// **配方**（压深之后过线），钉不到**调用点** —— 调用点直接写 `color: primary`
// 当底、字再写死白，配方那条照样绿。v0.14.1 修的就是这种：
// 「重复待办 → 每月」的选中格，teal / orange 只有 2.63 / 2.55。
//
// **为什么从 `BoxDecoration` 入手**：静态分析看不出「这块颜色上面有没有字」，
// 但 `BoxDecoration` 的 `color` 是**当时就定死的填色**（不像 `withValues` 那种
// 半透明叠色，也不像 `TextStyle.color` 那种前景色）。于是规则收窄成一句：
//
//   界面层里，`BoxDecoration(color: primary|accent)` —— 没用 `solidAccent(...)`
//   包一层、也不是 `.withValues(...)` 叠色 —— 要么改配方，要么加具名豁免。
//
// 已知盲区（有意不处理，别以为它全守住了）：
//   - 填色写在局部变量里再传进去（`final c = primary; … color: c`）；
//   - `Border.all(color: primary)` 这种边框 —— 边框不垫字，不归这条管；
//   - 渐变里的停靠点（`LinearGradient(colors: [primary, …])`），元素没有
//     `color:` 标签，正则看不见；
//   - `TextStyle.copyWith(color: primary)` 是**前景色**，不在此列。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

/// 扫哪些目录 —— 与 `design_tokens_test` 的扫描网一致（界面层）。
const List<String> _scanDirs = <String>[
  'lib/features',
  'lib/core/widgets',
  'lib/core/glass',
  'lib/core/theme',
];

final RegExp _boxHead = RegExp(r'BoxDecoration\(');
final RegExp _colorArg = RegExp(r'color:\s*([A-Za-z_][A-Za-z0-9_]*)');
final RegExp _ignoreMarker = RegExp(r'//\s*design-tokens-ignore:\s*(\S.*?)\s*$');

/// `open`（左括号下标）的配对右括号，返回参数串在原串里的 `[start, end)`。
(int, int)? _balancedArgs(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return (open + 1, i);
    }
  }
  return null;
}

/// [index] 处在 [s] 里的括号嵌套深度。
int _depthAt(String s, int index) {
  var depth = 0;
  for (var i = 0; i < index; i++) {
    final c = s[i];
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
    }
  }
  return depth;
}

/// 某一行（或紧邻上一行）有没有具名豁免；与 `design_tokens_test` 同一套约定。
///
/// 必须在**原始源码**上查 —— 规则跑的是剥过壳的副本，注释在那里已是空格。
String? _ignoreReasonAt(String rawSrc, int line) {
  final lines = rawSrc.split('\n');
  for (final i in <int>[line - 1, line - 2]) {
    if (i < 0 || i >= lines.length) continue;
    final m = _ignoreMarker.firstMatch(lines[i]);
    if (m != null) return m.group(1);
  }
  return null;
}

/// 扫一段源码，返回「裸主色当 BoxDecoration 填色」的位置。
List<String> _bareAccentFills(String path, String src) {
  final String code = blankNonCode(src);
  final List<String> out = <String>[];
  final Set<String> seen = <String>{};
  for (final RegExpMatch head in _boxHead.allMatches(code)) {
    final span = _balancedArgs(code, head.end - 1);
    if (span == null) continue;
    final (int argStart, int argEnd) = span;
    final String args = code.substring(argStart, argEnd);
    for (final RegExpMatch m in _colorArg.allMatches(args)) {
      // 嵌套调用里的 `color:` 不归这层 BoxDecoration 管。
      if (_depthAt(args, m.start) != 0) continue;
      final String name = m.group(1)!;
      if (name != 'primary' && name != 'accent') continue;
      // `color: primary.withValues(...)` 是叠色，不是实心填色。
      var j = m.end;
      while (j < args.length && (args[j] == ' ' || args[j] == '\n')) {
        j++;
      }
      if (j < args.length && args[j] == '.') continue;

      final int line = '\n'.allMatches(code.substring(0, argStart + m.start)).length + 1;
      if (_ignoreReasonAt(src, line) != null) continue;
      if (!seen.add('$line:$name')) continue;
      out.add('$path:$line  填色直接用了 `$name`（D3：改走 AppTokens.solidAccent）');
    }
  }
  return out;
}

void main() {
  test('界面层没有「裸主色当实心填色」的地方', () {
    final List<String> offenders = <String>[];
    for (final String dir in _scanDirs) {
      final Directory d = Directory(dir);
      if (!d.existsSync()) {
        fail('扫描目录不存在：$dir —— 这条用例假定工作目录是 app/');
      }
      for (final FileSystemEntity e in d.listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final String path = e.path.replaceAll(r'\', '/');
        offenders.addAll(_bareAccentFills(path, e.readAsStringSync()));
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '这些地方把主色直接当实心填色用了（D3）：\n  ${offenders.join('\n  ')}\n'
          '实心面走 `AppTokens.solidAccent(primary)`，字色走 `AppTokens.onSolid(…看底色…)`；'
          '确实不该管的（比如纯装饰、不承载文字的细条）加 '
          '`// design-tokens-ignore: <理由>`。',
    );
  });

  test('自证：该报的报、不该报的不报', () {
    // 正面：裸主色当填色。
    expect(
        _bareAccentFills('t.dart', 'BoxDecoration(color: primary)'), hasLength(1));
    expect(
        _bareAccentFills('t.dart', 'BoxDecoration(color: accent)'), hasLength(1));
    // 跨行写法也要报。
    expect(
        _bareAccentFills('t.dart', 'BoxDecoration(\n  color: primary,\n)'),
        hasLength(1));

    // 反面一：走 solidAccent 就合法。
    expect(
        _bareAccentFills(
            't.dart', 'BoxDecoration(color: AppTokens.solidAccent(primary))'),
        isEmpty);
    // 反面二：叠色（withValues）不是实心面。
    expect(
        _bareAccentFills(
            't.dart', 'BoxDecoration(color: primary.withValues(alpha: 0.14))'),
        isEmpty);
    // 反面三：别的颜色不归这条管。
    expect(_bareAccentFills('t.dart', 'BoxDecoration(color: AppTokens.bgLight)'),
        isEmpty);
    // 反面四：具名豁免生效；没写理由不算数。
    expect(
        _bareAccentFills(
            't.dart',
            '// design-tokens-ignore: 4×18 纯装饰竖条\n'
                'BoxDecoration(color: accent)'),
        isEmpty);
    expect(
        _bareAccentFills('t.dart',
            '// design-tokens-ignore:\nBoxDecoration(color: accent)'),
        hasLength(1));
    // 反面五：注释里的不算（剥壳之后是空格）。
    expect(_bareAccentFills('t.dart', '// BoxDecoration(color: primary)'),
        isEmpty);
  });
}
