// app/test/ringtone_pick_result_test.dart
//
// 「从文件中选择铃声」的**回传解析**（2026-11-15 的真机反馈）。
//
// 现场：某台机用系统文件管理器（多选语义的选择器）选完 MP3，退回 App 后
// 一声不响、铃声列表里什么都没多出来。根因是原生侧只认 `data.data`，
// 拿不到就当成「用户取消」→ Dart 静默 return。
//
// 这一条钉住三件事，任何一条被改回去都要当场红：
//   1. 用 `ACTION_GET_CONTENT`（导入一份副本的语义，各厂商文件管理器实现最全）；
//   2. 回传解析有三种兜底：`data` → `clipData` → `EXTRA_STREAM`；
//   3. 「选了但没给 URI」是**独立的错误码**，不许再和「取消」合并成静默返回。
//
// 扫的是 Kotlin 源码，先剥注释再断言（E7：注释里出现那个词会把假护栏喂绿）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

void main() {
  final file = File(
      'android/app/src/main/kotlin/com/daoban/shiftassistantpro/MainActivity.kt');
  final raw = file.readAsStringSync();
  final code = blankNonCode(raw);

  test('铃声选择器用 ACTION_GET_CONTENT（不是 OPEN_DOCUMENT）', () {
    expect(code.contains('ACTION_GET_CONTENT'), isTrue,
        reason: '换回 ACTION_OPEN_DOCUMENT 会让部分 OEM 选择器又交不回文件');
  });

  test('回传解析认 data / clipData / EXTRA_STREAM 三种', () {
    expect(code.contains('resolvePickedUri'), isTrue,
        reason: '解析被内联回去了 —— 三种兜底就散了');
    expect(code.contains('clipData'), isTrue,
        reason: '丢了 clipData 兜底：多选语义的选择器正是把结果放这里');
    expect(code.contains('EXTRA_STREAM'), isTrue,
        reason: '丢了 EXTRA_STREAM 兜底：部分文件管理器只填这个');
  });

  test('「没拿到 URI」有独立错误码，不许当成用户取消', () {
    expect(raw.contains('PICK_NO_URI'), isTrue,
        reason: '没有这个错误码，界面又会变回「点了没反应」');
    expect(code.contains('PICK_NO_URI'), isFalse,
        reason: '它必须出现在**字符串**里（作为 MethodChannel 错误码），'
            '不在字符串里说明被写成了注释');
  });
}
