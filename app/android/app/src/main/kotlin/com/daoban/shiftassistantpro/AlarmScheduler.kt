package com.daoban.shiftassistantpro

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.ApplicationExitInfo
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Calendar
import java.util.Locale

/**
 * 原生闹钟统一排定：setAlarmClock → AlarmReceiver（前台服务响铃 + 全屏 + 续排）。
 *
 * 一次性闹钟只排一次；每天/每周闹钟在触发后由 AlarmReceiver 用同一 id 自动续排下一次，
 * 因此每个重复闹钟始终只有一条待触发的 AlarmManager 记录，不会累积。
 */
object AlarmScheduler {

    /** 自定义闹钟的原生 id 基址（id = 10000 + 数据库自增 id），与排班闹钟 0..359 隔离。 */
    const val CUSTOM_BASE_ID = 10000

    /**
     * 待办提醒的原生 id 基址（id = 20000 + 数据库里那一行的自增 id）。
     *
     * **`AUTOINCREMENT` 永不复用**，所以这个号只增不减。留到 39999（两万槽）：
     * 一个「每天」的重复待办每完成一次就产生一行，两三年就能把一千个号用光 ——
     * 而从前只留了 1000，越界之后提醒**排得下去、谁也取消不掉**（幽灵提醒）。
     */
    const val TODO_BASE_ID = 20000

    /**
     * 重复待办提醒的原生 id 基址（id = 40000 + 系列的自增 id）。
     *
     * **与待办行的号段分开**是有意的：系列的条数由用户手建，几十条就到头了，而
     * 待办行会越攒越多 —— 两者共用一个自增序列的话，行号迟早把提醒的号挤出去。
     * 留到 41999。
     */
    const val RECURRING_BASE_ID = 40000

    /**
     * 排一条「安静的」提醒：到点只弹一条通知，不响铃、不全屏、不进系统闹钟栏。
     *
     * 与 [schedule] 的两点不同，都是刻意的：
     *
     *  - 用 `setExactAndAllowWhileIdle` 而不是 `setAlarmClock`。后者会被系统当成
     *    真闹钟：状态栏常驻闹钟图标、时钟应用的「下次闹钟」里也会列出来。对一条
     *    「交体检报告」太重了，用户会以为手机一直在设闹钟。
     *  - 精确闹钟权限没给（`canScheduleExactAlarms` 为假）时**退化成非精确**排定，
     *    宁可晚几分钟也不静默不响。少数 ROM 上前面报 true、`setExact...` 仍抛
     *    `SecurityException`，所以那条路也再兜一次。
     */
    fun scheduleQuiet(
        context: Context,
        id: Int,
        millis: Long,
        title: String,
        body: String,
        repeatTimes: LongArray = LongArray(0)
    ) {
        val q = armQuiet(context, id, millis, title, body, repeatTimes)
        // 与闹钟同样落盘一份：重启后 AlarmManager 里的记录会被清空，只有这份清单
        // 能让 BootReceiver 把提醒排回去。放在排定之后写 —— 精确 / 退化 / 再退化的
        // 结果都该进清单，否则「没有精确闹钟权限」的机器上一重启提醒就全没了。
        AlarmStore.putQuiet(context, q)
    }

    /**
     * 排一条安静提醒并返回它的落盘记录（**不写库**）。
     *
     * 精确闹钟权限没给时退化成非精确，`setExact` 被个别 ROM 拒绝时再退一次 ——
     * 两条退路都是「宁可晚几分钟也不静默不响」。
     */
    internal fun armQuiet(
        context: Context,
        id: Int,
        millis: Long,
        title: String,
        body: String,
        repeatTimes: LongArray
    ): AlarmStore.Quiet {
        val op = Intent(context, TodoReminderReceiver::class.java).apply {
            putExtra("id", id)
            putExtra("title", title)
            putExtra("body", body)
            // 后面还跟着的几次点火时刻（升序）。空数组 = 一次性提醒，与从前一样。
            putExtra("repeatTimes", repeatTimes)
        }
        val pi = PendingIntent.getBroadcast(
            context, id, op,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !am.canScheduleExactAlarms()
            ) {
                AlarmLog.info(context, "scheduleQuiet: 无精确闹钟权限，退化为非精确排定")
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, pi)
            }
        } catch (e: SecurityException) {
            AlarmLog.error(
                context,
                "scheduleQuiet: setExact 被拒(${e.message})，退化为非精确排定"
            )
            try {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, pi)
            } catch (e2: Exception) {
                AlarmLog.error(context, "scheduleQuiet: 退化排定也失败: ${e2.message}")
            }
        }
        return AlarmStore.Quiet(
            id = id, millis = millis, title = title, body = body,
            repeatTimes = repeatTimes.toList()
        )
    }

    /**
     * 取消全部待办提醒与待办闹钟。
     *
     * **按落盘清单逐个撤，不再盲目扫一大段 id。** 从前扫的是固定 1000 个号，而
     * 现在待办提醒能排到 [RECURRING_BASE_ID] 附近 —— 盲扫会变成几万次
     * `PendingIntent` 操作，而**每勾一次待办都要跑一遍这一段**。
     *
     * 末尾保留一小段盲扫（`TODO_BASE_ID .. +1000`）：只为清掉「升级前排下、清单里
     * 还没有」的陈旧记录。这一段的开销与从前的实现相同，所以不引入新的性能代价。
     *
     * [keepStore]：升级后的**一次性清扫**用。清扫与随后那次整批重排之间进程若被杀，
     * 清单里还留着旧的一批，开机重排能排回去；不 keep 的话那一段里「零闹钟、零清单」
     * —— 正是 v0.13.18 要消灭的那类静默。
     */
    fun cancelTodoReminders(context: Context, keepStore: Boolean = false) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // **两种目标都要取消**：同一条待办按「联动闹钟」开关二选一 —— 开走
        // AlarmReceiver（响铃），关走 TodoReminderReceiver（通知）。两者用的是
        // 同一个 id，只取消一种就会把另一种留成幽灵闹钟，到点还会响。
        val targets = listOf(AlarmReceiver::class.java, TodoReminderReceiver::class.java)
        val upper = RECURRING_BASE_ID + 2000
        val ids = mutableSetOf<Int>()
        // ① 清单里记着的（准确、量小）
        for (e in AlarmStore.all(context)) {
            if (e.id in TODO_BASE_ID until upper) ids.add(e.id)
        }
        for (q in AlarmStore.allQuiets(context)) {
            if (q.id in TODO_BASE_ID until upper) ids.add(q.id)
        }
        // ② 一小段盲扫兜底：旧版本用过、清单里没有的那些
        for (i in 0 until 1000) ids.add(TODO_BASE_ID + i)

        for (id in ids) {
            for (target in targets) {
                try {
                    val pi = PendingIntent.getBroadcast(
                        context,
                        id,
                        // 只比 action/data/type/class/categories，extras 不参与，
                        // 所以空 Intent 也能稳稳取消掉排定时那个。
                        Intent(context, target),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    am.cancel(pi)
                } catch (_: Exception) {
                }
            }
        }
        // 两份清单同步清掉这两段（清了之后 Dart 会把要留的重新排一遍）。
        if (keepStore) return
        AlarmStore.clearQuiets(context, TODO_BASE_ID, upper)
        AlarmStore.clearEntries(context, TODO_BASE_ID, upper)
    }

    fun schedule(
        context: Context,
        id: Int,
        millis: Long,
        label: String,
        uri: String?,
        repeatType: Int = 0,
        hour: Int = 0,
        minute: Int = 0,
        weekdays: Int = 0,
        detail: String? = null,
        repeatTimes: LongArray = LongArray(0)
    ) {
        // 排定与落盘必须成对：漏了这条记录，那个闹钟以后就只在「App 打开过」的
        // 情况下能响（重启后 BootReceiver 只能照清单排）。
        AlarmStore.put(
            context,
            arm(context, id, millis, label, uri, repeatType, hour, minute,
                weekdays, detail, repeatTimes)
        )
    }

    /**
     * 排一条响铃闹钟并返回它的落盘记录（**不写库**）。
     *
     * 批量重排（[reconcile]）与巡检（`AlarmRestorer`）都走这里：攒齐一批之后
     * 一次落盘，而不是每条都把整份清单重新序列化一遍。
     */
    internal fun arm(
        context: Context,
        id: Int,
        millis: Long,
        label: String,
        uri: String?,
        repeatType: Int,
        hour: Int,
        minute: Int,
        weekdays: Int,
        detail: String?,
        repeatTimes: LongArray
    ): AlarmStore.Entry {
        // showIntent：系统「闹钟图标/通知」用的 Activity，点击回到本 App。
        val show = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            putExtra("alarm_label", label)
            putExtra("alarm_detail", detail)
        }
        val showPi = PendingIntent.getActivity(
            context, id, show,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // operation：到点触发 AlarmReceiver（前台服务响铃 + 全屏 + 续排下一次）。
        val op = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("label", label)
            putExtra("uri", uri)
            putExtra("id", id)
            putExtra("repeatType", repeatType)
            putExtra("hour", hour)
            putExtra("minute", minute)
            putExtra("weekdays", weekdays)
            putExtra("detail", detail)
            // 时刻表驱动（`repeatType == 3`）时后面还跟着的几次（升序）。
            // showIntent 那枚 PendingIntent 不用带：它只负责点通知回 App。
            putExtra("repeatTimes", repeatTimes)
        }
        val opPi = PendingIntent.getBroadcast(
            context, id, op,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAlarmClock(AlarmManager.AlarmClockInfo(millis, showPi), opPi)

        return AlarmStore.Entry(
            id = id, millis = millis, label = label, uri = uri,
            repeatType = repeatType, hour = hour, minute = minute,
            weekdays = weekdays, detail = detail,
            repeatTimes = repeatTimes.toList()
        )
    }

    // -----------------------------------------------------------------------
    // 一批排定（先排后清）
    // -----------------------------------------------------------------------

    /** 一条要排的响铃闹钟（Dart 侧 `NativeAlarm` 的对应物）。 */
    data class AlarmSpec(
        val id: Int,
        val millis: Long,
        val label: String,
        val repeatType: Int,
        val hour: Int,
        val minute: Int,
        val weekdays: Int,
        val detail: String?,
        val repeatTimes: LongArray,
    )

    /** 一条要排的安静提醒（Dart 侧 `NativeQuiet` 的对应物）。 */
    data class QuietSpec(
        val id: Int,
        val millis: Long,
        val title: String,
        val body: String,
        val repeatTimes: LongArray,
    )

    private val fmt: DateTimeFormatter =
        DateTimeFormatter.ofPattern("MM-dd HH:mm", Locale.getDefault())

    /**
     * 整批重排：**先把新计划全部排上，再撤掉多余的那些**。
     *
     * 旧实现（2026-11 及以前）是「先把几段 id 盲扫全撤 + 清空落盘清单，再一条条
     * 排回来」。中间有几秒系统里一条闹钟都没有，而每次闹钟响都会冷启动 App 并
     * 整链重排 —— 进程死在那段窗口里就停在「已清空、还没排完」，此后全哑
     * （2026-11-22 三星用户「6 点没响」的复盘）。这里顺序反过来：任何瞬间系统里
     * 都至少有「旧的」那一批。
     *
     * [cancelIds] 由 Dart 侧按差集算好（纯函数、有用例），原生不会自行撤别的 id。
     * [ranges] 是本次重排拥有的号段，只用于**合并式落盘**（段外原样保留）。
     */
    fun reconcile(
        context: Context,
        alarms: List<AlarmSpec>,
        quiets: List<QuietSpec>,
        cancelIds: IntArray,
        ranges: List<IntArray>,
    ): ReconcileSummary {
        val started = System.currentTimeMillis()
        // 铃声是全局设置（与从前 `MainActivity.scheduleNativeAlarm` 读的是同一个键）。
        val uri = context
            .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.ringtoneUri", null)

        var failed = 0
        val entries = ArrayList<AlarmStore.Entry>(alarms.size)
        for (a in alarms) {
            try {
                entries.add(
                    arm(context, a.id, a.millis, a.label, uri, a.repeatType,
                        a.hour, a.minute, a.weekdays, a.detail, a.repeatTimes)
                )
            } catch (e: Exception) {
                failed++
                // **失败也进清单**：清单的语义是「应当存在的那一批」，巡检
                // （`AlarmRestorer`）与开机重排都会拿它再试一次。
                entries.add(
                    AlarmStore.Entry(
                        id = a.id, millis = a.millis, label = a.label, uri = uri,
                        repeatType = a.repeatType, hour = a.hour, minute = a.minute,
                        weekdays = a.weekdays, detail = a.detail,
                        repeatTimes = a.repeatTimes.toList()
                    )
                )
                AlarmLog.error(
                    context,
                    "AlarmScheduler: 排定失败 id=${a.id} ${e.javaClass.simpleName}: ${e.message}"
                )
            }
        }
        val quietEntries = ArrayList<AlarmStore.Quiet>(quiets.size)
        for (q in quiets) {
            quietEntries.add(armQuiet(context, q.id, q.millis, q.title, q.body, q.repeatTimes))
        }

        // 一批只落一次盘（O(n²) → O(n)）。
        AlarmStore.replaceInRanges(context, entries, ranges)
        AlarmStore.replaceQuietsInRanges(context, quietEntries, ranges)

        // 最后才撤：走到这里，这一批已经全部在系统里了。
        var cancelled = 0
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // **同一批里每个 id 都只该留在它自己的那条链路上**：待办的「联动闹钟」开关
        // 可以让同一个 id 在 AlarmReceiver ↔ TodoReminderReceiver 之间换通道，而差集
        // 只回答「这个 id 还要不要」—— 换通道时 id 仍在计划里，`cancelIds` 不会包含它，
        // 旧的那条就永远留着：到点既全屏响铃又弹通知（重复待办更糟，两条链路各自
        // 续排，每次发生日都双响）。旧实现靠「盲扫时两种目标一起撤」顺带治好了它。
        for (a in alarms) cancelOtherChannel(context, am, a.id, AlarmReceiver::class.java)
        for (q in quiets) cancelOtherChannel(context, am, q.id, TodoReminderReceiver::class.java)
        for (id in cancelIds) {
            // 两种目标都要撤：这个 id 已经整个不要了，撞上哪个撤哪个。
            am.cancel(pendingIntent(context, id, AlarmReceiver::class.java))
            am.cancel(pendingIntent(context, id, TodoReminderReceiver::class.java))
            cancelled++
        }

        val elapsed = System.currentTimeMillis() - started
        AlarmLog.diagnostic(
            context,
            "AlarmScheduler: 重排完成 排 ${entries.size} 铃 / ${quietEntries.size} 静，" +
                "撤 $cancelled 条" + (if (failed > 0) " 失败 $failed 条" else "") +
                "，用时 ${elapsed}ms，下一跳 ${nextDigest(context, System.currentTimeMillis())}"
        )
        // 巡检：系统/厂商把闹钟整条取消时（三星「休眠应用」就是这样），下一次
        // 巡检把它们排回来 —— 不必等用户打开 App。
        AlarmWatchdog.ensureScheduled(context)
        return ReconcileSummary(
            armed = entries.size - failed,
            quieted = quietEntries.size,
            cancelled = cancelled,
            failed = failed,
            elapsedMs = elapsed,
        )
    }

    /** 「下一跳」：清单里还没到点的最早一条（响铃与提醒一起比）。 */
    fun nextDigest(context: Context, now: Long): String {
        val e = AlarmStore.all(context).filter { it.millis > now }.minByOrNull { it.millis }
        val q = AlarmStore.allQuiets(context).filter { it.millis > now }.minByOrNull { it.millis }
        val at = listOfNotNull(e?.millis, q?.millis).minOrNull() ?: return "无"
        val id = if (e != null && e.millis == at) e.id else q?.id
        return "${formatAt(at)} id=$id"
    }

    /** 毫秒时刻 → 日志里的 `MM-dd HH:mm`。 */
    fun formatAt(millis: Long): String =
        Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).format(fmt)

    // -----------------------------------------------------------------------
    // 启动取证（v0.13.22）
    // -----------------------------------------------------------------------

    /**
     * 进程启动那一刻的「系统 vs 自己的清单」快照。**必须在 Dart 重排之前调用。**
     *
     * **为什么要抢在重排之前**：`reschedule` 一跑就会把「清单里有、新计划里没有」
     * 的条目（包括已经过期的那一条）撤掉，实测进程起来约 **180ms** 之后就会发生。
     * 之后导出的诊断包、`nextDigest`、`alarms.json` 全是**改过之后**的状态 ——
     * 于是「系统把闹钟删了」和「系统没把广播递过来」这两件事永远分不开。
     *
     * **怎么读这一行**（诊断包 README 里也写着）：
     *  - `系统下一跳` 与 `清单最早` **是同一个时刻**（哪怕它已经过期）→ 那条记录
     *    还在 `AlarmManager` 里，是**投递**被拦（进程起不来 / 被冻结）；
     *  - `系统下一跳` **更晚或为「无」**，而清单里那条已经过期 → 记录**已经被删**
     *    （被清理 / 被强行停止 / 权限被撤）。
     *
     * `AlarmManager.getNextAlarmClock()` 是**全系统**的下一枚闹钟（可能来自别的
     * App），所以只有「它比我们那条更晚」这一侧是确定的判据 —— 反过来不成立。
     */
    fun startupSnapshot(context: Context, now: Long): String {
        val sys = try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.nextAlarmClock?.triggerTime
        } catch (_: Throwable) {
            null
        }
        val e = AlarmStore.all(context).minByOrNull { it.millis }
        val q = AlarmStore.allQuiets(context).minByOrNull { it.millis }
        val storeAt: Long?
        val storeId: Int?
        if (e != null && (q == null || e.millis <= q.millis)) {
            storeAt = e.millis
            storeId = e.id
        } else {
            storeAt = q?.millis
            storeId = q?.id
        }
        val sysText = if (sys == null) "无" else formatAt(sys)
        val storeText = if (storeAt == null) {
            "无"
        } else {
            "${formatAt(storeAt)} id=$storeId" + (if (storeAt <= now) "（已过期）" else "")
        }
        return "启动快照（重排前）：系统下一跳 $sysText / 清单最早 $storeText"
    }

    /**
     * 上一次进程是怎么没的 —— 分清「被强行停止 / 一键清理」与「被系统冻结」。
     *
     * 这两件事在日志里长得一模一样（都没有 onReceive、清单都在），只有这里能分开：
     *  - `REASON_USER_REQUESTED(10)`：用户或清理工具强行停止（force-stop / 最近任务
     *    划掉 / 一键清理）—— **会把这个包已排的闹钟全部撤掉**；
     *  - `REASON_FREEZER(14)`：被系统的应用冻结器（cached app freezer）杀掉的；
     *  - **「无记录」本身也是证据**：正常情况下历史里至少有上一次的退出原因。
     *
     * 只取最近一条；读不到不影响任何功能（纯取证）。
     */
    fun lastExitDigest(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return "上次退出原因：Android 11 以下没有这个接口"
        }
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val info = am.getHistoricalProcessExitReasons(context.packageName, 0, 1)
                .firstOrNull()
            if (info == null) {
                "上次退出原因：无记录"
            } else {
                "上次退出原因：${exitReasonName(info.reason)}" +
                    "（${formatAt(info.timestamp)}，status=${info.status}）"
            }
        } catch (e: Throwable) {
            "上次退出原因：读不到（${e.javaClass.simpleName}: ${e.message}）"
        }
    }

    /**
     * [ApplicationExitInfo.reason] → 人话。
     *
     * **常量值写死、不引用 `ApplicationExitInfo.REASON_*`**：其中好几个（FREEZER /
     * USER_STOPPED / PACKAGE_UPDATED…）是 API 31 才加的字段，引用它们会被 Android
     * Lint 的 `NewApi` 拦下（`android-lint.yml` 守着），而我们这里只是比大小。
     * 这些数字在系统里是固定的，注释里挂着常量名，改不动。
     */
    private fun exitReasonName(reason: Int): String = when (reason) {
        10 -> "中途被要求结束(10=REASON_USER_REQUESTED，含强行停止/一键清理)"
        11 -> "被用户停止(11=REASON_USER_STOPPED)"
        14 -> "被系统冻结器杀掉(14=REASON_FREEZER)"
        3 -> "低内存(3=REASON_LOW_MEMORY)"
        4 -> "崩溃(4=REASON_CRASH)"
        5 -> "原生崩溃(5=REASON_CRASH_NATIVE)"
        6 -> "无响应(6=REASON_ANR)"
        2 -> "被信号杀死(2=REASON_SIGNALED)"
        9 -> "资源超限(9=REASON_EXCESSIVE_RESOURCE_USAGE)"
        8 -> "权限变更(8=REASON_PERMISSION_CHANGE)"
        12 -> "依赖进程死亡(12=REASON_DEPENDENCY_DIED)"
        15 -> "包状态变更(15=REASON_PACKAGE_STATE_CHANGE)"
        16 -> "包被更新(16=REASON_PACKAGE_UPDATED)"
        else -> "其他($reason)"
    }

    private fun pendingIntent(context: Context, id: Int, target: Class<*>): PendingIntent =
        PendingIntent.getBroadcast(
            context, id, Intent(context, target),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    /**
     * 撤掉同一个 id 在**另一条链路**上的 PendingIntent。
     *
     * 两条链路用的是同一个 id（`_eventBaseId + 行 id` / `_recurringBaseId + 系列 id`），
     * 换通道时只换目标组件 —— 而 `PendingIntent` 的身份是「requestCode + 目标组件」，
     * 所以另一条链路上那条是**另一枚独立的 PendingIntent**，不撤它就一直留在
     * `AlarmManager` 里：到点既全屏响铃又弹通知；重复待办更糟，两条链路各自续排，
     * 每个发生日都双响。
     *
     * **只在「刚排上这条链路」之后调**：它撤的是另一侧，不会碰到本批刚排好的那枚。
     * 用 `FLAG_NO_CREATE` —— 不存在就什么都不做，别顺手为 600 个 id 造出空 PI。
     */
    internal fun cancelOtherChannel(
        context: Context,
        am: AlarmManager,
        id: Int,
        armed: Class<*>,
    ) {
        val other =
            if (armed == AlarmReceiver::class.java) TodoReminderReceiver::class.java
            else AlarmReceiver::class.java
        val pi = PendingIntent.getBroadcast(
            context, id, Intent(context, other),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        ) ?: return
        am.cancel(pi)
    }

    data class ReconcileSummary(
        val armed: Int,
        val quieted: Int,
        val cancelled: Int,
        val failed: Int,
        val elapsedMs: Long,
    )

    /**
     * 从「本次时刻 + 后续队列」里挑出第一个还没过的时刻，连同剩下的队列。
     *
     * 队列是 Dart 侧算好的（`upcomingFireTimes`，见 `alarm_service.dart` 的
     * `planRecurringReminders`）。**规则判断一律不写在这里**：Kotlin 侧没有可跑的
     * 测试目标，而月末特例 / 多选星期几 / 提前提醒的偏移 / 夏令时这些边角照抄
     * 一份必然与 Dart 侧对不上 —— 症状还是「某天没响」这种不报错的。
     *
     * 全过了（或队列为空、时刻本身也过了）返回 null，由调用方决定「不再续排」。
     */
    fun nextPending(millis: Long, queue: LongArray, now: Long): Pair<Long, LongArray>? {
        val all = LongArray(queue.size + 1)
        all[0] = millis
        System.arraycopy(queue, 0, all, 1, queue.size)
        val idx = all.indexOfFirst { it > now }
        if (idx < 0) return null
        return all[idx] to all.copyOfRange(idx + 1, all.size)
    }

    /**
     * 取消一条闹钟：AlarmManager 的记录与落盘清单**一起**撤。
     *
     * 凡是绕开这里、只 `am.cancel(...)` 的调用点，都会在清单里留下一条「幽灵闹钟」
     * —— 界面上看不出来，直到某天重启后它自己响了。
     */
    fun cancel(context: Context, id: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val op = Intent(context, AlarmReceiver::class.java)
        val opPi = PendingIntent.getBroadcast(
            context, id, op,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        am.cancel(opPi)
        AlarmStore.remove(context, id)
    }

    /** 下一次 [hour]:[minute]（今天该时刻已过则顺延到明天）。 */
    fun nextDaily(nowMillis: Long, hour: Int, minute: Int): Long {
        val cal = Calendar.getInstance().apply {
            timeInMillis = nowMillis
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (cal.timeInMillis <= nowMillis) cal.add(Calendar.DAY_OF_YEAR, 1)
        return cal.timeInMillis
    }

    /**
     * 下一次匹配 [weekdays]（位掩码 1<<(周一=0)…，即 Dart DateTime.weekday 约定）的
     * [hour]:[minute]；从明天开始向前找 7 天，保证严格晚于 [nowMillis]。
     */
    fun nextWeekly(nowMillis: Long, weekdays: Int, hour: Int, minute: Int): Long {
        val cal = Calendar.getInstance().apply { timeInMillis = nowMillis }
        for (i in 1..7) {
            cal.add(Calendar.DAY_OF_YEAR, 1)
            cal.set(Calendar.HOUR_OF_DAY, hour)
            cal.set(Calendar.MINUTE, minute)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            // Calendar.DAY_OF_WEEK: 1=周日,2=周一…7=周六 → 转成 Dart 的 1=周一…7=周日
            val dartWeekday = ((cal.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
            if ((weekdays and (1 shl (dartWeekday - 1))) != 0) {
                return cal.timeInMillis
            }
        }
        // 兜底（weekdays 为空等异常）：明天同一时间
        return cal.timeInMillis
    }
}
