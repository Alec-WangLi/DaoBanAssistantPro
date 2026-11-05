// app/test/calendar_month_stats_test.dart
//
// 信息卡「本月统计」、换月动画与光晕背景、当月事实的缓存键。
//
// 由 app/test/calendar_screen_test.dart 按被测对象切分而来：断言与用例名一字未改，
// 夹具与 helper 在 support/calendar_test_support.dart。
import 'dart:math' as math;

import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/theme/animated_background.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/state/app_settings.dart';
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


  testWidgets('信息卡「本月统计」：只画在装得下的那天，最满的一天不画', (tester) async {
    await pumpCalendar(tester, 'six_crew_three_shift');
    final m = await seekHolidayMonth(tester);

    final box = find.byKey(const Key('info-card-box'));
    final content = find.byKey(const Key('info-card-content'));
    final cardH = tester.getSize(box).height;
    final inner = cardH - (AppTokens.spaceLg * 2 + 2);
    final days = DateTime(m.year, m.month + 1, 0).day;

    var maxContent = 0.0;
    var shown = 0;
    var hidden = 0;
    for (var d = 1; d <= days; d++) {
      final hasTally = await tapDay(tester, d);
      expect(tester.getSize(box).height, cardH,
          reason: '$d 日：统计行不许把卡片顶高 —— 顶高一像素，上面六个格子就集体矮一像素');
      final c = tester.getSize(content).height;
      maxContent = math.max(maxContent, c);
      if (hasTally) {
        shown++;
        expect(c, lessThanOrEqualTo(inner),
            reason: '$d 日：画了统计行之后内容 $c 装不进卡片内高 $inner，最后一行会被裁掉');
      } else {
        hidden++;
      }
    }
    expect(shown, greaterThan(0),
        reason: '有节假日的月份里普通日子是有富余的，一天都没画说明判定收得太紧');
    expect(hidden, greaterThan(0), reason: '最满的那天富余为 0，那天必须不画');

    // 前提：卡片确实紧贴最满的那天（容 2dp 取整余量，与另一条用例同口径）。
    expect(inner - maxContent, lessThanOrEqualTo(2),
        reason: '卡片该是紧贴最满那天的；高出太多说明富余被算漏了');

    await disposeCalendar(tester);
  });


  testWidgets('信息卡「本月统计」：数字就是本月的实际班次天数', (tester) async {
    await pumpCalendar(tester, 'white_white_night_night_rest_rest');
    final m = await seekHolidayMonth(tester);
    final days = DateTime(m.year, m.month + 1, 0).day;

    String? text;
    for (var d = 1; d <= days && text == null; d++) {
      if (await tapDay(tester, d)) {
        text = tester
            .widget<Text>(find.byKey(const Key('info-card-month-tally')))
            .data;
      }
    }
    expect(text, isNotNull, reason: '有节假日的月份里该有画着统计行的日子');
    expect(text, startsWith(L10n.monthTally));

    final parts = text!.substring(L10n.monthTally.length).trim().split(' · ');
    expect(parts, isNotEmpty);
    var total = 0;
    final labels = <String>[];
    for (final p in parts) {
      // 形状是「简称 + 数字」：白12 / 夜8 / 休11（英文是 M12 / N8 / O11）。
      final match = RegExp(r'^(\D+?)(\d+)$').firstMatch(p);
      expect(match, isNotNull, reason: '「$p」不符合「简称 + 数字」的形状');
      labels.add(match!.group(1)!);
      final n = int.parse(match.group(2)!);
      expect(n, greaterThan(0), reason: '「$p」是 0 天，那这个班次这个月根本没出现');
      total += n;
    }
    expect(labels.toSet().length, labels.length, reason: '同一个班次不许出现两次');
    expect(labels.length, greaterThanOrEqualTo(2), reason: '这个模板至少白 / 夜 / 休三种班');
    expect(total, days,
        reason: '数的是**整月**（不是到今天为止），每天都有班次，加总该等于这个月的天数');

    await disposeCalendar(tester);
  });


  // ── 换月动画 ──

  testWidgets('换月：进出两版同时在树上，落定后只剩一版', (tester) async {
    // 换月从前是瞬切。加了位移 + 淡入之后要盯两件事：动画真的起来了（两版同时在
    // 树上，而不是被同一个键判成「同一个孩子」直接换掉），以及落定之后不留残影
    // —— 留着的话按 `day-card-N` 找格子会找到两个。
    await pumpCalendar(tester, 'day_night_rest_rest');
    final cell = find.byKey(const ValueKey('day-card-1'));
    expect(cell, findsOneWidget);

    await tester.tap(nextMonth());
    await tester.pump(); // 起手一帧
    await tester.pump(AppTokens.durMed ~/ 2); // 动画正中间
    expect(cell, findsNWidgets(2),
        reason: '换月动画中途该有新旧两版；只找到一版说明位移/淡入没起来');

    await tester.pumpAndSettle();
    expect(cell, findsOneWidget, reason: '落定后旧的那版要收干净');

    await disposeCalendar(tester);
  });


  // ── 光晕背景 ──

  testWidgets('日历页挂着光晕背景，且它不是逐帧驱动的', (tester) async {
    // 这一条盯两件事。
    // ① 页面确实有那层流光（在此之前整页唯一的流光只出现在响铃界面，日历页是一块
    //    纯色 —— 满页磨砂没在磨东西）。
    // ② 它**不是逐帧驱动**的：`pumpAndSettle` 能停下来（下面这行断言为假）就说明
    //    帧队列空得下来。用 `AnimationController..repeat()` 的话这里永远有待处理帧
    //    —— 那意味着整页永久不空闲，压在背景上的每一层 `BackdropFilter` 每帧重算。
    //    日历是长时间停留的一页，所以驱动改成了低频定时器（见 `FlowingBackground`
    //    类头注：26 秒漂 46dp，逐帧更新每帧只动 0.03dp，纯粹是白烧）。
    await pumpCalendar(tester, 'day_night_rest_rest');
    expect(find.byType(FlowingBackground), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: '背景在逐帧推帧 —— 整页不空闲，每层模糊每帧重算');

    await disposeCalendar(tester);
  });

  // ── 长按拖选一段日子 ──
  //
  // 两端固定取 `rangeFirstDay` / `rangeLastDay`（见文件头：为什么不用「今天」）。
  // 拖动距离 60：实测测试面上格子高约 91（420 宽 / 1600 高），60 落在
  // 「半格 < 60 < 一格半」之间 —— 从格子中心往下拖必落到下一行，且只落一行。

  /// 长按 [fromDay] 那一格，松开时停在 `fromDay + stepRows * 7` 那一格。
  ///
  /// [midDrag] 在**手指还没抬起**时调用：范围淡染是瞬时的（松手就收），要断言
  /// 「圈住了哪几格 / 有没有进范围态」只能卡在这个时刻看。


  // ── 当月那五样的缓存键（v0.10.20）───────────────────────────────────────
  //
  // `_factsFor` 把「本月统计 / 整月有没有班表在管」按一把键缓存住（这两样是每次
  // 重建都要整月 × 链查询的大头）。**键漏一项 = 界面上静默显示旧值** —— 下面几条
  // 各钉一头：语言、以及**排班本身**（基准日 / 周期 / 班组错位 / 按天改班）。
  //
  // ⚠️ 键里用的是 `chain.rotationKey` 而**不是 `chain.cacheKey`** —— 后者是「信息卡
  // 高度」的指纹，不含按天改班。当初用错它的后果是「调过班之后这一行还是旧数字」，
  // 这正是下面第二条用例钉住的（独立审查抓的）。
  group('当月事实缓存', () {
    testWidgets('调过班之后「本月统计」那一行跟着变（键里必须含排班本身）', (tester) async {
      // 要一个有富余画统计行的月份（见 `pinNow`）。
      pinNow(DateTime(2026, 10, 15));
      // ⚠️ 这一条是独立审查抓的：键原来用的是 `chain.cacheKey`，而那个是**信息卡
      // 高度**的指纹 —— 它只看组名 / 简称 / 空白表 / 时段，**不含基准日、周期、
      // 班组错位、按天改班的覆盖**。于是「调一次班」之后键不变 ⇒ 这一行一直显示
      // 旧数字，而同一个界面上格子与班次行已经变了（自己打自己的脸）。
      final AppDatabase db = await pumpCalendar(tester, 'four_crew_three_shift');
      final String before = tester
          .widget<Text>(find.byKey(const Key('info-card-month-tally')))
          .data!;

      final DateTime today = dateOnly(appNow());
      final ActiveSchedules schedules =
          (await AppRepository(db).getActiveSchedules())!;
      final ShiftClass target = schedules.chain.scheduleOn(today)!.classes[1];
      await AppRepository(db)
          .setDayOverrides(<DateTime>[today], classId: target.id!);
      await tester.pumpAndSettle();

      final String after = tester
          .widget<Text>(find.byKey(const Key('info-card-month-tally')))
          .data!;
      expect(after, isNot(before),
          reason: '调过班之后这一行还是旧数字 —— 键里少了「排班本身」');
      await disposeCalendar(tester);
    });

    testWidgets('换语言之后「本月统计」那一行跟着换（键里必须含语言）', (tester) async {
      pinNow(DateTime(2026, 10, 15));
      await pumpCalendar(tester, 'four_crew_three_shift');
      expect(find.textContaining(L10n.monthTally), findsOneWidget,
          reason: '前提：这一行本来就画出来了（不然下面比的是「都没有」）');

      // ⚠️ `L10n.locale` 是模块级的，用完必须还原 —— 漏出去会把后面用例的班次名
      // 换成英文（`pumpCalendar` 的说明里写着这条）。还原只动 `L10n`，不碰已经
      // 拆掉的 provider 容器（在那里读会抛「container already disposed」）。
      addTearDown(() => L10n.locale = 'zh');

      // 走 provider 换语言 —— 直接改 `L10n.locale` 不会让这一页重建。
      final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(CalendarScreen)));
      await container.read(appSettingsProvider.notifier).setLanguage('en');
      await tester.pumpAndSettle();

      expect(find.textContaining(L10n.monthTally), findsOneWidget,
          reason: '键里少了语言 —— 换到英文之后这一行还是从前的缓存值（中文）');
      await disposeCalendar(tester);
    });

  });
}
