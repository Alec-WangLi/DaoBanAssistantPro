# 月历小组件：相邻月连起来 + 上下月切换 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 4×5 那张月历小组件把相邻月份的日子画出来（连成一片），并在标题行给它左右两个箭头翻上 / 下月、点月份文字回到今天。

**Architecture:** Dart 侧把快照窗口从「本月 + 下月」扩到「上月 + 本月 + 下月」（**协议版本不动**，两边互相降级）；原生把 42 格从「本月 1 日所在周的周一起、连续 42 天」铺满，相邻月的日数字变灰、班次胶囊照画；「现在翻到哪个月」作为**每个实例一份**的锚点落盘（存绝对值），点箭头走一枚**广播** PendingIntent 打到**已有的** `WidgetRefreshReceiver`，只重渲染那一个实例。**小组件仍然不需要 App 进程活着。**

**Tech Stack:** Flutter / Dart 3（快照生成与测试）、Kotlin + Android AppWidget / RemoteViews（渲染，**本仓没有 Kotlin 测试目标**）、SharedPreferences（状态落盘）

**Spec:** `docs/superpowers/specs/2026-09-30-widget-month-navigation-design.md`

## Global Constraints

- **版本号**：`X.Y` 由用户决定，AI 只能动末位 `Z` 与 `build`；`app/pubspec.yaml` 的 `version:` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须同步（`test/app_info_test.dart` 盯着）。
- **不许跑 `dart format`**：工具链是新版 tall style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `flutter analyze`。
- **快照协议版本 `v` 保持 2**：这次只改窗口**范围**，字段结构一个不动。升版本会把所有小组件立刻打成占位态。
- **原生侧不许出现用户可见的中文字面量**（Kotlin 里只有 `AlarmLog` 的日志串是中文，那是既有惯例）。箭头的 `‹` `›` 是符号，不在此列。
- **颜色一律取资源色**（`wg_ink_*` / `wg_muted_*` / `wg_holiday`，见 `res/values/widget_colors.xml`），不在 Kotlin 里写字面量。
- **RemoteViews 布局只能用白名单里的视图**（`TextView` / `ImageView` / 四种 Layout …），由 `test/widget_layout_whitelist_test.dart` 守门。
- **往容器 `addView` 之前必须先 `removeAllViews`**（`test/widget_fixed_cards_guard_test.dart` 守门，它同时查「出现过」与「先后顺序」）。
- **4×1 本周条与 4×3 今日卡一个字不改。**
- **不新增 receiver**：manifest 里那四个是 `widget_fixed_cards_guard_test.dart` 钉住的（release 开 R8，只被代码引用的类会被裁掉）。
- **验收**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿（当前 **523** 条，**只增不减**）；`flutter test tool/visual/` 全绿（当前 **246** 条）。**Kotlin 侧没有可跑的测试目标** —— 那半边靠「Dart 扫源码的护栏 + 真机」两头兜，凡是没有护栏的结构性约定，都必须写进 Task 5 的真机清单。
- **提交前先跑测试**，每个任务末尾提交一次。

## Review Focus

以下是 spec 隐含、但没人会主动去试的输入。每一条都要在它归属的那个任务里落成用例（Kotlin 那几条落不了自动化用例的，落进 Task 5 的真机清单）：

1. **App 两三个月没打开**（快照窗口早就走偏了）—— 点箭头、点某一格，期望：**卡片照常画能画的、到头的箭头是灰的**，点上去什么都不发生；不崩、不黑、不跳到一片空白。（任务 3 / 4）
2. **翻到相邻月时点某一格** —— 期望：跳到**那一格那一天**（比如 8 月 31 日），不是跳到本月同号那天。（任务 3 / 4）
3. **删掉小组件再重新添加**（系统会复用 `widgetId`）—— 期望：新卡片从**今天那个月**开始，不继承上一张卡翻到的月份。（任务 2）
4. **快照是旧版本（窗口只有 68 天）或解析失败** —— 期望：相邻月那几格挖空、箭头变灰，本月照常画；不崩。（任务 1 / 4）
5. **5 行月的最后一行整行都是下个月的日子**（例如 8 月，31 天且 1 日是周六）—— 期望：整行照常画（不是整行空掉，也不是把那几格挪进本月）。（任务 1 / 3）

---

### Task 1: 快照窗口扩到「上月 + 本月 + 下月」（Dart）

**Files:**
- Modify: `app/lib/features/widget/widget_snapshot.dart:30-49`（`kWidgetSnapshotMaxDays` 与 `widgetWindow`）
- Test: `app/test/widget_snapshot_test.dart`（在既有的窗口用例旁加）

**Interfaces:**
- Consumes: 无（只动纯函数）
- Produces: `widgetWindow(DateTime now) → ({DateTime from, DateTime to})`（语义变了：现在是**整周对齐的三个月**）；`kWidgetSnapshotMaxDays = 112`。原生的「这个月能不能翻」判据就建立在「该月 42 格 ⊆ `days[]`」上，所以这条窗口性质是**翻月功能的地基**。

- [ ] **Step 1: 写失败的用例**

在 `app/test/widget_snapshot_test.dart` 里加（放在既有 `widgetWindow` 相关用例旁）：

```dart
  // ── 窗口是「翻月」的地基 ──
  //
  // 能翻多远完全由窗口决定：某个月的 42 格只要有一格落在窗口外，那个月就翻不过去
  // （原生按同一条判据把箭头变灰、接收端直接吞掉点击）。所以这条性质不是「锦上添花
  // 的断言」—— 它是 v0.9.17 那个功能的**前提**，写成用例才不会在以后被悄悄改小。
  test('窗口覆盖「上月 / 本月 / 下月」三个月的完整 42 格', () {
    // 取几个刁钻的日子：年初、年末、1 日在周日、1 日在周一、5 行月与 6 行月都有。
    final samples = [
      DateTime(2026, 1, 15),
      DateTime(2026, 12, 31),
      DateTime(2026, 3, 1),
      DateTime(2026, 8, 31),
      DateTime(2026, 11, 1),
      DateTime(2027, 2, 28),
    ];
    for (final now in samples) {
      final w = widgetWindow(now);
      final from = dayNumber(w.from);
      final to = dayNumber(w.to);
      for (final delta in const [-1, 0, 1]) {
        // 那个月的 42 格：从「1 日所在周的周一」起连续 42 天（与原生同一条算法）。
        final first = DateTime(now.year, now.month + delta, 1);
        final start = DateTime(
            first.year, first.month, first.day - (first.weekday - 1));
        for (var i = 0; i < 42; i++) {
          final d = DateTime(start.year, start.month, start.day + i);
          final n = dayNumber(d);
          expect(n >= from && n <= to, true,
              reason: '$now 的窗口没盖住 ${first.year}-${first.month} 的第 $i 格'
                  '（$d）—— 那个月就翻不过去了');
        }
      }
    }
  });

  test('窗口长度不超过 kWidgetSnapshotMaxDays', () {
    for (final now in [
      DateTime(2026, 1, 15),
      DateTime(2026, 7, 31),
      DateTime(2026, 12, 31),
    ]) {
      final w = widgetWindow(now);
      final n = dayNumber(w.to) - dayNumber(w.from) + 1;
      expect(n, lessThanOrEqualTo(kWidgetSnapshotMaxDays),
          reason: '窗口 $n 天，超过上限 $kWidgetSnapshotMaxDays —— '
              '改了窗口算法就要同步改上限（生成快照那边有同样的断言）');
      // 顺手挡住「窗口被改回两个月」：三个月里最短的一种组合是「2 月(28) + 3 月(31) +
      // 4 月(30)」，两端刚好都不需要补齐 → 89 天。写 84 是给闰年/补齐留的余量，
      // 同时远大于任何两个月组合（最多 31 + 31 + 6 + 6 = 74）。
      expect(n, greaterThanOrEqualTo(84), reason: '窗口只有 $n 天，装不下三个月');
    }
  });
```

- [ ] **Step 2: 跑一遍，确认它红**

Run: `../toolchain/flutter/bin/flutter test test/widget_snapshot_test.dart`
Expected: FAIL —— 两个新用例都红（当前窗口 `[min(本月1日, 本周一), 下月最后一天]` 装不下上个月的 42 格，天数约 68 < 90）。

- [ ] **Step 3: 实现**

把 `app/lib/features/widget/widget_snapshot.dart` 里这两段换掉：

```dart
/// 窗口的**最大**天数。真正用多少由 [widgetWindow] 算：
/// 「上月 + 本月 + 下月」三个月，各自的最坏情况 31 天，再加两端补齐整周最多各 6 天
/// → 6 + 31 + 31 + 31 + 6 = 105。取 112 留余量，由下面的断言兜住。
const int kWidgetSnapshotMaxDays = 112;

/// 快照窗口：`[上月 1 日所在周的周一, 下月最后一天所在周的周日]`。
///
/// 为什么是**整周对齐的三个月**（v0.9.17 改的，原来只到「下月最后一天」）：
/// 月历小组件现在要画**连续的 42 天**，并且能翻到上 / 下月 —— 那张卡能画的每一格
/// 都必须有数据。一条用例（`widget_snapshot_test.dart` 的「窗口覆盖…完整 42 格」）
/// 把这条性质钉住了，改窗口时它会先红。
///
/// 仍然**含窗口里已经过去的天**：本周条要画得出「上周日~本周六」那种跨月的周，
/// 而翻到上个月时那整月本来就是过去的。
({DateTime from, DateTime to}) widgetWindow(DateTime now) {
  final today = dateOnly(now); // UTC 纯日期，年月日即本地日历日
  // Dart 会把越界的 month 归一：month-1 = 0 → 去年 12 月，month+2 且 day=0 → 下月末。
  final prevFirst = DateTime(today.year, today.month - 1, 1);
  final nextLast = DateTime(today.year, today.month + 2, 0);
  final from = DateTime(
      prevFirst.year, prevFirst.month, prevFirst.day - (prevFirst.weekday - 1));
  final to = DateTime(
      nextLast.year, nextLast.month, nextLast.day + (7 - nextLast.weekday));
  return (from: from, to: to);
}
```

（`_mondayOf` / `_sundayOf` 这种小助手**不要**抽 —— 只在 `widgetWindow` 里用一次，
单独抽一个函数反而多一层要跟着改的地方。`DateTime.weekday` 周一 = 1、周日 = 7。）

- [ ] **Step 4: 跑一遍，确认全绿**

Run: `../toolchain/flutter/bin/flutter test test/widget_snapshot_test.dart`
Expected: PASS（含既有的窗口用例 —— `days.length` 那条是按 `widgetWindow` 现算的，跟着新窗口一起变）

- [ ] **Step 5: 跑全家桶**

Run: `../toolchain/flutter/bin/flutter test`
Expected: 全绿（若有红，多半是某处硬写了「窗口 68 天」或「to 是下月最后一天」，逐个按新语义改）

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/widget/widget_snapshot.dart app/test/widget_snapshot_test.dart
git commit -m "feat(widget): 快照窗口扩到「上月+本月+下月」，为翻月备好数据"
```

---

### Task 2: 每个实例一份「显示哪个月」的锚点（Kotlin）

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetStore.kt`（加锚点读写）
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/ShiftWidgetBase.kt`（`onDeleted` 里清掉）
- Test: `app/test/widget_fixed_cards_guard_test.dart`（加一条扫源码的护栏）

**Interfaces:**
- Consumes: `WidgetStore.prefs(context)`（文件 `shift_widget`，与快照同一个 SharedPreferences）
- Produces（Task 3 / 4 要用）：
  - `WidgetStore.monthAnchor(context: Context, widgetId: Int): Long?` —— 那个月 **1 日**的 epochDay；不存在 = 跟随今天
  - `WidgetStore.setMonthAnchor(context: Context, widgetId: Int, epochDayOfFirst: Long?)` —— 传 null = 清掉（回今天）
  - `WidgetStore.clearMonthAnchors(context: Context, widgetIds: IntArray)`

- [ ] **Step 1: 写失败的护栏用例**

在 `app/test/widget_fixed_cards_guard_test.dart` 末尾（`addView` 那条之后）加：

```dart
  // 锚点是**每个实例一份**的落盘状态（「这张卡现在翻到哪个月」）。它的失效方式是
  // **静默**的：删卡时不清，系统把 widgetId 复用给下一张卡，新卡一上来就停在上一张
  // 卡翻到的月份上 —— 不报错、不崩，只是「我的小组件怎么是 11 月？」。
  //
  // 这条只能扫源码：Kotlin 在这个仓库里没有可跑的测试目标（真机是唯一的眼睛，
  // 所以它同时出现在实施计划的真机清单里）。
  test('翻月锚点：删卡要清、键名只有一处拼', () {
    final base = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/ShiftWidgetBase.kt');
    expect(base.contains('clearMonthAnchors'), true,
        reason: 'ShiftWidgetBase.onDeleted 必须清掉被删实例的月份锚点 —— '
            'widgetId 会被系统复用，不清就是「新卡片继承上一张卡的月份」');

    final store = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetStore.kt');
    expect(store.contains(r'"month_$widgetId"'), true,
        reason: '锚点的键名必须由一处拼出来（month_<widgetId>），'
            '读写各拼一遍迟早会出现「写的和读的不是一个键」这种静默失效');
  });
```

- [ ] **Step 2: 跑一遍，确认它红**

Run: `../toolchain/flutter/bin/flutter test test/widget_fixed_cards_guard_test.dart`
Expected: FAIL —— `ShiftWidgetBase.kt` 里没有 `clearMonthAnchors`、`WidgetStore.kt` 里没有那个键名。

- [ ] **Step 3: 实现锚点读写**

在 `WidgetStore.kt` 的 `object WidgetStore` 里（`snapshot()` 附近）加：

```kotlin
    /**
     * 每个实例「现在翻到哪个月」的锚点 —— 那个月 **1 日**的 epochDay；没有 = 跟随今天。
     *
     * 为什么落盘而不是放内存：`RemoteViews` 没有进程内状态（卡片是宿主进程里的
     * 一棵视图树，我们的进程可能根本没起来）。所以「翻到哪个月」必须和快照一样存下来。
     *
     * **存绝对值，不存「相对今天的偏移」**：偏移会让跨天把用户翻到的那个月一起挪走
     * （今天进 10 月，他翻到的「9 月」就变成了「10 月」）。
     */
    @Synchronized
    fun monthAnchor(context: Context, widgetId: Int): Long? {
        val v = prefs(context).getLong(monthKey(widgetId), NO_ANCHOR)
        return if (v == NO_ANCHOR) null else v
    }

    @Synchronized
    fun setMonthAnchor(context: Context, widgetId: Int, epochDayOfFirst: Long?) {
        val e = prefs(context).edit()
        if (epochDayOfFirst == null) {
            e.remove(monthKey(widgetId))
        } else {
            e.putLong(monthKey(widgetId), epochDayOfFirst)
        }
        e.apply()
    }

    /** 删卡时清掉。不清的话系统把 widgetId 复用给新卡时，新卡会继承上一张卡的月份。 */
    @Synchronized
    fun clearMonthAnchors(context: Context, widgetIds: IntArray) {
        if (widgetIds.isEmpty()) return
        val e = prefs(context).edit()
        for (id in widgetIds) e.remove(monthKey(id))
        e.apply()
    }

    /** 键名只在这里拼一次 —— 读、写、清三处各拼一遍迟早会有一个地方拼歪。 */
    private fun monthKey(widgetId: Int) = "month_$widgetId"

    /** `getLong` 的缺省值：SharedPreferences 没有「返回 null 的 long」这种取法。 */
    private const val NO_ANCHOR = Long.MIN_VALUE
```

并在 `ShiftWidgetBase.onDeleted` 里、判「一个不剩」**之前**加一行（顺序无所谓，但放在最前面更显眼）：

```kotlin
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        // 先清掉这几个实例的月份锚点：widgetId 会被系统复用，留着就是「新卡片
        // 一上来停在上一张卡翻到的月份」（静默失效）。
        WidgetStore.clearMonthAnchors(context, appWidgetIds)

        if (!ShiftWidgets.hasAnyInstance(context)) {
            ...
        }
    }
```

- [ ] **Step 4: 跑一遍，确认全绿**

Run: `../toolchain/flutter/bin/flutter test test/widget_fixed_cards_guard_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetStore.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/ShiftWidgetBase.kt \
        app/test/widget_fixed_cards_guard_test.dart
git commit -m "feat(widget): 每个实例落盘一份「现在翻到哪个月」的锚点"
```

---

### Task 3: 月历渲染 —— 连续 42 格，相邻月日数变灰

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`（`monthCard`，约 344-467 行）

**Interfaces:**
- Consumes: `WidgetStore.monthAnchor(context, widgetId)`（Task 2）；`snap.days`（既有）
- Produces（Task 4 要用）两个 **internal** 函数：
  - `WidgetRenderer.monthCovered(snap: WidgetStore.Snapshot?, firstOfMonth: LocalDate): Boolean` —— 「那个月的 42 格全在快照窗口里」。渲染用它决定箭头灰不灰，接收端用它决定这枚点击吞不吞。
  - `WidgetRenderer.displayedMonth(context: Context, widgetId: Int, snap: WidgetStore.Snapshot?): LocalDate` —— 「这个实例**现在显示的是哪个月**」（锚点 ?? 今天，锚点画不出来就当没设）。⚠️ **接收端算目标月时必须用它，不能自己去读 `WidgetStore.monthAnchor`** —— 那样会出现「箭头作用在你没看见的那个月」（锚点还在盘上、但渲染早就忽略它了），正是 spec §4.2 那条「让看到的与箭头作用的永远是同一个状态」要挡的事。

- [ ] **Step 1: 先改渲染（Kotlin 没有测试目标，这一任务没有可写的失败用例）**

⚠️ 这个任务的验收只有两条腿：**Dart 侧那两条既有的结构性护栏不许变红**（`widget_fixed_cards_guard_test.dart` 的 42 槽位 / `removeAllViews`，`widget_layout_whitelist_test.dart` 的白名单），以及 **Task 5 的真机清单**。所以改完先跑一遍那两条护栏，别让结构悄悄坏掉。

Run（改之前先跑一遍，记住基线）：`../toolchain/flutter/bin/flutter test test/widget_fixed_cards_guard_test.dart test/widget_layout_whitelist_test.dart`
Expected: PASS

- [ ] **Step 2: 实现（`monthCard` 里三处 + 新增一个 internal 函数）**

**① 新增 `monthCovered`**（放在 `monthCard` 上方，`object WidgetRenderer` 内）：

```kotlin
    /**
     * 那个月能不能画：它的**42 格**（从该月 1 日所在周的周一起连续 42 天）全在快照
     * 覆盖的范围内。翻月的箭头灰不灰、接收端吞不吞这枚点击，用的都是它。
     *
     * 为什么问「42 格」而不是「这个月在 `snap.months` 里」：窗口是按整周对齐的，
     * 边上那两个月可能**只被蹭到几天** —— 那种月份列在 `months` 里，却画不出一张完整
     * 的月历（大半格子没数据）。判据必须与「画得出来」严格一致，否则箭头亮着、
     * 点下去是一张空卡。
     */
    internal fun monthCovered(snap: WidgetStore.Snapshot?, firstOfMonth: LocalDate): Boolean {
        if (snap == null || snap.days.isEmpty()) return false
        val start = firstOfMonth
            .minusDays((firstOfMonth.dayOfWeek.value - 1).toLong())
            .toEpochDay()
        return start >= snap.days.first().day && start + 41 <= snap.days.last().day
    }
```

**② 显示哪个月**：先在 `monthCovered` 旁边加第二个 internal 函数

```kotlin
    /**
     * 这个实例**现在显示的是哪个月**：锚点 ?? 今天那个月；**锚点那个月要是画不出来
     * 就当没设**（数据过期 / 被挤到窗口外）。
     *
     * ⚠️ **接收端算目标月也走这里**，不许自己去读 `WidgetStore.monthAnchor`：
     * 盘上那个锚点可能已经是一个渲染端不认的值，两边各判一次就会出现「箭头作用在你
     * 没看见的那个月」—— 点一下跳到莫名其妙的地方。
     */
    internal fun displayedMonth(
        context: Context,
        widgetId: Int,
        snap: WidgetStore.Snapshot?,
    ): LocalDate {
        val todayFirst = LocalDate.now().withDayOfMonth(1)
        val anchored = WidgetStore.monthAnchor(context, widgetId)
            ?.let { LocalDate.ofEpochDay(it).withDayOfMonth(1) }
        return if (anchored != null && monthCovered(snap, anchored)) anchored else todayFirst
    }
```

然后把 `monthCard` 开头那段

```kotlin
        val today = LocalDate.now()
        val todayEpoch = today.toEpochDay()
```

换成

```kotlin
        val today = LocalDate.now()
        val todayEpoch = today.toEpochDay()
        // 显示哪个月见 `displayedMonth` 的注释（锚点在盘上、但画不出来时按没设处理）。
        val firstOfMonth = displayedMonth(context, widgetId, snap)
```

**③ 月份标题**：把

```kotlin
        val title = snap.months.firstOrNull { it.y == today.year && it.m == today.monthValue }
```

换成

```kotlin
        val title = snap.months.firstOrNull {
            it.y == firstOfMonth.year && it.m == firstOfMonth.monthValue
        }
```

**④ 42 格**：把整段（从 `val firstOfMonth = today.withDayOfMonth(1)` 到循环结束）换成

```kotlin
        // ── 42 格：从「该月 1 日所在周的周一」起**连续** 42 天 ──
        //
        // 月头月尾那几格因此画的是**相邻月份**的日子（日数字走 muted），整张卡读起来
        // 是一段连续的日子。窗口外的格仍然 GONE —— 「相邻月」与「没数据」是两回事。
        val leading = firstOfMonth.dayOfWeek.value - 1   // 周一 = 1 → 前导天数
        val gridStart = firstOfMonth.minusDays(leading.toLong())
        val slotIds = IntArray(42) { i ->
            context.resources.getIdentifier("wg_m_slot${i + 1}", "id", context.packageName)
        }

        for (slot in 0 until 42) {
            // 先清空再填，理由与 `weekStrip` 那处逐字相同（含放在循环开头而非 addView
            // 前面的取舍）。42 格每格都要清 —— 窗外那几格也走这里。
            v.removeAllViews(slotIds[slot])
            val date = gridStart.plusDays(slot.toLong())
            val epoch = date.toEpochDay()
            val i = snap.days.indexOfFirst { it.day == epoch }
            if (i < 0) {
                // 快照没盖到这一天（窗口到头了 / 快照过期）。挖空 —— 画一张理直气壮的
                // 错日子比空着更糟。
                v.setViewVisibility(slotIds[slot], android.view.View.GONE)
                continue
            }
            v.setViewVisibility(slotIds[slot], android.view.View.VISIBLE)

            // 点某一格 → 打开 App 并跳到那天。相邻月的格同样如此（点 8 月 31 日就跳
            // 8 月 31 日，语义自洽）。格子占槽位 1..42（一个实例 64 个槽位）。
            v.setOnClickPendingIntent(
                slotIds[slot],
                launchIntent(context, cellRequestCode(widgetId, slot), epochDay = epoch.toInt()),
            )

            val d = snap.days[i]
            val inMonth = date.year == firstOfMonth.year &&
                date.monthValue == firstOfMonth.monthValue
            val isToday = epoch == todayEpoch
            val c = RemoteViews(context.packageName, R.layout.widget_month_cell)

            // 可见性两个方向都要设满：宿主 `reapply` 只重放新动作，漏设的一边会留着
            // 上一次的状态。
            c.setViewVisibility(R.id.wg_mc_day, android.view.View.VISIBLE)
            c.setTextViewText(R.id.wg_mc_day, date.dayOfMonth.toString())
            // 「今天」只走主色、**不许加粗**（`TextView` 没有 `setTypeface(int)`，
            // 反射会在宿主进程抛 `ActionException`）。相邻月的日数字走 muted ——
            // 那是这张卡上唯一表达「这个月从哪开始」的地方。
            c.setTextColor(
                R.id.wg_mc_day,
                when {
                    isToday -> snap.accent
                    inMonth -> ink
                    else -> muted
                },
            )

            // 没班次就不画胶囊 —— 与 App 日历格一致（`shift == null` 时那块根本不画）。
            // **相邻月的格照样画**（用户 2026-09-30 选的「日数变灰、胶囊照画」）。
            // **不能**拿 `wg_empty_*` 顶上：`tintedChip` 里 `Paint.setAlpha` 会**覆盖**
            // 颜色字节自带的 alpha（fill 写死 36、stroke 写死 115），`#14000000` 会变成
            // 一条 45% 的黑描边环，比 App 的长相响得多。
            if (d.hasShift) {
                c.setViewVisibility(R.id.wg_mc_pill, android.view.View.VISIBLE)
                c.setViewVisibility(R.id.wg_mc_abbr, android.view.View.VISIBLE)
                // 尺寸恒定 40×18dp：一格一尺寸会让 `WidgetChip` 的位图缓存失效
                // （key 含尺寸），42 格就把缓存冲爆。见本函数的 KDoc。
                c.setImageViewBitmap(
                    R.id.wg_mc_pill,
                    WidgetChip.tintedChip(d.color, dpToPx(context, 40), dpToPx(context, 18)),
                )
                c.setTextViewText(R.id.wg_mc_abbr, d.shiftAbbr)
                c.setTextColor(R.id.wg_mc_abbr, ink)
            } else {
                c.setViewVisibility(R.id.wg_mc_pill, android.view.View.GONE)
                c.setViewVisibility(R.id.wg_mc_abbr, android.view.View.GONE)
            }

            c.setViewVisibility(R.id.wg_mc_lunar, android.view.View.VISIBLE)
            c.setTextViewText(R.id.wg_mc_lunar, d.lunarShort)
            c.setTextColor(R.id.wg_mc_lunar, if (d.lunarIsHoliday) holiday else muted)

            v.addView(slotIds[slot], c)
        }
```

并把 `monthCard` 的 KDoc 里「前导空格由本月 1 日的星期几现算」「42 格」那几句按新语义改写（**别再写「前导 / 尾随空格」**—— 它们现在是相邻月的日子）。

- [ ] **Step 3: 跑两条结构性护栏**

Run: `../toolchain/flutter/bin/flutter test test/widget_fixed_cards_guard_test.dart test/widget_layout_whitelist_test.dart`
Expected: PASS（42 槽位 id、`removeAllViews` 顺序、视图白名单都不受影响）

- [ ] **Step 4: 编译一遍（Kotlin 有编译期错误就得当场修）**

Run: `../toolchain/flutter/bin/flutter build apk --release --target-platform android-arm64`
Expected: 成功（22 MB 上下）。⚠️ 若报 `Unresolved reference: monthCovered`，检查它是不是被写成了 `private`（Task 4 的接收端要用它）。

- [ ] **Step 5: 提交**

```bash
git add app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt
git commit -m "feat(widget): 月历 42 格改成连续 42 天，相邻月日数变灰"
```

---

### Task 4: 标题行三件套 + 翻月广播

**Files:**
- Modify: `app/android/app/src/main/res/layout/widget_month_card.xml`（标题那一行）
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`（标题行渲染 + 箭头 PendingIntent + requestCode）
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRefreshReceiver.kt`（新 action + 处理）
- Test: `app/test/widget_fixed_cards_guard_test.dart`（箭头 id 与 requestCode 基数的护栏）

**Interfaces:**
- Consumes: `WidgetRenderer.monthCovered`（Task 3）、`WidgetStore.monthAnchor/setMonthAnchor`（Task 2）、`ShiftWidgets.render`（既有，internal）
- Produces: 两个新 id `wg_m_prev` / `wg_m_next`；action `WidgetRefreshReceiver.ACTION_MONTH_STEP = "com.daoban.shiftassistantpro.WIDGET_MONTH_STEP"`；extras `"widgetId"`（Int）与 `"delta"`（Int，`-1`/`+1`/`0`）

- [ ] **Step 1: 写失败的护栏用例**

在 `app/test/widget_fixed_cards_guard_test.dart` 里加：

```dart
  // 标题行的两枚箭头靠 **id 拼名 + 一个跨语言的常量** 接起来：id 在布局里、
  // 取它在 Kotlin 里、action 字符串在发送端与接收端各写一遍（Kotlin 之间没有共享通道
  // 的检查）。这三处任意一处歪掉都是静默的：箭头画出来但点了没反应、或者点了没人接。
  test('翻月箭头：id 齐全、action 两边一致、requestCode 落在广播池空段', () {
    final xml = _read('android/app/src/main/res/layout/widget_month_card.xml');
    for (final id in ['wg_m_prev', 'wg_m_title', 'wg_m_next']) {
      expect(xml.contains('@+id/$id'), true, reason: '布局里缺 $id');
    }

    final kt = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
    for (final id in ['wg_m_prev', 'wg_m_next']) {
      expect(kt.contains('R.id.$id'), true, reason: '渲染器没有往 $id 上挂东西');
    }

    // action 常量：发送端（渲染器）与接收端必须逐字一致。
    final rx = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRefreshReceiver.kt');
    expect(rx.contains('WIDGET_MONTH_STEP'), true, reason: '接收端没有处理翻月 action');
    expect(rx.contains('com.daoban.shiftassistantpro.WIDGET_MONTH_STEP'), true);
    expect(kt.contains(rxAction(kt, rx)), true,
        reason: '渲染器里用的 action 字符串必须与接收端那一个逐字相同');

    // requestCode：新基数必须落在既有广播池占用**之上**。已知占用（AGENTS 的
    // 「requestCode 池」那条）：班次闹钟 0..400、自定义闹钟 10000..11000、
    // 待办提醒 20000..39999、重复待办 40000..41999、选铃声 40071、刷新闹钟 40081。
    final m = RegExp(r'WIDGET_MONTH_REQ_BASE\s*=\s*([\d_]+)').firstMatch(kt);
    expect(m, isNotNull, reason: 'WidgetRenderer.kt 里找不到 WIDGET_MONTH_REQ_BASE');
    final base = int.parse(m!.group(1)!.replaceAll('_', ''));
    expect(base, greaterThan(42000),
        reason: '基数 $base 落在既有广播池的号段里 —— 撞号的症状是「点这张卡的箭头、'
            '那张卡翻页」（Intent.filterEquals 不比 extras）');
    expect(RegExp(r'WIDGET_MONTH_REQ_BASE\s*\+\s*widgetId\s*\*\s*\d+\s*\+')
            .hasMatch(kt), true,
        reason: '编号必须逐实例、逐方向展开（形如 BASE + widgetId * 步长 + 方向），'
            '两个实例共用一个 requestCode 就会互相翻页');
  });
```

上面用到的 `rxAction` 是个小助手，加在文件末尾的 `main()` 之外：

```dart
/// 从接收端源码里抠出翻月 action 的字面量，用来跟渲染端比对。
/// 抠不到就返回一个不可能匹配的串（让调用点那条断言去报错，而不是这里 throw）。
String rxAction(String renderer, String receiver) {
  final m = RegExp(r'WIDGET_MONTH_STEP\s*=\s*"([^"]+)"').firstMatch(receiver);
  return m?.group(1) ?? '<接收端里没有 WIDGET_MONTH_STEP 的字面量>';
}
```

- [ ] **Step 2: 跑一遍，确认它红**

Run: `../toolchain/flutter/bin/flutter test test/widget_fixed_cards_guard_test.dart`
Expected: FAIL —— 布局里还没有 `wg_m_prev` / `wg_m_next`。

- [ ] **Step 3: 布局：标题那个 TextView 换成一行三件套**

`widget_month_card.xml` 里，把开头那个

```xml
    <TextView
        android:id="@+id/wg_m_title"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:gravity="center"
        android:textSize="13sp"
        android:maxLines="1"
        android:ellipsize="end" />
```

换成

```xml
    <!-- 标题行：‹ 2026年9月 ›。箭头是 TextView（在 RemoteViews 白名单里，
         也就没有「加一张矢量图」带来的小米按资源 id 缓存 drawable 那类问题）；
         ‹ › 是符号不是文案，与语言无关。
         行高定 28dp：箭头要有像样的触摸目标，而这一行原先只有 ~18dp。 -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="28dp"
        android:orientation="horizontal">

        <TextView
            android:id="@+id/wg_m_prev"
            android:layout_width="32dp"
            android:layout_height="match_parent"
            android:gravity="center"
            android:textSize="16sp"
            android:maxLines="1"
            android:text="&#8249;" />

        <TextView
            android:id="@+id/wg_m_title"
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="1"
            android:gravity="center"
            android:textSize="13sp"
            android:maxLines="1"
            android:ellipsize="end" />

        <TextView
            android:id="@+id/wg_m_next"
            android:layout_width="32dp"
            android:layout_height="match_parent"
            android:gravity="center"
            android:textSize="16sp"
            android:maxLines="1"
            android:text="&#8250;" />
    </LinearLayout>
```

（`&#8249;` / `&#8250;` 就是 `‹` / `›`。写实体而不是字面量：XML 文件是 UTF-8，
但这两个字符长得太像 `<` `>`，实体更不容易被后来的人或工具改坏。）

- [ ] **Step 4: 渲染器：标题行 + 两枚箭头**

在 `WidgetRenderer.kt` 里：

**① action 与 requestCode 常量**（放在 `object WidgetRenderer` 顶部常量区，`WIDGET_REQ_BASE` 附近）：

```kotlin
    /**
     * 翻月那两枚箭头的 requestCode 基数。**广播池**，与上面 `WIDGET_REQ_BASE`
     * （活动池，点格开 App）是两回事。
     *
     * 900_000 离既有占用都够远：班次闹钟 0..400、自定义闹钟 10000..11000、待办提醒
     * 20000..39999、重复待办 40000..41999、选铃声 40071、刷新闹钟 40081。
     * 编号 = BASE + widgetId * 4 + dir（dir：0=上月、1=下月、2=回今天，第 4 档留给
     * 将来）—— **每个实例、每个方向各一枚**：`Intent.filterEquals` 不比 extras，
     * 撞号会让两张卡共用一个箭头（点这张、那张翻页）。由
     * `widget_fixed_cards_guard_test.dart` 钉住基数与展开形式。
     */
    private const val WIDGET_MONTH_REQ_BASE = 900_000
```

**② 生成 PendingIntent 的小助手**（紧挨着 `cellRequestCode` 那一段）：

```kotlin
    /** 翻月 / 回今天：发给 [WidgetRefreshReceiver]（广播池，与活动池无关）。 */
    private fun monthStepIntent(context: Context, widgetId: Int, delta: Int): PendingIntent {
        val dir = when {
            delta < 0 -> 0
            delta > 0 -> 1
            else -> 2      // 点标题 = 回今天
        }
        val i = Intent(context, WidgetRefreshReceiver::class.java)
            .setAction(WidgetRefreshReceiver.ACTION_MONTH_STEP)
            .putExtra(WidgetRefreshReceiver.EXTRA_WIDGET_ID, widgetId)
            .putExtra(WidgetRefreshReceiver.EXTRA_DELTA, delta)
        return PendingIntent.getBroadcast(
            context,
            WIDGET_MONTH_REQ_BASE + widgetId * 4 + dir,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
```

**③ 标题行渲染**：把 Task 3 里改过的「月份标题」那一段换成

```kotlin
        // ── 标题行：‹ 月份 › ──
        //
        // **箭头永远设点击**，哪怕那一侧没得翻：`RemoteViews` 的 `reapply` 只重放
        // **新的**动作串，**没有任何办法撤掉上一次设过的点击**（与 v0.9.9 那条
        // `removeAllViews` 同源：宿主会复用已在的那棵视图树）。所以「到头了」由
        // **接收端**判 —— 颜色只作提示。
        val title = snap.months.firstOrNull {
            it.y == firstOfMonth.year && it.m == firstOfMonth.monthValue
        }
        if (title == null) {
            // 查不到就隐藏（绝不借相邻月份的标题顶上）—— 既有纪律，不改。
            v.setViewVisibility(R.id.wg_m_title, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_m_title, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_m_title, title.title)
            v.setTextColor(R.id.wg_m_title, muted)
        }
        val canPrev = monthCovered(snap, firstOfMonth.minusMonths(1))
        val canNext = monthCovered(snap, firstOfMonth.plusMonths(1))
        // 能翻 = ink，翻不动 = muted（标题本身也走 muted：翻不动时两者同档）。
        v.setTextColor(R.id.wg_m_prev, if (canPrev) ink else muted)
        v.setTextColor(R.id.wg_m_next, if (canNext) ink else muted)
        v.setOnClickPendingIntent(R.id.wg_m_prev, monthStepIntent(context, widgetId, -1))
        v.setOnClickPendingIntent(R.id.wg_m_next, monthStepIntent(context, widgetId, +1))
        v.setOnClickPendingIntent(R.id.wg_m_title, monthStepIntent(context, widgetId, 0))
```

- [ ] **Step 5: 接收端：新 action + 处理**

`WidgetRefreshReceiver.kt` 整个换成：

```kotlin
package com.daoban.shiftassistantpro

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.time.LocalDate

/**
 * 小组件那两条广播的落点：**刷新**（三张卡一起重画）与**翻月**（只有月历那张）。
 *
 * 为什么不让闹钟直接打给某一个 provider：三张卡是平级的，指向其中一张会让
 * 「谁负责刷新」变成一件没有理由的耦合（那张卡被删掉/改名时会连累另两张）。
 *
 * 只由本 App 自己发（`exported="false"` + 显式组件），不接任何外部意图。
 */
class WidgetRefreshReceiver : BroadcastReceiver() {

    companion object {
        /**
         * 翻月。发送端是 `WidgetRenderer.monthStepIntent` —— **两边的字符串必须逐字一致**
         * （Kotlin 之间没有共享通道，写歪一个是静默的：箭头画得出来、点了没反应）。
         * 由 `widget_fixed_cards_guard_test.dart` 扫源码比对。
         */
        const val ACTION_MONTH_STEP = "com.daoban.shiftassistantpro.WIDGET_MONTH_STEP"
        const val EXTRA_WIDGET_ID = "widgetId"
        const val EXTRA_DELTA = "delta"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            WidgetRefreshScheduler.ACTION_REFRESH -> ShiftWidgets.refreshAll(context)
            ACTION_MONTH_STEP -> handleMonthStep(context, intent)
            else -> return
        }
    }

    /**
     * 翻上 / 下月（`delta = ±1`），或点标题回今天（`delta = 0`）。
     *
     * **越界在这里吞掉**：箭头那一侧没得翻时渲染端把它画成灰的，但灰的箭头**也带着
     * 点击**（`reapply` 撤不掉上次设过的点击，见渲染端那段注释）。所以「能不能翻」
     * 必须由这里判 —— 判据与渲染端同一个 `WidgetRenderer.monthCovered`。
     */
    private fun handleMonthStep(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_WIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) return
        val mgr = AppWidgetManager.getInstance(context)
        // 卡片可能刚刚被删掉（删卡与点击完全可以同时发生）—— 查不到就什么都不做。
        if (mgr.getAppWidgetInfo(id) == null) return

        val snap = WidgetStore.snapshot(context)
        // **当前显示的是哪个月，问渲染端那一个实现**（`displayedMonth`）——
        // 自己读盘上的锚点会踩到「锚点还在、但渲染早就忽略它了」那种情形，
        // 于是箭头作用在一个你看不见的月份上。
        val current = WidgetRenderer.displayedMonth(context, id, snap)
        val delta = intent.getIntExtra(EXTRA_DELTA, 0)
        val target = if (delta == 0) {
            null                                    // 回今天 = 清掉锚点
        } else {
            current.plusMonths(delta.toLong())
        }
        if (target != null && !WidgetRenderer.monthCovered(snap, target)) return

        WidgetStore.setMonthAnchor(context, id, target?.toEpochDay())
        // 只重画这一个实例（翻月与另外两张卡无关），快照复用刚读到的那份。
        ShiftWidgets.render(context, mgr, snap, WidgetVariant.MONTH, intArrayOf(id))
    }
}
```

- [ ] **Step 6: 跑护栏 + 编译**

Run: `../toolchain/flutter/bin/flutter test test/widget_fixed_cards_guard_test.dart test/widget_layout_whitelist_test.dart`
Expected: PASS

Run: `../toolchain/flutter/bin/flutter build apk --release --target-platform android-arm64`
Expected: 成功。⚠️ 常见错误：`EXTRA_WIDGET_ID` / `ACTION_MONTH_STEP` 忘了写进 `companion object`（`Unresolved reference`）；`monthCovered` 还是 `private`。

- [ ] **Step 7: 提交**

```bash
git add app/android/app/src/main/res/layout/widget_month_card.xml \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRefreshReceiver.kt \
        app/test/widget_fixed_cards_guard_test.dart
git commit -m "feat(widget): 月历标题行加 ‹ › 翻月，点月份回今天"
```

---

### Task 5: 收尾 —— 版本、日志、文档、构建、发布 + 真机验收

**Files:**
- Modify: `app/pubspec.yaml`、`app/lib/core/app_info.dart`、`app/lib/features/profile/app_dialogs.dart`
- Modify: `AGENTS.md`（版本史、最近改动、requestCode 池那条清单、测试条数）、`PRODUCT_SPEC.md`（小组件那一段）
- Create: `tools/gh/release-notes-v0.9.17.md`

**Interfaces:**
- Consumes: 前四个任务的成果
- Produces: 一版可以装的 APK + 一份要交给用户真机核的清单

- [ ] **Step 1: 版本号（末位 +1、build +1）**

`app/pubspec.yaml`：`version: 0.9.16+120` → `0.9.17+121`
`app/lib/core/app_info.dart`：`appVersion = '0.9.16'` → `'0.9.17'`

Run: `../toolchain/flutter/bin/flutter test test/app_info_test.dart`
Expected: PASS

- [ ] **Step 2: 更新日志（prepend 一条、删最旧一条、保持 10 条）**

`app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh` / `_changelogEn` 各 prepend：

```dart
const String _changelogZh = 'v0.9.17\n'
    '· 桌面小组件那张月历（最大的那张）现在把上个月和下个月的日子连起来一起画了：月头月尾那几格不再是空的，相邻的日数字淡一档、班次照常显示，整张卡读起来是一段连续的日子\n'
    '· 那张卡的标题行多了左右两个箭头：点一下翻上 / 下月，翻到没有数据的月份那侧会变灰；点中间的月份文字回到今天那个月\n'
    '· 翻到你关注的月份之后，跨天、跨月都不会把你拽回来 —— 停在你翻到的那个月，直到你自己点回今天\n\n'

    'v0.9.16\n'
```

英文那条同义（`'· The month widget (the largest one) now draws the previous and next month\'s days as well…'` 三段），**不许出现 markdown 标记**（`changelog_window_test.dart` 会扫）。删掉窗口里最旧的一版（现在是 v0.9.7）。

Run: `../toolchain/flutter/bin/flutter test test/changelog_window_test.dart`
Expected: PASS（10 条、版本递减、首条 = 当前版本、中英一致、无 markdown）

- [ ] **Step 3: AGENTS.md 三处**

① **版本史**末尾追加：`→ 0.9.17(+121) 测试版（**月历小组件连月 + 翻月**：42 格改成连续 42 天、相邻月日数变灰；标题行 ‹ › 翻月、点月份回今天；每个实例落盘一份月份锚点；快照窗口扩到上月+本月+下月，协议版本不动）。更早见`

② **「关键决策与坑」里 requestCode 那条清单**（搜「给 `MainActivity` 造 `getActivity` 的 PendingIntent」）追加一句：**小组件翻月另占广播池 `900_000` 起、步长 4**（`BASE + widgetId*4 + dir`，dir 0/1/2），它与活动池那一段互不相干。

③ **「最近改动」**开头插入 v0.9.17 一条（三段：为什么、怎么改、验收），并更新验收标准里的测试条数（跑完全套后填实际值，当前 523 + 本计划新增的用例数）。

- [ ] **Step 4: PRODUCT_SPEC.md 的小组件段**

把 4×5 那段的「月份由 `LocalDate.now()` 定」改成新语义：42 格是**连续 42 天**（相邻月日数淡一档）；显示哪个月由**每个实例落盘的锚点**决定（默认今天那个月）；标题行 ‹ › 翻月、点月份回今天；能翻的范围 = 快照覆盖到的月份（上月 / 本月 / 下月），到头变灰。同时把快照窗口那句改成「上月 + 本月 + 下月」。

- [ ] **Step 5: 全量验收**

Run: `../toolchain/flutter/bin/flutter analyze`
Expected: `No issues found!`

Run: `../toolchain/flutter/bin/flutter test`
Expected: 全绿（条数 ≥ 523 + 新增）

Run: `../toolchain/flutter/bin/flutter test tool/visual/`
Expected: 246 条全绿（⚠️ **原生小组件画不进这套工装** —— 它是 RemoteViews，工装只能渲染 Flutter 屏。所以这张卡这次的观感变化**只能真机看**，见 Step 8）

- [ ] **Step 6: 构建 + 归档 + 校验**

```bash
cd app
export JAVA_HOME="C:/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/jdk" \
       ANDROID_HOME="C:/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/android-sdk" \
       ANDROID_SDK_ROOT="C:/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/android-sdk" \
       GRADLE_USER_HOME="C:/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/gradle-home" \
       PUB_CACHE="C:/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/pub-cache" \
       ANDROID_USER_HOME="C:/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/android-user"
../toolchain/flutter/bin/flutter build apk --release --target-platform android-arm64
cd ..
cp app/build/app/outputs/flutter-apk/app-release.apk "dist/倒班助手Pro-v0.9.17.apk"
toolchain/android-sdk/build-tools/36.0.0/aapt2.exe dump badging "dist/倒班助手Pro-v0.9.17.apk" | head -1
```

Expected: `versionCode='121' versionName='0.9.17'`、包名 `com.daoban.shiftassistantpro`

- [ ] **Step 7: 发布**

```bash
git add -A
git commit -m "chore(release): v0.9.17（月历小组件连月 + 翻月）"
git tag v0.9.17 && git push origin beta && git push origin v0.9.17
export GH_CONFIG_DIR="C:\\Users\\Alec\\AppData\\Roaming\\GitHub CLI"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/release.ps1 -SkipConfirm
curl -s https://raw.githubusercontent.com/Alec-WangLi/DaoBanAssistantPro/main/latest.json
```

Expected: Release 建好、`latest.json` 的 `prerelease.version` = `0.9.17`（第 7b 步会自己同步到 main；没同步成功就按 AGENTS 里那段手动补）

- [ ] **Step 8: 交给用户的真机验收清单**（Kotlin 没有测试目标，这是那半边唯一的眼睛）

发版后请用户装一版并核这五条（**改完小组件资源后先 `adb shell am force-stop com.miui.home` 再验**，否则小米桌面会按资源 id 吃到缓存的位图而误判成「没生效」）：

1. 4×5 那张卡的月头月尾：相邻月的日子画出来了、日数淡一档、班次胶囊照画、月分界一眼能分。
2. 翻月：`‹` `›` 各点几下 —— 上 / 下月都到得了；翻到头那侧箭头是灰的、**点了什么都不发生**。
3. 点中间的月份文字 → 回到今天那个月；翻到别的月之后**过一晚（跨天）再看不被拽回来**。
4. 相邻月那一格点下去 → 打开 App 并跳到**那一天**（不是本月同号那天）。
5. **升级后先别打开 App，看一眼桌面**（那一份快照还是旧版 68 天的窗口）：本月照常画、相邻月那几格是空的、箭头是灰的；打开一次 App 之后它们就都出来了 —— 这条验的是 spec §4.1 那条「协议版本不动、两边互相降级」，**别跳过**。
6. **每格高度**：42 格恒定 6 行之后每行从 5 行月的约 77dp 降到约 63~65dp（这是本轮唯一的观感变化，spec 里写明只有真机能判）。看不看得清、要不要把日数字/胶囊调小一档，由用户拍板。
7. 顺手删掉这张卡再加回来：应当是**今天那个月**（不是删之前翻到的那个月）。

---

## 计划外的提醒（写给执行的人）

- **原生侧没有测试**这件事不是本计划的疏漏：Kotlin 在这个仓库里没有可跑的目标，所以凡是「错了也不报错」的结构性约定（id 拼名、跨语言常量、锚点清理、requestCode 池）一律落成 `widget_fixed_cards_guard_test.dart` 里的源码扫描用例，行为层面的观感只能真机看。**别为了「有测试」去搭一套 Kotlin 测试基建** —— 那是另一件事，且这个仓库的既有取舍写得很清楚。
- **`widgetWindow` 改宽之后 `boundaries` 会变多**（每天最多 3 条 × 105 天）。这只影响快照 JSON 的大小（几十 KB），`scheduleNextRefreshIfNeeded` 仍是「取第一个未来的时刻」，不用动。
