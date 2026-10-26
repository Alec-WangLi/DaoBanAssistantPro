// app/test/glass_value_row_test.dart
//
// 共享值行 `GlassValueRow`（本版从排班管理页的私有实现里抽出来）的对外契约：
//   · 默认行尾一颗箭头（「点开会打开别的东西」），
//   · 点整行才触发 `onTap`（图标不是独立命中区），
//   · `trailing` 可以换成自己的尾部（例如「清空」钮），
//   · `valueStyle` 可以覆盖默认值字号（闹钟弹窗的 18 号时间用）。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('箭头贴住内容右缘，值与箭头同一列', (tester) async {
    await _pump(
      tester,
      SizedBox(
        width: 320,
        child: GlassValueRow(label: '日期', value: '10月26日', onTap: () {}),
      ),
    );

    final rowRight = tester.getRect(find.byType(GlassValueRow)).right;
    final iconRight =
        tester.getRect(find.byIcon(Icons.chevron_right_outlined)).right;
    expect(rowRight - iconRight, lessThan(0.5),
        reason: '值行右侧不许留死区 —— 值与箭头要在同一列、贴着内容右缘');
  });

  testWidgets('200dp 宽：长标签折行而不是被硬裁', (tester) async {
    await _pump(
      tester,
      SizedBox(
        width: 128,
        child: GlassValueRow(
          label: '提前提醒（可选）',
          value: '提前30分钟',
          onTap: () {},
        ),
      ),
    );

    final label = tester.renderObject<RenderParagraph>(find.text('提前提醒（可选）'));
    expect(label.didExceedMaxLines, isFalse,
        reason: '标签被 maxLines 截掉了');
    expect(label.getMaxIntrinsicHeight(label.size.width),
        lessThanOrEqualTo(label.size.height + 2),
        reason: '容器把标签裁短了');
  });

  testWidgets('无障碍：这一行被读成按钮', (tester) async {
    await _pump(
      tester,
      GlassValueRow(label: '日期', value: '10月26日', onTap: () {}),
    );

    expect(
      tester.getSemantics(find.byType(GlassValueRow)),
      isSemantics(isButton: true, hasTapAction: true),
    );
  });
}
