# 设计语言大一统 · 设计规格

- 日期：2026-09-03
- 目标版本：`0.4.4+64`（AI 只改末位 Z；若你认为这是「大版本」要上 `0.5.0`，由你拍板）
- 状态：待评审

---

## 1. 背景与目标

倒班助手 Pro 已经确立了自己的设计语言——**简洁 + 液态玻璃（磨砂模糊）+ Q 弹动画**，并且沉淀了 10 个共享玻璃组件（`GlassPanel`/`GlassTile`/`GlassBlur` + `core/widgets/` 下的按钮、分段、开关、弹窗、选择器、提示条等）。

但这套语言没有落地成「设计令牌」，各组件各自内联声明圆角/时长/透明度/图标，导致**令牌漂移**：

- 圆角散落 13 种值（20×15、14×11、28、24、12、30、10、22、18、16、4、3、2）。
- 动画时长散落 10+ 种（80~650ms），Q 弹都挂 `easeOutBack` 但没有统一节奏。
- 「白玻璃」填充配方至少 5 套（GlassPanel `0.10/0.02`、GlassButton `0.22/0.06`、GlassSegment `0.07`、导航 `0.18/0.08`、Snackbar `0.18/0.05`）。
- 图标混用 filled（`_rounded`）与 outlined（`_outline_rounded`，另有一个落单 `circle_outlined`）。
- `AppColors.glassLightFill/glassDarkFill/glassDarkBorder` 等定义了却没被 `glass.dart` 消费，`glass.dart` 自己又硬编码一套。
- **强调色未完全贯通**：导航选中胶囊硬编码了蓝紫 `AppColors.gradientStart/gradientEnd`，导致用户把主色换成青/橙/玫瑰后，按钮开关会变、导航滑块与响铃背景光晕仍是蓝紫；`secondary` 固定 `#8A5CFF` 亦然。

目标：**收敛成一套设计令牌（单一事实来源），并按下述已确认方向做一轮「整体重设计」**，让外观、动画、图标风格全部统一。

---

## 2. 设计方向（已与用户确认）

1. **背景层 = 中性**：亮色「简约白」/ 暗色「暗夜黑」，去掉蓝紫光晕与渐变氛围（`FlowingBackground` 的彩色 blob、`scaffoldBackground` 色调）。
2. **强调色 = 现有 5 色主色调，只染「强调点」**：开关开态 / 按钮 / 导航选中 / 高亮描边，与背景层互不干涉；不再通过 `fromSeed` 污染整套 ColorScheme。
3. **玻璃 = 磨砂模糊 + 半透明（无镜面高光）**：真实背景模糊 + 半透明白 tint + 顶部 1px 细描边界定边缘，营造「液态玻璃」质感；**不叠加任何镜面高光**（倾斜动态与静态左上都不做，见修订记录）。
4. **图标 = outlined 线性**。
5. **动效 = Q 弹拉到极致**：用弹簧物理替代固定时长缩放。

---

## 3. 设计令牌层（单一事实来源）

新增 `<app>/lib/core/design_tokens.dart`（唯一令牌来源），`app_colors.dart`/`app_theme.dart`/`glass.dart`/`core/widgets/*` 一律改为引用它，不再内联 magic number。令牌按域分组：

### 3.1 颜色令牌

| 令牌 | 亮色 | 暗色 | 说明 |
|---|---|---|---|
| `bg` | `#F5F6FA` | `#0B0B10` | 页面背景（中性） |
| `surface` | `#FFFFFF` | `#16161E` | 实心面板/底部弹层底 |
| `ink` | `#111118` | `#F2F2F7` | 主文字 |
| `inkMuted` | `#6E6E82` | `#9A9AB0` | 次要文字/禁用 |
| `accent`（5 色） | `#5B6CFF`(默认) / `#0A84FF` / `#00C7BE` / `#FF9F0A` / `#FF375F` | 同 | 强调色，决定开关/按钮/选中态 |
| `danger` | `#E53935` | `#E53935` | 危险/删除/节假日红（归一） |
| `success` | `#4ADE80` | `#4ADE80` | 成功态 |
| `holiday` | `#E53935` | `#E53935` | 法定节假日（值同 danger，语义独立） |

- **班次数据色不变**（`int`，与 domain 默认一致）：`shiftDay 0xFF4C8DFF` / `shiftNight 0xFF7A5CFF` / `shiftAfterNight 0xFF9AA0B4` / `shiftRest 0xFF5A5F73` —— 属「内容」非「装饰」，保留。
- **删除** `AppColors` 里定义未消费的 `glassLightFill/glassDarkFill/glassLightBorder/glassDarkHighlight` 等死令牌，由 §3.2 的玻璃配方令牌取代。
- **强调色渐变派生**：删除全局硬编码 `gradientStart/gradientEnd`，改为 `accentGradient(Color accent)` = `accent.withValues(0.85→0.50)` 顶部至右下。所有「主色渐变」（按钮、导航选中、走马灯）一律从此派生，**真正跟随主色**。

### 3.2 玻璃配方令牌（统一，消除多套配方）

每个明暗主题各一顿「玻璃配方」，分两档，全部玻璃组件从中取值：

| 令牌 | 亮色 | 暗色 |
|---|---|---|
| `glassTint`（按钮/开关轨/提示条） | 白 `0.80 → 0.45` | 白 `0.16 → 0.07` |
| `navFill`（底部悬浮导航胶囊，近实填充） | 白 `0.97 → 0.93` | `#16161E` `0.97 → 0.92` |
| `glassSurface`（卡片/列表行/面板） | 白 `0.70 → 0.34` | 白 `0.11 → 0.04` |
| `glassBorder` | 白 `0.90` | 白 `0.16` |
| `glassHighlight`（顶部镜面高光） | 白 `0.55 → 0` @ stop 0.30 | 白 `0.18 → 0` @ stop 0.28 |
| `glassShadow` | 黑 `0.10` blur 28 offset(0,10) | 黑 `0.45` blur 28 offset(0,10) |
| `navShadow`（底部悬浮导航投影） | 黑 `0.16` blur 28 offset(0,12) | 黑 `0.50` blur 28 offset(0,12) |

- 模糊 sigma 收敛为三档：`blurChip 12` / `blurCard 18` / `blurPanel 24`（现散落 12/18/24/26/28/30）。
- `solid`（底部弹层）继续用 `surface` 打底，只保留描边，不再半透明。

### 3.3 圆角令牌（13 值 → 5 档）

| 令牌 | 值 | 用途 |
|---|---|---|
| `radiusS` | 12 | 小 chip / 分段内滑块 / 标签 |
| `radiusM` | 16 | 按钮 / 输入框 / 小卡 |
| `radiusL` | 22 | 卡片 / 列表行 / 提示条 |
| `radiusXL` | 28 | 面板 / 弹窗 / 底部弹层 |
| `radiusPill` | `height/2` | 导航胶囊 / 开关 / 分段轨道 |

映射：`GlassPanel` 默认 28→XL；`GlassTile` 20→L；`GlassButton` 20→M；`GlassActionButton` 14→M；`GlassDialog` 24→XL；`GlassSegment`/`GlassSwitch`/导航胶囊→Pill；Snackbar 20→L。

### 3.4 间距令牌（4px 栅格）

`4 / 8 / 12 / 16 / 20 / 24 / 32`，外加固定控件高 `topbar 40` / `button 56` / `nav 64`。替换散落 magic number（如 FAB `-76` 偏移、`_outerPad 16`、日历顶栏 40 等统一走令牌）。

### 3.5 动效令牌（Q 弹 → 弹簧物理）

- **弹簧**：`SpringDescription(mass: 1, stiffness: 400, damping: 16)`（约 0.35 过冲，Q 弹但可控），新增共享 `QSpring` 原语（`AnimationController` + `SpringSimulation`）。
- **按压缩放**两档：`pressScale 0.96`（按钮/卡片/条目，缩小）；`pillGrow 1.06`（胶囊轨道/导航滑块，放大）。
- **时长为非弹簧过渡保留三档**：`dur.fast 120` / `dur.med 220` / `dur.slow 340`（开关轨道色、分段吸附、页面转场用）。
- 拖拽跟手逻辑（`Duration.zero` 那段）**保持不变**。
- 页面转场保留现有「右滑淡入」FadeSlide，统一 `dur.slow` + `easeOutCubic`。

### 3.6 图标令牌（outlined 线性）

- 统一用 Material `Icons.*_outlined`；无 `_outlined` 变体的图标手动降级或换等价线性图标。
- 新增 `AppIcon` 包装：统一 `size`（导航 22、按钮内 20、列表 20）与描边粗细，杜绝到处 `Icon(... size: n)`。
- 涉及替换的 filled→outlined 清单在实施时逐文件列出（现主要落在 `profile_screen` / `schedule_editor` / `calendar` / `glass_delete_button` 的 `*_outline` 与 `circle_outlined` 穿插）。

### 3.7 排版令牌（system 字体，收拢字号）

| 令牌 | 值 | 用途 |
|---|---|---|
| `displayXL` | 84 | 响铃大时钟 |
| `display` | 28 | 大数字 |
| `title` | 20 | 页内主标题 |
| `heading` | 18 | 弹窗标题 |
| `body` | 14 | 正文 |
| `caption` | 12 | 说明文字 |
| `micro` | 11/10 | 标签/导航 |

字重收敛：标题 `w700`，强调 `w600`，正文 `w500`；去掉散落的 `14.5/13.5/12.5` 小数字号与 `w800` 混用（响铃时钟 `w800` 保留）。

---

## 4. 主题架构改造（`app_theme.dart`）

1. **中性 ColorScheme**：不再 `ColorScheme.fromSeed(accent)`（它会按主色相给整套 surface 染色）。改为中性 seed（如 `#5B6CFF` 以外，取灰 `#9AA0B4` 派生中性 surface）+ 显式覆盖 `primary = accent`、`onPrimary = white`。
2. **`secondary` 改跟随 accent**（不再固定 `#8A5CFF`），或置中性；M3 派生元素不再带蓝紫。
3. `scaffoldBackgroundColor` / `colorScheme.surface` 用 §3.1 的 `bg`/`surface` 中性值。
4. `cardTheme`/`appBarTheme` 等继续，但色值改走令牌。

---

## 5. 玻璃 = 磨砂模糊 + 半透明（无镜面高光）

- **玻璃质感配方**：真实背景模糊（`ImageFilter.blur`，sigma 三档：`blurChip/blurCard/blurPanel`）+ 半透明白 tint 渐变（`glassTint` 胶囊档 / `glassSurface` 卡片档）+ 1px 细描边（`glassBorder`），共同营造「液态玻璃」。
- **无镜面高光**：`GlassPanel` 与底部导航胶囊**不再叠加任何镜面高光层**——v0.4.4 的倾斜驱动动态光线与 v0.4.5 的静态左上高光实测观感均不佳，0.4.6 起彻底去掉高光，通透感交给模糊 + tint + 描边（见修订记录）。
- **降级**：`glassBlurDisabled == true`（内存 <4GB 自动，或用户关「高级材质」）时，玻璃组件退回更实填充，无模糊、无传感器。
- 响铃界面 `FlowingBackground` 保留「缓慢流动」骨架，为中性微光（非蓝紫、非倾斜驱动）。

---

## 6. 迁移清单（按文件）

**core/theme/**
- 新增 `design_tokens.dart`。
- `app_colors.dart`：只保留强调色 palette + shift 数据色 + 语义色；删除死玻璃令牌与 `gradientStart/gradientEnd`。
- `app_theme.dart`：中性方案 + accent 覆盖 + 令牌接入。
- `animated_background.dart`：`FlowingBackground` 中性化。

**core/glass/glass.dart**
- 玻璃配方从 §3.2 取值；`blurSigma` 三档；无镜面高光；保留 `glassBlurDisabled` 降级链路。

**core/widgets/（10 个共享组件）**
- 全部改引令牌；`GlassButton`/`GlassActionButton`/`GlassDialog`/`GlassSegment`/`GlassSwitch`/`GlassSnackbar`/`glass_pickers` 的填充/圆角/时长/图标统一；`glass_delete_button` 的 `delete_outline` 换 outlined 收编；`_red` 归一 `danger`。

**features/（8 个页面）**
- 9 处硬编码 `Color(0x...)` 收编：`alarm_ringing_screen`（`0xFF0B0B14` 背景→`bg`、`0xFFE2E2EC`/`0xFF6E6E82`/`0xFF9A9AB0` 灰阶→令牌）、`alarm_screen`（`0xFF4ADE80`/`0xFFF87171`→`success`/`danger`）、`calendar_screen`（`_holidayRed`→`holiday`）、`profile_screen`（`0xFFE53935`×2→`danger`）。
- `home_shell`：导航选中滑块改 `accentGradient(accent)`，修「换主色导航不换色」。
- 全图标 outlined 化 + `AppIcon` 统一。
- 列表行/卡片的圆角、时长、字号收敛到令牌。

---

## 7. 范围外（本次明确不做）

- 不动业务逻辑、Drift 数据模型、闹钟/通知原生链路。
- 班次数据色、节假日红、seed 默认数据不变。
- 不改 `X.Y` 版本号；不动跨端（Windows/iOS/鸿蒙）规划。
- 不引入新第三方依赖（Q 弹用手写 `SpringSimulation`，不引 `flutter_animate`；v0.4.4 临时引入的 `sensors_plus` 已随动态光线在 0.4.5 一并移除）。

---

## 8. 验收标准

- `flutter analyze` 0 error / 0 warning；`flutter test` 6/6（现有单测不回归）。
- 视觉抽查：亮色/暗色 × 5 主色各过一遍，确认「背景中性、强调点随主色、导航随主色」。
- 低端机 / 关「高级材质」：真实模糊与动态光线正确回退，无崩溃、无空指针。
- 无新增硬编码 `Color(0x...)` / 非令牌圆角 / 非令牌时长进入 feature 层。

---

## 9. 版本与更新日志

- 版本 `0.4.3+63 → 0.4.4+64`：`pubspec.yaml` 与 `app/lib/core/app_info.dart` 两处同步。
- 更新日志 `app_dialogs.dart` prepend 新条目、删最旧、保持 10 条；末位非 0，按测试版原样写本版改动（不归纳）。

---

## 10. 修订记录

| 日期 | 版本 | 改动 |
|---|---|---|
| 2026-09-03 | 0.4.4+64 | 初稿：设计令牌层 + 动态光线玻璃 + outlined 图标 + 弹簧动效，实施「设计语言大一统」。 |
| 2026-09-03 | 0.4.5+65 | **移除倾斜动态光线**（实测观感不佳）：删除 `LightController` / `sensors_plus`，玻璃高光恢复静态左上；底部导航胶囊悬浮化（去磨砂蒙版、近实填充 + 强投影）；应用图标按设计语言重绘。§2.3 / §5 / §6 / §7 同步更新。 |
| 2026-09-04 | 0.4.6+66 | **彻底去掉玻璃镜面高光**（静态左上观感差）：`GlassPanel` 与底部导航胶囊删除高光层；底部导航胶囊去掉投影（`navShadow` 删除）、填充改回半透明磨砂（`navFill` 亮 0.62→0.28 / 暗 0.14→0.06）并恢复真实背景模糊，内容滑过若隐若现。§2.3 / §5 / §6 同步更新。 |
| 2026-09-04 | 0.4.7+67 | **胶囊更通透 + 去浮层四周蒙版**：`navFill` 再降（亮 0.52→0.20 / 暗 0.11→0.045）；外层 `PageView` 包 `MediaQuery.removePadding(removeBottom: true)`，让页面内容无遮挡铺满到屏底、从悬浮胶囊下穿过，消除胶囊四周的空背景「蒙版」。 |
| 2026-09-05 | 0.4.9+69 | 胶囊浅色可见性（新增 `navBorder` 深色细描边、`navFill` 亮色 0.44→0.56）；胶囊左右边距 16→24；5 主题色微调（`#4F5BE8/#0B6FE6/#00B3A6/#F08800/#E83567`）；滑块选中文字改 `navForeground` 自动对比色。 |