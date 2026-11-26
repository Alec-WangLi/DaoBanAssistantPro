// app/tool/promo/render_promo_video_test.dart
//
// 出**功能演示视频**用的逐帧素材（抖音 / 小红书 / B 站）。
//
//   toolchain/flutter/bin/flutter test tool/promo/render_promo_video_test.dart
//   python scripts/make_promo_video.py --assemble
//
// 和 `render_promo_test.dart`（静态图）、`render_promo_gifs_test.dart`（README 动图）
// 是同一套思路的第三个用途：**画面来自真实控件树**，不是真机录屏 ——
// 录屏有通知栏、有误触、有手指入画，而工装每一条交互都写在代码里，可以重跑。
//
// 三个刻意的差别：
//
//   1. **尺寸按视频定**：9:16、1080×1920。逻辑尺寸取 360×640（常见机型的 dp 宽度），
//      `toImage(pixelRatio: 3)` 正好三倍 → 1080×1920，字形是 3 倍栅格化的，不糊。
//      不复用 `renderFrames` 的原因就是它把 pixelRatio 写死成 kVisualDpr(2.0)。
//   2. **帧率 30**：录像与平台都按 30 走；`renderFrames` 默认 80ms 一步（12.5fps），
//      拖动和液态玻璃会一顿一顿。
//   3. **每场一条用例**：`flutter test --plain-name 日历` 可以只重渲染那一场，
//      改分镜时不用等全部重跑。
//
// 场次名会变成文件名前缀，`scripts/make_promo_video.py` 按前缀挑帧、按 `--scene`
// 顺序拼接，所以**改名要两边一起改**。
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_check.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/alarm/alarm_ringing_screen.dart';
import 'package:shiftassistantpro/features/calendar/shift_template_picker_screen.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';
import 'package:shiftassistantpro/features/stats/stats_screen.dart';

import '../visual/visual_harness.dart';
import 'render_promo_test.dart' show promoDatabase;

/// 9:16 的逻辑尺寸。乘 [kVideoDpr] 正好 1080×1920。
///
/// 为什么不取 360×640：那是 1080×1920 手机在 3 倍密度下的 dp，**高度只有 640dp**，
/// 而 640dp 装不下「周标题 + 六行日期 + 底栏信息卡」—— 实测最后一行被信息卡切掉。
/// 1080×1920 的真机密度多是 2.5 倍，也就是 432×768dp，这才是这类机器的真实 dp 尺寸。
const Size kVideoSize = Size(432, 768);
const double kVideoDpr = 2.5;

/// 30fps。用微秒是因为 1/30 秒不是整毫秒（33.333ms），按 33ms 走会每 30 秒偏
/// 掉一帧的时间 —— 拼接时长与口播时间码就对不上了。
const Duration kVideoStep = Duration(microseconds: 33333);

/// 逐帧渲染一场戏。
///
/// [onFrame] 在**抓图之前**调用，所以 `i` 那一帧拍到的是那一刻交互之后的样子。
/// 需要连续手势（拖动）时，在 `i` 对应的帧里 `moveBy` 一小段即可 —— 和
/// `render_promo_gifs_test.dart` 里那几个手势用例是同一个套路。
Future<void> recordScene(
  WidgetTester tester, {
  required String scene,
  required Widget home,
  required List<Override> overrides,
  required int frames,
  Future<void> Function(WidgetTester tester, int i)? onFrame,
  Map<String, Object> extraPrefs = const {},
  Brightness brightness = Brightness.light,
}) async {
  final GlobalKey key = await pumpScreen(
    tester,
    home: home,
    overrides: overrides,
    size: kVideoSize,
    brightness: brightness,
    extraPrefs: extraPrefs,
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  final Directory dir = Directory('$kVisualOutDir/frames');
  dir.createSync(recursive: true);

  for (int i = 0; i < frames; i++) {
    if (onFrame != null) await onFrame(tester, i);
    final File file =
        File('${dir.path}/${scene}_${i.toString().padLeft(4, '0')}.png');
    // 取像与写盘必须在真实异步区里（伪造时钟区里的 future 不会完成）。
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: kVideoDpr);
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await file.writeAsBytes(data!.buffer.asUint8List(), flush: false);
    });
    await tester.pump(kVideoStep);
  }
  stdout.writeln('[video] $scene → $frames 帧（${dir.path}/$scene*.png）');
  await teardownVisual(tester);
}

/// 点底栏某个 tab。必须限定在导航栏里找 —— 页面标题里有同名词。
Future<void> tapTab(WidgetTester tester, IconData icon) async {
  await tester.tap(find.descendant(
    of: find.byKey(const Key('glass-nav-bar')),
    matching: find.byIcon(icon),
  ));
}

void main() {
  // 与静态宣传图、README 动图分开落盘，免得 make_promo_images.py / make_gif.py 误捡。
  kVisualOutDir = 'build/promo-video';

  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
    await ensureVisualFonts();
  });
  setUp(setUpVisualPrefs);

  List<Override> overrides(AppDatabase db) =>
      <Override>[databaseProvider.overrideWithValue(db)];

  testWidgets('日历', (tester) async {
    final db = await promoDatabase();
    addTearDown(db.close);
    await recordScene(
      tester,
      scene: 's1_calendar',
      home: const HomeShell(),
      overrides: overrides(db),
      extraPrefs: onboardingPrefs,
      frames: 150,
      onFrame: (t, i) async {
        if (i == 12) {
          // 翻下个月：带上方向性动画（往前翻往左滑）。
          await t.tap(find.byIcon(Icons.chevron_right_outlined).first);
        } else if (i == 52) {
          await t.tap(find.byIcon(Icons.chevron_left_outlined).first);
        } else if (i == 78) {
          // 选一天：胶囊变实心、底栏信息卡跟着换。
          await t.tap(find.byKey(const ValueKey('day-card-18')));
        } else if (i == 118) {
          await t.tap(find.byKey(const ValueKey('day-card-26')));
        }
      },
    );
  });

  testWidgets('统计', (tester) async {
    final db = await promoDatabase();
    addTearDown(db.close);
    await recordScene(
      tester,
      scene: 's2_stats',
      home: const StatsScreen(),
      overrides: overrides(db),
      extraPrefs: onboardingPrefs,
      frames: 135,
      onFrame: (t, i) async {
        if (i == 70) {
          // 往下滚一段，让「出勤构成 + 请假占比」入画。
          final g = await t.startGesture(const Offset(180, 520));
          for (var k = 0; k < 14; k++) {
            await g.moveBy(const Offset(0, -13));
            await t.pump(const Duration(milliseconds: 16));
          }
          await g.up();
        }
      },
    );
  });

  testWidgets('统计年视图', (tester) async {
    final db = await promoDatabase();
    addTearDown(db.close);
    await recordScene(
      tester,
      scene: 's3_stats_year',
      home: const StatsScreen(initialYearMode: true),
      overrides: overrides(db),
      extraPrefs: onboardingPrefs,
      frames: 105,
      onFrame: (t, i) async {
        if (i == 45) {
          final g = await t.startGesture(const Offset(180, 560));
          for (var k = 0; k < 14; k++) {
            await g.moveBy(const Offset(0, -16));
            await t.pump(const Duration(milliseconds: 16));
          }
          await g.up();
        }
      },
    );
  });

  testWidgets('闹钟', (tester) async {
    final db = await promoDatabase();
    addTearDown(db.close);
    await recordScene(
      tester,
      scene: 's4_alarm',
      home: const HomeShell(),
      overrides: overrides(db),
      extraPrefs: onboardingPrefs,
      frames: 120,
      onFrame: (t, i) async {
        if (i == 8) {
          await tapTab(t, Icons.alarm_outlined);
        } else if (i == 45) {
          final g = await t.startGesture(Offset(kVideoSize.width / 2, 560));
          for (var k = 0; k < 14; k++) {
            await g.moveBy(const Offset(0, -14));
            await t.pump(const Duration(milliseconds: 16));
          }
          await g.up();
        }
      },
    );
  });

  testWidgets('响铃', (tester) async {
    final db = await promoDatabase();
    addTearDown(db.close);
    await recordScene(
      tester,
      scene: 's5_ringing',
      home: const AlarmRingingScreen(label: '白班'),
      overrides: overrides(db),
      extraPrefs: onboardingPrefs,
      frames: 90,
    );
  });

  testWidgets('待办', (tester) async {
    final db = await promoDatabase();
    addTearDown(db.close);
    await recordScene(
      tester,
      scene: 's6_todos',
      home: const HomeShell(),
      overrides: overrides(db),
      extraPrefs: onboardingPrefs,
      frames: 140,
      onFrame: (t, i) async {
        if (i == 8) {
          await tapTab(t, Icons.event_note_outlined);
        } else if (i == 40) {
          // 勾一条：字体变暗 + 删除线，然后收进「已完成」。
          await t.tap(find.byType(GlassCheck).first);
        } else if (i == 82) {
          await t.tap(find.textContaining('已完成').first);
        }
      },
    );
  });

  testWidgets('换班', (tester) async {
    final db = await promoDatabase();
    addTearDown(db.close);
    // 长按拖选一段日子 —— 手指必须**跨帧**按住，一次 drag 拍不到那条水带。
    TestGesture? drag;
    await recordScene(
      tester,
      scene: 's7_override',
      home: const HomeShell(),
      overrides: overrides(db),
      extraPrefs: onboardingPrefs,
      frames: 150,
      onFrame: (t, i) async {
        if (i == 12) {
          drag = await t.startGesture(
              t.getCenter(find.byKey(const ValueKey('day-card-9'))));
        } else if (i == 20) {
          // 长按识别阈值之后才开始移动。
          await t.pump(const Duration(milliseconds: 520));
        } else if (i > 20 && i <= 34) {
          await drag!.moveBy(const Offset(0, 9));
          await t.pump(const Duration(milliseconds: 16));
        } else if (i == 36) {
          await drag!.up();
          drag = null;
        } else if (i == 80) {
          // 点底栏那行班次：选择层里能改班 / 请假 / 加班。
          await t.tap(find.byKey(const Key('info-card-shift-entry')));
        }
      },
    );
  });

  testWidgets('倒班方式', (tester) async {
    final db = await promoDatabase();
    addTearDown(db.close);
    await recordScene(
      tester,
      scene: 's8_templates',
      home: const ShiftTemplatePickerScreen(),
      overrides: overrides(db),
      extraPrefs: onboardingPrefs,
      frames: 110,
      onFrame: (t, i) async {
        // 只滚不点：这张屏是被当作 home 直接装上去的，点卡片会走
        // `Navigator.pop(模板)` —— 没有上一页可回，画面会整块空掉。
        if (i == 15) {
          final g = await t.startGesture(Offset(kVideoSize.width / 2, 560));
          for (var k = 0; k < 14; k++) {
            await g.moveBy(const Offset(0, -13));
            await t.pump(const Duration(milliseconds: 16));
          }
          await g.up();
        } else if (i == 55) {
          final g = await t.startGesture(Offset(kVideoSize.width / 2, 560));
          for (var k = 0; k < 14; k++) {
            await g.moveBy(const Offset(0, -13));
            await t.pump(const Duration(milliseconds: 16));
          }
          await g.up();
        }
      },
    );
  });

  testWidgets('字号', (tester) async {
    final db = await promoDatabase();
    addTearDown(db.close);
    await recordScene(
      tester,
      scene: 's9_font',
      home: const HomeShell(),
      overrides: overrides(db),
      extraPrefs: onboardingPrefs,
      frames: 165,
      onFrame: (t, i) async {
        if (i == 8) {
          await tapTab(t, Icons.person_outlined);
        } else if (i == 22) {
          await settleVisual(t);
          await t.scrollUntilVisible(find.text(L10n.fontSize), 200,
              scrollable: find.byType(Scrollable).first);
          await settleVisual(t);
        } else if (i == 46) {
          await t.tap(find.text(L10n.fontExtraLarge).first);
        } else if (i == 96) {
          await tapTab(t, Icons.calendar_month_outlined);
        }
      },
    );
  });
}
