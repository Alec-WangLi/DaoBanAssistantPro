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
 * 与 ShiftWidgetProvider 分开是为了能单独读懂它 —— 这个类里没有一行涉及
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
     * `ShiftWidgetProvider` 且 `setAction` 过，目标组件与 `filterEquals` 都不同，
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
     * [snap] 为 null（没有快照 / 解析失败 / 版本对不上）或快照已过期时，返回占位态。
     */
    fun render(
        context: Context,
        snap: WidgetStore.Snapshot?,
        tier: WidgetTier,
        widgetId: Int,
    ): RemoteViews {
        if (snap == null) return placeholder(context, dark = isDark(context, "system"), widgetId = widgetId)
        val todayIndex = snap.indexOfToday()
        if (todayIndex < 0) {
            // 快照过期：App 超过 14 天没打开，这份 days 里已经没有今天了。
            AlarmLog.info(context, "WidgetRenderer: 快照已过期，走占位态")
            return placeholder(context, isDark(context, snap.themeMode), widgetId = widgetId)
        }
        // 空表（没建过排班 / 选了「跟随法定节假日」那种空白表方案）：整张卡只留
        // 一句来自快照的提示。这一支必须在分档**之前** —— 三档尺寸在空表下长得
        // 一致，不必各写一套。
        if (!snap.hasSchedule) return empty(context, snap, widgetId)
        return when (tier) {
            WidgetTier.LIST_COMPACT -> listRows(context, snap, todayIndex, widgetId, 2, 12f)
            WidgetTier.LIST_3 -> listRows(context, snap, todayIndex, widgetId, 3, 13f)
            WidgetTier.LIST_5 -> listRows(context, snap, todayIndex, widgetId, 5, 13f)
            // 网格两档 = 网格 + 今日卡片，两张一起装配进 `widget_grid_with_card`。
            // 网格定高、卡片定高，多出来的高度成上下均匀留白（见 `gridWithCard`）。
            WidgetTier.GRID_WEEK -> gridWithCard(context, snap, todayIndex, widgetId, 8)
            WidgetTier.GRID_FORTNIGHT -> gridWithCard(context, snap, todayIndex, widgetId, 16)
        }
    }

    /** 档位偏移 → 该显示哪个相对称法。≥3 直接用那天的周几（它不会腐坏）。 */
    private fun relativeLabel(snap: WidgetStore.Snapshot, index: Int, todayIndex: Int): String =
        when (index - todayIndex) {
            0 -> snap.today
            1 -> snap.tomorrow
            2 -> snap.dayAfter
            else -> snap.days[index].weekday
        }

    private fun small(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_small)
        val dark = isDark(context, snap.themeMode)
        val today = snap.days[todayIndex]

        v.setInt(
            R.id.wg_s_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        // 整卡点击 → 打开 App（落在日历页的今天）。这一步不传 epochDay。
        v.setOnClickPendingIntent(R.id.wg_s_root, launchIntent(context, rootRequestCode(widgetId)))

        // 可见性必须**显式设满**，不能依赖「上次是可见的」：`empty()` 复用同一张布局
        // `R.layout.widget_small`，会把班次区那几个视图设成 GONE；而宿主在布局 id 不变时
        // 走 `RemoteViews.reapply`、只重放**新的**动作列表 —— 不显式设回来的话，
        // 「空表态 → 建好排班」之后小卡会永久丢掉班次名 / 日期 / 色条 / 分隔线，
        // 只剩「今天」+ 时间串 + 明天预告，直到桌面重新 inflate 才恢复。
        // 与「休班日不复位位图」同一根因（只重放新动作 → 没被重设的留着旧值），
        // 同一套修法：让动作列表齐次。`wg_s_time` 的 VISIBLE 由下面按有无时间覆盖。
        for (id in intArrayOf(
            R.id.wg_s_weekday, R.id.wg_s_date, R.id.wg_s_bar,
            R.id.wg_s_shift, R.id.wg_s_divider, R.id.wg_s_next,
        )) {
            v.setViewVisibility(id, android.view.View.VISIBLE)
        }

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted =
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)
        val divider =
            context.getColor(if (dark) R.color.wg_divider_dark else R.color.wg_divider_light)

        v.setTextViewText(R.id.wg_s_relative, relativeLabel(snap, todayIndex, todayIndex))
        v.setTextColor(R.id.wg_s_relative, ink)
        v.setTextViewText(R.id.wg_s_weekday, today.weekday)
        v.setTextColor(R.id.wg_s_weekday, muted)
        v.setTextViewText(R.id.wg_s_date, today.dateShort)
        v.setTextColor(R.id.wg_s_date, muted)

        // 没有班次（空表 / 休班）时，班次名那行显示周几兜底 —— 快照里 shiftName 是
        // 空串，直接设空会让整行塌掉、时间行往上跳。
        v.setTextViewText(
            R.id.wg_s_shift,
            if (today.hasShift) today.shiftName else today.weekday,
        )
        v.setTextColor(R.id.wg_s_shift, ink)

        if (today.timeRange == null) {
            v.setViewVisibility(R.id.wg_s_time, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_s_time, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_s_time, today.timeRange)
            v.setTextColor(R.id.wg_s_time, muted)
        }

        // 色条：6dp 宽、撑满班次区高度。高度要到布局跑完才知道，这里按一个固定值
        // 画（180dp 档位下这个区域约 60dp），贴上去时 ImageView 会用 `fitXY` 把它
        // 缩放到控件大小 —— **是缩放不是裁切**，所以 6dp 宽这条被纵向压到约 0.83×、
        // 圆头成微椭圆。肉眼几乎无差，但别在注释里写成「只会被裁」（那是错的，
        // 而且与本次特意修掉的那类「假保证」同源）。
        //
        // ⚠️ 休班日也要**设位图**，不能只 `setBackgroundColor`。理由：`setBackgroundColor`
        // 设的是 background，而班次日设的是 image；宿主在布局 id 不变时会走
        // `RemoteViews.reapply`，它只重放**新的**动作列表 —— 没被重设的 image 会留着
        // 旧位图、盖在新背景色上面。结果就是「昨天白班、今天休班」那天，色条还挂着
        // 昨天的颜色。统一都设位图，从结构上免疫，而不是逐个分支打补丁。
        v.setImageViewBitmap(
            R.id.wg_s_bar,
            WidgetChip.bar(
                if (today.hasShift) {
                    today.color
                } else {
                    context.getColor(if (dark) R.color.wg_empty_dark else R.color.wg_empty_light)
                },
                dpToPx(context, 6),
                dpToPx(context, 72),
            ),
        )

        v.setInt(R.id.wg_s_divider, "setBackgroundColor", divider)

        // 明天预告。今天已是窗口最后一天时（todayIndex=13，窗口 14 天）没有明天，
        // 留空 —— **这不是「不可能」**：快照是 14 天，todayIndex 落在 [0,13] 是设计
        // 明确支持的状态（跨天只右移不重算），13 时这里真的会走到 GONE 这一支。
        // 把「不可能」写进注释会让下一处真的越界的代码失去戒心（large() 漏闸
        // 就是这么活到评审的）。
        val nextIndex = todayIndex + 1
        if (nextIndex < snap.days.size) {
            val n = snap.days[nextIndex]
            val label = relativeLabel(snap, nextIndex, todayIndex)
            val tail = if (n.hasShift) {
                if (n.timeRange == null) n.shiftName else "${n.shiftName} ${n.timeRange}"
            } else {
                n.weekday
            }
            v.setTextViewText(R.id.wg_s_next, "$label  $tail")
            v.setViewVisibility(R.id.wg_s_next, android.view.View.VISIBLE)
        } else {
            v.setViewVisibility(R.id.wg_s_next, android.view.View.GONE)
        }
        v.setTextColor(R.id.wg_s_next, muted)

        return v
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
            // 比槽位数多。越界读会被 ShiftWidgetProvider 的 try/catch 吞掉，
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
            c.setTextColor(R.id.wg_c_abbr, d.abbrInk)

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

    private fun medium(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        dark: Boolean,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_medium)
        v.setInt(
            R.id.wg_m_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        // 整卡点击 → 打开 App（落在日历页的今天）。
        v.setOnClickPendingIntent(R.id.wg_m_root, launchIntent(context, rootRequestCode(widgetId)))

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted =
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)
        val divider =
            context.getColor(if (dark) R.color.wg_divider_dark else R.color.wg_divider_light)
        val empty = context.getColor(
            if (dark) R.color.wg_empty_dark else R.color.wg_empty_light
        )

        // 三行的 id 表。顺序与 widget_medium.xml 里的行顺序一一对应。
        val dots = intArrayOf(R.id.wg_m_dot1, R.id.wg_m_dot2, R.id.wg_m_dot3)
        val labels = intArrayOf(R.id.wg_m_label1, R.id.wg_m_label2, R.id.wg_m_label3)
        val dates = intArrayOf(R.id.wg_m_date1, R.id.wg_m_date2, R.id.wg_m_date3)
        val shifts = intArrayOf(R.id.wg_m_shift1, R.id.wg_m_shift2, R.id.wg_m_shift3)
        val times = intArrayOf(R.id.wg_m_time1, R.id.wg_m_time2, R.id.wg_m_time3)
        val divs = intArrayOf(R.id.wg_m_div1, R.id.wg_m_div2)

        for (row in 0 until 3) {
            val i = todayIndex + row
            if (i >= snap.days.size) {
                // 窗口耗尽：今天已经排到 days[12] / days[13]（App 十来天没打开，
                // 跨天只右移不重算）。整行隐藏。
                // ⚠️ 这**不是**「不可能」—— 原注释那么写是错的，Task 4 的评审算过：
                // todayIndex ∈ [0,13] 是设计明确支持的状态，12/13 时这里真的会走到。
                for (idArr in listOf(dots, labels, dates, shifts, times)) {
                    v.setViewVisibility(idArr[row], android.view.View.GONE)
                }
                continue
            }
            // 每个分支都要**显式设可见性**（与小卡同一条纪律，只是这条更罕见）：
            // 今天下标单调递增，所以只有设备日期回退（改钟、跨时区西行）才会让某行
            // 从「越界 GONE」又回到「在界内」；那时不显式设 VISIBLE 就会一直留着
            // GONE，整行再不出现。`times[row]` 随后按有无时间覆盖一次。
            for (idArr in listOf(dots, labels, dates, shifts, times)) {
                v.setViewVisibility(idArr[row], android.view.View.VISIBLE)
            }
            val d = snap.days[i]

            // 色点：今天是实心圆点，其余是同样的实心 —— 「今天」那行靠字重与
            // 相对称法区分，不靠点的形状。
            //
            // 休班也设位图（浅色圆点），理由同小卡色条：只 `setBackgroundColor`
            // 会让上一次的位图留在 ImageView 上。
            v.setImageViewBitmap(
                dots[row],
                WidgetChip.circle(
                    if (d.hasShift) d.color else empty,
                    dpToPx(context, 8),
                ),
            )

            v.setTextViewText(labels[row], relativeLabel(snap, i, todayIndex))
            v.setTextColor(labels[row], ink)
            v.setTextViewText(dates[row], d.dateShort)
            v.setTextColor(dates[row], muted)

            v.setTextViewText(
                shifts[row],
                if (d.hasShift) d.shiftName else d.weekday,
            )
            v.setTextColor(shifts[row], ink)

            if (d.timeRange == null) {
                v.setViewVisibility(times[row], android.view.View.GONE)
            } else {
                v.setViewVisibility(times[row], android.view.View.VISIBLE)
                v.setTextViewText(times[row], d.timeRange)
                v.setTextColor(times[row], muted)
            }
        }
        // 分隔线只画在「上面那一行可见、且下面也还有一行」的地方 —— 否则行被隐藏后
        // 会在空白区域留一条悬空的线（窗口将耗尽时真的会发生）。
        for (k in divs.indices) {
            val above = todayIndex + k < snap.days.size
            val below = todayIndex + k + 1 < snap.days.size
            v.setViewVisibility(
                divs[k],
                if (above && below) android.view.View.VISIBLE else android.view.View.GONE,
            )
            v.setInt(divs[k], "setBackgroundColor", divider)
        }

        return v
    }

    /** 大卡的格子：今天起连续 7 天。第 8 格恒隐藏 —— 它占着位置让前 7 格保持 4 列均分。 */
    private fun large(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_large)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_l_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        // 整卡点击 → 打开 App（落在日历页的今天）：点在格子之间的空隙 / 第 8 格
        // 那些没被下面逐格覆盖的地方时走这一条。
        v.setOnClickPendingIntent(R.id.wg_l_root, launchIntent(context, rootRequestCode(widgetId)))

        // 这里**不**声明 ink：大卡的日期走 muted（今天那格走 accent）、简称走
        // abbrInk（Dart 侧按班次色算好的白/黑二选一），没有需要纯正文色的地方。
        // 声明了会被 analyze 报未使用。
        val muted =
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)
        val empty = context.getColor(
            if (dark) R.color.wg_empty_dark else R.color.wg_empty_light
        )

        // 显式列 id，**不要**用 `resources.getIdentifier("wg_l_cell$n", ...)` ——
        // 后者靠名字反射，改个 id 名只在运行时静默返回 0，编译期毫无提示。
        val cells = intArrayOf(
            R.id.wg_l_cell1, R.id.wg_l_cell2, R.id.wg_l_cell3, R.id.wg_l_cell4,
            R.id.wg_l_cell5, R.id.wg_l_cell6, R.id.wg_l_cell7, R.id.wg_l_cell8,
        )
        val dates = intArrayOf(
            R.id.wg_l_date1, R.id.wg_l_date2, R.id.wg_l_date3, R.id.wg_l_date4,
            R.id.wg_l_date5, R.id.wg_l_date6, R.id.wg_l_date7, R.id.wg_l_date8,
        )
        val pills = intArrayOf(
            R.id.wg_l_pill1, R.id.wg_l_pill2, R.id.wg_l_pill3, R.id.wg_l_pill4,
            R.id.wg_l_pill5, R.id.wg_l_pill6, R.id.wg_l_pill7, R.id.wg_l_pill8,
        )
        val abbrs = intArrayOf(
            R.id.wg_l_abbr1, R.id.wg_l_abbr2, R.id.wg_l_abbr3, R.id.wg_l_abbr4,
            R.id.wg_l_abbr5, R.id.wg_l_abbr6, R.id.wg_l_abbr7, R.id.wg_l_abbr8,
        )

        for (cell in 0 until 7) {
            val i = todayIndex + cell
            // ⚠️ 边界保护必须有，而且**这不是「防御性代码」**：快照是 14 天，`todayIndex`
            // 落在 [0,13] 是设计明确支持的状态（跨天只右移不重算，App 八天以上没打开就
            // 会走到 8 以后）。越界抛的 `IndexOutOfBoundsException` 会被
            // `ShiftWidgetProvider.renderAll` 的 try/catch 吞掉 —— 结果不是崩，而是
            // `updateAppWidget` 被跳过、卡片**继续显示上一次渲染的旧日期**，正是
            // `widget_snapshot.dart` 开头警告的「理直气壮写错」。
            // （Task 4 的评审算过：medium() 有这道闸、large() 漏了，6/14 的窗口都会中招。）
            if (i >= snap.days.size) {
                v.setViewVisibility(cells[cell], android.view.View.GONE)
                continue
            }
            val d = snap.days[i]
            v.setViewVisibility(cells[cell], android.view.View.VISIBLE)
            // 点某一格 → 打开 App 并跳到那天。requestCode 走 `cellRequestCode`，
            // 与整卡的 `rootRequestCode` 落在同一个命名空间里 —— 初稿写的是
            // `widgetId * 16 + cell` 而整卡用裸 `widgetId`，那两个空间会撞（见
            // `launchIntent` 的注释）。
            v.setOnClickPendingIntent(
                cells[cell],
                launchIntent(context, cellRequestCode(widgetId, cell), epochDay = d.day.toInt()),
            )
            v.setTextViewText(dates[cell], d.dateShort)
            // 「今天」那格（cell == 0，大卡就是「从今天起连续 7 天」）：日期走**主色**。
            // 字重由**布局**给出 —— `wg_l_date1` 是 `android:textStyle="bold"`、
            // 其余 `wg_l_date2..8` 是常规字重 —— 于是「今天」比别的格更重、又带主色，
            // 4×4 上一眼认得出来。
            //
            // 为什么字重放在布局、而不是像 spec 初稿那样现场改：
            //   · spec 初稿的大卡方案是「被『今天』那格主色描边」。描边要用 `WidgetChip`
            //     画一张带描边的位图，而 `RemoteViews` 在渲染时**量不到单元格的实际尺寸**，
            //     只能按固定尺寸画再由 `fitXY` 拉伸 —— 拉伸会把圆角拉成椭圆、把 1dp 描边
            //     拉成粗细不匀的边（正是小卡色条那处「6×72dp 被压成 0.83×、圆头成微椭圆」
            //     的同一类问题）。所以改成「今天的日期用主色 + 加粗」——既避开像素级拉伸，
            //     又正是本项目自己日历格的既有配方（`design_tokens.dart` 里「格子里的
            //     「今天」加粗」）。
            //   · 加粗**不能**走 `v.setInt(id, "setTypeface", <int>)`：`TextView` 只有
            //     `setTypeface(Typeface)` 与 `setTypeface(Typeface, int)` 两个重载，**没有**
            //     `setTypeface(int)`，`setInt` 反射时找不到方法会在宿主进程抛 `ActionException`、
            //     整张卡不更新（`javap` 查过 android.jar 确认无 `setTypeface(int)`）。
            //     所以字重静态写在布局里，渲染侧只设颜色。
            v.setTextColor(dates[cell], if (cell == 0) snap.accent else muted)

            // 胶囊宽度写死：RemoteViews 里量不到文字宽度（排版在宿主进程做）。
            // 3 个字的简称（中文最多 2 字、英文最多 4 个字母的缩写）在 12sp 下
            // 约 40dp 就够；给 48dp 留余量，多的部分由 fitXY 拉伸，
            // 而 TextView 是居中的，视觉上看不出来。
            //
            // 休班也设位图（浅色空胶囊），理由同小卡色条。
            v.setImageViewBitmap(
                pills[cell],
                WidgetChip.pill(
                    if (d.hasShift) d.color else empty,
                    dpToPx(context, 48),
                    dpToPx(context, 22),
                ),
            )
            // 文字也走「无条件设」：休班那格清空。写「休」会和真叫「休班」的
            // 班次撞在一起，用户分不出哪个是排出来的、哪个是空着的。
            // `abbrInk` 在无班次时 Dart 侧给的是 0（透明），空串配透明字正好。
            v.setTextViewText(abbrs[cell], if (d.hasShift) d.shiftAbbr else "")
            v.setTextColor(abbrs[cell], d.abbrInk)
        }

        // 第 8 格必须显式 GONE：它有 layout_columnWeight，不隐藏就仍占掉四分之一
        // 宽度，前 7 格会被挤成一行 7 个。
        v.setViewVisibility(cells[7], android.view.View.GONE)
        return v
    }

    /**
     * 空表态：没有排班（`snap.hasSchedule == false`）。
     *
     * 为什么不复用 `small()` 加几个 if：那条路要隐藏六七个视图，且留下的东西
     * （「今天 周四 / 周四 / 后天 周五」）看着像一张正常的班次卡，用户会以为
     * 排班已经生效了。这里清空重设，语义上就是「还没排班」这一件事。
     *
     * 文案来自快照的 `emptyHint`（Dart 侧 `L10n.widgetEmptyHint` 产出）——
     * Kotlin 侧仍然一个字面量都没有。
     */
    private fun empty(context: Context, snap: WidgetStore.Snapshot, widgetId: Int): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_small)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_s_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        // 空表态也要能点开 App —— 用的是同一个 widget_small 布局，根 id 同为
        // `wg_s_root`。用户看到「还没排班」时点一下应该进 App 去建排班。
        v.setOnClickPendingIntent(R.id.wg_s_root, launchIntent(context, rootRequestCode(widgetId)))
        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        v.setTextViewText(R.id.wg_s_relative, snap.emptyHint)
        v.setTextColor(R.id.wg_s_relative, ink)
        for (id in intArrayOf(
            R.id.wg_s_weekday, R.id.wg_s_date, R.id.wg_s_bar,
            R.id.wg_s_shift, R.id.wg_s_time, R.id.wg_s_divider, R.id.wg_s_next,
        )) {
            v.setViewVisibility(id, android.view.View.GONE)
        }
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
