# 液态玻璃：把「高级材质」开关改成「标准 / 液态」两档 · 设计规格

> 2026-09-30 头脑风暴定稿。开工基线 **v0.10.0**（`app/pubspec.yaml` = `0.10.0+124`、`app/lib/core/app_info.dart` = `0.10.0`，两处同步；最新 tag `v0.10.0`）。
> **目标版本由用户拍板**（末位 `Z` 归 AI，`X.Y` 归用户）。本规格的各阶段按仓库规矩落在 **`beta`** 分支，各出一个测试版。

## 1. 背景与目标

起点是用户看到 iOS 26 的液态玻璃，问有没有开源实现能拿。调研结论（2026-09-30）：

- 开源实现很多，分三类：**iOS 原生**（与本项目无关，路线图已砍 iOS）、**Android 原生**（Kotlin/C++，不是 Flutter）、**Flutter 自绘**（跑在 Android 上 —— 本项目唯一相关的赛道）。
- Flutter 自绘里最成熟的是 `liquid_glass_widgets`（MIT；175 个版本、近三个月发了 70+、最新 1.8.1 是 10 小时前）。**它不是「陈旧」，是「它不属于我们」**：那是一整套 UI kit（`GlassScaffold` / `GlassTabBar` / `GlassDialog` / `GlassSheet` / `GlassSwitch` / `GlassSlider` / `GlassTextField`…），组件之间靠 `AdaptiveLiquidGlassLayer` / `LiquidGlassScope` 互相咬合。引进来的结果是 App 里同时存在两套玻璃系统，而自己那套是 `design_tokens_test.dart` 的令牌守门 + 270 条视觉工装逐个钉住的（v0.6.11 一路收到 v0.10.0）。
- **结论：不引入任何依赖，借技术不借组件。** 真正需要的技术量很小 —— 一个 `.frag`（约 60–120 行 GLSL）+ `pubspec` 一行 `shaders:` + `glass.dart` 约 30 行。这是**自己完全拥有的资源文件**，不是「引入一个框架」。那些包的正确用法是**当参考实现读**（MIT），不是当依赖装。

用户提出并拍板的核心想法：**把「高级材质」这个已有开关回收利用** —— 关 = 现在的磨砂玻璃，开 = 液态玻璃。这个想法成立的理由比「省一个新开关」硬得多，见 §3。

**目标**：玻璃从「一档」变成「两档**可选**」（外加一档**自动**兜底）；「高级材质」从一个**只能让画面变差的开关**变成一个**选择品质档位的开关**。

**成功标准**：

- 默认（不碰任何设置）的用户，升级后观感**只升不降**，且**零性能回退**；
- **低内存机器行为一字不变**（仍进省电档，不糊）；
- 打开「液态」的设备上，玻璃边缘看得见折射与色散；
- 不支持的设备打开它，**回落到标准（磨砂）**并说明原因 —— 不崩、不黑、不静默无反应；
- 关掉它，回到与今天（除饱和度外）一致的玻璃。

## 2. 已定决策（2026-09-30 拍板）

① **三档，但只有两档可选**：

| 档 | 谁能到 | 效果 |
|---|---|---|
| **省电** | **只有低内存机器自动进**（用户不可选） | 今天那个「更实」的观感（无真实模糊） |
| **标准** | 默认，人人可到 | 磨砂玻璃 + 真实饱和度 |
| **液态** | 用户在开关里主动打开，且设备支持 | 标准之上再叠边缘折射 / 色散 / 镜面边缘光 |

用户最初提过「把省电整条删掉」，在看到「低内存机器会从『不糊』变成『默认糊』= 唯一一处真实回退」之后**决定保留**。随后拍板：**省电只自动、不给手动选** —— 于是「我的 → 外观」那颗控件仍然是一颗开关（关 = 标准、开 = 液态），「省电」这个词不出现在用户界面上。

② **复用「高级材质」这个开关**，不新增设置项。

③ **默认翻成「关」，并改用新的存储键**（老键 `advancedMaterial` → 新键 `liquidGlass`，见 §3.2）。不做的话全体老用户会静默吃上最贵的一档。

④ **不引入任何第三方依赖**。shader 是自己的 `.frag`，参考实现只读不装。

⑤ **`enableBlur: false` 那 18 处本轮不动**，留到阶段 3 单独判。它们是**逐调用点**的性能优化，与全局档位是两套机制（`glass.dart:70`：`blurOn = enableBlur && !blurDisabled`）；捆在一起会让改动变成「一次动 19 个地方」。详见 §3.3。

## 3. 现状：这个开关今天其实是个「重复品」

### 3.1 两条触发源落在同一档上

`app/lib/core/glass/glass.dart:19`：

```dart
final disabled = lowEndDevice || advancedMaterialDisabled;
```

`lowEndDevice`（`main.dart:32-34`，物理内存 <4GB 自动）与用户手动关「高级材质」**落到同一个结果上**。所以这个开关今天只能让画面**变差**，永远不能变好 —— 用户没有任何理由去碰它。它是全 app 唯一一颗「关掉好看的东西」的按钮。

决策 ① 正好补上这一刀：**把自动那一档与手动那一档拆开** —— 自动降级只管省电档，手动开关改管液态档。改完之后两条触发源不再重复，而且**`lowEndDevice` 本身就成了地板**：低内存机器压根够不到液态档，不需要另设一条「内存再挡一次液态」的规则。

### 3.2 为什么默认必须翻成「关」

`app/lib/state/app_settings.dart:18` 与 `:71` 的 `?? true` —— `advancedMaterial` **默认为真**。

若「开」的新含义是液态玻璃，那么**升级之后所有从来没碰过这个开关的人会静默吃上最贵的一档**，而他们根本没选过。这属于本仓库最忌讳的那类问题（与「明明有更新的测试版却说已是最新」同源：用户没做错什么，App 自己变了）。

**做法：换一个新的存储键**（`'advancedMaterial'` → `'liquidGlass'`）。老库里没有这个键 → 读到 `null` → 默认 `false` → 所有人升上来都是**标准档**。这就是一次性重置，但它**不需要任何标记**，结构上也不可能踩到「每次启动都重置」那条坑。老键留着不管，`clearAll` 会连同它一起抹掉。

这么处理之后，两种人都干净：

- 从来没碰过它的人（绝大多数）：默认 = 标准 = **今天默认的观感**，零感知、零回退；
- 今天**主动关掉**它的人（他要的是省电）：旧语义下他拿到的是「完全不糊」，翻默认之后会变成磨砂玻璃。**他因此失去了手动回到省电档的能力** —— 这是决策 ① 的已知代价，用一次性重置把它变成「明确的、一次性的观感变化」，而不是每次启动都反复。

### 3.3 一个容易砍错的地方：`enableBlur: false` 不是「省电档」

代码里是两套机制：

```dart
final blurOn = enableBlur && !blurDisabled;   // glass.dart:70
```

- `blurDisabled`（全局）= 省电档；
- `enableBlur: false`（逐调用点）= **有意让这一行不糊**，全 app **18 处**：我的页 7、模板选择 3、排班管理 2、闹钟 2、待办 1、重复面板 1、日历 1。

要命的是：`enableBlur=false` 渲染出来的是**和「省电档」完全相同的那个「更实」外观**（`app/lib/core/design_tokens.dart:167` 写着「`blurOn=false`（低端机/关高级材质）时整体更实」）。**也就是说用户说「太差了」的那个观感，现在正永久挂在这 18 行上** —— 只是它们在纯色背景上，不像日历那样有光晕可透，所以没显出难看。

这条留给**阶段 3**：等液态档落地、出图看过之后，单独判这 18 处要不要一起收（那是从「省电档保留」这个决定自然长出来的一个后续问题，不是本轮范围）。

## 4. 设计

### 4.1 三档模型与模块级判据

```dart
// core/glass/glass.dart
bool lowEndDevice = false;        // 物理内存 <4GB（main() 设置）—— 语义不变：强制省电档

/// 「我的 → 外观 → 液态玻璃」开关（默认关）。用户意愿。
final ValueNotifier<bool> liquidGlassEnabled = ValueNotifier<bool>(false);

/// 省电档生效中（只由 lowEndDevice 触发，用户不能手动选）。
final ValueNotifier<bool> glassBlurDisabled = ValueNotifier<bool>(false);

/// 液态档生效中。能力闸门是「与」关系 —— 漏一个就是崩（见 §4.2）。
final ValueNotifier<bool> liquidGlassActive = ValueNotifier<bool>(false);

/// 重新计算三档。main() 与「外观」开关变更时调用。
void recomputeGlassTiers() {
  glassBlurDisabled.value = lowEndDevice;
  liquidGlassActive.value = !lowEndDevice &&
      liquidGlassEnabled.value &&
      ImageFilter.isShaderFilterSupported;
}
```

`recomputeGlassTiers()` 沿用现有的 `recomputeGlassBlur()` 那套写法（模块级标志 + `main()` 与设置变更时重算），与 `hapticsDisabled` 同一条路 —— `glass.dart` 的改动面最小，调用点不必各自查设置。

**优先级说明**：`!lowEndDevice` 写在最前面是有意的 —— 省电档是地板，它上面才有标准与液态。

### 4.2 为什么 `isShaderFilterSupported` 这条闸门是必须的

`ImageFilter.shader` 在非 Impeller 下**直接抛 `UnsupportedError`**（`sky_engine/lib/ui/painting.dart:4413-4414`、`:4487`）—— 不是「画不出来」，是**崩**。判据是运行时的（`static bool get isShaderFilterSupported => _impellerEnabled;`），编译期没有。

这条对 Windows 那条线尤其要紧：Impeller 是 **3.47.0（2026-08-12）才成为 Windows / Linux 默认**的，且有已知的个别显卡驱动黑屏问题（有 Skia 回退开关）。所以液态档在桌面上大概率不是「能不能跑」而是「**哪些机器**能跑」—— `isShaderFilterSupported` 正好是这条的判据。

**闸门不满足时一律回落「标准」，不是回落「省电」**：用户开的是「更好看」，不是「更省电」。

### 4.3 阶段 1：真实饱和度（零依赖、零 shader）

这一层补的是**代码注释里已经标出来的缺口**。`app/lib/core/glass/glass.dart:26-32` 自己写着：

```
/// 效果构成（与调研结论一致）：
///   1) 背景模糊（BackdropFilter + ImageFilter.blur）
///   2) 半透明渐变着色（近似饱和度提升）
///   3) 顶部镜面高光描边（liquid 边缘光）
```

现状是用一层半透明渐变在**假装**饱和度。但它可以是真的 —— 本地 SDK 已核实（`sky_engine/lib/ui/painting.dart`）：

```
4406:  factory ImageFilter.compose({required ImageFilter outer, required ImageFilter inner})
        /// result = outer(inner(source))
4073:  class ColorFilter implements ImageFilter          // ← 关键：它本身就是 ImageFilter
```

`ColorFilter` 是 `ImageFilter` 的子类型，所以可以直接塞进现有的 `BackdropFilter`：

```dart
BackdropFilter(
  filter: ImageFilter.compose(
    outer: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
    inner: const ColorFilter.matrix(_saturationBoost),
  ),
  ...
)
```

`_saturationBoost` 走 Rec.709 保亮度的饱和度矩阵（`Lr = 0.2126 / Lg = 0.7152 / Lb = 0.0722`），系数 `s` 待定，先在工装上试 1.15–1.30 之间。

**为什么这一层值得单独做一版**：真实液态玻璃**最可辨识的特征**（除折射外）就是这个 —— 玻璃后面的东西不只是变模糊，**还变得更浓、更艳**。这不是拍脑袋：`liquid_glass_widgets` 自己的**最低画质档**（`minimal`）的定义就是「`BackdropFilter` 模糊 + Rec.709 饱和度矩阵 + 一圈镜面描边」。一条成熟产品线的最低档就是这么划的。

**实现时必须对账的一处**：现有的「近似饱和度提升」那层渐变要**同步收掉或减弱**，否则饱和度被算两遍。这是本阶段唯一需要看图判断的地方。

**另外**：`solid: true` 的面板（底部弹层、选择器弹层）不走这条路的观感 —— 它用不透明的 `Theme.colorScheme.surface` 做底，模糊本来就看不见，饱和度自然也看不见。这是对的，**不要为它特判**。

### 4.4 阶段 2：液态档（shader）

**管线**：把 shader 与模糊**合成一个** `ImageFilter`，而不是叠两层 `BackdropFilter`（两层 = 两次 backdrop 抓取）：

```dart
// result = outer(inner(source))，所以「先糊、再折射」= outer: shader, inner: blur
final filter = ImageFilter.compose(
  outer: ImageFilter.shader(_liquidShader),   // 折射 / 色散 / 边缘光
  inner: ImageFilter.blur(sigmaX: s, sigmaY: s),
);
```

比 `liquid_glass_widgets` 那套「blur 一趟 + shader 一趟」少一次抓取。

**shader 契约**（`painting.dart` 已核实）：

- 第一个 uniform 必须是 `vec2`，由引擎填入绑定纹理的尺寸；
- 至少一个 `sampler2D`，**第一个 sampler 自动绑定为 filter 的输入**（即模糊过的那张 backdrop）；
- `.frag` 放 `app/shaders/`，`app/pubspec.yaml` 里加 `shaders:` 声明，由 `impellerc` 在**构建期**编译。

**着色器要做四件事**（算法参考：Prismal 的技术文档，含 Snell 折射 / 色差 / Schlick 菲涅尔的完整推导）：

1. 圆角矩形 SDF → 表面法线（对 SDF 求梯度）；
2. 沿法线方向偏移 UV 采样 → **折射**（这就是 `BackdropFilter` 永远做不出来的那一口）；
3. R/G/B 用略微不同的偏移采样 → **色散**（最便宜、也最可辨识的一档）；
4. 沿 SDF 边缘叠一条亮带 → **镜面边缘光**。

**首批上哪几个面**（数量少、位置静态、不滚动）：

- 顶栏胶囊、底栏导航胶囊（`home_shell`）、日历信息卡面板、响铃界面。

**明确不上**：日历 42 个格子（42 个会动的着色器 = 就是 30fps + 发烫那个场景）、任何列表行（已经 `enableBlur:false`）、以及**任何会动的控件** —— 第一批先不碰 `GlassSegment`（`liquid_glass_renderer` 的文档写着「移动任何一个形状都会逼整组重渲染」）。

### 4.5 这一阶段要一并改掉的（原「删省电档」收缩版）

省电档保留了，所以**没有删除清单**。但下面几处的**含义**仍然要跟着改：

| 位置 | 改什么 |
|---|---|
| `core/glass/glass.dart:15,19,20` | `glassBlurDisabled` 不再由用户开关驱动（`= lowEndDevice`）；`recomputeGlassBlur()` 换成 `recomputeGlassTiers()`；新增 `liquidGlassEnabled` / `liquidGlassActive` |
| `core/glass/glass.dart:62,162` | 两个 `BackdropFilter` 除原有的 `glassBlurDisabled` 外，再按 `liquidGlassActive` 选装配路径 |
| `main.dart:32-37` | 调用改名（`recomputeGlassBlur()` → `recomputeGlassTiers()`）；**内存读取保留** |
| `state/app_settings.dart:76,114,145` | 三处调用改名；`:113-117` 的 setter 改为写 `liquidGlassEnabled`；默认值 `:18` / `:71` 的 `?? true` 改 `?? false` |
| `features/alarm/alarm_service.dart:559` + `MainActivity.kt:668` | **不动**（`getTotalRamBytes` 仍然要用） |
| `core/theme/animated_background.dart:64,69,86` | **不动** —— `freezeWhenBlurDisabled` 仍由 `glassBlurDisabled` 触发，而后者仍会被低内存机器置真，语义反而比改动前更准 |
| `core/l10n.dart:844,792` | 两句会变成错的文案（见 §6） |

**顺带确认的好消息**：因为省电档保留了，`freezeWhenBlurDisabled` **没有失去触发源** —— v0.9.8 那条「低频驱动、不许改回 `repeat()`」的护栏照旧成立，不需要额外加约束。

## 5. 分阶段实施

每个阶段**各自独立成版、独立可回退**：

| 阶段 | 内容 | 依赖 | 风险 |
|---|---|---|---|
| **1** | 真实饱和度（§4.3） | 无 | 极低：一个文件，无 shader、无构建链改动，Skia / Impeller / Windows 都跑 |
| **2** | 液态档：shader 基础设施 + 闸门 + 默认翻转 + 文案 + 判据改名（§4.4 / §4.5） | 阶段 1 | 中：新增构建链；桌面端 Impeller 有已知驱动问题 |
| **3**（可选，另行拍板） | 复查那 18 处 `enableBlur: false`（§3.3） | 阶段 2 | 低，但要出图看 |

**阶段 1 单独上也有价值**：如果上完已经够「润」，阶段 2 可能根本不必做 —— 这正是把它放最前面的理由。

## 6. 文案（`app/lib/core/l10n.dart`）

现在这两句在改动之后会变成**错的**：

- `:844` `advancedMaterialHint`：「磨砂玻璃的背景模糊；**关掉更省电**、低端机更流畅」
- `:792` `guideAppearanceDesc` 第 2 条：「「高级材质」关掉后全 App 取消背景模糊，省电、低端机更流畅」

「关掉 = 省电」在新模型下不成立 —— **关掉是标准档**；省电档还在，但只由低内存自动触发，用户点不到。这正是 v0.7.0（把「切换排班」说成在排班管理页）与 v0.10.0（「清空重置」实际不清自定义闹钟与模板）栽过的同一类坑：**行为改了、文案没跟着改**。

建议连同**行名**一起换掉：「高级材质」在新模型下两边都描述不清。方向：

```
行名：液态玻璃 / Liquid glass
副标题：开启后玻璃边缘会折射背景（iOS 26 那种）；关掉是磨砂玻璃，更省电
        （不支持该效果的设备会自动保持磨砂玻璃）
```

按仓库惯例，副标题要写「**不开会怎样**」（v0.8.0 ⑤ 权限页重做定的），中英两份都要改。`clearAll` 的确认框（`l10n.dart:200`）里点了「高级材质」这个名字，一并改。

**注意**：副标题**不要**提「省电档用户选不了」这类实现细节 —— 用户看不见的东西不需要解释。低内存机器自动降级本来就是既有行为，不必新解释一遍。

## 7. 测试

- **阶段 1**：两条 ——
  1. **装配用例**：断言 `BackdropFilter` 的 filter 是 `ImageFilter.compose` 且内含 `ColorFilter`，而不是只有 blur。钉住「不许退回纯模糊」。
  2. **渲染冒烟**：光断言类型不算数 —— `ColorFilter` 作为 `ImageFilter` 嵌进 `BackdropFilter` 这条路**本仓库从没跑过**。第一条任务就是在真机上确认它真的出图（不是静默变透明 / 变黑），再往下走。这一步过了，阶段 1「极低风险」的判断才算站住。
- **阶段 2**：
  - **闸门用例**（最重要的一条）：`liquidGlassEnabled` 为真，但 `isShaderFilterSupported` 为假 / `lowEndDevice` 为真时，`liquidGlassActive` 必须为假。四个组合逐条钉（`lowEndDevice` × `isShaderFilterSupported` × 开关），因为这是**「与」关系、漏一个就是崩**。
  - 「关掉回到标准」用例：关开关后装配路径不含 shader。
  - 「默认是标准」用例：新库里 `advancedMaterial` 为假。
  - 确认 `design_tokens_test` 的扫描范围不会误伤 `app/shaders/`（`core/theme` 在扫描范围内；shader 不在 `lib/` 下，**实施时确认**）。
- **工装**：**必须补屏**。按仓库家法（v0.8.1 四处跑偏的根因、v0.9.14 / v0.9.18 连续两次靠屏单抓出真 bug），新观感**没有屏单就没有眼睛**。至少补：标准档（浅 / 深）× 液态档（浅 / 深），面覆盖日历、布局、响铃界面。
- **真机**：折射档的性能只能在真机上量（20dp 模糊单趟约 8ms，折射是**在其之上**的逐像素运算）。在用户的小米机型上量一版，别按「反正现在很轻」推过去。

## 8. 明确不做

- 不引入 `liquid_glass_widgets` / `liquid_glass_renderer` / `oc_liquid_glass` 或任何第三方玻璃依赖（决策 ④）。参考实现只读不装。
- 不给日历 42 格、不给列表行、不给首批之外的面加折射。
- **不让用户手动选省电档**（决策 ①）—— 不做三段选择器。
- 本轮不动那 18 处 `enableBlur: false`（决策 ⑤）。
- 不做「液态档」的自动性能探测（`liquid_glass_widgets` 那种启动期约 3 秒的基准测试 —— 它自己文档里也说会造成「每次冷启动都有 3 秒降级预热」，对本 App 的冷启动体验是负担）。
- 不动 `FlowingBackground` 的低频驱动方式。

## 9. 风险与坑（实施时挨个对照）

1. **`ImageFilter.shader` 在非 Impeller 下抛 `UnsupportedError`**（`painting.dart:4413`）。闸门必须走 `ImageFilter.isShaderFilterSupported`，不能只看用户开关。症状是**崩**，不是画不出来。
2. **3.47.2 的 `ImageFilter.shader` 没有 `filterQuality` 参数** —— 已在本地 `toolchain/flutter/bin/cache/pkg/sky_engine/lib/ui/painting.dart` 核实：签名是 `factory ImageFilter.shader(FragmentShader shader)`，**只有一个参数**。修这个问题的 PR **#188544 于 2026-07-30 合进 master、未进 3.47.2**（同期的 `ImageFilter.matrix` 倒是自带 `filterQuality`、默认 `medium` —— 对比之下更显眼）。所以 backdrop 采样器**写死 Nearest**，扭曲 UV 会在高对比边缘出阶梯锯齿 —— **必须在 GLSL 里手写 4 抽头双线性过滤**（每像素 4 倍纹理采样开销）。不写的话你会以为是自己的 shader 写错了。等未来 stable 带上那个参数之后，可以删掉这段自写过滤。
3. **Impeller 的 GLES 后端 y 轴是反的**。自定义片元着色器必须 `#ifdef IMPELLER_TARGET_OPENGLES` 翻转 y，否则**整个效果上下颠倒**。这条专门打低端机（走 GLES 回退的那批）。
4. **`.frag` 由 `impellerc` 在构建期编译**，改了要重新走 `flutter build`；`pubspec.yaml` 的 `shaders:` 路径写错是**构建期**报错，不是运行期。
5. **饱和度与现有的「近似饱和度」渐变会叠两遍**（§4.3）—— 阶段 1 唯一的看图项。
6. **默认翻转必须配一次性重置**（§3.2），否则老用户静默升级到贵档。**用新存储键实现**（`'advancedMaterial'` → `'liquidGlass'`，默认 `false`）—— **不要**写「一次性标记 + 重置」那一套：标记漏清一次就是「用户开了液态、下次启动被拨回去」，那是另一类「我设了它自己变回去」的反馈，而新键从结构上就没有这个失败模式。**注意别顺手把老键删掉**（`prefs.remove('advancedMaterial')`）—— 万一要回滚版本，键还在才回得去；`clearAll` 自然会清掉它。
7. **桌面端**：Impeller 3.47 才成为 Windows 默认，且有已知的个别驱动黑屏问题。液态档在桌面上大概率不是「能不能跑」而是「**哪些机器**能跑」—— `isShaderFilterSupported` 正好是这条的判据。
8. **透明度 / 无障碍**：`liquid_glass_widgets` 的文档说它读不到系统的 `Reduce Transparency`（Flutter 引擎限制），只能用 `Increase Contrast` 近似。本项目**已知**还有一处在开着的对比度问题（白字压 teal / orange / rose 实心主色不达 AA，见 `AGENTS.md`「关键决策与坑」）—— 液态档会改变玻璃后面的明度，**实施时要重新量一遍那几处的对比度**，别让新效果把它推得更糟。
9. **`glassBlurDisabled` 的语义变窄了**（从「低内存 **或** 用户关了」变成「只有低内存」）。凡是用它当「用户不想看到重合成」判据的地方，都要重新看一眼还成不成立 —— 目前只有 `FlowingBackground.freezeWhenBlurDisabled` 一处，逻辑仍然正确（低内存机器才需要冻住光晕），**但改的时候要确认没有第二处**。

## 10. 参考实现（只读，不入依赖）

| 用途 | 出处 |
|---|---|
| Flutter 两趟管线的工程做法、画质分档 | `liquid_glass_widgets`（MIT，pub.dev） |
| 折射 / 色散 / 菲涅尔的算法推导 | Prismal 技术文档（`styropyr0/Prismal`，`TECHNICAL.md`） |
| 最小 `FragmentProgram` 示例 | `lucas-goldner/liquid_glass_example`（**无 LICENSE 文件 —— 只读，不可抄代码**） |
| Android 端性能与降级阶梯实测 | `react-native-liquid-glassmorphism` 的 `ARCHITECTURE.md` |

## 11. 收尾（照 `AGENTS.md`）

- 版本：每个阶段一个测试版，落在 `beta` 分支，`Z` 递增、`build` 同步 +1，`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 两处同步（`app_info_test.dart` 盯着）；更新日志 prepend + 删最旧一条、保持 10 条。
- 阶段 2 改了用户可见的设置语义 → 更新日志、使用帮助（`guideAppearanceDesc`）、`clearAll` 确认框**三处一并改**。
- 阶段 2 之后回看 `AGENTS.md`：「目录架构地图」里 `core/glass/glass.dart` 那一行的描述（写着 `glassBlurDisabled`=低端机自动+手动开关取或）要改；「最近改动」补条目。
- 新增界面 / 新观感一律补进 `app/tool/visual/visual_screens.dart` 的屏单。
