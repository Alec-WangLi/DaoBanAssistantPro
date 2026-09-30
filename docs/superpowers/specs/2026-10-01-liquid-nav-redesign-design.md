# 底栏液态玻璃重做：把透镜做成一枚真的会动的玻璃 · 设计规格

> 2026-10-01 头脑风暴定稿。开工基线 **v0.10.2**（`app/pubspec.yaml` = `0.10.2+126`、`app/lib/core/app_info.dart` = `0.10.2`，两处同步；最新 tag `v0.10.2`）。
> **目标版本由用户拍板**（末位 `Z` 归 AI，`X.Y` 归用户）。本规格按仓库规矩落在 **`beta`** 分支。

## 1. 背景与目标

v0.10.2 真机测试后用户的判断是「液态玻璃的 bug 还是挺多的」，并要求**重新理思路**：
先梳理开源实现，再给出**符合本项目设计理念**的最佳结合方案。

对照用户提出的两条理想期望，v0.10.2 一条都没达到：

1. 「滑块按住时吸附到手上并放大，拖动时形状有 Q 弹变化」——没有。按住只是 `AnimatedScale(1.22)` 等比放大，是「缩放」不是「液体」。
2. 「滑块边缘根据底部胶囊产生光线折射」——没有。边缘光是一圈**单色**的晕，没有任何色散/折射的视觉签名。

**根因是一个结构问题，不是三个 bug**：v0.10.1/v0.10.2 的液态档让**同一件事有两个真相来源** —— 滑块本体由 `_RimPainter` 画在胶囊**之下**（于是被半透明胶囊压暗），而真 widget 身上的装饰又被摘掉了。用户反馈的①（静止时比胶囊大）、⑥（吸附僵硬）、以及独立审查抓出的对比度问题，**是同一个病的三次发作** —— 每修一处就冒出另一处，因为它们本来就不是一套东西。

**目标**：底栏的液态档从「给滑块贴一层光」改成「**一枚独立、会动、会形变的玻璃滴**」。先只做底栏；做对了再往其他玻璃面搬。

**成功标准**：

- 按住时透镜**离开胶囊**、吸附到手指并放大；拖动时形状跟着速度形变；松手带过冲地落回格子；
- 透镜边缘有一圈**以主色为锚**的彩色光，且透镜里能看见底下的胶囊被**放大**；
- **关掉液态玻璃之后，标准档一个像素都不变** —— 而且这一次是**结构上**的保证，不是事后比对；
- 液态档下**除底栏之外**的玻璃面与标准档完全一致。

## 2. 已定决策（2026-10-01 拍板）

① **液态档现阶段 = 底栏一处。** 摘掉 `GlassRim` / `GlassLensGlow` 在 `GlassPanel`（`glass.dart:124`）、`GlassPill`（`glass_pill.dart:92`）、`GlassSegment`（`glass_segment.dart:164`）、`GlassSwitch`（`glass_switch.dart:73`）四处的调用。现在那些「有点丑的边缘」从此不可能再发出去；底栏做对之后一处一处搬，每搬一处单独看图验收。

② **边缘光谱取「以主色为锚走色相」** —— 不是克制版（只在主色的邻近色之间，离用户描述的「光彩斑斓」最远），也不是满彩虹高饱和（与「极简黑白 + 单一主色」正面冲突）。整圈从主色的色相出发走一遍，压饱和度、只有左上最亮，其余渐隐成白。

③ **透镜要能「弯掉」底下的东西** —— 走 `ImageFilter.matrix`（SDK 自带，**零 shader**），先探针后实施。探针已通过，见 §4。

④ **架构走「两棵树」**：底栏 `build` 里直接分叉，标准档走今天那段代码（一个字符不动），液态档走新路径。两条路各自一套，**不互相打补丁**。

⑤ **不引入 shader 构建链。** 见 §3.3 与 §8。

## 3. 调研结论：开源实现怎么做，以及一条推翻旧假设的事实

### 3.1 算法高度收敛

八家开源实现（`oc_liquid_glass`、`Prismal`、`liquid_glass_widgets`、`liquid_glass_renderer`、RN 版 `react-native-liquid-glassmorphism`、`lucas-goldner/liquid_glass_example`、`Reimagined-Glass`、几个小仓库）走的是**同一套**：

```
圆角矩形 SDF → 中心差分求法线 → 沿法线偏移 UV 采样 → 菲涅尔边光
```

差别只在用**真 Snell 折射律**（Prismal）还是**经验偏移**（`off = n * rim² * strength`，其余各家）。可安全抄代码的是四家 MIT（`oc_liquid_glass` / `Prismal` / `liquid_glass_widgets` / RN）；另外两家没有 LICENSE，只能读思路。

### 3.2 一条推翻旧假设的事实

v0.10.1 的调研结论写的是「**折射在平背景上看不见**（本 App 的底色是刻意的极简黑白，实测 ≤1/255），于是整条 shader 链一个都没做」。这次调研发现：**那句话对「采样背景」成立，但对「边缘那圈彩色」不成立** —— 后者由 shader 的 rim 项驱动，**不采样背景也看得见**。

于是问题从「能不能采到东西」变成了「**那圈彩色从哪来**」，而答案有两个层次：

- **物理上**，色散是**真的逐通道采样**（R 采 `uv+ca`、B 采 `uv-ca`，`ca = n * rim² * 0.018`），不是叠彩虹渐变；
- **但它采的是背景。** 主色是青的，折射出来的还是青的 —— **色散只把「已经存在」的颜色分开，变不出彩虹**。iOS 底栏后面是照片、图标、彩色内容；我们后面是刻意的极简黑白。
- **iOS 自己也把它关掉了。** `liquid_glass_widgets` 为 iOS 26 做的那档校准，注释写着真实的 iOS UI 玻璃**几乎没有虹彩、大的分裂读起来像瑕疵**，于是把 `chromaticAberration` **主动设成 0.0**，只保留透镜折射。RN 那份文档里是同一句话。用户记得的那圈彩虹是**玻璃叠玻璃**（控制中心）的 prism glow，不是底栏那颗选中胶囊。

**结论：在我们这儿，那圈彩色必须「画」出来，不能「算」出来。** 这不是降级 —— 在这个设计语言下这是它唯一可能的形态，而且它比 iOS 底栏那颗胶囊更显眼，因为我们是刻意让它显眼的。

### 3.3 另一条：代价全在动画时

三家的性能文档（RN 的 `ARCHITECTURE.md`、`liquid_glass_widgets` 的自适应降档、HN 上的观察）指向同一件事：**静态玻璃几乎免费，一动起来就贵**。工业界的标准分工因此是：

- **「按住放大成透镜」走 shader 层** —— 元素尺寸不变，只放大内部 UV；
- **「拖动 Q 弹形变」走几何层** —— 弹簧 + 超出边界 + `Clip.none`。

这条正好防住 v0.10.1 的问题：那一版按住时**面积真的膨胀了**。我们的方案里，几何层的膨胀是有意且有限的（一枚 ~95×72dp 的透镜），放大层则完全不膨胀面积。

## 4. 探针：唯一的不确定项已经验过

**问题**：`BackdropFilter` + `ImageFilter.matrix`（SDK 自带，**带 `filterQuality`**，对比 `ImageFilter.shader` 在 3.47.2 里是单参数、backdrop 采样器写死 Nearest）能不能在透镜形状里放大背景？三个未知：① 它读到的 backdrop 里**有没有同层里更早画的东西**（胶囊）；② Flutter 会不会把读取范围**卡在 BackdropFilter 自己的绘制边界**上；③ 矩阵方向是「内容 ×2」还是「内容 ÷2」。

**做法**（`app/test/lens_magnify_probe_test.dart`，两条用例）：素材是一条已知位置的黑竖线（x=16），透镜覆盖 x∈[10,30]、中心 x=20。内容 ×2 会把线搬到 x=12、÷2 搬到 x=18、没生效则留在 x=16 —— **三个答案互不相同**，所以一次能把 ①②③ 全部分开。对照组用**单位矩阵**（同一套机器、只差缩放）。

**结果（实测）**：

```
[probe] 黑竖线的列位置：无透镜 15 → 单位矩阵 15 → 2× 11
[probe] 透镜区域内最暗的列：不放大 15 → 2× 11   ← 底栏的真实分层
```

- ① **读得到**：第二条用例里「胶囊」自己就套着一层 `BackdropFilter`（模糊），而透镜作为它的**兄弟节点**照样看得见它、放大照样生效。
- ② **结构上不存在这个坑**：放大意味着**源区域 ⊂ 目标区域**（关于中心缩放 s>1，目标 `[c−R, c+R]` 只读 `[c−R/s, c+R/s]`），所以放大镜**永远不需要读自己边界之外**。
- ③ **方向是「内容 ×2」**，符合直觉。

**未验的一项**：真机是 Impeller，`flutter test` 走的是另一套光栅化 —— **放大层必须在真机上再验一次**。它是可以单独摘掉的一层（几何与光谱环不依赖它）。

## 5. 设计

### 5.1 结构：两棵树

底栏 `build` 里直接分叉：

```dart
// core/glass/glass.dart 的档位标志不变；判据只在 features/home/ 里被读。
final bool liquid = liquidGlassActive.value;
return liquid ? _buildLiquid(context, ...) : _buildStandard(context, ...);
```

外层包一层 `ValueListenableBuilder<bool>(valueListenable: liquidGlassActive, …)`，开关一翻实时重建。

**手势与动画状态机一行不改** —— `_press` / `_dragStart` / `_dragUpdate` / `_release` / `_cancel` / `_syncFromController` / `_indexForDx` / `_nearestIndex` / `_clampPage` 以及 `_visualPage` / `_pressed` / `_dragging` / `_committedIndex` / `_previewIndex` / `_grabOffset` / `_drivingPage` 全部两条路共用。标准档那一段就是**今天那段代码搬进一个方法**。

于是「关掉液态玻璃不能影响磨砂玻璃」从**「比对后证明」**变成**「结构上不可能」** —— 这是这一版对用户那条硬性要求的正面回答。

### 5.2 液态档的三层树

```
SizedBox(height: capsuleH)
└── Stack(clipBehavior: Clip.none)        ← 不裁剪，透镜要能凸出去
    ├── ① 胶囊  ClipRRect(capsuleH/2) > GlassBlur > 填充 + 描边 + 边光
    ├── ② 透镜  LiquidLens（凸出、形变、放大、光谱环…）
    └── ③ 图标  Row（恒定最上层、恒定清晰）
```

- **① 胶囊** 与标准档同一份配方（`navFill` / `navBorder` / `blurPanel`），外加一圈边光（把今天 `GlassRim` 的画法搬进新模块）与「光跟随滑块」那条窄亮带。
- **③ 图标放最上是有意的**：24px 的小图标被透镜放大扭曲之后既不好看也不好读，而用户要的那圈光本来就是「**透过透镜看胶囊**」，不需要动图标。
- **手感判定**：透镜是 `IgnorePointer`，手势仍由 ③ 里那个 `GestureDetector` 接（与今天同一处）。

### 5.3 透镜的几何与弹簧

**坐标系**：胶囊局部，size = `(W, capsuleH)`。`pad = AppTokens.gapIconText`（6），`itemW = (W − 2·pad) / n`，`slotCenterX(i) = pad + (i + 0.5)·itemW`。

**静止**：宽 `w₀ = itemW`、高 `h₀ = capsuleH − 2·pad`，端头是**半圆**（半径 = 高/2）。注意这与标准档那个 `radiusL`=22 的圆角矩形差约 4px 圆角 —— **这是有意的**（水滴的端头本来就该是半圆），且标准档不受影响。

**弹簧**：一个自写的阻尼谐振子，`a = −k(x − target) − d·v`，`d = 2ζ√k`，**帧间隔封顶 48ms**。用它而不是 `TweenAnimationBuilder` 买的是两样东西：**速度**（形变要读它）和**过冲**（落回格子那一下）。

**按住（升程 `t` 0→1）**：

- **吸附到手指**：目标位置不是格子中心，而是手指。但**跟随被升程闸住** —— `targetX = lerp(slotCenter(最近格), fingerX, t)`。于是**快速点按几乎不动**（升程刚起来就松手了），**按住再拖才是完全跟手**，与 iOS 的「按住才提起」是同一个手感。
- **放大**：宽 `w = w₀ + liftW·t`，高 `h = h₀ + 2·AppTokens.navLensProtrude·t`。满升程时高 = 52 + 20 = 72，**比 64 高的胶囊高出 4px**（上下各 2px）。

**拖动（形变）**：由弹簧输出的真实速度 `v` 驱动，`s = clamp(|v| / vRef, 0, 1)`：

- `w *= 1 + 0.20·s`，`h *= 1 − 0.12·s`（面积近似守恒）；
- 形状**不是圆角矩形**：两个端头是**圆心同在水平中轴、但半径不同**的圆，中间用两段**外公切线**连起来 —— 半径相等时就是一枚标准胶囊，不等时就是一枚**水滴**（前缘大、后缘小）。向右拖 → 右端半径 `b·(1+0.25s)`、左端 `b·(1−0.15s)`；向左拖镜像。
- 这个构造是**精确**的（外公切线有闭式解，圆弧走 `Path.arcTo`），不是贝塞尔近似 —— 好处是「半径相等 ⇒ 退化成胶囊」这条性质可以被单测钉住。

**松手**：升程与位置各自弹回，位置落向最近格子。**弹簧的落回时间要与标准档的 `durFast` 相当**（先把 `durFast` 量出来，弹簧参数按它定，误差 ±20%）—— 用户反馈⑥ 说的就是这一下「僵硬、没有标准档那种缓慢优雅」。

**参数初值**（全部进 `AppTokens`，看图调）：`liftW = 10`、`protrude = navLensProtrude = 10`（既有令牌）、`vRef = 1500 px/s`、`ω ≈ 2π·1.8 Hz`、`ζ ≈ 0.85`、`dt` 上限 48ms。

### 5.4 光：三层叠出来

1. **放大层**（§4 验过的那条）：`ClipPath(透镜轮廓) > BackdropFilter(ImageFilter.matrix(关于透镜中心放大))`，倍率 `1.10`。带来两处可见的东西 —— 透镜凸出胶囊时**胶囊那条描边会在透镜里弯掉**；平时则让透镜内部的渐变与周围错开，读作「鼓起来」。
2. **光谱环**：沿透镜轮廓走一圈 `SweepGradient`，色相从 **`HSLColor.fromColor(primary).hue`** 出发走一遍邻近色；**透明度峰值钉在左上**、往右下渐隐；上面再压一条**白色高光芯**（线性渐变，左上亮、右下暗）。读起来是「一条被点亮的彩色玻璃边」，不是「贴了一圈彩虹」。
3. **浮起阴影 + 弯月面**：透镜投在胶囊上的影子（升程越高越深、越散），以及它与胶囊交界处那道细的接触弧。

**材质守门**：这一段住在 `lib/core/glass/`，在 `design_tokens_test` 的扫描范围内 —— **所有数值必须走 `AppTokens`**（同 `glassRimProbe*` 的做法），**不许出现 `Color(0x…)` 字面量**。主色走 `Theme.colorScheme.primary`，白/黑走既有的 `Colors.white/black.withValues(alpha:)` 豁免路径。

### 5.5 摘掉其他几处

按决策①：

| 位置 | 改什么 |
|---|---|
| `core/glass/glass.dart:123-129` | `GlassPanel` 里的 `GlassRim` 调用删掉 |
| `core/glass/glass.dart:161-579` | `GlassRim` / `GlassLensGlow` / `_RimPainter` / `_LensGlowPainter` **整个删掉**（边光画法搬进新模块） |
| `core/widgets/glass_pill.dart:92` | `GlassRim` 包层删掉 |
| `core/widgets/glass_segment.dart:134,164,200` | 液态分支、`GlassRim`、`GlassLensGlow` 全删 |
| `core/widgets/glass_switch.dart:54-85` | 液态分支与 `GlassLensGlow` 全删（含 `enabled` 闸门、`_dragT` 拖动那套） |
| `core/design_tokens.dart:222-268` | `glassRimProbe*` 保留（新模块要用）；`segmentLensProtrude` / `switchLensProtrude` 随调用点一起删 |
| `core/l10n.dart` | 液态玻璃那两行文案要重写（见 §7） |

**为什么是删而不是留着**：那两个类是「**给一块静止的玻璃贴一层光**」的思路，而新模块是「**一枚会动的玻璃**」的思路。将来往其他玻璃面搬时是**从新模块往外扩**，不是把旧类捡回来。

## 6. 分阶段实施

每步各自可回退，每步收尾测试全绿：

| 阶段 | 内容 | 验收 |
|---|---|---|
| **1** | 拆树（§5.1）+ 摘掉其他几处（§5.5） | **工装 181 张逐像素比**：标准档全部一致（`00_home_shell_*` 必须完全相同）；`37/38/39_*_liquid` 变回与标准档一致 |
| **2** | 透镜几何 + 弹簧 + 形变（§5.3），**不含放大与光谱环** | 纯逻辑单测；出 GIF 自查「动得对不对」 |
| **3** | 放大层 + 光谱环 + 阴影（§5.4） | 出图 + GIF；真机验放大层 |
| **4** | 屏单、动图、真机量性能 | 交付物 |

阶段 1 独立可验、独立可回退，而且**立刻**消掉那些丑边缘 —— 所以它排在最前，且它的验收标准与后三步无关。

## 7. 测试与工装

**新增 `app/test/liquid_lens_test.dart`**（纯逻辑 + 光栅化）：

1. **弹簧**：从中点出发收敛到目标（误差 < 0.5px）；**有过冲**；不发散；`dt` 封顶 48ms（喂 1 秒的 dt，一步位移不超过封顶后的结果）。
2. **透镜几何**：`t=0, v=0` → 两个端头半径相等（= 高/2，即胶囊）；`t=1` → 高 = 基准 + 2·`navLensProtrude`；`v>0` → 宽 > 静止宽、高 < 静止高；向右拖时右端半径 > 左端半径、向左拖镜像。
3. **光谱环跟着主色走**：两个不同主色渲染出的像素必须不同（同 `glass_saturation_test` 的 `_identity` 对照组思路 —— 这条要有鉴别力，不能只是「有没有画东西」）。
4. **透镜真的凸出胶囊**：`t=1` 时在胶囊外框的上下各命中一个非透明像素。

**扩充 `app/test/glass_tier_test.dart`**：

5. **标准档的底栏树里不含液态档的元素类型、液态档里含** —— 钉住「两棵树真的分叉了」。

**新增源码护栏 `app/test/liquid_scope_guard_test.dart`**（同 `haptics_guard_test` / `widget_fixed_cards_guard_test` 的套路）：

6. **`liquidGlassActive` 只许出现在 `core/glass/glass.dart`（定义处）与 `features/home/` 下** —— 把「液态档 = 底栏一处」这条决策变成会失败的用例。将来有人往别处搬而没想清楚，这条会先红。

**永久护栏**：`app/test/lens_magnify_probe_test.dart` 保留 —— 它证明的是**引擎行为**（backdrop 含同层更早的内容、矩阵方向、放大只读自身范围），那是承重墙。

**工装**（`app/tool/visual/`）：

- 保留 `36_home_shell_liquid`；**新增一屏「底栏 · 液态 · 按住拖到一半」**（静止帧拍不到凸出与形变，要靠 `beforeCapture` 起手拖动停在中途）。
- `37/38/39_*_liquid` 保留 —— 它们是「液态档在别处与标准档一致」的常设证据。

**动图**（`app/tool/gif/render_gifs_test.dart` + `scripts/make_gif.py`）：那条「底栏拖动」重出。**按住-吸附-拉伸-落回这一整串，静态图拍不出来** —— 动图是验收这个功能的主要眼睛，也是给用户看的第一交付物（长期记忆 `prefer-gifs-for-feature-demos`）。

**真机**：①②**放大层在 Impeller 下要再验**（§4 的未验项）；②量一次动画期间的帧时间（透镜面积 ~95×72dp，`BackdropFilter` 每帧一次 backdrop 读 —— 研究结论说代价全在动画时，这条只能在真机上量）。

**文案**（`core/l10n.dart`）：`liquidGlassHint` 现在是「玻璃边缘带光、按下时鼓起成透镜；关掉更省电」——「鼓起成透镜」在新实现下成立，但**「玻璃边缘带光」要改成描述实际效果**（底栏滑块按住时提起成透镜、边缘带彩色的折射光）。使用帮助与 `clearAll` 确认框里点到这个名字的地方一并核。

## 8. 明确不做

- **不引入 shader 构建链**（方案丙）：`pubspec` 的 `shaders:` + `impellerc` + Impeller-only 闸门（`ImageFilter.shader` 在非 Impeller 下**直接抛 `UnsupportedError`**）。代价与收益不成比例 —— 背景是平的，采不到东西；而 `flutter test` 里多半跑不了，等于**放弃动图与像素基线**这两样验收工具。
- 不引入任何第三方玻璃依赖（`liquid_glass_widgets` / `liquid_glass_renderer` / `oc_liquid_glass` 等一律**只读参考、不装**）。
- **这一版不给底栏以外任何玻璃面加液态效果**（决策①）；也不动那 18 处 `enableBlur: false`。
- 不给日历 42 格、不给列表行加任何效果。
- 不做液态档的启动期性能探测（`liquid_glass_widgets` 那种 ~3 秒 benchmark —— 它自己文档里也说会造成「每次冷启动都有 3 秒降级预热」）。
- 不改 `FlowingBackground` 的低频驱动方式。
- 不做「液态档的自适应降档」。

## 9. 风险与坑

1. **`ImageFilter.matrix` 在真机 Impeller 下的行为未验**（`flutter test` 与真机是两套光栅化）。**它是可摘的一层** —— 几何与光谱环不依赖它。真机若不稳，摘掉它退回纯自发光。
2. **`ClipPath > BackdropFilter`**：探针用的是 `ClipRect`。`ClipPath` 应当等价，但要在实施时确认（`ClipPath` 会走 `saveLayer` 还是纯 clip 会影响 backdrop 的作用域）。
3. **每次参数改动都会改观感** —— `liftW` / `protrude` / `vRef` / `ω` / `ζ` / 放大倍率 / 环宽全都只能看图定。**探针管「能不能」，GIF 管「好不好看」**，别指望单测替这两件事。
4. **`design_tokens_test` 会扫 `core/glass/`** —— 新模块不许有 `Color(0x…)` / `fontSize:` / `Duration(milliseconds:)` / 非法圆角字面量。数值一律进 `AppTokens`，主色走 `colorScheme.primary`。
5. **`QScale(pressed: _pressed, scale: pillGrow)` 会把整棵 Stack（含透镜）一起放大 6%** —— 这是标准档今天就有的行为，保留。但它会让「透镜凸出多少」在按下时被放大，**调 `protrude` 时要连着它一起算**。
6. **`Clip.none` 只在 Stack 这一层生效** —— 祖先若裁剪，凸出会被切。今天 `GlassRim` 已经在用 `Clip.none` 且凸出看得见，所以祖先不裁剪（用户反馈① 就是证据），但阶段 2 出图时要确认一次。
7. **弹簧必须有帧间隔上限**（48ms）：掉帧时一步积太大的位移会让透镜「瞬移」，而且 `dt` 越小数值越稳。
8. **`_press` 现在的语义是「吸附到手指所在的功能区」**，新几何要的是**手指的真实像素位置**。别把 `_visualPage`（以格为单位）直接当像素用 —— 差一个 `pad` 和一个 `itemW` 的量纲。手指位置存**内层（已扣 pad）坐标**，渲染时再加 `pad`。
9. **删 `GlassRim` / `GlassLensGlow` 会牵动 `glass_pill.dart` / `glass_segment.dart` / `glass_switch.dart` 三个共享件** —— 它们各自的既有用例（`glass_segment` / `glass_switch` 相关）会跟着改。**改这些用例时不许为了让它们变绿而放宽断言的鉴别力**。
10. **标准档零变化这一条要靠「快照-改动-比对」三步**：动手前先把 181 张渲一遍存档，改完再渲一遍逐像素比。`std-old` 那种基线**要确认它确实是改动前的**（v0.10.1 那轮就吃过「基线本身早于目标版本」的假差异）。

## 10. 参考实现（只读，不入依赖）

| 用途 | 出处 | 许可 |
|---|---|---|
| 最小 SDF + 边光骨架 | [`heyarny/oc_liquid_glass`](https://github.com/heyarny/oc_liquid_glass) 的 `liquid_glass.frag`（~180 行） | MIT |
| 折射 / 色散 / 菲涅尔的光学推导 | [`styropyr0/Prismal`](https://github.com/styropyr0/Prismal) 的 `TECHNICAL.md` | MIT |
| 色散系数、交互放大、降级阶梯 | [`himanshu-lal4/react-native-liquid-glassmorphism`](https://github.com/himanshu-lal4/react-native-liquid-glassmorphism) 的 `ARCHITECTURE.md` | MIT |
| 两趟管线、画质分档、iOS 26 校准档 | [`sdegenaar/liquid_glass_widgets`](https://github.com/sdegenaar/liquid_glass_widgets) | MIT |
| Flutter 自抓纹理的做法 | [`whynotmake-it/flutter_liquid_glass`](https://github.com/whynotmake-it/flutter_liquid_glass) | MIT |
| Apple 官方材质行为 | [WWDC25 Session 219](https://developer.apple.com/videos/play/wwdc2025/219/) | — |
| backdrop 采样器写死 Nearest | [flutter/flutter#188365](https://github.com/flutter/flutter/issues/188365) | — |
| `ImageFilter.blur` 与 `.shader` 同用时的尺寸问题 | [flutter/flutter#170820](https://github.com/flutter/flutter/issues/170820) | — |

## 11. 收尾（照 `AGENTS.md`）

- 版本：`0.10.3+127`，`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 两处同步（`app_info_test.dart` 盯着）；更新日志 prepend + 删最旧一条、保持 10 条（测试版条目原样写自己这版改了什么）。
- 落在 `beta` 分支；`git tag v0.10.3` → `scripts/release.ps1 -SkipConfirm` → **curl 一次 `main` 上的 `latest.json` 核对**。
- `AGENTS.md`：「目录架构地图」里 `core/glass/glass.dart` 那一行的描述要改（`GlassRim` 已删、液态档移到 `features/home/`）；「共享玻璃组件」一节里带液态描述的条目要改；「最近改动」补条目。
- 新增界面 / 新观感一律补进 `app/tool/visual/visual_screens.dart` 的屏单。
- 对比度：透镜的颜色变了 → **要重新量一次导航选中项的白字对比度**（`AGENTS.md` 那条「白字压实心主色，只有 primary/sky 过 AA」是同源问题，别让新效果把它推得更糟）。
