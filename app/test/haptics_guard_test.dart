// app/test/haptics_guard_test.dart
//
// 守门：**除 `lib/core/haptics.dart` 外，任何文件不许直接调 `HapticFeedback.*`。**
//
// 少了这条，词汇表会被绕过 —— 新代码想加个震动就自己写一行 `HapticFeedback`，
// 那「三档语义 + 一处开关」两天就散了，而且绕过的那些**不会**受用户开关控制。
//
// 规则跑在剥过壳的副本上（见 `support/source_scan.dart`）：否则在注释里提一句
// `HapticFeedback` 就会把构建打红 —— `design_tokens_test` 在 v0.6.11 踩过这个坑。
//
// **两条断言**：第一条查「除词汇表外没人绕过」，第二条查「不算豁免时，恰好只命中
// 词汇表自己」。后者是这条守门的**自证** —— 只跑前一条的话，一次扫错目录、正则
// 打错、或剥壳把真代码清掉的回归，都会让 offenders 恒空、守门恒绿而没人知道
// （「从来没被看到失败过」的守门不算守门）。第二条用同一次走查的**同一个**实现，
// 所以它命的正是检测能力本身。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

/// 唯一允许直接调用 `HapticFeedback` 的文件。
const String _lexiconPath = 'lib/core/haptics.dart';

/// 走一遍 `lib/`，返回**直接出现 `HapticFeedback.`** 的文件路径（已排序）。
///
/// [includeLexicon] 为 false 时跳过豁免的那个文件。两条断言共用这一份实现 ——
/// 绝不把这次走查写两遍（两份迟早走偏，而走偏的表现是漏检，不会报错）。
///
/// 排序是为了失败信息**确定**：`listSync` 的顺序取决于文件系统。
List<String> _rawHapticCallFiles({required bool includeLexicon}) {
  final offenders = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll(r'\', '/');
    if (!includeLexicon && path == _lexiconPath) continue;
    if (blankNonCode(entity.readAsStringSync()).contains('HapticFeedback.')) {
      offenders.add(path);
    }
  }
  offenders.sort();
  return offenders;
}

void main() {
  test('除词汇表外，没有地方直接调 HapticFeedback', () {
    final offenders = _rawHapticCallFiles(includeLexicon: false);
    expect(
      offenders,
      isEmpty,
      reason: '这些文件绕过了词汇表直接调 HapticFeedback：\n'
          '  ${offenders.join('\n  ')}\n'
          '改用 core/haptics.dart 的 Haptics.select() / commit() / modeEnter()。'
          '它们经过用户开关，绕过的那行不会。',
    );
  });

  test('守门自证：不排除豁免时，扫描恰好只命中词汇表自己', () {
    // 这一条是**常驻证据**，替代「靠人记得手动破一次构建」。它同时钉住三件事：
    //   1. 走查真的走进了 `lib/`（目录名/递归没写错）；
    //   2. 匹配串真的能匹配到 `HapticFeedback.`（不是拼错了才恒空）；
    //   3. 剥壳没有把真代码当注释/字符串清掉（`haptics.dart` 那三处调用是活体样本）。
    // 任何一条坏掉，这条立刻红 —— 而不是让上一条静静地永远为真。
    expect(
      _rawHapticCallFiles(includeLexicon: true),
      [_lexiconPath],
      reason: '去掉豁免后应**恰好**命中 $_lexiconPath：\n'
          '  少命中 = 扫描/匹配/剥壳坏了，上一条守门会变成永远为真的空话；\n'
          '  多命中 = 真有文件绕过了词汇表（上一条也该同时红）。',
    );
  });
}
