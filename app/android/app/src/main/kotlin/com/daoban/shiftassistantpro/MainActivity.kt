package com.daoban.shiftassistantpro

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        /** 由原生闹钟拉起时待处理的闹钟标签（Flutter 启动后读取）。 */
        var pendingAlarmLabel: String? = null
    }

    private val settingsChannel = "com.daoban.shiftassistantpro/settings"
    private var flutterChannel: MethodChannel? = null
    private var playingRingtone: android.media.Ringtone? = null
    private var alarmPlayer: MediaPlayer? = null
    private var alarmVibrator: Vibrator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // 关键：必须在 setContentView（super.onCreate 内部）之前设置，锁屏冷启动才能点亮屏幕并显示
        applyShowWhenLocked(intent)
        super.onCreate(savedInstanceState)
        handleAlarmIntent(intent)
        // 捕获原生未处理异常（含闹钟 receiver 触发时的崩溃），写入日志文件
        val default = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                appendLog(
                    "NATIVE CRASH: ${throwable.javaClass.name}: ${throwable.message}\n" +
                        throwable.stackTraceToString()
                )
            } catch (_: Exception) {
            }
            default?.uncaughtException(thread, throwable)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleAlarmIntent(intent)
    }

    private fun applyShowWhenLocked(intent: Intent?) {
        val label = intent?.getStringExtra("alarm_label")
        if (label != null && Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            AlarmLog.info(this, "MainActivity: (onCreate 前) 已 setShowWhenLocked+setTurnScreenOn")
        }
    }

    private fun handleAlarmIntent(intent: Intent?) {
        val label = intent?.getStringExtra("alarm_label")
        AlarmLog.info(
            this,
            "MainActivity.handleAlarmIntent: label=$label, ${AlarmLog.deviceState(this)}"
        )
        if (label != null) {
            pendingAlarmLabel = label
            if (Build.VERSION.SDK_INT >= 27) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
                AlarmLog.info(this, "MainActivity: 已 setShowWhenLocked(true)+setTurnScreenOn(true)")
            }
            AlarmLog.info(this, "MainActivity: invokeMethod(onAlarmFired, $label)")
            flutterChannel?.invokeMethod("onAlarmFired", label)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannel)
        flutterChannel = channel
        channel
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAppSettings" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("OPEN_SETTINGS_FAILED", e.message, null)
                        }
                    }
                    "openOverlaySettings" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("OPEN_OVERLAY_FAILED", e.message, null)
                        }
                    }
                    "checkOverlayPermission" -> {
                        result.success(Settings.canDrawOverlays(this))
                    }
                    "checkBatteryOptimization" -> {
                        try {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            result.success(pm.isIgnoringBatteryOptimizations(packageName))
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "checkFullScreenIntentPermission" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= 34) {
                                val nm = getSystemService(NOTIFICATION_SERVICE)
                                        as android.app.NotificationManager
                                result.success(nm.canUseFullScreenIntent())
                            } else {
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "openFullScreenIntentSettings" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("OPEN_FSI_FAILED", e.message, null)
                        }
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("BATTERY_OPT_FAILED", e.message, null)
                        }
                    }
                    "clearNotificationCache" -> {
                        try {
                            val sp = getSharedPreferences(
                                "scheduled_notifications", MODE_PRIVATE
                            )
                            sp.edit().clear().apply()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("CLEAR_CACHE_FAILED", e.message, null)
                        }
                    }
                    "appendLog" -> {
                        val msg = call.argument<String>("msg") ?: ""
                        appendLog(msg)
                        result.success(null)
                    }
                    "logInfo" -> {
                        val msg = call.argument<String>("msg") ?: ""
                        logInfo(msg)
                        result.success(null)
                    }
                    "openUrl" -> {
                        try {
                            val url = call.argument<String>("url") ?: ""
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("OPEN_URL_FAILED", e.message, null)
                        }
                    }
                    "installApk" -> {
                        try {
                            val path = call.argument<String>("path") ?: ""
                            val file = File(path)
                            val uri = FileProvider.getUriForFile(
                                this, "$packageName.fileprovider", file
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INSTALL_APK_FAILED", e.message, null)
                        }
                    }
                    "readLog" -> result.success(readLog())
                    "clearLog" -> {
                        clearLog()
                        result.success(null)
                    }
                    "listRingtones" -> {
                        try {
                            // 用 applicationContext 走 RingtoneManager(Context) 构造：
                            // 若传 Activity 会走 managedQuery 注册托管 cursor，本方法结束 close 后，
                            // Activity 重启 requery 时抛 StaleDataException。
                            val manager = RingtoneManager(applicationContext)
                            manager.setType(RingtoneManager.TYPE_ALL)
                            val cursor = manager.cursor
                            val list = ArrayList<Map<String, String>>()
                            if (cursor != null && cursor.moveToFirst()) {
                                do {
                                    val position = cursor.position
                                    val title = cursor.getString(
                                        RingtoneManager.TITLE_COLUMN_INDEX
                                    ) ?: "铃声 $position"
                                    val uri = manager.getRingtoneUri(position).toString()
                                    val map = HashMap<String, String>()
                                    map["title"] = title
                                    map["uri"] = uri
                                    list.add(map)
                                } while (cursor.moveToNext())
                            }
                            cursor?.close()
                            result.success(list)
                        } catch (e: Exception) {
                            result.error("LIST_RINGTONES_FAILED", e.message, null)
                        }
                    }
                    "getVolumeLevels" -> {
                        try {
                            val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                            val map = HashMap<String, Int>()
                            map["alarm"] = audio.getStreamVolume(AudioManager.STREAM_ALARM)
                            map["alarmMax"] =
                                audio.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                            map["notification"] =
                                audio.getStreamVolume(AudioManager.STREAM_NOTIFICATION)
                            map["notificationMax"] =
                                audio.getStreamMaxVolume(AudioManager.STREAM_NOTIFICATION)
                            map["music"] = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                            map["musicMax"] =
                                audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            result.success(map)
                        } catch (e: Exception) {
                            result.error("GET_VOLUME_FAILED", e.message, null)
                        }
                    }
                    "playRingtone" -> {
                        try {
                            playingRingtone?.stop()
                            val uriStr = call.argument<String>("uri")
                            val uri = if (uriStr.isNullOrEmpty()) {
                                Uri.parse(
                                    "android.resource://$packageName/raw/alarm_beep"
                                )
                            } else {
                                Uri.parse(uriStr)
                            }
                            val rt = RingtoneManager.getRingtone(this, uri)
                            // 试听走「闹钟音量」，静音/免打扰下也能听到
                            rt.setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_ALARM)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                    .build()
                            )
                            playingRingtone = rt
                            rt.play()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("PLAY_RINGTONE_FAILED", e.message, null)
                        }
                    }
                    "stopRingtone" -> {
                        try {
                            playingRingtone?.stop()
                            playingRingtone = null
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("STOP_RINGTONE_FAILED", e.message, null)
                        }
                    }
                    "startAlarm" -> {
                        try {
                            stopAlarmInternal()
                            val uriStr = call.argument<String>("uri")
                            val uri = if (uriStr.isNullOrEmpty()) {
                                Uri.parse(
                                    "android.resource://$packageName/raw/alarm_beep"
                                )
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
                            alarmPlayer = mp

                            val v = getSystemService(VIBRATOR_SERVICE) as Vibrator
                            alarmVibrator = v
                            v.vibrate(
                                VibrationEffect.createWaveform(longArrayOf(0, 700, 400), 0)
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("START_ALARM_FAILED", e.message, null)
                        }
                    }
                    "stopAlarm" -> {
                        stopAlarmInternal()
                        stopService(Intent(this, AlarmRingService::class.java))
                        result.success(null)
                    }
                    "scheduleNativeAlarm" -> {
                        try {
                            val id = call.argument<Int>("id") ?: 0
                            val millis = call.argument<Long>("millis") ?: 0L
                            val label = call.argument<String>("label") ?: "闹钟"
                            val repeatType = call.argument<Int>("repeatType") ?: 0
                            val hour = call.argument<Int>("hour") ?: 0
                            val minute = call.argument<Int>("minute") ?: 0
                            val weekdays = call.argument<Int>("weekdays") ?: 0
                            val sp = getSharedPreferences(
                                "FlutterSharedPreferences", Context.MODE_PRIVATE
                            )
                            val uri = sp.getString("flutter.ringtoneUri", null)
                            AlarmScheduler.schedule(
                                this, id, millis, label, uri,
                                repeatType, hour, minute, weekdays
                            )
                            AlarmLog.info(
                                this,
                                "scheduleNativeAlarm 成功: id=$id, millis=$millis, label=$label, repeatType=$repeatType, ${AlarmLog.deviceState(this)}"
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            AlarmLog.error(this, "scheduleNativeAlarm 失败: ${e.javaClass.name}: ${e.message}")
                            result.error("SCHEDULE_ALARM_FAILED", e.message, null)
                        }
                    }
                    "cancelNativeAlarm" -> {
                        try {
                            val id = call.argument<Int>("id") ?: 0
                            val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                            am.cancel(nativePendingIntent(id))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("CANCEL_ALARM_FAILED", e.message, null)
                        }
                    }
                    "cancelAllNativeAlarms" -> {
                        // 后台线程执行，避免 ~1400 次 cancel 卡住主线程（重排时开关动画会卡顿）
                        Thread {
                            try {
                                val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                                for (id in 0..400) am.cancel(nativePendingIntent(id))
                                for (id in 10000..11000) am.cancel(nativePendingIntent(id))
                                for (id in 99990..100000) am.cancel(nativePendingIntent(id))
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("CANCEL_ALL_ALARM_FAILED", e.message, null)
                            }
                        }.start()
                    }
                    "cancelAllNotificationAlarms" -> {
                        Thread {
                            try {
                                val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                                for (id in 0..400) cancelNotificationAlarm(am, id)
                                for (id in 10000..11000) cancelNotificationAlarm(am, id)
                                for (id in 99990..100000) cancelNotificationAlarm(am, id)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("CANCEL_ALL_NOTIF_ALARM_FAILED", e.message, null)
                            }
                        }.start()
                    }
                    "getPendingAlarmLabel" -> {
                        val label = pendingAlarmLabel
                        pendingAlarmLabel = null
                        result.success(label)
                    }
                    "getTotalRamBytes" -> {
                        try {
                            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                            val mi = ActivityManager.MemoryInfo()
                            am.getMemoryInfo(mi)
                            result.success(mi.totalMem)
                        } catch (e: Exception) {
                            result.success(-1L)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun appendLog(msg: String) = AlarmLog.error(this, msg)

    private fun logInfo(msg: String) = AlarmLog.info(this, msg)

    private fun readLog(): String = AlarmLog.read(this)

    private fun clearLog() = AlarmLog.clear(this)

    private fun stopAlarmInternal() {
        try {
            alarmPlayer?.stop()
            alarmPlayer?.release()
        } catch (_: Exception) {
        }
        alarmPlayer = null
        try {
            alarmVibrator?.cancel()
        } catch (_: Exception) {
        }
        alarmVibrator = null
    }

    private fun nativePendingIntent(id: Int): PendingIntent {
        val intent = Intent(this, AlarmReceiver::class.java)
        return PendingIntent.getBroadcast(
            this, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun cancelNotificationAlarm(am: AlarmManager, id: Int) {
        try {
            val intent = Intent(
                this,
                com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver::class.java
            )
            val pi = PendingIntent.getBroadcast(
                this, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.cancel(pi)
        } catch (_: Exception) {
        }
    }
}
