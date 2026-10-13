// app/test/help_faq_screen_test.dart
//
// 第二层《遇到问题怎么解决》。
//
// 这一屏的风险不在逻辑，在**长文案**：答案句子比现在帮助里任何一句都长，
// 窄屏 + 大字号下会被吃掉；英文又普遍比中文长。所以除了「两组在不在」，
// 还钉了三条版式与语言的。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/features/profile/help_content.dart';
import 'package:shiftassistantpro/features/profile/help_faq_screen.dart';

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(420, 2400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: const HelpFaqScreen(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

HelpFaqItem get _first => helpFaqGroups.first.sections.first.items.first;

void main() {
  testWidgets('两组标题都在，第一条问题的原文在页面上', (tester) async {
    L10n.locale = 'zh';
    await _pump(tester);
    expect(find.text(helpFaqGroups.first.title.zh), findsOneWidget);
    expect(find.text(_first.question.zh), findsOneWidget);

    // 第二组在二十多条之后，而 `ListView` **只挂载视口里的元素** ——
    // 不滚过去 `find.text` 就是找不到。滚过去再断言，顺带证明它真的在页面上
    // （而不只是「常量里有」）。
    await tester.scrollUntilVisible(find.text(helpFaqGroups[1].title.zh), 400);
    expect(find.text(helpFaqGroups[1].title.zh), findsOneWidget);
  });

  testWidgets('切到英文之后整页是英文（不许漏一条中文）', (tester) async {
    L10n.locale = 'zh';
    addTearDown(() => L10n.locale = 'zh');
    await _pump(tester);
    expect(find.text(helpFaqGroups.first.title.zh), findsOneWidget);

    // 中间隔一棵别的树：`const HelpFaqScreen()` 是同一个实例，直接重 pump
    // 有可能整棵子树被当成没变、跳过重建 —— 那样这条用例就变成空话了。
    await tester.pumpWidget(const SizedBox());
    L10n.locale = 'en';
    await _pump(tester);

    expect(find.text(helpFaqGroups.first.title.en), findsOneWidget);
    expect(find.text(_first.question.en), findsOneWidget);
    expect(find.text(helpFaqGroups.first.title.zh), findsNothing);
    expect(find.text(_first.question.zh), findsNothing);
  });

  testWidgets('小窗（200×400）下不溢出，第一条问题仍然完整可见', (tester) async {
    L10n.locale = 'zh';
    await _pump(tester, size: const Size(200, 400));
    expect(tester.takeException(), isNull);
    expect(find.text(_first.question.zh), findsOneWidget);
  });

  testWidgets('特大字号（1.2）下不溢出，第一条问题仍然完整可见', (tester) async {
    L10n.locale = 'zh';
    // 1.2 是 App 自己那一档字号里最大的一档（`AppFontSize`）。
    await _pump(tester, textScale: 1.2);
    expect(tester.takeException(), isNull);
    expect(find.text(_first.question.zh), findsOneWidget);
  });

  testWidgets('英文折行之后，问题与答案还是上下分开的两行', (tester) async {
    L10n.locale = 'en';
    addTearDown(() => L10n.locale = 'zh');
    await _pump(tester, size: const Size(320, 2400));
    final q = tester.getRect(find.text(_first.question.en));
    final a = tester.getRect(find.text(_first.answer.en));
    expect(q.bottom, lessThanOrEqualTo(a.top),
        reason: '问题那行必须整个排在答案上面 —— 挤成一行就读不出哪句是问题了');
  });
}
