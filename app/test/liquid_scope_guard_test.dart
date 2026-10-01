// app/test/liquid_scope_guard_test.dart
//
// 守门：**液态档的判据只许出现在下面 [_allowed] 列的那几处。**
//
// 2026-10-01 把液态玻璃推广到分段器与开关时，这条名单从 2 处扩到 4 处 ——
// 注意**新抽出来的两个件（`liquid_lens_controller` / `liquid_track`）不在名单里**：
// 它们不读档位，判据只出现在调用点。多写了不该有的位置也是一种错误，同一条用例照得出。
//
// 2026-10-01 用户拍板：「咱们先把这个液态玻璃应用到底部导航栏，之前修改的其他
// 地方先暂时不动。」这条守门把那个决定变成会失败的用例 —— 将来有人往别的玻璃面
// 搬液态效果而没想清楚，这里会先红，而不是等到用户看见一排「不知道是什么情况」
// 的边缘（v0.10.2 就是这么在闹钟页与待办页各挨了一条反馈）。
//
// 规则跑在剥过壳的副本上（`support/source_scan.dart`）：否则在注释里提一句这个词
// 就会把构建打红 —— 本文件顶上这段注释里就有它。
//
// **两条断言**，与 `haptics_guard_test.dart` 同一套路：第一条查「没人在允许的位置
// 之外读它」；第二条是守门的**自证** —— 只跑前一条的话，一次扫错目录、匹配串打错、
// 或剥壳把真代码清掉的回归，都会让 offenders 恒空、守门恒绿而没人知道。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

/// 允许出现这个判据的位置（前缀匹配）。
const List<String> _allowed = <String>[
  'lib/core/glass/glass.dart', // 定义处
  'lib/features/home/', // 底栏
  'lib/core/widgets/glass_segment.dart', // 分段器
];

const String _needle = 'liquidGlassActive';

/// 走一遍 `lib/`，返回**剥壳之后**仍出现 [_needle] 的文件路径（已排序）。
///
/// [exempt] 为 true 时跳过 [_allowed] 里的那些位置。两条断言共用这一份实现 ——
/// 绝不把这次走查写两遍（两份迟早走偏，而走偏的表现是漏检，不会报错）。
///
/// 排序是为了失败信息**确定**：`listSync` 的顺序取决于文件系统。
List<String> _readers({required bool exempt}) {
  final List<String> hits = <String>[];
  for (final FileSystemEntity entity
      in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final String path = entity.path.replaceAll(r'\', '/');
    if (exempt && _allowed.any(path.startsWith)) continue;
    if (blankNonCode(entity.readAsStringSync()).contains(_needle)) {
      hits.add(path);
    }
  }
  hits.sort();
  return hits;
}

void main() {
  test('液态档的判据没有出现在允许的位置之外', () {
    final List<String> offenders = _readers(exempt: true);
    expect(
      offenders,
      isEmpty,
      reason: '这些文件读了 $_needle，但液态档现阶段只作用于底栏：\n'
          '  ${offenders.join('\n  ')}\n'
          '要么把它搬回底栏，要么先想清楚那一处的观感再动 —— '
          '规格：docs/superpowers/specs/2026-10-01-liquid-nav-redesign-design.md',
    );
  });

  test('守门自证：不豁免时，命中的恰好是那几个已知位置', () {
    // 这一条是**常驻证据**，替代「靠人记得手动破一次构建」。它同时钉住三件事：
    //   1. 走查真的走进了 `lib/`（目录名 / 递归没写错）；
    //   2. 匹配串真的能匹配到（不是拼错了才恒空）；
    //   3. 剥壳没有把真代码当注释清掉（`glass.dart` 那三处是真代码样本）。
    // 任何一条坏掉，这条立刻红 —— 而不是让上一条静静地永远为真。
    expect(
      _readers(exempt: false),
      // **按字典序**（`_readers` 排过序）—— 顺序写反了也会红。
      <String>[
        'lib/core/glass/glass.dart',
        'lib/core/widgets/glass_segment.dart',
        'lib/features/home/glass_nav_bar.dart',
      ],
      reason: '去掉豁免后应**恰好**命中这两处（定义处 + 底栏）：\n'
          '  少命中 = 扫描 / 匹配 / 剥壳坏了，上一条守门会变成永远为真的空话；\n'
          '  多命中 = 真有文件在允许的位置之外读了它（上一条也该同时红）。\n'
          '  底栏在 Task 2 从 `home_shell.dart` 搬进了 `glass_nav_bar.dart` —— '
          '这条自证本来就是要跟着现实走的，它红过一次，改的就是这里。',
    );
  });
}
