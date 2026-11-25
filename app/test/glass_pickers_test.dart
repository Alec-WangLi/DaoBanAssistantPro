// app/test/glass_pickers_test.dart
//
// 日期选择器（`showGlassDatePicker`）的三条体验契约 —— issue #7（2026-11-23）：
//   ① 年月标题可点，直接跳到目标月份，不再只能一个月一个月点箭头；
//   ② 翻月箭头显式取色 —— 裸 `Icon` 不给 color 时落到 `IconThemeData.fallback`
//      的纯黑，深色下就是黑压黑（与 `stats_period_header.dart` 头注释同一条根因）；
//   ③ 弹层高度与当月周数无关 —— 31 天 6 行、30 天 5 行，翻月时面板会一高一低。
//
// 这个件是**一个件带六个调用点**（统计导出起/止、新建闹钟、添加待办、添加时段、
// 排班编辑两处），所以三条契约都钉在这里，不按页面重复。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/theme/app_theme.dart';
import 'package:shiftassistantpro/core/widgets/glass_pickers.dart';

/// 在 420×900 的竖屏里打开日期选择器（和真机比例接近，行高取到上限 40）。
Future<void> _openDatePicker(
  WidgetTester tester,
  ThemeData theme,
  DateTime initial,
) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showGlassDatePicker(context, initialDate: initial),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  // `L10n.yearMonth` / `monthShort` 走 intl 的 'zh' 语言数据，不初始化会抛
  // `LocaleDataException` —— 那是测试的问题，不是选择器的问题。
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
  });

  setUp(() => L10n.locale = 'zh');

  testWidgets('深色下翻月箭头是近白，不落回默认黑', (tester) async {
    final theme = buildDarkTheme();
    await _openDatePicker(tester, theme, DateTime(2026, 11, 12));

    final left = tester.widget<Icon>(find.byIcon(Icons.chevron_left_outlined));
    final right = tester.widget<Icon>(find.byIcon(Icons.chevron_right_outlined));
    // 判据是「真正画出来的那一层」：显式给的色必须走到 Icon.color，
    // 不能是 null（null 就等于交给 IconThemeData.fallback）。
    expect(left.color, theme.colorScheme.onSurface,
        reason: '深色下的箭头必须显式取 onSurface（近白），否则黑压黑');
    expect(right.color, theme.colorScheme.onSurface);
  });

  testWidgets('浅色下翻月箭头用压过的主色（不是无条件白）', (tester) async {
    final theme = buildLightTheme();
    await _openDatePicker(tester, theme, DateTime(2026, 11, 12));

    final left = tester.widget<Icon>(find.byIcon(Icons.chevron_left_outlined));
    expect(left.color, AppTokens.solidAccent(theme.colorScheme.primary),
        reason: '浅色玻璃上写纯白等于把箭头擦掉（D3 的反面）');
  });

  testWidgets('点年月标题打开月份弹层，选完直接跳到那个月', (tester) async {
    await _openDatePicker(tester, buildLightTheme(), DateTime(2026, 11, 12));

    await tester.tap(find.text(L10n.yearMonth(DateTime(2026, 11, 1))));
    await tester.pumpAndSettle();
    expect(find.text(L10n.jumpToMonth), findsOneWidget,
        reason: '标题要能点开月份弹层，不再只能逐月点箭头');

    await tester.tap(find.text(L10n.monthShort(3)));
    await tester.pumpAndSettle();
    expect(find.text(L10n.yearMonth(DateTime(2026, 3, 1))), findsOneWidget,
        reason: '选完月份，日期选择器的年月标题要跟着走');
    expect(find.text(L10n.jumpToMonth), findsNothing, reason: '月份弹层要关掉');
  });

  testWidgets('翻月时弹层高度不随当月周数变化', (tester) async {
    // 2026-10：10 月 1 日是周四 → 5 行；2026-11：11 月 1 日是周日 → 6 行。
    // 改之前这一对月份正好差一行，是 issue #7 第三条的证据。
    await _openDatePicker(tester, buildLightTheme(), DateTime(2026, 10, 15));
    final before = tester.getSize(find.byType(GlassPanel)).height;

    await tester.tap(find.byIcon(Icons.chevron_right_outlined));
    await tester.pumpAndSettle();
    expect(find.text(L10n.yearMonth(DateTime(2026, 11, 1))), findsOneWidget,
        reason: '箭头仍要能翻月');

    final after = tester.getSize(find.byType(GlassPanel)).height;
    expect(after, before, reason: '高度必须钉死，不许随 30/31 天的行数跳');
  });

  testWidgets('点日期仍返回选中那天（改标题入口不许碰这条主路径）', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                picked = await showGlassDatePicker(context,
                    initialDate: DateTime(2026, 11, 12));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2026, 11, 20));
  });
}
