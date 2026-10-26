# 可编辑与可点文字的可见性统一 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让全 app「能改的文字」看起来能改、「能点的行」看起来能点：班组名改成有框输入，点开编辑的行加铅笔，点开选择器 / 页面 / 弹窗的行加箭头，并把统一规则写进 AGENTS。

**Architecture:** 先抽一个共享的值行组件 `GlassValueRow`（从排班管理页的私有实现纯搬运），再把五组弹窗值行换过去；随后逐屏补图标（信息卡、编辑页班组卡、列表行、一致性缺口）。所有图标都只是装饰，不新增点击区、不改变任何点击结果。最后补视觉屏单与常设护栏，出图逐张比基线。

**Tech Stack:** Flutter / Dart、Riverpod、drift、flutter_test、仓库自带的视觉工装（`app/tool/visual`）。

**Spec:** `docs/superpowers/specs/2026-10-26-editable-affordance-design.md`

## Global Constraints

- **分支**：`beta`（测试版只在 beta 上做、提交、发布；`main` 只在正式版收一次合并）。
- **版本**：`0.12.3+178` → `0.12.4+179`；`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 同步（`app_info_test.dart` 盯着）。
- **禁止 `dart format`**：本机工具链是新版 tall style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `flutter analyze`。
- **测试命令**：`bash tools/flutter-test.sh [路径]`（它已设好 PATH 与 PUB_CACHE；不要手写 export）。
- **不改点击结果**：每一处图标的点击行为、弹层、页面跳转与改动前完全一致；图标不单独挂 `onTap`。
- **不改默认班组名**：仍是「一班…八班」；不加甲乙丙丁预设。
- **不新增依赖**；不动 Kotlin / 桌面小组件 / 数据库 schema。
- **不跑 `pumpAndSettle`** 的页面（待办、闹钟、日历）继续用逐帧 `_settle`；原因见各测试文件头。
- **新界面必须进屏单**（`app/tool/visual/visual_screens.dart`），并跑 `text_fit_guard_test`。
- **提交信息**用中文 conventional commit（`feat(ui): …` / `test: …` / `docs: …`）。

## Review Focus

下面五类是这次改动最可能踩坏、而任务里的常规断言不一定覆盖的，已分别钉进对应任务：

1. **200×400 小窗**：弹窗值行、班组卡展开、待办 / 闹钟行加图标后不许溢出、不许把值挤成省略号（`text_fit_guard` 的小窗两档是冒烟、不判失败，兜不住）。
2. **日历信息卡定高**：加箭头后整卡高度必须与改动前一致，「多条闹钟不该把卡片顶高」不能变红。
3. **360dp 标准档顶栏**：必须仍是一行（本轮不加年月箭头，但不能被别处的改动带偏）。
4. **点击结果不变**：铅笔 / 箭头所在的整行仍打开原来的界面；图标不能成为独立的点击目标。
5. **长班组名 / 8 个班组 / 英文界面**：折叠副标题与班组输入框在这些输入下不许溢出或裁字。

---

### Task 1: 视觉基线 + 抽出 `GlassValueRow`（纯搬运，逐像素不变）

**Files:**
- Create: `app/lib/core/widgets/glass_value_row.dart`
- Modify: `app/lib/features/calendar/schedule_management_screen.dart`（`_row`、`showSpanEditor` 里的「排班」行、`_spanDateRow` 三处调用；删掉文件末尾的私有 `_labelValueRow`）
- Test: `app/test/glass_value_row_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class GlassValueRow extends StatelessWidget {
    const GlassValueRow({
      super.key,
      required this.label,
      required this.value,
      required this.onTap,
      this.mutedValue = false,
      this.valueStyle,
      this.trailing,
    });
    final String label;
    final String value;
    final VoidCallback onTap;
    final bool mutedValue;
    final TextStyle? valueStyle;
    final Widget? trailing;
  }
  ```
  默认 `trailing` 为 `Icon(Icons.chevron_right_outlined, size: AppTokens.iconSm, color: AppTokens.inkMuted(context))`；
  默认值样式 `valueStyle ?? (mutedValue ? AppTokens.rowSecondary.copyWith(color: muted) : AppTokens.labelStrong)`。

- [ ] **Step 1: 存视觉基线**

Run:
```bash
bash tools/flutter-test.sh tool/visual/render_screens_test.dart
mv app/build/visual app/build/visual-baseline-20261026
```
Expected: 全部通过；目录里是 `.png`。之后每次出图都生成新的 `app/build/visual`。

- [ ] **Step 2: 写失败用例**

`app/test/glass_value_row_test.dart`，三个 `testWidgets`：
- 「默认行尾箭头；点整行触发 onTap」：`label: '日期'`、`value: '10月26日'`；断言两段文字都在、`find.byIcon(Icons.chevron_right_outlined)` 恰一枚；`tester.tap(find.byType(GlassValueRow))` 后计数为 1。
- 「trailing 覆盖默认箭头」：传 `trailing: const Icon(Icons.close)`；断言 `Icons.close` 在、`chevron_right_outlined` 不在。
- 「valueStyle 覆盖默认字号」：传 `valueStyle: AppTokens.sectionTitle`；读 `tester.widget<Text>(find.text('08:30'))` 的 `style!.fontSize`，等于 `AppTokens.sectionTitle.fontSize`。

- [ ] **Step 3: 跑用例确认失败**

Run: `bash tools/flutter-test.sh test/glass_value_row_test.dart`
Expected: 编译失败（`GlassValueRow` 未定义）。

- [ ] **Step 4: 实现共享件**

把 `schedule_management_screen.dart` 末尾 `_labelValueRow` 的函数体**原样搬进**新组件（`GlassPressable` + `GestureDetector(opaque)` + `Padding` + `Row`：左 `Expanded` 标签最多两行，右 `Flexible` + `FittedBox(scaleDown)` 值，行尾 `trailing ?? 箭头`）。只做两件事：把 `context` 参数化进 `build`，把默认值与 `valueStyle` 参数接上。**不做其它任何改写。**

- [ ] **Step 5: 跑用例确认通过**

Run: `bash tools/flutter-test.sh test/glass_value_row_test.dart`
Expected: PASS。

- [ ] **Step 6: 迁移管理页三处调用**

`_row`、`showSpanEditor` 里那行「排班」、`_spanDateRow` 里的 `_labelValueRow(...)` 改成 `GlassValueRow(...)`（参数名不变；`_spanDateRow` 传的 `trailing` 清空钮原样保留）。删掉私有 `_labelValueRow` 及其文档注释，但把注释里「为什么不用 ListTile」那两段理由**搬进新组件的文档**（v0.9.14 / v0.9.18 两次踩过）。

- [ ] **Step 7: 验证管理页零差异**

Run:
```bash
bash tools/flutter-test.sh tool/visual/render_screens_test.dart
python scripts/diff_visual.py app/build/visual-baseline-20261026 app/build/visual --threshold 0 --filter 03_management
python scripts/diff_visual.py app/build/visual-baseline-20261026 app/build/visual --threshold 0 --filter 33_span_editor
```
Expected: 两个 filter 都报 0 差异。任何差异先解决，不往下走（纯搬运必须是逐像素不变）。

- [ ] **Step 8: 提交**

```bash
git add app/lib/core/widgets/glass_value_row.dart app/lib/features/calendar/schedule_management_screen.dart app/test/glass_value_row_test.dart
git commit -m "refactor(ui): 抽出共享值行 GlassValueRow（纯搬运）"
```

---

### Task 2: 弹窗值行换成 `GlassValueRow`（补箭头）

**Files:**
- Modify: `app/lib/features/schedule/schedule_screen.dart`（待办弹窗「日期 / 开始于」行）
- Modify: `app/lib/features/schedule/recurring_fields.dart`（「时间（可选）」「提前提醒（可选）」两行）
- Modify: `app/lib/features/alarm/alarm_screen.dart`（闹钟弹窗「时间」「日期」两行）
- Test: `app/test/editable_affordance_test.dart`（新建，先放弹窗一组）

**Interfaces:**
- Consumes: `GlassValueRow`（Task 1）。
- Produces: 每行一个稳定 key —— `todo-date-row`、`todo-time-row`、`todo-remind-row`、`alarm-time-row`、`alarm-date-row`。

- [ ] **Step 1: 写失败用例**

`editable_affordance_test.dart` 先放公共辅助：`_settle` / `_dispose` 照 `todo_dialog_test.dart` 抄（逐帧推进，不用 `pumpAndSettle`），`_pumpTodos` 照同一文件抄。用例：
- 「待办弹窗：日期 / 时间 / 提醒三行都有箭头」：点 `find.byIcon(Icons.add_outlined)` 开弹窗，逐行 `find.byKey(Key(...))`，并断言每行内部有 `Icons.chevron_right_outlined`。
- 「闹钟弹窗：时间行保留 18 号字、两行都有箭头」：挂闹钟页、点 `find.text(L10n.newAlarm)`；`alarm-time-row` 内 `Text` 的 `style.fontSize == AppTokens.sectionTitle.fontSize`；两行各有箭头。
- 「200×400：待办弹窗三行不溢出、箭头可见」：视口 `Size(200, 400)`；开弹窗后 `expect(tester.takeException(), isNull)`，三个 key 都在。

- [ ] **Step 2: 跑用例确认失败**

Run: `bash tools/flutter-test.sh test/editable_affordance_test.dart`
Expected: 三个用例失败（找不到 key / 没有箭头）。

- [ ] **Step 3: 替换五处 `ListTile`**

- `schedule_screen.dart`：把 `ListTile(contentPadding: zero, title: Text(...), trailing: Text(...), onTap: ...)` 换成 `GlassValueRow(key: Key('todo-date-row'), label: ..., value: ..., onTap: ...)`。
- `recurring_fields.dart`：两处同理，key 为 `todo-time-row` / `todo-remind-row`。
- `alarm_screen.dart`：「时间」行 `valueStyle: AppTokens.sectionTitle`，「日期」行默认样式；key 为 `alarm-time-row` / `alarm-date-row`。
- 不改任何 `onTap` 里的逻辑。

- [ ] **Step 4: 跑用例确认通过**

Run: `bash tools/flutter-test.sh test/editable_affordance_test.dart test/todo_dialog_test.dart test/recurring_dialog_test.dart test/alarm_screen_test.dart`
Expected: 全 PASS（既有行为用例不许改断言）。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/schedule/schedule_screen.dart app/lib/features/schedule/recurring_fields.dart app/lib/features/alarm/alarm_screen.dart app/test/editable_affordance_test.dart
git commit -m "feat(ui): 弹窗值行统一走 GlassValueRow 并补箭头"
```

---

### Task 3: 列表行补铅笔 / 箭头

**Files:**
- Modify: `app/lib/features/schedule/schedule_screen.dart`（`_eventTile`）
- Modify: `app/lib/features/alarm/alarm_screen.dart`（`_alarmTile`）
- Modify: `app/lib/features/calendar/shift_template_picker_screen.dart`（`_manageTemplates` 的行）
- Modify: `app/lib/features/calendar/schedule_management_screen.dart`（已保存方案行的 `trailing`）
- Test: `app/test/editable_affordance_test.dart`

**Interfaces:**
- Produces keys：`todo-edit-hint`、`alarm-edit-hint`、`template-edit-hint`、`scheme-open-hint`。

- [ ] **Step 1: 写失败用例**

- 待办页（`_pumpTodos`，种一条待办）→ `find.byKey(Key('todo-edit-hint'))` 恰一枚，且它在删除钮之前（比较两枚 widget 的 `getTopLeft().dx`）；**点铅笔本身**仍然打开编辑弹窗（图标不是独立命中区的证明）。
- 闹钟页（种一条自定义闹钟）→ `alarm-edit-hint` 恰一枚、位置在删除钮左边；点它也打开编辑弹窗。
- 模板选择页（`makeVisualDatabase()` 后 `seedMyTemplates(db)`）→ 点 `find.text(L10n.manageTemplates)` 打开管理弹窗 → `template-edit-hint` 至少一枚。
- 排班管理页 → `scheme-open-hint` 恰一枚。
- 待办页 200×400：整行不溢出（`expect(tester.takeException(), isNull)`），铅笔与删除钮都还在。

- [ ] **Step 2: 跑用例确认失败**

Run: `bash tools/flutter-test.sh test/editable_affordance_test.dart`
Expected: 四条失败（找不到 key）。

- [ ] **Step 3: 实现**

- 待办 / 闹钟：在 `GlassDeleteButton` 之前插入
  ```dart
  AppIcon(Icons.edit_outlined, key: const Key('todo-edit-hint'),
      size: AppTokens.iconSm, color: AppTokens.inkMuted(context)),
  const SizedBox(width: AppTokens.gapIconText),
  ```
- 模板管理行：`trailing` 从单个删除钮改成 `Row(mainAxisSize: MainAxisSize.min, children: [铅笔, gap, 删除钮])`。
- 排班管理方案行：同样把 `trailing` 改成 `Row(… [箭头, gap, 删除钮])`（箭头 = `Icons.chevron_right_outlined`，`iconSm` + muted）。
- 图标不挂 `onTap`。

- [ ] **Step 4: 跑用例确认通过**

Run: `bash tools/flutter-test.sh test/editable_affordance_test.dart test/todo_archive_screen_test.dart test/alarm_screen_test.dart test/glass_pill_height_test.dart test/schedule_timeline_test.dart`
Expected: 全 PASS（窄窗既有用例不许红）。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/schedule/schedule_screen.dart app/lib/features/alarm/alarm_screen.dart app/lib/features/calendar/shift_template_picker_screen.dart app/lib/features/calendar/schedule_management_screen.dart app/test/editable_affordance_test.dart
git commit -m "feat(ui): 列表行补编辑铅笔与打开箭头"
```

---

### Task 4: 日历信息卡与紧凑卡补箭头

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`（完整信息卡班次行、`_infoCard(compact: true)`）
- Test: `app/test/editable_affordance_test.dart`（新增日历组）

**Interfaces:**
- Produces keys：`info-card-shift-chevron`、`compact-shift-chevron`、`compact-shift-time`（时间那段的 `Text`）。

- [ ] **Step 1: 写失败用例**

- 420×900 日历页：`info-card-shift-chevron` 恰一枚（种子库里今天有班次）。
- 200×400 日历页（短屏走 compact）：`compact-shift-chevron` 恰一枚；`compact-shift-time` 的 `RenderParagraph.didExceedMaxLines == false`。
- 「无班表那天不画箭头」：`makeVisualDatabase()` 后调 `seedBlankSchedule(db)`，再挂日历；`info-card-shift-chevron` 不在。

- [ ] **Step 2: 跑用例确认失败**

Run: `bash tools/flutter-test.sh test/editable_affordance_test.dart`
Expected: 前两条失败。

- [ ] **Step 3: 实现**

- 完整卡：在「已调班」徽章之后、
  ```dart
  if (daySchedule.classes.isNotEmpty)
    Padding(
      padding: const EdgeInsets.only(left: AppTokens.spaceSm),
      child: AppIcon(Icons.chevron_right_outlined,
          key: const Key('info-card-shift-chevron'),
          size: AppTokens.iconSm, color: muted),
    ),
  ```
- 紧凑卡：班次 `Row` 的 `Expanded` 之后加同样的箭头（key `compact-shift-chevron`，同样判据）。
- 紧凑卡时间：把 `Text(timeText, overflow: ellipsis)` 换成
  ```dart
  SizedBox(
    height: _oneLineHeight(context, AppTokens.labelSecondary),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(timeText, key: const Key('compact-shift-time'),
          maxLines: 1, style: AppTokens.labelSecondary),
    ),
  )
  ```
- 行高模型一个字不改。

- [ ] **Step 4: 跑用例确认通过**

Run: `bash tools/flutter-test.sh test/editable_affordance_test.dart test/calendar_screen_test.dart test/info_card_fit_test.dart test/calendar_header_fit_test.dart`
Expected: 全 PASS；「多条闹钟不该把卡片顶高」与顶栏两档保持绿。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/editable_affordance_test.dart
git commit -m "feat(ui): 日历信息卡与紧凑卡补调整箭头"
```

---

### Task 5: 编辑页班组卡（有框输入 + 标题 + 箭头 + 测试用展开参数）

**Files:**
- Modify: `app/lib/core/l10n.dart`（复用 `teamSettings`；新增 `teamSettingsHint`；删 `crewSettingsOptional`）
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`
- Test: `app/test/schedule_editor_test.dart`（扩展它的 `_pumpEditor`）＋ `app/test/editable_affordance_test.dart`

**Interfaces:**
- `ScheduleEditorScreen({super.key, this.scheduleId, @visibleForTesting this.initialCrewExpanded = false})`。
- L10n：`static String teamSettingsHint(String names) => t('$names · 点开可改名', '$names · tap to rename');`
- Keys：`crew-name-$i`、`crew-start-chevron-$i`、`crew-segment-chevron-$i`、`my-cycle-start-chevron`、`monthly-day-chevron-$index`。

- [ ] **Step 1: 写失败用例**

在 `schedule_editor_test.dart`：
- `_pumpEditor` 加可选参数 `crewExpanded = false`，透传给 `ScheduleEditorScreen`。
- 「班组名是有框输入框」：`crewExpanded: true`；取 `find.byKey(Key('crew-name-0'))` 的 `TextField`，断言 `decoration!.border is OutlineInputBorder`、`decoration!.hintText == null`，且存在 `find.ancestor(of: field, matching: find.byType(GlassField))`。
- 「折叠时副标题列出班组名」：默认挂载；断言 `find.textContaining(L10n.defaultTeamName(0))` 在标题下方（用 `getTopLeft().dy` 比较标题与副标题）。
- 「四行班组起始日都有箭头」：展开后 `crew-start-chevron-0..3` 各一枚。
- 「改名会落库」：先 `scrollUntilVisible(find.byKey(Key('crew-name-0')), 400)`，在 `crew-name-0` 输入 `甲班`、点保存、`repo.saved!.teamNames.first == '甲班'`。

在 `editable_affordance_test.dart`：
- 按月模式：`_pumpEditor(tester, _domain(monthly: true, monthSegments: const [MonthlySegment(startDay: 1, classIndex: 0), MonthlySegment(startDay: 11, classIndex: 1)]), crewExpanded: true)`；`crew-segment-chevron-0` 存在；`monthly-day-chevron-1` 存在（第一段不能改，不应有箭头）。
- 「我的班组起始日」行：`my-cycle-start-chevron` 存在且 `Icons.edit_outlined` 不再出现在那一行。

- [ ] **Step 2: 跑用例确认失败**

Run: `bash tools/flutter-test.sh test/schedule_editor_test.dart test/editable_affordance_test.dart`
Expected: 新用例失败。

- [ ] **Step 3: 实现**

- 构造参数与 `late bool _crewExpanded = widget.initialCrewExpanded;`。
- `_crewRow` 的名称列换成 `GlassField(label: L10n.teamName, isDense: true, child: TextField(key: Key('crew-name-$i'), decoration: glassInputDecoration(context, isDense: true), ...))`；删掉原 `hintText`；`Row` 的 `crossAxisAlignment` 改 `end`，让「设为我」chip 与输入框底对齐。
- `_crewCard` 标题用 `L10n.teamSettings`；折叠时在标题下加副标题（`L10n.teamSettingsHint(_teamNames.take(_teamCount).join(' · '))`，`microText` + muted，最多两行）；展开时不显示。
- 班组「周期起始日 / 从第 N 段入场」两行末尾加 `const Spacer()` + 箭头（key 见上）。
- `_headerCard` 的「我这组从这个周期开始」：`Icons.edit_outlined` → `Icons.chevron_right_outlined`（`iconMd` + muted，key `my-cycle-start-chevron`）。
- 按月段「每月第 N 天起」：铅笔 → 箭头（`iconSm` + muted，key `monthly-day-chevron-$index`）。
- 删掉 `L10n.crewSettingsOptional`（全仓只有这一处引用）。

- [ ] **Step 4: 跑用例确认通过**

Run: `bash tools/flutter-test.sh test/schedule_editor_test.dart test/editable_affordance_test.dart test/monthly_schedule_editor_test.dart`
Expected: 全 PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/l10n.dart app/lib/features/calendar/schedule_editor_screen.dart app/test/schedule_editor_test.dart app/test/editable_affordance_test.dart
git commit -m "feat(ui): 班组名改成有框输入并统一班组卡提示"
```

---

### Task 6: 一致性缺口（我的页 / 时段弹层 / 窄屏模板卡）

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart`（清除数据 + 四个动作行）
- Modify: `app/lib/features/calendar/calendar_screen.dart`（时段弹层「管理排班时段」行）
- Modify: `app/lib/features/calendar/shift_template_picker_screen.dart`（堆叠分支）
- Test: `app/test/editable_affordance_test.dart`

**Interfaces:**
- Keys：`profile-chevron-update`、`profile-chevron-changelog`、`profile-chevron-help`、`profile-chevron-log`、`profile-chevron-reset`、`manage-timeline-chevron`、`template-card-chevron`（宽/堆叠两分支同 key）。

- [ ] **Step 1: 写失败用例**

- 「我的」页：五行各有对应 key 的箭头；版本行没有箭头。
- 日历 → 点 `Icons.timeline` 打开时段总览 → `manage-timeline-chevron` 恰一枚。
- 模板选择页 200×400（堆叠分支）→ `template-card-chevron` 至少一枚（卡片 `onTap` 仍在）。

- [ ] **Step 2: 跑用例确认失败**

Run: `bash tools/flutter-test.sh test/editable_affordance_test.dart`
Expected: 失败。

- [ ] **Step 3: 实现**

- 「我的」页五行补 `trailing: Icon(Icons.chevron_right_outlined, key: Key(...))`（页面级行沿用默认 24）。
- 时段弹层那行补 `trailing: Icon(Icons.chevron_right_outlined, key: Key('manage-timeline-chevron'))`。
- 堆叠分支把 `texts` 包成 `Row(children: [Expanded(child: texts), SizedBox(width: 8), Icon(Icons.chevron_right_outlined, key: Key('template-card-chevron'), color: muted)])`；宽分支同一 key。

- [ ] **Step 4: 跑用例确认通过**

Run: `bash tools/flutter-test.sh test/editable_affordance_test.dart test/glass_pill_height_test.dart test/calendar_screen_test.dart`
Expected: 全 PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/profile/profile_screen.dart app/lib/features/calendar/calendar_screen.dart app/lib/features/calendar/shift_template_picker_screen.dart app/test/editable_affordance_test.dart
git commit -m "feat(ui): 补齐导航与动作行的方向暗示"
```

---

### Task 7: 视觉屏单 + 展开态字号护栏

**Files:**
- Modify: `app/tool/visual/visual_screens.dart`（新增 `67_editor_crew_expanded`）
- Modify: `app/tool/visual/render_screens_test.dart`（无需新钩子：屏的 `build` 直接传 `initialCrewExpanded: true`）
- Modify: `app/tool/visual/text_fit_guard_test.dart`（加一条「展开班组卡」的滚动矩阵）
- Test: 视觉工装本身

**Interfaces:**
- Consumes: `ScheduleEditorScreen.initialCrewExpanded`（Task 5）、`currentScheduleId`。

- [ ] **Step 1: 加屏**

`visual_screens.dart`：
```dart
(
  slug: '67_editor_crew_expanded',
  title: '排班编辑器 · 班组设置展开',
  build: (db) async => ScheduleEditorScreen(
    scheduleId: await currentScheduleId(db),
    initialCrewExpanded: true,
  ),
  needsOnboardingPrefs: false,
),
```
并加进 `visualScrollDown`：`'67_editor_crew_expanded': 2400`（让出图真的滚到班组卡）。

- [ ] **Step 2: 加护栏**

`text_fit_guard_test.dart` 末尾、主矩阵之后、**汇总用例之前**（声明顺序就是执行顺序）：对 `configs` 里 `strict: true` 的每一格，挂 `ScheduleEditorScreen(initialCrewExpanded: true)`，`tester.scrollUntilVisible(find.byKey(const Key('crew-name-0')), 400, scrollable: find.byType(Scrollable).first)`，再跑 `truncatedParagraphs(tester)`，非空就计入同一份 `findings`。文件顶部补 `import 'package:shiftassistantpro/features/calendar/schedule_editor_screen.dart';`。

- [ ] **Step 3: 跑护栏**

Run: `bash tools/flutter-test.sh tool/visual/text_fit_guard_test.dart`
Expected: PASS（若报出截断，先修字体降级再继续）。

- [ ] **Step 4: 出图并逐张比基线**

Run:
```bash
bash tools/flutter-test.sh tool/visual/render_screens_test.dart
python scripts/diff_visual.py app/build/visual-baseline-20261026 app/build/visual --threshold 0
```
Expected: 差异只出现在本轮动过的屏：`01_calendar`、`02_editor`、`03_management`、`04_template_picker`、`05_todos`、`06_alarm`、`07_profile`、`33_span_editor`、`11_override_picker`、`65_recurring_series_editor`、新屏 `67_editor_crew_expanded`，以及更新日志/版本号屏。**逐条写进交付说明**；任何解释不了的差异先查。

- [ ] **Step 5: 提交**

```bash
git add app/tool/visual/visual_screens.dart app/tool/visual/text_fit_guard_test.dart app/tool/visual/render_screens_test.dart
git commit -m "test(visual): 班组设置展开态补进屏单与字号护栏"
```

---

### Task 8: 版本、更新日志、AGENTS、全套验证

**Files:**
- Modify: `app/pubspec.yaml`、`app/lib/core/app_info.dart`
- Modify: `app/lib/features/profile/app_dialogs.dart`（`_changelogZh` / `_changelogEn`）
- Modify: `AGENTS.md`
- Test: `app/test/app_info_test.dart`、`app/test/changelog_window_test.dart`

- [ ] **Step 1: 升级版本**

`version: 0.12.4+179`；`appVersion = '0.12.4'`。

- [ ] **Step 2: 更新日志**

中英各 prepend 一条 `0.12.4`（测试版条目，原样写这一版改了什么，不做归纳），窗口保持 10 条、删最旧一条。内容：班组名改成看得出来的输入框；班组设置标题与折叠副标题；全 app 可编辑/可点提示统一（铅笔 = 编辑，箭头 = 打开）；日历信息卡与小窗补箭头；弹窗值行统一；窄屏模板卡补箭头。

- [ ] **Step 3: AGENTS**

- 版本史末尾加 `0.12.4(+179)` 一行。
- 「最近改动」加一段。
- 「关键决策与坑」新增一条**可编辑暗示规则**：有框 = 直接输入；铅笔 = 进入编辑表单；箭头 = 打开别的东西（选择器 / 页面 / 弹窗）；箭头两档尺寸（页面级 24、密集行 16）；动作行（动词文案 + leading 图标）不加箭头；例外四处（重复待办面板、取色圆点、长按拖选、年月胶囊——后者已实测 19.59dp 预算、20dp 成本）。
- 「新界面补进屏单」段补一句 `67_editor_crew_expanded` 与「展开态也要进字号护栏」。

- [ ] **Step 4: 全套验证**

Run:
```bash
bash tools/flutter-test.sh
bash tools/flutter-test.sh tool/visual/
flutter analyze
```
Run:
```bash
export PATH="$PWD/toolchain/flutter/bin:$PATH"
export PUB_CACHE="$PWD/toolchain/pub-cache"
cd app && flutter analyze
```
Expected: 0 error / 0 warning；两套测试全绿；记录改前 / 改后用例数。

- [ ] **Step 5: 提交**

```bash
git add app/pubspec.yaml app/lib/core/app_info.dart app/lib/features/profile/app_dialogs.dart AGENTS.md
git commit -m "chore(release): v0.12.4 文案与版本"
```

---

### Task 9: 构建与发布（beta 测试版）

**Files:**
- `dist/倒班助手Pro-v0.12.4.apk`（产物，gitignore）

- [ ] **Step 1: 构建（必须在主 checkout，worktree 会静默回退 debug 签名）**

Run:
```powershell
powershell -NoProfile -Command ". .\tools\build-env.ps1; cd app; flutter build apk --release --target-platform android-arm64"
```
Expected: `app/build/app/outputs/flutter-apk/app-release.apk`。

- [ ] **Step 2: 分发与校验**

```bash
cp app/build/app/outputs/flutter-apk/app-release.apk "dist/倒班助手Pro-v0.12.4.apk"
```
用 `aapt2 dump badging` 核对 `versionName=0.12.4`、`versionCode=179`、包名 `com.daoban.shiftassistantpro`。

- [ ] **Step 3: 提交、打 tag、推送**

```bash
git push origin beta
git tag v0.12.4
git push origin v0.12.4
```

- [ ] **Step 4: 发布**

```powershell
powershell -NoProfile -File tools/_run-release.ps1
```
（它已设好 `GH_CONFIG_DIR`；直接手写 `gh` 会撞「未认证」。）发布说明先写到 `tools/gh/release-notes-v0.12.4.md`。

- [ ] **Step 5: 核对发布清单**

```bash
curl -s https://raw.githubusercontent.com/Alec-WangLi/DaoBanAssistantPro/main/latest.json
```
Expected: beta 通道为 `0.12.4`，`stable` 仍是 `0.12.0`。若这一步失败（脚本只告警），按 AGENTS「只改本次发布那个通道那一个节点」手动补。

---

## 自检记录

- **Spec 覆盖**：§3.1 → Task 5；§3.2 → Task 3；§3.3 → Task 2（弹窗五行）/ 4（信息卡两处）/ 5（编辑页三处）/ 3（方案行）/ 6（其余四类）；§4 → Task 1；§5 → 各任务与 Task 7；§6 → Task 8；§7 方案 A 已定。
- **类型一致**：`GlassValueRow` 的 `valueStyle` / `trailing` 在 Task 1 定义、Task 2 使用；`initialCrewExpanded` 在 Task 5 定义、Task 7 使用。
- **Review Focus**：五条分别由 Task 2/4（200×400）、Task 4（定高）、Task 4（顶栏回归）、Task 1~6（点击不变）、Task 5/7（长名与英文）覆盖。
- **比例**：计划以签名、key、断言为主，未预写实现函数体。
