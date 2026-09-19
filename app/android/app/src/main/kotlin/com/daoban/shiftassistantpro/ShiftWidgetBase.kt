package com.daoban.shiftassistantpro

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent

/**
 * 三张固定卡的公共实现。子类只有一个 `variant`，没有别的。
 *
 * 刷新触发点（承自 v0.8.4 的 spec §6.1，本轮一处未改）：
 *   · App 内数据变化 —— Dart 侧 `WidgetService.push()` 走 MethodChannel 进来
 *   · 跨天 00:00 与今天班次的开始/结束 —— [WidgetRefreshScheduler] 排的精确闹钟
 *   · 开机 / 装更新 —— BootReceiver 里补一次
 *   · 刚添加到桌面 —— 系统的 onUpdate
 *
 * **没有 `onAppWidgetOptionsChanged`**：本轮三张卡都 `resizeMode="none"`，
 * 尺寸不会变，那个回调不会再来。留着它只会让人以为「尺寸还是会变」。
 */
abstract class ShiftWidgetBase : AppWidgetProvider() {

    abstract val variant: WidgetVariant

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // `javaClass`（不是 `this`）：注册表按类名反查 variant，见 `ShiftWidgets.variantOf`。
        ShiftWidgets.render(context, appWidgetManager, javaClass, variant, appWidgetIds)
        ShiftWidgets.scheduleNextRefreshIfNeeded(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        // 最后一个实例（跨三张卡一起数）被删掉时才取消刷新闹钟 —— 否则桌面上一个
        // 小组件都没有了，它还会一天一次地把自己排回来，永远。
        //
        // 判「一个不剩」而不是「本 provider 不剩」：三张卡共用同一个刷新闹钟，
        // 只看自己会把另外两张卡的刷新一起取消掉。
        if (!ShiftWidgets.hasAnyInstance(context)) {
            WidgetRefreshScheduler.cancel(context)
            AlarmLog.info(context, "ShiftWidgetBase.onDeleted: 三张卡都无实例，已取消刷新闹钟")
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == WidgetRefreshScheduler.ACTION_REFRESH) {
            ShiftWidgets.refreshAll(context)
            return // 自定义 action 不走 super（super 只认系统那几个 action）
        }
        super.onReceive(context, intent)
    }
}
