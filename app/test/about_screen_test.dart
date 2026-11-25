// app/test/about_screen_test.dart
//
// 「关于」页的链接与署名。链接走原生 `openUrl`，这里挂空通道并记录调用，
// 断言地址取的是 `UpdateChecker` 那一份真源，而不是界面里另抄的字符串。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/update_checker.dart';
import 'package:shiftassistantpro/features/profile/about_screen.dart';

const _settingsChannel = MethodChannel('com.daoban.shiftassistantpro/settings');

void main() {
  setUp(() => L10n.locale = 'zh');

  testWidgets('关于页列出作者、许可与三个外链', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();

    expect(find.text(L10n.aboutDeveloperName), findsOneWidget);
    expect(find.text(L10n.aboutLicenseValue), findsOneWidget);
    expect(find.text(UpdateChecker.siteBase), findsOneWidget);

    // 仓库与 Issues 在首屏之下，滚过去再断言（ListView 是懒构建的）。
    await tester.scrollUntilVisible(find.text(L10n.aboutIssuesValue), 200);
    expect(find.text(UpdateChecker.repoUrl), findsOneWidget);
    expect(find.text(L10n.aboutIssuesValue), findsOneWidget);
  });

  testWidgets('点官网走 openUrl，地址取 siteBase', (tester) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_settingsChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(_settingsChannel, null));

    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('about-row-website')));
    await tester.pumpAndSettle();

    expect(calls, isNotEmpty);
    expect(calls.last.method, 'openUrl');
    expect((calls.last.arguments as Map)['url'], UpdateChecker.siteBase);
  });
}
