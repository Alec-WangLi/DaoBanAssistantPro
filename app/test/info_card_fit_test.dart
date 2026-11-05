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
import 'package:shiftassistantpro/core/clock.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/state/app_settings.dart';

import '../tool/visual/visual_harness.dart';
import 'support/fixed_clock.dart';

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

/// 把「今天」钉到 [when]（用例结束时还原成夹具锚点 `kAnchor`）。
///
/// 「一屏装下」这条保证只管**5 行的月份**（见文件头）；外层锚点落在 6 行月时，
/// 让用例自己把要的那种月份点名要过来 —— 前提失败会明说「这个月不是 5 行」，
/// 而不是把多出来的那一行悄悄合法化。
void _pinNow(DateTime when) {
  appNow = () => when;
  addTearDown(() => appNow = () => kAnchor);
}

/// 这一帧网格**真实画了几行**：按格子顶边去重量，不按日历算式推。
int _weekRows(WidgetTester tester) {
  final int days = DateTime(appNow().year, appNow().month + 1, 0).day;
  final Set<int> rows = <int>{};
  for (int d = 1; d <= days; d++) {
    final Finder f = find.byKey(ValueKey('day-card-$d'));
    if (f.evaluate().isEmpty) continue;
    rows.add(tester.getRect(f).top.round());
  }
  return rows.length;
}

/// 网格自己（`calendar-grid` 里那支 `SingleChildScrollView`）还剩多少可滚余量。
double _gridRoom(WidgetTester tester) {
  final ScrollableState s = tester.state<ScrollableState>(find
      .descendant(
        of: find.byKey(const Key('calendar-grid')),
        matching: find.byType(Scrollable),
      )
      .first);
  return s.position.maxScrollExtent;
}

void main() {
  useFixedNow();
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
        // 2026-10：10 月 1 日是周四、31 天 → 5 行（`_weekRows` 会当场量一遍）。
        _pinNow(DateTime(2026, 10, 15));
        await _pump(tester, size: size, font: font);
        expect(_weekRows(tester), 5,
            reason: '这条保证线只管 5 行的月份；6 行月是已知代价，另有专门一条');
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
    _pinNow(DateTime(2026, 10, 15));
    await _pump(tester, size: const Size(360, 780), lang: 'en');
    expect(_weekRows(tester), 5,
        reason: '同上：这里是英文串更长的 5 行月，6 行月另有专门一条');
    expect(truncatedParagraphs(tester), isEmpty);
    expect(_scrollRoom(tester), 0);
    await teardownVisual(tester);
  });


  // ── 6 行月：**装不下是已知代价**，但要滚得有界、而且差多少算得出来 ──────
  //
  // 账：格子有可读下限 `_minCellH = 58`（`calendar_screen.dart:3094` —— 三行字
  // 装得下的最小高度）。5 行月信息卡让得起，6 行月要多一整行 ≈62dp，信息卡里
  // 再也抠不出 18dp 的富余，于是多出来的那一行只能靠滚。
  //
  // 这是**产品取舍，不是 bug**：拿「字糊 / 卡片缺内容」换「少滑一下」不划算。
  // 所以我们不把 18dp 说成「通过」，而是把它钉成一条**算得出来的定数** ——
  // 哪天有人动了格高下限或卡片让步逻辑，这条会立刻报出差值变了多少。
  testWidgets('六行月：装不下是已知代价，滚的量恰好等于格子卡在 58 上的差额',
      (tester) async {
    // 2026-03：3 月 1 日是周日、31 天 → 6 行。
    _pinNow(DateTime(2026, 3, 15));
    await _pump(tester, size: const Size(360, 780));
    final int rows = _weekRows(tester);
    expect(rows, 6, reason: '这条要的是 6 行的月份');

    // 两份数分开来：可用高度**量**，格子高度**算**（走生产那颗纯函数）。
    // 拿量的格子高去推期望值就成了「同一份配置读两遍」，等于没测。
    final Rect grid = tester.getRect(find.byKey(const Key('calendar-grid')));
    final double cellW =
        tester.getSize(find.byKey(const ValueKey('day-card-1'))).width;
    final double cellH = calendarCellHeight(
      cellW: cellW,
      availHeight: grid.height,
      weekRows: rows,
      weekdayH: 26,
    );
    expect(cellH, closeTo(58, 0.01), reason: '格子应当正卡在可读下限 58 上');
    // 真画出来的格高必须就是算出来那个（否则这条在量一个不存在的东西）。
    expect(
        tester.getSize(find.byKey(const ValueKey('day-card-1'))).height,
        closeTo(cellH, 0.5),
        reason: '画出来的格高与 calendarCellHeight 的结论对不上');

    final double deficit = 26 + rows * cellH - grid.height;
    expect(deficit, greaterThan(0), reason: '这条要的是「真的差一点」的月份');
    expect(_gridRoom(tester), closeTo(deficit, 1),
        reason: '网格滚的量应当恰好是缺口 ${deficit.toStringAsFixed(1)}dp'
            '（周标题 26 + $rows × $cellH − 网格可用 ${grid.height.toStringAsFixed(1)}）');
    // 除了网格，谁都不许滚 —— 信息卡尤其（它只是让回高度，内容一条没少）。
    expect(_scrollRoom(tester), closeTo(_gridRoom(tester), 0.01),
        reason: '除网格之外还有东西在滚：信息卡自己撑破了');
    expect(truncatedParagraphs(tester), isEmpty,
        reason: '让高度不等于让内容：农历与班次行仍然一个字都不许省略');
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
