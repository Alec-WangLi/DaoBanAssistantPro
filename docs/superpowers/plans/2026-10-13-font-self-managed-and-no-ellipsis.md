# 字号自管 + 收干净「静默省略」实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让字号只由 App 自己的四档设置决定（系统字号不再影响界面），并把全 app 的「字被省略号悄悄吃掉」收干净 —— 每一档、每一屏都不许出现省略，日历页的网格与信息卡也不许出现内部滚动。

**Architecture:** 字号在 `app.dart` 的根部 `builder` 一处收口（`MediaQuery.textScaler` 换成 `TextScaler.linear(我们的档位)`，系统那一维归零）。版式不再需要「一份版式容忍无限大」——因为我们知道有哪几档，可以逐档定版式（大字号档顶栏常态两行）。判据靠一条**常设护栏**兜住：把每一屏在每一档下渲一遍，断言「没有任何段落被截断、也没有容器把段落裁短」。

**Tech Stack:** Flutter 应用（`app/`）、Riverpod（设置）、visual harness（`app/tool/visual/`，出图与渲染装配）、`flutter test`。

**Spec:** `docs/superpowers/specs/2026-10-13-narrow-large-font-design.md` —— **执行者要读它**，本计划的每条裁定都能在那里找到理由。

## Global Constraints

- 版本号：本轮为 **0.11.12(+159)**（测试版，`X.Y` 由用户定，AI 只改 `Z` 与 `build`）。`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 必须同步（`app/test/app_info_test.dart` 盯着）。
- 四条字号档位起步值：**小 0.9 / 标准 1.0 / 大 1.15 / 特大 1.3**（**最终落定 0.9 / 1.0 / 1.1 / 1.2**，理由见 spec §5）。**「特大」最终取哪一档由 Task 9 的出图 + 断言决定**，不许在本计划里提前拍死。
- 界面层不许写死字号 / 字重 / 圆角 / 时长字面量（`app/test/design_tokens_test.dart` 扫源码守门），一律走 `AppTokens`。
- 文案一律进 `app/lib/core/l10n.dart` 的 `t('中文','English')`，不许在界面里写死中文。
- **本地验收两条都要跑**：`flutter analyze`（0 error / 0 warning）与 `flutter test` 全绿；涉及界面的任务额外跑 `flutter test tool/visual/`。
- 本沙箱跑 Flutter 前先设：`FLUTTER_ROOT=<repo>/toolchain/flutter`、`PUB_CACHE=<repo>/toolchain/pub-cache`、`JAVA_HOME=<repo>/toolchain/jdk`、`ANDROID_HOME=<repo>/toolchain/android-sdk`，并把 `$FLUTTER_ROOT/bin` 加进 `PATH`。
- **不要跑 `dart format`**（工具链是新版 tall style，一跑就重排整个文件）。

## Review Focus

以下几类是这个 spec 隐含、但任何单个任务的测试都盖不住的地方 —— **最容易让用户踩到，按可能性排序**。每条在本计划里都挂了一个断言（见括号里的任务）：

1. **把系统字号挡在门外之后，无障碍用户看到什么** —— 系统调到 200% 时界面**不变**（这是有意的取舍，但必须有断言钉住「不变」，而不是「碰巧没测」）。（Task 1）
2. **英文文案比中文长**，同一条「静默省略」在英文下更容易发生，而现有量表只跑了中文。（Task 3）
3. **小窗 200×400 与横屏 900×420** 是既有档位，新一轮改动最容易顺手弄坏它们。（Task 3）
4. **信息卡的高度模型**：卡片高度是按「该月最满的一天」算的，与选中哪天无关（`calendar_screen_test.dart` 的「点开某天」用例盯着）。改那两行的行数会动到这个模型。（Task 7）
5. **桌面小组件仍然吃系统 `sp`** —— 本轮**不改**（它是原生 `RemoteViews`）。系统 200% 时桌面那张卡还会变大，别误以为已经修好了。（Task 9 的文档收尾）

---

### Task 1: 字号档位（设置项 + 根部生效 + 我的页控件）

**Files:**
- Modify: `app/lib/state/app_settings.dart`（`AppFontSize` 枚举、`AppSettings.fontSize`、`copyWith`、`_load`、`setFontSize`、`resetToDefaults`）
- Modify: `app/lib/app.dart`（`builder` 里的 `MediaQuery`）
- Modify: `app/lib/core/l10n.dart`（5 条新文案）
- Modify: `app/lib/features/profile/profile_screen.dart`（外观那张卡里加一行）
- Test: `app/test/app_font_size_test.dart`（新建）

**Interfaces:**
- Consumes: 无（本任务是地基）。
- Produces:
  - `enum AppFontSize { small, standard, large, extraLarge }`，带 `double get scale`（0.9 / 1.0 / 1.15 / 1.3）。
  - `AppSettings.fontSize`（`AppFontSize`，默认 `AppFontSize.standard`）；prefs 键 **`'fontSize'`**，存 `name`。
  - `Future<void> AppSettingsNotifier.setFontSize(AppFontSize size)`。
  - 根部生效：`MaterialApp.builder` 里那层 `MediaQuery` 的 `textScaler` = `TextScaler.linear(settings.fontSize.scale)` —— **它会整个替换掉系统报上来的 scaler**。
  - 新增 l10n：`L10n.fontSize`（字体大小 / Text size）、`L10n.fontSmall`、`L10n.fontStandard`、`L10n.fontLarge`、`L10n.fontExtraLarge`（小/标准/大/特大 · Small/Standard/Large/Extra large）。

- [ ] **Step 1: 写失败的测试**

`app/test/app_font_size_test.dart`，三条：

```dart
// 1. 拨档位 → 根部那个 textScaler 跟着变
testWidgets('拨「大」：根部的 textScaler 变成 1.15', (tester) async {
  await _pumpApp(tester);                       // 走 ShiftAssistantApp（真根 Widget）
  final notifier = _notifier(tester);
  await notifier.setFontSize(AppFontSize.large);
  await tester.pump();
  expect(MediaQuery.textScalerOf(_ctx(tester)).scale(14), closeTo(14 * 1.15, 0.01));
});

// 2. **系统字号被挡在门外** —— 这条是 Review Focus 第 1 条
testWidgets('系统字号调到 2.0：App 的字号一点不变', (tester) async {
  tester.platformDispatcher.textScaleFactorTestValue = 2.0;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await _pumpApp(tester);
  expect(MediaQuery.textScalerOf(_ctx(tester)).scale(14), closeTo(14, 0.01),
      reason: '字号只由 App 自己的档位决定 —— 系统那一维已经被 §3 有意挡在门外');
});

// 3. 四档的值就是约定的那四个
test('四档的倍率', () {
  expect(AppFontSize.small.scale, 0.9);
  expect(AppFontSize.standard.scale, 1.0);
  expect(AppFontSize.large.scale, 1.15);
  expect(AppFontSize.extraLarge.scale, 1.3);
});
```

- [ ] **Step 2: 跑测试，确认它失败**

Run: `flutter test test/app_font_size_test.dart`
Expected: 编译失败（`AppFontSize` 未定义）。

- [ ] **Step 3: 实现**

`app_settings.dart`：枚举放在 `AppThemeMode` 旁边；`AppSettings` 加 `fontSize` 字段（默认 `standard`）与 `copyWith` 参数；`_load` 读 `sp.getString('fontSize')`（照 `themeMode` 那条 `firstWhere(..., orElse:)` 的写法）；`setFontSize` 照 `setThemeMode` 的写法（先改 state 再落盘）；`resetToDefaults()` 一并拨回 `standard`。

`app.dart`：`ref.watch(appSettingsProvider.select(...))` 那个具名记录**加一个 `fontSize`**（它参与渲染，必须进 select —— `settings_select_test.dart` 钉着「只订阅真正渲染的那几项」，字号是渲染项）。根部那层 `MediaQuery` 改成：

```dart
builder: (context, child) => MediaQuery(
  data: sanitizeSystemInsets(MediaQuery.of(context))
      .copyWith(textScaler: TextScaler.linear(settings.fontSize.scale)),
  child: AnnotatedRegion<SystemUiOverlayStyle>(...),   // 原样保留
),
```

`l10n.dart`：五条新文案，照 `sectionAppearance` / `themeMode` 的写法。

`profile_screen.dart`：在「语言」那一行**之后**、用同一个配方加一行 —— `Text(L10n.fontSize, style: AppTokens.labelStrong)` + `SizedBox(height: 8)` + `GlassSegment(count: 4, selectedIndex: settings.fontSize.index, onSelected: (i) => …setFontSize(AppFontSize.values[i]), itemBuilder: (i, selected) => Text([…][i], style: AppTokens.labelSecondary.copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)))`。

- [ ] **Step 4: 跑测试，确认通过**

Run: `flutter test test/app_font_size_test.dart test/settings_select_test.dart test/design_tokens_test.dart`
Expected: PASS。（`settings_select_test` 若因记录多了一个字段而红，按它的立意修 —— **只许把「字号」这类真的参与渲染的项加进 select**，不许退回全量 watch。）

- [ ] **Step 5: 提交**

```bash
git add app/lib/state/app_settings.dart app/lib/app.dart app/lib/core/l10n.dart app/lib/features/profile/profile_screen.dart app/test/app_font_size_test.dart
git commit -m "feat(font): 字号只由 App 自己的四档决定，系统字号不再影响界面"
```

---

### Task 2: 把工装与既有用例从「平台字号」切到「我们的档位」

**Files:**
- Modify: `app/tool/visual/render_screens_test.dart`（`20_calendar_large_font` 那一屏）
- Modify: `app/tool/visual/visual_harness.dart`（`pumpScreen` / `renderScreen` 的 `textScale` 参数）
- Test: 既有用例里凡是用 `textScale` 的（先全局搜出来）

**Interfaces:**
- Consumes: Task 1 的 `AppFontSize` 与 prefs 键 `'fontSize'`。
- Produces: `pumpScreen(..., double textScale = 1.0)` **改名并改义**为 `AppFontSize fontSize = AppFontSize.standard`，它通过 `extraPrefs: {'fontSize': fontSize.name}` 生效（走 prefs → `appSettingsProvider._load()` → 根部）。`VisualApp` 那层 `textScale` 参数**删掉**（它现在什么也不会发生，留着就是骗后人的）。

- [ ] **Step 1: 先搜清楚谁在用**

Run: `grep -rn "textScale\|textScaleFactor\|textScalerOf" app/lib app/test app/tool`
Expected: 得到一份清单。**逐个判断它属于哪一类**：① 想验「大字号下的样子」→ 改成走 `AppFontSize`；② 想验「系统字号变化时的行为」→ 那条现在**应该断言「不变」**（Review Focus 第 1 条）。

- [ ] **Step 2: 写一条让改动可验证的测试**

在 `app/test/app_font_size_test.dart` 里补一条：

```dart
testWidgets('工装里给「特大」：渲染出来的确是我们的特大档，而不是被平台字号带着走', (tester) async {
  // 同时把平台字号也调到 2.0，确认它被忽略
  tester.platformDispatcher.textScaleFactorTestValue = 2.0;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await _pumpShell(tester, fontSize: AppFontSize.extraLarge);
  expect(MediaQuery.textScalerOf(_ctx(tester)).scale(14), closeTo(14 * 1.3, 0.01));
});
```

- [ ] **Step 3: 跑测试，确认它失败**

Run: `flutter test test/app_font_size_test.dart`
Expected: FAIL（`_pumpShell` 还没有 `fontSize` 参数）。

- [ ] **Step 4: 实现**

`visual_harness.dart`：`pumpScreen` / `renderScreen` 的 `double textScale = 1.0` 换成 `AppFontSize fontSize = AppFontSize.standard`，实现上往 `extraPrefs` 里塞 `{'fontSize': fontSize.name}`；`VisualApp` 里那段 `MediaQuery(...copyWith(textScaler: TextScaler.linear(textScale)))` 删掉（根部已经由 `app.dart` 统一管）。`render_screens_test.dart` 的 `20_calendar_large_font` 改成 `fontSize: AppFontSize.extraLarge` 并把屏名与注释里的「1.8×」一并订正。

- [ ] **Step 5: 跑测试，确认通过**

Run: `flutter test test/app_font_size_test.dart` → PASS
Run: `flutter test tool/visual/` → 全绿
Run: `flutter test` → 全绿

- [ ] **Step 6: 提交**

```bash
git add -A app/tool app/test
git commit -m "test(font): 工装与既有用例改用我们自己的字号档位（平台字号已被挡掉）"
```

---

### Task 3: 常设护栏（两种判据 + 白名单 + 反向验证）

**Files:**
- Create: `app/tool/visual/text_fit_guard_test.dart`
- Test: 它自己

**Interfaces:**
- Consumes: Task 2 的 `pumpScreen(..., fontSize:)`、`visualScreens` / `screenExtraPrefs` / `onboardingPrefs` / `teardownVisual` / `makeVisualDatabase`。
- Produces: `const Map<String, String> kDeliberateEllipsis`（**具名白名单**：段落文本 → 允许被截的理由）。判据函数 `List<String> truncatedParagraphs(WidgetTester tester)`（返回「被截的段落文本 + 它被截的方式」）。

**为什么放 `tool/visual/` 而不是 `test/`**（与 spec §8 的措辞有一处偏离，理由写在这）：它要装配**全部 39 屏**、每屏 8 种配置（4 档 × 320/360 两个宽度），且依赖 visual harness 的一整套装配函数。放这儿与它同族、也不会把日常 `flutter test` 拖慢。**两条验收命令都要跑它**（AGENTS.md 的验收标准本来就含 `tool/visual/`）。

- [ ] **Step 1: 写失败的判据测试**

先只做判据本身，用**一条已知会被截断的构造**验它抓得住：

```dart
testWidgets('判据能抓住两种截断', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold(
    body: Column(children: [
      SizedBox(width: 80, child: Text('这一串字在八十像素里一定放不下', maxLines: 1, overflow: TextOverflow.ellipsis)),
      SizedBox(height: 12, width: 200, child: ListTile(
        title: const Text('标题'),
        subtitle: const Text('副标题很长很长很长很长很长很长很长很长', maxLines: 2, overflow: TextOverflow.ellipsis),
      )),
    ]),
  )));
  final hits = truncatedParagraphs(tester);
  expect(hits.where((h) => h.contains('方式 1')), isNotEmpty, reason: '段落自己截的');
  expect(hits.where((h) => h.contains('方式 2')), isNotEmpty,
      reason: '容器把段落裁短的 —— `ListTile` 不给 `isThreeLine` 就会这样，'
          '而这时 `didExceedMaxLines` 是 false，只查它会瞎');
});
```

- [ ] **Step 2: 跑测试，确认它失败**

Run: `flutter test tool/visual/text_fit_guard_test.dart`
Expected: FAIL（`truncatedParagraphs` 未定义）。

- [ ] **Step 3: 实现判据**

`truncatedParagraphs` 遍历 `tester.allRenderObjects.whereType<RenderParagraph>()`，按两条判据收集：

1. `ro.didExceedMaxLines == true` → 记「方式 1」。
2. `ro.getMaxIntrinsicHeight(ro.size.width) > ro.size.height + 0.5` → 记「方式 2」（它在当前宽度下本来需要更高，实际拿到的不够 —— 说明被容器裁了）。

两条都要**跳过白名单**：段落文本命中 `kDeliberateEllipsis` 的键、或**文本本身就以 `…` 结尾**（那是我们自己烘进字符串里的截断，如 `LunarInfo.cellLabel`）。命中白名单要 `debugPrint` 一行（与 `design_tokens_test.dart` 的豁免同一套规矩 —— 故意不查的东西要看得见）。

- [ ] **Step 4: 跑测试，确认判据通过**

Run: `flutter test tool/visual/text_fit_guard_test.dart`
Expected: PASS。

- [ ] **Step 5: 把判据接到全部屏上（**预期它当场红**）**

同一个文件里加第二组用例：`for (final screen in visualScreens) for (final cfg in <({String label, Size size, AppFontSize font, String lang})>[...])`，配置矩阵 = **4 档 × 320×640 × (中文, 英文)** 加 **4 档 × 360×780 × 中文**，每条 `pumpScreen(..., size:, fontSize:, language:, extraPrefs:)` → 调 `truncatedParagraphs` → 非空即 `fail`，**一次列全**（照 `failOnOverflow` 的写法：收进列表、`addTearDown` 里统一报，别在循环里当场 fail）。

同时把「布局溢出」那一条也收进来（现在只在出图用例里）：照抄 `failOnOverflow` 的收集方式。

Run: `flutter test tool/visual/text_fit_guard_test.dart`
Expected: **FAIL，并打印出一份清单** —— 这就是 Task 4~8 的施工单。把它记进进度文件。

- [ ] **Step 6: 提交**

```bash
git add app/tool/visual/text_fit_guard_test.dart
git commit -m "test(visual): 常设护栏 —— 全屏 × 四档 × 两宽度，抓「字被悄悄吃掉」的两种方式"
```

> ⚠️ 从这一步起，这条护栏是红的，直到 Task 8 结束。**每个后续任务只许让它变绿、不许放宽度量**；白名单只能加**具名 + 带理由**的条目。

---

### Task 4: 日历顶栏的年月

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart:814-930`（`_header`）
- Test: `app/test/calendar_header_fit_test.dart`（新建）

**Interfaces:**
- Consumes: 无新接口。
- Produces: `Widget _header(BuildContext context)` 的行为变化 —— 一行档与两行档的选择**由排版实测决定**（不再由 `AppLayout.isNarrow` 决定）；两行档是「大 / 特大」两档的**常态版式**。

- [ ] **Step 1: 写失败的测试**

```dart
// 1.0× —— 一行放得下，走一行档
testWidgets('标准档 360dp：顶栏一行，年月完整', (tester) async {
  await _pumpCalendar(tester, width: 360, font: AppFontSize.standard);
  expect(find.byKey(const Key('header-single-row')), findsOneWidget);
  expect(_yearMonthText(tester), isNotNull, reason: '年月那串文字不许被截');
});

// 1.3× —— 一行放不下，走两行档，年月仍然完整
testWidgets('特大档 360dp：顶栏自动两行，年月仍完整', (tester) async {
  await _pumpCalendar(tester, width: 360, font: AppFontSize.extraLarge);
  expect(find.byKey(const Key('header-two-row')), findsOneWidget);
  expect(_yearMonthText(tester), isNotNull);
});
```

（两个 `Key` 由本任务的实现加上。）

- [ ] **Step 2: 跑测试，确认它失败**

Run: `flutter test test/calendar_header_fit_test.dart`
Expected: FAIL（`header-single-row` / `header-two-row` 都不存在）。

- [ ] **Step 3: 实现**

`_header` 拆成 `_headerSingleRow` / `_headerTwoRow` 两支（今天那个「窄档」分支就是 `_headerTwoRow`，把它的触发条件从 `AppLayout.of(context).isNarrow` 换成**本任务新增的判据**）。判据函数：

```dart
/// 一行装不装得下 —— 用**排版实测**，不用宽度阈值猜。
///
/// 固定件 = 四个圆形钮（`40`）＋ 四个 `AppTokens.gapIconText` ＋「今天」胶囊的实测宽；
/// 可变件 = 年月的排版宽（`TextPainter` 量，与 `info_card_metrics` 同一套路）。
/// 判据：`年月宽 + 固定件 > 可用宽` ⟹ 走两行。
bool _needsTwoRowHeader(BuildContext context, TextStyle style);
```

`VoidCallback _today` 那侧的 `GlassSegment`/胶囊在 `_headerTwoRow` 里**只留图标**（现状已经是）。

- [ ] **Step 4: 跑测试，确认通过**

Run: `flutter test test/calendar_header_fit_test.dart test/calendar_screen_test.dart`
Expected: PASS。

- [ ] **Step 5: 跑护栏，看它少报几条**

Run: `flutter test tool/visual/text_fit_guard_test.dart`
Expected: 清单里`2026年10月`那一族消失；其余照旧。

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_header_fit_test.dart
git commit -m "fix(calendar): 顶栏按排版实测决定一行/两行，年月不再被省略"
```

---

### Task 5: 编辑器的标签值行

**Files:**
- Modify: `app/lib/features/calendar/schedule_management_screen.dart:511`（`_labelValueRow`）
- Test: `app/test/label_value_row_test.dart`（新建）

**Interfaces:**
- Consumes: 无。
- Produces: `_labelValueRow` 的行为变化 —— 标签**最多 2 行**；值**按可用宽等比缩小**（`FittedBox(scaleDown)`，不折行、不省略）。签名不变（`{required String label, required String value, required bool mutedValue, required VoidCallback onTap, Widget? trailing}`），所以 §6.4 的三处调用点一行都不用改。

- [ ] **Step 1: 写失败的测试**

```dart
testWidgets('标签值行：窄屏大字号下标签折两行、值缩小，两处都不省略', (tester) async {
  await _pumpRow(tester, width: 320, font: AppFontSize.extraLarge,
      label: '响铃时间', value: '前一天 23:00');
  expect(truncatedParagraphs(tester), isEmpty);
  expect(tester.widget<Text>(find.text('响铃时间')).maxLines, 2);
});
```

- [ ] **Step 2: 跑测试，确认它失败**

Run: `flutter test test/label_value_row_test.dart`
Expected: FAIL（`truncatedParagraphs` 非空 / `maxLines` 是 1）。

- [ ] **Step 3: 实现**

标签那个 `Expanded(Text(label, maxLines: 1, overflow: ellipsis))` → `maxLines: 2`，**去掉 `overflow: ellipsis`**（留默认的 clip 也无妨，判据 2 会盯着它到底有没有被裁）。值那个 `Flexible(Text(value, maxLines: 1, overflow: ellipsis, textAlign: right))` → 包一层 `FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(value, maxLines: 1, textAlign: TextAlign.right))`。

- [ ] **Step 4: 跑测试，确认通过**

Run: `flutter test test/label_value_row_test.dart test/schedule_management_test.dart test/schedule_timeline_test.dart`
Expected: PASS。

- [ ] **Step 5: 跑护栏**

Run: `flutter test tool/visual/text_fit_guard_test.dart`
Expected: `响铃时间` / `前一天 23:00` / `次日 00:15` / `可选，如「午休」` 那一族消失。**`可选，如「午休」` 若仍在**：它是 `glassInputDecoration` 的 `hintText`，按 §6.4 同样放成 2 行（同一个文件里的输入框装饰），在本步一并收掉。

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/calendar/schedule_management_screen.dart app/test/label_value_row_test.dart
git commit -m "fix(editor): 标签值行 —— 标签折两行、值按宽度缩小，不再省略"
```

---

### Task 6: 列表行的副标题

**Files:**
- Modify: `app/lib/features/schedule/schedule_screen.dart`、`app/lib/features/calendar/schedule_management_screen.dart`、`app/lib/features/calendar/shift_override_picker.dart`、`app/lib/features/calendar/shift_template_picker_screen.dart`、`app/lib/features/profile/profile_screen.dart`（这五处有 `subtitle:`）
- Test: `app/test/list_subtitle_fit_test.dart`（新建）

**Interfaces:**
- Consumes: 无。
- Produces: 约定 —— **凡是要折两行的 `ListTile` 副标题，必须同时给行高**（`isThreeLine: true`，或换掉 `ListTile`）。**只改 `maxLines` 不改行高 = Tile 把第二行裁掉，而段落自己认为「我没被截」**（判据 1 看不见，只有判据 2 抓得住）。

- [ ] **Step 1: 写失败的测试**

```dart
testWidgets('待办副标题：320dp 特大档折两行、两行都看得见', (tester) async {
  await _pumpTodos(tester, width: 320, font: AppFontSize.extraLarge);
  expect(truncatedParagraphs(tester), isEmpty,
      reason: '判据 2 会抓到「给了 maxLines: 2 但行高没放开」这种裁切');
  // 反向验证用：把 isThreeLine 拿掉，这条要红
});
```

- [ ] **Step 2: 跑测试，确认它失败**

Run: `flutter test test/list_subtitle_fit_test.dart`
Expected: FAIL（判据 2 报出副标题被裁）。

- [ ] **Step 3: 实现**

五处逐个过：副标题所在的 `ListTile` 加 `isThreeLine: true`（副标题两行时的正确用法；不加的话 Tile 的固定行高会把第二行裁掉），需要时把 `subtitle` 的 `maxLines` 提到 2。**闹钟页那类「一行里并排时间+名称」的密集列表不改行高**，改走 §6.3 的例外：把值那一列包 `FittedBox(scaleDown)`。

- [ ] **Step 4: 跑测试，确认通过**

Run: `flutter test test/list_subtitle_fit_test.dart test/todo_archive_screen_test.dart test/recurring_screen_test.dart test/alarm_screen_test.dart`
Expected: PASS。

- [ ] **Step 5: 跑护栏**

Run: `flutter test tool/visual/text_fit_guard_test.dart`
Expected: `10月13日 星期二 · …` / `炼油三部 · 四班三倒` / `「再睡一会」之后隔 5 分钟重新响铃` 那一族消失。

- [ ] **Step 6: 提交**

```bash
git add app/lib/features app/test/list_subtitle_fit_test.dart
git commit -m "fix(lists): 副标题折两行并把行高放开，不再静默省略"
```

---

### Task 7: 信息卡那两行

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart:2476`（农历行）、`:2551`（班次行）
- Modify: `app/lib/features/calendar/info_card_metrics.dart`（量高时用的行数要跟着改）
- Test: `app/test/info_card_fit_test.dart`（新建）

**Interfaces:**
- Consumes: 无。
- Produces: 农历行 `maxLines: 3`（从 2 提一档）且**去掉 `overflow: ellipsis`**；班次行 `maxLines: 2`。`info_card_metrics` 里对应两行的高度模型同步改成新行数。

**不要碰**：卡片高度**与选中哪天无关**这条不变量（`calendar_screen_test.dart` 的「点开某天」用例盯着）。

- [ ] **Step 1: 写失败的测试**

```dart
testWidgets('信息卡：320dp 特大档，农历与班次行都不省略、卡片自己也不滚', (tester) async {
  await _pumpCalendar(tester, width: 320, font: AppFontSize.extraLarge);
  expect(truncatedParagraphs(tester), isEmpty);
  expect(informationCardMaxScrollExtent(tester), 0,
      reason: '§2 第 2 条：卡片不许自己滚');
});

testWidgets('日历页：网格 6 行全在视口里，网格也没有可滚的余量', (tester) async {
  await _pumpCalendar(tester, width: 320, font: AppFontSize.extraLarge);
  expect(gridMaxScrollExtent(tester), 0,
      reason: '§2 第 3 条（用户原话：「日期…不要出现内容太多、需要你自己滚」）');
});
```

（两个 helper 由本任务实现：`tester.state<ScrollableState>(...)` 读 `position.maxScrollExtent`。）

- [ ] **Step 2: 跑测试，确认它失败**

Run: `flutter test test/info_card_fit_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

改那两行的 `maxLines` 与 `overflow`；`info_card_metrics.dart` 里对应的行数常量一并改（两处必须同步 —— 不同步的表现是「卡片高度算矮了、内容被底边裁掉」，判据 2 会抓）。

**若 320dp@特大 下网格被挤出余量**：**不许**给卡片加滚动、也**不许**去动网格那个滚动容器（它是亚像素兜底，见 spec §2 第 3 条）—— **本步的收法是回报「这一档 320dp 收不住」**，交 Task 9 决定是把「特大」降到 1.25/1.2，还是把保证线定在 360dp。**在 Task 9 拍板前不许擅自降档。**

- [ ] **Step 4: 跑测试，确认通过（或带着一条明确的「收不住」结论收工）**

Run: `flutter test test/info_card_fit_test.dart test/calendar_screen_test.dart test/info_card_chain_test.dart`
Expected: PASS。

- [ ] **Step 5: 跑护栏 + 出图看**

Run: `flutter test tool/visual/text_fit_guard_test.dart`
Run: `flutter test tool/visual/`（看图：`build/visual/01_calendar_light.png` 的卡片是不是还紧凑）

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/calendar app/test/info_card_fit_test.dart
git commit -m "fix(calendar): 信息卡两行放宽到装得下，量高的行数同步"
```

---

### Task 8: 14 天预览条

**Files:**
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart:427` 附近（`_previewCell`）
- Test: `app/test/preview_strip_fit_test.dart`（新建）

**Interfaces:**
- Consumes: 无。
- Produces: 格内日期文字包 `FittedBox(scaleDown)`（与日历格子同一条规矩 —— 定尺点阵、不折行、不省略）。

- [ ] **Step 1: 写失败的测试**

```dart
testWidgets('预览条：320dp 特大档，14 格里的日期都不省略', (tester) async {
  await _pumpEditor(tester, width: 320, font: AppFontSize.extraLarge);
  expect(truncatedParagraphs(tester), isEmpty,
      reason: '只该缩，不该省略');
});
```

- [ ] **Step 2: 跑测试，确认它失败**

Run: `flutter test test/preview_strip_fit_test.dart`
Expected: FAIL（`10/13` 一族被省略）。

- [ ] **Step 3: 实现**

`_previewCell` 里那两行文字各包一层 `FittedBox(fit: BoxFit.scaleDown)`（与 `calendar_screen.dart` 里格子内容的写法一致）。

- [ ] **Step 4: 跑测试，确认通过**

Run: `flutter test test/preview_strip_fit_test.dart test/schedule_editor_test.dart`

- [ ] **Step 5: 跑护栏**

Run: `flutter test tool/visual/text_fit_guard_test.dart`
Expected: **全绿**（护栏从 Task 3 起一直是红的，到这里应当归零）。

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/calendar/schedule_editor_screen.dart app/test/preview_strip_fit_test.dart
git commit -m "fix(editor): 14 天预览条的格内文字改为按宽缩小，不再省略"
```

---

### Task 9: 定「特大」是哪一档 · 屏单补两档 · 收尾

**Files:**
- Modify: `app/lib/state/app_settings.dart`（若「特大」要降档，改 `AppFontSize.extraLarge.scale`）
- Modify: `app/tool/visual/render_screens_test.dart`（补两档屏单）
- Modify: `app/test/app_font_size_test.dart`（四档倍率的断言跟着改）
- Modify: `app/pubspec.yaml`、`app/lib/core/app_info.dart`、`app/lib/features/profile/app_dialogs.dart`（版本 + 更新日志）、`AGENTS.md`

**Interfaces:**
- Consumes: 全部前序任务。
- Produces: 定稿的四档值；屏单里的 `360×780 @特大` 与 `320×640 @特大` 两份新图；更新日志与 AGENTS.md 的条目。

- [ ] **Step 1: 出一遍阶梯图，用眼睛定档**

用一次性探针把**日历页**在 `320×640` 与 `360×780` 上、四档各渲一张（照 `tool/probe/font_ladder_probe_test.dart` 的做法，跑完即删），并排拼成一张图放到 `work/`。

判据（spec §5，**必须同时满足**）：

> 顶栏年月完整、网格 6 行全在**且 `maxScrollExtent == 0`**、信息卡内容全部可见**且 `maxScrollExtent == 0`**、没有任何 `didExceedMaxLines`。

- [ ] **Step 2: 若「特大」收不住，降档**

`AppFontSize.extraLarge.scale` 从 1.3 降到 **1.25 或 1.2**（哪个收得住用哪个），同步改 `app_font_size_test.dart` 的断言与 `l10n` 里那一档的文案（「特大」可以保留这个名字）。

Run: `flutter test tool/visual/text_fit_guard_test.dart test/app_font_size_test.dart`
Expected: PASS（降档后没东西被截）。

- [ ] **Step 3: 屏单补两档**

在 `render_screens_test.dart` 里加一组**独立循环**（**不要**去给 `visualVariants` 的记录类型加字段 —— 那种改法要动全部条目，仓库里已有注释说明为什么不做）：对**常设屏单那 6 屏**（`00_home_shell`、`01_calendar`、`07_profile`、`alarm_screen`、`05_todos`、`02_editor`）各渲一张 `360×780 @特大` 与一张 `320×640 @特大`。

Run: `flutter test tool/visual/`
Expected: 全绿；`build/visual/` 多出约 12 张图。

- [ ] **Step 4: 逐张看图**

**这一条不能省。** 护栏只保证「没省略」，保证不了「缩得太小而看不清」。看这 12 张，尤其是：顶栏年月是否还读得出、信息卡有没有变得头重脚轻、编辑器那几行挤不挤。

- [ ] **Step 5: 版本与文档收尾**

`app/pubspec.yaml` → `0.11.12+159`；`app/lib/core/app_info.dart` → `'0.11.12'`；`app_dialogs.dart` 的 `_changelogZh` / `_changelogEn` **prepend** 一条 `v0.11.12`（测试版条目原样写、不归纳），**删最旧一条保持 10 条**，且**不许出现 markdown 标记**（`changelog_window_test.dart` 盯着）。

`AGENTS.md`：版本历史那一行加 `0.11.12(+159)`；「最近改动」加一条，写清三件事 —— ① 字号自管（含**代价**与**桌面小组件仍吃系统 sp** 这个已知缺口）；② 五类静默省略各自怎么收；③ 新增的常设护栏（两种判据 + 那两条反向验证）。

Run: `flutter analyze` → 0 error / 0 warning
Run: `flutter test` → 全绿
Run: `flutter test tool/visual/` → 全绿

- [ ] **Step 6: 提交 + 发布**

```bash
git add -A
git commit -m "chore(release): v0.11.12 —— 字号自管 + 收干净静默省略"
```
然后照项目惯例：`git tag v0.11.12` → `git push origin beta && git push origin v0.11.12` → `scripts/release.ps1 -SkipConfirm`（**先构建 APK**，`release.ps1` 只会复制现成的）→ 最后 `curl` 一次 main 上的 `latest.json` 核对版本号。

---

## 自检记录

- **spec 覆盖**：§2 规矩 → Task 3 的护栏 + 各任务；§3 字号自管 → Task 1/2；§4.4 矩阵 → Task 3/9；§5 四档与逐档定版式 → Task 1/4/9；§6.1~6.5 → Task 4~8；§7 工装 → Task 9；§8 护栏 → Task 3；§9 验收 → 每任务的 Step 4/5 与 Task 9；§10 不做的 → 各任务的「不要碰」；§11.2 的边界（日历页网格与卡片都不许滚）→ Task 7 的两条 `maxScrollExtent == 0`。
- **类型一致**：`AppFontSize` / `AppSettings.fontSize` / `setFontSize` / prefs 键 `'fontSize'` 在 Task 1 定义，Task 2、3、9 与各测试一致引用；`truncatedParagraphs` 在 Task 3 定义，Task 4~8 一致引用。
- **Review Focus 五条各有归属**：①→Task 1；②③→Task 3 的配置矩阵；④→Task 7 的「不要碰」+ 既有用例；⑤→Task 9 的文档收尾。
- **未决项**：Task 7 Step 3 可能回报「320dp@特大 收不住」，那一条由 Task 9 Step 2 拍板，本计划不预判。
