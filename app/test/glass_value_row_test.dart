// app/test/glass_value_row_test.dart
//
// 共享值行 `GlassValueRow`（本版从排班管理页的私有实现里抽出来）的对外契约：
//   · 默认行尾一颗箭头（「点开会打开别的东西」），
//   · 点整行才触发 `onTap`（图标不是独立命中区），
//   · `trailing` 可以换成自己的尾部（例如「清空」钮），
//   · `valueStyle` 可以覆盖默认值字号（闹钟弹窗的 18 号时间用）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/widgets/glass_value_row.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  testWidgets('默认行尾箭头；点整行触发 onTap', (tester) async {
    var tapped = 0;
    await _pump(
      tester,
      GlassValueRow(
        label: '日期',
        value: '10月26日',
        onTap: () => tapped++,
      ),
    );

    expect(find.text('日期'), findsOneWidget);
    expect(find.text('10月26日'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_outlined), findsOneWidget);

    await tester.tap(find.byType(GlassValueRow));
    expect(tapped, 1);
  });

  testWidgets('trailing 覆盖默认箭头', (tester) async {
    await _pump(
      tester,
      GlassValueRow(
        label: '从',
        value: '10月1日',
        onTap: () {},
        trailing: const Icon(Icons.close),
      ),
    );

    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_outlined), findsNothing);
  });

  testWidgets('valueStyle 覆盖默认值字号', (tester) async {
    await _pump(
      tester,
      GlassValueRow(
        label: '时间',
        value: '08:30',
        onTap: () {},
        valueStyle: AppTokens.sectionTitle,
      ),
    );

    final text = tester.widget<Text>(find.text('08:30'));
    expect(text.style?.fontSize, AppTokens.sectionTitle.fontSize);
  });
}
