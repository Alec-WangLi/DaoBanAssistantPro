// app/tool/promo/render_promo_gifs_test.dart
//
// README / 酷安用的**动图**素材（v0.14.0 起从工装逐帧出，不再靠真机录屏）。
//
//   toolchain/flutter/bin/flutter test tool/promo/render_promo_gifs_test.dart
//   python scripts/make_gif.py --prefix gif_color_ --out docs/images/v0140-color.gif
//
// 为什么另起一个文件而不是塞进 `tool/gif/`：那边是**液态玻璃**的动效素材（底栏透镜、
// 开关升程、弹窗凝聚），每一条都在拍某一个交互的动画曲线；这里拍的是**功能本身**
// （换颜色、切按月、归档、字号），跟 README 的四段文案一一对应。混在一起会让
// 「这次要重出哪几张」变得看不出来。
//
// 数据用 `promoDatabase()`（与宣传图同一套假库：有待办、有自定义闹钟、「今天」落在白班），
// 这样动图与静态图里的内容一致，不会一张写着「还没有待办」而另一张有。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_check.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/schedule_editor_screen.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';

import '../visual/visual_harness.dart';
import 'render_promo_test.dart' show promoDatabase;

/// 点底栏某个 tab。限定在导航栏里找 —— 「闹钟」「我的」这些词页面上也有。
Future<void> _tapTab(WidgetTester tester, IconData icon) async {
  await tester.tap(find.descendant(
    of: find.byKey(const Key('glass-nav-bar')),
    matching: find.byIcon(icon),
  ));
}

/// 逐段移动的滚动（一次大位移实测会被滚动识别器吞掉）。
Future<void> _scrollDown(WidgetTester tester, double dy) async {
  final gesture = await tester.startGesture(const Offset(210, 700));
  const steps = 14;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, -dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await settleVisual(tester);
}

void main() {
  // 与静态宣传图分开落盘，免得 make_gif.py 误捡。
  kVisualOutDir = 'build/promo-gif';

  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
    await ensureVisualFonts();
  });
  setUp(setUpVisualPrefs);

  List<Override> overrides(AppDatabase db) =>
      <Override>[databaseProvider.overrideWithValue(db)];

  // ① 班次颜色：点色点 → 弹层 → 换一颗预设 → 确定。
  testWidgets('班次颜色', (tester) async {
    final db = await promoDatabase();
    addTearDown(db.close);
    await renderFrames(
      tester,
      prefix: 'gif_color_',
      home: ScheduleEditorScreen(scheduleId: await currentScheduleId(db)),
      overrides: overrides(db),
      extraPrefs: onboardingPrefs,
      count: 70,
      step: const Duration(milliseconds: 40),
      onFrame: (t, i) async {
        if (i == 6) {
          await t.tap(find.byKey(const ValueKey('shift-color-dot-0')));
        } else if (i == 30) {
          // 弹层里第 6 颗预设（换一个颜色，两颗日历小样会当场变）。
          await t.tap(find.byKey(const ValueKey('shift-preset-5')));
        } else if (i == 46) {
          await t.tap(find.text(L10n.confirm));
        }
      },
    );
  });

  // ② 按月排班：滚到编辑器底部 → 切「按月」→ 滚到切法那一节。
  testWidgets('按月排班', (tester) async {
    final db = await promoDatabase();
    addTearDown(db.close);
    await renderFrames(
      tester,
      prefix: 'gif_monthly_',
      home: ScheduleEditorScreen(scheduleId: await currentScheduleId(db)),
      overrides: overrides(db),
      extraPrefs: onboardingPrefs,
      count: 80,
      step: const Duration(milliseconds: 40),
      onFrame: (t, i) async {
        if (i == 6) {
          // 编辑器是懒构建的长列表：按月那一段在屏幕外，先滚到它再点。
          final mode = find.text(L10n.scheduleModeMonthly);
          await t.scrollUntilVisible(mode, 240,
              scrollable: find.byType(Scrollable).first);
          await settleVisual(t);
          await t.tap(mode.first);
        } else if (i == 30) {
          await _scrollDown(t, 420);
        } else if (i == 54) {
          await _scrollDown(t, 260);
        }
      },
    );
  });

  // ③ 待办自动归档：勾一条 → 落进「已完成」→ 点开折叠区再看见它。
  testWidgets('待办自动归档', (tester) async {
    final db = await promoDatabase();
    addTearDown(db.close);
    await renderFrames(
      tester,
      prefix: 'gif_archive_',
      home: const HomeShell(),
      overrides: overrides(db),
      extraPrefs: onboardingPrefs,
      count: 80,
      step: const Duration(milliseconds: 40),
      onFrame: (t, i) async {
        if (i == 6) {
          await _tapTab(t, Icons.event_note_outlined);
        } else if (i == 22) {
          await t.tap(find.byType(GlassCheck).first);
        } else if (i == 52) {
          await t.tap(find.textContaining('已完成').first);
        }
      },
    );
  });

  // ④ 字号四档：我的 → 滚到字体大小 → 点「特大」→ 回日历看效果。
  testWidgets('字号四档', (tester) async {
    final db = await promoDatabase();
    addTearDown(db.close);
    await renderFrames(
      tester,
      prefix: 'gif_font_',
      home: const HomeShell(),
      overrides: overrides(db),
      extraPrefs: onboardingPrefs,
      count: 96,
      step: const Duration(milliseconds: 40),
      onFrame: (t, i) async {
        if (i == 6) {
          await _tapTab(t, Icons.person_outlined);
        } else if (i == 16) {
          await settleVisual(t);
          // 滚到「字体大小」那一行（懒构建列表：不滚到它就找不到四档）。
          await t.scrollUntilVisible(find.text(L10n.fontSize), 200,
              scrollable: find.byType(Scrollable).first);
          await settleVisual(t);
        } else if (i == 34) {
          await t.tap(find.text(L10n.fontExtraLarge).first);
        } else if (i == 52) {
          await _tapTab(t, Icons.calendar_month_outlined);
        }
      },
    );
  });
}
