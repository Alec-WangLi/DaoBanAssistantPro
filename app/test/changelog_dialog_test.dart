// app/test/changelog_dialog_test.dart
//
// 「版本更新」弹窗的**折叠**：首屏只画最近 kChangelogPreviewCount 版，
// 更早的收在「展开更早的 N 版」那颗胶囊后面。
//
// 为什么要有这条：2026-11-25 一位用户反馈，反复开关这个弹窗三四次之后，
// 弹窗里的字变成错位的碎片、接着整页上下翻转（重启恢复）。查下来是字形图集
// 被压满后采样错位 —— 只有老机型的驱动上会犯，我们自己的机子跑十轮复现不出来。
// 首屏从十条压到三版，是把这一次的字形量砍掉七成，属于**缓解**；
// 而「缓解」最怕的是后人一句「这层折叠没用，删了吧」就把它撤销，
// 所以这里把三件事钉住：
//   1. 切分函数按 `vX.Y.Z` 行切，条数等于更新日志的窗口条数；
//   2. 首屏只出现前三版，第四版必须在折叠状态里看不见；
//   3. 点开之后十条全在，并且胶囊变成「收起」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/features/profile/app_dialogs.dart';

/// 弹窗正文里所有含版本头的 `Text`，拼成一段，便于断言「在 / 不在」。
String _visibleLog(WidgetTester tester) {
  final parts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((s) => s.contains('v0.1'));
  return parts.join('\n');
}

/// 打开「版本更新」弹窗的壳。
Widget _host() => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showChangelogDialog(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

void main() {
  setUp(() => L10n.locale = 'zh');

  test('切分：条数等于窗口条数，首条是当前版本', () {
    final versions = splitChangelogVersions(appChangelog);
    expect(versions.length, 10, reason: '更新日志窗口固定十条，切分不能多也不能少');
    expect(versions.first.startsWith('v0.14.0'), isTrue);
    // 每一条都必须正好以一条版本头开头，且不含下一条的头。
    for (final block in versions) {
      expect(RegExp(r'^v\d+\.\d+\.\d+\n').hasMatch(block), isTrue,
          reason: '这一段没有从版本头开始：\n$block');
      expect(RegExp(r'\nv\d+\.\d+\.\d+\n').hasMatch(block), isFalse,
          reason: '这一段里混进了别的版本头：\n$block');
    }
  });

  testWidgets('首屏只给前三版，点「展开更早的」之后十条全在', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final collapsed = _visibleLog(tester);
    expect(collapsed, contains('v0.14.0'));
    expect(collapsed, contains('v0.13.27'));
    expect(collapsed, contains('v0.13.26'));
    expect(collapsed, isNot(contains('v0.13.25')),
        reason: '折叠态下第四版就不该画出来 —— 画了等于没折叠');

    final more = find.text('展开更早的 7 版');
    expect(more, findsOneWidget, reason: '十条里先给三条，剩下七条要有个入口');

    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();

    final expanded = _visibleLog(tester);
    for (final v in ['v0.14.0', 'v0.13.22', 'v0.13.19']) {
      expect(expanded, contains(v), reason: '展开后 $v 应当出现');
    }
    expect(find.text('收起'), findsOneWidget);
    expect(find.text('展开更早的 7 版'), findsNothing);
  });
}
