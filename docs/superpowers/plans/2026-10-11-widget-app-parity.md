# 桌面小组件贴齐 App（A 版）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让桌面那三张小组件卡（周条 / 今日卡 / 月历）的观感贴齐 App —— 月历恢复「每格一张白卡」，「今天」在月历格 / 周条列 / 今日卡药丸三处都成为**实心主色块**。

**Architecture:** 桌面小组件走原生 `RemoteViews`（宿主进程渲染），所以「玻璃」全部靠**烤好的位图**与**静态 `<shape>`** 近似：**颜色会变的**（今天那块、实心班次胶囊）烤位图，**颜色固定的**（格子卡底、面板底）用矢量 `<shape>`（圆角不会被 `fitXY` 拉成椭圆）。月历卡的面板去扮 App 的「页面」（浅灰/深底），42 格扮白卡 —— 这是 A 版成立的前提。

**Tech Stack:** Kotlin（`RemoteViews` / `Canvas` 画位图 / `LruCache`）、Android XML 资源（`<shape>` / 布局）、Dart 侧的**扫源码护栏测试**（这个仓库在 Kotlin 侧**没有可跑的测试目标**，所以结构不变量靠 Dart 读源码来守、行为靠真机）。

**Spec:** `docs/superpowers/specs/2026-10-11-widget-app-parity-design.md`（**先读它**，本计划的每一条约束都出自它；两者冲突以 spec 为准）

## Global Constraints

- **今天那块是实心主色，这是与 App 的有意偏离**（App 那枚选择块是半透明的）—— 见 spec §1 末尾。构建者拿它跟 App 并排比时**不要「修正」成半透明**。
- **块上的字一律走 `onSolidInk`**：一个运行期函数，按块的颜色现算（相对亮度 > 0.55 取近黑，否则取白）。**不是**「浅色档一套、深色档一套」两个固定值 —— 主色与班次色都是用户可选的。
- **月历卡的面板必须不透明**（`#FFF5F6FA` / `#FF0B0B10`）：97% 时叠黑壁纸，`wg_muted_light` 只有 **4.33:1（跌破 AA）**，不透明是 **4.61:1**。这是算出来的，不是口味。
- **别为了「更像」把 `widget_colors.xml` 里 `wg_card_*` 那 94~97% 的不透明度调回去** —— 那是为了挡壁纸（可读性优先）。要动先重算对比度。
- **Kotlin 里不许出现用户可见的中文字面量**（文案全在 Dart 的 `L10n`，随快照过来）。
- **`addView` 前必须 `removeAllViews`**；**每个视图的状态两个方向都要设满**（该 `GONE` 的显式 `GONE`）—— 宿主 `reapply` 只重放新动作。
- **不改 requestCode 池**（本轮不加任何点击目标）、**不改三张卡的尺寸**（`resizeMode="none"`）、**不动 Dart 侧的快照协议**（`weekday` / `lunarShort` / `accent` / `themeMode` 都已在快照里）。
- 版本号只改末位 `Z` 与 `build`（本轮 **0.11.8+155 → 0.11.9+156**），`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 必须同步。
- 构建：`source tools/build-env.sh` 之后用 `"$FLUTTER_ROOT/bin/flutter"`（`flutter` 不在 PATH 上）。**不许跑 `dart format`**。

## Review Focus

这些是 spec 隐含、但**没有任何自动测试能覆盖**的输入/失败方式（Kotlin 侧没有测试目标，真机是唯一的眼睛）—— 每条都在下面某个任务里配了一条**扫源码的护栏**或一个**真机清单项**：

1. **假期正好是今天** —— 农历那行平时走 `holiday`（红字）表示节假日；今天那格是实心块，红字压在块上读不出来。**决定：今天那格一律 `onSolidInk`**（可读性优先），代价是**这一天看不出「是节假日」**，一个月至多一次。护栏：`wg_mc_lunar` 的 `setTextColor` 实参必须出现 `onSolidInk`（任务 2）。
2. **自定义班次色与主色接近** —— 今天那格是「实心主色块 + 里面一颗实心班次色胶囊」，两颗色接近时胶囊会糊进块里。真机清单项（任务 5）。
3. **今天落在一个 5 行的月 vs 6 行的月** —— 块的尺寸按**当月真实可见行数**反推，行数差 18%；用固定值会让 5 行月那格明显偏矮、四个角露出白卡的角尖。护栏：块尺寸必须来自 `monthCellPx`（任务 2）。
4. **空白表方案（那天没有班次定义）** —— 今天那格没有胶囊，块上只有日数字与农历；`hasShift == false` 那一支必须把胶囊与简称都显式 `GONE`。真机清单项（任务 5）。
5. **英文 + 长简称** —— 「今天」药丸的宽度写死 52dp（`RemoteViews` 量不到文字宽度），英文 `Today` 比「今天」宽；周条的周几在两字简称（「上夜」）下要确认没被 `fitXY` 压变形。真机清单项（任务 5）。

---

### Task 1: 位图原语与资源

**Files:**
- Modify: `android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetChip.kt`
- Create: `android/app/src/main/res/drawable/widget_cell_light.xml`、`widget_cell_dark.xml`、`widget_page_light.xml`、`widget_page_dark.xml`
- Modify: `android/app/src/main/res/values/widget_colors.xml`
- Test: `test/widget_cell_block_guard_test.dart`（新建）

**Interfaces:**
- Produces: `WidgetChip.block(color: Int, w: Int, h: Int, radiusPx: Float, borderColor: Int = 0, borderPx: Float = 0f): Bitmap` —— 圆角实心块（可选描边），命中 `LruCache`，键含全部入参。任务 2 / 3 / 4 都用它。
- Produces（资源名，任务 2 用）：`R.drawable.widget_cell_light` / `widget_cell_dark`（格子卡底）、`widget_page_light` / `widget_page_dark`（月历卡面板底）；颜色 `wg_cell_fill_light` `#FFFFFFFF`、`wg_cell_border_light` `#0F000000`、`wg_cell_fill_dark` `#FF1B1B22`、`wg_cell_border_dark` `#1AFFFFFF`、`wg_on_solid_light` `#FFFFFFFF`、`wg_on_solid_dark` `#FF111818`。

- [ ] **Step 1: 写失败的护栏测试**

新建 `app/test/widget_cell_block_guard_test.dart`。它是**扫源码**的护栏（Kotlin 没有测试目标），照 `test/widget_fixed_cards_guard_test.dart` 的写法：顶层一个 `String _read(String rel)`（工作目录是 `app/`，路径拼 `'android/app/src/main/res/…'` 与 `'android/app/src/main/kotlin/…'`）。

本任务只放两条（**先只写这两条，任务 2/3 再往这个文件里加**）：

```dart
test('四张资源成对存在：格子卡底与页面底，浅深各一', () {
  for (final base in ['widget_cell', 'widget_page']) {
    for (final tier in ['light', 'dark']) {
      final f = File('android/app/src/main/res/drawable/$base\_$tier.xml');
      expect(f.existsSync(), true,
          reason: '$base\_$tier.xml 不在 —— 少一张就是**某一档静默没有底**'
              '（另一个档看不出来，真机上只有把系统切过去才会现形）');
    }
  }
});

test('页面底必须不透明（97% 会跌破 AA）', () {
  for (final tier in ['light', 'dark']) {
    final src = _read('android/app/src/main/res/drawable/widget_page\_$tier.xml');
    // shape 的两个颜色字面量
    final colors = RegExp(r'#([0-9A-Fa-f]{8})')
        .allMatches(src)
        .map((m) => m.group(1)!.toUpperCase())
        .toList();
    expect(colors.length, greaterThanOrEqualTo(2),
        reason: '页面底应当有渐变的两端色 —— 只扫到 ${colors.length} 个 8 位色值，'
            '要么资源被改回单色，要么这条正则跟源码对不上了');
    for (final c in colors) {
      expect(c.substring(0, 2), 'FF',
          reason: '页面底 $tier 档有半透明端（#$c）—— 叠黑壁纸时 wg_muted 只有 4.33:1，'
              '跌破 AA 4.5。这条数在 spec §5 里算过，别改成 97%');
    }
  }
});
```

- [ ] **Step 2: 跑它，确认红**

Run: `"$FLUTTER_ROOT/bin/flutter" test test/widget_cell_block_guard_test.dart`
Expected: FAIL —— 两条都在报文件不存在（第一条报 `widget_cell_light.xml` 不在，第二条 `_read` 抛异常）。

- [ ] **Step 3: 加四张 drawable 与六个颜色**

`widget_cell_light.xml` / `_dark.xml`：`<shape android:shape="rectangle">`，`<corners android:radius="12dp"/>`，`<solid>` 取 `@color/wg_cell_fill_*`，`<stroke android:width="1dp" android:color="@color/wg_cell_border_*"/>`。

`widget_page_light.xml`：`<corners android:radius="22dp"/>` + `<gradient android:angle="315" android:startColor="#FFF5F6FA" android:endColor="#FFF1F3F8"/>` + `<stroke android:width="1dp" android:color="@color/wg_border_light"/>`；`_dark.xml` 同形，两端 `#FF0B0B10` / `#FF15151B`，描边 `@color/wg_border_dark`。

`widget_colors.xml` 追加（**值照抄，别改**）：`wg_cell_fill_light` `#FFFFFFFF`、`wg_cell_border_light` `#0F000000`、`wg_cell_fill_dark` `#FF1B1B22`、`wg_cell_border_dark` `#1AFFFFFF`、`wg_on_solid_light` `#FFFFFFFF`、`wg_on_solid_dark` `#FF111818`。

- [ ] **Step 4: 跑测试，确认绿**

Run: `"$FLUTTER_ROOT/bin/flutter" test test/widget_cell_block_guard_test.dart`
Expected: PASS 2/2。

- [ ] **Step 5: 加 `WidgetChip.block`**

在 `WidgetChip.kt` 的 `object WidgetChip` 里，`rounded` 之上加：

```kotlin
fun block(color: Int, w: Int, h: Int, radiusPx: Float,
          borderColor: Int = 0, borderPx: Float = 0f): Bitmap
```

实现照 `tintedChip` 的骨架：同样的 `coerceAtLeast(1)` 兜底、同样的 `LruCache` 命中/写回；键写成 `"blk:$color:$borderColor:$borderPx:$width:$height:$radiusPx"`；`radiusPx` 要 `coerceAtMost(minOf(width, height) / 2f)`（同 `rounded`）；先画 FILL 的圆角矩形，`borderPx > 0f` 时再画 STROKE（`strokeWidth = borderPx`，矩形内缩 `borderPx / 2f`）。

- [ ] **Step 6: 跑全套，确认没碰坏别的**

Run: `"$FLUTTER_ROOT/bin/flutter" analyze` → Expected: `No issues found!`
Run: `"$FLUTTER_ROOT/bin/flutter" test` → Expected: 全绿（本轮之前是 **892** 条，现在应为 **894**）

- [ ] **Step 7: 提交**

```bash
git add app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetChip.kt \
        app/android/app/src/main/res/drawable/widget_cell_light.xml \
        app/android/app/src/main/res/drawable/widget_cell_dark.xml \
        app/android/app/src/main/res/drawable/widget_page_light.xml \
        app/android/app/src/main/res/drawable/widget_page_dark.xml \
        app/android/app/src/main/res/values/widget_colors.xml \
        app/test/widget_cell_block_guard_test.dart
git commit -m "feat(widget): 圆角实心块原语 + 格子/页面四张资源"
```

---

### Task 2: 月历卡 —— 面板扮页面、每格白卡、今天实心块

**Files:**
- Modify: `android/app/src/main/res/layout/widget_month_cell.xml`
- Modify: `android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`（`monthCard`、新增 `onSolidInk` / `monthCellPx` / `monthGridRows`）
- Test: `test/widget_cell_block_guard_test.dart`（追加）

**Interfaces:**
- Consumes: 任务 1 的 `WidgetChip.block` 与四张资源、六个颜色。
- Produces: `private fun onSolidInk(context: Context, color: Int): Int`、`private fun monthCellPx(context: Context, widgetId: Int, rows: Int): Pair<Int, Int>`、`private fun monthGridRows(snap: WidgetStore.Snapshot, gridStart: LocalDate): Int` —— 任务 3 复用 `onSolidInk`。

- [ ] **Step 1: 追加护栏（先红）**

往 `test/widget_cell_block_guard_test.dart` 追加：

```dart
test('月历格有「今天」那块 ImageView，且 id 与 Kotlin 引用逐字一致', () {
  const id = 'wg_mc_block';
  final kt = _read('android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
  final xml = _read('android/app/src/main/res/layout/widget_month_cell.xml');
  expect(RegExp('android:id="\\@\\+id/$id"').hasMatch(xml), true,
      reason: 'widget_month_cell.xml 里没有 $id —— 块画不出来，而且**不报错**');
  // 两个方向都要设满：只 setImageViewBitmap 不 setViewVisibility(GONE)，
  // 翻月之后非今天那一格会挂着上一次的块（宿主 reapply 只重放新动作）。
  expect(kt.contains('R.id.$id'), true,
      reason: 'WidgetRenderer.kt 里没引用 $id —— 布局改了、Kotlin 没跟');
  expect(kt.contains('R.id.$id, android.view.View.GONE'), true,
      reason: '$id 没有显式 GONE 那一支 —— 块会残留到别的格子上');
});

test('「今天」块的位图尺寸来自 AppWidgetOptions，不是写死的', () {
  final kt = _read('android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
  expect(kt.contains('WidgetChip.block('), true, reason: '一处都没用上块原语');
  final i = kt.indexOf('private fun monthCellPx');
  expect(i, greaterThanOrEqualTo(0), reason: 'monthCellPx 不见了');
  final body = kt.substring(i, kt.indexOf('\n    }', i));
  expect(body.contains('OPTION_APPWIDGET_MIN_WIDTH'), true,
      reason: 'monthCellPx 没读 AppWidgetOptions —— 尺寸写死的话，5 行月与 6 行月'
          '（格子高差 18%）里必有一档的圆角被拉变形、四角露出白卡的角尖');
  expect(body.contains('OPTION_APPWIDGET_MIN_HEIGHT'), true, reason: '同上，高度那一路');
});

test('今天那格的字都过 onSolidInk', () {
  final kt = _read('android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
  expect(kt.contains('private fun onSolidInk'), true, reason: 'onSolidInk 不见了');
  final uses = RegExp(r'onSolidInk\(').allMatches(kt).length;
  // ⚠️ 这是一个**下界**（不是精确计数）：它抓的是「漏了一处分支」。
  // 本任务做完应当是 3 处（日数字 / 农历 / 胶囊简称）—— 少一处，就是
  // 「假期撞上今天时红字压在实心块上读不出来」这类情况。
  expect(uses, greaterThanOrEqualTo(3),
      reason: 'onSolidInk 只用到了 $uses 处，月格那三处（日数字 / 农历 / 简称）没凑齐');
});
```

> ⚠️ **这两条护栏是分任务长大的**：任务 3 会把第一条扩到周条的 `wg_sc_block`、把第二条扩到 `stripCellPx`、把第三条的下界提到 6；任务 4 再提到 7。**别在任务 2 就一次写满** —— 那样任务 2 自己结束时还是红的（它还没做周条与今日卡）。

- [ ] **Step 2: 跑它，确认红**

Run: `"$FLUTTER_ROOT/bin/flutter" test test/widget_cell_block_guard_test.dart`
Expected: FAIL 3 条（布局里没有 `wg_mc_block`、`WidgetChip.block(` 一处都没有、`onSolidInk` 不存在）。

- [ ] **Step 3: 改布局 `widget_month_cell.xml`**

根从 `LinearLayout` 换成 `FrameLayout`（**id 仍是 `wg_mc_root`**，`layout_margin="2dp"`），里面两层：

1. `ImageView` `android:id="@+id/wg_mc_block"`，`match_parent` / `match_parent`，`android:scaleType="fitXY"`，`android:contentDescription="@null"`；
2. 原来的 `LinearLayout`（`match_parent`、`orientation="vertical"`、`gravity="center"`）连同它的三个子视图（`wg_mc_day` / 那个 `FrameLayout` 里的 `wg_mc_pill` + `wg_mc_abbr` / `wg_mc_lunar`）**原样搬进来**，一个属性都不改。

- [ ] **Step 4: 加三个私有函数**

在 `WidgetRenderer` 里（`dpToPx` 附近）：

`onSolidInk(context, color)`：取 `(color shr 16) and 0xFF` / `(color shr 8) and 0xFF` / `color and 0xFF`，算 `(0.2126*r + 0.7152*g + 0.0722*b) / 255.0`，`> 0.55` 返回 `context.getColor(R.color.wg_on_solid_dark)`，否则 `R.color.wg_on_solid_light`。

`monthCellPx(context, widgetId, rows)`：读 `AppWidgetManager.getInstance(context).getAppWidgetOptions(widgetId)` 的 `OPTION_APPWIDGET_MIN_WIDTH`（兜底 250）/ `OPTION_APPWIDGET_MIN_HEIGHT`（兜底 320），单位 dp → px 乘 `context.resources.displayMetrics.density`；宽 = `((wDp - 16) / 7f - 4f)`；高 = `((hDp - 16 - 28 - 20) / rows - 4f)`（16 = 卡 padding 8dp×2、28 = 标题行、20 ≈ 周几行、4 = 格缝 2dp×2）；两者各 `coerceAtLeast(1)`。

`monthGridRows(snap, gridStart)`：把 `snap.days` 的 `day` 收成 `HashSet`，数 42 个槽位里有几个落在这个集合里，返回 `((visible + 6) / 7).coerceAtLeast(1)`。

- [ ] **Step 5: 改 `monthCard`**

四处改动：

1. 面板底换成 `widget_page_light` / `widget_page_dark`（按 `dark`）；
2. 在 `val leading = …` 那一段之后算一次 `val rows = monthGridRows(snap, gridStart)`；
3. 循环里**每一格**：`c.setInt(R.id.wg_mc_root, "setBackgroundResource", if (isToday) 0 else if (dark) R.drawable.widget_cell_dark else R.drawable.widget_cell_light)` —— **今天那格置 0**（块自己充当卡，见 spec §5「不许白卡上面盖块」）；
4. 循环里**今天那格**：`c.setViewVisibility(R.id.wg_mc_block, View.VISIBLE)` + `c.setImageViewBitmap(R.id.wg_mc_block, WidgetChip.block(snap.accent, cellW, cellH, dpToPx(context, 12).toFloat()))`，`cellW`/`cellH` 来自 `monthCellPx(context, widgetId, rows)`；非今天 `GONE`。日数字 / 农历 / 胶囊简称三处的颜色各加一条 `isToday -> onSolidInk(context, …)` 分支（日数字与农历用 `snap.accent`，简称用 `d.color`）；今天那格的胶囊改画 `WidgetChip.block(d.color, 40dp, 18dp, 9dp)`。

- [ ] **Step 6: 跑测试，确认绿**

Run: `"$FLUTTER_ROOT/bin/flutter" test test/widget_cell_block_guard_test.dart` → Expected: PASS 5/5
Run: `"$FLUTTER_ROOT/bin/flutter" analyze` → Expected: `No issues found!`
Run: `"$FLUTTER_ROOT/bin/flutter" test` → Expected: 全绿 **894**

- [ ] **Step 7: 出图看一眼（真机）**

Run（照 `AGENTS.md` 的小组件流程）：

```bash
source tools/build-env.sh && cd app && "$FLUTTER_ROOT/bin/flutter" build apk --release --target-platform android-arm64
adb install -r app/build/app/outputs/flutter-apk/app-release.apk
adb shell am start -n com.daoban.shiftassistantpro/.MainActivity   # 推一次快照
adb shell input keyevent 3
adb shell am force-stop com.miui.home && sleep 8                   # 小米按资源 id 缓存 drawable
adb shell input keyevent 3
# 划到最后一页（月历卡所在页），截图
adb exec-out screencap -p > work/wg-month.png
```

Expected: 月历卡的面板是浅灰、42 格是带缝的白卡、今天那一格是**实心主色块且四角没有白尖**。

- [ ] **Step 8: 提交**

```bash
git add app/android/app/src/main/res/layout/widget_month_cell.xml \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt \
        app/test/widget_cell_block_guard_test.dart
git commit -m "feat(widget): 月历卡扮页面 + 每格白卡 + 今天实心块"
```

---

### Task 3: 周条 —— 今天那一列

**Files:**
- Modify: `android/app/src/main/res/layout/widget_strip_cell.xml`
- Modify: `android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`（`weekStrip`、新增 `stripCellPx`）
- Test: `test/widget_cell_block_guard_test.dart`（任务 2 的 Step 1 已经把 `wg_sc_block` 那一条写进去了，**它此刻应当还是红的**）

**Interfaces:**
- Consumes: 任务 2 的 `onSolidInk`。
- Produces: `private fun stripCellPx(context: Context, widgetId: Int): Pair<Int, Int>`。

- [ ] **Step 1: 把三条护栏扩到周条，先确认它们红**

在 `test/widget_cell_block_guard_test.dart` 里做三处扩写：
1. 第一条那个测试**改名为「两张 cell 布局都有『今天』那块 ImageView…」**，把 `widget_month_cell` / `wg_mc_block` 与 `widget_strip_cell` / `wg_sc_block` 都过一遍（把测试体抽成一个 `void check(String layout, String id)` 调两次）；
2. 第二条那个测试在 `monthCellPx` 之外，再对 `stripCellPx` 做同样两问（存在、且读 `OPTION_APPWIDGET_MIN_WIDTH` / `_HEIGHT`）；
3. 第三条那个测试的下界从 `3` 改成 `6`（周条新增周几 / 日数字 / 简称三处）。

Run: `"$FLUTTER_ROOT/bin/flutter" test test/widget_cell_block_guard_test.dart`
Expected: FAIL 3 条（`widget_strip_cell.xml` 里没有 `wg_sc_block`、`stripCellPx` 不存在、`onSolidInk` 只有 3 处）。

- [ ] **Step 2: 改布局 `widget_strip_cell.xml`**

与任务 2 Step 3 同形：根换成 `FrameLayout`（**id 仍是 `wg_sc_root`**，**不加 margin** —— 这一列原本就贴满槽位），里面一层 `ImageView wg_sc_block`（`match_parent` + `fitXY` + `contentDescription="@null"` + `layout_margin="2dp"`），再一层原来那个 `LinearLayout`（`match_parent`，三个子视图 `wg_sc_weekday` / `wg_sc_day` / 胶囊那对**原样不动**）。

- [ ] **Step 3: 加 `stripCellPx` 并改 `weekStrip`**

`stripCellPx(context, widgetId)`：与 `monthCellPx` 同形，但**没有标题行与周几行** —— 高 = `(hDp - 20) * density`（20 ≈ 卡 padding 8dp×2 + 格缝 4dp），宽 = `((wDp - 16) / 7f - 4f) * density`；`OPTION_APPWIDGET_MIN_HEIGHT` 兜底 **40**。

`weekStrip` 里：循环前 `val (colW, colH) = stripCellPx(context, widgetId)`；循环里今天那一列 `wg_sc_block` 显式 `VISIBLE` + `setImageViewBitmap(… WidgetChip.block(snap.accent, colW, colH, dpToPx(context, 12).toFloat()))`，非今天显式 `GONE`；周几 / 日数字 / 胶囊简称三处的颜色各加 `isToday -> onSolidInk(context, …)`，今天那列的胶囊改画 `WidgetChip.block(d.color, 36dp, 18dp, 9dp)`。

- [ ] **Step 4: 跑测试，确认绿**

Run: `"$FLUTTER_ROOT/bin/flutter" test test/widget_cell_block_guard_test.dart` → Expected: PASS 5/5
Run: `"$FLUTTER_ROOT/bin/flutter" test` → Expected: 全绿 **894**

- [ ] **Step 5: 出图（真机，与月历卡同一屏）**

同任务 2 Step 7 的流程，但要划到**倒数第二页**（周条 + 今日卡）。
Expected: 今天那一列是实心主色块，块里的周几 / 日数字 / 胶囊都是块上字；**与旁边月历卡的今天看起来是同一件事**。

- [ ] **Step 6: 提交**

```bash
git add app/android/app/src/main/res/layout/widget_strip_cell.xml \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt
git commit -m "feat(widget): 周条的今天那一列铺实心主色块"
```

---

### Task 4: 今日卡 —— 「今天」药丸转实心

**Files:**
- Modify: `android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`（`renderTodayCard`）
- Test: `test/widget_cell_block_guard_test.dart`（靠任务 2 的 `onSolidInk` 计数那条覆盖）

**Interfaces:**
- Consumes: 任务 1 的 `WidgetChip.block`、任务 2 的 `onSolidInk`。

- [ ] **Step 1: 把 `onSolidInk` 的下界提到 7，先确认它红**

第三条测试里的 `greaterThanOrEqualTo(6)` 改成 `7`（今日卡药丸那处）。
Run: `"$FLUTTER_ROOT/bin/flutter" test test/widget_cell_block_guard_test.dart --plain-name '今天那格的字都过 onSolidInk'`
Expected: FAIL —— 报「只用到了 6 处」。

- [ ] **Step 2: 改 `renderTodayCard` 的「今天」徽章**

把那处 `WidgetChip.tintedChip(snap.accent, dpToPx(context, 52), dpToPx(context, 24))` 换成 `WidgetChip.block(snap.accent, dpToPx(context, 52), dpToPx(context, 24), dpToPx(context, 12).toFloat())`（圆角取高度的一半），并把紧随其后的 `v.setTextColor(R.id.wg_tc_today_text, snap.accent)` 换成 `onSolidInk(context, snap.accent)`。**布局一个字都不用改**（`wg_tc_today_bg` 已经是 `ImageView` + `fitXY`）。

- [ ] **Step 3: 跑测试，确认绿**

Run: `"$FLUTTER_ROOT/bin/flutter" test test/widget_cell_block_guard_test.dart` → Expected: PASS 5/5
Run: `"$FLUTTER_ROOT/bin/flutter" analyze` → Expected: `No issues found!`

- [ ] **Step 4: 出图（真机）**

同任务 3 Step 5 的同一页。
Expected: 「今天」是**实心主色药丸 + 块上字**，不再是被冲淡的淡染。

- [ ] **Step 5: 提交**

```bash
git add app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt
git commit -m "feat(widget): 今日卡的「今天」药丸转实心主色"
```

---

### Task 5: 真机验收矩阵

**Files:** 无（只出图与记录）

- [ ] **Step 1: 浅色 / 深色 × 三张卡**

主色调用**默认的蓝**。同一份构建下切主题：**改 App 的主题设置**（我的 → 主题模式），**不要**只切系统的深色 —— 小组件只有在 App 推一次新快照时才会重画。
Expected: 三张卡在浅深两档下都成立；月历卡的格子与面板分得开；块上文字都读得出来。

- [ ] **Step 2: 最坏的两颗主色调**

把主色调依次切到 **teal（青）** 与 **orange（橙）**，各看一遍月历卡与今日卡。
Expected: `onSolidInk` 在这两档下判成**黑字**（白字压这两颗不达 AA：2.63 / 2.55，见 `AGENTS.md`）。**这两档是这一轮第一次让主色去当背景**，只用默认的蓝去看永远照不出来。

- [ ] **Step 3: 英文**

语言切 English。
Expected: 「今天」药丸（宽度写死 52dp）里的 `Today` 没被 `fitXY` 压变形、也没把日期挤走。

- [ ] **Step 4: 5 行月与 6 行月**

翻月，找到一个 5 行的月（例如 2026 年 2 月）与一个 6 行的月（例如 2026 年 8 月），各看一眼今天那一格（把日期临时改到那两个月看，或看图里相邻月的格子）。
Expected: 两块块的四角都**没有露出白卡的角尖**（露尖就是 `monthCellPx` 的行数反推错了）。

- [ ] **Step 5: 空白表方案 + 假期撞今天**

排班切到「跟随法定节假日（无班次）」那套：今天那格**不该有胶囊**，块上只有日数字与农历。
再把日期临调到某个法定节假日（如 10 月 1 日）：Expected: 块上的农历走**块上字**（不追求红字），且**读得出来** —— 这是 spec §4 那条有意的取舍。

- [ ] **Step 6: 记录**

把六组图（浅 / 深 / 青 / 橙 / 英文 / 5-6 行月）并排存一份给用户，并在提交信息里写清「哪几张是这一轮的验收图」。

---

### Task 6: 收尾（版本号 / 更新日志 / 项目记忆 / 发布）

**Files:**
- Modify: `app/pubspec.yaml`（`version: 0.11.8+155` → `0.11.9+156`）
- Modify: `app/lib/core/app_info.dart`（`appVersion` → `'0.11.9'`）
- Modify: `app/lib/features/profile/app_dialogs.dart`（`_changelogZh` / `_changelogEn` 各 prepend 一条 **0.11.9**、删最旧一条，**窗口恒 10 条**）
- Modify: `AGENTS.md`（版本号规则那一串加一条 0.11.9；「关键决策与坑」加一条小组件贴齐的约束）
- Create: `tools/gh/release-notes-v0.11.9.md`（**gitignored**，只在本机）

- [ ] **Step 1: 版本号两处同步**

两处一起改，`app/test/app_info_test.dart` 会盯住它们一致。

- [ ] **Step 2: 更新日志**

中文与英文各 prepend 一条，**纯文本、不许出现 markdown 标记**（`changelog_window_test.dart` 会扫），措辞照这一版的实情：月历恢复每格白卡、今天改成实心主色块（三处）、顺带说明「桌面上没有实时模糊，玻璃感靠描边与圆角近似」。

- [ ] **Step 3: `AGENTS.md`**

「关键决策与坑」加一条：**桌面小组件的「今天」是实心块，App 那边是半透明的选择块 —— 这是有意的偏离**（桌面没有实时模糊，半透明块压在任意壁纸上会消失），**别再「修正」回去**；并记下那条算出来的数（页面底必须不透明，97% 时 muted 只有 4.33:1）。

- [ ] **Step 4: 跑全套**

Run: `"$FLUTTER_ROOT/bin/flutter" analyze` → `No issues found!`
Run: `"$FLUTTER_ROOT/bin/flutter" test` → 全绿（含更新日志窗口与版本号两条护栏）
Run: `"$FLUTTER_ROOT/bin/flutter" test tool/visual/` → 全绿（**Kotlin 改动不该动到那 255 张图**；若有差异，逐张解释）

- [ ] **Step 5: 构建 + 发布**

Run: `scripts/release.ps1 -SkipConfirm`（**不要**先 dot-source `build-env.ps1`，那会让 `gh` 认不出登录态），tag `v0.11.9` 打在 beta 上，发完 `curl` 一次 main 上的 `latest.json` 核对。
