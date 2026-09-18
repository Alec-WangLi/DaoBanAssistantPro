package com.daoban.shiftassistantpro

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 把「下一次该刷新了」排进 AlarmManager。
 *
 * 与 [AlarmScheduler] 的分工：那条链路排的是**响铃闹钟**（AlarmClock 类型、会出声、
 * 走 AlarmReceiver → 前台服务）；这条排的是**小组件重绘**（静默、走
 * ShiftWidgetProvider 的 ACTION_REFRESH）。两者互不影响，但共享同一个
 * 「自续排」的套路 —— 每次刷新只排下一个边界，不一次排一堆。
 *
 * 刷新时刻由 Dart 侧算好放在快照的 `boundaries` 里（见 `widget_snapshot.dart`），
 * 原生只做一次线性扫描。为什么不在原生算：那些算法（本地零点怎么跨时区、跨午夜
 * 班次的结束落在次日、休班不产生边界）属于「算错了不报错、只显示错」的那一类，
 * 放在有 170 条测试的 Dart 侧划算得多。
 */
object WidgetRefreshScheduler {

    /** 请求码。与 `MainActivity.REQ_PICK_RINGTONE(40071)` 错开。 */
    private const val REQ = 40081

    fun schedule(context: Context, atMs: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = PendingIntent.getBroadcast(
            context,
            REQ,
            Intent(context, ShiftWidgetProvider::class.java)
                .setAction(ShiftWidgetProvider.ACTION_REFRESH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        try {
            // API 31 起精确闹钟要用户授权（SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM）。
            // 被收回时退化成非精确 —— 跨天翻页本来就不要求秒级准时，可接受的偏差是
            // 「凌晨多等一会儿才翻页」，而不是「卡片永久停住」。
            if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
                AlarmLog.info(context, "WidgetRefreshScheduler: 无精确权限，退化非精确 at=$atMs")
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
                AlarmLog.info(context, "WidgetRefreshScheduler: 已排精确 at=$atMs")
            }
        } catch (e: Exception) {
            // SecurityException（权限中途被收回）等：绝不让它冒出去弄崩 onReceive。
            // 再退一档，用不保证唤醒的 set()。
            try {
                am.set(AlarmManager.RTC_WAKEUP, atMs, pi)
                AlarmLog.info(context, "WidgetRefreshScheduler: 二次退化为 set() at=$atMs")
            } catch (e2: Exception) {
                AlarmLog.error(context, "WidgetRefreshScheduler.schedule 彻底失败: ${e2.message}")
            }
        }
    }

    fun cancel(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = PendingIntent.getBroadcast(
            context,
            REQ,
            Intent(context, ShiftWidgetProvider::class.java)
                .setAction(ShiftWidgetProvider.ACTION_REFRESH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        am.cancel(pi)
    }
}
