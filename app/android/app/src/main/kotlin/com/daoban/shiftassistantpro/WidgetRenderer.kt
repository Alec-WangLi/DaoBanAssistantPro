package com.daoban.shiftassistantpro

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.util.TypedValue
import android.widget.RemoteViews

import java.time.LocalDate

/**
 * 排版。**纯渲染**：不写盘、不排闹钟、不读除宿主配置之外的任何系统状态。
 *
 * 与 ShiftWidgetBase 分开是为了能单独读懂它 —— 这个类里没有一行涉及
 * 「什么时候刷新」「刷新排在哪」，只有「给我一份快照，我给你一棵 RemoteViews 树」。
 *
 * 三条纪律：
 *  1. Kotlin 侧一个中文字面量都不许有。所有文案都来自快照（Dart 侧 `L10n` 产出）。
 *     唯一的例外是占位态那行应用名，它取自 `applicationInfo.loadLabel()`。
 *  2. 明暗一律**显式选资源**，不依赖 `-night` 限定符 —— `RemoteViews` 由宿主进程
 *     inflate，限定符在宿主进程里的解析顺序各家 ROM 不一致。
 *  3. 布局只用 RemoteViews 白名单里的类：FrameLayout / LinearLayout / RelativeLayout /
 *     GridLayout + TextView / ImageView。**没有 ConstraintLayout**，报的是运行期
 *     `ClassNotFoundException`，不是编译错误。
 */
object WidgetRenderer {

    /**
     * dp → px。`RemoteViews` 里的尺寸单位是 px，送给 `WidgetChip` 画位图前要自己乘密度。
     */
    private fun dpToPx(context: Context, dp: Int): Int =
        (dp * context.resources.displayMetrics.density).toInt()

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
     * 班次闹钟 0..400、自定义闹钟 10000..11000、待办提醒 20000..21000，另有
     * `AlarmRingService` 的通知点击 0 / 1（同样带着 `alarm_label` 打向 `MainActivity`）
     * 与 `MainActivity.REQ_PICK_RINGTONE = 40071`。取 100000 起，全部避开。
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
     * 需要 `Root` + 16 个网格格 = 17，向上取到 32。
     *
     * ⚠️ **这个数不是随便取的，它是编址方案的护栏。** `Cell(w, n) = B + 16w + 1 + n`，
     * 当槽位数为 16 时 `n = 15` 会得到 `B + 16(w+1)` —— **正好等于下一个实例的 `Root`**，
     * 撞成同一个 PendingIntent（`filterEquals` 不比 extras，配 `FLAG_UPDATE_CURRENT`
     * 会互相冲掉 `widget_day`）。这个撞车类在本仓**真实发生过**（见 `launchIntent` 的 KDoc）。
     * 步长 32 之后 `Cell` 落在 `[32w+1, 32w+31]`，永不为 32 的倍数 ✓ 结构性根除。
     */
    private const val REQ_SLOTS_PER_WIDGET = 32

    /** 整卡的 requestCode：低位 0 留给「不指定日期」。 */
    private fun rootRequestCode(widgetId: Int): Int = WIDGET_REQ_BASE + widgetId * REQ_SLOTS_PER_WIDGET

    /** 第 cell 格的 requestCode。低位 +1 起，避开 `rootRequestCode` 的 0。 */
    private fun cellRequestCode(widgetId: Int, cell: Int): Int =
        WIDGET_REQ_BASE + widgetId * REQ_SLOTS_PER_WIDGET + 1 + cell

    /**
     * 打开 App 的 PendingIntent。
     *
     * 用 `getActivity` + 显式组件：隐式 LAUNCHER intent 在某些 ROM 上会被解析到
     * 「选择启动器」之类的东西上。
     *
     * ⚠️ requestCode 走上面那两个函数，**整卡与格子必须落在同一个仿射命名空间里**。
     * `PendingIntent` 的身份是「requestCode + 意图的 `filterEquals`」——而 `filterEquals`
     * **不比较 extras**，配上 `FLAG_UPDATE_CURRENT`（会覆盖 extras），两个实例只要
     * 满足 `A == 32 * B + c`（`c ∈ 0..31`）就会共用一个 PendingIntent、互相冲掉
     * `widget_day`，点一下跳到错的那天。
     *
     * **为什么步长必须是 32 而不是 16**：一个网格实例真正用到 `Cell(w, 0..15)`（16 格）。
     * 若步长仍是 16，末格 `Cell(m, 15) = B + 16m + 16 = B + 16(m+1)` —— **正好等于下一个
     * 实例的 `Root(m+1)`**，撞成同一个 PendingIntent；这个撞车类在本仓**真实发生过**
     * （初稿让整卡用**裸 `widgetId`**，单实例时 `16w + c ≠ w` 不自撞，所以在只有 id 34
     * 的桌面上测全过、藏得住；而 widget id **不是**「系统给的小整数」——它是设备级单调
     * 计数器，不复用，差 16 倍的两实例够得着）。步长提成 32 后 `Cell` 落在
     * `[32m+1, 32m+31]`、**永不为 32 的倍数**，而 `Root` 恒为 32 的倍数 —— 两者结构性
     * 错开，对任意 `n ≠ m` 都不相等，单实例内也不自撞。这不是「取个大点的数保险」，
     * 而是「格子数 16 与步长必须错开到不产生进位碰撞」的硬约束，见 `REQ_SLOTS_PER_WIDGET`。
     *
     * 现在 `Root(n) = WIDGET_REQ_BASE + 32n`、`Cell(m, c) = WIDGET_REQ_BASE + 32m + 1 + c`；
     * 基址再把它们整体抬离所有既有区间（见 `WIDGET_REQ_BASE`）。`widgetId` 涨到约
     * 6700 万才会 `Int` 溢出。
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
     * ⚠️ `TODAY` / `MONTH` 两个分支**暂时是旧的**（先走旧版式的渲染函数，保证每一步都编得过、
     * 桌面上也都看得见一张卡），Task 6 / 7 逐个换成 `renderTodayCard` / `monthCard`。
     * `WEEK_STRIP` 已在 Task 5 换成真的 `weekStrip`。
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
            // ⚠️ TASK4 临时：TODAY / MONTH 仍走旧版式的网格档，Task 6/7 逐个替换。
            WidgetVariant.TODAY -> gridWithCard(context, snap, todayIndex, widgetId, 8)
            WidgetVariant.MONTH -> gridWithCard(context, snap, todayIndex, widgetId, 16)
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
        val empty = context.getColor(if (dark) R.color.wg_empty_dark else R.color.wg_empty_light)

        val todayEpoch = snap.days[todayIndex].day
        val today = LocalDate.ofEpochDay(todayEpoch)
        val monday = today.minusDays((today.dayOfWeek.value - 1).toLong())

        val columns = intArrayOf(
            R.id.wg_ws_col1, R.id.wg_ws_col2, R.id.wg_ws_col3, R.id.wg_ws_col4,
            R.id.wg_ws_col5, R.id.wg_ws_col6, R.id.wg_ws_col7,
        )

        for (col in columns.indices) {
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
            for (id in intArrayOf(R.id.wg_sc_weekday, R.id.wg_sc_day, R.id.wg_sc_pill, R.id.wg_sc_abbr)) {
                // 可见性无条件设满：宿主 reapply 时只重放新动作，漏设会保持上一次的状态。
                c.setViewVisibility(id, android.view.View.VISIBLE)
            }

            c.setTextViewText(R.id.wg_sc_weekday, d.weekday)
            c.setTextColor(R.id.wg_sc_weekday, if (isToday) snap.accent else muted)
            // 日数字：与 App 的格子一样只印「日」，整串「9月19日」在 46dp 宽的列里排不下。
            c.setTextViewText(R.id.wg_sc_day, LocalDate.ofEpochDay(epoch).dayOfMonth.toString())
            c.setTextColor(R.id.wg_sc_day, if (isToday) snap.accent else ink)

            c.setImageViewBitmap(
                R.id.wg_sc_pill,
                WidgetChip.tintedChip(
                    if (d.hasShift) d.color else empty,
                    dpToPx(context, 36),
                    dpToPx(context, 18),
                ),
            )
            c.setTextViewText(R.id.wg_sc_abbr, if (d.hasShift) d.shiftAbbr else "")
            c.setTextColor(R.id.wg_sc_abbr, ink)

            v.addView(columns[col], c)
        }
        return v
    }

    /** 档位偏移 → 该显示哪个相对称法。≥3 直接用那天的周几（它不会腐坏）。 */
    private fun relativeLabel(snap: WidgetStore.Snapshot, index: Int, todayIndex: Int): String =
        when (index - todayIndex) {
            0 -> snap.today
            1 -> snap.tomorrow
            2 -> snap.dayAfter
            else -> snap.days[index].weekday
        }

    /**
     * 列表档（LIST_COMPACT / LIST_3 / LIST_5 共用）。
     *
     * [rowCount] 决定用哪张槽位布局：2 → `widget_list_compact`（22dp 行高），
     * 3 或 5 → `widget_list`（40dp 行高）。
     * [textSizeSp] 由档位给（紧凑 12、普通 13）—— 行布局里不写死字号，
     * 靠 `setTextViewTextSize` 按档设，一张布局供两档用。
     *
     * 槽位是**固定高度**、根布局 `gravity="center_vertical"`：多出来的高度成为上下
     * 均匀的留白，而不是把行拉长 —— 那是上一版被用户点名的问题。
     */
    private fun listRows(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
        rowCount: Int,
        textSizeSp: Float,
    ): RemoteViews {
        val compact = rowCount <= 2
        val v = RemoteViews(
            context.packageName,
            if (compact) R.layout.widget_list_compact else R.layout.widget_list,
        )
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            if (compact) R.id.wg_lc_root else R.id.wg_l5_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.setOnClickPendingIntent(
            if (compact) R.id.wg_lc_root else R.id.wg_l5_root,
            launchIntent(context, rootRequestCode(widgetId)),
        )

        // 空表提示 `wg_lc_hint` 只长在紧凑档那张布局上。这里显式设 GONE：`empty()`
        // 会把它设成 VISIBLE，同一实例从空表切到有排班时宿主走 `reapply`、只重放新动作
        // —— 不显式设回来，提示会一直挂在正常的两行卡上。
        if (compact) v.setViewVisibility(R.id.wg_lc_hint, android.view.View.GONE)

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted =
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)
        val empty = context.getColor(
            if (dark) R.color.wg_empty_dark else R.color.wg_empty_light
        )

        val slots = if (compact) {
            intArrayOf(R.id.wg_lc_slot1, R.id.wg_lc_slot2)
        } else {
            intArrayOf(
                R.id.wg_l5_slot1, R.id.wg_l5_slot2, R.id.wg_l5_slot3,
                R.id.wg_l5_slot4, R.id.wg_l5_slot5,
            )
        }

        for (row in slots.indices) {
            val i = todayIndex + row
            // 两个都要挡：快照窗口耗尽（todayIndex 靠后），以及这一档要的行数
            // 比槽位数多。越界读会被 ShiftWidgets 的 try/catch 吞掉，
            // 后果不是崩而是**卡片继续显示上一次渲染的旧内容**。
            if (row >= rowCount || i >= snap.days.size) {
                v.setViewVisibility(slots[row], android.view.View.GONE)
                continue
            }
            v.setViewVisibility(slots[row], android.view.View.VISIBLE)

            val d = snap.days[i]
            val r = RemoteViews(context.packageName, R.layout.widget_row)
            // 可见性无条件设满：同一张布局被两种档位复用，宿主走 `reapply` 时
            // 只重放新的动作列表 —— 不显式设回来的视图会保持上一次的状态。
            for (id in intArrayOf(
                R.id.wg_r_dot, R.id.wg_r_label, R.id.wg_r_date, R.id.wg_r_shift,
            )) {
                r.setViewVisibility(id, android.view.View.VISIBLE)
            }

            r.setImageViewBitmap(
                R.id.wg_r_dot,
                WidgetChip.circle(
                    if (d.hasShift) d.color else empty,
                    dpToPx(context, 8),
                ),
            )
            r.setTextViewText(R.id.wg_r_label, relativeLabel(snap, i, todayIndex))
            r.setTextColor(R.id.wg_r_label, ink)
            r.setTextViewText(R.id.wg_r_date, d.dateShort)
            r.setTextColor(R.id.wg_r_date, muted)
            r.setTextViewText(
                R.id.wg_r_shift,
                if (d.hasShift) d.shiftName else d.weekday,
            )
            r.setTextColor(R.id.wg_r_shift, ink)

            if (d.timeRange == null) {
                r.setViewVisibility(R.id.wg_r_time, android.view.View.GONE)
            } else {
                r.setViewVisibility(R.id.wg_r_time, android.view.View.VISIBLE)
                r.setTextViewText(R.id.wg_r_time, d.timeRange)
                r.setTextColor(R.id.wg_r_time, muted)
            }

            for (id in intArrayOf(
                R.id.wg_r_label, R.id.wg_r_date, R.id.wg_r_shift, R.id.wg_r_time,
            )) {
                r.setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_SP, textSizeSp)
            }

            v.addView(slots[row], r)
        }
        return v
    }

    /**
     * 网格档（GRID_WEEK / GRID_FORTNIGHT 共用）。**只出网格本身**，由 `gridWithCard`
     * 塞进装配壳、与今日卡片拼成一张卡。
     *
     * [cellCount] = 8（一周，用到前 7 格）或 16（两周，用到前 14 格）。
     * 格高固定 56dp，多出来的高度由**今日卡片**和留白吃（见 `gridWithCard`）。
     * 卡片底色与整卡根点击**不在这里设** —— 已挪到外壳根上，理由见函数体的注释。
     *
     * 「今天」那格（永远是最前面那一格，因为网格从今天起排）的日期走**主色** ——
     * 大卡每格只有日期 + 胶囊、没有相对称法，「今天」否则完全认不出来。
     * **不能用加粗**：`TextView` 没有 `setTypeface(int)` 重载，
     * `v.setInt(id, "setTypeface", ...)` 会在宿主进程抛 `ActionException`。
     */
    private fun gridCells(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
        cellCount: Int,
        accent: Int,
    ): RemoteViews {
        val fortnight = cellCount > 8
        val v = RemoteViews(
            context.packageName,
            if (fortnight) R.layout.widget_grid_fortnight else R.layout.widget_grid_week,
        )
        val dark = isDark(context, snap.themeMode)
        // ⚠️ 卡片底色与**整卡根点击**都**不在这里设** —— 它们已挪到外壳
        // `widget_grid_with_card` 的根上（`gridWithCard`）。理由：网格现在只是外壳里的
        // 一个内容块，外壳才是一张卡的可视边界；且外壳根高 `match_parent`、把整块都盖住，
        // 而网格本身是 `wrap_content` 高 —— 只在网格上设背景与点击，小组件底部那截
        // （Task 5 评审量到卡只占高度的 37%/44%）就成了全死区，且用户肉眼看不见
        // （可见卡 == 可点区）。**只挪背景不挪点击会得到一张全死的卡。**

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted =
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)
        val empty = context.getColor(
            if (dark) R.color.wg_empty_dark else R.color.wg_empty_light
        )

        val slots = if (fortnight) {
            intArrayOf(
                R.id.wg_gf_slot1, R.id.wg_gf_slot2, R.id.wg_gf_slot3, R.id.wg_gf_slot4,
                R.id.wg_gf_slot5, R.id.wg_gf_slot6, R.id.wg_gf_slot7, R.id.wg_gf_slot8,
                R.id.wg_gf_slot9, R.id.wg_gf_slot10, R.id.wg_gf_slot11, R.id.wg_gf_slot12,
                R.id.wg_gf_slot13, R.id.wg_gf_slot14, R.id.wg_gf_slot15, R.id.wg_gf_slot16,
            )
        } else {
            intArrayOf(
                R.id.wg_gw_slot1, R.id.wg_gw_slot2, R.id.wg_gw_slot3, R.id.wg_gw_slot4,
                R.id.wg_gw_slot5, R.id.wg_gw_slot6, R.id.wg_gw_slot7, R.id.wg_gw_slot8,
            )
        }

        // 用得到的格数：一周 7 天、两周 14 天。剩下的槽位隐藏 —— 但**不 GONE 之外的
        // 余地**：GridLayout 里 GONE 的子视图不参与布局，所以末行不会留空位。
        val used = if (fortnight) 14 else 7

        for (cell in slots.indices) {
            val i = todayIndex + cell
            if (cell >= used || i >= snap.days.size) {
                v.setViewVisibility(slots[cell], android.view.View.GONE)
                continue
            }
            v.setViewVisibility(slots[cell], android.view.View.VISIBLE)

            val d = snap.days[i]
            // 点某一格 → 打开 App 并跳到那天。与外壳根点击走同一套 requestCode
            // 命名空间：一个实例占 32 个槽位，根取偏移 0、格子取偏移 1..16（格 0..15）。
            // 步长之所以是 32 而不是 16 —— 16 时格 15 会进位撞上下一实例的根，
            // 见 `REQ_SLOTS_PER_WIDGET` 与 `launchIntent` 的 KDoc。
            // 这条是上一版 large() 就有的功能（用户真机验过），本轮的网格替换了它，
            // 别把它丢掉。
            v.setOnClickPendingIntent(
                slots[cell],
                launchIntent(
                    context,
                    cellRequestCode(widgetId, cell),
                    epochDay = d.day.toInt(),
                ),
            )
            val c = RemoteViews(context.packageName, R.layout.widget_cell)
            c.setViewVisibility(R.id.wg_c_date, android.view.View.VISIBLE)
            c.setViewVisibility(R.id.wg_c_pill, android.view.View.VISIBLE)
            c.setViewVisibility(R.id.wg_c_abbr, android.view.View.VISIBLE)

            c.setTextViewText(R.id.wg_c_date, d.dateShort)
            // 「今天」永远是最前面那一格（网格从今天起排）。
            c.setTextColor(R.id.wg_c_date, if (cell == 0) accent else muted)

            c.setImageViewBitmap(
                R.id.wg_c_pill,
                WidgetChip.pill(
                    if (d.hasShift) d.color else empty,
                    dpToPx(context, 48),
                    dpToPx(context, 22),
                ),
            )
            c.setTextViewText(R.id.wg_c_abbr, if (d.hasShift) d.shiftAbbr else "")
            c.setTextColor(R.id.wg_c_abbr, ink)

            v.addView(slots[cell], c)
        }
        return v
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
     * ⚠️ 本函数渲染的内容**永远在外壳内**（只被 `gridWithCard` 调用），所以自己**不画**
     * 卡片底 —— 画了就是双层边：外壳根与卡片根铺同一张带 `1dp` stroke / 22dp 圆角的
     * drawable，成品上会多出一圈圆角描边、悬在外壳边框内侧。卡片底只画一层，在外壳上。
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

        // 日期/班次/时间/色点一律取 `days[todayIndex]` 而**不是** `todayCard` ——
        // `days[]` 会被原生对表右移、永远是对的；`todayCard` 不会。
        val d = snap.days[todayIndex]
        val tc = snap.todayCard
        val stale = tc == null || tc.day != LocalDate.now().toEpochDay()

        // ── 1. 日期行 ──
        v.setImageViewBitmap(
            R.id.wg_tc_bar,
            WidgetChip.bar(
                if (d.hasShift) d.color else snap.accent,
                dpToPx(context, 4),
                dpToPx(context, 18),
            ),
        )
        v.setTextViewText(R.id.wg_tc_date, d.dateShort)
        v.setTextColor(R.id.wg_tc_date, ink)

        // 「今天」徽章。宽度写死在布局里 —— RemoteViews 量不到文字宽度。
        v.setImageViewBitmap(
            R.id.wg_tc_today_bg,
            WidgetChip.tintedChip(snap.accent, dpToPx(context, 52), dpToPx(context, 20)),
        )
        v.setTextViewText(R.id.wg_tc_today_text, snap.today)
        v.setTextColor(R.id.wg_tc_today_text, snap.accent)

        // 「N 项待办」徽章。`todoBadge` 为空（没有待办）或快照跨天 → 整块隐藏。
        val todoText = if (stale) null else tc.todoBadge
        if (todoText == null) {
            v.setViewVisibility(R.id.wg_tc_todo_wrap, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_todo_wrap, android.view.View.VISIBLE)
            v.setImageViewBitmap(
                R.id.wg_tc_todo_bg,
                WidgetChip.tintedChip(snap.accent, dpToPx(context, 84), dpToPx(context, 20)),
            )
            v.setTextViewText(R.id.wg_tc_todo_text, todoText)
            v.setTextColor(R.id.wg_tc_todo_text, snap.accent)
        }

        // ── 2. 农历：跨天就隐藏（它是生成那天的） ──
        if (stale) {
            v.setViewVisibility(R.id.wg_tc_lunar, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_lunar, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_tc_lunar, tc.lunarShort)
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
                    dpToPx(context, 20),
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
            for (slot in crewSlots.indices) {
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

        return v
    }

    /**
     * 网格 + 今日卡片的**装配壳**。两个纵向槽位各塞一份嵌套 `RemoteViews`。
     *
     * 外壳根是 `match_parent` 高、`gravity="center_vertical"`：网格与卡片都定高，
     * 多出来的竖直空间成为上下均匀留白 —— 不把任何一块拉长。
     *
     * **卡片底色与整卡根点击设在外壳根上**（不再设在 `gridCells` 里）：外壳才是一张卡的
     * 可视边界，而它的根铺满整个小组件；只在 `wrap_content` 高的网格上设，小组件底部
     * 那截就成死区。两者必须一起挪 —— 只挪背景会得到一张全死的卡。
     */
    private fun gridWithCard(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
        cellCount: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_grid_with_card)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_gwc_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        // 整卡点击 → 打开 App（落在日历页的今天）：点在网格与卡片之间的空隙、
        // 以及被隐藏的末尾槽位上时走这一条。逐格点击由 `gridCells` 设在格子上，
        // 卡片内部由 `renderTodayCard` 设在自己的根上。
        v.setOnClickPendingIntent(
            R.id.wg_gwc_root,
            launchIntent(context, rootRequestCode(widgetId)),
        )
        v.addView(
            R.id.wg_gwc_grid_slot,
            gridCells(context, snap, todayIndex, widgetId, cellCount, snap.accent),
        )
        v.addView(R.id.wg_gwc_card_slot, renderTodayCard(context, snap, todayIndex, widgetId))
        return v
    }

    /**
     * 空表态：没有排班（`snap.hasSchedule == false`）。
     *
     * **复用紧凑列表的壳**（`widget_list_compact`）：它最矮、空表本来也没什么可说的。
     * 两个行槽位都 GONE，提示挂在槽位**之外**的常驻 `wg_lc_hint` 上 —— 所以那张布局里
     * 除了两个槽位，还有一个常驻的 `TextView`。反过来，`listRows()` 在正常两行档里必须
     * 把 `wg_lc_hint` 设回 GONE：可见性两个方向都要设满（宿主 `reapply` 只重放新动作）。
     *
     * 文案来自快照的 `emptyHint`（Dart 侧 `L10n.widgetEmptyHint` 产出）——
     * Kotlin 侧仍然一个字面量都没有。
     */
    private fun empty(context: Context, snap: WidgetStore.Snapshot, widgetId: Int): RemoteViews {
        // 空表提示复用紧凑列表的壳：它最矮、空表本来也没什么可说的。
        // 两个行槽位都 GONE，提示文字挂在槽位之外 —— 所以 widget_list_compact
        // 里除了两个槽位，还要有一个常驻的 TextView `wg_lc_hint`。
        val v = RemoteViews(context.packageName, R.layout.widget_list_compact)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_lc_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.setOnClickPendingIntent(R.id.wg_lc_root, launchIntent(context, rootRequestCode(widgetId)))
        // 可见性显式设满：这张布局也被正常两行档复用，宿主 reapply 时只重放新动作。
        v.setViewVisibility(R.id.wg_lc_slot1, android.view.View.GONE)
        v.setViewVisibility(R.id.wg_lc_slot2, android.view.View.GONE)
        v.setViewVisibility(R.id.wg_lc_hint, android.view.View.VISIBLE)
        v.setTextViewText(R.id.wg_lc_hint, snap.emptyHint)
        v.setTextColor(
            R.id.wg_lc_hint,
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
