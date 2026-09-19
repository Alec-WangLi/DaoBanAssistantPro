package com.daoban.shiftassistantpro

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context

/**
 * 三张卡的注册表。**所有「对全部实例」的操作都必须走这里** ——
 * 少扫一张卡的症状是静默的：那张卡不刷新、或者三张卡都删光了刷新闹钟还在跑。
 */
object ShiftWidgets {

    /** 三张卡的 provider 类。顺序与 `WidgetVariant` 一致，便于对照。 */
    private val PROVIDERS = listOf(
        WeekStripWidgetProvider::class.java,
        TodayCardWidgetProvider::class.java,
        MonthWidgetProvider::class.java,
    )

    /** 渲染全部卡的**全部实例**。Dart 侧 push 完快照后调它。 */
    fun refreshAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        // 快照**只解析一次**：三张卡共用同一份（约 20KB）JSON，之前每个 provider
        // 各自读盘 + 解析一遍，一次推送要解析三到五次，全是浪费。
        val snap = WidgetStore.snapshot(context)
        var total = 0
        for (cls in PROVIDERS) {
            val ids = mgr.getAppWidgetIds(ComponentName(context, cls))
            total += ids.size
            render(context, mgr, snap, variantOf(cls), ids)
        }
        AlarmLog.info(context, "ShiftWidgets.refreshAll: $total 个实例")
        // 桌面上一个实例都没有时不排刷新 —— 否则用户删掉小组件之后，下一次打开 App
        // 又把它排回来，于是「删了还在刷」永远循环（v0.8.4 的注释有完整推演）。
        if (total > 0) scheduleNextRefreshIfNeeded(context)
    }

    /** 三张卡里还有没有活着的实例。`onDeleted` 判「该不该取消刷新闹钟」用它。 */
    fun hasAnyInstance(context: Context): Boolean {
        val mgr = AppWidgetManager.getInstance(context)
        return PROVIDERS.any { mgr.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
    }

    /**
     * 排下一次刷新。
     *
     * 快照里 `boundaries` 是生成时刻起、窗口内所有「该刷新了」的时刻（每天的本地零点
     * + 各工作班次的开始/结束），升序。取第一个大于现在的即可。
     *
     * 窗口耗尽（App 两个多月没打开）就退化为「下一个本地零点」—— 那时卡片本来就已经
     * 是占位态了，零点这一刷只是给它一个自愈的机会。
     *
     * ⚠️ 跨月**不需要**单排一条「下月 1 日」的边界：零点那条边界本来就会重渲染一次，
     * 而月历渲染哪个月是原生按 `LocalDate.now()` 现算的，数据早就在窗口里。
     */
    fun scheduleNextRefreshIfNeeded(context: Context) {
        // 这里**自己读一次**快照，不从调用方穿进来：另外两个调用方
        // （`ShiftWidgetBase.onUpdate`、`BootReceiver`）手上都没有快照，
        // 为省这一次解析把签名改成「可空快照」得让三处都先读一遍，不划算。
        val now = System.currentTimeMillis()
        val snap = WidgetStore.snapshot(context)
        val next = snap?.boundaries?.firstOrNull { it > now }
            ?: run {
                val d = java.time.LocalDate.now().plusDays(1)
                AlarmLog.info(context, "ShiftWidgets: 边界窗口耗尽，退化为下一个零点")
                d.atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
            }
        WidgetRefreshScheduler.schedule(context, next)
    }

    /**
     * 渲染一批实例。按 [variant] 交给 [WidgetRenderer]。
     *
     * 快照由调用方解析好传进来（[refreshAll] 三张卡共用一份；系统 `onUpdate`
     * 那条路径自己读一次）—— 这里**不再读盘**。
     */
    internal fun render(
        context: Context,
        mgr: AppWidgetManager,
        snap: WidgetStore.Snapshot?,
        variant: WidgetVariant,
        ids: IntArray,
    ) {
        if (ids.isEmpty()) return
        for (id in ids) {
            try {
                mgr.updateAppWidget(id, WidgetRenderer.render(context, snap, variant, id))
            } catch (e: Exception) {
                // 越界读、位图过大这类问题在这里被吞掉时**不会崩**，只会让那张卡
                // 停在上一次的内容上 —— 所以这条日志是唯一的线索。
                AlarmLog.error(context, "ShiftWidgets: 渲染 $variant id=$id 失败: ${e.message}")
            }
        }
    }

    private fun variantOf(cls: Class<out AppWidgetProvider>): WidgetVariant = when (cls) {
        WeekStripWidgetProvider::class.java -> WidgetVariant.WEEK_STRIP
        TodayCardWidgetProvider::class.java -> WidgetVariant.TODAY
        else -> WidgetVariant.MONTH
    }
}
