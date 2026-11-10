// app/test/donate_sheet_test.dart
//
// 打赏弹层的金额与两个入口。二维码图片走真实 asset（pubspec 里已挂），
// 所以这里同时验证「图能加载、弹窗能出来」。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/features/profile/donate_sheet.dart';

const _settingsChannel = MethodChannel('com.daoban.shiftassistantpro/settings');

Future<void> _pumpSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: DonateSheet())),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => L10n.locale = 'zh');

  testWidgets('默认 ¥5，点微信弹出二维码并写当前金额', (tester) async {
    await _pumpSheet(tester);
    expect(find.text(L10n.donateAmountLabel(5)), findsOneWidget);

    await tester.tap(find.text(L10n.donateWechat));
    await tester.pumpAndSettle();

    expect(find.text(L10n.donateScanTitle), findsOneWidget);
    expect(find.text(L10n.donateAmountHint(5)), findsOneWidget);
  });

  testWidgets('自定义金额 88 会带到二维码弹窗', (tester) async {
    await _pumpSheet(tester);

    await tester.tap(find.text(L10n.donateCustom));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '88');
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();

    await tester.tap(find.text(L10n.donateWechat));
    await tester.pumpAndSettle();
    expect(find.text(L10n.donateAmountHint(88)), findsOneWidget);
  });

  testWidgets('自定义金额 0 留在弹窗里提示，不关窗', (tester) async {
    await _pumpSheet(tester);
    await tester.tap(find.text(L10n.donateCustom));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();

    expect(find.text(L10n.donateCustomInvalid), findsOneWidget);
    expect(find.text(L10n.donateCustomTitle), findsOneWidget);
  });

  testWidgets('支付宝走 alipays scheme，收款链接取自二维码内容', (tester) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_settingsChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(_settingsChannel, null));

    await _pumpSheet(tester);
    await tester.tap(find.text(L10n.donateAlipay));
    await tester.pumpAndSettle();

    expect(calls, isNotEmpty);
    expect(calls.last.method, 'openUrl');
    final url = (calls.last.arguments as Map)['url'] as String;
    expect(url, startsWith('alipays://platformapi/startapp?saId=10000007&qrcode='));
    expect(url, contains(Uri.encodeComponent(alipayQrContent)));
  });

  testWidgets('支付宝唤起失败时回落到二维码', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_settingsChannel, (call) async {
      if (call.method == 'openUrl') {
        throw PlatformException(code: 'OPEN_URL_FAILED');
      }
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(_settingsChannel, null));

    await _pumpSheet(tester);
    await tester.tap(find.text(L10n.donateAlipay));
    await tester.pumpAndSettle();

    expect(find.text(L10n.donateScanTitle), findsOneWidget);
    expect(find.text(L10n.donateAmountHint(5)), findsOneWidget);
  });
}
