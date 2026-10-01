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
import 'package:shiftassistantpro/features/home/home_shell.dart';
import 'package:shiftassistantpro/features/calendar/shift_template_picker_screen.dart';
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
          extraPrefs: <String, Object>{
            ...(screen.needsOnboardingPrefs ? onboardingPrefs : const {}),
            ...screenExtraPrefs(screen.slug),
          },
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

  // 底栏 · 液态 · 按住拖到一半。
  //
  // **静止帧拍不到这一档的全部** —— 凸出胶囊、沿运动方向拉伸、光谱环与那条被折射的
  // 边，都只在**按住**的时候才发生（松手就没了）。所以要起手拖动、**拖到一半停住**
  // 再取像。
  //
  // 时序不能省：这个 `GestureDetector` 同时挂着 tap 与横向拖动两个识别器，
  // `onTapDown` 要等竞技场裁决（`kPressTimeout` = 100ms）才触发；升程的闸门
  // （`lensHoldDelay` = 110ms）再晚一点。先按 30ms 一帧推够这两段，再拖。
  // **五档变体全出**，不是只出手机那一张。
  //
  // 这条屏一开始只渲了 420×900 一张 —— 于是**小窗 200×400 那一档从头到尾没被
  // 「看过」**，而窄窗恰好是「透镜整个画不出来」那个 Critical 的现场（工装出图的
  // 意义就在这里；AGENTS.md 里「没有屏单 = 没有眼睛」已经记过两次，这是第三次）。
  for (final variant in visualVariants) {
    visualTest('底栏 · 液态 · 按住拖到一半 · ${variant.label}', (tester) async {
      failOnOverflow(tester);
      final db = await freshDb();
      await renderScreen(
        tester,
        name: '40_nav_lens_dragging_${variant.suffix}',
        home: const HomeShell(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        brightness: variant.brightness,
        language: variant.language,
        size: variant.size,
        // 液态档必须走 prefs —— 只拨模块标志会被 `_load()` 覆盖回去（v0.10.1 踩过）。
        extraPrefs: <String, Object>{...onboardingPrefs, 'liquidGlass': true},
        beforeCapture: (t) async {
          final Rect nav = t.getRect(find.byKey(const Key('glass-nav-bar')));
          final TestGesture g = await t.startGesture(
              Offset(nav.left + nav.width * 0.25, nav.center.dy));
          addTearDown(g.up); // 取像之后不松手会留下一个未完成的指针
          for (int i = 0; i < 12; i++) {
            await t.pump(const Duration(milliseconds: 30));
          }
          for (int i = 0; i < 8; i++) {
            await g.moveBy(const Offset(12, 0));
            await t.pump(const Duration(milliseconds: 16));
          }
        },
      );
    });
  }

  // 底栏 · 液态 · **正在动**（手指还在走的那一刻）。
  //
  // 与上面那条 `40_nav_lens_dragging` 是**故意的反例**，两条缺一不可：
  // 那一条在 `beforeCapture` 之后会被 `settleVisual`（60 帧）稳住，而手指停在原地
  // —— 于是透镜速度衰减到 0。**光谱环、折边、形变全都由速度驱动**，所以那一屏拍到的
  // 其实是「按住但静止」，恰好是这个档位唯一一切都正常的那个状态。
  // **用户 2026-10-05 说的「彩色边缘看不出来」因此从没在任何一张图上现形过。**
  //
  // 靠 `settleAfterCapture: false` 取「还在动」的那一帧。速度**故意取慢的**：
  // 每帧 16ms 走 5px = **312px/s**，比一格 90px 走 290ms —— 一次不紧不慢的正常拖动。
  //
  // 为什么不取快的（750px/s 那种）：旧代码的环亮度是 `× clamp(v / 700)`，**在快的那
  // 一端它本来就是满的** —— 拍快了这条屏单刚好盖住要看的那个变化。用户说的
  // 「看不出来」发生在 200~400px/s 这一段：旧代码在那里只有三成亮度，新的是一来就满。
  for (final variant in visualVariants) {
    visualTest('底栏 · 液态 · 正在动 · ${variant.label}', (tester) async {
      failOnOverflow(tester);
      final db = await freshDb();
      await renderScreen(
        tester,
        name: '41_nav_lens_moving_${variant.suffix}',
        home: const HomeShell(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        brightness: variant.brightness,
        language: variant.language,
        size: variant.size,
        extraPrefs: <String, Object>{...onboardingPrefs, 'liquidGlass': true},
        settleAfterCapture: false,
        beforeCapture: (t) async {
          final Rect nav = t.getRect(find.byKey(const Key('glass-nav-bar')));
          final TestGesture g = await t.startGesture(
              Offset(nav.left + nav.width * 0.2, nav.center.dy));
          addTearDown(g.up);
          for (int i = 0; i < 12; i++) {
            await t.pump(const Duration(milliseconds: 30)); // 过长按闸门
          }
          for (int i = 0; i < 12; i++) {
            await g.moveBy(const Offset(5, 0));
            await t.pump(const Duration(milliseconds: 16));
          }
        },
      );
    });
  }
}
