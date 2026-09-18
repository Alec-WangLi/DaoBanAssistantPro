# 触觉反馈系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立一套按语义命名的触觉反馈词汇表，铺到全 app 的「状态改变」与「不可逆动作」上，给用户一个 App 级开关，并用一条守门测试钉住它不被绕过；顺带修掉 v0.8.1 实机反馈里的四处设计语言偏差。

**Architecture:** 新建设计系统层 `core/haptics.dart`（与 `core/motion.dart`、`core/design_tokens.dart` 并列），暴露三个语义档位 `select()` / `commit()` / `modeEnter()`，内部读一个模块级标志 `hapticsDisabled`（由「外观」设置反灌，抄 `advancedMaterialDisabled` 那条现成的路）。高频的三类交互由共享组件**自己震**，其余在**状态提交的那一刻**显式调用。一条源码扫描测试禁止任何文件绕过词汇表直接调 `HapticFeedback`。

**Tech Stack:** Flutter / Dart、Riverpod、shared_preferences、自研液态玻璃设计系统（`AppTokens` 角色令牌）

**Spec:** `docs/superpowers/specs/2026-09-18-haptic-feedback-system-design.md`

## Global Constraints

- **版本号**：目标 `0.8.2+93`。`X.Y` 由用户决定，AI **只改末位 `Z` 与 `build`**。`app/pubspec.yaml` 的 `version:` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须同步改，由 `app/test/app_info_test.dart` 盯着。
- **不要跑 `dart format`**：工具链是新版 tall style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `flutter analyze`。
- **验收标准**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿。起手基线 **217 条**（v0.8.1 之后），只增不减。
- **设计令牌**：界面层只写 `AppTokens` 的角色名，不写字面量 —— 字号（`fontSize:`）、字重（`fontWeight:`）、`onSurface` 系文字明度（`.withValues(alpha: …)`）、圆角（`circular(…)`）、`Duration(milliseconds: …)`、`Color(0x…)`、图标尺寸（`Icon`/`IconThemeData` 的 `size:`）一律不许写死；由 `app/test/design_tokens_test.dart` 整文件级扫描把关。确需豁免要写 `// design-tokens-ignore: <理由>`。（裸的 `width:`/`height:` 数值不在扫描面内。）
- **弹窗配方**：遮罩统一 `barrierColor: Colors.black26`；底部弹层用 `GlassPanel(solid: true)`。
- **文案**：一律 zh / en 成对（`L10n.t(zh, en)`），中文不许漏进英文界面。
- **触觉铁律**：**除 `app/lib/core/haptics.dart` 外，任何文件不许出现 `HapticFeedback.`** —— 由 Task 2 的守门测试强制。**挂动作，不挂按压**；普通点击一律不震。
- **测试文件顶部注释**：本项目惯例是在测试文件头写一段说明「这个文件在测什么、为什么」。新写的测试照做。
- **每个任务提交前跑一次全量 `flutter test`**，不是只跑改动的那一个文件。

---

## File Structure

| 文件 | 职责 | 动作 |
|---|---|---|
| `app/lib/core/haptics.dart` | 触觉词汇表 + 模块级开关标志 | **Create** |
| `app/test/haptics_test.dart` | 词汇表行为 + 完整性自检 | **Create** |
| `app/test/haptics_guard_test.dart` | 守门：禁止绕过词汇表 | **Create** |
| `app/test/support/source_scan.dart` | 源码剥壳器（从 `design_tokens_test.dart` 抽出，两处共用） | **Create** |
| `app/test/design_tokens_test.dart` | 改成 import 共用的剥壳器 | Modify |
| `app/lib/state/app_settings.dart` | 加 `hapticsEnabled` + 持久化 + 反灌标志 | Modify |
| `app/lib/core/l10n.dart` | 开关的标题与副标题 | Modify |
| `app/lib/features/profile/profile_screen.dart` | 「外观」分区加一行开关 | Modify |
| `app/lib/core/widgets/glass_switch.dart` | 翻转时自震 | Modify |
| `app/lib/core/widgets/glass_segment.dart` | 选中项真的变了时自震 | Modify |
| `app/lib/core/widgets/glass_choice_chip.dart` | 选中时自震 | Modify |
| `app/lib/core/widgets/glass_pickers.dart` | 四个选择器的提交点自震 | Modify |
| `app/lib/core/widgets/glass_action_button.dart` | 危险确认按钮按下时震 | Modify |
| `app/lib/features/schedule/schedule_screen.dart` | 待办勾选完成时震 | Modify |
| `app/lib/features/calendar/calendar_screen.dart` | 手套震、改班震、切方案震；「已调整」改胶囊；去水波纹；底色 18→14 | Modify |
| `app/lib/features/calendar/info_card_metrics.dart` | 把「已调整」标记纳入定高模型 | Modify |
| `app/lib/features/calendar/shift_override_picker.dart` | 圆点尺寸的理由写进注释 | Modify |
| `app/tool/visual/visual_screens.dart` | 补新界面的屏单 | Modify |
| `app/lib/features/profile/app_dialogs.dart` | 更新日志条目 | Modify |
| `app/lib/core/app_info.dart` + `app/pubspec.yaml` | 版本号 | Modify |

**任务边界依据**：Task 1–2 是词汇表与它的守门（先立规矩）；Task 3 是开关（词汇表要能被关掉才有意义）；Task 4–6 是三类铺开（共享组件 / 提交点 / 手势），各自独立可测；Task 7–8 是设计语言对齐；Task 9 是防复发；Task 10–11 收尾。

---

### Task 1: 触觉词汇表 `core/haptics.dart`

**Files:**
- Create: `app/lib/core/haptics.dart`
- Create: `app/test/haptics_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `bool hapticsDisabled`（顶层可变变量，默认 `false`）
  - `Haptics.select()` / `Haptics.commit()` / `Haptics.modeEnter()` —— 均为 `static void`，无参数无返回

- [ ] **Step 1: 写失败的测试**

创建 `app/test/haptics_test.dart`：

```dart
// app/test/haptics_test.dart
//
// 触觉词汇表的两个行为：开关关掉时一处不动；开着时按档位发出对应的
// `HapticFeedbackType`。
//
// 三个档位全部走 `SystemChannels.platform` 的 `HapticFeedback.vibrate`，
// 只是参数字符串不同 —— 拦这一个方法就够断言全部三档，不必碰真振动器。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Object?> fired;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    fired = [];
    hapticsDisabled = false;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    // 标志是模块级的，漏还原会漏给下一个用例（本文件里就有个用例专门置真）。
    hapticsDisabled = false;
  });

  test('三档各自发出对应的 HapticFeedbackType', () async {
    Haptics.select();
    Haptics.commit();
    Haptics.modeEnter();
    await pumpEventQueue();
    expect(fired, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
    ]);
  });

  test('关掉之后一次都不发（一处生效，调用点不用自己查）', () async {
    hapticsDisabled = true;
    Haptics.select();
    Haptics.commit();
    Haptics.modeEnter();
    await pumpEventQueue();
    expect(fired, isEmpty);
  });

  test('词汇表完整性：三个名字都被本文件断言过', () {
    // 与 `design_tokens_test` 的「令牌自检」同一个理由：手写枚举的 expect 列表
    // 加漏一个，测试照样绿。这里按名字去源码里找。
    final lexicon = File('lib/core/haptics.dart').readAsStringSync();
    final self = File('test/haptics_test.dart').readAsStringSync();
    for (final name in ['select', 'commit', 'modeEnter']) {
      expect(lexicon, contains('static void $name('),
          reason: '词汇表里没有 $name —— 删档位的话本测试要跟着改');
      expect(self, contains('Haptics.$name()'),
          reason: '$name 没有任何断言覆盖到');
    }
  });
}
```

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/haptics_test.dart
```

期望：编译失败 —— `Target of URI doesn't exist: 'package:shiftassistantpro/core/haptics.dart'`。

- [ ] **Step 3: 实现词汇表**

创建 `app/lib/core/haptics.dart`：

```dart
// 触觉反馈的设计系统层 —— 与 `core/motion.dart`（交互反馈的动画层）、
// `core/design_tokens.dart`（视觉令牌）并列。
//
// 词汇表按**语义**命名，不按强度：调用方写 `Haptics.select()` 表达的是「选中
// 变了」，不是「震得轻一点」。这样将来调某一档的强度时，不必回头改所有调用点。
//
// **挂动作，不挂按压。** 普通点击一律不震 —— 震动一旦变成背景噪音，信息量就归零，
// 用户会去系统里把触觉整个关掉，那时你想用震动区分的那件事也一起没了。所以
// `GlassPressable` 故意不挂：它包的是*每一次*按压，包括普通点击。触觉只出现在
// 「状态真的变了」或「这一步不可逆」的时刻。
//
// **除本文件外，任何地方不许直接调 `HapticFeedback.*`** —— 由
// `test/haptics_guard_test.dart` 扫源码盯着。
import 'dart:async';

import 'package:flutter/services.dart';

/// 用户是否关掉了触觉反馈（由「外观」设置反灌）。
///
/// 走模块级标志，而不是让每个调用点自己去查设置 —— 与 `advancedMaterialDisabled`
/// （`core/glass/glass.dart`）同一条路：一处赋值全 app 生效，没人会漏查。
bool hapticsDisabled = false;

/// 触觉词汇表。**只有三档**，且只在下面三种语义下调用。
abstract final class Haptics {
  /// **选中变了**：开关翻转、胶囊段切换、选项胶囊选中、选择器提交、拖到新格。
  static void select() => _fire(HapticFeedback.selectionClick);

  /// **动作落实**：删除类确认、待办勾选完成、应用改班 / 恢复轮转、切换排班方案。
  static void commit() => _fire(HapticFeedback.lightImpact);

  /// **进入一个模式**：长按进入日历的多选态。
  static void modeEnter() => _fire(HapticFeedback.mediumImpact);

  /// 统一出口：先查开关，再发；且 fire-and-forget。
  ///
  /// **参数必须是「函数」而不是「已求值的 Future」** —— 这是本文件最容易写错的一处：
  /// 写成 `_fire(HapticFeedback.selectionClick())` 的话，那个调用在**传参时**就已经
  /// 发生了（Dart 先求值实参），平台消息在 `hapticsDisabled` 判断之前就发了出去，
  /// 于是用户的开关完全失效、而任何只看「有没有调用 Haptics」的测试都照样绿。
  /// 传 `HapticFeedback.selectionClick` 这个方法引用，等检查过了再调。
  ///
  /// **不 await、异常不上抛**：震不震不该影响功能，更不该让一个触觉调用的失败
  /// 冒到业务逻辑里。平台侧拒绝（没有振动器、被系统策略拦掉）静默忽略即可。
  static void _fire(Future<void> Function() call) {
    if (hapticsDisabled) return;
    unawaited(call().catchError((Object _) {}));
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/haptics_test.dart && flutter analyze
```

期望：3 条全 PASS，`flutter analyze` 干净。若 `abstract final class` 报语法错，说明 SDK 太老 —— 换成普通的 `abstract class Haptics` 加私有构造（`Haptics._();`），语义等价。

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/haptics.dart app/test/haptics_test.dart
git commit -m "feat(core): 触觉反馈词汇表（三档语义 + 模块级开关）"
```

---

### Task 2: 守门测试 + 抽出共用的源码剥壳器

**Files:**
- Create: `app/test/support/source_scan.dart`
- Create: `app/test/haptics_guard_test.dart`
- Modify: `app/test/design_tokens_test.dart`（删掉本地的 `blankNonCode` / `_identChar`，改成 import）

**Interfaces:**
- Consumes: Task 1 的 `core/haptics.dart`
- Produces: `String blankNonCode(String src)` —— 顶层公开函数，可被任意测试 import

> **为什么要把剥壳器抽出来而不是复制一份**：它要正确处理**可嵌套的块注释**、三引号字符串、原始字符串前缀 —— 抄一份迟早两份会走偏，而走偏的表现是**漏检**（把真代码当注释清掉）。`test/support/` 目录已经存在（`cjk.dart`），放这里就是它的用途。

- [ ] **Step 1: 抽剥壳器**

把 `app/test/design_tokens_test.dart` 里的 `blankNonCode` 函数（约 `:48-137`，含它上方那段说明文档注释）与它依赖的私有 `_identChar` 正则**整体剪切**到新文件 `app/test/support/source_scan.dart`。

新文件的形状：

```dart
// app/test/support/source_scan.dart
//
// 源码剥壳器：把 Dart 源码里的**非代码部分**（行注释、块注释、字符串字面量的
// 内容）替换成**等长空格**，供「按模式扫源码」的守门测试共用。
//
// 原本长在 `design_tokens_test.dart` 里。触觉守门测试（`haptics_guard_test.dart`）
// 也要用它，所以抽到这里 —— 抄一份的话，两份迟早走偏，而走偏的表现是**漏检**
// （把真代码当成注释清掉），不会报错。
//
// 注意：**豁免标记写在注释里**，所以「有没有具名豁免」必须回到**原始源码**上查，
// 不能查这个副本（注释在这里已经是空格了）。
//
// 本文件**不需要任何 import** —— `blankNonCode` 只用 `String` / `RegExp`，都在
// `dart:core` 里。
final _identChar = RegExp(r'[A-Za-z0-9_$]');

String blankNonCode(String src) {
  // …（原样搬过来，一个字符都不用改）
}
```

`app/test/design_tokens_test.dart` 顶部加：

```dart
import 'support/source_scan.dart';
```

并删掉本文件里那两处定义。**`design_tokens_test.dart` 的其余部分一个字都不许动** —— 它是 1103 行的守门测试，改坏它比不改更糟。

> ✅ **`_identChar` 的去留我已经替你核实过了：它留在原处。** 它在本文件里出现三次 —— `:113`（`blankNonCode` 内）、`:224` 定义、以及 **`:245`（`blankNonCode` 之外，函数在 `:135` 就结束了）**。所以**只搬 `blankNonCode`**，`_identChar` 在 `design_tokens_test.dart` 原地不动，`source_scan.dart` 自己定义一份私有副本。两份正则都是 `[A-Za-z0-9_$]`（Dart 标识符字符集，写死在语言里），不存在走偏风险。

- [ ] **Step 2: 确认抽取没改行为**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/design_tokens_test.dart
```

期望：**与抽取前完全相同的通过条数**（23 条）。这一条就是这个步骤的全部证据 —— 抽取是纯搬运，条数或结果变了就是搬错了。

- [ ] **Step 3: 写守门测试**

创建 `app/test/haptics_guard_test.dart`：

```dart
// app/test/haptics_guard_test.dart
//
// 守门：**除 `lib/core/haptics.dart` 外，任何文件不许直接调 `HapticFeedback.*`。**
//
// 少了这条，词汇表会被绕过 —— 新代码想加个震动就自己写一行 `HapticFeedback`，
// 那「三档语义 + 一处开关」两天就散了，而且绕过的那些**不会**受用户开关控制。
//
// 规则跑在剥过壳的副本上（见 `support/source_scan.dart`）：否则在注释里提一句
// `HapticFeedback` 就会把构建打红 —— `design_tokens_test` 在 v0.6.11 踩过这个坑。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

/// 唯一允许直接调用 `HapticFeedback` 的文件。
const String _lexiconPath = 'lib/core/haptics.dart';

void main() {
  test('除词汇表外，没有地方直接调 HapticFeedback', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path == _lexiconPath) continue;
      if (blankNonCode(entity.readAsStringSync()).contains('HapticFeedback.')) {
        offenders.add(path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '这些文件绕过了词汇表直接调 HapticFeedback：\n'
          '  ${offenders.join('\n  ')}\n'
          '改用 core/haptics.dart 的 Haptics.select() / commit() / modeEnter()。'
          '它们经过用户开关，绕过的那行不会。',
    );
  });
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/haptics_guard_test.dart && flutter test && flutter analyze
```

期望：守门测试 PASS（此刻全 app 还没有别处直接调 `HapticFeedback`，所以是绿的）；全量 **221** 条（217 + Task 1 的 3 条 + 本任务的 1 条）；analyze 干净。

**验证这条守卫不是恒真**：临时在 `app/lib/core/glass/glass.dart` 顶部加一行 `// ignore: unused_import`+`import 'package:flutter/services.dart';` 并在某个 `build` 里写一句 `HapticFeedback.lightImpact();`，跑守门测试 → 必须变红并点名该文件；然后删掉那行、确认恢复绿。**把观察到的输出写进报告。**

- [ ] **Step 5: 提交**

```bash
git add app/test/support/source_scan.dart app/test/haptics_guard_test.dart app/test/design_tokens_test.dart
git commit -m "test(haptics): 守门禁止绕过词汇表，剥壳器抽到 test/support 共用"
```

---

### Task 3: 开关（`AppSettings` + 设置页）

**Files:**
- Modify: `app/lib/state/app_settings.dart`
- Modify: `app/lib/core/l10n.dart`
- Modify: `app/lib/features/profile/profile_screen.dart`
- Create: `app/test/haptics_setting_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `hapticsDisabled`
- Produces:
  - `AppSettings.hapticsEnabled`（`bool`，默认 `true`）
  - `AppSettingsNotifier.setHapticsEnabled(bool)`
  - `L10n.hapticFeedback` / `L10n.hapticFeedbackHint`

- [ ] **Step 1: 写失败的测试**

创建 `app/test/haptics_setting_test.dart`：

```dart
// app/test/haptics_setting_test.dart
//
// 「触觉反馈」这个开关的两件事：
//   1. 持久化 —— 关掉再重建 notifier，仍然是关的（跟「高级材质」同一套）
//   2. 反灌 —— 它真的会去改 `hapticsDisabled`，否则词汇表根本不知道用户关过
// 第 2 条是重点：少了哪一处赋值，开关在界面上看着能拨，实际一点作用都没有。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/haptics.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/features/profile/profile_screen.dart';
import 'package:shiftassistantpro/state/app_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    hapticsDisabled = false;
    L10n.locale = 'zh';
  });

  test('默认开着', () async {
    final n = AppSettingsNotifier();
    await pumpEventQueue();
    expect(n.state.hapticsEnabled, isTrue);
    expect(hapticsDisabled, isFalse);
  });

  test('关掉之后：状态、持久化、反灌标志三处都跟着走', () async {
    final n = AppSettingsNotifier();
    await pumpEventQueue();
    await n.setHapticsEnabled(false);
    expect(n.state.hapticsEnabled, isFalse);
    expect(hapticsDisabled, isTrue, reason: '词汇表靠这个标志，漏了开关就是摆设');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('hapticsEnabled'), isFalse, reason: '要能跨启动记住');

    // 重建一个 notifier（模拟下次启动）
    hapticsDisabled = false;
    final n2 = AppSettingsNotifier();
    await pumpEventQueue();
    expect(n2.state.hapticsEnabled, isFalse);
    expect(hapticsDisabled, isTrue);
  });

  testWidgets('设置页「外观」分区里有这一行，且能拨动', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: ProfileScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text(L10n.hapticFeedback), findsOneWidget);
    expect(find.text(L10n.hapticFeedbackHint), findsOneWidget);
  });
}
```

> **实施时核实**：`ProfileScreen` 是否需要额外的 provider override 才能渲染（它可能读数据库）。照抄 `app/test/` 里既有的、渲染 `ProfileScreen` 的用例的夹具；若没有先例，就把第三个 `testWidgets` 降级为「只断言两个 `L10n` 文案非空、且 `L10n.hapticFeedback` 与 `L10n.hapticFeedbackHint` 是不同字符串」，并在报告里说明为什么没做界面断言 —— 不要为了让它绿色而写一个假断言。

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/haptics_setting_test.dart
```

期望：编译失败 —— `The getter 'hapticsEnabled' isn't defined` / `'setHapticsEnabled' isn't defined` / `'hapticFeedback' isn't defined`。

- [ ] **Step 3: 实现**

**3a. `app/lib/state/app_settings.dart`** —— 照 `advancedMaterial` 那条路一模一样地加。

字段与构造参数：

```dart
    this.advancedMaterial = true,
    this.hapticsEnabled = true,
```

```dart
  /// 触觉反馈：true=状态改变与不可逆动作时轻微震动（默认），false=完全不震。
  final bool hapticsEnabled;
```

`copyWith` 加 `bool? hapticsEnabled,` 与 `hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,`。

`_load()` 里读出来、赋给 state，并在已有的 `advancedMaterialDisabled = …` 那两行**紧邻**处加：

```dart
      final hapticsEnabled = sp.getBool('hapticsEnabled') ?? true;
      hapticsDisabled = !hapticsEnabled;
```

（`import '../core/haptics.dart';` 加到文件顶部；state 的构造里带上 `hapticsEnabled: hapticsEnabled`。）

新增 setter，形状与 `setAdvancedMaterial` 完全一致：

```dart
  Future<void> setHapticsEnabled(bool value) async {
    state = state.copyWith(hapticsEnabled: value);
    hapticsDisabled = !value;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('hapticsEnabled', value);
    } catch (_) {}
  }
```

> ⚠️ `setAdvancedMaterial` 的实际形状以文件里那个为准（`_load` 里的赋值是否在 `try` 内、持久化怎么写）—— **读一遍它再照着写**，不要照抄上面的示意。

**3b. `app/lib/core/l10n.dart`** —— 在「外观」分区那一片加：

```dart
  // 触觉反馈（外观分区的一条设置）
  static String get hapticFeedback => t('触觉反馈', 'Haptic feedback');
  static String get hapticFeedbackHint =>
      t('切换开关、选中、删除确认时轻微震动',
        'Subtle vibration on toggles, selections and delete confirmations');
```

**3c. `app/lib/features/profile/profile_screen.dart`** —— 在「高级材质」那一行**之后**、同一个「外观」分区里，加一行同形状的设置行（标题 + 副标题 + 右侧 `GlassSwitch`），形状照抄 `:125-142` 那一处：

```dart
                      GlassSwitch(
                        value: settings.hapticsEnabled,
                        onChanged: (v) =>
                            ref.read(appSettingsProvider.notifier)
                                .setHapticsEnabled(v),
                      ),
```

标题 `L10n.hapticFeedback`、副标题 `L10n.hapticFeedbackHint`。**副标题的 style 抄同一分区那条副标题用的角色**（`AppTokens.microText.copyWith(color: AppTokens.inkMuted(context))`），不要另立。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/haptics_setting_test.dart && flutter test test/design_tokens_test.dart && flutter analyze
```

期望：新用例全 PASS；`design_tokens_test` 仍 23 条绿（新加的那行 UI 不许有字面量）；analyze 干净。

- [ ] **Step 5: 提交**

```bash
git add app/lib/state/app_settings.dart app/lib/core/l10n.dart app/lib/features/profile/profile_screen.dart app/test/haptics_setting_test.dart
git commit -m "feat(settings): 触觉反馈开关（外观分区，默认开）"
```

---

### Task 4: 共享组件自震（三类最高频的交互）

**Files:**
- Modify: `app/lib/core/widgets/glass_switch.dart`
- Modify: `app/lib/core/widgets/glass_segment.dart`
- Modify: `app/lib/core/widgets/glass_choice_chip.dart`
- Modify: `app/lib/core/widgets/glass_pickers.dart`
- Create: `app/test/haptics_shared_widgets_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Haptics.select()`
- Produces: 无（纯行为）

- [ ] **Step 1: 写失败的测试**

创建 `app/test/haptics_shared_widgets_test.dart`：

```dart
// app/test/haptics_shared_widgets_test.dart
//
// 共享组件自己震的那几处。三件事各有用例：
//   1. 真的会震（不然「自动一致」是空话）
//   2. 状态没变时**不震**（点当前已选中的那一段不该有反馈）
//   3. 选择器的滚轮**滚动**不震 —— 拨一次滚轮连震十几下是这套设计最容易犯的错
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/haptics.dart';
import 'package:shiftassistantpro/core/widgets/glass_choice_chip.dart';
import 'package:shiftassistantpro/core/widgets/glass_segment.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Object?> fired;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    fired = [];
    hapticsDisabled = false;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    hapticsDisabled = false;
  });

  testWidgets('GlassSwitch 翻转时震一次', (tester) async {
    var value = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => GlassSwitch(
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(GlassSwitch));
    await tester.pumpAndSettle();
    expect(fired, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('GlassSegment 选中项变了才震；点当前段不震', (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => GlassSegment(
            count: 3,
            selectedIndex: selected,
            height: 40,
            // `itemBuilder` 是**必填**的（签名已核实），漏了编译不过。
            itemBuilder: (i, isSelected) => Text('$i'),
            onSelected: (i) => setState(() => selected = i),
          ),
        ),
      ),
    ));

    // 点第二段：选中变了 → 震
    final box = tester.getRect(find.byType(GlassSegment));
    await tester.tapAt(Offset(box.left + box.width / 2, box.center.dy));
    await tester.pumpAndSettle();
    expect(fired, hasLength(1), reason: '选中变了该震');

    // 再点同一段：没变 → 不震
    await tester.tapAt(Offset(box.left + box.width / 2, box.center.dy));
    await tester.pumpAndSettle();
    expect(fired, hasLength(1), reason: '状态没变不该再震');
  });

  testWidgets('GlassChoiceChip 选中时震一次', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlassChoiceChip(
          label: '白班',
          selected: false,
          color: Colors.blue,
          onTap: () {},
        ),
      ),
    ));
    await tester.tap(find.byType(GlassChoiceChip));
    await tester.pumpAndSettle();
    expect(fired, hasLength(1));
  });

  testWidgets('时间选择器：拨滚轮不震，点确定才震一次', (tester) async {
    // 这一条是 spec §6.3 点名的「滚轮不震」，也是这套设计最容易犯的错 ——
    // 把触觉挂到 `onSelectedItemChanged` 上，拨一次滚轮会连震十几下。
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showGlassTimePicker(
              context,
              initialTime: const TimeOfDay(hour: 7, minute: 0),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 拨滚轮：一格都不该震
    final wheel = find.byType(ListWheelScrollView);
    expect(wheel, findsWidgets, reason: '时间选择器应该是滚轮');
    await tester.drag(wheel.first, const Offset(0, 80));
    await tester.pumpAndSettle();
    expect(fired, isEmpty, reason: '滚动不是提交，绝不能震');

    // 点确定：一次
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();
    expect(fired, hasLength(1), reason: '确定那一处才是提交点');
  });
}
```

> **实施时核实**：时间选择器里那个滚轮的真实 widget 类型（`ListWheelScrollView` / `CupertinoPicker` / 自绘），以及确认按钮上的文案取的是哪个 `L10n` 常量（[glass_pickers.dart:118](app/lib/core/widgets/glass_pickers.dart:118) 附近那处）。按实际改；**若滚轮在测试环境里确实拨不动**（拿不到可拖的目标），就在报告里明说「这一条测不了，原因是 X」，**不要**把那条否定断言删掉后假装测过了 —— 它是 spec 点名要的那条。

> ✅ **构造签名我已经替你核实过了**（省得你再去试）：
> - `GlassSwitch({value, onChanged, activeColor?, width = 46, height = 28})`
> - `GlassSegment({count, selectedIndex, onSelected, **required** itemBuilder, height = 44})` —— `itemBuilder` 是必填，上面的代码已补
> - `GlassChoiceChip({label, color, selected, onTap, semanticsLabel?})`
> - 时间选择器的确定按钮是 `GlassActionButton(label: L10n.confirm, …)`，所以 `find.text(L10n.confirm)` 可用；滚轮是 `ListWheelScrollView`（若实际不是这个类型，按真实类型改，并在报告里说明）。

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/haptics_shared_widgets_test.dart
```

期望：三条都失败（`fired` 为空）。

- [ ] **Step 3: 实现**

**3a. `glass_switch.dart`** —— `GestureDetector` 的 `onTap`（约 `:30`）：

```dart
      onTap: () {
        Haptics.select();
        onChanged(!value);
      },
```

**3b. `glass_segment.dart`** —— `_release()` 里**已有**「选中项真的变了」的判据，触觉就放进去（不要另写判据）：

```dart
    if (target != widget.selectedIndex) widget.onSelected(target);
```

改成：

```dart
    if (target != widget.selectedIndex) {
      // 只有选中项真的变了才震 —— 拖动回原位、点当前段都不该有反馈。
      Haptics.select();
      widget.onSelected(target);
    }
```

**3c. `glass_choice_chip.dart`** —— `InkWell` 的 `onTap`（约 `:54`）：

```dart
          onTap: () {
            Haptics.select();
            onTap();
          },
```

> 这个组件的「选没选中」由父级决定，组件自己判断不了，所以**只要点了就算一次选中意图**，即使父级忽略它。可接受：胶囊不是高频误点控件。

**3d. `glass_pickers.dart`** —— **四个**提交点各加一行 `Haptics.select();`，位置都在 `Navigator.pop` 之前：

- 时间选择器约 `:123`（确定按钮的 `onPressed`）
- 日期选择器约 `:205`（某个日期的 `onTap`）
- 年月选择器约 `:403`
- 选项选择器约 `:501`

> ⚠️ **绝对不要**给 `showGlassTimePicker` 的 `onSelectedItemChanged`（约 `:48`）加 —— 那是滚轮**滚动**，拨一次会连震十几下（spec §4.1 点名的头号错误）。只有 `Navigator.pop` 那一处算提交。
>
> ⚠️ 上面几个行号是**改动前**的，加完前一处会整体下移 —— 每一处都先 `grep -n "Navigator.pop" app/lib/core/widgets/glass_pickers.dart` 重新定位，不要照着行号盲改。

每个文件顶部加 `import '../../core/haptics.dart';`（`glass_pickers.dart` 同理，路径深度按它自己的位置调整）。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/haptics_shared_widgets_test.dart && flutter test test/haptics_guard_test.dart && flutter test
```

期望：三条全 PASS；守门仍绿（说明都走了词汇表、没绕过）；全量只增不减。

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/widgets/glass_switch.dart app/lib/core/widgets/glass_segment.dart app/lib/core/widgets/glass_choice_chip.dart app/lib/core/widgets/glass_pickers.dart app/test/haptics_shared_widgets_test.dart
git commit -m "feat(haptics): 共享组件自震（开关 / 胶囊段 / 选项胶囊 / 选择器提交）"
```

---

### Task 5: 提交点显式震

**Files:**
- Modify: `app/lib/core/widgets/glass_action_button.dart`
- Modify: `app/lib/features/schedule/schedule_screen.dart`
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Create: `app/test/haptics_commit_points_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Haptics.commit()`
- Produces: 无

> ⚠️ **本任务最容易犯的错是重复震动。** `GlassSwitch` 在 Task 4 已经自震了，所以 [alarm_screen.dart:234](app/lib/features/alarm/alarm_screen.dart:234) 与 `:277` 那两条**闹钟单条开关不需要再写** —— 写了就是每拨一下震两下。**动手前先确认那个控件是不是已经在 Task 4 覆盖的名单里**（`GlassSwitch` / `GlassSegment` / `GlassChoiceChip` / 四个 picker）。

- [ ] **Step 1: 删除确认的落点（已替你核实完毕，照做即可）**

`GlassActionVariant.danger` 全 app 共 **4 处**调用，我逐个读过上下文，**全部是破坏性确认对话框里的「确认」按钮**：

| 位置 | 是什么 |
|---|---|
| `profile_screen.dart:309` | 清除全部数据（`confirmResetAction`） |
| `schedule_management_screen.dart:109` | 删除排班方案（`delete`） |
| `schedule_editor_screen.dart:1190` | 切「跟随法定节假日」并丢掉按天调整（`confirm`） |
| `schedule_editor_screen.dart:1348` | 删除一个班次定义（`delete`） |

每个对话框的**取消**按钮用的是别的变体，所以不会连带。

**决定：把 `Haptics.commit();` 加在 `glass_action_button.dart` 的按压路径上、按变体门住**，一处覆盖全部四处删除确认，不必改四个调用点。

⚠️ **不是加在那个 `case` 里** —— `case GlassActionVariant.danger:` 在选配色的 switch 里，不在按压路径上。真正的位置是约 `:125` 那个 `InkWell(onTap: widget.onPressed, …)`：

```dart
            child: InkWell(
              // `onPressed` 是可空的（为 null 时按钮本就禁用），所以整段要门住 ——
              // 直接 `widget.onPressed()` 会在禁用态崩掉。
              onTap: widget.onPressed == null
                  ? null
                  : () {
                      // 危险变体 = 破坏性确认（全 app 四处，全是删除/清空类）。
                      // `commit` 表达的是「这一步不可逆」，与普通点击区分开。
                      if (widget.variant == GlassActionVariant.danger) {
                        Haptics.commit();
                      }
                      widget.onPressed!();
                    },
```

`GlassActionButton` 的构造签名（已核实）：`{required onPressed /* VoidCallback? */, required label, variant = GlassActionVariant.secondary, icon?}`。

> 若你在实施时发现还有**第 5 处** danger 调用、且它不是破坏性动作，就**不要**加在按钮里，改为在那四处调用点各加一次，并把发现写进报告。

- [ ] **Step 2: 写失败的测试**

创建 `app/test/haptics_commit_points_test.dart`：

```dart
// app/test/haptics_commit_points_test.dart
//
// 提交点显式震的那几处。**这里只覆盖不依赖数据库的那两处**（危险按钮会震、
// 非危险按钮不震）；**待办勾选、改班、切换方案这三处本文件不测** —— 它们各需要
// 一套真库 + Riverpod 夹具，成本远高于收益，由「守门测试 + 全量套件」兜底
// （守门保证它们走的是词汇表，而不是绕过）。
//
// 这条边界是**有意画在这里的**，不是漏写；上一轮有两次因为「断言声称覆盖了
// 其实没覆盖的东西」被打回，所以这里把没覆盖的明写出来。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/haptics.dart';
import 'package:shiftassistantpro/core/widgets/glass_action_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Object?> fired;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    fired = [];
    hapticsDisabled = false;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    hapticsDisabled = false;
  });

  testWidgets('危险确认按钮按下时震一次', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlassActionButton(
          label: '删除',
          onPressed: () {},
          variant: GlassActionVariant.danger,
        ),
      ),
    ));
    await tester.tap(find.byType(GlassActionButton));
    await tester.pumpAndSettle();
    expect(fired, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('非危险的同类按钮不震（普通按钮点击一律不震）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlassActionButton(
          label: '取消',
          onPressed: () {},
          variant: GlassActionVariant.secondary,
        ),
      ),
    ));
    await tester.tap(find.byType(GlassActionButton));
    await tester.pumpAndSettle();
    expect(fired, isEmpty, reason: '决策①：普通点击一律不震');
  });
}
```

> **实施时核实** `GlassActionButton` 的真实构造参数（`label` / `onPressed` / `variant` 的名字与是否必填）。按实际签名改，不要改组件签名。
> 第二条用例（非危险不震）是**故意**的护栏：若第 1 步判定「加在按钮里」，这条就同时钉住了「只给 danger 分支加」。

- [ ] **Step 3: 跑测试确认它失败**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/haptics_commit_points_test.dart
```

期望：第一条失败（`fired` 为空）；第二条本来就该绿。

- [ ] **Step 4: 实现剩下三处**

- **危险确认按钮**：按第 1 步的判定落地（`glass_action_button.dart` 的 danger 分支，或各调用点）。
- **待办勾选完成 —— 不加（已裁定，见 spec §4.2 的「一条自我纠正」）。** 那个控件（`schedule_screen.dart:119`）是 `GlassSwitch`，§4.1 已经让它自动震 `select()` 了；再补一个 `commit()` 就是**拨一下震两下**，正好是 §4.2 那条闹钟警告说的同一个错。spec 原文把待办列成一个提交点是**枚举时的疏忽**，已更正。
  **所以待办那一处的测试应当断言「只有 `select()`、没有 `commit()`」** —— 那才钉住了裁定。
- **应用改班 / 恢复轮转** —— `calendar_screen.dart` 的 `adjustDays` 里，`setDayOverrides` / `clearDayOverrides` **落库之后**加 `Haptics.commit();`（放在 `AlarmService.rescheduleAll` 之前或之后都行，但要在写库之后 —— 写失败就落不进这一步）。
- **切换排班方案** —— [calendar_screen.dart:532](app/lib/features/calendar/calendar_screen.dart:532) 的 `await repo.setCurrentSchedule(id);` 之后加 `Haptics.commit();`。

> **通用规则（由待办那次裁定得出）**：§4.1 覆盖的控件（`GlassSwitch` / `GlassSegment` / `GlassChoiceChip` / 四个选择器提交点）**绝不能再加 §4.2 的触觉**。加任何一处之前，先确认它不在 §4.1 的名单里。

三处都要 `import '../../core/haptics.dart';`（路径按文件位置调整）。

- [ ] **Step 5: 跑测试确认通过**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/haptics_commit_points_test.dart && flutter test test/haptics_guard_test.dart && flutter test && flutter analyze
```

期望：两条全 PASS；守门绿；全量只增不减；analyze 干净。

- [ ] **Step 6: 提交**

```bash
git add app/lib/core/widgets/glass_action_button.dart app/lib/features/schedule/schedule_screen.dart app/lib/features/calendar/calendar_screen.dart app/test/haptics_commit_points_test.dart
git commit -m "feat(haptics): 提交点显式震（删除确认 / 待办勾选 / 改班 / 切换方案）"
```

---

### Task 6: 日历手势震（单格滑块 + 长按两级）

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Modify: `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Haptics.select()` / `Haptics.modeEnter()`
- Produces: 无

- [ ] **Step 1: 写失败的用例**

在 `app/test/calendar_screen_test.dart` 追加（复用文件里已有的 `_pumpCalendar` / `_disposeCalendar` 夹具）：

```dart
  testWidgets('长按进入多选态震一次，每进一格再震一次', (tester) async {
    final fired = <Object?>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
      return null;
    });
    addTearDown(() => messenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _pumpCalendar(tester, 'day_night_rest_rest');
    fired.clear(); // 建树过程本身不该有触觉

    final start =
        tester.getCenter(find.byKey(const ValueKey('day-card-8')));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600)); // 过长按判定
    await gesture.moveBy(const Offset(0, 60));            // 往下拖一格
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(fired, contains('HapticFeedbackType.mediumImpact'),
        reason: '进入多选态那一下是 modeEnter');
    expect(fired, contains('HapticFeedbackType.selectionClick'),
        reason: '每进一格要有 select');
    expect(fired.where((f) => f == 'HapticFeedbackType.mediumImpact'),
        hasLength(1), reason: '进入只该震一次');

    await _disposeCalendar(tester);
  });

  testWidgets('单格滑块拖到新的一格时震，没换格不震', (tester) async {
    final fired = <Object?>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
      return null;
    });
    addTearDown(() => messenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _pumpCalendar(tester, 'day_night_rest_rest');

    // **先把滑块钉到 8 号。** 本用例两半都依赖「当前选中是 8 号」这个前提，而
    // `_pumpCalendar` 默认选的是今天 —— 不钉的话，下面的拖动会从「今天」出发、
    // 落到「今天 + 7」，而随后点 8 号就成了**真的换格**、必然震，与「不震」那半
    // 直接矛盾。（原计划漏了这一步，实测撞了这个矛盾。）
    final day8 = find.byKey(const ValueKey('day-card-8'));
    await tester.tapAt(tester.getCenter(day8));
    await tester.pumpAndSettle();

    // ── 先测「没换格不震」 ──
    // **顺序不能颠倒**：拖动的落点由「当前选中」算出来。先测这半，才能保证下一段
    // 的拖动是从 8 号出发往下走一行（8 号在任意月份都落在网格第 2 行，
    // `index = leading + 7`）。若先拖动，`_selected` 就变了，这半就不再成立。
    fired.clear();
    await tester.tapAt(tester.getCenter(day8));
    await tester.pumpAndSettle();
    expect(fired, isEmpty, reason: '选中没变不该震');

    // ── 再测「换格要震」 ──
    fired.clear();
    final cellH = tester.getSize(day8).height;
    final start = tester.getCenter(day8);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(Offset(0, 20)); // 先过 slop，把 Tap 识别器挤掉
    await tester.pump();
    await gesture.moveBy(Offset(0, cellH)); // 落到下一行
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fired, isNotEmpty, reason: '拖动落到新的一格该震');

    await _disposeCalendar(tester);
  });
```

> ⚠️ **别把第一条用例写成 `fired.first == mediumImpact`。** 长按起手那一下会先走 `onTapDown` → `_selectFromPosition`，而 8 号本来不是当前选中日，所以**先**响一次 `selectionClick`（选中确实变了，这是对的），`mediumImpact` 排在它后面。断言用「包含 + 计数」，不要赌顺序。

> ⚠️ **沿月末拖动会落空。** `_nearestDateFromVisual` 对本月之外的格子返回 null —— 一个月里约 23% 的日子，从「今天」往下拖一格是**不改变任何东西**的（所以「拖动必震」不能拿「今天」当锚点）。钉到 8 号也顺带解决了这个：它总在第 2 行，往下一定还有一行。

> **实施时核实**：模板 id 用 `day_night_rest_rest`（v0.8.1 那轮已核实它存在，`four_crew_two_shift` **不存在**）；`day-card-8` 这个 key 的日期 8 号在任意月份都落在网格第 2 行（`leading ∈ [0,6]` 时 `index = leading + 7`），所以往下拖一格一定能换行。

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/calendar_screen_test.dart
```

期望：两条新用例都失败（`fired` 为空）。

- [ ] **Step 3: 实现**

**3a. 单格滑块 —— 有**两个**落点，不是一处（原计划只写了第一处，是错的）**

`_selectFromPosition` 只从 `onTapDown` 走到。而**拖动**是 Pan：一旦移动越过 slop，Tap 识别器就被拒了，拖动走的是 `onPanEnd` → `_nearestDateFromVisual()`，**根本不经过 `_selectFromPosition`**。只改第一处的话，滑块拖一次都不会震。

两处都要，判据都是「吸附到的日期真的变了」：

```dart
  void _selectFromPosition(Offset pos, double cellW, double cellH) {
    final date = _dateFromPosition(pos, cellW, cellH);
    if (date != null && date != _selected) {
      // 与长按拖选同一口径：**吸附到的格子真的变了**才震。原地按一下不震。
      Haptics.select();
      setState(() => _selected = date);
    }
  }
```

`onPanEnd` 里（约 `:670` 那个回调），在它已有的 `if (date != null) _selected = date;` 处补上同一判据：

```dart
          onPanEnd: (_) {
            final date = _nearestDateFromVisual();
            setState(() {
              _pressed = false;
              _dragActive = false;
              if (date != null && date != _selected) {
                // 拖动落点。**必须在 setState 之外震**（回调要同步无副作用），
                // 但判据要用 setState 之前的 _selected —— 所以先算好。
                Haptics.select();
                _selected = date;
              }
            });
          },
```

> ⚠️ 注意上面那句 `Haptics.select()` 写在 `setState` 的闭包里了 —— 把它挪到 `setState` **外面**：先 `final changed = date != null && date != _selected;`，`setState` 里只赋值，`setState` 之后再 `if (changed) Haptics.select();`。计划里给的是示意，**以「回调同步无副作用」为准**。

**3b. 长按进入** —— `onLongPressStart` 里，`_rangeAnchor` 被设成有效日期的那一处（`canPick` 为真、且 `_dateFromPosition` 拿到了日期）：

```dart
              _rangeAnchor = date;
              _rangeFocus = date;
            });
            // **必须门住 `date != null`。** 长按落在空白格 / 周标题 / 或者**任何
            // 一张空白表方案上**（`canPick == false`）时，`date` 是 null、`_rangeAnchor`
            // 也没被设上 —— 那时压根没进入多选态，绝不能响。无条件写的话，每次
            // 这种长按都会发一记「已进入多选态」的闷响，而什么都没发生。
            if (date != null) Haptics.modeEnter();
```

（`Haptics.modeEnter()` 放在 `setState` **之外**：`setState` 的回调必须同步且无副作用，触觉是副作用。）

> ⚠️ 这一处原计划给的是**无条件**的代码片段，与同一段散文（「`canPick` 为真、且 `_dateFromPosition` 拿到了日期」）和 spec §4.3 都矛盾 —— 已更正。**散文与 spec 为准。**

**3c. 长按拖选每进一格** —— `onLongPressMoveUpdate` 里 `_rangeFocus` 真的变了的那一处：

```dart
            if (date == null || date == _rangeFocus) return;
            Haptics.select();
            setState(() => _rangeFocus = date);
```

范围往回缩时同样会响 —— 只要吸附到的格子变了就响，两个方向一致（spec §4.3）。

**3d.** `import '../../core/haptics.dart';` 加到 `calendar_screen.dart` 顶部。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/calendar_screen_test.dart && flutter test test/haptics_guard_test.dart && flutter test && flutter analyze
```

期望：两条新用例 PASS；**既有的全部日历用例不回归**（尤其单格滑块与长按那几条 —— 触觉加在判据**之内**，不该改变任何行为）；守门绿；analyze 干净。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_screen_test.dart
git commit -m "feat(haptics): 日历手势震（单格滑块 + 长按进入与逐格）"
```

---

### Task 7: 「已调整」改胶囊 + 纳入定高模型

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Modify: `app/lib/features/calendar/info_card_metrics.dart`
- Modify: `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: 无

> ⚠️ **这两处必须一起改。** 信息卡是**定高**的（`_bottomCardHeight` → `measureBottomInfoCardHeight`），而胶囊比纯文字高。只改胶囊不改模型，信息卡会随内容长高、上面整个网格跟着跳 —— 那正是 `info_card_metrics.dart` 存在的全部理由。

- [ ] **Step 1: 写失败的用例**

在 `app/test/calendar_screen_test.dart` 追加：

```dart
  testWidgets('「已调整」是胶囊而不是裸文字，且信息卡高度不因它变化', (tester) async {
    final db = await _pumpCalendar(tester, 'day_night_rest_rest');
    final hBefore = tester
        .getSize(find.byKey(const Key('info-card-box')))
        .height;

    final classes = await db.select(db.shiftClassRows).get();
    final repo = AppRepository(db);
    final today = dateOnly(DateTime.now());
    await repo.setDayOverrides([today], classId: classes.first.id);
    await tester.pumpAndSettle();

    // 标记还在，而且**它自己**就是一颗胶囊（不是裸 Text）。
    //
    // 注意 key 就挂在那个 Container 上，所以要用 `tester.widget<Container>` 直接
    // 看它自己 —— `find.ancestor(of: marker, …)` 找的是它的**祖先**，不含它本身，
    // 那样写会恒为空、用例假失败。
    final marker = find.byKey(const Key('info-card-adjusted'));
    expect(marker, findsOneWidget);
    final box = tester.widget<Container>(marker);
    final deco = box.decoration as BoxDecoration?;
    expect(deco?.borderRadius, isNotNull,
        reason: '「已调整」要与同一行另外两个徽章一样是胶囊');
    expect(deco?.border, isNotNull, reason: '信息胶囊是「淡染底 + 同色描边」两件套');

    if (hBefore > 0) {
      expect(
        tester.getSize(find.byKey(const Key('info-card-box'))).height,
        hBefore,
        reason: '定高契约：有标记与没标记，卡片高度必须一样',
      );
    }

    await _disposeCalendar(tester);
  });
```

> ⚠️ 这个用例**故意写成容错的**（`if (hBefore > 0)`）：`info-card-box` 在测试环境里未必量得到高度。若那条高度断言恒不成立，**把它删掉并在报告里说明**，不要留一条永远为真的 `expect` —— 上一轮已经有两次因为「不可能失败的断言」被打回。

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/calendar_screen_test.dart
```

期望：新用例失败（「已调整」目前是裸 `Text`，没有胶囊容器）。

- [ ] **Step 3: 实现 —— 胶囊**

`calendar_screen.dart` 里现在是这样（约 `:1500-1511`）：

```dart
                  if (schedule.dayOverrides
                      .containsKey(dayNumber(_selected)))
                    Padding(
                      padding:
                          const EdgeInsets.only(left: AppTokens.spaceSm),
                      child: Text(
                        L10n.adjusted,
                        key: const Key('info-card-adjusted'),
                        style: AppTokens.microStrong.copyWith(
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
```

换成**同一行那个「N 项待办」徽章的容器配方**（`_todoHintBadge`，约 `:966-992`：14% 淡染底 + 45% 描边 + `radiusL` + `inkFor` 文字），去掉图标：

```dart
                  if (schedule.dayOverrides
                      .containsKey(dayNumber(_selected)))
                    Padding(
                      padding:
                          const EdgeInsets.only(left: AppTokens.spaceSm),
                      child: Container(
                        key: const Key('info-card-adjusted'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.spaceSm,
                            vertical: AppTokens.padChipV),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.14),
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusL),
                          border: Border.all(
                              color: primary.withValues(alpha: 0.45)),
                        ),
                        child: Text(
                          L10n.adjusted,
                          style: AppTokens.microStrong.copyWith(
                              color: AppTokens.inkFor(
                                  primary,
                                  Color.alphaBlend(
                                      primary.withValues(alpha: 0.14),
                                      Theme.of(context)
                                          .colorScheme
                                          .surface))),
                        ),
                      ),
                    ),
```

（`primary` 若该作用域没有现成变量，用 `Theme.of(context).colorScheme.primary`。`_todoHintBadge` 就在同一个文件里，**照它的写法抄**，不要自己配。）

- [ ] **Step 4: 实现 —— 定高模型**

`info_card_metrics.dart`：

1. 照 `const double _shiftDot = 12;` 的样子加一个标记的高度贡献常量。胶囊高 = `padChipV × 2 + 描边 × 2 + microStrong 行高`。**不要手算这个数** —— 用同文件里 `_todoHintH(measure)` 的做法（它就是用 `measure` 真量一个同款胶囊），照它写一个 `_adjustedBadgeH(measure)`。
2. 把标记纳入 `shiftRowH` 的取大：现在是

```dart
  final shiftRowH = [shiftLineH, noShiftH, blankH, _shiftDot]
      .reduce((a, b) => a > b ? a : b);
```

把 `_adjustedBadgeH(measure)` 加进那个列表。

3. **是否要按「本月有没有被调整的日子」决定要不要预留** —— 照 `hasTodoHint` 那条路做（[info_card_metrics.dart:106-107](app/lib/features/calendar/info_card_metrics.dart:106) 与 `calendar_screen.dart` 的 `_monthHasPendingTodos`）：加一个 `bool hasOverrideHint` 参数，由调用方算出「本月是否有被按天调整的日子」（`schedule.dayOverrides.keys` 里有没有属于本月的 `dayNumber`），只在有时才把它算进取大。**按月而不是按天** —— 按天算的话点一天卡片高度就变一次。

   对应地，`calendar_screen.dart` 的 `_bottomCardHeight` 要把这个新的 key 与参数一起接上（它有一份缓存键，见 `_cardHeightKey` —— **新参数必须进那个键**，否则缓存会拿旧值）。

- [ ] **Step 5: 跑测试确认通过**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/calendar_screen_test.dart && flutter test && flutter analyze
```

期望：新用例 PASS；**既有的定高/布局用例不回归**（尤其 `app_layout_test.dart` 与 `calendar_screen_test.dart` 里量高度的那些）；analyze 干净。

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/lib/features/calendar/info_card_metrics.dart app/test/calendar_screen_test.dart
git commit -m "fix(calendar): 「已调整」改用同一行的胶囊配方，并纳入定高模型"
```

---

### Task 8: 其余三处设计语言对齐

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Modify: `app/lib/features/calendar/shift_override_picker.dart`
- Modify: `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: 无

- [ ] **Step 1: 写用例（同一处信息卡的点击反馈）**

在 `app/test/calendar_screen_test.dart` 追加：

```dart
  testWidgets('信息卡那行用玻璃按压缩放，不引入 Material 水波纹', (tester) async {
    await _pumpCalendar(tester, 'day_night_rest_rest');

    final entry = find.byKey(const Key('info-card-shift-entry'));
    expect(entry, findsOneWidget);

    // 这一行的按压反馈必须是 GlassPressable（Q 弹缩放），不能是裸 InkWell。
    //
    // `info-card-shift-entry` 这个 key 就挂在 GlassPressable 上，所以不能写
    // `find.descendant(of: entry, matching: find.byType(GlassPressable))` ——
    // descendant 只找**后代**，不含自身，那样写恒为空。
    expect(
      find.descendant(of: entry, matching: find.byType(InkWell)),
      findsNothing,
      reason: '全 app 的按压反馈是玻璃缩放；水波纹只该出现在弹层的 ListTile 里',
    );
    expect(tester.widget(entry), isA<GlassPressable>());

    // 点击必须照旧能打开选择层
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.text(L10n.restoreRotation), findsNothing,
        reason: '今天没被调整过，所以不该有「恢复轮转」');
    expect(find.byType(ListTile), findsWidgets, reason: '选择层该弹出来了');

    await _disposeCalendar(tester);
  });
```

> **实施时核实**：`GlassPressable` 与 `InkWell` 的真实 import 是否已在测试文件里（没有就补）。第二条断言（点开选择层）是这条用例的**非空性保障** —— 只断言「没有 InkWell」的话，一个把整行删掉的改动也能让它绿。

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/calendar_screen_test.dart
```

期望：新用例在第一条 `InkWell` 断言处失败（现在正是 `InkWell`）。

- [ ] **Step 3: 实现 —— 去掉水波纹**

`calendar_screen.dart` 约 `:1453-1457` 现在是：

```dart
            key: const Key('info-card-shift-entry'),
            child: InkWell(
              onTap: schedule.classes.isEmpty
                  ? null
                  : () => adjustDays(_selected, _selected),
```

把 `InkWell` 换成**只拿点击、不加波纹**的手势层，并放进 `GlassPressable` 里拿缩放反馈：

```dart
            key: const Key('info-card-shift-entry'),
            child: GlassPressable(
              child: GestureDetector(
                // `opaque`：行内元素之间有空隙，不加这个，点在空隙上不响应。
                behavior: HitTestBehavior.opaque,
                onTap: schedule.classes.isEmpty
                    ? null
                    : () => adjustDays(_selected, _selected),
```

并**闭合括号**：原来的 `InkWell(` 多出来的那一层要在 `Row` 结束后补上 `)`（改完跑 `flutter analyze` 看括号对不对）。

> `GlassPressable` 已经在文件顶部 import 了。这一改的依据：全 app 的按压反馈是它的 Q 弹缩放，没有任何玻璃面带过 Material 水波纹（spec §7.2）。

- [ ] **Step 4: 实现 —— 范围底色与圆点注释**

**4a. 范围底色 18% → 14%** —— `calendar_screen.dart` 约 `:1056`：

```dart
                    color: primary.withValues(alpha: 0.18),
```

改成 `0.14`。旁边补一句注释说明取的是全 app 的淡染约定值。

**4b. 圆点尺寸的理由写进注释** —— `shift_override_picker.dart` 的 `_ClassDot` 类文档注释，现在写的是「**不是**信息卡上那个 12dp 的小色点，两者尺寸不同是有意的」。**把「为什么」补全**：

```dart
/// 班次色的圆点，落在 `ListTile.leading` 位。
///
/// 尺寸取 `iconMd`（20dp），**有意不与信息卡里那个 12dp 的色点统一**：
/// - 这里它在 `ListTile.leading`，对面那个打勾（`trailing`）也是 20dp，缩到 12
///   会和它失衡；
/// - 信息卡里那个 12dp 是行内元素，本来就该小一档。
///
/// 两个尺寸都在设计令牌上，不是随手写的数 —— 这是**有据可查的决定**，
/// 不是遗漏（spec §7.4）。
```

- [ ] **Step 5: 跑测试确认通过**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/calendar_screen_test.dart && flutter test test/design_tokens_test.dart && flutter test && flutter analyze
```

期望：新用例 PASS（`InkWell` 没了、`GlassPressable` 在、点击照旧能开选择层）；既有用例不回归；`design_tokens_test` 仍绿；analyze 干净。

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/lib/features/calendar/shift_override_picker.dart app/test/calendar_screen_test.dart
git commit -m "fix(calendar): 去信息卡水波纹、范围底色回到 14%、写明圆点尺寸的理由"
```

---

### Task 9: 渲染工装补屏单

**Files:**
- Modify: `app/tool/visual/visual_screens.dart`
- Modify: `app/tool/visual/visual_harness.dart`（若新屏需要预置一条按天覆盖）

**Interfaces:**
- Consumes: 前八个任务的全部 UI 改动
- Produces: 无

> **这是本轮的防复发措施。** v0.8.1 那四处设计语言偏差之所以三道评审都没拦住，根因是**新界面从没进过屏单，没有人真正「看过」它** —— 守门测试只查字面量，查不出「裸文字 vs 胶囊」。补上屏单，这类偏差下次会在出图时被眼睛看见。

- [ ] **Step 1: 先跑一次，看现在的图**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant && export FLUTTER_ROOT="$PWD/toolchain/flutter" PUB_CACHE="$PWD/toolchain/pub-cache" APPDATA="$PWD/toolchain/appdata" LOCALAPPDATA="$PWD/toolchain/localappdata" JAVA_HOME="$PWD/toolchain/jdk" && export PATH="$FLUTTER_ROOT/bin:$JAVA_HOME/bin:$PATH" && cd app && flutter test tool/visual/render_screens_test.dart
```

找到它出图的目录（看 `visual_harness.dart` 里的输出路径），确认现有的图能出、并记下产在哪儿。

- [ ] **Step 2: 加屏单条目**

`visual_screens.dart` 的 `visualScreens` 列表里追加（照现有条目的形状；`slug` 的数字前缀决定文件名顺序）：

1. **`07_calendar_adjusted`** —— 日历，且**今天**带按天覆盖（这样格子上有 4dp 圆点、信息卡有「已调整」胶囊）。它的 `build` 里先往 `db` 写一条覆盖再返回 `CalendarScreen()`：照 `_pumpCalendar` 夹具的做法（`AppRepository(db).saveSchedule(...)` 之后 `setDayOverrides([today], classId: ...)`）。
2. **`08_override_picker`** —— 「调整班次」选择层。**这一屏是弹层，不是页面**，需要一个只供工装使用的极薄包装：一个 `StatefulWidget`，在 `initState` 里 `WidgetsBinding.instance.addPostFrameCallback` 调 `showShiftOverridePicker(...)`，`build` 返回一个空的 `Scaffold`（让弹层浮在它上面）。判定条件与参数照 `calendar_screen.dart` 的 `adjustDays` 里那次调用。**这个包装只放在 `tool/visual/` 里，不要进 `lib/`。**
3. **`09_profile` 已有** —— 确认「触觉反馈」那一行出现在设置页的图里（现有 `07_profile` 或类似 slug 的条目会覆盖它，无需新增）。

> **实施时核实**：`visual_screens.dart` 里现有的 slug 命名与顺序（`00_home_shell` / `01_calendar` / …），新条目插在正确位置、**不要撞号**；以及 `_pumpCalendar` 用的模板 id 是 `day_night_rest_rest`（`four_crew_two_shift` 不存在）。

- [ ] **Step 3: 出图并**看图**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test tool/visual/render_screens_test.dart && flutter test tool/visual/contrast_audit_test.dart
```

期望：全过；出图目录里出现新屏。

**然后逐个打开新出的 PNG 看** —— 这是本步骤的实质内容，不是走过场：
- `07_calendar_adjusted`：圆点**看得见**吗？信息卡那个「已调整」胶囊与同一行的「今天」徽章**看起来是一族**的吗？
- `08_override_picker`：选择层的行距、色点、打勾，与既有弹层（`04_template_picker` 那张）**放在一起像同一套东西**吗？

**把肉眼观察到的问题写进报告**，包括「看着没问题」这个结论本身。

- [ ] **Step 4: 提交**

```bash
git add app/tool/visual/visual_screens.dart app/tool/visual/visual_harness.dart
git commit -m "test(visual): 补上按天改班的屏单（日历标记、调整班次选择层）"
```

---

### Task 10: 版本号 `0.8.2+93` + 更新日志

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/core/app_info.dart`
- Modify: `app/lib/features/profile/app_dialogs.dart`

**Interfaces:**
- Consumes: 无
- Produces: 无

- [ ] **Step 1: 改两处版本号**

`app/pubspec.yaml` 顶部：`version: 0.8.2+93`
`app/lib/core/app_info.dart`：把 `const String appVersion = '0.8.1';` 改成 `'0.8.2'`（**保留 `const String` 这个形式**，文件里就是这个写法）。

两处必须同步 —— `app/test/app_info_test.dart` 盯着这条。

- [ ] **Step 2: 加更新日志条目**

`app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh` 与 `_changelogEn`：**prepend 新版本、删最旧一条、保持 10 条**。

本轮是**测试版**（末位 `Z = 2`，非 0），所以条目**只写自己这版改了什么、原样保留**，不做归纳（归纳是正式版的事）。

中文条目：

```
· 加了触觉反馈：切换开关、选中、删除确认时会轻微震动，长按拖选日子时还会逐格轻震一下。可在「我的 → 外观」里关掉
· 修好了几处界面对不齐：信息卡上「已调整」现在与同一行的徽章是同一款胶囊；信息卡那行按下去的反馈改回与全 app 一致的玻璃缩放（不再是水波纹）
```

英文条目照同样的信息量写。

- [ ] **Step 3: 跑测试**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter test test/app_info_test.dart && flutter test
```

期望：全绿；两个更新日志列表都恰好 10 条。

- [ ] **Step 4: 提交**

```bash
git add app/pubspec.yaml app/lib/core/app_info.dart app/lib/features/profile/app_dialogs.dart
git commit -m "chore(release): v0.8.2 版本号与更新日志"
```

---

### Task 11: 产品文档收尾

**Files:**
- Modify: `PRODUCT_SPEC.md`
- Modify: `README.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: 前面所有任务的最终形态
- Produces: 无

- [ ] **Step 1: `PRODUCT_SPEC.md`**

1. **§6 设计系统**一节：在「设计令牌（单一来源）」那条**旁边**加一条「触觉反馈」，说明：三档语义词汇表在 `core/haptics.dart`；挂动作不挂按压，普通点击一律不震；开关在「外观」；**除该文件外不许直接调 `HapticFeedback`，由守门测试盯着**。
2. **§2「我的 / 设置」**那节：设置项清单里补「触觉反馈」。
3. **抬头版本号**：`v0.8.1` → `v0.8.2`。

- [ ] **Step 2: `README.md`**

功能清单里补一条触觉反馈。**逐条对着当前实现核一遍** —— 这个文件有反复过时的前科（`AGENTS.md` 里记着）。

- [ ] **Step 3: `AGENTS.md`**

1. **`core/` 的文件地图**：加 `core/haptics.dart`（触觉词汇表）。
2. **「关键决策与坑」**加一条：**触觉挂动作不挂按压**；三档 `select` / `commit` / `modeEnter`；开关靠模块级 `hapticsDisabled`（同 `advancedMaterialDisabled` 那条路）；**除 `core/haptics.dart` 外任何文件不许出现 `HapticFeedback.`**，由 `test/haptics_guard_test.dart` 扫源码强制 —— 绕过的那一行不会受用户开关控制。
   **同一条里必须带上本轮得到的那条子规则**（它是设计里最容易犯的错，且已经真的犯过一次）：**共享组件已经自动震过的控件（`GlassSwitch` / `GlassSegment` / `GlassChoiceChip` / 四个选择器提交点），绝不能再在调用点补一次触觉** —— 那就是「一次操作震两下」，信息量反而归零。待办勾选那一处正是这么被裁掉的（spec §4.2 的「一条自我纠正」有完整推导）。**加任何一处触觉之前，先确认它不在那份名单里。**
3. 顺带记一句：**新界面一律补进 `tool/visual/visual_screens.dart` 的屏单**，理由写清楚（v0.8.1 的四处在设计语言上跑偏、三道评审都没拦住，根因是没人真正「看过」新界面）。
4. **版本史**那一行：`→ 0.8.1(+92) 测试版` 改成 `→ 0.8.1(+92) 测试版 → 0.8.2(+93) 测试版`。

- [ ] **Step 4: 全量验证**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app && flutter analyze && flutter test
```

期望：0 error / 0 warning；全绿。并核一遍文档里的数字与实际一致（测试条数、版本号）。

- [ ] **Step 5: 提交**

```bash
git add PRODUCT_SPEC.md README.md AGENTS.md
git commit -m "docs: 触觉反馈（v0.8.2）的产品规格、README 与项目记忆"
```

---

## Self-Review

**1. Spec 覆盖检查**

| Spec 章节 | 落在哪个任务 |
|---|---|
| §2 决策①②③ | 决策①=Task 4/5/6 的取舍与 Task 5 Step 1 的护栏用例；②=Task 3；③=Task 8 Step 4b |
| §3 词汇表三档 | Task 1 |
| §3 fire-and-forget 不 await | Task 1 Step 3 的 `_fire` |
| §3.1 模块级标志 | Task 3 Step 3a |
| §4.1 共享组件自震 | Task 4 |
| §4.1 滚轮不算提交 / Segment 只在真变了时震 | Task 4 Step 1 的第三条用例 + Step 3b/3d 的两处警告 |
| §4.2 提交点显式震 | Task 5 |
| §4.2「不要给闹钟单条开关再加一次」 | Task 5 开头的警告 |
| §4.3 日历手势三处 | Task 6 |
| §4.4 明确不震 | Task 5 Step 2 的「非危险不震」护栏（`secondary` + `primary`）+ Task 4/6 都只在判据内触发。**注**：主题 / 主色调 / 语言三段**不在** §4.4 内 —— 它们是 `GlassSegment`（§4.1），段翻转是状态改变，静默由 §4.1 覆盖；本表初版把它们算进 §4.4，那是一处与实际代码不符的错觉（最终评审发现，spec §4.4 已随之更正） |
| §5.1 状态与持久化 | Task 3 Step 3a |
| §5.2 设置页那一行 + 文案 | Task 3 Step 3b/3c |
| §6.1 源码扫描守门 | Task 2 |
| §6.2 词汇表完整性 | Task 1 Step 1 的第三条用例 |
| §6.3 行为测试四类 | 开关关掉=Task 1；开着会震=Task 1/4/5；长按两级=Task 6；滚轮不震=Task 4 Step 1 |
| §7.1 「已调整」胶囊 + 定高模型 | Task 7 |
| §7.2 去水波纹 | Task 8 Step 3 |
| §7.3 底色 18→14 | Task 8 Step 4a |
| §7.4 圆点保持 20dp + 写明理由 | Task 8 Step 4b |
| §9 渲染工装补屏单 | Task 9 |
| §9 四份文档收尾 | Task 10 + Task 11 |
| §10 七条风险 | 风险1=Task 5 警告；2/3/4=Task 1 的 `_fire` 与 Step 3 注释；5=Task 7 的 ⚠️；6/7=Global Constraints |

**缺口**：无。

**2. 占位符扫描**：Task 4、Task 5、Task 6、Task 7、Task 8、Task 9 各留了「实施时核实」的标注，都是构造函数签名、模板 id、行号一类**我未逐一核实**的东西。硬写会给出错的代码；标出来让实现者先 `grep` 一次更安全。除此之外每个步骤都有可执行的代码或命令。

**3. 类型一致性**：`Haptics.select()` / `commit()` / `modeEnter()` 三者均为 `static void`、无参 —— Task 1 定义，Task 4/5/6 消费，调用形式一致。`hapticsDisabled` 是顶层 `bool` —— Task 1 定义，Task 3 赋值，Task 1/4/5 的测试直接置它以验证开关。`blankNonCode(String)` 在 Task 2 抽出、同任务即消费。`AppSettings.hapticsEnabled` 在 Task 3 定义并消费。`hasOverrideHint` 在 Task 7 Step 4 内部一致（参数名与 `hasTodoHint` 并列，进 `_cardHeightKey`）。
