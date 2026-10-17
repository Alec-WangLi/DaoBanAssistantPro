// GlassSheetHeader —— 底部弹层统一头部（把手 + 主色竖条 + 标题 + 分隔线）。
//
// 抽出来的理由：五个弹层各自内联写头部，而且**都没有**弹窗那根主色竖条 ——
// 于是弹层标题读起来像内容列表的第一行。这一件把弹窗那份标题行
//（`GlassTitleRow`）搬进弹层，再补上弹层专属的把手与分隔线。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/widgets/glass_sheet_header.dart';

void main() {
  testWidgets('把手、标题、分隔线都在；标题走 titleStrong（不是弹窗那档 20）',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: GlassSheetHeader(title: '调整班次', subtitle: '10月13日'))));
    expect(find.text('调整班次'), findsOneWidget);
    expect(find.text('10月13日'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    final t = tester.widget<Text>(find.text('调整班次'));
    expect(t.style?.fontSize, AppTokens.titleStrong.fontSize,
        reason: '弹层标题比弹窗（dialogTitle 20）矮一档 —— 弹窗是居中的模态、'
            '弹层是贴底的抽屉');
  });

  testWidgets('副标题排在标题下面（调班那行日期区间不能被挤掉）', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: GlassSheetHeader(title: '调整班次', subtitle: '10月5日 – 10月7日 · 3 天'))));
    final t = tester.getRect(find.text('调整班次'));
    final s = tester.getRect(find.text('10月5日 – 10月7日 · 3 天'));
    expect(t.bottom, lessThanOrEqualTo(s.top));
  });
}
