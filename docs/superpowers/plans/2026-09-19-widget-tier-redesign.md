# 小组件尺寸分档重做 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把桌面小组件的「三个版式摊到七个高度」改成「五档高度一一对应」：矮档是未来 n 天的列表（2/3/5 天），高档是网格（一周或两周）+ 下方今日信息卡片。

**Architecture:** Dart 侧快照多带一份「今日卡片」的数据；原生侧把「槽位」与「内容」拆开 —— 外层布局只摆空的 `FrameLayout` 槽位，渲染时用 `RemoteViews.addView` 把同一张「行 / 格」布局塞进 N 个槽位。行高与格高**固定**，多出来的高度是留白（整体垂直居中），不再把行拉长。

**Tech Stack:** Flutter 3.47 / Dart 3.13 · Android `AppWidgetProvider` + `RemoteViews`（含 `addView` 嵌套，无新依赖）· `java.time` · Riverpod · Drift

**Spec:** `docs/superpowers/specs/2026-09-19-widget-tier-redesign-design.md` —— 每一处取舍都论证自它；执行时两份一起读。它又建于 `docs/superpowers/specs/2026-09-18-home-widget-design.md` 之上（术语与两条不变量沿用）。

## Global Constraints

- **版本号**：目标 `0.8.6+97`。`X.Y` 由**用户**决定，AI 只能改末位 `Z` 与 `build`。`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` **两处必须同步**（`app/test/app_info_test.dart` 盯着）。
- **不要跑 `dart format`** —— 工具链是新版 tall style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `flutter analyze`。
- **构建 / 测试的环境变量**（bash 里必须先 export，否则 Gradle 会去 `~/.gradle` 下载到超时）：
  ```bash
  export JAVA_HOME=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/jdk
  export ANDROID_HOME=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/android-sdk
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export GRADLE_USER_HOME=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/gradle-home
  export PUB_CACHE=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/pub-cache
  export ANDROID_USER_HOME=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/android-user
  export PATH=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH
  ```
- **装真机必须 `flutter build apk --release`**（手机上是 release 密钥签的；debug APK 会 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，卸载重装会丢用户的真实排班数据）。
- **`RemoteViews` 视图白名单**：布局只用 `FrameLayout` / `LinearLayout` / `RelativeLayout` / `GridLayout`；控件只用 `TextView` / `ImageView` / `Button` / `ProgressBar` / `Chronometer` / `TextClock`。⚠️ 白名单靠 `@RemoteView` 注解过滤，**`android.view.View` 与 `android.widget.Space` 都没有该注解** —— 整张卡片会渲染不出来。画分隔线/占位一律用 `ImageView`。
- **Kotlin 侧用户可见文案一个字面量都不许出现**（中文只允许出现在日志串与注释里，那是仓库既有惯例）。
- **快照格式版本 `kWidgetSnapshotVersion` 与 `WidgetStore.parse` 里的字面量是双边协议**，改一边必须同步另一边。
- **测试只增不减**（当前 255 条）。
- **本设计的两条不变量**（承自 2026-09-18 那份 spec）：**(A)** 原生零 i18n、零日期格式化、零排班引擎；**(B)** 相对文案按「偏移」索引，不按「日期」烘焙。

---

## 给执行者的先导事实

### A. 真机尺寸（2026-09-19 实测，本设计的全部依据）

Redmi 25102RKBEC，400dp 宽屏 / 480dpi，横向 4 列。小组件拉满 4 列时**宽 328dp**。高度七个可达值，**步长 95dp 的等差数列**：

```
1 行 63dp   2 行 158dp   3 行 253dp   4 行 348dp   5 行 443dp   6 行 538dp   7 行 633dp
```

**要再测一次**（例如换了机器，或要确认拖动没漏档）：

```bash
"$ADB" logcat -c                      # 先清缓冲
# 让用户从最矮慢慢拉到最高，每个能停住的高度停一下（停住才触发上报）
"$ADB" logcat -d -s ShiftAssistant | grep "ShiftWidgetProvider: id="
```

### B. 真机上的四条坑（都踩过，别再踩）

1. **触发快照推送必须先 force-stop**：App 已在前台时 `am start` 只走 `onNewIntent`、不重跑 `initState`，那条推送路径根本不会发生。
   ```bash
   "$ADB" shell am force-stop com.daoban.shiftassistantpro
   "$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity
   ```
2. **测「点小组件」要用 `am kill` 而不是 `am force-stop`** —— force-stop 会把包置为 stopped 态，MIUI 桌面据此发 `MAIN/LAUNCHER` 意图时会**丢掉 extras**，点击日期不生效，看起来像功能坏了。
3. **改了小组件的资源色之后，验证前先重启桌面**（`"$ADB" shell am force-stop com.miui.home` + `input keyevent KEYCODE_HOME`）—— 小米桌面按**资源 id** 缓存 drawable，`install -r` 换了内容但 id 不变，它会继续用旧缓存重绘。
4. **小米/HyperOS 上标准 Android 小组件不进原生那一栏**，藏在「支持小部件的应用」→「安卓小部件」里；长按应用图标也不弹入口。

### C. 用户桌面上已绑定一个实例

`id=34`、4 列宽。所以每一档都能真机出图 —— **这是本设计的核心验收手段**。

---

## 文件结构

**新增（Kotlin）**

| 文件 | 职责 |
|---|---|
| `WidgetTier.kt` | 改写：五档 + 宽度闸门。纯函数，一个文件一件事 |
| `WidgetRenderer.kt` | 改写：五个渲染函数（列表三档 / 网格两档 / 今日卡片）+ `addView` 装配 |
| `WidgetChip.kt` | 扩一个 `ring()`（今日卡片里那三个徽章的动态底色胶囊） |

**新增（资源，`app/android/app/src/main/res/layout/`）**

| 文件 | 职责 |
|---|---|
| `widget_list_compact.xml` | 2 个行槽位，每个 22dp |
| `widget_list.xml` | 5 个行槽位，每个 40dp |
| `widget_row.xml` | **一张**行（被上两者共用）：色点 + 相对称法 + 日期 + 班次名 + 时间 |
| `widget_grid_week.xml` | 8 个格槽位（4×2） |
| `widget_grid_fortnight.xml` | 16 个格槽位（4×4） |
| `widget_cell.xml` | **一张**格（被上两者共用）：日期 + 班次胶囊 |
| `widget_today_card.xml` | 今日卡片：色条 + 日期 + 今日徽章 + 待办徽章 + 农历 + 色点/班次/已调班徽章 + 时间 + 其他班组 |
| `widget_crew_chip.xml` | **一张**班组胶囊（被今日卡片用 4 次） |

**删除**：`widget_small.xml` / `widget_medium.xml` / `widget_large.xml`（Task 7 做）

**修改（Dart）**：`widget_snapshot.dart`（加 `todayCard` 与 `todayTodoCount` 入参）/ `widget_service.dart`（传待办数）/ `home_shell.dart`（把待办数喂进去）

**修改（测试）**：`widget_snapshot_test.dart`（扩）/ `widget_layout_whitelist_test.dart`（扩到新布局）/ 新建 `widget_tier_thresholds_test.dart`

**修改（Kotlin）**：`WidgetStore.kt`（解析新字段）/ `ShiftWidgetProvider.kt`（requestCode 基数 16→32 无处可改，实际在 `WidgetRenderer`）

---

## Task 1: 验证 `addView` 嵌套（这道闸不过，后面全部作废）

`RemoteViews.addView(viewId, nested)` 上一版**有意回避过**（当时的理由是「没有真机可验，不在同一轮里引入第二处未知」）。现在手机在手上，先把它验掉 —— 因为后面五档布局全建在它上面。

**Files:**
- Modify（临时，之后回退）：`app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`
- Create（临时，之后删除）：`app/android/app/src/main/res/layout/zz_nested_probe.xml`
- Modify：`docs/superpowers/specs/2026-09-19-widget-tier-redesign-design.md`（§5.4 回写结论）

**Interfaces:**
- 本任务不产出可复用的接口。产出的是**一个结论**：`addView` 嵌套能不能用、槽位要不要 `FrameLayout`。

- [ ] **Step 1: 写一张最小探针布局**

创建 `app/android/app/src/main/res/layout/zz_nested_probe.xml` —— **必须用 `FrameLayout` 当槽位**（`LinearLayout` 的默认 LayoutParams 是 `WRAP_CONTENT`，嵌套内容不会填满）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/zz_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:background="#CC101018"
    android:padding="8dp">

    <!-- 槽位 1：固定 40dp 高 -->
    <FrameLayout
        android:id="@+id/zz_slot1"
        android:layout_width="match_parent"
        android:layout_height="40dp" />

    <!-- 槽位 2：与槽位 1 同构，id 换成 zz_slot2 -->
    <FrameLayout
        android:id="@+id/zz_slot2"
        android:layout_width="match_parent"
        android:layout_height="40dp" />
</LinearLayout>
```

创建 `app/android/app/src/main/res/layout/zz_nested_row.xml` —— 被塞进槽位的那一行：

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/zz_row_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="horizontal"
    android:gravity="center_vertical"
    android:background="#44FF0000">

    <TextView
        android:id="@+id/zz_row_text"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:textSize="14sp"
        android:textColor="#FFFFFFFF" />
</LinearLayout>
```

- [ ] **Step 2: 临时把它接进现有的 `medium()`**

在 `WidgetRenderer.kt` 的 `medium()` **最开头**插一段临时分支（这段是脚手架，第 5 步会删）：

```kotlin
        // ⚠️ TASK1 临时探针 —— 验完必须删。用途：确认 RemoteViews.addView 的嵌套
        // 行为，尤其是「槽位用 FrameLayout 时嵌套内容会不会填满」。
        if (true) {
            val probe = RemoteViews(context.packageName, R.layout.zz_nested_probe)
            for ((i, slot) in intArrayOf(R.id.zz_slot1, R.id.zz_slot2).withIndex()) {
                val row = RemoteViews(context.packageName, R.layout.zz_nested_row)
                row.setTextViewText(R.id.zz_row_text, "SLOT ${i + 1} ${"█".repeat(8 + i * 6)}")
                probe.addView(slot, row)
            }
            return probe
        }
```

- [ ] **Step 3: 构建、安装、重启桌面、出图**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
"$ADB" shell am force-stop com.miui.home; sleep 2
"$ADB" shell input keyevent KEYCODE_HOME; sleep 4
"$ADB" shell am force-stop com.daoban.shiftassistantpro
"$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity
sleep 6
"$ADB" shell input keyevent KEYCODE_HOME; sleep 3
"$ADB" exec-out screencap -p > /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/work/probe_addview.png
```

- [ ] **Step 4: 看图，回答这两个问题**

**自己 Read 那张截图**，然后回答：

1. **两条红底的行都出现了吗？** 后面那条的白色方块比前面那条长吗？（这验的是「嵌套 RemoteViews 的内容真的被渲染出来了，不是空白」）
2. **红底填满了 40dp 的槽位高度吗？**（这验的是「槽位用 `FrameLayout` 时嵌套内容会 `MATCH_PARENT` 填满」—— 若红条只有文字那么高、上下留着深色空档，说明 LayoutParams 没按预期生效，要改用别的手段）

**若答不上来或答案是「没有」**：停下来，把现象写进报告，**不要把后面的任务继续做下去** —— 布局结构要退回 spec §5.4 的退路（逐档写死布局），那是一次重新规划。这正是本任务存在的意义。

- [ ] **Step 5: 回写 spec 的 §5.4**

把 spec 里 `### 5.4 这是本设计唯一未验证的假设` 那一节整段替换成实测结论，格式照抄下面（把括号里的内容换成你实际看到的）：

```markdown
### 5.4 `addView` 嵌套：已真机验证（2026-09-19，Task 1）

结论：**成立**。证据：`work/probe_addview.png` —— 两条 `FrameLayout` 槽位（各 40dp）里
各渲染出一条嵌套的行，红色底 `#44FF0000` **填满了槽位高度**，说明嵌套视图拿到的是
`FrameLayout` 的默认 `MATCH_PARENT` LayoutParams。

⚠️ 因此一条硬规则：**槽位必须用 `FrameLayout`**。`LinearLayout` 的默认 LayoutParams 是
`WRAP_CONTENT`，嵌套内容会缩成一小团且不报错。
```

- [ ] **Step 6: 删脚手架，确认删干净**

- 删 `zz_nested_probe.xml` 与 `zz_nested_row.xml`
- 删掉 `medium()` 里那段 `// ⚠️ TASK1 临时探针` 的 `if (true) { ... }` 整块

确认：

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
grep -rn "zz_nested\|zz_slot\|zz_row\|TASK1" android/app/src/main/ || echo "脚手架已删净 ✓"
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
```

Expected: `脚手架已删净 ✓` 且 `No issues found!`

- [ ] **Step 7: 提交（只提交文档）**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add docs/superpowers/specs/2026-09-19-widget-tier-redesign-design.md
git commit -m "docs(spec): addView 嵌套已真机验证成立 —— 槽位必须用 FrameLayout"
```

---

## Task 2: 快照扩字段（`todayCard` + 待办数）

今日卡片要照搬 App 的底栏信息卡，而快照现在没有农历、其他班组、待办数。

**Files:**
- Modify: `app/lib/features/widget/widget_snapshot.dart`
- Modify: `app/lib/features/widget/widget_service.dart`
- Modify: `app/lib/features/home/home_shell.dart`
- Test: `app/test/widget_snapshot_test.dart`

**Interfaces:**
- Consumes: `lunarOf(DateTime)`（`app/lib/domain/lunar_info.dart`）· `ShiftSchedule.teamShift(int, DateTime)` / `teamNames` / `teamCount` / `ourTeamIndex` / `dayOverrides`（`app/lib/domain/shift_rotation.dart`）
- Produces:
  - `buildWidgetSnapshot` 新签名（多一个 `required int todayTodoCount`）
  - 快照新增顶层键 `todayCard`：
    ```jsonc
    "todayCard": {
      "day": 20346,                // epochDay —— 原生用它判「这份卡片还是不是今天」
      "lunarShort": "初八",
      "lunarIsHoliday": false,
      "adjusted": false,           // 今天是否被按天改班覆盖
      "todoCount": 0,
      "crews": [ { "name": "一班", "abbr": "白", "color": 4283208703 } ]
                                   // 其他班组（**不含我们班组**）；班次数为 1 时是空数组
    }
    ```

- [ ] **Step 1: 写失败的测试**

追加到 `app/test/widget_snapshot_test.dart` 的 `main()` 里（文件末尾最后一个 `test(...)` 之后）：

```dart
  test('todayCard 带出农历、其他班组、待办数，且不含我们班组', () {
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 3,
    );
    final tc = s['todayCard']! as Map;
    expect(tc['day'], dayNumber(DateTime(2026, 9, 18)));
    expect(tc['todoCount'], 3);
    expect(tc['lunarShort'], isA<String>());
    expect(tc['lunarShort'], isNotEmpty);
    expect(tc['lunarIsHoliday'], isA<bool>());
    expect(tc['adjusted'], false);

    // 其他班组：`_schedule()` 没设 teamCount/teamOffsets，走默认的 4 个班组、
    // ourTeamIndex=0，所以「其他班组」应当是 3 个，且名字里不含我们那个。
    final crews = (tc['crews']! as List).cast<Map>();
    expect(crews.length, 3);
    for (final c in crews) {
      expect(c['name'], isA<String>());
      expect(c['name'], isNotEmpty);
      expect(c['abbr'], isA<String>());
      expect(c['color'], isA<int>());
      expect(c['name'], isNot(crews.isEmpty ? '' : '一班'));
    }
  });

  test('班组数为 1 时 crews 是空数组（今日卡片会整块隐藏）', () {
    final solo = ShiftSchedule(
      name: '单人',
      anchorDate: DateTime.utc(2026, 9, 18),
      classes: const [
        ShiftClass(id: 11, name: '白班', abbr: '白', startMinute: 480, endMinute: 1200),
      ],
      cycle: const [0],
      teamCount: 1,
      teamNames: const ['我自己'],
      ourTeamIndex: 0,
      teamOffsets: const [0],
    );
    final s = buildWidgetSnapshot(
      schedule: solo,
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    expect((s['todayCard']! as Map)['crews'], isEmpty);
  });

  test('今天被按天改班覆盖时 adjusted 为 true', () {
    final s = buildWidgetSnapshot(
      // 9/18 在 3 天周期里是第 0 天 → 白班；覆盖成 classes[2]（休班）
      schedule: _schedule(overrides: {dayNumber(DateTime(2026, 9, 18)): 2}),
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    expect((s['todayCard']! as Map)['adjusted'], true);
  });
```

`_schedule()` 现在还不接受 `overrides` 参数 —— 给它加上（照抄 `app/test/shift_alarm_decision_test.dart` 里同名的写法）：

```dart
ShiftSchedule _schedule({Map<int, int> overrides = const {}}) => ShiftSchedule(
      name: '测试',
      anchorDate: DateTime.utc(2026, 9, 18),
      classes: const [
        ShiftClass(
            id: 11,
            name: '白班',
            abbr: '白',
            startMinute: 8 * 60 + 30,
            endMinute: 20 * 60 + 30,
            color: 0xFF4C8DFF),
        ShiftClass(
            id: 12,
            name: '夜班',
            abbr: '夜',
            startMinute: 20 * 60 + 30,
            endMinute: 8 * 60 + 30,
            color: 0xFF7A5CFF),
        ShiftClass(id: 13, name: '休班', abbr: '休', isRest: true, color: 0xFF5A5F73),
      ],
      cycle: const [0, 1, 2],
      dayOverrides: overrides,
    );
```

同时把文件里**其余**调用 `buildWidgetSnapshot` 的地方都补上 `todayTodoCount: 0`（新参数是 required，不补会编译不过）。

- [ ] **Step 2: 跑测试，确认它失败**

Run: `cd app && flutter test test/widget_snapshot_test.dart`

Expected: 编译失败 —— `No named parameter with the name 'todayTodoCount'`。

- [ ] **Step 3: 实现**

在 `app/lib/features/widget/widget_snapshot.dart` 里：

**(a)** `buildWidgetSnapshot` 的签名加一个参数：

```dart
Map<String, Object?> buildWidgetSnapshot({
  required ShiftSchedule? schedule,
  required DateTime now,
  required String themeMode,
  required int accent,
  /// 今日**未完成**待办数。今日卡片上那个「N 项待办」徽章用它。
  /// 快照拿不到待办数据（那是 Drift 里的事），所以由调用方数好传进来。
  required int todayTodoCount,
}) {
```

**(b)** 在 `return {` 之前、`final sorted = ...` 附近加一段构造 `todayCard`：

```dart
  // 今日卡片的数据。它**按日期烘焙**（农历、待办数、其他班组都是「今天」这一天的），
  // 所以带上自己的 `day` —— 跨天之后原生对表发现对不上，就走降级态而不是把旧数据
  // 当成今天显示（见 spec §6 的 ⚠️）。
  final todayDate = DateTime(today.year, today.month, today.day);
  final lunar = lunarOf(todayDate);
  final todayShift = schedule?.shiftOn(todayDate);
  final crews = <Map<String, Object?>>[];
  if (schedule != null && !schedule.isBlank) {
    for (var i = 0; i < schedule.teamCount; i++) {
      if (i == schedule.ourTeamIndex) continue; // 只看别人
      final t = schedule.teamShift(i, todayDate);
      if (t == null) continue;
      final name = i < schedule.teamNames.length
          ? schedule.teamNames[i]
          : (L10n.isEn ? 'Team ${i + 1}' : '${i + 1}班');
      crews.add({'name': name, 'abbr': t.shortLabel, 'color': t.color});
    }
  }
  final todayCard = {
    'day': dayNumber(todayDate),
    'lunarShort': lunar.shortLabel,
    'lunarIsHoliday': lunar.isLegalHoliday,
    'adjusted': schedule?.dayOverrides.containsKey(dayNumber(todayDate)) ?? false,
    'todoCount': todayTodoCount,
    // 徽章上的**文字**也在这里给全 —— 原生不许有中文字面量，而
    // `'$n 项待办'` / `'$n todos'` 是双语的。没有待办时给 null，原生据此隐藏徽章。
    'todoBadge': todayTodoCount > 0 ? L10n.pendingTodos(todayTodoCount) : null,
    'crews': crews,
  };
```

**(c)** 在返回的 map 里加两处：`'todayCard': todayCard,`（放在 `'days': days,` 旁边），以及 `labels` 里多一条 `'adjusted': L10n.adjusted,`（「已调班」/「Shift changed」，`L10n.adjusted` 已存在；原生读成 `snap.adjustedBadge`）。

**(d)** 顶部补 import：`import '../../domain/lunar_info.dart';`

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd app && flutter test test/widget_snapshot_test.dart`

Expected: `All tests passed!`（条数 = 原有 + 3）

- [ ] **Step 5: 把待办数从上层喂进来**

`app/lib/features/widget/widget_service.dart` 的 `push()` 加参数并透传：

```dart
  static Future<void> push({
    required ShiftSchedule? schedule,
    required AppSettings settings,
    required int todayTodoCount,
  }) async {
    try {
      final json = jsonEncode(buildWidgetSnapshot(
        schedule: schedule,
        now: DateTime.now(),
        themeMode: settings.themeMode.name,
        accent: settings.accentColor.toARGB32(),
        todayTodoCount: todayTodoCount,
      ));
```

`app/lib/features/home/home_shell.dart` 的 `_pushWidgetSnapshot()` 里把数字算好传进去：

```dart
  Future<void> _pushWidgetSnapshot() async {
    final async = ref.read(activeScheduleProvider);
    if (!async.hasValue) return;
    // 今日未完成待办数：与日历信息卡上那个「N 项待办」徽章同一个口径
    // （同一天、`completed == false`）。
    final today = DateTime.now();
    final events = await ref.read(appRepositoryProvider).listEvents();
    final todoCount = events
        .where((e) => !e.completed && isSameDay(e.date, today))
        .length;
    await WidgetService.push(
      schedule: async.value?.toDomain(),
      settings: ref.read(appSettingsProvider),
      todayTodoCount: todoCount,
    );
  }
```

（`isSameDay` 来自 `package:shiftassistantpro/domain/shift_rotation.dart`；`appRepositoryProvider` 的名字以 `app_repository.dart` 里实际的定义为准，若它叫别的名字，照抄 `AlarmService.rescheduleAll(repo)` 那条链路上用的那个 provider。`ScheduleEvent.completed` 的字段名也以 `app_database.dart` 为准。）

- [ ] **Step 6: 跑全量测试 + analyze**

Run: `cd app && flutter analyze && flutter test`

Expected: `No issues found!` 与全绿（255 + 3 = 258 条）

- [ ] **Step 7: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/lib/features/widget/widget_snapshot.dart app/lib/features/widget/widget_service.dart \
        app/lib/features/home/home_shell.dart app/test/widget_snapshot_test.dart
git commit -m "feat(widget): 快照带出今日卡片的数据（农历/其他班组/待办数/是否已调班）"
```

---

## Task 3: 五档分档 + 宽度闸门

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetTier.kt`
- Test: `app/test/widget_tier_thresholds_test.dart`（新建）

**Interfaces:**
- Produces:
  ```kotlin
  enum class WidgetTier { LIST_COMPACT, LIST_3, LIST_5, GRID_WEEK, GRID_FORTNIGHT;
      companion object {
          const val COMPACT_MAX_HEIGHT_DP = 110
          const val LIST3_MAX_HEIGHT_DP = 205
          const val LIST5_MAX_HEIGHT_DP = 300
          const val FORTNIGHT_MIN_HEIGHT_DP = 490
          const val GRID_MIN_WIDTH_DP = 300
          fun pick(widthDp: Int, heightDp: Int): WidgetTier
      }
  }
  ```

- [ ] **Step 1: 写失败的测试**

创建 `app/test/widget_tier_thresholds_test.dart`：

```dart
// `WidgetTier.pick` 的阈值护栏。
//
// ⚠️ `WidgetTier.pick` **在 Kotlin 侧**（`app/android/app/src/main/kotlin/com/daoban/
// shiftassistantpro/WidgetTier.kt`），Dart 测不到它本人。所以这条测试**读它的源码**
// 把四个常量抠出来，在 Dart 里重跑同一段判定 —— 有人改了阈值就会红。
//
// 为什么值得这么绕：上一版的分档只有三个阈值，而真机高度有七个可达值，结果三个版式
// 被摊到七个高度上、两个版式被拉伸 —— 那正是这一轮返工的全部起因。阈值是纯数字、
// 没有编译期保护，而这套「扫源码」的套路仓库里已有先例
// （`widget_layout_whitelist_test.dart`）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 从 `WidgetTier.kt` 里抠一个 `const val X = 数字`。
int _const(String src, String name) {
  final m = RegExp('const val $name\\s*=\\s*(\\d+)').firstMatch(src);
  expect(m, isNotNull, reason: 'WidgetTier.kt 里找不到 $name —— 是不是改名了？');
  return int.parse(m!.group(1)!);
}

void main() {
  late String src;
  late int compactMax, list3Max, list5Max, fortnightMin, gridMinWidth;

  setUpAll(() {
    final f = File(
      'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetTier.kt',
    );
    expect(f.existsSync(), true, reason: '找不到 ${f.path} —— 测试的工作目录应当是 app/');
    src = f.readAsStringSync();
    compactMax = _const(src, 'COMPACT_MAX_HEIGHT_DP');
    list3Max = _const(src, 'LIST3_MAX_HEIGHT_DP');
    list5Max = _const(src, 'LIST5_MAX_HEIGHT_DP');
    fortnightMin = _const(src, 'FORTNIGHT_MIN_HEIGHT_DP');
    gridMinWidth = _const(src, 'GRID_MIN_WIDTH_DP');
  });

  /// 与 Kotlin 侧 `pick` 逐字同构的判定。
  String pick(int w, int h) {
    if (h >= fortnightMin && w >= gridMinWidth) return 'GRID_FORTNIGHT';
    if (h >= list5Max && w >= gridMinWidth) return 'GRID_WEEK';
    if (h < compactMax) return 'LIST_COMPACT';
    if (h < list3Max) return 'LIST_3';
    if (h < list5Max) return 'LIST_5';
    return 'LIST_5'; // 高够但宽不够：降级为最长列表
  }

  test('四个边界各两侧', () {
    expect(pick(328, compactMax - 1), 'LIST_COMPACT');
    expect(pick(328, compactMax), 'LIST_3');
    expect(pick(328, list3Max - 1), 'LIST_3');
    expect(pick(328, list3Max), 'LIST_5');
    expect(pick(328, list5Max - 1), 'LIST_5');
    expect(pick(328, list5Max), 'GRID_WEEK');
    expect(pick(328, fortnightMin - 1), 'GRID_WEEK');
    expect(pick(328, fortnightMin), 'GRID_FORTNIGHT');
  });

  test('宽度闸门：299dp 不上网格、300dp 上网格', () {
    expect(pick(gridMinWidth - 1, 633), 'LIST_5');
    expect(pick(gridMinWidth, 633), 'GRID_FORTNIGHT');
    expect(pick(gridMinWidth - 1, 348), 'LIST_5');
    expect(pick(gridMinWidth, 348), 'GRID_WEEK');
  });

  test('七档真机实测值逐一落对（2026-09-19 用户拖动演示）', () {
    const measured = <int, String>{
      63: 'LIST_COMPACT',
      158: 'LIST_3',
      253: 'LIST_5',
      348: 'GRID_WEEK',
      443: 'GRID_WEEK',
      538: 'GRID_FORTNIGHT',
      633: 'GRID_FORTNIGHT',
    };
    measured.forEach((heightDp, expected) {
      expect(pick(328, heightDp), expected, reason: '实测 ${heightDp}dp 应当落在 $expected');
    });
  });

  test('阈值取在实测值的相邻中点（任一档离边界至少 40dp）', () {
    expect(compactMax, 110); // (63+158)/2
    expect(list3Max, 205); // (158+253)/2
    expect(list5Max, 300); // (253+348)/2
    expect(fortnightMin, 490); // (443+538)/2
    expect(gridMinWidth, 300);
  });
}
```

- [ ] **Step 2: 跑测试，确认它失败**

Run: `cd app && flutter test test/widget_tier_thresholds_test.dart`

Expected: FAIL —— `WidgetTier.kt 里找不到 COMPACT_MAX_HEIGHT_DP —— 是不是改名了？`

- [ ] **Step 3: 改写 `WidgetTier.kt`**

整份替换：

```kotlin
package com.daoban.shiftassistantpro

/**
 * 五档尺寸。
 *
 * 阈值全部取自**真机实测**（2026-09-19 用户拖动演示，Redmi 25102RKBEC / 400dp 宽屏 /
 * 480dpi / 横向 4 列，小组件拉满 4 列时宽 328dp）。可达高度是**步长 95dp 的等差数列**：
 *
 * ```
 * 1 行 63   2 行 158   3 行 253   4 行 348   5 行 443   6 行 538   7 行 633  （dp）
 * ```
 *
 * 阈值取在**相邻实测值的中点**，这样任一档离边界至少 40dp，不会被一两个 dp 的抖动甩出去。
 *
 * ⚠️ **档位由高度决定，宽度只当网格的闸门。** 两个入参管的是两件事，别把它们混成一个
 * 「面积够大就上网格」的判断 —— 一个 60×633dp 的细长条面积很小但高度很高，它该走列表
 * 而不是网格。
 *
 * 上一版的教训（这一轮返工的全部起因）：那时只有三个阈值，而真机有七个可达高度，
 * 于是三个版式被摊到七个高度上、两个版式被拉伸。阈值是纯数字、没有编译期保护，
 * 所以配了一条 Dart 护栏测试（`app/test/widget_tier_thresholds_test.dart`）——
 * 它读本文件里的常量、在 Dart 里重跑同一段判定，改阈值就会红。
 */
enum class WidgetTier {
    /** 两行紧凑列表（今天 + 明天），行高 22dp。 */
    LIST_COMPACT,

    /** 三行列表，行高 40dp。 */
    LIST_3,

    /** 五行列表，行高 40dp。 */
    LIST_5,

    /** 一周网格（8 格）+ 今日卡片。 */
    GRID_WEEK,

    /** 两周网格（16 格）+ 今日卡片。 */
    GRID_FORTNIGHT;

    companion object {
        const val COMPACT_MAX_HEIGHT_DP = 110
        const val LIST3_MAX_HEIGHT_DP = 205
        const val LIST5_MAX_HEIGHT_DP = 300
        const val FORTNIGHT_MIN_HEIGHT_DP = 490

        /** 网格要 4 列才排得下，4 列在这台机上实测 328dp —— 留到 300dp 有余量。 */
        const val GRID_MIN_WIDTH_DP = 300

        fun pick(widthDp: Int, heightDp: Int): WidgetTier = when {
            heightDp >= FORTNIGHT_MIN_HEIGHT_DP && widthDp >= GRID_MIN_WIDTH_DP ->
                GRID_FORTNIGHT

            heightDp >= LIST5_MAX_HEIGHT_DP && widthDp >= GRID_MIN_WIDTH_DP -> GRID_WEEK

            heightDp < COMPACT_MAX_HEIGHT_DP -> LIST_COMPACT
            heightDp < LIST3_MAX_HEIGHT_DP -> LIST_3
            // 高够但宽不够（窄长条）：降级为最长的那档列表 —— 网格排不下。
            else -> LIST_5
        }
    }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd app && flutter test test/widget_tier_thresholds_test.dart`

Expected: `All tests passed!`（4 条）

- [ ] **Step 5: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetTier.kt \
        app/test/widget_tier_thresholds_test.dart
git commit -m "feat(widget): 分档改五档、阈值按真机实测的七档高度定，并补一条 Dart 护栏"
```

---

## Task 4: 列表三档（行槽位 + 共用行布局）

**Files:**
- Create: `app/android/app/src/main/res/layout/widget_list_compact.xml`
- Create: `app/android/app/src/main/res/layout/widget_list.xml`
- Create: `app/android/app/src/main/res/layout/widget_row.xml`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`

**Interfaces:**
- Consumes: `WidgetTier`（Task 3）· `WidgetStore.Snapshot` / `Day` · `WidgetChip` · `WidgetRenderer.rootRequestCode/widgetId`
- Produces（新的私有函数，Task 7 的 `render()` 会用）：
  ```kotlin
  private fun listRows(
      context: Context, snap: WidgetStore.Snapshot, todayIndex: Int,
      widgetId: Int, rowCount: Int, rowHeightDp: Int, textSizeSp: Float,
  ): RemoteViews
  ```
  它内部按 `rowCount` 选 `widget_list_compact`（2 行）或 `widget_list`（5 行），把 `rowCount` 行塞进前 `rowCount` 个槽位。

- [ ] **Step 1: 写共用行布局**

创建 `app/android/app/src/main/res/layout/widget_row.xml`。**这张布局会被同一张卡塞进多个槽位** —— 每次都是一个新的 `RemoteViews` 实例，所以 id 重复没有问题（这正是 `addView` 套路的用法）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  列表里的**一行**。被 widget_list_compact / widget_list 共用。

  ⚠️ 根布局的 layout_height 必须是 match_parent 而不是 wrap_content：它被塞进一个
  FrameLayout 槽位，拿的是 FrameLayout 的默认 LayoutParams（MATCH_PARENT × MATCH_PARENT），
  自己再声明 match_parent 才与外层一致。

  字号**不在布局里写死** —— 紧凑档 12sp、普通档 13sp，由渲染侧
  `setTextViewTextSize` 按档位设（一张布局供两档用）。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_r_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="horizontal"
    android:gravity="center_vertical">

    <ImageView
        android:id="@+id/wg_r_dot"
        android:layout_width="8dp"
        android:layout_height="8dp"
        android:scaleType="fitXY"
        android:contentDescription="@null" />

    <TextView
        android:id="@+id/wg_r_label"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginStart="10dp"
        android:textStyle="bold"
        android:maxLines="1"
        android:ellipsize="end" />

    <TextView
        android:id="@+id/wg_r_date"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginStart="8dp"
        android:maxLines="1"
        android:ellipsize="end" />

    <TextView
        android:id="@+id/wg_r_shift"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:layout_marginStart="10dp"
        android:textStyle="bold"
        android:gravity="end"
        android:maxLines="1"
        android:ellipsize="end" />

    <TextView
        android:id="@+id/wg_r_time"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginStart="8dp"
        android:maxLines="1"
        android:ellipsize="end" />
</LinearLayout>
```

- [ ] **Step 2: 写两张槽位布局**

创建 `app/android/app/src/main/res/layout/widget_list_compact.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  紧凑列表：2 行，每行 22dp（1 行那档，实测高 63dp）。
  槽位一律用 FrameLayout —— 它的默认 LayoutParams 是 MATCH_PARENT×MATCH_PARENT，
  `RemoteViews.addView` 塞进去的内容才会填满槽位。换 LinearLayout 会缩成一小团且不报错。
  行高写死、不给 weight：上一版就是让行去分掉全部高度，所以高度一变行高就变，
  用户看到的是「每行被拉长」。多出来的高度现在是留白（见根布局的 gravity）。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_lc_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center_vertical"
    android:background="@drawable/widget_card_light"
    android:padding="8dp">

    <FrameLayout
        android:id="@+id/wg_lc_slot1"
        android:layout_width="match_parent"
        android:layout_height="22dp" />

    <FrameLayout
        android:id="@+id/wg_lc_slot2"
        android:layout_width="match_parent"
        android:layout_height="22dp" />
</LinearLayout>
```

创建 `app/android/app/src/main/res/layout/widget_list.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  普通列表：5 行，每行 40dp（2 行与 3 行那两档按 rowCount 用到前 3 或前 5 个槽位）。
  与 widget_list_compact 同构，只是行高与槽位数不同。
  槽位一律用 FrameLayout —— 它的默认 LayoutParams 是 MATCH_PARENT×MATCH_PARENT。
  行高写死、不给 weight：多出来的高度是留白（根布局 gravity="center_vertical"）。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_l5_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center_vertical"
    android:background="@drawable/widget_card_light"
    android:padding="14dp">

    <FrameLayout
        android:id="@+id/wg_l5_slot1"
        android:layout_width="match_parent"
        android:layout_height="40dp" />

    <FrameLayout
        android:id="@+id/wg_l5_slot2"
        android:layout_width="match_parent"
        android:layout_height="40dp" />

    <FrameLayout
        android:id="@+id/wg_l5_slot3"
        android:layout_width="match_parent"
        android:layout_height="40dp" />

    <FrameLayout
        android:id="@+id/wg_l5_slot4"
        android:layout_width="match_parent"
        android:layout_height="40dp" />

    <FrameLayout
        android:id="@+id/wg_l5_slot5"
        android:layout_width="match_parent"
        android:layout_height="40dp" />
</LinearLayout>
```

- [ ] **Step 3: 写渲染函数**

在 `WidgetRenderer` 里加（放在 `medium()` 原来的位置附近）：

```kotlin
    /**
     * 列表档（LIST_COMPACT / LIST_3 / LIST_5 共用）。
     *
     * [rowCount] 决定用哪张槽位布局：2 → `widget_list_compact`（22dp 行高），
     * 3 或 5 → `widget_list`（40dp 行高）。
     * [textSizeSp] 由档位给（紧凑 12、普通 13）—— 行布局里不写死字号，
     * 靠 `setTextViewTextSize` 按档设，一张布局供两档用。
     *
     * 槽位是**固定高度**、根布局 `gravity="center_vertical"`：多出来的高度成为上下
     * 均匀的留白，而不是把行拉长 —— 那是上一版被用户点名的问题。
     */
    private fun listRows(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
        rowCount: Int,
        textSizeSp: Float,
    ): RemoteViews {
        val compact = rowCount <= 2
        val v = RemoteViews(
            context.packageName,
            if (compact) R.layout.widget_list_compact else R.layout.widget_list,
        )
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            if (compact) R.id.wg_lc_root else R.id.wg_l5_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.setOnClickPendingIntent(
            if (compact) R.id.wg_lc_root else R.id.wg_l5_root,
            launchIntent(context, rootRequestCode(widgetId)),
        )

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted =
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)
        val empty = context.getColor(
            if (dark) R.color.wg_empty_dark else R.color.wg_empty_light
        )

        val slots = if (compact) {
            intArrayOf(R.id.wg_lc_slot1, R.id.wg_lc_slot2)
        } else {
            intArrayOf(
                R.id.wg_l5_slot1, R.id.wg_l5_slot2, R.id.wg_l5_slot3,
                R.id.wg_l5_slot4, R.id.wg_l5_slot5,
            )
        }

        for (row in slots.indices) {
            val i = todayIndex + row
            // 两个都要挡：快照窗口耗尽（todayIndex 靠后），以及这一档要的行数
            // 比槽位数多。越界读会被 ShiftWidgetProvider 的 try/catch 吞掉，
            // 后果不是崩而是**卡片继续显示上一次渲染的旧内容**。
            if (row >= rowCount || i >= snap.days.size) {
                v.setViewVisibility(slots[row], android.view.View.GONE)
                continue
            }
            v.setViewVisibility(slots[row], android.view.View.VISIBLE)

            val d = snap.days[i]
            val r = RemoteViews(context.packageName, R.layout.widget_row)
            // 可见性无条件设满：同一张布局被两种档位复用，宿主走 `reapply` 时
            // 只重放新的动作列表 —— 不显式设回来的视图会保持上一次的状态。
            for (id in intArrayOf(
                R.id.wg_r_dot, R.id.wg_r_label, R.id.wg_r_date, R.id.wg_r_shift,
            )) {
                r.setViewVisibility(id, android.view.View.VISIBLE)
            }

            r.setImageViewBitmap(
                R.id.wg_r_dot,
                WidgetChip.circle(
                    if (d.hasShift) d.color else empty,
                    dpToPx(context, 8),
                ),
            )
            r.setTextViewText(R.id.wg_r_label, relativeLabel(snap, i, todayIndex))
            r.setTextColor(R.id.wg_r_label, ink)
            r.setTextViewText(R.id.wg_r_date, d.dateShort)
            r.setTextColor(R.id.wg_r_date, muted)
            r.setTextViewText(
                R.id.wg_r_shift,
                if (d.hasShift) d.shiftName else d.weekday,
            )
            r.setTextColor(R.id.wg_r_shift, ink)

            if (d.timeRange == null) {
                r.setViewVisibility(R.id.wg_r_time, android.view.View.GONE)
            } else {
                r.setViewVisibility(R.id.wg_r_time, android.view.View.VISIBLE)
                r.setTextViewText(R.id.wg_r_time, d.timeRange)
                r.setTextColor(R.id.wg_r_time, muted)
            }

            for (id in intArrayOf(
                R.id.wg_r_label, R.id.wg_r_date, R.id.wg_r_shift, R.id.wg_r_time,
            )) {
                r.setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_SP, textSizeSp)
            }

            v.addView(slots[row], r)
        }
        return v
    }
```

顶部补 import：`import android.util.TypedValue`

- [ ] **Step 4: 临时接进 `render()` 看一眼（三档列表）**

把 `render()` 末尾的 `when (tier)` 临时改成（Task 7 会换成最终版）：

```kotlin
        return when (tier) {
            WidgetTier.LIST_COMPACT -> listRows(context, snap, todayIndex, widgetId, 2, 12f)
            WidgetTier.LIST_3 -> listRows(context, snap, todayIndex, widgetId, 3, 13f)
            WidgetTier.LIST_5 -> listRows(context, snap, todayIndex, widgetId, 5, 13f)
            // 网格两档与今日卡片还没做（Task 5/6），暂时也走列表，别留下编译不过的洞。
            WidgetTier.GRID_WEEK -> listRows(context, snap, todayIndex, widgetId, 5, 13f)
            WidgetTier.GRID_FORTNIGHT -> listRows(context, snap, todayIndex, widgetId, 5, 13f)
        }
```

- [ ] **Step 5: 构建、安装、三档各出一张图**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
"$ADB" shell am force-stop com.miui.home; sleep 2
"$ADB" shell input keyevent KEYCODE_HOME; sleep 4
"$ADB" shell am force-stop com.daoban.shiftassistantpro
"$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity
sleep 6
```

然后**在桌面上手动把小组件依次拉到 1 行 / 2 行 / 3 行**（每停一次跑一组）：

```bash
"$ADB" logcat -d -s ShiftAssistant | grep "ShiftWidgetProvider: id=" | tail -1   # 确认档位
"$ADB" shell input keyevent KEYCODE_HOME; sleep 2
"$ADB" exec-out screencap -p > /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/work/tier_listN.png
```

**自己 Read 这三张图**，回答：

1. 1 行（63dp）那档是**两行**、且两行都完整没被裁吗？
2. 2 行（158dp）是**三行**、行高看起来一致吗？
3. 3 行（253dp）是**五行**、行高与上一档**看起来一样**吗（而不是被拉长）？
4. 三张图的留白是不是分在上下两侧（垂直居中），而不是全堆在底部？

**若「行高被拉长」又出现了**：说明槽位没有固定高度或根布局带 `weight` —— 回去查那张槽位布局。

- [ ] **Step 6: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/android/app/src/main/res/layout/widget_list_compact.xml \
        app/android/app/src/main/res/layout/widget_list.xml \
        app/android/app/src/main/res/layout/widget_row.xml \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt
git commit -m "feat(widget): 列表三档（行槽位 + 共用行布局），行高固定、多余高度成留白"
```

---

## Task 5: 网格两档（格槽位 + 共用格布局）

**Files:**
- Create: `app/android/app/src/main/res/layout/widget_cell.xml`
- Create: `app/android/app/src/main/res/layout/widget_grid_week.xml`
- Create: `app/android/app/src/main/res/layout/widget_grid_fortnight.xml`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`

**Interfaces:**
- Produces:
  ```kotlin
  private fun gridCells(
      context: Context, snap: WidgetStore.Snapshot, todayIndex: Int,
      widgetId: Int, cellCount: Int, accent: Int,
  ): RemoteViews
  ```
  `cellCount` = 8（一周）或 16（两周）。

- [ ] **Step 1: 写共用格布局**

创建 `app/android/app/src/main/res/layout/widget_cell.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  网格里的**一格**：上行日期、下行班次胶囊。被 widget_grid_week / widget_grid_fortnight
  共用。日期色由渲染侧给 —— 「今天」那格走主色 + 加粗（`android:textStyle` 在这里写死
  bold 是不行的，因为要区分今天与其余），所以**日期默认不加粗**，
  「今天」那格的字重靠……见下方说明。

  ⚠️ 加粗**不能**走 `v.setInt(id, "setTypeface", ...)`：`TextView` 没有
  `setTypeface(int)` 重载，反射找不到方法会在宿主进程抛 `ActionException`。
  所以「今天」的日期用**主色**标记（颜色能动态设），字重保持常规。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_c_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center">

    <TextView
        android:id="@+id/wg_c_date"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:textSize="13sp"
        android:maxLines="1"
        android:ellipsize="end" />

    <FrameLayout
        android:layout_width="48dp"
        android:layout_height="22dp"
        android:layout_marginTop="4dp">

        <ImageView
            android:id="@+id/wg_c_pill"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:scaleType="fitXY"
            android:contentDescription="@null" />

        <TextView
            android:id="@+id/wg_c_abbr"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:gravity="center"
            android:textSize="12sp"
            android:textStyle="bold"
            android:maxLines="1" />
    </FrameLayout>
</LinearLayout>
```

- [ ] **Step 2: 写两张槽位布局**

创建 `app/android/app/src/main/res/layout/widget_grid_week.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  一周网格：4 列 × 2 行 = 8 格（前 7 格是今天起 7 天，末格隐藏）。
  格高**固定 56dp**、不给 rowWeight —— 上一版让格去分掉全部高度，七档高度里
  四档都落在这一套上，格子被拉到 633dp 那么高，用户的原话是「显示有点难看」。

  槽位用 FrameLayout 的理由同列表：它的默认 LayoutParams 是 MATCH_PARENT。
  宽度还是得吃 columnWeight=1（4 列等分），那个不受 addView 影响。
-->
<GridLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_gw_root"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:columnCount="4"
    android:padding="12dp">

    <FrameLayout
        android:id="@+id/wg_gw_slot1"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <!-- 同构再写 7 个：wg_gw_slot2 .. wg_gw_slot8，每个都
         layout_width="0dp" layout_height="56dp" layout_columnWeight="1" -->
</GridLayout>
```

> **`GridLayout` 的根用 `wrap_content` 高**（内容定高），外层若需要它撑满再由容器给。**八个槽位逐个写出来，不要用 `<include>`**（它在 RemoteViews 里的行为不保证）。

八个槽位全部照抄下面这 5 行、只把 `wg_gw_slot1` 的下标依次改成 2…8：

```xml
    <FrameLayout
        android:id="@+id/wg_gw_slot1"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />
```

创建 `app/android/app/src/main/res/layout/widget_grid_fortnight.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  两周网格：4 列 × 4 行 = 16 格（前 14 格是今天起 14 天，末两格隐藏）。
  与 widget_grid_week 同构，只是槽位数从 8 变 16、columnCount 仍是 4（GridLayout 自动换行）。
  格高同样**固定 56dp**，不给 rowWeight。
-->
<GridLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_gf_root"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:columnCount="4"
    android:padding="12dp">

    <!-- 16 个槽位逐个写出来：wg_gf_slot1 … wg_gf_slot16，
         每个都是下面这 5 行，只换 id 下标。 -->
    <FrameLayout
        android:id="@+id/wg_gf_slot1"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot2"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot3"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot4"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot5"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot6"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot7"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot8"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot9"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot10"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot11"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot12"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot13"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot14"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot15"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />

    <FrameLayout
        android:id="@+id/wg_gf_slot16"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />
</GridLayout>
```

- [ ] **Step 3: 写渲染函数**

```kotlin
    /**
     * 网格档（GRID_WEEK / GRID_FORTNIGHT 共用）。
     *
     * [cellCount] = 8（一周，用到前 7 格）或 16（两周，用到前 14 格）。
     * 格高固定 56dp，多出来的高度由**今日卡片**和留白吃（见 `render()` 的装配）。
     *
     * 「今天」那格（永远是最前面那一格，因为网格从今天起排）的日期走**主色** ——
     * 大卡每格只有日期 + 胶囊、没有相对称法，「今天」否则完全认不出来。
     * **不能用加粗**：`TextView` 没有 `setTypeface(int)` 重载，
     * `v.setInt(id, "setTypeface", ...)` 会在宿主进程抛 `ActionException`。
     */
    private fun gridCells(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
        cellCount: Int,
        accent: Int,
    ): RemoteViews {
        val fortnight = cellCount > 8
        val v = RemoteViews(
            context.packageName,
            if (fortnight) R.layout.widget_grid_fortnight else R.layout.widget_grid_week,
        )
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            if (fortnight) R.id.wg_gf_root else R.id.wg_gw_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )

        val muted =
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)
        val empty = context.getColor(
            if (dark) R.color.wg_empty_dark else R.color.wg_empty_light
        )

        val slots = if (fortnight) {
            intArrayOf(
                R.id.wg_gf_slot1, R.id.wg_gf_slot2, R.id.wg_gf_slot3, R.id.wg_gf_slot4,
                R.id.wg_gf_slot5, R.id.wg_gf_slot6, R.id.wg_gf_slot7, R.id.wg_gf_slot8,
                R.id.wg_gf_slot9, R.id.wg_gf_slot10, R.id.wg_gf_slot11, R.id.wg_gf_slot12,
                R.id.wg_gf_slot13, R.id.wg_gf_slot14, R.id.wg_gf_slot15, R.id.wg_gf_slot16,
            )
        } else {
            intArrayOf(
                R.id.wg_gw_slot1, R.id.wg_gw_slot2, R.id.wg_gw_slot3, R.id.wg_gw_slot4,
                R.id.wg_gw_slot5, R.id.wg_gw_slot6, R.id.wg_gw_slot7, R.id.wg_gw_slot8,
            )
        }

        // 用得到的格数：一周 7 天、两周 14 天。剩下的槽位隐藏 —— 但**不 GONE 之外的
        // 余地**：GridLayout 里 GONE 的子视图不参与布局，所以末行不会留空位。
        val used = if (fortnight) 14 else 7

        for (cell in slots.indices) {
            val i = todayIndex + cell
            if (cell >= used || i >= snap.days.size) {
                v.setViewVisibility(slots[cell], android.view.View.GONE)
                continue
            }
            v.setViewVisibility(slots[cell], android.view.View.VISIBLE)

            val d = snap.days[i]
            val c = RemoteViews(context.packageName, R.layout.widget_cell)
            c.setViewVisibility(R.id.wg_c_date, android.view.View.VISIBLE)
            c.setViewVisibility(R.id.wg_c_pill, android.view.View.VISIBLE)
            c.setViewVisibility(R.id.wg_c_abbr, android.view.View.VISIBLE)

            c.setTextViewText(R.id.wg_c_date, d.dateShort)
            // 「今天」永远是最前面那一格（网格从今天起排）。
            c.setTextColor(R.id.wg_c_date, if (cell == 0) accent else muted)

            c.setImageViewBitmap(
                R.id.wg_c_pill,
                WidgetChip.pill(
                    if (d.hasShift) d.color else empty,
                    dpToPx(context, 48),
                    dpToPx(context, 22),
                ),
            )
            c.setTextViewText(R.id.wg_c_abbr, if (d.hasShift) d.shiftAbbr else "")
            c.setTextColor(R.id.wg_c_abbr, d.abbrInk)

            v.addView(slots[cell], c)
        }
        return v
    }
```

- [ ] **Step 4: 临时接进 `render()` 看一眼（网格两档）**

把 `render()` 的 `when (tier)` 里那两行网格档改成：

```kotlin
            WidgetTier.GRID_WEEK -> gridCells(context, snap, todayIndex, widgetId, 8, snap.accent)
            WidgetTier.GRID_FORTNIGHT -> gridCells(context, snap, todayIndex, widgetId, 16, snap.accent)
```

- [ ] **Step 5: 构建安装、两档各出一张图**

同 Task 4 的构建流程，把小组件依次拉到 **4 行（348dp）** 与 **6 行（538dp）**，各截一张到 `work/tier_gridweek.png` / `work/tier_fortnight.png`。

**自己 Read 这两张图**，回答：

1. 4 行那档是 **8 格（4×2，末格空）**吗？格高看起来正常吗（不是被拉到很高）？
2. 6 行那档是 **16 格（4×4，末两格空）**吗？
3. 两档的**格高看起来一样**吗？
4. 「今天」那格的日期是**主色**、其余是灰色吗？
5. 两档下方都**还没有**今日卡片（Task 6 才做）—— 留白是不是很大？记下这个观感，Task 6 做完要对比。

- [ ] **Step 6: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/android/app/src/main/res/layout/widget_cell.xml \
        app/android/app/src/main/res/layout/widget_grid_week.xml \
        app/android/app/src/main/res/layout/widget_grid_fortnight.xml \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt
git commit -m "feat(widget): 网格两档（格槽位 + 共用格布局），格高固定 56dp"
```

---

## Task 6: 今日卡片（照搬 App 的底栏信息卡）

**Files:**
- Create: `app/android/app/src/main/res/layout/widget_today_card.xml`
- Create: `app/android/app/src/main/res/layout/widget_crew_chip.xml`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetStore.kt`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetChip.kt`
- Test: `app/test/widget_today_card_staleness_test.dart`（新建）

**Interfaces:**
- Consumes: Task 2 的快照 `todayCard`
- Produces:
  ```kotlin
  private fun todayCard(context: Context, snap: WidgetStore.Snapshot, todayIndex: Int, widgetId: Int): RemoteViews
  ```
  以及 `WidgetStore.Snapshot` 上的新属性 `todayCard: TodayCard?`（含 `day: Long`）。

- [ ] **Step 1: 写失败的测试（跨天降级）**

这条是本设计最容易静默出错的地方 —— 用一条 Dart 测试把「快照里 `todayCard.day` 一定是生成那天」这条前提钉住，剩下的判定在原生（Step 5 用真机验）：

创建 `app/test/widget_today_card_staleness_test.dart`：

```dart
// `todayCard` 的时间基准。
//
// 为什么值得单独钉：`todayCard` 里的农历、待办数、其他班组都是**生成那天**的，
// 而跨天时原生只能拿 `LocalDate.now().toEpochDay()` 去 `days[]` 对表右移 ——
// `todayCard` 右移不了。原生据此判「这份卡片还是不是今天」，对不上就走**降级态**
// （农历与其他班组留空），而不是把旧数据当成今天显示。
//
// 这条测试保证那个判定所依赖的前提成立：`todayCard.day` **恒等于生成那天的
// epochDay**，且与 `days[0].day` 一致。
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/widget/widget_snapshot.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
  });
  setUp(() => L10n.locale = 'zh');

  test('todayCard.day 恒等于生成那天，且与 days[0] 同天', () {
    for (final d in [
      DateTime(2026, 9, 19, 0, 5),
      DateTime(2026, 9, 19, 23, 55),
      DateTime(2026, 12, 31, 12),
      DateTime(2027, 1, 1, 0, 1),
    ]) {
      final s = buildWidgetSnapshot(
        schedule: null,
        now: d,
        themeMode: 'system',
        accent: 0xFF4F5BE8,
        todayTodoCount: 0,
      );
      final tc = s['todayCard']! as Map;
      final days = s['days']! as List;
      expect(tc['day'], dayNumber(d), reason: '生成于 $d 时应当带那天的 epochDay');
      expect(tc['day'], (days.first as Map)['day']);
    }
  });

  test('跨过午夜之后，同一个生成时刻的 todayCard.day 不再等于「今天」', () {
    final generated = DateTime(2026, 9, 19, 23, 0);
    final s = buildWidgetSnapshot(
      schedule: null,
      now: generated,
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    final cardDay = (s['todayCard']! as Map)['day'] as int;
    // 第二天再看：原生的判定就是这一句。
    final tomorrow = dayNumber(DateTime(2026, 9, 20, 0, 30));
    expect(cardDay == tomorrow, false,
        reason: '这份卡片生成于 9/19，9/20 再看时它不该被当成今天 —— 那时要走降级态');
  });
}
```

- [ ] **Step 2: 跑测试，确认通过**

这条测试测的是 Task 2 已实现的行为，所以**它一开始就该绿**（先绿后绿的护栏）。Run：

`cd app && flutter test test/widget_today_card_staleness_test.dart`

Expected: `All tests passed!`（2 条）。**若它红了，说明 Task 2 的 `todayCard.day` 写错了，回去修 Task 2 再继续。**

- [ ] **Step 3: 扩 `WidgetStore` 的解析**

在 `WidgetStore.kt` 里加数据类与解析：

```kotlin
    /** 今日卡片里的一条「其他班组」。 */
    data class Crew(
        val name: String,
        val abbr: String,
        val color: Int,
    )

    /**
     * 今日卡片的详情。
     *
     * ⚠️ [day] 是**生成那天**的 epochDay。农历、待办数、其他班组都是那天的 ——
     * 跨天之后这份数据就过期了，渲染前必须拿它跟 `LocalDate.now().toEpochDay()`
     * 比一下：对不上就走降级态（农历与其他班组留空，只用 `days[todayIndex]` 里
     * 那份按日期烘焙的数据）。**绝不能把旧数据当成今天显示。**
     */
    data class TodayCard(
        val day: Long,
        val lunarShort: String,
        val lunarIsHoliday: Boolean,
        val adjusted: Boolean,
        val todoCount: Int,
        val crews: List<Crew>,
    )
```

`Snapshot` 加一个字段 `val todayCard: TodayCard?`；`parse()` 里解析（照抄既有 `optXxx` 的宽容写法，**`lunarShort` 用 `optString` 前先 `isNull` 判**，理由见下面那条注释）：

```kotlin
        // ⚠️ `optString(name, fallback)` 只在**键不存在**时才给 fallback；键存在而值是
        // JSON `null` 时它返回**四字符串 `"null"`**（Android 的 org.json 刻意与参考实现
        // 逐 bug 兼容，见 AOSP issue 13830）。Dart 侧有可空字段时一律先 isNull 判。
        val tcObj = o.optJSONObject("todayCard")
        val todayCard = tcObj?.let { t ->
            val crewArr = t.optJSONArray("crews") ?: JSONArray()
            TodayCard(
                day = t.optLong("day", -1L),
                lunarShort = t.optString("lunarShort", ""),
                lunarIsHoliday = t.optBoolean("lunarIsHoliday", false),
                adjusted = t.optBoolean("adjusted", false),
                todoCount = t.optInt("todoCount", 0),
                crews = (0 until crewArr.length()).mapNotNull { k ->
                    val c = crewArr.optJSONObject(k) ?: return@mapNotNull null
                    Crew(
                        name = c.optString("name", ""),
                        abbr = c.optString("abbr", ""),
                        color = c.optInt("color", 0),
                    )
                },
            )
        }
```

（`Snapshot(...)` 的构造里加 `todayCard = todayCard,`。）

- [ ] **Step 4: 给 `WidgetChip` 加一个胶囊描边变体**

今日卡片上的三个徽章（「今天」「N 项待办」「已调班」）都是「14% 淡染底 + 45% 同色描边」的胶囊，颜色随主色/班次色动 —— 静态 `<shape>` 做不到，所以照抄 `WidgetChip` 已有的路子再画一种：

```kotlin
    /**
     * 淡染胶囊：14% 底 + 45% 描边，圆角为高度的一半。
     *
     * App 里那三个徽章（「今天」「N 项待办」「已调班」）是同一族配方，见
     * `calendar_screen.dart` 里 `_todayBadge` 附近的注释。小组件这侧颜色是动态的
     * （主色用户可选、已调班跟当天班次色走），静态 `<shape>` 做不到，所以画位图。
     */
    fun tintedChip(color: Int, wPx: Int, hPx: Int): Bitmap {
        val width = wPx.coerceAtLeast(1)
        val height = hPx.coerceAtLeast(1)
        val key = "tint:$color:$width:$height"
        cache.get(key)?.let { return it }

        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val r = height / 2f
        val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
        val radius = r.coerceAtMost(minOf(width, height) / 2f)

        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            alpha = 36 // 0x24 ≈ 14%
            style = Paint.Style.FILL
        }
        canvas.drawRoundRect(rect, radius, radius, fill)

        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            alpha = 115 // 0x73 ≈ 45%
            style = Paint.Style.STROKE
            strokeWidth = height * 0.08f
        }
        val inset = stroke.strokeWidth / 2f
        canvas.drawRoundRect(
            RectF(inset, inset, width - inset, height - inset),
            radius, radius, stroke,
        )
        cache.put(key, bmp)
        return bmp
    }
```

（需要 `import android.graphics.RectF` —— 文件里已有。）

- [ ] **Step 5: 写今日卡片的布局与渲染**

创建 `app/android/app/src/main/res/layout/widget_crew_chip.xml`（被塞进今日卡片的 4 个班组槽位）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_cc_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="horizontal"
    android:gravity="center_vertical">

    <FrameLayout
        android:layout_width="14dp"
        android:layout_height="14dp">

        <ImageView
            android:id="@+id/wg_cc_bg"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:scaleType="fitXY"
            android:contentDescription="@null" />

        <ImageView
            android:id="@+id/wg_cc_dot"
            android:layout_width="8dp"
            android:layout_height="8dp"
            android:layout_gravity="center"
            android:scaleType="fitXY"
            android:contentDescription="@null" />
    </FrameLayout>

    <TextView
        android:id="@+id/wg_cc_text"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginStart="6dp"
        android:textSize="11sp"
        android:maxLines="1"
        android:ellipsize="end" />
</LinearLayout>
```

创建 `app/android/app/src/main/res/layout/widget_today_card.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  今日卡片。照搬 App 底栏信息卡的**完整版**（calendar_screen.dart 的 _infoCard），
  元素与配方逐项见 spec §7。

  ⚠️ 三个徽章（今天 / N 项待办 / 已调班）都是「FrameLayout 固定宽高 + 底下铺一张淡染
  胶囊位图 + 上面一个居中 TextView」。**宽度必须写死** —— RemoteViews 在渲染时量不到
  文字宽度，只能按固定宽度画、文字居中、超长省略。宽度按**英文**留余量
  （「Shift changed」比「已调班」长得多）。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_tc_root"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:background="@drawable/widget_card_light"
    android:padding="14dp">

    <!-- 1. 日期行：色条 + 日期 + 今日徽章 + 待办徽章 -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical">

        <ImageView
            android:id="@+id/wg_tc_bar"
            android:layout_width="4dp"
            android:layout_height="18dp"
            android:scaleType="fitXY"
            android:contentDescription="@null" />

        <TextView
            android:id="@+id/wg_tc_date"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="10dp"
            android:textSize="18sp"
            android:textStyle="bold"
            android:maxLines="1"
            android:ellipsize="end" />

        <FrameLayout
            android:id="@+id/wg_tc_today_wrap"
            android:layout_width="52dp"
            android:layout_height="20dp"
            android:layout_marginStart="8dp">

            <ImageView
                android:id="@+id/wg_tc_today_bg"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:scaleType="fitXY"
                android:contentDescription="@null" />

            <TextView
                android:id="@+id/wg_tc_today_text"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:gravity="center"
                android:textSize="11sp"
                android:maxLines="1"
                android:ellipsize="end" />
        </FrameLayout>

        <FrameLayout
            android:id="@+id/wg_tc_todo_wrap"
            android:layout_width="84dp"
            android:layout_height="20dp"
            android:layout_marginStart="6dp">

            <ImageView
                android:id="@+id/wg_tc_todo_bg"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:scaleType="fitXY"
                android:contentDescription="@null" />

            <TextView
                android:id="@+id/wg_tc_todo_text"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:gravity="center"
                android:textSize="11sp"
                android:maxLines="1"
                android:ellipsize="end" />
        </FrameLayout>
    </LinearLayout>

    <!-- 2. 农历（法定节假日走 holiday 红由渲染侧给色） -->
    <TextView
        android:id="@+id/wg_tc_lunar"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="8dp"
        android:textSize="13sp"
        android:maxLines="1"
        android:ellipsize="end" />

    <!-- 3. 班次行：色点 + 班次名 + 已调班徽章 -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="8dp"
        android:orientation="horizontal"
        android:gravity="center_vertical">

        <ImageView
            android:id="@+id/wg_tc_dot"
            android:layout_width="12dp"
            android:layout_height="12dp"
            android:scaleType="fitXY"
            android:contentDescription="@null" />

        <TextView
            android:id="@+id/wg_tc_shift"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="6dp"
            android:textSize="15sp"
            android:textStyle="bold"
            android:maxLines="1"
            android:ellipsize="end" />

        <FrameLayout
            android:id="@+id/wg_tc_adj_wrap"
            android:layout_width="96dp"
            android:layout_height="20dp"
            android:layout_marginStart="6dp">

            <ImageView
                android:id="@+id/wg_tc_adj_bg"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:scaleType="fitXY"
                android:contentDescription="@null" />

            <TextView
                android:id="@+id/wg_tc_adj_text"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:gravity="center"
                android:textSize="11sp"
                android:maxLines="1"
                android:ellipsize="end" />
        </FrameLayout>
    </LinearLayout>

    <!-- 4. 时间。另起一行：挤在班次名那一行会在窄宽下把时间全截掉（App 里踩过）。
         左边缩进 18dp = 色点 12 + 间距 6，与上一行的班次名对齐。 -->
    <TextView
        android:id="@+id/wg_tc_time"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="2dp"
        android:layout_marginStart="18dp"
        android:textSize="13sp"
        android:maxLines="1"
        android:ellipsize="end" />

    <!-- 5. 其他班组：固定 4 个槽位（多于 4 个的丢掉，spec §7 已记这个上限）。
         槽位是 FrameLayout + 等分权重；嵌套的 chip 拿到 MATCH_PARENT 正好填满。 -->
    <LinearLayout
        android:id="@+id/wg_tc_crew_row"
        android:layout_width="match_parent"
        android:layout_height="22dp"
        android:layout_marginTop="8dp"
        android:orientation="horizontal">

        <FrameLayout
            android:id="@+id/wg_tc_crew_slot1"
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="1" />

        <FrameLayout
            android:id="@+id/wg_tc_crew_slot2"
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="1" />

        <FrameLayout
            android:id="@+id/wg_tc_crew_slot3"
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="1" />

        <FrameLayout
            android:id="@+id/wg_tc_crew_slot4"
            android:layout_width="0dp"
            android:layout_height="match_parent"
            android:layout_weight="1" />
    </LinearLayout>
</LinearLayout>
```

然后在 `WidgetRenderer` 里加：

```kotlin
    /**
     * 今日卡片。照搬 App 底栏信息卡的**完整版**（`calendar_screen.dart` 的 `_infoCard`，
     * 不是 `compact` 版），元素与配方逐项对照 spec §7。
     *
     * ⚠️ **跨天降级**：`todayCard` 里的农历、待办数、其他班组都是**生成那天**的，
     * 而跨天刷新时原生只能对表右移、重算不了。所以先拿 `todayCard.day` 跟今天比：
     * 对不上就把这三样留空，只显示 `days[todayIndex]` 里那份按日期烘焙的数据
     * （日期、班次、时间）。**绝不把旧数据当成今天显示。**
     */
    private fun todayCard(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_today_card)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_tc_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.setOnClickPendingIntent(
            R.id.wg_tc_root,
            launchIntent(context, rootRequestCode(widgetId)),
        )

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted =
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)

        // 日期/班次/时间/色点一律取 `days[todayIndex]` 而**不是** `todayCard` ——
        // `days[]` 会被原生对表右移、永远是对的；`todayCard` 不会。
        val d = snap.days[todayIndex]
        val tc = snap.todayCard
        val stale = tc == null || tc.day != LocalDate.now().toEpochDay()

        // ── 1. 日期行 ──
        v.setImageViewBitmap(
            R.id.wg_tc_bar,
            WidgetChip.bar(
                if (d.hasShift) d.color else snap.accent,
                dpToPx(context, 4),
                dpToPx(context, 18),
            ),
        )
        v.setTextViewText(R.id.wg_tc_date, d.dateShort)
        v.setTextColor(R.id.wg_tc_date, ink)

        // 「今天」徽章。宽度写死在布局里 —— RemoteViews 量不到文字宽度。
        v.setImageViewBitmap(
            R.id.wg_tc_today_bg,
            WidgetChip.tintedChip(snap.accent, dpToPx(context, 52), dpToPx(context, 20)),
        )
        v.setTextViewText(R.id.wg_tc_today_text, snap.today)
        v.setTextColor(R.id.wg_tc_today_text, snap.accent)

        // 「N 项待办」徽章。`todoBadge` 为空（没有待办）或快照跨天 → 整块隐藏。
        val todoText = if (stale) null else tc.todoBadge
        if (todoText == null) {
            v.setViewVisibility(R.id.wg_tc_todo_wrap, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_todo_wrap, android.view.View.VISIBLE)
            v.setImageViewBitmap(
                R.id.wg_tc_todo_bg,
                WidgetChip.tintedChip(snap.accent, dpToPx(context, 84), dpToPx(context, 20)),
            )
            v.setTextViewText(R.id.wg_tc_todo_text, todoText)
            v.setTextColor(R.id.wg_tc_todo_text, snap.accent)
        }

        // ── 2. 农历：跨天就隐藏（它是生成那天的） ──
        if (stale) {
            v.setViewVisibility(R.id.wg_tc_lunar, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_lunar, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_tc_lunar, tc.lunarShort)
            v.setTextColor(
                R.id.wg_tc_lunar,
                if (tc.lunarIsHoliday) {
                    context.getColor(R.color.wg_holiday)
                } else {
                    muted
                },
            )
        }

        // ── 3. 班次行 ──
        v.setImageViewBitmap(
            R.id.wg_tc_dot,
            WidgetChip.circle(
                if (d.hasShift) {
                    d.color
                } else {
                    context.getColor(if (dark) R.color.wg_empty_dark else R.color.wg_empty_light)
                },
                dpToPx(context, 12),
            ),
        )
        v.setTextViewText(R.id.wg_tc_shift, if (d.hasShift) d.shiftName else d.weekday)
        v.setTextColor(R.id.wg_tc_shift, ink)

        // 「已调班」徽章：底色跟当天班次色走（与 App 信息卡的 `_adjustedBadge` 同源）。
        if (stale || !tc.adjusted) {
            v.setViewVisibility(R.id.wg_tc_adj_wrap, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_adj_wrap, android.view.View.VISIBLE)
            v.setImageViewBitmap(
                R.id.wg_tc_adj_bg,
                WidgetChip.tintedChip(d.color, dpToPx(context, 96), dpToPx(context, 20)),
            )
            v.setTextViewText(R.id.wg_tc_adj_text, snap.adjustedBadge)
            v.setTextColor(R.id.wg_tc_adj_text, d.color)
        }

        // ── 4. 时间 ──
        if (d.timeRange == null) {
            v.setViewVisibility(R.id.wg_tc_time, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_time, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_tc_time, d.timeRange)
            v.setTextColor(R.id.wg_tc_time, muted)
        }

        // ── 5. 其他班组：跨天就整行隐藏（那是生成那天的） ──
        val crews = if (stale) emptyList() else tc.crews.take(4)
        val crewSlots = intArrayOf(
            R.id.wg_tc_crew_slot1, R.id.wg_tc_crew_slot2,
            R.id.wg_tc_crew_slot3, R.id.wg_tc_crew_slot4,
        )
        if (crews.isEmpty()) {
            v.setViewVisibility(R.id.wg_tc_crew_row, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_crew_row, android.view.View.VISIBLE)
            for (slot in crewSlots.indices) {
                if (slot >= crews.size) {
                    v.setViewVisibility(crewSlots[slot], android.view.View.GONE)
                    continue
                }
                v.setViewVisibility(crewSlots[slot], android.view.View.VISIBLE)
                val crew = crews[slot]
                val chip = RemoteViews(context.packageName, R.layout.widget_crew_chip)
                chip.setImageViewBitmap(
                    R.id.wg_cc_bg,
                    WidgetChip.tintedChip(crew.color, dpToPx(context, 14), dpToPx(context, 14)),
                )
                chip.setImageViewBitmap(
                    R.id.wg_cc_dot,
                    WidgetChip.circle(crew.color, dpToPx(context, 8)),
                )
                chip.setTextViewText(R.id.wg_cc_text, "${crew.name} ${crew.abbr}")
                // 文字色固定走 muted：胶囊底是 14% 淡染、卡片底近不透明，两者都够对比度。
                // 这里**有意偏离** App 的 `AppTokens.inkFor` —— 那套「按底色算可读色」要
                // luminance 计算，为一行 11sp 的小字在原生复刻一份不值当，而快照里也没有
                // 现成的对比色可拿。
                chip.setTextColor(R.id.wg_cc_text, muted)
                v.addView(crewSlots[slot], chip)
            }
        }

        return v
    }
```

**这一步还牵出四个必须一起补的东西**（不补就编译不过或渲染成空白）：

1. **`WidgetStore.Snapshot` 加 `val adjustedBadge: String`**（顶层 `labels.adjusted` 那条，见下面 Task 2 的补充）与 `TodayCard.todoBadge: String?`。
2. **`res/values/widget_colors.xml` 加一个 `<color name="wg_holiday">#E53935</color>`**（照抄 `AppTokens.holiday`）。
3. **`WidgetChip.tintedChip`**（Task 6 Step 4 已给）。
4. **`import java.time.LocalDate`**（`WidgetStore.kt` 里已有，`WidgetRenderer.kt` 里可能要补）。

  > ⚠️ **徽章的文字必须在 Dart 侧生成。** 快照的 `todayCard.todoCount` 是个**数字**，而原生不许有中文字面量（`"$n 项待办"` / `"$n todos"` 是双语）。所以 **Task 2 要补两个字段**：
  > 1. `todayCard.todoBadge`（`String?`）—— `todayTodoCount > 0 ? L10n.pendingTodos(todayTodoCount) : null`，为空时原生整块隐藏徽章。
  > 2. 顶层 `labels` 里加 `'adjusted': L10n.adjusted`（`L10n.adjusted` 已存在，就是「已调班」/「Shift changed」）—— 原生读成 `snap.adjustedBadge`。
  >
  > 「今天」徽章的文字**不用新加**：复用顶层 `labels.today`（原生侧的 `snap.today`）即可。
  >
  > 这三处都体现同一条不变量（原生零 i18n），spec §7 只说了「文字来自快照」没点到徽章这一层 —— 执行 Task 2 时按这里的补充做，并在 spec 的修订记录里补一笔。

- [ ] **Step 6: 装配进 `render()`（网格两档 = 网格 + 卡片）**

```kotlin
    private fun gridWithCard(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
        cellCount: Int,
    ): RemoteViews {
        // 纵向：网格（内容定高）→ 今日卡片。多余的竖直空间由根布局的
        // gravity="center_vertical" 变成上下均匀留白 —— 不把任何一块拉长。
        val v = RemoteViews(context.packageName, R.layout.widget_grid_with_card)
        v.addView(R.id.wg_gwc_grid_slot, gridCells(context, snap, todayIndex, widgetId, cellCount, snap.accent))
        v.addView(R.id.wg_gwc_card_slot, todayCard(context, snap, todayIndex, widgetId))
        return v
    }
```

需要**再建一张**装配布局 `app/android/app/src/main/res/layout/widget_grid_with_card.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  网格 + 今日卡片的**装配壳**：两个纵向槽位，内容由渲染侧 addView 塞进去。
  根布局 gravity="center_vertical" —— 多出来的高度成为上下均匀留白，
  而不是把网格或卡片拉长（上一版就是让内容分掉全部高度才「难看」）。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_gwc_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center_vertical"
    android:background="@drawable/widget_card_light"
    android:padding="4dp">

    <FrameLayout
        android:id="@+id/wg_gwc_grid_slot"
        android:layout_width="match_parent"
        android:layout_height="wrap_content" />

    <FrameLayout
        android:id="@+id/wg_gwc_card_slot"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="6dp" />
</LinearLayout>
```

> ⚠️ **两个槽位是 `wrap_content` 高**，而嵌套内容会被给 `MATCH_PARENT`。在 `wrap_content` 的 `FrameLayout` 里，`MATCH_PARENT` 的子视图按**内容**测量 —— 所以网格与卡片各自保持自己的内容高度，不会被拉长。**这一条要在真机上确认**（Step 7 的第 3 问），若发现被拉长，就把槽位改成固定高度。

同时：网格自身的根背景要去掉（外壳已经有背景了），否则会出现双层卡片边。把 `widget_grid_week.xml` / `widget_grid_fortnight.xml` 的根 `android:background` 删掉，并给 `gridCells` 加一个 `withBackground: Boolean = true` 参数由调用方决定 —— 或者更简单：**卡片底色只画一层**，把 `setBackgroundResource` 从 `gridCells` 里挪到 `gridWithCard` 的根上，`gridCells` 不再设背景。

- [ ] **Step 7: 构建安装、逐档出图并回答**

按 Task 4 的流程构建安装，把小组件依次拉到 **4 行 / 5 行 / 6 行 / 7 行**，各截一张。**自己 Read 它们**，回答：

1. 4 行那档：网格（8 格）+ 今日卡片都在吗？卡片里的**农历、其他班组、「N 项待办」**（如果有待办）都在吗？
2. 5 行（443dp）那档：多出来的高度是不是变成了**留白**，网格与卡片都没被拉长？
3. 6/7 行那档：网格变成 **16 格**了吗？留白是不是更大了？
4. 卡片里的文字与卡片底**读得清**吗（这一版是近不透明的深/浅卡）？
5. **留白量**：把 6 行与 7 行的图放在一起看，说说你的判断 —— 是「可以接受」，还是「太空了、需要让格子长大一点」。**这是 spec §4.2 留给真机定的一件事，你的判断就是结论。**

- [ ] **Step 8: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/android/app/src/main/res/layout/widget_today_card.xml \
        app/android/app/src/main/res/layout/widget_crew_chip.xml \
        app/android/app/src/main/res/layout/widget_grid_with_card.xml \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetStore.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetChip.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt \
        app/lib/features/widget/widget_snapshot.dart \
        app/test/widget_today_card_staleness_test.dart
git commit -m "feat(widget): 今日卡片（照搬 App 信息卡）+ 跨天降级"
```

---

## Task 7: 收口（五档分派、requestCode 扩槽、删旧布局、守门测试扩）

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`
- Modify: `app/test/widget_layout_whitelist_test.dart`
- Delete: `app/android/app/src/main/res/layout/widget_small.xml` / `widget_medium.xml` / `widget_large.xml`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`（`empty()` 改走列表档布局）

- [ ] **Step 1: 收口 `render()` 的分派**

```kotlin
        return when (tier) {
            WidgetTier.LIST_COMPACT -> listRows(context, snap, todayIndex, widgetId, 2, 12f)
            WidgetTier.LIST_3 -> listRows(context, snap, todayIndex, widgetId, 3, 13f)
            WidgetTier.LIST_5 -> listRows(context, snap, todayIndex, widgetId, 5, 13f)
            WidgetTier.GRID_WEEK -> gridWithCard(context, snap, todayIndex, widgetId, 8)
            WidgetTier.GRID_FORTNIGHT -> gridWithCard(context, snap, todayIndex, widgetId, 16)
        }
```

- [ ] **Step 2: `empty()` 改走列表档布局**

`empty()` 现在用的是 `widget_small`（要删了）。改成用 `widget_list_compact`，把两个槽位都隐藏、只留提示：

```kotlin
    private fun empty(
        context: Context,
        snap: WidgetStore.Snapshot,
        widgetId: Int,
    ): RemoteViews {
        // 空表提示复用紧凑列表的壳：它最矮、空表本来也没什么可说的。
        // 两个行槽位都 GONE，提示文字挂在槽位之外 —— 所以 widget_list_compact
        // 里除了两个槽位，还要有一个常驻的 TextView `wg_lc_hint`。
        val v = RemoteViews(context.packageName, R.layout.widget_list_compact)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_lc_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.setOnClickPendingIntent(R.id.wg_lc_root, launchIntent(context, rootRequestCode(widgetId)))
        // 可见性显式设满：这张布局也被正常两行档复用，宿主 reapply 时只重放新动作。
        v.setViewVisibility(R.id.wg_lc_slot1, android.view.View.GONE)
        v.setViewVisibility(R.id.wg_lc_slot2, android.view.View.GONE)
        v.setViewVisibility(R.id.wg_lc_hint, android.view.View.VISIBLE)
        v.setTextViewText(R.id.wg_lc_hint, snap.emptyHint)
        v.setTextColor(
            R.id.wg_lc_hint,
            context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light),
        )
        return v
    }
```

**同时要给 `widget_list_compact.xml` 加一个常驻的 `TextView id=wg_lc_hint`**（`layout_width="match_parent"` `layout_height="wrap_content"` `textSize="13sp"` `maxLines="2"` `ellipsize="end"`，初始 `android:visibility="gone"`），并让 `listRows()` 在正常两行档里把它设成 `GONE`。

- [ ] **Step 3: requestCode 槽位基数 16 → 32**

```kotlin
    /**
     * 每个小组件实例占用的 requestCode 槽位数。
     *
     * 需要 `Root` + 5 个列表行 + 16 个网格格 = 22，向上取到 32。
     * 基数从 16 提到 32 之后，`Int` 溢出的 widgetId 上限从约 1.34 亿降到约 6710 万 ——
     * 仍然远够用（本机 widgetId 是 34）。
     */
    private const val REQ_SLOTS_PER_WIDGET = 32

    private fun rootRequestCode(widgetId: Int): Int =
        WIDGET_REQ_BASE + widgetId * REQ_SLOTS_PER_WIDGET

    private fun cellRequestCode(widgetId: Int, cell: Int): Int =
        WIDGET_REQ_BASE + widgetId * REQ_SLOTS_PER_WIDGET + 1 + cell
```

> 列表的 5 行如果也做「点某行跳到那天」，用 `cellRequestCode(widgetId, 16 + row)` 的槽位段（16..20），与网格的 0..15 错开。**本轮列表行不做点击**（整卡点击就够），所以只需把基数扩到 32 备将来用 —— 若你决定本轮就加，记得同步 `rootRequestCode/cellRequestCode` 的注释与 `AGENTS.md`。

**同步改 `AGENTS.md`** 里那条 requestCode 保留区间：把「`Root(n)=B+16n`、`Cell(m,c)=B+16m+1+c`」改成 32 的版本，并把溢出上限从 1.34 亿改成 6710 万。

- [ ] **Step 4: 删旧布局**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git rm app/android/app/src/main/res/layout/widget_small.xml \
       app/android/app/src/main/res/layout/widget_medium.xml \
       app/android/app/src/main/res/layout/widget_large.xml
```

- [ ] **Step 5: 守门测试扩到全部新布局**

`app/test/widget_layout_whitelist_test.dart` 现在扫 `res/layout/widget*.xml` —— 新的七张布局文件名都以 `widget` 开头，**所以它已经自动覆盖**。跑一遍确认它绿，并**再做一次「先红后绿」**：

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter test test/widget_layout_whitelist_test.dart
# 临时把 widget_cell.xml 里的某个 <ImageView 改成 <View，重跑，应当点名那一行且行号正确
# 再改回去，重跑应当绿
```

把「先红后绿」那两趟的命令与输出原文写进报告。

- [ ] **Step 6: 全量检查 + 七档出图**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter test
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
"$ADB" shell am force-stop com.miui.home; sleep 2
"$ADB" shell input keyevent KEYCODE_HOME; sleep 4
"$ADB" shell am force-stop com.daoban.shiftassistantpro
"$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity; sleep 6
```

**七档各停一次、各截一张**到 `work/final_tier1.png` … `work/final_tier7.png`，逐张 Read 后按 spec §3.1 的映射表核对：

| 档 | 应当看到 |
|---|---|
| 1 行 63dp | 两行（今天、明天），完整不裁 |
| 2 行 158dp | 三行 |
| 3 行 253dp | 五行 |
| 4 行 348dp | 8 格网格 + 今日卡片 |
| 5 行 443dp | 同 4 行，留白更多 |
| 6 行 538dp | 16 格网格 + 今日卡片 |
| 7 行 633dp | 同 6 行，留白更多 |

**另外验两条边界**：

1. **跨天降级**：把系统时间往后拨一天（设置 → 日期与时间 → 关自动 → 手改），回桌面看今日卡片是否走了降级（农历与其他班组消失、日期/班次/时间仍正确）。**验完把时间拨回自动。**
2. **窄档降级**：把小组件横向拉窄到 2 列（宽 <300dp），确认它落到列表档而不是网格。

- [ ] **Step 7: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add -A app/android/app/src/main/res/layout app/android/app/src/main/kotlin app/test AGENTS.md
git commit -m "feat(widget): 五档分派收口、requestCode 扩到 32 槽、删旧布局"
```

---

## Task 8: 收尾 —— 文档、版本号、发布

**Files:**
- Modify: `app/pubspec.yaml` · `app/lib/core/app_info.dart` · `app/lib/features/profile/app_dialogs.dart`
- Modify: `AGENTS.md` · `README.md` · `PRODUCT_SPEC.md`

- [ ] **Step 1: 版本号两处同步**

`0.8.5+96` → `0.8.6+97`（`pubspec.yaml` 的 `version:` 与 `app_info.dart` 的 `appVersion`）。

Run: `cd app && flutter test test/app_info_test.dart` — 必须绿。

- [ ] **Step 2: 更新日志**

`app_dialogs.dart` 的 `_changelogZh` / `_changelogEn`：prepend `v0.8.6`、删最旧一条、保持 10 条。**测试版规则**（只写这一版改了什么，不归纳）。

内容要点：小组件的尺寸分档重做 —— 矮的时候按高度显示 2/3/5 天的班次列表，高的时候是一周或两周的网格、下方带今日信息卡（农历、其他班组、待办）。**只说事实，不用绝对话** —— 这个项目被「假保证文案」咬过五次。

- [ ] **Step 3: 三份文档**

- `README.md`：小组件那条改写（三档 → 五档 + 今日卡片）
- `PRODUCT_SPEC.md`：§2 那条改写；抬头版本号跟着走
- `AGENTS.md`：版本史加 `0.8.6(+97) 测试版`；若 Task 7 改了 requestCode 基数，那条同步；把「五档 + 今日卡片」补进小组件那条决策

- [ ] **Step 4: 全量检查**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter test
```

Expected: `No issues found!` 与全绿（255 + 新增的若干条）

- [ ] **Step 5: 提交、打 tag、构建、发布**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git tag v0.8.6
git push origin main --tags
```

然后跑 `scripts/release.ps1`。⚠️ **要单独设 `GH_CONFIG_DIR`**（`build-env.ps1` 重定向了 `APPDATA`，`gh` 会报「未认证」）：

```powershell
$env:GH_CONFIG_DIR = "$env:USERPROFILE\AppData\Roaming\GitHub CLI"
```

它应当自动判为**预发布（测试版）**（末位 6 ≠ 0）。

- [ ] **Step 6: 七档复验（最终一轮）**

再按 Task 7 Step 6 的七档清单走一遍（代码若有变动），并补上两条真机边界：**浅色时段下的卡片观感**（若此时是深色时段，就在报告里说明未验并留给下一轮）与**点击仍然正确**（`am kill` 冷启动 + 热启动各点一次，`input tap`）。

---

## 自审记录

**Spec 覆盖**：§1（背景/目标）→ 全文；§2 六个决策 → 决策①②③在 Task 3（分档）与 Task 4/5（版式），④在 Task 6，⑤在 Task 1（验证）与 Task 4/5/6（落地），⑥在 Task 5 的 `cell == 0`；§3 映射表 → Task 3；§3.2 真机标定 → Task 7 Step 6 的七档核对；§4.1 行高固定 → Task 4 Step 2 的槽位布局；§4.2 留白 → Task 6 Step 7 第 5 问（真机定）；§5 布局结构 → Task 1（验证）+ Task 4/5/6（文件清单逐项）；§6 快照字段 → Task 2；§6 的 ⚠️ 跨天降级 → Task 6 Step 5 + Task 7 Step 6 的边界验证；§7 今日卡片配方 → Task 6；§8.1 requestCode → Task 7 Step 3；§8.2 可见性齐次 → Task 4 Step 3 与 Task 7 Step 2；§8.3 失准注释 → Task 4/5 的布局注释；§9 边界容错 → Task 4/5/6 的越界闸与 Task 7 的窄档/跨天验证；§10 不做 → 全文未涉及；§11 测试 → Task 2/3/6 的测试 + Task 7 Step 5 的守门测试 + Task 7/8 的真机清单；§12 收尾 → Task 8；§13 风险 → 逐条落到对应任务的排查步骤。

**一处对 spec 的补充**：写 Task 6 时发现三个徽章的**文字也必须由 Dart 侧给**（原生不许有中文字面量），所以给 Task 2 补了 `todayCard.todoBadge` 与 `labels.adjusted` 两个字段 —— spec §7 只说了「文字来自快照」没点到徽章这一层。执行 Task 2 时按计划里的补充做，并在 spec 的修订记录里补一笔。Task 6 还牵出一个新的资源色 `wg_holiday`（农历在法定节假日时走红），那一条是 spec §7 那张表里写了「走 `AppTokens.holiday` 红」但没说小组件侧要新加一个色值 —— 也在 spec 修订记录里补。

**类型一致性**：`WidgetTier` 的五个枚举名（`LIST_COMPACT` / `LIST_3` / `LIST_5` / `GRID_WEEK` / `GRID_FORTNIGHT`）在 Task 3 定义、Task 4/5/7 使用，逐处一致；`listRows` 与 `gridCells` 的签名在 Task 4/5 定义、Task 7 的分派里按同一签名调用；`todayCard`（Kotlin 函数名）与 `snap.todayCard`（`Snapshot` 的字段）**同名但不是一回事** —— 实现时若觉得绕，把函数改名 `renderTodayCard`，但要同时改 Task 7 的调用点。
