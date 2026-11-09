# 设计理念 · 规范层（D1–D16）

> **应然**：动任何 UI / 视觉 / 动效 / 玻璃 / 触觉之前先读本文件。每条只写「现在必须怎么做」，
> 不写「当时为什么改」——那在 `docs/decisions/ui-rules.md`、`docs/decisions/glass.md` 与
> `docs/changelog/`（要查历史才去，别当必读）。
>
> 每条五段：**原则 → 落到哪 → 谁守门 → 例外与豁免 → 反模式**。
> 「谁守门」的三种强度（机器拦 / 半机器 / 自守）与全局矩阵见 `README.md` §2、§4。
> 标 **自守** 的，机器不拦、只有你在守——那是漂移高发点，别当"可选的优化"放掉。

## 总纲

**简洁 + 液态玻璃（磨砂模糊）+ Q弹动画。** 界面靠「层级、玻璃质感、动效」说话，
不堆颜色、不堆装饰。一切可调值收敛进 `app/lib/core/design_tokens.dart`（唯一来源），
界面层只写角色名、不写字面量。

一句话验收：**把这一屏的令牌、层级、玻璃档、动效全部按本文件走一遍，剩下的问题只能是"设计取舍"，
不可能是"实现跑偏"。**

## 原则

### D1. 令牌是唯一来源，界面层不写字面量
- **原则**：颜色/圆角/间距/模糊/时长/弹簧/排版/图标尺寸一律引用 `AppTokens`；排版走**角色令牌**
  （`pageTitle`/`rowPrimary`…），不写 `fontSize:`/`fontWeight:`。间距进 4px 栅格（`n==1 || n%4==0`）。
- **落到哪**：`core/design_tokens.dart` 的 `AppTokens`（15 个分节）；班次色只在 `core/shift_palette.dart`。
- **谁守门**：`test/design_tokens_test.dart`——扫 `lib/features`·`lib/core/widgets`·`lib/core/glass`·
  `lib/core/theme` 四根目录（89 个 lib 文件中的 62 个），7 条规则：`fontSize` 数字、
  `onSurface.withValues(alpha:)`、`FontWeight.`、`circular(数字)`、`Duration(milliseconds:)` 数字、
  `Color(0x`、`AppTokens.font[A-Z]`。**半机器**。
- **例外与豁免**：
  - 豁免注释 `// design-tokens-ignore: <理由>`，作用域=同一行或紧邻上一行，**必须带理由**，理由过词法校验。
    全仓真业务豁免只有 1 处（`core/widgets/glass_choice_chip.dart:39`，命中区补到 44dp，见 D15）。
  - **扫描网外**（改这些地方时靠人守）：`lib/core` 顶层 11 个、`lib/domain` 8 个、`lib/data` 5 个、
    `lib/state` 1 个文件；`EdgeInsetsDirectional` 完全不扫；`Duration(seconds:)` 不报；
    条件表达式里的 `fontWeight` 漏检；`Offset(`、`Positioned(`、`BorderSide(width:)`、`letterSpacing:` 同样不扫
    （现存唯一真漏：`features/alarm/alarm_ringing_screen.dart:247` 的 `letterSpacing: 2`，`AppTokens` 里没有这个令牌）。
  - **4px 栅格只管间距**：阴影位移、描边宽度、着色器常数（band/bend/thickness）不在其内，别硬套。
  - `core/theme/app_colors.dart` 的 `AppColors` 是历史残留（班次色 4 个字面量与
    `shift_palette.dart:55-58` 重复）。**新代码只用 `AppTokens` + `shift_palette`**；撞见就顺手往这两处收。
- **反模式**：为「差一点」新起 off-grid 常量、或内联数字（12.5/13.5/14.5/15/22 就是这么冒出来的）。

### D2. 层级只靠字号、字重、明度
- **原则**：内容的强弱只用这三样表达，不靠颜色堆叠。
- **落到哪**：`AppTokens` 角色令牌 + 明度两档 `inkMuted`(0.62) / `inkFaint`(0.35)，以及
  `AppTokens.inkMuted(context)` 这类 context 形态。
- **谁守门**：`design_tokens_test`——字号/字重归 D1 那 7 条规则；**alpha 字面量同样被禁**
  （`onSurface.withValues(alpha:)`），所以明度是**半机器**，不是自守。
- **例外与豁免**：`navInactiveForeground`（0.72 / 0.55）与 `design_tokens.dart` 内定义的 alpha 在扫描网外，
  改动时靠人守；新增明度档必须先加进 `AppTokens` 再引用。
- **反模式**：给次要文字另调一个 0.45/0.5/0.55 的 alpha（历史上一角色被调出四种，收敛成 0.62）。

### D3. 白字压实心主色面，按需压深到「刚好过 AA」
- **原则**：白字/白图标压实心主色时，只把不够的主色压到刚过 WCAG AA，本来就够的一个像素不动。
  实现目标是 **4.52**，测试判 **4.5**（0.02 是留给浮点的余量，别去"对齐"它）。
- **落到哪**：`AppTokens.solidAccent`（定义，HSL 逐档 −0.004 压到刚过线）+ `navForeground` / `onSolid`（取字色）。
- **谁守门**：`design_tokens_test`（够的不许动、压过的再亮 2% 不许过线）+ `glass_segment_ink_test`
  （真渲一个 `GlassSegment`，读最终解析出来的字色）。**盲区：只测纯函数，不查调用点。**
  **已知硬违规（待修）**：`features/schedule/recurring_fields.dart:432-453`「每月几号」的选中方块是
  raw 主色 + `Colors.white`，五个可选主色里 teal 2.63 / orange 2.55 不过 AA（共享组件 9 处都正确走了 `solidAccent`）。
- **例外与豁免**：`navForeground` 之外的自定义实心面上写白字，必须先算对比度再落字色，不许"看着行"。
- **反模式**：一律「明度 ×0.62」不问深浅地砍（v0.11.21 默认蓝 5.26→11.35，用户报「太暗」）；
  或给浅色档取近黑字色（判据是"压在哪块底上"，不是"现在浅色还是深色"）。

### D4. 玻璃配方两档；省电档结构、布局、交互一字不变
- **原则**：胶囊/按钮走 `glassTint`、卡片/面板走 `glassSurface`、边框走 `glassBorder`；
  `blurOn=false`（低端机 / 关高级材质）时**更实**，但结构、布局、命中区、动效节奏一字不变，
  只允许"模糊与折射不画"这一个差异。
- **落到哪**：`AppTokens.glassTint` / `glassSurface` / `glassBorder`（**定义在 `design_tokens.dart`，不在 `glass.dart`**）
  + `core/glass/glass.dart` 的 `GlassPanel`/`GlassTile`。
- **谁守门**：`glass_tier_test`——**半机器**：省电档只做结构断言（`GlassBlur` 不挂 `BackdropFilter`），
  像素断言只有反方向一条（液态关/开必须不同，`differing>0`）。**没有"两档逐像素相同"的断言**，
  别以为它守着那条 —— 那是待补的第 6 条（见 `README.md` §6）。
- **已知违规（待收）**：`core/widgets/glass_pill.dart:71-96` 与 `calendar_screen.dart:1117-1142` 的 `_circleIcon`
  逐字复制了**第四套配方**（`0.95/0.55` + border `0.95/0.28` + black `0.35/0.10`），不是 `glassTint`(0.80/0.45)；
  另有 6 处近似变体。收法：`_circleIcon` 改复用 `glass_pill`，配方回令牌（**配方只许一份**）。
- **例外与豁免**：底栏是唯一 `refract:true` 处（见 D10）；省电档不许用"多画一层实色"去补观感。
- **反模式**：动 `glassTint`/`glassSurface` 的 alpha 去"救"饱和度（实测否掉：底近中性救不回来，
  还破坏省电档观感）。

### D5. 液态档判据只许定义处 + 6 个文件；静止玻璃面不加
- **原则**：液态档的「开/关」判据只许出现在 `core/glass/glass.dart` 定义处 + 6 个文件（实测 12 处读取，`calendar_screen` 独占 8 处）
  （`features/home/`、`glass_check.dart`、`glass_segment.dart`、`glass_switch.dart`、
  `alarm_ringing_screen.dart`、`calendar_screen.dart`）。往别处搬先想：那处得有
  ①胶囊容器 ②会滑动/被按住的指示块 ③四周有空隙凸出去；**静止玻璃面不加**（静止时这套东西一个像素都不画）。
- **落到哪**：名单在 `test/liquid_scope_guard_test.dart`；三个开关的**唯一写入点**是
  `state/app_settings.dart`（`liquidGlassEnabled` / `glassBlurDisabled` / `liquidRefractionEnabled`），
  其余地方只读 `.value`。
- **谁守门**：`liquid_scope_guard_test` 扫源码守名单——**半机器**：它只匹配 needle `liquidGlassActive`，
  开关真源那三个名字**不在名单也匹配不到**，所以"从 `app_settings` 外面改开关"它拦不住。
- **例外与豁免**：`calendar_screen.dart` 有 8 处读 `.value`，全部在名单内；新增读取点=改名单=过评审。
- **反模式**：给 `enableBlur:false` 的列表行加液态光（v0.10.2 闹钟页/待办页各报一次「边缘有点丑」）。

### D6. 触觉三档、挂动作不挂按压、共享组件不重复震
- **原则**：只三档——`select()`（选中变了）/ `commit()`（动作落实）/ `modeEnter()`（进入模式）；
  普通点击、列表行、滚动、滚轮一律不震；共享组件已自动震过的，调用点绝不再补。
- **落到哪**：`core/haptics.dart`（唯一许出现 `HapticFeedback.` 的地方）。
- **谁守门**：`haptics_guard_test`（全 `lib/` 除 `haptics.dart` 不许出现 `HapticFeedback.`）+
  `haptics_commit_points_test`（"不重复震"的常驻用例）——**机器拦**。
- **例外与豁免**：无。要加第四档就改 `haptics.dart` 并同步本条与矩阵。
- **反模式**：给 `GlassSwitch`/`GlassSegment` 的调用点再挂 `commit()`（它们自己发过 `select()`，补了就一次震两下）。

### D7. 可编辑暗示只用三种视觉语言
- **原则**：有框的输入框 = 直接打字；铅笔 = 点开进入编辑表单；箭头 = 点开打开别的东西。
  判定只看「点开之后是什么」，不看「看起来像什么」。
- **落到哪**：值行一律 `core/widgets/glass_value_row.dart` 的 `GlassValueRow`
  （现 8 处调用：`alarm_screen.dart:416/442`、`schedule_management_screen.dart:325/460/560`、
  `recurring_fields.dart:323/341`、`schedule_screen.dart:687`）。
- **谁守门**：`editable_affordance_test` 按页面钉住三种视觉语言——**半机器**：新页面不在名单内就不设防。
- **例外与豁免**（**五处**有意例外，改之前先读决策层）：重复待办面板、取色圆点、长按拖选、年月胶囊、
  待办行整行无暗示（`schedule_screen.dart:470-475` 自证：2026-11-05 用户真机否掉了这行的铅笔，行仍整行可点）。
- **反模式**：裸 `TextField` 当"能改"的入口（班组名因此没人发现能改）；给「标签+值+箭头」手写
  `ListTile+trailing`（窄窗抛 `Trailing widget consumes the entire tile width`）。

### D8. 新界面必须进视觉工装屏单
- **原则**：加新页面/弹层/特殊状态（含展开态），往 `app/tool/visual/visual_screens.dart` 的屏单加一条
  再出图看——屏单是唯一会「看」的眼睛，令牌守门看不出「裸文字徽章」和「胶囊」的差别。
- **落到哪**：`app/tool/visual/`（屏单 49 条 slug；现有 10 个 `*_screen.dart` 全覆盖）。
  **已知缺口**：两条有布局风险的弹层从没进单 —— `RecurringRulePicker`（`recurring_fields.dart:70`）、
  `EventTimingPicker`（`:297`），`test/` 与 `tool/` 里零命中。
- **谁守门**：**自守**。屏单是清单不是护栏——`test/` 里没有任何"新屏未进单"的机械校验。
- **例外与豁免**：无。屏重命名要同步改屏单（`render_screens_test.dart:111` 会 `throw` 说明屏改名了）。
- **反模式**：新界面不进屏单（v0.8.1 四处跑偏，三道评审 + 令牌守门都没拦住）。

### D9. 弹簧两条方向分开，离散格式上调
- **原则**：提起/落下、亮起/熄灭这类「去」和「回」手感不同，各一条弹簧；别拿连续解理论公式调，
  要在与实现同一套离散格式（半隐式欧拉、16ms 一帧）上扫数。
- **落到哪**：`AppTokens` 里 **6 组 12 个标量**：`lensLiftOmega/lensLiftZeta`、`lensDropOmega/lensDropZeta`、
  `lensSlideOmega/lensSlideZeta`、`lensStretchOmega/lensStretchZeta`、`lensLitOmega/lensLitZeta`、
  `lensUnlitOmega/lensUnlitZeta`（**没有 `lensLift*` 这种通配名**）+ `lensMaxStep`(16ms) 与
  `liquid_lens_controller.dart` 的方向选择。
- **谁守门**：`liquid_lens_test`——**半机器**：只钉了 `Lift vs Drop` 不对称；
  `lensLit`/`lensUnlit` 在 `test/` 与 `tool/` **零命中**。16ms 那头由 `lensMaxStep` + 帧率无关用例撑着。
- **例外与豁免**：单条弹簧（不区分"去/回"）只许出现在纯装饰、无方向语义的地方。
  **已知单条实例**：`calendar_range_band.dart:168-185` 的 `_lift` 固定 `lensLift`、从不切 `lensDrop`（`_ring` 才切）
  —— 属"带只提起"，必须在文件内一行注释说明，否则按缺配对处理。
- **反模式**：照公式填 ζ（照公式 0.72 实测过冲 0.00%）。

### D10. 玻璃不能采样玻璃；着色器 uniform 0 不是你的
- **原则**：折射只发生在「玻璃↔背景」边界；任何「按容器尺寸归一化」的着色器，容器尺寸要**另立 uniform**
  （引擎会把第 0 个 vec2 uniform 覆写成输入纹理尺寸，模糊还会外扩纹理）。
- **落到哪**：`app/shaders/glass_refraction.frag`（`uSize/uOrigin/uRadius/uBand/uBend/uThickness` 之后才是
  `uContainer`）+ `core/glass/glass_refraction.dart` 的 `setFloat(8, width*dpr)` / `setFloat(9, height*dpr)`。
- **谁守门**：`glass_refraction_test`（源码前提逐字钉 floats 8/9、禁 `setFloat(0/1)`、Skia 返回 null 不抛）——
  **机器拦**。"玻璃不采样玻璃"由 `glass_refraction_test.dart:369`（全仓只有底栏一处 `refract:true`）间接守。
- **例外与豁免**：新增折射点=同时改 `refract:true` 名单与这条的例外段。
- **反模式**：把折射带 20 / bend 12 套到 46 宽的开关上（clamp 成 14，整颗钮在抖）。
  bend 的实际值是 `glass_refraction.dart:206` 的 `_bendLogic = 12`；`sanitizeGeometry` **只夹 band 不夹 bend**。

### D11. 班次色可读性 = 描边对比度，不是色块本身
- **原则**：班次色走「14% 淡染 + 45% 描边」，可读性压在那道描边上；描边对四处卡底
  （App 浅 `#FFFFFF`/深 `#16161E`、小组件浅 `#F5F5F5`/深 `#24242B`）对比度 ≥ **1.3501**。
  文字色另走 `AppTokens.inkFor`（App）/ 小组件走中性 `wg_ink_*`。
- **落到哪**：`core/shift_palette.dart` 的 `kShiftPalette` / `kShiftColorBar`。
- **谁守门**：`shift_palette_test`（16 颗 × 4 卡底逐颗断言，门槛钉在现有八颗的下界 1.350188）——**机器拦**。
- **例外与豁免**：卡底以 int 形式存（`shift_palette.dart:11-15` 有注释说明为何不存 `Color`），改门槛要动常量。盘里一颗都不许多。
- **反模式**：往盘里塞正黄 `#FFCC00`（白卡上 1.22 必红）——「黄」只能是琥珀/暗金/橄榄。

### D12. 正文禁截断；单行溢出只许 ellipsis
- **原则**：中文正文默认**不许**出现截断（`…`/裁字/裁边框）。两条判据一起用：
  ①**段落自截**：`kDeliberateEllipsis` 白名单里的每一条都要写出"为什么这里截断是对的"；
  ②**容器裁短**：渲染结果与期望尺寸差 > 2px 即算裁短。
  单行文字溢出时只许 `TextOverflow.ellipsis`，不许 `fade`、不许 `softWrap:false` 硬剪。
- **落到哪**：`app/tool/visual/visual_harness.dart`（`kDeliberateEllipsis` 与两判据）+ 各单行文本的
  `overflow: TextOverflow.ellipsis`（lib 内 22 处，`TextOverflow.fade` 0 处）。
- **谁守门**：`tool/visual/text_fit_guard_test.dart`（全屏 × 每档字号 × 320/360 宽 × 中英 四维矩阵）——**机器拦**。
- **例外与豁免**：白名单当前为**空表**。要加一条必须写理由，且理由要能回答"为什么不能换行/不缩字号"。
- **反模式**：用"再小一号字"或"加个 `fade`"糊过去（看不出来，但用户看得出来）。

### D13. 字号自管，系统 textScaler 整层替换
- **原则**：字号由 `AppTokens` 角色令牌决定，**整层替换 `textScaler`**（App 内字号设置是唯一来源），
  不跟随系统字号缩放；代价是自己兜住最坏情况——320 宽 + 最大字号档 + 英文长词，由 D12 的矩阵兜。
- **落到哪**：`app.dart:54`（`MediaQuery` 覆写）+ `state/app_settings.dart:70`（档位）+ `features/profile/profile_screen.dart:134`（入口）。
- **谁守门**：**自守**（实际防线是 D12 的矩阵；这是"用自管换稳定，用矩阵还债"的一对）。
- **例外与豁免**：小组件（RemoteViews）不在 App 层，字号由原生侧定，不在本条范围。
- **反模式**：某处"顺手尊重一下系统字号"——那一处立刻变成新的溢出源。

### D14. 24 小时制写死，`1440` 显示 `24:00`
- **原则**：时间显示一律 24 小时制（无 AM/PM、无 12 小时格式）；分钟数一律格式化成 `HH:mm`，
  跨日边界 **1440 显示 `24:00`**（不是 `00:00`——那会读成"当天零点"）。
- **落到哪**：`domain/shift_rotation.dart:51`（分钟→`HH:mm`）+ `core/l10n.dart` 的 `crossesMidnight`
  （文案是「晚于 24:00」）。
- **谁守门**：班次时间串相关用例 + `time_of_day_guard_test`（`TimeOfDay.now()` 只有响铃页一处白名单）——**半机器**。
- **例外与豁免**：`alarm_ringing_screen.dart:196` 的 `TimeOfDay.now()` 是刻意豁免（响铃页时钟，`time_of_day_guard_test` 守）。
- **反模式**：为了"国际化"引入 AM/PM，或把 24:00 归一成 00:00。

### D15. 命中区 44dp，视觉尺寸与命中区分离
- **原则**：可点元素的有效命中区 ≥ 44×44dp；视觉可以比 44 小（用 `Padding`/`Transform` 撑命中区），
  **不许**为了命中区把视觉放大，也不许让命中区重叠。
- **落到哪**：`core/widgets/glass_choice_chip.dart:37-39`（命中区补到 44dp，D1 的唯一豁免）、
  `core/widgets/glass_segment.dart:37`、`core/widgets/glass_pickers.dart:90`。
- **谁守门**：`press_feedback_guard_test` 等按件钉——**半机器**。
- **例外与豁免**：整行可点的列表行（命中区=行高）不需要额外撑；跨全宽的拖拽区同理。
- **反模式**：直接给 28dp 的圆点挂 `GestureDetector`（点不中，用户以为是坏的）。

### D16. 豁免必须具名可查（元规矩）
- **原则**：任何"这条规矩此处不适用"的例外，都必须**写在代码里、带理由、可被搜到**；
  规范层的「例外与豁免」段是唯一登记处，代码里的豁免注释是它的镜像。三者对不上即为漂移。
- **落到哪**：`// design-tokens-ignore: <理由>`（D1）、`kDeliberateEllipsis` 每条带理由（D12）、
  `time_of_day_guard_test` 的白名单（D14）、`liquid_scope_guard_test` 的名单（D5）、本条目的各处例外段。
- **谁守门**：`design_tokens_test` 会解析豁免标记并**要求带理由**（空理由/无理由不生效）——**半机器**；
  其余靠评审。
- **例外与豁免**：本条没有例外。写不出理由的豁免，就是不成立。
- **反模式**：`// ignore` 一把梭、或把豁免注释写成"暂时"（没有到期日的暂时等于永久）。

### D17. 弹层只走三个入口；破坏性动作红 + 具名确认
- **原则**：弹层只有三条入口 —— `showGlassDialog` / `showGlassSnack` / `showGlassSheet`；
  删除/清空/覆盖必须用 `danger` 变体（红），确认文案写明**问句 + 后果 + 不可撤销**。
- **落到哪**：`core/widgets/glass_dialog.dart`（26 处 dialog、18 处 snack、10 处 sheet；`danger` 变体 9 处）；
  确认文案在 `core/l10n.dart:224-231/679-690/775-778/848-851`。
- **谁守门**：**半机器**：裸 `showDialog` / `showModalBottomSheet` 当前全仓 **0** 处 —— 这条的命门就是别开第一处；
  「破坏性动作必须红」没有断言。
- **例外与豁免**：系统级弹层（权限说明、`showDatePicker` 类原生选择器）不在此内。
- **反模式**：靠注释记数（`glass_action_button.dart:50` 自称"全 app 四处"，实测 9 处 —— 见 E15 的"不许裸写计数"）。
