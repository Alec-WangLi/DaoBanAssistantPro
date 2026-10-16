# 今日卡片贴齐 App（通高竖条 + 其他班组胶囊）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让桌面今日信息卡的两处观感追上 App：左边主色竖条通高，其他班组套上半透明胶囊并紧挨左排。

**Architecture:** 纯原生侧改动（Kotlin + 两张布局 XML），快照协议 v2 与 Dart 侧一字不动。竖条靠把 `widget_today_card.xml` 根换成 FrameLayout、把通高条叠在内容左边；胶囊复用 `WidgetChip.tintedChip`（它已是 App 的「14% 淡染 + 45% 描边」配方），宽度用 `Paint.measureText` 现量、左排靠把四个槽位从等宽改成自然宽。

**Tech Stack:** Kotlin（RemoteViews / Paint.measureText / WidgetChip 位图）、Android 布局 XML、Dart 测试护栏（`flutter test` 扫源码）。

**Spec:** `docs/superpowers/specs/2026-10-16-today-card-parity-design.md`

## Global Constraints

- Kotlin 里**不许出现用户可见的中文字面量**（所有文案来自 Dart 快照；注释可以写中文）。
- 字号/间距**只从 App 令牌同源取值**，不在 Kotlin 另抄一份常量（已有 `widget_today_card_guard_test.dart` 把「其他班组」字号钉在 `microText`）。
- 测试版（末位 `Z≠0`）在 `beta` 分支；版本号只动 `Z` 与 `build`（`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 同步，由 `app_info_test.dart` 盯）。
- 快照协议仍是 v2，**不新增字段**；不改周条 / 月历两张卡。
- 本轮改的两张布局（`widget_today_card.xml`、`widget_crew_chip.xml`）都是**嵌套 RemoteViews**——渲染侧每次都 `removeAllViews` + `addView`，所以每次渲染都重新 inflate，**改动立刻生效、无需 force-stop 桌面**（v0.11.25 那条「外层布局要重启桌面」只对外层壳 `widget_today_standalone.xml` / `widget_week_strip.xml` 成立，这两张是外层壳里的嵌套内容）。
- 只跑 `flutter analyze`，**不跑 `dart format`**。

## Review Focus

1. **4 个班组时第 4 颗胶囊溢出被裁** —— 用户拍板「接受省略」；预期是第 4 颗在卡片右缘被裁掉、不把整行挤崩、不报错。→ Task 2 的「5 班组出图」步骤。
2. **竖条 `match_parent` 高度在 `wrap_content` 的 FrameLayout 里塌成 0**（Android 经典坑，竖条会变成一根看不到的细线或消失）。→ Task 1 的「真机通高量测」步骤。
3. **竖条位图 `fitXY` 拉伸后两端圆头变椭圆**（6dp 宽、半径 3dp，位图烤 200dp 高、真实 ~168dp）。→ Task 1 的「真机目视圆头」步骤。
4. **胶囊位图宽与布局 TextView 实际宽不一致**（`measureText` 的字体度量误差，导致胶囊比文字窄被裁、或宽出空隙）。→ Task 2 的「真机胶囊贴字」步骤。
5. **左排后标签与首颗、胶囊之间的间距与 App 不同量级**（左排了但间隙忽大忽小，读起来不整齐）。→ Task 2 的「真机并排比」步骤。

---

### Task 1: 竖条通高

**Files:**
- Modify: `app/android/app/src/main/res/layout/widget_today_card.xml`（根换 FrameLayout、竖条改通高、日期行去掉 4×24 条）
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`（`renderTodayCard` 里 `wg_tc_bar` 位图 4×24 → 6×200）
- Test: `app/test/widget_today_card_guard_test.dart`

**Interfaces:**
- Consumes: `WidgetChip.bar(color: Int, wPx: Int, hPx: Int): Bitmap`（圆头胶囊，`radiusPx = wPx/2`，已存在，不改）。
- Produces: 无新函数。`wg_tc_bar` 的位图尺寸变为 6dp × 200dp；`widget_today_card.xml` 根结构变为 `FrameLayout[内容列(marginStart 20dp), wg_tc_bar(6dp×match_parent, gravity start)]`。

- [ ] **Step 1: 写失败测试 —— 竖条是全高的，不是日期行里的 4×24**

在 `widget_today_card_guard_test.dart` 加一条 `test('竖条通高：6dp 宽、match_parent 高、贴左，不再住在日期行里', ...)`：

```dart
test('竖条通高：根是横向 LinearLayout，竖条 6dp 宽、match_parent 高', () {
  final xml = _read('android/app/src/main/res/layout/widget_today_card.xml');
  // 根是**横向** LinearLayout —— 竖条贴左、内容列占满剩余宽，竖条 match_parent 高才能
  // 被二次测量成内容列高（FrameLayout 只量一次、match_parent 会解析成位图自己的高）。
  // 根是文件里第一个 <LinearLayout>（头注释之后）。
  final rootStart = xml.indexOf('<LinearLayout');
  final rootBlock = xml.substring(rootStart, xml.indexOf('>', rootStart));
  expect(rootBlock.contains('orientation="horizontal"'), true,
      reason: '根不是横向 LinearLayout —— 竖条 match_parent 高不会被量成内容高（FrameLayout/垂直 LinearLayout 都做不到）');
  // 竖条那一层：从 id 截到自闭合，免得匹配到别的视图。
  final bar = xml.indexOf('@+id/wg_tc_bar');
  expect(bar, greaterThanOrEqualTo(0), reason: '没有 wg_tc_bar');
  final barBlock = xml.substring(bar, xml.indexOf('/>', bar));
  expect(barBlock.contains('layout_width="6dp"'), true,
      reason: '竖条不是 6dp 宽（App 里是 6dp）');
  expect(barBlock.contains('layout_height="match_parent"'), true,
      reason: '竖条不是 match_parent 高 —— 那它就不会通到内容底（旧实现是 24dp）');
  final kt = _read('android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
  expect(kt.contains('dpToPx(context, 6)'), true,
      reason: '竖条位图不是 6dp 宽');
  expect(kt.contains('dpToPx(context, 200)'), true,
      reason: '竖条位图高度不是 200dp —— 改回 24dp 会被 fitXY 拉成长椭圆两端（半径 3dp → 25dp）');
});
```

- [ ] **Step 2: 跑它，确认红**

Run: `flutter test test/widget_today_card_guard_test.dart`
Expected: FAIL —— 根还是 `<LinearLayout`、`wg_tc_bar` 是 `4dp`/`24dp`。

- [ ] **Step 3: 改 `widget_today_card.xml` 根结构**

把根 `<LinearLayout ... orientation="vertical" android:padding="22dp">` 改成**横向** `<LinearLayout ... android:orientation="horizontal" android:paddingLeft="0dp" android:paddingTop="22dp" android:paddingRight="22dp" android:paddingBottom="22dp">`。两个子层：

1. 竖条 `<ImageView android:id="@+id/wg_tc_bar" android:layout_width="6dp" android:layout_height="match_parent" android:scaleType="fitXY" android:contentDescription="@null" />`（根的**第一个直接子层**）。
2. 内容列 `<LinearLayout android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content" android:orientation="vertical" android:layout_marginStart="14dp">`，把原内容（日期行 / 农历 / 班次行 / 时间 / 班组行 / 本月统计）整个搬进去。

日期行里 `<ImageView ... wg_tc_bar 4dp×24dp .../>` **删掉**；`wg_tc_date` 的 `layout_marginStart="10dp"` **删掉**（那是原来给 4dp 行内条留的间隙，删了它日期才跟别的行对齐到 20dp）。

（注意：四个方向的内边距**逐个写**，别用 `padding` 一次定四个 —— 左是 0、其余是 22；注释写清「为什么横向 LinearLayout（match_parent 高要二次测量成内容高，FrameLayout 做不到）」并标注这个改动立刻生效、无需 force-stop。）

- [ ] **Step 4: 改 `renderTodayCard` 里竖条位图**

把 `WidgetChip.bar(if (d.hasShift) d.color else snap.accent, dpToPx(context, 4), dpToPx(context, 24))` 改成 `WidgetChip.bar(if (d.hasShift) d.color else snap.accent, dpToPx(context, 6), dpToPx(context, 200))`（200dp 是够长的常量，理由见 spec §3.1）。

- [ ] **Step 5: 跑测试，确认绿**

Run: `flutter test test/widget_today_card_guard_test.dart`
Expected: PASS（含那条新护栏）。

- [ ] **Step 6: 反向验证护栏**

把 `layout_height="match_parent"` 临时改回 `24dp` → 跑护栏 → 那条红；改回。把 `dpToPx(context, 6)` 改回 `dpToPx(context, 4)` → 红；改回。把 `dpToPx(context, 200)` 改回 `dpToPx(context, 24)` → 红；改回。把根 `orientation` 改回 `vertical` → 红；改回。

- [ ] **Step 7: 构建 + 真机验证竖条通高与圆头**

Run: `source tools/build-env.sh && cd app && "$FLUTTER_ROOT/bin/flutter" build apk --release --target-platform android-arm64` → `adb install -r ...` → 打开 App 触发一次快照重推 → 回桌面截图。量：竖条主色墨迹的顶 == 内容第一行顶、底 == 内容最后一行底、宽 6dp、两端是半圆。与 App 信息卡并排看。

- [ ] **Step 8: Commit**

```bash
git add app/android/app/src/main/res/layout/widget_today_card.xml app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt app/test/widget_today_card_guard_test.dart
git commit -m "fix(widget): 今日卡竖条改通高（6dp 贴左，与 App 信息卡对齐）"
```

---

### Task 2: 其他班组胶囊

**Files:**
- Modify: `app/android/app/src/main/res/layout/widget_crew_chip.xml`（14dp 圆环 → 全宽胶囊）
- Modify: `app/android/app/src/main/res/layout/widget_today_card.xml`（`wg_tc_crew_slot1..4` 等宽 → 自然宽左排）
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`（`renderTodayCard` 里胶囊位图宽用 `crewChipWidthPx`）
- Test: `app/test/widget_today_card_guard_test.dart`

**Interfaces:**
- Consumes: `WidgetChip.tintedChip(color: Int, wPx: Int, hPx: Int): Bitmap`（14% 淡染 + 45% 描边，圆角 = 高一半，已存在，不改）；`chipWidthPx(context, abbr, textSizeDp)` 的 `Paint.measureText` 路子。
- Produces: `private fun crewChipWidthPx(context: Context, text: String): Int` —— 返回 `(paint.measureText(text) + 30f * density).toInt()`（左内边距 8 + 圆点 8 + 间距 6 + 右内边距 8），`textSize = 12dp × density`。

- [ ] **Step 1: 写失败测试 —— 胶囊位图宽来自文字现量、槽位自然宽**

在 `widget_today_card_guard_test.dart` 加两条：

```dart
test('其他班组：胶囊位图宽来自文字现量（不是写死的比例）', () {
  final kt = _read('android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
  final today = kt.substring(kt.indexOf('private fun renderTodayCard('), kt.indexOf('private fun todayStandalone('));
  expect(today.length, greaterThan(500), reason: '没截出 renderTodayCard');
  expect(today.contains('crewChipWidthPx'), true,
      reason: '胶囊宽度没按「组名+简称」现量 —— 写死的宽要么比文字窄被裁、要么空出一大块');
  expect(today.contains('WidgetChip.tintedChip(crew.color'), true,
      reason: '胶囊没走 tintedChip（14% 淡染 + 45% 描边，与 App 同一配方）');
  expect(today.contains('dpToPx(context, 22)'), true,
      reason: '胶囊高度不是 22dp（与「其他班组」那行同高）');
  // 现量必须是真量：函数体里有 measureText（只「调了 crewChipWidthPx」还不够，
  // 里面写死一个数也能过前一条）。
  final fn = kt.substring(kt.indexOf('fun crewChipWidthPx('));
  expect(fn.length, greaterThan(100), reason: '没截出 crewChipWidthPx');
  expect(fn.substring(0, fn.indexOf('\n    }')).contains('measureText'), true,
      reason: 'crewChipWidthPx 函数体里没有 measureText —— 宽度不是真按文字量的');
});

test('其他班组：槽位自然宽左排，不再四个等宽', () {
  final xml = _read('android/app/src/main/res/layout/widget_today_card.xml');
  for (final id in ['wg_tc_crew_slot1', 'wg_tc_crew_slot2', 'wg_tc_crew_slot3', 'wg_tc_crew_slot4']) {
    final i = xml.indexOf('@+id/$id');
    expect(i, greaterThanOrEqualTo(0), reason: '没有 $id');
    final block = xml.substring(xml.lastIndexOf('<FrameLayout', i), xml.indexOf('/>', i));
    expect(block.contains('layout_width="wrap_content"'), true,
        reason: '$id 不是 wrap_content —— 还是等宽槽，胶囊会摊成方盒而不是紧挨左排');
    expect(block.contains('layout_weight="1"'), false,
        reason: '$id 还带着 weight=1 等宽');
  }
});
```

- [ ] **Step 2: 跑它们，确认红**

Run: `flutter test test/widget_today_card_guard_test.dart`
Expected: FAIL —— `crewChipWidthPx` 不存在；槽位还是 `0dp` + `weight=1`。

- [ ] **Step 3: 改 `widget_crew_chip.xml`**

根 `LinearLayout(match_parent × match_parent)` 改成 `FrameLayout(wrap_content × 22dp)`：里面放 `ImageView wg_cc_bg`（match_parent × match_parent，`scaleType="fitXY"`），删掉 14dp 的圆环 FrameLayout；圆点 `wg_cc_dot` 改成 8dp×8dp，与文字 `wg_cc_text`（wrap_content、`marginStart 6dp`、12dp、`maxLines=1`）一起包进一个 `LinearLayout(horizontal, match_parent × match_parent, gravity="center_vertical", paddingHorizontal="8dp")`。**内层这个 LinearLayout 必须 `match_parent` 高**（`center_vertical` 只居中它自己的子层，自己缩成内容高就顶到胶囊上沿）。注释写明「这是 App `_otherCrewChips` 的同款胶囊，圆环已删、圆点 8dp 实心、内层撑满以垂直居中」。

- [ ] **Step 4: 改 `widget_today_card.xml` 的槽位**

`wg_tc_crew_slot1..4` 每个从 `layout_width="0dp" + layout_weight="1"` 改成 `layout_width="wrap_content" + layout_marginStart="8dp"`（第一个不加 margin，与 App 的 `spaceSm=8` 一致）。

- [ ] **Step 5: 改 `renderTodayCard` 的胶囊位图**

在 `WidgetRenderer.kt` 加 `crewChipWidthPx`（见 Interfaces），把 `chip.setImageViewBitmap(R.id.wg_cc_bg, WidgetChip.tintedChip(crew.color, dpToPx(context, 14), dpToPx(context, 14)))` 改成 `chip.setImageViewBitmap(R.id.wg_cc_bg, WidgetChip.tintedChip(crew.color, crewChipWidthPx(context, "${crew.name} ${crew.abbr}"), dpToPx(context, 22)))`。`wg_cc_dot` 的 `WidgetChip.circle(crew.color, dpToPx(8))` 不变。

- [ ] **Step 6: 跑测试，确认绿**

Run: `flutter test test/widget_today_card_guard_test.dart`
Expected: PASS。

- [ ] **Step 7: 反向验证护栏**

把某个 `crew_slot` 改回 `0dp` + `weight=1` → 红，改回；把 `crewChipWidthPx` 的调用换回写死的 `dpToPx(context, 60)` → 红（护栏要求出现 `crewChipWidthPx`），改回；把 `crewChipWidthPx` 函数体里的 `measureText` 换成写死的返回值 → 红（护栏断言函数体含 `measureText`），改回。

- [ ] **Step 8: 构建 + 真机验证胶囊贴字与 4 班组降级**

构建安装 → 打开 App 触发快照重推 → 回桌面截图：3 个班组时胶囊紧贴文字、挨着左排、圆点 8dp 无圆环，与 App 并排看间距同量级。再把种子库换成 5 班组（4 个「其他」）出图，确认第 4 颗在右缘被裁、不崩、别处不动。

- [ ] **Step 9: Commit**

```bash
git add app/android/app/src/main/res/layout/widget_crew_chip.xml app/android/app/src/main/res/layout/widget_today_card.xml app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt app/test/widget_today_card_guard_test.dart
git commit -m "fix(widget): 今日卡「其他班组」套半透明胶囊、紧挨左排"
```

---

### Task 3: 收尾（版本 / 更新日志 / 文档 / 发布）

**Files:**
- Modify: `app/pubspec.yaml`（`version: 0.11.26+173`）、`app/lib/core/app_info.dart`（`appVersion = '0.11.26'`）
- Modify: `app/lib/features/profile/app_dialogs.dart`（`_changelogZh`/`_changelogEn` prepend v0.11.26、删最旧一条、各保持 10 条）
- Modify: `AGENTS.md`（版本史一行 + 「最近改动」一节 + 关键决策与坑里「外层布局要 force-stop 桌面」这条已经有，若有新教训补上）
- Create: `tools/gh/release-notes-v0.11.26.md`

**Interfaces:** 无新函数。沿用既有发布流程（`tools/_run-release.ps1`）。

- [ ] **Step 1: 版本号 + 更新日志**

`version: 0.11.25+172` → `0.11.26+173`；`appVersion` 同步。`_changelogZh`/`_changelogEn` 各 prepend v0.11.26 两条（竖条通高、其他班组胶囊），删最旧一条，各保持 10 条。

- [ ] **Step 2: 全量验收**

Run: `flutter analyze`（0 issue）、`flutter test`（1092 + 新增护栏，只增不减）。反向验证已在各 Task 内做。

- [ ] **Step 3: 文档**

`AGENTS.md`：版本史加 `→ 0.11.26(+173) 测试版（…）`，「最近改动」加一节，若真机踩出新坑（如 FrameLayout match_parent 高度塌不塌）补进「关键决策与坑」。

- [ ] **Step 4: 发布**

跑 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\_run-release.ps1`；发完 curl 一次 `main` 的 `latest.json` 核对 `prerelease = 0.11.26`；确认签名那行不是「跳过」（或在装过 release 包的机器上 `adb install -r` 能过）。

- [ ] **Step 5: Commit + tag + push**

```bash
git add -A
git commit -m "chore(release): v0.11.26"
git push origin beta
git tag v0.11.26 && git push origin v0.11.26
```
