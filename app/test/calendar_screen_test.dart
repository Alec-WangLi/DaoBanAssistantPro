// app/test/calendar_screen_test.dart
//
// 日历日详情卡片的界面行为测试：
//   - 「其他班组」从一整行文字改成色块列表（6 班组场景不溢出）
//   - 跨午夜班次的时间走 L10n.timeRange，英文界面下不露出中文
//
// 本机没有可运行目标（无 Android 设备 / 无 VS 工具链 / web 被本地通知插件挡住），
// 所以界面行为全部靠 widget 测试覆盖。
import 'dart:math' as math;

import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
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
/// **注意**：`template.classes` 的班次名按 `L10n.locale` 生成，而这里是先
/// 落库再渲染。所以任何改动语言的用例都必须自己还原，否则漏出去的语言会
/// 让下一个用例存下另一种语言的班次名（英文名更长，可能把卡片挤溢出）。
///
/// [width] 是逻辑宽度。默认 420（窄屏手机），色块换行的场景用它；
/// 时间串的场景要给宽一点：测试字体每个字符都占满一个字身，英文的
/// `08:00 – 08:00 (next day)` 在测试里比真机宽得多，窄屏会被那个等宽字体
/// 挤出假溢出。
Future<AppDatabase> _pumpCalendar(WidgetTester tester, String templateId,
    {double width = 420, double height = 1600}) async {
  final template = _template(templateId);

  tester.view.physicalSize = Size(width, height);
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
    // 本用例靠「App 自己从设置里读出 en」来切语言，因此必须自己还原 ——
    // L10n.locale 是全局静态量，泄漏到下个用例会让那边的 saveSchedule
    // 存下英文班次名（模板的班次名按当前语言生成），进而把信息卡挤溢出。
    final prevLocale = L10n.locale;
    addTearDown(() => L10n.locale = prevLocale);

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

  test('横屏：格子高度不再只按宽度算', () {
    // 起因：`cellH = cellW / 0.78` 只按宽度算。横屏 cellW ≈ 125 → cellH ≈ 160，
    // 一个月六行要 960px，一屏只看得到一行多。
    const cellW = 125.0; // (900 − 24) / 7
    final landscape = calendarCellHeight(
      cellW: cellW,
      availHeight: 244, // 横屏扣掉顶栏与信息卡之后
      weekRows: 6,
      weekdayH: 26,
    );
    expect(landscape, lessThan(cellW / 0.78),
        reason: '横屏必须进入压缩分支，不能仍取按宽度算出来的 160');
    expect(landscape, greaterThanOrEqualTo(80),
        reason: '压缩不得低于可读下限，否则要裁字');
  });

  test('竖屏：格子高度与旧公式完全等价', () {
    // 竖屏空间富余，走的还是原来那条「拉高」分支 —— 逐像素不变。
    // fillCellH = (600−26)/5 = 114.8，超过 naturalCellH(72.6)，于是取
    // min(fillCellH, cellW/0.62) = 91.3 —— 与旧代码同一分支、同一算式。
    const cellW = 56.6; // (420 − 24) / 7
    final portrait = calendarCellHeight(
      cellW: cellW,
      availHeight: 600,
      weekRows: 5,
      weekdayH: 26,
    );
    expect(portrait, closeTo(cellW / 0.62, 0.01));
  });

  test('小窗 200 宽：格子高度仍不低于可读下限', () {
    // 起因：小窗（小米小窗实测 200×400）cellW ≈ 25，naturalCellH ≈ 32，
    // 而「不许再瘦」的比例在窄屏放开到 0.46 → cellW / 0.46 ≈ 54。
    // 那时可用高度也还有富余，于是走的是**富余分支**、返回 54 ——
    // 比格子里的三行字（约 51 + 内缩）还矮，整月每个格子都溢出。
    //
    // 下限是「装不下三行字」决定的，跟走哪个分支无关，所以它必须作用在
    // 最终值上。
    const cellW = 25.1; // (200 − 24) / 7
    final small = calendarCellHeight(
      cellW: cellW,
      availHeight: 182, // 小窗扣掉两行顶栏与信息卡之后
      weekRows: 5,
      weekdayH: 26,
      aspectMin: 0.46, // 窄屏放开的那档
    );
    expect(small, greaterThanOrEqualTo(80),
        reason: '富余分支同样要守住可读下限，否则格子装不下日期/班次/农历三行');
    expect(small, greaterThan(cellW / 0.46),
        reason: '按宽度算出来的 54 装不下三行字，下限必须把它顶上去');
  });

  // 用信息卡自己的日期文本定位。不要用 L10n.today —— 「今天」在顶栏按钮和
  // 信息卡的「今天」徽章各出现一次，find.text 会一次命中两个。
  Finder cardDate() =>
      find.text(L10n.monthDayWeekday(dateOnly(DateTime.now())));

  testWidgets('宽屏：日历改左右分栏，信息卡在右不在下', (tester) async {
    await _pumpCalendar(tester, 'four_crew_three_shift', width: 1280);
    expect(tester.getTopLeft(cardDate()).dx, greaterThan(640),
        reason: '宽屏下信息卡应当被排在右栏，而不是底栏');
    await _disposeCalendar(tester);
  });

  testWidgets('竖屏：仍是单栏，信息卡在下方', (tester) async {
    await _pumpCalendar(tester, 'four_crew_three_shift');
    expect(tester.getTopLeft(cardDate()).dx, lessThan(420));
    expect(tester.getTopLeft(cardDate()).dy, greaterThan(600),
        reason: '竖屏下信息卡在底部区域');
    await _disposeCalendar(tester);
  });

  testWidgets('短屏：信息卡压成紧凑版，把高度让给网格', (tester) async {
    await _pumpCalendar(tester, 'four_crew_three_shift');
    final portraitH = tester.getSize(find.byType(GlassTile).last).height;
    await _disposeCalendar(tester);

    await _pumpCalendar(tester, 'four_crew_three_shift',
        width: 420, height: 420);
    final shortH = tester.getSize(find.byType(GlassTile).last).height;
    await _disposeCalendar(tester);

    expect(shortH, lessThan(portraitH),
        reason: '短屏下信息卡应当比竖屏矮，把高度让给网格');
  });

  testWidgets('窄屏：顶栏「今天」收成纯图标钮', (tester) async {
    // 「今天」这两个字在顶栏按钮与信息卡的「今天」徽章里各有一处，
    // 所以数总数：宽屏 2 处，窄屏只剩徽章那 1 处。
    await _pumpCalendar(tester, 'four_crew_three_shift');
    expect(find.text(L10n.today), findsNWidgets(2));
    await _disposeCalendar(tester);

    await _pumpCalendar(tester, 'four_crew_three_shift', width: 320);
    expect(find.text(L10n.today), findsOneWidget,
        reason: '320 宽下顶栏那两个该收起来，只留下信息卡的徽章');
    expect(find.byIcon(Icons.today_outlined), findsWidgets);
    await _disposeCalendar(tester);
  });

  testWidgets('点开某天：信息卡定高，日期格不再跟着一涨一缩', (tester) async {
    // 起因：竖屏是 `Column[顶栏, Expanded(网格), 信息卡]`，格子高度按**剩余
    // 空间**算，所以信息卡随当天内容长高一点，六个格子就集体矮一点。
    // 内容里会变的至少有四处：法定节假日徽章、农历描述换行、其他班组色块
    // 换行、有没有班次/闹钟 —— 点一天晃一次。
    await _pumpCalendar(tester, 'six_crew_three_shift');

    final box = find.byKey(const Key('info-card-box'));
    final cardH = tester.getSize(box).height;

    // 把整月的每一天都点一遍：每天的农历、节气、节日与班次都不一样。
    final daysInMonth =
        DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day;
    var maxContentH = 0.0;
    for (var d = 1; d <= daysInMonth; d++) {
      await tester.tap(find.text('$d').first);
      await tester.pump();
      expect(tester.getSize(box).height, cardH,
          reason: '$d 日：信息卡高度不该随当天内容变，否则格子会跟着伸缩');
      final contentH =
          tester.getSize(find.byKey(const Key('info-card-content'))).height;
      maxContentH = math.max(maxContentH, contentH);
      expect(contentH, lessThanOrEqualTo(cardH),
          reason: '$d 日：卡片内容 $contentH 装不进定高 $cardH');
    }

    // 定高不能只是「足够大」——留太多空白等于白占网格的高度。
    expect(cardH - maxContentH, lessThanOrEqualTo(48),
        reason: '定高 $cardH 比最满的一天（$maxContentH）高出太多，空格子白占网格');

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
