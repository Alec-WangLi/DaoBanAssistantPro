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

    /** 归档文件的命名前缀与保留天数（v0.13.20）。 */
    private const val ARCHIVE_PREFIX = "app_log-"
    private const val KEEP_DAYS = 7L

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
            rotateIfNeeded(context, f)
            f.appendText("[${stamp()}] $msg\n")
            trim(f)
        } catch (_: Throwable) {
        }
    }

    /**
     * 跨天归档（v0.13.20）。
     *
     * **为什么要分段**：报「偶尔没响」的用户往往隔一两天才反馈，而单文件 256KB
     * 上限只覆盖几个小时（一次冷启动就写十几行，206 条重排还带两行汇总）——
     * 等用户来反馈时，出事那一段早被 [trim] 裁掉了。按天一分，翻到那天就行。
     */
    @Synchronized
    private fun rotateIfNeeded(context: Context, f: File) {
        try {
            if (!f.exists() || f.length() == 0L) return
            val zone = ZoneId.systemDefault()
            val last = Instant.ofEpochMilli(f.lastModified()).atZone(zone).toLocalDate()
            val today = java.time.LocalDate.now(zone)
            if (!last.isBefore(today)) return
            val target = File(context.filesDir, "$ARCHIVE_PREFIX$last.txt")
            // 同一天内进程重起多次时，目标可能已经在了 —— 追加而不是覆盖。
            if (target.exists()) {
                target.appendText(f.readText())
                f.delete()
            } else if (!f.renameTo(target)) {
                target.writeText(f.readText())
                f.delete()
            }
            prune(context)
        } catch (_: Throwable) {
        }
    }

    /** 删掉超过 [KEEP_DAYS] 天的归档。 */
    private fun prune(context: Context) {
        try {
            val cutoff = java.time.LocalDate.now(ZoneId.systemDefault())
                .minusDays(KEEP_DAYS)
            for (file in context.filesDir.listFiles() ?: return) {
                val name = file.name
                if (!name.startsWith(ARCHIVE_PREFIX) || !name.endsWith(".txt")) continue
                val day = try {
                    java.time.LocalDate.parse(
                        name.removePrefix(ARCHIVE_PREFIX).removeSuffix(".txt"))
                } catch (_: Throwable) {
                    continue
                }
                if (day.isBefore(cutoff)) file.delete()
            }
        } catch (_: Throwable) {
        }
    }

    /**
     * 日志文件清单（新的在前）：当前文件 + 归档。
     *
     * `day` 是那一份覆盖的日期（当前文件给今天）—— 界面按它做选择条。
     */
    fun listFiles(context: Context): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val cur = File(context.filesDir, "app_log.txt")
        if (cur.exists() && cur.length() > 0) {
            out.add(
                mapOf(
                    "name" to "app_log.txt",
                    "day" to java.time.LocalDate.now(ZoneId.systemDefault()).toString(),
                    "size" to cur.length(),
                )
            )
        }
        val archives = (context.filesDir.listFiles() ?: emptyArray())
            .filter { it.name.startsWith(ARCHIVE_PREFIX) && it.name.endsWith(".txt") }
            .sortedByDescending { it.name }
        for (f in archives) {
            out.add(
                mapOf(
                    "name" to f.name,
                    "day" to f.name.removePrefix(ARCHIVE_PREFIX).removeSuffix(".txt"),
                    "size" to f.length(),
                )
            )
        }
        return out
    }

    /**
     * 读某一份日志。
     *
     * **只认本对象自己产出的两种文件名** —— 别让它变成一个「按名字读任意文件」
     * 的入口（名字是界面传进来的）。
     */
    fun readFile(context: Context, name: String): String {
        val safe = name == "app_log.txt" || (
            name.startsWith(ARCHIVE_PREFIX) &&
                name.endsWith(".txt") &&
                !name.contains('/') &&
                !name.contains('\\') &&
                !name.contains("..")
            )
        if (!safe) return ""
        return try {
            val f = File(context.filesDir, name)
            if (f.exists()) f.readText() else ""
        } catch (_: Throwable) {
            ""
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

    /** 清空全部日志（当前文件 + 归档）。 */
    fun clear(context: Context) {
        try {
            File(context.filesDir, "app_log.txt").delete()
            for (file in context.filesDir.listFiles() ?: emptyArray()) {
                if (file.name.startsWith(ARCHIVE_PREFIX) && file.name.endsWith(".txt")) {
                    file.delete()
                }
            }
        } catch (_: Throwable) {
        }
    }

    /**
     * 诊断包里的**设备与权限快照**（结构化 Map，给机器读）。
     *
     * 与 [deviceState] 那行中文摘要互补：那一行给人看，这一份进导出包给排查用
     * —— 键名稳定，不随文案改。
     */
    fun deviceReport(context: Context): Map<String, Any?> {
        val m = LinkedHashMap<String, Any?>()
        m["sdk"] = Build.VERSION.SDK_INT
        m["release"] = Build.VERSION.RELEASE
        m["manufacturer"] = Build.MANUFACTURER
        m["model"] = Build.MODEL
        m["device"] = Build.DEVICE
        m["timezone"] = java.util.TimeZone.getDefault().id
        m["locale"] = java.util.Locale.getDefault().toString()
        try {
            m["versionName"] =
                context.packageManager.getPackageInfo(context.packageName, 0).versionName
        } catch (_: Throwable) {
        }
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            m["ignoringBatteryOptimizations"] =
                pm.isIgnoringBatteryOptimizations(context.packageName)
        } catch (_: Throwable) {
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val am = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
                m["canScheduleExactAlarms"] = am.canScheduleExactAlarms()
            } catch (_: Throwable) {
            }
        }
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            m["notificationsEnabled"] = nm.areNotificationsEnabled()
            if (Build.VERSION.SDK_INT >= 34) {
                m["canUseFullScreenIntent"] = nm.canUseFullScreenIntent()
            }
        } catch (_: Throwable) {
        }
        try {
            m["canDrawOverlays"] = Settings.canDrawOverlays(context)
        } catch (_: Throwable) {
        }
        try {
            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            m["keyguardLocked"] = km.isKeyguardLocked
        } catch (_: Throwable) {
        }
        return m
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
