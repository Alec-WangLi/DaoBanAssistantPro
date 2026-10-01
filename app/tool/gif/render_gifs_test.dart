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
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/widgets/glass_check.dart';
import 'package:shiftassistantpro/core/widgets/glass_segment.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/alarm/alarm_ringing_screen.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';
import 'package:shiftassistantpro/features/profile/app_dialogs.dart';

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
  // ③ 分段器 · 液态 · 拖到下一格。
  //
  //    与底栏那条同源：按住提起 → 拖动时滴沿运动方向拉伸、边缘彩边渐入 →
  //    松手落回。**出帧必须 16ms**（弹簧每帧积分封顶在 `lensMaxStep`），
  //    合成时用 `--fps 60` 还原实时。
  testWidgets('分段器 · 液态 · 拖动 · light', (WidgetTester tester) async {
    useLiquidGlassTier();
    late TestGesture gesture;
    bool released = false;
    await renderFrames(
      tester,
      prefix: 'seg_liquid_',
      home: const _SegmentGifHost(),
      overrides: const <Override>[],
      count: 100,
      step: const Duration(milliseconds: 16),
      onFrame: (WidgetTester t, int i) async {
        if (i == 0) {
          final Rect box = t.getRect(find.byType(GlassSegment));
          gesture = await t.startGesture(
              Offset(box.left + box.width * 0.18, box.center.dy));
          addTearDown(() {
            if (!released) return gesture.up();
            return Future<void>.value();
          });
          await t.pump(const Duration(milliseconds: 16));
        } else if (i <= 24) {
          // 按住 380ms：过按住闸门，滴提起来
        } else if (i <= 78) {
          await gesture.moveBy(const Offset(2.5, 0)); // 拖过去
        } else if (i == 79) {
          await gesture.up();
          released = true;
        }
      },
    );
  });

  // ④ 开关 · 液态 · **按住拉长**。
  //
  //    用户 2026-10-01：「按住的时候不是要放大吗？那就要做成往纵向放大，
  //    参考 iOS 26 他们的开关液态玻璃那种形状变化」。
  testWidgets('开关 · 液态 · 按住 · light', (WidgetTester tester) async {
    useLiquidGlassTier();
    late TestGesture gesture;
    bool released = false;
    await renderFrames(
      tester,
      prefix: 'switch_liquid_',
      home: const _SwitchGifHost(),
      overrides: const <Override>[],
      count: 80,
      step: const Duration(milliseconds: 16),
      onFrame: (WidgetTester t, int i) async {
        if (i == 0) {
          final Rect box = t.getRect(find.byType(GlassSwitch).last);
          gesture = await t.startGesture(box.center);
          addTearDown(() {
            if (!released) return gesture.up();
            return Future<void>.value();
          });
          await t.pump(const Duration(milliseconds: 16));
        } else if (i == 70) {
          await gesture.up();
          released = true;
        }
      },
    );
  });

  // ④b 开关 · 液态 · **按住 → 拖动 → 松手**（「头大尾轻」的完整过程）。
  //
  //    与 ④ 是故意的配对：按住不动时形变恒为 0，光看 ④ 根本不知道形状会不会变 ——
  //    而 2026-10-01 这一轮争的正是「拖动时到底有没有头大尾轻」。
  //
  //    ⚠️ **拖动距离必须先走掉 `kTouchSlop`（18px）**：识别器赢下竞技场之前那 18px
  //    是空走的，而这条轨道一共只有 56 宽、钮只能走 25px。本轮第一版每帧只走 3px、
  //    六帧才 18px，识别器压根没收下这次拖动，两帧逐字节相同。
  //    出帧必须 16ms（弹簧每帧积分封顶在 `lensMaxStep`），合成用 `--fps 62`。
  for (final ({String suffix, Brightness brightness}) v in _modes) {
    testWidgets('开关 · 液态 · 按住拖到另一端 · ${v.suffix}',
        (WidgetTester tester) async {
      useLiquidGlassTier();
      late TestGesture gesture;
      bool released = false;
      await renderFrames(
        tester,
        prefix: 'switch_drag_${v.suffix}_',
        home: const _SwitchGifHost(),
        overrides: const <Override>[],
        brightness: v.brightness,
        count: 100,
        step: const Duration(milliseconds: 16),
        onFrame: (WidgetTester t, int i) async {
          if (i == 0) {
            final Rect box = t.getRect(find.byType(GlassSwitch).last);
            gesture =
                await t.startGesture(Offset(box.right - 8, box.center.dy));
            addTearDown(() {
              if (!released) return gesture.up();
              return Future<void>.value();
            });
            await t.pump(const Duration(milliseconds: 16));
          } else if (i <= 24) {
            // 按住 ~380ms：过按住闸门，钮纵向提起来
          } else if (i == 25) {
            await gesture.moveBy(const Offset(-18, 0)); // 走掉 kTouchSlop
          } else if (i <= 37) {
            await gesture.moveBy(const Offset(-2, 0)); // 125px/s，拖满那一格
          } else if (i == 62) {
            await gesture.up();
            released = true;
          }
        },
      );
    });
  }

  // ⑤ 待办打勾 · 标准档 / 液态档。
  //
  //    用户 2026-10-01：「我看别的设计语言都是用打勾的样式……弄完之后打勾，给一个
  //    删除线表达」。这一条拍的是**勾本身怎么长出来**（描出来 + 底色晕开），
  //    以及液态档下按住时那枚滴凸出来。
  //
  //    两档各出一条：`GlassCheck` 读的是模块级档位标志，一条片子只能是一个档位。
  for (final bool liquid in <bool>[false, true]) {
    testWidgets('待办打勾 · ${liquid ? '液态档' : '标准档'}',
        (WidgetTester tester) async {
      // 档位是**模块级标志**，会在用例之间残留 —— 上一条 `switch_liquid_` 刚把它
      // 点亮，不给标准档显式拨回去的话，这一条拍出来的其实是液态档（两条片子会
      // **逐字节相同**）。
      if (liquid) {
        useLiquidGlassTier();
      } else {
        useStandardGlassTier();
      }
      await renderFrames(
        tester,
        prefix: 'check_${liquid ? 'liquid' : 'std'}_',
        home: const _CheckGifHost(),
        overrides: const <Override>[],
        count: 70,
        // **16ms 一帧**：勾与升程都走弹簧，`LiquidLensSpring.step` 把每帧积分
        // 封顶在 `lensMaxStep`（16ms）—— 喂更长的帧整段动画会变慢。
        step: const Duration(milliseconds: 16),
        onFrame: (WidgetTester t, int i) async {
          if (i == 6) {
            await t.tap(find.byType(GlassCheck).first); // 勾上
          } else if (i == 44) {
            await t.tap(find.byType(GlassCheck).first); // 再点一下取消
          }
        },
      );
    });
  }

  // ⑥ 弹窗的**凝聚**入场 / 消散退场。
  //
  //    起点小一圈、糊一层，过程中一起收敛到清晰 —— 玻璃该有的样子是「从模糊里
  //    凝出来」，而不是一张不透明卡片被点亮。驱动用的是路由自己的动画，所以退场
  //    不用另写一份。
  //
  //    取「开始使用」那个弹窗：内容够长（九条带圆点的短句），凝聚过程在白底上
  //    也看得出来；而且它是纯文案、不用库。
  for (final v in _modes) {
    testWidgets('弹窗 · 凝聚入场 · ${v.suffix}', (WidgetTester tester) async {
      final GlobalKey host = GlobalKey();
      await renderFrames(
        tester,
        prefix: 'dialog_condense_${v.suffix}_',
        home: Scaffold(key: host, body: const SizedBox.expand()),
        overrides: const <Override>[],
        brightness: v.brightness,
        count: 22,
        step: const Duration(milliseconds: 16),
        onFrame: (WidgetTester t, int i) async {
          if (i == 0) showGettingStartedDialog(host.currentContext!);
        },
      );
    });
  }

  // ⑦ 响铃页那枚「上滑关闭」的滴（v0.10.13 把它从手搓的白圆钮换成真的玻璃滴）。
  //
  //    拍「按住提起 → 跟着手指拉长 → 没到阈值弹回去」一整段。**故意不拖到 0.7**
  //    （阈值）：到了就 `_finish()` 把整页 pop 掉，GIF 结尾会是一片黑。
  for (final v in _modes) {
    testWidgets('响铃 · 上滑关闭的玻璃滴 · ${v.suffix}', (WidgetTester tester) async {
      // 这枚药丸挂在了液态玻璃开关后面（两条档位两棵树），所以必须拨到液态档 ——
      // 顺带这条也钉住「液态档真的画了东西」：标准档那棵树上没有 `LiquidLens`，
      // 下面 `find.byType(LiquidLens)` 会当场抛。
      useLiquidGlassTier();
      addTearDown(useStandardGlassTier);
      late TestGesture g;
      bool released = false;
      await renderFrames(
        tester,
        prefix: 'ring_dismiss_${v.suffix}_',
        home: const AlarmRingingScreen(label: '早班'),
        overrides: const <Override>[],
        brightness: v.brightness,
        count: 100,
        step: const Duration(milliseconds: 16),
        onFrame: (WidgetTester t, int i) async {
          if (i == 0) {
            // 位置从树上量，别按算式猜 —— 轨道底边离屏幕底多少是布局说了算的。
            final Offset c = t.getRect(find.byType(LiquidLens)).center;
            g = await t.startGesture(c);
            addTearDown(() {
              if (released) return Future<void>.value();
              return g.up();
            });
          } else if (i <= 10) {
            // 按住 ~160ms。**别指望这期间会「提起」** —— 竖向拖动识别器要等手指
            // 走掉 `kTouchSlop`（18px）才算开始，`onVerticalDragStart` 根本还没跑。
          } else if (i <= 48) {
            // 一路往上；⚠️ 前 18px 是空走的，要算进去，否则拖不到六成就松手、
            // 看不出「跟着手指拉长」。
            await g.moveBy(const Offset(0, -3.6));
          } else if (i == 49) {
            await g.up(); // 没到 0.7 的阈值 → 弹回去
            released = true;
          }
        },
      );
    });
  }

  // ⑧ 日历那枚选中块**飞回去**（v0.10.17）。用户 2026-10-01 的原话：「点击当月的
  //    其他日期之后，再点『今天』，返回的动画也应该像底部导航栏点击时那样，加上
  //    该有的光晕，以及『头大尾轻』之类的特效。现在看起来还是以前那种效果。」
  //
  //    时间轴：先点到远处那一格（它自己也飞一下）→ 稳住 → 点「今天」飞回来
  //    （约 14 帧）→ 落定之后彩边还要**渐灭**约 400ms。前后都留着，才看得出
  //    「动的时候亮、停下来才收」。
  for (final v in _modes) {
    testWidgets('日历 · 点「今天」飞回去 · ${v.suffix}', (WidgetTester tester) async {
      final db = await freshDb();
      final int today = DateTime.now().day;
      final int other = today >= 15 ? today - 10 : today + 10; // 一定在 1..25 里
      await renderFrames(
        tester,
        prefix: 'calendar_flight_${v.suffix}_',
        home: const CalendarScreen(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        extraPrefs: _liquidPrefs,
        brightness: v.brightness,
        count: 46,
        // ⚠️ **有弹簧的动图必须 16ms 一帧**（`LiquidLensSpring.step` 把每帧积分
        // 封顶在 16ms）：喂 55ms 一帧整段动画会慢 3.4 倍。
        step: const Duration(milliseconds: 16),
        onFrame: (WidgetTester t, int i) async {
          if (i == 0) {
            await t.tap(find.byKey(ValueKey('day-card-$other')));
          } else if (i == 18) {
            await t.tap(find.byIcon(Icons.today_outlined));
          }
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

/// 一屏只放三段分段器（液态档下拍拖动）。
class _SegmentGifHost extends StatelessWidget {
  const _SegmentGifHost();

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

/// 三枚待办的勾（拍「勾出来」那一刻；最后一枚按住看液态档那枚滴凸出去）。
class _CheckGifHost extends StatelessWidget {
  const _CheckGifHost();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              GlassCheck(value: false, onChanged: _ignore),
              SizedBox(height: AppTokens.space2xl),
              GlassCheck(value: true, onChanged: _ignore),
              SizedBox(height: AppTokens.space2xl),
              GlassCheck(value: false, onChanged: _ignore),
            ],
          ),
        ),
      );

  static void _ignore(bool _) {}
}

/// 三枚开关（液态档下拍「按住拉长」）。
class _SwitchGifHost extends StatelessWidget {
  const _SwitchGifHost();

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
