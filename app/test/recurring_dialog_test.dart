// app/test/recurring_dialog_test.dart
//
// 新建 / 编辑待办弹窗里的「重复」那一行。
//
// 重点不在「界面上有这一行」，而在**它落库落成了什么**：
//  ① 选了「每周三」→ 建出一个系列（weekdays 的位没歪）；
//  ② 编辑一条重复的行 → 改的是它背后的系列；
//  ③ 改周期之后，**当前那一条被对齐到新规则**（生成器只往前顺延、不管回退）；
//  ④ 把重复改回「不重复」→ 解绑并删系列，**待办一条都不许删**。
//
// 夹具照 `todo_dialog_test.dart`：库走 `NativeDatabase.opened`、插件通道挂空实现
// （没人接的通道调用**永远不会完成**，而保存链路里有「重排提醒」这一步要过通道）。
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

/// 有界推进若干帧（**不用 `pumpAndSettle`**：页面上有一堆永远调度下一帧的东西）。
Future<void> _settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 收尾：主动拆树，让 drift 取消查询流时排的那个零时长定时器真的跑掉。
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

/// 周三的掩码位（`DateTime.wednesday == 3` → `1 << 2`）。
const _wedBit = 1 << 2;

/// 周五的掩码位。
const _friBit = 1 << 4;

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
    final raw = sqlite3.sqlite3.openInMemory();
    db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    repo = AppRepository(db);
    await repo.ensureSeeded();
  });
  tearDown(() => db.close());

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: ScheduleScreen()),
    ));
    await _settle(tester);
  }

  /// 造一条「每周三、从一周前起效」的系列，并跑一次生成器让它有「当前这一条」。
  ///
  /// **起始日必须放在过去**：周三的系列若从今天起效，而今天不是周三时
  /// `occurrenceOnOrBefore` 返回 null（那是对的 —— 第一次要等下周三），于是列表里
  /// 什么都没有，后面那些「点开它」的步骤全会找不到控件。放一周前就恒有一个。
  Future<int> seedSeries() async {
    final t = DateTime.now();
    final id = await repo.addRecurringTodo(
      title: '周三例会',
      repeat: RecurRepeat.weekly,
      startDate: dateOnly(DateTime(t.year, t.month, t.day - 7)),
      weekdays: _wedBit,
    );
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    return id;
  }

  testWidgets('新建：选「每周」→ 只勾周三 → 添加，落成一个系列', (tester) async {
    await mount(tester);
    await tester.tap(find.byIcon(Icons.add_outlined));
    await _settle(tester);

    await tester.enterText(find.byType(TextField), '周三例会');
    // 重复那一行是四档胶囊，默认「不重复」
    expect(find.text(L10n.repeatNone), findsOneWidget);
    await tester.tap(find.text(L10n.repeatWeekly));
    await _settle(tester, frames: 6);

    // 选「每周」之后**默认勾上今天那一天**（掩码为空的话生成器会当脏数据、
    // 一条都不生成，而界面上看不出来）。把它调成「只有周三」——
    // 这里要按今天是星期几来调，否则用例会在周三那天自己把勾点掉。
    final todayWd = DateTime.now().weekday; // 1..7，周一 = 1
    if (todayWd != DateTime.wednesday) {
      await tester.ensureVisible(find.text(L10n.weekday(todayWd - 1)));
      await tester.tap(find.text(L10n.weekday(todayWd - 1)));
      await _settle(tester, frames: 6);
      await tester.ensureVisible(find.text(L10n.weekday(2)));
      await tester.tap(find.text(L10n.weekday(2)));
      await _settle(tester, frames: 6);
    }

    await tester.tap(find.text(L10n.add));
    await _settle(tester);

    final series = await repo.listRecurringTodos();
    expect(series.length, 1);
    expect(series.single.title, '周三例会');
    expect(series.single.weekdays, _wedBit,
        reason: '位序不能歪（周三 = 1 << 2）');
    expect(series.single.repeat, RecurRepeat.weekly);
    await _dispose(tester);
  });

  testWidgets('编辑一条重复的行：改的是它背后的系列', (tester) async {
    final id = await seedSeries();
    await mount(tester);

    await tester.tap(find.text('周三例会'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '周例会');
    await tester.tap(find.text(L10n.save));
    await _settle(tester);

    final series = (await repo.listRecurringTodos()).single;
    expect(series.id, id, reason: '还是那个系列，不是新建一个');
    expect(series.title, '周例会');
    await _dispose(tester);
  });

  testWidgets('把周期从「每周三」改成「每周五」→ 当前那条被对齐到周五',
      (tester) async {
    // spec §4.2 末段：生成器只往前顺延、永不回退，所以**改周期这条路径要自己
    // 把当前那条对齐**。不对齐的话，「每周三」改成「每周五」之后，列表里那条
    // 还停在周三 —— 而下次到点又是周五，中间会错一次。
    await seedSeries();
    final before = (await repo.listEvents()).single;

    await mount(tester);
    await tester.tap(find.text('周三例会'));
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

    expect((await repo.listRecurringTodos()).single.weekdays, _friBit);
    final after = (await repo.listEvents()).single;
    expect(after.id, before.id, reason: '还是那一条，只换了日子');
    expect(after.date.weekday, DateTime.friday,
        reason: '对齐到新规则 —— 生成器不会替我们回退');

    // 落点应当是「不晚于今天的最近一个周五」
    final t = DateTime.now();
    final back = (t.weekday - DateTime.friday + 7) % 7;
    final expected = DateTime(t.year, t.month, t.day - back);
    expect(dayNumber(after.date), dayNumber(expected));
    await _dispose(tester);
  });

  testWidgets('把重复改回「不重复」→ 解绑并删系列，**待办留着**', (tester) async {
    await seedSeries();
    await mount(tester);

    await tester.tap(find.text('周三例会'));
    await _settle(tester);
    await tester.tap(find.text(L10n.repeatNone));
    await _settle(tester, frames: 6);
    await tester.tap(find.text(L10n.save));
    await _settle(tester);

    expect(await repo.listRecurringTodos(), isEmpty, reason: '系列该没了');
    final rows = await repo.listEvents();
    expect(rows.length, 1,
        reason: '待办一条都不许删 —— 用户说的是「别再自动出现」，'
            '而这条正是他正在编辑的那一条');
    expect(rows.single.seriesId, isNull);
    await _dispose(tester);
  });
}
