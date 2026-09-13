// app/test/design_tokens_test.dart
//
// 这一轮（设计语言 v2）把「界面层不写数值」从文档里的一句话变成了会红的东西。
//
// 三组：
//   1. 角色令牌的字号 / 字重 / 行高必须等于规格里那张表 —— 改令牌就得先改规格。
//   2. lib/features · lib/core/widgets · lib/core/glass 下不许出现字面量。
//      迁移期间曾用 _pending 兜住还没迁完的文件，收口时已连同进度用例一起删除；
//      这条规则从此扫**全部**文件、没有任何豁免。
//   3. 间距类常量（名字带 Pad/Gap/Inset/Spacing 的 const）的值也必须在 4px 栅格上
//      —— 否则把字面量提成常量就能绕过第 2 条。真要保留 off-grid 值必须写
//      `// design-tokens-ignore: <理由>` 具名豁免（作用域：同一行或紧邻上一行），
//      命中的豁免会打进日志 —— 故意不扫要看得见（见 `_constantViolationsIn`）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/theme/app_colors.dart';

double _wcagContrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

const List<String> _scanDirs = [
  'lib/features',
  'lib/core/widgets',
  'lib/core/glass',
  'lib/core/theme',
];

/// 文件级豁免：**配色层本身**。
///
/// 这两个文件是颜色的**定义处**，不是颜色的**用法** —— 主色板与中性 seed 本来
/// 就该写成字面量，扫它们等于要求令牌引用自己。目录里其余文件（渲染件）照常扫。
///
/// 豁免只在 `_violations` 的**入口**处生效（见该函数），所以无论从目录遍历进来、
/// 还是直接点某个文件，结果一致 —— 不会出现「目录扫是绿的、单点这个文件是红的」。
const Set<String> _exemptFiles = {
  'lib/core/theme/app_colors.dart',
  'lib/core/theme/app_theme.dart',
};

/// 把源码里的**非代码部分**替换成**等长空格**：行注释、块注释、字符串字面量的内容。
///
/// 为什么要等长替换而不是删掉：所有规则都靠「命中偏移 → 行号」定位（`_lineAt`），
/// 删字符会让偏移全错。换成空格则偏移与行号纹丝不动。
///
/// 换行**保留** —— 行数也不能变。
///
/// 注意：**具名豁免标记写在注释里**，所以豁免判定必须回到**原始源码**上查，
/// 不能查这个副本（注释在这里已经是空格了）。见 `_ignoreReasonAt`。
///
/// 两处必须按 Dart 词法走对，否则会**漏检**（把真代码当成注释/字符串清掉）：
///   - **原始字符串** `r'…'` / `R"…"` 里 `\` **不转义**：`r'a\'` 在结束引号前
///     有一个 `\`，若照普通字符串「跳转义」就会以为引号没结束、一路吞到下一个
///     引号（或文件尾），把中间真代码静默清掉。故先看引号前是不是 `r`/`R`
///     前缀（且它前面不是标识符字符）。
///   - **块注释可嵌套**：`/* a /* b */ c */` 里 `indexOf('*/')` 会停在内层，
///     把内层之后的正文当代码露出来（误报）。故按深度找配对的 `*/`。
///
/// 已知边界（有意不处理）：字符串**插值里嵌套同引号字面量**
/// （`Text('${m['k']}')`）会把内层内容露出来 —— 是**误报**方向，且引号奇偶
/// 仍平衡、不会跑飞。要处理需真正的插值感知解析，本轮不做。
String blankNonCode(String src) {
  final out = src.split('');
  void blank(int from, int to) {
    for (var k = from; k < to && k < out.length; k++) {
      if (out[k] != '\n') out[k] = ' ';
    }
  }

  var i = 0;
  while (i < src.length) {
    // 行注释：到行尾（不含换行）
    if (src.startsWith('//', i)) {
      final nl = src.indexOf('\n', i);
      final stop = nl < 0 ? src.length : nl;
      blank(i, stop);
      i = stop;
      continue;
    }
    // 块注释：**可嵌套**，按深度找配对的 `*/`。未闭合则到文件尾
    // （j 每轮至少 +1，不会死循环）。
    if (src.startsWith('/*', i)) {
      var depth = 1;
      var j = i + 2;
      while (j < src.length && depth > 0) {
        if (src.startsWith('/*', j)) {
          depth++;
          j += 2;
        } else if (src.startsWith('*/', j)) {
          depth--;
          j += 2;
        } else {
          j++;
        }
      }
      blank(i, j);
      i = j;
      continue;
    }
    final c = src[i];
    if (c == "'" || c == '"') {
      // 原始字符串前缀：`r'…'` / `R"…"`。`r` 前面若还是标识符字符，那 `r` 是
      // 标识符的一部分（`abr'…'`），不是前缀。
      final raw = i > 0 &&
          (src[i - 1] == 'r' || src[i - 1] == 'R') &&
          (i < 2 || !_identChar.hasMatch(src[i - 2]));
      final triple = i + 2 < src.length && src[i + 1] == c && src[i + 2] == c;
      final quote = triple ? c * 3 : c;
      var j = i + quote.length;
      while (j < src.length) {
        // 原始字符串里 `\` 不转义，只有普通字符串才跳过转义的下一个字符。
        if (!raw && src[j] == '\\') {
          j += 2;
          continue;
        }
        if (src.startsWith(quote, j)) break;
        j++;
      }
      final stop = j >= src.length ? src.length : j + quote.length;
      // 只清**内容**，引号（含 `r` 前缀）保留 —— 更直观，也不影响任何规则。
      blank(i + quote.length, j);
      i = stop;
      continue;
    }
    i++;
  }
  return out.join();
}

/// 界面层禁止的字面量。这一组**整文件扫描**：正则在全文上跑、命中偏移再换算回行号。
///
/// 不逐行跑，是因为迁移期实测出三个漏洞 —— 值一旦与关键字**分行**就会静默漏检
/// （逐行的正则只看得到一行）：
///
///   1. 图标：`Icon(` 与 `size: 28` 分写两行时，逐行的 `[^)]*` 跨不过换行
///      （Task 5 实测的响铃界面那处就是这么写的）；
///   2. 明度：`Theme.of(context)` / `.colorScheme` / `.onSurface` / `.withValues(…)`
///      链式跨行时关键字不在同一行（Task 7 实测的导航未选中标签色）；
///   3. 字重：`fontWeight: selected\n ? FontWeight.w700\n : FontWeight.w500`
///      这种三元跨行写法（Task 7 审查发现，`home_shell.dart` 导航标签）。
///
/// 既然这三条会漏，其余几条就没有理由再逐行 —— 「逐行」是整类缺陷，不是这三条的
/// 特例。所以**一律**整文件扫：省下的那点开销，远抵不上「守门测试绿」失去可信度。
final Map<String, RegExp> _rules = {
  '字号字面量（改用角色令牌）': RegExp(r'fontSize:\s*[0-9]'),
  // 图标：`Icon(` 与 `size: 28` 分写两行时，`[^)]*` 要能跨过换行。
  '图标尺寸字面量（改用 iconSm/Md/Lg）':
      RegExp(r'(Icon|IconThemeData)\([^)]*size:\s*[0-9]'),
  // 明度：`onSurface` 与 `.withValues(` 之间允许换行 —— 链式写法会把它拆到下一行。
  '文字明度字面量（改用 inkMuted / inkFaint）':
      RegExp(r'onSurface\s*\.\s*withValues\(\s*alpha:'),
  // 字重：`fontWeight:` 与 `FontWeight.` 之间允许一段不含 `,` `;` `)` 的值表达式，
  // 于是 `fontWeight: selected ? FontWeight.w700 : FontWeight.w500` 这类三元也认得。
  // 逗号/分号/右括号当作值的边界，免得跨过语句去匹配后面无关的 `FontWeight.`。
  '字重字面量（改用角色令牌，个别变化走 copyWith）':
      RegExp(r'fontWeight:[^;,)]*?FontWeight\.'),
  '圆角字面量（改用 radiusS/M/L/XL 或 pillOf）': RegExp(r'circular\([0-9]'),
  '时长字面量（改用 durFast/Med/Slow/Flow）':
      RegExp(r'Duration\(milliseconds:\s*[0-9]'),
  '颜色字面量（改用令牌）': RegExp(r'Color\(0x'),
  '旧的按尺寸命名的字号令牌（改用角色令牌）': RegExp(r'AppTokens\.font[A-Z]'),
};

/// 逐文件入口。文件级豁免（`_exemptFiles`）在这里判定 —— 不看调用方是谁：
/// 从目录遍历进来、还是直接点某个文件，结果都一样。
List<String> _violations(String path) {
  if (_exemptFiles.contains(path)) return const [];
  return _violationsIn(path, File(path).readAsStringSync());
}

/// 扫一段源码里的字面量。拆出「读文件」这一步是为了能用临时文本单测 ——
/// [path] 只进报告、不参与判断（与 `_spacingViolationsIn` 同一套路）。
///
/// **双轨**：规则跑在 [blankNonCode] 剥过的副本上（注释与字符串内容已成空格），
/// 免得注释里写 `fontSize: 10` 这种示例把测试打红；而**报告行文本**要回到原始
/// 源码上取，才能拿到带注释的可读上下文。两份串等长，偏移通用。
/// 具名豁免标记写在注释里，因此豁免判定也一律回原文查（见 `_ignoreReasonAt`）。
List<String> _violationsIn(String path, String src) {
  final code = blankNonCode(src);
  final out = <String>[];
  for (final rule in _rules.entries) {
    for (final m in rule.value.allMatches(code)) {
      // `copyWith(fontWeight: …)` 是一个角色内的刻意变化，允许（见规格 §3.2）。
      // 判据是「这次匹配落在某个 `copyWith(` 调用的括号里」，而不是「同一行含
      // copyWith」—— 值跨行时 `copyWith(` 会留在上一行，行级判定会把合法调用误报。
      //
      // 注意这里查的是 `code`（剥过的副本）：字符串里的 `copyWith` 文本不该
      // 影响括号配对。偏移在两份串上一致（等长替换）。
      if (rule.key.startsWith('字重') && _insideCopyWith(code, m.start)) continue;
      final at = _lineAt(src, m.start); // 行号在两份源码上一致（等长替换）
      out.add('$path:${at.line}  ${rule.key}\n      ${at.text}');
    }
  }
  return out;
}

/// [offset] 处在 [src] 的哪一行（1 起），以及那一行的文本（去首尾空白）。
({int line, String text}) _lineAt(String src, int offset) {
  final before = src.substring(0, offset);
  final line = '\n'.allMatches(before).length + 1;
  final start = before.lastIndexOf('\n') + 1;
  var end = src.indexOf('\n', offset);
  if (end < 0) end = src.length;
  return (line: line, text: src.substring(start, end).trim());
}

final RegExp _identChar = RegExp(r'[A-Za-z0-9_$]');

/// [index] 处的字符是否落在某个 `copyWith(` 调用的括号内：从匹配点向前走、做括号
/// 配对，找到**包裹它的那个左括号**，再看左括号前面的标识符是不是 `copyWith`。
/// 比「同一行含 copyWith」稳 —— 值跨行时行级判定会把合法调用误报（见 `_violationsIn`）。
bool _insideCopyWith(String src, int index) {
  var depth = 0;
  for (var i = index - 1; i >= 0; i--) {
    final c = src[i];
    if (c == ')') {
      depth++;
    } else if (c == '(') {
      if (depth > 0) {
        depth--;
        continue;
      }
      var j = i - 1;
      while (j >= 0 && (src[j] == ' ' || src[j] == '\n')) {
        j--;
      }
      final end = j + 1;
      while (j >= 0 && _identChar.hasMatch(src[j])) {
        j--;
      }
      return src.substring(j + 1, end) == 'copyWith';
    }
  }
  return false;
}

/// 间距位置上只允许两类数字：`1`（描边与发丝线），以及 **4 的倍数**。
///
/// 判的是「在不在 4px 栅格上」，不是「是不是那七个档位值」——
/// `EdgeInsets.fromLTRB(16, 8, 16, 96)` 里的 96 不在档位上但在栅格上，合法。
///
/// 2 / 3 / 5 / 6 / 7 / 9 / 10 / 14 / 18 / 22 都不在栅格上，必须要么写成光学
/// 令牌（gapHair / padChipV / gapIconText / gapIconTextLg），要么就近归到栅格。
/// 这样「4px 栅格」就不靠自觉：栅格上的值直接写数字（它本身就是刻度），
/// 栅格外的值必须有名有姓。
bool _spacingOk(double n) => n == 1 || n % 4 == 0;

final RegExp _spacingHead = RegExp(r'(SizedBox|EdgeInsets\.[a-zA-Z]+)\(');
final RegExp _numberIn = RegExp(r'[0-9]+(?:\.[0-9]+)?');

/// 从 `open`（左括号的下标）出发找它的配对右括号，返回**参数串**在原串里的
/// `[start, end)`。找不到闭合（源码被截断）返回 null，当作没有这次调用。
///
/// 为什么不能用 `\(([^()]*)\)`：那样 `SizedBox(width: 6, child: Center(…))`
/// 整条不匹配 —— 带子 widget 的写法里写多大的间距都没人管（v0.6.11 审查发现）。
///
/// 字符串在调用方已经用 `blankNonCode` 清成空格，所以参数里的 `)` 不会干扰深度。
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

/// [index] 处在参数串 [s] 里的括号嵌套深度（`(` 记 +1，`)` 记 -1）。
///
/// 只有**深度 0** 的数字才是这次调用的直接参数。嵌套调用里的数字一律不算 ——
/// 那正是旧正则 `\(([^()]*)\)` 用「有嵌套括号就整条跳过」挡住的那一批：
/// `child: Row(…)` 里的 `withValues(alpha: 0.35)` / `strokeWidth: 2.6` /
/// `maxLength: 2` / `List.generate(7, …)`。改成配对括号扫描后，闸门得从「整条
/// 跳过」挪到这里 —— 否则带子 widget 的 `SizedBox` 一放开，child 里的透明度、
/// 描边宽、个数全成了间距误报（实测 15 处）。
///
/// 嵌套调用自己的间距不会被漏：它的函数头会被 `_spacingHead` 单独命中。
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

String _charBefore(String s, int i) {
  var j = i - 1;
  while (j >= 0 && (s[j] == ' ' || s[j] == '\n')) {
    j--;
  }
  return j >= 0 ? s[j] : '';
}

/// 返回参数里这个数字「后面」紧跟的字符；到参数末尾返回空串
/// （`SizedBox(width: 6)` 这样的单参数调用，最后一个数字后面没有逗号）。
String _charAfter(String s, int i) {
  var j = i;
  while (j < s.length && (s[j] == ' ' || s[j] == '\n')) {
    j++;
  }
  return j < s.length ? s[j] : '';
}

List<String> _spacingViolations(String path) =>
    _spacingViolationsIn(path, File(path).readAsStringSync());

/// 扫一段源码里的间距字面量。拆出「读文件」这一步是为了能用临时文本单测 ——
/// [path] 只进报告、不参与判断。
///
/// 调用与参数**分两步取**：`_spacingHead` 只认函数头，参数再用 `_balancedArgs`
/// 按括号深度配平取出（而不是一条正则吃下整条调用）—— 否则参数里一旦有嵌套
/// 括号（`child: Row(…)`）就会整条跳过。取出后再用 `_depthAt` 只留**直接参数**
/// 上的数字：嵌套调用里的 `alpha:` / `strokeWidth:` / 个数不是间距（见 `_depthAt`）。
/// 规则跑在 [blankNonCode] 剥过的副本上，参数里的 `)` 不会打乱深度；
/// 报告行号回原始 [src] 取（两份等长，偏移通用）。
List<String> _spacingViolationsIn(String path, String src) {
  final code = blankNonCode(src);
  final out = <String>[];
  final seen = <String>{};
  for (final head in _spacingHead.allMatches(code)) {
    final span = _balancedArgs(code, head.end - 1);
    if (span == null) continue;
    final (argStart, argEnd) = span;
    final args = code.substring(argStart, argEnd);
    for (final m in _numberIn.allMatches(args)) {
      // 嵌套调用里的数字不归这次调用管（`alpha: 0.35` / `strokeWidth: 2.6` …）。
      if (_depthAt(args, m.start) != 0) continue;
      final before = _charBefore(args, m.start);
      final after = _charAfter(args, m.end);
      // 只把「整个参数就是一个数字」的当成间距值，跳过算式里的数字
      // （`width: cellW - _cellInset * 2` 的 2 是算式的一部分）。
      //
      // **空串要放行**：位置 0 的数字前面没有字符可看，`_charBefore` 返回空串 ——
      // 那正说明它就是整个参数本身（`EdgeInsets.all(2)` 的 args 就是 `"2"`，
      // `SizedBox(width: 6)` 的 args 是 `"width: 6"` 有 `':'`）。少了这一条，
      // 单参数写法会静默漏检，「守门测试绿」就不等于「文件里没有字面量」了。
      if (before != '' && before != ':' && before != ',' && before != '(') {
        continue;
      }
      if (after != ',' && after != ')' && after != '') continue;
      final n = double.parse(m.group(0)!);
      if (_spacingOk(n)) continue;
      final line = _lineAt(src, argStart + m.start).line;
      final key = '$line:$n';
      if (!seen.add(key)) continue;
      out.add('$path:$line  间距不在 4px 栅格上：$n'
          '（改用 spaceXxx 或 gapHair/padChipV/gapIconText/gapIconTextLg）');
    }
  }
  return out;
}

/// 间距类常量：名字里带 `Pad` / `Gap` / `Inset` / `Spacing` 的 `const`。
///
/// 为什么按名字收窄：实测扫描目录里 off-grid 的常量有 15 处，**只有 4 处是
/// 真间距**，其余是控件几何（`_trackHeight` 190）、比例（`_cellAspect` 0.78）、
/// 计数（`maxSlots` 14）甚至一个测试 id。全扫要付 11 条永久豁免注释，豁免一多
/// 就没人读了 —— 那是「守门测试绿但没人信」的另一条路。
///
/// 已知边界：把间距提成名字不含这四个词的常量（比如叫 `_k`）仍能逃。
/// 这条规则拦的是「顺手提成常量」的习惯，不是对抗性绕过 —— 要拦后者得做标识符
/// 解析，不划算。
/// **大小写不敏感**：真实的那处 `const inset = 3.0;` 是全小写，区分大小写会漏掉它。
///
/// 行首要写 `[ \t]*` 而**不是** `\s*`：`\s` 含换行，多行模式下 `^` 会在空行的
/// 行首先匹配，再把中间的空行一并吃掉 —— 匹配起点落到**空行**上，`_lineAt` 报出
/// 的行号也跟着上移，于是 `_ignoreReasonAt` 查错了行：声明上方隔两行的标记会被
/// 当成本行豁免。`[ \t]*` 只吃缩进，匹配起点稳落在声明自己那一行。
final RegExp _constDecl = RegExp(
    r'^[ \t]*(?:static\s+)?const\s+(?:double\s+)?'
    r'(\w*(?:Pad|Gap|Inset|Spacing)\w*)\s*=\s*(-?[0-9][0-9.]*)\s*;',
    multiLine: true,
    caseSensitive: false);

/// 具名豁免标记。冒号后必须**有非空理由**。
final RegExp _ignoreMarker = RegExp(r'//\s*design-tokens-ignore:\s*(\S.*?)\s*$');

/// 查某一行（或紧邻上一行）有没有具名豁免，有则返回理由。
///
/// **必须在原始源码上查** —— 规则跑的是 `blankNonCode` 的副本，注释在那里已经
/// 是空格了。两份串等长，所以行号通用。
String? _ignoreReasonAt(String rawSrc, int line) {
  final lines = rawSrc.split('\n');
  for (final i in [line - 1, line - 2]) {
    if (i < 0 || i >= lines.length) continue;
    final m = _ignoreMarker.firstMatch(lines[i]);
    if (m != null) return m.group(1);
  }
  return null;
}

/// 豁免过的条目会打进日志 —— 让「故意不扫」看得见，而不是默不作声。
final List<String> spacingConstantWaivers = [];

List<String> _constantViolations(String path) =>
    _constantViolationsIn(path, File(path).readAsStringSync());

/// 扫一段源码里的**间距类常量**。拆出「读文件」这一步是为了能用临时文本单测 ——
/// [path] 只进报告、不参与判断（与 `_spacingViolationsIn` 同一套路）。
///
/// 与字面量规则同走**双轨**：规则跑在 [blankNonCode] 剥过的副本上 —— 否则一行
/// **被注释掉的** `// static const double _oldPad = 6;` 会被误报；而具名豁免标记
/// 是注释，必须回到原始 [src] 上查（见 `_ignoreReasonAt`）。两份串等长，行号通用。
List<String> _constantViolationsIn(String path, String src) {
  final code = blankNonCode(src);
  final out = <String>[];
  for (final m in _constDecl.allMatches(code)) {
    final name = m.group(1)!;
    final value = double.parse(m.group(2)!);
    if (_spacingOk(value)) continue;
    final at = _lineAt(src, m.start);
    final reason = _ignoreReasonAt(src, at.line);
    if (reason != null) {
      spacingConstantWaivers.add('$path:${at.line}  $name = $value —— $reason');
      continue;
    }
    out.add('$path:${at.line}  间距类常量的值不在 4px 栅格上：'
        '$name = $value\n      ${at.text}\n'
        '      要么改引用已有令牌（spaceXxx / gapHair / padChipV / '
        'gapIconText / gapIconTextLg），要么加 '
        '`// design-tokens-ignore: <理由>` 说明它为什么不是设计间距');
  }
  return out;
}

/// 15 条角色排版令牌 —— 它们是阶梯的核心，必须逐条自检。
const Set<String> _typography = {
  'ringClock', 'pageTitle', 'bigNumber', 'dialogTitle', 'sectionTitle',
  'cellDate', 'titleStrong', 'labelStrong', 'rowPrimary', 'rowSecondary',
  'labelSecondary', 'microStrong', 'microLabel', 'microText', 'tinyLabel',
};

/// 「阶梯」= 排版 / 图标 / 间距 / 光学 / 圆角 / 明度 alpha / 时长。
///
/// **不在内**（有意，不是遗漏）：配色（`bg*` / `surface*` / `ink*` / `danger` /
/// `success` / `holiday`）、玻璃配方（`blur*` / `glass*`）、弹簧与缩放
/// （`qSpring` / `pressScale` / `pillGrow`）—— 它们不是阶梯，各自有别的用例盯着，
/// 或本身就是配方。
bool _isLadderToken(String n) =>
    _typography.contains(n) ||
    n.startsWith('icon') ||
    n.startsWith('space') ||
    n.startsWith('gap') ||
    n.startsWith('pad') ||
    n.startsWith('radius') ||
    n.startsWith('dur') ||
    (n.startsWith('ink') && n.endsWith('Alpha'));

void main() {
  test('角色令牌的尺寸与规格一致', () {
    void check(String name, TextStyle t, double size, FontWeight weight,
        [double? height]) {
      expect(t.fontSize, size, reason: '$name 的字号');
      expect(t.fontWeight, weight, reason: '$name 的字重');
      if (height != null) expect(t.height, height, reason: '$name 的行高');
    }

    check('ringClock', AppTokens.ringClock, 84, FontWeight.w800, 1.0);
    check('pageTitle', AppTokens.pageTitle, 28, FontWeight.w700);
    check('bigNumber', AppTokens.bigNumber, 24, FontWeight.w700);
    check('dialogTitle', AppTokens.dialogTitle, 20, FontWeight.w600);
    check('sectionTitle', AppTokens.sectionTitle, 18, FontWeight.w700);
    check('cellDate', AppTokens.cellDate, 18, FontWeight.w600, 1.15);
    check('titleStrong', AppTokens.titleStrong, 16, FontWeight.w700);
    check('labelStrong', AppTokens.labelStrong, 14, FontWeight.w700);
    check('rowPrimary', AppTokens.rowPrimary, 14, FontWeight.w500);
    check('rowSecondary', AppTokens.rowSecondary, 13, FontWeight.w400);
    check('labelSecondary', AppTokens.labelSecondary, 13, FontWeight.w600);
    check('microStrong', AppTokens.microStrong, 12, FontWeight.w700, 1.15);
    check('microLabel', AppTokens.microLabel, 12, FontWeight.w600);
    check('microText', AppTokens.microText, 12, FontWeight.w400);
    check('tinyLabel', AppTokens.tinyLabel, 11, FontWeight.w400, 1.15);

    // 图标三档。每项单列一行、各带 reason —— 早前这几组写成「手写枚举」
    // （`expect([a, b, c], [1, 2, 3])`），漏掉 `padChipV` 正是这么来的：加了
    // 令牌却忘了往枚举里补一项，断言照绿。逐项列出后，缺哪一项一眼可见。
    expect(AppTokens.iconSm, 16, reason: 'iconSm —— 小注 / 行内提示');
    expect(AppTokens.iconMd, 20, reason: 'iconMd —— 按钮内 / 列表项 / 导航项');
    expect(AppTokens.iconLg, 24, reason: 'iconLg —— 默认（IconTheme 也设成它）');

    // 节奏：4px 栅格。
    expect(AppTokens.spaceXs, 4, reason: 'spaceXs');
    expect(AppTokens.spaceSm, 8, reason: 'spaceSm');
    expect(AppTokens.spaceMd, 12, reason: 'spaceMd');
    expect(AppTokens.spaceLg, 16, reason: 'spaceLg');
    expect(AppTokens.spaceXl, 20, reason: 'spaceXl');
    expect(AppTokens.space2xl, 24, reason: 'space2xl');
    expect(AppTokens.space3xl, 32, reason: 'space3xl');

    // 光学：一个控件内部两个元素的贴合。
    expect(AppTokens.gapHair, 2, reason: 'gapHair —— 发丝线 / 描边');
    expect(AppTokens.padChipV, 3, reason: 'padChipV —— 小胶囊 / 徽章上下内边距');
    expect(AppTokens.gapIconText, 6, reason: 'gapIconText —— 图标↔文字');
    expect(AppTokens.gapIconTextLg, 10,
        reason: 'gapIconTextLg —— 图标↔文字（大号）');

    expect(AppTokens.durFlow, const Duration(milliseconds: 650),
        reason: 'durFlow —— 响铃界面入场动画的一次性控制器（非背景光晕循环）');
    expect(AppTokens.durFast, const Duration(milliseconds: 120),
        reason: 'durFast —— 短促反馈（按下 / 淡入淡出）');
    expect(AppTokens.durMed, const Duration(milliseconds: 220),
        reason: 'durMed —— 常规过渡（展开 / 切换）');
    expect(AppTokens.durSlow, const Duration(milliseconds: 340),
        reason: 'durSlow —— 较慢的位移 / 形变过渡');

    expect(AppTokens.inkMutedAlpha, 0.62,
        reason: '浅色最坏底 #F5F6FA 上 0.62 才到 4.70:1 过 AA（0.60 只有 4.33:1）');
    expect(AppTokens.inkFaintAlpha, 0.35,
        reason: '禁用/已完成档，有意低于 AA（见规格 §3.3）');
    expect(AppTokens.pillOf(40),
        const BorderRadius.all(Radius.circular(20)));
  });

  test('自检覆盖了每一个阶梯令牌（漏一个就红）', () {
    final tokenSrc = File('lib/core/design_tokens.dart').readAsStringSync();
    final testSrc = File('test/design_tokens_test.dart').readAsStringSync();

    final names = RegExp(
            r'^\s*static const (?:double|TextStyle|Duration) (\w+)\s*=',
            multiLine: true)
        .allMatches(tokenSrc)
        .map((m) => m.group(1)!)
        .where(_isLadderToken)
        .toList();

    expect(names, isNotEmpty, reason: '一个阶梯令牌都没抽到 —— 抽取的正则不对');
    final missing =
        names.where((n) => !testSrc.contains('AppTokens.$n')).toList();
    expect(missing, isEmpty,
        reason: '这些阶梯令牌没有自检断言，加令牌时漏了：$missing');
  });

  test('界面层不写数值', () {
    final offenders = <String>[];
    // 豁免清单只统计**真实界面文件**里命中的豁免：清一次，免得此前单测调用
    // `_constantViolationsIn` 留下的临时条目混进来。
    spacingConstantWaivers.clear();
    for (final dir in _scanDirs) {
      final d = Directory(dir);
      if (!d.existsSync()) {
        fail('扫描目录不存在：$dir —— 这条用例假定工作目录是 app/');
      }
      for (final e in d.listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final path = e.path.replaceAll(Platform.pathSeparator, '/');
        offenders.addAll(_violations(path));
        offenders.addAll(_spacingViolations(path));
        offenders.addAll(_constantViolations(path));
      }
    }
    // 豁免是**故意不扫**，不能默不作声 —— 打进日志，让人一眼看见哪些地方被放过。
    if (spacingConstantWaivers.isNotEmpty) {
      // ignore: avoid_print
      print('间距类常量的具名豁免（design-tokens-ignore）：\n'
          '${spacingConstantWaivers.join('\n')}');
    }
    expect(offenders, isEmpty,
        reason: '界面层只能引用令牌，发现 ${offenders.length} 处字面量：\n'
            '${offenders.join('\n')}');
  });

  test('core/theme 纳入扫描，但配色层两文件显式豁免', () {
    // 扫描目录表里必须含 core/theme —— 少了它，这个目录的守门就静默消失。
    // 这一条断言专门钉住「扩范围」本身：把 core/theme 从 `_scanDirs` 里删掉，
    // 下面的 isEmpty 仍然会过（豁免是看文件的），只有这里会红。
    expect(_scanDirs, contains('lib/core/theme'));
    // 配色层本身：豁免（它们是颜色**定义**，不是颜色**用法** —— 主色板与中性
    // seed 本来就该写成字面量，扫它们等于要求令牌引用自己）。
    expect(_violations('lib/core/theme/app_colors.dart'), isEmpty);
    expect(_violations('lib/core/theme/app_theme.dart'), isEmpty);
    // 渲染件不豁免 —— bgBlob 已收进配色层，这个文件必须干净。
    expect(_violations('lib/core/theme/animated_background.dart'), isEmpty);
    // 用一段仿真文本钉住「豁免按文件、不按目录」：同目录的其余文件照扫。
    expect(
        _violationsIn('lib/core/theme/x.dart', 'const c = Color(0xFFB9BECF);'),
        hasLength(1));
  });

  test('间距扫描认得单参数写法（钉住空串放行那条）', () {
    // 回归钉：曾经因为 `_charBefore` 在位置 0 返回空串、过滤条件却不放行空串，
    // `EdgeInsets.all(2)` / `EdgeInsets.all(3)` 这类整个参数就是一个数字的写法
    // 会被静默跳过 —— 于是界面里的漏网字面量「测试是绿的」。
    const src = '''
Widget a() => Padding(padding: const EdgeInsets.all(2), child: c);
Widget b() => Padding(padding: const EdgeInsets.all(4), child: c);
Widget d() => SizedBox(width: 6);
Widget e() => const SizedBox(height: 8);
Widget f() => SizedBox(width: cellW - _cellInset * 2);
''';
    final hit = _spacingViolationsIn('synthetic.dart', src);
    expect(hit, hasLength(2), reason: hit.join('\n'));
    expect(hit[0], contains('2.0'));
    expect(hit[1], contains('6.0'));
  });

  // ── 三条整文件扫描规则的正反两面钉子 ──
  //
  // 这三条规则原先逐行跑，各有一个「值跨行时静默漏检」的洞（见 `_rules` 的注释）。
  // 每条都**正反两面**钉：正面是跨行写法必须报，反面是合法写法不得误报 ——
  // 只钉正面的话，把规则改成「一律不查」也能让用例过。

  test('图标规则整文件扫描：`size` 写在下一行也要报', () {
    const bad = '''
Icon(
  Icons.alarm,
  size: 28,
);
''';
    final hit = _violationsIn('synthetic.dart', bad);
    expect(hit, hasLength(1), reason: hit.join('\n'));
    expect(hit.single, contains('图标'));

    // 反面：同一写法改用令牌，不得误报。
    const good = '''
Icon(
  Icons.alarm,
  size: AppTokens.iconLg,
);
''';
    expect(_violationsIn('synthetic.dart', good), isEmpty);
  });

  test('明度规则整文件扫描：链式跨行也要报', () {
    const bad = '''
final c = Theme.of(context)
    .colorScheme
    .onSurface
    .withValues(alpha: 0.5);
''';
    final hit = _violationsIn('synthetic.dart', bad);
    expect(hit, hasLength(1), reason: hit.join('\n'));
    expect(hit.single, contains('明度'));

    // 反面：改用 inkMuted / inkFaint，不得误报。
    const good = 'final c = AppTokens.inkMuted(context);';
    expect(_violationsIn('synthetic.dart', good), isEmpty);
  });

  test('字重规则整文件扫描：三元跨行也要报（copyWith 里不报）', () {
    // 正面：不在 copyWith 里的三元跨行 —— 逐行跑时 `fontWeight:` 那行没有
    // `FontWeight.`、`FontWeight.` 那行没有 `fontWeight:`，两边都漏。
    const bad = '''
Text('x', style: TextStyle(
  fontWeight: selected
      ? FontWeight.w700
      : FontWeight.w500,
));
''';
    final hit = _violationsIn('synthetic.dart', bad);
    expect(hit, hasLength(1), reason: hit.join('\n'));
    expect(hit.single, contains('字重'));

    // 反面：同样的三元放进 copyWith —— 一个角色内的刻意变化，合法、不得误报。
    // `copyWith(` 留在上一行，正是「行级豁免」会失手的地方。
    const good = '''
Text('x', style: AppTokens.tinyLabel.copyWith(
  fontWeight: selected
      ? FontWeight.w700
      : FontWeight.w500,
));
''';
    expect(_violationsIn('synthetic.dart', good), isEmpty);
  });

  // ── 间距扫描：带子 widget 的调用也要扫 ──
  //
  // **旧行为已反转**：`_spacingCall` 的参数部分曾写成 `[^()]*`，参数里一旦出现
  // 另一个括号就**整条跳过** —— 于是 `SizedBox(width: 6, child: Row(…))` 这种带
  // 子 widget 的写法里写多大的间距都不会被发现（v0.6.11 审查发现）。现在参数改用
  // 配对括号扫描（`_spacingHead` 认函数头 + `_balancedArgs` 按深度取参数）：字符串
  // 内容已由 `blankNonCode` 清成空格，参数里的 `)` 不会打乱深度，嵌套括号自然配平。

  test('带子 widget 的 SizedBox 也要扫', () {
    expect(
        _spacingViolationsIn('t.dart', 'SizedBox(width: 6, child: Text("x"))'),
        hasLength(1),
        reason: '带 child 的 SizedBox 必须照扫');
    expect(
        _spacingViolationsIn('t.dart', 'SizedBox(width: 4, child: Text("x"))'),
        isEmpty);
    // 保留原语义：算式里的数字不算间距值。
    expect(
        _spacingViolationsIn('t.dart',
            'SizedBox(width: cellW - _cellInset * 2, child: Text("x"))'),
        isEmpty,
        reason: '算式里的 2 不是间距值');
    // 嵌套两层也要能配平。
    expect(
        _spacingViolationsIn('t.dart',
            'SizedBox(width: 6, child: Center(child: Text("x")))'),
        hasLength(1));
    // 反面：子 widget 自己调用的参数不是这次调用的间距 —— 旧正则靠「有嵌套括号
    // 就整条跳过」挡住，现在靠 `_depthAt` 只扫深度 0 的数字。少了这道闸，下面
    // 这几个都会被误报（实测在现有代码里一次报出 15 处）。
    expect(
        _spacingViolationsIn(
            't.dart', 'SizedBox(width: 8, child: Text("x", overflow: 3))'),
        isEmpty,
        reason: '嵌套调用里的 3 不是间距');
    expect(
        _spacingViolationsIn('t.dart',
            'SizedBox(width: 12, child: BoxShadow(alpha: 0.35, blur: 2))'),
        isEmpty,
        reason: '嵌套调用里的 0.35 / 2 不是间距');
    // `EdgeInsets.symmetric` / `EdgeInsets.all` 两种形态都认得（`all` 那条在
    // 「间距扫描认得单参数写法」里钉过，这里补 `symmetric`）。
    expect(
        _spacingViolationsIn(
            't.dart', 'EdgeInsets.symmetric(horizontal: 6, vertical: 8)'),
        hasLength(1));
    // 调用没闭合（源码被截断）当成没有这次调用：既不报，也不能一路走到文件尾
    // 把后面的代码全当成参数（那样会误报）。
    expect(
        _spacingViolationsIn('t.dart', 'SizedBox(width: 6, child: Text("x")'),
        isEmpty,
        reason: '未闭合的调用跳过，不崩也不报');
  });

  // ── 间距类常量：提升成命名常量不能绕过扫描 ──
  //
  // 间距规则只看 `SizedBox` / `EdgeInsets` 的字面量参数；把 `6` 提成
  // `const double _innerPad = 6;` 再引用，数字本身就从参数位挪走了 —— 旧规则
  // 静默放行，等于给「顺手包一层常量」开了后门。下面两条把它堵上：规则**按名字
  // 收窄**到含 `Pad`/`Gap`/`Inset`/`Spacing` 的 `const`（大小写不敏感），并要求
  // 「真要保留 off-grid 值」必须**具名豁免**、且豁免要写清理由。

  test('间距类常量不再逃过扫描', () {
    // 名字带这四个词的常量要查
    expect(_constantViolationsIn('t.dart', 'static const double _extraPad = 6;'),
        hasLength(1));
    expect(
        _constantViolationsIn('t.dart', 'const double _fooSpacing = 2;'),
        hasLength(1));
    expect(_constantViolationsIn('t.dart', 'const inset = 3.0;'), hasLength(1));
    // 合法值不报
    expect(_constantViolationsIn('t.dart', 'static const double _aPad = 8;'),
        isEmpty);
    expect(_constantViolationsIn('t.dart', 'static const double _aGap = 1;'),
        isEmpty);
    // 名字不含这四个词的不查 —— 控件几何 / 比例不归间距管
    expect(_constantViolationsIn('t.dart', 'static const _trackHeight = 190.0;'),
        isEmpty);
    expect(_constantViolationsIn('t.dart', 'static const _aspect = 0.78;'),
        isEmpty);
    // 注释掉的声明不算
    expect(
        _constantViolationsIn('t.dart', '// static const double _oldPad = 6;'),
        isEmpty);
  });

  test('具名豁免：写了理由才豁免', () {
    expect(
        _constantViolationsIn('t.dart',
            '// design-tokens-ignore: 命中区推导值\nstatic const double _hitPad = 6;'),
        isEmpty,
        reason: '带理由的标记应当豁免');
    expect(
        _constantViolationsIn('t.dart',
            'static const double _hitPad = 6; // design-tokens-ignore: 同行也行'),
        isEmpty);
    expect(
        _constantViolationsIn(
            't.dart', '// design-tokens-ignore:\nstatic const double _hitPad = 6;'),
        hasLength(1),
        reason: '只有标记没理由不算数');
    expect(
        _constantViolationsIn('t.dart',
            '// design-tokens-ignore: 隔了两行\n\n\nstatic const double _hitPad = 6;'),
        hasLength(1),
        reason: '豁免只作用于紧邻的上一行或同一行');
  });

  // ── 扫描器自身的「已知边界」：也用能失败的用例钉住 ──
  //
  // 上面各条钉的是「会怎么报」；这一组钉的是**扫描器边界本身**（有意不处理的
  // 写法）。两条行为都是有意为之，将来一次「顺手重构」就可能把洞悄悄开大。
  // 每条都写成能失败的用例 —— 把对应实现改成相反的极端行为，用例会红。

  test('字面量扫描边界：注释与字符串内容不参与扫描', () {
    // **旧行为已反转**：扫描器曾读原始源码，注释里的 `fontSize: 10` 也会被报
    // （上一轮的设计，当时的理由是「跳过注释需要词法分析，本轮不做」）。那让
    // 「注释里不能提及被禁模式」成了一条没法长期维持的约定 —— 有人把基线值写进
    // 注释说明问题，构建就红了。那是**误报**，不是漏检。现在规则跑 `blankNonCode`
    // 剥过的副本（注释与字符串内容已成等长空格），二者里的字面量一律不报。
    //
    // 这条从**正面**钉住新语义：把实现改回「读原始源码」，下面几个 `isEmpty`
    // 立刻转红。**具名豁免标记仍是注释**，所以豁免判定必须回原始源码查 ——
    // 这个「规则看剥过的副本、豁免看原文」的双轨结构见 `_violationsIn`。
    const legacy = '''
// 历史遗留写法示例：fontSize: 10
Widget a() => const SizedBox.shrink();
''';
    expect(_violationsIn('synthetic.dart', legacy), isEmpty);

    // 行注释 / 块注释 / 单双引号字符串 / 跨行三引号字符串，内容都不参与扫描。
    expect(_violationsIn('t.dart', '// 基线是 fontSize: 10\n'), isEmpty);
    expect(_violationsIn('t.dart', '/*\n fontSize: 10\n*/\n'), isEmpty);
    expect(_violationsIn('t.dart', "Text('fontSize: 10');"), isEmpty);
    expect(_violationsIn('t.dart', 'Text("Color(0xFFFFFFFF)");'), isEmpty);
    expect(_violationsIn('t.dart', "Text('''\nfontSize: 10\n''');"), isEmpty);
    // 原始字符串内容同样清。
    expect(_violationsIn('t.dart', "Text(r'fontSize: 10');"), isEmpty);

    // 但真代码照报。
    expect(_violationsIn('t.dart', 'Text(x, style: TextStyle(fontSize: 10));'),
        hasLength(1));
    // 字符串里含 `//` 不能把后面的代码当成注释吞掉（否则会漏检真代码 ——
    // 那是把误报修成漏检，比原来更糟）。
    const src =
        "Text('https://example.com');\nText(x, style: TextStyle(fontSize: 10));";
    expect(_violationsIn('t.dart', src), hasLength(1),
        reason: '字符串里的 // 不得吞掉紧随其后的代码');

    // ── 原始字符串：结束引号前的 `\` 不转义，后面的真代码**不得**被吞掉 ──
    //
    // `r'a\'` 是合法 Dart（内容是 `a\`）。若照普通字符串「跳转义」，扫描器会
    // 以为引号没结束、一路吞到下一个引号或文件尾 —— 把中间的真代码静默清成
    // 空格，那是**漏检**。下面这条钉住「后面的 fontSize: 10 照报」。
    const rawBackslash = r"var s = r'a\'; var t = TextStyle(fontSize: 10);";
    final rawHit = _violationsIn('t.dart', rawBackslash);
    expect(rawHit, hasLength(1), reason: rawHit.join('\n'));
    expect(rawHit.single, contains('字号'));
    // 反面：普通字符串里的转义行为**不变** —— `'a\\'` 是两个字符 `a\`，
    // `\\` 吃掉的是反斜杠而不是引号，字符串正常结束，后面真代码照报。
    const escaped = r"var s = 'a\\'; var t = TextStyle(fontSize: 10);";
    expect(_violationsIn('t.dart', escaped), hasLength(1));

    // ── 块注释可嵌套：内层注释的正文不得被当成代码露出来 ──
    //
    // `/* a /* b */ fontSize: 10 */` 整体是一段注释（内层 `/* b */` 配对后
    // 仍在注释内）。若用 `indexOf('*/')` 停在第一个 `*/`，`fontSize: 10` 就
    // 会露成代码、被**误报** —— 正是本任务要消掉的那一类。
    expect(_violationsIn('t.dart', '/* a /* b */ fontSize: 10 */'), isEmpty);
    // 单层块注释（既有行为）照旧不报。
    expect(_violationsIn('t.dart', '/* fontSize: 10 */'), isEmpty);
    // 嵌套注释**结束之后**的真代码照报 —— 别把嵌套修成「一路吞到文件尾」。
    expect(_violationsIn('t.dart', '/* a /* b */ c */ TextStyle(fontSize: 10);'),
        hasLength(1));
  });

  test('字重扫描边界：条件表达式里带函数调用会漏（要修需括号感知解析）', () {
    // 字重正则把 `)` `,` `;` 当作值的边界（见 `_rules` 注释）。所以
    // `fontWeight: f(x) ? …` 里那个 `)` 会提前终止值的扫描、匹配不到后面的
    // `FontWeight.` —— 这是**已知边界**：要修需要括号感知的解析，本轮不做。
    // 这条钉住「它确实会漏」，免得将来有人把它当成「已经能处理」而据此清理
    // 代码里其实没被覆盖的写法。
    const src = '''
Text('x', style: TextStyle(
  fontWeight: heavy(x) ? FontWeight.w700 : FontWeight.w500,
));
''';
    final weight =
        _violationsIn('synthetic.dart', src).where((v) => v.contains('字重'));
    expect(weight, isEmpty,
        reason: '条件表达式里带函数调用时字重应当漏检（已知边界）');
  });

  // ── 令牌规格（本文件原有的一组，随守门测试一并保留）──
  //
  // 这一组盯的是色板 / 圆角 / 玻璃配方 / WCAG 对比度这些**数值本身**，
  // 与上面两条（角色令牌尺寸、界面层字面量）是同一职责的两半，不要删。

  test('圆角/间距/模糊令牌为预期档位', () {
    expect(AppTokens.radiusS, 12);
    expect(AppTokens.radiusM, 16);
    expect(AppTokens.radiusL, 22);
    expect(AppTokens.radiusXL, 28);
    expect(AppTokens.blurCard, 18);
    expect(AppTokens.blurPanel, 24);
  });

  test('中性背景与语义色非空且区分明暗', () {
    expect(AppTokens.bgLight, isNot(equals(AppTokens.bgDark)));
    expect(AppTokens.inkLight, isNot(equals(AppTokens.inkDark)));
    expect(AppTokens.danger, const Color(0xFFE53935));
  });

  test('accentGradient 用 accent 色：顶 0.85 底 0.50', () {
    final g = AppTokens.accentGradient(const Color(0xFF00C7BE));
    expect(g.colors.first, const Color(0xFF00C7BE).withValues(alpha: 0.85));
    expect(g.colors.last, const Color(0xFF00C7BE).withValues(alpha: 0.50));
  });

  test('玻璃配方随明暗变化（暗色更淡）', () {
    final lightTop = AppTokens.glassTint(false, true).first;
    final darkTop = AppTokens.glassTint(true, true).first;
    expect(lightTop.a, greaterThan(darkTop.a));
  });

  test('navBorder 亮色为深描边、暗色为白描边', () {
    final light = AppTokens.navBorder(false);
    final dark = AppTokens.navBorder(true);
    expect(light.r, lessThan(0.3)); // 深色
    expect(dark.r, greaterThan(0.9)); // 白
    expect(light.a, greaterThan(0.08));
  });

  test('5 个主题色在胶囊滑块上文字对比度 ≥ 4.5', () {
    // 模拟滑块：主题色渐变与玻璃底按 60% 混合（文字所在区域的近似比例）
    const bgLight = Color(0xFFF5F6FA);
    const bgDark = Color(0xFF16161E);
    for (final accent in AppColors.accentPalette) {
      final sliderLight = Color.lerp(bgLight, accent, 0.6)!;
      expect(
        _wcagContrast(AppTokens.navForeground(false, accent), sliderLight),
        greaterThanOrEqualTo(4.5),
        reason: '亮色模式 $accent',
      );
      final sliderDark = Color.lerp(bgDark, accent, 0.6)!;
      expect(
        _wcagContrast(AppTokens.navForeground(true, accent), sliderDark),
        greaterThanOrEqualTo(4.5),
        reason: '暗色模式 $accent',
      );
    }
  });

  test('onSolid：任何底色上的文字对比度都 ≥ 4.5', () {
    // 白/黑两条对比度曲线在亮度 0.179 处交叉，交叉点上各是 4.58:1 ——
    // 所以「取对比度高的一侧」对**任何**底色都能过 AA。
    const samples = <Color>[
      Color(0xFF4C8DFF),
      Color(0xFF7A5CFF),
      Color(0xFF9AA0B4),
      Color(0xFF5A5F73),
      Color(0xFF34C759),
      Color(0xFFFF9F0A),
      Color(0xFFFF375F),
      Color(0xFF00C7BE),
      Color(0xFFFFFFFF),
      Color(0xFF000000),
    ];
    for (final bg in samples) {
      expect(_wcagContrast(AppTokens.onSolid(bg), bg), greaterThanOrEqualTo(4.5),
          reason: '底色 $bg 上取到的文字色不可读');
    }
    for (final accent in AppColors.accentPalette) {
      expect(_wcagContrast(AppTokens.onSolid(accent), accent),
          greaterThanOrEqualTo(4.5),
          reason: '主题色 $accent 上取到的文字色不可读');
    }

    // 钉住几个具体选择：只断言「对比度够」的话，把实现换成恒定白字仍然
    // 会在橙、绿、灰上失败，但在蓝紫上会通过 —— 那说明它没在按底色选。
    expect(AppTokens.onSolid(const Color(0xFF4C8DFF)), Colors.black);
    expect(AppTokens.onSolid(const Color(0xFF7A5CFF)), Colors.black);
    expect(AppTokens.onSolid(const Color(0xFF9AA0B4)), Colors.black);
    expect(AppTokens.onSolid(const Color(0xFFFF9F0A)), Colors.black);
    expect(AppTokens.onSolid(const Color(0xFF5A5F73)), Colors.white);
  });
}
