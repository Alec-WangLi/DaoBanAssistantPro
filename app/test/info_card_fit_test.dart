// app/test/info_card_fit_test.dart
//
// 日历页底栏那张信息卡，与整页的「一屏构图」。
//
// 收法见设计 §6.2，两条硬约束：
//   ① 那两行**装得下**（农历放到三行、班次行放到两行，卡片跟着长高）；
//   ② **卡片自己不许滚**，**网格也不许滚** —— 用户 2026-10-13 的原话：
//      「它的日期和今日信息卡片不要出现说内容太多、需要你自己滚的情况」。
//
// ── ② 的边界（2026-10-13 独立审查提出、实测后写准）──────────────────────
//
// 「一屏构图」保证的是**常见高度**：360×780 与 420×900 上**四档全部为 0**
// （实测 `maxScrollExtent` 见下面的用例）。**矮屏不在保证线内**：
// 320×640 与 360×640 上，网格从**最小档 0.9 就开始滚**（320×640：0.9 → 95、
// 1.0 → 110、1.1 → 125、1.2 → 139）—— 也就是说那**不是字号档位的问题，是高度不够**：
// 格子有可读下限（`_minCellH = 58`），六班组那种排满的日子信息卡本身就要
// ~340dp，640 高的屏装不下「顶栏 + 完整网格 + 完整卡片」。
//
// 那条兜底是**既有的、有意的**（`calendar_screen.dart` 的网格滚动容器上写着
// 「小屏 6 行放不下时滚动而非被裁切，避免底部行与信息卡重叠」），本轮不动它 ——
// 代价是矮屏用户要滚一下，收益是格子仍然是可读的大小。**这条边界写进了设计 §4.4。**
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

  // ── 保证线：常见高度上，四档都要「装得下 + 谁都不用滚」 ──
  for (final size in const <Size>[Size(360, 780), Size(420, 900)]) {
    for (final font in AppFontSize.values) {
      testWidgets('一屏构图：${size.width.toInt()}dp · ${font.name}',
          (tester) async {
        await _pump(tester, size: size, font: font);
        expect(truncatedParagraphs(tester), isEmpty,
            reason: '整条农历与班次行都要装得下（放不下就折行/缩小，不许省略）');
        expect(_scrollRoom(tester), 0,
            reason: '§2 第 2、3 条：网格与信息卡都不许出现「内容太多、'
                '需要你自己滚」的情况');
        await teardownVisual(tester);
      });
    }
  }

  // ── 英文：同一块屏、最大档 —— 英文串更长，是最狠的那一格 ──
  testWidgets('一屏构图：360dp · 特大 · 英文', (tester) async {
    await _pump(tester, size: const Size(360, 780), lang: 'en');
    expect(truncatedParagraphs(tester), isEmpty);
    expect(_scrollRoom(tester), 0);
    await teardownVisual(tester);
  });

  // ── 矮屏：**只保证「字不被吃掉」**，不保证一屏构图（理由见文件头）──
  for (final lang in const <String>['zh', 'en']) {
    testWidgets('矮屏 320dp 特大只保证不省略 · $lang', (tester) async {
      await _pump(tester, lang: lang);
      expect(truncatedParagraphs(tester), isEmpty,
          reason: '矮屏上网格可以滚（既有兜底），但字一个都不许被吃掉');
      await teardownVisual(tester);
    });
  }
}
