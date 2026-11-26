// app/test/liquid_scope_guard_test.dart
//
// 守门：**液态档的判据只许出现在下面 [_allowed] 列的那几处。**
//
// 2026-10-01 把液态玻璃推广到分段器与开关时，这条名单从 2 处扩到 4 处 ——
// 注意**新抽出来的两个件（`liquid_lens_controller` / `liquid_track`）不在名单里**：
// 它们不读档位，判据只出现在调用点。多写了不该有的位置也是一种错误，同一条用例照得出。
// v0.10.13 加响铃页那枚药丸（5 → 6），v0.10.15 加日历那枚选中块（6 → 7）——
// 后者同样带出一个不读档位的新件 `calendar_lens.dart`，它**不进名单**。
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
  'lib/core/widgets/glass_check.dart', // 待办那个勾
  'lib/core/widgets/glass_segment.dart', // 分段器
  'lib/core/widgets/glass_switch.dart', // 开关
  // 响铃页那枚「上滑关闭」的药丸（2026-10-01 用户拍板：「同时挂在液态玻璃开关
  // 后面……要像底栏那样分一棵树出来」）。
  'lib/features/alarm/alarm_ringing_screen.dart',
  // 日历那枚选中块（v0.10.15）。判据只在这一个文件里读 —— 它分两处岔口
  // （`_glassBlock` 与 `AnimatedScale`），但都在同一棵子树里。
  // ⚠️ **`calendar_lens.dart` 不进名单**：它不读档位（与 `liquid_track.dart` 同一条纪律）。
  'lib/features/calendar/calendar_screen.dart',
];

const String _needle = 'liquidGlassActive';

/// 除 `liquidGlassActive` 之外的三个档位标志，**各有各的范围**。
///
/// v0.14.1 补。此前只有 `liquidGlassActive` 被守，另外三个在源码里各被读 6~10 处、
/// 一处护栏都没有 —— 规范写「判据只许出现在定义处 + 六个文件」，实际只管住了其中
/// 一个变量，绿测试的覆盖面比说的窄。
///
/// **为什么不塞进同一张名单**：它们不是同一件事，混在一起只会靠扩大豁免来变绿。
///   - `liquidGlassEnabled` 是**用户开关**：写入方在设置层（`app_settings`），
///     读取方只有 `glass.dart` 的 `recomputeGlassTiers`。页面直接读它就会绕过
///     省电档 —— 低端机本该退回标准档，绕过就有一台机器在算它算不动的合成（D4）。
///   - `glassBlurDisabled` 是**省电档**：玻璃件和背景动效各自据此决定要不要糊
///     （D4「省电档结构/交互一字不变」的另一半）。
///   - `liquidRefractionEnabled` 是**折射可用性闸门**（D10）：只在 `glass.dart`
///     里判一次，其余玻璃件读的是它算好的结果。
const Map<String, List<String>> _flagScopes = <String, List<String>>{
  'liquidGlassEnabled': <String>[
    'lib/core/glass/', // 定义 + recomputeGlassTiers
    'lib/state/app_settings.dart', // 读写设置
  ],
  'glassBlurDisabled': <String>[
    'lib/core/glass/', // 定义 + GlassPanel / GlassBlur
    'lib/core/theme/animated_background.dart', // 省电档停背景
  ],
  'liquidRefractionEnabled': <String>[
    'lib/core/glass/', // 定义 + 判据出口
  ],
};

/// 全部命中 [needle] 的文件（剥壳后，已排序）。
List<String> _readersOf(String needle) {
  final List<String> hits = <String>[];
  for (final FileSystemEntity entity
      in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final String path = entity.path.replaceAll(r'\', '/');
    if (blankNonCode(entity.readAsStringSync()).contains(needle)) {
      hits.add(path);
    }
  }
  hits.sort();
  return hits;
}

/// 走一遍 `lib/`，返回**剥壳之后**仍出现 [_needle] 的文件路径（已排序）。
///
/// [exempt] 为 true 时跳过 [_allowed] 里的那些位置。两条断言共用这一份实现 ——
/// 绝不把这次走查写两遍（两份迟早走偏，而走偏的表现是漏检，不会报错）。
///
/// 排序是为了失败信息**确定**：`listSync` 的顺序取决于文件系统。
List<String> _readers({required bool exempt}) => _readersOf(_needle)
    .where((String path) => !(exempt && _allowed.any(path.startsWith)))
    .toList();

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
        'lib/core/widgets/glass_check.dart',
        'lib/core/widgets/glass_segment.dart',
        'lib/core/widgets/glass_switch.dart',
        'lib/features/alarm/alarm_ringing_screen.dart',
        'lib/features/calendar/calendar_screen.dart',
        'lib/features/home/glass_nav_bar.dart',
      ],
      reason: '去掉豁免后应**恰好**命中这几处（定义处 + 六个调用点）：\n'
          '  少命中 = 扫描 / 匹配 / 剥壳坏了，上一条守门会变成永远为真的空话；\n'
          '  多命中 = 真有文件在允许的位置之外读了它（上一条也该同时红）。\n'
          '  底栏在 Task 2 从 `home_shell.dart` 搬进了 `glass_nav_bar.dart` —— '
          '这条自证本来就是要跟着现实走的，它红过一次，改的就是这里。',
    );
  });

  group('其余三个档位标志各有各的范围', () {
    for (final MapEntry<String, List<String>> entry in _flagScopes.entries) {
      test('${entry.key} 没有出现在声明的范围之外', () {
        final List<String> offenders = _readersOf(entry.key)
            .where((String path) => !entry.value.any(path.startsWith))
            .toList();
        expect(
          offenders,
          isEmpty,
          reason: '这些文件读了 ${entry.key}，但它的范围是 ${entry.value}：\n'
              '  ${offenders.join('\n  ')}\n'
              '新页面要判档位，走 `liquidGlassActive`（D5）或让玻璃件自己判断；'
              '直接读底层标志会绕过省电档 / 折射闸门。',
        );
      });
    }

    test('守门的常驻证据：三个标志的读取点清单', () {
      // 与上面 `liquidGlassActive` 那条同类：钉住「此刻到底谁在读」。
      // 清单变了（多一处正当的写入、或某个件被搬走）就红 —— 让人**有意识地**
      // 改这张表，而不是让守门悄悄变宽。
      expect(_readersOf('liquidGlassEnabled'), <String>[
        'lib/core/glass/glass.dart',
        'lib/state/app_settings.dart',
      ]);
      expect(_readersOf('glassBlurDisabled'), <String>[
        'lib/core/glass/glass.dart',
        'lib/core/theme/animated_background.dart',
      ]);
      expect(_readersOf('liquidRefractionEnabled'), <String>[
        'lib/core/glass/glass.dart',
      ]);
    });
  });
}
