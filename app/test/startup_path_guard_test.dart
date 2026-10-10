// app/test/startup_path_guard_test.dart
//
// **首帧之前那条路上不许再有白付的东西。**
//
// 这一条管的是 `tz.initializeTimeZones()`（`latest_all` = 全量 IANA 库）：
// 实测 **21ms**（宿主；真机更慢），跑在 `main()` 里、**首帧之前**，而全仓从来没有
// 一处 `zonedSchedule` / `TZDateTime` —— 排定全部走原生（epoch 毫秒）或
// `scheduleNativeAlarm`。2026-10-10 删掉，这条防它长回来。
//
// 真要上 `flutter_local_notifications` 的时区型 API 时才该加回来，且**必须同时补
// `tz.setLocalLocation`**（否则 `tz.local` 是 UTC、整体差一个时区偏移）——
// `alarm_service.dart` 的 `init()` 里留着这句话。
//
// 扫的是**剥过注释与字符串**的副本（`support/source_scan.dart`）：`init()` 里正好
// 有一句注释提到这个方法名，不剥就会把构建打红 —— 与 `haptics_guard_test.dart`、
// `liquid_scope_guard_test.dart` 同一套路。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

void main() {
  const String needle = 'initializeTimeZones';

  /// 走一遍 `lib/`，返回剥壳之后仍出现 [needle] 的文件路径（已排序 ——
  /// `listSync` 的顺序取决于文件系统，排序是为了失败信息确定）。
  List<String> readers() {
    final List<String> hits = <String>[];
    for (final FileSystemEntity entity
        in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String path = entity.path.replaceAll(r'\', '/');
      if (blankNonCode(entity.readAsStringSync()).contains(needle)) {
        hits.add(path);
      }
    }
    hits.sort();
    return hits;
  }

  test('首帧前的启动路径上没有时区库初始化', () {
    expect(readers(), isEmpty,
        reason: '时区库（latest_all）是全量 IANA 库、实测 21ms，而全仓没有一处用它 —— '
            '要加回来必须先有一条 `zonedSchedule` / `TZDateTime` 的调用点，'
            '且同时补上 `tz.setLocalLocation`');
  });

  // ── 守门的自证（没有这两条，一次扫错目录或匹配串打错都让它恒绿）────────────
  test('自证：真代码扫得到', () {
    expect(blankNonCode('void f() { tz.initializeTimeZones(); }'), contains(needle),
        reason: '剥壳没把真代码吃掉');
  });

  test('自证：注释里的不算数', () {
    expect(blankNonCode('// 不要再把 tz.initializeTimeZones() 加回来'),
        isNot(contains(needle)),
        reason: '注释里提一句不该打红');
  });
}
