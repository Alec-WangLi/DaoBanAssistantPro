// 桌面小组件的投递与启动意图。
//
// 与 `alarm_service.dart` 的关系：同一个 MethodChannel（`.../settings`），但各管
// 各的方法。**不能**在这里再 `setMethodCallHandler` —— 一个 MethodChannel 只有
// 一个 handler，`AlarmService.init()` 已经占了；原生推过来的 `onWidgetDayTapped`
// 由那边分派过来（见 `AlarmService.init`）。
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/schedule_chain.dart';
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

  /// 原生推过来的「点了小组件的某一天」。
  ///
  /// `HomeShell` 监听它做跳页（本任务已接）。`CalendarScreen` 还要读它来定位到
  /// 那一天 —— **那是 Task 7 的活**，此处尚未实现，别提前接。
  ///
  /// 与 `AlarmService.openTodoRequested` 同款：值非 null 表示有一次待处理的请求，
  /// 消费方处理完负责置回 null（置回会再触发一次监听，靠「值为 null 就返回」兜住）。
  static final ValueNotifier<DateTime?> widgetLaunchRequested =
      ValueNotifier<DateTime?>(null);

  /// 上一次**推成功**的那份内容指纹（`null` = 还没推过）。见 [push] 的说明。
  static String? _lastPushedKey;

  /// 清掉去重记忆。用例之间要隔离（它是模块级的）。
  @visibleForTesting
  static void resetPushCache() => _lastPushedKey = null;

  /// 把当前状态算成快照推给原生。
  ///
  /// 原生收到后会：落盘 → `updateAppWidget` 全部实例 → 重排下一次刷新闹钟。
  /// 所以「改完排班桌面立刻变」这件事，靠的就是这里被调到。
  ///
  /// **同一份内容不推第二次**：这个函数在首帧、每次回前台、排班变、外观变（含换
  /// 主色）、勾一条待办时都会跑，而它同步构建 224 天、编码约 48KB JSON 再跨一次端。
  /// 最常见的那次白付就是「回前台」—— 什么都没改，却整套重算 + 全量重渲染。
  static Future<void> push({
    required ScheduleChain? chain,
    required AppSettings settings,
    required int todayTodoCount,
  }) async {
    final DateTime now = DateTime.now();
    // 指纹取**输入**而不是 JSON：快照是
    // (链, 窗口, 今天, 主题, 主色, 今日待办数) 的纯函数（见 `buildWidgetSnapshot`），
    // 这六样一样不差地覆盖了它。直接比 JSON 是不行的 —— 里面带 `genAtMs`
    // （生成时刻，毫秒），两次调用之间必然不同，等于永不命中。
    final String key = <String>[
      chain?.cacheKey ?? '-',
      widgetWindow(now).from.millisecondsSinceEpoch.toString(),
      dateOnly(now).millisecondsSinceEpoch.toString(),
      settings.themeMode.name,
      settings.accentColor.toARGB32().toString(),
      todayTodoCount.toString(),
    ].join('|');
    if (key == _lastPushedKey) return;
    try {
      final json = jsonEncode(buildWidgetSnapshot(
        chain: chain,
        now: now,
        themeMode: settings.themeMode.name,
        accent: settings.accentColor.toARGB32(),
        todayTodoCount: todayTodoCount,
      ));
      await _channel.invokeMethod<bool>('widgetPushSnapshot', {'json': json});
      // ⚠️ **只在推成功之后才记。** 失败也记的话，那条「装完新版先打开一次 App」的
      // 兜底重试（回前台再推一次）就永远不会再试 —— 桌面会一直挂着升级前那一次的
      // 渲染字节，而用户在界面上看不出任何异常。
      _lastPushedKey = key;
    } catch (e) {
      // 小组件是锦上添花：没有它 App 一切照常，推失败不打扰用户、也不中断调用方
      // （它多半跑在 build 之后的后帧回调里）。
      //
      // 但**要留痕**：「桌面怎么没变」这类问题只能靠日志排查，而这一层恰好是唯一
      // 知道 push 发生过的地方 —— 静默吞掉等于把唯一线索也扔了。
      // 直接走 channel 而不 import `alarm_service.dart`：那两个文件互相 import 会
      // 成环，而 `logInfo` 本来就是同一条 channel 上的一个方法名。
      try {
        await _channel.invokeMethod('logInfo', {'msg': 'widgetPushSnapshot 失败: $e'});
      } catch (_) {
        // 连日志都发不出去（引擎已经没了）—— 到这一步没什么可做的了。
      }
    }
  }

  /// 走 channel 的 `logInfo` 留一条痕（原生落盘到 `ShiftAssistant` 日志）。
  ///
  /// 与 [push] 的 catch 同一个 channel、同一个方法名。**不 import `alarm_service.dart`**：
  /// 那两个文件互相 import 会成环（见文件头），而 `logInfo` 本来就是同一条 channel
  /// 上的一个方法名 —— 各持一份常量比互相 import 干净。
  static Future<void> logInfo(String msg) async {
    try {
      await _channel.invokeMethod('logInfo', {'msg': msg});
    } catch (_) {
      // 连日志都发不出去（引擎已经没了）—— 到这一步没什么可做的了。
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
