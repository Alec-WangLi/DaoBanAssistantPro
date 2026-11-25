// app/test/site_copy_test.dart
//
// 官网是一份手写静态页，发版时最容易漏的就是「更新日志」那一节。
// 这条护栏让 CI 直接红：app_info 的版本号必须出现在 site/index.html 里。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/app_info.dart';

void main() {
  test('官网更新日志包含当前版本', () {
    final File site = File('../site/index.html');
    expect(site.existsSync(), true, reason: '找不到 site/index.html');
    final String html = site.readAsStringSync();
    expect(
      html,
      contains('v$appVersion'),
      reason: '发版后忘了把 site/index.html 的「更新日志」补到当前版本',
    );
  });

  test('README 与产品规格包含当前版本', () {
    final String readme = File('../README.md').readAsStringSync();
    final String spec = File('../PRODUCT_SPEC.md').readAsStringSync();
    expect(readme, contains('v$appVersion'),
        reason: 'README 的版本 / 下载行忘了更新到当前版本');
    expect(spec, contains('v$appVersion'),
        reason: 'PRODUCT_SPEC 的抬头忘了更新到当前版本');
  });
}
