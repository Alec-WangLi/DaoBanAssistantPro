// app/tool/visual/render_screens_test.dart
//
// 把主要界面渲染成 PNG 到 `app/build/visual/`。
//
//   toolchain/flutter/bin/flutter test tool/visual/render_screens_test.dart
//
// 用途是**看**，不是比对：没有 golden 基线，不因像素差异失败。唯一的断言是
// 「渲染期间没有布局溢出」——把肉眼才能发现的问题固定成可回归的信号。
//
// 界面清单与变体在 visual_screens.dart，与对比度审计共用同一份。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';

import 'visual_harness.dart';
import 'visual_screens.dart';

/// 渲染用例统一带超时：工装里一旦有东西卡住（比如取像没切到真实异步区），
/// 要看到一条明确的失败，而不是一个永远不结束的进程。
void visualTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, body, timeout: const Timeout(Duration(seconds: 45)));
}

void main() {
  // 字体与 locale 数据都必须在这里装：只有 setUpAll 不在 fake_async 的伪造
  // 时钟区里，真 I/O 才会完成（详见 ensureVisualFonts 的注释）。
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
    await ensureVisualFonts();
  });

  setUp(setUpVisualPrefs);

  /// 每个用例一套干净的库，避免前一个用例的改动漏到后一个的图里。
  Future<AppDatabase> freshDb() async {
    final db = await makeVisualDatabase();
    addTearDown(db.close);
    return db;
  }

  for (final screen in visualScreens) {
    for (final variant in visualVariants) {
      visualTest('${screen.title} · ${variant.label}', (tester) async {
        failOnOverflow(tester);
        final db = await freshDb();
        await renderScreen(
          tester,
          name: '${screen.slug}_${variant.suffix}',
          home: await screen.build(db),
          overrides: <Override>[databaseProvider.overrideWithValue(db)],
          brightness: variant.brightness,
          language: variant.language,
          extraPrefs: screen.needsOnboardingPrefs ? onboardingPrefs : const {},
        );
      });
    }
  }

  visualTest('日历 · 点开某天', (tester) async {
    failOnOverflow(tester);
    final db = await freshDb();
    await renderScreen(
      tester,
      name: '01_calendar_day_selected',
      home: const CalendarScreen(),
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      beforeCapture: (t) async {
        // 选一个「非今天」的日子，日详情卡才会展开出班次与时间。
        final day = DateTime.now().add(const Duration(days: 2));
        await t.tap(find.text('${day.day}').first);
      },
    );
  });
}
