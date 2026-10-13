// app/test/calendar_header_fit_test.dart
//
// 日历顶栏那一行：**年月不许被省略**（用户 2026-10-13 报的就是它 —— 真我 GT7 Pro
// 上把「2026年10月」显示成「2026年1…」）。
//
// 收法见设计 §6.1：**别再按 360dp 这个写死的门槛猜**一行放不放得下，改成按排版
// 实测 —— 固定件（四个圆形钮 + 间距 + 「今天」胶囊）是量得出来的，年月那串也是。
// 装不下就走两行档（大 / 特大两档的**常态版式**，不是应急）。
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/state/app_settings.dart';

import '../tool/visual/visual_harness.dart';

Future<void> _pumpCalendar(WidgetTester tester,
    {required double width, required AppFontSize font}) async {
  setUpVisualPrefs();
  final db = await makeVisualDatabase();
  addTearDown(db.close);
  await pumpScreen(
    tester,
    home: const CalendarScreen(),
    overrides: <Override>[databaseProvider.overrideWithValue(db)],
    size: Size(width, width <= 320 ? 640 : 780),
    fontSize: font,
  );
}

/// 年月那串字有没有被截。
bool _yearMonthIntact(WidgetTester tester) {
  final want = L10n.yearMonth(DateTime.now());
  final rs = tester.allRenderObjects
      .whereType<RenderParagraph>()
      .where((ro) => ro.text.toPlainText() == want)
      .toList();
  return rs.isNotEmpty && rs.every((ro) => !ro.didExceedMaxLines);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await ensureVisualFonts();
  });
  setUp(() => L10n.locale = 'zh');

  testWidgets('标准档 360dp：顶栏一行，年月完整', (tester) async {
    await _pumpCalendar(tester, width: 360, font: AppFontSize.standard);
    expect(find.byKey(const Key('header-single-row')), findsOneWidget,
        reason: '标准档下 360dp 一行放得下 —— 不该白占一行高度');
    expect(_yearMonthIntact(tester), isTrue);
    await teardownVisual(tester);
  });

  testWidgets('特大档 360dp：顶栏自动两行，年月仍完整', (tester) async {
    await _pumpCalendar(tester, width: 360, font: AppFontSize.extraLarge);
    expect(find.byKey(const Key('header-two-row')), findsOneWidget,
        reason: '一行装不下时要自己换两行 —— 大/特大档这是常态版式');
    expect(_yearMonthIntact(tester), isTrue,
        reason: '换了版式之后年月必须完整 —— 那正是用户报的那一条');
    await teardownVisual(tester);
  });
}
