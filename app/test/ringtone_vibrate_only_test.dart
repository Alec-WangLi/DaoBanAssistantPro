// app/test/ringtone_vibrate_only_test.dart
//
// 「仅震动」这一档铃声的三件事：
//   1. **两边哨兵逐字一致** —— Dart 的 `AlarmService.vibrateOnlyRingtone` 与 Kotlin 的
//      `AlarmSound.VIBRATE_ONLY`。两边各持一份常量（Dart 与 Kotlin 之间没有共享常量的
//      通道），写歪一个的后果是**静默的**：设置里存了个原生不认识的值，`AlarmSound.start`
//      会走「自选铃声用不了 → 回落到内置铃声」那条路 —— 用户要静音，闹钟反而响了。
//      编译、构建、跑起来的界面都看不出问题，只有半夜那一声会告诉他。
//   2. 选择层里真有这一行，选了它把哨兵写进设置（而不是把键删掉 —— 删掉 = 退回内置）。
//   3. 选完之后「我的」页那一行的副标题跟着变（否则用户没法确认自己设成功没有）。
//
// 第 2、3 条都是**行为**，不是「有这段代码」；第 1 条是源码扫描，与
// `widget_fixed_cards_guard_test.dart` 同一套路（那边扫 Kotlin 里的槽位 id 拼法）。
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';
import 'package:shiftassistantpro/features/profile/profile_screen.dart';

/// 有界推进若干帧。
///
/// **不能用 `pumpAndSettle`**：`ProfileScreen` 里的权限卡在 `initState` 会去调一串
/// 原生插件方法，卡片一直停在无限旋转的加载态 —— 逐帧推进既不会挂、结果也确定
/// （同 `haptics_setting_test.dart`）。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 24}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 把插件通道挂上空实现。
///
/// **没人接的通道调用永远不会完成**（`alarm_screen_test.dart` 的 `_stubPluginChannels`
/// 记的是同一件事）。这一条对本文件是硬前提：`_showRingtonePicker` 在弹选择层**之前**
/// 会先 `await AlarmService.listRingtones()`，那个 Future 不完成，选择层就永远不弹 ——
/// 表现是「点了铃声这一行，什么都没发生」，而断言只会说「找不到那一行」，看不出原因。
///
/// `listRingtones` 给一个空列表（这一档不依赖系统铃声），其余一律 null：调用方都
/// 自带 try/catch，拿到 null 就按「没有实现」处理。
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
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _stubPluginChannels();
    L10n.locale = 'zh';
  });

  test('「仅震动」哨兵在 Dart 与 Kotlin 两侧逐字一致', () {
    final kotlin = File(
            'android/app/src/main/kotlin/com/daoban/shiftassistantpro/AlarmSound.kt')
        .readAsStringSync();
    final m = RegExp(r'VIBRATE_ONLY\s*=\s*"([^"]*)"').firstMatch(kotlin);
    expect(m, isNotNull,
        reason: 'AlarmSound.kt 里找不到 VIBRATE_ONLY 的字面量 —— 哨兵被改名或搬走了？');
    expect(m!.group(1), AlarmService.vibrateOnlyRingtone,
        reason: 'Dart 侧存进设置的值必须与 Kotlin 侧认的值逐字相同，'
            '否则用户选了静音、闹钟回落到内置铃声照响');
  });

  testWidgets('选择层里有「仅震动」；选了它，哨兵落到设置里、副标题跟着变',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
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

    // 前置：默认是内置铃声（那个键根本没存），副标题应当是内置那档。
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('ringtoneUri'), isNull, reason: '前置：没设过铃声');
    await tester.ensureVisible(find.text(L10n.ringtone));
    await _pumpFrames(tester, frames: 4);
    expect(find.text(L10n.builtinRingtone), findsOneWidget,
        reason: '副标题要显示当前生效的那一档，而不是一句固定的泛泛提示');

    // 打开选择层
    await tester.tap(find.text(L10n.ringtone));
    await _pumpFrames(tester);
    expect(find.text(L10n.vibrateOnlyRingtone), findsOneWidget,
        reason: '「仅震动」这一行是这一档功能唯一的入口');

    // 选它
    await tester.tap(find.text(L10n.vibrateOnlyRingtone));
    await _pumpFrames(tester);

    expect(sp.getString('ringtoneUri'), AlarmService.vibrateOnlyRingtone,
        reason: '**必须把哨兵写进这个键**。删掉这个键（像「内置铃声」那样）'
            '等于退回内置铃声 —— 用户要静音，闹钟照响');
    expect(sp.getString('ringtoneTitle'), isNull,
        reason: '这一档没有自选文件，残留的标题会让副标题显示成上一个铃声');
    expect(find.text(L10n.vibrateOnlyRingtone), findsOneWidget,
        reason: '选择层关掉之后，页面上那一处「仅震动」应当是**副标题** —— '
            '它变了才说明用户能确认自己设成功了');

    // 收尾：主动拆树，让 drift 取消查询流时排的那个零时长定时器跑掉。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });
}
