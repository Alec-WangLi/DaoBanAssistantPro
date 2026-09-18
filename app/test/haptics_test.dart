// app/test/haptics_test.dart
//
// 触觉词汇表的两个行为：开关关掉时一处不动；开着时按档位发出对应的
// `HapticFeedbackType`。
//
// 三个档位全部走 `SystemChannels.platform` 的 `HapticFeedback.vibrate`，
// 只是参数字符串不同 —— 拦这一个方法就够断言全部三档，不必碰真振动器。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Object?> fired;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    fired = [];
    hapticsDisabled = false;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    // 标志是模块级的，漏还原会漏给下一个用例（本文件里就有个用例专门置真）。
    hapticsDisabled = false;
  });

  test('三档各自发出对应的 HapticFeedbackType', () async {
    Haptics.select();
    Haptics.commit();
    Haptics.modeEnter();
    await pumpEventQueue();
    expect(fired, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
    ]);
  });

  test('关掉之后一次都不发（一处生效，调用点不用自己查）', () async {
    hapticsDisabled = true;
    Haptics.select();
    Haptics.commit();
    Haptics.modeEnter();
    await pumpEventQueue();
    expect(fired, isEmpty);
  });

  test('词汇表完整性：三个名字都被本文件断言过', () {
    // 与 `design_tokens_test` 的「令牌自检」同一个理由：手写枚举的 expect 列表
    // 加漏一个，测试照样绿。这里按名字去源码里找。
    final lexicon = File('lib/core/haptics.dart').readAsStringSync();
    final self = File('test/haptics_test.dart').readAsStringSync();
    for (final name in ['select', 'commit', 'modeEnter']) {
      expect(lexicon, contains('static void $name('),
          reason: '词汇表里没有 $name —— 删档位的话本测试要跟着改');
      expect(self, contains('Haptics.$name()'),
          reason: '$name 没有任何断言覆盖到');
    }
  });
}
