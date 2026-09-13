// app/test/app_info_test.dart
//
// `AGENTS.md` 写着「每轮改动收尾：`pubspec.yaml` 的 `version` 与
// `app_info.dart` 的 `appVersion` 同步」。这是句口头约定，掉了没人拦 ——
// v0.6.6 到 v0.6.9 连续四个版本就只涨了 pubspec，`appVersion` 一直停在
// 0.6.5，于是「我的」页显示的版本号是错的，「版本更新」弹窗也再也不弹
// （它比的是 `lastSeenVersion` 与 `appVersion`，两个都停在旧值）。
//
// 所以把这条约定变成一条会失败的用例：两处对不上，`flutter test` 直接红。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/app_info.dart';

void main() {
  test('pubspec.yaml 的 version 与 app_info 的 appVersion 一致', () {
    // 测试的工作目录是包根目录（app/）。
    final pubspec = File('pubspec.yaml');
    expect(pubspec.existsSync(), isTrue,
        reason: '读不到 pubspec.yaml —— 这条用例假定工作目录是 app/');

    final match = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$',
            multiLine: true)
        .firstMatch(pubspec.readAsStringSync());
    expect(match, isNotNull,
        reason: 'pubspec.yaml 里的 version 不是 X.Y.Z+build 的形式');

    final pubspecVersion = match!.group(1);
    final build = int.parse(match.group(2)!);

    expect(appVersion, pubspecVersion,
        reason: 'pubspec.yaml 是 $pubspecVersion，app_info.dart 是 $appVersion —— '
            '两处必须同步；否则「我的」页显示的版本号、升级后的更新弹窗、'
            '以及「检查更新」里的当前版本全是错的');
    expect(build, greaterThan(0),
        reason: 'versionCode 要跟着版本一起涨，不能是 0');
  });
}
