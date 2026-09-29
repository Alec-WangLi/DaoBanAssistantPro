// app/test/glass_weekday_picker_test.dart
//
// 星期多选：待办弹窗（重复待办的「每周」）与闹钟弹窗（自定义闹钟的「每周」）
// 共用同一个控件。
//
// 抽出来之前它在 `alarm_screen.dart` 的弹窗里是内联的 —— 待办弹窗再抄一份就是
// 第二份实现，而这类「配方」一旦抄歪（缺一位、位序反了）**不会报错**：只是某个
// 星期永远选不上，或者选周三却存在周四。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_weekday_picker.dart';

void main() {
  setUp(() => L10n.locale = 'zh');

  testWidgets('点一下加一位，再点一下减一位；位序是「周一 = 1 << 0」',
      (tester) async {
    var value = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => GlassWeekdayPicker(
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    ));

    // 周三 = 3 = 1 << 2
    await tester.tap(find.text(L10n.weekday(2)));
    await tester.pumpAndSettle();
    expect(value, 1 << 2);

    // 再加周一 = 1 << 0
    await tester.tap(find.text(L10n.weekday(0)));
    await tester.pumpAndSettle();
    expect(value, (1 << 0) | (1 << 2));

    // 再点周三 → 去掉它
    await tester.tap(find.text(L10n.weekday(2)));
    await tester.pumpAndSettle();
    expect(value, 1 << 0);
  });

  testWidgets('七天都在，且顺序是周一到周日', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlassWeekdayPicker(value: 0, onChanged: (_) {}),
      ),
    ));
    for (var i = 0; i < 7; i++) {
      expect(find.text(L10n.weekday(i)), findsOneWidget);
    }
    final xs = [
      for (var i = 0; i < 7; i++)
        tester.getTopLeft(find.text(L10n.weekday(i))).dx,
    ];
    expect(xs, List.of(xs)..sort(), reason: '从左到右就是周一到周日');
  });

  testWidgets('选中态与未选中态用不同的字重（选中 w700）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlassWeekdayPicker(value: 1 << 2, onChanged: (_) {}),
      ),
    ));
    final selected = tester.widget<Text>(find.text(L10n.weekday(2)));
    final plain = tester.widget<Text>(find.text(L10n.weekday(1)));
    expect(selected.style?.fontWeight, FontWeight.w700);
    expect(plain.style?.fontWeight, FontWeight.w500);
  });
}
