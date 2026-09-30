// app/tool/gif/render_gifs_test.dart
//
// 逐帧出图 → `scripts/make_gif.py` 合成动图。
//
// **为什么不放在 `tool/visual/`**：那里的 270 条是**回归护栏**（把界面出图留档、供
// 人工审阅与前后对比），这里是**产出素材**（更新简介、商店页要用的动图）。两者的产物
// 与跑法都不同，混在一起会让护栏的条数随「这次要不要出动图」浮动。
//
// 只拍**动**的东西 —— 静止就能看明白的走 `tool/visual/` 那条线（长期记忆
// `prefer-gifs-for-feature-demos`）。
//
// 跑法：
//   flutter test tool/gif/render_gifs_test.dart
//   python scripts/make_gif.py --prefix drag_liquid_dark_ --out work/gif/nav.gif \
//       --crop 0,1490,840,1840 --width 620 --fps 13 --colors 96

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';

import '../visual/visual_harness.dart';

const List<({String suffix, Brightness brightness})> _modes =
    <({String suffix, Brightness brightness})>[
  (suffix: 'light', brightness: Brightness.light),
  (suffix: 'dark', brightness: Brightness.dark),
];

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

  // ① 底栏滑块被按住拖动：透镜**凸出胶囊**、边缘光跟着滑块走。
  //    凸起只在按住时发生，静止帧拍不到。
  for (final ({String suffix, Brightness brightness}) v in _modes) {
    testWidgets('底栏拖动 · ${v.suffix}', (tester) async {
      useLiquidGlassTier();
      final db = await freshDb();
      late TestGesture gesture;
      bool released = false;
      await renderFrames(
        tester,
        prefix: 'drag_liquid_${v.suffix}_',
        home: const HomeShell(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        extraPrefs: onboardingPrefs,
        brightness: v.brightness,
        count: 44,
        step: const Duration(milliseconds: 70),
        onFrame: (tester, i) async {
          if (i == 0) {
            gesture = await tester.startGesture(
                tester.getCenter(find.byKey(const Key('nav-highlight'))));
            // 幂等：帧 26 已经松过手的话这里不能再 `up()`（指针已抬起，
            // TestGesture 会断言失败）。
            addTearDown(() {
              if (!released) return gesture.up();
              return Future<void>.value();
            });
            await tester.pump(const Duration(milliseconds: 16));
          } else if (i < 26) {
            await gesture.moveBy(const Offset(4, 0)); // 往右拖约一格
          } else if (i == 26) {
            await gesture.up(); // 松手 → 吸附、回弹、页面跟过去
            released = true;
          }
        },
      );
    });
  }

  // ② 开关按一下：把手**按住时鼓起**成透镜、松手缩回并翻过去。
  for (final ({String suffix, Brightness brightness}) v in _modes) {
    testWidgets('开关按一下 · ${v.suffix}', (tester) async {
      useLiquidGlassTier();
      final db = await freshDb();
      late TestGesture gesture;
      bool released = false;
      await renderFrames(
        tester,
        prefix: 'switch_liquid_${v.suffix}_',
        home: const _SwitchBoard(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        brightness: v.brightness,
        count: 30,
        step: const Duration(milliseconds: 60),
        onFrame: (tester, i) async {
          if (i == 0) {
            gesture = await tester.startGesture(
                tester.getCenter(find.byKey(const ValueKey<bool>(true))));
            addTearDown(() {
              if (!released) return gesture.up();
              return Future<void>.value();
            });
          } else if (i == 14) {
            await gesture.up();
            released = true;
          }
          await tester.pump(const Duration(milliseconds: 16));
        },
      );
    });
  }
}

/// 开关特写用的板子：一行「开」一行「关」，落在中性的页面底色上 ——
/// 单看开关本身，不被整页其它玻璃面干扰。
class _SwitchBoard extends StatelessWidget {
  const _SwitchBoard();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (final bool v in <bool>[true, false])
              Padding(
                padding: const EdgeInsets.all(AppTokens.space2xl),
                child: GlassSwitch(
                  key: ValueKey<bool>(v),
                  value: v,
                  onChanged: (bool _) {},
                ),
              ),
          ],
        ),
      ),
    );
  }
}
