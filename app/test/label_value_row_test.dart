// app/test/label_value_row_test.dart
//
// 编辑器 / 排班管理里那些「左边标签、右边值」的行（`_labelValueRow`），以及输入框
// 旁边那些提示（`可选，如「午休」`）。护栏在 320dp 特大档下把它们一条条点了出来 ——
// 而这一**类**与字号放大无关：它们在最窄的屏上、**正常字号**下就已经在省略了。
//
// 收法见设计 §6.4：**值**按可用宽度等比缩小（它短、且是主角），**标签**允许折两行。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/schedule_editor_screen.dart';
import 'package:shiftassistantpro/features/calendar/schedule_management_screen.dart';
import 'package:shiftassistantpro/state/app_settings.dart';

import '../tool/visual/visual_harness.dart';

Future<void> _pump(
  WidgetTester tester,
  Future<Widget> Function(AppDatabase db) build, {
  required AppFontSize font,
  String lang = 'zh',
  double width = 320,
}) async {
  setUpVisualPrefs();
  final db = await makeVisualDatabase();
  addTearDown(db.close);
  await pumpScreen(
    tester,
    home: await build(db),
    overrides: <Override>[databaseProvider.overrideWithValue(db)],
    size: Size(width, width <= 320 ? 640 : 780),
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
    testWidgets('排班管理的标签值行 · 320dp 特大 · $lang', (tester) async {
      await _pump(tester, (db) async => const ScheduleManagementScreen(),
          font: AppFontSize.extraLarge, lang: lang);
      expect(truncatedParagraphs(tester), isEmpty,
          reason: '标签折两行、值按宽缩小之后，这一页不该再有省略号');
      await teardownVisual(tester);
    });

    testWidgets('编辑器的字段标签与值 · 320dp 特大 · $lang', (tester) async {
      await _pump(
        tester,
        (db) async => ScheduleEditorScreen(scheduleId: await currentScheduleId(db)),
        font: AppFontSize.extraLarge,
        lang: lang,
      );
      expect(truncatedParagraphs(tester), isEmpty,
          reason: '这一页有 `名称` / `响铃` / `前一天 23:00` / `如「午休」` 这些标签与提示');
      await teardownVisual(tester);
    });
  }

  testWidgets('对照：360dp 标准档也不许有省略', (tester) async {
    await _pump(tester, (db) async => const ScheduleManagementScreen(),
        font: AppFontSize.standard, width: 360);
    expect(truncatedParagraphs(tester), isEmpty);
    await teardownVisual(tester);
  });
}
