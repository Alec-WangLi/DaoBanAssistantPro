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
        val abbrInk: Int,
        /** 已是完整显示串（含「次日」/「(next day)」等语序）；无时间时为 null。 */
        val timeRange: String?,
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
        /** 主色 ARGB。**大卡「今天」那格的日期色** —— 见 `WidgetRenderer.large()`。 */
        val accent: Int,
        val hasSchedule: Boolean,
        val emptyHint: String,
        val today: String,
        val tomorrow: String,
        val dayAfter: String,
        val boundaries: List<Long>,
        val days: List<Day>,
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
        if (o.optInt("v", -1) != 1) return null

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
                abbrInk = d.optInt("abbrInk", 0),
                // ⚠️ 不能写 `d.optString("timeRange", "").ifEmpty { null }`：
                // `optString(name, fallback)` 只在**键不存在**时才给 fallback；
                // 键存在而值是 JSON `null` 时，它走 `JSON.toString(JSONObject.NULL)`
                // 返回**四字符串 `"null"`**，`.ifEmpty` 不会触发。而 Dart 侧每个
                // 休班日发的正是 JSON null —— 那样卡片上会印出字面的 `null`。
                // AOSP 是刻意与参考实现逐 bug 兼容的（issue 13830），别改成
                // 「更干净」的 fallback 写法。
                timeRange = if (d.isNull("timeRange")) null else d.optString("timeRange"),
            )
        }
        if (days.isEmpty()) return null

        val bArr = o.optJSONArray("boundaries") ?: JSONArray()
        val boundaries = (0 until bArr.length()).map { bArr.optLong(it, 0L) }
            .filter { it > 0L }

        return Snapshot(
            themeMode = o.optString("themeMode", "system"),
            accent = o.optInt("accent", 0),
            hasSchedule = o.optBoolean("hasSchedule", false),
            emptyHint = o.optString("emptyHint", ""),
            today = labels.optString("today", ""),
            tomorrow = labels.optString("tomorrow", ""),
            dayAfter = labels.optString("dayAfter", ""),
            boundaries = boundaries,
            days = days,
        )
    }
}
