// app/test/donate_assets_test.dart
//
// 打赏二维码是**用户提供的实际收款码**，不是占位图。缺图时 `Image.asset` 只会
// 在运行时显示兜底文案，用户扫不到码；所以这条用例把两张图钉在 CI 上 ——
// 空目录、被误删、换成 0 字节文件都会直接红。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
