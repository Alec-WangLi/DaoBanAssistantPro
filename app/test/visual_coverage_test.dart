// app/test/visual_coverage_test.dart
//
// 守门：**`lib/features` 下每一个 `*_screen.dart` 都必须在视觉工装屏单里**
// （`tool/visual/visual_screens.dart` 的 `visualScreens`）—— D8 的护栏。
//
// 这条一直写在规范里、却**没有护栏**（D8 强度标着「自守」）。代价已经发生过一次：
// v0.14.0 新加了 `BackupScreen` 与 `LogScreen`，两屏都没进屏单 —— 出图与对比度
// 审计照常跑、照常绿，只是**静默跳过了这两页**。漏掉不报错，正是自守条目最典型的
// 失效方式（与 AGENTS.md「危险的不是会红，是静默空转」同一条）。
//
// 判据是「类名出现在屏单源码的**代码**里」，不是「出现在 import 里」：
// `blankNonCode` 会把字符串内容清成空格，所以只 import 不渲染 = 没覆盖，
// 而 `build: (db) async => const BackupScreen()` 才是覆盖。这条性质由自证用例钉住。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

/// 一个文件里所有「看起来是一屏」的顶层类名（以 `Screen` 结尾）。
///
/// 只看**代码**：`blankNonCode` 之后注释里的类名不算。
List<String> _screenClasses(String src) => RegExp(
      r'^class ([A-Z]\w*Screen)\b',
      multiLine: true,
    ).allMatches(blankNonCode(src)).map((m) => m.group(1)!).toList();

/// [sources]（路径 → 源码）里没有被 [listSrc] 覆盖到的屏。
///
/// 拆成纯函数是为了能用合成源码正反两面钉 —— 与 `design_tokens_test` 的
/// `_violationsIn` 同一套路。
List<String> _missingScreens(Map<String, String> sources, String listSrc) {
  final String list = blankNonCode(listSrc);
  final List<String> out = <String>[];
  for (final MapEntry<String, String> e in sources.entries) {
    final List<String> screens = _screenClasses(e.value);
    if (screens.isEmpty) continue; // 没有 Screen 类的文件不归这条管
    if (!screens.any(list.contains)) {
      out.add('${e.key} → ${screens.join(' / ')}');
    }
  }
  out.sort();
  return out;
}

/// 真目录：`lib/features` 下所有 `*_screen.dart` 的源码。
Map<String, String> _screenSources() {
  final Map<String, String> sources = <String, String>{};
  for (final FileSystemEntity entity
      in Directory('lib/features').listSync(recursive: true)) {
    if (entity is! File) continue;
    final String path = entity.path.replaceAll(r'\', '/');
    if (!path.endsWith('_screen.dart')) continue;
    sources[path] = entity.readAsStringSync();
  }
  return sources;
}

void main() {
  test('lib/features 下每一屏都在视觉工装屏单里', () {
    final List<String> missing = _missingScreens(
      _screenSources(),
      File('tool/visual/visual_screens.dart').readAsStringSync(),
    );
    expect(
      missing,
      isEmpty,
      reason: '这些屏没有进 tool/visual/visual_screens.dart 的 visualScreens：\n'
          '  ${missing.join('\n  ')}\n'
          '新加一屏就要在屏单里加一条 —— 不然出图与对比度审计会静默跳过它，'
          '而两件事都显示「绿」。',
    );
  });

  test('自证：扫得到类名，既不太宽也不太窄', () {
    // 正面：顶层 `class XxxScreen` 认得出。
    expect(_screenClasses('class BackupScreen extends ConsumerStatefulWidget {'),
        <String>['BackupScreen']);
    // 反面：不以 Screen 结尾的类不算一屏。
    expect(_screenClasses('class BlockFrame extends StatelessWidget {'),
        isEmpty);
    // 反面：注释里写的不算（否则「讨论过它」就等于「覆盖了它」）。
    expect(_screenClasses('// class LogScreen 以后再拍\n'), isEmpty);
  });

  test('自证：只 import 不渲染 = 没覆盖', () {
    // 这条是本守门的关键性质。`blankNonCode` 把 import 路径的字符串清成空格，
    // 于是 `contains('BackupScreen')` 只认真正的渲染代码。
    final Map<String, String> sources = <String, String>{
      'lib/features/backup/backup_screen.dart':
          'class BackupScreen extends ConsumerStatefulWidget {}',
    };

    final List<String> importOnly = _missingScreens(
      sources,
      "import 'package:shiftassistantpro/features/backup/backup_screen.dart';",
    );
    expect(importOnly, hasLength(1),
        reason: '只 import 不算覆盖 —— 否则「加了文件但没加屏」会被这层放过');

    final List<String> rendered = _missingScreens(
      sources,
      'build: (db) async => const BackupScreen(),',
    );
    expect(rendered, isEmpty, reason: '真渲染了就该算覆盖');
  });
}
