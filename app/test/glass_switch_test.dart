// 「不可用」的玻璃开关：置灰 + 点不动。
//
// 来由：低内存机器上「我的 → 外观 → 液态玻璃」那一行要置灰并说明原因
// （spec §1 的成功标准：**回落并说明原因、不静默无反应**）。开关若还能拨动，
// 用户得到的是一个「拨了没反应」的开关 —— 那比直接说不可用更糟。
//
// 这条行为是 v0.10.2 加的，但**一直没有用例看着它**：它当初长在液态档的分支里，
// 归属含混。v0.10.3 把液态档收拢到底栏时它被剥出来重打了一遍，顺手补上护栏。
//
// 两条用例是一对：**「开着能点」是「置灰点不动」的对照**。只有后者的话，
// 一个把 `onTap` 整个删掉的实现也能让它变绿。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';

Future<int> _tapAndCount(WidgetTester tester, {required bool enabled}) async {
  int calls = 0;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: GlassSwitch(
          value: false,
          enabled: enabled,
          onChanged: (bool _) => calls++,
        ),
      ),
    ),
  ));
  await tester.tap(find.byType(GlassSwitch));
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('开着的时候点得动', (tester) async {
    expect(await _tapAndCount(tester, enabled: true), 1,
        reason: '对照组：能点的话必须点得动，否则下面那条测的不是 enabled 而是「开关坏了」');
  });

  testWidgets('置灰之后点不动', (tester) async {
    expect(await _tapAndCount(tester, enabled: false), 0,
        reason: '置灰的开关还能拨 —— 用户会得到一个「拨了没反应」的开关');
  });
}
