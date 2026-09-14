package com.daoban.shiftassistantpro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 开机重排：把重启前留下的闹钟清单重新排进 AlarmManager。
 *
 * 没有它的话，「重启后闹钟会丢」—— `setAlarmClock` 的记录重启即清空，而重排此前
 * 只发生在打开 App 的时候（Dart 侧 `reschedule`）。
 *
 * 三种情况的处理不一样，别混：
 *
 *  - **每天 / 每周**：按 `nextDaily` / `nextWeekly` 重算下一次 —— 直接把旧时刻排
 *    回去会排出一条已经过期的记录（`setAlarmClock` 对过去的时刻会立即触发）。
 *  - **一次性、还没到点**：原时刻排回去。
 *  - **一次性、关机期间已经错过**：从清单里删掉，**不在开机瞬间补响** —— 半夜的
 *    闹钟在早上开机时突然响，比不响更糟。
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
        val entries = AlarmStore.all(context)
        AlarmLog.info(
            context,
            "BootReceiver.onReceive: action=${intent.action}，清单 ${entries.size} 条"
        )

        var rescheduled = 0
        for (e in entries) {
            val next = when (e.repeatType) {
                1 -> AlarmScheduler.nextDaily(now, e.hour, e.minute)

                2 -> {
                    if (e.weekdays == 0) {
                        // 没有星期掩码的「每周」是条坏数据，删掉而不是排成明天
                        AlarmStore.remove(context, e.id)
                        continue
                    }
                    AlarmScheduler.nextWeekly(now, e.weekdays, e.hour, e.minute)
                }

                else -> {
                    if (e.millis <= now) {
                        AlarmStore.remove(context, e.id)
                        continue
                    }
                    e.millis
                }
            }
            try {
                AlarmScheduler.schedule(
                    context, e.id, next, e.label, e.uri,
                    e.repeatType, e.hour, e.minute, e.weekdays, e.detail
                )
                rescheduled++
            } catch (ex: Exception) {
                AlarmLog.error(
                    context,
                    "BootReceiver: 重排 id=${e.id} 失败: ${ex.javaClass.name}: ${ex.message}"
                )
            }
        }
        AlarmLog.info(context, "BootReceiver: 重排完成，$rescheduled 条")
    }
}
