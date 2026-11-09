// app/test/clock_guard_test.dart
//
// 守门：**`app/lib` 里读系统时钟的地方只许有一处 —— `core/clock.dart` 自己。**
//
// 背景：2026-11-05 有 10 条用例红了，根因不是断言写错，而是**用例与界面各自
// 读了一遍真实时钟**：日历页在 5 处直接 `DateTime.now()`，测试也直接
// `DateTime.now()` 算期望值。两边都「对」，但只要真实月份换了形状（11 月没有
// 法定节假日、没有 31 号、还是 6 行月），期望值就整体漂走。
//
// 修法不是把那 10 条改绿，而是把「现在几点」变成**显式输入**：
//   - 生产：`appNow()` 默认就是 `DateTime.now`，行为逐字节不变；
//   - 用例：`test/support/fixed_clock.dart` 的 `useFixedNow()` 把它钉死，
//     `tearDown` 还原。
// 这一条守门守的是**这个决定不会退回去** —— 有人再手滑写 `DateTime.now()`，
// 这里先红，而不是等下一次换月才红 10 条。
//
// 跑在剥过壳的副本上（`support/source_scan.dart`）：注释里提到这个词不算数 ——
// 本文件顶上这段注释里就有三处。
//
// **三条断言**（与 `liquid_scope_guard_test.dart` / `haptics_guard_test.dart` 同一套路）：
//   1. 除 `core/clock.dart` 外，`lib/` 里没有一处 `DateTime.now`；
//   2. **自证**：剥壳器真的会把注释里的那串清掉、而代码里的留着 —— 否则扫错目录、
//      匹配串打错、剥壳过头都会让第 1 条恒绿而没人知道；
//   3. 接缝本身还在（`appNow` 仍是 `DateTime Function()`）—— 有人把接缝删了，
//      第 1 条照样绿（一个都不剩），但整个机制已经没了。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

/// 唯一允许读系统时钟的位置。
const String _allowed = 'lib/core/clock.dart';

/// 在**剥壳之后**的源码里找这个串。
const String _needle = 'DateTime.now';

/// 走一遍 `lib/`，返回剥壳后仍含 [_needle] 的文件（已排序，失败信息确定）。
///
/// 同时把「扫到几个文件」带出来：扫错工作目录时 `lib/` 不存在会直接抛，
/// 但扫到一个空目录则会**静默恒绿** —— 用文件数兜住。
({List<String> offenders, int scanned}) _scan() {
  final dir = Directory('lib');
  if (!dir.existsSync()) {
    fail('找不到 lib/ —— 用例必须在 app/ 下跑（flutter test 的 cwd 就是 app/）');
  }
  final offenders = <String>[];
  var scanned = 0;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    scanned++;
    final path = entity.path.replaceAll(r'\', '/');
    if (path == _allowed) continue;
    if (blankNonCode(entity.readAsStringSync()).contains(_needle)) {
      offenders.add(path);
    }
  }
  offenders.sort();
  return (offenders: offenders, scanned: scanned);
}

void main() {
  test('lib/ 里除 core/clock.dart 之外没人直接读系统时钟', () {
    final result = _scan();
    expect(result.offenders, isEmpty,
        reason: '请改用 core/clock.dart 的 appNow()（生产行为不变，用例才钉得住）');
    // 扫到的文件数：lib/ 目前一百多个 dart 文件；少于 50 说明扫错了地方。
    expect(result.scanned, greaterThan(50),
        reason: '只扫到 ${result.scanned} 个文件，多半是扫错了目录');
  });

  test('自证：剥壳器清掉注释里的那串、留着代码里的', () {
    const inComment = '// 这里写 DateTime.now() 是说明，不是代码';
    const inBlockComment = '/* DateTime.now() */';
    const inCode = 'final now = DateTime.now();';
    expect(blankNonCode(inComment).contains(_needle), isFalse);
    expect(blankNonCode(inBlockComment).contains(_needle), isFalse);
    expect(blankNonCode(inCode).contains(_needle), isTrue,
        reason: '剥壳过头会把真代码一起清掉 —— 那第 1 条就恒绿了');
  });

  test('接缝还在：core/clock.dart 的 appNow 仍是可替换的函数类型', () {
    final src = blankNonCode(File(_allowed).readAsStringSync());
    expect(src.contains('DateTime Function() appNow'), isTrue,
        reason: '接缝被删掉的话，第 1 条会「一个都不剩」地绿，但机制已经没了');
    expect(src.contains('DateTime.now'), isTrue,
        reason: '默认实现必须仍是系统时钟');
  });
}
