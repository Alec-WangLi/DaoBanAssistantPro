# 按月排班 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让一套排班方案可以选「按月切段」——每月第 1 天重新归零、从某天起换成另一个班次、最后一段到月底，并支持多班组按段错开。

**Architecture:** 在现有「连续周期」引擎旁边加**第二种锚定方式**。模式由 `ShiftSchedule.monthly` 这个标志决定（**不是**「哪一边的数据空」——见 spec §3.5）；规则本身是一组不依赖 `DateTime` 的纯整数函数（新文件 `domain/monthly_pattern.dart`），`shift_rotation.dart` 只负责把日期换成「当月第几天」再调它。数据层**纯新增**：一张段表 + 方案表两列 + 模板表三列，schemaVersion 13 → 14。闹钟、桌面小组件、按天改班、多套方案按日期衔接都站在 `ShiftSource.shiftOn(date)` 之上，一律不动。

**Tech Stack:** Flutter / Dart · Riverpod · Drift(SQLite) · `flutter_test`。

**Spec:** `docs/superpowers/specs/2026-10-13-monthly-schedule-design.md`（下面每个任务都从它推出来；实施时两份一起读）

## Global Constraints

- **版本号**：`X.Y` 由用户决定，本轮只动末位 `Z` 与 `build`。`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须同步（`app/test/app_info_test.dart` 盯着）。
- **验收线**：`flutter analyze` **0 error / 0 warning**（约 4 条 info 可容忍）；`flutter test` 全绿，**条数只增不减**（当前 933）。
- **不要跑 `dart format`** —— 工具链是新版 tall style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `analyze`。
- **改 Drift 表之后必须重生成**：`dart run build_runner build --delete-conflicting-outputs`。
- **跑命令前先备好环境**：bash 里要 `export ANDROID_HOME=.../toolchain/android-sdk JAVA_HOME=.../toolchain/jdk GRADLE_USER_HOME=.../toolchain/gradle`（见仓库 `BUILD.md`）；`flutter` 在 `toolchain/flutter/bin/`。所有 `flutter …` 命令都在 `app/` 目录下跑。
- **日期一律走 `dayNumber` / `dateOnly`**，不许直接比 `DateTime`（东八区差 8 小时、边界那天静默判错）。
- **界面只用 `AppTokens` 的角色令牌**，不写 `fontSize:` / `fontWeight:` / `Circular(x)` / `Duration(ms:)` / `Color(0x…)` 字面量（`app/test/design_tokens_test.dart` 扫源码）。
- **除 `core/haptics.dart` 外任何文件不许出现 `HapticFeedback.`**（`app/test/haptics_guard_test.dart`）。
- **弹窗 / 弹层一律走 `showGlassDialog` / `showGlassSheet`**，不许裸调 `showDialog` / `showModalBottomSheet`（`app/test/glass_overlay_guard_test.dart`）。
- **测试版走 `beta` 分支**（AGENTS.md「分支与发布」）。
- **每个提交的信息末尾带** `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`。
- **周期模式的行为一个字节都不许变**：`shift_rotation_test.dart` 的既有用例一条都不许改绿。实施中若发现某条既有用例必须改，停下来说明理由。

## Review Focus

这些是 spec 暗示、但**没有任何一个任务的测试天然覆盖**的输入与状态。每一条都在下面某个任务的步骤里有它的用例（标了 **RF-n**）：

1. **2 月与「起始日 29–31」的段** —— 一个从每月 29 日起的段，在 2 月整月不出现，那些天该落在**上一段**（不是空、不是别的班）。**RF-1**
2. **每月 1 日 00:00 之后那一瞬间** —— 日历、桌面小组件快照、闹钟三处必须**同时**归零（快照窗口跨月）。**RF-2**
3. **一套按月方案参与「排班时段」衔接** —— 跨边界那天归按月那套时，用的必须是**按月的切法**算出来的班次。**RF-3**
4. **段引用的班次定义被改 / 被删** —— 删一个还被段引用着的班次，或在段还在时删掉整套方案。**RF-4**
5. **模式来回切换** —— 切到按月再切回按周期，两边数据都还在，而且**当前模式说了算**（`monthly = false` 时哪怕段表非空也必须走周期）。**RF-5**

---

### Task 1: 纯整数规则 `domain/monthly_pattern.dart`

**Files:**
- Create: `app/lib/domain/monthly_pattern.dart`
- Test: `app/test/monthly_pattern_test.dart`

**Interfaces:**
- Produces（后面每个任务都用这几个名字，别改名）：
  - `class MonthlySegment` — `const MonthlySegment({required int startDay, required int classIndex})`，两个 `final int` 字段，带 `==` / `hashCode` / `toString`。
  - `int segmentIndexOn(List<MonthlySegment> segments, int dayOfMonth)` — 最后一个 `startDay <= dayOfMonth` 的**下标**；空表返回 `-1`。
  - `int? monthlyClassIndexOn(List<MonthlySegment> segments, int dayOfMonth, int teamSegOffset)` — 组错开后取那一段的 `classIndex`；空表返回 `null`。
  - `bool validMonthlySegments(List<MonthlySegment> segments)`
  - `List<MonthlySegment> defaultMonthlySegments(int count)`

**这个文件里不许出现 `DateTime`** —— 规则只跟「当月第几天」这个整数打交道，提取日号是 Task 2 的事。这样它既没有时区风险，也能纯整数测。

- [ ] **Step 1: 写失败的测试** `app/test/monthly_pattern_test.dart`

用户那张表：一个月三段，1–10 中、11–20 白、21–月底 夜。

```dart
test('用户那张表：每个月的第 1/11/21 天各换一次段', () {
  const segs = [
    MonthlySegment(startDay: 1, classIndex: 0),
    MonthlySegment(startDay: 11, classIndex: 1),
    MonthlySegment(startDay: 21, classIndex: 2),
  ];
  expect(segmentIndexOn(segs, 1), 0);
  expect(segmentIndexOn(segs, 10), 0);
  expect(segmentIndexOn(segs, 11), 1);
  expect(segmentIndexOn(segs, 20), 1);
  expect(segmentIndexOn(segs, 21), 2);
  expect(segmentIndexOn(segs, 31), 2);
  // 2 月只有 28 天：28 号同样落在第三段（「最后剩下的都是夜班」）
  expect(segmentIndexOn(segs, 28), 2);
});

test('单段 = 整月一个班次；空表返回 -1 / null', () {
  const one = [MonthlySegment(startDay: 1, classIndex: 3)];
  for (var d = 1; d <= 31; d++) {
    expect(segmentIndexOn(one, d), 0);
  }
  expect(segmentIndexOn(const [], 5), -1);
  expect(monthlyClassIndexOn(const [], 5, 0), isNull);
});

test('班组按段错开：绕回来', () {
  const segs = [ /* 同上三段 */ ];
  expect(monthlyClassIndexOn(segs, 5, 0), 0);
  expect(monthlyClassIndexOn(segs, 5, 1), 1);
  expect(monthlyClassIndexOn(segs, 5, 2), 2);
  // 25 号在第 3 段，乙组（错开 1）绕回第 1 段
  expect(monthlyClassIndexOn(segs, 25, 1), 0);
  expect(monthlyClassIndexOn(segs, 25, 2), 1);
});

test('defaultMonthlySegments：把 31 天均分，第 i 段指向第 i 个班次', () {
  expect(defaultMonthlySegments(1),
      const [MonthlySegment(startDay: 1, classIndex: 0)]);
  expect([for (final s in defaultMonthlySegments(3)) s.startDay], [1, 11, 22]);
  expect([for (final s in defaultMonthlySegments(4)) s.startDay], [1, 9, 17, 24]);
  for (var n = 1; n <= 31; n++) {
    final segs = defaultMonthlySegments(n);
    expect(segs.length, n);
    expect(validMonthlySegments(segs), isTrue);
    expect(segs.last.startDay, lessThanOrEqualTo(31));
  }
});

test('validMonthlySegments 的五种非法形状', () {
  expect(validMonthlySegments(const []), isFalse);            // 空
  expect(validMonthlySegments(const [MonthlySegment(startDay: 2, classIndex: 0)]), isFalse); // 不从 1 起
  expect(validMonthlySegments(const [
    MonthlySegment(startDay: 1, classIndex: 0),
    MonthlySegment(startDay: 1, classIndex: 1),
  ]), isFalse);                                               // 不严格递增
  expect(validMonthlySegments(const [MonthlySegment(startDay: 32, classIndex: 0)]), isFalse); // 越界
  expect(validMonthlySegments(const [
    MonthlySegment(startDay: 1, classIndex: 0),
    MonthlySegment(startDay: 21, classIndex: 1),
  ]), isTrue);
});
```

- [ ] **Step 2: 跑一遍，确认它红**

Run: `flutter test test/monthly_pattern_test.dart`
Expected: 编译失败（`monthly_pattern.dart` 不存在）。

- [ ] **Step 3: 实现 `app/lib/domain/monthly_pattern.dart`**

只有四条逻辑：

- `segmentIndexOn` —— 从后往前找第一个 `startDay <= dayOfMonth`；找不到返回 `-1`。
- `monthlyClassIndexOn` —— `n = segments.length`；`n == 0` 返回 `null`；`seg = segmentIndexOn(...)`；`seg < 0` 返回 `null`；返回 `segments[(seg + teamSegOffset) % n].classIndex`。
  ⚠️ **Dart 的 `%` 对正除数恒返回非负值**（`-1 % 3 == 2`），所以负的 `teamSegOffset` 不必再补一次模。
- `validMonthlySegments` —— 非空、`first.startDay == 1`、每段的 `startDay` 落在 1..31、且严格大于前一段。
- `defaultMonthlySegments(count)` —— `count <= 0` 返回空表；否则第 `i` 段 `startDay = 1 + (i * 31 / count).round()`、`classIndex = i`。

文件头写一段注释说明「这是按月锚定的规则本体、不碰 DateTime、纯整数因而可纯测」，并把 spec §3.1 那两条约束抄进去（第一段恒从 1 起、最后一段自动到月底）。

- [ ] **Step 4: 跑测试，确认全绿**

Run: `flutter test test/monthly_pattern_test.dart && flutter analyze lib/domain/monthly_pattern.dart`
Expected: PASS；0 issue。

- [ ] **Step 5: 提交**

```bash
git add app/lib/domain/monthly_pattern.dart app/test/monthly_pattern_test.dart
git commit -m "feat(domain): 按月切法的纯整数规则

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `ShiftSchedule` 接上按月模式 + 撞班检测

**Files:**
- Modify: `app/lib/domain/shift_rotation.dart`（`ShiftSchedule` 的字段 / `isBlank` / `teamShift` / `crewClashes`）
- Test: `app/test/monthly_schedule_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 的 `MonthlySegment` / `segmentIndexOn` / `monthlyClassIndexOn`
- Produces:
  - `ShiftSchedule` 增三个可选具名参数：`bool monthly = false`、`List<MonthlySegment> monthlySegments = const []`、`List<int> teamSegOffsets = const []`（**默认值保证既有调用点一字不改**）
  - `bool get isBlank => monthly ? monthlySegments.isEmpty : cycle.isEmpty;`
  - 顶层 `int dayOfMonth(DateTime date) => dateOnly(date).day;`
  - `CrewClash.cycleDay` 在按月模式下装的是**当日号数**

（spec §5.1 还提过一个 `monthSegmentCount` getter —— **本计划不实现它**：界面数的是编辑器自己那份 `_monthlySegments`，域里没有任何调用点，加了就是一句没人用的死 API。）

- [ ] **Step 1: 写失败的测试** `app/test/monthly_schedule_test.dart`

固定夹具：三个班次定义 中班 / 白班 / 夜班（都不休），段表 `[(1,0),(11,1),(21,2)]`。

```dart
ShiftSchedule monthSchedule({
  List<MonthlySegment> segments = const [
    MonthlySegment(startDay: 1, classIndex: 0),
    MonthlySegment(startDay: 11, classIndex: 1),
    MonthlySegment(startDay: 21, classIndex: 2),
  ],
  List<int> segOffsets = const [],
  int teams = 1,
}) =>
    ShiftSchedule(
      name: '按月',
      anchorDate: DateTime.utc(2020, 1, 1),   // 按月模式不读它，随便给
      classes: [中班, 白班, 夜班],
      cycle: const [],
      monthly: true,
      monthlySegments: segments,
      teamCount: teams,
      ourTeamIndex: 0,
      teamSegOffsets: segOffsets,
    );

test('用户报的那个现象：12 月 1 日必须是中班', () {
  final s = monthSchedule();
  expect(s.shiftOn(DateTime(2026, 12, 1))!.name, '中班');
  expect(s.shiftOn(DateTime(2026, 12, 10))!.name, '中班');
  expect(s.shiftOn(DateTime(2026, 12, 11))!.name, '白班');
  expect(s.shiftOn(DateTime(2026, 12, 20))!.name, '白班');
  expect(s.shiftOn(DateTime(2026, 12, 21))!.name, '夜班');
  expect(s.shiftOn(DateTime(2026, 12, 31))!.name, '夜班');
});

test('四种月长下切法完全一样（31 / 30 / 28 / 闰年 29）', () {
  final s = monthSchedule();
  for (final m in [
    DateTime(2026, 1),   // 31
    DateTime(2026, 4),   // 30
    DateTime(2026, 2),   // 28
    DateTime(2028, 2),   // 29
  ]) {
    final days = DateTime(m.year, m.month + 1, 0).day;
    for (var d = 1; d <= days; d++) {
      final want = d <= 10 ? '中班' : (d <= 20 ? '白班' : '夜班');
      expect(s.shiftOn(DateTime(m.year, m.month, d))!.name, want,
          reason: '${m.year}-${m.month}-$d');
    }
  }
});

test('每月 1 日恒落在第一段', () {
  final s = monthSchedule();
  for (var m = 1; m <= 12; m++) {
    expect(s.shiftOn(DateTime(2026, m, 1))!.name, '中班');
  }
});

// RF-1：起始日 29 的段在 2 月整月不出现，那些天落在上一段
test('起始日 29 的段遇上 2 月：整月都归上一段', () {
  final s = monthSchedule(segments: const [
    MonthlySegment(startDay: 1, classIndex: 0),
    MonthlySegment(startDay: 29, classIndex: 1),
  ]);
  for (var d = 1; d <= 28; d++) {
    expect(s.shiftOn(DateTime(2026, 2, d))!.name, '中班');
  }
  expect(s.shiftOn(DateTime(2026, 1, 28))!.name, '中班');
  expect(s.shiftOn(DateTime(2026, 1, 29))!.name, '白班');
  expect(s.shiftOn(DateTime(2026, 1, 31))!.name, '白班');
});
```

再加这几条（RF-5 与 §3.5 那个坑）：

```dart
test('isBlank：按月模式下看段表，周期模式下只看周期 —— 两边可以同时非空', () {
  expect(monthSchedule().isBlank, isFalse);
  expect(monthSchedule(segments: const []).isBlank, isTrue);       // monthly=true 空段 = 空白表
  final cycleMode = ShiftSchedule(
    name: '周期', anchorDate: DateTime.utc(2025, 1, 6),
    classes: [中班, 白班], cycle: const [0, 1],
    monthly: false,
    monthlySegments: const [MonthlySegment(startDay: 1, classIndex: 0)],  // 陈旧的段表
  );
  expect(cycleMode.isBlank, isFalse);
  expect(cycleMode.shiftOn(DateTime(2025, 1, 6))!.name, '中班');   // ← 必须走周期
  expect(cycleMode.shiftOn(DateTime(2025, 1, 7))!.name, '白班');
});

test('段指到一个不存在的班次下标：返回 null，不抛', () {
  final s = monthSchedule(segments: const [
    MonthlySegment(startDay: 1, classIndex: 9),   // 只有三个班次
  ]);
  expect(s.shiftOn(DateTime(2026, 3, 3)), isNull);
});
```

班组错开那条（**这是 spec §3.3 那条推演的护栏**）：

```dart
test('三组三段：扫一整年，每天三组的班次两两不同且都非空', () {
  final s = monthSchedule(teams: 3, segOffsets: const [0, 1, 2]);
  for (var day = DateTime(2026, 1, 1);
      day.isBefore(DateTime(2027, 1, 1));
      day = day.add(const Duration(days: 1))) {
    final names = [for (var t = 0; t < 3; t++) s.teamShift(t, day)?.name];
    expect(names.whereType<String>().length, 3, reason: '$day 有人没班');
    expect(names.toSet().length, 3, reason: '$day 撞班：$names');
  }
  expect(crewClashes(s), isEmpty);
});

test('四组三段：报得出撞班，且当日号数落在 1..31', () {
  final s = monthSchedule(teams: 4, segOffsets: const [0, 1, 2, 3]);
  final clashes = crewClashes(s);
  expect(clashes, isNotEmpty);
  for (final c in clashes) {
    expect(c.cycleDay, inInclusiveRange(1, 31));
    expect(c.teamA, lessThan(c.teamB));
  }
});
```

- [ ] **Step 2: 跑一遍，确认它红**

Run: `flutter test test/monthly_schedule_test.dart`
Expected: 编译失败（`ShiftSchedule` 没有 `monthly` / `monthlySegments` / `teamSegOffsets` / `monthSegmentCount`，也没有顶层的 `dayOfMonth`）。

- [ ] **Step 3: 改 `app/lib/domain/shift_rotation.dart`**

1. `import 'monthly_pattern.dart';`
2. 顶层加 `int dayOfMonth(DateTime date) => dateOnly(date).day;`（挨着 `dateOnly` 放，注释写「走 `dateOnly` 与全仓日期纪律一致」）。
3. `ShiftSchedule` 构造器与字段加上那三个（**都给默认值**）。类文档里补一句：`monthly` 是**唯一**的模式判据（spec §3.5）。
4. `isBlank`、`monthSegmentCount` 按 Interfaces 写。
5. `teamShift` 在**最前面**分叉：

```dart
if (monthly) {
  final n = monthlySegments.length;
  if (n == 0) return null;
  final off = (teamIndex >= 0 && teamIndex < teamSegOffsets.length)
      ? teamSegOffsets[teamIndex]
      : teamIndex - ourTeamIndex;
  final ci = monthlyClassIndexOn(monthlySegments, dayOfMonth(date), off);
  if (ci == null || ci < 0 || ci >= classes.length) return null;
  return classes[ci];
}
// ↓ 以下原周期算式一字不动
```
   ⚠️ **越界只有一条出路：`return null`** —— 按月模式下没有周期可退，别写「回退到轮转」。
6. `crewClashes`：开头改成 `if (s.classes.isEmpty) return const []; if (s.monthly) return _monthlyCrewClashes(s); if (s.cycle.isEmpty) return const [];`，其余**原样不动**。
7. 新增 `List<CrewClash> _monthlyCrewClashes(ShiftSchedule s)`：从 `DateTime.utc(2020, 1, 1)`（闰年，保证 2/29 出现）起逐日扫 **1461 天**（四年）；每天按现有的「两个非休班班组撞同一个班次」判据收；结果按 `(cycleDay, teamA, teamB)` **去重**后返回。
8. `CrewClash.cycleDay` 的文档补一句：按月模式下装的是**当日号数（1..31）**，含义由模式决定。

- [ ] **Step 4: 反向验证班组错开那条护栏（一次性，不入库）**

把 `teamShift` 的按月分支临时改成「按天错开」（把 `teamSegOffsets` 当**天**数加到 `dayOfMonth` 上再取段），跑 `flutter test test/monthly_schedule_test.dart`：

Run: `flutter test test/monthly_schedule_test.dart`
Expected: **红**，且红在「每天三组的班次两两不同」那条上（0/1/2 天错开会在 11 号之类的地方撞）。看完把代码改回来。

- [ ] **Step 5: 跑测试，确认全绿，且既有用例一条没改**

Run: `flutter test test/monthly_schedule_test.dart test/shift_rotation_test.dart test/shift_templates_test.dart && flutter analyze`
Expected: 全 PASS；0 error / 0 warning。**`shift_rotation_test.dart` 里一条断言都不许动。**

- [ ] **Step 6: 提交**

```bash
git add app/lib/domain/shift_rotation.dart app/test/monthly_schedule_test.dart
git commit -m "feat(domain): ShiftSchedule 支持按月模式与按段错开的班组

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: `ScheduleChain` 的指纹与衔接

**Files:**
- Modify: `app/lib/domain/schedule_chain.dart`（`_rotationOf`）
- Test: `app/test/schedule_chain_test.dart`（追加）

**Interfaces:**
- Consumes: Task 2 的 `monthly` / `monthlySegments` / `teamSegOffsets`
- Produces: 无新 API，只让 `rotationKey` 覆盖到按月切法

不加这一个的后果就是 v0.10.21 那个病再来一次：换一次按月切法，**桌面小组件不重推、信息卡「本月统计」显示旧数字**，而且完全静默。

- [ ] **Step 1: 写失败的测试**（追加到 `app/test/schedule_chain_test.dart`）

```dart
test('rotationKey：改一次按月切法之后必须变', () {
  String keyWith(List<MonthlySegment> segs) => ScheduleChain(
        fallback: /* monthSchedule 那一套，段表换成 segs */,
        fallbackId: 1,
      ).rotationKey;

  final a = keyWith(const [
    MonthlySegment(startDay: 1, classIndex: 0),
    MonthlySegment(startDay: 11, classIndex: 1),
  ]);
  final b = keyWith(const [
    MonthlySegment(startDay: 1, classIndex: 0),
    MonthlySegment(startDay: 12, classIndex: 1),   // 只挪了一天
  ]);
  final c = keyWith(const [
    MonthlySegment(startDay: 1, classIndex: 0),
    MonthlySegment(startDay: 11, classIndex: 2),   // 只换了班次
  ]);
  expect(a, isNot(b));
  expect(a, isNot(c));
});
```

再加 **RF-3**：一套按月方案作为 `spans` 里的一段，与另一套周期方案前后衔接 ——

```dart
test('衔接：跨边界那天归按月那套，且用的是按月切法算出来的班次', () {
  final chain = ScheduleChain(spans: [/* 周期那套：～9/30 */, /* 按月那套：10/1～ */]);
  expect(chain.shiftOn(DateTime(2026, 10, 1))!.name, '中班');   // 10/1 恒第一段
  expect(chain.shiftOn(DateTime(2026, 10, 11))!.name, '白班');
  expect(chain.shiftOn(DateTime(2026, 9, 30))!.name, /* 周期那套算出来的 */);
});
```

最后一条把 spec §7 那句「`hasCycle` 不用单独改、实施时确认一下」钉住 —— 它是日历上「长按拖选」与「调整班次」的闸门：

```dart
test('hasCycle：按月方案算「有班次可挑」（它从 isBlank 推出来，不该另写一份判据）', () {
  expect(ScheduleChain(fallback: monthSchedule()).hasCycle, isTrue);
  // 空白表（monthly=true 且段表空）仍然算「没有」
  expect(ScheduleChain(fallback: monthSchedule(segments: const [])).hasCycle, isFalse);
});
```

- [ ] **Step 2: 跑一遍，确认它红**

Run: `flutter test test/schedule_chain_test.dart`
Expected: `rotationKey` 那条**红**（`a` / `b` / `c` 三处算出来相同）；`hasCycle` 那条**应当是绿的** —— 它绿的这件事本身就是「`hasCycle` 不用单独改」的证据，若它红了说明 Task 2 的 `isBlank` 写错了。

- [ ] **Step 3: 改 `_rotationOf`**

在 `_rotationOf(s)` 拼出来的那个字符串里加三段：`s.monthly`、段的 `startDay:classIndex` 串、`s.teamSegOffsets.join(",")`。**`_sourceKey` 一个字都不许动** —— 它的职责是「会影响信息卡高度」，加宽只会让缓存白失效（spec §5.4）。

- [ ] **Step 4: 跑测试**

Run: `flutter test test/schedule_chain_test.dart test/info_card_chain_test.dart test/widget_push_dedup_test.dart`
Expected: 全 PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/domain/schedule_chain.dart app/test/schedule_chain_test.dart
git commit -m "fix(domain): rotationKey 带上按月切法（改完界面没跟上那类静默问题）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: 数据层：段表 + 新列 + 迁移

**Files:**
- Modify: `app/lib/data/app_database.dart`
- Regenerate: `app/lib/data/app_database.g.dart`
- Test: `app/test/migration_v13_to_v14_test.dart`（新建）、`app/test/migration_v10_to_v14_test.dart`（新建）

**Interfaces:**
- Produces:
  - 表类 `ScheduleMonthSegmentRows`（列：`id` / `scheduleId` / `order` / `startDay` / `classId`），并加进 `@DriftDatabase(tables: [...])`
  - `ShiftScheduleRows` 增 `BoolColumn monthly`（默认 false）与 `TextColumn teamSegOffsets`（默认 `''`）
  - `CustomTemplates` 增 `BoolColumn monthly`（默认 false）、`TextColumn monthSegments`（默认 `''`）、`TextColumn teamSegOffsets`（默认 `''`）
  - `schemaVersion` **14**

- [ ] **Step 1: 写失败的迁移测试** `app/test/migration_v13_to_v14_test.dart`

照 `app/test/migration_v12_to_v13_test.dart` 的写法：手抄 **v13 形态**的建表 DDL + 插几条真实数据（一套方案 + 班次 + 周期 + 一条闹钟 + 一条按天覆盖 + 一条「我的模板」），升到 v14 之后断言：

- 上面六样**逐项不变**（比日期一律走 `dayNumber`）；
- 新列的默认值到位：`monthly = 0`、`team_seg_offsets = ''`、模板那三列同理；
- `schedule_month_segment_rows` 建出来了、能写能读。

- [ ] **Step 2: 跑一遍，确认它红**

Run: `flutter test test/migration_v13_to_v14_test.dart`
Expected: FAIL（schema 还是 13 / 新表不存在）。

- [ ] **Step 3: 改 `app/lib/data/app_database.dart`**

1. 新表类 `ScheduleMonthSegmentRows`，紧挨着 `ShiftCycleRows` 放。类文档写明：与 `ShiftCycleRows` 同形（`order` 是段序、`startDay` 是每月的第几天、`classId` 指 `shift_class_rows.id`）；**存 `classId` 而不是 `classes` 下标**，理由与周期序列那条一样（下标会随编辑器增删班次而挪）。**表名必须带 `Rows` 后缀**（drift 会按表名生成行类）。
2. `ShiftScheduleRows` 加两列；`CustomTemplates` 加三列，都写清默认值。
3. `tables: [...]` 里加上新表。
4. `schemaVersion => 14`。
5. `onUpgrade` 新增分支，**放在 `from < 13` 之前**（分支按倒序跑，最新的一版先跑）：

```dart
if (from < 14) {
  await m.createTable(scheduleMonthSegmentRows);
  await m.addColumn(shiftScheduleRows, shiftScheduleRows.monthly);
  await m.addColumn(shiftScheduleRows, shiftScheduleRows.teamSegOffsets);
  await m.addColumn(customTemplates, customTemplates.monthly);
  await m.addColumn(customTemplates, customTemplates.monthSegments);
  await m.addColumn(customTemplates, customTemplates.teamSegOffsets);
}
```

   注释写明：**必须放在 `from < 13` 之前** —— 那一段会 `TableMigration(shiftScheduleRows)` 重建方案表，先加列才安全（重建按当前 schema 走、按列名拷数据，新列带默认值过去）。`custom_templates` 是**三**列，别少写一列。

6. `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 4: 再写一条 v10 → v14 的迁移测试** `app/test/migration_v10_to_v14_test.dart`

同形，但从 v10 形态的库直接升上来（盖住「新列加完之后后面还有好几段重建在跑」这条组合路径）。断言的也是「老数据逐项不变 + 新列有默认值」。

- [ ] **Step 5: 跑全部迁移测试**

Run: `flutter test test/migration_v5_to_v6_test.dart test/migration_v6_to_v7_test.dart test/migration_v7_to_v8_test.dart test/migration_v8_to_v9_test.dart test/migration_v9_to_v10_test.dart test/migration_v10_to_v11_test.dart test/migration_v11_to_v13_test.dart test/migration_v12_to_v13_test.dart test/migration_v13_to_v14_test.dart test/migration_v10_to_v14_test.dart && flutter analyze`
Expected: 全 PASS；0 error / 0 warning。

- [ ] **Step 6: 提交**

```bash
git add app/lib/data/app_database.dart app/lib/data/app_database.g.dart app/test/migration_v13_to_v14_test.dart app/test/migration_v10_to_v14_test.dart
git commit -m "feat(data): 按月段表 + 方案/模板新列，schema 13 → 14

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: 仓库装配：读 / 写 / 删

**Files:**
- Modify: `app/lib/data/app_repository.dart`（`ActiveSchedule` / `_loadChildren` / `saveSchedule` / `deleteSchedule` / `clearAll`）
- Test: `app/test/monthly_schedule_repository_test.dart`（新建）、`app/test/widget_snapshot_test.dart`（追加一条 RF-2）

**Interfaces:**
- Consumes: Task 2 的三个字段与 `MonthlySegment`、Task 4 的表与列
- Produces:
  - `ActiveSchedule` 增字段 `List<ScheduleMonthSegment> monthSegments`（默认 `const []`）；`toDomain()` 里把 `classId` 换算成 `classes` 下标、带出 `monthly` / `monthlySegments` / `teamSegOffsets`（`teamSegOffsets` 走既有的 `parseTeamOffsets`）
  - `saveSchedule({... bool monthly = false, List<MonthlySegment> monthSegments = const [], List<int> teamSegOffsets = const []})`
  - 三个新参数**都有默认值** —— 既有调用点一处都不用改

- [ ] **Step 1: 写失败的测试** `app/test/monthly_schedule_repository_test.dart`

```dart
test('往返：存一套按月方案，读回来逐项一致', () async {
  final id = await repo.saveSchedule(
    name: '按月', anchorDate: dateOnly(DateTime(2026, 1, 1)),
    classes: [中班, 白班, 夜班], cycle: const [],
    monthly: true,
    monthSegments: const [
      MonthlySegment(startDay: 1, classIndex: 0),
      MonthlySegment(startDay: 11, classIndex: 1),
      MonthlySegment(startDay: 21, classIndex: 2),
    ],
    teamCount: 3, teamSegOffsets: const [0, 1, 2],
  );
  final d = (await repo.getScheduleDomain(id))!;
  expect(d.monthly, isTrue);
  expect(d.monthlySegments, const [/* 同上三段的等值对象 */]);
  expect(d.teamSegOffsets, [0, 1, 2]);
  expect(d.cycle, isEmpty);
  expect(d.shiftOn(DateTime(2026, 12, 1))!.name, '中班');
});

// RF-4
test('删掉一个还被段引用着的班次，段行一起被清掉', () async {
  // 存三段 → 把第三段那个班次从 classes 里去掉再存一次
  // 断言：库里没有引用它的段行、也没有悬空的 classId
});

test('deleteSchedule / clearAll 连带删段行', () async { /* 各一条 */ });

// RF-2 —— 写在 widget_snapshot_test.dart 里（buildWidgetSnapshot 是纯函数，
// 拿一条按月方案的 ScheduleChain 直接调即可，照那个文件既有用例的写法）
test('快照跨月：12/31 与次年 1/1 各归各的', () {
  // 断言快照窗口里 12/31 的 shiftAbbr 是「夜」、次年 1/1 是「中」
});
```

- [ ] **Step 2: 跑一遍，确认它红**

Run: `flutter test test/monthly_schedule_repository_test.dart`
Expected: FAIL（`saveSchedule` 不认 `monthly` 等参数）。
（`widget_snapshot_test.dart` 里新加的那条**现在就该是绿的** —— 快照走的是 `shiftOn`，它不需要 Task 5 的任何改动。它绿着进仓库，是为了**以后谁动了这条路它立刻红**。）

- [ ] **Step 3: 改 `app/lib/data/app_repository.dart`**

1. `ActiveSchedule` 加 `monthSegments` 字段与构造参数（默认空表，既有构造点不动）。
2. `ActiveSchedule.toDomain()`：把段行按 `classId → 下标` 换算（查不到的**跳过**，与覆盖行那条同口径）、`monthly: schedule.monthly`、`teamSegOffsets: parseTeamOffsets(schedule.teamSegOffsets)`。
3. `_loadChildren`：多查一次段表（`..where(scheduleId 相等)..orderBy(order 升序)`），塞进 `ActiveSchedule`。
4. `saveSchedule`：签名加三个具名参数；方案行 insert / update 带上 `monthly` 与 `teamSegOffsets`；在写周期行那一段**旁边**「先删后插」段行（`classIds[classIndex]` 换算 classId，越界跳过）；**悬空清理那一段**里，删班次时连带删引用它的段行（照它删 `shiftDayOverrides` 的写法）。
5. `deleteSchedule` 与 `clearAll`：各加一次 `db.delete(db.scheduleMonthSegmentRows)`（`clearAll` 里排在班次定义**之前**，与周期行同一条「先子后父」的顺序）。

- [ ] **Step 4: 跑测试**

Run: `flutter test test/monthly_schedule_repository_test.dart test/widget_snapshot_test.dart test/day_override_repository_test.dart test/save_schedule_current_test.dart test/factory_reset_test.dart && flutter analyze`
Expected: 全 PASS；0 error / 0 warning。

- [ ] **Step 5: 提交**

```bash
git add app/lib/data/app_repository.dart app/test/monthly_schedule_repository_test.dart
git commit -m "feat(data): 按月段表的读写与连带删除

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: 「我的模板」承载按月配置

**Files:**
- Modify: `app/lib/domain/schedule_template.dart`
- Modify: `app/lib/data/app_repository.dart`（`saveTemplate` / `listTemplates` 三列）
- Test: `app/test/schedule_template_test.dart`（追加）、`app/test/saved_template_test.dart`（追加）

**Interfaces:**
- Consumes: Task 1 的 `MonthlySegment`、Task 2 的 `monthly` / `teamSegOffsets`
- Produces:
  - `ScheduleTemplate` 增 `bool monthly`、`List<MonthlySegment> monthlySegments`、`List<int> teamSegOffsets`
  - `String encodeTemplateMonthSegments(List<MonthlySegment>)` / `List<MonthlySegment> decodeTemplateMonthSegments(String)`（`startDay:classIndex` 逗号分隔，**容错**：坏项丢掉）
  - `ScheduleTemplate.fromSchedule` 归一化时**连段偏移一起归一化**

- [ ] **Step 1: 写失败的测试**（追加）

```dart
test('按月的模板往返同构', () { /* fromSchedule → 编码 → 解码 → 段表与 monthly 一致 */ });

test('归一化：我们班组转到第 0 位、段偏移相对它归零（模段数取正）', () {
  // ourTeamIndex = 2、teamSegOffsets = [0, 1, 2]（段数 3、3 组）
  // 归一化后 ourTeamIndex == 0、teamSegOffsets == [0, 1, 2]（相对 2 号组平移）
});

test('段串的坏数据不炸：解析不出来的那一段丢掉', () {
  expect(decodeTemplateMonthSegments('1:0,11:bogus,21:2').length, 2);
  expect(decodeTemplateMonthSegments('').length, 0);
});
```

- [ ] **Step 2: 跑一遍，确认它红** → `flutter test test/schedule_template_test.dart`

- [ ] **Step 3: 改 `schedule_template.dart`**

`ScheduleTemplate` 加三个字段（`monthly` / `monthlySegments` / `teamSegOffsets`，后两个给默认值，且**列偏移的编码与 `cycle` 那套同一条容错口径**）。`workingTeamsPerDay` 加按月分支：段表为空返回 0，否则按**每月 1 日那一档**数非休班的班组数（用 `monthlyClassIndexOn(monthlySegments, 1, off)`）。`fromSchedule` 在既有的整体平移之后，再对 `teamSegOffsets` 做同一次旋转 + 减去基准偏移，**再对段数取模**（Dart 的 `%` 恒非负，直接 `%` 即可）；`monthlySegments.length == 0` 时 `teamSegOffsets` 给空表。

- [ ] **Step 4: 改 `saveTemplate` / `listTemplates`**（三列读写），并在 `saved_template_test.dart` 里追加一条「按月的模板存下来、选择页读得到」。

- [ ] **Step 5: 跑测试**

Run: `flutter test test/schedule_template_test.dart test/saved_template_test.dart && flutter analyze`
Expected: 全 PASS。

- [ ] **Step 6: 提交**

```bash
git add app/lib/domain/schedule_template.dart app/lib/data/app_repository.dart app/test/schedule_template_test.dart app/test/saved_template_test.dart
git commit -m "feat(template): 我的模板承载按月切法与段偏移

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: 编辑器：模式切换 + 按月段列表

**Files:**
- Modify: `app/lib/core/l10n.dart`
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`
- Test: `app/test/monthly_schedule_editor_test.dart`（新建）

**Interfaces:**
- Consumes: Task 2 / Task 5
- Produces（界面契约，测试与后续任务都靠它们）：
  - 分段器的段位：`0` = 按周期、`1` = 按月（`GlassSegment(count: 2, selectedIndex: _monthly ? 1 : 0, ...)`）
  - 按月段列表中第 i 行日号的可点文本 key：`monthRowDayKey(int i)`
  - 按月段列表中第 i 行、第 j 个班次胶囊的 key：沿用既有的 `cycleChipKey(i, j)`（同一时刻只有一张列表在屏上）
  - 「添加一段」那颗按钮的 key：`const Key('month-add-segment')`
  - 顶部那张卡的「我这组从这个周期开始」那一行在按月模式下**不出现**

- [ ] **Step 1: 先加 l10n 键**

在 `app/lib/core/l10n.dart` 里**先 grep 一遍撞键**（`nextDay` / `myCycleStart` 那两处都是踩过的），再按现有 `t(zh, en)` 写法加：

| 键 | 中文 | 英文 |
|---|---|---|
| `scheduleModeCycle` | 按周期 | By cycle |
| `scheduleModeMonthly` | 按月 | By month |
| `monthlySection` | 按月切法 | Monthly split |
| `monthlyFromDay(int n)` | 每月第 $n 天起 | From day $n |
| `monthlyAddSegment` | 添加一段 | Add a segment |
| `monthlyDeleteSegmentTitle` / `monthlyDeleteSegmentContent(String day)` | 删掉这一段 / 这一段的班次会并到上一段（从第 $day 天起往后都跟着上一段）。 | … |
| `monthlyCrewHint` | 各班组按段错开，都在每月同一天换班。 | Teams swap shifts every segment, all on the same day of the month. |

- [ ] **Step 2: 写失败的界面测试** `app/test/monthly_schedule_editor_test.dart`

```dart
test('切到「按月」：出段列表、周期行消失；切回去周期还在', () async {
  // RF-5 —— 这一条同时钉住「切换不丢数据」与「当前模式说了算」
});

test('第一次切到按月：段表按班组数种出来、且不撞班', () async {
  // 断言 editor-crew-clash-hint 不出现（4 班组 4 段，均分 0/1/2/3）
});

test('按月模式的预览条逐格等于领域层算出来的班次', () async {
  // 造一套 1/11/21 的按月方案，把预览条 14 格与 shiftOn 逐个比
});

test('添加一段 / 日号选项器只列合法值 / 删中间一段并进上一段', () async {
  // 删第二段之后：第一段吃 1–20、第三段仍从 21 起（总覆盖不出现空档）
});
```

- [ ] **Step 3: 跑一遍，确认它红** → `flutter test test/monthly_schedule_editor_test.dart`

- [ ] **Step 4: 改编辑器状态与保存链路**

1. 三个新状态：`bool _monthly = false;`、`List<MonthlySegment> _monthlySegments = [];`、`List<int> _teamSegOffsets = [];`
2. `_load` 里读：`_monthly = dd.monthly; _monthlySegments = List.of(dd.monthlySegments);`、`_teamSegOffsets` 照 `_teamOffsets` 那条「长度不够就按 `i - ourTeamIndex` 补」的写法补。
3. `_draftSchedule()` 带上这三个 —— **漏了的话预览与撞班检查会静默停在周期模式**（审查点过名）。
4. `_save()` 把三个传给 `saveSchedule`。

- [ ] **Step 5: 加界面**

「周期设置」这张卡（`_cycleCard`）的最上面加一行 `GlassSegment`（两段：「按周期」/「按月」）：
- 选「按周期」→ 现在那条步进器 + 周期行，原样。
- 选「按月」→ 整组换成 `_monthRows(context)`：一行一段，左边是**可点的**「每月第 N 天起」（`Key` 用 `monthRowDayKey(i)`，与 `cycleChipKey` 一样做成顶层函数，方便用例按行点；第一行固定 `1`、且不给删除键），中间与右边沿用 `_cycleRow` 那套（`GlassChoiceChip` + 只在放得下时显示的时段文字），行末 `GlassDeleteButton(compact: true)`；列表末尾一行「添加一段」，`Key` 用 `const Key('month-add-segment')`。
- **第一次**从周期切到按月且 `_monthlySegments` 为空时，种 `defaultMonthlySegments(_teamCount)`（Task 1 的），并把 `_teamSegOffsets` 设成 `List.generate(_teamCount, (i) => i)`。**只在空的时候种**，不冲掉用户排好的段表。
- 日号可点 → `showGlassOptionPicker`，只列**合法**的日号：`上一段 + 1 .. 31 - (后面还有几段)`。
- **删一段 = 把它并进上一段**：删掉下标 i 的段之后，它的日子归上一段（第一段删不了，因为它恒在 1 起）。这条要写进注释 —— 它是唯一能保持「不覆盖出现空档」的删法。
- 顶部那张卡的「我这组从这个周期开始」那一行在 `_monthly` 时**不渲染**。

- [ ] **Step 6: 跑测试**

Run: `flutter test test/monthly_schedule_editor_test.dart test/schedule_editor_test.dart && flutter analyze`
Expected: 全 PASS；既有编辑器用例一条不许改绿。

- [ ] **Step 7: 提交**

```bash
git add app/lib/core/l10n.dart app/lib/features/calendar/schedule_editor_screen.dart app/test/monthly_schedule_editor_test.dart
git commit -m "feat(editor): 按月切法的模式切换与段列表

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: 编辑器：班组按段错位、撞班提示、空白表开关

**Files:**
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`
- Modify: `app/lib/core/l10n.dart`
- Test: `app/test/monthly_schedule_editor_test.dart`（追加）

**Interfaces:**
- Consumes: Task 7 的状态、Task 2 的 `crewClashes` / `evenTeamOffsets`
- Produces:
  - 班组行在按月模式下显示「从第 N 段开始」（可点 → 选项器列 `1..段数`），替换掉「周期起始日 <日期>」那一行
  - `_evenCrewStarts()` 在按月模式下对 `_teamSegOffsets` 做均分
  - `_deleteClass(i)` 的「还引用着」判据**同时数周期与段表**，重映射也同时做两边
  - `_setFollowHoliday` 切到空白表时清空 `_monthly` / `_monthlySegments` / `_teamSegOffsets`
  - `_saveAsTemplate` 的闸门从「`_cycle.isEmpty` 就拦」改成「周期与段表都空才拦」

- [ ] **Step 1: 写失败的测试**（追加）

```dart
test('按月模式下班组行写「从第 N 段开始」，改它会影响那组当月 1 日上什么班', () async {});
test('撞班提示：3 段 4 组时报得出、且文案里没有数字；点均分之后消失', () async {});
test('删一个还被段引用着的班次：拦下，提示写清被引用了几段', () async {});
test('切到「跟随法定节假日」再切回来：按月那套被清干净，回到默认四班两倒', () async {});
test('按月方案可以存成模板（不再被「没有周期」拦下）', () async {});
```

- [ ] **Step 2: 跑一遍，确认它红** → `flutter test test/monthly_schedule_editor_test.dart`

- [ ] **Step 3: 改代码**

1. `_crewRow` 那一行日期：`_monthly` 时换成 `L10n.crewSegmentStart(k)`（新键，中文「从第 $k 段开始」），点它弹 `showGlassOptionPicker` 列 `1.._monthlySegments.length`。
2. `_crewCard` 底部的说明：`_monthly` 时用 `L10n.monthlyCrewHint`，否则用现有的 `L10n.teamHint`。
3. `_crewClashNotice`：`crewClashes(_draftSchedule())` 之后，**按月那一支不算 `days`、文案走一句不带数字的**（新键 `crewClashHintMonthly(teamA, teamB)`，中文「$a 与 $b 会在同一天上同一个班」）；周期那一支原样。
4. `_evenCrewStarts`：`_monthly` 时传 `_monthlySegments.length` 与当前的 `_teamSegOffsets`，写回 `_teamSegOffsets`；否则原样。
5. `_deleteClass`：`used` 改成周期里出现的次数 **+** 段表里出现的次数（`_monthlySegments.where((s) => s.classIndex == index).length`），提示文案沿用「被引用 N 次」那条（N 是两边的和）；确认通过之后，**两边一起做下标重映射**（`> index` 的整体 `--`）。
6. `_setFollowHoliday`：切到空白表时把 `_monthly = false`、`_monthlySegments = []`、`_teamSegOffsets = []` 一起清掉；切回来恢复默认时同样重置。
7. `_saveAsTemplate`：闸门改成 `_followHoliday || _classes.isEmpty || (_cycle.isEmpty && _monthlySegments.isEmpty)`。

- [ ] **Step 4: 跑测试**

Run: `flutter test test/monthly_schedule_editor_test.dart test/schedule_editor_test.dart test/saved_template_test.dart && flutter analyze`
Expected: 全 PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/schedule_editor_screen.dart app/lib/core/l10n.dart app/test/monthly_schedule_editor_test.dart
git commit -m "feat(editor): 按月模式的班组按段错位、撞班提示与空白表开关

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: 选择页：「按月排班」那张卡

**Files:**
- Modify: `app/lib/features/calendar/shift_template_picker_screen.dart`
- Modify: `app/lib/core/l10n.dart`
- Test: `app/test/shift_template_picker_test.dart`（追加）

**Interfaces:**
- Consumes: Task 1 的 `defaultMonthlySegments`、Task 5 的 `saveSchedule`
- Produces:
  - `ShiftTemplateChoice.monthly()` 第三个变体（与 `.custom()` 平级）
  - `createScheduleFromTemplatePicker` 认这个变体：建一套 `monthly: true` 的方案
  - l10n 键 `monthlyPattern`（按月排班 / Monthly roster）、`monthlyPatternHint`（每个月重复一套切法 / The same split repeats every month）

- [ ] **Step 1: 写失败的测试**（追加到 `app/test/shift_template_picker_test.dart`）

```dart
test('「按月排班」卡片在「我自己排」旁边，点它建出来的是一套按月方案', () async {
  // 点卡片 → 断言库里新方案 monthly == true、段表 == defaultMonthlySegments(3)、
  // cycle 为空；再断言领域层 shiftOn(某月 1 日) 是第一个班次
});
```

- [ ] **Step 2: 跑一遍，确认它红** → `flutter test test/shift_template_picker_test.dart`

- [ ] **Step 3: 改代码**

1. `ShiftTemplateChoice` 加 `.monthly()` 变体（`bool monthly` 标志位，与 `custom` 同形）。
2. 选择页加 `_monthlyCard(context)`：**复用 `_patternCard`** —— 色条传**段的班次下标序列**（一「格」= 一段），`classes` 传 `defaultSchedule().classes`，`workingTeamsPerDay` 传 3。位置贴着 `_customCard`（排在它前面）。它**不参与搜索**（与「我自己排」同待遇）。
3. `createScheduleFromTemplatePicker` 加一条分支：选的是按月时，

```dart
final d = defaultSchedule();
return ref.read(appRepositoryProvider).saveSchedule(
      name: L10n.monthlyPattern,
      anchorDate: dateOnly(DateTime.now()),
      classes: d.classes,
      cycle: const [],
      monthly: true,
      monthSegments: defaultMonthlySegments(3),
      teamCount: 3,                       // ← 见下
      teamNames: L10n.defaultTeamNames(3),
      ourTeamIndex: 0,
      teamOffsets: const [],
      teamSegOffsets: const [0, 1, 2],
      makeCurrent: makeCurrent,
    );
```

   ⚠️ **班组数取 3 是有理由的、不是随手写的**：默认的 4 组配 3 段**必然撞班**（`round(i×3÷4)` = 0/1/2/2），选完卡片当场弹撞班提示。三班倒正是这个功能的来处，3 段 3 组天然不撞；用户要改成别的班组数，在「班组设置」里改、撞班提示会带他点「均分」。

- [ ] **Step 4: 跑测试**

Run: `flutter test test/shift_template_picker_test.dart test/seed_locale_test.dart && flutter analyze`
Expected: 全 PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/shift_template_picker_screen.dart app/lib/core/l10n.dart app/test/shift_template_picker_test.dart
git commit -m "feat(picker): 新建排班多一条「按月排班」的起步

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: 排班管理页那一行

**Files:**
- Modify: `app/lib/features/calendar/schedule_management_screen.dart`
- Modify: `app/lib/core/l10n.dart`
- Test: `app/test/schedule_management_test.dart`（**仓库里还没有这个文件**，新建；挂载这个页面的写法照 `app/test/schedule_timeline_test.dart` —— 它挂的就是同一个页面）

**Interfaces:**
- Consumes: `ShiftScheduleRow.monthly`、`ActiveSchedule` 的段数
- Produces: l10n 键 `scheduleMonthlySummary(int segments)`（每月 $segments 段 / $segments segments a month）

- [ ] **Step 1: 写失败的测试**

```dart
test('按月方案那一行印切法摘要，不印基准日', () async {
  // 造一套按月方案 + 一套周期方案
  // 断言：按月那行含「每月 3 段」、不含 monthDay(anchorDate)；
  //       周期那行仍含 monthDay(anchorDate)
});
```

- [ ] **Step 2: 跑一遍，确认它红**

- [ ] **Step 3: 改 `schedule_management_screen.dart:76-82`**

副标题尾巴那一段按 `s.monthly` 分叉：按月印 `L10n.scheduleMonthlySummary(段数)`，否则印 `L10n.monthDay(s.anchorDate)`。段数从已经装配好的 `ActiveSchedules.all` 那一份里取（别为它再查一次库）。

- [ ] **Step 4: 跑测试 + `flutter analyze`**

Run: `flutter test test/schedule_management_test.dart && flutter analyze`
Expected: 全 PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/schedule_management_screen.dart app/lib/core/l10n.dart app/test/schedule_management_test.dart
git commit -m "fix(management): 按月方案那一行不再印一个不再生效的基准日

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: 视觉工装屏单

**Files:**
- Modify: `app/tool/visual/visual_harness.dart`（加 `makeMonthlyScheduleCurrent(db)` 之类的种子）
- Modify: `app/tool/visual/visual_screens.dart`（加屏单）
- Test: 工装自身（`flutter test tool/visual/`）

**Interfaces:**
- Consumes: Task 2 的 `ShiftSchedule` 三个字段、Task 4 的表
- Produces: 三条新屏单（slug 从 **57** 起，当前最大是 `56_calendar_new_colors`）

- [ ] **Step 1: 加种子** `makeMonthlyScheduleCurrent(db)`：把当前方案换成「段表 1/11/21 → 中/白/夜、3 个班组、段偏移 0/1/2」（用户那张表的形状）。
- [ ] **Step 2: 加屏单**
  - `57_editor_monthly`（排班编辑器 · 按月）—— 浅色 / 深色各一张。
  - `58_template_picker_monthly`（倒班方式选择 · 按月排班那张卡）。
  - `59_preview_month_boundary`（排班编辑器 · 预览条跨月）—— 今天落在月末往前 14 天那个位置，一眼能看出归零。
- [ ] **Step 3: 出图看图**

Run: `flutter test tool/visual/`（先照 `app/tool/visual/README` 或既有写法确认出图目录）
Expected: 全 PASS，并把新图**逐张看过**：段列表排得下、日号没有被截、分段器两种模式的选中态对、跨月那张图上一眼看得见「1 号变回中班」。

- [ ] **Step 4: 提交**

```bash
git add app/tool/visual/visual_harness.dart app/tool/visual/visual_screens.dart
git commit -m "feat(visual): 屏单补按月模式三屏

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: 版本号与更新日志

**Files:**
- Modify: `app/pubspec.yaml`（`version:`）
- Modify: `app/lib/core/app_info.dart`（`appVersion`）
- Modify: `app/lib/features/profile/app_dialogs.dart`（`_changelogZh` / `_changelogEn`）

**Interfaces:** 无（收尾）

- [ ] **Step 1: 定版本号**

`0.11.14+161` → **`0.11.15+162`**（`X.Y` 由用户定、AI 只动末位 `Z`；`+build` 同步 +1）。**两处一起改**（`app_info_test.dart` 盯着）。

- [ ] **Step 2: 更新日志 prepend 一条**

`_changelogZh` / `_changelogEn` 各在最前面插一条 `0.11.15` 的**测试版条目**（原样写这一版改了什么，**不做归纳** —— 归纳只在正式版做），并**删掉最旧的那一条**保持窗口恒 10 条（`changelog_window_test.dart` 盯着）。条目里**不许出现 markdown 标记**（`**` / 反引号 / 行首 `#` / `[文字](链接)`）—— 更新日志是纯文本渲染的，同一个坑犯过两次。

条目要写到的话：排班方案现在可以选「按月切段」（每月 1 号重新归零，比如 1–10 中班、11–20 白班、剩下夜班），多班组按段错开；老的周期方案原样不动。

- [ ] **Step 3: 跑验收**

Run: `flutter analyze && flutter test`
Expected: 0 error / 0 warning；全部用例 PASS，**条数 ≥ 933 + 本轮新增**。

- [ ] **Step 4: 提交**

```bash
git add app/pubspec.yaml app/lib/core/app_info.dart app/lib/features/profile/app_dialogs.dart docs/superpowers/specs/2026-10-13-monthly-schedule-design.md docs/superpowers/plans/2026-10-13-monthly-schedule.md
git commit -m "chore(release): v0.11.15 按月排班

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 5: 真机复验（spec §8 最后一段）**

装上这一版之后做两件事，两条都要亲眼看到：

1. **照用户那张 12 月的截图造一套**（3 段 1/11/21、班组数 1）—— 确认**12 月 1 日显示中班**，而且 10 月与 12 月的切法一模一样。
2. **配 3 个班组** —— 在「查看其他班组」里确认三组互不撞班，而且都在 1 / 11 / 21 号换班。

发布按 AGENTS.md「分支与发布」：测试版走 **beta** 分支、`git tag v0.11.15`、`scripts/release.ps1`，发完 curl 一次 `main` 上的 `latest.json` 核对。

---

## 留给实施时的三个判断

1. **`MonthlySegment` 放在新文件里**（计划已按这个写）：`domain/monthly_pattern.dart` 只处理整数、不碰 `DateTime`，`shift_rotation.dart` 负责提取日号。这样既没有循环依赖，规则本身也能纯整数测。
2. **选择页那张卡种 3 段 / 3 组**（Task 9）：4 组配 3 段必然撞班，理由写在那个任务的 Step 3 里。**这是计划里我自己定的、spec 没写的** —— 若觉得该保持 4 组，把段数一起改成 4（`defaultMonthlySegments(4)` + `teamSegOffsets: [0,1,2,3]`）即可。
3. **编辑器第一次切换时种 `defaultMonthlySegments(_teamCount)` 而不是一段**（Task 7）：spec §6.2 原稿写的是 `[(1,0)]`，但那样在 4 个班组时会**一进去就撞班**；按班组数种段在 1 个班组时正好退化成 `[(1,0)]`，所以这条与 spec 的意图一致、只是把班组数>1 那一半补上了。
