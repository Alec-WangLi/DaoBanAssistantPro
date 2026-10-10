// app/test/alarm_auto_stop_test.dart
//
// **响铃 15 分钟超时自停**的 Dart 这一半。
//
// 为什么要它：`AlarmRingService` 从前没有自停 —— 用户不在 / 睡着 / 手机扔在包里，
// 它就**一直响、一直震、一直占着前台服务与 WakeLock**。原生那一半（定时器、
// 撤通知、放锁）没有测试目标，但「原生说停了，Dart 这边要把界面收掉」这一半能测，
// 而且是最容易漏的一半：**声音停了、屏幕还占着**，用户会以为 App 卡死了。
//
// 原生那半条路径与用户手动关闭**完全相同**（`MainActivity.onAlarmAutoStopped` →
// `exitLockScreenMode()` + `stopForeground(REMOVE)` + `stopSelf()`），
// 所以这里只钉 Dart 的收尾动作。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AlarmService.ringingAlarm.value = null);

  test('原生发来 onAlarmAutoStopped：把 ringingAlarm 清掉', () async {
    AlarmService.ringingAlarm.value = const AlarmRing('测试闹钟', null);

    await AlarmService.handleNativeCall(
        const MethodCall('onAlarmAutoStopped', null));

    expect(AlarmService.ringingAlarm.value, isNull,
        reason: '声音停了、响铃界面还占着屏 —— 用户会以为 App 卡死。'
            '清掉这个值之后 `HomeShell` 才收得掉那层路由');
  });

  test('对照：别的原生回调不许碰 ringingAlarm', () async {
    AlarmService.ringingAlarm.value = const AlarmRing('测试闹钟', null);

    await AlarmService.handleNativeCall(
        const MethodCall('onTodoTapped', 7));

    expect(AlarmService.ringingAlarm.value, isNotNull,
        reason: '点一下待办通知不该把正在响的闹钟界面收掉');
  });
}
