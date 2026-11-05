// app/test/widget_push_retry_test.dart
//
// 小组件快照推失败之后的**自动重推**：3 秒一次、最多 2 次，用尽提示一次。
//
// 为什么要有这一组：这条机制是修「桌面卡片停在降级态」的核心 —— 2026-11-05
// 用户那台 MIUI13 上卡片一直是白块，而 `push` 失败只写了一条 `logInfo`，之后
// **再没有人管**（回前台才重推一次，可用户不一定再回前台）。独立审查指出：
// 把 `_scheduleWidgetRetry` 那两处调用删掉、或把上限改成 0，1217 条照样全绿
// —— 这一轮真正要修的东西，一条用例都没守着。
//
// 这里钉四件事：
//   ① 失败之后**确实又发了一次**（不是只发一次就完）；
//   ② 间隔是 3 秒（不是下一帧、也不是 30 秒）；
//   ③ 首发 + 2 次重试 = **总共 3 发**，之后不再发（上限真的是 2）；
//   ④ 用尽时提示条**只弹一次**（`_warnWidgetSyncOnce` 的每进程一次）。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/app_info.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';
import 'package:shiftassistantpro/features/widget/widget_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const MethodChannel _channel =
    MethodChannel('com.daoban.shiftassistantpro/settings');

/// 拆树并推一下时钟，让 drift 取消查询流时排的零时长定时器真的跑掉
/// （否则报「A Timer is still pending even after the widget tree was disposed」）。
Future<void> _disposeShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    L10n.locale = 'zh';
    WidgetService.resetPushCache();
    SharedPreferences.setMockInitialValues({
      'onboarded': true,
      'lastSeenVersion': appVersion,
    });
  });

  testWidgets('推失败：3 秒后重推，最多 2 次，用尽只提示一次', (tester) async {
    // 每一次 `widgetPushSnapshot` 都失败：这是「快照压根没落到桌面上」那条路
    // （`WidgetRenderer` 于是只能一直画降级布局）。
    var pushes = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method != 'widgetPushSnapshot') return null;
      pushes++;
      throw PlatformException(code: 'boom');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(
        NativeDatabase.opened(sqlite3.sqlite3.openInMemory()));
    addTearDown(database.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: HomeShell()),
    ));

    // 逐帧推进（**不能用 `pumpAndSettle`**：主壳里的背景光晕一直调度下一帧），
    // 每次推送发生的时刻按「挂树后经过的毫秒」记下来。
    var elapsedMs = 0;
    final atMs = <int>[];
    Future<void> advance(int totalMs) async {
      final end = elapsedMs + totalMs;
      while (elapsedMs < end) {
        final before = pushes;
        await tester.pump(const Duration(milliseconds: 40));
        elapsedMs += 40;
        if (pushes > before) atMs.add(elapsedMs);
      }
    }

    // 启动阶段：首帧那几次触发被 340ms 尾去抖合并成第一发（`AppTokens.durSlow`）。
    await advance(1200);
    final afterStartup = pushes;

    // 再推 7 秒：够跑完两次重试（+3s、+6s），第 9 秒之后不该再有。
    await advance(7000);

    // ① 失败之后确实又发了 —— 不是「发一次就没人管」。
    expect(pushes, greaterThan(afterStartup),
        reason: '首推失败后必须自动重推；一条都没有 = 桌面会一直停在降级布局');

    // ② 首发 + 2 次重试 = 3 发，之后不再发。
    expect(pushes, 3, reason: '上限是 2 次重试（首发 + 2），不是无限重推也不是只推一次');

    // ③ 间隔 3 秒：相邻两发之间的差应落在 (2.8s, 3.2s) 里。
    for (var i = 1; i < atMs.length; i++) {
      final gap = atMs[i] - atMs[i - 1];
      expect(gap, inInclusiveRange(2800, 3200),
          reason: '第 $i 次重推的间隔是 ${gap}ms，期望 3000ms（`_widgetPushRetryDelay`）');
    }

    // ④ 用尽只提示一次。
    expect(find.text(L10n.widgetSyncFailed), findsOneWidget,
        reason: '重试用尽应当提示一次；弹两次以上说明 `_widgetSyncWarned` 没生效');

    await _disposeShell(tester);
  });
}
