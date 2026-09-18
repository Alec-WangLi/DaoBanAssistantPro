// app/test/haptics_guard_test.dart
//
// 守门：**除 `lib/core/haptics.dart` 外，任何文件不许直接调 `HapticFeedback.*`。**
//
// 少了这条，词汇表会被绕过 —— 新代码想加个震动就自己写一行 `HapticFeedback`，
// 那「三档语义 + 一处开关」两天就散了，而且绕过的那些**不会**受用户开关控制。
//
// 规则跑在剥过壳的副本上（见 `support/source_scan.dart`）：否则在注释里提一句
// `HapticFeedback` 就会把构建打红 —— `design_tokens_test` 在 v0.6.11 踩过这个坑。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

/// 唯一允许直接调用 `HapticFeedback` 的文件。
const String _lexiconPath = 'lib/core/haptics.dart';

void main() {
  test('除词汇表外，没有地方直接调 HapticFeedback', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path == _lexiconPath) continue;
      if (blankNonCode(entity.readAsStringSync()).contains('HapticFeedback.')) {
        offenders.add(path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '这些文件绕过了词汇表直接调 HapticFeedback：\n'
          '  ${offenders.join('\n  ')}\n'
          '改用 core/haptics.dart 的 Haptics.select() / commit() / modeEnter()。'
          '它们经过用户开关，绕过的那行不会。',
    );
  });
}
