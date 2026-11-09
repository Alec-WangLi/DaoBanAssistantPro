# 小组件跟随深浅色 + 重复待办「挂班次那天」收口（设计）

- 日期：2026-11-09
- 起因：用户 v0.12.10 真机测试后的两条反馈（原话）：
  1. 「桌面小组件目前不能自动跟随系统切换亮色、深色模式。」
  2. 「重复待办：明明我设置它的待办时间是在某个班次里，但它还是在班次时间之外显示。我打勾之后，到了固定提醒时间，它还会弹出通知提醒。感觉现在的逻辑有点混乱，需要优化一下。」
- 用户拍板（2026-11-09）：跨午夜班次的重复待办，**行挂班次那天**（不是提醒落地那天）。
- 影响版本：v0.12.11 测试版（`X.Y` 由用户定，AI 只动 `Z` 与 `build`）

---

## 1. 目标 / 非目标 / 反目标

**目标**

- App 主题为「跟随系统」时，系统切深浅色后桌面三张卡**自动**跟着变；App 进程不在也一样。
- 重复待办的**行**回到发生日（班次那天）；提醒仍按 `alarmDayAnchor` 的三档落点（前一天 / 当天 / 次日）。
- 打勾 / 删除一次之后，那一次的提醒**不再响**。
- 「跳过这一次」的水位线与发生日同口径，不再误伤下一次。
- 行上把「班次名」和「次日 / 前一天」一起标出来，避免 2026-11-05「行和事错开一天」的误会重演。

**非目标**

- 不改 `alarmDayAnchor` 的三档判据、24 小时值班与回绕式 `endMinute` 的既有规则。
- 不改一次性待办、每天 / 每周 / 每月规则的日期与提醒。
- 不改原生「弹队首、续队尾」的排定机制。
- 不改小组件的版式、尺寸、文案、刷新时机（跨天 / 班次边界）。
- 不引入常驻服务、`updatePeriodMillis` 周期刷新或 `JobScheduler` 轮询。

**反目标**（做成了也算失败）

- 背景跟着变了、文字没变（API < 31 上会出现这种半翻状态）。
- 为了「跟随系统」把 manifest 收 `CONFIGURATION_CHANGED` 当唯一通道 —— 实测收不到。
- 修落点时顺手「优化」`alarmDayAnchor`。
- 继续用 `todoDisplayDay` 把行挂到提醒日。
- 修「打勾还响」时只取消通知、不重排时刻表 —— 原生队尾还会把下一次续上。
- 为修日期把用户手工挪过的行拽回规则日。

---

## 2. 小组件：跟随系统深浅色

### 2.1 现状与根因

判断没坏：`WidgetRenderer.isDark()` 每次渲染都现读 `Configuration.uiMode`，快照里的 `themeMode` 也是模式串（`system | light | dark`）。坏在**没人触发重画**：

- 颜色在渲染时被烤成具体 ARGB（`setTextColor(具体值)`）与具体 drawable（`widget_card_light/dark`）。
- 刷新只有三个时机：跨天 00:00、今天班次的开始/结束、App 内数据变化。系统切深浅色不在其中。
- `AppWidgetHostView`（AOSP）**没有** `onConfigurationChanged`；宿主只在收到新 RemoteViews 时 `apply / reapply`。
- `ACTION_CONFIGURATION_CHANGED` **不在** Android 8+ 的隐式广播豁免名单里，manifest 注册收不到。

### 2.2 真机实测（2026-11-09）

设备：Xiaomi 25102RKBEC（Android 16 / HyperOS），系统 `Night mode: auto`（自定义 19:00–07:30）。

诊断包同时带三条路：`setColorInt` 日夜双值 + `drawable-night` 背景、运行时接收器、manifest 接收器。

| 场景 | 结果 |
|---|---|
| App 进程存活，切深浅色 | 运行时接收器收到广播并 `refreshAll`（logcat 有记录），卡片翻转 |
| **App 进程被杀**（`am force-stop` / `am kill`），切深浅色 | 三张卡**全部自动翻转**（周条 / 今日卡 / 月历逐张截图），logcat **无任何本 App 日志** |
| 同上，专门看 manifest 接收器 | **没有**收到 `CONFIGURATION_CHANGED` |

结论：**小米桌面在配置变化时会重新应用 RemoteViews**，主题感知的 `setColorInt` 与 `-night` drawable 都会按新配置解析。manifest 那条路是死的；运行时接收器是有效兜底。

### 2.3 采用方案

**A. 主题感知渲染（主路）**

- 文字：新 helper `themedColor(rv, id, system, dark, light, night)`
  - `system && SDK >= 31` → `setColorInt(id, "setTextColor", light, night)`
  - 否则 → 原烤死路径
- 背景：`cardBackground / pageBackground / cellBackground`
  - `system && SDK >= 31` → 同名资源 + `drawable-night/`（`widget_card_auto` / `widget_page_auto` / `widget_cell_auto`）
  - 否则 → 原 light/dark
- 「没班次」那个 12dp 圆点：`system && SDK >= 31` → `setImageViewResource(R.drawable.widget_dot_empty)`（两份 -night）；否则原烤位图。
- `themeMode != "system"`（用户在 App 里明确选了亮 / 暗）→ 一律烤死，小组件跟 App 的选择，不跟系统。

**B. 运行时接收器（兜底）**

- `MainActivity.onCreate` 用 `ContextCompat.registerReceiver(..., RECEIVER_NOT_EXPORTED)` 注册 `ACTION_CONFIGURATION_CHANGED`，收到 `ShiftWidgets.refreshAll(context)`，`onDestroy` 注销。
- 作用：API < 31（没有 `setColorInt`）以及「某个 ROM 不重新应用」时的兜底。App 不在运行时它不生效 —— 那种情况在 API 31+ 由 A 覆盖。

**C. 删掉 manifest 那条路**

`WidgetRefreshReceiver` 的 `CONFIGURATION_CHANGED` 分支与 manifest 的 intent-filter 一并删除（实测收不到，留着是死代码）。

### 2.4 API 分档

| 档 | 文字 | 背景 | App 不运行时的自动跟随 |
|---|---|---|---|
| API 31+ | `setColorInt` | `-night` drawable | **是** |
| API 26–30 | 烤死 | 烤死（**不用** `-night`） | 否；等下一次跨天 / 班次刷新，或 App 活着时由运行时接收器刷新 |

**API < 31 为什么不用 `-night` 背景**：文字翻不了，只翻背景会得到「浅色字压深色卡」或反之的半翻状态，比不翻更糟。

### 2.5 改动清单

> **起点**：工作区里已有一版**未提交**的诊断实现 —— `themedColor` 覆盖了中性文字色、三份 auto 背景、`MainActivity` 运行时接收器、manifest 分支、六份 drawable。实现时以它为起点：保留并清理，补上 §2.3 的 API < 31 守卫与空班次圆点的 drawable，删掉 manifest 分支。**别把它当成已完成** —— 它缺这两块，而且「-night 在 API < 31 上不能单用」这条还没落进代码。

- `app/android/app/src/main/kotlin/.../WidgetRenderer.kt`
  - 新增 `themedColor` 与三个背景 helper
  - 所有中性文字色（ink / muted / holiday）改走 `themedColor`
  - 三张卡 + 空态 + 占位态的背景改走 helper
  - 空班次圆点改走 `setImageViewResource`
- 新增资源：
  - `drawable/widget_card_auto.xml` + `drawable-night/widget_card_auto.xml`
  - `drawable/widget_page_auto.xml` + `drawable-night/widget_page_auto.xml`
  - `drawable/widget_cell_auto.xml` + `drawable-night/widget_cell_auto.xml`
  - `drawable/widget_dot_empty.xml` + `drawable-night/widget_dot_empty.xml`
- `MainActivity.kt`：运行时接收器
- `WidgetRefreshReceiver.kt` / `AndroidManifest.xml`：删除 manifest 分支
- 文档：`docs/decisions/widget.md` 补实测证据与 API 分档；`WidgetRenderer.kt` 顶部「纪律 2」那条「不依赖 `-night`」改写为「2026-11-09 实测：MIUI 宿主会重新应用，`-night` 在 API 31+ 可用；API < 31 仍不用」。

### 2.6 验收

- 三张卡在「App 进程被杀 + 切换深浅色」后自动翻转（真机截图）。
- `themeMode` 为显式 `light/dark` 时，系统切换**不**改变卡片。
- App 进程存活时，运行时接收器 logcat 有记录且 `refreshAll: 3 个实例`。
- 源码护栏见 §5。

---

## 3. 重复待办：行挂班次那天

### 3.1 统一模型

一条重复待办有两个日期，必须分清：

| 概念 | 含义 | 用途 |
|---|---|---|
| **发生日** `occ` | 规则命中的那一天（按班次 = 班次那天） | 行的 `date`、列表排序、水位线、生成器顺延 |
| **提醒时刻** `fire` | `_fireAt(occ, clock, advance, shift)`，可能 `occ` / `occ±1` | 原生排定、通知 |

行的副标题依次是：`日期 · 班次名 · 提醒钟点（带次日/前一天）· 提前档位`。

例：上夜班 11/9、待办 02:00 →

```
11月9日 周一 · 上夜班 · 次日 02:00
```

行在 11/9，提醒在 11/10 02:00 —— 两个日期各自说清楚，不再靠「行跟着提醒走」去回避。

### 3.2 生成器

- 删除 `advanceRecurringTodos` 里对 `todoDisplayDay` 的使用：行 `date = occ`。
- 顺延比较改回 `daysBetween(keep.date, occ) > 0`（仍然只往前、不回退）。
- `todoDisplayDay` 改名 `legacyDisplayDayForMigration`（或保留原名 + 标注「仅迁移用」），只服务于 §3.3 的一次性迁移；下一版可删。

### 3.3 旧数据迁移

旧版把跨午夜的行写成了提醒落地日（`occ±1`）。升级后做**一次性**迁移：

- 触发点：`home_shell._tryStartupReschedule` 在 `advanceRecurringTodos` **之前**调 `repo.migrateLegacyRecurringRowDays()`；用一个 SharedPreferences 键（`recurringRowDayMigratedV1`）保证只跑一次，成功后才置位。
- 范围：**所有**带 `seriesId` 的行（主列表 + 归档），不只当前那一行 —— 否则归档里旧行的「班次名 + 次日」标记会指到错误的发生日。
- 判据：对每一行，在 `row.date - 1 / row.date / row.date + 1` 里找**唯一**一个满足
  - 那天是该系列的按班次发生日（`shiftNames` 命中），且
  - `legacyDisplayDay(series, 那个候选日, shift) == row.date`
  的候选；找到且不等于 `row.date` 就写回候选日。
- 同一天命中多个候选（不同班次窗口叠加的极端情形）→ **不动**，只记日志。
- 迁移跑在「新版第一次启动」时，此时库里所有行都还是旧口径，不存在「新行被误判」的问题。
- `todoDisplayDay` 改名 `legacyDisplayDayForMigration`，只服务迁移与「以后不再重复」的解绑（§3.9）；下一版可删。

**已知代价（不在本轮修）**：旧版写入的 `skipThrough` 是「显示日」口径，可能比发生日多一天。升级后相关系列**至多**少出现一次。原因是无法区分「勾掉留下的水位线」与「删掉留下的水位线」；把水位线统一往回退会让已经删掉的那一次复活。可接受，写进更新说明。

### 3.4 排提醒：打勾后不再响

根因：`upcomingFireTimes` 读 `enabled`、`advanceRemindMinutes`，但**没读 `skipThrough`**；而 `setEventCompleted(done: true)` 会写它。生成器读了，排提醒没读 —— 于是重排时又把同一时刻排了回去。

修法：在 `upcomingFireTimes` 的 occurrence 循环里，先判

```dart
if (s.skipThrough != null && dayNumber(occ) <= s.skipThrough!) {
  occ = nextOccurrenceAfter(s, occ, shiftOn: shiftOn);
  continue;
}
```

`planRecurringReminders` 自动受益。`rescheduleTodoReminders`（`_toggleDone` 已经在调）会把新计划推给原生，队首 / 队尾一起换掉。

**取消勾选 / 撤销要把它还回来**（否则「勾错了 → 撤销」会留下一个永远不响的提醒）：

- `setEventCompleted(e, false)`：若 `skipThrough == dayNumber(e.date)`，清成 null；若水位线更高（更晚的一次被跳过），不动。
- `_restoreCompleted`（页面已销毁后的「撤销」）现在只调 `rescheduleEventReminders`，改成 `AlarmService.rescheduleTodoReminders(repo)`，让系列提醒一起重排。
- 「勾上 → 撤销 → 再勾上」的用例要覆盖。

### 3.5 水位线口径

- `setEventCompleted` / `skipRecurringOccurrence` 写入的 `e.date` 现在就是发生日，与生成器、`upcomingFireTimes` 三处同口径。
- 不再出现「跨午夜时水位线多走一天、把下一次也跳过」。

### 3.6 列表行

- 副标题加 `shift.name`，条件复用现有的「四道一致性闸门」：按班次规则、设了钟点且与行一致、当天的班次名在系列选过的名字里、有排班链。任一不成立就不加（不猜）。
- 保留 `todoReminderClockLabel` 的「次日 / 前一天」标记。
- 目的：2026-11-05 的反馈是「今天的行为什么写着次日 00:00」。现在把班次名写在前面，读起来是「这属于上夜班，提醒在次日 02:00」，而不是「系统把日期算错了」。

### 3.7 受影响的路径

- `advanceRecurringTodos`（行日期 + 迁移）
- `setEventCompleted` / `skipRecurringOccurrence`（口径自然对齐）
- `schedule_screen._toggleDone` / `_restoreCompleted` / 删除（都走 `rescheduleTodoReminders`）
- `recurring_series_editor`（只改标题 / 时间时不拽回日期 —— 现有逻辑不动）
- `recurring_panel` 的「下次 X」用发生日，不变

### 3.8 边界

- 全天提醒（`timeMinute == null`）：不发生落点，`occ` 不变；`skipThrough` 照常生效。
- 非按班次规则：`occ` 本来就是行日期，行为不变。
- 换排班后旧行留在原地（只往前不回退），不变。
- 连续两个夜班日：行分别挂在各自的发生日，提醒可能都落在同一时刻 —— `upcomingFireTimes` 现有的「排序后与上一条相等则去重」仍然管用。
- 「N 项待办」徽章（`isPendingTodoOn` / 日历信息卡 / 桌面小组件）按 `e.date` 计数：行挂回发生日后，跨午夜待办的徽章从提醒日移到班次日。这是「行挂班次那天」的直接结果，不做第二套映射；用例钉住。

### 3.9 两处连带修正

**A. 冷启动会把重复待办的提醒清掉、不再排回来（既有 bug，本轮一起修）**

`home_shell._tryStartupReschedule` 调的是 `AlarmService.reschedule(...)`：

- `reschedule` 内部的 `rescheduleEventReminders` 开头 `cancelAllTodoReminders()`，会把重复待办号段一起取消；
- 然后只排 `seriesId == null` 的一次性行；
- `rescheduleRecurringReminders` 只在 `rescheduleAll` / `rescheduleTodoReminders` 里调，**冷启动这条路径没有**。

结果：每次冷启动之后，重复待办的提醒要等用户打开待办页才回来。`rescheduleTodoReminders` 注释里「重复系列的提醒只在冷启动等 `rescheduleAll` 路径上才排得上」也因此是错的。

修法：`_tryStartupReschedule` 最后改调 `AlarmService.rescheduleAll(repo)`（= `reschedule` + `rescheduleRecurringReminders`）。验证时必须**检查生成的计划**，不能只看「没有响」—— 冷启动后本来可能根本没有计划。

**B. 「以后不再重复」会把跨午夜的提醒挪 24 小时**

解绑后行变成一次性，`eventReminderTime = 行日期 + 钟点`，不走 `alarmDayAnchor`。新模型下行的日期 = 发生日，于是夜班 02:00 的待办解绑后会**提前 24 小时**响（零点班 23:00 则晚 24 小时）。

修法：`unlinkRecurringSeries(id)` 在解绑前，把**当前未完成那一行**的日期改成 `legacyDisplayDayForMigration(series, 行日期, shift)` —— 即提醒落地日。这样一次性提醒的绝对时刻不变。两个解绑入口（待办编辑弹窗、系列编辑器）都走同一个仓库方法，只改一处。归档行已经没有提醒，不改日期。

---

## 4. 数据与迁移

- **不改表结构**，不需要 `build_runner`，无 schemaVersion 变化。
- 新增一个 **SharedPreferences** 键 `recurringRowDayMigratedV1`（布尔），只作为「旧行日期一次性迁移跑过没有」的标记 —— 不是用户可见设置，不放进「我的」页。
- 旧行日期：§3.3 的一次性迁移（主列表 + 归档）。
- 水位线：不迁移（§3.3 的已知代价）。

---

## 5. 测试

**改**

- `app/test/todo_shift_row_day_test.dart`
  - 生成器落库：跨午夜系列的行 `date == occ`（不再等于提醒日）。
  - 旧数据迁移：`date == legacyDisplayDay` 的行被写回 `occ`；手工挪到别的日子的行不动。
  - 原来的 `todoDisplayDay` 纯函数用例删除或改指向迁移函数。
- `app/test/todo_shift_marker_test.dart`
  - 副标题包含班次名 + 「次日 02:00」；四道闸门任一不成立时不加班次名、不标落点。

**加**

- `app/test/recurring_alarm_plan_test.dart`
  - `upcomingFireTimes` / `planRecurringReminders` 跳过 `dayNumber(occ) <= skipThrough` 的发生日。
  - 勾选当前这次之后，计划里不再包含它的 fire 时刻（含 `repeatTimes`）。
  - 取消勾选 / 撤销之后，计划里**恢复**它（水位线被清掉）。
  - 连续夜班日 + 相邻两次落成同一时刻时仍然只排一条。
- `app/test/todo_startup_reschedule_test.dart`
  - 冷启动路径（`rescheduleAll`）会排上重复待办的提醒；防止「取消之后没有重排」的回退。
- `app/test/recurring_unlink_test.dart`
  - 夜班 02:00 的系列解绑成一次性后，`eventReminderTime` 仍落在次日 02:00（提前 / 延后 24 小时都算失败）。
- `app/test/widget_fixed_cards_guard_test.dart`
  - `drawable/` 与 `drawable-night/` 两份 auto 资源都存在且字段一致。
  - `WidgetRenderer.kt` 的中性文字色走 `setColorInt`，且有 `Build.VERSION_CODES.S` 守卫（扫源码前先 `_stripComments`）。
  - `AndroidManifest.xml` 不再声明 `CONFIGURATION_CHANGED`。
  - `MainActivity.kt` 有运行时注册 + 注销。
- `app/test/todo_migration_test.dart`
  - 旧显示日的行（含归档行）迁回发生日；迁移只跑一次（键置位后不再动）；手工挪到非旧显示日的行不动。

**条数**

- 只增不减；跑完全套后按尾行 `+N` 改 `.github/workflows/ci.yml` 的 `EXPECTED_TESTS`，**不推算**。

**真机**

- 三张卡：App 进程被杀 + 切深浅色 → 自动翻转（已有 2026-11-09 的截图证据，实现后再复验一次）。
- 重复待办：夜班 02:00 的系列，行出现在班次日；勾选后到次日照常不响。

---

## 6. 发布与文档

- `app/pubspec.yaml` `0.12.10+185` → `0.12.11+186`；`app/lib/core/app_info.dart` 同步。
- `app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh/_changelogEn`：prepend 新版本、删最旧、保持 10 条；测试版条目原样写本版改动。
- 测试版走 `beta` 分支；`git tag v0.12.11`；`scripts\release.ps1 -SkipConfirm`；发完 curl main 上的 `latest.json` 核对。
- 决策记录：
  - `docs/decisions/widget.md`：`-night` 的实测证据、API 分档、manifest 死路。
  - `docs/decisions/todo.md`：行挂发生日（撤销 2026-11-05「行跟着提醒走」）、`skipThrough` 在排提醒侧也要读。
- `docs/changelog/v0.12.md` 补 v0.12.11 一条。
- 更新说明里如实写：旧版跨午夜系列升级后至多少出现一次（§3.3 代价）。

---

## 7. 留给实现

- 空班次圆点两份 drawable 的具体色值（照抄 `wg_empty_light/dark`）。
- 源码护栏的正则与 `_stripComments` 写法。
- 副标题加班次名后的窄屏折行（`maxLines: 2` 已允许）。
- 一次性迁移的 prefs 键放在 `core/` 下的小 helper 里，还是并进 `AppSettings`（倾向前者：它是内部迁移标记，不该出现在设置模型里）。
- `legacyDisplayDayForMigration` 放在 `domain/recurring_todo.dart`（纯函数，便于单测）；迁移本身放 `AppRepository`（要读 series / rows / chain）。
- 迁移不可判定时只记日志，不阻塞启动。
