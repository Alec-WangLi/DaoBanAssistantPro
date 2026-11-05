// app/test/calendar_header_fit_test.dart
//
// 日历顶栏那一行：**年月不许被省略**（用户 2026-10-13 报的就是它 —— 真我 GT7 Pro
// 上把「2026年10月」显示成「2026年1…」）。
//
// 收法见设计 §6.1：**别再按 360dp 这个写死的门槛猜**一行放不放得下，改成按排版
// 实测 —— 固定件（四个圆形钮 + 间距 + 「今天」胶囊）是量得出来的，年月那串也是。
// 装不下就走两行档（大 / 特大两档的**常态版式**，不是应急）。
//
// **月份必须钉住，不能跟着真实日历漂**：顶栏那串字的宽度是逐月变的，跟着跑就等于
// 一年里有十一个月在测短月份、只有某一个月才真的碰到最宽的那串。实测（2026 年、
// 360dp、`RenderParagraph` 的实测宽度）：
//   · 中文  一位数月份 78.7（standard）/ 94.1（extraLarge）
//           两位数月份 87.9（standard）/ 105.1（extraLarge）← 最宽
//   �� 英文  `MMM yyyy`（缩写月，不是全称）：`May 2026` 86.0 最宽，
//           `Mar/Aug/Nov` 83.6~83.7 次之，`Sep 2026` 只有 82.2
// 所以下面中文钉 `十二月`、英文钉 `五月`，都是各自**最宽**的那一串。
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/clock.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/state/app_settings.dart';

import '../tool/visual/visual_harness.dart';

Future<void> _pumpCalendar(WidgetTester tester,
    {required double width,
    required AppFontSize font,
    required DateTime when,
    String language = 'zh'}) async {
  appNow = () => when;
  addTearDown(() => appNow = DateTime.now);
  setUpVisualPrefs();
  final db = await makeVisualDatabase();
  addTearDown(db.close);
  await pumpScreen(
    tester,
    home: const CalendarScreen(),
    overrides: <Override>[databaseProvider.overrideWithValue(db)],
    size: Size(width, width <= 320 ? 640 : 780),
    fontSize: font,
    language: language,
  );
}

/// 年月那串字有没有被截。
///
/// 「哪个月」一律取 `appNow()`（网格显示的月份也是它算的，见
/// `calendar_screen.dart` 的 `initState`）；取真实时钟的话，用例把月份钉住之后
/// 这里就去找今天那个月份的字，永远对不上。
bool _yearMonthIntact(WidgetTester tester) {
  final want = L10n.yearMonth(appNow());
  final rs = tester.allRenderObjects
      .whereType<RenderParagraph>()
      .where((ro) => ro.text.toPlainText() == want)
      .toList();
  return rs.isNotEmpty && rs.every((ro) => !ro.didExceedMaxLines);
}

/// 年月那串字相对**自然宽度**被缩了多少（1.0 = 一个像素没缩）。
///
/// 光看 `didExceedMaxLines` 不够：两行档的年月外面套着 `FittedBox(scaleDown)`
/// （`calendar_screen.dart` 的 `_header`），它是「缩，不省略」那一档兜底 ——
/// 真的挤了也不会报 exceed，只会悄悄变小。所以这里往上找到 `RenderFittedBox`，
/// 用「它给的宽度 ÷ 文字自然宽度」直接量缩放。
double? _shrinkOf(WidgetTester tester, String want) {
  RenderParagraph? ro;
  for (final p in tester.allRenderObjects.whereType<RenderParagraph>()) {
    if (p.text.toPlainText() == want) {
      ro = p;
      break;
    }
  }
  if (ro == null) return null;
  final double natural = ro.size.width;
  if (natural == 0) return null;
  RenderObject p = ro;
  while (p.parent != null && p.parent is! RenderFittedBox) {
    p = p.parent!;
  }
  if (p.parent is! RenderFittedBox) return 1.0; // 一行档没有这层兜底
  return (p.parent! as RenderFittedBox).size.width / natural;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await ensureVisualFonts();
  });
  setUp(() => L10n.locale = 'zh');

  testWidgets('标准档 360dp：顶栏一行，年月完整', (tester) async {
    await _pumpCalendar(tester,
        width: 360, font: AppFontSize.standard, when: DateTime(2026, 12, 15));
    expect(find.byKey(const Key('header-single-row')), findsOneWidget,
        reason: '标准档下 360dp 一行放得下 —— 不该白占一行高度');
    expect(_yearMonthIntact(tester), isTrue);
    await teardownVisual(tester);
  });

  testWidgets('特大档 360dp：顶栏自动两行，年月仍完整', (tester) async {
    await _pumpCalendar(tester,
        width: 360, font: AppFontSize.extraLarge, when: DateTime(2026, 12, 15));
    expect(find.byKey(const Key('header-two-row')), findsOneWidget,
        reason: '一行装不下时要自己换两行 —— 大/特大档这是常态版式');
    expect(_yearMonthIntact(tester), isTrue,
        reason: '换了版式之后年月必须完整 —— 那正是用户报的那一条');
    await teardownVisual(tester);
  });

  testWidgets('中文最宽的那串「2026年12月」：特大档两行，完整不截', (tester) async {
    await _pumpCalendar(tester,
        width: 360, font: AppFontSize.extraLarge, when: DateTime(2026, 12, 15));
    expect(L10n.yearMonth(DateTime(2026, 12, 15)), '2026年12月',
        reason: '钉的就是中文六种月份里最宽的那一串（105.1dp）');
    expect(find.byKey(const Key('header-two-row')), findsOneWidget);
    expect(_yearMonthIntact(tester), isTrue);
    expect(_shrinkOf(tester, L10n.yearMonth(DateTime(2026, 12, 15))),
        greaterThanOrEqualTo(0.999),
        reason: '中文最宽那串在两行档里就是原尺寸 —— 一个像素都不该缩');
    await teardownVisual(tester);
  });

  testWidgets('英文最宽的那串「May 2026」：特大档年月完整不截', (tester) async {
    await _pumpCalendar(tester,
        width: 360,
        font: AppFontSize.extraLarge,
        when: DateTime(2026, 5, 15),
        language: 'en');
    expect(L10n.yearMonth(DateTime(2026, 5, 15)), 'May 2026',
        reason: '顶栏用缩写月（MMM yyyy）；英文十二个月里 May 最宽（86.0dp）');
    expect(_yearMonthIntact(tester), isTrue,
        reason: '英文最宽月名也要完整 —— 顶栏一旦截断，就是用户报过的那条');
    // 实测：`May 2026` 自然宽 86.0，两行档里那颗胶囊只给得起约 85.5，于是
    // `FittedBox` 把它缩到 **0.9941**（差 0.6%，肉眼看不出）。这一档兜底就是
    // 「缩，不省略」，所以这里不要求 1.0，只钉住「不许缩得像换了个字号」。
    expect(_shrinkOf(tester, L10n.yearMonth(DateTime(2026, 5, 15))),
        greaterThanOrEqualTo(0.99),
        reason: '英文最宽月名最多缩 1%；超过就不是兜底而是字号掉档了');
    await teardownVisual(tester);
  });
}
