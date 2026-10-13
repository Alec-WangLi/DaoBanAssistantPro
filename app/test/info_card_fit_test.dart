// app/test/info_card_fit_test.dart
//
// 日历页底栏那张信息卡。护栏剩下的最后一类：整条农历串与「班次 时间 闹钟」那一行，
// 窄屏大字号下仍会被省略。
//
// 收法见设计 §6.2，两条硬约束：
//   ① 那两行**装得下**（农历放到三行、班次行放到两行，卡片跟着长高）；
//   ② **卡片自己不许滚**，**网格也不许滚** —— 用户 2026-10-13 的原话：
//      「它的日期和今日信息卡片不要出现说内容太多、需要你自己滚的情况」。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/state/app_settings.dart';

import '../tool/visual/visual_harness.dart';

Future<void> _pump(WidgetTester tester,
    {Size size = const Size(320, 640),
    AppFontSize font = AppFontSize.extraLarge,
    String lang = 'zh'}) async {
  setUpVisualPrefs();
  final db = await makeVisualDatabase();
  addTearDown(db.close);
  await pumpScreen(
    tester,
    home: const CalendarScreen(),
    overrides: <Override>[databaseProvider.overrideWithValue(db)],
    size: size,
    fontSize: font,
    language: lang,
  );
}

/// 这一帧里所有可滚动区域**还剩多少可滚的余量**。
///
/// `maxScrollExtent == 0` 才是「没有东西可滚」；只看 `pixels` 不行 —— 没人滚过
/// 它也是 0。
double _scrollRoom(WidgetTester tester) {
  var total = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    total += ((e as StatefulElement).state as ScrollableState)
        .position
        .maxScrollExtent;
  }
  return total;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
    await ensureVisualFonts();
  });
  setUp(() => L10n.locale = 'zh');

  for (final lang in const <String>['zh', 'en']) {
    testWidgets('信息卡两行装得下 · 320dp 特大 · $lang', (tester) async {
      await _pump(tester, lang: lang);
      expect(truncatedParagraphs(tester), isEmpty,
          reason: '整条农历与班次行都要装得下（放不下就折行/缩小，不许省略）');
      await teardownVisual(tester);
    });

    testWidgets('信息卡与网格都不用滚 · 360dp 特大 · $lang', (tester) async {
      await _pump(tester, size: const Size(360, 780), lang: lang);
      expect(truncatedParagraphs(tester), isEmpty);
      expect(_scrollRoom(tester), 0,
          reason: '§2 第 2、3 条：日历页的网格与信息卡都不许出现「内容太多、'
              '需要你自己滚」的情况');
      await teardownVisual(tester);
    });
  }

  for (final size in const <Size>[Size(360, 780), Size(420, 900)]) {
    testWidgets('对照：${size.width.toInt()}dp 标准档既不省略也不用滚',
        (tester) async {
      await _pump(tester, size: size, font: AppFontSize.standard);
      expect(truncatedParagraphs(tester), isEmpty);
      expect(_scrollRoom(tester), 0,
          reason: '标准档是最常见的样子 —— 它必须保持一屏构图');
      await teardownVisual(tester);
    });
  }
}
