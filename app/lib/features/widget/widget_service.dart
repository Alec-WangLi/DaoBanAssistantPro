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
import '../../state/app_settings.dart';
import 'widget_snapshot.dart';
import '../../core/clock.dart';

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

  /// 上一次推送失败的原因（`null` = 还没推过 / 上一次成功）。
  ///
  /// 存在的理由：「桌面怎么没变」这件事在界面上**看不见** —— 原生侧只会把卡片画成
  /// 上一次的样子（或者干脆停在降级态），而 `push` 的 catch 里那条 `logInfo` 只有
  /// 抓 logcat 的人才看得到。这个位给 `HomeShell` 在**重试用尽**之后提示一次，
  /// 免得用户以为是自己没打开过 App。
  static final ValueNotifier<String?> lastFailure = ValueNotifier<String?>(null);

  /// 清掉去重记忆。用例之间要隔离（它是模块级的）。
  @visibleForTesting
  /// 仅供测试：把模块级状态（去重的「上一份」与「在飞」）一起清掉。
  ///
  /// **两个要一起清**：只清去重的话，上一个用例里那发没跑完的推送会把 `_inFlight`
  /// 留成 `true`，下一个用例的冷启动推送就被守卫**静默丢掉** —— 表现是
  /// 「前提：冷启动那几次确实试过推」那种断言莫名其妙地空掉（第一次加守卫时
  /// `home_shell_nav_test` 就是这么红的）。
  @visibleForTesting
  static void resetPushCache() {
    _lastPushedKey = null;
    _inFlight = false;
    lastFailure.value = null;
  }

  /// 上一次推送还在飞。`true` 时后来的触发**直接丢掉**。
  ///
  /// 为什么需要它：五个触发点（首帧 / 回前台 / 排班变 / 外观变 / 勾待办）**可能挨在
  /// 一起** —— 保存一次排班会让好几个 provider 连着发。而 [push] 中间要同步构建
  /// 224 天 + 编码两份 JSON + 跨一次端；上一次还在飞的时候第二次进来，去重键又是
  /// 不同的（内容真的变了），于是两发一起压到原生侧、把全部实例重渲染两遍。
  ///
  /// ⚠️ **必须用 `finally` 放开**：一次失败就把闸门永久关死，比没有守卫更糟 ——
  /// 那之后再也推不出去，而桌面上什么都看不出来。
  static bool _inFlight = false;

  /// 把当前状态算成快照推给原生。
  ///
  /// 原生收到后会：落盘 → `updateAppWidget` 全部实例 → 重排下一次刷新闹钟。
  /// 所以「改完排班桌面立刻变」这件事，靠的就是这里被调到。
  ///
  /// **同一份内容不推第二次**：这个函数在首帧、每次回前台、排班变、外观变（含换
  /// 主色）、勾一条待办时都会跑，而它同步构建 224 天、编码约 48KB JSON 再跨一次端。
  /// 最常见的那次白付就是「回前台」—— 什么都没改，却整套重算 + 全量重渲染。
  /// 返回值 = **这一发到底有没有落到桌面上**（`true` 也包含「内容没变，省掉了」）。
  /// 调用方（`HomeShell`）拿它决定要不要延迟重推，见那里的 `_pushWidgetSnapshot`。
  ///
  /// ⚠️ **构建快照本身也会抛**（`buildWidgetSnapshot` 要算 224 天的农历、跨午夜、
  /// 班次解析），而它原先在 `try` 之外 —— 抛了既不落盘、也不留痕、更不会重推。
  /// 这是「打开过 App、桌面却一直是降级态」那条链上**最前面**的静默点
  /// （2026-11-05 独立审查指出）。现在整段都在 `try` 里。
  static Future<bool> push({
    required ScheduleChain? chain,
    required AppSettings settings,
    required int todayTodoCount,
  }) async {
    final DateTime now = appNow();
    String json;
    String key;
    try {
      final Map<String, Object?> snap = buildWidgetSnapshot(
        chain: chain,
        now: now,
        themeMode: settings.themeMode.name,
        accent: settings.accentColor.toARGB32(),
        todayTodoCount: todayTodoCount,
      );
      json = jsonEncode(snap);
      // 去重键 = **内容本身**，只把「生成时刻」那一项换成常量（它每次都不同，但它不是
      // 内容；`genAtMs` 只有诊断用途，原生侧一个字都没读它）。
      //
      // ⚠️ **别退回「手写一串输入当指纹」** —— 那串东西漏一项就是「该推的没推」，
      // 而它已经漏过一次（拿 `chain.cacheKey` 当指纹：那是**信息卡高度**的指纹，
      // 不含按天改班、周期、班组起始日、班组错位，也不含语言 ⇒ 「调一次班」或
      // 「换一次语言」之后桌面小组件**一直画着旧的**，而 App 里已经变了）。
      // 比内容自己会覆盖将来新增的每一个字段 —— 代价只是多一次 `jsonEncode`
      // （热态那次构建 8~11ms，编码占其中一小截）。
      snap['genAtMs'] = 0;
      key = jsonEncode(snap);
    } catch (e) {
      // 构建这一层抛了（农历、跨午夜、班次解析都可能）。到不了原生，桌面就永远
      // 停在降级态 —— 而这条路上原先连一条日志都没有。
      lastFailure.value = '构建快照失败: $e';
      await logInfo('buildWidgetSnapshot 失败: $e');
      return false;
    }
    if (key == _lastPushedKey) return true;
    // 上一次还在飞：这一发不发车（见 [_inFlight]）。放在去重之后，因为「同一份内容」
    // 本来就不该发，那是更省的那条路。
    //
    // ⚠️ **必须回 `false`，不能回 `true`**（2026-11-05 独立审查指出）：能走到这一行
    // 就说明 `key != _lastPushedKey`，**这一发的内容和还在飞的那发不一样** —— 在飞那发
    // 带的是旧内容。回 true 等于告诉调用方「这一发落地了」，于是最新的那份内容
    // 被静默丢掉，桌面要等到下一次触发（改排班 / 回前台）才跟上。这正是「改完排班
    // 桌面没变」那一类投诉的形状。
    //
    // 回 false 之后调用方会排一次尾重推（3 秒），那时在飞那发早回来了，推的就是
    // **最新**内容 —— 连续几个 provider 一起发的情形因此收敛成「最后一发」。
    // 注意这里**不是失败**：`lastFailure` 清空，调用方据此不把它算进失败预算
    // （见 `HomeShell._scheduleWidgetRetry`）。
    if (_inFlight) {
      lastFailure.value = null;
      return false;
    }
    _inFlight = true;
    try {
      // 原生侧**如实回话**（`MainActivity` 的 `widgetPushSnapshot` 分支：落盘成没成、
      // `refreshAll` 有没有抛，都会回一个布尔）。`null` 当成功 —— 用例里的假通道、
      // 以及将来别的实现都可能不回值。
      final bool? ok =
          await _channel.invokeMethod<bool>('widgetPushSnapshot', {'json': json});
      if (ok == false) {
        lastFailure.value = '原生侧回 false（落盘或刷新失败）';
        await logInfo('widgetPushSnapshot 原生侧回 false —— 快照没落到桌面上');
        return false;
      }
      // ⚠️ **只在推成功之后才记。** 失败也记的话，那条「装完新版先打开一次 App」的
      // 兜底重试（回前台再推一次）就永远不会再试 —— 桌面会一直挂着升级前那一次的
      // 渲染字节，而用户在界面上看不出任何异常。
      _lastPushedKey = key;
      lastFailure.value = null;
      return true;
    } catch (e) {
      // 小组件是锦上添花：没有它 App 一切照常，推失败不打扰用户、也不中断调用方
      // （它多半跑在 build 之后的后帧回调里）。
      //
      // 但**要留痕**：「桌面怎么没变」这类问题只能靠日志排查，而这一层恰好是唯一
      // 知道 push 发生过的地方 —— 静默吞掉等于把唯一线索也扔了。
      // 直接走 channel 而不 import `alarm_service.dart`：那两个文件互相 import 会
      // 成环，而 `logInfo` 本来就是同一条 channel 上的一个方法名。
      lastFailure.value = '$e';
      try {
        await _channel.invokeMethod('logInfo', {'msg': 'widgetPushSnapshot 失败: $e'});
      } catch (_) {
        // 连日志都发不出去（引擎已经没了）—— 到这一步没什么可做的了。
      }
      return false;
    } finally {
      // ⚠️ **放在 `finally` 里**：成功、失败、连日志都发不出去，三条路都要放开闸门。
      // 少放一次，这条链路就永久哑了（而界面上看不出来）。
      _inFlight = false;
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
