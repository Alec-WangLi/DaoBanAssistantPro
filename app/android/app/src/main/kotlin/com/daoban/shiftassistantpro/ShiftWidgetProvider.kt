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
            // 桌面上一个实例都没有时不排刷新 —— 否则用户删掉小组件之后，下一次打开
            // App 又把它排回来（`widgetPushSnapshot` 也无条件调 `refreshAll`），
            // 于是「删了还在刷」永远循环：14 天窗口内一天 3~5 次，之后一天一次。
            // `onDeleted` 只盖住「删除那一刻」，盖不住这条 push 路径。
            if (ids.isNotEmpty()) scheduleNextRefresh(context)
        }

        /**
         * 排下一次刷新。
         *
         * 快照里 `boundaries` 是生成时刻起、14 天窗口内所有「该刷新了」的时刻
         * （每天的本地零点 + 各工作班次的开始/结束），升序。取第一个大于现在的即可。
         * 窗口耗尽（App 两周没打开）就退化为「下一个本地零点」—— 那时卡片本来就已经
         * 是占位态了，零点这一刷只是给它一个自愈的机会。
         */
        fun scheduleNextRefresh(context: Context) {
            val now = System.currentTimeMillis()
            val snap = WidgetStore.snapshot(context)
            val next = snap?.boundaries?.firstOrNull { it > now }
                ?: run {
                    val d = java.time.LocalDate.now().plusDays(1)
                    AlarmLog.info(context, "ShiftWidgetProvider: 边界窗口耗尽，退化为下一个零点")
                    d.atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
                }
            WidgetRefreshScheduler.schedule(context, next)
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
                    mgr.updateAppWidget(id, WidgetRenderer.render(context, snap, tier, id))
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
        scheduleNextRefresh(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        renderAll(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        // 最后一个实例被删掉时才取消刷新闹钟 —— 否则桌面上没小组件了，
        // 它还会一天一次地把自己排回来，永远。
        // `WidgetRefreshScheduler.cancel()` 本来就是为这里准备的（Task 6 写了没接）。
        //
        // 为什么判「最后一个」：多个实例共用同一个请求码，还剩实例时把它取消掉，
        // 剩下的那个就再也不刷新了。
        val mgr = AppWidgetManager.getInstance(context)
        val remaining = mgr.getAppWidgetIds(
            ComponentName(context, ShiftWidgetProvider::class.java)
        )
        if (remaining.isEmpty()) {
            WidgetRefreshScheduler.cancel(context)
            AlarmLog.info(context, "ShiftWidgetProvider.onDeleted: 无实例，已取消刷新闹钟")
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REFRESH) {
            refreshAll(context)
            return // 自定义 action 不走 super（super 只认系统那几个 action）
        }
        super.onReceive(context, intent)
    }
}
