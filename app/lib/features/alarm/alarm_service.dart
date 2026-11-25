import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n.dart';
import '../../data/app_repository.dart';
import '../../domain/recurring_todo.dart';
import '../../domain/shift_rotation.dart';
import '../../domain/shift_stats.dart';
import '../widget/widget_service.dart';
import '../../core/clock.dart';

/// 没设时间的待办，提醒以当天这个整点为基准（「全天」那类待办没有更准的时点）。
const int allDayReminderHour = 9;

/// 「从文件中选择铃声」失败。[code] 是原生侧给的错误码。
///
/// 要单独成类而不是返回 null：**文件太大**和**读不出来**得在界面上说成两句话，
/// 否则用户只会对着同一个文件反复重试。
class RingtonePickException implements Exception {
  RingtonePickException(this.code);

  final String code;

  bool get isTooLarge => code == 'RINGTONE_TOO_LARGE';

  /// 选择器回来了、但没把文件 URI 交出来（`PICK_NO_URI`）。
  ///
  /// 与「用户取消」是两件事：取消是用户自己的决定，不该提示；这一条是选择器
  /// 的回传方式不标准，必须说一句，否则用户只会觉得「点了没反应」。
  bool get isNoUri => code == 'PICK_NO_URI';
}

/// 正在响铃的闹钟要显示的内容：主标题 +（可选的）说明。
///
/// 说明是给待办的「联动闹钟」准备的：光一个标题说不清「这是什么事、几点钟」，
/// 响铃界面要把待办本身交代清楚（`detail` 就是「9月15日 周二 · 14:30」）。
/// 班次/自定义闹钟不带说明，响铃界面只显示标题，与从前一致。
class AlarmRing {
  const AlarmRing(this.title, [this.detail]);

  final String title;
  final String? detail;

  /// 由原生侧回传的 `{label, detail}` 构造；label 为空返回 null。
  static AlarmRing? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['label'];
    if (label is! String || label.isEmpty) return null;
    final detail = raw['detail'];
    return AlarmRing(label, (detail is String && detail.isNotEmpty) ? detail : null);
  }
}

/// 「某天要排一条班次联动闹钟」的一条决策结果。
///
/// [offset] 是距起点日的天数偏移（`0` = 起点当天）。原生 id 由 `offset` 与
/// [alarmIndex] 一起算出（`序号 × 天数窗口 + 天数偏移`，见 [planShiftAlarms] 与
/// `AlarmService._shiftDaysHorizon`）—— 这个映射必须保持不变，否则每次重排都会把
/// 闹钟换个号，用户设过的响铃记录会跟着错位。
class ShiftAlarmPlan {
  const ShiftAlarmPlan({
    required this.offset,
    required this.shift,
    required this.alarm,
    required this.alarmIndex,
    required this.fireAt,
  });

  final int offset;
  final ShiftClass shift;

  /// 要响的那一条闹钟。
  final ShiftAlarm alarm;

  /// 这个闹钟在 `shift.alarms` 里的下标 —— 原生 id 的「序号」就是它。
  final int alarmIndex;

  final DateTime fireAt;
}

/// 某天某个班次的**某一条**闹钟的响铃时刻。
///
/// 钟点取 [alarm] 的钟面值；落在**哪一天**由 [alarmDayAnchor] 定（前一天 / 班次
/// 当天 / 次日三档）：00:00 上班、23:00 响铃排的是**前一天** 23:00（排在班次当天
/// 就已经是班后 15 小时了）；16:30–次日 00:30 的 00:15 与 01:00 排的是**次日**；
/// 20:00 上班、08:00 响铃排的是**班次当天**（正好下班那一刻）。
///
/// 日期用 `DateTime(y, m, d + delta)` 重建而不是 `add(Duration(days: delta))`：
/// 后者加的是绝对 24 小时，碰上夏令时切换会把钟点也挪掉一小时。
DateTime shiftAlarmFireAt(DateTime date, ShiftClass shift, ShiftAlarm alarm) {
  final delta = switch (alarmDayAnchor(shift, alarm)) {
    AlarmDayAnchor.prev => -1,
    AlarmDayAnchor.same => 0,
    AlarmDayAnchor.next => 1,
  };
  return DateTime(date.year, date.month, date.day + delta)
      .add(Duration(minutes: alarm.minute));
}

/// 决定「从**昨天**起的 [days] 天里，哪些天要排班次联动闹钟、各排在几点」。
///
/// 从 [AlarmService.reschedule] 的排定循环里抽出来的**纯**决策：不碰通知插件、
/// 不读 `DateTime.now()`（当前时刻由 [from] 传入）。抽出来是因为那段逻辑原本
/// 和 `scheduleNativeAlarm` 缠在一起，而项目没有可运行的原生插件目标，于是
/// 三条规格（spec §11：覆盖成休班不排 / 覆盖成别的班按那个班的时间排 /
/// 与「按天关闹钟」正交）**从来没有被任何测试盖到**。
///
/// 跳过条件与从前的循环逐条一致：
/// 那天没有班次 / 是休班 / 班次没开总开关 / 班次一条闹钟都没配 /
/// 那天被「按天关闹钟」显式关过（[overrides] 里值为 `false`）/
/// 算出来的触发时刻不晚于 [from]（今天这个点已经过去了）。
///
/// **一个班次挂了几个闹钟就出几条 plan**，各自算各自的触发时刻与落点。
///
/// 触发时刻由 [shiftAlarmFireAt] 算（可能是**前一天**晚上，也可能是**次日**），
/// 但 `offset` 与原生
/// id 始终按**班次那一天**算 —— id 是 `序号 × 天数窗口 + 天数偏移`，跟着触发时刻走
/// 的话，每个午夜班的闹钟都会换号。**「序号」是闹钟在 `shift.alarms` 里的下标**：
/// 用户在编辑页里调整顺序会让闹钟换号（可接受 —— 编辑之后必然重排、`cancelAll`
/// 先跑），但**重排本身绝不能重新编号**，否则每次打开 App 都换一批。
///
/// 入参是 [ShiftSource] 而不是 `ShiftSchedule`：**「按天衔接」之后，某天归哪套方案
/// 是那条链自己知道的事**，而这里本来就逐天问一次「今天什么班」—— 换一个源进来
/// 即可，函数体一个字不用改（除了这一处 `source.shiftOn`）。原生的 id 算式因此
/// 天生安全：**同一天只归一套方案**，`offset` 相同的两天不可能同时存在。
///
/// 一条容易被误报成 bug 的语义：跨时段边界时，落在**前一天**的那条闹钟会排到
/// 「前一天所属那套方案」的日子里 —— 那是**对的**，闹钟属于那个班次、不属于
/// 触发日。落哪天由 [shiftAlarmFireAt] 里**班次自己的日期**决定，与「那天归哪套」
/// 无关，别把它「修」成按触发日解析。
List<ShiftAlarmPlan> planShiftAlarms(
  ShiftSource source, {
  required DateTime from,
  required int days,
  Map<int, bool> overrides = const {},
  Map<int, int> leaveMinutes = const {},
}) {
  // ⚠️ 从**昨天**起算，不是今天。次日档的闹钟（16:30–次日 00:30 的 00:15、夜班的
  // 上午时段）属于**昨天那个班次**、却在今天响 —— 而 `reschedule` 开头会把
  // `0..600` 全部取消再照这份计划重排，窗口里没有「昨天」就等于**取消之后再也没
  // 排回去**，静默不响（冷启动 / 回前台 / 开机重排都走这条路）。
  //
  // 往前挪一天的代价只是前向窗口少一天（今天 +58 而不是 +59）；`offset` 的含义随之
  // 变成「距昨天几天」，但它只负责让 id 在同一次重排里唯一、且跳过的天照样占号，
  // 绝对值不参与任何判据。**别把这一行改回 `dateOnly(from)`。**
  final anchor = dateOnly(from).subtract(const Duration(days: 1));
  final plans = <ShiftAlarmPlan>[];
  for (var d = 0; d < days; d++) {
    final date = anchor.add(Duration(days: d));
    final t = source.shiftOn(date);
    if (t == null || t.isRest || !t.alarmEnabled || t.alarms.isEmpty) {
      continue;
    }
    // 按天覆盖：该天被单独关闭则跳过
    if (overrides[dayNumber(date)] == false) continue;
    // 整天请假：那天不在岗，班次闹钟不排。部分请假照常排（差一分钟也要上班）。
    // 判据放在这里而不是让界面顺手写一条按天关闹钟 —— 否则「请了假、又在闹钟页
    // 把那天的开关打开」会变成两个开关打架。
    final leave = leaveMinutes[dayNumber(date)] ?? 0;
    final duration = shiftDurationMinutes(t);
    if (leave > 0 && duration != null && leave >= duration) continue;

    for (var i = 0; i < t.alarms.length; i++) {
      final alarm = t.alarms[i];
      final fireAt = shiftAlarmFireAt(date, t, alarm);
      if (!fireAt.isAfter(from)) continue;
      plans.add(ShiftAlarmPlan(
        offset: d,
        shift: t,
        alarm: alarm,
        alarmIndex: i,
        fireAt: fireAt,
      ));
    }
  }
  return plans;
}

/// 一份日志文件的元信息（按天分段的展示用）。
class LogFileInfo {
  const LogFileInfo(
      {required this.name, required this.day, required this.size});

  /// 原生侧的文件名：`app_log.txt`（当前）或 `app_log-2026-11-23.txt`（归档）。
  final String name;

  /// 这一份覆盖的日期（`yyyy-MM-dd`）。
  final String day;

  final int size;
}

/// 「下一次响铃」是哪一条（闹钟页顶部摘要用）。
class NextAlarmInfo {  const NextAlarmInfo({required this.fireAt, required this.label});

  final DateTime fireAt;

  /// 响铃标题，与真正响起来时那条完全一致（`shiftAlarmTitle` / 「自定义闹钟」）。
  final String label;
}

/// 班次联动闹钟与自定义闹钟里，**最近**的那一条。
///
/// **不许另写一份「下次是哪条」的算法**：这里直接复用 [planShiftAlarms] 与
/// `_customAlarmRequests` —— 也就是 `reschedule` 真正排定时走的那两条路。另起
/// 一份必然分岔，症状是摘要说 15:00、系统里排的却是别的时间：不报错，比不显示
/// 更糟。
///
/// [overrides] 是**按天关闹钟**（`shift_alarm_overrides`）：用户在闹钟页把某天的
/// 开关关掉时，那条就真的不会响，摘要也得跳过它 —— 不传的话摘要在关了之后还
/// 停在原处（2026-11-25 用户实测报的）。
///
/// 取 31 天而不是一两天：连休、空白表、只在上班日才有闹钟的排法，下一条完全
/// 可能在好几天以后。
NextAlarmInfo? nextAlarmInfo(
  ShiftSource source,
  List<CustomAlarm> alarms, {
  required DateTime now,
  Map<int, bool> overrides = const <int, bool>{},
}) {
  NextAlarmInfo? best;
  void consider(DateTime fireAt, String label) {
    if (!fireAt.isAfter(now)) return;
    if (best == null || fireAt.isBefore(best!.fireAt)) {
      best = NextAlarmInfo(fireAt: fireAt, label: label);
    }
  }

  for (final p in planShiftAlarms(source,
      from: now, days: 31, overrides: overrides)) {
    consider(p.fireAt, L10n.shiftAlarmTitle(p.shift.name, p.alarm.label));
  }
  for (final a in AlarmService._customAlarmRequests(alarms, now: now)) {
    consider(a.fireAt, L10n.customAlarmTitle);
  }
  return best;
}

/// 一条重复待办提醒的排定计划。
///
/// 队首（[fireAt]）现在排给原生；[repeatTimes] 是它后面还跟着的几次 —— 一起递
/// 过去，由原生在响完之后**弹队首、续队尾**，所以 App 长期不开也不漏。
class RecurringAlarmPlan {
  const RecurringAlarmPlan({
    required this.seriesId,
    required this.fireAt,
    required this.repeatTimes,
  });

  final int seriesId;
  final DateTime fireAt;

  /// [fireAt] 之后的下几次触发时刻（升序，不含 [fireAt]）。
  final List<DateTime> repeatTimes;
}

/// 纯函数：把系列列表算成要排的提醒。**不碰通知通道、不读时钟**。
///
/// 抽出来是为了能直接单测 —— 它错了不会报错，只会**在错的时候提醒**或者
/// **根本不提醒**，两样都靠界面看不出来（与 [planShiftAlarms] 同一条理由）。
///
/// 关键的一条：时刻从 [from] **之后**算起（`upcomingFireTimes` 的语义），不是从
/// 「当前那一次的日期」算起 —— 下午打开 App 时今天那次早过去了，照那一次排等于
/// 永远排不上。
///
/// 规则**不递给原生**：那一串绝对时刻就是全部，原生只做「弹队首、续队尾」。
/// 把月份 / 星期掩码 / 提前提醒的偏移照抄一份到 Kotlin 会变成第二份实现，而原生
/// 在这个仓库里没有可跑的测试目标 —— 两份迟早对不上，症状还是「某天没响」。
List<RecurringAlarmPlan> planRecurringReminders(
  List<RecurringTodo> series, {
  required DateTime from,
  int days = 180,
  int cap = 200,
  ShiftClass? Function(DateTime day)? shiftOn,
}) {
  final out = <RecurringAlarmPlan>[];
  for (final s in series) {
    final id = s.id;
    // 提醒的号是 `_recurringBaseId + 系列 id`，没有 id 就没有稳定的号可排。
    if (id == null) continue;
    final times = upcomingFireTimes(
      s,
      from: from,
      // 「没设时间按几点提醒」是提醒层的策略，领域层不知道也不该知道。
      clockMinute: s.timeMinute ?? allDayReminderHour * 60,
      days: days,
      cap: cap,
      shiftOn: shiftOn,
    );
    if (times.isEmpty) continue;
    out.add(RecurringAlarmPlan(
      seriesId: id,
      fireAt: times.first,
      repeatTimes: times.skip(1).toList(),
    ));
  }
  return out;
}

// ---------------------------------------------------------------------------
// 原生排定的「请求」：一次重排算成一整批交给原生
// ---------------------------------------------------------------------------
//
// 为什么从「逐条跨端 + 每条一次全量落盘」改成「一批一次」：
//
// 2026-11-22 一位三星用户报「早上 6 点的没响」，日志里 4:00 那条全链路正常、
// 6:00 **连 `AlarmReceiver.onReceive` 都没有** —— 那一刻系统里没有这条闹钟。
//
// 旧的重排是「先按固定区间盲扫全撤 + 清空落盘清单，再一条条排回来」，中间还夹着
// 待办那段几千次 `PendingIntent` 操作，整段窗口有**几秒**。而**每次闹钟响都会
// 冷启动 App → 每次都整链重排**：用户关掉 4:00 那个闹钟之后随手把 App 划掉
// （或厂商清理），进程死在这个窗口里，就停在「已清空、还没排完」，此后所有闹钟
// 全哑，直到下次打开 App（`BootReceiver` 只在开机时跑）。
//
// 现在改成：先拿「落盘清单里已有」与「新计划」算差集 → **先排新的、再撤多余的**，
// 任何瞬间都不存在「一条闹钟都没有」的状态；一批只跨一次端、只落一次盘。
// 差集是纯函数（[staleNativeIds]），顺序也有用例钉着。

/// 一条要交给原生排定的**响铃闹钟**。
///
/// [repeatTimes] 非空时一律按「时刻表驱动」（`repeatType == 3`）递过去 —— 弹队首、
/// 续队尾，规则只在 Dart 侧算（与 `Reschedule` 里的老约定一致）。
class NativeAlarm {
  const NativeAlarm({
    required this.id,
    required this.fireAt,
    required this.label,
    this.detail,
    this.repeatType = 0,
    this.hour = 0,
    this.minute = 0,
    this.weekdays = 0,
    this.repeatTimes = const [],
  });

  final int id;
  final DateTime fireAt;
  final String label;
  final String? detail;
  final int repeatType;
  final int hour;
  final int minute;
  final int weekdays;
  final List<DateTime> repeatTimes;

  Map<String, Object?> toMap() => {
        'id': id,
        'millis': fireAt.millisecondsSinceEpoch,
        'label': label,
        'detail': detail,
        'repeatType': repeatTimes.isEmpty ? repeatType : 3,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays,
        'repeatTimes': [for (final t in repeatTimes) t.millisecondsSinceEpoch],
      };

  @override
  String toString() => 'NativeAlarm($id, $fireAt, $label)';
}

/// 一条要交给原生排定的**安静提醒**（待办提醒那条链路，只弹通知）。
class NativeQuiet {
  const NativeQuiet({
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
    this.repeatTimes = const [],
  });

  final int id;
  final DateTime fireAt;
  final String title;
  final String body;
  final List<DateTime> repeatTimes;

  Map<String, Object?> toMap() => {
        'id': id,
        'millis': fireAt.millisecondsSinceEpoch,
        'title': title,
        'body': body,
        'repeatTimes': [for (final t in repeatTimes) t.millisecondsSinceEpoch],
      };

  @override
  String toString() => 'NativeQuiet($id, $fireAt, $title)';
}

/// 本 App 拥有的原生 id 号段，闭开区间 `[from, to)`。
///
/// **这就是从前 Kotlin 侧三段盲扫（`0..600` / `10000..11000` / `99990..100000`）
/// 与待办那段盲扫的等价物**，只是现在由 Dart 传给原生、按号段筛选差集，
/// 不再每次开机扫几千次 `PendingIntent`。改号段要同时看 `AlarmService` 的几个
/// `*BaseId` 常量与 `AlarmScheduler` 的注释。
const List<(int, int)> nativeFullRanges = [
  (0, 600), // 班次闹钟：序号 × 60 + 天数偏移
  (10000, 11000), // 自定义闹钟
  (20000, 42000), // 待办行 20000.. 与重复待办系列 40000..
  (99990, 100000), // 贪睡 99998 / 测试 99999
];

/// 只重排待办时拥有的号段（[AlarmService.rescheduleTodoReminders]）。
///
/// 前端「按班次」的闹钟与自定义闹钟都在号段之外，所以改待办**碰不到**它们 ——
/// 这是「勾一条待办不该把几百条班次闹钟全撤重排」那条规矩的结构化版本。
const List<(int, int)> nativeTodoRanges = [(20000, 42000)];

/// 「落盘清单里已有、但新计划里没有」的 id —— **只撤号段内的**。
///
/// 这是「先排后清」的那一半：撤的只能是**确认不再需要**的，新计划里的 id 无论
/// 怎样都不会出现在返回值里（用例钉着）。
///
/// 号段筛选不是为了性能，是为了**隔离**：`rescheduleTodoReminders` 只拿得到待办
/// 那一批请求，没有号段它会把班次闹钟一起撤掉。
List<int> staleNativeIds({
  required Iterable<int> armed,
  required Iterable<int> desired,
  required List<(int, int)> ranges,
}) {
  final keep = desired.toSet();
  final out = <int>[];
  for (final id in armed.toSet()) {
    if (keep.contains(id)) continue;
    if (!ranges.any((r) => id >= r.$1 && id < r.$2)) continue;
    out.add(id);
  }
  out.sort();
  return out;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 一批请求里**最近**那一跳的日志写法：`11-23 06:30 id=125`（没有则为 `无`）。
///
/// 响铃闹钟与安静提醒一起比：用户贴日志时最想知道的是「App 认为下一条是什么」，
/// 与它走哪条链路无关。
String nativeNextDigest({
  required List<NativeAlarm> alarms,
  required List<NativeQuiet> quiets,
}) {
  DateTime? at;
  int? id;
  void consider(DateTime t, int i) {
    if (at == null || t.isBefore(at!)) {
      at = t;
      id = i;
    }
  }

  for (final a in alarms) {
    consider(a.fireAt, a.id);
  }
  for (final q in quiets) {
    consider(q.fireAt, q.id);
  }
  final t = at;
  if (t == null) return '无';
  return '${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)} id=$id';
}

/// 某天这个班次**还有没有没响过的**闹钟 —— 闹钟页「未来 30 天」那一行留不留。
///
/// **不能只看第一条**（那是只有一个闹钟时的口径）：首条已响、后面还有时
/// （早餐闹钟 06:30 响过了、午休 12:30 还等着），整行会被「响过的自动隐藏」
/// 一起藏掉 —— 那一行的「按天关闹钟」开关也跟着没了，用户当天再也没法关掉
/// 剩下的那一条。（独立审查抓出来的；`shift_alarm_decision_test.dart` 里
/// 「首条已响、后面还有」与「零点班：起床在前一晚已响」两条是它的护栏。）
bool hasPendingShiftAlarm(ShiftClass shift, DateTime date, DateTime now) =>
    shift.alarms.any((a) => shiftAlarmFireAt(date, shift, a).isAfter(now));

/// 一次性自定义闹钟该落在哪天：`hour:minute` 的**下一次出现**。
///
/// **为什么不能就是「今天」**：新建闹钟时时间默认此刻、日期默认今天，两个默认叠在
/// 一起，触发时刻在按下「添加」之前就已经过去了。而一次性闹钟的排定判据是
/// `fire.isAfter(now)`（见 `reschedule`）—— 过去的那一刻直接**不排**，
/// `deleteExpiredOnceAlarms` 还会在下一次进闹钟页时把它删掉。用户看到的是「加了一
/// 条、它自己没了」。`repeatType` 的默认值从「每天」改成「一次性」之后（v0.9.6），
/// 这不是边角情况而是常态，所以日期一律由这里算。
///
/// 规则：今天这个钟点还没到就是今天，已经过了就顺延一天；[chosen] 是更晚的日期时
/// 听用户的（手选了日子的人比默认值清楚）。界面那行「日期」显示的就是它的结果，
/// 所以卡上写的永远等于真正会响的那天。
///
/// 返回的是**日期**（`dateOnly`，与库里 `onceDate` 那一列同形），不是带钟点的时刻：
/// 钟点单独存在 `hour`/`minute` 两列，排定时由 `reschedule` 现拼
/// （`DateTime(od.year, od.month, od.day, a.hour, a.minute)`）。
///
/// `alarm_screen_test.dart` 里「新建后直接添加」那条用例盯住落点，
/// `once_alarm_date_test.dart` 在纯函数上把边界逐条钉死。
DateTime nextOnceDate({
  required DateTime now,
  required DateTime chosen,
  required int hour,
  required int minute,
}) {
  final chosenAt = DateTime(chosen.year, chosen.month, chosen.day, hour, minute);
  final today = DateTime(now.year, now.month, now.day, hour, minute);
  // `day + 1` 交给 `DateTime` 归一化（月末、年末都跨得过去），不要自己加 24 小时
  // —— `Duration` 遇上夏令时会偏一小时。
  final occurrence = today.isAfter(now)
      ? today
      : DateTime(now.year, now.month, now.day + 1, hour, minute);
  return dateOnly(chosenAt.isAfter(occurrence) ? chosenAt : occurrence);
}

/// 联动班次闹钟 + 自定义闹钟服务。
///
/// 排班闹钟排定未来 `_shiftDaysHorizon` 天（60）；每次打开 App 自动续排，
/// 跟着排班走、不过期。自定义闹钟支持：一次性 / 每天 / 每周（可选星期几）。
class AlarmService {
  AlarmService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _shiftBaseId = 0;

  /// 班次闹钟排定的天数窗口（`reschedule` 的 [days] 缺省值）。
  ///
  /// **它就是原生 id 里的那个 60**：id = `序号 × 本值 + 天数偏移`。所以它与
  /// `maxAlarmsPerShift`（10，见 `domain/shift_rotation.dart`）是一对：
  /// 10 × 60 = 600 ≤ 600，而 Kotlin 侧 `cancelAllNativeAlarms` / `cancelAllNotificationAlarms`
  /// 扫的是 0..600（`MainActivity.kt:604` 与 `:620`）。
  /// **改这个值必须同时改那个上限与 Kotlin 的扫描范围。**
  static const int _shiftDaysHorizon = 60;

  /// 测试用只读出口：id 算式是「上限 10」的由来，得能在纯测试里断言。
  static int get shiftDaysHorizonForTesting => _shiftDaysHorizon;

  /// 班次闹钟的原生 id —— **唯一算式出处**：`reschedule` 排定与诊断包导出都走它。
  ///
  /// 改算式要同时看 `maxAlarmsPerShift` 与 Kotlin 侧 `cancelAllNativeAlarms` 的
  /// 扫描上界（`docs/decisions/alarm.md` 那条「三个一起改」）。
  static int shiftAlarmNativeIdOf(ShiftAlarmPlan p) =>
      _shiftBaseId + p.alarmIndex * _shiftDaysHorizon + p.offset;

  static const _customBaseId = 10000;

  /// 待办提醒的原生 id 基址。
  ///
  /// **四段互不重叠**，原生侧按区间扫着取消（见 `MainActivity` 的几个 cancel 分支）：
  /// 班次 `0..600`、自定义闹钟 `10000..11000`、待办行 `20000..`（留到 39999）、
  /// 重复待办系列 `40000..41999`。
  ///
  /// 为什么把重复待办单列一段：它的号按**系列 id** 算，而待办行的号按**行 id** 算，
  /// 而行 id 只增不减（`AUTOINCREMENT` 永不复用）—— 两者共用一个自增序列的话，
  /// 行号迟早会把提醒的号挤出去，越界之后提醒排得下去、谁也取消不掉。
  static const _eventBaseId = 20000;

  /// 重复待办提醒的原生 id 基址（id = `40000 + 系列 id`）。
  static const _recurringBaseId = 40000;

  static Future<void> init() async {
    // ⚠️ **不要再把 `tz.initializeTimeZones()` 加回来**（2026-10-10 删）。
    //
    // 它从前是为了「以后可能要用 `flutter_local_notifications` 的时区型 API」而留着
    // 的，但全仓从来没有一处 `zonedSchedule` / `TZDateTime` —— 排定全部走原生
    // （epoch 毫秒）或 `scheduleNativeAlarm`。代价却是实打实的：`latest_all` 是全量
    // IANA 库，实测 **21ms**（宿主；真机更慢），而且它跑在 `main()` 里、**首帧之前**。
    //
    // 将来真要上时区型 API，除了把这一句加回来，还必须补 `tz.setLocalLocation`
    // —— 否则 `tz.local` 是 UTC，会整体差一个时区偏移（见 `scheduleTodoReminder` 的说明）。
    // 原生闹钟触发时（App 已在后台），MainActivity 通过此回调通知我们弹出响铃界面；
    // 待办提醒被点开时同样由它通知我们切到「待办」页。
    _settingsChannel.setMethodCallHandler(handleNativeCall);

    // 通知通道的名字要在系统「通知」设置里显示，得跟着界面语言走；而通道只能
    // 在原生侧建。启动时把当前语言的名字递过去（同名重复创建 = 更新，不是报错）。
    await ensureTodoChannel(L10n.todoReminderChannel);
    // 通知小图标必须是 drawable：插件用 getIdentifier(name, "drawable", pkg) 查它，
    // 而且是按**白剪影**渲染的 —— 塞一个满幅彩色的启动器图标进去只会得到一坨白块。
    // 原生 AlarmRingService 早就在用 drawable/ic_notification，这里与它对齐。
    const android = AndroidInitializationSettings('ic_notification');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
    // 注意：这里不能清缓存——清了之后 cancelAll 就找不到已排定的 AlarmManager 闹钟，
    // 导致每次启动都累积新闹钟、最终撞上「500 条并发闹钟」上限。
    // 若缓存损坏，reschedule 里 cancelAll 的 try-catch 会兜底清一次。

    // 冷启动：检查是否由闹钟通知（全屏通知）拉起
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        final payload = launch?.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          // 插件这条路径的载荷就是标签（没有说明），与原生那两条一致地包一层。
          ringingAlarm.value = AlarmRing(payload);
        }
      }
    } catch (_) {}

    // 冷启动：检查是否由原生闹钟（AlarmReceiver）拉起
    final nativeAlarm = await getPendingAlarm();
    if (nativeAlarm != null) {
      await logInfo('Dart init: 冷启动读取 pendingAlarm=${nativeAlarm.title}');
      ringingAlarm.value = nativeAlarm;
    }

    // 冷启动：检查是否由待办提醒的通知拉起
    final todoId = await getPendingTodoId();
    if (todoId != null) {
      await logInfo('Dart init: 冷启动读取 pendingTodoId=$todoId');
      openTodoRequested.value = true;
    }
  }

  /// 处理原生推过来的方法调用 —— 「原生说了什么、Dart 要做什么」的全套契约。
  ///
  /// **抽成静态方法是为了能单测**：`init()` 里那一堆插件初始化在 widget 测试里跑不起来，
  /// 而这里面每一条都是会静默出错的东西（漏一条就是「原生做了、界面没跟上」）。
  @visibleForTesting
  static Future<void> handleNativeCall(MethodCall call) async {
    if (call.method == 'onAlarmFired') {
      // 原生侧回传的是 {label, detail} 两张牌（见 MainActivity.handleAlarmIntent）
      final ring = AlarmRing.fromMap(call.arguments);
      await logInfo('Dart 收到 onAlarmFired: ${ring?.title}');
      if (ring != null) {
        ringingAlarm.value = ring;
      }
    } else if (call.method == 'onTodoTapped') {
      await logInfo('Dart 收到 onTodoTapped');
      openTodoRequested.value = true;
    } else if (call.method == 'onAlarmAutoStopped') {
      // **响铃 15 分钟超时自停**。原生那条路与用户手动关闭**完全相同**
      // （`MainActivity.onAlarmAutoStopped` → `exitLockScreenMode()` +
      // `stopForeground(REMOVE)` + `stopSelf()`），走到最后发这一发。
      //
      // 这里只清这个值：`HomeShell` 看到它从「有」变成「没有」就把响铃那层路由收掉
      // （用户手动关闭那条路由它自己 `popUntil`，两条路在这里合流）。
      await logInfo('Dart 收到 onAlarmAutoStopped');
      ringingAlarm.value = null;
    }
    // 小组件某一天被点击（热启动路径）。它不参与上面那条 if/else ——
    // 单独一个 `if` 是有意的，别顺手并进去。
    if (call.method == 'onWidgetDayTapped') {
      WidgetService.onNativeDayTapped(call.arguments as int);
    }
  }

  static void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      ringingAlarm.value = AlarmRing(payload);
    }
  }

  /// 请求通知 + 精确闹钟 + 全屏通知权限（须在 runApp 后调用，否则 Activity 未就绪会静默失败）。
  static Future<void> requestPermissions() async {
    await requestNotificationsPermission();
    await requestExactAlarmsPermission();
    await requestFullScreenIntentPermission();
  }

  static Future<void> requestNotificationsPermission() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
  }

  static Future<void> requestExactAlarmsPermission() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestExactAlarmsPermission();
  }

  static Future<void> requestFullScreenIntentPermission() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestFullScreenIntentPermission();
  }

  /// 返回 (通知权限, 精确闹钟权限) 是否开启。
  static Future<(bool, bool)> checkPermissions() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    bool notif = false, exact = false;
    try {
      notif = await androidImpl?.areNotificationsEnabled() ?? false;
    } catch (_) {}
    try {
      exact = await androidImpl?.canScheduleExactNotifications() ?? false;
    } catch (_) {}
    return (notif, exact);
  }

  static const _settingsChannel = MethodChannel(
      'com.daoban.shiftassistantpro/settings');

  /// 打开本应用的系统设置详情页（国产 ROM 上通常含「自启动」开关）。
  static Future<void> openAppSettings() async {
    try {
      await _settingsChannel.invokeMethod('openAppSettings');
    } catch (_) {}
  }

  /// 打开「显示悬浮窗」权限设置（弹响铃界面的 AOSP 层豁免靠它）。
  static Future<void> openOverlaySettings() async {
    try {
      await _settingsChannel.invokeMethod('openOverlaySettings');
    } catch (_) {}
  }

  /// 本应用是否已获得「显示悬浮窗」权限（`SYSTEM_ALERT_WINDOW`）。
  static Future<bool> checkOverlayPermission() async {
    try {
      return await _settingsChannel.invokeMethod('checkOverlayPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 这台机器上有没有小米的 App 权限页（非小米机型没有）。
  ///
  /// 那里装着一项**小米私有**的权限「后台弹出界面」，与上面的「显示悬浮窗」是
  /// 两回事：不开它，MIUI 会静默拒绝从后台拉起 Activity，闹钟只响、不弹界面。
  /// 这项权限读不到状态（没有公开 API），所以界面上只做「去查看」。
  static Future<bool> checkMiuiPermissionPage() async {
    try {
      return await _settingsChannel.invokeMethod('checkMiuiPermissionPage') ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// 打开小米的 App 权限页；打不开返回 false，由调用方落回系统「应用信息」。
  static Future<bool> openMiuiPermissionPage() async {
    try {
      return await _settingsChannel.invokeMethod('openMiuiPermissionPage') ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// 这台机器上有没有三星「后台使用限制」那一页（非三星机型解析不到）。
  ///
  /// 与小米那两项同一条理由：它是厂商私有的页面，没有公开 API。区别是它管的是
  /// 「睡眠应用 / 深度休眠应用」—— **进了名单的 App，系统会把它已排好的闹钟一起
  /// 取消**，症状正是「几天偶尔漏响一次」（2026-11-17 三星 One UI 8.5 用户反馈）。
  static Future<bool> checkSamsungBatteryPage() async {
    try {
      return await _settingsChannel.invokeMethod('checkSamsungBatteryPage') ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// 打开三星「设备维护 → 电池」页；打不开返回 false，由调用方落回「应用信息」。
  static Future<bool> openSamsungBatteryPage() async {
    try {
      return await _settingsChannel.invokeMethod('openSamsungBatteryPage') ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// 本应用是否已被忽略电池优化（后台闹钟可靠运行的关键）。
  static Future<bool> checkBatteryOptimization() async {
    try {
      return await _settingsChannel.invokeMethod('checkBatteryOptimization') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 本应用是否已获得「全屏通知」权限（Android 14+ 全屏闹钟需要）。
  static Future<bool> checkFullScreenIntentPermission() async {
    try {
      return await _settingsChannel
              .invokeMethod('checkFullScreenIntentPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 打开「全屏通知」权限设置。
  static Future<void> openFullScreenIntentSettings() async {
    try {
      await _settingsChannel.invokeMethod('openFullScreenIntentSettings');
    } catch (_) {}
  }

  /// 排一个原生闹钟（setAlarmClock → AlarmReceiver → 前台服务响铃 + 全屏）。
  /// [repeatType]：0=一次性，1=每天，2=每周（触发后由原生侧自动续排下一次）。
  ///
  /// [detail] 是响铃界面上标题下面那行说明（待办的联动闹钟用它交代「什么事、
  /// 几点」）；班次/自定义闹钟不传，响铃界面就只显示标题。
  static Future<void> scheduleNativeAlarm(
    int id,
    DateTime fireAt,
    String label, {
    String? detail,
    int repeatType = 0,
    int hour = 0,
    int minute = 0,
    int weekdays = 0,
    List<DateTime> repeatTimes = const [],
  }) async {
    try {
      await _settingsChannel.invokeMethod('scheduleNativeAlarm', {
        'id': id,
        'millis': fireAt.millisecondsSinceEpoch,
        'label': label,
        'detail': detail,
        // **队列优先**：带时刻表时一律发 3（「时刻表驱动」），原生据此走
        // 「弹队首、续队尾」，而不是自定义闹钟的 nextDaily / nextWeekly 重算 ——
        // 重复待办的那些边角（月末、多选星期几、夏令时）只在 Dart 侧算得对。
        'repeatType': repeatTimes.isEmpty ? repeatType : 3,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays,
        'repeatTimes': [
          for (final t in repeatTimes) t.millisecondsSinceEpoch,
        ],
      });
      // ⚠️ **这里不许再跟一条 `logInfo`**：那等于每排一条闹钟就多跨一次端
      // （实测一次 `rescheduleAll` 46 条班次闹钟 + 2 条汇总，跨端 99 次里有 46 次
      // 是它）。要留痕就在 `reschedule` 收尾打一条汇总 —— 由
      // `alarm_reschedule_budget_test.dart` 钉住。
    } catch (e) {
      await appendLog('scheduleNativeAlarm 失败: $e');
    }
  }

  /// 取消全部原生闹钟。
  ///
  /// [keepStore]：**升级后的一次性清扫**用 —— 只撤系统里的，不动落盘清单。
  /// 清单留着，清扫与随后那次整批重排之间进程若被杀，开机重排还能把旧的一批排回去。
  static Future<void> cancelAllNativeAlarms({bool keepStore = false}) async {
    try {
      await _settingsChannel.invokeMethod(
          'cancelAllNativeAlarms', {'keepStore': keepStore});
    } catch (_) {}
  }

  /// 按 id 取消全部通知闹钟（清理历史累积，避免撞上「500 条并发闹钟」上限）。
  static Future<void> cancelAllNotificationAlarms() async {
    try {
      await _settingsChannel.invokeMethod('cancelAllNotificationAlarms');
    } catch (_) {}
  }

  /// 读取由原生闹钟拉起时携带的标题与说明（一次性）。
  static Future<AlarmRing?> getPendingAlarm() async {
    try {
      final raw = await _settingsChannel.invokeMethod('getPendingAlarm');
      return AlarmRing.fromMap(raw);
    } catch (_) {
      return null;
    }
  }

  /// 查询设备物理内存（字节），用于低端机玻璃模糊降级；失败返回 -1。
  static Future<int> getTotalRamBytes() async {
    try {
      final v = await _settingsChannel.invokeMethod<int>('getTotalRamBytes');
      return v ?? -1;
    } catch (_) {
      return -1;
    }
  }

  /// 申请忽略电池优化（白名单），提高后台闹钟可靠性。
  static Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _settingsChannel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  /// 清空 flutter_local_notifications 的「已排定通知」缓存。
  ///
  /// 该缓存是插件用 Gson 序列化到 SharedPreferences 的；一旦旧版本写入的数据
  /// 与当前反序列化逻辑不兼容，`cancel`/`cancelAll` 会抛
  /// `Missing type parameter`，导致所有重排都在第一步崩掉、闹钟永远排不进去。
  static Future<void> clearNotificationCache() async {
    try {
      await _settingsChannel.invokeMethod('clearNotificationCache');
    } catch (_) {}
  }

  /// 追加一条错误/崩溃日志到原生日志文件（可在「我的 → 查看日志」里查看）。
  static Future<void> appendLog(String msg) async {
    try {
      await _settingsChannel.invokeMethod('appendLog', {'msg': msg});
    } catch (_) {}
  }

  /// 追加一条普通信息日志（仅写入 Android Logcat，不落盘、应用内不可见）。
  static Future<void> logInfo(String msg) async {
    try {
      await _settingsChannel.invokeMethod('logInfo', {'msg': msg});
    } catch (_) {}
  }

  /// 读取原生日志文件内容。
  static Future<String> readLog() async {
    try {
      return await _settingsChannel.invokeMethod('readLog') ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 清空原生日志文件（当前文件 + 全部按天归档）。
  static Future<void> clearLog() async {
    try {
      await _settingsChannel.invokeMethod('clearLog');
    } catch (_) {}
  }

  /// 日志文件清单（新的在前）。`day` 是那一份覆盖的日期，界面按它做选择条。
  static Future<List<LogFileInfo>> listLogFiles() async {
    try {
      final raw = await _settingsChannel.invokeMethod<List>('listLogFiles');
      if (raw == null) return const <LogFileInfo>[];
      return <LogFileInfo>[
        for (final e in raw)
          if (e is Map)
            LogFileInfo(
              name: e['name'] as String? ?? '',
              day: e['day'] as String? ?? '',
              size: (e['size'] as num?)?.toInt() ?? 0,
            ),
      ];
    } catch (_) {
      return const <LogFileInfo>[];
    }
  }

  /// 读某一份日志（当前文件或某个归档）。
  static Future<String> readLogFile(String name) async {
    try {
      return
          await _settingsChannel.invokeMethod('readLogFile', {'name': name}) ??
              '';
    } catch (_) {
      return '';
    }
  }

  /// 设备与权限快照（诊断包用；键名稳定，不随文案改）。
  static Future<Map<String, dynamic>> deviceReport() async {
    try {
      final raw = await _settingsChannel.invokeMethod<Map>('deviceReport');
      return raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(raw);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// 原生落盘清单：App 认为系统里应该躺着哪些闹钟。
  ///
  /// **这一份是「没响」类报障的分水岭**：清单里有、日志里没有 `onReceive` =
  /// 系统没递过来；清单里根本没有 = App 本来就没排它。
  static Future<List<Map<String, dynamic>>> nativeAlarmStore() async {
    try {
      final raw = await _settingsChannel.invokeMethod<List>('nativeAlarmStore');
      if (raw == null) return const <Map<String, dynamic>>[];
      return <Map<String, dynamic>>[
        for (final e in raw)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  /// 诊断包里的「App 认为接下来会响什么」（未来 7 天）。
  ///
  /// 与 [reschedule] 走**同一批纯函数**（[planShiftAlarms] / `_customAlarmRequests`
  /// / `_eventRequests` / `_recurringRequests`）—— 这份计划要是另写一份，排查时
  /// 「导出包说的」和「真排的」就会分岔，那这份包反而误导人。
  static Future<Map<String, dynamic>> diagnosticPlan(
      AppRepository repo) async {
    final schedules = await repo.getActiveSchedules();
    final chain = schedules?.chain;
    final now = appNow();
    final customAlarms = await repo.listCustomAlarms();
    final events = await repo.listEvents();
    final series = await repo.listRecurringTodos();
    final overrides = await repo.listShiftAlarmOverrides();
    final leave = <int, int>{
      for (final e in (await repo.listDayExtras()).entries)
        if (e.value.leaveMinutes > 0) e.key: e.value.leaveMinutes,
    };
    final event = _eventRequests(events, now: now);
    final recurring = _recurringRequests(
        series, planRecurringReminders(series, from: now, shiftOn: chain?.shiftOn));
    return <String, dynamic>{
      'now': now.toIso8601String(),
      'schedule': schedules?.current?.schedule.name,
      'shift': chain == null
          ? const <Map<String, dynamic>>[]
          : <Map<String, dynamic>>[
              for (final p in planShiftAlarms(chain,
                  from: now, days: 7, overrides: overrides, leaveMinutes: leave))
                <String, dynamic>{
                  'id': shiftAlarmNativeIdOf(p),
                  'at': p.fireAt.toIso8601String(),
                  'shift': p.shift.name,
                  'label': p.alarm.label,
                  'alarmIndex': p.alarmIndex,
                  'offset': p.offset,
                },
            ],
      'custom': <Map<String, dynamic>>[
        for (final a in _customAlarmRequests(customAlarms, now: now))
          <String, dynamic>{
            'id': a.id,
            'at': a.fireAt.toIso8601String(),
            'label': a.label,
            'repeatType': a.repeatType,
          },
      ],
      'todos': <Map<String, dynamic>>[
        for (final a in event.alarms)
          <String, dynamic>{'id': a.id, 'at': a.fireAt.toIso8601String(), 'label': a.label},
      ],
      'todoQuiets': <Map<String, dynamic>>[
        for (final q in event.quiets)
          <String, dynamic>{'id': q.id, 'at': q.fireAt.toIso8601String(), 'title': q.title},
      ],
      'recurring': <Map<String, dynamic>>[
        for (final a in recurring.alarms)
          <String, dynamic>{
            'id': a.id,
            'at': a.fireAt.toIso8601String(),
            'label': a.label,
            'repeatTimes': [for (final t in a.repeatTimes) t.toIso8601String()],
          },
      ],
    };
  }

  /// 用系统浏览器 / 对应 App 打开 [url]（「关于」页的外链、打赏的支付宝唤起都走它）。
  ///
  /// 返回是否成功唤起：原生侧 `startActivity` 在没有匹配应用时会抛
  /// `OPEN_URL_FAILED`，这里吞掉异常但把成败回给调用方 —— 打赏页要靠它决定
  /// 是否回落到二维码，不能让「点了没反应」变成静默失败。
  static Future<bool> openUrl(String url) async {
    try {
      await _settingsChannel.invokeMethod('openUrl', {'url': url});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 用系统安装器打开本地 [path] 指向的 APK（走 FileProvider，见 MainActivity.kt）。
  static Future<void> installApk(String path) async {
    try {
      await _settingsChannel.invokeMethod('installApk', {'path': path});
    } catch (_) {}
  }

  /// 立即排一个 10 秒后的测试闹钟，用于排查整条闹钟链路是否通。
  static Future<void> testAlarm() async {
    const testId = 99999;
    await logInfo('testAlarm: 开始排定测试闹钟');
    final vol = await getVolumeLevels();
    await logInfo('testAlarm: 音量 alarm=${vol['alarm']}/${vol['alarmMax']}, '
        'notification=${vol['notification']}/${vol['notificationMax']}, '
        'music=${vol['music']}/${vol['musicMax']}');
    try {
      await _plugin.cancel(testId);
    } catch (e) {
      await appendLog('testAlarm: cancel 异常: $e');
    }
    final fire = appNow().add(const Duration(seconds: 10));
    await scheduleNativeAlarm(testId, fire, '测试闹钟');
    await logInfo('testAlarm: 排定成功，约 ${fire.toIso8601String()} 触发');
  }

  /// 当前已排定的通知数量（排查用，失败返回 -1）。
  static Future<int> pendingNotificationCount() async {
    try {
      final list = await _plugin.pendingNotificationRequests();
      return list.length;
    } catch (_) {
      return -1;
    }
  }

  /// 列出系统里可用的铃声（标题 + URI）。
  static Future<List<({String title, String uri})>> listRingtones() async {
    try {
      final raw = await _settingsChannel.invokeMethod('listRingtones') as List?;
      return (raw ?? [])
          .map((e) => (
                title: (e as Map)['title'] as String? ?? '铃声',
                uri: e['uri'] as String? ?? '',
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 读取当前音量（alarm / notification / music），用于排查无声问题。
  static Future<Map<String, int>> getVolumeLevels() async {
    try {
      final raw = await _settingsChannel.invokeMethod('getVolumeLevels') as Map?;
      return (raw ?? const {}).map((k, v) => MapEntry(k.toString(), v as int));
    } catch (_) {
      return const {};
    }
  }

  /// 试听铃声：[uri] 为空则播放内置铃声。
  static Future<void> playRingtone(String? uri) async {
    try {
      await _settingsChannel.invokeMethod('playRingtone', {'uri': uri ?? ''});
    } catch (_) {}
  }

  /// 停止试听。
  static Future<void> stopRingtone() async {
    try {
      await _settingsChannel.invokeMethod('stopRingtone');
    } catch (_) {}
  }

  /// 「仅震动」——响铃时**不发声**，只有震动。
  ///
  /// 它和铃声 URI 存在**同一个** SharedPreferences 键（`ringtoneUri`）里，因为整条
  /// 链路本来就是一路的字符串：prefs → `AlarmScheduler` 的 Intent extra →
  /// `AlarmReceiver` → `AlarmRingService` → `AlarmSound`。另加一个布尔开关要同时改
  /// 这五处、还得改 `AlarmStore` 的开机重排记录，不值当。
  ///
  /// 它不可能与真实音源撞上：系统铃声是 `content://`、自选是 `file://`、内置**根本不存**
  /// 这个键（见 `profile_screen.dart` 写入的四个分支）。
  ///
  /// ⚠️ 与 Kotlin 侧的 `AlarmSound.VIBRATE_ONLY` **必须逐字一致**。两边各持一份常量
  /// 而不是互相 import（Dart 与 Kotlin 之间没有共享常量的通道），所以由
  /// `test/ringtone_vibrate_only_test.dart` 扫两边源码比对，改单边会当场变红。
  static const String vibrateOnlyRingtone = 'vibrateOnly';

  /// 让用户从系统文件选择器挑一个音频当铃声。
  ///
  /// 原生侧会把选中的文件**复制进应用私有目录**再返回 `file://` 路径 —— 不直接
  /// 用选择器给的 `content://`，那种授权不持久，重启或清理后就失效，而闹钟到点
  /// 读不到文件时用户是听不见错误的。
  ///
  /// 返回 `(显示名, URI)`；用户取消返回 null；失败抛 [RingtonePickException]。
  static Future<({String name, String uri})?> pickRingtoneFile() async {
    try {
      final raw =
          await _settingsChannel.invokeMethod('pickRingtoneFile') as Map?;
      if (raw == null) return null;
      final uri = raw['uri'] as String? ?? '';
      if (uri.isEmpty) return null;
      return (name: raw['name'] as String? ?? '', uri: uri);
    } on PlatformException catch (e) {
      throw RingtonePickException(e.code);
    } catch (e) {
      throw RingtonePickException('PICK_RINGTONE_FAILED');
    }
  }

  /// 把一个**已有的**音源 URI 复制进应用私有目录，返回 `(显示名, file:// URI)`。
  ///
  /// 「系统铃声」那一栏列的是 `RingtoneManager` 给的 `content://media/...`，那种
  /// URI 在响铃那一刻（前台服务、没有媒体读取权限）**可能打不开** —— 表现是
  /// 「明明设了铃声，闹钟响的还是内置那一声」，而且只在半夜发生、没有界面能报错
  /// （2026-11-16 真机：`AlarmSound: 自选铃声用不了，回落到内置铃声: content://media/
  /// external/audio/media/12837?title=Go%20Time&canonical=1`）。所以选系统铃声时
  /// 也走这条「复制一份」的路，与「从文件中选择」同源。
  ///
  /// 失败抛 [RingtonePickException]（`isTooLarge` / 其余 = 读不到）。
  static Future<({String name, String uri})> importRingtone(String uri) async {
    try {
      final raw = await _settingsChannel
          .invokeMethod('importRingtone', {'uri': uri}) as Map?;
      final fileUri = raw?['uri'] as String? ?? '';
      if (fileUri.isEmpty) throw RingtonePickException('RINGTONE_UNREADABLE');
      return (name: raw?['name'] as String? ?? '', uri: fileUri);
    } on PlatformException catch (e) {
      throw RingtonePickException(e.code);
    } catch (e) {
      if (e is RingtonePickException) rethrow;
      throw RingtonePickException('RINGTONE_UNREADABLE');
    }
  }

  /// 删掉复制进私有目录的自选铃声文件（换回内置/系统铃声时用，不留垃圾）。
  static Future<void> clearRingtoneFile() async {
    try {
      await _settingsChannel.invokeMethod('clearRingtoneFile');
    } catch (_) {}
  }

  /// 让原生侧确保「待办提醒」通知通道存在，并（重新）设置它的显示名。
  ///
  /// 通道名要在系统「通知」设置里显示，所以必须跟着界面语言走。通道只能在原生侧
  /// 创建（通知由 `TodoReminderReceiver` 在后台发出），但语言只有 Dart 侧知道 ——
  /// 于是启动时由这里把当前语言的名字递过去。同名通道重复创建是更新而不是报错，
  /// 所以每次启动调一次就能跟着语言切换走。
  static Future<void> ensureTodoChannel(String name) async {
    try {
      await _settingsChannel
          .invokeMethod('ensureTodoChannel', {'name': name});
    } catch (_) {}
  }

  /// 当前正在响铃的闹钟（null 表示没在响）。由通知回调/冷启动触发。
  static final ValueNotifier<AlarmRing?> ringingAlarm =
      ValueNotifier<AlarmRing?>(null);

  /// 开始响铃（原生 MediaPlayer 循环播放 + 震动），绕开通知声音系统。
  static Future<void> startAlarmSound() async {
    String? uri;
    try {
      final sp = await SharedPreferences.getInstance();
      uri = sp.getString('ringtoneUri');
    } catch (_) {}
    try {
      await _settingsChannel.invokeMethod('startAlarm', {'uri': uri ?? ''});
    } catch (_) {}
  }

  /// 停止响铃与震动。
  static Future<void> stopAlarmSound() async {
    try {
      await _settingsChannel.invokeMethod('stopAlarm');
    } catch (_) {}
  }

  /// 贪睡时长在 SharedPreferences 里的键（分钟）。
  static const String snoozeMinutesKey = 'snoozeMinutes';

  /// 当前贪睡时长（分钟）。
  ///
  /// ⚠️ **直接读 prefs，不走 `appSettingsProvider`。** 响铃界面是原生闹钟的
  /// intent 拉起来的，它**不 watch** 那个 provider，而设置要等 `_load()` 才落到
  /// 模块级标志上 —— 走那条路就多一处会静默失灵的依赖（v0.10.13 的
  /// `47_ringing_liquid` 出图与真机逐字节相同，正是这个坑的现场）。prefs 是唯一
  /// 真源，铃声那条路也是这么读的。
  ///
  /// 读到坏值（键被改成不在档位里的数）**退回默认**而不是照排：照排的话 `0`
  /// 会变成「按下就再响」、负数会排到过去，都比不给这一项更糟。
  static Future<int> snoozeMinutes() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getInt(snoozeMinutesKey);
      if (v != null && L10n.snoozeOptions.contains(v)) return v;
    } catch (_) {
      // 读不到（极少见）就当没设过 —— 这一条不该把响铃动作带崩。
    }
    return L10n.snoozeDefaultMinutes;
  }

  static Future<void> setSnoozeMinutes(int minutes) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(snoozeMinutesKey, minutes);
    } catch (_) {}
  }

  /// 再睡一会：按设置里的时长重新响铃（原生闹钟），标题与说明原样带过去。
  static Future<void> snoozeAlarm(AlarmRing ring) async {
    try {
      final fire = appNow().add(Duration(minutes: await snoozeMinutes()));
      await scheduleNativeAlarm(99998, fire, ring.title, detail: ring.detail);
    } catch (e) {
      await appendLog('snoozeAlarm 排定失败: $e');
    }
  }

  /// 排一条待办提醒（**普通通知**，不是全屏响铃闹钟）。
  ///
  /// **为什么不走 `flutter_local_notifications` 的 `zonedSchedule`**：它的排定
  /// API 只收 `TZDateTime`，而时区库的「本地时区」从来没设过（`init` 里只有
  /// `initializeTimeZones()`，依赖里也没有 `flutter_timezone`），`tz.local` 是
  /// UTC —— 照那样排，提醒会整体差一个时区偏移，而且不报错、只是时候不对。
  /// 原生这条走 epoch 毫秒，根本不碰时区。
  static Future<void> scheduleTodoReminder(
    int id,
    DateTime fireAt, {
    required String title,
    required String body,
    List<DateTime> repeatTimes = const [],
  }) async {
    try {
      await _settingsChannel.invokeMethod('scheduleTodoReminder', {
        'id': id,
        'millis': fireAt.millisecondsSinceEpoch,
        'title': title,
        'body': body,
        // 后续几次的绝对时刻（升序）。**规则不递过去** —— 原生只做「弹队首、
        // 续队尾」，规则判断全在 Dart 侧（那边有测试）。空数组 = 一次性提醒。
        'repeatTimes': [
          for (final t in repeatTimes) t.millisecondsSinceEpoch,
        ],
      });
    } catch (e) {
      await appendLog('scheduleTodoReminder 失败: $e');
    }
  }

  /// 取消全部待办提醒（按 id 区间扫，见 `_eventBaseId`）。
  static Future<void> cancelAllTodoReminders({bool keepStore = false}) async {
    try {
      await _settingsChannel
          .invokeMethod('cancelAllTodoReminders', {'keepStore': keepStore});
    } catch (_) {}
  }

  /// 原生落盘清单里当前记着的全部 id（响铃闹钟 + 安静提醒，两份合并）。
  ///
  /// 重排前用它算差集（[staleNativeIds]）。**读失败返回空** —— 调用方据此一条
  /// 都不撤：不知道系统里有什么的时候，盲撤比留着更危险。
  static Future<List<int>> nativeAlarmStoreIds() async {
    try {
      final raw = await _settingsChannel.invokeMethod('nativeAlarmStoreIds');
      if (raw is List) {
        return [
          for (final v in raw)
            if (v is int) v,
        ];
      }
    } catch (_) {}
    return const [];
  }

  /// 追加一条**诊断信息**到原生日志文件（落盘，「我的 → 查看日志」可复制）。
  ///
  /// 与 [appendLog] 的区别：那个走 `AlarmLog.error`，日志里看着像出了错；这个是
  /// 「给作者看的现场」，正常路径也要留。排障时用户贴来的就是这种行。
  static Future<void> appendDiagnostic(String msg) async {
    try {
      await _settingsChannel
          .invokeMethod('appendDiagnostic', {'msg': msg});
    } catch (_) {}
  }

  /// 用户点了待办提醒的通知 → 置位，壳子读到后切到「待办」页。
  ///
  /// 与 [ringingAlarm] 同一套机制：冷启动由 `init` 读原生侧的 pending 值置位，
  /// 热启动由原生侧反向 `onTodoTapped` 置位。
  static final ValueNotifier<bool> openTodoRequested = ValueNotifier<bool>(false);

  /// 读取由通知拉起时带着的待办 id（一次性）。
  static Future<int?> getPendingTodoId() async {
    try {
      final id = await _settingsChannel.invokeMethod('getPendingTodoId');
      return id is int ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// 待办提醒的触发时刻；这条待办不需要提醒时返回 null。
  ///
  /// 基准时间：待办设了时间就按那个时间，没设时间按当天 [allDayReminderHour]:00
  /// —— 界面上允许只设提醒不设时间，没有基准就排不出提醒。
  /// `advanceRemindMinutes` 为 0 表示「准时」（事件当时提醒）。
  ///
  /// 抽成顶层纯函数是为了能直接单测时间推算：它错了不会报错，只会**在错的时候
  /// 提醒**，那是靠界面看不出来的。
  static DateTime? eventReminderTime(ScheduleEvent e) {
    final advance = e.advanceRemindMinutes;
    if (advance == null || e.isCompleted) return null;
    final base = e.timeMinute ?? allDayReminderHour * 60;
    // e.date 是 `dateOnly(...)` 存下的（UTC 日期），只取它的年月日再按本地时区
    // 重建 —— 直接用会带着 UTC 标志，交给原生算 epoch 毫秒时会差一个时区。
    final d = e.date;
    return DateTime(d.year, d.month, d.day)
        .add(Duration(minutes: base - advance));
  }

  /// 待办提醒通知的正文：日期 + 时间。
  ///
  /// 写**完整日期**而不是「今天 / 明天」：提前一天的那档提醒是在前一天响的，
  /// 写「今天」就错了。
  static String eventReminderBody(ScheduleEvent e) {
    final d = e.date;
    final date = L10n.monthDayWeekday(DateTime(d.year, d.month, d.day));
    final t = e.timeMinute;
    return t == null ? '$date · ${L10n.allDay}' : '$date · ${formatClock(t)}';
  }

  /// 一次把全部闹钟重排：先读齐库里的排班 / 自定义闹钟 / 按天覆盖 / 待办，
  /// 再交给 [reschedule]。
  ///
  /// 调用点原先各自读库再分别传进来（六处），加待办之后每处都还要多读一次 ——
  /// 与其让每个调用点抄一遍，不如在这里读齐。漏传一个参数不会报错，只会让
  /// 那类提醒静默不生效，所以这个「读齐」的动作只该有一份。
  static Future<void> rescheduleAll(AppRepository repo) async {
    // 读的是**整条链**：未来 60 天里可能跨时段边界，边界之后那几天的班属于别的
    // 方案 —— 只按当前方案排会排到错的班表上，直到冷启动才自愈。
    final schedules = await repo.getActiveSchedules();
    if (schedules == null) return;
    await reschedule(
      schedules.chain,
      await repo.listCustomAlarms(),
      overrides: await repo.listShiftAlarmOverrides(),
      leaveMinutes: {
        for (final e in (await repo.listDayExtras()).entries)
          if (e.value.leaveMinutes > 0) e.key: e.value.leaveMinutes,
      },
      events: await repo.listEvents(),
      // 重复待办与一次性待办同一次交给原生：一条 [reconcileNative] 把「响铃」
      // 与「安静提醒」两批一起排，落盘清单一次写完（从前是逐条写、O(n²)）。
      recurring: await repo.listRecurringTodos(),
      shiftOn: schedules.chain.shiftOn,
    );
  }

  /// 按 [source] + [customAlarms] + [events] + [recurring] + [overrides] 重排所有闹钟。
  ///
  /// **先排后清**：整批交给原生 [reconcileNative] —— 它先把新计划全部排上，再撤掉
  /// 「落盘清单里有、新计划里没有」的那些。旧实现是「先全撤、再逐条排」，中间有
  /// 几秒系统里一条闹钟都没有；而每次闹钟响都会冷启动 App 并整链重排，进程死在
  /// 那个窗口里就全哑了（见 [NativeAlarm] 上面那段说明）。
  ///
  /// [overrides] 为按天覆盖（dayNumber → enabled）；值为 false 的日期跳过班次闹钟。
  /// [events] 是要排提醒的待办（`advanceRemindMinutes` 为 null 的跳过）。
  /// [recurring] 是重复待办的系列 —— 时刻由 [planRecurringReminders] 算，与一次性
  /// 待办一起交给原生（两条链路都在 2xxxx/4xxxx 号段）。
  ///
  /// [source] 是 [ShiftSource] 而不是 `ShiftSchedule`，理由见 [planShiftAlarms]。
  static Future<void> reschedule(
    ShiftSource source,
    List<CustomAlarm> customAlarms, {
    int days = _shiftDaysHorizon,
    Map<int, bool> overrides = const {},
    Map<int, int> leaveMinutes = const {},
    List<ScheduleEvent> events = const [],
    List<RecurringTodo> recurring = const [],
    ShiftClass? Function(DateTime day)? shiftOn,
  }) async {
    // id 算式是 `序号 × _shiftDaysHorizon + 天数偏移`：`days` 一旦超过天数窗口，
    // 「某天的第 2 个闹钟」就会撞上「更晚那天的第 1 个闹钟」。今天两个调用点都走
    // 缺省值，所以这里只是把那条隐含约束写成断言（debug 生效）。
    assert(days <= _shiftDaysHorizon,
        'days（$days）不得超过天数窗口 $_shiftDaysHorizon —— 原生 id 会撞号');
    await logInfo(
        'reschedule: 开始，排班=${source.label}，自定义闹钟=${customAlarms.length} 个');
    final Stopwatch sw = Stopwatch()..start();
    // 通知插件自己的缓存先清掉（它排过的 TZ 型通知与本链路无关，但顺手清干净；
    // 缓存损坏时 cancelAll 会抛 Missing type parameter）。
    try {
      await _plugin.cancelAll();
    } catch (e) {
      await appendLog('reschedule: cancelAll 异常，清缓存重试: $e');
      await clearNotificationCache();
      try {
        await _plugin.cancelAll();
      } catch (e2) {
        await appendLog('reschedule: cancelAll 二次仍异常: $e2');
      }
    }
    // 升级上来的机器可能残留「系统里有、落盘清单里没有」的孤儿 id —— 差集撤不到
    // 它们，所以升级后跑一次盲扫，之后不再扫（见 [_sweepLegacyOnce]）。
    await _sweepLegacyOnce();

    final now = appNow();
    // 1) 排班联动闹钟：未来 days 天。「哪些天要排、各排几点」由纯函数
    //    [planShiftAlarms] 决定（可单测），这里只把决策落成请求。
    final List<ShiftAlarmPlan> shiftPlans = planShiftAlarms(source,
        from: now, days: days, overrides: overrides, leaveMinutes: leaveMinutes);
    // 2) 自定义闹钟 / 3) 一次性待办 / 4) 重复待办
    final event = _eventRequests(events, now: now);
    final recurringReq = _recurringRequests(
        recurring, planRecurringReminders(recurring, from: now, shiftOn: shiftOn));

    await reconcileNative(
      alarms: [
        for (final p in shiftPlans)
          NativeAlarm(
            id: shiftAlarmNativeIdOf(p),
            fireAt: p.fireAt,
            label: L10n.shiftAlarmTitle(p.shift.name, p.alarm.label),
          ),
        ..._customAlarmRequests(customAlarms, now: now),
        ...event.alarms,
        ...recurringReq.alarms,
      ],
      quiets: [...event.quiets, ...recurringReq.quiets],
      ranges: nativeFullRanges,
      stopwatch: sw,
      detail: '班次 ${shiftPlans.length} / 自定义 '
          '${customAlarms.where((a) => a.enabled).length} / 待办 ${events.length}',
    );
  }

  /// 自定义闹钟 → 请求。**只排「下一次」**：每天/每周在触发后由原生用同一 id
  /// 自动续排，因此每个重复闹钟始终只有一条待触发记录。
  static List<NativeAlarm> _customAlarmRequests(
      List<CustomAlarm> alarms, {required DateTime now}) {
    final out = <NativeAlarm>[];
    for (final a in alarms) {
      if (!a.enabled) continue;
      final id = _customBaseId + a.id;
      switch (a.repeatType) {
        case 0: // 一次性
          final od = a.onceDate;
          if (od == null) break;
          final fire = DateTime(od.year, od.month, od.day, a.hour, a.minute);
          if (fire.isAfter(now)) {
            out.add(NativeAlarm(id: id, fireAt: fire, label: '自定义闹钟'));
          }
          break;
        case 2: // 每周
          final fire = _nextWeekly(now, a.weekdays, a.hour, a.minute);
          if (fire != null) {
            out.add(NativeAlarm(
              id: id,
              fireAt: fire,
              label: '自定义闹钟',
              repeatType: 2,
              hour: a.hour,
              minute: a.minute,
              weekdays: a.weekdays,
            ));
          }
          break;
        default: // 每天
          out.add(NativeAlarm(
            id: id,
            fireAt: _nextDaily(now, a.hour, a.minute),
            label: '自定义闹钟',
            repeatType: 1,
            hour: a.hour,
            minute: a.minute,
          ));
      }
    }
    return out;
  }

  /// 一次性待办 → 请求。联动闹钟走响铃链路、关掉走安静提醒，**同一个 id 二选一**。
  static ({List<NativeAlarm> alarms, List<NativeQuiet> quiets}) _eventRequests(
      List<ScheduleEvent> events, {required DateTime now}) {
    final alarms = <NativeAlarm>[];
    final quiets = <NativeQuiet>[];
    for (final e in events) {
      // **重复待办的「某一次」不在这里排**：它的提醒由系列那一条负责
      // （[_recurringRequests]）。两处都排的话同一次会响两声。
      if (e.seriesId != null) continue;
      final fireAt = eventReminderTime(e);
      if (fireAt == null || !fireAt.isAfter(now)) continue;
      final id = _eventBaseId + e.id;
      if (e.alarmEnabled) {
        alarms.add(NativeAlarm(
            id: id,
            fireAt: fireAt,
            label: e.title,
            detail: eventReminderBody(e)));
      } else {
        quiets.add(NativeQuiet(
            id: id,
            fireAt: fireAt,
            title: e.title,
            body: eventReminderBody(e)));
      }
    }
    return (alarms: alarms, quiets: quiets);
  }

  /// 重复待办 → 请求。规则全在 Dart 侧算好（[planRecurringReminders]），原生只做
  /// 「弹队首、续队尾」。
  static ({List<NativeAlarm> alarms, List<NativeQuiet> quiets}) _recurringRequests(
      List<RecurringTodo> series, List<RecurringAlarmPlan> plans) {
    final alarms = <NativeAlarm>[];
    final quiets = <NativeQuiet>[];
    final byId = {for (final s in series) if (s.id != null) s.id!: s};
    for (final p in plans) {
      final s = byId[p.seriesId];
      if (s == null) continue;
      final id = _recurringBaseId + p.seriesId;
      if (s.alarmEnabled) {
        alarms.add(NativeAlarm(
            id: id,
            fireAt: p.fireAt,
            label: s.title,
            detail: s.ruleWithTime,
            repeatTimes: p.repeatTimes));
      } else {
        quiets.add(NativeQuiet(
            id: id,
            fireAt: p.fireAt,
            title: s.title,
            body: s.ruleWithTime,
            repeatTimes: p.repeatTimes));
      }
    }
    return (alarms: alarms, quiets: quiets);
  }

  /// 把一整批请求交给原生：**先排、后撤**，一次跨端、一次落盘。
  ///
  /// 差集只在 Dart 侧算（[staleNativeIds]，有用例）。原生拿到的 `cancelIds` 就是
  /// 「确认不再需要」的那一个集合 —— 它不会再自行撤任何别的 id。
  static Future<void> reconcileNative({
    required List<NativeAlarm> alarms,
    required List<NativeQuiet> quiets,
    required List<(int, int)> ranges,
    Stopwatch? stopwatch,
    String? detail,
  }) async {
    final sw = stopwatch ?? (Stopwatch()..start());
    // 最近的那条排在最前：万一进程在这一批里被打断，也先保住马上要响的。
    final sorted = [...alarms]..sort((a, b) {
        final c = a.fireAt.compareTo(b.fireAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    // 快照读不到 → 空 → 差集为空 → **一条都不撤**。不知道系统里有什么的时候，
    // 盲撤比留着更危险（留下的最坏是旧闹钟多响一次）。
    final armed = await nativeAlarmStoreIds();
    final stale = staleNativeIds(
      armed: armed,
      desired: [for (final a in sorted) a.id, for (final q in quiets) q.id],
      ranges: ranges,
    );
    try {
      await _settingsChannel.invokeMethod('reconcileNativeAlarms', {
        'alarms': [for (final a in sorted) a.toMap()],
        'quiets': [for (final q in quiets) q.toMap()],
        'cancelIds': stale,
        'ranges': [
          for (final r in ranges) [r.$1, r.$2]
        ],
      });
    } catch (e) {
      await appendLog('reconcileNativeAlarms 失败: $e');
      return;
    }
    await appendDiagnostic(
        'alarm: 重排完成 —— 响铃 ${sorted.length} 条 / 提醒 ${quiets.length} 条 / '
        '撤旧 ${stale.length} 条，${sw.elapsedMilliseconds}ms'
        '${detail == null ? '' : '（$detail）'}；'
        '下一跳 ${nativeNextDigest(alarms: sorted, quiets: quiets)}');
  }

  /// 一次性历史清扫：把**不在落盘清单里**的孤儿 id 清掉。
  ///
  /// 旧版本每次启动都盲扫 `0..600` / `10000..11000` / `99990..100000` 与待办两段；
  /// 现在差集只撤清单里记着的 id，扫不到「系统里有、清单里没有」的残留。那类残留
  /// 只会出现在升级前（落盘清单是 v0.6 才有的），所以升级后跑一次就够。
  ///
  /// 标记存在**原生那份 prefs** 里（`AlarmStore`）：出厂重置会清空 Flutter 那份，
  /// 而重置之后不需要再扫 —— 空库重排的差集已经把所有旧 id 精确撤掉了。
  ///
  /// **失败不设标记** —— 下一次启动会再试一次。
  static Future<void> _sweepLegacyOnce() async {
    try {
      if (await _legacySweepDone()) return;
      // **清单留着**：清扫只撤系统里的那些孤儿 id，落盘清单交给随后那次整批重排
      // 改写。否则「清扫完、重排还没跑」这一两秒里系统与清单同时是空的，进程被杀
      // 就一路哑到用户下次主动打开 App —— 正是这一版要消灭的那种静默。
      await cancelAllNotificationAlarms();
      await cancelAllNativeAlarms(keepStore: true);
      await cancelAllTodoReminders(keepStore: true);
      await _settingsChannel.invokeMethod('markLegacySweepDone');
      await appendLog('alarm: 一次性历史清扫完成（升级残留的孤儿 id）');
    } catch (e) {
      await appendLog('alarm: 一次性历史清扫失败（下次启动再试）: $e');
    }
  }

  static Future<bool> _legacySweepDone() async {
    try {
      return await _settingsChannel.invokeMethod('legacySweepDone') == true;
    } catch (_) {
      // 读不到就当「没扫过」：多扫一次是安全的（它只撤不再需要的 id），
      // 少扫一次会留下孤儿闹钟。
      return false;
    }
  }

  /// 待办页增删改之后的**一次**重排：一次性提醒 + 重复待办提醒。
  ///
  /// 只碰待办号段（[nativeTodoRanges]）—— 勾一条待办不该把几百条班次闹钟全撤
  /// 重排一遍。两条一起排：从前这里只排一次性提醒，而重复系列的提醒只在冷启动
  /// 等 `rescheduleAll` 路径上才排得上 —— 新建一个重复待办可能当天该响却不响。
  ///
  /// 一条待办按 `alarmEnabled` **二选一**：联动闹钟（全屏 + 循环铃声）或普通
  /// 通知。两者用同一个 id（`_eventBaseId + e.id`），但目标组件不同
  /// （`AlarmReceiver` / `TodoReminderReceiver`）—— 重排交给原生时按「响铃/提醒」
  /// 两批分开递，取消则由差集按 id 一次撤掉两种。
  static Future<void> rescheduleTodoReminders(AppRepository repo) async {
    final active = await repo.getActiveSchedules();
    final shiftOn = active?.chain.shiftOn;
    final events = await repo.listEvents();
    final series = await repo.listRecurringTodos();
    final now = appNow();
    final event = _eventRequests(events, now: now);
    final recurring = _recurringRequests(
        series, planRecurringReminders(series, from: now, shiftOn: shiftOn));
    await reconcileNative(
      alarms: [...event.alarms, ...recurring.alarms],
      quiets: [...event.quiets, ...recurring.quiets],
      ranges: nativeTodoRanges,
      detail: '待办 ${events.length} / 重复系列 ${series.length}',
    );
  }

  /// 排班结构变了之后：先把按班次的「当前这一次」对齐，再整链重排闹钟。
  ///
  /// 两步缺一不可 —— 日历跟着库立刻变，但待办列表与原生闹钟都不会自己跟上
  /// （v0.12.1 的教训）。所有「会改变某天上什么班」的入口都走这里。
  static Future<void> replanAfterScheduleChange(AppRepository repo) async {
    await repo.advanceRecurringTodos(today: dateOnly(appNow()));
    await rescheduleAll(repo);
  }

  /// 下一次 [hour]:[minute]（今天未过则今天，否则明天），按设备本地时区。
  static DateTime _nextDaily(DateTime now, int hour, int minute) {
    var d = DateTime(now.year, now.month, now.day, hour, minute);
    if (!d.isAfter(now)) d = d.add(const Duration(days: 1));
    return d;
  }

  /// 下一次星期 [weekday]（1=周一..7=周日）的 [hour]:[minute]，按设备本地时区。
  static DateTime _nextWeekday(DateTime now, int weekday, int hour, int minute) {
    var d = DateTime(now.year, now.month, now.day, hour, minute);
    final delta = (weekday - d.weekday) % 7;
    d = d.add(Duration(days: delta));
    if (!d.isAfter(now)) d = d.add(const Duration(days: 7));
    return d;
  }

  /// 下一次匹配 [weekdays] 位掩码（1<<(周一=0)…）中任意一天的 [hour]:[minute]。
  /// 未选中任何一天时返回 null。
  static DateTime? _nextWeekly(
      DateTime now, int weekdays, int hour, int minute) {
    DateTime? best;
    for (var wd = 1; wd <= 7; wd++) {
      if ((weekdays & (1 << (wd - 1))) == 0) continue;
      final d = _nextWeekday(now, wd, hour, minute);
      if (best == null || d.isBefore(best)) best = d;
    }
    return best;
  }

}
