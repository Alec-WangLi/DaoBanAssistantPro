# 桌面小组件（三档尺寸） Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给「倒班助手Pro」加一个桌面小组件，小/中/大三档尺寸分别显示今天、未来三天、未来一周的班次，跨天自动翻页。

**Architecture:** Dart 侧生成一份「已本地化的快照」写进 SharedPreferences，原生 Kotlin 的 `AppWidgetProvider` 读它并用 `RemoteViews` 排版。原生侧不持有任何文案、不做日期格式化、不算轮转 —— 它只做「取数 → 选档位 → 排版 → 排下一次刷新」。

**Tech Stack:** Flutter 3.47 / Dart 3.13 · Android `AppWidgetProvider` + `RemoteViews`（无新依赖）· `java.time`（minSdk 26，不需要脱糖）· `AlarmManager` · Riverpod · Drift

**Spec:** `docs/superpowers/specs/2026-09-18-home-widget-design.md` —— 本计划的每一处设计取舍都论证自它；执行时两份一起读。

## Global Constraints

- **版本号**：`X.Y` 由**用户**决定，AI 只能改末位 `Z` 与 `build`。本轮目标 `0.8.4+95`。`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须同步（`app/test/app_info_test.dart` 盯着）。
- **不要跑 `dart format`** —— 工具链是新版 tall style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `flutter analyze`。
- **构建/测试的环境变量**（bash 里必须先 export，否则 Gradle 会去 `~/.gradle` 下载到超时）：
  ```bash
  export JAVA_HOME=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/jdk
  export ANDROID_HOME=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/android-sdk
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export GRADLE_USER_HOME=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/gradle-home
  export PUB_CACHE=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/pub-cache
  export ANDROID_USER_HOME=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/android-user
  export PATH=/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH
  ```
  `adb` 不在 PATH 里，用绝对路径 `/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/android-sdk/platform-tools/adb.exe`，下称 `$ADB`。
- **装到真机一律用 `flutter build apk --release`，不能用 `--debug`。** 目标机上那个
  App 是 **release 密钥**签的（证书 SHA-256 `26:5D:09:B2:8F:D0:6B:19:85:B7:A0:91:AD:EB:D7:AE:97:8E:E5:76:3E:77:08:B5:AF:AC:71:EF:CE:DC:E8:93`，与 `app/android/keystore/release.jks` 一致），
  debug APK 是自动生成的 debug 密钥，`adb install -r` 会报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。
  卸载重装会**丢掉用户的真实排班数据**，所以只能走 release 构建。实测约 70 秒一次。
  附带好处：release 开了 `isMinifyEnabled = true`，顺带真的验一遍 R8 没把 `ShiftWidgetProvider` 裁掉。
- **`RemoteViews` 视图白名单**：布局只用 `FrameLayout` / `LinearLayout` / `RelativeLayout` / `GridLayout`；控件只用 `TextView` / `ImageView` / `Button` / `ProgressBar` / `Chronometer` / `TextClock`。**没有 `ConstraintLayout`**，且**不能用这些类的子类**。
  - ⚠️ **白名单是靠 `@RemoteView` 注解过滤的，所以 `android.view.View` 与 `android.widget.Space` 都不行**（两者都没这个注解）。实测本仓 `android-36/android.jar`：`View`/`ViewGroup`/`Space` 为 0，`TextView`/`ImageView`/`LinearLayout`/`FrameLayout`/`GridLayout` 为 7（`javap -v` 数 `RemoteView` 出现次数）。**想要一条 1dp 分隔线或一个占位弹簧，要用 `ImageView`** —— 用 `<View>` 的后果是宿主在 `apply()` 阶段抛 `InflateException: Class not allowed to be inflated android.view.View`，**整张卡片渲染不出来**，而不是只丢那一条线。Task 3 实做时踩中，评审用 `javap` 实测发现。`setViewVisibility(id, android.view.View.GONE)` 里引用 `View.GONE` 这个**常量**没问题 —— 受限的是被 inflate 的类，不是常量。
- **包名** `com.daoban.shiftassistantpro`；`minSdk = 26`、`targetSdk = 36`（`flutter.targetSdkVersion`）。`release` 构建 `isMinifyEnabled = true`，新增的 `AppWidgetProvider` **必须**在 `AndroidManifest.xml` 里显式声明，否则会被 R8 裁掉。
- **测试只增不减**（本分支起点 `e503b78` 实测 `241` 条 —— 计划初稿写的 170 是抄自更早那份 spec 的旧值，Task 1 的评审指出后已改正）。
- **文案一律走 `L10n`**（`app/lib/core/l10n.dart`），不要在任何地方硬编码中文字符串。Kotlin 侧一个中文字面量都不许出现。
- **设计数值一律引用令牌**（`app/lib/core/design_tokens.dart` / `app/lib/core/theme/app_colors.dart`），不要在 Dart 里内联 magic number。

---

## 给执行者的两件先导事实

### A. 为什么不能靠 `adb shell am broadcast` 触发刷新

小组件的 receiver 必须是 `android:exported="false"`，而 `adb shell` 以 shell（uid 2000）身份发广播，**到不了非导出的 receiver**。所以本计划一律用这两条：

```bash
# 触发一次 Dart 侧 push（走 App 启动 → watchActiveSchedule → WidgetService.push）
# **必须先 force-stop**：App 已在前台时 `am start` 只走 onNewIntent、不重跑
# initState，那条推送路径根本不会发生（Task 3 实做时踩到）。force-stop 只杀进程，
# 不动数据 —— 不要用卸载或 pm clear。
"$ADB" shell am force-stop com.daoban.shiftassistantpro; "$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity

# 看「下一次刷新排在了几点」—— 不用真的等到那一刻
"$ADB" shell dumpsys alarm | grep -A3 shiftassistantpro
```

冷启动会 push **两次**（首帧回调一次 + `activeScheduleProvider` 首次下发一次），原生据此
`refreshAll` 两次。幂等、无功能危害，属预期。

改排班、改主题、改语言之后要刷新小组件，**都是启动一次 App**（`am start` 对已在跑的 Activity 走 `onNewIntent`，同样能触发）。别去折腾 `am broadcast`，那会白花半小时。

### B. 真机与工具链的杂项

- 目标机：Redmi `25102RKBEC`、HyperOS（`ro.miui.ui.version.code = 816`）、启动器 `com.miui.home`、屏幕 1200×2608 @480dpi（= **400dp 宽**），已连 ADB。
- 这台机的 `getprop` 是**伪装过的**（`ro.build.version.sdk` 报 21、`release` 报 6.0.1，而安装的包 `targetSdk=36`）。判断系统能力时以 `dumpsys package` 与实测行为为准。
- 截图：`"$ADB" exec-out screencap -p > work/wg.png`（`work/` 已 gitignore）。
- 日志：`AlarmLog.info` 只写 Logcat（`adb logcat -s ShiftAssistant`），`AlarmLog.error` 另写 `filesDir/app_log.txt`。

---

## 文件结构

**新增（Dart）**

| 文件 | 职责 |
|---|---|
| `app/lib/features/widget/widget_snapshot.dart` | 纯函数：`ShiftSchedule` + 时刻 + 主题 → 快照 `Map`。**不碰 Channel、不读挂钟** |
| `app/lib/features/widget/widget_service.dart` | 投递快照、消费「点某天」意图、`epochDay ↔ DateTime` 换算 |
| `app/test/widget_snapshot_test.dart` | 上两者的纯逻辑用例 |

**新增（Kotlin，`app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/`）**

| 文件 | 职责 |
|---|---|
| `WidgetStore.kt` | 快照的落盘 / 读取 / 解析（含 `Snapshot` / `Day` 数据类）。`AlarmStore` 的同族 |
| `WidgetTier.kt` | `enum WidgetTier` + `pick(widthDp, heightDp)`。四次整数比较，一个文件只干这件事 |
| `WidgetRenderer.kt` | `(快照, 档位, 明暗, 尺寸) → RemoteViews`。纯排版，不排闹钟、不写盘 |
| `WidgetRefreshScheduler.kt` | 把「下一个边界」排进 `AlarmManager`，权限缺失时降级 |
| `ShiftWidgetProvider.kt` | `AppWidgetProvider`：收系统回调与自定义刷新 action，串起上面四个 |

**新增（资源，`app/android/app/src/main/res/`）**

| 文件 | 职责 |
|---|---|
| `xml/shift_widget_info.xml` | `appwidget-provider` 元数据 |
| `layout/widget_placeholder.xml` | `initialLayout`，同时也是「无快照 / 快照过期」的降级态 |
| `layout/widget_small.xml` / `widget_medium.xml` / `widget_large.xml` | 三档布局 |
| `drawable/widget_card_light.xml` / `widget_card_dark.xml` | 卡片底（`<shape>` 渐变 + 圆角） |
| `drawable/widget_pill_light.xml` / `widget_pill_dark.xml` | 空白天/占位用的实心圆角（非班次色） |
| `values/widget_colors.xml` | 从 `design_tokens.dart` 翻译过来的色值 |

**修改**

| 文件 | 改什么 |
|---|---|
| `app/android/app/src/main/AndroidManifest.xml` | 加 `<receiver>` + `<meta-data>` |
| `app/android/app/src/main/kotlin/.../MainActivity.kt` | channel 加两个方法；`pendingWidgetDay`；`handleWidgetIntent` |
| `app/android/app/src/main/kotlin/.../BootReceiver.kt` | 补一次小组件刷新重排 |
| `app/lib/core/l10n.dart` | 小组件文案 |
| `app/lib/features/alarm/alarm_service.dart` | channel handler 里加 `onWidgetDayTapped` 分支 |
| `app/lib/features/home/home_shell.dart` | 启动 push + 订阅排班/设置变化 + 消费「点某天」 |
| `app/lib/features/calendar/calendar_screen.dart` | 消费 `widgetLaunchRequested`，跳到指定日期 |
| 文档与版本号 | 见 Task 8 |

---

## Task 1: 快照生成（纯 Dart）

这一层是本设计的地基：原生侧显示什么，全由这里决定。它是**纯函数** —— 不读 `DateTime.now()`（当前时刻由参数传入）、不碰 `MethodChannel`、不碰 Flutter 的渲染层。理由与 `alarm_service.dart` 里 `planShiftAlarms` 的注释一字不差：本项目没有可运行的原生插件目标，只有抽成纯函数才盖得到测试。

**Files:**
- Create: `app/lib/features/widget/widget_snapshot.dart`
- Create: `app/test/widget_snapshot_test.dart`
- Modify: `app/lib/core/l10n.dart`（文件末尾，`yearMonthDay` 之后）

**Interfaces:**
- Consumes: `ShiftSchedule` / `ShiftClass` / `dayNumber` / `dateOnly` / `formatClock`（`app/lib/domain/shift_rotation.dart`）· `L10n`（`app/lib/core/l10n.dart`）· `AppTokens.onSolid`（`app/lib/core/design_tokens.dart`）
- Produces:
  - `const int kWidgetSnapshotVersion` = `1`
  - `const int kWidgetSnapshotDays` = `14`
  - `Map<String, Object?> buildWidgetSnapshot({required ShiftSchedule? schedule, required DateTime now, required String themeMode, required int accent})`

- [ ] **Step 1: 先加文案（`l10n.dart`）**

在 `app/lib/core/l10n.dart` 里 `yearMonthDay` 那个 getter 之后、类闭合大括号之前追加：

```dart
  // 桌面小组件。只有「今天/明天/后天」与空表提示是本轮新文案 ——
  // 时间串复用既有的 [timeRange]，日期串复用 [monthDay]，周几复用 [weekday]，
  // 一个都不新造（`timeRange` 的注释写明了中英语序不同、整串必须过 `t()`）。
  static String get widgetToday => t('今天', 'Today');
  static String get widgetTomorrow => t('明天', 'Tomorrow');
  static String get widgetDayAfter => t('后天', 'Day after');
  static String get widgetEmptyHint =>
      t('还没有排班，点一下去设置', 'No schedule yet — tap to set up');
```

> 先确认 `L10n.today`（已存在于 `l10n.dart:278`）与 `widgetToday` 不是重复的东西：前者是日历页在别处用的，语义相同但**调用点不同**，本轮不去动既有那条，避免牵动既有测试。

- [ ] **Step 2: 写失败的测试**

创建 `app/test/widget_snapshot_test.dart`：

```dart
// 桌面小组件快照 —— 纯函数 `buildWidgetSnapshot`。
//
// 为什么这一层值得单独测：整个小组件的正确性都压在它身上。原生侧只是个排版器
// （Kotlin 里一个中文字符串都没有），所以「今天/明天对不对」「跨午夜班次的时间串
// 对不对」「14 天窗口够不够」这些判断一旦错了，真机上表现为「卡片显示别的班的
// 时间」，而且不报错。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/widget/widget_snapshot.dart';

/// 与 `shift_alarm_decision_test.dart` 同款：班次名写死，用例断言**结构**不论文案。
ShiftSchedule _schedule() => ShiftSchedule(
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
    );

void main() {
  // `L10n.monthDay` 走 `DateFormat('M月d日', 'zh')`，**必须先装 locale 数据**，
  // 否则 9 条用例全抛 `LocaleDataException`。中英两套都要装 —— 「英文界面下跨午夜
  // 不露出中文」那条会切到 en。这是本仓既有约定，照抄即可。
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
  });

  setUp(() => L10n.locale = 'zh');

  test('days 恒 14 条，day 逐日递增', () {
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
    );
    final days = s['days']! as List;
    expect(days.length, 14);
    for (var i = 0; i < 14; i++) {
      expect((days[i] as Map)['day'], dayNumber(DateTime(2026, 9, 18 + i)));
    }
  });

  test('空白表（schedule=null）仍产出 14 条空行，并带上空表提示', () {
    final s = buildWidgetSnapshot(
      schedule: null,
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'light',
      accent: 0xFF4F5BE8,
    );
    expect(s['hasSchedule'], false);
    expect(s['emptyHint'], L10n.widgetEmptyHint);
    final days = s['days']! as List;
    expect(days.length, 14);
    for (final d in days) {
      final m = d as Map;
      expect(m['hasShift'], false);
      expect(m['timeRange'], isNull);
      expect(m['color'], 0);
    }
  });

  test('空白表方案（schedule 非 null 但 isBlank）也算「没有排班」', () {
    final blank = ShiftSchedule(
      name: '跟随法定节假日',
      anchorDate: DateTime.utc(2026, 9, 18),
      classes: const [],
      cycle: const [],
    );
    final s = buildWidgetSnapshot(
      schedule: blank,
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
    );
    expect(s['hasSchedule'], false);
  });

  test('跨午夜班次的时间串由 L10n.timeRange 产出，不拼前缀', () {
    final s = buildWidgetSnapshot(
      // 9/19 在 3 天周期里是第 1 天 → 夜班（20:30 → 次日 08:30）
      schedule: _schedule(),
      now: DateTime(2026, 9, 19, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
    );
    final d0 = (s['days']! as List).first as Map;
    expect(d0['shiftName'], '夜班');
    expect(d0['timeRange'], L10n.timeRange('20:30', '08:30', true));
  });

  test('英文界面下跨午夜不露出中文', () {
    L10n.locale = 'en';
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: DateTime(2026, 9, 19, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
    );
    final d0 = (s['days']! as List).first as Map;
    expect((d0['timeRange']! as String).contains('次日'), false);
    expect(d0['timeRange'], '20:30 – 08:30 (next day)');
  });

  test('休班行没有时间串', () {
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: DateTime(2026, 9, 20, 10), // 周期第 2 天 → 休班
      themeMode: 'system',
      accent: 0xFF4F5BE8,
    );
    final d0 = (s['days']! as List).first as Map;
    expect(d0['isRest'], true);
    expect(d0['timeRange'], isNull);
  });

  test('boundaries 升序、无重复、都是未来时刻', () {
    final now = DateTime(2026, 9, 18, 10);
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: now,
      themeMode: 'system',
      accent: 0xFF4F5BE8,
    );
    final b = (s['boundaries']! as List).cast<int>();
    expect(b, isNotEmpty);
    for (var i = 1; i < b.length; i++) {
      expect(b[i] > b[i - 1], true, reason: '必须严格递增（已去重）');
    }
    for (final t in b) {
      expect(t > now.millisecondsSinceEpoch, true);
    }
    // 每天都贡献了**次日**的本地零点，所以 14 条全在未来（没有哪一条代表
    // 「今天零点已过」）。原稿这里的注释写反了，Task 1 实做时发现。
    expect(b.where((t) => t > now.millisecondsSinceEpoch).length >= 14, true);
  });

  test('主题模式原样透传，不在这里解析成 light/dark', () {
    for (final mode in ['system', 'light', 'dark']) {
      final s = buildWidgetSnapshot(
        schedule: _schedule(),
        now: DateTime(2026, 9, 18, 10),
        themeMode: mode,
        accent: 0xFF4F5BE8,
      );
      expect(s['themeMode'], mode);
    }
  });

  test('快照可以 JSON 往返（原生按 org.json 解析，类型错了会静默变默认值）', () {
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
    );
    final back = jsonDecode(jsonEncode(s)) as Map<String, dynamic>;
    expect(back['v'], kWidgetSnapshotVersion);
    expect(back['days'], hasLength(14));
    expect(back['boundaries'], isA<List>());
    final d0 = (back['days'] as List).first as Map<String, dynamic>;
    expect(d0['day'], isA<int>());
    expect(d0['hasShift'], isA<bool>());
    expect(d0['color'], isA<int>());
  });
}
```

在文件顶部补上 `import 'dart:convert';`（`jsonDecode` / `jsonEncode`）。

- [ ] **Step 3: 跑测试，确认它失败**

Run: `cd app && /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter test test/widget_snapshot_test.dart`

Expected: 编译失败 —— `Error: Couldn't resolve the package 'shiftassistantpro/features/widget/widget_snapshot.dart'`（文件还不存在）。

- [ ] **Step 4: 写实现**

创建 `app/lib/features/widget/widget_snapshot.dart`：

```dart
// 桌面小组件的快照生成 —— 纯函数，无 Flutter 渲染依赖、不读挂钟、不碰 Channel。
//
// 这个文件是整条链路的**唯一**智能所在：原生侧（Kotlin 的 WidgetRenderer）
// 只是个排版器，它不知道今天是几号、不会算班次、也不会做中英切换。所有判断都在
// 这里出结论，原样贴到桌面上。
//
// 为什么不把轮转规则抄一份到 Kotlin 让原生自己算：两份引擎就是两个 bug 源，
// 而 `shift_rotation.dart` 里 `dayOverrides` 那套语义（覆盖只在 `shiftOn` 这
// 一层生效、`teamShift` 不查覆盖）抄一遍必抄错。
//
// ⚠️ 一条容易腐坏的不变量：**相对文案按「偏移」索引，不按「日期」烘焙**。
// 快照生成于 9/18 时 days[1] 是「明天」；9/19 凌晨跨天刷新后 days[1] 变成了
// 今天 —— 若「明天」二字烘焙在 days[1] 的 `weekday` 里，卡片会理直气壮写错。
// 所以日期固有的东西（`dateShort` / `weekday` / `timeRange`）按日期烘焙，
// 相对的三个词（今天/明天/后天）放在顶层 `labels` 里，由原生按**渲染时的偏移**取。
library;

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../domain/shift_rotation.dart';

/// 快照格式版本。原生按它判断能不能解析 —— 对不上就按「无快照」走降级态。
const int kWidgetSnapshotVersion = 1;

/// 快照里带的天数。
///
/// 14 而不是 7，是因为跨天时小组件**不能**重算（它手上只有这份快照），只能拿
/// `LocalDate.now().toEpochDay()` 去 `days` 里对表、整体右移一格。给「App 两周
/// 没打开」留余量；真耗尽了原生退化成占位态。大卡只用到其中 7 天。
const int kWidgetSnapshotDays = 14;

/// 生成快照。纯函数：当前时刻由 [now] 传入，不读 `DateTime.now()`。
///
/// [themeMode] 是 `'system' | 'light' | 'dark'` —— **模式，不是解析结果**。
/// 把 `system` 提前解析成 light/dark 存进来，「跟随系统」就变成了「跟随生成快照
/// 那一刻的系统」，用户傍晚切深色模式要等到下次 App 启动才跟上。
Map<String, Object?> buildWidgetSnapshot({
  required ShiftSchedule? schedule,
  required DateTime now,
  required String themeMode,
  required int accent,
}) {
  final today = dateOnly(now);
  final nowMs = now.millisecondsSinceEpoch;
  final days = <Map<String, Object?>>[];
  final boundaries = <int>{};

  for (var i = 0; i < kWidgetSnapshotDays; i++) {
    // 本地日历日。`today` 是 UTC 的纯日期，只取它的年月日再重建成**本地**时刻，
    // 这样下面减出来的毫秒数才落在用户所在时区的正确钟点上。
    final date = DateTime(today.year, today.month, today.day + i);
    final dayStart = date;
    final shift = schedule?.shiftOn(date);

    // 本地零点也是边界：跨天要翻页。
    final nextMidnight = DateTime(date.year, date.month, date.day + 1);
    if (nextMidnight.millisecondsSinceEpoch > nowMs) {
      boundaries.add(nextMidnight.millisecondsSinceEpoch);
    }

    String? timeRange;
    if (shift != null && shift.startMinute != null && shift.endMinute != null) {
      final start = dayStart.add(Duration(minutes: shift.startMinute!));
      var end = dayStart.add(Duration(minutes: shift.endMinute!));
      // 结束时间有两种表示法，都要接住：
      //   · endMinute < startMinute —— 跨午夜（20:30 → 08:30，end=510）
      //   · endMinute ≥ 1440      —— 24 小时班 / 24:00（480 → 1920）
      // 前者加一天；后者本身就落在次日，加了反而过头。
      if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
      timeRange = L10n.timeRange(
        formatClock(shift.startMinute!),
        formatClock(shift.endMinute!),
        shift.endsNextDay,
      );
      if (start.millisecondsSinceEpoch > nowMs) {
        boundaries.add(start.millisecondsSinceEpoch);
      }
      if (end.millisecondsSinceEpoch > nowMs) {
        boundaries.add(end.millisecondsSinceEpoch);
      }
    }

    days.add({
      'day': dayNumber(date),
      'weekday': L10n.weekday(date.weekday - 1),
      'dateShort': L10n.monthDay(date),
      'hasShift': shift != null,
      'isRest': shift?.isRest ?? true,
      'shiftName': shift?.name ?? '',
      'shiftAbbr': shift?.shortLabel ?? '',
      'color': shift?.color ?? 0,
      // 胶囊上的字色：底色已定、白黑二选一，交给既有的 [AppTokens.onSolid]
      // （它的注释说明了为什么不能让 `inkFor` 代劳）。
      'abbrInk': shift == null
          ? 0
          : AppTokens.onSolid(Color(shift.color)).toARGB32(),
      'timeRange': timeRange,
    });
  }

  final sorted = boundaries.toList()..sort();

  return {
    'v': kWidgetSnapshotVersion,
    'genAtMs': nowMs,
    'lang': L10n.locale,
    'themeMode': themeMode,
    'accent': accent,
    'hasSchedule': schedule != null && !schedule.isBlank,
    'emptyHint': L10n.widgetEmptyHint,
    'labels': {
      'today': L10n.widgetToday,
      'tomorrow': L10n.widgetTomorrow,
      'dayAfter': L10n.widgetDayAfter,
    },
    'boundaries': sorted,
    'days': days,
  };
}
```

`package:flutter/material.dart` 是给 `AppTokens.onSolid` 与 `Color` 用的，import 区见上。

- [ ] **Step 5: 跑测试，确认通过**

Run: `cd app && /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter test test/widget_snapshot_test.dart`

Expected: `All tests passed!`（9 条）

若 「boundaries 升序、无重复」 那条失败，检查是否漏了 `toSet()` —— `{...}` 字面量本身就是 `Set<int>`，别在别处又改成 `List`。

- [ ] **Step 6: 跑静态检查**

Run: `cd app && /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze lib/features/widget test/widget_snapshot_test.dart`

Expected: `No issues found!`

- [ ] **Step 7: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/lib/features/widget/widget_snapshot.dart app/lib/core/l10n.dart app/test/widget_snapshot_test.dart
git commit -m "feat(widget): 快照生成纯函数 —— 原生侧从此只排版

相对文案按偏移索引而不是按日期烘焙，否则跨天之后 days[1] 会
自称「明天」。跨午夜班次的时间串走既有的 L10n.timeRange，不拼
前缀（那样英文会露出中文）。"
```

---

## Task 2: 原生骨架 —— Provider 注册 + 降级态上桌面

这一步**不接线**，只证明三件事：receiver 注册得对、`<shape>` 圆角卡片在 `RemoteViews` 里确实能渲染、R8 没把类裁掉。它是整个原生路线的最小可证伪单元。

**Files:**
- Create: `app/android/app/src/main/res/values/widget_colors.xml`
- Create: `app/android/app/src/main/res/drawable/widget_card_light.xml`
- Create: `app/android/app/src/main/res/drawable/widget_card_dark.xml`
- Create: `app/android/app/src/main/res/xml/shift_widget_info.xml`
- Create: `app/android/app/src/main/res/layout/widget_placeholder.xml`
- Create: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetStore.kt`
- Create: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetTier.kt`
- Create: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`
- Create: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/ShiftWidgetProvider.kt`
- Modify: `app/android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: `AlarmLog`（已有）
- Produces:
  - `WidgetTier.pick(widthDp: Int, heightDp: Int): WidgetTier`
  - `WidgetStore.snapshot(context: Context): WidgetStore.Snapshot?`
  - `WidgetRenderer.render(context: Context, snap: WidgetStore.Snapshot?, tier: WidgetTier): RemoteViews`
  - `ShiftWidgetProvider.refreshAll(context: Context)` / `ShiftWidgetProvider.ACTION_REFRESH`

- [ ] **Step 1: 色值资源**

创建 `app/android/app/src/main/res/values/widget_colors.xml`。每个值都注明来源，改令牌时这里要跟着走：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  小组件配色。逐项翻译自 app/lib/core/design_tokens.dart 与 core/theme/app_colors.dart。
  改令牌时这里要跟着改 —— 但**不**要求数值恰好相等：桌面小组件没有真实背景模糊，
  本来就走的是 `glassSurface(isDark, blurOn: false)` 那一档（「高级材质」关闭时的配方）。
-->
<resources>
    <!-- 卡片底：glassSurface(isDark, blurOn: false) 的渐变两端。 -->
    <!-- 亮：白 82% → 白 60%。 -->
    <color name="wg_card_from_light">#D1FFFFFF</color>
    <color name="wg_card_to_light">#99FFFFFF</color>
    <!-- 暗：白 16% → 白 8%。 -->
    <color name="wg_card_from_dark">#29FFFFFF</color>
    <color name="wg_card_to_dark">#14FFFFFF</color>

    <!-- 描边：走 navBorder 那条路（inkLight 14% / 白 16%），不走 glassBorder。 -->
    <!-- glassBorder 亮色是白 90%，它在 App 里成立是因为底下垫着 bgLight(#F5F6FA)； -->
    <!-- 在壁纸上那就是白底描白边，直接隐身。见 navBorder 的注释原话「白底上白描边会隐身」。 -->
    <color name="wg_border_light">#24111118</color>
    <color name="wg_border_dark">#29FFFFFF</color>

    <!-- 分隔线：inkMuted 12%。层级只靠明度（设计理念 §3），所以是浅一档的线，不是另一种颜色。 -->
    <color name="wg_divider_light">#1F6E6E82</color>
    <color name="wg_divider_dark">#1F9A9AB0</color>

    <!-- 正文 / 次要文字。 -->
    <color name="wg_ink_light">#111118</color>
    <color name="wg_ink_dark">#F2F2F7</color>
    <color name="wg_muted_light">#6E6E82</color>
    <color name="wg_muted_dark">#9A9AB0</color>

    <!-- 无班次那格的底色（空白天 / 占位胶囊）。 -->
    <color name="wg_empty_light">#14000000</color>
    <color name="wg_empty_dark">#1AFFFFFF</color>
</resources>
```

- [ ] **Step 2: 卡片底 drawable**

创建 `app/android/app/src/main/res/drawable/widget_card_light.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- 卡片底。angle=315 对应 Flutter 的 Alignment.topLeft→bottomRight —— -->
<!-- Android 的 <gradient android:angle> 是逆时针、0 = 左→右，所以右下方向是 -45 ≡ 315。 -->
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <corners android:radius="22dp" />
    <gradient
        android:angle="315"
        android:startColor="@color/wg_card_from_light"
        android:endColor="@color/wg_card_to_light" />
    <stroke
        android:width="1dp"
        android:color="@color/wg_border_light" />
</shape>
```

创建 `app/android/app/src/main/res/drawable/widget_card_dark.xml`：同上，把三个 `_light` 换成 `_dark`。

- [ ] **Step 3: 小组件元数据**

创建 `app/android/app/src/main/res/xml/shift_widget_info.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  updatePeriodMillis 设 0：不要系统轮询（它最快 30 分钟一次、还被限流，纯浪费电）。
  刷新全靠 WidgetRefreshScheduler 自排的边界闹钟。若真机上发现 MIUI 把自排闹钟
  吃掉，再改成 1800000 加一层兜底 —— 这是留给实测的开关，不预先加。

  默认给 4×2（中档），可横竖自由拉：拉小到 2×2 变「今天一张牌」，拉大到 4×4 变
  「一周一览」。三档的内容与阈值见 WidgetTier。
-->
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="110dp"
    android:minHeight="110dp"
    android:minResizeWidth="110dp"
    android:minResizeHeight="60dp"
    android:targetCellWidth="4"
    android:targetCellHeight="2"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"
    android:updatePeriodMillis="0"
    android:initialLayout="@layout/widget_placeholder"
    android:previewLayout="@layout/widget_placeholder" />
```

> `previewLayout` 暂时指向占位布局，Task 4 做出中卡后改指向 `@layout/widget_medium`。

- [ ] **Step 4: 占位布局**

创建 `app/android/app/src/main/res/layout/widget_placeholder.xml`。它身兼两职：`initialLayout`，以及「无快照 / 快照过期」时的降级态。

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  降级态：App 图标 + 应用名，**不含任何句子**。
  这是唯一允许出现文字的地方 —— 文字取自 `applicationInfo.loadLabel()`（系统按
  locale 给的），所以 Kotlin 里仍然一个中文字面量都没有。
  什么情况下会走到这里：装了 App 但没打开过（还没有快照）；或者 App 超过 14 天
  没打开（快照里对不上今天）。点它会打开 App，一打开就自愈。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_ph_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center"
    android:background="@drawable/widget_card_light"
    android:padding="12dp">

    <ImageView
        android:id="@+id/wg_ph_icon"
        android:layout_width="40dp"
        android:layout_height="40dp"
        android:contentDescription="@null"
        android:src="@mipmap/ic_launcher" />

    <TextView
        android:id="@+id/wg_ph_label"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="6dp"
        android:maxLines="1"
        android:ellipsize="end"
        android:textColor="@color/wg_muted_light"
        android:textSize="12sp" />
</LinearLayout>
```

- [ ] **Step 5: `WidgetStore`**

创建 `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetStore.kt`：

```kotlin
package com.daoban.shiftassistantpro

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate

/**
 * 桌面小组件快照的落盘与读取 —— [AlarmStore] 的同族。
 *
 * 存的是 Dart 侧算好的**一整份 JSON 串**（见 `lib/features/widget/widget_snapshot.dart`），
 * 原生只负责原样落盘、按需解析。为什么不让原生直接读 Drift 的 SQLite：那要耦合
 * 一份由 `build_runner` 生成的表结构，且要在 Kotlin 里重写一遍轮转引擎 —— 两份引擎
 * 就是两个 bug 源。
 *
 * 解析失败一律按「无快照」处理（渲染成占位态），不抛。一条坏数据不该让整张卡片消失。
 */
object WidgetStore {
    private const val PREFS = "shift_widget"
    private const val KEY = "snapshot"

    /** 一天。字段与 Dart 侧 `buildWidgetSnapshot` 的 `days[i]` 一一对应。 */
    data class Day(
        val day: Long,
        val weekday: String,
        val dateShort: String,
        val hasShift: Boolean,
        val isRest: Boolean,
        val shiftName: String,
        val shiftAbbr: String,
        val color: Int,
        val abbrInk: Int,
        /** 已是完整显示串（含「次日」/「(next day)」等语序）；无时间时为 null。 */
        val timeRange: String?,
    )

    /**
     * 一份完整的快照。
     *
     * [themeMode] 是 `"system" | "light" | "dark"` —— **模式，不是解析结果**。
     * `system` 由 [WidgetRenderer.isDark] 在渲染时读宿主配置现算，这样「跟随系统」
     * 永远是新鲜的。
     */
    data class Snapshot(
        val themeMode: String,
        val accent: Int,
        val hasSchedule: Boolean,
        val emptyHint: String,
        val today: String,
        val tomorrow: String,
        val dayAfter: String,
        val boundaries: List<Long>,
        val days: List<Day>,
    ) {
        /** 今天在 [days] 里的下标；快照过期（对不上）时返回 -1。 */
        fun indexOfToday(): Int {
            val t = LocalDate.now().toEpochDay()
            return days.indexOfFirst { it.day == t }
        }
    }

    @Synchronized
    fun write(context: Context, json: String) {
        try {
            prefs(context).edit().putString(KEY, json).apply()
        } catch (e: Exception) {
            AlarmLog.error(context, "WidgetStore.write 失败: ${e.message}")
        }
    }

    /** 读并解析；没有 / 版本对不上 / 解析失败都返回 null（调用方走降级态）。 */
    @Synchronized
    fun snapshot(context: Context): Snapshot? {
        val raw = try {
            prefs(context).getString(KEY, null)
        } catch (e: Exception) {
            AlarmLog.error(context, "WidgetStore.read 失败: ${e.message}")
            null
        } ?: return null

        return try {
            parse(raw)
        } catch (e: Exception) {
            AlarmLog.error(context, "WidgetStore 解析失败，按无快照处理: ${e.message}")
            null
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** 抽成 internal 便于将来单测；现在只有 [snapshot] 一个调用方。 */
    internal fun parse(raw: String): Snapshot? {
        val o = JSONObject(raw)
        // 版本对不上就当作看不懂 —— 比按老结构硬解出半份错数据强。
        if (o.optInt("v", -1) != 1) return null

        val labels = o.optJSONObject("labels") ?: JSONObject()
        val arr = o.optJSONArray("days") ?: JSONArray()
        val days = (0 until arr.length()).mapNotNull { i ->
            val d = arr.optJSONObject(i) ?: return@mapNotNull null
            Day(
                day = d.optLong("day", -1L),
                weekday = d.optString("weekday", ""),
                dateShort = d.optString("dateShort", ""),
                hasShift = d.optBoolean("hasShift", false),
                isRest = d.optBoolean("isRest", true),
                shiftName = d.optString("shiftName", ""),
                shiftAbbr = d.optString("shiftAbbr", ""),
                color = d.optInt("color", 0),
                abbrInk = d.optInt("abbrInk", 0),
                // ⚠️ 不能写 `d.optString("timeRange", "").ifEmpty { null }`：
                // `optString(name, fallback)` 只在**键不存在**时才给 fallback；
                // 键存在而值是 JSON `null` 时，它走 `JSON.toString(JSONObject.NULL)`
                // 返回**四字符串 `"null"`**，`.ifEmpty` 不会触发。而 Dart 侧每个
                // 休班日发的正是 JSON null —— 那样卡片上会印出字面的 `null`。
                timeRange = if (d.isNull("timeRange")) null else d.optString("timeRange"),
            )
        }
        if (days.isEmpty()) return null

        val bArr = o.optJSONArray("boundaries") ?: JSONArray()
        val boundaries = (0 until bArr.length()).map { bArr.optLong(it, 0L) }
            .filter { it > 0L }

        return Snapshot(
            themeMode = o.optString("themeMode", "system"),
            accent = o.optInt("accent", 0),
            hasSchedule = o.optBoolean("hasSchedule", false),
            emptyHint = o.optString("emptyHint", ""),
            today = labels.optString("today", ""),
            tomorrow = labels.optString("tomorrow", ""),
            dayAfter = labels.optString("dayAfter", ""),
            boundaries = boundaries,
            days = days,
        )
    }
}
```

- [ ] **Step 6: `WidgetTier`**

创建 `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetTier.kt`：

```kotlin
package com.daoban.shiftassistantpro

/**
 * 三档尺寸。
 *
 * 阈值按本机（400dp 宽、MIUI 4 列网格）估算：2×2 ≈ 180×180dp、4×2 ≈ 380×180dp、
 * 4×4 ≈ 380×380dp。**上线前必须真机标定一次** —— ShiftWidgetProvider 会把每次
 * 刷新时实测的 dp 打进 `AlarmLog.info`，`adb logcat -s ShiftAssistant` 读回来
 * 对着三档各拉一次，再回来定死这里。
 *
 * ⚠️ 高度闸门不是保险，是必需的：4×1 那种尺寸宽度轻松过 300，但只有 ~86dp 高，
 * 三行装不下会**静默裁掉最后一行** —— 这正是 `info_card_metrics.dart` 那条注释
 * 里踩过的坑。所以两档都是「宽**且**高」。
 */
enum class WidgetTier {
    /** 今天一张牌。 */
    SMALL,

    /** 未来三天。 */
    MEDIUM,

    /** 一周一览（4×4 网格）。 */
    LARGE;

    companion object {
        const val MEDIUM_MIN_WIDTH_DP = 220
        const val MEDIUM_MIN_HEIGHT_DP = 130
        const val LARGE_MIN_WIDTH_DP = 300
        const val LARGE_MIN_HEIGHT_DP = 260

        fun pick(widthDp: Int, heightDp: Int): WidgetTier = when {
            widthDp >= LARGE_MIN_WIDTH_DP && heightDp >= LARGE_MIN_HEIGHT_DP -> LARGE
            widthDp >= MEDIUM_MIN_WIDTH_DP && heightDp >= MEDIUM_MIN_HEIGHT_DP -> MEDIUM
            else -> SMALL
        }
    }
}
```

- [ ] **Step 7: `WidgetRenderer`（本任务只做占位分支）**

创建 `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`：

```kotlin
package com.daoban.shiftassistantpro

import android.content.Context
import android.content.res.Configuration
import android.widget.RemoteViews

/**
 * 排版。**纯渲染**：不写盘、不排闹钟、不读除宿主配置之外的任何系统状态。
 *
 * 与 ShiftWidgetProvider 分开是为了能单独读懂它 —— 这个类里没有一行涉及
 * 「什么时候刷新」「刷新排在哪」，只有「给我一份快照，我给你一棵 RemoteViews 树」。
 *
 * 三条纪律：
 *  1. Kotlin 侧一个中文字面量都不许有。所有文案都来自快照（Dart 侧 `L10n` 产出）。
 *     唯一的例外是占位态那行应用名，它取自 `applicationInfo.loadLabel()`。
 *  2. 明暗一律**显式选资源**，不依赖 `-night` 限定符 —— `RemoteViews` 由宿主进程
 *     inflate，限定符在宿主进程里的解析顺序各家 ROM 不一致。
 *  3. 布局只用 RemoteViews 白名单里的类：FrameLayout / LinearLayout / RelativeLayout /
 *     GridLayout + TextView / ImageView。**没有 ConstraintLayout**，报的是运行期
 *     `ClassNotFoundException`，不是编译错误。
 */
object WidgetRenderer {

    /** 主题模式 → 此刻该用暗色吗。`system` 读宿主当前的配置，所以永远是新鲜的。 */
    fun isDark(context: Context, themeMode: String): Boolean = when (themeMode) {
        "light" -> false
        "dark" -> true
        else -> (context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    }

    /**
     * [snap] 为 null（没有快照 / 解析失败 / 版本对不上）或快照已过期时，返回占位态。
     */
    fun render(
        context: Context,
        snap: WidgetStore.Snapshot?,
        tier: WidgetTier,
    ): RemoteViews {
        if (snap == null) return placeholder(context, dark = systemDark(context))
        val todayIndex = snap.indexOfToday()
        if (todayIndex < 0) {
            // 快照过期：App 超过 14 天没打开，这份 days 里已经没有今天了。
            AlarmLog.info(context, "WidgetRenderer: 快照已过期，走占位态")
            return placeholder(context, isDark(context, snap.themeMode))
        }
        TODO("Task 3 起，这里按 tier 分派到小/中/大三档")
    }

    private fun systemDark(context: Context): Boolean =
        (context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

    private fun placeholder(context: Context, dark: Boolean): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_placeholder)
        v.setInt(
            R.id.wg_ph_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.setImageViewResource(R.id.wg_ph_icon, R.mipmap.ic_launcher)
        v.setTextViewText(
            R.id.wg_ph_label,
            context.applicationInfo.loadLabel(context.packageManager).toString(),
        )
        v.setTextColor(
            R.id.wg_ph_label,
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light),
        )
        return v
    }
}
```

> `TODO(...)` 是 Kotlin 的 `Nothing` 表达式，能让这一步编译通过、且真走到就抛异常 —— 本任务里永远走不到（还没有快照能落盘）。

- [ ] **Step 8: `ShiftWidgetProvider`（本任务只做刷新与分档）**

创建 `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/ShiftWidgetProvider.kt`：

```kotlin
package com.daoban.shiftassistantpro

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/**
 * 桌面小组件的入口。
 *
 * 它只做四件事：读快照 → 按每个实例自己的尺寸分档 → 交给 [WidgetRenderer] 排版
 * → 把下一次刷新排进 AlarmManager。所有业务判断都不在这里（见 widget_snapshot.dart）。
 *
 * 刷新触发点（对应 spec §6.1）：
 *   · App 内数据变化 —— Dart 侧 `WidgetService.push()` 走 MethodChannel 进来
 *   · 跨天 00:00 与今天班次的开始/结束 —— [WidgetRefreshScheduler] 排的精确闹钟
 *   · 开机 / 装更新 —— BootReceiver 里补一次
 *   · 刚添加到桌面 / 改尺寸 —— 系统的 onUpdate / onAppWidgetOptionsChanged
 */
class ShiftWidgetProvider : AppWidgetProvider() {

    companion object {
        /** 自定义刷新 action。注意它**只由本 App 自己发** —— receiver 是 not exported。 */
        const val ACTION_REFRESH = "com.daoban.shiftassistantpro.WIDGET_REFRESH"

        /** 渲染全部实例。Dart 侧 push 完快照后调它。 */
        fun refreshAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, ShiftWidgetProvider::class.java)
            )
            AlarmLog.info(context, "ShiftWidgetProvider.refreshAll: ${ids.size} 个实例")
            renderAll(context, mgr, ids)
        }

        private fun renderAll(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            if (ids.isEmpty()) return
            val snap = WidgetStore.snapshot(context)
            for (id in ids) {
                val opts = mgr.getAppWidgetOptions(id)
                val w = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                val h = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
                val tier = WidgetTier.pick(w, h)
                // 真机标定用：对着三档各拉一次，adb logcat -s ShiftAssistant 读回来。
                AlarmLog.info(context, "ShiftWidgetProvider: id=$id, ${w}x${h}dp → $tier")
                try {
                    mgr.updateAppWidget(id, WidgetRenderer.render(context, snap, tier))
                } catch (e: Exception) {
                    AlarmLog.error(context, "ShiftWidgetProvider: 渲染 id=$id 失败: ${e.message}")
                }
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        renderAll(context, appWidgetManager, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        renderAll(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REFRESH) {
            refreshAll(context)
            return // 自定义 action 不走 super（super 只认系统那几个 action）
        }
        super.onReceive(context, intent)
    }
}
```

> **`WidgetRefreshScheduler` 不在本任务里建** —— Task 6 才需要它。本任务靠「重新添加小组件」触发 `onUpdate` 验证。

- [ ] **Step 9: 注册到 manifest**

在 `app/android/app/src/main/AndroidManifest.xml` 的 `<application>` 里，紧跟在现有 `<receiver android:name=".TodoReminderReceiver" .../>` 之后插入：

```xml
        <!-- 桌面小组件。label 沿用 <application> 那份写死的文案（本项目没有
             res/values/strings.xml，全仓只有这一处 App 名称来源，不新开一张表）。
             必须在这里显式声明：release 构建 isMinifyEnabled = true，只靠代码
             引用的类会被 R8 裁掉。 -->
        <receiver
            android:name=".ShiftWidgetProvider"
            android:exported="false"
            android:label="倒班助手Pro">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/shift_widget_info" />
        </receiver>
```

- [ ] **Step 10: 构建并安装 release APK**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
```

Expected: `Built build/app/outputs/flutter-apk/app-release.apk (21.9MB)`（约 70 秒），`Success`。

若报 `ClassNotFoundException` 或 `aapt` 找不到 `@xml/shift_widget_info`，说明上一步的 meta-data 名字或文件名拼错了。

- [ ] **Step 11: 真机验证 —— 桌面上出现占位卡**

在手机上**长按桌面空白处 → 添加小部件 → 找到「倒班助手Pro」→ 拖到桌面**。然后截图：

```bash
"$ADB" exec-out screencap -p > /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/work/wg_t2.png
```

Expected: 桌面上出现一张**圆角**卡片，里面有 App 图标与「倒班助手Pro」，圆角与 1px 描边看得见。

再确认注册状态：

```bash
"$ADB" shell dumpsys appwidget | grep -B2 -A8 shiftassistantpro
```

Expected: 能看到 `com.daoban.shiftassistantpro/.ShiftWidgetProvider` 与一条 widget id。

同时读一次实测尺寸（**这是 Task 4 定阈值要用的数据，记下来**）：

```bash
"$ADB" logcat -d -s ShiftAssistant | grep "ShiftWidgetProvider:"
```

Expected: 形如 `ShiftWidgetProvider: id=… , 380x180dp → MEDIUM`。

**这一步是整个原生路线最关键的验证点**：如果卡片没有圆角、或里面一片空白、或根本不出现在小部件列表里，就停在这里排查，不要往下走。排查方向依次是：`<meta-data>` 的 resource 名、`res/xml` 文件名、`android:exported`。

- [ ] **Step 12: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/android/app/src/main/res/values/widget_colors.xml \
        app/android/app/src/main/res/drawable/widget_card_light.xml \
        app/android/app/src/main/res/drawable/widget_card_dark.xml \
        app/android/app/src/main/res/xml/shift_widget_info.xml \
        app/android/app/src/main/res/layout/widget_placeholder.xml \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetStore.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetTier.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/ShiftWidgetProvider.kt \
        app/android/app/src/main/AndroidManifest.xml
git commit -m "feat(widget): 原生骨架 —— Provider 注册、快照存储、尺寸分档

只到占位态为止，证明三件事：receiver 注册得对、<shape> 圆角卡片在
RemoteViews 里确实能渲染、R8 没把类裁掉。桌面上出现的是一张三档通用
的降级卡（图标 + 应用名，不含任何句子，所以 Kotlin 里仍然没有中文）。"
```

---

## Task 3: 接线 —— 通道打通，小卡显示今天的班次

Task 2 是一棵没人浇水的树。这一步把 Dart 的快照送到它手上。

**Files:**
- Create: `app/lib/features/widget/widget_service.dart`
- Create: `app/android/app/src/main/res/layout/widget_small.xml`
- Modify: `app/android/app/src/main/kotlin/.../MainActivity.kt`
- Modify: `app/android/app/src/main/kotlin/.../WidgetRenderer.kt`（补 SMALL 分支）
- Modify: `app/lib/features/home/home_shell.dart`

**Interfaces:**
- Consumes: `buildWidgetSnapshot`（Task 1）· `WidgetStore` / `WidgetRenderer` / `WidgetTier`（Task 2）· `_settingsChannel` 那条协议（`com.daoban.shiftassistantpro/settings`）
- Produces:
  - `WidgetService.push({required ShiftSchedule? schedule, required AppSettings settings})`
  - `WidgetService.dateFromEpochDay(int epochDay) → DateTime`
  - `WidgetService.widgetLaunchRequested` (`ValueNotifier<DateTime?>`)
  - `WidgetService.consumeLaunchDay()`
  - 原生 channel 方法 `widgetPushSnapshot` / `getWidgetLaunchDay`

- [ ] **Step 1: 写失败的测试（`epochDay` 换算）**

追加到 `app/test/widget_snapshot_test.dart` 末尾（`main()` 内部，最后一个 `test(...)` 之后）：

```dart
  test('epochDay ↔ DateTime 换算：与 dayNumber 互为逆运算', () {
    for (final d in [
      DateTime(2026, 9, 18),
      DateTime(2026, 1, 1),
      DateTime(2026, 12, 31),
      DateTime(2027, 2, 28),
    ]) {
      expect(dayNumber(WidgetService.dateFromEpochDay(dayNumber(d))), dayNumber(d));
    }
  });
```

在文件顶部加 `import 'package:shiftassistantpro/features/widget/widget_service.dart';`。

**同一步再加一条**（Task 1 的评审指出：本设计的核心不变量 B「相对文案按偏移索引、不按日期烘焙」原本零测试覆盖，而 `labels` 正是本任务 `relativeLabel` 要消费的接口）：

```dart
  test('labels 按偏移提供相对文案 —— 不变量 B 的契约', () {
    final s = buildWidgetSnapshot(
      schedule: _schedule(),
      now: DateTime(2026, 9, 18, 10),
      themeMode: 'system',
      accent: 0xFF4F5BE8,
    );
    final labels = s['labels']! as Map;
    expect(labels['today'], L10n.widgetToday);
    expect(labels['tomorrow'], L10n.widgetTomorrow);
    expect(labels['dayAfter'], L10n.widgetDayAfter);
    // 关键：这**三个**词都不在 days[] 里 —— 若有人把它们烘进 days[i]，
    // 跨天之后 days[i] 会自称「明天」。三个都要循环断言：只钉「明天」的话，
    // 「今天」或「后天」被烘进去时这条测试不会红。
    for (final word in [
      L10n.widgetToday,
      L10n.widgetTomorrow,
      L10n.widgetDayAfter,
    ]) {
      for (final d in s['days']! as List) {
        expect((d as Map).values, isNot(contains(word)));
      }
    }
  });
```

所以本任务结束时 `widget_snapshot_test.dart` 是 **11 条**（原 9 + epochDay + labels）。

- [ ] **Step 2: 跑测试，确认它失败**

Run: `cd app && /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter test test/widget_snapshot_test.dart`

Expected: 编译失败，`Couldn't resolve the package 'shiftassistantpro/features/widget/widget_service.dart'`。

- [ ] **Step 3: 写 `WidgetService`**

创建 `app/lib/features/widget/widget_service.dart`：

```dart
// 桌面小组件的投递与启动意图。
//
// 与 `alarm_service.dart` 的关系：同一个 MethodChannel（`.../settings`），但各管
// 各的方法。**不能**在这里再 `setMethodCallHandler` —— 一个 MethodChannel 只有
// 一个 handler，`AlarmService.init()` 已经占了；原生推过来的 `onWidgetDayTapped`
// 由那边分派过来（见 `AlarmService.init`）。
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/shift_rotation.dart';
import '../../state/app_settings.dart';
import 'widget_snapshot.dart';

/// 与 `AlarmService._settingsChannel` 同一个名字 —— MethodChannel 按名字寻址，
/// Dart 侧多个实例会落到原生同一个 handler 上。各自持有常量比互相 import 私有
/// 字段干净。
const MethodChannel _channel =
    MethodChannel('com.daoban.shiftassistantpro/settings');

class WidgetService {
  WidgetService._();

  /// 原生推过来的「点了小组件的某一天」。`CalendarScreen` 与 `HomeShell` 都监听它。
  ///
  /// 与 `AlarmService.openTodoRequested` 同款：值非 null 表示有一次待处理的请求，
  /// 消费方处理完负责置回 null（置回会再触发一次监听，靠「值为 null 就返回」兜住）。
  static final ValueNotifier<DateTime?> widgetLaunchRequested =
      ValueNotifier<DateTime?>(null);

  /// 把当前状态算成快照推给原生。
  ///
  /// 原生收到后会：落盘 → `updateAppWidget` 全部实例 → 重排下一次刷新闹钟。
  /// 所以「改完排班桌面立刻变」这件事，靠的就是这里被调到。
  static Future<void> push({
    required ShiftSchedule? schedule,
    required AppSettings settings,
  }) async {
    try {
      final json = jsonEncode(buildWidgetSnapshot(
        schedule: schedule,
        now: DateTime.now(),
        themeMode: settings.themeMode.name,
        accent: settings.accentColor.toARGB32(),
      ));
      await _channel.invokeMethod<bool>('widgetPushSnapshot', {'json': json});
    } catch (e) {
      // 小组件是锦上添花：没有它 App 一切照常，推失败不打扰用户、也不中断调用方
      // （它多半跑在 build 之后的后帧回调里）。
      //
      // 但**要留痕**：「桌面怎么没变」这类问题只能靠日志排查，而这一层恰好是唯一
      // 知道 push 发生过的地方 —— 静默吞掉等于把唯一线索也扔了。
      // 直接走 channel 而不 import `alarm_service.dart`：那两个文件互相 import 会
      // 成环，而 `logInfo` 本来就是同一条 channel 上的一个方法名。
      try {
        await _channel.invokeMethod('logInfo', {'msg': 'widgetPushSnapshot 失败: $e'});
      } catch (_) {
        // 连日志都发不出去（引擎已经没了）—— 到这一步没什么可做的了。
      }
    }
  }

  /// 冷启动由小组件拉起时，读一次原生存下的「要跳到哪天」。
  ///
  /// 热启动**不走这里** —— 那时 Dart 已经在跑，原生直接推 `onWidgetDayTapped`。
  /// 这个分界是既有代码注释里写明的（见 `MainActivity.handleAlarmIntent`）。
  static Future<void> consumeLaunchDay() async {
    try {
      final day = await _channel.invokeMethod<int>('getWidgetLaunchDay');
      if (day == null) return;
      widgetLaunchRequested.value = dateFromEpochDay(day);
    } catch (_) {}
  }

  /// `LocalDate.toEpochDay()` → 本地日历日的 `DateTime`。
  ///
  /// 返回的是 **UTC 的纯日期**（`dateOnly()` 同一口径）—— `isSameDay` / `dayNumber`
  /// 都按 UTC 日期整数比较，与日历页的 `_selected` 混用不会出错；反过来若返回本地
  /// 午夜的 `DateTime`，在 UTC+8 下会比出「前一天」。
  static DateTime dateFromEpochDay(int epochDay) =>
      DateTime.fromMillisecondsSinceEpoch(
        epochDay * Duration.millisecondsPerDay,
        isUtc: true,
      );

  /// 原生推来的一天（热启动路径）。由 `AlarmService.init` 的 channel handler 转发。
  static void onNativeDayTapped(int epochDay) {
    widgetLaunchRequested.value = dateFromEpochDay(epochDay);
  }
}
```

顶部 import 区需要 `dart:convert`（`jsonEncode`）：把 `import 'dart:convert';` 加在 `import 'package:flutter/foundation.dart';` 之前。

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd app && /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter test test/widget_snapshot_test.dart`

Expected: `All tests passed!`（10 条）

- [ ] **Step 5: 原生侧加 channel 方法**

在 `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/MainActivity.kt` 里。

**(a)** 在 companion object 里，紧跟 `pendingTodoId` 那段之后加：

```kotlin
        /**
         * 冷启动由小组件拉起时待处理的「要跳到哪天」（`LocalDate.toEpochDay()`）。
         * -1 = 没有。热启动不走这里，直接推 `onWidgetDayTapped` 给已经在跑的 Dart
         * —— 与上面 `pendingTodoId` 完全同一套分界，理由见 `handleAlarmIntent`。
         */
        var pendingWidgetDay: Int = -1
```

**(b)** 在 `override fun onCreate` 里 `handleAlarmIntent(intent)` 那行之后加一行 `handleWidgetIntent(intent)`；在 `override fun onNewIntent` 里同样。

**(c)** 新增私有方法（放在 `handleAlarmIntent` 之后）：

```kotlin
    private fun handleWidgetIntent(intent: Intent?) {
        // 小组件某一天那一格带过来的日期。单元是「自 epoch 的天数」，与 Dart 的
        // `dayNumber()` 同口径 —— 不传毫秒，省得两边为时区各算一遍。
        val day = intent?.getIntExtra("widget_day", -1) ?: -1
        if (day < 0) return
        AlarmLog.info(this, "MainActivity: 小组件点击 day=$day")
        if (flutterChannel == null) {
            pendingWidgetDay = day
        } else {
            flutterChannel?.invokeMethod("onWidgetDayTapped", day)
        }
    }
```

**(d)** 在 `configureFlutterEngine` 的 `when (call.method)` 里，紧跟 `"getPendingTodoId" -> { ... }` 那个分支之后插入两个分支：

```kotlin
                    "widgetPushSnapshot" -> {
                        val json = call.argument<String>("json") ?: ""
                        if (json.isEmpty()) {
                            result.error("BAD_ARGS", "json 缺失", null)
                        } else {
                            WidgetStore.write(this, json)
                            ShiftWidgetProvider.refreshAll(this)
                            result.success(true)
                        }
                    }
                    "getWidgetLaunchDay" -> {
                        val d = pendingWidgetDay
                        pendingWidgetDay = -1
                        result.success(if (d >= 0) d else null)
                    }
```

> 刷新走主线程没问题：`refreshAll` 对一两个实例做的是读一段 prefs + 建一棵小视图树，量级与 `AlarmStore.all` 相当。
>
> **Task 6 会在这两个分支里各补一行排刷新闹钟**，现在还没有 `WidgetRefreshScheduler`。

**(e)** 在 `AlarmService.init()` 的 channel handler 里加第三个分支。文件 `app/lib/features/alarm/alarm_service.dart`，找到 `if (call.method == 'onTodoTapped')` 那段，在其后追加：

```dart
      // 小组件某一天被点击（热启动路径）。
      if (call.method == 'onWidgetDayTapped') {
        WidgetService.onNativeDayTapped(call.arguments as int);
      }
```

并在文件顶部加 `import '../widget/widget_service.dart';`。

- [ ] **Step 6: 小卡布局**

创建 `app/android/app/src/main/res/layout/widget_small.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  小档：今天一张牌。尺寸约 2×2（180×180dp）。
  结构从上到下：日期行 → 班次区（色条 + 班次名 + 时间）→ 分隔线 → 明天预告行。
  色条是 ImageView 而不是 View —— Task 5 要给它换上一张带圆角的位图
  （setImageViewBitmap 只认 ImageView）。现在先用 setBackgroundColor 铺实色。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_s_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:background="@drawable/widget_card_light"
    android:padding="14dp">

    <!-- 日期行：左「今天 · 周四」，右「9月18日」 -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal">

        <TextView
            android:id="@+id/wg_s_relative"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textSize="12sp"
            android:textStyle="bold"
            android:maxLines="1" />

        <TextView
            android:id="@+id/wg_s_weekday"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:layout_marginStart="6dp"
            android:textSize="12sp"
            android:maxLines="1" />

        <TextView
            android:id="@+id/wg_s_date"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textSize="12sp"
            android:maxLines="1" />
    </LinearLayout>

    <!-- 班次区：色条 + 班次名 + 时间。占满纵向剩余空间，底对齐看着更稳。 -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:layout_marginTop="8dp"
        android:orientation="horizontal"
        android:gravity="center_vertical">

        <ImageView
            android:id="@+id/wg_s_bar"
            android:layout_width="6dp"
            android:layout_height="match_parent"
            android:contentDescription="@null" />

        <LinearLayout
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:layout_marginStart="10dp"
            android:orientation="vertical">

            <TextView
                android:id="@+id/wg_s_shift"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:textSize="24sp"
                android:textStyle="bold"
                android:maxLines="1"
                android:ellipsize="end" />

            <TextView
                android:id="@+id/wg_s_time"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="2dp"
                android:textSize="14sp"
                android:maxLines="1"
                android:ellipsize="end" />
        </LinearLayout>
    </LinearLayout>

    <!-- 分隔线用 ImageView 而不是 <View>：白名单是靠 `@RemoteView` 注解
         过滤的，而 `android.view.View` **没有**这个注解（`Space` 也没有）——
         实测本仓 android-36 的 android.jar：View/ViewGroup/Space 均为 0，
         TextView/ImageView/LinearLayout/FrameLayout/GridLayout 均为 7。
         用 <View> 的后果是宿主在 apply() 阶段抛
         `InflateException: Class not allowed to be inflated android.view.View`，
         **整张卡片渲染不出来**（不是只丢这条线）。Task 3 实做后由评审用
         javap 实测发现。 -->
    <ImageView
        android:id="@+id/wg_s_divider"
        android:layout_width="match_parent"
        android:layout_height="1dp"
        android:layout_marginTop="8dp"
        android:contentDescription="@null" />

    <TextView
        android:id="@+id/wg_s_next"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="8dp"
        android:textSize="12sp"
        android:maxLines="1"
        android:ellipsize="end" />
</LinearLayout>
```

- [ ] **Step 7: `WidgetRenderer` 补 SMALL 分支**

把 `WidgetRenderer.kt` 里的 `TODO(...)` 那行换成：

```kotlin
        // 空表（没建过排班 / 选了「跟随法定节假日」那种空白表方案）：整张卡只留
        // 一句来自快照的提示。这一支必须在分档**之前** —— 三档尺寸在空表下长得
        // 一致，不必各写一套。
        if (!snap.hasSchedule) return empty(context, snap)

        return when (tier) {
            WidgetTier.SMALL -> small(context, snap, todayIndex)
            WidgetTier.MEDIUM -> small(context, snap, todayIndex) // Task 4 换成 medium(...)
            WidgetTier.LARGE -> small(context, snap, todayIndex)  // Task 4 换成 large(...)
        }
```

并在 `object WidgetRenderer` 里加 `empty`（放在 `placeholder` 之前）：

```kotlin
    /**
     * 空表态：没有排班（`snap.hasSchedule == false`）。
     *
     * 为什么不复用 `small()` 加几个 if：那条路要隐藏六七个视图，且班上「今天周四 /
     * 周四 / 后天 周五」那种看着像正常班次卡的东西会让用户以为排班已经生效了。
     * 这里清空重设，语义上就是「还没排班」这一件事。
     *
     * 文案来自快照的 `emptyHint`（Dart 侧 `L10n.widgetEmptyHint` 产出）——
     * Kotlin 侧仍然一个字面量都没有。
     */
    private fun empty(context: Context, snap: WidgetStore.Snapshot): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_small)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_s_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        v.setTextViewText(R.id.wg_s_relative, snap.emptyHint)
        v.setTextColor(R.id.wg_s_relative, ink)
        for (id in intArrayOf(
            R.id.wg_s_weekday, R.id.wg_s_date, R.id.wg_s_bar,
            R.id.wg_s_shift, R.id.wg_s_time, R.id.wg_s_divider, R.id.wg_s_next,
        )) {
            v.setViewVisibility(id, android.view.View.GONE)
        }
        return v
    }
```

> 中/大档暂时复用小卡：这样 Task 3 结束时**所有尺寸都显示得出来**，Task 4 只是把内容换得更丰富，不引入「某档还是空白」的中间态。

然后在 `object WidgetRenderer` 里加（放在 `placeholder` 之前）：

```kotlin
    /** 档位偏移 → 该显示哪个相对称法。≥3 直接用那天的周几（它不会腐坏）。 */
    private fun relativeLabel(snap: WidgetStore.Snapshot, index: Int, todayIndex: Int): String =
        when (index - todayIndex) {
            0 -> snap.today
            1 -> snap.tomorrow
            2 -> snap.dayAfter
            else -> snap.days[index].weekday
        }

    private fun small(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_small)
        val dark = isDark(context, snap.themeMode)
        val today = snap.days[todayIndex]

        v.setInt(
            R.id.wg_s_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted =
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)
        val divider =
            context.getColor(if (dark) R.color.wg_divider_dark else R.color.wg_divider_light)

        v.setTextViewText(R.id.wg_s_relative, relativeLabel(snap, todayIndex, todayIndex))
        v.setTextColor(R.id.wg_s_relative, ink)
        v.setTextViewText(R.id.wg_s_weekday, today.weekday)
        v.setTextColor(R.id.wg_s_weekday, muted)
        v.setTextViewText(R.id.wg_s_date, today.dateShort)
        v.setTextColor(R.id.wg_s_date, muted)

        // 没有班次（空表 / 休班）时，班次名那行显示周几兜底 —— 快照里 shiftName 是
        // 空串，直接设空会让整行塌掉、时间行往上跳。
        v.setTextViewText(
            R.id.wg_s_shift,
            if (today.hasShift) today.shiftName else today.weekday,
        )
        v.setTextColor(R.id.wg_s_shift, ink)

        if (today.timeRange == null) {
            v.setViewVisibility(R.id.wg_s_time, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_s_time, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_s_time, today.timeRange)
            v.setTextColor(R.id.wg_s_time, muted)
        }

        // 色条：Task 5 会换成带圆角的位图。现在是实色 —— `setBackgroundColor`
        // 对任何 View 都有效，且不需要位图。
        v.setInt(
            R.id.wg_s_bar,
            "setBackgroundColor",
            if (today.hasShift) today.color else context.getColor(
                if (dark) R.color.wg_empty_dark else R.color.wg_empty_light
            ),
        )

        v.setInt(R.id.wg_s_divider, "setBackgroundColor", divider)

        // 明天预告。今天已是窗口最后一天时（不可能 —— 窗口 14 天）留空。
        val nextIndex = todayIndex + 1
        if (nextIndex < snap.days.size) {
            val n = snap.days[nextIndex]
            val label = relativeLabel(snap, nextIndex, todayIndex)
            val tail = if (n.hasShift) {
                if (n.timeRange == null) n.shiftName else "${n.shiftName} ${n.timeRange}"
            } else {
                n.weekday
            }
            v.setTextViewText(R.id.wg_s_next, "$label  $tail")
            v.setViewVisibility(R.id.wg_s_next, android.view.View.VISIBLE)
        } else {
            v.setViewVisibility(R.id.wg_s_next, android.view.View.GONE)
        }
        v.setTextColor(R.id.wg_s_next, muted)

        return v
    }
```

- [ ] **Step 8: `HomeShell` 接线**

在 `app/lib/features/home/home_shell.dart`。

**(a)** 顶部加 import：

```dart
import '../../data/app_repository.dart';
import '../widget/widget_service.dart';
```

**(b)** 在 `initState` 的 `addPostFrameCallback` 里，`_maybeAutoCheckUpdate();` 之后加一行：

```dart
      // 冷启动由桌面小组件拉起：读一次「要跳到哪天」。
      WidgetService.consumeLaunchDay();
      // 首帧推一次快照，桌面上的卡片立刻与 App 对齐。
      _pushWidgetSnapshot();
```

**(c)** 在 `AlarmService.openTodoRequested.addListener(_onTodoRequested);` 之后加两行订阅：

```dart
    // 排班数据与外观设置任一变化就重推快照 —— 这是「改完排班桌面立刻变」的那条路。
    ref.listenManual(activeScheduleProvider, (_, __) => _pushWidgetSnapshot());
    ref.listenManual(appSettingsProvider, (_, __) => _pushWidgetSnapshot());
```

**(d)** 在 `dispose()` 里加上：

```dart
    WidgetService.widgetLaunchRequested.removeListener(_onWidgetDayRequested);
```

**(e)** 在 `initState` 里订阅那个 notifier（与 `addPostFrameCallback` 同级）：

```dart
    WidgetService.widgetLaunchRequested.addListener(_onWidgetDayRequested);
```

**(f)** 新增两个方法（放在 `_openTodoPage` 之后）：

```dart
  /// 用户在桌面小组件上点了某一天：切到日历页，再让 CalendarScreen 跳到那天。
  ///
  /// **不在这里把 notifier 置回 null** —— CalendarScreen 还要读它。由那边收尾。
  void _onWidgetDayRequested() {
    if (WidgetService.widgetLaunchRequested.value == null) return;
    if (!mounted || !_controller.hasClients) return;
    _controller.jumpToPage(0); // 0 = 日历，与 _items/_screens 的顺序绑定
  }

  /// 把当前排班与外观算成快照推给原生。
  ///
  /// `hasValue` 那道闸门是必需的：`activeScheduleProvider` 是 StreamProvider，
  /// 首帧还没读到库时 `.value` 是 null，此时推会把「有一定有排班」误报成
  /// 「没有排班」，桌面上闪一下空表提示。等它真下发（哪怕下发的就是 null）再推。
  Future<void> _pushWidgetSnapshot() async {
    final async = ref.read(activeScheduleProvider);
    if (!async.hasValue) return;
    await WidgetService.push(
      schedule: async.value?.toDomain(),
      settings: ref.read(appSettingsProvider),
    );
  }
```

- [ ] **Step 9: 构建安装，真机验证「今天」**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze lib/features/widget lib/features/home lib/features/alarm
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
"$ADB" shell am force-stop com.daoban.shiftassistantpro; "$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity
sleep 4
"$ADB" exec-out screencap -p > /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/work/wg_t3.png
```

Expected（看截图）：
- 卡片上第一行是「**今天** · 周X」+ 右侧日期
- 中间是 **6dp 班次色条** + 班次名（大字）+ 时间串
- 底下一行是「**明天**  班次名 时间」
- 若这台机上还没建过排班，卡片应显示「还没有排班，点一下去设置」

验证「改排班桌面立刻变」：在 App 里改一个班次的名字 → 回桌面看卡片是否跟着变（`am start` 之后 Dart 会 push）。

- [ ] **Step 10: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/lib/features/widget/widget_service.dart \
        app/lib/features/home/home_shell.dart \
        app/lib/features/alarm/alarm_service.dart \
        app/test/widget_snapshot_test.dart \
        app/android/app/src/main/res/layout/widget_small.xml \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/MainActivity.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt
git commit -m "feat(widget): 通道接线，桌面显示今天与明天

Dart 侧 push 快照、原生落盘并渲染小卡。中/大档暂时复用小卡 —— 这样
三档都显示得出来，Task 4 只是把内容换丰富，不引入空白中间态。"
```

---

## Task 4: 三档布局与分档

**Files:**
- Create: `app/android/app/src/main/res/layout/widget_medium.xml`
- Create: `app/android/app/src/main/res/layout/widget_large.xml`
- Modify: `app/android/app/src/main/kotlin/.../WidgetRenderer.kt`
- Modify: `app/android/app/src/main/res/xml/shift_widget_info.xml`（`previewLayout` 指向中卡）
- Modify: `app/android/app/src/main/kotlin/.../WidgetTier.kt`（按标定结果改阈值，如果需要）

**Interfaces:**
- Consumes: Task 2/3 的 `WidgetRenderer.render` / `WidgetTier.pick` / `relativeLabel`
- Produces: 三档各自的 `RemoteViews`；`WidgetTier.pick` 的阈值定稿

- [ ] **Step 1: 中卡布局**

创建 `app/android/app/src/main/res/layout/widget_medium.xml`。三行逐行写全 —— 不用 `addView` 嵌套 RemoteViews：那是个真技术，但它在这里要引入「嵌套视图的 LayoutParams 由容器决定」这层不显眼的规则，而本设计已经有一处未验证项（Task 5 的位图）了，不该再加第二处。XML 重复是免费的。

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  中档：未来三天。尺寸约 4×2（380×180dp）。
  每行：色点(8dp) + 相对称法 + 日期 + 班次名(右对齐) + 时间串。
  三行结构完全一致，渲染侧用 id 数组循环填 —— 见 WidgetRenderer.medium。
-->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_m_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:background="@drawable/widget_card_light"
    android:padding="14dp">

    <!-- ===== 第 1 行 ===== -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:orientation="horizontal"
        android:gravity="center_vertical">

        <ImageView
            android:id="@+id/wg_m_dot1"
            android:layout_width="8dp"
            android:layout_height="8dp"
            android:scaleType="fitXY"
            android:contentDescription="@null" />

        <TextView
            android:id="@+id/wg_m_label1"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="10dp"
            android:textSize="14sp"
            android:textStyle="bold"
            android:maxLines="1" />

        <TextView
            android:id="@+id/wg_m_date1"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="8dp"
            android:textSize="12sp"
            android:maxLines="1" />

        <TextView
            android:id="@+id/wg_m_shift1"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:layout_marginStart="10dp"
            android:textSize="14sp"
            android:textStyle="bold"
            android:gravity="end"
            android:maxLines="1"
            android:ellipsize="end" />

        <TextView
            android:id="@+id/wg_m_time1"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="8dp"
            android:textSize="12sp"
            android:maxLines="1" />
    </LinearLayout>

    <!-- 同 widget_small：分隔线必须是 ImageView，不能用 <View>（无 @RemoteView）。 -->
    <ImageView
        android:id="@+id/wg_m_div1"
        android:layout_width="match_parent"
        android:layout_height="1dp"
        android:layout_marginTop="4dp"
        android:contentDescription="@null" />

    <!-- ===== 第 2 行 ===== -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:orientation="horizontal"
        android:gravity="center_vertical">

        <ImageView
            android:id="@+id/wg_m_dot2"
            android:layout_width="8dp"
            android:layout_height="8dp"
            android:scaleType="fitXY"
            android:contentDescription="@null" />

        <TextView
            android:id="@+id/wg_m_label2"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="10dp"
            android:textSize="14sp"
            android:textStyle="bold"
            android:maxLines="1" />

        <TextView
            android:id="@+id/wg_m_date2"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="8dp"
            android:textSize="12sp"
            android:maxLines="1" />

        <TextView
            android:id="@+id/wg_m_shift2"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:layout_marginStart="10dp"
            android:textSize="14sp"
            android:textStyle="bold"
            android:gravity="end"
            android:maxLines="1"
            android:ellipsize="end" />

        <TextView
            android:id="@+id/wg_m_time2"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="8dp"
            android:textSize="12sp"
            android:maxLines="1" />
    </LinearLayout>

    <!-- 同 widget_small：分隔线必须是 ImageView，不能用 <View>（无 @RemoteView）。 -->
    <ImageView
        android:id="@+id/wg_m_div2"
        android:layout_width="match_parent"
        android:layout_height="1dp"
        android:layout_marginTop="4dp"
        android:contentDescription="@null" />

    <!-- ===== 第 3 行（底下不再接分隔线） ===== -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:orientation="horizontal"
        android:gravity="center_vertical">

        <ImageView
            android:id="@+id/wg_m_dot3"
            android:layout_width="8dp"
            android:layout_height="8dp"
            android:scaleType="fitXY"
            android:contentDescription="@null" />

        <TextView
            android:id="@+id/wg_m_label3"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="10dp"
            android:textSize="14sp"
            android:textStyle="bold"
            android:maxLines="1" />

        <TextView
            android:id="@+id/wg_m_date3"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="8dp"
            android:textSize="12sp"
            android:maxLines="1" />

        <TextView
            android:id="@+id/wg_m_shift3"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:layout_marginStart="10dp"
            android:textSize="14sp"
            android:textStyle="bold"
            android:gravity="end"
            android:maxLines="1"
            android:ellipsize="end" />

        <TextView
            android:id="@+id/wg_m_time3"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="8dp"
            android:textSize="12sp"
            android:maxLines="1" />
    </LinearLayout>
</LinearLayout>
```

- [ ] **Step 2: 大卡布局**

创建 `app/android/app/src/main/res/layout/widget_large.xml`。

**「一周」是从今天起连续 7 天，不是自然周** —— 快照结构本来就是 `days[0] = 今天`，换成自然周要额外引入「一周从周几开始」，且那个判断在不同文化下还不一样。

八格逐格写全。每格：日期（13sp）+ 班次胶囊（`FrameLayout` 48×22dp，里面叠一层 `ImageView` 底色与一个居中的简称 `TextView`）。第 8 格留空 —— 它仍然在布局里站着位置，渲染侧把它 `GONE` 掉，这样 4×2 的网格不会因为少一格而塌成 7 格挤一行。

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  大档：一周一览。尺寸约 4×4（380×380dp）。
  4 列 × 2 行 = 8 格，前 7 格是今天起连续 7 天，第 8 格由渲染侧隐藏。
  胶囊里的底色由 Task 5 画成位图（setImageViewBitmap）；现在是实色方块。
-->
<GridLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wg_l_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/widget_card_light"
    android:padding="12dp"
    android:columnCount="4"
    android:rowCount="2">

    <!-- ===== 格 1 ===== -->
    <LinearLayout
        android:id="@+id/wg_l_cell1"
        android:layout_width="0dp"
        android:layout_height="0dp"
        android:layout_columnWeight="1"
        android:layout_rowWeight="1"
        android:orientation="vertical"
        android:gravity="center">

        <TextView
            android:id="@+id/wg_l_date1"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textSize="13sp"
            android:textStyle="bold"
            android:maxLines="1" />

        <FrameLayout
            android:layout_width="48dp"
            android:layout_height="22dp"
            android:layout_marginTop="4dp">

            <ImageView
                android:id="@+id/wg_l_pill1"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:scaleType="fitXY"
                android:contentDescription="@null" />

            <TextView
                android:id="@+id/wg_l_abbr1"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:gravity="center"
                android:textSize="12sp"
                android:textStyle="bold"
                android:maxLines="1" />
        </FrameLayout>
    </LinearLayout>

    <!-- ===== 格 2 ===== -->
    <LinearLayout
        android:id="@+id/wg_l_cell2"
        android:layout_width="0dp"
        android:layout_height="0dp"
        android:layout_columnWeight="1"
        android:layout_rowWeight="1"
        android:orientation="vertical"
        android:gravity="center">

        <TextView
            android:id="@+id/wg_l_date2"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textSize="13sp"
            android:textStyle="bold"
            android:maxLines="1" />

        <FrameLayout
            android:layout_width="48dp"
            android:layout_height="22dp"
            android:layout_marginTop="4dp">

            <ImageView
                android:id="@+id/wg_l_pill2"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:scaleType="fitXY"
                android:contentDescription="@null" />

            <TextView
                android:id="@+id/wg_l_abbr2"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:gravity="center"
                android:textSize="12sp"
                android:textStyle="bold"
                android:maxLines="1" />
        </FrameLayout>
    </LinearLayout>

    <!-- ===== 格 3 ===== -->
    <LinearLayout
        android:id="@+id/wg_l_cell3"
        android:layout_width="0dp"
        android:layout_height="0dp"
        android:layout_columnWeight="1"
        android:layout_rowWeight="1"
        android:orientation="vertical"
        android:gravity="center">

        <TextView
            android:id="@+id/wg_l_date3"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textSize="13sp"
            android:textStyle="bold"
            android:maxLines="1" />

        <FrameLayout
            android:layout_width="48dp"
            android:layout_height="22dp"
            android:layout_marginTop="4dp">

            <ImageView
                android:id="@+id/wg_l_pill3"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:scaleType="fitXY"
                android:contentDescription="@null" />

            <TextView
                android:id="@+id/wg_l_abbr3"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:gravity="center"
                android:textSize="12sp"
                android:textStyle="bold"
                android:maxLines="1" />
        </FrameLayout>
    </LinearLayout>

    <!-- ===== 格 4 ===== -->
    <LinearLayout
        android:id="@+id/wg_l_cell4"
        android:layout_width="0dp"
        android:layout_height="0dp"
        android:layout_columnWeight="1"
        android:layout_rowWeight="1"
        android:orientation="vertical"
        android:gravity="center">

        <TextView
            android:id="@+id/wg_l_date4"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textSize="13sp"
            android:textStyle="bold"
            android:maxLines="1" />

        <FrameLayout
            android:layout_width="48dp"
            android:layout_height="22dp"
            android:layout_marginTop="4dp">

            <ImageView
                android:id="@+id/wg_l_pill4"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:scaleType="fitXY"
                android:contentDescription="@null" />

            <TextView
                android:id="@+id/wg_l_abbr4"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:gravity="center"
                android:textSize="12sp"
                android:textStyle="bold"
                android:maxLines="1" />
        </FrameLayout>
    </LinearLayout>

    <!-- ===== 格 5 ===== -->
    <LinearLayout
        android:id="@+id/wg_l_cell5"
        android:layout_width="0dp"
        android:layout_height="0dp"
        android:layout_columnWeight="1"
        android:layout_rowWeight="1"
        android:orientation="vertical"
        android:gravity="center">

        <TextView
            android:id="@+id/wg_l_date5"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textSize="13sp"
            android:textStyle="bold"
            android:maxLines="1" />

        <FrameLayout
            android:layout_width="48dp"
            android:layout_height="22dp"
            android:layout_marginTop="4dp">

            <ImageView
                android:id="@+id/wg_l_pill5"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:scaleType="fitXY"
                android:contentDescription="@null" />

            <TextView
                android:id="@+id/wg_l_abbr5"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:gravity="center"
                android:textSize="12sp"
                android:textStyle="bold"
                android:maxLines="1" />
        </FrameLayout>
    </LinearLayout>

    <!-- ===== 格 6 ===== -->
    <LinearLayout
        android:id="@+id/wg_l_cell6"
        android:layout_width="0dp"
        android:layout_height="0dp"
        android:layout_columnWeight="1"
        android:layout_rowWeight="1"
        android:orientation="vertical"
        android:gravity="center">

        <TextView
            android:id="@+id/wg_l_date6"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textSize="13sp"
            android:textStyle="bold"
            android:maxLines="1" />

        <FrameLayout
            android:layout_width="48dp"
            android:layout_height="22dp"
            android:layout_marginTop="4dp">

            <ImageView
                android:id="@+id/wg_l_pill6"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:scaleType="fitXY"
                android:contentDescription="@null" />

            <TextView
                android:id="@+id/wg_l_abbr6"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:gravity="center"
                android:textSize="12sp"
                android:textStyle="bold"
                android:maxLines="1" />
        </FrameLayout>
    </LinearLayout>

    <!-- ===== 格 7 ===== -->
    <LinearLayout
        android:id="@+id/wg_l_cell7"
        android:layout_width="0dp"
        android:layout_height="0dp"
        android:layout_columnWeight="1"
        android:layout_rowWeight="1"
        android:orientation="vertical"
        android:gravity="center">

        <TextView
            android:id="@+id/wg_l_date7"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textSize="13sp"
            android:textStyle="bold"
            android:maxLines="1" />

        <FrameLayout
            android:layout_width="48dp"
            android:layout_height="22dp"
            android:layout_marginTop="4dp">

            <ImageView
                android:id="@+id/wg_l_pill7"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:scaleType="fitXY"
                android:contentDescription="@null" />

            <TextView
                android:id="@+id/wg_l_abbr7"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:gravity="center"
                android:textSize="12sp"
                android:textStyle="bold"
                android:maxLines="1" />
        </FrameLayout>
    </LinearLayout>

    <!-- ===== 格 8（渲染侧恒 GONE，占着位置让前 7 格保持 4 列均分） ===== -->
    <LinearLayout
        android:id="@+id/wg_l_cell8"
        android:layout_width="0dp"
        android:layout_height="0dp"
        android:layout_columnWeight="1"
        android:layout_rowWeight="1"
        android:orientation="vertical"
        android:gravity="center">

        <TextView
            android:id="@+id/wg_l_date8"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textSize="13sp"
            android:textStyle="bold"
            android:maxLines="1" />

        <FrameLayout
            android:layout_width="48dp"
            android:layout_height="22dp"
            android:layout_marginTop="4dp">

            <ImageView
                android:id="@+id/wg_l_pill8"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:scaleType="fitXY"
                android:contentDescription="@null" />

            <TextView
                android:id="@+id/wg_l_abbr8"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:gravity="center"
                android:textSize="12sp"
                android:textStyle="bold"
                android:maxLines="1" />
        </FrameLayout>
    </LinearLayout>
</GridLayout>
```

- [ ] **Step 3: 渲染侧补 MEDIUM / LARGE**

在 `WidgetRenderer.kt` 里：

**(a)** 把 Step 7 那段 `when (tier)` 的占位换成真分派：

```kotlin
        val dark = isDark(context, snap.themeMode)
        return when (tier) {
            // 小卡与大卡自己算 dark（它们只在这一个地方被调），中卡由外面传进去 ——
            // 中卡的三行共用一个 dark，传参比在循环里每次重算清楚。
            WidgetTier.SMALL -> small(context, snap, todayIndex)
            WidgetTier.MEDIUM -> medium(context, snap, todayIndex, dark = dark)
            WidgetTier.LARGE -> large(context, snap, todayIndex)
        }
```

**(b)** 加两个方法。中卡的三行结构一致，用一个 `IntArray` 数组按 id 循环，避免三段复制粘贴各写错一处：

```kotlin
    private fun medium(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        dark: Boolean,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_medium)
        v.setInt(
            R.id.wg_m_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted =
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)
        val divider =
            context.getColor(if (dark) R.color.wg_divider_dark else R.color.wg_divider_light)
        val empty = context.getColor(
            if (dark) R.color.wg_empty_dark else R.color.wg_empty_light
        )

        // 三行的 id 表。顺序与 widget_medium.xml 里的行顺序一一对应。
        val dots = intArrayOf(R.id.wg_m_dot1, R.id.wg_m_dot2, R.id.wg_m_dot3)
        val labels = intArrayOf(R.id.wg_m_label1, R.id.wg_m_label2, R.id.wg_m_label3)
        val dates = intArrayOf(R.id.wg_m_date1, R.id.wg_m_date2, R.id.wg_m_date3)
        val shifts = intArrayOf(R.id.wg_m_shift1, R.id.wg_m_shift2, R.id.wg_m_shift3)
        val times = intArrayOf(R.id.wg_m_time1, R.id.wg_m_time2, R.id.wg_m_time3)
        val divs = intArrayOf(R.id.wg_m_div1, R.id.wg_m_div2)

        for (row in 0 until 3) {
            val i = todayIndex + row
            if (i >= snap.days.size) {
                // 窗口耗尽：今天已经排到 days[12] / days[13]（App 十来天没打开，
                // 跨天只右移不重算）。整行隐藏。
                // ⚠️ 这**不是**「不可能」—— 原注释那么写是错的，Task 4 的评审算过：
                // todayIndex ∈ [0,13] 是设计明确支持的状态，12/13 时这里真的会走到。
                for (idArr in listOf(dots, labels, dates, shifts, times)) {
                    v.setViewVisibility(idArr[row], android.view.View.GONE)
                }
                continue
            }
            val d = snap.days[i]

            // 色点：Task 5 换成圆形位图。今天是实心圆点，其余是同样的实心 ——
            // 「今天」那行靠字重与相对称法区分，不靠点的形状。
            v.setInt(
                dots[row],
                "setBackgroundColor",
                if (d.hasShift) d.color else empty,
            )

            v.setTextViewText(labels[row], relativeLabel(snap, i, todayIndex))
            v.setTextColor(labels[row], ink)
            v.setTextViewText(dates[row], d.dateShort)
            v.setTextColor(dates[row], muted)

            v.setTextViewText(
                shifts[row],
                if (d.hasShift) d.shiftName else d.weekday,
            )
            v.setTextColor(shifts[row], ink)

            if (d.timeRange == null) {
                v.setViewVisibility(times[row], android.view.View.GONE)
            } else {
                v.setViewVisibility(times[row], android.view.View.VISIBLE)
                v.setTextViewText(times[row], d.timeRange)
                v.setTextColor(times[row], muted)
            }
        }
        // 分隔线只画在「上面那一行可见、且下面也还有一行」的地方 —— 否则行被隐藏后
        // 会在空白区域留一条悬空的线（窗口将耗尽时真的会发生）。
        for (k in divs.indices) {
            val above = todayIndex + k < snap.days.size
            val below = todayIndex + k + 1 < snap.days.size
            v.setViewVisibility(
                divs[k],
                if (above && below) android.view.View.VISIBLE else android.view.View.GONE,
            )
            v.setInt(divs[k], "setBackgroundColor", divider)
        }

        return v
    }
```

```kotlin
    /** 大卡的格子：今天起连续 7 天。第 8 格恒隐藏 —— 它占着位置让前 7 格保持 4 列均分。 */
    private fun large(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_large)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_l_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )

        // 这里**不**声明 ink：大卡的日期走 muted、简称走 abbrInk（Dart 侧按班次色
        // 算好的白/黑二选一），没有需要纯正文色的地方。声明了会被 analyze 报未使用。
        val muted =
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)
        val empty = context.getColor(
            if (dark) R.color.wg_empty_dark else R.color.wg_empty_light
        )

        // 显式列 id，**不要**用 `resources.getIdentifier("wg_l_cell$n", ...)` ——
        // 后者靠名字反射，改个 id 名只在运行时静默返回 0，编译期毫无提示。
        val cells = intArrayOf(
            R.id.wg_l_cell1, R.id.wg_l_cell2, R.id.wg_l_cell3, R.id.wg_l_cell4,
            R.id.wg_l_cell5, R.id.wg_l_cell6, R.id.wg_l_cell7, R.id.wg_l_cell8,
        )
        val dates = intArrayOf(
            R.id.wg_l_date1, R.id.wg_l_date2, R.id.wg_l_date3, R.id.wg_l_date4,
            R.id.wg_l_date5, R.id.wg_l_date6, R.id.wg_l_date7, R.id.wg_l_date8,
        )
        val pills = intArrayOf(
            R.id.wg_l_pill1, R.id.wg_l_pill2, R.id.wg_l_pill3, R.id.wg_l_pill4,
            R.id.wg_l_pill5, R.id.wg_l_pill6, R.id.wg_l_pill7, R.id.wg_l_pill8,
        )
        val abbrs = intArrayOf(
            R.id.wg_l_abbr1, R.id.wg_l_abbr2, R.id.wg_l_abbr3, R.id.wg_l_abbr4,
            R.id.wg_l_abbr5, R.id.wg_l_abbr6, R.id.wg_l_abbr7, R.id.wg_l_abbr8,
        )

        for (cell in 0 until 7) {
            val i = todayIndex + cell
            // ⚠️ 边界保护必须有，而且**这不是「防御性代码」**：快照是 14 天，`todayIndex`
            // 落在 [0,13] 是设计明确支持的状态（跨天只右移不重算，App 八天以上没打开就
            // 会走到 8 以后）。越界抛的 `IndexOutOfBoundsException` 会被
            // `ShiftWidgetProvider.renderAll` 的 try/catch 吞掉 —— 结果不是崩，而是
            // `updateAppWidget` 被跳过、卡片**继续显示上一次渲染的旧日期**，正是
            // `widget_snapshot.dart` 开头警告的「理直气壮写错」。
            // （Task 4 的评审算过：medium() 有这道闸、large() 漏了，6/14 的窗口都会中招。）
            if (i >= snap.days.size) {
                v.setViewVisibility(cells[cell], android.view.View.GONE)
                continue
            }
            val d = snap.days[i]
            v.setViewVisibility(cells[cell], android.view.View.VISIBLE)
            v.setTextViewText(dates[cell], d.dateShort)
            v.setTextColor(dates[cell], muted)

            if (d.hasShift) {
                // Task 5 把这里换成带圆角的位图。
                v.setInt(pills[cell], "setBackgroundColor", d.color)
                v.setTextViewText(abbrs[cell], d.shiftAbbr)
                v.setTextColor(abbrs[cell], d.abbrInk)
            } else {
                // 休班：只留一个浅色空胶囊，**不写字** —— 写「休」会和真的叫
                // 「休班」的班次撞在一起，用户分不出哪个是排出来的、哪个是空着的。
                v.setInt(pills[cell], "setBackgroundColor", empty)
                v.setTextViewText(abbrs[cell], "")
            }
        }

        // 第 8 格必须显式 GONE：它有 layout_columnWeight，不隐藏就仍占掉四分之一
        // 宽度，前 7 格会被挤成一行 7 个。
        v.setViewVisibility(cells[7], android.view.View.GONE)
        return v
    }
```

> `abbrInk` 由 Dart 侧算好（`AppTokens.onSolid`），不是原生算的 —— 白黑二选一的判定规则只留一处。

**(c)** 把 `shift_widget_info.xml` 的 `android:previewLayout="@layout/widget_placeholder"` 改成 `"@layout/widget_medium"`。

**(d) 加一条守门测试 —— 这一步不是可选的。**

Task 3 踩中的那个坑（用 `<View>` 画分隔线）之所以凶险，是因为它**在开发期完全看不见**：XML 合法、编译通过、资源 id 全都解析得到、Dart 侧测试全绿、logcat 里链路也通 —— 只有真机上真的 `apply()` 那一刻才炸，而宿主抛的是 `InflateException: Class not allowed to be inflated android.view.View`，**整张卡片渲染不出来**，不是只丢那一个视图。

现在三档布局都齐了，把它变成一条会失败的测试 —— 与 `haptics_guard_test.dart` / `design_tokens_test.dart` 同款做法（拿一个筛选器扫源码，命中就红）。**注意**：这是 Dart 测试，跑在既有的 `flutter test` 里，**不需要**任何 Kotlin 单测基建 —— 与本计划 §11 那条「不引入 Kotlin 单测」的决定不冲突。

创建 `app/test/widget_layout_whitelist_test.dart`：

```dart
// 桌面小组件布局的 RemoteViews 白名单守门测试。
//
// 为什么需要它：`RemoteViews` 的视图白名单是靠 `@RemoteView` 注解做 LayoutInflater
// 的 filter 的，用了白名单外的类（最典型的是想用 `<View>` 画一条 1dp 分隔线），宿主
// 会在 apply() 阶段抛 `InflateException: Class not allowed to be inflated ...`，
// **整张卡片渲染不出来** —— 不是只丢那一个视图。
//
// 而这类缺陷在开发期几乎不可能被发现：XML 合法、编译通过、资源 id 全都解析得到、
// Dart 侧测试全绿、logcat 里链路也通。只有真机上真的渲染那一刻才炸。Task 3 实做时
// 正是这样踩中的（分隔线用了 `<View>`），差点带着它跑到发布。
//
// 所以把它变成一条会失败的测试。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `RemoteViews` 允许 inflate 的类。来源是 Google 文档「Create a simple widget」
/// 与 `android.widget.RemoteViews` 的 `@RemoteView` 注解清单。
///
/// ⚠️ 这份清单**只有文档在维持**，没有编译期保护。加新布局时若用到没列在这里的类，
/// 先在本仓 `toolchain/android-sdk/platforms/android-36/android.jar` 上跑
/// `javap -v -classpath android.jar <全限定类名> | grep -c RemoteView` 确认它确实带
/// 注解，再补进这里。
const _allowed = {
  // 布局
  'FrameLayout', 'LinearLayout', 'RelativeLayout', 'GridLayout',
  'ListView', 'GridView', 'StackView', 'AdapterViewFlipper', 'ViewFlipper',
  // 控件
  'TextView', 'ImageView', 'Button', 'ImageButton', 'ProgressBar',
  'Chronometer', 'TextClock', 'AnalogClock',
  // API 31+
  'CheckBox', 'RadioButton', 'RadioGroup', 'Switch',
};

/// XML 里长得像视图元素、但不是视图的东西 —— 免得将来用了它们被误伤。
/// `layout_*` 这类属性不会命中（正则要求 `<` 紧跟字母）。
const _nonView = {'include', 'merge', 'requestFocus'};

void main() {
  test('小组件布局里不得出现 RemoteViews 白名单之外的视图类', () {
    final dir = Directory('android/app/src/main/res/layout');
    expect(dir.existsSync(), true,
        reason: '找不到 ${dir.path} —— 测试的工作目录应当是 app/');

    final offenders = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.xml')) continue;
      if (!f.path.contains('widget')) continue; // 只管小组件的布局

      // **先剥 XML 注释再扫，但必须「等长替换」**：所有规则都靠「命中偏移 → 行号」
      // 定位，把注释**删掉**会让后面所有偏移一起前移、报出来的行号偏小。换成等长
      // 空格则偏移与行号纹丝不动 —— 这正是 `test/support/source_scan.dart` 给 Dart
      // 源码那套做法讲的道理，XML 这边照抄。
      final raw = f.readAsStringSync();
      final src = raw.replaceAllMapped(
        RegExp(r'<!--.*?-->', dotAll: true),
        (m) => m[0]!.replaceAll(RegExp(r'[^\n]'), ' '),
      );

      for (final m in RegExp(r'<([A-Za-z][A-Za-z0-9_.]*)').allMatches(src)) {
        final name = m.group(1)!;
        final simple = name.split('.').last; // 带包名前缀的取最后一段
        if (_allowed.contains(simple)) continue;
        if (_nonView.contains(simple)) continue;
        final line = src.substring(0, m.start).split('\n').length;
        offenders.add('${f.path}:$line  <$name>');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '这些类不在 RemoteViews 白名单里，宿主 inflate 时会抛 '
          'InflateException、导致整张卡片渲染不出来：\n${offenders.join('\n')}\n'
          '想画分隔线/占位，用 ImageView 或 TextView。',
    );
  });
}
```

跑它，确认三档布局加占位布局全绿：

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter test test/widget_layout_whitelist_test.dart
```

Expected: `All tests passed!`（1 条）

**顺手验一下这条测试真的会红**（不然它和没写一样）：临时把 `widget_large.xml` 里某个 `<ImageView` 改成 `<View`，重跑，应当看到那行被点名；然后**改回去**再跑绿。把这个来回的命令与输出写进报告。

- [ ] **Step 4: 标定分档阈值**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
```

在手机上把小组件分别拉到**最小、4×2、4×4** 三种尺寸，每拉一次跑：

```bash
"$ADB" logcat -d -s ShiftAssistant | grep "ShiftWidgetProvider:"
```

Expected: 三行形如 `id=… , WxHdp → TIER`。

对照实测值检查 `WidgetTier.pick` 的四个阈值：

- 最小那档必须落到 `SMALL`
- 4×2 必须落到 `MEDIUM`（**如果它落到了 `LARGE`，说明高度闸门写成了「或」** —— 那是本设计点名要避免的错）
- 4×4 必须落到 `LARGE`

若实测值与估算相差较大（比如 4×2 实测高只有 110dp），把 `WidgetTier.kt` 里的常量改成实测值下方留 10dp 余量，重构建再验一次。**改完把实测值写进 `WidgetTier` 的注释，替换掉那段「按本机估算」的话。**

- [ ] **Step 5: 三档截图**

```bash
for i in 1 2 3; do
  "$ADB" shell am force-stop com.daoban.shiftassistantpro; "$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity; sleep 3
  "$ADB" exec-out screencap -p > /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/work/wg_t4_$i.png
done
```

（截图前在手机上把小组件拉到对应档位。）

Expected（看图）：
- **小**：今天 + 明天预告
- **中**：三行，今天加粗、行首色点、行间浅线
- **大**：8 格 4×2，前 7 格是今天起 7 天，第 8 格空；每格日期 + 班次胶囊

- [ ] **Step 6: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/android/app/src/main/res/layout/widget_medium.xml \
        app/android/app/src/main/res/layout/widget_large.xml \
        app/android/app/src/main/res/xml/shift_widget_info.xml \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetTier.kt
git commit -m "feat(widget): 三档布局与分档阈值标定

中卡三行、大卡 4×2 格子。阈值按真机实测标定，高度闸门是「且」不是
「或」—— 4×1 那种宽而扁的尺寸宽度轻松过 300，只看宽度会让三行被静默
裁掉最后一行。"
```

---

## Task 5: 圆角色块（本设计唯一的未知项）

`<shape>` 只能在布局里静态引用，运行期构造的 `GradientDrawable` **传不进 `RemoteViews`**（官方白名单）。而班次色是用户在编辑器里自由选的任意 ARGB，没法枚举成几个静态 drawable。

方案：按 `(色, 圆角, 尺寸)` 缓存一张小 `Bitmap`，走 `setImageViewBitmap`。这是官方文档点名的可行做法。

**Files:**
- Create: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetChip.kt`
- Modify: `app/android/app/src/main/kotlin/.../WidgetRenderer.kt`

**Interfaces:**
- Consumes: Task 4 的 `small` / `medium` / `large`
- Produces: `WidgetChip.bar(color: Int, wPx: Int, hPx: Int): Bitmap` · `WidgetChip.circle(color: Int, sizePx: Int): Bitmap` · `WidgetChip.pill(color: Int, wPx: Int, hPx: Int): Bitmap`

- [ ] **Step 1: 写 `WidgetChip`**

创建 `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetChip.kt`：

```kotlin
package com.daoban.shiftassistantpro

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.LruCache

/**
 * 班次色块的小位图。
 *
 * 为什么非要画位图：色块的颜色是**用户自选**的任意 ARGB（编辑器的取色盘），
 * 没法枚举成几个静态的 `<shape>` drawable；而运行期构造的 `GradientDrawable`
 * 又**传不进 RemoteViews**（宿主进程渲染，只认官方白名单里的东西 —— 它接受
 * drawable 资源 id 与 Bitmap，不接受 Drawable 对象）。所以只能自己画。
 *
 * 开销：一次刷新最多几十张 60×60px 以内的小图，一天刷 3~5 次，可以忽略。
 * 用 LruCache 按 (颜色, 形状, 尺寸) 复用 —— 换个月份视图时同一批颜色会反复出现。
 */
object WidgetChip {
    private const val MAX_ENTRIES = 64
    private val cache = LruCache<String, Bitmap>(MAX_ENTRIES)

    /** 色条：完全圆头（与 App 里 `pillOf(6)` 同款）。 */
    fun bar(color: Int, wPx: Int, hPx: Int): Bitmap =
        rounded(color, wPx, hPx, radiusPx = wPx / 2f)

    /** 胶囊：圆角为高度的一半。 */
    fun pill(color: Int, wPx: Int, hPx: Int): Bitmap =
        rounded(color, wPx, hPx, radiusPx = hPx / 2f)

    /** 圆点：中卡行首那个，直径 = 高。 */
    fun circle(color: Int, sizePx: Int): Bitmap = rounded(
        color, sizePx, sizePx, radiusPx = sizePx / 2f,
    )

    private fun rounded(color: Int, w: Int, h: Int, radiusPx: Float): Bitmap {
        val width = w.coerceAtLeast(1)
        val height = h.coerceAtLeast(1)
        val key = "$color:$width:$height:$radiusPx"
        cache.get(key)?.let { return it }

        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        // 圆角半径不能超过短边的一半，否则 RectF 会画出怪形状。
        val r = radiusPx.coerceAtMost(minOf(width, height) / 2f)
        canvas.drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), r, r, paint)
        cache.put(key, bmp)
        return bmp
    }
}
```

- [ ] **Step 2: 三处色块改用位图**

在 `WidgetRenderer.kt` 里。**先把密度拿到手** —— `RemoteViews` 里的尺寸是 px，dp→px 要自己乘：

在 `object WidgetRenderer` 顶部加：

```kotlin
    private fun dpToPx(context: Context, dp: Int): Int =
        (dp * context.resources.displayMetrics.density).toInt()
```

然后把三处 `setBackgroundColor` 换掉：

**(a) 小卡的色条**（`small` 里）—— 把那段 `v.setInt(R.id.wg_s_bar, "setBackgroundColor", ...)` 整块替换成：

```kotlin
        // 色条：6dp 宽、撑满班次区高度。高度要到布局跑完才知道，这里按一个固定值
        // 画（180dp 档位下这个区域约 60dp），贴上去时 ImageView 会用 `fitXY` 把它
        // 缩放到控件大小 —— **是缩放不是裁切**，所以 6dp 宽这条被纵向压到约 0.83×、
        // 圆头成微椭圆。肉眼几乎无差，但别在注释里写成「只会被裁」（那是错的，
        // 而且与 Task 5 特意修掉的那类「假保证」同源）。
        //
        // ⚠️ 休班日也要**设位图**，不能只 `setBackgroundColor`。理由：`setBackgroundColor`
        // 设的是 background，而班次日设的是 image；宿主在布局 id 不变时会走
        // `RemoteViews.reapply`，它只重放**新的**动作列表 —— 没被重设的 image 会留着
        // 旧位图、盖在新背景色上面。结果就是「昨天白班、今天休班」那天，色条还挂着
        // 昨天的颜色。统一都设位图，从结构上免疫，而不是逐个分支打补丁。
        v.setImageViewBitmap(
            R.id.wg_s_bar,
            WidgetChip.bar(
                if (today.hasShift) {
                    today.color
                } else {
                    context.getColor(if (dark) R.color.wg_empty_dark else R.color.wg_empty_light)
                },
                dpToPx(context, 6),
                dpToPx(context, 72),
            ),
        )
```

并在 `widget_small.xml` 里给 `wg_s_bar` 加上 `android:scaleType="fitXY"`。

**(b) 中卡的色点**（`medium` 里）—— 把 `v.setInt(dots[row], "setBackgroundColor", ...)` 换掉：

```kotlin
            // 休班也设位图（浅色圆点），理由同 (a)：只 `setBackgroundColor`
            // 会让上一次的位图留在 ImageView 上。
            v.setImageViewBitmap(
                dots[row],
                WidgetChip.circle(
                    if (d.hasShift) d.color else empty,
                    dpToPx(context, 8),
                ),
            )
```

并在 `widget_medium.xml` 里给三个 `wg_m_dotN` 加上 `android:scaleType="fitXY"`。

**(c) 大卡的胶囊**（`large` 里）—— 把 `v.setInt(pills[cell], "setBackgroundColor", d.color)` 换掉。胶囊宽度由简称字数决定，固定给一个够宽的：

```kotlin
            // 胶囊宽度写死：RemoteViews 里量不到文字宽度（排版在宿主进程做）。
            // 3 个字的简称（中文最多 2 字、英文最多 4 个字母的缩写）在 12sp 下
            // 约 40dp 就够；给 48dp 留余量，多的部分由 fitXY 拉伸，
            // 而 TextView 是居中的，视觉上看不出来。
            //
            // 休班也设位图（浅色空胶囊），理由同 (a)。
            v.setImageViewBitmap(
                pills[cell],
                WidgetChip.pill(
                    if (d.hasShift) d.color else empty,
                    dpToPx(context, 48),
                    dpToPx(context, 22),
                ),
            )
            // 文字也走「无条件设」：休班那格清空。写「休」会和真叫「休班」的
            // 班次撞在一起，用户分不出哪个是排出来的、哪个是空着的。
            // `abbrInk` 在无班次时 Dart 侧给的是 0（透明），空串配透明字正好。
            v.setTextViewText(abbrs[cell], if (d.hasShift) d.shiftAbbr else "")
            v.setTextColor(abbrs[cell], d.abbrInk)
```

并在 `widget_large.xml` 里给八个 `wg_l_pillN` 加上 `android:scaleType="fitXY"`。

- [ ] **Step 3: 构建并验证圆角**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze lib
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
"$ADB" shell am force-stop com.daoban.shiftassistantpro; "$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity
sleep 3
"$ADB" exec-out screencap -p > /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/work/wg_t5.png
```

Expected（放大看截图）：小卡的色条两端是**圆头**；中卡的色点是**正圆**；大卡的胶囊是**圆角矩形**，且简称文字在胶囊里居中。

**若圆角没出来**（显示成方块或全黑），按这个顺序查：
1. 位图是不是被 R8/资源收缩弄没了 —— 不会，位图是运行期画的
2. `android:scaleType` 是不是漏加了 —— 漏了会拉伸变形，但不会变黑
3. `Bitmap.Config.ARGB_8888` 是不是被换成了 `RGB_565` —— 那会丢掉 alpha，圆角外变成黑角
4. 真的退不回来，就走 spec §13.1 的**降级方案**：删掉 `WidgetChip`，三处改回 `setBackgroundColor` 画方形色块。**降级是有意的产品选择，不是失败** —— 说明这一条要写进 spec 的修订记录。

- [ ] **Step 4: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetChip.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt \
        app/android/app/src/main/res/layout/widget_small.xml \
        app/android/app/src/main/res/layout/widget_medium.xml \
        app/android/app/src/main/res/layout/widget_large.xml
git commit -m "feat(widget): 班次色块改画位图以拿到圆角

色块颜色是用户自选的任意 ARGB，没法枚举成静态 <shape>；而运行期构造的
GradientDrawable 传不进 RemoteViews。按 (色, 形状, 尺寸) 缓存小位图，
走 setImageViewBitmap —— 官方文档点名的做法。"
```

---

## Task 6: 刷新链 —— 跨天与班次边界

到此为止，小组件只会在「加进桌面」和「打开 App」时刷新。这一步补上「App 没打开也要翻页」。

**Files:**
- Create: `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRefreshScheduler.kt`
- Modify: `app/android/app/src/main/kotlin/.../ShiftWidgetProvider.kt`
- Modify: `app/android/app/src/main/kotlin/.../MainActivity.kt`
- Modify: `app/android/app/src/main/kotlin/.../BootReceiver.kt`

**Interfaces:**
- Consumes: `WidgetStore.snapshot`（Task 2）· `ShiftWidgetProvider.ACTION_REFRESH` / `refreshAll`
- Produces: `WidgetRefreshScheduler.schedule(context: Context, atMs: Long)` · `ShiftWidgetProvider.scheduleNextRefresh(context: Context)`

- [ ] **Step 1: 写 `WidgetRefreshScheduler`**

创建 `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRefreshScheduler.kt`：

```kotlin
package com.daoban.shiftassistantpro

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 把「下一次该刷新了」排进 AlarmManager。
 *
 * 与 [AlarmScheduler] 的分工：那条链路排的是**响铃闹钟**（AlarmClock 类型、会出声、
 * 走 AlarmReceiver → 前台服务）；这条排的是**小组件重绘**（静默、走
 * ShiftWidgetProvider 的 ACTION_REFRESH）。两者互不影响，但共享同一个
 * 「自续排」的套路 —— 每次刷新只排下一个边界，不一次排一堆。
 *
 * 刷新时刻由 Dart 侧算好放在快照的 `boundaries` 里（见 `widget_snapshot.dart`），
 * 原生只做一次线性扫描。为什么不在原生算：那些算法（本地零点怎么跨时区、跨午夜
 * 班次的结束落在次日、休班不产生边界）属于「算错了不报错、只显示错」的那一类，
 * 放在有 170 条测试的 Dart 侧划算得多。
 */
object WidgetRefreshScheduler {

    /** 请求码。与 `MainActivity.REQ_PICK_RINGTONE(40071)` 错开。 */
    private const val REQ = 40081

    fun schedule(context: Context, atMs: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = PendingIntent.getBroadcast(
            context,
            REQ,
            Intent(context, ShiftWidgetProvider::class.java)
                .setAction(ShiftWidgetProvider.ACTION_REFRESH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        try {
            // API 31 起精确闹钟要用户授权（SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM）。
            // 被收回时退化成非精确 —— 跨天翻页本来就不要求秒级准时，可接受的偏差是
            // 「凌晨多等一会儿才翻页」，而不是「卡片永久停住」。
            if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
                AlarmLog.info(context, "WidgetRefreshScheduler: 无精确权限，退化非精确 at=$atMs")
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
                AlarmLog.info(context, "WidgetRefreshScheduler: 已排精确 at=$atMs")
            }
        } catch (e: Exception) {
            // SecurityException（权限中途被收回）等：绝不让它冒出去弄崩 onReceive。
            // 再退一档，用不保证唤醒的 set()。
            try {
                am.set(AlarmManager.RTC_WAKEUP, atMs, pi)
                AlarmLog.info(context, "WidgetRefreshScheduler: 二次退化为 set() at=$atMs")
            } catch (e2: Exception) {
                AlarmLog.error(context, "WidgetRefreshScheduler.schedule 彻底失败: ${e2.message}")
            }
        }
    }

    fun cancel(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = PendingIntent.getBroadcast(
            context,
            REQ,
            Intent(context, ShiftWidgetProvider::class.java)
                .setAction(ShiftWidgetProvider.ACTION_REFRESH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        am.cancel(pi)
    }
}
```

- [ ] **Step 2: `ShiftWidgetProvider` 补排程**

在 `companion object` 里加：

```kotlin
        /**
         * 排下一次刷新。
         *
         * 快照里 `boundaries` 是生成时刻起、14 天窗口内所有「该刷新了」的时刻
         * （每天的本地零点 + 各工作班次的开始/结束），升序。取第一个大于现在的即可。
         * 窗口耗尽（App 两周没打开）就退化为「下一个本地零点」—— 那时卡片本来就已经
         * 是占位态了，零点这一刷只是给它一个自愈的机会。
         */
        fun scheduleNextRefresh(context: Context) {
            val now = System.currentTimeMillis()
            val snap = WidgetStore.snapshot(context)
            val next = snap?.boundaries?.firstOrNull { it > now }
                ?: run {
                    val d = java.time.LocalDate.now().plusDays(1)
                    AlarmLog.info(context, "ShiftWidgetProvider: 边界窗口耗尽，退化为下一个零点")
                    d.atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
                }
            WidgetRefreshScheduler.schedule(context, next)
        }
```

并在 `refreshAll` 与 `onUpdate` 的末尾各加一行 `scheduleNextRefresh(context)`：

```kotlin
        fun refreshAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, ShiftWidgetProvider::class.java)
            )
            AlarmLog.info(context, "ShiftWidgetProvider.refreshAll: ${ids.size} 个实例")
            renderAll(context, mgr, ids)
            scheduleNextRefresh(context)
        }
```

```kotlin
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        renderAll(context, appWidgetManager, appWidgetIds)
        scheduleNextRefresh(context)
    }
```

`onReceive` 里 `ACTION_REFRESH` 分支也补：

```kotlin
        if (intent.action == ACTION_REFRESH) {
            refreshAll(context)
            return
        }
```

（`refreshAll` 自己已经会排下一次，所以这里不用再加。）

- [ ] **Step 3: `BootReceiver` 补重排**

`AlarmManager` 的记录**重启即清空**，小组件的刷新闹钟也不例外。在 `BootReceiver.onReceive` 的最末尾（`AlarmLog.info(context, "BootReceiver: 提醒重排完成，$quiets 条")` 之后）追加：

```kotlin
        // 小组件的刷新闹钟也重启即清空，同样要排回去。与上面两条链路的区别是：
        // 它没有「清单」可读 —— 边界时刻就在快照里，`scheduleNextRefresh` 自己
        // 会挑第一个未来的。所以这里只是「叫醒它一次」。
        try {
            ShiftWidgetProvider.scheduleNextRefresh(context)
        } catch (e: Exception) {
            AlarmLog.error(context, "BootReceiver: 小组件刷新重排失败: ${e.message}")
        }
```

- [ ] **Step 4: 构建安装、验证闹钟排上了**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
"$ADB" shell am force-stop com.daoban.shiftassistantpro; "$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity
sleep 4
"$ADB" shell dumpsys alarm | grep -B4 -A4 shiftassistantpro
"$ADB" logcat -d -s ShiftAssistant | grep "WidgetRefreshScheduler"
```

Expected:
- `logcat` 里有一行 `WidgetRefreshScheduler: 已排精确 at=…`
- `dumpsys alarm` 里能看到这个包名下的 `WIDGET_REFRESH`

把 `at=` 那个毫秒换算成时刻对一下：它应当等于**今天班次的开始时刻、结束时刻、或明天零点**三者中最早的那个未来时刻。

- [ ] **Step 5: 验证「当前时刻已过界」时能自愈**

把手机的系统时间往**今天班次开始之后**拨（设置 → 日期与时间关掉自动、手改），然后：

```bash
"$ADB" shell am force-stop com.daoban.shiftassistantpro; "$ADB" shell am start -n com.daoban.shiftassistantpro/.MainActivity
sleep 4
"$ADB" shell dumpsys alarm | grep -A4 shiftassistantpro
```

Expected: 排的时刻**前进到了下一个边界**（不再是刚刚那个已经过去的），说明 `firstOrNull { it > now }` 的过滤生效。

**验完把系统时间拨回自动。**

- [ ] **Step 6: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRefreshScheduler.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/ShiftWidgetProvider.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/BootReceiver.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/MainActivity.kt
git commit -m "feat(widget): 跨天与班次边界的自动刷新

边界时刻由 Dart 算好放在快照里，原生只做一次线性扫描 —— 日期算术留在
有 170 条测试的那一侧。精确闹钟权限被收回时两级退化，绝不让异常冒出去
弄崩 onReceive。开机也要重排（AlarmManager 记录重启即清空）。"
```

---

## Task 7: 点击 —— 开 App，并跳到那一天

**Files:**
- Modify: `app/android/app/src/main/kotlin/.../WidgetRenderer.kt`
- Modify: `app/lib/features/calendar/calendar_screen.dart`

**Interfaces:**
- Consumes: `WidgetService.widgetLaunchRequested`（Task 3）· `MainActivity.handleWidgetIntent` 读的 `"widget_day"` extra（Task 3）
- Produces: 大卡每格可点；`CalendarScreen` 响应跳转请求

- [ ] **Step 1: 整卡点击 → 开 App**

在 `WidgetRenderer.kt` 里加一个工具方法：

```kotlin
    /**
     * 打开 App 的 PendingIntent。
     *
     * 用 `getActivity` + 显式组件：隐式 LAUNCHER intent 在某些 ROM 上会被解析到
     * 「选择启动器」之类的东西上。requestCode 用 widget id 区分 —— 同一个
     * PendingIntent 被不同实例共用时，extras 会互相覆盖。
     */
    private fun launchIntent(context: Context, requestCode: Int, epochDay: Int? = null): PendingIntent {
        val i = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (epochDay != null) putExtra("widget_day", epochDay)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
```

`launchIntent` 需要知道 widget id 才能给出互不冲突的 requestCode（同一个 `PendingIntent` 被多个实例共用时，extras 会互相覆盖）。所以这一步要给**四个函数**加参数，一个都不能漏 —— 漏了编译不过，报的是参数不匹配，容易一眼看出；真正容易漏的是下一步 `renderAll` 里那次调用。

**改动清单（逐个照做）：**

```kotlin
    fun render(
        context: Context,
        snap: WidgetStore.Snapshot?,
        tier: WidgetTier,
        widgetId: Int,
    ): RemoteViews
```

```kotlin
    private fun placeholder(context: Context, dark: Boolean, widgetId: Int): RemoteViews
    private fun small(context: Context, snap: WidgetStore.Snapshot, todayIndex: Int, widgetId: Int): RemoteViews
    private fun medium(context: Context, snap: WidgetStore.Snapshot, todayIndex: Int, dark: Boolean, widgetId: Int): RemoteViews
    private fun large(context: Context, snap: WidgetStore.Snapshot, todayIndex: Int, widgetId: Int): RemoteViews
```

`render` 内部的三处调用与 `placeholder` 的两处调用（`snap == null` 那支与「快照过期」那支）都要把 `widgetId` 透传下去。

然后在每个布局函数里加一行整卡点击：

| 函数 | 加这一行 |
|---|---|
| `placeholder` | `v.setOnClickPendingIntent(R.id.wg_ph_root, launchIntent(context, widgetId))` |
| `small` | `v.setOnClickPendingIntent(R.id.wg_s_root, launchIntent(context, widgetId))` |
| `medium` | `v.setOnClickPendingIntent(R.id.wg_m_root, launchIntent(context, widgetId))` |
| `large` | `v.setOnClickPendingIntent(R.id.wg_l_root, launchIntent(context, widgetId))` |

整卡这一层不传 `epochDay`（点空白处就是「打开 App」，落在日历页的今天）。

`ShiftWidgetProvider.renderAll` 里对应改成 `WidgetRenderer.render(context, snap, tier, id)`。

- [ ] **Step 2: 大卡每格 → 跳到那天**

在 `large(...)` 的循环里，设置可见时加：

```kotlin
            v.setViewVisibility(cells[cell], android.view.View.VISIBLE)
            // 点某一格 → 打开 App 并跳到那天。requestCode 用 `widgetId * 16 + cell`
            // 错开（widget id 是系统给的小整数，格子最多 8 个），避免实例之间撞号。
            v.setOnClickPendingIntent(
                cells[cell],
                launchIntent(context, widgetId * 16 + cell, epochDay = d.day.toInt()),
            )
```

`large` 也要接 `widgetId` 参数。

> 第 8 格（下标 7）在 14 天窗口里永远有数据，所以不需要给它单独设「普通启动」—— 循环里统一处理。

- [ ] **Step 3: `CalendarScreen` 消费跳转请求**

在 `app/lib/features/calendar/calendar_screen.dart`。

**(a)** 顶部加 import：`import '../widget/widget_service.dart';`

**(b)** 在 `_CalendarScreenState` 的 `initState` 里（找 `_month = …` / `_selected = …` 那两行的初始化之后）加：

```dart
    WidgetService.widgetLaunchRequested.addListener(_onWidgetLaunchRequested);
```

**(c)** 在 `dispose()` 里加：

```dart
    WidgetService.widgetLaunchRequested.removeListener(_onWidgetLaunchRequested);
```

> 若 `_CalendarScreenState` 没有 `dispose()`，就新建一个。

**(d)** 新增方法（放在 `_goToday` 之类既有导航方法旁边）：

```dart
  /// 用户在桌面小组件上点了某一天。
  ///
  /// 消费完由**这里**把 notifier 置回 null（不是 HomeShell）—— HomeShell 只负责
  /// 切到日历页，切完还得有人把日期落到网格上。置回会再触发一次监听，
  /// 靠开头那句「值为 null 就返回」兜住，不会递归。
  void _onWidgetLaunchRequested() {
    final d = WidgetService.widgetLaunchRequested.value;
    if (d == null) return;
    WidgetService.widgetLaunchRequested.value = null;
    if (!mounted) return;
    setState(() {
      _month = DateTime(d.year, d.month, 1);
      _selected = dateOnly(d);
    });
  }
```

> `_selected` 用 `dateOnly(d)` 而不是 `d`：`dateFromEpochDay` 给的是 UTC 纯日期，而网格里逐格构造的是本地日期 —— `isSameDay` 按 UTC 日期整数比较，两边混用不会出错，但 `_selected` 直接参与 `_visualCol`/`_visualRow` 的计算，统一成 `dateOnly` 更稳。
>
> 若既有初始化不是 `dateOnly(...)` 而是别的写法，照抄既有那行的写法。

- [ ] **Step 4: 构建安装、真机验证两种启动路径**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze lib
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter test
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter build apk --release
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
```

**冷启动路径**：先 `"$ADB" shell am force-stop com.daoban.shiftassistantpro`，再在桌面上点大卡的**某一格**。

Expected: App 打开、落在**日历页**、并且**选中的是那一格对应的日期**（截图确认）。

**热启动路径**：App 先打开并切到「闹钟」tab，回桌面点大卡的某格。

Expected: 切回 App 时**跳到日历 tab** 且选中的是那天。

**整卡路径**：点小卡的空白处。

Expected: App 打开、落在日历页、选中的是**今天**（没有传 `widget_day`，保持默认）。

- [ ] **Step 5: 提交**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt \
        app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/ShiftWidgetProvider.kt \
        app/lib/features/calendar/calendar_screen.dart
git commit -m "feat(widget): 点击整卡开 App、点大卡某格跳到那天

冷热启动分两路：冷启动走静态变量由 Dart 启动后取走，热启动直接推
onWidgetDayTapped —— 照抄 pendingTodoId 那条既有链路的分界。"
```

---

## Task 8: 收尾 —— 文档、版本号、发布

**Files:**
- Modify: `app/pubspec.yaml`（`version:`）
- Modify: `app/lib/core/app_info.dart`（`appVersion`）
- Modify: `app/lib/features/profile/app_dialogs.dart`（更新日志）
- Modify: `AGENTS.md` · `README.md` · `PRODUCT_SPEC.md`

- [ ] **Step 1: 版本号两处同步**

- `app/pubspec.yaml`：`version: 0.8.3+94` → `version: 0.8.4+95`
- `app/lib/core/app_info.dart`：`appVersion` 同步改成 `0.8.4`

Run: `cd app && /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter test test/app_info_test.dart`

Expected: PASS。**这条必须绿** —— 历史上漏改过四轮，代价是「我的」页显示错版本、升级后更新弹窗再也不弹。

- [ ] **Step 2: 更新日志**

在 `app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh` / `_changelogEn` 里 **prepend** 一条 `0.8.4`，并**删掉最旧一条**（窗口固定 10 条）。这是**测试版**，条目按测试版规则写 —— 只写这一版改了什么，不归纳：

```
0.8.4
· 新增桌面小组件：小/中/大三档尺寸，一眼看到今天、未来三天或一周的班次
· 跨天自动翻页；在 App 里改了排班，桌面立刻跟着变
· 点小组件上的某一天，直接跳到那天的日历
```

英文版对应 `0.8.4 · Home screen widget: three sizes ...`。

- [ ] **Step 3: `AGENTS.md`**

三处：

1. 「目录架构地图（app/lib）」的代码块里，在 `features/` 那一段加：
   ```
   features/widget/            桌面小组件的快照生成与投递（原生侧见 android/.../ShiftWidgetProvider.kt）
   ```
2. 「关键决策与坑」加一条：
   ```
   - 桌面小组件走**原生 RemoteViews**，不是 Flutter 渲染。Dart 侧 `widget_snapshot.dart`
     产出「已本地化的快照」写进 SharedPreferences（`shift_widget`/`snapshot`），原生
     `ShiftWidgetProvider` 只排版 —— **Kotlin 里一个中文字面量都没有**，双语只有
     `l10n.dart` 一处。快照里相对文案（今天/明天/后天）按**偏移**索引而非按日期烘焙，
     否则跨天之后 days[1] 会自称「明天」。刷新粒度＝跨天 + 班次边界，不逐分钟。
   ```
3. 版本史末尾：`→ 0.8.3(+94) 测试版` 之后加 `→ 0.8.4(+95) 测试版`。

- [ ] **Step 4: `README.md` 与 `PRODUCT_SPEC.md`**

- `README.md` 功能清单加一条：
  ```
  - 桌面小组件：小/中/大三档，一眼看到今天、未来三天或一周的班次
  ```
- `PRODUCT_SPEC.md`：§2 功能清单补「桌面小组件（三档尺寸自适应）」；抬头版本号跟着走。**不放配图**（配图管线留给正式版 `0.9.0` 时统一重跑）。

- [ ] **Step 5: 全量测试与静态检查**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/app
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter analyze
/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin/flutter test
```

Expected: `No issues found!` 与全绿（`0.8.3` 时是 170 条，本轮加上 `widget_snapshot_test.dart` 的 10 条，应为 180 条）。

**若 analyze 报 `features/widget/widget_service.dart` 里有未使用的 import，就地删掉** —— 别跑 `dart format` 去「顺手修」。

- [ ] **Step 6: 提交文档与版本号**

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git add app/pubspec.yaml app/lib/core/app_info.dart \
        app/lib/features/profile/app_dialogs.dart \
        AGENTS.md README.md PRODUCT_SPEC.md
git commit -m "docs(widget): v0.8.4 版本号、更新日志与项目文档"
```

- [ ] **Step 7: 打 tag、构建、发布**

按项目既有流程（`AGENTS.md` 与 `scripts/release.ps1`）：

```bash
cd /c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant
git tag v0.8.4
git push origin main --tags
```

然后跑 `scripts/release.ps1` 发 GitHub Release。

⚠️ **`release.ps1` 要单独设 `GH_CONFIG_DIR`** —— `build-env.ps1` 把 `APPDATA` 重定向到了 `toolchain/appdata`，`gh` 会找不到登录态而报「未认证」：

```powershell
$env:GH_CONFIG_DIR = "$env:USERPROFILE\AppData\Roaming\GitHub CLI"
```

- [ ] **Step 8: 真机全场景复验**

按 spec §11 的清单跑一遍，每项截图存 `work/`：

| 场景 | 怎么看 |
|---|---|
| 三档布局 | 拉到最小 / 4×2 / 4×4，各截一张 |
| 深浅色 | 在「我的 → 外观」切深色，`am start` 一次，看卡片跟着变；切成「跟随系统」后切系统深色，看是否**不等 App 启动**就跟上 |
| 双语 | 切英文，`am start`，确认没有露出中文（尤其跨午夜那行） |
| 空白表 | 建一个「跟随法定节假日」方案并设为当前，看是否显示空表提示 |
| 休班日 | 翻到一个休班的日子，确认没有空的时间行 |
| 跨午夜 | 找一个夜班的日子，确认时间是「20:30 – 次日08:30」 |
| 快照过期 | 把系统时间往后拨 20 天，`am start`（不打开 App 界面就退出），看是否变占位态 |
| 点某天 | 冷热启动各一次，确认落到正确的日期 |

**验完把系统时间拨回自动。**

---

## 自审记录

**Spec 覆盖**：§1（目标/非目标）→ 全文；§2 四个决策 → 决策①②③体现在 Task 2/4/5 与 Task 5 的位图选择，决策④体现在 Task 1 的 `themeMode` 与 Task 2 的 `isDark`；§3.1 快照 schema → Task 1；§3.2 不变量 A/B → Task 1 的实现与注释、Task 3 的 `relativeLabel`；§3.3 推送时机 → Task 3 Step 8；§4 四个原生文件 → Task 2（Store/Tier/Renderer/Provider）+ Task 6（RefreshScheduler）；§5 三档 → Task 2（分档函数）与 Task 4（布局）；§6 刷新链 → Task 6；§7 交互 → Task 7；§8 视觉配方 → Task 2 Step 1–2；§9 边界与容错 → Task 2 的占位态、Task 3 的空表分支、Task 8 的复验表；§10 不做 → 全文未涉及；§11 测试 → Task 1 的 9 条 + Task 3 的 1 条 + Task 4/6/7 的真机验证步骤；§12 收尾 → Task 8；§13 风险 → 逐条落到对应任务的排查步骤里。

**一处与 spec 的差异**：spec §4 说「四个新文件」，本计划拆成五个 —— `WidgetTier` 独立成文件，因为它是个可独立审阅的判定表，塞进 `WidgetRenderer` 会让那个文件同时管「分档」与「排版」两件事。Task 8 的 spec 修订记录里要补这一笔。

**类型一致性**：`WidgetStore.Day` / `Snapshot` 的字段名与 Dart 快照的键一一对应（`day` / `weekday` / `dateShort` / `hasShift` / `isRest` / `shiftName` / `shiftAbbr` / `color` / `abbrInk` / `timeRange`）；`WidgetTier.pick(Int, Int)` 在 Task 2 定义、Task 2/4 使用；`WidgetRenderer.render` 在 Task 2 定义时是 3 参、Task 7 加到 4 参（加 `widgetId`），本计划已在 Task 7 Step 1 显式说明这次签名变更与 `renderAll` 的对应改动。
