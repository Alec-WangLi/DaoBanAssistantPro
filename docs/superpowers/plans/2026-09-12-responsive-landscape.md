# 手机横屏 / 小窗 / 宽屏适配 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让七个界面与全部弹层在手机横屏、小窗、宽屏（平板/车机）下都不溢出、不重叠、可完整操作，且竖屏观感逐像素不变。

**Architecture:** 新增 `core/layout.dart` 的双轴分档（`isNarrow` / `isShort` / `isWide` 三个**独立布尔值**，不是一个档位枚举），各处按档位取值。弹层改用 `LayoutBuilder` 拿弹层自己的真实预算来收缩大块部件。日历格子高度从「只按宽度算」改成「宽高共同决定」，并在宽屏走左右分栏。视觉工装加尺寸维度，把「溢出」从只能靠肉眼发现变成测试失败。

**Tech Stack:** Flutter / Dart，`flutter_test` widget 测试，纯静态 i18n。

**Spec:** `docs/superpowers/specs/2026-09-12-responsive-landscape-design.md`

## Global Constraints

- 目标版本 **`0.6.4+75`**（`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 同步；`+build` 只能递增）。
- 版本号 `X.Y` 由用户决定，AI 只能改末位 `Z` 与 `build`。
- 验收：`flutter analyze` **0 error / 0 warning**；`flutter test` **全绿**（v0.6.3 结束时是 97 条）。
- **`flutter test tool/visual/render_screens_test.dart` 在全部变体 × 7 屏下零溢出** —— 这条是本版的主要验收手段。
- **竖屏（420×900）逐像素不变**：任何算式在高屏上必须取到与今天相同的值。
- 不动竖屏的布局结构；不做每个页面各自的横屏专属设计。
- 更新日志保持 **10 条**（prepend 新版本、删最旧一条）。
- **不得出现任何「参考 / 借鉴 / 对照 / 类似某 App」的表述。**
- 所有命令的工作目录是 `app/`；Flutter 可执行文件是 `../toolchain/flutter/bin/flutter.bat`。

## 文件结构

| 文件 | 职责 | 本计划中的改动 |
|---|---|---|
| `app/lib/core/layout.dart` | **新建**。布局分档 | Task 1 |
| `app/tool/visual/visual_harness.dart` | 出图/审计工装 | Task 2：`pumpScreen` / `renderScreen` 接尺寸 |
| `app/tool/visual/visual_screens.dart` | 出图清单与变体 | Task 2：变体加尺寸 + 两个新变体 |
| `app/tool/visual/render_screens_test.dart` | 出图用例 | Task 2 |
| `app/tool/visual/contrast_audit_test.dart` | 对比度审计 | Task 2：只跑竖屏三个变体 |
| `app/lib/core/widgets/glass_pickers.dart` | 三个玻璃选择器 | Task 3 |
| `app/lib/core/widgets/glass_dialog.dart` | 通用玻璃弹窗 | Task 3 |
| `app/lib/features/calendar/calendar_screen.dart` | 日历 | Task 4、5 |
| `app/lib/features/home/home_shell.dart` | 导航壳与悬浮胶囊 | Task 5 |
| `app/lib/features/calendar/schedule_editor_screen.dart` | 排班编辑器 | Task 5、6 |
| `app/lib/features/**/*_screen.dart` | 四个 tab 页与选择页 | Task 6：宽屏限宽 |
| `app/lib/features/profile/app_dialogs.dart` | 更新日志 | Task 7 |

**为什么 `AppLayout` 用三个独立布尔值而不是 `compact / regular / expanded`**：手机横屏（900×420）与车机（1280×720）宽度都大，但一个矮一个不矮，处置完全不同；小窗（360×360）宽和矮**同时**成立。套三档枚举会立刻需要 `compactButWide` 这种名字 —— 那等于把布尔值藏起来，还多一层要维护的映射。

---

### Task 1: 布局分档

**Files:**
- Create: `app/lib/core/layout.dart`
- Test: `app/test/app_layout_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `AppLayout`，字段 `isNarrow` / `isShort` / `isWide`（`bool`）、`availableWidth` / `availableHeight`（`double`）；静态 `AppLayout.of(BuildContext)`、静态常量 `AppLayout.maxContentWidth = 720`

- [ ] **Step 1: 写失败的测试**

创建 `app/test/app_layout_test.dart`：

```dart
// app/test/app_layout_test.dart
//
// 分档判定是这一版所有适配的输入：判错了，下面每一处都会照着错的档位走。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/layout.dart';

/// 在一个指定尺寸下取分档。
Future<AppLayout> _layoutAt(WidgetTester tester, Size size,
    {EdgeInsets padding = EdgeInsets.zero,
    EdgeInsets viewInsets = EdgeInsets.zero}) async {
  late AppLayout result;
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(
      size: size,
      padding: padding,
      viewPadding: padding,
      viewInsets: viewInsets,
    ),
    child: Builder(builder: (context) {
      result = AppLayout.of(context);
      return const SizedBox();
    }),
  ));
  return result;
}

void main() {
  testWidgets('五种形态的判定与设计表一致', (tester) async {
    final portrait = await _layoutAt(tester, const Size(420, 900));
    expect(portrait.isNarrow, isFalse);
    expect(portrait.isShort, isFalse);
    expect(portrait.isWide, isFalse, reason: '竖屏手机三档全 false，所有分支都不生效');

    final landscape = await _layoutAt(tester, const Size(900, 420));
    expect(landscape.isWide, isTrue);
    expect(landscape.isShort, isTrue);
    expect(landscape.isNarrow, isFalse);

    final small = await _layoutAt(tester, const Size(360, 360));
    expect(small.isShort, isTrue);
    expect(small.isWide, isFalse);
    expect(small.isNarrow, isFalse, reason: '360 是窄的边界值，不算窄');

    final tiny = await _layoutAt(tester, const Size(320, 360));
    expect(tiny.isNarrow, isTrue);
    expect(tiny.isShort, isTrue);
    expect(tiny.isWide, isFalse);

    final car = await _layoutAt(tester, const Size(1280, 720));
    expect(car.isWide, isTrue);
    expect(car.isShort, isFalse, reason: '车机是「宽且不矮」，与手机横屏不是一回事');
    expect(car.isNarrow, isFalse);
  });

  testWidgets('可用高度扣掉键盘与系统栏', (tester) async {
    // 键盘弹起会把可用高度吃掉一半。不扣掉的话，编辑器在键盘弹起时会
    // 被误判成「屏幕变矮了」而切到紧凑档 —— 那是另一回事。
    final withKeyboard = await _layoutAt(
      tester,
      const Size(420, 900),
      viewInsets: const EdgeInsets.only(bottom: 500),
    );
    expect(withKeyboard.availableHeight, 400);
    expect(withKeyboard.isShort, isTrue, reason: '扣掉键盘后确实变矮了');

    final withBar = await _layoutAt(
      tester,
      const Size(420, 900),
      padding: const EdgeInsets.only(top: 40, bottom: 30),
    );
    expect(withBar.availableHeight, 830);
    expect(withBar.availableWidth, 420);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `../toolchain/flutter/bin/flutter.bat test test/app_layout_test.dart`
Expected: 编译失败 —— `Target of URI doesn't exist: 'package:shiftassistantpro/core/layout.dart'`

- [ ] **Step 3: 写实现**

创建 `app/lib/core/layout.dart`：

```dart
// app/lib/core/layout.dart
import 'package:flutter/material.dart';

/// 布局分档。三个判据**彼此独立** —— 手机横屏是「宽且矮」，车机是「宽且不矮」，
/// 小窗常常「又窄又矮」，用单一档位枚举表达不了：硬套会立刻需要
/// `compactButWide` 这种名字，等于把布尔值藏起来，还多一层要维护的映射。
class AppLayout {
  const AppLayout({
    required this.isNarrow,
    required this.isShort,
    required this.isWide,
    required this.availableWidth,
    required this.availableHeight,
  });

  /// 可用宽 < 360：小窗、分屏。
  final bool isNarrow;

  /// 可用高 < 480：手机横屏、小窗。
  final bool isShort;

  /// 可用宽 >= 720：平板、车机、手机横屏。
  final bool isWide;

  /// 扣掉键盘与系统栏之后的可用区域。
  final double availableWidth;
  final double availableHeight;

  /// 宽屏下内容的最大宽度。表单在 1280 宽的车机上拉满整屏会难以阅读：
  /// 「标签在左、值在右」的行会两端离得太远。
  static const double maxContentWidth = 720;

  static const double _narrowWidth = 360;
  static const double _shortHeight = 480;
  static const double _wideWidth = 720;

  /// 用**可用区域**判定，不是整屏尺寸：键盘（viewInsets）与刘海/系统栏
  /// （viewPadding）都实打实地吃掉空间。不扣掉就会把「键盘占了半屏」
  /// 误判成「屏幕变矮」，而这两件事该有完全不同的处置。
  static AppLayout of(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width - mq.viewInsets.horizontal;
    final h = mq.size.height -
        mq.viewInsets.vertical -
        mq.viewPadding.vertical;
    return AppLayout(
      isNarrow: w < _narrowWidth,
      isShort: h < _shortHeight,
      isWide: w >= _wideWidth,
      availableWidth: w,
      availableHeight: h,
    );
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `../toolchain/flutter/bin/flutter.bat test test/app_layout_test.dart`
Expected: PASS（2 条）

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/layout.dart app/test/app_layout_test.dart
git commit -m "feat(layout): 新增双轴布局分档 core/layout.dart"
```

---

### Task 2: 视觉工装加尺寸维度

先建好验收工具，后面每一处改动都能立刻在横屏与小窗下出图核对。这也是本版「把溢出变成测试失败」的落点：`failOnOverflow` 已经在渲染期间捕获布局溢出，只要让它跑在横屏尺寸下就能自动发现。

**Files:**
- Modify: `app/tool/visual/visual_harness.dart`（`pumpScreen`、`renderScreen`）
- Modify: `app/tool/visual/visual_screens.dart`（`visualVariants`）
- Modify: `app/tool/visual/render_screens_test.dart`（传尺寸）
- Modify: `app/tool/visual/contrast_audit_test.dart`（只跑竖屏）

**Interfaces:**
- Consumes: 无
- Produces: `visualVariants` 的每条多一个 `Size size` 字段；`pumpScreen(..., Size size = kVisualSize)`、`renderScreen(..., Size size = kVisualSize)`

- [ ] **Step 1: 给 `pumpScreen` 与 `renderScreen` 加尺寸参数**

`app/tool/visual/visual_harness.dart`。

`pumpScreen` 签名加一行参数（其余不动）：

```dart
Future<GlobalKey> pumpScreen(
  WidgetTester tester, {
  required Widget home,
  required List<Override> overrides,
  Brightness brightness = Brightness.light,
  String language = 'zh',
  Map<String, Object> extraPrefs = const {},
  Size size = kVisualSize,
  Future<void> Function(WidgetTester tester)? beforeCapture,
}) async {
```

并把函数体内设置视口的那四行改成用 `size`：

```dart
  tester.view.physicalSize = Size(
    size.width * kVisualDpr,
    size.height * kVisualDpr,
  );
```

`renderScreen` 同样加 `Size size = kVisualSize`，透传给 `pumpScreen`，并把收尾那行日志改成用 `size`：

```dart
  stdout.writeln(
      '[visual] ${file.path}  ${size.width.toInt()}x${size.height.toInt()} @${kVisualDpr}x');
```

- [ ] **Step 2: 给变体加尺寸，并加两个新变体**

`app/tool/visual/visual_screens.dart` 的 `visualVariants` 整段替换：

```dart
/// 每个界面要出的变体。
///
/// 英文那张不是凑数：文案漏翻、英文顶到边、日期格式在英文下串成
/// 「2026 9」这类问题，只有在英文界面上才看得见。
///
/// 横屏与小窗两张同样不是凑数：它们的尺寸正是 v0.6.1 里「几乎无法使用」
/// 的那两种形态 —— 工装过去只拍 420×900，所以那些缺陷一张图都拍不到。
final List<
    ({
      String suffix,
      String label,
      Brightness brightness,
      String language,
      Size size,
    })> visualVariants = [
  (
    suffix: 'light',
    label: '浅色',
    brightness: Brightness.light,
    language: 'zh',
    size: kVisualSize,
  ),
  (
    suffix: 'dark',
    label: '深色',
    brightness: Brightness.dark,
    language: 'zh',
    size: kVisualSize,
  ),
  (
    suffix: 'en',
    label: '英文',
    brightness: Brightness.light,
    language: 'en',
    size: kVisualSize,
  ),
  (
    suffix: 'landscape',
    label: '横屏 900×420',
    brightness: Brightness.light,
    language: 'zh',
    size: Size(900, 420),
  ),
  (
    suffix: 'small',
    label: '小窗 360×360',
    brightness: Brightness.light,
    language: 'zh',
    size: Size(360, 360),
  ),
];
```

- [ ] **Step 3: 出图用例传尺寸**

`app/tool/visual/render_screens_test.dart` 的循环里给 `renderScreen` 加一行：

```dart
          language: variant.language,
          size: variant.size,
          extraPrefs: screen.needsOnboardingPrefs ? onboardingPrefs : const {},
```

- [ ] **Step 4: 对比度审计只跑竖屏三张**

对比度与尺寸无关，多跑两个尺寸是白烧一倍时间。`app/tool/visual/contrast_audit_test.dart` 的循环改成：

```dart
  for (final screen in visualScreens) {
    // 对比度与画布尺寸无关；只跑竖屏那三张，横屏/小窗两张跳过。
    for (final variant
        in visualVariants.where((v) => v.size == kVisualSize)) {
```

并在文件顶部确认已 import `visual_harness.dart`（`kVisualSize` 在那里）。

- [ ] **Step 5: 跑出图，看现在的横屏与小窗坏成什么样**

Run: `../toolchain/flutter/bin/flutter.bat test tool/visual/render_screens_test.dart`

Expected: **失败** —— `failOnOverflow` 会在横屏与小窗变体上报出一批布局溢出。这正是本版要修的东西；把失败清单记下来，作为后面几个任务的靶子。

**如果意外全绿**：说明溢出没被捕获，先查 `failOnOverflow` 是否真的挂上了（它在每个用例开头调用）。

- [ ] **Step 6: 提交**

```bash
git add app/tool/visual/
git commit -m "test(visual): 工装加尺寸维度，新增横屏 900×420 与小窗 360×360 变体"
```

---

### Task 3: 弹层限高自适应

**Files:**
- Modify: `app/lib/core/widgets/glass_pickers.dart`（三个选择器）
- Modify: `app/lib/core/widgets/glass_dialog.dart`
- Test: `app/test/glass_pickers_layout_test.dart`（新建）

**Interfaces:**
- Consumes: `AppLayout.of(context).availableHeight`（Task 1）
- Produces: 无新对外接口（弹层对外签名不变）

- [ ] **Step 1: 写失败的测试**

创建 `app/test/glass_pickers_layout_test.dart`：

```dart
// app/test/glass_pickers_layout_test.dart
//
// 三个玻璃选择器在短屏（手机横屏 / 小窗）下的高度自适应。
//
// 这一版的起因就是它们：`showModalBottomSheet` 默认把弹层压到屏幕的 9/16，
// 横屏 420 高的屏上只有 236px，而时间选择器的内容要 340px —— 一定会溢出。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/widgets/glass_pickers.dart';

/// 在指定尺寸下打开某个弹层。
Future<void> _open(
  WidgetTester tester,
  Size size,
  Future<void> Function(BuildContext) open,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('时间选择器：高屏滚轮 180，横屏收缩', (tester) async {
    await _open(tester, const Size(420, 900),
        (c) => showGlassTimePicker(c, initialTime: const TimeOfDay(hour: 8, minute: 0)));
    // 高屏上应当仍是今天的高度
    expect(tester.takeException(), isNull);

    await _open(tester, const Size(900, 420),
        (c) => showGlassTimePicker(c, initialTime: const TimeOfDay(hour: 8, minute: 0)));
    // 横屏的关键断言是「没有溢出异常」—— 尺寸具体取多少由 clamp 决定
    expect(tester.takeException(), isNull);
  });

  testWidgets('月份选择器：小窗也不溢出', (tester) async {
    await _open(tester, const Size(360, 360),
        (c) => showGlassMonthPicker(c, initialMonth: DateTime(2026, 9)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('日期选择器：横屏也不溢出', (tester) async {
    await _open(
      tester,
      const Size(900, 420),
      (c) => showGlassDatePicker(c, initialDate: DateTime(2026, 9, 12)),
    );
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `../toolchain/flutter/bin/flutter.bat test test/glass_pickers_layout_test.dart`
Expected: FAIL —— 横屏与小窗的用例报 `A RenderFlex overflowed by N pixels`

- [ ] **Step 3: 时间选择器**

`app/lib/core/widgets/glass_pickers.dart` 的 `showGlassTimePicker` 加上 `isScrollControlled: true`：

```dart
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    // 不开这个开关，`showModalBottomSheet` 会把弹层压到屏幕的 9/16 ——
    // 横屏 420 高的屏上只有 236px，而下面的内容要 340px，必然溢出。
    isScrollControlled: true,
    barrierColor: Colors.black26,
    builder: (context) => _GlassTimePickerSheet(initialTime: initialTime),
  );
```

`_GlassTimePickerSheetState.build` 里，把 `Column` 包进 `LayoutBuilder`，并把滚轮那段的固定 `height: 180` 改成算出来的值：

```dart
  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      solid: true,
      margin: const EdgeInsets.all(12),
      borderRadius: const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
      child: SafeArea(
        // 用弹层**自己的**预算：margin 与 SafeArea 已经被 LayoutBuilder 扣掉了，
        // 再自己按 MediaQuery 算一遍容易漏项。
        child: LayoutBuilder(
          builder: (context, constraints) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  L10n.selectTime,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  // 106 = 内边距 28 + 标题 22 + 间距 12 + 按钮行 44；
                  // 余下的都留给滚轮，但不超过今天的 180，也不低于能滚的 96。
                  height: (constraints.maxHeight - 106).clamp(96.0, 180.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _wheel(
                          itemCount: 24,
                          initialItem: _hour,
                          onChanged: (i) => _hour = i,
                        ),
                      ),
                      const Text(':',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700)),
                      Expanded(
                        child: _wheel(
                          itemCount: 60,
                          initialItem: _minute,
                          onChanged: (i) => _minute = i,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GlassActionButton(
                      onPressed: () => Navigator.pop(context),
                      label: L10n.cancel,
                    ),
                    GlassActionButton(
                      variant: GlassActionVariant.primary,
                      onPressed: () => Navigator.pop(
                          context, TimeOfDay(hour: _hour, minute: _minute)),
                      label: L10n.confirm,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 4: 月份选择器**

`showGlassMonthPicker` 同样加 `isScrollControlled: true`（与时间选择器一样的原因）。

`_GlassMonthPickerSheetState.build` 里包 `LayoutBuilder`，并把年份滚轮高度与月份格行高改成算出来的：

```dart
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 年份滚轮与月份格按弹层预算收缩；高屏上取到上限，
            // 因此竖屏结果与今天完全一致。
            final yearH = (constraints.maxHeight * 0.30).clamp(72.0, 120.0);
            final rowH = (constraints.maxHeight * 0.10).clamp(32.0, 40.0);
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L10n.jumpToMonth,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: yearH,
                    child: CupertinoPicker(
                      /* …以下与今天完全相同，不动… */
                    ),
                  ),
                  const SizedBox(height: 12),
                  Column(
                    children: List.generate(4, (r) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: List.generate(3, (c) {
                            /* …与今天相同，只把 Container 的 height: 40 换成 rowH… */
                          }),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        ),
      ),
```

**注意**：`CupertinoPicker` 与月份格内部的构造一字不改，只把外层 `SizedBox(height: 120)` 换成 `height: yearH`、把月份格 `Container` 的 `height: 40` 换成 `rowH`。

- [ ] **Step 5: 日期选择器**

它已经是 `isScrollControlled: true`。包一层 `LayoutBuilder`，把日期格高从 `height: 40` 改成 `(constraints.maxHeight * 0.10).clamp(32.0, 40.0)`，并把整个 `Column` 包进 `SingleChildScrollView`（里面没有滚轮，不存在手势争抢）：

```dart
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final rowH = (constraints.maxHeight * 0.10).clamp(32.0, 40.0);
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    /* …与今天相同，只把日期格的 height: 40 换成 rowH… */
                  ],
                ),
              ),
            );
          },
        ),
      ),
```

- [ ] **Step 6: `GlassDialog` 内容可滚**

`app/lib/core/widgets/glass_dialog.dart` 的 `content` 外面包一层：

```dart
            const SizedBox(height: 16),
            // 内容过高时滚动而不是溢出。上限用弹窗自己的预算减去标题行
            // 与按钮行 —— `Dialog` 的 insetPadding 已经由 LayoutBuilder 扣掉了。
            LayoutBuilder(
              builder: (context, constraints) => ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight - 100,
                ),
                child: SingleChildScrollView(child: content),
              ),
            ),
```

**注意**：`GlassDialog` 的 `Column` 是 `mainAxisSize: MainAxisSize.min`，里面没有 `Expanded`，`LayoutBuilder` 拿到的 `maxHeight` 是 `Dialog` 给的宽松上界。这样写能给出「内容最多占多少」的上限，但**不会**把本来矮的弹窗撑高 ✓。

- [ ] **Step 7: 跑测试**

Run:
```
../toolchain/flutter/bin/flutter.bat test test/glass_pickers_layout_test.dart
../toolchain/flutter/bin/flutter.bat test
```
Expected: 新测试 PASS；全量仍全绿（既有测试的视口是 900 高，各 `clamp` 都取到上限 = 今天的值，所以零回归）

- [ ] **Step 8: 提交**

```bash
git add app/lib/core/widgets/glass_pickers.dart app/lib/core/widgets/glass_dialog.dart app/test/glass_pickers_layout_test.dart
git commit -m "fix(ui): 三个选择弹层高度自适应，横屏与小窗不再溢出"
```

---

### Task 4: 日历 —— 格子高度双向约束

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart:439-460`（`_buildGrid` 的高度算式）
- Test: `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: 无（纯算式改动）
- Produces: `minCellH` 常量（`_CalendarScreenState` 私有）

- [ ] **Step 1: 写失败的测试**

在 `app/test/calendar_screen_test.dart` 末尾追加。**断言直接打在算式上，不去量 widget 树** —— `SingleChildScrollView` 的尺寸是它自己的**视口**（等于可用高度），不是内容高度，拿它判「网格变矮了」改不改都会通过，等于没测：

```dart
  test('横屏：格子高度不再只按宽度算', () {
    // 起因：`cellH = cellW / 0.78` 只按宽度算。横屏 cellW ≈ 125 → cellH ≈ 160，
    // 一个月六行要 960px，一屏只看得到一行多。
    const cellW = 125.0; // (900 − 24) / 7
    final landscape = calendarCellHeight(
      cellW: cellW,
      availHeight: 244, // 横屏扣掉顶栏与信息卡之后
      weekRows: 6,
      weekdayH: 26,
    );
    expect(landscape, lessThan(cellW / 0.78),
        reason: '横屏必须进入压缩分支，不能仍取按宽度算出来的 160');
    expect(landscape, greaterThanOrEqualTo(56),
        reason: '压缩不得低于可读下限，否则要裁字');
  });

  test('竖屏：格子高度与旧公式完全等价', () {
    // 竖屏空间富余，走的还是原来那条「拉高」分支 —— 逐像素不变。
    // fillCellH = (600−26)/5 = 114.8，超过 naturalCellH(72.6)，于是取
    // min(fillCellH, cellW/0.62) = 91.3 —— 与旧代码同一分支、同一算式。
    const cellW = 56.6; // (420 − 24) / 7
    final portrait = calendarCellHeight(
      cellW: cellW,
      availHeight: 600,
      weekRows: 5,
      weekdayH: 26,
    );
    expect(portrait, closeTo(cellW / 0.62, 0.01));
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `../toolchain/flutter/bin/flutter.bat test test/calendar_screen_test.dart`
Expected: 编译失败 —— `Method not found: 'calendarCellHeight'`

- [ ] **Step 3: 把算式抽成顶层纯函数并改成宽高共同决定**

`app/lib/features/calendar/calendar_screen.dart` 的 `_buildGrid` 里，把这一段：

```dart
        final cellW = (constraints.maxWidth - _hPad * 2) / 7;
        final naturalCellH = cellW / _aspect;
        final fillCellH = (availHeight - _weekdayH) / _weekRows;
        final cellH = fillCellH > naturalCellH
            ? math.min(fillCellH, cellW / _aspectMin)
            : naturalCellH;
```

替换为：

```dart
        final cellW = (constraints.maxWidth - _hPad * 2) / 7;
        final cellH = calendarCellHeight(
          cellW: cellW,
          availHeight: availHeight,
          weekRows: _weekRows,
          weekdayH: _weekdayH,
        );
```

并在文件**顶层**（`_CalendarScreenState` 类外，与其它顶层函数放一起）加：

```dart
// 格子高宽比：0.78 = 自然比例，0.62 = 「不许再高」的下限比例。
const double _cellAspect = 0.78;
const double _cellAspectMin = 0.62;

/// 格子高的下限：日期 18×1.15 + 班次 12×1.15 + 农历 11×1.15 + 两处间距
/// + 格子内缩 ≈ 56。再压就要裁字了。
const double _minCellH = 56;

/// 日历格子高度：**宽高共同决定**。
///
/// 抽成顶层纯函数是为了能直接断言「横屏进入压缩分支」——
/// `SingleChildScrollView` 的尺寸是视口不是内容，拿它测不出压缩。
///
/// 空间富余时拉高（但不超过 [_cellAspectMin] 那道「不许太瘦」的比例）；
/// 空间不足时**压缩到够用**，但不低于可读下限。
///
/// 原来空间不足时直接取 `cellW / _cellAspect`（只按宽度算），于是横屏下
/// `cellW` 大 → 格子高 160 → 一个月六行要 960px，一屏只看得到一行多。
/// 那道「不许太瘦」的下限只在富余时生效、不足时反而没有任何压缩通道，
/// 逻辑正好反了。
double calendarCellHeight({
  required double cellW,
  required double availHeight,
  required int weekRows,
  required double weekdayH,
}) {
  final naturalCellH = cellW / _cellAspect;
  final fillCellH = (availHeight - weekdayH) / weekRows;
  return fillCellH >= naturalCellH
      ? math.min(fillCellH, cellW / _cellAspectMin)
      : math.max(fillCellH, _minCellH);
}
```

并把类里原来的 `_aspect` / `_aspectMin` 常量删掉（已移到顶层；`_aspect` 在 `_selectedRect` 等处没有别的引用，只有 `_buildGrid` 用）。

**竖屏等价性**：竖屏 `availHeight` 大（600+），`fillCellH` 远大于 `naturalCellH` → 走富余分支 `min(fillCellH, cellW/0.62)`，与旧代码同一分支、同一算式 ✓。

- [ ] **Step 4: 跑测试**

Run:
```
../toolchain/flutter/bin/flutter.bat test test/calendar_screen_test.dart
../toolchain/flutter/bin/flutter.bat test
```
Expected: 新测试 PASS；既有日历测试全绿（它们用 420/640 宽 + 1600 高，走的还是富余分支）

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/test/calendar_screen_test.dart
git commit -m "fix(calendar): 格子高度改为宽高共同决定，横屏不再一屏一行"
```

---

### Task 5: 日历宽屏左右分栏 + 导航胶囊短屏收紧

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`（`build` 与 `_infoCard`）
- Modify: `app/lib/features/home/home_shell.dart`（`_GlassNavBar`）
- Test: `app/test/calendar_screen_test.dart`

**Interfaces:**
- Consumes: `AppLayout.of`（Task 1）
- Produces: `_infoCard(BuildContext, ShiftSchedule?, {bool inSidePane})`

- [ ] **Step 1: 给测试助手加高度参数，并写失败的测试**

`app/test/calendar_screen_test.dart` 的 `_pumpCalendar` 目前只有 `width`，把它改成也能给高度（这一版的短屏用例都要用）：

```dart
Future<AppDatabase> _pumpCalendar(WidgetTester tester, String templateId,
    {double width = 420, double height = 1600}) async {
  final template = _template(templateId);

  tester.view.physicalSize = Size(width, height);
```

在文件末尾追加：

```dart
  testWidgets('宽屏：日历改左右分栏，信息卡在右不在下', (tester) async {
    await _pumpCalendar(tester, 'four_crew_three_shift', width: 1280);

    // 用信息卡自己的日期文本定位。不要用 L10n.today —— 「今天」在顶栏
    // 按钮和信息卡的「今天」徽章各出现一次，find.text 会一次命中两个。
    final cardDate =
        find.text(L10n.monthDayWeekday(dateOnly(DateTime.now())));
    expect(tester.getTopLeft(cardDate).dx, greaterThan(640),
        reason: '宽屏下信息卡应当被排在右栏，而不是底栏');
  });

  testWidgets('竖屏：仍是单栏，信息卡在下方', (tester) async {
    await _pumpCalendar(tester, 'four_crew_three_shift');
    final cardDate =
        find.text(L10n.monthDayWeekday(dateOnly(DateTime.now())));
    expect(tester.getTopLeft(cardDate).dx, lessThan(420));
    expect(tester.getTopLeft(cardDate).dy, greaterThan(600),
        reason: '竖屏下信息卡在底部区域');
  });

  testWidgets('短屏：信息卡压成紧凑版，把高度让给网格', (tester) async {
    await _pumpCalendar(tester, 'four_crew_three_shift',
        width: 420, height: 420);
    final cardDate =
        find.text(L10n.monthDayWeekday(dateOnly(DateTime.now())));
    expect(tester.getSize(find.byType(GlassTile).last).height, lessThan(90),
        reason: '短屏下信息卡应当比竖屏的约 110 矮');
  });

  testWidgets('窄屏：顶栏「今天」收成纯图标钮', (tester) async {
    await _pumpCalendar(tester, 'four_crew_three_shift', width: 320);
    expect(find.text(L10n.today), findsNothing,
        reason: '320 宽下「今天」两个字应当收起来，把宽度让给年月');
    expect(find.byIcon(Icons.today_outlined), findsWidgets);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `../toolchain/flutter/bin/flutter.bat test test/calendar_screen_test.dart`
Expected: 四条里至少「宽屏分栏」「短屏紧凑」「窄屏收图标」三条 FAIL

- [ ] **Step 3: 日历改分栏**

`app/lib/features/calendar/calendar_screen.dart` 的 `build` 里，把网格区与信息卡改成按 `isWide` 二选一：

```dart
    final layout = AppLayout.of(context);
    final gridArea = Expanded(
      child: LayoutBuilder(
        builder: (context, c) => scheduleAsync.isLoading && schedule == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: _buildGrid(context, schedule, c.maxHeight),
              ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            // 宽屏左右分栏：网格与信息卡并排，网格拿到的可用高度从
            // 「减去底部信息卡」变成「整屏高度」，格子不用再被压扁。
            if (layout.isWide)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    gridArea,
                    const SizedBox(width: AppTokens.spaceMd),
                    SizedBox(
                      width: 300,
                      child: SingleChildScrollView(
                        child: _infoCard(context, schedule, inSidePane: true),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              gridArea,
              _infoCard(context, schedule,
                  compact: layout.isShort),
            ],
          ],
        ),
      ),
    );
```

顶部补 import：`import '../../core/layout.dart';`

- [ ] **Step 4: 信息卡按栏位与短屏变**

`_infoCard` 签名与首行内边距：

```dart
  Widget _infoCard(BuildContext context, ShiftSchedule? schedule,
      {bool inSidePane = false, bool compact = false}) {
    // …前面的 muted / accent 计算不变…

    return Padding(
      // 底栏时要给悬浮胶囊让出高度（竖屏 120，短屏 76）；右栏时胶囊在
      // 屏幕底部、与这一栏无关，只需要常规留白。
      padding: inSidePane
          ? const EdgeInsets.fromLTRB(0, 8, 16, 16)
          : EdgeInsets.fromLTRB(16, 8, 16, compact ? 76 : 120),
      child: Stack(
        children: [
          GlassTile(
            padding: EdgeInsets.fromLTRB(
                22, compact ? 10 : 18, 18, compact ? 10 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /* …其余内容不变… */
```

短屏时同时把卡片内的固定间距收一档：`SizedBox(height: 6)` → `SizedBox(height: compact ? 2 : 6)`、`SizedBox(height: 12)` → `SizedBox(height: compact ? 6 : 12)`、`SizedBox(height: 8)` → `SizedBox(height: compact ? 4 : 8)`（`_infoCard` 内各处）。

- [ ] **Step 5: 窄屏顶栏收起「今天」文字**

`_header` 里那个 accent 胶囊，把图标 + 文字改成窄屏只留图标：

```dart
          _glassPill(
            context,
            onTap: _today,
            accent: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.today_outlined, size: 18, color: Colors.white),
                // 320 宽下「今天」两个字会挤掉年月的显示宽度，窄屏只留图标。
                if (!AppLayout.of(context).isNarrow) ...[
                  const SizedBox(width: 4),
                  Text(
                    L10n.today,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.98),
                    ),
                  ),
                ],
              ],
            ),
          ),
```

- [ ] **Step 6: 导航胶囊短屏收紧**

`app/lib/features/home/home_shell.dart` 的 `_GlassNavBarState`：

```dart
  static const _outerPad = 24.0;
  static const _innerPad = 6.0;
  static const _capsuleHeight = 64.0;

  /// 短屏（< 480 高）用的紧凑尺寸：横屏下 64 高的胶囊约占可用高度的
  /// 六分之一，且它悬浮在内容之上，太占地方。
  static const _capsuleHeightShort = 52.0;
  static const _outerPadShort = 16.0;
```

`build` 里取：

```dart
    final isShort = AppLayout.of(context).isShort;
    final capsuleH = isShort ? _capsuleHeightShort : _capsuleHeight;
    final outerPad = isShort ? _outerPadShort : _outerPad;
```

并把该方法内所有 `_capsuleHeight` 换成 `capsuleH`、`_outerPad` 换成 `outerPad`、图标 `size: 22` 换成 `size: isShort ? 20 : 22`。

顶部补 import：

```dart
import '../../core/layout.dart';
```

- [ ] **Step 7: 短屏收紧编辑器的底部留白**

日历信息卡的底部留白已在 Step 4 一并处理（`compact ? 76 : 120`），这里只剩编辑器。

`schedule_editor_screen.dart` 的 `ListView` padding（约 239 行）：

```dart
                  padding: EdgeInsets.fromLTRB(
                      AppTokens.spaceLg,
                      AppTokens.spaceSm,
                      AppTokens.spaceLg,
                      AppLayout.of(context).isShort ? 56 : 100),
```

顶部补 import：`import '../../core/layout.dart';`

- [ ] **Step 8: 跑测试与出图**

Run:
```
../toolchain/flutter/bin/flutter.bat test
../toolchain/flutter/bin/flutter.bat test tool/visual/render_screens_test.dart
```
Expected: 测试全绿；出图**日历在横屏与小窗变体下不再溢出**（其他屏可能还有溢出，留给 Task 6）

- [ ] **Step 9: 提交**

```bash
git add app/lib/features/calendar/calendar_screen.dart app/lib/features/home/home_shell.dart app/lib/features/calendar/schedule_editor_screen.dart app/test/calendar_screen_test.dart
git commit -m "feat(calendar): 宽屏左右分栏；短屏收紧导航胶囊与各页底部留白"
```

---

### Task 6: 宽屏内容限宽 + 紧凑档

**Files:**
- Modify: `app/lib/core/widgets/glass_pressable.dart` 所在目录新建 `app/lib/core/widgets/centered_content.dart`
- Modify: 七个界面文件（四个 tab 页 + 编辑器 + 模板页 + 管理页）
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`（紧凑档）

**Interfaces:**
- Consumes: `AppLayout.of`（Task 1）
- Produces: `CenteredContent({required Widget child})`

- [ ] **Step 1: 写失败的测试**

创建 `app/test/centered_content_test.dart`：

```dart
// app/test/centered_content_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/layout.dart';
import 'package:shiftassistantpro/core/widgets/centered_content.dart';

void main() {
  testWidgets('宽屏：内容限宽居中', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: CenteredContent(child: SizedBox(height: 100, child: Text('x'))),
      ),
    ));

    expect(tester.getSize(find.text('x')).width,
        lessThanOrEqualTo(AppLayout.maxContentWidth));
    // 居中：左右留白相等
    final left = tester.getTopLeft(find.text('x')).dx;
    final right = 1280 - tester.getTopRight(find.text('x')).dx;
    expect((left - right).abs(), lessThan(1));
  });

  testWidgets('窄屏：不介入，内容仍然拉满', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: CenteredContent(child: SizedBox(height: 100, child: Text('x'))),
      ),
    ));

    expect(tester.getSize(find.text('x')).width, 420);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `../toolchain/flutter/bin/flutter.bat test test/centered_content_test.dart`
Expected: 编译失败 —— `Target of URI doesn't exist: '…/centered_content.dart'`

- [ ] **Step 3: 写组件**

创建 `app/lib/core/widgets/centered_content.dart`：

```dart
import 'package:flutter/material.dart';

import '../layout.dart';

/// 宽屏下把内容限宽并居中，窄屏原样透传。
///
/// 表单在 1280 宽的车机上拉满整屏会难以阅读：「标签在左、值在右」的行
/// 两端离得太远，眼睛要在一条长线上来回找。限宽居中是宽屏表单的通行做法，
/// 也是这一版为车机做的性价比最高的一处改动。
///
/// **窄屏下必须是零介入**（直接返回 child，不套任何额外的盒子），
/// 否则会在竖屏上多出一层约束，把「逐像素不变」破坏掉。
class CenteredContent extends StatelessWidget {
  const CenteredContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AppLayout.of(context).isWide) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
        child: child,
      ),
    );
  }
}
```

- [ ] **Step 4: 套到各页**

规则两条，别弄错顺序：

1. 包**滚动容器**，不是整个 `body` —— 包住 `Scaffold` 的 FAB / 底部按钮条只会徒增麻烦。
2. 页面若已有 `SafeArea`，`CenteredContent` 要套在**它里面**。套在外面的话，横屏带刘海时安全区会按 720 的盒子算而不是按屏幕算，内容可能钻到刘海底下。

逐处：

| 文件 | 现在 | 改成 |
|---|---|---|
| `features/calendar/schedule_editor_screen.dart` | `body: _notFound ? … : !_loaded ? … : ListView(…)` | `body: CenteredContent(child: <原三元表达式整体>)` |
| `features/calendar/shift_template_picker_screen.dart` | `body: ListView(` | `body: CenteredContent(child: ListView(` |
| `features/calendar/schedule_management_screen.dart` | `body: async.isLoading && schedules.isEmpty ? … : ListView(` | `body: CenteredContent(child: <原三元表达式整体>)` |
| `features/alarm/alarm_screen.dart` | `body: SafeArea(child: Column(` | `body: SafeArea(child: CenteredContent(child: Column(` |
| `features/schedule/schedule_screen.dart` | `body: SafeArea(child: Column(` | `body: SafeArea(child: CenteredContent(child: Column(` |
| `features/profile/profile_screen.dart` | `body: SafeArea(child: ListView(` | `body: SafeArea(child: CenteredContent(child: ListView(` |

每个文件补 import：`import '../../core/widgets/centered_content.dart';`

**日历除外** —— 它已由 Task 5 的分栏处理，再套限宽会把分栏挤回中间一条。

- [ ] **Step 5: 编辑器窄屏紧凑档**

`schedule_editor_screen.dart`：`isNarrow` 时把各卡片的内边距从 `spaceLg(16)` 收到 `spaceMd(12)`。在 `_classesCard` / `_cycleCard` / `_crewCard` / `_followHolidayCard` / `_headerCard` 里，把 `padding: const EdgeInsets.all(AppTokens.spaceLg)` 换成：

```dart
      padding: EdgeInsets.all(AppLayout.of(context).isNarrow
          ? AppTokens.spaceMd
          : AppTokens.spaceLg),
```

**字号一律不缩** —— 窄屏本来就更需要可读性。

- [ ] **Step 6: 跑测试、分析与出图**

Run:
```
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat test
../toolchain/flutter/bin/flutter.bat test tool/visual/render_screens_test.dart
```
Expected: 0 error / 0 warning；测试全绿；**出图在 15 个变体（5 变体 × 7 屏）下零溢出**

- [ ] **Step 7: 逐张看横屏与小窗的图**

看 `app/build/visual/*_landscape.png` 与 `*_small.png` 共 14 张。重点：
- 日历分栏后信息卡的内容没有被裁
- 编辑器周期行的 chip 与「第 N 天」在窄屏下没被挤坏
- 模板页的卡片标题换行正常
- 四个 tab 页没有元素贴边或被胶囊压住

- [ ] **Step 8: 提交**

```bash
git add app/lib/core/widgets/centered_content.dart app/lib/features/ app/test/centered_content_test.dart
git commit -m "feat(ui): 宽屏内容限宽居中，编辑器窄屏收紧内边距"
```

---

### Task 7: 版本号与更新日志

**Files:**
- Modify: `app/pubspec.yaml:4`
- Modify: `app/lib/core/app_info.dart:2`
- Modify: `app/lib/features/profile/app_dialogs.dart`

- [ ] **Step 1: 改版本号**

`app/pubspec.yaml`：`version: 0.6.3+74` → `version: 0.6.4+75`
`app/lib/core/app_info.dart`：`'0.6.3'` → `'0.6.4'`

- [ ] **Step 2: prepend 更新日志**

在 `_changelogZh` 的 `'v0.6.3\n'` 之前插入：

```dart
const String _changelogZh = 'v0.6.4\n'
    '· 适配手机横屏与小窗：时间 / 日期 / 月份三个选择弹层此前在横屏下会溢出，现在按可用高度自适应\n'
    '· 日历在横屏 / 宽屏下改为左右分栏：左边日期网格、右边当天信息，格子不再被压成一屏只看得到一行\n'
    '· 悬浮导航胶囊在矮屏下自动收紧，各页底部留白同步收窄\n'
    '· 平板与车机等宽屏设备：内容限宽居中，不再横向拉满整屏\n'
    '· 窄屏下编辑器卡片内边距收紧，字号不缩\n\n'
    'v0.6.3\n'
```

在 `_changelogEn` 的 `'v0.6.3\n'` 之前插入：

```dart
const String _changelogEn = 'v0.6.4\n'
    '· Phone landscape and small windows are now usable: the time, date and month picker sheets adapt to the available height instead of overflowing\n'
    '· On wide or landscape screens the calendar becomes two panes — month grid on the left, day details on the right — so day cells are no longer squashed\n'
    '· The floating nav capsule shrinks on short screens, and pages no longer reserve as much space beneath it\n'
    '· On tablets and car head units the content is centred with a maximum width instead of stretching across the screen\n'
    '· Narrow screens get tighter editor paddings (text sizes are unchanged)\n\n'
    'v0.6.3\n'
```

- [ ] **Step 3: 删最旧一条，保持 10 条**

删掉两个常量末尾 `'v0.4.5\n'` 那一条（从中英各自的 v0.4.5 起始标记到该常量的收尾分号，删完最后一条是 `v0.4.6`，以 `\n\n';` 收尾）。

- [ ] **Step 4: 验证条数**

```bash
cd app
grep -c "^    'v0\." lib/features/profile/app_dialogs.dart
```

Expected: `18`（两个常量各 9 行；每个常量的第一条写在声明行上，不被计入 —— 对应各 10 条）。

- [ ] **Step 5: 全量验收**

Run:
```
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat test
```
Expected: 0 error / 0 warning；全绿

- [ ] **Step 6: 提交**

```bash
git add app/pubspec.yaml app/lib/core/app_info.dart app/lib/features/profile/app_dialogs.dart
git commit -m "chore(release): v0.6.4 版本号与更新日志"
```

---

### Task 8: 构建与发布

**Files:**
- 产出：`app/build/visual/*.png`、`dist/倒班助手Pro-v0.6.4.apk`（均 gitignore）

- [ ] **Step 1: 最终出图与看图**

```bash
cd app
../toolchain/flutter/bin/flutter.bat test tool/visual/render_screens_test.dart
```

确认 **15 张全部渲染通过、零溢出**；再抽查 14 张横屏/小窗图（Task 6 已逐张看过，这里确认最终状态）。

- [ ] **Step 2: 全量验收**

```bash
../toolchain/flutter/bin/flutter.bat analyze
../toolchain/flutter/bin/flutter.bat test
```

- [ ] **Step 3: 构建 APK**

先加载构建环境（**PowerShell**）：

```powershell
. C:\Users\Alec\Documents\DeepSeekHermesData\shiftassistant\tools\build-env.ps1
```

再：

```bash
cd app
../toolchain/flutter/bin/flutter.bat build apk --release --target-platform android-arm64
```

- [ ] **Step 4: 校验并分发**

```bash
cp app/build/app/outputs/flutter-apk/app-release.apk "dist/倒班助手Pro-v0.6.4.apk"
toolchain/android-sdk/build-tools/36.0.0/aapt2 dump badging "dist/倒班助手Pro-v0.6.4.apk" | head -1
```

Expected: 同时含 `com.daoban.shiftassistantpro`、`versionCode='75'`、`versionName='0.6.4'`。

- [ ] **Step 5: 写发布说明**

写到 `tools/gh/release-notes-v0.6.4.md`，结构照 `release-notes-v0.6.3.md`（`## 标题` / `### 本次更新` / `### 说明` / `### 构建信息`），末尾附 APK 大小、对应源码提交与 SHA256（`sha256sum dist/倒班助手Pro-v0.6.4.apk`）。

**说明段里要写清楚**：本版是横屏/小窗适配，用户此前反馈「这两种状态下几乎无法使用」；同时说明车机（自行安装 APK）的横屏大屏是同一套分档覆盖的。

- [ ] **Step 6: 提交、打标签、推送**

```bash
git add -A
git commit -m "chore(release): 更新发布清单至 v0.6.4"
git tag v0.6.4
git push origin main
git push origin v0.6.4
```

- [ ] **Step 7: 发布到 GitHub Release**

```bash
scripts/release.ps1 -SkipConfirm
```

**这次有个额外的发布动作**：v0.6.4 是这一轮的收尾，0.6.1 反馈的四项至此全部落地。发布说明里可以提一句「本轮四项反馈已全部处理」，但**不要**写成「最终版/稳定版」——是否升 `X.Y` 由用户决定。

**这一步是本计划唯一的真机入口**：本环境没有 Android 设备，所有 GUI 行为都没有被任何 agent 实际看过。工装的横屏/小窗出图与「溢出即失败」能兜住布局层面的问题，但**触控手感、横滑是否顺手、真机旋转时的重建行为**都只能由用户确认 —— 发布说明与最终报告里都要如实写明。

---

## 验收清单（对 spec §6）

- [ ] `flutter analyze` 0 error / 0 warning
- [ ] `flutter test` 全绿
- [x] `flutter test tool/visual/render_screens_test.dart` 在 5 变体 × 7 屏下零溢出（41 张全过）—— Task 2 建工具、Task 3~6 逐个消掉溢出
- [x] `AppLayout.of` 在五组尺寸下判定正确 —— Task 1
- [x] 日历格子高度：横屏进入压缩分支、竖屏与旧公式等价 —— Task 4
- [x] 弹层高度：横屏与小窗不溢出、高屏仍取今天的值 —— Task 3
- [x] 竖屏三个变体的产出图与 v0.6.3 一致（人工抽查）
- [ ] **手工验收（待用户）**：真机横屏开日历/编辑器/三个选择器；小窗下滑完整月、走一遍新建排班全流程。
      本环境无 Android 设备，GUI 未经 agent 实际运行验证 —— 触控手感、横滑是否顺手、真机旋转时的重建行为都只能由用户确认。

---

## 执行记录（与计划的偏差）

| # | 情况 | 处理 |
|---|---|---|
| 1 | **工装的 `failOnOverflow` 把信号变成了噪音**：它在错误回调里当场 `fail()`，异常抛进帧管线后 flutter_test 处理不了 —— 症状是一条用例卡到 45 秒超时、其余全部连锁失败，一轮只看得到第一条溢出 | 改成收集到 `addTearDown` 里统一报。改完立刻从「37 条失败」收敛成「2 条真实失败 + 39 条通过」，一轮就能看到全部靶子 |
| 2 | **spec 的「内容限高 85%」修不掉溢出**：时间与月份选择器都没开 `isScrollControlled`，`showModalBottomSheet` 默认把弹层压到屏幕的 9/16 —— 横屏 420 高只有 236px，而内容要 340px。**这才是主因**，不是内容本身高 | 三处都补 `isScrollControlled: true`，内容再用 `LayoutBuilder` 拿弹层自己的真实预算收缩 |
| 3 | **spec 的 `bottomInset` 公式会改掉竖屏**：公式算出来 76，而日历今天用的是 120（差的 44 是刻意的视觉呼吸余地，不是由胶囊尺寸推导的） | 不做统一公式，只在 `isShort` 时收紧；竖屏原样保留 |
| 4 | **格子下限估算不对**：按字形算是 56，实测（测试字体每字占满一个字身）内容要 75px 才不溢出；而且窄屏上「按宽度算的上限」也卡着它 | 下限提到 80；窄/短屏把 `aspectMin` 放宽到 0.46。两处都只走压缩分支，竖屏走的是「拉高」分支，不受影响 |
| 5 | **`_minCellH` 一次没调够**：先提到 68 仍溢出 11px，才算出真实需求 | 见上条 |
| 6 | **短屏信息卡一开始只收了间距**，出图后发现网格仍被挤成一条缝（360×360 里信息卡约 340 高） | 改成 spec 说的真正单行版（哪天 · 什么班 · 几点到几点 + 闹钟图标），并清掉完整卡里因此变成死代码的 `compact ? a : b` |
| 7 | **300 宽的侧栏把信息卡的「班次名 + 时间」行挤溢出**（宽屏用例报 7.8px） | 班次名与时间都改 `Flexible` + 省略号，栏再窄也不溢出 |
| 8 | **包裹脚本踩了两次括号计数 bug**：三元表达式没有外层括号，从 depth=1 数下去会把 Scaffold 的收尾也吞进去 | 最终只用 `: ListView(` 锚点 + 从 `(` 配平，另外三处（`SafeArea` 的 child 是单个构造调用）用原办法是对的 |
| 9 | **发布后我又想改一处**（编辑器的保存按钮也该跟着限宽，否则宽屏上正文居中 720、按钮却横贯整屏） | **撤回**：0.6.4 已发布、tag 已推，让主干与已发布的 APK 不一致是不对的，而重写已推的 tag 风险更大。记在这里，下个版本做 |

