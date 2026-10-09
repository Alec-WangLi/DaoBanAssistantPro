// app/test/glow_layer_test.dart
//
// **护栏**：光晕背景每 340ms 走一步，而那一步**只该重绘光晕自己**。
//
// 改前：`CustomPaint(painter:, child: 整页)` —— 光晕是整页的**祖先**，于是它一动，
// 顶栏 / 42 格 / 信息卡连同压在光晕上面的每一层 `BackdropFilter` 全部跟着重绘。
// 实测那一帧「被画过的绘制节点」是 **139** 个，而安静帧是 0 —— 也就是每 340ms
// 一次固定掉帧。
//
// **反向验证过**：把结构改回 `CustomPaint(child: 整页)`，这条立刻红（139 > 8）。
//
// ⚠️ 它数的是 `PaintingContext.paintChild` 的调用（框架自带的 `debugOnProfilePaint`）
// —— **被合成的 `RepaintBoundary` 不计入**（那正是这一轮要达到的效果），所以门的
// 量级是「个位数」而不是「一百多」。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

Future<void> _pumpCalendar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 900);
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

  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: CalendarScreen()),
  ));
  await tester.pumpAndSettle();
}

/// 推一帧，数这一帧里 `PaintingContext.paintChild` 被调了几次。
Future<int> _paintedInOneFrame(WidgetTester tester, Duration step) async {
  var painted = 0;
  debugProfilePaintsEnabled = true;
  debugOnProfilePaint = (RenderObject child) => painted++;

  await tester.pump(step);

  // ⚠️ **必须在测试体里还原**：`addTearDown` 跑在框架的 `_verifyInvariants` **之后**，
  // 在那里还原会被报成「测试改了渲染调试变量」。
  debugOnProfilePaint = null;
  debugProfilePaintsEnabled = false;
  return painted;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    glassBlurDisabled.value = false;
    addTearDown(() => glassBlurDisabled.value = false);
  });

  testWidgets('光晕每一帧只重绘自己（不再牵动整页）', (tester) async {
    await _pumpCalendar(tester);

    // 安静帧：什么都没脏 —— 0 个绘制节点
    final int quiet = await _paintedInOneFrame(tester, const Duration(milliseconds: 16));
    expect(quiet, lessThanOrEqualTo(2), reason: '安静帧不该重绘任何东西；实测 $quiet');

    // 光晕那一步（`_tick` = durSlow = 340ms）
    final int glow = await _paintedInOneFrame(tester, const Duration(milliseconds: 340));
    expect(glow, lessThanOrEqualTo(8),
        reason: '光晕那一帧把整页都重绘了 —— 改前实测 139 个绘制节点'
            '（含信息卡那层 BackdropFilter 的重算）。实测本次：$glow');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });
}
