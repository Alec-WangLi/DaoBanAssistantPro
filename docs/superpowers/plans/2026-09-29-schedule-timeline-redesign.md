# 排班时段重做 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「生效时段」从「某一套方案的属性」改成**一条时间线**：段之间不许重叠（界面挡在保存前），没被段覆盖的日子归「其余时间」那一套（可以设成「无」）；日历上那个「切换排班」按钮换成只读的「排班时段」总览。

**Architecture:** 存储**完全不动**（段仍是 `effectiveFrom`/`effectiveTo`，其余时间仍是 `isCurrent`），所以 `ScheduleChain` / 日历 / 闹钟 / 桌面小组件那条链路一行都不用改。改的是三处：**界面**（时段从编辑器搬到排班管理页）、**一条规则**（重叠从「后者赢」变成「不许有」，解析退化成唯一解 + 一条只防脏数据的 tiebreak）、**一次数据规整**（v0.9.12 已经发出去过，用户库里可能躺着重叠的段，迁移 12 → 13 按旧解析结果等价改写）。

**Tech Stack:** Flutter / Dart 3、Riverpod、Drift（SQLite，`build_runner` 代码生成）、纯 Dart 领域层。

**Spec:** [docs/superpowers/specs/2026-09-29-schedule-timeline-redesign-design.md](../specs/2026-09-29-schedule-timeline-redesign-design.md)

---

## ⚠️ 2026-09-29 修订（实施到 Task 3 时发现，已拍板）

**原计划的「存储完全不动」不成立。** 旧规则（起点最晚的赢）能表达一种**一对起止
装不下**的形状：外段被内段截断之后还要接着用 —— 例如 `B[7/1, ∞)` 与
`C[9/1, 9/30]`，用户看到的是「7/1–8/31 归 B、9 月归 C、10/1 起又归 B」，而 B 得
出现在**两段**上。这不是迁移的锅，是模型的限制：**「9 月临时换别的班表、之后换
回来」在原模型下也做不到**。

**已拍板改为：段独立成一张表**（无损、一套方案可以出现在多段上）。本节的改动
**取代**下面各任务里的相应内容；其余部分（界面、文案、日历按钮、工装、收尾）不变。

### 改动一：新表 `ScheduleSpanRows`（schema 12 → 13）

```dart
/// 时间线上的一段。**表名带 `Rows` 后缀**：drift 按表名生成行类，叫
/// `ScheduleSpans` 会生成 `ScheduleSpan`、与领域层那个撞名
/// （`ShiftClassRows` / `RecurringSeriesRows` 是同一回事）。
class ScheduleSpanRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get scheduleId => integer()();                    // → shift_schedule_rows.id
  DateTimeColumn get startDate => dateTime().nullable()();    // null = 不限起点
  DateTimeColumn get endDate => dateTime().nullable()();      // null = 一直持续
}
```

`ShiftScheduleRows.effectiveFrom` / `effectiveTo` **作废并删掉**（不留死列，照 v10
删 `alarm_minute` 的先例）。`@DriftDatabase` 的 tables 列表加上新表，
`schemaVersion => 13`。

### 改动二：迁移按「边界切、逐段求胜者、再合并」

**逐区间重放旧规则**（覆盖那天的段里起点最晚的赢，并列按 id 大者胜），所以天然
无损、不必为「装不下的形状」做特判：

1. 读出带时段的方案行（按 id 升序）。没有就只建表、删列。
2. 收集**边界点**：每段的 `from`，以及每段 `to` 的**次日**（`to == null` 跳过）。
   起点为空用 `-∞` 哨兵、终点为空用 `+∞`。
3. 边界点去重排序 → 区间 `[pₖ, p₊₁ − 1]`。
4. 每个区间求胜者；**没人覆盖的区间跳过**（那些天归「其余时间」）。
5. **合并相邻同胜者的区间**成一段 —— B 因此会产生两段。
6. 逐段 INSERT；再 `TableMigration(shiftScheduleRows)` 删掉那两列。

> ⚠️ **从 v11 及更早升上来时那两列还不存在**（它们是 v12 加的）：`from < 12` 的
> 分支先跑、把列加上，才轮到 `from < 13`。所以读列之前先判 `from >= 12`（照
> v9→v10 那次「⚠️ 只有 v6 及以后才有 shift_class_rows」的先例）。

### 改动三：`ScheduleSpan` 带两个 id

```dart
class ScheduleSpan {
  /// **段**的行 id：编辑 / 删除 / `conflictingSpans` 判「是不是自己」。
  final int? id;
  /// **方案**的行 id：`scheduleIdOn(day)` 返回它（按天改班要用）。
  final int? scheduleId;
  final ShiftSchedule schedule;
  final DateTime? from;
  final DateTime? to;
}
```

`ScheduleChain._resolve` 返回 `(ShiftSchedule?, int?)` 里的第二个从「段的 id」
改成「**方案的 id**」（`best?.scheduleId ?? fallbackId`）—— 这是最容易搞混的一处，
混了的症状是**按天改班记到错的方案名下**（不生效也不报错）。

### 改动四：仓库层的段 CRUD

新增：`addSpan({scheduleId, from, to}) -> Future<int>`、`updateSpan(spanId, {from, to})`、
`deleteSpan(spanId)`。**删掉** `setScheduleSpan` / `getScheduleSpan`。

`deleteSchedule` 要**连带删掉该方案的段**（照它删班次 / 周期的既有做法）；
`clearAll` 同理。两列的写入要**显式构造 `Value`**（`Value.absent()` 清不回 null）。

### 改动五：装配

`assembleSchedules` 多读一张 `scheduleSpanRows`，按 `scheduleId` 关联到方案；
**关联不到的段跳过**（方案被删的脏数据）。`watchActiveSchedule` 的触发源**加上
`select(scheduleSpanRows).watch()`**（漏了就是「改了段、日历不动」—— 与当年
「覆盖表没挂 watch」同一条）。

### 任务拆分的调整

**原来的 Task 3 + Task 4 合成一个「数据层」任务，一次做完、一笔提交。** 理由是
原子性：schemaVersion 只有一个，`if (from < 13)` 那一段必须**同时**建表、搬数据、
删列；而一旦两列没了，装配 / 领域层 / 仓库那几处**必须同时**改成读段表，否则编译
不过。拆开只会造出「编译不过」或「两个真相来源」的中间态。

| 原 | 现 |
|---|---|
| Task 3 迁移（纯数据） + Task 4 仓库与文案 | **Task 3（新）**：数据层一次做完 —— 新表 + 删列 + 边界切迁移 + `ScheduleSpan.scheduleId` + 装配 + 段 CRUD + `setRemainingNone` + 删掉 `setScheduleSpan`/`getScheduleSpan`（含迁移与装配的用例）<br>**Task 4（新）**：只剩标签与文案（`effectiveRangeLabel` 两种说法、`spanRangeLabel`、l10n 增删） |
| Task 5 / 6 / 7 / 8 / 9 | 序号不变（那一节的**行来源**从「方案行」改成「段表的行」，其余描述照旧） |

**Task 5 里那一节的实现要点补两条**：① 行的数据源是 `scheduleSpanRows`，
`label` 用 `spanRangeLabel`（由段的起止算），`value` 是它指向的**方案名**；
② 「添加时段」先选方案、再选起止，走 `addSpan`。

---

## Global Constraints

- **版本号形如 `X.Y.Z+build`：`X.Y` 由用户决定，AI 只能改最后一位 `Z`（`build` 同步 +1）**；`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 必须一致（`app/test/app_info_test.dart` 把关）。
- **`flutter analyze` 必须 0 error / 0 warning**；**`flutter test` 必须全绿**（当前 **494** 条）；视觉工装另算（当前 **232** 条）。
- **绝对不许跑 `dart format`**。只跑 `flutter analyze`。
- **改 Drift 表后必须重生成**：`dart run build_runner build --delete-conflicting-outputs`。（本轮**没有**表结构改动，但迁移函数写在 `app_database.dart` 里，改完仍要跑一次确认生成代码没被带偏。）
- **测试版在 `beta` 分支上做、提交、发布**。
- **日期比较一律走 `dayNumber` / `isSameDay`**；日期算术一律 `DateTime(y, m, d ± n)`，不用 `Duration(days:)`。
- **界面层只写角色令牌**（`fontSize:` / `fontWeight:` / `circular(<数字>)` / `Duration(milliseconds:)` / `Color(0x…)` / 4px 栅格外间距都会被 `design_tokens_test` 打红）；新界面抄最近的同类件配方，能用共享件就用共享件（`GlassPill` / `GlassTile` / `GlassPressable` / `GlassActionButton` / `showGlassDatePicker` / `showGlassOptionPicker` / `showGlassSnack`）。
- **触觉只在「状态真的变了」时发**，且不许给已经自动发过的控件再补一记（`GlassSwitch` / `GlassSegment` / `GlassChoiceChip` / 四个选择器提交点，见 `core/haptics.dart` 顶上那份名单）。
- **新界面一律补进视觉工装屏单**。
- 所有命令在 **`app/` 目录**下执行。

## Review Focus

这五类输入或失败模式是 spec 隐含、但单看某个任务的测试不一定照得出来的（用例都分派到了下面各自的任务里）：

1. **迁移必须与 v0.9.12 的旧解析结果逐条等价** —— 用户已经在用那个版本，升级后**一天都不能变**。这是整轮唯一会动用户既有数据的操作。→ Task 3。
2. **「其余时间」为 null 是新的合法状态** —— 日历 / 闹钟 / 小组件每一处都要能接住，否则症状是「某天整片空白但没人知道为什么」或者更糟的崩溃。→ Task 2、Task 7。
3. **重叠必须挡在保存之前，而且要说出撞了谁** —— 只拒绝、不说清，用户只能靠猜（这正是 v0.9.12 那个「感觉有点乱」的同一个根源）。→ Task 6。
4. **删掉一套方案之后「其余时间」不能悬空** —— 自动接管那条既有行为必须保住，否则删掉默认那套会让整张日历变空。→ Task 4。
5. **编辑器那一节删干净** —— 状态字段、校验、保存路径里的写入、以及那一节的用例，漏一处就是「死代码 + 一条永远跑不到的分支」。→ Task 1。

---

## 文件结构

**修改**

| 文件 | 改什么 |
|---|---|
| `app/lib/features/calendar/schedule_editor_screen.dart` | 删掉「生效时段」一节与它牵着的全部东西（状态 / 校验 / 保存路径 / 文档） |
| `app/lib/domain/schedule_chain.dart` | `overlappingSpans` → `conflictingSpans`（用途从「提示」改成「禁止」）；注释订正（不重叠 → 唯一解 + 防御 tiebreak） |
| `app/lib/data/app_database.dart` | 迁移 12 → 13（纯数据规整，无 DDL） |
| `app/lib/data/app_repository.dart` | 新增 `setRemainingNone()` |
| `app/lib/features/calendar/schedule_span_label.dart` | 两种「没设时段」的说法改成「其余时间」/「未使用」 |
| `app/lib/features/calendar/schedule_management_screen.dart` | 顶部新增「排班时段」一节（列表 + 设为无 + 添加/编辑弹层 + 重叠校验） |
| `app/lib/features/calendar/calendar_screen.dart` | 按钮换成只读总览、删 `_switchSchedule`、整月无班次时给一句指路 |
| `app/lib/core/l10n.dart` | 增删文案 |
| `app/tool/visual/visual_screens.dart` + `visual_harness.dart` | 屏单调整 + 种子 |

**新建**

| 文件 | 职责 |
|---|---|
| `app/test/migration_v12_to_v13_test.dart` | 重叠规整的三种形态 + 「本来就不重叠的库一行都不改」 |
| `app/test/schedule_span_conflict_test.dart` | `conflictingSpans` 的边界 |
| `app/test/schedule_timeline_test.dart` | 排班管理页那一节：列表 / 设为无 / 添加 / 重叠不让存 / 日历弹层 |

**不动**：`schedule_chain.dart` 的解析主路径、`info_card_metrics.dart`、`widget_snapshot.dart`、`alarm_service.dart`、整个 Kotlin 侧、`ShiftAlarmOverrides` / `ShiftDayOverrides`。

---

## Task 1: 先把编辑器那一节拆掉

**Files:**
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`
- Modify: `app/test/schedule_editor_test.dart`（删掉 4 条用例）
- Modify: `app/lib/core/l10n.dart`（删掉只有这一节在用的文案）

**Interfaces:**
- 无新增。**删掉**的是 `_effectivePeriodCard` / `_effectiveFrom` / `_effectiveTo` / `_warnIfSpanOverlaps` 与保存路径里的 `setScheduleSpan` 调用。

> **为什么先做这个**：`setScheduleSpan` / `getScheduleSpan` 留在仓库里（下一批 UI 还要用），但编辑器是**目前唯一**的调用点。「先拆旧界面、再改领域层」的顺序能保证每一次提交都能编译、都能跑，不会出现「改完名字编辑器还指着旧函数」的中间态。

- [ ] **Step 1: 删掉那一节**

在 `schedule_editor_screen.dart` 里删掉：

1. 状态字段：

```dart
  DateTime? _effectiveFrom;
  DateTime? _effectiveTo;
```

（连同它们上面那段「三种含义要分清」的文档注释）

2. `_load` 里读时段的这几行：

```dart
    // 生效时段是**库行**上的两列，领域模型（`ShiftSchedule`）不带，所以按行 id
    // 单独读一次。读不到（id 为 null）就当作「没设过」。
    DateTime? spanFrom;
    DateTime? spanTo;
    if (id != null) {
      final span = await repo.getScheduleSpan(id);
      spanFrom = span.from;
      spanTo = span.to;
    }
```

以及 `setState` 里的 `_effectiveFrom = spanFrom;` / `_effectiveTo = spanTo;`。

> `_load` 里那个 `int? id` 与 `repo` 变量如果因此变成未使用，**一并删掉**（`repo` 在 `_load` 里只被时段那一处用；`id` 也一样）。

3. `_effectivePeriodCard` 整个方法，以及 `build` 里调用它的那两行：

```dart
                    // 生效时段在 `if (!_followHoliday)` **外面**：空白表方案同样
                    // 可以有生效时段（它是方案的元信息，与班次 / 周期无关）。
                    _effectivePeriodCard(context),
```

4. `_save` 里的校验、写时段、重叠提示：

```dart
    // 校验放在写库**之前**：开始晚于结束时直接打回，别写进去再让用户自己发现。
    final from = _effectiveFrom;
    final to = _effectiveTo;
    if (from != null && to != null && dayNumber(from) > dayNumber(to)) {
      showGlassSnack(context, L10n.effectiveRangeInvalid,
          icon: Icons.error_outline);
      return;
    }
```
```dart
      // 生效时段**单独写**：……
      await repo.setScheduleSpan(id, from: _effectiveFrom, to: _effectiveTo);
```
```dart
      // 重叠提示放在 `pop` 之前：……
      await _warnIfSpanOverlaps(id);
```

5. `_warnIfSpanOverlaps` 整个方法。

6. 只在那一节用到的 import：`schedule_chain.dart`（`ScheduleSpan` / `overlappingSpans` 都只在那儿用）、`ScheduleChain` 相关。

**保存路径改完应该是这样**（保留那段「重排读的是整条链」的注释）：

```dart
      final repo = ref.read(appRepositoryProvider);
      await repo.saveSchedule(
            scheduleId: widget.scheduleId ??
                ref.read(activeScheduleProvider).valueOrNull?.currentScheduleId,
            name: name,
            anchorDate: anchor,
            classes: _classes,
            cycle: _cycle,
            makeCurrent: widget.scheduleId == null,
            teamCount: _teamCount,
            teamNames: _teamNames,
            ourTeamIndex: _ourTeamIndex,
            teamOffsets: _teamOffsets,
          );
      // 重排读的是**整条链**（`rescheduleAll` → `getActiveSchedules`），链上既有
      // 刚编辑的这套、也有当前方案 —— 所以「编辑的是一套非当前方案」这条路径
      // 本来就对，不必再特别处理。
      await AlarmService.rescheduleAll(repo);
      // 返回 true 告知上层「已保存」，由上层弹提示（避免 SnackBar 随页面一起销毁）
      if (mounted) Navigator.of(context).pop(true);
```

> ⚠️ 原文里 `final id = await repo.saveSchedule(...)` 的返回值**只给写时段那一处用**，删掉写入之后它就没用了 —— 改回不接返回值，别留一个未使用的局部变量。

- [ ] **Step 2: 删掉那一节的用例**

`app/test/schedule_editor_test.dart` 里删掉 4 条：`生效时段：库里设过就读得进来，保存时原样写回去` / `生效时段：点「从」选一天，保存时带上它、结束仍为空` / `生效时段：开始晚于结束 → 不保存，并给一句说明` / `生效时段：与别的方案重叠 → 保存照旧，但多一句提示`。

同时删掉假仓库里只为它们存在的成员：`persistedFrom` / `persistedTo` / `spanCalled` / `spanId` / `spanFrom` / `spanTo` / `getScheduleSpan` / `setScheduleSpan` / `spanRows` / `listSchedules`，以及 `_pumpEditor` 上那三个只为时段加的参数（`spanFrom` / `spanTo` / `spanRows`）。

> `listSchedules` 的覆写**也一起删**：它当时就是为重叠提示提供数据的，提示没了它就没用了；而**不覆写**它会走到基类实现（打测试用内存库、表在、空结果），不会报错。

- [ ] **Step 3: 删掉只给那一节用的文案**

`l10n.dart` 里删掉：`effectivePeriod` / `effectiveFrom` / `effectiveTo` / `effectiveUnbounded` / `effectiveForever` / `effectiveRangeInvalid` / `effectiveOutsideHint` / `overlappingSpan`。

> ⚠️ **别顺手把这三个也删了**：`effectiveFromDate` / `effectiveUntilDate` / `effectiveRangeSpan` —— 它们被 **`effectiveRangeLabel`**（`schedule_span_label.dart`，**保留**的那个函数）用着，而且 Task 5 新加的 `spanRangeLabel` 也要用同一套。删了会直接编译不过。

**保留**：`effectiveRemaining` / `effectiveNotChained`（Task 4 会改文案）、`effectiveFromDate` / `effectiveUntilDate` / `effectiveRangeSpan`（两个标签函数共用）。

- [ ] **Step 4: 跑编译与用例**

```bash
cd app && flutter analyze && flutter test test/schedule_editor_test.dart
```

预期：analyze 干净；编辑器用例从 47 掉到 43，全绿。

- [ ] **Step 5: 确认只掉这 4 条**

```bash
cd app && flutter test 2>&1 | tail -3
```

预期：**490** 条全绿（494 − 4）。条数是**暂时**下降的（功能搬去别处，用例在 Task 5/6/7 补回来），收尾时必须回到 **≥ 494**。

- [ ] **Step 6: 提交**

```bash
git add -A && git commit -m "refactor(editor): 拆掉编辑器里的「生效时段」一节"
```

---

## Task 2: 领域层 —— 重叠从「后者赢」改成「不许有」

**Files:**
- Modify: `app/lib/domain/schedule_chain.dart`
- Test: `app/test/schedule_chain_test.dart`（改 + 补）

**Interfaces:**
- Produces: `List<ScheduleSpan> conflictingSpans(List<ScheduleSpan> all, ScheduleSpan self)`（原 `overlappingSpans` 改名；语义从「提示一句」变成「不许保存」）
- 不变：`ScheduleChain.scheduleOn` / `shiftOn` / `scheduleIdOn` / `hasCycle` / `monthHasOverrideHint` / `cacheKey` / `label`

- [ ] **Step 1: 写失败的测试**

在 `app/test/schedule_chain_test.dart` 里：

1. 把 `group('overlappingSpans —— 只服务于那句提醒', ...)` 整个改名与改写为：

```dart
  group('conflictingSpans —— 重叠**不许有**，界面靠它挡在保存前', () {
    test('首尾相接**不算**重叠（那是正常的衔接）', () {
      final a = _span('A', id: 1, from: _d(2026, 1, 1), to: _d(2026, 6, 30));
      final b = _span('B', id: 2, from: _d(2026, 7, 1));
      expect(conflictingSpans([a, b], a), isEmpty);
      expect(conflictingSpans([a, b], b), isEmpty);
    });

    test('真重叠 → 报出对方', () {
      final a = _span('A', id: 1, from: _d(2026, 1, 1), to: _d(2026, 8, 31));
      final b = _span('B', id: 2, from: _d(2026, 7, 1));
      expect(conflictingSpans([a, b], a).map((s) => s.schedule.name), ['B']);
      expect(conflictingSpans([a, b], b).map((s) => s.schedule.name), ['A']);
    });

    test('多段都撞上时**全部**报出（按起点升序）', () {
      final self = _span('我', id: 9, from: _d(2026, 1, 1), to: _d(2026, 12, 31));
      final all = [
        self,
        _span('早', id: 1, from: _d(2026, 2, 1), to: _d(2026, 3, 31)),
        _span('晚', id: 2, from: _d(2026, 9, 1), to: _d(2026, 10, 31)),
      ];
      expect(conflictingSpans(all, self).map((s) => s.schedule.name), ['早', '晚']);
    });

    test('两端都空（不参与衔接）的既不算冲突、也不被报出', () {
      final none = _span('未使用', id: 1);
      final a = _span('A', id: 2, from: _d(2026, 1, 1));
      expect(conflictingSpans([none, a], a), isEmpty);
      expect(conflictingSpans([none, a], none), isEmpty);
    });

    test('自己与自己不算冲突（同名 id）', () {
      final a = _span('A', id: 1, from: _d(2026, 1, 1));
      expect(conflictingSpans([a], a), isEmpty);
    });
  });
```

2. 把 `group('ScheduleChain.scheduleOn —— 时段优先、当前方案兜底', ...)` 的组名改成 `group('ScheduleChain.scheduleOn —— 段不重叠 → 唯一解；其余时间兜底', ...)`，并把那条「两段重叠 → **起点晚的赢**（与列表顺序无关）」的用例改写成**防御性**的口吻（断言不变，理由改掉）：

```dart
    test('重叠**不该出现**（界面禁止）—— 真出现时也必须确定，不随列表顺序变', () {
      // 段之间不重叠是界面保证的（保存前校验）+ 迁移规整过的。这条用例守的是
      // 万一库里真有脏数据时的**确定性**：结果仍按「起点晚的赢」，而不是
      // 「列表里第一个」—— 后者会让同一条数据换一次装配顺序就换个答案。
      final early = _span('早', id: 1, from: _d(2026, 1, 1));
      final late = _span('晚', id: 2, from: _d(2026, 7, 1));
      expect(ScheduleChain(spans: [late, early]).scheduleOn(_d(2026, 9, 1))!.name, '晚');
      expect(ScheduleChain(spans: [early, late]).scheduleOn(_d(2026, 9, 1))!.name, '晚');
    });
```

3. 补两条**「其余时间为 null」**的用例（新状态）：

```dart
    test('其余时间为 null（设成「无」）→ 没段覆盖的日子返回 null', () {
      final chain = ScheduleChain(
        spans: [_span('A', id: 1, from: _d(2026, 9, 1), to: _d(2026, 9, 30))],
        fallback: null,
      );
      expect(chain.scheduleOn(_d(2026, 9, 15))!.name, 'A');
      expect(chain.scheduleOn(_d(2026, 9, 30))!.name, 'A'); // 闭区间
      expect(chain.scheduleOn(_d(2026, 10, 1)), isNull);
      expect(chain.scheduleOn(_d(2026, 8, 31)), isNull);
      expect(chain.shiftOn(_d(2026, 10, 1)), isNull);
    });

    test('其余时间为 null 且没有任何段 → 哪天都是 null，且 hasCycle 为假', () {
      const chain = ScheduleChain();
      expect(chain.scheduleOn(_d(2026, 9, 1)), isNull);
      expect(chain.hasCycle, isFalse, reason: '桌面小组件据此画空态');
    });
```

- [ ] **Step 2: 跑测试，确认它失败**

```bash
cd app && flutter test test/schedule_chain_test.dart
```

预期：编译失败（`conflictingSpans` 未定义）。

- [ ] **Step 3: 实现**

`domain/schedule_chain.dart`：

1. `overlappingSpans` → `conflictingSpans`（函数体不变），文档注释改写成：

```dart
/// [self] 之外的、与它时段重叠的那些段（按起点升序）。
///
/// **重叠是不允许的**：段代表「这段时间归这套方案」，一个人一天不可能同时有两套
/// 班 —— 所以界面在保存前拿它拦下并点名（`L10n.spanConflicts`），而不是像 v0.9.12
/// 那样允许重叠、再用「起点最晚的赢」默默选一个（那正是「设了两套都占 9 月、
/// 结果是其中一套、还说不出为什么」的根源）。
///
/// **恰好首尾相接不算重叠**（`A.to + 1 天 == B.from` 是正常的衔接）。
/// 留空端按无穷处理；两端都空（不参与衔接）的直接跳过。
List<ScheduleSpan> conflictingSpans(List<ScheduleSpan> all, ScheduleSpan self) { ... }
```

2. `class ScheduleChain` 的文档注释里，把「规则」那一段改成：

```dart
/// 规则：
///   1. [spans] 里覆盖那天的**至多只有一个**（重叠是界面禁止的、迁移也规整过），
///      有就是它；
///   2. 没有 → [fallback]（「其余时间」）——**它可以是 null**，那意味着那些天
///      真的没有排班（用户把「其余时间」设成了「无」）。
///
/// 实现里那条「起点最晚的赢」**只是一条防御性的 tiebreak**：只有库里真有重叠
/// （脏数据 / 手工改库）时才会用到。留着它而不是「取第一个」，是因为后者会让
/// 同一条数据换一次装配顺序就换个答案 —— 那是另一种静默的不确定。
/// **但别把它的存在读成「重叠是允许的」** —— 用户可见的语义已经改成唯一解了。
```

3. `scheduleOn` 的注释里也补一句同样的说明（那是最容易被后人不小心「简化」掉的地方）。

- [ ] **Step 4: 跑测试**

```bash
cd app && flutter test test/schedule_chain_test.dart
```

预期：全绿（原 19 条 + 新增的 2 条 null 用例 + 冲突组改写后的 5 条）。

- [ ] **Step 5: 全套**

```bash
cd app && flutter analyze && flutter test
```

预期：analyze 干净；**492** 条全绿（490 + 2 条新用例）。

- [ ] **Step 6: 提交**

```bash
git add -A && git commit -m "refactor(schedule): 重叠从「后者赢」改成「不许有」（conflictingSpans）"
```

---

## Task 3: 迁移 12 → 13（把已有的重叠规整掉）

**Files:**
- Modify: `app/lib/data/app_database.dart`
- Test: `app/test/migration_v12_to_v13_test.dart`（新建）

**Interfaces:**
- Produces: `AppDatabase.schemaVersion == 13`；迁移 `if (from < 13)` 里调用的私有方法 `Future<void> _normalizeOverlappingSpans()`

> **这是整轮唯一会改用户既有数据的操作。** 规则：**按 v0.9.12 的解析结果等价改写** —— 升级前后日历上看到的一模一样，只是数据变合法。

- [ ] **Step 1: 写失败的测试**

创建 `app/test/migration_v12_to_v13_test.dart`。骨架照 `migration_v11_to_v12_test.dart`（`sqlite3.openInMemory()` + `NativeDatabase.opened` + `PRAGMA user_version = 12`）；v12 形态的 `shift_schedule_rows` **就是 v11 那份 DDL 加两列**：

```dart
const _v12ScheduleTable = '''
CREATE TABLE shift_schedule_rows (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  anchor_date INTEGER NOT NULL,
  is_current INTEGER NOT NULL DEFAULT 0,
  team_count INTEGER NOT NULL DEFAULT 4,
  team_names TEXT NOT NULL DEFAULT '一班,二班,三班,四班',
  our_team_index INTEGER NOT NULL DEFAULT 0,
  team_offsets TEXT NOT NULL DEFAULT '',
  effective_from INTEGER,
  effective_to INTEGER
)
''';
```

用例（**先写、先跑红**；每条都先在心里按**旧规则**算一遍期望值）：

```dart
  test('A 一直持续 + B 从 7/1 起 → A 截到 6/30', () async {
    final db = await _openV12([
      // (name, from, to, isCurrent)：null 表示那一列为空
      ('A', DateTime.utc(2026, 1, 1), null, true),
      ('B', DateTime.utc(2026, 7, 1), null, false),
    ]);
    addTearDown(db.close);
    final rows = await _spans(db);
    // 旧规则：7/1 起两段都覆盖 → 起点晚的 B 赢；1/1–6/30 只有 A
    expect(rows['A'], (from: '2026-01-01', to: '2026-06-30'));
    expect(rows['B'], (from: '2026-07-01', to: null));
  });

  test('B 起得更早但排在后面 → B 截到 A 的前一天', () async {
    final db = await _openV12([
      ('A', DateTime.utc(2026, 8, 1), null, true),
      ('B', DateTime.utc(2026, 7, 1), null, false),
    ]);
    // 旧规则：8/1 起两段都覆盖 → A（起点晚）赢；7/1–7/31 只有 B
    expect(rows['B'], (from: '2026-07-01', to: '2026-07-31'));
    expect(rows['A'], (from: '2026-08-01', to: null));
  });

  test('起点相同、id 小的那段被整个盖住 → 两列清成 null（未使用）', () async {
    final db = await _openV12([
      ('A', DateTime.utc(2026, 1, 1), DateTime.utc(2026, 12, 31), true), // id 1
      ('B', DateTime.utc(2026, 1, 1), DateTime.utc(2026, 6, 30), false),  // id 2
    ]);
    // 旧规则：起点并列 → id 大的（B）赢，全程归 B；A 整段被盖
    expect(rows['A'], (from: null, to: null));
    expect(rows['B'], (from: '2026-01-01', to: '2026-06-30'));
  });

  test('本来就不重叠的库**一行都不改**', () async {
    final db = await _openV12([
      ('A', DateTime.utc(2026, 1, 1), DateTime.utc(2026, 6, 30), true),
      ('B', DateTime.utc(2026, 7, 1), null, false),
      ('C', null, null, false), // 未使用
    ]);
    // 逐列比 dayNumber，三个名字对应的值全不变
  });
```

> 上面 `rows['A']` 拿的是「名字 → (from 串, to 串)」的辅助结构，实施时写成一个小 helper；**比较一律走 `dayNumber`**（drift 读回来是本地 DateTime），别直接比 `DateTime`。

- [ ] **Step 2: 跑测试，确认它失败**

```bash
cd app && flutter test test/migration_v12_to_v13_test.dart
```

预期：红 —— 迁移还没写，重叠原样留着（第一条会看到 `A.to` 为空而不是 `6/30`）。

- [ ] **Step 3: 写迁移**

`app_database.dart`：

1. `int get schemaVersion => 13;`
2. `onUpgrade` 最前面插入：

```dart
          if (from < 13) {
            // 排班时段重做：v0.9.12 允许时段重叠（解析按「起点最晚的赢」），
            // 从这一版起**禁止重叠**（界面挡在保存前）。已经发出去的测试版可能
            // 在用户库里留下重叠数据，这里按**旧解析结果等价**规整一遍 ——
            // 升级前后日历上看到的一模一样，只是数据变成合法的。
            //
            // 纯数据整理：**没有 DDL 改动**，也没有新表新列。
            await _normalizeOverlappingSpans();
          }
```

3. 新方法（`_migrateRowsToTwoTier` 附近）：

```dart
  /// v12 → v13：把重叠的生效时段规整成互不重叠，**等价于 v0.9.12 的解析结果**。
  ///
  /// 旧规则是「覆盖那天的段里起点最晚的赢」。于是从右往左看，每一段只要伸进了
  /// 它右边那段的起点，就该被截到那段起点的**前一天**；要是截完比自己的起点还早，
  /// 说明它整段都被右边盖住了 —— 两列一起清成 null（它变成「未使用」）。
  ///
  /// 例：
  ///   A[1/1, ∞) 与 B[7/1, ∞)      → A 截到 6/30
  ///   A[8/1, ∞) 与 B[7/1, ∞)      → B 截到 7/31（旧规则里 7/1–7/31 归 B）
  ///   A[1/1, 12/31] 与 B[1/1, 6/30]（A 的 id 大）→ B 两列清空
  ///
  /// **日期算术用 `DateTime(y, m, d - 1)`**，不用 `Duration(days: 1)`（夏令时）。
  Future<void> _normalizeOverlappingSpans() async {
    final rows = await select(shiftScheduleRows).get();
    bool live(ShiftScheduleRow r) =>
        r.effectiveFrom != null || r.effectiveTo != null;
    final spans = rows.where(live).toList()
      ..sort((a, b) {
        final af = a.effectiveFrom, bf = b.effectiveFrom;
        if (af == null && bf == null) return a.id.compareTo(b.id);
        if (af == null) return -1;
        if (bf == null) return 1;
        final c = dayNumber(af).compareTo(dayNumber(bf));
        return c != 0 ? c : a.id.compareTo(b.id);
      });

    // 从右往左：`watermarkFrom` = 已经保留下来的**右边最近那段**的起点；
    // `watermarkUnbounded` = 那段的起点是不限（null）—— 那种段把它左边全吃掉了。
    DateTime? watermarkFrom;
    var watermarkUnbounded = false;
    var sealed = false; // 还没有任何段被保留（最右那一段总是保留）

    for (final r in spans.reversed) {
      final from = r.effectiveFrom;
      final to = r.effectiveTo;
      DateTime? newTo = to;
      var clearBoth = false;

      if (sealed) {
        if (watermarkUnbounded) {
          clearBoth = true;
        } else {
          // 伸进水位就截到水位前一天。
          if (to == null || dayNumber(to) >= dayNumber(watermarkFrom!)) {
            newTo = DateTime(
                watermarkFrom!.year, watermarkFrom.month, watermarkFrom.day - 1);
          }
          // 截完比自己的起点还早 → 整段被盖住。
          if (from != null && dayNumber(newTo!) < dayNumber(from)) {
            clearBoth = true;
          }
        }
      }

      if (clearBoth) {
        await (update(shiftScheduleRows)..where((t) => t.id.equals(r.id)))
            .write(const ShiftScheduleRowsCompanion(
          effectiveFrom: Value(null),
          effectiveTo: Value(null),
        ));
        // 被清空的那段不作为水位（它已经不在时间线上了）。
        continue;
      }

      if (newTo?.millisecondsSinceEpoch != to?.millisecondsSinceEpoch) {
        await (update(shiftScheduleRows)..where((t) => t.id.equals(r.id)))
            .write(ShiftScheduleRowsCompanion(effectiveTo: Value(newTo)));
      }

      sealed = true;
      watermarkFrom = from;
      watermarkUnbounded = from == null;
    }
  }
```

- [ ] **Step 4: 重生成 + 跑测试**

```bash
cd app && dart run build_runner build --delete-conflicting-outputs && flutter test test/migration_v12_to_v13_test.dart
```

- [ ] **Step 5: 跑全套迁移测试**

```bash
cd app && flutter test $(ls test/migration_*.dart | tr '\n' ' ')
```

预期：全绿。⚠️ **迁移分支按倒序跑**，`from < 13` 在更早的 fixture 里也会执行 —— 它只读 `shift_schedule_rows` 的时段列，而那张表每份 fixture 都建过，所以这次**不该**需要补 DDL；真红了再按老规矩补（v11→v12 那次的教训）。

- [ ] **Step 6: 提交**

```bash
git add -A && git commit -m "feat(db): 迁移 12 → 13，把重叠的生效时段按旧解析结果规整掉"
```

---

## Task 4: 仓库与文案 —— `setRemainingNone` + 两种新说法

**Files:**
- Modify: `app/lib/data/app_repository.dart`
- Modify: `app/lib/features/calendar/schedule_span_label.dart`
- Modify: `app/lib/core/l10n.dart`
- Test: `app/test/schedule_span_label_test.dart`（改）、`app/test/schedule_chain_repository_test.dart`（补）

**Interfaces:**
- Produces: `Future<void> AppRepository.setRemainingNone()`
- Produces: `String effectiveRangeLabel(ShiftScheduleRow s, {required bool isCurrent})` —— 两种「没设」的说法改成「其余时间」/「未使用」
- Produces（l10n）：`scheduleTimeline` / `remainingTime` / `remainingNone` / `remainingHint` / `addSpan` / `setRemainingNone` / `manageTimeline` / `spanConflicts(name, range)` / `noScheduleHere` / `unusedSchedule` / `unusedHint`

- [ ] **Step 1: 写失败的测试**

1. `schedule_span_label_test.dart` 改两条：

```dart
  test('两端都空 + 是当前方案 → 「其余时间」', () {
    expect(effectiveRangeLabel(_row(), isCurrent: true), L10n.remainingTime);
  });

  test('两端都空 + 不是当前方案 → 「未使用」（**不能**说成其余时间）', () {
    expect(effectiveRangeLabel(_row(), isCurrent: false), L10n.unusedSchedule);
  });
```

2. `schedule_chain_repository_test.dart` 补一组：

```dart
  test('setRemainingNone：之后没有「其余时间」，没段覆盖的日子就是 null', () async {
    final aId = await _save(repo, 'A', current: true);
    expect((await repo.getActiveSchedules())!.chain.fallback, isNotNull);

    await repo.setRemainingNone();
    final s = (await repo.getActiveSchedules())!;
    expect(s.currentScheduleId, isNull);
    expect(s.chain.fallback, isNull);
    expect(s.chain.scheduleOn(_d(2026, 9, 1)), isNull);
    expect(aId, isNotNull); // 方案本身还在，只是不再是「其余时间」
  });

  test('设成无之后还能再设回来', () async {
    final aId = await _save(repo, 'A', current: true);
    await repo.setRemainingNone();
    await repo.setCurrentSchedule(aId);
    expect((await repo.getActiveSchedules())!.chain.scheduleOn(_d(2026, 9, 1))!.name, 'A');
  });

  test('删掉「其余时间」那套时，自动接管仍然生效（日历不会整片空掉）', () async {
    final aId = await _save(repo, 'A', current: true);
    await _save(repo, 'B', current: false);
    await repo.deleteSchedule(aId);
    final s = (await repo.getActiveSchedules())!;
    expect(s.currentScheduleId, isNotNull, reason: '删掉默认那套之后必须还有一套兜底');
    expect(s.chain.scheduleOn(_d(2026, 9, 1)), isNotNull);
  });
```

- [ ] **Step 2: 跑测试，确认它失败**

```bash
cd app && flutter test test/schedule_span_label_test.dart test/schedule_chain_repository_test.dart
```

- [ ] **Step 3: 加文案**

`l10n.dart`（删掉的那批已在 Task 1 处理）：

```dart
  // ── 排班时段（时间线） ──
  static String get scheduleTimeline => t('排班时段', 'Schedule timeline');
  static String get remainingTime => t('其余时间', 'Other dates');
  static String get remainingNone => t('无', 'None');
  static String get remainingHint =>
      t('没被时段覆盖的日子，用「其余时间」那一套。',
        'Dates not covered by a period use the one under "Other dates".');
  static String get addSpan => t('添加时段', 'Add a period');
  static String get setRemainingNone => t('设为无', 'Set to none');
  static String get manageTimeline => t('管理排班时段', 'Manage the timeline');
  static String spanConflicts(String name, String range) => t(
      '与「$name」的 $range 重叠了 —— 一天只能有一套排班，改开一点或先改那一段。',
      'Overlaps “$name” ($range) — a day can only have one schedule. Adjust the dates or edit that period first.');
  static String get noScheduleHere =>
      t('这段时间没有排班', 'No schedule for these dates');
  static String get noScheduleHereHint =>
      t('去「我的 → 排班管理 → 排班时段」里加一段，或者给它设一套「其余时间」',
        'Add a period under Me → Schedules → Schedule timeline, or give it an "Other dates" schedule');
  static String get unusedSchedule => t('未使用', 'Unused');
  static String get unusedHint =>
      t('未使用 —— 去上面的「排班时段」把它排进去', 'Unused — put it on the timeline above');

  // 时段弹层里「起 / 止」两行。**与 Task 1 删掉的那四个不是一回事**（那些是编辑器
  // 用的、已经没了）—— 这几个是时间线自己的。
  static String get spanFrom => t('从', 'From');
  static String get spanTo => t('到', 'To');
  static String get spanUnbounded => t('不限', 'Any time');
  static String get spanForever => t('一直持续', 'Ongoing');
```

- [ ] **Step 4: 改标签函数**

`schedule_span_label.dart`：把 `isCurrent ? L10n.effectiveRemaining : L10n.effectiveNotChained` 换成 `isCurrent ? L10n.remainingTime : L10n.unusedSchedule`，并把 `effectiveRangeLabel` 的文档注释改成：

```dart
/// 一套方案在**时间线**上的身份标签。**两种「没设时段」的说法不同**：
///  · 没设时段、又是「其余时间」那套 → 「其余时间」；
///  · 没设时段、也不是 → 「未使用」（它根本不在时间线上）。
```

同时删掉 `effectiveRemaining` / `effectiveNotChained` 两个旧常量。

- [ ] **Step 5: 加 `setRemainingNone`**

`app_repository.dart`，挨着 `setCurrentSchedule`：

```dart
  /// 把「其余时间」设成**无**：所有方案都不再是 `isCurrent`。
  ///
  /// 与 [setCurrentSchedule] 配套 —— 后者永远是「设成某一套」，这个是「一套都不设」。
  /// 于是没被任何时段覆盖的日子在日历上**真的没有排班**（用户原话：「领导可能确实
  /// 给他休息几天，懒得去新建一个休息的排班表，直接留空也不是不行」）。
  ///
  /// **只有「排班时段」那一节的「设为无」会调它** —— 删掉一套方案时仍然自动把
  /// 其余时间交给列表里的第一套（[deleteSchedule]），否则「删掉默认那套」会让整张
  /// 日历变空，那是个惊悚结果。
  Future<void> setRemainingNone() async {
    await db.update(db.shiftScheduleRows).write(
          const ShiftScheduleRowsCompanion(isCurrent: Value(false)),
        );
  }
```

- [ ] **Step 6: 跑测试**

```bash
cd app && flutter analyze && flutter test
```

预期：**495** 条全绿（492 + 3 条仓库用例）。

- [ ] **Step 7: 提交**

```bash
git add -A && git commit -m "feat(repo): setRemainingNone + 时间线的两种新说法（其余时间 / 未使用）"
```

---

## Task 5: 排班管理页 —— 「排班时段」一节（列表 + 设为无）

**Files:**
- Modify: `app/lib/features/calendar/schedule_management_screen.dart`
- Test: `app/test/schedule_timeline_test.dart`（新建）

**Interfaces:**
- Consumes: `effectiveRangeLabel`（Task 4）、`setRemainingNone`（Task 4）、`L10n.remainingTime` 等
- Produces: 顶层 `class ScheduleTimelineSection extends ConsumerWidget`（页面顶部的这一节；**弹层在 Task 6 加**）

- [ ] **Step 1: 写失败的测试**

创建 `app/test/schedule_timeline_test.dart`。骨架照 `schedule_span_label_test.dart` 的纯函数路子 + `shift_template_picker_test.dart` 的 widget 路子（那里有现成的「假仓库 + `schedulesProvider` / `activeScheduleProvider` 覆写」写法）：

```dart
// app/test/schedule_timeline_test.dart
//
// 排班管理页顶部那一节「排班时段」。
//
// 这一节是「某天归哪套」的**唯一**入口（编辑器那一节已在 v0.9.13 拆掉），
// 所以它显示错了没有第二个地方能兜住。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/schedule_management_screen.dart';

// `_pump`：内存库 → 建两套排班 → 覆写两个 provider → pump 页面。
// 需要的话（Task 6 的「添加时段」用例）把弹层再点开。

void main() {
  setUpAll(() async => initializeDateFormatting('zh'));
  setUp(() => L10n.locale = 'zh');

  testWidgets('没有任何时段 → 只有「其余时间」一行，指向当前方案', (tester) async {
    // 建 A（当前）、B；跑到页面
    // 期望：L10n.scheduleTimeline 出现；L10n.remainingTime 出现一次；
    //      那一行显示 A 的名字；「添加时段」在
    //      （**没有**「9月1日 ～ 9月30日」这样的段行）
  });

  testWidgets('有时段 → 段行按起点升序排在「其余时间」下面', (tester) async {
    // A（当前）+ B 带 9/1–9/30 + C 带 10/8 起
    // 期望：三行的顺序是 其余时间 / 9月1日 ～ 9月30日 / 10月8日 起
  });

  testWidgets('「其余时间」那一行能设成「无」，设完显示「无」', (tester) async {
    // 点那一行 → 弹层里点「设为无」→ 关掉 → 那一行右侧变成 L10n.remainingNone
  });

  testWidgets('未使用的方案在下面的列表里带「未使用」提示', (tester) async {
    // B 既不是其余时间、也没有时段 → 列表行副标题含 L10n.unusedSchedule
  });
}
```

- [ ] **Step 2: 跑测试，确认它失败**

```bash
cd app && flutter test test/schedule_timeline_test.dart
```

- [ ] **Step 3: 实现这一节**

`schedule_management_screen.dart`：

1. 页面 `body` 的 `ListView` 顶部插入这一节：

```dart
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                ScheduleTimelineSection(schedules: schedules, current: current),
                const SizedBox(height: AppTokens.spaceMd),
                ...schedules.map((s) { /* 现有列表，一行不改 */ }),
                const SizedBox(height: 8),
                FilledButton.icon(/* 现有「新增排班」，一行不改 */),
              ],
            ),
```

2. 新组件（同文件顶层；它是一个 `ConsumerWidget`，`ref` 用来调仓库）：

```dart
/// 排班管理页顶部那一节「排班时段」。
///
/// 形态与「其余时间」这个概念是配套的：**永远列出「其余时间」那一行**，没有段时
/// 就只有它 —— 所以不必为「有没有段」写两套版式（少一个要维护、要出图的状态）。
class ScheduleTimelineSection extends ConsumerWidget {
  const ScheduleTimelineSection({
    super.key,
    required this.schedules,
    required this.current,
  });

  final List<ShiftScheduleRow> schedules;
  final ActiveSchedules? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = current?.current;            // 可能为 null（设成了「无」）
    final segments = schedules
        .where((s) => s.effectiveFrom != null || s.effectiveTo != null)
        .toList()
      ..sort((a, b) { /* (from 升序，null 最前；并列按 id) */ });

    return GlassTile(
      enableBlur: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L10n.scheduleTimeline, style: AppTokens.sectionTitle),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            L10n.remainingHint,
            style: AppTokens.rowSecondary
                .copyWith(color: AppTokens.inkMuted(context)),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _row(
            context,
            label: L10n.remainingTime,
            value: remaining?.schedule.name ?? L10n.remainingNone,
            mutedValue: remaining == null,
            onTap: () => showSpanEditor(context, ref,
                existing: remaining?.schedule, isRemaining: true),
          ),
          for (final s in segments)
            _row(
              context,
              label: spanRangeLabel(s),
              value: s.name,
              onTap: () => showSpanEditor(context, ref, existing: s),
            ),
          GlassPressable(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_outlined),
              title: Text(L10n.addSpan),
              onTap: () => showSpanEditor(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}
```

`spanRangeLabel(row)` = 只有「起 ～ 止」那一部分（复用 `effectiveRangeLabel` 的那几个 `L10n` 组合，但**不看 isCurrent**）——实施时把它加到 `schedule_span_label.dart` 里，与 `effectiveRangeLabel` 并排：

```dart
/// 段在时间线上那一段的**日期说法**（「9月1日 ～ 9月30日」/「10月8日 起」/「到 9月30日」）。
///
/// 与 [effectiveRangeLabel] 的分工：那个给「排班表列表」用（含其余时间 / 未使用
/// 两种**身份**），这个给「时间线的段行」用 —— 段一定有时段，所以没有那两种身份，
/// 传进来的行必须至少有一端。
String spanRangeLabel(ShiftScheduleRow s) {
  final from = s.effectiveFrom;
  final to = s.effectiveTo;
  if (from == null) return L10n.effectiveUntilDate(L10n.monthDay(to!));
  if (to == null) return L10n.effectiveFromDate(L10n.monthDay(from));
  return L10n.effectiveRangeSpan(L10n.monthDay(from), L10n.monthDay(to));
}
```

（`effectiveRangeLabel` 自己就能改写成「`from == null && to == null` 时按身份给说法，否则调 `spanRangeLabel`」—— 实施时那样收一下，两个函数就不会各写一份日期组合。）

`showSpanEditor` 是 Task 6 的产物 —— **本步先写一个只支持「设为无」的最小版**，Task 6 再把它扩成完整的编辑弹层：

```dart
/// 时段编辑弹层。Task 6 会把「换方案 / 改起止 / 删除」补齐，本步先只做
/// 「其余时间 → 设为无」这一条路。
Future<void> showSpanEditor(BuildContext context, WidgetRef ref,
    {ShiftScheduleRow? existing, bool isRemaining = false}) async { ... }
```

- [ ] **Step 4: 跑测试 + 全套**

```bash
cd app && flutter analyze && flutter test test/schedule_timeline_test.dart && flutter test
```

- [ ] **Step 5: 提交**

```bash
git add -A && git commit -m "feat(schedule): 排班管理页新增「排班时段」一节（列表 + 其余时间设为无）"
```

---

## Task 6: 添加 / 编辑时段 + 重叠校验

**Files:**
- Modify: `app/lib/features/calendar/schedule_management_screen.dart`（把 `showSpanEditor` 补齐）
- Test: `app/test/schedule_timeline_test.dart`（补）、`app/test/schedule_span_conflict_test.dart`（新建）

**Interfaces:**
- Consumes: `conflictingSpans`（Task 2）、`setScheduleSpan` / `getScheduleSpan`（仓库，已有）、`showGlassDatePicker` / `showGlassOptionPicker` / `showGlassSnack`
- Produces: `Future<void> showSpanEditor(BuildContext, WidgetRef, {ShiftScheduleRow? existing, bool isRemaining = false})` 的完整形态

- [ ] **Step 1: 写失败的测试**

1. 纯函数那一层已经在 Task 2 覆盖（`conflictingSpans`）。这里只补一条**页面级**的：

```dart
  testWidgets('加一段与已有的段重叠 → 不让存，并点名撞了谁', (tester) async {
    // B 已有 9/1–9/30；再给 C 加 9/15–10/15
    // 点「添加时段」→ 选 C → 起 9月15日 → 止 10月15日 → 保存
    // 期望：这一步**不写库**（C 的两列仍为空），屏幕上出现
    //      L10n.spanConflicts('B', ...)
  });

  testWidgets('首尾相接**可以**存（A 到 6/30、B 从 7/1 起）', (tester) async {
    // 期望：写库成功，B 的 from 是 7/1
  });

  testWidgets('编辑一段：能改方案、能改起止、能删除', (tester) async {
    // 三段各验一次
  });
```

2. 日期怎么选：弹层里「起 / 止」两行走 `showGlassDatePicker`，点某天**直接返回**（没有「确定」按钮）—— 照 `schedule_editor_test.dart` 里那条「点『从』选一天」的写法（`find.descendant(of: find.byType(BottomSheet), matching: find.text('15'))`）。

- [ ] **Step 2: 跑测试，确认它失败**

```bash
cd app && flutter test test/schedule_timeline_test.dart
```

- [ ] **Step 3: 补齐弹层**

`showSpanEditor` 的完整形态（`GlassDialog`）：

```dart
/// 时段编辑弹层。
///
/// 三个入口共用：时间线上点某一段（[existing] 是那一段）、点「其余时间」
/// （[isRemaining]）、点「添加时段」（都为默认）。
///
/// **重叠校验在写库之前**：把「本次要写的那一段」与库里其余的段一起交给
/// `conflictingSpans`，撞上就弹一句点名、直接返回（不写库）。这与
/// v0.9.12 那次「允许重叠、让起点晚的赢」是相反的做法 —— 用户要的是
/// 「不许我犯错」，不是「替我选一个」。
Future<void> showSpanEditor(
  BuildContext context,
  WidgetRef ref, {
  ShiftScheduleRow? existing,
  bool isRemaining = false,
}) async {
  final schedules = await ref.read(schedulesProvider.future);
  if (!context.mounted) return;

  var picked = existing;
  var from = existing?.effectiveFrom;
  var to = existing?.effectiveTo;
  var isRemainingLocal = isRemaining;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) => GlassDialog(
        title: isRemainingLocal
            ? L10n.remainingTime
            : (existing == null ? L10n.addSpan : spanRangeLabel(existing)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isRemainingLocal)
              // 只列**还没有时段、也不是其余时间**的方案 + 自己
              _schedulePickerRow(...),   // 走 showGlassOptionPicker
            if (!isRemainingLocal)
              _dateRow(L10n.spanFrom, from, ...),
            if (!isRemainingLocal)
              _dateRow(L10n.spanTo, to, ...),
            if (isRemainingLocal)
              // 「设为无」/「设成某一套」两档
              _remainingRow(...),
          ],
        ),
        actions: [
          if (existing != null && !isRemainingLocal)
            GlassActionButton(
              variant: GlassActionVariant.danger,
              label: L10n.delete,
              onPressed: () async { /* setScheduleSpan(id) 清空 + pop */ },
            ),
          GlassActionButton(label: L10n.cancel, onPressed: () => dialogCloser(dialogContext)),
          GlassActionButton(
            variant: GlassActionVariant.primary,
            label: L10n.save,
            onPressed: () async {
              // 1) 其余时间那档：设成无 / 设成某套
              // 2) 段那档：先 conflictingSpans 校验，撞上 → showGlassSnack + return
              //    不撞 → setScheduleSpan(id, from:, to:)
            },
          ),
        ],
      ),
    ),
  );
}
```

**几条实现要点**（都是踩过的地方）：

- 用 `dialogCloser(dialogContext)` 而不是 `Navigator.pop`（异步动作之后关窗，见 `glass_dialog.dart`）；
- 「起 / 止」两行各带一个清除钮（`✕`），清空 = 留空 = 不限 / 一直持续；
- 日期行的选择器是**提交点**，自己会发 `Haptics.select()` —— 别补触觉；
- 校验里那一段的 `ScheduleSpan` 要带 `id: existing?.id`，否则 `conflictingSpans` 会把它自己算成冲突；
- 区间文案给 `L10n.spanConflicts` 用 `spanRangeLabel(对方)` 的产物。

- [ ] **Step 4: 跑测试 + 全套**

```bash
cd app && flutter analyze && flutter test test/schedule_timeline_test.dart && flutter test
```

预期：**≥ 500** 条全绿（495 + 冲突用例若干）。

- [ ] **Step 5: 提交**

```bash
git add -A && git commit -m "feat(schedule): 时段的添加/编辑弹层 + 重叠校验（不让存并点名）"
```

---

## Task 7: 日历 —— 按钮换成只读总览 + 整月无班次时指路

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Test: `app/test/calendar_chain_test.dart`（补）

**Interfaces:**
- 删除：`_switchSchedule`、`_showScheduleSwitcher`（连同它们的注释）
- Produces: `_showTimeline()`（只读弹层）+ 网格上一句「这段时间没有排班」

- [ ] **Step 1: 写失败的测试**

在 `calendar_chain_test.dart` 里补：

```dart
  testWidgets('顶栏那个按钮点开是**只读**的排班时段总览，今天所在那段打勾', (tester) async {
    await _pumpChainedCalendar(tester);
    await tester.tap(find.byIcon(Icons.timeline));
    await tester.pumpAndSettle();

    expect(find.text(L10n.scheduleTimeline), findsOneWidget);
    expect(find.text(L10n.remainingTime), findsOneWidget);
    expect(find.textContaining('9月15日'), findsOneWidget);   // 那一段
    expect(find.text(L10n.manageTimeline), findsOneWidget);
    // **没有**「点一行就切过去」这件事：这里不该出现任何「已切换」提示
    await _disposeCalendar(tester);
  });

  testWidgets('其余时间为无 + 没有任何段 → 网格上出现一句指路', (tester) async {
    // 库里只建一套方案、setRemainingNone()、不给它时段
    // 期望：find.text(L10n.noScheduleHere) 找得到
  });
```

- [ ] **Step 2: 跑测试，确认它失败**

```bash
cd app && flutter test test/calendar_chain_test.dart
```

- [ ] **Step 3: 换按钮 + 写只读弹层 + 删掉切换**

1. 两处 `_circleIcon(context, Icons.swap_vert_outlined, L10n.switchSchedule, _showScheduleSwitcher, ...)` 改成：

```dart
          _circleIcon(context, Icons.timeline, L10n.scheduleTimeline, _showTimeline),
```

（窄档那一处带 `size: narrowSide`，只换图标与回调）

2. `_showTimeline`：底部弹层，内容与 `ScheduleTimelineSection` 的**只读版**同构 —— 「其余时间」+ 各段，**今天所在的那一段**打勾 + 主色，底部一个 `ListTile`「管理排班时段」`Navigator.pop` 之后 `Navigator.push(ScheduleManagementScreen)`。

```dart
  /// 「排班时段」只读总览。
  ///
  /// **只读是有意的**：原来那个「切换排班」点一行就把 isCurrent 换过去，可它改的
  /// 只是「没被时段覆盖时的兜底」—— 时段盖满之后点它什么也不会变，用户以为按钮
  /// 坏了。现在它只回答「这段时间在用哪套」，要改去排班管理页。
  Future<void> _showTimeline() async {
    final schedules = await ref.read(schedulesProvider.future);
    if (!mounted) return;
    final today = dateOnly(DateTime.now());
    final chain = ref.read(activeScheduleProvider).valueOrNull?.chain;
    final todayRowId = chain?.scheduleIdOn(today);   // 今天归哪一套（行 id）
    ...
  }
```

3. **删掉** `_switchSchedule`（连同 `Haptics.commit()` 那处）与旧的 `_showScheduleSwitcher`。删完 grep 一遍确认没有残留引用：

```bash
cd app && grep -rn "_switchSchedule\|_showScheduleSwitcher" lib/ test/ tool/ || echo "（没有残留）"
```

4. 整月无班次时的指路：在网格那块（`gridArea`）外面包一层 `Stack`，当**这个月每一天都没有班次**时叠一句居中说明：

```dart
  /// 这个月是不是一天班都没有（「其余时间」设成了无、又没有任何段覆盖）。
  ///
  /// 逐天问一遍 —— 一个月最多 31 次，可以忽略；而判「中点那天」会在跨段边界
  /// 的月份上判错。
  bool _monthHasNoShift(ScheduleChain? chain, DateTime month) {
    if (chain == null) return true;
    final days = DateTime(month.year, month.month + 1, 0).day;
    for (var d = 1; d <= days; d++) {
      if (chain.shiftOn(DateTime(month.year, month.month, d)) != null) return false;
    }
    return true;
  }
```

```dart
                if (!layout.isShort)
                  Stack(
                    children: [
                      gridArea,
                      if (_monthHasNoShift(chain, _month))
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(L10n.noScheduleHere,
                                      style: AppTokens.sectionTitle),
                                  const SizedBox(height: AppTokens.spaceXs),
                                  Text(L10n.noScheduleHereHint,
                                      textAlign: TextAlign.center,
                                      style: AppTokens.rowSecondary
                                          .copyWith(color: AppTokens.inkMuted(context))),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
```

> **`IgnorePointer` 是必需的**：不加的话这一层会吃掉网格的手势（点日期、长按拖选全失灵）—— 而这种「盖了一层透明东西导致交互没了」的症状在 widget 测试里默认不会被发现（除非专门去点）。用例里要**真的点一下某天**再断言信息卡变了。

- [ ] **Step 4: 跑测试 + 全套**

```bash
cd app && flutter analyze && flutter test test/calendar_chain_test.dart test/calendar_screen_test.dart && flutter test
```

- [ ] **Step 5: 提交**

```bash
git add -A && git commit -m "feat(calendar): 顶栏按钮换成「排班时段」只读总览；整月无班次时指路"
```

---

## Task 8: 视觉工装

**Files:**
- Modify: `app/tool/visual/visual_screens.dart`、`app/tool/visual/visual_harness.dart`
- Test: 出图 + **看图**

**Interfaces:**
- Consumes: `seedScheduleChain`（已有，Task 8 可能要调）、`setRemainingNone`
- Produces: `seedNoScheduleAtAll(db)`

- [ ] **Step 1: 屏单调整**

`visual_screens.dart`：

1. **删** `29_editor_span`（编辑器那一节没了），并从 `visualScrollDown` 里删掉它的条目；
2. **改** `28_span_picker`：名字里的 picker 已经不「pick」了 → 改成 `28_calendar_timeline`，标题「日历 · 排班时段总览」，`beforeCapture` 里改成 `find.byIcon(Icons.timeline)`；
3. **加** 两屏：

```dart
  (
    // 排班时段那一节的**两种状态**同屏：上面「其余时间 + 三段（含一段
    // 「～ 一直持续」）」，下面再接现有的排班表列表 —— 一页看完「有哪些班表 +
    // 它们怎么排」，正是这一节并进管理页的理由。
    slug: '30_management_timeline',
    title: '排班管理 · 排班时段',
    build: (db) async {
      await seedScheduleChain(db);
      return const ScheduleManagementScreen();
    },
    needsOnboardingPrefs: false,
  ),
  (
    slug: '31_calendar_no_schedule',
    title: '日历 · 这段时间没有排班',
    build: (db) async {
      await seedNoScheduleAtAll(db);
      return const CalendarScreen();
    },
    needsOnboardingPrefs: false,
  ),
```

4. `visualScrollDown` 补 `'30_management_timeline': 0`（那一节在页面**顶部**，不用滚）—— 其实不需要，它默认就拍首屏 ✓，**别加**。

- [ ] **Step 2: 新种子**

`visual_harness.dart`：

```dart
/// 让整个日历**一天班都没有**：把「其余时间」设成无、又不给任何方案时段。
///
/// 这是用户点过「设为无」又忘了加段时的样子 —— 也是这一轮唯一会画出一片空白
/// 的状态，必须出图看一眼那句指路盖在网格上是什么观感。
Future<void> seedNoScheduleAtAll(AppDatabase db) async {
  final repo = AppRepository(db);
  final rows = await repo.listSchedules();
  for (final r in rows) {
    await repo.setScheduleSpan(r.id);
  }
  await repo.setRemainingNone();
}
```

同时把 `seedScheduleChain` 从「第一套不设时段」保持原样（它现在正好复用成「其余时间 + 一段」的形态）—— **额外**给第二套方案加第二段，让时间线上出现三段（含一段只设起点 = 「～ 一直持续」）：

```dart
Future<void> seedScheduleChain(AppDatabase db) async {
  final repo = AppRepository(db);
  final rows = await repo.listSchedules();
  if (rows.length < 2) return;
  final t = DateTime.now();
  await repo.setScheduleSpan(rows[0].id);   // 其余时间 = 第一套
  await repo.setScheduleSpan(rows[1].id,
      from: DateTime(t.year, t.month, 15), to: DateTime(t.year, t.month + 1, 0));
  // 若库里还有第三套，再给它一段「只设起点」的（拍出「～ 一直持续」那种形态）。
  if (rows.length >= 3) {
    await repo.setScheduleSpan(rows[2].id, from: DateTime(t.year, t.month + 2, 1));
  }
}
```

> 视觉库现在只有两套方案。**要么**接受时间线上只有两行（其余时间 + 一段），**要么**在 `seedVisualDatabase` 里再加一套 —— 实施时看 `30_management_timeline` 那张图的观感再定；三段才能验出「排序 + 只设起点的形态」，我倾向**加一套**。

- [ ] **Step 3: 出图**

```bash
cd app && flutter test tool/visual/render_screens_test.dart
```

- [ ] **Step 4: 看图（这一步是这一任务的全部意义）**

逐张看：

- **`30_management_timeline_light` / `_dark`**：其余时间 + 各段一行一行排开、右侧方案名与箭头对齐；「添加时段」在最后；下面接排班表列表时不会显得是两坨不相干的东西；
- **`31_calendar_no_schedule_light`**：那句指路**盖在网格上**居中、不压到顶栏与信息卡、两层文字不互相打架；网格的日期与农历仍看得见（它只是叠了一层说明，不是替换）；
- **`28_calendar_timeline`**：只读总览里今天那一段打勾、其余时间那行在、底部「管理排班时段」在。

- [ ] **Step 5: 全套**

```bash
cd app && flutter test tool/visual/ && flutter analyze && flutter test
```

- [ ] **Step 6: 提交**

```bash
git add -A && git commit -m "test(visual): 排班时段那一节与「整月无班次」两屏"
```

---

## Task 9: 收尾 —— 版本号、更新日志、文档、构建发布

**Files:**
- Modify: `app/pubspec.yaml`、`app/lib/core/app_info.dart`、`app/lib/features/profile/app_dialogs.dart`
- Modify: `PRODUCT_SPEC.md`、`AGENTS.md`
- Create: `tools/gh/release-notes-vX.Y.Z.md`

- [ ] **Step 1: 定版本号**

`Z` 归 AI，`X.Y` **必须问用户**（这一轮是实打实的界面重做 + 一次数据迁移，够不够动 `X.Y` 由用户定）。假设维持 `0.9`：

```bash
cd app && sed -i 's/^version: 0\.9\.13+117/version: 0.9.14+118/' pubspec.yaml
# app_info.dart 的 appVersion 同步改成 '0.9.14'
```

- [ ] **Step 2: 更新日志 prepend**

在 `_changelogZh` / `_changelogEn` 最前面插一条、各删掉最旧一条（窗口固定 10 条，由 `changelog_window_test.dart` 验）。测试版条目**原样写自己这版改了什么**：

```
    '· 「排班时段」不再设在排班编辑器里了：现在在「排班管理」页顶部，一条时间线由上到下 —— 头一行是「其余时间」（没被时段覆盖的日子归它管），下面是你排的每一段，点任意一行就能改\n'
    '· 两段时间**不许重叠**：一天只能有一套排班，撞上了会告诉你跟哪一段撞的（从前允许重叠，结果是「设了两套都占 9 月，出来的是其中一套」，说不清为什么）\n'
    '· 「其余时间」可以设成「无」：两个班表之间领导真给休息几天时，直接留空就行，不必再专门建一套「休息」的班表。没排班的日子在日历上会写一句「这段时间没有排班」，告诉你去哪加\n'
    '· 日历顶栏那个「切换排班」按钮改成了「排班时段」：点开是一张只读的时间线，能看到这段时间在用哪套、今天在哪一段，要改就点底下的「管理排班时段」。原来那个按钮在时段盖满日子之后就什么也改不动，看着像坏了\n'
```

- [ ] **Step 3: `PRODUCT_SPEC.md`**

- §2 第 5 条：把「多排班表按日期衔接」那一段按新语义重写（**不许重叠**、其余时间可设无、时间线在排班管理页、日历按钮只读）；
- §2 第 9 条：拖选拦住那句里对「边界」的说法保持不变（仍成立）；
- 数据模型表：`effectiveFrom`/`effectiveTo` 那行的说明改成「**时间线**上的一段；段之间不许重叠」；
- `schemaVersion 12 → 13` + 迁移行：**纯数据规整、无 DDL**，并写明「按旧解析结果等价改写」。

- [ ] **Step 4: `AGENTS.md`**

- 版本史追加；
- 「最近改动」写一节（把用户的反馈原话、四个决策、以及「删掉的比加的多」写清楚）；
- Drift 表清单里的 `schemaVersion = 14`？——**不**，是 `13`；同时把那段说明里的「生效时段两列」补上「段之间不许重叠」；
- 「关键决策与坑」：
  1. **改写**原来那条「解析规则」的条目：从「起点最晚的赢」改成「**不重叠 → 唯一解** + 一条只防脏数据的 tiebreak」，并写清「**别把那条 tiebreak 读成重叠是允许的**」；
  2. **新增**一条：**「不能表达的状态就别让它可表达」** —— 重叠靠保存前校验挡住，而不是靠解析规则容忍（v0.9.12 的教训：容忍重叠的代价是结果不可预测，用户看不懂）；
  3. **新增**一条：**迁移必须与旧解析结果等价**，以及它的算法（从右往左截断 + 整段被盖就清空），并写明它是**纯数据、无 DDL**。

- [ ] **Step 5: 全套验收**

```bash
cd app && flutter analyze && flutter test && flutter test tool/visual/
```

预期：analyze 干净；`flutter test` **≥ 494**（条数必须回到 Task 1 之前那么多以上 —— 中间掉过 4 条，这一轮补回来并超过）；工装全绿。把实际条数记下来写进 AGENTS。

- [ ] **Step 6: 构建 + 校验**

```bash
cd app && flutter build apk --release --target-platform android-arm64
cp build/app/outputs/flutter-apk/app-release.apk ../dist/倒班助手Pro-vX.Y.Z.apk
aapt2 dump badging ../dist/倒班助手Pro-vX.Y.Z.apk | head -1   # 核 versionName / versionCode / 包名
```

- [ ] **Step 7: 发布说明**

写 `tools/gh/release-notes-vX.Y.Z.md`（`release.ps1` 自动复用，格式照 `release-notes-v0.9.12.md`）。

- [ ] **Step 8: 提交 + 发布（beta 分支）**

```bash
git add -A && git commit -m "chore(release): vX.Y.Z（排班时段重做）"
git push origin beta && git tag vX.Y.Z && git push origin vX.Y.Z
# release.ps1 要先把 pwsh 的构建环境与 gh 登录态备好（见记忆 gh-release-config-dir）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Alec\Documents\DeepSeekHermesData\shiftassistant\tools\_run-release.ps1"
```

发完**必须 curl 一次** main 上的 `latest.json` 核对版本号。

---

## 自检（写完计划后对着 spec 过一遍）

**1. spec 覆盖**

| spec 章节 | 落在哪个任务 |
|---|---|
| §2 四个决策 | Task 5（并进管理页）、Task 6（禁止重叠）、Task 4（其余时间可设无）、Task 7（日历按钮） |
| §3.1 存储不动 | 全程 —— 只有 Task 3 动数据、不动结构 |
| §3.2 解析两段 + 防御 tiebreak | Task 2 |
| §3.3 重叠校验 | Task 2（实现）、Task 6（接入） |
| §3.4 `setRemainingNone` | Task 4 |
| §4.1 排班管理页那一节 | Task 5 + Task 6 |
| §4.2 列表两种新说法 + 未使用提示 | Task 4（文案）、Task 5（未使用提示的用例） |
| §4.3 日历按钮 | Task 7 |
| §4.4 编辑器删节 | Task 1 |
| §5 连带的行为变化 | Task 4（删方案自动接管那条用例） |
| §6 迁移 12 → 13 | Task 3 |
| §7 删掉的东西 | Task 1 / 2 / 7 |
| §8 文案 | Task 4 |
| §9 明确不做 | 全程不碰 |
| §10 测试 | 每个任务的 Step 1 |
| §11 收尾 | Task 9 |
| §12 风险 1（迁移等价） | Task 3 |
| §12 风险 2（其余时间为 null） | Task 2（用例）+ Task 7（指路） |
| §12 风险 3（校验要说清撞了谁） | Task 6 |
| §12 风险 4（删方案自动接管） | Task 4 |
| §12 风险 5（编辑器删干净） | Task 1 |
| §12 风险 6（标签两种说法的用例） | Task 4 |
| §12 风险 7（`hasCycle` 在 null 下） | Task 2 |

**2. 占位符扫描**

- Task 5 Step 3 的 `showSpanEditor` 与 Task 6 的完整版之间有一处**有意分两步**（先只支持「设为无」，再补齐）—— 两步都写明了各自要做什么，不是 TBD。
- Task 6 的弹层代码块里 `_schedulePickerRow` / `_dateRow` / `_remainingRow` 是**要写的私有小部件**，它们的职责、走哪个共享件、以及三条实现要点都写在代码块下面了。
- Task 8 Step 2 里有一处「实施时看那张图的观感再定」（视觉库要不要加第三套方案）—— 这是**出图之后的判断**，写明了判据（三段才能验出排序与「只设起点」的形态）与我的倾向。

**3. 类型一致性**

- `conflictingSpans(List<ScheduleSpan>, ScheduleSpan) -> List<ScheduleSpan>`：Task 2 定义、Task 6 调用，签名一致。
- `setRemainingNone()`：Task 4 定义、Task 5/8 调用。
- `spanRangeLabel(ShiftScheduleRow) -> String`：Task 5 定义（在 `schedule_span_label.dart`）、Task 6 调用。
- `ScheduleTimelineSection({schedules, current})`：Task 5 定义、Task 8 出图用到。
- `showSpanEditor(BuildContext, WidgetRef, {ShiftScheduleRow? existing, bool isRemaining})`：Task 5 定义最小版、Task 6 补齐，签名不变。
- `_monthHasNoShift(ScheduleChain?, DateTime) -> bool`：Task 7 内部。

**4. Review Focus 的落点**

五条各自有任务与用例：① → Task 3 的四条迁移用例；② → Task 2 的两条 null 用例 + Task 7 的指路用例；③ → Task 6 的「撞了要说清撞谁」用例；④ → Task 4 的「删掉默认那套之后仍有兜底」用例；⑤ → Task 1 的 Step 4–5（编译 + 条数只掉那 4 条）。
