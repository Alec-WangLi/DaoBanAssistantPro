package com.daoban.shiftassistantpro

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri

/**
 * 响铃音源：把「放哪个声音」这件事收在一处，两条响铃链路（App 前台时的
 * `MainActivity.startAlarm`、后台/锁屏时的 `AlarmRingService`）共用。
 *
 * 做两件有分量的事：
 *  1. **自选铃声坏了就回落到内置铃声**（见 [start]）。
 *  2. **认「仅震动」这个哨兵**（见 [VIBRATE_ONLY]）。
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

    /** 内置铃声（`res/raw/alarm_beep`）的 URI。 */
    fun builtinUri(context: Context): Uri =
        Uri.parse("android.resource://${context.packageName}/raw/alarm_beep")

    /**
     * 起一个循环播放、走闹钟音频流（不受静音键影响）的 [MediaPlayer]。
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
    fun start(context: Context, uriStr: String?): MediaPlayer? {
        if (uriStr == VIBRATE_ONLY) {
            AlarmLog.info(context, "AlarmSound: 仅震动，不发声")
            return null
        }
        if (!uriStr.isNullOrEmpty()) {
            tryCreate(context, Uri.parse(uriStr))?.let {
                AlarmLog.info(context, "AlarmSound: 使用自选铃声 $uriStr")
                return it
            }
            AlarmLog.error(
                context,
                "AlarmSound: 自选铃声用不了，回落到内置铃声: $uriStr"
            )
        }
        val mp = tryCreate(context, builtinUri(context))
        if (mp == null) {
            AlarmLog.error(context, "AlarmSound: 内置铃声也起不来（raw/alarm_beep 缺失？）")
        }
        return mp
    }

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
            mp.start()
            mp
        } catch (e: Exception) {
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
