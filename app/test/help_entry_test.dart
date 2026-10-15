// app/test/help_entry_test.dart
//
// 帮助里那一条（图标 + 标题 + 正文）：**宽的那一档逐像素不变，窄的那一档换版式**。
//
// 2026-10-15 用户真机反馈的清单里那条「小窗下帮助弹窗被 38dp 图标吃掉三分之一
// 宽度、正文挤到没法读」（v0.9.5 就记下、一直留待拍板）。判据落在**几何**上：
// 并排时文字左边被顶到 entry.left + 50，改版之后回到 entry.left。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/widgets/app_icon.dart';
import 'package:shiftassistantpro/features/profile/help_entry.dart';

Future<void> _pump(WidgetTester tester, double width) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: const HelpEntry(
            icon: Icons.edit_calendar_outlined,
            title: '先把班排上',
            lines: ['「我的 → 排班管理」里新建一套，保存之后日历上就有了。'],
            bulleted: false,
          ),
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('宽的那一档：图标在左、文字在右（原来那套，不动）', (tester) async {
    await _pump(tester, 372);
    final icon = tester.getRect(find.byType(AppIcon));
    final title = tester.getRect(find.text('先把班排上'));
    final entry = tester.getRect(find.byType(HelpEntry));

    expect(title.left - entry.left, greaterThan(40),
        reason: '并排时文字要躲开图标那一列（38 + 12）');
    expect((icon.center.dy - title.center.dy).abs(), lessThan(24),
        reason: '同一行：图标与标题的垂直中心不该差出一行去');
  });

  testWidgets('窄的那一档：图标挪到标题上方，正文拿回整行宽度', (tester) async {
    // 200 宽的小窗里，「开始使用」那个弹窗的内宽就在这个量级。
    await _pump(tester, 112);
    final icon = tester.getRect(find.byType(AppIcon));
    final title = tester.getRect(find.text('先把班排上'));
    final entry = tester.getRect(find.byType(HelpEntry));

    expect(title.left, closeTo(entry.left, 0.5),
        reason: '改版之后标题从条目左缘起排 —— 左边那 50dp 的图标沟没了');
    expect(icon.bottom, lessThanOrEqualTo(title.top + 0.5),
        reason: '图标站自己那一行（在标题上方），不再是并排');
  });
}
