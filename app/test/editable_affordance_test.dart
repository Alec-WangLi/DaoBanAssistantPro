// app/test/editable_affordance_test.dart
//
// 「能改 / 能点的东西看起来得像能改 / 能点」的界面护栏。
//
// 这一版把全 app 的提示统一成三种语言：
//   · 有框的输入框 = 可以直接打字；
//   · 铅笔 = 点开进入「编辑这条内容」的表单；
//   · 箭头 = 点开打开别的东西（选择器 / 页面 / 说明或动作弹窗）。
//
// 本文件按页面分组，先收弹窗值行（Task 2），后续任务继续往里加。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/alarm/alarm_screen.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 有界推进若干帧（待办 / 闹钟页都有常驻定时器，不能 `pumpAndSettle`）。
Future<void> _settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

/// 把插件通道挂上空实现（没人接的通道调用永远不会完成，重排链路会卡住）。
void _stubPluginChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in const [
    'dexterous.com/flutter/local_notifications',
    'com.daoban.shiftassistantpro/settings',
  ]) {
    messenger.setMockMethodCallHandler(
        MethodChannel(channel), (call) async => null);
  }
}

Future<AppDatabase> _pump(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(420, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);
  _stubPluginChannels();

  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: home),
  ));
  await _settle(tester);
  return db;
}

Finder _chevronIn(String key) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byIcon(Icons.chevron_right_outlined));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() {
    L10n.locale = 'zh';
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('待办弹窗：日期 / 时间 / 提醒三行都有箭头', (tester) async {
    await _pump(tester, const ScheduleScreen());
    await tester.tap(find.byIcon(Icons.add_outlined));
    await _settle(tester);

    for (final key in const ['todo-date-row', 'todo-time-row', 'todo-remind-row']) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: '$key 不在');
      expect(_chevronIn(key), findsOneWidget, reason: '$key 没有箭头');
    }

    await _dispose(tester);
  });

  testWidgets('闹钟弹窗：时间行保留 18 号字、两行都有箭头', (tester) async {
    await _pump(tester, const AlarmScreen());
    await tester.tap(find.text(L10n.newAlarm));
    await _settle(tester);

    final timeRow = find.byKey(const Key('alarm-time-row'));
    expect(timeRow, findsOneWidget);
    final texts = tester.widgetList<Text>(
        find.descendant(of: timeRow, matching: find.byType(Text)));
    expect(
      texts.any((t) => t.style?.fontSize == AppTokens.sectionTitle.fontSize),
      isTrue,
      reason: '闹钟弹窗的时间是主角，必须保留 sectionTitle 那一档',
    );
    for (final key in const ['alarm-time-row', 'alarm-date-row']) {
      expect(_chevronIn(key), findsOneWidget, reason: '$key 没有箭头');
    }

    await _dispose(tester);
  });

  testWidgets('200×400：待办弹窗三行不溢出、箭头可见', (tester) async {
    await _pump(tester, const ScheduleScreen(), size: const Size(200, 400));
    await tester.tap(find.byIcon(Icons.add_outlined));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    for (final key in const ['todo-date-row', 'todo-time-row', 'todo-remind-row']) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: '$key 在小窗里不在');
      expect(_chevronIn(key), findsOneWidget, reason: '$key 在小窗里没有箭头');
    }

    await _dispose(tester);
  });
}
