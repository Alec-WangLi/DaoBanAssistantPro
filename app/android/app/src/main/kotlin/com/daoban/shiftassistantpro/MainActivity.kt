package com.daoban.shiftassistantpro

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
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
import android.provider.OpenableColumns
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

        /**
         * 与 [pendingAlarmLabel] 配套的说明（标题下面那行）。班次/自定义闹钟为空，
         * 待办的联动闹钟会带上「9月15日 周二 · 14:30」这样一行。
         */
        var pendingAlarmDetail: String? = null

        /**
         * 由待办提醒的通知冷启动拉起时待处理的待办 id（Flutter 启动后读取）。
         * -1 = 没有。热启动不走这里，直接推 `onTodoTapped` 给已经在跑的 Dart。
         */
        var pendingTodoId: Int = -1

        /**
         * 冷启动由小组件拉起时待处理的「要跳到哪天」（`LocalDate.toEpochDay()`）。
         * -1 = 没有。热启动不走这里，直接推 `onWidgetDayTapped` 给已经在跑的 Dart
         * —— 与上面 `pendingTodoId` 完全同一套分界，理由见 `handleAlarmIntent`。
         */
        var pendingWidgetDay: Int = -1

        /** 自选铃声请求码 —— 与插件占用的请求码区分开。 */
        private const val REQ_PICK_RINGTONE = 40071

        /** 自选铃声在私有目录里的子目录名（`filesDir/ringtone/`）。 */
        const val RINGTONE_DIR = "ringtone"

        /**
         * 自选铃声的文件大小上限。铃声要整个复制进私有目录，用户误选一个几百 MB
         * 的整轨音频会白白占掉存储、还拖慢那次选择；给个上限并在界面上说清楚。
         */
        private const val MAX_RINGTONE_BYTES = 32L * 1024 * 1024
    }

    private val settingsChannel = "com.daoban.shiftassistantpro/settings"
    private var flutterChannel: MethodChannel? = null
    private var playingRingtone: android.media.Ringtone? = null
    private var alarmPlayer: MediaPlayer? = null
    private var alarmVibrator: Vibrator? = null

    /** 等文件选择器回来的那个 Flutter 回调（同一时刻只允许一个）。 */
    private var pendingRingtoneResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // 关键：必须在 setContentView（super.onCreate 内部）之前设置，锁屏冷启动才能点亮屏幕并显示
        applyShowWhenLocked(intent)
        super.onCreate(savedInstanceState)
        handleAlarmIntent(intent)
        handleWidgetIntent(intent)
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
        handleWidgetIntent(intent)
    }

    private fun applyShowWhenLocked(intent: Intent?) {
        val label = intent?.getStringExtra("alarm_label")
        if (label != null && Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            AlarmLog.info(this, "MainActivity: (onCreate 前) 已 setShowWhenLocked+setTurnScreenOn")
        }
    }

    /**
     * 撤掉「盖在锁屏上」的状态 —— 与 [applyShowWhenLocked] 成对。
     *
     * `setShowWhenLocked(true)` 是**只进不出**的：不显式关掉，这个 Activity 会一直
     * 处于「可以盖在锁屏上」的状态，直到进程被杀。后果是用户关掉响铃界面之后，露
     * 出来的是 **App 主界面**、锁屏回不来 —— 真人测试反馈，这也意味着锁屏下能直接
     * 看到并操作 App 内容。
     *
     * 响铃一停就撤掉这两个标志，系统会把锁屏盖回来，正好是「关掉响铃 → 回到锁屏」。
     */
    private fun exitLockScreenMode() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
            AlarmLog.info(this, "MainActivity: 已 setShowWhenLocked(false)+setTurnScreenOn(false)")
        }
    }

    /**
     * 小米机型的 App 权限页 —— 「后台弹出界面」「锁屏显示」这两项都在那里。
     *
     * 这不是标准 Android 权限：MIUI 的 `ActivityStarterImpl` 会**静默**拒绝从后台
     * 拉起 Activity（logcat 里只有一行 `MIUILOG- Permission Denied Activity`），
     * 表现就是闹钟只响、不弹界面。它没有公开 API，状态也读不到，只能把用户送到
     * 这个页面自己开。
     */
    private fun miuiPermissionEditor(): Intent =
        Intent("miui.intent.action.APP_PERM_EDITOR").apply {
            putExtra("extra_pkgname", packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    /** 这台机器上有没有那个页面（非小米机型解析不到）。 */
    private fun miuiPermissionPageAvailable(): Boolean = try {
        if (Build.VERSION.SDK_INT >= 33) {
            packageManager.resolveActivity(
                miuiPermissionEditor(), PackageManager.ResolveInfoFlags.of(0L)
            ) != null
        } else {
            @Suppress("DEPRECATION")
            (packageManager.resolveActivity(miuiPermissionEditor(), 0) != null)
        }
    } catch (_: Exception) {
        false
    }

    private fun handleAlarmIntent(intent: Intent?) {
        val label = intent?.getStringExtra("alarm_label")
        val detail = intent?.getStringExtra("alarm_detail")
        AlarmLog.info(
            this,
            "MainActivity.handleAlarmIntent: label=$label, ${AlarmLog.deviceState(this)}"
        )
        if (label != null) {
            // **只有 Dart 还没就绪（冷启动）时才暂存**，由它 init 时来取；热启动直接
            // 推过去就行。以前这里是无条件暂存的，而清空只发生在 `getPendingAlarm`
            // —— Dart 每次引擎启动只调那一次。于是热启动留下的值没人清：界面销毁重建
            // 时 Dart 会把这枚**陈旧的**值当成新闹钟读出来，再弹一次响铃界面，而且
            // 没有声音（根本没有闹钟在响）。与下面 todo_id 那段同一套写法。
            if (flutterChannel == null) {
                pendingAlarmLabel = label
                pendingAlarmDetail = detail
            }
            if (Build.VERSION.SDK_INT >= 27) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
                AlarmLog.info(this, "MainActivity: 已 setShowWhenLocked(true)+setTurnScreenOn(true)")
            }
            AlarmLog.info(this, "MainActivity: invokeMethod(onAlarmFired, $label)")
            // 两张牌一起给：响铃界面除了标题还要显示说明（待办的联动闹钟靠它
            // 交代「什么事、几点」）。
            flutterChannel?.invokeMethod(
                "onAlarmFired", mapOf("label" to label, "detail" to detail)
            )
        }

        // 待办提醒的通知被点开：冷启动时 Dart 还没就绪，先记下来由它 `init` 时取；
        // 热启动时 Dart 已经在跑，直接推给它（与闹钟的 onAlarmFired 同一套）。
        val todoId = intent?.getIntExtra("todo_id", -1) ?: -1
        if (todoId >= 0) {
            AlarmLog.info(this, "MainActivity: 收到待办提醒点击 todo_id=$todoId")
            if (flutterChannel == null) {
                pendingTodoId = todoId
            } else {
                flutterChannel?.invokeMethod("onTodoTapped", todoId)
            }
        }
    }

    private fun handleWidgetIntent(intent: Intent?) {
        // 小组件某一天那一格带过来的日期。单元是「自 epoch 的天数」，与 Dart 的
        // `dayNumber()` 同口径 —— 不传毫秒，省得两边为时区各算一遍。
        val day = intent?.getIntExtra("widget_day", -1) ?: -1
        if (day < 0) return
        AlarmLog.info(this, "MainActivity: 小组件点击 day=$day")
        if (flutterChannel == null) {
            pendingWidgetDay = day
        } else {
            flutterChannel?.invokeMethod("onWidgetDayTapped", day)
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
                    "checkMiuiPermissionPage" -> {
                        result.success(miuiPermissionPageAvailable())
                    }
                    "openMiuiPermissionPage" -> {
                        try {
                            startActivity(miuiPermissionEditor())
                            result.success(true)
                        } catch (e: Exception) {
                            // 解析得到不等于打得开（个别 ROM 会拦），失败让 Dart 侧
                            // 落回系统「应用信息」页，至少用户能自己翻到权限那一栏。
                            AlarmLog.error(
                                this,
                                "打开小米权限页失败: ${e.javaClass.name}: ${e.message}"
                            )
                            result.success(false)
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
                    "pickRingtoneFile" -> {
                        // 系统文件选择器（SAF）挑一个音频，选完**复制进应用私有
                        // 目录**再存路径。
                        //
                        // 不直接存选择器给的 `content://` URI：那种授权不持久，
                        // 重启或系统清理后被回收，闹钟到点会读不到 —— 而失败发生
                        // 在响铃那一刻，用户听不到任何错误提示。复制进私有目录就
                        // 没有这个问题，也不需要申请任何存储权限。
                        if (pendingRingtoneResult != null) {
                            result.error("PICK_IN_PROGRESS", "已有选择器在等待", null)
                        } else {
                            pendingRingtoneResult = result
                            try {
                                startActivityForResult(
                                    Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                        addCategory(Intent.CATEGORY_OPENABLE)
                                        type = "audio/*"
                                    },
                                    REQ_PICK_RINGTONE
                                )
                            } catch (e: Exception) {
                                pendingRingtoneResult = null
                                result.error("PICK_RINGTONE_FAILED", e.message, null)
                            }
                        }
                    }
                    "clearRingtoneFile" -> {
                        try {
                            File(filesDir, RINGTONE_DIR).listFiles()?.forEach { it.delete() }
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("CLEAR_RINGTONE_FAILED", e.message, null)
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
                            // 音源挑选与「自选铃声坏了回落内置」都在 AlarmSound 里
                            // （后台那条链路 AlarmRingService 用的是同一份）。
                            alarmPlayer = AlarmSound.start(
                                this, call.argument<String>("uri")
                            )

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
                        // 响铃结束，把「盖在锁屏上」一起撤掉：滑块关闭与「再睡一会」
                        // 两条路都走这里，主界面不会留在锁屏上。
                        exitLockScreenMode()
                        result.success(null)
                    }
                    "scheduleNativeAlarm" -> {
                        try {
                            val id = call.argument<Int>("id") ?: 0
                            val millis = call.argument<Long>("millis") ?: 0L
                            val label = call.argument<String>("label") ?: "闹钟"
                            val detail = call.argument<String>("detail")
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
                                repeatType, hour, minute, weekdays, detail
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
                            // 走 AlarmScheduler.cancel：排定记录与落盘清单一起撤。
                            // 直接 am.cancel 会在清单里留下一条幽灵闹钟。
                            AlarmScheduler.cancel(this, id)
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
                                // 清单一起清空：随后 Dart 会把要留的重新排一遍，
                                // 两份清单因此始终一致。
                                AlarmStore.clear(this)
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
                    "getPendingAlarm" -> {
                        // 冷启动那次：把标签与说明一起给出去，读完两个都清空。
                        val label = pendingAlarmLabel
                        val detail = pendingAlarmDetail
                        pendingAlarmLabel = null
                        pendingAlarmDetail = null
                        result.success(
                            if (label == null) null
                            else mapOf("label" to label, "detail" to detail)
                        )
                    }
                    "getPendingTodoId" -> {
                        val id = pendingTodoId
                        pendingTodoId = -1
                        result.success(if (id >= 0) id else null)
                    }
                    "widgetPushSnapshot" -> {
                        val json = call.argument<String>("json") ?: ""
                        if (json.isEmpty()) {
                            result.error("BAD_ARGS", "json 缺失", null)
                        } else {
                            WidgetStore.write(this, json)
                            ShiftWidgets.refreshAll(this)
                            result.success(true)
                        }
                    }
                    "getWidgetLaunchDay" -> {
                        val d = pendingWidgetDay
                        pendingWidgetDay = -1
                        result.success(if (d >= 0) d else null)
                    }
                    "scheduleTodoReminder" -> {
                        try {
                            val id = call.argument<Int>("id") ?: -1
                            val millis = call.argument<Long>("millis") ?: 0L
                            val title = call.argument<String>("title") ?: ""
                            val body = call.argument<String>("body") ?: ""
                            if (id < 0 || title.isEmpty()) {
                                result.error("BAD_ARGS", "id/title 缺失", null)
                            } else {
                                AlarmScheduler.scheduleQuiet(this, id, millis, title, body)
                                AlarmLog.info(
                                    this, "scheduleTodoReminder: id=$id, millis=$millis"
                                )
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            result.error("SCHEDULE_TODO_FAILED", e.message, null)
                        }
                    }
                    "cancelAllTodoReminders" -> {
                        // 与另外两个 cancelAll 一样放后台：一千次 PendingIntent 操作
                        // 会把主线程卡住（重排时正播着开关动画）。
                        Thread {
                            try {
                                AlarmScheduler.cancelTodoReminders(this)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("CANCEL_TODO_FAILED", e.message, null)
                            }
                        }.start()
                    }
                    "ensureTodoChannel" -> {
                        try {
                            TodoReminderReceiver.ensureChannel(
                                this, call.argument<String>("name")
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ENSURE_CHANNEL_FAILED", e.message, null)
                        }
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

    // -----------------------------------------------------------------------
    // 自选铃声：系统文件选择器 → 复制进私有目录
    // -----------------------------------------------------------------------

    /**
     * 文件选择器回来。[FlutterActivity] 是 `android.app.Activity`（不是
     * `ComponentActivity`），所以用不了 `registerForActivityResult`，只能走
     * `startActivityForResult` + 这个回调。
     *
     * **必须调 super**：插件的 onActivityResult 也走这里转发（通知权限、
     * 精确闹钟授权都要），漏掉会让那些插件的授权流程收不到结果。
     */
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK_RINGTONE) return
        val result = pendingRingtoneResult
        pendingRingtoneResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            // 用户按返回取消了：不是错误，回 null 让界面什么都不做。
            result?.success(null)
            return
        }
        // 复制是磁盘 I/O（一个音频文件可能十几 MB），放后台线程，拷完回主线程。
        Thread {
            var tooLarge = false
            val copied = try {
                copyRingtoneIntoPrivateDir(uri)
            } catch (e: RingtoneTooLargeException) {
                tooLarge = true
                null
            }
            runOnUiThread {
                // 错误码分开给：文件太大要在界面上说清是「太大」而不是「失败」，
                // 否则用户只会反复重试同一个文件。
                when {
                    tooLarge -> result?.error(
                        "RINGTONE_TOO_LARGE", "铃声文件太大", null
                    )
                    copied == null -> result?.error(
                        "COPY_RINGTONE_FAILED", "复制铃声文件失败", null
                    )
                    else -> result?.success(
                        mapOf("name" to copied.first, "uri" to copied.second)
                    )
                }
            }
        }.start()
    }

    /**
     * 把 [uri] 指向的音频复制到 `filesDir/ringtone/`，返回 (显示名, file:// URI)。
     * 失败返回 null；文件超过 [MAX_RINGTONE_BYTES] 抛 [RingtoneTooLargeException]。
     */
    private fun copyRingtoneIntoPrivateDir(uri: Uri): Pair<String, String>? {
        return try {
            val name = queryDisplayName(uri) ?: "ringtone"
            val size = queryFileSize(uri)
            if (size != null && size > MAX_RINGTONE_BYTES) {
                throw RingtoneTooLargeException(size)
            }
            val dir = File(filesDir, RINGTONE_DIR).apply { mkdirs() }
            // 只留一份：换铃声时把上一个删掉，别在私有目录里堆垃圾。
            dir.listFiles()?.forEach { it.delete() }
            val safe = name.replace(Regex("[^\\p{L}\\p{N}._-]"), "_").take(48)
            val dest = File(dir, safe)
            contentResolver.openInputStream(uri).use { input ->
                if (input == null) return null
                dest.outputStream().use { out -> input.copyTo(out) }
            }
            AlarmLog.info(this, "ringtone: 已复制 $name（$size 字节）到 $dest")
            name to Uri.fromFile(dest).toString()
        } catch (e: RingtoneTooLargeException) {
            AlarmLog.error(this, "ringtone: 文件太大，拒绝复制 ${e.bytes} 字节")
            throw e
        } catch (e: Exception) {
            AlarmLog.error(this, "ringtone: 复制失败 ${e.javaClass.name}: ${e.message}")
            null
        }
    }

    /** 文件选择器里那一项的显示名（`OpenableColumns.DISPLAY_NAME`）。 */
    private fun queryDisplayName(uri: Uri): String? = try {
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (i >= 0 && c.moveToFirst()) c.getString(i) else null
        }
    } catch (_: Exception) {
        null
    }

    /** 文件大小（读不到返回 null，由复制本身兜底）。 */
    private fun queryFileSize(uri: Uri): Long? = try {
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            val i = c.getColumnIndex(OpenableColumns.SIZE)
            if (i >= 0 && c.moveToFirst() && !c.isNull(i)) c.getLong(i) else null
        }
    } catch (_: Exception) {
        null
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

/** 自选的铃声文件超过 [MainActivity] 允许复制的上限。要单独一类错误码，用户才知道该换个文件。 */
class RingtoneTooLargeException(val bytes: Long) : Exception("ringtone too large: $bytes")
