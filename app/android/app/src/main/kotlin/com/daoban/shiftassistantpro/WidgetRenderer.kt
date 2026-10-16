package com.daoban.shiftassistantpro

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Paint
import android.util.TypedValue
import android.widget.RemoteViews

import java.time.LocalDate

/**
 * 排版。**纯渲染**：不写盘、不排闹钟、不读除宿主配置之外的任何系统状态。
 *
 * 与 ShiftWidgetBase 分开是为了能单独读懂它 —— 这个类里没有一行涉及
 * 「什么时候刷新」「刷新排在哪」，只有「给我一份快照，我给你一棵 RemoteViews 树」。
 *
 * 四条纪律：
 *  1. Kotlin 侧一个中文字面量都不许有。所有文案都来自快照（Dart 侧 `L10n` 产出）。
 *     唯一的例外是占位态那行应用名，它取自 `applicationInfo.loadLabel()`。
 *  2. 明暗一律**显式选资源**，不依赖 `-night` 限定符 —— `RemoteViews` 由宿主进程
 *     inflate，限定符在宿主进程里的解析顺序各家 ROM 不一致。
 *  3. 布局只用 RemoteViews 白名单里的类：FrameLayout / LinearLayout / RelativeLayout /
 *     GridLayout + TextView / ImageView。**没有 ConstraintLayout**，报的是运行期
 *     `ClassNotFoundException`，不是编译错误。
 *  4. **往容器里 `addView` 之前必须先 `removeAllViews`**（每一个容器、每一次渲染，
 *     包括 `continue` 逃掉的那几支）。见下面那条长说明 —— 漏掉它不会报任何错，
 *     只在部分机型上表现为「内容一变就重影」。
 */
object WidgetRenderer {

    /*
     * ── 纪律 4 的长说明：为什么每个容器在 addView 之前都要 removeAllViews ──
     *
     * 症状（2026-09-29 用户反馈，几个 OPPO / vivo 用户，开发机上复现不出来）：
     * 把某天的「前夜」按天改成「休班」之后，桌面小组件上的字**重影**了 ——
     * 旧班的字压在新班的字上、上一周的日期压在今天的日期上。
     *
     * 机制：桌面（宿主）收到与手上那棵视图树**同一个布局 id** 的 RemoteViews 时，
     * **不会重新 inflate**，而是走 `RemoteViews.reapply(...)`，把整串动作在已有的
     * 视图树上重放一遍。而 `AppWidgetHostView` 只管换掉旧的**根**视图，**不负责
     * 清空容器里的子视图**。于是同一个槽位每渲染一次就多一个格子；格子根是
     * `match_parent`（`widget_strip_cell.xml` / `widget_month_cell.xml`），
     * 后加的不会把先加的挤开，而是**叠在同一块面积上**。
     *
     * 为什么平时看不出来：两层内容完全一样时，合成结果只是略微糊一点、胶囊深一档，
     * 没人会注意。**只有某一格的内容变了，旧层才露出来** —— 这正是「改了排班才出现」
     * 的原因，也是它被当成新 bug 的原因（其实一直在叠，只是从前看不见）。
     *
     * 为什么只有部分机型：新一些的 AOSP / 启动器会**回收**已加进去的子视图
     * （`canRecycleView`，Android 12 起进了 CTS），刚好把缺陷盖住；旧框架与厂商分叉
     * 会老老实实再加一个。所以「我这台上没问题」不能当成这条不存在 —— 它取决于宿主，
     * 不取决于我们。`RemoteViews.addView` 的官方文档写的就是这条：宿主可能回收布局，
     * 要用 `removeAllViews(int)` 清掉已有的子视图。
     *
     * 护栏：`app/test/widget_fixed_cards_guard_test.dart` 里那条「每处 addView 的容器
     * 都先被 removeAllViews 清过」，扫的就是本文件。**别为消掉它的红而放宽正则** ——
     * 它是这条约定唯一的凭据（本文件没有编译期可以依赖的东西）。
     */

    /**
     * dp → px。`RemoteViews` 里的尺寸单位是 px，送给 `WidgetChip` 画位图前要自己乘密度。
     */
    private fun dpToPx(context: Context, dp: Int): Int =
        (dp * context.resources.displayMetrics.density).toInt()

    /**
     * 班次胶囊位图的**宽度**：按简称在 [textSizeDp] 下的实际排版宽度现量，两侧各留 4dp。
     *
     * **为什么现量而不是定值。** v0.11.23 用的是「基准 40dp（周条 36dp）× 缩放」——
     * 那在格子小的时候会把胶囊顶到格边：真机量到月历那格占格宽 **95.5%**，而 App 里
     * 同一颗只有 **81%**（用户 2026-10-16：「跟里边班次的胶囊又重合了……APP 里边其实
     * 不重合，有点间隙」）。App 走的是 `_shiftChip`：`padding: horizontal spaceXs(4) × s`
     * 包着 `FittedBox(Text(cellShift))` —— 宽度**跟着文字走**，所以「白」窄、「大休」宽。
     *
     * **为什么是 `Paint.measureText`。** `RemoteViews` 在宿主进程渲染、量不到文字宽，
     * 而能改容器尺寸的 `setViewLayoutWidth` 要 API 31（本仓 minSdk 26）。本函数跑在
     * **我们自己的进程**里、用的是同一套系统字体，量出来的就是桌面上真正会画出来的
     * 那个宽。布局那侧由 `TextView(wrap_content + paddingHorizontal 4dp)` 驱动同样的宽度，
     * 两者差的那点零头由 `fitXY` 吸收。
     *
     * 那 4dp 与 App 的 `spaceXs` 同一个数，**有意不乘缩放** —— 布局里 `paddingHorizontal`
     * 是固定 dp，两边取同一个值才不会一个宽一个窄。
     */
    private fun chipWidthPx(context: Context, abbr: String, textSizeDp: Float): Int {
        val density = context.resources.displayMetrics.density
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = textSizeDp * density }
        return (paint.measureText(abbr) + 8f * density)
            .toInt()
            .coerceAtLeast(dpToPx(context, 12))
    }

    // ── 字号缩放（2026-10-15） ─────────────────────────────────────────────
    //
    // 用户 2026-10-15：「桌面小组件仍按系统 sp 排版 —— 系统字号调到 200% 时桌面那张
    // 卡还会跟着变大」。真机实测（font_scale=2.0）今日卡的时间行被切、班组整行不见；
    // 根因是**卡片尺寸编译期定死（resizeMode="none"）而字号写 `sp`**。
    //
    // 两件事一起做：① 布局里全部改用 `dp`（不乘 fontScale）；② 这里按**真实格子
    // 尺寸**算一个缩放系数再 set 回去 —— 与 App 日历格同一条规则
    // （`app/lib/features/calendar/calendar_screen.dart:1893` 的
    // `s = (cellH - _cellInset*2) / _cellDesignH`）。
    //
    // 基准数与 App 的 `app/lib/core/design_tokens.dart` 同源：
    //   `cellDateSm` 13 / `cellShift` 12 / `tinyLabel` 11，
    //   以及 `calendar_screen.dart:3015` 的 `_cellDesignH = 55`、`_cellInset = gapHair = 2`。
    // **改那边要回来改这里。**

    /** 与 `_cellDesignH` 同一个数。 */
    private const val CARD_DESIGN_H = 55f

    /**
     * 下限 0.85（App 是 1.0）：App 的格子永远 ≥ 设计尺寸，而桌面的格高**由启动器给**，
     * 可能更矮 —— 那时宁可字小一档，也不要溢出（桌面外壳没有滚动，溢出就是切字）。
     * 上限 1.25 与 App 同档。
     */
    private const val MIN_CARD_SCALE = 0.85f
    private const val MAX_CARD_SCALE = 1.25f

    /**
     * 今日卡的**设计高度**（dp）：按基准字号排布时，**去掉根内边距之后**内容占多高。
     *
     * 与 App 的 `_cellDesignH = 55` 同一种做法 —— 而且同样是量出来的，不是推的。
     * 推法（真机实测反推，Redmi K90 Pro Max · 3× · 2026-10-15）：
     *   卡片 256.3dp，上下余量 27.3 / 37.0dp ⟹ 居中项 = 44（根内边距）+ C
     *   ⟹ C = 256.3 − 27.3 − 37.0 − 44 = **148**。
     *
     * ⚠️ **别拿「内容墨迹高度」当它**：墨迹量到的是 192dp，那里面**含**了上下那
     * 44dp 内边距，而且不含行盒的行距。第一版按 192 写，s 算成 1.16、内容溢出，
     * 真机上「本月统计」那一行直接被切掉（真机出图才看见）。
     *
     * **改布局里的字号或间距就要重新量一次。**
     */
    private const val TODAY_CARD_DESIGN_H = 148f

    /**
     * 月历格的缩放系数。[slotDp] 是**行槽**的高度（含格子卡两侧各 2dp 的外边距）——
     * 与 App 那个 `cellH` 同一个口径。
     */
    private fun cardScale(slotDp: Float): Float =
        ((slotDp - 4f) / CARD_DESIGN_H).coerceIn(MIN_CARD_SCALE, MAX_CARD_SCALE)

    /**
     * 按内容可用高算的缩放系数（今日卡用）。[availDp] 是**去掉根内边距之后**能放内容
     * 的那一段，[designDp] 是「按基准字号自然排布时内容占多高」—— 那个数要**在真机上量**，
     * 与 App 的 `_cellDesignH = 55` 同一种做法。
     *
     * ⚠️ [maxScale] 默认 1.0 —— **今日卡只缩不放**。原因是量出来的：那三样补上之后
     * 内容自然高 148dp，而 4×3 的格子给它 212dp，`fitScale` 会一路顶到 1.25；但
     * **行距（16/14/8dp）与徽章盒（24dp）是写死的、不跟着缩放**，字一放大，农历那行
     * 就折成两行、整体高过可用高 —— 真机出图时「本月统计」那一行**被整行切掉**。
     *
     * 桌面外壳是定尺寸、**没有滚动**，溢出就是静默丢内容。所以宁可留着那点余量。
     * 想真正填满它得改卡片的尺寸（4×2），或再补内容 —— 两件都不在这一轮里。
     */
    private fun fitScale(availDp: Float, designDp: Float, maxScale: Float = 1f): Float =
        (availDp / designDp).coerceIn(MIN_CARD_SCALE, maxScale)

    /**
     * 把字号设成「基准 × 缩放」。
     *
     * ⚠️ **必须 `COMPLEX_UNIT_DIP`**：`COMPLEX_UNIT_SP` 会乘 `fontScale`，那正是这一轮
     * 要脱开的东西。`dp` 只乘 density。
     */
    private fun applyScale(v: RemoteViews, id: Int, baseDp: Float, s: Float) {
        v.setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_DIP, baseDp * s)
    }

    /** WCAG 相对亮度（sRGB 线性化）—— 与 App 的 `AppTokens.contrastRatio` 同一套算式。 */
    private fun relLuminance(color: Int): Double {
        fun lin(c: Int): Double {
            val s = c / 255.0
            return if (s <= 0.03928) s / 12.92 else Math.pow((s + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * lin((color shr 16) and 0xFF) +
            0.7152 * lin((color shr 8) and 0xFF) +
            0.0722 * lin(color and 0xFF)
    }

    /** WCAG 对比度。 */
    private fun contrastRatio(fg: Int, bg: Int): Double {
        val a = relLuminance(fg)
        val b = relLuminance(bg)
        return (maxOf(a, b) + 0.05) / (minOf(a, b) + 0.05)
    }

    /**
     * 实心块上的字色：**黑或白里对比更高的那一个**。
     *
     * ⚠️ **按对比度二选一，不是拿相对亮度卡一个阈值。** 这是与 App 的
     * `AppTokens.onSolid` 逐字同一条判据 —— 那条判据之所以能保证「恒 ≥ 4.58:1」，
     * 靠的正是「两个极值里取更大的那个」，与阈值无关。
     *
     * 第一版这里写成了 `亮度 > 0.55 ? 黑 : 白`，于是 **teal（`#00B3A6`，亮度 0.549）
     * 选了白字：实测 2.63:1** —— 而 `AGENTS.md` 记着「用户自己用的就是 teal」，
     * 这一格又正是本轮唯一「字压在用户自选的颜色上」的地方。判据错在这里是**静默**的：
     * 默认的蓝选出来是对的，只有换到 teal / 橙 / 粉那几档才现形。
     *
     * ⚠️ 两个候选必须是**纯白与纯黑**：那条 ≥ 4.58 的保证是按两个极值推的，
     * 换成近黑（第一版用的是 `#111818`）最坏一档会掉到约 4.1。
     */
    private fun onSolidInk(context: Context, color: Int): Int {
        val white = context.getColor(R.color.wg_on_solid_light)
        val black = context.getColor(R.color.wg_on_solid_dark)
        return if (contrastRatio(white, color) >= contrastRatio(black, color)) white else black
    }

    /**
     * 月历一格的**真实像素尺寸**，用来烤「今天」那块实心块。
     *
     * 为什么非要贴近真实尺寸：宿主是 `fitXY` 拉伸位图的，宽高比对不上时圆角会被
     * 拉成椭圆。格子的尺寸是 `GridLayout` 的 `rowWeight` 在布局期算出来的，渲染这侧
     * 拿不到 —— 所以按 `AppWidgetOptions` 给的实际 dp 反推（卡 padding 8dp×2、
     * 标题行 28dp、周几行约 20dp、格缝 2dp×2）。
     *
     * ⚠️ **行数必须按当月真实可见行数传进来**：5 行月每行约 77dp、6 行月约 65dp
     * （差约 18%），拿固定值去反推会让其中一档明显偏矮、四角露出白卡的角尖。
     */
    private fun monthCellPx(context: Context, widgetId: Int, rows: Int): Pair<Int, Int> {
        val opt = AppWidgetManager.getInstance(context).getAppWidgetOptions(widgetId)
        val wDp = opt.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
        val hDp = opt.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 320)
        val density = context.resources.displayMetrics.density
        val cellW = (((wDp - 16) / 7f) - 4f) * density
        val cellH = (((hDp - 16 - 28 - 20) / rows.toFloat()) - 4f) * density
        return cellW.toInt().coerceAtLeast(1) to cellH.toInt().coerceAtLeast(1)
    }

    /**
     * 网格里**真正会被布局的行数**：槽位按周一开头排 42 个，行数 = ceil(可见槽位 / 7)。
     *
     * 「可见」= 这一天在快照窗口里（`widget_month_card.xml` 顶部那两行注释讲了
     * `rowWeight` 是按可见行数均分的）。窗口到头那几格会被设成 GONE、不参与布局。
     */
    private fun monthGridRows(snap: WidgetStore.Snapshot, gridStart: LocalDate): Int {
        val epochs = HashSet<Long>(snap.days.size * 2)
        for (d in snap.days) epochs.add(d.day)
        var visible = 0
        for (slot in 0 until 42) {
            if (epochs.contains(gridStart.plusDays(slot.toLong()).toEpochDay())) visible++
        }
        return ((visible + 6) / 7).coerceAtLeast(1)
    }

    /**
     * 小组件点击用的 requestCode 基址。
     *
     * **必须远离项目里所有既有的 requestCode 区间。** 理由：这些 PendingIntent 的意图
     * 都是「无 action、无 data 的 `MainActivity`」，而 `PendingIntent` 的身份是
     * 「requestCode + 意图的 `filterEquals`」—— `filterEquals` **只比 action/data/
     * category/component，不比 extras，也不比 flags**。所以只要 requestCode 撞上，两个
     * 逻辑上毫不相干的点击就会共用同一个 PendingIntent，配 `FLAG_UPDATE_CURRENT`
     * 互相覆盖 extras。
     *
     * 既有区间（`AlarmScheduler` / `TodoReminderReceiver` 都用 `requestCode = 各自的 id`）：
     * 班次闹钟 0..600、自定义闹钟 10000..11000、待办行提醒 20000..39999、重复待办
     * 提醒 40000..41999，另有 `AlarmRingService` 的通知点击 0 / 1（同样带着
     * `alarm_label` 打向 `MainActivity`）与 `MainActivity.REQ_PICK_RINGTONE = 40071`。
     * 取 100000 起，全部避开。
     *
     * （`REQ_PICK_RINGTONE` 那个 40071 与重复待办的号段数值上挨着，但**不是同一个
     * 池**：它是 `getActivity` 的活动池，这里是 `getBroadcast` 的闹钟池，
     * `filterEquals` 连目标组件一起比。之所以写下来，是免得下一个人看到两个
     * 4 万多的号以为撞了。）
     *
     * `WidgetRefreshScheduler.REQ = 40081` **不在此列**：它是 `getBroadcast` 给
     * `WidgetRefreshReceiver` 且 `setAction` 过，目标组件与 `filterEquals` 都不同，
     * 本来就与这里不是同一个 PendingIntent。（`MainActivity.nativePendingIntent`
     * 同理，打向 `AlarmReceiver`。）
     *
     * 这条是 Task 7 的复审在 diff 之外发现的：初稿用 `widgetId * 16`，而 widget id 是
     * **设备级全局单调计数器**（新设备上第一个小组件拿到的就是 1 左右），于是
     * `Root(1) = 16` 正好落进班次闹钟的 id 区间里（那个区间从 0 起）。后果比「点错天」
     * 更糟 —— 小组件每次渲染都会把那枚 PendingIntent 上的 `alarm_label` /
     * `alarm_detail` 抹成空，闹钟通知点开的响铃界面因此失效。
     */
    private const val WIDGET_REQ_BASE = 100_000

    /**
     * 每个小组件实例占用的 requestCode 槽位数。
     *
     * 需要 `Root` + 42 个月历格 = 43，向上取到 64。
     *
     * ⚠️ **这个数不是随便取的，它是编址方案的护栏。** `Cell(w, n) = B + 64w + 1 + n`
     * （`n` 是 0 起的格子下标，实例共 `k` 格）。只要 **`k ≤ 63`**，格子偏移 `1 + n`
     * 就恒 `< 64` —— 要进位到 `B + 64(w+1)` 需要 `1 + n = 64`，即 `k ≥ 64`。于是
     * `Cell(w, n) − Root(w) = 1 + n` 恒落 `[1, 63]`、**恒不为 0**：`Cell` 既不会撞上
     * 本实例的 `Root`，也不会撞上**别的实例**的 `Root`（`Root(m) = B + 64m` 与 `B` 的差
     * 恒是 64 的倍数）。本仓最多用到 42 格（月历），远在护栏之内。
     *
     * ⚠️ **不要把这条推广成「`Cell` 永不为 64 的倍数」——那在绝对值上是错的**：
     * `B = 100_000 ≡ 32 (mod 64)`，于是 `Cell(w, 31) = 100_032 = 64 × 1563` 就是 64 的
     * 倍数。真正起作用的永远是上面那条**偏移**性质（`Cell − Root` 恒不为 0），
     * 不是「值本身不被 64 整除」。这个撞车类在本仓**真实发生过**（见 `launchIntent`
     * 的 KDoc）。基数从 32 提到 64 之后，`Int` 溢出的 widgetId 上限从约 6710 万降到
     * 约 3350 万，仍远够用。
     */
    private const val REQ_SLOTS_PER_WIDGET = 64

    /**
     * 翻月那两枚箭头的 requestCode 基数。**广播池**，与上面 `WIDGET_REQ_BASE`
     * （活动池，点格开 App 用 `getActivity`）**是两回事**。
     *
     * 900_000 离既有占用都够远：班次闹钟 0..600、自定义闹钟 10000..11000、待办提醒
     * 20000..39999、重复待办 40000..41999、选铃声 40071、刷新闹钟 40081。
     *
     * 编号 = `BASE + widgetId * 4 + dir`（dir：0 = 上月、1 = 下月、2 = 回今天，第 4 档
     * 留给将来）—— **每个实例、每个方向各一枚**：`Intent.filterEquals` 不比 extras，
     * 撞号会让两张卡共用一个箭头（点这张、那张翻页）。基数与展开形式由
     * `widget_fixed_cards_guard_test.dart` 扫源码钉住。
     */
    private const val WIDGET_MONTH_REQ_BASE = 900_000

    /** 整卡的 requestCode：低位 0 留给「不指定日期」。 */
    private fun rootRequestCode(widgetId: Int): Int = WIDGET_REQ_BASE + widgetId * REQ_SLOTS_PER_WIDGET

    /** 第 cell 格的 requestCode。低位 +1 起，避开 `rootRequestCode` 的 0。 */
    private fun cellRequestCode(widgetId: Int, cell: Int): Int =
        WIDGET_REQ_BASE + widgetId * REQ_SLOTS_PER_WIDGET + 1 + cell

    /**
     * 翻上 / 下月（`delta = ±1`）或回今天（`delta = 0`）：发给 [WidgetRefreshReceiver]
     * 的**广播**（与上面那个活动池无关，见 [WIDGET_MONTH_REQ_BASE]）。
     *
     * 越界不由这里拦：箭头那一侧没得翻时只是画成灰的，但**点击照样挂着** ——
     * `RemoteViews` 的 `reapply` 只重放新的动作串，**没有任何办法撤掉上一次设过的
     * 点击**。所以「能不能翻」由接收端判（同一个 [monthCovered]）。
     */
    private fun monthStepIntent(context: Context, widgetId: Int, delta: Int): PendingIntent {
        val dir = when {
            delta < 0 -> 0
            delta > 0 -> 1
            else -> 2      // 点标题 = 回今天
        }
        val i = Intent(context, WidgetRefreshReceiver::class.java)
            .setAction(WidgetRefreshReceiver.ACTION_MONTH_STEP)
            .putExtra(WidgetRefreshReceiver.EXTRA_WIDGET_ID, widgetId)
            .putExtra(WidgetRefreshReceiver.EXTRA_DELTA, delta)
        return PendingIntent.getBroadcast(
            context,
            WIDGET_MONTH_REQ_BASE + widgetId * 4 + dir,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * 打开 App 的 PendingIntent。
     *
     * 用 `getActivity` + 显式组件：隐式 LAUNCHER intent 在某些 ROM 上会被解析到
     * 「选择启动器」之类的东西上。
     *
     * ⚠️ requestCode 走上面那两个函数，**整卡与格子必须落在同一个仿射命名空间里**。
     * `PendingIntent` 的身份是「requestCode + 意图的 `filterEquals`」——而 `filterEquals`
     * **不比较 extras**，配上 `FLAG_UPDATE_CURRENT`（会覆盖 extras），两个 requestCode
     * 只要**数值相等**就会共用一个 PendingIntent、互相冲掉 `widget_day`，点一下跳到错
     * 的那天。
     *
     * **为什么步长必须与格子数错开**：（**历史注** —— 下面这个 16 格的网格是本轮删掉的
     * 旧版式，留着只是为了记下这个撞车类当初是怎么来的。）当时一个网格实例真正用到
     * `Cell(w, 0..15)`（16 格）。
     * 若步长仍是 16，末格 `Cell(m, 15) = B + 16m + 16 = B + 16(m+1)` —— **正好等于下一个
     * 实例的 `Root(m+1)`**，撞成同一个 PendingIntent；这个撞车类在本仓**真实发生过**
     * （初稿让整卡用**裸 `widgetId`**，单实例时 `16w + c ≠ w` 不自撞，所以在只有 id 34
     * 的桌面上测全过、藏得住；而 widget id **不是**「系统给的小整数」——它是设备级单调
     * 计数器，不复用，差 16 倍的两实例够得着）。当时的修法是把步长提到 32：格子偏移
     * `1 + n` ≤ 16、恒小于步长 32，`Cell(m, n) − Root(m) = 1 + n` **恒不为 0** ——
     * 于是对任意实例都不相等，单实例内也不自撞。这不是「取个大点的数保险」，
     * 而是「格子数必须与步长错开到不产生进位碰撞」的硬约束，见 `REQ_SLOTS_PER_WIDGET`。
     * **Task 7 的月历一格一码、要用满 42 格**：步长 32 已经不够 —— 第 32 格
     * `Cell(m, 31) = B + 32m + 32` 正好又是下一个实例的 `Root(m+1)`（42 > 32，直接撞车）。
     * 故基数一并提到 64：42 格 ≤ 63，格子偏移 `1 + n` ≤ 42、恒 `< 64`，`Cell − Root`
     * 因此仍恒不为 0。
     *
     * 现在 `Root(n) = WIDGET_REQ_BASE + 64n`、`Cell(m, c) = WIDGET_REQ_BASE + 64m + 1 + c`；
     * 基址再把它们整体抬离所有既有区间（见 `WIDGET_REQ_BASE`）。`widgetId` 涨到约
     * 3350 万才会 `Int` 溢出。
     */
    private fun launchIntent(context: Context, requestCode: Int, epochDay: Int? = null): PendingIntent {
        val i = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (epochDay != null) putExtra("widget_day", epochDay)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** 主题模式 → 此刻该用暗色吗。`system` 读宿主当前的配置，所以永远是新鲜的。 */
    fun isDark(context: Context, themeMode: String): Boolean = when (themeMode) {
        "light" -> false
        "dark" -> true
        else -> (context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    }

    /**
     * 三张卡的分派。**纯渲染**：不写盘、不排闹钟、不读除宿主配置之外的任何系统状态。
     *
     * 三张卡各自走自己的渲染函数：`weekStrip` / `todayStandalone` / `monthCard`。
     * 旧版式的五档渲染族（两行/五行列表、一周/两周网格、网格+今日卡片的装配壳）连同
     * 尺寸分档枚举已一并删净（Task 8 清账，见那次的提交信息）—— 尺寸在编译期定死
     * （`resizeMode="none"`），这里不再有分档分支。
     */
    fun render(
        context: Context,
        snap: WidgetStore.Snapshot?,
        variant: WidgetVariant,
        widgetId: Int,
    ): RemoteViews {
        if (snap == null) {
            return placeholder(context, dark = isDark(context, "system"), widgetId = widgetId)
        }
        val todayIndex = snap.indexOfToday()
        if (todayIndex < 0) {
            // 快照过期：App 两个多月没打开，这份 days 里已经没有今天了。
            AlarmLog.info(context, "WidgetRenderer: 快照已过期，走占位态")
            return placeholder(context, isDark(context, snap.themeMode), widgetId = widgetId)
        }
        if (!snap.hasSchedule) return empty(context, snap, widgetId)
        return when (variant) {
            WidgetVariant.WEEK_STRIP -> weekStrip(context, snap, todayIndex, widgetId)
            WidgetVariant.TODAY -> todayStandalone(context, snap, todayIndex, widgetId)
            WidgetVariant.MONTH -> monthCard(context, snap, widgetId)
        }
    }

    /**
     * 4×1 本周条：**今天所在的那一周**（周一~周日），与 App 日历的一行同构。
     *
     * 列的位置由**日期**定，不由 `todayIndex` 定：先算本周一，再逐列拿 epochDay 去
     * `days[]` 里找。窗口是绝对日期的（spec §7.1），所以本周一即使是上个月的最后几天
     * 也在窗口里 —— 这正是换窗口换来的能力。
     *
     * 「今天」那列：周几与日数字走**主色**。**不许加粗** —— `TextView` 没有
     * `setTypeface(int)` 重载，`setInt(id, "setTypeface", …)` 会在宿主进程抛 `ActionException`。
     *
     * 胶囊走**淡染配方**（14% 底 + 45% 描边）而不是实心：那是 App 日历格里班次胶囊的
     * 同一套长相（spec §4.1），文字因此走中性 ink —— 淡染底混合后≈卡片底，
     * `wg_ink_*` 必然过 AA，而 `onSolid` 那套黑/白字在淡染底上是错的。
     *
     * **没班次（`hasShift == false`）那一列整个不画胶囊**，与 App 日历格一致（`shift == null`
     * 时那块根本不画）。这里**不能**拿 `wg_empty_*` 去画「淡占位」：`WidgetChip.tintedChip`
     * 里 fill/stroke 的 alpha 是写死的（36 / 115），`Paint.setAlpha` 会**覆盖**颜色字节自带的
     * alpha —— `#14000000` 会变成一条 45% 的黑描边环，比 App 的长相响得多。正常排班里
     * 「休班」是一个**有颜色的班次定义**（`hasShift == true`），照常画胶囊 ——
     * 这条只影响空白表方案下的无班次日。
     */
    private fun weekStrip(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_week_strip)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_ws_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.setOnClickPendingIntent(R.id.wg_ws_root, launchIntent(context, rootRequestCode(widgetId)))

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted = context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)

        val todayEpoch = snap.days[todayIndex].day
        val today = LocalDate.ofEpochDay(todayEpoch)
        val monday = today.minusDays((today.dayOfWeek.value - 1).toLong())

        val columns = intArrayOf(
            R.id.wg_ws_col1, R.id.wg_ws_col2, R.id.wg_ws_col3, R.id.wg_ws_col4,
            R.id.wg_ws_col5, R.id.wg_ws_col6, R.id.wg_ws_col7,
        )
        // 「今天」那一列那块位图的尺寸（见 `stripCellPx` 的 KDoc）。一周只算一次。
        val (colW, colH) = stripCellPx(context, widgetId)

        for (col in columns.indices) {
            // **先清空再填** —— 这一句是「内容变了之后小组件重影」的修复，见本文件顶部
            // 那条 addView 的说明。放在循环开头而不是紧贴 addView：`continue` 逃掉的
            // 那一支（窗口里没有这天）同样要让容器里**一个子视图都不留**，否则旧格子
            // 会缩在 GONE 的槽位里，等这个槽位下次填上时又叠一层。
            v.removeAllViews(columns[col])
            val epoch = monday.plusDays(col.toLong()).toEpochDay()
            val i = snap.days.indexOfFirst { it.day == epoch }
            if (i < 0) {
                // 窗口里没有这天（理论上不会发生 —— 窗口恒含本周一与本周日）。
                // 不当成「没有班次」画：那会理直气壮地显示一张空卡。
                v.setViewVisibility(columns[col], android.view.View.GONE)
                continue
            }
            v.setViewVisibility(columns[col], android.view.View.VISIBLE)

            val d = snap.days[i]
            val isToday = epoch == todayEpoch

            // 点某一列 → 打开 App 并跳到那天。格子占槽位 1..7。
            v.setOnClickPendingIntent(
                columns[col],
                launchIntent(context, cellRequestCode(widgetId, col), epochDay = epoch.toInt()),
            )

            val c = RemoteViews(context.packageName, R.layout.widget_strip_cell)

            // ── 「今天」那一列铺一块**实心主色** ──
            // 与月历卡那张是同一件事（两张卡在桌面同一屏上，不能一个有一个没有）。
            // 主色是用户选的，静态 drawable 做不到，只能烤位图；一周只有一张。
            if (isToday) {
                c.setViewVisibility(R.id.wg_sc_block, android.view.View.VISIBLE)
                c.setImageViewBitmap(
                    R.id.wg_sc_block,
                    // 与月历那格**同一支、同参数**（2026-10-16 同步）：半透明玻璃块。
                    // 周条这一列底下没有独立白卡（七列都在同一张卡里），块直接压在
                    // 卡自己的近白底上 —— 与月历「白卡上压块」同一个观感。
                    WidgetChip.glassBlock(
                        snap.accent, colW, colH,
                        dpToPx(context, 12).toFloat(), dpToPx(context, 2).toFloat(),
                    ),
                )
            } else {
                c.setViewVisibility(R.id.wg_sc_block, android.view.View.GONE)
            }

            // 可见性无条件设满：宿主 reapply 时只重放新动作，漏设会保持上一次的状态。
            c.setViewVisibility(R.id.wg_sc_weekday, android.view.View.VISIBLE)
            c.setViewVisibility(R.id.wg_sc_day, android.view.View.VISIBLE)

            // 周标题：**单字**，与月历表头同一份（快照顶层 `weekdays`，按周一起算）。
            // 周条 7 列恰好是「本周一..本周日」，所以下标直接对得上。
            // ⚠️ 今日卡那边读的是 `days[].weekday`（完整「周几」），那是另一条路。
            c.setTextViewText(R.id.wg_sc_weekday, snap.weekdays.getOrNull(col) ?: d.weekday)
            // 字色一律走中性 —— 块是半透明的**浅底**，`onSolidInk` 在 teal / orange 上
            // 会给白字、读不出来（与月历 `monthCard` 同一条，2026-10-15 踩过）。
            c.setTextColor(R.id.wg_sc_weekday, muted)
            // 日数字：与 App 的格子一样只印「日」，整串「9月19日」在 46dp 宽的列里排不下。
            c.setTextViewText(R.id.wg_sc_day, LocalDate.ofEpochDay(epoch).dayOfMonth.toString())
            c.setTextColor(R.id.wg_sc_day, ink)

            // 没班次就不画胶囊 —— 与 App 日历格一致（`shift == null` 时那块不画）。
            // 不能拿 `wg_empty_*` 顶：`tintedChip` 的 `Paint.setAlpha` 会覆盖颜色字节自带的
            // alpha（fill 写死 36、stroke 写死 115），`#14000000` 会变成一条 45% 黑描边环。
            // **两个方向都要设满**：宿主 reapply 只重放新动作，漏设的一边会留着上一次的状态
            // （同一实例从有班次日切到无班次日时，胶囊会残留在那里）。
            if (d.hasShift) {
                c.setViewVisibility(R.id.wg_sc_pill, android.view.View.VISIBLE)
                c.setViewVisibility(R.id.wg_sc_abbr, android.view.View.VISIBLE)
                // 宽度按简称现量（与月历同一支）。**周条没有缩放** —— 字号就是布局里
                // 那个 10dp（v0.11.23 加 `cardScale` 的是月历，4×1 的周条从头到尾没接它）。
                // 今天那列也走淡染：以前转实心是因为淡染压在实心主色块上会糊，
                // 块改半透明浅底之后那条理由没了。
                c.setImageViewBitmap(
                    R.id.wg_sc_pill,
                    WidgetChip.tintedChip(
                        d.color,
                        chipWidthPx(context, d.shiftAbbr, 10f),
                        dpToPx(context, 18),
                    ),
                )
                c.setTextViewText(R.id.wg_sc_abbr, d.shiftAbbr)
                c.setTextColor(R.id.wg_sc_abbr, ink)
            } else {
                c.setViewVisibility(R.id.wg_sc_pill, android.view.View.GONE)
                c.setViewVisibility(R.id.wg_sc_abbr, android.view.View.GONE)
            }

            v.addView(columns[col], c)
        }
        return v
    }

    /**
     * 那个月能不能画：它的**42 格**（从该月 1 日所在周的周一起连续 42 天）全在快照
     * 覆盖的范围内。翻月的箭头灰不灰、接收端吞不吞这枚点击，用的都是它。
     *
     * 为什么问「42 格」而不是「这个月在 `snap.months` 里」：窗口是按整周对齐的，
     * 边上那两个月可能**只被蹭到几天** —— 那种月份列在 `months` 里，却画不出一张完整
     * 的月历（大半格子没数据）。判据必须与「画得出来」严格一致，否则箭头亮着、
     * 点下去是一张空卡。
     */
    internal fun monthCovered(snap: WidgetStore.Snapshot?, firstOfMonth: LocalDate): Boolean {
        if (snap == null || snap.days.isEmpty()) return false
        val start = firstOfMonth
            .minusDays((firstOfMonth.dayOfWeek.value - 1).toLong())
            .toEpochDay()
        return start >= snap.days.first().day && start + 41 <= snap.days.last().day
    }

    /**
     * 这个实例**现在显示的是哪个月**：锚点 ?? 今天那个月；**锚点那个月要是画不出来
     * 就当没设**（数据过期 / 被挤到窗口外）。
     *
     * ⚠️ **接收端算目标月也走这里**，不许自己去读 `WidgetStore.monthAnchor`：盘上那个
     * 锚点可能已经是一个渲染端不认的值，两边各判一次就会出现「箭头作用在你没看见的
     * 那个月」—— 点一下跳到莫名其妙的地方。
     */
    internal fun displayedMonth(
        context: Context,
        widgetId: Int,
        snap: WidgetStore.Snapshot?,
    ): LocalDate {
        val todayFirst = LocalDate.now().withDayOfMonth(1)
        val anchored = WidgetStore.monthAnchor(context, widgetId)
            ?.let { LocalDate.ofEpochDay(it).withDayOfMonth(1) }
        return if (anchored != null && monthCovered(snap, anchored)) anchored else todayFirst
    }

    /**
     * 4×5 整月：月份标题 + 周几行 + 6×7 格。
     *
     * **渲染哪个月**由 [displayedMonth] 定（锚点 ?? 今天，锚点画不出来就当没设）——
     * 不由快照的生成月定，也不需要 App 活着：数据早就在窗口里。
     *
     * **42 格是连续 42 天**（v0.9.17 起）：起点是「该月 1 日所在周的周一」，于是月头
     * 月尾那几格画的是**相邻月份**的日子（日数字走 muted、胶囊照画）——整张卡读起来
     * 是一段连续的日子。窗口外的格仍然 GONE：**「相邻月」与「没数据」是两回事**。
     *
     * 月份标题从 `snap.months` 里按「年-月」查；**查不到就隐藏标题行**，
     * 绝不借相邻月份的标题顶上。
     *
     * 42 格共用 `widget_month_cell` 一张布局、每格一个 `RemoteViews` 实例；胶囊是
     * **定尺 40×18dp** 的 `tintedChip` 位图，靠 `WidgetChip` 的 LruCache 按 (颜色, 尺寸)
     * 复用 —— 同尺寸 + 同色共一张，42 格实际只画得出屈指可数的几张。**别在这条路上
     * 按格子改尺寸或按格子造唯一颜色**，那会把这套复用打掉（Task 1 的探针结论）。
     *
     * 没班次（空白表方案）那格不画胶囊，与 App 日历格一致（`shift == null` 时那块
     * 根本不画）—— 完整理由见 [weekStrip] 里那条「不能拿 `wg_empty_*` 顶上」。
     *
     * 不收 `todayIndex`：本卡渲染哪个月由锚点决定、42 格又是连续的日子，「今天」只能
     * 按日期现算（`epoch == todayEpoch`），快照里那份下标在这里用不上。
     */
    private fun monthCard(
        context: Context,
        snap: WidgetStore.Snapshot,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_month_card)
        val dark = isDark(context, snap.themeMode)
        // 面板底**扮 App 的「日历页」**（浅灰 / 深底），42 张白格垫在它上面 ——
        // App 里就是这层关系（白卡垫在 `bgLight #F5F6FA` 上），桌面上没有「页面」
        // 这一层，得让面板去扮，白卡才显出来。见 `widget_page_*.xml`。
        v.setInt(
            R.id.wg_m_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_page_dark else R.drawable.widget_page_light,
        )
        v.setOnClickPendingIntent(R.id.wg_m_root, launchIntent(context, rootRequestCode(widgetId)))

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted = context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)
        val holiday = context.getColor(R.color.wg_holiday)

        val today = LocalDate.now()
        val todayEpoch = today.toEpochDay()
        // 显示哪个月见 `displayedMonth` 的注释（锚点在盘上、但画不出来时按没设处理）。
        val firstOfMonth = displayedMonth(context, widgetId, snap)

        // ── 标题行：‹ 月份 › ──
        val title = snap.months.firstOrNull {
            it.y == firstOfMonth.year && it.m == firstOfMonth.monthValue
        }
        if (title == null) {
            // 查不到就隐藏（绝不借相邻月份的标题顶上）—— 既有纪律，不改。
            v.setViewVisibility(R.id.wg_m_title, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_m_title, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_m_title, title.title)
            v.setTextColor(R.id.wg_m_title, muted)
        }
        // **箭头永远设点击**，哪怕那一侧没得翻：`RemoteViews` 的 `reapply` 只重放
        // **新的**动作串，**没有任何办法撤掉上一次设过的点击**（与 v0.9.9 那条
        // `removeAllViews` 同源：宿主会复用已在的那棵视图树）。所以「到头了」由
        // **接收端**判 —— 颜色只作提示：能翻 = ink，翻不动 = muted（与标题同档）。
        v.setTextColor(
            R.id.wg_m_prev,
            if (monthCovered(snap, firstOfMonth.minusMonths(1))) ink else muted,
        )
        v.setTextColor(
            R.id.wg_m_next,
            if (monthCovered(snap, firstOfMonth.plusMonths(1))) ink else muted,
        )
        v.setOnClickPendingIntent(R.id.wg_m_prev, monthStepIntent(context, widgetId, -1))
        v.setOnClickPendingIntent(R.id.wg_m_next, monthStepIntent(context, widgetId, 1))
        // 点中间的月份文字 = 回今天（已经是今天那个月时是 no-op）。
        v.setOnClickPendingIntent(R.id.wg_m_title, monthStepIntent(context, widgetId, 0))

        // ── 周几行（7 条文案来自快照，原生不做 i18n） ──
        val wdIds = intArrayOf(
            R.id.wg_m_wd1, R.id.wg_m_wd2, R.id.wg_m_wd3, R.id.wg_m_wd4,
            R.id.wg_m_wd5, R.id.wg_m_wd6, R.id.wg_m_wd7,
        )
        for (i in wdIds.indices) {
            val text = snap.weekdays.getOrNull(i)
            if (text == null) {
                // 快照只有 7 条文案时不会走到这里；真缺了就隐藏，不拿别的顶上。
                v.setViewVisibility(wdIds[i], android.view.View.GONE)
            } else {
                v.setViewVisibility(wdIds[i], android.view.View.VISIBLE)
                v.setTextViewText(wdIds[i], text)
                v.setTextColor(wdIds[i], muted)
            }
        }

        // ── 42 格：从「该月 1 日所在周的周一」起**连续** 42 天 ──
        //
        // 月头月尾那几格因此画的是**相邻月份**的日子，整张卡读起来是一段连续的日子。
        // 窗口外的格仍然 GONE —— 「相邻月」（有数据、照画）与「没数据」（挖空）是两回事。
        val leading = firstOfMonth.dayOfWeek.value - 1   // 周一 = 1 → 前导天数
        val gridStart = firstOfMonth.minusDays(leading.toLong())
        val slotIds = IntArray(42) { i ->
            context.resources.getIdentifier("wg_m_slot${i + 1}", "id", context.packageName)
        }
        // 「今天」那块块的位图尺寸要按**当月真实可见行数**反推（5 行月与 6 行月的
        // 格子高差约 18%）。整月只算一次 —— 它里面那次 `getAppWidgetOptions` 是
        // 一次 binder IPC，放进 42 格的循环里就是每次渲染 42 次。
        val cellRows = monthGridRows(snap, gridStart)
        val (cellW, cellH) = monthCellPx(context, widgetId, cellRows)

        // 字号按格子尺寸缩放（见 `cardScale`）。`monthCellPx` 给的是**格子卡**的高
        // （行槽减去上下各 2dp 的外边距），加回那 4dp 才是 App 那个 `cellH` 的口径。
        // 42 格共用同一个 s —— 尺寸在循环外算一次，别按格子算（那会把位图缓存冲爆）。
        val cellDensity = context.resources.displayMetrics.density
        val cellScale = cardScale(cellH / cellDensity + 4f)

        // 胶囊位图的**高度**：基准 18dp × 缩放，42 格共用一个。
        // **宽度不在这里算** —— 它按各格的简称现量（`chipWidthPx`），见下面那段。
        val pillH = (18f * cellScale * cellDensity).toInt().coerceAtLeast(1)
        // 简称的字号（= `design_tokens.cellShift` 的基准 12 × 缩放），量宽时要用它。
        val chipTextDp = 12f * cellScale

        for (slot in 0 until 42) {
            // 先清空再填，理由与 `weekStrip` 那处逐字相同（含放在循环开头而非 addView
            // 前面的取舍）。42 格每格都要清 —— 窗外那几格也走这里。
            v.removeAllViews(slotIds[slot])
            val date = gridStart.plusDays(slot.toLong())
            val epoch = date.toEpochDay()
            val i = snap.days.indexOfFirst { it.day == epoch }
            if (i < 0) {
                // 快照没盖到这一天（窗口到头了 / 快照过期）。挖空 —— 画一张理直气壮的
                // 错日子比空着更糟。
                v.setViewVisibility(slotIds[slot], android.view.View.GONE)
                continue
            }
            v.setViewVisibility(slotIds[slot], android.view.View.VISIBLE)

            // 点某一格 → 打开 App 并跳到那天。相邻月的格同样如此（点 8 月 31 日就跳
            // 8 月 31 日，语义自洽）。格子占槽位 1..42（一个实例 64 个槽位）。
            v.setOnClickPendingIntent(
                slotIds[slot],
                launchIntent(context, cellRequestCode(widgetId, slot), epochDay = epoch.toInt()),
            )

            val d = snap.days[i]
            val inMonth = date.year == firstOfMonth.year &&
                date.monthValue == firstOfMonth.monthValue
            val isToday = epoch == todayEpoch
            val c = RemoteViews(context.packageName, R.layout.widget_month_cell)

            // ── 格子卡底（贴齐 App：白卡垫在「页面」上）──
            // 用**静态 `<shape>`**：圆角随控件尺寸走，天然不会被 `fitXY` 拉成椭圆。
            //
            // 2026-10-15：**今天那一格不再置 0 了**。原先置 0 是因为块是实心位图、
            // 卡底是静态 drawable，两者圆角在宽高比不一致时会错开、四角露出白卡的尖。
            // 现在块改回**半透明**（见下面那段），它本来就该压在白卡上 —— 与 App 里
            // 「页面底 → 白卡 → 主色块」三层同构。
            c.setInt(
                R.id.wg_mc_root,
                "setBackgroundResource",
                if (dark) R.drawable.widget_cell_dark else R.drawable.widget_cell_light,
            )

            // ── 「今天」那块**半透明玻璃块**（2026-10-15 从实心改回来）──
            // 用户原话：「问题就出在这格子的外观跟 App 里的差别太多了，尤其是那个
            // 半透明块，如果你能实现的话，那基本上就很好了」。
            //
            // 当初（v0.11.9）做诚实的理由已经不成立了：那条写的是「半透明块压在任意
            // 壁纸上会消失」，而**同一轮**已经把月历的面板底换成了不透明的页面色、
            // 格子换回了白卡 —— 块压在白卡上，跟 App 里是同一个结构。App 那枚块自己
            // 也**不带模糊**（模糊在页面背景那一层）。详见规格 §5。
            //
            // 尺寸在循环外算好了（`cellW` / `cellH`），这里只贴。
            if (isToday) {
                c.setViewVisibility(R.id.wg_mc_block, android.view.View.VISIBLE)
                c.setImageViewBitmap(
                    R.id.wg_mc_block,
                    WidgetChip.glassBlock(
                        snap.accent,
                        cellW,
                        cellH,
                        dpToPx(context, 12).toFloat(),
                        dpToPx(context, 2).toFloat(),
                    ),
                )
            } else {
                c.setViewVisibility(R.id.wg_mc_block, android.view.View.GONE)
            }

            // 可见性两个方向都要设满：宿主 `reapply` 只重放新动作，漏设的一边会留着
            // 上一次的状态。
            c.setViewVisibility(R.id.wg_mc_day, android.view.View.VISIBLE)
            c.setTextViewText(R.id.wg_mc_day, date.dayOfMonth.toString())
            // 三个字号一起按格子缩放。基准数与 `widget_month_cell.xml` 里的初值、
            // 以及 `design_tokens.dart` 的三个令牌**三处同源**：
            //   日数字 = cellDateSm 13 / 胶囊字 = cellShift 12 / 农历 = tinyLabel 11
            applyScale(c, R.id.wg_mc_day, 13f, cellScale)
            applyScale(c, R.id.wg_mc_abbr, 12f, cellScale)
            applyScale(c, R.id.wg_mc_lunar, 11f, cellScale)
            // 三种字色：今天**不再**走 `onSolidInk` —— 半透明块是**浅底**，
            // 而 `onSolidInk` 对 teal / orange 会给白字，白压浅底读不出来
            // （静默：默认那颗蓝是对的，只有换到浅主色才现形）。
            // 字重仍然只能靠布局里的 `textStyle`：`TextView` 没有 `setTypeface(int)`，
            // 反射会在宿主进程抛 `ActionException`。
            c.setTextColor(R.id.wg_mc_day, if (inMonth) ink else muted)

            // 没班次就不画胶囊 —— 与 App 日历格一致（`shift == null` 时那块根本不画）。
            // **相邻月的格照样画**（用户 2026-09-30 选的「日数变灰、胶囊照画」）。
            // **不能**拿 `wg_empty_*` 顶上：`tintedChip` 里 `Paint.setAlpha` 会**覆盖**颜色
            // 字节自带的 alpha（fill 写死 36、stroke 写死 115），`#14000000` 会变成一条 45%
            // 的黑描边环，比 App 的长相响得多。正常排班里「休班」是一个**有颜色的班次定义**
            // （`hasShift == true`），照常画胶囊 —— 这条只影响空白表方案下的无班次日。
            if (d.hasShift) {
                c.setViewVisibility(R.id.wg_mc_pill, android.view.View.VISIBLE)
                c.setViewVisibility(R.id.wg_mc_abbr, android.view.View.VISIBLE)
                // **高度**恒定（循环外算好的 pillH）；**宽度按这一格的简称现量** ——
                // 与 App 的 `_shiftChip` 同一条（「白」窄、「大休」宽）。
                // LruCache 不会炸：宽度只由 (字号 × 文字宽) 决定，同宽的简称自然共用
                // 同一张位图，一屏仍是屈指可数的几张。**别按格子造唯一尺寸**（那才会冲爆）。
                // **今天那格也走淡染**：以前它转实心是因为淡染压在实心主色块上会糊成
                // 一片 —— 块改成半透明浅底之后那条理由没了，与 App 的普通格一致。
                c.setImageViewBitmap(
                    R.id.wg_mc_pill,
                    WidgetChip.tintedChip(
                        d.color, chipWidthPx(context, d.shiftAbbr, chipTextDp), pillH,
                    ),
                )
                c.setTextViewText(R.id.wg_mc_abbr, d.shiftAbbr)
                // 字色走中性 `ink`（淡染底 + 近不透明的卡底，两者都够对比度）
                c.setTextColor(R.id.wg_mc_abbr, ink)
            } else {
                c.setViewVisibility(R.id.wg_mc_pill, android.view.View.GONE)
                c.setViewVisibility(R.id.wg_mc_abbr, android.view.View.GONE)
            }

            c.setViewVisibility(R.id.wg_mc_lunar, android.view.View.VISIBLE)
            c.setTextViewText(R.id.wg_mc_lunar, d.lunarShort)
            // ⚠️ **今天那格走块上字，不走 `holiday` 的红字** —— 红字压在实心主色块上
            // 读不出来。代价是**这一天看不出「是节假日」**（一个月至多一次），
            // 可读性优先。这一条在规格的「Review Focus」里点了名。
            // 农历的字色：**今天那格不再吃掉节假日红字**。
            // 原先 `isToday -> onSolidInk(...)` 是为了压在实心块上读得出来，代价是
            // 「这一天看不出是节假日」。块改回半透明（浅底）之后那条理由没有了，
            // 红字自然回来。
            c.setTextColor(
                R.id.wg_mc_lunar,
                if (d.lunarIsHoliday) holiday else muted,
            )

            v.addView(slotIds[slot], c)
        }
        return v
    }

    /**
     * 本周条一列的真实像素尺寸（同 `monthCellPx` 的理由：位图被 `fitXY` 拉伸，
     * 宽高比对不上时圆角会被拉成椭圆）。周条**没有标题行与周几行** ——
     * 只有卡 padding 与块自己的外边距，所以比月历那格矮得多。
     *
     * ⚠️ **那两个减数是「布局里让掉了多少」，三个地方是一组，改一个要改三个**
     * （2026-10-16 用户真机反馈那轮改过一次，由 `widget_cell_block_guard_test.dart`
     * 逐个数对账）：
     *   · 宽：`- 16` 是 `widget_week_strip.xml` 的横向内边距 8dp × 2，
     *         `- 4` 是 `widget_strip_cell.xml` 里块自己的 2dp × 2。
     *   · 高：`- 6` 是那边的**纵向**内边距 3dp × 2 + 块纵向外边距 0。
     *
     * 纵向那两个数为什么与横向不同：块在纵向要长到「周几离上沿、下夜胶囊离下沿」
     * 与横向那 6.7dp 同一个量级 —— 原来横向 8dp + 块 2dp 时，块离卡上下沿 8.7dp，
     * 可块**里面**只剩 3.7dp / 5.3dp。真机量出来的数写在两份布局的头注里。
     */
    private fun stripCellPx(context: Context, widgetId: Int): Pair<Int, Int> {
        val opt = AppWidgetManager.getInstance(context).getAppWidgetOptions(widgetId)
        val wDp = opt.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
        val hDp = opt.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 40)
        val density = context.resources.displayMetrics.density
        val cellW = (((wDp - 16) / 7f) - 4f) * density
        val cellH = (hDp - 6) * density
        return cellW.toInt().coerceAtLeast(1) to cellH.toInt().coerceAtLeast(1)
    }

    /**
     * 今日卡片。照搬 App 底栏信息卡的**完整版**（`calendar_screen.dart` 的 `_infoCard`，
     * 不是 `compact` 版），元素与配方逐项对照 spec §7。
     *
     * ⚠️ **跨天降级**：`todayCard` 里的农历、待办数、其他班组都是**生成那天**的，
     * 而跨天刷新时原生只能对表右移、重算不了。所以先拿 `todayCard.day` 跟今天比：
     * 对不上就把这三样留空，只显示 `days[todayIndex]` 里那份按日期烘焙的数据
     * （日期、班次、时间）。**绝不把旧数据当成今天显示。**
     *
     * 命名是 `renderTodayCard` 而不是 `todayCard`：快照里有个属性也叫 `snap.todayCard`，
     * 同一屏里 `val tc = snap.todayCard` 挨着 `todayCard(...)` 读起来太绕（控制方裁定）。
     *
     * ⚠️ 本函数渲染的内容**永远在外壳内**（唯一的调用方是 `todayStandalone` 的槽位），
     * 所以自己**不画**卡片底 —— 画了就是双层边：外壳根与卡片根铺同一张带 `1dp`
     * stroke / 22dp 圆角的 drawable，成品上会多出一圈圆角描边、悬在外壳边框内侧。
     * 卡片底只画一层，在外壳上。
     */
    private fun renderTodayCard(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_today_card)
        val dark = isDark(context, snap.themeMode)
        v.setOnClickPendingIntent(
            R.id.wg_tc_root,
            launchIntent(context, rootRequestCode(widgetId)),
        )

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted =
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)

        // 字号按**卡内可用高**缩放（今日卡没有「格子」，用的是整张卡能放内容的那一段）。
        // 可用高 = 宿主给的卡高 − 布局根那 22dp 内边距 × 2。
        // ⚠️ **徽章那三个文字不参与缩放**（今天 / N 项待办 / 已调班）：它们的盒子是
        // 写死的 52/84/96dp，而改容器尺寸的 `setViewLayoutWidth` 要 API 31（本仓
        // minSdk 26）—— 字放大了盒子不动就会挤。见规格 §8。
        val cardH = AppWidgetManager.getInstance(context)
            .getAppWidgetOptions(widgetId)
            .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 180)
        val s = fitScale(cardH - 44f, TODAY_CARD_DESIGN_H)

        // 日期/班次/时间/色点一律取 `days[todayIndex]` 而**不是** `todayCard` ——
        // `days[]` 会被原生对表右移、永远是对的；`todayCard` 不会。
        val d = snap.days[todayIndex]
        val tc = snap.todayCard
        val stale = tc == null || tc.day != LocalDate.now().toEpochDay()

        // ── 0. 左边那条通高的主色竖条 ──
        // 与 App 的信息卡对齐（`Positioned(left: 0, top/bottom: spaceLg, width: 6)`）：
        // **6dp 宽、通到内容底、圆头**。颜色跟当天班次色走、没班次退回主色（与 App
        // `accent = shift != null ? shift.color : primary` 同一条）。
        //
        // ⚠️ 位图高给 **200dp 这个「够长的常量」**，由 `fitXY` 拉到真实内容高
        // （约 168~192dp）：`bar()` 的圆头半径是 `w/2 = 3dp`，200 → 168~192 这一步
        // 缩放让两端半圆半径浮动在 2.5~3.4dp，肉眼看不出。**别去精算内容高** ——
        // 它随农历折行与「本月统计」有无而变化。
        // ⚠️ 布局那一侧必须能让它拉到内容高：根是**横向 LinearLayout**（`match_parent`
        // 高的子层会被二次测量成邻列高）；换成 FrameLayout 就会解析成固定 200dp。
        v.setImageViewBitmap(
            R.id.wg_tc_bar,
            WidgetChip.bar(
                if (d.hasShift) d.color else snap.accent,
                dpToPx(context, 6),
                dpToPx(context, 200),
            ),
        )
        v.setTextViewText(R.id.wg_tc_date, d.dateShort)
        v.setTextColor(R.id.wg_tc_date, ink)

        // 「今天」徽章。宽度写死在布局里 —— RemoteViews 量不到文字宽度。
        // 高同样要与布局的 `wg_tc_today_wrap`（24dp）一致：`block` 的 radius 也按
        // **位图**高算，拉了 fitXY 会让两端的半圆变椭圆、上下描边偏重。
        // **实心主色 + 块上字**（贴齐 App 那枚药丸：App 里它就是实心主色 + 白字；
        // 桌面上原来是 14% 淡染，读起来是被冲淡的）。
        v.setImageViewBitmap(
            R.id.wg_tc_today_bg,
            WidgetChip.block(
                snap.accent,
                dpToPx(context, 52),
                dpToPx(context, 24),
                dpToPx(context, 12).toFloat(),
            ),
        )
        v.setTextViewText(R.id.wg_tc_today_text, snap.today)
        v.setTextColor(R.id.wg_tc_today_text, onSolidInk(context, snap.accent))

        // 「N 项待办」徽章。`todoBadge` 为空（没有待办）或快照跨天 → 整块隐藏。
        val todoText = if (stale) null else tc.todoBadge
        if (todoText == null) {
            v.setViewVisibility(R.id.wg_tc_todo_wrap, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_todo_wrap, android.view.View.VISIBLE)
            v.setImageViewBitmap(
                R.id.wg_tc_todo_bg,
                WidgetChip.tintedChip(snap.accent, dpToPx(context, 84), dpToPx(context, 24)),
            )
            v.setTextViewText(R.id.wg_tc_todo_text, todoText)
            v.setTextColor(R.id.wg_tc_todo_text, snap.accent)
        }

        // ── 2. 农历：跨天就隐藏（它是生成那天的） ──
        // 4×3 比原来的紧凑档高出约 95dp，多出来的地方要放**真内容**：
        // 换用 `LunarInfo.fullDescription`（App 完整版信息卡用的就是它），
        // 因此布局里那行是 maxLines="2"。
        if (stale) {
            v.setViewVisibility(R.id.wg_tc_lunar, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_lunar, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_tc_lunar, tc.lunarFull)
            v.setTextColor(
                R.id.wg_tc_lunar,
                if (tc.lunarIsHoliday) {
                    context.getColor(R.color.wg_holiday)
                } else {
                    muted
                },
            )
        }

        // ── 3. 班次行 ──
        v.setImageViewBitmap(
            R.id.wg_tc_dot,
            WidgetChip.circle(
                if (d.hasShift) {
                    d.color
                } else {
                    context.getColor(if (dark) R.color.wg_empty_dark else R.color.wg_empty_light)
                },
                dpToPx(context, 12),
            ),
        )
        v.setTextViewText(R.id.wg_tc_shift, if (d.hasShift) d.shiftName else d.weekday)
        v.setTextColor(R.id.wg_tc_shift, ink)

        // ── 3b. 班次备注（「休息日 · 不响闹钟」/「闹钟 07:00」） ──
        // 位置与 App 的信息卡一致：**班次名之后、已调班徽章之前**。
        // ⚠️ 取值走 `d.shiftNote`（按日烘焙）而不是 `tc.*` —— 跨天之后 `tc` 整块
        // 过期，而这一行不该跟着消失（它描述的是**今天那个班次**，`d` 永远是对的）。
        if (d.shiftNote.isNullOrEmpty()) {
            v.setViewVisibility(R.id.wg_tc_note, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_note, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_tc_note, d.shiftNote)
            v.setTextColor(R.id.wg_tc_note, muted)
        }

        // 「已调班」徽章：底色跟当天班次色走（与 App 信息卡的 `_adjustedBadge` 同源）。
        // 与色条/色点一致地**回落**：休班日 `d.color` 是 Dart 侧的 `shift?.color ?? 0`
        // = 0（全透明），直接用会得到一个占 96dp 却什么也看不见的徽章。
        if (stale || !tc.adjusted) {
            v.setViewVisibility(R.id.wg_tc_adj_wrap, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_adj_wrap, android.view.View.VISIBLE)
            v.setImageViewBitmap(
                R.id.wg_tc_adj_bg,
                WidgetChip.tintedChip(
                    if (d.hasShift) d.color else snap.accent,
                    dpToPx(context, 96),
                    dpToPx(context, 24),
                ),
            )
            v.setTextViewText(R.id.wg_tc_adj_text, snap.adjustedBadge)
            v.setTextColor(R.id.wg_tc_adj_text, if (d.hasShift) d.color else snap.accent)
        }

        // ── 4. 时间 ──
        if (d.timeRange == null) {
            v.setViewVisibility(R.id.wg_tc_time, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_time, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_tc_time, d.timeRange)
            v.setTextColor(R.id.wg_tc_time, muted)
        }

        // ── 5. 其他班组：跨天就整行隐藏（那是生成那天的） ──
        val crews = if (stale) emptyList() else tc.crews.take(4)
        val crewSlots = intArrayOf(
            R.id.wg_tc_crew_slot1, R.id.wg_tc_crew_slot2,
            R.id.wg_tc_crew_slot3, R.id.wg_tc_crew_slot4,
        )
        if (crews.isEmpty()) {
            v.setViewVisibility(R.id.wg_tc_crew_row, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_crew_row, android.view.View.VISIBLE)
            // 行首那个「其他班组」标签。它是一行里的**零号槽位**，所以只设一次，
            // 不参与下面按槽位循环（循环只清 4 个 crew_slot）。
            v.setTextViewText(R.id.wg_tc_crew_label, snap.otherCrews)
            v.setTextColor(R.id.wg_tc_crew_label, muted)
            for (slot in crewSlots.indices) {
                // 先清空再填，理由与 `weekStrip` 那处逐字相同。
                v.removeAllViews(crewSlots[slot])
                if (slot >= crews.size) {
                    v.setViewVisibility(crewSlots[slot], android.view.View.GONE)
                    continue
                }
                v.setViewVisibility(crewSlots[slot], android.view.View.VISIBLE)
                val crew = crews[slot]
                val chip = RemoteViews(context.packageName, R.layout.widget_crew_chip)
                chip.setImageViewBitmap(
                    R.id.wg_cc_bg,
                    WidgetChip.tintedChip(crew.color, dpToPx(context, 14), dpToPx(context, 14)),
                )
                chip.setImageViewBitmap(
                    R.id.wg_cc_dot,
                    WidgetChip.circle(crew.color, dpToPx(context, 8)),
                )
                chip.setTextViewText(R.id.wg_cc_text, "${crew.name} ${crew.abbr}")
                // 文字色固定走 muted：胶囊底是 14% 淡染、卡片底近不透明，两者都够对比度。
                // 这里**有意偏离** App 的 `AppTokens.inkFor` —— 那套「按底色算可读色」要
                // luminance 计算，为一行 11sp 的小字在原生复刻一份不值当，而快照里也没有
                // 现成的对比色可拿。
                chip.setTextColor(R.id.wg_cc_text, muted)
                v.addView(crewSlots[slot], chip)
            }
        }

        // ── 6. 本月统计 ──
        // 「本月 大休13 · 白7 · 上夜6 · 下夜5」（App 的信息卡 v0.9.7 就有）。
        //
        // 取值链路：当天那条 `days[todayIndex]` 的 `day`（epochDay）→ 年月 → 在
        // `months[]` 里查那个月的 `tally`。**这样跨天与翻月都自动是对的** ——
        // `d` 永远指向"今天"，而 `months[]` 是按月存的（不是逐日烘）。
        // 查不到（窗口外、或没有排班）就 GONE：不画一句空话，也不留一行空白。
        val tally = run {
            val todayDate = LocalDate.ofEpochDay(d.day)
            snap.months
                .firstOrNull { it.y == todayDate.year && it.m == todayDate.monthValue }
                ?.tally
        }
        if (tally.isNullOrEmpty()) {
            v.setViewVisibility(R.id.wg_tc_tally, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_tally, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_tc_tally, tally)
            v.setTextColor(R.id.wg_tc_tally, muted)
        }

        // ── 字号：一律按卡内可用高缩放（`s` 在函数开头算好了） ──
        // 数值与 `widget_today_card.xml` 里的 dp 初值一一对应。
        // **徽章那三个不在里面**（见开头那段说明）。
        // 「其他班组」那两处（这里与 `widget_crew_chip.xml`）的 12 = App 的
        // `AppTokens.microText` / `microLabel` —— 原来是 11，比 App 与这张卡自己的
        // 「本月统计」都小一档（2026-10-16 用户真机反馈），由
        // `widget_today_card_guard_test.dart` 对着 Dart 令牌盯住两边不跑偏。
        applyScale(v, R.id.wg_tc_date, 22f, s)
        applyScale(v, R.id.wg_tc_lunar, 14f, s)
        applyScale(v, R.id.wg_tc_shift, 18f, s)
        applyScale(v, R.id.wg_tc_note, 13f, s)
        applyScale(v, R.id.wg_tc_time, 13f, s)
        applyScale(v, R.id.wg_tc_crew_label, 12f, s)
        applyScale(v, R.id.wg_tc_tally, 12f, s)

        return v
    }

    /**
     * 4×3 今日卡：外壳（画卡底）+ 嵌套 [renderTodayCard]。
     *
     * 与旧版最大的差别是**不再套在网格下面** —— 它是独立的一张卡，
     * 尺寸固定，所以内容按 4×3 排版（大一号的字、`lunarFull` 两行）。
     */
    private fun todayStandalone(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_today_standalone)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_ts_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        // 整卡点击设**外壳根**上：外壳铺满整个小组件，而内层卡片是 wrap_content 高、
        // 被 `gravity="center_vertical"` 居中 —— 卡底画到了上下那两截留白上，只在卡片上设
        // 点击就有一圈「看得见但不响应」的死区（4×3 下各约 34dp）。这条与
        // `weekStrip` / `monthCard` / `empty` / `placeholder` 一致，见那几处的 KDoc。
        v.setOnClickPendingIntent(R.id.wg_ts_root, launchIntent(context, rootRequestCode(widgetId)))
        // 先清空再填 —— 这一处塞进去的是**整棵今日卡子树**，叠起来比一格重影严重得多：
        // 槽位是个竖向 LinearLayout，多余的副本会往下排、把卡片撑出外壳后被裁掉。
        // 完整的机制说明见 `weekStrip` 那处。
        v.removeAllViews(R.id.wg_ts_slot)
        v.addView(R.id.wg_ts_slot, renderTodayCard(context, snap, todayIndex, widgetId))
        return v
    }

    /**
     * 空表态：没有排班（`snap.hasSchedule == false`）。
     *
     * 三张卡共用一张布局（`widget_empty`）—— 空表本来也没什么可说的，三档各写一张
     * 只会长成三个样。它原先挂在紧凑列表的壳上，那张壳随旧版式一起删了。
     *
     * 文案来自快照的 `emptyHint`（Dart 侧 `L10n.widgetEmptyHint` 产出）——
     * Kotlin 侧仍然一个字面量都没有。
     */
    private fun empty(context: Context, snap: WidgetStore.Snapshot, widgetId: Int): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_empty)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_e_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.setOnClickPendingIntent(R.id.wg_e_root, launchIntent(context, rootRequestCode(widgetId)))
        v.setTextViewText(R.id.wg_e_hint, snap.emptyHint)
        v.setTextColor(
            R.id.wg_e_hint,
            context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light),
        )
        return v
    }

    private fun placeholder(context: Context, dark: Boolean, widgetId: Int): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_placeholder)
        v.setInt(
            R.id.wg_ph_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        // 占位态也要能点开 App —— 它多半是「还没有快照」，点进去最该做的是打开
        // App 让它推一份下来。
        v.setOnClickPendingIntent(R.id.wg_ph_root, launchIntent(context, rootRequestCode(widgetId)))
        v.setImageViewResource(R.id.wg_ph_icon, R.mipmap.ic_launcher)
        v.setTextViewText(
            R.id.wg_ph_label,
            context.applicationInfo.loadLabel(context.packageManager).toString(),
        )
        v.setTextColor(
            R.id.wg_ph_label,
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light),
        )
        return v
    }
}
