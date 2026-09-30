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
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/features/calendar/shift_template_picker_screen.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';
import 'package:shiftassistantpro/features/profile/profile_screen.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';

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
  // 档位是模块级标志，会在用例之间残留 —— 每个用例收尾都拨回标准档，
  // 免得「液态档那几条」把后面所有屏都染上。
  tearDown(useStandardGlassTier);

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

  // 「大字号」的日历：系统字号 1.8×（Android 字体大小设置里那一档）。
  //
  // 单出一张的理由与上面「两字简称」同源，而且更硬：**全 app 都没有钳制
  // `textScaler`，而工装此前每一屏都只在 1.0× 下出图** —— 于是「系统字号放大之后
  // 文字被截」这一类问题在图上结构性地看不见。2026-09-29 用户反馈的那张截图
  // （农历被截成「财…」「地…」、周标题那行挤进格子）就是这么漏掉的。
  //
  // 1.8 这个值是按「能把两条都压出来」挑的：周标题 13×1.8×1.15 ≈ 26.9 > `_weekdayH`
  // 的 26（原来会压进第一行格子），农历 11×1.25×1.8 ≈ 24.8、两个字就要 49.6 > 格
  // 内容宽的 44（原来会省略成「财…」）。
  //
  // 与「搜索落空」那张同理，它没有进 `visualScreens`（记录类型加可选字段要改全部
  // 24 条），所以对比度审计不覆盖它 —— 这一屏用的也全是既有令牌与既有配色。
  visualTest('日历 · 大字号', (tester) async {
    failOnOverflow(tester);
    final db = await freshDb();
    await renderScreen(
      tester,
      name: '20_calendar_large_font',
      home: const CalendarScreen(),
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      textScale: 1.8,
    );
  });

  // 新建弹窗里选了「每周」的样子：星期胶囊那一排的间距、选中态、以及它与
  // 「重复」四档胶囊的上下关系，只有看图才知道对不对。它是**内部状态**
  //（`_EventFields` 不公开），只能靠首帧之后真点。同理它没进 `visualScreens`
  //（记录类型加可选字段要改全部 24 条），对比度审计因此不覆盖这一张 ——
  // 这屏用的全是既有令牌与既有配色。
  visualTest('待办 · 新建弹窗选了每周', (tester) async {
    failOnOverflow(tester);
    final db = await freshDb();
    await renderScreen(
      tester,
      name: '26_todo_dialog_weekly',
      home: const ScheduleScreen(),
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      beforeCapture: (t) async {
        await t.tap(find.byIcon(Icons.add_outlined));
        await settleVisual(t);
        await t.tap(find.text(L10n.repeatWeekly));
        await settleVisual(t);
      },
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

  // 顶栏那颗按钮点开的**排班时段只读总览**。弹层是命令式的、没有可渲染的
  // widget，所以只能首帧之后真点一次那个入口 —— 与上面那张空态同一条路子。
  visualTest('日历 · 排班时段总览', (tester) async {
    failOnOverflow(tester);
    final db = await freshDb();
    await seedScheduleChain(db);
    await renderScreen(
      tester,
      name: '28_calendar_timeline',
      home: const CalendarScreen(),
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      beforeCapture: (t) async {
        await t.tap(find.byIcon(Icons.timeline));
        await settleVisual(t);
      },
    );
  });

  // ── 液态玻璃档 ──────────────────────────────────────────────────────────
  //
  // 这一档是**可选**的（「我的 → 外观」里那个开关，默认关）：它给玻璃叠一层边缘光，
  // 并让底栏滑块与开关在**按住时**鼓起成透镜。上面那些屏拍的全是标准档 ——
  // 默认档由 `useStandardGlassTier()`（`ensureVisualFonts` 里调的）保证，
  // 这里单出液态档，**两个档位各留一张底片**。
  //
  // 为什么必须进屏单：这几处的观感是五轮实测才收敛的 —— 白光照白底在浅色下
  // 结构性地看不见、透镜不凸出容器就谈不上折射 —— 而每一轮都只有「看图」能判断。
  // 没有屏单，下一次改动就没有眼睛。
  for (final ({String suffix, Brightness brightness}) v
      in <({String suffix, Brightness brightness})>[
    (suffix: 'light', brightness: Brightness.light),
    (suffix: 'dark', brightness: Brightness.dark),
  ]) {
    visualTest('主壳 · 液态玻璃 · ${v.suffix}', (tester) async {
      failOnOverflow(tester);
      final db = await freshDb();
      useLiquidGlassTier();
      await renderScreen(
        tester,
        name: '36_home_shell_liquid_${v.suffix}',
        home: const HomeShell(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        extraPrefs: onboardingPrefs,
        brightness: v.brightness,
      );
    });

    visualTest('我的 · 液态玻璃 · ${v.suffix}', (tester) async {
      failOnOverflow(tester);
      final db = await freshDb();
      useLiquidGlassTier();
      await renderScreen(
        tester,
        name: '37_profile_liquid_${v.suffix}',
        home: const ProfileScreen(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        brightness: v.brightness,
      );
    });
  }
}
