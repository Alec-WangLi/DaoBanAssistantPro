// app/test/widget_cell_block_guard_test.dart
//
// 桌面小组件那几张卡底的**结构不变量**。Kotlin 在这个仓库里没有可跑的测试目标
// （真机是唯一的眼睛），所以这一族护栏只能**扫源码**：它们证明不了「画出来好不好
// 看」，只证明「该在的东西都在、该成对的都成对、两个方向的状态都设满了」。
//
// 与 `widget_fixed_cards_guard_test.dart` 同一套路、同一份家法。
//
// ⚠️ 这一族是**分任务长大**的（见实施计划）：本文件在任务 1 只守资源，
// 任务 2 加月历格那三条，任务 3 扩到周条并把下界提到 6，任务 4 提到 7。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 读一个相对 `app/` 的文件（Dart 测试的工作目录就是 `app/`）。
String _read(String rel) {
  final f = File(rel);
  expect(f.existsSync(), true,
      reason: '$rel 不存在 —— 要么实现还没做，要么这条护栏自己跟源码对不上了');
  return f.readAsStringSync();
}

void main() {
  test('四张资源成对存在：格子卡底与页面底，浅深各一', () {
    for (final base in ['widget_cell', 'widget_page']) {
      for (final tier in ['light', 'dark']) {
        final f = File('android/app/src/main/res/drawable/${base}_$tier.xml');
        expect(f.existsSync(), true,
            reason: '${base}_$tier.xml 不在 —— 少一张就是**某一档静默没有底**'
                '（另一档看不出来，真机上只有把系统切过去才会现形）');
      }
    }
  });

  test('页面底必须不透明（97% 会跌破 AA）', () {
    for (final tier in ['light', 'dark']) {
      final src = _read('android/app/src/main/res/drawable/widget_page_$tier.xml');
      final colors = RegExp(r'#([0-9A-Fa-f]{8})')
          .allMatches(src)
          .map((m) => m.group(1)!.toUpperCase())
          .toList();
      // 自证：扫不到色值时这条护栏是句空话，必须红。
      expect(colors.length, greaterThanOrEqualTo(2),
          reason: '页面底应当有渐变的两端色 —— 只扫到 ${colors.length} 个 8 位色值，'
              '要么资源被改回了单色，要么这条正则跟源码对不上了');
      for (final c in colors) {
        expect(c.substring(0, 2), 'FF',
            reason: '页面底 $tier 档有一个半透明端（#$c）—— 叠黑壁纸时 wg_muted '
                '只有 4.33:1，跌破 AA 4.5。这个数在 spec §5 里算过，别改成 97%');
      }
    }
  });
}
