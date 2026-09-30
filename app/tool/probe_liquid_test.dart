// 液态档探针：**临时文件，不是回归工装的一部分。**
//
// 它不放进 `tool/visual/`，就是为了不被 `flutter test tool/visual/` 扫进那 270 条里
// （那些是永久护栏，这个是一次性实验）。跑法：
//
//   flutter test tool/probe_liquid_test.dart
//
// 要回答的问题：在不碰标准档的前提下，靠「加色」的那一层（方向性边缘光 / 主色着色）
// 能不能让液态档明显好看？—— 折射那一条已经实测证否（平背景上 ≤1/255）。
//
// 三个状态各出浅深两张图，落到 `build/visual/probe_*.png`，看图定夺。

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';

import 'visual/visual_harness.dart';

/// 逐帧出图，供 `scripts/make_gif.py` 合成 GIF。
///
/// 与 [renderScreen] 的区别是它**故意不稳住**：动画必须还在走才拍得成动图。
/// [onFrame] 在每帧取像**之前**调用，用来推进手势 / 切换状态；
/// 每帧之后按 [step] 推进时钟。产物落 `build/visual/frames/<prefix>NNN.png`。
Future<void> renderFrames(
  WidgetTester tester, {
  required String prefix,
  required Widget home,
  required List<Override> overrides,
  required int count,
  Duration step = const Duration(milliseconds: 80),
  Brightness brightness = Brightness.light,
  Map<String, Object> extraPrefs = const {},
  Future<void> Function(WidgetTester tester, int frame)? onFrame,
}) async {
  final GlobalKey key = await pumpScreen(
    tester,
    home: home,
    overrides: overrides,
    brightness: brightness,
    extraPrefs: extraPrefs,
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  final Directory dir = Directory('$kVisualOutDir/frames');
  dir.createSync(recursive: true);

  for (int i = 0; i < count; i++) {
    if (onFrame != null) await onFrame(tester, i);
    final File file = File('${dir.path}/$prefix${i.toString().padLeft(3, '0')}.png');
    // 取像与写盘必须在真实异步区里（伪造时钟区里的 future 不会完成）——
    // 同 `visual_harness.dart` 的 renderScreen。
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: kVisualDpr);
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
    });
    await tester.pump(step);
  }
  stdout.writeln('[gif] $count 帧 → ${dir.path}/$prefix*.png');
  await teardownVisual(tester);
}

/// 第二轮只剩两个状态：现状 / 加边缘光。
///
/// 第一轮的「主色着色」已按实测砍掉（它把卡片洗成一块平色板，且 HIG 明确说
/// 「实心填充会破坏液态玻璃的性格」），所以不再出那一档的图。
const List<String> _states = <String>['off', 'rim'];

void _applyState(String state) {
  glassProbeRim = state == 'rim';
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await ensureVisualFonts();
  });

  setUp(setUpVisualPrefs);

  Future<AppDatabase> freshDb() async {
    final db = await makeVisualDatabase();
    addTearDown(db.close);
    return db;
  }

  for (final String state in _states) {
    for (final ({String suffix, Brightness brightness}) v
        in <({String suffix, Brightness brightness})>[
      (suffix: 'light', brightness: Brightness.light),
      (suffix: 'dark', brightness: Brightness.dark),
    ]) {
      testWidgets('探针 · $state · ${v.suffix}', (tester) async {
        _applyState(state);
        addTearDown(() => glassProbeRim = false);

        final db = await freshDb();
        await renderScreen(
          tester,
          name: 'probe_${state}_${v.suffix}',
          home: const CalendarScreen(),
          overrides: <Override>[databaseProvider.overrideWithValue(db)],
          brightness: v.brightness,
        );
      });
    }
  }

  // 底栏导航胶囊那一条 —— 它是「有内容从底下穿过」的面，折射若将来要做，
  // 效果主要在它身上。整壳一屏能同时看到顶栏胶囊与底栏胶囊。
  testWidgets('探针 · rim · 主壳（含底栏胶囊）', (tester) async {
    glassProbeRim = true;
    addTearDown(() => glassProbeRim = false);

    final db = await freshDb();
    await renderScreen(
      tester,
      name: 'probe_rim_shell',
      home: const HomeShell(),
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      extraPrefs: onboardingPrefs,
    );
  });

  // 「按住滑动」的中途帧：滑块正被拖着、放大着，且没松手 —— 光的响应只在
  // 这个状态下才画得出来，静止帧看不见它。off / rim 各出一张做对比。
  for (final String state in _states) {
    testWidgets('探针 · $state · 底栏按住滑动中', (tester) async {
      _applyState(state);
      addTearDown(() => glassProbeRim = false);

      final db = await freshDb();
      await renderScreen(
        tester,
        name: 'probe_drag_$state',
        home: const HomeShell(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        extraPrefs: onboardingPrefs,
        // 起手点取滑块自己（`nav-highlight`），再往左拖半格并**不松手**：
        // 松手会弹回吸附位、缩放也回到 1.0，那样就拍不到中途态了。
        beforeCapture: (tester) async {
          final slider = find.byKey(const Key('nav-highlight'));
          final gesture = await tester.startGesture(tester.getCenter(slider));
          addTearDown(() => gesture.up());
          await tester.pump(const Duration(milliseconds: 16));
          await gesture.moveBy(const Offset(-58, 0));
          await tester.pump(const Duration(milliseconds: 16));
        },
      );
    });
  }

  // 动图：底栏滑块被按住拖动的一整段。
  //
  // 两个用途：① 回答「滑块滑过时有没有光的响应」—— 那是**动**的过程，静止帧拍不出来；
  // ② 验证 GIF 管线（`scripts/make_gif.py`）能不能用于以后的更新简介。
  for (final String state in _states) {
    for (final ({String suffix, Brightness brightness}) v
        in <({String suffix, Brightness brightness})>[
      (suffix: 'light', brightness: Brightness.light),
      (suffix: 'dark', brightness: Brightness.dark),
    ]) {
      testWidgets('动图 · $state · 底栏拖动 · ${v.suffix}', (tester) async {
        _applyState(state);
        addTearDown(() => glassProbeRim = false);

        final db = await freshDb();
        late TestGesture gesture;
        bool released = false;
        await renderFrames(
          tester,
          prefix: 'drag_${state}_${v.suffix}_',
          home: const HomeShell(),
          overrides: <Override>[databaseProvider.overrideWithValue(db)],
          extraPrefs: onboardingPrefs,
          brightness: v.brightness,
          count: 44,
          step: const Duration(milliseconds: 70),
          onFrame: (tester, i) async {
            if (i == 0) {
              final slider = find.byKey(const Key('nav-highlight'));
              gesture = await tester.startGesture(tester.getCenter(slider));
              // 幂等：帧 26 已经松过手的话，这里不能再 `up()`（指针已抬起，
              // TestGesture 会断言失败）。
              addTearDown(() {
                if (!released) return gesture.up();
                return Future<void>.value();
              });
              await tester.pump(const Duration(milliseconds: 16));
            } else if (i < 26) {
              // 从「日历」往右拖约一格（每帧 4px），滑块一路放大着走
              await gesture.moveBy(const Offset(4, 0));
            } else if (i == 26) {
              await gesture.up(); // 松手 → 吸附、回弹、页面跟过去
              released = true;
            }
          },
        );
      });
    }
  }
}
