// app/test/settings_select_test.dart
//
// **护栏**：`appSettingsProvider` 的消费者只许订阅**它自己真正渲染的那几项**。
//
// 改之前是 7 处全量 `ref.watch(appSettingsProvider)` —— 而 `app.dart` 根节点也在里面，
// 于是**拨一下触觉开关就把整个 App 重建一遍**。触觉开关不参与主题、不参与语言、
// 不影响任何渲染，那一整轮重建是白付的。
//
// 另一头同样要钉：**切语言必须还重建得起来** —— `select` 收窄最容易在这里漏一个
// 消费者，而它不会报错，只会「切了语言界面不动」。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/state/app_settings.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

Future<void> _pumpCalendar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  final ShiftTemplate t = shiftTemplates
      .firstWhere((ShiftTemplate x) => x.id == 'four_crew_three_shift');
  await AppRepository(db).saveSchedule(
    name: t.subtitle,
    anchorDate: dateOnly(DateTime.now()),
    classes: t.classes,
    cycle: t.cycle,
    makeCurrent: true,
    teamCount: t.teamCount,
    teamNames: L10n.defaultTeamNames(t.teamCount),
    ourTeamIndex: 0,
    teamOffsets: t.teamOffsets,
  );

  // ⚠️ **用受控的 `ProviderScope`，不要 `UncontrolledProviderScope`** ——
  // 后者不随树释放容器，于是容器订阅着的 drift 查询流一直开着、它取消时排的那个
  // 零时长定时器永远不跑。表现是**整条用例挂到测试超时**（第一次写就挂了两回，
  // 每次四分钟）。
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: CalendarScreen()),
  ));
  // 让 `AppSettingsNotifier._load()` 那一发异步读盘先落定 —— 否则它的 state 变更
  // 会被算进下面这次计数里。
  await tester.pumpAndSettle();
}

AppSettingsNotifier _notifier(WidgetTester tester) =>
    ProviderScope.containerOf(
            tester.element(find.byType(CalendarScreen)),
            listen: false)
        .read(appSettingsProvider.notifier);

/// 拨一次设置，数**日历页那个 element 重跑了几次 build**。
///
/// 用框架自带的 `debugOnRebuildDirtyWidget`：它数的是**真的重跑过 build 的那些**，
/// 比「树上有多少个 widget」有鉴别力。
Future<int> _calendarRebuilds(
  WidgetTester tester,
  Future<void> Function() act,
) async {
  var n = 0;
  debugOnRebuildDirtyWidget = (Element e, bool wasDirty) {
    if (e.widget is CalendarScreen) n++;
  };
  await act();
  await tester.pump();
  // ⚠️ **必须在测试体里还原**（`addTearDown` 跑在框架自检之后）。
  debugOnRebuildDirtyWidget = null;
  return n;
}

/// 收尾：主动拆掉界面，并推一下时钟让 drift 取消查询流时排的那个零时长定时器真的跑掉。
///
/// **要放在断言之前**：断言失败时若还挂着那个定时器，整条用例会挂到测试超时
/// （不是干脆地报错），排查起来极费时间。
Future<void> _disposeCalendar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('拨触觉开关：日历页不该重建', (WidgetTester tester) async {
    await _pumpCalendar(tester);
    final int n = await _calendarRebuilds(
        tester, () => _notifier(tester).setHapticsEnabled(false));
    await _disposeCalendar(tester);
    expect(n, 0, reason: '触觉开关不参与主题、不参与语言、不影响任何渲染 —— '
        '全量 watch 时它会把整页白重建一遍。实测重建 $n 次');
  });

  testWidgets('拨液态玻璃开关：日历页不该重建', (WidgetTester tester) async {
    await _pumpCalendar(tester);
    final int n = await _calendarRebuilds(
        tester, () => _notifier(tester).setLiquidGlass(true));
    await _disposeCalendar(tester);
    expect(n, 0,
        reason: '液态档靠模块级标志（`liquidGlassActive`）驱动重算，'
            '日历页不需要为它重建。实测重建 $n 次');
  });

  testWidgets('对照：切语言**必须**重建日历页', (WidgetTester tester) async {
    await _pumpCalendar(tester);
    final int n = await _calendarRebuilds(
        tester, () => _notifier(tester).setLanguage('en'));
    await _disposeCalendar(tester);
    expect(n, greaterThan(0),
        reason: 'select 收窄最容易漏掉这个消费者 —— 漏了不会报错，'
            '只会「切了语言界面不动」。实测重建 $n 次');
  });
}
