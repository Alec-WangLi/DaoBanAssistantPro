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
import 'package:shiftassistantpro/core/app_info.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/features/profile/app_dialogs.dart';

/// 每一段的版本头（`vX.Y.Z` 那一行）。
///
/// **不再把版本号写死在用例里**（v0.14.1 改）：原来这里钉的是 `v0.14.0` /
/// `v0.13.26` / `v0.13.19` 三个字符串，每发一版就要手改一次，忘改就红 ——
/// 而这个红说的是「用例过期了」，不是「代码坏了」。改成从 [appChangelog] 自己
/// 推导：用例守的是**折叠行为**，不是某几个具体版本。
List<String> _headLines(String changelog) => <String>[
      for (final String block in splitChangelogVersions(changelog))
        block.split('\n').first.trim(),
    ];

/// 弹窗正文里所有含版本头的 `Text`，拼成一段，便于断言「在 / 不在」。
String _visibleLog(WidgetTester tester) {
  final parts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((s) => RegExp(r'v\d+\.\d+\.\d+').hasMatch(s));
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
    expect(versions.first.startsWith('v$appVersion'), isTrue,
        reason: '首条必须是当前版本（app_info 的 appVersion）');
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

    final heads = _headLines(appChangelog);
    expect(heads, hasLength(10), reason: '更新日志窗口固定十条');

    final collapsed = _visibleLog(tester);
    for (final v in heads.take(kChangelogPreviewCount)) {
      expect(collapsed, contains(v), reason: '首屏该画出 $v');
    }
    expect(collapsed, isNot(contains(heads[kChangelogPreviewCount])),
        reason: '折叠态下第四版（${heads[kChangelogPreviewCount]}）就不该画出来 —— 画了等于没折叠');

    final more = find.text('展开更早的 ${heads.length - kChangelogPreviewCount} 版');
    expect(more, findsOneWidget, reason: '十条里先给三条，剩下七条要有个入口');

    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();

    final expanded = _visibleLog(tester);
    for (final v in heads) {
      expect(expanded, contains(v), reason: '展开后 $v 应当出现');
    }
    expect(find.text('收起'), findsOneWidget);
    expect(find.text('展开更早的 ${heads.length - kChangelogPreviewCount} 版'), findsNothing);
  });
}
