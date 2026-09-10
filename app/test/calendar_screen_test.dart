// app/test/calendar_screen_test.dart
//
// 日历日详情卡片的界面行为测试：
//   - 「其他班组」从一整行文字改成色块列表（6 班组场景不溢出）
//   - 跨午夜班次的时间走 L10n.timeRange，英文界面下不露出中文
//
// 本机没有可运行目标（无 Android 设备 / 无 VS 工具链 / web 被本地通知插件挡住），
// 所以界面行为全部靠 widget 测试覆盖。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/features/calendar/schedule_editor_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

ShiftTemplate _template(String id) =>
    shiftTemplates.firstWhere((t) => t.id == id);

/// 色块 chip 的文本形状：`组名 简称`（例：`二班 休`）。
final _chipPattern = RegExp(r'^[一二三四五六七八九]班 [早中夜休值晚]$');

List<String> _chipTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where(_chipPattern.hasMatch)
    .toList();

/// 造一套真库（内存）+ 一套当前排班，再渲染日历页。
///
/// 落库方式照抄 `createScheduleFromTemplatePicker`：模板提供
/// classes/cycle/班组数/偏移，班组名由创建路径按 teamCount 给满
/// （`L10n.defaultTeamNames`）—— 库出口的补位只是防御性兜底。
///
/// [width] 是逻辑宽度。默认 420（窄屏手机），色块换行的场景用它；
/// 时间串的场景要给宽一点：测试字体每个字符都占满一个字身，英文的
/// `08:00 – 08:00 (next day)` 在测试里比真机宽得多，窄屏会被那个等宽字体
/// 挤出假溢出。
Future<AppDatabase> _pumpCalendar(WidgetTester tester, String templateId,
    {double width = 420}) async {
  final template = _template(templateId);

  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  await AppRepository(db).saveSchedule(
    name: template.subtitle,
    anchorDate: dateOnly(DateTime.now()),
    classes: template.classes,
    cycle: template.cycle,
    makeCurrent: true,
    teamCount: template.teamCount,
    teamNames: L10n.defaultTeamNames(template.teamCount),
    ourTeamIndex: 0,
    teamOffsets: template.teamOffsets,
  );

  // 日历页的数据源是 databaseProvider（activeScheduleProvider 直接 watch 它），
  // 所以要换掉数据库本身，而不是 appRepositoryProvider。
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: CalendarScreen()),
  ));
  await tester.pumpAndSettle();
  return db;
}

/// 库里现有几套排班方案。
Future<int> _scheduleCount(AppDatabase db) async =>
    (await db.select(db.shiftScheduleRows).get()).length;

/// 收尾：主动拆掉界面，并推一下时钟让 drift 取消查询流时排的那个零时长
/// 定时器真的跑掉。
///
/// 不这么做，框架会在测试体结束时自己拆树，随即报
/// 「A Timer is still pending even after the widget tree was disposed」
/// —— drift 的 `StreamQueryStore.markAsClosed` 用 `Timer.run` 延迟清理缓存。
Future<void> _disposeCalendar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  setUpAll(() async {
    // L10n.yearMonth 用 intl DateFormat('zh')，测试里要自己初始化。
    await initializeDateFormatting('zh');
    // 每个测试各建一个内存库做隔离，drift 会为「同名库建了多次」刷警告，这里静音。
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  // 语言从 SharedPreferences 读；默认不写 key → 'zh'。
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('六班三倒（6 个班组）：其他班组渲染 5 个色块，不再拼成一整行',
      (tester) async {
    // 窄屏：6 个色块必须换行，而不是把卡片撑破。
    await _pumpCalendar(tester, 'six_crew_three_shift');

    expect(find.text(L10n.otherCrews), findsOneWidget);

    // 我们是第 1 组 → 剩下 5 组各一个色块（休班的组也要列出）
    final chips = _chipTexts(tester);
    expect(chips, hasLength(5), reason: '6 个班组应当出 5 个色块');
    expect(chips.toSet(), hasLength(5), reason: '每个班组一个色块');
    // 一班是「我」，不该出现；五班/六班的名字由创建路径给满
    expect(chips.map((c) => c.split(' ').first).toSet(),
        {'二班', '三班', '四班', '五班', '六班'});

    // 旧的「一整行文字」形状：`其他班组：组名·班次名　…` 已不复存在
    expect(find.textContaining('${L10n.otherCrews}：'), findsNothing);

    // 窄屏 + 换行布局：不应有 RenderFlex overflow
    expect(tester.takeException(), isNull);

    await _disposeCalendar(tester);
  });

  testWidgets('上 24 休 48：值班当天时间走 L10n，中文界面显示「次日」',
      (tester) async {
    await _pumpCalendar(tester, 'duty_24_48', width: 640);

    expect(L10n.isEn, isFalse);
    expect(find.text('08:00 – 次日08:00'), findsOneWidget);

    await _disposeCalendar(tester);
  });

  testWidgets('上 24 休 48 英文界面：时间用 (next day) 且不露出中文',
      (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await _pumpCalendar(tester, 'duty_24_48', width: 640);

    expect(L10n.isEn, isTrue, reason: '语言应当已从设置里读成 en');
    final time = find.text('08:00 – 08:00 (next day)');
    expect(time, findsOneWidget);

    // 时间这一条里不能有中文（旧实现硬编码「次日」就会漏出来）
    final rendered = tester.widget<Text>(time).data!;
    expect(RegExp(r'[一-鿿]').hasMatch(rendered), isFalse);
    expect(find.textContaining('次日'), findsNothing);

    await _disposeCalendar(tester);
  });

  testWidgets('单班组排班：不渲染「其他班组」那一段', (tester) async {
    await _pumpCalendar(tester, 'standard_week');

    expect(find.text(L10n.otherCrews), findsNothing);
    expect(_chipTexts(tester), isEmpty);

    await _disposeCalendar(tester);
  });

  // ---------------------------------------------------------------------------
  // 日历 → 切换排班 → 新增排班：必须和「我的 → 排班管理」一样走模板选择页。
  // 修前这条路径直接 saveSchedule(defaultSchedule()) 并开一个没有 scheduleId 的
  // 编辑器 —— 从日历进来的用户永远看不到 19 种模板。
  // ---------------------------------------------------------------------------

  testWidgets('日历「新增排班」弹「选择你的倒班方式」；按返回键放弃不建方案',
      (tester) async {
    final db = await _pumpCalendar(tester, 'day_night_rest_rest');
    expect(await _scheduleCount(db), 1, reason: '进入前只有种子方案');

    // 日历右上角「切换排班」→ 弹层里的「新增排班」
    await tester.tap(find.byTooltip(L10n.switchSchedule));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.addSchedule));
    await tester.pumpAndSettle();

    // 关键：日历这条路径现在也弹模板选择页，而不是直接把默认方案落库
    expect(find.text(L10n.pickShiftPattern), findsOneWidget);

    // 按返回键放弃 → 不建方案
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(L10n.pickShiftPattern), findsNothing);
    expect(await _scheduleCount(db), 1,
        reason: '按返回键放弃后不该凭空多出一套方案');

    await _disposeCalendar(tester);
  });

  testWidgets('日历「新增排班」选中的模板真的落库，并进入带 id 的编辑器',
      (tester) async {
    final db = await _pumpCalendar(tester, 'day_night_rest_rest');

    await tester.tap(find.byTooltip(L10n.switchSchedule));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.addSchedule));
    await tester.pumpAndSettle();
    expect(find.text(L10n.pickShiftPattern), findsOneWidget);

    // 选「四班三倒」：周期 8 天，与默认的四班两倒（4 天）不同，能证明用的是模板。
    final target = findTemplate('four_crew_three_shift')!;
    await tester.enterText(find.byType(TextField), '四班三倒');
    await tester.pumpAndSettle();
    await tester.tap(find.text(target.title));
    await tester.pumpAndSettle();

    // 新方案按模板落库：名字 = 模板副标题，周期长度 = 模板周期。
    expect(await _scheduleCount(db), 2);
    final rows = await db.select(db.shiftScheduleRows).get();
    final created = rows.firstWhere((r) => r.name == target.subtitle);
    final domain = await AppRepository(db).getScheduleDomain(created.id);
    expect(domain, isNotNull);
    expect(domain!.cycleLength, target.cycle.length);

    // 弹层关闭，改用带 scheduleId 的编辑器（不再靠 makeCurrent 的隐式约定）。
    expect(find.byType(ScheduleEditorScreen), findsOneWidget);

    await _disposeCalendar(tester);
  });
}
