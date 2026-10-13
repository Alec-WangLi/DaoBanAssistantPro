// app/test/no_bare_text_button_test.dart
//
// 裸 Material 按钮在界面上读起来像正文、不像能点的东西 —— 这个仓库为同一类事
// 改过两次（v0.9.13「重复待办」、v0.11.4「已完成 N 条」）。v0.12.0 收掉最后两处。
//
// 判据落在**源码**上。剥壳与走查照 `haptics_guard_test.dart` 那份写
// （`test/support/source_scan.dart` 只提供 `blankNonCode(String)`，
// **没有**现成的「扫目录」函数 —— 各守门测试自己走 `Directory('lib')`）。
// `FilledButton` **允许**留两处（班次卡里的「添加班次」与错误态的「返回」，见 spec §7），
// 所以只查前三个。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

/// 走一遍 `lib/features`，返回**命中**的 `路径:行号`（已排序）。
///
/// 排序是为了失败信息**确定**：`listSync` 的顺序取决于文件系统。
List<String> _hits(List<String> needles) {
  final out = <String>[];
  for (final entity in Directory('lib/features').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll(r'\', '/');
    final lines = blankNonCode(entity.readAsStringSync()).split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (needles.any(lines[i].contains)) out.add('$path:${i + 1}');
    }
  }
  out.sort();
  return out;
}

void main() {
  test('lib/features 下不许出现裸 TextButton / ElevatedButton / OutlinedButton', () {
    // 带上 `.icon(` 那种构造形态：`TextButton.icon(` 里**没有** `TextButton(`
    // 这个子串，只查后者会让它悄悄溜过去（今天还没有这种调用点，所以现在仍绿）。
    final hits = _hits(const [
      'TextButton(', 'TextButton.icon(',
      'ElevatedButton(', 'ElevatedButton.icon(',
      'OutlinedButton(', 'OutlinedButton.icon(',
    ]);
    expect(hits, isEmpty,
        reason: '这些读起来像正文、不像能点的东西；换 GlassPill 或现成的玻璃件：\n'
            '${hits.join('\n')}');
  });
}
