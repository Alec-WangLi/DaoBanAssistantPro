// app/test/alarm_ringing_haptics_test.dart
//
// 响铃页那两个出口的触觉（2026-11-11 用户点名的 C / D 项）。
//
// 「上滑关闭」与「再睡一会」是全 App 最重的两个动作，此前完全静音。两处都走
// `Haptics.commit()`（动作落实、不可逆），而且**只在该真的发生时响**：
// 上滑没过阈值松手 = 什么都没发生，一记都不该有。
//
// 夹具照抄 `alarm_ringing_liquid_test.dart`（同一屏，同一套原生通道桩）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/haptics.dart';
import 'package:shiftassistantpro/features/alarm/alarm_ringing_screen.dart';

import 'support/plugin_channels.dart';

/// 触觉原生通道名，与 `MainActivity.kt` 的 `hapticsChannel` 一致。
const MethodChannel _hapticsChannel =
    MethodChannel('com.daoban.shiftassistantpro/haptics');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Object?> fired;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    fired = [];
    hapticsDisabled = false;
    messenger.setMockMethodCallHandler(_hapticsChannel, (call) async {
      if (call.method == 'play') fired.add(call.arguments);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_hapticsChannel, null);
    hapticsDisabled = false;
  });

  /// 装配响铃页，并推到入场动画结束。
  Future<void> pumpRinging(WidgetTester tester) async {
    stubPluginChannels();
    tester.view.physicalSize = const Size(420, 900) * 2;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AlarmRingingScreen(label: '早班'),
    ));
    // 逐帧推：入场动画 650ms，推够 1.3 秒（与 liquid 用例同一口径）。
    for (int i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// 收尾：拆掉界面，把转场里排的帧放干净。
  Future<void> disposeRinging(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('上滑越过阈值关闭：震一记 commit', (tester) async {
    await pumpRinging(tester);
    fired.clear();

    // 手指从页面中部往上一把推 —— `_onBodyDragEnd` 的判据是
    // |dy| > 120 或速度 > 800，这里两样都过。
    await tester.dragFrom(
      tester.getCenter(find.byType(AlarmRingingScreen)),
      const Offset(0, -300),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(fired, ['commit'], reason: '关掉闹钟是动作落实，一记就够');
    await disposeRinging(tester);
  });

  testWidgets('上滑没过阈值就松手：一记都不该有', (tester) async {
    await pumpRinging(tester);
    fired.clear();

    // 慢拖 60px：位移没过 120、速度约 100px/s 也没过 800 —— 松手后界面弹回去，
    // 什么都没发生，所以不该响。触觉一旦在「无事发生」时也响，就成了噪音。
    await tester.timedDrag(
      find.byType(AlarmRingingScreen),
      const Offset(0, -60),
      const Duration(milliseconds: 600),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(fired, isEmpty, reason: '没过阈值 = 没关掉，不该震');
    await disposeRinging(tester);
  });

  testWidgets('点「再睡一会」：震一记 commit', (tester) async {
    await pumpRinging(tester);
    fired.clear();

    await tester.tap(find.byIcon(Icons.snooze_outlined));
    await tester.pump(const Duration(milliseconds: 50));

    expect(fired, ['commit'], reason: '贪睡也是一次不可逆的动作落实');
    await disposeRinging(tester);
  });
}
