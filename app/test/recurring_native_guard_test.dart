// app/test/recurring_native_guard_test.dart
//
// 原生那一段（时刻表续排）**没有可跑的测试目标** —— 这个仓库里没有 Android
// 单元测试的夹具。所以照 `widget_fixed_cards_guard_test.dart` 的老办法：扫源码，
// 把「编译期没有保护、错了又不报错」的几处约定钉住。
//
// 钉的是行为的存在性，不是实现细节：
//  ① 队列的挑选规则只有一处（`nextPending`），不许在接收器里各写一份；
//  ② 安静提醒那条链路响完要续排，且续排要走 `scheduleQuiet`（落盘与排定成对）；
//  ③ 落盘清单要能装下队列（否则重启后重复待办就不响了）；
//  ④ Dart 侧送的 key（`repeatTimes`）与原生读的 key 逐字一致；
//  ⑤ 时刻表驱动的响铃用 `repeatType = 3` 与自定义闹钟的续排区分开。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final f = File(path);
  expect(f.existsSync(), true, reason: '找不到 $path —— 测试的工作目录应当是 app/');
  return f.readAsStringSync();
}

const _dir = 'android/app/src/main/kotlin/com/daoban/shiftassistantpro';

void main() {
  test('队列的挑选只有一处实现（`AlarmScheduler.nextPending`）', () {
    final scheduler = _read('$_dir/AlarmScheduler.kt');
    expect(scheduler.contains('fun nextPending('), true,
        reason: '挑「第一个还没过的时刻」这件事只能有一份实现');
    // 接收器 / 开机重排里**不许**各自再写一遍筛选逻辑
    for (final f in [
      'TodoReminderReceiver.kt',
      'AlarmReceiver.kt',
      'BootReceiver.kt'
    ]) {
      final kt = _read('$_dir/$f');
      expect(kt.contains('AlarmScheduler.nextPending('), true,
          reason: '$f 要用队列续排，就得走同一个函数');
    }
  });

  test('安静提醒响完要续排，且续排要走 scheduleQuiet（落盘与排定成对）', () {
    final kt = _read('$_dir/TodoReminderReceiver.kt');
    expect(kt.contains('getLongArrayExtra("repeatTimes")'), true,
        reason: 'Dart 侧用 putExtra("repeatTimes", LongArray) 递过来的时刻表要读得到');
    expect(kt.contains('AlarmScheduler.scheduleQuiet('), true,
        reason: '绕开 scheduleQuiet 直接排 = 清单里少一条，重启后就不响了');
  });

  test('落盘清单装得下时刻表（两份清单都要）', () {
    final store = _read('$_dir/AlarmStore.kt');
    expect(store.contains('val repeatTimes: List<Long>'), true,
        reason: 'Quiet 与 Entry 都要带队列，否则重启后重复待办不再续排');
    expect(RegExp(r'put\("repeatTimes"').allMatches(store).length,
        greaterThanOrEqualTo(2),
        reason: '两份清单的写盘各要一处');
    // 读盘这里**数调用点而不是数 optJSONArray**：两处读的是同一个私有帮助函数
    // （`_readRepeatTimes`），所以 `optJSONArray("repeatTimes")` 只出现一次是
    // **对的** —— 这条护栏要盯的是「两份清单都读到了队列」，用调用点数才表达得准。
    expect(RegExp(r'_readRepeatTimes\(o\)').allMatches(store).length,
        greaterThanOrEqualTo(2),
        reason: '两份清单的读盘各要接上队列');
  });

  test('原生读的 key 与 Dart 侧送的 key 逐字一致', () {
    final dart = _read('lib/features/alarm/alarm_service.dart');
    expect(dart.contains("'repeatTimes':"), true,
        reason: 'Dart 侧要用这个 key 送时刻表');
    expect(_read('$_dir/AlarmScheduler.kt').contains('putExtra("repeatTimes"'),
        true);
  });

  test('时刻表驱动的响铃用 repeatType = 3 与自定义闹钟区分开', () {
    final dart = _read('lib/features/alarm/alarm_service.dart');
    expect(dart.contains('repeatTimes.isEmpty ? repeatType : 3'), true,
        reason: '队列优先于自定义闹钟的 nextDaily/nextWeekly 续排');
    expect(_read('$_dir/AlarmReceiver.kt').contains('repeatType == 3'), true);
    expect(_read('$_dir/BootReceiver.kt').contains('repeatType == 3'), true,
        reason: '重启后也要按同一条规则重排，否则重启一次就退回按星期重算');
  });

  test('号段：待办行在 20000 段、重复系列在 40000 段，且互不重叠', () {
    final s = _read('$_dir/AlarmScheduler.kt');
    expect(s.contains('TODO_BASE_ID = 20000'), true);
    expect(s.contains('RECURRING_BASE_ID = 40000'), true);
    // 上界：待办段不许伸进系列段
    expect(s.contains('RECURRING_BASE_ID + 2000'), true,
        reason: '取消与清单清理的范围要覆盖到系列段的上界');
  });

  test('取消改成按落盘清单走，不再盲目扫一大段 id', () {
    final s = _read('$_dir/AlarmScheduler.kt');
    final body = s.substring(s.indexOf('fun cancelTodoReminders'));
    expect(body.contains('AlarmStore.all('), true,
        reason: '先取消清单里记着的那几条');
    expect(body.contains('AlarmStore.allQuiets('), true,
        reason: '两份清单都要（响铃那条走 Entry，安静那条走 Quiet）');
    expect(body.contains('for (i in from until to)'), false,
        reason: '别再扫一大段 —— 号段已经到两万，每勾一次待办都要跑一遍');
  });
}
