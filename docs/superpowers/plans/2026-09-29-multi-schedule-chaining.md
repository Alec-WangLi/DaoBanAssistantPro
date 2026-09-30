# 多排班表按日期衔接 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 每套排班方案可带一个生效时段（起 / 止，都可留空），日历、闹钟、桌面小组件**按天**取「那天归哪套」，翻历史看到的是当时的班。

**Architecture:** 「某天什么班」全 app 只有 `ShiftSchedule.shiftOn(date)` 一个入口，而闹钟（`planShiftAlarms`）与小组件（`buildWidgetSnapshot`）本来就逐天遍历 —— 所以**原生侧一个字都不改**，只换一个「按天回答」的源进去。为此把查询面抽成 `ShiftSource` 接口（只有 `shiftOn` 一个方法），`ShiftSchedule` 与新的 `ScheduleChain` 都实现它，调用点分不出单套与多套。解析规则**只有一处实现**（`ScheduleChain.scheduleOn`）：设了时段的方案里挑「覆盖那天、起点最晚」的那套；都没覆盖就用当前方案兜底。两列都可空 → 老库不改一行数据 → 没设过时段的用户行为一字不变。

**Tech Stack:** Flutter / Dart 3、Riverpod、Drift（SQLite，`build_runner` 代码生成）、纯 Dart 领域层（可直接 `dart test`）。

**Spec:** [docs/superpowers/specs/2026-09-29-multi-schedule-chaining-design.md](../specs/2026-09-29-multi-schedule-chaining-design.md)（计划在论证时一律回到这份 spec；每个任务都要读它相关的章节）

## Global Constraints

- **版本号形如 `X.Y.Z+build`：`X.Y` 由用户决定，AI 只能改最后一位 `Z`（以及 `build` 同步 +1）。** 每轮收尾时 `app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须一致（`app/test/app_info_test.dart` 把关）。
- **`flutter analyze` 必须 0 error / 0 warning**（约 4 条 info 可容忍）；**`flutter test` 必须全绿且只增不减**（当前 **450** 条）；视觉工装另算：`flutter test tool/visual/`（当前 **213** 条）。
- **绝对不许跑 `dart format`** —— 工具链里的新版是 tall-style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `flutter analyze`。
- **改 Drift 表后必须重生成**：`dart run build_runner build --delete-conflicting-outputs`。
- **测试版（末位 `Z ≠ 0`）在 `beta` 分支上做、提交、发布**；`main` 只在发正式版时合并。
- **日期比较一律走 `dayNumber` / `isSameDay`**，绝不直接比 `DateTime`（drift 读回来的是**本地** DateTime，存进去的是 UTC 纯日期，东八区差 8 小时）。日期算术一律 `DateTime(y, m, d + n)`，**不用 `Duration(days:)`**（夏令时）。
- **界面层只写角色令牌，不写字面量**（`fontSize:` / `fontWeight:` / `circular(<数字>)` / `Duration(milliseconds:)` / `Color(0x…)` / 间距不在 4px 栅格上都会被 `design_tokens_test` 打红）；新界面一律抄最近的同类件配方。
- **触觉只在「状态真的变了」时发**，且**不许给已经自动发过的控件再补一记**（`GlassSwitch` / `GlassSegment` / `GlassChoiceChip` / 四个选择器提交点，见 `core/haptics.dart` 顶上那份名单）；除 `core/haptics.dart` 外任何文件不许出现 `HapticFeedback.`。
- **新界面一律补进视觉工装屏单**（`app/tool/visual/visual_screens.dart`）—— 屏单是唯一会「看」的眼睛。
- **Kotlin 侧用户可见的中文一个字都不许有**（本计划不改 Kotlin，这条只是提醒别顺手在 Kotlin 里加东西）。
- 所有命令在 **`app/` 目录**下执行。

## Review Focus

这五类输入或失败模式是 spec 隐含、但单看某个任务的测试不一定照得出来的。它们的用例被分派到下面各自的任务里（每条都写明了落在哪个任务）：

1. **跨时段边界那一天的归属（闭区间端点）** —— `to` 那天算这套、`to + 1` 天算下一套。差一天是这类功能最典型的错法，而界面上只在翻到那一天时才看得出来。→ Task 1、Task 6。
2. **改了**非当前**方案的时段 / 班次之后，日历、闹钟、小组件会不会跟着变** —— 漏了「watch 整表」就全都不动，且**不报错**（与当年「覆盖表没挂 watch」完全同一条）。→ Task 3。
3. **一个月横跨两套方案时的信息卡高度与「本月统计」数字** —— 按下标计数会把两套的第 0 个班次算成同一个，数字错得看不出来；`showChips` 按月固定会让卡片高度装不下某些天。→ Task 5、Task 6。
4. **老库（两列全是 null）升级后的一切与升级前逐字一致** —— 这是整轮改动唯一不能出错的地方：出错的代价是所有现有用户看到的东西都变了。→ Task 2、Task 3。
5. **「按天改班」的覆盖要落在「那天所属的那套方案」名下，而且拖选跨边界时不能静默半生效** —— 覆盖表的主键是 `{scheduleId, day}`，`setDayOverrides` 从前写死「当前方案 id」；有了衔接之后，给属于**非当前**方案的那天调整班次会把记录记在错的方案名下：**既查不出来也不报错**，用户看到的是「改了班，日历纹丝不动」。→ Task 3（仓库层按天解析）、Task 10（界面拦住跨边界的那一段）。

---

## 文件结构

**新建**

| 文件 | 职责 |
|---|---|
| `app/lib/domain/schedule_chain.dart` | `ScheduleSpan`（方案 + 时段）、`ScheduleChain`（按天解析，**唯一实现**）、`overlappingSpans`（重叠提示用）。纯 Dart，可直接单测。 |
| `app/test/schedule_chain_test.dart` | 上一条的全套边界用例。 |
| `app/test/migration_v11_to_v12_test.dart` | v11 → v12：老方案原样、两列为 null、能写能读。 |
| `app/test/schedule_chain_repository_test.dart` | 装配多套、只有一套时与今天等价、时段变化时流重发。 |
| `app/test/calendar_chain_test.dart` | 跨边界那个月的界面：格子、信息卡、本月统计、拖选被拦。 |

**修改**

| 文件 | 改什么 |
|---|---|
| `app/lib/domain/shift_rotation.dart` | 新增 `abstract class ShiftSource`；`ShiftSchedule implements ShiftSource` + `label`。 |
| `app/lib/data/app_database.dart` | `ShiftScheduleRows` 加两列；`schemaVersion 11 → 12`；`onUpgrade` 加 `from < 12` 分支。 |
| `app/lib/data/app_repository.dart` | 新增 `ActiveSchedules`、`setScheduleSpan`、`getActiveSchedules`、`loadActiveSchedulesForTesting`；`watchActiveSchedule()` 从「只盯当前行」改成 watch 整表；`activeScheduleProvider` 的值类型换成 `ActiveSchedules?`。 |
| `app/lib/features/alarm/alarm_service.dart` | `planShiftAlarms` / `reschedule` / `rescheduleAll` 的入参从 `ShiftSchedule` 改成 `ShiftSource`。 |
| `app/lib/features/alarm/alarm_screen.dart` | 「未来 30 天」改用 chain。 |
| `app/lib/features/calendar/calendar_screen.dart` | 网格、信息卡班次行与「其他班组」、本月统计、`_monthHasOverrideHint`、切换弹窗、拖选拦住 —— 全部改按天解析。 |
| `app/lib/features/calendar/info_card_metrics.dart` | 入参换成 `ScheduleChain?`；`showChips` 逐日化。 |
| `app/lib/features/calendar/schedule_editor_screen.dart` | 新增「生效时段」一节（含校验、清除、保存、重叠提示）；`_load` / `_save` / `currentScheduleId`。 |
| `app/lib/features/calendar/schedule_management_screen.dart` | 每行副标题接上时段标签。 |
| `app/lib/features/home/home_shell.dart` | 启动重排与快照推送改传 chain。 |
| `app/lib/features/widget/widget_snapshot.dart` | 入参换成 `ScheduleChain?`；逐天 + 今日卡按 `scheduleOn(today)`。 |
| `app/lib/features/widget/widget_service.dart` | `push` 的入参跟着换。 |
| `app/lib/core/l10n.dart` | 时段相关文案。 |
| `app/tool/visual/visual_harness.dart` + `visual_screens.dart` | 新种子（第二套方案带时段、边界落在本月中间）+ 三屏。 |

**不改**：`WidgetRenderer.kt` 与整个 Kotlin 侧、`ShiftAlarmOverrides`（全局表，跨方案仍成立）、`CustomTemplates`（模板存结构，不含时段）、`clearAll` / `deleteSchedule`（删表逻辑不变）。

---

## Task 1: 领域层 —— `ShiftSource` 与 `ScheduleChain`

**Files:**
- Create: `app/lib/domain/schedule_chain.dart`
- Modify: `app/lib/domain/shift_rotation.dart`（加接口，加 `implements`）
- Test: `app/test/schedule_chain_test.dart`

**Interfaces:**
- Consumes: `ShiftSchedule` / `ShiftClass` / `dayNumber`（`domain/shift_rotation.dart`）
- Produces: `abstract class ShiftSource { ShiftClass? shiftOn(DateTime date); String get label; }`；`class ScheduleSpan({int? id, required ShiftSchedule schedule, DateTime? from, DateTime? to})` 带 `bool covers(DateTime day)`；`class ScheduleChain({List<ScheduleSpan> spans = const [], ShiftSchedule? fallback})` 实现 `ShiftSource`，带 `ShiftSchedule? scheduleOn(DateTime day)` / `bool get hasCycle` / `bool monthHasOverrideHint(DateTime month)` / `String get cacheKey`；`List<ScheduleSpan> overlappingSpans(List<ScheduleSpan> all, ScheduleSpan self)`

- [ ] **Step 1: 在 `shift_rotation.dart` 里加 `ShiftSource` 接口**

在 `class ShiftSchedule` 的文档注释**上方**插入：

```dart
/// 「某天什么班」的**唯一**查询面 —— 日历、闹钟、桌面小组件都只依赖它。
///
/// 抽出来是为了让「单套方案」与「按天衔接的多套方案」（`ScheduleChain`，
/// 见 `schedule_chain.dart`）在调用点**无法区分**：`planShiftAlarms` /
/// `AlarmService.reschedule` 从前收的是 `ShiftSchedule`，改成收这个接口之后
/// 传哪一边都对，而调用点拿到的就是「一个能回答某天什么班的东西」。
abstract class ShiftSource {
  /// 某天的班次；那天没有班次（空白表 / 无方案）返回 null。
  ShiftClass? shiftOn(DateTime date);

  /// 日志用的一行描述。**不是用户可见文案**（Kotlin 的日志串本来就是中文，
  /// 仓库既有惯例）。
  String get label;
}
```

然后把 `class ShiftSchedule {` 改成 `class ShiftSchedule implements ShiftSource {`，给已有的 `ShiftSchedule? shiftOn(DateTime date)` 上面加 `@override`，并在 `int get cycleLength => cycle.length;` **后面**加：

```dart
  @override
  String get label => name;
```

- [ ] **Step 2: 写失败的测试**

创建 `app/test/schedule_chain_test.dart`：

```dart
// app/test/schedule_chain_test.dart
//
// 「某天归哪套方案」的解析 —— 全是纯函数，边界比正例多。
//
// 这些函数错了**不会报错**：只会「某几天显示成另一套班表的班」，而且只有翻到
// 那一天才看得见。所以边界要逐条钉住：闭区间的两端、起点为空、终点为空、
// 重叠时的胜负、以及没有一套覆盖时的兜底。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/schedule_chain.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

/// 一套只有名字不同的方案 —— 断言时靠 name 分辨谁赢。
ShiftSchedule _sched(String name) => ShiftSchedule(
      name: name,
      anchorDate: DateTime.utc(2026, 1, 1),
      classes: [
        ShiftClass(name: '$name-白', abbr: '白', startMinute: 480, endMinute: 1080),
        ShiftClass(name: '$name-休', abbr: '休', isRest: true),
      ],
      // 周期 2 天：单数日白班、双数日休班（相对 anchor）。
      cycle: const [0, 1],
    );

DateTime _d(int y, int m, int day) => DateTime.utc(y, m, day);

ScheduleSpan _span(String name, {int id = 1, DateTime? from, DateTime? to}) =>
    ScheduleSpan(id: id, schedule: _sched(name), from: from, to: to);

void main() {
  group('ScheduleSpan.covers —— 闭区间', () {
    test('两端当天**都算**覆盖', () {
      final s = _span('A', from: _d(2026, 1, 1), to: _d(2026, 6, 30));
      expect(s.covers(_d(2026, 1, 1)), isTrue);
      expect(s.covers(_d(2026, 6, 30)), isTrue);
      // 关键的两个「差一天」
      expect(s.covers(_d(2025, 12, 31)), isFalse);
      expect(s.covers(_d(2026, 7, 1)), isFalse);
    });

    test('起点为空 = 不限起点；终点为空 = 一直持续', () {
      final open = _span('A', to: _d(2026, 6, 30));
      expect(open.covers(_d(1999, 1, 1)), isTrue);
      expect(open.covers(_d(2026, 7, 1)), isFalse);

      final forever = _span('A', from: _d(2026, 1, 1));
      expect(forever.covers(_d(2222, 1, 1)), isTrue);
      expect(forever.covers(_d(2025, 12, 31)), isFalse);
    });
  });

  group('ScheduleChain.scheduleOn —— 时段优先、当前方案兜底', () {
    test('没有任何时段 → 一律走 fallback（**老库行为一字不变**）', () {
      final chain = ScheduleChain(fallback: _sched('当前'));
      expect(chain.scheduleOn(_d(2020, 5, 5))!.name, '当前');
      expect(chain.scheduleOn(_d(2030, 5, 5))!.name, '当前');
    });

    test('一段覆盖 → 覆盖的那些天归它，其余归 fallback', () {
      final chain = ScheduleChain(
        spans: [_span('A', from: _d(2026, 1, 1), to: _d(2026, 6, 30))],
        fallback: _sched('当前'),
      );
      expect(chain.scheduleOn(_d(2026, 3, 15))!.name, 'A');
      expect(chain.scheduleOn(_d(2026, 6, 30))!.name, 'A'); // 闭区间
      expect(chain.scheduleOn(_d(2026, 7, 1))!.name, '当前'); // 差一天
    });

    test('两段不重叠 → 各归各的', () {
      final chain = ScheduleChain(spans: [
        _span('A', id: 1, from: _d(2026, 1, 1), to: _d(2026, 6, 30)),
        _span('B', id: 2, from: _d(2026, 7, 1)),
      ]);
      expect(chain.scheduleOn(_d(2026, 6, 30))!.name, 'A');
      expect(chain.scheduleOn(_d(2026, 7, 1))!.name, 'B');
    });

    test('两段重叠 → **起点晚的赢**（与列表顺序无关）', () {
      // 故意把晚起的那段放在**前面**，证明结论不靠装配顺序。
      final early = _span('早', id: 1, from: _d(2026, 1, 1));
      final late = _span('晚', id: 2, from: _d(2026, 7, 1));
      final a = ScheduleChain(spans: [late, early]);
      final b = ScheduleChain(spans: [early, late]);
      expect(a.scheduleOn(_d(2026, 9, 1))!.name, '晚');
      expect(b.scheduleOn(_d(2026, 9, 1))!.name, '晚');
      // 7/1 之前只有早的那段覆盖
      expect(a.scheduleOn(_d(2026, 3, 1))!.name, '早');
    });

    test('起点并列 → id 大的（后建的那套）赢', () {
      final chain = ScheduleChain(spans: [
        _span('先建', id: 3, from: _d(2026, 1, 1)),
        _span('后建', id: 9, from: _d(2026, 1, 1)),
      ]);
      expect(chain.scheduleOn(_d(2026, 5, 1))!.name, '后建');
    });

    test('起点为空的那段算「一直往前」，输给任何有起点的', () {
      final chain = ScheduleChain(spans: [
        _span('不限起点', id: 1, to: _d(2026, 12, 31)),
        _span('七月起', id: 2, from: _d(2026, 7, 1)),
      ]);
      expect(chain.scheduleOn(_d(2026, 3, 1))!.name, '不限起点');
      expect(chain.scheduleOn(_d(2026, 9, 1))!.name, '七月起');
    });

    test('没有一套覆盖、fallback 也是 null → null', () {
      final chain = ScheduleChain(spans: [_span('A', from: _d(2026, 1, 1))]);
      expect(chain.scheduleOn(_d(2025, 1, 1)), isNull);
    });

    test('scheduleIdOn：报出**那天归哪一套的行 id**（写按天覆盖要用）', () {
      final chain = ScheduleChain(
        spans: [
          _span('A', id: 11, from: _d(2026, 1, 1), to: _d(2026, 6, 30)),
          _span('B', id: 22, from: _d(2026, 7, 1)),
        ],
        fallback: _sched('当前'),
        fallbackId: 99,
      );
      expect(chain.scheduleIdOn(_d(2026, 3, 1)), 11);
      expect(chain.scheduleIdOn(_d(2026, 8, 1)), 22);
      // 时段之外 → 兜底那套的 id（老库恒走这一支，与从前一致）
      expect(chain.scheduleIdOn(_d(2025, 1, 1)), 99);
      // 完全没有方案 → null
      expect(ScheduleChain().scheduleIdOn(_d(2026, 1, 1)), isNull);
    });
  });

  group('ScheduleChain.shiftOn —— 真的问到那一套的班', () {
    test('边界两侧各返回**各自方案**的班次', () {
      final chain = ScheduleChain(spans: [
        _span('A', id: 1, from: _d(2026, 1, 1), to: _d(2026, 6, 30)),
        _span('B', id: 2, from: _d(2026, 7, 1)),
      ]);
      // 周期 2 天：anchor 起第 0 天=白、第 1 天=休。挑两天让两套的班级不同。
      final before = chain.shiftOn(_d(2026, 6, 30));
      final after = chain.shiftOn(_d(2026, 7, 1));
      expect(before!.name, startsWith('A-'));
      expect(after!.name, startsWith('B-'));
    });

    test('hasCycle：空白表不算，只要有**一套**有周期就为真', () {
      final blank = ScheduleChain(fallback: ShiftSchedule(
        name: '空白',
        anchorDate: DateTime.utc(2026, 1, 1),
        classes: const [ShiftClass(name: '休息', isRest: true)],
        cycle: const [],
      ));
      expect(blank.hasCycle, isFalse);
      expect(ScheduleChain(fallback: _sched('A')).hasCycle, isTrue);
      // 当前是空表，但链上有一张有周期的
      expect(
        ScheduleChain(spans: [_span('A', from: _d(2026, 1, 1))], fallback: null)
            .hasCycle,
        isTrue,
      );
    });
  });

  group('monthHasOverrideHint —— 逐天问「那天归哪套」', () {
    ShiftSchedule withOverride(String name, {required int day, required int idx}) {
      final base = _sched(name);
      return ShiftSchedule(
        name: base.name,
        anchorDate: base.anchorDate,
        classes: base.classes,
        cycle: base.cycle,
        dayOverrides: {dayNumber(_d(2026, month, day)): idx},
      );
    }

    const month = 9;

    test('覆盖记在归 A 的那天、而这个月归 B → false', () {
      final chain = ScheduleChain(spans: [
        ScheduleSpan(
            id: 1, schedule: withOverride('A', day: 1, idx: 0), from: _d(2026, 8, 1), to: _d(2026, 8, 31)),
        ScheduleSpan(
            id: 2, schedule: withOverride('B', day: 1, idx: 0), from: _d(2026, 9, 1)),
      ]);
      expect(chain.monthHasOverrideHint(DateTime.utc(2026, month, 1)), isFalse);
    });

    test('覆盖就在这个月里 → true', () {
      final chain = ScheduleChain(spans: [
        ScheduleSpan(
            id: 2, schedule: withOverride('B', day: 15, idx: 1), from: _d(2026, 9, 1)),
      ]);
      expect(chain.monthHasOverrideHint(DateTime.utc(2026, month, 1)), isTrue);
    });

    test('覆盖在**别的月**、同一套方案 → false（按月判定）', () {
      final chain = ScheduleChain(spans: [
        ScheduleSpan(
            id: 2, schedule: withOverride('B', day: 3, idx: 1), from: _d(2026, 10, 1)),
      ]);
      expect(chain.monthHasOverrideHint(DateTime.utc(2026, month, 1)), isFalse);
    });
  });

  group('overlappingSpans —— 只服务于那句提醒', () {
    test('首尾相接**不算**重叠', () {
      final a = _span('A', id: 1, from: _d(2026, 1, 1), to: _d(2026, 6, 30));
      final b = _span('B', id: 2, from: _d(2026, 7, 1));
      expect(overlappingSpans([a, b], a), isEmpty);
      expect(overlappingSpans([a, b], b), isEmpty);
    });

    test('真重叠 → 报出对方', () {
      final a = _span('A', id: 1, from: _d(2026, 1, 1), to: _d(2026, 8, 31));
      final b = _span('B', id: 2, from: _d(2026, 7, 1));
      expect(overlappingSpans([a, b], a).map((s) => s.schedule.name), ['B']);
      expect(overlappingSpans([a, b], b).map((s) => s.schedule.name), ['A']);
    });

    test('两端都空（不参与衔接）的既不算重叠、也不被报出', () {
      final none = _span('未参与', id: 1);
      final a = _span('A', id: 2, from: _d(2026, 1, 1));
      expect(overlappingSpans([none, a], a), isEmpty);
      expect(overlappingSpans([none, a], none), isEmpty);
    });
  });
}
```

- [ ] **Step 3: 跑测试，确认它失败**

```bash
cd app && flutter test test/schedule_chain_test.dart
```

预期：编译失败，`Target of URI doesn't exist: 'package:shiftassistantpro/domain/schedule_chain.dart'`。

- [ ] **Step 4: 实现 `domain/schedule_chain.dart`**

```dart
// app/lib/domain/schedule_chain.dart
//
// 多排班表按日期衔接：把「某天归哪套方案」这件事收敛到**一个**地方。
//
// 为什么单独一个文件：这条解析规则只要有两份实现，就迟早对不上，而症状是
// 「某几天显示成另一套班表的班」—— 不报错，且只有翻到那一天才看得见。
//
// 两条贯穿本文件的纪律：
//  · **日期比较一律走 `dayNumber`**（自 epoch 的天数）。透进来的日子可能是
//    UTC 纯日期、也可能带本地时分，而 `from`/`to` 由 drift 读回来是**本地**
//    DateTime —— 直接比 `DateTime` 在东八区就差 8 小时，边界那天静默判错。
//  · **三种「空」不能混**：两端都空 = 不参与衔接；只有 `to` = 不限起点；
//    只有 `from` = 一直持续。
library;

import 'shift_rotation.dart';

/// 一套方案 + 它的生效时段（**闭区间**，两端都可留空）。
class ScheduleSpan {
  const ScheduleSpan({this.id, required this.schedule, this.from, this.to});

  /// `shift_schedule_rows.id`。界面用来跳编辑器 / 删除 / 判重叠；
  /// **解析规则只用它当起点并列时的胜负判据**。
  final int? id;

  final ShiftSchedule schedule;

  /// null = 不限起点（一直往前）。**与「不参与衔接」不是一回事** —— 两端都空的
  /// 方案根本不会出现在 [ScheduleChain.spans] 里。
  final DateTime? from;

  /// null = 一直持续下去。
  final DateTime? to;

  /// 这一天在不在这个时段里。**闭区间：两端当天都算。**
  bool covers(DateTime day) {
    final n = dayNumber(day);
    if (from != null && n < dayNumber(from!)) return false;
    if (to != null && n > dayNumber(to!)) return false;
    return true;
  }

  @override
  String toString() =>
      'ScheduleSpan(${schedule.name}, $from..$to)';
}

/// 「某天归哪套方案」的**唯一**解析处（spec §2 ②）。
///
/// 规则：
///   1. 在 [spans] 里挑**覆盖那天、且起点最晚**的那一条；起点并列时取 id 大的
///      （后建的那套赢）。
///   2. 一条都没有 → [fallback]（当前方案，管所有没被时段覆盖的日子）。
///
/// **起点为空的按「一直往前」算**，也就是最不晚的那一档 —— 所以「～6月30日」
/// 这种只设终点的时段，会把 6/30 之前全占了，但输给任何有明确起点的段。
///
/// 结论**不依赖 [spans] 的顺序**（实现是显式比起点，不是「靠后的赢」）——
/// 装配时的排序只为了让界面与日志有个稳定顺序。
class ScheduleChain implements ShiftSource {
  const ScheduleChain({this.spans = const [], this.fallback, this.fallbackId});

  /// 参与衔接的方案（设了任一端时段的那些）。
  final List<ScheduleSpan> spans;

  /// 当前方案（`isCurrent`）。**老库全靠它**：两列都是 null 时 [spans] 为空，
  /// 每天都落到这里，行为与从前一字不差。
  final ShiftSchedule? fallback;

  /// 兜底那套方案的**行 id**。`ShiftSchedule` 是领域模型、不带 id，所以只能由
  /// 装配方（`assembleSchedules`）把它一起递进来。写按天覆盖要用（见 [scheduleIdOn]）。
  final int? fallbackId;

  /// 那天归哪套方案；连兜底都没有（还没有任何方案）时返回 null。
  ShiftSchedule? scheduleOn(DateTime day) => _resolve(day).$1;

  /// 那天归哪套方案的**行 id**。
  ///
  /// 写按天改班的覆盖必须用它，**不能用「当前方案 id」**：覆盖表的主键是
  /// `{scheduleId, day}`，把属于另一套方案的那天记在当前方案名下 —— 那条覆盖
  /// 既不会生效、也不会报错，用户看到的是「改了班、日历纹丝不动」。
  /// 老库没有时段时它恒等于当前方案 id，与从前完全一致。
  int? scheduleIdOn(DateTime day) => _resolve(day).$2;

  (ShiftSchedule?, int?) _resolve(DateTime day) {
    ScheduleSpan? best;
    for (final s in spans) {
      if (!s.covers(day)) continue;
      if (best == null || _startsLater(s, best)) best = s;
    }
    if (best != null) return (best.schedule, best.id);
    return (fallback, fallbackId);
  }

  @override
  ShiftClass? shiftOn(DateTime day) => scheduleOn(day)?.shiftOn(day);

  /// 链上有没有「有周期」的方案。
  ///
  /// 空白表（跟随法定节假日、`cycle` 为空）不算 —— 桌面小组件据此决定画不画
  /// 空态提示（与从前 `!schedule.isBlank` 同一口径）。**注意不能只问兜底那套**：
  /// 当前方案可能是空白表，而链上另一套排得满满当当。
  bool get hasCycle =>
      spans.any((s) => !s.schedule.isBlank) ||
      (fallback != null && !fallback!.isBlank);

  /// 这个月里有没有被**按天改班**调过的日子。
  ///
  /// 日历信息卡的定高要用：班次行尾巴上那颗「已调班」胶囊只在被改过的那天画，
  /// 而卡片是**定高**的 —— 高度必须按**月**预留，按天算的话点一天高度变一次、
  /// 上面的网格跟着抖（`info_card_metrics.dart` 整篇就在消灭这件事）。
  ///
  /// **逐天问「那天归哪套、那套有没有覆盖这天」**：一个月可能横跨两套方案，
  /// 被改过的那天可能归另一套 —— 只看兜底那套的 `dayOverrides` 会漏。
  bool monthHasOverrideHint(DateTime month) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    for (var d = 1; d <= days; d++) {
      final date = DateTime(month.year, month.month, d);
      final s = scheduleOn(date);
      if (s != null && s.dayOverrides.containsKey(dayNumber(date))) return true;
    }
    return false;
  }

  /// 信息卡定高缓存键里代表「这条链」的那一段。
  ///
  /// 少了它就会出现「改了班次名、卡片高度没跟着重算」—— 旧高度可能装不下新内容，
  /// 而卡片装不下时**只在卡内静默滚动**（最后一行被裁掉）。
  String get cacheKey => [
        for (final s in spans)
          '${s.id}|${_sourceKey(s.schedule)}|'
              '${s.from?.millisecondsSinceEpoch}|${s.to?.millisecondsSinceEpoch}',
        'f:${_sourceKey(fallback)}',
      ].join(';');

  @override
  String get label {
    final names = [for (final s in spans) s.schedule.name];
    if (fallback != null) names.add(fallback!.name);
    return names.isEmpty ? '—' : names.join(' → ');
  }
}

/// 一套方案里**会影响信息卡高度**的那些特征（组名、班次简称、是否空白表）。
String _sourceKey(ShiftSchedule? s) => s == null
    ? '-'
    : '${s.name}|${s.teamCount}|${s.ourTeamIndex}|${s.isBlank}|'
        '${s.teamNames.join("/")}|${s.classes.map((c) => c.shortLabel).join("/")}';

/// [a] 的起点是否**晚于** [b] 的起点（并列时比 id，大的赢）。
///
/// 起点为空按「一直往前」算，也就是最不晚的 —— 所以它输给任何有起点的段。
bool _startsLater(ScheduleSpan a, ScheduleSpan b) {
  final af = a.from, bf = b.from;
  if (af == null && bf == null) return (a.id ?? 0) >= (b.id ?? 0);
  if (af == null) return false;
  if (bf == null) return true;
  final c = dayNumber(af).compareTo(dayNumber(bf));
  return c != 0 ? c > 0 : (a.id ?? 0) >= (b.id ?? 0);
}

/// [self] 之外的、与它时段重叠的那些方案（按 id 升序）。
///
/// 重叠**不是错误**：解析规则给的是确定答案（起点最晚的赢）。这条只服务于界面上
/// 那句提醒 —— 用户设完时段要有机会知道「这个月和另一套撞上了」。
///
/// **恰好首尾相接不算重叠**（`A.to + 1 天 == B.from` 是正常的衔接）。
/// 留空端按无穷处理；两端都空（不参与衔接）的直接跳过。
List<ScheduleSpan> overlappingSpans(List<ScheduleSpan> all, ScheduleSpan self) {
  bool live(ScheduleSpan s) => s.from != null || s.to != null;
  if (!live(self)) return const [];
  final out = <ScheduleSpan>[];
  for (final s in all) {
    if (identical(s, self)) continue;
    if (s.id != null && s.id == self.id) continue;
    if (!live(s)) continue;
    if (_overlaps(self, s)) out.add(s);
  }
  out.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
  return out;
}

bool _overlaps(ScheduleSpan a, ScheduleSpan b) {
  // 比真实日期大得多的哨兵，够到 22 世纪（`dayNumber` 是自 epoch 的天数）。
  const int far = 1 << 40;
  final aFrom = a.from == null ? -far : dayNumber(a.from!);
  final aTo = a.to == null ? far : dayNumber(a.to!);
  final bFrom = b.from == null ? -far : dayNumber(b.from!);
  final bTo = b.to == null ? far : dayNumber(b.to!);
  return aFrom <= bTo && bFrom <= aTo;
}
```

- [ ] **Step 5: 跑测试，确认全绿**

```bash
cd app && flutter test test/schedule_chain_test.dart
```

- [ ] **Step 6: 确认没有把别处带崩**

```bash
cd app && flutter analyze && flutter test
```

预期：analyze 0 issue；450 条全绿（这一步只是加了一个接口与一个新文件，`ShiftSchedule` 的行为一字未改）。

- [ ] **Step 7: 提交**

```bash
git add app/lib/domain/schedule_chain.dart app/lib/domain/shift_rotation.dart \
        app/test/schedule_chain_test.dart
git commit -m "feat(schedule): 按天解析的领域层（ShiftSource + ScheduleChain）"
```

---

## Task 2: schema 11 → 12（两列 + 迁移）

**Files:**
- Modify: `app/lib/data/app_database.dart`（两列、`schemaVersion`、`onUpgrade`）
- Create: `app/test/migration_v11_to_v12_test.dart`

**Interfaces:**
- Produces: `ShiftScheduleRow.effectiveFrom` / `.effectiveTo`（`DateTime?`）、`ShiftScheduleRowsCompanion` 上的同名可空字段；`AppDatabase.schemaVersion == 12`

- [ ] **Step 1: 写失败的测试**

先照仓库惯例找一个现成的迁移 fixture 抄骨架：

```bash
cd app && ls test/migration_*.dart && sed -n '1,60p' test/migration_v10_to_v11_test.dart
```

然后创建 `app/test/migration_v11_to_v12_test.dart`（下面的 `_v11Ddl` 要与 `migration_v10_to_v11_test.dart` 里的做法同源 —— 它建的是 **v11 形态**的库：把 v11 之前所有表的 DDL 都建出来，再手工把 `schema_version` 设成 11）：

```dart
// app/test/migration_v11_to_v12_test.dart
//
// v11 → v12：给 shift_schedule_rows 加两个**可空**的时段列。
//
// 这一版是「老库行为一字不变」的全部依据，所以要点比正例多：
// 老方案的行数与 isCurrent 原样、两列都是 null（= 不参与衔接）、能写能读。
//
// ⚠️ 日期一律走 `dayNumber` / `isSameDay` 比 —— drift 读回来的是**本地** DateTime，
// 存进去的是 UTC 纯日期，直接比 DateTime 在东八区就差 8 小时。
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_database.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

/// v11 形态的库：只建这张测试关心的那几张表，行数按需要种。
///
/// **必须**包含 `shift_schedule_rows`（本版的 `addColumn` 打的就是它）以及
/// `onUpgrade` 倒序链上更早分支会碰到的表 —— 迁移分支一律按**倒序**跑，
/// 「谁碰了什么表，所有更早版本的迁移 fixture 就都得有那张表」。
Future<AppDatabase> _openV11({required List<String> scheduleNames}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.customStatement('''
    CREATE TABLE shift_schedule_rows (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      anchor_date INTEGER NOT NULL,
      is_current INTEGER NOT NULL DEFAULT 0,
      team_count INTEGER NOT NULL DEFAULT 4,
      team_names TEXT NOT NULL DEFAULT '一班,二班,三班,四班',
      our_team_index INTEGER NOT NULL DEFAULT 0,
      team_offsets TEXT NOT NULL DEFAULT ''
    )''');
  await db.customStatement('''
    CREATE TABLE shift_class_rows (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      schedule_id INTEGER NOT NULL, "order" INTEGER NOT NULL,
      name TEXT NOT NULL, abbr TEXT NULL,
      start_minute INTEGER NULL, end_minute INTEGER NULL,
      is_rest INTEGER NOT NULL DEFAULT 0,
      color INTEGER NOT NULL DEFAULT 4284186623,
      alarm_enabled INTEGER NOT NULL DEFAULT 0
    )''');
  await db.customStatement('''
    CREATE TABLE shift_cycle_rows (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      schedule_id INTEGER NOT NULL, "order" INTEGER NOT NULL,
      class_id INTEGER NOT NULL
    )''');
  // 迁移链上更早的分支会碰到的表（v10 的闹钟表、v9 的模板、v8 的按天改班、
  // v5 的按天关闹钟、v3 的自定义闹钟、以及 v7 加过列的 schedule_events）。
  await db.customStatement('''
    CREATE TABLE shift_class_alarms (
      class_id INTEGER NOT NULL, "order" INTEGER NOT NULL,
      minute INTEGER NOT NULL, label TEXT NULL,
      PRIMARY KEY (class_id, "order")
    )''');
  await db.customStatement('''
    CREATE TABLE shift_day_overrides (
      schedule_id INTEGER NOT NULL, day INTEGER NOT NULL,
      class_id INTEGER NOT NULL, PRIMARY KEY (schedule_id, day)
    )''');
  await db.customStatement('''
    CREATE TABLE custom_templates (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
      classes TEXT NOT NULL, cycle TEXT NOT NULL, team_count INTEGER NOT NULL,
      team_offsets TEXT NOT NULL, created_at INTEGER NOT NULL
    )''');
  await db.customStatement('''
    CREATE TABLE shift_alarm_overrides (
      day INTEGER NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
      PRIMARY KEY (day)
    )''');
  await db.customStatement('''
    CREATE TABLE custom_alarms (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      hour INTEGER NOT NULL, minute INTEGER NOT NULL,
      repeat_type INTEGER NOT NULL DEFAULT 1, once_date INTEGER NULL,
      weekdays INTEGER NOT NULL DEFAULT 0,
      enabled INTEGER NOT NULL DEFAULT 1
    )''');
  await db.customStatement('''
    CREATE TABLE schedule_events (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL,
      date INTEGER NOT NULL, time_minute INTEGER NULL,
      advance_remind_minutes INTEGER NULL,
      is_completed INTEGER NOT NULL DEFAULT 0,
      alarm_enabled INTEGER NOT NULL DEFAULT 0,
      series_id INTEGER NULL, created_at INTEGER NOT NULL
    )''');
  await db.customStatement('''
    CREATE TABLE recurring_series_rows (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL,
      time_minute INTEGER NULL, advance_remind_minutes INTEGER NULL,
      alarm_enabled INTEGER NOT NULL DEFAULT 0,
      repeat_type INTEGER NOT NULL DEFAULT 0,
      weekdays INTEGER NOT NULL DEFAULT 0,
      month_day INTEGER NOT NULL DEFAULT 1,
      start_date INTEGER NOT NULL, skip_through INTEGER NULL,
      enabled INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL
    )''');

  for (var i = 0; i < scheduleNames.length; i++) {
    await db.customStatement(
      "INSERT INTO shift_schedule_rows (name, anchor_date, is_current) "
      "VALUES ('${scheduleNames[i]}', ${DateTime.utc(2026, 1, 1).millisecondsSinceEpoch}, ${i == 0 ? 1 : 0})",
    );
  }
  await db.customStatement('PRAGMA user_version = 11');
  return db;
}

void main() {
  test('v11 → v12：老方案原样保留、两列都是 null、isCurrent 不变', () async {
    final db = await _openV11(scheduleNames: ['四班两倒', '备选']);
    addTearDown(db.close);

    await db.customStatement('PRAGMA user_version = 11');
    // 触发迁移
    await db.customSelect('SELECT COUNT(*) AS c FROM shift_schedule_rows').get();

    final rows = await (db.select(db.shiftScheduleRows)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    expect(rows.length, 2);
    expect(rows[0].name, '四班两倒');
    expect(rows[0].isCurrent, isTrue);
    expect(rows[0].effectiveFrom, isNull);
    expect(rows[0].effectiveTo, isNull);
    expect(rows[1].isCurrent, isFalse);
    expect(rows[1].effectiveFrom, isNull);
    expect(rows[1].effectiveTo, isNull);
  });

  test('v11 → v12：两列能写能读，且能再清回 null', () async {
    final db = await _openV11(scheduleNames: ['四班两倒']);
    addTearDown(db.close);
    await db.customSelect('SELECT COUNT(*) AS c FROM shift_schedule_rows').get();

    final id = (await db.select(db.shiftScheduleRows).getSingle()).id;
    await (db.update(db.shiftScheduleRows)..where((t) => t.id.equals(id))).write(
      ShiftScheduleRowsCompanion(
        effectiveFrom: Value(DateTime.utc(2026, 1, 1)),
        effectiveTo: Value(DateTime.utc(2026, 6, 30)),
      ),
    );
    var row = await (db.select(db.shiftScheduleRows)..where((t) => t.id.equals(id))).getSingle();
    expect(dayNumber(row.effectiveFrom!), dayNumber(DateTime(2026, 1, 1)));
    expect(dayNumber(row.effectiveTo!), dayNumber(DateTime(2026, 6, 30)));

    // **显式 Value(null) 能清回**：这正是「把时段改回不限」那条路径要的。
    await (db.update(db.shiftScheduleRows)..where((t) => t.id.equals(id))).write(
      const ShiftScheduleRowsCompanion(
        effectiveFrom: Value(null),
        effectiveTo: Value(null),
      ),
    );
    row = await (db.select(db.shiftScheduleRows)..where((t) => t.id.equals(id))).getSingle();
    expect(row.effectiveFrom, isNull);
    expect(row.effectiveTo, isNull);
  });
}
```

> 实施提示：如果 `_openV11` 的骨架与 `migration_v10_to_v11_test.dart` 里的写法有出入（比如它用 `db.customStatement` 之外的辅助），**以那份为准**把它抄成 v11 形态 —— 两份 fixture 只该差在 `PRAGMA user_version` 与新建表。

- [ ] **Step 2: 跑测试，确认它失败**

```bash
cd app && flutter test test/migration_v11_to_v12_test.dart
```

预期：`NoSuchMethodError` / 编译失败（`effectiveFrom` 这个 getter 还不存在）。

- [ ] **Step 3: 加两列、升 schemaVersion、加迁移分支**

`app/lib/data/app_database.dart`：在 `ShiftScheduleRows` 的 `teamOffsets` **下面**加：

```dart
  /// 生效时段起点（**闭区间**，纯日期，`dateOnly` 口径）；null = 不限起点。
  ///
  /// 与 [effectiveTo] 一起决定「某天归哪套方案」（见 `domain/schedule_chain.dart`）。
  /// **两端都空 = 不参与衔接** —— 这是老库（两列都是 null）行为一字不变的关键：
  /// 那种方案永远选不上，于是每天都落到「当前方案」兜底那条路。
  DateTimeColumn get effectiveFrom => dateTime().nullable()();

  /// 生效时段终点（**闭区间**，纯日期）；null = 一直持续下去。
  DateTimeColumn get effectiveTo => dateTime().nullable()();
```

把 `int get schemaVersion => 11;` 改成 `=> 12;`，并在 `onUpgrade` 的**最前面**（`if (from < 11)` 之前）插入：

```dart
          if (from < 12) {
            // 多排班表按日期衔接：给方案加两个**可空**的时段列。
            // 老行自动是 null（= 不参与衔接），于是老库的所见行为一字不变 ——
            // 迁移**不改任何既有行的数据**。
            //
            // 与 v10→v11 那次的区别：那次给 `schedule_events` 加列，而更早的
            // fixture 里**没有这张表**，所以三份 fixture 都被迫补了 DDL；
            // 这次的两列加在 `shift_schedule_rows` 上，那张表从 v1 就在，
            // 每个 fixture 都建过它 —— 所以不用补 DDL（`migration_v11_to_v12_test`
            // 仍要照惯例连带把全套迁移测试跑一遍确认）。
            await m.addColumn(shiftScheduleRows, shiftScheduleRows.effectiveFrom);
            await m.addColumn(shiftScheduleRows, shiftScheduleRows.effectiveTo);
          }
```

- [ ] **Step 4: 重生成 drift 代码**

```bash
cd app && dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 5: 跑新测试 + 全套迁移测试**

```bash
cd app && flutter test test/migration_ && flutter test test/migration_v11_to_v12_test.dart
```

预期：全绿。若某个更早的 fixture 报 `no such table`，说明它没建 `shift_schedule_rows` —— 按 `AGENTS.md`「迁移分支一律按倒序跑」那条给它补上 DDL（这是**已知的坑**，不是意外）。

- [ ] **Step 6: 全套**

```bash
cd app && flutter analyze && flutter test
```

- [ ] **Step 7: 提交**

```bash
git add app/lib/data/app_database.dart app/lib/data/app_database.g.dart \
        app/test/migration_v11_to_v12_test.dart
git commit -m "feat(db): 方案表加生效时段两列（schema 11 → 12）"
```

---

## Task 3: 装配 `ActiveSchedules` + `watchActiveSchedule` 改 watch 整表

**Files:**
- Modify: `app/lib/data/app_repository.dart`
- Test: `app/test/schedule_chain_repository_test.dart`

**Interfaces:**
- Consumes: `ScheduleChain` / `ScheduleSpan`（Task 1）、`effectiveFrom` / `effectiveTo`（Task 2）
- Produces:
  - `class ActiveSchedules { List<ActiveSchedule> all; ScheduleChain chain; ActiveSchedule? get current; ShiftSchedule? get currentDomain; int? get currentScheduleId; }`
  - `AppDatabase.watchActiveSchedule()` 的返回类型变成 `Stream<ActiveSchedules?>`
  - `AppRepository.setScheduleSpan(int id, {DateTime? from, DateTime? to})`、`getActiveSchedules()`、`loadActiveSchedulesForTesting()`
  - `activeScheduleProvider` 的值类型变成 `ActiveSchedules?`

- [ ] **Step 1: 写失败的测试**

创建 `app/test/schedule_chain_repository_test.dart`：

```dart
// app/test/schedule_chain_repository_test.dart
//
// 装配与流：
//  · 只有一套方案时（**今天的样子**）与从前等价 —— 这是「老库一字不变」的回归；
//  · 两套带时段时按天解析各归各的；
//  · 改**非当前**方案的时段，这条流必须重发（漏了 watch 整表就是「改完不动」，不报错）。
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

ShiftSchedule _sched(String name) => ShiftSchedule(
      name: name,
      anchorDate: DateTime.utc(2026, 1, 1),
      classes: [
        ShiftClass(name: '$name-白', abbr: '白', startMinute: 480, endMinute: 1080),
        ShiftClass(name: '$name-休', abbr: '休', isRest: true),
      ],
      cycle: const [0, 1],
    );

Future<int> _save(AppRepository repo, String name, {required bool current}) =>
    repo.saveSchedule(
      name: name,
      anchorDate: DateTime.utc(2026, 1, 1),
      classes: _sched(name).classes,
      cycle: const [0, 1],
      makeCurrent: current,
    );

DateTime _d(int y, int m, int day) => DateTime.utc(y, m, day);

void main() {
  late AppDatabase db;
  late AppRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppRepository(db);
  });
  tearDown(() => db.close());

  test('只有一套方案（今天的样子）→ 每天都归它，spans 为空', () async {
    await _save(repo, '四班两倒', current: true);
    final a = (await repo.getActiveSchedules())!;
    expect(a.all.length, 1);
    expect(a.chain.spans, isEmpty);
    expect(a.chain.scheduleOn(_d(2020, 1, 1))!.name, '四班两倒');
    expect(a.chain.scheduleOn(_d(2030, 1, 1))!.name, '四班两倒');
    expect(a.currentScheduleId, a.all.single.schedule.id);
  });

  test('两套各带时段 → 按天各归各的', () async {
    final aId = await _save(repo, 'A', current: true);
    final bId = await _save(repo, 'B', current: false);
    await repo.setScheduleSpan(aId, from: _d(2026, 1, 1), to: _d(2026, 6, 30));
    await repo.setScheduleSpan(bId, from: _d(2026, 7, 1));

    final s = (await repo.getActiveSchedules())!;
    expect(s.chain.spans.length, 2);
    expect(s.chain.scheduleOn(_d(2026, 6, 30))!.name, 'A');
    expect(s.chain.scheduleOn(_d(2026, 7, 1))!.name, 'B');
    // 时段之外仍然是兜底的当前方案
    expect(s.chain.scheduleOn(_d(2025, 1, 1))!.name, 'A');
  });

  test('setScheduleSpan 能把时段清回 null（= 不再参与衔接）', () async {
    final id = await _save(repo, 'A', current: true);
    await repo.setScheduleSpan(id, from: _d(2026, 1, 1));
    expect((await repo.getActiveSchedules())!.chain.spans.length, 1);
    await repo.setScheduleSpan(id);
    expect((await repo.getActiveSchedules())!.chain.spans, isEmpty);
  });

  test('按天覆盖跟着「那天归哪套」走 —— 记在**那天所属方案**名下', () async {
    final aId = await _save(repo, 'A', current: true);
    final bId = await _save(repo, 'B', current: false);
    await repo.setScheduleSpan(aId, from: _d(2026, 1, 1), to: _d(2026, 6, 30));
    await repo.setScheduleSpan(bId, from: _d(2026, 7, 1));

    final bRestId = (await repo.getScheduleDomain(bId))!.classes.last.id!;

    // 7/1 归 B，而**当前方案是 A**。修 `setDayOverrides` 之前，这里会把那条覆盖
    // 记在 A 名下 —— 既查不出来、也不报错，用户看到的是「改了班，日历纹丝不动」。
    await repo.setDayOverrides([_d(2026, 7, 1)], classId: bRestId);

    final row = await db.select(db.shiftDayOverrides).getSingle();
    expect(row.scheduleId, bId);
    expect(
      (await repo.getActiveSchedules())!.chain.shiftOn(_d(2026, 7, 1))!.isRest,
      isTrue,
      reason: '覆盖没生效 = 记到错的方案名下了',
    );
  });

  test('clearDayOverrides 同样按天找方案（否则撤不回来）', () async {
    final aId = await _save(repo, 'A', current: true);
    final bId = await _save(repo, 'B', current: false);
    await repo.setScheduleSpan(aId, from: _d(2026, 1, 1), to: _d(2026, 6, 30));
    await repo.setScheduleSpan(bId, from: _d(2026, 7, 1));
    final bRestId = (await repo.getScheduleDomain(bId))!.classes.last.id!;

    await repo.setDayOverrides([_d(2026, 7, 1)], classId: bRestId);
    await repo.clearDayOverrides([_d(2026, 7, 1)]);

    expect(await db.select(db.shiftDayOverrides).get(), isEmpty);
    expect(
      (await repo.getActiveSchedules())!.chain.shiftOn(_d(2026, 7, 1))!.name,
      startsWith('B-'),
    );
  });

  test('改**非当前**方案的时段 → watchActiveSchedule 重发', () async {
    await _save(repo, 'A', current: true);
    final bId = await _save(repo, 'B', current: false);

    final seen = <int>[];
    final sub =
        db.watchActiveSchedule().listen((s) => seen.add(s!.chain.spans.length));
    await Future<void>.delayed(const Duration(milliseconds: 20)); // 等首帧
    expect(seen.last, 0);

    await repo.setScheduleSpan(bId, from: _d(2026, 7, 1));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(seen.last, 1, reason: '改非当前方案不重发 = 日历/闹钟/小组件全不动');
  });
}
```

> 顶部 import 需要 `package:drift/drift.dart`（用了 `db.select(db.shiftDayOverrides)`）—— 既有测试文件里 `hide isNull` 那种写法也照抄，免得 `isNull` 与 `flutter_test` 的重名。

- [ ] **Step 2: 跑测试，确认它失败**

```bash
cd app && flutter test test/schedule_chain_repository_test.dart
```

预期：编译失败（`getActiveSchedules` / `setScheduleSpan` 不存在，`ActiveSchedules` 未定义）。

- [ ] **Step 3: 加 `ActiveSchedules`**

`app/lib/data/app_repository.dart`，在 `class ActiveSchedule` **后面**（`toDomain` 之后、`}` 之前的位置不行 —— 放在 `ActiveSchedule` 整个类之后）：

```dart
/// 时间线上的全部方案（已装配成领域模型）+ 按天解析面。
///
/// 与单套的 [ActiveSchedule] 是两个类型，别混：编辑器 / 管理页 / 模板那边要的是
/// **某一套**（按 id 查，见 `getScheduleDomain`），而日历 / 闹钟 / 小组件要的是
/// [chain] —— 「一个能回答某天什么班的东西」。
class ActiveSchedules {
  const ActiveSchedules({required this.all, required this.chain});

  /// 全部方案（按 id 升序）。装配 [chain] 的原料，界面要「列出所有方案」时也用它。
  final List<ActiveSchedule> all;

  /// 按天解析面。
  final ScheduleChain chain;

  /// 当前方案（`isCurrent`）。没有就返回 null。
  ActiveSchedule? get current {
    for (final a in all) {
      if (a.schedule.isCurrent) return a;
    }
    return null;
  }

  /// 当前方案的领域模型。
  ShiftSchedule? get currentDomain => current?.toDomain();

  /// 当前方案的行 id。
  ///
  /// 单拎出来是因为有三处（编辑器的「新建」路径、管理页的「当前」标记、切换弹窗的
  /// 选中态）都要它，各写一遍 `current?.schedule.id` 迟早写歪。
  int? get currentScheduleId => current?.schedule.id;
}
```

在文件顶部 import 区加：

```dart
import '../domain/schedule_chain.dart';
```

- [ ] **Step 4: 改 `watchActiveSchedule()` 与装配**

把 `app_database.dart` 里 `AppDatabaseQueries` 的 `watchActiveSchedule()` **整体替换**成下面这样（`_loadChildren` 与 `loadActiveScheduleForTesting` 保留不动）：

```dart
  /// 监听**全部**排班方案（含各自的班次、闹钟、周期、按天覆盖），装配成
  /// [ActiveSchedules]（响应式）。
  ///
  /// **必须 watch 整张方案表 + 两张子表**：
  ///  · 从前只 watch `isCurrent` 那一行（`watchSingleOrNull`）。要做「按天衔接」，
  ///    非当前方案也得装配进来，所以改成整表 —— 而且**改非当前方案的时段 / 班次
  ///    必须让这条流重发**，否则日历、闹钟、桌面小组件全都不动，**不报错**
  ///    （与当年「覆盖表没挂 watch」完全同一条，那次也是静默不刷新）。
  ///  · 覆盖表与闹钟表是独立的子表，各挂一条；班次 / 周期跟着方案行一起改
  ///    （`saveSchedule` 会 update 那一行），靠方案行的通知就够了。
  Stream<ActiveSchedules?> watchActiveSchedule() {
    final triggers = <Stream<Object?>>[
      select(shiftScheduleRows).watch(),
      select(shiftDayOverrides).watch(),
      select(shiftClassAlarms).watch(),
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
      final rows = await (select(shiftScheduleRows)
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
      if (rows.isEmpty) return null;
      return assembleSchedules(rows);
    });
  }

  /// 把一行行方案装配成 [ActiveSchedules]。
  ///
  /// 每套方案的 children 各查一次 —— [_loadChildren] 按 `scheduleId` 过滤，
  /// 天然是单套的（所以这里能直接复用，不必为多套另写一套查询）。
  ///
  /// 公开是为了给 `loadActiveSchedulesForTesting` 与迁移测试用；生产路径只走
  /// [watchActiveSchedule]。
  Future<ActiveSchedules> assembleSchedules(List<ShiftScheduleRow> rows) async {
    final all = <ActiveSchedule>[];
    for (final r in rows) {
      all.add(await _loadChildren(r));
    }
    ActiveSchedule? current;
    for (final a in all) {
      if (a.schedule.isCurrent) {
        current = a;
        break;
      }
    }
    // 参与衔接的 = **设了任一端时段**的那些。两端都空的不参与 —— 老库全是这种，
    // 于是它们全都落到 `fallback` 那条路，行为与从前一字不差（spec §3）。
    final spans = <ScheduleSpan>[
      for (final a in all)
        if (a.schedule.effectiveFrom != null || a.schedule.effectiveTo != null)
          ScheduleSpan(
            id: a.schedule.id,
            schedule: a.toDomain(),
            from: a.schedule.effectiveFrom,
            to: a.schedule.effectiveTo,
          ),
    ];
    // 排序只为了让界面与日志有稳定顺序 —— 解析规则自己显式比起点，不靠顺序。
    spans.sort((a, b) {
      final af = a.from, bf = b.from;
      if (af == null && bf == null) return (a.id ?? 0).compareTo(b.id ?? 0);
      if (af == null) return -1;
      if (bf == null) return 1;
      final c = dayNumber(af).compareTo(dayNumber(bf));
      return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
    });
    return ActiveSchedules(
      all: all,
      chain: ScheduleChain(
        spans: spans,
        fallback: current?.toDomain(),
        // 兜底那套的**行 id** 要单独递进去：`ShiftSchedule` 是领域模型、不带 id，
        // 而「写按天覆盖该记在哪套名下」得靠它（见 `ScheduleChain.scheduleIdOn`）。
        fallbackId: current?.schedule.id,
      ),
    );
  }
```

把 `loadActiveScheduleForTesting()` 的返回类型保持 `Future<ActiveSchedule?>`（既有迁移测试在用），实现改成：

```dart
  /// 测试专用：按当前方案装配一次 [ActiveSchedule]（不经过 Riverpod 流）。
  Future<ActiveSchedule?> loadActiveScheduleForTesting() async {
    final rows = await (select(shiftScheduleRows)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    if (rows.isEmpty) return null;
    return (await assembleSchedules(rows)).current;
  }

  /// 测试专用：装配整条链（迁移测试要验「两列为 null → 不参与衔接」）。
  Future<ActiveSchedules?> loadActiveSchedulesForTesting() async {
    final rows = await (select(shiftScheduleRows)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    if (rows.isEmpty) return null;
    return assembleSchedules(rows);
  }
```

> `_loadChildren(sched)` 里那个「只查当前方案」的门没有了 —— 它本来就按传入的 `sched.id` 过滤，直接复用。若它内部还引用了 `schedQuery`，一并去掉。

- [ ] **Step 5: 加 `setScheduleSpan` 与 `getActiveSchedules`**

在 `AppRepository` 里 `setCurrentSchedule` **后面**加：

```dart
  /// 写一套方案的**生效时段**（`null` = 不限 / 一直持续；两端都 `null` = 不参与衔接）。
  ///
  /// 单独一个方法而不是给 [saveSchedule] 加两个参数，理由是仓库里已有的先例
  /// （[setEventDate]）：`saveSchedule` 是**整行覆盖**，给它加两个可空参数意味着
  /// 每个调用点都得记得带上，漏一个就把用户设好的时段**静默清掉**了。而这里只碰
  /// 那两列，忘了传就是「不动」，错法安全得多。
  ///
  /// **必须显式写 `Value(...)`**：`Value.absent()` 表达不了「清成 null」，
  /// 那条路径（把设好的时段改回不限）会静默保留旧值。
  Future<void> setScheduleSpan(int id,
      {DateTime? from, DateTime? to}) async {
    await (db.update(db.shiftScheduleRows)..where((s) => s.id.equals(id))).write(
      ShiftScheduleRowsCompanion(
        effectiveFrom: Value(from == null ? null : dateOnly(from)),
        effectiveTo: Value(to == null ? null : dateOnly(to)),
      ),
    );
  }

  /// 立即读取整条链（重排闹钟用，避免读 Riverpod 流拿到旧值）。
  Future<ActiveSchedules?> getActiveSchedules() async {
    final rows = await (db.select(db.shiftScheduleRows)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    if (rows.isEmpty) return null;
    return db.assembleSchedules(rows);
  }
```

- [ ] **Step 6: 修 `setDayOverrides` / `clearDayOverrides`（衔接之后会静默失效的那个洞）**

两个方法现在都写死 `final scheduleId = await currentScheduleId();`，而**覆盖表的主键是 `{scheduleId, day}`**。有了时段衔接之后，用户可以在日历上选中属于**非当前**方案的那一天去「调整班次」—— 覆盖会记在当前方案名下，那条记录**既查不出来、也不报错**，用户看到的是「改了班，日历纹丝不动」。这与当年「覆盖表没挂 watch」同属一类：**落库成功、界面不动、没有错误**。

修法是**按天找方案**（`ScheduleChain.scheduleIdOn`），规则仍然只有那一处实现：

```dart
  /// 一次装配、逐天解析 —— 每写一天都重新装配一遍链是没必要的。
  ///
  /// **不能用「当前方案 id」**：有了时段衔接，「这天归哪套」与「哪套是当前」是
  /// 两件事。老库没有时段时 `scheduleIdOn` 恒等于当前方案 id，与从前完全一致。
  Future<void> setDayOverrides(List<DateTime> dates,
      {required int classId}) async {
    final schedules = await getActiveSchedules();
    if (schedules == null) return;
    final chain = schedules.chain;
    await db.transaction(() async {
      for (final date in dates) {
        final scheduleId = chain.scheduleIdOn(date);
        if (scheduleId == null) continue;
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

  Future<void> clearDayOverrides(List<DateTime> dates) async {
    final schedules = await getActiveSchedules();
    if (schedules == null) return;
    final chain = schedules.chain;
    await db.transaction(() async {
      for (final date in dates) {
        final scheduleId = chain.scheduleIdOn(date);
        if (scheduleId == null) continue;
        await (db.delete(db.shiftDayOverrides)
              ..where((t) =>
                  t.scheduleId.equals(scheduleId) &
                  t.day.equals(dayNumber(date))))
            .go();
      }
    });
  }
```

**签名一个都不改** —— 所以 `calendar_screen.dart` 的两处调用、`tool/visual/visual_harness.dart` 的种子、以及两个测试文件里的 16 处调用**一行都不用动**（它们全都在「只有一套方案」的库里，解析结果与从前的 `currentScheduleId()` 完全相同）。

> 多天跨两套方案时 `classId` 只属于其中一套 —— 那条路径由 Task 10 在界面上拦住（「请分开调整」），所以到不了这里。仓库这一层仍按天解析，是因为**删覆盖不需要 classId**，多天一起撤本来就该各自找各自的方案。

- [ ] **Step 7: 换 provider 的值类型**

`activeScheduleProvider`：

```dart
final activeScheduleProvider =
    StreamProvider<ActiveSchedules?>((ref) async* {
  final db = ref.watch(databaseProvider);
  await seedIfEmpty(db);
  yield* db.watchActiveSchedule();
});
```

- [ ] **Step 8: 跑编译错误清单，逐个改调用点**

```bash
cd app && flutter analyze
```

analyze 会把所有「`.toDomain()` 不存在」「`.schedule.id` 不存在」的地方指出来。这一刻**不要**去改行为，只做机械替换（生产代码）：

| 文件 | 原来 | 改成 |
|---|---|---|
| `home_shell.dart:165` | `.value?.toDomain()` | `.value?.chain` |
| `home_shell.dart:199` | `.valueOrNull?.toDomain()` | `.valueOrNull?.chain` |
| `alarm_screen.dart:71` | `.valueOrNull?.toDomain()` | `.valueOrNull?.chain` |
| `calendar_screen.dart:391` | `.valueOrNull?.toDomain()` | 见 Task 6（本步先临时写 `.valueOrNull?.chain.fallback`，Task 6 会整段重写） |
| `schedule_editor_screen.dart:127` | `active?.toDomain()` | `active?.currentDomain` |
| `schedule_editor_screen.dart:1640` | `?.schedule.id` | `?.currentScheduleId` |
| `schedule_management_screen.dart:24` | `current?.schedule.id` | `current?.currentScheduleId` |
| `calendar_screen.dart:791` | `current?.schedule.id` | `current?.currentScheduleId` |
| `tool/visual/visual_harness.dart` / `tool/visual/visual_screens.dart` / `tool/promo/render_promo_test.dart` | 同上规律 | 同上 |

`alarm_screen.dart` 里 `final schedule = async.valueOrNull?.toDomain();` 那一步后面还有 `if (schedule != null)` 与 `schedule.shiftOn(date)` —— 把变量名改成 `chain`（类型仍是 `ShiftChain?`，`shiftOn` 同名），Task 7 会补完其余。

> **`home_shell` / `alarm_screen` 这一步就能跑**：`ScheduleChain` 已实现 `shiftOn`，而 `planShiftAlarms` 此刻还收 `ShiftSchedule` —— 所以 `home_shell` 那处会编译不过。**Task 4 紧接着做**，中间不要试图单独跑通。

- [ ] **Step 9: 跑新测试**

```bash
cd app && flutter test test/schedule_chain_repository_test.dart test/day_override_repository_test.dart
```

`day_override_repository_test.dart` 那 8 处调用**必须原样全绿** —— 它钉的正是「覆盖写在哪张表的哪一行」，是这一步「签名不变、行为等价」的凭据。

- [ ] **Step 10: 提交**（与 Task 4 一起提交也可以 —— 两者必须同时落地才能编译通过）

```bash
git add app/lib/data/app_repository.dart app/test/schedule_chain_repository_test.dart
git commit -m "feat(db): 装配整条排班链（ActiveSchedules + watch 整表 + setScheduleSpan）"
```

---

## Task 4: 闹钟链路改收 `ShiftSource`

**Files:**
- Modify: `app/lib/features/alarm/alarm_service.dart:113`（`planShiftAlarms`）、`:867`（`rescheduleAll`）、`:885`（`reschedule`）
- Modify: `app/lib/features/home/home_shell.dart:199`（`_tryStartupReschedule`）
- Test: `app/test/alarm_plan_test.dart`（补一组）

**Interfaces:**
- Consumes: `ShiftSource`（Task 1）、`ScheduleChain`（Task 1）、`getActiveSchedules()`（Task 3）
- Produces: `List<ShiftAlarmPlan> planShiftAlarms(ShiftSource source, {required DateTime from, required int days, Map<int, bool> overrides})`；`AlarmService.reschedule(ShiftSource source, List<CustomAlarm> customAlarms, {int days, Map<int,bool> overrides, List<ScheduleEvent> events})`

- [ ] **Step 1: 写失败的测试**

在 `app/test/alarm_plan_test.dart` 末尾（`main()` 内、最后一个 `}` 之前）加：

```dart
  group('跨时段边界：60 天窗口里前段按 A、后段按 B', () {
    ShiftSchedule sched(String name, {required bool restOnFirstDay}) => ShiftSchedule(
          name: name,
          anchorDate: DateTime.utc(2026, 1, 1),
          classes: [
            ShiftClass(
              name: '$name-白',
              abbr: '白',
              startMinute: 480,
              endMinute: 1080,
              alarmEnabled: true,
              alarms: const [ShiftAlarm(minute: 420)], // 07:00
            ),
            ShiftClass(name: '$name-休', abbr: '休', isRest: true),
          ],
          // 周期 2 天：第 0 天白、第 1 天休
          cycle: const [0, 1],
        );

    test('边界前的日子按 A 的班、边界后的按 B 的班', () {
      final from = DateTime(2026, 6, 28); // A 的周期第 0 天（锚点 1/1 起偶数天）
      final chain = ScheduleChain(spans: [
        ScheduleSpan(
          id: 1,
          schedule: sched('A', restOnFirstDay: false),
          from: DateTime.utc(2026, 1, 1),
          to: DateTime.utc(2026, 6, 29),
        ),
        ScheduleSpan(
          id: 2,
          schedule: sched('B', restOnFirstDay: false),
          from: DateTime.utc(2026, 6, 30),
        ),
      ]);

      final plans = planShiftAlarms(chain, from: from, days: 4);
      final byDay = <int, String>{
        for (final p in plans) p.offset: p.shift.name,
      };
      // 6/28 与 6/30 归各自方案的白班；6/29、7/1 两侧都是休 → 不排
      expect(byDay[0], 'A-白');
      expect(byDay.containsKey(1), isFalse);
      expect(byDay[2], 'B-白');
      expect(byDay.containsKey(3), isFalse);
    });

    test('id 不会撞：同一天只归一套方案', () {
      final chain = ScheduleChain(spans: [
        ScheduleSpan(
            id: 1,
            schedule: sched('A', restOnFirstDay: false),
            from: DateTime.utc(2026, 1, 1),
            to: DateTime.utc(2026, 6, 29)),
        ScheduleSpan(
            id: 2,
            schedule: sched('B', restOnFirstDay: false),
            from: DateTime.utc(2026, 6, 30)),
      ]);
      final plans = planShiftAlarms(chain, from: DateTime(2026, 6, 28), days: 6);
      final ids = [
        for (final p in plans) p.alarmIndex * 60 + p.offset,
      ];
      expect(ids.toSet().length, ids.length, reason: '原生 id 撞号 = 两个闹钟互相取消');
    });
  });
```

> 顶部 import 需要加 `import 'package:shiftassistantpro/domain/schedule_chain.dart';`。

- [ ] **Step 2: 跑测试，确认它失败**

```bash
cd app && flutter test test/alarm_plan_test.dart
```

预期：编译失败（`planShiftAlarms` 现在收 `ShiftSchedule`，传 `ScheduleChain` 类型不匹配）。

- [ ] **Step 3: 改 `planShiftAlarms`**

`alarm_service.dart`：

- 把 `List<ShiftAlarmPlan> planShiftAlarms(` 的第一行参数 `ShiftSchedule schedule,` 改成 `ShiftSource source,`
- 把函数体里的 `schedule.shiftOn(date)` 改成 `source.shiftOn(date)`
- 在文档注释里补一段：

```dart
/// 入参是 [ShiftSource] 而不是 `ShiftSchedule`：**「按天衔接」之后，某天归哪套方案
/// 是这条链自己知道的事**，而这里本来就逐天问一次「今天什么班」—— 换一个源进来
/// 即可，函数体一个字不用改。原生的 id 算式（`序号 × 天数窗口 + 天数偏移`）因此
/// 天生安全：同一天只归一套方案，`offset` 相同的两天不可能同时存在。
```

- [ ] **Step 4: 改 `reschedule` 与 `rescheduleAll`**

`rescheduleAll`：

```dart
  static Future<void> rescheduleAll(AppRepository repo) async {
    final schedules = await repo.getActiveSchedules();
    if (schedules == null) return;
    await reschedule(
      schedules.chain,
      await repo.listCustomAlarms(),
      overrides: await repo.listShiftAlarmOverrides(),
      events: await repo.listEvents(),
    );
    // 重复待办的提醒走独立号段，与上面那条链路互不影响（`reschedule` 里的
    // 待办那一段会跳过带 `seriesId` 的行）。
    await rescheduleRecurringReminders(await repo.listRecurringTodos());
  }
```

`reschedule`：第一参数 `ShiftSchedule schedule,` → `ShiftSource source,`；函数体里 `schedule.name` → `source.label`、`planShiftAlarms(schedule,` → `planShiftAlarms(source,`。文档注释里 `[schedule]` 的引用一并改成 `[source]`。

- [ ] **Step 5: 跑新测试与闹钟相关的全套**

```bash
cd app && flutter test test/alarm_plan_test.dart test/alarm_screen_test.dart test/once_alarm_date_test.dart
```

- [ ] **Step 6: 全套**

```bash
cd app && flutter analyze && flutter test
```

预期这**一步才第一次全绿** —— Task 3 与 Task 4 必须一起落地。若 `home_shell` 报错，确认 `_tryStartupReschedule` 里已经是 `.valueOrNull?.chain` 且 `sched == null` 的判断改成读 chain。

- [ ] **Step 7: 提交**

```bash
git add app/lib/features/alarm/alarm_service.dart app/lib/features/home/home_shell.dart \
        app/test/alarm_plan_test.dart
git commit -m "feat(alarm): 排班闹钟改按天解析（入参收 ShiftSource）"
```

---

## Task 5: 信息卡定高改收 `ScheduleChain`（`showChips` 逐日化）

**Files:**
- Modify: `app/lib/features/calendar/info_card_metrics.dart`
- Test: `app/test/info_card_chain_test.dart`（新建）

**Interfaces:**
- Consumes: `ScheduleChain`（Task 1）
- Produces: `InfoCardMetrics measureBottomInfoCardHeight({required BuildContext context, required double cardOuterWidth, required ScheduleChain? chain, required DateTime month, required bool hasTodoHint, required bool hasOverrideHint})`

- [ ] **Step 1: 写失败的测试**

创建 `app/test/info_card_chain_test.dart`：

```dart
// app/test/info_card_chain_test.dart
//
// 卡片高度必须**按月定死**（点哪天都不能变），所以「其他班组」那一行在跨方案的
// 月份里要按「哪天要就哪天算」来取大 —— 只按兜底那套算的话，某个归另一套的日子
// （组数更多、色块折更多行）会把内容顶出定高，而卡片装不下时**只在卡内静默滚动**
// （最后一行被裁掉，没有任何报错）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/schedule_chain.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/calendar/info_card_metrics.dart';

ShiftSchedule _sched(String name, int teamCount) => ShiftSchedule(
      name: name,
      anchorDate: DateTime.utc(2026, 1, 1),
      classes: [
        ShiftClass(name: '$name-白', abbr: '白', startMinute: 480, endMinute: 1080),
        ShiftClass(name: '$name-休', abbr: '休', isRest: true),
      ],
      cycle: const [0, 1],
      teamCount: teamCount,
      teamNames: List.generate(teamCount, (i) => '$name组${i + 1}'),
      teamOffsets: List.generate(teamCount, (i) => i),
    );

void main() {
  testWidgets('跨方案的月份：高度按**两套里更满的那个**取，且逐日恒定', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        final chain = ScheduleChain(spans: [
          ScheduleSpan(
              id: 1,
              schedule: _sched('A', 6),
              from: DateTime.utc(2026, 1, 1),
              to: DateTime.utc(2026, 9, 14)),
          ScheduleSpan(
              id: 2,
              schedule: _sched('B', 1),
              from: DateTime.utc(2026, 9, 15)),
        ]);
        final single = ScheduleChain(spans: [
          ScheduleSpan(
              id: 1,
              schedule: _sched('A', 6),
              from: DateTime.utc(2026, 1, 1),
              to: DateTime.utc(2026, 12, 31)),
        ]);

        final month = DateTime(2026, 9, 1);
        final mixed = measureBottomInfoCardHeight(
            context: context, cardOuterWidth: 400, chain: chain,
            month: month, hasTodoHint: false, hasOverrideHint: false);
        final allSix = measureBottomInfoCardHeight(
            context: context, cardOuterWidth: 400, chain: single,
            month: month, hasTodoHint: false, hasOverrideHint: false);

        // 整月都是 6 班组那一套 → 高度就该按 6 班组算；
        // 混了 15 天 6 班组 + 15 天 1 班组 → 仍然按 6 班组（那天更满）。
        expect(mixed.outerHeight, allSix.outerHeight);
        // 逐日数组长度 = 月长，且**每两天都不一样**（这是「逐日取大」不是「整齐划一」）
        expect(mixed.dayContentHeights.length, 30);

        // 只有 1 班组的那套 → 矮一截（没有「其他班组」那一行）
        final onlyOne = measureBottomInfoCardHeight(
            context: context, cardOuterWidth: 400,
            chain: ScheduleChain(spans: [
              ScheduleSpan(id: 3, schedule: _sched('B', 1),
                  from: DateTime.utc(2026, 1, 1), to: DateTime.utc(2026, 12, 31)),
            ]),
            month: month, hasTodoHint: false, hasOverrideHint: false);
        expect(onlyOne.outerHeight, lessThan(allSix.outerHeight));
        return const SizedBox();
      }),
    ));
  });
}
```

- [ ] **Step 2: 跑测试，确认它失败**

```bash
cd app && flutter test test/info_card_chain_test.dart
```

预期：编译失败（`chain:` 这个具名参数不存在）。

- [ ] **Step 3: 换签名、把 `showChips` 挪进逐日循环**

`info_card_metrics.dart`：

1. `required ShiftSchedule? schedule,` → `required ScheduleChain? chain,`（文档里「[schedule]」的引用改成「[chain]」），import 加 `../../domain/schedule_chain.dart`。
2. 删掉循环外那两段固定量：

```dart
  final showChips = schedule != null && schedule.teamCount > 1;

  // 「其他班组」那一行是 `Row[标签, 色块]`，高度取两者的大者。标签不折行，
  // 它那份是定值，先算好。这两项与具体哪天无关，逐日的循环里不用重量。
  final otherCrewsLabelH = showChips
      ? measure
              .text(L10n.otherCrews, AppTokens.microText)
              .height +
          _otherCrewsLabelTop
      : 0.0;
  final chipLineH = showChips ? _chipLineH(measure) : 0.0;
```

   换成一段注释（说明为什么它必须挪进去）：

```dart
  // 「其他班组」那一行的高度**不能在这里一次算好**：跨方案的月份里，有的天
  // 归 6 个班组的那套、有的天归 1 个班组的那套 —— 只有归多班组那套的日子才有
  // 这一行。所以它与 `showChips` 一起放进逐日循环里量（spec §7）。
  //
  // 标签不折行、色块行高也固定，两者与**哪天**无关，只与「那天归哪套」有关 ——
  // 所以在循环里按当天的方案取，重复量同一个方案的代价可以忽略（一个月最多两种）。
```

3. 逐日循环里，把 `if (showChips) { final rows = _chipRows(measure, contentW, schedule, date); ... }` 一整段换成：

```dart
    // 那天归哪套方案 —— 「其他班组」有没有、有几行，都跟着它走。
    final daySchedule = chain?.scheduleOn(date);
    final showChips = daySchedule != null && daySchedule.teamCount > 1;

    var chipsH = 0.0;
    if (showChips) {
      final labelH = measure.text(L10n.otherCrews, AppTokens.microText).height +
          _otherCrewsLabelTop;
      final lineH = _chipLineH(measure);
      final rows = _chipRows(measure, contentW, daySchedule, date);
      chipsH = math.max(labelH, rows * lineH + (rows - 1) * _chipGapY);
    }
```

4. `_chipRows` 与 `_otherCrewLineH` 的第一参数类型从 `ShiftSchedule` 改成 `ShiftSchedule`（不变 —— 它们收的本来就是单套），但**调用点**要传 `daySchedule!`。

5. `app/lib/features/calendar/calendar_screen.dart` 里 `_cardMetricsFor` 的调用点：`schedule: schedule` → `chain: ScheduleChain(fallback: schedule)`，并加 import。**这是临时适配**：Task 6 会把它换成真正的链。同时把 `_cardMetricsKey` 里所有 `schedule?.xxx` 那几项换成 `chain.cacheKey`（Task 6 的那一步会顺带做；本步先让 key 里保留原样也能跑，但**必须**至少加一项能反映链的，否则跨方案时会拿到旧高度）。

- [ ] **Step 4: 跑测试**

```bash
cd app && flutter test test/info_card_chain_test.dart test/calendar_screen_test.dart
```

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/info_card_metrics.dart app/test/info_card_chain_test.dart \
        app/lib/features/calendar/calendar_screen.dart
git commit -m "feat(calendar): 信息卡定高按天解析（其他班组逐日化）"
```

---

## Task 6: 日历页整体按天解析

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Test: `app/test/calendar_chain_test.dart`（新建）

**Interfaces:**
- Consumes: `ScheduleChain`（Task 1）、`ActiveSchedules`（Task 3）
- Produces: 无新 API —— 这一任务只改渲染

**六处站点**（`grep -n "shiftOn\|teamShift\|isBlank\|dayOverrides" calendar_screen.dart` 能一次全列出来）：

| 行 | 现在 | 改成 |
|---|---|---|
| 391 | `.valueOrNull?.toDomain()` → 变量名 `schedule` | `final chain = scheduleAsync.valueOrNull?.chain;`（Task 3 留的临时写法在这一步去掉） |
| 1126 | `schedule?.shiftOn(date)`（网格） | `chain?.shiftOn(date)` |
| 1604 | `schedule?.shiftOn(_selected)`（信息卡班次行） | `chain?.shiftOn(_selected)` |
| 1912 | `schedule.dayOverrides.containsKey(dayNumber(_selected))`（「已调班」胶囊） | `daySchedule?.dayOverrides.containsKey(dayNumber(_selected))` |
| 1925 | `schedule != null && schedule.isBlank` | `daySchedule != null && daySchedule.isBlank` |
| 1950 | `schedule != null && schedule.teamCount > 1` | `daySchedule != null && daySchedule.teamCount > 1` |
| 2069 | `schedule.teamShift(i, date)`（其他班组色块） | `daySchedule.teamShift(i, date)` |
| 125 | `_cardMetricsFor` 的 key 里 `schedule?.…` | `chain?.cacheKey` |
| 102/115 | `_monthHasOverrideHint(schedule)` | `chain?.monthHasOverrideHint(_month) ?? false` |
| 157 | `_monthTally(schedule)` | 见下 |

- [ ] **Step 1: 写失败的测试**

创建 `app/test/calendar_chain_test.dart`：

```dart
// app/test/calendar_chain_test.dart
//
// 跨时段边界的那个月：边界前的格子是 A 的班、边界后的是 B 的班；
// 信息卡跟着**选中那天**走；「本月统计」跨方案时按简称合并，加总等于月长。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';

void main() {
  // 具体骨架照 `calendar_screen_test.dart` 的 `_pumpCalendar` 抄：
  // 内存库 → 种两套方案（A 六天一轮、B 另一套）→ 给 A/B 各设时段，边界落在
  // **本月中间** → pump 日历 → 断言。
  //
  // 三条断言（缺一不可）：
  //  ① `find.text` 在边界前那格找到 A 的简称、边界后那格找到 B 的简称；
  //  ② 点边界前那格与边界后那格，信息卡里的班次名不同；
  //  ③ 「本月统计」那一行的各数字**加总等于本月天数**（跨方案时不重不漏）。
  testWidgets('跨时段边界：格子/信息卡/本月统计都按天解析', (tester) async {
    // ... 照 calendar_screen_test.dart 装配 ...
  }, skip: 'Task 6 实施时补上骨架');
}
```

> **这一步要真的把它写出来**，不要真的留 `skip`：先照 `calendar_screen_test.dart` 的 `_pumpCalendar`（约 100-140 行那一段）把种子与装配抄过来，再把上面三条断言填上。`skip` 只是给「先跑通编译」留的余地，**提交时必须是会跑的**。

- [ ] **Step 2: 跑测试，确认它失败**

```bash
cd app && flutter test test/calendar_chain_test.dart
```

预期：断言失败（现在整屏都按兜底那套画）。

- [ ] **Step 3: 改渲染**

按上面的表逐处替换。信息卡那一段（`_infoCard` 里）先取一次当天的方案，后面全用它：

```dart
    // 这一屏讲的是**选中那天**，所以取那天所属的方案；下面「班次行 / 已调班 /
    // 空白表 / 其他班组」四处全用它。**不能再用「当前方案」** —— 跨时段之后
    // 「今天归哪套」是 chain 才知道的事。
    final daySchedule = chain?.scheduleOn(_selected);
```

`_monthTally` 改成按简称累加（spec §7.1）：

```dart
  /// 信息卡最后那行「本月 早12 · 午8 · 夜8 · 休6」：**整个月**各上几天什么班。
  ///
  /// 数整月而不是数到今天为止 —— 于是同一月里每天这一行完全一样、量出来的高度也
  /// 一样，判定它画不画的时候不必按天重量。班次用 `shortLabel`（格子里那个一到
  /// 两个字的简称），一行放得下；班次多的排班会折到第二行，折行的高度也照量。
  ///
  /// **按简称累加、不按 `classes` 下标计数**：跨时段的一个月里两套方案的班次定义
  /// 不同，按下标数会把 A 的第 0 个班次和 B 的第 0 个班次算成同一个 —— 数字会错得
  /// 看不出来（spec §7.1）。跨方案时同名的「休」合并成一个数，本来就该合。
  String? _monthTally(ScheduleChain? chain) {
    if (chain == null) return null;
    final counts = <String, int>{};
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    for (var d = 1; d <= days; d++) {
      final shift = chain.shiftOn(DateTime(_month.year, _month.month, d));
      if (shift == null) continue;
      counts.update(shift.shortLabel, (n) => n + 1, ifAbsent: () => 1);
    }
    if (counts.isEmpty) return null;
    final parts = [for (final e in counts.entries) '${e.key}${e.value}'];
    return '${L10n.monthTally} ${parts.join(' · ')}';
  }
```

> ⚠️ **顺序变了**：原来是按 `classes` 顺序输出，现在是 `Map` 的插入序（第一次出现的先后）。**单套方案下顺序与从前一致**（班次在周期里首次出现的顺序），所以既有用例不会因为顺序红。若 `calendar_screen_test.dart` 里有按字面量比的用例红了，先确认它是「顺序不同」还是「数字不同」——前者可接受（改断言），后者是 bug。

`_cardMetricsFor` 的 key：

```dart
    final key = [
      _month.year,
      _month.month,
      cardOuterWidth.toStringAsFixed(1),
      L10n.isEn,
      MediaQuery.textScalerOf(context).scale(14).toStringAsFixed(3),
      // **整条链**的指纹：哪套方案、各自的时段与内容。少了它，跨方案时会拿到
      // 上一条链算出来的高度 —— 而卡片装不下时只在卡内静默滚动（末行被裁）。
      chain?.cacheKey ?? '-',
      hasTodoHint,
      hasOverrideHint,
    ].join('|');
```

`_monthHasOverrideHint(schedule)` 整个方法删掉，换成 `chain?.monthHasOverrideHint(_month) ?? false`。

- [ ] **Step 4: 跑测试**

```bash
cd app && flutter test test/calendar_chain_test.dart test/calendar_screen_test.dart
```

- [ ] **Step 5: 出图看一眼跨边界那个月**

（视觉工装的种子要到 Task 11 才加，所以这一步先跑现成的屏确认**没画坏**。）

```bash
cd app && flutter test tool/visual/
```

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_chain_test.dart
git commit -m "feat(calendar): 日历与信息卡按天解析（网格/其他班组/本月统计）"
```

---

## Task 7: 闹钟页「未来 30 天」与桌面小组件

**Files:**
- Modify: `app/lib/features/alarm/alarm_screen.dart:65-95`
- Modify: `app/lib/features/widget/widget_snapshot.dart`、`app/lib/features/widget/widget_service.dart`
- Modify: `app/lib/features/home/home_shell.dart:199`（`_pushWidgetSnapshot` 传 chain）
- Test: `app/test/widget_snapshot_test.dart`（补一组）

**Interfaces:**
- Consumes: `ScheduleChain`（Task 1）
- Produces: `Map<String, Object?> buildWidgetSnapshot({required ScheduleChain? chain, required DateTime now, required String themeMode, required int accent, required int todayTodoCount})`；`WidgetService.push({required ScheduleChain? chain, …})`

- [ ] **Step 1: 写失败的测试**

在 `app/test/widget_snapshot_test.dart` 末尾加：

```dart
  test('窗口跨时段边界：边界前是 A 的班、边界后是 B 的班', () {
    final chain = ScheduleChain(spans: [
      ScheduleSpan(
        id: 1,
        schedule: _sched('A'),
        from: DateTime.utc(2026, 1, 1),
        to: DateTime.utc(2026, 9, 14),
      ),
      ScheduleSpan(id: 2, schedule: _sched('B'), from: DateTime.utc(2026, 9, 15)),
    ]);
    // now 落在 9 月 → 窗口是「9/1 起（或本周一）～ 10/31」
    final snap = buildWidgetSnapshot(
      chain: chain,
      now: DateTime(2026, 9, 10, 9),
      themeMode: 'system',
      accent: 0xFF5B7FFF,
      todayTodoCount: 0,
    );
    final days = (snap['days']! as List).cast<Map<String, Object?>>();
    final sep14 = days.firstWhere((d) => d['dateShort'] == L10n.monthDay(DateTime(2026, 9, 14)));
    final sep15 = days.firstWhere((d) => d['dateShort'] == L10n.monthDay(DateTime(2026, 9, 15)));
    expect(sep14['shiftName'], startsWith('A-'));
    expect(sep15['shiftName'], startsWith('B-'));
    // 今日卡取**今天所属**那一套
    final todayCard = snap['todayCard']! as Map<String, Object?>;
    expect(snap['hasSchedule'], isTrue);
    expect(todayCard['crews'], isNotNull);
  });
```

> `_sched(name)` 这个 helper 与 `schedule_chain_repository_test.dart` 里那个同形（周期 2 天、两个班次名带方案前缀）。既有测试文件里可能已有同类 helper —— 有就复用，别再造一个。

- [ ] **Step 2: 跑测试，确认它失败**

```bash
cd app && flutter test test/widget_snapshot_test.dart
```

- [ ] **Step 3: 改 `buildWidgetSnapshot`**

`widget_snapshot.dart`：

- 签名 `required ShiftSchedule? schedule,` → `required ScheduleChain? chain,`
- import 加 `../../domain/schedule_chain.dart`
- 逐天循环里 `final shift = schedule?.shiftOn(date);` → `final shift = chain?.shiftOn(date);`
- 今日卡那一块：

```dart
  // 今日卡片的数据。它**按日期烘焙**（农历、待办数、其他班组都是「今天」这一天的），
  // 所以带上自己的 `day` —— 跨天之后原生对表发现对不上，就走降级态而不是把旧数据
  // 当成今天显示（见 spec §6 的 ⚠️）。
  //
  // 「其他班组」与「有没有调过班」问的都是**今天所属的那一套**（跨时段之后
  // 可能不是当前方案）。
  final todayDate = DateTime(today.year, today.month, today.day);
  final lunar = lunarOf(todayDate);
  final todaySchedule = chain?.scheduleOn(todayDate);
  final crews = <Map<String, Object?>>[];
  if (todaySchedule != null && !todaySchedule.isBlank) {
    for (var i = 0; i < todaySchedule.teamCount; i++) {
      if (i == todaySchedule.ourTeamIndex) continue; // 只看别人
      final t = todaySchedule.teamShift(i, todayDate);
      if (t == null) continue;
      final name = i < todaySchedule.teamNames.length
          ? todaySchedule.teamNames[i]
          : L10n.defaultTeamName(i);
      crews.add({'name': name, 'abbr': t.shortLabel, 'color': t.color});
    }
  }
```

- `'adjusted': schedule?.dayOverrides.containsKey(dayNumber(todayDate)) ?? false,` → `todaySchedule?.dayOverrides.containsKey(dayNumber(todayDate)) ?? false,`
- `'hasSchedule': schedule != null && !schedule.isBlank,` → `'hasSchedule': chain?.hasCycle ?? false,`

- [ ] **Step 4: 改 `WidgetService.push` 与 `home_shell`**

`widget_service.dart`：`required ShiftSchedule? schedule,` → `required ScheduleChain? chain,`（参数名与传参一并改），import 换成 `../../domain/schedule_chain.dart`。

`home_shell.dart` 的 `_pushWidgetSnapshot`：`schedule: async.value?.toDomain(),` → `chain: async.value?.chain,`。

- [ ] **Step 5: 改闹钟页**

`alarm_screen.dart`：

```dart
    final async = ref.watch(activeScheduleProvider);
    final chain = async.valueOrNull?.chain;
```

后面 `if (schedule != null) { … schedule.shiftOn(date) … }` 里那些 `schedule` 全改成 `chain`（`ScheduleChain` 有同名的 `shiftOn`，行为一致）。

- [ ] **Step 6: 跑测试与全套**

```bash
cd app && flutter test test/widget_snapshot_test.dart test/alarm_screen_test.dart && flutter analyze && flutter test
```

- [ ] **Step 7: 提交**

```bash
git add app/lib/features/widget/ app/lib/features/alarm/alarm_screen.dart \
        app/lib/features/home/home_shell.dart app/test/widget_snapshot_test.dart
git commit -m "feat(widget): 桌面小组件与闹钟页按天解析"
```

---

## Task 8: 编辑器 —— 「生效时段」一节

**Files:**
- Modify: `app/lib/core/l10n.dart`（文案）
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`
- Test: `app/test/schedule_editor_test.dart`（补一组）

**Interfaces:**
- Consumes: `setScheduleSpan`（Task 3）、`overlappingSpans` / `ScheduleSpan`（Task 1）
- Produces: 编辑器状态 `_effectiveFrom` / `_effectiveTo`（`DateTime?`）；保存路径调 `setScheduleSpan`

- [ ] **Step 1: 加文案**

`app/lib/core/l10n.dart` 里（照既有 `t('中文','English')` 的写法，放在排班编辑器那一组附近）：

```dart
  static String get effectivePeriod => t('生效时段', 'Active period');
  static String get effectiveFrom => t('从', 'From');
  static String get effectiveTo => t('到', 'To');
  static String get effectiveUnbounded => t('不限', 'Any time');
  static String get effectiveForever => t('一直持续', 'Ongoing');
  static String get effectiveRangeInvalid =>
      t('开始日期晚于结束日期', 'Start date is after end date');
  static String effectiveFromDate(String d) => t('$d 起', 'From $d');
  static String effectiveUntilDate(String d) => t('到 $d', 'Until $d');
  static String effectiveRangeSpan(String a, String b) => t('$a ～ $b', '$a – $b');
  static String get effectiveRemaining => t('其余日子', 'Other days');
  static String get effectiveNotChained => t('未参与衔接', 'Not in the timeline');
  static String get effectiveOutsideHint =>
      t('没被上面时段覆盖的日子，用标着「其余日子」的那套。',
        'Days not covered by a period above use the one marked "Other days".');
  static String overlappingSpan(String name) =>
      t('与「$name」的时段重叠，重叠的日子按开始更晚的那套算。',
        'Overlaps “$name”; overlapping days use the later-starting one.');
  static String spansTwoSchedules(String name, String d) =>
      t('这段跨了两套排班的生效边界（$d 起换成「$name」），请分开调整。',
        'This range spans a schedule boundary (switches to “$name” on $d); adjust them separately.');
```

- [ ] **Step 2: 写失败的测试**

在 `app/test/schedule_editor_test.dart` 里，给那个 `_FakeRepository` 加：

```dart
  int? spanId;
  DateTime? spanFrom;
  DateTime? spanTo;
  bool spanCalled = false;

  @override
  Future<void> setScheduleSpan(int id, {DateTime? from, DateTime? to}) async {
    spanCalled = true;
    spanId = id;
    spanFrom = from;
    spanTo = to;
  }
```

（`_FakeRepository` 上面加 `import 'package:drift/drift.dart' show Value;` 不需要 —— `setScheduleSpan` 的签名里没有 `Value`。）

再加一组用例：

```dart
  testWidgets('编辑器保存时把生效时段写下去', (tester) async {
    final repo = _FakeRepository(db, _domain());
    // pump 编辑器（照本文件既有用例的装配）
    // …找到「生效时段」两行，点「从」→ 日期选择器 → 选 2026-01-01…
    // 点保存
    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();
    expect(repo.spanCalled, isTrue);
    expect(dayNumber(repo.spanFrom!), dayNumber(DateTime(2026, 1, 1)));
    expect(repo.spanTo, isNull);
  });

  testWidgets('开始日期晚于结束日期 → 不保存并给提示', (tester) async {
    // 设 from = 2026-06-01、to = 2026-01-01 → 点保存
    // 期望：repo.saved 仍为 null（没保存）、屏幕上出现 L10n.effectiveRangeInvalid
  });
```

> 日期选择器是模态底部弹层（`showGlassDatePicker`）—— 本文件既有用例里若没有开过它，照 `alarm_screen_test.dart` 里挑日期的写法抄（那里有现成的「打开选择器 → 点某天 → 确定」三步）。

- [ ] **Step 3: 跑测试，确认它失败**

```bash
cd app && flutter test test/schedule_editor_test.dart
```

- [ ] **Step 4: 加状态与卡片**

`schedule_editor_screen.dart`：

1. 状态字段（挨着 `_anchor`）：`DateTime? _effectiveFrom; DateTime? _effectiveTo;`
2. `_load()` 里读进来：`_effectiveFrom = dd.effectiveFrom; _effectiveTo = dd.effectiveTo;` —— **但 `ShiftSchedule` 上没有这两个字段**（它们是行的属性，不是领域模型的）。所以改成从 `active` / 库里读：`_load` 走的是 `getScheduleDomain`，它返回的是 `ShiftSchedule`。**这一步改用 `schedulesProvider` 或新增一个 `getScheduleSpan(id)`**：

   ```dart
   /// 读一套方案的生效时段（`ShiftSchedule` 是领域模型，不带这两个库字段）。
   Future<(DateTime?, DateTime?)> getScheduleSpan(int id) async {
     final row = await (db.select(db.shiftScheduleRows)..where((s) => s.id.equals(id)))
         .getSingleOrNull();
     return (row?.effectiveFrom, row?.effectiveTo);
   }
   ```

   在 `_load()` 里、拿到 `d` 之后：

   ```dart
   final id = widget.scheduleId ?? ref.read(activeScheduleProvider).valueOrNull?.currentScheduleId;
   if (id != null) {
     final span = await ref.read(appRepositoryProvider).getScheduleSpan(id);
     _effectiveFrom = span.$1;
     _effectiveTo = span.$2;
   }
   ```

3. 新增 `_effectivePeriodCard(BuildContext context)`，**插在 build 的 `_crewCard` 之后、`_followHolidayCard` 之前**（它在 `if (!_followHoliday)` 块**外面** —— 空白表方案同样可以有生效时段）：

```dart
  /// 6') 生效时段：这套方案从哪天到哪天生效（两端都可留空）。
  ///
  /// 放在 `if (!_followHoliday)` **外面**：空白表方案同样可以有生效时段。
  /// 它是方案的**元信息**，与班次 / 周期无关。
  Widget _effectivePeriodCard(BuildContext context) {
    final muted = AppTokens.inkMuted(context);
    // 行的配方照仓库主流那套：`GlassPressable(child: ListTile(...))`（排班管理页、
    // 「我的」页的设置行都是它）。**不要包 `InkWell`**：`GlassPressable` 自己已经
    // 是「玻璃按压缩放」，再叠一层 Material 水波纹就是两套反馈叠在一起
    // （v0.8.2 把信息卡的水波纹撤掉，理由同一条）。
    Widget row(String label, DateTime? value, String emptyText,
        Future<void> Function(DateTime) onPick, VoidCallback onClear) {
      return GlassPressable(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: AppTokens.rowPrimary),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value == null ? emptyText : L10n.monthDay(value),
                style: value == null
                    ? AppTokens.rowSecondary.copyWith(color: muted)
                    : AppTokens.rowPrimary,
              ),
              if (value != null)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_outlined),
                  iconSize: AppTokens.iconSm,
                  color: muted,
                ),
            ],
          ),
          onTap: () async {
            // 日期选择器是选择器的**提交点**，它自己会发 `select()`
            // （见 `core/haptics.dart` 那份名单）—— 这里不补触觉。
            final picked = await showGlassDatePicker(
              context,
              initialDate: value ?? dateOnly(DateTime.now()),
            );
            if (picked != null) onPick(picked);
          },
        ),
      );
    }

    return GlassTile(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L10n.effectivePeriod, style: AppTokens.sectionTitle),
          const SizedBox(height: AppTokens.spaceSm),
          row(L10n.effectiveFrom, _effectiveFrom, L10n.effectiveUnbounded,
              (d) async => setState(() => _effectiveFrom = d),
              () => setState(() => _effectiveFrom = null)),
          row(L10n.effectiveTo, _effectiveTo, L10n.effectiveForever,
              (d) async => setState(() => _effectiveTo = d),
              () => setState(() => _effectiveTo = null)),
        ],
      ),
    );
  }
```

4. `_save()`：在 `saveSchedule` 之后、`rescheduleAll` **之前**插入写时段 + 校验 + 重叠提示：

```dart
      // 校验放在写库**之前**：开始晚于结束时直接打回，别写进去再让用户自己发现。
      if (_effectiveFrom != null && _effectiveTo != null &&
          dayNumber(_effectiveFrom!) > dayNumber(_effectiveTo!)) {
        if (mounted) {
          showGlassSnack(context, L10n.effectiveRangeInvalid,
              icon: Icons.error_outline);
        }
        return;
      }

      final repo = ref.read(appRepositoryProvider);
      await repo.setScheduleSpan(
        widget.scheduleId ?? id, // `saveSchedule` 的返回值，见下
        from: _effectiveFrom,
        to: _effectiveTo,
      );
```

> 实施时把 `saveSchedule(...)` 的返回值接住：`final id = await ref.read(appRepositoryProvider).saveSchedule(...)`。原来的代码没有接（它用 `widget.scheduleId ?? currentScheduleId` 传进去），现在需要它来确定「写哪一行的时段」。

5. 重叠提示：保存成功、`pop(true)` **之前**（由上层弹 snack 更合适 —— 但重叠提示需要全部方案的时段，放上层要再读一次库。**就在编辑器里弹**，用 `showGlassSnack`）：

```dart
      // 重叠提示：解析规则给的是确定答案（起点最晚的赢），所以**不拦** ——
      // 只是让用户有机会知道「这个月和另一套撞上了」。
      final rows = await ref.read(schedulesProvider.future);
      final self = ScheduleSpan(
        id: id, schedule: _draftSchedule(),
        from: _effectiveFrom, to: _effectiveTo,
      );
      final all = [
        for (final r in rows)
          ScheduleSpan(
            id: r.id,
            schedule: _draftSchedule(), // 内容无关，只比时段
            from: r.effectiveFrom,
            to: r.effectiveTo,
          ),
      ];
      final clash = overlappingSpans(all, self);
      if (clash.isNotEmpty && mounted) {
        showGlassSnack(context, L10n.overlappingSpan(clash.first.schedule.name),
            icon: Icons.info_outline);
      }
```

> ⚠️ `all` 里每项的 `schedule` 都用了 `_draftSchedule()` —— 那是**有意的**：重叠判定只看 `from`/`to`，不看内容，而唯一需要名字的地方是 `clash.first.schedule.name`。**所以名字必须是真的**：把上面那句改成用 `r.name` 建一个最小的壳（`ScheduleSpan(id: r.id, schedule: ShiftSchedule(name: r.name, anchorDate: r.anchorDate, classes: const [], cycle: const []), from: r.effectiveFrom, to: r.effectiveTo)`），否则提示里会写成当前正在编辑的这套的名字。

- [ ] **Step 5: 跑测试**

```bash
cd app && flutter test test/schedule_editor_test.dart && flutter analyze
```

- [ ] **Step 6: 提交**

```bash
git add app/lib/core/l10n.dart app/lib/features/calendar/schedule_editor_screen.dart \
        app/lib/data/app_repository.dart app/test/schedule_editor_test.dart
git commit -m "feat(editor): 方案可设生效时段（含校验与重叠提示）"
```

---

## Task 9: 切换弹窗的时段视图 + 管理页副标题

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`（`_showScheduleSwitcher`，约 787-860）
- Modify: `app/lib/features/calendar/schedule_management_screen.dart`
- Modify: `app/lib/core/l10n.dart`（若还有缺的）
- Test: `app/test/calendar_chain_test.dart`（补一组）

**Interfaces:**
- Consumes: `ShiftScheduleRow.effectiveFrom/to`（Task 2）、`currentScheduleId`（Task 3）
- Produces: 一个共用的纯函数 `String effectiveRangeLabel(ShiftScheduleRow s, {required bool isCurrent})`（放 `app/lib/features/calendar/schedule_management_screen.dart` 顶层或抽到一个小文件里，两处共用）

- [ ] **Step 1: 写失败的测试**

在 `app/test/calendar_chain_test.dart` 里加：

```dart
  test('时段标签的六种形态', () {
    ShiftScheduleRow row({DateTime? from, DateTime? to, bool current = false}) =>
        ShiftScheduleRow(
          id: 1, name: 'A', anchorDate: DateTime.utc(2026, 1, 1),
          isCurrent: current, teamCount: 4, teamNames: '一班,二班,三班,四班',
          ourTeamIndex: 0, teamOffsets: '0,1,2,3',
          effectiveFrom: from, effectiveTo: to,
        );
    expect(effectiveRangeLabel(row(from: DateTime.utc(2026, 1, 1), to: DateTime.utc(2026, 6, 30)), isCurrent: false),
        L10n.effectiveRangeSpan(L10n.monthDay(DateTime(2026, 1, 1)), L10n.monthDay(DateTime(2026, 6, 30))));
    expect(effectiveRangeLabel(row(from: DateTime.utc(2026, 7, 1)), isCurrent: false),
        L10n.effectiveFromDate(L10n.monthDay(DateTime(2026, 7, 1))));
    expect(effectiveRangeLabel(row(to: DateTime.utc(2026, 6, 30)), isCurrent: false),
        L10n.effectiveUntilDate(L10n.monthDay(DateTime(2026, 6, 30))));
    expect(effectiveRangeLabel(row(), isCurrent: true), L10n.effectiveRemaining);
    expect(effectiveRangeLabel(row(), isCurrent: false), L10n.effectiveNotChained);
  });
```

- [ ] **Step 2: 跑测试，确认它失败**

```bash
cd app && flutter test test/calendar_chain_test.dart --plain-name '时段标签'
```

- [ ] **Step 3: 实现标签函数**

在 `schedule_management_screen.dart` 顶层（`class ScheduleManagementScreen` **上方**）：

```dart
/// 一套方案的生效时段标签。**两种形态的说法不同**，这点很要紧：
///  · 没设时段、又是当前方案 → 「其余日子」（它管的就是剩下那些天）；
///  · 没设时段、又不是当前 → 「未参与衔接」（它在时间线上根本不出现）。
///
/// 这两句是把解析规则讲给用户听的唯一一处（spec §8.2）。
String effectiveRangeLabel(ShiftScheduleRow s, {required bool isCurrent}) {
  final from = s.effectiveFrom;
  final to = s.effectiveTo;
  if (from == null && to == null) {
    return isCurrent ? L10n.effectiveRemaining : L10n.effectiveNotChained;
  }
  if (from == null) return L10n.effectiveUntilDate(L10n.monthDay(to!));
  if (to == null) return L10n.effectiveFromDate(L10n.monthDay(from));
  return L10n.effectiveRangeSpan(L10n.monthDay(from), L10n.monthDay(to));
}
```

管理页副标题：

```dart
                        subtitle: Text(
                            '${effectiveRangeLabel(s, isCurrent: isCurrent)} · '
                            '${L10n.teamCountN(parseTeamNames(s.teamNames).length)} · '
                            '${L10n.monthDay(s.anchorDate)}'
                            '${isCurrent ? ' · ${L10n.current}' : ''}'),
```

- [ ] **Step 4: 切换弹窗**

`calendar_screen.dart` 的 `_showScheduleSwitcher`：

- 标题下面加一行说明：

```dart
                  const SizedBox(height: 4),
                  Text(
                    L10n.effectiveOutsideHint,
                    style: AppTokens.rowSecondary
                        .copyWith(color: AppTokens.inkMuted(context)),
                  ),
                  const SizedBox(height: 8),
```

- 每行的 `subtitle` 从 `Text(L10n.teamCountN(...))` 改成：

```dart
                              subtitle: Text(
                                  '${effectiveRangeLabel(s, isCurrent: selected)} · '
                                  '${L10n.teamCountN(parseTeamNames(s.teamNames).length)}'),
```

（`s` 是 `schedulesProvider` 的 `ShiftScheduleRow`，`selected` 已有。）

- [ ] **Step 5: 跑测试 + 全套**

```bash
cd app && flutter test test/calendar_chain_test.dart test/calendar_screen_test.dart test/schedule_management_test.dart 2>/dev/null || true
cd app && flutter analyze && flutter test
```

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart \
        app/lib/features/calendar/schedule_management_screen.dart \
        app/lib/core/l10n.dart app/test/calendar_chain_test.dart
git commit -m "feat(calendar): 切换弹窗与管理页显示生效时段"
```

---

## Task 10: 拖选跨时段边界时拦住

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`（`adjustDays`，约 740-785）
- Test: `app/test/calendar_chain_test.dart`（补一组）

**Interfaces:**
- Consumes: `ScheduleChain.scheduleOn`（Task 1）、`L10n.spansTwoSchedules`（Task 8）
- Produces: 无

- [ ] **Step 1: 写失败的测试**

```dart
  testWidgets('长按拖选跨过时段边界 → 拦下并说明，不弹选择层', (tester) async {
    // 种两套方案、边界落在本月中间 → 长按拖选边界**两侧各一天**
    // 期望：`find.byType(GlassDialog)` 找不到（选择层没开），
    //       屏幕上出现 L10n.spansTwoSchedules(...) 那句说明。
  });
```

- [ ] **Step 2: 跑测试，确认它失败**

```bash
cd app && flutter test test/calendar_chain_test.dart --plain-name '跨过时段边界'
```

- [ ] **Step 3: 加拦截**

`calendar_screen.dart` 的 `adjustDays`：

- 第一行 `.valueOrNull?.toDomain()` 改成 `.valueOrNull?.chain`（Task 3 的临时写法在这一步收口），变量名 `schedule` → `chain`
- 开头那段空白表守卫改成「按**起点那天**的方案判」：

```dart
  Future<void> adjustDays(DateTime from, DateTime to) async {
    final chain = ref.read(activeScheduleProvider).valueOrNull?.chain;
    if (chain == null) return;
    final firstDay = chain.scheduleOn(from);
    if (firstDay == null || firstDay.isBlank || firstDay.classes.isEmpty) {
      // 空白表（跟随法定节假日）没有班次定义可挑，入口本来就不该出现；
      // 这里再兜一次，免得别处误调。
      return;
    }
```

- 在算出 `days` 之后、开选择层**之前**插入：

```dart
    // 拖选跨了时段边界 → **拦住**。
    //
    // 选择层列的是**某一套**的班次定义，而覆盖表 `{scheduleId, day}` 是按天归属的
    // —— 放过去只能得到「列了 A 的班次、却只对 A 的日子生效」这种**静默半生效**，
    // 正是最难查的那类 bug。拦住是不让用户走进那个状态，代价只是一句话。
    // （与「不跨月拖选」同一条思路。）
    for (var i = 1; i < days.length; i++) {
      final before = chain.scheduleOn(days[i - 1]);
      final here = chain.scheduleOn(days[i]);
      if (!identical(before, here)) {
        if (mounted) {
          showGlassSnack(
            context,
            L10n.spansTwoSchedules(
              here?.name ?? '', L10n.monthDay(days[i])),
            icon: Icons.info_outline,
          );
        }
        return;
      }
    }
```

> `identical` 而不是 `==`：`ShiftSchedule` 没有 `operator ==`，两份内容相同的不同实例会被 `==` 判成不等 —— 这里问的是「是不是**同一套**」，`identical` 才对（`crewClashes` 里那条注释是同一条理由）。
>
> 同时 **`chain.scheduleOn(days.single)` 那一处（`current`）也保留**：选择层里的「当前值打勾」照旧按起点那天算。

- [ ] **Step 4: 跑测试 + 全套**

```bash
cd app && flutter test test/calendar_chain_test.dart && flutter analyze && flutter test
```

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_chain_test.dart
git commit -m "feat(calendar): 拖选跨时段边界时拦住并说明"
```

---

## Task 11: 视觉工装 —— 种子与三屏

**Files:**
- Modify: `app/tool/visual/visual_harness.dart`（新种子函数）
- Modify: `app/tool/visual/visual_screens.dart`（三屏）
- Test: 出图 + **看图**

**Interfaces:**
- Consumes: `setScheduleSpan`（Task 3）
- Produces: `Future<void> seedScheduleChain(AppDatabase db)`

- [ ] **Step 1: 加种子**

`visual_harness.dart` 末尾（照 `makeCrewClashCurrent` / `seedMyTemplates` 的写法）：

```dart
/// 让**种子库里已有的第二套方案**（「备选 · 12 天长周期」）带一个时段，
/// 边界落在**本月中间** —— 于是同一个月的格子左半边画第一套、右半边画第二套，
/// 一张图就能看出衔接对不对。
///
/// 必须落在本月中间：边界落在上月/下月时，「跨月那一屏」在这个月里什么都看不出来。
Future<void> seedScheduleChain(AppDatabase db) async {
  final repo = AppRepository(db);
  final rows = await repo.listSchedules();
  if (rows.length < 2) return;
  final today = dateOnly(DateTime.now());
  // 边界取本月 15 日（前后都至少有一天，且离月末足够远，跨月那屏也拍得到）
  final mid = DateTime(today.year, today.month, 15);
  // 第一套（当前）管到 14 日为止
  await repo.setScheduleSpan(rows[0].id, to: DateTime(today.year, today.month, 14));
  // 第二套从 15 日起、一直持续
  await repo.setScheduleSpan(rows[1].id, from: mid);
}
```

- [ ] **Step 2: 加三屏**

`visual_screens.dart` 的 `visualScreens` 列表里，编号接在现有最大编号之后（当前最大是 `26_todo_dialog_weekly`，所以从 **27** 起）：

```dart
  (
    slug: '27_calendar_chained',
    title: '日历 · 排班衔接',
    build: (db) async {
      await seedScheduleChain(db);
      return const CalendarScreen();
    },
    needsOnboardingPrefs: false,
  ),
  (
    slug: '28_span_picker',
    title: '切换排班 · 生效时段',
    build: (db) async {
      await seedScheduleChain(db);
      return const _ScheduleSwitcherHost();
    },
    needsOnboardingPrefs: false,
  ),
  (
    slug: '29_editor_span',
    title: '编辑器 · 生效时段',
    build: (db) async {
      await seedScheduleChain(db);
      return ScheduleEditorScreen(scheduleId: await currentScheduleId(db));
    },
    needsOnboardingPrefs: false,
  ),
```

`_ScheduleSwitcherHost` 照现成的 `_OverridePickerHost` / `_DialogHost` 写一个薄壳（切换弹窗是命令式的，没有可渲染的 widget）：

```dart
/// 「切换排班」是底部弹层、没有可渲染的 widget，用一层薄壳把它弹出来。
/// 与 `_OverridePickerHost` 同一套路。
class _ScheduleSwitcherHost extends ConsumerStatefulWidget {
  const _ScheduleSwitcherHost();
  @override
  ConsumerState<_ScheduleSwitcherHost> createState() => _ScheduleSwitcherHostState();
}

class _ScheduleSwitcherHostState extends ConsumerState<_ScheduleSwitcherHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // 必须是 `CalendarScreen` 上那条路径（`_showScheduleSwitcher` 是私有的）
      // —— 实施时把 `_showScheduleSwitcher` 提到顶层函数
      // `Future<void> showScheduleSwitcher(BuildContext, WidgetRef)`（照
      // `showEditEventDialog` 那条先例），壳与日历页共用一份。
    });
  }
  @override
  Widget build(BuildContext context) => const CalendarScreen();
}
```

> 实施时若 `_showScheduleSwitcher` 不方便提成顶层（它用了 `_switchSchedule` 与 `mounted`），退一步：壳直接 `Scaffold` + 一份**最小复刻**的弹层内容 —— 但那样图与真界面会走样，**优先提成顶层**。

- [ ] **Step 3: 出图**

```bash
cd app && flutter test tool/visual/ --update-goldens 2>/dev/null || flutter test tool/visual/
```

照仓库惯例把图落到 `app/tool/visual/out/`（若脚本如此），然后**真的看这三张图**：

- `27`：边界左右两半的班次简称与颜色**明显不同**（这是本轮唯一会「看」的眼睛）；
- `28`：五种时段标签都出现（「其余日子」「未参与衔接」「…起」「到…」「…～…」）；
- `29`：编辑器里「生效时段」一节排在班组设置之后、跟随法定节假日之前，两行对齐、清除钮只在设了值时出现。

- [ ] **Step 4: 全套（`failOnOverflow` 会硬拦布局溢出）**

```bash
cd app && flutter test tool/visual/ && flutter analyze && flutter test
```

- [ ] **Step 5: 提交**

```bash
git add app/tool/visual/
git commit -m "test(visual): 排班衔接的种子与三张图"
```

---

## Task 12: 收尾 —— 版本号、更新日志、文档、构建发布

**Files:**
- Modify: `app/pubspec.yaml`、`app/lib/core/app_info.dart`
- Modify: `app/lib/features/profile/app_dialogs.dart`（`_changelogZh` / `_changelogEn`）
- Modify: `PRODUCT_SPEC.md`、`AGENTS.md`
- Create: `tools/gh/release-notes-vX.Y.Z.md`

- [ ] **Step 1: 定版本号**

`Z` 归 AI，`X.Y` **必须问用户**（这个功能的分量够不够动 `X.Y` 由用户定）。假设用户维持 `0.9`：

```bash
cd app && sed -i 's/^version: 0\.9\.11+115/version: 0.9.12+116/' pubspec.yaml
# app_info.dart 的 appVersion 同步改成 '0.9.12'
```

- [ ] **Step 2: 更新日志 prepend**

在 `app_dialogs.dart` 的 `_changelogZh` **最前面**插一条（`_changelogEn` 对应），并**删掉最旧那一条**（窗口固定 10 条 —— `changelog_window_test.dart` 会验）。测试版条目**原样写自己这版改了什么**，不做归纳（归纳只发生在正式版）。

条目内容（照既有语气，一句话一件事）：

```
  'v0.9.12',
  '· 排班表可以「衔接」了：每套方案能设生效时段（从几号到几号，两端都可留空），日历、闹钟、桌面小组件都按天取「那天归哪套」，翻回历史看到的是当时的班。',
  '· 设生效时段：排班编辑器 → 生效时段。留空 = 不限起点 / 一直持续。',
  '· 顶栏「切换排班」现在会显示每套方案实际管哪些日子。没设时段的日子用标着「其余日子」的那套。',
  '· 一段日子跨了两套排班时，日历上「调整班次」会提示你分开调整，不会只改一半。',
```

- [ ] **Step 3: `PRODUCT_SPEC.md`**

- 抬头版本号
- 排班那一节：补「方案可带生效时段，按天解析（时段优先、当前方案兜底）」
- 数据模型表：`ShiftScheduleRows` 补两列
- `schemaVersion 11 → 12`；迁移那节补 v11→v12 一行，并写明「这次不用给更早的 fixture 补 DDL，因为两列加在从 v1 就存在的表上」

- [ ] **Step 4: `AGENTS.md`**

- 版本史追加 `0.9.12(+116)`
- 「最近改动」写一节（照 v0.9.11 那种详细度：为什么这么切、原生侧为什么不改、`ShiftSource` 的作用、被拦住的拖选）
- Drift 表清单里 `ShiftScheduleRows` 补两列 + `schemaVersion = 12`
- 「关键决策与坑」补三条：
  1. **解析规则只有一处**（`ScheduleChain.scheduleOn`；起点最晚的赢 + 当前方案兜底）
  2. **「两端都空 = 不参与衔接」是零迁移风险的关键** —— 老库两列全 null，行为一字不变
  3. **`ShiftSource` 让单套与多套在调用点无法区分** —— 所以原生侧一个字不用改

- [ ] **Step 5: 全套验收**

```bash
cd app && flutter analyze && flutter test && flutter test tool/visual/
```

预期：analyze 0 issue；`flutter test` **≥ 450 + 本轮新增**全绿（记下实际条数写进 AGENTS）；工装全绿。

- [ ] **Step 6: 构建**

```bash
cd app && flutter build apk --release --target-platform android-arm64
cp build/app/outputs/flutter-apk/app-release.apk ../dist/倒班助手Pro-vX.Y.Z.apk
aapt2 dump badging ../dist/倒班助手Pro-vX.Y.Z.apk | head -3   # 核 versionName / versionCode / 包名
```

- [ ] **Step 7: 发布说明**

写 `tools/gh/release-notes-vX.Y.Z.md`（`release.ps1` 会自动复用）。

- [ ] **Step 8: 提交 + 发布（beta 分支）**

```bash
git add -A && git commit -m "chore(release): vX.Y.Z（排班表按日期衔接）"
git push origin beta && git tag vX.Y.Z && git push origin vX.Y.Z
GH_CONFIG_DIR="C:/Users/Alec/AppData/Roaming/GitHub CLI" pwsh -File scripts/release.ps1 -SkipConfirm
```

发完**必须 curl 一次** main 上的 `latest.json` 核对版本号：

```bash
curl -s https://raw.githubusercontent.com/<owner>/<repo>/main/latest.json
```

（脚本打印的「发布成功」只覆盖 Release 上传那一步；第 7b 步失败只告警。）

---

## 自检（写完计划后对着 spec 过一遍）

**1. spec 覆盖**

| spec 章节 | 落在哪个任务 |
|---|---|
| §2 已定决策（时段优先/当前兜底、入口形态） | Task 1（规则）、Task 8/9（入口） |
| §3 为什么零风险迁移 | Task 2（迁移不改数据）、Task 3（spans 为空 → 全走 fallback） |
| §4 数据模型与迁移 | Task 2 |
| §5.1 `ShiftSource` | Task 1 |
| §5.2 `ScheduleChain` / `ScheduleSpan` / `monthHasOverrideHint` / `cacheKey` | Task 1 |
| §5.3 `overlappingSpans` | Task 1（实现）、Task 8（调用） |
| §6 装配与 provider | Task 3 |
| §7 消费者改造清单 | Task 4（闹钟）、Task 5（定高）、Task 6（日历）、Task 7（闹钟页+小组件） |
| §7.1 本月统计按简称 | Task 6 |
| §7.2 拖选拦住 | Task 10 |
| §7.3 覆盖沉没不提示 | 无需实现（明确不做） |
| §8.1 编辑器生效时段 | Task 8 |
| §8.2 切换弹窗时段视图 | Task 9 |
| §8.3 管理页副标题 | Task 9 |
| §8.4 不画边界 | 无需实现（明确不做） |
| §9 明确不做 | 全程不碰 |
| §10 文案 | Task 8 / Task 9 |
| §11 测试 | 每个任务的 Step 1 |
| §12 收尾 | Task 12 |
| §13 风险 1（dayNumber） | Task 1（`covers` / `_startsLater` / `_overlaps` 全走 `dayNumber`） |
| §13 风险 2（watch 整表） | Task 3 |
| §13 风险 3（可空列显式 Value） | Task 3（`setScheduleSpan`） |
| §13 风险 4（两个类型别混） | Task 3 |
| §13 风险 5（参数类型改 ShiftSource） | Task 4 |
| §13 风险 6（showChips 逐日） | Task 5 |
| §13 风险 7（闹钟页 30 天） | Task 7 |
| §13 风险 8（测试定时器） | Task 3 Step 8 若红则照 `_disposeCalendar` 拆树 |
| §13 风险 9（三种「空」） | Task 1（`covers`）与 Task 9（三种标签） |
| 按天覆盖的归属（spec 未写，实施时摸出来的洞） | Task 3 Step 6（`setDayOverrides` / `clearDayOverrides` 按天解析） |

**2. 占位符扫描**

- Task 6 Step 1 与 Task 11 Step 2 各有一处「先留骨架、实施时补实」的说明 —— 两处都写明了「提交时不许留 skip」「优先提成顶层函数」。**实施时必须补实**，这是本计划里仅有的两处需要临场判断的地方。
- 其余代码块都是可直接落地的完整片段（含 import、断言与失败时的预期输出）。

**3. 类型一致性**

- `ScheduleChain.scheduleOn` → `ShiftSchedule?`；`shiftOn` → `ShiftClass?`；`cacheKey` → `String`；`hasCycle` → `bool`；`monthHasOverrideHint(DateTime)` → `bool`。Task 5/6/7 的调用点用的都是这几个名字。
- `setScheduleSpan(int id, {DateTime? from, DateTime? to})` 在 Task 3 定义、Task 8/11 调用，签名一致。
- `buildWidgetSnapshot(chain:)` / `WidgetService.push(chain:)` 在 Task 7 同时改。
- `effectiveRangeLabel(ShiftScheduleRow, {required bool isCurrent})` 在 Task 9 定义并在两处调用。
- `planShiftAlarms(ShiftSource source, {...})` Task 4 定义、Task 1 的测试与 Task 4 的测试都用。

**4. Review Focus 的落点**

五条各自有任务与用例：① → Task 1 `covers` 的两个「差一天」+ Task 6 界面；② → Task 3 的「改非当前方案重发」；③ → Task 5 的跨方案高度 + Task 6 的本月统计加总；④ → Task 2 的迁移用例 + Task 3 的「只有一套时每天都归它」；⑤ → Task 10。
