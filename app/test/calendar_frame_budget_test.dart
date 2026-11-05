// app/test/calendar_frame_budget_test.dart
//
// **护栏**：液态档在那枚块动起来的时候，**一帧重建的 widget 数**必须小。
//
// 为什么要有这条：那枚块的位置原来住在整页的 `State` 里，于是「点日期飞过去 /
// 按住拖 / 长按拖选」这三种交互**全程每帧重建整页**（顶栏 + 42 格 + 信息卡）——
// 实测 **436** 个 widget/帧，而标准档同一个动作只有 **6** 个。
//
// **反向验证过**：把那几个值塞回 `State`、把每帧 `setState` 放回去，这条立刻红
// （436 > 80）。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/clock.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'support/fixed_clock.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 一帧里重建了多少个 element。
///
/// 用框架自带的 `debugOnRebuildDirtyWidget`（`Element.rebuild()` 里逐个回调）——
/// 它数的是**真的重跑过 build 的那些**，比「树上有多少个 widget」有鉴别力得多。
Future<int> _rebuildsInOneFrame(
  WidgetTester tester, {
  required Future<void> Function() act,
}) async {
  var n = 0;
  var on = false;
  debugOnRebuildDirtyWidget = (Element e, bool wasDirty) {
    if (on) n++;
  };

  await act();
  await tester.pump(); // 处理这一下交互本身
  on = true;
  await tester.pump(const Duration(milliseconds: 16)); // 动画里的一帧

  // ⚠️ **必须在测试体里还原**（`addTearDown` 跑在框架的自检之后 —— 与
  // `glow_layer_test.dart` 同一条）。
  debugOnRebuildDirtyWidget = null;
  return n;
}

Future<void> _pumpCalendar(WidgetTester tester, {required bool liquid}) async {
  // ⚠️ **液态档必须走 prefs**：`appSettingsProvider._load()` 会拿 prefs 去
  // `recomputeGlassTiers()`，先设模块标志会被它覆盖回去（v0.10.1 / v0.10.13 各踩过一次）。
  if (liquid) {
    SharedPreferences.setMockInitialValues(<String, Object>{'liquidGlass': true});
  }
  liquidGlassActive.value = liquid;
  addTearDown(() => liquidGlassActive.value = false);

  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  final ShiftTemplate t =
      shiftTemplates.firstWhere((ShiftTemplate x) => x.id == 'four_crew_three_shift');
  await AppRepository(db).saveSchedule(
    name: t.subtitle,
    anchorDate: dateOnly(kAnchor),
    classes: t.classes,
    cycle: t.cycle,
    makeCurrent: true,
    teamCount: t.teamCount,
    teamNames: L10n.defaultTeamNames(t.teamCount),
    ourTeamIndex: 0,
    teamOffsets: t.teamOffsets,
  );

  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: CalendarScreen()),
  ));
  await tester.pumpAndSettle();
}

/// 收尾：主动拆掉界面，并推一下时钟让 drift 取消查询流时排的那个零时长定时器真的跑掉。
///
/// 不这么做，框架会在测试体结束时抛「A Timer is still pending even after the widget
/// tree was disposed」—— 表现是这条用例**挂到超时**才失败（`calendar_screen_test.dart`
/// 的 `_disposeCalendar` 是同一件事）。
Future<void> _disposeCalendar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

/// 点一个**离今天够远**的日子 —— 那会起一次滑行（每帧都在动），正是要量的场景。
///
/// 「今天」取 `appNow()`，**不取真实时钟**：原来这里读 `DateTime.now().day`，
/// 而网格画的是夹具锚点那个月。真实今天是 **8 号或 22 号**时，`±7` 正好落在
/// 锚点的今天（15 号）上 —— 那一击点的是那枚块**当前所在**的格子，滑行根本没起，
/// 「重建数 ≤ 80」于是静默变成空转（每月 2 天，约 6.5%）。
/// 所以另外配一条前置断言（[_assertFarFromToday]），把这件事钉死。
Finder _farDay() =>
    find.byKey(ValueKey<String>('day-card-${_farDayNumber()}'));

int _farDayNumber() {
  final int today = appNow().day;
  return today > 15 ? today - 7 : today + 7;
}

/// 前置：要点的那一格必须真的离今天远 —— 否则这条在测「原地不动」。
void _assertFarFromToday() {
  final int far = _farDayNumber();
  expect((far - appNow().day).abs(), greaterThanOrEqualTo(5),
      reason: '要点的那天（$far 号）离今天（${appNow().day} 号）太近：'
          '滑行不会起，「重建数」这条就变成空转了');
}

void main() {
  useFixedNow();
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('液态档：点日期起滑行时，一帧重建的 widget 数 ≤ 80', (tester) async {
    await _pumpCalendar(tester, liquid: true);
    _assertFarFromToday();
    final int n = await _rebuildsInOneFrame(tester,
        act: () => tester.tap(_farDay()));
    expect(n, lessThanOrEqualTo(80),
        reason: '改前实测 436 个 widget/帧（标准档同场景 6 个）—— 那枚块的位置'
            '不该由整页重建来驱动。实测本次：$n');
    await _disposeCalendar(tester);
  });

  testWidgets('液态档：长按拖选一段日子时，一帧重建的 widget 数 ≤ 80', (tester) async {
    // ⚠️ 这一条是独立审查抓出来的缺口：上面那条只测「点日期起滑行」，而**用户真正
    // 觉得卡的是拖选** —— 带子每帧把「末端淌到哪儿」回调给父层，父层每帧 `setState`
    // 就把整页重建了一遍（实测 509 个 widget/帧，比滑行那 42 个还多）。
    await _pumpCalendar(tester, liquid: true);

    final TestGesture g =
        await tester.startGesture(tester.getCenter(find.byKey(const ValueKey<String>('day-card-8'))));
    await tester.pump(const Duration(milliseconds: 600)); // 过长按判定，进入多选态
    await g.moveBy(const Offset(0, 60)); // 往下拖一行，带子开始淌
    await tester.pump();

    var n = 0;
    var on = false;
    debugOnRebuildDirtyWidget = (Element e, bool wasDirty) {
      if (on) n++;
    };
    on = true;
    await tester.pump(const Duration(milliseconds: 16)); // 带子还在动的一帧
    on = false;
    debugOnRebuildDirtyWidget = null;

    expect(n, lessThanOrEqualTo(80),
        reason: '拖选时整页还在每帧重建 —— 带子的末端位置不该由 `setState` 驱动。'
            '实测本次：$n');
    await g.up();
    await tester.pumpAndSettle();
    await _disposeCalendar(tester);
  });

  testWidgets('对照：标准档同一个动作仍然只有个位数', (tester) async {
    // 标准档那棵树一个字没动（`AnimatedPositioned` 自己走），所以它本来就该小。
    await _pumpCalendar(tester, liquid: false);
    _assertFarFromToday();
    final int n = await _rebuildsInOneFrame(tester,
        act: () => tester.tap(_farDay()));
    expect(n, lessThanOrEqualTo(20), reason: '标准档那棵树不该被这一轮碰到；实测：$n');
    await _disposeCalendar(tester);
  });
}
