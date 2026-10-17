# 桌面小组件再贴齐 + 底栏光晕接缝 · 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消掉液态玻璃那圈光谱在正右方的接缝；把三张桌面小组件的字号与系统字号解耦并按格子尺寸缩放；把月历「今天」改回与 App 同款的半透明块、周标题改单字；把今日卡的上下留白收掉并补齐 App 信息卡有的三行。

**Architecture:** 接缝那条是纯 Dart 的单点改动（`spectralSweep()` 的色相行程 300° → 360°）。桌面那三张是「Dart 侧烘焙快照 → Kotlin 侧只排版」这条既有链路的延伸：新文案与新数字一律加进 `widget_snapshot.dart`（协议仍是 v2，只增字段），Kotlin 侧只加「按格子尺寸算缩放系数」与「画半透明块」两件事。

**Tech Stack:** Flutter/Dart（`spectralSweep`、快照生成）+ Android Kotlin（`RemoteViews` / `AppWidget`，minSdk 26）；测试是 `flutter test`（含 Dart 侧扫源码的小组件护栏），Kotlin 无测试目标 —— 靠护栏 + 真机 adb 出图。

**Spec:** `docs/superpowers/specs/2026-10-15-widget-parity-2-and-glass-seam-design.md`

## Global Constraints

- **minSdk 26**：`RemoteViews.setViewLayoutWidth/Height` 是 API 31 才有的，**不许用**。
- **不引入任何新依赖。**
- **Kotlin 在这个仓库里没有可跑的测试目标**：Kotlin 的改动靠 ① Dart 侧扫源码的护栏 ② 真机 adb 出图，两条都不可省。
- **桌面小组件的用户可见文案必须全部来自 Dart 侧快照** —— Kotlin 里**不许出现用户可见的中文字面量**（全仓唯一的例外是 `AlarmLog` 的日志串）。
- **快照协议版本仍是 `v2`**（`kWidgetSnapshotVersion = 2`）：只增字段、不换版本号。
- **每一处往容器 `addView` 之前必须先 `removeAllViews`**（`RemoteViews` 的 `reapply` 不清子视图，漏了就是「内容一变就重影」）。
- **不要跑 `dart format`**（工具链是新版格式化器，一跑就是几百行无关 diff）；只跑 `flutter analyze`。
- **版本号**：`X.Y` 由用户定，AI 只改末位 `Z` 与 `build`；`pubspec.yaml` 与 `lib/core/app_info.dart` 两处必须同步（`app_info_test.dart` 盯着）。
- **验收基线**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿且**只增不减**（当前 1063 条）；`flutter test tool/visual/` 全跑 + 逐张比基线，差异逐条解释。
- **分支**：测试版一律在 `beta` 上做与提交。
- 构建前先 `. C:\...\shiftassistant\tools\build-env.ps1`（设 `JAVA_HOME` / `ANDROID_HOME` / `PUB_CACHE`）；真机用 `toolchain/android-sdk/platform-tools/adb.exe`（设备 `7288a9b0`，1200×2608 @480dpi = **3×**）。

## Review Focus

写测试时逐条对照，每条都要落到某个任务的用例里：

1. **系统字号极端值下的裁切**：把系统 `font_scale` 拨到 `0.85` 与 `2.0`，三张卡的渲染结果**必须与 1.0 完全一致**。桌面外壳是定尺寸且**没有滚动**，字号写死 `sp` 时 2.0 会切内容（今日卡的时间行被切、班组整行消失 —— 真机实测过）。
2. **浅主色下「今天」那格的可读性**：用户把主色换成 **teal / orange** 时，半透明块上的日数字与农历**必须仍读得清**。旧实现走 `onSolidInk`，在浅主色上会给白字 —— 那是**静默**的（默认那颗蓝是对的）。
3. **空白表方案（跟随法定节假日）下的降级**：`monthTallyFor` 必须返回 `null`（整月没有班次定义），`alarmNote` 在无班次那天必须是 `null`。这两样为 null 时，卡上**不画那一行**，而不是画一句「null」或留一条空白。
4. **跨天 / 跨月之后那三行还是新鲜的**：跨天刷新时原生**只重渲染旧快照、不跑 Dart**。`shiftNote` 按日烘焙、`tally` 挂在 `months[]` 上，正是为了零点之后取到的仍是新一天的。翻月（‹ › 或跨月）之后月份统计必须换成新月份的。
5. **快照窗口边缘的降级**：翻到窗口外的月份、或 `days[]` 里没有对应项时，标题行与那三行**不画**，不是画旧值、也不是抛异常。

---

### Task 1: 光谱环的接缝（正右方那 62° 的跳变）

**Files:**
- Modify: `app/lib/core/glass/liquid_lens.dart`（`spectralSweep()`，约 1181 行）
- Test: `app/test/liquid_lens_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `spectralSweep({required Color accent, required double alpha, required double floor, required double span, required bool pow2, double hueLag = 0, double anchorDeg = spectralSweepRestAnchor, int steps = 24})` —— **签名一个参数都不改**，只改色相行程。四个既有调用点（同文件 847 / 1065 / 1082 / 1113）与日历那侧全部自动跟上。

- [ ] **Step 1: 写失败用例**

在 `app/test/liquid_lens_test.dart` 追加：

```dart
test('光谱环没有接缝：t=0 与 t=1 两端颜色相同', () {
  final g = spectralSweep(
    accent: const Color(0xFF4C8DFF), alpha: 1, floor: 0.58, span: 0.42, pow2: true,
  );
  expect(g.colors.first, g.colors.last,
      reason: '色相没走满一圈 ⟹ 起点与终点落在同一个屏幕方位（正右方）却不同色，'
              '那就是用户报的「一刀切」');
});

test('光谱环最暗那一侧仍有颜色（floor 没被绕过）', () {
  final g = spectralSweep(
    accent: const Color(0xFF4C8DFF), alpha: 1, floor: 0.58, span: 0.42, pow2: true,
  );
  // stops 与 colors 等长；取每一个 stop 的 alpha，全部 ≥ floor×alpha×255 的九折。
  for (final c in g.colors) {
    expect(c.a, greaterThanOrEqualTo(0.58 * 0.9),
        reason: 'v0.10.7 修过这条：最暗那一侧要是没有色，彩边就只剩半边');
  }
});
```

- [ ] **Step 2: 跑，确认第一条红**

Run: `flutter test test/liquid_lens_test.dart -p vm`
Expected: 第 1 条 **FAIL**（两端色相相差 60°）；第 2 条 PASS。

- [ ] **Step 3: 改 `spectralSweep()` 的色相行程**

`app/lib/core/glass/liquid_lens.dart` 里那一行：

```dart
// 改前
(base.hue + hueLag + 300 * t) % 360,
// 改后
// 走满 360° 而不是 300°：`SweepGradient` 的 t=0 与 t=1 落在**同一个屏幕方位**
// （正右方），300° 会让那里留一道 60° 的色相硬边 —— 真机上量到那一步跳 62°，
// 别的地方只有 0~11°。走满 360 之后两端同色，边就不存在了。
// **别改成往复活（0→300→0）**：那会得到镜像对称的色相，读起来像两半拼的。
(base.hue + hueLag + 360 * t) % 360,
```

顺带把该函数上方那段 doc 里「绕主色走 300°」的说法改成 360°，并把用户 2026-10-15 那条反馈记进去。

- [ ] **Step 4: 跑，确认全绿**

Run: `flutter test test/liquid_lens_test.dart -p vm`
Expected: PASS。

- [ ] **Step 5: 跑全套，确认没有别的用例被色相变化打红**

Run: `flutter test`
Expected: 全绿（若 `glass_tier_test` / `liquid_track_test` 有按色相取样点的断言，按新值更新并写明理由 —— **不许放宽公差糊过去**）。

- [ ] **Step 6: 提交**

```bash
git add app/lib/core/glass/liquid_lens.dart app/test/liquid_lens_test.dart
git commit -m "fix(glass): 光谱环色相走满 360°，消掉正右方那道 62° 的接缝"
```

---

### Task 2: 月历周标题改单字 + 顶层补「其他班组」标签

**Files:**
- Modify: `app/lib/features/widget/widget_snapshot.dart`（约 218 行的 `'weekdays'`、返回的顶层 map）
- Test: `app/test/widget_snapshot_test.dart`

**Interfaces:**
- Consumes: `L10n.weekdays`（`List<String>`，zh = `['一'..'日']`，en = `['M','T','W','T','F','S','S']`）、`L10n.otherCrews`
- Produces: 快照顶层多一个 `'otherCrews': String`；`'weekdays'` 的元素从「周一」变成「一」。**`days[].weekday` 不动**（周条与今日卡读的是它，仍是「周一」）。

- [ ] **Step 1: 写失败用例**

在 `app/test/widget_snapshot_test.dart` 追加：

```dart
test('周标题是单字（与 App 日历页同源），而 days[].weekday 仍是「周一」', () {
  final snap = buildWidgetSnapshot(chain: chain, now: DateTime(2026, 10, 15),
      themeMode: 'system', accent: 0xFF4C8DFF, todayTodoCount: 0);
  expect(snap['weekdays'], ['一', '二', '三', '四', '五', '六', '日']);
  // 周条那一列读的是 days[].weekday，**不能**跟着变成单字
  final days = snap['days']! as List;
  expect((days.first as Map)['weekday'], startsWith('周'));
  expect(snap['otherCrews'], '其他班组');
});
```

（`chain` 用该文件里既有的夹具构造，与相邻用例保持一致。）

- [ ] **Step 2: 跑，确认红**

Run: `flutter test test/widget_snapshot_test.dart -p vm`
Expected: FAIL —— `weekdays` 现在是 `['周一', ...]`，且 `otherCrews` 为 null。

- [ ] **Step 3: 改快照**

`widget_snapshot.dart`：

```dart
// 改前
'weekdays': List.generate(7, L10n.weekday),
// 改后 —— 与 App 日历页那一行**同一份文案**。`L10n.weekdays` 的注释写着它和
// `weekday(i)` 是两套、不能混用：前者是「网格列头」的一格一字，后者是
// 「周几」这个完整的词（周条那一列要的是后者，走 `days[].weekday`）。
'weekdays': L10n.weekdays,
```

顶层 map 里，`'emptyHint'` 那一行后面补：

```dart
'otherCrews': L10n.otherCrews,
```

- [ ] **Step 4: 跑，确认绿**

Run: `flutter test test/widget_snapshot_test.dart -p vm`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/widget/widget_snapshot.dart app/test/widget_snapshot_test.dart
git commit -m "feat(widget): 月历周标题改单字，快照补「其他班组」标签"
```

---

### Task 3: 抽出 `alarmNote` / `monthTallyFor`，快照补两个字段

**Files:**
- Create: `app/lib/domain/day_summary.dart`
- Modify: `app/lib/features/calendar/calendar_screen.dart`（删掉 `_alarmText` / `_shiftHasAlarms` / `_computeMonthTally` 三处私有实现，改成调用新文件；`_computeMonthTally` 的调用点改成 `monthTallyFor(chain, _month)`）
- Modify: `app/lib/features/widget/widget_snapshot.dart`（`days[]` 加 `shiftNote`；`months[]` 每条加 `tally`）
- Test: `app/test/day_summary_test.dart`（新建）、`app/test/widget_snapshot_test.dart`

**Interfaces:**
- Consumes: `L10n.restNoAlarm` / `L10n.alarmOff` / `L10n.alarmAt` / `L10n.alarmAtEtc`（以 `calendar_screen.dart:2968` 现用的为准）、`alarmDayAnchor`（`domain/shift_rotation.dart`）、`L10n.monthTally`
- Produces:
  - `bool shiftHasAlarms(ShiftClass t)`
  - `String alarmNote(ShiftClass t)` —— 休班「休息日 · 不响闹钟」/ 无闹钟「未开启」/ 有闹钟「闹钟 07:00」或「闹钟 07:00 等 2 个」，含「前一天 / 次日」标记
  - `String? monthTallyFor(ScheduleChain? chain, DateTime month)` —— 该月按 `shortLabel` 累加；`chain == null` 或整月没有班次时返回 `null`

- [ ] **Step 1: 写失败用例**

新建 `app/test/day_summary_test.dart`：

```dart
test('alarmNote：休班 / 未开启 / 有闹钟三种', () { /* 三个 ShiftClass 夹具各断言一次 */ });
test('alarmNote：不落在班次当天的钟点带「前一天 / 次日」标记',
    () { /* 00:00 上班 + 23:00 响铃 → 含「前一天」 */ });
test('monthTallyFor：按简称累加，空白表返回 null', () {
  // 跨方案的一个月里两套班次定义不同 —— 按下标数会算错（v0.9.12 修过）
  expect(monthTallyFor(blankChain, DateTime(2026, 10)), isNull);
  expect(monthTallyFor(chain, DateTime(2026, 10)), startsWith('本月 '));
});
```

在 `app/test/widget_snapshot_test.dart` 追加：

```dart
test('days[] 带 shiftNote；months[] 每条带 tally，同月各天查到同一个串', () {
  final snap = buildWidgetSnapshot(/* 同上 */);
  final days = (snap['days']! as List).cast<Map>();
  expect(days.first['shiftNote'], isNotNull);

  final months = (snap['months']! as List).cast<Map>();
  expect(months.first['tally'], startsWith('本月 '));
  // 同一月里的两天，按 day 反算年月之后必须查到**同一个**串 ——
  // tally 挂在 months[] 而不是逐日烘，就靠这条把它钉住。
  expect(months.where((m) => m['y'] == 2026 && m['m'] == 10), hasLength(1));
});

test('降级：没有班次的那天 shiftNote 为 null；窗口外的月份查不到 tally', () {
  // Review Focus 第 3、5 条
  final snap = buildWidgetSnapshot(/* blank 夹具：空白表方案 */);
  final days = (snap['days']! as List).cast<Map>();
  expect(days.first['shiftNote'], isNull);
  final months = (snap['months']! as List).cast<Map>();
  expect(months.every((m) => m['tally'] == null), true);
  // months[] 必须**恰好**是窗口覆盖到的那些月，不多不少 —— 多出来的月份
  // 会被宿主用「今天的年月」查到，显示成别的月份的统计。
  expect(months.map((m) => '${m['y']}-${m['m']}').toSet(),
      hasLength(months.length));
});
```

跨天/跨月的新鲜度由**既有**的 `app/test/widget_today_card_staleness_test.dart` 承重（Review Focus 第 4 条）—— 读一遍它，确认新增的三行也落在它守的那套降级规则里；若它只覆盖了 `todayCard`，就在里面补一条「`days[]` 侧的三行在跨天之后仍取得到」。**不要另起一个新文件**。
```

- [ ] **Step 2: 跑，确认红**

Run: `flutter test test/day_summary_test.dart test/widget_snapshot_test.dart -p vm`
Expected: FAIL —— `day_summary.dart` 不存在（编译不过）。

- [ ] **Step 3: 建 `app/lib/domain/day_summary.dart`**

把 `calendar_screen.dart:2963-2985` 那两段**原样搬过来**并去掉下划线：

```dart
/// 「这个班次挂没挂联动闹钟」—— 格子左上角那个点与 [alarmNote] **共用这一份判据**。
/// 两处各写一遍的话，哪天规则变了就会出现「格子上有点、信息卡却写着未开启」
/// 这种自相矛盾的画面，而它不会报错。
bool shiftHasAlarms(ShiftClass t) => t.alarmEnabled && t.alarms.isNotEmpty;

/// 班次那一行的备注。休班 / 未开启 / 「闹钟 HH:MM」（不落在班次当天的带
/// 「前一天 / 次日」标记 —— 不标会被读成班次当天）。
String alarmNote(ShiftClass t) { /* calendar_screen.dart 原实现，一字不改 */ }

/// 某个月按**简称累加**的天数串（「本月 大休13 · 白7 · 上夜6 · 下夜5」）。
///
/// **按简称累加、不按 `classes` 下标计数**：跨时段的一个月里两套方案的班次定义
/// 不同，按下标数会把 A 的第 0 个班次和 B 的第 0 个班次算成同一个（v0.9.12 修过）。
/// 没有排班、或整月都没有班次（空白表跟随法定节假日）时返回 null。
String? monthTallyFor(ScheduleChain? chain, DateTime month) { /* 同上 */ }
```

`calendar_screen.dart` 里三处私有实现删掉，改成 import 这个文件；`_alarmText(shift)` → `alarmNote(shift)`、`_shiftHasAlarms(s)` → `shiftHasAlarms(s)`、`_computeMonthTally(chain)` → `monthTallyFor(chain, _month)`。**只许改名字与出处，一个字符的逻辑都不许顺手改**。

- [ ] **Step 4: 快照挂上两个字段**

`widget_snapshot.dart`：

- `days.add({...})` 里补一行：`'shiftNote': shift == null ? null : alarmNote(shift),`
- `_monthsInWindow` 里每条补 `'tally': monthTallyFor(chain, DateTime(y, m)),` —— 该函数要多收一个 `chain` 参数，调用点一并改。

> **为什么 tally 挂 `months[]` 而不是逐日烘**：它是**按月**的量。挂 `months[]` 只有 7 条、快照不膨胀；而原生跨天之后拿 `days[todayIndex]` 反算出月份再查 `months[]`，零点与翻月都自动是对的。

- [ ] **Step 5: 跑，确认绿**

Run: `flutter test test/day_summary_test.dart test/widget_snapshot_test.dart test/calendar_screen_test.dart -p vm`
Expected: PASS（日历那侧行为不变 —— 这一步是纯搬运）。

- [ ] **Step 6: 跑全套**

Run: `flutter test`
Expected: 全绿。

- [ ] **Step 7: 提交**

```bash
git add app/lib/domain/day_summary.dart app/lib/features/calendar/calendar_screen.dart \
        app/lib/features/widget/widget_snapshot.dart app/test/day_summary_test.dart \
        app/test/widget_snapshot_test.dart
git commit -m "refactor: 抽出 alarmNote / monthTallyFor，快照补 shiftNote 与按月的 tally"
```

---

### Task 4: 今日卡补齐 App 信息卡有的三行

**Files:**
- Modify: `app/android/app/src/main/res/layout/widget_today_card.xml`（补两个 TextView、一个标签）
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`（`renderTodayCard`，约 789 行）
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetStore.kt`（`Snapshot` 若用显式字段承载，则加 `shiftNote` / `otherCrews` / `months[].tally`）
- Test: `app/test/widget_today_card_guard_test.dart`（新建，扫源码）

**Interfaces:**
- Consumes: Task 3 的 `days[].shiftNote`、`months[].tally`、顶层 `otherCrews`
- Produces: 三个新视图 id —— `wg_tc_crew_label`（「其他班组」标签）、`wg_tc_note`（班次备注）、`wg_tc_tally`（本月统计行）

- [ ] **Step 1: 写失败用例（扫源码）**

新建 `app/test/widget_today_card_guard_test.dart`，与 `widget_cell_block_guard_test.dart` 同一套路（`File(...).readAsStringSync()` + `contains`）：

```dart
test('今日卡布局有那三个新视图，且渲染侧两个方向都设满', () {
  final xml = _read('android/app/src/main/res/layout/widget_today_card.xml');
  for (final id in ['wg_tc_crew_label', 'wg_tc_note', 'wg_tc_tally']) {
    expect(xml.contains('@+id/$id'), true, reason: '$id 不在布局里');
  }
});
test('renderTodayCard 对那三个视图读的是快照字段，不是写死的文案', () {
  final kt = _read('android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
  expect(kt.contains('shiftNote'), true);
  expect(kt.contains('otherCrews'), true);
  expect(kt.contains('tally'), true);
});
test('Kotlin 里没有用户可见的中文字面量（本文件新增的那几行也不许有）', () {
  // 扫 WidgetRenderer.kt，断言 '其他班组' / '本月' / '休息日' 这些串一个都不出现
});
```

- [ ] **Step 2: 跑，确认红**

Run: `flutter test test/widget_today_card_guard_test.dart -p vm`
Expected: FAIL —— 三个 id 都还没有。

- [ ] **Step 3: 改布局**

`widget_today_card.xml`：

- 班组行（`wg_tc_crew_row`）前面补一个 `TextView` `@+id/wg_tc_crew_label`，`textSize="11dp"`，`layout_marginTop="16dp"`，**宽度写 56dp 固定**（与 App 的标签列同一列宽），`maxLines="1"`；
- 时间行下面补 `TextView` `@+id/wg_tc_note`（`textSize="13dp"`，`layout_marginStart="18dp"`，色走 `wg_muted_*`）；
- 末尾补 `TextView` `@+id/wg_tc_tally`（`textSize="12dp"`，`layout_marginTop="14dp"`，`maxLines="1"`，`ellipsize="end"`）。

（**`textSize` 一律写 `dp`** —— Task 5 会把全仓的 `sp` 都换掉，这里先按新家法写。）

- [ ] **Step 4: 改渲染侧**

`renderTodayCard` 里，按既有那种「**两个方向都设满**」的写法给三个视图设文案与可见性：拿到空串 / `null` 就 `GONE`（**不是**设成空字符串 —— 空字符串会让那一行留着高度）。三处取值：

- `wg_tc_crew_label` ← `snap.otherCrews`（恒定非空）
- `wg_tc_note` ← `days[todayIndex].shiftNote`（可能为 null）
- `wg_tc_tally` ← 按 `days[todayIndex].day` 反算年月，从 `snap.months` 里查 `tally`（查不到 → GONE）

把 `widget_today_card.xml` 头注里那组过时的数（266 / 232 / 34）改成本轮真机实测值，并写明测量方法与日期。

- [ ] **Step 5: 跑，确认绿**

Run: `flutter test test/widget_today_card_guard_test.dart -p vm`
Expected: PASS。

- [ ] **Step 6: 真机出图核**

```bash
. tools/build-env.ps1
flutter build apk --release --target-platform android-arm64
toolchain/android-sdk/platform-tools/adb.exe install -r app/build/app/outputs/flutter-apk/app-release.apk
```
打开一次 App（推快照），回桌面截今日卡，与 `work/adb-shots/compare_card.png` 的左边（App 信息卡）并排比。**三样都在、上下余量明显小于改造前**。

- [ ] **Step 7: 提交**

```bash
git add app/android/app/src/main/res/layout/widget_today_card.xml \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt \
        app/test/widget_today_card_guard_test.dart
git commit -m "feat(widget): 今日卡补「其他班组」标签、班次备注与本月统计行"
```

---

### Task 5: 桌面卡脱 `sp` + 按格子尺寸缩放

**Files:**
- Modify: 7 张布局的 `textSize` —— `widget_month_card.xml`(10) / `widget_today_card.xml`(7) / `widget_month_cell.xml`(3) / `widget_strip_cell.xml`(3) / `widget_crew_chip.xml`(1) / `widget_empty.xml`(1) / `widget_placeholder.xml`(1)
- Modify: `WidgetRenderer.kt`（新增 `cardScale` / `applyScale`，在 `monthCard` 与 `renderTodayCard` 里用）
- Test: `app/test/widget_font_scale_guard_test.dart`（新建，扫源码）

**Interfaces:**
- Consumes: `monthCellPx(context, widgetId, rows) -> Pair<Int, Int>`（已存在，`WidgetRenderer.kt:118`，返回格子的**像素**宽高）
- Produces:
  - `private fun cardScale(cellHpx: Int, density: Float): Float`
  - `private fun applyScale(v: RemoteViews, id: Int, baseDp: Float, s: Float)`
  - `private const val kTodayCardDesignH = <真机实测值>`（见 Step 5）

- [ ] **Step 1: 写失败用例（扫源码）**

新建 `app/test/widget_font_scale_guard_test.dart`：

```dart
test('会渲染真数据的小组件布局里一个 sp 都没有', () {
  const layouts = ['month_card', 'month_cell', 'today_card', 'today_standalone',
                   'strip_cell', 'week_strip', 'crew_chip', 'empty', 'placeholder'];
  expect(layouts, hasLength(9), reason: '自证：清单本身不许被改短');
  for (final n in layouts) {
    final s = _read('android/app/src/main/res/layout/widget_$n.xml');
    expect(RegExp(r'textSize="[0-9.]+sp"').hasMatch(s), false,
        reason: 'widget_$n.xml 里还有 sp —— 它会跟着系统字号长，'
                '而卡片的尺寸是编译期定死的，装不下就切内容');
  }
});

test('自证：preview 那三张豁免的东西确实不在上面那份清单里', () {
  const layouts = [/* 同上 */];
  for (final n in ['preview_month', 'preview_strip', 'preview_today']) {
    expect(layouts.contains(n), false, reason: 'preview 是静态缩略图，不渲染真数据');
  }
});

test('缩放机制在位，且基准数与 design_tokens 同源', () {
  final kt = _read('android/.../WidgetRenderer.kt');
  expect(kt.contains('cardScale'), true);
  expect(kt.contains('TypedValue.COMPLEX_UNIT_DIP'), true,
      reason: 'COMPLEX_UNIT_DIP 不乘 fontScale；用 SP 就等于没脱开系统字号');
});
```

- [ ] **Step 2: 跑，确认红**

Run: `flutter test test/widget_font_scale_guard_test.dart -p vm`
Expected: FAIL —— 26 处 `sp` 还在。

- [ ] **Step 3: 布局 `sp` → `dp`，并按 App 的基准值对齐**

把 7 张布局里所有 `textSize="Nsp"` 改成 `textSize="Ndp"`，**数值同时按 App 那一份基准订正**（`app/lib/core/design_tokens.dart`）：

| 视图 | 改前 | 改后（基准 dp） | 出处 |
|---|---|---|---|
| `wg_mc_day`（月历日数字） | 16sp | **13** | `cellDateSm` |
| `wg_mc_abbr`（月历胶囊字） | 11sp | **12** | `cellShift` |
| `wg_mc_lunar`（月历农历） | 11sp | **11** | `tinyLabel` |
| `wg_m_wd1..7`（周标题） | 11sp | **13** | `labelSecondary`，**不随 s 缩放**（App 也不缩） |

今日卡、周条、`crew_chip`、`empty`、`placeholder` 的数值**保持不变**，只换单位（它们的基准本来就是照 App 信息卡抄的）。

- [ ] **Step 4: 加缩放机制**

`WidgetRenderer.kt`：

```kotlin
/**
 * 桌面卡的缩放系数 —— 与 App 日历格**同一条规则**：
 * `app/lib/features/calendar/calendar_screen.dart:1893` 的
 * `s = (cellH - _cellInset*2) / _cellDesignH`，夹在 [0.85, 1.25]。
 *
 * 四个数逐字来自 `app/lib/core/design_tokens.dart`：
 * `cellDateSm` 13 / `cellShift` 12 / `tinyLabel` 11，`_cellDesignH` = 55、
 * `_cellInset` = `gapHair` = 2。**改那边三个令牌要回来改这里。**
 *
 * 下限 0.85（App 是 1.0）：App 的格子永远 ≥ 设计尺寸，而桌面的格高由启动器给，
 * 可能更矮 —— 那时宁可字小一档，也不要溢出（桌面外壳没有滚动）。
 */
private fun cardScale(cellHpx: Int, density: Float): Float =
    ((cellHpx / density - 4f) / 55f).coerceIn(0.85f, 1.25f)

/** `COMPLEX_UNIT_DIP` 不乘 fontScale —— 用 SP 就等于没跟系统字号脱开。 */
private fun applyScale(v: RemoteViews, id: Int, baseDp: Float, s: Float) {
    v.setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_DIP, baseDp * s)
}
```

在 `monthCard` 里：拿到 `monthCellPx(...)` 之后算一次 `s`，对 42 格的 `wg_mc_day` / `wg_mc_abbr` / `wg_mc_lunar` 各调一次 `applyScale`。

- [ ] **Step 5: 今日卡的那一档系数**

先**在真机上量出**补完三行之后今日卡的**自然内容高**（外壳 256dp 减去上下内边距后，内容占了多少），把那个数写进 `WidgetRenderer.kt`：

```kotlin
/**
 * 今日卡内容的**设计高度**（dp）—— 与 App 的 `_cellDesignH = 55` 同一种做法：
 * 它是「按基准字号自然排布时内容占多高」，真机量出来的，不是推的。
 * 测量：<日期> <设备> <方法>，量到 <N>dp。
 */
private const val kTodayCardDesignH = 0f  // ← 换成实测值
```

在 `renderTodayCard` 里用 `AppWidgetOptions` 的 `OPTION_APPWIDGET_MIN_HEIGHT` 减去上下内边距当作可用高，算 `s`，对今日卡的各个 `TextView` 逐个 `applyScale`。

- [ ] **Step 6: 跑，确认绿**

Run: `flutter test test/widget_font_scale_guard_test.dart -p vm && flutter test`
Expected: 全绿。

- [ ] **Step 7: 真机验「字号不动」**

```bash
ADB=toolchain/android-sdk/platform-tools/adb.exe
$ADB shell settings put system font_scale 2.0 && sleep 2 && $ADB exec-out screencap -p > work/adb-shots/w_fs200.png
$ADB shell settings put system font_scale 1.0 && sleep 2 && $ADB exec-out screencap -p > work/adb-shots/w_fs100.png
```
三张卡各截一遍，逐像素比 —— **内容区必须一致**（系统状态栏等区域允许不同）。

- [ ] **Step 8: 提交**

```bash
git add app/android/app/src/main/res/layout/ app/android/app/src/main/kotlin/ \
        app/test/widget_font_scale_guard_test.dart
git commit -m "fix(widget): 桌面卡字号脱离系统字号，改按格子尺寸缩放"
```

---

### Task 6: 月历那格的胶囊由文字撑开（去掉写死的 40dp 宽）

**Files:**
- Modify: `app/android/app/src/main/res/layout/widget_month_cell.xml`（胶囊那个 `FrameLayout`）
- Modify: `WidgetRenderer.kt`（`monthCard` 里烤胶囊位图那一段，约 710 行）
- Test: `app/test/widget_cell_block_guard_test.dart`（追加）

**Interfaces:**
- Consumes: Task 5 的 `s` 与 `applyScale`
- Produces: 胶囊盒子的尺寸 = 它里面那个 `TextView` 的尺寸（不再写死 40dp × 18dp）

- [ ] **Step 1: 写失败用例（扫源码）**

```dart
test('月历胶囊的盒子由文字撑开，不是写死的 40dp', () {
  final xml = _read('android/app/src/main/res/layout/widget_month_cell.xml');
  expect(xml.contains('40dp'), false,
      reason: '写死 40dp 时文字放大了盒子不动，而且 App 那格的胶囊本来就是内容宽');
  expect(xml.contains('layout_width="wrap_content"'), true);
});
```

- [ ] **Step 2: 跑，确认红**

Run: `flutter test test/widget_cell_block_guard_test.dart -p vm`
Expected: FAIL。

- [ ] **Step 3: 改布局**

`widget_month_cell.xml` 里那个包胶囊的 `FrameLayout`：`layout_width` / `layout_height` 改成 `wrap_content`；`wg_mc_abbr` 保持 `wrap_content` 并补左右内边距 `paddingHorizontal="6dp"`；`wg_mc_pill` 保持 `match_parent`（`FrameLayout` 量到的是 `TextView` 的尺寸，没有 src 的 `ImageView` 不参与定尺 —— **这就是绕开 API 31 的那个点，别把 `ImageView` 改成 `wrap_content`**）。

- [ ] **Step 4: 改渲染侧**

胶囊位图的宽高改成在**循环外**按 `s` 算一次（`dpToPx` 换成 `baseDp * s * density` 的算式），42 格共用同一对尺寸 —— **别按格子造唯一尺寸**，那会把 `WidgetChip` 的 LruCache 冲爆。

- [ ] **Step 5: 跑 + 真机看**

Run: `flutter test test/widget_cell_block_guard_test.dart test/widget_fixed_cards_guard_test.dart -p vm`
然后装到真机、回桌面截月历卡，确认：胶囊宽度参差（「白」窄、「大休」宽）、没有一格溢出、农历那行没被挤掉。

- [ ] **Step 6: 提交**

```bash
git add app/android/app/src/main/res/layout/widget_month_cell.xml \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt \
        app/test/widget_cell_block_guard_test.dart
git commit -m "feat(widget): 月历胶囊由文字撑开，尺寸随格子缩放"
```

---

### Task 7: 月历「今天」改成与 App 同款的半透明块

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetChip.kt`（**新开一支**，不要改 `block`）
- Modify: `WidgetRenderer.kt`（`monthCard` 里 `isToday` 那三处，约 656-750 行）
- Test: `app/test/widget_cell_block_guard_test.dart`（改两条、加两条）

**Interfaces:**
- Consumes: 既有的 `WidgetChip.block(color, w, h, radiusPx, borderColor, borderPx)` 与 `tintedChip(color, w, h)`（**都不许改行为**）
- Produces: `WidgetChip.glassBlock(accent: Int, w: Int, h: Int, radiusPx: Float): Bitmap` —— 主色 22%→10% 对角渐变 + 2dp 实心主色描边

- [ ] **Step 1: 改/加用例**

`widget_cell_block_guard_test.dart` 里那条「今天那格的字都走 `onSolidInk`」**反向改掉**：

```dart
test('今天那格的字一律走中性色，不走 onSolidInk', () {
  final kt = _read('.../WidgetRenderer.kt');
  final monthCell = /* 截出 monthCard 那一段 */;
  expect(monthCell.contains('onSolidInk'), false,
      reason: '半透明块是浅底；onSolidInk 在 teal/orange 上给白字，白压浅底读不出来'
              '（默认那颗蓝是对的，所以这是静默的）');
});
test('glassBlock 是三处共用之外的第四支，block/tintedChip 的行为没被改', () {
  final kt = _read('.../WidgetChip.kt');
  expect(kt.contains('fun glassBlock'), true);
});
test('块的层级仍排在内容之前', () { /* 保留既有的那条，断言不变 */ });
```

- [ ] **Step 2: 跑，确认红**

Run: `flutter test test/widget_cell_block_guard_test.dart -p vm`
Expected: 前两条 FAIL。

- [ ] **Step 3: 加 `WidgetChip.glassBlock`**

```kotlin
/**
 * **半透明玻璃块** —— 只给月历那格「今天」用（周条那一列与今日卡的「今天」药丸
 * 仍走 [block] 的实心版：药丸是白字压主色，半透明会读不出来）。
 *
 * 配方照 App 液态档那枚选择块：主色 22% → 10% 的对角渐变 + 2dp 实心主色描边。
 * App 那枚块**自己不带模糊**（模糊在页面背景那一层），所以这不是打折，是同款。
 */
fun glassBlock(accent: Int, w: Int, h: Int, radiusPx: Float): Bitmap
```

实现要点：`LinearGradient` 从左上到右下（与 App 的 315° 同向），`shader` 的两种颜色是 `accent` 分别带 `alpha = 56`（22%）与 `alpha = 26`（10%）；描边用**实心** `accent`，`strokeWidth = 2dp * density`，向内 `inset` 半个描边宽。

- [ ] **Step 4: 改 `monthCard` 的三处**

- `setBackgroundResource` 那段的 `isToday -> 0` 去掉 —— 半透明块需要底下那张**白卡**（`widget_cell_*`）；
- 今天那格的块换成 `WidgetChip.glassBlock(snap.accent, cellW, cellH, dpToPx(context, 12).toFloat())`；
- 日数字：`isToday -> onSolidInk(...)` 改成走 `ink`（相邻月仍 `muted`）；
- 农历：`isToday -> onSolidInk(...)` 删掉，回到 `d.lunarIsHoliday -> holiday / else muted` —— **顺带把「今天且是法定节假日」的红字还回来**；
- 胶囊：`if (isToday) WidgetChip.block(...) else WidgetChip.tintedChip(...)` 整个分支去掉，恒走 `tintedChip`；`wg_mc_abbr` 的字色恒走 `ink`。

- [ ] **Step 5: 跑，确认绿**

Run: `flutter test test/widget_cell_block_guard_test.dart test/widget_on_solid_test.dart -p vm`
Expected: PASS（`widget_on_solid_test` 若原来把月历今天那格算进去，按新行为更新并写明理由）。

- [ ] **Step 6: 真机浅深两档 + 换浅主色**

装到真机，月历卡截图 × 2（浅色 / 深色）；再把主色换成 **teal**，确认那格的日数字与农历仍读得清（**这是 Review Focus 第 2 条，必须真看**）。

- [ ] **Step 7: 提交**

```bash
git add app/android/app/src/main/kotlin/ app/test/widget_cell_block_guard_test.dart
git commit -m "feat(widget): 月历「今天」改成与 App 同款的半透明玻璃块"
```

---

### Task 8: 收尾 —— 并排验收、版本号、更新日志、文档

**Files:**
- Modify: `app/pubspec.yaml` 与 `app/lib/core/app_info.dart`（版本号，**同步**）
- Modify: `app/lib/features/profile/app_dialogs.dart`（`_changelogZh` / `_changelogEn`，prepend 新条目、删最旧、保持 10 条；测试版条目**原样只写这一版**）
- Modify: `AGENTS.md`（版本史 + 「最近改动」；**并把 2026-10-11 那条「桌面「今天」是有意的实心偏离，别再改回半透明」改写成「v0.11.23 起已推翻，理由见 spec §5」**）
- Test: `app/test/changelog_window_test.dart` 既有护栏

**Interfaces:**
- Consumes: 前面七个任务的成果
- Produces: 可发布的版本

- [ ] **Step 1: 并排出图**

`work/adb-shots/` 下重新生成三张并排图（月历 vs App 日历页、今日卡 vs App 信息卡、底栏光晕特写），与改造前的 `compare_month.png` / `compare_card.png` / `navglow_zoom.png` 对照，**逐条回答 spec §7 的五条验收**。

- [ ] **Step 2: 光谱接缝的数值验收**

滑着截一帧，按 spec §7.3 沿轮廓采一圈色相（采样点跨过正右方），断言**任意相邻 5° 的色相差 ≤ 20°**（改造前那一步是 62°）。

- [ ] **Step 3: 版本号**

`app/pubspec.yaml` 的 `version:` 与 `app/lib/core/app_info.dart` 的 `appVersion` **同步**改成 `0.11.23+170`（`Z` 与 `build` 由本计划定；`X.Y` 不动）。

- [ ] **Step 4: 更新日志**

`app_dialogs.dart` 的 `_changelogZh` / `_changelogEn` **各 prepend 一条、各删最旧一条、保持 10 条**；测试版条目**只写自己这一版改了什么**（不做归纳 —— 归纳留给下一个正式版）。

- [ ] **Step 5: 跑全部验收**

```bash
flutter analyze
flutter test
flutter test tool/visual/
```
Expected: 0 error / 0 warning；全绿；工装逐张比基线，差异逐条解释（响铃页时钟跳字那几张是已知假象）。

- [ ] **Step 6: 提交 + 打 tag + 发布**

```bash
git add -A
git commit -m "chore(release): v0.11.23"
git tag v0.11.23 && git push origin beta && git push origin v0.11.23
```
再跑 `scripts\release.ps1 -SkipConfirm`（**必须在主 checkout 里构建**，worktree 没有 `key.properties` 会静默回退 debug 签名），最后 curl 一次 main 上的 `latest.json` 核对。
