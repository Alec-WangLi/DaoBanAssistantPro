package com.daoban.shiftassistantpro

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

/**
 * 原生闹钟统一排定：setAlarmClock → AlarmReceiver（前台服务响铃 + 全屏 + 续排）。
 *
 * 一次性闹钟只排一次；每天/每周闹钟在触发后由 AlarmReceiver 用同一 id 自动续排下一次，
 * 因此每个重复闹钟始终只有一条待触发的 AlarmManager 记录，不会累积。
 */
object AlarmScheduler {

    /** 自定义闹钟的原生 id 基址（id = 10000 + 数据库自增 id），与排班闹钟 0..359 隔离。 */
    const val CUSTOM_BASE_ID = 10000

    /**
     * 待办提醒的原生 id 基址（id = 20000 + 数据库里那一行的自增 id）。
     *
     * **`AUTOINCREMENT` 永不复用**，所以这个号只增不减。留到 39999（两万槽）：
     * 一个「每天」的重复待办每完成一次就产生一行，两三年就能把一千个号用光 ——
     * 而从前只留了 1000，越界之后提醒**排得下去、谁也取消不掉**（幽灵提醒）。
     */
    const val TODO_BASE_ID = 20000

    /**
     * 重复待办提醒的原生 id 基址（id = 40000 + 系列的自增 id）。
     *
     * **与待办行的号段分开**是有意的：系列的条数由用户手建，几十条就到头了，而
     * 待办行会越攒越多 —— 两者共用一个自增序列的话，行号迟早把提醒的号挤出去。
     * 留到 41999。
     */
    const val RECURRING_BASE_ID = 40000

    /**
     * 排一条「安静的」提醒：到点只弹一条通知，不响铃、不全屏、不进系统闹钟栏。
     *
     * 与 [schedule] 的两点不同，都是刻意的：
     *
     *  - 用 `setExactAndAllowWhileIdle` 而不是 `setAlarmClock`。后者会被系统当成
     *    真闹钟：状态栏常驻闹钟图标、时钟应用的「下次闹钟」里也会列出来。对一条
     *    「交体检报告」太重了，用户会以为手机一直在设闹钟。
     *  - 精确闹钟权限没给（`canScheduleExactAlarms` 为假）时**退化成非精确**排定，
     *    宁可晚几分钟也不静默不响。少数 ROM 上前面报 true、`setExact...` 仍抛
     *    `SecurityException`，所以那条路也再兜一次。
     */
    fun scheduleQuiet(
        context: Context,
        id: Int,
        millis: Long,
        title: String,
        body: String,
        repeatTimes: LongArray = LongArray(0)
    ) {
        val op = Intent(context, TodoReminderReceiver::class.java).apply {
            putExtra("id", id)
            putExtra("title", title)
            putExtra("body", body)
            // 后面还跟着的几次点火时刻（升序）。空数组 = 一次性提醒，与从前一样。
            putExtra("repeatTimes", repeatTimes)
        }
        val pi = PendingIntent.getBroadcast(
            context, id, op,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !am.canScheduleExactAlarms()
            ) {
                AlarmLog.info(context, "scheduleQuiet: 无精确闹钟权限，退化为非精确排定")
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, pi)
            }
        } catch (e: SecurityException) {
            AlarmLog.error(
                context,
                "scheduleQuiet: setExact 被拒(${e.message})，退化为非精确排定"
            )
            try {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, pi)
            } catch (e2: Exception) {
                AlarmLog.error(context, "scheduleQuiet: 退化排定也失败: ${e2.message}")
            }
        }

        // 与闹钟同样落盘一份：重启后 AlarmManager 里的记录会被清空，只有这份清单
        // 能让 BootReceiver 把提醒排回去。放在三条排定分支之后统一写 —— 精确 /
        // 退化 / 再退化的结果都该进清单，否则「没有精确闹钟权限」的机器上一重启
        // 提醒就全没了。
        AlarmStore.putQuiet(
            context,
            AlarmStore.Quiet(
                id = id, millis = millis, title = title, body = body,
                repeatTimes = repeatTimes.toList()
            )
        )
    }

    /**
     * 取消全部待办提醒与待办闹钟。
     *
     * **按落盘清单逐个撤，不再盲目扫一大段 id。** 从前扫的是固定 1000 个号，而
     * 现在待办提醒能排到 [RECURRING_BASE_ID] 附近 —— 盲扫会变成几万次
     * `PendingIntent` 操作，而**每勾一次待办都要跑一遍这一段**。
     *
     * 末尾保留一小段盲扫（`TODO_BASE_ID .. +1000`）：只为清掉「升级前排下、清单里
     * 还没有」的陈旧记录。这一段的开销与从前的实现相同，所以不引入新的性能代价。
     */
    fun cancelTodoReminders(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // **两种目标都要取消**：同一条待办按「联动闹钟」开关二选一 —— 开走
        // AlarmReceiver（响铃），关走 TodoReminderReceiver（通知）。两者用的是
        // 同一个 id，只取消一种就会把另一种留成幽灵闹钟，到点还会响。
        val targets = listOf(AlarmReceiver::class.java, TodoReminderReceiver::class.java)
        val upper = RECURRING_BASE_ID + 2000
        val ids = mutableSetOf<Int>()
        // ① 清单里记着的（准确、量小）
        for (e in AlarmStore.all(context)) {
            if (e.id in TODO_BASE_ID until upper) ids.add(e.id)
        }
        for (q in AlarmStore.allQuiets(context)) {
            if (q.id in TODO_BASE_ID until upper) ids.add(q.id)
        }
        // ② 一小段盲扫兜底：旧版本用过、清单里没有的那些
        for (i in 0 until 1000) ids.add(TODO_BASE_ID + i)

        for (id in ids) {
            for (target in targets) {
                try {
                    val pi = PendingIntent.getBroadcast(
                        context,
                        id,
                        // 只比 action/data/type/class/categories，extras 不参与，
                        // 所以空 Intent 也能稳稳取消掉排定时那个。
                        Intent(context, target),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    am.cancel(pi)
                } catch (_: Exception) {
                }
            }
        }
        // 两份清单同步清掉这两段（清了之后 Dart 会把要留的重新排一遍）。
        AlarmStore.clearQuiets(context, TODO_BASE_ID, upper)
        AlarmStore.clearEntries(context, TODO_BASE_ID, upper)
    }

    fun schedule(
        context: Context,
        id: Int,
        millis: Long,
        label: String,
        uri: String?,
        repeatType: Int = 0,
        hour: Int = 0,
        minute: Int = 0,
        weekdays: Int = 0,
        detail: String? = null,
        repeatTimes: LongArray = LongArray(0)
    ) {
        // showIntent：系统「闹钟图标/通知」用的 Activity，点击回到本 App。
        val show = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            putExtra("alarm_label", label)
            putExtra("alarm_detail", detail)
        }
        val showPi = PendingIntent.getActivity(
            context, id, show,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // operation：到点触发 AlarmReceiver（前台服务响铃 + 全屏 + 续排下一次）。
        val op = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("label", label)
            putExtra("uri", uri)
            putExtra("id", id)
            putExtra("repeatType", repeatType)
            putExtra("hour", hour)
            putExtra("minute", minute)
            putExtra("weekdays", weekdays)
            putExtra("detail", detail)
            // 时刻表驱动（`repeatType == 3`）时后面还跟着的几次（升序）。
            // showIntent 那枚 PendingIntent 不用带：它只负责点通知回 App。
            putExtra("repeatTimes", repeatTimes)
        }
        val opPi = PendingIntent.getBroadcast(
            context, id, op,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAlarmClock(AlarmManager.AlarmClockInfo(millis, showPi), opPi)

        // 同时落盘一份：重启后 AlarmManager 里的记录会被清空，只有这份清单能告诉
        // BootReceiver「重启前排过什么」。**排定与落盘必须成对**，漏了这条记录，
        // 那个闹钟以后就只在「App 打开过」的情况下能响。
        AlarmStore.put(
            context,
            AlarmStore.Entry(
                id = id, millis = millis, label = label, uri = uri,
                repeatType = repeatType, hour = hour, minute = minute,
                weekdays = weekdays, detail = detail,
                repeatTimes = repeatTimes.toList()
            )
        )
    }

    /**
     * 从「本次时刻 + 后续队列」里挑出第一个还没过的时刻，连同剩下的队列。
     *
     * 队列是 Dart 侧算好的（`upcomingFireTimes`，见 `alarm_service.dart` 的
     * `planRecurringReminders`）。**规则判断一律不写在这里**：Kotlin 侧没有可跑的
     * 测试目标，而月末特例 / 多选星期几 / 提前提醒的偏移 / 夏令时这些边角照抄
     * 一份必然与 Dart 侧对不上 —— 症状还是「某天没响」这种不报错的。
     *
     * 全过了（或队列为空、时刻本身也过了）返回 null，由调用方决定「不再续排」。
     */
    fun nextPending(millis: Long, queue: LongArray, now: Long): Pair<Long, LongArray>? {
        val all = LongArray(queue.size + 1)
        all[0] = millis
        System.arraycopy(queue, 0, all, 1, queue.size)
        val idx = all.indexOfFirst { it > now }
        if (idx < 0) return null
        return all[idx] to all.copyOfRange(idx + 1, all.size)
    }

    /**
     * 取消一条闹钟：AlarmManager 的记录与落盘清单**一起**撤。
     *
     * 凡是绕开这里、只 `am.cancel(...)` 的调用点，都会在清单里留下一条「幽灵闹钟」
     * —— 界面上看不出来，直到某天重启后它自己响了。
     */
    fun cancel(context: Context, id: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val op = Intent(context, AlarmReceiver::class.java)
        val opPi = PendingIntent.getBroadcast(
            context, id, op,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        am.cancel(opPi)
        AlarmStore.remove(context, id)
    }

    /** 下一次 [hour]:[minute]（今天该时刻已过则顺延到明天）。 */
    fun nextDaily(nowMillis: Long, hour: Int, minute: Int): Long {
        val cal = Calendar.getInstance().apply {
            timeInMillis = nowMillis
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (cal.timeInMillis <= nowMillis) cal.add(Calendar.DAY_OF_YEAR, 1)
        return cal.timeInMillis
    }

    /**
     * 下一次匹配 [weekdays]（位掩码 1<<(周一=0)…，即 Dart DateTime.weekday 约定）的
     * [hour]:[minute]；从明天开始向前找 7 天，保证严格晚于 [nowMillis]。
     */
    fun nextWeekly(nowMillis: Long, weekdays: Int, hour: Int, minute: Int): Long {
        val cal = Calendar.getInstance().apply { timeInMillis = nowMillis }
        for (i in 1..7) {
            cal.add(Calendar.DAY_OF_YEAR, 1)
            cal.set(Calendar.HOUR_OF_DAY, hour)
            cal.set(Calendar.MINUTE, minute)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            // Calendar.DAY_OF_WEEK: 1=周日,2=周一…7=周六 → 转成 Dart 的 1=周一…7=周日
            val dartWeekday = ((cal.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
            if ((weekdays and (1 shl (dartWeekday - 1))) != 0) {
                return cal.timeInMillis
            }
        }
        // 兜底（weekdays 为空等异常）：明天同一时间
        return cal.timeInMillis
    }
}
