// app/test/recurring_advance_hooks_test.dart
//
// 生成器要在三个时点跑：App 启动、回到前台、进待办页（改完系列是第四个，
// 由编辑路径自己负责 —— 见 `_EventFields.commit` 里那段对齐）。
//
// 漏掉「回到前台」的后果最隐蔽：App 一直没关、跨过午夜之后列表不会动 ——
// 因为列表是 drift 流，**不写库就不会重发**。用户看到的是「昨天的日期还在那儿」。
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

Future<void> _settle(WidgetTester tester, {int frames = 24}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

void _stubPluginChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in const [
    'dexterous.com/flutter/local_notifications',
    'com.daoban.shiftassistantpro/settings',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    addTearDown(
        () => messenger.setMockMethodCallHandler(MethodChannel(name), null));
  }
}

/// 模拟「App 回到前台」。
///
/// 走 `SystemChannels.lifecycle` 的平台消息，而不是 `binding.
/// handleAppLifecycleStateChanged` —— 后者是 `@protected`，测试里调它会被
/// analyzer 拦下。
Future<void> _resume(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    SystemChannels.lifecycle.codec.encodeMessage('AppLifecycleState.resumed'),
    (_) {},
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late AppRepository repo;

  setUp(() async {
    L10n.locale = 'zh';
    _stubPluginChannels();
    db = AppDatabase.forTesting(
        NativeDatabase.opened(sqlite3.sqlite3.openInMemory()));
    repo = AppRepository(db);
    await repo.ensureSeeded();
  });
  tearDown(() => db.close());

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: ScheduleScreen()),
    ));
    await _settle(tester);
  }

  /// 每天、一周前起效的系列。
  Future<int> seedDaily() async {
    final t = DateTime.now();
    return repo.addRecurringTodo(
      title: '每天交班',
      repeat: RecurRepeat.daily,
      startDate: dateOnly(DateTime(t.year, t.month, t.day - 7)),
      timeMinute: 7 * 60,
      advanceRemindMinutes: 0,
    );
  }

  testWidgets('进待办页会把「当前这一次」补齐', (tester) async {
    final id = await seedDaily();
    // 进页面前：库里一条行都没有
    expect(await repo.listEvents(), isEmpty);

    await mount(tester);

    final rows = await repo.listEvents();
    expect(rows.length, 1, reason: '进页面就该看到今天这一条');
    expect(rows.single.seriesId, id);
    expect(dayNumber(rows.single.date), dayNumber(DateTime.now()));
    await _dispose(tester);
  });

  testWidgets('回到前台会再跑一次（跨过午夜那条路径）', (tester) async {
    await seedDaily();
    await mount(tester);
    final row = (await repo.listEvents()).single;

    // 模拟「App 一直开着、跨过了午夜」：把那条行挪回昨天
    final t = DateTime.now();
    final yesterday = DateTime(t.year, t.month, t.day - 1);
    await repo.setEventDate(row.id, dateOnly(yesterday));
    expect(dayNumber((await repo.listEvents()).single.date),
        dayNumber(yesterday));

    await _resume(tester);
    await _settle(tester);

    expect(dayNumber((await repo.listEvents()).single.date),
        dayNumber(DateTime.now()),
        reason: '回到前台要顺延到今天，否则界面上一直挂着昨天的日期');
    expect((await repo.listEvents()).single.id, row.id, reason: '就地顺延');
    await _dispose(tester);
  });
}
