package com.daoban.shiftassistantpro

import android.content.Context

/**
 * 按落盘清单把 AlarmManager 重建一遍。
 *
 * 两个入口，规则完全相同：
 *
 *  - [BootReceiver]：重启会清空 AlarmManager 里的一切；
 *  - [AlarmWatchdogReceiver]：系统 / 厂商可能把已排的闹钟**整条取消**（三星
 *    「休眠应用 / 深度休眠应用」就是这么干的，见 `docs/decisions/alarm.md`），
 *    靠巡检把它补回来 —— 不必等用户下次打开 App。
 *
 * 抽出来是为了**不再有第二份实现**。从前只有 BootReceiver 一份；巡检要自己抄一遍
 * 的话，「每天 / 每周要不要重算下一次」「关机期间错过的不补响」这两条规矩迟早
 * 分岔，而分岔的症状还是「某天没响」这种不报错的。
 *
 * 三条规则（与从前 BootReceiver 一字不差）：
 *  - **每天 / 每周**：按 `nextDaily` / `nextWeekly` 重算下一次 —— 直接把旧时刻排
 *    回去会排出一条已经过期的记录（`setAlarmClock` 对过去的时刻会立即触发）。
 *  - **一次性、还没到点**：原时刻排回去。
 *  - **一次性、已经错过**：从清单里删掉，**不补响** —— 半夜的闹钟在早上突然响，
 *    比不响更糟。
 */
object AlarmRestorer {

    data class Result(val alarms: Int, val quiets: Int)

    fun restore(context: Context, now: Long): Result {
        val am = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        val entries = AlarmStore.all(context)
        val keep = ArrayList<AlarmStore.Entry>(entries.size)
        var armed = 0
        for (e in entries) {
            var next: Long? = null
            var queue = LongArray(0)
            when (e.repeatType) {
                // 时刻表驱动（重复待办）：从「本次 + 后续队列」里挑第一个还没过的。
                // **必须与 AlarmReceiver 同一套规则**，否则重启一次就退回按星期重算。
                3 -> {
                    val pending = AlarmScheduler.nextPending(
                        e.millis, e.repeatTimes.toLongArray(), now
                    )
                    if (pending != null) {
                        next = pending.first
                        queue = pending.second
                    }
                }

                1 -> next = AlarmScheduler.nextDaily(now, e.hour, e.minute)

                2 -> if (e.weekdays != 0) {
                    // 没有星期掩码的「每周」是条坏数据，删掉而不是排成明天。
                    next = AlarmScheduler.nextWeekly(now, e.weekdays, e.hour, e.minute)
                }

                else -> if (e.millis > now) next = e.millis
            }
            if (next == null) continue
            try {
                keep.add(
                    AlarmScheduler.arm(
                        context, e.id, next, e.label, e.uri, e.repeatType,
                        e.hour, e.minute, e.weekdays, e.detail, queue
                    )
                )
                armed++
                // 同一 id 只留它该走的那条链路（换过「联动闹钟」开关的会留下另一侧）。
                AlarmScheduler.cancelOtherChannel(
                    context, am, e.id, AlarmReceiver::class.java
                )
            } catch (ex: Exception) {
                // **排失败也把条目留在清单里**，并把时刻更新成刚算出来的那一个：
                // 清单的语义是「应当存在的那一批」，下一次巡检 / 开机重排还会再试。
                // 从清单里抹掉等于把这条闹钟永久丢掉 —— 那是最不该发生的一种。
                keep.add(e.copy(millis = next, repeatTimes = queue.toList()))
                AlarmLog.error(
                    context,
                    "AlarmRestorer: 排定 id=${e.id} 失败: ${ex.javaClass.simpleName}: ${ex.message}"
                )
            }
        }
        // 一次落盘（整批语义）：没排上的那些（过期一次性 / 坏数据）就从清单里消失。
        AlarmStore.replaceAll(context, keep)

        val quiets = AlarmStore.allQuiets(context)
        val keepQuiets = ArrayList<AlarmStore.Quiet>(quiets.size)
        for (q in quiets) {
            val pending = AlarmScheduler.nextPending(
                q.millis, q.repeatTimes.toLongArray(), now
            ) ?: continue
            keepQuiets.add(
                AlarmScheduler.armQuiet(
                    context, q.id, pending.first, q.title, q.body, pending.second
                )
            )
            AlarmScheduler.cancelOtherChannel(
                context, am, q.id, TodoReminderReceiver::class.java
            )
        }
        AlarmStore.replaceQuiets(context, keepQuiets)

        return Result(armed, keepQuiets.size)
    }
}
