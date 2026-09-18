# 守门测试收口与阶梯校正 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让那条守门测试重新等于「界面层真的没有字面量」——补齐它的漏检、消掉它的误报、封掉「把值提成常量就能绕过」的路径；顺带把阶梯里唯一一处角色分配错误改正，并给一个名不副实的令牌改名。

**Architecture:** 全部改动集中在 `app/test/design_tokens_test.dart`。核心是把扫描管线从「原始源码 → 正则」改成「原始源码 →（剥掉注释与字符串内容的等长副本）→ 正则」，并在这条管线旁边加三样东西：配对括号取参数串、常量声明规则、`// design-tokens-ignore: <理由>` 具名豁免。另有三处小的代码/规格/命名校正。

**Tech Stack:** Flutter 3.x / Dart 3、flutter_test、项目自带出图工装 `app/tool/visual`。

**Spec:** `docs/superpowers/specs/2026-09-13-guard-hardening-and-ladder-design.md`

## Global Constraints

- 目标版本 `0.6.12+83`。`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须同步（`app/test/app_info_test.dart` 盯着）。**`X.Y` 由用户决定，AI 只改末位 `Z` 与 `build`。**
- 每个任务收尾必须：`flutter analyze` 0 error / 0 warning，`flutter test` 全绿（当前 137 条）。
- **不要跑 `dart format`。** 本工具链是 tall style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `analyze`。
- **不改任何界面布局、不改业务逻辑、不改配色与玻璃配方。** 本轮唯一的视觉变化是底部导航图标 20→24。
- 每一处新机制都要有**正反两面的用例**，并且实现者要**验证过它不是恒真**（把对应实现改成相反的极端行为，用例必须变红）。
- `docs/` 在 gitignore 里，规格与计划不入库 —— 改它们是本地文件操作，不进提交。
- 提交信息用中文，格式 `type(scope): 描述`。

## 0. 环境

工作目录一律是仓库根 `C:\Users\Alec\Documents\DeepSeekHermesData\shiftassistant`。每个新 shell 先设：

```bash
export JAVA_HOME="$PWD/toolchain/jdk" ANDROID_HOME="$PWD/toolchain/android-sdk" \
       GRADLE_USER_HOME="$PWD/toolchain/gradle-home" PUB_CACHE="$PWD/toolchain/pub-cache" \
       ANDROID_USER_HOME="$PWD/toolchain/android-user" FLUTTER_ROOT="$PWD/toolchain/flutter" \
       APPDATA="$PWD/toolchain/appdata" LOCALAPPDATA="$PWD/toolchain/localappdata"
export PATH="$PWD/toolchain/flutter/bin:$PWD/toolchain/jdk/bin:$PATH"
```

`flutter test` / `flutter analyze` 的工作目录是 `app/`。

## 文件结构

| 文件 | 职责 | 变化 |
|---|---|---|
| `app/test/design_tokens_test.dart` | 守门测试：令牌自检 + 界面层字面量扫描 | **本轮的主战场**：剥注释字符串、配对括号、常量规则、具名豁免、自检完整性检查 |
| `app/lib/core/design_tokens.dart` | 设计令牌唯一来源 | `durFlow` → `durRingEnter` |
| `app/lib/core/theme/app_colors.dart` | 配色层（主色板 + 班次数据色 + 语义色） | 新增 `bgBlob` |
| `app/lib/core/theme/animated_background.dart` | 响铃背景光晕（渲染文件） | 那处色值改用 `AppColors.bgBlob` |
| `app/lib/features/home/home_shell.dart` | 导航壳 | 导航图标 `iconMd` → `iconLg`；`_innerPad` 改引用令牌 |
| `app/lib/features/alarm/alarm_ringing_screen.dart` | 响铃界面 | 只改 `durFlow` → `durRingEnter` 的引用（它的三个几何常量名里没有 Pad/Gap/Inset/Spacing，不在常量规则的范围内，无需标记） |
| `app/lib/features/calendar/calendar_screen.dart` | 日历 | `_cellInset` 改引用令牌 |
| `app/lib/features/calendar/shift_template_picker_screen.dart` | 模板选择 | `_stripSpacing` 改引用令牌 |
| `app/lib/core/widgets/glass_segment.dart` | 分段控件 | `inset` 改引用令牌 |
| `app/lib/core/widgets/glass_choice_chip.dart` | 选择 chip | `_hitPad` 带豁免标记 |

不改动：`app/lib/data/**`、`app/lib/domain/**`、`app/lib/state/**`、`app/android/**`、`app/lib/core/theme/app_theme.dart`（本轮不碰主题装配）。

---

## Task 1: 扫描器剥掉注释与字符串内容

**Files:**
- Modify: `app/test/design_tokens_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `String blankNonCode(String src)` —— 把源码里的行注释、块注释、字符串字面量**内容**替换成**等长空格**（换行保留），偏移与行号不变。后续所有规则都跑在它的返回值上。

**为什么先做这个**：它是后面三条的**前置**。配对括号扫描要靠它把参数里的字符串清掉（否则参数里的 `)` 会打乱括号深度）；常量规则要靠它把注释掉的声明清掉（否则会误报）；而**具名豁免标记是注释**，所以豁免判定必须回到原始源码上查 —— 这个「规则看空白副本、豁免看原文」的双轨结构由本任务确立。

- [ ] **Step 1: 写失败用例**

在 `design_tokens_test.dart` 的 `main()` 里加一条：

```dart
  test('注释与字符串内容不参与扫描', () {
    // 注释里的字面量不该报 —— 否则没人能在注释里写「别用 fontSize: 10」。
    expect(_violationsIn('t.dart', '// 基线是 fontSize: 10\n'), isEmpty);
    expect(_violationsIn('t.dart', '/*\n fontSize: 10\n*/\n'), isEmpty);
    // 字符串内容同理。
    expect(_violationsIn('t.dart', "Text('fontSize: 10');"), isEmpty);
    expect(_violationsIn('t.dart', 'Text("Color(0xFFFFFFFF)");'), isEmpty);
    // 但真代码照报。
    expect(_violationsIn('t.dart', 'Text(x, style: TextStyle(fontSize: 10));'),
        hasLength(1));
    // 字符串里含 `//` 不能把后面的代码当成注释吞掉。
    final src = "Text('https://example.com');\nText(x, style: TextStyle(fontSize: 10));";
    expect(_violationsIn('t.dart', src), hasLength(1),
        reason: '字符串里的 // 不得吞掉紧随其后的代码');
    // 三引号字符串跨行也要认。
    expect(_violationsIn('t.dart', "Text('''\nfontSize: 10\n''');"), isEmpty);
  });
```

- [ ] **Step 2: 跑，确认失败**

```bash
cd app && flutter test test/design_tokens_test.dart --plain-name 注释与字符串内容不参与扫描
```

Expected: FAIL（注释里的 `fontSize: 10` 现在会被报出来）。

- [ ] **Step 3: 实现 `blankNonCode`**

在文件顶部（`_rules` 之前）加：

```dart
/// 把源码里的**非代码部分**替换成**等长空格**：行注释、块注释、字符串字面量的内容。
///
/// 为什么要等长替换而不是删掉：所有规则都靠「命中偏移 → 行号」定位（`_lineAt`），
/// 删字符会让偏移全错。换成空格则偏移与行号纹丝不动。
///
/// 换行**保留** —— 行数也不能变。
///
/// 注意：**具名豁免标记写在注释里**，所以豁免判定必须回到**原始源码**上查，
/// 不能查这个副本（注释在这里已经是空格了）。见 `_ignoreReasonAt`。
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
    // 块注释：到 */ 之后
    if (src.startsWith('/*', i)) {
      final end = src.indexOf('*/', i + 2);
      final stop = end < 0 ? src.length : end + 2;
      blank(i, stop);
      i = stop;
      continue;
    }
    final c = src[i];
    if (c == "'" || c == '"') {
      // r'…' 这种原始字符串：引号本身照常处理，内容一样要清。
      final triple = i + 2 < src.length && src[i + 1] == c && src[i + 2] == c;
      final quote = triple ? c * 3 : c;
      var j = i + quote.length;
      while (j < src.length) {
        if (src[j] == '\\') {
          j += 2; // 跳过转义的下一个字符
          continue;
        }
        if (src.startsWith(quote, j)) break;
        j++;
      }
      final stop = j >= src.length ? src.length : j + quote.length;
      // 只清**内容**，引号保留（更直观，也不影响任何规则）。
      blank(i + quote.length, j);
      i = stop;
      continue;
    }
    i++;
  }
  return out.join();
}
```

然后把 `_violationsIn` 的入口改成先剥一遍：

```dart
List<String> _violationsIn(String path, String src) {
  final code = blankNonCode(src);
  final out = <String>[];
  for (final rule in _rules.entries) {
    for (final m in rule.value.allMatches(code)) {
      // `copyWith(fontWeight: …)` 是一个角色内的刻意变化，允许（见规格 §3.2）。
      // 判据是「这次匹配落在某个 `copyWith(` 调用的括号里」，而不是「同一行含
      // copyWith」—— 值跨行时 `copyWith(` 会留在上一行，行级判定会把合法调用误报。
      if (rule.key.startsWith('字重') && _insideCopyWith(code, m.start)) continue;
      final at = _lineAt(src, m.start); // 行号在两份源码上一致（等长替换）
      out.add('$path:${at.line}  ${rule.key}\n      ${at.text}');
    }
  }
  return out;
}
```

**注意**：`_insideCopyWith(code, …)` 与 `_lineAt(src, …)` 混用是**有意**的 —— 前者要在剥过的副本上判（避免字符串里的 `copyWith` 文本干扰），后者要在原文上取（要拿到带注释的可读文本）。两份串等长，偏移通用。

- [ ] **Step 4: 跑，确认通过**

```bash
cd app && flutter test test/design_tokens_test.dart
```

Expected: 全绿（新用例通过，既有用例不受影响）。

- [ ] **Step 5: 删掉/改写那条钉着旧行为的既有用例**

`design_tokens_test.dart:380` 有一条 **`test('字面量扫描边界：注释里的 fontSize 也会被扫到（扫描读原始源码）', …)`** —— 它断言的正是「注释会被扫到」这个**旧行为**。本任务把这个行为改掉了，所以那条用例现在语义反了。

**处理**：把它的名字与断言改成新语义（注释里的 `fontSize: 10` **不报**），并把它与 Step 1 新加的那条合并（内容重复，留一条就够）。**不要**只把它删掉 —— 它是「注释与字符串不参与扫描」这条性质的正面钉子。

- [ ] **Step 6: 验证用例不是恒真**

临时把 `_violationsIn` 里的 `final code = blankNonCode(src);` 改回 `final code = src;`，重跑 → 新用例必须**红**。改回来。

- [ ] **Step 7: 提交**

```bash
git add app/test/design_tokens_test.dart
git commit -m "test(tokens): 扫描器剥掉注释与字符串内容，消掉误报"
```

---

## Task 2: 间距扫描改用配对括号取参数

**Files:**
- Modify: `app/test/design_tokens_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `blankNonCode`（参数里的字符串已变成空格，括号深度不会被字符串里的 `)` 打乱）
- Produces: `_spacingViolationsIn` 覆盖带子 widget 的调用形如 `SizedBox(width: 6, child: …)`

- [ ] **Step 1: 写失败用例**

```dart
  test('带子 widget 的 SizedBox 也要扫', () {
    // 现在这条整条跳过（参数正则 `[^()]*` 跨不过嵌套括号）—— 于是这种写法里
    // 写多大的间距都不会被发现。
    expect(
        _spacingViolationsIn('t.dart', 'SizedBox(width: 6, child: Text("x"))'),
        hasLength(1),
        reason: '带 child 的 SizedBox 必须照扫');
    expect(
        _spacingViolationsIn('t.dart', 'SizedBox(width: 4, child: Text("x"))'),
        isEmpty);
    // 保留原语义：算式里的数字不算间距值。
    expect(
        _spacingViolationsIn(
            't.dart', 'SizedBox(width: cellW - _cellInset * 2, child: Text("x"))'),
        isEmpty,
        reason: '算式里的 2 不是间距值');
    // 嵌套两层也要能配平。
    expect(
        _spacingViolationsIn('t.dart',
            'SizedBox(width: 6, child: Center(child: Text("x")))'),
        hasLength(1));
  });
```

- [ ] **Step 2: 跑，确认失败**

```bash
cd app && flutter test test/design_tokens_test.dart --plain-name 带子widget的SizedBox也要扫
```

（用例名带空格，`--plain-name` 用不含空格的关键片段即可，例如 `--plain-name 配对括号` 若你把它写进名字里；否则直接跑整个文件。）

Expected: FAIL。

- [ ] **Step 3: 实现配对括号取参数**

把 `_spacingCall` 这个正则换成「找函数头 + 走括号深度」两个动作：

```dart
final RegExp _spacingHead = RegExp(r'(SizedBox|EdgeInsets\.[a-zA-Z]+)\(');

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
```

**⚠️ 还需要一层深度过滤（写计划时漏了，实装时才发现）。** 取出参数串之后**不能**直接扫里面所有数字 —— 旧的 `[^()]*` 正则用「有嵌套括号就整条跳过」顺带挡住了嵌套调用里的数字，换成配对括号之后那道挡板就没了。照上面那样直接扫，会在 `lib/` 里报出 **15 处误报**（`child: Row(…)` 里的 `withValues(alpha: 0.35)`、`strokeWidth: 2.6`、`length: 2`、`List.generate(7, …)` 之类），并且让「界面层不写数值」那条直接失败 —— 与「除一条既有用例之外全绿」的预期矛盾，也会逼你去改 15 处 lib（超出本任务范围）。

所以还要一个「这个数字在参数串的第几层括号里」：

```dart
/// [index] 处在参数串 [s] 里的括号嵌套深度（`(` 记 +1，`)` 记 -1）。
///
/// 只有**深度 0** 的数字才是这次调用的直接参数。嵌套调用里的数字一律不算 ——
/// 那正是旧正则用「有嵌套括号就整条跳过」挡住的那一批。
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
```

主循环里取到 `m` 之后先 `if (_depthAt(args, m.start) != 0) continue;`，**再做 `_charBefore` / `_charAfter` 那两道判据**。

`_spacingViolationsIn` 的主循环从「正则匹配整条调用」改成：

```dart
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
      final before = _charBefore(args, m.start);
      final after = _charAfter(args, m.end);
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
```

**`_charBefore` / `_charAfter` / `_spacingOk` / `_numberIn` 保持原样。** `_charBefore` 里对位置 0 的放行（空串）本来就对 —— `EdgeInsets.all(2)` 的参数串就是 `"2"`。

- [ ] **Step 4: 跑，确认通过**

```bash
cd app && flutter test test/design_tokens_test.dart && flutter test
```

Expected: 全绿。

**但有一条既有用例必然变红**：`design_tokens_test.dart:368` 的
**`test('间距扫描边界：带子 widget 的 SizedBox 不扫（参数里有嵌套括号就整条跳过）', …)`**
—— 它断言的正是旧行为，现在被推翻了。处理：

1. 把它的名字与断言改成新语义（**要报**），用例名相应改成「带子 widget 的 SizedBox 也要扫」；它与本任务 Step 1 新加的那条重复，**合并成一条**即可。
2. 同时改掉 `_spacingCall` 上方那段注释（现在写着「参数里出现另一个括号就整条跳过…代价是带到子 widget 的 SizedBox 不检查」）—— 那段说明随正则一起被替换掉了。

**不要**只删掉那条用例：它是「这种写法不再漏」的正面钉子。

- [ ] **Step 5: 验证用例不是恒真**

临时把 `_balancedArgs` 改成永远返回 `null` → 新用例必须红。改回来。

- [ ] **Step 6: 提交**

```bash
git add app/test/design_tokens_test.dart
git commit -m "test(tokens): 间距扫描改配对括号，带子 widget 的调用不再漏"
```

---

## Task 3: 常量规则与具名豁免

**Files:**
- Modify: `app/test/design_tokens_test.dart`
- Modify: `app/lib/features/calendar/calendar_screen.dart:33`
- Modify: `app/lib/features/calendar/shift_template_picker_screen.dart:263`
- Modify: `app/lib/features/home/home_shell.dart:173`
- Modify: `app/lib/core/widgets/glass_segment.dart:125`
- Modify: `app/lib/core/widgets/glass_choice_chip.dart:38`

**Interfaces:**
- Consumes: Task 1 的 `blankNonCode`（规则跑在剥过的副本上，注释掉的声明不会被误报）
- Produces: `_constantViolationsIn(String path, String src)`；`String? _ignoreReasonAt(String rawSrc, int line)`

**背景（规格 §3.3 实测）**：扫描目录里 off-grid 的 `const double` 共 **15 处**，但**只有 4 处是真间距**，其余是控件几何 / 比例 / 计数 / 一个测试 id。所以规则**按名字收窄**到含 `Pad`/`Gap`/`Inset`/`Spacing` 的常量 —— 全扫的话要付 11 条永久豁免注释，信号会被淹掉。

- [ ] **Step 1: 写失败用例**

```dart
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
```

- [ ] **Step 2: 跑，确认失败**

```bash
cd app && flutter test test/design_tokens_test.dart
```

Expected: FAIL —— `_constantViolationsIn` 还不存在，编译不过。

- [ ] **Step 3: 实现常量规则与豁免**

```dart
/// 间距类常量：名字里带 `Pad` / `Gap` / `Inset` / `Spacing` 的 `const double`。
///
/// 为什么要按名字收窄：实测扫描目录里 off-grid 的常量有 15 处，**只有 4 处是
/// 真间距**，其余是控件几何（`_trackHeight` 190）、比例（`_cellAspect` 0.78）、
/// 计数（`maxSlots` 14）甚至一个测试 id。全扫要付 11 条永久豁免注释，豁免一多
/// 就没人读了 —— 那是「守门测试绿但没人信」的另一条路。
///
/// 已知边界：把间距提成名字不含这四个词的常量（比如叫 `_k`）仍能逃。
/// 这条规则拦的是「顺手提成常量」的习惯，不是对抗性绕过 —— 要拦后者得做标识符
/// 解析，不划算。
/// **行首要写 `^[ 	]*` 而不是 `^\s*`** —— `\s` 会跨换行，配合 `multiLine` 时
/// 匹配起点会落到声明上面那行空行上，行号因此向上偏，还会让「隔两行的标记」
/// 被当成同行。写计划时正是这么错的，实装时才发现。
/// **大小写不敏感**：真实的那处 `const inset = 3.0;` 是全小写，区分大小写会漏掉它。
final RegExp _constDecl = RegExp(
    r'^[ 	]*(?:static\s+)?const\s+(?:double\s+)?'
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
```

`_constantViolationsIn`：

```dart
/// 豁免过的条目会打进日志 —— 让「故意不扫」看得见，而不是默不作声。
final List<String> spacingConstantWaivers = [];

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
```

把它接进扫描循环（`_violations(path)` 那一条链路）：

```dart
List<String> _violations(String path) {
  final src = File(path).readAsStringSync();
  return [
    ..._violationsIn(path, src),
    ..._spacingViolationsIn(path, src),
    ..._constantViolationsIn(path, src),
  ];
}
```

（若现有代码不是这个形态，按等价的合并方式接上即可；关键是三条扫描都跑。）

- [ ] **Step 4: 把 4 处真间距常量改成引用令牌（值一字不改）**

| 文件 | 现状 | 改成 |
|---|---|---|
| `app/lib/features/calendar/calendar_screen.dart:33` | `static const _cellInset = 2.0;` | `static const _cellInset = AppTokens.gapHair;` |
| `app/lib/features/calendar/shift_template_picker_screen.dart:263` | `const double _stripSpacing = 2;` | `const double _stripSpacing = AppTokens.gapHair;` |
| `app/lib/features/home/home_shell.dart:173` | `static const _innerPad = 6.0;` | `static const _innerPad = AppTokens.gapIconText;` |
| `app/lib/core/widgets/glass_segment.dart:125` | `const inset = 3.0;` | `const inset = AppTokens.padChipV;` |

四个文件都已在 import 里引了 `AppTokens`（它们已经在用别的令牌）；若某个没有，补 import。

- [ ] **Step 5: 给 `_hitPad` 加豁免标记**

`app/lib/core/widgets/glass_choice_chip.dart:38` 上方加一行：

```dart
// design-tokens-ignore: 命中区补到 44dp 触摸目标的推导值，不是设计间距
static const double _hitPad = 6;
```

- [ ] **Step 6: 跑，确认通过**

```bash
cd app && flutter analyze && flutter test
```

Expected: 全绿。若常量规则报出**别的**名字带这四个词的常量（本计划基于实测的清单，可能不全），**不要加豁免了事** —— 先判断它是真间距还是几何：真间距改引用令牌，几何才加豁免。在报告里列出你遇到的每一处与判断依据。

- [ ] **Step 7: 验证用例不是恒真**

临时把 `_ignoreReasonAt` 改成永远返回 `null` → 「带理由的标记」那条必须红。改回来。

- [ ] **Step 8: 提交**

```bash
git add app/test/design_tokens_test.dart app/lib/features app/lib/core/widgets
git commit -m "test(tokens): 间距类常量纳入扫描，用 design-tokens-ignore 具名豁免"
```

---

## Task 4: 扫描范围纳入 `core/theme`，色值收进 `bgBlob`

**Files:**
- Modify: `app/test/design_tokens_test.dart`
- Modify: `app/lib/core/theme/app_colors.dart`
- Modify: `app/lib/core/theme/animated_background.dart:57`

**Interfaces:**
- Consumes: Task 1~3 的扫描管线
- Produces: 无新接口

**背景**：`lib/core/theme/` 整个目录此前不在扫描范围，理由是「配色层本身」。实测该目录 8 处命中里 7 处确实是配色层（`app_colors.dart` 的 5 个主色 + `app_theme.dart` 的 2 个中性 seed），只有 `animated_background.dart` 那 1 处是**渲染文件**里的色值。

- [ ] **Step 1: 写失败用例**

```dart
  test('core/theme 纳入扫描，但配色层两文件显式豁免', () {
    // 配色层本身：豁免（它们是颜色**定义**，不是颜色**用法**）
    expect(_violations('lib/core/theme/app_colors.dart'), isEmpty);
    expect(_violations('lib/core/theme/app_theme.dart'), isEmpty);
    // 渲染文件不豁免 —— 用一段仿真文本钉住「这个目录本身是被扫的」
    expect(
        _violationsIn('lib/core/theme/x.dart', 'const c = Color(0xFFB9BECF);'),
        hasLength(1));
    // **这条不能省**：豁免在 `_violations` 入口生效，所以「把目录从 _scanDirs
    // 删掉」并不会让上面那两条 isEmpty 变红 —— 少了这条，Step 6 的验证是恒真的。
    expect(_scanDirs, contains('lib/core/theme'));
  });
```

- [ ] **Step 2: 跑，确认失败**

Expected: FAIL（`app_colors.dart` 现在不在 `_scanDirs` 里，`_violations` 会扫出它的 5 个主色）。

- [ ] **Step 3: 扩扫描范围 + 加文件级豁免**

```dart
const List<String> _scanDirs = [
  'lib/features',
  'lib/core/widgets',
  'lib/core/glass',
  'lib/core/theme',
];

/// 文件级豁免：**配色层本身**。
///
/// 这两个文件是颜色的**定义处**，不是颜色的**用法** —— 主色板与中性 seed 本来就
/// 该写成字面量，扫它们等于要求令牌引用自己。目录里其余文件（渲染件）照常扫。
const Set<String> _exemptFiles = {
  'lib/core/theme/app_colors.dart',
  'lib/core/theme/app_theme.dart',
};
```

豁免在 **`_violations(path)` 的入口**处生效（不是只在目录遍历那一层）—— 这样无论从目录扫还是直接点某个文件，豁免都成立：

```dart
List<String> _violations(String path) {
  if (_exemptFiles.contains(path)) return const [];
  final src = File(path).readAsStringSync();
  return [
    ..._violationsIn(path, src),
    ..._spacingViolationsIn(path, src),
    ..._constantViolationsIn(path, src),
  ];
}
```

- [ ] **Step 4: 把 `animated_background` 的色值收进配色层**

`app/lib/core/theme/app_colors.dart` 的 `AppColors` 里加：

```dart
  /// 响铃背景中间那团光斑的颜色。中性偏冷的浅蓝灰 ——
  /// 它只在 `FlowingBackground` 里用，不参与主题主色，也不随明暗切换。
  static const Color bgBlob = Color(0xFFB9BECF);
```

`app/lib/core/theme/animated_background.dart:57` 的 `const Color(0xFFB9BECF)` 换成 `AppColors.bgBlob`（并在 import 里引 `app_colors.dart`）。

- [ ] **Step 5: 跑，确认通过**

```bash
cd app && flutter analyze && flutter test
```

- [ ] **Step 6: 验证用例不是恒真**

临时把 `lib/core/theme` 从 `_scanDirs` 里删掉 → 第 1 条用例必须红。改回来。

> **写计划时这处验证是恒真的**（`expect(_scanDirs, contains('lib/core/theme'))` 那一行是实装时补的）：因为豁免在 `_violations` 入口生效，删掉目录表并不会让两条 `isEmpty` 变红。实装时由执行者发现并补上，本计划已同步。

- [ ] **Step 7: 提交**

```bash
git add app/test/design_tokens_test.dart app/lib/core/theme
git commit -m "test(tokens): 扫描范围纳入 core/theme，配色层两文件显式豁免"
```

---

## Task 5: 令牌自检的完整性检查

**Files:**
- Modify: `app/test/design_tokens_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `bool _isLadderToken(String name)`

**背景**：现在的自检是手写枚举的 `expect` 列表，加了令牌忘加断言时测试照样绿 —— v0.6.11 就漏过 `padChipV`。

- [ ] **Step 1: 写失败用例**

```dart
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
```

- [ ] **Step 2: 跑，确认失败**

Expected: FAIL，`_isLadderToken` 还不存在（编译不过）。

- [ ] **Step 3: 实现 `_isLadderToken`**

```dart
/// 15 条角色排版令牌 —— 它们是阶梯的核心，必须逐条自检。
const Set<String> _typography = {
  'ringClock', 'pageTitle', 'bigNumber', 'dialogTitle', 'sectionTitle',
  'cellDate', 'titleStrong', 'labelStrong', 'rowPrimary', 'rowSecondary',
  'labelSecondary', 'microStrong', 'microLabel', 'microText', 'tinyLabel',
};

/// 「阶梯」= 排版 / 图标 / 间距 / 光学 / 圆角 / 明度 alpha / 时长。
///
/// **排版那一类的判据是「声明类型是 `TextStyle`」，不是「名字在某个手写集合里」**
/// （写计划时用的是手写集合 `_typography`，实装后审查指出那与它要修的「手写枚举」
/// 是同一类缺口：新加一档排版令牌、只要名字不在集合里就永远不被要求断言）。
/// 抽取时把类型一并捕获下来即可 —— 令牌文件里所有 `TextStyle` 都是阶梯。
///
/// **不在内**（有意，不是遗漏）：配色（`bg*` / `surface*` / `ink*` / `danger` /
/// `success` / `holiday`）、玻璃配方（`blur*` / `glass*`）、弹簧与缩放
/// （`qSpring` / `pressScale` / `pillGrow`）—— 它们不是阶梯，各自有别的用例盯着，
/// 或本身就是配方。
bool _isLadderToken(String n, String type) =>
    type == 'TextStyle' ||
    n.startsWith('icon') ||
    n.startsWith('space') ||
    n.startsWith('gap') ||
    n.startsWith('pad') ||
    n.startsWith('radius') ||
    n.startsWith('dur') ||
    (n.startsWith('ink') && n.endsWith('Alpha'));
```

- [ ] **Step 4: 跑，确认通过**

```bash
cd app && flutter test test/design_tokens_test.dart
```

Expected: 全绿。若报出 `missing`，把缺的那些补进自检的 `expect` 列表（那是这次检查的**目的**），而不是放宽 `_isLadderToken`。

- [ ] **Step 5: 验证用例不是恒真**

临时删掉自检里任意一条 `expect`（例如 `expect(AppTokens.padChipV, 3, …)` 那一行）→ 完整性用例必须**红**，并点名 `padChipV`。把删掉的那行加回去。

- [ ] **Step 6: 提交**

```bash
git add app/test/design_tokens_test.dart
git commit -m "test(tokens): 令牌自检加完整性检查，漏断言会红"
```

---

## Task 6: 阶梯校正与 `durFlow` 改名

**Files:**
- Modify: `app/lib/features/home/home_shell.dart:379`
- Modify: `app/lib/core/design_tokens.dart`
- Modify: `app/lib/features/alarm/alarm_ringing_screen.dart:40`
- Modify: `app/test/design_tokens_test.dart`（时长规则的提示文案 + 自检里的名字）
- Modify: `docs/superpowers/specs/2026-09-13-design-language-v2-design.md`（§3.1 / §3.2 / §3.6）

**Interfaces:**
- Consumes: Task 5 的完整性检查（改名后它会盯住自检里的名字有没有跟着改）
- Produces: `AppTokens.durRingEnter`（替换 `durFlow`）

**背景（规格 §5，有出图对比作证）**：
- 导航图标：规格 §3.6 现在写「导航项 → `iconMd`(20)」，那是 v0.6.11 定的。对比图显示 **24 更好**（图标在胶囊里站得住）。改成 `iconLg`。**不新增 22 这一档。**
- 圆角：周期色条格子从圆角方块变成圆点**不是缺陷**（对比图里圆点在高密度排布下更清爽）。**不新增圆角档位**，改为在规格里把「≤16dp 实心小元素走 pill」写成规则。

- [ ] **Step 1: 导航图标改成 `iconLg`**

`app/lib/features/home/home_shell.dart:379` 的 `size: AppTokens.iconMd,` 改成 `size: AppTokens.iconLg,`，并把上方那条注释改成说明「导航项归 `iconLg`」而不是「归 `iconMd`」。

- [ ] **Step 2: `durFlow` → `durRingEnter`**

三处一起改：

| 位置 | 改动 |
|---|---|
| `app/lib/core/design_tokens.dart` | `durFlow` 的定义与引用它的注释 → `durRingEnter` |
| `app/lib/features/alarm/alarm_ringing_screen.dart:40` | `AppTokens.durFlow` → `AppTokens.durRingEnter` |
| `app/test/design_tokens_test.dart` | 时长规则的提示文案里的 `durFast/Med/Slow/Flow` → `durFast/Med/Slow/RingEnter`；自检里的 `AppTokens.durFlow` → `AppTokens.durRingEnter` |

- [ ] **Step 3: 跑，确认通过**

```bash
cd app && grep -rn "durFlow" lib/ test/ ; echo "（上面应当没有输出）"
cd app && flutter analyze && flutter test
```

Expected: 无 `durFlow` 残留；全绿（Task 5 的完整性检查会确认自检跟着改了）。

- [ ] **Step 4: 同步规格 §3.1 / §3.2 / §3.6**

在 `docs/superpowers/specs/2026-09-13-design-language-v2-design.md` 里：

- **§3.6**：把「导航项」那一档从 `iconMd` 改成 `iconLg`，并加一句说明为什么（出图对比：24 在胶囊里站得住，20 偏小）。
- **§3.1**：在圆角表下面补一条规则 ——

  > **≤16dp 的实心小元素一律走 `pillOf`。** 阶梯里没有小尺寸档是有意的：小到那个尺度时，圆角与 pill 的差别已经小于抗锯齿带来的差别，而 pill 在高密度排布下更干净（周期色条那种一排十几个的场景最明显）。

- **§3.5 / §9**：把 `durFlow` 的名字与那句「光晕循环」的旧措辞一并改成 `durRingEnter` / 入场动画。

- [ ] **Step 5: 出图，确认唯一差异是导航图标**

```bash
cd app && flutter test tool/visual/render_screens_test.dart
```

看 `00_home_shell_light.png` 与 `00_home_shell_dark.png`：导航图标变大且更饱满。**其余任何一张图都不该有差异** —— 若有，说明前面的常量收编改错了值（那四处都是纯保值替换），回头查。

- [ ] **Step 6: 提交**

```bash
git add app/lib app/test/design_tokens_test.dart
git commit -m "fix(tokens): 导航图标归 iconLg，durFlow 改名 durRingEnter"
```

---

## Task 7: 版本号、更新日志与项目文档

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/core/app_info.dart`
- Modify: `app/lib/features/profile/app_dialogs.dart`
- Modify: `AGENTS.md`
- Modify: `PRODUCT_SPEC.md`

**Interfaces:**
- Consumes: Task 1~6 的成果
- Produces: 可发布的版本号与用户可见的更新说明

- [ ] **Step 1: 版本号两处同步**

`app/pubspec.yaml`：`version: 0.6.11+82` → `version: 0.6.12+83`
`app/lib/core/app_info.dart`：`const String appVersion = '0.6.11';` → `'0.6.12';`

- [ ] **Step 2: 更新日志 prepend 一条、删最旧一条（保持 10 条）**

**本版只有一处用户看得见的变化**，其余全是内部工具与规格的收口 —— 所以这条更新日志应当**很短**，且**不许出现「守门测试」「扫描器」「令牌」「字面量」这类内部术语**。

`_changelogZh` 开头插入：

```dart
    'v0.6.12\n'
    '· 底部导航的四个图标调大一档，在胶囊里更醒目、与文字的比例更接近常见底栏\n'
    '· 内部整理：把设计规范里几处说法与实际不符的地方改正（导航图标的尺寸档位、小尺寸元素的圆角规则）\n\n'
```

`_changelogEn` 插入：

```dart
    'v0.6.12\n'
    '· The four bottom-nav icons are one step larger — more present in the capsule, and closer to the usual tab-bar ratio against their labels\n'
    '· Internal cleanup: corrected a few mismatches between the design spec and the actual code (the nav icon\'s size tier, and the rule for small elements\' corner radius)\n\n'
```

并把两份的最后一条（`v0.6.2`）删掉。

- [ ] **Step 3: 更新 `AGENTS.md`**

- 「验收标准」里的测试条数改成实际值（跑完全量后看真实数字）。
- 「最近改动」加一条 v0.6.12：底部导航图标 20→24；守门测试收口（剥注释与字符串、配对括号、间距类常量与 `design-tokens-ignore` 具名豁免、自检完整性检查）；扫描范围纳入 `core/theme` 并豁免配色层两文件；`durFlow`→`durRingEnter`。
- 目录架构地图里 `core/design_tokens.dart` 那行的说明若提到旧的扫描范围，同步更新。

- [ ] **Step 4: 更新 `PRODUCT_SPEC.md`**

设计系统那节里，「界面层不许写字面量、由 `design_tokens_test.dart` 强制」那段补一句本轮的收口：扫描已剥离注释与字符串、覆盖带子 widget 的调用与间距类常量，并支持 `// design-tokens-ignore: <理由>` 具名豁免。文档头的版本号改成当前版本。

- [ ] **Step 5: 跑测试与静态检查**

```bash
cd app && flutter analyze && flutter test
```

Expected: 全绿，且 `app_info_test.dart` 通过（版本号两处一致）。

- [ ] **Step 6: 提交**

```bash
git add app/pubspec.yaml app/lib/core/app_info.dart app/lib/features/profile/app_dialogs.dart AGENTS.md PRODUCT_SPEC.md
git commit -m "chore(release): v0.6.12 版本号、更新日志与项目文档"
```

---

## Task 8: 出图验收与发布

**Files:**
- 无源码改动（除非验收发现要回改）

**Interfaces:**
- Consumes: Task 1~7
- Produces: GitHub Release `v0.6.12`

- [ ] **Step 1: 出全套图**

```bash
cd app && flutter test tool/visual/render_screens_test.dart
```

- [ ] **Step 2: 逐屏核对：除导航图标外零差异**

看 `00_home_shell_light.png` / `00_home_shell_dark.png`（导航图标应变大且更饱满），以及 `01_calendar_*` / `02_editor_*` / `05_todos_*` / `06_alarm_*` / `07_profile_*` —— 这些**应当与 v0.6.11 完全一致**。任何差异都要追到原因（四处常量收编是纯保值替换，不该产生像素差异）。

- [ ] **Step 3: 对比度抽查（配色层被动过，重新核一遍）**

```bash
cd app && python tool/visual/sample_contrast.py build/visual/07_profile_light.png 30 135 115 180
```

Expected: 与 v0.6.11 相同的数字（4.78:1 一带）—— 本轮没动 `inkMuted`。

- [ ] **Step 4: 构建 APK**

```bash
cd app && flutter build apk --release --target-platform android-arm64
```

Expected: `√ Built build\app\outputs\flutter-apk\app-release.apk (21.6MB)`

- [ ] **Step 5: 校验版本元数据**

```bash
"$PWD/toolchain/android-sdk/build-tools/35.0.0/aapt2.exe" dump badging \
  app/build/app/outputs/flutter-apk/app-release.apk | head -3
```

Expected: `versionCode='83' versionName='0.6.12'`、`com.daoban.shiftassistantpro`。

- [ ] **Step 6: 归档到 dist/ 并算哈希**

```bash
cp app/build/app/outputs/flutter-apk/app-release.apk "dist/倒班助手Pro-v0.6.12.apk"
python -c "import hashlib,os,datetime;p='dist/倒班助手Pro-v0.6.12.apk';print(hashlib.sha256(open(p,'rb').read()).hexdigest().upper());print(datetime.datetime.fromtimestamp(os.path.getmtime(p)).strftime('%m/%d/%Y %H:%M:%S'))"
```

- [ ] **Step 7: 写发布说明**

写 `tools/gh/release-notes-v0.6.12.md`（本次更新 / 说明 / 构建信息三节），构建信息用上一步的数字与提交哈希。

**说明一节要写清楚**：这是内部收口版，**唯一可见变化是底部导航图标**。

- [ ] **Step 8: 提交、打 tag、推送**

```bash
git status --porcelain          # 应当为空；不为空说明前面漏提交了，先补
git tag v0.6.12
git push origin main && git push origin v0.6.12
```

（若 push 报连接被重置，重试即可 —— 这条链路偶尔不稳。）

- [ ] **Step 9: 跑一键发布**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -Command "cd 'C:\Users\Alec\Documents\DeepSeekHermesData\shiftassistant'; . .\tools\build-env.ps1; \$env:GH_CONFIG_DIR='C:\Users\Alec\AppData\Roaming\GitHub CLI'; .\scripts\release.ps1 -SkipConfirm"
```

**`GH_CONFIG_DIR` 不能省**：`build-env.ps1` 把 `APPDATA` 重定向到了 `toolchain/`，而 `gh` 的登录态在真实 AppData 里，不指回去会报「未登录」并以 exit 4 失败。

- [ ] **Step 10: 验证 Release**

```bash
GH_CONFIG_DIR="C:/Users/Alec/AppData/Roaming/GitHub CLI" ./tools/gh/bin/gh.exe release view v0.6.12 \
  --json tagName,isPrerelease,assets --jq '{tag:.tagName,prerelease:.isPrerelease,assets:[.assets[].name]}'
```

Expected: `prerelease: true`（末位非 0），资产名 `DaoBanAssistantPro-v0.6.12.apk`。
