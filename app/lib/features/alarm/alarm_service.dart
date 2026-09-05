import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import '../../data/app_database.dart';
import '../../domain/shift_rotation.dart';

/// 联动班次闹钟 + 自定义闹钟服务。
///
/// 排班闹钟排定未来 365 天；每次打开 App 自动续排，跟着排班走、不过期。
/// 自定义闹钟支持：一次性 / 每天 / 每周（可选星期几）。
class AlarmService {
  AlarmService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _shiftBaseId = 0;
  static const _customBaseId = 10000;

  static Future<void> init() async {
    tz.initializeTimeZones();
    // 原生闹钟触发时（App 已在后台），MainActivity 通过此回调通知我们弹出响铃界面
    _settingsChannel.setMethodCallHandler((call) async {
      if (call.method == 'onAlarmFired') {
        final label = call.arguments;
        await logInfo('Dart 收到 onAlarmFired: label=$label');
        if (label is String && label.isNotEmpty) {
          ringingAlarm.value = label;
        }
      }
    });
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
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
          ringingAlarm.value = payload;
        }
      }
    } catch (_) {}

    // 冷启动：检查是否由原生闹钟（AlarmReceiver）拉起
    final nativeLabel = await getPendingAlarmLabel();
    if (nativeLabel != null) {
      await logInfo('Dart init: 冷启动读取 pendingAlarmLabel=$nativeLabel');
      ringingAlarm.value = nativeLabel;
    }
  }

  static void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      ringingAlarm.value = payload;
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

  /// 打开「后台弹出界面 / 悬浮窗」权限设置（全屏闹钟需要）。
  static Future<void> openOverlaySettings() async {
    try {
      await _settingsChannel.invokeMethod('openOverlaySettings');
    } catch (_) {}
  }

  /// 本应用是否已获得「后台弹出界面 / 悬浮窗」权限。
  static Future<bool> checkOverlayPermission() async {
    try {
      return await _settingsChannel.invokeMethod('checkOverlayPermission') ??
          false;
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
  static Future<void> scheduleNativeAlarm(
    int id,
    DateTime fireAt,
    String label, {
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

  /// 读取由原生闹钟拉起时携带的闹钟标签（一次性）。
  static Future<String?> getPendingAlarmLabel() async {
    try {
      final label = await _settingsChannel.invokeMethod('getPendingAlarmLabel');
      return (label is String && label.isNotEmpty) ? label : null;
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

  /// 当前正在响铃的闹钟标签（null 表示没在响）。由通知回调/冷启动触发。
  static final ValueNotifier<String?> ringingAlarm = ValueNotifier<String?>(null);

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

  /// 再睡一会：5 分钟后重新响铃（原生闹钟）。
  static Future<void> snoozeAlarm(String label) async {
    try {
      final fire = DateTime.now().add(const Duration(minutes: 5));
      await scheduleNativeAlarm(99998, fire, label);
    } catch (e) {
      await appendLog('snoozeAlarm 排定失败: $e');
    }
  }

  /// 清除并按 [schedule] + [customAlarms] + [overrides] 重排所有闹钟。
  ///
  /// [overrides] 为按天覆盖（dayNumber → enabled）；值为 false 的日期跳过班次闹钟。
  static Future<void> reschedule(
    ShiftSchedule schedule,
    List<CustomAlarm> customAlarms, {
    int days = 60,
    Map<int, bool> overrides = const {},
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
    // 按 id 兜底取消所有通知闹钟 + 原生闹钟，清理历史累积（避免 500 上限）
    await cancelAllNotificationAlarms();
    await cancelAllNativeAlarms();

    final today = dateOnly(DateTime.now());

    // 1) 排班联动闹钟：未来 days 天
    for (var d = 0; d < days; d++) {
      final date = today.add(Duration(days: d));
      final t = schedule.shiftOn(date);
      if (t == null || t.isRest || !t.alarmEnabled || t.alarmMinute == null) {
        continue;
      }
      // 按天覆盖：该天被单独关闭则跳过
      if (overrides[dayNumber(date)] == false) continue;

      final fireAt = DateTime(date.year, date.month, date.day)
          .add(Duration(minutes: t.alarmMinute!));
      if (!fireAt.isAfter(DateTime.now())) continue;

      try {
        await scheduleNativeAlarm(_shiftBaseId + d, fireAt, '${t.name}提醒');
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
    await logInfo('reschedule: 完成');
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
