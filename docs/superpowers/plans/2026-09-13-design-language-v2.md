# 设计语言 v2 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把全 App 的排版、文字明度、间距、图标统一到一套按**角色**命名的设计令牌上，并加一条守门测试，让漂移不会再回来。

**Architecture:** 令牌层（`app/lib/core/design_tokens.dart`）新增 15 条角色 `TextStyle`、两档文字明度 helper、三档图标尺寸、两套间距刻度、一个 pill 圆角 helper。界面层把所有 `fontSize` / `fontWeight` / `onSurface.withValues(alpha:)` / 圆角 / 时长 / 颜色字面量换成令牌引用。迁移按「一块 = 一组相关文件」推进；期间由 `app/test/design_tokens_test.dart` 的 `_pending` 文件集合兜住尚未迁完的文件，每完成一块划掉一个，最后一块迁完时集合必须为空。

**Tech Stack:** Flutter 3.x / Dart 3、flutter_test、项目自带出图工装 `app/tool/visual`。

**Spec:** `docs/superpowers/specs/2026-09-13-design-language-v2-design.md`

## Global Constraints

- 目标版本 `0.6.11+82`。`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须同步（`app/test/app_info_test.dart` 盯着）。**`X.Y` 由用户决定，AI 只改末位 `Z` 与 `build`。**
- 每个任务收尾必须：`flutter analyze` 0 error / 0 warning，`flutter test` 全绿。
- 不引入新依赖；不改业务逻辑、Drift 模型、闹钟原生链路；不动圆角阶梯的**数值**（12/16/22/28）。
- **不要跑 `dart format`。** 本工具链是 tall style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `analyze`。
- **每个迁移任务都要顺带处理所涉文件里的间距**：`SizedBox` 的 `height`/`width` 与 `EdgeInsets.*` 的参数里，只允许 `1` 与 `4` 的倍数；其余一律按 **§0.5 间距归类表** 换掉。守门测试盯着这一条。
- **按尺寸归堆之前先核对原处的字重。** 映射表若只写了「卡片标题 → titleStrong」这类按尺寸的归堆，务必回看那一行原本有没有显式 `fontWeight`：带 w600/w700 的标签若落到 w400/w500 的正文令牌，会**明显变轻**，而**这种错误守门测试抓不到**（用错令牌不是字面量）。判据是「尺寸和字重都对得上」，不是「尺寸对就行」。
- **映射表不是穷举。** 各任务的「现值 → 令牌」表是按审计结果整理的，可能有遗漏（比如明度、间距）。真正的判据是守门测试：**把文件从 `_pending` 划掉之后，测试会立刻开始盯它**，报出来的每一处都要补掉，直到该文件干净。
- **计划与规格冲突时以规格为准。** 规格是 `docs/superpowers/specs/2026-09-13-design-language-v2-design.md`，本计划只是它的论证。发现两处打架（例如同一个值一张表写 12、另一张写 13）**请在报告里如实指出**，不要自行挑一个了事 —— 由控制器裁决。
- 提交信息用中文，格式 `type(scope): 描述`。

## 0. 怎么跑命令

工作目录一律是**仓库根** `C:\Users\Alec\Documents\DeepSeekHermesData\shiftassistant`。每个新 shell 先设一次环境变量：

```bash
export JAVA_HOME="$PWD/toolchain/jdk" ANDROID_HOME="$PWD/toolchain/android-sdk" \
       GRADLE_USER_HOME="$PWD/toolchain/gradle-home" PUB_CACHE="$PWD/toolchain/pub-cache" \
       ANDROID_USER_HOME="$PWD/toolchain/android-user" FLUTTER_ROOT="$PWD/toolchain/flutter" \
       APPDATA="$PWD/toolchain/appdata" LOCALAPPDATA="$PWD/toolchain/localappdata"
export PATH="$PWD/toolchain/flutter/bin:$PWD/toolchain/jdk/bin:$PATH"
```

之后本计划里所有 `flutter …` 命令都假定这些变量已设好。`flutter test` / `flutter analyze` 的工作目录是 `app/`，所以 Run 行写成：

```bash
cd app && flutter test test/design_tokens_test.dart
```

---

## 0.5 间距归类表（每个迁移任务都要用）

守门测试实测报出 **43 处、分布在 15 个文件**。判定规则见规格 §3.4：**在分隔两个板块，还是在贴合一个控件内部的两个元素？** 前者归节奏、后者归光学。

按**数值**归类（同一个数字在不同位置可能归不同的档，看它旁边是谁）：

| 值 | 处数 | 归到 | 判据 |
|---|---|---|---|
| 2 | 6 | `AppTokens.gapHair` | 两行紧贴的小间隙；当它明显是「图标贴着文字」时也用它 |
| 3 | 5 | `AppTokens.padChipV` | 徽章 / 其他班组色块 / 小胶囊的**上下**内边距 |
| 5 | 3 | `AppTokens.spaceXs`（4）或 `AppTokens.gapIconText`（6） | 紧跟图标就是 gap，纯板块留白就近到 4 |
| 6 | 9 | `AppTokens.gapIconText` | 图标↔文字；若它分隔的是两个板块则用 `spaceSm`（8） |
| 7 | 1 | `AppTokens.spaceSm`（8） | |
| 9 | 1 | `AppTokens.spaceSm`（8） | |
| 10 | 12 | `AppTokens.gapIconTextLg` | 图标↔文字；若分隔板块则用 `spaceMd`（12） |
| 11 | 1 | `AppTokens.spaceMd`（12） | |
| 14 | 2 | `AppTokens.spaceMd`（12）或 `spaceLg`（16） | 就近，保持同一组间距的节奏一致 |
| 18 | 3 | `AppTokens.spaceLg`（16）或 `spaceXl`（20） | 就近 |

**合法的（不要动）**：

| 值 | 为什么 |
|---|---|
| `1` | 描边与发丝线（`Border.all(width: 1)` 根本不在扫描范围里，`SizedBox(height: 1)` 是分隔线） |
| `4 / 8 / 12 / 16 / 20 / 24 / 32` | 它们本身就是刻度 |
| `36 / 44 / 96 / 120` 这类 4 的倍数 | 不在档位上但在栅格上，合法（按钮高、胶囊让位、底部留白这些布局常数） |

**判据是「在不在 4px 栅格上」**，不是「是不是那七个档位值」：`96` 不在档位上但在栅格上，合法；`6` 看起来像光学值，但没写成令牌就是违规。

**实测过的 43 处集中在这些位置**（执行时可以拿来对数）：`EdgeInsets.symmetric(horizontal: 18, vertical: 8)`、`(horizontal: 14, vertical: 7)`、`(horizontal: 18, vertical: 11)`、`(horizontal: 9, vertical: 3)`、`(horizontal: 14, vertical: 10)`、`(horizontal: 2, vertical: spaceXs)`、`EdgeInsets.fromLTRB(12, 10, 12, 6)`、`(4, 6, 4, 6)`、`(22, 18, 18, 18)`，以及按钮内、弹窗标题旁、小色块旁的那些 `SizedBox(width: 6)` 与 `SizedBox(width: 10)`、`SizedBox(height: 2)`。

**拿不准时的判据**：这个数如果变大 2dp，是「板块之间变松」还是「图标和文字分家了」？前者归节奏，后者归光学。两处都说得通时按「它旁边那个值」决定，保持同一组间距的节奏一致。

---

## 文件结构

| 文件 | 职责 | 变化 |
|---|---|---|
| `app/lib/core/design_tokens.dart` | 唯一令牌来源：颜色 / 圆角 / 间距 / 明度 / 排版 / 图标 / 动效 | 大改：加 15 条角色 `TextStyle` + helper，删旧的 8 条按尺寸命名的字号令牌 |
| `app/test/design_tokens_test.dart` | 令牌与规格一致性 + 界面层字面量守门 | 新建 |
| `app/lib/core/widgets/app_icon.dart` | 图标统一包装，尺寸只从三档取 | 接口收紧并上岗 |
| `app/lib/core/glass/glass.dart` | 玻璃面板与卡片 | 默认圆角 / 模糊 / 内边距改引用令牌 |
| `app/lib/core/widgets/*.dart`（其余 9 个） | 共享玻璃组件 | 全部改引角色令牌 |
| `app/lib/features/**`（8 处） | 七个界面 + 我的页弹窗 | 全部改引角色令牌 |

不改动：`lib/core/theme/**`（配色层本身）、`lib/core/l10n.dart`、`lib/core/layout.dart`、`lib/core/motion.dart`、`lib/domain/**`、`lib/data/**`、`lib/state/**`。

---

## Task 1: 令牌层与守门测试

**Files:**
- Modify: `app/lib/core/design_tokens.dart`
- Modify: `app/test/design_tokens_test.dart` —— **这个文件已经存在**（104 行 / 7 条用例，覆盖圆角与模糊档位、中性色、`accentGradient`、玻璃配方、`navBorder`、主题色对比度、`onSolid`）。本任务是**往里加**两条守门用例，不是覆盖；那 7 条必须原样保留。

**Interfaces:**
- Consumes: 无（本任务是起点）
- Produces: 后续所有任务要用的令牌 ——
  - 排版：`AppTokens.ringClock` `pageTitle` `bigNumber` `dialogTitle` `sectionTitle` `cellDate` `titleStrong` `labelStrong` `rowPrimary` `rowSecondary` `labelSecondary` `microStrong` `microLabel` `microText` `tinyLabel`（都是 `const TextStyle`）
  - 明度：`AppTokens.inkMuted(BuildContext)` → `Color`；`AppTokens.inkFaint(BuildContext)` → `Color`
  - 间距：`AppTokens.spaceXs/Sm/Md/Lg/Xl/2xl/3xl`（`double`）、`AppTokens.gapHair/padChipV/gapIconText/gapIconTextLg`（`double`）
  - 图标：`AppTokens.iconSm/iconMd/iconLg`（`double`）
  - 圆角：`AppTokens.pillOf(double height)` → `BorderRadius`
  - 动效：`AppTokens.durFlow`（`Duration`）

- [ ] **Step 1: 在 `design_tokens.dart` 里新增全部新令牌**

在 `// ── 圆角 ──` 那一段下面补：

```dart
  /// 胶囊圆角：高度的一半。用于导航胶囊、开关轨道、分段滑块，以及
  /// 信息卡左侧那根 6dp 色条这类「细长条」。
  static BorderRadius pillOf(double height) =>
      BorderRadius.all(Radius.circular(height / 2));
```

在 `// ── 间距（4px 栅格） ──` 那一段改成两套刻度：

```dart
  // ── 间距：两套刻度 ──
  //
  // 「节奏」用于分隔两个**板块**：页面留白、区块间距、卡片内边距、列表行。
  // 4px 栅格。判据是「这个间距在分隔板块，还是在贴合一个控件内部的两个元素」。
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 20;
  static const double space2xl = 24;
  static const double space3xl = 32;

  // 「光学」用于**一个控件内部**两个元素的贴合：图标与文字之间、小胶囊的
  // 上下内边距。硬套 4px 会让图标显得脱开、胶囊显得臃肿，所以单独留四档。
  static const double gapHair = 2;
  static const double padChipV = 3;
  static const double gapIconText = 6;
  static const double gapIconTextLg = 10;
```

把 `// ── 排版（system 字体） ──` 那一段里**「只留这四档」那段与代码矛盾的注释重写**（它说只留四档，实际声明了八条），然后**在旧常量下面新增**角色令牌那一段：

**注意：`fontDisplayXl` 到 `fontCaption` 这八个旧常量本任务不要删。** 此刻还有 8 个尚未迁移的文件在引用它们，删掉会直接把 `flutter analyze` 从 0 条打到 70 多条。删除是 **Task 8 Step 4** 的事（那时所有调用点都已迁完）。在旧常量那一段上方加一行注释标明「暂时保留，只为让尚未迁移的界面继续编译；Task 8 确认无调用方后删除」。

```dart
  // ── 排版：角色令牌 ──
  //
  // 令牌即完整样式（字号 + 字重 + 行高）。界面层只写角色名，不写 fontSize /
  // fontWeight；颜色由调用处 `copyWith(color:)` 覆盖 —— 同一个角色在不同底色上
  // （尤其班次色块）要取不同的可读色，所以颜色不进令牌。
  //
  // 名字说的是「什么时候用它」，不是「它多大」。这也是为什么不再按
  // fontLead / fontBody 那样按尺寸命名：按尺寸命名会让人挑「最像的那个大小」，
  // 12.5 / 13.5 / 14.5 / 15 / 22 就是这么来的。
  //
  // 一个角色内的个别变化走 `copyWith`，不另立令牌（格子里的「今天」加粗、
  // 选择器选中项加粗、导航标签选中态、调休日「班」标记转主色）。
  static const TextStyle ringClock =
      TextStyle(fontSize: 84, fontWeight: FontWeight.w800, height: 1.0);
  static const TextStyle pageTitle =
      TextStyle(fontSize: 28, fontWeight: FontWeight.w700);
  static const TextStyle bigNumber =
      TextStyle(fontSize: 24, fontWeight: FontWeight.w700);
  static const TextStyle dialogTitle =
      TextStyle(fontSize: 20, fontWeight: FontWeight.w600);
  static const TextStyle sectionTitle =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
  static const TextStyle cellDate =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.15);
  static const TextStyle titleStrong =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
  static const TextStyle labelStrong =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
  static const TextStyle rowPrimary =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
  static const TextStyle rowSecondary =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
  static const TextStyle labelSecondary =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const TextStyle microStrong =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w700);
  static const TextStyle microLabel =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
  static const TextStyle microText =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
  static const TextStyle tinyLabel =
      TextStyle(fontSize: 11, fontWeight: FontWeight.w400, height: 1.15);

  // ── 图标尺寸：三档 ──
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
```

在 `// ── 时长（非弹簧过渡） ──` 那一段补一档：

```dart
  /// 响铃界面背景光晕的循环周期。不是过渡，是「缓慢流动」的呼吸节奏。
  static const Duration durFlow = Duration(milliseconds: 650);
```

在 `// ── 文字可读性 ──` 那一段**之前**插入明度 helper：

```dart
  // ── 文字明度：两档 ──
  //
  // 「层级只靠字号、字重、明度」里的明度就是这一层。此前它没有令牌，于是
  // 次要文字散着 0.45 / 0.5 / 0.55 / 0.6 四种 alpha —— 同一个角色被调了不同值。
  // 压在主色胶囊上的次要白字不归这两档（那是「前景色已定」的情形）。

  /// 次要文字：副标题 · 说明 · hint · 分组标签 · 星期行。
  static Color inkMuted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

  /// 更淡的：禁用态 · 占位 · 待办已完成。
  static Color inkFaint(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35);
```

`design_tokens.dart` 顶部需要 `import 'package:flutter/material.dart';`（已经有了）。

- [ ] **Step 2: 写守门测试（此时应当是红的）**

Create `app/test/design_tokens_test.dart`：

```dart
// app/test/design_tokens_test.dart
//
// 这一轮（设计语言 v2）把「界面层不写数值」从文档里的一句话变成了会红的东西。
//
// 两条：
//   1. 角色令牌的字号 / 字重 / 行高必须等于规格里那张表 —— 改令牌就得先改规格。
//   2. lib/features · lib/core/widgets · lib/core/glass 下不许出现字面量。
//      迁移期间用 _pending 兜住还没迁完的文件，每迁完一块划掉一个；
//      最后一块迁完时这个集合必须为空。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';

/// 尚未迁完的文件 —— 每完成一个任务就删掉对应的行。
/// 全部删完（集合为空）是这一轮的终点，由最后一条用例盯着。
const Set<String> _pending = {
  'lib/core/glass/glass.dart',
  'lib/core/widgets/glass_action_button.dart',
  'lib/core/widgets/glass_button.dart',
  'lib/core/widgets/glass_choice_chip.dart',
  'lib/core/widgets/glass_delete_button.dart',
  'lib/core/widgets/glass_dialog.dart',
  'lib/core/widgets/glass_pickers.dart',
  'lib/core/widgets/glass_snackbar.dart',
  'lib/features/alarm/alarm_ringing_screen.dart',
  'lib/features/alarm/alarm_screen.dart',
  'lib/features/calendar/calendar_screen.dart',
  'lib/features/calendar/info_card_metrics.dart',
  'lib/features/calendar/schedule_editor_screen.dart',
  'lib/features/calendar/schedule_management_screen.dart',
  'lib/features/calendar/shift_template_picker_screen.dart',
  'lib/features/home/home_shell.dart',
  'lib/features/profile/app_dialogs.dart',
  'lib/features/profile/profile_screen.dart',
  'lib/features/schedule/schedule_screen.dart',
};

const List<String> _scanDirs = [
  'lib/features',
  'lib/core/widgets',
  'lib/core/glass',
];

final Map<String, RegExp> _rules = {
  '字号字面量（改用角色令牌）': RegExp(r'fontSize:\s*[0-9]'),
  '字重字面量（改用角色令牌，个别变化走 copyWith）':
      RegExp(r'fontWeight:\s*FontWeight\.'),
  '文字明度字面量（改用 inkMuted / inkFaint）':
      RegExp(r'onSurface\.withValues\(\s*alpha:'),
  '圆角字面量（改用 radiusS/M/L/XL 或 pillOf）': RegExp(r'circular\([0-9]'),
  '时长字面量（改用 durFast/Med/Slow/Flow）':
      RegExp(r'Duration\(milliseconds:\s*[0-9]'),
  '颜色字面量（改用令牌）': RegExp(r'Color\(0x'),
  '旧的按尺寸命名的字号令牌（改用角色令牌）': RegExp(r'AppTokens\.font[A-Z]'),
  '图标尺寸字面量（改用 iconSm/Md/Lg）':
      RegExp(r'(Icon|IconThemeData)\([^)]*size:\s*[0-9]'),
};

List<String> _violations(String path) {
  final out = <String>[];
  final lines = File(path).readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (final rule in _rules.entries) {
      if (!rule.value.hasMatch(line)) continue;
      // `copyWith(fontWeight: …)` 是一个角色内的刻意变化，允许（见规格 §3.2）。
      if (rule.key.startsWith('字重') && line.contains('copyWith')) continue;
      out.add('$path:${i + 1}  ${rule.key}\n      ${line.trim()}');
    }
  }
  return out;
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

List<String> _spacingViolations(String path) {
  final out = <String>[];
  final src = File(path).readAsStringSync();
  final seen = <String>{};
  for (final call in _spacingCall.allMatches(src)) {
    final args = call.group(2)!;
    for (final m in _numberIn.allMatches(args)) {
      final before = _charBefore(args, m.start);
      final after = _charAfter(args, m.end);
      // 只把「整个参数就是一个数字」的当成间距值，跳过算式里的数字
      // （`width: cellW - _cellInset * 2` 的 2 是算式的一部分）。
      if (before != ':' && before != ',' && before != '(') continue;
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
    check('microStrong', AppTokens.microStrong, 12, FontWeight.w700);
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
        if (_pending.contains(path)) continue;
        offenders.addAll(_violations(path));
        offenders.addAll(_spacingViolations(path));
      }
    }
    expect(offenders, isEmpty,
        reason: '界面层只能引用令牌，发现 ${offenders.length} 处字面量：\n'
            '${offenders.join('\n')}');
  });

  test('迁移完成时 _pending 必须清空', () {
    // 这条用例本身不失败，只在日志里提示进度，方便执行者随时看还剩多少。
    // 真正的强制来自：_pending 里划掉文件后，上一条用例立刻开始盯这个文件。
    expect(_pending.length, lessThanOrEqualTo(19));
  });
}
```

- [ ] **Step 3: 跑测试，确认守门那条是绿的（因为 19 个文件都还在 `_pending` 里）**

```bash
cd app && flutter test test/design_tokens_test.dart
```

Expected: `All tests passed!` —— 此时 `_pending` 恰好覆盖所有违规文件。

- [ ] **Step 4: 验证 `_pending` 列表是准的**

临时把 `_pending` 清空再跑一次，确认失败信息里列出的文件正好是那 19 个（多一个少一个都说明清单不准），然后**恢复** `_pending`：

```bash
cd app && flutter test test/design_tokens_test.dart
```

Expected（清空时）: FAIL，理由里列出 19 个文件。恢复后重新 PASS。

- [ ] **Step 5: 跑全量测试与静态检查**

```bash
cd app && flutter analyze && flutter test
```

Expected: `No issues found!` + `All tests passed!`（126 + 3 = 129 条）

- [ ] **Step 6: 提交**

```bash
git add app/lib/core/design_tokens.dart app/test/design_tokens_test.dart
git commit -m "feat(tokens): 设计语言 v2 的角色令牌层与守门测试"
```

---

## Task 2: core 层（玻璃底座 + 共享组件）

**Files:**
- Modify: `app/lib/core/glass/glass.dart`
- Modify: `app/lib/core/widgets/glass_action_button.dart`
- Modify: `app/lib/core/widgets/glass_button.dart`
- Modify: `app/lib/core/widgets/glass_choice_chip.dart`
- Modify: `app/lib/core/widgets/glass_delete_button.dart`
- Modify: `app/lib/core/widgets/glass_dialog.dart`
- Modify: `app/lib/core/widgets/glass_pickers.dart`
- Modify: `app/lib/core/widgets/glass_snackbar.dart`
- Modify: `app/lib/core/widgets/app_icon.dart`
- Modify: `app/test/design_tokens_test.dart`（从 `_pending` 划掉上面 8 个）

**Interfaces:**
- Consumes: Task 1 的全部令牌
- Produces: `AppIcon(IconData icon, {AppIconSize…})` —— 实际签名 `AppIcon(this.icon, {super.key, this.size = AppTokens.iconMd, this.color})`，`size` 只接受三档令牌之一；`GlassTile` 默认圆角变成 `radiusL`；`GlassPanel` 默认圆角 / 模糊 / 内边距走令牌

- [ ] **Step 1: `glass.dart` 改默认值**

三处：

```dart
// GlassPanel 默认圆角
this.borderRadius = const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
// GlassPanel 默认模糊
this.blurSigma = AppTokens.blurPanel,
// GlassPanel 的内边距默认值
padding: padding ?? const EdgeInsets.all(AppTokens.spaceXl),
```

```dart
// GlassTile 默认圆角：20 → radiusL(22)。这是全 App 每张卡片一起 +2dp 的那一处。
this.borderRadius = const BorderRadius.all(Radius.circular(AppTokens.radiusL)),
```

```dart
// GlassTile 传给 GlassPanel 的模糊
blurSigma: AppTokens.blurCard,
```

- [ ] **Step 2: `app_icon.dart` 收紧接口并上岗**

整个文件替换为：

```dart
import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 统一图标包装：线性图标 + 三档尺寸。
///
/// 尺寸只从 [AppTokens.iconSm] / [AppTokens.iconMd] / [AppTokens.iconLg] 三档取，
/// 默认中档。`IconTheme` 的全局默认值在本轮一并设成 `iconLg`，所以漏包成
/// `AppIcon` 的图标也仍落在刻度上。
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size = AppTokens.iconMd, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Icon(icon, size: size, color: color);
}
```

- [ ] **Step 3: 逐个共享组件换令牌**

映射表（现值 → 令牌）：

| 文件 | 现值 | 令牌 | 说明 |
|---|---|---|---|
| `glass_action_button.dart` | `fontSize: 14, fontWeight: w700` | `AppTokens.labelStrong` | 弹窗按钮文字 |
| | `IconThemeData(… size: 18)` | `size: AppTokens.iconMd` | 图标 |
| | `SizedBox(width: 6)` | `width: AppTokens.gapIconText` | 图标↔文字 |
| `glass_button.dart` | `fontSize: 15, fontWeight: w700` | `AppTokens.titleStrong` | 主按钮文字（15→16） |
| | `IconThemeData(… size: 20)` | `size: AppTokens.iconMd` | |
| | `SizedBox(width: 6)` | `width: AppTokens.gapIconText` | |
| `glass_choice_chip.dart` | `fontSize: AppTokens.fontSupport` | `AppTokens.rowSecondary` | 换名 |
| | `onSurface.withValues(alpha: 0.55)` | `AppTokens.inkMuted(context)` | 换 helper |
| `glass_delete_button.dart` | `onSurface.withValues(alpha: 0.55)` | `AppTokens.inkMuted(context)` | 换 helper |
| | `Icon(…, size: 20)` | `AppIcon(Icons.delete_outlined)` | 走 AppIcon |
| `glass_dialog.dart` | `fontSize: AppTokens.fontHeading` | `AppTokens.dialogTitle` | 换名 |
| | `Icon(…, size: 18)` | `AppIcon(Icons.close_outlined, size: AppTokens.iconMd)` | 18→20 |
| | `SizedBox(width: 10)` | `width: AppTokens.gapIconTextLg` | 标题↔关闭钮 |
| `glass_pickers.dart` | `fontSize: 22, fontWeight: w700` | `AppTokens.bigNumber` | 年份滚轮（22→24） |
| | `fontSize: 20, fontWeight: w600` ×2 | `AppTokens.dialogTitle` | 弹层标题 |
| | `fontSize: 16, fontWeight: w700` ×3 | `AppTokens.titleStrong` | 弹层选项 |
| | `fontSize: 14` + `isSelected ? w700 : w500` ×2 | `AppTokens.rowPrimary` + `copyWith(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: …)` | 日期/月份格子 |
| | `fontSize: 12, fontWeight: w600` | `AppTokens.microLabel` | 选择器星期行 |
| `glass_snackbar.dart` | `fontSize: AppTokens.fontBody` | `AppTokens.rowPrimary` | 提示条正文 |
| | `Icon(…, size: 18)` | `AppIcon(icon, size: AppTokens.iconMd)` | 18→20 |
| | `SizedBox(width: 10)` | `width: AppTokens.gapIconTextLg` | |

**注意**：`glass_pickers.dart` 里 `BorderRadius.circular(AppTokens.radiusM)` 这类已经是令牌的**不要动**；只有 `circular(<数字>)` 才需要改。本文件没有数字圆角，所以圆角不动。

- [ ] **Step 4: 从 `_pending` 划掉本任务的文件**

删掉这 8 行：

```dart
  'lib/core/glass/glass.dart',
  'lib/core/widgets/glass_action_button.dart',
  'lib/core/widgets/glass_button.dart',
  'lib/core/widgets/glass_choice_chip.dart',
  'lib/core/widgets/glass_delete_button.dart',
  'lib/core/widgets/glass_dialog.dart',
  'lib/core/widgets/glass_pickers.dart',
  'lib/core/widgets/glass_snackbar.dart',
```

- [ ] **Step 5: 跑测试**

```bash
cd app && flutter analyze && flutter test
```

Expected: `No issues found!` + `All tests passed!`。若守门用例报出 core 层文件，说明上一步有遗漏，按提示回去改。

- [ ] **Step 6: 出图看玻璃组件的变化**

```bash
cd app && flutter test tool/visual/render_screens_test.dart
```

看 `build/visual/` 下这几张（圆角 +2dp 与图标尺寸都在这几屏最明显）：`00_home_shell_light.png`、`06_alarm_light.png`、`03_management_light.png`、`02_editor_light.png`。重点看列表行圆角与行内图标是否仍居中、按钮内的图标与文字间距有没有变。

- [ ] **Step 7: 提交**

```bash
git add app/lib/core app/test/design_tokens_test.dart
git commit -m "refactor(tokens): core 层玻璃组件改引角色令牌，GlassTile 圆角 20→22"
```

---

## Task 3: 日历

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Modify: `app/lib/features/calendar/info_card_metrics.dart`
- Modify: `app/test/design_tokens_test.dart`

**Interfaces:**
- Consumes: Task 1 的令牌；Task 2 的 `AppIcon`
- Produces: `info_card_metrics.dart` 里的测算样式与卡片渲染**引用同一批令牌**（这是本轮要消掉的隐患：测算与渲染各写一遍样式，改一处忘一处就会量错高度）

- [ ] **Step 1: `calendar_screen.dart` 换令牌**

| 现值 | 令牌 | 用在哪 |
|---|---|---|
| `18/w700` ×2 | `AppTokens.sectionTitle` | 顶栏标题、信息卡日期行 |
| `18` + `isToday ? w800 : w600` ×1 | `AppTokens.cellDate.copyWith(fontWeight: isToday ? FontWeight.w800 : FontWeight.w600)` | 格子里的日期数字 |
| `16/w700` ×1 | `AppTokens.titleStrong` | 信息卡班次名 |
| `15/w800` ×2 | `AppTokens.titleStrong` | 顶栏年月（宽档 + 窄档） |
| `14/w500` ×1 | `AppTokens.rowPrimary` | 信息卡时间 |
| `14/w700` ×1 | `AppTokens.labelStrong` | 「上班 / 休息」状态词 |
| `13/w700` ×1 | `AppTokens.labelStrong` | 顶栏「今天」按钮（13→14） |
| `13/w600` ×1 | `AppTokens.labelSecondary` | 星期行 |
| `13/w400` ×3 | `AppTokens.rowSecondary` | 说明 / 无排班 / 农历描述 |
| `12/w700` ×2 | `AppTokens.microStrong` | 格子班次简称、信息卡「今天」徽章 |
| `12/w600` ×1 | `AppTokens.microLabel` | 其他班组色块 |
| `12/w400` ×1 | `AppTokens.microText` | 「其他班组」标签 |
| `11/w400` ×1 | `AppTokens.tinyLabel` | 格子里的农历 |
| `9/w700` ×1 | `AppTokens.tinyLabel.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)` | 调休日的「班」标记（9→11，靠主色区分而不是靠更小） |
| `AppTokens.fontBody` ×1 | `AppTokens.rowPrimary` | 换名 |
| `AppTokens.fontCaption` ×1 | `AppTokens.microLabel` | 换名 |
| `AppTokens.fontSupport` ×1 | `AppTokens.rowSecondary` | 换名 |
| `onSurface.withValues(alpha: 0.5 / 0.6)` | `AppTokens.inkMuted(context)` | 各处次要文字 |
| `BorderRadius.circular(3)` ×1 | `AppTokens.pillOf(6)` | 信息卡左侧那根 6dp 色条 |
| `Icon(…, size: 20)` 等 | `AppIcon(…, size: AppTokens.iconMd)` | 顶栏圆形钮 |
| `Icon(…, size: 14)` | `AppIcon(Icons.celebration_outlined, size: AppTokens.iconSm)` | 节假日徽章图标（14→16） |
| `Icon(…, size: 16)` | `AppIcon(…, size: AppTokens.iconSm)` | 信息卡闹钟图标 |

- [ ] **Step 2: `info_card_metrics.dart` 改成引用同一批令牌**

这个文件里每一处 `TextStyle(fontSize: …, fontWeight: …)` 都是**在复刻卡片里的样式**，全部换成与上一步**同一个令牌对象**：

| 现值 | 令牌 |
|---|---|
| `18/w700` | `AppTokens.sectionTitle` |
| `16/w700` | `AppTokens.titleStrong` |
| `14/w700` | `AppTokens.labelStrong` |
| `13/w400` ×2 | `AppTokens.rowSecondary` |
| `12/w600` ×2 | `AppTokens.microLabel` |
| `12/w400` ×1 | `AppTokens.microText` |
| `AppTokens.fontBody` / `fontCaption` | `AppTokens.rowPrimary` / `AppTokens.microLabel` |

文件顶部加一行 `import '../../core/design_tokens.dart';`（已有则跳过）。

**这一条很关键**：换完以后，测算用的样式与卡片渲染用的样式是**同一个 `const` 对象**，不可能再各写一遍。Task 3 结束后必须重新跑一遍日历测试的「点开某天」用例，它断言的是「卡片高度 = 本月最满内容 + 卡片自身开销」，只要量出来的字号与渲染不一致就会红。

- [ ] **Step 3: 从 `_pending` 划掉这两个文件**

- [ ] **Step 4: 跑日历测试**

```bash
cd app && flutter analyze && flutter test test/calendar_screen_test.dart
```

Expected: `All tests passed!`（22 条）。特别注意「点开某天：信息卡高度只由本月决定」「信息卡高度跟着「其他班组」占几行走」两条 —— 它们直接验证测算仍准确。

- [ ] **Step 5: 跑全量测试**

```bash
cd app && flutter test
```

- [ ] **Step 6: 出图**

```bash
cd app && flutter test tool/visual/render_screens_test.dart
```

看 `01_calendar_light.png`、`01_calendar_dark.png`、`01_calendar_en.png`、`01_calendar_day_selected.png`。重点：顶栏的「今天」按钮（13→14）与年月（15→16）在同一条胶囊栏里是否仍对齐、高度没撑破；格子里的日期与农历行距是否正常；调休日那个「班」标记变大后有没有挤出格子。

- [ ] **Step 7: 提交**

```bash
git add app/lib/features/calendar app/test/design_tokens_test.dart
git commit -m "refactor(tokens): 日历改引角色令牌，测算与渲染共用同一批样式"
```

---

## Task 4: 排班编辑器与模板选择

**Files:**
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`
- Modify: `app/lib/features/calendar/shift_template_picker_screen.dart`
- Modify: `app/lib/features/calendar/schedule_management_screen.dart`
- Modify: `app/test/schedule_editor_test.dart` —— 该测试**直接引用了本任务要换掉的旧令牌**（`schedule_editor_test.dart:962,963,973,974,975,979`），不更新会编译不过
- Modify: `app/test/design_tokens_test.dart`

**Interfaces:**
- Consumes: Task 1 的令牌
- Produces: 无新接口（纯迁移）

- [ ] **Step 1: `schedule_editor_screen.dart` 换令牌（**26 处旧令牌、0 处字面量**）**

这个文件全是 `AppTokens.fontXxx` 引用，按用途换名：

| 现值 | 令牌 |
|---|---|
| `AppTokens.fontLead` | 看用途：卡片标题 / 输入框标签 → `AppTokens.titleStrong`；按钮文字 → `AppTokens.titleStrong` |
| `AppTokens.fontBody` | 看用途：行内主文字 → `AppTokens.rowPrimary`；正文 → `AppTokens.rowPrimary` |
| `AppTokens.fontSupport` | `AppTokens.rowSecondary` |
| `AppTokens.fontCaption` | `AppTokens.microLabel`（标签类）/ `AppTokens.microText`（正文类） |

同一行若还带 `fontWeight: FontWeight.w…`，**不要简单地删掉它，要挑尺寸与字重都对得上的令牌** —— 比如 `fontSupport`(13) 带 `w600` 的标签应当落到 `labelSecondary`(13/w600)，落到 `rowSecondary`(13/w400) 会让本来有强调的标签明显变轻。只有确认那个字重确实多余（同尺寸其它地方都不带）才删。

另有 `onSurface.withValues(alpha: 0.55)` 多处 → `AppTokens.inkMuted(context)`；`BorderRadius.circular(AppTokens.radiusS)` 这类**已经是令牌的不动**。

`Icon(…, size: …)` 若出现，换成 `AppIcon(…, size: AppTokens.iconMd)`。

**判定方法**：换名前先看这行文字在界面上是什么角色（卡片标题 / 输入框 / 行内主文字 / 说明 / 小标签），再从上表取对应令牌。拿不准时优先「尺寸最接近、角色说得通」的那个，不要为此新增令牌 —— 准入规则见规格 §3.2。

- [ ] **Step 2: `shift_template_picker_screen.dart` 换令牌**

| 现值 | 令牌 |
|---|---|
| `10/w400` ×1 | `AppTokens.tinyLabel` | 周期色条格子（10→11） |
| `AppTokens.fontSupport` ×4 | `AppTokens.rowSecondary` |
| `AppTokens.fontCaption` ×1 | `AppTokens.microLabel` |
| `AppTokens.fontLead` ×2 | `AppTokens.titleStrong` |
| `onSurface.withValues(alpha: 0.5 / 0.6)` | `AppTokens.inkMuted(context)` |
| `BorderRadius.circular(3)` ×2 | `AppTokens.pillOf(6)`（若色条高 6）/ 按实际高度取半 |
| `Icon(…, size: …)` | `AppIcon(…, size: …)` 对应档 |

- [ ] **Step 3: 更新 `app/test/schedule_editor_test.dart` 里的旧令牌引用**

该文件 6 处直接引用旧的按尺寸命名的令牌，Task 8 删掉它们之后会编译不过：

| 行 | 现值 | 换成 |
|---|---|---|
| 962, 963, 973, 974 | `AppTokens.fontLead` | `AppTokens.titleStrong` |
| 975 | `AppTokens.fontSupport` | `AppTokens.rowSecondary` |
| 979 | `AppTokens.fontCaption` | 该处控件迁移后用的那个 12px 角色令牌 |

**注意不只是改名字**：断言形式是 `expect(e.style.fontSize, AppTokens.fontLead)` —— 左边是 `double?`，而 `fontLead` 过去是 `double`。迁移后令牌是 `TextStyle`，所以必须写成 `AppTokens.titleStrong.fontSize`；`reason:` 字符串里的插值同理。

- [ ] **Step 4: `schedule_management_screen.dart` 归位那一处间距**

这个文件只有 1 处不在栅格上（列表行的上下留白 10），按 §0.5 归到 `AppTokens.spaceMd`（12）或 `spaceSm`（8）。

- [ ] **Step 5: 从 `_pending` 划掉这三个文件**

- [ ] **Step 6: 跑测试**

```bash
cd app && flutter analyze && flutter test test/schedule_editor_test.dart && flutter test
```

Expected: 全绿。

- [ ] **Step 7: 出图**

```bash
cd app && flutter test tool/visual/render_screens_test.dart
```

看 `02_editor_light.png`、`02_editor_dark.png`、`04_template_picker_light.png`、`04_template_picker_dark.png`、`04_template_picker_en.png`、`03_management_light.png`。重点：编辑器的标签与输入框字号是否还分得清层级；色条格子变大一档后有没有撑破卡片宽度。

- [ ] **Step 8: 提交**

```bash
git add app/lib/features/calendar app/test/schedule_editor_test.dart app/test/design_tokens_test.dart
git commit -m "refactor(tokens): 编辑器与模板选择改引角色令牌"
```

---

## Task 5: 闹钟

**Files:**
- Modify: `app/lib/features/alarm/alarm_screen.dart`
- Modify: `app/lib/features/alarm/alarm_ringing_screen.dart`
- Modify: `app/test/design_tokens_test.dart`

**Interfaces:**
- Consumes: Task 1 的令牌（特别是 `ringClock`、`durFlow`）
- Produces: 无新接口

- [ ] **Step 1: `alarm_screen.dart` 换令牌**

| 现值 | 令牌 | 用在哪 |
|---|---|---|
| `24/w700` ×1 | `AppTokens.bigNumber` | 首页大时间 |
| `18/w700` ×2 | `AppTokens.sectionTitle` | 区块标题 |
| `16/w700` ×3 | `AppTokens.titleStrong` | 卡片标题 / 时间行 |
| `13/w400` ×4 | `AppTokens.rowSecondary` | 副标题 / 说明 |
| `12/w400` ×2 | `AppTokens.microText` | 微字 |
| `onSurface.withValues(alpha: 0.5)` ×2 | `AppTokens.inkMuted(context)` | |
| `Icon(…, size: …)` | `AppIcon(…, size: …)` | |

- [ ] **Step 2: `alarm_ringing_screen.dart` 换令牌**

| 现值 | 令牌 |
|---|---|
| `fontSize: AppTokens.fontDisplayXl` + 同处 `fontWeight: FontWeight.w800` | `AppTokens.ringClock`（删掉行内的 `fontWeight`，w800 已在令牌里） |
| `AppTokens.fontBody` | `AppTokens.rowPrimary` |
| `AppTokens.fontCaption` | `AppTokens.microText` |
| `Duration(milliseconds: 650)` | `AppTokens.durFlow` |
| `Icon(…, size: 28)` | `AppIcon(…, size: AppTokens.iconLg)`（28→24，**本轮唯一一处图标缩小**） |

- [ ] **Step 3: 从 `_pending` 划掉这两个文件**

- [ ] **Step 4: 跑测试**

```bash
cd app && flutter analyze && flutter test
```

- [ ] **Step 5: 出图，并记录一处无法在这里核对的改动**

```bash
cd app && flutter test tool/visual/render_screens_test.dart
```

看 `06_alarm_light.png`、`06_alarm_dark.png`、`00_home_shell_dark.png`。

**注意：出图工装里没有响铃界面**（只有 00~07 那八屏），所以「响铃大闹钟图标 28→24」这一处在本任务里核对不了。它是本轮唯一一处图标缩小，留到 Task 10 的真机验收里确认 —— 在报告里写明「该处未经出图核对」，不要假装看过。如果真机上觉得分量不够，走规格的修订记录加话，不要偷偷再加一档尺寸。

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/alarm app/test/design_tokens_test.dart
git commit -m "refactor(tokens): 闹钟页与响铃界面改引角色令牌"
```

---

## Task 6: 我的页与弹窗

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart`
- Modify: `app/lib/features/profile/app_dialogs.dart`
- Modify: `app/test/design_tokens_test.dart`

**Interfaces:**
- Consumes: Task 1 的令牌
- Produces: 无新接口

- [ ] **Step 1: `profile_screen.dart` 换令牌**

| 现值 | 令牌 | 用在哪 |
|---|---|---|
| `28/w700` ×1 | `AppTokens.pageTitle` | 页题 |
| `16/w700` ×1 | `AppTokens.titleStrong` | 弹层标题 |
| `13/w400` ×2 | `AppTokens.rowSecondary` | 开关说明 |
| `13/w600` ×1 | `AppTokens.labelSecondary` | 分区小标题 |
| `12/w400` ×2` | `AppTokens.microText` | 微字 |
| `12/w700` ×1 | `AppTokens.labelSecondary` | 权限卡分组小标题（12→13，同时 w700→w600） |
| `onSurface.withValues(alpha: 0.5)` | `AppTokens.inkMuted(context)` | |
| `BorderRadius.circular(AppTokens.radiusXL)` | **不动**（已是令牌） | 铃声弹层 |

- [ ] **Step 2: `app_dialogs.dart` 换令牌**

| 现值 | 令牌 | 用在哪 |
|---|---|---|
| `14.5/w700` ×1 | `AppTokens.labelStrong` | 使用帮助条目标题（14.5→14） |
| `14/w600` ×1 | `AppTokens.labelStrong` | 「版本：v0.6.10」（w600→w700） |
| `14/w700` ×1 | `AppTokens.labelStrong` | 更新通道名 |
| `13.5/w400` ×1 | `AppTokens.rowSecondary` | 更新日志正文（13.5→13） |
| `13/w400` ×5 | `AppTokens.rowSecondary` | |
| `13/w600` ×1 | `AppTokens.labelSecondary` | |
| `12.5/w400` ×1 | `AppTokens.rowSecondary` | 使用帮助条目描述（12.5→13，与更新日志正文同档；规格 §4 明确写的是 →13） |
| `11/w400` ×2 | `AppTokens.tinyLabel` | 版本号小字 |
| `onSurface.withValues(alpha: 0.5 / 0.6)` | `AppTokens.inkMuted(context)` | |
| `Icon(it.$1, size: 20)` | `AppIcon(it.$1, size: AppTokens.iconMd)` | 使用帮助图标 |

- [ ] **Step 3: 从 `_pending` 划掉这两个文件**

- [ ] **Step 4: 跑测试**

```bash
cd app && flutter analyze && flutter test
```

- [ ] **Step 5: 出图**

```bash
cd app && flutter test tool/visual/render_screens_test.dart
```

看 `07_profile_light.png`、`07_profile_dark.png`、`07_profile_en.png`、`07_profile_landscape.png`、`07_profile_small.png`。重点：权限卡分组小标题从 12/w700 变成 13/w600 后，与下面权限项的主次是否还分得开（它靠主色区分，应该没问题）；信息卡在 `07_profile_small` 里的挤压情况。

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/profile app/test/design_tokens_test.dart
git commit -m "refactor(tokens): 我的页与弹窗改引角色令牌"
```

---

## Task 7: 待办与导航壳

**Files:**
- Modify: `app/lib/features/schedule/schedule_screen.dart`
- Modify: `app/lib/features/home/home_shell.dart`
- Modify: `app/lib/core/theme/app_theme.dart`（给 `IconTheme` 设全局默认尺寸）
- Modify: `app/test/design_tokens_test.dart`

**Interfaces:**
- Consumes: Task 1 的令牌、Task 2 的 `AppIcon`
- Produces: 全局 `IconThemeData(size: AppTokens.iconLg)` —— 让漏包 `AppIcon` 的图标也落在刻度上

- [ ] **Step 1: `schedule_screen.dart` 换令牌**

| 现值 | 令牌 | 用在哪 |
|---|---|---|
| `28/w700` ×1 | `AppTokens.pageTitle` | 页题 |
| `16/w600` ×1 | `AppTokens.titleStrong` | 待办标题（w600→w700） |
| `12/w400` ×1 | `AppTokens.microText` | 副标题 |
| `onSurface.withValues(alpha: 0.55)` | `AppTokens.inkMuted(context)` | 副标题常态 |
| `onSurface.withValues(alpha: 0.45)` | `AppTokens.inkFaint(context)` | 已完成标题 |
| `onSurface.withValues(alpha: 0.35)` | `AppTokens.inkFaint(context)` | 已完成副标题 |
| `onSurface.withValues(alpha: 0.5)` ×2 | `AppTokens.inkMuted(context)` | |

- [ ] **Step 2: `home_shell.dart` 换令牌**

导航标签：

```dart
    style: AppTokens.tinyLabel.copyWith(
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      color: selected ? fg : inactiveColor,
    ),
```

（`fontSize: 10` → `tinyLabel` 的 11，`fontWeight: selected ? w700 : w500` 通过 `copyWith` 保留。）

- [ ] **Step 3: 给 `app_theme.dart` 的 `IconTheme` 设全局默认尺寸**

在 `app_theme.dart` 的两个 `ThemeData(...)`（亮/暗）里补：

```dart
        iconTheme: const IconThemeData(size: AppTokens.iconLg),
```

并在文件顶部 `import 'design_tokens.dart';`（若已有则跳过）。这一步让「忘了换 AppIcon」的图标也停在 24 而不是裸 `IconThemeData` 的默认值。

- [ ] **Step 4: 从 `_pending` 划掉这两个文件**

- [ ] **Step 5: 跑测试**

```bash
cd app && flutter analyze && flutter test
```

- [ ] **Step 6: 出图（导航壳最值得看）**

```bash
cd app && flutter test tool/visual/render_screens_test.dart
```

看 `00_home_shell_light.png`、`00_home_shell_dark.png`、`00_home_shell_small.png`、`05_todos_light.png`、`05_todos_dark.png`。重点：导航标签 10→11 后，在 200×400 的小窗胶囊里有没有挤到换行；待办标题变粗后已完成态的删除线是否还清楚。

- [ ] **Step 7: 提交**

```bash
git add app/lib/features app/lib/core/theme app/test/design_tokens_test.dart
git commit -m "refactor(tokens): 待办与导航壳改引角色令牌，图标全局默认尺寸落到 iconLg"
```

---

## Task 8: 收口 —— 清空 `_pending` 并删掉旧令牌

**Files:**
- Modify: `app/lib/core/design_tokens.dart`
- Modify: `app/test/design_tokens_test.dart`

**Interfaces:**
- Consumes: Task 1~7 的全部迁移
- Produces: 无 —— 这是收口任务，删掉过渡设施

- [ ] **Step 1: 确认 `_pending` 已经空了**

```bash
cd app && flutter test test/design_tokens_test.dart
```

若还有文件留着，说明前面某个任务漏划，回去补任务并确认那个文件真的迁完了。

- [ ] **Step 2: 删掉 `_pending` 整个集合，并把第三条用例改成「集合已删除」的终态**

把 `design_tokens_test.dart` 里的 `const Set<String> _pending = {…};` 整段删掉，并把循环里的：

```dart
        if (_pending.contains(path)) continue;
```

也删掉。同时删掉 `test('迁移完成时 _pending 必须清空', …)` 这条用例 —— 它的使命是在迁移期间报进度，`_pending` 没了它就没有意义了。

- [ ] **Step 3: 跑守门测试，确认它现在是全绿且没有豁免**

```bash
cd app && flutter test test/design_tokens_test.dart
```

Expected: `All tests passed!`（2 条）。此时任何界面层文件写一个字面量都会立刻变红。

- [ ] **Step 3.5: 把逐行跑的规则改成整文件扫描（补两类跨行盲点）**

迁移期间暴露了守门测试自己的两个洞，**都是在实装时才发现的**：

1. **图标规则**：`(Icon|IconThemeData)\([^)]*size:\s*[0-9]` 逐行跑时，`Icon(` 与 `size: 28` 分写两行会漏（Task 5 实测，响铃界面那处就是这么写的）。
2. **明度规则**：`onSurface\.withValues\(\s*alpha:` 逐行跑时，`Theme.of(context)` / `.colorScheme` / `.onSurface` / `.withValues(...)` 链式跨行会漏（Task 7 实测，导航未选中标签色就是这么写的）。

3. **字重规则**：`fontWeight:\s*FontWeight\.` 逐行跑时，`fontWeight: selected
 ? FontWeight.w700
 : FontWeight.w500` 这种**三元跨行**写法会漏（Task 7 审查发现，`home_shell.dart` 的导航标签就是这么写的 —— 它本身经 `copyWith` 豁免是合法的，但规则漏检这件事是真的）。

三处的暴露面实测各为 1 处、且都已手工处理，所以**现在改不会红**。改法是照抄 `_spacingViolationsIn` 的套路：读整个文件文本、用正则在全文里找、再把偏移换算回行号。**三类一起改**，别只改一类。

改完**各加一条正反两面的用例**钉住（正面：跨行写法必须被报出；反面：合法的写法不能被误报）。注意「只钉正面」是不够的 —— 把逻辑改成「一律不查」也能让正面用例过。

```bash
cd app && flutter test test/design_tokens_test.dart && flutter analyze && flutter test
```

Expected: 全绿。若报出新的文件或位置，说明还有第三处漏网，**先修掉再往下走**。

- [ ] **Step 4: 删掉 `design_tokens.dart` 里旧的按尺寸命名的字号令牌**

`fontDisplayXl` / `fontDisplay` / `fontTitle` / `fontHeading` / `fontLead` / `fontBody` / `fontSupport` / `fontCaption` —— 此时应当已无调用方。删完后：

```bash
cd app && flutter analyze
```

Expected: `No issues found!`。若报「未定义」，说明还有地方在引用，回到对应任务补迁移。

- [ ] **Step 4.5: 顺手修掉一处会误导人的注释**

`app/lib/features/home/home_shell.dart:381` 附近有一行注释写「基线 11px w400」，但它紧挨着的其实是迁移**之后**的 `tinyLabel`(11/w400) —— 迁移前的基线是 `fontSize: 10`。注释与它描述的对象不符，改准。（Task 7 审查发现。）

- [ ] **Step 5: 处理 `blurChip`**

```bash
cd app && grep -rn "blurChip" lib
```

此时应只剩 `design_tokens.dart` 里的定义本身。删掉它（`blurCard` 与 `blurPanel` 已有调用方，保留）。

- [ ] **Step 6: 全量验收**

```bash
cd app && flutter analyze && flutter test
```

Expected: `No issues found!` + `All tests passed!`（129 - 1 = 128 条，少了那条迁移期进度用例）。

- [ ] **Step 7: 提交**

```bash
git add app/lib/core/design_tokens.dart app/test/design_tokens_test.dart
git commit -m "refactor(tokens): 迁移收口，删除旧字号令牌与迁移期豁免"
```

---

## Task 9: 版本号、更新日志与项目文档

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/core/app_info.dart`
- Modify: `app/lib/features/profile/app_dialogs.dart`
- Modify: `AGENTS.md`
- Modify: `PRODUCT_SPEC.md`

**Interfaces:**
- Consumes: Task 1~8 的成果
- Produces: 可发布的版本号与用户可见的更新说明

- [ ] **Step 1: 版本号两处同步**

`app/pubspec.yaml`：`version: 0.6.10+81` → `version: 0.6.11+82`
`app/lib/core/app_info.dart`：`const String appVersion = '0.6.10';` → `'0.6.11';`

- [ ] **Step 2: 更新日志 prepend 一条、删最旧一条（保持 10 条）**

在 `app_dialogs.dart` 的 `_changelogZh` 开头插入：

```dart
    'v0.6.11\n'
    '· 全 App 的排版、间距与图标统一到一套按「角色」命名的设计令牌上：同一个角色的字号、字重、行高、透明度、间距只有一个来源，不再各自调\n'
    '· 次要文字的透明度此前散着 0.45 / 0.5 / 0.55 / 0.6 四种，现在统一到两档（常规 0.55、更淡的 0.35），同一个层级在哪个页面看都一样\n'
    '· 图标尺寸统一到三档（16 / 20 / 24），不再各处写 14 / 18 / 22 / 28\n'
    '· 卡片圆角由 20 归到 22，与列表行、提示条同档\n'
    '· 外观变化很轻：12 处字号、3 处字重各动了一档，其余只是内部换了写法\n\n'
```

英文同样在 `_changelogEn` 开头插入对应内容，并把两份的最后一条（`v0.6.1`）删掉。

- [ ] **Step 3: 更新 `AGENTS.md`**

- 「版本号规则」那条补一句：更新日志保持 10 条、正式版条目归纳的规则不变。
- 目录架构地图里 `core/design_tokens.dart` 那行改成说明它是**角色令牌**来源（`design_tokens_test.dart` 守着界面层不写字面量）。
- 「最近改动」加一条 v0.6.11，写明：令牌改按角色命名、明度两档、间距两套刻度、图标三档、新增守门测试。
- 「验收标准」里的测试条数改成实际值。

- [ ] **Step 4: 更新 `PRODUCT_SPEC.md`**

在描述视觉/设计语言的那一节补一段：设计语言的单一来源是 `core/design_tokens.dart` 的角色令牌；界面层不许写 `fontSize` / `fontWeight` / 圆角 / 时长 / 颜色字面量，由 `app/test/design_tokens_test.dart` 强制。并把文档头的版本号改成当前版本。

- [ ] **Step 5: 跑测试与静态检查**

```bash
cd app && flutter analyze && flutter test
```

Expected: 全绿，且 `app_info_test.dart` 通过（两处版本号一致）。

- [ ] **Step 6: 提交**

```bash
git add app/pubspec.yaml app/lib/core/app_info.dart app/lib/features/profile/app_dialogs.dart AGENTS.md PRODUCT_SPEC.md
git commit -m "chore(release): v0.6.11 版本号、更新日志与项目文档"
```

---

## Task 10: 全量出图验收与发布

**Files:**
- 无源码改动（除非出图发现要回改）

**Interfaces:**
- Consumes: Task 1~9 的全部成果
- Produces: GitHub Release `v0.6.11`

- [ ] **Step 1: 出全套图**

```bash
cd app && flutter test tool/visual/render_screens_test.dart
```

- [ ] **Step 2: 按规格 §7 逐项核对**

打开 `app/build/visual/` 下的图，确认：

1. **圆角 +2dp**：所有卡片与内部元素（信息卡左侧色条、其他班组色块、节假日徽章）仍对齐，没有色条探出圆角的地方。
2. **12 处变字号**：日历顶栏的年月与「今天」、主按钮、格子「班」标记、选择器年份滚轮、权限卡分组小标题、导航标签 —— 逐一看过。
3. **明度 0.55**：深色主题下次要文字仍读得清（`01_calendar_dark` / `07_profile_dark` / `05_todos_dark`）。
4. **图标三档**：导航胶囊那一排、列表项、按钮内的图标密度；响铃界面那个大闹钟图标 28→24 的分量。

发现任何一处不对，**回到对应任务改并重新出图**，不要在发布任务里临时改。

- [ ] **Step 3: 对比度抽查（明度改了，必须重新核一遍）**

```bash
cd app && python tool/visual/sample_contrast.py
```

按项目惯例：对比度审计脚本是筛子，报出来的每一处都要用取样脚本核实真实像素值，不能只看审计结论。

- [ ] **Step 4: 构建 APK**

```bash
cd app && flutter build apk --release --target-platform android-arm64
```

Expected: `√ Built build\app\outputs\flutter-apk\app-release.apk (21.6MB)`

- [ ] **Step 5: 校验 APK 的版本元数据**

```bash
"$PWD/toolchain/android-sdk/build-tools/35.0.0/aapt2.exe" dump badging \
  app/build/app/outputs/flutter-apk/app-release.apk | head -3
```

Expected: `versionCode='82' versionName='0.6.11'`、`com.daoban.shiftassistantpro`。

- [ ] **Step 6: 归档到 dist/**

```bash
cp app/build/app/outputs/flutter-apk/app-release.apk "dist/倒班助手Pro-v0.6.11.apk"
```

- [ ] **Step 7: 写发布说明**

写 `tools/gh/release-notes-v0.6.11.md`，含「本次更新 / 说明 / 构建信息」三节。构建信息里的 SHA256 与构建时间要从上一步的 APK 现算：

```bash
python -c "import hashlib,os,datetime;p='dist/倒班助手Pro-v0.6.11.apk';print(hashlib.sha256(open(p,'rb').read()).hexdigest().upper());print(datetime.datetime.fromtimestamp(os.path.getmtime(p)))"
```

- [ ] **Step 8: 提交、打 tag、推送**

Task 9 之后工作区应当已经干净，这一步不需要再产生提交：

```bash
git status --porcelain          # 应当为空；不为空说明前面漏提交了，先补
git tag v0.6.11
git push origin main && git push origin v0.6.11
```

（若 push 报连接被重置，重试即可 —— 这条链路偶尔不稳，`ls-remote` 能通不代表 push 能通。）

- [ ] **Step 9: 跑一键发布**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -Command "cd 'C:\Users\Alec\Documents\DeepSeekHermesData\shiftassistant'; . .\tools\build-env.ps1; \$env:GH_CONFIG_DIR='C:\Users\Alec\AppData\Roaming\GitHub CLI'; .\scripts\release.ps1 -SkipConfirm"
```

**`GH_CONFIG_DIR` 不能省**：`build-env.ps1` 把 `APPDATA` 重定向到了 `toolchain/`，而 `gh` 的登录态在真实 AppData 里，不指回去就会报「未登录」而以 exit 4 失败。

Expected: 打印 Release 地址，资产名 `DaoBanAssistantPro-v0.6.11.apk`，并更新 `latest.json`。

- [ ] **Step 10: 验证 Release**

```bash
GH_CONFIG_DIR="C:/Users/Alec/AppData/Roaming/GitHub CLI" ./tools/gh/bin/gh.exe release view v0.6.11 \
  --json tagName,isPrerelease,assets --jq '{tag:.tagName,prerelease:.isPrerelease,assets:[.assets[].name]}'
```

Expected: `prerelease: true`（末位非 0），资产名正确。
