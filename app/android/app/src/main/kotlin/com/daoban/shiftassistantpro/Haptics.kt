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
 *   ① `VibrationEffect.startComposition()` 原语（API **30**+，设备支持时）——
 *      Pixel / 三星这类新机的系统 UI 走的就是这条路，最脆最跟手；
 *   ② 预定义效果 `EFFECT_CLICK` / `EFFECT_HEAVY_CLICK`（API 29+）——
 *      **各品牌 HAL 自己调好的波形**，换台手机得到的是那台手机自己的「咔哒」；
 *   ③ `performHapticFeedback(LONG_PRESS)`（20ms 单次）—— 前两条都不认时的兜底。
 *
 * 一路走到哪一档由设备能力决定，`logCapabilities()` 会把结论写进「查看日志」，
 * 换品牌排查时不用猜。
 *
 * **两条铁律（v0.13.11 用两台真机换来的）：**
 *
 *   1. **每个 API 30+ 的调用都要有 `SDK_INT` 门槛。** 门槛不是照感觉写的，按
 *      `platforms/android-34/data/api-versions.xml` 抄：`areEffectsSupported` /
 *      `areAllEffectsSupported` / `areAllPrimitivesSupported` / `startComposition` /
 *      `VibrationEffect.Composition` 都是 **30**（只有 `PRIMITIVE_THUD` 是 31），
 *      `createPredefined` 是 **29**。写错一档的代价见第 2 条。
 *   2. **所有 `catch` 都抓 `Throwable`，不抓 `Exception`。** 设备缺方法时抛的是
 *      `NoSuchMethodError` —— 它属于 `Error`，`catch (e: Exception)` 一个都接不住。
 *      v0.13.10 就是让 `logCapabilities()` 在启动路径上无门槛地调了 API 30 的
 *      `areEffectsSupported`：荣耀 10（COL-AL10）与畅享 20 Pro（DVC-AN20）都是
 *      HarmonyOS 3.0（底子 Android 10 / API 29），冷启动直接白屏闪退，而 `catch
 *      (Exception)` 眼睁睁看着它冒到主线程。触觉是 fire-and-forget 的东西，
 *      任何失败都不许把进程带下去。
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
     *
     * **这里兜 `Throwable`**：`play` 是从 MethodChannel 的 handler 里同步调的，
     * 一冒出去就是主线程未捕获异常。缺 API 抛的是 `Error`，不是 `Exception`。
     */
    fun play(view: View, level: String) {
        try {
            playLadder(view, level)
        } catch (t: Throwable) {
            AlarmLog.error(
                view.context,
                "Haptics: 播放失败: ${t.javaClass.simpleName}: ${t.message}"
            )
        }
    }

    /** 能力阶梯本体。任何一步失败都往下走一档，绝不抛出。 */
    private fun playLadder(view: View, level: String) {
        val context = view.context
        if (!touchFeedbackEnabled(context)) return
        val vibrator = vibrator(context) ?: return
        if (!vibrator.hasVibrator()) return

        // 三档只挑两种手感：选中是「咔哒」，落实/进模式是更重的一记。
        val heavy = level == COMMIT || level == MODE_ENTER

        // ① Composition 原语。门槛是 **30**（R），不是 31 —— 类与
        //    startComposition 都是 API 30 进的公共 API（见文件头铁律 1）。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            playPrimitive(context, vibrator, heavy)
        ) {
            return
        }

        // ② 预定义效果：各品牌 HAL 自己调好的波形（本机型走的是这一档）。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val effectId = if (heavy) {
                VibrationEffect.EFFECT_HEAVY_CLICK
            } else {
                VibrationEffect.EFFECT_CLICK
            }
            if (effectSupported(vibrator, effectId) &&
                playEffect(context, vibrator, VibrationEffect.createPredefined(effectId))
            ) {
                return
            }
        } else {
            // Android 8 / 9：没有 EFFECT_* 也没有 createPredefined（都是 API 29）。
            // 直调同样是 NoSuchMethodError，所以这里改发 20ms 单次 —— 与第 ③ 档
            // 的 LONG_PRESS 同一量级，但走的是 Vibration 服务，更稳。
            if (playEffect(
                    context,
                    vibrator,
                    VibrationEffect.createOneShot(20, VibrationEffect.DEFAULT_AMPLITUDE)
                )
            ) {
                return
            }
        }

        // ③ 兜底：设备不认识预定义效果（个别 OEM 的 HAL 只支持 oneshot）时，
        // 退回 AOSP 的 LONG_PRESS —— 20ms 单次，比「不震」和「70ms 长震」都强。
        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
    }

    /**
     * ① 原语：`heavy` 时优先 THUD（更闷更重；THUD 是 API 31 才有的原语），
     * 否则 CLICK；设备一个都不认就返回 false，让调用方落到下一档。
     */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun playPrimitive(context: Context, vibrator: Vibrator, heavy: Boolean): Boolean {
        return try {
            val click = VibrationEffect.Composition.PRIMITIVE_CLICK
            val thud = VibrationEffect.Composition.PRIMITIVE_THUD
            val primitive = when {
                heavy && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    vibrator.areAllPrimitivesSupported(thud) -> thud
                vibrator.areAllPrimitivesSupported(click) -> click
                else -> return false
            }
            val effect = VibrationEffect.startComposition()
                .addPrimitive(primitive, 1.0f)
                .compose()
            playEffect(context, vibrator, effect)
        } catch (t: Throwable) {
            AlarmLog.error(
                context,
                "Haptics: 原语播放失败: ${t.javaClass.simpleName}: ${t.message}"
            )
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
    } catch (_: Throwable) {
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
    } catch (_: Throwable) {
        null
    }

    /**
     * 这台设备认不认这个预定义效果。
     *
     * `UNKNOWN` 不算「不支持」—— 有些 HAL 只是答不上来，真播一次通常没问题；
     * 只有明确的 `NO` 才让位给 fallback。
     *
     * **API 30 以下不探测**：`areAllEffectsSupported` 与
     * `VIBRATION_EFFECT_SUPPORT_*` 都是 API 30 的公共 API；在 Android 8~10 上它
     * 只是个签名可能对不上的隐藏方法，赌它存在的代价就是 v0.13.10 那次闪退。
     */
    private fun effectSupported(vibrator: Vibrator, effectId: Int): Boolean = try {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            true
        } else {
            vibrator.areAllEffectsSupported(effectId) !=
                Vibrator.VIBRATION_EFFECT_SUPPORT_NO
        }
    } catch (_: Throwable) {
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
    } catch (t: Throwable) {
        // 没有振动器 / 被系统策略拦掉：触觉失败不该影响功能，静默降级。
        AlarmLog.error(
            context,
            "Haptics: 播放失败: ${t.javaClass.simpleName}: ${t.message}"
        )
        false
    }

    /**
     * 把这台机器的振动能力写进「我的 → 查看日志」。
     *
     * 换品牌排查时最想知道的就是这些：认不认预定义效果、有没有 Composition
     * 原语、有没有振幅控制 —— 它们共同决定 [play] 实际走到哪一档。写文件而不是
     * 只打 Logcat，是因为用户换机后不一定有 adb。
     *
     * **整段兜 `Throwable`**：它在 `configureFlutterEngine` 里同步跑，也就是
     * **冷启动的必经之路**。诊断信息再有用，也不值得让 App 起不来 ——
     * v0.13.10 在 HarmonyOS 3.0 上就是这么白屏闪退的。
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

            // 下面这一整段都是 API 30+：在 Android 8~10 上只能记「未知」，
            // 不许调用（见 [effectSupported] 的注释）。
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                sb.append(", 预定义=未知（低于 API 30，未探测）")
                sb.append(", 实际路径=预定义效果（API 29）/ 20ms 单次（26~28）")
                AlarmLog.diagnostic(context, sb.toString())
                return
            }

            val click = VibrationEffect.EFFECT_CLICK
            val heavy = VibrationEffect.EFFECT_HEAVY_CLICK
            val effects = v.areEffectsSupported(click, heavy)
            sb.append(", 预定义[CLICK=${supportName(effects.getOrNull(0))}")
            sb.append(", HEAVY_CLICK=${supportName(effects.getOrNull(1))}]")

            val primitiveOk = tryPrimitives(v)
            sb.append(", 原语[CLICK/THUD 任一可播=$primitiveOk]")

            val effectOk = effects.getOrNull(0) != Vibrator.VIBRATION_EFFECT_SUPPORT_NO
            val path = when {
                primitiveOk -> "原语"
                effectOk -> "预定义效果"
                else -> "performHapticFeedback 兜底"
            }
            sb.append(", 实际路径=$path")
            AlarmLog.diagnostic(context, sb.toString())
        } catch (t: Throwable) {
            // 诊断本身失败不该影响任何功能，更不该影响启动。
            AlarmLog.error(
                context,
                "Haptics: 能力探测失败: ${t.javaClass.simpleName}: ${t.message}"
            )
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun tryPrimitives(vibrator: Vibrator): Boolean = try {
        val click = vibrator.areAllPrimitivesSupported(
            VibrationEffect.Composition.PRIMITIVE_CLICK
        )
        // THUD 是 API 31 才有的原语，30 的机器上不要去问。
        val thud = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            vibrator.areAllPrimitivesSupported(
                VibrationEffect.Composition.PRIMITIVE_THUD
            )
        click || thud
    } catch (_: Throwable) {
        false
    }

    private fun supportName(value: Int?): String = when (value) {
        Vibrator.VIBRATION_EFFECT_SUPPORT_YES -> "YES"
        Vibrator.VIBRATION_EFFECT_SUPPORT_NO -> "NO"
        else -> "UNKNOWN"
    }
}
