# 排班编辑器设计语言对齐 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把编辑排班界面的字号拉回全 App 档位、把周期设置的选班次改成行内彩色 chip（去掉 Material 下拉）、把删除键降噪并加确认。

**Architecture:** 字号靠**令牌**收敛 —— `AppTokens` 新增 `fontLead(16)` / `fontSupport(13)`，删掉全项目只有编辑器在用的 `fontMicro(11)`；「11 号字还会回来」这件事由编译器保证（令牌没了就写不出来）。选班次不再有二级界面：新增共享组件 `GlassChoiceChip`，周期行把可选班次平铺成一行可横滑的 chip。删除键改共享组件的 `compact` 变体。

**Tech Stack:** Flutter / Dart，`flutter_test` widget 测试，纯静态 i18n（`L10n.t(zh, en)`）。

**Spec:** `docs/superpowers/specs/2026-09-12-editor-design-alignment-design.md`

## Global Constraints

- 目标版本 **`0.6.3+74`**（`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 同步；`+build` 只能递增）。
- 版本号 `X.Y` 由用户决定，AI 只能改末位 `Z` 与 `build`。
- 验收：`flutter analyze` **0 error / 0 warning**；`flutter test` **全绿**（v0.6.2 结束时是 88 条）。
- 字号只取四档 **16 / 14 / 13 / 12**。除 `AppTokens` 之外**不允许**在 feature 层内联字号数字（`design_tokens.dart` 开头就写着这条）。
- **不动其他页面的字号**（日历格子的 18/12/11/9 是密集网格的专门设计）。
- 更新日志（`app_dialogs.dart`）：prepend 新版本、删最旧条目、**保持 10 条**。
- **不得出现任何「参考 / 借鉴 / 对照 / 类似某 App」的表述。**
- 所有命令的工作目录是 `app/`；Flutter 可执行文件是 `../toolchain/flutter/bin/flutter.bat`。

## 文件结构

| 文件 | 职责 | 本计划中的改动 |
|---|---|---|
| `app/lib/core/design_tokens.dart` | 设计令牌唯一来源 | Task 1、3：新增 `fontLead` / `fontSupport` / `onSolid`，删 `fontMicro` |
| `app/lib/core/widgets/glass_choice_chip.dart` | **新建**。共享「可选中的彩色 chip」组件 | Task 3 |
| `app/lib/core/widgets/glass_delete_button.dart` | 共享删除按钮 | Task 2：`compact` 变体改中性色 + 按压转红 |
| `app/lib/core/l10n.dart` | 全局静态 i18n | Task 2：删除确认的两条文案 |
| `app/lib/features/calendar/schedule_editor_screen.dart` | 排班编辑器 | Task 1 字号 / Task 2 删除确认 / Task 3 chip |
| `app/lib/features/calendar/shift_template_picker_screen.dart` | 倒班方式选择页 | Task 1 字号换令牌 |
| `app/lib/features/profile/app_dialogs.dart` | 更新日志 | Task 4 |

**`GlassChoiceChip` 为什么放 `core/widgets/` 而不是编辑器文件里**：本项目已确立「共享玻璃组件放 `core/widgets/`」的约定（`AGENTS.md` 有专门一节列它们）。更实际的理由是**可测** —— 私有类在 widget 测试里找不到，测试只能靠 Key 或装饰反推选中态；公开组件可以直接 `find.byType(GlassChoiceChip)` 并读 `.selected`。

---

### Task 1: 字号档位统一

把编辑器与模板选择页的字号收敛到全 App 的四档。这是三处改动里唯一直接对应「字体小了一圈」那个抱怨的。

**Files:**
- Modify: `app/lib/core/design_tokens.dart:53-60`
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`（27 处字号 + 1 个常量）
- Modify: `app/lib/features/calendar/shift_template_picker_screen.dart`（5 处字号）
- Test: `app/test/schedule_editor_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `AppTokens.fontLead`（`double`，16）、`AppTokens.fontSupport`（`double`，13）；`fontMicro` **被删除**

- [ ] **Step 1: 写失败的测试**

在 `app/test/schedule_editor_test.dart` 末尾（`main()` 的收尾 `}` 之前）追加：

```dart
  testWidgets('输入框字号与主题默认一致，不再被显式压小', (tester) async {
    // 「字体比其他界面小一圈」的直接成因：班次名称/简称输入框上写了
    // fontSize: fontBody(14)，把 M3 默认的 16 盖掉了 —— 而同一张卡片里的
    // 方案名称输入框没有显式字号、就是 16，于是同屏两个输入框不一样大。
    await _pumpEditor(tester, _domain());

    final editables = tester.widgetList<EditableText>(find.byType(EditableText));
    expect(editables, isNotEmpty);
    for (final e in editables) {
      expect(e.style.fontSize, AppTokens.fontLead,
          reason: '输入框字号应为 ${AppTokens.fontLead}，实际 ${e.style.fontSize}');
    }
  });

  testWidgets('卡片标题与行内标签落在统一档位', (tester) async {
    await _pumpEditor(tester, _domain());

    double sizeOf(String text) =>
        tester.widget<Text>(find.text(text)).style!.fontSize!;

    expect(sizeOf(L10n.shiftClasses), AppTokens.fontLead); // 卡片标题
    expect(sizeOf(L10n.cycleSection), AppTokens.fontLead); // 卡片标题
    expect(sizeOf(L10n.dayN(1)), AppTokens.fontSupport); // 行内次要标签

    // 预览条是唯一被压到最低一档的地方（7 列网格，再大就换行破版）
    final previewTitle = tester.widget<Text>(find.text(L10n.previewNext14));
    expect(previewTitle.style!.fontSize, AppTokens.fontCaption);
  });
```

文件顶部补 import：

```dart
import 'package:shiftassistantpro/core/design_tokens.dart';
```

- [ ] **Step 2: 跑测试确认失败**

Run: `../toolchain/flutter/bin/flutter.bat test test/schedule_editor_test.dart`
Expected: 编译失败 —— `The getter 'fontLead' isn't defined for the type 'AppTokens'`

- [ ] **Step 3: 加令牌、删 `fontMicro`**

`app/lib/core/design_tokens.dart` 第 53-60 行整段替换：

```dart
  // ── 排版（system 字体） ──
  //
  // 全 App 实际只用到这四档：16 输入框与卡片标题 / 14 行内主文字 /
  // 13 次要标签 / 12 微字。令牌里**只留这四档** —— 多一档就迟早有人
  // 顺手用上，档位就又散了。
  static const double fontDisplayXl = 84;
  static const double fontDisplay = 28;
  static const double fontTitle = 20;
  static const double fontHeading = 18;
  static const double fontLead = 16;
  static const double fontBody = 14;
  static const double fontSupport = 13;
  static const double fontCaption = 12;
```

注意 `fontMicro`（11）**整行删掉**。它全项目只有编辑器在用，提档后无人消费 —— 而删掉之后「11 号字再写回来」就不可能了，这比加一条测试更硬。

- [ ] **Step 4: 改编辑器的 27 处字号**

`app/lib/features/calendar/schedule_editor_screen.dart`。下表是**改动前**的行号与替换，逐条改：

| 行 | 位置 | 原来 | 改为 |
|---|---|---|---|
| 292 | 预览条标题「未来 14 天」 | `fontCaption` | `fontCaption`（不变） |
| 325 | 预览条日期 | `fontMicro` | `fontCaption` |
| 340 | 预览条班次简称 | `fontMicro` | `fontCaption` |
| 399 | 「我这组从这个周期开始」 | `fontBody` | `fontLead` |
| 404 | 顶部起始日日期值 | `fontCaption` | `fontSupport` |
| 431 | 卡片标题「班次设置」 | `fontBody` | `fontLead` |
| 436 | 「班次设置」下方说明 | `fontCaption` | `fontSupport` |
| 482 | 班次名称输入框 | `const TextStyle(fontSize: fontBody)` | **整行 `style:` 删掉** |
| 497 | 简称输入框 | `const TextStyle(fontSize: fontBody)` | **整行 `style:` 删掉** |
| 519 | 工作/休息分段器标签 | `fontCaption` | `fontSupport` |
| 558 | 「跨午夜」提示 | `fontMicro` | `fontCaption` |
| 565 | 「联动闹钟」 | `fontBody` | 不变 |
| 721 | 时间块的字段名（开始/结束/响铃时间） | `fontMicro` | `fontSupport` |
| 727 | 时间块的值 | `fontBody` | 不变 |
| 775 | 卡片标题「周期设置」 | `fontBody` | `fontLead` |
| 820 | 「第 N 天」 | `fontCaption` | `fontSupport` |
| 855 | 下拉项文字 | `fontCaption` | `fontSupport`（Task 3 会整块删掉） |
| 869 | 周期行右侧只读时间 | `fontMicro` | `fontSupport` |
| 909 | 折叠标题「班组设置（可选…）」 | `fontCaption` | `fontLead` |
| 926 | 「N 个班组」 | `fontBody` | 不变 |
| 946 | 班组区底部说明 | `fontCaption` | `fontSupport` |
| 1007 | 「设为我 / 我的班」标签 | `fontCaption` | `fontSupport` |
| 1030 | 「周期起始日」标签 | `fontCaption` | `fontSupport` |
| 1035 | 班组起始日日期值 | `fontCaption` | `fontSupport` |
| 1093 | 卡片标题「跟随法定节假日（无班次）」 | `fontBody` | `fontLead` |
| 1134 | 该卡片下方说明 | `fontCaption` | `fontSupport` |
| 1165 | 「班次颜色」弹层标题 | `fontHeading` | `fontLead` |

第 482 与 497 行的改法（把 `style:` 整行去掉，让它回到 `MaterialApp` 主题默认的 16）：

```dart
              Expanded(
                child: TextField(
                  controller: _nameCtrls[index],
                  onChanged: (v) => setState(() =>
                      _classes[index] = _editClass(_classes[index], name: v)),
                  decoration: glassInputDecoration(context, L10n.shiftName,
                      isDense: true),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              SizedBox(
                width: _abbrFieldWidth,
                child: TextField(
                  controller: _abbrCtrls[index],
                  maxLength: 2,
                  textAlign: TextAlign.center,
                  onChanged: (v) => setState(() =>
                      _classes[index] = _editClass(_classes[index], abbr: v)),
                  decoration: glassInputDecoration(context, L10n.abbrLabel,
                          isDense: true)
                      .copyWith(counterText: ''),
                ),
              ),
```

**同时把简称输入框宽度从 60 提到 68**（第 45 行的 `_abbrFieldWidth`）：

```dart
  /// 简称输入框宽度：放得下 2 个汉字（`maxLength: 2`）再加边框内边距。
  ///
  /// 60 是按 **14 号字**算出来的（两个汉字 28 + 边框内边距）；字号提到 16 后
  /// 两个汉字要 32，60 又会把第二个字裁掉 —— 而只断言文本内容的 widget 测试
  /// 看不出这种截断，只有真机截图才发现。所以字号与这个宽度必须一起改。
  static const double _abbrFieldWidth = 68;
```

- [ ] **Step 5: 改模板选择页的 5 处字号**

`app/lib/features/calendar/shift_template_picker_screen.dart`（行号为改动前）：

| 行 | 位置 | 原来 | 改为 |
|---|---|---|---|
| 65 | 顶部说明 | `13` | `AppTokens.fontSupport` |
| 92 | 分组标题 | `13` | `AppTokens.fontSupport` |
| 152 | 卡片主标题 | `14` | `AppTokens.fontLead` |
| 155 | 卡片副标题 | `12` | `AppTokens.fontSupport` |
| 161 | 「N 个班组在岗」 | `11` | `AppTokens.fontCaption` |

文件顶部补 import：

```dart
import '../../core/design_tokens.dart';
```

- [ ] **Step 6: 跑测试确认通过**

Run: `../toolchain/flutter/bin/flutter.bat test test/schedule_editor_test.dart test/shift_template_picker_test.dart`
Expected: PASS

- [ ] **Step 7: 确认没有残留的 `fontMicro` 引用**

Run: `grep -rn "fontMicro" lib/ test/ tool/`
Expected: 无输出（令牌已删，任何残留都会是编译错误）

- [ ] **Step 8: 全量验收**

Run:
```
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat test
```
Expected: 0 error / 0 warning（4 条既有 info 可容忍）；全绿

- [ ] **Step 9: 提交**

```bash
git add app/lib/core/design_tokens.dart app/lib/features/calendar/schedule_editor_screen.dart app/lib/features/calendar/shift_template_picker_screen.dart app/test/schedule_editor_test.dart
git commit -m "style(editor): 字号收敛到四档令牌，输入框不再被显式压小"
```

---

### Task 2: 删除键降噪 + 删除确认

**Files:**
- Modify: `app/lib/core/widgets/glass_delete_button.dart:27-38`（`compact` 分支）
- Modify: `app/lib/core/l10n.dart`（新增两条文案，挨着现有的 `deleteShiftClassInUse`）
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart:1218-1237`（`_deleteClass`）
- Test: `app/test/schedule_editor_test.dart`

**Interfaces:**
- Consumes: Task 1 的字号令牌
- Produces: `L10n.deleteShiftClassTitle`（`String`）、`L10n.deleteShiftClassContent(String name)`（`String`）

- [ ] **Step 1: 写失败的测试**

把 `app/test/schedule_editor_test.dart` 里现有的「删掉中间的班次定义后，周期里比它大的下标整体前移一位」整条替换为下面两条（原来的写法是点一下就删，现在中间多一道确认）：

```dart
  testWidgets('删未被引用的班次：先确认，取消则不删', (tester) async {
    final repo = await _pumpEditor(
      tester,
      _domain(
        classes: const [
          ShiftClass(name: 'A班', abbr: 'A'),
          ShiftClass(name: 'B班', abbr: 'B'),
          ShiftClass(name: 'C班', abbr: 'C'),
        ],
        cycle: const [0, 2],
      ),
    );
    expect(find.byType(GlassDeleteButton), findsNWidgets(3));

    // 删中间的 B（下标 1，周期没引用它）
    await tester.tap(find.byType(GlassDeleteButton).at(1));
    await tester.pumpAndSettle();
    expect(find.text(L10n.deleteShiftClassTitle), findsOneWidget,
        reason: '删除要先确认 —— 删错了没法靠重加复原');

    await tester.tap(find.text(L10n.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(GlassDeleteButton), findsNWidgets(3),
        reason: '取消后班次必须还在');

    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();
    expect(repo.saved!.classes.map((c) => c.name), ['A班', 'B班', 'C班']);
  });

  testWidgets('删未被引用的班次：确认后删除，周期下标整体前移一位',
      (tester) async {
    final repo = await _pumpEditor(
      tester,
      _domain(
        classes: const [
          ShiftClass(name: 'A班', abbr: 'A'),
          ShiftClass(name: 'B班', abbr: 'B'),
          ShiftClass(name: 'C班', abbr: 'C'),
        ],
        cycle: const [0, 2],
      ),
    );

    await tester.tap(find.byType(GlassDeleteButton).at(1));
    await tester.pumpAndSettle();
    // 确认框里的「删除」与别处文案相同，用弹窗内的那颗按钮定位
    await tester.tap(find.descendant(
      of: find.byType(GlassDialog),
      matching: find.text(L10n.delete),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(GlassDeleteButton), findsNWidgets(2));

    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();

    expect(repo.saved!.classes.map((c) => c.name), ['A班', 'C班']);
    expect(repo.saved!.cycle, [0, 1],
        reason: 'C 的下标要从 2 前移到 1，否则周期会指向不存在的班次定义');
  });

  testWidgets('删仍被周期引用的班次：拦下并提示，不弹确认框', (tester) async {
    await _pumpEditor(tester, _domain(cycle: const [0, 0, 2]));
    // 下标 0 被周期用了 2 天
    await tester.tap(find.byType(GlassDeleteButton).first);
    await tester.pumpAndSettle();

    expect(find.byType(GlassDialog), findsNothing,
        reason: '这条路径本来就删不掉，再问一次是多余的');
    expect(find.text(L10n.deleteShiftClassInUse.replaceAll('{n}', '2')),
        findsOneWidget);
    expect(find.byType(GlassDeleteButton), findsNWidgets(3));
  });
```

顶部补 import：

```dart
import 'package:shiftassistantpro/core/widgets/glass_dialog.dart';
```

- [ ] **Step 2: 跑测试确认失败**

Run: `../toolchain/flutter/bin/flutter.bat test test/schedule_editor_test.dart`
Expected: 编译失败 —— `The getter 'deleteShiftClassTitle' isn't defined for the type 'L10n'`

- [ ] **Step 3: 加文案**

`app/lib/core/l10n.dart`，紧挨现有的 `deleteShiftClassInUse` 之后插入：

```dart
  static String get deleteShiftClassTitle =>
      t('删除这个班次？', 'Delete this shift?');
  static String deleteShiftClassContent(String name) => isEn
      ? 'Delete "$name"? This cannot be undone.'
      : '将删除「$name」，此操作不可撤销。';
```

- [ ] **Step 4: 删除键改中性色、按压才转红**

`app/lib/core/widgets/glass_delete_button.dart` 的 `compact` 分支整段替换：

```dart
    if (compact) {
      // 常驻的 danger 红在一屏 2~5 行的表单里等于每行一个警报，与「简洁 +
      // 玻璃」的克制基调冲突。改用中性色，只在按住时转红 —— 危险语义留给
      // 按压反馈与随后的确认框，而不是一直喊。
      final muted = Theme.of(context)
          .colorScheme
          .onSurface
          .withValues(alpha: 0.55);
      return IconButton(
        tooltip: tooltip ?? L10n.delete,
        onPressed: onPressed,
        icon: const Icon(Icons.delete_outlined, size: 18),
        color: muted,
        // 按住时转危险红：IconButton 的 pressed 态没有回调，用 theme 覆盖
        // 水波纹外的图标色即可（按下时 Flutter 会走 highlightColor 之外的
        // 图标色过渡，这里用最直接的一种：交给 hoverColor/聚焦色）。
        focusColor: AppTokens.danger.withValues(alpha: 0.14),
        hoverColor: AppTokens.danger.withValues(alpha: 0.10),
        highlightColor: AppTokens.danger.withValues(alpha: 0.14),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        visualDensity: VisualDensity.compact,
      );
    }
```

**注意上面那段注释里的自我更正**：`IconButton` 没有「按住就把 `color` 换成另一个色」的钩子，`hoverColor`/`highlightColor` 改的是水波纹而不是图标。要真正做到「按下转红」得包一层 `StatefulWidget` 监听 `onHighlightChanged`。本步先用最简形态（中性色 + 红色按压反馈），**图标本身的颜色不变**；真机上若觉得反馈不够，Step 6 有可选加强。

- [ ] **Step 5: 给删除加确认框**

`app/lib/features/calendar/schedule_editor_screen.dart` 的 `_deleteClass`（约 1218 行）整段替换：

```dart
  Future<void> _deleteClass(int index) async {
    final used = _cycle.where((c) => c == index).length;
    if (used > 0) {
      // 仍被周期引用：直接拦下，不弹确认 —— 这条路本来就删不掉。
      showGlassSnack(
        context,
        L10n.deleteShiftClassInUse.replaceAll('{n}', '$used'),
        icon: Icons.info_outline,
      );
      return;
    }

    // 删除会把周期里比它大的下标整体前移，删错了没法靠重加复原
    // （时间、颜色、闹钟配置都丢了），所以先确认一次。
    final name = _classes[index].name;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (dialogContext) => GlassDialog(
        title: L10n.deleteShiftClassTitle,
        content: Text(L10n.deleteShiftClassContent(name)),
        actions: [
          GlassActionButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            label: L10n.cancel,
          ),
          const SizedBox(width: 8),
          GlassActionButton(
            variant: GlassActionVariant.danger,
            onPressed: () => Navigator.pop(dialogContext, true),
            label: L10n.delete,
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _classes.removeAt(index);
      _nameCtrls.removeAt(index).dispose();
      _abbrCtrls.removeAt(index).dispose();
      for (var i = 0; i < _cycle.length; i++) {
        if (_cycle[i] > index) _cycle[i]--;
      }
    });
  }
```

文件顶部补 import：

```dart
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_dialog.dart';
```

- [ ] **Step 6: 跑测试**

Run: `../toolchain/flutter/bin/flutter.bat test test/schedule_editor_test.dart`
Expected: PASS（3 条删除相关的用例 + 既有全部）

真机上如果觉得「按下转红」的反馈不够明显，可选的加强（**不在本计划验收范围内，先不做**）：把 `compact` 分支包成 `StatefulWidget`，用 `IconButton(onHighlightChanged: ...)` 在按下时把 `color` 切到 `AppTokens.danger`。

- [ ] **Step 7: 全量验收**

Run:
```
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat test
```
Expected: 0 error / 0 warning；全绿

- [ ] **Step 8: 提交**

```bash
git add app/lib/core/widgets/glass_delete_button.dart app/lib/core/l10n.dart app/lib/features/calendar/schedule_editor_screen.dart app/test/schedule_editor_test.dart
git commit -m "style(editor): 删除键改中性色，删除班次前先确认"
```

---

### Task 3: 周期行改行内彩色 chip

**Files:**
- Create: `app/lib/core/widgets/glass_choice_chip.dart`
- Modify: `app/lib/core/design_tokens.dart`（新增 `onSolid`）
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`（`_cycleRow`）
- Test: `app/test/design_tokens_test.dart`、`app/test/schedule_editor_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `fontSupport` / `fontLead`
- Produces:
  - `AppTokens.onSolid(Color background) → Color`（恒满足对比度 ≥ 4.5:1）
  - `GlassChoiceChip({required String label, required Color color, required bool selected, required VoidCallback onTap, String? semanticsLabel})`
  - `cycleChipKey(int dayIndex, int classIndex) → Key`（顶层函数，供测试精确定位）

- [ ] **Step 1: 写失败的测试**

先在 `app/test/design_tokens_test.dart` 末尾追加：

```dart
  test('onSolid：任何底色上的文字对比度都 ≥ 4.5', () {
    // 白/黑两条对比度曲线在亮度 0.179 处交叉，交叉点上各是 4.58:1 ——
    // 所以「取对比度高的一侧」对**任何**底色都能过 AA。
    const samples = <Color>[
      Color(0xFF4C8DFF), Color(0xFF7A5CFF), Color(0xFF9AA0B4),
      Color(0xFF5A5F73), Color(0xFF34C759), Color(0xFFFF9F0A),
      Color(0xFFFF375F), Color(0xFF00C7BE),
      Color(0xFFFFFFFF), Color(0xFF000000),
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
  });
```

再在 `app/test/schedule_editor_test.dart` 末尾追加：

```dart
  testWidgets('周期行把可选班次铺成 chip，点一下就切换', (tester) async {
    await _pumpEditor(tester, _domain(cycle: const [0, 1, 1]));

    // 3 天 × 3 个班次定义 = 9 个 chip
    expect(find.byType(GlassChoiceChip), findsNWidgets(9));
    expect(tester.widget<GlassChoiceChip>(find.byKey(cycleChipKey(0, 0))).selected,
        isTrue);
    expect(tester.widget<GlassChoiceChip>(find.byKey(cycleChipKey(0, 1))).selected,
        isFalse);

    // 第 1 天从「班次 0」改成「班次 2」
    await tester.tap(find.byKey(cycleChipKey(0, 2)));
    await tester.pumpAndSettle();

    expect(tester.widget<GlassChoiceChip>(find.byKey(cycleChipKey(0, 0))).selected,
        isFalse);
    expect(tester.widget<GlassChoiceChip>(find.byKey(cycleChipKey(0, 2))).selected,
        isTrue);

    // 保存后确实落到了周期上
    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();
  });

  testWidgets('周期行不再有下拉控件', (tester) async {
    // 二级弹层是这次要消掉的东西：Material 的方角下拉与全 App 的玻璃
    // 弹层完全不同源。用「找不到 DropdownButton」把这件事钉住。
    await _pumpEditor(tester, _domain());
    expect(find.byType(DropdownButton<int>), findsNothing);
  });

  testWidgets('选中 chip 的文字色按底色取，保证可读', (tester) async {
    await _pumpEditor(tester, _oneShift(
      const ShiftClass(name: '白班', abbr: '白', color: 0xFF4C8DFF),
    ));

    final chip = tester.widget<GlassChoiceChip>(find.byKey(cycleChipKey(0, 0)));
    expect(chip.selected, isTrue);
    expect(chip.label, '白班');
    expect(chip.color, const Color(0xFF4C8DFF));
  });
```

顶部补 import：

```dart
import 'package:shiftassistantpro/core/widgets/glass_choice_chip.dart';
```

- [ ] **Step 2: 跑测试确认失败**

Run: `../toolchain/flutter/bin/flutter.bat test test/design_tokens_test.dart test/schedule_editor_test.dart`
Expected: 编译失败 —— `Method not found: 'onSolid'` / `'GlassChoiceChip'` / `'cycleChipKey'`

- [ ] **Step 3: 加 `AppTokens.onSolid`**

`app/lib/core/design_tokens.dart`，紧挨现有的 `inkFor` / `_computeInk` 之后插入：

```dart
  /// 实心色块上的可读文字色：白或黑，取对比度更高的一侧。
  ///
  /// 恒有 max(白, 黑) ≥ 4.58:1 —— 两条曲线在亮度 0.179 处交叉，交叉点上
  /// 各是 4.58。所以这个二选一对**任何**底色都能过 WCAG AA，不需要像
  /// [inkFor] 那样逐档逼近。
  ///
  /// 不能拿 [inkFor] 代劳：那个是「把一个前景色调到在给定背景上可读」，
  /// 朝黑还是朝白由**背景**明暗决定；这里是「底色已定，白黑二选一」，
  /// 方向必须由底色与黑白两色的对比度决定。拿 inkFor(white, 橙) 会得到
  /// 白色本身（它朝白逼近），而橙底白字只有 2.23:1。
  static Color onSolid(Color background) =>
      contrastRatio(Colors.white, background) >=
              contrastRatio(Colors.black, background)
          ? Colors.white
          : Colors.black;
```

- [ ] **Step 4: 新建 `GlassChoiceChip`**

创建 `app/lib/core/widgets/glass_choice_chip.dart`：

```dart
import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 可选中的彩色 chip：一排平铺出来，点一下就选中。
///
/// 用在「这一天用哪个班次」这类**选项少、且要一眼看全**的地方 ——
/// 比下拉少一层界面（不用弹二级），也比下拉更容易比较各选项的颜色。
///
/// 选中态是班次色**实心底**，文字色由 [AppTokens.onSolid] 按底色取 ——
/// 恒定白字在调色板的浅色（橙 2.23:1、绿、灰）上读不出来。
class GlassChoiceChip extends StatelessWidget {
  const GlassChoiceChip({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.semanticsLabel,
  });

  final String label;

  /// 班次色：未选中时作圆点色，选中时作实心底与描边色。
  final Color color;

  final bool selected;
  final VoidCallback onTap;

  /// 读屏用的完整标签；缺省时用 [label]。
  final String? semanticsLabel;

  /// 视觉高度。外层再补 6pt 竖向内边距，把**命中区**补到 44 —— 视觉上仍
  /// 是 32 的小 chip，手指却够得着（也为以后的车机留余量）。
  static const double visualHeight = 32;
  static const double _hitPad = 6;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel ?? label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusS),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: _hitPad),
            child: Container(
              height: visualHeight,
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
              decoration: BoxDecoration(
                color: selected
                    ? color
                    : primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppTokens.radiusS),
                border: Border.all(
                  color: selected
                      ? color
                      : AppTokens.glassBorder(isDark)
                          .withValues(alpha: isDark ? 0.30 : 0.85),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!selected) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: AppTokens.spaceSm),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTokens.fontSupport,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AppTokens.onSolid(color)
                          : onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: 周期行改用 chip**

`app/lib/features/calendar/schedule_editor_screen.dart` 的 `_cycleRow`（约 808 行）整段替换为下面的内容，并在**顶层**（类外，`_editClass` 附近）加 `cycleChipKey`：

```dart
/// 周期行里某个 chip 的 Key —— 让测试能精确点到「第几天选哪个班次」。
Key cycleChipKey(int dayIndex, int classIndex) =>
    ValueKey('cycle-chip-$dayIndex-$classIndex');
```

```dart
  Widget _cycleRow(BuildContext context, int index) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(L10n.dayN(index + 1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: AppTokens.fontSupport,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            // 班次多（五六班倒）或屏窄时横向滚动：右侧露出半个 chip
            // 就是「还能滑」的提示。
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _classes.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                          right: i == _classes.length - 1
                              ? 0
                              : AppTokens.spaceSm),
                      child: GlassChoiceChip(
                        key: cycleChipKey(index, i),
                        label: _classes[i].name,
                        color: Color(_classes[i].color),
                        selected: i == _cycle[index],
                        onTap: () => setState(() => _cycle[index] = i),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          Text(
            _rangeText(_classes[_cycle[index]]),
            style: TextStyle(fontSize: AppTokens.fontSupport, color: muted),
          ),
        ],
      ),
    );
  }
```

顶部补 import：

```dart
import '../../core/widgets/glass_choice_chip.dart';
```

`_rangeText` 保持不变（chip 行仍复用它显示右侧只读时间）。

- [ ] **Step 6: 跑测试**

Run: `../toolchain/flutter/bin/flutter.bat test test/design_tokens_test.dart test/schedule_editor_test.dart`
Expected: PASS

- [ ] **Step 7: 全量验收**

Run:
```
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat test
```
Expected: 0 error / 0 warning；全绿

- [ ] **Step 8: 出图确认**

Run: `../toolchain/flutter/bin/flutter.bat test tool/visual/render_screens_test.dart`

看 `app/build/visual/02_editor_light.png` 与 `02_editor_en.png`、`02_editor_dark.png`：周期行应当是「第 N 天 + 一排彩色 chip + 只读时间」，**不再有方角下拉**。特别注意浅色班次（橙、灰）选中时的文字是否读得清 —— 那是这次配色改动的重点。

- [ ] **Step 9: 提交**

```bash
git add app/lib/core/widgets/glass_choice_chip.dart app/lib/core/design_tokens.dart app/lib/features/calendar/schedule_editor_screen.dart app/test/design_tokens_test.dart app/test/schedule_editor_test.dart
git commit -m "feat(editor): 周期设置改行内彩色 chip，去掉二级下拉"
```

---

### Task 4: 版本号与更新日志

**Files:**
- Modify: `app/pubspec.yaml:4`
- Modify: `app/lib/core/app_info.dart:2`
- Modify: `app/lib/features/profile/app_dialogs.dart`

**Interfaces:**
- Consumes: 无
- Produces: 无（发布元数据）

- [ ] **Step 1: 改版本号**

`app/pubspec.yaml` 第 4 行：`version: 0.6.2+73` → `version: 0.6.3+74`
`app/lib/core/app_info.dart` 第 2 行：`'0.6.2'` → `'0.6.3'`

- [ ] **Step 2: prepend 更新日志**

在 `_changelogZh` 的 `'v0.6.2\n'` 之前插入：

```dart
const String _changelogZh = 'v0.6.3\n'
    '· 排班编辑界面的字号与全 App 统一（此前输入框被单独压小了一号，同一张卡片里两个输入框都不一样大）\n'
    '· 周期设置改成**行内直接点选班次**：每个可选班次平铺成一个彩色小块，点一下就换，不再弹下拉菜单\n'
    '· 班次简称输入框加宽，两个汉字不会被裁掉\n'
    '· 删除班次改为低调图标（不再每行一个红点），并在删除前先确认一次\n\n'
    'v0.6.2\n'
```

在 `_changelogEn` 的 `'v0.6.2\n'` 之前插入：

```dart
const String _changelogEn = 'v0.6.3\n'
    '· Schedule editor typography now matches the rest of the app (input fields were a size smaller — two fields on the same card did not even match each other)\n'
    '· The cycle section now lets you pick a shift inline: every option is a coloured chip you tap, with no dropdown to open\n'
    '· The shift-abbreviation field is wider, so two characters are no longer clipped\n'
    '· Deleting a shift uses a quieter icon (no red dot on every row) and asks for confirmation first\n\n'
    'v0.6.2\n'
```

- [ ] **Step 3: 删最旧一条，保持 10 条**

删掉两个常量末尾 `'v0.4.4\n'` 那一条（从中英各自的 v0.4.4 起始标记到该常量的收尾分号 `;`，删完最后一条是 `v0.4.5`，以 `\n\n';` 收尾）。

- [ ] **Step 4: 验证条数**

```bash
cd app
grep -c "^    'v0\." lib/features/profile/app_dialogs.dart
```

每个常量的**第一条**写在 `const String _changelogXx = 'v0.6.3\n'` 那一行上（行首是 `const`，不被这条 grep 计到），所以两个常量各剩 9 行匹配。

Expected: `18`（即 9 + 9，对应两个常量各 10 条）。若得到别的数，回去数条目，别往下走。

- [ ] **Step 5: 全量验收**

Run:
```
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat test
```
Expected: 0 error / 0 warning；全绿

- [ ] **Step 6: 提交**

```bash
git add app/pubspec.yaml app/lib/core/app_info.dart app/lib/features/profile/app_dialogs.dart
git commit -m "chore(release): v0.6.3 版本号与更新日志"
```

---

### Task 5: 构建与发布

**Files:**
- 产出：`app/build/visual/*.png`（gitignore）、`dist/倒班助手Pro-v0.6.3.apk`（gitignore）

**Interfaces:**
- Consumes: 前四个任务的全部改动
- Produces: 发布产物

- [ ] **Step 1: 出图并看图**

```bash
cd app
../toolchain/flutter/bin/flutter.bat test tool/visual/render_screens_test.dart
```

**看这三张**：`02_editor_light.png`、`02_editor_dark.png`、`04_template_picker_en.png`。

检查点：周期行是 chip 不是下拉；浅色班次选中时文字读得清；编辑器字号与模板页观感不再「小一圈」；模板页英文卡片的标题换行没有撑破卡片。

- [ ] **Step 2: 全量验收**

```bash
cd app
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat test
```

Expected: 0 error / 0 warning；全绿。

- [ ] **Step 3: 构建 APK**

先加载构建环境（**PowerShell**）：

```powershell
. C:\Users\Alec\Documents\DeepSeekHermesData\shiftassistant\tools\build-env.ps1
```

再：

```bash
cd app
../toolchain/flutter/bin/flutter.bat build apk --release --target-platform android-arm64
```

- [ ] **Step 4: 校验并分发**

```bash
cp app/build/app/outputs/flutter-apk/app-release.apk "dist/倒班助手Pro-v0.6.3.apk"
toolchain/android-sdk/build-tools/36.0.0/aapt2 dump badging "dist/倒班助手Pro-v0.6.3.apk" | head -1
```

Expected: 该行同时含 `package: name='com.daoban.shiftassistantpro'` 与 `versionCode='74' versionName='0.6.3'`。

- [ ] **Step 5: 写发布说明**

写到 `tools/gh/release-notes-v0.6.3.md`（发布脚本会自动复用同名文件），结构照下面这段：

```markdown
## 倒班助手Pro v0.6.3

### 本次更新
- **排班编辑界面的字号与全 App 统一**：此前班次名称与简称输入框被单独设成了小一号，同一张卡片里的方案名称输入框却是一号大 —— 现在全屏统一
- **周期设置改成行内直接点选班次**：每个可选班次平铺成一个彩色小块，点一下就换；不再弹出方角的下拉菜单，与全 App 的玻璃弹层风格一致
- **选中的班次块用班次色实心填充，文字颜色按底色自动取白或黑**：橙色、绿色这类浅色班次上的字不再糊得读不出来
- **班次简称输入框加宽**：两个汉字（如「大夜」）不会被裁掉
- **删除班次改为低调图标**：不再每行一个红色垃圾桶，并在真正删除前先确认一次

### 说明
- 本版为测试版，**不涉及数据格式，升级无需重录**
- 班次定义与周期表的数据结构未变；本版只改界面

### 构建信息
- 版本：0.6.3（versionCode 74）
- 包名：com.daoban.shiftassistantpro，minSdk 26
- APK 大小：<用 `stat -c %s` 取，写成 MB（字节数）>
- 对应源码提交：<HEAD 短哈希 + 提交标题>
- SHA256：`<sha256sum dist/倒班助手Pro-v0.6.3.apk 的输出>`
```

`<…>` 三处是构建完成后才有值的，按当次实际产物填。

- [ ] **Step 6: 提交、打标签、推送**

```bash
git add -A
git commit -m "chore(release): 更新发布清单至 v0.6.3"
git tag v0.6.3
git push origin main
git push origin v0.6.3
```

- [ ] **Step 7: 发布到 GitHub Release**

```bash
scripts/release.ps1 -SkipConfirm
```

末位非 0 → 自动标为「预发布测试版」。

**若脚本报「源文件比 APK 新」**：说明构建之后又动过源文件（或 git 操作重写了 mtime）。**不要改文件时间戳绕过它** —— 重新构建一次，让不变式真正成立。

**这一步是本计划唯一的真机入口**：本环境没有 Android 设备，所有 GUI 行为都没有被任何 agent 实际看过。chip 的按下手感、命中区大小、真机上 chip 组的横滑体验，都要靠用户装 APK 确认 —— 发布说明与最终报告里都要如实写明。

---

## 验收清单（对 spec §6）

- [x] `flutter analyze` 0 error / 0 warning（4 条既有 info）
- [x] `flutter test` 全绿（97 条，v0.6.2 基线 88 → +9）
- [x] 同一屏字号自洽：编辑器每个 `EditableText` 生效字号都是 16 —— Task 1
- [x] 档位落点：卡片标题 16 / 第 N 天 13 / 时间块字段名 13 / 预览条 12 —— Task 1
- [x] `fontMicro` 在全项目无引用（令牌已删，编译器保证）—— Task 1
- [x] chip 选中态可读：调色板与主题色上 `onSolid` 对比度均 ≥ 4.5:1，且钉住了具体选择 —— Task 3
- [x] 删除需确认：取消不删、确认才删且周期下标正确前移；被引用时不弹确认 —— Task 2
- [x] 周期行无 `DropdownButton` —— Task 3
- [x] 出图确认（浅色 + 深色）：chip 观感、选中态可读、无溢出 —— Task 3 / Task 5
- [ ] **手工验收（待用户）**：真机上看 chip 的命中区手感与横滑体验、简称输入框两个汉字不被裁。
      本环境无 Android 设备，GUI 未经 agent 实际运行验证，这一条只能由用户完成。

---

## 执行记录（与计划的偏差）

计划里有七处与实际执行对不上，逐条记下。

| # | 情况 | 处理 |
|---|---|---|
| 1 | **既有删除测试有两处漏算**：计划只点名一条（「删掉中间的班次定义后…」），实际还有「删除仍被引用的班次定义被拦下，未被引用的可以删」与「添加班次：新增一条定义，周期里没引用所以可以删掉」也要走确认框 | 三条一起改，并抽了 `_tapDeleteAndConfirm` 帮手避免各写一遍 |
| 2 | **chip 改造漏算两条既有测试**：「周期某天下拉换班次后，该行右侧时间文本跟着变」与「改周期里某天引用的班次，预览条对应格子跟着变」都靠点 `DropdownButton` 换班次 | 改成点 `cycleChipKey(天, 班次)`；前者顺带改名（不再有「下拉」） |
| 3 | **`IconButton` 在这个 Flutter 版本上不暴露 `onHighlightChanged`** —— 计划里假设有，并据此把「按下转红」标为「可选加强、先不做」 | 改用 `Tooltip + InkResponse` 自己拼，按 spec 把「按下转红」真正做出来。只做中性色的话，危险操作的提示就完全没了 |
| 4 | **出图发现真问题**：三张 chip（约 214px）与最长的只读时间串（约 208px）在 420 宽的手机上互斥，chip 被挤成半个、看起来像坏了。spec 只说「空间不足时隐藏时间」，没给判定方式 | 新增可单测的 `cycleRowFitsTime`：量出 chip 组与时间串的实际宽度再决定显不显示。宽屏显示、手机宽度下 3 个以上班次时隐藏 |
| 5 | **工装看不到周期行**：它每屏只拍一屏，而周期设置在编辑器中段 | 写了一次性脚本滚到周期行出图（浅色 + 深色都看过，图已删）。工装本身的滚动/多尺寸扩展留给 0.6.4 —— 那一版本来就要改它 |
| 6 | **analyze 一度 4 → 5 条**：`test/design_tokens_test.dart` 的 `dart:ui` 导入变成多余 | 删掉该导入，退回基线的 4 条 |
| 7 | **发布脚本的「源文件比 APK 新」防线**（v0.6.2 时靠重新构建解决过一次） | 这次换掉触发条件本身：用 `git fetch . HEAD:main` 更新主干引用，**不动工作区文件**，于是 checkout 不再重写 mtime，防线自然通过、也不必重构建 |

