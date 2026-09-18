package com.daoban.shiftassistantpro

import android.content.Context
import android.content.res.Configuration
import android.widget.RemoteViews

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
    ): RemoteViews {
        if (snap == null) return placeholder(context, dark = isDark(context, "system"))
        val todayIndex = snap.indexOfToday()
        if (todayIndex < 0) {
            // 快照过期：App 超过 14 天没打开，这份 days 里已经没有今天了。
            AlarmLog.info(context, "WidgetRenderer: 快照已过期，走占位态")
            return placeholder(context, isDark(context, snap.themeMode))
        }
        // 空表（没建过排班 / 选了「跟随法定节假日」那种空白表方案）：整张卡只留
        // 一句来自快照的提示。这一支必须在分档**之前** —— 三档尺寸在空表下长得
        // 一致，不必各写一套。
        if (!snap.hasSchedule) return empty(context, snap)
        val dark = isDark(context, snap.themeMode)
        return when (tier) {
            // 小卡与大卡自己算 dark（它们只在这一个地方被调），中卡由外面传进去 ——
            // 中卡的三行共用一个 dark，传参比在循环里每次重算清楚。
            WidgetTier.SMALL -> small(context, snap, todayIndex)
            WidgetTier.MEDIUM -> medium(context, snap, todayIndex, dark = dark)
            WidgetTier.LARGE -> large(context, snap, todayIndex)
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
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_small)
        val dark = isDark(context, snap.themeMode)
        val today = snap.days[todayIndex]

        v.setInt(
            R.id.wg_s_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )

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

    private fun medium(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        dark: Boolean,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_medium)
        v.setInt(
            R.id.wg_m_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )

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
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_large)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_l_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )

        // 这里**不**声明 ink：大卡的日期走 muted、简称走 abbrInk（Dart 侧按班次色
        // 算好的白/黑二选一），没有需要纯正文色的地方。声明了会被 analyze 报未使用。
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
            v.setTextViewText(dates[cell], d.dateShort)
            v.setTextColor(dates[cell], muted)

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
    private fun empty(context: Context, snap: WidgetStore.Snapshot): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_small)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_s_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
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

    private fun placeholder(context: Context, dark: Boolean): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_placeholder)
        v.setInt(
            R.id.wg_ph_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
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
