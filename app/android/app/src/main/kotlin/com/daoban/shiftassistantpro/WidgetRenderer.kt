package com.daoban.shiftassistantpro

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.widget.RemoteViews

import java.time.LocalDate

/**
 * 排版。**纯渲染**：不写盘、不排闹钟、不读除宿主配置之外的任何系统状态。
 *
 * 与 ShiftWidgetBase 分开是为了能单独读懂它 —— 这个类里没有一行涉及
 * 「什么时候刷新」「刷新排在哪」，只有「给我一份快照，我给你一棵 RemoteViews 树」。
 *
 * 四条纪律：
 *  1. Kotlin 侧一个中文字面量都不许有。所有文案都来自快照（Dart 侧 `L10n` 产出）。
 *     唯一的例外是占位态那行应用名，它取自 `applicationInfo.loadLabel()`。
 *  2. 明暗一律**显式选资源**，不依赖 `-night` 限定符 —— `RemoteViews` 由宿主进程
 *     inflate，限定符在宿主进程里的解析顺序各家 ROM 不一致。
 *  3. 布局只用 RemoteViews 白名单里的类：FrameLayout / LinearLayout / RelativeLayout /
 *     GridLayout + TextView / ImageView。**没有 ConstraintLayout**，报的是运行期
 *     `ClassNotFoundException`，不是编译错误。
 *  4. **往容器里 `addView` 之前必须先 `removeAllViews`**（每一个容器、每一次渲染，
 *     包括 `continue` 逃掉的那几支）。见下面那条长说明 —— 漏掉它不会报任何错，
 *     只在部分机型上表现为「内容一变就重影」。
 */
object WidgetRenderer {

    /*
     * ── 纪律 4 的长说明：为什么每个容器在 addView 之前都要 removeAllViews ──
     *
     * 症状（2026-09-29 用户反馈，几个 OPPO / vivo 用户，开发机上复现不出来）：
     * 把某天的「前夜」按天改成「休班」之后，桌面小组件上的字**重影**了 ——
     * 旧班的字压在新班的字上、上一周的日期压在今天的日期上。
     *
     * 机制：桌面（宿主）收到与手上那棵视图树**同一个布局 id** 的 RemoteViews 时，
     * **不会重新 inflate**，而是走 `RemoteViews.reapply(...)`，把整串动作在已有的
     * 视图树上重放一遍。而 `AppWidgetHostView` 只管换掉旧的**根**视图，**不负责
     * 清空容器里的子视图**。于是同一个槽位每渲染一次就多一个格子；格子根是
     * `match_parent`（`widget_strip_cell.xml` / `widget_month_cell.xml`），
     * 后加的不会把先加的挤开，而是**叠在同一块面积上**。
     *
     * 为什么平时看不出来：两层内容完全一样时，合成结果只是略微糊一点、胶囊深一档，
     * 没人会注意。**只有某一格的内容变了，旧层才露出来** —— 这正是「改了排班才出现」
     * 的原因，也是它被当成新 bug 的原因（其实一直在叠，只是从前看不见）。
     *
     * 为什么只有部分机型：新一些的 AOSP / 启动器会**回收**已加进去的子视图
     * （`canRecycleView`，Android 12 起进了 CTS），刚好把缺陷盖住；旧框架与厂商分叉
     * 会老老实实再加一个。所以「我这台上没问题」不能当成这条不存在 —— 它取决于宿主，
     * 不取决于我们。`RemoteViews.addView` 的官方文档写的就是这条：宿主可能回收布局，
     * 要用 `removeAllViews(int)` 清掉已有的子视图。
     *
     * 护栏：`app/test/widget_fixed_cards_guard_test.dart` 里那条「每处 addView 的容器
     * 都先被 removeAllViews 清过」，扫的就是本文件。**别为消掉它的红而放宽正则** ——
     * 它是这条约定唯一的凭据（本文件没有编译期可以依赖的东西）。
     */

    /**
     * dp → px。`RemoteViews` 里的尺寸单位是 px，送给 `WidgetChip` 画位图前要自己乘密度。
     */
    private fun dpToPx(context: Context, dp: Int): Int =
        (dp * context.resources.displayMetrics.density).toInt()

    /**
     * 小组件点击用的 requestCode 基址。
     *
     * **必须远离项目里所有既有的 requestCode 区间。** 理由：这些 PendingIntent 的意图
     * 都是「无 action、无 data 的 `MainActivity`」，而 `PendingIntent` 的身份是
     * 「requestCode + 意图的 `filterEquals`」—— `filterEquals` **只比 action/data/
     * category/component，不比 extras，也不比 flags**。所以只要 requestCode 撞上，两个
     * 逻辑上毫不相干的点击就会共用同一个 PendingIntent，配 `FLAG_UPDATE_CURRENT`
     * 互相覆盖 extras。
     *
     * 既有区间（`AlarmScheduler` / `TodoReminderReceiver` 都用 `requestCode = 各自的 id`）：
     * 班次闹钟 0..400、自定义闹钟 10000..11000、待办行提醒 20000..39999、重复待办
     * 提醒 40000..41999，另有 `AlarmRingService` 的通知点击 0 / 1（同样带着
     * `alarm_label` 打向 `MainActivity`）与 `MainActivity.REQ_PICK_RINGTONE = 40071`。
     * 取 100000 起，全部避开。
     *
     * （`REQ_PICK_RINGTONE` 那个 40071 与重复待办的号段数值上挨着，但**不是同一个
     * 池**：它是 `getActivity` 的活动池，这里是 `getBroadcast` 的闹钟池，
     * `filterEquals` 连目标组件一起比。之所以写下来，是免得下一个人看到两个
     * 4 万多的号以为撞了。）
     *
     * `WidgetRefreshScheduler.REQ = 40081` **不在此列**：它是 `getBroadcast` 给
     * `WidgetRefreshReceiver` 且 `setAction` 过，目标组件与 `filterEquals` 都不同，
     * 本来就与这里不是同一个 PendingIntent。（`MainActivity.nativePendingIntent`
     * 同理，打向 `AlarmReceiver`。）
     *
     * 这条是 Task 7 的复审在 diff 之外发现的：初稿用 `widgetId * 16`，而 widget id 是
     * **设备级全局单调计数器**（新设备上第一个小组件拿到的就是 1 左右），于是
     * `Root(1) = 16` 正好落进班次闹钟的 id 区间里（那个区间从 0 起）。后果比「点错天」
     * 更糟 —— 小组件每次渲染都会把那枚 PendingIntent 上的 `alarm_label` /
     * `alarm_detail` 抹成空，闹钟通知点开的响铃界面因此失效。
     */
    private const val WIDGET_REQ_BASE = 100_000

    /**
     * 每个小组件实例占用的 requestCode 槽位数。
     *
     * 需要 `Root` + 42 个月历格 = 43，向上取到 64。
     *
     * ⚠️ **这个数不是随便取的，它是编址方案的护栏。** `Cell(w, n) = B + 64w + 1 + n`
     * （`n` 是 0 起的格子下标，实例共 `k` 格）。只要 **`k ≤ 63`**，格子偏移 `1 + n`
     * 就恒 `< 64` —— 要进位到 `B + 64(w+1)` 需要 `1 + n = 64`，即 `k ≥ 64`。于是
     * `Cell(w, n) − Root(w) = 1 + n` 恒落 `[1, 63]`、**恒不为 0**：`Cell` 既不会撞上
     * 本实例的 `Root`，也不会撞上**别的实例**的 `Root`（`Root(m) = B + 64m` 与 `B` 的差
     * 恒是 64 的倍数）。本仓最多用到 42 格（月历），远在护栏之内。
     *
     * ⚠️ **不要把这条推广成「`Cell` 永不为 64 的倍数」——那在绝对值上是错的**：
     * `B = 100_000 ≡ 32 (mod 64)`，于是 `Cell(w, 31) = 100_032 = 64 × 1563` 就是 64 的
     * 倍数。真正起作用的永远是上面那条**偏移**性质（`Cell − Root` 恒不为 0），
     * 不是「值本身不被 64 整除」。这个撞车类在本仓**真实发生过**（见 `launchIntent`
     * 的 KDoc）。基数从 32 提到 64 之后，`Int` 溢出的 widgetId 上限从约 6710 万降到
     * 约 3350 万，仍远够用。
     */
    private const val REQ_SLOTS_PER_WIDGET = 64

    /**
     * 翻月那两枚箭头的 requestCode 基数。**广播池**，与上面 `WIDGET_REQ_BASE`
     * （活动池，点格开 App 用 `getActivity`）**是两回事**。
     *
     * 900_000 离既有占用都够远：班次闹钟 0..400、自定义闹钟 10000..11000、待办提醒
     * 20000..39999、重复待办 40000..41999、选铃声 40071、刷新闹钟 40081。
     *
     * 编号 = `BASE + widgetId * 4 + dir`（dir：0 = 上月、1 = 下月、2 = 回今天，第 4 档
     * 留给将来）—— **每个实例、每个方向各一枚**：`Intent.filterEquals` 不比 extras，
     * 撞号会让两张卡共用一个箭头（点这张、那张翻页）。基数与展开形式由
     * `widget_fixed_cards_guard_test.dart` 扫源码钉住。
     */
    private const val WIDGET_MONTH_REQ_BASE = 900_000

    /** 整卡的 requestCode：低位 0 留给「不指定日期」。 */
    private fun rootRequestCode(widgetId: Int): Int = WIDGET_REQ_BASE + widgetId * REQ_SLOTS_PER_WIDGET

    /** 第 cell 格的 requestCode。低位 +1 起，避开 `rootRequestCode` 的 0。 */
    private fun cellRequestCode(widgetId: Int, cell: Int): Int =
        WIDGET_REQ_BASE + widgetId * REQ_SLOTS_PER_WIDGET + 1 + cell

    /**
     * 翻上 / 下月（`delta = ±1`）或回今天（`delta = 0`）：发给 [WidgetRefreshReceiver]
     * 的**广播**（与上面那个活动池无关，见 [WIDGET_MONTH_REQ_BASE]）。
     *
     * 越界不由这里拦：箭头那一侧没得翻时只是画成灰的，但**点击照样挂着** ——
     * `RemoteViews` 的 `reapply` 只重放新的动作串，**没有任何办法撤掉上一次设过的
     * 点击**。所以「能不能翻」由接收端判（同一个 [monthCovered]）。
     */
    private fun monthStepIntent(context: Context, widgetId: Int, delta: Int): PendingIntent {
        val dir = when {
            delta < 0 -> 0
            delta > 0 -> 1
            else -> 2      // 点标题 = 回今天
        }
        val i = Intent(context, WidgetRefreshReceiver::class.java)
            .setAction(WidgetRefreshReceiver.ACTION_MONTH_STEP)
            .putExtra(WidgetRefreshReceiver.EXTRA_WIDGET_ID, widgetId)
            .putExtra(WidgetRefreshReceiver.EXTRA_DELTA, delta)
        return PendingIntent.getBroadcast(
            context,
            WIDGET_MONTH_REQ_BASE + widgetId * 4 + dir,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * 打开 App 的 PendingIntent。
     *
     * 用 `getActivity` + 显式组件：隐式 LAUNCHER intent 在某些 ROM 上会被解析到
     * 「选择启动器」之类的东西上。
     *
     * ⚠️ requestCode 走上面那两个函数，**整卡与格子必须落在同一个仿射命名空间里**。
     * `PendingIntent` 的身份是「requestCode + 意图的 `filterEquals`」——而 `filterEquals`
     * **不比较 extras**，配上 `FLAG_UPDATE_CURRENT`（会覆盖 extras），两个 requestCode
     * 只要**数值相等**就会共用一个 PendingIntent、互相冲掉 `widget_day`，点一下跳到错
     * 的那天。
     *
     * **为什么步长必须与格子数错开**：（**历史注** —— 下面这个 16 格的网格是本轮删掉的
     * 旧版式，留着只是为了记下这个撞车类当初是怎么来的。）当时一个网格实例真正用到
     * `Cell(w, 0..15)`（16 格）。
     * 若步长仍是 16，末格 `Cell(m, 15) = B + 16m + 16 = B + 16(m+1)` —— **正好等于下一个
     * 实例的 `Root(m+1)`**，撞成同一个 PendingIntent；这个撞车类在本仓**真实发生过**
     * （初稿让整卡用**裸 `widgetId`**，单实例时 `16w + c ≠ w` 不自撞，所以在只有 id 34
     * 的桌面上测全过、藏得住；而 widget id **不是**「系统给的小整数」——它是设备级单调
     * 计数器，不复用，差 16 倍的两实例够得着）。当时的修法是把步长提到 32：格子偏移
     * `1 + n` ≤ 16、恒小于步长 32，`Cell(m, n) − Root(m) = 1 + n` **恒不为 0** ——
     * 于是对任意实例都不相等，单实例内也不自撞。这不是「取个大点的数保险」，
     * 而是「格子数必须与步长错开到不产生进位碰撞」的硬约束，见 `REQ_SLOTS_PER_WIDGET`。
     * **Task 7 的月历一格一码、要用满 42 格**：步长 32 已经不够 —— 第 32 格
     * `Cell(m, 31) = B + 32m + 32` 正好又是下一个实例的 `Root(m+1)`（42 > 32，直接撞车）。
     * 故基数一并提到 64：42 格 ≤ 63，格子偏移 `1 + n` ≤ 42、恒 `< 64`，`Cell − Root`
     * 因此仍恒不为 0。
     *
     * 现在 `Root(n) = WIDGET_REQ_BASE + 64n`、`Cell(m, c) = WIDGET_REQ_BASE + 64m + 1 + c`；
     * 基址再把它们整体抬离所有既有区间（见 `WIDGET_REQ_BASE`）。`widgetId` 涨到约
     * 3350 万才会 `Int` 溢出。
     */
    private fun launchIntent(context: Context, requestCode: Int, epochDay: Int? = null): PendingIntent {
        val i = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (epochDay != null) putExtra("widget_day", epochDay)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** 主题模式 → 此刻该用暗色吗。`system` 读宿主当前的配置，所以永远是新鲜的。 */
    fun isDark(context: Context, themeMode: String): Boolean = when (themeMode) {
        "light" -> false
        "dark" -> true
        else -> (context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    }

    /**
     * 三张卡的分派。**纯渲染**：不写盘、不排闹钟、不读除宿主配置之外的任何系统状态。
     *
     * 三张卡各自走自己的渲染函数：`weekStrip` / `todayStandalone` / `monthCard`。
     * 旧版式的五档渲染族（两行/五行列表、一周/两周网格、网格+今日卡片的装配壳）连同
     * 尺寸分档枚举已一并删净（Task 8 清账，见那次的提交信息）—— 尺寸在编译期定死
     * （`resizeMode="none"`），这里不再有分档分支。
     */
    fun render(
        context: Context,
        snap: WidgetStore.Snapshot?,
        variant: WidgetVariant,
        widgetId: Int,
    ): RemoteViews {
        if (snap == null) {
            return placeholder(context, dark = isDark(context, "system"), widgetId = widgetId)
        }
        val todayIndex = snap.indexOfToday()
        if (todayIndex < 0) {
            // 快照过期：App 两个多月没打开，这份 days 里已经没有今天了。
            AlarmLog.info(context, "WidgetRenderer: 快照已过期，走占位态")
            return placeholder(context, isDark(context, snap.themeMode), widgetId = widgetId)
        }
        if (!snap.hasSchedule) return empty(context, snap, widgetId)
        return when (variant) {
            WidgetVariant.WEEK_STRIP -> weekStrip(context, snap, todayIndex, widgetId)
            WidgetVariant.TODAY -> todayStandalone(context, snap, todayIndex, widgetId)
            WidgetVariant.MONTH -> monthCard(context, snap, widgetId)
        }
    }

    /**
     * 4×1 本周条：**今天所在的那一周**（周一~周日），与 App 日历的一行同构。
     *
     * 列的位置由**日期**定，不由 `todayIndex` 定：先算本周一，再逐列拿 epochDay 去
     * `days[]` 里找。窗口是绝对日期的（spec §7.1），所以本周一即使是上个月的最后几天
     * 也在窗口里 —— 这正是换窗口换来的能力。
     *
     * 「今天」那列：周几与日数字走**主色**。**不许加粗** —— `TextView` 没有
     * `setTypeface(int)` 重载，`setInt(id, "setTypeface", …)` 会在宿主进程抛 `ActionException`。
     *
     * 胶囊走**淡染配方**（14% 底 + 45% 描边）而不是实心：那是 App 日历格里班次胶囊的
     * 同一套长相（spec §4.1），文字因此走中性 ink —— 淡染底混合后≈卡片底，
     * `wg_ink_*` 必然过 AA，而 `onSolid` 那套黑/白字在淡染底上是错的。
     *
     * **没班次（`hasShift == false`）那一列整个不画胶囊**，与 App 日历格一致（`shift == null`
     * 时那块根本不画）。这里**不能**拿 `wg_empty_*` 去画「淡占位」：`WidgetChip.tintedChip`
     * 里 fill/stroke 的 alpha 是写死的（36 / 115），`Paint.setAlpha` 会**覆盖**颜色字节自带的
     * alpha —— `#14000000` 会变成一条 45% 的黑描边环，比 App 的长相响得多。正常排班里
     * 「休班」是一个**有颜色的班次定义**（`hasShift == true`），照常画胶囊 ——
     * 这条只影响空白表方案下的无班次日。
     */
    private fun weekStrip(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_week_strip)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_ws_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.setOnClickPendingIntent(R.id.wg_ws_root, launchIntent(context, rootRequestCode(widgetId)))

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted = context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)

        val todayEpoch = snap.days[todayIndex].day
        val today = LocalDate.ofEpochDay(todayEpoch)
        val monday = today.minusDays((today.dayOfWeek.value - 1).toLong())

        val columns = intArrayOf(
            R.id.wg_ws_col1, R.id.wg_ws_col2, R.id.wg_ws_col3, R.id.wg_ws_col4,
            R.id.wg_ws_col5, R.id.wg_ws_col6, R.id.wg_ws_col7,
        )

        for (col in columns.indices) {
            // **先清空再填** —— 这一句是「内容变了之后小组件重影」的修复，见本文件顶部
            // 那条 addView 的说明。放在循环开头而不是紧贴 addView：`continue` 逃掉的
            // 那一支（窗口里没有这天）同样要让容器里**一个子视图都不留**，否则旧格子
            // 会缩在 GONE 的槽位里，等这个槽位下次填上时又叠一层。
            v.removeAllViews(columns[col])
            val epoch = monday.plusDays(col.toLong()).toEpochDay()
            val i = snap.days.indexOfFirst { it.day == epoch }
            if (i < 0) {
                // 窗口里没有这天（理论上不会发生 —— 窗口恒含本周一与本周日）。
                // 不当成「没有班次」画：那会理直气壮地显示一张空卡。
                v.setViewVisibility(columns[col], android.view.View.GONE)
                continue
            }
            v.setViewVisibility(columns[col], android.view.View.VISIBLE)

            val d = snap.days[i]
            val isToday = epoch == todayEpoch

            // 点某一列 → 打开 App 并跳到那天。格子占槽位 1..7。
            v.setOnClickPendingIntent(
                columns[col],
                launchIntent(context, cellRequestCode(widgetId, col), epochDay = epoch.toInt()),
            )

            val c = RemoteViews(context.packageName, R.layout.widget_strip_cell)
            // 可见性无条件设满：宿主 reapply 时只重放新动作，漏设会保持上一次的状态。
            c.setViewVisibility(R.id.wg_sc_weekday, android.view.View.VISIBLE)
            c.setViewVisibility(R.id.wg_sc_day, android.view.View.VISIBLE)

            c.setTextViewText(R.id.wg_sc_weekday, d.weekday)
            c.setTextColor(R.id.wg_sc_weekday, if (isToday) snap.accent else muted)
            // 日数字：与 App 的格子一样只印「日」，整串「9月19日」在 46dp 宽的列里排不下。
            c.setTextViewText(R.id.wg_sc_day, LocalDate.ofEpochDay(epoch).dayOfMonth.toString())
            c.setTextColor(R.id.wg_sc_day, if (isToday) snap.accent else ink)

            // 没班次就不画胶囊 —— 与 App 日历格一致（`shift == null` 时那块不画）。
            // 不能拿 `wg_empty_*` 顶：`tintedChip` 的 `Paint.setAlpha` 会覆盖颜色字节自带的
            // alpha（fill 写死 36、stroke 写死 115），`#14000000` 会变成一条 45% 黑描边环。
            // **两个方向都要设满**：宿主 reapply 只重放新动作，漏设的一边会留着上一次的状态
            // （同一实例从有班次日切到无班次日时，胶囊会残留在那里）。
            if (d.hasShift) {
                c.setViewVisibility(R.id.wg_sc_pill, android.view.View.VISIBLE)
                c.setViewVisibility(R.id.wg_sc_abbr, android.view.View.VISIBLE)
                c.setImageViewBitmap(
                    R.id.wg_sc_pill,
                    WidgetChip.tintedChip(d.color, dpToPx(context, 36), dpToPx(context, 18)),
                )
                c.setTextViewText(R.id.wg_sc_abbr, d.shiftAbbr)
                c.setTextColor(R.id.wg_sc_abbr, ink)
            } else {
                c.setViewVisibility(R.id.wg_sc_pill, android.view.View.GONE)
                c.setViewVisibility(R.id.wg_sc_abbr, android.view.View.GONE)
            }

            v.addView(columns[col], c)
        }
        return v
    }

    /**
     * 那个月能不能画：它的**42 格**（从该月 1 日所在周的周一起连续 42 天）全在快照
     * 覆盖的范围内。翻月的箭头灰不灰、接收端吞不吞这枚点击，用的都是它。
     *
     * 为什么问「42 格」而不是「这个月在 `snap.months` 里」：窗口是按整周对齐的，
     * 边上那两个月可能**只被蹭到几天** —— 那种月份列在 `months` 里，却画不出一张完整
     * 的月历（大半格子没数据）。判据必须与「画得出来」严格一致，否则箭头亮着、
     * 点下去是一张空卡。
     */
    internal fun monthCovered(snap: WidgetStore.Snapshot?, firstOfMonth: LocalDate): Boolean {
        if (snap == null || snap.days.isEmpty()) return false
        val start = firstOfMonth
            .minusDays((firstOfMonth.dayOfWeek.value - 1).toLong())
            .toEpochDay()
        return start >= snap.days.first().day && start + 41 <= snap.days.last().day
    }

    /**
     * 这个实例**现在显示的是哪个月**：锚点 ?? 今天那个月；**锚点那个月要是画不出来
     * 就当没设**（数据过期 / 被挤到窗口外）。
     *
     * ⚠️ **接收端算目标月也走这里**，不许自己去读 `WidgetStore.monthAnchor`：盘上那个
     * 锚点可能已经是一个渲染端不认的值，两边各判一次就会出现「箭头作用在你没看见的
     * 那个月」—— 点一下跳到莫名其妙的地方。
     */
    internal fun displayedMonth(
        context: Context,
        widgetId: Int,
        snap: WidgetStore.Snapshot?,
    ): LocalDate {
        val todayFirst = LocalDate.now().withDayOfMonth(1)
        val anchored = WidgetStore.monthAnchor(context, widgetId)
            ?.let { LocalDate.ofEpochDay(it).withDayOfMonth(1) }
        return if (anchored != null && monthCovered(snap, anchored)) anchored else todayFirst
    }

    /**
     * 4×5 整月：月份标题 + 周几行 + 6×7 格。
     *
     * **渲染哪个月**由 [displayedMonth] 定（锚点 ?? 今天，锚点画不出来就当没设）——
     * 不由快照的生成月定，也不需要 App 活着：数据早就在窗口里。
     *
     * **42 格是连续 42 天**（v0.9.17 起）：起点是「该月 1 日所在周的周一」，于是月头
     * 月尾那几格画的是**相邻月份**的日子（日数字走 muted、胶囊照画）——整张卡读起来
     * 是一段连续的日子。窗口外的格仍然 GONE：**「相邻月」与「没数据」是两回事**。
     *
     * 月份标题从 `snap.months` 里按「年-月」查；**查不到就隐藏标题行**，
     * 绝不借相邻月份的标题顶上。
     *
     * 42 格共用 `widget_month_cell` 一张布局、每格一个 `RemoteViews` 实例；胶囊是
     * **定尺 40×18dp** 的 `tintedChip` 位图，靠 `WidgetChip` 的 LruCache 按 (颜色, 尺寸)
     * 复用 —— 同尺寸 + 同色共一张，42 格实际只画得出屈指可数的几张。**别在这条路上
     * 按格子改尺寸或按格子造唯一颜色**，那会把这套复用打掉（Task 1 的探针结论）。
     *
     * 没班次（空白表方案）那格不画胶囊，与 App 日历格一致（`shift == null` 时那块
     * 根本不画）—— 完整理由见 [weekStrip] 里那条「不能拿 `wg_empty_*` 顶上」。
     *
     * 不收 `todayIndex`：本卡渲染哪个月由锚点决定、42 格又是连续的日子，「今天」只能
     * 按日期现算（`epoch == todayEpoch`），快照里那份下标在这里用不上。
     */
    private fun monthCard(
        context: Context,
        snap: WidgetStore.Snapshot,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_month_card)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_m_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.setOnClickPendingIntent(R.id.wg_m_root, launchIntent(context, rootRequestCode(widgetId)))

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted = context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)
        val holiday = context.getColor(R.color.wg_holiday)

        val today = LocalDate.now()
        val todayEpoch = today.toEpochDay()
        // 显示哪个月见 `displayedMonth` 的注释（锚点在盘上、但画不出来时按没设处理）。
        val firstOfMonth = displayedMonth(context, widgetId, snap)

        // ── 标题行：‹ 月份 › ──
        val title = snap.months.firstOrNull {
            it.y == firstOfMonth.year && it.m == firstOfMonth.monthValue
        }
        if (title == null) {
            // 查不到就隐藏（绝不借相邻月份的标题顶上）—— 既有纪律，不改。
            v.setViewVisibility(R.id.wg_m_title, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_m_title, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_m_title, title.title)
            v.setTextColor(R.id.wg_m_title, muted)
        }
        // **箭头永远设点击**，哪怕那一侧没得翻：`RemoteViews` 的 `reapply` 只重放
        // **新的**动作串，**没有任何办法撤掉上一次设过的点击**（与 v0.9.9 那条
        // `removeAllViews` 同源：宿主会复用已在的那棵视图树）。所以「到头了」由
        // **接收端**判 —— 颜色只作提示：能翻 = ink，翻不动 = muted（与标题同档）。
        v.setTextColor(
            R.id.wg_m_prev,
            if (monthCovered(snap, firstOfMonth.minusMonths(1))) ink else muted,
        )
        v.setTextColor(
            R.id.wg_m_next,
            if (monthCovered(snap, firstOfMonth.plusMonths(1))) ink else muted,
        )
        v.setOnClickPendingIntent(R.id.wg_m_prev, monthStepIntent(context, widgetId, -1))
        v.setOnClickPendingIntent(R.id.wg_m_next, monthStepIntent(context, widgetId, 1))
        // 点中间的月份文字 = 回今天（已经是今天那个月时是 no-op）。
        v.setOnClickPendingIntent(R.id.wg_m_title, monthStepIntent(context, widgetId, 0))

        // ── 周几行（7 条文案来自快照，原生不做 i18n） ──
        val wdIds = intArrayOf(
            R.id.wg_m_wd1, R.id.wg_m_wd2, R.id.wg_m_wd3, R.id.wg_m_wd4,
            R.id.wg_m_wd5, R.id.wg_m_wd6, R.id.wg_m_wd7,
        )
        for (i in wdIds.indices) {
            val text = snap.weekdays.getOrNull(i)
            if (text == null) {
                // 快照只有 7 条文案时不会走到这里；真缺了就隐藏，不拿别的顶上。
                v.setViewVisibility(wdIds[i], android.view.View.GONE)
            } else {
                v.setViewVisibility(wdIds[i], android.view.View.VISIBLE)
                v.setTextViewText(wdIds[i], text)
                v.setTextColor(wdIds[i], muted)
            }
        }

        // ── 42 格：从「该月 1 日所在周的周一」起**连续** 42 天 ──
        //
        // 月头月尾那几格因此画的是**相邻月份**的日子，整张卡读起来是一段连续的日子。
        // 窗口外的格仍然 GONE —— 「相邻月」（有数据、照画）与「没数据」（挖空）是两回事。
        val leading = firstOfMonth.dayOfWeek.value - 1   // 周一 = 1 → 前导天数
        val gridStart = firstOfMonth.minusDays(leading.toLong())
        val slotIds = IntArray(42) { i ->
            context.resources.getIdentifier("wg_m_slot${i + 1}", "id", context.packageName)
        }

        for (slot in 0 until 42) {
            // 先清空再填，理由与 `weekStrip` 那处逐字相同（含放在循环开头而非 addView
            // 前面的取舍）。42 格每格都要清 —— 窗外那几格也走这里。
            v.removeAllViews(slotIds[slot])
            val date = gridStart.plusDays(slot.toLong())
            val epoch = date.toEpochDay()
            val i = snap.days.indexOfFirst { it.day == epoch }
            if (i < 0) {
                // 快照没盖到这一天（窗口到头了 / 快照过期）。挖空 —— 画一张理直气壮的
                // 错日子比空着更糟。
                v.setViewVisibility(slotIds[slot], android.view.View.GONE)
                continue
            }
            v.setViewVisibility(slotIds[slot], android.view.View.VISIBLE)

            // 点某一格 → 打开 App 并跳到那天。相邻月的格同样如此（点 8 月 31 日就跳
            // 8 月 31 日，语义自洽）。格子占槽位 1..42（一个实例 64 个槽位）。
            v.setOnClickPendingIntent(
                slotIds[slot],
                launchIntent(context, cellRequestCode(widgetId, slot), epochDay = epoch.toInt()),
            )

            val d = snap.days[i]
            val inMonth = date.year == firstOfMonth.year &&
                date.monthValue == firstOfMonth.monthValue
            val isToday = epoch == todayEpoch
            val c = RemoteViews(context.packageName, R.layout.widget_month_cell)

            // 可见性两个方向都要设满：宿主 `reapply` 只重放新动作，漏设的一边会留着
            // 上一次的状态。
            c.setViewVisibility(R.id.wg_mc_day, android.view.View.VISIBLE)
            c.setTextViewText(R.id.wg_mc_day, date.dayOfMonth.toString())
            // 「今天」只走主色，**不许加粗**（`TextView` 没有 `setTypeface(int)`，
            // 反射会在宿主进程抛 `ActionException`）。相邻月的日数字走 muted ——
            // 那是这张卡上唯一表达「这个月从哪天开始」的地方。
            c.setTextColor(
                R.id.wg_mc_day,
                when {
                    isToday -> snap.accent
                    inMonth -> ink
                    else -> muted
                },
            )

            // 没班次就不画胶囊 —— 与 App 日历格一致（`shift == null` 时那块根本不画）。
            // **相邻月的格照样画**（用户 2026-09-30 选的「日数变灰、胶囊照画」）。
            // **不能**拿 `wg_empty_*` 顶上：`tintedChip` 里 `Paint.setAlpha` 会**覆盖**颜色
            // 字节自带的 alpha（fill 写死 36、stroke 写死 115），`#14000000` 会变成一条 45%
            // 的黑描边环，比 App 的长相响得多。正常排班里「休班」是一个**有颜色的班次定义**
            // （`hasShift == true`），照常画胶囊 —— 这条只影响空白表方案下的无班次日。
            if (d.hasShift) {
                c.setViewVisibility(R.id.wg_mc_pill, android.view.View.VISIBLE)
                c.setViewVisibility(R.id.wg_mc_abbr, android.view.View.VISIBLE)
                // 尺寸恒定 40×18dp：一格一尺寸会让 `WidgetChip` 的位图缓存失效
                // （key 含尺寸），42 格就把缓存冲爆。见本函数的 KDoc。
                c.setImageViewBitmap(
                    R.id.wg_mc_pill,
                    WidgetChip.tintedChip(d.color, dpToPx(context, 40), dpToPx(context, 18)),
                )
                c.setTextViewText(R.id.wg_mc_abbr, d.shiftAbbr)
                c.setTextColor(R.id.wg_mc_abbr, ink)
            } else {
                c.setViewVisibility(R.id.wg_mc_pill, android.view.View.GONE)
                c.setViewVisibility(R.id.wg_mc_abbr, android.view.View.GONE)
            }

            c.setViewVisibility(R.id.wg_mc_lunar, android.view.View.VISIBLE)
            c.setTextViewText(R.id.wg_mc_lunar, d.lunarShort)
            c.setTextColor(R.id.wg_mc_lunar, if (d.lunarIsHoliday) holiday else muted)

            v.addView(slotIds[slot], c)
        }
        return v
    }

    /**
     * 今日卡片。照搬 App 底栏信息卡的**完整版**（`calendar_screen.dart` 的 `_infoCard`，
     * 不是 `compact` 版），元素与配方逐项对照 spec §7。
     *
     * ⚠️ **跨天降级**：`todayCard` 里的农历、待办数、其他班组都是**生成那天**的，
     * 而跨天刷新时原生只能对表右移、重算不了。所以先拿 `todayCard.day` 跟今天比：
     * 对不上就把这三样留空，只显示 `days[todayIndex]` 里那份按日期烘焙的数据
     * （日期、班次、时间）。**绝不把旧数据当成今天显示。**
     *
     * 命名是 `renderTodayCard` 而不是 `todayCard`：快照里有个属性也叫 `snap.todayCard`，
     * 同一屏里 `val tc = snap.todayCard` 挨着 `todayCard(...)` 读起来太绕（控制方裁定）。
     *
     * ⚠️ 本函数渲染的内容**永远在外壳内**（唯一的调用方是 `todayStandalone` 的槽位），
     * 所以自己**不画**卡片底 —— 画了就是双层边：外壳根与卡片根铺同一张带 `1dp`
     * stroke / 22dp 圆角的 drawable，成品上会多出一圈圆角描边、悬在外壳边框内侧。
     * 卡片底只画一层，在外壳上。
     */
    private fun renderTodayCard(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_today_card)
        val dark = isDark(context, snap.themeMode)
        v.setOnClickPendingIntent(
            R.id.wg_tc_root,
            launchIntent(context, rootRequestCode(widgetId)),
        )

        val ink = context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light)
        val muted =
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light)

        // 日期/班次/时间/色点一律取 `days[todayIndex]` 而**不是** `todayCard` ——
        // `days[]` 会被原生对表右移、永远是对的；`todayCard` 不会。
        val d = snap.days[todayIndex]
        val tc = snap.todayCard
        val stale = tc == null || tc.day != LocalDate.now().toEpochDay()

        // ── 1. 日期行 ──
        // 位图高**必须等于布局里视图的高**（色条 24dp）：ImageView 是 `fitXY`，
        // 两者不等就是非等比拉伸，而 `bar()` 的圆头半径是按位图宽/高算的。
        v.setImageViewBitmap(
            R.id.wg_tc_bar,
            WidgetChip.bar(
                if (d.hasShift) d.color else snap.accent,
                dpToPx(context, 4),
                dpToPx(context, 24),
            ),
        )
        v.setTextViewText(R.id.wg_tc_date, d.dateShort)
        v.setTextColor(R.id.wg_tc_date, ink)

        // 「今天」徽章。宽度写死在布局里 —— RemoteViews 量不到文字宽度。
        // 高同样要与布局的 `wg_tc_today_wrap`（24dp）一致：`tintedChip` 的 radius 与
        // strokeWidth 都按**位图**高算，拉了 fitXY 会让两端的半圆变椭圆、上下描边偏重。
        v.setImageViewBitmap(
            R.id.wg_tc_today_bg,
            WidgetChip.tintedChip(snap.accent, dpToPx(context, 52), dpToPx(context, 24)),
        )
        v.setTextViewText(R.id.wg_tc_today_text, snap.today)
        v.setTextColor(R.id.wg_tc_today_text, snap.accent)

        // 「N 项待办」徽章。`todoBadge` 为空（没有待办）或快照跨天 → 整块隐藏。
        val todoText = if (stale) null else tc.todoBadge
        if (todoText == null) {
            v.setViewVisibility(R.id.wg_tc_todo_wrap, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_todo_wrap, android.view.View.VISIBLE)
            v.setImageViewBitmap(
                R.id.wg_tc_todo_bg,
                WidgetChip.tintedChip(snap.accent, dpToPx(context, 84), dpToPx(context, 24)),
            )
            v.setTextViewText(R.id.wg_tc_todo_text, todoText)
            v.setTextColor(R.id.wg_tc_todo_text, snap.accent)
        }

        // ── 2. 农历：跨天就隐藏（它是生成那天的） ──
        // 4×3 比原来的紧凑档高出约 95dp，多出来的地方要放**真内容**：
        // 换用 `LunarInfo.fullDescription`（App 完整版信息卡用的就是它），
        // 因此布局里那行是 maxLines="2"。
        if (stale) {
            v.setViewVisibility(R.id.wg_tc_lunar, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_lunar, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_tc_lunar, tc.lunarFull)
            v.setTextColor(
                R.id.wg_tc_lunar,
                if (tc.lunarIsHoliday) {
                    context.getColor(R.color.wg_holiday)
                } else {
                    muted
                },
            )
        }

        // ── 3. 班次行 ──
        v.setImageViewBitmap(
            R.id.wg_tc_dot,
            WidgetChip.circle(
                if (d.hasShift) {
                    d.color
                } else {
                    context.getColor(if (dark) R.color.wg_empty_dark else R.color.wg_empty_light)
                },
                dpToPx(context, 12),
            ),
        )
        v.setTextViewText(R.id.wg_tc_shift, if (d.hasShift) d.shiftName else d.weekday)
        v.setTextColor(R.id.wg_tc_shift, ink)

        // 「已调班」徽章：底色跟当天班次色走（与 App 信息卡的 `_adjustedBadge` 同源）。
        // 与色条/色点一致地**回落**：休班日 `d.color` 是 Dart 侧的 `shift?.color ?? 0`
        // = 0（全透明），直接用会得到一个占 96dp 却什么也看不见的徽章。
        if (stale || !tc.adjusted) {
            v.setViewVisibility(R.id.wg_tc_adj_wrap, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_adj_wrap, android.view.View.VISIBLE)
            v.setImageViewBitmap(
                R.id.wg_tc_adj_bg,
                WidgetChip.tintedChip(
                    if (d.hasShift) d.color else snap.accent,
                    dpToPx(context, 96),
                    dpToPx(context, 24),
                ),
            )
            v.setTextViewText(R.id.wg_tc_adj_text, snap.adjustedBadge)
            v.setTextColor(R.id.wg_tc_adj_text, if (d.hasShift) d.color else snap.accent)
        }

        // ── 4. 时间 ──
        if (d.timeRange == null) {
            v.setViewVisibility(R.id.wg_tc_time, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_time, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_tc_time, d.timeRange)
            v.setTextColor(R.id.wg_tc_time, muted)
        }

        // ── 5. 其他班组：跨天就整行隐藏（那是生成那天的） ──
        val crews = if (stale) emptyList() else tc.crews.take(4)
        val crewSlots = intArrayOf(
            R.id.wg_tc_crew_slot1, R.id.wg_tc_crew_slot2,
            R.id.wg_tc_crew_slot3, R.id.wg_tc_crew_slot4,
        )
        if (crews.isEmpty()) {
            v.setViewVisibility(R.id.wg_tc_crew_row, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_tc_crew_row, android.view.View.VISIBLE)
            for (slot in crewSlots.indices) {
                // 先清空再填，理由与 `weekStrip` 那处逐字相同。
                v.removeAllViews(crewSlots[slot])
                if (slot >= crews.size) {
                    v.setViewVisibility(crewSlots[slot], android.view.View.GONE)
                    continue
                }
                v.setViewVisibility(crewSlots[slot], android.view.View.VISIBLE)
                val crew = crews[slot]
                val chip = RemoteViews(context.packageName, R.layout.widget_crew_chip)
                chip.setImageViewBitmap(
                    R.id.wg_cc_bg,
                    WidgetChip.tintedChip(crew.color, dpToPx(context, 14), dpToPx(context, 14)),
                )
                chip.setImageViewBitmap(
                    R.id.wg_cc_dot,
                    WidgetChip.circle(crew.color, dpToPx(context, 8)),
                )
                chip.setTextViewText(R.id.wg_cc_text, "${crew.name} ${crew.abbr}")
                // 文字色固定走 muted：胶囊底是 14% 淡染、卡片底近不透明，两者都够对比度。
                // 这里**有意偏离** App 的 `AppTokens.inkFor` —— 那套「按底色算可读色」要
                // luminance 计算，为一行 11sp 的小字在原生复刻一份不值当，而快照里也没有
                // 现成的对比色可拿。
                chip.setTextColor(R.id.wg_cc_text, muted)
                v.addView(crewSlots[slot], chip)
            }
        }

        return v
    }

    /**
     * 4×3 今日卡：外壳（画卡底）+ 嵌套 [renderTodayCard]。
     *
     * 与旧版最大的差别是**不再套在网格下面** —— 它是独立的一张卡，
     * 尺寸固定，所以内容按 4×3 排版（大一号的字、`lunarFull` 两行）。
     */
    private fun todayStandalone(
        context: Context,
        snap: WidgetStore.Snapshot,
        todayIndex: Int,
        widgetId: Int,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_today_standalone)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_ts_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        // 整卡点击设**外壳根**上：外壳铺满整个小组件，而内层卡片是 wrap_content 高、
        // 被 `gravity="center_vertical"` 居中 —— 卡底画到了上下那两截留白上，只在卡片上设
        // 点击就有一圈「看得见但不响应」的死区（4×3 下各约 34dp）。这条与
        // `weekStrip` / `monthCard` / `empty` / `placeholder` 一致，见那几处的 KDoc。
        v.setOnClickPendingIntent(R.id.wg_ts_root, launchIntent(context, rootRequestCode(widgetId)))
        // 先清空再填 —— 这一处塞进去的是**整棵今日卡子树**，叠起来比一格重影严重得多：
        // 槽位是个竖向 LinearLayout，多余的副本会往下排、把卡片撑出外壳后被裁掉。
        // 完整的机制说明见 `weekStrip` 那处。
        v.removeAllViews(R.id.wg_ts_slot)
        v.addView(R.id.wg_ts_slot, renderTodayCard(context, snap, todayIndex, widgetId))
        return v
    }

    /**
     * 空表态：没有排班（`snap.hasSchedule == false`）。
     *
     * 三张卡共用一张布局（`widget_empty`）—— 空表本来也没什么可说的，三档各写一张
     * 只会长成三个样。它原先挂在紧凑列表的壳上，那张壳随旧版式一起删了。
     *
     * 文案来自快照的 `emptyHint`（Dart 侧 `L10n.widgetEmptyHint` 产出）——
     * Kotlin 侧仍然一个字面量都没有。
     */
    private fun empty(context: Context, snap: WidgetStore.Snapshot, widgetId: Int): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_empty)
        val dark = isDark(context, snap.themeMode)
        v.setInt(
            R.id.wg_e_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        v.setOnClickPendingIntent(R.id.wg_e_root, launchIntent(context, rootRequestCode(widgetId)))
        v.setTextViewText(R.id.wg_e_hint, snap.emptyHint)
        v.setTextColor(
            R.id.wg_e_hint,
            context.getColor(if (dark) R.color.wg_ink_dark else R.color.wg_ink_light),
        )
        return v
    }

    private fun placeholder(context: Context, dark: Boolean, widgetId: Int): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_placeholder)
        v.setInt(
            R.id.wg_ph_root,
            "setBackgroundResource",
            if (dark) R.drawable.widget_card_dark else R.drawable.widget_card_light,
        )
        // 占位态也要能点开 App —— 它多半是「还没有快照」，点进去最该做的是打开
        // App 让它推一份下来。
        v.setOnClickPendingIntent(R.id.wg_ph_root, launchIntent(context, rootRequestCode(widgetId)))
        v.setImageViewResource(R.id.wg_ph_icon, R.mipmap.ic_launcher)
        v.setTextViewText(
            R.id.wg_ph_label,
            context.applicationInfo.loadLabel(context.packageManager).toString(),
        )
        v.setTextColor(
            R.id.wg_ph_label,
            context.getColor(if (dark) R.color.wg_muted_dark else R.color.wg_muted_light),
        )
        return v
    }
}
