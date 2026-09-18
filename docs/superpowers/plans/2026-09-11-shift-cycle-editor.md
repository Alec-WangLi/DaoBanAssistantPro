# 周期排班编辑器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把排班方案从「每天一行的单表」换成「班次定义 + 周期序列」两层模型，放开周期长度，提供 19 种常见倒班方式模板的一键起步，并让编辑器与日历适配新增的班次形态。

**Architecture:** 领域层 `ShiftSchedule` 改为持有 `classes`（班次定义，一个班次只定义一次）与 `cycle`（周期序列，元素是 classes 下标），`shiftOn`/`teamShift` 的内部公式与对外签名不变，因此日历与闹钟两层只需改类型名。持久层新增 `ShiftClassRows` + `ShiftCycleRows` 两张表并通过 schemaVersion 6 迁移搬运老数据。新建排班前插一页「选择你的倒班方式」，模板是纯 Dart 常量数据，选中即生成一个普通方案。

**Tech Stack:** Flutter 3.47.2 / Dart 3.13.2 · Drift 2.31（SQLite，schemaVersion 5 → 6）· Riverpod · 自研液态玻璃组件（`core/glass/`、`core/widgets/`）

**Spec:** `docs/superpowers/specs/2026-09-11-shift-cycle-editor-design.md`

## Global Constraints

- **工具链**：`flutter` 不在 PATH 上，一律用仓库内自举的 `toolchain/flutter/bin/flutter.bat`；所有命令在 `app/` 目录下执行。
- **版本号**：唯一来源 `app/pubspec.yaml`（`0.6.0+71`）与 `app/lib/core/app_info.dart` 的 `appVersion`（`0.6.0`）同步。
  ⚠️ **`+build` 是 Android 的 versionCode，必须单调递增**：`0.5.0+70` 之后是 `0.6.0+71`，**不能写 `0.6.0+0`** —— 那会让 versionCode 从 70 掉到 1，Android 判为降级，老用户无法原地升级。`X.Y.Z` 里的 Z 才是「末位 0 = 正式版」的那个位。
- **改表后必须重生成 Drift 代码**：`dart run build_runner build --delete-conflicting-outputs`。
- **验收门槛**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿。
- **中英双语**：所有新文案走 `L10n`（`core/l10n.dart` 的 `static String get xxx => t('中文','English')`），不硬编码中文。
- **设计语言**：新界面一律用现有玻璃组件（`GlassTile` / `GlassPressable` / `GlassSwitch` / `GlassActionButton` / `showGlassSnack`），底部弹层 `GlassPanel(solid: true)`，弹窗遮罩 `barrierColor: Colors.black26`。
- **发布说明措辞**：只写本应用提供/支持的能力，**不得出现任何「参考 / 借鉴 / 对照 / 类似某 App」的表述，不点名任何第三方应用**。
- **`shiftOn(date)` / `teamShift(i, date)` 的签名与返回字段在本次改造中保持不变**，仅类型名 `ShiftType` → `ShiftClass`；`features/alarm/alarm_service.dart` 的排定逻辑与 `ShiftAlarmOverrides` 表完全不动。

### 规划期发现的补充（对 spec 的一处扩展）

spec §9.3 要求 24 小时值班班次显示为 `08:00 – 次日 08:00`，但现有模型 `endMinute` 最大 1439，`08:00–08:00` 会被判成 0 小时且 `crossesMidnight` 为假。因此本次把分钟域扩展为 **`endMinute` 允许取到 2880**（跨过午夜后继续按「距开始日的分钟数」计数），并让 `crossesMidnight` 与时间显示按下面规则处理：

| 班次 | start | end | crossesMidnight | 显示 |
|---|---|---|---|---|
| 白班 08:30–20:30 | 510 | 1230 | false | `08:30 – 20:30` |
| 上夜班 20:30–次日 08:30 | 1230 | 510 | true | `20:30 – 次日08:30` |
| 中班 16:00–24:00 | 960 | 1440 | false | `16:00 – 24:00` |
| 值班 24 小时 | 480 | 1920 | true | `08:00 – 次日08:00` |

判定规则：`crossesMidnight = e < s || e > 1440`；`1440` 恰好显示为 `24:00`。该扩展只影响 `domain/shift_rotation.dart` 与 `calendar_screen.dart` 的时间格式化，闹钟层只用 `alarmMinute`，不受影响。

### 任务拆分说明

Task 1 与 Task 2 是一次原子替换的两半：Task 1 换领域模型（用一层临时适配器把老的单表读成新模型），Task 2 换持久层并删掉适配器。这样拆是为了**每个任务结束时应用都能编译、测试都全绿**。Task 2 会明确列出它删除的适配代码。

---

## File Structure

| 文件 | 职责 | 变更 |
|---|---|---|
| `app/lib/domain/shift_rotation.dart` | 排班轮换引擎：`ShiftClass` + `ShiftSchedule` + 公式 | 重写 |
| `app/lib/domain/shift_templates.dart` | 19 种倒班方式的模板常量数据 | 新建 |
| `app/lib/data/app_database.dart` | Drift 表定义 + v6 迁移 | 改 |
| `app/lib/data/app_repository.dart` | 读写排班方案 / 事件 / 闹钟 | 改 |
| `app/lib/data/seed.dart` | 首次启动写入默认方案 | 改 |
| `app/lib/features/calendar/shift_template_picker_screen.dart` | 「选择你的倒班方式」页 | 新建 |
| `app/lib/features/calendar/schedule_editor_screen.dart` | 排班编辑器 | 重写 |
| `app/lib/features/calendar/schedule_management_screen.dart` | 排班管理列表 | 改 |
| `app/lib/features/calendar/calendar_screen.dart` | 日历 | 改 |
| `app/lib/features/alarm/alarm_screen.dart` | 闹钟页 | 改（仅类型名） |
| `app/lib/core/l10n.dart` | 双语文案 | 改 |
| `app/test/shift_rotation_test.dart` | 引擎单测 | 改 |
| `app/test/migration_v5_to_v6_test.dart` | 迁移等价性测试 | 新建 |
| `app/test/shift_templates_test.dart` | 模板自检测试 | 新建 |

---

## Task 1: 领域层两层模型（含临时适配器，行为不变）

这一步换掉领域模型，但持久层还是老的「每天一行」单表——用一个临时适配器把老表读成新模型、把新模型展平写回老表。**本任务结束后用户可见行为必须与改动前完全一致。**

**Files:**
- Modify: `app/pubspec.yaml`（把 `characters` 提为直接依赖）
- Modify: `app/lib/domain/shift_rotation.dart`（重写）
- Modify: `app/lib/data/app_repository.dart`（`ActiveSchedule.toDomain()` + `saveSchedule()` 展平）
- Modify: `app/lib/data/seed.dart`
- Modify: `app/lib/features/calendar/calendar_screen.dart`（类型名 + 时间显示）
- Modify: `app/lib/features/calendar/schedule_management_screen.dart`
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`（最小适配）
- Modify: `app/lib/features/alarm/alarm_screen.dart`（类型名）
- Test: `app/test/shift_rotation_test.dart`

**Interfaces:**
- Consumes: 无（本任务是起点）
- Produces:
  - `class ShiftClass { const ShiftClass({required String name, String? abbr, int? startMinute, int? endMinute, bool isRest = false, int color = 0xFF5B7FFF, bool alarmEnabled = false, int? alarmMinute}) }`
  - `String get ShiftClass.shortLabel` / `bool get ShiftClass.crossesMidnight` / `ShiftClass copyWith({...})`
  - `class ShiftSchedule { const ShiftSchedule({required String name, required DateTime anchorDate, required List<ShiftClass> classes, required List<int> cycle, int teamCount = 4, List<String> teamNames = const ['一班','二班','三班','四班'], int ourTeamIndex = 0, List<int> teamOffsets = const []}) }`
  - `int get ShiftSchedule.cycleLength` / `bool get ShiftSchedule.isBlank` / `ShiftClass? shiftOn(DateTime)` / `ShiftClass? teamShift(int, DateTime)`
  - `ShiftSchedule defaultSchedule()`

- [ ] **Step 1: 把 `characters` 提为直接依赖**

`shift_rotation.dart` 要保持无 Flutter 依赖，但需要 `String.characters` 取整字素簇（旧代码在 `calendar_screen.dart` 里用的就是它，靠 Flutter 的再导出）。它已在 `pubspec.lock` 里（Flutter 的传递依赖），提升为直接依赖即可，不引入新的第三方包。

在 `app/pubspec.yaml` 的 `dependencies:` 下的「工具」段加一行：

```yaml
  characters: ^1.4.0
```

然后：

```bash
cd app
../toolchain/flutter/bin/flutter.bat pub get
```

- [ ] **Step 2: 重写 `app/lib/domain/shift_rotation.dart`**

整份替换为：

```dart
// 排班轮换引擎 —— 纯 Dart，无 Flutter 依赖，可直接 dart test。
//
// 两层模型：
//   classes —— 班次定义（白班/上夜班/休班…），一个班次只定义一次
//   cycle   —— 周期序列，长度即周期，元素是 classes 的下标
//
// 核心公式：
//   某班组某天的班次 = classes[ cycle[ (目标日 − 基准日 + 班组偏移) mod 周期 ] ]

import 'package:characters/characters.dart';

/// 小时+分钟 → 分钟自午夜（0..1439）。
int toMinutes(int hour, int minute) => hour * 60 + minute;

/// 两个日期之间的"整日"差，用 UTC 日期整数计算，规避时区/夏令时。
int daysBetween(DateTime a, DateTime b) {
  final da = DateTime.utc(a.year, a.month, a.day);
  final db = DateTime.utc(b.year, b.month, b.day);
  return db.difference(da).inDays;
}

/// 取 UTC 的"纯日期"（时间归零）。
DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// 纯日期 → 自 epoch 的天数（按天闹钟覆盖表的主键）。
int dayNumber(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  return d.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

/// 分钟数 → `HH:mm`，供日历与编辑器共用。1440 恰好显示为 `24:00`。
///
/// [minutes] 可以超过 1440（跨过午夜后继续累加），调用方负责先减掉 1440
/// 并自行补「次日」前缀。
String formatClock(int minutes) {
  if (minutes == 1440) return '24:00';
  final m = minutes % 1440;
  final h = (m ~/ 60).toString().padLeft(2, '0');
  return '$h:${(m % 60).toString().padLeft(2, '0')}';
}

/// 班次定义：一个班次只定义一次，周期里的每一天引用它。
class ShiftClass {
  const ShiftClass({
    required this.name,
    this.abbr,
    this.startMinute,
    this.endMinute,
    this.isRest = false,
    this.color = 0xFF5B7FFF,
    this.alarmEnabled = false,
    this.alarmMinute,
  });

  /// 班次名（自由文本），如 白班 / 上夜班 / 下夜班 / 大休。
  final String name;

  /// 日历格子里的 1~2 字简称；为空时按 [name] 推断。
  final String? abbr;

  /// 工作开始时间（分钟自开始日午夜）。
  final int? startMinute;

  /// 工作结束时间（分钟自开始日午夜）；跨过午夜后继续累加，
  /// 因此 24 小时班的值班是 480 → 1920（08:00 → 次日 08:00）。
  final int? endMinute;

  /// 是否休息日（不响联动闹钟）。
  final bool isRest;

  /// 日历格子的 ARGB 颜色。
  final int color;

  /// 联动闹钟是否开启。
  final bool alarmEnabled;

  /// 联动闹钟响铃时间（分钟自午夜）；null 表示未设。
  final int? alarmMinute;

  /// 工作窗口是否跨过午夜。
  bool get crossesMidnight {
    final s = startMinute, e = endMinute;
    if (s == null || e == null) return false;
    return e < s || e > 1440;
  }

  /// 日历格子显示的简称：优先用 [abbr]，为空时按名称推断。
  ///
  /// 用 `characters.first`（整字素簇）而不是 `substring(0, 1)`：
  /// 后者会把 emoji 等增补平面字符切成半个代理对，旧代码用的就是前者。
  String get shortLabel {
    final a = abbr?.trim();
    if (a != null && a.isNotEmpty) return a;
    if (isRest) return '休';
    if (name.contains('白') || name.contains('早')) return '白';
    if (name.contains('夜')) return '夜';
    return name.isEmpty ? '·' : name.characters.first;
  }

  ShiftClass copyWith({
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
      name: name ?? this.name,
      abbr: abbr ?? this.abbr,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      isRest: isRest ?? this.isRest,
      color: color ?? this.color,
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      alarmMinute: alarmMinute ?? this.alarmMinute,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShiftClass &&
      other.name == name &&
      other.abbr == abbr &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute &&
      other.isRest == isRest &&
      other.color == color &&
      other.alarmEnabled == alarmEnabled &&
      other.alarmMinute == alarmMinute;

  @override
  int get hashCode => Object.hash(name, abbr, startMinute, endMinute, isRest,
      color, alarmEnabled, alarmMinute);

  @override
  String toString() => 'ShiftClass($name, rest=$isRest)';
}

/// 一套排班方案（班次定义 + 轮换周期 + 多班组）。
class ShiftSchedule {
  const ShiftSchedule({
    required this.name,
    required this.anchorDate,
    required this.classes,
    required this.cycle,
    this.teamCount = 4,
    this.teamNames = const ['一班', '二班', '三班', '四班'],
    this.ourTeamIndex = 0,
    this.teamOffsets = const [],
  });

  /// 空白表（跟随法定节假日）：周期为空。
  bool get isBlank => cycle.isEmpty;

  final String name;

  /// 基准日：各班组在此日期的周期位置由 [teamOffsets] 显式指定。
  final DateTime anchorDate;

  /// 班次定义。
  final List<ShiftClass> classes;

  /// 周期序列：长度即周期，元素是 [classes] 的下标。
  final List<int> cycle;

  /// 班组数。
  final int teamCount;

  /// 班组名（长度与 teamCount 一致）。
  final List<String> teamNames;

  /// 我们是第几个班组。
  final int ourTeamIndex;

  /// 每个班组相对基准日的天数偏移（长度与 teamCount 一致）；
  /// 为空时回退到旧的「按 ourTeamIndex 错开」逻辑。
  final List<int> teamOffsets;

  int get cycleLength => cycle.length;

  /// 我们班组的班次；空白表（无周期）返回 null。
  ShiftClass? shiftOn(DateTime date) => teamShift(ourTeamIndex, date);

  /// 指定班组在某天的班次；空白表（无周期）返回 null。
  ShiftClass? teamShift(int teamIndex, DateTime date) {
    if (cycle.isEmpty) return null;
    final base = (teamIndex >= 0 && teamIndex < teamOffsets.length)
        ? teamOffsets[teamIndex]
        : teamIndex - ourTeamIndex; // 回退：旧的按班组错开
    final offset = daysBetween(anchorDate, date) + base;
    var idx = offset % cycleLength;
    if (idx < 0) idx += cycleLength;
    final classIndex = cycle[idx];
    if (classIndex < 0 || classIndex >= classes.length) return null;
    return classes[classIndex];
  }
}

/// 默认「四班两倒」配置：白班 → 上夜班 → 下夜班 → 大休（4 天周期），4 个班组错开。
ShiftSchedule defaultSchedule() {
  final anchor = DateTime.utc(2025, 1, 6); // 占位基准日（我们班组的第 1 天）
  return ShiftSchedule(
    name: '四班两倒',
    anchorDate: anchor,
    teamCount: 4,
    teamNames: const ['一班', '二班', '三班', '四班'],
    ourTeamIndex: 0,
    teamOffsets: const [0, 1, 2, 3],
    cycle: const [0, 1, 2, 3],
    classes: const [
      ShiftClass(
        name: '白班',
        abbr: '白',
        startMinute: 8 * 60 + 30,
        endMinute: 20 * 60 + 30,
        color: 0xFF4C8DFF,
        alarmEnabled: true,
        alarmMinute: 7 * 60,
      ),
      ShiftClass(
        name: '上夜班',
        abbr: '夜',
        startMinute: 20 * 60 + 30,
        endMinute: 8 * 60 + 30,
        color: 0xFF7A5CFF,
        alarmEnabled: true,
        alarmMinute: 19 * 60 + 30,
      ),
      ShiftClass(name: '下夜班', abbr: '休', isRest: true, color: 0xFF9AA0B4),
      ShiftClass(name: '大休', abbr: '休', isRest: true, color: 0xFF5A5F73),
    ],
  );
}
```

- [ ] **Step 2: 改 `app/test/shift_rotation_test.dart`，跑测试确认新模型成立**

把文件里所有 `s.shiftOn(...)` 断言保留，新增三条：

```dart
  test('图层：周期引用的是班次定义，不是每天一行', () {
    final s = ShiftSchedule(
      name: '白白夜夜休休',
      anchorDate: DateTime.utc(2025, 1, 6),
      classes: const [
        ShiftClass(name: '白班', abbr: '白'),
        ShiftClass(name: '夜班', abbr: '夜'),
        ShiftClass(name: '休班', abbr: '休', isRest: true),
      ],
      cycle: const [0, 0, 1, 1, 2, 2],
      teamCount: 3,
      teamNames: const ['一班', '二班', '三班'],
      teamOffsets: const [0, 2, 4],
    );
    expect(s.cycleLength, 6);
    expect(s.classes.length, 3);
    expect(s.shiftOn(DateTime.utc(2025, 1, 6))!.name, '白班');
    expect(s.shiftOn(DateTime.utc(2025, 1, 8))!.name, '夜班');
    expect(s.shiftOn(DateTime.utc(2025, 1, 11))!.name, '休班');
    expect(s.shiftOn(DateTime.utc(2025, 1, 12))!.name, '白班'); // 一轮回绕
  });

  test('格子简称：显式 abbr 优先，为空时按名称推断', () {
    expect(const ShiftClass(name: '早班', abbr: '早').shortLabel, '早');
    expect(const ShiftClass(name: '早班').shortLabel, '白'); // 旧的推断行为
    expect(const ShiftClass(name: '大夜').shortLabel, '夜');
    expect(const ShiftClass(name: '休班', isRest: true).shortLabel, '休');
    expect(const ShiftClass(name: '').shortLabel, '·');
  });

  test('24 小时值班跨午夜', () {
    const duty = ShiftClass(name: '值班', startMinute: 8 * 60, endMinute: 32 * 60);
    expect(duty.crossesMidnight, isTrue);
    const mid = ShiftClass(name: '中班', startMinute: 16 * 60, endMinute: 24 * 60);
    expect(mid.crossesMidnight, isFalse); // 16:00–24:00 不算跨午夜
  });
```

运行：`toolchain/flutter/bin/flutter.bat test test/shift_rotation_test.dart`
预期：PASS。此时 `flutter analyze` 会因其他文件仍引用 `ShiftType` 而报错——下一步修。

- [ ] **Step 3: 改 `app/lib/data/app_repository.dart`（临时适配器）**

`ActiveSchedule.toDomain()` 改为：

```dart
  ShiftSchedule toDomain() => ShiftSchedule(
        name: schedule.name,
        anchorDate: schedule.anchorDate,
        classes: shiftTypes.map((t) => t.toDomain()).toList(),
        // 临时适配：老表就是「每天一行」，直接按行序当周期。
        cycle: List.generate(shiftTypes.length, (i) => i),
        teamCount: schedule.teamCount,
        teamNames: parseTeamNames(schedule.teamNames),
        ourTeamIndex: schedule.ourTeamIndex,
        teamOffsets: parseTeamOffsets(schedule.teamOffsets),
      );
```

`extension ShiftTypeRowX on ShiftTypeRow` 的 `toDomain()` 改为：

```dart
extension ShiftTypeRowX on ShiftTypeRow {
  ShiftClass toDomain() => ShiftClass(
        name: name,
        startMinute: startMinute,
        endMinute: endMinute,
        isRest: isRest,
        color: color,
        alarmEnabled: alarmEnabled,
        alarmMinute: alarmMinute,
      );
}
```

`saveSchedule` 的 `required List<ShiftType> types` 参数换成 `required List<ShiftClass> classes, required List<int> cycle`，写库部分改为展平：

```dart
      // 临时适配：把「定义 + 周期」展平回老表的每天一行。
      await (db.delete(db.shiftTypeRows)
            ..where((t) => t.scheduleId.equals(id)))
          .go();
      for (var i = 0; i < cycle.length; i++) {
        final ci = cycle[i];
        if (ci < 0 || ci >= classes.length) continue;
        final t = classes[ci];
        await db.into(db.shiftTypeRows).insert(
              ShiftTypeRowsCompanion.insert(
                scheduleId: id,
                order: i,
                name: t.name,
                startMinute: Value(t.startMinute),
                endMinute: Value(t.endMinute),
                isRest: Value(t.isRest),
                color: Value(t.color),
                alarmEnabled: Value(t.alarmEnabled),
                alarmMinute: Value(t.alarmMinute),
              ),
            );
      }
```

- [ ] **Step 4: 改 `app/lib/data/seed.dart` 的写入循环**

```dart
  for (var i = 0; i < sched.cycle.length; i++) {
    final t = sched.classes[sched.cycle[i]];
    await db.into(db.shiftTypeRows).insert(
          ShiftTypeRowsCompanion.insert(
            scheduleId: id,
            order: i,
            name: t.name,
            startMinute: Value(t.startMinute),
            endMinute: Value(t.endMinute),
            isRest: Value(t.isRest),
            color: Value(t.color),
            alarmEnabled: Value(t.alarmEnabled),
            alarmMinute: Value(t.alarmMinute),
          ),
        );
  }
```

- [ ] **Step 5: 改消费方（机械改名 + 时间显示）**

`app/lib/features/alarm/alarm_screen.dart:514`：`final ShiftType shift;` → `final ShiftClass shift;`

`app/lib/features/calendar/calendar_screen.dart`：
- 删除顶层函数 `_shortLabel(ShiftType t)`（第 845–850 行），`_dayCell` 里 `_shortLabel(shift)` 改为 `shift.shortLabel`。
- `_timeRange(ShiftType t)` / `_alarmText(ShiftType t)` 的形参类型改为 `ShiftClass`。
- `_timeRange` 整份替换为（复用 domain 里的 `formatClock`，删掉本地 `_fmt`）：

```dart
String _timeRange(ShiftClass t) {
  final s = formatClock(t.startMinute!);
  var e = t.endMinute!;
  final nextDay = e > 1440 || e < t.startMinute!;
  if (e > 1440) e -= 1440;
  return '$s – ${nextDay ? '次日' : ''}${formatClock(e)}';
}
```

- 文件底部私有的 `String _fmt(int minutes)` 换成 domain 里的 `formatClock`（`_alarmText` 里那处调用一并改），然后删掉 `_fmt`，避免两份一样的东西。
- 第 394 行附近的 `types: d.shiftTypes,` 改为 `classes: d.classes,` 并新增一行 `cycle: d.cycle,`

`app/lib/features/calendar/schedule_management_screen.dart:86`：`types: d.shiftTypes,` → `classes: d.classes,` 并新增 `cycle: d.cycle,`

`app/lib/features/calendar/schedule_editor_screen.dart`（最小适配，Task 5 会重写）：
- `List<ShiftType> _types = [];` → `List<ShiftClass> _types = [];`
- `_load` 里 `_types = List.of(dd.shiftTypes);` → `_types = List.of(dd.classes);`
- `_load` 里 `_followHoliday = dd.shiftTypes.isEmpty;` → `_followHoliday = dd.isBlank;`
- `_followHolidayCard` 里 `d.shiftTypes` → `d.classes`
- `_setTeamCount` 里 `_types.add(ShiftType(order: ..., name: L10n.restShift, isRest: true, color: 0xFF9AA0B4))` → `_types.add(const ShiftClass(name: L10n.restShift, isRest: true, color: 0xFF9AA0B4))`
  ⚠️ `L10n.restShift` 是 getter 不是 const，所以这里不能加 `const`，写成 `_types.add(ShiftClass(name: L10n.restShift, isRest: true, color: 0xFF9AA0B4))`。
- `_shiftCard(BuildContext, int, ShiftType t)` → `ShiftClass t`；`t.copyWith(...)` 的 `order:` 参数删掉。
- `_save` 里 `types: _types,` → `classes: _types, cycle: List.generate(_types.length, (i) => i),`
- `_save` 末尾构造 `AlarmService.reschedule(ShiftSchedule(...))` 时同样加 `classes: _types, cycle: List.generate(_types.length, (i) => i),`

- [ ] **Step 6: 跑全量检查**

```bash
cd app
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat test
```

预期：0 error / 0 warning，测试全绿。

- [ ] **Step 7: 手工冒烟（可选但推荐）**

```bash
cd app
../toolchain/flutter/bin/flutter.bat run -d windows
```

确认日历显示的班次、颜色、时间与改动前一致；打开排班编辑器改一下再保存，确认无异常。

- [ ] **Step 8: 提交**

```bash
git add app/lib/domain/shift_rotation.dart app/lib/data/ app/lib/features/ app/test/shift_rotation_test.dart
git commit -m "refactor(schedule): 领域层改为班次定义 + 周期序列两层模型"
```

---

## Task 2: 持久层 v6（两张表 + 迁移 + 迁移等价性测试）

把持久层真正分成两张表，删掉 Task 1 的临时适配器，并用自动化测试证明**老数据迁移后逐日等价**。

**Files:**
- Modify: `app/pubspec.yaml`（把 `sqlite3` 加进 `dev_dependencies`——迁移测试直接 import 它）
- Modify: `app/lib/data/app_database.dart`
- Modify: `app/lib/data/app_repository.dart`
- Modify: `app/lib/data/seed.dart`
- Regenerate: `app/lib/data/app_database.g.dart`（由 build_runner 生成，不手改）
- Test: `app/test/migration_v5_to_v6_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 的 `ShiftClass` / `ShiftSchedule` / `defaultSchedule()`
- Produces:
  - `class ShiftClassRows`（列：`id, scheduleId, order, name, abbr?, startMinute?, endMinute?, isRest, color, alarmEnabled, alarmMinute?`）
  - `class ShiftCycleRows`（列：`id, scheduleId, order, classId`）
  - `AppDatabase.forTesting(QueryExecutor executor)`
  - `Future<int> AppRepository.saveSchedule({int? scheduleId, required String name, required DateTime anchorDate, required List<ShiftClass> classes, required List<int> cycle, bool makeCurrent = true, int teamCount = 4, List<String> teamNames = const ['一班','二班','三班','四班'], int ourTeamIndex = 0, List<int> teamOffsets = const []})`
  - `class ActiveSchedule { final ShiftScheduleRow schedule; final List<ShiftClassRow> classes; final List<ShiftCycleRow> cycle; ShiftSchedule toDomain(); }`

- [ ] **Step 1: 先写迁移等价性测试（此时会失败）**

新建 `app/test/migration_v5_to_v6_test.dart`：

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_database.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v5 时期的表结构（迁移前的形态）。
const _v5Schema = <String>[
  '''
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
  ''',
  '''
  CREATE TABLE shift_type_rows (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    schedule_id INTEGER NOT NULL,
    "order" INTEGER NOT NULL,
    name TEXT NOT NULL,
    start_minute INTEGER,
    end_minute INTEGER,
    is_rest INTEGER NOT NULL DEFAULT 0,
    color INTEGER NOT NULL DEFAULT 4284186623,
    alarm_enabled INTEGER NOT NULL DEFAULT 0,
    alarm_minute INTEGER
  )
  ''',
  '''
  CREATE TABLE schedule_events (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    date INTEGER NOT NULL,
    time_minute INTEGER,
    advance_remind_minutes INTEGER,
    is_completed INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE custom_alarms (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    hour INTEGER NOT NULL,
    minute INTEGER NOT NULL,
    repeat_type INTEGER NOT NULL DEFAULT 1,
    once_date INTEGER,
    weekdays INTEGER NOT NULL DEFAULT 0,
    enabled INTEGER NOT NULL DEFAULT 1
  )
  ''',
  '''
  CREATE TABLE shift_alarm_overrides (
    day INTEGER NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (day)
  )
  ''',
];

class _LegacyRow {
  const _LegacyRow(this.name, this.start, this.end, this.isRest, this.color,
      this.alarmOn, this.alarm);
  final String name;
  final int? start;
  final int? end;
  final int isRest;
  final int color;
  final int alarmOn;
  final int? alarm;
}

/// 手抄的 12 天周期：白×4 休×2 上夜×4 下夜×1 休×1。
/// 四行「白班」字段完全相同 —— 迁移后应合并成 1 个班次定义。
const _legacyTwelveDays = <_LegacyRow>[
  _LegacyRow('白班', 510, 1230, 0, 0xFF4C8DFF, 1, 420),
  _LegacyRow('白班', 510, 1230, 0, 0xFF4C8DFF, 1, 420),
  _LegacyRow('白班', 510, 1230, 0, 0xFF4C8DFF, 1, 420),
  _LegacyRow('白班', 510, 1230, 0, 0xFF4C8DFF, 1, 420),
  _LegacyRow('休班', null, null, 1, 0xFFFF9F0A, 0, null),
  _LegacyRow('休班', null, null, 1, 0xFFFF9F0A, 0, null),
  _LegacyRow('上夜班', 1230, 510, 0, 0xFF7A5CFF, 1, 1170),
  _LegacyRow('上夜班', 1230, 510, 0, 0xFF7A5CFF, 1, 1170),
  _LegacyRow('上夜班', 1230, 510, 0, 0xFF7A5CFF, 1, 1170),
  _LegacyRow('上夜班', 1230, 510, 0, 0xFF7A5CFF, 1, 1170),
  _LegacyRow('下夜班', null, null, 1, 0xFF9AA0B4, 0, null),
  _LegacyRow('休班', null, null, 1, 0xFFFF9F0A, 0, null),
];

// `DateTime.utc` 不是 const 构造，只能用 final。
final _anchor = DateTime.utc(2025, 1, 6);

ShiftClass _toClass(_LegacyRow r) => ShiftClass(
      name: r.name,
      startMinute: r.start,
      endMinute: r.end,
      isRest: r.isRest != 0,
      color: r.color,
      alarmEnabled: r.alarmOn != 0,
      alarmMinute: r.alarm,
    );

void main() {
  late sqlite3.Database raw;

  setUp(() {
    raw = sqlite3.sqlite3.openInMemory();
    for (final ddl in _v5Schema) {
      raw.execute(ddl);
    }
    raw.execute(
      'INSERT INTO shift_schedule_rows '
      '(id, name, anchor_date, is_current, team_count, team_names, '
      'our_team_index, team_offsets) VALUES (1, ?, ?, 1, 1, ?, 0, ?)',
      [
        'B班',
        _anchor.millisecondsSinceEpoch ~/ 1000,
        '我',
        '0',
      ],
    );
    for (var i = 0; i < _legacyTwelveDays.length; i++) {
      final r = _legacyTwelveDays[i];
      raw.execute(
        'INSERT INTO shift_type_rows '
        '(schedule_id, "order", name, start_minute, end_minute, is_rest, '
        'color, alarm_enabled, alarm_minute) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?)',
        [i, r.name, r.start, r.end, r.isRest, r.color, r.alarmOn, r.alarm],
      );
    }
    raw.execute('PRAGMA user_version = 5');
  });

  tearDown(() => raw.dispose());

  test('v5 → v6 迁移后逐日等价，且重复班次合并成一个定义', () async {
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final migrated = await AppRepository(db).getScheduleDomain(1);
    expect(migrated, isNotNull);

    // 基准日原样保留
    expect(migrated!.anchorDate.year, 2025);
    expect(migrated.anchorDate.month, 1);
    expect(migrated.anchorDate.day, 6);

    // 12 天周期 + 4 个定义（白班 / 休班 / 上夜班 / 下夜班）
    expect(migrated.cycleLength, 12);
    expect(migrated.classes.map((c) => c.name).toList(),
        ['白班', '休班', '上夜班', '下夜班']);
    expect(migrated.classes.where((c) => c.name == '白班').length, 1);

    // 迁移前的等价模型：老表就是「每天一行」
    final before = ShiftSchedule(
      name: 'B班',
      anchorDate: _anchor,
      classes: _legacyTwelveDays.map(_toClass).toList(),
      cycle: List.generate(_legacyTwelveDays.length, (i) => i),
      teamCount: 1,
      teamNames: const ['我'],
      ourTeamIndex: 0,
      teamOffsets: const [0],
    );

    for (var d = -30; d <= 60; d++) {
      final date = _anchor.add(Duration(days: d));
      final a = before.shiftOn(date);
      final b = migrated.shiftOn(date);
      final why = '第 $d 天不一致';
      expect(b?.name, a?.name, reason: why);
      expect(b?.startMinute, a?.startMinute, reason: why);
      expect(b?.endMinute, a?.endMinute, reason: why);
      expect(b?.isRest, a?.isRest, reason: why);
      expect(b?.color, a?.color, reason: why);
      expect(b?.alarmEnabled, a?.alarmEnabled, reason: why);
      expect(b?.alarmMinute, a?.alarmMinute, reason: why);
    }
  });

  test('迁移后旧的 shift_type_rows 表已删除', () async {
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await AppRepository(db).getScheduleDomain(1); // 触发迁移
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='shift_type_rows'")
        .get();
    expect(rows, isEmpty);
  });

  test('空方案（跟随法定节假日）迁移后仍为空', () async {
    raw.execute(
      'INSERT INTO shift_schedule_rows '
      '(id, name, anchor_date, is_current, team_count, team_names, '
      'our_team_index, team_offsets) VALUES (2, ?, ?, 0, 1, ?, 0, ?)',
      ['法定节假日', _anchor.millisecondsSinceEpoch ~/ 1000, '我', '0'],
    );
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);
    final blank = await AppRepository(db).getScheduleDomain(2);
    expect(blank, isNotNull);
    expect(blank!.isBlank, isTrue);
    expect(blank.shiftOn(_anchor), isNull);
  });
}
```

运行：`../toolchain/flutter/bin/flutter.bat test test/migration_v5_to_v6_test.dart`
预期：编译失败（`AppDatabase.forTesting` 不存在、`AppRepository.getScheduleDomain` 还没换）——这是预期的红。

- [ ] **Step 2: 改 `app/lib/data/app_database.dart`**

`ShiftTypeRows` 整类替换为下面两张表（放在原来 `ShiftTypeRows` 的位置）：

```dart
/// 班次定义表：一个班次只定义一次（属于某套排班方案）。
class ShiftClassRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get scheduleId => integer()();
  IntColumn get order => integer()();
  TextColumn get name => text()();

  /// 日历格子里的 1~2 字简称；为空时按名称推断。
  TextColumn get abbr => text().nullable()();
  IntColumn get startMinute => integer().nullable()();
  IntColumn get endMinute => integer().nullable()();
  BoolColumn get isRest => boolean().withDefault(const Constant(false))();
  IntColumn get color => integer().withDefault(const Constant(0xFF5B7FFF))();
  BoolColumn get alarmEnabled => boolean().withDefault(const Constant(false))();
  IntColumn get alarmMinute => integer().nullable()();
}

/// 周期序列表：第 N 天用哪个班次定义。
class ShiftCycleRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get scheduleId => integer()();
  IntColumn get order => integer()();
  IntColumn get classId => integer()();
}
```

`@DriftDatabase(tables: [...])` 里把 `ShiftTypeRows` 换成 `ShiftClassRows, ShiftCycleRows`，`schemaVersion` 改为 `6`。

给 `AppDatabase` 加测试构造：

```dart
  AppDatabase() : super(driftDatabase(name: 'shiftassistantpro'));

  /// 测试专用：接外部注入的 QueryExecutor（内存库 / 迁移 fixture）。
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);
```

`migration` 改为（**注意 `from < 6` 必须在最后**，因为它读的是其它分支整理完的 v5 形态表）：

```dart
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 5) {
            await m.createTable(shiftAlarmOverrides);
          }
          if (from < 4) {
            await m.addColumn(shiftScheduleRows, shiftScheduleRows.teamOffsets);
          }
          if (from < 3) {
            await m.createTable(customAlarms);
          }
          if (from < 2) {
            // 1) shift_type_rows 去掉 3 列（提前提醒/贪睡）：重建表
            //
            // 注意：这里不能用 m.createTable(shiftTypeRows)——ShiftTypeRows 表类
            // 在本版已被 ShiftClassRows/ShiftCycleRows 取代、从 @DriftDatabase 注销，
            // 引用它编译不过。改成等价的原生 SQL 建出 v5 形态的表，
            // 好让下面的 from < 6 分支仍能读到它。
            await customStatement(
                'ALTER TABLE shift_type_rows RENAME TO shift_type_rows_old');
            await customStatement('''
              CREATE TABLE shift_type_rows (
                id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                schedule_id INTEGER NOT NULL,
                "order" INTEGER NOT NULL,
                name TEXT NOT NULL,
                start_minute INTEGER,
                end_minute INTEGER,
                is_rest INTEGER NOT NULL DEFAULT 0,
                color INTEGER NOT NULL DEFAULT 4284186623,
                alarm_enabled INTEGER NOT NULL DEFAULT 0,
                alarm_minute INTEGER
              )
            ''');
            await customStatement(
              'INSERT INTO shift_type_rows (id, schedule_id, "order", name, '
              'start_minute, end_minute, is_rest, color, alarm_enabled, alarm_minute) '
              'SELECT id, schedule_id, "order", name, start_minute, end_minute, '
              'is_rest, color, alarm_enabled, alarm_minute FROM shift_type_rows_old',
            );
            await customStatement('DROP TABLE shift_type_rows_old');

            // 2) shift_schedule_rows 加 3 个班组列
            await m.addColumn(shiftScheduleRows, shiftScheduleRows.teamCount);
            await m.addColumn(shiftScheduleRows, shiftScheduleRows.teamNames);
            await m.addColumn(
                shiftScheduleRows, shiftScheduleRows.ourTeamIndex);
          }
          // 必须最后跑：要读的是上面各分支整理完的 v5 形态表。
          if (from < 6) {
            await m.createTable(shiftClassRows);
            await m.createTable(shiftCycleRows);
            await _migrateRowsToTwoTier();
          }
        },
      );

  /// v5 → v6：把「每天一行」的班次拆成
  /// 班次定义（shift_class_rows）+ 周期序列（shift_cycle_rows）。
  ///
  /// 字段完全相同的行合并成同一个定义 —— 12 天里 4 个「白班」迁完只剩 1 个。
  Future<void> _migrateRowsToTwoTier() async {
    final rows = await customSelect(
      'SELECT schedule_id, "order", name, start_minute, end_minute, is_rest, '
      'color, alarm_enabled, alarm_minute FROM shift_type_rows '
      'ORDER BY schedule_id, "order"',
    ).get();

    final idBySignature = <String, int>{};
    final definitionsInSchedule = <int, int>{};
    var nextClassId = 1;

    for (final r in rows) {
      final scheduleId = r.read<int>('schedule_id');
      final name = r.read<String>('name');
      final startMinute = r.read<int?>('start_minute');
      final endMinute = r.read<int?>('end_minute');
      final isRest = r.read<int>('is_rest') != 0;
      final color = r.read<int>('color');
      final alarmEnabled = r.read<int>('alarm_enabled') != 0;
      final alarmMinute = r.read<int?>('alarm_minute');
      final order = r.read<int>('order');

      final signature = <Object?>[
        scheduleId,
        name,
        startMinute,
        endMinute,
        isRest,
        color,
        alarmEnabled,
        alarmMinute,
      ].join('|');

      var classId = idBySignature[signature];
      if (classId == null) {
        classId = nextClassId++;
        idBySignature[signature] = classId;
        final orderInList = definitionsInSchedule[scheduleId] ?? 0;
        definitionsInSchedule[scheduleId] = orderInList + 1;
        await customInsert(
          'INSERT INTO shift_class_rows '
          '(id, schedule_id, "order", name, abbr, start_minute, end_minute, '
          'is_rest, color, alarm_enabled, alarm_minute) '
          'VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withInt(classId),
            Variable.withInt(scheduleId),
            Variable.withInt(orderInList),
            Variable.withString(name),
            // ⚠️ Variable.withInt 的形参是非空 int，插可空列必须用
            //    Variable<int>(null) 这种构造，否则编译不过。
            Variable<int>(startMinute),
            Variable<int>(endMinute),
            Variable.withInt(isRest ? 1 : 0),
            Variable.withInt(color),
            Variable.withInt(alarmEnabled ? 1 : 0),
            Variable<int>(alarmMinute),
          ],
        );
      }

      await customInsert(
        'INSERT INTO shift_cycle_rows (schedule_id, "order", class_id) '
        'VALUES (?, ?, ?)',
        variables: [
          Variable.withInt(scheduleId),
          Variable.withInt(order),
          Variable.withInt(classId),
        ],
      );
    }

    await customStatement('DROP TABLE IF EXISTS shift_type_rows');
  }
```

- [ ] **Step 3: 重生成 Drift 代码**

```bash
cd app
../toolchain/flutter/bin/dart.exe run build_runner build --delete-conflicting-outputs
```

预期：`app_database.g.dart` 重新生成，包含 `ShiftClassRow` / `ShiftCycleRow` / `ShiftClassRowsCompanion` / `ShiftCycleRowsCompanion`，不再有 `ShiftTypeRow`。

- [ ] **Step 4: 改 `app/lib/data/app_repository.dart`（删掉 Task 1 的适配器）**

`ActiveSchedule` 整类替换：

```dart
/// 活跃排班方案（当前方案行 + 班次定义 + 周期序列）。
class ActiveSchedule {
  const ActiveSchedule({
    required this.schedule,
    required this.classes,
    required this.cycle,
  });

  final ShiftScheduleRow schedule;
  final List<ShiftClassRow> classes;
  final List<ShiftCycleRow> cycle;

  ShiftSchedule toDomain() {
    final domainClasses = classes.map((c) => c.toDomain()).toList();
    // 库里存的是 classId，领域层要的是 classes 的下标。
    final indexById = {
      for (var i = 0; i < classes.length; i++) classes[i].id: i,
    };
    final domainCycle = cycle
        .map((r) => indexById[r.classId] ?? -1)
        .where((i) => i >= 0)
        .toList();
    final n = schedule.teamCount;
    final names = parseTeamNames(schedule.teamNames);
    final offsets = parseTeamOffsets(schedule.teamOffsets);
    return ShiftSchedule(
      name: schedule.name,
      anchorDate: schedule.anchorDate,
      classes: domainClasses,
      cycle: domainCycle,
      teamCount: n,
      // 统一补位到 teamCount：模板生成的 6 班组方案只带了默认的 4 个班组名，
      // 不补位的话消费方按 teamCount 索引会越界。
      teamNames: List.generate(
        n,
        (i) => i < names.length ? names[i] : (i < 8 ? '${_cnNum(i)}班' : '${i + 1}班'),
      ),
      ourTeamIndex: schedule.ourTeamIndex,
      teamOffsets: List.generate(
        n,
        (i) => i < offsets.length ? offsets[i] : (i - schedule.ourTeamIndex),
      ),
    );
  }
}

const _cnNums = ['一', '二', '三', '四', '五', '六', '七', '八'];
String _cnNum(int i) => i < _cnNums.length ? _cnNums[i] : '${i + 1}';

extension ShiftClassRowX on ShiftClassRow {
  ShiftClass toDomain() => ShiftClass(
        name: name,
        abbr: abbr,
        startMinute: startMinute,
        endMinute: endMinute,
        isRest: isRest,
        color: color,
        alarmEnabled: alarmEnabled,
        alarmMinute: alarmMinute,
      );
}
```

`watchActiveSchedule()` 与 `getScheduleDomain()`、`getActiveSchedule()` 三处读取都改为同时取两张表：

```dart
  /// 监听当前排班方案及其班次（响应式）。
  Stream<ActiveSchedule?> watchActiveSchedule() {
    final schedQuery = select(shiftScheduleRows)
      ..where((s) => s.isCurrent.equals(true));
    return schedQuery.watchSingleOrNull().asyncMap((sched) async {
      if (sched == null) return null;
      return _loadChildren(sched);
    });
  }

  Future<ActiveSchedule> _loadChildren(ShiftScheduleRow sched) async {
    final classes = await (select(shiftClassRows)
          ..where((t) => t.scheduleId.equals(sched.id))
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    final cycle = await (select(shiftCycleRows)
          ..where((t) => t.scheduleId.equals(sched.id))
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    return ActiveSchedule(schedule: sched, classes: classes, cycle: cycle);
  }
```

`getScheduleDomain(int id)`：

```dart
  /// 取一套排班方案的完整领域模型（含班次定义与周期）。
  Future<ShiftSchedule?> getScheduleDomain(int id) async {
    final row = await (db.select(db.shiftScheduleRows)
          ..where((s) => s.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return (await _loadChildren(row)).toDomain();
  }

  /// 立即读取当前方案领域模型（重排闹钟用，避免读 Riverpod 流拿到旧值）。
  Future<ShiftSchedule?> getActiveSchedule() async {
    final row = await (db.select(db.shiftScheduleRows)
          ..where((s) => s.isCurrent.equals(true)))
        .getSingleOrNull();
    if (row == null) return null;
    return (await _loadChildren(row)).toDomain();
  }
```

`clearAll()` 的删除清单里把 `db.shiftTypeRows` 换成 `db.shiftCycleRows` 与 `db.shiftClassRows`（**先删 cycle 再删 classes**，先删子后删父）。

`saveSchedule` 的写库部分替换为：

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

      for (var i = 0; i < cycle.length; i++) {
        final ci = cycle[i];
        if (ci < 0 || ci >= classIds.length) continue;
        await db.into(db.shiftCycleRows).insert(
              ShiftCycleRowsCompanion.insert(
                scheduleId: id,
                order: i,
                classId: classIds[ci],
              ),
            );
      }
```

- [ ] **Step 5: 改 `app/lib/data/seed.dart` 的写入**

```dart
  final classIds = <int>[];
  for (var i = 0; i < sched.classes.length; i++) {
    final c = sched.classes[i];
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
  for (var i = 0; i < sched.cycle.length; i++) {
    await db.into(db.shiftCycleRows).insert(
          ShiftCycleRowsCompanion.insert(
            scheduleId: id,
            order: i,
            classId: classIds[sched.cycle[i]],
          ),
        );
  }
```

- [ ] **Step 6: 跑测试**

```bash
cd app
../toolchain/flutter/bin/flutter.bat test
../toolchain/flutter/bin/flutter.bat analyze
```

预期：迁移测试三条全绿，其余测试不受影响，analyze 0 error / 0 warning。

- [ ] **Step 7: 用真机/桌面验证老数据**

如果手边有装着旧版的设备：覆盖安装后打开，确认日历上的班次、颜色与升级前一致。若没有，跳过此步并在提交信息里注明。

- [ ] **Step 8: 提交**

```bash
git add app/lib/data/ app/test/migration_v5_to_v6_test.dart
git commit -m "feat(schedule): 持久层拆成班次定义 + 周期序列两张表（schemaVersion 6）"
```

---

## Task 3: 模板库数据 + 自检测试

**Files:**
- Create: `app/lib/domain/shift_templates.dart`
- Test: `app/test/shift_templates_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 的 `ShiftClass`
- Produces:
  - `class ShiftTemplate { const ShiftTemplate({required String id, required String title, required String subtitle, required List<String> aliases, required String group, required List<ShiftClass> classes, required List<int> cycle, int teamCount = 1, List<int> teamOffsets = const [0]}) }`
  - `int get ShiftTemplate.workingTeamsPerDay`
  - `List<ShiftTemplate> get shiftTemplates`
  - `List<String> get shiftTemplateGroups`（分组显示顺序）
  - `ShiftTemplate? findTemplate(String id)`

- [ ] **Step 1: 写自检测试（先红）**

新建 `app/test/shift_templates_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';

void main() {
  test('模板库非空且 id 唯一', () {
    expect(shiftTemplates, isNotEmpty);
    final ids = shiftTemplates.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('每个模板结构自洽', () {
    for (final t in shiftTemplates) {
      final why = '模板 ${t.id}';
      expect(t.cycle, isNotEmpty, reason: why);
      expect(t.classes, isNotEmpty, reason: why);
      expect(t.teamCount, greaterThanOrEqualTo(1), reason: why);
      expect(t.teamOffsets.length, t.teamCount, reason: why);
      expect(t.title.trim(), isNotEmpty, reason: why);
      expect(t.subtitle.trim(), isNotEmpty, reason: why);
      expect(t.aliases, isNotEmpty, reason: why);
      for (final i in t.cycle) {
        expect(i, inInclusiveRange(0, t.classes.length - 1), reason: why);
      }
      for (final c in t.classes) {
        if (c.isRest) {
          expect(c.alarmEnabled, isFalse, reason: '$why：休息班次不该开联动闹钟');
        } else {
          expect(c.startMinute, isNotNull, reason: '$why：工作班次必须有时间');
          expect(c.endMinute, isNotNull, reason: '$why：工作班次必须有时间');
          expect(c.alarmMinute, isNotNull, reason: '$why：工作班次必须带建议闹钟');
        }
      }
    }
  });

  test('多班组模板每天上班组数恒定且符合预期', () {
    // 只有轮转型模板（班组数 > 1）才要求每天人数恒定；
    // 常白 / 做X休Y 是单人班表，人数本来就按天变化。
    const expected = <String, int>{
      'day_night_rest_rest': 2,
      'white_white_night_night_rest_rest': 2,
      'white_white_rest_rest_night_night_rest_rest': 2,
      'two_shift_weekly': 2,
      'dupont': 2,
      'four_crew_three_shift': 3,
      'five_crew_three_shift': 3,
      'six_crew_three_shift': 3,
      'five_crew_four_shift': 4,
      'six_crew_four_shift': 4,
      'duty_24_24': 1,
      'duty_24_48': 1,
      'duty_24_72': 1,
    };
    for (final t in shiftTemplates.where((t) => t.teamCount > 1)) {
      final want = expected[t.id];
      expect(want, isNotNull, reason: '模板 ${t.id} 缺预期上班组数');
      expect(t.workingTeamsPerDay, want, reason: '模板 ${t.id} 上班组数不符');
    }
  });

  test('findTemplate 能按 id 取到', () {
    expect(findTemplate('dupont')?.cycle.length, 28);
    expect(findTemplate('不存在'), isNull);
  });
}
```

运行：`../toolchain/flutter/bin/flutter.bat test test/shift_templates_test.dart`
预期：编译失败（文件不存在）——预期的红。

- [ ] **Step 2: 新建 `app/lib/domain/shift_templates.dart`**

```dart
// 常见倒班方式模板 —— 纯 Dart 常量数据，无 Flutter 依赖，不入库。
//
// 模板只是一份「配方」：选中后生成的就是一个普通排班方案，
// 用户可以随意改，数据库里没有「模板」这个概念。
//
// 周期结构（几天一循环、每天几个班、几个班组错开）是模板要负责摆对的；
// 具体到几点几分各厂差异很大，这里只填常见值，用户可改。

import 'shift_rotation.dart';

class ShiftTemplate {
  const ShiftTemplate({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.aliases,
    required this.group,
    required this.classes,
    required this.cycle,
    this.teamCount = 1,
    this.teamOffsets = const [0],
  });

  final String id;

  /// 人话主标题（给不懂术语的人看）。
  final String title;

  /// 行话副标题（给会搜「四班三倒」的人看）。
  final String subtitle;

  /// 搜索词。
  final List<String> aliases;

  /// 分组：12 小时制 / 8 小时制 / 6 小时制 / 值班制 / 常白。
  final String group;

  /// 班次定义。
  final List<ShiftClass> classes;

  /// 周期序列（元素是 [classes] 的下标）。
  final List<int> cycle;

  final int teamCount;
  final List<int> teamOffsets;

  int get cycleLength => cycle.length;

  /// 每天同时在上班的班组数（轮转型模板应当每天都一样）。
  int get workingTeamsPerDay {
    var count = 0;
    for (var t = 0; t < teamCount; t++) {
      final offset = t < teamOffsets.length ? teamOffsets[t] : t;
      final idx = offset % cycle.length;
      if (idx < 0) continue;
      if (!classes[cycle[idx]].isRest) count++;
    }
    return count;
  }
}

/// 界面上分组的显示顺序。
const shiftTemplateGroups = <String>[
  '12 小时制',
  '8 小时制',
  '6 小时制',
  '值班制',
  '常白',
];

// ---------------------------------------------------------------------------
// 共用班次
// ---------------------------------------------------------------------------

// 12 小时制
const _d12 = ShiftClass(
    name: '白班', abbr: '白', startMinute: 8 * 60 + 30, endMinute: 20 * 60 + 30,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 7 * 60);
const _n12 = ShiftClass(
    name: '夜班', abbr: '夜', startMinute: 20 * 60 + 30, endMinute: 8 * 60 + 30,
    color: 0xFF7A5CFF, alarmEnabled: true, alarmMinute: 19 * 60);

// 8 小时制
const _e8 = ShiftClass(
    name: '早班', abbr: '早', startMinute: 8 * 60, endMinute: 16 * 60,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 7 * 60);
const _m8 = ShiftClass(
    name: '中班', abbr: '中', startMinute: 16 * 60, endMinute: 24 * 60,
    color: 0xFFFF9F0A, alarmEnabled: true, alarmMinute: 15 * 60);
const _n8 = ShiftClass(
    name: '夜班', abbr: '夜', startMinute: 0, endMinute: 8 * 60,
    color: 0xFF7A5CFF, alarmEnabled: true, alarmMinute: 23 * 60);

// 6 小时制
const _e6 = ShiftClass(
    name: '早班', abbr: '早', startMinute: 6 * 60, endMinute: 12 * 60,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 5 * 60 + 30);
const _m6 = ShiftClass(
    name: '中班', abbr: '中', startMinute: 12 * 60, endMinute: 18 * 60,
    color: 0xFFFF9F0A, alarmEnabled: true, alarmMinute: 11 * 60 + 30);
const _l6 = ShiftClass(
    name: '晚班', abbr: '晚', startMinute: 18 * 60, endMinute: 24 * 60,
    color: 0xFF00C7BE, alarmEnabled: true, alarmMinute: 17 * 60 + 30);
const _n6 = ShiftClass(
    name: '夜班', abbr: '夜', startMinute: 0, endMinute: 6 * 60,
    color: 0xFF7A5CFF, alarmEnabled: true, alarmMinute: 23 * 60);

// 24 小时值班：08:00 → 次日 08:00（endMinute 跨过午夜继续累加）
const _duty = ShiftClass(
    name: '值班', abbr: '值', startMinute: 8 * 60, endMinute: 32 * 60,
    color: 0xFFFF375F, alarmEnabled: true, alarmMinute: 7 * 60);

// 常白
const _office = ShiftClass(
    name: '白班', abbr: '白', startMinute: 8 * 60 + 30, endMinute: 17 * 60 + 30,
    color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 7 * 60 + 30);

// 休息
const _rest = ShiftClass(name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4);
const _restGrey =
    ShiftClass(name: '休息', abbr: '休', isRest: true, color: 0xFF5A5F73);

// ---------------------------------------------------------------------------
// 模板库
// ---------------------------------------------------------------------------

final List<ShiftTemplate> shiftTemplates = [
  // -------- 12 小时制 --------
  const ShiftTemplate(
    id: 'day_night_rest_rest',
    title: '上一天白班、一天夜班，然后休两天',
    subtitle: '白夜休休 · 四班两倒',
    aliases: ['白夜休休', '四班两倒', '4班2倒', '两班倒'],
    group: '12 小时制',
    classes: [_d12, _n12, _rest],
    cycle: [0, 1, 2, 2],
    teamCount: 4,
    teamOffsets: [0, 1, 2, 3],
  ),
  const ShiftTemplate(
    id: 'white_white_night_night_rest_rest',
    title: '白班两天、夜班两天，然后休两天',
    subtitle: '白白夜夜休休 · 三班两倒',
    aliases: ['白白夜夜休休', '三班两倒', '3班2倒'],
    group: '12 小时制',
    classes: [_d12, _n12, _rest],
    cycle: [0, 0, 1, 1, 2, 2],
    teamCount: 3,
    teamOffsets: [0, 2, 4],
  ),
  const ShiftTemplate(
    id: 'white_white_rest_rest_night_night_rest_rest',
    title: '上两天白班休两天，再上两天夜班休两天',
    subtitle: '白白休休夜夜休休',
    aliases: ['白白休休夜夜休休', '四班两倒'],
    group: '12 小时制',
    classes: [_d12, _n12, _rest],
    cycle: [0, 0, 2, 2, 1, 1, 2, 2],
    teamCount: 4,
    teamOffsets: [0, 2, 4, 6],
  ),
  const ShiftTemplate(
    id: 'two_shift_weekly',
    title: '白班、夜班各上一整周，每周倒一次',
    subtitle: '上 12 休 12 · 两班倒',
    aliases: ['两班倒', '上12休12', '两班两倒', '一周一倒'],
    group: '12 小时制',
    classes: [_d12, _n12],
    cycle: [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1],
    teamCount: 2,
    teamOffsets: [0, 7],
  ),
  const ShiftTemplate(
    id: 'dupont',
    title: '四夜三休、三白一休、三夜三休、四白，再连休七天',
    subtitle: 'DuPont · 28 天周期',
    aliases: ['dupont', '杜邦', '28天', '四班两倒'],
    group: '12 小时制',
    classes: [_d12, _n12, _rest],
    cycle: [
      1, 1, 1, 1, 2, 2, 2, 0, 0, 0, 2, 1, 1, 1,
      2, 2, 2, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2, 2,
    ],
    teamCount: 4,
    teamOffsets: [0, 7, 14, 21],
  ),

  // -------- 8 小时制 --------
  const ShiftTemplate(
    id: 'four_crew_three_shift',
    title: '早班两天、中班两天、夜班两天，然后休两天',
    subtitle: '四班三倒 · 四班三运转',
    aliases: ['四班三倒', '四班三运转', '早晚中', '8小时'],
    group: '8 小时制',
    classes: [_e8, _m8, _n8, _rest],
    cycle: [0, 0, 1, 1, 2, 2, 3, 3],
    teamCount: 4,
    teamOffsets: [0, 2, 4, 6],
  ),
  const ShiftTemplate(
    id: 'five_crew_three_shift',
    title: '早班、中班、夜班各一天，然后休两天',
    subtitle: '五班三倒',
    aliases: ['五班三倒', '5班3倒'],
    group: '8 小时制',
    classes: [_e8, _m8, _n8, _rest],
    cycle: [0, 1, 2, 3, 3],
    teamCount: 5,
    teamOffsets: [0, 1, 2, 3, 4],
  ),
  const ShiftTemplate(
    id: 'six_crew_three_shift',
    title: '上一天班休两天，早中夜轮着来',
    subtitle: '六班三倒',
    aliases: ['六班三倒', '6班3倒'],
    group: '8 小时制',
    classes: [_e8, _m8, _n8, _rest],
    cycle: [0, 3, 1, 3, 2, 3],
    teamCount: 6,
    teamOffsets: [0, 1, 2, 3, 4, 5],
  ),

  // -------- 6 小时制 --------
  const ShiftTemplate(
    id: 'five_crew_four_shift',
    title: '早中晚夜各一天，然后休一天',
    subtitle: '五班四倒',
    aliases: ['五班四倒', '5班4倒', '6小时'],
    group: '6 小时制',
    classes: [_e6, _m6, _l6, _n6, _rest],
    cycle: [0, 1, 2, 3, 4],
    teamCount: 5,
    teamOffsets: [0, 1, 2, 3, 4],
  ),
  const ShiftTemplate(
    id: 'six_crew_four_shift',
    title: '早中晚夜各一天，然后休两天',
    subtitle: '六班四倒',
    aliases: ['六班四倒', '6班4倒'],
    group: '6 小时制',
    classes: [_e6, _m6, _l6, _n6, _rest],
    cycle: [0, 1, 2, 3, 4, 4],
    teamCount: 6,
    teamOffsets: [0, 1, 2, 3, 4, 5],
  ),

  // -------- 值班制 --------
  const ShiftTemplate(
    id: 'duty_24_24',
    title: '上 24 小时，休 24 小时',
    subtitle: '上 24 休 24',
    aliases: ['上24休24', '24小时', '值班'],
    group: '值班制',
    classes: [_duty, _restGrey],
    cycle: [0, 1],
    teamCount: 2,
    teamOffsets: [0, 1],
  ),
  const ShiftTemplate(
    id: 'duty_24_48',
    title: '上 24 小时，休 48 小时',
    subtitle: '上 24 休 48',
    aliases: ['上24休48', '上1休2', '值班'],
    group: '值班制',
    classes: [_duty, _restGrey],
    cycle: [0, 1, 1],
    teamCount: 3,
    teamOffsets: [0, 1, 2],
  ),
  const ShiftTemplate(
    id: 'duty_24_72',
    title: '上 24 小时，休 72 小时',
    subtitle: '上 24 休 72',
    aliases: ['上24休72', '上1休3', '值班'],
    group: '值班制',
    classes: [_duty, _restGrey],
    cycle: [0, 1, 1, 1],
    teamCount: 4,
    teamOffsets: [0, 1, 2, 3],
  ),

  // -------- 常白 --------
  const ShiftTemplate(
    id: 'standard_week',
    title: '周一到周五上班，周末休息',
    subtitle: '长白班 · 双休',
    aliases: ['长白班', '行政班', '双休', '朝九晚五', '周末双休'],
    group: '常白',
    classes: [_office, _restGrey],
    cycle: [0, 0, 0, 0, 0, 1, 1],
  ),
  const ShiftTemplate(
    id: 'big_small_week',
    title: '这周休一天，下周休两天',
    subtitle: '大小周',
    aliases: ['大小周', '大周小周'],
    group: '常白',
    classes: [_office, _restGrey],
    cycle: [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1],
  ),
  const ShiftTemplate(
    id: 'work_1_rest_1',
    title: '上一天休一天',
    subtitle: '做一休一',
    aliases: ['做一休一', '上一休一'],
    group: '常白',
    classes: [_d12, _rest],
    cycle: [0, 1],
  ),
  const ShiftTemplate(
    id: 'work_2_rest_2',
    title: '上两天休两天',
    subtitle: '做二休二',
    aliases: ['做二休二', '上二休二'],
    group: '常白',
    classes: [_d12, _rest],
    cycle: [0, 0, 1, 1],
  ),
  const ShiftTemplate(
    id: 'work_4_rest_2',
    title: '上四天休两天',
    subtitle: '做四休二',
    aliases: ['做四休二', '上四休二'],
    group: '常白',
    classes: [_d12, _rest],
    cycle: [0, 0, 0, 0, 1, 1],
  ),
  const ShiftTemplate(
    id: 'work_6_rest_1',
    title: '上六天休一天',
    subtitle: '做六休一',
    aliases: ['做六休一', '上六休一', '单休'],
    group: '常白',
    classes: [_office, _restGrey],
    cycle: [0, 0, 0, 0, 0, 0, 1],
  ),
];

ShiftTemplate? findTemplate(String id) {
  for (final t in shiftTemplates) {
    if (t.id == id) return t;
  }
  return null;
}
```

`shiftTemplates` 声明为 `final` 而非 `const`，但每个 `ShiftTemplate` 都是 `const` 构造：`cycle: [0, 1, 2, 2]` 这类字面量在 const 上下文里会成为 const 列表，赋给 `final List<int> cycle` 合法。

- [ ] **Step 3: 跑测试**

```bash
cd app
../toolchain/flutter/bin/flutter.bat test test/shift_templates_test.dart
```

预期：4 条全绿。

- [ ] **Step 4: 提交**

```bash
git add app/lib/domain/shift_templates.dart app/test/shift_templates_test.dart
git commit -m "feat(schedule): 内置 19 种常见倒班方式模板"
```

---

## Task 4: 「选择你的倒班方式」页

**Files:**
- Create: `app/lib/features/calendar/shift_template_picker_screen.dart`
- Create: `app/test/shift_template_picker_test.dart`（分组覆盖测试，见 Step 3b）
- Modify: `app/lib/core/l10n.dart`
- Modify: `app/lib/features/calendar/schedule_management_screen.dart`（新建入口改为先选模板）
- Modify: `app/lib/features/calendar/calendar_screen.dart`（「切换排班」里的新增入口也要走模板选择，见 Step 3c）

**Interfaces:**
- Consumes: Task 3 的 `shiftTemplates` / `shiftTemplateGroups` / `ShiftTemplate`
- Produces: `class ShiftTemplatePickerScreen extends StatelessWidget`，`Navigator.pop(context, ShiftTemplate?)` 返回选中的模板；用户选「我自己排」时返回 `null`。

- [ ] **Step 1: 加文案**

在 `app/lib/core/l10n.dart` 的排班相关分区追加：

```dart
  // 选择倒班方式
  static String get pickShiftPattern => t('选择你的倒班方式', 'Pick your shift pattern');
  static String get pickShiftPatternHint =>
      t('选一个和你班表最像的，建好之后还能随时改', 'Pick the closest one — you can tweak it anytime');
  static String get searchPattern => t('搜索，如「四班三倒」「上24休48」', 'Search, e.g. "4-crew 3-shift"');
  static String get customPattern => t('我自己排', 'Start from scratch');
  static String get customPatternHint => t('从默认四班两倒开始，边看边改', 'Start from the default and edit as you go');
  static String get noPatternMatch => t('没找到匹配的倒班方式', 'No matching pattern');
  static String get crewsOnDuty => t('每天在岗', 'on duty');
  static String get crewUnit => t('个班组', 'crews');
```

- [ ] **Step 2: 新建 `app/lib/features/calendar/shift_template_picker_screen.dart`**

```dart
import 'package:flutter/material.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../domain/shift_templates.dart';

/// 选择页的返回值。
///
/// 不能只用 `ShiftTemplate?`：那样「我自己排」（null）与「按返回键放弃」
/// （push 也返回 null）无法区分，用户一按返回就会凭空多出一套排班。
class ShiftTemplateChoice {
  const ShiftTemplateChoice.template(ShiftTemplate this.template) : custom = false;
  const ShiftTemplateChoice.custom()
      : template = null,
        custom = true;

  /// 选中的模板；[custom] 为 true 时为 null。
  final ShiftTemplate? template;

  /// 用户选了「我自己排」。
  final bool custom;
}

/// 「选择你的倒班方式」：卡片网格 + 搜索，选中后返回该模板。
///
/// 返回 null 表示用户按返回键放弃，调用方应直接 return。
class ShiftTemplatePickerScreen extends StatefulWidget {
  const ShiftTemplatePickerScreen({super.key});

  @override
  State<ShiftTemplatePickerScreen> createState() =>
      _ShiftTemplatePickerScreenState();
}

class _ShiftTemplatePickerScreenState
    extends State<ShiftTemplatePickerScreen> {
  String _query = '';

  bool _matches(ShiftTemplate t) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return t.title.toLowerCase().contains(q) ||
        t.subtitle.toLowerCase().contains(q) ||
        t.group.toLowerCase().contains(q) ||
        t.aliases.any((a) => a.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final matched =
        shiftTemplates.where(_matches).toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(L10n.pickShiftPattern)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            L10n.pickShiftPatternHint,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: glassInputDecoration(context, L10n.searchPattern),
          ),
          const SizedBox(height: 16),
          ..._buildGrouped(context, matched),
        ],
      ),
    );
  }

  List<Widget> _buildGrouped(BuildContext context, List<ShiftTemplate> matched) {
    final out = <Widget>[];
    for (final group in shiftTemplateGroups) {
      final inGroup = matched.where((t) => t.group == group).toList();
      if (inGroup.isEmpty) continue;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(group,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ));
      for (final t in inGroup) {
        out.add(_templateCard(context, t));
      }
      out.add(const SizedBox(height: 8));
    }
    if (matched.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            L10n.noPatternMatch,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
          ),
        ),
      ));
    }
    out.add(_customCard(context));
    return out;
  }

  /// 一排小色块，就是把周期表画出来；最多画前 14 天，够认出是哪一种。
  Widget _cycleStrip(ShiftTemplate t) {
    const dot = 14.0;
    return SizedBox(
      width: dot * 7 + 12,
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [
          for (final i in t.cycle.take(14))
            Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: Color(t.classes[i].color),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _templateCard(BuildContext context, ShiftTemplate t) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return GlassTile(
      enableBlur: false,
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.zero,
      child: GlassPressable(
        child: InkWell(
          onTap: () =>
              Navigator.of(context).pop(ShiftTemplateChoice.template(t)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cycleStrip(t),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(t.subtitle,
                          style: TextStyle(fontSize: 12, color: muted)),
                      if (t.teamCount > 1) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${L10n.crewsOnDuty} ${t.workingTeamsPerDay} '
                          '${L10n.crewUnit}',
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_outlined, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _customCard(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GlassTile(
      enableBlur: false,
      padding: EdgeInsets.zero,
      child: GlassPressable(
        child: InkWell(
          onTap: () => Navigator.of(context).pop(const ShiftTemplateChoice.custom()),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.tune_outlined, color: primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(L10n.customPattern,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        L10n.customPatternHint,
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_outlined, color: primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

已核实的组件 API（照抄即可，别改签名）：

- `glassInputDecoration(BuildContext context, String label, {bool isDense = false})`
- `GlassTile({required Widget child, BorderRadius borderRadius, EdgeInsetsGeometry? padding, EdgeInsetsGeometry? margin, bool enableBlur = true, VoidCallback? onTap})`
- `GlassPressable({required Widget child, double pressedScale = 0.97})` —— 只做按压缩放与波纹承载，**不含 onTap**，点击要自己套 `InkWell` / `ListTile(onTap:)`
- `GlassDeleteButton({required VoidCallback? onPressed, String? tooltip})`
- `AppTokens.radiusS = 12` / `radiusM = 16` / `radiusL = 22`

- [ ] **Step 3: 改 `app/lib/features/calendar/schedule_management_screen.dart` 的新建入口**

`_addSchedule` 替换为：

```dart
  Future<void> _addSchedule(BuildContext context, WidgetRef ref) async {
    final choice = await Navigator.of(context).push<ShiftTemplateChoice>(
      MaterialPageRoute(builder: (_) => const ShiftTemplatePickerScreen()),
    );
    // 按返回键放弃：既不建方案，也不进编辑器。
    if (choice == null || !context.mounted) return;

    final d = defaultSchedule();
    final picked = choice.template;
    final classes = picked?.classes ?? d.classes;
    final cycle = picked?.cycle ?? d.cycle;

    final id = await ref.read(appRepositoryProvider).saveSchedule(
          name: picked?.subtitle ?? L10n.newSchedule,
          anchorDate: dateOnly(DateTime.now()),
          classes: classes,
          cycle: cycle,
          makeCurrent: false,
          teamCount: picked?.teamCount ?? d.teamCount,
          teamNames: d.teamNames,
          ourTeamIndex: 0,
          teamOffsets: picked?.teamOffsets ?? d.teamOffsets,
        );
    if (context.mounted) await _openEditor(context, ref, id);
  }
```

新增 import：`import 'shift_template_picker_screen.dart';`

（**不要**再 import `domain/shift_templates.dart`：改用 `ShiftTemplateChoice` 之后，`_addSchedule` 里不再出现 `ShiftTemplate` 这个名字，加了会触发 `unused_import`。`defaultSchedule()` 来自已在 import 列表里的 `domain/shift_rotation.dart`。）

> 「我自己排」（`ShiftTemplateChoice.custom()`）沿用默认四班两倒起步——比给一张空白表更友好。
> **不要把「我自己排」实现成 `pop(null)`**：那和按返回键无法区分，用户一按返回就会凭空多出一套排班。

- [ ] **Step 3b: 补一个分组覆盖测试**

选择页按 `shiftTemplateGroups` 分组渲染，某个模板的 `group` 字符串若与分组列表对不上就会**静默消失**——而「让用户找到自己的班表」正是这个功能的核心。新建 `app/test/shift_template_picker_test.dart`，双向断言：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';

void main() {
  test('每个模板的分组都在展示分组列表里，且每个分组都有模板', () {
    for (final t in shiftTemplates) {
      expect(shiftTemplateGroups, contains(t.group),
          reason: '模板 ${t.id} 的分组「${t.group}」不在 shiftTemplateGroups 里，会被界面静默丢弃');
    }
    for (final g in shiftTemplateGroups) {
      expect(shiftTemplates.where((t) => t.group == g), isNotEmpty,
          reason: '分组「$g」下没有任何模板，会在界面上留下一个空标题');
    }
  });
}
```

- [ ] **Step 3c: 「切换排班」里的新增入口也要走模板选择**

**这是最容易漏的一步。** 全应用有**两条**新建排班的路径：

1. 我的 → 排班管理 → 新增排班（Step 3 已处理）
2. 日历 → 右上角「切换排班」→ 新增排班（`calendar_screen.dart` 的切换弹层里）

第二条如果还在直接 `saveSchedule(defaultSchedule())`，那么从日历进来的用户**永远看不到模板库**——而模板正是这次改版的核心卖点。两条路径必须共用同一段逻辑。

在 `shift_template_picker_screen.dart` 里加一个顶层函数，两个调用点都用它：

```dart
/// 弹出「选择你的倒班方式」，按选择建出一套方案并返回新方案 id。
/// 用户按返回键放弃时返回 null（不建方案）。
Future<int?> createScheduleFromTemplatePicker(
  BuildContext context,
  WidgetRef ref, {
  required bool makeCurrent,
}) async {
  final choice = await Navigator.of(context).push<ShiftTemplateChoice>(
    MaterialPageRoute(builder: (_) => const ShiftTemplatePickerScreen()),
  );
  // 按返回键放弃：不建方案
  if (choice == null || !context.mounted) return null;

  final d = defaultSchedule();
  final picked = choice.template;
  return ref.read(appRepositoryProvider).saveSchedule(
        name: picked?.subtitle ?? L10n.newSchedule,
        anchorDate: dateOnly(DateTime.now()),
        classes: picked?.classes ?? d.classes,
        cycle: picked?.cycle ?? d.cycle,
        makeCurrent: makeCurrent,
        teamCount: picked?.teamCount ?? d.teamCount,
        teamNames: d.teamNames,
        ourTeamIndex: 0,
        teamOffsets: picked?.teamOffsets ?? d.teamOffsets,
      );
}
```

然后：
- `schedule_management_screen.dart` 的 `_addSchedule` 改为调它（`makeCurrent: false`），拿到 id 后 `_openEditor(context, ref, id)`。
- `calendar_screen.dart` 切换弹层里的「新增排班」也改为调它（`makeCurrent: true`，因为用户本来就在切换排班），拿到 id 后 `Navigator.pop(context)` 关闭弹层，再用**带 `scheduleId`** 的方式打开编辑器（`ScheduleEditorScreen(scheduleId: id)`）——不要再像现在这样传空 id 去编辑「当前方案」，那是靠刚保存时 `makeCurrent: true` 兜住的隐式约定。

- [ ] **Step 4: 检查 + 冒烟**

```bash
cd app
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat test
```

**环境限制（已实测）**：本机没有 Android 设备、没有 Visual Studio 工具链（`flutter run -d windows` 会报 "Unable to find suitable Visual Studio toolchain"），web 又被 `flutter_local_notifications` + `sqlite3_flutter_libs` 挡住 —— **没有可运行目标，GUI 手工验证在本环境做不到**。GUI 行为改由 widget 测试覆盖，最终的真机确认由用户装 APK 完成（见 Task 8）。报告里必须如实写明「未运行应用」，不得声称验证过。

预期：analyze 0 error / 0 warning，test 全绿。

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/l10n.dart app/lib/features/calendar/shift_template_picker_screen.dart app/lib/features/calendar/schedule_management_screen.dart
git commit -m "feat(schedule): 新建排班改为先选倒班方式"
```

---

## Task 5: 排班编辑器改版（班次定义 + 周期表 + 班组起始日）

**Files:**
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`（重写）
- Modify: `app/lib/core/l10n.dart`

**Interfaces:**
- Consumes: Task 1 的 `ShiftClass` / `ShiftSchedule`、Task 2 的 `saveSchedule`
- Produces: 无对外新接口（界面层）

- [ ] **Step 1: 加文案**

```dart
  // 编辑器
  static String get shiftClasses => t('班次设置', 'Shift types');
  static String get shiftClassesHint =>
      t('先把你的班次各定义一次，下面周期里直接引用', 'Define each shift once, then reuse it in the cycle');
  static String get addShiftClass => t('添加班次', 'Add shift');
  static String get deleteShiftClassInUse =>
      t('周期里还有 {n} 天在用这个班次，先把它们改成别的', 'Still used by {n} day(s) in the cycle');
  static String get cycleSection => t('周期设置', 'Cycle');
  static String get cycleLengthUnit => t('天', 'days');
  static String get myCycleStart => t('我这组从这个周期开始', 'My crew starts this cycle on');
  static String get crewCycleStart => t('周期起始日', 'Cycle start date');
  static String get abbrLabel => t('简称', 'Short');
  static String get crewSettingsOptional =>
      t('班组设置（可选，用于查看其他班组）', 'Crews (optional, to see other crews)');
  static String get shiftInUseHint =>
      t('周期里引用它的天数会一并改成休班', 'Days using it will become rest days');

  /// 「开始 – 结束」；跨午夜时中文插「次日」、英文在括号里注明。
  ///
  /// 中英两种语序不同，所以整串交给 [t] 而不是拼接前缀 ——
  /// 直接拼 `'次日'` 会在英文界面下露出中文。
  static String timeRange(String start, String end, bool crossesMidnight) =>
      crossesMidnight
          ? t('$start – 次日$end', '$start – $end (next day)')
          : '$start – $end';
```

`L10n` 里目前没有带参数的写法，用 `.replaceAll('{n}', '$n')` 处理 `deleteShiftClassInUse`。

- [ ] **Step 2: 重写 `schedule_editor_screen.dart`**

界面结构（用现有玻璃组件）：

1. **排班名称**：`GlassTile` + `TextField`（沿用现有 `glassInputDecoration`）。
2. **我的班组起始日**：`GlassTile` + `ListTile`，标题 `L10n.myCycleStart`，副标题 `L10n.yearMonthDay(_myCrewStart)`，点击 `showGlassDatePicker` 且回调走 `_setMyCycleStart`。这是整页最重要的一项，放在名称正下方。

   ⚠️ **副标题必须读 `_myCrewStart`（= `_crewStartDate(_ourTeamIndex)`），不能读 `_anchor`。** `_anchor` 只在我这一组的偏移恰好为 0 时才等于我的起始日，而这个不变量没有任何东西在维持：在班组区点「设为我」改掉 `_ourTeamIndex` 之后它就不成立了，届时顶部与班组行会显示两个不同的日期。派生显示值让两条路径天然一致。
3. **班次设置**：`GlassTile` 包一个列表，每条一行：
   - 左：颜色圆点（点开 `_palette` 选色）
   - 中：`TextField` 名称（`isDense`）
   - 中右：`TextField` 简称（宽度 44，`maxLength: 2`）
   - 右侧：`GlassSwitch`（是否休息）
   - 展开区：非休息时给「开始 / 结束时间」两个 `_timeTile`（复用现有实现）+ 联动闹钟开关与闹钟时间
   - 行尾：删除按钮 `GlassDeleteButton`
   - 底部：`FilledButton.icon`「添加班次」
   - 删除时若 `cycle.contains(index)` 则 `showGlassSnack` 提示 `L10n.deleteShiftClassInUse.replaceAll('{n}', '$count')` 并中止。
4. **周期设置**：`GlassTile`，顶部一行 `IconButton(−)` + `Text('${_cycle.length} ${L10n.cycleLengthUnit}')` + `IconButton(+)`；下面 `_cycle.length` 行：
   `第 N 天 ｜ DropdownButton<int>（选项 = `_classes` 的名字）｜ 时间（只读文本，`_rangeText(c)`）`
   - 周期上限 60、下限 1，到界时按钮置灰。
   - 变长：新位置默认取 `_cycle.last`；变短：直接截断。
   - 行尾给一个「休班」快捷下拉项？不需要——休班本身就是 `_classes` 里的一项。
5. **班组设置**：默认折叠（用一个 `ExpansionTile` 风格的 `GlassTile` + 自管 `_crewExpanded` 布尔）。展开后：班组数 `−/＋`（1–8）、每行「名称输入 + 周期起始日（`showGlassDatePicker`）+ 设为我」。
6. **跟随法定节假日**：沿用现有 `_followHolidayCard`，打开时清空 `_classes` 与 `_cycle`。

关键的状态与换算（整份替换 `_ScheduleEditorScreenState` 的字段与转换函数）：

```dart
  List<ShiftClass> _classes = [];
  List<int> _cycle = [];

  /// 某班组的「周期起始日」= 基准日 − teamOffsets[它] 天。
  DateTime _crewStartDate(int i) {
    final off = i < _teamOffsets.length ? _teamOffsets[i] : i;
    return dateOnly(_anchor).subtract(Duration(days: off));
  }

  /// 用户把某班组的起始日改成 [date] 后，回填 teamOffsets。
  ///
  /// 改的是「我这一组」时必须走 [_setMyCycleStart] 的重锚定语义而不是只改
  /// 单个偏移 —— 只改一个偏移会让我这组与其他班组的**相对错位**跟着变，
  /// 等于把整个班表结构弄坏了。
  void _setCrewStartDate(int i, DateTime date) {
    if (i == _ourTeamIndex) {
      _setMyCycleStart(date);
      return;
    }
    final off = daysBetween(dateOnly(date), dateOnly(_anchor));
    setState(() => _teamOffsets[i] = off);
  }

  /// 我的班组的周期起始日（顶部卡片的显示值）。
  DateTime get _myCrewStart => _crewStartDate(_ourTeamIndex);

  /// 把「我的班组」的起始日设为 [date]：重新锚定整个轮转。
  ///
  /// 目标是让 `shiftOn(date) == classes[cycle[0]]`，同时保持各班组之间的
  /// 相对错位不变。做法是基准日改为 [date]、每个班组的偏移减去「我这一组」
  /// 的基线偏移（这样 `teamOffsets[ourTeamIndex]` 归零，基准日即我的周期第 1 天）。
  ///
  /// 注意：**不要**改成「减去基准日的位移量」——那会让
  /// `daysBetween(newAnchor, d) + (offset − shift)` 恰好抵消掉，
  /// 用户拖完日期选择器后整个班表一个字都不变。
  void _setMyCycleStart(DateTime date) {
    final base = _ourTeamIndex < _teamOffsets.length
        ? _teamOffsets[_ourTeamIndex]
        : 0;
    setState(() {
      _anchor = dateOnly(date);
      for (var i = 0; i < _teamOffsets.length; i++) {
        _teamOffsets[i] = _teamOffsets[i] - base;
      }
    });
  }
```

`_save`：

```dart
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final name = _name.trim().isEmpty ? L10n.schedule : _name.trim();
      final anchor = dateOnly(_anchor);
      await ref.read(appRepositoryProvider).saveSchedule(
            scheduleId: widget.scheduleId ?? ref.read(activeScheduleProvider).valueOrNull?.schedule.id,
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
      final repo = ref.read(appRepositoryProvider);
      await AlarmService.reschedule(
        ShiftSchedule(
          name: name,
          anchorDate: anchor,
          classes: _classes,
          cycle: _cycle,
          teamCount: _teamCount,
          teamNames: _teamNames,
          ourTeamIndex: _ourTeamIndex,
          teamOffsets: _teamOffsets,
        ),
        await repo.listCustomAlarms(),
        overrides: await repo.listShiftAlarmOverrides(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
```

周期长度步进器（照抄，上下限就靠这里的 `onPressed: null` 置灰）：

```dart
  Widget _cycleStepper(BuildContext context) {
    return Row(
      children: [
        Text(L10n.cycleSection,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline_outlined),
          onPressed:
              _cycle.length > 1 ? () => _setCycleLength(_cycle.length - 1) : null,
        ),
        Text('${_cycle.length}${L10n.cycleLengthUnit}'),
        IconButton(
          icon: const Icon(Icons.add_circle_outline_outlined),
          onPressed:
              _cycle.length < 60 ? () => _setCycleLength(_cycle.length + 1) : null,
        ),
      ],
    );
  }

  /// 变长时新的一天默认沿用最后一天的班次；变短直接截断。
  void _setCycleLength(int n) {
    setState(() {
      if (n > _cycle.length) {
        final tail = _cycle.isEmpty ? 0 : _cycle.last;
        while (_cycle.length < n) {
          _cycle.add(tail);
        }
      } else {
        _cycle.removeRange(n, _cycle.length);
      }
    });
  }
```

周期里的第 N 天（下拉引用班次定义，时间是只读文本）：

```dart
  Widget _cycleRow(BuildContext context, int index) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(L10n.dayN(index + 1),
                style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppTokens.radiusS),
              ),
              child: DropdownButton<int>(
                value: _cycle[index],
                isExpanded: true,
                isDense: true,
                underline: const SizedBox(),
                borderRadius: BorderRadius.circular(AppTokens.radiusS),
                dropdownColor: Theme.of(context).colorScheme.surface,
                items: _classes.asMap().entries.map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: Color(e.value.color),
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(e.value.name,
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    )).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _cycle[index] = v);
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _rangeText(_classes[_cycle[index]]),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
```

删除班次定义时的引用保护：

```dart
  void _deleteClass(int index) {
    final used = _cycle.where((c) => c == index).length;
    if (used > 0) {
      showGlassSnack(
        context,
        L10n.deleteShiftClassInUse.replaceAll('{n}', '$used'),
        icon: Icons.info_outline,
      );
      return;
    }
    setState(() {
      _classes.removeAt(index);
      // 删掉一个定义后，周期里所有比它大的下标整体前移一位
      for (var i = 0; i < _cycle.length; i++) {
        if (_cycle[i] > index) _cycle[i]--;
      }
    });
  }
```

周期行右侧的只读时间用 Task 1 已有的 `formatClock`（`domain/shift_rotation.dart` 顶层函数）：

```dart
  /// 周期行右侧的只读时间，与日历上的显示规则一致。
  String _rangeText(ShiftClass c) {
    if (c.isRest || c.startMinute == null || c.endMinute == null) {
      return L10n.rest;
    }
    var e = c.endMinute!;
    final nextDay = e > 1440 || e < c.startMinute!;
    if (e > 1440) e -= 1440;
    return L10n.timeRange(
        formatClock(c.startMinute!), formatClock(e), nextDay);
  }
```

（`dateOnly`、`daysBetween`、`formatClock` 都已在 `shift_rotation.dart` 中，编辑器直接 import 该文件即可。）

- [ ] **Step 3: 检查**

```bash
cd app
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat run -d windows
```

手工验证：
- 用「白白夜夜休休」模板新建 → 周期显示 6 天、引用 3 个班次。
- 把周期改成 12 天 → 多出的 6 天默认引用最后一个班次。
- 改「白班」的时间 → 周期里所有白班行的时间同步变。
- 试着删「白班」→ 被拦下并提示还有 N 天在用。
- 改「我这组从这个周期开始」→ 保存后日历整体平移。
- 打开「跟随法定节假日」→ 周期与班次清空。

- [ ] **Step 4: 提交**

```bash
git add app/lib/features/calendar/schedule_editor_screen.dart app/lib/core/l10n.dart
git commit -m "feat(schedule): 编辑器改为班次定义 + 周期表 + 班组起始日"
```

---

## Task 6: 编辑器实时预览条

**Files:**
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`
- Modify: `app/lib/core/l10n.dart`

**Interfaces:**
- Consumes: Task 5 的编辑器状态（`_classes` / `_cycle` / `_anchor` / `_teamOffsets` / `_ourTeamIndex`）
- Produces: `Widget _previewStrip(BuildContext)`（私有）

- [ ] **Step 1: 加文案**

```dart
  static String get previewNext14 => t('未来 14 天', 'Next 14 days');
```

- [ ] **Step 2: 实现预览条**

在编辑器 `ListView` 最顶部（名称卡之前）插入 `_previewStrip(context)`：

```dart
  /// 未来 14 天预览：改任何设置都能立刻看出对不对。
  Widget _previewStrip(BuildContext context) {
    final schedule = ShiftSchedule(
      name: _name,
      anchorDate: dateOnly(_anchor),
      classes: _classes,
      cycle: _cycle,
      teamCount: _teamCount,
      teamNames: _teamNames,
      ourTeamIndex: _ourTeamIndex,
      teamOffsets: _teamOffsets,
    );
    final today = dateOnly(DateTime.now());
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return GlassTile(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L10n.previewNext14,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 14,
              itemBuilder: (context, i) {
                final date = today.add(Duration(days: i));
                final s = schedule.shiftOn(date);
                final color =
                    s == null ? muted : Color(s.color);
                return Container(
                  width: 40,
                  margin: const EdgeInsets.only(right: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${date.month}/${date.day}',
                          style: TextStyle(fontSize: 10, color: muted)),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(AppTokens.radiusS),
                          border: Border.all(color: color.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          s?.shortLabel ?? '—',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: color),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 3: 检查 + 冒烟**

```bash
cd app
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat run -d windows
```

预期：改周期、改班次时间、改起始日时，顶部预览条实时变化；把起始日往后拖一天，整条预览跟着移一位。

- [ ] **Step 4: 提交**

```bash
git add app/lib/features/calendar/schedule_editor_screen.dart app/lib/core/l10n.dart
git commit -m "feat(schedule): 编辑器加未来 14 天实时预览条"
```

---

## Task 7: 日历适配（其他班组色块列表 + 跨午夜提示）

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Modify: `app/lib/core/l10n.dart`

**Interfaces:**
- Consumes: Task 1 的 `shortLabel` / `crossesMidnight`
- Produces: 无对外新接口

- [ ] **Step 1: 加文案**

```dart
  static String get otherCrews => t('其他班组', 'Other crews');
```

（**不要再加 `nextDaySuffix` 之类的「次日」文案 key** —— Task 5 已经加了 `L10n.timeRange(start, end, crossesMidnight)`，它同时管中文的「次日$end」与英文的「$end (next day)」。重复的 key 只会让两处慢慢漂移。）

- [ ] **Step 2: 把 `_otherTeamsText` 换成色块列表**

删除顶层函数 `_otherTeamsText`，在日详情卡片里把原来的：

```dart
            if (schedule != null && schedule.teamCount > 1) ...[
              const SizedBox(height: 8),
              Text(
                _otherTeamsText(schedule, _selected),
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
```

替换为：

```dart
            if (schedule != null && schedule.teamCount > 1) ...[
              const SizedBox(height: 10),
              Text(L10n.otherCrews,
                  style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _otherCrewChips(schedule, _selected),
              ),
            ],
```

并新增：

```dart
  /// 其他班组当天班次：色点 + 组名 + 简称，横向换行，6 个班组也放得下。
  List<Widget> _otherCrewChips(ShiftSchedule schedule, DateTime date) {
    final chips = <Widget>[];
    for (var i = 0; i < schedule.teamCount; i++) {
      if (i == schedule.ourTeamIndex) continue;
      final t = schedule.teamShift(i, date);
      if (t == null) continue;
      final name = i < schedule.teamNames.length
          ? schedule.teamNames[i]
          : '${i + 1}班';
      chips.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Color(t.color).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppTokens.radiusS),
          border: Border.all(color: Color(t.color).withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: Color(t.color), shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text('$name ${t.shortLabel}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(t.color))),
          ],
        ),
      ));
    }
    return chips;
  }
```

- [ ] **Step 3: 时间显示改走 L10n**

`calendar_screen.dart` 的 `_timeRange` 目前把「次日」硬编码在字符串拼接里（改动前既有），英文界面下会露出中文。Task 5 已经加了 `L10n.timeRange`，这里改成复用它：

```dart
String _timeRange(ShiftClass t) {
  var e = t.endMinute!;
  final nextDay = e > 1440 || e < t.startMinute!;
  if (e > 1440) e -= 1440;
  return L10n.timeRange(formatClock(t.startMinute!), formatClock(e), nextDay);
}
```

改完后 `grep -n "次日" app/lib/features/` 应该只剩编辑器/日历里那两条注释之外的零处硬编码（`L10n` 里的那份除外）。

- [ ] **Step 4: 检查 + 冒烟**

```bash
cd app
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat run -d windows
```

手工验证：用「六班三倒」模板新建（6 个班组），点开某天 → 其他班组显示为 5 个色块标签且不溢出；用「上 24 休 48」模板 → 值班当天显示「08:00 – 次日08:00」。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/lib/core/l10n.dart
git commit -m "feat(calendar): 其他班组改为色块列表，补齐跨午夜提示"
```

---

## Task 8: 版本号、文档与发布说明

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/core/app_info.dart`
- Modify: `PRODUCT_SPEC.md`
- Modify: `BUILD.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: 前 7 个任务的全部成果
- Produces: 无（收尾）

- [ ] **Step 1: 升版本号**

`app/pubspec.yaml`：`version: 0.5.0+70` → `version: 0.6.0+71`
`app/lib/core/app_info.dart`：`appVersion = '0.5.0'` → `'0.6.0'`

同时更新 `AGENTS.md`：版本历史那行追加 `→ **0.6.0(+71)**（正式稳定版 · 周期排班编辑器）`，并把它里面的 schemaVersion（5 → 6）与数据表清单（`shift_type_rows` → `shift_class_rows` + `shift_cycle_rows`）一并改到与代码一致。

- [ ] **Step 2: 更新 `PRODUCT_SPEC.md`**

- §2「排班日历」第 1 条改为：**两层轮换模型**——班次定义（一个班次只定义一次）+ 周期序列（长度即周期，元素引用班次定义），周期长度 1–60 天；班组相位由「每班组一个周期起始日」表达。
- 新增第 7、8 条：**内置 19 种常见倒班方式模板**（新建排班先选倒班方式）、**编辑器未来 14 天实时预览**。
- §3「班次模型」默认配置表里补上格子简称 `abbr`，并说明 `endMinute` 允许超过 1439（24 小时值班 = 480→1920）。
- §4 数据模型表：`ShiftTypeRows` 一行拆成 `ShiftClassRows`（班次定义）与 `ShiftCycleRows`（周期序列）两行；`schemaVersion` 5 → 6。
- 「明确不做」清单里补上：**日历上直接改某一天（换班/请假覆盖）**、2-2-3 Pitman 型「固定日班组/夜班组」模式、周期中间插入删除某一天。

- [ ] **Step 3: 更新 `BUILD.md` 与 `README.md`**

- `BUILD.md`「首次运行注意」段：说明入口是 **我的 → 排班管理 → 新增排班**（不是「日历 → 排班管理」——日历里没有排班管理入口），选中倒班方式后进入编辑器。
- `README.md` 功能清单里加上两条：内置 19 种倒班方式模板、「周期表可自由编辑」；新增排班的入口描述同样写成 **我的 → 排班管理 → 新增排班**，与 `BUILD.md` 和 `L10n` 里的应用内引导文案保持一致。
- 若仓库里还有别处写着「日历 → 排班管理」或「新建排班」这类与实现不符的导航描述，一并按实现改掉（按钮文案是 `L10n.addSchedule`，即「新增排班」）。

- [ ] **Step 4: 写发布说明**

按项目约定写到 `tools/gh/release-notes-v0.6.0.md`。**措辞红线**（来自 Global Constraints）：只写本应用提供了什么，不得出现「参考 / 借鉴 / 对照 / 类似某 App」，不点名任何第三方应用。示例骨架：

```markdown
## 倒班助手 Pro v0.6.0

### 新增
- **19 种倒班方式模板**：白夜休休、白白夜夜休休、四班三倒、五班三倒、六班三倒、五班四倒、六班四倒、上 24 休 24/48/72、长白班、做一休一/二/四、做六休一、大小周、DuPont 等，新建排班时选一个最像的即可起步。
- **周期表可自由编辑**：周期长度 1–60 天，每一天从已定义的班次里选一个。
- **班次定义只需配一次**：时间、颜色、联动闹钟挂在班次上，周期里所有同名单日自动同步。
- **班组用「周期起始日」表达**：每班组选一个日期，那天它从周期第 1 天开始。
- **编辑器实时预览**：未来 14 天的班次随手改随手看。

### 优化
- 日历格子简称改为班次自带，冷门班次名也能正确显示。
- 查看其他班组改为色块列表，6 个班组也不挤。
- 24 小时值班班次正确显示为「08:00 – 次日 08:00」。
```

- [ ] **Step 5: 全量验收**

```bash
cd app
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat test
../toolchain/flutter/bin/flutter.bat build apk --release
```

预期：0 error / 0 warning，全部测试通过，APK 产出到 `dist/`。

**这一步是本计划唯一的真机入口**：本环境没有可运行目标（无 Android 设备、无 VS 工具链、web 被插件挡住），所有 GUI 行为都没有被任何 agent 实际看过。`build apk` 至少能在编译与打包层面兜住 Android 侧的问题，真正的界面确认由用户安装 APK 完成——所以发布说明里要写清楚这次发的是**需要用户实测**的版本。

打包后在报告与最终交付里如实写明：GUI 未经 agent 实际运行验证。

- [ ] **Step 6: 提交**

```bash
git add app/pubspec.yaml app/lib/core/app_info.dart PRODUCT_SPEC.md BUILD.md README.md tools/gh/release-notes-v0.6.0.md
git commit -m "docs: v0.6.0 版本号、产品规格与发布说明"
```

---

## 验收清单（对 spec §11）

- [ ] `flutter analyze` 0 error / 0 warning
- [ ] `flutter test` 全绿，且下列测试存在并通过：
  - [ ] 迁移等价性（Task 2，含重复班次合并、空方案、旧表已删三条）
  - [ ] 长周期取模 14 / 28 天（Task 1 `白白夜夜休休` 用例 + Task 3 `dupont` 自检）
  - [ ] 班组起始日换算（Task 1 公式未变，Task 5 的 `_crewStartDate` / `_setMyCycleStart` 互逆）
  - [ ] 模板自检（Task 3，含每天上班组数恒定）
  - [ ] 周期边界：1 天 / 60 天 / 空（Task 5 步进器上下限 + Task 2 空方案用例）
- [ ] 手工验收：从模板新建「白白夜夜休休」与「DuPont」，改起始日为今天，日历上今天/明天/后天的班次与周期表一致；联动闹钟按新周期排定
