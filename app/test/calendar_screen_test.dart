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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_pressable.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/lunar_info.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/features/calendar/info_card_metrics.dart';
import 'package:shiftassistantpro/features/calendar/schedule_editor_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

ShiftTemplate _template(String id) =>
    shiftTemplates.firstWhere((t) => t.id == id);

/// 色块 chip 的文本形状：`组名 简称`（例：`二班 休`）。
final _chipPattern = RegExp(r'^[一二三四五六七八九]班 [早中夜休值晚]$');

/// 长按拖选用例圈住的那一段日子（闭区间 8…15）。
///
/// 锚点固定取每月的 8 日 / 15 日那两格，**不取「今天」**：今天可能落在网格的
/// 最后一行，往下拖就掉出本月（`_dateFromPosition` 返回 null），区间会只剩一天，
/// 用例于是随机某天转红。而 8 日 → 槽位 `leading + 7` → 网格第 1 行、15 日 →
/// 槽位 `leading + 14` → 第 2 行 —— 任何月份、任何月初偏移下都成立，两格永远
/// 相差一行（= 7 天），所以「往下拖一格」圈住的正是这 8 天。
const int _rangeFirstDay = 8;
const int _rangeLastDay = 15;
const int _rangeSpan = _rangeLastDay - _rangeFirstDay + 1;

/// 玻璃块（选中滑块）当前的缩放：按住/拖拽时 1.22，松手后回到 1.0。
///
/// 用「块的祖先里的 `AnimatedScale`」定位，而不是 `find.byType(AnimatedScale)`：
/// 整页里不止这一处 `AnimatedScale`。
double _blockScale(WidgetTester tester) => tester
    .widget<AnimatedScale>(find.ancestor(
      of: find.byKey(const Key('calendar-selection-block')),
      matching: find.byType(AnimatedScale),
    ))
    .scale;

/// 屏幕上还剩几格范围淡染 —— 只数 8…15 这 8 格，所以 `_rangeSpan` 既表示
/// 「8 格都在」也表示「没有多画」。
int _rangeTintCount(WidgetTester tester) {
  var n = 0;
  for (var d = _rangeFirstDay; d <= _rangeLastDay; d++) {
    if (tester.any(find.byKey(ValueKey('day-range-$d')))) n++;
  }
  return n;
}

List<String> _chipTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where(_chipPattern.hasMatch)
    .toList();

/// 信息卡「班次名 · 时间 · 闹钟」那一行的纯文本。
///
/// 三段并成了一段富文本（为了让省略号从尾部、也就是最不重要的闹钟开始截），
/// 所以整行内容要从 `textSpan` 上取，不能按独立 `Text` 去找。
String _shiftLine(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('info-card-shift-line')))
    .textSpan!
    .toPlainText();

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
///
/// [blank] 造「跟随法定节假日（无班次）」那种空白表：形状照抄编辑器的
/// `_followHolidayCard`（周期为空 → `isBlank`，班组收敛成「我」一个人）。
Future<AppDatabase> _pumpCalendar(WidgetTester tester, String templateId,
    {double width = 420, double height = 1600, bool blank = false}) async {
  final template = _template(templateId);

  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  await AppRepository(db).saveSchedule(
    name: blank ? L10n.holidayScheduleName : template.subtitle,
    anchorDate: dateOnly(DateTime.now()),
    classes: blank ? const [] : template.classes,
    cycle: blank ? const [] : template.cycle,
    makeCurrent: true,
    teamCount: blank ? 1 : template.teamCount,
    teamNames: blank
        ? [L10n.isEn ? 'Me' : '我']
        : L10n.defaultTeamNames(template.teamCount),
    ourTeamIndex: 0,
    teamOffsets: blank ? const [] : template.teamOffsets,
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
    // 班次名、时间、闹钟并成了一段富文本（见 info-card-shift-line 的说明），
    // 所以按整行的纯文本断言，而不是找独立的 Text。
    expect(_shiftLine(tester), contains('08:00 – 次日08:00'));

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
    final rendered = _shiftLine(tester);
    expect(rendered, contains('08:00 – 08:00 (next day)'));

    // 时间那一段里不能有中文（旧实现硬编码「次日」就会漏出来）。
    // 只查时间那一段：数据库里存的班次名是按**存库时**的语言生成的，而
    // 存库发生在 App 读出设置之前，所以它还是中文 —— 那是另一回事。
    final spans = (tester
            .widget<Text>(find.byKey(const Key('info-card-shift-line')))
            .textSpan! as TextSpan)
        .children!
        .whereType<TextSpan>();
    final timeSpan = spans.firstWhere((s) => (s.text ?? '').contains('08:00'));
    expect(RegExp(r'[一-鿿]').hasMatch(timeSpan.text!), isFalse);
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
    expect(landscape, greaterThanOrEqualTo(58),
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
    expect(small, greaterThanOrEqualTo(58),
        reason: '富余分支同样要守住可读下限，否则格子装不下日期/班次/农历三行');
    expect(small, greaterThan(cellW / 0.46),
        reason: '按宽度算出来的 54 装不下三行字，下限必须把它顶上去');
  });

  // 回归：v0.6.5 用户实测「最后一行被信息卡压住」。
  //
  // 真因不是「格子算高了一点点」，而是可读下限被抬到了内容需求之上：
  // 三行字（18/12/11，行盒 height 1.15 压过）实测只要 ≈52，加格子内缩 4
  // 约 56，而当时的下限是 80 —— 于是在 400×869 的手机上，五行的月份被顶到
  // 26+5×80=426、六行的顶到 506，双双超过只有 405 的网格视口，最后一行
  // 被 `SingleChildScrollView` 裁在信息卡上沿（多出来的部分要靠滚动才看得到，
  // 用户读到的就是「被卡片压住」）。
  //
  // 这里盯的是**不变量**：只要空间放得下可读下限，网格内容就不得高于视口。
  test('竖屏 400×869：四/五/六行月份都要完整落在网格视口里，不许滚动', () {
    // 小米 25102RKBEC：1200×2608 @3.0 → 400×869.33；
    // 扣状态栏 48、导航栏 20、顶栏 56、信息卡块（8 + 248 + 84）340 → 405.33。
    const cellW = (400 - 24) / 7;
    const viewport = 405.33;
    for (final rows in [4, 5, 6]) {
      final cellH = calendarCellHeight(
        cellW: cellW,
        availHeight: viewport - 2, // 网格自己留的亚像素余量
        weekRows: rows,
        weekdayH: 26,
      );
      expect(26 + rows * cellH, lessThanOrEqualTo(viewport),
          reason: '$rows 行：内容高过视口就会被裁掉最后一行（v0.6.5 用户实测）');
    }
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

  testWidgets('点开某天：信息卡高度只由本月决定，不随选中哪天变', (tester) async {
    // 起因：竖屏是 `Column[顶栏, Expanded(网格), 信息卡]`，格子高度按**剩余
    // 空间**算，所以信息卡随当天内容长高一点，六个格子就集体矮一点。
    // 内容里会变的至少有四处：法定节假日徽章、农历描述换行、其他班组色块
    // 换行、有没有班次/闹钟 —— 点一天晃一次。
    //
    // v0.6.10 起高度是**算**出来的（`info_card_metrics.dart`）：取本月最满的
    // 一天。所以这里同时盯两件事 —— 月内恒定，且紧到不留白。
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
          reason: '$d 日：卡片内容 $contentH 装不进卡片 $cardH');
    }

    // 高度 = 本月最满的一天 + 卡片自身的上下内边距与描边，且**刚好**是这个值：
    // 留多了就是白占网格的高度（这正是写死 248 时的毛病），留少了就要裁字。
    // 允许 2dp 的取整余量。
    //
    // 卡片上下内边距是 `spaceLg`(16)×2，描边是 `Border.all(width: 1)`×2 ——
    // 与 `info_card_metrics.dart` 的 `_cardChromeV` 同一个算式，别再写死。
    final inner = cardH - (AppTokens.spaceLg * 2 + 2);
    expect(inner - maxContentH, greaterThanOrEqualTo(0),
        reason: '本月最满的一天 $maxContentH 装不进卡片内高 $inner');
    expect(inner - maxContentH, lessThanOrEqualTo(2),
        reason: '卡片内高 $inner 比最满的一天 $maxContentH 高出太多，空格子白占网格');

    await _disposeCalendar(tester);
  });

  testWidgets('信息卡高度跟着「其他班组」占几行走', (tester) async {
    // 高度的逐日差异只有三处：节假日徽章、农历行数、其他班组色块折行数。
    // 前两处是「本月有没有」，第三处是「这个排班有几个班组」—— 班组越多色块
    // 占的行越多，卡片越高。这条用例盯住它确实跟着变（否则高度就是写死的）。
    final heights = <String, double>{};
    for (final t in ['four_crew_three_shift', 'six_crew_three_shift']) {
      await _pumpCalendar(tester, t);
      heights[t] = tester.getSize(find.byKey(const Key('info-card-box'))).height;
      await _disposeCalendar(tester);
    }

    expect(heights['six_crew_three_shift'],
        greaterThan(heights['four_crew_three_shift']!),
        reason: '六个班组的色块比四个班组多占行，卡片该更高');
  });

  testWidgets('没有法定节假日的月份：卡片更矮，网格拿到更多高度', (tester) async {
    // 「换月时高度可能变一次」是这套做法的代价，也是它的收益：没有节假日的
    // 月份不必为节假日徽章那一行留着空。这里盯住收益真的兑现了 —— 卡片变矮，
    // 而矮下来的高度确实还给了网格。
    await _pumpCalendar(tester, 'four_crew_three_shift');

    final box = find.byKey(const Key('info-card-box'));
    final grid = find.byType(SingleChildScrollView).first;

    DateTime? plainMonth;
    DateTime? holidayMonth;
    var plainCardH = 0.0;
    var plainGridH = 0.0;
    var holidayCardH = 0.0;
    var holidayGridH = 0.0;
    final start = DateTime(DateTime.now().year, DateTime.now().month, 1);
    for (var i = 0; i < 24 && (plainMonth == null || holidayMonth == null); i++) {
      if (i > 0) {
        await tester.tap(find.byIcon(Icons.chevron_right_outlined));
        await tester.pumpAndSettle();
      }
      final m = DateTime(start.year, start.month + i, 1);
      final days = DateTime(m.year, m.month + 1, 0).day;
      final hasHoliday = List.generate(
              days, (k) => lunarOf(DateTime(m.year, m.month, k + 1)))
          .any((l) => l.isLegalHoliday);
      if (hasHoliday) {
        holidayMonth ??= m;
      } else {
        plainMonth ??= m;
      }

      if (m == plainMonth) plainCardH = tester.getSize(box).height;
      if (m == plainMonth) plainGridH = tester.getSize(grid).height;
      if (m == holidayMonth) holidayCardH = tester.getSize(box).height;
      if (m == holidayMonth) holidayGridH = tester.getSize(grid).height;
    }

    expect(plainMonth, isNotNull, reason: '两年内总该有一个月没有法定节假日');
    expect(holidayMonth, isNotNull, reason: '两年内总该有一个月有法定节假日');
    expect(plainCardH, lessThan(holidayCardH),
        reason: '没有节假日的月份不该留着徽章那一行的高度');
    expect(plainGridH, greaterThan(holidayGridH),
        reason: '卡片矮下来的高度要真的给到网格，而不是留在空档里');

    await _disposeCalendar(tester);
  });

  // 回归：v0.6.6 用户实测「信息卡最左侧那根色条错位，且不跟卡片变高变矮」。
  //
  // 根因是色条与面板各量各的高度：`Stack` 默认 `StackFit.loose`，只给非定位
  // 子节点松约束，面板于是缩到内容高度（用户那天 126）；而色条是
  // `Positioned(top: 18, bottom: 18)`（现值 `spaceLg`=16），量的是外面那个定高
  // 盒子（248）—— 于是色条比卡片长出 86dp 垂在空白里。修法是底栏时让面板撑满
  // 定高，两边同源。
  testWidgets('底栏信息卡：面板撑满定高，色条与面板上下对齐', (tester) async {
    await _pumpCalendar(tester, 'four_crew_three_shift');

    final box = tester.getRect(find.byKey(const Key('info-card-box')));
    final panel = tester.getRect(find.byKey(const Key('info-card-panel')));
    final bar = tester.getRect(find.byKey(const Key('info-card-accent-bar')));

    expect(panel.height, closeTo(box.height, 0.5),
        reason: '面板要撑满定高盒子；否则色条按盒子高度画、会探出卡片的下沿');
    expect(bar.top - panel.top, closeTo(AppTokens.spaceLg, 0.5),
        reason: '色条上端贴着面板内容区的上沿');
    expect(panel.bottom - bar.bottom, closeTo(AppTokens.spaceLg, 0.5),
        reason: '色条下端贴着面板内容区的下沿');

    await _disposeCalendar(tester);
  });

  // 回归：卡片是**定高**的，内容装不下时靠卡内滚动兜底 —— 也就是说内容一旦
  // 超过可用高度，最后一行就被底边裁掉，而卡片本身不会变大去提醒你。
  // v0.6.7 实测：六班组那种排满的日子内容已经 224dp，可用只有 210dp，
  // 「其他班组」最后一行被裁掉一截。这条不变量盯住它。
  testWidgets('底栏信息卡：最满的一天也要装得进卡片，不靠卡内滚动', (tester) async {
    await _pumpCalendar(tester, 'six_crew_three_shift');

    // 可用高度 = 定高 − 上下 padding(spaceLg=16 ×2) − 上下描边(1×2)。描边那 2px
    // 来自 GlassPanel 的 `Border.all(width: 1)`，`Container` 会把它算进自己的
    // 内边距。与 `info_card_metrics.dart` 的 `_cardChromeV` 同一个算式。
    final inner = tester.getSize(find.byKey(const Key('info-card-box'))).height -
        (AppTokens.spaceLg * 2 + 2);

    final daysInMonth =
        DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day;
    for (var d = 1; d <= daysInMonth; d++) {
      await tester.tap(find.text('$d').first);
      await tester.pump();
      final contentH =
          tester.getSize(find.byKey(const Key('info-card-content'))).height;
      expect(contentH, lessThanOrEqualTo(inner),
          reason: '$d 日：内容 $contentH 高过卡片内部的 $inner，'
              '最后一行会被底边裁掉');
    }

    await _disposeCalendar(tester);
  });

  // 回归：v0.6.7 用户实测「法定节假日徽章太宽，把农历挤到右边，两行都显示不全」。
  // 徽章连图标带「法定节假日 · 」有一百多 dp，和农历并排时农历只剩一半宽度。
  testWidgets('信息卡：节假日徽章自占一行，农历独占下一行且不再被挤到右边',
      (tester) async {
    await _pumpCalendar(tester, 'four_crew_three_shift');

    // 找出本月的第一个法定节假日（中秋那种）。
    final badgeFinder = find.byKey(const Key('info-card-holiday-badge'));
    final daysInMonth =
        DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day;
    var found = false;
    for (var d = 1; d <= daysInMonth && !found; d++) {
      await tester.tap(find.text('$d').first);
      await tester.pump();
      found = badgeFinder.evaluate().isNotEmpty;
    }
    expect(found, isTrue, reason: '本月应当有法定节假日，否则这条用例没有意义');

    final badge = tester.getRect(badgeFinder);
    final lunar = tester.getRect(find.textContaining('农历').first);
    final content = tester.getRect(find.byKey(const Key('info-card-content')));

    expect(lunar.top, greaterThanOrEqualTo(badge.bottom - 0.5),
        reason: '农历要排在徽章**下面**，不再和它挤同一行');
    expect(lunar.left, closeTo(content.left, 0.5),
        reason: '农历要从内容区左边起排（占满整行），而不是被徽章推到右边');

    await _disposeCalendar(tester);
  });

  // 对比度审计跑不到节假日徽章：工装渲染的日历选中的是「今天」，而今天未必是
  // 节假日，徽章根本不出现在图里。这条直接在控件树上量它的真配色补上缺口 ——
  // v0.6.8 之前它用原色红压在同色淡底上，浅深两套主题都只有 3.4:1。
  testWidgets('节假日徽章：文字与淡染底要过 AA 对比度', (tester) async {
    await _pumpCalendar(tester, 'four_crew_three_shift');

    final badgeFinder = find.byKey(const Key('info-card-holiday-badge'));
    final daysInMonth =
        DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day;
    for (var d = 1; d <= daysInMonth; d++) {
      await tester.tap(find.text('$d').first);
      await tester.pump();
      if (badgeFinder.evaluate().isNotEmpty) break;
    }
    expect(badgeFinder, findsOneWidget, reason: '本月应当有法定节假日');

    final text = tester.widget<Text>(
        find.descendant(of: badgeFinder, matching: find.byType(Text)).first);
    // 分隔用的纯空白 span 没有样式，跳过。
    final spans = (text.textSpan! as TextSpan)
        .children!
        .whereType<TextSpan>()
        .where((s) => s.style?.color != null);
    final surface = Theme.of(tester.element(badgeFinder)).colorScheme.surface;
    final bg =
        Color.alphaBlend(AppTokens.holiday.withValues(alpha: 0.14), surface);
    for (final span in spans) {
      final ink = span.style!.color!;
      expect(AppTokens.contrastRatio(ink, bg), greaterThanOrEqualTo(4.5),
          reason: '「${span.text!.trim()}」压在徽章底上对比度不够 AA');
    }

    await _disposeCalendar(tester);
  });

  testWidgets('信息卡：班次名、时间、闹钟在同一行', (tester) async {
    await _pumpCalendar(tester, 'four_crew_three_shift');
    // 默认选中今天；先点一个「上夜班」的日子，让时间与闹钟都出来。
    await tester.tap(find.text('${DateTime.now().day}').first);
    await tester.pump();

    final line = _shiftLine(tester);
    expect(line, contains('闹钟'), reason: '闹钟要并进班次那一行，不再单独占一行');
    expect(
      tester
          .widget<Text>(find.byKey(const Key('info-card-shift-line')))
          .maxLines,
      1,
      reason: '整行只占一行文字，这就是「并进同一行」的落点',
    );

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

  testWidgets('格子班次胶囊：选中那天实心（班次色 100%），其余淡染', (tester) async {
    await _pumpCalendar(tester, 'white_white_night_night_rest_rest');

    // 胶囊底色 = 班次色按 alpha 合成，所以 alpha 就是「实心 / 淡染」的判据。
    // 读 `AnimatedContainer` 上的 `decoration`（目标值）：补间进行中也断言目标，
    // 与「落地后应该是什么」一致。
    BoxDecoration chipDeco(int day) =>
        tester.widget<AnimatedContainer>(find.byKey(ValueKey('day-chip-$day')))
            .decoration! as BoxDecoration;
    double chipAlpha(int day) => chipDeco(day).color!.a;

    final today = DateTime.now().day;
    final other = today == 1 ? 2 : 1;

    // 初始选中「今天」（`initState` 就把 `_selected` 设成今天）。
    expect(chipAlpha(today), closeTo(1.0, 1e-6),
        reason: '选中那天的胶囊要实心 —— 首帧就选中的日子也必须生效，'
            '这里曾经因为底色走 AnimatedContainer 而停在淡染');
    expect(chipAlpha(other), closeTo(0.14, 1e-6), reason: '没选中的那天要淡染');

    // 换选一天：实心跟着走。
    await tester.tap(find.text('$other').first);
    await tester.pumpAndSettle();
    expect(chipAlpha(other), closeTo(1.0, 1e-6));
    expect(chipAlpha(today), closeTo(0.14, 1e-6));

    await _disposeCalendar(tester);
  });

  testWidgets('格子班次胶囊：实心时文字色取 onSolid，且与底色过 AA', (tester) async {
    await _pumpCalendar(tester, 'white_white_night_night_rest_rest');
    final today = DateTime.now().day;

    final chip = tester.widget<AnimatedContainer>(
        find.byKey(ValueKey('day-chip-$today')));
    final deco = chip.decoration! as BoxDecoration;
    final ink = tester
        .widget<Text>(find.descendant(
            of: find.byKey(ValueKey('day-chip-$today')),
            matching: find.byType(Text)))
        .style!
        .color!;

    // 实心胶囊只有「白或黑」两种文字色（`onSolid`），且对任何底色都 ≥ 4.58:1。
    expect(ink, AppTokens.onSolid(deco.color!));
    expect(AppTokens.contrastRatio(ink, deco.color!), greaterThanOrEqualTo(4.5));

    await _disposeCalendar(tester);
  });

  testWidgets('选中块：不能带 boxShadow —— 阴影会从半透明块内透出来洗掉胶囊色相',
      (tester) async {
    await _pumpCalendar(tester, 'white_white_night_night_rest_rest');

    final block = tester
        .widget<Container>(find.byKey(const Key('calendar-selection-block')));
    final deco = block.decoration! as BoxDecoration;

    // 这一层画在网格之上，必须半透明（不透明会把选中那格的内容整个糊掉），
    // 于是任何 boxShadow 都会从块内部透出来再叠一层主色：实测格子内部吃到
    // 约 33% 主色，橙 `#FF9F0A` 的实心胶囊被洗成棕 `#C28758`。
    expect(deco.boxShadow, anyOf(isNull, isEmpty),
        reason: '选中块只留 2px 主色描边 + 13% 淡染，不要阴影');
    expect(deco.color!.a, lessThan(1.0), reason: '填充必须半透明，内容才看得见');

    await _disposeCalendar(tester);
  });

  testWidgets('选中块：圆角必须与格子卡片同源 —— 差一档就从四个角露出卡片',
      (tester) async {
    // v0.7.3 真机实测：块走 radiusL(22)、卡片走 radiusM(16)，两者尺寸与位置
    // 完全一致（同 inset、同一格），于是四个角各露出一条约 4dp 的月牙 ——
    // 看起来就是「滑块没把日期格子盖住」。两处现在都取 `_cellRadius`，
    // 这条用例钉着它们相等：哪天有人只改其中一边，这里会红。
    await _pumpCalendar(tester, 'white_white_night_night_rest_rest');
    final today = DateTime.now().day;

    final blockRadius = (tester
            .widget<Container>(find.byKey(const Key('calendar-selection-block')))
            .decoration! as BoxDecoration)
        .borderRadius;
    final cardRadius = (tester
            .widget<Container>(find.byKey(ValueKey('day-card-$today')))
            .decoration! as BoxDecoration)
        .borderRadius;

    expect(blockRadius, cardRadius,
        reason: '选中块盖在同一格上，圆角大一点就会在四个角露出底下的卡片');

    await _disposeCalendar(tester);
  });

  testWidgets('格子班次胶囊：简称套在 FittedBox 里，不靠算宽度', (tester) async {
    // v0.7.1 的坑：胶囊字号原本按「字数 × 基准字号」硬算可用宽度，是**零余量**
    // 的 —— 两字简称差一点点就退化成「上…」，系统字号一放大整串字都没了
    // （真机实测）。改成让 FittedBox 按实际排版缩，这里钉住那个兜底还在。
    await _pumpCalendar(tester, 'white_white_night_night_rest_rest');

    final chip = find.byKey(ValueKey('day-chip-${DateTime.now().day}'));
    expect(chip, findsOneWidget, reason: '今天那格应该有班次胶囊');
    expect(find.descendant(of: chip, matching: find.byType(FittedBox)),
        findsOneWidget,
        reason: '胶囊文字必须套 FittedBox 兜底（宽度算不准，让排版自己缩）');

    await _disposeCalendar(tester);
  });

  testWidgets('信息卡待办提示：选中那天有待办才显示，且不改变卡片高度', (tester) async {
    final db = await _pumpCalendar(tester, 'white_white_night_night_rest_rest');
    final today = dateOnly(DateTime.now());
    await AppRepository(db).addEvent(
      title: '交体检报告',
      date: today,
      timeMinute: 14 * 60 + 30,
      advanceRemindMinutes: 15,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('info-card-todo-hint')), findsOneWidget);
    expect(find.text(L10n.todoCount(1)), findsOneWidget);
    final heightOnTodoDay =
        tester.getSize(find.byKey(const Key('info-card-box'))).height;

    // 换到本月里没待办的一天：提示要消失，而卡片高度必须**一点不变** ——
    // 它是定高的（`info_card_metrics.dart`），变一点上面的格子就跟着抖。
    final other = today.day == 1 ? 2 : 1;
    await tester.tap(find.text('$other').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('info-card-todo-hint')), findsNothing);
    expect(tester.getSize(find.byKey(const Key('info-card-box'))).height,
        heightOnTodoDay,
        reason: '有没有待办提示都不该改变卡片高度');

    await _disposeCalendar(tester);
  });

  testWidgets('信息卡待办提示：窄屏不显示（放不下，会挤掉日期的字）', (tester) async {
    final db = await _pumpCalendar(tester, 'white_white_night_night_rest_rest',
        width: 320);
    await AppRepository(db).addEvent(
      title: '交体检报告',
      date: dateOnly(DateTime.now()),
      timeMinute: 14 * 60,
      advanceRemindMinutes: 15,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('info-card-todo-hint')), findsNothing);

    await _disposeCalendar(tester);
  });

  testWidgets('信息卡那行班次可点，弹层选中后日历跟着变', (tester) async {
    final db = await _pumpCalendar(tester, 'day_night_rest_rest');
    final today = dateOnly(DateTime.now());

    // 点开入口
    await tester.tap(find.byKey(const Key('info-card-shift-line')));
    await tester.pumpAndSettle();
    expect(find.text(L10n.adjustShift), findsNothing,
        reason: '标题是日期区间，不是「调整班次」四个字');

    // 挑一个与当前不同的班次
    final before = _shiftLine(tester);
    final classes = await db.select(db.shiftClassRows).get();
    final target = classes.firstWhere((c) => !before.contains(c.name));

    await tester.tap(find.text(target.name).last);
    await tester.pumpAndSettle();

    // 落库了
    final rows = await db.select(db.shiftDayOverrides).get();
    expect(rows, hasLength(1));
    expect(rows.single.day, dayNumber(today));
    expect(rows.single.classId, target.id);

    // 界面上那天换了班
    expect(_shiftLine(tester), contains(target.name));
    // 并且带上「已调整」标记
    expect(find.text(L10n.adjusted), findsWidgets);

    await _disposeCalendar(tester);
  });

  // ── spec §11：唯一一条撤掉按天调整的路 —— 「恢复轮转」 ──
  //
  // 改班那条路（`setDayOverrides`）上面已经钉住了；撤回来这条（`choice.restore`
  // → `repo.clearDayOverrides(days)`，`adjustDays` 里那两行）此前**一次也没跑过**。
  // 它要是接错了（比如清了别的日子、或者干脆没清），日历上那天会一直挂着
  // 「已调整」，用户再也回不到轮转。
  testWidgets('信息卡弹层选「恢复轮转」：覆盖行清掉，「已调整」也不再显示',
      (tester) async {
    final db = await _pumpCalendar(tester, 'day_night_rest_rest');
    final today = dateOnly(DateTime.now());

    // 先造出「今天被单独改过」的状态
    final classes = await db.select(db.shiftClassRows).get();
    await AppRepository(db).setDayOverrides([today], classId: classes.first.id);
    await tester.pumpAndSettle();

    expect(await db.select(db.shiftDayOverrides).get(), hasLength(1));
    expect(find.byKey(const Key('info-card-adjusted')), findsOneWidget);
    expect(find.byKey(ValueKey('day-adjusted-${today.day}')), findsOneWidget);

    // 点开信息卡那行（入口就是它），底部弹层里挑「恢复轮转」
    await tester.tap(find.byKey(const Key('info-card-shift-entry')));
    await tester.pumpAndSettle();
    expect(find.text(L10n.restoreRotation), findsOneWidget,
        reason: '这天被覆盖过，弹层才该给这条退路');

    await tester.tap(find.text(L10n.restoreRotation));
    await tester.pumpAndSettle();

    // 覆盖行清干净，界面回到轮转态
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty,
        reason: '「恢复轮转」要把这天的覆盖行真的删掉');
    expect(find.byKey(const Key('info-card-adjusted')), findsNothing,
        reason: '覆盖没了，「已调整」这句说明也要跟着消失');
    expect(find.byKey(ValueKey('day-adjusted-${today.day}')), findsNothing,
        reason: '格子上的小圆点同理');
    // 这里不断「已把 1 天恢复为轮转」那条提示：`adjustDays` 走完
    // `clearDayOverrides` 之后还要 `await AlarmService.rescheduleAll(repo)`，
    // 而那一串原生插件调用在 flutter_test 里不会 resolve（上一版我试着多
    // `pump` 了 20 秒假时钟，SnackBar 依然是 0 —— 换成「改班」那条路同样为 0，
    // 所以是环境如此，不是恢复这条路的毛病）。提示条因此测不到，覆盖行与
    // 「已调整」标记这两条是这条用例真正要钉住的东西。

    await _disposeCalendar(tester);
  });

  testWidgets('没被覆盖过的那天：弹层不给「恢复轮转」', (tester) async {
    await _pumpCalendar(tester, 'day_night_rest_rest');

    await tester.tap(find.byKey(const Key('info-card-shift-entry')));
    await tester.pumpAndSettle();

    expect(find.text(L10n.restoreRotation), findsNothing,
        reason: '本来就在轮转上，没有可恢复的东西 —— 这条由 canRestore 把住');

    await _disposeCalendar(tester);
  });

  testWidgets('被覆盖的那天在格子上有小圆点标记', (tester) async {
    final db = await _pumpCalendar(tester, 'day_night_rest_rest');
    final today = dateOnly(DateTime.now());

    expect(find.byKey(ValueKey('day-adjusted-${today.day}')), findsNothing);

    final classes = await db.select(db.shiftClassRows).get();
    final repo = AppRepository(db);
    await repo.setDayOverrides([today], classId: classes.first.id);
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('day-adjusted-${today.day}')), findsOneWidget,
        reason: '被调整过的那天要有可辨认的标记');

    // spec §7.4：小圆点**固定在 3–4dp、不跟格子高度缩放**。这里断的是规格
    // 区间而不是复述令牌 —— 上一版用的 `gapHair`（2）正好落在规格点名的
    // 「小窗里缩到 1–2px 就等于没有」那一段里，这条断言能把它拦下来。
    final dot =
        tester.getSize(find.byKey(ValueKey('day-adjusted-${today.day}')));
    expect(dot.width, inInclusiveRange(3, 4));
    expect(dot.height, inInclusiveRange(3, 4));

    await _disposeCalendar(tester);
  });

  // 设计语言：新加的东西要抄**最近的同类件配方**。
  //
  // 「已调整」原先是班次行里唯一的**裸文字** —— 而同一页的两个邻居（日期行上的
  // 「今天」「N 项待办」徽章）都是胶囊。三种形状并排，看着就散。所以它改抄
  // `_todoHintBadge` 的配方（14% 淡染底 + 45% 同色描边 + `radiusL` + `inkFor`），
  // 只是不带图标。
  //
  // ⚠️ 这条用例**只**钉形状，**不**钉「卡片高度不因标记而变」—— 那个说法是错的：
  // 高度按**月**预留（`hasOverrideHint`，与 `hasTodoHint` 同一条路），所以「本月
  // 一天覆盖也没有」与「本月有被调过的日子」两个月份之间高度**本来就该不一样**。
  // 写成「加覆盖前后高度相同」等于断言那条按月闸门的反面，而且它还会绿 ——
  // 只因测试字体下胶囊（21.8）比班次行（22.88）矮；等哪天有人把胶囊做高一点，
  // 它会红，下一个人就会去「修」掉按月预留下来。形状与模型分开钉，各钉各的。
  testWidgets('「已调整」是胶囊而不是裸文字', (tester) async {
    final db = await _pumpCalendar(tester, 'day_night_rest_rest');

    final classes = await db.select(db.shiftClassRows).get();
    final repo = AppRepository(db);
    final today = dateOnly(DateTime.now());
    await repo.setDayOverrides([today], classId: classes.first.id);
    await tester.pumpAndSettle();

    // 标记还在，而且**它自己**就是一颗胶囊（不是裸 Text）。
    //
    // 注意 key 就挂在那个 Container 上，所以要用 `tester.widget<Container>` 直接
    // 看它自己 —— `find.ancestor(of: marker, …)` 找的是它的**祖先**，不含它本身，
    // 那样写会恒为空、用例假失败。
    final marker = find.byKey(const Key('info-card-adjusted'));
    expect(marker, findsOneWidget);
    final deco =
        tester.widget<Container>(marker).decoration as BoxDecoration?;
    expect(deco?.borderRadius, isNotNull,
        reason: '「已调整」要与同一行另外两个徽章一样是胶囊');
    expect(deco?.border, isNotNull, reason: '信息胶囊是「淡染底 + 同色描边」两件套');

    await _disposeCalendar(tester);
  });

  // 「胶囊高度真的进了定高模型」这件事在这里量 —— 界面侧量不到它。
  //
  // 界面侧量不到的原因是个字体巧合：`DefaultTextStyle` 走的 Material 排版表行高
  // 1.43，班次行是 16px 的一行字 → 22.88，而胶囊是 12px×1.15 + 上下内边距 6 +
  // 描边 2 = 21.8 —— 胶囊**比班次行还矮**，顶不动行高，所以界面高度对「模型有
  // 没有算它」逐像素不敏感。（真机上字体行高比例一变，胶囊就会成为行里的最高件，
  // 那时它必须已经被算进取大。）
  //
  // 所以这里直接调 `measureBottomInfoCardHeight`，并换一个**紧行高**的
  // `DefaultTextStyle` 把差别放大出来：行高压到 1.0 后班次行只有 16.0，胶囊 21.8
  // 成了行里最高件 —— `hasOverrideHint` 的取舍立刻可见、也确实能失败（把
  // `_adjustedBadgeH` 从取大列表里拿掉，这条即红）。
  //
  // **残留缺口**（控制器已知并记在账上）：它证明的是「模型的这一项是通的」，
  // 而**不**证明「同一个月里换选中哪天高度不变」—— 后者在本夹具里被同一个字体
  // 巧合遮住（高度对逐日差异不敏感），本套件不钉。
  testWidgets('定高模型：「本月有被调整的日子」要为「已调整」胶囊多留高度', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: DefaultTextStyle(
        // 只压行高，字号/字重照旧走角色令牌（模型内部自带）。
        style: const TextStyle(height: 1.0),
        child: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ),
    ));

    double cardH({required bool hasOverrideHint}) => measureBottomInfoCardHeight(
          context: ctx,
          cardOuterWidth: 420,
          // 这一条只盯班次行：不挂排班就没有色块那一段的干扰。
          schedule: null,
          month: DateTime(2026, 9, 1),
          hasTodoHint: false,
          hasOverrideHint: hasOverrideHint,
        );

    expect(cardH(hasOverrideHint: true), greaterThan(cardH(hasOverrideHint: false)),
        reason: '这个月有被按天调过的日子时，班次行要按「已调整」胶囊的高度预留 —— '
            '少了这一步，真机上有标记的那天卡片内容会顶出定高');

    await _disposeCalendar(tester);
  });

  // ── 长按拖选一段日子 ──
  //
  // 两端固定取 `_rangeFirstDay` / `_rangeLastDay`（见文件头：为什么不用「今天」）。
  // 拖动距离 60：实测测试面上格子高约 91（420 宽 / 1600 高），60 落在
  // 「半格 < 60 < 一格半」之间 —— 从格子中心往下拖必落到下一行，且只落一行。

  /// 长按 [fromDay] 那一格，松开时停在 `fromDay + stepRows * 7` 那一格。
  ///
  /// [midDrag] 在**手指还没抬起**时调用：范围淡染是瞬时的（松手就收），要断言
  /// 「圈住了哪几格 / 有没有进范围态」只能卡在这个时刻看。
  Future<void> longPressDragCell(
      WidgetTester tester, int fromDay, int stepRows,
      {Future<void> Function()? midDrag}) async {
    final start = tester.getCenter(find.byKey(ValueKey('day-card-$fromDay')));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600)); // 过长按判定
    await gesture.moveBy(Offset(0, 60.0 * stepRows));      // 每 60 ≈ 一行
    await tester.pump();
    if (midDrag != null) await midDrag();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('长按拖选一段日子后弹层改多天', (tester) async {
    final db = await _pumpCalendar(tester, 'day_night_rest_rest');

    // 长按「8 日」那格，往下拖一格 → 圈住 8…15 共 8 天
    await longPressDragCell(tester, _rangeFirstDay, 1);

    // 弹层出来了，标题是「起点 – 终点 · 8 天」
    expect(find.textContaining('$_rangeSpan 天'), findsOneWidget);

    final classes = await db.select(db.shiftClassRows).get();
    await tester.tap(find.text(classes.first.name).last);
    await tester.pumpAndSettle();

    // 圈住的那 8 天都要落库，而且**就是这 8 天**（不是数目对、日子错）。
    final rows = await db.select(db.shiftDayOverrides).get();
    final now = DateTime.now();
    expect(
        rows.map((r) => r.day).toSet(),
        {
          for (var d = _rangeFirstDay; d <= _rangeLastDay; d++)
            dayNumber(DateTime(now.year, now.month, d)),
        },
        reason: '圈住的 8…15 每一天都要落库');
    expect(rows.map((r) => r.classId).toSet(), {classes.first.id});

    await _disposeCalendar(tester);
  });

  testWidgets('长按向上拖选：起点在终点之后，区间要归一成正序', (tester) async {
    // 拖回去（15 日 → 8 日）时 `_rangeAnchor` 是**后**一天、`_rangeFocus` 是
    // **前**一天。`adjustDays` 不认 `from > to`（会静默拼出空列表、弹一条
    // 误导的提示），所以松手前必须把两端调换成正序 —— 这条用例钉住那步。
    final db = await _pumpCalendar(tester, 'day_night_rest_rest');

    await longPressDragCell(tester, _rangeLastDay, -1); // 往上拖一格

    expect(find.textContaining('$_rangeSpan 天'), findsOneWidget,
        reason: '起点在后、终点在前，区间跨度仍是 8 天');

    final classes = await db.select(db.shiftClassRows).get();
    await tester.tap(find.text(classes.first.name).last);
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final rows = await db.select(db.shiftDayOverrides).get();
    expect(
        rows.map((r) => r.day).toSet(),
        {
          for (var d = _rangeFirstDay; d <= _rangeLastDay; d++)
            dayNumber(DateTime(now.year, now.month, d)),
        },
        reason: '归一之后落的还是 8…15 这 8 天，不是空区间');

    await _disposeCalendar(tester);
  });

  // 长按拖选（LongPress）与滑块（Pan）挂在**同一个** `GestureDetector` 上，
  // 靠竞技场分流：按住不动约 500ms 长按赢，立刻滑动超过 touch slop 则是 Pan 赢。
  // 上面两条钉住长按那一支；这条钉住 Pan 那一支没被长按顶掉 —— 顶掉了日历就
  // 没法拖着滑块选日子了，而这是这一页最早的交互。
  testWidgets('长按手势没顶掉单格滑块：立刻滑动仍是拖拽选中', (tester) async {
    final db = await _pumpCalendar(tester, 'day_night_rest_rest');

    // 先点中 8 日：滑块落在它上面（拖拽的基准是**滑块**，不是手指按下的地方）。
    await tester.tap(find.text('$_rangeFirstDay').first);
    await tester.pumpAndSettle();

    // 卡片外面还裹着一层 `_cellInset`（= gapHair）的四边内缩，所以格子高 =
    // 卡片高 + 2×gapHair。滑块走的是「松手位置 − 起手位置」，位移给满一格。
    final card = find.byKey(const ValueKey('day-card-$_rangeFirstDay'));
    final cellH = tester.getSize(card).height + AppTokens.gapHair * 2;

    final gesture = await tester.startGesture(tester.getCenter(card));
    // 第一下先走掉 touch slop（这一下只让 Pan 赢得竞技场，滑块纹丝不动），
    // 第二下才是真正的位移。
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(Offset(0, cellH));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 滑块吸附到下一行那一格 → 选中日变成 15 日，且那一格的胶囊是实心的。
    final now = DateTime.now();
    expect(
        find.text(L10n.monthDayWeekday(
            DateTime(now.year, now.month, _rangeLastDay))),
        findsOneWidget,
        reason: '立刻滑动仍要吸附到下一行那一格');
    final chip = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('day-chip-$_rangeLastDay')));
    expect((chip.decoration! as BoxDecoration).color!.a, closeTo(1.0, 1e-6),
        reason: '松手后滑块落在那格，胶囊要实心');
    // 而且这一下**不是**长按拖选：没弹改班层，也就没落任何覆盖。
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty,
        reason: '立刻滑动不该被当成长按拖选');

    await _disposeCalendar(tester);
  });

  // ── spec §7.3：空白表方案（跟随法定节假日）下长按不进入范围态 ──
  //
  // 空白表没有班次定义可挑：让用户拖出一片淡染、松手却什么也不发生，是死的
  // 交互。信息卡那个入口（Task 8）已经按同一条判据灰掉了，这条钉住长按这一路
  // 也跟上 —— 两处判据必须同源。
  //
  // 断言写在**拖动中**（`midDrag`）：范围淡染松手就收，等 `longPressDragCell`
  // 跑完再看是看不到它的，那条断言会变成一句永远为真的空话（我第一版就是
  // 这么写的，靠"把闸门拆掉跑一遍"才照出来）。
  testWidgets('空白表方案：长按不进入范围态，也不落覆盖', (tester) async {
    final db = await _pumpCalendar(tester, 'day_night_rest_rest', blank: true);

    // 触觉一起钉：`onLongPressStart` 里的 `modeEnter()` 挂在 `if (date != null)`
    // 之下 —— 这一下压根没进入多选态，就不许发那记「进入多选态」的强震。
    // 少了这条，「闸门」没人看着，下次谁把条件删掉都不会有人知道。
    // （起手那一下**可能**会有一次 selectionClick：长按满 100ms 时 Tap 的 deadline
    // 到点，`onTapDown` → `_selectFromPosition` 把选中挪到按下的那格 —— 那是
    // 真的变了，该响。但若按下的那格**本来就是当前选中**（本月 8 号恰是今天时），
    // 那一下是无变化的 no-op，一条也没有。所以下面的断言是「不含 mediumImpact」
    // 而不是「为空」—— 它不依赖起手有没有那一记。）
    final fired = <Object?>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
      return null;
    });
    addTearDown(() => messenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await longPressDragCell(tester, _rangeFirstDay, 1, midDrag: () async {
      expect(_rangeTintCount(tester), 0, reason: '空白表下长按不该画范围淡染');
      expect(_blockScale(tester), 1.0, reason: '空白表下这一下也不该点亮玻璃块');
    });

    expect(fired, isNot(contains('HapticFeedbackType.mediumImpact')),
        reason: '空白表下压根没进入多选态，不该发 modeEnter 那记强震');

    expect(find.textContaining('$_rangeSpan 天'), findsNothing,
        reason: '空白表下不该弹改班层');
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty,
        reason: '空白表下不该落任何覆盖');

    await _disposeCalendar(tester);
  });

  // ── 长按落在本月之外的空白格 ──
  //
  // 选星期表头那一条：`_dateFromPosition` 的 `row < 0` 分支（表头中心 y ≈ 13，
  // 减掉 `_weekdayH` 26 之后是负行）。这一下不是范围选择，但它是**被长按赢下**
  // 的手势 —— `onTapUp` / `onPanEnd` 都不会再来，不在这儿把 `_pressed` 熄掉，
  // 玻璃块会一直停在按下的放大态（1.22）直到下一次触点。
  testWidgets('长按落在本月之外的空白格：不画范围，玻璃块也不能卡在放大态', (tester) async {
    final db = await _pumpCalendar(tester, 'day_night_rest_rest');

    final gesture = await tester.startGesture(
        tester.getCenter(find.text(L10n.weekdays.first)));
    await tester.pump(const Duration(milliseconds: 600)); // 过长按判定
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_rangeTintCount(tester), 0);
    expect(_blockScale(tester), 1.0,
        reason: '长按在空白格上也要把玻璃块收回去');
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty);

    await _disposeCalendar(tester);
  });

  // ── 长按拖到一半，手指被系统取消 ──
  //
  // 长按赢下竞技场之后框架只把 `PointerUp` 送进 `onLongPressEnd`；取消走的是
  // 另一条回调 `onLongPressCancel`（长按已经 accept 也照样会发 ——
  // `GestureRecognizerState` 只有 ready/possible/defunct 三档，accept 不改
  // state，所以 `_checkLongPressCancel` 那道 `state == possible` 的闸门仍然
  // 放行）。两条回调缺一条，那片淡染就会一直挂在屏幕上。
  testWidgets('长按拖到一半被系统取消：范围淡染要收干净', (tester) async {
    final db = await _pumpCalendar(tester, 'day_night_rest_rest');

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('day-card-$_rangeFirstDay'))));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();

    // 拖动中就圈住 8…15 这 8 格：逐格画，所以正好 8 个 —— 画成外接矩形的话
    // 会多出整整一行（14 个）。
    expect(_rangeTintCount(tester), _rangeSpan,
        reason: '拖选中：8…15 逐格淡染，一个不多一个不少');

    await gesture.cancel(); // 切前台、来电之类的系统取消
    await tester.pumpAndSettle();

    expect(_rangeTintCount(tester), 0, reason: '取消之后不该留下任何范围淡染');
    expect(_blockScale(tester), 1.0);
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty,
        reason: '取消不是「松手」，不该落库');

    await _disposeCalendar(tester);
  });

  // ── spec §4.3：日历手势的触觉 ──
  //
  // 用户 v0.8.1 的原话：「长按这个滑块的时候，它不是会触发这个连选吗？那它触发
  // 的时候能不能加个震动反馈啊，这样区分更明显一点」。长按因此分两级：进入多选态
  // 那一下要「更明显」（`modeEnter`），之后每进一格再轻震一下（`select`）——
  // 用户在两档里选了「进入时震 + 每进一格再轻震」。
  //
  // 拦截平台通道来断言：三档触觉都走 `SystemChannels.platform` 的
  // `HapticFeedback.vibrate`，只是参数字符串不同（与 `haptics_test.dart` 同一招）。

  testWidgets('长按进入多选态震一次，每进一格再震一次', (tester) async {
    final fired = <Object?>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
      return null;
    });
    addTearDown(() => messenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _pumpCalendar(tester, 'day_night_rest_rest');
    fired.clear(); // 建树过程本身不该有触觉

    final start =
        tester.getCenter(find.byKey(const ValueKey('day-card-8')));
    // 格子节距 = 卡片高 + 上下各一条发丝间隙（与上面那条滑块用例同一算式）。
    // 用节距而不是写死 60：一次 move 正好跨一行，落点是确定的。
    final cellH =
        tester.getSize(find.byKey(const ValueKey('day-card-8'))).height +
            AppTokens.gapHair * 2;

    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600)); // 过长按判定

    // 起手那一下的账先单独记：Tap 的 deadline 到点会走一次 `_selectFromPosition`
    // （把选中挪到按下的那格，真的变了、该响），紧接着是 `modeEnter`。此后
    // **只数 move 的贡献**，断言就不依赖「今天是不是正好 8 号」这种日期脸色。
    final selBefore =
        fired.where((f) => f == 'HapticFeedbackType.selectionClick').length;
    expect(fired.where((f) => f == 'HapticFeedbackType.mediumImpact'), hasLength(1),
        reason: '进入多选态在起手那一刻发一记 modeEnter');

    await gesture.moveBy(Offset(0, cellH)); // 8 → 15
    await tester.pump();
    await gesture.moveBy(Offset(0, cellH)); // 15 → 22
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // **精确计数**，不是 `contains`：后者在 `onLongPressMoveUpdate` 那一行被删掉
    // 时依然由起手那记 select 满足 —— 于是「长按拖选每进一格」这个落点没有任何
    // 东西看着（正是 spec 警告过的「两个落点别只改一个」的镜像）。
    final selAfter =
        fired.where((f) => f == 'HapticFeedbackType.selectionClick').length;
    expect(selAfter - selBefore, 2,
        reason: '长按拖过两格 → 恰好两记 select：每进一格一记，多一下少一下都说明落点不对');
    expect(fired.where((f) => f == 'HapticFeedbackType.mediumImpact'), hasLength(1),
        reason: '整场手势只该进入一次多选态');

    await _disposeCalendar(tester);
  });

  testWidgets('单格滑块拖到新的一格时震，没换格不震', (tester) async {
    final fired = <Object?>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
      return null;
    });
    addTearDown(() => messenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _pumpCalendar(tester, 'day_night_rest_rest');
    fired.clear();

    final cellH =
        tester.getSize(find.byKey(const ValueKey('day-card-8'))).height;
    final start = tester.getCenter(find.byKey(const ValueKey('day-card-8')));

    // 先把滑块钉在 8 日再动它。拖拽的基准是**滑块**、不是手指按下的地方
    // （`onPanStart` 读的是 `_selectedRect`）—— 不先钉住的话，「往下拖一格」落到
    // 的是「今天 + 7」，而今天落在月末那几天就掉出本月、`_nearestDateFromVisual`
    // 返回 null，选中其实一步没动，这条用例会在每个月的某些日子随机转红。
    // 钉在 8 日则是 8 日（第 2 行）→ 15 日（第 3 行），任何月份都成立（见文件头）。
    await tester.tapAt(start);
    await tester.pumpAndSettle();

    // 原地轻点（还是 8 日，没有换格）→ 不震
    fired.clear();
    await tester.tapAt(start);
    await tester.pumpAndSettle();
    expect(fired, isEmpty, reason: '选中没变不该震');

    // 拖一格 → 选中变了 → 震
    var gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, 20)); // 过 slop
    await tester.pump();
    await gesture.moveBy(Offset(0, cellH)); // 落到下一行
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fired, isNotEmpty, reason: '选中换了格该震');

    // 拖出去又拖回来（松手还落回原来那格）→ 同样「没换格」，不震
    fired.clear();
    gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, 20)); // 过 slop，Pan 赢下竞技场
    await tester.pump();
    await gesture.moveBy(const Offset(0, -20)); // 拖回原格
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fired, isEmpty, reason: '拖回原来那格不该震');

    // 点按**另一格** → 恰好一记 select。
    //
    // 用**精确列表**而不是 `isNotEmpty`：上面每一条都由旁边的拖拽（`onPanEnd`）
    // 一路满足，所以 `_selectFromPosition` 里那行 `Haptics.select()` 被删掉时
    // 套件照样全绿 —— 点选这个落点没有任何东西看着。这条会红。
    fired.clear();
    await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('day-card-9'))));
    await tester.pumpAndSettle();
    expect(fired, ['HapticFeedbackType.selectionClick'],
        reason: '点按换了格：恰好一记 select（多一记少一记都说明点选落点不对）');

    await _disposeCalendar(tester);
  });

  testWidgets('信息卡那行用玻璃按压缩放，不引入 Material 水波纹', (tester) async {
    await _pumpCalendar(tester, 'day_night_rest_rest');

    final entry = find.byKey(const Key('info-card-shift-entry'));
    expect(entry, findsOneWidget);

    // 这一行的按压反馈必须是 GlassPressable（Q 弹缩放），不能是裸 InkWell。
    //
    // `info-card-shift-entry` 这个 key 就挂在 GlassPressable 上，所以不能写
    // `find.descendant(of: entry, matching: find.byType(GlassPressable))` ——
    // descendant 只找**后代**，不含自身，那样写恒为空。
    expect(
      find.descendant(of: entry, matching: find.byType(InkWell)),
      findsNothing,
      reason: '全 app 的按压反馈是玻璃缩放；水波纹只该出现在弹层的 ListTile 里',
    );
    expect(tester.widget(entry), isA<GlassPressable>());

    // 点击必须照旧能打开选择层
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.text(L10n.restoreRotation), findsNothing,
        reason: '今天没被调整过，所以不该有「恢复轮转」');
    expect(find.byType(ListTile), findsWidgets, reason: '选择层该弹出来了');

    await _disposeCalendar(tester);
  });

  testWidgets('小窗（高 < 480dp）：网格让位，只留信息卡；「已调班」还在', (tester) async {
    // 200×400 是各机型小窗的默认尺寸（也是我们真机上量到的那档）。
    final db = await _pumpCalendar(tester, 'day_night_rest_rest',
        width: 200, height: 400);

    // 先确认这个尺寸确实落进了小窗那一档：网格不画了。
    expect(find.byKey(const ValueKey('day-card-8')), findsNothing,
        reason: '小窗下两者都想要的结果是两者都看不清 —— 格子让位给信息卡');

    // 给「今天」上一条按天调整，标记必须出现在信息卡上。
    final classes = await db.select(db.shiftClassRows).get();
    await AppRepository(db)
        .setDayOverrides([dateOnly(DateTime.now())], classId: classes.first.id);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('info-card-adjusted')), findsOneWidget,
        reason: '小窗里格子窄到画不出胶囊、圆点根本不会出现，'
            '信息卡是唯一还能承载这个标记的地方');

    await _disposeCalendar(tester);
  });

  testWidgets('400×640 那档小窗不受影响：网格与「已调班」都还在', (tester) async {
    // 各机型小窗的默认尺寸，高 640 > 480，**不该**被上面那条规则收走网格。
    final today = dateOnly(DateTime.now());
    final db = await _pumpCalendar(tester, 'day_night_rest_rest',
        width: 400, height: 640);

    expect(find.byKey(ValueKey('day-card-${today.day}')), findsWidgets,
        reason: '这档是主流小窗尺寸，必须保持网格 + 完整信息卡');

    final classes = await db.select(db.shiftClassRows).get();
    await AppRepository(db).setDayOverrides([today], classId: classes.first.id);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('info-card-adjusted')), findsOneWidget);

    await _disposeCalendar(tester);
  });
}
