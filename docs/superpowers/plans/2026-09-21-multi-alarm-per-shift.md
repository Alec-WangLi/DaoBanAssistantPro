# 每个班次自定义 N 个闹钟 · 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一个班次能挂 0..6 个联动闹钟（各带可选名字），「前一天 / 当天」自动推断正确，六个消费方与老数据迁移全部到位。

**Architecture:** 把 `ShiftClass` 上「一个钟点」换成有序列表 `List<ShiftAlarm>`（新表 `shift_class_alarms` 落库，`alarmEnabled` 留作总开关）。落哪天由一条纯函数按「钟点是否落在值班窗口内」判定；原生 id 用 `序号 × 60 + 天数偏移`（所以上限是 6）。界面按现有配方扩展：编辑器的班次卡片里长出一串闹钟行，闹钟页与日历信息卡各自显示多条。

**Tech Stack:** Flutter 3.47 / Dart 3.13 · Drift 2.31（SQLite，schemaVersion 9 → 10）· flutter_riverpod · flutter_local_notifications（原生 `setAlarmClock` 走 MethodChannel）

**Spec:** `docs/superpowers/specs/2026-09-21-multi-alarm-per-shift-design.md`（本文按它逐节落地；两边冲突以 spec 为准，改 spec 要单独提）

## Global Constraints

- **不要跑 `dart format`**：工具链是新的 tall style 格式化器，一跑就把整个文件重排、制造几百行无关 diff。只跑 `flutter analyze`。
- 命令一律带上工具链环境（缺了会去 `~/.gradle` 下载到超时）：
  ```bash
  export JAVA_HOME=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/jdk
  export ANDROID_HOME=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/android-sdk
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export GRADLE_USER_HOME=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/gradle-home
  export PUB_CACHE=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/pub-cache
  export FLUTTER_ROOT=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter
  export PATH="$FLUTTER_ROOT/bin:$JAVA_HOME/bin:$PATH"
  ```
- 验收线：`flutter analyze` **0 error / 0 warning**；`flutter test` **全绿且只增不减**（当前 297 条）。
- **改动数据表后必须**：`cd app && dart run build_runner build --delete-conflicting-outputs`。
- **中间任务不发布、不动版本号**。版本号与 `release.ps1` 只在 Task 9 收尾那一步做；**`X.Y` 由用户决定，AI 只能改末位 `Z` 与 `build`**。
- **上限 6 是硬约束**，不是产品口味：原生 id 是 `序号 × 60 + 天数偏移`，Kotlin 侧 `cancelAllNativeAlarms` 扫 `0..400`（`MainActivity.kt:550`），而那个 60 就是 `AlarmService.reschedule` 的 `days` 缺省值。两者必须同源，改一个就得改另一个。
- 用户可见文案一律走 `L10n`（`t(zh, en)`），`lib/` 里不许出现裸中文串；**新界面一律进视觉工装屏单**（`app/tool/visual/visual_screens.dart`）。
- 数据迁移必须**向后兼容老数据**：老库（≤v9）与老模板 JSON（用户已存的「我的模板」）都要照常能读。

## Review Focus

按 spec 推出来、但最容易让**用户**踩到的五类输入/状态 —— 每条都在它所属任务的测试里钉住：

1. **老库里「开关关着但有时间」的班次**：升级后必须还是「开关关着 + 时间还在」。迁移只挑 `alarm_enabled = 1` 的行就等于**把用户配好的时间吞了**，而界面上看不出来。（Task 3）
2. **重排闹钟不能改「序号」**：原生 id 含序号，同一份数据重排两次必须得到同一批 id —— 否则每次打开 App 都换一批号，用户设过的响铃记录会错位。（Task 5）
3. **到上限之后再点「添加闹钟」**：第 7 个加不上是设计，但界面**不能装作还能加** —— 按钮要消失并给一行说明，而不是点了没反应。（Task 6）
4. **「前一天」标记不能丢**：零点班的 23:00 不标「前一天」就会被读成班次当天（v0.8.9 的教训）。多条闹钟混排时，每条各自标自己的。（Task 6 / Task 7）
5. **闹钟名字的边界**：名字为空 / 只填空格 / 前后带空格 / 很长 / 含 emoji 时，响铃标题与列表行都不能出现「白班 · 」「白班 · 　　午 休」这类成品，也不能溢出。（Task 6 / Task 5）

---

### Task 1: 领域换成列表 + 全部调用点机械改到位（行为不变）

这一轮**只换形状，不改行为**：一个班次还是只有一个闹钟在起作用，规则也照旧。所有消费方先按「取列表里的第 0 条 / 写回一条」改到位，让整棵树编译得过、测试全绿；功能在后面的任务里逐个长出来。这么切是因为 `ShiftClass.alarmMinute` 是个被 12 处引用的字段，换它的那一刻必须所有引用一起动，否则树是编译不过的。

**Files:**
- Modify: `app/lib/domain/shift_rotation.dart`（值类型 + 字段 + 规则函数 + 上限常量）
- Modify: `app/lib/domain/shift_templates.dart`（`ShiftClassProto` 跟着换）
- Modify: `app/lib/data/seed.dart`、`app/lib/data/app_database.dart`（**只改 SQL/Companion 那一层还不用动**：本任务库表仍是 `alarm_minute`，见 Step 6）
- Modify: `app/lib/data/app_repository.dart`（`ShiftClassRowX.toDomain`、`saveSchedule` 两个写点）
- Modify: `app/lib/features/alarm/alarm_service.dart`（`shiftAlarmFireAt` 签名 + `planShiftAlarms` 逐闹钟 + 响铃标题）
- Modify: `app/lib/features/alarm/alarm_screen.dart`（读第一条）
- Modify: `app/lib/features/calendar/calendar_screen.dart`（`_alarmText` 读第一条）
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`（开关 + 一个时间块编辑 `alarms[0]`）
- Modify: `app/lib/domain/schedule_template.dart`（编解码仍写旧的两个字段，取/给第一条）
- Modify: `app/test/shift_rotation_test.dart`、`app/test/shift_alarm_decision_test.dart`、`app/test/migration_v8_to_v9_test.dart`、`app/test/schedule_template_test.dart`（构造点换字段）

**Interfaces:**
- Produces（后面每个任务都按这套名字写）：
  - `class ShiftAlarm { const ShiftAlarm({required int minute, String? label}); final int minute; final String? label; }`（含 `==` / `hashCode` / `toString`）
  - `const int maxAlarmsPerShift = 6;`
  - `ShiftClass.alarms` → `List<ShiftAlarm>`（不可变，缺省 `const []`）；`ShiftClass.alarmEnabled` 保留
  - `bool alarmFallsOnPreviousDay(ShiftClass shift, ShiftAlarm alarm)`
  - `DateTime shiftAlarmFireAt(DateTime date, ShiftClass shift, ShiftAlarm alarm)`
  - `class ShiftAlarmPlan { final int offset; final ShiftClass shift; final ShiftAlarm alarm; final int alarmIndex; final DateTime fireAt; }`
  - `List<ShiftAlarmPlan> planShiftAlarms(ShiftSchedule schedule, {required DateTime from, required int days, Map<int, bool> overrides})`（签名不变，语义变成「每个闹钟一条」）
- Consumes：无（这是第一个任务）

- [ ] **Step 1: 先写领域测试（会红）**

追加到 `app/test/shift_rotation_test.dart` 末尾（`main()` 里）：

```dart
  group('ShiftAlarm：班次上的多个闹钟', () {
    const shift = ShiftClass(
      name: '白班',
      startMinute: 8 * 60,
      endMinute: 20 * 60,
      alarmEnabled: true,
      alarms: [
        ShiftAlarm(minute: 6 * 60 + 30, label: '起床'),
        ShiftAlarm(minute: 12 * 60 + 30, label: '午休'),
      ],
    );

    test('alarms 默认空表，且带着 label 一起比相等', () {
      const bare = ShiftClass(name: '休班', isRest: true);
      expect(bare.alarms, isEmpty);
      expect(shift.alarms, hasLength(2));
      expect(shift.alarms.first.label, '起床');
      expect(
          shift.alarms.first,
          const ShiftAlarm(minute: 6 * 60 + 30, label: '起床'));
      expect(shift.alarms.first == const ShiftAlarm(minute: 6 * 60 + 30),
          isFalse,
          reason: '名字不同就是不同的闹钟（响铃标题与列表行都靠它）');
    });

    test('闹钟列表参与 ShiftClass 的相等判定', () {
      final same = ShiftClass(
        name: shift.name,
        startMinute: shift.startMinute,
        endMinute: shift.endMinute,
        alarmEnabled: true,
        alarms: const [
          ShiftAlarm(minute: 6 * 60 + 30, label: '起床'),
          ShiftAlarm(minute: 12 * 60 + 30, label: '午休'),
        ],
      );
      final other = shift.copyWith(alarms: const [ShiftAlarm(minute: 6 * 60 + 30)]);
      expect(same, equals(shift));
      expect(same.hashCode, shift.hashCode);
      expect(other == shift, isFalse, reason: '少一个闹钟就不是同一个班次定义');
    });
  });
```

- [ ] **Step 2: 跑一遍，确认红**

```bash
cd app && flutter test test/shift_rotation_test.dart
```
Expected: 编译失败 —— `ShiftClass` 没有 `alarms` 具名参数 / `copyWith` 不认 `alarms`。

- [ ] **Step 3: 领域实现**

`app/lib/domain/shift_rotation.dart`，在 `formatClock` 之后加：

```dart
/// 一个班次上的**一条**联动闹钟。
///
/// [minute] 是钟面值（0..1439，分钟自午夜）。[label] 是可选名字（「起床」「午休」），
/// 为空时响铃标题退回「白班提醒」。名字的空白由**输入侧**（编辑器）负责 trim，
/// 值类型本身不做归一化 —— 它是纯数据，跟库里存的一致。
class ShiftAlarm {
  const ShiftAlarm({required this.minute, this.label});

  final int minute;
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is ShiftAlarm && other.minute == minute && other.label == label;

  @override
  int get hashCode => Object.hash(minute, label);

  @override
  String toString() => 'ShiftAlarm($minute${label == null ? '' : ', $label'})';
}

/// 一个班次最多挂几个联动闹钟。
///
/// **不是产品口味，是原生 id 空间的硬上限**：原生 id 是
/// `序号 × 天数窗口 + 天数偏移`（见 `alarm_service.dart` 的 `_shiftDaysHorizon`），
/// Kotlin 侧 `cancelAllNativeAlarms` 扫的是 `0..400`（`MainActivity.kt:550`）。
/// 6 × 60 = 360 ≤ 400 刚好放得下。**改这个数或改天数窗口，必须同时改另一边。**
const int maxAlarmsPerShift = 6;

/// 响铃钟点是否落在上班的**前一天**。
///
/// 判据只有一条：响铃的钟面值晚于上班的钟面值 —— 那个钟点在同一天里只可能排在
/// 上班**之后**（00:00 上班、23:00 响铃 → 当天 23:00 时这个班已经结束 15 小时），
/// 所以它指的必然是前一天晚上那个钟点。
///
/// 上班时间没填（或钟点相同）时返回 false：前者无从判断，后者「不晚于上班时刻的
/// 最近一次该钟点」就是上班那一刻本身。
bool alarmFallsOnPreviousDay(ShiftClass shift, ShiftAlarm alarm) {
  final s = shift.startMinute;
  if (s == null) return false;
  return alarm.minute > s;
}
```

`ShiftClass` 里：删掉 `this.alarmMinute` 参数与 `final int? alarmMinute;` 字段、删掉 `alarmPreviousDay` getter，加：

```dart
    this.alarms = const [],
```

```dart
  /// 这个班次的联动闹钟（有序）。
  ///
  /// **顺序就是原生 id 里的「序号」**（`alarm_service.dart` 的 `_shiftDaysHorizon`）——
  /// 所以重排闹钟会让它们换号，而**重排本身绝不能重新编号**。上限 [maxAlarmsPerShift]。
  final List<ShiftAlarm> alarms;
```

`copyWith` 加 `List<ShiftAlarm>? alarms`（写法 `alarms: alarms ?? this.alarms`），`==` / `hashCode` / `toString` 里把 `alarmMinute` 换成 `alarms`（列表比较手写，本文件**不许引 Flutter 或 package:collection**，它得能直接 `dart test`）：

```dart
/// 两个闹钟列表逐条相等（本文件不引 Flutter，拿不到 `listEquals`）。
bool _sameAlarms(List<ShiftAlarm> a, List<ShiftAlarm> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```
```dart
      _sameAlarms(other.alarms, alarms);
```
```dart
  int get hashCode => Object.hash(
      id, name, abbr, startMinute, endMinute, isRest, color, alarmEnabled,
      Object.hashAll(alarms));
```

`defaultSchedule()` 里两条 `alarmMinute: 7 * 60` / `19 * 60 + 30` 改成：

```dart
        alarms: const [ShiftAlarm(minute: 7 * 60)],
```
```dart
        alarms: const [ShiftAlarm(minute: 19 * 60 + 30)],
```

- [ ] **Step 4: 跑领域测试，绿**

```bash
cd app && flutter test test/shift_rotation_test.dart
```
Expected: PASS（含新加的 group）。此时**整棵树编译不过**（别的文件还在用 `alarmMinute`），下一步一起改。

- [ ] **Step 5: 其余调用点机械改到位（不改行为）**

**`app/lib/domain/shift_templates.dart`**：`ShiftClassProto` 的两个字段 `alarmEnabled` / `alarmMinute` 换成 `this.alarms = const []`，`toClass()` 里传 `alarms: alarms`。然后把 20 个内置模板里每处 `alarmMinute: X` 改成 `alarms: const [ShiftAlarm(minute: X)]`（**只动形状，钟点一个都不许变**，`shift_templates_test.dart` 会盯着）：

```bash
grep -n "alarmMinute" lib/domain/shift_templates.dart
```

**`app/lib/data/seed.dart`**（第 37-38 行）：`alarmMinute: Value(c.alarmMinute)` 这一行删掉，`alarmEnabled: Value(c.alarmEnabled)` 保留 —— 本任务库表还是老形状，落库走 `c.alarms` 的第一条：

```dart
            alarmEnabled: Value(c.alarmEnabled),
            alarmMinute: Value(c.alarms.isEmpty ? null : c.alarms.first.minute),
```

**`app/lib/data/app_repository.dart`**：

`ShiftClassRowX.toDomain()`（第 87-98 行）末两行改成：

```dart
        alarmEnabled: alarmEnabled,
        alarms: alarmMinute == null
            ? const []
            : [ShiftAlarm(minute: alarmMinute!)],
```

`saveSchedule` 的两个写点（第 392-393、407-408 行）同样把 `alarmMinute: Value(c.alarmMinute)` 换成：

```dart
            alarmMinute:
                Value(c.alarms.isEmpty ? null : c.alarms.first.minute),
```
（**注意**：这里对 `addColumn` 之后的库形状是临时的，Task 3 会把这两处换成新表的同步写入。现在只保证编译与行为不变。）

**`app/lib/features/alarm/alarm_service.dart`**：

`shiftAlarmFireAt`（第 73-80 行）改成带 alarm 参数：

```dart
/// 某天某个班次的**某一条**闹钟的响铃时刻。
///
/// 钟点取 [alarm] 的钟面值；[alarmFallsOnPreviousDay] 为真时整体前移一天 ——
/// 规则是「**不晚于上班时刻的最近一次该钟点**」，所以 00:00 上班、23:00 响铃排的是
/// 前一天 23:00（排在班次当天就已经是班后 15 小时了）。
///
/// 日期用 `DateTime(y, m, d - 1)` 重建而不是 `subtract(Duration(days: 1))`：
/// 后者减的是绝对 24 小时，碰上夏令时切换会把钟点也挪掉一小时。
DateTime shiftAlarmFireAt(DateTime date, ShiftClass shift, ShiftAlarm alarm) {
  final clock = alarm.minute;
  return alarmFallsOnPreviousDay(shift, alarm)
      ? DateTime(date.year, date.month, date.day - 1)
          .add(Duration(minutes: clock))
      : DateTime(date.year, date.month, date.day)
          .add(Duration(minutes: clock));
}
```

`ShiftAlarmPlan`（第 53-63 行）加 `alarmIndex` 与 `alarm` 字段：

```dart
class ShiftAlarmPlan {
  const ShiftAlarmPlan({
    required this.offset,
    required this.shift,
    required this.alarm,
    required this.alarmIndex,
    required this.fireAt,
  });

  final int offset;
  final ShiftClass shift;
  final ShiftAlarm alarm;

  /// 这个闹钟在 `shift.alarms` 里的下标 —— 原生 id 的「序号」就是它。
  final int alarmIndex;

  final DateTime fireAt;
}
```

`planShiftAlarms` 里那个 `continue` 条件与 push 改成逐闹钟：

```dart
    final t = schedule.shiftOn(date);
    if (t == null || t.isRest || !t.alarmEnabled || t.alarms.isEmpty) {
      continue;
    }
    // 按天覆盖：该天被单独关闭则跳过
    if (overrides[dayNumber(date)] == false) continue;

    for (var i = 0; i < t.alarms.length; i++) {
      final alarm = t.alarms[i];
      final fireAt = shiftAlarmFireAt(date, t, alarm);
      if (!fireAt.isAfter(from)) continue;
      plans.add(ShiftAlarmPlan(
        offset: d,
        shift: t,
        alarm: alarm,
        alarmIndex: i,
        fireAt: fireAt,
      ));
    }
```

`reschedule` 的排定循环（第 735-740 行）暂不改 id 算式（Task 5 做），但要把标题改成走 L10n：

```dart
    for (final plan in planShiftAlarms(schedule,
        from: DateTime.now(), days: days, overrides: overrides)) {
      try {
        await scheduleNativeAlarm(
            _shiftBaseId + plan.offset,
            plan.fireAt,
            L10n.shiftAlarmTitle(plan.shift.name, plan.alarm.label));
      } catch (e) {
        await appendLog('reschedule: 排班闹钟排定失败: $e');
      }
    }
```

**`app/lib/core/l10n.dart`**（加在 `alarmTime` 后面，第 312 行之后）：

```dart
  /// 联动闹钟的响铃标题。[label] 是这条闹钟自己的名字（可空）。
  ///
  /// 从前这里是 `'${shift.name}提醒'` 拼裸中文 —— 英文界面下会露出中文。
  /// 名字为空的判定连空白一起算：用户在输入框里敲了个空格不该变成「白班 · 」。
  static String shiftAlarmTitle(String shiftName, String? label) {
    final name = label?.trim();
    if (name == null || name.isEmpty) return t('$shiftName提醒', '$shiftName alarm');
    return '$shiftName · $name';
  }
```

**`app/lib/features/alarm/alarm_screen.dart`**（第 85、267、270 行）：过滤条件与那两行显示取第一条（多个的显示是 Task 7 的事）：

```dart
        if (t == null || t.isRest || !t.alarmEnabled || t.alarms.isEmpty) {
          continue;
        }
```
```dart
              Text(
                _fmt(e.shift.alarms.first.minute),
                style: AppTokens.titleStrong,
              ),
              if (alarmFallsOnPreviousDay(e.shift, e.shift.alarms.first))
```

**`app/lib/features/calendar/calendar_screen.dart`** `_alarmText`（第 1884-1891 行）：

```dart
String _alarmText(ShiftClass t) {
  if (t.isRest) return L10n.restNoAlarm;
  if (!t.alarmEnabled || t.alarms.isEmpty) return L10n.alarmOff;
  final alarm = t.alarms.first;
  final clock = formatClock(alarm.minute);
  // 落在上班**前一天**的（00:00 上班的夜班）必须标出来：不标的话，这一行会跟
  // 前面的「00:00 – 08:00」读成同一天的两件事。
  return L10n.alarmAt(
      alarmFallsOnPreviousDay(t, alarm) ? L10n.clockPrevDay(clock) : clock);
}
```

**`app/lib/features/calendar/schedule_editor_screen.dart`**：`_editClass`（第 1575-1602 行）里 `alarmMinute` / `clearAlarmMinute` 换成 `alarms`：

```dart
  List<ShiftAlarm>? alarms,
  bool clearAlarms = false,
```
```dart
    alarms: clearAlarms ? const [] : (alarms ?? c.alarms),
```

`_classRow` 里那三处（第 549-554、667-692 行）：`alarmPrevDay` / `alarmNoStart` 的计算与显示改用第一条：

```dart
    final firstAlarm = c.alarms.isEmpty ? null : c.alarms.first;
    final alarmPrevDay = c.alarmEnabled &&
        firstAlarm != null &&
        alarmFallsOnPreviousDay(c, firstAlarm);
    final alarmNoStart = c.alarmEnabled &&
        firstAlarm != null &&
        !alarmFallsOnPreviousDay(c, firstAlarm) &&
        c.startMinute == null;
```
```dart
            if (c.alarmEnabled) ...[
              const SizedBox(height: AppTokens.spaceSm),
              _timeChip(
                context,
                label: L10n.alarmTime,
                minutes: firstAlarm?.minute,
                valueText: alarmPrevDay
                    ? L10n.clockPrevDay(formatClock(firstAlarm!.minute))
                    : null,
                onPick: (m) => setState(() => _classes[index] = _editClass(
                    _classes[index],
                    alarms: [ShiftAlarm(minute: m, label: firstAlarm?.label)])),
              ),
              if (alarmPrevDay || alarmNoStart)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                  child: Text(
                    alarmPrevDay
                        ? L10n.alarmPrevDayHint(formatClock(c.startMinute!),
                            formatClock(firstAlarm!.minute))
                        : L10n.alarmNoStartHint,
                    style: AppTokens.microText.copyWith(color: muted),
                  ),
                ),
            ],
```

`_setRest`（第 728-733 行）：`clearAlarmMinute: true` → `clearAlarms: true`。

**`app/lib/domain/schedule_template.dart`**：`encodeTemplateClasses` 仍写旧的两个字段（新格式在 Task 4），取第一条：

```dart
          'alarmEnabled': c.alarmEnabled,
          'alarmMinute': c.alarms.isEmpty ? null : c.alarms.first.minute,
```
`decodeTemplateClasses` 里 `alarmMinute:` 那一行换成：

```dart
            alarms: (e['alarmMinute'] as num?) == null
                ? const []
                : [ShiftAlarm(minute: (e['alarmMinute'] as num).toInt())],
```

- [ ] **Step 6: 改测试里的构造点**

```bash
grep -rn "alarmMinute:" test/
```
每个命中点按上面的形状改（`alarmMinute: X` → `alarms: const [ShiftAlarm(minute: X)]`，`alarmMinute: null` → 删行）。断言里读 `alarmMinute` 的地方改成 `alarms.first.minute`（`migration_v8_to_v9_test.dart:95` 那条 `expect(back.single.classes.first.alarmMinute, 7 * 60)` → `expect(back.single.classes.first.alarms.first.minute, 7 * 60)`）。

- [ ] **Step 7: 全量验证**

```bash
cd app && flutter analyze && flutter test
```
Expected: `No issues found!` + 全绿（297 条上下，只多不少）。**这一步是「行为不变」的验收**：除新加的领域用例之外，一条既有用例都不该改断言（只改构造形状）。

- [ ] **Step 8: 提交**

```bash
git add -A app/lib app/test
git commit -m "refactor(alarm): 班次闹钟从单个钟点换成列表（行为不变）"
```

---

### Task 2: 「前一天 / 当天」规则补好（含零点班班中那一档）

**Files:**
- Modify: `app/lib/domain/shift_rotation.dart`（`alarmFallsOnPreviousDay` 的实现）
- Test: `app/test/shift_rotation_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `ShiftAlarm` / `ShiftClass.alarms` / `alarmFallsOnPreviousDay`
- Produces：同签名，语义升级为「窗口内 → 当天，否则晚于上班钟点 → 前一天，否则当天」

- [ ] **Step 1: 写失败测试**

追加到 `app/test/shift_rotation_test.dart`：

```dart
  group('闹钟落在哪天：窗口内算当天（spec §4）', () {
    bool prev(int? start, int? end, int alarm) => alarmFallsOnPreviousDay(
          ShiftClass(name: '班', startMinute: start, endMinute: end),
          ShiftAlarm(minute: alarm),
        );

    test('白班 08:00–20:00：起床当天、午休也当天（旧规则会把午休排到前一天）', () {
      expect(prev(8 * 60, 20 * 60, 6 * 60 + 30), isFalse, reason: '窗外早于上班 → 当天');
      expect(prev(8 * 60, 20 * 60, 12 * 60 + 30), isFalse, reason: '窗内 → 当天');
    });

    test('零点班 00:00–08:00：23:00 前一天，班中 03:00 当天', () {
      // 用户 2026-09-21 点名问的就是这一条。
      expect(prev(0, 8 * 60, 23 * 60), isTrue, reason: '窗外晚于上班 → 前一天');
      expect(prev(0, 8 * 60, 3 * 60), isFalse, reason: '班中补觉 → 当天');
      expect(prev(0, 8 * 60, 7 * 60 + 30), isFalse, reason: '窗内 → 当天');
    });

    test('20:00–次日 08:00 的夜班：19:00 与 02:00 都当天', () {
      expect(prev(20 * 60, 8 * 60 + 1440, 19 * 60), isFalse);
      expect(prev(20 * 60, 8 * 60 + 1440, 2 * 60), isFalse);
    });

    test('边界：正好等于上班时刻 → 当天', () {
      expect(prev(8 * 60, 20 * 60, 8 * 60), isFalse);
    });

    test('边界：正好等于下班时刻 / 下班之后 —— 与旧规则逐字相同', () {
      // 00:00 班的 08:00：窗外且晚于上班钟点 → 前一天（旧规则同）
      expect(prev(0, 8 * 60, 8 * 60), isTrue);
      // 20:00 班的 08:00：窗外、早于上班钟点 → 当天（旧规则同）
      expect(prev(20 * 60, 8 * 60 + 1440, 8 * 60), isFalse);
      expect(prev(0, 8 * 60, 22 * 60), isTrue, reason: '下班之后的钟点仍是前一天');
    });

    test('24 小时值班：全天都算当天', () {
      expect(prev(8 * 60, 8 * 60 + 1440, 7 * 60), isFalse);
      expect(prev(8 * 60, 8 * 60 + 1440, 12 * 60), isFalse);
      expect(prev(8 * 60, 8 * 60 + 1440, 22 * 60), isFalse);
    });

    test('没填时间：判不了，一律当天', () {
      expect(prev(null, null, 23 * 60), isFalse, reason: '上班时间没填 —— 不瞎挪一天');
      expect(prev(8 * 60, null, 12 * 60 + 30), isFalse,
          reason: '下班时间没填 → 窗口算不出，退回旧规则：12:30 晚于 08:00');
      expect(prev(8 * 60, null, 6 * 60 + 30), isFalse);
      expect(prev(8 * 60, null, 21 * 60), isTrue,
          reason: '退回旧规则：21:00 晚于 08:00 → 前一天');
    });
  });
```

- [ ] **Step 2: 跑一遍，确认红**

```bash
cd app && flutter test test/shift_rotation_test.dart --plain-name '闹钟落在哪天'
```
Expected: FAIL —— 午休那条（12:30）会得到 `true`（旧规则），断言 `isFalse` 失败。

- [ ] **Step 3: 实现**

`app/lib/domain/shift_rotation.dart`，替换 `alarmFallsOnPreviousDay` 整块：

```dart
/// 某条闹钟的钟点落在上班的**前一天**还是**班次当天**。
///
/// 规则（spec §4.2）：
///   ① 钟点落在**值班窗口内**（`[start, end)`，按班次相对时刻算 —— 跨午夜与
///      24 小时班都成立）→ **当天**。班中间的闹钟（白班的午休 12:30、零点班的
///      班中 03:00）要的就是这一档。
///   ② 否则钟点**晚于上班钟点** → **前一天**。00:00 上班、23:00 响铃排前一天的
///      23:00 —— 排在班次当天就已经是班后 15 小时（v0.8.9 修好的那条）。
///   ③ 否则 → **当天**。
///
/// 与旧规则（`alarm.minute > start` 一条判据）的差异**只有第 ① 档**：旧规则会把
/// 班中间的闹钟搬到 20 多小时前。其余钟点逐条相同，包括两个边界 ——
/// 正好等于下班时刻 / 下班之后的钟点走第 ② ③ 档，落哪天取决于它相对上班钟点的
/// 大小（00:00 班的 08:00 → 前一天；20:00 班的 08:00 → 当天），两种形状都与旧规则
/// 逐字相同。这两类钟点用户真想要的是「次日」，两档模型表达不了，见 spec §9。
///
/// 时间没填：上班没填 → 判不了，按当天（不瞎挪一天）；下班没填 → 窗口算不出，
/// 退回旧规则（只按上班钟点判）。
bool alarmFallsOnPreviousDay(ShiftClass shift, ShiftAlarm alarm) {
  final s = shift.startMinute;
  if (s == null) return false;
  final e = shift.endMinute;
  if (e != null) {
    final span = e - s; // 值班时长；跨午夜/24 小时班都成立（end 允许 > 1440）
    final rel = ((alarm.minute - s) % _dayMinutes + _dayMinutes) % _dayMinutes;
    if (rel < span) return false;
  }
  return alarm.minute > s;
}

const int _dayMinutes = 1440;
```

- [ ] **Step 4: 跑，绿**

```bash
cd app && flutter test test/shift_rotation_test.dart
```
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/domain/shift_rotation.dart app/test/shift_rotation_test.dart
git commit -m "fix(alarm): 班中闹钟算班次当天 —— 钟点落在值班窗口内不再挪到前一天"
```

---

### Task 3: 新表 `shift_class_alarms` + v9→v10 迁移 + 仓储读写

**Files:**
- Modify: `app/lib/data/app_database.dart`（新表 + `schemaVersion` + 迁移分支 + 修 v5→v6 历史路径）
- Modify: `app/lib/data/app_database.g.dart`（**生成物**，跑 build_runner）
- Modify: `app/lib/data/app_repository.dart`（`_loadChildren` 装载闹钟、`ShiftClassRowX.toDomain`、`saveSchedule` 同步写入、`seed.dart`）
- Test: `app/test/migration_v9_to_v10_test.dart`（**新建**）

**Interfaces:**
- Consumes：Task 1 的 `ShiftAlarm` / `ShiftClass.alarms`
- Produces：
  - 表 `ShiftClassAlarms`：`classId` + `order` + `minute` + `label`（可空），复合主键 `{classId, order}`
  - `ActiveSchedule.classAlarms` → `Map<int, List<ShiftAlarm>>`（key 是 classId），`toDomain()` 用它装配
  - `AppRepository.saveSchedule(...)` 的签名**不变**（闹钟跟着 `ShiftClass.alarms` 走）

- [ ] **Step 1: 先写迁移测试（会红）**

新建 `app/test/migration_v9_to_v10_test.dart`：

```dart
// app/test/migration_v9_to_v10_test.dart
//
// v9 → v10：班次闹钟从 `shift_class_rows` 上的一个钟点（`alarm_minute`）搬进新表
// `shift_class_alarms`，并把那一列**删掉**。
//
// 这条迁移比 v8→v9 危险：`alterTable` 会**重建 shift_class_rows**，而
// `shift_cycle_rows.class_id` 与 `shift_day_overrides.class_id` 都指着它的 id ——
// id 一变，周期与按天覆盖集体指飞（不报错，只是那天变成别的班）。所以 fixture
// 要抄全套四张表，并逐条断言引用还指得对。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v9 的四张表（DDL 与 v9 生成代码逐列一致）。
const _v9Tables = [
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
  CREATE TABLE shift_class_rows (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    schedule_id INTEGER NOT NULL,
    "order" INTEGER NOT NULL,
    name TEXT NOT NULL,
    abbr TEXT,
    start_minute INTEGER,
    end_minute INTEGER,
    is_rest INTEGER NOT NULL DEFAULT 0,
    color INTEGER NOT NULL DEFAULT 4284186623,
    alarm_enabled INTEGER NOT NULL DEFAULT 0,
    alarm_minute INTEGER
  )
  ''',
  '''
  CREATE TABLE shift_cycle_rows (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    schedule_id INTEGER NOT NULL,
    "order" INTEGER NOT NULL,
    class_id INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE shift_day_overrides (
    schedule_id INTEGER NOT NULL,
    day INTEGER NOT NULL,
    class_id INTEGER NOT NULL,
    PRIMARY KEY (schedule_id, day)
  )
  ''',
  '''
  CREATE TABLE custom_templates (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    classes TEXT NOT NULL,
    cycle TEXT NOT NULL,
    team_count INTEGER NOT NULL,
    team_offsets TEXT NOT NULL,
    created_at INTEGER NOT NULL
  )
  ''',
];

int _day(int y, int m, int d) => dayNumber(DateTime.utc(y, m, d));

void main() {
  late sqlite3.Database raw;

  setUp(() {
    raw = sqlite3.sqlite3.openInMemory();
    for (final ddl in _v9Tables) {
      raw.execute(ddl);
    }
    raw.execute(
      'INSERT INTO shift_schedule_rows '
      '(id, name, anchor_date, is_current, team_count, team_names, '
      'our_team_index, team_offsets) VALUES (1, ?, ?, 1, 1, ?, 0, ?)',
      [
        '我的班',
        DateTime.utc(2026, 9, 21).millisecondsSinceEpoch ~/ 1000,
        '我',
        '0',
      ],
    );
    // 白班：开关开着 + 07:00（要搬进新表）
    raw.execute(
      'INSERT INTO shift_class_rows (id, schedule_id, "order", name, abbr, '
      'start_minute, end_minute, is_rest, color, alarm_enabled, alarm_minute) '
      'VALUES (11, 1, 0, ?, ?, ?, ?, 0, 4284186623, 1, ?)',
      ['白班', '白', 8 * 60, 20 * 60, 7 * 60],
    );
    // 夜班：开关**关着**但时间还在（19:30）—— 用户手滑关过开关的情形，
    // 时间必须一起搬过去，不然升级一次配置就没了
    raw.execute(
      'INSERT INTO shift_class_rows (id, schedule_id, "order", name, abbr, '
      'start_minute, end_minute, is_rest, color, alarm_enabled, alarm_minute) '
      'VALUES (12, 1, 1, ?, ?, ?, ?, 0, 4284186623, 0, ?)',
      ['夜班', '夜', 20 * 60, 8 * 60, 19 * 60 + 30],
    );
    // 休班：从来没设过闹钟
    raw.execute(
      'INSERT INTO shift_class_rows (id, schedule_id, "order", name, abbr, '
      'start_minute, end_minute, is_rest, color, alarm_enabled, alarm_minute) '
      'VALUES (13, 1, 2, ?, ?, NULL, NULL, 1, 4284186623, 0, NULL)',
      ['休班', '休'],
    );
    raw.execute('INSERT INTO shift_cycle_rows (schedule_id, "order", class_id) '
        'VALUES (1, 0, 11), (1, 1, 12), (1, 2, 13)');
    // 按天覆盖：把 9/22 换成休班（classId 13）—— 迁移后必须还指着 13
    raw.execute(
        'INSERT INTO shift_day_overrides (schedule_id, day, class_id) VALUES (1, ?, 13)',
        [_day(2026, 9, 22)]);
    raw.execute('PRAGMA user_version = 9');
  });

  tearDown(() => raw.dispose());

  test('v9 → v10：闹钟搬进新表、老排班的周期与按天覆盖仍指得对', () async {
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // 1) 闹钟行搬过来了，连「开关关着但有时间」那条一起
    final rows = await (db.select(db.shiftClassAlarms)
          ..orderBy([(t) => OrderingTerm.asc(t.classId)]))
        .get();
    expect(rows, hasLength(2));
    expect(rows[0].classId, 11);
    expect(rows[0].order, 0);
    expect(rows[0].minute, 7 * 60);
    expect(rows[0].label, isNull);
    expect(rows[1].classId, 12);
    expect(rows[1].minute, 19 * 60 + 30,
        reason: '开关关着但有时间的行也必须搬 —— 只挑 alarm_enabled = 1 就等于把用户配好的时间吞了');

    // 2) 总开关没被动过
    final classes = await (db.select(db.shiftClassRows)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    expect(classes.map((c) => c.id), [11, 12, 13]);
    expect(classes[1].alarmEnabled, isFalse, reason: '关着的开关不能因为迁移被打开');

    // 3) 周期与按天覆盖仍指向同一批 id
    final domain = (await db.select(db.shiftCycleRows).get())
        .map((r) => r.classId)
        .toList();
    expect(domain, [11, 12, 13], reason: 'alterTable 重建表后 classId 不能变');
    final ov = await db.select(db.shiftDayOverrides).get();
    expect(ov.single.classId, 13, reason: '按天覆盖还指着休班那条');

    // 4) 走一遍领域装配：班次带着闹钟出来，覆盖换成下标
    final active = await db.loadActiveScheduleForTesting();
    final s = active!.toDomain();
    expect(s.classes[0].alarms.single.minute, 7 * 60);
    expect(s.classes[1].alarms.single.minute, 19 * 60 + 30);
    expect(s.classes[1].alarmEnabled, isFalse);
    expect(s.classes[2].alarms, isEmpty);
    expect(s.dayOverrides[_day(2026, 9, 22)], 2, reason: '覆盖装配成 classes 下标');

    // 5) 老列真的没了（没留死列）
    final cols = raw
        .select('PRAGMA table_info(shift_class_rows)')
        .map((r) => r['name'] as String)
        .toList();
    expect(cols, isNot(contains('alarm_minute')));
  });
}
```

（`loadActiveScheduleForTesting` 是本任务要加的测试入口，见 Step 3；`OrderingTerm` 来自 `package:drift/drift.dart`，记得在测试顶部 `import 'package:drift/drift.dart' show OrderingTerm;`。）

- [ ] **Step 2: 跑，确认红**

```bash
cd app && flutter test test/migration_v9_to_v10_test.dart
```
Expected: 编译失败 —— `db.shiftClassAlarms` / `loadActiveScheduleForTesting` 还不存在。

- [ ] **Step 3: 加表与迁移**

`app/lib/data/app_database.dart`，表定义加在 `ShiftCycleRows` 之后：

```dart
/// 班次闹钟表：一个班次可以挂多条联动闹钟（上限 `maxAlarmsPerShift`）。
///
/// **不设自增 id**：没有任何东西引用单条闹钟（「按天关闹钟」是按天、不是按闹钟；
/// 模板不存身份），所以它跟 `ShiftDayOverrides` 不是一类东西 —— 那边要稳定 id
/// 是因为覆盖要指得住班次定义。别为了对称给它加 id。
///
/// `order` 是用户在编辑页里的顺序，**同时也是原生 id 里的「序号」**
/// （见 `AlarmService._shiftDaysHorizon`）。总开关在 `ShiftClassRows.alarmEnabled`
/// 上（关掉不清空这里的时间）。
class ShiftClassAlarms extends Table {
  IntColumn get classId => integer()();
  IntColumn get order => integer()();
  IntColumn get minute => integer()();
  TextColumn get label => text().nullable()();

  @override
  Set<Column> get primaryKey => {classId, order};
}
```

`@DriftDatabase(tables: [...])` 里加 `ShiftClassAlarms`，`schemaVersion` 改成 `10`，`onUpgrade` 里在最前面加：

```dart
          if (from < 10) {
            // 班次闹钟：一个钟点（alarm_minute 列）→ 一张表（每组有序）。
            await m.createTable(shiftClassAlarms);
            // 条件只看 alarm_minute：开关关着但时间还留着的行同样要搬 ——
            // 只挑 alarm_enabled = 1 等于把用户配好的时间吞了，而界面上看不出来。
            await customStatement(
              'INSERT INTO shift_class_alarms (class_id, "order", minute, label) '
              'SELECT id, 0, alarm_minute, NULL FROM shift_class_rows '
              'WHERE alarm_minute IS NOT NULL',
            );
            // 删掉旧列（重建表）。id 必须原样带过去 —— shift_cycle_rows 与
            // shift_day_overrides 都指着它，一变就集体指飞。
            await m.alterTable(TableMigration(shiftClassRows));
          }
```

`_migrateRowsToTwoTier`（v5→v6 历史路径）里那两条对 `shift_class_rows` 的写入要跟着改：`INSERT INTO shift_class_rows (...)` 去掉 `alarm_enabled` 与 `alarm_minute` 两列（表里已经没有 `alarm_minute`），并在插完班次行之后，把 `alarm_minute` 插进新表：

```dart
        await customInsert(
          'INSERT INTO shift_class_rows '
          '(id, schedule_id, "order", name, abbr, start_minute, end_minute, '
          'is_rest, color, alarm_enabled) '
          'VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?)',
          variables: [ ... ],
        );
        if (alarmMinute != null) {
          await customInsert(
            'INSERT INTO shift_class_alarms (class_id, "order", minute, label) '
            'VALUES (?, 0, ?, NULL)',
            variables: [Variable.withInt(classId), Variable.withInt(alarmMinute)],
          );
        }
```
（`from < 10` 分支排在 `from < 6` **之前**，所以 v5 升上来时新表已经建好了。这一点要写进注释 —— 顺序错了这段 insert 会打到不存在的表上。）

删掉 `if (from < 7)` 里那句 `m.addColumn(scheduleEvents, scheduleEvents.alarmEnabled)`？**不要** —— 那是 `schedule_events`（待办的联动闹钟），与班次闹钟不是一张表。原样留着。

- [ ] **Step 4: 重新生成 drift 代码**

```bash
cd app && dart run build_runner build --delete-conflicting-outputs
```
Expected: 生成 `ShiftClassAlarm` / `ShiftClassAlarmsCompanion`，且 `ShiftClassRow` 上**不再有** `alarmMinute`。

- [ ] **Step 5: 仓储读写新表**

`app/lib/data/app_repository.dart`：

`ActiveSchedule` 加一个字段与参数 —— **给缺省值 `const {}`**，别做成必填：测试里另有几处直接构造它（`day_override_repository_test.dart` 之类），必填会把它们全打红。

```dart
  /// 本方案各班次的闹钟行（key = classId，value 已按 order 排好）。
  final Map<int, List<ShiftAlarm>> classAlarms;
```
```dart
    this.classAlarms = const {},
```

`_loadChildren` 里多查一张表：

```dart
    final alarmRows = await (select(shiftClassAlarms)
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    final alarmsByClass = <int, List<ShiftAlarm>>{};
    for (final r in alarmRows) {
      (alarmsByClass[r.classId] ??= []).add(ShiftAlarm(minute: r.minute, label: r.label));
    }
```
（`shiftClassAlarms` 表没有 `scheduleId`，靠 `ActiveSchedule` 的 classes 过滤；`toDomain()` 里只取本方案 classId 的键即可，多余键无害。）

`toDomain()` 里 `classes.map((c) => c.toDomain())` 改成：

```dart
    final domainClasses =
        classes.map((c) => c.toDomain(alarms: classAlarms[c.id] ?? const [])).toList();
```

`ShiftClassRowX.toDomain` 签名与实现：

```dart
extension ShiftClassRowX on ShiftClassRow {
  /// [alarms] 由调用方从 `shift_class_alarms` 取好传进来（本行没有这张表的信息）。
  ShiftClass toDomain({List<ShiftAlarm> alarms = const []}) => ShiftClass(
        id: id,
        name: name,
        abbr: abbr,
        startMinute: startMinute,
        endMinute: endMinute,
        isRest: isRest,
        color: color,
        alarmEnabled: alarmEnabled,
        alarms: alarms,
      );
}
```

`saveSchedule`：两个写点删掉 `alarmMinute:` 那一行（表里没这列了），并在循环内、拿到 `classId` 之后同步闹钟行 —— **整组删掉重建**（条数 ≤ 6、没有外部引用，不必像班次那样走增量）：

```dart
      // 闹钟整组重写：条数少（≤ maxAlarmsPerShift）、没有任何东西引用单条闹钟，
      // 删了重建比逐条对账简单得多。**顺序必须按列表顺序落**，它就是原生 id 的序号。
      final classId = classIds[i];
      await (db.delete(db.shiftClassAlarms)
            ..where((t) => t.classId.equals(classId)))
          .go();
      for (var k = 0; k < c.alarms.length; k++) {
        await db.into(db.shiftClassAlarms).insert(
              ShiftClassAlarmsCompanion.insert(
                classId: classId,
                order: k,
                minute: c.alarms[k].minute,
                label: Value(c.alarms[k].label),
              ),
            );
      }
```
（放的位置：`if (c.id != null) {...} else {...}` 之后、`classIds.add` 的同一个循环体里 —— 两个分支都要走这段，所以把它写在 `for (var i = 0; i < classes.length; i++)` 循环体的**末尾**，用刚得到的 `classIds[i]`。）

删班次那一段（第 420-427 行）加一句连带删：

```dart
        await (db.delete(db.shiftClassAlarms)
              ..where((t) => t.classId.equals(row.id)))
            .go();
```
`deleteSchedule` / `clearAll` 里凡是删班次行的地方都要同样连带删（`grep -n "shiftClassRows" lib/data/app_repository.dart` 逐个看）。

`seed.dart`：`alarmMinute:` 那一行删掉，插完班次行后插闹钟行（照上面 saveSchedule 的写法，`order` 用列表下标）。那两行：

```dart
            alarmEnabled: Value(c.alarmEnabled),
```
```dart
    for (var k = 0; k < c.alarms.length; k++) {
      await db.into(db.shiftClassAlarms).insert(
            ShiftClassAlarmsCompanion.insert(
              classId: classIds.last,
              order: k,
              minute: c.alarms[k].minute,
              label: Value(c.alarms[k].label),
            ),
          );
    }
```
（写在 `classIds.add(...)` 之后。）

加一个测试入口（`app/lib/data/app_repository.dart` 里，`AppDatabaseQueries` 扩展上）：

```dart
  /// 测试专用：按当前方案装配一次 `ActiveSchedule`（不依赖 Riverpod 流）。
  Future<ActiveSchedule?> loadActiveScheduleForTesting() async {
    final sched = await (select(shiftScheduleRows)
          ..where((s) => s.isCurrent.equals(true)))
        .getSingleOrNull();
    if (sched == null) return null;
    return _loadChildren(sched);
  }
```

- [ ] **Step 6: 跑迁移测试 + 全量**

```bash
cd app && flutter test test/migration_v9_to_v10_test.dart && flutter test
```
Expected: 新用例 PASS；**既有迁移用例一条都不许红** —— 尤其 `migration_v5_to_v6_test.dart`（它盯的就是 Step 3 那段历史路径）。`saved_template_test.dart` / `day_override_repository_test.dart` 如果因为落库形状变了而红，按新形状改它们的断言（**不许**为了让它们绿而把行为改回去）。

- [ ] **Step 7: 提交**

```bash
git add -A app/lib app/test
git commit -m "feat(db): 班次闹钟迁进新表 shift_class_alarms（schemaVersion 10）"
```

---

### Task 4: 模板格式：`alarms` 新字段 + 老 JSON 回退

**Files:**
- Modify: `app/lib/domain/schedule_template.dart`
- Test: `app/test/schedule_template_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `ShiftAlarm`、Task 3 的表（无直接关系）
- Produces：模板 JSON 里班次对象新增 `"alarms": [{"minute": int, "label": String?}, …]`，**不再写** `alarmEnabled` / `alarmMinute`

- [ ] **Step 1: 写失败测试**

追加到 `app/test/schedule_template_test.dart`：

```dart
  test('编解码往返：多条闹钟连名字一起存回来', () {
    final classes = [
      const ShiftClass(
        name: '白班',
        abbr: '白',
        startMinute: 8 * 60,
        endMinute: 20 * 60,
        alarmEnabled: true,
        alarms: [
          ShiftAlarm(minute: 6 * 60 + 30, label: '起床'),
          ShiftAlarm(minute: 12 * 60 + 30, label: '午休'),
        ],
      ),
    ];
    final raw = encodeTemplateClasses(classes);
    expect(raw, contains('alarms'));
    expect(raw, isNot(contains('alarmMinute')),
        reason: '只许有一个来源：新字段写出去之后旧字段不能再写');

    final back = decodeTemplateClasses(raw);
    expect(back.single.alarms, hasLength(2));
    expect(back.single.alarms.first.label, '起床');
    expect(back.single.alarms[1].minute, 12 * 60 + 30);
    expect(back.single.alarmEnabled, isTrue);
  });

  test('老模板 JSON（只有 alarmEnabled / alarmMinute）：回退成一个闹钟', () {
    // 用户在升级前存下的「我的模板」必须照常打开。
    const legacy = '[{"name":"白班","abbr":"白","startMinute":480,'
        '"endMinute":1200,"isRest":false,"color":4284186623,'
        '"alarmEnabled":true,"alarmMinute":420}]';
    final back = decodeTemplateClasses(legacy);
    expect(back.single.alarms.single.minute, 420);
    expect(back.single.alarms.single.label, isNull);
    expect(back.single.alarmEnabled, isTrue);
  });

  test('老模板里 alarmEnabled 开、钟点为 null：得到一个空表（不是一条 0 点的闹钟）', () {
    const legacy = '[{"name":"白班","alarmEnabled":true,"alarmMinute":null}]';
    expect(decodeTemplateClasses(legacy).single.alarms, isEmpty);
  });
```

- [ ] **Step 2: 跑，确认红**

```bash
cd app && flutter test test/schedule_template_test.dart
```
Expected: FAIL —— 编码里还没有 `alarms` 字段。

- [ ] **Step 3: 实现**

`encodeTemplateClasses` 里把两个旧字段换成：

```dart
          'alarms': [
            for (final a in c.alarms) {'minute': a.minute, 'label': a.label},
          ],
```

`decodeTemplateClasses` 里：

```dart
            alarmEnabled: e['alarmEnabled'] == true,
            alarms: _decodeAlarms(e),
```

文件底部加：

```dart
/// 班次对象 → 闹钟列表。
///
/// 新格式读 `alarms`；**没有就回退**读旧的两个字段（用户升级前存下的模板仍在
/// 硬盘上）。旧格式里 `alarmMinute` 为空 → 空表 —— 不能退化成「一条 0 点的闹钟」。
List<ShiftAlarm> _decodeAlarms(Map e) {
  final list = e['alarms'];
  if (list is List) {
    return [
      for (final a in list)
        if (a is Map && a['minute'] is num)
          ShiftAlarm(
            minute: (a['minute'] as num).toInt(),
            label: a['label'] is String ? a['label'] as String : null,
          ),
    ];
  }
  final legacy = e['alarmMinute'];
  if (legacy is num) return [ShiftAlarm(minute: legacy.toInt())];
  return const [];
}
```

- [ ] **Step 4: 跑，绿 + 全量**

```bash
cd app && flutter test test/schedule_template_test.dart && flutter test
```
Expected: PASS + 全绿（`saved_template_test.dart` 会顺带走一遍存取往返）。

- [ ] **Step 5: 提交**

```bash
git add app/lib/domain/schedule_template.dart app/test/schedule_template_test.dart
git commit -m "feat(template): 模板 JSON 支持多条班次闹钟，老模板回退成一个"
```

---

### Task 5: 排定：原生 id 算式 + 天窗口常量 + 响铃标题

**Files:**
- Modify: `app/lib/features/alarm/alarm_service.dart`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/AlarmScheduler.kt`（**只改注释**）
- Test: `app/test/shift_alarm_decision_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `ShiftAlarmPlan.alarmIndex`、Task 2 的规则
- Produces：
  - `AlarmService` 里 `static const int _shiftDaysHorizon = 60;`（`reschedule(days:)` 的缺省值引用它）
  - 原生 id = `_shiftBaseId + plan.alarmIndex * _shiftDaysHorizon + plan.offset`

- [ ] **Step 1: 写失败测试**

追加到 `app/test/shift_alarm_decision_test.dart`（那个文件里已有 `_schedule()` / `_nightOnlySchedule()` 两个夹具，按需给它们加 `alarms`）：

```dart
  group('一条班次挂多个闹钟（spec §6）', () {
    ShiftSchedule twoAlarms() => ShiftSchedule(
          name: '测试',
          anchorDate: DateTime.utc(2026, 9, 20),
          classes: const [
            ShiftClass(
              id: 31,
              name: '白班',
              abbr: '白',
              startMinute: 8 * 60,
              endMinute: 20 * 60,
              alarmEnabled: true,
              alarms: [
                ShiftAlarm(minute: 6 * 60 + 30, label: '起床'),
                ShiftAlarm(minute: 12 * 60 + 30, label: '午休'),
              ],
            ),
          ],
          cycle: const [0],
          teamCount: 1,
          teamNames: const ['我'],
          teamOffsets: const [0],
        );

    test('两个闹钟各一条 plan，序号 0/1，都落在班次当天', () {
      final plans = planShiftAlarms(twoAlarms(),
          from: DateTime(2026, 9, 20, 5), days: 1);
      expect(plans, hasLength(2));
      expect(plans[0].alarmIndex, 0);
      expect(plans[0].fireAt, DateTime(2026, 9, 20, 6, 30));
      expect(plans[1].alarmIndex, 1);
      expect(plans[1].fireAt, DateTime(2026, 9, 20, 12, 30),
          reason: '午休落在值班窗口内 → 班次当天（旧规则会排到前一天中午）');
      expect(plans[0].alarm.label, '起床');
    });

    test('零点班：起床在前一天、班中补觉在当天，两条各归各的', () {
      final s = ShiftSchedule(
        name: '测试',
        anchorDate: DateTime.utc(2026, 9, 20),
        classes: const [
          ShiftClass(
            id: 32,
            name: '夜班',
            abbr: '夜',
            startMinute: 0,
            endMinute: 8 * 60,
            alarmEnabled: true,
            alarms: [
              ShiftAlarm(minute: 23 * 60, label: '起床'),
              ShiftAlarm(minute: 3 * 60, label: '补觉'),
            ],
          ),
        ],
        cycle: const [0],
        teamCount: 1,
        teamNames: const ['我'],
        teamOffsets: const [0],
      );
      final plans = planShiftAlarms(s, from: DateTime(2026, 9, 19, 12), days: 2);
      // 9/19 那天的班：起床 9/18 23:00（已过去，跳过）、补觉 9/19 03:00（已过去）
      // 9/20 那天的班：起床 9/19 23:00、补觉 9/20 03:00
      expect(plans.map((p) => p.fireAt).toList(),
          [DateTime(2026, 9, 19, 23), DateTime(2026, 9, 20, 3)]);
      expect(plans.map((p) => p.offset).toList(), [1, 1],
          reason: 'offset 仍按班次那一天算');
      expect(plans.map((p) => p.alarmIndex).toList(), [0, 1]);
    });

    test('按天关闹钟：那天这个班次的闹钟一个都不排', () {
      expect(
          planShiftAlarms(twoAlarms(),
              from: DateTime(2026, 9, 20, 5),
              days: 1,
              overrides: {dayNumber(DateTime(2026, 9, 20)): false}),
          isEmpty);
    });

    test('原生 id 的算式：序号 × 天窗口 + 天数偏移，且落在 0..400 里', () {
      // 这条把 `reschedule` 的 id 算式抄成纯断言 —— 它是「上限 6」的由来。
      final horizon = maxAlarmsPerShift * AlarmService.shiftDaysHorizonForTesting;
      expect(horizon, lessThanOrEqualTo(400),
          reason: 'Kotlin 侧 cancelAllNativeAlarms 只扫 0..400（MainActivity.kt:550）');
      final plans = planShiftAlarms(twoAlarms(),
          from: DateTime(2026, 9, 20, 5), days: 3);
      for (final p in plans) {
        final id = p.alarmIndex * AlarmService.shiftDaysHorizonForTesting + p.offset;
        expect(id, inInclusiveRange(0, 400));
      }
      // 同一天两个闹钟必须拿到不同的 id（序号把它们分开）
      final ids = plans
          .where((p) => p.offset == 0)
          .map((p) => p.alarmIndex * AlarmService.shiftDaysHorizonForTesting + p.offset)
          .toSet();
      expect(ids, hasLength(2));
    });

    test('重排两次得到同一批 id（序号不能自己变）', () {
      final a = planShiftAlarms(twoAlarms(), from: DateTime(2026, 9, 20, 5), days: 5)
          .map((p) => p.alarmIndex * 1000 + p.offset)
          .toList();
      final b = planShiftAlarms(twoAlarms(), from: DateTime(2026, 9, 20, 5), days: 5)
          .map((p) => p.alarmIndex * 1000 + p.offset)
          .toList();
      expect(a, b, reason: '同一份数据重排两次必须一致，否则用户设过的响铃记录会错位');
    });
  });
```

- [ ] **Step 2: 跑，确认红**

```bash
cd app && flutter test test/shift_alarm_decision_test.dart
```
Expected: 编译失败 —— `AlarmService.shiftDaysHorizonForTesting` 不存在。

- [ ] **Step 3: 实现**

`app/lib/features/alarm/alarm_service.dart`：

```dart
  static const _shiftBaseId = 0;
  static const _customBaseId = 10000;
```

改成：

```dart
  static const _shiftBaseId = 0;

  /// 班次闹钟排定的天数窗口（`reschedule` 的 [days] 缺省值）。
  ///
  /// **它就是原生 id 里的那个 60**：id = 序号 × 本值 + 天数偏移。所以它和
  /// `maxAlarmsPerShift`（6，见 `domain/shift_rotation.dart`）是一对：
  /// 6 × 60 = 360 ≤ 400，而 Kotlin 侧 `cancelAllNativeAlarms` 扫的是 0..400
  /// （`MainActivity.kt:550`）。**改这个值必须同时改那个上限与 Kotlin 的扫描范围。**
  static const int _shiftDaysHorizon = 60;

  /// 测试用只读出口（算式是「上限 6」的由来，得能在纯测试里断言）。
  static int get shiftDaysHorizonForTesting => _shiftDaysHorizon;
```

`reschedule` 的签名缺省值改成 `int days = _shiftDaysHorizon,`，排定循环里的 id 与标题：

```dart
        await scheduleNativeAlarm(
            _shiftBaseId + plan.alarmIndex * _shiftDaysHorizon + plan.offset,
            plan.fireAt,
            L10n.shiftAlarmTitle(plan.shift.name, plan.alarm.label));
```

`planShiftAlarms` 头上那段注释里「id 是 `_shiftBaseId + 天数偏移`」的句子要改准：

```dart
/// 触发时刻由 [shiftAlarmFireAt] 算（可能是**前一天**晚上），但 `offset` 与原生
/// id 始终按**班次那一天**算 —— id 是 `序号 × 天数窗口 + 天数偏移`，跟着触发时刻走
/// 的话，每个午夜班的闹钟都会换号。**「序号」是闹钟在 `shift.alarms` 里的下标**：
/// 用户在编辑页里调整顺序会让闹钟换号（可接受 —— 编辑之后必然重排、`cancelAll`
/// 先跑），但**重排本身绝不能重新编号**，否则每次打开 App 都换一批。
```

`AlarmScheduler.kt` 第 18 行的注释改成：

```kotlin
    /** 自定义闹钟的原生 id 基址（id = 10000 + 数据库自增 id），与排班闹钟 0..359 隔离。 */
```
（排班闹钟现在占 0..359：6 个闹钟 × 60 天窗口。）

- [ ] **Step 4: 跑，绿 + 全量**

```bash
cd app && flutter test test/shift_alarm_decision_test.dart && flutter analyze && flutter test
```
Expected: PASS + `No issues found!` + 全绿。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/alarm/alarm_service.dart app/test/shift_alarm_decision_test.dart app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/AlarmScheduler.kt
git commit -m "feat(alarm): 原生 id 按「序号 × 60 + 天数偏移」，响铃标题走 L10n"
```

---

### Task 6: 编辑器：闹钟列表（加 / 删 / 命名 / 上限）

**Files:**
- Modify: `app/lib/core/l10n.dart`（四条新文案）
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`（班次卡片的闹钟区）
- Test: `app/test/schedule_editor_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `maxAlarmsPerShift` / `ShiftAlarm` / `ShiftClass.alarms`、Task 3 的落库路径
- Produces：`L10n.addAlarm` / `L10n.alarmNameOptional` / `L10n.alarmNameHint` / `L10n.alarmLimitReached`

- [ ] **Step 1: 写失败测试**

追加到 `app/test/schedule_editor_test.dart`（那个文件用的是 `_FakeRepository`：`_pumpEditor(tester, _domain())` 打开编辑器，断言落在 `repo.saved` 上 —— **不要**去查库，照它既有的写法）：

```dart
  testWidgets('给白班加两个闹钟：列表里两行、保存后落库两条（名字已 trim）',
      (tester) async {
    final repo = await _pumpEditor(tester, _domain());

    // 打开第一个班次（白班）的联动闹钟开关
    await tester.tap(find.byKey(const Key('shift-alarm-switch-0')));
    await tester.pumpAndSettle();

    // 加两条：新班次上一条闹钟都没有，所以第一次点「添加闹钟」加的是第 0 条
    await tester.tap(find.text(L10n.addAlarm));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shift-alarm-row-0-0')), findsOneWidget);
    await tester.tap(find.text(L10n.addAlarm));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shift-alarm-row-0-1')), findsOneWidget);

    // 给第二条起名字（前后都带空格，落库必须是 trim 过的）
    await tester.enterText(
        find.byKey(const Key('shift-alarm-label-0-1')), ' 午休 ');
    await tester.pumpAndSettle();

    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();

    final saved = repo.saved!.classes.first;
    expect(saved.alarmEnabled, isTrue);
    expect(saved.alarms, hasLength(2));
    expect(saved.alarms[1].label, '午休',
        reason: '名字要落库且已经 trim 过 —— 空串一律当没填');
    expect(saved.alarms[0].label, isNull);
  });

  testWidgets('到上限：不再出现「添加闹钟」，改为一行说明', (tester) async {
    final repo = await _pumpEditor(tester, _domain());
    await tester.tap(find.byKey(const Key('shift-alarm-switch-0')));
    await tester.pumpAndSettle();
    for (var i = 0; i < maxAlarmsPerShift; i++) {
      await tester.tap(find.text(L10n.addAlarm));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(Key('shift-alarm-row-0-${maxAlarmsPerShift - 1}')),
        findsOneWidget);
    expect(find.text(L10n.addAlarm), findsNothing,
        reason: '到上限之后按钮要消失 —— 不能留一颗点了没反应的按钮');
    expect(find.text(L10n.alarmLimitReached), findsOneWidget);

    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();
    expect(repo.saved!.classes.first.alarms, hasLength(maxAlarmsPerShift));
  });
```

- [ ] **Step 2: 跑，确认红**

```bash
cd app && flutter test test/schedule_editor_test.dart --plain-name '闹钟'
```
Expected: FAIL —— 没有 `addAlarm` 文案、没有那些 Key。

- [ ] **Step 3: 加文案**

`app/lib/core/l10n.dart`（接在 `alarmTime` 后面）：

```dart
  static String get addAlarm => t('添加闹钟', 'Add alarm');
  static String get alarmNameOptional => t('名称（可选）', 'Name (optional)');
  static String get alarmNameHint => t('如「起床」「午休」', 'e.g. "Wake up"');
  static String get alarmLimitReached =>
      t('每个班次最多 $maxAlarmsPerShift 个闹钟', 'Up to $maxAlarmsPerShift alarms per shift');
```
（`maxAlarmsPerShift` 要 import `../domain/shift_rotation.dart` —— `l10n.dart` 现在只依赖 intl，**这会引入一条依赖**。若不想引，就把 6 写进串里并加一行注释指向常量；两种都行，**选后者**：`l10n.dart` 保持「无业务依赖」这件性质更值钱。）

于是写成：

```dart
  /// 每个班次最多几个闹钟 —— 数字与 `domain/shift_rotation.dart` 的
  /// `maxAlarmsPerShift` 必须一致（那边是权威定义，本文件只负责文案，
  /// 所以这里不 import 它，免得纯文案文件被拖进业务依赖）。
  static String get alarmLimitReached =>
      t('每个班次最多 6 个闹钟', 'Up to 6 alarms per shift');
```

- [ ] **Step 4: 编辑器改造**

`app/lib/features/calendar/schedule_editor_screen.dart` 的 `_classRow`，把「开关 + 一个时间块 + 小字」整段（Task 1 改过的那一段）换成列表：

```dart
            Row(
              children: [
                Expanded(child: Text(L10n.linkedAlarm, style: AppTokens.rowPrimary)),
                GlassSwitch(
                  key: Key('shift-alarm-switch-$index'),
                  value: c.alarmEnabled,
                  onChanged: (v) => setState(() => _classes[index] =
                      _editClass(_classes[index], alarmEnabled: v)),
                ),
              ],
            ),
            if (c.alarmEnabled) ...[
              const SizedBox(height: AppTokens.spaceSm),
              for (var k = 0; k < c.alarms.length; k++)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                  child: Row(
                    key: Key('shift-alarm-row-$index-$k'),
                    children: [
                      Expanded(
                        child: _timeChip(
                          context,
                          label: L10n.alarmTime,
                          minutes: c.alarms[k].minute,
                          valueText: alarmFallsOnPreviousDay(c, c.alarms[k])
                              ? L10n.clockPrevDay(formatClock(c.alarms[k].minute))
                              : null,
                          onPick: (m) => setState(() =>
                              _classes[index] = _editClass(_classes[index],
                                  alarms: [
                                    for (var j = 0; j < c.alarms.length; j++)
                                      j == k
                                          ? ShiftAlarm(
                                              minute: m,
                                              label: c.alarms[j].label)
                                          : c.alarms[j],
                                  ])),
                        ),
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                      SizedBox(
                        width: _alarmLabelFieldWidth,
                        child: _AlarmLabelField(
                          key: Key('shift-alarm-label-$index-$k'),
                          label: c.alarms[k].label,
                          onChanged: (v) => setState(() =>
                              _classes[index] = _editClass(_classes[index],
                                  alarms: [
                                    for (var j = 0; j < c.alarms.length; j++)
                                      j == k
                                          ? ShiftAlarm(
                                              minute: c.alarms[j].minute,
                                              label: v)
                                          : c.alarms[j],
                                  ])),
                        ),
                      ),
                      const SizedBox(width: AppTokens.spaceXs),
                      GlassDeleteButton(
                        compact: true,
                        onPressed: () => setState(() => _classes[index] =
                            _editClass(_classes[index], alarms: [
                              for (var j = 0; j < c.alarms.length; j++)
                                if (j != k) c.alarms[j],
                            ])),
                      ),
                    ],
                  ),
                ),
              // 每条的「前一天」小字：整组共用一句就够 —— 它讲的是规则
              // （上班 06:30，闹钟排在前一天 …），不是某一条的正文。
              if (c.alarms.any((a) => alarmFallsOnPreviousDay(c, a)))
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                  child: Text(
                    L10n.alarmPrevDayHint(
                        formatClock(c.startMinute!),
                        formatClock(c.alarms
                            .firstWhere((a) => alarmFallsOnPreviousDay(c, a))
                            .minute)),
                    style: AppTokens.microText.copyWith(color: muted),
                  ),
                )
              else if (c.startMinute == null)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                  child: Text(L10n.alarmNoStartHint,
                      style: AppTokens.microText.copyWith(color: muted)),
                ),
              if (c.alarms.length < maxAlarmsPerShift)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                  child: GlassActionButton(
                    variant: GlassActionVariant.secondary,
                    icon: const AppIcon(Icons.add_outlined),
                    label: L10n.addAlarm,
                    onPressed: () => setState(() {
                      _classes[index] = _editClass(_classes[index], alarms: [
                        ...c.alarms,
                        // 新的一条默认排在上一条之后一小时；第一条落到 08:00
                        // （与 `_timeChip` 没设过时的缺省一致）。
                        ShiftAlarm(
                            minute: c.alarms.isEmpty
                                ? toMinutes(8, 0)
                                : ((c.alarms.last.minute + 60) % 1440)),
                      ]);
                    }),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                  child: Text(L10n.alarmLimitReached,
                      style: AppTokens.microText.copyWith(color: muted)),
                ),
            ],
```

配套的三处：

1. 名字输入框自己持 controller 的小控件（**不要**把 controller 塞进编辑器状态：闹钟可以随时增删，班次下标 × 闹钟下标两层对账很容易漏一处，而漏了的表现是「改了名字没生效」或「名字串到别的闹钟上」，都不报错）。写进 `schedule_editor_screen.dart` 文件底部、`_editClass` 旁边：

```dart
/// 一条闹钟的名字输入框：自己持有 controller，初值由 [label] 给。
///
/// 用位置做 Key（`shift-alarm-label-<班次>-<序号>`）—— 删掉前面那条闹钟之后，
/// 同一格会换上**别人**的名字，所以必须靠 [didUpdateWidget] 把文本同步过去，
/// 否则界面上显示的是被删掉那条的名字（不报错，只是名字串了）。
class _AlarmLabelField extends StatefulWidget {
  const _AlarmLabelField({super.key, required this.label, required this.onChanged});

  final String? label;

  /// 已经 trim 过：空串一律当没填（用户敲了个空格不该变成「白班 · 」）。
  final ValueChanged<String?> onChanged;

  @override
  State<_AlarmLabelField> createState() => _AlarmLabelFieldState();
}

class _AlarmLabelFieldState extends State<_AlarmLabelField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.label ?? '');

  @override
  void didUpdateWidget(covariant _AlarmLabelField old) {
    super.didUpdateWidget(old);
    final next = widget.label ?? '';
    // 比的是 `_ctrl.text.trim()`：正在打字时下一个字符是空格，不该被当成
    // 「换了另一条闹钟」而把输入重置掉。
    if (next != old.label && next != _ctrl.text.trim()) {
      _ctrl.text = next;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctrl,
        onChanged: (v) => widget.onChanged(v.trim().isEmpty ? null : v.trim()),
        decoration: glassInputDecoration(context, L10n.alarmNameOptional,
                isDense: true)
            .copyWith(hintText: L10n.alarmNameHint),
      );
}
```
2. 常量：`static const double _alarmLabelFieldWidth = 120;`（与 `_abbrFieldWidth` 并列）。
3. `_setRest` 已经传 `clearAlarms: true`（Task 1 改的），切休班清空整组 —— 保持。

**布局注意**：这行在窄屏（小窗 200 宽）会被挤 —— 时间块 + 名字框 + 删除钮三件并排。名字框宽度是常量、`Expanded` 给时间块，所以最窄时时间块先被压扁。**这一条必须靠视觉工装出图确认**（Task 8），不能只看测试。

- [ ] **Step 5: 跑，绿 + 全量**

```bash
cd app && flutter test test/schedule_editor_test.dart && flutter analyze && flutter test
```

- [ ] **Step 6: 提交**

```bash
git add app/lib/core/l10n.dart app/lib/features/calendar/schedule_editor_screen.dart app/test/schedule_editor_test.dart
git commit -m "feat(editor): 班次闹钟改成可增删、可命名的列表（上限 6）"
```

---

### Task 7: 闹钟页与日历信息卡：多条闹钟的显示

**Files:**
- Modify: `app/lib/features/alarm/alarm_screen.dart`（「未来 30 天」每行列出当天全部闹钟）
- Modify: `app/lib/features/calendar/calendar_screen.dart`（`_alarmText` → 首条 + 等 N 个）
- Modify: `app/lib/data/app_repository.dart`（一个测试入口）
- Modify: `app/lib/core/l10n.dart`（信息卡那句）
- Test: `app/test/calendar_screen_test.dart`

**显示改动的眼睛在 Task 8**：闹钟页现在**一条 widget 测试都没有**（`grep -rln AlarmScreen test/` 为空），给它从零搭一套夹具（库 + prefs + 通道桩 + 那个 1 分钟的 `Timer.periodic`）不值当 —— 那一屏由视觉工装出图看（Task 8 加一条「闹钟页 · 两个闹钟」的屏），行为侧由 Task 2 的纯函数用例盯着。

**Interfaces:**
- Consumes：Task 1 的 `ShiftClass.alarms`、Task 2 的 `alarmFallsOnPreviousDay`
- Produces：`L10n.alarmFirstOfMany(String clock, int total)`

- [ ] **Step 1: 写失败测试**

`app/test/calendar_screen_test.dart` 加一条（它已经有「信息卡：班次名、时间、闹钟在同一行」那条，照它的查法写；**用班次下标而不是名字**选班次 —— 模板里的班次名按角色变，别赌它叫「白班」）：

```dart
  testWidgets('信息卡：一个班次多个闹钟时只写首条 + 「等 N 个」', (tester) async {
    final db = await _pumpCalendar(tester, 'four_crew_three_shift');
    // 给第一个班次塞三条闹钟，然后**逐天点过去找它** —— 不假定「今天」正好上
    // 这个班次（模板的周期第一个元素是什么、今天轮到谁，都不该写死在用例里）。
    await AppRepository(db).setClassAlarmsForTesting(0, const [
      ShiftAlarm(minute: 6 * 60 + 30, label: '起床'),
      ShiftAlarm(minute: 12 * 60 + 30, label: '午休'),
      ShiftAlarm(minute: 17 * 60 + 30),
    ]);
    final daysInMonth =
        DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day;
    var found = false;
    for (var d = 1; d <= daysInMonth && !found; d++) {
      await tester.tap(find.text('$d').first);
      await tester.pumpAndSettle();
      final line = _shiftLine(tester);
      if (line.contains('06:30')) {
        found = true;
        expect(line, contains('等 3 个'),
            reason: '卡片定高、这一行只有一行：铺开列三个时刻会把后面的内容挤掉');
      }
    }
    expect(found, isTrue, reason: '本月应当有上这个班次的日子，否则这条用例没有意义');

    await _disposeCalendar(tester);
  });
```

- [ ] **Step 2: 跑，确认红**

```bash
cd app && flutter test test/calendar_screen_test.dart --plain-name '多个闹钟'
```
Expected: FAIL —— `setClassAlarmsForTesting` 不存在。

- [ ] **Step 3: 文案**

`app/lib/core/l10n.dart`（接在 `alarmAt` 那一族后面）：

```dart
  /// 信息卡上「首条闹钟 + 还有几条」。卡片定高、这一行只有一行，
  /// 所以铺开列全部时刻会挤掉省略号后面的内容。
  static String alarmFirstOfMany(String clock, int total) =>
      t('闹钟 $clock 等 $total 个', 'Alarm $clock (+${total - 1})');
```

- [ ] **Step 4: 仓储测试入口**

`app/lib/data/app_repository.dart`：

```dart
  /// 测试专用：给**当前方案**第 [classIndex] 个班次（按 `order`）设一组闹钟，
  /// 顺带打开总开关。按下标而不是按名字取 —— 班次名是用户改得的，测试别赌它。
  Future<void> setClassAlarmsForTesting(
      int classIndex, List<ShiftAlarm> alarms) async {
    final rows = await (db.select(db.shiftClassRows)
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    if (classIndex < 0 || classIndex >= rows.length) return;
    final classId = rows[classIndex].id;
    await (db.update(db.shiftClassRows)..where((t) => t.id.equals(classId)))
        .write(const ShiftClassRowsCompanion(alarmEnabled: Value(true)));
    await (db.delete(db.shiftClassAlarms)..where((t) => t.classId.equals(classId)))
        .go();
    for (var k = 0; k < alarms.length; k++) {
      await db.into(db.shiftClassAlarms).insert(
            ShiftClassAlarmsCompanion.insert(
              classId: classId,
              order: k,
              minute: alarms[k].minute,
              label: Value(alarms[k].label),
            ),
          );
    }
  }
```

- [ ] **Step 5: 两处显示**

`app/lib/features/calendar/calendar_screen.dart` 的 `_alarmText`：

```dart
String _alarmText(ShiftClass t) {
  if (t.isRest) return L10n.restNoAlarm;
  if (!t.alarmEnabled || t.alarms.isEmpty) return L10n.alarmOff;
  final alarm = t.alarms.first;
  final clock = formatClock(alarm.minute);
  // 落在上班**前一天**的（00:00 上班的夜班）必须标出来：不标的话，这一行会跟
  // 前面的「00:00 – 08:00」读成同一天的两件事。
  final shown =
      alarmFallsOnPreviousDay(t, alarm) ? L10n.clockPrevDay(clock) : clock;
  // 多条的只写首条 + 「等 N 个」：这一行本来就是 maxLines: 1 + 省略号，
  // 铺开列全部时刻会把「其他班组」那些更重要的一句挤掉（卡片还是定高的）。
  return t.alarms.length == 1
      ? L10n.alarmAt(shown)
      : L10n.alarmFirstOfMany(shown, t.alarms.length);
}
```

`app/lib/features/alarm/alarm_screen.dart` 的 `_shiftAlarmEntryTile`（第 262-276 行那个右列）：

```dart
          // 一天里的每条闹钟各占一行（时间 + 可选名字），落在前一天的那条
          // 自己带一行「前一天」小字 —— 多条混排时，标记必须跟着各自那条走。
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final a in e.shift.alarms) ...[
                Text(
                  a.label == null || a.label!.trim().isEmpty
                      ? _fmt(a.minute)
                      : '${_fmt(a.minute)} ${a.label!.trim()}',
                  style: AppTokens.titleStrong,
                ),
                if (alarmFallsOnPreviousDay(e.shift, a))
                  Text(L10n.prevDay,
                      style: AppTokens.microText.copyWith(color: muted)),
              ],
            ],
          ),
```

- [ ] **Step 6: 跑，绿 + 全量**

```bash
cd app && flutter test test/calendar_screen_test.dart && flutter analyze && flutter test
```
Expected: PASS + 全绿。**特别看** `calendar_screen_test.dart` 里那两条定高用例（「点开某天：信息卡高度只由本月决定」「最满的一天也要装得进卡片」）：多闹钟**不许**把卡片顶高。

- [ ] **Step 7: 提交**

```bash
git add app/lib/core/l10n.dart app/lib/data/app_repository.dart app/lib/features/alarm/alarm_screen.dart app/lib/features/calendar/calendar_screen.dart app/test/
git commit -m "feat(ui): 闹钟页列出当天全部闹钟，信息卡写首条 + 等 N 个"
```

---

### Task 8: 视觉工装：把新界面放进屏单、出图看图

**Files:**
- Modify: `app/tool/visual/visual_screens.dart`
- Modify: `app/tool/visual/visual_harness.dart`（若需要新的造数据小工具）

**Interfaces:**
- Consumes：Task 6 / Task 7 的界面
- Produces：屏单里至少三条新屏（编辑器 1 个闹钟 / 3 个闹钟 / 上限态），并已「看过图」

- [ ] **Step 1: 加屏与造数据的 helper**

屏单在 `app/tool/visual/visual_screens.dart`（体例照它已有的 `02_editor` / `13_editor_midnight`：`build: (db) async { … ; return ScheduleEditorScreen(scheduleId: await currentScheduleId(db)); }`）。四条新屏：

```dart
  (
    slug: '20_editor_alarm_one',
    title: '编辑器 · 一个闹钟',
    build: (db) async {
      await makeAlarmShowcase(db, count: 1);
      return ScheduleEditorScreen(scheduleId: await currentScheduleId(db));
    },
    needsOnboardingPrefs: false,
  ),
  (
    slug: '21_editor_alarm_three',
    title: '编辑器 · 三个闹钟（其中一条带名字）',
    build: (db) async {
      await makeAlarmShowcase(db, count: 3);
      return ScheduleEditorScreen(scheduleId: await currentScheduleId(db));
    },
    needsOnboardingPrefs: false,
  ),
  (
    slug: '22_editor_alarm_max',
    title: '编辑器 · 闹钟到上限（6 个）',
    build: (db) async {
      await makeAlarmShowcase(db, count: maxAlarmsPerShift);
      return ScheduleEditorScreen(scheduleId: await currentScheduleId(db));
    },
    needsOnboardingPrefs: false,
  ),
  (
    slug: '23_alarm_two_per_shift',
    title: '闹钟页 · 一个班次两个闹钟（含「前一天」）',
    build: (db) async {
      await makeAlarmShowcase(db, count: 2, nightShift: true);
      return const AlarmScreen();
    },
    needsOnboardingPrefs: false,
  ),
```

造数据的 helper 写进 `app/tool/visual/visual_harness.dart`，体例照 `makeMidnightShiftCurrent`（第 378 行起 —— 它也是先 `AppRepository(db).saveSchedule(...)` 再把某套方案设为当前）：

```dart
/// 视觉工装专用：把当前方案里某个班次改成带 [count] 个闹钟，其中一个带名字。
///
/// [nightShift] 为真时改用「零点班」形状（00:00–08:00、起床 23:00）：只有这种形状
/// 才拍得出「前一天」那行小字与「班中补觉」两条混排的样子。
///
/// 闹钟列表是新界面 —— 令牌守门只能看出字面量，看不出「一行挤没挤、标记跟没跟着
/// 走」，只有出图能看，所以这条必须进屏单（AGENTS.md 的规矩）。
Future<void> makeAlarmShowcase(
  AppDatabase db, {
  required int count,
  bool nightShift = false,
}) async {
  final today = dateOnly(DateTime.now());
  await AppRepository(db).saveSchedule(
    name: nightShift ? '零点班 · 两条闹钟' : '白班 · 两条闹钟',
    anchorDate: today,
    classes: [
      ShiftClass(
        name: nightShift ? '零点班' : '白班',
        abbr: nightShift ? '零' : '白',
        startMinute: nightShift ? 0 : 8 * 60,
        endMinute: nightShift ? 8 * 60 : 20 * 60,
        color: 0xFF7A5CFF,
        alarmEnabled: true,
        alarms: [
          for (var k = 0; k < count; k++)
            ShiftAlarm(
              // 零点班那套刻着用户的例子：起床 23:00（前一天）+ 班中 03:00（当天）
              minute: nightShift
                  ? (k == 0 ? 23 * 60 : 3 * 60)
                  : [6 * 60 + 30, 12 * 60 + 30, 17 * 60 + 30, 22 * 60, 5 * 60, 9 * 60][k % 6],
              label: k == 1 ? '午休' : (k == 0 ? '起床' : null),
            ),
        ],
      ),
      const ShiftClass(name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4),
    ],
    cycle: const [0, 0, 1],
    makeCurrent: true,
    teamCount: 1,
    teamNames: L10n.defaultTeamNames(1),
    ourTeamIndex: 0,
    teamOffsets: const [0],
  );
}
```
（`cycle: [0, 0, 1]` 让今天必落在上班那个班次上 —— 闹钟页才有行可看。）

- [ ] **Step 2: 出图**

```bash
cd app && flutter test tool/visual/render_screens_test.dart
```
Expected: 新四条屏 × 工装自带的多变体（深浅 × 中英 × 各尺寸）各出一张 PNG，落在 `app/build/visual/`（`kVisualOutDir`）。**`failOnOverflow` 会在渲染时就拦住溢出** —— 界面上有东西被挤爆的话这一步就红了，不用等看图。

- [ ] **Step 3: 看图（**这一步不能跳**）**

逐张看新出的图（`app/build/visual/2*_*.png`），重点：

1. `21_editor_alarm_three`：时间块 + 名字框 + 删除钮在一行里**没有被挤扁、没有重叠**；**窄屏那张（小窗尺寸）尤其要看** —— 三个控件并排是这一屏最挤的地方。
2. `22_editor_alarm_max`：没有「添加闹钟」按钮，只有一行小字说明；六个闹钟行不溢出卡片。
3. `23_alarm_two_per_shift`：两条闹钟各占一行、各自带自己的「前一天」小字（23:00 有、03:00 没有）。
4. 深浅两套主题、中英两种语言各扫一遍（工装会自动出这些变体）。

发现问题就回 Task 6 / Task 7 改布局，再来一遍。**图没过就不算完。**

- [ ] **Step 4: 提交**

```bash
git add app/tool/visual/
git commit -m "test(visual): 编辑器闹钟列表（1 / 3 / 上限态）进屏单"
```

---

### Task 9: 收尾 —— 文档、版本号、更新日志、真机验收、发布

**Files:**
- Modify: `AGENTS.md`（schemaVersion、Drift 表清单、版本历史、一条坑）
- Modify: `PRODUCT_SPEC.md`（班次闹钟那条现状描述）
- Modify: `app/pubspec.yaml`、`app/lib/core/app_info.dart`（版本号）
- Modify: `app/lib/features/profile/app_dialogs.dart`（`_changelogZh` / `_changelogEn`）

**Interfaces:**
- Consumes：Task 1-8 的全部产物
- Produces：一个可发布的版本

- [ ] **Step 1: 问用户目标版本号（**不许自己定 X.Y**）**

```
要发的版本号是多少？X.Y 由你定，我只动末位 Z（比如 0.9.2）。
如果这轮要升 X.Y（例如 0.10.0），也告诉我，我照改。
```

- [ ] **Step 2: 文档**

`AGENTS.md`：`当前 schemaVersion = 9` → `10`；Drift 表清单加 `ShiftClassAlarms`（班次闹钟：复合主键 `{classId, order}`，`order` 同时是原生 id 的序号）；版本历史行追加新版本；在「关键决策与坑」里加一条：

```markdown
- **班次闹钟的数量上限是 id 空间算出来的，不是产品口味**：原生 id = `序号 × 天数窗口 + 天数偏移`，
  天数窗口就是 `AlarmService._shiftDaysHorizon`（= `reschedule(days:)` 的缺省值 60），序号 = 闹钟在
  `ShiftClass.alarms` 里的下标。6 × 60 = 360 ≤ 400 —— 400 是 Kotlin 侧 `cancelAllNativeAlarms`
  的扫描上界（`MainActivity.kt:550`）。**改上限、改天数窗口、改扫描范围，三个一起改。**
  另一条：**重排绝不能重新编号**（否则每次打开 App 都换一批 id，用户设过的响铃记录错位），
  但**用户在编辑页里调整闹钟顺序会**换号 —— 那是可接受的，编辑之后必然重排。
```

`PRODUCT_SPEC.md`：把「班次闹钟」那条现状描述从「一个班次一个闹钟」改成「一个班次最多 6 个闹钟（可命名）」，并写清「前一天 / 当天」的判定规则（照 spec §4.2 的原话）。

- [ ] **Step 3: 版本号与更新日志**

`app/pubspec.yaml` 的 `version:` 与 `app/lib/core/app_info.dart` 的 `appVersion` 同步改（`app_info_test.dart` 会盯着，两处不一致直接红）。`app_dialogs.dart` 的 `_changelogZh` / `_changelogEn` prepend 新版本、删掉最旧一条、保持 10 条（末位非 0 = 测试版，按「本版改了什么」原样写）。

- [ ] **Step 4: 全量验收**

```bash
cd app && flutter analyze && flutter test
git add -A && git commit -m "docs+chore: 版本号、更新日志与文档口径"
```

- [ ] **Step 5: 真机验收（**必须，不是可选**）**

构建并装到设备上（`adb` 在 `toolchain/android-sdk/platform-tools/adb.exe`）：

```bash
cd app && flutter build apk --release
$ADB install -r build/app/outputs/flutter-apk/app-release.apk
```

逐条验（**装上之后先关掉「版本更新」弹窗**，它会吃掉第一次点击）：

1. **老库迁移**：打开班次编辑页 —— 原来那个闹钟还在、钟点没变、开关状态没变。
2. **加第二个闹钟**：给白班加「午休 12:30」→ 保存 → 重进编辑页还在。
3. **闹钟页**：那个班次的每一行列出两个时刻；零点班的 19:30 带「前一天」小字。
4. **日历信息卡**：显示「闹钟 06:30 等 2 个」，卡片高度没变（与相邻日期来回点几下确认不跳）。
5. **响铃（关键）**：把白班的两个闹钟临时设到 2 分钟后与 4 分钟后，锁屏等两次 —— 两次都要**全屏响铃**，标题分别是「白班提醒」与「白班 · 午休」。验完改回去。
6. **按天关闹钟**：在闹钟页把某天关掉 → 那天两条都不响（重排后 `dumpsys alarm | grep shiftassistantpro` 的那一天没有条目）。

- [ ] **Step 6: 提交与发布**

```bash
git add -A && git commit -m "chore(release): <版本号>"
git push origin main
git tag v<版本号> && git push origin v<版本号>
```

发布（`GH_CONFIG_DIR` 必须指回真实 AppData，否则 gh 报未认证）：

```bash
export GH_CONFIG_DIR='C:\Users\Alec\AppData\Roaming\GitHub CLI'
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/release.ps1 -SkipConfirm
```

发布说明先写好 `tools/gh/release-notes-v<版本号>.md`（脚本只在文件不存在时才生成占位模板），格式照 v0.9.1 那份。

---

## 附：任务之间的依赖

```
Task 1（领域+调用点）
  ├─ Task 2（规则）───┐
  ├─ Task 3（表+迁移）─┤
  ├─ Task 4（模板）    │
  │                    ├─ Task 5（排定 id + 标题）
  │                    ├─ Task 6（编辑器 UI）── Task 8（视觉工装）
  │                    └─ Task 7（闹钟页 + 信息卡）
  └──────────────────────────────── Task 9（收尾+发布）
```

Task 1 是硬前置（它换的那个字段是所有任务的接口）；Task 2-4 彼此独立、可并行；Task 5-7 各自只依赖前面某一两个任务；Task 9 必须最后。
