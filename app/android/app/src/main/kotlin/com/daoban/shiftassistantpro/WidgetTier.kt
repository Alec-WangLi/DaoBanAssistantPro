package com.daoban.shiftassistantpro

/**
 * 五档尺寸。
 *
 * 阈值全部取自**真机实测**（2026-09-19 用户拖动演示，Redmi 25102RKBEC / 400dp 宽屏 /
 * 480dpi / 横向 4 列，小组件拉满 4 列时宽 328dp）。可达高度是**步长 95dp 的等差数列**：
 *
 * ```
 * 1 行 63   2 行 158   3 行 253   4 行 348   5 行 443   6 行 538   7 行 633  （dp）
 * ```
 *
 * 阈值取在**相邻实测值的中点**，这样任一档离边界至少 40dp，不会被一两个 dp 的抖动甩出去。
 *
 * ⚠️ **档位由高度决定，宽度只当网格的闸门。** 两个入参管的是两件事，别把它们混成一个
 * 「面积够大就上网格」的判断 —— 一个 60×633dp 的细长条面积很小但高度很高，它该走列表
 * 而不是网格。
 *
 * 上一版的教训（这一轮返工的全部起因）：那时只有三个阈值，而真机有七个可达高度，
 * 于是三个版式被摊到七个高度上、两个版式被拉伸。阈值是纯数字、没有编译期保护，
 * 所以配了一条 Dart 护栏测试（`app/test/widget_tier_thresholds_test.dart`）——
 * 它读本文件里的常量、在 Dart 里重跑同一段判定，改阈值就会红。
 */
enum class WidgetTier {
    /** 两行紧凑列表（今天 + 明天），行高 22dp。 */
    LIST_COMPACT,

    /** 三行列表，行高 40dp。 */
    LIST_3,

    /** 五行列表，行高 40dp。 */
    LIST_5,

    /** 一周网格（8 格）+ 今日卡片。 */
    GRID_WEEK,

    /** 两周网格（16 格）+ 今日卡片。 */
    GRID_FORTNIGHT;

    companion object {
        const val COMPACT_MAX_HEIGHT_DP = 110
        const val LIST3_MAX_HEIGHT_DP = 205
        const val LIST5_MAX_HEIGHT_DP = 300
        const val FORTNIGHT_MIN_HEIGHT_DP = 490

        /** 网格要 4 列才排得下，4 列在这台机上实测 328dp —— 留到 300dp 有余量。 */
        const val GRID_MIN_WIDTH_DP = 300

        fun pick(widthDp: Int, heightDp: Int): WidgetTier = when {
            heightDp >= FORTNIGHT_MIN_HEIGHT_DP && widthDp >= GRID_MIN_WIDTH_DP ->
                GRID_FORTNIGHT

            heightDp >= LIST5_MAX_HEIGHT_DP && widthDp >= GRID_MIN_WIDTH_DP -> GRID_WEEK

            heightDp < COMPACT_MAX_HEIGHT_DP -> LIST_COMPACT
            heightDp < LIST3_MAX_HEIGHT_DP -> LIST_3
            // 高够但宽不够（窄长条）：降级为最长的那档列表 —— 网格排不下。
            else -> LIST_5
        }
    }
}
