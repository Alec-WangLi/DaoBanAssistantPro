// app/test/calendar_month_haptics_test.dart
//
// 翻月那一记触觉（2026-11-11 用户点名的 B 项）。
//
// 三个入口、一条判据：**月份真的变了才震一记 `select()`**。
//   - ‹ › 箭头：走 `_setMonth()`
//   - 「今天」：走 `_today()`，月份或选中日至少变一个才震
//   - 月份选择器：弹层里原来自己那记**已删**，改由 `_setMonth()` 补 ——
//     留着就是一次操作两响（选中 → 关弹层 → 再补一记）
//
// 负数用例（「已经停在今天就该静音」）同样重要：触觉一旦在「什么都没变」时也响，
// 它就退化成背景噪音，D6 那套语义也就白定了。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/clock.dart';
import 'package:shiftassistantpro/core/haptics.dart';
import 'package:shiftassistantpro/core/l10n.dart';

import 'support/calendar_test_support.dart';
import 'support/fixed_clock.dart';

/// 触觉原生通道名，与 `MainActivity.kt` 的 `hapticsChannel` 一致。
const MethodChannel _hapticsChannel =
    MethodChannel('com.daoban.shiftassistantpro/haptics');

void main() {
  useFixedNow();
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Object?> fired;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    fired = [];
    hapticsDisabled = false;
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(_hapticsChannel, (call) async {
      if (call.method == 'play') fired.add(call.arguments);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_hapticsChannel, null);
    hapticsDisabled = false;
  });

  testWidgets('‹ › 箭头：每真的翻一个月震一记', (tester) async {
    await pumpCalendar(tester, 'day_night_rest_rest');
    fired.clear();

    await tester.tap(find.byIcon(Icons.chevron_right_outlined).first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(fired, ['select'], reason: '下一月');

    await tester.tap(find.byIcon(Icons.chevron_left_outlined).first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(fired, ['select', 'select'], reason: '上一月');

    await disposeCalendar(tester);
  });

  testWidgets('「今天」：从别的月份跳回来震一记', (tester) async {
    await pumpCalendar(tester, 'day_night_rest_rest');
    await tester.tap(find.byIcon(Icons.chevron_right_outlined).first);
    await tester.pump(const Duration(milliseconds: 500));
    fired.clear();

    await tester.tap(find.byIcon(Icons.today_outlined).first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(fired, ['select'], reason: '跳回本月 = 选中变了，该有一记');

    await disposeCalendar(tester);
  });

  testWidgets('已经停在今天再点「今天」：一记都不该有', (tester) async {
    await pumpCalendar(tester, 'day_night_rest_rest');
    fired.clear();

    await tester.tap(find.byIcon(Icons.today_outlined).first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(fired, isEmpty, reason: '月份与选中日都没变，没携带任何信息');

    await disposeCalendar(tester);
  });

  testWidgets('月份选择器选另一月：只震一记（弹层自己不再补）', (tester) async {
    await pumpCalendar(tester, 'day_night_rest_rest');
    fired.clear();

    // 打开年月选择器：点标题那枚胶囊。
    //
    // ⚠️ 弹层是路由，动画要**先挂上再走**：单次 `pump(500ms)` 只推到动画起点，
    // 月份格还在屏幕下面（y≈1954 / 屏高 1600），点它会 warnIfMissed 而白点。
    // 所以先 `pump()` 一帧，再逐帧推完。
    await tester.tap(find.text(L10n.yearMonth(appNow())));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // 选另一个月（固定时钟是 10 月，这里点 11 月）。
    await tester.tap(find.text(L10n.monthShort(11)));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(fired, ['select'],
        reason: '选月份 → 关弹层 → _setMonth，整条路只该有一记');

    await disposeCalendar(tester);
  });
}
