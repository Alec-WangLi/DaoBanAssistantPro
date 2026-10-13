// app/test/press_feedback_guard_test.dart
//
// 全 app 的按压反馈是「玻璃按压缩放」（GlassPressable）。`InkWell` 是 Material
// 水波纹，**只该长在共享件里**（`lib/core/widgets/` 那几个玻璃件用它、并垫了
// `Material` 让波纹浮在玻璃之上 —— 见 `glass_pressable.dart` 顶上的根因说明）。
// 散在 `lib/features/` 里的那些属于漏网：v0.12.0 收掉 12 处。
//
// 判据落在**源码**上，剥壳与走查照 `haptics_guard_test.dart` 那份写
// （`test/support/source_scan.dart` 只提供 `blankNonCode(String)`）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

List<String> _hits(String needle) {
  final out = <String>[];
  for (final entity in Directory('lib/features').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll(r'\', '/');
    final lines = blankNonCode(entity.readAsStringSync()).split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains(needle)) out.add('$path:${i + 1}');
    }
  }
  out.sort();
  return out;
}

void main() {
  test('InkWell 不许出现在 lib/features 里（它属于共享件）', () {
    final hits = _hits('InkWell(');
    expect(hits, isEmpty,
        reason: '换成 GlassPressable（它自带按压缩放与垫在玻璃上的 Material）：\n'
            '${hits.join('\n')}');
  });
}
