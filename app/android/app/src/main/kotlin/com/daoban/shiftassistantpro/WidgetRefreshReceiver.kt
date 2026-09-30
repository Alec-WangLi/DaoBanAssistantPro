package com.daoban.shiftassistantpro

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 小组件那两条广播的落点：**刷新**（三张卡一起重画）与**翻月**（只有月历那张）。
 *
 * 为什么不让闹钟直接打给某一个 provider：三张卡是平级的，指向其中一张会让
 * 「谁负责刷新」变成一件没有理由的耦合（那张卡被删掉/改名时会连累另两张）。
 *
 * 只由本 App 自己发（`exported="false"` + 显式组件），不接任何外部意图。
 */
class WidgetRefreshReceiver : BroadcastReceiver() {

    companion object {
        /**
         * 翻月。发送端是 `WidgetRenderer.monthStepIntent` —— **两边的字符串必须逐字
         * 一致**（Kotlin 之间没有共享常量通道，写歪一个是静默的：箭头画得出来、
         * 点了没反应）。由 `widget_fixed_cards_guard_test.dart` 扫源码比对。
         */
        const val ACTION_MONTH_STEP = "com.daoban.shiftassistantpro.WIDGET_MONTH_STEP"
        const val EXTRA_WIDGET_ID = "widgetId"
        const val EXTRA_DELTA = "delta"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            WidgetRefreshScheduler.ACTION_REFRESH -> ShiftWidgets.refreshAll(context)
            ACTION_MONTH_STEP -> handleMonthStep(context, intent)
            else -> return
        }
    }

    /**
     * 翻上 / 下月（`delta = ±1`），或点标题回今天（`delta = 0`）。
     *
     * **越界在这里吞掉**：箭头那一侧没得翻时渲染端把它画成灰的，但灰箭头**照样带着
     * 点击**（`reapply` 撤不掉上次设过的点击，见渲染端 `monthStepIntent` 那段注释）。
     * 所以「能不能翻」必须由这里判 —— 判据与渲染端同一个 [WidgetRenderer.monthCovered]。
     */
    private fun handleMonthStep(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_WIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) return
        val mgr = AppWidgetManager.getInstance(context)
        // 卡片可能刚刚被删掉（删卡与点击完全可以同时发生）—— 查不到就什么都不做。
        if (mgr.getAppWidgetInfo(id) == null) return

        val snap = WidgetStore.snapshot(context)
        // **当前显示的是哪个月，问渲染端那一个实现**（`displayedMonth`）：自己读盘上的
        // 锚点会踩到「锚点还在、但渲染早就忽略它了」那种情形，于是箭头作用在一个你
        // 看不见的月份上 —— 点一下跳到莫名其妙的地方。
        val current = WidgetRenderer.displayedMonth(context, id, snap)
        val delta = intent.getIntExtra(EXTRA_DELTA, 0)
        val target = if (delta == 0) {
            null                                    // 回今天 = 清掉锚点
        } else {
            current.plusMonths(delta.toLong())
        }
        if (target != null && !WidgetRenderer.monthCovered(snap, target)) return

        WidgetStore.setMonthAnchor(context, id, target?.toEpochDay())
        // 只重画这一个实例（翻月与另外两张卡无关），快照复用刚读到的那份。
        ShiftWidgets.render(context, mgr, snap, WidgetVariant.MONTH, intArrayOf(id))
    }
}
