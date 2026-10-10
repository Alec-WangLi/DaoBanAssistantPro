# 待办自动归档 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 待办页的主列表只列未完成的（加上本次进来之后刚勾掉的），已完成的收进底部一个默认收起的「已完成 N 条」折叠区，归档上限 100 条。

**Architecture:** 分层做：仓库层加两个纯/近纯的能力（把待办拆成两批、把超出上限的旧归档删掉），界面层只负责「主列表 + 折叠区」的排版与「本次刚勾」这一小撮会话内状态。**不改数据表**（`isCompleted` 与 `date` 已经够用）。

**Tech Stack:** Flutter / Riverpod / Drift（SQLite）。仓库层与拆分的纯函数可直接单测；界面层走 widget 测试与视觉工装。

**Spec:** `docs/superpowers/specs/2026-10-11-todo-auto-archive-design.md`

## Global Constraints

- **版本号**：`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须同步（由 `app/test/app_info_test.dart` 盯着）。本轮是**测试版**：`0.11.2+149` → `0.11.3+150`。`X.Y` 不许动。
- **分支**：测试版一律在 `beta` 上做、提交、发布（`main` 只在发正式版时收合并）。
- **验收**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿；`flutter test tool/visual/` 全绿。用例数只增不减（当前单测 **834**、工装 **359**）。
- **界面层不许写数值字面量**（`app/test/design_tokens_test.dart` 守门）：字号 / 字重 / `Color(0x…)` / `Circular(<n>)` / `Duration(milliseconds:)` / `Icon(size:)` / 非 4px 栅格的间距常量。文案一律走 `L10n`。
- **除 `core/haptics.dart` 外，任何文件不许出现 `HapticFeedback.`**；**共享组件已经震过的控件不许在调用点再补一次**（`GlassCheck` 自己发 `select()`，勾选那处**有意不加** `commit()`，见 `schedule_screen.dart:224-228` 的注释）。
- **Drift 表没有任何改动** → 不需要 `dart run build_runner build`。
- **不要跑 `dart format`**（本仓工具链的格式化器会重排整个文件）。只跑 `flutter analyze`。
- 构建环境：`source tools/build-env.sh`，然后用 `"$FLUTTER_ROOT/bin/flutter"`（`flutter` 不在 PATH 上）。

## Review Focus

以下五类输入是这份规格隐含、而**任何单一任务的测试都不会自动覆盖**的；每一类都在所属任务的步骤里有对应用例：

1. **主列表为空、归档非空**（把仅有的几条都勾完）—— 期望：那句空态还在、**折叠区仍能点开**，不能让归档被空态顶掉。
2. **勾一条日期很旧的待办**（比如去年那条）—— 期望：这一趟仍看得见它「先划掉」，**不会当场消失**（截断只在启动跑，见规格 §4）。
3. **折叠区展开后**：最后一行与悬浮「新建」按钮的关系 —— 期望删除键点得到（`kFloatingActionInset` 那条既有约束对归档区同样成立）。
4. **小窗 200×400** —— 折叠区那一行（「已完成 N 条」+ 箭头）不许溢出。
5. **重复待办的历史行**（在归档里）—— 「只删这一次」与「删整个系列」两条路径都不许把别的行带错、也不许触发「删了又回来」。

---

### Task 1: `skipRecurringOccurrence` 改成单调（水位线不倒流）

**Files:**
- Modify: `app/lib/data/app_repository.dart`（`skipRecurringOccurrence`，`app_repository.dart:922` 一带）
- Test: `app/test/recurring_repository_test.dart`

**Interfaces:**
- Produces: `Future<void> skipRecurringOccurrence(int seriesId, DateTime occ)` —— **签名不变**，语义改成 `skipThrough = max(当前值, dayNumber(occ))`（当前值为 null 时取新值）。
- 为什么先做这个：Task 4 的归档区里会出现**比当前那一条更旧**的 occurrence，而主列表里那条永远是最新的 —— 「删旧的会把水位线往回写」这条路径从前不可达，这一版第一次可达。

- [ ] **Step 1: 写失败的用例**

在 `app/test/recurring_repository_test.dart` 里加：

```dart
test('跳过一次：水位线不倒流（删归档里更旧的那条，不会把新的那条补回来）', () async {
  final t = DateTime.now();
  final today = dateOnly(t);
  final yesterday = dateOnly(DateTime(t.year, t.month, t.day - 1));
  final sid = await repo.addRecurringTodo(
      title: '每天交班', repeat: RecurRepeat.daily, startDate: yesterday);

  // 造出两行：昨天那条（会被勾掉 ⇒ 归档里那一条）与今天那条（当前那一条）。
  await repo.advanceRecurringTodos(today: yesterday);
  final older = (await repo.listEvents()).where((e) => e.seriesId == sid).single;
  await repo.setEventCompleted(older, true); // skipThrough = 昨天
  await repo.advanceRecurringTodos(today: today);
  final newer = (await repo.listEvents())
      .firstWhere((e) => e.seriesId == sid && !e.isCompleted);

  // 先删新的那条（= 主列表里「只删这一次」），再删归档里旧的那条。
  await repo.skipRecurringOccurrence(sid, newer.date);
  await repo.deleteEvent(newer);
  await repo.skipRecurringOccurrence(sid, older.date);
  await repo.deleteEvent(older);

  // 生成器再跑一次：不该把刚删掉的那条补出来。
  await repo.advanceRecurringTodos(today: today);
  expect((await repo.listEvents()).where((e) => e.seriesId == sid), isEmpty,
      reason: '水位线往回写会让刚删掉的那条又被补出来（「删了又回来」）');
});
```

- [ ] **Step 2: 跑它，确认它失败**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/recurring_repository_test.dart`
Expected: FAIL —— 那条断言报 `Expected: empty, Actual: [<今天那条>]`。

- [ ] **Step 3: 实现**

把 `skipRecurringOccurrence` 的函数体改成先读当前行再取 max（同一个 `db` 上调一次 `select`；别用 SQL 的 `max()` 表达式 —— 仓库里没有先例，读一次更直白）：

```dart
Future<void> skipRecurringOccurrence(int seriesId, DateTime occ) async {
  final row = await (db.select(db.recurringSeriesRows)
        ..where((t) => t.id.equals(seriesId)))
      .getSingleOrNull();
  if (row == null) return;
  final next = dayNumber(occ);
  final current = row.skipThrough;
  // **单调**：主列表里删的永远是最新那一次，水位线只往前走；归档里那条是更旧的
  // occurrence —— 不取 max 的话，删它会把水位线往回写，生成器于是把用户刚删掉
  // 的那条又补出来（「删了又回来」）。
  if (current != null && current >= next) return;
  await (db.update(db.recurringSeriesRows)
        ..where((t) => t.id.equals(seriesId)))
      .write(RecurringSeriesRowsCompanion(skipThrough: Value(next)));
}
```

- [ ] **Step 4: 跑它，确认通过**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/recurring_repository_test.dart test/advance_recurring_test.dart`
Expected: PASS（`advance_recurring_test` 那几条「勾掉当天那条 → 不复活」必须仍然绿）。

- [ ] **Step 5: 提交**

```bash
git add app/lib/data/app_repository.dart app/test/recurring_repository_test.dart
git commit -m "fix(recurring): 跳过一次改成单调 —— 水位线不能倒流"
```

---

### Task 2: 拆分纯函数与上限常量

**Files:**
- Create: `app/lib/data/todo_archive.dart`
- Test: `app/test/todo_archive_test.dart`

**Interfaces:**
- Produces:
  - `const int kArchivedTodoLimit = 100;`
  - `class TodoSplit { const TodoSplit({required this.active, required this.archived}); final List<ScheduleEvent> active; final List<ScheduleEvent> archived; }`
  - `TodoSplit splitTodos(List<ScheduleEvent> events, Set<int> justCompleted)`
- **注意 `ScheduleEvent` 是 Drift 生成的行类**（`data/app_database.dart` 的 `ScheduleEvents` 表 → `app_database.g.dart`），所以这个文件放 **`data/`**，不放 `domain/`（`domain/` 现在不依赖数据层，别破这个界限）。

语义（规格 §3）：
- `active` = `!e.isCompleted || justCompleted.contains(e.id)`，**保持入参顺序**（入参是 `watchEvents()` 的日期升序 —— 刚勾的那条因此停在原地）。
- `archived` = 补集，按 **`date` 降序**（同一天按 `id` 降序兜底）。

- [ ] **Step 1: 写失败的用例**

新建 `app/test/todo_archive_test.dart`：

```dart
// 拆分的纯函数：主列表 = 未完成 + 本次刚勾的；折叠区 = 其余已完成，按日期降序。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_database.dart';
import 'package:shiftassistantpro/data/todo_archive.dart';

ScheduleEvent _e(int id, DateTime date, {bool done = false}) => ScheduleEvent(
      id: id, title: 't$id', date: date, isCompleted: done,
      alarmEnabled: false, createdAt: DateTime(2026));

void main() {
  test('未完成的全在主列表、顺序不变；已完成的进折叠区、按日期降序', () {
    final events = [
      _e(1, DateTime(2026, 1, 1), done: true),
      _e(2, DateTime(2026, 1, 2)),
      _e(3, DateTime(2026, 1, 3), done: true),
      _e(4, DateTime(2026, 1, 4)),
    ];
    final s = splitTodos(events, const {});
    expect(s.active.map((e) => e.id).toList(), [2, 4]);
    expect(s.archived.map((e) => e.id).toList(), [3, 1],
        reason: '折叠区是「回头看一眼」，最近做完的排最前');
  });

  test('本次刚勾的留在主列表里、且停在原来的位置', () {
    final events = [
      _e(1, DateTime(2026, 1, 1), done: true),
      _e(2, DateTime(2026, 1, 2)),
      _e(3, DateTime(2026, 1, 3), done: true),
    ];
    final s = splitTodos(events, const {1});
    expect(s.active.map((e) => e.id).toList(), [1, 2],
        reason: '刚勾的那条还在主列表，且按日期排在 2 前面 —— 不能跳到末尾');
    expect(s.archived.map((e) => e.id).toList(), [3]);
  });

  test('空表不炸', () {
    final s = splitTodos(const [], const {});
    expect(s.active, isEmpty);
    expect(s.archived, isEmpty);
  });
}
```

- [ ] **Step 2: 跑它，确认它失败（文件不存在）**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_test.dart`
Expected: FAIL —— `Error: Couldn't resolve the package 'shiftassistantpro/data/todo_archive.dart'` / `Undefined name 'splitTodos'`。

- [ ] **Step 3: 实现 `app/lib/data/todo_archive.dart`**

按上面的语义写 `kArchivedTodoLimit`、`TodoSplit`、`splitTodos`。文件头写清楚两条：**为什么 `active` 要保持入参顺序**（刚勾的那条停在原地，不跳）、**为什么 `archived` 是降序**。顺手在 `kArchivedTodoLimit` 上写一句「这不是设置项，100 是用户点名要的值」。

- [ ] **Step 4: 跑它，确认通过**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/data/todo_archive.dart app/test/todo_archive_test.dart
git commit -m "feat(todo): 待办拆成主列表与归档两批的纯函数"
```

---

### Task 3: 截断到 100 条，并在启动时就绪闸里跑一次

**Files:**
- Modify: `app/lib/data/app_repository.dart`（新增 `pruneArchivedTodos`）
- Modify: `app/lib/features/home/home_shell.dart:294` 一带（启动闸里加一次调用）
- Test: `app/test/todo_archive_test.dart`、`app/test/home_shell_nav_test.dart`

**Interfaces:**
- Consumes: `kArchivedTodoLimit`（Task 2）
- Produces: `Future<int> pruneArchivedTodos({int keep = kArchivedTodoLimit})` —— 返回删掉的行数。

语义：把 `isCompleted == true` 的行按 **`date` 升序**排，保留**最后** `keep` 条、删掉其余。**只许碰 `isCompleted == true` 的行**（规格 §2 的反目标）。

- [ ] **Step 1: 写失败的用例（仓库层）**

在 `app/test/todo_archive_test.dart` 里加（照 `recurring_repository_test.dart` 的夹具：`AppDatabase.forTesting(NativeDatabase.memory())` + `repo.ensureSeeded()`）：

```dart
test('截断到 100：丢日期最旧的那些，一条未完成都不许少', () async {
  // 105 条已完成（日期自 2026-01-01 起递增）+ 3 条未完成（日期最新）。
  for (var i = 0; i < 105; i++) {
    final e = await repo.addEvent(title: 'done$i', date: DateTime(2026, 1, 1 + i));
    await repo.setEventCompleted(e, true);
  }
  for (var i = 0; i < 3; i++) {
    await repo.addEvent(title: 'open$i', date: DateTime(2026, 6, 1 + i));
  }
  final removed = await repo.pruneArchivedTodos();
  expect(removed, 5);
  final all = await repo.listEvents();
  expect(all.where((e) => !e.isCompleted), hasLength(3),
      reason: '截断只许碰已完成的行');
  final done = all.where((e) => e.isCompleted).toList();
  expect(done, hasLength(100));
  expect(done.map((e) => e.title).toSet().contains('done0'), isFalse,
      reason: '丢的必须是日期最旧的那几条');
});

test('截断绝不碰未完成的行 —— 哪怕它比所有已完成的行都旧', () async {
  await repo.addEvent(title: '很旧但没做', date: DateTime(2020, 1, 1));
  for (var i = 0; i < 101; i++) {
    final e = await repo.addEvent(title: 'd$i', date: DateTime(2026, 1, 1 + i));
    await repo.setEventCompleted(e, true);
  }
  await repo.pruneArchivedTodos();
  final all = await repo.listEvents();
  expect(all.where((e) => !e.isCompleted).single.title, '很旧但没做');
  expect(all.where((e) => e.isCompleted), hasLength(100));
});
```

- [ ] **Step 2: 跑它，确认它失败**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_test.dart`
Expected: FAIL —— `Undefined name 'pruneArchivedTodos'`。

- [ ] **Step 3: 实现 `pruneArchivedTodos`**

在 `AppRepository` 里实现（读全部已完成行 → 排序 → 删超出部分；用一个事务）。给函数写一段注释说明**为什么按 `date` 而不是「完成时间」**（表里没有完成时间，也不为它加列 —— 规格 §2 明说不改表）。

- [ ] **Step 4: 跑它，确认通过**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_test.dart`
Expected: PASS。

- [ ] **Step 5: 写启动闸的用例**

在 `app/test/home_shell_nav_test.dart` 里加一条：种 **105 条已完成**（照 Step 1 的写法），挂 `HomeShell`，落定后断言库里只剩 100 条已完成。（这个文件里已有挂整个壳的夹具，照抄它的 `mount`。）

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/home_shell_nav_test.dart`
Expected: FAIL —— 仍是 105 条（`home_shell` 还没调）。

- [ ] **Step 6: 在启动闸里加调用**

`app/lib/features/home/home_shell.dart:294` 那句 `advanceRecurringTodos` **之后**加一行 `await repo.pruneArchivedTodos();`，并补一句注释：为什么放在启动闸、而**不**放在 `setEventCompleted` 里（勾一条去年完成过的待办时会被当场删掉，「先划掉再收走」那一趟反馈就没了 —— 规格 §4）。

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/home_shell_nav_test.dart`
Expected: PASS。

- [ ] **Step 7: 跑全套并提交**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" analyze && "$FLUTTER_ROOT/bin/flutter" test`
Expected: 0 issues；全绿。

```bash
git add app/lib/data/app_repository.dart app/lib/features/home/home_shell.dart app/test/todo_archive_test.dart app/test/home_shell_nav_test.dart
git commit -m "feat(todo): 归档超上限时丢最旧的，启动时就绪闸裁一次"
```

---

### Task 4: 待办页 —— 折叠区、本次刚勾、空态共存

**Files:**
- Modify: `app/lib/core/l10n.dart`（`noEvents` 一带，`l10n.dart:260`）
- Modify: `app/lib/features/schedule/schedule_screen.dart`（`_eventTile` 与 `build` 的列表那一段）
- Test: Create `app/test/todo_archive_screen_test.dart`

**Interfaces:**
- Consumes: `splitTodos` / `kArchivedTodoLimit`（Task 2）、`pruneArchivedTodos`（Task 3）
- Produces（l10n）：`static String archivedTodos(int n) => t('已完成 $n 条', '$n completed');`

界面结构（规格 §6）：
- `_ScheduleScreenState` 加 `final Set<int> _justCompleted = {};` 与 `bool _archiveOpen = false;`。
- `_eventTile` 的 `GlassCheck.onChanged`：**先** `setState(() => v ? _justCompleted.add(e.id) : _justCompleted.remove(e.id));`，**再** `await repo.setEventCompleted(e, v)`。**必须是乐观的**：等 `await` 完再放，流会先吐一帧「已完成、又不在集合里」，那一条会离开主列表再被 `setState` 加回来 —— 正是规格 §2 反目标里那条「勾一条整页跳一下」。
- 列表改成 `ListView`（不是 `ListView.builder`，因为要挂尾部）：`split.active` 的行 → 若 `split.active.isEmpty` 且 `split.archived.isNotEmpty`，插一句 `L10n.noEvents`（沿用现有那份 `Padding(horizontal: 24)` + 居中 + `rowSecondary` + `inkMuted` 的配方，只是从「整块居中」改成「列表里的一项」）→ 若 `split.archived.isNotEmpty`，插折叠区：一行标题（`L10n.archivedTodos(n)` + 一个随 `_archiveOpen` 转的箭头，整行可点）→ `_archiveOpen` 时逐个画归档行。
- **归档行不画 `GlassCheck`**（归档区不给取消勾选，规格 §5）：左侧留一个与勾选框等宽的空位，免得文字缩进跳一档；其余（标题划掉 + 淡、副标题、尾部删除键）与主列表行**同一套配方**。删除键的语义照抄主列表那一处（一次性直接删；重复项走 `_askDeleteRecurring`）。
- 整页一条待办都没有时（`events.isEmpty`）**保持现状**（整块居中那句），不进列表分支。

- [ ] **Step 1: 加 l10n 键**

在 `l10n.dart` 的 `noEvents` 附近加 `archivedTodos(int n)`。中英语序不同，整串交给 `t()`（别拼前缀）。

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" analyze`
Expected: 0 issues。

- [ ] **Step 2: 写失败的用例**

新建 `app/test/todo_archive_screen_test.dart`，夹具照抄 `recurring_screen_test.dart` 的头部（`_settle` / `_dispose` / `_stubPluginChannels` / `NativeDatabase.opened(sqlite3.openInMemory())` / `ensureSeeded` / `mount`）。用例：

```dart
testWidgets('已完成的进折叠区，默认收起；标题里的数字与展开后的行数一致', ...);
// 种 2 条未完成 + 3 条已完成（用 setEventCompleted 造）
// 断言：主列表里看不到那 3 条的标题；find.text(L10n.archivedTodos(3)) 命中
// 点它 → 3 条标题都出现；再点 → 收起

testWidgets('勾掉一条：它仍在主列表里、且停在原位（划掉）', ...);
// 种 2 条未完成（日期 1/2、1/3）。点第一条的 GlassCheck
// 断言：第一条仍在主列表（它在 find.byType(GlassTile) 的第 0 个），且它带删除线
//      折叠区标题是 archivedTodos(0) 或干脆不出现

testWidgets('主列表为空、归档非空：那句提示还在，折叠区仍能点开', ...);
// 种 2 条已完成（且都不是本次勾的）
// 断言：find.text(L10n.noEvents) 命中；折叠区标题命中；点开能看到那 2 条

testWidgets('走 HomeShell 切走再切回：刚勾的那条进了折叠区', ...);
// 见下面的说明 —— 这条要挂整个壳
```

**第 4 条为什么必须走 `HomeShell`**：「下次进来才收走」唯一靠的是 `PageView` 会把离屏那一页 dispose（v0.10.22 明确决定**不做** tab 保活），而上面三条都是**直接挂 `ScheduleScreen`**、观察不到这件事。将来谁把保活加回来，只有这条用例会红。写法照 `app/test/home_shell_nav_test.dart` 里已有的整壳夹具：挂壳 → 切到待办页 → 点勾 → 切到别的 tab → 切回待办页 → 断言那条已在折叠区。

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_screen_test.dart`
Expected: FAIL（折叠区还不存在）。

- [ ] **Step 3: 实现界面**

按上面的结构改 `schedule_screen.dart`。两点容易写错，写进注释：
- `_justCompleted` 的增删必须**在 `await` 之前**（乐观），否则那条会闪一下再回来。
- 归档行**不画 `GlassCheck`** —— 这一区不给取消勾选（规格 §5 有理由：归档里的行可能是旧 occurrence，取消勾选会让一个系列出现两条未完成的行，管理面板的 `live.single` 会当场抛异常）。

- [ ] **Step 4: 跑它，确认通过；再跑全套**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_screen_test.dart && "$FLUTTER_ROOT/bin/flutter" test`
Expected: 全绿。

- [ ] **Step 5: 顺手补一条几何用例**

「折叠区展开后最后一行不被悬浮按钮压住」—— 在 `todo_archive_screen_test.dart` 里照 `recurring_screen_test.dart` 那两条「滑到底…真的点得到」的写法（几何 + 命中测试）。**夹具条数要真的撑破视口**，否则那条断言永远为真。

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/todo_archive_screen_test.dart`
Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add app/lib/core/l10n.dart app/lib/features/schedule/schedule_screen.dart app/test/todo_archive_screen_test.dart
git commit -m "feat(todo): 已完成的收进底部折叠区，勾完先划掉再收走"
```

---

### Task 5: 视觉工装屏单与基线

**Files:**
- Modify: `app/tool/visual/visual_screens.dart`（`05_todos` / `24_todos_recurring` 一带）
- Modify: `app/tool/visual/visual_harness.dart`（种子，如需）

- [ ] **Step 1: 给折叠区补两态**

`05_todos` 的种子里若没有已完成的行，加两条；并加一屏（或给既有屏加一个变体）把折叠区**展开**那一态拍出来。归档行与主列表行长得不一样（没有勾选框），只有出图能看。

- [ ] **Step 2: 出图并**看图**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test tool/visual/`
Expected: 全绿。然后**逐张打开** `05_todos*` / `24_todos_recurring*` / `39_todos_liquid*` 的浅色与深色两份，确认：折叠区那一行没溢出、归档行不像主列表行、小窗那两张（200×400）排版没坏。

- [ ] **Step 3: 与上一版基线逐张比**

用 `scripts/diff_visual.py` 比一遍改动前后（找不到上一版基线就先把「该变的屏」列出来，逐张说明为什么该变）。**注意**：这几屏的种子库里带已完成的行，它们从主列表挪进折叠区 ⇒ 图**必然**变；要确认的是「变的只有该变的」。

- [ ] **Step 4: 提交**

```bash
git add app/tool/visual/
git commit -m "test(visual): 待办归档折叠区的收起 / 展开两态"
```

---

### Task 6: 版本号、更新日志与发布

**Files:**
- Modify: `app/pubspec.yaml:4`、`app/lib/core/app_info.dart:10`
- Modify: `app/lib/features/profile/app_dialogs.dart`（`_changelogZh` / `_changelogEn`）
- Modify: `AGENTS.md`（版本史 + 「关键决策与坑」里待办那一条）

- [ ] **Step 1: 版本号**

`0.11.2+149` → `0.11.3+150`，`appVersion` 同步 `'0.11.3'`。

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/app_info_test.dart`
Expected: PASS。

- [ ] **Step 2: 更新日志**

在 `_changelogZh` / `_changelogEn` **prepend** 一条 `0.11.3`，删掉最旧一条，保持**恰好 10 条**；纯文本、**不许出现 markdown 标记**（`changelog_window_test.dart` 守门）。要点：待办勾完不再堆在列表里、收进底部「已完成」折叠区；归档最多留 100 条、更早的自己消失；顺带修好一处「删掉一条重复待办、它又回来了」。

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/changelog_window_test.dart`
Expected: PASS。

- [ ] **Step 3: 全套验收**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" analyze && "$FLUTTER_ROOT/bin/flutter" test && "$FLUTTER_ROOT/bin/flutter" test tool/visual/`
Expected: analyze 0 error / 0 warning；两套全绿；用例数只增不减。

- [ ] **Step 4: 构建与分发**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" build apk --release --target-platform android-arm64`
复制到 `dist/倒班助手Pro-v0.11.3.apk`，用 `aapt2 dump badging` 核对 versionName `0.11.3` / versionCode `150` / 包名 `com.daoban.shiftassistantpro`。

- [ ] **Step 5: 更新 `AGENTS.md`**

版本史里补 0.11.3 那条；「关键决策与坑」里待办相关那一条补上归档的两条硬约束（**截断只许碰已完成的行**、**归档区不给取消勾选**及其理由）。

- [ ] **Step 6: 真机复验（有设备时）**

勾几条、退出、重进：确认它们在折叠区里、展开看得到、删除键点得到；把仅有的几条都勾完，确认那句空态还在且折叠区仍能点开。

- [ ] **Step 7: 提交并发布**

```bash
git add app AGENTS.md docs/superpowers/
git commit -m "chore(release): v0.11.3 —— 待办自动归档"
git push origin beta
git tag v0.11.3 && git push origin v0.11.3
```

发布说明写进 `tools/gh/release-notes-v0.11.3.md`，再跑 `scripts/release.ps1 -SkipConfirm`；**发完 curl 一次 `main` 上的 `latest.json` 核对版本号**。

---

## 自查

- **规格覆盖**：§1/§2 → 全局约束 + Task 2/3 的反目标断言；§3 → Task 2（拆分）+ Task 4（乐观插入、切 tab）；§4 → Task 3；§5 → Task 1（水位线单调）+ Task 4（归档行不画勾选框）；§6 → Task 4（l10n、空态共存）+ Task 5（出图）；§7 → Task 1/2/3/4 各自的用例；§8 → 各任务内已就地定下（拆分放 `data/`、上限常量落点、折叠区按钮只删不勾）。
- **类型一致**：`splitTodos` / `TodoSplit` / `kArchivedTodoLimit` / `pruneArchivedTodos` / `archivedTodos(int)` / `_justCompleted` / `_archiveOpen` 全文同名同签名。
- **Review Focus 五条**各自落在：1 → Task 4 第 3 条用例；2 → Task 3（截断只在启动）+ Task 4 第 2 条用例；3 → Task 4 Step 5 的几何用例；4 → Task 5 看图；5 → Task 1 的仓库用例 + Task 4 删除键沿用既有语义。
