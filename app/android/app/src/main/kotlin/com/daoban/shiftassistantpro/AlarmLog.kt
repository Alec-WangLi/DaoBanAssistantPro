package com.daoban.shiftassistantpro

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 全局日志：错误/崩溃写入 filesDir/app_log.txt（「我的 → 查看日志」可复制排查），
 * 普通信息仅写 Logcat（adb 可见，应用内不显示）。文件按大小自动裁剪，避免无限增长。
 */
object AlarmLog {
    private const val TAG = "ShiftAssistant"
    private const val MAX_BYTES = 256L * 1024L // 超过则裁剪
    private const val KEEP_CHARS = 42_000 // 约等于 128KB（中文按 3 字节估算）

    private val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault())

    /** 错误/崩溃：写文件 + Logcat。 */
    fun error(context: Context, msg: String) {
        Log.e(TAG, msg)
        appendFile(context, msg)
    }

    /** 普通信息：只写 Logcat，不落盘。 */
    fun info(context: Context, msg: String) {
        Log.d(TAG, msg)
    }

    private fun appendFile(context: Context, msg: String) {
        try {
            val f = File(context.filesDir, "app_log.txt")
            f.appendText("[${fmt.format(Date())}] $msg\n")
            trim(f)
        } catch (_: Throwable) {
        }
    }

    /** 超过上限时只保留最新一段（从行首开始），避免日志无限增长。 */
    private fun trim(f: File) {
        try {
            if (f.length() <= MAX_BYTES) return
            val text = f.readText()
            val keep = text.takeLast(KEEP_CHARS)
            val idx = keep.indexOf('\n')
            f.writeText(if (idx >= 0) keep.substring(idx + 1) else keep)
        } catch (_: Throwable) {
        }
    }

    fun read(context: Context): String = try {
        val f = File(context.filesDir, "app_log.txt")
        if (f.exists()) f.readText() else ""
    } catch (_: Throwable) { "" }

    fun clear(context: Context) {
        try { File(context.filesDir, "app_log.txt").delete() } catch (_: Throwable) {}
    }

    /** 关键设备状态，用于排查「锁屏不自动弹全屏」：权限 + 屏幕/锁屏状态。 */
    fun deviceState(context: Context): String {
        val sb = StringBuilder("sdk=${Build.VERSION.SDK_INT}")
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            sb.append(", interactive=${pm.isInteractive}")
        } catch (_: Throwable) {}
        try {
            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            sb.append(", keyguardLocked=${km.isKeyguardLocked}")
            if (Build.VERSION.SDK_INT >= 23) sb.append(", deviceLocked=${km.isDeviceLocked}")
        } catch (_: Throwable) {}
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= 34) {
                sb.append(", canUseFullScreenIntent=${nm.canUseFullScreenIntent()}")
            }
        } catch (_: Throwable) {}
        try {
            sb.append(", canDrawOverlays=${Settings.canDrawOverlays(context)}")
        } catch (_: Throwable) {}
        return sb.toString()
    }
}
