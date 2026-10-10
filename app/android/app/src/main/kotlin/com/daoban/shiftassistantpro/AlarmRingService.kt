package com.daoban.shiftassistantpro

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.os.IBinder
import android.os.Handler
import android.os.Looper
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

    /**
     * 响铃多久没人管就自己停。
     *
     * 15 分钟是**拍的**（不是量出来的）：够把人叫醒又赖一会儿床；再长，人不在就是
     * 白耗电 + 一直占着前台服务、震动与 WakeLock。参考 iOS 的响铃上限也是这个量级。
     */
    private val autoStopMs = 15 * 60 * 1000L

    private val autoStopHandler = Handler(Looper.getMainLooper())
    private val autoStopRunnable = Runnable { autoStop() }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val label = intent?.getStringExtra("label") ?: "闹钟"
        val detail = intent?.getStringExtra("detail")
        val uriStr = intent?.getStringExtra("uri")
        AlarmLog.info(
            this,
            "AlarmRingService.onStartCommand: label=$label, ${AlarmLog.deviceState(this)}"
        )
        startForeground(1, buildNotification(label, detail))
        AlarmLog.info(this, "AlarmRingService: startForeground 完成，通知已带 fullScreenIntent + CATEGORY_ALARM")
        wakeScreen()
        startSound(uriStr)
        // **重新计时**：每次 onStartCommand 都排一次。`onStartCommand` 会因为
        // 「再睡一会」（重新排定后又响）与重复的 startService 再进来，那时要的是一个
        // **新的**窗口，不是接上一轮的剩余时间。
        autoStopHandler.removeCallbacks(autoStopRunnable)
        autoStopHandler.postDelayed(autoStopRunnable, autoStopMs)
        AlarmLog.info(this, "AlarmRingService: ${autoStopMs / 1000} 秒后自动停止")
        return START_NOT_STICKY
    }

    /**
     * 超时自停。**走的是与用户手动关闭完全相同的那条拆除路径**：
     * `MainActivity.onAlarmAutoStopped()`（撤 `setShowWhenLocked`/`setTurnScreenOn`
     * + 让 Dart 收掉响铃界面）、撤通知、`stopSelf()` → `onDestroy` 停声/停震/放锁。
     *
     * ⚠️ `exitLockScreenMode()` **绝不能省**：那两个标志是只进不出的，不撤就等于把
     * 「锁屏下能直接操作 App」那个洞重新打开（v0.8.0 修过一次）。
     */
    private fun autoStop() {
        AlarmLog.info(this, "AlarmRingService: 到时无人关闭，自动停止响铃")
        try {
            MainActivity.onAlarmAutoStopped()
        } catch (e: Exception) {
            AlarmLog.error(this, "AlarmRingService: 自停回调失败: ${e.message}")
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun startSound(uriStr: String?) {
        // 音源挑选与「自选铃声坏了回落内置」都在 AlarmSound 里（两条响铃链路共用）。
        player = AlarmSound.start(this, uriStr)
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

    private fun buildNotification(label: String, detail: String?): Notification {
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
            // 待办的联动闹钟会带说明（「9月15日 周二 · 14:30」），那比一句通用的
            // 「闹钟响了」有用得多 —— 用户瞟一眼通知就知道是什么事。
            .setContentText(detail ?: "闹钟响了，点击停止")
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
        // 先把定时器摘掉：服务已经被用户关掉之后再触发一次自停，会去动一个已经
        // 停掉的响铃（轻则多一条日志，重则把用户刚打开的那层界面收掉）。
        autoStopHandler.removeCallbacks(autoStopRunnable)
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
