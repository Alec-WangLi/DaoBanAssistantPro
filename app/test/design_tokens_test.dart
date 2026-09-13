// app/test/design_tokens_test.dart
//
// 这一轮（设计语言 v2）把「界面层不写数值」从文档里的一句话变成了会红的东西。
//
// 两条：
//   1. 角色令牌的字号 / 字重 / 行高必须等于规格里那张表 —— 改令牌就得先改规格。
//   2. lib/features · lib/core/widgets · lib/core/glass 下不许出现字面量。
//      迁移期间用 _pending 兜住还没迁完的文件，每迁完一块划掉一个；
//      Task 8 收口后这个集合已删 —— 这条规则从此扫**全部**文件、没有任何豁免。
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
];

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

List<String> _violations(String path) =>
    _violationsIn(path, File(path).readAsStringSync());

/// 扫一段源码里的字面量。拆出「读文件」这一步是为了能用临时文本单测 ——
/// [path] 只进报告、不参与判断（与 `_spacingViolationsIn` 同一套路）。
List<String> _violationsIn(String path, String src) {
  final out = <String>[];
  for (final rule in _rules.entries) {
    for (final m in rule.value.allMatches(src)) {
      // `copyWith(fontWeight: …)` 是一个角色内的刻意变化，允许（见规格 §3.2）。
      // 判据是「这次匹配落在某个 `copyWith(` 调用的括号里」，而不是「同一行含
      // copyWith」—— 值跨行时 `copyWith(` 会留在上一行，行级判定会把合法调用误报。
      if (rule.key.startsWith('字重') && _insideCopyWith(src, m.start)) continue;
      final at = _lineAt(src, m.start);
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

final RegExp _spacingCall =
    RegExp(r'(SizedBox|EdgeInsets\.[a-zA-Z]+)\(([^()]*)\)');
final RegExp _numberIn = RegExp(r'[0-9]+(?:\.[0-9]+)?');

/// 注意 `_spacingCall` 的参数部分写的是 `[^()]*` 而不是 `[^)]*`：**参数里一旦
/// 出现另一个括号就整条跳过**。否则 `SizedBox(width: cellW, child: Center(…)`
/// 会把 `child` 里那些字号、个数一路当成间距扫进来，全是误报。
///
/// 代价是带到子 widget 的 `SizedBox`（`child: Row(…)` 那种）不检查 —— 那种位置
/// 本来也很少写间距值。审计实测：这条规则在现有代码里报出 43 处，**零误报**。
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
List<String> _spacingViolationsIn(String path, String src) {
  final out = <String>[];
  final seen = <String>{};
  for (final call in _spacingCall.allMatches(src)) {
    final args = call.group(2)!;
    for (final m in _numberIn.allMatches(args)) {
      final before = _charBefore(args, m.start);
      final after = _charAfter(args, m.end);
      // 只把「整个参数就是一个数字」的当成间距值，跳过算式里的数字
      // （`width: cellW - _cellInset * 2` 的 2 是算式的一部分）。
      //
      // **空串要放行**：位置 0 的数字前面没有字符可看，`_charBefore` 返回空串 ——
      // 那正说明它就是整个参数本身（`EdgeInsets.all(2)` 的 args 就是 `"2"`，
      // `SizedBox(width: 6)` 的 args 是 `"width: 6"` 有 `':'`）。少了这一条，
      // 单参数写法会静默漏检，「守门测试绿」就不等于「文件里没有字面量」了。
      if (before != '' && before != ':' && before != ',' && before != '(') continue;
      if (after != ',' && after != ')' && after != '') continue;
      final n = double.parse(m.group(0)!);
      if (_spacingOk(n)) continue;
      final line = src.substring(0, call.start + m.start).split('\n').length;
      final key = '$line:$n';
      if (!seen.add(key)) continue;
      out.add('$path:$line  间距不在 4px 栅格上：$n'
          '（改用 spaceXxx 或 gapHair/padChipV/gapIconText/gapIconTextLg）');
    }
  }
  return out;
}

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

    expect([AppTokens.iconSm, AppTokens.iconMd, AppTokens.iconLg], [16, 20, 24]);
    expect([AppTokens.spaceXs, AppTokens.spaceSm, AppTokens.spaceMd,
        AppTokens.spaceLg, AppTokens.spaceXl, AppTokens.space2xl,
        AppTokens.space3xl], [4, 8, 12, 16, 20, 24, 32]);
    expect([AppTokens.gapHair, AppTokens.gapIconText, AppTokens.gapIconTextLg],
        [2, 6, 10]);
    expect(AppTokens.durFlow, const Duration(milliseconds: 650));

    expect(AppTokens.inkMutedAlpha, 0.62,
        reason: '浅色最坏底 #F5F6FA 上 0.62 才到 4.70:1 过 AA（0.60 只有 4.33:1）');
    expect(AppTokens.inkFaintAlpha, 0.35,
        reason: '禁用/已完成档，有意低于 AA（见规格 §3.3）');
    expect(AppTokens.pillOf(40),
        const BorderRadius.all(Radius.circular(20)));
  });

  test('界面层不写数值', () {
    final offenders = <String>[];
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
      }
    }
    expect(offenders, isEmpty,
        reason: '界面层只能引用令牌，发现 ${offenders.length} 处字面量：\n'
            '${offenders.join('\n')}');
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
