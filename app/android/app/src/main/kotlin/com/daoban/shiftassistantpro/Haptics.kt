// app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/Haptics.kt
package com.daoban.shiftassistantpro

import android.content.Context
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.View

/**
 * App 的触觉出口（原生侧）。Dart 侧是 `lib/core/haptics.dart`，两边靠
 * `com.daoban.shiftassistantpro/haptics` 通道的 `play(level)` 相连，
 * `level` 取 [SELECT] / [COMMIT] / [MODE_ENTER]。
 *
 * **为什么不直接让 Flutter 调 `HapticFeedback.*`**：那几条最终落到
 * `View.performHapticFeedback`，走 AOSP 的「常量 → 预定义效果」表。表里
 * `CLOCK_TICK`（Dart 侧 `selectionClick`）请求的是 `EFFECT_TEXTURE_TICK`，
 * 而这台小米机的 HAL 不支持它 —— 系统静默回退成 `EFFECT_TICK`（一次 70ms），
 * 手感是「转子嗡嗡」。2026-11-10 用 `dumpsys vibrator_manager` 的
 * Recent vibrations 逐条核对过：
 *
 *     performHapticFeedback(constant=4)
 *       original: Prebaked=TEXTURE_TICK  played: Prebaked=TICK
 *
 * 这里改为直接点播设备**自己调好的**预定义效果（`EFFECT_CLICK` /
 * `EFFECT_HEAVY_CLICK`）。同一份记录里 MIUI 桌面按图标是 `Prebaked=CLICK`，
 * 输入法按键是 `Prebaked=THUD` —— 都是 HAL 里按机型调过的短波形，这才是
 * 「系统自己适配好的那种疙瘩感」的来源。
 *
 * **系统设置要自己尊重**：直接调 `Vibrator` 绕过了 `performHapticFeedback`
 * 自带的那道「触摸时振动」闸门，所以这里先读 `HAPTIC_FEEDBACK_ENABLED`，
 * 关掉时一声都不发。App 自己的开关在 Dart 侧（`hapticsDisabled`），两边各管一层。
 */
object Haptics {
    /** 选中变了（开关、胶囊段、选择器）。 */
    const val SELECT = "select"

    /** 动作落实（删除确认、应用改班）。 */
    const val COMMIT = "commit"

    /** 进入一个模式（长按进多选）。 */
    const val MODE_ENTER = "modeEnter"

    /**
     * 播一记对应档位的触觉。
     *
     * [view] 只用于两件事：取 Context，以及在设备不支持预定义效果时退回
     * `performHapticFeedback`（那条路要一个挂着的 View）。调用方传
     * `window.decorView` 即可。
     */
    fun play(view: View, level: String) {
        val context = view.context
        if (!touchFeedbackEnabled(context)) return
        val vibrator = vibrator(context) ?: return
        if (!vibrator.hasVibrator()) return

        // 三档只挑两种波形：选中是「咔哒」，落实/进模式是更实的「咔哒」。
        // 这是 HAL 调好的预定义效果，强到能分清档位，又不至于变成噪音。
        val effectId = if (level == COMMIT || level == MODE_ENTER) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                VibrationEffect.EFFECT_HEAVY_CLICK
            } else {
                VibrationEffect.EFFECT_CLICK
            }
        } else {
            VibrationEffect.EFFECT_CLICK
        }

        if (effectSupported(vibrator, effectId) && vibrate(context, vibrator, effectId)) {
            return
        }

        // 设备不认识预定义效果（个别 OEM 的 HAL 只支持 oneshot）：退回 AOSP 的
        // LONG_PRESS —— 20ms 单次，比「不震」和「70ms 长震」都强。
        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
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
     * 真正发出去。API 34 起带 `USAGE_TOUCH` —— 系统据此套用用户设定的触感强度，
     * 与 `performHapticFeedback` 同一口径（旧记录里 usage 就是 TOUCH）。
     */
    private fun vibrate(context: Context, vibrator: Vibrator, effectId: Int): Boolean = try {
        val effect = VibrationEffect.createPredefined(effectId)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val attributes = VibrationAttributes.Builder()
                .setUsage(VibrationAttributes.USAGE_TOUCH)
                .build()
            vibrator.vibrate(effect, attributes)
        } else {
            vibrator.vibrate(effect)
        }
        true
    } catch (e: Exception) {
        // 没有振动器 / 被系统策略拦掉：触觉失败不该影响功能，静默降级。
        AlarmLog.error(context, "Haptics: 播放预定义效果 $effectId 失败: ${e.message}")
        false
    }
}
