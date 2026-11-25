// app/lib/features/profile/diagnostic_bundle.dart
//
// 诊断包（v0.13.20）：用户报障时一键导出 —— 日志（含按天归档）+ 设备/权限快照 +
// 原生落盘清单 + App 自己算出来的未来 7 天计划。
//
// 为什么不是「只把日志复制出来」：日志只回答「发生了什么」，回答不了
// 「App 当时认为应该发生什么」。把落盘清单与计划一起带走，才分得清
// 「App 根本没排」和「排了、被系统丢了」—— 这正是「偶尔没响」最难查的一段。
//
// 隐私：日志与计划里有用户写的待办标题、班次备注。导出是用户主动选保存位置，
// 界面在导出前**必须**把这一点说明白（见 `log_screen.dart`）。

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../core/app_info.dart';
import '../../core/clock.dart';
import '../../data/app_repository.dart';
import '../alarm/alarm_service.dart';

class DiagnosticBundle {
  const DiagnosticBundle._();

  /// 组装 zip 写到 [dir]，返回文件路径。
  ///
  /// 任何一步取不到（原生通道失败）都按空处理，不中断打包 —— 一份缺项的
  /// 诊断包也比「导出失败、什么都没拿到」有用。
  static Future<String> build(AppRepository repo,
      {required Directory dir}) async {
    final Archive archive = Archive();
    void addText(String name, String content) {
      final List<int> bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    // 1) 日志：当前文件 + 全部按天归档
    for (final LogFileInfo f in await AlarmService.listLogFiles()) {
      final String text = await AlarmService.readLogFile(f.name);
      if (text.isEmpty) continue;
      addText(f.name == 'app_log.txt' ? 'app_log.txt' : 'logs/${f.name}', text);
    }

    // 2) 设备与权限
    final Map<String, dynamic> device = await AlarmService.deviceReport();
    addText(
        'device.json',
        const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
          ...device,
          'appVersion': appVersion,
          'schemaVersion': AppDatabase.schemaVersionNumber,
          'exportedAt': appNow().toIso8601String(),
        }));

    // 3) 原生落盘清单：App 认为系统里应该躺着哪些闹钟
    final List<Map<String, dynamic>> store =
        await AlarmService.nativeAlarmStore();
    addText(
        'alarms.json',
        const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
          'count': store.length,
          'entries': <Map<String, dynamic>>[
            for (final Map<String, dynamic> e in store)
              <String, dynamic>{...e, 'at': _isoOfMillis(e['millis'])},
          ],
        }));

    // 4) App 按当前排班算出来的未来 7 天计划
    addText(
        'plan.json',
        const JsonEncoder.withIndent('  ')
            .convert(await AlarmService.diagnosticPlan(repo)));

    // 5) 说明
    addText('README.txt', _readme());

    final List<int> bytes = ZipEncoder().encodeBytes(archive);
    final File file =
        File(p.join(dir.path, 'shiftassistant-diagnostics-${_stamp()}.zip'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 毫秒时间戳 → 本地 ISO 字符串（原生清单里存的是 epoch 毫秒）。
  static String? _isoOfMillis(Object? millis) {
    if (millis is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis.toInt())
        .toIso8601String();
  }

  /// 文件名里的时间戳：`20261124-1345`。用 [appNow] 而不是 `DateTime.now()`，
  /// 与全仓「时钟只有一个出口」同一条纪律。
  static String _stamp() {
    final DateTime n = appNow();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}-'
        '${two(n.hour)}${two(n.minute)}';
  }

  static String _readme() => '''
ShiftAssistant 诊断包
=====================

app_log.txt      当前日志（最近一段，超过 256KB 只保留最新的部分）
logs/*.txt       按天归档的日志（保留 7 天）
device.json      设备、系统版本、时区、权限状态、App 版本与数据库 schema
alarms.json      App 认为系统里应该躺着的闹钟（原生落盘清单，含 id 与触发时刻）
plan.json        App 按当前排班算出来的未来 7 天计划（班次 / 自定义 / 待办）

怎么读「闹钟该响却没响」（v0.13.22 起按这个顺序看）：

  0) 先看出事那次启动的「进程启动」那一行**紧下面**这两行 —— 它们是在任何重排
     **之前**写的，所以是唯一没被 App 自己改过的现场：

         启动快照（重排前）：系统下一跳 11-25 10:00 / 清单最早 11-25 10:00 id=61（已过期）
         上次退出原因：中途被要求结束(10，含强行停止/一键清理)（11-25 10:00，status=0）

       · 两边**是同一个时刻**（哪怕它已经过期）→ 那条记录还在系统的闹钟里，
         是**投递**被拦（自启动关着 / 应用速冻 / 后台限制）；
       · 系统那边**更晚或「无」**，而清单里那条已经过期 → 记录**已经被删**
         （被强行停止 / 一键清理 / 「闹钟和提醒」权限被撤）。

     「上次退出原因」：中途被要求结束(10) = 强行停止 / 一键清理；被系统冻结器
     杀掉(14) = 厂商冻结；「无记录」本身在异常重启后也可疑。

  1) 「重排完成 … 撤 N 条」里的 N：那条没响的闹钟如果当时还躺在清单里，
     打开 App 后的第一次重排会把它当陈旧记录（已经过期）撤掉 —— N 里就有它。

  2) plan.json 里有、alarms.json 里没有 → App 算出来了却没排进系统。
     注意 alarms.json 是**打开 App 之后**的状态，过期条目已经被撤掉了。

  3) 有 AlarmReceiver.onReceive、没有 AlarmSound 开始播放 → 响铃服务或音源
     出了问题（onReceive 的第一句就落盘，所以「没有那行」= 广播压根没到）。

注意：日志里有你写的待办标题与班次备注，分享前请确认接收方。
''';
}
