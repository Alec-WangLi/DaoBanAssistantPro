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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/features/calendar/shift_template_picker_screen.dart';

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
          size: variant.size,
          extraPrefs: screen.needsOnboardingPrefs ? onboardingPrefs : const {},
        );
      });
    }
  }

  // 「向下滚动后」：首屏之下的内容（权限卡、自定义闹钟列表……）也要拍得到，
  // 清单见 `visualScrollDown`。只出浅色 / 深色两档——滚动后要看的是**版式与
  // 文案**，跟语言、横竖屏无关，每档都出一份只是把图数翻倍。
  for (final entry in visualScrollDown.entries) {
    final screen = visualScreens.firstWhere(
      (s) => s.slug == entry.key,
      orElse: () => throw StateError(
          'visualScrollDown 里的 ${entry.key} 不在 visualScreens 里 —— 屏改名了？'),
    );
    for (final variant in visualVariants
        .where((v) => v.suffix == 'light' || v.suffix == 'dark')) {
      visualTest('${screen.title} · ${variant.label} · 向下滚动后', (tester) async {
        failOnOverflow(tester);
        final db = await freshDb();
        await renderScreen(
          tester,
          name: '${screen.slug}_${variant.suffix}_scrolled',
          home: await screen.build(db),
          overrides: <Override>[databaseProvider.overrideWithValue(db)],
          brightness: variant.brightness,
          language: variant.language,
          size: variant.size,
          extraPrefs: screen.needsOnboardingPrefs ? onboardingPrefs : const {},
          beforeCapture: (t) async {
            // 拖主滚动区：各屏的首个 Scrollable 就是页面本身（列表 / 滚动容器）。
            await t.drag(find.byType(Scrollable).first, Offset(0, -entry.value));
            await settleVisual(t);
          },
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

  // 「两字简称」的日历：内置模板的简称都是单字，单字看不出胶囊放不放得下两个
  // 字。v0.7.1 真机上两个字的简称被省略成「上…」、系统字号放大后整串消失 ——
  // 这类问题只有看图能发现，所以单出一张。
  visualTest('日历 · 两字简称', (tester) async {
    failOnOverflow(tester);
    final db = await freshDb();
    await makeLongCycleCurrent(db);
    await renderScreen(
      tester,
      name: '09_calendar_long_abbr',
      home: const CalendarScreen(),
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
    );
  });

  // 搜不到倒班方式那张空态。**只能单独一个用例**：搜索词 `_query` 是选择页的
  // 内部状态、构造参数进不去，必须首帧之后真敲一次字（`beforeCapture`）。
  // 也正因为它没法进 `visualScreens`（记录类型加可选字段要改全部 24 条），
  // 对比度审计不覆盖这一张 —— 那条空态用的全是既有令牌（rowPrimary /
  // rowSecondary / inkMuted），没有新引入的配色。
  visualTest('倒班方式选择 · 搜索落空', (tester) async {
    failOnOverflow(tester);
    final db = await freshDb();
    await renderScreen(
      tester,
      name: '19_template_picker_no_match',
      home: const ShiftTemplatePickerScreen(),
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      beforeCapture: (t) async {
        // 用一个**真实存在、但不在内置模板里**的班表名 —— 这正是这条反馈的原形。
        await t.enterText(find.byType(TextField), '上12休24');
        await t.pumpAndSettle();
      },
    );
  });
}
