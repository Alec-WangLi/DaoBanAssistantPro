package com.daoban.shiftassistantpro

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.util.Calendar

/**
 * 原生闹钟统一排定：setAlarmClock → AlarmReceiver（前台服务响铃 + 全屏 + 续排）。
 *
 * 一次性闹钟只排一次；每天/每周闹钟在触发后由 AlarmReceiver 用同一 id 自动续排下一次，
 * 因此每个重复闹钟始终只有一条待触发的 AlarmManager 记录，不会累积。
 */
object AlarmScheduler {

    /** 自定义闹钟的原生 id 基址（id = 10000 + 数据库自增 id），与排班闹钟 0..59 隔离。 */
    const val CUSTOM_BASE_ID = 10000

    fun schedule(
        context: Context,
        id: Int,
        millis: Long,
        label: String,
        uri: String?,
        repeatType: Int = 0,
        hour: Int = 0,
        minute: Int = 0,
        weekdays: Int = 0
    ) {
        // showIntent：系统「闹钟图标/通知」用的 Activity，点击回到本 App。
        val show = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            putExtra("alarm_label", label)
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
        }
        val opPi = PendingIntent.getBroadcast(
            context, id, op,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAlarmClock(AlarmManager.AlarmClockInfo(millis, showPi), opPi)
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
