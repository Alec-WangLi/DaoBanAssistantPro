package com.daoban.shiftassistantpro

/** 4×5 整月。内容全在 [WidgetRenderer.monthCard]：月份标题 + 周几行 + 6×7 格。 */
class MonthWidgetProvider : ShiftWidgetBase() {
    override val variant = WidgetVariant.MONTH
}
