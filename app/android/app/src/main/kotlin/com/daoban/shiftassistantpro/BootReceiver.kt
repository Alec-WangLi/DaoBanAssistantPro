package com.daoban.shiftassistantpro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 开机重排：把重启前留下的闹钟与提醒重新排进 AlarmManager。
 *
 * 没有它的话，「重启后闹钟会丢」—— `AlarmManager` 的记录重启即清空（`setAlarmClock`
 * 与 `setExactAndAllowWhileIdle` 都一样），而重排此前只发生在打开 App 的时候
 * （Dart 侧 `reconcileNative`）。
 *
 * **重排规则本身在 [AlarmRestorer] 里**，与 6 小时一次的巡检（[AlarmWatchdog]）
 * 共用同一份实现 —— 两处各写一遍必然分岔，而分岔的症状是「某天没响」这种不报错的。
 *
 * 权限：只需要 `RECEIVE_BOOT_COMPLETED`（manifest 里已有，不用新增）。小米机型上
 * 还要用户开「自启动」，否则 MIUI 可能压根不把这个广播发给 App。
 *
 * 已知边界：设备设了锁屏密码时，`BOOT_COMPLETED` 通常要等**首次解锁之后**才会送到
 * 非 Direct Boot 应用。也就是「半夜重启、此后一直没解锁」这一段里闹钟仍是哑的；
 * 要覆盖它得让存储与接收器都走 Direct Boot，改动更大，先不做。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val now = System.currentTimeMillis()
        AlarmLog.diagnostic(
            context,
            "BootReceiver.onReceive: action=${intent.action}，" +
                "清单 ${AlarmStore.all(context).size} 铃 / " +
                "${AlarmStore.allQuiets(context).size} 静"
        )
        try {
            val r = AlarmRestorer.restore(context, now)
            AlarmLog.diagnostic(
                context,
                "BootReceiver: 重排完成，补排 ${r.alarms} 铃 / ${r.quiets} 静，" +
                    "下一跳 ${AlarmScheduler.nextDigest(context, now)}"
            )
        } catch (e: Exception) {
            AlarmLog.error(
                context,
                "BootReceiver: 重排失败 ${e.javaClass.simpleName}: ${e.message}"
            )
        }

        // 巡检也要排上：重启之后它是「系统 / 厂商把闹钟整条丢掉」这条路上唯一的兜底。
        AlarmWatchdog.ensureScheduled(context)

        // 小组件的刷新闹钟也重启即清空，同样要排回去。与上面两条链路的区别是：
        // 它没有「清单」可读 —— 边界时刻就在快照里，`scheduleNextRefreshIfNeeded`
        // 自己会挑第一个未来的。所以这里只是「叫醒它一次」。
        try {
            ShiftWidgets.scheduleNextRefreshIfNeeded(context)
        } catch (e: Exception) {
            AlarmLog.error(context, "BootReceiver: 小组件刷新重排失败: ${e.message}")
        }
    }
}
