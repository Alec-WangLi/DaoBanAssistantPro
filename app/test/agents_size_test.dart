// app/test/agents_size_test.dart
//
// AGENTS.md 的体积红线（≤ 35 KB）。
//
// 为什么要有这条：文件抬头自己就写着「目标体积 ≤35KB」，但从没人盯 —— 2026-11-08 之后
// 它一路从 37.5 KB 涨到 37.9 KB，中间没有任何东西红过。同一类「文档写了、没有守门」
// 的问题在 `docs/standards` §6 那张待补表里反复出现（10 条待补里 6 条是这一类）。
//
// 超了**不要**靠删两句话糊过去：事故复盘搬去 `docs/decisions/`，正文只留「每次开工要
// 照着做」的部分 —— v0.14.2 就是这么从 37.6 KB 收到 27.4 KB 的（发布链两大段进了
// `docs/decisions/release.md`）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AGENTS.md 不超过 35 KB', () {
    final File f = File('../AGENTS.md');
    expect(f.existsSync(), isTrue,
        reason: '找不到 ../AGENTS.md —— 这条用例假定工作目录是 app/');
    final int bytes = f.lengthSync();
    expect(bytes, lessThanOrEqualTo(35 * 1024),
        reason: 'AGENTS.md 现在 $bytes 字节（红线 ${35 * 1024}）—— '
            '新加的内容先想想是不是该进 docs/decisions/ 或 docs/changelog/；'
            '正文只放「每次开工都要知道」的东西。');
  });
}
