// app/test/alarm_evidence_guard_test.dart
//
// 「闹钟没响」的**取证与自愈**护栏（v0.13.22）。
//
// 现场：2026-11-25 一位一加 PLK110（Android 16）用户报「早上 10:00 的闹钟没响」，
// 是连着两天的第二次。日志能证明排定侧完全正确（08:00:03 与 08:18:46 各排了
// 206 条、0 失败、清单里那条活到 10:06），而那一刻连 `AlarmReceiver.onReceive`
// 都没有 —— 进程在整个时间窗里一次都没起来。
//
// 那次排查卡在「拿不到系统侧的状态」上：诊断包里只有我们自己的落盘清单，
// 而 App 一启动就重排、把那条过期记录撤掉了（实测 ~180ms）。这一版补三件事，
// 任何一条被改回去，下次报障又会回到「分不清是谁丢的」：
//   1. 进程启动、**Flutter 起来之前**，先把「系统下一跳」与「清单最早」拍下来；
//   2. 同时记录上一次进程的退出原因（强行停止 / 被冻结 / 别的）；
//   3. 巡检不许被重排推后，并且提前到最早那条闹钟前 1 小时。
//
// 扫的是 Kotlin 源码，先剥注释再断言（E7：注释里出现那个词会把假护栏喂绿）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

void main() {
  const kt = 'android/app/src/main/kotlin/com/daoban/shiftassistantpro';

  String read(String name) => File('$kt/$name').readAsStringSync();

  final mainRaw = read('MainActivity.kt');
  final schedRaw = read('AlarmScheduler.kt');
  final dogRaw = read('AlarmWatchdog.kt');
  final bootRaw = read('BootReceiver.kt');
  final serviceRaw =
      File('lib/features/alarm/alarm_service.dart').readAsStringSync();
  final profileRaw =
      File('lib/features/profile/profile_screen.dart').readAsStringSync();
  final bundleRaw =
      File('lib/features/profile/diagnostic_bundle.dart').readAsStringSync();

  final mainCode = blankNonCode(mainRaw);
  final schedCode = blankNonCode(schedRaw);
  final dogCode = blankNonCode(dogRaw);
  final bootCode = blankNonCode(bootRaw);

  test('启动取证排在 super.onCreate 之前（也就是 Flutter 引擎起来之前）', () {
    final onCreate = mainCode.indexOf('override fun onCreate(');
    expect(onCreate, greaterThan(-1), reason: 'MainActivity 里找不到 onCreate');

    final snap = mainCode.indexOf('startupSnapshot', onCreate);
    final superCall =
        mainCode.indexOf('super.onCreate(savedInstanceState)', onCreate);
    expect(snap, greaterThan(onCreate), reason: 'onCreate 里没有启动取证');
    expect(superCall, greaterThan(onCreate));

    // 180ms：10:06:05.781 写「进程启动」、10:06:05.960 就已经重排完成。
    // 取证只要排在引擎起来之后，拍到的就全是「我们自己改过之后」的状态。
    expect(snap, lessThan(superCall),
        reason: '取证必须在 Dart 重排之前 —— 排到 super.onCreate 之后就已经晚了');
  });

  test('启动快照读的是系统的「下一枚闹钟」，不是我们自己的清单', () {
    expect(schedCode.contains('fun startupSnapshot('), isTrue,
        reason: '快照函数不见了：又只剩清单这一侧的自我印证');
    expect(schedCode.contains('nextAlarmClock'), isTrue,
        reason: '没读 AlarmManager.nextAlarmClock —— 那就分不清「记录被删」和「投递被拦」');
    expect(mainCode.contains('startupSnapshot'), isTrue,
        reason: '快照函数写了却没人调');
  });

  test('启动时记录上一次进程的退出原因', () {
    expect(schedCode.contains('getHistoricalProcessExitReasons'), isTrue,
        reason: '没有它，「强行停止 / 一键清理」与「被冻结」在日志里长得一模一样');
    // 常量值写死（`ApplicationExitInfo.REASON_FREEZER` 等是 API 31 的字段，
    // 引用会被 NewApi 拦下），所以这里断的是 `when` 的分支值。
    expect(schedCode.contains('10 ->'), isTrue,
        reason: '强行停止（REASON_USER_REQUESTED=10）这一档必须单独认出来');
    expect(schedCode.contains('14 ->'), isTrue,
        reason: '冻结器（REASON_FREEZER=14）这一档必须单独认出来');
    expect(mainCode.contains('lastExitDigest'), isTrue,
        reason: '退出原因写了却没人调');
  });

  test('巡检不会被重排推后，且提前到最早那条闹钟前 1 小时', () {
    expect(dogCode.contains('fun nextTarget('), isTrue,
        reason: '巡检时刻的算法不见了');
    expect(dogCode.contains('LEAD_MS'), isTrue,
        reason: '没有「闹钟前 1 小时也巡检一次」：0.5~2 小时的窗口里没有任何自愈机会');
    expect(dogCode.contains('scheduledAt'), isTrue,
        reason: '不记「已经排到几点」，就没法判断该不该覆盖');
    expect(dogCode.contains('pending <= target'), isTrue,
        reason: '这条判断是「只往前挪、不往后推」的实现 —— 2026-11-25 就是被它推后的');
    expect(bootCode.contains('forceScheduled'), isTrue,
        reason: '重启后 AlarmManager 已清空，必须无条件重排一次巡检');
  });

  test('一加 / OPPO 的「自启动」有专属入口', () {
    expect(mainCode.contains('colorOsStartupPage'), isTrue,
        reason: 'ColorOS 的自启动页解析不见了');
    expect(mainRaw.contains('checkColorOsStartupPage'), isTrue,
        reason: '通道方法名要和 Dart 侧对上，字符串在剥壳副本里已被清空');
    expect(mainRaw.contains('openColorOsStartupPage'), isTrue);
    expect(serviceRaw.contains("'checkColorOsStartupPage'"), isTrue,
        reason: 'Dart 侧没有对应的通道调用，原生写了也调不到');
    expect(serviceRaw.contains("'openColorOsStartupPage'"), isTrue);
    expect(profileRaw.contains('permColorOsStartup'), isTrue,
        reason: '「我的 → 权限」里没有这一行，一加用户看不到该开什么');
    expect(blankNonCode(profileRaw).contains('_openColorOsStartup'), isTrue,
        reason: '那一行没有点击动作');
  });

  test('诊断包 README 教会读「重排前」的那两行', () {
    expect(bundleRaw.contains('启动快照（重排前）'), isTrue,
        reason: 'README 还在教老的三分法 —— 导出时那条过期条目早被我们撤掉了');
    expect(bundleRaw.contains('上次退出原因'), isTrue,
        reason: 'README 没提退出原因这一行，用户抄了也白抄');
    expect(bundleRaw.contains('撤 N 条'), isTrue,
        reason: '「撤 N 条」是唯一能把「当时还在清单里」说清楚的计数器');
  });
}
