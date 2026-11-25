package com.daoban.shiftassistantpro

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 闹钟巡检：每 6 小时照落盘清单把 AlarmManager 重建一遍。
 *
 * **为什么需要它**：`setAlarmClock` 只在系统**愿意**保留的时候有效。三星的
 * 「休眠应用 / 深度休眠应用」会把 App 已排的闹钟**整条取消**，国产 ROM 的清理
 * 也有类似行为 —— 症状正是「几天偶尔漏响一次」，用户不去翻设置根本查不出来。
 * 巡检把丢掉的排回来，最坏也就晚 6 小时恢复，而不是一路哑到下次打开 App。
 *
 * 三条设计约束：
 *  - **非精确**（`setAndAllowWhileIdle`）：巡检不需要准点，精确闹钟那份额度留给
 *    真正的闹钟。Doze 下它会被推后，但那也够了。
 *  - **自续排**：每次响完再排下一次，不一次排一堆；进程被杀也不影响（闹钟记在
 *    系统里，到点会把进程拉起来）。
 *  - **只补排、不新增**：重建的是清单里已有的条目，不改变任何规则 —— 规则全在
 *    Dart 侧（排班 / 重复待办）算好。
 *
 * ⚠️ PendingIntent 带了**自己的 action**：`MainActivity.cancelAllNativeAlarms`
 * 那类「无 action」的盲扫因此碰不到它（`filterEquals` 不同）。一次性历史清扫
 * 跑完不会把巡检一起取消。
 */
object AlarmWatchdog {

    const val ACTION = "com.daoban.shiftassistantpro.ALARM_WATCHDOG"

    /** 请求码。与 `WidgetRefreshScheduler.REQ(40081)`、`REQ_PICK_RINGTONE(40071)` 错开。 */
    private const val REQ = 40091

    /** 巡检间隔。6 小时：一晚最多两次，够在下一次闹钟之前把丢掉的补回来。 */
    const val INTERVAL_MS = 6L * 60 * 60 * 1000

    /**
     * **最早那条闹钟之前 1 小时也要巡检一次**（v0.13.22）。
     *
     * 只靠 6 小时一轮是不够的：用户报「某条闹钟没响」的时间点几乎总在「他手动打开
     * App 之后 0.5~2 小时」（2026-11-25 一加用户 08:18 开、10:00 丢；11-24 15:27
     * 开、16:00 丢）。而每次重排都会把巡检推到 now+6h，那一段正好没有任何自愈机会。
     * 提前一小时跑，等于在每条闹钟前面站一班岗 —— 被厂商整条撤销的，当场补排回去。
     */
    private const val LEAD_MS = 60L * 60 * 1000

    /** 两次巡检至少隔这么久：闹钟挨得很近时别每 10 分钟重排几百条。 */
    private const val MIN_GAP_MS = 10L * 60 * 1000

    /**
     * 已经排出去的那一次巡检落在什么时候。
     *
     * 系统没有「读一条闹钟定的几点」的公开接口，所以只能自己记 —— `setAndAllowWhileIdle`
     * 用的是同一个 PendingIntent，再调一次就是**覆盖成更晚的时刻**，从前的 `ensureScheduled`
     * 正是这么把 09:12 挤成 14:18 的（`docs/decisions/alarm.md`）。
     */
    private const val PREFS = "alarm_watchdog"
    private const val KEY_AT = "next_at"

    /** 每次重排收尾都调：**只往前挪，不往后推**。 */
    fun ensureScheduled(context: Context) =
        scheduleAhead(context, System.currentTimeMillis(), force = false)

    /**
     * 重启 / 应用被更新之后用：`AlarmManager` 里的记录已经全清空，落盘的那个时刻
     * 不再可信，必须无条件重排一次。
     */
    fun forceScheduled(context: Context) =
        scheduleAhead(context, System.currentTimeMillis(), force = true)

    /**
     * 下一次巡检该落在什么时候：`min(now + 6h, 最早那条闹钟 - 1h)`，且不早于
     * `now + 10min`。
     *
     * **「不早于 10 分钟」这一条是防自激的**：巡检自己排到 T-1h 之后，那一刻
     * `next - LEAD` 已经等于刚才，若照算就会再排一次 T-10min、T-20min …… 一直
     * 空转到那条闹钟真的响。加了这道下限，边界上自然落回 `now + 6h`。
     */
    fun nextTarget(context: Context, now: Long): Long {
        val base = now + INTERVAL_MS
        val next = AlarmStore.all(context)
            .filter { it.millis > now }
            .minByOrNull { it.millis }?.millis
        val lead = if (next != null && next - LEAD_MS >= now + MIN_GAP_MS) {
            next - LEAD_MS
        } else {
            Long.MAX_VALUE
        }
        return minOf(base, lead)
    }

    private fun scheduledAt(context: Context): Long = try {
        prefs(context).getLong(KEY_AT, 0L)
    } catch (_: Exception) {
        0L
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun scheduleAhead(context: Context, now: Long, force: Boolean) {
        val target = nextTarget(context, now)
        val pending = scheduledAt(context)
        // **不许把已经排好的、更早的那一次推后**：这正是 03:12 排的 09:12 被
        // 08:00/08:18 两次重排挤到 14:18 的原因（10:00 那条因此没有自愈机会）。
        if (!force && pending > now && pending <= target) return
        schedule(context, target)
    }

    fun schedule(context: Context, atMs: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = PendingIntent.getBroadcast(
            context,
            REQ,
            Intent(context, AlarmWatchdogReceiver::class.java).setAction(ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        var ok = false
        try {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
            ok = true
        } catch (e: Exception) {
            // 权限中途被收回等：绝不让它冒出去。再退一档，用不保证唤醒的 set()。
            try {
                am.set(AlarmManager.RTC_WAKEUP, atMs, pi)
                ok = true
                AlarmLog.info(context, "AlarmWatchdog: 退化为 set() at=$atMs")
            } catch (e2: Exception) {
                AlarmLog.error(context, "AlarmWatchdog: 排定失败 ${e2.message}")
            }
        }
        // **排成功才记账**：排失败还记下来，后面的 `ensureScheduled` 会以为「已经有
        // 更早的一次」而不再重试 —— 那等于把巡检彻底关掉。
        if (ok) {
            try {
                prefs(context).edit().putLong(KEY_AT, atMs).apply()
            } catch (_: Exception) {
            }
        }
    }
}

/**
 * 巡检的落点。重建可能要几百毫秒（几百条 `setAlarmClock`），所以走
 * `goAsync()` + 工作线程 —— broadcast 的 10 秒上限里绰绰有余，也不占主线程。
 */
class AlarmWatchdogReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Thread {
            try {
                val r = AlarmRestorer.restore(context, System.currentTimeMillis())
                AlarmLog.diagnostic(
                    context,
                    "AlarmWatchdog: 巡检补排 ${r.alarms} 铃 / ${r.quiets} 静，" +
                        "下一跳 ${AlarmScheduler.nextDigest(context, System.currentTimeMillis())}"
                )
            } catch (e: Exception) {
                AlarmLog.error(
                    context,
                    "AlarmWatchdog: 巡检失败 ${e.javaClass.simpleName}: ${e.message}"
                )
            } finally {
                // 先排下一次再收工：中途抛异常也不会让巡检断掉。
                AlarmWatchdog.ensureScheduled(context)
                pending.finish()
            }
        }.start()
    }
}
