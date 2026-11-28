package com.daoban.shiftassistantpro

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/**
 * 响铃音源：把「放哪个声音」这件事收在一处，两条响铃链路（App 前台时的
 * `MainActivity.startAlarm`、后台/锁屏时的 `AlarmRingService`）共用。
 *
 * 做三件有分量的事：
 *  1. **自选铃声坏了就回落到内置铃声**（见 [start]）。
 *  2. **认「仅震动」这个哨兵**（见 [VIBRATE_ONLY]）。
 *  3. **渐响**（见 [Playback]）：开关打开时音量从 0 升到 1，而不是一上来
 *     就是最大声。
 */
object AlarmSound {

    /**
     * 「仅震动」——响铃时**不发声**，只有震动。
     *
     * 它和 `ringtoneUri` 存在**同一个键**里（SharedPreferences），值就是这个常量，
     * 因为整条链路（prefs → `MainActivity.scheduleNativeAlarm` → `AlarmScheduler`
     * 的 Intent extra → `AlarmReceiver` → `AlarmRingService`）本来就是一路的字符串，
     * 再加一个布尔开关要同时改这五处、还要改 `AlarmStore` 的重启重排记录。
     * 哨兵不可能与真实音源撞上：系统铃声是 `content://`、自选是 `file://`。
     *
     * ⚠️ **不能拿空串/`null` 表示「不发声」**：那两值在 [start] 里的含义是
     * 「没配 → 用内置铃声」，拿它们当静音会**静静地响一声** —— 用户要静音却响了，
     * 比不响更糟。这也是为什么要在 [start] 的最前面判它。
     *
     * Dart 侧同一个值在 `alarm_service.dart` 的 `AlarmService.vibrateOnlyRingtone`。
     */
    const val VIBRATE_ONLY = "vibrateOnly"

    /**
     * 渐响时长：0 → 1 用 20 秒。
     *
     * 这个数是拍的，不是量出来的：太短听不出「慢慢响」，太长又像闹钟没响 ——
     * 睡着的人可能把前十几秒睡过去了。到 1.0 之后就是原来那个音量，不再变化。
     */
    private const val FADE_IN_MS = 20_000L

    /** 渐响步长：100ms 一档，20 秒共 200 档，耳朵听不出台阶。 */
    private const val FADE_STEP_MS = 100L

    /**
     * 渐响开关在 SharedPreferences 里的键。
     *
     * Dart 的 `shared_preferences` 会给键加 `flutter.` 前缀（同 `flutter.ringtoneUri`，
     * 见 `MainActivity` 的 `scheduleNativeAlarm`），所以这里读的是带前缀的名字。
     */
    private const val FADE_IN_KEY = "flutter.fadeInRingtone"

    /**
     * 一次响铃的播放句柄：播放器 + 渐响计时器。
     *
     * **停止必须走 [stop]**，不要直接 `player.stop()` / `release()` —— 渐响还在跑
     * 的时候释放播放器，下一次 `setVolume` 会对着已经释放的 native 对象抛
     * `IllegalStateException`；而它抛在 Handler 里，用户看不见，只表现为渐响
     * 半路停住。
     */
    class Playback internal constructor(
        val player: MediaPlayer,
        private val handler: Handler?,
        private val ramp: Runnable?,
    ) {
        fun stop() {
            ramp?.let { handler?.removeCallbacks(it) }
            try {
                player.stop()
            } catch (_: Exception) {
            }
            try {
                player.release()
            } catch (_: Exception) {
            }
        }
    }

    /** 内置铃声（`res/raw/alarm_beep`）的 URI。 */
    fun builtinUri(context: Context): Uri =
        Uri.parse("android.resource://${context.packageName}/raw/alarm_beep")

    /**
     * 起一个循环播放、走闹钟音频流（不受静音键影响）的 [MediaPlayer]，并按开关
     * 决定是否渐响。
     *
     * [uriStr] 是 [VIBRATE_ONLY] 时**直接返回 null**（不发声，也不记错误 —— 这是
     * 用户选的正常状态，不是失败）；非空时先试它，失败就回落到内置铃声。
     * 两条路都失败（内置资源缺失等极端情况）也返回 null。
     *
     * **为什么要回落**：用户自选的铃声是复制进 `filesDir/ringtone/` 的文件，它可能
     * 损坏、被清理工具删掉、或在换机恢复后失效。原先两处都是把 `setDataSource`/
     * `prepare` 整个包在 `catch (_: Exception) {}` 里 —— 出问题时**一点声音都没有**，
     * 而闹钟不响是用户最不可能原谅的失败方式，且失败发生在半夜、没有任何界面能报错。
     * 回落之后最差也只是响成内置铃声。
     *
     * **返回 null 因此有两重含义**（用户选的静音 / 连内置都起不来），调用方拿到
     * null 时只需「不播放」即可，别把它当成错误上报 —— 判断谁是谁的日志在
     * 这里已经分开写了。
     */
    fun start(context: Context, uriStr: String?): Playback? {
        if (uriStr == VIBRATE_ONLY) {
            AlarmLog.info(context, "AlarmSound: 仅震动，不发声")
            return null
        }
        if (!uriStr.isNullOrEmpty()) {
            val uri = Uri.parse(uriStr)
            tryCreate(context, uri)?.let {
                AlarmLog.info(context, "AlarmSound: 使用自选铃声 $uriStr")
                return begin(context, it, uri)
            }
            AlarmLog.error(
                context,
                "AlarmSound: 自选铃声用不了，回落到内置铃声: $uriStr"
            )
        }
        val builtin = builtinUri(context)
        val mp = tryCreate(context, builtin)
        if (mp == null) {
            AlarmLog.error(context, "AlarmSound: 内置铃声也起不来（raw/alarm_beep 缺失？）")
            return null
        }
        return begin(context, mp, builtin)
    }

    /**
     * 真正起播。
     *
     * 渐响打开时**先把音量压到 0 再 start**：否则第一帧就是最大声，用户听到的
     * 仍然是「一开始就那么大声」，只是两秒后又被调小 —— 比不渐响更怪。
     */
    private fun begin(context: Context, mp: MediaPlayer, uri: Uri): Playback? {
        val fade = fadeEnabled(context)
        return try {
            if (fade) mp.setVolume(0f, 0f)
            mp.start()
            // 「响铃链路走到哪一步」的第三条证据（前两条在 AlarmReceiver 与
            // AlarmRingService）：有这一行 = 声音真的出声了，没有 = 音源或音频
            // 通道的问题。落盘才查得到，见 AlarmReceiver 那段的三种结果。
            //
            // 写法用 [describe] 而不是 `scheme://authority`：后者对自选铃声只会打出
            // 一句 `file://`（file 没有 authority），看着像坏了 —— 2026-11-22 那条
            // 报障日志里就是这么一行，读的人以为音源是空的。
            AlarmLog.diagnostic(context, "AlarmSound: 开始播放 ${describe(uri)}")
            if (fade) startRamp(mp) else Playback(mp, null, null)
        } catch (e: Exception) {
            AlarmLog.error(
                context,
                "AlarmSound: 起播失败 ${describe(uri)}：${e.javaClass.simpleName}: ${e.message}"
            )
            try {
                mp.release()
            } catch (_: Exception) {
            }
            null
        }
    }

    private fun fadeEnabled(context: Context): Boolean = try {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getBoolean(FADE_IN_KEY, false)
    } catch (_: Exception) {
        // 读不到就按「关」处理：渐响是锦上添花，不能因为它让闹钟不响。
        false
    }

    private fun startRamp(mp: MediaPlayer): Playback {
        val handler = Handler(Looper.getMainLooper())
        val startedAt = SystemClock.elapsedRealtime()
        val ramp = object : Runnable {
            override fun run() {
                val elapsed = SystemClock.elapsedRealtime() - startedAt
                val level = (elapsed.toFloat() / FADE_IN_MS).coerceIn(0f, 1f)
                val ok = try {
                    mp.setVolume(level, level)
                    true
                } catch (_: IllegalStateException) {
                    // 播放器已被别人停掉/释放：安静收工，别在 Handler 里崩。
                    false
                }
                if (ok && level < 1f) handler.postDelayed(this, FADE_STEP_MS)
            }
        }
        handler.postDelayed(ramp, FADE_STEP_MS)
        return Playback(mp, handler, ramp)
    }

    /**
     * 日志里的音源写法。
     *
     * 不用 `scheme://authority`：`file` 与 `android.resource` 都没有 authority，
     * 打出来是 `file://` / `android.resource://`，读日志的人会以为音源是空的
     * （2026-11-22 那条报障日志里正是「开始播放 file://」）。
     */
    private fun describe(uri: Uri): String = when (uri.scheme) {
        "android.resource" -> "内置"
        "file" -> "自选 ${uri.lastPathSegment ?: uri}"
        else -> "${uri.scheme}://${uri.authority}"
    }

    /**
     * 建好并 prepare，但**不 start** —— 起播交给 [begin]，因为渐响要在 start
     * 之前把音量压到 0。
     */
    private fun tryCreate(context: Context, uri: Uri): MediaPlayer? {
        val mp = MediaPlayer()
        return try {
            mp.setDataSource(context, uri)
            mp.isLooping = true
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            mp.prepare()
            mp
        } catch (e: Exception) {
            // **把原因写进日志文件**（2026-11-16）：以前这里一声不响地吞掉，
            // 于是「自选铃声用不了」在用户端只剩一句没有下文的提示 —— 分不清是
            // 没权限读、文件被删、还是格式不支持。用 `error` 而不是 `info`：
            // 这两处都会落盘，「查看日志」里才看得见。
            AlarmLog.error(
                context,
                "AlarmSound: 音源打不开 ${describe(uri)}：${e.javaClass.simpleName}: ${e.message}"
            )
            // 半路失败的 MediaPlayer 不能复用，也不能就这么丢掉（会泄漏一个
            // native 播放器），release 掉再让调用方回落。
            try {
                mp.release()
            } catch (_: Exception) {
            }
            null
        }
    }
}
