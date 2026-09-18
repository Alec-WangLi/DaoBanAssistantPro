# 设计语言大一统 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「倒班助手Pro」散落的视觉 magic number 收敛成一套设计令牌，并按已确认方向完成「整体重设计」——中性背景 + 5 色强调 + 动态光线玻璃 + outlined 图标 + 弹簧 Q 弹动画。

**Architecture:** 新增 `core/design_tokens.dart` 作为唯一令牌来源（颜色/圆角/间距/动效/玻璃配方/排版），`core/motion.dart` 提供弹簧原语，`core/glass/light_controller.dart` 用 `sensors_plus` 驱动动态光线。`app_theme.dart` 改为中性 ColorScheme（强调色只覆盖 `primary`），`glass.dart` 与 10 个共享玻璃组件、8 个页面全部改为消费令牌，消除各自内联的圆角/时长/透明度/图标。

**Tech Stack:** Flutter · Dart · Riverpod · Drift · `sensors_plus`（唯一新增依赖）。

**Spec:** [2026-09-03-design-language-unification-design.md](../specs/2026-09-03-design-language-unification-design.md)

## Global Constraints

- 版本号 `X.Y.Z+build`：**AI 只改末位 Z**（`0.4.3+63 → 0.4.4+64`），`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 两处同步。
- 验收铁律：`flutter analyze` **0 error / 0 warning**；`flutter test` **6/6**。
- **不新增第三方依赖（`sensors_plus` 除外）**；Q 弹用手写 `SpringSimulation`，不引 `flutter_animate`。
- **不碰**业务逻辑 / Drift 数据模型 / 闹钟原生链路 / domain 排班公式；班次数据色（白班蓝/夜班紫/休息灰/大休）、节假日红、seed 数据一律不动。
- feature 层（`features/`）收尾后**不得再出现**内联 `Color(0x…)`、非令牌圆角、非令牌 `Duration(milliseconds:…)`。
- 复用 `core/widgets/` 共享组件，不另起炉灶。
- 所有步骤在命令前先 `cd app`（pubspec/test 均在 `app/` 下）。
- 本机构建需先 `. C:/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/tools/build-env.ps1`（设 JAVA_HOME/ANDROID_HOME/PUB_CACHE）。仅 `flutter analyze` / `flutter test` 不需要该环境；`flutter pub get` 需要 pub cache 可用。

---

## 全局替换映射表（所有 sweep 任务共用）

下面这几张表是「哪些 magic number → 哪个令牌」的唯一口径，后文每个 sweep 任务都引用它们，不再重复。

**圆角**（`BorderRadius.circular` / `StadiumBorder` 等）：

| 现值 | 换成 |
|---|---|
| `circular(12)` | `AppTokens.radiusS` |
| `circular(14)` | `AppTokens.radiusM` |
| `circular(16)` | `AppTokens.radiusM` |
| `circular(18)` | `AppTokens.radiusL` |
| `circular(20)` | `AppTokens.radiusL` |
| `circular(22)` | `AppTokens.radiusL` |
| `circular(24)` | `AppTokens.radiusXL` |
| `circular(28)` | `AppTokens.radiusXL` |
| `circular(30)` | `AppTokens.radiusXL` |
| `circular(2/3/4/10)`（标签/小 chip/描边角） | `AppTokens.radiusS`（描写边小圆角用 `AppTokens.spaceXs` 级，见下） |

> 例：`BorderRadius.circular(20)` → `BorderRadius.circular(AppTokens.radiusL)`；`BorderRadius.circular(30)`（导航胶囊）改为胶囊语义 `BorderRadius.circular(height/2)`，见 Task 12。

**时长**（非弹簧的 `Duration(milliseconds:…)`）：

| 现值 | 换成 |
|---|---|
| `80` / `120` / `140` | `AppTokens.durFast` |
| `150` / `180` / `200` / `240` | `AppTokens.durMed` |
| `360` / `650` | `AppTokens.durSlow`（响铃入场 650 保留其戏剧性，用 `durSlow`） |

**曲线**：`Curves.easeOutBack` 用于「按压缩放回弹」处统一换弹簧（见 `core/motion.dart`）；`Curves.easeOutCubic` 用于位置吸附（分段/导航/开关轨道）保留。

**玻璃配方**：一律改用 `AppTokens.glassTint / glassSurface / glassBorder / glassHighlight / glassShadow`（见 Task 1 定义），删除组件内硬编码的 `Colors.white.withValues(alpha: …)` 渐变对。

**图标**：统一 `_outlined` 线性家族。`Icons.*_rounded` → `Icons.*_outlined`（`add_rounded`→`add_outlined`、`check_rounded`→`check_outlined`、`snooze_rounded`→`snooze_outlined`、`bolt_rounded`→`bolt_outlined`、`close_rounded`→`close_outlined`、`chevron_*_rounded`→`chevron_*_outlined`、`keyboard_arrow_up_rounded`→`keyboard_arrow_up_outlined`、`add_circle_outline_rounded`→`add_circle_outline_outlined`、`remove_circle_outline_rounded`→`remove_circle_outline_outlined`）。`circle_outlined` 保留。其余 `*_outline_rounded` / `*_outline`（如 `play_circle_outline_rounded`、`delete_outline_rounded`、`error_outline_rounded`、`help_outline_rounded`、`info_outline_rounded`、`celebration_rounded`、`calendar_month_rounded`）在**最终一致性收尾**统一 grep 转 `_outlined` 变体（有则转、无则留）。导航 4 图标单独见 Task 12。

---

## Task 1: 设计令牌层 `design_tokens.dart`

**Files:**
- Create: `app/lib/core/design_tokens.dart`
- Test: `app/test/design_tokens_test.dart`

**Interfaces:**
- Produces: `class AppTokens`（静态常量 + 静态方法），供所有后续任务 import `'../core/design_tokens.dart'`。关键成员：
  - 颜色：`bgLight/bgDark/surfaceLight/surfaceDark/inkLight/inkDark/inkMutedLight/inkMutedDark/danger/success/holiday`
  - 圆角：`radiusS/radiusM/radiusL/radiusXL`（double）
  - 间距：`spaceXs/spaceSm/spaceMd/spaceLg/spaceXl`（double）
  - 模糊：`blurChip/blurCard/blurPanel`（double）
  - 时长：`durFast/durMed/durSlow`（Duration）
  - 弹簧：`qSpring`（SpringDescription）、`pressScale`、`pillGrow`
  - 方法：`static LinearGradient accentGradient(Color accent)`、`glassTint/surface/border/highlight/highlightStop/shadow`
  - 排版：`fontDisplayXl/fontDisplay/fontTitle/fontHeading/fontBody/fontCaption/fontMicro`

- [ ] **Step 1: 写失败测试**

```dart
// app/test/design_tokens_test.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';

void main() {
  test('圆角/间距/模糊令牌为预期档位', () {
    expect(AppTokens.radiusS, 12);
    expect(AppTokens.radiusM, 16);
    expect(AppTokens.radiusL, 22);
    expect(AppTokens.radiusXL, 28);
    expect(AppTokens.blurChip, 12);
    expect(AppTokens.blurCard, 18);
    expect(AppTokens.blurPanel, 24);
  });

  test('中性背景与语义色非空且区分明暗', () {
    expect(AppTokens.bgLight, isNot(equals(AppTokens.bgDark)));
    expect(AppTokens.inkLight, isNot(equals(AppTokens.inkDark)));
    expect(AppTokens.danger, const Color(0xFFE53935));
  });

  test('accentGradient 用 accent 色：顶 0.85 底 0.50', () {
    final g = AppTokens.accentGradient(const Color(0xFF00C7BE));
    expect(g.colors.first, const Color(0xFF00C7BE).withValues(alpha: 0.85));
    expect(g.colors.last, const Color(0xFF00C7BE).withValues(alpha: 0.50));
  });

  test('玻璃配方随明暗变化（暗色更淡）', () {
    final lightTop = AppTokens.glassTint(false, true).first;
    final darkTop = AppTokens.glassTint(true, true).first;
    expect(lightTop.a, greaterThan(darkTop.a));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/design_tokens_test.dart`
Expected: FAIL（`design_tokens.dart` 不存在）

- [ ] **Step 3: 写实现**

```dart
// app/lib/core/design_tokens.dart
import 'package:flutter/material.dart';

/// 设计令牌单一事实来源。所有组件的颜色/圆角/间距/动效/玻璃配方/排版一律引用这里，
/// 禁止在 feature 层内联 magic number。
class AppTokens {
  AppTokens._();

  // ── 颜色：中性背景 + 文字（明/暗各一套） ──
  static const Color bgLight = Color(0xFFF5F6FA);
  static const Color bgDark = Color(0xFF0B0B10);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF16161E);
  static const Color inkLight = Color(0xFF111118);
  static const Color inkDark = Color(0xFFF2F2F7);
  static const Color inkMutedLight = Color(0xFF6E6E82);
  static const Color inkMutedDark = Color(0xFF9A9AB0);

  // ── 语义色 ──
  static const Color danger = Color(0xFFE53935);
  static const Color success = Color(0xFF4ADE80);
  static const Color holiday = Color(0xFFE53935);

  // ── 圆角 ──
  static const double radiusS = 12;
  static const double radiusM = 16;
  static const double radiusL = 22;
  static const double radiusXL = 28;

  // ── 间距（4px 栅格） ──
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 20;

  // ── 玻璃模糊 sigma ──
  static const double blurChip = 12;
  static const double blurCard = 18;
  static const double blurPanel = 24;

  // ── 时长（非弹簧过渡） ──
  static const Duration durFast = Duration(milliseconds: 120);
  static const Duration durMed = Duration(milliseconds: 220);
  static const Duration durSlow = Duration(milliseconds: 340);

  // ── Q 弹弹簧 + 缩放 ──
  static const SpringDescription qSpring =
      SpringDescription(mass: 1, stiffness: 400, damping: 16);
  static const double pressScale = 0.96;
  static const double pillGrow = 1.06;

  // ── 排版（system 字体） ──
  static const double fontDisplayXl = 84;
  static const double fontDisplay = 28;
  static const double fontTitle = 20;
  static const double fontHeading = 18;
  static const double fontBody = 14;
  static const double fontCaption = 12;
  static const double fontMicro = 11;

  /// 强调色渐变（按钮/导航选中/填充条用）：顶 0.85 → 底 0.50。
  static LinearGradient accentGradient(Color accent) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: 0.85),
          accent.withValues(alpha: 0.50),
        ],
      );

  // ── 玻璃配方（统一，两档：glassTint 胶囊/按钮、glassSurface 卡片/面板） ──
  // 顶层 alpha 更高；blurOn=false（低端机/关高级材质）时整体更实。
  static List<Color> glassTint(bool isDark, bool blurOn) => isDark
      ? [
          Colors.white.withValues(alpha: blurOn ? 0.16 : 0.22),
          Colors.white.withValues(alpha: blurOn ? 0.07 : 0.12),
        ]
      : [
          Colors.white.withValues(alpha: blurOn ? 0.80 : 0.90),
          Colors.white.withValues(alpha: blurOn ? 0.45 : 0.72),
        ];

  static List<Color> glassSurface(bool isDark, bool blurOn) => isDark
      ? [
          Colors.white.withValues(alpha: blurOn ? 0.11 : 0.16),
          Colors.white.withValues(alpha: blurOn ? 0.04 : 0.08),
        ]
      : [
          Colors.white.withValues(alpha: blurOn ? 0.70 : 0.82),
          Colors.white.withValues(alpha: blurOn ? 0.34 : 0.60),
        ];

  static Color glassBorder(bool isDark) =>
      Colors.white.withValues(alpha: isDark ? 0.16 : 0.90);

  static List<Color> glassHighlight(bool isDark) => [
        Colors.white.withValues(alpha: isDark ? 0.18 : 0.55),
        Colors.white.withValues(alpha: 0.0),
      ];

  static double glassHighlightStop(bool isDark) => isDark ? 0.28 : 0.30;

  static BoxShadow glassShadow(bool isDark) => BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
        blurRadius: 28,
        offset: const Offset(0, 10),
      );
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/design_tokens_test.dart`
Expected: PASS（4 项全过）

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/design_tokens.dart app/test/design_tokens_test.dart
git commit -m "feat(design): add design tokens single source of truth"
```

---

## Task 2: 修剪 `AppColors`（去死令牌 + 蓝紫硬编码）

**Files:**
- Modify: `app/lib/core/theme/app_colors.dart`

**Interfaces:**
- Consumes: `AppTokens`（`danger`/`holiday`/`success` 已迁移）。
- Produces: `AppColors.accentPalette` / `AppColors.primary` **签名不变**（`app_settings.dart` / `app_theme.dart` 依赖）；删除 `secondary`/`accent`/`gradientStart`/`gradientEnd`/`accentGradient`/`glassLightFill`/`glassLightBorder`/`glassLightHighlight`/`glassDarkFill`/`glassDarkBorder`/`glassDarkHighlight`/`shiftDay`~`shiftRest` 中的 UI 死令牌与蓝紫常量。

- [ ] **Step 1: 重写文件**

替换 `app/lib/core/theme/app_colors.dart` 全文为：

```dart
import 'package:flutter/material.dart';

/// 强调色（主色调）5 色候选 + 班次数据色。
/// 中性背景 / 语义色 / 圆角 / 动效 / 玻璃配方见 `design_tokens.dart`。
class AppColors {
  AppColors._();

  // 主色（默认深蓝紫，仅作「强调色」，不再当背景氛围）
  static const Color primary = Color(0xFF5B6CFF);

  // 主色调候选（「我的」页可选，与下方 accentPalette 顺序一致）
  static const Color sky = Color(0xFF0A84FF);
  static const Color teal = Color(0xFF00C7BE);
  static const Color orange = Color(0xFFFF9F0A);
  static const Color rose = Color(0xFFFF375F);
  static const List<Color> accentPalette = [primary, sky, teal, orange, rose];

  // 班次数据色（与 domain 默认一致，属「内容」非「装饰」，保留）
  static const int shiftDay = 0xFF4C8DFF; // 白班
  static const int shiftNight = 0xFF7A5CFF; // 上夜班
  static const int shiftAfterNight = 0xFF9AA0B4; // 下夜班
  static const int shiftRest = 0xFF5A5F73; // 大休
}
```

- [ ] **Step 2: 全仓引用修正**

Run（列出所有引用已删符号处，逐处改）：

```bash
grep -rn "AppColors.secondary\|AppColors.accent\b\|AppColors.gradientStart\|AppColors.gradientEnd\|AppColors.accentGradient\|AppColors.glassLight\|AppColors.glassDark" app/lib
```

按结果改：
- `app_theme.dart` 里 `secondary: AppColors.secondary` → `secondary: AppTokens.inkMutedDark`（见 Task 5，此处先行一并改，避免编译失败）。
- `animated_background.dart` 里 `AppColors.gradientStart/gradientEnd/secondary` 三处 blob 色 → 见 Task 7 整体中性化，先改为 `Colors.white.withValues(alpha: 0.10)` 占位保证可编译，Task 7 再定稿。
- `home_shell.dart` 里 `AppColors.gradientStart/gradientEnd`（导航滑块）→ `AppTokens.accentGradient(activeColor)`（见 Task 12，此处先一并改保障编译）。

- [ ] **Step 3: 校验**

Run: `flutter analyze`
Expected: 0 error（Task 5/7/12 会收敛 warning，此处只要求能编译）

- [ ] **Step 4: Commit**

```bash
git add app/lib/core/theme/app_colors.dart app/lib/core/theme/app_theme.dart app/lib/core/theme/animated_background.dart app/lib/features/home/home_shell.dart
git commit -m "refactor(design): trim AppColors dead tokens, decouple accent from background"
```

---

## Task 3: 弹簧原语 `core/motion.dart`

**Files:**
- Create: `app/lib/core/motion.dart`
- Test: `app/test/motion_test.dart`

**Interfaces:**
- Produces: `void springTo(AnimationController c, double target)`、`class QScale`（`{required bool pressed, required double scale, required Widget child}`）。

- [ ] **Step 1: 写失败测试**

```dart
// app/test/motion_test.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/motion.dart';

void main() {
  test('qSpring 欠阻尼（阻尼比 < 1，产生 Q 弹过冲）', () {
    final ratio = AppTokens.qSpring.damping /
        (2 * math.sqrt(AppTokens.qSpring.stiffness * AppTokens.qSpring.mass));
    expect(ratio, lessThan(1.0));
    expect(ratio, greaterThan(0.0));
  });

  testWidgets('QScale 按下从 1.0 弹向 scale', (tester) async {
    var pressed = false;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => pressed = !pressed),
        child: QScale(
          pressed: pressed,
          scale: 0.96,
          child: const SizedBox(width: 10, height: 10),
        ),
      ),
    ));

    var scale = tester
        .widget<ScaleTransition>(find.byType(ScaleTransition))
        .scale
        .value;
    expect(scale, closeTo(1.0, 0.001));

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    scale = tester
        .widget<ScaleTransition>(find.byType(ScaleTransition))
        .scale
        .value;
    expect(scale, lessThan(1.0));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/motion_test.dart`
Expected: FAIL（`design_tokens.dart` 里 `qSpring` 的 `SpringDescription` 需 import `flutter/physics`；确认已可用，若报错则修 import）

- [ ] **Step 3: 写实现**

```dart
// app/lib/core/motion.dart
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'design_tokens.dart';

/// 让 [controller] 从当前值以弹簧物理弹到 [target]（Q 弹过冲，替换 easeOutBack+固定时长）。
void springTo(AnimationController controller, double target) {
  final sim = SpringSimulation(
    AppTokens.qSpring,
    controller.value,
    target,
    controller.velocity,
  );
  controller.animateWith(sim);
}

/// Q 弹缩放组件：按下时从 1.0 弹到 [scale]，松手弹回 1.0。
class QScale extends StatefulWidget {
  const QScale({
    super.key,
    required this.pressed,
    required this.scale,
    required this.child,
  });

  final bool pressed;
  final double scale;
  final Widget child;

  @override
  State<QScale> createState() => _QScaleState();
}

class _QScaleState extends State<QScale> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController.unbounded(vsync: this, value: 1.0);

  @override
  void didUpdateWidget(covariant QScale old) {
    super.didUpdateWidget(old);
    if (old.pressed != widget.pressed) {
      springTo(_c, widget.pressed ? widget.scale : 1.0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _c, child: widget.child);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/motion_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/motion.dart app/test/motion_test.dart
git commit -m "feat(design): add spring motion primitive (QScale)"
```

---

## Task 4: 动态光线 `light_controller.dart` + `sensors_plus`

**Files:**
- Modify: `app/pubspec.yaml`（dependencies 加 `sensors_plus: ^6.0.0`）
- Create: `app/lib/core/glass/light_controller.dart`
- Test: `app/test/light_controller_test.dart`

**Interfaces:**
- Consumes: 无（不 import `glass.dart`，避免循环）。
- Produces: `class LightController`，`static final ValueNotifier<Offset> light`、`static void setEnabled(bool)`、`static Offset lightDirectionFromGravity({required double x, required double y, required double z})`。
- 供 `glass.dart`（在 `recomputeGlassBlur` 里调 `setEnabled`）+ `GlassPanel` 消费。

- [ ] **Step 1: 加依赖**

`app/pubspec.yaml` 的 `dependencies:` 段尾（`cupertino_icons` 之前）加：

```yaml
  sensors_plus: ^6.0.0
```

Run: `flutter pub get`
Expected: 无报错（若 6.0.0 拉不到，用 `^6.1.0` 就近版本，仍是 6.x）。

- [ ] **Step 2: 写失败测试**

```dart
// app/test/light_controller_test.dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/light_controller.dart';

void main() {
  test('重力向量 → 光方向（纯函数归一化）', () {
    expect(
      LightController.lightDirectionFromGravity(x: 9.8, y: 0, z: 0),
      const Offset(1, 0),
    );
    expect(
      LightController.lightDirectionFromGravity(x: 0, y: 9.8, z: 0),
      const Offset(0, 1),
    );
    // 极端值 clamp
    final big = LightController.lightDirectionFromGravity(x: 30, y: -30, z: 0);
    expect(big.dx, lessThanOrEqualTo(1.0));
    expect(big.dy, greaterThanOrEqualTo(-1.0));
  });
}
```

- [ ] **Step 3: 写失败测试确认失败**

Run: `flutter test test/light_controller_test.dart`
Expected: FAIL（文件不存在）

- [ ] **Step 4: 写实现**

```dart
// app/lib/core/glass/light_controller.dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// 动态光线控制器：把设备倾斜（重力向量）归一为 [-1,1] 的光方向，
/// 驱动玻璃高光/折射随手机倾斜流动。降级时（低端机/关「高级材质」）回到静态左上高光。
class LightController {
  LightController._();

  /// 光方向（水平 x/y 分量），默认静态左上。
  static final ValueNotifier<Offset> light =
      ValueNotifier<Offset>(const Offset(-0.4, -0.3));

  static StreamSubscription<AccelerometerEvent>? _sub;
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _enabled = false;

  /// 开/关动态光线。关闭时退静态，不跑传感器。
  static void setEnabled(bool enabled) {
    if (enabled == _enabled) return;
    _enabled = enabled;
    if (!enabled) {
      _sub?.cancel();
      _sub = null;
      light.value = const Offset(-0.4, -0.3);
      return;
    }
    _sub = accelerometerEventStream().listen((e) {
      // 节流到 ~30Hz，避免每帧全屏重绘
      final now = DateTime.now();
      if (now.difference(_last).inMilliseconds < 33) return;
      _last = now;
      light.value = lightDirectionFromGravity(x: e.x, y: e.y, z: e.z);
    }, onError: (_) {});
  }

  /// 纯函数：加速度计读数（含重力）→ 2D 光方向。
  static Offset lightDirectionFromGravity({
    required double x,
    required double y,
    required double z,
  }) {
    const g = 9.8;
    return Offset(
      (x / g).clamp(-1.0, 1.0),
      (y / g).clamp(-1.0, 1.0),
    );
  }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/light_controller_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/core/glass/light_controller.dart app/test/light_controller_test.dart
git commit -m "feat(design): add tilt-driven dynamic light controller"
```

---

## Task 5: 中性 ColorScheme（`app_theme.dart`）

**Files:**
- Modify: `app/lib/core/theme/app_theme.dart`

**Interfaces:**
- Consumes: `AppTokens`、`AppColors.primary`。
- Produces: `buildLightTheme({Color seed = AppColors.primary})` / `buildDarkTheme(...)` 签名不变。

- [ ] **Step 1: 重写两函数**

替换 `buildLightTheme` / `buildDarkTheme` 全文（页面转场 `_FadeSlidePageTransitionsBuilder`/`_pageTransitions` 保留不动）：

```dart
ThemeData buildLightTheme({Color seed = AppColors.primary}) {
  // 中性 seed：让 M3 surface 按灰派生，不随主色相染色。
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF9AA0B4),
    brightness: Brightness.light,
  ).copyWith(
    primary: seed,
    onPrimary: Colors.white,
    secondary: seed, // 次强调也跟主色，消除蓝紫固定色
    surface: AppTokens.surfaceLight,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppTokens.bgLight,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: _pageTransitions,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: AppTokens.inkLight,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusL)),
    ),
  );
}

ThemeData buildDarkTheme({Color seed = AppColors.primary}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF9AA0B4),
    brightness: Brightness.dark,
  ).copyWith(
    primary: seed,
    onPrimary: Colors.white,
    secondary: seed,
    surface: AppTokens.surfaceDark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppTokens.bgDark,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: _pageTransitions,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: AppTokens.inkDark,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusL)),
    ),
  );
}
```

顶部 import 区补 `import '../design_tokens.dart';`。

- [ ] **Step 2: 校验**

Run: `flutter analyze`
Expected: 0 error，0 warning（本轮 warning 应清零；若仍有，只允许来自尚未 sweep 的 feature 层，并记录）。

- [ ] **Step 3: Commit**

```bash
git add app/lib/core/theme/app_theme.dart
git commit -m "refactor(design): neutral color scheme, accent only as primary/secondary"
```

---

## Task 6: `glass.dart` 统一玻璃配方 + 动态光线接入

**Files:**
- Modify: `app/lib/core/glass/glass.dart`

**Interfaces:**
- Consumes: `AppTokens`、`LightController`。
- Produces: `GlassPanel` / `GlassTile` / `GlassBlur`、`lowEndDevice`、`advancedMaterialDisabled`、`glassBlurDisabled`、`recomputeGlassBlur()` 签名不变。

- [ ] **Step 1: 改 `recomputeGlassBlur` 联动光线**

把 `glass.dart` 顶部：

```dart
void recomputeGlassBlur() =>
    glassBlurDisabled.value = lowEndDevice || advancedMaterialDisabled;
```

改为：

```dart
void recomputeGlassBlur() {
  final disabled = lowEndDevice || advancedMaterialDisabled;
  glassBlurDisabled.value = disabled;
  LightController.setEnabled(!disabled); // 只有真·高级材质才开动态光线
}
```

文件顶部 import 加 `import 'light_controller.dart';` 与 `import '../design_tokens.dart';`。

- [ ] **Step 2: `GlassPanel._build` 用令牌 + 动态高光**

把 `_build` 里硬编码的 `fillGradient`/`borderColor`/`highlight` 全替换：

```dart
Widget _build(BuildContext context, bool blurDisabled) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final surface = Theme.of(context).colorScheme.surface;
  final blurOn = enableBlur && !blurDisabled;
  final fill = solid
      ? [surface, surface]
      : AppTokens.glassSurface(isDark, blurOn);
  final fillGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: fill,
  );
  final borderColor = AppTokens.glassBorder(isDark);

  Widget panel = Container(
    margin: margin,
    decoration: BoxDecoration(
      borderRadius: borderRadius,
      border: Border.all(color: borderColor, width: 1),
      gradient: fillGradient,
      boxShadow: [AppTokens.glassShadow(isDark)],
    ),
    child: Stack(
      children: [
        // 顶部镜面高光（方向随光线倾动）
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<Offset>(
              valueListenable: LightController.light,
              builder: (context, light, _) => DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: LinearGradient(
                    begin: Alignment(
                      light.dx * 0.6,
                      light.dy * 0.6 - 1.0,
                    ),
                    end: Alignment(
                      light.dx * 0.25,
                      light.dy * 0.25 - 0.3,
                    ),
                    colors: AppTokens.glassHighlight(isDark),
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: padding ?? const EdgeInsets.all(20),
          child: Material(color: Colors.transparent, child: child),
        ),
      ],
    ),
  );

  if (blurOn && !solid) {
    panel = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: panel,
      ),
    );
  }
  if (onTap != null) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: panel,
      ),
    );
  }
  return panel;
}
```

> 原高光顶边 `begin: topCenter, end: center, stops [0, 0.28]` 换成随光线方向旋转的渐变（`stops` 简化为 0→1）。`highlightStop` 令牌保留供后续精细调；此处用完整渐变覆盖即可。

- [ ] **Step 3: 校验**

Run: `flutter analyze`
Expected: 0 error

- [ ] **Step 4: Commit**

```bash
git add app/lib/core/glass/glass.dart
git commit -m "feat(design): unify glass recipe + integrate dynamic light"
```

---

## Task 7: `FlowingBackground` 中性化 + 响铃界面收编

**Files:**
- Modify: `app/lib/core/theme/animated_background.dart`
- Modify: `app/lib/features/alarm/alarm_ringing_screen.dart`

**Interfaces:**
- Consumes: `AppTokens`、`AppColors`（已无蓝紫）。
- Produces: `FlowingBackground` 签名不变。

- [ ] **Step 1: blob 去色相**

`animated_background.dart` 里 `_WavePainter` 的三处 `Color`：

```dart
final blobs = <(Offset, double, Color, double)>[
  (Offset(size.width * 0.15, size.height * 0.12), 200, AppColors.gradientStart, 0.0),
  (Offset(size.width * 0.88, size.height * 0.32), 240, AppColors.gradientEnd, 1.3),
  (Offset(size.width * 0.55, size.height * 0.9), 280, AppColors.secondary, 2.1),
];
```

改为中性（无蓝紫）：

```dart
final blobs = <(Offset, double, Color, double)>[
  (Offset(size.width * 0.15, size.height * 0.12), 200, Colors.white, 0.0),
  (Offset(size.width * 0.88, size.height * 0.32), 240, const Color(0xFFB9BECF), 1.3),
  (Offset(size.width * 0.55, size.height * 0.9), 280, Colors.white, 2.1),
];
```

顶部 import 去掉 `app_colors.dart`（已无需引用 AppColors）。

- [ ] **Step 2: 响铃界面硬编码色 → 令牌**

`alarm_ringing_screen.dart` 逐处替换（值见 spec §6）：

| 行 | 现值 | 换成 |
|---|---|---|
| `102` | `Color(0xFF0B0B14)` | `AppTokens.bgDark` |
| `185` | `Color(0xFFE2E2EC)`（胶囊文字） | `AppTokens.inkDark` |
| `266` | `Color(0xFF6E6E82)`（滑块图标未 armed） | `AppTokens.inkMutedDark` |
| `279` | `Color(0xFF9A9AB0)`（提示文字） | `AppTokens.inkMutedDark` |
| `178` | 胶囊 `Colors.white 0.14/0.04` | `AppTokens.glassTint(true, true)` |
| `179` | 胶囊边框 `Colors.white 0.18` | `AppTokens.glassBorder(true)` |

顶部 import 补 `../../core/design_tokens.dart`。

图标 Outlined：`Icons.snooze_rounded`→`Icons.snooze_outlined`、`Icons.check_rounded`→`Icons.check_outlined`、`Icons.keyboard_arrow_up_rounded`→`Icons.keyboard_arrow_up_outlined`。

排版令牌：`fontSize: 84`→`AppTokens.fontDisplayXl`、`fontSize: 17`→`AppTokens.fontBody`（响铃胶囊文字 17 本身接近正文，统一）、`fontSize: 12`→`AppTokens.fontCaption`、`fontSize: 18`→`AppTokens.fontHeading`。

- [ ] **Step 3: 校验**

Run: `flutter analyze`
Expected: 0 error，0 new warning

- [ ] **Step 4: Commit**

```bash
git add app/lib/core/theme/animated_background.dart app/lib/features/alarm/alarm_ringing_screen.dart
git commit -m "refactor(design): neutralize ambient bg, tokenize ringing screen"
```

---

## Task 8: 共享组件 sweep（一）按钮/动作按钮/按压

**Files:**
- Modify: `app/lib/core/widgets/glass_button.dart`
- Modify: `app/lib/core/widgets/glass_action_button.dart`
- Modify: `app/lib/core/widgets/glass_pressable.dart`

**Interfaces:** 三组件公开 API 不变；内部改用 `QScale`/令牌。

- [ ] **Step 1: `GlassButton`**

- 圆角 `BorderRadius.circular(20)` 全部 → `BorderRadius.circular(AppTokens.radiusM)`（共 4 处 + `ClipRRect`）。
- primary 渐变 `[primary.withValues(alpha:0.85), primary.withValues(alpha:0.50)]` → `AppTokens.accentGradient(primary).colors`；`border: primary 0.55` 保留 accent，但幂用 `AppTokens.accentGradient`。
- secondary（白玻璃）渐变对 `Colors.white 0.22/0.06`(dark) / `0.95/0.55`(light) → `AppTokens.glassTint(isDark, true)`；边框 `Colors.white 0.28/0.95` → `AppTokens.glassBorder(isDark)`。
- 按压 `AnimatedScale(_pressed?0.95:1.0, duration:120, curve:easeOutBack)` → `QScale(pressed: _pressed, scale: AppTokens.pressScale, child: …)`。
- 图标大小 `20` 保留（导航/按钮内图标另有 `AppIcon`，见 Task 12 落地——此处按钮内 icon 用 `IconThemeData(size:20)` 不变）。
- 顶部 import 补 `import '../../design_tokens.dart';`、`import '../../motion.dart';`。

- [ ] **Step 2: `GlassActionButton`**

- `static const _red = Color(0xFFE53935)` **删**，改 `AppTokens.danger`；danger 渐变 `_red 0.85/0.55`、边框 `_red 0.55`、阴影 `_red 0.30` 全用 `AppTokens.danger`。
- 圆角 `14` → `AppTokens.radiusM`；secondary 玻璃对 → `AppTokens.glassTint`/`glassBorder`；primary 渐变 → `AppTokens.accentGradient(primary).colors`，边框 `primary 0.55` 保留。
- 按压 `AnimatedScale(120ms easeOutBack 0.95)` → `QScale(pressed:_pressed, scale:AppTokens.pressScale, …)`。

- [ ] **Step 3: `GlassPressable`**

- `AnimatedScale(120ms easeOutBack, _pressed?widget.pressedScale:1.0)` → `QScale(pressed:_pressed, scale:widget.pressedScale, child: …)`（`pressedScale` 默认 0.97 保留）。

- [ ] **Step 4: 校验**

Run: `flutter analyze` + `flutter test`
Expected: 0 error / 0 warning；test 6/6

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/widgets/glass_button.dart app/lib/core/widgets/glass_action_button.dart app/lib/core/widgets/glass_pressable.dart
git commit -m "refactor(design): spring press + tokens for buttons/pressable"
```

---

## Task 9: 共享组件 sweep（二）开关/弹窗/删除/输入

**Files:**
- Modify: `app/lib/core/widgets/glass_switch.dart`
- Modify: `app/lib/core/widgets/glass_dialog.dart`
- Modify: `app/lib/core/widgets/glass_delete_button.dart`
- Modify: `app/lib/core/widgets/glass_input.dart`

- [ ] **Step 1: `GlassSwitch`**

- 关闭态轨道色 `Colors.white 0.10/0.70` → 用 `AppTokens.glassBorder(isDark).withValues(alpha: 0.6)` 近似浅灰（保留开关「轨道比面板略淡」的观感）；边框 `Colors.white 0.20/0.65` → `AppTokens.glassBorder(isDark)`。
- `AnimatedContainer(duration:200)` → `AppTokens.durMed`；`AnimatedAlign(duration:240, easeOutBack)` → `AppTokens.durMed` + `Curves.easeOutBack`（开关 thumb 弹跳保留曲线，不需改弹簧，因 `AnimatedAlign` 无弹簧）。圆钮阴影 `black 0.18 blur 4` 保留。

- [ ] **Step 2: `GlassDialog`**

- 圆角 `BorderRadius.circular(24)` → `AppTokens.radiusXL`；标题条 `width:4,height:18` 保留、圆角 `circular(2)` → `AppTokens.radiusS`（描边小角）。
- 阴影 `black 0.25 blur 32` 保留（弹窗专属大阴影像）；`surface` 底保留。
- `_GlassCloseButton` 玻璃渐变对 `Colors.white 0.22/0.06 / 0.95/0.55` → `AppTokens.glassTint`；边框 → `AppTokens.glassBorder`；`Icons.close_rounded` → `Icons.close_outlined`。
- 标题 `fontSize:18, w700` → `AppTokens.fontHeading`。

- [ ] **Step 3: `GlassDeleteButton`**

- `static const _red = Color(0xFFE53935)` → `AppTokens.danger`（渐变/边框/阴影/icon 色全换）。
- `Icons.delete_outline_rounded` 保留（本就线性）。

- [ ] **Step 4: `GlassInput`**

- `fillColor` 白 `0.06/0.72` → `AppTokens.glassSurface(isDark, true).first`（单色填充取高层）。
- 圆角 `14` → `AppTokens.radiusM`；边框 `Colors.white 0.14/0.65` → `AppTokens.glassBorder(isDark).withValues(alpha: 0.8)`。

- [ ] **Step 5: 校验**

Run: `flutter analyze` + `flutter test`
Expected: 0/0，test 6/6

- [ ] **Step 6: Commit**

```bash
git add app/lib/core/widgets/glass_switch.dart app/lib/core/widgets/glass_dialog.dart app/lib/core/widgets/glass_delete_button.dart app/lib/core/widgets/glass_input.dart
git commit -m "refactor(design): tokenize switch/dialog/delete/input"
```

---

## Task 10: 共享组件 sweep（三）分段/提示条/弹层

**Files:**
- Modify: `app/lib/core/widgets/glass_segment.dart`
- Modify: `app/lib/core/widgets/glass_snackbar.dart`
- Modify: `app/lib/core/widgets/glass_pickers.dart`

- [ ] **Step 1: `GlassSegment`**

- 胶囊底 `color: Colors.white 0.07/0.72`、边框 `0.14/0.65` → `AppTokens.glassTint` 单色（取 `.first` 或保留浅灰近似）与 `AppTokens.glassBorder`。
- 滑块 `AnimatedPositioned(duration:140)` → `AppTokens.durFast`；`AnimatedScale(180ms easeOutBack, _pressed?1.08:1.0)` → `QScale(pressed:_pressed, scale:AppTokens.pillGrow, child: …)`。
- 滑块渐变 `activeColor 0.9/0.62` → `AppTokens.accentGradient(activeColor).colors`；阴影 `activeColor 0.32` 保留。

- [ ] **Step 2: `GlassSnackbar`**

- `ClipRRect`/`Container`/`foregroundDecoration` 圆角 `20` → `AppTokens.radiusL`。
- 玻璃渐变对 `Colors.white 0.18/0.05 / 0.82/0.48` → `AppTokens.glassTint(isDark, true)`；边框 → `AppTokens.glassBorder`；阴影 `black 0.35/0.12 blur 14` → 用 `AppTokens.glassShadow(isDark)`。
- 高光 `foregroundDecoration` 渐变色 → `AppTokens.glassHighlight(isDark)`，`stops [0.0, 0.28]` → 保留 stop（提示条固定顶光，不随倾动）。
- 文字 `fontSize:14, w600` → `AppTokens.fontBody`；图标 `size:18` 保留。

- [ ] **Step 3: `GlassPanel` 弹层（`glass_pickers.dart`）**

- 全文件 `glass_pickers.dart` 里的 `borderRadius`/`Duration` 按全局映射表替换：`circular(14/16/20)` → 对应档；`Duration(milliseconds:N)` → `durFast/Med/Slow`。
- `showGlassTimePicker/showGlassDatePicker/showGlassMonthPicker` 底部弹层已用 `solid:true`，`glass_pickers` 内部 `GlassPanel(solid:true)` 保留；仅收敛圆角/时长与 `chevron_*_rounded` → `chevron_*_outlined`。

- [ ] **Step 4: 校验**

Run: `flutter analyze` + `flutter test`
Expected: 0/0，6/6

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/widgets/glass_segment.dart app/lib/core/widgets/glass_snackbar.dart app/lib/core/widgets/glass_pickers.dart
git commit -m "refactor(design): tokenize segment/snackbar/pickers"
```

---

## Task 11: 图标包装 `AppIcon`

**Files:**
- Create: `app/lib/core/widgets/app_icon.dart`
- Test: `app/test/app_icon_test.dart`

**Interfaces:**
- Produces: `class AppIcon`（`{required IconData icon, double size = 20, Color? color}`）。

- [ ] **Step 1: 写失败测试**

```dart
// app/test/app_icon_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/widgets/app_icon.dart';

void main() {
  testWidgets('AppIcon 渲染给定 size', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AppIcon(icon: Icons.alarm_outlined, size: 22),
    ));
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.size, 22);
    expect(icon.icon, Icons.alarm_outlined);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/app_icon_test.dart`
Expected: FAIL

- [ ] **Step 3: 写实现**

```dart
// app/lib/core/widgets/app_icon.dart
import 'package:flutter/material.dart';

/// 统一图标包装：默认 outlined 线性 + 统一尺寸，杜绝到处 `Icon(... size: n)`。
class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.icon, this.size = 20, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Icon(icon, size: size, color: color);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/app_icon_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/widgets/app_icon.dart app/test/app_icon_test.dart
git commit -m "feat(design): add AppIcon wrapper"
```

---

## Task 12: `home_shell.dart` 导航 + 底部胶囊

**Files:**
- Modify: `app/lib/features/home/home_shell.dart`

- [ ] **Step 1: 导航图标 Outlined**

`_items` 四处：

```dart
(Icons.calendar_month_rounded, L10n.navCalendar),
(Icons.alarm_rounded, L10n.navAlarm),
(Icons.event_note_rounded, L10n.navTodo),
(Icons.person_rounded, L10n.navProfile),
```

改为 `_outlined`：`calendar_month_outlined` / `alarm_outlined` / `event_note_outlined` / `person_outlined`。

- [ ] **Step 2: 导航选中滑块改跟主色**

`_GlassNavBarState.build` 滑块 `Container` 装饰里：

```dart
colors: [
  AppColors.gradientStart.withValues(alpha: isDark ? 0.32 : 0.20),
  AppColors.gradientEnd.withValues(alpha: isDark ? 0.26 : 0.14),
],
```

改为：

```dart
colors: AppTokens.accentGradient(activeColor).colors,
```

（`activeColor` 本函数顶部已取 `colorScheme.primary`。）

- [ ] **Step 3: 胶囊玻璃 + 圆角 + 弹簧**

- 外胶囊圆角 `BorderRadius.circular(30)` → `BorderRadius.circular(widget.height / 2)`（胶囊语义）；滑块圆角 `circular(24)` → `AppTokens.radiusL`。
- 底部胶囊 `Container` 玻璃渐变对 `Colors.white 0.18/0.08 / 0.58/0.24` → `AppTokens.glassTint(isDark, true)`；边框 `Colors.white 0.16/0.65` → `AppTokens.glassBorder(isDark)`。
- `AnimatedScale(180ms easeOutBack, _pressed?1.04:1.0)` → `QScale(pressed:_pressed, scale:AppTokens.pillGrow, child:…)`；`AnimatedPositioned(duration:_dragging?zero:140)` → `_dragging ? Duration.zero : AppTokens.durFast`。
- 图标 `Icon(..., size:22)` → `Icon(..., size:22)` 保留 22（导航图标定 22）；选中色 `activeColor`、未选中 `inactiveColor` 逻辑不动。
- 顶部 import 补 `../../core/design_tokens.dart`、`../../core/motion.dart`（`app_colors.dart` 中 `gradientStart/End` 已删，`AppColors` 可能不再被引用，留意 import 冗余）。

- [ ] **Step 4: 校验**

Run: `flutter analyze` + `flutter test`
Expected: 0/0，6/6

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/home/home_shell.dart
git commit -m "refactor(design): neutralize nav capsule, accent-follow active pill, outlined icons"
```

---

## Task 13: 日历三页 sweep

**Files:**
- Modify: `app/lib/features/calendar/calendar_screen.dart`
- Modify: `app/lib/features/calendar/schedule_editor_screen.dart`
- Modify: `app/lib/features/calendar/schedule_management_screen.dart`

- [ ] **Step 1: 硬编码色收编（已知）**

`calendar_screen.dart:17` `_holidayRed = Color(0xFFE53935)` → 删常量，改 `AppTokens.holiday`（该常量在 `_holidaySpans` 标红处使用，一并替换引用）。

`schedule_editor_screen.dart` 里的 9 处 `0xFF…` 是**班次类型色板**（白班蓝/夜班紫等），属功能数据色，**保留原值不动**，仅确认未混入 UI 装饰色（若出现 `0xFFE53935` 删除红，改 `AppTokens.danger`）。

- [ ] **Step 2: 图标 Outlined**

按全局映射表替换本三文件内 `Icons.*_rounded` → `_outlined`（`add_rounded`/`check_circle_rounded`/`swap_horiz_rounded`/`swap_vert_rounded`/`chevron_*_rounded`/`today_rounded`/`edit_rounded`/`event_rounded`/`check_rounded`/`access_time_rounded`/`add_circle_outline_rounded`/`remove_circle_outline_rounded`）；`circle_outlined`（`calendar_screen.dart:360`）已是线性，保留。

- [ ] **Step 3: 圆角/时长/字号 sweep**

按全局映射表，用 `grep` 逐文件定位并替换 `BorderRadius.circular(N)`、`Duration(milliseconds:N)`、散落 `fontSize : 14.5/13.5/12.5`（→ 最邻近令牌 `fontBody/fontCaption`）。

Run 定位：
```bash
grep -rn "circular(\|Duration(milliseconds\|fontSize: *1[0-9]*\.5" app/lib/features/calendar/
```

- [ ] **Step 4: 校验**

Run: `flutter analyze` + `flutter test`
Expected: 0/0，6/6

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/calendar/
git commit -m "refactor(design): tokenize calendar screens"
```

---

## Task 14: 闹钟页 + 待办页 sweep

**Files:**
- Modify: `app/lib/features/alarm/alarm_screen.dart`
- Modify: `app/lib/features/schedule/schedule_screen.dart`

- [ ] **Step 1: 硬编码色收编（闹钟页）**

| 行 | 现值 | 换成 |
|---|---|---|
| `339` | `Color(0xFF4ADE80)`（测试成功 icon） | `AppTokens.success` |
| `348` | `Color(0xFFF87171)`（测试失败 icon） | `AppTokens.danger` |

- [ ] **Step 2: 图标 Outlined**

`alarm_screen.dart`：`Icons.add_rounded`→`add_outlined`、`Icons.bolt_rounded`→`bolt_outlined`、`Icons.check_circle_rounded`→`check_circle_outlined`、`Icons.error_rounded`→`error_outlined`。
`schedule_screen.dart`：`Icons.add_rounded`→`add_outlined`。

- [ ] **Step 3: 圆角/时长 sweep**

`alarm_screen.dart` 里 `_showAlarmDialog` 的星期选择 `AnimatedContainer(duration:180, easeOutBack)` 换 `QScale`（或至少 `duration`→`AppTokens.durMed`，把 `AnimatedContainer` 换为 `AnimatedScale`+`QScale` 优先）；`BorderRadius.circular(20)` → `AppTokens.radiusL`（星期 chip）。
`schedule_screen.dart` 逐处按映射表替换圆角/时长/字号。

- [ ] **Step 4: 校验**

Run: `flutter analyze` + `flutter test`
Expected: 0/0，6/6

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/alarm/alarm_screen.dart app/lib/features/schedule/schedule_screen.dart
git commit -m "refactor(design): tokenize alarm + todo screens"
```

---

## Task 15: 我的页 + 弹窗 sweep + 更新日志

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart`
- Modify: `app/lib/features/profile/app_dialogs.dart`

- [ ] **Step 1: 硬编码色收编**

`profile_screen.dart` `177`/`264` 两处 `Color(0xFFE53935)` → `AppTokens.danger`。

- [ ] **Step 2: 图标 Outlined**

`profile_screen.dart` 大量权限卡图标：`battery_saver_rounded`/`power_settings_new_rounded`/`fullscreen_rounded`/`aspect_ratio_rounded`/`alarm_on_rounded`/`alarm_off_rounded`/`notifications_off_rounded`/`notifications_active_rounded`/`music_note_rounded`/`play_circle_outline_rounded`/`alarm_rounded`/`content_copy_rounded`/`check_circle_rounded`/`error_outline_rounded`/`bug_report_rounded`/`help_outline_rounded`/`new_releases_rounded`/`system_update_rounded`/`info_outline_rounded`/`delete_sweep_rounded`/`chevron_right_rounded`/`tune_rounded` 等：凡有 `_outlined` 变体的换 `_outlined`，已是 `*_outline_rounded` 的一律保留。
`app_dialogs.dart` 的 `system_update_rounded`/`shield_rounded`/`event_note_rounded`/`alarm_rounded`/`tune_rounded`/`calendar_month_rounded` → 换 `_outlined` 变体。

- [ ] **Step 3: 圆角/时长 sweep**

按映射表 grep 替换两文件 `circular(N)` 与 `Duration(milliseconds:N)`。

- [ ] **Step 4: 校验**

Run: `flutter analyze` + `flutter test`
Expected: 0/0，6/6

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/profile/
git commit -m "refactor(design): tokenize profile screens"
```

---

## Task 16: 版本号 + 更新日志

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/core/app_info.dart`
- Modify: `app/lib/features/profile/app_dialogs.dart`

- [ ] **Step 1: 版本号两处同步**

`app/pubspec.yaml`：`version: 0.4.3+63` → `version: 0.4.4+64`。
`app/lib/core/app_info.dart`：`'0.4.3'` → `'0.4.4'`。

- [ ] **Step 2: 更新日志 prepend（zh / en 各一条）**

`app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh` / `_changelogEn` 顶部各插一条，删掉各自最末一条（保持 10 条）。

`_changelogZh` 新条目（测试版，只写本版）：

```
v0.4.4：视觉大一统——极简黑白背景(自动深浅)+ 5 色主色只染强调点，液态玻璃统一配方并新增随手机倾斜流动的动态光线，图标统一线性，动效全面换弹簧 Q 弹。
```

`_changelogEn` 新条目（同义英文）：

```
v0.4.4: Unified visual language — monochrome light/dark background, accent color confined to interactive highlights, unified glass recipe with tilt-reactive dynamic light, outlined icons, spring-based motion throughout.
```

（若现有条目长度的结构是「版本号换行 + 描述换行」的嵌套结构，按现有格式插入同等结构；执行时先读 `_changelogZh`/`_changelogEn` 顶部 5 条对齐格式。）

- [ ] **Step 3: Commit + tag**

```bash
git add app/pubspec.yaml app/lib/core/app_info.dart app/lib/features/profile/app_dialogs.dart
git commit -m "chore: v0.4.4 version bump + changelog"
git tag v0.4.4
```

---

## Task 17: 全量验收

- [ ] **Step 1: 静态检查**

Run: `flutter analyze`
Expected: `0 errors · 0 warnings`（可容忍少量既有 info，但不得新增 error/warning）

- [ ] **Step 2: 单测**

Run: `flutter test`
Expected: 全部通过（`shift_rotation_test` 6 项 + 新增 `design_tokens_test`/`motion_test`/`light_controller_test`/`app_icon_test`）

- [ ] **Step 3: 视觉抽查（真机/模拟器）**

构建并安装后，逐项过：
- 亮色 × 5 主色、暗色 × 5 主色：背景皆中性，导航选中/按钮/开关随主色变。
- 倾斜手机：玻璃高光有流动（真机）；低端机/关「高级材质」：静态高光、无崩溃。
- 图标全线性、圆角/字号肉眼协调。

（构建命令，若需：`. C:/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/tools/build-env.ps1` 后 `flutter build apk --release --target-platform android-arm64`）

- [ ] **Step 4: 提交最终结果**

```bash
git add -A
git commit -m "feat(design): unify design language + redesign (v0.4.4)"
```

---

## 自检结论

- **Spec 覆盖**：§3 令牌 → Task 1；§3.1 颜色/语义 → Task 1/2/13-15；§3.2 玻璃配方 → Task 1/6；§3.3 圆角 → 映射表 + Task 8-15；§3.4 间距 → Task 1；§3.5 动效弹簧 → Task 3 + 8-12；§3.6 图标 → Task 11 + 12-15；§3.7 排版 → Task 1 + sweep；§4 中性主题 → Task 5；§5 动态光线 → Task 4/6/7；§6 迁移 → Task 8-15；§8 范围外在 Global Constraints 明列；§9 验收 → Task 17；§10 版本日志 → Task 16。
- **无占位符**：所有新增文件/关键重构给了完整代码；sweep 用「精确现值 → 令牌」映射表 + grep 定位，非模糊描述。
- **类型一致**：`AppTokens.accentGradient` / `glassTint` / `glassBorder` / `QScale` / `LightController.light` 在定义任务与消费任务中命名一致。