// app/test/recurring_screen_test.dart
//
// 列表上的两件事：重复项有标记；删掉当前那条 = 「这次不要了」
//（不是删系列、也不会被生成器补回来）。
//
// 夹具照 `todo_dialog_test.dart`：库走 `NativeDatabase.opened`、插件通道挂空实现。
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_delete_button.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

Future<void> _settle(WidgetTester tester, {int frames = 20}) async {
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

  /// 造一条「每周三、一周前起效」的系列 + 一条普通待办。
  Future<int> seed() async {
    final t = DateTime.now();
    final id = await repo.addRecurringTodo(
      title: '周三例会',
      repeat: RecurRepeat.weekly,
      startDate: dateOnly(DateTime(t.year, t.month, t.day - 7)),
      weekdays: 1 << 2,
    );
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    await repo.addEvent(title: '交体检报告', date: dateOnly(DateTime.now()));
    return id;
  }

  testWidgets('重复项那一行带循环标记，普通待办不带', (tester) async {
    await seed();
    await mount(tester);

    // **限定在那条待办所在的行里数**：页面顶部那个「重复待办」入口用的是同一个
    // 图标，全页数会把两者混在一起（这条断言原来就是全页数，加那个入口才现形）。
    Finder repeatIn(String title) => find.descendant(
          of: find.ancestor(of: find.text(title), matching: find.byType(Row)),
          matching: find.byIcon(Icons.repeat),
        );

    expect(repeatIn('周三例会'), findsOneWidget);
    // 另一半（用例名里写着、原来却没验）：一次性待办不该带这个标记。
    expect(repeatIn('交体检报告'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('删掉当前那条：确认之后系列还在，只是**这一次**不要了',
      (tester) async {
    final id = await seed();
    await mount(tester);

    // 列表里两条待办 → 两个删除钮；删「周三例会」那个（它在上面）
    expect(find.byType(GlassDeleteButton), findsNWidgets(2));
    await tester.tap(find.byType(GlassDeleteButton).first);
    await _settle(tester);

    // 确认框里说的是「这一次」，不是删整个系列
    expect(find.text(L10n.skipThisOccurrence), findsOneWidget);
    await tester.tap(find.text(L10n.skipThisOccurrence));
    await _settle(tester);

    expect((await repo.listRecurringTodos()).single.id, id, reason: '系列要留着');
    final rows = await repo.listEvents();
    expect(rows.where((e) => e.seriesId != null), isEmpty);

    // 再跑一次生成器：不该补回来（这就是「删不掉」的那条护栏）
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    expect((await repo.listEvents()).where((e) => e.seriesId != null), isEmpty);
    await _dispose(tester);
  });

  testWidgets('确认框里的另一条路：删掉整个系列', (tester) async {
    await seed();
    await mount(tester);
    await tester.tap(find.byType(GlassDeleteButton).first);
    await _settle(tester);
    await tester.tap(find.text(L10n.deleteWholeSeries));
    await _settle(tester);

    expect(await repo.listRecurringTodos(), isEmpty);
    final rows = await repo.listEvents();
    expect(rows.length, 1, reason: '只剩那条普通待办');
    expect(rows.single.title, '交体检报告');
    await _dispose(tester);
  });
}
