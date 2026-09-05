package com.daoban.shiftassistantpro

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator

/**
 * 前台服务：闹钟到点时循环播放铃声 + 震动，并显示一条前台通知。
 *
 * 前台服务不受「后台启动 Activity」限制，也不受通知声音静音影响，
 * 是国产 ROM 上闹钟能稳定响铃的关键。
 */
class AlarmRingService : Service() {
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val label = intent?.getStringExtra("label") ?: "闹钟"
        val uriStr = intent?.getStringExtra("uri")
        AlarmLog.info(
            this,
            "AlarmRingService.onStartCommand: label=$label, ${AlarmLog.deviceState(this)}"
        )
        startForeground(1, buildNotification(label))
        AlarmLog.info(this, "AlarmRingService: startForeground 完成，通知已带 fullScreenIntent + CATEGORY_ALARM")
        wakeScreen()
        startSound(uriStr)
        return START_NOT_STICKY
    }

    private fun startSound(uriStr: String?) {
        try {
            val uri = if (uriStr.isNullOrEmpty()) {
                Uri.parse("android.resource://$packageName/raw/alarm_beep")
            } else {
                Uri.parse(uriStr)
            }
            val mp = MediaPlayer()
            mp.setDataSource(this, uri)
            mp.isLooping = true
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            mp.prepare()
            mp.start()
            player = mp
        } catch (_: Exception) {
        }
        try {
            val v = getSystemService(VIBRATOR_SERVICE) as Vibrator
            vibrator = v
            v.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 700, 400), 0))
        } catch (_: Exception) {
        }
    }

    /** 点亮屏幕：锁屏/息屏时闹钟到点也能看到全屏关闭界面。 */
    @Suppress("DEPRECATION")
    private fun wakeScreen() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(
                PowerManager.FULL_WAKE_LOCK
                    or PowerManager.ACQUIRE_CAUSES_WAKEUP
                    or PowerManager.ON_AFTER_RELEASE,
                "shiftassistant:alarm_ring"
            )
            wl.acquire(10 * 60 * 1000L) // 最长 10 分钟；停止响铃时在 onDestroy 释放
            wakeLock = wl
            AlarmLog.info(
                this,
                "AlarmRingService: WakeLock 已获取(FULL_WAKE_LOCK+ACQUIRE_CAUSES_WAKEUP)"
            )
        } catch (e: Exception) {
            AlarmLog.error(
                this,
                "AlarmRingService: WakeLock 获取失败: ${e.javaClass.name}: ${e.message}"
            )
        }
    }

    private fun buildNotification(label: String): Notification {
        val channelId = "alarm_ring"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            channelId, "闹钟响铃", NotificationManager.IMPORTANCE_HIGH
        )
        channel.setSound(null, null)
        nm.createNotificationChannel(channel)

        val launch = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            putExtra("alarm_label", label)
        }
        // 内容点击：回到响铃界面
        val pi = PendingIntent.getActivity(
            this, 0, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // 全屏通知：锁屏/息屏时自动弹出全屏关闭界面（requestCode 与上面区分开）
        val fullScreenPi = PendingIntent.getActivity(
            this, 1, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return Notification.Builder(this, channelId)
            .setSmallIcon(getDrawableId("ic_notification"))
            .setContentTitle(label)
            .setContentText("闹钟响了，点击停止")
            .setContentIntent(pi)
            .setFullScreenIntent(fullScreenPi, true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
    }

    private fun getDrawableId(name: String): Int =
        resources.getIdentifier(name, "drawable", packageName)

    override fun onDestroy() {
        try {
            player?.stop()
            player?.release()
        } catch (_: Exception) {
        }
        player = null
        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        }
        vibrator = null
        try {
            wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
