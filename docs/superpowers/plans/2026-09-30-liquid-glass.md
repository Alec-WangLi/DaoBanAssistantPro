# 液态玻璃（标准 / 液态两档）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「高级材质」这颗只能让画面变差的开关，改成在「标准（磨砂玻璃 + 真实饱和度）」与「液态（边缘折射）」之间选品质档位的开关；省电档保留，但只由低内存自动进入。

**Architecture:** 不引入任何第三方依赖。阶段 1 用 `ImageFilter.compose` 把一张 Rec.709 饱和度矩阵（`ColorFilter`，它本身就是 `ImageFilter`）与现有的 `ImageFilter.blur` 合成一个 filter —— 补上 `glass.dart` 注释里一直写着「近似」的那个缺口。阶段 2 加一个自己的 `.frag`，用同一个 `compose` 叠在模糊外面做折射 / 色散 / 边缘光，并由一个四条件的「与」闸门控制是否生效。阶段 3 是出图之后对那 18 处 `enableBlur: false` 的复查，不在本次实现范围。

**Tech Stack:** Flutter 3.47.2 / Dart 3.13.2（`app/`），`dart:ui` 的 `ImageFilter` / `FragmentShader` / `FragmentProgram`，Riverpod，自研视觉工装（`app/tool/visual/`）。

**Spec:** `docs/superpowers/specs/2026-09-30-liquid-glass-design.md`（已提交 `577cb1f`）

## Global Constraints

- **不引入任何第三方依赖**：`app/pubspec.yaml` 的 `dependencies:` / `dev_dependencies:` 一行都不许加。参考实现（`liquid_glass_widgets` / Prismal）只读不装。唯一允许的 pubspec 改动是新增 `flutter:` 下的 `shaders:` 声明。
- **版本号**：`X.Y` 由用户决定，AI 只改末位 `Z` 与 `build`。每阶段收尾时 `app/pubspec.yaml` 的 `version` 与 `app/lib/core/app_info.dart` 的 `appVersion` **两处同步**（`app/test/app_info_test.dart` 盯着）。
- **分支**：三个阶段都是测试版（`Z ≠ 0`），一律在 **`beta`** 分支做与提交。
- **验收**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿且**条数只增不减**（当前 **541** 条）；视觉工装 `flutter test tool/visual/` 全绿（当前 **270** 条）。
- **文案**：任何用户可见文案都要中英双语、写在 `app/lib/core/l10n.dart`，且副标题写**「不开会怎样」**（v0.8.0 ⑤ 定的）。
- **新观感必须进屏单**：`app/tool/visual/visual_screens.dart`（仓库家法 —— v0.8.1 四处跑偏、v0.9.14 / v0.9.18 两次靠屏单抓出真 bug）。
- **不要跑 `dart format`**（工具链是新版 tall style，会重排整个文件）。只跑 `flutter analyze`。
- 本计划**不动 Drift 表**，不需要 `build_runner`。
- 构建前在本沙箱先 `. C:\...\shiftassistant\tools\build-env.ps1`；bash 里构建要按记忆 `build-env-vars` 设 `ANDROID_HOME` / `JAVA_HOME` / `GRADLE_USER_HOME`。

## Review Focus

以下是规格隐含、但没有哪个任务的测试会覆盖到的失败模式。每一条都已在 owning task 里挂了对应断言或在真机验收里点名。

1. **低内存机器（`lowEndDevice == true`）的用户主动打开「液态玻璃」** —— 期望：仍停在省电档（不糊），不崩、不闪、不出现半糊半液态的中间态。这是「省电档是地板」那句话的唯一验金石。
2. **shader 资源加载失败或后端不支持**（pubspec 路径写错 / 编进包但加载抛错 / Windows 旧驱动走 Skia 回退）—— 期望：静默回落到**标准**，不黑屏、不崩。`ImageFilter.shader` 在非 Impeller 下抛的是 `UnsupportedError`，是真崩。
3. **同一个 `FragmentShader` 实例被多个 `BackdropFilter` 同时使用** —— 期望：各自渲染正确、互不串扰。这是本设计里唯一「不确定引擎怎么处理」的地方，必须真机看。
4. **用户开过液态之后点「我的 → 清空重置」** —— 期望：回到**标准**（外观那一组拨回默认），而不是停在液态。
5. **系统开「降低透明度」/ 切到 teal·orange·rose 主色** —— 期望：不崩；且实心主色上的白字对比度**不因液态档而变差**（仓库已知有一处开着的 AA 问题，别推得更糟）。

---

## 文件结构

| 文件 | 职责 | 阶段 |
|---|---|---|
| `app/lib/core/glass/glass.dart` | 三档判据（模块级 `ValueNotifier`）+ `GlassPanel` / `GlassBlur` 的 filter 装配 | 1、2 |
| `app/lib/core/design_tokens.dart` | 新增饱和度矩阵常量（**不**在守门扫描目录里，零风险） | 1 |
| `app/lib/state/app_settings.dart` | `advancedMaterial` → `liquidGlass`，默认 false，新键 | 2 |
| `app/lib/main.dart` | 加载 shader、调用改名 | 2 |
| `app/lib/core/l10n.dart` | 行名 + 副标题 + 使用帮助条目 + `clearAll` 确认框（中英各四句） | 2 |
| `app/lib/features/profile/profile_screen.dart` | 那一行绑到新字段 | 2 |
| `app/pubspec.yaml` | 仅新增 `shaders:` 声明 | 2 |
| `app/shaders/liquid_glass.frag` | 折射 / 色散 / 边缘光（**新建**） | 2 |
| `app/test/glass_tier_test.dart` | 三档判据（**新建**） | 1、2 |
| `app/test/glass_saturation_test.dart` | 饱和度真的作用到像素上（**新建**） | 1 |
| `app/tool/visual/visual_harness.dart` | 加两个把档位拨到指定状态的工具函数 | 1、2 |
| `app/tool/visual/visual_screens.dart` `render_screens_test.dart` | 补屏 | 1、2 |
| `app/test/factory_reset_test.dart` | **既有用例要改**：断言 `advancedMaterial` 为真 → 改为新字段为假 | 2 |

---

# 阶段 1：真实饱和度

> 独立成版、独立可回退。零依赖、零 shader、无构建链改动。若这一版做完已经够「润」，阶段 2 可以不做。

### Task 1: 冒烟探针 —— 证明 `ColorFilter` 嵌进 `BackdropFilter` 真的出图

**为什么单独成任务：** `ColorFilter implements ImageFilter`（`sky_engine/lib/ui/painting.dart:4073`）是类型层面的事实，但**本仓库从来没有跑过这条路**。规格把阶段 1 定性为「极低风险」，这个判断**要先被证明**才成立。探针失败的话，整个设计的装配方式都要换，所以它必须挡在最前面。

**Files:**
- Create: `app/test/glass_saturation_test.dart`
- 不改任何 `lib/` 文件

**Interfaces:**
- Consumes: 无
- Produces: 一个结论（可行 / 不可行）。可行则后面所有任务照本计划走；**不可行则停下来报告，不要改设计自己往下做**。

- [ ] **Step 1: 写像素级断言（这是本任务唯一有鉴别力的证据）**

在 `app/test/glass_saturation_test.dart` 里建一个「已知底色 + 一层玻璃」的拼装，光栅化后读像素：

```dart
testWidgets('ColorFilter 作为 ImageFilter 嵌进 BackdropFilter 后，像素真的被提饱和',
    (tester) async {
  // 底色用一个低饱和的中间色（灰蓝），玻璃盖在它上面
  // 玻璃的 filter = ImageFilter.compose(outer: blur(0), inner: ColorFilter.matrix(_boost))
  // 断言：玻璃内一块像素的 (max-min) 通道差 > 未加 ColorFilter 时的对应值
});
```

要点：`blur` 用 `sigma: 0`，把「模糊」这个变量摘掉，只留饱和度；`toImage` 与读像素必须放在 `tester.runAsync` 里（工装 `visual_harness.dart:865-871` 的注释写了原因：伪造时钟区里的真异步 future 不会完成）。

- [ ] **Step 2: 跑它，确认它现在**失败**

Run: `flutter test test/glass_saturation_test.dart -v`
Expected: FAIL（像素差没有变大）

- [ ] **Step 3: 把它写成真的**

把 `ColorFilter.matrix` 换成单位矩阵（`[1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0]`）再跑一次 —— **应当仍然 FAIL**。这一步是**反向验证**：确认这条断言测的是饱和度而不是「有没有颜色」。若单位矩阵也 PASS，说明断言写松了，回去改。

- [ ] **Step 4: 在真机上看一眼**

工装出图（用 Task 2 之后的状态也行，此处先手改一个 `sigma: 0` + 强饱和的临时屏）：

```bash
flutter test tool/visual/render_screens_test.dart --plain-name '日历 · 浅色'
```

看 `app/build/visual/01_calendar_light.png`：**不能是纯黑、不能透明、不能整块变灰**。

- [ ] **Step 5: 记录结论并提交**

可行 → 继续 Task 2。不可行 → 停在此处，把现象（像素值 / 截图 / 异常栈）报告给用户，**不要自行改设计**。

```bash
git add app/test/glass_saturation_test.dart
git commit -m "test(glass): 证明 ColorFilter 嵌进 BackdropFilter 真的出图"
```

---

### Task 2: 饱和度矩阵令牌 + `GlassPanel` 接入（含与现有渐变对账）

**Files:**
- Modify: `app/lib/core/design_tokens.dart`（在「玻璃配方」那一段，`glassTint` 之前）
- Modify: `app/lib/core/glass/glass.dart:95-103`（`_build` 里那个 `if (blurOn && !solid)` 分支）

**Interfaces:**
- Consumes: Task 1 的结论
- Produces:
  - `AppTokens.glassSaturation` —— `static const ColorFilter`（Rec.709 保亮度矩阵，`s = 1.2`）
  - `ImageFilter glassFilter(double sigma)` —— 顶层函数，**这个签名是阶段 2 的接入点**

- [ ] **Step 1: 写失败测试**

在 `app/test/glass_tier_test.dart`（本任务新建）里：

```dart
testWidgets('标准档：GlassPanel 的 BackdropFilter 里含饱和度矩阵', (tester) async {
  // 装配一个 GlassPanel，找到 BackdropFilter，断言它的 filter 是
  // _ComposeImageFilter 且内层是 ColorFilter —— 不能只有 blur。
});
```

判据走「装配出来的 filter 不是裸的 `ImageFilter.blur`」：比较 `filter.toString()` 含 `ColorFilter` 字样，或直接对 `identical(filter, ImageFilter.blur(...))` 取反。**别断言私有类型名**（`_ComposeImageFilter` 不稳）。

- [ ] **Step 2: 跑它，确认失败**

Run: `flutter test test/glass_tier_test.dart -v`
Expected: FAIL（当前 filter 只有 blur）

- [ ] **Step 3: 加令牌**

在 `app/lib/core/design_tokens.dart` 的玻璃配方段加：

```dart
/// Rec.709 保亮度饱和度矩阵，s = 1.2。中性灰保持不动（三行各自加和为 1）。
///
/// 这是玻璃**被看穿的背景**那一层的处理 —— 真实液态玻璃后面的东西不只是变糊，
/// 还更浓、更艳。这一条以前是用 glassTint / glassSurface 那层白渐变「近似」的
/// （见 glass.dart 的注释），现在是真的，所以那两个函数的 alpha 要跟着收
/// （见 Task 3 的对账）。
static const ColorFilter glassSaturation = ColorFilter.matrix(<double>[
  1.15748, -0.14304, -0.01444, 0, 0,   // R
  -0.04252, 1.05696, -0.01444, 0, 0,   // G
  -0.04252, -0.14304, 1.18556, 0, 0,   // B
  0, 0, 0, 1, 0,                       // A
]);
```

矩阵由 `Lr=0.2126 / Lg=0.7152 / Lb=0.0722`、`1-s = -0.2` 算出。**三行各自加和必须为 1**（中性灰不变），这是唯一的自检。

- [ ] **Step 4: 加装配函数并接进 `GlassPanel`**

在 `app/lib/core/glass/glass.dart` 加顶层函数：

```dart
/// 玻璃的完整 filter。阶段 2 会在这里按档位分叉。
ImageFilter glassFilter(double sigma) => ImageFilter.compose(
      outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      inner: AppTokens.glassSaturation,
    );
```

把 `glass.dart:98-100` 的 `ImageFilter.blur(...)` 换成 `glassFilter(blurSigma)`。

- [ ] **Step 5: 跑测试，确认通过**

Run: `flutter test test/glass_tier_test.dart test/glass_saturation_test.dart -v`
Expected: PASS

- [ ] **Step 6: 跑守门测试**

Run: `flutter test test/design_tokens_test.dart -v`
Expected: PASS。`design_tokens.dart` 不在守门扫描目录（`_scanDirs` 只含 `lib/features` / `lib/core/widgets` / `lib/core/glass` / `lib/core/theme`），而 `glass.dart` 只多了一个函数调用、没有新字面量 —— 若仍报红，按仓库惯例用 `// design-tokens-ignore: <理由>`，**不许放宽正则**。

- [ ] **Step 7: 提交**

```bash
git add app/lib/core/design_tokens.dart app/lib/core/glass/glass.dart app/test/glass_tier_test.dart
git commit -m "feat(glass): 玻璃背景改用真实饱和度矩阵（Rec.709，s=1.2）"
```

---

### Task 3: `GlassBlur` 接入 + 与现有「近似饱和度」渐变对账

**Files:**
- Modify: `app/lib/core/glass/glass.dart:165-168`（`GlassBlur.build` 里那个 `BackdropFilter`）
- Modify: `app/lib/core/design_tokens.dart:166-189`（`glassTint` / `glassSurface` 的 alpha）

**Interfaces:**
- Consumes: Task 2 的 `glassFilter(double)`
- Produces: 无新接口

- [ ] **Step 1: 接进 `GlassBlur`**

`GlassBlur` 现在是「关闭时直接返回 child，开启时套一层 `BackdropFilter`」。把它的 filter 也换成 `glassFilter(sigma)`。**保持 `glassBlurDisabled` 的短路行为不变**（关掉时不该多一层 filter）。

- [ ] **Step 2: 出图，做对账**

```bash
flutter test tool/visual/render_screens_test.dart
```

逐张比对 `app/build/visual/01_calendar_{light,dark}.png`、`00_home_shell_{light,dark}.png`。

**要判断的只有一件事：饱和度是不是被算了两次。** 现在 `glassTint` / `glassSurface` 用一层半透明白渐变在「近似」饱和度，而真的矩阵已经加上去了 —— 白色叠加会让整体**变淡**，与提饱和**方向相反**，两者相抵会看不出效果。

判断与动作：
- 若图里玻璃后面**看不出更浓更艳** → 把 `glassTint` / `glassSurface` 在 `blurOn == true` 那一支的 alpha **收 20%~30%**（只改 `blurOn ? a : b` 里 `a` 那些值，`b`（省电档）**一个数都不许动** —— 那是省电档的观感，改了会破坏「低内存机器行为一字不变」）。
- 若已经明显 → 不动。

- [ ] **Step 3: 补屏单**

按仓库家法，这一轮的新观感要进屏单。**不需要新增屏**（改的是已有屏的观感），但要在 `app/tool/visual/visual_harness.dart` 里加一个工具函数，供阶段 2 与对比度审计复用：

```dart
/// 把玻璃拨到「标准」档（默认档）：省电关、液态关。
void useStandardGlassTier() { ... }
```

并在 `ensureVisualFonts()` 现在那三行（`advancedMaterialDisabled = false; lowEndDevice = false; recomputeGlassBlur();`，`visual_harness.dart:158-161`）处改成调用它 —— 阶段 2 会把它和 `useLiquidGlassTier()` 并列。

- [ ] **Step 4: 全量验收**

```bash
flutter analyze
flutter test
flutter test tool/visual/
```
Expected: analyze 0 error / 0 warning；`flutter test` ≥ 541 条全绿（本阶段新增 2 条以上）；工装 270 条全绿。

- [ ] **Step 5: 收尾提交 + 发测试版**

按 Global Constraints 升版本（`Z` 递增、`build` +1，两处同步）、更新日志 prepend + 删最旧一条。然后走仓库发布链路（`beta` 分支 → tag → `scripts/release.ps1 -SkipConfirm`）。

```bash
git add -A && git commit -m "chore(release): vX.Y.Z（玻璃改用真实饱和度）"
```

---

# 阶段 2：液态档

> 依赖阶段 1。新增 shader 构建链。**默认翻转 + 文案**必须与 shader 同版落地，否则开关会指向一个不存在的效果。

### Task 4: shader 基础设施 —— 能被加载、能出图

**Files:**
- Create: `app/shaders/liquid_glass.frag`
- Modify: `app/pubspec.yaml`（`flutter:` 段下新增 `shaders:`）
- Modify: `app/lib/main.dart`
- Modify: `app/lib/core/glass/glass.dart`

**Interfaces:**
- Consumes: `glassFilter(double)`
- Produces:
  - `FragmentShader? liquidGlassShader` —— 顶层可空变量（`glass.dart`）
  - `bool Function() shaderFilterSupported` —— 顶层可覆盖判据（测试注入用）
  - `ImageFilter glassFilter(double sigma)` 改为按档位分叉

- [ ] **Step 1: 写最小 shader**

`app/shaders/liquid_glass.frag`。**第一版只做「原样输出」**——先证明管线通，再做效果：

```glsl
#version 460 core
#include <flutter/runtime_effect.glsl>

// 第一个 uniform 必须是 vec2，由引擎填入绑定纹理的尺寸
uniform vec2 uSize;
// 第一个 sampler 由引擎自动绑定为 filter 的输入（模糊过的那张 backdrop）
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  fragColor = texture(uTexture, uv);
}
```

**注意**：Impeller 的 GLES 后端 y 轴是反的。现在就写进去，别等出图发现倒置：

```glsl
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
```

- [ ] **Step 2: 声明资源**

`app/pubspec.yaml` 的 `flutter:` 段下（与 `uses-material-design: true` 同级）加：

```yaml
  shaders:
    - shaders/liquid_glass.frag
```

- [ ] **Step 3: 在 `main()` 里加载**

`app/lib/main.dart`，在 `runApp` 之前、`recomputeGlassTiers()` 之前：

```dart
try {
  final program = await FragmentProgram.fromAsset('shaders/liquid_glass.frag');
  liquidGlassShader = program.fragmentShader();
} catch (_) {
  // 加载不了就是没有液态档。别抛 —— 这个 App 的玻璃是装饰，不是功能。
}
```

`main.dart` 已经 `import 'dart:ui';`（无 show 子句），`FragmentProgram` 直接可用。

- [ ] **Step 4: 验收管线通了**

```bash
flutter build apk --release --target-platform android-arm64 --debug
```
Expected: 构建通过（`impellerc` 在构建期编译 `.frag`；路径写错是**构建期**报错，不是运行期）。

然后装到真机、临时把液态档硬开（`liquidGlassShader` 加载成功即可）、出图确认**画面与标准档一致**（原样输出的 shader 应当看不出差别）。这一步证明的是「管线通、没倒置、没黑屏」。

- [ ] **Step 5: 提交**

```bash
git add app/shaders/liquid_glass.frag app/pubspec.yaml app/lib/main.dart
git commit -m "feat(glass): 接入 FragmentShader 管线（原样输出，先证管线通）"
```

---

### Task 5: 三档判据

**Files:**
- Modify: `app/lib/core/glass/glass.dart:7-21`
- Modify: `app/lib/main.dart:37`
- Modify: `app/lib/state/app_settings.dart:74,76,113-118,143-145`
- Test: `app/test/glass_tier_test.dart`

**Interfaces:**
- Consumes: `liquidGlassShader`（Task 4）
- Produces:
  - `final ValueNotifier<bool> glassBlurDisabled`（语义收窄为「省电档生效中」）
  - `final ValueNotifier<bool> liquidGlassEnabled`（用户开关）
  - `final ValueNotifier<bool> liquidGlassActive`（实际生效）
  - `void recomputeGlassTiers()` —— **取代 `recomputeGlassBlur()`（旧名删净）**
  - `bool Function() shaderFilterSupported = () => ImageFilter.isShaderFilterSupported;`

- [ ] **Step 1: 写失败测试**

`app/test/glass_tier_test.dart` 加**四组组合**（闸门是「与」关系，漏一个就是崩）：

```dart
setUp(() { shaderFilterSupported = () => true; });          // 测试跑在 Skia 上，真值恒为 false
tearDown(() { shaderFilterSupported = () => ImageFilter.isShaderFilterSupported; });

// ① 全开 → active 为真
// ② lowEndDevice = true（其余全开）→ active 为假，且 glassBlurDisabled 为真
// ③ shaderFilterSupported = () => false → active 为假，且 glassBlurDisabled 为假（回落标准）
// ④ liquidGlassShader = null → active 为假
```

第 ③ 组是关键：**闸门不满足时回落「标准」，不是回落「省电」** —— 所以 `glassBlurDisabled` 必须仍是假。

- [ ] **Step 2: 跑它，确认失败**

Run: `flutter test test/glass_tier_test.dart -v`
Expected: FAIL（`recomputeGlassTiers` / `liquidGlassActive` 还不存在）

- [ ] **Step 3: 改 `glass.dart` 顶部**

```dart
/// 低端机自动降级标志（物理内存 < 4GB，main() 设置）。**语义不变**：强制省电档。
bool lowEndDevice = false;

/// 「我的 → 外观 → 液态玻璃」开关（默认关）。用户意愿。
final ValueNotifier<bool> liquidGlassEnabled = ValueNotifier<bool>(false);

/// 省电档生效中。**只由 [lowEndDevice] 触发** —— 用户不能手动选它。
final ValueNotifier<bool> glassBlurDisabled = ValueNotifier<bool>(false);

/// 液态档生效中。
final ValueNotifier<bool> liquidGlassActive = ValueNotifier<bool>(false);

/// 后端是否支持 [ImageFilter.shader]。做成可覆盖的，是因为测试跑在 Skia 上、
/// 真值恒为 false，不给注入点就没法测「开着」那条路。
bool Function() shaderFilterSupported = () => ImageFilter.isShaderFilterSupported;

/// 重新计算三档（main() 与「外观」开关变更时调用）。
void recomputeGlassTiers() {
  glassBlurDisabled.value = lowEndDevice;
  liquidGlassActive.value = !lowEndDevice &&
      liquidGlassEnabled.value &&
      liquidGlassShader != null &&
      shaderFilterSupported();
}
```

删掉 `advancedMaterialDisabled` 与 `recomputeGlassBlur()`。

- [ ] **Step 4: 改 `app_settings.dart`**

- 字段 `advancedMaterial` → `liquidGlass`，默认 **`false`**（`:18` 的构造默认与 `:71` 的 `??` 两处都要）
- 存储键 `'advancedMaterial'` → **`'liquidGlass'`**
- `setAdvancedMaterial` → `setLiquidGlass`：内部先 `liquidGlassEnabled.value = value;` 再 `recomputeGlassTiers();`
- `resetToDefaults()`：`advancedMaterialDisabled = false` 删掉，换成 `liquidGlassEnabled.value = false;`，并调用 `recomputeGlassTiers()`
- 注释同步改（`:30`、`:135`）

**用新键 = 自带一次性重置**：老库里没有 `'liquidGlass'` 这个键 → 读到 `null` → 默认 `false` → 所有人升上来都是**标准档**。这比在 spec §3.2 里写的「落一个一次性标记」更简单，而且**不可能踩到「每次启动都重置」那个坑**（那条坑是 risk 7 警告的）。老键 `'advancedMaterial'` 留着不管，`clearAll` 会连同它一起清掉。

- [ ] **Step 5: 改 `main.dart`**

`main.dart:37` 的 `recomputeGlassBlur()` → `recomputeGlassTiers()`，且**必须在 shader 加载之后**（Task 4 Step 3 已经把加载放在它前面）。

- [ ] **Step 6: 跑测试**

Run: `flutter test test/glass_tier_test.dart -v`
Expected: PASS（四组）

- [ ] **Step 7: 提交**

```bash
git add app/lib/core/glass/glass.dart app/lib/state/app_settings.dart app/lib/main.dart app/test/glass_tier_test.dart
git commit -m "feat(glass): 三档判据（省电自动 / 标准默认 / 液态可选）"
```

---

### Task 6: 真正的折射 shader

**Files:**
- Modify: `app/shaders/liquid_glass.frag`

**Interfaces:**
- Consumes: Task 4 的管线、Task 5 的判据
- Produces: 无新 Dart 接口

- [ ] **Step 1: 写效果**

着色器要做的四件事（算法参考：Prismal 的 `TECHNICAL.md`，含 Snell 折射 / 色差 / Schlick 菲涅尔的推导）：

1. **SDF**：圆角矩形的有符号距离场，半径从 uniform 传进来；
2. **法线**：对 SDF 求梯度（中心差分）；
3. **折射**：沿法线方向偏移 UV 采样 —— 这是 `BackdropFilter` 永远做不出来的那一口；
4. **色散**：R / G / B 用**略微不同**的偏移各采一次；
5. **边缘光**：沿 SDF 边缘叠一条亮带。

**必须手写 4 抽头双线性过滤。** 本地 SDK 已核实（`sky_engine/lib/ui/painting.dart:4461`）：3.47.2 的 `ImageFilter.shader` **只有一个参数**、没有 `filterQuality`，所以 backdrop 采样器写死 Nearest。扭曲 UV 会在高对比边缘出阶梯锯齿，而**写错的人会以为是自己的 shader 有问题**。修这个的 PR #188544 于 2026-07-30 进了 master、没进 3.47.2；等它进 stable 之后可以删掉这段：

```glsl
// 手写双线性：backdrop 采样器是 Nearest，扭曲 UV 会出锯齿（flutter#188365）
vec4 sampleBilinear(sampler2D tex, vec2 uv, vec2 texSize) {
  vec2 p = uv * texSize - 0.5;
  vec2 f = fract(p);
  vec2 base = (floor(p) + 0.5) / texSize;
  vec2 off = 1.0 / texSize;
  return mix(mix(texture(tex, base), texture(tex, base + vec2(off.x, 0)), f.x),
             mix(texture(tex, base + vec2(0, off.y)), texture(tex, base + off), f.x),
             f.y);
}
```

**y 轴翻转那条守住在**（Task 4 已经写了）。

- [ ] **Step 2: 出图看**

```bash
flutter test tool/visual/render_screens_test.dart
```

看液态档的图（Task 7 之后的 `*_liquid*`）：边缘有折射、有色散、**画面没有上下颠倒**、没有锯齿状硬边。

- [ ] **Step 3: 真机量性能**

装到用户的小米机型，滚日历 + 停在响铃界面各看一遍。

**别按「反正现在很轻」推过去** —— 20dp 模糊单趟约 8ms，折射是**在其之上**的逐像素运算。若掉帧明显，先降 shader 里的采样次数（色散那一档最贵），**不要**去动 `FlowingBackground` 的低频驱动。

- [ ] **Step 4: 提交**

```bash
git add app/shaders/liquid_glass.frag
git commit -m "feat(glass): 折射 + 色散 + 边缘光（含手写双线性，绕开 filterQuality 缺失）"
```

---

### Task 7: 装配分叉 + 屏单 + 文案 + 默认翻转收尾

**Files:**
- Modify: `app/lib/core/glass/glass.dart`（`glassFilter` 分叉、`GlassPanel._build`、`GlassBlur.build`）
- Modify: `app/lib/core/l10n.dart:200,792,843-846`
- Modify: `app/lib/features/profile/profile_screen.dart:122-136`
- Modify: `app/tool/visual/visual_harness.dart`、`visual_screens.dart`、`render_screens_test.dart`
- Modify: `app/test/factory_reset_test.dart:160,162`

**Interfaces:**
- Consumes: Task 5 的 `liquidGlassActive`
- Produces: 无

- [ ] **Step 1: `glassFilter` 分叉**

```dart
ImageFilter glassFilter(double sigma) {
  final inner = ImageFilter.compose(
    outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    inner: AppTokens.glassSaturation,
  );
  final shader = liquidGlassShader;
  if (!liquidGlassActive.value || shader == null) return inner;
  // result = outer(inner(source))，所以「先糊再折射」= outer: shader
  return ImageFilter.compose(outer: ImageFilter.shader(shader), inner: inner);
}
```

`GlassPanel._build` 与 `GlassBlur.build` 都要**同时监听两个 notifier**（`glassBlurDisabled` 决定要不要套 filter、`liquidGlassActive` 决定套哪一种）。两个 `ValueListenableBuilder` 嵌套，或改成 `Listenable.merge([...])` 一个。

- [ ] **Step 2: 文案（中英各四处）**

`app/lib/core/l10n.dart`：

- `:843` `advancedMaterial` → `liquidGlass`：`t('液态玻璃', 'Liquid glass')`
- `:844` `advancedMaterialHint` → `liquidGlassHint`：
  - 中：`'开启后玻璃边缘会折射背景（iOS 26 那种）；关掉是磨砂玻璃，更省电（不支持该效果的设备会自动保持磨砂玻璃）'`
  - 英：对应英文，同样写「不开会怎样」
- `:792` `guideAppearanceDesc` 第 2 条：把「「高级材质」关掉后全 App 取消背景模糊，省电、低端机更流畅」改成描述**两档**，且**不要再提「省电档用户选不了」**（用户看不见的东西不需要解释）
- `:200` `clearAll` 确认框里那句点名「高级材质」的，跟着改名字

`profile_screen.dart:122,125` 的 `L10n.advancedMaterial` / `advancedMaterialHint` 换成新 getter，`:132` 的 `settings.advancedMaterial` → `settings.liquidGlass`，`:135` 的 `setAdvancedMaterial` → `setLiquidGlass`。

- [ ] **Step 3: 改既有测试**

`app/test/factory_reset_test.dart:160` 的 `expect(settings.advancedMaterial, isTrue)` → `expect(settings.liquidGlass, isFalse)`；`:162` 的 `expect(advancedMaterialDisabled, isFalse)` → `expect(liquidGlassEnabled.value, isFalse)`。`:97` 那个 mock prefs 里的 `'advancedMaterial': false` 改成 `'liquidGlass': true`（这样才真的在测「拨回默认」是不是把它翻回去了）。

- [ ] **Step 4: 屏单补屏**

`app/tool/visual/visual_harness.dart` 加与 `useStandardGlassTier()` 并列的：

```dart
/// 把玻璃拨到「液态」档，供出图与对比度审计用。
void useLiquidGlassTier() { ... }
```

`render_screens_test.dart` 里加两条独立用例（**不进 `visualVariants` 循环** —— 那是屏 × 变体的笛卡尔积，进去会让每一屏都多出两个变体）：

- `name: '36_calendar_liquid'`，`beforeCapture: (t) async => useLiquidGlassTier()`
- `name: '37_ringing_liquid'`

`:78` 那个只跑 light/dark 的 scrolled 循环不受影响。

- [ ] **Step 5: 全量验收**

```bash
flutter analyze
flutter test
flutter test tool/visual/
```
Expected: analyze 干净；`flutter test` 全绿且 ≥ 阶段 1 的条数；工装 272 条（+2）。

- [ ] **Step 6: 比对与收尾**

出图逐张看 `36_calendar_liquid` / `37_ringing_liquid` 与对应的标准档 —— 差异**必须看得见**，否则这一版等于没做。

然后按 Global Constraints 升版本、更新日志、发 `beta` 测试版。

---

# 阶段 3：复查那 18 处 `enableBlur: false`（另行拍板，不在本次实现）

**这是从「省电档保留」这个决定自然长出来的一个后续问题，不是本计划的实现范围。**

出发点是阶段 1/2 出图时会看到的一个事实：那 18 处（我的页 7、模板选择 3、排班管理 2、闹钟 2、待办 1、重复面板 1、日历 1）渲染出来的是**和「省电档」完全相同的那个「更实」外观**（`design_tokens.dart:167`），而用户对这个观感的原话是「太差了」。它们现在挂在纯色背景上所以不显眼，但液态档落地之后，同一屏里「胶囊是折射的、下面是实心的」这种落差会更明显。

**这一步要单独拍板，因为**：去掉它们 = 18 个列表行各自多一次 backdrop 抓取，是真金白银的性能代价（`glass.dart:70` 那条 `enableBlur && !blurDisabled` 就是为这个存在的）。要么保持现状，要么给列表找一个共享 backdrop 的方案（那是另一个子系统的活）。

---

## Self-Review

**1. Spec coverage**

| Spec 章节 | 落在哪个任务 |
|---|---|
| §3.1 两条触发源拆开 | Task 5 |
| §3.2 默认翻 + 一次性重置 | Task 5 Step 4（**用新键实现**，见下） |
| §3.3 那 18 处 | 阶段 3（计划外，已注明） |
| §4.1 三档模型与判据 | Task 5 |
| §4.2 `isShaderFilterSupported` 闸门 | Task 5 Step 1 第 ③ 组 |
| §4.3 真实饱和度 | Task 1 / 2 / 3 |
| §4.4 液态档 shader | Task 4 / 6 / 7 |
| §4.5 判据改名与连带改动 | Task 5、Task 7 |
| §5 分阶段 | 三个阶段的边界即此 |
| §6 文案 | Task 7 Step 2 |
| §7 测试与工装 | Task 3 Step 3、Task 7 Step 4 |
| §9 九条风险 | 1→Task 5 Step 1；2→Task 6 Step 1；3→Task 4 Step 1；4→Task 4 Step 4；5→Task 3 Step 2；6→Task 7 Step 2；7→Task 5 Step 4；8→Task 5 Step 1 ③ + Task 7 Step 5；9→Task 5 Step 4 |

**唯一一处对 spec 的偏离**（有意，且更简单）：spec §3.2 / risk 7 说「旧值一次性重置要落进 SharedPreferences 的一次性标记」。计划改用**新存储键 `'liquidGlass'`** —— 老库没有这个键，读到 `null` 就是默认 `false`，效果等价，而且结构上不可能踩到「每次启动都重置」那条坑。**建议同时把 spec 那两处改掉**，免得后来人对着两份不一致的文档猜。

**2. Step scan** —— 已查：没有「TBD」「适当处理」「加上必要的校验」这类不决定任何事的行；也没有把签名和测试已经定死的函数体抄一遍（shader 只给了契约与四个效果要点 + 那段必须手写的双线性，没有全文转录）。

**3. Type consistency** —— 已查：`recomputeGlassBlur()` 在 Task 5 被 `recomputeGlassTiers()` 取代，`visual_harness.dart:161` 那处调用一并改（Task 3 Step 3 先改成 `useStandardGlassTier()`，内部再调新名）；`advancedMaterial` → `liquidGlass` 的三处用法（`l10n` getter 名、`AppSettings` 字段、`VisualApp` 无关）在两处任务里一致；`glassFilter(double)` 的签名在 Task 2 定义、Task 4/7 使用，未变。

**4. Review Focus** —— 五条都已在对应任务落断言或验收：① → Task 5 Step 1 第 ② 组；② → Task 5 Step 1 第 ③④ 组 + Task 4 Step 4；③ → Task 6 Step 3 真机项；④ → Task 7 Step 3（factory_reset_test）；⑤ → Task 7 Step 5 的对比度审计（`flutter test tool/visual/` 含 `contrast_audit_test.dart`）。

**5. Proportion** —— 计划约 300 行、spec 约 230 行，同量级；代码块都是签名、测试断言与那段无法由签名决定的 GLSL，不是程序转录。
