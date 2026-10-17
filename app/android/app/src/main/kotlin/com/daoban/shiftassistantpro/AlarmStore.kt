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
        /**
         * 时刻表驱动（`repeatType == 3`，重复待办）时后面还跟着的几次点火时刻
         * （升序）。空 = 一次性或按星期重算的普通闹钟。
         */
        val repeatTimes: List<Long> = emptyList(),
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
        /**
         * 与 [Entry.repeatTimes] 同理：重复待办的提醒靠它续排，空 = 一次性。
         *
         * **必须有它，否则重启之后重复待办就只剩那一次** —— AlarmManager 的记录
         * 重启即清空，而 BootReceiver 只能照这份清单排回去。
         */
        val repeatTimes: List<Long> = emptyList(),
    )

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // ---------- 内存镜像（**只镜像「读」这一半，写仍是写穿**）----------
    //
    // `put` 原先是「读全表 → 解析 → 全量序列化 → 全量写回」，**一条一次**。而
    // `AlarmScheduler.schedule` 每排一条闹钟就调它一次 —— 一次 `rescheduleAll`
    // 是几十条（用户库实测 29 条班次闹钟 + 8 条待办），于是整份 JSON 被解析几十遍，
    // 是实打实的 O(n²)。
    //
    // 这里只治**解析**那一半：`all()` 之后把解析结果留在内存里，后续的读与改都在它
    // 上面做，不再反复解析。**写仍然每条都落** —— 详见下面那条裁定。
    //
    // ⚠️ **曾经试过「攒一段静默期合并写一次」，被最终审查否掉了**，两个理由，都是真的：
    //   ① **竞态**：延迟那一发跑在主线程的 `Handler` 上、**不在任何锁里**，而
    //      `clear` / `clearEntries` / `clearQuiets` 是从**后台线程**调的
    //      （`MainActivity` 的 `cancelAllNativeAlarms` / `cancelTodoReminders` 都是
    //      `Thread{…}.start()`）。两边一起动 `cachedEntries` 与同一个 prefs 键，
    //      后果是丢更新、或者**把刚清掉的清单又写回去** —— 而症状是「重启之后冒出
    //      一条幽灵闹钟」，正是这一层要防的事。
    //   ② **丢失窗口比看上去大**：`reschedule` 开头就是 `cancelAllNativeAlarms` →
    //      `clear()`（同步把键删掉），那一刻**盘上是空的**，而新的那一批要等静默期
    //      才落 —— 这窗口里进程被杀，重启之后 `BootReceiver` 一条都排不回来。
    //      写穿的话这个窗口不存在：每写一条盘上就有一条。
    //
    // 写穿的代价是 O(n) 的序列化（每次几 KB JSON），而不是 O(n²) 的解析 + 序列化 ——
    // 真机实测（探针）：这一层从 **16ms** 降到 **~7ms**，仍然是一次重排里可以忽略的一笔。



    /** 内存镜像。`null` = 还没读过。**所有访问都在 `@Synchronized` 里**。 */
    private var cachedEntries: MutableList<Entry>? = null
    private var cachedQuiets: MutableList<Quiet>? = null

    /** 全量读。解析不出来的记录直接跳过 —— 一条坏数据不该让整份清单失效。 */
    @Synchronized
    fun all(context: Context): List<Entry> {
        cachedEntries?.let { return it }
        val raw = prefs(context).getString(KEY, null)
        val parsed: List<Entry> = if (raw == null) {
            emptyList()
        } else {
            try {
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
                        repeatTimes = _readRepeatTimes(o),
                    )
                }
            } catch (e: Exception) {
                AlarmLog.error(context, "AlarmStore.all 解析失败，按空清单处理: ${e.message}")
                emptyList()
            }
        }
        val box = parsed.toMutableList()
        cachedEntries = box
        return box
    }

    /** 写入 / 覆盖一条（同一个 id 只有一条待触发记录，与 AlarmScheduler 的约定一致）。 */
    @Synchronized
    fun put(context: Context, e: Entry) {
        try {
            // 写穿：`write` 会同步更新镜像，所以下一次 `all()` 不必再解析
            // （镜像那一半的收益全在这里，落盘仍然是每条都落）。
            write(context, all(context).filterNot { it.id == e.id } + e)
        } catch (ex: Exception) {
            AlarmLog.error(context, "AlarmStore.put 失败: ${ex.message}")
        }
    }

    @Synchronized
    fun remove(context: Context, id: Int) {
        try {
            // 删除是低频单发，不等静默期，立刻落盘（`write` 会同步更新镜像）。
            write(context, all(context).filterNot { it.id == id })
        } catch (ex: Exception) {
            AlarmLog.error(context, "AlarmStore.remove 失败: ${ex.message}")
        }
    }

    @Synchronized
    fun clear(context: Context) {
        try {
            cachedEntries = null
            prefs(context).edit().remove(KEY).apply()
        } catch (ex: Exception) {
            AlarmLog.error(context, "AlarmStore.clear 失败: ${ex.message}")
        }
    }

    /**
     * 按 id 区间清闹钟清单。
     *
     * `AlarmScheduler.cancelTodoReminders` 收尾用：那一趟把待办那两段里的提醒都
     * 取消了（含响铃那条链路写在 [Entry] 里的），清单也得跟着清 —— 只清安静的
     * 那一份，下次重启 BootReceiver 会照 [Entry] 把已经取消的闹钟排回来。
     */
    @Synchronized
    fun clearEntries(context: Context, from: Int, to: Int) {
        try {
            write(context, all(context).filterNot { it.id in from until to })
        } catch (ex: Exception) {
            AlarmLog.error(context, "AlarmStore.clearEntries 失败: ${ex.message}")
        }
    }

    // ---------- 安静提醒（待办提醒那条链路）----------
    //
    // 与闹钟是**两份独立的清单**：id 段不重叠（闹钟 0..600 / 10000..11000，
    // 待办提醒 20000..21999、重复待办 40000..41999），取消路径也各走各的 ——
    // 合成一份反而要在每次取消时判断类型，正是容易漏删的地方。
    //
    // 但**待办那两段横跨两份清单**：同一条待办按「联动闹钟」开关二选一，开的那条
    // 写在 [Entry] 里、关的那条写在 [Quiet] 里。所以 `cancelTodoReminders` 两份
    // 都要查、都要清。

    @Synchronized
    fun allQuiets(context: Context): List<Quiet> {
        cachedQuiets?.let { return it }
        val raw = prefs(context).getString(KEY_QUIET, null)
        val parsed: List<Quiet> = if (raw == null) {
            emptyList()
        } else {
            try {
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
                        repeatTimes = _readRepeatTimes(o),
                    )
                }
            } catch (e: Exception) {
                AlarmLog.error(context, "AlarmStore.allQuiets 解析失败，按空清单处理: ${e.message}")
                emptyList()
            }
        }
        val box = parsed.toMutableList()
        cachedQuiets = box
        return box
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
        cachedEntries = list.toMutableList()
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
                    put("repeatTimes", _toJson(e.repeatTimes))
                }
            )
        }
        // apply() 而不是 commit()：取消是在主线程上做的，落盘晚几毫秒没关系；
        // 但**开机广播之后**必须已经落盘 —— 那是几个小时以后的事，够。
        prefs(context).edit().putString(KEY, arr.toString()).apply()
    }

    private fun writeQuiets(context: Context, list: List<Quiet>) {
        cachedQuiets = list.toMutableList()
        val arr = JSONArray()
        for (q in list) {
            arr.put(
                JSONObject().apply {
                    put("id", q.id)
                    put("millis", q.millis)
                    put("title", q.title)
                    put("body", q.body)
                    put("repeatTimes", _toJson(q.repeatTimes))
                }
            )
        }
        prefs(context).edit().putString(KEY_QUIET, arr.toString()).apply()
    }

    /** 时刻表 → JSON 数组（空表也写一个空数组，读的时候不必判 null）。 */
    private fun _toJson(times: List<Long>): JSONArray =
        JSONArray().apply { times.forEach { put(it) } }

    /**
     * 读回时刻表。**只留正数**：0 / 负数不是合法时刻（`millis` 缺失时
     * `optLong` 会回 0），留着会让 `nextPending` 把它当成一个「很久以前」的
     * 候选，无害但脏。
     */
    private fun _readRepeatTimes(o: JSONObject): List<Long> {
        val arr = o.optJSONArray("repeatTimes") ?: return emptyList()
        return (0 until arr.length())
            .map { arr.optLong(it, 0L) }
            .filter { it > 0L }
    }
}
