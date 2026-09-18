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
        return when (tier) {
            WidgetTier.SMALL -> small(context, snap, todayIndex)
            WidgetTier.MEDIUM -> small(context, snap, todayIndex) // Task 4 换成 medium(...)
            WidgetTier.LARGE -> small(context, snap, todayIndex)  // Task 4 换成 large(...)
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

        // 色条：Task 5 会换成带圆角的位图。现在是实色 —— `setBackgroundColor`
        // 对任何 View 都有效，且不需要位图。
        v.setInt(
            R.id.wg_s_bar,
            "setBackgroundColor",
            if (today.hasShift) today.color else context.getColor(
                if (dark) R.color.wg_empty_dark else R.color.wg_empty_light
            ),
        )

        v.setInt(R.id.wg_s_divider, "setBackgroundColor", divider)

        // 明天预告。今天已是窗口最后一天时（不可能 —— 窗口 14 天）留空。
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
