// app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/Haptics.kt
package com.daoban.shiftassistantpro

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.annotation.RequiresApi

/**
 * App 的触觉出口（原生侧）。Dart 侧是 `lib/core/haptics.dart`，两边靠
 * `com.daoban.shiftassistantpro/haptics` 通道的 `play(level)` 相连，
 * `level` 取 [SELECT] / [COMMIT] / [MODE_ENTER]。
 *
 * **没有一行厂商判断。** 走的是 AOSP 标准三档能力阶梯，越靠前越好：
 *
 *   ① `VibrationEffect.startComposition()` 原语（API 31+，设备支持时）——
 *      Pixel / 三星这类新机的系统 UI 走的就是这条路，最脆最跟手；
 *   ② 预定义效果 `EFFECT_CLICK` / `EFFECT_HEAVY_CLICK`（API 26+）——
 *      **各品牌 HAL 自己调好的波形**，换台手机得到的是那台手机自己的「咔哒」；
 *   ③ `performHapticFeedback(LONG_PRESS)`（20ms 单次）—— 前两条都不认时的兜底。
 *
 * 一路走到哪一档由设备能力决定，`logCapabilities()` 会把结论写进「查看日志」，
 * 换品牌排查时不用猜。
 *
 * **为什么不直接用 Flutter 的 `HapticFeedback.*`**：它落到 `performHapticFeedback`，
 * 走 AOSP 的「常量 → 预定义效果」表。表里 `CLOCK_TICK`（Dart 侧 `selectionClick`）
 * 请求的是 `EFFECT_TEXTURE_TICK`，而这台小米机（25102RKBEC，HyperOS）的 HAL 不支持，
 * 于是回退成 `EFFECT_TICK`（一次 70ms）—— `dumpsys vibrator_manager` 的 Recent
 * vibrations 里逐条写着 `original: Prebaked=TEXTURE_TICK` / `played: Prebaked=TICK`，
 * 手感就是「转子嗡嗡」。同一份记录里 MIUI 桌面按图标是 `Prebaked=CLICK`。
 *
 * **系统设置要自己尊重**：直接调 `Vibrator` 绕过了 `performHapticFeedback` 自带的那道
 * 「触摸时振动」闸门，所以这里先读 `HAPTIC_FEEDBACK_ENABLED`，关掉时一声都不发。
 * App 自己的开关在 Dart 侧（`hapticsDisabled`），两边各管一层。
 */
object Haptics {
    /** 选中变了（开关、胶囊段、选择器）。 */
    const val SELECT = "select"

    /** 动作落实（删除确认、应用改班）。 */
    const val COMMIT = "commit"

    /** 进入一个模式（长按进多选）。 */
    const val MODE_ENTER = "modeEnter"

    /**
     * 26~33 没有 `VibrationAttributes.USAGE_TOUCH`（那是 API 34 才有）。
     *
     * 用 `AudioAttributes` 的「辅助提示音」归类，系统会把它当成**硬件反馈**
     * （等同于触摸），而不是 `UNKNOWN` —— 否则部分 ROM 会按媒体/未知去套强度，
     * 同一个手势在不同机器上忽大忽小。
     */
    private val SONIFICATION_ATTRIBUTES: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    /**
     * 播一记对应档位的触觉。
     *
     * [view] 只用于两件事：取 Context，以及前两档都不认时退回
     * `performHapticFeedback`（那条路要一个挂着的 View）。调用方传
     * `window.decorView` 即可。
     */
    fun play(view: View, level: String) {
        val context = view.context
        if (!touchFeedbackEnabled(context)) return
        val vibrator = vibrator(context) ?: return
        if (!vibrator.hasVibrator()) return

        // 三档只挑两种手感：选中是「咔哒」，落实/进模式是更重的一记。
        val heavy = level == COMMIT || level == MODE_ENTER

        // ① Composition 原语：设备认的话这里最好。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            playPrimitive(context, vibrator, heavy)
        ) {
            return
        }

        // ② 预定义效果：各品牌 HAL 自己调好的波形（本机型走的是这一档）。
        val effectId = if (heavy) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                VibrationEffect.EFFECT_HEAVY_CLICK
            } else {
                VibrationEffect.EFFECT_CLICK
            }
        } else {
            VibrationEffect.EFFECT_CLICK
        }
        if (effectSupported(vibrator, effectId) &&
            playEffect(context, vibrator, VibrationEffect.createPredefined(effectId))
        ) {
            return
        }

        // ③ 兜底：设备不认识预定义效果（个别 OEM 的 HAL 只支持 oneshot）时，
        // 退回 AOSP 的 LONG_PRESS —— 20ms 单次，比「不震」和「70ms 长震」都强。
        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
    }

    /**
     * ① 原语：`heavy` 时优先 THUD（更闷更重），否则 CLICK；设备一个都不认就返回
     * false，让调用方落到下一档。
     */
    @RequiresApi(Build.VERSION_CODES.S)
    private fun playPrimitive(context: Context, vibrator: Vibrator, heavy: Boolean): Boolean {
        return try {
            val click = VibrationEffect.Composition.PRIMITIVE_CLICK
            val thud = VibrationEffect.Composition.PRIMITIVE_THUD
            val primitive = when {
                heavy && vibrator.areAllPrimitivesSupported(thud) -> thud
                vibrator.areAllPrimitivesSupported(click) -> click
                else -> return false
            }
            val effect = VibrationEffect.startComposition()
                .addPrimitive(primitive, 1.0f)
                .compose()
            playEffect(context, vibrator, effect)
        } catch (e: Exception) {
            AlarmLog.error(context, "Haptics: 原语播放失败: ${e.message}")
            false
        }
    }

    /** 系统的「触摸时振动」。读不到时按开着办（宁可多响一下，也别静默全没）。 */
    private fun touchFeedbackEnabled(context: Context): Boolean = try {
        Settings.System.getInt(
            context.contentResolver,
            Settings.System.HAPTIC_FEEDBACK_ENABLED,
            1
        ) != 0
    } catch (_: Exception) {
        true
    }

    /** API 31 起走 `VibratorManager`；更早的版本只有 `VIBRATOR_SERVICE`。 */
    private fun vibrator(context: Context): Vibrator? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    } catch (_: Exception) {
        null
    }

    /**
     * 这台设备认不认这个预定义效果。
     *
     * `UNKNOWN` 不算「不支持」—— 有些 HAL 只是答不上来，真播一次通常没问题；
     * 只有明确的 `NO` 才让位给 fallback。
     */
    private fun effectSupported(vibrator: Vibrator, effectId: Int): Boolean = try {
        vibrator.areAllEffectsSupported(effectId) != Vibrator.VIBRATION_EFFECT_SUPPORT_NO
    } catch (_: Exception) {
        true
    }

    /**
     * 真正发出去，并告诉系统「这是一次触摸反馈」。
     *
     * API 34 起用 `VibrationAttributes.USAGE_TOUCH`（与 `performHapticFeedback`
     * 同一口径，用户设的触感强度才吃得到）；26~33 没有这个常量，退到
     * [SONIFICATION_ATTRIBUTES] 把归类打成硬件反馈。
     */
    private fun playEffect(
        context: Context,
        vibrator: Vibrator,
        effect: VibrationEffect,
    ): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val attributes = VibrationAttributes.Builder()
                .setUsage(VibrationAttributes.USAGE_TOUCH)
                .build()
            vibrator.vibrate(effect, attributes)
        } else {
            vibrator.vibrate(effect, SONIFICATION_ATTRIBUTES)
        }
        true
    } catch (e: Exception) {
        // 没有振动器 / 被系统策略拦掉：触觉失败不该影响功能，静默降级。
        AlarmLog.error(context, "Haptics: 播放失败: ${e.message}")
        false
    }

    /**
     * 把这台机器的振动能力写进「我的 → 查看日志」。
     *
     * 换品牌排查时最想知道的就是这些：认不认预定义效果、有没有 Composition
     * 原语、有没有振幅控制 —— 它们共同决定 [play] 实际走到哪一档。写文件而不是
     * 只打 Logcat，是因为用户换机后不一定有 adb。
     */
    fun logCapabilities(context: Context) {
        try {
            val sb = StringBuilder("Haptics: sdk=${Build.VERSION.SDK_INT}")
            val v = vibrator(context)
            if (v == null || !v.hasVibrator()) {
                AlarmLog.diagnostic(context, "$sb, 没有振动器（触觉全部静默）")
                return
            }
            sb.append(", 振幅控制=${v.hasAmplitudeControl()}")

            val click = VibrationEffect.EFFECT_CLICK
            val heavy = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                VibrationEffect.EFFECT_HEAVY_CLICK
            } else {
                VibrationEffect.EFFECT_CLICK
            }
            val effects = v.areEffectsSupported(click, heavy)
            sb.append(", 预定义[CLICK=${supportName(effects.getOrNull(0))}")
            sb.append(", HEAVY_CLICK=${supportName(effects.getOrNull(1))}]")

            var primitiveOk = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val prims = tryPrimitives(v)
                primitiveOk = prims
                sb.append(", 原语[CLICK/THUD 任一可播=$prims]")
            }

            val effectOk = effects.getOrNull(0) != Vibrator.VIBRATION_EFFECT_SUPPORT_NO
            val path = when {
                primitiveOk -> "原语"
                effectOk -> "预定义效果"
                else -> "performHapticFeedback 兜底"
            }
            sb.append(", 实际路径=$path")
            AlarmLog.diagnostic(context, sb.toString())
        } catch (e: Exception) {
            // 诊断本身失败不该影响任何功能。
            AlarmLog.error(context, "Haptics: 能力探测失败: ${e.message}")
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun tryPrimitives(vibrator: Vibrator): Boolean = try {
        vibrator.areAllPrimitivesSupported(
            VibrationEffect.Composition.PRIMITIVE_CLICK
        ) || vibrator.areAllPrimitivesSupported(
            VibrationEffect.Composition.PRIMITIVE_THUD
        )
    } catch (_: Exception) {
        false
    }

    private fun supportName(value: Int?): String = when (value) {
        Vibrator.VIBRATION_EFFECT_SUPPORT_YES -> "YES"
        Vibrator.VIBRATION_EFFECT_SUPPORT_NO -> "NO"
        else -> "UNKNOWN"
    }
}
