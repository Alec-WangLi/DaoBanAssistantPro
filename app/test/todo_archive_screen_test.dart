// app/test/todo_archive_screen_test.dart
//
// 待办页的归档读法：主列表只列**未完成**的（加上**本次进来之后**刚勾掉的那几条），
// 已完成的收进底部「已完成 N 条」的折叠区。
//
// 夹具照 `recurring_screen_test.dart`：库走 `NativeDatabase.opened`、插件通道挂空实现。
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_check.dart';
import 'package:shiftassistantpro/core/widgets/glass_delete_button.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
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

  /// 挂这一页。[key] 换一个就等于「下次进来」（视作被销毁重建）。
  Future<void> pumpScreen(WidgetTester tester, {Key? key}) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(home: ScheduleScreen(key: key)),
    ));
    await _settle(tester);
  }

  /// 造一条待办；[done] 为真就直接勾掉。
  ///
  /// `addEvent` 回的是行 id、不是行，而 `setEventCompleted` 要一个 `ScheduleEvent`
  /// —— 所以读回来再勾。
  Future<void> add(String title, DateTime date, {bool done = false}) async {
    final id = await repo.addEvent(title: title, date: date);
    if (done) {
      final e = (await repo.listEvents()).firstWhere((x) => x.id == id);
      await repo.setEventCompleted(e, true);
    }
  }

  testWidgets('已完成的进折叠区、默认收起；数字与展开后的行数一致', (tester) async {
    await add('没做的甲', DateTime(2026, 1, 1));
    await add('没做的乙', DateTime(2026, 1, 2));
    await add('做完的甲', DateTime(2026, 1, 3), done: true);
    await add('做完的乙', DateTime(2026, 1, 4), done: true);
    await pumpScreen(tester);

    expect(find.text('没做的甲'), findsOneWidget);
    expect(find.text('没做的乙'), findsOneWidget);
    expect(find.text('做完的甲'), findsNothing, reason: '已完成的默认收在折叠区里');
    expect(find.text('做完的乙'), findsNothing);
    expect(find.text(L10n.archivedTodos(2)), findsOneWidget);

    await tester.tap(find.text(L10n.archivedTodos(2)));
    await _settle(tester);
    expect(find.text('做完的甲'), findsOneWidget);
    expect(find.text('做完的乙'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('勾掉一条：它仍在主列表里、且停在原位（不能跳到末尾）', (tester) async {
    await add('第一条', DateTime(2026, 1, 1));
    await add('第二条', DateTime(2026, 1, 2));
    await pumpScreen(tester);

    await tester.tap(find.byType(GlassCheck).first);
    await _settle(tester);

    expect(find.text('第一条'), findsOneWidget,
        reason: '先划掉 —— 这一趟它仍留在原地（下次进来才收走）');
    expect(tester.getTopLeft(find.text('第一条')).dy,
        lessThan(tester.getTopLeft(find.text('第二条')).dy),
        reason: '它得停在原来的位置上，而不是「啪」地跳到列表末尾');
    expect(find.text(L10n.archivedTodos(1)), findsNothing,
        reason: '刚勾的那条这一趟不进折叠区');

    await _dispose(tester);
  });

  testWidgets('下次进来（重建这一页）才收走：那条进了折叠区、主列表里没了', (tester) async {
    await add('第一条', DateTime(2026, 1, 1));
    await add('第二条', DateTime(2026, 1, 2));
    await pumpScreen(tester);

    await tester.tap(find.byType(GlassCheck).first);
    await _settle(tester);
    expect(find.text('第一条'), findsOneWidget, reason: '这一趟还在主列表');

    // 换一个 key = 这一页被销毁重建（切走再回来时 PageView 就是这么做的）。
    await pumpScreen(tester, key: const ValueKey('again'));

    expect(find.text('第一条'), findsNothing, reason: '收进折叠区了');
    expect(find.text(L10n.archivedTodos(1)), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('主列表为空、归档非空：那句提示还在，折叠区仍能点开', (tester) async {
    await add('做完的甲', DateTime(2026, 1, 1), done: true);
    await pumpScreen(tester);

    expect(find.text(L10n.noEvents), findsOneWidget,
        reason: '没有未完成的待办了 —— 那句话还得在');
    expect(find.text(L10n.archivedTodos(1)), findsOneWidget,
        reason: '折叠区不能被空态顶掉');

    await tester.tap(find.text(L10n.archivedTodos(1)));
    await _settle(tester);
    expect(find.text('做完的甲'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('折叠区展开后滑到底：最后一行那颗删除键不被「新建」按钮挡住', (tester) async {
    // 条数要**真的撑破视口**（420×1200，一行约 74 → 十几条根本滚不动，那种断言
    // 会变成一句永远为真的空话）。主列表与归档各 16 条，且归档要展开。
    final day = dateOnly(DateTime.now());
    for (var i = 0; i < 16; i++) {
      await repo.addEvent(title: '没做的 $i', date: day);
      await repo.addEvent(title: '做完的 $i', date: day);
    }
    for (final e in await repo.listEvents()) {
      if (e.title.startsWith('做完的')) {
        await repo.setEventCompleted(e, true);
      }
    }
    await pumpScreen(tester);
    await tester.tap(find.text(L10n.archivedTodos(16)));
    await _settle(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -8000));
    await _settle(tester);

    final fab = tester.getRect(find.byIcon(Icons.add_outlined));
    final buttons = find.byType(GlassDeleteButton);
    final last = tester.getRect(buttons.last);

    expect(last.bottom, lessThanOrEqualTo(fab.top),
        reason: '折叠区最后一行那颗删除键的底边（${last.bottom}）应当在「新建」按钮的'
            '顶边（${fab.top}）之上 —— 被压住就点不到了');

    // **主判据**：在它自己的中心做一次命中测试，它必须真的在命中路径里。
    // 只断言几何的话，「被别的层吃掉手势」这类照样漏。
    final hit = tester.hitTestOnBinding(last.center);
    expect(
        hit.path.any((e) => e.target == tester.renderObject(buttons.last)), isTrue,
        reason: '删除键的中心得真的打得中 —— 被 FAB 盖住时命中的是 FAB');

    await _dispose(tester);
  });
}
