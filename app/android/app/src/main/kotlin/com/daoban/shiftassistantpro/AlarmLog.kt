package com.daoban.shiftassistantpro

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * 全局日志：错误/崩溃写入 filesDir/app_log.txt（「我的 → 查看日志」可复制排查），
 * 普通信息仅写 Logcat（adb 可见，应用内不显示）。文件按大小自动裁剪，避免无限增长。
 */
object AlarmLog {
    private const val TAG = "ShiftAssistant"
    private const val MAX_BYTES = 256L * 1024L // 超过则裁剪
    private const val KEEP_CHARS = 42_000 // 约等于 128KB（中文按 3 字节估算）

    /**
     * 时间戳格式器。
     *
     * **必须是线程安全的**：写日志的点遍布主线程（`AlarmReceiver`）与工作线程
     * （`AlarmScheduler.reconcile`、`AlarmWatchdogReceiver`）。`SimpleDateFormat`
     * 内部有可变状态，并发用会打出乱码、甚至抛 `ArrayIndexOutOfBoundsException`
     * —— 那会让「用户贴来的日志」正好在关键时刻变成一坨。`DateTimeFormatter`
     * 不可变，天然可以共用。
     */
    private val fmt: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault())

    private fun stamp(): String =
        Instant.ofEpochMilli(System.currentTimeMillis())
            .atZone(ZoneId.systemDefault())
            .format(fmt)

    /** 错误/崩溃：写文件 + Logcat。 */
    fun error(context: Context, msg: String) {
        Log.e(TAG, msg)
        appendFile(context, msg)
    }

    /** 普通信息：只写 Logcat，不落盘。 */
    fun info(context: Context, msg: String) {
        Log.d(TAG, msg)
    }

    /**
     * 诊断信息：写文件 + Logcat。
     *
     * 与 [info] 的区别是**要落盘** —— 设备能力这类东西用户换机后要能在
     * 「我的 → 查看日志」里直接看到，不该只在 adb 里可见；与 [error] 的区别是
     * 它**不是错误**，别让用户看到一屏「错误」以为出事了。
     */
    fun diagnostic(context: Context, msg: String) {
        Log.i(TAG, msg)
        appendFile(context, msg)
    }

    /**
     * 同一个 [key] 在本**进程**内只落一次盘。
     *
     * 用途是那串很长的设备能力（`deviceState` 约 200 字）：每个进程的第一条闹钟
     * 日志带上一次就够了，后面每行都带会把整份日志撑满，用户复制时也看不过来
     * （2026-11-22 反馈里那 4 行日志被设备信息占了 3 行）。
     */
    fun diagnosticOnce(context: Context, key: String, msg: String) {
        if (!onceKeys.add(key)) return
        diagnostic(context, msg)
    }

    /** [deviceState] 的「每进程一次」形态：已经出现过就返回空串。 */
    fun deviceStateOnce(context: Context, key: String): String {
        if (!onceKeys.add(key)) return ""
        return deviceState(context)
    }

    /** 本进程内已经落过盘的键。进程重启会重置 —— 正是要的粒度。 */
    private val onceKeys = java.util.Collections.synchronizedSet(mutableSetOf<String>())

    private fun appendFile(context: Context, msg: String) {
        try {
            val f = File(context.filesDir, "app_log.txt")
            f.appendText("[${stamp()}] $msg\n")
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

    /** 关键设备状态，用于排查「锁屏不自动弹全屏」与「闹钟没响」。 */
    fun deviceState(context: Context): String {
        val sb = StringBuilder("sdk=${Build.VERSION.SDK_INT}")
        // 机型：「闹钟偶尔不响」几乎都是厂商的休眠 / 电池策略，先要知道是哪一家。
        sb.append(", device=${Build.MANUFACTURER}/${Build.MODEL}")
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            sb.append(", interactive=${pm.isInteractive}")
            // 没被排除出电池优化时，系统可以把闹钟压成非精确甚至整段吞掉。
            sb.append(", ignoreBatteryOpt=${pm.isIgnoringBatteryOptimizations(context.packageName)}")
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
            sb.append(", notifications=${nm.areNotificationsEnabled()}")
        } catch (_: Throwable) {}
        try {
            sb.append(", canDrawOverlays=${Settings.canDrawOverlays(context)}")
        } catch (_: Throwable) {}
        return sb.toString()
    }
}
