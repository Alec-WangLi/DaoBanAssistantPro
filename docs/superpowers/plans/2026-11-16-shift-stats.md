# 统计页 + 请假/加班 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增按月 / 按年的统计页，并给「按天改班」补上请假 / 加班两种日级记录。

**Architecture:** 统计是纯函数（`domain/shift_stats.dart`）从 `ScheduleChain` + 日级 extras 现算，不落统计表；请假 / 加班存进新的全局日级表 `ShiftDayExtras`；夜班是班次上的标记 `isNight`；整天请假由 `planShiftAlarms` 统一抑制闹钟。

**Tech Stack:** Flutter / Riverpod / Drift / 纯 Dart 域层。

**Spec:** `docs/superpowers/specs/2026-11-16-shift-stats-design.md`

## Global Constraints

- 版本号只动 `Z` 与 `build`：`0.13.14+201`，两处同步（`app/pubspec.yaml` / `app/lib/core/app_info.dart`）。
- 用户可见文案一律走 `L10n`；界面只引用 `AppTokens`，不写字面量。
- 日期比较走 `dayNumber` / `dateOnly`；「现在」走 `appNow()`。
- 改 Drift 表后跑 `dart run build_runner build`（**不带** `--delete-conflicting-outputs`）。
- 不跑 `dart format`；不并发跑 `flutter test`。
- 单文件 ≤800 行。
- 收尾必须有本回合原始输出：`flutter analyze` 0 error / 0 warning、`flutter test` 尾行 `+N`。

## Review Focus

- **`endMinute` 的三种形态**：累计（1920）、回绕（510 且上班 1230）、正好 1440。任一种算错都会让夜班 / 24 小时班工时静默偏差。
- **跨月 / 跨年夜班**：12/31 20:30–1/1 08:30 必须整段算在 12 月，不能两天各算一半或重复计。
- **空白表与未排班**：`shiftOn == null` 不等于「休息」；空白表也不能合成上班 / 休息。
- **整天请假的边界**：请假分钟数正好等于班次时长时，必须算出勤、且不排闹钟；少一分钟仍算出勤、闹钟照响。
- **窄窗 / 大字号**：统计页的 2×2 指标卡、年视图 12 行、请假弹层的加减行在 320 宽 + 最大字号下不溢出。

---

### Task 1: `DayExtra` 值类型

**Files:**
- Create: `app/lib/domain/day_extra.dart`
- Test: `app/test/day_extra_test.dart`

**Interfaces:**
- Produces: `enum DayExtraKind { leave, overtime }`；`class DayExtra { const DayExtra({int leaveMinutes = 0, int overtimeMinutes = 0}); bool get isEmpty; }`

- [ ] **Step 1: 写失败用例**

```dart
test('空值判定', () {
  expect(const DayExtra().isEmpty, isTrue);
  expect(const DayExtra(leaveMinutes: 1).isEmpty, isFalse);
  expect(const DayExtra(overtimeMinutes: 1).isEmpty, isFalse);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `tools/flutter-test.sh test/day_extra_test.dart`
Expected: FAIL（`day_extra.dart` 不存在）。

- [ ] **Step 3: 实现值类型**（带 `==` / `hashCode` / `toString`）

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: 提交**（`feat(stats): 日级请假/加班值类型`）

---

### Task 2: 统计域层

**Files:**
- Create: `app/lib/domain/shift_stats.dart`
- Test: `app/test/shift_stats_test.dart`

**Interfaces:**
- Consumes: `ScheduleChain`、`ShiftClass`、`DayExtra`。
- Produces:
  - `int? shiftDurationMinutes(ShiftClass c)`
  - `class ShiftStats`：`workDays / restDays / unscheduledDays / blankDays / missingTimeDays / normalMinutes / overtimeMinutes / leaveMinutes / fullLeaveDays / nightShiftDays / holidayWorkDays / longestWorkStreak / longestRestStreak / classDayCounts`；`totalMinutes`；`averageMinutesPerWorkDay`；`isEmpty`
  - `ShiftStats shiftStatsFor({required ScheduleChain? chain, required DateTime from, required DateTime to, Map<int, DayExtra> extras = const {}, bool Function(DateTime)? isHoliday})`

- [ ] **Step 1: 写失败用例**（覆盖 Review Focus 五项）

```dart
test('endMinute 三种形态都算对', () {
  expect(shiftDurationMinutes(_work(480, 1920)), 1440);
  expect(shiftDurationMinutes(_work(1230, 510)), 720);
  expect(shiftDurationMinutes(_work(480, 1440)), 960);
});
test('跨月夜班算在上班那天', () { /* 12/31 20:30–1/1 08:30，12 月工时 720，1 月 0 */ });
test('整天请假不计出勤、不重复减工时', () { /* 12h 班 + 12h 假 → workDays 0, leave 720, normal 0 */ });
test('部分请假仍算出勤', () { /* 12h 班 + 4h 假 → workDays 1, normal 480, leave 240 */ });
test('空白表不算休息、不算未排班', () { /* blankDays 1, restDays 0 */ });
test('未设时间的班次算出勤但工时 0，并记 missingTimeDays', () { /* ... */ });
test('节假日上班与夜班按出勤日统计', () { /* ... */ });
test('最长连班 / 连休在未排班处断开', () { /* ... */ });
test('平均工时在零出勤时返回 0', () { /* ... */ });
```

夹具用 `ShiftSchedule` + `ScheduleChain`，日期用 `kAnchor` 前后；节假日用注入的 `isHoliday` 桩，不读真实农历。

- [ ] **Step 2: 运行确认失败**

Run: `tools/flutter-test.sh test/shift_stats_test.dart`
Expected: FAIL（文件不存在）。

- [ ] **Step 3: 实现** `shiftDurationMinutes` 与 `shiftStatsFor`

- [ ] **Step 4: 运行确认通过**

Run: `tools/flutter-test.sh test/shift_stats_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

---

### Task 3: 日级数据表 / 迁移 / 仓库 / provider

**Files:**
- Modify: `app/lib/data/app_database.dart`（表 + schemaVersion 16 + `from < 16`）
- Modify: `app/lib/data/app_repository.dart`（读写 + provider + `clearAll`）
- Test: `app/test/shift_day_extras_test.dart`、`app/test/migration_v15_to_v16_test.dart`

**Interfaces:**
- Produces: `ShiftDayExtras` 表；`AppRepository.setDayExtra(int day, DayExtraKind kind, int minutes)`、`clearDayExtra(...)`、`Future<Map<int, DayExtra>> listDayExtras()`；`dayExtrasProvider = StreamProvider<Map<int, DayExtra>>`。

- [ ] **Step 1: 写失败用例**

```dart
test('写入 / 覆盖 / 清除', () async { /* set 4h leave → 8h leave → clear */ });
test('clearAll 清掉 extras', () async { /* ... */ });
test('v15 → v16：is_night 默认 0、新表存在、旧数据原样', () async { /* fixture */ });
```

迁移 fixture 只建 `shift_class_rows`（含 v15 的列），升级后断言 `is_night == 0`、`shift_day_extras` 可写。

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现表 + 迁移（`if (from < 16) { createTable; if (from >= 6) addColumn }`）+ 仓库 + provider**

- [ ] **Step 4: `dart run build_runner build`**

Run: `cd app && dart run build_runner build`
Expected: 生成成功，`app_database.g.dart` 更新。

- [ ] **Step 5: 运行确认通过**

- [ ] **Step 6: 提交**

---

### Task 4: 夜班标记贯通

**Files:**
- Modify: `app/lib/domain/shift_rotation.dart`（`ShiftClass.isNight`、`copyWith`、`==`、`defaultSchedule`）
- Modify: `app/lib/domain/shift_templates.dart`（`role == ShiftRole.night`）
- Modify: `app/lib/domain/schedule_template.dart`（JSON 编解码）
- Modify: `app/lib/data/app_database.dart`（已在 Task 3 加列；这里补 `toDomain`）
- Modify: `app/lib/data/app_repository.dart:156`（`toDomain`）、`:745/:759`（写入）
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`（`_editClass` + 开关行）
- Test: `app/test/shift_night_flag_test.dart`

**Interfaces:**
- Produces: `ShiftClass.isNight`（默认 false）；模板 JSON 的 `isNight`。

- [ ] **Step 1: 写失败用例**

```dart
test('内置模板的夜班角色自动标 isNight', () {
  final t = shiftTemplates.firstWhere((e) => e.id == 'four_two');
  expect(t.classes.any((c) => c.isNight), isTrue);
});
test('模板 JSON 旧数据缺 isNight 时为 false', () { /* decode 旧字符串 */ });
test('copyWith / == 带上 isNight', () { /* ... */ });
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现字段与各链路；编辑器在非休班时显示「夜班」开关（`GlassSwitch`，key `shift-night-switch-<index>`）**

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: 提交**

---

### Task 5: 整天请假抑制闹钟

**Files:**
- Modify: `app/lib/features/alarm/alarm_service.dart`
- Test: `app/test/alarm_leave_suppression_test.dart`

**Interfaces:**
- `planShiftAlarms(..., Map<int, int> leaveMinutes = const {})`
- `AlarmService.reschedule(..., Map<int, int> leaveMinutes = const {})`
- `rescheduleAll` 读 `repo.listDayExtras()`。

- [ ] **Step 1: 写失败用例**

```dart
test('请假分钟数 >= 班次时长时跳过该天', () { /* plans 为空 */ });
test('部分请假照常排', () { /* plans 非空 */ });
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现**：在 `planShiftAlarms` 拿到 `t` 后判 `leave >= shiftDurationMinutes(t)` 则 `continue`。

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: 提交**

---

### Task 6: 录入弹层与日历标记

**Files:**
- Create: `app/lib/features/calendar/day_extra_sheet.dart`
- Modify: `app/lib/features/calendar/shift_override_picker.dart`
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Test: `app/test/day_extra_sheet_test.dart`、`app/test/shift_override_picker_test.dart`

**Interfaces:**
- `showShiftOverridePicker` 新增返回 `ShiftOverrideChoice.leaveIntent()` / `.overtimeIntent()`。
- `Future<int?> showDayExtraSheet(BuildContext, {required DayExtraKind kind, required DateTime from, required DateTime to, required int? defaultMinutes, required bool hasExisting})`；返回 `null` = 取消，`0` = 整天（按天算），`>0` = 每天分钟数。
- 日历写入后调用 `replanAfterScheduleChange`。

- [ ] **Step 1: 写失败用例**

```dart
testWidgets('弹层返回整天哨兵 0', ...);
testWidgets('加减 30 分钟', ...);
testWidgets('有记录时可清除', ...);
testWidgets('窄窗 320 宽不溢出', ...);
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现弹层 + 两行动作 + 日历写入 + 格子农历前缀「假 / 加」+ 信息卡追加文字**

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: 提交**

---

### Task 7: 统计页与入口

**Files:**
- Create: `app/lib/features/stats/stats_screen.dart`、`app/lib/features/stats/stats_widgets.dart`
- Modify: `app/lib/features/calendar/calendar_screen.dart`（顶栏图标 + 跳转）
- Modify: `app/lib/core/l10n.dart`
- Test: `app/test/stats_screen_test.dart`

**Interfaces:**
- `StatsScreen` 是 `ConsumerWidget`，自取 `activeScheduleProvider` + `dayExtrasProvider`。

- [ ] **Step 1: 写失败用例**

```dart
testWidgets('默认打开本月，能切到年', ...);
testWidgets('空排班显示空态', ...);
testWidgets('指标卡显示工时 / 上班 / 休息 / 请假 / 加班', ...);
testWidgets('年视图点某月切回月视图', ...);
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现页面、L10n、入口替换**

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: 提交**

---

### Task 8: 视觉工装、文档、版本与交付

**Files:**
- Modify: `app/tool/visual/visual_screens.dart`
- Modify: `docs/decisions/schedule.md`、`docs/changelog/v0.13.md`
- Modify: 帮助页 / `site/index.html` / `README.md` / `PRODUCT_SPEC.md`
- Modify: `app/pubspec.yaml`、`app/lib/core/app_info.dart`、`app/lib/features/profile/app_dialogs.dart`
- Modify: `.github/workflows/ci.yml`（`EXPECTED_TESTS`）
- Create: `tools/gh/release-notes-v0.13.14.md`

- [ ] **Step 1: 屏单加 `stats_month` / `stats_year` / `stats_blank` / `day_extra_sheet`，出图**
- [ ] **Step 2: 更新文档与辅助信息（版本号、更新日志、帮助、site、README、SPEC）**
- [ ] **Step 3: 升版本 `0.13.14+201` 并同步 `app_info.dart`**
- [ ] **Step 4: 全套验证**

Run: `cd app && flutter analyze`
Expected: 0 error / 0 warning（允许既有 info）。

Run: `tools/flutter-test.sh`
Expected: 全绿；记下尾行 `+N`，同步 `EXPECTED_TESTS`。

Run: `cd app && flutter test tool/visual/`
Expected: 全绿；核对新屏出图。

- [ ] **Step 5: 构建 APK + 提交 + tag + 发布**

```bash
cd app && flutter build apk --release --target-platform android-arm64
cp build/app/outputs/flutter-apk/app-release.apk "../dist/倒班助手Pro-v0.13.14.apk"
git add -A && git commit -m "feat(stats): 统计页 + 请假/加班（v0.13.14）"
git tag v0.13.14 && git push origin beta && git push origin v0.13.14
```

然后写 `tools/gh/release-notes-v0.13.14.md`，跑 `tools/_run-release.ps1`（已设 `GH_CONFIG_DIR`）。

- [ ] **Step 6: 核对 Release 与 main 上的 `latest.json`**
