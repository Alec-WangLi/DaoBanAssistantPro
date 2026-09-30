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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';

import 'visual/visual_harness.dart';

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
}
