package com.daoban.shiftassistantpro

/**
 * 三张固定卡。**尺寸与内容都在编译期定死**（`resizeMode="none"`），
 * 运行期不再分档 —— 这是本轮重做的全部要点：一张卡只为它自己的尺寸排版。
 */
enum class WidgetVariant {
    /** 4×1 本周条：周几 / 日数字 / 班次胶囊，七列。 */
    WEEK_STRIP,

    /** 4×3 今日信息卡：照搬 App 底栏信息卡的完整版。 */
    TODAY,

    /** 4×5 整月：月份标题 + 周几行 + 6×7 格。 */
    MONTH,
}
