package com.daoban.shiftassistantpro

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * 已排定闹钟 / 提醒的落盘清单 —— 开机重排的唯一依据。
 *
 * 为什么需要它：`AlarmManager` 排的记录**重启即清空**（`setAlarmClock` 与
 * `setExactAndAllowWhileIdle` 都一样），而在此之前只有「打开一次 App」会重排
 * （Dart 侧的 `reschedule`）。也就是说手机重启之后、用户下次打开 App 之前，
 * 所有闹钟与提醒都是哑的。系统的开机广播只告诉你「重启了」，不会告诉你
 * 「重启前排过什么」—— 那份清单必须自己留着。
 *
 * 两份清单，各管一条链路：
 *  - [Entry]（KEY）—— 响铃闹钟（`AlarmScheduler.schedule`）
 *  - [Quiet]（KEY_QUIET）—— 安静提醒（`AlarmScheduler.scheduleQuiet`）
 *
 * 存的是**排定参数**而不是「下次该响的时刻」：重复闹钟开机后要按
 * `nextDaily` / `nextWeekly` 重算下一次，存时刻只会存出一条已经过期的记录。
 *
 * 最容易写错的一处：**每条取消路径都必须同步删**。漏掉一处就留下一条「幽灵
 * 闹钟」—— 界面上看不出来，直到某天重启后它自己响了。
 */
object AlarmStore {
    private const val PREFS = "alarm_store"
    private const val KEY = "entries"
    private const val KEY_QUIET = "quiets"

    /** 一条已排定闹钟的全部参数，够 `AlarmScheduler.schedule` 原样再排一次。 */
    data class Entry(
        val id: Int,
        val millis: Long,
        val label: String,
        val uri: String?,
        val repeatType: Int,
        val hour: Int,
        val minute: Int,
        val weekdays: Int,
        val detail: String?,
    )

    /**
     * 一条已排定的「安静提醒」（待办提醒那条链路，`AlarmScheduler.scheduleQuiet`）。
     *
     * 字段比闹钟少：它只发一条普通通知，不响铃、不重复，所以没有重复类型 / 铃声 /
     * 星期掩码这些东西。
     */
    data class Quiet(
        val id: Int,
        val millis: Long,
        val title: String,
        val body: String,
    )

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** 全量读。解析不出来的记录直接跳过 —— 一条坏数据不该让整份清单失效。 */
    @Synchronized
    fun all(context: Context): List<Entry> {
        val raw = prefs(context).getString(KEY, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                val id = o.optInt("id", -1)
                val millis = o.optLong("millis", 0L)
                if (id < 0 || millis <= 0L) return@mapNotNull null
                Entry(
                    id = id,
                    millis = millis,
                    label = o.optString("label", "闹钟"),
                    uri = o.optString("uri", "").ifEmpty { null },
                    repeatType = o.optInt("repeatType", 0),
                    hour = o.optInt("hour", 0),
                    minute = o.optInt("minute", 0),
                    weekdays = o.optInt("weekdays", 0),
                    detail = o.optString("detail", "").ifEmpty { null },
                )
            }
        } catch (e: Exception) {
            AlarmLog.error(context, "AlarmStore.all 解析失败，按空清单处理: ${e.message}")
            emptyList()
        }
    }

    /** 写入 / 覆盖一条（同一个 id 只有一条待触发记录，与 AlarmScheduler 的约定一致）。 */
    @Synchronized
    fun put(context: Context, e: Entry) {
        try {
            val list = all(context).filterNot { it.id == e.id } + e
            write(context, list)
        } catch (ex: Exception) {
            AlarmLog.error(context, "AlarmStore.put 失败: ${ex.message}")
        }
    }

    @Synchronized
    fun remove(context: Context, id: Int) {
        try {
            write(context, all(context).filterNot { it.id == id })
        } catch (ex: Exception) {
            AlarmLog.error(context, "AlarmStore.remove 失败: ${ex.message}")
        }
    }

    @Synchronized
    fun clear(context: Context) {
        try {
            prefs(context).edit().remove(KEY).apply()
        } catch (ex: Exception) {
            AlarmLog.error(context, "AlarmStore.clear 失败: ${ex.message}")
        }
    }

    // ---------- 安静提醒（待办提醒那条链路）----------
    //
    // 与闹钟是**两份独立的清单**：id 段不重叠（闹钟 0..400 / 10000..11000，
    // 待办提醒 20000..21000），取消路径也各走各的 —— 合成一份反而要在每次取消时
    // 判断类型，正是容易漏删的地方。

    @Synchronized
    fun allQuiets(context: Context): List<Quiet> {
        val raw = prefs(context).getString(KEY_QUIET, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                val id = o.optInt("id", -1)
                val millis = o.optLong("millis", 0L)
                if (id < 0 || millis <= 0L) return@mapNotNull null
                Quiet(
                    id = id,
                    millis = millis,
                    title = o.optString("title", ""),
                    body = o.optString("body", ""),
                )
            }
        } catch (e: Exception) {
            AlarmLog.error(context, "AlarmStore.allQuiets 解析失败，按空清单处理: ${e.message}")
            emptyList()
        }
    }

    @Synchronized
    fun putQuiet(context: Context, q: Quiet) {
        try {
            writeQuiets(context, allQuiets(context).filterNot { it.id == q.id } + q)
        } catch (ex: Exception) {
            AlarmLog.error(context, "AlarmStore.putQuiet 失败: ${ex.message}")
        }
    }

    @Synchronized
    fun removeQuiet(context: Context, id: Int) {
        try {
            writeQuiets(context, allQuiets(context).filterNot { it.id == id })
        } catch (ex: Exception) {
            AlarmLog.error(context, "AlarmStore.removeQuiet 失败: ${ex.message}")
        }
    }

    /** 按 id 区间清（`AlarmScheduler.cancelTodoReminders` 扫的那一段）。 */
    @Synchronized
    fun clearQuiets(context: Context, from: Int, to: Int) {
        try {
            writeQuiets(context, allQuiets(context).filterNot { it.id in from until to })
        } catch (ex: Exception) {
            AlarmLog.error(context, "AlarmStore.clearQuiets 失败: ${ex.message}")
        }
    }

    private fun write(context: Context, list: List<Entry>) {
        val arr = JSONArray()
        for (e in list) {
            arr.put(
                JSONObject().apply {
                    put("id", e.id)
                    put("millis", e.millis)
                    put("label", e.label)
                    put("uri", e.uri ?: "")
                    put("repeatType", e.repeatType)
                    put("hour", e.hour)
                    put("minute", e.minute)
                    put("weekdays", e.weekdays)
                    put("detail", e.detail ?: "")
                }
            )
        }
        // apply() 而不是 commit()：取消是在主线程上做的，落盘晚几毫秒没关系；
        // 但**开机广播之后**必须已经落盘 —— 那是几个小时以后的事，够。
        prefs(context).edit().putString(KEY, arr.toString()).apply()
    }

    private fun writeQuiets(context: Context, list: List<Quiet>) {
        val arr = JSONArray()
        for (q in list) {
            arr.put(
                JSONObject().apply {
                    put("id", q.id)
                    put("millis", q.millis)
                    put("title", q.title)
                    put("body", q.body)
                }
            )
        }
        prefs(context).edit().putString(KEY_QUIET, arr.toString()).apply()
    }
}
