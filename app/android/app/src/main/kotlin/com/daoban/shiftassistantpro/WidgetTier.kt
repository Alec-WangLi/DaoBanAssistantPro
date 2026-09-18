package com.daoban.shiftassistantpro

/**
 * 三档尺寸。
 *
 * 阈值按本机（400dp 宽、MIUI 4 列网格）估算：2×2 ≈ 180×180dp、4×2 ≈ 380×180dp、
 * 4×4 ≈ 380×380dp。**上线前必须真机标定一次** —— ShiftWidgetProvider 会把每次
 * 刷新时实测的 dp 打进 `AlarmLog.info`，`adb logcat -s ShiftAssistant` 读回来
 * 对着三档各拉一次，再回来定死这里。
 *
 * ⚠️ 高度闸门不是保险，是必需的：4×1 那种尺寸宽度轻松过 300，但只有 ~86dp 高，
 * 三行装不下会**静默裁掉最后一行** —— 这正是 `info_card_metrics.dart` 那条注释
 * 里踩过的坑。所以两档都是「宽**且**高」。
 */
enum class WidgetTier {
    /** 今天一张牌。 */
    SMALL,

    /** 未来三天。 */
    MEDIUM,

    /** 一周一览（4×4 网格）。 */
    LARGE;

    companion object {
        const val MEDIUM_MIN_WIDTH_DP = 220
        const val MEDIUM_MIN_HEIGHT_DP = 130
        const val LARGE_MIN_WIDTH_DP = 300
        const val LARGE_MIN_HEIGHT_DP = 260

        fun pick(widthDp: Int, heightDp: Int): WidgetTier = when {
            widthDp >= LARGE_MIN_WIDTH_DP && heightDp >= LARGE_MIN_HEIGHT_DP -> LARGE
            widthDp >= MEDIUM_MIN_WIDTH_DP && heightDp >= MEDIUM_MIN_HEIGHT_DP -> MEDIUM
            else -> SMALL
        }
    }
}
