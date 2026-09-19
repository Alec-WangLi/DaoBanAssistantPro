package com.daoban.shiftassistantpro

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context

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
 *
 * **没有 `onReceive`**：刷新广播的落点是 [WidgetRefreshReceiver]（三张卡平级，
 * 不该把「谁负责刷新」耦合到某一家的组件上）。基类曾经也接同一个 action，
 * 但 `ACTION_REFRESH` 的**唯一生产者已改成打给那个 receiver**，那一段是死的。
 */
abstract class ShiftWidgetBase : AppWidgetProvider() {

    abstract val variant: WidgetVariant

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // `variant` 直接来自子类（`abstract val variant`）—— 不需要按类名反查。
        // 那条按类名查表的路只有 `ShiftWidgets.refreshAll` 遍历注册表时用得到。
        ShiftWidgets.render(
            context,
            appWidgetManager,
            WidgetStore.snapshot(context),
            variant,
            appWidgetIds,
        )
        ShiftWidgets.scheduleNextRefreshIfNeeded(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        // 最后一个实例（跨三张卡一起数）被删掉时才取消刷新闹钟 —— 否则桌面上一个
        // 小组件都没有了，它还会一天一次地把自己排回来，永远。
        //
        // 判「一个不剩」而不是「本 provider 不剩」：三张卡共用同一个刷新闹钟，
        // 只看自己会把另外两张卡的刷新一起取消掉。
        //
        // 这里是唯一做这件事的地方（原先的 `ShiftWidgets.cancelRefreshIfNone`
        // 零调用方，已删）：日志行要指名 `onDeleted`，绕一层注册表反而说不清
        // 是谁取消的。
        if (!ShiftWidgets.hasAnyInstance(context)) {
            WidgetRefreshScheduler.cancel(context)
            AlarmLog.info(context, "ShiftWidgetBase.onDeleted: 三张卡都无实例，已取消刷新闹钟")
        }
    }
}
