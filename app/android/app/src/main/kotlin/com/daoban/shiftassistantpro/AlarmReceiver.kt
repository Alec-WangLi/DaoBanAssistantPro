package com.daoban.shiftassistantpro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 原生闹钟接收器：AlarmManager 到点触发。
 *
 * 1) 启动前台服务（循环播放铃声 + 震动，后台/锁屏都能响）；
 * 2) 尝试直接拉起全屏响铃界面（App 在前台时生效；锁屏由前台通知的 fullScreenIntent 兜底）；
 * 3) 每天/每周闹钟：用同一 id 自动续排下一次。
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val label = intent.getStringExtra("label") ?: "闹钟"
        val uri = intent.getStringExtra("uri")
        val id = intent.getIntExtra("id", 0)
        val repeatType = intent.getIntExtra("repeatType", 0)
        val hour = intent.getIntExtra("hour", 0)
        val minute = intent.getIntExtra("minute", 0)
        val weekdays = intent.getIntExtra("weekdays", 0)

        AlarmLog.info(
            context,
            "AlarmReceiver.onReceive: id=$id, label=$label, repeatType=$repeatType, ${AlarmLog.deviceState(context)}"
        )

        // 1) 前台服务：响铃 + 震动
        try {
            val serviceIntent = Intent(context, AlarmRingService::class.java).apply {
                putExtra("label", label)
                putExtra("uri", uri)
            }
            context.startForegroundService(serviceIntent)
            AlarmLog.info(context, "AlarmReceiver: startForegroundService 成功")
        } catch (e: Exception) {
            AlarmLog.error(
                context,
                "AlarmReceiver: startForegroundService 失败: ${e.javaClass.name}: ${e.message}"
            )
        }

        // 2) 尝试直接拉起全屏响铃界面（前台时生效）
        try {
            val launch = Intent(context, MainActivity::class.java)
            launch.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            launch.putExtra("alarm_label", label)
            context.startActivity(launch)
            AlarmLog.info(context, "AlarmReceiver: startActivity 成功（直接拉起全屏）")
        } catch (e: Exception) {
            AlarmLog.error(
                context,
                "AlarmReceiver: startActivity 被拒(疑似后台启动限制): ${e.javaClass.name}: ${e.message}"
            )
        }

        // 3) 重复闹钟续排下一次
        val now = System.currentTimeMillis()
        when (repeatType) {
            1 -> {
                val next = AlarmScheduler.nextDaily(now, hour, minute)
                AlarmScheduler.schedule(context, id, next, label, uri, repeatType, hour, minute, weekdays)
            }
            2 -> if (weekdays != 0) {
                val next = AlarmScheduler.nextWeekly(now, weekdays, hour, minute)
                AlarmScheduler.schedule(context, id, next, label, uri, repeatType, hour, minute, weekdays)
            }
        }
    }
}
