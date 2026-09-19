package com.daoban.shiftassistantpro

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate

/**
 * 桌面小组件快照的落盘与读取 —— [AlarmStore] 的同族。
 *
 * 存的是 Dart 侧算好的**一整份 JSON 串**（见 `lib/features/widget/widget_snapshot.dart`），
 * 原生只负责原样落盘、按需解析。为什么不让原生直接读 Drift 的 SQLite：那要耦合
 * 一份由 `build_runner` 生成的表结构，且要在 Kotlin 里重写一遍轮转引擎 —— 两份引擎
 * 就是两个 bug 源。
 *
 * 解析失败一律按「无快照」处理（渲染成占位态），不抛。一条坏数据不该让整张卡片消失。
 */
object WidgetStore {
    private const val PREFS = "shift_widget"
    private const val KEY = "snapshot"

    /** 一天。字段与 Dart 侧 `buildWidgetSnapshot` 的 `days[i]` 一一对应。 */
    data class Day(
        val day: Long,
        val weekday: String,
        val dateShort: String,
        val hasShift: Boolean,
        val isRest: Boolean,
        val shiftName: String,
        val shiftAbbr: String,
        val color: Int,
        /** 已是完整显示串（含「次日」/「(next day)」等语序）；无时间时为 null。 */
        val timeRange: String?,
        /**
         * 月历格子的第三行（农历短标签，如「初八」）。
         *
         * 原生不查农历（那是 Dart 侧的事），所以它**按日期烘焙** —— 与
         * [dateShort] / [weekday] 同类，跨天对表右移时跟着那一天走，不会腐坏。
         */
        val lunarShort: String,
        /** 这一天的农历是否落在法定节假日（Dart 侧 `LunarInfo.isLegalHoliday`）。 */
        val lunarIsHoliday: Boolean,
    )

    /** 窗口覆盖到的某个月的标题（「2026年9月」/「September 2026」）。 */
    data class MonthTitle(val y: Int, val m: Int, val title: String)

    /** 今日卡片里的一条「其他班组」。 */
    data class Crew(
        val name: String,
        val abbr: String,
        val color: Int,
    )

    /**
     * 今日卡片的详情。
     *
     * ⚠️ [day] 是**生成那天**的 epochDay。农历、待办数、其他班组都是那天的 ——
     * 跨天之后这份数据就过期了，渲染前必须拿它跟 `LocalDate.now().toEpochDay()`
     * 比一下：对不上就走降级态（农历与其他班组留空，只用 `days[todayIndex]` 里
     * 那份按日期烘焙的数据）。**绝不能把旧数据当成今天显示。**
     */
    data class TodayCard(
        val day: Long,
        val lunarShort: String,
        val lunarIsHoliday: Boolean,
        /**
         * 完整农历描述（「农历 丙午年 八月初八 · 生肖马 · 日干壬辰 · 国际民主日」）。
         *
         * 4×3 比原来的紧凑档高出约 95dp，多出来的地方放**真内容**而不是把行距摊开 ——
         * 这句就是那份内容（App 的完整版信息卡用的也是它）。
         */
        val lunarFull: String,
        val adjusted: Boolean,
        /**
         * 今日未完成待办数。**仅供线上协议 / 诊断，界面不用它** —— 徽章画的是
         * [todoBadge]（Dart 侧给的完整文字）。解析它是为了协议字段对齐与日志排查，
         * 不要以为它驱动着什么。
         */
        val todoCount: Int,
        /**
         * 「N 项待办」徽章上的**文字**，由 Dart 侧 `L10n.todoCount` 产出；没有待办时
         * 为 null（原生据此整块隐藏徽章）。原生不许有中文字面量，而这个串是双语的。
         */
        val todoBadge: String?,
        val crews: List<Crew>,
    )

    /**
     * 一份完整的快照。
     *
     * [themeMode] 是 `"system" | "light" | "dark"` —— **模式，不是解析结果**。
     * `system` 由 [WidgetRenderer.isDark] 在渲染时读宿主配置现算，这样「跟随系统」
     * 永远是新鲜的。
     */
    data class Snapshot(
        val themeMode: String,
        /**
         * 主色 ARGB。三张卡里「今天」都用它：本周条的周几/日数字、月历的日数字、
         * 今日卡那个「今天」徽章 —— 见 `WidgetRenderer.weekStrip` / `monthCard` /
         * `renderTodayCard`。
         *
         * （原文指向的 `WidgetRenderer.large()` 是旧版式里的大卡函数，随五档一起删了。）
         */
        val accent: Int,
        val hasSchedule: Boolean,
        val emptyHint: String,
        /**
         * 「今天 / 明天 / 后天」三个相对文案（顶层 `labels`）。
         *
         * **本轮三张卡都不消费它们**：本周条用周几、今日卡用绝对日期、月历用日数字。
         * 保留是有意的 —— Dart 侧仍在发，将来要用不必改协议。别当成漏接的字段。
         */
        val today: String,
        val tomorrow: String,
        val dayAfter: String,
        /** 「已调班」徽章的文字（顶层 `labels.adjusted`）。原生不许有中文字面量。 */
        val adjustedBadge: String,
        val boundaries: List<Long>,
        val days: List<Day>,
        /** 七条周几文案（索引 0 = 周一）。月历表头行用 —— 原生不许有中文字面量。 */
        val weekdays: List<String>,
        /**
         * 窗口覆盖到的月份标题，升序。
         *
         * ⚠️ 月历渲染的是**今天所在的月**，而这份快照可能生成于上个月（跨天右移）。
         * 找不到对应月份时**隐藏标题行**，绝不借相邻月份的标题顶上 ——
         * 那是本仓「不让卡片理直气壮地写错」那条纪律的又一入口。
         */
        val months: List<MonthTitle>,
        val todayCard: TodayCard?,
    ) {
        /** 今天在 [days] 里的下标；快照过期（对不上）时返回 -1。 */
        fun indexOfToday(): Int {
            val t = LocalDate.now().toEpochDay()
            return days.indexOfFirst { it.day == t }
        }
    }

    @Synchronized
    fun write(context: Context, json: String) {
        try {
            prefs(context).edit().putString(KEY, json).apply()
        } catch (e: Exception) {
            AlarmLog.error(context, "WidgetStore.write 失败: ${e.message}")
        }
    }

    /** 读并解析；没有 / 版本对不上 / 解析失败都返回 null（调用方走降级态）。 */
    @Synchronized
    fun snapshot(context: Context): Snapshot? {
        val raw = try {
            prefs(context).getString(KEY, null)
        } catch (e: Exception) {
            AlarmLog.error(context, "WidgetStore.read 失败: ${e.message}")
            null
        } ?: return null

        return try {
            parse(raw)
        } catch (e: Exception) {
            AlarmLog.error(context, "WidgetStore 解析失败，按无快照处理: ${e.message}")
            null
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** 抽成 internal 便于将来单测；现在只有 [snapshot] 一个调用方。 */
    internal fun parse(raw: String): Snapshot? {
        val o = JSONObject(raw)
        // 版本对不上就当作看不懂 —— 比按老结构硬解出半份错数据强。
        if (o.optInt("v", -1) != 2) return null

        val labels = o.optJSONObject("labels") ?: JSONObject()
        val arr = o.optJSONArray("days") ?: JSONArray()
        val days = (0 until arr.length()).mapNotNull { i ->
            val d = arr.optJSONObject(i) ?: return@mapNotNull null
            Day(
                day = d.optLong("day", -1L),
                weekday = d.optString("weekday", ""),
                dateShort = d.optString("dateShort", ""),
                hasShift = d.optBoolean("hasShift", false),
                isRest = d.optBoolean("isRest", true),
                shiftName = d.optString("shiftName", ""),
                shiftAbbr = d.optString("shiftAbbr", ""),
                color = d.optInt("color", 0),
                // ⚠️ 不能写 `d.optString("timeRange", "").ifEmpty { null }`：
                // `optString(name, fallback)` 只在**键不存在**时才给 fallback；
                // 键存在而值是 JSON `null` 时，它走 `JSON.toString(JSONObject.NULL)`
                // 返回**四字符串 `"null"`**，`.ifEmpty` 不会触发。而 Dart 侧每个
                // 休班日发的正是 JSON null —— 那样卡片上会印出字面的 `null`。
                // AOSP 是刻意与参考实现逐 bug 兼容的（issue 13830），别改成
                // 「更干净」的 fallback 写法。
                timeRange = if (d.isNull("timeRange")) null else d.optString("timeRange"),
                lunarShort = d.optString("lunarShort", ""),
                lunarIsHoliday = d.optBoolean("lunarIsHoliday", false),
            )
        }
        if (days.isEmpty()) return null

        val bArr = o.optJSONArray("boundaries") ?: JSONArray()
        val boundaries = (0 until bArr.length()).map { bArr.optLong(it, 0L) }
            .filter { it > 0L }

        val wdArr = o.optJSONArray("weekdays") ?: JSONArray()
        // ⚠️ **不要 `.filter { it.isNotEmpty() }`**：这份表是**按位置**用的
        // （`weekdays[i]` = 第 i 列），滤掉一条会让后面七条整体左移一格，
        // 七列表头**静默错一整列**。空了就让它空着占位 —— 空字符串照样渲染成一格空白，
        // 位置是对的。
        val weekdays = (0 until wdArr.length()).map { wdArr.optString(it, "") }

        val mArr = o.optJSONArray("months") ?: JSONArray()
        val months = (0 until mArr.length()).mapNotNull { i ->
            val m = mArr.optJSONObject(i) ?: return@mapNotNull null
            MonthTitle(
                y = m.optInt("y", 0),
                m = m.optInt("m", 0),
                title = m.optString("title", ""),
            )
        }

        // ⚠️ `optString(name, fallback)` 只在**键不存在**时才给 fallback；键存在而值是
        // JSON `null` 时它返回**四字符串 `"null"`**（Android 的 org.json 刻意与参考实现
        // 逐 bug 兼容，见 AOSP issue 13830）。Dart 侧有可空字段时一律先 isNull 判。
        val tcObj = o.optJSONObject("todayCard")
        val todayCard = tcObj?.let { t ->
            val crewArr = t.optJSONArray("crews") ?: JSONArray()
            TodayCard(
                day = t.optLong("day", -1L),
                lunarShort = t.optString("lunarShort", ""),
                lunarIsHoliday = t.optBoolean("lunarIsHoliday", false),
                lunarFull = t.optString("lunarFull", ""),
                adjusted = t.optBoolean("adjusted", false),
                todoCount = t.optInt("todoCount", 0),
                // 同 timeRange 那条：Dart 侧没有待办时发的正是 JSON `null`，
                // 不先 isNull 判就会印出字面的 `null`。
                todoBadge = if (t.isNull("todoBadge")) null else t.optString("todoBadge"),
                crews = (0 until crewArr.length()).mapNotNull { k ->
                    val c = crewArr.optJSONObject(k) ?: return@mapNotNull null
                    Crew(
                        name = c.optString("name", ""),
                        abbr = c.optString("abbr", ""),
                        color = c.optInt("color", 0),
                    )
                },
            )
        }

        return Snapshot(
            themeMode = o.optString("themeMode", "system"),
            accent = o.optInt("accent", 0),
            hasSchedule = o.optBoolean("hasSchedule", false),
            emptyHint = o.optString("emptyHint", ""),
            today = labels.optString("today", ""),
            tomorrow = labels.optString("tomorrow", ""),
            dayAfter = labels.optString("dayAfter", ""),
            adjustedBadge = labels.optString("adjusted", ""),
            boundaries = boundaries,
            days = days,
            weekdays = weekdays,
            months = months,
            todayCard = todayCard,
        )
    }
}
