package com.daoban.shiftassistantpro

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri

/**
 * 响铃音源：把「放哪个声音」这件事收在一处，两条响铃链路（App 前台时的
 * `MainActivity.startAlarm`、后台/锁屏时的 `AlarmRingService`）共用。
 *
 * 只做一件有分量的事：**自选铃声坏了就回落到内置铃声**。
 *
 * 用户自选的铃声是复制进 `filesDir/ringtone/` 的文件，它可能损坏、被清理工具
 * 删掉、或者在换机恢复后失效。原先两处都是把 `setDataSource`/`prepare` 整个
 * 包在 `catch (_: Exception) {}` 里 —— 出问题时**一点声音都没有**，而闹钟不响
 * 是用户最不可能原谅的失败方式，且失败发生在半夜、没有任何界面能报错。
 * 回落之后最差也只是响成内置铃声。
 */
object AlarmSound {

    /** 内置铃声（`res/raw/alarm_beep`）的 URI。 */
    fun builtinUri(context: Context): Uri =
        Uri.parse("android.resource://${context.packageName}/raw/alarm_beep")

    /**
     * 起一个循环播放、走闹钟音频流（不受静音键影响）的 [MediaPlayer]。
     *
     * [uriStr] 非空时先试它，失败就回落到内置铃声。两条路都失败（内置资源缺失
     * 等极端情况）返回 null，由调用方决定怎么办。
     */
    fun start(context: Context, uriStr: String?): MediaPlayer? {
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
