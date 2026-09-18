# 按天改班（换班 / 请假覆盖）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户能在日历上对某一天或连续的一段日子单独指定班次（请假 / 跟同事调班），不动整张轮转表，且联动闹钟自动跟着变。

**Architecture:** 新增一张 Drift 覆盖表 `shift_day_overrides`（复合主键 `scheduleId + day`，指向 `shift_class_rows.id`），把它装配进领域对象 `ShiftSchedule.dayOverrides`，由覆盖感知的 `shiftOn()` 作为「某天是什么班」的**唯一出口** —— 日历格子、底栏信息卡、闹钟重排、闹钟页 30 天四个消费者因此全都不用改。为了让覆盖引用的 `classId` 在每次保存方案后仍然有效，同时把 `saveSchedule` 从「删光重建班次行」改成增量保存。

**Tech Stack:** Flutter / Dart、Riverpod、Drift（SQLite）、自研液态玻璃设计系统（`AppTokens` 角色令牌）

**Spec:** `docs/superpowers/specs/2026-09-18-per-day-shift-override-design.md`

## Global Constraints

- **版本号**：目标 `0.8.1+92`。`X.Y` 由用户决定（本轮已定 0.8.1），AI **只改末位 `Z` 与 `build`**。`app/pubspec.yaml` 的 `version:` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须同步改，`app/test/app_info_test.dart` 盯着这条。
- **不要跑 `dart format`**：工具链是新版 tall style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `flutter analyze`。
- **改 Drift 表后必须重生成**：`dart run build_runner build --delete-conflicting-outputs`。
- **构建环境变量**：bash 里跑任何 Flutter 命令前都要 `export ANDROID_HOME/JAVA_HOME/GRADLE_USER_HOME` 指向 `toolchain/`（或先 `. tools/build-env.ps1`），否则 Gradle 会去 `~/.gradle` 下载到超时。
- **验收标准**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿（当前 170 条，**只增不减**）。
- **设计令牌**：界面层只写 `AppTokens` 的角色名，不写字面量 —— 字号（`fontSize:`）、字重（`fontWeight:`）、`onSurface` 系文字明度（`.withValues(alpha: …)`）、圆角（`circular(…)`）、`Duration(milliseconds: …)`、`Color(0x…)`、图标尺寸（`Icon`/`IconThemeData` 的 `size:`）一律不许写死；由 `app/test/design_tokens_test.dart` 整文件级扫描把关。确需豁免要写 `// design-tokens-ignore: <理由>`。
- **弹窗配方**：遮罩统一 `barrierColor: Colors.black26`（不能更暗）；底部弹层用 `GlassPanel(solid: true)`。
- **文案**：一律 zh / en 成对（`L10n.t(zh, en)`），中文不许漏进英文界面。
- **测试文件顶部注释**：本项目惯例是在测试文件头写一段说明「这个文件在测什么、为什么」。新写的测试照做。

---

## File Structure

| 文件 | 职责 | 动作 |
|---|---|---|
| `app/lib/data/app_database.dart` | 新表 `ShiftDayOverrides` + schema 7→8 迁移 | Modify |
| `app/lib/domain/shift_rotation.dart` | `ShiftClass.id`；`ShiftSchedule.dayOverrides`；覆盖感知的 `shiftOn` | Modify |
| `app/lib/data/app_repository.dart` | 装配覆盖进领域对象；`saveSchedule` 增量；覆盖写入口 | Modify |
| `app/lib/core/l10n.dart` | 新文案 | Modify |
| `app/lib/features/calendar/shift_override_picker.dart` | 选择层（**新建**）：列出班次 + 恢复轮转 | Create |
| `app/lib/features/calendar/calendar_screen.dart` | 信息卡入口、格子小圆点、长按拖选 | Modify |
| `app/lib/features/calendar/schedule_editor_screen.dart` | `_editClass` 保住 id；预览提示 | Modify |
| `app/lib/features/profile/app_dialogs.dart` | 更新日志条目 | Modify |
| `app/lib/core/app_info.dart` + `app/pubspec.yaml` | 版本号 | Modify |
| `app/test/migration_v7_to_v8_test.dart` | 迁移用例 | **Create** |
| `app/test/day_override_repository_test.dart` | 仓库层用例 | **Create** |
| `app/test/shift_override_picker_test.dart` | 选择层与日历交互用例 | **Create** |
| `app/test/shift_rotation_test.dart` | 领域层用例 | Modify |
| `app/test/calendar_screen_test.dart` | 信息卡入口用例 | Modify |

**任务边界依据**：Task 1–5 是数据链路（表 → 领域 → 装配 → 保存 → 写入口），每层都有独立可测的产出；Task 6–9 是界面；Task 10–12 是收尾。每个任务都能单独被评审通过或打回。

---

### Task 1: Drift 新表 `ShiftDayOverrides` + v7→v8 迁移

**Files:**
- Modify: `app/lib/data/app_database.dart`
- Create: `app/test/migration_v7_to_v8_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: Drift 表 `shiftDayOverrides`（列 `scheduleId` / `day` / `classId`，复合主键 `{scheduleId, day}`）、生成的伴生类 `ShiftDayOverridesCompanion` 与数据类 `ShiftDayOverride`；`AppDatabase.schemaVersion == 8`

- [ ] **Step 1: 写失败的迁移测试**

创建 `app/test/migration_v7_to_v8_test.dart`：

```dart
// app/test/migration_v7_to_v8_test.dart
//
// v7 → v8 只**新增一张表**：`shift_day_overrides`（按天改班 / 请假覆盖）。
// 这条迁移不碰任何既有表的列，所以 fixture 只需要一张 `shift_schedule_rows`
// 来验「老数据还在」，不必像 v5→v6 那条那样抄全套（那条会重建表、碰好几张表）。
//
// 要验三件事：新表建出来了、老排班原样保留、新表真的能写能读。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v7 时期的 `shift_schedule_rows`（v8 没有改动它）。
const _v7ScheduleTable = '''
CREATE TABLE shift_schedule_rows (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  anchor_date INTEGER NOT NULL,
  is_current INTEGER NOT NULL DEFAULT 0,
  team_count INTEGER NOT NULL DEFAULT 4,
  team_names TEXT NOT NULL DEFAULT '一班,二班,三班,四班',
  our_team_index INTEGER NOT NULL DEFAULT 0,
  team_offsets TEXT NOT NULL DEFAULT ''
)
''';

void main() {
  late sqlite3.Database raw;

  setUp(() {
    raw = sqlite3.sqlite3.openInMemory();
    raw.execute(_v7ScheduleTable);
    raw.execute(
      'INSERT INTO shift_schedule_rows '
      '(id, name, anchor_date, is_current, team_count, team_names, '
      'our_team_index, team_offsets) VALUES (1, ?, ?, 1, 4, ?, 0, ?)',
      [
        '四班两倒',
        DateTime.utc(2025, 1, 6).millisecondsSinceEpoch ~/ 1000,
        '一班,二班,三班,四班',
        '0,1,2,3',
      ],
    );
    raw.execute('PRAGMA user_version = 7');
  });

  tearDown(() => raw.dispose());

  test('v7 → v8：建出 shift_day_overrides，老排班原样保留', () async {
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final schedules = await db.select(db.shiftScheduleRows).get();
    expect(schedules, hasLength(1), reason: '老排班要原样留着');
    expect(schedules.single.name, '四班两倒');
    expect(schedules.single.teamOffsets, '0,1,2,3');

    // 新表建出来了
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty);

    // 而且能写能读
    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: 1,
            day: 20000,
            classId: 7,
          ),
        );
    final rows = await db.select(db.shiftDayOverrides).get();
    expect(rows, hasLength(1));
    expect(rows.single.day, 20000);
    expect(rows.single.classId, 7);
  });
}
```

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd app && flutter test test/migration_v7_to_v8_test.dart
```

期望：编译失败 —— `The getter 'shiftDayOverrides' isn't defined for the type 'AppDatabase'`。

- [ ] **Step 3: 加表、提 schemaVersion、写迁移**

在 `app/lib/data/app_database.dart` 的 `ShiftAlarmOverrides` 类**之后**、`@DriftDatabase` 注解**之前**插入：

```dart
/// 按天改班表：用户对某一天单独指定班次（换班 / 请假覆盖）。
///
/// 复合主键 `{scheduleId, day}`，覆盖**跟着方案走** —— 切到别的方案时这套覆盖
/// 不生效（「这天是什么班」整个都变了），删方案时连带删掉。
///
/// [day] 与 [ShiftAlarmOverrides.day] 同一个口径：纯日期自 epoch 的天数，
/// 由 `dayNumber()` 计算。[classId] 指向 `shift_class_rows.id`。
///
/// **与 [ShiftAlarmOverrides] 有意不一致**：那张表是全局的（只有 `day` 一个主键），
/// 因为它表达的是「那天别响」，跨方案也说得通；本表表达的是「那天上哪个班」，
/// 必然依附于某套方案的班次定义。别顺手把两者统一。
class ShiftDayOverrides extends Table {
  IntColumn get scheduleId => integer()();
  IntColumn get day => integer()();
  IntColumn get classId => integer()();

  @override
  Set<Column> get primaryKey => {scheduleId, day};
}
```

把 `@DriftDatabase(tables: [...])` 补上 `ShiftDayOverrides`：

```dart
@DriftDatabase(tables: [
  ShiftScheduleRows,
  ShiftClassRows,
  ShiftCycleRows,
  ScheduleEvents,
  CustomAlarms,
  ShiftAlarmOverrides,
  ShiftDayOverrides,
])
```

把 `schemaVersion` 改成 8，并在 `onUpgrade` 的**最前面**加一条（现有的分支是按版本倒序排的）：

```dart
  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 8) {
            // 按天改班（换班 / 请假覆盖）。纯新增一张表，不碰任何既有数据。
            await m.createTable(shiftDayOverrides);
          }
          if (from < 7) {
            // …以下保持原样，不动
```

- [ ] **Step 4: 重生成 Drift 代码**

```bash
cd app && dart run build_runner build --delete-conflicting-outputs
```

期望：`app/lib/data/app_database.g.dart` 里出现 `ShiftDayOverride` / `ShiftDayOverridesCompanion` / `$ShiftDayOverridesTable`。

- [ ] **Step 5: 跑测试确认通过**

```bash
cd app && flutter test test/migration_v7_to_v8_test.dart
```

期望：PASS。

再跑一次全量，确认没碰坏别的（schemaVersion 一改，`AppDatabase.forTesting` 的既有用例都会走一次 `onCreate`）：

```bash
cd app && flutter test
```

期望：全绿。

- [ ] **Step 6: 提交**

```bash
git add app/lib/data/app_database.dart app/lib/data/app_database.g.dart app/test/migration_v7_to_v8_test.dart
git commit -m "feat(db): 新增按天改班覆盖表 ShiftDayOverrides，schema 7→8"
```

---

### Task 2: 领域层 —— `ShiftClass.id`、`ShiftSchedule.dayOverrides`、覆盖感知的 `shiftOn`

**Files:**
- Modify: `app/lib/domain/shift_rotation.dart`
- Modify: `app/test/shift_rotation_test.dart`

**Interfaces:**
- Consumes: 无（纯 Dart，不依赖 Task 1）
- Produces:
  - `ShiftClass({int? id, required String name, …})`，`copyWith` 保住 `id`，`==`/`hashCode` 含 `id`
  - `ShiftSchedule({…, Map<int, int> dayOverrides = const {}})`
  - `ShiftClass? ShiftSchedule.shiftOn(DateTime date)` —— 现在覆盖感知
  - `ShiftClass? ShiftSchedule.teamShift(int teamIndex, DateTime date)` —— **行为不变**

- [ ] **Step 1: 写失败的领域层测试**

在 `app/test/shift_rotation_test.dart` 的 `main()` 里追加一个 group（文件已有的 import 不变；`defaultSchedule`、`dayNumber` 都已经在这个 import 里）：

```dart
  group('按天改班覆盖', () {
    /// 拿默认「四班两倒」当底，只换 dayOverrides。
    ShiftSchedule withOverrides(Map<int, int> overrides) {
      final base = defaultSchedule();
      return ShiftSchedule(
        name: base.name,
        anchorDate: base.anchorDate,
        classes: base.classes,
        cycle: base.cycle,
        teamCount: base.teamCount,
        teamNames: base.teamNames,
        ourTeamIndex: base.ourTeamIndex,
        teamOffsets: base.teamOffsets,
        dayOverrides: overrides,
      );
    }

    final day = DateTime(2026, 9, 20);

    test('覆盖命中：那天返回覆盖的班次', () {
      final s = withOverrides({dayNumber(day): 3});
      final bare = withOverrides(const {});
      expect(s.shiftOn(day)!.name, isNot(bare.shiftOn(day)!.name),
          reason: '这天应当换成了别的班');
      expect(s.shiftOn(day)!.name, bare.classes[3].name);
    });

    test('没被覆盖的日子仍是轮转结果', () {
      final s = withOverrides({dayNumber(day): 3});
      final bare = withOverrides(const {});
      final next = day.add(const Duration(days: 1));
      expect(s.shiftOn(next)!.name, bare.shiftOn(next)!.name);
    });

    test('下标越界回退到轮转，不抛异常', () {
      final s = withOverrides({dayNumber(day): 99});
      final bare = withOverrides(const {});
      expect(s.shiftOn(day)!.name, bare.shiftOn(day)!.name);
    });

    test('teamShift 不受覆盖影响（其他班组仍是纯轮转）', () {
      final s = withOverrides({dayNumber(day): 3});
      final bare = withOverrides(const {});
      for (var t = 0; t < 4; t++) {
        expect(s.teamShift(t, day)!.name, bare.teamShift(t, day)!.name,
            reason: '第 $t 组不该被「我」的覆盖改掉');
      }
    });

    test('空白表方案忽略覆盖（无周期 → 仍是 null）', () {
      final blank = ShiftSchedule(
        name: '跟随法定节假日',
        anchorDate: DateTime.utc(2025, 1, 6),
        classes: const [],
        cycle: const [],
        dayOverrides: {dayNumber(day): 0},
      );
      expect(blank.shiftOn(day), isNull);
    });

    test('ShiftClass 带 id 时按 id 区分身份', () {
      const a = ShiftClass(id: 1, name: '白班');
      const b = ShiftClass(id: 2, name: '白班');
      const noId = ShiftClass(name: '白班');
      expect(a, isNot(b), reason: '内容相同但 id 不同 = 两个不同实体');
      expect(a, isNot(noId));
      expect(a.copyWith(abbr: '白').id, 1, reason: 'copyWith 必须保住 id');
    });
  });
```

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd app && flutter test test/shift_rotation_test.dart
```

期望：编译失败 —— `No named parameter with the name 'dayOverrides'` / `No named parameter with the name 'id'`。

- [ ] **Step 3: 实现领域层**

`app/lib/domain/shift_rotation.dart`，`ShiftClass` 改造 —— 加字段：

```dart
class ShiftClass {
  const ShiftClass({
    this.id,
    required this.name,
    this.abbr,
    this.startMinute,
    this.endMinute,
    this.isRest = false,
    this.color = 0xFF5B7FFF,
    this.alarmEnabled = false,
    this.alarmMinute,
  });

  /// 库里的行 id；null = 还没落库的新班次。
  ///
  /// **这个字段是「按天改班」能成立的前提**：覆盖表引用的是班次定义，而
  /// `saveSchedule` 从前每次保存都把班次行删光重建、id 全变 —— 有了稳定 id，
  /// 覆盖才指得住（spec §4）。
  final int? id;
```

`copyWith` 加上（放在最前，与构造参数同序）：

```dart
  ShiftClass copyWith({
    int? id,
    String? name,
    String? abbr,
    int? startMinute,
    int? endMinute,
    bool? isRest,
    int? color,
    bool? alarmEnabled,
    int? alarmMinute,
  }) {
    return ShiftClass(
      id: id ?? this.id,
      name: name ?? this.name,
      // …以下原样不变
```

`==` / `hashCode` 加上 `id`：

```dart
  @override
  bool operator ==(Object other) =>
      other is ShiftClass &&
      other.id == id &&
      other.name == name &&
      // …其余条件原样不变

  @override
  int get hashCode => Object.hash(id, name, abbr, startMinute, endMinute,
      isRest, color, alarmEnabled, alarmMinute);
```

`ShiftSchedule` 加字段（构造参数也加 `this.dayOverrides = const {}`）：

```dart
  /// 按天改班覆盖：`dayNumber(日期) → classes 下标`。
  ///
  /// 与其他班次查询**同口径**（存的是下标，不是 classId）—— 库里存 classId，
  /// 由 `ActiveSchedule.toDomain()` 转换过来。
  ///
  /// 只作用于**我们班组**：[teamShift] 不查它。
  final Map<int, int> dayOverrides;
```

`shiftOn` 换成覆盖感知版本（**`teamShift` 一个字都不改**）：

```dart
  /// 我们班组的班次：先查按天覆盖，没有覆盖才按轮转算。
  ///
  /// **覆盖只在 `shiftOn` 这一层生效**，所以四个消费者 —— 日历格子、底栏
  /// 信息卡、闹钟重排（`AlarmService.reschedule`）、闹钟页「未来 30 天」 ——
  /// 全都自动跟着走。而 [teamShift] 不查覆盖，「查看其他班组」看到的仍是纯
  /// 轮转，别人的班不会被我的调整改掉。
  ///
  /// 覆盖下标越界（班次被删、历史脏数据）时**回退到轮转**，不抛异常。
  /// 空白表（无周期）仍返回 null，覆盖不改变这一点。
  ShiftClass? shiftOn(DateTime date) {
    final ov = dayOverrides[dayNumber(date)];
    if (ov != null && ov >= 0 && ov < classes.length) return classes[ov];
    return teamShift(ourTeamIndex, date);
  }
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd app && flutter test test/shift_rotation_test.dart
```

期望：PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/domain/shift_rotation.dart app/test/shift_rotation_test.dart
git commit -m "feat(domain): 班次定义带稳定 id，shiftOn 支持按天覆盖"
```

---

### Task 3: 仓库层 —— 把覆盖装配进领域对象，并让它可响应

**Files:**
- Modify: `app/lib/data/app_repository.dart`
- Create: `app/test/day_override_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `shiftDayOverrides` 表；Task 2 的 `ShiftClass.id` / `ShiftSchedule.dayOverrides`
- Produces:
  - `ActiveSchedule.overrideRows`（`List<ShiftDayOverride>`）
  - `ShiftClassRowX.toDomain()` 返回的 `ShiftClass` **带 `id`**
  - `Stream<ActiveSchedule?> AppDatabase.watchActiveSchedule()` —— 覆盖表变化时重新发值

> ⚠️ **这是本轮最容易静默失败的一环。** `ShiftClassRowX.toDomain()` 若忘了带 `id`，`saveSchedule` 就会永远当成新班次插入，覆盖一保存就指飞 —— 而这一切**不报错**。Step 1 的第二个用例就是钉这条的。

- [ ] **Step 1: 写失败的仓库测试**

创建 `app/test/day_override_repository_test.dart`：

```dart
// app/test/day_override_repository_test.dart
//
// 按天改班的仓库层：装配（存的是 classId，领域层要的是下标）、班次带 id、
// 以及最要命的一条 —— 覆盖表变化时 `watchActiveSchedule()` 必须重新发值。
// 最后这条如果不成立，用户改完覆盖落库成功、日历却纹丝不动，**不报错、
// 只是不动**，从界面上根本看不出原因。
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

void main() {
  late AppDatabase db;
  late AppRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppRepository(db);
  });

  tearDown(() => db.close());

  /// 建一套四班两倒，返回 (scheduleId, 大休那个班次的 id)。
  Future<(int, int)> seed() async {
    final d = defaultSchedule();
    final id = await repo.saveSchedule(
      name: d.name,
      anchorDate: d.anchorDate,
      classes: d.classes,
      cycle: d.cycle,
      makeCurrent: true,
      teamCount: d.teamCount,
      teamNames: d.teamNames,
      ourTeamIndex: d.ourTeamIndex,
      teamOffsets: d.teamOffsets,
    );
    final classes = await (db.select(db.shiftClassRows)
          ..where((t) => t.scheduleId.equals(id))
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    final rest = classes.firstWhere((c) => c.isRest);
    return (id, rest.id);
  }

  test('从库里读出来的班次必须带 id', () async {
    final (_, restId) = await seed();
    final d = (await repo.getActiveSchedule())!;
    expect(d.classes.every((c) => c.id != null), isTrue,
        reason: '不带 id 的话 saveSchedule 会永远当新班次插，覆盖一保存就指飞');
    expect(d.classes.map((c) => c.id), contains(restId));
  });

  test('覆盖装配成 classes 下标，shiftOn 命中', () async {
    final (scheduleId, _) = await seed();
    final day = DateTime(2026, 9, 20);
    final classes = await (db.select(db.shiftClassRows)
          ..where((t) => t.scheduleId.equals(scheduleId))
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    // 目标挑「大休」（最后一个），**不要**用 `firstWhere((c) => c.isRest)`：
    // 后者拿到的是「下夜班」，而 2026-09-20 那天的轮转结果**正好也是下夜班**
    // （anchor 2025-01-06 → 差 622 天，622 mod 4 = 2 → cycle[2] = classes[2]），
    // 两边同名，下面那条 isNot 断言会假失败。
    final target = classes.last;
    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: scheduleId,
            day: dayNumber(day),
            classId: target.id,
          ),
        );

    final d = (await repo.getActiveSchedule())!;
    expect(d.shiftOn(day)!.name, target.name, reason: '覆盖要命中');
    expect(d.shiftOn(day)!.name, isNot(d.teamShift(0, day)!.name),
        reason: '覆盖应当与那天的轮转结果不同（这天才选得有代表性）');
  });

  test('覆盖指向不存在的班次时忽略它，回退到轮转', () async {
    final (scheduleId, _) = await seed();
    final day = DateTime(2026, 9, 20);
    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: scheduleId,
            day: dayNumber(day),
            classId: 99999, // 悬空
          ),
        );

    final d = (await repo.getActiveSchedule())!;
    expect(d.dayOverrides, isEmpty, reason: '查不到的脏数据不该进领域模型');
    expect(d.shiftOn(day)!.name, d.teamShift(0, day)!.name);
  });

  test('覆盖表变化时 watchActiveSchedule 重新发值', () async {
    final (scheduleId, restId) = await seed();
    final day = DateTime(2026, 9, 20);

    final seen = <int>[];
    final sub = db.watchActiveSchedule().listen((s) {
      seen.add(s?.toDomain().dayOverrides.length ?? -1);
    });
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(seen, isNotEmpty, reason: '订阅时应该先发一次');
    expect(seen.last, 0);

    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: scheduleId,
            day: dayNumber(day),
            classId: restId,
          ),
        );
    await pumpEventQueue();

    expect(seen.last, 1,
        reason: '覆盖落库后流必须重发 —— 不重发的话日历纹丝不动，且不报错');
  });
}
```

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd app && flutter test test/day_override_repository_test.dart
```

期望：至少「从库里读出来的班次必须带 id」与「覆盖装配成 classes 下标」失败（`dayOverrides` 永远是空 Map），「覆盖表变化时…重新发值」也会失败（`seen.last` 停在 0）。

- [ ] **Step 3: 实现装配与响应**

`app/lib/data/app_repository.dart`。

**3a. `ActiveSchedule` 加字段：**

```dart
class ActiveSchedule {
  const ActiveSchedule({
    required this.schedule,
    required this.classes,
    required this.cycle,
    this.overrideRows = const [],
  });

  final ShiftScheduleRow schedule;
  final List<ShiftClassRow> classes;
  final List<ShiftCycleRow> cycle;

  /// 本方案的按天改班覆盖行（存的是 classId）。
  final List<ShiftDayOverride> overrideRows;

  ShiftSchedule toDomain() {
    // …现有代码不动，在 domainCycle 之后追加：
    final dayOverrides = <int, int>{};
    for (final r in overrideRows) {
      final idx = indexById[r.classId];
      // 查不到的（班次被删、历史脏数据）直接忽略 —— 那天回退到轮转。
      if (idx != null) dayOverrides[r.day] = idx;
    }
    return ShiftSchedule(
      // …现有参数原样
      dayOverrides: dayOverrides,
    );
  }
}
```

**3b. `ShiftClassRowX.toDomain()` 带上 id** —— 这一行是整条链路的开关：

```dart
extension ShiftClassRowX on ShiftClassRow {
  ShiftClass toDomain() => ShiftClass(
        id: id,
        name: name,
        // …以下原样不变
```

**3c. `watchActiveSchedule()` 改成两张表任一变化都重新装配：**

```dart
  /// 监听当前排班方案及其班次、周期、按天覆盖（响应式）。
  ///
  /// **必须同时监听覆盖表**：只监听方案行的话，用户改完覆盖落库成功，
  /// 这个流不会重发，日历上**纹丝不动** —— 不报错、不崩溃，从界面上看不出
  /// 原因。班次 / 周期是随方案行一起改的（保存方案会 update 那一行），所以
  /// 它们靠方案行的通知就够了；覆盖是独立的行，得单独挂一条。
  Stream<ActiveSchedule?> watchActiveSchedule() {
    final schedQuery = select(shiftScheduleRows)
      ..where((s) => s.isCurrent.equals(true));
    final triggers = <Stream<Object?>>[
      schedQuery.watchSingleOrNull(),
      select(shiftDayOverrides).watch(),
    ];
    // 不用 rxdart（项目没有这个依赖）：手写一个「任一来源发值就置位」的触发流。
    return Stream<Object?>.multi((controller) {
      final subs = [for (final s in triggers) s.listen(controller.add)];
      controller.onCancel = () {
        for (final sub in subs) {
          sub.cancel();
        }
      };
    }).asyncMap((_) async {
      final sched = await schedQuery.getSingleOrNull();
      if (sched == null) return null;
      return _loadChildren(sched);
    });
  }

  Future<ActiveSchedule> _loadChildren(ShiftScheduleRow sched) async {
    // …现有两个查询不动，追加：
    final overrideRows = await (select(shiftDayOverrides)
          ..where((t) => t.scheduleId.equals(sched.id)))
        .get();
    return ActiveSchedule(
      schedule: sched,
      classes: classes,
      cycle: cycle,
      overrideRows: overrideRows,
    );
  }
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd app && flutter test test/day_override_repository_test.dart
```

期望：4 条全 PASS。

- [ ] **Step 5: 跑全量确认没碰坏别的**

```bash
cd app && flutter test && flutter analyze
```

期望：全绿；`analyze` 0 error / 0 warning。

- [ ] **Step 6: 提交**

```bash
git add app/lib/data/app_repository.dart app/test/day_override_repository_test.dart
git commit -m "feat(data): 覆盖装配进领域对象，watchActiveSchedule 响应覆盖表"
```

---

### Task 4: `saveSchedule` 增量保存（班次 id 稳定）+ 连带清理

**Files:**
- Modify: `app/lib/data/app_repository.dart`
- Modify: `app/test/day_override_repository_test.dart`（追加用例）

**Interfaces:**
- Consumes: Task 3 的装配；Task 2 的 `ShiftClass.id`
- Produces: `saveSchedule` 保证「内容没变的班次定义 id 不变」；被删班次的悬空覆盖自动清掉；`deleteSchedule` / `clearAll` 连带删覆盖

- [ ] **Step 1: 写失败的测试**

在 `app/test/day_override_repository_test.dart` 追加：

```dart
  test('改方案名不动班次 id（从前会全变）', () async {
    final (scheduleId, _) = await seed();
    Future<List<int>> ids() async => (await (db.select(db.shiftClassRows)
              ..where((t) => t.scheduleId.equals(scheduleId))
              ..orderBy([(t) => OrderingTerm.asc(t.order)]))
            .get())
        .map((c) => c.id)
        .toList();

    final before = await ids();
    final d = (await repo.getActiveSchedule())!;
    await repo.saveSchedule(
      scheduleId: scheduleId,
      name: '我们组', // 只改名字
      anchorDate: d.anchorDate,
      classes: d.classes,
      cycle: d.cycle,
      teamCount: d.teamCount,
      teamNames: d.teamNames,
      ourTeamIndex: d.ourTeamIndex,
      teamOffsets: d.teamOffsets,
    );
    expect(await ids(), before,
        reason: '只改方案名却换了班次 id 的话，已设置的覆盖会全部指飞');
  });

  test('改班次时间也不动 id', () async {
    final (scheduleId, _) = await seed();
    final d = (await repo.getActiveSchedule())!;
    final edited = [...d.classes];
    edited[0] = edited[0].copyWith(startMinute: 9 * 60);
    await repo.saveSchedule(
      scheduleId: scheduleId,
      name: d.name,
      anchorDate: d.anchorDate,
      classes: edited,
      cycle: d.cycle,
      teamCount: d.teamCount,
      teamNames: d.teamNames,
      ourTeamIndex: d.ourTeamIndex,
      teamOffsets: d.teamOffsets,
    );
    final after = (await repo.getActiveSchedule())!;
    expect(after.classes[0].id, d.classes[0].id);
    expect(after.classes[0].startMinute, 9 * 60, reason: '改动本身要落库');
  });

  test('删掉一个班次时，引用它的覆盖连带被清掉', () async {
    final (scheduleId, restId) = await seed();
    final day = DateTime(2026, 9, 20);
    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: scheduleId,
            day: dayNumber(day),
            classId: restId,
          ),
        );

    final d = (await repo.getActiveSchedule())!;
    final kept = d.classes.where((c) => c.id != restId).toList();
    // 周期里指向被删班次的下标要跟着重映射，否则这次保存本身就坏了
    final keptIndex = {for (var i = 0; i < kept.length; i++) kept[i].id!: i};
    final cycle = d.cycle
        .map((ci) => keptIndex[d.classes[ci].id])
        .whereType<int>()
        .toList();
    await repo.saveSchedule(
      scheduleId: scheduleId,
      name: d.name,
      anchorDate: d.anchorDate,
      classes: kept,
      cycle: cycle,
      teamCount: d.teamCount,
      teamNames: d.teamNames,
      ourTeamIndex: d.ourTeamIndex,
      teamOffsets: d.teamOffsets,
    );

    expect(await db.select(db.shiftDayOverrides).get(), isEmpty,
        reason: '悬空的覆盖行要清掉，否则表里攒一堆指着空气的记录');
  });

  test('删方案 / 清空数据时连带删覆盖', () async {
    final (scheduleId, restId) = await seed();
    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: scheduleId,
            day: dayNumber(DateTime(2026, 9, 20)),
            classId: restId,
          ),
        );
    await repo.deleteSchedule(scheduleId);
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty);

    // clearAll 这条路也走一遍
    await repo.clearAll();
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty);
  });
```

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd app && flutter test test/day_override_repository_test.dart
```

期望：「改方案名不动班次 id」失败（`before` 与 `after` 不同）。

- [ ] **Step 3: 把 `saveSchedule` 的重建改成增量**

`app/lib/data/app_repository.dart`，把 `saveSchedule` 里这一段：

```dart
      // 重建班次定义与周期序列
      await (db.delete(db.shiftCycleRows)
            ..where((t) => t.scheduleId.equals(id)))
          .go();
      await (db.delete(db.shiftClassRows)
            ..where((t) => t.scheduleId.equals(id)))
          .go();

      final classIds = <int>[];
      for (var i = 0; i < classes.length; i++) {
        final c = classes[i];
        classIds.add(await db.into(db.shiftClassRows).insert(
              ShiftClassRowsCompanion.insert(
                scheduleId: id,
                order: i,
                name: c.name,
                abbr: Value(c.abbr),
                startMinute: Value(c.startMinute),
                endMinute: Value(c.endMinute),
                isRest: Value(c.isRest),
                color: Value(c.color),
                alarmEnabled: Value(c.alarmEnabled),
                alarmMinute: Value(c.alarmMinute),
              ),
            ));
      }
```

换成：

```dart
      // 班次定义走**增量更新**，不再「删光重建」。
      //
      // 从前这里是把该方案的班次行全部删掉再逐条 insert，于是每次保存都拿到
      // 全新的自增 id —— 用户哪怕只是把方案名从「四班两倒」改成「我们组」，
      // 所有班次 id 也一起变。而 `shift_day_overrides.classId` 引用正是这个 id，
      // 一保存覆盖就全部指飞。
      //
      // 顺带这一改也贴回了两层模型的本意（`PRODUCT_SPEC.md` §3：「一个班次只
      // 定义一次」）—— 从前的实现每次保存都把班次当新的重新定义一遍。
      final classIds = <int>[];
      for (var i = 0; i < classes.length; i++) {
        final c = classes[i];
        if (c.id != null) {
          await (db.update(db.shiftClassRows)
                ..where((t) => t.id.equals(c.id!)))
              .write(ShiftClassRowsCompanion(
            scheduleId: Value(id),
            order: Value(i),
            name: Value(c.name),
            abbr: Value(c.abbr),
            startMinute: Value(c.startMinute),
            endMinute: Value(c.endMinute),
            isRest: Value(c.isRest),
            color: Value(c.color),
            alarmEnabled: Value(c.alarmEnabled),
            alarmMinute: Value(c.alarmMinute),
          ));
          classIds.add(c.id!);
        } else {
          classIds.add(await db.into(db.shiftClassRows).insert(
                ShiftClassRowsCompanion.insert(
                  scheduleId: id,
                  order: i,
                  name: c.name,
                  abbr: Value(c.abbr),
                  startMinute: Value(c.startMinute),
                  endMinute: Value(c.endMinute),
                  isRest: Value(c.isRest),
                  color: Value(c.color),
                  alarmEnabled: Value(c.alarmEnabled),
                  alarmMinute: Value(c.alarmMinute),
                ),
              ));
        }
      }

      // 库里不在新列表里的班次定义：删掉，并**连带删掉引用它的覆盖行**
      // （悬空引用留着只会在表里攒垃圾，渲染时还得再兜一次底）。
      final keptClassIds = classIds.toSet();
      final staleClasses = await (db.select(db.shiftClassRows)
            ..where((t) => t.scheduleId.equals(id)))
          .get();
      for (final row in staleClasses) {
        if (keptClassIds.contains(row.id)) continue;
        await (db.delete(db.shiftDayOverrides)
              ..where((t) => t.classId.equals(row.id)))
            .go();
        await (db.delete(db.shiftClassRows)..where((t) => t.id.equals(row.id)))
            .go();
      }
```

**周期序列那段保持不变**（它本来就是删了重建，且 `classIds[ci]` 现在拿的是复用后的 id，语义正确）。

然后在 `deleteSchedule` 里加一句（放在删 `shiftClassRows` 之前）：

```dart
      await (db.delete(db.shiftDayOverrides)
            ..where((t) => t.scheduleId.equals(id)))
          .go();
```

在 `clearAll` 里加一句（与 `shiftAlarmOverrides` 并列）：

```dart
      await db.delete(db.shiftDayOverrides).go();
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd app && flutter test test/day_override_repository_test.dart
```

期望：8 条全 PASS。

- [ ] **Step 5: 跑全量**

```bash
cd app && flutter test && flutter analyze
```

期望：全绿。**这一步特别重要** —— `saveSchedule` 是所有排班写入的必经之路，`save_schedule_current_test.dart` / `schedule_editor_test.dart` / `calendar_screen_test.dart` 都会跑到它。

- [ ] **Step 6: 提交**

```bash
git add app/lib/data/app_repository.dart app/test/day_override_repository_test.dart
git commit -m "fix(data): saveSchedule 改增量保存，班次 id 不再每次重建"
```

---

### Task 5: 覆盖的写入口

**Files:**
- Modify: `app/lib/data/app_repository.dart`
- Modify: `app/test/day_override_repository_test.dart`（追加用例）

**Interfaces:**
- Consumes: Task 1 的表、Task 3 的装配
- Produces（Task 7/8/9 会调）：
  - `Future<void> AppRepository.setDayOverrides(List<DateTime> dates, {required int classId})`
  - `Future<void> AppRepository.clearDayOverrides(List<DateTime> dates)`
  - `Future<int> AppRepository.dayOverrideCount()`
  - `Future<int?> AppRepository.currentScheduleId()`

- [ ] **Step 1: 写失败的测试**

在 `app/test/day_override_repository_test.dart` 追加：

```dart
  test('setDayOverrides 一次写多天，clearDayOverrides 只清给定那几天', () async {
    final (_, restId) = await seed();
    final days = [
      DateTime(2026, 9, 18),
      DateTime(2026, 9, 19),
      DateTime(2026, 9, 20),
    ];
    await repo.setDayOverrides(days, classId: restId);

    final d = (await repo.getActiveSchedule())!;
    for (final day in days) {
      expect(d.dayOverrides.containsKey(dayNumber(day)), isTrue,
          reason: '${day.day} 号应当被覆盖');
    }
    expect(await repo.dayOverrideCount(), 3);

    await repo.clearDayOverrides([days.first]);
    expect(await repo.dayOverrideCount(), 2);
    final d2 = (await repo.getActiveSchedule())!;
    expect(d2.dayOverrides.containsKey(dayNumber(days.first)), isFalse);
    expect(d2.dayOverrides.containsKey(dayNumber(days[1])), isTrue,
        reason: '不在清理列表里的那天要保持原样');
  });

  test('setDayOverrides 覆盖已有的同一天（幂等更新，不报主键冲突）', () async {
    final (_, restId) = await seed();
    final day = DateTime(2026, 9, 18);
    await repo.setDayOverrides([day], classId: restId);
    await repo.setDayOverrides([day], classId: restId);
    expect(await repo.dayOverrideCount(), 1);
  });

  test('没有当前方案时 setDayOverrides 静默返回，不抛异常', () async {
    // 不 seed，库里空空如也
    await repo.setDayOverrides([DateTime(2026, 9, 18)], classId: 1);
    expect(await repo.dayOverrideCount(), 0);
  });
```

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd app && flutter test test/day_override_repository_test.dart
```

期望：编译失败 —— `The method 'setDayOverrides' isn't defined`。

- [ ] **Step 3: 实现写入口**

在 `AppRepository` 里、`setShiftAlarmOverride` 那段附近加：

```dart
  /// 当前方案的行 id；没有当前方案时返回 null。
  Future<int?> currentScheduleId() async {
    final row = await (db.select(db.shiftScheduleRows)
          ..where((s) => s.isCurrent.equals(true)))
        .getSingleOrNull();
    return row?.id;
  }

  /// 把 [dates] 这些天改成 [classId] 指定的班次（当前方案）。
  ///
  /// 一次写多天为什么不做成范围：底层就是一天一行（复合主键 `{scheduleId, day}`），
  /// 存范围反而要在读写两头各拆一次。连休三天就是三行，天然支持。
  ///
  /// 重复设置同一天走 `insertOnConflictUpdate`，是更新不是报错。
  Future<void> setDayOverrides(List<DateTime> dates,
      {required int classId}) async {
    final scheduleId = await currentScheduleId();
    if (scheduleId == null) return;
    await db.transaction(() async {
      for (final date in dates) {
        await db.into(db.shiftDayOverrides).insertOnConflictUpdate(
              ShiftDayOverridesCompanion.insert(
                scheduleId: scheduleId,
                day: dayNumber(date),
                classId: classId,
              ),
            );
      }
    });
  }

  /// 清掉 [dates] 这些天的覆盖，让它们回到按轮转算（当前方案）。
  Future<void> clearDayOverrides(List<DateTime> dates) async {
    final scheduleId = await currentScheduleId();
    if (scheduleId == null) return;
    await db.transaction(() async {
      for (final date in dates) {
        await (db.delete(db.shiftDayOverrides)
              ..where((t) =>
                  t.scheduleId.equals(scheduleId) &
                  t.day.equals(dayNumber(date))))
            .go();
      }
    });
  }

  /// 当前方案已设置的覆盖天数（编辑器顶部提示用）。
  Future<int> dayOverrideCount() async {
    final scheduleId = await currentScheduleId();
    if (scheduleId == null) return 0;
    final rows = await (db.select(db.shiftDayOverrides)
          ..where((t) => t.scheduleId.equals(scheduleId)))
        .get();
    return rows.length;
  }
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd app && flutter test test/day_override_repository_test.dart && flutter analyze
```

期望：11 条全 PASS，analyze 干净。

- [ ] **Step 5: 提交**

```bash
git add app/lib/data/app_repository.dart app/test/day_override_repository_test.dart
git commit -m "feat(data): 按天覆盖的写入口（设置 / 清除 / 计数）"
```

---

### Task 6: l10n 文案

**Files:**
- Modify: `app/lib/core/l10n.dart`

**Interfaces:**
- Consumes: 无
- Produces（Task 7/8/9 会调）：
  - `L10n.adjustShift` / `L10n.adjusted` / `L10n.restoreRotation`
  - `L10n.adjustedDays(int n, String shift)` / `L10n.restoredRotation(int n)`
  - `L10n.overrideRangeTitle(String fromLabel, String toLabel, int days)`
  - `L10n.previewHasOverrides(int n)`

> **注意**：`l10n.dart` 只依赖 `intl`（纯 Dart），**不能** import `domain/shift_rotation.dart`（那边反过来 import 了本文件，会成环）。所以日期区间标题的「N 天」由调用方算好传进来，本文件不去调 `daysBetween`。

- [ ] **Step 1: 加文案**

在 `app/lib/core/l10n.dart` 的「我的」页分区那一片附近，新增一节：

```dart
  // 按天改班（换班 / 请假覆盖）
  static String get adjustShift => t('调整班次', 'Adjust shift');
  static String get adjusted => t('已调整', 'Adjusted');
  static String get restoreRotation => t('恢复轮转', 'Restore rotation');

  /// 应用后的提示：「已把 3 天改为大休」。
  static String adjustedDays(int n, String shift) =>
      t('已把 $n 天改为$shift', 'Changed $n day(s) to $shift');

  /// 清除覆盖后的提示。
  static String restoredRotation(int n) =>
      t('已把 $n 天恢复为轮转', 'Restored $n day(s) to rotation');

  /// 选择层标题：单日只写日期，多日写「起 – 止 · N 天」。
  ///
  /// 「N 天」由调用方算（本文件不能依赖 `domain/shift_rotation.dart` 的
  /// `daysBetween` —— 那边 import 了本文件，会成环）。
  static String overrideRangeTitle(String fromLabel, String toLabel, int days) =>
      days <= 1
          ? fromLabel
          : t('$fromLabel – $toLabel · $days 天',
              '$fromLabel – $toLabel · $days days');

  /// 编辑器顶部提示：预览不叠覆盖。
  static String previewHasOverrides(int n) => t(
      '本方案有 $n 天单独调整，预览只显示轮转规则',
      'This schedule has $n adjusted day(s); the preview shows rotation only');
```

- [ ] **Step 2: 跑测试与静态检查**

```bash
cd app && flutter test && flutter analyze
```

期望：全绿（这一步没有新用例，只是确认文案没写坏语法、没碰坏 `seed_locale_test`）。

- [ ] **Step 3: 提交**

```bash
git add app/lib/core/l10n.dart
git commit -m "feat(l10n): 按天改班的文案"
```

---

### Task 7: 选择层 `showShiftOverridePicker`

**Files:**
- Create: `app/lib/features/calendar/shift_override_picker.dart`
- Create: `app/test/shift_override_picker_test.dart`

**Interfaces:**
- Consumes: `L10n`（Task 6）；`ShiftSchedule` / `ShiftClass`（Task 2）；`AppTokens`、`GlassPanel`、`GlassPressable`
- Produces（Task 8/9 会调）：

```dart
/// 选择层的结果：改成某个班次，或恢复轮转。
class ShiftOverrideChoice {
  const ShiftOverrideChoice.change(ShiftClass this.shift) : restore = false;
  const ShiftOverrideChoice.restore() : shift = null, restore = true;

  final ShiftClass? shift;
  final bool restore;
}

/// 弹出「调整班次」底部选择层；用户取消返回 null。
Future<ShiftOverrideChoice?> showShiftOverridePicker(
  BuildContext context, {
  required ShiftSchedule schedule,
  required DateTime from,
  required DateTime to,
  bool canRestore = false,
  String Function(ShiftClass) timeRangeOf = _defaultTimeRange,
});
```

- [ ] **Step 1: 写失败的选择层测试**

创建 `app/test/shift_override_picker_test.dart`：

```dart
// app/test/shift_override_picker_test.dart
//
// 「调整班次」选择层：列全本方案的班次定义、当前值打勾、可选「恢复轮转」。
// 本机没有可运行目标，界面行为全靠 widget 测试覆盖。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/calendar/shift_override_picker.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
  });

  Future<ShiftOverrideChoice?> pumpPicker(
    WidgetTester tester, {
    ShiftClass? current,
    bool canRestore = false,
  }) async {
    ShiftOverrideChoice? result;
    final schedule = defaultSchedule();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showShiftOverridePicker(
                  context,
                  schedule: schedule,
                  from: DateTime(2026, 9, 18),
                  to: DateTime(2026, 9, 20),
                  canRestore: canRestore,
                  currentClass: current,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('列出本方案全部班次定义', (tester) async {
    await pumpPicker(tester);
    for (final c in defaultSchedule().classes) {
      expect(find.text(c.name), findsOneWidget, reason: '${c.name} 应当可选');
    }
  });

  testWidgets('多日时标题写「起 – 止 · N 天」', (tester) async {
    await pumpPicker(tester);
    expect(find.textContaining('3 天'), findsOneWidget);
  });

  testWidgets('选中一项后返回「改成这个班次」', (tester) async {
    final schedule = defaultSchedule();
    ShiftOverrideChoice? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showShiftOverridePicker(
                  context,
                  schedule: schedule,
                  from: DateTime(2026, 9, 18),
                  to: DateTime(2026, 9, 18),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(schedule.classes[3].name));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.restore, isFalse);
    expect(result!.shift!.name, schedule.classes[3].name);
  });

  testWidgets('canRestore 为假时不出现「恢复轮转」', (tester) async {
    await pumpPicker(tester);
    expect(find.text(L10n.restoreRotation), findsNothing);
  });

  testWidgets('canRestore 为真时出现且返回「恢复轮转」', (tester) async {
    final schedule = defaultSchedule();
    ShiftOverrideChoice? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showShiftOverridePicker(
                  context,
                  schedule: schedule,
                  from: DateTime(2026, 9, 18),
                  to: DateTime(2026, 9, 18),
                  canRestore: true,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(L10n.restoreRotation), findsOneWidget);

    await tester.tap(find.text(L10n.restoreRotation));
    await tester.pumpAndSettle();
    expect(result!.restore, isTrue);
  });
}
```

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd app && flutter test test/shift_override_picker_test.dart
```

期望：文件不存在，编译失败。

- [ ] **Step 3: 实现选择层**

创建 `app/lib/features/calendar/shift_override_picker.dart`：

```dart
// 「调整班次」底部选择层：给一天或一段日子单独指定班次（或恢复轮转）。
//
// 配方照抄现有的底部弹层（`glass_pickers.dart` 的 `showGlassOptionPicker`）：
// 透明遮罩 + `GlassPanel(solid: true)` + `GlassPressable` 包 `ListTile`。
// 没直接复用它，是因为它只认一个 `labelOf` 字符串 —— 这里每行还要画一个班次色
// 圆点和一行时间，另外底部要挂一条「恢复轮转」。
import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/glass/glass.dart';
import '../../domain/shift_rotation.dart';

/// 选择层的结果：改成某个班次，或恢复轮转。
class ShiftOverrideChoice {
  const ShiftOverrideChoice.change(ShiftClass this.shift) : restore = false;
  const ShiftOverrideChoice.restore() : shift = null, restore = true;

  final ShiftClass? shift;
  final bool restore;
}

/// 班次的时间区间文本。
///
/// **不能直接调 `L10n.timeRange`**：它的签名是
/// `timeRange(String start, String end, bool crossesMidnight)` —— 收的是两个
/// 钟面字符串加一个跨午夜标志，不是分钟整数。所以这里自己把分钟换算成钟面，
/// 换算规则与 `calendar_screen.dart` 里那个同名私有函数 `_timeRange(ShiftClass)`
/// 一致（`endMinute > 1440` 时减 1440；`nextDay = e > 1440 || e < s`）。
/// 那边收的也是 `ShiftClass`，但它是日历页的私有函数、且那边不归本轮改，
/// 所以这里是第二份 —— 两份的输入类型本就不同，不值得为去重把它们耦合起来。
String _defaultTimeRange(ShiftClass c) {
  final s = c.startMinute, e = c.endMinute;
  if (s == null || e == null) return '';
  var end = e;
  final nextDay = end > 1440 || end < s;
  if (end > 1440) end -= 1440;
  return L10n.timeRange(formatClock(s), formatClock(end), nextDay);
}

/// 弹出「调整班次」选择层；用户取消返回 null。
///
/// [from] / [to] 是本次要改的日期区间（闭区间，单日时传同一天）。
/// [canRestore] 为真时底部出现「恢复轮转」—— 由调用方判断，只有当区间内至少
/// 有一天已经被覆盖过才有意义。
/// [currentClass] 是当前值，命中的那一项打勾；传 null 则都不打勾。
Future<ShiftOverrideChoice?> showShiftOverridePicker(
  BuildContext context, {
  required ShiftSchedule schedule,
  required DateTime from,
  required DateTime to,
  ShiftClass? currentClass,
  bool canRestore = false,
  String Function(ShiftClass) timeRangeOf = _defaultTimeRange,
}) {
  final days = daysBetween(from, to) + 1;
  final title = L10n.overrideRangeTitle(
      L10n.monthDay(from), L10n.monthDay(to), days);

  return showModalBottomSheet<ShiftOverrideChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black26,
    builder: (sheetContext) => GlassPanel(
      solid: true,
      margin: const EdgeInsets.all(12),
      borderRadius: const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceLg, AppTokens.spaceLg, AppTokens.spaceLg, 8),
              child: Text(title, style: AppTokens.titleStrong),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in schedule.classes)
                    GlassPressable(
                      child: ListTile(
                        leading: _ClassDot(color: Color(c.color)),
                        title: Text(c.name),
                        subtitle: timeRangeOf(c).isEmpty
                            ? null
                            : Text(timeRangeOf(c),
                                style: AppTokens.labelSecondary),
                        trailing: identical(c, currentClass)
                            ? AppIcon(Icons.check,
                                size: AppTokens.iconMd,
                                color: Theme.of(sheetContext)
                                    .colorScheme
                                    .primary)
                            : null,
                        onTap: () => Navigator.pop(
                            sheetContext, ShiftOverrideChoice.change(c)),
                      ),
                    ),
                ],
              ),
            ),
            if (canRestore)
              GlassPressable(
                child: ListTile(
                  leading: AppIcon(Icons.restart_alt,
                      size: AppTokens.iconMd,
                      color: AppTokens.inkMuted(sheetContext)),
                  title: Text(L10n.restoreRotation),
                  onTap: () => Navigator.pop(
                      sheetContext, const ShiftOverrideChoice.restore()),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// 班次色的圆点，落在 `ListTile.leading` 位。
///
/// 尺寸取 `iconMd`：弹层里这一档是 leading 图标的位置，跟同层其他弹层的
/// leading 图标同一档才对（**不是**信息卡上那个 12dp 的小色点，两者尺寸不同是
/// 有意的）。
class _ClassDot extends StatelessWidget {
  const _ClassDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: AppTokens.iconMd,
        height: AppTokens.iconMd,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
```

> **实施时可能要微调的一处**：`AppIcon` 的 import 路径（在 `core/widgets/app_icon.dart`，签名是 `AppIcon(IconData, {size, color})`，`calendar_screen.dart` 里就有现成用法可抄）。`L10n.timeRange` 的签名已核实为 `timeRange(String start, String end, bool crossesMidnight)`，上面的 `_defaultTimeRange` 就是按它写的。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd app && flutter test test/shift_override_picker_test.dart
```

期望：5 条全 PASS。

- [ ] **Step 5: 跑设计令牌守门与全量**

```bash
cd app && flutter test test/design_tokens_test.dart && flutter test && flutter analyze
```

期望：全绿。若 `design_tokens_test` 报字面量，按规则加 `// design-tokens-ignore: <理由>` 具名豁免，**不要**把令牌值改成字面量。

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/calendar/shift_override_picker.dart app/test/shift_override_picker_test.dart
git commit -m "feat(calendar): 调整班次的选择层"
```

---

### Task 8: 信息卡入口 —— 那行班次可点 + 「已调整」标记

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Modify: `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: Task 5 的 `setDayOverrides` / `clearDayOverrides`；Task 6 的文案；Task 7 的 `showShiftOverridePicker` / `ShiftOverrideChoice`
- Produces: `_CalendarScreenState.adjustDays(DateTime from, DateTime to)` —— Task 9 复用

- [ ] **Step 1: 写失败的信息卡用例**

在 `app/test/calendar_screen_test.dart` 追加（复用文件里已有的 `_pumpCalendar` 夹具与 `_shiftLine` 取值器）：

```dart
  testWidgets('信息卡那行班次可点，弹层选中后日历跟着变', (tester) async {
    final db = await _pumpCalendar(tester, 'four_crew_two_shift');
    final today = dateOnly(DateTime.now());

    // 点开入口
    await tester.tap(find.byKey(const Key('info-card-shift-line')));
    await tester.pumpAndSettle();
    expect(find.text(L10n.adjustShift), findsNothing,
        reason: '标题是日期区间，不是「调整班次」四个字');

    // 挑一个与当前不同的班次
    final before = _shiftLine(tester);
    final classes = await db.select(db.shiftClassRows).get();
    final target = classes.firstWhere((c) => !before.contains(c.name));

    await tester.tap(find.text(target.name).last);
    await tester.pumpAndSettle();

    // 落库了
    final rows = await db.select(db.shiftDayOverrides).get();
    expect(rows, hasLength(1));
    expect(rows.single.day, dayNumber(today));
    expect(rows.single.classId, target.id);

    // 界面上那天换了班
    expect(_shiftLine(tester), contains(target.name));
    // 并且带上「已调整」标记
    expect(find.text(L10n.adjusted), findsWidgets);

    await _disposeCalendar(tester);
  });
```

> 实施前先确认模板 id：`_pumpCalendar(tester, '<id>')` 里的 id 必须是 `shift_templates.dart` 里真实存在的（`four_crew_two_shift` 是默认四班两倒，若名字不同就换成实际 id）。跑一次 `grep -n "id:" app/lib/domain/shift_templates.dart | head` 核对。

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd app && flutter test test/calendar_screen_test.dart
```

期望：新用例失败（点那行没反应，找不到弹层）。

- [ ] **Step 3: 实现**

**3a.** 文件顶部补 import（**只需要这一条** —— `app_repository.dart` / `alarm_service.dart` / `glass_pressable.dart` / `glass_snackbar.dart` / `app_icon.dart` 这个文件**已经都 import 了**，别重复添加）：

```dart
import 'shift_override_picker.dart';
```

**3b.** 在 `_CalendarScreenState` 里加一个共用方法（Task 9 也用）：

```dart
  /// 弹「调整班次」选择层，把 [from]..[to] 这段日子改掉（或恢复轮转）。
  ///
  /// 改完必须重排闹钟：这天可能从工作班变成休班（不该响），或从休班变成夜班
  /// （要响）—— 不重排的话闹钟跟日历就对不上了。
  Future<void> adjustDays(DateTime from, DateTime to) async {
    final schedule = ref.read(activeScheduleProvider).valueOrNull?.toDomain();
    if (schedule == null || schedule.isBlank || schedule.classes.isEmpty) {
      // 空白表（跟随法定节假日）没有班次定义可挑，入口本来就不该出现；
      // 这里再兜一次，免得别处误调。
      return;
    }
    final days = <DateTime>[];
    final span = daysBetween(from, to);
    for (var i = 0; i <= span; i++) {
      days.add(dateOnly(DateTime(from.year, from.month, from.day + i)));
    }

    final hasOverride =
        days.any((d) => schedule.dayOverrides.containsKey(dayNumber(d)));
    final current =
        days.length == 1 ? schedule.shiftOn(days.single) : null;

    final choice = await showShiftOverridePicker(
      context,
      schedule: schedule,
      from: from,
      to: to,
      currentClass: hasOverride ? current : null,
      canRestore: hasOverride,
    );
    if (choice == null || !mounted) return;

    final repo = ref.read(appRepositoryProvider);
    if (choice.restore) {
      await repo.clearDayOverrides(days);
    } else {
      await repo.setDayOverrides(days, classId: choice.shift!.id!);
    }
    await AlarmService.rescheduleAll(repo);
    if (!mounted) return;
    showGlassSnack(
      context,
      choice.restore
          ? L10n.restoredRotation(days.length)
          : L10n.adjustedDays(days.length, choice.shift!.name),
    );
  }
```

**3c.** 把信息卡里那行班次（`Key('info-card-shift-line')` 所在的 `Row`，约在 1250–1288 行）外面套一层可点手势，并在有覆盖时追一个「已调整」标记。把那一段：

```dart
        if (shift != null)
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: Color(shift.color), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  key: const Key('info-card-shift-line'),
                  // …原样
                ),
              ),
            ],
          )
```

改成：

```dart
        if (shift != null)
          // `GlassPressable` **没有 `onTap`** —— 它只是个按压缩放的视觉包装
          // （`Listener` + `QScale`），点击一律由子 widget 承载。所以这里套
          // `InkWell`（`GlassPressable` 内部已经给了 `Material`，水波纹拿得到），
          // 与 `glass_pickers.dart` 里 `GlassPressable(child: ListTile(onTap: …))`
          // 是同一套做法。
          //
          // 空白表方案没有班次定义可挑，入口不给（spec §7.3）—— 传 null 禁用它。
          // 已知小瑕疵：`GlassPressable` 的按压缩放挡不住，空白表下按这行仍会
          // 缩一下。不值得为它再加一层条件包装。
          GlassPressable(
            key: const Key('info-card-shift-entry'),
            child: InkWell(
              onTap: schedule.classes.isEmpty
                  ? null
                  : () => adjustDays(_selected, _selected),
              child: Row(
                children: [
                  Container(
                    // 保持原来的 12 不动 —— 这个色点的尺寸不是本任务要改的东西，
                    // 换成 `AppTokens.iconSm`（16）会白白把点撑大一圈。
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: Color(shift.color), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      key: const Key('info-card-shift-line'),
                      // …原样
                    ),
                  ),
                  // 这天被单独调整过（spec §7.4）：给一句文字说明，让用户第一眼
                  // 看见日历上那个小圆点时能对上号。
                  if (schedule.dayOverrides.containsKey(dayNumber(_selected)))
                    Padding(
                      padding: const EdgeInsets.only(left: AppTokens.spaceSm),
                      child: Text(
                        L10n.adjusted,
                        key: const Key('info-card-adjusted'),
                        style: AppTokens.microStrong.copyWith(
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                ],
              ),
            ),
          )
```

`primary` 若此作用域没有现成变量，就用上面写的 `Theme.of(context).colorScheme.primary`。

**3d.** 紧凑版信息卡（`compact` 分支，约 1116–1158 行）那张 `GlassTile` 同样包一层 `GlassPressable`，`onTap` 同理调 `adjustDays(_selected, _selected)`。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd app && flutter test test/calendar_screen_test.dart && flutter analyze
```

期望：新用例 PASS，既有用例不回归。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_screen_test.dart
git commit -m "feat(calendar): 信息卡那行班次可点改班，并显示「已调整」"
```

---

### Task 9: 日历格子小圆点 + 长按拖选一段日子

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Modify: `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: Task 8 的 `adjustDays(DateTime, DateTime)`
- Produces: 无（本任务是交互链路的终点）

- [ ] **Step 1: 写失败的用例**

在 `app/test/calendar_screen_test.dart` 追加：

```dart
  testWidgets('被覆盖的那天在格子上有小圆点标记', (tester) async {
    final db = await _pumpCalendar(tester, 'four_crew_two_shift');
    final today = dateOnly(DateTime.now());

    expect(find.byKey(ValueKey('day-adjusted-${today.day}')), findsNothing);

    final classes = await db.select(db.shiftClassRows).get();
    final repo = AppRepository(db);
    await repo.setDayOverrides([today], classId: classes.first.id);
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('day-adjusted-${today.day}')), findsOneWidget,
        reason: '被调整过的那天要有可辨认的标记');

    await _disposeCalendar(tester);
  });

  testWidgets('长按拖选一段日子后弹层改多天', (tester) async {
    final db = await _pumpCalendar(tester, 'four_crew_two_shift');
    final today = dateOnly(DateTime.now());

    // 长按「今天」那格，往下拖一格 → 圈住 2 天
    final start = tester.getCenter(find.byKey(ValueKey('day-card-${today.day}')));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600)); // 过长按判定
    await gesture.moveBy(const Offset(0, 60));            // 往下拖一格
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 弹层出来了，标题是「起点 – 终点 · 2 天」
    expect(find.textContaining('2 天'), findsOneWidget);

    final classes = await db.select(db.shiftClassRows).get();
    await tester.tap(find.text(classes.first.name).last);
    await tester.pumpAndSettle();

    final rows = await db.select(db.shiftDayOverrides).get();
    expect(rows, hasLength(2), reason: '圈住的两天都要落库');

    await _disposeCalendar(tester);
  });
```

> 拖动距离 `Offset(0, 60)` 依赖格子高度。若测试里格子高度不是 60，改成从 `tester.getSize(find.byKey(ValueKey('day-card-…')))` 取实际高度再拖。**先看清楚再写死。**

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd app && flutter test test/calendar_screen_test.dart
```

期望：两条新用例都失败。

- [ ] **Step 3: 实现**

**3a.** `_CalendarScreenState` 加范围态字段：

```dart
  /// 长按拖选：起点与当前终点（null = 不在范围选择态）。
  DateTime? _rangeAnchor;
  DateTime? _rangeFocus;
```

**3b.** 加一个与 `_selectFromPosition` 同源的取日期函数，并让 `_selectFromPosition` 复用它（消掉重复）：

```dart
  /// 手指位置 → 那一格的日期（越界 / 空格 / 不是本月都返回 null）。
  DateTime? _dateFromPosition(Offset pos, double cellW, double cellH) {
    final col = ((pos.dx - _hPad) / cellW).floor();
    final row = ((pos.dy - _weekdayH) / cellH).floor();
    if (col < 0 || col > 6 || row < 0) return null;
    final index = row * 7 + col;
    if (index < _leading) return null;
    final day = index - _leading + 1;
    if (day < 1 || day > _daysInMonth) return null;
    return DateTime(_month.year, _month.month, day);
  }

  void _selectFromPosition(Offset pos, double cellW, double cellH) {
    final date = _dateFromPosition(pos, cellW, cellH);
    if (date != null && date != _selected) setState(() => _selected = date);
  }
```

**3c.** 在 `_buildGrid` 那个 `GestureDetector` 上加长按三件套（**加在现有 `onPanEnd` 之后即可**，两套手势在竞技场里天然分流：按住不动约 500ms 长按赢，立刻滑动还是原来的 Pan 赢）：

```dart
          onLongPressStart: (d) {
            final date = _dateFromPosition(d.localPosition, cellW, cellH);
            if (date == null) return;
            setState(() {
              _pressed = false;
              _dragActive = false;
              _rangeAnchor = date;
              _rangeFocus = date;
            });
          },
          onLongPressMoveUpdate: (d) {
            if (_rangeAnchor == null) return;
            final date = _dateFromPosition(d.localPosition, cellW, cellH);
            if (date == null || date == _rangeFocus) return;
            setState(() => _rangeFocus = date);
          },
          onLongPressEnd: (_) {
            final from = _rangeAnchor;
            final to = _rangeFocus;
            setState(() {
              _rangeAnchor = null;
              _rangeFocus = null;
            });
            if (from == null || to == null) return;
            // 起点终点谁在前都行，调换成正序
            final a = daysBetween(from, to) >= 0 ? from : to;
            final b = daysBetween(from, to) >= 0 ? to : from;
            adjustDays(a, b);
          },
```

**3d.** 范围高亮：在 `_dayCell` 里加一个 `inRange` 参数，在 `Stack` 的**最底层**铺一层主色淡染。`_dayCell` 的签名末尾加 `bool inRange`（它是纯位置参数的一串，保持同风格）：

```dart
  Widget _dayCell(BuildContext context, DateTime date, ShiftClass? shift,
      LunarInfo lunar, double cellW, double cellH, bool isToday, bool solid,
      bool inRange) {
```

`Stack` 里那层：

```dart
        child: Stack(
          children: [
            // 长按拖选时，圈住的日子铺一层主色淡染（画在内容下面，不挡字）。
            // 逐格画而不是画一个外接矩形：日期区间在月历里是折行的（周五到
            // 下周二），外接矩形会把区间之外整整一行都染上。
            if (inRange)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.18),
                    borderRadius: _cellRadius,
                  ),
                ),
              ),
            Positioned.fill(
              // …原有的 FittedBox 内容，原样
```

**3e.** 小圆点：在 `_dayCell` 的班次胶囊那一行外面套一个 `Stack`，右上角放点。最省的位置是在 `children.add(chip ? … )` 那里，把 `_shiftChip` 包一层：

```dart
      children.add(chip
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: _chipSideGap),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _shiftChip(context, shift, s, solid,
                      ValueKey('day-chip-${date.day}')),
                  if (adjusted)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        key: ValueKey('day-adjusted-${date.day}'),
                        // 尺寸用光学微距令牌而不是跟着 `s` 缩放：小窗里
                        // 1–2px 的点等于没有（spec §7.4）。
                        width: AppTokens.gapHair,
                        height: AppTokens.gapHair,
                        decoration: BoxDecoration(
                          color: Color(shift.color),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            )
          : const SizedBox.shrink())
```

其中 `adjusted` 由 `_dayCell` 的调用方 `_dayRows` 传入（新增一个位置参数，与 `solid` 并列）：

```dart
          blockDate != null && isSameDay(date, blockDate),
          schedule?.dayOverrides.containsKey(dayNumber(date)) ?? false,
          _rangeAnchor != null &&
              _rangeFocus != null &&
              _inSelectedRange(date));
```

并加一个辅助：

```dart
  /// [date] 是否落在长按拖选的范围里（闭区间，两端谁前谁后都算）。
  bool _inSelectedRange(DateTime date) {
    final a = _rangeAnchor, b = _rangeFocus;
    if (a == null || b == null) return false;
    final lo = daysBetween(a, b) >= 0 ? a : b;
    final hi = daysBetween(a, b) >= 0 ? b : a;
    return daysBetween(lo, date) >= 0 && daysBetween(date, hi) >= 0;
  }
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd app && flutter test test/calendar_screen_test.dart
```

期望：两条新用例 PASS，既有用例不回归（尤其「单格滑块拖动」那几条 —— 长按手势不能把它们顶掉）。

- [ ] **Step 5: 跑全量与静态检查**

```bash
cd app && flutter test && flutter analyze
```

期望：全绿，0 error / 0 warning。

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_screen_test.dart
git commit -m "feat(calendar): 长按拖选一段日子批量改班，格子上标记已调整"
```

---

### Task 10: 编辑器 —— 班次带 id 走 + 预览提示

**Files:**
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`
- Modify: `app/test/schedule_editor_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `ShiftClass.id`；Task 5 的 `dayOverrideCount()`
- Produces: 无

> ⚠️ `_editClass` 现在是**逐字段手工构造** `ShiftClass(...)`，没有把 `id` 传下去 —— 只要用户改任何一个字段（哪怕只是改个简称），这个班次的 id 就丢了，保存时会当成新班次插入，**引用它的覆盖全部指飞**。这是本轮最隐蔽的一处。

- [ ] **Step 1: 写失败的用例**

在 `app/test/schedule_editor_test.dart` 追加：

```dart
  testWidgets('改班次简称不会丢掉它的 id（丢了的话覆盖会指飞）', (tester) async {
    final db = await _pumpEditor(tester); // 复用本文件已有的夹具
    final before = await db.select(db.shiftClassRows).get();
    final target = before.first;

    // 把第一个班次的简称改一下并保存
    await tester.enterText(
        find.byKey(ValueKey('class-abbr-0')), 'X');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor-save')));
    await tester.pumpAndSettle();

    final after = await db.select(db.shiftClassRows).get();
    final same = after.where((c) => c.abbr == 'X');
    expect(same, hasLength(1));
    expect(same.single.id, target.id, reason: 'id 必须保住');
    expect(after.map((c) => c.id).toSet(), before.map((c) => c.id).toSet(),
        reason: '整组 id 都不该变');
  });
```

> **实施提示**：夹具名 `_pumpEditor`、输入框 key `class-abbr-0`、保存按钮 key `editor-save` 都是**待核实**的 —— 先读一遍 `schedule_editor_test.dart` 里现有的用例，用它的夹具和它实际用的 finder，别照抄上面的名字。这条用例的价值在于断言 `id` 集合前后相同，finder 用现成的即可，不要为了写这条测试去新加 key（除非确实没有可用的入口，那时才给输入框/保存按钮补 key，且要一并更新既有用例）。

- [ ] **Step 2: 跑测试确认它失败**

```bash
cd app && flutter test test/schedule_editor_test.dart
```

期望：新用例失败（id 集合变了）。

- [ ] **Step 3: 实现**

**3a.** `_editClass` 把 id 传下去：

```dart
  return ShiftClass(
    id: c.id, // 必须带下去：丢了 id 就等于把这个班次变成「新班次」，
              // 保存时插一条新行，引用它的按天覆盖全部指飞。
    name: name ?? c.name,
    // …以下原样
  );
```

**3b.** 预览**不带覆盖** —— `_previewStrip` 里 `ShiftSchedule(...)` **不加** `dayOverrides` 参数即可（默认就是 `const {}`）。在这一行上方补注释说明这是有意的：

```dart
    // **有意不传 dayOverrides**：预览要回答的是「按这套规则未来 14 天是什么班」。
    // 叠上按天覆盖之后，用户改周期就看不出规则本身的变化了，预览会失去意义。
    // 代价是它跟日历上看到的不一致 —— 所以下面在有覆盖时给一行提示。
    final schedule = ShiftSchedule(
```

**3c.** 顶部提示。把 `_previewStrip` 改成读得到覆盖数（编辑器已在 `_load` 里读方案，顺手用 `dd.dayOverrides.length` 存一个字段）：

```dart
  /// 本方案已设置的按天调整天数（只用于预览上方那行提示）。
  int _overrideDays = 0;
```

在 `_load` 里 `_classes = List.of(dd.classes);` 旁边加 `_overrideDays = dd.dayOverrides.length;`。

然后在 `_previewStrip` 的 `Column` 顶部（标题之前）插入：

```dart
          if (_overrideDays > 0) ...[
            Text(
              L10n.previewHasOverrides(_overrideDays),
              key: const Key('editor-override-hint'),
              style: AppTokens.labelSecondary
                  .copyWith(color: AppTokens.inkMuted(context)),
            ),
            const SizedBox(height: AppTokens.spaceSm),
          ],
```

**3d.** 兜底：从空白表切回普通表那段（约 1105–1125 行）会把 `_classes = []` 再恢复默认，新班次没有 id（null），走 INSERT —— 这是对的，**不用改**。确认一遍别顺手给它塞 id。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd app && flutter test test/schedule_editor_test.dart && flutter analyze
```

期望：新用例 PASS，既有用例不回归。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/schedule_editor_screen.dart app/test/schedule_editor_test.dart
git commit -m "fix(editor): 改班次时保住 id，预览不叠按天覆盖并给出提示"
```

---

### Task 11: 版本号 `0.8.1+92` + 更新日志

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/core/app_info.dart`
- Modify: `app/lib/features/profile/app_dialogs.dart`

**Interfaces:**
- Consumes: 无
- Produces: 无

- [ ] **Step 1: 改两处版本号**

`app/pubspec.yaml` 顶部：`version: 0.8.1+92`
`app/lib/core/app_info.dart`：`const appVersion = '0.8.1';`

（两处必须同步 —— `app/test/app_info_test.dart` 盯着这条，不一致直接红。）

- [ ] **Step 2: 加更新日志条目**

`app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh` 与 `_changelogEn`：**prepend 新版本、删最旧一条、保持 10 条**。

本轮是**测试版**（末位 Z=1，非 0），所以条目**只写自己这版改了什么、原样保留**，不做归纳（归纳是正式版的事）。

中文条目文案：

```
· 日历上可以单独改某一天的班次了：点底栏那行班次，或长按格子拖选一段日子，就能给这几天单独指定班次（请假、跟同事调班都行），不改整套排班
· 被单独改过的那天，格子上有个小圆点，信息卡上写着「已调整」；选择层里可以一键「恢复轮转」
· 编辑排班不再重建班次定义，改方案名不会影响已设置的按天调整
```

英文对应条目照同样的信息量写。

- [ ] **Step 3: 跑测试**

```bash
cd app && flutter test test/app_info_test.dart && flutter test
```

期望：全绿。

- [ ] **Step 4: 提交**

```bash
git add app/pubspec.yaml app/lib/core/app_info.dart app/lib/features/profile/app_dialogs.dart
git commit -m "chore(release): v0.8.1 版本号与更新日志"
```

---

### Task 12: 产品文档收尾

**Files:**
- Modify: `PRODUCT_SPEC.md`
- Modify: `README.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: 前面所有任务的最终形态
- Produces: 无

- [ ] **Step 1: 改 `PRODUCT_SPEC.md`**

1. **§2 的「明确不做」那一行**：划掉「日历上直接改某一天（换班/请假覆盖）」。剩下一行变成：

```
**明确不做（现状仍成立）**：2-2-3 Pitman 型「固定日班组/夜班组」模式、**周期中间插入删除某一天**、桌面小组件、云同步/备份/数据导入导出、工资/补贴记账、广告、商店上架、IM/天气/组织/好友。
```

同时**明确列出**本轮新划的边界（免得以后被当成漏做）：空白表方案下不支持按天改班、不支持跨月拖选、不支持「从这天起一直」。

2. **§2「排班日历」一节**补一条按天改班的说明（点信息卡那行 / 长按拖选一段；圆点标记；恢复轮转；只作用于我们班组；空白表不支持）。

3. **§2「联动班次闹钟」一节**补一句：按天覆盖会流进闹钟排定（改成休班不响、改成别的班按那个班的闹钟时间响），与「按天关闹钟」正交。

4. **§4 数据模型**：表格加一行 `ShiftDayOverrides`；`schemaVersion = 7` 改成 `= 8`；`某天的班次不落库…（为未来「换班/请假覆盖」留余地）` 那句改成「某天的班次**默认不落库**，只有被按天覆盖的那些天才在 `ShiftDayOverrides` 里有一行」。

5. **抬头版本号**：`（现状规格 · v0.8.0）` → `v0.8.1`。

- [ ] **Step 2: 改 `README.md`**

功能清单里补一条按天改班；把任何提到「排班表排完就固定了」或与之矛盾的表述改掉。**逐条对着当前实现核一遍**，别只补新条目（这是本项目反复过时的老毛病）。

- [ ] **Step 3: 改 `AGENTS.md`**

1. `## 目录架构地图` 或「关键决策与坑」里的 Drift 表清单：加 `ShiftDayOverrides`（按天改班覆盖，复合主键 `scheduleId + day`），`当前 schemaVersion = 7` 改成 `= 8`。
2. 「关键决策与坑」加一条：**「班次定义的 id 必须稳定」** —— `saveSchedule` 从前是删光重建、已改成增量；`ShiftClass.id` 存续、`ShiftClassRowX.toDomain()` 必须带上它、编辑器的 `_editClass` 必须传下去，任何一环漏了都会让按天覆盖静默指飞。顺带写明「改 Drift 表后必须重生成」这条仍然成立。
3. 「关键决策与坑」加一条：**`watchActiveSchedule()` 必须同时监听覆盖表**，只监听方案行的话改完覆盖日历不动、且不报错。
4. 版本史那一行：`→ **0.8.0(+91)**（正式稳定版 · 当前）` 改成 `→ **0.8.0(+91)**（正式稳定版）→ 0.8.1(+92) 测试版`。

- [ ] **Step 4: 跑全量验证**

```bash
cd app && flutter analyze && flutter test
```

期望：0 error / 0 warning；全绿。

同时核一遍文档里的数字与实际一致（schemaVersion、条数、版本号）。

- [ ] **Step 5: 提交**

```bash
git add PRODUCT_SPEC.md README.md AGENTS.md
git commit -m "docs: 按天改班（v0.8.1）的产品规格、README 与项目记忆"
```

---

## Self-Review

**1. Spec 覆盖检查**

| Spec 章节 | 落在哪个任务 |
|---|---|
| §3.1 新表 + 迁移 | Task 1 |
| §3.2 `ShiftAlarmOverrides` 不动 | 无任务（**有意**——「不做」本身不需要任务；已写进 Task 1 的表注释里） |
| §4.1 问题 | Task 4 Step 3 的注释 |
| §4.2 `ShiftClass.id` + 增量保存 + 删班次清覆盖 + deleteSchedule/clearAll | Task 2（id）、Task 4（增量与清理） |
| §4.3 编辑器成本（`_editClass` 丢 id） | **Task 10** —— 这是全篇最隐蔽的一处，单独成任务 |
| §5 `dayOverrides` + `shiftOn` + 越界回退 + `teamShift` 不受影响 | Task 2 |
| §5.1 一个出口、四个消费者不用改 | Task 2（实现）＋ 全篇不改那四个调用点（**本身即验证**） |
| §5.2 `watchActiveSchedule` 静默失效 | Task 3 |
| §6 闹钟自动跟随 | Task 2（`shiftOn` 一处改完即生效）＋ Task 8 Step 3 的 `rescheduleAll` |
| §7.1 两个入口 | Task 8（信息卡）＋ Task 9（长按） |
| §7.2 选择层 | Task 7 |
| §7.3 空白表入口不出现 | Task 8 Step 3b 的前置判断 + 3c 的 `onTap: classes.isEmpty ? null` |
| §7.4 小圆点 | Task 9 |
| §8 编辑器预览不带覆盖 + 提示 | Task 10 |
| §9 文案 | Task 6 |
| §10 明确不做 | Task 12 Step 1 |
| §11 测试 | 每个任务各自的 Step 1；迁移与仓库用例集中在 Task 1/3/4/5 |
| §12 收尾 | Task 11（版本/日志）＋ Task 12（文档） |
| §13 风险 1、2、3、4、5、6、7 | 分别落在 Task 3、Task 4、Task 2 Step 5、Task 1 Step 4、Global Constraints、Global Constraints、Task 9 |

**缺口**：无。

**2. 占位符扫描**：Task 7 Step 3 与 Task 10 Step 1 各留了一处「实施前先核实」的标注（`L10n.timeRange` 的签名、编辑器测试的 finder 名）。这是**有意的**——那两处的实际名字我未逐一核实，硬写会给出错的代码；标出来让实施者先 grep 一次，比编一个看起来对的假签名安全。其余步骤都有可执行的代码或命令。

**3. 类型一致性**：`ShiftOverrideChoice`（`change` / `restore` 命名构造、`shift` / `restore` 两个字段）在 Task 7 定义、Task 8 消费，命名一致。`setDayOverrides(List<DateTime>, {required int classId})` / `clearDayOverrides(List<DateTime>)` / `dayOverrideCount()` / `currentScheduleId()` 在 Task 5 定义、Task 8 与 Task 10 消费，签名一致。`ShiftSchedule.dayOverrides` 是 `Map<int, int>`（dayNumber → classes 下标），Task 2 定义、Task 3 装配、Task 8/9 都按 `containsKey(dayNumber(date))` 使用，口径一致。`ActiveSchedule.overrideRows` 命名为 `overrideRows`（不是 `dayOverrides`），避免与领域层那个 Map 混起来。
