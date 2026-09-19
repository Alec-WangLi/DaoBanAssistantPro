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
 * 三条纪律：
 *  1. Kotlin 侧一个中文字面量都不许有。所有文案都来自快照（Dart 侧 `L10n` 产出）。
 *     唯一的例外是占位态那行应用名，它取自 `applicationInfo.loadLabel()`。
 *  2. 明暗一律**显式选资源**，不依赖 `-night` 限定符 —— `RemoteViews` 由宿主进程
 *     inflate，限定符在宿主进程里的解析顺序各家 ROM 不一致。
 *  3. 布局只用 RemoteViews 白名单里的类：FrameLayout / LinearLayout / RelativeLayout /
 *     GridLayout + TextView / ImageView。**没有 ConstraintLayout**，报的是运行期
 *     `ClassNotFoundException`，不是编译错误。
 */
object WidgetRenderer {

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
     * 班次闹钟 0..400、自定义闹钟 10000..11000、待办提醒 20000..21000，另有
     * `AlarmRingService` 的通知点击 0 / 1（同样带着 `alarm_label` 打向 `MainActivity`）
     * 与 `MainActivity.REQ_PICK_RINGTONE = 40071`。取 100000 起，全部避开。
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

    /** 整卡的 requestCode：低位 0 留给「不指定日期」。 */
    private fun rootRequestCode(widgetId: Int): Int = WIDGET_REQ_BASE + widgetId * REQ_SLOTS_PER_WIDGET

    /** 第 cell 格的 requestCode。低位 +1 起，避开 `rootRequestCode` 的 0。 */
    private fun cellRequestCode(widgetId: Int, cell: Int): Int =
        WIDGET_REQ_BASE + widgetId * REQ_SLOTS_PER_WIDGET + 1 + cell

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
     * 4×5 整月：月份标题 + 周几行 + 6×7 格。
     *
     * **渲染哪个月由 `LocalDate.now()` 定**，不由快照的生成月定：快照窗口覆盖
     * 「本月 + 下月」（spec §7.1），跨月那一刻零点那次刷新会重渲染，此时今天已经
     * 落在新的一个月里 —— 数据早就在窗口里，不需要 App 活着。
     *
     * **前导空格**由本月 1 日的星期几现算（周一 = 1）—— 纯日期算术，不是 i18n，
     * 与不变量 (A) 不冲突。
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
     * 不收 `todayIndex`：本卡渲染的是 `LocalDate.now()` 那个月，「今天」是按日期现算的
     * （见上），拿不到快照里那份下标也用不上。
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

        // ── 月份标题 ──
        val title = snap.months.firstOrNull { it.y == today.year && it.m == today.monthValue }
        if (title == null) {
            v.setViewVisibility(R.id.wg_m_title, android.view.View.GONE)
        } else {
            v.setViewVisibility(R.id.wg_m_title, android.view.View.VISIBLE)
            v.setTextViewText(R.id.wg_m_title, title.title)
            v.setTextColor(R.id.wg_m_title, muted)
        }

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

        // ── 42 格 ──
        val firstOfMonth = today.withDayOfMonth(1)
        val leading = firstOfMonth.dayOfWeek.value - 1   // 周一 = 1 → 前导空格数
        val daysInMonth = firstOfMonth.lengthOfMonth()
        val slotIds = IntArray(42) { i ->
            context.resources.getIdentifier("wg_m_slot${i + 1}", "id", context.packageName)
        }

        for (slot in 0 until 42) {
            val dayOfMonth = slot - leading + 1
            if (dayOfMonth < 1 || dayOfMonth > daysInMonth) {
                // 前导/尾随空格：GONE —— GridLayout 里 GONE 的子视图不参与布局。
                v.setViewVisibility(slotIds[slot], android.view.View.GONE)
                continue
            }
            val date = firstOfMonth.withDayOfMonth(dayOfMonth)
            val epoch = date.toEpochDay()
            val i = snap.days.indexOfFirst { it.day == epoch }
            if (i < 0) {
                // 窗口里没有这天（理论上不会发生）。当成空格而不是「没班次」——
                // 后者会画出一张理直气壮的空格。
                v.setViewVisibility(slotIds[slot], android.view.View.GONE)
                continue
            }
            v.setViewVisibility(slotIds[slot], android.view.View.VISIBLE)

            // 点某一格 → 打开 App 并跳到那天。格子占槽位 1..42（一个实例 64 个槽位）。
            v.setOnClickPendingIntent(
                slotIds[slot],
                launchIntent(context, cellRequestCode(widgetId, slot), epochDay = epoch.toInt()),
            )

            val d = snap.days[i]
            val isToday = epoch == todayEpoch
            val c = RemoteViews(context.packageName, R.layout.widget_month_cell)

            // 可见性两个方向都要设满：宿主 `reapply` 只重放新动作，漏设的一边会留着
            // 上一次的状态。
            c.setViewVisibility(R.id.wg_mc_day, android.view.View.VISIBLE)
            c.setTextViewText(R.id.wg_mc_day, dayOfMonth.toString())
            // 「今天」只走主色，**不许加粗**（`TextView` 没有 `setTypeface(int)`，
            // 反射会在宿主进程抛 `ActionException`）。
            c.setTextColor(R.id.wg_mc_day, if (isToday) snap.accent else ink)

            // 没班次就不画胶囊 —— 与 App 日历格一致（`shift == null` 时那块根本不画）。
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
        // 位图高**必须等于布局里视图的高**（色条 22dp）：ImageView 是 `fitXY`，
        // 两者不等就是非等比拉伸，而 `bar()` 的圆头半径是按位图宽/高算的。
        v.setImageViewBitmap(
            R.id.wg_tc_bar,
            WidgetChip.bar(
                if (d.hasShift) d.color else snap.accent,
                dpToPx(context, 4),
                dpToPx(context, 22),
            ),
        )
        v.setTextViewText(R.id.wg_tc_date, d.dateShort)
        v.setTextColor(R.id.wg_tc_date, ink)

        // 「今天」徽章。宽度写死在布局里 —— RemoteViews 量不到文字宽度。
        // 高同样要与布局的 `wg_tc_today_wrap`（22dp）一致：`tintedChip` 的 radius 与
        // strokeWidth 都按**位图**高算，拉了 fitXY 会让两端的半圆变椭圆、上下描边偏重。
        v.setImageViewBitmap(
            R.id.wg_tc_today_bg,
            WidgetChip.tintedChip(snap.accent, dpToPx(context, 52), dpToPx(context, 22)),
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
                WidgetChip.tintedChip(snap.accent, dpToPx(context, 84), dpToPx(context, 22)),
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
                    dpToPx(context, 22),
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
