// app/test/calendar_grid_layout_test.dart
//
// 日历网格几何与手机档位版式：格子高度公式、滚动兜底、横竖屏分栏、紧凑卡、窄屏顶栏。
//
// 由 app/test/calendar_screen_test.dart 按被测对象切分而来：断言与用例名一字未改，
// 夹具与 helper 在 support/calendar_test_support.dart。

import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/core/clock.dart';
import 'support/fixed_clock.dart';
import 'support/calendar_test_support.dart';

void main() {
  useFixedNow();
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('六班三倒（6 个班组）：其他班组渲染 5 个色块，不再拼成一整行',
      (tester) async {
    // 窄屏：6 个色块必须换行，而不是把卡片撑破。
    await pumpCalendar(tester, 'six_crew_three_shift');

    expect(find.text(L10n.otherCrews), findsOneWidget);

    // 我们是第 1 组 → 剩下 5 组各一个色块（休班的组也要列出）
    final chips = chipTexts(tester);
    expect(chips, hasLength(5), reason: '6 个班组应当出 5 个色块');
    expect(chips.toSet(), hasLength(5), reason: '每个班组一个色块');
    // 一班是「我」，不该出现；五班/六班的名字由创建路径给满
    expect(chips.map((c) => c.split(' ').first).toSet(),
        {'二班', '三班', '四班', '五班', '六班'});

    // 旧的「一整行文字」形状：`其他班组：组名·班次名　…` 已不复存在
    expect(find.textContaining('${L10n.otherCrews}：'), findsNothing);

    // 窄屏 + 换行布局：不应有 RenderFlex overflow
    expect(tester.takeException(), isNull);

    await disposeCalendar(tester);
  });


  testWidgets('上 24 休 48：值班当天时间走 L10n，中文界面显示「次日」',
      (tester) async {
    await pumpCalendar(tester, 'duty_24_48', width: 640);

    expect(L10n.isEn, isFalse);
    // 班次名、时间、闹钟并成了一段富文本（见 info-card-shift-line 的说明），
    // 所以按整行的纯文本断言，而不是找独立的 Text。
    expect(shiftLine(tester), contains('08:00 – 次日08:00'));

    await disposeCalendar(tester);
  });


  testWidgets('上 24 休 48 英文界面：时间用 (next day) 且不露出中文',
      (tester) async {
    // 本用例靠「App 自己从设置里读出 en」来切语言，因此必须自己还原 ——
    // L10n.locale 是全局静态量，泄漏到下个用例会让那边的 saveSchedule
    // 存下英文班次名（模板的班次名按当前语言生成），进而把信息卡挤溢出。
    final prevLocale = L10n.locale;
    addTearDown(() => L10n.locale = prevLocale);

    SharedPreferences.setMockInitialValues({'language': 'en'});
    await pumpCalendar(tester, 'duty_24_48', width: 640);

    expect(L10n.isEn, isTrue, reason: '语言应当已从设置里读成 en');
    final rendered = shiftLine(tester);
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

    await disposeCalendar(tester);
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


  test('差 2dp 就装得下时，格子吃掉差额而不是多出一条滚动条', () {
    // 2026-11-05：视觉工装的字体钉成仓库内 Noto Sans CJK 之后，360×780 特大档的
    // 信息卡比等线高 2dp，网格可用高度 316 → 314，而 26 + 5×58 = 316，
    // 于是探针量到 `maxScrollExtent == 2.0`。2dp 的滚动条没有意义。
    const cellW = 48.0; // (360 − 24) / 7
    final fitted = calendarCellHeight(
      cellW: cellW,
      availHeight: 314,
      weekRows: 5,
      weekdayH: 26,
    );
    expect(fitted, lessThan(58),
        reason: '让出 0.4dp，别顶在可读下限上制造 2dp 溢出');
    expect(26 + 5 * fitted, lessThanOrEqualTo(314 + 0.001),
        reason: '让完之后必须正好装进视口');
  });


  test('差得更多时仍守可读下限，交给外层滚动兜底', () {
    // 同一个函数，差 20dp 就不该再让 —— 那是「真的装不下」，
    // 硬让会把格子压到装不下三行字。
    final fitted = calendarCellHeight(
      cellW: 48.0,
      availHeight: 296,
      weekRows: 5,
      weekdayH: 26,
    );
    expect(fitted, 58);
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
      find.text(L10n.monthDayWeekday(dateOnly(appNow())));


  testWidgets('宽屏：日历改左右分栏，信息卡在右不在下', (tester) async {
    // ⚠️ **尺寸必须写成「宽且横」**（1280×800）。原来只传了 `width: 1280`、
    // 高度取 `pumpCalendar` 的默认 1600 —— 那其实是一台**竖着的平板**，
    // 而分栏的判据是「宽且矮」（手机横屏）与「宽且高且横向」（平板/车机），
    // 竖屏平板本该走竖屏那一套。这条用例以前能过，是因为当时判据只看了宽度。
    await pumpCalendar(tester, 'four_crew_three_shift',
        width: 1280, height: 800);
    expect(tester.getTopLeft(cardDate()).dx, greaterThan(640),
        reason: '宽屏下信息卡应当被排在右栏，而不是底栏');
    await disposeCalendar(tester);
  });


  testWidgets('竖屏：仍是单栏，信息卡在下方', (tester) async {
    await pumpCalendar(tester, 'four_crew_three_shift');
    expect(tester.getTopLeft(cardDate()).dx, lessThan(420));
    expect(tester.getTopLeft(cardDate()).dy, greaterThan(600),
        reason: '竖屏下信息卡在底部区域');
    await disposeCalendar(tester);
  });


  testWidgets('短屏：信息卡压成紧凑版，把高度让给网格', (tester) async {
    await pumpCalendar(tester, 'four_crew_three_shift');
    final portraitH = tester.getSize(find.byType(GlassTile).last).height;
    await disposeCalendar(tester);

    await pumpCalendar(tester, 'four_crew_three_shift',
        width: 420, height: 420);
    final shortH = tester.getSize(find.byType(GlassTile).last).height;
    await disposeCalendar(tester);

    expect(shortH, lessThan(portraitH),
        reason: '短屏下信息卡应当比竖屏矮，把高度让给网格');
  });


  testWidgets('窄屏：顶栏「今天」收成纯图标钮', (tester) async {
    // 「今天」这两个字在顶栏按钮与信息卡的「今天」徽章里各有一处，
    // 所以数总数：宽屏 2 处，窄屏只剩徽章那 1 处。
    await pumpCalendar(tester, 'four_crew_three_shift');
    expect(find.text(L10n.today), findsNWidgets(2));
    await disposeCalendar(tester);

    await pumpCalendar(tester, 'four_crew_three_shift', width: 320);
    expect(find.text(L10n.today), findsOneWidget,
        reason: '320 宽下顶栏那两个该收起来，只留下信息卡的徽章');
    expect(find.byIcon(Icons.today_outlined), findsWidgets);
    await disposeCalendar(tester);
  });
}
