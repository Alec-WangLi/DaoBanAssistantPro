# 模板双语化与周期色条截断提示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让英文界面下从倒班方式模板新建的方案，从卡片到日历格子全链路不出现中文；并给周期色条加截断提示。

**Architecture:** 模板拆成两层 —— 语言无关的结构（`ShiftClassProto` + 周期/班组数据）与双语文案（`L10nText` 常量）。`ShiftTemplate` 从「数据类」变成「读取期视图」，持有 spec 并在 getter 里按当前 locale 解析出 `String` / `List<ShiftClass>`。这样 `shiftTemplates` 仍是**一次求值、身份稳定**的顶层列表（既有测试用 `same()` 比身份），而文案与班次名跟着语言走。

**Tech Stack:** Flutter / Dart，纯静态 i18n（`core/l10n.dart` 的 `L10n.locale` + `L10n.t(zh, en)`），flutter_test。

**Spec:** `docs/superpowers/specs/2026-09-12-shift-template-i18n-design.md`

## Global Constraints

- 目标版本 **`0.6.2+73`**（`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 同步；`+build` 是 Android versionCode，只能递增，不能重置）。
- 版本号 `X.Y` 由用户决定，AI 只能改末位 `Z` 与 `build`。
- 验收：`flutter analyze` **0 error / 0 warning**；`flutter test` **全绿**。
- 改 `app/lib/domain/` 下两个文件后必须保持**纯 Dart、无 Flutter 依赖**（可 `dart test`）。
- 中文界面的文案**逐字节不变**；不做存量数据迁移；不引入第三种语言。
- 更新日志（`app_dialogs.dart` 的 `_changelogZh` / `_changelogEn`）：prepend 新版本、删最旧条目、**保持 10 条**。
- **不得出现任何「参考 / 借鉴 / 对照 / 类似某 App」的表述**，不点名任何第三方应用。
- 所有命令的工作目录是 `app/`；Flutter 可执行文件是 `../toolchain/flutter/bin/flutter.bat`。

## 文件结构

| 文件 | 职责 | 本计划中的改动 |
|---|---|---|
| `app/lib/core/l10n.dart` | 全局静态 i18n。**新增**通用双语文案原语 `L10nText`；分组名映射由中文键改为语言无关键 | Task 1、2 |
| `app/lib/domain/shift_templates.dart` | 模板库。**重构**为「原型 + 双语文案 + 读取期视图」 | Task 1、2 |
| `app/lib/domain/shift_rotation.dart` | 排班领域模型。`defaultSchedule()` 改为按语言生成 | Task 3 |
| `app/lib/main.dart` | 启动流程。在 `runApp` 前把语言定下来，避免首启播种落中文 | Task 3 |
| `app/lib/features/calendar/shift_template_picker_screen.dart` | 选择页。搜索规则 + 色条省略标记 | Task 4 |
| `app/lib/features/profile/app_dialogs.dart` | 更新日志 | Task 5 |

**为什么不把班次角色名放进 `l10n.dart`**：`ShiftRole` 是领域类型，放 `domain/`；若 `core/l10n.dart` 反过来 import 它，就形成 core ↔ domain 循环依赖。角色名放 `shift_templates.dart`（它本来就依赖 `l10n.dart`），依赖方向保持单向。

---

### Task 1: 分组键改造

分组名现在是**中文当键**（`t.group == '12 小时制'`），显示层靠 `L10n.templateGroup` 映射。改成语言无关键（`'h12'`），让数据层不再持有任何界面文案。

**Files:**
- Modify: `app/lib/core/l10n.dart:243-256`（`templateGroup`）
- Modify: `app/lib/domain/shift_templates.dart:62-69`（`shiftTemplateGroups`）、各模板的 `group:` 字段、`ShiftTemplate.group` 字段名
- Modify: `app/lib/features/calendar/shift_template_picker_screen.dart:88`（`t.group == group`）
- Test: `app/test/shift_template_picker_test.dart`

**Interfaces:**
- Consumes: 无（本任务是起点）
- Produces: `ShiftTemplate.groupKey`（`String`，取值 `'h12' | 'h8' | 'h6' | 'duty' | 'office'`）；`L10n.templateGroup(String key) → String`

- [ ] **Step 1: 把既有测试改到新接口（红）**

`app/test/shift_template_picker_test.dart` 第 74-85 行的 `每个模板的 group 都在分组列表里` 改为用 `groupKey`：

```dart
  test('每个模板的 groupKey 都在分组列表里，不会静默消失', () {
    // 选择页按 shiftTemplateGroups 分组渲染：键写错会让该模板
    // 从「选择你的倒班方式」页上无声消失。
    for (final t in shiftTemplates) {
      expect(shiftTemplateGroups, contains(t.groupKey),
          reason: '模板 ${t.id} 的 groupKey「${t.groupKey}」不在分组列表里，会被静默丢弃');
    }
    for (final g in shiftTemplateGroups) {
      expect(shiftTemplates.any((t) => t.groupKey == g), isTrue,
          reason: '分组「$g」没有任何模板，分组标题永远不会出现');
    }
  });
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `../toolchain/flutter/bin/flutter.bat test test/shift_template_picker_test.dart`
Expected: 编译失败，`The getter 'groupKey' isn't defined for the type 'ShiftTemplate'`

- [ ] **Step 3: 新增分组键的显示名测试（红）**

在 `app/test/shift_template_picker_test.dart` 末尾追加：

```dart
  test('分组键是语言无关键，且中英都有显示名', () {
    // 键本身不该被当成显示名露出去 —— 英文界面上冒出一个「h12」，
    // 中文界面上冒出原样的键，都是同一类缺陷。
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);

    for (final locale in ['zh', 'en']) {
      L10n.locale = locale;
      for (final key in shiftTemplateGroups) {
        expect(L10n.templateGroup(key), isNot(key),
            reason: '分组键「$key」在 $locale 下没有显示名，会原样露出');
        expect(L10n.templateGroup(key).trim(), isNotEmpty,
            reason: '分组键「$key」在 $locale 下显示名为空');
      }
    }
  });
```

- [ ] **Step 4: 改 `l10n.dart` 的 `templateGroup`**

把 `app/lib/core/l10n.dart` 第 243-256 行整段替换为：

```dart
  /// 倒班方式列表的分组标题。
  ///
  /// 分组在数据层是**语言无关键**（`ShiftTemplate.groupKey`），这里映射到
  /// 当前语言的显示名。键与显示名都必须与 `shiftTemplateGroups` 对得上 ——
  /// 对不上的键会走 `_ => key` 原样露出，英文界面上就会冒出一个 `h12`。
  ///
  /// 模板自身的标题/副标题**不在这里** —— 那是内容文案，跟着模板数据走，
  /// 见 `domain/shift_templates.dart`。
  static String templateGroup(String key) => switch (key) {
        'h12' => t('12 小时制', '12-hour shifts'),
        'h8' => t('8 小时制', '8-hour shifts'),
        'h6' => t('6 小时制', '6-hour shifts'),
        'duty' => t('值班制', '24-hour duty'),
        'office' => t('常白', 'Day shift only'),
        _ => key,
      };
```

- [ ] **Step 5: 改 `shift_templates.dart` 的分组**

把 `app/lib/domain/shift_templates.dart` 第 62-69 行替换为：

```dart
/// 界面上分组的显示顺序（**语言无关键**，显示名走 `L10n.templateGroup`）。
///
/// 每个模板的 `groupKey` 必须落在这个列表里，否则它不会出现在选择页上，
/// 而且是静默消失 —— 由 `shift_template_picker_test.dart` 守着。
const shiftTemplateGroups = <String>[
  'h12',
  'h8',
  'h6',
  'duty',
  'office',
];
```

字段重命名与取值替换（该文件里）：

1. 类定义 `final String group;` → `final String groupKey;`，构造参数 `required this.group` → `required this.groupKey`，doc 注释改为：

```dart
  /// 分组键（语言无关）：'h12' / 'h8' / 'h6' / 'duty' / 'office'。
  final String groupKey;
```

2. 19 处 `group: '…'` 依次替换（**只改这一行，不动其它字段**）：

| 模板 id | 原 `group:` | 新 `group:` |
|---|---|---|
| `day_night_rest_rest` | `'12 小时制'` | `'h12'` |
| `white_white_night_night_rest_rest` | `'12 小时制'` | `'h12'` |
| `white_white_rest_rest_night_night_rest_rest` | `'12 小时制'` | `'h12'` |
| `two_shift_weekly` | `'12 小时制'` | `'h12'` |
| `dupont` | `'12 小时制'` | `'h12'` |
| `four_crew_three_shift` | `'8 小时制'` | `'h8'` |
| `five_crew_three_shift` | `'8 小时制'` | `'h8'` |
| `six_crew_three_shift` | `'8 小时制'` | `'h8'` |
| `five_crew_four_shift` | `'6 小时制'` | `'h6'` |
| `six_crew_four_shift` | `'6 小时制'` | `'h6'` |
| `duty_24_24` / `duty_24_48` / `duty_24_72` | `'值班制'` | `'duty'` |
| `standard_week` / `big_small_week` / `work_1_rest_1` / `work_2_rest_2` / `work_4_rest_2` / `work_6_rest_1` | `'常白'` | `'office'` |

- [ ] **Step 6: 改选择页分组匹配**

`app/lib/features/calendar/shift_template_picker_screen.dart` 第 88 行：

```dart
      final inGroup = matched.where((t) => t.groupKey == group).toList();
```

- [ ] **Step 7: 跑测试确认全绿**

Run: `../toolchain/flutter/bin/flutter.bat test test/shift_template_picker_test.dart test/shift_templates_test.dart`
Expected: PASS（`每个模板的 groupKey 都在分组列表里`、`分组键是语言无关键`、`每个分组标题都有英文映射`、`英文界面：分组标题跟着语言走` 四条都过）

- [ ] **Step 8: 提交**

```bash
git add app/lib/core/l10n.dart app/lib/domain/shift_templates.dart app/lib/features/calendar/shift_template_picker_screen.dart app/test/shift_template_picker_test.dart
git commit -m "refactor(templates): 分组名改用语言无关键，不再拿中文当键"
```

---

### Task 2: 模板双层重构（原型 + 双语文案）

本任务把模板的数据层拆开。**中文界面的文案与结构必须逐字节不变**，所以先落一条基线测试，再重构。

**Files:**
- Modify: `app/lib/core/l10n.dart`（新增 `L10nText`）
- Modify: `app/lib/domain/shift_templates.dart`（整体重构）
- Test: `app/test/shift_templates_test.dart`（新增基线 + 双语断言）

**Interfaces:**
- Consumes: Task 1 的 `ShiftTemplate.groupKey`
- Produces:
  - `L10nText(String zh, String en)`，getter `String value` 按 `L10n.isEn` 取值
  - `enum ShiftRole { day, night, morning, afternoon, evening, duty, off, rest }`
  - `ShiftClassProto({required ShiftRole role, int? startMinute, int? endMinute, bool isRest, required int color, bool alarmEnabled, int? alarmMinute}).toClass() → ShiftClass`
  - `ShiftTemplateSpec(spec 级数据)`
  - `ShiftTemplate`（视图）：`id` / `groupKey` / `title` / `subtitle` / `aliases` / `classes` / `cycle` / `cycleLength` / `teamCount` / `teamOffsets` / `workingTeamsPerDay`
  - `shiftTemplates`（`List<ShiftTemplate>`，顶层 `final`，身份稳定）、`findTemplate(String id) → ShiftTemplate?`

- [ ] **Step 1: 先把中文基线测试写下来（红）**

在 `app/test/shift_templates_test.dart` 里追加。**这 38 条中文串是从当前源码逐条抄下来的**，重构后必须一条不差 —— 它是「中文界面零回归」的唯一凭据：

```dart
/// 中文文案基线：重构前的实际取值，逐条抄自源码。
///
/// 模板双层化会重排数据，但用户看到的中文一个字都不该变；这张表是
/// 唯一能证明这件事的东西 —— 结构字段由「每个模板结构自洽」那条守着。
const _zhBaseline = <String, (String, String)>{
  'day_night_rest_rest': ('上一天白班、一天夜班，然后休两天', '白夜休休 · 四班两倒'),
  'white_white_night_night_rest_rest': ('白班两天、夜班两天，然后休两天', '白白夜夜休休 · 三班两倒'),
  'white_white_rest_rest_night_night_rest_rest':
      ('上两天白班休两天，再上两天夜班休两天', '白白休休夜夜休休'),
  'two_shift_weekly': ('白班、夜班各上一整周，每周倒一次', '上 12 休 12 · 两班倒'),
  'dupont': ('四夜三休、三白一休、三夜三休、四白，再连休七天', 'DuPont · 28 天周期'),
  'four_crew_three_shift': ('早班两天、中班两天、夜班两天，然后休两天', '四班三倒 · 四班三运转'),
  'five_crew_three_shift': ('早班、中班、夜班各一天，然后休两天', '五班三倒'),
  'six_crew_three_shift': ('上一天班休两天，早中夜轮着来', '六班三倒'),
  'five_crew_four_shift': ('早中晚夜各一天，然后休一天', '五班四倒'),
  'six_crew_four_shift': ('早中晚夜各一天，然后休两天', '六班四倒'),
  'duty_24_24': ('上 24 小时，休 24 小时', '上 24 休 24'),
  'duty_24_48': ('上 24 小时，休 48 小时', '上 24 休 48'),
  'duty_24_72': ('上 24 小时，休 72 小时', '上 24 休 72'),
  'standard_week': ('周一到周五上班，周末休息', '长白班 · 双休'),
  'big_small_week': ('这周休一天，下周休两天', '大小周'),
  'work_1_rest_1': ('上一天休一天', '做一休一'),
  'work_2_rest_2': ('上两天休两天', '做二休二'),
  'work_4_rest_2': ('上四天休两天', '做四休二'),
  'work_6_rest_1': ('上六天休一天', '做六休一'),
};

/// 中文班次名与简称基线：按模板 id → 「角色名/简称」序列。
const _zhClassBaseline = <String, List<String>>{
  'day_night_rest_rest': ['白班/白', '夜班/夜', '休班/休'],
  'white_white_night_night_rest_rest': ['白班/白', '夜班/夜', '休班/休'],
  'white_white_rest_rest_night_night_rest_rest': ['白班/白', '夜班/夜', '休班/休'],
  'two_shift_weekly': ['白班/白', '夜班/夜'],
  'dupont': ['白班/白', '夜班/夜', '休班/休'],
  'four_crew_three_shift': ['早班/早', '中班/中', '夜班/夜', '休班/休'],
  'five_crew_three_shift': ['早班/早', '中班/中', '夜班/夜', '休班/休'],
  'six_crew_three_shift': ['早班/早', '中班/中', '夜班/夜', '休班/休'],
  'five_crew_four_shift': ['早班/早', '中班/中', '晚班/晚', '夜班/夜', '休班/休'],
  'six_crew_four_shift': ['早班/早', '中班/中', '晚班/晚', '夜班/夜', '休班/休'],
  'duty_24_24': ['值班/值', '休息/休'],
  'duty_24_48': ['值班/值', '休息/休'],
  'duty_24_72': ['值班/值', '休息/休'],
  'standard_week': ['白班/白', '休息/休'],
  'big_small_week': ['白班/白', '休息/休'],
  'work_1_rest_1': ['白班/白', '休班/休'],
  'work_2_rest_2': ['白班/白', '休班/休'],
  'work_4_rest_2': ['白班/白', '休班/休'],
  'work_6_rest_1': ['白班/白', '休息/休'],
};

/// 中英之外的表意文字 / 中文标点 / 全角符号。英文文案里许可 `·` 与 `–`。
final _cjk = RegExp(r'[\u3000-\u303F\u4E00-\u9FFF\uFF00-\uFFEF]');
```

再接两条测试：

```dart
  test('中文文案与班次名零回归（基线）', () {
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);
    L10n.locale = 'zh';

    expect(_zhBaseline.length, shiftTemplates.length);
    expect(_zhClassBaseline.length, shiftTemplates.length);

    for (final t in shiftTemplates) {
      final want = _zhBaseline[t.id]!;
      expect(t.title, want.$1, reason: '模板 ${t.id} 的中文主标题变了');
      expect(t.subtitle, want.$2, reason: '模板 ${t.id} 的中文副标题变了');
      expect(
        t.classes.map((c) => '${c.name}/${c.abbr}').toList(),
        _zhClassBaseline[t.id],
        reason: '模板 ${t.id} 的中文班次名或简称变了',
      );
    }
  });

  test('英文文案与班次名不含中文', () {
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);
    L10n.locale = 'en';

    for (final t in shiftTemplates) {
      final why = '模板 ${t.id}';
      expect(_cjk.hasMatch(t.title), isFalse, reason: '$why 英文主标题含中文：${t.title}');
      expect(_cjk.hasMatch(t.subtitle), isFalse, reason: '$why 英文副标题含中文：${t.subtitle}');
      for (final c in t.classes) {
        expect(_cjk.hasMatch(c.name), isFalse, reason: '$why 英文班次名含中文：${c.name}');
        expect(_cjk.hasMatch(c.abbr!), isFalse, reason: '$why 英文简称含中文：${c.abbr}');
      }
    }
  });

  test('中英文案都非空，别名中英都有', () {
    for (final t in shiftTemplates) {
      expect(t.spec.title.zh.trim(), isNotEmpty, reason: '模板 ${t.id} 中文主标题为空');
      expect(t.spec.title.en.trim(), isNotEmpty, reason: '模板 ${t.id} 英文主标题为空');
      expect(t.spec.subtitle.zh.trim(), isNotEmpty, reason: '模板 ${t.id} 中文副标题为空');
      expect(t.spec.subtitle.en.trim(), isNotEmpty, reason: '模板 ${t.id} 英文副标题为空');
      expect(t.aliases, isNotEmpty, reason: '模板 ${t.id} 没有搜索别名');
    }
  });
```

在文件顶部补 import：

```dart
import 'package:shiftassistantpro/core/l10n.dart';
```

- [ ] **Step 2: 跑测试确认失败**

Run: `../toolchain/flutter/bin/flutter.bat test test/shift_templates_test.dart`
Expected: 编译失败 —— `The getter 'spec' isn't defined for the type 'ShiftTemplate'`（英文断言与 `spec.zh` 都还没有实现）

- [ ] **Step 3: 在 `l10n.dart` 加 `L10nText`**

在 `app/lib/core/l10n.dart` 的 `L10n` 类**之前**插入：

```dart
/// 一段双语文案的持有者。
///
/// 用在**数据层需要持有文案**的地方（倒班方式模板）：模板是编译期常量，
/// 定义时不能调 `L10n.t`，只能先把两种语言都存下来、读取时再按当前语言取。
///
/// 英文缺省时**不回退中文** —— 悄悄回退会让漏翻在英文界面上伪装成正常
/// 内容，而缺失本该被测试抓出来。
class L10nText {
  const L10nText(this.zh, this.en);

  final String zh;
  final String en;

  String get value => L10n.isEn ? en : zh;
}
```

- [ ] **Step 4: 重写 `shift_templates.dart`**

整文件替换为下面内容（**19 条模板的结构字段与 Task 1 之后完全一致，只改文案的持有方式**）：

````dart
// 常见倒班方式模板 —— 纯 Dart 常量数据，无 Flutter 依赖，不入库。
//
// 模板只是一份「配方」：选中后生成的就是一个普通排班方案，
// 用户可以随意改，数据库里没有「模板」这个概念。
//
// 周期结构（几天一循环、每天几个班、几个班组错开）是模板要负责摆对的；
// 具体到几点几分各厂差异很大，这里只填常见值，用户可改。
//
// **两层结构**：`ShiftTemplateSpec` 是语言无关的结构与双语文案，
// `ShiftTemplate` 是读取期视图，按当前语言解析出 `String` 与 `ShiftClass`。
// 之所以要分这两层：班次名与简称会被**写进数据库**（方案建成后归用户），
// 必须在建的时候就是用户的语言；而 `shiftTemplates` 又必须是一次求值、
// 身份稳定的顶层列表（测试用 `same()` 比身份）。

import '../core/l10n.dart';
import 'shift_rotation.dart';

/// 班次在模板中的语义角色。
///
/// 名称与简称按当前语言生成；时间、颜色、闹钟、是否休息仍由原型自带。
///
/// 英文简称取**单字母**：日历格子宽度是按 1~2 个汉字设计的。
/// 「中班」译作 Afternoon（A）而不是 Mid —— 后者首字母 M 会与早班撞车。
enum ShiftRole { day, night, morning, afternoon, evening, duty, off, rest }

const _roleName = <ShiftRole, L10nText>{
  ShiftRole.day: L10nText('白班', 'Day shift'),
  ShiftRole.night: L10nText('夜班', 'Night shift'),
  ShiftRole.morning: L10nText('早班', 'Morning shift'),
  ShiftRole.afternoon: L10nText('中班', 'Afternoon shift'),
  ShiftRole.evening: L10nText('晚班', 'Evening shift'),
  ShiftRole.duty: L10nText('值班', 'Duty'),
  ShiftRole.off: L10nText('休班', 'Off'),
  ShiftRole.rest: L10nText('休息', 'Rest'),
};

const _roleAbbr = <ShiftRole, L10nText>{
  ShiftRole.day: L10nText('白', 'D'),
  ShiftRole.night: L10nText('夜', 'N'),
  ShiftRole.morning: L10nText('早', 'M'),
  ShiftRole.afternoon: L10nText('中', 'A'),
  ShiftRole.evening: L10nText('晚', 'E'),
  ShiftRole.duty: L10nText('值', 'D'),
  ShiftRole.off: L10nText('休', 'O'),
  ShiftRole.rest: L10nText('休', 'R'),
};

/// 班次原型：模板的结构部分。名称与简称由 [role] 按当前语言生成。
class ShiftClassProto {
  const ShiftClassProto({
    required this.role,
    this.startMinute,
    this.endMinute,
    this.isRest = false,
    required this.color,
    this.alarmEnabled = false,
    this.alarmMinute,
  });

  final ShiftRole role;
  final int? startMinute;
  final int? endMinute;
  final bool isRest;
  final int color;
  final bool alarmEnabled;
  final int? alarmMinute;

  ShiftClass toClass() => ShiftClass(
        name: _roleName[role]!.value,
        abbr: _roleAbbr[role]!.value,
        startMinute: startMinute,
        endMinute: endMinute,
        isRest: isRest,
        color: color,
        alarmEnabled: alarmEnabled,
        alarmMinute: alarmMinute,
      );
}

/// 模板的结构 + 双语文案（语言无关的常量）。
class ShiftTemplateSpec {
  const ShiftTemplateSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.aliases,
    required this.groupKey,
    required this.classes,
    required this.cycle,
    this.teamCount = 1,
    this.teamOffsets = const [0],
  });

  final String id;

  /// 人话主标题（给不懂术语的人看）。
  final L10nText title;

  /// 行话副标题（给会搜「四班三倒」的人看）。**同时是新建方案时的方案名**。
  final L10nText subtitle;

  /// 搜索词。中英关键词**都放** —— 搜索不该分语言，中文用户搜「四班三倒」、
  /// 英文用户搜 `4-crew` 都要能中。
  final List<String> aliases;

  /// 分组键（语言无关），显示名走 `L10n.templateGroup`。
  final String groupKey;

  /// 班次原型（结构 + 角色），名称在读取时按语言解析。
  final List<ShiftClassProto> classes;

  /// 周期序列（元素是 [classes] 的下标）。
  final List<int> cycle;

  final int teamCount;
  final List<int> teamOffsets;
}

/// 读取期的模板视图：把原型与双语文案解析成当前语言可直接使用的值。
///
/// 不持有语言状态 —— 所以 [shiftTemplates] 可以在顶层求值一次并长期复用，
/// 而它吐出来的文案始终跟着 `L10n.locale` 走。
class ShiftTemplate {
  const ShiftTemplate(this.spec);

  final ShiftTemplateSpec spec;

  String get id => spec.id;
  String get groupKey => spec.groupKey;
  String get title => spec.title.value;
  String get subtitle => spec.subtitle.value;
  List<String> get aliases => spec.aliases;
  List<ShiftClass> get classes =>
      spec.classes.map((p) => p.toClass()).toList(growable: false);
  List<int> get cycle => spec.cycle;
  int get cycleLength => cycle.length;
  int get teamCount => spec.teamCount;
  List<int> get teamOffsets => spec.teamOffsets;

  /// 每天同时在上班的班组数（轮转型模板应当每天都一样）。
  ///
  /// 读**原型**的 `isRest` —— 「是否休息」是结构字段，不走本地化；而且这个
  /// getter 每次 build 都被卡片调用，让它去分配一份临时的 [classes] 列表
  /// 是白白的开销。
  int get workingTeamsPerDay {
    var count = 0;
    for (var t = 0; t < spec.teamCount; t++) {
      final offset = t < spec.teamOffsets.length ? spec.teamOffsets[t] : t;
      final idx = offset % spec.cycle.length;
      if (idx < 0) continue;
      if (!spec.classes[spec.cycle[idx]].isRest) count++;
    }
    return count;
  }
}

/// 界面上分组的显示顺序（**语言无关键**，显示名走 `L10n.templateGroup`）。
///
/// 每个模板的 `groupKey` 必须落在这个列表里，否则它不会出现在选择页上，
/// 而且是静默消失 —— 由 `shift_template_picker_test.dart` 守着。
const shiftTemplateGroups = <String>[
  'h12',
  'h8',
  'h6',
  'duty',
  'office',
];

// ---------------------------------------------------------------------------
// 共用班次原型
// ---------------------------------------------------------------------------

// 12 小时制
const _d12 = ShiftClassProto(
    role: ShiftRole.day, startMinute: 8 * 60 + 30, endMinute: 20 * 60 + 30,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 7 * 60);
const _n12 = ShiftClassProto(
    role: ShiftRole.night, startMinute: 20 * 60 + 30, endMinute: 8 * 60 + 30,
    color: 0xFF7A5CFF, alarmEnabled: true, alarmMinute: 19 * 60);

// 8 小时制
const _e8 = ShiftClassProto(
    role: ShiftRole.morning, startMinute: 8 * 60, endMinute: 16 * 60,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 7 * 60);
const _m8 = ShiftClassProto(
    role: ShiftRole.afternoon, startMinute: 16 * 60, endMinute: 24 * 60,
    color: 0xFFFF9F0A, alarmEnabled: true, alarmMinute: 15 * 60);
const _n8 = ShiftClassProto(
    role: ShiftRole.night, startMinute: 0, endMinute: 8 * 60,
    color: 0xFF7A5CFF, alarmEnabled: true, alarmMinute: 23 * 60);

// 6 小时制
const _e6 = ShiftClassProto(
    role: ShiftRole.morning, startMinute: 6 * 60, endMinute: 12 * 60,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 5 * 60 + 30);
const _m6 = ShiftClassProto(
    role: ShiftRole.afternoon, startMinute: 12 * 60, endMinute: 18 * 60,
    color: 0xFFFF9F0A, alarmEnabled: true, alarmMinute: 11 * 60 + 30);
const _l6 = ShiftClassProto(
    role: ShiftRole.evening, startMinute: 18 * 60, endMinute: 24 * 60,
    color: 0xFF00C7BE, alarmEnabled: true, alarmMinute: 17 * 60 + 30);
const _n6 = ShiftClassProto(
    role: ShiftRole.night, startMinute: 0, endMinute: 6 * 60,
    color: 0xFF7A5CFF, alarmEnabled: true, alarmMinute: 23 * 60);

// 24 小时值班：08:00 → 次日 08:00（endMinute 跨过午夜继续累加）
const _duty = ShiftClassProto(
    role: ShiftRole.duty, startMinute: 8 * 60, endMinute: 32 * 60,
    color: 0xFFFF375F, alarmEnabled: true, alarmMinute: 7 * 60);

// 常白（与 12 小时制白班同名同色，仅时段不同 —— 故复用同一角色）
const _office = ShiftClassProto(
    role: ShiftRole.day, startMinute: 8 * 60 + 30, endMinute: 17 * 60 + 30,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 7 * 60 + 30);

// 休息
const _rest = ShiftClassProto(
    role: ShiftRole.off, isRest: true, color: 0xFF9AA0B4);
const _restGrey = ShiftClassProto(
    role: ShiftRole.rest, isRest: true, color: 0xFF5A5F73);

// ---------------------------------------------------------------------------
// 模板库
// ---------------------------------------------------------------------------

const List<ShiftTemplateSpec> shiftTemplateSpecs = [
  // -------- 12 小时制 --------
  ShiftTemplateSpec(
    id: 'day_night_rest_rest',
    title: L10nText('上一天白班、一天夜班，然后休两天', 'One day shift, one night shift, then two off'),
    subtitle: L10nText('白夜休休 · 四班两倒', 'Day-Night-Off-Off · 4-crew 2-shift'),
    aliases: ['白夜休休', '四班两倒', '4班2倒', '两班倒', 'day night off off', '4-crew', '2-shift'],
    groupKey: 'h12',
    classes: [_d12, _n12, _rest],
    cycle: [0, 1, 2, 2],
    teamCount: 4,
    teamOffsets: [0, 1, 2, 3],
  ),
  ShiftTemplateSpec(
    id: 'white_white_night_night_rest_rest',
    title: L10nText('白班两天、夜班两天，然后休两天', 'Two day shifts, two night shifts, then two off'),
    subtitle: L10nText('白白夜夜休休 · 三班两倒', '2 days, 2 nights, 2 off · 3-crew 2-shift'),
    aliases: ['白白夜夜休休', '三班两倒', '3班2倒', '2 day 2 night', '3-crew'],
    groupKey: 'h12',
    classes: [_d12, _n12, _rest],
    cycle: [0, 0, 1, 1, 2, 2],
    teamCount: 3,
    teamOffsets: [0, 2, 4],
  ),
  ShiftTemplateSpec(
    id: 'white_white_rest_rest_night_night_rest_rest',
    title: L10nText('上两天白班休两天，再上两天夜班休两天', 'Two days on, two off, then two nights on, two off'),
    subtitle: L10nText('白白休休夜夜休休', '2 day, 2 off, 2 night, 2 off'),
    aliases: ['白白休休夜夜休休', '四班两倒', '4-crew', '2 day 2 off'],
    groupKey: 'h12',
    classes: [_d12, _n12, _rest],
    cycle: [0, 0, 2, 2, 1, 1, 2, 2],
    teamCount: 4,
    teamOffsets: [0, 2, 4, 6],
  ),
  ShiftTemplateSpec(
    id: 'two_shift_weekly',
    title: L10nText('白班、夜班各上一整周，每周倒一次', 'A full week of days, then a full week of nights'),
    subtitle: L10nText('上 12 休 12 · 两班倒', '12 on, 12 off · 2-crew'),
    aliases: ['两班倒', '上12休12', '两班两倒', '一周一倒', '12 on 12 off', 'weekly rotation'],
    groupKey: 'h12',
    classes: [_d12, _n12],
    cycle: [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1],
    teamCount: 2,
    teamOffsets: [0, 7],
  ),
  ShiftTemplateSpec(
    id: 'dupont',
    title: L10nText('四夜三休、三白一休、三夜三休、四白，再连休七天',
        'DuPont rotation: 4 nights, 3 off, 3 days, 1 off, 3 nights, 3 off, 4 days, then 7 off'),
    subtitle: L10nText('DuPont · 28 天周期', 'DuPont · 28-day cycle'),
    aliases: ['dupont', '杜邦', '28天', '四班两倒', '28-day', '4-crew'],
    groupKey: 'h12',
    classes: [_d12, _n12, _rest],
    cycle: [
      1, 1, 1, 1, 2, 2, 2, 0, 0, 0, 2, 1, 1, 1,
      2, 2, 2, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2, 2,
    ],
    teamCount: 4,
    teamOffsets: [0, 7, 14, 21],
  ),

  // -------- 8 小时制 --------
  ShiftTemplateSpec(
    id: 'four_crew_three_shift',
    title: L10nText('早班两天、中班两天、夜班两天，然后休两天',
        'Two mornings, two afternoons, two nights, then two off'),
    subtitle: L10nText('四班三倒 · 四班三运转', '4-crew 3-shift'),
    aliases: ['四班三倒', '四班三运转', '早晚中', '8小时', '4-crew 3-shift', '8-hour'],
    groupKey: 'h8',
    classes: [_e8, _m8, _n8, _rest],
    cycle: [0, 0, 1, 1, 2, 2, 3, 3],
    teamCount: 4,
    teamOffsets: [0, 2, 4, 6],
  ),
  ShiftTemplateSpec(
    id: 'five_crew_three_shift',
    title: L10nText('早班、中班、夜班各一天，然后休两天', 'One morning, one afternoon, one night, then two off'),
    subtitle: L10nText('五班三倒', '5-crew 3-shift'),
    aliases: ['五班三倒', '5班3倒', '5-crew 3-shift', '8-hour'],
    groupKey: 'h8',
    classes: [_e8, _m8, _n8, _rest],
    cycle: [0, 1, 2, 3, 3],
    teamCount: 5,
    teamOffsets: [0, 1, 2, 3, 4],
  ),
  ShiftTemplateSpec(
    id: 'six_crew_three_shift',
    title: L10nText('上一天班休两天，早中夜轮着来', 'One shift on, two off — mornings, afternoons and nights in turn'),
    subtitle: L10nText('六班三倒', '6-crew 3-shift'),
    aliases: ['六班三倒', '6班3倒', '6-crew 3-shift', '8-hour'],
    groupKey: 'h8',
    classes: [_e8, _m8, _n8, _rest],
    cycle: [0, 3, 1, 3, 2, 3],
    teamCount: 6,
    teamOffsets: [0, 1, 2, 3, 4, 5],
  ),

  // -------- 6 小时制 --------
  ShiftTemplateSpec(
    id: 'five_crew_four_shift',
    title: L10nText('早中晚夜各一天，然后休一天', 'One morning, afternoon, evening and night each, then one off'),
    subtitle: L10nText('五班四倒', '5-crew 4-shift'),
    aliases: ['五班四倒', '5班4倒', '6小时', '5-crew 4-shift', '6-hour'],
    groupKey: 'h6',
    classes: [_e6, _m6, _l6, _n6, _rest],
    cycle: [0, 1, 2, 3, 4],
    teamCount: 5,
    teamOffsets: [0, 1, 2, 3, 4],
  ),
  ShiftTemplateSpec(
    id: 'six_crew_four_shift',
    title: L10nText('早中晚夜各一天，然后休两天', 'One morning, afternoon, evening and night each, then two off'),
    subtitle: L10nText('六班四倒', '6-crew 4-shift'),
    aliases: ['六班四倒', '6班4倒', '6-crew 4-shift', '6-hour'],
    groupKey: 'h6',
    classes: [_e6, _m6, _l6, _n6, _rest],
    cycle: [0, 1, 2, 3, 4, 4],
    teamCount: 6,
    teamOffsets: [0, 1, 2, 3, 4, 5],
  ),

  // -------- 值班制 --------
  ShiftTemplateSpec(
    id: 'duty_24_24',
    title: L10nText('上 24 小时，休 24 小时', '24 hours on, 24 hours off'),
    subtitle: L10nText('上 24 休 24', '24 on, 24 off'),
    aliases: ['上24休24', '24小时', '值班', '24 on 24 off', '24-hour duty'],
    groupKey: 'duty',
    classes: [_duty, _restGrey],
    cycle: [0, 1],
    teamCount: 2,
    teamOffsets: [0, 1],
  ),
  ShiftTemplateSpec(
    id: 'duty_24_48',
    title: L10nText('上 24 小时，休 48 小时', '24 hours on, 48 hours off'),
    subtitle: L10nText('上 24 休 48', '24 on, 48 off'),
    aliases: ['上24休48', '上1休2', '值班', '24 on 48 off', '1 on 2 off'],
    groupKey: 'duty',
    classes: [_duty, _restGrey],
    cycle: [0, 1, 1],
    teamCount: 3,
    teamOffsets: [0, 1, 2],
  ),
  ShiftTemplateSpec(
    id: 'duty_24_72',
    title: L10nText('上 24 小时，休 72 小时', '24 hours on, 72 hours off'),
    subtitle: L10nText('上 24 休 72', '24 on, 72 off'),
    aliases: ['上24休72', '上1休3', '值班', '24 on 72 off', '1 on 3 off'],
    groupKey: 'duty',
    classes: [_duty, _restGrey],
    cycle: [0, 1, 1, 1],
    teamCount: 4,
    teamOffsets: [0, 1, 2, 3],
  ),

  // -------- 常白 --------
  ShiftTemplateSpec(
    id: 'standard_week',
    title: L10nText('周一到周五上班，周末休息', 'Monday to Friday, weekends off'),
    subtitle: L10nText('长白班 · 双休', 'Standard week · two days off'),
    aliases: ['长白班', '行政班', '双休', '朝九晚五', '周末双休', 'weekdays', 'weekends off', '9 to 5'],
    groupKey: 'office',
    classes: [_office, _restGrey],
    cycle: [0, 0, 0, 0, 0, 1, 1],
  ),
  ShiftTemplateSpec(
    id: 'big_small_week',
    title: L10nText('这周休一天，下周休两天', 'One day off this week, two days off next'),
    subtitle: L10nText('大小周', 'Alternating weeks'),
    aliases: ['大小周', '大周小周', 'alternating weeks', 'big small week'],
    groupKey: 'office',
    classes: [_office, _restGrey],
    cycle: [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1],
  ),
  ShiftTemplateSpec(
    id: 'work_1_rest_1',
    title: L10nText('上一天休一天', 'One day on, one day off'),
    subtitle: L10nText('做一休一', '1 on, 1 off'),
    aliases: ['做一休一', '上一休一', '1 on 1 off'],
    groupKey: 'office',
    classes: [_d12, _rest],
    cycle: [0, 1],
  ),
  ShiftTemplateSpec(
    id: 'work_2_rest_2',
    title: L10nText('上两天休两天', 'Two days on, two days off'),
    subtitle: L10nText('做二休二', '2 on, 2 off'),
    aliases: ['做二休二', '上二休二', '2 on 2 off'],
    groupKey: 'office',
    classes: [_d12, _rest],
    cycle: [0, 0, 1, 1],
  ),
  ShiftTemplateSpec(
    id: 'work_4_rest_2',
    title: L10nText('上四天休两天', 'Four days on, two days off'),
    subtitle: L10nText('做四休二', '4 on, 2 off'),
    aliases: ['做四休二', '上四休二', '4 on 2 off'],
    groupKey: 'office',
    classes: [_d12, _rest],
    cycle: [0, 0, 0, 0, 1, 1],
  ),
  ShiftTemplateSpec(
    id: 'work_6_rest_1',
    title: L10nText('上六天休一天', 'Six days on, one day off'),
    subtitle: L10nText('做六休一', '6 on, 1 off'),
    aliases: ['做六休一', '上六休一', '单休', '6 on 1 off'],
    groupKey: 'office',
    classes: [_office, _restGrey],
    cycle: [0, 0, 0, 0, 0, 0, 1],
  ),
];

/// 模板列表：**一次求值、身份稳定**（测试用 `same()` 比较元素身份）。
///
/// 元素只持有 spec，不持有语言状态 —— 所以列表可以在顶层缓存，
/// 而 [ShiftTemplate.title] 之类的 getter 每次读取都跟着 `L10n.locale` 走。
final List<ShiftTemplate> shiftTemplates =
    shiftTemplateSpecs.map(ShiftTemplate.new).toList(growable: false);

ShiftTemplate? findTemplate(String id) {
  for (final t in shiftTemplates) {
    if (t.id == id) return t;
  }
  return null;
}
````

- [ ] **Step 5: 跑模板测试**

Run: `../toolchain/flutter/bin/flutter.bat test test/shift_templates_test.dart`
Expected: PASS（6 条：模板库非空、结构自洽、上班组数恒定、findTemplate、中文零回归基线、英文无中文、中英文案非空）

- [ ] **Step 6: 跑选择页测试，修掉写死的副标题，并补落库路径的语言断言**

Run: `../toolchain/flutter/bin/flutter.bat test test/shift_template_picker_test.dart`
Expected: 失败在 `expect(find.text('DuPont · 28 天周期'), findsNothing)` —— 因为源码里的字面量没有跟着本地化走，仍是可用的，但这是**脆的**。

先把该行改为引用数据：

```dart
      expect(find.text(findTemplate('dupont')!.subtitle), findsNothing);
```

再让记录用的测试替身把方案名与班次也记下来（**改 `_RecordingRepository`，第 17-42 行**）：加两个字段并在 `saveSchedule` 里赋值。

```dart
  int saveCalls = 0;
  int lastTeamCount = 0;
  List<String> lastTeamNames = const [];
  String lastScheduleName = '';
  List<ShiftClass> lastClasses = const [];
```

```dart
  @override
  Future<int> saveSchedule({
    int? scheduleId,
    required String name,
    required DateTime anchorDate,
    required List<ShiftClass> classes,
    required List<int> cycle,
    bool makeCurrent = true,
    int teamCount = 4,
    List<String> teamNames = const ['一班', '二班', '三班', '四班'],
    int ourTeamIndex = 0,
    List<int> teamOffsets = const [],
  }) async {
    saveCalls++;
    lastTeamCount = teamCount;
    lastTeamNames = List.of(teamNames);
    lastScheduleName = name;
    lastClasses = List.of(classes);
    return 1;
  }
```

最后追加这条测试 —— 它覆盖 spec §6 的「落库路径无中文」，也是本规格最初那个用户可见症状（英文用户建完方案，「排班管理」里躺着一条中文名）的直接回归测试：

```dart
  testWidgets('英文界面：从模板新建的方案名与班次名都不落中文进库', (tester) async {
    final prev = L10n.locale;
    addTearDown(() => L10n.locale = prev);
    L10n.locale = 'en';

    final raw = sqlite3.sqlite3.openInMemory();
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);
    final repo = _RecordingRepository(db);

    await tester.pumpWidget(ProviderScope(
      overrides: [appRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => createScheduleFromTemplatePicker(context, ref,
                    makeCurrent: false),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final dupont = findTemplate('dupont')!;
    await tester.enterText(find.byType(TextField), 'dupont');
    await tester.pumpAndSettle();
    await tester.tap(find.text(dupont.title));
    await tester.pumpAndSettle();

    // 中英之外的表意文字 / 中文标点 / 全角符号（`·`、`–` 不在其中）。
    // 走 RegExp 自己的 `\uXXXX` 转义，不写字面汉字 —— 免得这段被当成
    // 「该文件里本来就有中文」的噪音。
    final cjk = RegExp(r'[\u3000-\u303F\u4E00-\u9FFF\uFF00-\uFFEF]');

    expect(repo.saveCalls, 1);
    expect(repo.lastScheduleName, dupont.subtitle);
    expect(cjk.hasMatch(repo.lastScheduleName), isFalse,
        reason: '方案名落库时含中文：${repo.lastScheduleName}');
    expect(repo.lastClasses, isNotEmpty);
    for (final c in repo.lastClasses) {
      expect(cjk.hasMatch(c.name), isFalse, reason: '班次名落库时含中文：${c.name}');
      expect(cjk.hasMatch(c.abbr!), isFalse, reason: '简称落库时含中文：${c.abbr}');
    }
  });
```

再跑一次：Expected PASS。

- [ ] **Step 7: 跑全量测试**

Run: `../toolchain/flutter/bin/flutter.bat test`
Expected: 全绿（含 `calendar_screen_test.dart` 与 `schedule_editor_test.dart` —— 它们经 `findTemplate` / `t.title` 间接使用模板）

`calendar_screen_test.dart` 有两处与本改动擦肩，确认它们仍过：

- `_chipPattern = RegExp(r'^[一二三四五六七八九]班 [早中夜休值晚]$')` —— 匹配的是**中文**简称，而该文件在 `setUp` 里 `SharedPreferences.setMockInitialValues({})`（无 `language` 键）→ 语言是 `zh` → 简称仍是汉字，不变。
- 它用 `template.subtitle` 当方案名、`template.classes` 当班次 —— 同样走 zh，取值不变。

- [ ] **Step 8: 提交**

```bash
git add app/lib/core/l10n.dart app/lib/domain/shift_templates.dart app/test/shift_templates_test.dart app/test/shift_template_picker_test.dart
git commit -m "refactor(templates): 模板拆成结构原型与双语文案两层"
```

---

### Task 3: 默认方案双语化与首启落库竞态

`defaultSchedule()` 是「我自己排」、清空重置、编辑器从空白表切回普通表的共同输入，也是**首启播种**的输入。它现在硬编码中文。

**Files:**
- Modify: `app/lib/domain/shift_rotation.dart:213-250`（`defaultSchedule`）
- Modify: `app/lib/main.dart`（`runApp` 之前先定语言）
- Test: `app/test/seed_locale_test.dart`（新建）、`app/test/shift_rotation_test.dart`（加语言护栏）

**Interfaces:**
- Consumes: Task 2 的 `L10nText`／`L10n`
- Produces: 无新对外接口（`defaultSchedule()` 签名不变）

- [ ] **Step 1: 写失败测试**

新建 `app/test/seed_locale_test.dart`：

```dart
// app/test/seed_locale_test.dart
//
// 首启播种的语言必须跟着用户的语言走。`defaultSchedule()` 一旦按当前语言
// 生成，就暴露出一条竞态：`activeScheduleProvider` 落库时，语言可能还没从
// SharedPreferences 读回来，于是英文用户的第一套排班是中文的。
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_database.dart';
import 'package:shiftassistantpro/data/seed.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 中英之外的表意文字 / 中文标点 / 全角符号。
final _cjk = RegExp(r'[\u3000-\u303F\u4E00-\u9FFF\uFF00-\uFFEF]');

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  test('英文 locale 下 defaultSchedule() 不产出中文', () {
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);
    L10n.locale = 'en';

    final s = defaultSchedule();
    expect(_cjk.hasMatch(s.name), isFalse, reason: '方案名含中文：${s.name}');
    for (final n in s.teamNames) {
      expect(_cjk.hasMatch(n), isFalse, reason: '班组名含中文：$n');
    }
    for (final c in s.classes) {
      expect(_cjk.hasMatch(c.name), isFalse, reason: '班次名含中文：${c.name}');
      expect(_cjk.hasMatch(c.abbr!), isFalse, reason: '班次简称含中文：${c.abbr}');
    }
  });

  test('英文 locale 下首启播种写进库里的不是中文', () async {
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);
    L10n.locale = 'en';

    final raw = sqlite3.sqlite3.openInMemory();
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    await seedIfEmpty(db);

    final sched = (await db.select(db.shiftScheduleRows).get()).single;
    expect(_cjk.hasMatch(sched.name), isFalse, reason: '落库的方案名含中文：${sched.name}');
    expect(_cjk.hasMatch(sched.teamNames), isFalse,
        reason: '落库的班组名含中文：${sched.teamNames}');

    final classes = await db.select(db.shiftClassRows).get();
    expect(classes, isNotEmpty);
    for (final c in classes) {
      expect(_cjk.hasMatch(c.name), isFalse, reason: '落库的班次名含中文：${c.name}');
      expect(_cjk.hasMatch(c.abbr!), isFalse, reason: '落库的简称含中文：${c.abbr}');
    }
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `../toolchain/flutter/bin/flutter.bat test test/seed_locale_test.dart`
Expected: FAIL —— 两条都报「含中文：四班两倒 / 一班 / 白班 …」

- [ ] **Step 3: 改 `defaultSchedule()`**

`app/lib/domain/shift_rotation.dart` 第 213-250 行整段替换。文件顶部补 import：

```dart
import '../core/l10n.dart';
```

```dart
/// 默认「四班两倒」配置：白班 → 上夜班 → 下夜班 → 大休（4 天周期），4 个班组错开。
///
/// 名称与班次名按**当前语言**生成：返回值有三条落库/入界面路径 ——
/// `seedIfEmpty` 首启播种、「我自己排」进编辑器、编辑器从空白表切回普通表。
/// 在英文界面下，这三条路都不该产出中文。
ShiftSchedule defaultSchedule() {
  final anchor = DateTime.utc(2025, 1, 6); // 占位基准日（我们班组的第 1 天）
  return ShiftSchedule(
    name: L10n.t('四班两倒', '4-crew 2-shift'),
    anchorDate: anchor,
    teamCount: 4,
    teamNames: L10n.defaultTeamNames(4),
    ourTeamIndex: 0,
    teamOffsets: const [0, 1, 2, 3],
    cycle: const [0, 1, 2, 3],
    classes: [
      ShiftClass(
        name: L10n.t('白班', 'Day shift'),
        abbr: L10n.t('白', 'D'),
        startMinute: 8 * 60 + 30,
        endMinute: 20 * 60 + 30,
        color: 0xFF4C8DFF,
        alarmEnabled: true,
        alarmMinute: 7 * 60,
      ),
      ShiftClass(
        name: L10n.t('上夜班', 'Night shift'),
        abbr: L10n.t('夜', 'N'),
        startMinute: 20 * 60 + 30,
        endMinute: 8 * 60 + 30,
        color: 0xFF7A5CFF,
        alarmEnabled: true,
        alarmMinute: 19 * 60 + 30,
      ),
      ShiftClass(
        name: L10n.t('下夜班', 'Off after nights'),
        abbr: L10n.t('休', 'O'),
        isRest: true,
        color: 0xFF9AA0B4,
      ),
      ShiftClass(
        name: L10n.t('大休', 'Long rest'),
        abbr: L10n.t('休', 'R'),
        isRest: true,
        color: 0xFF5A5F73,
      ),
    ],
  );
}
```

注意 `ShiftSchedule` 的其它调用方（订阅流、闹钟）不受影响 —— 本任务只改这一个函数的函数体与它读语言的时机。

- [ ] **Step 4: 给既有的中文断言加上语言护栏**

`app/test/shift_rotation_test.dart` 里有 **9 处**断言 `defaultSchedule()` 的中文名（`'白班'` / `'上夜班'` / `'下夜班'` / `'大休'` 与 `teamNames == ['一班','二班','三班','四班']`）。它们现在能过，是因为 `L10n.locale` 的静态初值就是 `'zh'`。

**这些断言必须保持通过** —— 它们正是「中文界面零回归」在默认方案这条路径上的凭据。但它们目前**隐式**依赖默认语言，改起来看不出来。给该文件加一条显式护栏，让意图写在纸面上：

```dart
void main() {
  setUp(() {
    // 本文件断言的是 defaultSchedule() 的**中文**取值（它按当前语言生成），
    // 所以语言必须显式钉死 —— 别再让它隐式依赖 L10n.locale 的初值。
    L10n.locale = 'zh';
  });

  test('daysBetween 整日差', () {
    // …以下不变
```

并在文件顶部补 import：

```dart
import 'package:shiftassistantpro/core/l10n.dart';
```

- [ ] **Step 5: 跑测试**

Run: `../toolchain/flutter/bin/flutter.bat test test/seed_locale_test.dart test/shift_rotation_test.dart`
Expected: PASS。`shift_rotation_test.dart` 断言的是 `shiftOn` 结果与文案（zh 下不变），应保持通过。

- [ ] **Step 6: 关掉首启落库的竞态**

竞态是两条独立异步链赛跑：`AppSettingsNotifier` 读 SharedPreferences 的 `_load()`，与 `activeScheduleProvider` 里的 `seedIfEmpty()`。把语言读取提到 `runApp` **之前**，竞态就变成了确定的顺序 —— 播种最早也在首帧之后，那时语言早已就位。

**在 `main.dart` 里加这两件事**（放在 `AlarmService.init()` 之前 —— 它是 main 里第一处可能触及数据层或原生侧的动作）：

顶部补 import：

```dart
import 'package:shared_preferences/shared_preferences.dart';

import 'core/l10n.dart';
```

`main()` 体内、`await initializeDateFormatting('zh');` 之后插入：

```dart
  // 语言必须在**任何落库之前**定下来：首启播种（seedIfEmpty → defaultSchedule）
  // 会把方案名与班次名写进数据库，而这些文案是按当前语言生成的。若此时
  // L10n.locale 还是静态初值 'zh'，英文用户的第一套排班就是中文的。
  //
  // AppSettingsNotifier 稍后还会再读一次同一个键，两处取值一致，幂等。
  try {
    final sp = await SharedPreferences.getInstance();
    L10n.locale = sp.getString('language') ?? 'zh';
  } catch (_) {
    // 读取失败就用默认中文，与改动前行为一致
  }
```

**不改** `state/app_settings.dart` 与 `data/app_repository.dart` —— 不提 `ready`、不让数据层反向依赖 `state/`，少两个文件的改动与一条跨层依赖。

- [ ] **Step 7: 跑全量测试**

Run: `../toolchain/flutter/bin/flutter.bat test`
Expected: 全绿

- [ ] **Step 8: 提交**

```bash
git add app/lib/domain/shift_rotation.dart app/lib/main.dart app/test/seed_locale_test.dart app/test/shift_rotation_test.dart
git commit -m "fix(i18n): 默认排班按语言生成，并在落库前定下语言"
```

---

### Task 4: 选择页的搜索与色条省略标记

**Files:**
- Modify: `app/lib/features/calendar/shift_template_picker_screen.dart:43-50`（搜索）、`:119-140`（色条）
- Test: `app/test/shift_template_picker_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `ShiftTemplate.aliases` / `groupKey`
- Produces: `cycleStripPlan(ShiftTemplate t) → ({List<int> colors, bool truncated})`（顶层函数，供测试直接断言）

- [ ] **Step 1: 写失败测试**

在 `app/test/shift_template_picker_test.dart` 末尾追加：

```dart
  test('色条：周期不超过 14 天全画，无省略标记', () {
    final t = findTemplate('four_crew_three_shift')!; // 周期 8 天
    final plan = cycleStripPlan(t);
    expect(plan.truncated, isFalse);
    expect(plan.colors, hasLength(8));
  });

  test('色条：周期超过 14 天画 13 格 + 省略标记', () {
    // DuPont 是 28 天周期，原来只画前 14 个色块、剩下的静默消失。
    final t = findTemplate('dupont')!;
    final plan = cycleStripPlan(t);
    expect(plan.truncated, isTrue);
    expect(plan.colors, hasLength(13),
        reason: '留最后一格给省略标记，7×2 的网格节奏不能破');
  });

  test('色条：14 天整不截断', () {
    // 边界值 —— 恰好两行画满，不该出现省略标记。
    final t = findTemplate('two_shift_weekly')!; // 周期 14 天
    expect(t.cycleLength, 14);
    final plan = cycleStripPlan(t);
    expect(plan.truncated, isFalse);
    expect(plan.colors, hasLength(14));
  });

  testWidgets('英文界面：能按英文关键词搜到模板', (tester) async {
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);
    L10n.locale = 'en';

    await _openPicker(tester, <Object?>[]);
    await tester.enterText(find.byType(TextField), '4-crew 3-shift');
    await tester.pumpAndSettle();

    expect(find.text(findTemplate('four_crew_three_shift')!.title), findsOneWidget);
    expect(find.text(findTemplate('dupont')!.title), findsNothing);
  });

  testWidgets('中文界面：仍能按中文关键词搜到模板', (tester) async {
    await _openPicker(tester, <Object?>[]);
    await tester.enterText(find.byType(TextField), '四班三倒');
    await tester.pumpAndSettle();
    expect(find.text(findTemplate('four_crew_three_shift')!.title), findsOneWidget);
  });

  testWidgets('色条截断时显示省略标记', (tester) async {
    await _openPicker(tester, <Object?>[]);
    await tester.enterText(find.byType(TextField), 'dupont');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cycle-strip-more')), findsOneWidget);
  });

  testWidgets('未截断的模板不显示省略标记', (tester) async {
    await _openPicker(tester, <Object?>[]);
    await tester.enterText(find.byType(TextField), '四班三倒');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cycle-strip-more')), findsNothing);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `../toolchain/flutter/bin/flutter.bat test test/shift_template_picker_test.dart`
Expected: 编译失败 —— `cycleStripPlan isn't defined`

- [ ] **Step 3: 实现色条计划函数与渲染**

`app/lib/features/calendar/shift_template_picker_screen.dart`，把 `_cycleStrip`（第 119-140 行）整段替换为：

```dart
/// 色条要画的东西：前 N 个班次的颜色，以及是否被截断。
///
/// 抽成顶层纯函数是为了能直接断言「28 天的模板画出 13 格 + 1 个省略标记」，
/// 而不必去数 widget 树里的色块。
///
/// 为什么留最后一格做省略标记、而不是把整条周期画完：周期上限 60 天，
/// 卡片高度会随模板剧烈起伏，且 60 个色块在手机宽度下每个不到 5px，
/// 认不出任何东西。7×2 是「够认出是哪一种」的尺寸。
({List<int> colors, bool truncated}) cycleStripPlan(ShiftTemplate t) {
  const maxSlots = 14; // 7 列 × 2 行
  final truncated = t.cycleLength > maxSlots;
  final visible = truncated ? maxSlots - 1 : t.cycleLength;
  final classes = t.classes; // 只解析一次：它是现算的列表，别在循环里反复取
  return (
    colors: [for (var i = 0; i < visible; i++) classes[t.cycle[i]].color],
    truncated: truncated,
  );
}

/// 一排小色块，就是把周期表画出来；最多画 14 格，够认出是哪一种。
///
/// 超过 14 天时最后一格画成省略标记 —— 28 天的 DuPont 原来会静默只剩半截，
/// 看不出「后面还有」。副标题里写着周期天数，有了这个标记它就从
/// 「唯一线索」退回「补充说明」，这是它该有的位置。
Widget _cycleStrip(BuildContext context, ShiftTemplate t) {
  const dot = 14.0;
  const spacing = 2.0;
  const perRow = 7;
  final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
  final plan = cycleStripPlan(t);
  return SizedBox(
    // 按实际间距算，别写死 —— 改间距时宽度才不会对不上。
    width: dot * perRow + spacing * (perRow - 1),
    child: Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final color in plan.colors)
          Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: Color(color),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        if (plan.truncated)
          Container(
            key: const Key('cycle-strip-more'),
            width: dot,
            height: dot,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: muted.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('…',
                style: TextStyle(fontSize: 10, height: 1, color: muted)),
          ),
      ],
    ),
  );
}
```

并把 `_templateCard` 里的 `_cycleStrip(t)` 改为 `_cycleStrip(context, t)`（第 158 行）。

- [ ] **Step 4: 实现搜索规则**

把 `_matches`（第 43-50 行）替换为：

```dart
  /// 搜索：当前语言的标题/副标题/分组名 + id + 别名（中英都放）。
  ///
  /// 分组名走 `L10n.templateGroup` 而不是原始键 —— 键是 `h12` 这种，
  /// 对用户没有意义；换成本地化显示名后，「常白」在中文下仍然搜得到。
  bool _matches(ShiftTemplate t) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return t.title.toLowerCase().contains(q) ||
        t.subtitle.toLowerCase().contains(q) ||
        L10n.templateGroup(t.groupKey).toLowerCase().contains(q) ||
        t.id.toLowerCase().contains(q) ||
        t.aliases.any((a) => a.toLowerCase().contains(q));
  }
```

- [ ] **Step 5: 跑选择页测试**

Run: `../toolchain/flutter/bin/flutter.bat test test/shift_template_picker_test.dart`
Expected: PASS（含既有 10 条与本任务新增 7 条）

- [ ] **Step 6: 跑全量测试 + 分析**

Run:
```
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat test
```
Expected: 0 error / 0 warning；全绿

- [ ] **Step 7: 提交**

```bash
git add app/lib/features/calendar/shift_template_picker_screen.dart app/test/shift_template_picker_test.dart
git commit -m "feat(templates): 周期色条超长给出省略标记，搜索按语言匹配"
```

---

### Task 5: 版本号与更新日志

**Files:**
- Modify: `app/pubspec.yaml:4`
- Modify: `app/lib/core/app_info.dart:2`
- Modify: `app/lib/features/profile/app_dialogs.dart:43`（`_changelogZh`）、`:88`（`_changelogEn`）

**Interfaces:**
- Consumes: 无
- Produces: 无（发布元数据）

- [ ] **Step 1: 改版本号**

`app/pubspec.yaml` 第 4 行：`version: 0.6.1+72` → `version: 0.6.2+73`

`app/lib/core/app_info.dart` 第 2 行：`const String appVersion = '0.6.1';` → `const String appVersion = '0.6.2';`

- [ ] **Step 2: prepend 中文更新日志**

在 `_changelogZh` 的 `'v0.6.1\n'` **之前**插入：

```dart
const String _changelogZh = 'v0.6.2\n'
    '· 英文界面：倒班方式模板的标题与副标题改由模板自带双语，不再漏出中文\n'
    '· 英文界面：从模板新建的排班，其方案名与班次名（「白班」「夜班」等）按你的语言生成，日历格子里的简称也随之变成 D / N / O\n'
    '· 英文界面：默认排班与首启自动生成的班表同样按语言生成；模板可搜索英文关键词（如 4-crew、dupont）\n'
    '· 周期色条超过 14 天时末格显示省略标记，不再静默截断（DuPont 这类 28 天周期一眼能看出后面还有）\n\n'
    'v0.6.1\n'
```

- [ ] **Step 3: prepend 英文更新日志**

在 `_changelogEn` 的第一行之前插入对应英文：

```dart
const String _changelogEn = 'v0.6.2\n'
    '· English UI: shift-pattern templates now carry their own bilingual titles and subtitles — no more Chinese leaking through\n'
    '· English UI: a schedule created from a template gets its name and shift names ("Day shift", "Night shift", …) in your language, and calendar cells use D / N / O\n'
    '· English UI: the default schedule and the one seeded on first launch are generated in your language; templates can be searched with English keywords (4-crew, dupont)\n'
    '· The cycle colour strip now shows an ellipsis on its last cell when a pattern runs past 14 days, instead of truncating silently\n\n'
    'v0.6.1\n'
```

- [ ] **Step 4: 删最旧条目，回到 10 条**

两个常量当前各有 **11** 条（v0.6.1 … v0.4.2），已经比 AGENTS.md 规定的 10 条多一条。prepend 之后是 12 条，因此**删掉最旧的两条**。

删的是 `'v0.4.3\n'` 这个起始标记到该常量结尾分号 `;` 之间的**全部内容** —— `v0.4.2` 是最后一条，所以这两条是一次连续的尾删。中英两个常量各删一段（`app_dialogs.dart` 的第 79-86 行与第 124-131 行附近）。删完后每个常量的最后一条都是 `v0.4.4`，以 `\n\n';` 收尾。

改完的样子：

```dart
    // _changelogZh 末尾
    'v0.4.4\n'
    '· 视觉大一统——极简黑白背景(自动深浅)+ 5 色主色只染强调点，液态玻璃统一配方并新增随手机倾斜流动的动态光线，图标统一线性，动效全面换弹簧 Q 弹。\n\n';

    // _changelogEn 末尾
    'v0.4.4\n'
    '· Unified visual language — monochrome light/dark background, accent color confined to interactive highlights, unified glass recipe with tilt-reactive dynamic light, outlined icons, spring-based motion throughout.\n\n';
```

- [ ] **Step 5: 验证条数**

Run:
```bash
grep -c "^    'v0\." app/lib/features/profile/app_dialogs.dart
```

两个常量、每个 10 行（首条写在常量声明行上，所以 grep 数到的是 9×2=18 行）。用下面这条更准：

```bash
awk "/_changelogZh =/{f=1} /_changelogEn =/{f=0} f" app/lib/features/profile/app_dialogs.dart | grep -c "v0\.[0-9]"
```

Expected: `10`

- [ ] **Step 6: 跑全量测试**

Run: `../toolchain/flutter/bin/flutter.bat test`
Expected: 全绿

- [ ] **Step 7: 提交**

```bash
git add app/pubspec.yaml app/lib/core/app_info.dart app/lib/features/profile/app_dialogs.dart
git commit -m "chore(release): v0.6.2 版本号与更新日志"
```

---

### Task 6: 出图、构建与发布

**Files:**
- 产出：`app/build/visual/*.png`（gitignore）、`dist/倒班助手Pro-v0.6.2.apk`（gitignore）

**Interfaces:**
- Consumes: 前五个任务的全部改动
- Produces: 发布产物

- [ ] **Step 1: 出视觉工装图**

```bash
cd app
../toolchain/flutter/bin/flutter.bat test tool/visual/render_screens_test.dart
```

产物在 `app/build/visual/`。**看这三张**：

- `04_template_picker_light.png` —— 中文界面，确认与 v0.6.1 观感一致
- `04_template_picker_en.png` —— 英文界面，确认卡片标题/副标题是英文（首屏 4–5 张）
- `02_editor_en.png` —— 英文界面，确认预览条里的班次简称是字母而非汉字

对照物：`git stash` 后重跑同样的命令得到的旧图，或直接看 `dist/倒班助手Pro-v0.6.1.apk` 里的实际界面。

**注意出图的局限**：模板列表是懒构建的 `ListView`，一屏只渲染前几张卡片。「19 张全部无中文」由 `test/shift_templates_test.dart` 的穷举断言负责，不靠出图。

- [ ] **Step 2: 全量验收**

```bash
cd app
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat test
```

Expected: `analyze` 0 error / 0 warning；`test` 全绿。

- [ ] **Step 3: 构建 APK**

在 **PowerShell** 里先加载构建环境（本沙箱需要，设置了 JAVA_HOME / ANDROID_HOME / PUB_CACHE）：

```powershell
. C:\Users\Alec\Documents\DeepSeekHermesData\shiftassistant\tools\build-env.ps1
```

然后：

```bash
cd app
../toolchain/flutter/bin/flutter.bat build apk --release --target-platform android-arm64
```

- [ ] **Step 4: 校验并分发**

```bash
cp app/build/app/outputs/flutter-apk/app-release.apk "dist/倒班助手Pro-v0.6.2.apk"
```

校验产物里的版本与包名（`aapt2` 在 Android SDK 的 build-tools 下）：

```bash
toolchain/android-sdk/build-tools/36.0.0/aapt2 dump badging "dist/倒班助手Pro-v0.6.2.apk" | head -1
```

Expected: 该行同时含 `package: name='com.daoban.shiftassistantpro'` 与 `versionCode='73' versionName='0.6.2'`。三者有一条对不上就停下来查，别往下发布。

- [ ] **Step 5: 提交并推送**

```bash
git add -A
git commit -m "chore(release): 更新发布清单至 v0.6.2"
git tag v0.6.2
git push origin main
git push origin v0.6.2
```

（`dist/`、`*.apk` 均被 gitignore，不进仓库。）

- [ ] **Step 6: 发布到 GitHub Release**

先把发布说明写到 `tools/gh/release-notes-v0.6.2.md`（脚本会自动复用），再：

```bash
scripts/release.ps1 -SkipConfirm
```

末位非 0 → 自动标为「预发布测试版」。

**这一步是本计划唯一的真机入口**：本环境没有可运行目标（无 Android 设备），所有 GUI 行为都没有被任何 agent 实际看过。真正的界面确认由用户安装 APK 完成 —— 发布说明与最终报告里都要如实写明这一点。

---

## 验收清单（对 spec §6）

- [x] `flutter analyze` 0 error / 0 warning
- [x] `flutter test` 全绿（88 条，基线 69 → +19）
- [x] 英文无中文（穷举 19 个模板的标题/副标题/班次名/简称）—— Task 2
- [x] 中文零回归（38 条文案基线 + 19 组班次名基线）—— Task 2
- [x] 落库路径无中文（`seedIfEmpty` 英文 locale 下写库的内容）—— Task 3
- [x] `defaultSchedule()` 无中文 —— Task 3
- [x] 文案完整性（中英均非空、别名非空）—— Task 2
- [x] 搜索命中（英文关键词 + 中文关键词 + 分组名）—— Task 4
- [x] 色条省略（>14 截断画 13 格 + 标记，=14 不截断，<14 全画）—— Task 4
- [x] 视觉工装出图确认：英文变体全链路无中文、DuPont 卡片带省略标记、中文变体与 v0.6.1 一致 —— Task 6
- [ ] **手工验收（待用户）**：安装 APK 走一遍「切英文 → 建方案 → 看日历/列表」。
      本环境无 Android 设备，GUI 未经 agent 实际运行验证，这一条只能由用户完成。

---

## 执行记录（与计划的偏差）

计划写完后的实际执行中出现四处计划没预料到的情况，逐条记下，供 0.6.3 / 0.6.4 参照。

| # | 情况 | 处理 |
|---|---|---|
| 1 | **spec 的角色表漏了「早班」** —— 8/6 小时制模板全在用，按原表实现会把早班显示成「中班」 | 写计划阶段发现，补 `morning`(M) / `afternoon`(A) 两个角色，并删掉与 `day` 产出完全相同的 `office` 角色。**中文基线测试正是为这类错误准备的** —— 它会在第一批断言就炸 |
| 2 | **`calendar_screen_test.dart` 有语言泄漏**：英文用例把 `L10n.locale` 设成 `en` 后从不还原。改动前模板班次名是硬编码中文、与语言无关，所以这个泄漏一直无害；`template.classes` 改成跟随语言后，泄漏让下一个用例存下英文班次名（更长），把信息卡挤溢出 | 修的是**测试隔离**（加 `addTearDown` 还原 + 在 `_pumpCalendar` 注明这个耦合），不是产品代码。产品侧同一时序问题由 Task 3 的 `main()` 修改覆盖 |
| 3 | **英文文案语序错误**：模板卡片底部显示「on duty 2 crews」—— 起因是把「每天在岗」+ 数字 +「个班组」拼接，中英语序不同 | 出图时肉眼发现，改为整串本地化的 `L10n.crewsOnDutyCount(n)`，并删掉不再消费的两个 getter |
| 4 | **发布脚本的「源文件比 APK 新」防线被分支流程误触**：`git checkout main` 合并时重写了几个文件的 mtime，而 APK 是在合并前构建的 | 没有去改文件时间戳绕过防线，而是**重新构建**。重构建产出逐位相同的 APK（SHA256 一致），反过来证明原 APK 确实对应最终源码 |

另有一处结构性调整：三个测试文件都要判「这段文案里还有中文吗」，抽成了共用的 `app/test/support/cjk.dart`（计划里原本是在每个文件各写一份）。用码点区间判定而不写字面汉字，免得测试文件本身被当成「有中文」的噪音。

