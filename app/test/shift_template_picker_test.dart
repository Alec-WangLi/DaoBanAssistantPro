// app/test/shift_template_picker_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';
import 'package:shiftassistantpro/features/calendar/shift_template_picker_screen.dart';

/// 从一个宿主页 push 选择页，并把 pop 的返回值收进 [results]。
Future<void> _openPicker(WidgetTester tester, List<Object?> results) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              results.add(await Navigator.of(context).push<ShiftTemplate>(
                MaterialPageRoute(
                    builder: (_) => const ShiftTemplatePickerScreen()),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  test('每个模板的 group 都在分组列表里，不会静默消失', () {
    // 选择页按 shiftTemplateGroups 分组渲染：group 字符串写错会让该模板
    // 从「选择你的倒班方式」页上无声消失。
    for (final t in shiftTemplates) {
      expect(shiftTemplateGroups, contains(t.group),
          reason: '模板 ${t.id} 的 group「${t.group}」不在分组列表里，会被静默丢弃');
    }
    for (final g in shiftTemplateGroups) {
      expect(shiftTemplates.any((t) => t.group == g), isTrue,
          reason: '分组「$g」没有任何模板，分组标题永远不会出现');
    }
  });

  testWidgets('首屏列出模板卡片', (tester) async {
    await _openPicker(tester, <Object?>[]);
    expect(find.text(L10n.pickShiftPattern), findsOneWidget);
    expect(find.text(shiftTemplates.first.title), findsOneWidget);
  });

  testWidgets('搜索「四班三倒」只剩匹配卡片', (tester) async {
    await _openPicker(tester, <Object?>[]);
    await tester.enterText(find.byType(TextField), '四班三倒');
    await tester.pumpAndSettle();

    final target = findTemplate('four_crew_three_shift')!;
    expect(find.text(target.title), findsOneWidget);
    // 不相关的卡片被过滤掉。
    expect(find.text(shiftTemplates.first.title), findsNothing);
    expect(find.text('DuPont · 28 天周期'), findsNothing);
    // 「我自己排」始终在。
    expect(find.text(L10n.customPattern), findsOneWidget);
  });

  testWidgets('搜不到时显示空状态，「我自己排」仍在', (tester) async {
    await _openPicker(tester, <Object?>[]);
    await tester.enterText(find.byType(TextField), 'zzzzzz');
    await tester.pumpAndSettle();
    expect(find.text(L10n.noPatternMatch), findsOneWidget);
    expect(find.text(L10n.customPattern), findsOneWidget);
  });

  testWidgets('点模板卡片返回该模板', (tester) async {
    final results = <Object?>[];
    await _openPicker(tester, results);
    await tester.tap(find.text(shiftTemplates.first.title));
    await tester.pumpAndSettle();
    expect(results.single, same(shiftTemplates.first));
  });

  testWidgets('点「我自己排」返回 null', (tester) async {
    final results = <Object?>[];
    await _openPicker(tester, results);
    // 先过滤，把「我自己排」卡片带进首屏。
    await tester.enterText(find.byType(TextField), 'zzzzzz');
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.customPattern));
    await tester.pumpAndSettle();
    expect(results.single, isNull);
  });
}
