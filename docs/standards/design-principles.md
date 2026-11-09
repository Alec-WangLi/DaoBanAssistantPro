# 设计理念 · 规范层（写给 agent）

> **应然**：动任何 UI / 视觉 / 动效 / 玻璃 / 触觉之前先读本文件。每条只写「现在必须
> 怎么做」，不写「当时为什么改」——那在 `docs/decisions/ui-rules.md`、
> `docs/decisions/glass.md` 与 `docs/changelog/`（要查历史才去，别当必读）。
>
> 每条四段：**原则 → 落到哪 → 谁守门 → 反模式**。
> 「谁守门」标 **自守** 的，机器不拦、只有你在守——那是漂移高发点，别当「可选的优化」放掉。

## 总纲

**简洁 + 液态玻璃（磨砂模糊）+ Q弹动画。** 界面靠「层级、玻璃质感、动效」说话，
不堆颜色、不堆装饰。一切可调值收敛进 `app/lib/core/design_tokens.dart`（唯一来源），
界面层只写角色名、不写字面量。

## 原则

### 1. 令牌是唯一来源，界面层不写字面量
- **原则**：颜色/圆角/间距/模糊/时长/弹簧/排版/图标尺寸一律引用 `AppTokens`；排版走**角色令牌**（`pageTitle`/`rowPrimary`…），不写 `fontSize:`/`fontWeight:`。
- **落到哪**：`core/design_tokens.dart` 的 `AppTokens`。
- **谁守门**：`test/design_tokens_test.dart` 扫 `lib/features`·`lib/core/widgets`·`lib/core/glass`·`lib/core/theme` 的字面量 + 间距 4px 栅格（具名豁免 `// design-tokens-ignore: <理由>`）。
- **反模式**：为「差一点」新起 off-grid 常量、或内联数字（12.5/13.5/14.5/15/22 就是这么冒出来的）。

### 2. 层级只靠字号、字重、明度
- **原则**：内容的强弱只用这三样表达，不靠颜色堆叠。
- **落到哪**：`AppTokens` 角色令牌 + 明度两档 `inkMuted`(0.62) / `inkFaint`(0.35)。
- **谁守门**：字号/字重由 `design_tokens_test` 守；明度 alpha **自守**。
- **反模式**：给次要文字另调一个 0.45/0.5/0.55 的 alpha（历史上一角色被调出四种，收敛成 0.62）。

### 3. 白字压实心主色面，按需压深到「刚好过 AA」
- **原则**：白字/白图标压实心主色时，只把不够的主色压到刚过 WCAG AA（4.52），本来就够的一个像素不动。
- **落到哪**：`AppTokens.solidAccent`（定义）+ `navForeground` / `onSolid`（取字色）。
- **谁守门**：`design_tokens_test`（够的不许动、压过的再亮 2% 不许过）+ `glass_segment_ink_test`（渲真分段器读字色）。
- **反模式**：一律「明度 ×0.62」不问深浅地砍（v0.11.21 默认蓝 5.26→11.35，用户报「太暗」）；或给浅色档取近黑字色（判据是「压在哪块底上」，不是「现在浅色还是深色」）。

### 4. 玻璃配方两档；省电档逐像素不变
- **原则**：胶囊/按钮走 `glassTint`、卡片/面板走 `glassSurface`；`blurOn=false`（低端机/关高级材质）时更实，但结构/布局/交互一字不变。
- **落到哪**：`AppTokens.glassTint` / `glassSurface` / `glassBorder` + `core/glass/glass.dart` 的 `GlassPanel`/`GlassTile`。
- **谁守门**：`glass_tier_test`（两档逐像素一致）。
- **反模式**：动 `glassTint`/`glassSurface` 的 alpha 去「救」饱和度（实测否掉：底近中性救不回来，还破坏省电档观感）。

### 5. 液态档判据只许 6 个调用点；静止玻璃面不加
- **原则**：液态档的「开/关」判据只许出现在 `core/glass/glass.dart` 定义处 + 6 个调用点（`features/home/`、`glass_check.dart`、`glass_segment.dart`、`glass_switch.dart`、`alarm_ringing_screen.dart`、`calendar_screen.dart`）。往别处搬先想：那处得有①胶囊容器②会滑动/被按住的指示块③四周有空隙凸出去；**静止玻璃面不加**（静止时这套东西一个像素都不画）。
- **落到哪**：见 `test/liquid_scope_guard_test.dart` 的名单。
- **谁守门**：`liquid_scope_guard_test` 扫源码守名单；「观感合不合适」**自守**。
- **反模式**：给 `enableBlur:false` 的列表行加液态光（v0.10.2 闹钟页/待办页各报一次「边缘有点丑」）。

### 6. 触觉三档、挂动作不挂按压、共享组件不重复震
- **原则**：只三档——`select()`（选中变了）/ `commit()`（动作落实）/ `modeEnter()`（进入模式）；普通点击、列表行、滚动、滚轮一律不震；共享组件已自动震过的，调用点绝不再补。
- **落到哪**：`core/haptics.dart`（唯一许出现 `HapticFeedback.` 的地方）。
- **谁守门**：`haptics_guard_test` 扫 `lib/` 不许 `HapticFeedback.`；「不重复震」名单 **自守**。
- **反模式**：给 `GlassSwitch`/`GlassSegment` 的调用点再挂 `commit()`（它们自己发过 `select()`，补了就一次震两下）。

### 7. 可编辑暗示只用三种视觉语言
- **原则**：有框的输入框 = 直接打字；铅笔 = 点开进入编辑表单；箭头 = 点开打开别的东西。判定只看「点开之后是什么」。
- **落到哪**：值行一律 `core/widgets/glass_value_row.dart` 的 `GlassValueRow`。
- **谁守门**：**自守**。
- **反模式**：裸 `TextField` 当「能改」的入口（班组名因此没人发现能改）；给「标签+值+箭头」手写 `ListTile+trailing`（窄窗抛 `Trailing widget consumes the entire tile width`）。四处有意例外：重复待办面板、取色圆点、长按拖选、年月胶囊。

### 8. 新界面必须进视觉工装屏单
- **原则**：加新页面/弹层/特殊状态（含展开态），往 `app/tool/visual/visual_screens.dart` 的屏单加一条再出图看——屏单是唯一会「看」的眼睛，令牌守门看不出「裸文字徽章」和「胶囊」的差别。
- **落到哪**：`app/tool/visual/`。
- **谁守门**：**自守**（屏单是清单不是护栏）。
- **反模式**：新界面不进屏单（v0.8.1 四处跑偏，三道评审 + 令牌守门都没拦住）。

### 9. 弹簧两条方向分开，离散格式上调
- **原则**：提起/落下、亮起/熄灭这类「去」和「回」手感不同，各一条弹簧；别拿连续解理论公式调，要在与实现同一套离散格式（半隐式欧拉、16ms 一帧）上扫数。
- **落到哪**：`AppTokens.lensLift*` / `lensDrop*` / `lensLit*` / `lensUnlit*` 等。
- **谁守门**：`liquid_lens_test`。
- **反模式**：照公式填 ζ（照公式 0.72 实测过冲 0.00%）。

### 10. 玻璃不能采样玻璃；着色器 uniform 0 不是你的
- **原则**：折射只发生在「玻璃↔背景」边界；任何「按容器尺寸归一化」的着色器，容器尺寸要**另立 uniform**（引擎会把第 0 个 vec2 uniform 覆写成输入纹理尺寸，模糊还会外扩纹理）。
- **落到哪**：`app/shaders/glass_refraction.frag`（`uContainer`，灌 floats 8/9）+ `core/glass/glass_refraction.dart`。
- **谁守门**：`glass_refraction_test`（源码前提 + Skia 返回 null 不抛）。
- **反模式**：把折射带 20/位移 8 套到 46 宽的开关上（clamp 成 14，整颗钮在抖）。

### 11. 班次色可读性 = 描边对比度，不是色块本身
- **原则**：班次色走「14% 淡染 + 45% 描边」，可读性压在那道描边上；描边对四处卡底（App 浅 `#FFFFFF`/深 `#16161E`、小组件浅 `#F5F5F5`/深 `#24242B`）对比度 ≥ 1.3501。文字色另走 `AppTokens.inkFor`（App）/ 小组件走中性 `wg_ink_*`。
- **落到哪**：`core/shift_palette.dart` 的 `kShiftPalette` / `kShiftColorBar`。
- **谁守门**：`shift_palette_test`（逐颗 × 4 卡底）。
- **反模式**：往盘里塞正黄 `#FFCC00`（白卡上 1.22 必红）——「黄」只能是琥珀/暗金/橄榄。
