package com.daoban.shiftassistantpro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 刷新广播的落点。
 *
 * 为什么不让闹钟直接打给某一个 provider：三张卡是平级的，指向其中一张会让
 * 「谁负责刷新」变成一件没有理由的耦合（那张卡被删掉/改名时会连累另两张）。
 *
 * 只由本 App 自己发（`exported="false"` + 显式组件），不接任何外部意图。
 */
class WidgetRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != WidgetRefreshScheduler.ACTION_REFRESH) return
        ShiftWidgets.refreshAll(context)
    }
}
