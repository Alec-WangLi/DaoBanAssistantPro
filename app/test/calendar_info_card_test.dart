// app/test/calendar_info_card_test.dart
//
// 底部信息卡：高度模型与内容（节假日徽章、农历、多闹钟、本月统计之外的其余内容）、
// 待办提示、玻璃按压反馈。
//
// 由 app/test/calendar_screen_test.dart 按被测对象切分而来：断言与用例名一字未改，
// 夹具与 helper 在 support/calendar_test_support.dart。
import 'dart:math' as math;

import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_pressable.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/lunar_info.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
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


  testWidgets('点开某天：信息卡高度只由本月决定，不随选中哪天变', (tester) async {
    // 起因：竖屏是 `Column[顶栏, Expanded(网格), 信息卡]`，格子高度按**剩余
    // 空间**算，所以信息卡随当天内容长高一点，六个格子就集体矮一点。
    // 内容里会变的至少有四处：法定节假日徽章、农历描述换行、其他班组色块
    // 换行、有没有班次/闹钟 —— 点一天晃一次。
    //
    // v0.6.10 起高度是**算**出来的（`info_card_metrics.dart`）：取本月最满的
    // 一天。所以这里同时盯两件事 —— 月内恒定，且紧到不留白。
    await pumpCalendar(tester, 'six_crew_three_shift');

    final box = find.byKey(const Key('info-card-box'));
    final cardH = tester.getSize(box).height;

    // 把整月的每一天都点一遍：每天的农历、节气、节日与班次都不一样。
    final daysInMonth =
        DateTime(appNow().year, appNow().month + 1, 0).day;
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

    await disposeCalendar(tester);
  });


  testWidgets('信息卡高度跟着「其他班组」占几行走', (tester) async {
    // 高度的逐日差异只有三处：节假日徽章、农历行数、其他班组色块折行数。
    // 前两处是「本月有没有」，第三处是「这个排班有几个班组」—— 班组越多色块
    // 占的行越多，卡片越高。这条用例盯住它确实跟着变（否则高度就是写死的）。
    final heights = <String, double>{};
    for (final t in ['four_crew_three_shift', 'six_crew_three_shift']) {
      await pumpCalendar(tester, t);
      heights[t] = tester.getSize(find.byKey(const Key('info-card-box'))).height;
      await disposeCalendar(tester);
    }

    expect(heights['six_crew_three_shift'],
        greaterThan(heights['four_crew_three_shift']!),
        reason: '六个班组的色块比四个班组多占行，卡片该更高');
  });


  testWidgets('没有法定节假日的月份：卡片更矮，网格拿到更多高度', (tester) async {
    // 「换月时高度可能变一次」是这套做法的代价，也是它的收益：没有节假日的
    // 月份不必为节假日徽章那一行留着空。这里盯住收益真的兑现了 —— 卡片变矮，
    // 而矮下来的高度确实还给了网格。
    await pumpCalendar(tester, 'four_crew_three_shift');

    final box = find.byKey(const Key('info-card-box'));
    final grid = find.byType(SingleChildScrollView).first;

    DateTime? plainMonth;
    DateTime? holidayMonth;
    var plainCardH = 0.0;
    var plainGridH = 0.0;
    var holidayCardH = 0.0;
    var holidayGridH = 0.0;
    final start = DateTime(appNow().year, appNow().month, 1);
    for (var i = 0; i < 24 && (plainMonth == null || holidayMonth == null); i++) {
      if (i > 0) {
        await tester.tap(nextMonth());
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

    await disposeCalendar(tester);
  });


  // 回归：v0.6.6 用户实测「信息卡最左侧那根色条错位，且不跟卡片变高变矮」。
  //
  // 根因是色条与面板各量各的高度：`Stack` 默认 `StackFit.loose`，只给非定位
  // 子节点松约束，面板于是缩到内容高度（用户那天 126）；而色条是
  // `Positioned(top: 18, bottom: 18)`（现值 `spaceLg`=16），量的是外面那个定高
  // 盒子（248）—— 于是色条比卡片长出 86dp 垂在空白里。修法是底栏时让面板撑满
  // 定高，两边同源。
  testWidgets('底栏信息卡：面板撑满定高，色条与面板上下对齐', (tester) async {
    await pumpCalendar(tester, 'four_crew_three_shift');

    final box = tester.getRect(find.byKey(const Key('info-card-box')));
    final panel = tester.getRect(find.byKey(const Key('info-card-panel')));
    final bar = tester.getRect(find.byKey(const Key('info-card-accent-bar')));

    expect(panel.height, closeTo(box.height, 0.5),
        reason: '面板要撑满定高盒子；否则色条按盒子高度画、会探出卡片的下沿');
    expect(bar.top - panel.top, closeTo(AppTokens.spaceLg, 0.5),
        reason: '色条上端贴着面板内容区的上沿');
    expect(panel.bottom - bar.bottom, closeTo(AppTokens.spaceLg, 0.5),
        reason: '色条下端贴着面板内容区的下沿');

    await disposeCalendar(tester);
  });


  // 回归：卡片是**定高**的，内容装不下时靠卡内滚动兜底 —— 也就是说内容一旦
  // 超过可用高度，最后一行就被底边裁掉，而卡片本身不会变大去提醒你。
  // v0.6.7 实测：六班组那种排满的日子内容已经 224dp，可用只有 210dp，
  // 「其他班组」最后一行被裁掉一截。这条不变量盯住它。
  testWidgets('底栏信息卡：最满的一天也要装得进卡片，不靠卡内滚动', (tester) async {
    await pumpCalendar(tester, 'six_crew_three_shift');

    // 可用高度 = 定高 − 上下 padding(spaceLg=16 ×2) − 上下描边(1×2)。描边那 2px
    // 来自 GlassPanel 的 `Border.all(width: 1)`，`Container` 会把它算进自己的
    // 内边距。与 `info_card_metrics.dart` 的 `_cardChromeV` 同一个算式。
    final inner = tester.getSize(find.byKey(const Key('info-card-box'))).height -
        (AppTokens.spaceLg * 2 + 2);

    final daysInMonth =
        DateTime(appNow().year, appNow().month + 1, 0).day;
    for (var d = 1; d <= daysInMonth; d++) {
      await tester.tap(find.text('$d').first);
      await tester.pump();
      final contentH =
          tester.getSize(find.byKey(const Key('info-card-content'))).height;
      expect(contentH, lessThanOrEqualTo(inner),
          reason: '$d 日：内容 $contentH 高过卡片内部的 $inner，'
              '最后一行会被底边裁掉');
    }

    await disposeCalendar(tester);
  });


  // 回归：v0.6.7 用户实测「法定节假日徽章太宽，把农历挤到右边，两行都显示不全」。
  // 徽章连图标带「法定节假日 · 」有一百多 dp，和农历并排时农历只剩一半宽度。
  testWidgets('信息卡：节假日徽章自占一行，农历独占下一行且不再被挤到右边',
      (tester) async {
    // 国庆那几天：这个月一定有法定节假日。
    pinNow(DateTime(2026, 10, 3));
    await pumpCalendar(tester, 'four_crew_three_shift');

    // 找出本月的第一个法定节假日（中秋那种）。
    final badgeFinder = find.byKey(const Key('info-card-holiday-badge'));
    final daysInMonth =
        DateTime(appNow().year, appNow().month + 1, 0).day;
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

    await disposeCalendar(tester);
  });


  // 对比度审计跑不到节假日徽章：工装渲染的日历选中的是「今天」，而今天未必是
  // 节假日，徽章根本不出现在图里。这条直接在控件树上量它的真配色补上缺口 ——
  // v0.6.8 之前它用原色红压在同色淡底上，浅深两套主题都只有 3.4:1。
  testWidgets('节假日徽章：文字与淡染底要过 AA 对比度', (tester) async {
    pinNow(DateTime(2026, 10, 3));
    await pumpCalendar(tester, 'four_crew_three_shift');

    final badgeFinder = find.byKey(const Key('info-card-holiday-badge'));
    final daysInMonth =
        DateTime(appNow().year, appNow().month + 1, 0).day;
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

    await disposeCalendar(tester);
  });


  testWidgets('信息卡：班次名、时间、闹钟在同一行', (tester) async {
    await pumpCalendar(tester, 'four_crew_three_shift');
    // 默认选中今天；先点一个「上夜班」的日子，让时间与闹钟都出来。
    await tester.tap(find.text('${appNow().day}').first);
    await tester.pump();

    final line = shiftLine(tester);
    expect(line, contains('闹钟'), reason: '闹钟要并进班次那一行，不再单独占一行');
    expect(
      tester
          .widget<Text>(find.byKey(const Key('info-card-shift-line')))
          .maxLines,
      1,
      reason: '整行只占一行文字，这就是「并进同一行」的落点',
    );

    await disposeCalendar(tester);
  });


  testWidgets('单班组排班：不渲染「其他班组」那一段', (tester) async {
    await pumpCalendar(tester, 'standard_week');

    expect(find.text(L10n.otherCrews), findsNothing);
    expect(chipTexts(tester), isEmpty);

    await disposeCalendar(tester);
  });


  testWidgets('信息卡待办提示：选中那天有待办才显示，且不改变卡片高度', (tester) async {
    final db = await pumpCalendar(tester, 'white_white_night_night_rest_rest');
    final today = dateOnly(appNow());
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

    await disposeCalendar(tester);
  });


  testWidgets('信息卡待办提示：窄屏不显示（放不下，会挤掉日期的字）', (tester) async {
    final db = await pumpCalendar(tester, 'white_white_night_night_rest_rest',
        width: 320);
    await AppRepository(db).addEvent(
      title: '交体检报告',
      date: dateOnly(appNow()),
      timeMinute: 14 * 60,
      advanceRemindMinutes: 15,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('info-card-todo-hint')), findsNothing);

    await disposeCalendar(tester);
  });


  testWidgets('信息卡那行用玻璃按压缩放，不引入 Material 水波纹', (tester) async {
    await pumpCalendar(tester, 'day_night_rest_rest');

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

    await disposeCalendar(tester);
  });


  // 一个班次挂多个闹钟之后，信息卡那一行**只有一行**（卡片是定高的，多出来的
  // 内容会顶高卡片、把网格挤矮）—— 所以只写首条 + 「等 N 个」。
  testWidgets('信息卡：一个班次多个闹钟时只写首条 + 「等 N 个」', (tester) async {
    final db = await pumpCalendar(tester, 'four_crew_three_shift');
    // 给第一个班次塞三条闹钟，然后**逐天点过去找它** —— 不假定「今天」正好上
    // 这个班次（模板的周期第一个元素是什么、今天轮到谁，都不该写死在用例里）。
    await AppRepository(db).setClassAlarmsForTesting(0, const [
      ShiftAlarm(minute: 6 * 60 + 30, label: '起床'),
      ShiftAlarm(minute: 12 * 60 + 30, label: '午休'),
      ShiftAlarm(minute: 17 * 60 + 30),
    ]);
    final daysInMonth =
        DateTime(appNow().year, appNow().month + 1, 0).day;
    var found = false;
    for (var d = 1; d <= daysInMonth && !found; d++) {
      await tester.tap(find.text('$d').first);
      await tester.pumpAndSettle();
      final line = shiftLine(tester);
      if (line.contains('06:30')) {
        found = true;
        expect(line, contains('等 3 个'),
            reason: '卡片定高、这一行只有一行：铺开列三个时刻会把后面的内容挤掉');
      }
    }
    expect(found, isTrue, reason: '本月应当有上这个班次的日子，否则这条用例没有意义');

    // spec §11 点名的断言：3 条闹钟那天的**卡片内容高度**必须与 1 条时一模一样
    // （那一行仍然只有一行；卡片被顶高就会连累日历网格变矮）。
    final withThree =
        tester.getSize(find.byKey(const Key('info-card-content'))).height;
    await AppRepository(db)
        .setClassAlarmsForTesting(0, const [ShiftAlarm(minute: 6 * 60 + 30)]);
    await tester.pumpAndSettle();
    final withOne =
        tester.getSize(find.byKey(const Key('info-card-content'))).height;
    expect(withThree, withOne,
        reason: '多条闹钟只改那一行的文字，不该把卡片顶高');

    await disposeCalendar(tester);
  });
}
