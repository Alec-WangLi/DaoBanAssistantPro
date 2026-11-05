// app/test/time_of_day_guard_test.dart
//
// 守门：**`app/lib` 里读「现在几点」只许经 `core/clock.dart` 的 `appNow()`**，
// 唯一豁免是响铃界面上那句「现在几点」。
//
// 背景（2026-11-06，批次 4）：`app/lib` 里有三处 `TimeOfDay.now()`。
//   - `features/alarm/alarm_screen.dart` 新建闹钟的默认钟点 —— **错**：它下面的
//     默认日期用的是 `dateOnly(appNow())`，两个时钟一旦不同步，默认落点就总在
//     「此刻」之后，`nextOnceDate` 的「已过 → 顺延一天」那一支永远走不到。
//     `alarm_screen_test.dart` 那条用例因此常年绿着，却什么都没验到（静默空转）。
//   - `features/schedule/recurring_fields.dart` 新建重复待办的时间选择器默认值 ——
//     同一个病：只是打开选择器、不落库，但真实时钟混进了一条本该与 `appNow()`
//     一体的流程，将来钉住时钟的用例在这条路径上照样空转。
//   - `features/alarm/alarm_ringing_screen.dart` 的 `ringClockText(TimeOfDay.now())`
//     —— **正确**：响铃界面显示的就是真实此刻，与排定逻辑无关，保留。
// 前两处已改成 `TimeOfDay.fromDateTime(appNow())`；这一条守的是它不会退回去 ——
// 退回去时「顺延」那条用例会先红，但只靠一条用例太窄：同一个病可以从别处冒出来。
//
// 与 `clock_guard_test.dart`（守 `DateTime.now`）同一套路，跑在剥过壳的副本上
// （`support/source_scan.dart` 的 `blankNonCode`）：注释里提到这个词不算数 ——
// 本文件顶上这段注释里就有四处。
//
// **三条断言**：
//   1. 除那一个豁免文件外，`lib/` 里没有一处 `TimeOfDay.now`；
//   2. **自证**：剥壳器真的会清掉注释里的这串、而代码里的留着 —— 否则扫错目录、
//      匹配串打错、剥壳过头都会让第 1 条恒绿而没人知道；
//   3. 豁免那处还在（响铃界面仍显示真实此刻）—— 有人顺手把它也改成 `appNow()`，
//      真机上响铃时显示的时间就会跟着用例的钉住值走，而第 1 条照样绿。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

/// 唯一允许读真实钟点的位置：响铃界面显示「现在几点」。
const String _allowed = 'lib/features/alarm/alarm_ringing_screen.dart';

/// 在**剥壳之后**的源码里找这个串。
const String _needle = 'TimeOfDay.now';

/// 走一遍 `lib/`，返回剥壳后仍含 [_needle] 的文件（已排序，失败信息确定）。
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
  test('lib/ 里除响铃界面那句「现在几点」之外没人读真实钟点', () {
    final result = _scan();
    expect(result.offenders, isEmpty,
        reason: '新建条目/选择器的默认时刻请用 '
            'TimeOfDay.fromDateTime(appNow()) —— 真实时钟混进来，'
            '钉住时钟的用例在那些路径上就是空转');
    // 扫到的文件数：lib/ 目前一百多个 dart 文件；少于 50 说明扫错了地方。
    expect(result.scanned, greaterThan(50),
        reason: '只扫到 ${result.scanned} 个文件，多半是扫错了目录');
  });

  test('自证：剥壳器清掉注释里的那串、留着代码里的', () {
    const inComment = '// 这里写 TimeOfDay.now() 是说明，不是代码';
    const inBlockComment = '/* TimeOfDay.now() */';
    const inCode = 'final now = TimeOfDay.now();';
    expect(blankNonCode(inComment).contains(_needle), isFalse);
    expect(blankNonCode(inBlockComment).contains(_needle), isFalse);
    expect(blankNonCode(inCode).contains(_needle), isTrue,
        reason: '剥壳过头会把真代码一起清掉 —— 那第 1 条就恒绿了');
  });

  test('豁免还在：响铃界面显示的仍是真实此刻', () {
    final src = blankNonCode(File(_allowed).readAsStringSync());
    expect(src.contains('ringClockText(TimeOfDay.now())'), isTrue,
        reason: '响铃那句是「现在几点」，语义就是真实此刻；改成 appNow() 的话，'
            '真机上响铃时显示的时间会跟着用例的钉住值走');
  });
}
