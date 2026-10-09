# 动画与流畅性 · 第一轮（每帧重建的收口）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「每一帧到底做了多少事」降下来 —— 不改观感、不动交互语义、不碰原生。

**Architecture:** 三件事。① 日历页那四个每帧都在变的字段从 `State` 挪进两个通知源，
让「重建范围」从整页缩到那两层；② 光晕背景从「整页的祖先」改成「页面旁边的一层」，
并在交互时暂停；③ 四处「每次重算都白算」的缓存（农历 / 当月事实 / 小组件快照 / 排闹钟日志）。

**Tech Stack:** Flutter 3.47.2（Impeller 默认档）· Riverpod · drift（本轮**不**改表）· `flutter test`。

**Spec:** `docs/superpowers/specs/2026-10-10-smoothness-first-pass-design.md` ——
本计划里每一个数字（436 / 22~41µs / 139 / 101 / 46ms）都出自那份规格的 §2，跑之前先读它。

## Global Constraints

- **环境**：每次新开 shell 先 `export FLUTTER_ROOT=<repo>/toolchain/flutter && export PUB_CACHE=<repo>/toolchain/pub-cache && export PATH="$FLUTTER_ROOT/bin:$PATH"`（pwsh 用 `. tools/build-env.ps1`）。`tools/` 与 `toolchain/` 不入库。
- **版本号**：本轮 `0.10.20+144`。`app/pubspec.yaml` 的 `version:` 与 `app/lib/core/app_info.dart` 的 `appVersion` **必须同步**（`app/test/app_info_test.dart` 盯着）。`X.Y` 是用户定的，AI 只许改 `Z` 与 `build`。
- **验收**：`flutter analyze` 0 error / 0 warning（约 4 条 info 可容忍）；`flutter test` 全绿（当前 **773** 条，**只增不减**）；视觉工装 `flutter test tool/visual/`（**349** 条）另算。
- **不许跑 `dart format`** —— 工具链是新的 tall-style 格式化器，一跑就重排整文件、制造几百行无关 diff。只跑 `analyze`。
- **令牌纪律**：界面层不许写 `fontSize:` / `fontWeight:` / `Circular(<数字>)` / `Duration(milliseconds: …)` / `Color(0x…)` / `Icon` 的 `size:`，间距类常量必须落在 4px 栅格上 —— 用 `AppTokens` 的角色令牌（`app/test/design_tokens_test.dart` 守门）。
- **档位判据纪律**：`liquidGlassActive` 只许出现在 `app/test/liquid_scope_guard_test.dart` 的 `_allowed` 名单里那 7 处。**本计划新建的文件一个都不许读它**（`frame_notifier.dart` / `lens_warp_scope.dart`）—— 判据归调用点。
- **触觉**：本轮一个字不动。除 `core/haptics.dart` 外不许出现 `HapticFeedback.`。
- **本轮不改 Drift 表**，所以**不跑** `build_runner`。
- **视觉基线**：动 UI 的每个任务收尾都跑一次出图 + 逐张比；**标准档一张都不许变**。
- **一次性探针**在 `app/tool/probe/`（4 个文件，未入库）：本计划用它量前后对比，**最后一个任务里删掉**。

## Review Focus

规格里暗含、但没有哪条既有用例会照出来的五件事。每一条都已安排进某个任务的测试里：

1. **缓存键漏项** → 同一个月里换语言 / 换主色 / 调了班之后，信息卡那行「本月统计」或
   「已调班」徽章还显示旧值（静默错，界面上看不出来是 bug）。钉在 Task 10。
2. **`publishSilently` 用错地方** → 帧外误用 silent 会让该动的不动；帧内误用 `publish`
   会当场抛「setState() called during build」。钉在 Task 6 / Task 7。
3. **`_lensCenter` 静止时残留** → 上一次拖选的末端没清，某几格的字长期被挤着。钉在 Task 6。
4. **去抖 Timer 泄漏** → 测试报「A Timer is still pending」，或 dispose 之后才 fire。
   钉在 Task 4。
5. **快照去重把失败那次记成已推** → 「装完新版先打开一次 App」的兜底重试永远不再试，
   桌面小组件停在升级前那次渲染。钉在 Task 4。

---

## 文件结构

| 文件 | 动作 | 职责 |
|---|---|---|
| `app/lib/domain/lunar_info.dart` | 改 | `lunarOf` 加模块级缓存（纯函数记忆化） |
| `app/lib/features/alarm/alarm_service.dart` | 改 | 排闹钟的逐条日志收成一条汇总 |
| `app/lib/main.dart` | 改 | 去掉启动时的时区库解析 |
| `app/lib/features/widget/widget_service.dart` | 改 | 快照去重（同一份 JSON 不重复推） |
| `app/lib/features/widget/widget_snapshot.dart` | 改 | `days[]` 按天缓存 |
| `app/lib/features/home/home_shell.dart` | 改 | 快照触发合并成一处尾去抖 |
| `app/lib/core/frame_notifier.dart` | **新建** | `FrameNotifier<T>`：可「静默写」的值通知源 |
| `app/lib/features/calendar/lens_warp_scope.dart` | **新建** | `cellWarpFor(...)` 纯函数 + `LensWarpScope` 小组件 |
| `app/lib/core/theme/animated_background.dart` | 改 | 光晕自己一层 + `pauseWhen` |
| `app/lib/features/calendar/calendar_screen.dart` | 改 | 每帧状态外置 + 当月事实缓存 |
| `app/test/frame_notifier_test.dart` | 新建 | 新件的三条 |
| `app/test/lens_warp_scope_test.dart` | 新建 | 新件的四条（含「内容不重建」） |
| `app/test/lunar_info_cache_test.dart` | 新建 | 缓存命中 / 上界 |
| `app/test/alarm_reschedule_budget_test.dart` | 新建 | 护栏：跨端调用次数 |
| `app/test/widget_push_dedup_test.dart` | 新建 | 护栏：同一份不重复推 |
| `app/test/calendar_frame_budget_test.dart` | 新建 | 护栏：一帧重建的 widget 数 |

---

### Task 1: `lunarOf` 加缓存

**Files:**
- Modify: `app/lib/domain/lunar_info.dart:173-194`
- Test: `app/test/lunar_info_cache_test.dart`（新建）

**Interfaces:**
- Consumes: 无
- Produces: `LunarInfo lunarOf(DateTime date)`（签名不变）· `@visibleForTesting int lunarCacheEntryCount()` · `@visibleForTesting void lunarCacheClear()`

- [ ] **Step 1: 写失败的测试**

```dart
// app/test/lunar_info_cache_test.dart
test('同一个日期返回同一个实例（缓存命中）', () {
  lunarCacheClear();
  final a = lunarOf(DateTime(2026, 10, 1));
  final b = lunarOf(DateTime(2026, 10, 1));
  expect(identical(a, b), isTrue);
});

test('缓存有上界：超过 1024 条之后旧的被清掉', () {
  lunarCacheClear();
  for (var i = 0; i < 1025; i++) {
    lunarOf(DateTime(2020, 1, 1).add(Duration(days: i)));
  }
  expect(lunarCacheEntryCount(), lessThanOrEqualTo(1024));
});

test('值本身没被缓存改坏：缓存与直接算一字不差', () {
  lunarCacheClear();
  final fresh = lunarOf(DateTime(2026, 2, 17));
  final cached = lunarOf(DateTime(2026, 2, 17));
  expect(cached.dayChinese, fresh.dayChinese);
  expect(cached.shortLabel, fresh.shortLabel);
  expect(cached.fullDescription, fresh.fullDescription);
});
```

- [ ] **Step 2: 跑一遍，确认它红**

Run: `flutter test app/test/lunar_info_cache_test.dart`
Expected: FAIL —— `identical` 为 false（`lunarOf` 每次新建）；`lunarCacheEntryCount` 未定义。

- [ ] **Step 3: 实现**

在 `lunar_info.dart` 顶部（`lunarOf` 之前）加：

```dart
/// `lunarOf` 的记忆化。**键 = `dayNumber(date)`（自 epoch 天数）** ——
/// `LunarInfo` 与语言无关（节日名来自 lunar_plus 与内置的官方放假表，
/// `shortLabel` / `cellLabel` / `fullDescription` 都不读 `L10n`），所以键里不需要语言。
///
/// 为什么要缓存：日历一屏 42 格、每重建一次就是 42 次 `Solar.fromYmd().getLunar()`
/// （实测 22~41µs/次 ⇒ 1.5ms/次重建），而屏幕上的农历在同一个月里**永远不变**。
/// 桌面小组件那条链路更狠：一次快照 224 次。
///
/// 上界到了就**整个清掉**，不做 LRU —— 请求天然按天聚集，清一次最多多付一屏 42 次的
/// 代价，而 LRU 要多一套要维护、要测的东西。
const int _lunarCacheMax = 1024;
final Map<int, LunarInfo> _lunarCache = <int, LunarInfo>{};

@visibleForTesting
int lunarCacheEntryCount() => _lunarCache.length;

@visibleForTesting
void lunarCacheClear() => _lunarCache.clear();
```

`lunarOf` 本体改成先查后算（命中直接 return；未命中算完塞进去，超上界先 `clear()`）。
`import 'package:flutter/foundation.dart';` 若还没有就补上（`@visibleForTesting`）。

- [ ] **Step 4: 跑一遍，确认它绿**

Run: `flutter test app/test/lunar_info_cache_test.dart`
Expected: PASS（3 条）

- [ ] **Step 5: 跑全套，确认没碰坏别的**（农历的既有用例有 `lunar_cell_label_test.dart` 等）

Run: `flutter test`
Expected: 全绿，条数 = 773 + 3

- [ ] **Step 6: 提交**

```bash
git add app/lib/domain/lunar_info.dart app/test/lunar_info_cache_test.dart
git commit -m "perf(lunar): lunarOf 加按天缓存（一屏 42 格 1.5ms → 第二次起 0）"
```

---

### Task 2: 排闹钟的日志收成一条（+ 护栏）

**Files:**
- Modify: `app/lib/features/alarm/alarm_service.dart:526-529`（删逐条）、`:980` 附近（收尾加汇总）
- Test: `app/test/alarm_reschedule_budget_test.dart`（新建）

**Interfaces:**
- Consumes: `AlarmService.rescheduleAll(AppRepository)`（签名不变）
- Produces: 无新接口；行为变化是 `scheduleNativeAlarm` 不再每次跨端记一条日志

- [ ] **Step 1: 写失败的测试**

```dart
// app/test/alarm_reschedule_budget_test.dart
// 假通道计数：一次 rescheduleAll 到底往原生发多少次调用。
// 反向验证过：把 logInfo 加回去，这条立刻红（101 > 55）。
testWidgets('一次 rescheduleAll 的跨端调用不超过 55 次', (tester) async {
  final db = await _seed3Crew(tester);           // 夹具照抄 tool/probe 里那份
  final calls = <String, int>{};
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('com.daoban.shiftassistantpro/settings'),
    (call) async { calls[call.method] = (calls[call.method] ?? 0) + 1; return null; },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('com.daoban.shiftassistantpro/settings'), null));

  await AlarmService.rescheduleAll(AppRepository(db));
  final total = calls.values.fold<int>(0, (a, b) => a + b);
  expect(total, lessThanOrEqualTo(55),
      reason: '101 次里 48 次是每闹钟一条的日志 —— 那一条不该再跟着跨端');
  expect(calls['logInfo'], lessThanOrEqualTo(3),
      reason: '只许剩收尾那一两条汇总');
});
```

- [ ] **Step 2: 跑一遍，确认它红**

Run: `flutter test app/test/alarm_reschedule_budget_test.dart`
Expected: FAIL —— `total` 约 101、`logInfo` 约 48。

- [ ] **Step 3: 实现**

删掉 `scheduleNativeAlarm` 里那句 `await logInfo('scheduleNativeAlarm 成功: …')`
（`:526-529`），**保留** `catch` 里的 `appendLog`（失败是异常路径，不砍）。
在 `reschedule` 收尾那条 `logInfo('reschedule: 完成')` 上补上计数与耗时：

```dart
// 逐条日志换成一条汇总：每个闹钟跟一条 logInfo 就是每次跨端再跨一次，
// 实测一次 rescheduleAll 的 101 次调用里 48 次是它（见规格 §2）。
await logInfo('reschedule: 完成 —— 排班闹钟 $shiftCount 条、'
    '自定义 $customCount 条、待办 $eventCount 条，耗时 ${sw.elapsedMilliseconds}ms');
```

（`sw` 在方法开头起 `Stopwatch`；三个计数在各自的循环里累加。）

- [ ] **Step 4: 跑一遍，确认它绿**

Run: `flutter test app/test/alarm_reschedule_budget_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/alarm/alarm_service.dart app/test/alarm_reschedule_budget_test.dart
git commit -m "perf(alarm): 排闹钟的逐条日志收成一条汇总（跨端调用 101 → ~54）"
```

---

### Task 3: 启动去掉时区库解析

**Files:**
- Modify: `app/lib/main.dart`（`AlarmService.init()` 之前/之内）、`app/lib/features/alarm/alarm_service.dart:300-305`

**Interfaces:**
- Consumes: 无
- Produces: 无（启动路径少 21ms）

- [ ] **Step 1: 核实它真的没用**（**不核实不许删**）

Run:
```bash
grep -rn "TZDateTime\|tz\.\|timezone" app/lib --include=*.dart
```
Expected: 只有 `alarm_service.dart` 里那句 `tz.initializeTimeZones()` 与它的 import；
**没有**任何 `zonedSchedule` / `TZDateTime` 调用点。
若出现调用点：**停在这里**，回报「时区库被用到了」，本任务作废。

- [ ] **Step 2: 删掉它，并跑受影响的用例**

删 `tz.initializeTimeZones()` 那一行与 `import 'package:timezone/data/latest_all.dart'`；
`import 'package:timezone/timezone.dart' as tz` 若也只剩初始化用，一并删。
在删掉的位置留一句注释说明为什么可以删（全仓无 `zonedSchedule` / `TZDateTime`）。

Run: `flutter test app/test/alarm_screen_test.dart app/test/event_reminder_test.dart`
Expected: PASS

- [ ] **Step 3: 跑全套**

Run: `flutter test`
Expected: 全绿

- [ ] **Step 4: 提交**

```bash
git add app/lib/main.dart app/lib/features/alarm/alarm_service.dart
git commit -m "perf(startup): 去掉首帧前的时区库解析（21ms，全仓没有一处用它）"
```

---

### Task 4: 小组件快照 —— 按天缓存 + 去抖 + 同一份不重复推

**Files:**
- Modify: `app/lib/features/widget/widget_snapshot.dart`（`days[]` 缓存）、
  `app/lib/features/widget/widget_service.dart:39-67`（去重）、
  `app/lib/features/home/home_shell.dart:56-77,137-140,176-200`（合并触发 + 尾去抖）
- Test: `app/test/widget_push_dedup_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 的 `lunarOf` 缓存（同一份缓存，不额外接线）
- Produces: `@visibleForTesting void WidgetService.resetPushCache()` ·
  `HomeShell` 内私有 `void _scheduleWidgetPush()`

- [ ] **Step 1: 写失败的测试**

```dart
// app/test/widget_push_dedup_test.dart
const _channel = MethodChannel('com.daoban.shiftassistantpro/settings');

/// 装一个只会数 `widgetPushSnapshot` 的假通道，跑 [body]，返回它发了几次。
/// [failFirst] 让前 N 次抛 —— 用来验「失败不许记成已推」。
Future<int> _pushesOf(Future<void> Function() body, {int failFirst = 0}) async {
  var pushes = 0;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
    if (call.method != 'widgetPushSnapshot') return null;
    pushes++;
    if (pushes <= failFirst) throw PlatformException(code: 'boom');
    return true;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));
  await body();
  return pushes;
}

testWidgets('同一份快照连推两次，只发一次', (tester) async {
  WidgetService.resetPushCache();
  final n = await _pushesOf(() async {
    await WidgetService.push(chain: _chain, settings: const AppSettings(), todayTodoCount: 3);
    await WidgetService.push(chain: _chain, settings: const AppSettings(), todayTodoCount: 3);
  });
  expect(n, 1);
});

testWidgets('推失败时不记「已推」，下一次照样重试', (tester) async {
  WidgetService.resetPushCache();
  final n = await _pushesOf(() async {
    await WidgetService.push(chain: _chain, settings: const AppSettings(), todayTodoCount: 3);
    await WidgetService.push(chain: _chain, settings: const AppSettings(), todayTodoCount: 3);
  }, failFirst: 1);   // 第一次抛（`push` 自己会吞掉，它是 fire-and-forget）
  expect(n, 2, reason: '第一次失败了就不能记「已推」—— 否则那条兜底重试永远不再试');
});
```

- [ ] **Step 2: 跑一遍，确认它红**

Run: `flutter test app/test/widget_push_dedup_test.dart`
Expected: FAIL —— `resetPushCache` 未定义；同一个输入推了两次。

- [ ] **Step 3: 实现**

**3a 去重**（`widget_service.dart`）：静态字段 `String? _lastPushedJson`；
`push` 里 `jsonEncode` 之后比一下，一样就直接 `return`；**只在 `invokeMethod` 成功返回之后**
才把它记上。补 `@visibleForTesting void resetPushCache() => _lastPushedJson = null;`。

**3b `days[]` 缓存**（`widget_snapshot.dart`）：把逐日那份列表的构建抽成一个私有函数，
按 `(chain.cacheKey, 窗口起点, 窗口终点, L10n.isEn, 今天)` 拼键缓存住；
命中时只重新着色（色号在 days 里）+ 重新拼 map。**缓存必须是有上界的**（只留最近一份）。

**3c 触发去抖 + 合并**（`home_shell.dart`）：把 `_pushWidgetSnapshot()` 的调用点
（首帧回调 `:67`、三处 `ref.listenManual` `:72/73/77`、`didChangeAppLifecycleState` 的
resumed `:139`）全部换成 `_scheduleWidgetPush()`：

```dart
/// 300ms 尾去抖：一次保存排班会让好几个 provider 连着发，合并成一次推送。
Timer? _pushDebounce;

void _scheduleWidgetPush() {
  _pushDebounce?.cancel();
  _pushDebounce = Timer(const Duration(milliseconds: 300), () {
    if (mounted) _pushWidgetSnapshot();
  });
}
```

⚠️ **`dispose()` 里必须 `_pushDebounce?.cancel()`** —— 不取消的话 widget 测试会报
「A Timer is still pending even after the widget tree was disposed」（Review Focus 第 4 条），
`home_shell_nav_test.dart` 会当场红。
⚠️ 那个时长字面量要走令牌（`AppTokens.durGlassIn` 之外没有 300ms 的档 —— 用
`AppTokens.durSlow`（340ms）并写明「它只是去抖窗口、不是过渡时长」，与 `animated_background`
里 `_tick` 那条同一个理由，否则 `design_tokens_test` 打红）。

- [ ] **Step 4: 跑一遍，确认它绿**

Run: `flutter test app/test/widget_push_dedup_test.dart app/test/home_shell_nav_test.dart app/test/widget_snapshot_test.dart`
Expected: PASS

- [ ] **Step 5: 跑全套**

Run: `flutter test`
Expected: 全绿

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/widget app/lib/features/home/home_shell.dart app/test/widget_push_dedup_test.dart
git commit -m "perf(widget): 快照按天缓存 + 触发去抖 + 同一份不重复推"
```

---

### Task 5: `FrameNotifier`（可静默写的值通知源）

**Files:**
- Create: `app/lib/core/frame_notifier.dart`
- Test: `app/test/frame_notifier_test.dart`（新建）

**Interfaces:**
- Consumes: 无
- Produces: `class FrameNotifier<T> extends ChangeNotifier implements ValueListenable<T>` ·
  `T get value` · `void publish(T next)`（变了才通知）· `void publishSilently(T next)`（只记值）

- [ ] **Step 1: 写失败的测试**

```dart
// app/test/frame_notifier_test.dart
test('publish：值变了才通知', () {
  final n = FrameNotifier<int>(0);
  var hits = 0;
  n.addListener(() => hits++);
  n.publish(1);
  n.publish(1);          // 同一个值 —— 不许再通知
  n.publish(2);
  expect(hits, 2);
  expect(n.value, 2);
});

test('publishSilently：值变了、但一声不响', () {
  final n = FrameNotifier<int>(0);
  var hits = 0;
  n.addListener(() => hits++);
  n.publishSilently(7);
  expect(n.value, 7);
  expect(hits, 0);
});

test('静默写之后再 publish 同一个值也不通知（值没变）', () {
  final n = FrameNotifier<int>(0);
  var hits = 0;
  n.addListener(() => hits++);
  n.publishSilently(3);
  n.publish(3);
  expect(hits, 0);
});
```

- [ ] **Step 2: 跑一遍，确认它红**

Run: `flutter test app/test/frame_notifier_test.dart`
Expected: FAIL —— 找不到 `FrameNotifier`。

- [ ] **Step 3: 实现**

```dart
// app/lib/core/frame_notifier.dart
/// 一个「可以静默写」的值通知源。
///
/// 为什么需要：日历那两层每帧都在变的值，写入点分两类 ——
/// · **帧间**（`Ticker` 回调、指针回调、带子的每帧回调）：写完之后通知，
///   `ValueListenableBuilder` 的 `setState` 在那里是安全的；
/// · **帧内**（`LayoutBuilder` 的回调跑在布局阶段）：在那里通知会当场抛
///   「setState() called during build」。而那里**不需要**通知 ——
///   `ValueListenableBuilder` 自己在 build 时读 `.value`，它排在写入点之后建。
///
/// `ValueNotifier` 的 `value` setter 只能「记值 + 通知」一条路（`_value` 是私有的，
/// 子类碰不到），所以这里自己实现一个。**判据只归调用点**：这个件不读 `liquidGlassActive`。
class FrameNotifier<T> extends ChangeNotifier implements ValueListenable<T> {
  FrameNotifier(this._value);

  T _value;

  @override
  T get value => _value;

  /// 帧间写：值变了就通知。
  void publish(T next) {
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  /// 帧内写：**只记值**，一声不响。
  void publishSilently(T next) {
    if (next == _value) return;
    _value = next;
  }
}
```

- [ ] **Step 4: 跑一遍，确认它绿**

Run: `flutter test app/test/frame_notifier_test.dart`
Expected: PASS（3 条）

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/frame_notifier.dart app/test/frame_notifier_test.dart
git commit -m "feat(core): FrameNotifier —— 可静默写的值通知源（帧内写不通知）"
```

---

### Task 6: 挤压场改走通知源（行为不变、像素不变）

**Files:**
- Create: `app/lib/features/calendar/lens_warp_scope.dart`
- Modify: `app/lib/features/calendar/calendar_screen.dart`（`_cellWarp` 挪走、`_dayRows` 改用它、
  `_gridBody` 里那几处写 `_lensCenter`）
- Test: `app/test/lens_warp_scope_test.dart`（新建）；既有 `app/test/calendar_screen_test.dart`、
  `app/test/lens_warped_cell_test.dart` 全绿

**Interfaces:**
- Consumes: Task 5 的 `FrameNotifier<Offset?>`
- Produces:
  - `Matrix4? cellWarpFor({required Offset cellCenter, required Offset lensCenter, required double cellW, required double cellH, required double inset})`
  - `class LensWarpScope extends StatelessWidget`，参数 `{required ValueListenable<Offset?> center, required Offset cellCenter, required double cellW, required double cellH, required double inset, required Widget child}`

这一任务**不加分**（块那一层照旧每帧重建）—— 它只把那 42 格那条路换成「只重算矩阵」，
好处是把风险摊成两步：这一步先证明「换一条等价的路，画面一个像素不变」。

- [ ] **Step 1: 写失败的测试**

```dart
// app/test/lens_warp_scope_test.dart
test('cellWarpFor：恒等时返回 null（一层 Transform 都不套）', () {
  // 中心远在天边 → 权重见底
  expect(cellWarpFor(cellCenter: const Offset(100, 100),
      lensCenter: const Offset(9000, 9000),
      cellW: 56, cellH: 72, inset: 5), isNull);
});

test('cellWarpFor：中心压在这一格上时给一个非恒等矩阵', () {
  final m = cellWarpFor(cellCenter: const Offset(100, 100),
      lensCenter: const Offset(100, 100),
      cellW: 56, cellH: 72, inset: 5);
  expect(m, isNotNull);
});

testWidgets('LensWarpScope：中心为 null 时原样返回 child（树上没有 Transform）',
    (tester) async {
  final n = FrameNotifier<Offset?>(null);
  await tester.pumpWidget(MaterialApp(home: LensWarpScope(
      center: n, cellCenter: Offset.zero, cellW: 56, cellH: 72, inset: 5,
      child: const Text('内容'))));
  expect(find.byType(Transform), findsNothing);
});

testWidgets('LensWarpScope：中心变了只重算矩阵，**格子内容不重建**',
    (tester) async {
  // Review Focus 第 2 条：帧内写入走 silent（不通知）时画面照样要跟上
  var contentBuilds = 0;
  // 用 debugOnRebuildDirtyWidget 数 child 那棵子树；断言它为 0
  // （内容作为一个实例传进 `child:`，矩阵变了它也不重建）
});
```

- [ ] **Step 2: 跑一遍，确认它红**

Run: `flutter test app/test/lens_warp_scope_test.dart`
Expected: FAIL —— 找不到 `cellWarpFor` / `LensWarpScope`。

- [ ] **Step 3: 实现**

**3a** 把 `calendar_screen.dart:1467-1491` 的 `_cellWarp` **原样**搬进新文件成顶层函数
`cellWarpFor(...)`（`_cellInset` 变成参数 `inset`）—— 算式与注释一起搬，一个字不改。

**3b** 写 `LensWarpScope`：`ValueListenableBuilder<Offset?>(valueListenable: center,
child: child, builder: …)`，`center == null` 或矩阵为 null 时 `return child!`，
否则 `Transform(alignment: Alignment.center, transform: m, child: child)`。
**这个件不许读 `liquidGlassActive`**（档位判据归调用点）。

**3c** 接线（`calendar_screen.dart`）：
- State 加字段 `final FrameNotifier<Offset?> _lensCenter = FrameNotifier<Offset?>(null);`
  （`dispose()` 里 `_lensCenter.dispose()`），以及私有方法
  **`void _publishFrame({required Offset? center, bool silent = false})`** ——
  本任务里它只写 `_lensCenter`；Task 7 会把 `BlockFrame` 一并塞进同一个方法
  （**只此一处发布，两个通知源不许各自写**）。
- `_gridBody` 里那两处算出的中心（`bandWarpCenter` / 块心）**一样发出去**，但走
  `silent: true`（那段跑在 `LayoutBuilder` 的**布局阶段** —— Review Focus 第 2 条）。
- 带子的 `onTipPos` 回调与 `onPanUpdate` / `_onFlightTick` 里那两处（帧间）走 `publish`。
- **`_rangeAnchor`/`_rangeFocus` 被清掉时（`onLongPressEnd` / `_clearGestureState`）
  必须把中心发成 `null`** —— 否则上一次拖选的末端留在那儿，某几格的字长期被挤着
  （Review Focus 第 3 条）。加一条用例钉住。
- `_dayRows` 去掉 `lensCenter` 参数，改成给每格内容套
  `liquidGlassActive.value ? LensWarpScope(center: _lensCenter, …) : 内容` ——
  **标准档那棵树因此与今天逐字节相同**（多一个 VLB 都不加）。

- [ ] **Step 4: 跑一遍，确认它绿**

Run: `flutter test app/test/lens_warp_scope_test.dart app/test/calendar_screen_test.dart app/test/lens_warped_cell_test.dart`
Expected: PASS

- [ ] **Step 5: 出图，逐张比基线**（这一步是本任务的**主要验收**）

Run:
```bash
flutter test tool/visual/            # 349 条
python scripts/diff_visual.py <基线目录> <新目录>
```
Expected: **一张都不许变**（这一步是纯等价的搬运；有差异就停在这里查清楚，
不许带着差异往下走）。

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/calendar app/test/lens_warp_scope_test.dart
git commit -m "refactor(calendar): 挤压场改走通知源 + 抽 LensWarpScope（画面逐像素不变）"
```

---

### Task 7: 块那一层改走通知源（收益落地 + 护栏 #1）

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`（`_blockPlacement` / `_glassBlock` /
  `_onFlightTick` / `onPanUpdate` / `onPanStart` / `onPanEnd`）
- Test: `app/test/calendar_frame_budget_test.dart`（新建）

**Interfaces:**
- Consumes: Task 5 的 `FrameNotifier<T>`、Task 6 已接好的 `_lensCenter`
- Produces: `class BlockFrame { final Offset pos; final Offset velocity; final bool live; }`（`app` 私有，
  定义在 `calendar_screen.dart` 顶部）+ State 字段 `_blockFrame`（`FrameNotifier<BlockFrame>`）

- [ ] **Step 1: 写失败的测试（护栏 #1）**

```dart
// app/test/calendar_frame_budget_test.dart
// 护栏：液态档「点一个日期起飞行」时，**一帧重建的 widget 数**必须小。
// 反向验证过：把那几个值塞回 State（每帧 setState），这条立刻红（436 > 80）。
testWidgets('液态档一帧重建的 widget 数 ≤ 80', (tester) async {
  await _pumpCalendar(tester, liquid: true);   // ⚠️ 液态档必须走 prefs，不是模块标志
  var n = 0; var on = false;
  debugOnRebuildDirtyWidget = (e, _) { if (on) n++; };
  addTearDown(() => debugOnRebuildDirtyWidget = null);
  final today = DateTime.now().day;
  await tester.tap(find.byKey(ValueKey('day-card-${today > 15 ? today - 7 : today + 7}')));
  await tester.pump();
  on = true;
  await tester.pump(const Duration(milliseconds: 16));
  on = false;
  expect(n, lessThanOrEqualTo(80), reason: '标准档同场景是 6，今天液态档是 436');
});

testWidgets('标准档同场景仍然是 6 上下（这条路一个字没动）', (tester) async { … });
```

- [ ] **Step 2: 跑一遍，确认它红**

Run: `flutter test app/test/calendar_frame_budget_test.dart`
Expected: FAIL —— 实测 436。

- [ ] **Step 3: 实现**

- `BlockFrame`（`@immutable`，实现 `==` 与 `hashCode` —— `publish` 靠 `==` 挡掉重复写）。
- `_blockFrame = FrameNotifier<BlockFrame>(…)`（初值 = 今天那一格的位置、速度 0、`live: false`）。
- `_publishFrame({required Offset? center, bool silent = false})`（Task 6 建的）：现在再把
  `_flightPos` / `_vx` / `_vy` 与 `live: _dragActive || _flying`（**与今天 `:1987` 那句一字
  不差**）打包成 `BlockFrame` 一起发出 —— 两个通知源**仍然只从这一个方法**出去。
- **写入点逐个换**（四处 `setState` → `_publishFrame`）：
  `:521` 飞行 tick（**注意顺序**：先 `_flightPos = pos`、再 `if (t >= 1) _stopFlight()`、
  **最后**才 publish —— 这样最后一帧发出去的是 `live: false`，透镜那边「松手那一帧把
  最后的速度交回来」照样成立）、`:1211` 拖动、`:1180` panStart（`live: true`）、
  `:1224` panEnd（**速度不归零**，只是 `live` 变 false）。
- 块那一层改成 `Positioned.fill(IgnorePointer(ValueListenableBuilder<BlockFrame>(…)))`，
  builder 返回**内层 `Stack`**（`clipBehavior: Clip.none`）里一个 `Positioned`
  —— ⚠️ **`Stack` 的孩子必须是 `Positioned`**，直接把 VLB 塞进去布局当场错
  （规格 §4.1 纪律 1）。
- `_glassBlock` 不再从 State 读 `_vx/_vy/_flying`，改读 `BlockFrame` 的三个字段；
  `liftTarget` 仍读 `_pressed || _dragActive`（离散状态，仍走 `setState`）。
- 标准档那条分支（`AnimatedPositioned`）**一个字节都不改**。
- `dispose()` 里 `_blockFrame.dispose()`。

- [ ] **Step 4: 跑一遍，确认它绿**

Run: `flutter test app/test/calendar_frame_budget_test.dart`
Expected: PASS（液态档 ≤ 80）

- [ ] **Step 5: 出图 + 逐张比基线**

Run: `flutter test tool/visual/ && python scripts/diff_visual.py <基线> <新>`
Expected: **标准档一张都不变**；液态档只许在「挤压场/块」那几屏出现差异，
逐张写得出理由。

- [ ] **Step 6: 手动跑一次探针，记下前后数字**

Run: `flutter test tool/probe/perf_probe_test.dart`
Expected: `PROBE frame N: 重建 … 个 widget` 从 436 降到 ≤ 80。把数字抄进提交信息。

- [ ] **Step 7: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_frame_budget_test.dart
git commit -m "perf(calendar): 每帧状态外置，一帧重建 436 → N 个 widget（标准档逐像素不变）"
```

---

### Task 8: 光晕改成自己一层

**Files:**
- Modify: `app/lib/core/theme/animated_background.dart`

**Interfaces:**
- Consumes: 无
- Produces: `FlowingBackground` 的外部接口不变（`intensity` / `freezeWhenBlurDisabled` / `child`）

- [ ] **Step 1: 改结构**

`CustomPaint(painter: _WavePainter(...), child: widget.child)` 换成：

```dart
Stack(children: <Widget>[
  Positioned.fill(
    child: RepaintBoundary(
      child: CustomPaint(painter: _WavePainter(_t, widget.intensity)),
    ),
  ),
  widget.child,
])
```

层序与今天**完全一致**（今天 painter 也是先画、child 后画），所以画面应当逐像素相同。
把「为什么不给 child 加 RepaintBoundary」写进注释（`BackdropFilter` 看不到边界外的变化
会把模糊冻住 —— 规格 §4.3a）。

- [ ] **Step 2: 跑该页的既有用例**

Run: `flutter test app/test/calendar_screen_test.dart app/test/alarm_ringing_liquid_test.dart`
Expected: PASS

- [ ] **Step 3: 出图 + 逐张比基线**

Run: `flutter test tool/visual/ && python scripts/diff_visual.py <基线> <新>`
Expected: 一张都不许变。

- [ ] **Step 4: 跑一条专项核对（Review Focus 之外的这条，规格 §6.2 点名要）**

用探针量「光晕 tick 那一帧重绘的绘制节点」从 **139** 降到个位数：

Run: `flutter test tool/probe/perf_probe3_test.dart`
Expected: `PROBE D 光晕帧：paintChild 调用 N 次`，N ≤ 8。
⚠️ 同一条探针里还要取**两帧隔 340ms、比玻璃内部像素**：必须不同
（冻住就说明这一层的隔离放错了位置）。

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/theme/animated_background.dart
git commit -m "perf(glow): 光晕改成自己一层（一次 tick 重绘 139 → 个位数绘制节点）"
```

---

### Task 9: 光晕在交互时暂停

**Files:**
- Modify: `app/lib/core/theme/animated_background.dart`（新增 `pauseWhen`）、
  `app/lib/features/calendar/calendar_screen.dart`（`_interacting` 的源）
- Test: 加进 `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `FlowingBackground({…, ValueListenable<bool>? pauseWhen})`（默认 `null` ⇒ 行为不变）

- [ ] **Step 1: 写失败的测试**

测试要读到光晕当前走到哪一相位。为此在 `animated_background.dart` 里加两处**只读**的
观察窗（先加它们，再写用例）：

```dart
// _WavePainter 里
@visibleForTesting
double get debugPhase => t;
// CustomPaint 上
key: const Key('flowing-background'),
```

```dart
// app/test/calendar_screen_test.dart 里加
double _glowPhase(WidgetTester tester) => (tester
        .widget<CustomPaint>(find.byKey(const Key('flowing-background')))
        .painter! as dynamic)
    .debugPhase as double;

testWidgets('拖动中光晕停、松手后接着走（不跳回）', (tester) async {
  await _pumpCalendar(tester, liquid: true);
  final t0 = _glowPhase(tester);
  for (var i = 0; i < 21; i++) { await tester.pump(const Duration(milliseconds: 16)); }
  expect(_glowPhase(tester), isNot(t0), reason: '静止时它在走');

  await _startDrag(tester);                 // 按住拖起来（`_dragActive` 为真）
  final t1 = _glowPhase(tester);
  for (var i = 0; i < 42; i++) { await tester.pump(const Duration(milliseconds: 16)); }
  expect(_glowPhase(tester), t1, reason: '拖动中它不动');

  await tester.pump(const Duration(milliseconds: 16)); // 收尾这一帧
  final t2 = _glowPhase(tester);
  await _endDrag(tester);
  for (var i = 0; i < 21; i++) { await tester.pump(const Duration(milliseconds: 16)); }
  expect(_glowPhase(tester), isNot(t2), reason: '松手之后接着走（且不是归零重来）');
});
```

- [ ] **Step 2: 跑一遍，确认它红**

Run: `flutter test app/test/calendar_screen_test.dart`
Expected: FAIL —— 拖动中 `t` 仍在变。

- [ ] **Step 3: 实现**

- `FlowingBackground` 加可选参数 `ValueListenable<bool>? pauseWhen`；`_syncRun` 里多一条判断
  （与 `freezeWhenBlurDisabled` **各写各的**，两者都能把定时器停掉）；`initState` 里
  `addListener(_syncRun)`、`dispose` 里 `removeListener`。
  **暂停期间 `_t` 不推进** ⇒ 恢复时接着走、不跳。
- 日历页：`final ValueNotifier<bool> _interacting = ValueNotifier<bool>(false);`
  在 `_publishFrame` 里顺手更新（`_dragActive || _flying || _rangeAnchor != null`），
  `FlowingBackground(pauseWhen: _interacting, …)`；`dispose()` 里 `dispose()` 掉。
  响铃页那一处不传 ⇒ 行为不变。

- [ ] **Step 4: 跑一遍，确认它绿**

Run: `flutter test app/test/calendar_screen_test.dart`
Expected: PASS

- [ ] **Step 5: 出图（只核对那几屏，这一条**会**改变画面 —— 但只在「正在动」的那些帧）**

Run: `flutter test tool/visual/ && python scripts/diff_visual.py <基线> <新>`
Expected: 差异只许出现在「拖选/飞行中」那几屏（`49`/`50` 那两档里本来就在动的那张），
逐张写理由。

- [ ] **Step 6: 提交**

```bash
git add app/lib/core/theme/animated_background.dart app/lib/features/calendar/calendar_screen.dart app/test/calendar_screen_test.dart
git commit -m "perf(glow): 有东西在动时暂停光晕（拿掉每 340ms 一次的固定掉帧）"
```

---

### Task 10: 当月事实按月缓存

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`
  （`_monthTally:213` / `_monthHasNoSchedule:1077` / `monthHasOverrideHint` /
  `infoCardTallyFits` 的调用点）
- Test: 加进 `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: State 内 `class _MonthFacts` + `_factsFor(...)`（与 `_cardMetricsFor` **并列**的第二份缓存）

- [ ] **Step 1: 先实现**（这一轮唯一一条「先码后测」：缓存的用例在实现之前无法变红，
  它们的鉴别力由 Step 4 的反向验证负责）

```dart
/// 与「这个月」有关、与「选中哪天」无关的几样 —— 一次算好，键变了才重量。
///
/// 键的四项：**年 | 月 | 语言 | 链指纹**，外加**本月未完成待办数**
/// （它依赖待办数据，而那不在链指纹里；这个数本身很便宜，每次重建重算一次，
/// 顺便当键用 —— 它一变，下面这一整包都要重量）。
class _MonthFacts {
  final String? tally;        // 「本月 早12 · 午8 …」
  final bool hasNoSchedule;   // 整月一天班表都没有
  final bool hasOverrideHint; // 这个月有被按天调过的日子
  final bool hasPendingTodos; // 这个月有未完成的待办
}
```

`_factsFor(context, chain)` 与既有的 `_cardMetricsFor` **同样的写法**（拼键 → 命中就返回
→ 没命中就重量）。取用点（`:213` / `:1077` / `:145` / `monthHasOverrideHint`）改成读缓存。

⚠️ `infoCardTallyFits` 需要「卡内高」，而那个是 `InfoCardMetrics` 给的 —— 它**不并进
`_MonthFacts`**（规格 §9 已定），改成挂在**与 metrics 同一把键**的第二份 memo 上。

- [ ] **Step 2: 写用例（两条键的护栏）**

```dart
testWidgets('换语言之后「本月统计」那一行跟着换（键里必须含语言）', (tester) async {
  // Review Focus 第 1 条：键漏项 = 界面上静默显示旧值
  await _pumpCalendar(tester, 'four_crew_three_shift');
  expect(find.textContaining('本月'), findsOneWidget);
  L10n.locale = 'en';
  await tester.pumpAndSettle();
  expect(find.textContaining('This month'), findsOneWidget);
});

testWidgets('本月待办徽章跟着待办走（键里必须含本月未完成待办数）', (tester) async { … });
```

- [ ] **Step 3: 跑一遍，确认它绿**

Run: `flutter test app/test/calendar_screen_test.dart app/test/info_card_chain_test.dart`
Expected: PASS

- [ ] **Step 4: 反向验证（这两条用例的鉴别力全靠这一步）**

把 `L10n.isEn` 从键里删掉 → 「换语言」那条**必须红**（红的表现：换到英文之后那一行还是
中文）；把「本月未完成待办数」从键里删掉 → 徽章那条**必须红**。
两条都**先看着它红一次**，再还原。

- [ ] **Step 5: 出图 + 逐张比基线**

Run: `flutter test tool/visual/ && python scripts/diff_visual.py <基线> <新>`
Expected: 一张都不许变（这一条纯缓存，画面必须一致）。

- [ ] **Step 6: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_screen_test.dart
git commit -m "perf(calendar): 当月那五样按月缓存（每次重建少 93 次链查询 + 一个 TextPainter）"
```

---

### Task 11: 收尾 —— 前后对比、基线、账本、发版

**Files:**
- Modify: `app/pubspec.yaml` · `app/lib/core/app_info.dart` · `app/lib/features/profile/app_dialogs.dart`（更新日志）· `AGENTS.md`
- Delete: `app/tool/probe/`（4 个一次性探针）

- [ ] **Step 1: 全套验收**

Run:
```bash
flutter analyze
flutter test
flutter test tool/visual/
```
Expected: analyze 0 error / 0 warning；test 全绿（773 + 新增）；工装全绿。
**任何一条不绿就停在这里。**

- [ ] **Step 2: 前后对比（四个探针，记进提交信息与账本）**

Run: `flutter test tool/probe/`
Expected（目标值来自规格 §6.1）：

| 指标 | 改前 | 目标 |
|---|---|---|
| 液态档一帧重建 | 436 | ≤ 80 |
| 一屏 42 格 lunar | 1.47 ms | ≈ 0 |
| 光晕 tick 重绘节点 | 139 | ≤ 8 |
| `rescheduleAll` 跨端调用 | 101 | ≤ 55 |
| `buildWidgetSnapshot` | 46 ms | ≤ 15 ms |

- [ ] **Step 3: 版本号 + 更新日志**

- `app/pubspec.yaml` 的 `version:` → `0.10.20+144`；`app/lib/core/app_info.dart` 的
  `appVersion` → `'0.10.20'`（两处不同步会被 `app_info_test.dart` 打红）。
- `app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh` / `_changelogEn`：
  **prepend** 一条 0.10.20（测试版条目原样写自己改了什么）、**删最旧一条**、**保持 10 条**
  （`changelog_window_test.dart` 盯着）。⚠️ 更新日志是**纯文本**渲染的，**不许出现
  markdown 标记**（`**` / 反引号 / 行首 `#`）—— 那条用例会报出命中哪一行。
  条目里要写清「装完新版要打开一次 App」这类**用户看得见的东西**；纯内部优化就写
  「更顺了、更省电了」这种能读懂的话，别写「重建 436 → 80」。
- `AGENTS.md`：版本史末尾补一段、`## 最近改动` 顶部补 v0.10.20 那一笔（写清这一轮的
  实测数字与两条纪律：`FrameNotifier` 的帧内静默写、光晕为什么不能给 child 加
  `RepaintBoundary`）。

- [ ] **Step 4: 删掉探针**

```bash
git rm -r --cached app/tool/probe 2>/dev/null; rm -rf app/tool/probe
```
（它们本来就未入库，删掉目录即可；删完 `flutter test` 再跑一次确认没被别的用例引用。）

- [ ] **Step 5: 提交 + 打 tag + 推送（beta 分支）**

```bash
git add -A && git commit -m "chore(release): v0.10.20 —— 动画与流畅性第一轮"
git tag v0.10.20
git push origin beta && git push origin v0.10.20
```

- [ ] **Step 6: 构建 + 发布**

```bash
flutter build apk --release --target-platform android-arm64
```
然后把发布说明写到 `tools/gh/release-notes-v0.10.20.md`（末位非 0 ⇒ 自动标预发布测试版），
复制 APK 到 `dist/倒班助手Pro-v0.10.20.apk`，最后跑 `scripts/release.ps1 -SkipConfirm`。
**发完 curl 一次** `raw.githubusercontent.com/<owner>/<repo>/main/latest.json` 核对版本号
（脚本第 7b 步失败只告警、不影响发布，那时手动把 `latest.json` 同步回 main）。

---

## 自检记录

- **规格覆盖**：§4.1 → Task 6/7 · §4.2 → Task 6 · §4.3 → Task 8/9 · §4.4 → Task 10 ·
  §4.5 → Task 1 · §4.6 → Task 2 · §4.7 → Task 4 · §3 的 tz 那一项 → Task 3 ·
  §6.4 三条护栏 → Task 7 / Task 2 / Task 4 · §6.2 的专项核对 → Task 8 Step 4 ·
  收尾与发版 → Task 11。规格里没有无任务的要求。
- **任务边界**：Task 6 与 Task 7 拆开是有意的 —— 6 是「等价换路、画面不变」，7 才是
  「收益落地」。合在一起的话，一旦出图有差异就分不清是搬运错了还是外置错了。
- **类型一致**：`FrameNotifier.publish/publishSilently`（Task 5）在 6/7/9 里同名同参；
  `_publishFrame` 从 Task 6 就定名、Task 7 只是往同一个方法里多塞一个值（**不换名**）；
  `LensWarpScope` / `cellWarpFor` 的参数名在定义处、接线处、用例里三处同名同序；
  `BlockFrame` 的三个字段（`pos` / `velocity` / `live`）在 Task 7 内部一致。
- **反向验证**：这一轮的护栏大多是「新加的护栏」，都会在**当时**是绿的 —— 所以三条数字
  护栏（Task 2 / 4 / 7）与 Task 10 的缓存键护栏，**每一条都要求先看着它红一次**
  （把老写法放回去），红不出来就说明那条用例是句空话。这是仓库既有的规矩。
- **只有 Task 10 是「先码后测」**：缓存的用例在实现之前无法变红。它的鉴别力由 Step 4 的
  反向验证负责 —— 这是这一轮唯一一处例外，写在任务里了。
- **不动的东西**：`CalendarLens` 的接口、标准档那棵树、`AnimatedPositioned` 那条路、
  触觉、Drift 表 —— 计划里没有任何一步碰它们。
