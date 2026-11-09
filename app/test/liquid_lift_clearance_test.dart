// app/test/liquid_lift_clearance_test.dart
//
// 液态滑块的**升程下限**：按住拖动、被抽出来的时候，每侧至少要越过容器边 **4dp**。
//
// 为什么是这条规则，而不是「占自身高度的百分比」：
// 用户 2026-11-05 把开关高度定在 42 时说得很清楚 —— 「这是液态玻璃的一个统一理念：
// 底栏的滑块也是按住拖动时放大、超出底栏」。统一的**是那件事**（越出容器），
// 不是那个比值。按比值看两个控件差得很远（底栏 4/52 = 7.7%，开关 6/24 = 25%），
// 差在**内缩**上：`protrude` 是从内缩后的基准量的，底栏内缩 6、开关只内缩 3。
//
// 拿底栏的比例去收开关会得到 3dp —— 3x 屏上 9 个物理像素，比底栏那 12 还弱，
// 于是**最小的控件拿到最弱的信号**，与「统一」正好相反。所以下限取绝对值 4dp：
// 底栏现在是 4、开关是 6，两条都过；谁把开关收到 3 就该红。
//
// 断言只有一条方向：`>= 4`。**往上调大不算违规**（当年给的是「至少」，不是「恰好」），
// 所以这里不许写 `closeTo(4)` —— 那样把底栏调到 12 反而会红，规则就成了「别动」。
// 「今天量到的是 4 / 6」只写在注释里，当记录，不当闸门。
//
// ## 量的是**轮廓**，不是配置
//
// `clearanceOf` 读 `LiquidLensShape` 的 `(height − capsuleH) / 2` —— 也就是真画出去
// 的那条轮廓比胶囊高出多少。不去读 `metrics.protrude − pad`：那是**同一份配置的
// 两次读数**，谁把 `liquid_lens.dart` 里 `2 * m.protrude * lift` 的系数写成
// `1 *`（`liquid_lens.dart:222-227` 记着上一回正是系数写错、整枚透镜沉回胶囊里），
// 配置读数照样报 4，而屏幕上根本没有浮起来。
//
// ## 前提：满升程、无形变
//
// 「越出量 = protrude − pad」只在 `lift = 1` 且 `stretch = 0`（没在滑动）时成立。
// 满压扁档（`lensSquash` 吃满）底栏只剩 **1.92dp**（0.92 × 52 + 20 = 67.84 对 64），
// 那是「正在飞」的中间态，不是静止的升程 —— 别拿这条 4dp 规则去卡拖动中的某一帧。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';
import 'package:shiftassistantpro/core/widgets/liquid_track.dart';
import 'package:shiftassistantpro/features/home/glass_nav_bar.dart';

void main() {
  /// 规则本身：每侧越过容器边至少这么多逻辑 px。
  const double kMinClearance = 4;

  /// 弹簧的收敛噪声。升程弹簧停不到一丝不差：实测量到 3.9999991。
  /// 留 0.01dp（远小于 1 个物理像素 = 0.33dp）的余量，别让浮点尾数把规则判红 ——
  /// 真要收小到 3dp 时差的是整整 1dp，这点余量拦不住。
  const double kNoise = 0.01;

  /// 满升程时每侧越过容器边多少 —— **从轮廓量**（见文件头）。
  double clearanceOf(WidgetTester tester) {
    final LiquidLensShape shape =
        tester.widget<LiquidLens>(find.byType(LiquidLens).first).shape;
    return (shape.height - shape.capsuleH) / 2;
  }

  /// 按住不放，把升程推到满（40 帧 = 640ms，过按住闸门并等弹簧停住）。
  ///
  /// 走控制器自己的 `press(…, moveToSlot: false)`：只进按住态、不挪位置，
  /// 于是没有位移、没有速度、没有形变 —— 量到的就是纯粹的升程。
  Future<void> holdToFullLift(WidgetTester tester) async {
    final LiquidTrack track =
        tester.widget<LiquidTrack>(find.byType(LiquidTrack).first);
    track.controller.press(track.pad, moveToSlot: false);
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pumpNavBar(WidgetTester tester) async {
    liquidGlassEnabled.value = true;
    recomputeGlassTiers();
    final PageController controller = PageController();
    addTearDown(() {
      controller.dispose();
      liquidGlassEnabled.value = false;
      recomputeGlassTiers();
    });
    expect(liquidGlassActive.value, isTrue, reason: '前提：液态档没生效 —— 树上没有滑块');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: GlassNavBar(
            controller: controller,
            items: const <(IconData, String)>[
              (Icons.calendar_month_outlined, '日历'),
              (Icons.alarm_outlined, '闹钟'),
              (Icons.check_circle_outline, '待办'),
              (Icons.person_outline, '我的'),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('底栏胶囊（64 高那一档）：每侧越过 4dp', (tester) async {
    await pumpNavBar(tester);
    final LiquidLensShape rest = tester
        .widget<LiquidLens>(find.byType(LiquidLens).first)
        .shape;
    expect(rest.capsuleH, closeTo(64, 0.01), reason: '前提：不是默认那一档');

    await holdToFullLift(tester);
    final double c = clearanceOf(tester);
    expect(c, greaterThanOrEqualTo(kMinClearance - kNoise),
        reason: '底栏滑块满升程只越过 $c dp —— 低于 4dp 就看不见「浮起来」了'
            '（今天量到的是 4：72 对 64）');
  });

  testWidgets('底栏胶囊（矮屏 52 高那一档）：照样越过 4dp', (tester) async {
    // 矮屏（可用高 < 480）只矮了胶囊、没矮升程：`glass_nav_bar.dart:216` 换的是
    // `capsuleH`，`:438` 的 `protrude` 还是同一个 `navLensProtrude`。
    // 这条要渲真的矮屏 —— 只算一遍的话，「底栏在所有档位都过线」就只是推理。
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpNavBar(tester);
    final LiquidLensShape rest = tester
        .widget<LiquidLens>(find.byType(LiquidLens).first)
        .shape;
    expect(rest.capsuleH, closeTo(52, 0.01), reason: '前提：没进矮屏那一档');

    await holdToFullLift(tester);
    final double c = clearanceOf(tester);
    expect(c, greaterThanOrEqualTo(kMinClearance - kNoise),
        reason: '矮屏底栏满升程只越过 $c dp —— 换胶囊高度时忘了保住升程');
  });

  testWidgets('开关钮：每侧越过 6dp', (tester) async {
    liquidGlassActive.value = true;
    addTearDown(() => liquidGlassActive.value = false);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Center(
          child: GlassSwitch(value: false, onChanged: (_) {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final LiquidLensShape rest = tester
        .widget<LiquidLens>(find.byType(LiquidLens).first)
        .shape;
    expect(rest.capsuleH, closeTo(30, 0.01), reason: '前提：开关槽不是 30 高');

    await holdToFullLift(tester);
    final double c = clearanceOf(tester);
    expect(c, greaterThanOrEqualTo(kMinClearance - kNoise),
        reason: '开关满升程每侧只越过 $c dp —— 30 高的轨道上这点量等于没提起来'
            '（用户 2026-11-05 要的正是「按住拖动时超出容器」；今天量到的是 6：42 对 30）');
  });
}
