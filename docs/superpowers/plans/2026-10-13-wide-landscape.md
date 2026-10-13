# 横屏（平板 / 车机）重新适配 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让日历页在平板 / 车机的横屏上按「看板」重排（顶栏收进左栏、今日卡贴右下、网格不被胶囊压住、格子里的字跟着格子长），并给底部导航胶囊限宽。

**Architecture:** 在 `AppLayout` 上新增一个「宽横屏」档位，日历页据此分成**三支**（宽横屏新版式 / 宽且矮保留今天版式只加让位 / 其余竖屏不动）。新档位只影响日历页的排布与格子字号的**上限**；导航胶囊限宽是 `GlassNavBar` 的一处约束，全 app 生效；待办页那颗悬浮按钮改的是它自己的 `FloatingActionButtonLocation`。

**Tech Stack:** Flutter / Dart、Riverpod、Drift（本计划不碰数据层）、`flutter_test` + 自带视觉工装（`app/tool/visual/`）。

**Spec:** `docs/superpowers/specs/2026-10-13-wide-landscape-design.md`

## Global Constraints

- **版本号**：`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` **两处同步**改，`X.Y` 不许动，只改 `Z` 与 `build`。本版是 `0.11.13+160` → **`0.11.14+161`**（末位非 0 = 测试版，在 `beta` 分支上做）。由 `test/app_info_test.dart` 盯着两处一致。
- **不许跑 `dart format`** —— 工具链是新版 tall-style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `flutter analyze`。
- **`flutter analyze` 必须 0 error / 0 warning**（约 4 条 info 可容忍）。
- **`flutter test` 全绿，条数只增不减**（当前 **933**）。
- **硬验收：手机竖屏版式逐像素不变**。加了新分支之后必须**实测**（`scripts/diff_visual.py` 逐张比基线），不能靠推理。唯一有意的例外见 Task 5（竖屏平板的格子字号）。
- **界面层不许写字面量**：字号 / 字重 / 圆角 / 时长 / 颜色 / 间距一律走 `core/design_tokens.dart` 的角色令牌，由 `test/design_tokens_test.dart` 守门。新常量若干倍于 4px 栅格的，要么落在栅格上、要么加 `// design-tokens-ignore: <理由>`。
- **不碰原生**：Kotlin / AndroidManifest / 小组件一行都不改。
- **工装**：动了 UI 就要跑 `flutter test tool/visual/` 并按 `app/tool/visual/` 出图看图（「没有屏单 = 没有眼睛」）。
- **一次性探针**（`app/tool/probe/landscape_probe_test.dart`、`nav_rect_probe_test.dart`）**收尾时删掉**。那个目录**是 gitignore 的**（`.gitignore:53` 有 `/app/tool/probe/`），所以不会漏进提交；但仓库惯例是「跑完即删」，别留着让下一次跑全套测试的人多跑两个用不上的文件。

## Review Focus

按「最可能咬到真人」排序，每条都在下面的任务里配了用例：

1. **手机横屏（900×420，宽且矮）** —— 用户在这个尺寸上期望看到的仍然是**一张完整的月历**。判据从 `isWide` 换成 `isWideLandscape` 之后，它会被推进竖屏那一支、被 `if (!layout.isShort)` 把网格整块删掉。界面上只会少一块、**不报任何错**（Task 2）。
2. **竖着的平板（800×1280）** —— `isWide` 成立但不是横屏。它今天被错判成左右两栏；本版改成竖屏版式，但它仍会吃到「宽屏」的格子字号上限（Task 5）。这条路径没有任何真机证据，只能靠用例钉。
3. **车机上「特大」字号 + 六班组那种最满的信息卡** —— 右栏一旦装不下，用户期望看到的是「它自己滚」而不是黄黑条纹，而且卡片仍然贴底（Task 4）。
4. **宽且矮那一支多出来的 96 让位** —— 网格只剩 246dp 给六行（每行 41 < `_minCellH` 58），期望是**照旧滚动**而不是被裁掉（Task 2）。
5. **液态玻璃档下的底栏** —— 限宽之后 `LayoutBuilder` 算出的 `itemW` 变了，按住 / 拖动 / 点按的坐标必须仍然对得上（Task 6）。

---

### Task 1: `AppLayout.isWideLandscape`

**Files:**
- Modify: `app/lib/core/layout.dart`（`AppLayout` 类，约 97-141 行）
- Test: `app/test/app_layout_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `AppLayout.isWideLandscape`（`bool`）—— 后续 Task 2/3/4 的分支判据。

- [ ] **Step 1: 写失败的用例**

追加到 `test/app_layout_test.dart` 的 `main()` 里（`_layoutAt` 已存在，直接用）：

```dart
  testWidgets('宽横屏：够宽、够高、而且是横着的', (tester) async {
    // 平板 / 车机 —— 只有这三档才算「宽横屏」。
    for (final s in const [Size(1024, 600), Size(1280, 800), Size(1920, 720)]) {
      expect((await _layoutAt(tester, s)).isWideLandscape, isTrue, reason: '$s');
    }
    // **竖着的平板**：isWide 成立，但它是竖的，该走竖屏版式。
    expect((await _layoutAt(tester, const Size(800, 1280))).isWideLandscape,
        isFalse, reason: '竖屏平板不该被拆成左右两栏');
    // **宽且矮**（手机横屏）：宽够了，但高不够 —— 分栏之后网格每行只剩 41dp。
    expect((await _layoutAt(tester, const Size(900, 420))).isWideLandscape,
        isFalse);
    // 其余各档一律 false。
    for (final s in const [
      Size(420, 900),
      Size(360, 780),
      Size(200, 400),
      Size(320, 360),
    ]) {
      expect((await _layoutAt(tester, s)).isWideLandscape, isFalse, reason: '$s');
    }
    // 键盘弹起把可用高压到 480 以下时也不算 —— 判据走的是**可用区域**。
    expect(
        (await _layoutAt(tester, const Size(1280, 800),
                viewInsets: const EdgeInsets.only(bottom: 400)))
            .isWideLandscape,
        isFalse,
        reason: '键盘占掉一半高之后就不该再分栏');
  });
```

- [ ] **Step 2: 跑一遍，确认它失败**

Run: `flutter test test/app_layout_test.dart`
Expected: 编译失败 —— `The getter 'isWideLandscape' isn't defined for the type 'AppLayout'`。

- [ ] **Step 3: 实现**

`lib/core/layout.dart` 的 `AppLayout` 里，在 `isWide` 字段后面加字段与构造参数 `required this.isWideLandscape,`，并加 getter 文档：

```dart
  /// 平板 / 车机的**横屏**：**够宽、够高、而且是横着的**。三个条件缺一不可。
  ///
  ///   · [isWide]     —— 宽 ≥ 720，有横向余量才谈得上分栏；
  ///   · `!isShort`   —— 高 ≥ 480，手机横屏只有 420 高，分栏之后网格每行只剩 41dp
  ///                     （日历格子那道可读下限 `_minCellH` 是 58），比不分栏还差；
  ///   · 宽 > 高      —— **竖着的平板**（800×1280）也是 [isWide]，但它该走竖屏那套：
  ///                     七列格子要的是宽度，不是分栏。
  ///
  /// ⚠️ **[isWide] 本身不许跟着改**：`CenteredContent`（另外三个 tab 与三个编辑页）
  /// 靠它把内容限宽到 720。把方向条件并进 `isWide`，竖屏平板会从「居中 720」
  /// 变成「拉满整屏」—— 那是另一个 bug。
  final bool isWideLandscape;
```

`of()` 里加一行：

```dart
      isWideLandscape: w >= _wideWidth && h >= _shortHeight && w > h,
```

- [ ] **Step 4: 跑用例，确认通过**

Run: `flutter test test/app_layout_test.dart`
Expected: PASS（含既有的「五种形态」那条 —— 它没碰新字段，但顺带证明没改坏旧的）。

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/layout.dart app/test/app_layout_test.dart
git commit -m "feat(layout): 新增「宽横屏」档位（宽 ≥ 720 且高 ≥ 480 且宽 > 高）"
```

---

### Task 2: 日历页改成**三支**，两支宽屏都让开胶囊

⚠️ **这是本计划最容易踩坏的一步。** 现在 `build()` 里是 `if (layout.isWide) … else …`。
把判据换成 `isWideLandscape` 而不补第二支，**手机横屏（900×420）会掉进竖屏那一支**，
被那里的 `if (!layout.isShort) gridArea` 把网格整块删掉 —— 界面上只是少一块，不报错。

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`（`build()` 的 `Column`，约 786-847 行）
- Test: `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: `AppLayout.isWideLandscape`（Task 1）
- Produces: `build()` 里三支的结构；后面 Task 3（顶栏）、Task 4（右栏）各自只改自己那一支的内部。

- [ ] **Step 1: 写失败的用例**

追加到 `test/calendar_screen_test.dart`（`_pumpCalendar(tester, templateId, {width, height})`
与 `'six_crew_three_shift'` 模板都已存在）：

```dart
  testWidgets('手机横屏（900×420）上日历仍然画格子', (tester) async {
    // ⚠️ **回归用例**：分栏判据换成「宽横屏」之后，这一档会掉进竖屏那一支，
    // 而竖屏那一支里有 `if (!layout.isShort) gridArea` —— 不加第二支的话
    // 网格会被整块删掉：界面上只是少一块，**不报任何错**。
    await _pumpCalendar(tester, 'six_crew_three_shift',
        width: 900, height: 420);
    expect(find.byKey(const ValueKey('day-card-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('day-card-31')), findsOneWidget);
  });

  testWidgets('宽屏两支都让开底部胶囊：网格底边 ≤ 屏高 − 96', (tester) async {
    // 96 = `kNavCapsuleInset`。竖屏不用管（那一支把让位写在信息卡自己的内边距里）。
    for (final s in const [(w: 1280.0, h: 800.0), (w: 900.0, h: 420.0)]) {
      await _pumpCalendar(tester, 'six_crew_three_shift',
          width: s.w, height: s.h);
      final grid = tester.getRect(find.byKey(const Key('calendar-grid')));
      expect(grid.bottom, lessThanOrEqualTo(s.h - kNavCapsuleInset + 0.5),
          reason: '${s.w}×${s.h}：网格底边 ${grid.bottom} 越过了胶囊让位线');
      await _disposeCalendar(tester);
    }
  });

  testWidgets('宽横屏：最后一行格子完整落在底部胶囊之上', (tester) async {
    // ⚠️ 断言写成「**最下面那一格**的底边」而不是「第 6 行」：月份的行数随月份变
    // （2026-10 是 5 行），钉死行号会写成一句只在某几个月成立的用例。
    await _pumpCalendar(tester, 'six_crew_three_shift',
        width: 1280, height: 800);
    final bottoms = <double>[];
    for (var d = 1; d <= 31; d++) {
      final f = find.byKey(ValueKey('day-card-$d'));
      if (f.evaluate().isEmpty) continue;
      bottoms.add(tester.getRect(f).bottom);
    }
    expect(bottoms, isNotEmpty);
    expect(bottoms.reduce(math.max), lessThanOrEqualTo(800 - kNavCapsuleInset + 0.5),
        reason: '最下面那一格的底边被胶囊压住了');
  });
```

> 第二条用例需要文件顶部有 `import 'dart:math' as math;` —— 没有就加上。

- [ ] **Step 2: 跑一遍，确认它失败**

Run: `flutter test test/calendar_screen_test.dart -n 手机横屏`
Expected: 「手机横屏」那条目前**可能已经是绿的**（判据还没换）—— 它是**护栏**，不是红转绿的用例。
「让开胶囊」与「最后一行」两条必须是 **FAIL**：`find.byKey(Key('calendar-grid'))` 找不到
（这个 key 还没加），或者底边越过了 `h − 96`。**三条都必须先跑一遍看清实际输出，不许跳过。**

- [ ] **Step 3: 实现三支 + 让位**

`lib/features/calendar/calendar_screen.dart` 的 `build()`，现在这一段是：

```dart
          final layout = AppLayout.of(context);
          final gridArea = Expanded(child: LayoutBuilder(…));

          return Column(
            children: [
              _header(context),
              if (layout.isWide)
                Expanded(child: Row(children: [gridArea, gap, SizedBox(width: 300, child: SingleChildScrollView(child: _infoCard(…, inSidePane: true)))]))
              else ...[
                if (!layout.isShort) gridArea,
                _infoCard(context, chain, compact: layout.isShort),
              ],
            ],
          );
```

改成下面这版。**四处改动**：① `final gridArea = Expanded(…)` 加一个 key、改名成 `grid`；
② `if` 拆成**三支**；③ 右栏那个 `SizedBox` 加一个 key；
④ **`_header` 从最外层挪进「哪一支」里** —— 宽横屏那一支它要进左栏，
不挪的话它会在页顶**多画一份**。所以整页变成一个「先算 `body` 再返回」的形状：

```dart
    final layout = AppLayout.of(context);
    // ① 现在 gridArea 那一整段原样搬过来，只加一个 key、改个名。
    final grid = Expanded(
      key: const Key('calendar-grid'),
      child: LayoutBuilder(/* …原样… */),
    );

    // ③ 宽屏两支共用的右栏。`info-rail` 那个 key 是 Task 4 的几何抓手。
    Widget rail() => SizedBox(
          key: const Key('info-rail'),
          width: _railWidth(layout),
          child: _sideRail(context, chain),
        );

          // **三支，不是两支。**
          //   · 宽横屏（平板 / 车机）→ Task 3/4 会把它改成新版式（顶栏进左栏、卡片贴右下）；
          //   · 宽且矮（手机横屏）  → **今天的版式原样保留**，只多一层让位；
          //   · 其余                → 竖屏版式，一个像素不动。
          // ⚠️ 第二支存在的唯一理由：把分栏判据换成 `isWideLandscape` 之后，
          // 900×420 会掉进竖屏那一支、被 `if (!layout.isShort)` 删掉网格。
          final Widget body;
          if (layout.isWideLandscape) {
            // ④ 顶栏在**左栏里面**（与网格一起），整页只有这一块。
            body = Padding(
              padding: const EdgeInsets.only(bottom: kNavCapsuleInset),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(children: [_header(context), grid])),
                  const SizedBox(width: AppTokens.spaceMd),
                  rail(),
                ],
              ),
            );
          } else if (layout.isWide) {
            body = Column(children: [
              _header(context),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: kNavCapsuleInset),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      grid,
                      const SizedBox(width: AppTokens.spaceMd),
                      rail(),
                    ],
                  ),
                ),
              ),
            ]);
          } else {
            body = Column(children: [
              _header(context),
              if (!layout.isShort) grid,
              _infoCard(context, chain, compact: layout.isShort),
            ]);
          }
          return body;
```

⚠️ 注意竖屏那一支**逐字等于今天**（`_header` + `grid` + 信息卡），
唯一的形式差别是 `gridArea` 改名叫 `grid`、多了一个 key —— 两者都不影响渲染。
**交付前用 `scripts/diff_visual.py` 逐张比一遍竖屏基线确认。**

并在同一个 State 类里加两个私有成员：

```dart
  /// 宽屏右栏的宽度：按屏宽取比例，再夹在 280~340。
  ///
  /// 为什么不是写死 300（本版之前的做法）：720/800 这种刚过线的宽度上，
  /// 写死 300 会把左栏挤到 360（格子 48dp）；比例 + 上下限在小屏上收窄右栏、
  /// 把宽度让给日历。
  double _railWidth(AppLayout layout) =>
      (layout.availableWidth * 0.27).clamp(280.0, 340.0);

  /// 宽屏右栏里的今日信息卡。
  ///
  /// 用的是 `inSidePane: true` 那条路（卡片高度交给内容，见 `_infoCard`）。
  /// ⚠️ **这一步先照搬今天的写法（顶对齐 + 能滚）**，Task 4 才把它推到底部 ——
  /// 一次只改一件事，Task 4 那条用例才有红转绿可言。
  Widget _sideRail(BuildContext context, ScheduleChain? chain) =>
      SingleChildScrollView(child: _infoCard(context, chain, inSidePane: true));
```

`kNavCapsuleInset` 已经在 `core/layout.dart` 里、`calendar_screen.dart` 也已经 import 了它。

- [ ] **Step 4: 跑用例，确认通过（含全套日历用例）**

Run: `flutter test test/calendar_screen_test.dart`
Expected: 全 PASS。**特别确认「手机横屏」那条仍然是绿的**（它证明第二支没写漏）。

- [ ] **Step 5: 跑一遍竖屏基线，确认一张没变**

Run: `flutter test test/calendar_screen_test.dart test/info_card_fit_test.dart test/calendar_header_fit_test.dart`
Expected: 全 PASS —— 这三份是竖屏版式最密的护栏。

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_screen_test.dart
git commit -m "feat(calendar): 分栏改成三支，两支宽屏都让开底部胶囊"
```

---

### Task 3: 宽横屏的顶栏收进左栏、内容不再被拉伸

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`（`_header`，约 872-1013 行）
- Test: `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 的左栏结构（`Column(children: [_header(context), grid])`）
- Produces: 一行档在宽横屏下多一个分支；`Key('header-single-row')` 在宽横屏下**仍然存在**（沿用同一个 key，只是内部布局变了）。

- [ ] **Step 1: 写失败的用例**

```dart
  testWidgets('宽横屏：顶栏收在左栏里、年月胶囊不再被拉伸', (tester) async {
    await _pumpCalendar(tester, 'six_crew_three_shift',
        width: 1280, height: 800);

    // ① 顶栏整块在左栏里 —— 它的右缘不超过信息卡的左缘。
    final header = tester.getRect(find.byKey(const Key('header-single-row')));
    final card = tester.getRect(find.byKey(const Key('info-card-panel')));
    expect(header.right, lessThanOrEqualTo(card.left),
        reason: '顶栏右缘 ${header.right} 越到了信息卡（${card.left}）那边');

    // ② 年月那一行按内容收缩，不再撑满它拿到的宽度。
    //    判据：内层 Row 明显比外层的 Padding 窄 —— 从前 `Expanded` 撑着时两者等宽。
    final row = tester.getRect(find.descendant(
        of: find.byKey(const Key('header-single-row')),
        matching: find.byType(Row)));
    expect(row.width, lessThan(header.width - 100),
        reason: '内层 Row ${row.width} 与外层 ${header.width} 几乎等宽 —— 年月还在被撑开');
  });
```

- [ ] **Step 2: 跑一遍，确认它失败**

Run: `flutter test test/calendar_screen_test.dart -n 顶栏收在左栏`
Expected: FAIL —— ② 那条报「几乎等宽」（`Expanded` 还在撑）。

- [ ] **Step 3: 实现**

`_header` 里，把现在「一行档」那个 `return Padding(key: Key('header-single-row'), ...)`
整段**替换**成下面这版（控件、图标、`L10n` 全部沿用原样，**只改两处**：外层 Row 的
`mainAxisSize`，以及年月胶囊外面那层 `Expanded`）：

```dart
    final wide = AppLayout.of(context).isWideLandscape;
    // 年月胶囊：宽横屏下**不套 `Expanded`** —— 套着它就会拿到多宽撑多宽，
    // 1280 的屏上那是一条 1600px 的长条（用户 2026-10-13 报的「顶栏太长」）。
    final monthPill = GlassPill(
      onTap: _showMonthPicker,
      child: _monthSlide(
        month: _month,
        tag: 'pill',
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(L10n.yearMonth(_month),
              maxLines: 1, style: AppTokens.titleStrong),
        ),
      ),
    );

    return Padding(
      // 宽横屏沿用同一个 key：它仍然是「一行档」，只是排布不同。
      key: const Key('header-single-row'),
      padding: pad,
      child: Row(
        // 宽横屏：整行收缩到内容宽度 → 靠左；其余档位照旧撑满整行。
        mainAxisSize: wide ? MainAxisSize.min : MainAxisSize.max,
        children: [
          _circleIcon(
              context, Icons.chevron_left_outlined, L10n.prevMonth, _prev),
          const SizedBox(width: AppTokens.gapIconText),
          if (wide) monthPill else Expanded(child: monthPill),
          const SizedBox(width: AppTokens.gapIconText),
          _circleIcon(
              context, Icons.chevron_right_outlined, L10n.nextMonth, _next),
          const SizedBox(width: AppTokens.gapIconText),
          _circleIcon(context, Icons.timeline, L10n.scheduleTimeline, _showTimeline),
          const SizedBox(width: AppTokens.gapIconText),
          GlassPill(
            onTap: _today,
            accent: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(Icons.today_outlined,
                    size: AppTokens.iconMd, color: Colors.white),
                if (!AppLayout.of(context).isNarrow) ...[
                  const SizedBox(width: 4),
                  Text(L10n.today,
                      style: AppTokens.labelStrong
                          .copyWith(color: Colors.white.withValues(alpha: 0.98))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
```

⚠️ **两行档（`!_oneRowFits`）那一段不动** —— 宽横屏在它之前就返回了，永远走不到它。

- [ ] **Step 4: 跑用例，确认通过**

Run: `flutter test test/calendar_screen_test.dart test/calendar_header_fit_test.dart`
Expected: 全 PASS。`calendar_header_fit_test.dart` 是顶栏那套最密的护栏
（一行 / 两行怎么选），它必须一条都没红。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_screen_test.dart
git commit -m "feat(calendar): 宽横屏下顶栏收进左栏、年月胶囊不再被拉伸"
```

---

### Task 4: 宽横屏的右栏：卡片贴到右下角

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`（`_sideRail`，Task 2 建的那个）
- Test: `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `_sideRail` / `_railWidth`
- Produces: 无新接口。

- [ ] **Step 1: 写失败的用例**

```dart
  testWidgets('宽横屏：今日卡贴在右下角，且右栏宽度跟着屏宽走', (tester) async {
    await _pumpCalendar(tester, 'six_crew_three_shift',
        width: 1280, height: 800);

    final rail = tester.getRect(find.byKey(const Key('info-rail')));
    final card = tester.getRect(find.byKey(const Key('info-card-panel')));

    // ① **贴底**：卡片下方只剩这一栏自己的 16 内边距。从前是顶对齐，
    //    卡片底下会空出几百 dp（用户报的「一小块缩在右上角」）。
    expect(rail.bottom - card.bottom, lessThanOrEqualTo(20),
        reason: '卡片底边离右栏底部还有 ${rail.bottom - card.bottom} —— 它还没贴底');
    // ② 卡片水平方向在这一栏里。
    expect(card.left, greaterThanOrEqualTo(rail.left - 0.5));
    expect(card.right, lessThanOrEqualTo(rail.right + 0.5));
    // ③ 右栏宽 = (1280 × 0.27).clamp(280, 340) = 340。
    expect(rail.width, closeTo(340, 0.5));

    await _disposeCalendar(tester);

    // ④ 1024 那一档：0.27 × 1024 = 276.5 → 夹到下限 280。
    await _pumpCalendar(tester, 'six_crew_three_shift',
        width: 1024, height: 600);
    expect(tester.getSize(find.byKey(const Key('info-rail'))).width,
        closeTo(280, 0.5));
  });

  testWidgets('宽横屏右栏装不下时自己滚，不溢出', (tester) async {
    // 车机上用户开着「特大」字号：六班组那种最满的信息卡会高过这一栏。
    // 期望是**这一栏自己滚**，而不是 BOTTOM OVERFLOWED（`_pumpCalendar` 外面的
    // `failOnOverflow` 会当场抓到溢出）。卡片仍贴在这一栏的底边。
    await _pumpCalendar(tester, 'six_crew_three_shift',
        width: 1024, height: 600);
    final rail = tester.getRect(find.byKey(const Key('info-rail')));
    final card = tester.getRect(find.byKey(const Key('info-card-panel')));
    expect(rail.bottom - card.bottom, lessThanOrEqualTo(20));
  });
```

- [ ] **Step 2: 跑一遍，确认它失败**

Run: `flutter test test/calendar_screen_test.dart -n 今日卡贴在右下角`
Expected: FAIL —— ① 那条报卡片底边远在下方之上（现在还是顶对齐）。

- [ ] **Step 3: 实现**

把 Task 2 建的 `_sideRail` 从「顶对齐 + 能滚」改成「**贴底 + 不富余时自己滚**」：

```dart
  /// 宽屏右栏里的今日信息卡。
  ///
  /// 用的是 `inSidePane: true` 那条路（卡片高度交给内容，见 `_infoCard`）。
  ///
  /// **卡片推到底**（用户 2026-10-13：「就算是一小块，也得放在右下角吧」）：
  /// `ConstrainedBox(minHeight: 视口高)` 撑满这一栏，`Column(end)` 再把卡片压到底边。
  /// 有富余时这一层什么都不做（列高 = 视口高，卡片贴底）；**没富余时**（车机上开着
  /// 特大字号、六班组那种最满的卡片）列会长过视口，于是**这一栏自己滚** ——
  /// 外层的 `SingleChildScrollView` 就是这个兜底，别把它写成
  /// `NeverScrollableScrollPhysics`，那样会直接溢出成黄黑条纹。
  ///
  /// ⚠️ 这一栏**不是「面板套滚动」**（AGENTS.md 禁的是面板里再套一层滚动）：它是一个
  /// 布局列，卡片本身在 `inSidePane` 那条路上仍然是「高度交给内容」的。
  Widget _sideRail(BuildContext context, ScheduleChain? chain) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [_infoCard(context, chain, inSidePane: true)],
            ),
          ),
        ),
      );
```

- [ ] **Step 4: 跑用例，确认通过**

Run: `flutter test test/calendar_screen_test.dart -n 宽横屏`
Expected: 全 PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_screen_test.dart
git commit -m "feat(calendar): 宽横屏下今日卡贴到右下角，右栏宽度按屏宽取比例"
```

---

### Task 5: 格子字号的上限按档位取

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`（`_cellMaxScale` 常量约 2893 行、`_dayCell` 约 1782 行）
- Test: `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: `AppLayout.isWide`（既有）
- Produces: 顶层函数 `double cellMaxScale(AppLayout layout)` —— 公开可测，与 `calendarCellHeight` 同一套路。

- [ ] **Step 1: 写失败的用例**

```dart
  test('格子字号上限按档位取：宽屏 1.7、其余 1.25', () {
    AppLayout at(double w, double h) => AppLayout(
        isNarrow: w < 360, isShort: h < 480, isWide: w >= 720,
        isWideLandscape: w >= 720 && h >= 480 && w > h,
        availableWidth: w, availableHeight: h);
    expect(cellMaxScale(at(420, 900)), 1.25);
    expect(cellMaxScale(at(200, 400)), 1.25);
    expect(cellMaxScale(at(1280, 800)), 1.7);
    expect(cellMaxScale(at(1920, 720)), 1.7);
    // ⚠️ 判据是 `isWide`（不是 `isWideLandscape`）：竖着的平板也吃到宽屏上限。
    expect(cellMaxScale(at(800, 1280)), 1.7);
    // 宽且矮那一档格子只有 41dp 高，上限根本不生效 —— 给它宽屏值只是少一个分支。
    expect(cellMaxScale(at(900, 420)), 1.7);
  });

  testWidgets('宽横屏下格子里的字真的更大', (tester) async {
    await _pumpCalendar(tester, 'six_crew_three_shift',
        width: 1280, height: 800);
    final wide = tester.getSize(find.descendant(
        of: find.byKey(const ValueKey('day-card-13')),
        matching: find.text('13')));
    await _disposeCalendar(tester);

    await _pumpCalendar(tester, 'six_crew_three_shift');
    final phone = tester.getSize(find.descendant(
        of: find.byKey(const ValueKey('day-card-13')),
        matching: find.text('13')));

    // 字号是按 `s` 乘上去的，而格子里的 `FittedBox` 给子件的是**无界约束**
    // （缩放只改变绘制），所以这里量到的就是「按 s 排出来的自然尺寸」。
    expect(wide.height / phone.height, greaterThan(1.15),
        reason: '宽屏 ${wide.height} vs 手机 ${phone.height} —— 字没跟着档位长');
  });
```

- [ ] **Step 2: 跑一遍，确认它失败**

Run: `flutter test test/calendar_screen_test.dart -n 格子字号上限`
Expected: 编译失败 —— `The function 'cellMaxScale' isn't defined`。

- [ ] **Step 3: 实现**

`lib/features/calendar/calendar_screen.dart`：

1. 在 `const double _cellMaxScale = 1.25;`（约 2893 行）**旁边**加一个新常量
   （**别给旧的改名**：`_cellMaxScale` 这个私有名在文件里只被下面那个函数用到，
   改名只会制造无关 diff）：

```dart
/// 宽屏档（`AppLayout.isWide`）的格子字号上限。
///
/// **为什么宽屏要放开**：格子内容按 `(cellH − 内缩) / _cellDesignH(55)` 等比缩放、
/// 再夹上限。车机上 cellH ≈ 90~120，`(104 − 12) / 55 ≈ 1.67` —— 1.25 那道天花板
/// 早就顶到了，于是「调大字号 / 屏幕更大」都不再让字变大（用户 2026-10-13 报的
/// 第 5 条）。1.7 让内容占到格子的约 78%，仍有呼吸。
///
/// **判据取 `isWide` 而不是 `isWideLandscape`**：宽且矮那一支格子只有 41dp 高，
/// 上限根本不生效，多一个分支只是多一处要维护的东西。
///
/// ⚠️ **这是起手值**（照 1920×720 上 cellH≈90 反推的），出图之后可能还要回来调。
const double _cellMaxScaleWide = 1.7;

/// 格子内容的缩放上限，按档位取（见上面两个常量的说明）。
///
/// 抽成顶层纯函数（公开）是为了能直接断言「按档位分叉」——
/// 与 [calendarCellHeight] 同一个理由。
double cellMaxScale(AppLayout layout) =>
    layout.isWide ? _cellMaxScaleWide : _cellMaxScale;
```

2. `_dayCell` 里那一行：

```dart
    final s =
        ((cellH - _cellInset * 2) / _cellDesignH).clamp(1.0, _cellMaxScale);
```

改成：

```dart
    final s = ((cellH - _cellInset * 2) / _cellDesignH)
        .clamp(1.0, cellMaxScale(AppLayout.of(context)));
```

- [ ] **Step 4: 跑用例，确认通过**

Run: `flutter test test/calendar_screen_test.dart`
Expected: 全 PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_screen_test.dart
git commit -m "feat(calendar): 宽屏档放开格子字号上限（1.25 → 1.7）"
```

---

### Task 6: 底部导航胶囊限宽

**Files:**
- Modify: `app/lib/core/layout.dart`（加常量）、`app/lib/features/home/glass_nav_bar.dart`（`build()` 约 212-257 行、两棵树里那个胶囊 `Container`）
- Test: `app/test/glass_tier_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `kNavCapsuleMaxWidth`（`core/layout.dart` 的公开常量）、`Key('nav-capsule')`。

- [ ] **Step 1: 写失败的用例**

追加到 `test/glass_tier_test.dart`（`pumpShell(tester, liquid:, size:)` 与
`disposeShell` 都已存在）：

```dart
  testWidgets('底栏胶囊有宽度上限：宽屏不再摊到屏幕两端', (tester) async {
    // 420 竖屏：**逐像素级不变** —— 上限比它宽，约束不该生效。
    await pumpShell(tester, liquid: false, size: const Size(420, 900));
    expect(tester.getSize(find.byKey(const Key('nav-capsule'))).width,
        closeTo(372, 0.5));
    await disposeShell(tester);

    // 1280 车机：1232 → 440。
    await pumpShell(tester, liquid: false, size: const Size(1280, 800));
    expect(tester.getSize(find.byKey(const Key('nav-capsule'))).width,
        closeTo(kNavCapsuleMaxWidth, 0.5));
    await disposeShell(tester);

    // 1920 超宽车机：同样夹在 440。
    await pumpShell(tester, liquid: false, size: const Size(1920, 720));
    expect(tester.getSize(find.byKey(const Key('nav-capsule'))).width,
        closeTo(kNavCapsuleMaxWidth, 0.5));
    await disposeShell(tester);

    // ⚠️ **液态档那棵树也要一起查**：两棵树各自建胶囊，只在一棵里加约束的话，
    // 开着液态玻璃的用户看到的是「限宽没生效」，而上面三条全绿。
    await pumpShell(tester, liquid: true, size: const Size(1280, 800));
    expect(tester.getSize(find.byKey(const Key('nav-capsule'))).width,
        closeTo(kNavCapsuleMaxWidth, 0.5));
    await disposeShell(tester);
  });

  testWidgets('限宽之后点第 4 格仍然切到第 4 页', (tester) async {
    // 限宽把 `LayoutBuilder` 算出的 `itemW` 改了（1232/4 → (440 − 内边距)/4）。
    // 点按坐标必须仍然对得上 —— 判据照本文件既有的写法，读 `PageController.page`。
    await pumpShell(tester, liquid: false, size: const Size(1280, 800));
    final cap = tester.getRect(find.byKey(const Key('nav-capsule')));
    await tester.tapAt(Offset(cap.left + cap.width * 0.88, cap.center.dy));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    final c = tester.widget<PageView>(find.byType(PageView)).controller!;
    expect(c.page!.round(), 3, reason: '点了第 4 格却没切到第 4 页 —— 限宽之后坐标没跟着走');
    await disposeShell(tester);
  });
```

- [ ] **Step 2: 跑一遍，确认它失败**

Run: `flutter test test/glass_tier_test.dart -n 宽度上限`
Expected: 编译失败（`kNavCapsuleMaxWidth` / `nav-capsule` 未定义）。

- [ ] **Step 3: 实现**

**① `core/layout.dart`**：在 `kNavCapsuleInset` 旁边加：

```dart
/// 底部导航胶囊的**宽度上限**。
///
/// 胶囊原来只有左右各 `outerPad` 的外边距、没有上限，于是 1920 的车机上四个 tab
/// 摊开 1900px（用户 2026-10-13 报的「被拉太长」）。440 ≈ **手机那一条的宽度**
/// （420 宽的屏上是 372），四个 tab 各 110dp，比手机上的 93dp 还宽一点。
///
/// **窄屏上它必须是不生效的**：约束取 `kNavCapsuleMaxWidth + outerPad × 2` 与可用宽
/// 的较小值，420/320/200 各档都拿不到更小的数 —— 那几档逐像素不变。
const double kNavCapsuleMaxWidth = 440;
```

**② `glass_nav_bar.dart` 的 `build()`**：把现在直接 `return ValueListenableBuilder<bool>(…)`
改成先算上限、再包一层：

```dart
    // 胶囊的宽度上限要在**外面**加：胶囊本体外面还套着 `Padding(horizontal: outerPad)`，
    // 约束加在里面的话，实际宽度会变成 440 − 48 = 392。
    final maxOuter = kNavCapsuleMaxWidth + outerPad * 2;

    return Center(
      // `heightFactor: 1.0`：高度照旧收缩到胶囊高（`Scaffold` 的底部栏槽位给的是
      // 松高度约束，不写它 `Center` 会去够无穷大）。
      heightFactor: 1.0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxOuter),
        child: ValueListenableBuilder<bool>(/* …原样… */),
      ),
    );
```

**③ 两棵树里那个胶囊 `Container(height: capsuleH, decoration: …)` 各加一个 key**：

```dart
                    key: const Key('nav-capsule'),
```

（`_buildStandard` 与 `_buildLiquid` 各一处，`Container` 的 `height:` 就在它们里面。）

- [ ] **Step 4: 跑用例，确认通过**

Run: `flutter test test/glass_tier_test.dart test/home_shell_nav_test.dart`
Expected: 全 PASS。**`home_shell_nav_test` 必须一条都不红** —— 它靠
`getRect(Key('glass-nav-bar'))` 算点按坐标，而那个 key 的量出来的矩形
本来就是**整屏宽**（探针实测：420 下单是 `[0, 420]`），外面的 `Center` 不改它。

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/layout.dart app/lib/features/home/glass_nav_bar.dart app/test/glass_tier_test.dart
git commit -m "feat(nav): 底部导航胶囊限宽 440，宽屏不再摊到屏幕两端"
```

---

### Task 7: 待办页那颗悬浮「＋」跟着内容栏走

**Files:**
- Modify: `app/lib/features/schedule/schedule_screen.dart`（`_AboveCapsuleFabLocation`，约 886-894 行）
- Test: `app/test/recurring_screen_test.dart`

**Interfaces:**
- Consumes: `AppLayout.maxContentWidth`（既有常量 720）
- Produces: 无新接口。

- [ ] **Step 1: 写失败的用例**

`recurring_screen_test.dart` 的 `mount` 现在写死 `Size(420, 1200)`；先给它加一个可选参数：

```dart
  Future<void> mount(WidgetTester tester, {Size size = const Size(420, 1200)}) async {
    tester.view.physicalSize = size;
```

再追加一条用例：

```dart
  testWidgets('宽屏下「＋」按钮跟着内容栏走，手机上位置不变', (tester) async {
    await repo.addEvent(title: '甲', date: dateOnly(DateTime.now()));

    // ① 手机：与 `endFloat` 一模一样（右缘 = 屏宽 − 标准边距 16）。
    await mount(tester);
    final phone = tester.getRect(find.byKey(const Key('todo-fab')));
    expect(phone.right, closeTo(420 - 16, 0.5));
    await _dispose(tester);

    // ② 1280 车机：正文被 `CenteredContent` 限宽 720 居中，
    //    它右移的那一段 =（1280 − 720）/ 2 = 280。
    await mount(tester, size: const Size(1280, 800));
    final wide = tester.getRect(find.byKey(const Key('todo-fab')));
    expect(phone.center.dx - wide.center.dx, closeTo(280, 0.5),
        reason: '「＋」没跟着 720 的内容栏走（差值 ${phone.center.dx - wide.center.dx}）');
    await _dispose(tester);
  });
```

（文件顶部不需要新 import —— 这条用例不引用 `AppLayout`。
`Key('todo-fab')` 由下面的 Step 3 加上。）

- [ ] **Step 2: 跑一遍，确认它失败**

Run: `flutter test test/recurring_screen_test.dart -n 跟着内容栏`
Expected: FAIL —— ② 那条报 `wide.right` 约 1208，期望 984。

- [ ] **Step 3: 实现**

**① 给那颗按钮加一个 key**（`schedule_screen.dart` 的 `floatingActionButton:` 那个
`Container(width: 56, height: 56, …)`，约 203 行）：

```dart
      floatingActionButton: Container(
        key: const Key('todo-fab'),
        width: 56,
```

**② 改落点**：把 `_AboveCapsuleFabLocation.getOffset` 换成：

```dart
  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final base = FloatingActionButtonLocation.endFloat.getOffset(geometry);
    // 宽屏下正文被 `CenteredContent` 限宽到 720 并居中，FAB 跟着**内容栏的右缘**走，
    // 不然它孤零零挂在屏幕右缘、与列表对不上（用户 2026-10-13 选「一起做了」）。
    //
    // 用**平移**而不是重算边距：`base.dx` 已经是「屏幕右缘 − 按钮宽 − 标准边距」，
    // 减掉两侧各让出来的那一段就等价于「内容栏右缘 − 按钮宽 − 标准边距」——
    // 于是不必知道 Flutter 那个边距常量是多少，手机上 `extra` 恒为 0、逐像素不变。
    final contentW = math.min(AppLayout.maxContentWidth, geometry.scaffoldSize.width);
    final extra = (geometry.scaffoldSize.width - contentW) / 2;
    return Offset(base.dx - extra, base.dy - 76);
  }
```

并在文件顶部加 `import 'dart:math' as math;`（现在没有）。

- [ ] **Step 4: 跑用例，确认通过**

Run: `flutter test test/recurring_screen_test.dart test/todo_archive_screen_test.dart`
Expected: 全 PASS —— 后一份里那条「删除键不被 FAB 挡住」的几何用例必须仍然绿。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/schedule/schedule_screen.dart app/test/recurring_screen_test.dart
git commit -m "feat(todo): 宽屏下「＋」按钮跟着 720 内容栏走"
```

---

### Task 8: 工装宽屏档 + 基线比对 + 版本号 / 更新日志

**Files:**
- Modify: `app/tool/visual/render_screens_test.dart`（新增一个宽屏循环，照 `xl360` / `xl320` 那两个循环的写法）
- Modify: `app/pubspec.yaml`、`app/lib/core/app_info.dart`、`app/lib/features/profile/app_dialogs.dart`
- Delete: `app/tool/probe/landscape_probe_test.dart`、`app/tool/probe/nav_rect_probe_test.dart`

**Interfaces:**
- Consumes: Task 1~7 的全部改动
- Produces: 无。

- [ ] **Step 1: 加工装宽屏档**

`render_screens_test.dart` 里，照 `for (final cfg in const <({String suffix, Size size})>[…])`
那一段的写法新增一组（**放在它后面**）：

```dart
  // 「宽横屏」（平板 / 车机）。**不做成 `visualVariants` 的新变体** —— 那会给
  // 39 屏各加两档（+78 张），而真正需要人眼的只有这六屏。
  for (final cfg in const <({String suffix, Size size})>[
    (suffix: 'wide', size: Size(1280, 800)),
    (suffix: 'car', size: Size(1920, 720)),
  ]) {
    for (final slug in const <String>[
      '00_home_shell',
      '01_calendar',
      '05_todos',
      '06_alarm',
      '07_profile',
      '02_editor',
    ]) {
      final screen = visualScreens.firstWhere((s) => s.slug == slug,
          orElse: () => throw StateError('屏单里没有 $slug —— 屏改名了？'));
      visualTest('${screen.title} · ${cfg.suffix}', (tester) async {
        failOnOverflow(tester);
        final db = await freshDb();
        final extraPrefs = <String, Object>{
          ...(screen.needsOnboardingPrefs ? onboardingPrefs : const {}),
          ...screenExtraPrefs(screen.slug),
        };
        if (extraPrefs['liquidGlass'] == true) useLiquidGlassTier();
        await renderScreen(
          tester,
          name: '${screen.slug}_${cfg.suffix}',
          home: await screen.build(db),
          overrides: <Override>[databaseProvider.overrideWithValue(db)],
          size: cfg.size,
          extraPrefs: extraPrefs,
        );
      });
    }
  }
```

- [ ] **Step 2: 跑工装，出图**

Run: `flutter test tool/visual/render_screens_test.dart`
Expected: 全 PASS，`app/build/visual/` 下多出 `*_wide.png` / `*_car.png` 共 12 张。

- [ ] **Step 3: 看图（这一步不许跳）**

逐张看那 12 张新图，对着 spec §3 的草图核：
顶栏是否收在左栏、年月胶囊是否没被拉伸、今日卡是否贴在右下角、
网格最后一行是否完整落在底部（对照 `*_car` 里胶囊的位置）、
格子里的字是否明显比手机版大。

- [ ] **Step 4: 与基线逐张比，确认竖屏一张没变**

先在 Task 1 之前的状态上另开一个 worktree 渲一遍当基线（仓库惯例：
`git worktree add ../base <改动前的 commit>` → 在那边跑一次 `flutter test tool/visual/render_screens_test.dart`），
再用 `scripts/diff_visual.py` 比两边的产物。

Run: `python scripts/diff_visual.py <基线目录> app/build/visual`
Expected（spec §5）：**竖屏那几档（`light` / `dark` / `en` / `xl360` / `xl320` / `small`）
一张都不在差异名单里**；差异只该出现在 `*_landscape`（900×420，胶囊限宽 + 日历让位 +
待办 FAB 左移）与新增的 `*_wide` / `*_car` 上。

> 若某个竖屏档出现在名单里，**停下来查**，不要放过 —— 那是回归。

- [ ] **Step 5: 删掉一次性探针**

```bash
rm app/tool/probe/landscape_probe_test.dart app/tool/probe/nav_rect_probe_test.dart
```

（`app/tool/probe/` 是 gitignore 的（`.gitignore:53`），探针不会进提交；
`build/mockups/` 在 gitignore 的 `build/` 下，也不用管。删探针纯粹是仓库惯例。）

- [ ] **Step 6: 改版本号与更新日志**

- `app/pubspec.yaml`：`version: 0.11.13+160` → `version: 0.11.14+161`
- `app/lib/core/app_info.dart`：`const String appVersion = '0.11.13';` → `'0.11.14'`
- `app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh` / `_changelogEn`：
  **prepend** 一条 v0.11.14、删掉最旧一条（窗口恒 10 条）。测试版条目**原样写自己这版改了什么**
  （不做归纳 —— 归纳只发生在正式版），并且**不许出现任何 markdown 标记**
  （`changelog_window_test.dart` 盯着这条）。中文条目草稿：

  > 0.11.14 · 横屏（平板 / 车机）重新适配：日历页在横屏下改成左右两栏 —— 顶栏收进左栏、
  > 今日卡贴到右下角、日期网格不再被底部胶囊压住、格子里的字跟着格子变大；
  > 底部导航胶囊在宽屏上不再摊满整屏。竖屏与手机横屏的版式一个字没动。

  （英文条目照同一段意思写，风格对齐现有条目。）

- [ ] **Step 7: 全量验收**

```bash
cd app
flutter analyze                      # 0 error / 0 warning
flutter test                         # 全绿，条数 ≥ 933 + 本计划新增
flutter test tool/visual/            # 工装全绿
```

- [ ] **Step 8: 提交 + 打 tag + 发布**

```bash
git add -A
git commit -m "chore(release): v0.11.14 —— 横屏（平板 / 车机）重新适配"
git push origin beta
git tag v0.11.14 && git push origin v0.11.14
```

发布说明先写到 `tools/gh/release-notes-v0.11.14.md`，再跑：

```bash
scripts/release.ps1 -SkipConfirm
```

发完 **curl 一次 main 上的 `latest.json`** 核对版本号（脚本第 7b 步只告警、不影响发布本身；
不过它若失败，主更新通道会停在旧版本）。

---

## 附：本计划刻意不做的

- 不给另外三个 tab 重排版式（它们已经 `CenteredContent(720)` 限宽居中，出图核过没有坏掉的地方）。
- 不做竖屏平板的专门版式（走竖屏那套）。
- 不动 `CenteredContent` 的 720。
- 不碰原生 Kotlin / 桌面小组件 / 数据层。
