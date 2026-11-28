// app/test/alarm_fade_in_test.dart
//
// 「渐响」开关的两件事：
//   1. **Dart 与 Kotlin 认同一个键**。Dart 存 `fadeInRingtone`，插件的
//      `shared_preferences` 会给它加 `flutter.` 前缀，原生侧必须读
//      `flutter.fadeInRingtone`。两边写歪一个的后果是**静默的** —— 开关拨了、
//      界面也变了，响铃还是原来的硬起播，编译和构建都看不出问题。
//      与 `ringtone_vibrate_only_test.dart` 第 1 条同一套路（Dart 与 Kotlin
//      之间没有共享常量的通道，只能扫源码）。
//   2. **开关真的落到设置里**，并且再点一次能关掉。开关只管「响铃」，
//      试听是另一条播放链路，不在这里断言。
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';
import 'package:shiftassistantpro/features/profile/profile_screen.dart';

Future<void> _pumpFrames(WidgetTester tester, {int frames = 24}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 与 `ringtone_vibrate_only_test.dart` 同一份插件桩：没人接的通道调用永远不会
/// 完成（权限卡在 `initState` 会去调一串原生方法）。
void _stubPluginChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in const [
    'dexterous.com/flutter/local_notifications',
    'com.daoban.shiftassistantpro/settings',
  ]) {
    messenger.setMockMethodCallHandler(
      MethodChannel(channel),
      (call) async =>
          call.method == 'listRingtones' ? <Map<String, Object?>>[] : null,
    );
    addTearDown(
        () => messenger.setMockMethodCallHandler(MethodChannel(channel), null));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _stubPluginChannels();
    L10n.locale = 'zh';
  });

  test('渐响的键在 Dart 与 Kotlin 两侧对得上（含 flutter. 前缀）', () {
    expect(AlarmService.fadeInRingtoneKey, 'fadeInRingtone',
        reason: 'Dart 侧写进 SharedPreferences 的键名');
    final kotlin = File(
            'android/app/src/main/kotlin/com/daoban/shiftassistantpro/AlarmSound.kt')
        .readAsStringSync();
    expect(kotlin.contains('"flutter.${AlarmService.fadeInRingtoneKey}"'), isTrue,
        reason: 'AlarmSound.kt 必须读 `"flutter.fadeInRingtone"` —— 插件的 '
            'shared_preferences 会给 Dart 的键加 flutter. 前缀；写成裸键名会永远读到 '
            'false，开关怎么拨都不渐响，而且不报错');
  });

  testWidgets('「渐响」开关默认关；点一下写入设置、再点一下关掉', (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await AppRepository(db).ensureSeeded();

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: ProfileScreen()),
    ));
    await _pumpFrames(tester);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool(AlarmService.fadeInRingtoneKey), isNull,
        reason: '前置：没设过就是关（默认不替所有人把第一声调小）');

    await tester.ensureVisible(find.text(L10n.fadeInRingtone));
    await _pumpFrames(tester, frames: 4);

    final switchFinder = find.descendant(
      of: find.widgetWithText(ListTile, L10n.fadeInRingtone),
      matching: find.byType(GlassSwitch),
    );
    expect(switchFinder, findsOneWidget,
        reason: '这一行是渐响唯一的入口，不能只写在更新日志里');

    await tester.tap(switchFinder);
    await _pumpFrames(tester);
    expect(sp.getBool(AlarmService.fadeInRingtoneKey), isTrue);

    await tester.tap(switchFinder);
    await _pumpFrames(tester);
    expect(sp.getBool(AlarmService.fadeInRingtoneKey), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });
}
