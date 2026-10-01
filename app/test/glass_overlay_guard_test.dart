// app/test/glass_overlay_guard_test.dart
//
// 守门：**弹窗一律走统一入口**，`lib/` 里不许再出现裸的 `showDialog`。
//
// 为什么要守：这一轮把 21 处 `showDialog` 收敛到 `showGlassDialog`，为的是把两条时长与
// 那层「凝聚」拿到自己手里。**加新弹窗时只要有人图省事直接 `showDialog`，那个弹窗就会
// 静默地少掉凝聚、时长又回到 150ms** —— 从界面上完全看不出是漏了，只会觉得「这个弹窗
// 好像比别的生硬一点」。
//
// 规则跑在剥过壳的副本上（`support/source_scan.dart`）：否则在注释里提一句就打红 ——
// 本文件顶上这段注释里就有那些词。
//
// ⚠️ **第二条（自证）这一版是被自己抓出来的。** 第一版的自证写的是「不豁免时命中的恰好
// 是 `glass_dialog.dart`」—— 而那个文件**根本不调 `showDialog`**（入口走的是
// `Navigator.push` + 一条自定义 `PopupRoute`），于是匹配串在 `lib/` 里什么都匹配不到、
// 自证报 `Actual: []`。**要是没写这一条，第一条守门就是一句永远为真的空话。**
//
// 所以自证改成「拿一个**一定存在**的词当样本，证明扫描器真的读得到 `lib/` 里的真代码」
// —— 它同时钉住三件事：目录走查走进了 `lib/`、剥壳没把真代码当注释清掉、匹配真的能匹配。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

/// 允许出现裸 `showDialog` 的位置（前缀匹配）—— **只有定义处**（万一以后那里真的要调它）。
const List<String> _allowed = <String>[
  'lib/core/widgets/glass_dialog.dart',
];

/// 弹窗与弹层两族都要收。
///
/// ⚠️ **匹配串不能带左括号。** 第一版写的是 `showDialog(` —— 而真实的调用形态是
/// `showDialog<void>(`（泛型夹在中间），于是它**一个都匹配不到**、守门恒绿。
/// 那个错是**反向验证**抓出来的（把一处调用改回裸 `showDialog<void>(`，守门居然还是绿的）。
/// 去括号之后既能匹配带泛型的、也能匹配不带泛型的，而 `showGlassDialog` /
/// `showGlassSheet` 里都没有这两串，不会误伤。
const List<String> _needles = <String>['showDialog', 'showModalBottomSheet'];

/// 走一遍 `lib/`，返回**剥壳之后**仍出现 [needles] 里任何一个的文件路径（已排序）。
///
/// [needles] 不给就用生产那一份 —— 自证要用别的样本。
List<String> _hits({bool exempt = false, List<String>? needles}) {
  final List<String> words = needles ?? _needles;
  final List<String> hits = <String>[];
  for (final FileSystemEntity entity
      in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final String path = entity.path.replaceAll(r'\', '/');
    if (exempt && _allowed.any(path.startsWith)) continue;
    final String code = blankNonCode(entity.readAsStringSync());
    if (words.any(code.contains)) hits.add(path);
  }
  hits.sort();
  return hits;
}

void main() {
  test('lib/ 里没有裸的 showDialog（弹窗一律走 showGlassDialog）', () {
    final List<String> offenders = _hits(exempt: true);
    expect(
      offenders,
      isEmpty,
      reason: '这些文件直接用了裸的 showDialog，绕过了统一入口：\n'
          '  ${offenders.join('\n  ')}\n'
          '改成 `showGlassDialog`（`lib/core/widgets/glass_dialog.dart`）—— '
          '它会带上 300/200 两条时长与那层凝聚。',
    );
  });

  test('守门自证：扫描器读得到 lib/ 里的真代码', () {
    // 样本用 `Navigator.of(`（`glass_dialog.dart` 里一定有）。这一条要是红了，
    // 上面那条就只是一句永远为真的空话，而不是一条守门。
    // （第一版样本写的是 `Navigator.push` —— 那个文件里根本没有这串：
    // 它用的是 `Navigator.of(context, rootNavigator: true).push<T>(`。自证当场报红。）
    expect(
      _hits(needles: const <String>['Navigator.of(']),
      contains('lib/core/widgets/glass_dialog.dart'),
      reason: '扫描器什么都没扫到 —— 目录走查 / 剥壳 / 匹配三者里有一个坏了',
    );
  });

  test('守门自证：匹配串真的匹配得到**真实的调用形态**', () {
    // 光有「扫描器能扫到东西」还不够 —— 匹配串本身写歪了照样恒绿。
    // 第一版就是：写的是 `showDialog(`，而真实调用是 `showDialog<void>(`。
    for (final String sample in <String>[
      'showDialog(',
      'showDialog<void>(',
      'showDialog<bool>(',
      'await showDialog<_DeleteChoice>(',
      'showModalBottomSheet(',
      'showModalBottomSheet<int>(',
      'await showModalBottomSheet<DateTime>(',
    ]) {
      expect(_needles.any(sample.contains), isTrue,
          reason: '样本 `$sample` 匹配不到 —— 这种写法会从守门下面溜过去');
    }
    // 反过来：不许误伤统一入口（那两串在 `showGlassXxx` 里都不存在）。
    expect(_needles.any('showGlassDialog<void>('.contains), isFalse,
        reason: '匹配串误伤了弹窗入口 —— 全仓都会红');
    expect(_needles.any('showGlassSheet<void>('.contains), isFalse,
        reason: '匹配串误伤了弹层入口');
  });
}
