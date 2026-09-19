# 小组件固定档位重做 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把桌面小组件从「一个可拉伸、运行期分五档」改成**三张各自注册、各自优化的固定卡**：4×1 本周条、4×3 今日卡、4×5 整月；视觉回归 App 的设计语言（淡染胶囊、无套娃、今天走主色）。

**Architecture:** Dart 侧快照从「今天起 14 天」改成「本月 + 下月」的**绝对日期窗口**（协议 `v: 1 → 2`）；原生侧把 `ShiftWidgetProvider` 拆成三个 provider + 一个注册表，`WidgetRenderer` 按 `WidgetVariant` 分派三个渲染函数。月历的「渲染哪个月」由原生按 `LocalDate.now()` 现算，数据本来就在窗口里。刷新链路（跨天 + 班次边界）**完全沿用**。

**Tech Stack:** Flutter 3.47 / Dart 3.13 · Android `AppWidgetProvider` + `RemoteViews`（`addView` 嵌套，无新依赖）· `java.time` · Riverpod · Drift

**Spec:** `docs/superpowers/specs/2026-09-20-widget-fixed-cards-design.md` —— 每一处取舍都论证自它；执行时两份一起读。它取代 `2026-09-19-widget-tier-redesign-design.md`，并承自 `2026-09-18-home-widget-design.md` 的两条不变量。

## Global Constraints

- **版本号**：目标 `0.8.8+99`。`X.Y` 由**用户**决定，AI 只能改末位 `Z` 与 `build`。`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` **两处必须同步**（`app/test/app_info_test.dart` 盯着）。
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
  export ADB="$ANDROID_HOME/platform-tools/adb.exe"
  ```
- **装真机必须 `flutter build apk --release`**（手机上是 release 密钥签的；debug APK 会 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，卸载重装会丢用户的真实排班数据）。
- **`RemoteViews` 视图白名单**：布局只用 `FrameLayout` / `LinearLayout` / `RelativeLayout` / `GridLayout`；控件只用 `TextView` / `ImageView` / `Button` / `ProgressBar` / `Chronometer` / `TextClock`。⚠️ 白名单靠 `@RemoteView` 注解过滤，**`android.view.View` 与 `android.widget.Space` 都没有该注解** —— 整张卡片会渲染不出来。画分隔线/占位一律用 `ImageView`。
- **槽位一律 `FrameLayout`**，嵌套内容根上**显式写 `match_parent`**（v0.8.6 Task 1 真机验过这条链）。
- **Kotlin 侧用户可见文案一个字面量都不许出现**（中文只允许出现在日志串与注释里）。三张卡的全部文字 —— 周几、月份标题、班次名、空表提示、徽章 —— 都来自快照。
- **快照格式版本 `kWidgetSnapshotVersion` 与 `WidgetStore.parse` 里的字面量是双边协议**，改一边必须同步另一边。
- **测试只增不减**（当前 265 条）。
- **本设计的两条不变量**（承自 2026-09-18 那份 spec）：**(A)** 原生零 i18n、零日期格式化（周几/月份标题/班次名全部来自快照，`LocalDate` 只用来算「哪一天属于哪个月/哪一周」）；**(B)** 相对文案按「偏移」索引，不按「日期」烘焙。

---

## 给执行者的先导事实

### A. 真机尺寸（本设计的全部依据）

Redmi 25102RKBEC，400dp 宽屏 / 480dpi，横向 4 列。**4 列宽实测 328dp**（报告尺）。高度七个可达值、步长 95dp：`63 / 158 / 253 / 348 / 443 / 538 / 633`。本轮三张卡用到其中三个：

| 卡 | 报告尺 | 渲染尺（约 +15dp） |
|---|---|---|
| 4×1 本周条 | 63dp | 78dp |
| 4×3 今日卡 | 253dp | 268dp |
| 4×5 整月 | 443dp | 458dp |

改动后 `resizeMode="none"`，**不再能拖动** —— 尺寸靠 `targetCellWidth/Height`（Android 12+）与 `minWidth/minHeight` 的 `70n-30` 老公式两头声明。

### B. 真机上的四条坑（都踩过，别再踩）

1. **触发快照推送必须先 force-stop**：App 已在前台时 `am start` 只走 `onNewIntent`、不重跑 `initState`。
   ```bash
   "$ADB" shell am force-stop com.daoban.shiftassistantpro
   "$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity
   ```
2. **测「点小组件」要用 `am kill` 而不是 `am force-stop`** —— force-stop 把包置为 stopped 态，MIUI 桌面据此发 `MAIN/LAUNCHER` 时会**丢掉 extras**，点击日期不生效。
3. **改了小组件的资源色之后，验证前先重启桌面**（`"$ADB" shell am force-stop com.miui.home` + `input keyevent KEYCODE_HOME`）—— 小米桌面按**资源 id** 缓存 drawable。
4. **小米/HyperOS 上标准 Android 小组件不进原生那一栏**，藏在「支持小部件的应用」→「安卓小部件」里。

### C. 用户桌面上已绑定一个实例

`id=34`、4 列宽，**在桌面第 9 页（最后一页）**。出图前先翻页：

```bash
"$ADB" shell input keyevent KEYCODE_HOME; sleep 2
"$ADB" shell input swipe 1000 1300 200 1300 200; sleep 1   # 一页一次，翻到看见小组件
```

那一页的 a11y 层级读不到节点，只能靠截图认。

> ⚠️ **本轮的迁移：Task 4 删掉旧的 `ShiftWidgetProvider` 之后，桌面上这个实例会失效。**
> Task 4 起，验证要靠**新添加的三张卡**（picker 里「倒班助手Pro」名下会多出三条）。
> 加卡时把三张都放上去，之后的每个任务各自认领自己那张。

### D. 两把尺：报告尺 ≠ 渲染尺

`OPTION_APPWIDGET_MIN_WIDTH/HEIGHT` 是启动器**报**的值；卡片**渲染**出来的像素尺寸每轴大约 +15dp（v0.8.6 实测：报 `328×158dp`、渲染 `342.7×173.3dp`）。**尺寸声明只许对报告尺**；渲染尺只用来算「内容放不放得下」。

### E. 既有结论（本轮直接沿用，不要重新验）

- `addView` 嵌套成立，**槽位必须是 `FrameLayout`**，嵌套根要显式 `match_parent`。
- `GridLayout` 里 `GONE` 的子视图**不参与布局**，所以末行不会留空位（v0.8.6 的 8/16 格网格就是靠它）。
- ⚠️ **加粗不能走 `v.setInt(id, "setTypeface", …)`** —— `TextView` 没有 `setTypeface(int)` 重载，反射失败会在宿主进程抛 `ActionException`。「今天」只用**主色**标记。
- ⚠️ **可见性两个方向都要设满**：宿主 `reapply` 时只重放**新**动作，漏设的视图会保持上一次的状态。

---

## 文件结构

**Kotlin（`app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/`）**

| 文件 | 职责 |
|---|---|
| `WidgetVariant.kt`（新增） | `enum class WidgetVariant { WEEK_STRIP, TODAY, MONTH }` —— 三张卡的身份证 |
| `ShiftWidgetBase.kt`（新增） | 抽象基类：`onUpdate` / `onAppWidgetOptionsChanged` / `onDeleted` / `onReceive` 的公共实现，`abstract val variant` |
| `WeekStripWidgetProvider.kt` / `TodayCardWidgetProvider.kt` / `MonthWidgetProvider.kt`（新增） | 三个空壳子类 |
| `ShiftWidgets.kt`（新增） | 注册表：三个 `ComponentName`、`refreshAll` / `hasAnyInstance` / `scheduleNextRefreshIfNeeded` / `cancelRefreshIfNone` |
| `WidgetRefreshReceiver.kt`（新增） | 刷新广播的落点（不再指向某一个 provider） |
| `WidgetRenderer.kt`（改写） | `render(variant)` 分派 + `weekStrip` / `todayCard` / `monthCard` 三个渲染函数 |
| `WidgetStore.kt`（改写） | 协议 v2、`Day` 增删字段、`Snapshot` 增 `weekdays` / `months` |
| `WidgetRefreshScheduler.kt`（改写） | 目标组件换成 `WidgetRefreshReceiver` |
| `ShiftWidgetProvider.kt` / `WidgetTier.kt`（删除） | 旧版式的地基 |

**布局（`app/android/app/src/main/res/layout/`）**

| 文件 | 职责 |
|---|---|
| `widget_week_strip.xml`（新增） | 4×1 的壳：卡底 + 7 个等宽槽位 |
| `widget_strip_cell.xml`（新增） | 一格：周几 / 日数字 / 胶囊 |
| `widget_today_standalone.xml`（新增） | 4×3 的壳：卡底 + 一个槽位（嵌套今日卡） |
| `widget_today_card.xml`（改写） | 4×3 配方：大一号字 + `lunarFull` 两行（不再自画卡底） |
| `widget_month_card.xml`（新增） | 4×5 的壳：卡底 + 月份标题 + 周几行 + 42 个格槽位 |
| `widget_month_cell.xml`（新增） | 一格：日数字 / 胶囊 / 农历 |
| `widget_empty.xml`（新增） | 空表态：卡底 + 居中提示（三张卡共用） |
| `widget_placeholder.xml` / `widget_crew_chip.xml`（沿用） | 占位态 / 班组胶囊 |
| `widget_list*` / `widget_row` / `widget_grid_*` / `widget_cell` / `widget_grid_with_card`（删除） | Task 8 |

**资源**

| 文件 | 职责 |
|---|---|
| `res/xml/widget_week_strip_info.xml` / `widget_today_info.xml` / `widget_month_info.xml`（新增） | 三份 `appwidget-provider`，`resizeMode="none"` |
| `res/values/strings.xml` / `res/values-en/strings.xml`（新增） | 三张卡在 picker 里的名字（中文 / 英文） |
| `res/xml/shift_widget_info.xml`（删除） | 旧的单例声明 |

**Dart**：`features/widget/widget_snapshot.dart`（窗口 + 字段 + `v:2`）/ `test/widget_snapshot_test.dart`（改）/ `test/widget_tier_thresholds_test.dart`（删）

---

## Task 1: 探针 —— 42 格月历能不能渲染（这道闸不过，后面全部作废）

spec §14.1：月历一屏 **42 个胶囊位图**，粗算约 1.1MB，而现状最多 16 格。`WidgetChip` 的 `LruCache` 能让同一班次共用同一个 `Bitmap` **对象**，但 `RemoteViews` 把它序列化进 parcel 时**会不会去重、走不走 ashmem**，本仓从没验过这个量级。**先把它验掉** —— 后面三张卡里最复杂的一张全建在它上面。

探针同时回答第二个问题：`GridLayout` 里 **42 个槽位**（columnCount=7 × 6 行）的 `addView` 布局对不对。这一条比位图更容易出问题，而且**只有看图才知道**。

**Files:**
- Create（临时，之后删除）：`app/android/app/src/main/res/layout/zz_month_probe.xml`、`zz_probe_cell.xml`
- Modify（临时，之后回退）：`app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`
- Modify：`docs/superpowers/specs/2026-09-20-widget-fixed-cards-design.md`（§14.1 回写结论）

**Interfaces:**
- 本任务不产出可复用接口。产出的是**两个结论**：42 张位图能不能发出去、42 槽的 GridLayout 能不能排对。

- [ ] **Step 1: 生成 42 槽的探针布局**

42 个槽位手打容易错，用一次性脚本生成（产物**提交进仓库**，不是构建期生成）：

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
python - <<'PY'
slots = "\n\n".join(
    f'''    <FrameLayout
        android:id="@+id/zz_slot{i}"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />'''
    for i in range(1, 43)
)
xml = f'''<?xml version="1.0" encoding="utf-8"?>
<!--
  ⚠️ TASK1 临时探针 —— 验完必须删。
  42 个格槽位（7 列 × 6 行），形状与真·月历卡一致，区别只是标题/周几行还没做。
  它要回答两件事：① 42 张胶囊位图的 RemoteViews 能不能发出去 ② GridLayout 排 42 格对不对。
-->
<GridLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/zz_root"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:columnCount="7"
    android:background="#CC101018"
    android:padding="8dp">

{slots}
</GridLayout>
'''
open('app/android/app/src/main/res/layout/zz_month_probe.xml', 'w', encoding='utf-8').write(xml)
print('written:', len(slots.splitlines()), 'lines')
PY
```

再建那一格（`app/android/app/src/main/res/layout/zz_probe_cell.xml`）—— **故意只用 `TextView`**，比真格子简单，因为探针要压的是**位图张数**而不是版式：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- ⚠️ TASK1 临时探针 —— 验完必须删。 -->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center">

    <TextView
        android:id="@+id/zz_date"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:textSize="16sp"
        android:textColor="#FFFFFFFF" />

    <FrameLayout
        android:layout_width="40dp"
        android:layout_height="18dp"
        android:layout_marginTop="3dp">

        <ImageView
            android:id="@+id/zz_pill"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:scaleType="fitXY"
            android:contentDescription="@null" />

        <TextView
            android:id="@+id/zz_abbr"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:gravity="center"
            android:textSize="11sp"
            android:maxLines="1" />
    </FrameLayout>
</LinearLayout>
```

- [ ] **Step 2: 临时把它接进 `render()`**

在 `WidgetRenderer.render()` 的**最开头**（`if (snap == null)` 那一行之前）插一段脚手架：

```kotlin
        // ⚠️ TASK1 临时探针 —— 验完必须删。压最坏情况：42 张**颜色各不相同**的胶囊位图
        // （真卡片只有 5~6 种班次色，颜色全不同就不存在任何去重可能）。
        if (true) {
            val probe = RemoteViews(context.packageName, R.layout.zz_month_probe)
            for (i in 0 until 42) {
                val cell = RemoteViews(context.packageName, R.layout.zz_probe_cell)
                cell.setTextViewText(R.id.zz_date, "${i + 1}")
                cell.setImageViewBitmap(
                    R.id.zz_pill,
                    WidgetChip.pill(
                        0xFF000000.toInt() or (i * 6_000_000),
                        dpToPx(context, 40),
                        dpToPx(context, 18),
                    ),
                )
                cell.setTextViewText(R.id.zz_abbr, "AB")
                cell.setTextColor(R.id.zz_abbr, 0xFFFFFFFF.toInt())
                probe.addView(
                    context.resources.getIdentifier("zz_slot${i + 1}", "id", context.packageName),
                    cell,
                )
            }
            AlarmLog.info(context, "PROBE: 42 格探针已构造（42 张各不相同的胶囊位图）")
            return probe
        }
```

- [ ] **Step 3: 构建、安装、重启桌面、清日志**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
"$ADB" logcat -c
"$ADB" shell am force-stop com.miui.home; sleep 2
"$ADB" shell input keyevent KEYCODE_HOME; sleep 4
"$ADB" shell am force-stop com.daoban.shiftassistantpro
"$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity
sleep 8
```

**在桌面上把小组件拖到 5 行以上**（拖到最高更好，探针要 6 行格子才看得全）—— 此刻 `resizeMode` 还是旧的 `horizontal|vertical`，仍然拖得动。

- [ ] **Step 4: 出图 + 读日志**

```bash
"$ADB" shell input keyevent KEYCODE_HOME; sleep 2
"$ADB" exec-out screencap -p > /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/work/probe_month42.png
"$ADB" logcat -d -s ShiftAssistant | tail -20
"$ADB" logcat -d | grep -iE "TransactionTooLarge|RemoteViews|BadParcelable|IllegalArgument|AppWidget" | tail -30
```

- [ ] **Step 5: 看图，回答这三个问题**

**自己 Read `work/probe_month42.png`**：

1. **格子出现了吗？** 是不是 **7 列 × 6 行**、每格一个彩色胶囊 + 上面的数字？
2. **42 格是不是都画出来了**（不是只画了前几行、后面空白）？
3. **logcat 里有没有异常**（`TransactionTooLargeException` / `BadParcelableException` / RemoteViews 相关的报错）？

**若答案是「格子没出现」或「只出现前几行」或「日志里有 TransactionTooLarge」**：
停下来，把现象写进报告，**不要继续做后面的任务**（尤其不要做 Task 7）。按 spec §14.1 的**降级梯子**依次试，并在报告里写明试到哪一级：

1. **静态 `<shape>` + `setBackgroundTintList`**：先单独验 `View.setBackgroundTintList` 是不是 `@RemotableViewMethod`
   （`javap -v -classpath toolchain/android-sdk/platforms/android-36/android.jar android.view.View | grep -A2 setBackgroundTintList`），
   是的话把「外描边 + 内填充」拆成两层视图各带一个静态 shape、运行期 tint。
2. **月历格子退回彩色文字**（不画胶囊）—— App 自己在窄格时就是这么降级的（v0.7.1 有先例）。

这两条都是**重新规划**，别在探针任务里顺手改。

- [ ] **Step 6: 回写 spec §14.1**

把 spec 里第 1 条风险（「42 格的胶囊位图是本轮唯一未验证的技术假设」）那一整段替换成实测结论，格式照抄：

```markdown
1. ~~42 格的胶囊位图是本轮唯一未验证的技术假设~~ **已真机验证（2026-09-20，Task 1）**：
   42 张**颜色各不相同**的 40×18dp 胶囊位图（最坏情况，无任何去重可能）能正常发出并渲染，
   `work/probe_month42.png` 上是完整的 7 列 × 6 行，logcat 无 `TransactionTooLargeException`。
   结论：**按淡染胶囊做**，降级梯子保留在下面备查。
```

（把日志原文与截图路径写进去；若实际是降级路线，就写实际走的那条与证据。）

- [ ] **Step 7: 删脚手架，确认删干净**

- 删 `zz_month_probe.xml`、`zz_probe_cell.xml`
- 删 `render()` 开头那段 `// ⚠️ TASK1 临时探针` 的 `if (true) { ... }` 整块

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
grep -rn "zz_month_probe\|zz_probe_cell\|zz_slot\|PROBE:" android/app/src/main/ || echo "脚手架已删净 ✓"
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
```

Expected: `脚手架已删净 ✓`、`No issues found!`、`√ Built …app-release.apk`。

- [ ] **Step 8: 提交（只提交文档）**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add docs/superpowers/specs/2026-09-20-widget-fixed-cards-design.md
git commit -m "docs(spec): 42 格月历的位图与 GridLayout 已真机验证"
```

---

## Task 2: 快照协议 v2（Dart 侧：窗口 + 字段）

**Files:**
- Modify: `app/lib/features/widget/widget_snapshot.dart`
- Test: `app/test/widget_snapshot_test.dart`

**Interfaces:**
- Consumes: `dayNumber` / `dateOnly`（`app/lib/domain/shift_rotation.dart`）· `L10n.weekday(int)` / `L10n.yearMonth(DateTime)` / `L10n.monthDay`（`app/lib/core/l10n.dart`）· `LunarInfo.shortLabel` / `fullDescription` / `isLegalHoliday`（`app/lib/domain/lunar_info.dart`）
- Produces（协议 v2，Task 3 的 Kotlin 侧按它解析）：
  ```jsonc
  {
    "v": 2,
    "days": [ { "day": 20346, "weekday": "周日", "dateShort": "9月20日",
                "hasShift": true, "isRest": false, "shiftName": "白班", "shiftAbbr": "白",
                "color": 4283208703, "timeRange": "08:30 – 20:30",
                "lunarShort": "初八", "lunarIsHoliday": false } ],
                // ⚠️ 相对 v1：删 abbrInk、增 lunarShort / lunarIsHoliday
    "weekdays": ["周一", "…", "周日"],           // 7 条，索引 0 = 周一
    "months": [ { "y": 2026, "m": 8, "title": "2026年8月" }, … ],  // 窗口覆盖到的月，升序
    "todayCard": { …, "lunarFull": "农历 丙午年 八月初八 · 生肖马 · …" }
  }
  ```

- [ ] **Step 1: 写失败的测试**

把 `app/test/widget_snapshot_test.dart` 里那条 `test('days 恒 14 条，day 逐日递增', …)` **整条替换**成下面四条（其余既有用例只补参数、不改断言）：

```dart
  test('窗口 = [min(本月1日, 本周一), 下月最后一天]，且恒包含今天', () {
    for (final now in [
      DateTime(2026, 9, 20, 10),
      DateTime(2026, 10, 1, 0, 5), // 跨月当天
      DateTime(2026, 12, 31, 23, 55), // 年末
      DateTime(2027, 2, 14, 12),
    ]) {
      final s = buildWidgetSnapshot(
        schedule: null, now: now, themeMode: 'system', accent: 0xFF4F5BE8,
        todayTodoCount: 0,
      );
      final days = (s['days']! as List).cast<Map>();
      final first = days.first['day'] as int;
      final last = days.last['day'] as int;

      final monthStart = dayNumber(DateTime(now.year, now.month, 1));
      final weekMonday =
          dayNumber(DateTime(now.year, now.month, now.day - (now.weekday - 1)));
      expect(first, monthStart < weekMonday ? monthStart : weekMonday,
          reason: '窗口起点应当是「本月1日」与「本周一」里更早的那个（now=$now）');
      expect(last, dayNumber(DateTime(now.year, now.month + 2, 0)),
          reason: '窗口终点应当是本月的下一个月最后一天（now=$now）');

      // 恒包含今天，且 day 逐日递增
      final today = dayNumber(now);
      expect(days.any((d) => d['day'] == today), true,
          reason: '窗口必须包含今天（now=$now）');
      for (var i = 1; i < days.length; i++) {
        expect(days[i]['day'], (days[i - 1]['day'] as int) + 1);
      }
      expect(days.length, lessThanOrEqualTo(68));
    }
  });

  test('窗口含过去的天：9/20 的窗口起点是 9/1（本月 1 日比本周一 9/14 更早）', () {
    final s = buildWidgetSnapshot(
      schedule: null, now: DateTime(2026, 9, 20, 10), themeMode: 'system',
      accent: 0xFF4F5BE8, todayTodoCount: 0,
    );
    final days = (s['days']! as List).cast<Map>();
    final todayIndex = days.indexWhere((d) => d['day'] == dayNumber(DateTime(2026, 9, 20)));
    expect(todayIndex, greaterThan(0), reason: '今天不在第一项 —— 窗口里应当有更早的天');
  });

  test('days 每条都带农历；weekdays 七条、months 覆盖窗口的月', () {
    final s = buildWidgetSnapshot(
      schedule: null, now: DateTime(2026, 10, 1, 10), themeMode: 'system',
      accent: 0xFF4F5BE8, todayTodoCount: 0,
    );
    final days = (s['days']! as List).cast<Map>();
    for (final d in days) {
      expect(d['lunarShort'], isA<String>());
      expect((d['lunarShort'] as String), isNotEmpty);
      expect(d['lunarIsHoliday'], isA<bool>());
      expect(d.containsKey('abbrInk'), false, reason: 'abbrInk 已删 —— 胶囊文字改走 wg_ink_*');
    }
    expect((s['weekdays']! as List).length, 7);
    expect((s['weekdays']! as List).first, L10n.weekday(0));

    // 2026-10-01 是周四 → 窗口从 9/28（周一）起、到 11/30 止，覆盖 9/10/11 三个月
    final months = (s['months']! as List).cast<Map>();
    expect(months.map((m) => '${m['y']}-${m['m']}').toList(),
        ['2026-9', '2026-10', '2026-11']);
    expect(months.first['title'], L10n.yearMonth(DateTime(2026, 9)));
  });

  test('协议版本是 2', () {
    final s = buildWidgetSnapshot(
      schedule: null, now: DateTime(2026, 9, 20, 10), themeMode: 'system',
      accent: 0xFF4F5BE8, todayTodoCount: 0,
    );
    expect(s['v'], 2);
  });
```

`lunarOf` 与 `L10n` 的 import 若文件里没有，按现有 import 段补上（`package:shiftassistantpro/domain/lunar_info.dart`、`…/core/l10n.dart`）。

- [ ] **Step 2: 跑测试，确认它失败**

Run: `cd app && flutter test test/widget_snapshot_test.dart`

Expected: FAIL —— 窗口起点/终点对不上（现在还是「今天起 14 天」），且 `months` / `weekdays` / `lunarShort` 都是 null。

- [ ] **Step 3: 实现窗口**

在 `widget_snapshot.dart` 里：

**(a)** 版本号与窗口常量（替换原来的 `kWidgetSnapshotDays`）：

```dart
/// 快照格式版本。原生按它判断能不能解析 —— 对不上就按「无快照」走降级态。
///
/// v2（2026-09-20）：窗口从「今天起 14 天」改成「按月对齐的绝对窗口」；
/// `days[]` 删 `abbrInk`、增 `lunarShort` / `lunarIsHoliday`；顶层增 `weekdays` / `months`。
/// 换版本号是有意的：升级时旧快照一律解不开 → 渲染占位态，直到第一次 push。
const int kWidgetSnapshotVersion = 2;

/// 窗口的**最大**天数。真正用多少由 [widgetWindow] 算：
/// 「本月 + 下月」最多 62 天，再加本周一到月末最多 6 天补齐 → 68。
const int kWidgetSnapshotMaxDays = 68;

/// 快照窗口：`[min(本月 1 日, 今天所在周的周一), 下月最后一天]`。
///
/// 为什么不是「今天起 N 天」：月历要本月完整 + 前后补齐格，且**跨月那一刻**
/// （10 月 1 日零点）原生手上必须有 10 月的数据 —— 跨天刷新只能对表右移，
/// 变不出新月份，窗口里不预装下月的话桌面就是一张空月。
/// 起点取「本周一」是为了 4×1 本周条（今天可能是周日，本周一在 6 天前）。
({DateTime from, DateTime to}) widgetWindow(DateTime now) {
  final today = dateOnly(now); // UTC 纯日期，年月日即本地日历日
  final monthStart = DateTime(today.year, today.month, 1);
  final weekMonday =
      DateTime(today.year, today.month, today.day - (today.weekday - 1));
  final from = monthStart.isBefore(weekMonday) ? monthStart : weekMonday;
  // `DateTime(y, m + 2, 0)` = 下个月的最后一天（Dart 会把 day=0 归一成上月末）。
  final to = DateTime(today.year, today.month + 2, 0);
  return (from: from, to: to);
}
```

**(b)** 循环改成按窗口走（替换原来的 `for (var i = 0; i < kWidgetSnapshotDays; i++)` 与里面的 `date` 构造）：

```dart
  final window = widgetWindow(now);
  final dayCount = dayNumber(window.to) - dayNumber(window.from) + 1;
  assert(dayCount <= kWidgetSnapshotMaxDays, '窗口算出来 $dayCount 天，超出上限');

  for (var i = 0; i < dayCount; i++) {
    final date = DateTime(window.from.year, window.from.month, window.from.day + i);
```

循环体里除了 `days.add({...})` 的内容要改（见 (c)），其余（零点与班次边界、`timeRange` 那段）**逐字不动**。

**(c)** `days.add({...})` 里：删 `'abbrInk'` 那三行，加两条农历（`lunarOf(date)` 每格一次 —— 纯 Dart，68 次可以忽略）：

```dart
    final lunar = lunarOf(date);
    days.add({
      'day': dayNumber(date),
      'weekday': L10n.weekday(date.weekday - 1),
      'dateShort': L10n.monthDay(date),
      'hasShift': shift != null,
      'isRest': shift?.isRest ?? true,
      'shiftName': shift?.name ?? '',
      'shiftAbbr': shift?.shortLabel ?? '',
      'color': shift?.color ?? 0,
      'timeRange': timeRange,
      // 月历格子的第三行。原生不查农历（那是 Dart 侧的事），所以按日期烘焙。
      'lunarShort': lunar.shortLabel,
      'lunarIsHoliday': lunar.isLegalHoliday,
    });
```

> ⚠️ `abbrInk` 一并删掉的理由：胶囊底从「实心班次色」改成「14% 淡染」（spec §4.1），
> 文字改走 `wg_ink_*`，`onSolid` 算出来的黑/白字**在淡染底上是错的**（深色班次的淡染底接近白，
> 而 `onSolid` 会给白字）。留着一个错的字段，下一轮会被当成活的。

**(d)** 顶层加两个键（放在 `'days': days,` 旁边）与 `todayCard.lunarFull`：

```dart
    'weekdays': List.generate(7, L10n.weekday),
    'months': _monthsInWindow(window.from, window.to),
```

```dart
/// 窗口覆盖到的月份（含起止月），升序。月历标题行按「年-月」查它。
List<Map<String, Object?>> _monthsInWindow(DateTime from, DateTime to) {
  final out = <Map<String, Object?>>[];
  var y = from.year, m = from.month;
  while (y < to.year || (y == to.year && m <= to.month)) {
    out.add({'y': y, 'm': m, 'title': L10n.yearMonth(DateTime(y, m))});
    if (++m > 12) {
      m = 1;
      y++;
    }
  }
  return out;
}
```

`todayCard` 那张 map 里加一条（照抄 `lunar.shortLabel` 的位置）：

```dart
    'lunarFull': lunar.fullDescription,
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd app && flutter test test/widget_snapshot_test.dart`

Expected: `All tests passed!`（原有用例 + 4 条新的）

- [ ] **Step 5: 全量测试 + analyze**

Run: `cd app && flutter analyze && flutter test`

Expected: `No issues found!` 与全绿。**`widget_today_card_staleness_test.dart` 里那条「`todayCard.day` 与 `days[0].day` 同天」会红** —— 窗口现在含过去的天，`days[0]` 不再是今天。把它改成「与 `days` 里那一条 `day == 今天` 的项同天」：

```dart
      final today = dayNumber(d);
      final row = days.cast<Map>().firstWhere((r) => r['day'] == today);
      expect(tc['day'], row['day']);
```

- [ ] **Step 6: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/lib/features/widget/widget_snapshot.dart app/test/widget_snapshot_test.dart \
        app/test/widget_today_card_staleness_test.dart
git commit -m "feat(widget): 快照窗口改「本月+下月」的绝对窗口，协议 v2（删 abbrInk、增农历/周几/月份）"
```

---

## Task 3: 接住 v2（Kotlin：`WidgetStore` + 渲染侧临时适配）

Task 2 之后，Dart 发的是 v2、Kotlin 只认 v1 → 小组件会一直显示占位态。本任务把 Kotlin 侧接上。

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetStore.kt`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`

**Interfaces:**
- Produces:
  ```kotlin
  data class Day(day: Long, weekday: String, dateShort: String, hasShift: Boolean,
                 isRest: Boolean, shiftName: String, shiftAbbr: String, color: Int,
                 timeRange: String?, lunarShort: String, lunarIsHoliday: Boolean)
  data class MonthTitle(val y: Int, val m: Int, val title: String)
  data class Snapshot(…, val weekdays: List<String>, val months: List<MonthTitle>, …)
  ```
  `Day.abbrInk` 被删除 —— **Task 3 要把唯一的消费者（`gridCells` 里那句 `setTextColor(R.id.wg_c_abbr, d.abbrInk)`）改成 ink 色**，否则编不过。

- [ ] **Step 1: 改写 `WidgetStore`**

**(a)** 版本判断 `o.optInt("v", -1) != 1` → `!= 2`。

**(b)** `Day`：删 `val abbrInk: Int`，加两个字段（KDoc 照抄 spec §7.3 的口径）：

```kotlin
        /**
         * 月历格子的第三行（农历短标签，如「初八」）。
         *
         * 原生不查农历（那是 Dart 侧的事），所以它**按日期烘焙** —— 与
         * [dateShort] / [weekday] 同类，跨天对表右移时跟着那一天走，不会腐坏。
         */
        val lunarShort: String,
        /** 这一天的农历是否落在法定节假日（Dart 侧 `LunarInfo.isLegalHoliday`）。 */
        val lunarIsHoliday: Boolean,
```

**(c)** 解析那一段同步：删 `abbrInk = d.optInt("abbrInk", 0),`，加：

```kotlin
                lunarShort = d.optString("lunarShort", ""),
                lunarIsHoliday = d.optBoolean("lunarIsHoliday", false),
```

**(d)** `TodayCard` 加一个字段（Task 6 的 4×3 配方要显示它 —— `lunarShort` 只是「初八」，
4×3 用的是 App 完整信息卡那句：见 spec §5.2）：

```kotlin
        /**
         * 完整农历描述（「农历 丙午年 八月初八 · 生肖马 · 日干壬辰 · 国际民主日」）。
         *
         * 4×3 比原来的紧凑档高出约 95dp，多出来的地方放**真内容**而不是把行距摊开 ——
         * 这句就是那份内容（App 的完整版信息卡用的也是它）。
         */
        val lunarFull: String,
```

解析那段（与 `lunarShort` 挨着）：

```kotlin
                lunarFull = t.optString("lunarFull", ""),
```

**(e)** 新增 `MonthTitle` 与 `Snapshot` 的两个字段：

```kotlin
    /** 窗口覆盖到的某个月的标题（「2026年9月」/「September 2026」）。 */
    data class MonthTitle(val y: Int, val m: Int, val title: String)
```

```kotlin
        /** 七条周几文案（索引 0 = 周一）。月历表头行用 —— 原生不许有中文字面量。 */
        val weekdays: List<String>,
        /**
         * 窗口覆盖到的月份标题，升序。
         *
         * ⚠️ 月历渲染的是**今天所在的月**，而这份快照可能生成于上个月（跨天右移）。
         * 找不到对应月份时**隐藏标题行**，绝不借相邻月份的标题顶上 ——
         * 那是本仓「不让卡片理直气壮地写错」那条纪律的又一入口。
         */
        val months: List<MonthTitle>,
```

**(f)** `parse()` 里解析这两个（照抄 `boundaries` 那种宽容写法）：

```kotlin
        val wdArr = o.optJSONArray("weekdays") ?: JSONArray()
        val weekdays = (0 until wdArr.length()).map { wdArr.optString(it, "") }
            .filter { it.isNotEmpty() }

        val mArr = o.optJSONArray("months") ?: JSONArray()
        val months = (0 until mArr.length()).mapNotNull { i ->
            val m = mArr.optJSONObject(i) ?: return@mapNotNull null
            MonthTitle(
                y = m.optInt("y", 0),
                m = m.optInt("m", 0),
                title = m.optString("title", ""),
            )
        }
```

并在 `Snapshot(...)` 构造里加 `weekdays = weekdays, months = months,`。

- [ ] **Step 2: 渲染侧的临时适配**

`WidgetRenderer.gridCells` 里那句 `c.setTextColor(R.id.wg_c_abbr, d.abbrInk)` 改成走 ink（这一版网格还是旧版式，Task 8 会连整张布局一起删掉，此处只是让它编得过、且比原来更贴 spec §4.1）：

```kotlin
            c.setTextColor(R.id.wg_c_abbr, ink)
```

若 `gridCells` 里没有 `ink` 变量，就地取一次：
`val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)`。

- [ ] **Step 3: 构建（Kotlin 的唯一编译检查）**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
```

Expected: `√ Built build\app\outputs\flutter-apk\app-release.apk`。
⚠️ `flutter analyze` / `flutter test` **都不检查 Kotlin** —— 这一步不是走过场。

- [ ] **Step 4: 真机确认「占位态 → 正常卡片」这条恢复**

```bash
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
"$ADB" shell am force-stop com.daoban.shiftassistantpro
"$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity; sleep 6
"$ADB" shell input keyevent KEYCODE_HOME; sleep 3
"$ADB" exec-out screencap -p > /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/work/v2_after.png
```

读图：旧的那张卡应当**画出来了**（此刻还是旧五档版式 —— 那是预期的，本任务只验协议接得上）。

- [ ] **Step 5: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetStore.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt
git commit -m "feat(widget): 原生接住快照 v2（农历/周几/月份标题，删 abbrInk）"
```

---

## Task 4: 拆三个 provider + 注册表 + manifest + picker 名字

**Files:**
- Create: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetVariant.kt`
- Create: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/ShiftWidgetBase.kt`
- Create: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WeekStripWidgetProvider.kt`
- Create: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/TodayCardWidgetProvider.kt`
- Create: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/MonthWidgetProvider.kt`
- Create: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/ShiftWidgets.kt`
- Create: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRefreshReceiver.kt`
- Create: `app/android/app/src/main/res/xml/widget_week_strip_info.xml` / `widget_today_info.xml` / `widget_month_info.xml`
- Create: `app/android/app/src/main/res/values/strings.xml` / `app/android/app/src/main/res/values-en/strings.xml`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRefreshScheduler.kt`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/MainActivity.kt`（`widgetPushSnapshot` 那个分支）
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/BootReceiver.kt`（第 103 行附近）
- Delete: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/ShiftWidgetProvider.kt`

**Interfaces:**
- Consumes: `WidgetRenderer` / `WidgetStore`（既有）
- Produces:
  ```kotlin
  enum class WidgetVariant { WEEK_STRIP, TODAY, MONTH }
  abstract class ShiftWidgetBase : AppWidgetProvider() { abstract val variant: WidgetVariant }
  object ShiftWidgets {
      fun allComponents(context: Context): List<ComponentName>
      fun refreshAll(context: Context)
      fun hasAnyInstance(context: Context): Boolean
      fun scheduleNextRefreshIfNeeded(context: Context)
      fun cancelRefreshIfNone(context: Context)
  }
  // WidgetRenderer 的入口换成（Task 5~7 逐个替换 when 的三个分支）
  fun render(context: Context, snap: WidgetStore.Snapshot?, variant: WidgetVariant, widgetId: Int): RemoteViews
  ```

- [ ] **Step 1: `WidgetVariant` + `ShiftWidgetBase`**

`WidgetVariant.kt`：

```kotlin
package com.daoban.shiftassistantpro

/**
 * 三张固定卡。**尺寸与内容都在编译期定死**（`resizeMode="none"`），
 * 运行期不再分档 —— 这是本轮重做的全部要点：一张卡只为它自己的尺寸排版。
 */
enum class WidgetVariant {
    /** 4×1 本周条：周几 / 日数字 / 班次胶囊，七列。 */
    WEEK_STRIP,

    /** 4×3 今日信息卡：照搬 App 底栏信息卡的完整版。 */
    TODAY,

    /** 4×5 整月：月份标题 + 周几行 + 6×7 格。 */
    MONTH,
}
```

`ShiftWidgetBase.kt`（内容就是旧 `ShiftWidgetProvider` 的那四件事，**去掉分档**、改成按 `variant` 走；`refreshAll` / `scheduleNextRefresh` 的公共部分搬进 `ShiftWidgets`）：

```kotlin
package com.daoban.shiftassistantpro

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent

/**
 * 三张固定卡的公共实现。子类只有一个 `variant`，没有别的。
 *
 * 刷新触发点（承自 v0.8.4 的 spec §6.1，本轮一处未改）：
 *   · App 内数据变化 —— Dart 侧 `WidgetService.push()` 走 MethodChannel 进来
 *   · 跨天 00:00 与今天班次的开始/结束 —— [WidgetRefreshScheduler] 排的精确闹钟
 *   · 开机 / 装更新 —— BootReceiver 里补一次
 *   · 刚添加到桌面 —— 系统的 onUpdate
 *
 * **没有 `onAppWidgetOptionsChanged`**：本轮三张卡都 `resizeMode="none"`，
 * 尺寸不会变，那个回调不会再来。留着它只会让人以为「尺寸还是会变」。
 */
abstract class ShiftWidgetBase : AppWidgetProvider() {

    abstract val variant: WidgetVariant

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // `javaClass`（不是 `this`）：注册表按类名反查 variant，见 `ShiftWidgets.variantOf`。
        ShiftWidgets.render(context, appWidgetManager, javaClass, variant, appWidgetIds)
        ShiftWidgets.scheduleNextRefreshIfNeeded(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        // 最后一个实例（跨三张卡一起数）被删掉时才取消刷新闹钟 —— 否则桌面上一个
        // 小组件都没有了，它还会一天一次地把自己排回来，永远。
        //
        // 判「一个不剩」而不是「本 provider 不剩」：三张卡共用同一个刷新闹钟，
        // 只看自己会把另外两张卡的刷新一起取消掉。
        if (!ShiftWidgets.hasAnyInstance(context)) {
            WidgetRefreshScheduler.cancel(context)
            AlarmLog.info(context, "ShiftWidgetBase.onDeleted: 三张卡都无实例，已取消刷新闹钟")
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == WidgetRefreshScheduler.ACTION_REFRESH) {
            ShiftWidgets.refreshAll(context)
            return // 自定义 action 不走 super（super 只认系统那几个 action）
        }
        super.onReceive(context, intent)
    }
}
```

三个子类（`WeekStripWidgetProvider.kt` / `TodayCardWidgetProvider.kt` / `MonthWidgetProvider.kt`）：

```kotlin
package com.daoban.shiftassistantpro

/** 4×1 本周条。内容全在 [WidgetRenderer.weekStrip]。 */
class WeekStripWidgetProvider : ShiftWidgetBase() {
    override val variant = WidgetVariant.WEEK_STRIP
}
```

（另两个照抄，`variant` 分别是 `WidgetVariant.TODAY` / `WidgetVariant.MONTH`，KDoc 一句话写清是哪张卡。）

- [ ] **Step 2: `ShiftWidgets` 注册表**

```kotlin
package com.daoban.shiftassistantpro

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context

/**
 * 三张卡的注册表。**所有「对全部实例」的操作都必须走这里** ——
 * 少扫一张卡的症状是静默的：那张卡不刷新、或者三张卡都删光了刷新闹钟还在跑。
 */
object ShiftWidgets {

    /** 三张卡的 provider 类。顺序与 `WidgetVariant` 一致，便于对照。 */
    private val PROVIDERS = listOf(
        WeekStripWidgetProvider::class.java,
        TodayCardWidgetProvider::class.java,
        MonthWidgetProvider::class.java,
    )

    fun allComponents(context: Context): List<ComponentName> =
        PROVIDERS.map { ComponentName(context, it) }

    /** 渲染全部卡的**全部实例**。Dart 侧 push 完快照后调它。 */
    fun refreshAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val snap = WidgetStore.snapshot(context)
        var total = 0
        for (cls in PROVIDERS) {
            val ids = mgr.getAppWidgetIds(ComponentName(context, cls))
            total += ids.size
            render(context, mgr, cls, variantOf(cls), ids)
        }
        AlarmLog.info(context, "ShiftWidgets.refreshAll: $total 个实例")
        // 桌面上一个实例都没有时不排刷新 —— 否则用户删掉小组件之后，下一次打开 App
        // 又把它排回来，于是「删了还在刷」永远循环（v0.8.4 的注释有完整推演）。
        if (total > 0) scheduleNextRefreshIfNeeded(context)
    }

    /** 三张卡里还有没有活着的实例。`onDeleted` 判「该不该取消刷新闹钟」用它。 */
    fun hasAnyInstance(context: Context): Boolean {
        val mgr = AppWidgetManager.getInstance(context)
        return PROVIDERS.any { mgr.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
    }

    /**
     * 排下一次刷新。
     *
     * 快照里 `boundaries` 是生成时刻起、窗口内所有「该刷新了」的时刻（每天的本地零点
     * + 各工作班次的开始/结束），升序。取第一个大于现在的即可。
     *
     * 窗口耗尽（App 两个多月没打开）就退化为「下一个本地零点」—— 那时卡片本来就已经
     * 是占位态了，零点这一刷只是给它一个自愈的机会。
     *
     * ⚠️ 跨月**不需要**单排一条「下月 1 日」的边界：零点那条边界本来就会重渲染一次，
     * 而月历渲染哪个月是原生按 `LocalDate.now()` 现算的，数据早就在窗口里。
     */
    fun scheduleNextRefreshIfNeeded(context: Context) {
        val now = System.currentTimeMillis()
        val snap = WidgetStore.snapshot(context)
        val next = snap?.boundaries?.firstOrNull { it > now }
            ?: run {
                val d = java.time.LocalDate.now().plusDays(1)
                AlarmLog.info(context, "ShiftWidgets: 边界窗口耗尽，退化为下一个零点")
                d.atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
            }
        WidgetRefreshScheduler.schedule(context, next)
    }

    fun cancelRefreshIfNone(context: Context) {
        if (!hasAnyInstance(context)) WidgetRefreshScheduler.cancel(context)
    }

    /** 渲染一批实例。按 [variant] 交给 [WidgetRenderer]。 */
    internal fun render(
        context: Context,
        mgr: AppWidgetManager,
        cls: Class<out AppWidgetProvider>,
        variant: WidgetVariant,
        ids: IntArray,
    ) {
        if (ids.isEmpty()) return
        val snap = WidgetStore.snapshot(context)
        for (id in ids) {
            try {
                mgr.updateAppWidget(id, WidgetRenderer.render(context, snap, variant, id))
            } catch (e: Exception) {
                // 越界读、位图过大这类问题在这里被吞掉时**不会崩**，只会让那张卡
                // 停在上一次的内容上 —— 所以这条日志是唯一的线索。
                AlarmLog.error(context, "ShiftWidgets: 渲染 $variant id=$id 失败: ${e.message}")
            }
        }
    }

    private fun variantOf(cls: Class<out AppWidgetProvider>): WidgetVariant = when (cls) {
        WeekStripWidgetProvider::class.java -> WidgetVariant.WEEK_STRIP
        TodayCardWidgetProvider::class.java -> WidgetVariant.TODAY
        else -> WidgetVariant.MONTH
    }
}
```

> `onUpdate` 那条路径需要按「实例属于哪个类」拿 variant，所以 `render` 多一个 `cls` 参数；
> `refreshAll` 那份用 `variantOf(cls)`。两处都是同一张表的两个视角，别各写一份映射。

- [ ] **Step 3: `WidgetRefreshReceiver` + `WidgetRefreshScheduler` 改目标**

`WidgetRefreshReceiver.kt`：

```kotlin
package com.daoban.shiftassistantpro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 刷新广播的落点。
 *
 * 为什么不让闹钟直接打给某一个 provider：三张卡是平级的，指向其中一张会让
 * 「谁负责刷新」变成一件没有理由的耦合（那张卡被删掉/改名时会连累另两张）。
 *
 * 只由本 App 自己发（`exported="false"` + 显式组件），不接任何外部意图。
 */
class WidgetRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != WidgetRefreshScheduler.ACTION_REFRESH) return
        ShiftWidgets.refreshAll(context)
    }
}
```

`WidgetRefreshScheduler.kt`：`ACTION_REFRESH` 常量搬过来（值不变，仍是
`"com.daoban.shiftassistantpro.WIDGET_REFRESH"`），两处 `Intent(context, ShiftWidgetProvider::class.java)`
改成 `Intent(context, WidgetRefreshReceiver::class.java)`，并把文件头注释里
「ShiftWidgetProvider 的 ACTION_REFRESH」改准。

- [ ] **Step 4: 三份 info.xml + 两份 strings.xml**

`res/xml/widget_week_strip_info.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  4×1 本周条。固定尺寸、不可拉伸（本轮重做的核心）。

  `resizeMode="none"` 是正式声明；**部分老版本第三方桌面会忽略它** —— 那是平台边界，
  与「小米上标准小组件藏在二级分类里」同类，README 的已知边界里写了。

  尺寸两头都声明：Android 12+ 认 `targetCellWidth/Height`，12 以下不认，
  靠 `minWidth = 70n - 30` 的老公式折算（n = 格数）。

  `updatePeriodMillis="0"`：不要系统轮询（最快 30 分钟一次还被限流），
  刷新全靠 WidgetRefreshScheduler 自排的边界闹钟。

  `previewLayout` 所指的「结构示意图」是**静态 inflate**、不跑 RemoteViews 动作 ——
  真实版式是渲染期 addView 出来的，映不出来。示意图只画形状、不放假文字
  （那种布局要写死示例文案，而本项目是中英双语的）。

  ⚠️ 小米/HyperOS 会按**资源 id** 缓存 drawable：改了这里的资源色之后，
  验证前必须 `am force-stop com.miui.home`。
-->
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="250dp"
    android:minHeight="40dp"
    android:targetCellWidth="4"
    android:targetCellHeight="1"
    android:resizeMode="none"
    android:widgetCategory="home_screen"
    android:updatePeriodMillis="0"
    android:initialLayout="@layout/widget_placeholder"
    android:previewLayout="@layout/widget_preview_strip" />
```

`widget_today_info.xml` 同构，`minHeight="180dp"` / `targetCellHeight="3"` / `previewLayout="@layout/widget_preview_today"`。
`widget_month_info.xml` 同构，`minHeight="320dp"` / `targetCellHeight="5"` / `previewLayout="@layout/widget_preview_month"`。

> 三张 `widget_preview_*.xml` 是 spec §8 的**路线 A（结构示意图）**：只有形状与色块、**无文字**。
> 写中文会撞双语、写英文中文用户看不懂；也不要用假数据装成真内容。用生成脚本出（产物提交进仓库）：

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
mkdir -p app/android/app/src/main/res/drawable
cat > app/android/app/src/main/res/drawable/widget_preview_block.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<!--
  picker 缩略图里的「一块」。中灰而不是黑/白：系统 picker 的底色深浅随主题，
  中灰两头都看得见。缩略图**不写任何文字**（写中文撞双语、写英文中文用户看不懂）。
-->
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#556E6E82" />
    <corners android:radius="6dp" />
</shape>
XML

python - <<'PY'
HDR = '''<?xml version="1.0" encoding="utf-8"?>
<!-- picker 缩略图：%s。**结构示意、无文字、无假数据**（见 spec §8 路线 A）。 -->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center_vertical"
    android:background="@drawable/widget_card_light"
    android:padding="12dp">
'''

def block(w, h, weight=False, mt=0):
    w_attr = 'android:layout_width="0dp"\n        android:layout_weight="1"' if weight else f'android:layout_width="{w}dp"'
    mt_attr = f'\n        android:layout_marginTop="{mt}dp"' if mt else ''
    return f'''    <ImageView
        {w_attr}
        android:layout_height="{h}dp"{mt_attr}
        android:scaleType="fitXY"
        android:contentDescription="@null"
        android:src="@drawable/widget_preview_block" />'''

# 4×1 本周条：七列，每列「细块 + 胶囊块」
cols = "\n".join(
    f'''        <LinearLayout
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:orientation="vertical"
            android:gravity="center_horizontal"
            android:paddingHorizontal="3dp">
{block(0, 8, weight=True)}
{block(0, 16, weight=True, mt=3)}
        </LinearLayout>''' for _ in range(7)
)
strip = HDR % "4×1 本周条" + f'''    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal">
{cols}
    </LinearLayout>
</LinearLayout>
'''

# 4×3 今日卡：左侧一条竖色块 + 右侧三行递减的块
today = HDR % "4×3 今日卡" + f'''    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal">
{block(4, 90)}
        <LinearLayout
            android:layout_width="0dp"
            android:layout_weight="1"
            android:layout_height="wrap_content"
            android:layout_marginStart="12dp"
            android:orientation="vertical">
{block(0, 20, weight=True)}
{block(0, 14, weight=True, mt=12)}
{block(0, 14, weight=True, mt=12)}
{block(0, 14, weight=True, mt=12)}
        </LinearLayout>
    </LinearLayout>
</LinearLayout>
'''

# 4×5 整月：一条标题块 + 7×6 方格
rows = "\n".join(
    "        <LinearLayout\n"
    '            android:layout_width="match_parent"\n'
    '            android:layout_height="0dp"\n'
    '            android:layout_weight="1"\n'
    '            android:orientation="horizontal">\n'
    + "\n".join(
        '            <ImageView\n'
        '                android:layout_width="0dp"\n'
        '                android:layout_height="match_parent"\n'
        '                android:layout_weight="1"\n'
        '                android:layout_marginHorizontal="2dp"\n'
        '                android:layout_marginVertical="3dp"\n'
        '                android:scaleType="fitXY"\n'
        '                android:contentDescription="@null"\n'
        '                android:src="@drawable/widget_preview_block" />'
        for _ in range(7)
    )
    + "\n        </LinearLayout>"
    for _ in range(6)
)
month = HDR % "4×5 整月" + f'''{block(0, 10, weight=True)}
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:layout_marginTop="8dp"
        android:orientation="vertical">
{rows}
    </LinearLayout>
</LinearLayout>
'''

base = 'app/android/app/src/main/res/layout/'
open(base + 'widget_preview_strip.xml', 'w', encoding='utf-8').write(strip)
open(base + 'widget_preview_today.xml', 'w', encoding='utf-8').write(today)
open(base + 'widget_preview_month.xml', 'w', encoding='utf-8').write(month)
print('ok')
PY
```

⚠️ 三张缩略图**不能用 `#RRGGBB` 之外的东西、也不能出现文字**；`widget_layout_whitelist_test.dart`
会扫它们（`preview` 文件名不以 `widget` 开头也不要紧 —— 它扫的是**所有** `res/layout/widget*.xml`，
所以命名前缀保持 `widget_` 正好被覆盖）。

`res/values/strings.xml`（默认 = 中文，与 `android:label="倒班助手Pro"` 同口径）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  只有三张卡在系统 picker 里的名字。
  它们由 manifest 的 `android:label` 引用，**在安装时按系统语言解析** ——
  跟不了 App 内的语言开关（Android 平台边界：manifest 标签解析得比 Dart 早）。
  App 名本身仍在 manifest 里写死中文，本轮不动（改英文产品名是另一件事）。
-->
<resources>
    <string name="widget_week_strip_name">倒班助手Pro · 本周</string>
    <string name="widget_today_name">倒班助手Pro · 今日</string>
    <string name="widget_month_name">倒班助手Pro · 整月</string>
</resources>
```

`res/values-en/strings.xml` 同样三条，值分别为
`Shift Assistant Pro · This week` / `· Today` / `· Month`。

- [ ] **Step 5: manifest**

替换掉原来那个 `ShiftWidgetProvider` 的 `<receiver>`（连同 `shift_widget_info.xml` 的 meta-data），换成四个（R8 开着，**每个类都要显式声明**）：

```xml
        <!-- 桌面小组件：三张固定卡 + 一个刷新广播的落点。
             label 走 res/values/strings.xml（中英各一份），跟随**系统语言**。
             必须在这里显式声明：release 构建 isMinifyEnabled = true，
             只靠代码引用的类会被 R8 裁掉。 -->
        <receiver
            android:name=".WeekStripWidgetProvider"
            android:exported="false"
            android:label="@string/widget_week_strip_name">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/widget_week_strip_info" />
        </receiver>
        <!-- 另两个同构：.TodayCardWidgetProvider / @xml/widget_today_info、
             .MonthWidgetProvider / @xml/widget_month_info -->
        <receiver
            android:name=".WidgetRefreshReceiver"
            android:exported="false" />
```

顺手 `git rm app/android/app/src/main/res/xml/shift_widget_info.xml`。

- [ ] **Step 6: 改两处调用方**

`MainActivity.kt`（`widgetPushSnapshot` 那个分支，约 597 行）：`ShiftWidgetProvider.refreshAll(this)` → `ShiftWidgets.refreshAll(this)`。

`BootReceiver.kt`（约 103 行）：`ShiftWidgetProvider.scheduleNextRefresh(context)` → `ShiftWidgets.scheduleNextRefreshIfNeeded(context)`

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git rm app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/ShiftWidgetProvider.kt
grep -rn "ShiftWidgetProvider" app/android/app/src/main/ app/lib/ || echo "旧 provider 已无引用 ✓"
```

> ⚠️ 此刻 `WidgetRenderer.render` 的签名还是**旧的** `(context, snap, tier, id)` —— 本任务先只改调用方？
> **不行**：`ShiftWidgets.render` 调用的是新签名。所以本任务必须同时给出新的 `render`，
> 三个分支**临时全部委托给旧的渲染函数**（下一步）。

- [ ] **Step 7: 新 `render` 入口（三个分支临时委托旧版式）**

在 `WidgetRenderer.kt` 里把原来的 `render(context, snap, tier, widgetId)` 换成：

```kotlin
    /**
     * 三张卡的分派。**纯渲染**：不写盘、不排闹钟、不读除宿主配置之外的任何系统状态。
     *
     * ⚠️ Task 4~7 之间三个分支是**临时的**（先全都走旧版式的渲染函数，保证每一步都编得过、
     * 桌面上也都看得见一张卡）。Task 5 / 6 / 7 逐个换成 `weekStrip` / `todayCard` / `monthCard`。
     */
    fun render(
        context: Context,
        snap: WidgetStore.Snapshot?,
        variant: WidgetVariant,
        widgetId: Int,
    ): RemoteViews {
        if (snap == null) {
            return placeholder(context, dark = isDark(context, "system"), widgetId = widgetId)
        }
        val todayIndex = snap.indexOfToday()
        if (todayIndex < 0) {
            // 快照过期：App 两个多月没打开，这份 days 里已经没有今天了。
            AlarmLog.info(context, "WidgetRenderer: 快照已过期，走占位态")
            return placeholder(context, isDark(context, snap.themeMode), widgetId = widgetId)
        }
        if (!snap.hasSchedule) return empty(context, snap, widgetId)
        return when (variant) {
            // ⚠️ TASK4 临时：全部走旧版式的网格档，Task 5/6/7 逐个替换。
            WidgetVariant.WEEK_STRIP -> gridWithCard(context, snap, todayIndex, widgetId, 8)
            WidgetVariant.TODAY -> gridWithCard(context, snap, todayIndex, widgetId, 8)
            WidgetVariant.MONTH -> gridWithCard(context, snap, todayIndex, widgetId, 16)
        }
    }
```

删掉 `WidgetTier` 相关的引用（`import` 与 `when (tier)` 整块），但**先不要删 `WidgetTier.kt` / 旧布局 / 旧渲染函数** —— Task 8 统一清账。

⚠️ `WidgetTier.kt` 此刻没有引用者了（`grep -rn "WidgetTier" app/android` 应当只剩它自己的文件），保留即可（Kotlin 不会因未使用而报错），Task 8 删。

- [ ] **Step 8: 构建、安装，确认 picker 里有三条**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
"$ADB" shell am force-stop com.miui.home; sleep 2
```

**在桌面上手动加小组件**（长按桌面 → 添加小部件 → 「支持小部件的应用」→「安卓小部件」），确认：

1. 「倒班助手Pro」名下**多出三条**（本周 / 今日 / 整月）
2. 三条各自的**缩略图互不相同**（结构示意图）
3. **三条都加得上去**，且加上去之后各自渲染出内容（此刻都还是旧版式，旧版式还在）
4. 加完之后**拖不动**了 —— 长按卡片没有缩放手柄。这条是 `resizeMode="none"` 的真机判据

把四条的结果写进报告；任何一条不符都先查 manifest 与 info.xml。

- [ ] **Step 9: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add -A app/android/app/src/main
git commit -m "feat(widget): 拆成三个固定 provider + 注册表 + 刷新广播，picker 里三条各自命名"
```

---

## Task 5: 4×1 本周条

**Files:**
- Create: `app/android/app/src/main/res/layout/widget_week_strip.xml` / `widget_strip_cell.xml`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`

**Interfaces:**
- Produces:
  ```kotlin
  private fun weekStrip(
      context: Context, snap: WidgetStore.Snapshot, todayIndex: Int, widgetId: Int,
  ): RemoteViews
  ```
  它**不用** `todayIndex` 定位列，而是按 `LocalDate.now()` 现算本周一 → 逐列用
  `snap.days.indexOfFirst { it.day == targetEpochDay }` 找那一行数据（窗口是绝对日期，
  这正是 Task 2 换窗口换来的能力）。

- [ ] **Step 1: 写两张布局**

`app/android/app/src/main/res/layout/widget_strip_cell.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  本周条的**一格**。七格共用这一张（每格一个独立的 RemoteViews 实例，id 重复没关系）。

  ⚠️ 根布局的 layout_height 必须是 match_parent 而不是 wrap_content：它被塞进
  FrameLayout 槽位，拿的是槽位的 LayoutParams，自己再声明 match_parent 才与外层一致
  （v0.8.6 Task 1 真机验过这条链）。

  三行：周几 / 日数字 / 班次胶囊。高度预算见 spec §5.1：卡内可用约 62dp，
  三行 15+20+18 + 间距 4 ≈ 57dp —— **余量只有 5dp**，真机出图若被裁，
  退到「周几与日期同行」的两行备选（`一 19`），不要靠缩字号硬塞。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_sc_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center">

    <TextView
        android:id="@+id/wg_sc_weekday"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:textSize="11sp"
        android:maxLines="1"
        android:ellipsize="end" />

    <TextView
        android:id="@+id/wg_sc_day"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="2dp"
        android:textSize="15sp"
        android:maxLines="1"
        android:ellipsize="end" />

    <FrameLayout
        android:layout_width="36dp"
        android:layout_height="18dp"
        android:layout_marginTop="3dp">

        <ImageView
            android:id="@+id/wg_sc_pill"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:scaleType="fitXY"
            android:contentDescription="@null" />

        <TextView
            android:id="@+id/wg_sc_abbr"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:gravity="center"
            android:textSize="10sp"
            android:maxLines="1" />
    </FrameLayout>
</LinearLayout>
```

`app/android/app/src/main/res/layout/widget_week_strip.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  4×1 本周条的外壳：卡底 + 七列等宽槽位。
  槽位一律 FrameLayout（默认 LayoutParams 是 MATCH_PARENT×MATCH_PARENT，
  addView 塞进去的内容才会填满 —— 换 LinearLayout 会缩成一小团且不报错）。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_ws_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="horizontal"
    android:background="@drawable/widget_card_light"
    android:padding="8dp">

    <FrameLayout
        android:id="@+id/wg_ws_col1"
        android:layout_width="0dp"
        android:layout_height="match_parent"
        android:layout_weight="1" />

    <!-- wg_ws_col2 … wg_ws_col7：同一段，只换 id 下标 -->
</LinearLayout>
```

（七列逐个写出，`wg_ws_col1` … `wg_ws_col7`。手写七段比生成脚本更不容易出错。）

- [ ] **Step 2: 写渲染函数**

```kotlin
    /**
     * 4×1 本周条：**今天所在的那一周**（周一~周日），与 App 日历的一行同构。
     *
     * 列的位置由**日期**定，不由 `todayIndex` 定：先算本周一，再逐列拿 epochDay 去
     * `days[]` 里找。窗口是绝对日期的（spec §7.1），所以本周一即使是上个月的最后几天
     * 也在窗口里 —— 这正是换窗口换来的能力。
     *
     * 「今天」那列：周几与日数字走**主色**。**不许加粗** —— `TextView` 没有
     * `setTypeface(int)` 重载，`setInt(id, "setTypeface", …)` 会在宿主进程抛 `ActionException`。
     *
     * 胶囊走**淡染配方**（14% 底 + 45% 描边）而不是实心：那是 App 日历格里班次胶囊的
     * 同一套长相（spec §4.1），文字因此走中性 ink —— 淡染底混合后≈卡片底，
     * `wg_ink_*` 必然过 AA，而 `onSolid` 那套黑/白字在淡染底上是错的。
     */
    private fun weekStrip(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_week_strip)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_ws_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.setOnClickPendingIntent(R.id.wg_ws_root, launchIntent(context, rootRequestCode(widgetId)))

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted = context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)
        val empty = context.getColor(if (dark) R.color.wg_empty_dark else R.color.wg_empty_light)

        val todayEpoch = snap.days[todayIndex].day
        val today = LocalDate.ofEpochDay(todayEpoch)
        val monday = today.minusDays((today.dayOfWeek.value - 1).toLong())

        val columns = intArrayOf(
            R.id.wg_ws_col1, R.id.wg_ws_col2, R.id.wg_ws_col3, R.id.wg_ws_col4,
            R.id.wg_ws_col5, R.id.wg_ws_col6, R.id.wg_ws_col7,
        )

        for (col in columns.indices) {
            val epoch = monday.plusDays(col.toLong()).toEpochDay()
            val i = snap.days.indexOfFirst { it.day == epoch }
            if (i < 0) {
                // 窗口里没有这天（理论上不会发生 —— 窗口恒含本周一与本周日）。
                // 不当成「没有班次」画：那会理直气壮地显示一张空卡。
                v.setViewVisibility(columns[col], android.view.View.GONE)
                continue
            }
            v.setViewVisibility(columns[col], android.view.View.VISIBLE)

            val d = snap.days[i]
            val isToday = epoch == todayEpoch

            // 点某一列 → 打开 App 并跳到那天。格子占槽位 1..7。
            v.setOnClickPendingIntent(
                columns[col],
                launchIntent(context, cellRequestCode(widgetId, col), epochDay = epoch.toInt()),
            )

            val c = RemoteViews(context.packageName, R.layout.widget_strip_cell)
            for (id in intArrayOf(R.id.wg_sc_weekday, R.id.wg_sc_day, R.id.wg_sc_pill, R.id.wg_sc_abbr)) {
                // 可见性无条件设满：宿主 reapply 时只重放新动作，漏设会保持上一次的状态。
                c.setViewVisibility(id, android.view.View.VISIBLE)
            }

            c.setTextViewText(R.id.wg_sc_weekday, d.weekday)
            c.setTextColor(R.id.wg_sc_weekday, if (isToday) snap.accent else muted)
            // 日数字：与 App 的格子一样只印「日」，整串「9月19日」在 46dp 宽的列里排不下。
            c.setTextViewText(R.id.wg_sc_day, LocalDate.ofEpochDay(epoch).dayOfMonth.toString())
            c.setTextColor(R.id.wg_sc_day, if (isToday) snap.accent else ink)

            c.setImageViewBitmap(
                R.id.wg_sc_pill,
                WidgetChip.tintedChip(
                    if (d.hasShift) d.color else empty,
                    dpToPx(context, 36),
                    dpToPx(context, 18),
                ),
            )
            c.setTextViewText(R.id.wg_sc_abbr, if (d.hasShift) d.shiftAbbr else "")
            c.setTextColor(R.id.wg_sc_abbr, ink)

            v.addView(columns[col], c)
        }
        return v
    }
```

顶部补 import：`import java.time.LocalDate`（文件里可能已有）。

- [ ] **Step 3: 接进 `render()`**

```kotlin
            WidgetVariant.WEEK_STRIP -> weekStrip(context, snap, todayIndex, widgetId)
```

- [ ] **Step 4: 构建、安装、出图**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
"$ADB" shell am force-stop com.miui.home; sleep 2
"$ADB" shell input keyevent KEYCODE_HOME; sleep 3
"$ADB" shell am force-stop com.daoban.shiftassistantpro
"$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity; sleep 6
"$ADB" shell input keyevent KEYCODE_HOME; sleep 3
"$ADB" exec-out screencap -p > /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/work/card_strip.png
```

**自己 Read `work/card_strip.png`**，回答：

1. 是**七列**、周一到周日吗？周几与日期对得上吗（对着手机日历核一遍）？
2. **今天那一列**的周几与日数字是主色吗？
3. **三行一个不少、没有被裁**吗（尤其胶囊有没有被切掉下沿）？
4. 胶囊看起来是**淡染 + 同色描边**（不是实心砖）吗？
5. 上下留白均匀吗（不是全堆在底部）？

**第 3 问若答「被裁了」**：按 spec §5.1 退到两行备选（周几与日期同行：`一 19`，胶囊单独一行），
改完重跑本步 —— 这是**预期内的退路**，不是设计失败。

- [ ] **Step 5: 逐列点击验证**

```bash
"$ADB" shell am kill com.daoban.shiftassistantpro   # 用 kill，不是 force-stop（见先导事实 B-2）
# 先量出本周条七列在屏幕上的横坐标与纵坐标（从刚才那张截图里读），然后：
"$ADB" shell input tap <第 3 列的 x> <卡片的 y>
sleep 4
"$ADB" exec-out screencap -p > /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/work/card_strip_tap3.png
```

读图确认：App 打开后**日历停在那一列的那一天**（不是今天）。至少验两列（今天那列 + 另一列）。

- [ ] **Step 6: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/android/app/src/main/res/layout/widget_week_strip.xml \
        app/android/app/src/main/res/layout/widget_strip_cell.xml \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt
git commit -m "feat(widget): 4×1 本周条（周几/日数字/淡染胶囊，今天走主色）"
```

---

## Task 6: 4×3 今日卡

**Files:**
- Create: `app/android/app/src/main/res/layout/widget_today_standalone.xml`
- Modify: `app/android/app/src/main/res/layout/widget_today_card.xml`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`

**Interfaces:**
- Consumes: 既有的 `renderTodayCard(context, snap, todayIndex, widgetId)`（跨天降级逻辑逐字保留）
- Produces: `private fun todayStandalone(context, snap, todayIndex, widgetId): RemoteViews`

- [ ] **Step 1: 写外壳**

`app/android/app/src/main/res/layout/widget_today_standalone.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  4×3 今日卡的**外壳**：只画卡片底 + 一个槽位。
  卡片内容自己**不画底**（widget_today_card.xml 的根没有 background）——
  两层同图叠放会多出一圈圆角描边、悬在外壳边框内侧（v0.8.6 踩过）。

  gravity="center_vertical"：内容约 200dp、4×3 可用约 268dp，余下约 68dp
  成为上下均匀留白。**不靠继续放大字号去填满** —— 字号要能被真机图判定为「舒展」，
  而不是「被撑大」。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_ts_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center_vertical"
    android:background="@drawable/widget_card_light">

    <FrameLayout
        android:id="@+id/wg_ts_slot"
        android:layout_width="match_parent"
        android:layout_height="wrap_content" />
</LinearLayout>
```

- [ ] **Step 2: 按 4×3 配方改 `widget_today_card.xml`**

在**现有文件**上改（元素顺序、id 全部不动），只动这几处：

| 项 | 旧值 | 新值 |
|---|---|---|
| 根 padding | `14dp` | `18dp` |
| 根 `android:background` | `@drawable/widget_card_light` | **删掉**（外壳画底） |
| `wg_tc_date` textSize | `18sp` | `20sp` |
| `wg_tc_shift` textSize | `15sp` | `17sp` |
| 各行的 `layout_marginTop`（农历、班次行、班组行） | `8dp` | `12dp` |
| `wg_tc_time` 的 `layout_marginTop` | `2dp` | `6dp` |
| 三个徽章的 FrameLayout 高（`wg_tc_today_wrap` / `wg_tc_todo_wrap` / `wg_tc_adj_wrap`） | `20dp` | `22dp` |
| `wg_tc_bar` | `4dp × 18dp` | `4dp × 22dp` |
| `wg_tc_lunar` | `maxLines="1"` | `maxLines="2"` |
| `wg_tc_lunar` textSize | `13sp` | `13sp`（不变） |

**并给根的 id 说明补一句**：这张布局的根现在**永远**被 `widget_today_standalone` 的槽位包裹，
所以它自己画底就是双层边 —— 头部注释原来那句「本布局永远被塞进 widget_grid_with_card 的装配壳里」
改成「永远被塞进 `widget_today_standalone` 的槽位里」。

- [ ] **Step 3: 写渲染函数 + 农历换完整描述**

`renderTodayCard` 里唯一的内容改动是农历那一行：

```kotlin
        // ── 2. 农历：跨天就隐藏（它是生成那天的） ──
        // 4×3 比原来的紧凑档高出约 95dp，多出来的地方要放**真内容**：
        // 换用 `LunarInfo.fullDescription`（App 完整版信息卡用的就是它），
        // 因此布局里那行是 maxLines="2"。
        if (stale) {
            v.setViewVisibility(R.id.wg_tc_lunar, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_lunar, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_tc_lunar, tc.lunarFull)
            v.setTextColor(
                R.id.wg_tc_lunar,
                if (tc.lunarIsHoliday) {
                    context.getColor(R.color.wg_holiday)
                } else {
                    muted
                },
            )
        }
```

并新增外壳渲染函数：

```kotlin
    /**
     * 4×3 今日卡：外壳（画卡底）+ 嵌套 [renderTodayCard]。
     *
     * 与旧版最大的差别是**不再套在网格下面** —— 它是独立的一张卡，
     * 尺寸固定，所以内容按 4×3 排版（大一号的字、`lunarFull` 两行）。
     */
    private fun todayStandalone(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_today_standalone)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_ts_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.addView(R.id.wg_ts_slot, renderTodayCard(context, snap, todayIndex, widgetId))
        return v
    }
```

- [ ] **Step 4: 接进 `render()`**

```kotlin
            WidgetVariant.TODAY -> todayStandalone(context, snap, todayIndex, widgetId)
```

- [ ] **Step 5: 构建、安装、出图**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
"$ADB" shell am force-stop com.miui.home; sleep 2
"$ADB" shell am force-stop com.daoban.shiftassistantpro
"$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity; sleep 6
"$ADB" shell input keyevent KEYCODE_HOME; sleep 3
"$ADB" exec-out screencap -p > /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/work/card_today.png
```

**自己 Read `work/card_today.png`**，回答：

1. 日期 + 「今天」徽章 + 农历 + 班次 + 时间 + 其他班组**六块都在**吗？
2. 农历是**完整描述**（「农历 丙午年 … · 生肖 …」）吗？最多两行、没有截成「…」吗？
3. 内容是不是**垂直居中**、上下留白大致均匀？
4. 字看着是「舒展」还是「被撑大」？（这一条是 spec §5.2 留给真机定的一件事，你的判断就是结论；若觉得被撑大，把字号回调一档并重跑本步。）
5. 卡片底只有**一层**吗（边框没有双线）？

**另外验跨天降级**（这条最容易静默出错）：把系统时间往后拨一天，回桌面看——农历与「其他班组」应当**消失**，日期/班次/时间仍然正确；验完把时间拨回自动。

- [ ] **Step 6: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/android/app/src/main/res/layout/widget_today_standalone.xml \
        app/android/app/src/main/res/layout/widget_today_card.xml \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt
git commit -m "feat(widget): 4×3 今日卡独立成卡（大一号字 + 完整农历），跨天降级不变"
```

---

## Task 7: 4×5 整月

**Files:**
- Create: `app/android/app/src/main/res/layout/widget_month_card.xml` / `widget_month_cell.xml`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`

**Interfaces:**
- Produces:
  ```kotlin
  private fun monthCard(
      context: Context, snap: WidgetStore.Snapshot, todayIndex: Int, widgetId: Int,
  ): RemoteViews
  ```
  渲染哪个月 = `LocalDate.now()` 的月（**不是**快照的生成月）；前导空格 = 本月 1 日的星期几。

- [ ] **Step 1: 生成 42 槽的月历壳**

用与 Task 1 同一个生成脚本（**产物提交进仓库**），但这次带上标题行与周几行：

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
python - <<'PY'
slots = "\n\n".join(
    f'''    <FrameLayout
        android:id="@+id/wg_m_slot{i}"
        android:layout_width="0dp"
        android:layout_height="56dp"
        android:layout_columnWeight="1" />'''
    for i in range(1, 43)
)
weekdays = "\n\n".join(
    f'''    <TextView
        android:id="@+id/wg_m_wd{i}"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:gravity="center"
        android:textSize="11sp"
        android:maxLines="1" />'''
    for i in range(1, 8)
)
xml = f'''<?xml version="1.0" encoding="utf-8"?>
<!--
  4×5 整月的外壳：卡底 + 月份标题行 + 周几行 + 7×6 格。

  ⚠️ **格子不带白卡**（spec §4.2）：App 里每格是一张白卡，那是因为底下垫着中性底
  #F5F6FA；桌面上卡底是 96% 不透明、42 张叠起来会糊成一片，而且正是本轮要拆掉的套娃。
  分区靠间距与明度。

  ⚠️ 月份标题**查不到就隐藏**（原生从快照的 months 里按「年-月」查）：
  绝不借相邻月份的标题顶上 —— 那是「不让卡片理直气壮地写错」这条纪律的又一入口。

  ⚠️ 网格高 wrap_content + 根 gravity="center_vertical"：5 行的月份（多数月份）
  让网格整体居中、上下均匀留白，不为凑满 6 行而拉高格子。
  高度预算见 spec §5.3：可用约 442dp − 标题 18 − 周几 15 − 间距 8 ≈ 401dp，6 行 × 65.5dp。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_m_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center_vertical"
    android:background="@drawable/widget_card_light"
    android:padding="8dp">

    <TextView
        android:id="@+id/wg_m_title"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:gravity="center"
        android:textSize="13sp"
        android:maxLines="1"
        android:ellipsize="end" />

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="4dp"
        android:orientation="horizontal">

{weekdays}
    </LinearLayout>

    <GridLayout
        android:id="@+id/wg_m_grid"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="4dp"
        android:columnCount="7">

{slots}
    </GridLayout>
</LinearLayout>
'''
open('app/android/app/src/main/res/layout/widget_month_card.xml', 'w', encoding='utf-8').write(xml)
print('ok')
PY
```

`app/android/app/src/main/res/layout/widget_month_cell.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  月历的**一格**：日数字 / 班次胶囊 / 农历。42 格共用这一张。
  根 match_parent：它被塞进 FrameLayout 槽位，自己声明 match_parent 才与外层一致。
  内容约 59dp，槽位 56dp —— 靠 gravity="center" 吸收，真机图核对有没有被裁（Task 7 Step 4）。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_mc_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center">

    <TextView
        android:id="@+id/wg_mc_day"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:textSize="16sp"
        android:maxLines="1" />

    <FrameLayout
        android:layout_width="40dp"
        android:layout_height="18dp"
        android:layout_marginTop="3dp">

        <ImageView
            android:id="@+id/wg_mc_pill"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:scaleType="fitXY"
            android:contentDescription="@null" />

        <TextView
            android:id="@+id/wg_mc_abbr"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:gravity="center"
            android:textSize="11sp"
            android:maxLines="1" />
    </FrameLayout>

    <TextView
        android:id="@+id/wg_mc_lunar"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="2dp"
        android:textSize="11sp"
        android:maxLines="1"
        android:ellipsize="end" />
</LinearLayout>
```

> ⚠️ 槽位高 56dp 而内容约 59dp —— **差 3dp**。真机图若见农历被裁，把槽位改成 `60dp`
> 并把网格允许高度核一遍（6×60 + 表头 41 = 401 ≤ 442 ✓ 仍有 41dp 余量）。
> 这个数不要靠估算放行，以 Task 7 Step 4 的图为准。

- [ ] **Step 2: 写渲染函数**

```kotlin
    /**
     * 4×5 整月：月份标题 + 周几行 + 6×7 格。
     *
     * **渲染哪个月由 `LocalDate.now()` 定**，不由快照的生成月定：快照窗口覆盖
     * 「本月 + 下月」（spec §7.1），跨月那一刻零点那次刷新会重渲染，此时今天已经
     * 落在新的一个月里 —— 数据早就在窗口里，不需要 App 活着。
     *
     * **前导空格**由本月 1 日的星期几现算（周一 = 1）—— 纯日期算术，不是 i18n，
     * 与不变量 (A) 不冲突。
     *
     * 月份标题从 `snap.months` 里按「年-月」查；**查不到就隐藏标题行**，
     * 绝不借相邻月份的标题顶上。
     */
    private fun monthCard(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_month_card)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_m_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.setOnClickPendingIntent(R.id.wg_m_root, launchIntent(context, rootRequestCode(widgetId)))

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted = context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)
        val empty = context.getColor(if (dark) R.color.wg_empty_dark else R.color.wg_empty_light)
        val holiday = context.getColor(R.color.wg_holiday)

        val today = LocalDate.now()
        val todayEpoch = today.toEpochDay()

        // ── 月份标题 ──
        val title = snap.months.firstOrNull { it.y == today.year && it.m == today.monthValue }
        if (title == null) {
            v.setViewVisibility(R.id.wg_m_title, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_m_title, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_m_title, title.title)
            v.setTextColor(R.id.wg_m_title, muted)
        }

        // ── 周几行（7 条文案来自快照，原生不做 i18n） ──
        val wdIds = intArrayOf(
            R.id.wg_m_wd1, R.id.wg_m_wd2, R.id.wg_m_wd3, R.id.wg_m_wd4,
            R.id.wg_m_wd5, R.id.wg_m_wd6, R.id.wg_m_wd7,
        )
        for (i in wdIds.indices) {
            val text = snap.weekdays.getOrNull(i)
            if (text == null) {
                v.setViewVisibility(wdIds[i], android.view.View.GONE)
            } else {
                v.setViewVisibility(wdIds[i], android.view.View.VISIBLE)
                v.setTextViewText(wdIds[i], text)
                v.setTextColor(wdIds[i], muted)
            }
        }

        // ── 42 格 ──
        val firstOfMonth = today.withDayOfMonth(1)
        val leading = firstOfMonth.dayOfWeek.value - 1   // 周一 = 1 → 前导空格数
        val daysInMonth = firstOfMonth.lengthOfMonth()
        val slotIds = IntArray(42) { i ->
            context.resources.getIdentifier("wg_m_slot${i + 1}", "id", context.packageName)
        }

        for (slot in 0 until 42) {
            val dayOfMonth = slot - leading + 1
            if (dayOfMonth < 1 || dayOfMonth > daysInMonth) {
                // 前导/尾随空格：GONE —— GridLayout 里 GONE 的子视图不参与布局。
                v.setViewVisibility(slotIds[slot], android.view.View.GONE)
                continue
            }
            val date = firstOfMonth.withDayOfMonth(dayOfMonth)
            val epoch = date.toEpochDay()
            val i = snap.days.indexOfFirst { it.day == epoch }
            if (i < 0) {
                // 窗口里没有这天（理论上不会发生）。当成空格而不是「没班次」——
                // 后者会画出一张理直气壮的空格。
                v.setViewVisibility(slotIds[slot], android.view.View.GONE)
                continue
            }
            v.setViewVisibility(slotIds[slot], android.view.View.VISIBLE)

            // 点某一格 → 打开 App 并跳到那天。格子占槽位 1..42（一个实例 64 个槽位）。
            v.setOnClickPendingIntent(
                slotIds[slot],
                launchIntent(context, cellRequestCode(widgetId, slot), epochDay = epoch.toInt()),
            )

            val d = snap.days[i]
            val isToday = epoch == todayEpoch
            val c = RemoteViews(context.packageName, R.layout.widget_month_cell)
            for (id in intArrayOf(R.id.wg_mc_day, R.id.wg_mc_pill, R.id.wg_mc_abbr, R.id.wg_mc_lunar)) {
                c.setViewVisibility(id, android.view.View.VISIBLE)
            }

            c.setTextViewText(R.id.wg_mc_day, dayOfMonth.toString())
            c.setTextColor(R.id.wg_mc_day, if (isToday) snap.accent else ink)

            c.setImageViewBitmap(
                R.id.wg_mc_pill,
                WidgetChip.tintedChip(
                    if (d.hasShift) d.color else empty,
                    dpToPx(context, 40),
                    dpToPx(context, 18),
                ),
            )
            c.setTextViewText(R.id.wg_mc_abbr, if (d.hasShift) d.shiftAbbr else "")
            c.setTextColor(R.id.wg_mc_abbr, ink)

            c.setTextViewText(R.id.wg_mc_lunar, d.lunarShort)
            c.setTextColor(R.id.wg_mc_lunar, if (d.lunarIsHoliday) holiday else muted)

            v.addView(slotIds[slot], c)
        }
        return v
    }
```

顶部补：`import android.content.res.Resources` 其实不用 —— 用 `context.resources` 即可，把上面第二处 `resources.getIdentifier` 改成 `context.resources.getIdentifier`。

- [ ] **Step 3: requestCode 槽位基数 32 → 64**

```kotlin
    /**
     * 每个小组件实例占用的 requestCode 槽位数。
     *
     * 需要 `Root` + 42 个月历格 = 43，向上取到 64。
     *
     * ⚠️ **这个数不是随便取的，它是编址方案的护栏。** `Cell(w, n) = B + 64w + 1 + n`，
     * 当槽位数为 64 时 `n` 取满 63 也不会进位到 `B + 64(w+1)` ——
     * 即 `Cell` 恒落在 `[64w+1, 64w+63]`、**永不为 64 的倍数**，而 `Root` 恒为 64 的倍数，
     * 两者结构性错开。这个撞车类在本仓**真实发生过**（见 `launchIntent` 的 KDoc）。
     * 基数从 32 提到 64 之后，`Int` 溢出的 widgetId 上限从约 6710 万降到约 3350 万，
     * 仍远够用。
     */
    private const val REQ_SLOTS_PER_WIDGET = 64
```

（`rootRequestCode` / `cellRequestCode` 的表达式不用改 —— 它们本来就乘这个常量。）

- [ ] **Step 4: 接进 `render()` 并出图**

```kotlin
            WidgetVariant.MONTH -> monthCard(context, snap, todayIndex, widgetId)
```

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
"$ADB" shell am force-stop com.miui.home; sleep 2
"$ADB" shell am force-stop com.daoban.shiftassistantpro
"$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity; sleep 6
"$ADB" shell input keyevent KEYCODE_HOME; sleep 3
"$ADB" exec-out screencap -p > /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/work/card_month.png
"$ADB" logcat -d -s ShiftAssistant | tail -10
```

**自己 Read `work/card_month.png`**，回答：

1. 表头是「2026年9月」+ 一~日吗？
2. 格子的日数字**与真实日历对得上**吗（前导空格数对不对 —— 拿手机日历核第一个日期落在星期几）？
3. **今天是主色**吗？
4. 每格三行（日数字 / 胶囊 / 农历）**都在、没被裁**吗？
5. 网格整体垂直居中吗？5 行的月份上下留白是不是大致均匀？
6. logcat 有没有 RemoteViews / TransactionTooLarge 相关异常（Task 1 验过了，这里是复核）？

**再验一个 6 行的月份**：把系统时间拨到任意一个 6 行的月份（例如 2026 年 11 月：11/1 是周日），
回桌面确认网格变成 6 行、仍然居中。**验完把时间拨回自动。**

- [ ] **Step 5: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/android/app/src/main/res/layout/widget_month_card.xml \
        app/android/app/src/main/res/layout/widget_month_cell.xml \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt
git commit -m "feat(widget): 4×5 整月（月份标题 + 周几行 + 42 格），requestCode 槽位扩到 64"
```

---

## Task 8: 清账（删旧版式、空表态、requestCode 文档、AGENTS.md）

**Files:**
- Create: `app/android/app/src/main/res/layout/widget_empty.xml`
- Delete: 旧的七张布局 + `WidgetTier.kt`
- Modify: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`
- Delete: `app/test/widget_tier_thresholds_test.dart`
- Modify: `AGENTS.md`

- [ ] **Step 1: 空表态改用共享布局**

创建 `app/android/app/src/main/res/layout/widget_empty.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  空表态：没有排班（`hasSchedule == false`）。**三张卡共用这一张** —— 空表本来
  也没什么可说的，三档各写一张只会长成三个样。

  提示文字来自快照的 emptyHint（Dart 侧 L10n 产出）：Kotlin 侧仍然一个字面量都没有。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_e_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center"
    android:background="@drawable/widget_card_light"
    android:padding="16dp">

    <TextView
        android:id="@+id/wg_e_hint"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:gravity="center"
        android:textSize="13sp"
        android:maxLines="3"
        android:ellipsize="end" />
</LinearLayout>
```

`WidgetRenderer.empty()` 改成渲染它（原来的实现挂在 `widget_list_compact` 上，那张布局要删了）：

```kotlin
    /**
     * 空表态：没有排班（`snap.hasSchedule == false`）。
     *
     * 三张卡共用一张布局 —— 空表本来也没什么可说的，三档各写一张只会长成三个样。
     * 文案来自快照的 `emptyHint`（Dart 侧 `L10n.widgetEmptyHint` 产出）。
     */
    private fun empty(context: Context, snap: WidgetStore.Snapshot, widgetId: Int): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_empty)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_e_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.setOnClickPendingIntent(R.id.wg_e_root, launchIntent(context, rootRequestCode(widgetId)))
        v.setTextViewText(R.id.wg_e_hint, snap.emptyHint)
        v.setTextColor(
            R.id.wg_e_hint,
            context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light),
        )
        return v
    }
```

- [ ] **Step 2: 删旧版式**

先确认没人再引用它们：

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
grep -rn "widget_list\|widget_row\|widget_grid_\|widget_cell\|gridWithCard\|gridCells\|listRows\|relativeLabel" \
     app/android/app/src/main/kotlin/ || echo "旧渲染函数已无引用 ✓"
```

把 `WidgetRenderer.kt` 里 `listRows` / `gridCells` / `gridWithCard` / `relativeLabel` 四个函数**整段删除**
（`relativeLabel` 只被 `listRows` 用；「今天/明天/后天」这三个相对称法本轮三张卡都不再使用 ——
本周条用周几、今日卡用绝对日期、月历用日数字。**顶层 `labels.today/tomorrow/dayAfter` 保留在协议里**
，Dart 侧仍在发，将来要用不必改协议）。

```bash
git rm app/android/app/src/main/res/layout/widget_list_compact.xml \
       app/android/app/src/main/res/layout/widget_list.xml \
       app/android/app/src/main/res/layout/widget_row.xml \
       app/android/app/src/main/res/layout/widget_grid_week.xml \
       app/android/app/src/main/res/layout/widget_grid_fortnight.xml \
       app/android/app/src/main/res/layout/widget_cell.xml \
       app/android/app/src/main/res/layout/widget_grid_with_card.xml \
       app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetTier.kt \
       app/test/widget_tier_thresholds_test.dart
```

- [ ] **Step 3: 删净检查**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
grep -rn "WidgetTier\|widget_list\|widget_row\|widget_grid\|widget_cell\|gridWithCard" \
     android/app/src/main/ && echo "↑ 还有引用，逐条清掉" || echo "旧版式已删净 ✓"
grep -rn "TASK4 临时\|临时：全部走旧版式" android/app/src/main/ && echo "↑ 还有临时脚手架" || echo "临时脚手架已删净 ✓"
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter test
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
```

Expected: 两条「已删净 ✓」、`No issues found!`、测试全绿、`√ Built …app-release.apk`。

`flutter test` 里 `widget_layout_whitelist_test.dart` 会自动扫到 `widget_empty.xml` 与三张 `widget_preview_*.xml` —— 它们只用白名单里的类，应当直接绿。**再做一次「先红后绿」**：把 `widget_month_cell.xml` 里某个 `<ImageView` 临时改成 `<View`，重跑应当**点名那一行且行号正确**；改回去重跑应当绿。把两趟的命令与输出原文写进报告。

- [ ] **Step 4: 更新 `AGENTS.md`**

**(a)** 「关键决策与坑」里那条小组件决策**整体改写**（现在写的是五档 + 阈值）：三张固定卡的名字与尺寸、`resizeMode="none"`、窗口是「本月 + 下月」的绝对窗口（含过去的天）、协议 v2、胶囊走 14% 淡染 + 45% 描边（文字走 `wg_ink_*`）、月历格子不带白卡、月份标题查不到就隐藏、旧实例失效这件事。

**(b)** requestCode 那条：`Root(n)=B+64n`、`Cell(m,c)=B+64m+1+c`，溢出上限约 3350 万。

**(c)** 「最近改动」加一条 `v0.8.8`（测试版），要点：三张固定卡取代五档自适应；**旧小组件会消失、需重新添加**；月历要 42 格位图、已真机验过。

**(d)** 版本史那行末尾加 `→ 0.8.7(+98) 测试版 → 0.8.8(+99) 测试版`。

- [ ] **Step 5: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add -A app/ AGENTS.md
git commit -m "refactor(widget): 删旧五档版式与 WidgetTier，空表态三卡共用，文档口径同步"
```

---

## Task 9: 收尾 —— 版本号、更新日志、文档、发布、最终真机清单

**Files:**
- Modify: `app/pubspec.yaml` · `app/lib/core/app_info.dart` · `app/lib/features/profile/app_dialogs.dart`
- Modify: `README.md` · `PRODUCT_SPEC.md`

- [ ] **Step 1: 版本号两处同步**

`0.8.7+98` → `0.8.8+99`。

Run: `cd app && flutter test test/app_info_test.dart` — 必须绿。

- [ ] **Step 2: 更新日志**

`app_dialogs.dart` 的 `_changelogZh` / `_changelogEn`：prepend `v0.8.8`、删最旧一条、保持 10 条。**测试版规则**（只写这一版改了什么）。

要点（**只说事实，不用绝对话** —— 这个项目被「假保证文案」咬过五次）：

- 小组件改成三张固定尺寸的卡：本周、今日、整月；放置后不能再拉伸
- 视觉回归日历页的设计语言（班次胶囊改为淡染 + 描边，去掉白卡叠白卡）
- 整月那张要重新添加 —— **旧的小组件在升级后会消失**

- [ ] **Step 3: 两份文档**

`README.md`：小组件那段改写（三张卡分别是什么、怎么找、**不可拉伸**、升级后要重新添加）。
`PRODUCT_SPEC.md`：受影响条目改写 + 抬头版本号。

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter test
```

Expected: `No issues found!` 与全绿（265 + 新增的若干条）

- [ ] **Step 4: 提交、打 tag、构建、发布**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git tag v0.8.8
git push origin main --tags
```

然后跑 `scripts/release.ps1`。⚠️ **要单独设 `GH_CONFIG_DIR`**（`build-env.ps1` 重定向了 `APPDATA`，`gh` 会报「未认证」）：

```powershell
$env:GH_CONFIG_DIR = "$env:USERPROFILE\AppData\Roaming\GitHub CLI"
```

它应当自动判为**预发布（测试版）**（末位 8 ≠ 0）。

- [ ] **Step 5: 最终真机清单（发布版 APK）**

装发布包，把三张卡都放上桌面，逐条走：

| # | 验什么 | 判据 |
|---|---|---|
| 1 | 三张卡各截一张（浅色） | 版式、占比、留白对得上 spec §5 |
| 2 | 三张卡各截一张（深色） | 同上；改色前先 `am force-stop com.miui.home` |
| 3 | 4×1 的 5dp 余量 | 三行一个不少、不裁（被裁则用 Task 5 的两行备选并重截） |
| 4 | 5 行月 / 6 行月 | 网格居中、无空行残留 |
| 5 | 月历逐格点击 | 点至少 4 格（含今天、含一个空白前导格旁的日子），都跳到正确那天 |
| 6 | 本周条逐列点击 | 点今天那列 + 一列别的，都跳到正确那天 |
| 7 | 跨天 | 拨系统时间过零点：本周条跟着翻周、今日卡降级态正确；**跨月那天亲手拨一次**，月历翻到新月份 |
| 8 | 空表态 | 清空排班，三张卡都显示提示文案 |
| 9 | 占位态 | 清掉 App 数据（或 `am force-stop` 后卸载重装）后未打开 App 时，三张卡是占位态；打开 App 后自动恢复 |
| 10 | picker 三条 | 名字互不相同、缩略图互不相同、都加得上去 |
| 11 | 不可拉伸 | 长按卡片**没有缩放手柄** |

把每一条的结果（图 + 一句话结论）写进报告。**任何一条不符都不要自行判定为「小问题」** ——
写进报告等评审。

---

## 自审记录

**Spec 覆盖**：§1.2 三条病根 → §4 视觉配方（胶囊配方在 Task 5/7 的 `tintedChip` + `wg_ink_*`、无套娃在 Task 6 Step 1 与 Task 7 的「格子不带白卡」、为尺寸设计在三张卡各自的排版表）；§2 决策①→Task 4、②→Task 7、③→Task 2、④→Task 6、⑤→Task 7（只做 4×5）、⑥→Task 4 的 `ShiftWidgets.scheduleNextRefreshIfNeeded` 注释、⑦→Task 4、⑧→Task 4 Step 4 的三张 `widget_preview_*.xml`；§3 尺寸声明 → Task 4 Step 4；§4.3 今天走主色 → Task 5/7；§5 三张卡版式 → Task 5/6/7；§6.1~6.4 结构 → Task 4（6.4 的 64 槽在 Task 7 Step 3）；§6.5 文件清单 → 全文；§7 快照 → Task 2/3；§8 预览 → Task 4 Step 4；§9 迁移 → 先导事实 C + Task 9 Step 2/3；§10 边界容错 → Task 2（窗口恒含今天）、Task 5/7（查不到就 GONE，不画成空）、Task 6（跨天降级保留）、Task 8（空表态）；§11 不做 → 全文未涉及；§12 测试 → Task 2 的四条新用例 + Task 8 的守门红绿 + Task 9 的真机清单；§13 收尾 → Task 8 Step 4 + Task 9；§14 风险 → §14.1 落 Task 1、§14.2 落 Task 5 Step 4、§14.3 落 Task 7、§14.4 落 Task 7 Step 3、§14.5 落先导事实 C 与 Task 9、§14.6 落 Task 5/7 的「可见性无条件设满」、§14.7 先导事实 A/D、§14.8~14.10 落在各构建步骤。

**两处对 spec 的补充**（执行时按计划做，并在 spec 修订记录里补一笔）：

1. **Task 3 会临时把 `gridCells` 的胶囊字色从 `abbrInk` 改成 ink** —— spec §4.1 决定了要删 `abbrInk`，而它在旧网格里还有一个消费者，于是「删字段」与「换配方」必须同时发生，否则 Kotlin 编不过。Task 8 删掉整个 `gridCells` 之后这处临时改动自然消失。
2. **`ShiftWidgetBase` 去掉了 `onAppWidgetOptionsChanged`** —— 旧 provider 有它（尺寸变了要重渲染），而本轮三张卡都 `resizeMode="none"`，那个回调不会再来。spec §6.1 只说了「去掉分档」，没点到这个回调该不该留。
3. **`widget_month_cell.xml` 的槽位高 56dp vs 内容约 59dp** —— spec §5.3 写的是「格高 65.5dp」，而 65.5 是**每行可用高度**（401dp ÷ 6），其中要放 56dp 的格子 + 行间距，不是格子本身的高度。执行时以 Task 7 Step 4 的真机图为准（被裁就提到 60dp）。

**类型一致性**：`WidgetVariant` 的三个枚举名（`WEEK_STRIP` / `TODAY` / `MONTH`）在 Task 4 定义、Task 5/6/7 使用；`ShiftWidgets.refreshAll / hasAnyInstance / scheduleNextRefreshIfNeeded / cancelRefreshIfNone / render` 在 Task 4 定义并自用；`WidgetRenderer.render(context, snap, variant, widgetId)` 的签名在 Task 4 定、Task 5/6/7 保持；`WidgetStore.MonthTitle.y/m/title` 与 Dart 侧 `months[].y/m/title` 逐字段对齐；`Day.lunarShort/lunarIsHoliday` 与 Dart 侧 `days[].lunarShort/lunarIsHoliday` 对齐；`TodayCard.lunarFull` 与 Dart 侧 `todayCard.lunarFull` 对齐。
