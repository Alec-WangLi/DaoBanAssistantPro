# 班次颜色扩展与自定义取色 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 班次可选颜色从 8 颗扩到 16 颗，并新增一个能自己取色的面（色相条 + 饱和度/明度方盘 + 十六进制输入），且**那 16 颗在 App 的日历格子上与桌面小组件上都保证看得清**。

**Architecture:** 把「盘」与「它要过的那条线」从编辑器里搬出来成为两个纯文件（一个放数据与算式、一个放十六进制解析），再把取色那一层做成一个独立的弹层组件，编辑器只负责把当前色传进去、把结果写回。桌面小组件那侧**一个字都不改**（它只认一个 int 色号）。

**Tech Stack:** Flutter / Riverpod / Drift。盘与算式是纯 Dart，可直接单测；取色层走 widget 测试与视觉工装。

**Spec:** `docs/superpowers/specs/2026-10-11-shift-color-custom-design.md`（**本文所有取值以它为准**；§4 那四处卡底与 1.34906 那条线、§3 那 16 个色号、§8 那两条已拍板，都是它定的）

## Global Constraints

- **版本号**：`app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` 必须同步（`app/test/app_info_test.dart` 盯着）。本轮是**测试版**：`0.11.5+152` → `0.11.6+153`。**`X.Y` 不许动**。
- **分支**：测试版一律在 `beta` 上做、提交、发布（`main` 只在发正式版时收合并）。
- **验收**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿；`flutter test tool/visual/` 全绿。用例数**只增不减**（动工前先跑一遍记下真实数字，别抄旧的）。
- **界面层不许写数值字面量**（`app/test/design_tokens_test.dart` 守门）：字号 / 字重 / `Color(0x…)` / `Circular(<n>)` / `Duration(milliseconds:)` / `Icon(size:)` / 非 4px 栅格的间距常量。**盘色与卡底一律存 `int`**（不是 `Color(0x…)`），界面要用时 `Color(intValue)` —— 这样既躲开守门、又让纯函数用例读得到。文案一律走 `L10n`。
- **除 `core/haptics.dart` 外，任何文件不许出现 `HapticFeedback.`**。这一版**不发触觉**（规格 §5 末尾明写了：点预设、拖方盘都不震）—— 别顺手加。
- **不改 Drift 表** → 不需要 `dart run build_runner build`。
- **不要跑 `dart format`**（本仓工具链的格式化器会重排整个文件）。只跑 `flutter analyze`。
- 构建环境：`source tools/build-env.sh`，然后用 `"$FLUTTER_ROOT/bin/flutter"`（`flutter` 不在 PATH 上）。
- **门槛的精确值 `1.3501`**（权威值是实现算出来的 **1.35018838**；不是 1.35，也不是更早那两稿的 1.3947 / 1.34906 —— 前者只算了 App 两处卡底，后者是拿浮点混合算的、没按 8 位通道取整。见账本 Task 1 的 Ruling）。

## Review Focus

以下五类是这次改动隐含、而**任何单一任务的测试都不会自动覆盖**的：

1. **十六进制输入框的各种写法** —— 粘进来带空格、大写、少个 `#`、三位缩写、混进非法字符。期望：合法的照收并**当下**更新预览与日历小样；非法的**不改任何状态**、输入框转警示色，点「确定」用的仍是上一次的有效色。
2. **小窗 200×400 + 软件键盘弹起** —— 那个输入框一聚焦就会把可用高吃掉一大截。期望：整层能滚、方盘缩到装得下、**「确定」仍然点得到**（v0.7.3 那个坑的同一类：按钮画在屏幕上、可已经不在可点区域里）。
3. **当前色不在盘里的那 16 颗之内** —— `0xFF5B7FFF` 是域 / 库 / 模板三处的默认色，**任何一版盘都没有它**。期望：打开取色层一颗都不高亮、预览圆点如实显示当前色；什么都不动点「确定」，颜色**不变**。
4. **灰阶**（`#9AA0B4` / `#5A5F73`，饱和度极低）—— 色相在这种颜色上接近于「没有定义」，round-trip 本身有损。期望：打开不崩、拖色相条或方盘**当下就有反应**（判据不是「往返回来还是同一个色」，那做不到）。
5. **归档之外的那条线是算出来的，眼睛还没看过** —— 挑一颗新加的深色（比如 `#2E7D32` 深绿、`#795548` 棕）落到日历格子上，出图确认那颗胶囊真的看得见、字也读得出。

---

### Task 1: 盘与那条线（`core/shift_palette.dart`）

**Files:**
- Create: `app/lib/core/shift_palette.dart`
- Test: `app/test/shift_palette_test.dart`

**Interfaces:**
- Produces:
  - `const List<int> kShiftPalette`（**16** 颗，顺序即规格 §3 的表；**第一颗必须是 `0xFF4C8DFF`**，见 Task 5）
  - `const double kShiftChipTintAlpha = 0.14;`、`const double kShiftChipStrokeAlpha = 0.45;`
  - `const List<int> kShiftCardSurfaces`（**4** 处卡底，顺序见下）
  - `const double kShiftColorBar = 1.3501;`（下界是 1.35018838，常量取它下面一点）
  - `int compoundOver(int argb, int cardArgb, double alpha)` —— 把 `argb` 按 `alpha` 压在 `cardArgb` 上，返回不透明结果
  - `double shiftChipStrokeContrast(int argb, int cardArgb)` —— `contrastRatio(compoundOver(argb, cardArgb, kShiftChipStrokeAlpha), cardArgb)`

**四处卡底**（存 `int`；来源与推导写在文件的文档注释里）：

```dart
const int kShiftCardAppLight    = 0xFFFFFFFF; // 页面 #F5F6FA 上压 92% 白卡
const int kShiftCardAppDark     = 0xFF16161E; // AppTokens.surfaceDark
const int kShiftCardWidgetLight = 0xFFF5F5F5; // wg_card_to_light(96% 白) 压纯黑壁纸 —— 它最暗的一档
const int kShiftCardWidgetDark  = 0xFF24242B; // wg_card_to_dark(94% #16161E) 压纯白壁纸 —— 它最亮的一档
const List<int> kShiftCardSurfaces = <int>[
  kShiftCardAppLight, kShiftCardAppDark, kShiftCardWidgetLight, kShiftCardWidgetDark,
];
```

- [ ] **Step 1: 写失败的用例**

新建 `app/test/shift_palette_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/shift_palette.dart';

void main() {
  test('盘是 16 颗、互不相同、第一颗是白班蓝', () {
    expect(kShiftPalette, hasLength(16));
    expect(kShiftPalette.toSet(), hasLength(16), reason: '不许有重复色');
    expect(kShiftPalette.first, 0xFF4C8DFF,
        reason: '新建班次是循环取色的，顺序一动就换色（Task 5 钉着它）');
  });

  test('原班底那八颗一颗都没动（内置模板烘着其中 7 个）', () {
    const old = <int>[0xFF4C8DFF, 0xFF7A5CFF, 0xFF9AA0B4, 0xFF5A5F73,
                      0xFF34C759, 0xFFFF9F0A, 0xFFFF375F, 0xFF00C7BE];
    for (final c in old) {
      expect(kShiftPalette, contains(c));
    }
    expect(kShiftPalette.take(8).toList(), old, reason: '前八颗就是原来那八个，顺序也别动');
  });

  test('16 颗 × 4 处卡底：描边对卡底全部过线', () {
    for (final c in kShiftPalette) {
      for (final card in kShiftCardSurfaces) {
        final v = shiftChipStrokeContrast(c, card);
        expect(v, greaterThanOrEqualTo(kShiftColorBar),
            reason: '#${c.toRadixString(16)} 压在 #${card.toRadixString(16)} 上只有 $v');
      }
    }
  });

  test('那条线就是现有八个在四处卡底上的下界', () {
    // 定的那颗是 #FF9F0A，压在最暗的那处小组件卡上。**这条不是凑数**：
    // 谁改了卡底常量、或动了现有某颗色，这个数就会漂 —— 让它当场红，而不是
    // 悄悄把门槛放宽（门槛是「不比现在差」，漂了就失去意义）。
    expect(shiftChipStrokeContrast(0xFFFF9F0A, kShiftCardWidgetLight),
        closeTo(1.350188, 0.00001));
    var worst = 99.0;
    for (final c in kShiftPalette.take(8)) {
      for (final card in kShiftCardSurfaces) {
        final v = shiftChipStrokeContrast(c, card);
        if (v < worst) worst = v;
      }
    }
    expect(kShiftColorBar, closeTo(worst, 0.0005),
        reason: '门槛必须等于「现有八个的下界」，不能是一个更大的手写数');
  });

  test('合成算式的边界：α=1 就是原色、α=0 就是卡底', () {
    expect(compoundOver(0xFF123456, 0xFFFFFFFF, 1.0), 0xFF123456);
    expect(compoundOver(0xFF123456, 0xFFFFFFFF, 0.0), 0xFFFFFFFF);
    expect(compoundOver(0xFF000000, 0xFFFFFFFF, 0.5), 0xFF808080);
  });
}
```

- [ ] **Step 2: 跑它，确认它失败**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/shift_palette_test.dart`
Expected: FAIL —— `Couldn't resolve the package 'shiftassistantpro/core/shift_palette.dart'`。

- [ ] **Step 3: 实现 `app/lib/core/shift_palette.dart`**

`compoundOver` 的算式（按位做，别用 `Color.lerp` —— 那个会把 alpha 也插值，不等于「压在底上」）：

```dart
int compoundOver(int argb, int cardArgb, double alpha) {
  int mix(int shift) {
    final f = (argb >> shift) & 0xFF;
    final b = (cardArgb >> shift) & 0xFF;
    return (alpha * f + (1 - alpha) * b).round().clamp(0, 255);
  }
  return 0xFF000000 | (mix(16) << 16) | (mix(8) << 8) | mix(0);
}
```

`shiftChipStrokeContrast` 走现成的 `AppTokens.contrastRatio`（`core/design_tokens.dart:555`），别手搓一份 WCAG：

```dart
double shiftChipStrokeContrast(int argb, int cardArgb) =>
    AppTokens.contrastRatio(
      Color(compoundOver(argb, cardArgb, kShiftChipStrokeAlpha)),
      Color(cardArgb),
    );
```

文件头写清楚三件事：**为什么盘要搬出编辑器**（这一版的主要护栏是纯函数，读不到 private static）、**为什么卡底存 `int`**（令牌守门不许 `Color(0x…)` 字面量）、**那四处卡底是怎么来的**（含 `widget_colors.xml` 那两个极端壁纸的推导）。

- [ ] **Step 4: 跑它，确认通过**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/shift_palette_test.dart`
Expected: PASS（5/5）。

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/shift_palette.dart app/test/shift_palette_test.dart
git commit -m "feat(color): 16 颗班次预设与「四处卡底」的可读性门槛"
```

---

### Task 2: 十六进制解析（`core/hex_color.dart`）

**Files:**
- Create: `app/lib/core/hex_color.dart`
- Test: `app/test/hex_color_test.dart`

**Interfaces:**
- Produces:
  - `int? parseHexColor(String input)` —— 收 `#RRGGBB` / `RRGGBB` / `#RGB` / `RGB`（大小写都收、前后空白容忍）；**一律补成不透明的 `0xFF……`**；非法返回 `null`（**不抛异常、不进位**）
  - `String formatHexColor(int argb)` —— `#RRGGBB`（大写，丢掉 alpha）

- [ ] **Step 1: 写失败的用例**

新建 `app/test/hex_color_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/hex_color.dart';

void main() {
  test('六位：带不带 #、大写小写都收', () {
    expect(parseHexColor('#4C8DFF'), 0xFF4C8DFF);
    expect(parseHexColor('4C8DFF'), 0xFF4C8DFF);
    expect(parseHexColor('  4c8dff  '), 0xFF4C8DFF);
    expect(parseHexColor('#000000'), 0xFF000000, reason: '全黑是合法的，且**不是** 0');
    expect(parseHexColor('#FFFFFF'), 0xFFFFFFFF);
  });

  test('三位缩写：每一位翻倍', () {
    expect(parseHexColor('#ABC'), 0xFFAABBCC);
    expect(parseHexColor('f0a'), 0xFFFF00AA);
  });

  test('非法输入一律 null，不抛异常', () {
    for (final bad in <String>['', '   ', '#', '#12', '#12345', '#1234567',
                               '#GGGGGG', 'ff00zz', '#12 34 56', '红色']) {
      expect(parseHexColor(bad), isNull, reason: '「$bad」应当被判非法');
    }
  });

  test('带 alpha 的八位不收（这一版自定义色一律不透明）', () {
    expect(parseHexColor('#804C8DFF'), isNull);
    expect(parseHexColor('804C8DFF'), isNull);
  });

  test('格式化：丢掉 alpha、补足六位、大写', () {
    expect(formatHexColor(0xFF4C8DFF), '#4C8DFF');
    expect(formatHexColor(0x004C8DFF), '#4C8DFF', reason: 'alpha 不进这一串');
    expect(formatHexColor(0xFF000102), '#000102');
  });

  test('格式化之后再解析回来是同一个不透明色', () {
    for (final c in <int>[0xFF4C8DFF, 0xFF000000, 0xFFFFFFFF, 0xFF7A5CFF]) {
      expect(parseHexColor(formatHexColor(c)), c);
    }
  });
}
```

- [ ] **Step 2: 跑它，确认它失败**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/hex_color_test.dart`
Expected: FAIL —— 包解析不了。

- [ ] **Step 3: 实现 `app/lib/core/hex_color.dart`**

实现要点（规格 §8 已定）：先 `trim()`、去掉一个前导 `#`；长度必须是 3 或 6；每一位都必须是 `0-9a-fA-F`（用 `int.tryParse(..., radix: 16)` 逐段转，别用正则整串 —— 逐段转天然把「长度对但字符非法」也挡住了）；三位则每位重复一次；结果 `| 0xFF000000`。

- [ ] **Step 4: 跑它，确认通过**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/hex_color_test.dart`
Expected: PASS（6/6）。

- [ ] **Step 5: 提交**

```bash
git add app/lib/core/hex_color.dart app/test/hex_color_test.dart
git commit -m "feat(color): 十六进制色值解析与格式化（六位 / 三位，不收 alpha）"
```

---

### Task 3: 取色的面 —— 预览、小样、预设、确定/取消

**Files:**
- Create: `app/lib/features/calendar/shift_color_picker.dart`
- Test: `app/test/shift_color_picker_test.dart`

**Interfaces:**
- Consumes: `kShiftPalette` / `kShiftCardSurfaces` / `compoundOver` / `kShiftChipTintAlpha` / `kShiftChipStrokeAlpha`（Task 1）、`parseHexColor` / `formatHexColor`（Task 2）
- Produces:
  - `Future<int?> showShiftColorPicker(BuildContext context, {required int current, String? sampleLabel})` —— 返回用户选定的**不透明 ARGB**；取消 / 点外面关掉返回 `null`
  - 内部状态类 `ShiftColorPickerBody`（`StatefulWidget`，`{required int current, String? sampleLabel}`）—— 单独公开是为了 widget 测试能直接挂它，不必每次都走弹层

**这一版先不做色相条与方盘**（Task 4 加），先把壳立起来：预览 / 小样 / 预设 / 确定取消。

壳走 `showGlassSheet<int>(context: context, isScrollControlled: true, builder: ...)`（`glass_dialog.dart:408`）+ `GlassPanel(solid: true)`，与现在那个取色层同一个配方。`isScrollControlled: true` 是给 Task 4 的键盘留的。

- [ ] **Step 1: 写失败的用例**

新建 `app/test/shift_color_picker_test.dart`（夹具照 `app/test/recurring_panel_test.dart` 的头：`initializeDateFormatting` / `L10n.locale = 'zh'` / `_settle` / `_dispose`；这个组件**不碰库**，所以不需要 `databaseProvider`）。

```dart
// 弹层返回了什么、关没关 —— 每条用例开头由 `_openPicker` 重置。
int? _picked;
bool _closed = false;

Future<void> _openPicker(WidgetTester tester,
    {required int current, String? sampleLabel}) async {
  _picked = null;
  _closed = false;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            _picked = await showShiftColorPicker(context,
                current: current, sampleLabel: sampleLabel);
            _closed = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await _settle(tester);
}
```

每条用例的收尾一律是「点确定或取消 → `_settle` → 断言 `_picked`」。

```dart
void main() {
  testWidgets('挂上就有 16 颗预设与当前色的预览', ...);
  // 断言：`find.byKey(const ValueKey('shift-preset-0'))` 到 `-15` 都在；
  //       第 0 颗（当前色 0xFF4C8DFF）带选中描边。

  testWidgets('挑一颗预设 → 确定：返回那颗色', ...);
  // current = 0xFF4C8DFF；点第 8 颗（0xFFE53935）→ 点 L10n.confirm →
  // `_closed` 为真、`_picked == 0xFFE53935`。

  testWidgets('什么都不动 → 确定：原样返回当前色（当前色不在盘里也不许变）', ...);
  // current = 0xFF5B7FFF（那个默认色，任何一版盘都没有它）→ 直接确定 → 0xFF5B7FFF。

  testWidgets('取消：返回 null', ...);

  testWidgets('点外面关掉：返回 null', ...);
  // tester.tapAt 遮罩上一点（弹层顶端往上一点）。

  testWidgets('十六进制框：敲合法值 → 确定，返回敲的那个', ...);
  // enterText('#E65100') → 确定 → 0xFFE65100。

  testWidgets('十六进制框：敲非法值 → 确定，还是上一次的有效色', ...);
  // enterText('nonsense') → 确定 → 与打开时一致；且这一路不许抛异常。

  testWidgets('小窗 200×400：整层不溢出、确定点得到', ...);
  // 视口 200×400；断言 takeException() == null，且
  // tester.hitTestOnBinding(确定按钮中心) 命中的是它自己。
}
```

预设那 16 颗各挂一个 `ValueKey('shift-preset-$i')`（**顺序与 `kShiftPalette` 一致**），测试靠它定位 —— 别去数圆点个数。

- [ ] **Step 2: 跑它，确认它失败**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/shift_color_picker_test.dart`
Expected: FAIL —— 包解析不了。

- [ ] **Step 3: 实现 `app/lib/features/calendar/shift_color_picker.dart`**

结构（自上而下，写进注释）：

1. 标题 `L10n.shiftColor`。
2. **预览行**：当前色一颗实心大圆点 + `TextField`（`controller: _hexCtrl`，`decoration: glassInputDecoration(context, L10n.shiftColorHex)`）。输入变化时 `parseHexColor` 得到 `null` 就只把输入框转成警示色、**不动 `_color`**；得到颜色就 `setState` 更新 `_color` 与预览。
3. **两颗真日历小样**：按 §4 那套配方画「14% 淡染 + 45% 描边 + 中性字」，一颗压 `kShiftCardAppLight`、一颗压 `kShiftCardAppDark`，文字用 `sampleLabel ?? '班'`，字色走 `AppTokens.inkFor(...)`（与日历格子同一处口径）。
4. **16 颗预设**：`Wrap`，36dp 圆点（与现在那个取色层同一套），每颗挂 `ValueKey('shift-preset-$i')`（`i` 与 `kShiftPalette` 的下标一致 —— 测试靠它定位，别去数圆点个数）；点一下 `setState(() => _color = c)` 并同步十六进制框；当前色在其中时带 `onSurface` 描边。
5. **取消 / 确定**：`GlassActionButton`（`secondary` / `primary`），`onPressed: () => Navigator.pop(context)` 与 `() => Navigator.pop(context, _color)`。
   **这两个都是同步的**，所以不涉及仓库里 `dialogCloser` 那条「异步之后 pop 要先确认还是最上层」的规矩 —— 但**别**在别处给它套 `await`。
6. 外面套 `SingleChildScrollView` + `SafeArea`。

新 l10n（加在 `core/l10n.dart` 的 `shiftColor` 一带）：
`shiftColorHex`（`十六进制` / `Hex`）、`shiftColorPreview`（`在日历上的样子` / `On a calendar cell`）、`shiftColorCustomHint`（`颜色值格式不对，例如 #4C8DFF` / `Not a colour — try #4C8DFF`）。

- [ ] **Step 4: 跑它，确认通过**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/shift_color_picker_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/shift_color_picker.dart app/lib/core/l10n.dart app/test/shift_color_picker_test.dart
git commit -m "feat(color): 取色的面 —— 预览、日历小样、16 颗预设、确定与取消"
```

---

### Task 4: 色相条与饱和度 / 明度方盘

**Files:**
- Modify: `app/lib/features/calendar/shift_color_picker.dart`（在 Task 3 的壳里插进去）
- Test: `app/test/shift_color_picker_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `ShiftColorPickerBody`
- Produces: 组件内部的 `_hsv`（`HSVColor`）；对外**接口一个字不变**

**两处容易写错、写死在注释里**：

- **状态存 HSV、不存 `int`**：调色时反复 `int → HSV → int` 会漂（色相会慢慢走）。所以 `_hsv` 是唯一真源，`_color` 由它推；**用户点预设或敲十六进制**时才反过来 `HSVColor.fromColor(...)` 灌进去。已知有损：灰阶（饱和度≈0）的色相是无意义的，round-trip 之后色相会落到红 —— 这是 HSV 的固有性质，**不要试图修**，只要保证不崩、一动就有反应（Review Focus 4）。
- **方盘 / 色相条一律走 `CustomPaint` + `GestureDetector`**，宽度用 `LayoutBuilder` 现取：`fraction = localPosition.dx / width`。色相条是一段七色 `LinearGradient`（红→黄→绿→青→蓝→品红→红）；方盘是「横向 白→透明」叠「纵向 透明→黑」，底色是当前色相的纯色。**颜色字面量在这一处是必需的** —— 但按 §5 末尾那条，**用 `int` 常量 + `Color(int)`**，别写 `Color(0x…)`，这样令牌守门不用豁免。

- [ ] **Step 1: 写失败的用例**

在 `app/test/shift_color_picker_test.dart` 里加：

```dart
testWidgets('拖方盘 / 点色相条：预览与十六进制框当下就跟着走', ...);
  // 从 0xFFE53935 开。找方盘（byKey 或 byType，实施时给两个 CustomPaint 各挂一个 Key）：
  //   · 在它偏右上一点的位置 tapAt → _color 变了（断言十六进制框里的文字变了）
  //   · 在色相条上点靠左与靠右两点 → 两次得到的十六进制文字不相同

testWidgets('灰阶当前色打开：不崩，且一动就有反应', ...);
  // current = 0xFF9AA0B4（饱和度极低）。断言 takeException() == null；
  // 再在方盘上 tapAt 一处 → 十六进制文字变了（色相 round-trip 有损，只要求这个）。

testWidgets('在方盘上拖过之后再点一颗预设，方盘与预览要跟着回到那一颗', ...);
  // 这条钉「预设 ↔ HSV 是双向同步的」——只单向的话，用户拖完再点预设，
  // 方盘上的游标会停在上一个位置，下一次一拖颜色就跳回旧色相。
```

- [ ] **Step 2: 跑它，确认它失败**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/shift_color_picker_test.dart`
Expected: FAIL —— 找不到色相条 / 方盘那两个 Key。

- [ ] **Step 3: 实现**

给色相条与方盘各一个 `Key`（`const ValueKey('shift-hue')` / `const ValueKey('shift-sv')`），测试用它们定位。两者的拖拽用 `onPanStart` / `onPanUpdate`（`onTapDown` 也接上，点一下就该生效）；`onPanUpdate` 里用 `details.localPosition`（**不是** `globalPosition` —— 后者要减去控件原点，多一步就多一处能错的地方）。

- [ ] **Step 4: 跑它，确认通过；再跑全套**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/shift_color_picker_test.dart && "$FLUTTER_ROOT/bin/flutter" test`
Expected: 全绿。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/shift_color_picker.dart app/test/shift_color_picker_test.dart
git commit -m "feat(color): 色相条与饱和度 / 明度方盘"
```

---

### Task 5: 接进编辑器，并把老盘与老测试收掉

**Files:**
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`（`_palette` 删掉、`_pickColor` 换掉、`_addClass` 的取色换成 `kShiftPalette`）
- Modify: `app/test/design_tokens_test.dart:990-1001`（那份写死的 8 颗样本 → 16 颗）
- Test: `app/test/schedule_editor_test.dart`

**Interfaces:**
- Consumes: `kShiftPalette`（Task 1）、`showShiftColorPicker`（Task 3/4）
- Produces: 编辑器行为不变（点色点 → 弹层 → 结果写回 `_classes[index]`）

- [ ] **Step 1: 写失败的用例**

在 `app/test/schedule_editor_test.dart` 里加两条（这个文件已有挂编辑器的夹具，照抄）：

```dart
test('新建班次循环取色的起点是盘里的第一颗', ...);
  // 走 _addClass（点「添加班次」）→ 断言新那颗的 color == kShiftPalette.first。
  // ⚠️ 这一条是**新加的护栏**：原来那条「chip 带上班次色与名称」看着像在钉这件事，
  // 其实它自己造了一个带指定颜色的班次、压根没走 _addClass（builder check 查出来的）。

testWidgets('点行末的色点 → 取色层弹出 → 挑一颗 → 确定 → 班次的颜色变了', ...);
  // 断言弹层里有 find.text(L10n.shiftColor)；点一颗预设；点 L10n.confirm；
  // 落定后那一条班次的 color 是挑的那颗。
```

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/schedule_editor_test.dart`
Expected: 第一条 FAIL（`_addClass` 现在用的是 private `_palette`，测试读不到 `kShiftPalette` 之前包都解析不了）；第二条 FAIL（弹层还是老的那一层，没有 `L10n.confirm`）。

- [ ] **Step 2: 实现**

- 删掉 `_palette`；`_addClass` 里换成 `kShiftPalette[idx % kShiftPalette.length]`。
- `_pickColor` 整个换成：

```dart
Future<void> _pickColor(int index) async {
  final c = await showShiftColorPicker(context,
      current: _classes[index].color,
      sampleLabel: _classes[index].abbr ?? _classes[index].name);
  if (c == null || !mounted) return;
  setState(() => _classes[index] = _editClass(_classes[index], color: c));
}
```

  ⚠️ **`_editClass` 那套别动** —— `AGENTS.md` 写着它有意的**不走 `copyWith`**（可空字段清不掉），照抄它现在的写法就行，这一版只换颜色来源。

- [ ] **Step 3: 更新既有的令牌用例**

`app/test/design_tokens_test.dart:990-1001` 那份写死的样本列表换成 `kShiftPalette`（**别再手抄一遍 16 个**，直接引用常量 —— 那样盘一变它就跟着变）；`:1014-1018` 那条钉 `onSolid` 具体返回值的用例保持不动（它挑的是特定几颗，与盘的长度无关）。

- [ ] **Step 4: 跑它，确认通过；再跑全套**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" analyze && "$FLUTTER_ROOT/bin/flutter" test`
Expected: analyze 0 issues；全绿。

- [ ] **Step 5: 提交**

```bash
git add app/lib/features/calendar/schedule_editor_screen.dart app/test/design_tokens_test.dart app/test/schedule_editor_test.dart
git commit -m "feat(color): 编辑器改用 16 颗的盘与新的取色层"
```

---

### Task 6: 视觉工装屏单与基线

**Files:**
- Modify: `app/tool/visual/render_screens_test.dart`（取色层是命令式弹层，要一层薄壳在 `beforeCapture` 里点出来）
- Modify: `app/tool/visual/visual_screens.dart`（若取色层要进屏单让对比度审计覆盖）

- [ ] **Step 1: 补三屏**

- **取色层展开**（浅色 + 深色两档，它是个新的界面态）：16 颗预设 + 方盘 + 预览 + 小样同框。
- **非法十六进制**：`beforeCapture` 里 `enterText` 一个非法值 —— 警示色只有出图能看出好不好看。
- **新加的深色落到日历格子上**（Review Focus 5）：把种子库里某个班次的颜色换成 `#2E7D32` 或 `#795548`，拍日历那屏。

- [ ] **Step 2: 出图并**看图**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test tool/visual/`
Expected: 全绿。然后**逐张打开**：取色层在浅色 / 深色下是不是都像一件东西；方盘的游标看得见吗；那两颗日历小样里的字读得出来吗；小窗那两张（200×400）排版有没有坏。

- [ ] **Step 3: 与上一版基线逐张比**

**先把当前改动提交掉**（⚠️ 取基线要 `git checkout <旧提交> -- app/lib app/tool`，那一步会**冲掉未提交的改动** —— v0.11.4 真踩过），再比。用 `scripts/diff_visual.py`，把「变了」与「该变」对上。

- [ ] **Step 4: 提交**

```bash
git add app/tool/visual/
git commit -m "test(visual): 取色层、非法色值、新色落到日历上"
```

---

### Task 7: 版本号、更新日志与发布

**Files:**
- Modify: `app/pubspec.yaml:4`、`app/lib/core/app_info.dart`
- Modify: `app/lib/features/profile/app_dialogs.dart`（`_changelogZh` / `_changelogEn`）
- Modify: `AGENTS.md`（版本史 + 「关键决策与坑」新增一条）

- [ ] **Step 1: 版本号**

`0.11.5+152` → `0.11.6+153`，`appVersion` 同步 `'0.11.6'`。

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/app_info_test.dart`
Expected: PASS。

- [ ] **Step 2: 更新日志**

在 `_changelogZh` / `_changelogEn` **prepend** 一条 `0.11.6`，删掉最旧一条，保持**恰好 10 条**；纯文本、**不许出现 markdown 标记**（`changelog_window_test.dart` 守门）。要点：班次颜色从 8 种扩到 16 种；多了一个可以自己取色的面（色相 / 明度 + 直接填颜色值）；默认那 16 种都保证在日历和桌面小组件上看得清。

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" test test/changelog_window_test.dart`
Expected: PASS。

- [ ] **Step 3: 全套验收**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" analyze && "$FLUTTER_ROOT/bin/flutter" test && "$FLUTTER_ROOT/bin/flutter" test tool/visual/`
Expected: analyze 0 error / 0 warning；两套全绿；**用例数只增不减**。

- [ ] **Step 4: 构建与分发**

Run: `cd app && "$FLUTTER_ROOT/bin/flutter" build apk --release --target-platform android-arm64`
复制到 `dist/倒班助手Pro-v0.11.6.apk`，用 `aapt2 dump badging` 核对 versionName `0.11.6` / versionCode `153` / 包名 `com.daoban.shiftassistantpro`。

- [ ] **Step 5: 更新 `AGENTS.md`**

版本史补 0.11.6 那条；「关键决策与坑」新增一条：**班次色的盘与那条可读性门槛** —— 16 颗、四处卡底（含桌面小组件半透明卡的两个极端壁纸）、门槛 1.3490 是由现有八个的下界定出来的、以及「自定义色一律不透明」那两条理由（`WidgetChip.tintedChip` 的 `setAlpha` 覆盖 alpha 字节 + `widget_snapshot.dart` 用 `color: 0` 当哨兵）。

- [ ] **Step 6: 真机复验（有设备时）**

编辑排班 → 点班次行末的色点 → 挑一颗新加的深色 → 保存 → 看日历格子与桌面小组件上都看得清；再打开取色层，自己敲一个颜色值确认能落上。

- [ ] **Step 7: 提交并发布**

```bash
git add app AGENTS.md docs/superpowers/
git commit -m "chore(release): v0.11.6 —— 班次颜色扩到 16 种并支持自定义取色"
git push origin beta
git tag v0.11.6 && git push origin v0.11.6
```

发布说明写进 `tools/gh/release-notes-v0.11.6.md`，再跑 `scripts/release.ps1 -SkipConfirm`（**别先 dot-source `tools/build-env.ps1`** —— 它会把 `APPDATA` 重定向走，`gh` 于是找不到登录态，v0.11.4 发布时真踩过）；**发完 curl 一次 `main` 上的 `latest.json` 核对版本号**。

---

## 自查

- **规格覆盖**：§1 → Task 1（盘搬出来）+ Task 5（编辑器接线）；§2 → 全局约束 + 各任务的反目标断言；§3 → Task 1 Step 1（16 颗、顺序、前八不动）；§4 → Task 1 Step 1（四处卡底 × 16 颗 + 门槛自证）；§5 → Task 3（预览 / 小样 / 预设 / 确定取消）+ Task 4（色相条与方盘）+ 两处约定（`int` 常量、不发触觉）；§6 → Task 3 的 l10n；§7 → 各任务的用例 + Task 6 出图；§8 → 四条「留给实施」都落在 Task 2 / 3 / 6 里。
- **类型一致**：`kShiftPalette` / `kShiftCardSurfaces` / `kShiftColorBar` / `compoundOver` / `shiftChipStrokeContrast` / `parseHexColor` / `formatHexColor` / `showShiftColorPicker` / `ShiftColorPickerBody` / `L10n.shiftColorHex` 全文同名同签名。
- **Review Focus 五条**各自落在：1 → Task 3 Step 1 的两条十六进制用例 + Task 6 Step 1 的非法值那一屏；2 → Task 3 Step 1 的小窗那条（Task 4 加了方盘之后**要再跑一遍**）；3 → Task 3 Step 1 的「什么都不动 → 确定」；4 → Task 4 Step 1 的灰阶那条；5 → Task 6 Step 1 的第三屏 + Step 2 看图。
- **明确不做**：不做吸色；不给自定义色设取值范围；不收 alpha（八位十六进制判非法）；不发触觉；不碰 Drift 表；**Kotlin 一个字都不改**。
