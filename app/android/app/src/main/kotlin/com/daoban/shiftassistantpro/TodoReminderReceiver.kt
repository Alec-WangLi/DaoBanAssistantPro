package com.daoban.shiftassistantpro

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/**
 * 待办提醒到点：在通知栏弹一条**普通通知**。
 *
 * 与闹钟那条链路（[AlarmReceiver] → 前台服务循环响铃 + 全屏界面）刻意分开：
 * 「交体检报告」不该用循环响铃把人从梦里叫醒，也不该占着系统状态栏的闹钟图标。
 *
 * 通知的标题与正文都由 Dart 侧排定时给好（`AlarmService.scheduleTodoReminder`），
 * 这里只负责发出去 —— 文案要跟着界面语言走，而语言只有 Dart 侧知道。
 */
class TodoReminderReceiver : BroadcastReceiver() {

    companion object {
        const val CHANNEL_ID = "todo_reminders"

        /** 通道还没被 Dart 侧命名过时的兜底名（正常情况下用不上）。 */
        private const val FALLBACK_NAME = "待办提醒"

        /**
         * 建或**更新**通知通道。
         *
         * 通道名要显示在系统「通知」设置里，得跟着界面语言走；而通道只能在原生侧
         * 创建。同一个 id 重复创建是「更新」而不是报错，所以 App 每次启动时由
         * Dart 侧把当前语言的名字递进来（[AlarmService.ensureTodoChannel]）。
         *
         * 到点发通知前也调一次：通道不存在时 `notify` 会被系统**静默丢掉**，
         * 那是「提醒没响」里最难查的一种。
         */
        fun ensureChannel(context: Context, name: String? = null) {
            val nm = context
                .getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val existing = nm.getNotificationChannel(CHANNEL_ID)
            val channel = NotificationChannel(
                CHANNEL_ID,
                name ?: existing?.name ?: FALLBACK_NAME,
                // 高优先级 = 横幅弹出 + 有声音（声音用通道默认的系统通知音）。
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.enableVibration(true)
            nm.createNotificationChannel(channel)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: return
        val body = intent.getStringExtra("body") ?: ""
        val id = intent.getIntExtra("id", 0)
        AlarmLog.info(context, "TodoReminderReceiver: id=$id, title=$title")

        // 一次性提醒：**触发即消费**，落盘清单里那条先删掉。放在最前面是有意的
        // —— 后面每条提前 return（没通知权限等）都算「已经到过点」，留着它只会让
        // 下次重启时 BootReceiver 把一条过期提醒当成新排的。
        AlarmStore.removeQuiet(context, id)

        // Android 13+ 没给通知权限时 notify() 是**静默无效**的，不留一行日志的话
        // 用户报「提醒没来」时完全查不出原因。
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(
                android.Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            AlarmLog.error(
                context,
                "TodoReminderReceiver: 没有通知权限，这条提醒发不出去（id=$id）"
            )
            return
        }

        ensureChannel(context)

        // 点通知：打开 App 并切到「待办」页。todo_id 由 MainActivity 转给 Dart。
        val open = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            putExtra("todo_id", id)
        }
        val contentPi = PendingIntent.getActivity(
            context, id, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(getDrawableId(context))
            .setContentTitle(title)
            .setContentText(body)
            // 正文可能被截断时展开显示完整内容（日期 + 时间那一整串）。
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setContentIntent(contentPi)
            // 点掉就消失：提醒是一次性的，不该留在通知栏里当常驻项。
            .setAutoCancel(true)
            .setOngoing(false)
            .build()

        val nm = context
            .getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(id, notification)
    }

    /** 与响铃服务同一个图标（`res/drawable/ic_notification`，白剪影）。 */
    private fun getDrawableId(context: Context): Int =
        context.resources.getIdentifier("ic_notification", "drawable", context.packageName)
}
