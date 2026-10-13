// app/test/press_feedback_guard_test.dart
//
// 全 app 的按压反馈是「玻璃按压缩放」（GlassPressable）。`InkWell` 是 Material
// 水波纹，**只该长在共享件里**（`lib/core/widgets/` 那几个玻璃件用它、并垫了
// `Material` 让波纹浮在玻璃之上 —— 见 `glass_pressable.dart` 顶上的根因说明）。
// 散在 `lib/features/` 里的那些属于漏网：v0.12.0 收掉 12 处。
//
// 判据落在**源码**上，剥壳与走查照 `haptics_guard_test.dart` 那份写
// （`test/support/source_scan.dart` 只提供 `blankNonCode(String)`）。
//
// **两条断言**：第一条查「`lib/features` 下没有人自己写 `InkWell`」，第二条
// （扫 `lib/core/widgets`）是这条守门的**自证** —— 只跑前一条的话，目录名打错、
// 正则/needle 敲错一两个字符、或 `blankNonCode` 退化成把真代码清掉，都会让
// `hits` **恒为空、守门恒绿**而没人知道（AGENTS.md v0.10.13：一条恒为真的守卫
// 比没有守卫更糟）。第二条用**同一份**走查实现，所以它命的正是检测能力本身。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

/// 走一遍 [root]，返回**剥壳后仍出现 [needle] 的行**（`路径:行号`，已排序）。
///
/// 两条断言共用这一份实现 —— 绝不把这次走查写两遍（两份迟早走偏，而走偏的表现
/// 是漏检，不会报错）。排序是为了失败信息**确定**：`listSync` 的顺序取决于文件系统。
List<String> _hits(String needle, {String root = 'lib/features'}) {
  final out = <String>[];
  for (final entity in Directory(root).listSync(recursive: true)) {
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

  test('守门自证：同一份走查扫 lib/core/widgets，必须找得到 InkWell', () {
    // 那几个共享玻璃件（glass_button / glass_pill / glass_action_button /
    // glass_choice_chip / glass_dialog / glass_snackbar）确实用着 `InkWell` ——
    // 所以这是个**一定存在**的样本：一条都扫不到，只能是走查本身坏了
    // （根目录写错、needle 敲错、或剥壳把真代码清掉），而上面那条守卫会因此恒绿。
    //
    // 这一条是**常驻证据**，替代「靠人记得手动破一次构建」。
    final hits = _hits('InkWell(', root: 'lib/core/widgets');
    expect(hits, isNotEmpty,
        reason: '同样一趟扫 lib/core/widgets 却一条都没命中：走查（根目录 / '
            'needle / 剥壳）坏了，上面那条守卫会永远为真。');
  });
}
