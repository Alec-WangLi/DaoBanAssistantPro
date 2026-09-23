// app/test/alarm_screen_test.dart
//
// 闹钟页（`AlarmScreen`）的界面行为。
//
// **这一页此前一条测试都没有** —— 于是「按第一条判那天响没响」那个错口径活了
// 一整轮：首条已响、后面还有时（早餐闹钟响过、午休还等着），整行会被「响过的
// 自动隐藏」一起藏掉，连那一行的「按天关闹钟」开关也跟着没了。独立审查才抓到，
// v0.9.3 修的。判据本身现在抽成纯函数（`hasPendingShiftAlarm`，见
// `shift_alarm_decision_test.dart`）；**这一套测它在页面上的落点与渲染**。
//
// 页面里有个 `Timer.periodic(1min)`（让刚响过的闹钟自动消失），所以
// **不能 `pumpAndSettle`** —— 逐帧推进，与 `todo_dialog_test` 同一套做法。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/alarm/alarm_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 有界推进若干帧（不能用 `pumpAndSettle`：页面自己有个 1 分钟的周期定时器）。
Future<void> _settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 收尾：主动拆树，并让 drift 取消查询流时排的零时长定时器真的跑掉。
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

/// 挂一套只有一个班次的方案并打开闹钟页；[alarms] 就是这个班次的闹钟。
Future<AppDatabase> _pumpAlarmScreen(
  WidgetTester tester, {
  required String name,
  required int startMinute,
  required int endMinute,
  required List<ShiftAlarm> alarms,
}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  await AppRepository(db).saveSchedule(
    name: '测试方案',
    anchorDate: dateOnly(DateTime.now()),
    classes: [
      ShiftClass(
        name: name,
        abbr: '·',
        startMinute: startMinute,
        endMinute: endMinute,
        color: 0xFF7A5CFF,
        alarmEnabled: true,
        alarms: alarms,
      ),
    ],
    cycle: const [0], // 每天都是这个班次 —— 断言任意一天都拿得到
    makeCurrent: true,
    teamCount: 1,
    teamNames: const ['我'],
    teamOffsets: const [0],
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: AlarmScreen()),
  ));
  await _settle(tester);
  return db;
}

/// 把插件通道挂上空实现（与 `todo_dialog_test` 同一件事：没人接的通道调用
/// 永远不会完成，页面上的开关一说重排就会卡住）。
void _stubPluginChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in const [
    'dexterous.com/flutter/local_notifications',
    'com.daoban.shiftassistantpro/settings',
  ]) {
    messenger.setMockMethodCallHandler(
        MethodChannel(channel), (call) async => null);
  }
}

/// 某天的行（`AlarmScreen` 给每行挂了 `alarm-day-row-<天数>`）。
Finder _dayRow(DateTime date) =>
    find.byKey(Key('alarm-day-row-${dayNumber(date)}'));

/// 某天行里第 [k] 条闹钟的块（时间是它，下面那行「前一天」也是它）。
Finder _alarmBlock(DateTime date, int k) =>
    find.byKey(Key('alarm-block-${dayNumber(date)}-$k'));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    L10n.locale = 'zh';
    SharedPreferences.setMockInitialValues({});
    _stubPluginChannels();
  });

  // 取「今天 + 2 天」那一行：零点班的两条闹钟（23:00 前一天 / 03:00 当天）在这个
  // 日期上**无论测试几点跑都还没到**，断言因此与当前时刻无关。
  testWidgets('一个班次两条闹钟：同一天两行都列出来', (tester) async {
    await _pumpAlarmScreen(
      tester,
      name: '零点班',
      startMinute: 0,
      endMinute: 8 * 60, // 00:00–08:00
      alarms: const [
        ShiftAlarm(minute: 23 * 60, label: '起床'), // 落在上班前一天
        ShiftAlarm(minute: 3 * 60, label: '补觉'), // 落在班次当天
      ],
    );

    final date = dateOnly(DateTime.now()).add(const Duration(days: 2));
    expect(_dayRow(date), findsOneWidget);

    // 两条各自成一行（时间 + 名字）
    expect(find.descendant(of: _alarmBlock(date, 0), matching: find.text('23:00 起床')),
        findsOneWidget);
    expect(
        find.descendant(
            of: _alarmBlock(date, 1), matching: find.text('03:00 补觉')),
        findsOneWidget);

    await _dispose(tester);
  });

  // v0.8.9 的教训 + 多闹钟的坑：**「前一天」必须跟着各自那条走**，而且只能出现在
  // 该出现的那条下面（零点班的 23:00 是前一天、班中的 03:00 是当天）。
  testWidgets('「前一天」只跟在落在前一天的那条下面', (tester) async {
    await _pumpAlarmScreen(
      tester,
      name: '零点班',
      startMinute: 0,
      endMinute: 8 * 60,
      alarms: const [
        ShiftAlarm(minute: 23 * 60, label: '起床'), // 前一天
        ShiftAlarm(minute: 3 * 60, label: '补觉'), // 当天
      ],
    );

    final date = dateOnly(DateTime.now()).add(const Duration(days: 2));
    expect(find.descendant(of: _alarmBlock(date, 0), matching: find.text(L10n.prevDay)),
        findsOneWidget, reason: '23:00 晚于 00:00 上班钟点、又在窗口外 → 前一天');
    expect(find.descendant(of: _alarmBlock(date, 1), matching: find.text(L10n.prevDay)),
        findsNothing, reason: '03:00 落在值班窗口内 → 当天，不许跟着上一条一起标');

    await _dispose(tester);
  });

  // v0.9.3 修的那条（独立审查抓出来的）：**首条已响、后面还有时，整行不能藏**。
  // 用 24 小时值班的形状，这样两条闹钟无论几点跑都落在「当天」，断言与时刻无关；
  // 第一条取「一分钟前」（已响）、第二条取「五分钟后」（还等着）。
  testWidgets('首条已响、后面还有 → 那一行仍然在（连已响的那条也还列着）',
      (tester) async {
    final now = DateTime.now();
    final rung = (now.subtract(const Duration(minutes: 1)).hour * 60) +
        now.subtract(const Duration(minutes: 1)).minute;
    final pending = (now.add(const Duration(minutes: 5)).hour * 60) +
        now.add(const Duration(minutes: 5)).minute;

    await _pumpAlarmScreen(
      tester,
      name: '值班',
      startMinute: 8 * 60,
      endMinute: 32 * 60, // 24 小时值班：任何钟点都落在窗口内 → 都是当天
      alarms: [
        ShiftAlarm(minute: rung), // 序号 0：已经响过
        ShiftAlarm(minute: pending), // 序号 1：还等着
      ],
    );

    final today = dateOnly(now);
    expect(_dayRow(today), findsOneWidget,
        reason: '只看第一条的话，这条（已响）会把整行连它的开关一起藏掉');
    // 已响那条也仍然列着（整行是「这一天的闹钟」，不是「还没响的闹钟」）
    expect(find.descendant(of: _alarmBlock(today, 0), matching: find.text(_fmtClock(rung))),
        findsOneWidget);
    expect(
        find.descendant(
            of: _alarmBlock(today, 1), matching: find.text(_fmtClock(pending))),
        findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('英文界面：那一行不露出中文', (tester) async {
    // **界面测试切语言要种偏好，不能只改 `L10n.locale`** —— 页面 watch 的
    // `appSettingsProvider` 会从 SharedPreferences 读回 `language` 再写一次
    // `L10n.locale`，空的偏好就是 'zh'。（纯函数测试没有这层，直接改静态即可，
    // 比如 `shift_alarm_decision_test` 里那组。）
    SharedPreferences.setMockInitialValues({'language': 'en'});
    L10n.locale = 'en';
    await _pumpAlarmScreen(
      tester,
      name: 'Midnight shift',
      startMinute: 0,
      endMinute: 8 * 60,
      alarms: const [ShiftAlarm(minute: 23 * 60)],
    );

    final date = dateOnly(DateTime.now()).add(const Duration(days: 2));
    expect(find.descendant(of: _alarmBlock(date, 0), matching: find.text(L10n.prevDay)),
        findsOneWidget);
    expect(find.text('前一天'), findsNothing, reason: '英文界面不该出现中文标记');

    await _dispose(tester);
  });

  // ── 自定义闹钟：新建的默认值（v0.9.6） ──
  //
  // 默认从「每天」改成「一次性」：新建自定义闹钟十有八九就是「响这一次」，响过
  // 之后由 `deleteExpiredOnceAlarms` 收走，用户不必自己回来删。
  //
  // **但只改那一个默认值会造出一类排不出去的闹钟**：时间默认此刻、日期默认今天，
  // 两个默认叠在一起，触发时刻在按下「添加」之前就已经过去了，而一次性闹钟的排定
  // 判据是 `fire.isAfter(now)` —— 不排，下次进这一页还会被删掉。所以日期一律取
  // 「下一次出现」（`nextOnceDate`，边界在 `once_alarm_date_test.dart` 里逐条钉死）。
  // 下面这两条合起来才算数：一条盯默认值，一条盯「写库的那天在将来」。

  testWidgets('新建闹钟：默认「一次性」，日期行直接就在', (tester) async {
    await _pumpAlarmScreen(
      tester,
      name: '早班',
      startMinute: 8 * 60,
      endMinute: 16 * 60,
      alarms: const [], // 不留班次闹钟行，页面只剩自定义闹钟这一段
    );

    await tester.tap(find.text(L10n.newAlarm));
    await _settle(tester);

    // 日期行只在重复类型是「一次性」时才画（`_showAlarmDialog` 里的
    // `if (repeatType == 0)`），所以「它在」== 默认就是一次性。默认是「每天」的
    // 那几版里，这一行要手动点一下「一次性」才出现。
    expect(find.text(L10n.date), findsOneWidget,
        reason: '默认不是「一次性」的话，日期这一行根本不会画');
    expect(find.text(L10n.once), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('新建闹钟：什么都不动直接「添加」，存下来的是将来那一刻', (tester) async {
    final db = await _pumpAlarmScreen(
      tester,
      name: '早班',
      startMinute: 8 * 60,
      endMinute: 16 * 60,
      alarms: const [],
    );

    await tester.tap(find.text(L10n.newAlarm));
    await _settle(tester);
    await tester.tap(find.text(L10n.add));
    await _settle(tester);

    final alarms = await AppRepository(db).listCustomAlarms();
    expect(alarms, hasLength(1));
    final a = alarms.single;
    expect(a.repeatType, 0, reason: '新建的默认重复类型该是一次性');

    final od = a.onceDate!;
    final fire = DateTime(od.year, od.month, od.day, a.hour, a.minute);
    expect(fire.isAfter(DateTime.now()), isTrue,
        reason: '一次性的触发时刻落在过去 = 这一条排不出去、也不会响，'
            '下次进闹钟页还会被 deleteExpiredOnceAlarms 删掉 —— '
            '新建时的默认时间就是此刻，所以这一条必须靠日期顺延兜住');

    await _dispose(tester);
  });

  testWidgets('编辑一条「每天」的闹钟：不被新默认值盖成一次性', (tester) async {
    final db = await _pumpAlarmScreen(
      tester,
      name: '早班',
      startMinute: 8 * 60,
      endMinute: 16 * 60,
      alarms: const [],
    );
    await AppRepository(db).addCustomAlarm(hour: 7, minute: 30, repeatType: 1);
    await _settle(tester);

    await tester.tap(find.text(L10n.daily));
    await _settle(tester);

    expect(find.text(L10n.date), findsNothing,
        reason: '编辑既有闹钟要读它自己存的类型；默认值只在新建时说话');

    await _dispose(tester);
  });
}

/// 与 `AlarmScreen` 里那个私有 `_fmt` 同一形状（`HH:mm`）。
String _fmtClock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';
