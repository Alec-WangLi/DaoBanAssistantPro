// app/test/list_subtitle_fit_test.dart
//
// 列表行的副标题（待办的「日期 · 时间 · 提醒」、重复待办管理面板那一行）。
// 护栏在 320dp 特大档下把它们点出来了 —— 它们原来是 `maxLines: 1` + 省略号。
//
// 收法见设计 §6.3：**折两行**（行高跟着长）。这一类是「有地方长高」的那一半，
// 所以走降级顺序的第 1 档，不缩小。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';
import 'package:shiftassistantpro/state/app_settings.dart';

import '../tool/visual/visual_harness.dart';

Future<void> _pump(
  WidgetTester tester,
  Future<Widget> Function(AppDatabase db) build, {
  String lang = 'zh',
  Size size = const Size(320, 640),
  AppFontSize font = AppFontSize.extraLarge,
}) async {
  setUpVisualPrefs();
  final db = await makeVisualDatabase();
  addTearDown(db.close);
  await pumpScreen(
    tester,
    home: await build(db),
    overrides: <Override>[databaseProvider.overrideWithValue(db)],
    size: size,
    fontSize: font,
    language: lang,
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
    await ensureVisualFonts();
  });
  setUp(() => L10n.locale = 'zh');

  for (final lang in const <String>['zh', 'en']) {
    testWidgets('待办副标题折两行，不省略 · $lang', (tester) async {
      // 造一条「日期 · 时间 · 提醒」三样都有的待办 —— 那正是最长的那一行。
      await _pump(tester, (db) async {
        await seedRecurringTodo(db);
        return const ScheduleScreen();
      }, lang: lang);
      expect(truncatedParagraphs(tester), isEmpty,
          reason: '副标题要折两行，而不是把「提前15分钟」那段吃掉');
      await teardownVisual(tester);
    });
  }

  testWidgets('对照：420dp 标准档也不许有省略', (tester) async {
    await _pump(tester, (db) async => const ScheduleScreen(),
        size: const Size(420, 900), font: AppFontSize.standard);
    expect(truncatedParagraphs(tester), isEmpty);
    await teardownVisual(tester);
  });
}
