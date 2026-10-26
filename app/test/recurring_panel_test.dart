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
import 'package:shiftassistantpro/core/widgets/glass_weekday_picker.dart';
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

  testWidgets('库里短时间有两条未完成时，点开系列编辑器不许崩', (tester) async {
    final sid = await seedSeries();
    await mount(tester);
    await openPanel(tester);

    // **这条插入必须放在挂载之后。** `ScheduleScreen` 一挂上就会跑一次生成器，
    // 而生成器见到多条未完成会自己收掉（`app_repository.dart:1046` 那段「多条未完成
    // 是脏数据」）—— 提前插的话，还没被读到就先被治好了，用例就成了空话。
    //
    // 真实路径是「把当前那一条勾回来，而生成器还没跑」（回前台 / 跨天各会跑一次）。
    // 生成器迟早会收，但**在它收之前**面板点一下就先崩了。
    final live = (await repo.listEvents()).firstWhere((e) => e.seriesId == sid);
    await db.into(db.scheduleEvents).insert(ScheduleEventsCompanion.insert(
          title: live.title,
          date: live.date,
          timeMinute: drift.Value(live.timeMinute),
          createdAt: DateTime.now(),
          seriesId: drift.Value(sid),
        ));
    expect(
        (await repo.listEvents())
            .where((e) => e.seriesId == sid && !e.isCompleted)
            .length,
        2,
        reason: '脏状态摆好了');

    await tester.tap(find.descendant(
        of: find.byType(GlassDialog), matching: find.text('周三例会')));
    await _settle(tester);

    expect(tester.takeException(), isNull,
        reason: '两条未完成时旧实现的 `live.single` 会当场抛 StateError');
    expect(find.text(L10n.editRecurring), findsOneWidget,
        reason: '面板点进去开的是**系列编辑器**（不再依赖「当前这一次」）');

    await _dispose(tester);
  });

  // ── 2026-10-21 用户真机：「已添加的重复待办，它不能修改，也找不到编辑」 ──
  //
  // 根因：编辑入口绑在「当前这一次」上。每月 1 号的系列，在 1 号之前列表里
  // 没有那一条，面板点它只弹一句「没有下一次」。现在面板点任何一条都开系列
  // 编辑器，不依赖行在不在。
  testWidgets('没有「当前这一次」也能改：起始日在将来时面板照样点得开',
      (tester) async {
    final t = DateTime.now();
    // 起始日放在**下个月 1 号**：今天之后，生成器一条都不生成 —— 正是用户那条
    // 「每月 1 号」在月初之前的真实状态。
    final id = await repo.addRecurringTodo(
      title: '灭火器检查',
      repeat: RecurRepeat.monthly,
      startDate: dateOnly(DateTime(t.year, t.month + 1, 1)),
      monthDays: 1,
    );
    await repo.advanceRecurringTodos(today: dateOnly(t));
    expect(
        (await repo.listEvents()).where((e) => e.seriesId == id), isEmpty,
        reason: '起始日在将来时不该有当前这一次（夹具前提）');

    await mount(tester);
    await openPanel(tester);
    await tester.tap(find.descendant(
        of: find.byType(GlassDialog), matching: find.text('灭火器检查')));
    await _settle(tester);

    expect(find.text(L10n.editRecurring), findsOneWidget,
        reason: '没有当前这一次，也要能打开系列编辑器');
    expect(find.text(L10n.save), findsOneWidget);

    // 改标题 + 把规则改成每周（挑一个**当前没被选中**的星期），保存后系列真的落库。
    //
    // ⚠️ 别写死「周一」：切到每周时控件会把默认那天（起始日 / 今天）先勾上，
    // 若那天正好是周一，再点一下就是**取消**它 —— 这条用例因此会在周一必红
    // （2026-10-26 全套测试撞上过）。
    await tester.enterText(find.byType(TextField), '灭火器月检');
    await tester.tap(find.text(L10n.repeatWeekly));
    await _settle(tester, frames: 6);
    final picker =
        tester.widget<GlassWeekdayPicker>(find.byType(GlassWeekdayPicker));
    final int day = List<int>.generate(7, (i) => i)
        .firstWhere((i) => picker.value & (1 << i) == 0);
    await tester.tap(find.text(L10n.weekday(day)));
    await _settle(tester, frames: 6);
    await tester.tap(find.text(L10n.save));
    await _settle(tester);

    // 编辑器关掉了，系列写进去了。
    expect(find.text(L10n.editRecurring), findsNothing);
    final s = (await repo.listRecurringTodos()).single;
    expect(s.title, '灭火器月检');
    expect(s.repeat, RecurRepeat.weekly);
    expect(s.weekdays & (1 << day), isNot(0),
        reason: '勾了 ${L10n.weekday(day)} —— 掩码里至少得有这一天');
    await _dispose(tester);
  });




  testWidgets('系列编辑器改标题后，面板那一行立刻更新', (tester) async {
    await seedSeries();
    await mount(tester);
    await openPanel(tester);
    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(GlassDialog), matching: f);
    await tester.tap(inDialog(find.text('周三例会')));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '周三例会改');
    await tester.tap(find.text(L10n.save));
    await _settle(tester);

    expect(inDialog(find.text('周三例会改')), findsOneWidget,
        reason: '保存之后面板还显示旧标题的话，用户会以为没改成');
    await _dispose(tester);
  });

  // ── v0.12.3：面板去铅笔 + 按班次的下一次与缺名提示 ──

  testWidgets('行尾不再有编辑铅笔', (tester) async {
    await seedSeries();
    await mount(tester);
    await openPanel(tester);
    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(GlassDialog), matching: f);
    expect(inDialog(find.byIcon(Icons.edit_outlined)), findsNothing,
        reason: '整行点进去就是编辑，铅笔是多余的');
    await _dispose(tester);
  });

  testWidgets('按班次系列：显示下一次；班次名字找不到时给提示', (tester) async {
    final t = DateTime.now();
    await repo.addRecurringTodo(
      title: '带工牌',
      repeat: RecurRepeat.shift,
      startDate: dateOnly(DateTime(t.year, t.month, t.day - 7)),
      shiftNames: const ['上夜班'],
      timeMinute: 7 * 60,
      advanceRemindMinutes: 0,
    );
    await repo.addRecurringTodo(
      title: '写台账',
      repeat: RecurRepeat.shift,
      startDate: dateOnly(DateTime(t.year, t.month, t.day - 7)),
      shiftNames: const ['不存在的班'],
      timeMinute: 9 * 60,
      advanceRemindMinutes: 0,
    );
    await mount(tester);
    await openPanel(tester);
    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(GlassDialog), matching: f);

    // 「上夜班」在默认排班表里 → 有「下次 X」；「不存在的班」→ 缺名提示。
    expect(inDialog(find.textContaining(L10n.nextTime('').trim())),
        findsWidgets);
    expect(inDialog(find.text(L10n.shiftRuleMissing(['不存在的班']))),
        findsOneWidget);
    await _dispose(tester);
  });

  // ── v0.12.3：每月多选 + 按班次（系列编辑器接线） ──

  testWidgets('系列编辑器：每月改多选并保存', (tester) async {
    final t = DateTime.now();
    await repo.addRecurringTodo(
      title: '灭火器检查',
      repeat: RecurRepeat.monthly,
      startDate: dateOnly(DateTime(t.year, t.month - 1, 1)),
      monthDays: 1,
    );
    await repo.advanceRecurringTodos(today: dateOnly(t));
    await mount(tester);
    await openPanel(tester);
    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(GlassDialog), matching: f);
    await tester.tap(inDialog(find.text('灭火器检查')));
    await _settle(tester);

    await tester.tap(inDialog(find.text('15')));
    await _settle(tester, frames: 6);
    await tester.tap(find.text(L10n.save));
    await _settle(tester);

    expect(find.text(L10n.editRecurring), findsNothing);
    final s = (await repo.listRecurringTodos()).single;
    expect(s.monthDays, (1 << 0) | (1 << 14));
    await _dispose(tester);
  });

  testWidgets('系列编辑器：按班次没选名字、又没有可选班次时，保存被挡下并提示',
      (tester) async {
    final t = DateTime.now();
    // 空白表（跟随法定节假日）没有班次定义 —— 一个可选项都没有。
    await repo.saveSchedule(
      name: '法定班次',
      anchorDate: dateOnly(t),
      classes: const [],
      cycle: const [],
    );
    await repo.addRecurringTodo(
      title: '带工牌',
      repeat: RecurRepeat.shift,
      startDate: dateOnly(t),
      shiftNames: const [],
    );
    await mount(tester);
    await openPanel(tester);
    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(GlassDialog), matching: f);
    await tester.tap(inDialog(find.text('带工牌')));
    await _settle(tester);
    expect(inDialog(find.text(L10n.shiftRuleNoSchedule)), findsOneWidget);

    await tester.tap(find.text(L10n.save));
    await _settle(tester);

    expect(find.text(L10n.editRecurring), findsOneWidget, reason: '不许关窗');
    expect(inDialog(find.text(L10n.ruleNeedsShift)), findsOneWidget);
    expect((await repo.listRecurringTodos()).single.shiftNames, isEmpty,
        reason: '无效规则不许落库');
    await _dispose(tester);
  });

  testWidgets('系列编辑器：老数据的空班次规则打开时补上默认值', (tester) async {
    final t = DateTime.now();
    await repo.addRecurringTodo(
      title: '带工牌',
      repeat: RecurRepeat.shift,
      startDate: dateOnly(t),
      shiftNames: const [],
    );
    await mount(tester);
    await openPanel(tester);
    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(GlassDialog), matching: f);
    await tester.tap(inDialog(find.text('带工牌')));
    await _settle(tester);

    // 默认排班表有班次 → 打开时补成当天那一个，于是保存直接可用。
    await tester.tap(find.text(L10n.save));
    await _settle(tester);
    expect(find.text(L10n.editRecurring), findsNothing);
    expect((await repo.listRecurringTodos()).single.shiftNames, isNotEmpty);
    await _dispose(tester);
  });

  testWidgets('面板里改周期：当前这一次对齐到新规则（生成器不会替我们回退）',
      (tester) async {
    final sid = await seedSeries();
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    final before = (await repo.listEvents()).single;
    expect(before.date.weekday, DateTime.wednesday);

    await mount(tester);
    await openPanel(tester);
    await tester.tap(find.descendant(
        of: find.byType(GlassDialog), matching: find.text('周三例会')));
    await _settle(tester);

    // 去掉周三、加上周五
    await tester.ensureVisible(find.text(L10n.weekday(2)));
    await tester.tap(find.text(L10n.weekday(2)));
    await _settle(tester, frames: 6);
    await tester.ensureVisible(find.text(L10n.weekday(4)));
    await tester.tap(find.text(L10n.weekday(4)));
    await _settle(tester, frames: 6);
    await tester.tap(find.text(L10n.save));
    await _settle(tester);

    final s = (await repo.listRecurringTodos()).firstWhere((x) => x.id == sid);
    expect(s.weekdays, 1 << 4);
    final live = (await repo.listEvents())
        .where((e) => e.seriesId == sid && !e.isCompleted)
        .single;
    expect(live.date.weekday, DateTime.friday,
        reason: '当前这一次要对齐到新规则 —— 生成器只往前、不回退');
    await _dispose(tester);
  });

  testWidgets('只改标题时，不把用户手工挪过的那一次拽回规则日', (tester) async {
    await seedSeries();
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    final live = (await repo.listEvents()).single;
    // 用户把这一次会挪到了周四（规则仍是每周三）。
    await repo.setEventDate(
        live.id, dateOnly(live.date.add(const Duration(days: 1))));
    final moved =
        (await repo.listEvents()).firstWhere((e) => e.id == live.id);

    await mount(tester);
    await openPanel(tester);
    await tester.tap(find.descendant(
        of: find.byType(GlassDialog), matching: find.text('周三例会')));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '周三例会（改标题）');
    await tester.tap(find.text(L10n.save));
    await _settle(tester);

    final after =
        (await repo.listEvents()).firstWhere((e) => e.id == live.id);
    expect(after.title, '周三例会（改标题）');
    expect(dayNumber(after.date), dayNumber(moved.date),
        reason: '规则没动，用户手工挪过的日子不许被对齐逻辑拽回去');
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
