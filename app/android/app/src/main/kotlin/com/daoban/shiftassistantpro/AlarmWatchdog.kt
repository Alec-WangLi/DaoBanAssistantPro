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

    fun ensureScheduled(context: Context) =
        schedule(context, System.currentTimeMillis() + INTERVAL_MS)

    fun schedule(context: Context, atMs: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = PendingIntent.getBroadcast(
            context,
            REQ,
            Intent(context, AlarmWatchdogReceiver::class.java).setAction(ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        try {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
        } catch (e: Exception) {
            // 权限中途被收回等：绝不让它冒出去。再退一档，用不保证唤醒的 set()。
            try {
                am.set(AlarmManager.RTC_WAKEUP, atMs, pi)
                AlarmLog.info(context, "AlarmWatchdog: 退化为 set() at=$atMs")
            } catch (e2: Exception) {
                AlarmLog.error(context, "AlarmWatchdog: 排定失败 ${e2.message}")
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
