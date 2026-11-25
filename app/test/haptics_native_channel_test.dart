// app/test/haptics_native_channel_test.dart
//
// 触觉的原生通道契约：Android 上三档语义 → `play('select' | 'commit' | 'modeEnter')`。
//
// 钉的是**字符串**。`Haptics.kt` 按这三个值挑波形；哪天有人改了其中一处，
// 手机上不会崩、不会报错，只会「认不出这一档」而退回默认波形 —— 也就是这次
// 修掉的那种「转子嗡嗡」，界面上一点异常都看不出来。所以这条用例是必要的。
//
// 用例要显式把 `defaultTargetPlatform` 压成 Android：`core/haptics.dart` 按
// 平台分流（非 Android 走 Flutter 自带的三档），测试宿主是桌面，不压就永远
// 测不到通道那一条。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.daoban.shiftassistantpro/haptics');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> played;

  setUp(() {
    played = [];
    hapticsDisabled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'play') played.add(call.arguments as String);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    hapticsDisabled = false;
  });

  test('Android 上三档各发一次，参数与原生侧的约定一致', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    Haptics.select();
    Haptics.commit();
    Haptics.modeEnter();
    await pumpEventQueue();

    expect(played, ['select', 'commit', 'modeEnter']);
  });

  test('开关关掉时一条都不发（判定先于发送）', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    hapticsDisabled = true;

    Haptics.select();
    Haptics.commit();
    Haptics.modeEnter();
    await pumpEventQueue();

    expect(played, isEmpty);
  });

  test('非 Android 不走原生通道，回落 Flutter 自带三档', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    final platform = <Object?>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') platform.add(call.arguments);
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    Haptics.select();
    Haptics.commit();
    Haptics.modeEnter();
    await pumpEventQueue();

    expect(platform, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
    ]);
    expect(played, isEmpty, reason: '非 Android 不该碰原生通道');
  });
}
