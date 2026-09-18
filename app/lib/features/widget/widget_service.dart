// 桌面小组件的投递与启动意图。
//
// 与 `alarm_service.dart` 的关系：同一个 MethodChannel（`.../settings`），但各管
// 各的方法。**不能**在这里再 `setMethodCallHandler` —— 一个 MethodChannel 只有
// 一个 handler，`AlarmService.init()` 已经占了；原生推过来的 `onWidgetDayTapped`
// 由那边分派过来（见 `AlarmService.init`）。
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/shift_rotation.dart';
import '../../state/app_settings.dart';
import 'widget_snapshot.dart';

/// 与 `AlarmService._settingsChannel` 同一个名字 —— MethodChannel 按名字寻址，
/// Dart 侧多个实例会落到原生同一个 handler 上。各自持有常量比互相 import 私有
/// 字段干净。
const MethodChannel _channel =
    MethodChannel('com.daoban.shiftassistantpro/settings');

class WidgetService {
  WidgetService._();

  /// 原生推过来的「点了小组件的某一天」。`CalendarScreen` 与 `HomeShell` 都监听它。
  ///
  /// 与 `AlarmService.openTodoRequested` 同款：值非 null 表示有一次待处理的请求，
  /// 消费方处理完负责置回 null（置回会再触发一次监听，靠「值为 null 就返回」兜住）。
  static final ValueNotifier<DateTime?> widgetLaunchRequested =
      ValueNotifier<DateTime?>(null);

  /// 把当前状态算成快照推给原生。
  ///
  /// 原生收到后会：落盘 → `updateAppWidget` 全部实例 → 重排下一次刷新闹钟。
  /// 所以「改完排班桌面立刻变」这件事，靠的就是这里被调到。
  static Future<void> push({
    required ShiftSchedule? schedule,
    required AppSettings settings,
  }) async {
    try {
      final json = jsonEncode(buildWidgetSnapshot(
        schedule: schedule,
        now: DateTime.now(),
        themeMode: settings.themeMode.name,
        accent: settings.accentColor.toARGB32(),
      ));
      await _channel.invokeMethod<bool>('widgetPushSnapshot', {'json': json});
    } catch (_) {
      // 小组件是锦上添花：没有它 App 一切照常。推失败不打扰用户、也不中断调用方
      // （它多半跑在 build 之后的后帧回调里）。
    }
  }

  /// 冷启动由小组件拉起时，读一次原生存下的「要跳到哪天」。
  ///
  /// 热启动**不走这里** —— 那时 Dart 已经在跑，原生直接推 `onWidgetDayTapped`。
  /// 这个分界是既有代码注释里写明的（见 `MainActivity.handleAlarmIntent`）。
  static Future<void> consumeLaunchDay() async {
    try {
      final day = await _channel.invokeMethod<int>('getWidgetLaunchDay');
      if (day == null) return;
      widgetLaunchRequested.value = dateFromEpochDay(day);
    } catch (_) {}
  }

  /// `LocalDate.toEpochDay()` → 本地日历日的 `DateTime`。
  ///
  /// 返回的是 **UTC 的纯日期**（`dateOnly()` 同一口径）—— `isSameDay` / `dayNumber`
  /// 都按 UTC 日期整数比较，与日历页的 `_selected` 混用不会出错；反过来若返回本地
  /// 午夜的 `DateTime`，在 UTC+8 下会比出「前一天」。
  static DateTime dateFromEpochDay(int epochDay) =>
      DateTime.fromMillisecondsSinceEpoch(
        epochDay * Duration.millisecondsPerDay,
        isUtc: true,
      );

  /// 原生推来的一天（热启动路径）。由 `AlarmService.init` 的 channel handler 转发。
  static void onNativeDayTapped(int epochDay) {
    widgetLaunchRequested.value = dateFromEpochDay(epochDay);
  }
}
