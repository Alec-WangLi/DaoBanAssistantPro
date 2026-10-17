# 待办归档三处收口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 v0.11.3 真机测出来的三处收口：折叠区标题行融入设计语言、归档里的一次性待办给回勾选框、同一天内按钟点排；外加一条「勾完可撤销」。

**Architecture:** 仓库层只有一个纯函数要改（`splitTodos` 的排序与语义）；界面层改「本次动过的行」这套会话内状态、归档行的勾选框条件、标题行那一颗件；再给共享的玻璃提示条加一个动作。

**Tech Stack:** Flutter / Riverpod / Drift（SQLite）。纯函数直接单测，界面走 widget 测试 + 视觉工装。

**Spec:** 无独立规格 —— 三处收口是 2026-10-11 与用户逐条对完后在对话里定下的（①胶囊 ②只给一次性待办勾选 + 撤销 ③日期降序不变、同一天按钟点）。这一版**不回写** `2026-10-11-todo-auto-archive-design.md`。

## Global Constraints

- **版本号**：`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须同步（`app/test/app_info_test.dart` 盯着）。本轮是**测试版**：`0.11.3+150` → `0.11.4+151`。**`X.Y` 不许动**。
- **分支**：测试版一律在 `beta` 上做、提交、发布（`main` 只在发正式版时收合并）。
- **验收**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿；`flutter test tool/visual/` 全绿。用例数**只增不减**（动工前先跑一遍记下真实数字，别抄旧的）。
- **界面层不许写数值字面量**（`app/test/design_tokens_test.dart` 守门）：字号 / 字重 / `Color(0x…)` / `Circular(<n>)` / `Duration(milliseconds:)` / `Icon(size:)` / 非 4px 栅格的间距常量。文案一律走 `L10n`。
- **除 `core/haptics.dart` 外，任何文件不许出现 `HapticFeedback.`**；**共享组件已经震过的控件不许在调用点再补一次**（`GlassCheck` 自己发 `select()`，勾选那处**有意不加** `commit()`）。
- 只改 `isCompleted` / 排序 / 界面，**不动 Drift 表** → 不需要 `dart run build_runner build`。
- **不要跑 `dart format`**（本仓工具链的格式化器会重排整个文件）。只跑 `flutter analyze`。
- 构建环境：`source tools/build-env.sh`，然后用 `"$FLUTTER_ROOT/bin/flutter"`（`flutter` 不在 PATH 上）。

## Review Focus

以下五类是这次改动隐含、而**任何单一任务的测试都不会自动覆盖**的：

1. **取消勾选那一瞬间不许跳** —— 写库还没回来时，那一条不能离开主列表（先跳走再跳回来 = 用户当初报的「不见了」）。主列表里的、归档里的、一次性的、重复的，四条路都要。
2. **归档里一次性待办取消勾选之后**：它回到主列表、**不划掉**、且**只有一条**（不许出现「恢复出一条、原来那条还在」）。
3. **重复待办的历史行在归档里不许出现勾选框** —— 那一条点开会走 `recurring_panel` 的 `live.single`，两条未完成行当场抛 `StateError`。这一版只是「不给画」，必须在界面上钉住。
4. **小窗 200×400**：折叠区那一行（胶囊）与归档行（右边多了勾选框、左边少了空位）都不许溢出、标题不许被挤没。
5. **「撤销」是异步的**：点下去时那一页可能已经被切走 / 那一条可能已经被删掉 —— 不许崩、不许把别的层关掉（仓库里 `dialogCloser` 那条老规矩的同类）。

---

### Task 1: `splitTodos` 同一天内按钟点排

**Files:**
- Modify: `app/lib/data/todo_archive.dart`（`splitTodos` 的 `archived.sort`）
- Test: `app/test/todo_archive_test.dart`

**Interfaces:**
- Produces: `TodoSplit splitTodos(List<ScheduleEvent> events, Set<int> sessionRows)` —— 签名形状不变，**第二个参数改名**（Task 2 用），排序规则改成确定的
- 排序：`date` 降序 → `timeMinute` 降序（`null` 当 `-1`，即没填钟点的排在这一天最后）→ `id` 降序兜底
- 为什么：现在同一天的多条按 `id` 降序，**不看钟点** —— 一天排了 08:00 / 20:00 两条，归档里会倒着显示。主列表是「日期升序 + 钟点升序」，两区口径应当互为镜像。

- [ ] **Step 1: 写失败的用例**

在 `app/test/todo_archive_test.dart` 的 `splitTodos` 组里加（把现有那条「同一天的两条：折叠区按 id 降序兜底」**改名并扩写**成下面这条 —— 它原来钉的正是要改掉的旧口径）：

```dart
test('同一天的多条按钟点从晚到早；没填钟点的排在这一天最后', () {
  final d = DateTime.utc(2026, 1, 5);
  final s = splitTodos([
    _e(7, d, done: true, minute: 8 * 60),
    _e(9, d, done: true), // 没填钟点
    _e(11, d, done: true, minute: 20 * 60),
  ], const {});
  expect(s.archived.map((e) => e.id).toList(), [11, 7, 9],
      reason: '20:00 → 08:00 → 没钟点的；钟点降序，没钟点的垫底');
});
```

`_e` 那个夹具要加一个可空的 `minute`（透传给 `ScheduleEvent` 的 `timeMinute`）。

- [ ] **Step 2: 跑它，确认它失败**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_test.dart`
Expected: FAIL —— 实际拿到 `[11, 9, 7]` 或 `[9, 11, 7]`（按 id 降序 / 原位），断言要的是 `[11, 7, 9]`。

- [ ] **Step 3: 实现**

把 `splitTodos` 里那个比较器改成三级键：

```dart
archived.sort((a, b) {
  final byDate = b.date.compareTo(a.date);
  if (byDate != 0) return byDate;
  // 同一天按钟点从晚到早 —— 主列表是「日期升序 + 钟点升序」，两区互为镜像。
  // 没填钟点的当 -1（这一天里最早），降序下自然垫底。
  final byTime = (b.timeMinute ?? -1).compareTo(a.timeMinute ?? -1);
  return byTime != 0 ? byTime : b.id.compareTo(a.id);
});
```

- [ ] **Step 4: 跑它，确认通过**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/data/todo_archive.dart app/test/todo_archive_test.dart
git commit -m "fix(todo): 归档同一天内按钟点从晚到早，不再按行号倒序"
```

---

### Task 2: 「本次动过的行」一律留在主列表（修掉取消勾选时那一下跳）

**Files:**
- Modify: `app/lib/data/todo_archive.dart`（`splitTodos` 的参数的语义与注释）
- Modify: `app/lib/features/schedule/schedule_screen.dart`（`_justCompleted` → `_sessionRows`；`onChanged` 里两个分支都 `add`）
- Test: `app/test/todo_archive_test.dart`、`app/test/todo_archive_screen_test.dart`

**Interfaces:**
- Produces: `splitTodos(events, sessionRows)` 里 `sessionRows` 的语义 = **本次进来之后动过的行 id**（勾上或取消都算），这些行一律留在主列表
- 为什么改：现在的判据是 `!e.isCompleted || justCompleted.contains(e.id)`，而**取消勾选时把它从集合里移掉**了 —— 那一刻库里记的还是「已完成」（写库还没回来），于是那一条**先离开主列表、等写库回来再回来**。用户看到的就是「点了一下它跳一下」。改成两个方向都 `add`，它整趟都待在原地。

- [ ] **Step 1: 写失败的用例（纯函数层）**

在 `app/test/todo_archive_test.dart` 里把「本次刚勾的留在主列表里」那条**改名并扩写**（原来只钉勾上那一半）：

```dart
test('本次动过的行一律留在主列表 —— 勾上与取消都在原地', () {
  final events = [
    _e(1, DateTime.utc(2026, 1, 1), done: true),
    _e(2, DateTime.utc(2026, 1, 2)),
    _e(3, DateTime.utc(2026, 1, 3), done: true),
  ];
  final s = splitTodos(events, const {1, 2});
  expect(s.active.map((e) => e.id).toList(), [1, 2],
      reason: '刚勾的那条还在主列表，且按日期排在 2 前面 —— 不能跳到末尾');
  expect(s.archived.map((e) => e.id).toList(), [3]);
});
```

（与原来那条的差别：`{1}` → `{1, 2}`，把「取消勾选这一侧也在集合里」写进断言 —— 界面层照这个语义填集合。）

- [ ] **Step 2: 跑它，确认通过（这条纯函数本身不用改）**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_test.dart`
Expected: PASS —— 纯函数是**由界面层喂什么决定**的，所以真正要写的是下面那条界面层的。

- [ ] **Step 3: 写失败的用例（界面层 —— 这条才是回归）**

在 `app/test/todo_archive_screen_test.dart` 里加：

```dart
testWidgets('取消勾选：那一条整趟都留在主列表里，不许跳走', (tester) async {
  // 种 2 条未完成的待办（日期 1/2、1/3）。点第一条的勾（勾上），
  // 再点一次（取消）——**中间不许 pumpAndSettle**，要在写库还没回来的那一帧上看。
  // 断言：那一条始终在 find.byType(GlassTile) 的主列表区里，
  //      且取消之后它不带删除线（不是「已完成」）。
});
```

写法要点（写进注释）：勾上之后 `await tester.pump()` **一帧**（推进到写入发出、但流还没回来），再点一次、再 `pump()` 一帧 —— 这一帧上断言它**仍在主列表**。`pumpAndSettle` 会把流等回来，那条就照不出来。

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_screen_test.dart`
Expected: FAIL —— 取消勾选那一帧它从主列表里消失了。

- [ ] **Step 4: 实现**

`schedule_screen.dart`：

- `final Set<int> _justCompleted = {};` → `final Set<int> _sessionRows = {};`，注释改写成「**本次进来之后动过的行**（勾上与取消都算）：这一趟它们一律留在主列表里 —— 勾完先划掉再收走；取消勾选也不许跳走（写库回来之前库里记的还是旧值）」。
- `onChanged` 里那段：

```dart
setState(() {
  // **两个方向都记进集合、一律乐观写。** 勾上那半边是为了「先划掉再收走」；
  // 取消那半边是为了「不许跳走」—— 这一刻库里记的还是「已完成」，不把它按在
  // 主列表里的话，它会先离开、等写库回来再回来（用户看到的就是点一下跳一下）。
  _sessionRows.add(e.id);
});
await ref.read(appRepositoryProvider).setEventCompleted(e, v);
```

（`v` 那个分支没了 —— 集合的含义不再是「刚勾掉的」。）

- [ ] **Step 5: 跑它，确认通过；再跑全套**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_screen_test.dart && "$FLUTTER_ROOT/bin/flutter" test`
Expected: 全绿。

- [ ] **Step 6: 提交**

```bash
git add app/lib/data/todo_archive.dart app/lib/features/schedule/schedule_screen.dart app/test/todo_archive_test.dart app/test/todo_archive_screen_test.dart
git commit -m "fix(todo): 取消勾选不再跳走 —— 本次动过的行整趟留在主列表"
```

---

### Task 3: 归档里的一次性待办给回勾选框

**Files:**
- Modify: `app/lib/features/schedule/schedule_screen.dart`（`_eventTile` 的 `archived` 那一支）
- Test: `app/test/todo_archive_screen_test.dart`

**Interfaces:**
- Consumes: `_sessionRows`（Task 2）—— 取消勾选时 `add`，那一条于是当场回到主列表
- 规则：**`archived && e.seriesId == null` 才画 `GlassCheck`**；归档里的重复历史行仍走那个等宽空位（`_archiveCheckSlot`）
- 为什么只给一次性：归档里的行可能是**旧 occurrence**，而那个系列已经走到下一次了 —— 取消勾选会让一个系列出现两条未完成的行，`recurring_panel` 的 `live.single` 当场抛 `StateError`；就算不崩，生成器下次一跑又把它收回去。一次性待办没有系列，不受这条约束。

- [ ] **Step 1: 写失败的用例**

在 `app/test/todo_archive_screen_test.dart` 里加两条：

```dart
testWidgets('归档里的一次性待办：取消勾选，它回到主列表且不划掉', (tester) async {
  // 种 1 条已完成的**一次性**待办（date 早于今天）。展开折叠区。
  // 断言展开后那一条右边有一颗 GlassCheck，且它是勾上的。
  // 点它 → 落定后：它出现在主列表区（不在折叠区），且不带删除线。
  //       折叠区标题变成 0 条时那一条标题不再出现在折叠区里。
});

testWidgets('归档里的重复待办历史行：不许出现勾选框', (tester) async {
  // 种一个重复待办系列 + 一条已完成的历史行（seriesId != null）。
  // 展开折叠区。断言那一条所在的行里 find.byType(GlassCheck) 命中 0 次。
  // **这条是钉不变量用的**：给了勾选框，用户点一下就会让那个系列有两条
  // 未完成的行，recurring_panel 的 live.single 当场崩。
});
```

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_screen_test.dart`
Expected: 第一条 FAIL（归档行现在没有 `GlassCheck`）；第二条 PASS（现在本来就没有）。

- [ ] **Step 2: 实现**

`_eventTile` 里 `if (archived)` 那一支拆成两半：

```dart
if (archived && e.seriesId != null)
  // 归档里的**重复待办历史行**不给勾选框：它可能是旧 occurrence，而那个系列
  // 已经走到下一次了 —— 取消勾选会让一个系列出现两条未完成的行，
  // `recurring_panel._edit` 的 `live.single` 当场抛 `StateError`；就算不崩，
  // 生成器下次一跑又把它收回去。留一个与勾选框等宽的空位，免得缩进差一档。
  const SizedBox(width: _archiveCheckSlot, height: _archiveCheckSlot)
else
  GlassCheck(value: e.isCompleted, onChanged: ...),
```

`onChanged` 与主列表那一处**共用同一段**（抽一个局部函数 `_toggleDone(ref, e, v)`，两处都调它）—— 写两遍迟早走样。

- [ ] **Step 3: 跑它，确认通过**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_screen_test.dart`
Expected: PASS。

- [ ] **Step 4: 补一条几何用例（小窗不溢出）**

200×400 视口下，归档展开、里面同时有一次性和重复两种历史行 —— 断言没有溢出、标题没被挤没（`failOnOverflow` 开着就有鉴别力；再断言标题 `Text` 的实际宽度 > 0）。

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_screen_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/schedule/schedule_screen.dart app/test/todo_archive_screen_test.dart
git commit -m "feat(todo): 归档里的一次性待办给回勾选框，重复历史行仍只给删除"
```

---

### Task 4: 折叠区标题行换成胶囊

**Files:**
- Modify: `app/lib/features/schedule/schedule_screen.dart`（`_archiveHeader`）
- Test: `app/test/todo_archive_screen_test.dart`（沿用既有断言：标题文字与展开行为不变）
- Visual: `app/tool/visual/render_screens_test.dart`（既有 `54_todos_archive_open` 那两态）

**Interfaces:**
- Consumes: `GlassPill`（`core/widgets/glass_pill.dart`，`{onTap, child, accent, height}`）
- 形态：**非 accent** 的白玻璃胶囊（实心主色会跟悬浮「新建」按钮抢眼睛），内容 = `已完成 N 条` + 一个随展开转的箭头；`height: 36`
- 为什么：全 app 的入口都是胶囊（「今天」「重复待办」「管理」），就这一行是裸文字 + 小箭头 —— 与 v0.8.1「信息卡『已调整』写成裸文字」是同一个毛病。

- [ ] **Step 1: 改 `_archiveHeader`**

去掉 `GlassPressable` + `InkWell` + `Padding` 那一套，换成 `GlassPill(onTap: ..., height: 36, child: Row(...))`，`Row` 的 `mainAxisSize` 取 `min`，文字样式沿用 `rowSecondary`、颜色 `AppTokens.inkMuted(context)`，箭头仍是 `iconSm`。

- [ ] **Step 2: 跑既有用例，确认没打破行为**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_screen_test.dart`
Expected: PASS（`find.text(L10n.archivedTodos(3))` 与「点开 / 收起」那些断言都不该变）。

- [ ] **Step 3: 出图并**看图**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test tool/visual/`，然后**逐张打开** `54_todos_archive_open` 的浅色 / 深色两份（以及 `05_todos*`、`39_todos_liquid*`）。

判据（这一条是设计判断，只能看图）：那颗胶囊在浅色下**看得出是一条可点的件**而不是一块白斑；在深色下不与卡片糊在一起；小窗那两张里 `已完成 N 条` 没被挤掉。**看不顺眼就退回 `_sectionHeading` 那套（`AppTokens.sectionTitle` 的纯文字小节标题）** —— 那也是有先例的做法，别硬撑。

- [ ] **Step 4: 提交**

```bash
git add app/lib/features/schedule/schedule_screen.dart app/tool/visual/
git commit -m "feat(todo): 折叠区标题行换成胶囊，融入设计语言"
```

---

### Task 5: 勾完给一条「已划掉 · 撤销」

**Files:**
- Modify: `app/lib/core/widgets/glass_snackbar.dart`（加可选动作）
- Modify: `app/lib/core/l10n.dart`（`todoCheckedOff` / `undo`）
- Modify: `app/lib/features/schedule/schedule_screen.dart`（勾上时弹一条）
- Test: `app/test/todo_archive_screen_test.dart`

**Interfaces:**
- Produces: `void showGlassSnack(BuildContext context, String message, {IconData? icon, Color? iconColor, String? actionLabel, VoidCallback? onAction})` —— 后两个可选，**既有 8 处调用点一个字都不用改**
- Produces（l10n）：`static String get todoCheckedOff`（`已划掉` / `Marked done`）、`static String get undo`（`撤销` / `Undo`）
- 有动作时 `duration` 用 5 秒（没动作仍是 2 秒 —— 现有那 8 处行为不变）；**`Duration(seconds:)` 不在令牌守门的扫描范围**（守门只查 `Duration(milliseconds:)`），与 `glass_snackbar.dart` 现有的 `Duration(seconds: 2)` 同一处。
- 为什么做这一条：用户的原话是「刚勾错想马上改回来」。勾完那一条确实留在主列表、也确实能再点一下勾取消，但它**淡到 35% 不透明度、带删除线**，读起来是「已经处理完、别碰了」—— 一个写在提示条里的「撤销」才看得出来。

- [ ] **Step 1: 给提示条加动作**

`_GlassSnackContent` 加 `String? actionLabel` / `VoidCallback? onAction`，在 `Expanded(Text)` 之后接一颗文本按钮（走 `AppTokens.labelSecondary` + 主色，`InkWell` 带圆角水波纹，`padding` 撑到 ≥44dp 的触摸高）。`showGlassSnack` 里 `duration: actionLabel == null ? const Duration(seconds: 2) : const Duration(seconds: 5)`。

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" analyze`
Expected: 0 issues。

- [ ] **Step 2: 写失败的用例**

在 `app/test/todo_archive_screen_test.dart` 里加两条：

```dart
testWidgets('勾掉一条之后出现「撤销」，点它那一条回到未完成', (tester) async {
  // 种 2 条未完成。点第一条的勾。
  // 断言：find.text(L10n.undo) 命中；那一条带删除线。
  // 点「撤销」→ 落定后：那一条不带删除线，且库里它是未完成的。
});

testWidgets('「撤销」点下去时那一条已经被删掉：不许崩', (tester) async {
  // 勾上 → 从库里直接删掉那一行 → 再点「撤销」。
  // 断言：没有抛异常、页面还在（find.byType(ScheduleScreen) 命中）。
});
```

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_screen_test.dart`
Expected: FAIL —— `Undefined name` 或找不到「撤销」。

- [ ] **Step 3: 实现**

`schedule_screen.dart` 的 `_toggleDone`（Task 3 抽出来的那一份）里，**只在勾上时**弹：

```dart
if (v) {
  showGlassSnack(context, L10n.todoCheckedOff,
      icon: Icons.check_circle_outline,
      actionLabel: L10n.undo,
      onAction: () => _toggleDone(ref, e, false));
}
```

⚠️ **`onAction` 是异步的、而且可能在页面已经不在树上之后才跑**：`_toggleDone` 里对 `context` 的用法要过 `context.mounted`（照仓库里 `dialogCloser` 那条老规矩 —— 异步之后再用 `context` 必须先确认它还在）。**不要在这里 `Navigator.pop`。**

- [ ] **Step 4: 跑它，确认通过；再跑全套**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_screen_test.dart && "$FLUTTER_ROOT/bin/flutter" test`
Expected: 全绿。**特别确认既有那 8 处 `showGlassSnack` 的用例（若有）没变。**

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/widgets/glass_snackbar.dart app/lib/core/l10n.dart app/lib/features/schedule/schedule_screen.dart app/test/todo_archive_screen_test.dart
git commit -m "feat(todo): 勾完给一条「已划掉 · 撤销」"
```

---

### Task 6: 工装屏单、版本号、更新日志与发布

**Files:**
- Modify: `app/tool/visual/visual_screens.dart` / `render_screens_test.dart`（如需补「撤销」那一态）
- Modify: `app/pubspec.yaml:4`、`app/lib/core/app_info.dart`
- Modify: `app/lib/features/profile/app_dialogs.dart`（`_changelogZh` / `_changelogEn`）
- Modify: `AGENTS.md`（版本史 + 「关键决策与坑」里待办那一条）

- [ ] **Step 1: 工装**

给 `54_todos_archive_open` 那一族补上这次新增的三态：折叠区标题是胶囊、归档行里**一次性**（有勾）与**重复历史行**（没勾）同框、以及「撤销」那条提示条（提示条是命令式的，照 `_OverridePickerHost` 那套薄壳在 `beforeCapture` 里点出来）。**出图之后逐张看**。

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test tool/visual/`
Expected: 全绿。

- [ ] **Step 2: 与上一版基线逐张比**

用 `scripts/diff_visual.py` 比一遍改动前后。**注意跨天**：基线如果是别的日期渲的，日历那几屏会整批假差异（v0.10.18 记过这条）—— 先确认同一天再比。

- [ ] **Step 3: 版本号**

`0.11.3+150` → `0.11.4+151`，`appVersion` 同步 `'0.11.4'`。

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/app_info_test.dart`
Expected: PASS。

- [ ] **Step 4: 更新日志**

在 `_changelogZh` / `_changelogEn` **prepend** 一条 `0.11.4`，删掉最旧一条，保持**恰好 10 条**；纯文本、**不许出现 markdown 标记**（`changelog_window_test.dart` 守门）。要点：归档里的一次性待办可以直接取消勾选放回列表；勾错了当场有一条「撤销」；「已完成」那一行换成胶囊；同一天内按钟点排。

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/changelog_window_test.dart`
Expected: PASS。

- [ ] **Step 5: 全套验收**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" analyze && "$FLUTTER_ROOT/bin/flutter" test && "$FLUTTER_ROOT/bin/flutter" test tool/visual/`
Expected: analyze 0 error / 0 warning；两套全绿；**用例数只增不减**。

- [ ] **Step 6: 构建与分发**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" build apk --release --target-platform android-arm64`
复制到 `dist/倒班助手Pro-v0.11.4.apk`，用 `aapt2 dump badging` 核对 versionName `0.11.4` / versionCode `151` / 包名 `com.daoban.shiftassistantpro`。

- [ ] **Step 7: 更新 `AGENTS.md`**

版本史里补 0.11.4 那条；「关键决策与坑」里待办那一条（v0.11.3 五条约束）补上这次的改动：**取消勾选要乐观按在主列表里**（否则跳一下）、**归档只给一次性待办勾选**（重复历史行给了会撞 `live.single`）。

- [ ] **Step 8: 真机复验（有设备时）**

勾一条 → 点「撤销」→ 确认回到未完成；勾一条 → 切走再回来 → 在折叠区里 → 展开 → 点它的勾 → 确认回到主列表且不划掉；重复待办的历史行点开管理面板 → 不许崩。

- [ ] **Step 9: 提交并发布**

```bash
git add app AGENTS.md docs/superpowers/
git commit -m "chore(release): v0.11.4 —— 待办归档的三处收口"
git push origin beta
git tag v0.11.4 && git push origin v0.11.4
```

发布说明写进 `tools/gh/release-notes-v0.11.4.md`，再跑 `scripts/release.ps1 -SkipConfirm`；**发完 curl 一次 `main` 上的 `latest.json` 核对版本号**。

---

## 自查

- **对话里定的三条 → 任务**：① 胶囊 → Task 4；② 只给一次性待办勾选 → Task 3，撤销 + 修跳 → Task 2 / Task 5；③ 排序不动、同一天按钟点 → Task 1。
- **类型一致**：`splitTodos(events, sessionRows)` / `_sessionRows` / `_toggleDone(ref, e, v)` / `showGlassSnack(..., actionLabel, onAction)` / `L10n.todoCheckedOff` / `L10n.undo` 全文同名同签名。
- **Review Focus 五条**各自落在：1 → Task 2 Step 3；2 → Task 3 Step 1 第一条；3 → Task 3 Step 1 第二条；4 → Task 3 Step 4 + Task 4 Step 3；5 → Task 5 Step 2 第二条。
- **明确不做**：不改数据表；不给归档里的重复历史行勾选框；不做「按完成时间排」（用户 2026-10-11 明确要「按待办自己的日期从新到旧」）。
