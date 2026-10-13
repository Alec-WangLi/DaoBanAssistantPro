// app/test/status_bar_style_test.dart
//
// **护栏**：状态栏图标该深还是该浅，由 App 自己说了算，而且**跟着「主题模式」那一档走**。
//
// 起因（用户 2026-10-13 报的，荣耀 MagicOS 11）：浅色档下进「排班管理」，状态栏图标
// 反色成白的，退回来也不恢复；深色档正常。同一版在 HyperOS 4 上看不出来。
//
// **机制（一次性探针量出来的，不是推的）**：
//  · `MaterialApp` 每次 build 会**命令式**发一次 `SystemChrome.setSystemUIOverlayStyle`
//    （`material/app.dart` 的 `_themeBuilder`），值按主题深浅取 —— tab 那四页一直是对的，
//    这就是「进排班管理之前是好的」。
//  · `AppBar` 会往树上挂一层 `AnnotatedRegion<SystemUiOverlayStyle>`，值是**由 AppBar
//    的底色推出来的**；三个带 AppBar 的页面底色是 `Colors.transparent`（亮度 0）→ 被判成
//    「深色背景」→ 推出**白图标**。`RenderView._updateSystemChrome` 每合成一帧都拿「最上面
//    那一层声明」去**覆盖** `MaterialApp` 那一发 → 一进排班管理就变白。
//  · 退回来时那层声明随路由离开树，而 `_updateSystemChrome` **一份都没找到就直接早退**；
//    `MaterialApp` 那一发只在它自己 rebuild 时才发（pop 不会让它 rebuild）→ 白图标于是
//    留在屏幕上。**这就是「返回后也不恢复」。**
//
// 判据取在**真正发给系统的那条平台通道调用**上 —— 屏幕上那几个图标长什么样，只由这条
// 通道的最后一发决定；比「在树上找一个 `AnnotatedRegion`」有鉴别力（后者对「AppBar 那层
// 把根部那层盖住了」完全无感，而那正是这条 bug 的另一半）。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/app.dart';
import 'package:shiftassistantpro/core/app_info.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/alarm/alarm_ringing_screen.dart';
import 'package:shiftassistantpro/features/calendar/schedule_management_screen.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';
import 'package:shiftassistantpro/features/widget/widget_service.dart';
import 'package:shiftassistantpro/state/app_settings.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/plugin_channels.dart';

/// 捕获 `SystemChrome.setSystemUIOverlayStyle` **真正发出去**的那几份参数，按时间累积。
/// 列表里最后一份就是「此刻屏幕上生效的那一份」。
List<Map<Object?, Object?>> _captureStatusBar(WidgetTester tester) {
  final fired = <Map<Object?, Object?>>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
      fired.add(Map<Object?, Object?>.from(call.arguments as Map));
    }
    return null;
  });
  addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return fired;
}

/// 把 `SystemChrome` 记着的「上一发是什么」推到一个 **App 永远不会产出**的值上，再冲掉
/// 那一发。
///
/// 不这么做，同一个文件里第二条用例很可能**一发都收不到**：`setSystemUIOverlayStyle`
/// 对「与上一发完全相同」的样式会**静默丢掉**（`services/system_chrome.dart` 那句
/// `if (style == _latestStyle) return;`），而 `_latestStyle` 是个**静态**字段、跨用例
/// 不清。第一次写这个文件时第二条用例就报 `Actual: <null>` —— 断言成了句空话。
///
/// 哨兵发出去之后必须 `pump` 一次让那个 microtask 真的跑掉（它才落到 `_latestStyle`），
/// 所以这一发本身会被记进 `fired`，随后清掉。
Future<void> _primeStatusBarHistory(
    WidgetTester tester, List<Map<Object?, Object?>> fired) async {
  SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Color(0xFF010203)));
  await tester.pump();
  fired.clear();
}

/// 最后一发里的图标明度。**一发都没有时返回 null** —— 那本身也是一种答案：
/// 「这一刻没有任何东西声明过它」。
String? _icons(List<Map<Object?, Object?>> fired) => fired.isEmpty
    ? null
    : fired.last['statusBarIconBrightness'] as String?;

/// 有界推进若干帧。**不能用 `pumpAndSettle`**：主壳里一直有东西在调度下一帧
/// （背景光晕），它会一直等到超时（与 `home_shell_nav_test` 同一件事）。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 收尾：主动拆树，并推一下时钟让 drift 取消查询流时排的那个零时长定时器真的跑掉
/// （不这么做，框架会在测试体结束时报「A Timer is still pending」）。
Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

/// 装配**真正的根 Widget**（`ShiftAssistantApp`）—— 根部那层声明住在它的 `builder` 里，
/// 拿一个手搭的 `MaterialApp` 来测等于把被测代码抄进用例。
Future<void> _pumpApp(WidgetTester tester, AppThemeMode mode) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{
    'themeMode': mode.name,
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
  await _pumpFrames(tester);
}

/// push 一个整页出来（走根 Navigator，与真机路径一致）。
Future<void> _push(WidgetTester tester, Widget page) async {
  Navigator.of(tester.element(find.byType(HomeShell)))
      .push(MaterialPageRoute<void>(builder: (_) => page));
  await _pumpFrames(tester);
}

Future<void> _pop(WidgetTester tester, Type page) async {
  Navigator.of(tester.element(find.byType(page))).pop();
  await _pumpFrames(tester);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    L10n.locale = 'zh';
    // 快照去重的「上一份」是模块级状态，不清会漏给下一个用例。
    WidgetService.resetPushCache();
  });

  testWidgets('浅色档：进「排班管理」不会把状态栏变成白图标，退回来也还是深图标',
      (tester) async {
    final fired = _captureStatusBar(tester);
    await _primeStatusBarHistory(tester, fired);
    await _pumpApp(tester, AppThemeMode.light);

    expect(fired, isNotEmpty,
        reason: '这条通道什么都没发 ⟹ 这套断言问的不是屏幕上的图标（自证）');
    expect(_icons(fired), 'Brightness.dark', reason: '浅色档 = 深图标');

    await _push(tester, const ScheduleManagementScreen());
    expect(find.byType(AppBar), findsOneWidget);
    expect(_icons(fired), 'Brightness.dark',
        reason: '进排班管理不能把它翻成白图标 —— AppBar 的底色是 `Colors.transparent`，'
            'Flutter 据此判成「深色背景」；不给 `AppBarTheme` 补 systemOverlayStyle，'
            '它那一层就会盖住根部那一层');

    await _pop(tester, ScheduleManagementScreen);
    expect(_icons(fired), 'Brightness.dark',
        reason: '退回来必须还是深图标（用户报的「返回后也不恢复」）');

    await _disposeApp(tester);
  });

  testWidgets('深色档：一直是白图标（那条路径本来就是对的）', (tester) async {
    final fired = _captureStatusBar(tester);
    await _primeStatusBarHistory(tester, fired);
    await _pumpApp(tester, AppThemeMode.dark);

    expect(_icons(fired), 'Brightness.light');

    await _push(tester, const ScheduleManagementScreen());
    expect(_icons(fired), 'Brightness.light');

    await _pop(tester, ScheduleManagementScreen);
    expect(_icons(fired), 'Brightness.light');

    await _disposeApp(tester);
  });

  testWidgets('跟随系统档：跟着系统的深浅走', (tester) async {
    final fired = _captureStatusBar(tester);
    await _primeStatusBarHistory(tester, fired);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await _pumpApp(tester, AppThemeMode.system);
    expect(_icons(fired), 'Brightness.light', reason: '系统是深色 ⇒ 白图标');

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await _pumpFrames(tester);
    expect(_icons(fired), 'Brightness.dark', reason: '系统翻成浅色 ⇒ 深图标');

    await _disposeApp(tester);
  });

  // 响铃页是**恒深**的（`backgroundColor: AppTokens.bgDark`、内部 `isDark: true` 写死），
  // 而图标按**主题档**发 —— 浅色档下它会拿到一排深图标压在自己的深色底上。
  //
  // 这条同时是**根部那一层**的唯一鉴别力所在：把响铃页那层声明 pop 掉之后，必须有人
  // 把深图标顶回来。只补 `AppBarTheme.systemOverlayStyle`（不挂根部那层）的话，
  // 排班管理那条会因为「AppBar 声明的值与根部相同」而照样绿，这一条才会红。
  testWidgets('响铃页恒深：进去白图标，退回来又恢复成深图标', (tester) async {
    final fired = _captureStatusBar(tester);
    await _primeStatusBarHistory(tester, fired);
    await _pumpApp(tester, AppThemeMode.light);
    expect(_icons(fired), 'Brightness.dark');

    await _push(tester, const AlarmRingingScreen(label: '早班'));
    expect(_icons(fired), 'Brightness.light',
        reason: '响铃页是恒深的，深图标在它上面看不见');

    await _pop(tester, AlarmRingingScreen);
    expect(_icons(fired), 'Brightness.dark',
        reason: '它离开之后必须有人把深图标顶回来 —— 这一页自己声明了一层，'
            '而「离开即恢复」只能靠根部那一层');

    await _disposeApp(tester);
  });
}
