// app/tool/gif/render_gifs_test.dart
//
// 逐帧出图 → `scripts/make_gif.py` 合成动图。
//
// **为什么不放在 `tool/visual/`**：那里的 300 条是**回归护栏**（把界面出图留档、供
// 人工审阅与前后对比），这里是**产出素材**（更新简介、商店页要用的动图）。两者的产物
// 与跑法都不同，混在一起会让护栏的条数随「这次要不要出动图」浮动。
//
// 只拍**动**的东西 —— 静止就能看明白的走 `tool/visual/` 那条线（长期记忆
// `prefer-gifs-for-feature-demos`）。
//
// 跑法：
//   flutter test tool/gif/render_gifs_test.dart
//   python scripts/make_gif.py --prefix drag_liquid_dark_ --out work/gif/nav-drag.gif \
//       --crop 0,1540,840,1800 --width 620 --fps 13 --colors 96

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

/// **液态档必须走 prefs**，不能只调 `useLiquidGlassTier()`：屏幕一
/// `ref.watch(appSettingsProvider)` 就会建 notifier、`_load()` 读 prefs，把那个
/// 模块级标志覆盖回去 —— v0.10.1 出过这个岔子：工装那两张「液态档」基线图与标准档
/// **逐字节相同**，而「出图看差异、差异必须看得见」那道人工闸门在差异为 0 时静默通过。
/// 这条动图脚本当年也中过同一个招：拍出来的其实是标准档。
final Map<String, Object> _liquidPrefs = <String, Object>{
  ...onboardingPrefs,
  'liquidGlass': true,
};

/// 底栏上「沿宽度 [f] 那一带」的位置。**按几何算、不靠 widget key** ——
/// `nav-highlight` 那个 key 只存在于标准档的树上（液态档那枚滑块已经换成透镜了）。
Offset _navAt(WidgetTester tester, double f) {
  final Rect nav = tester.getRect(find.byKey(const Key('glass-nav-bar')));
  return Offset(nav.left + nav.width * f, nav.center.dy);
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

  // ① 底栏滑块被按住拖动：透镜**凸出胶囊**、形状跟着速度拉伸、光谱环跟着走。
  //    凸起只在按住时发生，静止帧拍不到。
  for (final ({String suffix, Brightness brightness}) v in _modes) {
    testWidgets('底栏拖动 · ${v.suffix}', (tester) async {
      final db = await freshDb();
      late TestGesture gesture;
      bool released = false;
      await renderFrames(
        tester,
        prefix: 'drag_liquid_${v.suffix}_',
        home: const HomeShell(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        extraPrefs: _liquidPrefs,
        brightness: v.brightness,
        count: 44,
        step: const Duration(milliseconds: 70),
        onFrame: (tester, i) async {
          if (i == 0) {
            gesture = await tester.startGesture(_navAt(tester, 0.15));
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
            await gesture.up(); // 松手 → 弹簧落回、页面跟过去
            released = true;
          }
        },
      );
    });
  }

  // ①b 彩边的**渐入渐出**：按住拖起来 → 手指停住不动 → 松手。
  //
  //    用户 2026-10-01：「彩边出现得太突然了。我的手不动它时没有，一动它就突然
  //    出来了……以及咱们手停下来的时候，也得有点过渡，不要突然就没了。」
  //
  //    这一条的时间轴就是照那句话铺的：前 20 帧按住不动（**没有彩边**）→ 中间 23 帧
  //    拖动（**渐入**）→ 后 28 帧手指停住、但**不松手**（**渐出**）→ 最后松手落回。
  //    没有「停住但不松手」这一段，就拍不出「手停下来它不会突然没」。
  testWidgets('彩边渐入渐出 · light', (tester) async {
    final db = await freshDb();
    late TestGesture gesture;
    bool released = false;
    await renderFrames(
      tester,
      prefix: 'bloom_',
      home: const HomeShell(),
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      extraPrefs: _liquidPrefs,
      // **必须 16ms 一帧**：`LiquidLensSpring.step` 把每帧积分封顶在
      // `lensMaxStep`（16ms），喂 55ms 一帧的话整段动画会慢 3.4 倍 ——
      // 拍出来的「渐入」比真机拖沓得多（第一版就是这么拍的，量出来要 440ms
      // 才爬到一半）。出图按 16ms，合成时用 `--fps 60` 还原成实时。
      count: 80,
      step: const Duration(milliseconds: 16),
      onFrame: (tester, i) async {
        if (i == 0) {
          gesture = await tester.startGesture(_navAt(tester, 0.18));
          addTearDown(() {
            if (!released) return gesture.up();
            return Future<void>.value();
          });
          await tester.pump(const Duration(milliseconds: 16));
        } else if (i <= 19) {
          // 按住不动 320ms：透镜已经提起，但**一点彩边都没有**
        } else if (i <= 42) {
          await gesture.moveBy(const Offset(3, 0)); // 187px/s → 渐入
        } else if (i <= 70) {
          // 手指停住、**不松手** 450ms：速度归零 → 渐出
        } else if (i == 71) {
          await gesture.up();
          released = true;
        }
      },
    );
  });

  // ② 点按换页：透镜**滑过去**、**不提起**。
  //
  //    与 ① 是一对反例：同样是从一格到另一格，① 是「按住吸附 + 放大 + 形变」，
  //    ② 是「不提起、纯粹滑过去」—— 这正是用户 2026-10-01 那条交互契约的两半。
  for (final ({String suffix, Brightness brightness}) v in _modes) {
    testWidgets('点按换页 · ${v.suffix}', (tester) async {
      final db = await freshDb();
      await renderFrames(
        tester,
        prefix: 'tap_liquid_${v.suffix}_',
        home: const HomeShell(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        extraPrefs: _liquidPrefs,
        brightness: v.brightness,
        count: 30,
        step: const Duration(milliseconds: 40),
        onFrame: (tester, i) async {
          if (i != 0) return;
          await tester.tapAt(_navAt(tester, 0.85));
        },
      );
    });
  }

  // ③ 开关按一下：把手**按住时鼓起**、松手缩回并翻过去。
  //
  //    注意它现在拍的是**标准档**的开关 —— v0.10.3 把液态效果收拢到底栏之后，
  //    开关上那一版已经删掉了（`liquid_scope_guard_test` 守着）。留着这条是因为
  //    更新简介里那个「Q 弹」的通用说法要用到它。
  for (final ({String suffix, Brightness brightness}) v in _modes) {
    testWidgets('开关按一下 · ${v.suffix}', (tester) async {
      final db = await freshDb();
      late TestGesture gesture;
      bool released = false;
      await renderFrames(
        tester,
        prefix: 'switch_${v.suffix}_',
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
