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
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/widgets/glass_check.dart';
import 'package:shiftassistantpro/core/widgets/glass_segment.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';
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
        final extraPrefs = <String, Object>{
          ...(screen.needsOnboardingPrefs ? onboardingPrefs : const {}),
          ...screenExtraPrefs(screen.slug),
        };
        // ⚠️ **屏单里「液态档」不能只靠 prefs。** 读档位的那些屏是 `appSettingsProvider`
        // 的 `_load()` 把 prefs 落实到模块级标志上的；而**不读那个 provider 的屏**
        // （响铃页就是）prefs 根本落不到标志上 —— 拍出来与标准档**逐字节相同**。
        // v0.10.1 踩过一次，这次是它的新变种：`47_ringing_liquid` 第一版两张图一模一样，
        // 是**出图时当场看出来的**（不是任何断言抓到的）。
        if (extraPrefs['liquidGlass'] == true) useLiquidGlassTier();
        await renderScreen(
          tester,
          name: '${screen.slug}_${variant.suffix}',
          home: await screen.build(db),
          overrides: <Override>[databaseProvider.overrideWithValue(db)],
          brightness: variant.brightness,
          language: variant.language,
          size: variant.size,
          extraPrefs: extraPrefs,
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

  // 液态档那枚选中块的两档「活的」状态（v0.10.15）——
  // **静止帧拍不到它们**，而这一轮的全部内容就在这两档上：按住时四面鼓出、
  // 拖动时沿运动方向形变且边缘挤过格子里的字。手势必须真按下去（形状由弹簧与
  // 速度驱动，喂参数是拍不出真东西的）。
  for (final (String slug, String title, double dragBy)
      in <(String, String, double)>[
    ('49_calendar_lens_press', '日历 · 液态档选中块 · 按住', 0),
    ('50_calendar_lens_drag', '日历 · 液态档选中块 · 拖动中', 46),
  ]) {
    visualTest(title, (tester) async {
      failOnOverflow(tester);
      final db = await freshDb();
      useLiquidGlassTier();
      await renderScreen(
        tester,
        name: slug,
        home: const CalendarScreen(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        extraPrefs: <String, Object>{'liquidGlass': true},
        beforeCapture: (WidgetTester t) async {
          // 起点取今天那一格（选中块默认落在今天）；不能找 `calendar-selection-block`
          // 的**位置**去按 —— 那枚块在拖动中会跟着走，而起点得是格子。
          final TestGesture g = await t.startGesture(t.getCenter(
              find.byKey(ValueKey('day-card-${DateTime.now().day}'))));
          for (int i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 16)); // 过按住闸门
          }
          if (dragBy == 0) return;
          // 46px = 半格 28 + 被竞技场 slop 吃掉的 18 —— 落点正好在两格之间，
          // 右边那格的内容才会被透镜边缘挤到。
          const int steps = 8;
          for (int i = 0; i < steps; i++) {
            await g.moveBy(Offset(dragBy / steps, 0));
            await t.pump(const Duration(milliseconds: 16));
          }
        },
      );
    });
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
  // **用户 2026-10-01 说的「彩色边缘看不出来」因此从没在任何一张图上现形过。**
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

  // 分段器 · 液态 · **按住**那一刻。
  //
  // 「静止」那两态在 `37_profile_liquid_*` 里已经有了；**按住时那枚滴凸出容器**
  // 只在按住时发生，静止帧拍不到 —— 这一屏专门拍它。
  //
  // 时序不能省：这个 `GestureDetector` 同时挂着 tap 与横向拖动两个识别器，
  // `onTapDown` 要等 `kPressTimeout`（100ms）才触发，升程的闸门（`lensHoldDelay`
  // = 110ms）再晚一点。所以按住之后要推够这两段。
  for (final variant in visualVariants) {
    visualTest('分段器 · 液态 · 按住 · ${variant.label}', (tester) async {
      failOnOverflow(tester);
      // 这两个宿主是**独立控件**，不读 `appSettingsProvider` —— 档位标志
      // 不会因为 prefs 被点亮（前几屏能亮是因为它们读 provider）。
      // 所以这里必须显式拨一下。
      useLiquidGlassTier();
      final db = await freshDb();
      await renderScreen(
        tester,
        name: '42_segment_liquid_${variant.suffix}',
        home: const _SegmentHost(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        brightness: variant.brightness,
        language: variant.language,
        size: variant.size,
        // 液态档必须走 prefs —— 只拨模块标志会被 `_load()` 覆盖回去（v0.10.1 踩过）。
        extraPrefs: <String, Object>{...onboardingPrefs, 'liquidGlass': true},
        beforeCapture: (WidgetTester t) async {
          final Rect box = t.getRect(find.byType(GlassSegment));
          final TestGesture g = await t.startGesture(
              Offset(box.left + box.width * 0.18, box.center.dy));
          addTearDown(g.up);
          for (int i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 30));
          }
        },
      );
    });
  }
  // 开关 · 液态 · **按住那一刻**（钮纵向拉长）。
  //
  // 「开」「关」两态在 `37_profile_liquid_*` 等屏里已经有了；**按住时钮被抽出来**
  // 只在按住时发生，静止帧拍不到 —— 这一屏专门拍它。
  for (final variant in visualVariants) {
    visualTest('开关 · 液态 · 按住 · ${variant.label}', (tester) async {
      failOnOverflow(tester);
      // 这两个宿主是**独立控件**，不读 `appSettingsProvider` —— 档位标志
      // 不会因为 prefs 被点亮（前几屏能亮是因为它们读 provider）。
      // 所以这里必须显式拨一下。
      useLiquidGlassTier();
      final db = await freshDb();
      await renderScreen(
        tester,
        name: '43_switch_liquid_${variant.suffix}',
        home: const _SwitchHost(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        brightness: variant.brightness,
        language: variant.language,
        size: variant.size,
        extraPrefs: <String, Object>{...onboardingPrefs, 'liquidGlass': true},
        beforeCapture: (WidgetTester t) async {
          // 按**最下面那一枚**（开着的那枚），上两枚作对照。
          final Rect box = t.getRect(find.byType(GlassSwitch).last);
          final TestGesture g = await t.startGesture(box.center);
          addTearDown(g.up);
          for (int i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 30));
          }
        },
      );
    });
  }

  // 开关 · 液态 · **拖动中**（「头大尾轻」那一态）。
  //
  // 与上面「按住」那条是**故意的配对**：按住不动时形变恒为 0，钮只是一枚竖着的椭圆；
  // 形状只有在**动**的时候才变。少了这一屏，「拖动时到底有没有头大尾轻」结构性地
  // 拍不到 —— 而这一轮争的正是它。
  //
  // ⚠️ **拖动距离必须先走掉 `kTouchSlop`（18px）**：识别器赢下竞技场之前那 18px 是
  // 空走的，而这条轨道一共只有 56 宽、钮只能走 25px。本轮第一版每帧只走 3px、六帧
  // 才 18px，识别器压根没收下这次拖动，两张图逐字节相同。
  for (final variant in visualVariants) {
    visualTest('开关 · 液态 · 拖动中 · ${variant.label}', (tester) async {
      failOnOverflow(tester);
      useLiquidGlassTier();
      final db = await freshDb();
      await renderScreen(
        tester,
        name: '46_switch_drag_${variant.suffix}',
        home: const _SwitchHost(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        brightness: variant.brightness,
        language: variant.language,
        size: variant.size,
        extraPrefs: <String, Object>{...onboardingPrefs, 'liquidGlass': true},
        settleAfterCapture: false,
        beforeCapture: (WidgetTester t) async {
          final Rect box = t.getRect(find.byType(GlassSwitch).last);
          final TestGesture g =
              await t.startGesture(Offset(box.right - 8, box.center.dy));
          addTearDown(g.up);
          for (int i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 30)); // 过长按闸门
          }
          await g.moveBy(const Offset(-18, 0)); // 走掉 kTouchSlop
          await t.pump(const Duration(milliseconds: 16));
          for (int i = 0; i < 6; i++) {
            await g.moveBy(const Offset(-3, 0)); // 187px/s，一次正常的拖动
            await t.pump(const Duration(milliseconds: 16));
          }
        },
      );
    });
  }

  // 待办 · **勾选态**（v0.10.10）。
  //
  // 待办原来用的是一枚开关，这一版换成了勾。屏单里已有的 `05_todos` 全是**没勾**的，
  // 所以「勾上之后长什么样」在图上结构性地看不见 —— 而它恰恰是这一版改的东西。
  // 点一下第一行那个勾，同一张图上就同时有「勾上」与「没勾」两态。
  //
  // 两档各出一张：一个 `GlassCheck` 只能读到一个档位（它读的是模块级标志），
  // 要同时拍到两档只能出两张。
  for (final bool liquid in <bool>[false, true]) {
    visualTest('待办 · 勾选态 · ${liquid ? '液态档' : '标准档'}', (tester) async {
      failOnOverflow(tester);
      useLiquidGlassTier();
      if (!liquid) useStandardGlassTier();
      final db = await freshDb();
      await renderScreen(
        tester,
        name: liquid ? '45_todo_check_liquid' : '44_todo_check',
        home: const ScheduleScreen(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        extraPrefs: liquid
            ? <String, Object>{...onboardingPrefs, 'liquidGlass': true}
            : onboardingPrefs,
        beforeCapture: (t) async {
          await t.tap(find.byType(GlassCheck).first);
          await settleVisual(t);
        },
      );
    });
  }

}

/// 一屏只放三段分段器，用来单独看清液态档按住时那枚滴。
class _SegmentHost extends StatelessWidget {
  const _SegmentHost();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.space2xl),
            child: GlassSegment(
              count: 3,
              selectedIndex: 0,
              height: 40,
              onSelected: (int _) {},
              itemBuilder: (int i, bool sel) => Text(
                <String>['跟随系统', '浅色', '深色'][i],
                style: AppTokens.rowPrimary.copyWith(
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
}


/// 三枚开关：开 / 关 / **按住那一枚会被拍下来**。
class _SwitchHost extends StatelessWidget {
  const _SwitchHost();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              GlassSwitch(value: true, onChanged: _ignore),
              SizedBox(height: AppTokens.space2xl),
              GlassSwitch(value: false, onChanged: _ignore),
              SizedBox(height: AppTokens.space2xl),
              GlassSwitch(value: true, onChanged: _ignore),
            ],
          ),
        ),
      );

  static void _ignore(bool _) {}
}
