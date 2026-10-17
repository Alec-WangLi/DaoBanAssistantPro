# 今日卡片贴齐 App：通高竖条 + 其他班组胶囊（设计）

- 日期：2026-10-16
- 起因：用户 v0.11.25 真机测完之后，说周视图和月视图「基本上可以了」，只剩今日信息卡还有两处没跟 App 对应上：
  1. 「最左边的竖条：现在怎么只在最顶部那个日期那里？它不应该竖到下面吗？」
  2. 「其他班组：怎么没有那种半透明的胶囊？你看 APP 里边是有的。」
- 影响版本：v0.11.26 测试版（`X.Y` 由用户定，AI 只动 `Z` 与 `build`）
- 用户对「4 个班组」的拍板（2026-10-16）：「接受省略」—— 最多显示 4 个，放不下就降级，不为此把卡片做高。

---

## 1. 现状（对着 App 源码核出来的差距）

两处都是**真差距**，不是有意的（上一版我把「其他班组」的胶囊当「放不下」给省了，这一版补上）。

**① 竖条只在日期那一行。** App 的信息卡（`calendar_screen.dart` 的 `_infoCard`）在面板最左边有一条 `Positioned(left: 0, top: spaceLg, bottom: spaceLg, width: 6)` 的**通高主色竖条**（`DecoratedBox`，`borderRadius: pillOf(6)` = 半径 3dp = 6dp 宽的一半，即圆头胶囊）；内容整体让到它右边（面板内边距 `fromLTRB(spaceXl=20, spaceLg=16, spaceLg=16, spaceLg=16)`）。桌面这张卡现在那条是 `wg_tc_bar` **4dp × 24dp**、只占「日期」那一行的行首 —— 是 v0.11.23 搬今日卡时没搬全。

  颜色判据两边已经一致：`accent = shift != null ? shift.color : primary`（App `calendar_screen.dart:2411`），桌面是 `if (d.hasShift) d.color else snap.accent` —— 不用改，只改「通高」。

**② 其他班组没有胶囊。** App 的 `_otherCrewChips` 把每个班组画成「`Container`：8dp 实心圆点 + 6dp 间距 + 组名简称（12dp），外面套 **14% 淡染底 + 45% 描边**、圆角 `radiusS=12`、内边距 8/3」。桌面现在是 `widget_crew_chip.xml`：**14dp 淡色圆环 + 8dp 圆点 + 裸文字**，还摊在四个**等宽**槽位（`weight=1`）里 —— 既没胶囊、又不像 App 那样紧挨着左排。

  `WidgetChip.tintedChip` 已经是这个胶囊配方（fill alpha 36 ≈ 14%、stroke alpha 115 ≈ 45%、圆角 = 高的一半），所以胶囊不用新写，直接拿它套上去；只差「把位图宽按文字量出来、把圆环换成胶囊、把四个等宽槽换成左排」。

---

## 2. 目标 / 非目标 / 反目标

**目标**

- 竖条：6dp 宽、从内容顶通到内容底、贴卡片最左、圆头，颜色不变（shift.color ?? accent）。
- 其他班组：每个班组 = 8dp 实心圆点 + 组名简称，套进「14% 淡染 + 45% 描边」胶囊，胶囊紧贴文字、几颗**挨着左排**。

**非目标**

- 不动快照协议（v2，本轮**不新增字段**）。
- 不动今日卡以外的两张卡（周条 / 月历已定稿）。
- 不动卡片尺寸、字号缩放（`fitScale` 只缩不放那一套）、刷新、点击跳转。
- 不动「最多显示 4 个」这个上限（用户拍板「接受省略」）。
- 不把卡片做高去容纳第 4 个班组（用户拍板不做）。

**反目标**（做成了也算失败）

- 把胶囊画成「每个槽位填满」的宽胶囊 —— 那会像一排方盒，不是 App 的紧胶囊。
- 为了「4 个班组一行放下」去缩小字号或把组名截成单字。
- 在 Kotlin 里**另抄一份**字号 / 间距常量 —— 与 App 分岔不报错（`widget_today_card_guard_test.dart` 那条「同一档字号」已把字号钉住，间距这里同样只从一处取）。
- 竖条颜色改错：它必须跟着「当天班次色 ?? 主色」走，跟现在一样，别改成恒主色。

---

## 3. 关键决定

### 3.1 竖条：用**横向 LinearLayout** 让通高条贴左、内容列占满剩余宽

`widget_today_card.xml` 的根从「垂直 LinearLayout + 四周 22dp 内边距」改成 **横向 LinearLayout**（左内边距 0、上/右/下仍 22dp），两个子层：

- **竖条** `wg_tc_bar`：`layout_width="6dp"`、`layout_height="match_parent"`、`scaleType="fitXY"`，是根的**第一个直接子层**。
- **内容列**（原垂直 LinearLayout，去掉日期行里那根 4×24 的 `wg_tc_bar`，并把日期文本 `wg_tc_date` 的 `layout_marginStart="10dp"` **删掉**）：`layout_width="0dp" layout_weight="1"`（占满竖条右边的剩余宽）、`layout_height="wrap_content"`、`layout_marginStart="14dp"`（= 竖条 6dp + 14dp 间隙 = App 的 `spaceXl` 20dp）。

**为什么必须是横向 LinearLayout、不能是 FrameLayout。** 这里要的几何是「竖条高 == 内容列高」。`LinearLayout.measureHorizontal` 会在量完 `wrap_content` 的内容列之后，把 `match_parent` 高的竖条**重新量成 `EXACTLY` 这个高度**（对非主轴方向 MATCH_PARENT 子层的经典二次测量）；而 `FrameLayout.onMeasure` 对每个子层只量一次、取 max —— 竖条会按它自己那张 200dp 位图解析成**固定的 200dp**，跟内容列脱钩：内容 168dp 时竖条多出 32dp、内容 192dp 时多出 8dp，「竖条底 = 内容底」这条验收恒不成立，而且卡的根会被撑到 `max(200, 内容) + 44`、把卡片尺寸改了（非目标里明说不许动尺寸）。**别退回 FrameLayout。**

**竖条位图**：`WidgetChip.bar(color, dpToPx(6), dpToPx(200))` —— `bar` 就是圆头胶囊（`radiusPx = w/2`），6dp 宽 × 200dp 高，两端是半径 3dp 的半圆。200dp 是**够长的常量**：横向 LinearLayout 会把竖条拉伸到真实内容高（约 168~192dp），`fitXY` 只做这一步缩放，两端半圆半径在 2.5~3.4dp 之间浮动，肉眼看不出（竖条宽 6dp、半径 3dp，这点比例误差是亚像素级的）。**别去精算内容高** —— 内容高随农历折行、本月统计有无而变化，精算只会把一条简单的事搅复杂。

### 3.2 其他班组胶囊：文字驱动宽度 + 左排 + 上限 4 + 越界裁掉

`widget_crew_chip.xml` 重排（与班次胶囊 `widget_strip_cell.xml` 同一条「文字驱动宽度、位图贴上去」的套路）：

```
FrameLayout wg_cc_root  (wrap_content × 22dp)          ← 胶囊就是这一层的高度
  ImageView wg_cc_bg     (match_parent × match_parent)  ← tintedChip 胶囊位图
  LinearLayout           (horizontal, match_parent × match_parent, gravity center_vertical, paddingHorizontal 8dp)
    ImageView wg_cc_dot  (8dp × 8dp)                     ← WidgetChip.circle 实心圆
    TextView  wg_cc_text (wrap_content, marginStart 6dp, 12dp, maxLines 1)
```

- **内层 LinearLayout 必须 `match_parent` 高**：它的 `center_vertical` 只居中**它自己的子层**（圆点 + 文字），自己若缩成内容高就会顶到胶囊上沿 —— 圆点+文字要的是在 22dp 胶囊里**垂直居中**（上下各约 3dp），靠「内层撑满 + `center_vertical`」拿到。
- 胶囊位图宽 = `measureText("${name} ${abbr}", 12dp) + 26dp`（左内边距 6 + 圆点 8 + 间距 6 + 右内边距 6；
  **内边距为什么是 6 而不是 App 的 8，见下面 §3.3 的订正**），Kotlin 侧现量（复用 `chipWidthPx` 的
  `Paint.measureText` 路子，新增一个 `crewChipWidthPx`）。
- 14dp 的淡色圆环**删掉**（App 里没有，只有 8dp 实心圆点）。
- 胶囊高 22dp（与现有「其他班组」那行同高，`tintedChip` 圆角 = 11dp，App 是 12dp，同量级）。

**左排**：`widget_today_card.xml` 里 `wg_tc_crew_row` 那四个槽位 `wg_tc_crew_slot1..4` 从 `layout_width="0dp" + layout_weight="1"`（等宽）改成 **`layout_width="wrap_content"`**（自然宽），加 `layout_marginStart="8dp"`（与 App 的 `Wrap(spacing: spaceSm)` 一致 —— `spaceSm = 8`，**不是 4**）。标签「其他班组」那行保持不变（`wrap_content` + `marginEnd 6dp`）。

**越界**：`RemoteViews` 没有换行布局，`wrap_content` 的一排胶囊装不下时由 `LinearLayout` 在**内容列右缘**（= 卡片视觉右缘往里 22dp，正好与其他行的右端对齐）把最后一颗挤窄。**三个班组**（用户当前正是 3 个）装得下、与 App 观感一致。

### 3.3 ⚠️ 订正（实施时真机量出来的，上面 §3.2 的两处估算都错了）

**① 胶囊内边距只能是 6dp，不是 App 的 8dp。** 上面按「每颗约 58.7dp」估的，真机量出来是
**77.3 / 77.3 / 65.3dp**（`一班 上夜` 这种 5 字串在 12dp 下比估的宽得多）。于是：

- App 那套排布需要 **303.3dp**（标签 47.7 + 8 + 81.3 + 8 + 81.3 + 8 + 69）；
- 而桌面这张卡的内容列只有 **299.7dp** 可用 —— 因为**桌面卡宽 341.7dp、App 的信息卡 368dp**
  （内容列 299.7 vs 332），同样的内容在桌面天然少 26dp。
- 差 4dp，`LinearLayout` 就把最后一颗挤成 **「四班…」**（真机第一次跑出来正是这样）。

**修法**：胶囊左右内边距 8 → **6dp**（每颗省 4dp、三颗省 12dp），位图宽度算式里的 30 → **26**。
改完真机复测：三颗 **77.3 / 77.3 / 65.3dp** 全部完整、胶囊之间仍是 App 的 8dp 间距，
末颗距内容列右缘还有 **8.0dp** 余量。

**② 「放不下就省略号」这句话要改准。** 真机看到的是 `LinearLayout` 把**最后一颗挤窄**，
不是硬裁：小溢出时那颗的 TextView 打省略号（「四班…」），**溢出更多时它会被挤到 0 宽、
整颗看不见**（4 个「其他班组」时就是这一档 —— 需要约 380dp、只有 299.7dp）。
两条都是**静默**的（不报错、不崩）。用户 2026-10-16 拍板「接受省略」时听的是「最后一个打省略号」，
实际第三种形态是「看不见」，**这一条要在交付时对用户说明**。

⚠️ **4 个班组这一档没有在真机上验过**：验它必须改用户真实的排班数据（把班组数从 4 改成 5），
那属于改动用户的数据，不做。上面那段是按同一套机制（3 颗时量到的那次挤窄）推的。

### 3.3 共用件不动

`WidgetChip.tintedChip` / `bar` / `circle` 原样复用，不改它们的配方（那是班次胶囊 / 徽章 / 色条的地基）。`chipWidthPx` 那条「文字现量」的护栏已有的不动，只新增「其他班组胶囊宽也来自 measureText」这一条。

---

## 4. 验收

1. **真机**（Redmi K90 Pro Max，adb）：今日卡出图，浅深两档，与 App 信息卡并排看。
2. **竖条通高**：量竖条的墨迹（主色），顶 = 内容第一行顶、底 = 内容最后一行底，宽 6dp、两端圆头。
3. **其他班组胶囊**：每个班组有 14% 淡染 + 45% 描边胶囊，紧贴文字、几颗挨着左排（与 App 间距同量级），圆点 8dp 实心、无圆环。
4. **4 个班组降级**：把种子库换成 5 班组（4 个「其他」），第 4 颗被卡片右缘裁掉、不报错、不挤别处。
5. **单测全绿**（当前 1092，只增不减）；`flutter analyze` 0/0；新增护栏逐条**反向验证过**（改回旧写法看它红）。
6. 逐像素比：竖条与胶囊之外，今日卡其余各行**零差异**。

## 5. 相关文件

- `app/android/app/src/main/res/layout/widget_today_card.xml`（根改 FrameLayout + 竖条 + 槽位改左排）
- `app/android/app/src/main/res/layout/widget_crew_chip.xml`（圆环换胶囊）
- `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt`（`renderTodayCard`：竖条位图 6×200、`crewChipWidthPx`、胶囊位图）
- `app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetChip.kt`（复用，不改）
- `app/lib/features/calendar/calendar_screen.dart`（`_infoCard` / `_otherCrewChips` —— 对照基准，不改）
- `app/test/widget_today_card_guard_test.dart`（护栏）
