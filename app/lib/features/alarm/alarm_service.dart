import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import '../../core/l10n.dart';
import '../../data/app_repository.dart';
import '../../domain/shift_rotation.dart';
import '../widget/widget_service.dart';

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
/// [offset] 是距起点日的天数偏移（`0` = 起点当天），原生 id 由它算出
/// （`AlarmService._shiftBaseId + offset`）—— 这个映射必须保持不变，否则
/// 每次重排都会把闹钟换个号，用户设过的响铃记录会跟着错位。
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
/// 钟点取 [alarm] 的钟面值；[alarmFallsOnPreviousDay] 为真时整体前移一天 ——
/// 规则是「**不晚于上班时刻的最近一次该钟点**」，所以 00:00 上班、23:00 响铃排的是
/// 前一天 23:00（排在班次当天就已经是班后 15 小时了）。
///
/// 日期用 `DateTime(y, m, d - 1)` 重建而不是 `subtract(Duration(days: 1))`：
/// 后者减的是绝对 24 小时，碰上夏令时切换会把钟点也挪掉一小时。
DateTime shiftAlarmFireAt(DateTime date, ShiftClass shift, ShiftAlarm alarm) {
  final clock = alarm.minute;
  return alarmFallsOnPreviousDay(shift, alarm)
      ? DateTime(date.year, date.month, date.day - 1)
          .add(Duration(minutes: clock))
      : DateTime(date.year, date.month, date.day)
          .add(Duration(minutes: clock));
}

/// 决定「未来 [days] 天里哪些天要排班次联动闹钟、各排在几点」。
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
/// 触发时刻由 [shiftAlarmFireAt] 算（可能是**前一天**晚上），但 `offset` 与原生
/// id 始终按**班次那一天**算 —— id 是 `序号 × 天数窗口 + 天数偏移`，跟着触发时刻走
/// 的话，每个午夜班的闹钟都会换号。**「序号」是闹钟在 `shift.alarms` 里的下标**：
/// 用户在编辑页里调整顺序会让闹钟换号（可接受 —— 编辑之后必然重排、`cancelAll`
/// 先跑），但**重排本身绝不能重新编号**，否则每次打开 App 都换一批。
List<ShiftAlarmPlan> planShiftAlarms(
  ShiftSchedule schedule, {
  required DateTime from,
  required int days,
  Map<int, bool> overrides = const {},
}) {
  final today = dateOnly(from);
  final plans = <ShiftAlarmPlan>[];
  for (var d = 0; d < days; d++) {
    final date = today.add(Duration(days: d));
    final t = schedule.shiftOn(date);
    if (t == null || t.isRest || !t.alarmEnabled || t.alarms.isEmpty) {
      continue;
    }
    // 按天覆盖：该天被单独关闭则跳过
    if (overrides[dayNumber(date)] == false) continue;

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

/// 联动班次闹钟 + 自定义闹钟服务。
///
/// 排班闹钟排定未来 365 天；每次打开 App 自动续排，跟着排班走、不过期。
/// 自定义闹钟支持：一次性 / 每天 / 每周（可选星期几）。
class AlarmService {
  AlarmService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _shiftBaseId = 0;

  /// 班次闹钟排定的天数窗口（`reschedule` 的 [days] 缺省值）。
  ///
  /// **它就是原生 id 里的那个 60**：id = `序号 × 本值 + 天数偏移`。所以它与
  /// `maxAlarmsPerShift`（6，见 `domain/shift_rotation.dart`）是一对：
  /// 6 × 60 = 360 ≤ 400，而 Kotlin 侧 `cancelAllNativeAlarms` 扫的是 0..400
  /// （`MainActivity.kt:550`）。**改这个值必须同时改那个上限与 Kotlin 的扫描范围。**
  static const int _shiftDaysHorizon = 60;

  /// 测试用只读出口：id 算式是「上限 6」的由来，得能在纯测试里断言。
  static int get shiftDaysHorizonForTesting => _shiftDaysHorizon;

  static const _customBaseId = 10000;

  /// 待办提醒的原生 id 基址。三段互不重叠：班次 0..400、自定义 10000..11000、
  /// 待办 20000..21000（原生侧按这几个区间扫，见 `MainActivity` 的 cancel 分支）。
  static const _eventBaseId = 20000;

  static Future<void> init() async {
    // 时区库：当前**没有**用它的地方 —— 排定全部走原生（epoch 毫秒）或
    // `scheduleNativeAlarm`。留着是因为 `flutter_local_notifications` 的
    // 时区型 API 一旦被用到（比如以后真要上 `zonedSchedule`）就得先有它，
    // 而那时还必须补 `tz.setLocalLocation`，否则 `tz.local` 是 UTC、会整体
    // 差一个时区偏移（见 `scheduleTodoReminder` 的说明）。
    tz.initializeTimeZones();
    // 原生闹钟触发时（App 已在后台），MainActivity 通过此回调通知我们弹出响铃界面；
    // 待办提醒被点开时同样由它通知我们切到「待办」页。
    _settingsChannel.setMethodCallHandler((call) async {
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
      }
      // 小组件某一天被点击（热启动路径）。
      if (call.method == 'onWidgetDayTapped') {
        WidgetService.onNativeDayTapped(call.arguments as int);
      }
    });

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
  }) async {
    try {
      await _settingsChannel.invokeMethod('scheduleNativeAlarm', {
        'id': id,
        'millis': fireAt.millisecondsSinceEpoch,
        'label': label,
        'detail': detail,
        'repeatType': repeatType,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays,
      });
      await logInfo(
          'scheduleNativeAlarm 成功: id=$id, label=$label, repeatType=$repeatType');
    } catch (e) {
      await appendLog('scheduleNativeAlarm 失败: $e');
    }
  }

  /// 取消全部原生闹钟。
  static Future<void> cancelAllNativeAlarms() async {
    try {
      await _settingsChannel.invokeMethod('cancelAllNativeAlarms');
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

  /// 清空原生日志文件。
  static Future<void> clearLog() async {
    try {
      await _settingsChannel.invokeMethod('clearLog');
    } catch (_) {}
  }

  /// 用系统浏览器打开 [url]（用于「检查更新」跳转下载页）。
  static Future<void> openUrl(String url) async {
    try {
      await _settingsChannel.invokeMethod('openUrl', {'url': url});
    } catch (_) {}
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
    final fire = DateTime.now().add(const Duration(seconds: 10));
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

  /// 再睡一会：5 分钟后重新响铃（原生闹钟），标题与说明原样带过去。
  static Future<void> snoozeAlarm(AlarmRing ring) async {
    try {
      final fire = DateTime.now().add(const Duration(minutes: 5));
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
  }) async {
    try {
      await _settingsChannel.invokeMethod('scheduleTodoReminder', {
        'id': id,
        'millis': fireAt.millisecondsSinceEpoch,
        'title': title,
        'body': body,
      });
    } catch (e) {
      await appendLog('scheduleTodoReminder 失败: $e');
    }
  }

  /// 取消全部待办提醒（按 id 区间扫，见 `_eventBaseId`）。
  static Future<void> cancelAllTodoReminders() async {
    try {
      await _settingsChannel.invokeMethod('cancelAllTodoReminders');
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
    final sched = await repo.getActiveSchedule();
    if (sched == null) return;
    await reschedule(
      sched,
      await repo.listCustomAlarms(),
      overrides: await repo.listShiftAlarmOverrides(),
      events: await repo.listEvents(),
    );
  }

  /// 清除并按 [schedule] + [customAlarms] + [events] + [overrides] 重排所有闹钟。
  ///
  /// [overrides] 为按天覆盖（dayNumber → enabled）；值为 false 的日期跳过班次闹钟。
  /// [events] 是要排提醒的待办（`advanceRemindMinutes` 为 null 的跳过）。
  static Future<void> reschedule(
    ShiftSchedule schedule,
    List<CustomAlarm> customAlarms, {
    int days = _shiftDaysHorizon,
    Map<int, bool> overrides = const {},
    List<ScheduleEvent> events = const [],
  }) async {
    await logInfo(
        'reschedule: 开始，排班=${schedule.name}，自定义闹钟=${customAlarms.length} 个');
    // 先清掉可能已损坏的排定缓存，再 cancelAll（否则会抛 Missing type parameter）
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
    // 按 id 兜底取消所有通知闹钟 + 原生闹钟 + 待办提醒，清理历史累积（避免 500 上限）
    await cancelAllNotificationAlarms();
    await cancelAllNativeAlarms();
    await cancelAllTodoReminders();

    // 1) 排班联动闹钟：未来 days 天
    //
    // 「哪些天要排、各排几点」由 [planShiftAlarms] 这个纯函数决定（可单测）；
    // 这里只负责把决策落成原生闹钟。id 仍是 `_shiftBaseId + 天数偏移`。
    for (final plan in planShiftAlarms(schedule,
        from: DateTime.now(), days: days, overrides: overrides)) {
      try {
        await scheduleNativeAlarm(
            _shiftBaseId + plan.alarmIndex * _shiftDaysHorizon + plan.offset,
            plan.fireAt,
            L10n.shiftAlarmTitle(plan.shift.name, plan.alarm.label));
      } catch (e) {
        await appendLog('reschedule: 排班闹钟排定失败: $e');
      }
    }

    // 2) 自定义闹钟：原生 setAlarmClock 只排「下一次」；每天/每周在触发后由
    //    AlarmReceiver 用同一 id 自动续排，因此每个重复闹钟始终只有一条待触发记录。
    final now = DateTime.now();
    for (final a in customAlarms) {
      if (!a.enabled) continue;
      final alarmId = _customBaseId + a.id;
      try {
        switch (a.repeatType) {
          case 0: // 一次性
            final od = a.onceDate;
            if (od == null) break;
            final fire = DateTime(od.year, od.month, od.day, a.hour, a.minute);
            if (fire.isAfter(now)) {
              await scheduleNativeAlarm(alarmId, fire, '自定义闹钟');
            }
            break;
          case 2: // 每周
            final fire = _nextWeekly(now, a.weekdays, a.hour, a.minute);
            if (fire != null) {
              await scheduleNativeAlarm(
                alarmId,
                fire,
                '自定义闹钟',
                repeatType: 2,
                hour: a.hour,
                minute: a.minute,
                weekdays: a.weekdays,
              );
            }
            break;
          default: // 每天
            final fire = _nextDaily(now, a.hour, a.minute);
            await scheduleNativeAlarm(
              alarmId,
              fire,
              '自定义闹钟',
              repeatType: 1,
              hour: a.hour,
              minute: a.minute,
            );
        }
      } catch (e) {
        await appendLog('reschedule: 自定义闹钟排定失败: $e');
      }
    }

    // 3) 待办提醒：普通通知，不进闹钟那套（全屏 + 循环响铃对一条待办太重）。
    //    每条待办只有一个日期、没有重复，所以一次排完就是全部。
    await rescheduleEventReminders(events);
    await logInfo('reschedule: 完成');
  }

  /// 只重排待办提醒（待办增删改之后调用）。
  ///
  /// 待办页的增删改**不**走 [rescheduleAll]：那会把上千条班次闹钟全部取消再
  /// 重排一遍，而勾一个复选框其实只需要改这一条待办的通知。
  ///
  /// 一条待办按 `alarmEnabled` **二选一**：联动闹钟（全屏 + 循环铃声）或普通
  /// 通知。两者用的是同一个 id（`_eventBaseId + e.id`），但目标组件不同
  /// （`AlarmReceiver` / `TodoReminderReceiver`），所以取消时两种都要扫。
  static Future<void> rescheduleEventReminders(
      List<ScheduleEvent> events) async {
    await cancelAllTodoReminders();
    final now = DateTime.now();
    for (final e in events) {
      final fireAt = eventReminderTime(e);
      if (fireAt == null || !fireAt.isAfter(now)) continue;
      try {
        if (e.alarmEnabled) {
          await scheduleNativeAlarm(_eventBaseId + e.id, fireAt, e.title,
              detail: eventReminderBody(e));
        } else {
          await scheduleTodoReminder(
            _eventBaseId + e.id,
            fireAt,
            title: e.title,
            body: eventReminderBody(e),
          );
        }
      } catch (err) {
        await appendLog('rescheduleEventReminders: 排定失败: $err');
      }
    }
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
