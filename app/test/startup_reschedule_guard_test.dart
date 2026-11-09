// app/test/startup_reschedule_guard_test.dart
//
// 冷启动的重排路径必须包含重复待办的提醒。
//
// `AlarmService.reschedule()` 开头会 `cancelAllTodoReminders`（含重复待办号段），
// 但只排一次性行；重复待办要靠 `rescheduleAll()` 里追加的
// `rescheduleRecurringReminders`。冷启动调错成 `reschedule()` 的症状是静默的：
// App 一启动，重复待办的提醒就没了，要等用户打开待办页才回来。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

void main() {
  test('冷启动路径必须走 rescheduleAll，不能只走 reschedule', () {
    final src = blankNonCode(
        File('lib/features/home/home_shell.dart').readAsStringSync());
    expect(src.contains('AlarmService.rescheduleAll('), true);
    expect(src.contains('AlarmService.reschedule('), false,
        reason: 'reschedule 会取消重复待办提醒却不排回来');
  });
}
