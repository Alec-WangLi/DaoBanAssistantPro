// app/test/todo_shift_marker_test.dart
//
// 待办行的「提醒落在前一天 / 次日」标记：纯函数 + 界面两层。
//
// 标记是**显示**，排定是**行为**，两者必须同源 —— 标记错了不会报错，只会让用户
// 以为提醒在 A 时其实它在 B 时响。所以纯函数层的用例钉死三种落点，界面层的用例
// 钉死「什么情况下不许标」（不是按班次 / 名字没选过 / 钟点对不上）。
import 'package:drift/drift.dart' show driftRuntimeOptions;
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
  setUp(() => L10n.locale = 'zh');

  group('todoReminderClockLabel', () {
    const night = ShiftClass(name: '夜班', startMinute: 1230, endMinute: 510);

    test('班中钟点标「次日」，上班前不标，零点班配 23:00 标「前一天」', () {
      expect(todoReminderClockLabel(clockMinute: 0, shift: night),
          L10n.clockNextDay('00:00'));
      expect(todoReminderClockLabel(clockMinute: 19 * 60, shift: night), isNull);
      expect(
          todoReminderClockLabel(
              clockMinute: 23 * 60,
              shift: const ShiftClass(
                  name: '零点班', startMinute: 0, endMinute: 480)),
          L10n.clockPrevDay('23:00'));
    });

    test('没有班次（那天没排班 / 不是按班次规则）不标', () {
      expect(todoReminderClockLabel(clockMinute: 0, shift: null), isNull);
    });
  });

  group('待办行上的标记', () {
    setUpAll(() async {
      await initializeDateFormatting('zh');
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
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

    /// 把当前方案换成「今天 = 夜班（20:30–次日 08:30）」的三天轮转。
    /// 锚点往前挪一天：周期 [白, 夜, 休] → 今天正好落在夜班。
    Future<void> useNightToday() async {
      final today = dateOnly(DateTime.now());
      await repo.saveSchedule(
        name: '夜班 · 今天',
        anchorDate: DateTime(today.year, today.month, today.day - 1),
        classes: const [
          ShiftClass(
              name: '白班',
              abbr: '白',
              startMinute: 480,
              endMinute: 1200,
              color: 0xFF4C8DFF),
          ShiftClass(
              name: '夜班',
              abbr: '夜',
              startMinute: 1230,
              endMinute: 480,
              color: 0xFF7A5CFF),
          ShiftClass(name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4),
        ],
        cycle: const [0, 1, 2],
        makeCurrent: true,
        teamCount: 1,
        teamNames: const ['我'],
        ourTeamIndex: 0,
        teamOffsets: const [0],
      );
    }

    Future<void> pumpScreen(WidgetTester tester) async {
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

    testWidgets('按班次 + 夜班 + 00:00：行上标「次日 00:00」', (tester) async {
      await useNightToday();
      final sid = await repo.addRecurringTodo(
        title: '夜班写台账',
        repeat: RecurRepeat.shift,
        startDate: dateOnly(DateTime.now()),
        shiftNames: const ['夜班'],
        timeMinute: 0,
        advanceRemindMinutes: 0,
      );
      await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
      await pumpScreen(tester);

      expect(find.text('夜班写台账'), findsOneWidget);
      expect(find.textContaining(L10n.clockNextDay('00:00')), findsOneWidget,
          reason: '夜班 20:30–次日 08:30 的 00:00 提醒落在次日，行上要标出来');
      expect(sid, isNotNull);
      await _dispose(tester);
    });

    testWidgets('每天规则 + 00:00：不标（没有班次上下文）', (tester) async {
      await useNightToday();
      await repo.addRecurringTodo(
        title: '每天现场巡检',
        repeat: RecurRepeat.daily,
        startDate: dateOnly(DateTime.now()),
        timeMinute: 0,
        advanceRemindMinutes: 0,
      );
      await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
      await pumpScreen(tester);

      expect(find.text('每天现场巡检'), findsOneWidget);
      expect(find.textContaining('次日'), findsNothing,
          reason: '每天 / 每周 / 每月没有班次上下文，落点恒为发生日');
      await _dispose(tester);
    });

    testWidgets('每天规则但残留班次名（切规则留下的）→ 仍不标', (tester) async {
      // `RecurringRulePicker` 从「按班次」切回「每天」时不会清空 shiftNames ——
      // 只有 `repeat == shift` 这道闸门拦得住。
      await useNightToday();
      await repo.addRecurringTodo(
        title: '每天均可',
        repeat: RecurRepeat.daily,
        startDate: dateOnly(DateTime.now()),
        shiftNames: const ['夜班'],
        timeMinute: 0,
        advanceRemindMinutes: 0,
      );
      await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
      await pumpScreen(tester);

      expect(find.text('每天均可'), findsOneWidget);
      expect(find.textContaining('次日'), findsNothing,
          reason: '规则不是按班次，就算名字还在，也没有班次上下文');
      await _dispose(tester);
    });

    testWidgets('系列停用 → 不标（排定侧不会响）', (tester) async {
      await useNightToday();
      final sid = await repo.addRecurringTodo(
        title: '停用的夜班',
        repeat: RecurRepeat.shift,
        startDate: dateOnly(DateTime.now()),
        shiftNames: const ['夜班'],
        timeMinute: 0,
        advanceRemindMinutes: 0,
      );
      await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
      await repo.setRecurringEnabled(sid, false);
      await pumpScreen(tester);

      expect(find.text('停用的夜班'), findsOneWidget);
      expect(find.textContaining('次日'), findsNothing);
      await _dispose(tester);
    });

    testWidgets('没设提醒 → 不标（排定侧不会响）', (tester) async {
      await useNightToday();
      await repo.addRecurringTodo(
        title: '不提醒的夜班',
        repeat: RecurRepeat.shift,
        startDate: dateOnly(DateTime.now()),
        shiftNames: const ['夜班'],
        timeMinute: 0,
      );
      await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
      await pumpScreen(tester);

      expect(find.text('不提醒的夜班'), findsOneWidget);
      expect(find.textContaining('次日'), findsNothing);
      await _dispose(tester);
    });

    testWidgets('旧行：今天的班次不在系列选的名单里 → 不标', (tester) async {
      // 改排班后生成器「只往前不回退」会留下这种行；排定侧不会给它排提醒。
      await useNightToday();
      final sid = await repo.addRecurringTodo(
        title: '白班才提醒',
        repeat: RecurRepeat.shift,
        startDate: dateOnly(DateTime.now()),
        shiftNames: const ['白班'],
        timeMinute: 0,
        advanceRemindMinutes: 0,
      );
      await repo.addEvent(
        title: '白班才提醒',
        date: dateOnly(DateTime.now()),
        timeMinute: 0,
        seriesId: sid,
      );
      await pumpScreen(tester);

      expect(find.text('白班才提醒'), findsOneWidget);
      expect(find.textContaining('次日'), findsNothing);
      await _dispose(tester);
    });

    testWidgets('行上的钟点与系列钟点不一致（脏数据）→ 不标', (tester) async {
      await useNightToday();
      final sid = await repo.addRecurringTodo(
        title: '钟点对不上',
        repeat: RecurRepeat.shift,
        startDate: dateOnly(DateTime.now()),
        shiftNames: const ['夜班'],
        timeMinute: 0,
        advanceRemindMinutes: 0,
      );
      await repo.addEvent(
        title: '钟点对不上',
        date: dateOnly(DateTime.now()),
        timeMinute: 9 * 60,
        seriesId: sid,
      );
      await pumpScreen(tester);

      expect(find.text('钟点对不上'), findsOneWidget);
      expect(find.textContaining('次日'), findsNothing);
      await _dispose(tester);
    });
  });
}
