# 动画与流畅性 · 第二轮（玻璃模糊的代价）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把每一帧的光栅线程开销降到 8.33ms 预算之内 —— 做法是把 `BackdropFilter`
收窄到「背后真有东西会动」的地方，并收掉上一轮明确留下的六项。

**Architecture:** 全 app 仍然开着模糊的调用点只有 8 处，**全部是 `GlassTile`**。
所以不加 8 处开关，而是把 `GlassPanel` 上「糊不糊」与「用哪支填充」这两件被捆在一起的事拆开，
让 `GlassTile` 只画填充/描边/阴影。其余（导航胶囊、液态透镜、按钮、提示条、弹窗）一个都不动。

**Tech Stack:** Flutter 3.47.2（Impeller）· Dart · Kotlin（Android 侧，**没有测试目标**）· Riverpod · drift

**Spec:** `docs/superpowers/specs/2026-10-10-smoothness-second-pass-design.md`

## Global Constraints

- **不改任何动画的时长、曲线、弹簧参数。**
- **填充配方（`AppTokens.glassSurface` / `glassTint`）一个字节不改** —— `GlassTile` 改完之后
  它用的仍是 `translucentFill: true` 那一支。用错了（换成更实的那支）就是肉眼可见的观感变化。
- **收窄范围只到 `GlassTile`。** `GlassBlur`（按钮 / 提示条 / 液态轨道 / 导航胶囊）与
  `liquid_lens` / `liquid_track` 一律不动。
- **`GlassPanel` 外面那圈 `ClipRRect` 留着**（它同时裁掉了 `boxShadow`，见 spec §3.2）——
  这一轮只补注释，不补阴影。
- 版本号：**AI 只能改 `Z` 与 `build`**，`X.Y` 是用户的。本轮 `0.10.21+145` → `0.10.22+146`。
- 更新日志窗口恒 **10 条**、**纯文本**（不许出现 `**` / 反引号 / 行首 `#` / markdown 链接）。
- **不要跑 `dart format`**（工具链是新版 tall style，一跑就是几百行无关 diff）。
- 探针（`app/tool/probe/`、`glass.dart` 里的三个 `probe*` 全局、`build.gradle.kts` 里的
  `maybeCreate("profile")`）**跑完即删 / 收尾前还原**，不进仓库、不进测试。
- 验收：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿（当前 **807** 条，只增不减）；
  `flutter test tool/visual/` 全绿（349 条）。
- **原生侧（Kotlin）没有测试目标** —— 那三项的验收只能靠真机 + 日志，与仓库既有约定一致。
- 构建环境：每次 pwsh/bash 先 `source work/perf/env.sh`（等价于 dot-source `tools/build-env.ps1`）。

## Review Focus

这一轮最可能出事、而**没有任何一条用例**会自动照出来的五个输入面（实施时逐条手动确认，
并在最终汇报里逐条给出结论）：

1. **卡片从悬浮控件底下滚过去的时候** —— 编辑排班页底部那颗「保存并重排闹钟」胶囊、
   闹钟页底部那条按钮条：内容是从**玻璃底下**穿过去的。要确认「卡片不糊」没有把
   那些地方一起改坏（`GlassBlur` 那一路保留着）。
2. **「我的」页那五个开关各自还跟不跟** —— 主题档 / 主色 / 语言 / 液态玻璃 / 触觉。
   `appSettingsProvider` 收窄之后，**每一个开关拨下去都必须立刻反映在它自己身上**
   （尤其：触觉与液态玻璃这两项不参与主题，最容易被漏掉）。
3. **语言切换** —— 切中/英之后，四个 tab 页与顶栏的文案**必须还跟着变**。
   select 收窄最容易在这里漏一个消费者，而它不会报错、只会「切了语言界面不动」。
4. **响铃的自动停止** —— 自停那一刻**必须走与用户手动关闭完全相同的那条拆除路径**
   （`exitLockScreenMode()` 不撤 = 把 v0.8.0 修过的「锁屏下能操作 App」重新打开）；
   以及「再睡一会」之后重新计时。
5. **小组件改非精确 + 跨天** —— 凌晨翻页会晚几分钟（已判定可接受），
   以及 `AlarmStore` 批量写之后**进程被杀**会不会丢掉已排的闹钟记录。

---

### Task 1: 把「糊不糊」与「用哪支填充」拆开，`GlassTile` 不再挂 `BackdropFilter`

**Files:**
- Modify: `app/lib/core/glass/glass.dart`
- Create: `app/test/glass_tile_backdrop_test.dart`

**Interfaces:**
- Consumes: 无（本轮第一个任务）
- Produces:
  - `GlassPanel({required double blurSigma, bool translucentFill = true, bool blurBackdrop = true, ...})`
    —— `enableBlur` 更名成 `translucentFill`（**极性不变**：`enableBlur: true` ⇒ `translucentFill: true`），
    并新增 `blurBackdrop`
  - `GlassTile({bool translucentFill = true, ...})` —— 内部固定传 `blurBackdrop: false`
  - `GlassBlur` 不变
  - 一个 `@visibleForTesting` 的计数器不算接口，不需要

- [ ] **Step 1: 写会失败的用例**

`app/test/glass_tile_backdrop_test.dart`：

```dart
// 卡片背后是平色，糊了等于没糊 —— 却要付一次 backdrop 渲染通道的钱。
// 实测：编辑排班页 raster p90 13.10ms → 2.37ms、掉拍帧 13.4% → 2%。
// 这一条防的就是「有人哪天顺手把它加回来」。
testWidgets('GlassTile 不挂 BackdropFilter', (tester) async {
  await tester.pumpWidget(_host(const GlassTile(child: Text('x'))));
  expect(find.byType(BackdropFilter), findsNothing);
});

// 反向的那一头：既然不糊，填充就**必须**还是原来那一支（translucentFill: true）。
// 换成更实的那支是肉眼可见的观感变化 —— 那正是「低端档」的补偿配方。
testWidgets('GlassTile 的填充仍是 translucentFill 那一支', (tester) async {
  await tester.pumpWidget(_host(const GlassTile(child: Text('x'))));
  final deco = _panelDecoration(tester);
  expect((deco.gradient! as LinearGradient).colors,
      AppTokens.glassSurface(isDark: true, blurOn: true));
});

// 反向验证的另一半：GlassPanel 自己**默认还是要糊**（弹层 / 悬浮栏要用）
testWidgets('GlassPanel 默认仍然挂 BackdropFilter', (tester) async {
  await tester.pumpWidget(_host(const GlassPanel(child: Text('x'))));
  expect(find.byType(BackdropFilter), findsOneWidget);
});
```

（`_host` 只包一层 `MaterialApp` + 深色 `Theme`；`_panelDecoration` 取 `GlassTile`
里那个带 `BoxDecoration` 的 `Container` 的 `decoration`。）

- [ ] **Step 2: 跑，看它红**

Run: `flutter test test/glass_tile_backdrop_test.dart`
Expected: 第一条 FAIL（`find.byType(BackdropFilter)` 找到 1 个）；
第三条 PASS（它本来就是绿的，是**对照**，不是新增行为）。

- [ ] **Step 3: 改 `glass.dart`**

1. `GlassPanel` 的 `enableBlur` 字段与构造参数**整体更名为 `translucentFill`**（极性不变）。
   文档改成：「用哪支填充 —— `true` = 半透那支（配模糊用），`false` = 更实的那支
   （低端档 / 密集列表用）。**它与『挂不挂 backdrop 通道』是两件事**，见 `blurBackdrop`。」
2. 新增 `final bool blurBackdrop;`（默认 `true`）与构造参数。文档写明：
   「要不要真的挂 `BackdropFilter`。`false` = 只画填充/描边/阴影 —— 背后是平色时
   糊了等于没糊，却要付一次 backdrop 渲染通道的钱（真机实测单次数 ms）。」
3. `blurOn` 那一支改成只看 `blurBackdrop`：
   `if (blurBackdrop && !solid) { panel = ClipRRect(borderRadius: …, child: BackdropFilter(filter: glassFilter(blurSigma), child: panel)); }`
   —— 注意 `ClipRRect` **始终留着**（Global Constraints）。
   **同时把 `probeSkipBackdrop` / `probeFilterMode` 这两个临时全局删掉**
   （它们只在 Task 1 之前的量测里用过），并把 `app/tool/probe/perf_main.dart`
   里对它们的引用一并去掉 —— 探针只留 `onReportTimings` 那一件事。
4. `GlassTile`：参数 `enableBlur` 同步更名为 `translucentFill`，
   内部 `GlassPanel(translucentFill: translucentFill, blurBackdrop: false, ...)`，
   并在类文档里写清**为什么**（卡片背后是平色）。
5. 全仓把 `enableBlur:` 的 16 个调用点改成 `translucentFill:`（**值不变**）。
   Run: `grep -rn "enableBlur" app/lib/` → 只许剩下 `glass.dart` 里那两处文档提到它的地方。
6. 顺手把 spec §3.2 那处注释写进 `GlassPanel`：`ClipRRect` 同时裁掉了 `boxShadow`，
   全 app 因此有两套卡片观感（带模糊的没阴影）；补阴影是**肉眼可见**的改动，要单独拍板。

- [ ] **Step 4: 跑，看它绿**

Run: `flutter test test/glass_tile_backdrop_test.dart && flutter test test/design_tokens_test.dart`
Expected: 全 PASS。

- [ ] **Step 5: 钉住「一屏几层 BackdropFilter」**

在**既有夹具**下数（不要新建屏）：
- `app/test/schedule_editor_test.dart` —— 在它已有的「打开编辑排班页」用例里加一条：
  `expect(find.byType(BackdropFilter), findsAtMost(N_editor))`；
- `app/test/calendar_screen_test.dart` —— 同样加一条 `findsAtMost(N_calendar)`。

`N_editor` / `N_calendar` **实施时先量出当前值再钉**（把量出来的数写进断言旁边的注释）。
**必须反向验证**：把 `GlassTile` 的 `blurBackdrop: false` 改回 `true`，这两条要立刻红。

- [ ] **Step 6: 提交**

```bash
git add app/lib/core/glass/glass.dart app/test/glass_tile_backdrop_test.dart \
        app/test/schedule_editor_test.dart app/test/calendar_screen_test.dart
git commit -m "perf(glass): GlassTile 不再挂 BackdropFilter（与填充配方拆开）"
```

---

### Task 2: 视觉基线逐张比（这一轮的差异是**预期**的，但必须逐张写理由）

**Files:**
- Modify: 无（产出是账本与结论）
- 产出：`work/perf/visual-baseline.md`（临时账本，收尾前随探针一起删）

**Interfaces:**
- Consumes: Task 1 改完的 `glass.dart`
- Produces: 一份逐屏结论，Task 12 的最终汇报要用

- [ ] **Step 1: 取基线**

工装把图渲进 `app/build/visual/`（`visual_harness.dart` 的 `kVisualOutDir`），
那 349 条**刻意没有 golden** —— `scripts/diff_visual.py` 的头部就写着流程：
**改之前先渲一遍存起来 → 改 → 再渲一遍 → 跑脚本比**。

基线要在**改之前**的提交上渲。当前工作区已经改过了，所以开一个临时 worktree：

```bash
git worktree add ../sa-baseline 9230c74        # 规格定稿那个提交
cd ../sa-baseline/app && source ../../shiftassistant/work/perf/env.sh
flutter test tool/visual/
cp -r build/visual /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app/build/visual/baseline-second-pass
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant && git worktree remove ../sa-baseline
```

Run: 上面五条
Expected: `app/build/visual/baseline-second-pass/` 里是基线的那批 PNG。

- [ ] **Step 2: 出当前图逐张比**

Run:
```bash
cd app && flutter test tool/visual/
python ../scripts/diff_visual.py build/visual/baseline-second-pass build/visual
```
Expected: 列出差异屏与差异量。（**差异不是失败**，是待解释项 —— 脚本自己就这么写的。）

- [ ] **Step 3: 逐张判**

判据（spec §4.2），**三条同时满足才算通过**：

1. 幅度 **≤ 32/255**；
2. 差异像素 **< 1%**；
3. 差异**只出现在玻璃卡片的描边/圆角上**（1px 级抗锯齿），不在色块 / 文字主体 / 胶囊填充上。

再剔除已知假差异（响铃页时钟跳字、跨天「今天」位移）。**每一张有差异的屏都要写一句理由**，
写不出理由 = 回归，停在那里解决，**不许放宽阈值糊过去**。

- [ ] **Step 4: 记账并提交**

`work/perf/visual-baseline.md` 写：基线提交、差异屏清单、每张的理由、以及「有没有超出三条判据的」。
**这一步不产生仓库提交**（账本是临时文件）。

---

### Task 3: 真机复测（spec §4.1 的硬指标）与有界归因

**Files:**
- Modify: 无（产出是账本）
- 产出：`work/perf/device-after.md`

**Interfaces:**
- Consumes: Task 1 的 `glass.dart`
- Produces: §4.1 的六个数字 + 归因结论

- [ ] **Step 1: 复核测量前提**

Run:
```bash
adb shell settings get system peak_refresh_rate   # 必须是 120
adb shell dumpsys package com.daoban.shiftassistantpro | grep versionName
```
Expected: `120`；版本仍是 `0.10.21`（还没改版本号是对的）。

- [ ] **Step 2: 构包（带探针，不动 `lib/`）**

Run:
```bash
source work/perf/env.sh
cd app && flutter build apk --profile --target-platform android-arm64 -t tool/probe/perf_main.dart
cp build/app/outputs/flutter-apk/app-profile.apk ../work/perf/apk-after.apk
```
Expected: 构建成功。**探针那三个 `probe*` 全局在 Task 1 里应该已经删掉了** ——
如果 `probe_main.dart` 因此编译不过，就把探针里对它们的引用一并去掉（探针本来就只留
`onReportTimings` 那一件事）。

- [ ] **Step 3: 量**

Run: `bash work/perf/measure.sh apk-after.apk after`（脚本在 `work/perf/`，收尾前删）

- [ ] **Step 4: 对照硬指标**

| 指标 | 今天（改前） | 目标 | 实测 |
|---|---|---|---|
| raster p50 | 4.19ms | ≤ 2.5ms | ? |
| raster p90 | 13.10ms | ≤ 4ms | ? |
| 掉拍帧 | 13.4% | ≤ 2% | ? |
| build p50 | 0.52ms | 不变 | ? |

- [ ] **Step 5: 四个 tab + 切 tab 再跑一遍**

Run: `bash work/perf/sweep.sh`；把仍在 8.33ms 之外的帧挑出来。

- [ ] **Step 6: 达标就记账；没达标做有界归因**

**达标**：把六个数字写进 `work/perf/device-after.md`，下一步。

**没达标**：做一次（且只做一次）归因 —— 把剩下的帧按「哪一页 / 哪一类 / 什么时候」
分堆，写清楚还差的是什么。然后：
- 指向**改法明确、代价可控**的东西 → 就地做掉，重跑 Step 4；
- 指向**要动观感 / 要单独一轮**的东西 → 写进账本与 Task 12 的最终汇报，
  **并且不许在本轮宣称流畅性已解决**。

归因如果要做 A/B（比如"把某一层拿掉再量一遍"），**可以在 `glass.dart` 里临时加回一个
`probe*` 全局** —— 但 Task 11 Step 1 那条「`probe*` 一个都不许剩」照旧适用，
**用完必须删干净**。

---

### Task 4: `appSettingsProvider` 收窄成 `select`

**Files:**
- Modify: `app/lib/app.dart`、`app/lib/features/calendar/calendar_screen.dart`、
  `app/lib/features/alarm/alarm_screen.dart`、`app/lib/features/schedule/schedule_screen.dart`、
  `app/lib/features/home/home_shell.dart`、`app/lib/features/profile/profile_screen.dart`
- Create: `app/test/settings_select_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: 无新接口（纯消费者侧改动）

- [ ] **Step 1: 写会失败的用例**

```dart
// 拨触觉开关不该重建整页 —— 它不参与主题、不参与语言、什么都不影响渲染。
testWidgets('拨触觉开关不重建日历页', (tester) async {
  // 照仓库既有写法用 debugOnRebuildDirtyWidget 数重建次数，
  // 且**调试变量的还原写在用例体里**（框架自检跑在 addTearDown 之前 ——
  // 工装 tearDownVisual 的注释里记过这条）
  // ...挂上监听、拨开关、断言日历页的根 widget 重建次数 == 0
});

// 反向那一头：语言切换**必须**还重建四个 tab 页。
testWidgets('切语言仍然重建四个 tab 页', (tester) async {
  // 逐个切过去、切语言、断言每个页面都重建了
});
```

- [ ] **Step 2: 跑，看它红**

Run: `flutter test test/settings_select_test.dart`
Expected: 第一条 FAIL（现在拨触觉会重建整页）。

- [ ] **Step 3: 改**

| 文件 | 改成 |
|---|---|
| `app.dart` | `.select((s) => (s.themeMode, s.accentIndex, s.language))` 之类的等值选择（用 record 或逐个 select） |
| `calendar_screen` / `alarm_screen` / `schedule_screen` / `home_shell` | 只 `.select((s) => s.language)` |
| **`profile_screen`** | 它把五个开关都画在自己身上 —— `.select` 出**它真正渲染的那五项**。⚠️ **不许收成 `language`**，那会把开关冻住 |

- [ ] **Step 4: 跑，看它绿**

Run: `flutter test test/settings_select_test.dart && flutter test`
Expected: 全绿。

- [ ] **Step 5: 手动过 Review Focus 第 2、3 条**

「我的」页五个开关逐个拨一遍（**尤其触觉与液态玻璃**）；中↔英各切一次，
四个 tab 页与顶栏文案都要跟着变。结论写进最终汇报。

- [ ] **Step 6: 提交**

```bash
git add app/lib/app.dart app/lib/features app/test/settings_select_test.dart
git commit -m "perf(settings): appSettingsProvider 收窄成 select"
```

---

### Task 5: `L10n` 的 `DateFormat` 缓存

**Files:**
- Modify: `app/lib/core/l10n.dart`
- Create: `app/test/l10n_dateformat_cache_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `L10n.debugDateFormatCacheSize()` 与 `L10n.debugDateFormatCacheClear()`
  （两个都是 `@visibleForTesting`，与既有的 `lunarCacheEntryCount()` / `lunarCacheClear()` 同形）

- [ ] **Step 1: 写会失败的用例**

```dart
test('同一个 pattern + locale 复用同一个 DateFormat', () {
  L10n.locale = 'zh';
  L10n.debugDateFormatCacheClear();
  L10n.yearMonth(DateTime(2026, 10, 1));
  L10n.yearMonth(DateTime(2026, 11, 1));
  expect(L10n.debugDateFormatCacheSize(), 1);   // 两次调用只造一个 DateFormat
});

test('换了 locale 就是另一个实例', () { ... 期望 2 ... });
```

- [ ] **Step 2: 跑，看它红**

Run: `flutter test test/l10n_dateformat_cache_test.dart`
Expected: FAIL —— `debugDateFormatCacheSize` 还不存在（编译错也算红，但**要确认它是因为这个**）。

- [ ] **Step 3: 改**

`l10n.dart` 里六处 `DateFormat('…', 'zh'|'en')` 收进一个 `_dateFormat(String pattern, String loc)`
（模块级 `Map<String, DateFormat>`，键 = `'$loc|$pattern'`，无上界 —— 模式是常量、最多十几条）。

- [ ] **Step 4: 跑，看它绿**

Run: `flutter test test/l10n_dateformat_cache_test.dart && flutter test test/changelog_window_test.dart`
Expected: 全 PASS。**日期格式的文案一个字符都不许变** —— 既有用例里有日期串的断言。

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/l10n.dart app/test/l10n_dateformat_cache_test.dart
git commit -m "perf(l10n): DateFormat 按 (pattern, locale) 缓存"
```

---

### Task 6: 光晕暂停判据 —— 「在动」而不是「手指按着」，并带上换月

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Modify: `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: `FlowingBackground.pauseWhen`（v0.10.20 已有）
- Produces: `_interacting` 的语义变化（从「手指按着」变成「四种交互正在进行」）

- [ ] **Step 1: 写会失败的用例**

```dart
// 「在动」= 飞行 ticker 在跑 / 拖动有新位移 / 带子弹簧未静止 / 换月动画在跑。
// 手指按着不动**不算** —— 那正是 v0.10.21 之后用户能看出光晕「卡住」的那一种。
testWidgets('按住不动时光晕继续走', (tester) async { ... expect(_interacting, isFalse) ... });

testWidgets('拖动中光晕停', (tester) async { ... });

testWidgets('换月时光晕停', (tester) async {
  // 点 ‹ 之后、AnimatedSwitcher 还在跑的这几帧里，暂停必须是 true
});
```

- [ ] **Step 2: 跑，看它红**

Run: `flutter test test/calendar_screen_test.dart`
Expected: 第一条 FAIL（现在按住就停）。

- [ ] **Step 3: 改**

把 `_interacting` 的写入点从「手势开始/结束」改成**四个动效源各自的起停**：
飞行 ticker 起停、拖动中是否收到新位移、带子的弹簧是否静止、换月的
`AnimatedSwitcher` 是否还在跑。**只要有一个在跑就是 true。**

- [ ] **Step 4: 跑，看它绿**

Run: `flutter test test/calendar_screen_test.dart && flutter test`
Expected: 全绿。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_screen_test.dart
git commit -m "perf(glow): 暂停判据改成「在动」，并带上换月"
```

---

### Task 7: `WidgetService.push` 加 in-flight 守卫

**Files:**
- Modify: `app/lib/features/widget/widget_service.dart`
- Modify: `app/test/widget_push_dedup_test.dart`

**Interfaces:**
- Consumes: v0.10.21 的 `_lastPushedKey` / `resetPushCache()`
- Produces: 无新公开接口

- [ ] **Step 1: 写会失败的用例**

```dart
test('上一次推送还没回来时，第二次触发不发车', () async {
  // 假通道：第一次 push 的 Future 挂着不返回（用 Completer 控住）
  // 期间再触发一次 push → 只许发出一次 widgetPushSnapshot
  // 第一次返回之后 → 下一次触发要能正常发出（守卫不能把闸门永久关死）
});
```

- [ ] **Step 2: 跑，看它红**

Run: `flutter test test/widget_push_dedup_test.dart`
Expected: FAIL（现在会发两次）。

- [ ] **Step 3: 改**

`WidgetService.push` 里加一个 `bool _inFlight`：进入时若已 true 就直接 return；
用 `try/finally` 保证异常路径也把它放下（**否则一次失败就把闸门永久关死**，
那比现在更糟）。

- [ ] **Step 4: 跑，看它绿**

Run: `flutter test test/widget_push_dedup_test.dart`
Expected: 全 PASS，且既有的「同一份只发一次」「失败要重试」两条仍然绿。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/widget/widget_service.dart app/test/widget_push_dedup_test.dart
git commit -m "perf(widget): push 加 in-flight 守卫"
```

---

### Task 8: `AlarmStore` 批量写（原生，真机验）

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/AlarmStore.kt`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/AlarmScheduler.kt`（若有调用点要改）

**Interfaces:**
- Consumes: 既有的 `AlarmStore.put` / `putQuiet` / `write` / `writeQuiets`
- Produces: 新增批量入口（例如 `putAll(context, List<Entry>)` / `putAllQuiets(context, List<Quiet>)`），
  `put` / `putQuiet` 变成它在单条上的封装

- [ ] **Step 1: 先量现状**

在 `MainActivity.scheduleNativeAlarm` 那条路上，把 `AlarmStore.put` 的调用次数打一条汇总日志
（或直接数：一次 `rescheduleAll` 排 N 条就是 N 次 `all()` + N 次全量 `write()`）。

Run: 真机装包 → 打开 App 触发一次 `rescheduleAll` → `adb logcat` 取汇总
Expected: 记下「今天一次重排落盘几次、耗时多少」——**这是改前的基线，要写进账本**。

- [ ] **Step 2: 改**

`AlarmStore` 加批量入口：**一次** `all()` → 在内存里合并整批 → **一次** `write()`。
`reschedule` 那条路改成攒够一批再落盘（**不是每条都落**）。
⚠️ **`@Synchronized` 的语义不能丢**，且 `write()` 内部仍是 `apply()`。

- [ ] **Step 3: 真机验**

Run: 重装 → 触发一次 `rescheduleAll` → 取汇总日志
Expected: 落盘次数从 N 降到 **1**；耗时明显下降。

- [ ] **Step 4: 逐条过「不丢记录」**

真机：排一次 → **强停 App**（`adb shell am force-stop`）→ 重启 → 闹钟列表**一条都不少**。
再验一次「关机重启后重排」（`BootReceiver` 读清单）仍然完整。

- [ ] **Step 5: 提交**

```bash
git add app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/AlarmStore.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/AlarmScheduler.kt
git commit -m "perf(alarm): AlarmStore 批量落盘（一次重排读写一次）"
```

---

### Task 9: `AlarmRingService` 15 分钟超时自停（原生，真机验）

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/AlarmRingService.kt`

**Interfaces:**
- Consumes: 用户手动关闭那条既有路径（`stopAlarm` / `MainActivity.exitLockScreenMode()`）
- Produces: 无新公开接口

- [ ] **Step 1: 改**

`onStartCommand` 里排一个 **15 分钟**的 `Handler.postDelayed`（或 `AlarmManager`），到点走
**与用户手动关闭完全相同的那条拆除路径**：
`exitLockScreenMode()` + 撤通知（`stopForeground` / `NotificationManager.cancel`）
+ 放 wakelock + 把响铃界面关掉 + `stopSelf()`。
**「再睡一会」重新计时**（取消旧的、排新的）。

- [ ] **Step 2: 真机验（四条，逐条记结论）**

1. 排一个 1 分钟后的测试闹钟 → 不管它 → **15 分钟**后自己停、通知消失、声音停；
2. **停完之后手机锁屏，App 主界面不能被操作**（`exitLockScreenMode` 确实撤了）；
3. 响铃中点「再睡一会」→ 再次响时**重新有 15 分钟**；
4. 响铃中手动关闭 → 行为与以前**一字不差**。

Run: 每条都在 `adb logcat` 上留证据；结论写进 `work/perf/native-verify.md`。
Expected: 四条全过。**任何一条不过就停下来解决。**

- [ ] **Step 3: 提交**

```bash
git add app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/AlarmRingService.kt
git commit -m "feat(alarm): 响铃 15 分钟超时自停，走与手动关闭相同的拆除路径"
```

---

### Task 10: 小组件刷新默认退非精确（原生，真机验）

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRefreshScheduler.kt`

**Interfaces:**
- Consumes: 既有的 `schedule(context, atMs)`
- Produces: 无新公开接口（行为变化：默认走 `setAndAllowWhileIdle`）

- [ ] **Step 1: 改**

`schedule()` 的默认分支从 `setExactAndAllowWhileIdle` 换成 `setAndAllowWhileIdle`，
并把现有注释从「无精确权限时才退化」改成「**跨天翻页本来就不要求秒级，默认就不占精确闹钟**」。
保留异常时的 `set()` 那一层退路。

- [ ] **Step 2: 真机验**

1. 三张卡都排上 → 跨一次午夜（或把系统时间拨到 23:59）→ 卡片**翻页了**（允许晚几分钟）；
2. `adb shell dumpsys alarm | grep daoban` 里**不再有** `*alarm*`（精确）那一档。

- [ ] **Step 3: 提交**

```bash
git add app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRefreshScheduler.kt
git commit -m "perf(widget): 刷新默认退非精确闹钟"
```

---

### Task 11: 收尾 —— 拆探针、还原 gradle、版本号、更新日志、AGENTS

**Files:**
- Delete: `app/tool/probe/`、`work/perf/`（含账本，**先把结论抄进最终汇报**）
- Modify: `app/android/app/build.gradle.kts`（删掉 `maybeCreate("profile")` 那一段）
- Modify: `app/pubspec.yaml`（`0.10.21+145` → `0.10.22+146`）
- Modify: `app/lib/core/app_info.dart`（`0.10.22`）
- Modify: `app/lib/features/profile/app_dialogs.dart`（更新日志 prepend + 删最旧一条）
- Modify: `AGENTS.md`（版本史 + 「最近改动」）

**Interfaces:**
- Consumes: Tasks 1~10
- Produces: 可发布的树

- [ ] **Step 1: 拆探针**

确认 `app/lib/core/glass/glass.dart` 里 `probeSkipBackdrop` / `probeFilterMode`
**已经没有了**（Task 1 应该已删）；删 `app/tool/probe/`；还原 `build.gradle.kts`。

Run: `git status --short` → 只许剩下版本号与文档那几个文件。

- [ ] **Step 2: 版本号两处同步**

Run: `flutter test test/app_info_test.dart`
Expected: PASS（两处不一致它直接红）。

- [ ] **Step 3: 更新日志**

`_changelogZh` / `_changelogEn` prepend 0.10.22 条目（**测试版条目原样写自己改了什么，不归纳**），
删最旧一条。**纯文本**，不许 markdown 标记。

Run: `flutter test test/changelog_window_test.dart`
Expected: PASS（窗口 10 条、版本号严格递减、首条 == appVersion、中英版本号列表逐条一致、
无 markdown 标记）。

- [ ] **Step 4: `AGENTS.md`**

版本史追加 0.10.22；「最近改动」写清这一轮的**根因与数字**
（瓶颈在光栅线程、`BackdropFilter` 通道本身的代价、观感实测不可见）。

- [ ] **Step 5: 全套验收**

Run: `flutter analyze && flutter test && flutter test tool/visual/`
Expected: 0 issue；**≥ 807 + 本轮新增**条全绿；工装 349 全绿。

- [ ] **Step 6: 提交**

```bash
git add -A && git commit -m "chore(release): v0.10.22 —— 动画与流畅性第二轮"
```

---

### Task 12: 发布 v0.10.22 测试版

**Files:**
- Create: `tools/gh/release-notes-v0.10.22.md`
- Modify: 发布产生的 `latest.json`（由脚本处理）

**Interfaces:**
- Consumes: Task 11 打好的树
- Produces: GitHub 上的预发布 + main 上的 `latest.json`

- [ ] **Step 1: 先把最终汇报要用的结论从临时账本抄出来**

`work/perf/visual-baseline.md` / `device-after.md` / `native-verify.md` 里的
**数字与结论**先落到对话里 —— 那三个文件下一步就删了。

- [ ] **Step 2: 写发布说明**

`tools/gh/release-notes-v0.10.22.md`：用户能读懂的版本（照 v0.10.21 那份的口径），
开头一句说清「这一版解决了什么感觉」。

- [ ] **Step 3: 提交并推 beta**

```bash
git push origin beta
git tag v0.10.22 && git push origin v0.10.22
```

- [ ] **Step 4: 发布**

```bash
# PowerShell：先 . tools\build-env.ps1，并设好 GH_CONFIG_DIR
scripts\release.ps1 -SkipConfirm
```
⚠️ **`release.ps1` 不构建 APK** —— 它只复制现成的，所以**必须先**
`flutter build apk --release --target-platform android-arm64`，
否则挂上去的是上一版的缓存产物（脚本第 4 步的闸门拦的就是这个）。

- [ ] **Step 5: 核对主通道**

```bash
curl -s https://raw.githubusercontent.com/<owner>/<repo>/main/latest.json
```
Expected: `prerelease` 是 `0.10.22`。**不是就手动补**（照 AGENTS.md「分支与发布」那节的命令）。

---

## 计划之外、但必须在最终汇报里交代的

- 规格 §9 里那两条**我定的**：「响铃自停 15 分钟」与「`GlassPanel` 阴影这一轮不补」。
- Review Focus 那五条**逐条**的实际结论。
- 像素基线里**每一张有差异的屏**及其理由（Task 2 的账本）。
- 若 Task 3 没达标：剩下的帧是什么、为什么这一轮不做。
