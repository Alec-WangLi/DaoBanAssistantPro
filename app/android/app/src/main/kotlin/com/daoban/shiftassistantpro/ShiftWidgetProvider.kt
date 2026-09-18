package com.daoban.shiftassistantpro

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/**
 * 桌面小组件的入口。
 *
 * 它只做四件事：读快照 → 按每个实例自己的尺寸分档 → 交给 [WidgetRenderer] 排版
 * → 把下一次刷新排进 AlarmManager。所有业务判断都不在这里（见 widget_snapshot.dart）。
 *
 * 刷新触发点（对应 spec §6.1）：
 *   · App 内数据变化 —— Dart 侧 `WidgetService.push()` 走 MethodChannel 进来
 *   · 跨天 00:00 与今天班次的开始/结束 —— [WidgetRefreshScheduler] 排的精确闹钟
 *   · 开机 / 装更新 —— BootReceiver 里补一次
 *   · 刚添加到桌面 / 改尺寸 —— 系统的 onUpdate / onAppWidgetOptionsChanged
 */
class ShiftWidgetProvider : AppWidgetProvider() {

    companion object {
        /** 自定义刷新 action。注意它**只由本 App 自己发** —— receiver 是 not exported。 */
        const val ACTION_REFRESH = "com.daoban.shiftassistantpro.WIDGET_REFRESH"

        /** 渲染全部实例。Dart 侧 push 完快照后调它。 */
        fun refreshAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, ShiftWidgetProvider::class.java)
            )
            AlarmLog.info(context, "ShiftWidgetProvider.refreshAll: ${ids.size} 个实例")
            renderAll(context, mgr, ids)
        }

        private fun renderAll(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            if (ids.isEmpty()) return
            val snap = WidgetStore.snapshot(context)
            for (id in ids) {
                val opts = mgr.getAppWidgetOptions(id)
                val w = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                val h = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
                val tier = WidgetTier.pick(w, h)
                // 真机标定用：对着三档各拉一次，adb logcat -s ShiftAssistant 读回来。
                AlarmLog.info(context, "ShiftWidgetProvider: id=$id, ${w}x${h}dp → $tier")
                try {
                    mgr.updateAppWidget(id, WidgetRenderer.render(context, snap, tier))
                } catch (e: Exception) {
                    AlarmLog.error(context, "ShiftWidgetProvider: 渲染 id=$id 失败: ${e.message}")
                }
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        renderAll(context, appWidgetManager, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        renderAll(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REFRESH) {
            refreshAll(context)
            return // 自定义 action 不走 super（super 只认系统那几个 action）
        }
        super.onReceive(context, intent)
    }
}
