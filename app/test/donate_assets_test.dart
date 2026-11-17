// app/test/donate_assets_test.dart
//
// 打赏二维码是**用户提供的实际收款码**，不是占位图。缺图时 `Image.asset` 只会
// 在运行时显示兜底文案，用户扫不到码；所以这条用例把两张图钉在 CI 上 ——
// 空目录、被误删、换成 0 字节文件都会直接红。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/features/profile/donate_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('打赏二维码素材随包发布', () async {
    for (final path in const [
      'assets/donate/alipay.png',
      'assets/donate/wechat.png',
    ]) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(1024), reason: path);
    }
  });

  // 支付宝那一张是「图片 + 常量」两半拼起来的：图片给人扫，常量给 `alipays://`
  // 唤起用。**换码必须同时换**，只换图片不改常量，点「打开支付宝」唤起的就是那个
  // 已经作废的旧码（2026-11-17 作者把个人收款码换成经营码，就是这一次）。
  // 这条用例钉住常量本身：改它必须同时确认 `assets/donate/alipay.png` 解出来
  // 也是这串（解不开就去解，别照着旧值抄）。
  test('支付宝唤起链接与当前收款码一致', () {
    expect(alipayQrContent, 'https://qr.alipay.com/2m6133750jrvc86p0ktkh2d');
  });
}
