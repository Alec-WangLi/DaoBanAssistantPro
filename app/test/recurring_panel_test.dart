// app/test/recurring_panel_test.dart
//
// 管理面板：入口在待办页标题那一行；面板里能停用、能删、能看到下一次什么时候。
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_delete_button.dart';
import 'package:shiftassistantpro/core/widgets/glass_dialog.dart';
import 'package:shiftassistantpro/core/widgets/glass_pill.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';
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

  Future<int> seedSeries() async {
    final t = DateTime.now();
    return repo.addRecurringTodo(
      title: '周三例会',
      repeat: RecurRepeat.weekly,
      startDate: dateOnly(DateTime(t.year, t.month, t.day - 7)),
      weekdays: 1 << 2,
      timeMinute: 9 * 60,
      advanceRemindMinutes: 0,
    );
  }

  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.text(L10n.recurring));
    await _settle(tester);
  }

  // 入口在标题那一行的**最右边**（不是紧贴标题）—— 用户 2026-09-30 反馈
  // 「可以移到右上角，感觉这样美观一些」。判据走**几何**而不是「有没有
  // Expanded」：那种断言换个写法照样能过（本仓吃过这种假护栏的亏）。
  testWidgets('入口靠在标题行的右边缘', (tester) async {
    await mount(tester);

    final pill = tester.getRect(find.byType(GlassPill));
    // 页面左右各留 20（`EdgeInsets.fromLTRB(20, 12, 20, 4)`）。
    //
    // **判据只有这一条，而且它是有鉴别力的**：改之前（标题走 `Flexible`）胶囊
    // 紧跟在标题后面，右边缘在 300 上下，离 400 差着一整个标题的宽度。
    //
    // 别再补一条「标题与入口之间有空隙」：`getRect(find.text(...))` 量的是
    // **文字盒**，而 `Expanded` 下那个盒恒等于「胶囊左边减去 8 的间距」——
    // 贴不贴它都这么宽，量不出任何东西（我第一版就是这么写的，报出来
    // `Actual: 301` 才发现量的是盒不是字）。
    expect(pill.right, closeTo(420 - 20, 1), reason: '入口靠右，与页面右边距对齐');

    await _dispose(tester);
  });

  testWidgets('标题旁有入口；点开能看到系列的周期与下一次', (tester) async {
    await seedSeries();
    await mount(tester);

    expect(find.text(L10n.recurring), findsOneWidget, reason: '标题那一行的入口');
    await openPanel(tester);

    // **断言一律限定在弹窗内**：待办页自己也会跑一次生成器，所以那条「当前这一次」
    // 也在列表里，`'09:00'` 这类文字会出现两次。
    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(GlassDialog), matching: f);
    expect(inDialog(find.text('周三例会')), findsOneWidget);
    expect(inDialog(find.textContaining(L10n.everyWeekOn([2]))), findsOneWidget);
    expect(inDialog(find.textContaining('09:00')), findsOneWidget);
    expect(inDialog(find.textContaining(L10n.nextTime('').trim())),
        findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('面板里停用之后，系列真的落了库（而且提醒会被重排）', (tester) async {
    await seedSeries();
    await mount(tester);
    await openPanel(tester);

    // 面板里那个开关 —— **限定在弹窗内**：后面待办列表里那条也有一个（勾选用）。
    await tester.tap(find.descendant(
        of: find.byType(GlassDialog), matching: find.byType(GlassSwitch)));
    await _settle(tester);

    expect((await repo.listRecurringTodos()).single.enabled, isFalse);
    await _dispose(tester);
  });

  testWidgets('面板里删除要确认，确认后系列与它的行都没了', (tester) async {
    await seedSeries();
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    expect((await repo.listEvents()).length, 1);
    await mount(tester);
    await openPanel(tester);

    // 面板里那个删除钮 —— **要限定在弹窗内**：后面待办列表里那条也有一个
    // `GlassDeleteButton`，不限定就「找到两个」。
    await tester.tap(find.descendant(
        of: find.byType(GlassDialog),
        matching: find.byType(GlassDeleteButton)));
    await _settle(tester);
    // 确认框点了名、也说了会连带删掉几条
    expect(find.textContaining('周三例会'), findsWidgets);
    await tester.tap(find.text(L10n.delete));
    await _settle(tester);

    expect(await repo.listRecurringTodos(), isEmpty);
    expect(await repo.listEvents(), isEmpty, reason: '它的行一起走');
    await _dispose(tester);
  });

  testWidgets('面板里删除**取消**：什么都不删（返回值被当成确认是迁移最容易丢的一条）',
      (tester) async {
    // Review Focus 第 1 条。把 21 处 `showDialog` 换成 `showGlassDialog` 时，每一处的
    // 泛型与 `await` 之后的用法必须原样保留 —— 丢了就是「点了取消却当成确认」，
    // **不报错**（`false` 与「没返回」在 `if (ok == true)` 之外长得一样）。
    // 上面那条只走了「确认」一侧，这条补上「取消」那一侧。
    await seedSeries();
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    expect((await repo.listEvents()).length, 1);
    await mount(tester);
    await openPanel(tester);

    await tester.tap(find.descendant(
        of: find.byType(GlassDialog),
        matching: find.byType(GlassDeleteButton)));
    await _settle(tester);
    // 取消钮**限定在最上面那个弹窗里** —— 面板自己也是个 `GlassDialog`。
    await tester.tap(find.descendant(
        of: find.byType(GlassDialog).last, matching: find.text(L10n.cancel)));
    await _settle(tester);

    expect(await repo.listRecurringTodos(), isNotEmpty,
        reason: '点了「取消」，系列却没了 —— 返回值被当成了确认');
    expect(await repo.listEvents(), isNotEmpty, reason: '点了「取消」，它的行却没了');
    await _dispose(tester);
  });

  testWidgets('一条都没有时给一行空态说明', (tester) async {
    await mount(tester);
    await openPanel(tester);
    expect(find.text(L10n.recurringEmpty), findsOneWidget);
    await _dispose(tester);
  });
}
