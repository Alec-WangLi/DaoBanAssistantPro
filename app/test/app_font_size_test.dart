// app/test/app_font_size_test.dart
//
// **字号只由 App 自己决定。**
//
// 用户 2026-10-13 在真机上把系统字号拉到 200% 试过：小米只有部分系统应用跟随，
// 第三方 App 基本都不跟、各自给一个「字体大小」。本版照此办理 —— 根部那层
// `MediaQuery` 把平台报上来的 `textScaler` **整个换掉**，换成我们自己的四档。
//
// 下面第 2 条钉的就是这件事：**系统调到 2.0，App 的字号一点不变**。
// 那是有意的取舍（代价写在设计 §3），但必须是一条被断言钉住的取舍，
// 而不是「碰巧没测」。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/app.dart';
import 'package:shiftassistantpro/core/app_info.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';
import 'package:shiftassistantpro/state/app_settings.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../tool/visual/visual_harness.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{
    'language': 'zh',
    'onboarded': true, // 首启引导会盖住整屏
    'lastSeenVersion': appVersion, // 「版本更新」弹窗同理
  });
  stubPluginChannels();

  final db = AppDatabase.forTesting(
      NativeDatabase.opened(sqlite3.sqlite3.openInMemory()));
  addTearDown(db.close);

  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[databaseProvider.overrideWithValue(db)],
    child: const ShiftAssistantApp(),
  ));
  // 有界推进：主壳里一直有东西在调度下一帧，`pumpAndSettle` 会等到超时。
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 收尾：主动拆树，并推一下时钟让 drift 取消查询流时排的零时长定时器真的跑掉。
Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

AppSettingsNotifier _notifier(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HomeShell)),
            listen: false)
        .read(appSettingsProvider.notifier);

BuildContext _ctx(WidgetTester tester) =>
    tester.element(find.byType(HomeShell));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await ensureVisualFonts();
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() => L10n.locale = 'zh');
  tearDown(useStandardGlassTier);

  test('四档的倍率', () {
    expect(AppFontSize.small.scale, 0.9);
    expect(AppFontSize.standard.scale, 1.0);
    expect(AppFontSize.large.scale, 1.1);
    expect(AppFontSize.extraLarge.scale, 1.2);
  });

  testWidgets('拨「大」：根部的 textScaler 跟着变成 1.1', (tester) async {
    await _pumpApp(tester);
    expect(MediaQuery.textScalerOf(_ctx(tester)).scale(14), closeTo(14, 0.01),
        reason: '默认是「标准」');

    await _notifier(tester).setFontSize(AppFontSize.large);
    await tester.pump();
    expect(MediaQuery.textScalerOf(_ctx(tester)).scale(14),
        closeTo(14 * 1.1, 0.01));

    await _disposeApp(tester);
  });

  testWidgets('系统字号调到 2.0：App 的字号一点不变', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpApp(tester);
    expect(MediaQuery.textScalerOf(_ctx(tester)).scale(14), closeTo(14, 0.01),
        reason: '字号只由 App 自己的档位决定 —— 系统那一维已被有意挡在门外'
            '（设计 §3 的取舍，代价写在那里）');

    await _disposeApp(tester);
  });

  // ── 工装那一侧 ──
  //
  // 工装原来的 `textScale` 参数是**直接改平台字号**的。字号自管之后那条路成了
  // 空操作（根部会把它整个换掉）—— 留着就是一个骗后人的参数：给 `textScale: 1.8`
  // 渲出来的图与 1.0 逐像素相同。所以它必须改走 prefs 里的 `fontSize`。
  testWidgets('工装给「特大」：装出来就是我们那一档，平台字号随之作废', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    setUpVisualPrefs();

    final db = await makeVisualDatabase();
    addTearDown(db.close);
    await pumpScreen(
      tester,
      home: const CalendarScreen(),
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      size: const Size(360, 780),
      fontSize: AppFontSize.extraLarge,
    );
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(CalendarScreen)))
          .scale(14),
      closeTo(14 * 1.2, 0.01),
    );
    await teardownVisual(tester);
  });
}
