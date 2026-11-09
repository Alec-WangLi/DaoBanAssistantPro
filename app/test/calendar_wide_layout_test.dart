// app/test/calendar_wide_layout_test.dart
//
// 宽屏 / 平板 / 车机版式、性能护栏、格子字号上限。
//
// 由 app/test/calendar_screen_test.dart 按被测对象切分而来：断言与用例名一字未改，
// 夹具与 helper 在 support/calendar_test_support.dart。
import 'dart:math' as math;

import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/layout.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/core/clock.dart';
import 'support/fixed_clock.dart';
import 'support/calendar_test_support.dart';

void main() {
  useFixedNow();
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });


  // ── 这一轮的性能护栏 ─────────────────────────────────────────────────
  //
  // 日历页那两张 `GlassTile`（完整信息卡 / 小窗卡）背后是那层极淡的光晕。
  // 真机上把卡片的 `BackdropFilter` 摘掉：日历 raster p50 **6.22ms → 3.59ms**、
  // p90 **10.36 → 5.92**。观感是量过的 —— 相位对齐之后全屏 ≥4 的像素 **0.43%**、
  // ≥8 的 **0.01%**，放大 12 倍才看得见（差异只有文字描边的抗锯齿、
  // 与光晕透过卡片的极淡纹理）。所以这不是取舍，是白捡。
  //
  // 夹具是**标准档**（`liquidGlass` 默认关）—— 那几层模糊属于液态档的浮层，
  // 不在这个断言的范围内。
  testWidgets('日历页不再有卡片那一层 BackdropFilter', (tester) async {
    await pumpCalendar(tester, 'four_crew_three_shift');
    final int layers =
        tester.widgetList<BackdropFilter>(find.byType(BackdropFilter)).length;
    // 改之前这里是 **1**（完整信息卡那一张）。小窗档那张用的是另一个夹具尺寸。
    expect(layers, 0, reason: '实测 $layers 层');
    await disposeCalendar(tester);
  });


  // ── 宽屏（平板 / 车机）的版式 ────────────────────────────────────────

  testWidgets('手机横屏（900×420）上日历仍然画格子', (tester) async {
    // ⚠️ **回归用例**：分栏判据换成「宽横屏」之后，这一档会掉进竖屏那一支，
    // 而竖屏那一支里有 `if (!layout.isShort) gridArea` —— 不加第二支的话
    // 网格会被整块删掉：界面上只是少一块，**不报任何错**。
    await pumpCalendar(tester, 'six_crew_three_shift',
        width: 900, height: 420);
    expect(find.byKey(const ValueKey('day-card-1')), findsOneWidget);
    // ⚠️ 末格按**当月天数**取，不写死 31：2 月只有 28 天，写死的那版在 2 月必红。
    final int lastDay = DateTime(appNow().year, appNow().month + 1, 0).day;
    expect(find.byKey(ValueKey('day-card-$lastDay')), findsOneWidget);
    await disposeCalendar(tester);
  });


  testWidgets('宽屏两支都让开底部胶囊：网格底边 ≤ 屏高 − 96', (tester) async {
    // 96 = `kNavCapsuleInset`。竖屏不用管（那一支把让位写在信息卡自己的内边距里）。
    for (final s in const [(w: 1280.0, h: 800.0), (w: 900.0, h: 420.0)]) {
      await pumpCalendar(tester, 'six_crew_three_shift',
          width: s.w, height: s.h);
      final grid = tester.getRect(find.byKey(const Key('calendar-grid')));
      expect(grid.bottom, lessThanOrEqualTo(s.h - kNavCapsuleInset + 0.5),
          reason: '${s.w}×${s.h}：网格底边 ${grid.bottom} 越过了胶囊让位线');
      await disposeCalendar(tester);
    }
  });


  testWidgets('宽横屏：最后一行格子完整落在底部胶囊之上', (tester) async {
    // ⚠️ 断言写成「**最下面那一格**的底边」而不是「第 6 行」：月份的行数随月份变
    // （2026-10 是 5 行），钉死行号会写成一句只在某几个月成立的用例。
    await pumpCalendar(tester, 'six_crew_three_shift',
        width: 1280, height: 800);
    final bottoms = <double>[];
    for (var d = 1; d <= 31; d++) {
      final f = find.byKey(ValueKey('day-card-$d'));
      if (f.evaluate().isEmpty) continue;
      bottoms.add(tester.getRect(f).bottom);
    }
    expect(bottoms, isNotEmpty);
    expect(bottoms.reduce(math.max),
        lessThanOrEqualTo(800 - kNavCapsuleInset + 0.5),
        reason: '最下面那一格的底边被胶囊压住了');
    await disposeCalendar(tester);
  });


  testWidgets('竖着的平板（800×1280）走竖屏版式：不分栏、也不画右栏', (tester) async {
    // ⚠️ **独立审查抓出来的一条**：第二支的判据原来只写了 `isWide`，
    // 于是「宽但竖着」的平板也落进那一支、被拆成左右两栏 —— 而 spec §4.1 说的
    // 恰恰是要修掉这处怪相（七列格子要的是宽度，不是分栏）。
    await pumpCalendar(tester, 'six_crew_three_shift',
        width: 800, height: 1280);
    expect(find.byKey(const Key('info-rail')), findsNothing,
        reason: '竖屏平板被拆成了左右两栏 —— 该走竖屏那套');
    // 网格仍然在，而且铺满整个宽度。
    final grid = tester.getRect(find.byKey(const Key('calendar-grid')));
    expect(grid.width, closeTo(800, 1));
    expect(find.byKey(const ValueKey('day-card-13')), findsOneWidget);
    await disposeCalendar(tester);
  });


  testWidgets('宽横屏：顶栏收在左栏里、年月胶囊不再被拉伸', (tester) async {
    await pumpCalendar(tester, 'six_crew_three_shift',
        width: 1280, height: 800);

    // ① 顶栏整块在左栏里 —— 它的右缘不超过信息卡的左缘。
    final header = tester.getRect(find.byKey(const Key('header-single-row')));
    final card = tester.getRect(find.byKey(const Key('info-card-panel')));
    expect(header.right, lessThanOrEqualTo(card.left),
        reason: '顶栏右缘 ${header.right} 越到了信息卡（${card.left}）那边');

    // ② 不再被拉伸：整行收缩到内容宽度。
    //    ⚠️ **判据取「顶栏自己的宽度」而不是「内层 Row 比外层 Padding 窄」**：
    //    收缩之后连外层那个 `Padding` 也一起收缩了（它外面是 `Column`，给的是松约束），
    //    两者只差内边距 24 —— 那个判据写成 `width - 100` 会永远为假。
    //    改之前顶栏是 928（整条左栏），收缩之后约 386。
    expect(header.width, lessThan(500),
        reason: '顶栏宽 ${header.width} —— 还在被撑满整条左栏');
    // ③ **靠左**：收缩之后 `Column` 默认的 `crossAxisAlignment: center` 会把它
    //    居中，而设计要的是贴着左缘。这一条就是钉它的。
    expect(header.left, lessThanOrEqualTo(20),
        reason: '顶栏左缘 ${header.left} —— 它被居中了，没靠左');
    await disposeCalendar(tester);
  });


  testWidgets('宽横屏：今日卡贴在右下角，且右栏宽度跟着屏宽走', (tester) async {
    await pumpCalendar(tester, 'six_crew_three_shift',
        width: 1280, height: 800);

    final rail = tester.getRect(find.byKey(const Key('info-rail')));
    final card = tester.getRect(find.byKey(const Key('info-card-panel')));

    // ⓪ **先钉住这一栏真的占满整列高**。不钉的话 ① 是句空话：
    //    这一栏要是收缩到内容高度，`rail.bottom` 与 `card.bottom` 本来就只差内边距，
    //    「贴底」与否都恒真（第一版就是这么写出来的，改之前它照样绿）。
    //    1280×800 下右栏高 = 800 − 胶囊让位 96 = 704。
    expect(rail.height, greaterThan(600),
        reason: '右栏只有 ${rail.height} 高 —— 它收缩到内容高度了，① 就成了空话');
    // ① **贴底**：卡片下方只剩这一栏自己的 16 内边距。从前是顶对齐，
    //    卡片底下会空出几百 dp（用户报的「一小块缩在右上角」）。
    expect(rail.bottom - card.bottom, lessThanOrEqualTo(20),
        reason: '卡片底边离右栏底部还有 ${rail.bottom - card.bottom} —— 它还没贴底');
    // ② 卡片水平方向在这一栏里。
    expect(card.left, greaterThanOrEqualTo(rail.left - 0.5));
    expect(card.right, lessThanOrEqualTo(rail.right + 0.5));
    // ③ 右栏宽 = (1280 × 0.27).clamp(280, 340) = 340。
    expect(rail.width, closeTo(340, 0.5));

    await disposeCalendar(tester);

    // ④ 1024 那一档：0.27 × 1024 = 276.5 → 夹到下限 280。
    await pumpCalendar(tester, 'six_crew_three_shift',
        width: 1024, height: 600);
    expect(tester.getSize(find.byKey(const Key('info-rail'))).width,
        closeTo(280, 0.5));
    await disposeCalendar(tester);
  });


  testWidgets('宽横屏最紧的一档：今日卡仍然装得下，而且贴底', (tester) async {
    // ⚠️ **这条用例原来是句空话**（独立审查指出来的）。原文写「右栏装不下时自己滚」，
    // 跑的是 1024×600 —— 但那一档卡片本来**装得下**，断言里的
    // `rail.bottom − card.bottom ≤ 20` 恒真，它测的其实是「贴底」，与「装不下」无关。
    //
    // 而且**「装不下」在宽横屏这一支今天根本到不了**：宽横屏要求高 ≥ 480 ⇒
    // 右栏高 ≥ 480 − 96 = 384，而今日卡在我们最大的字号档下也只有三百六十出头
    // （实测 362.3 —— 余量只有 22dp）。所以那句承诺无从验证；与其留一条读起来像
    // 覆盖了的假用例，不如把**真实的最紧几何**钉住：卡片必须仍然矮于右栏。
    // 卡片再长高 6% 这条就红 —— 那时右栏会开始滚，是「要么调阈值、要么承认走滚动」
    // 的岔路口。
    //
    // ⚠️ **贴底那半句在**这里**鉴别力很弱**（362 装在 384 里，顶对齐与贴底只差
    // 十几 dp）—— **强的那条在 1280×800 那条用例里**（那里差 412dp）。
    // 右栏外面那层 `SingleChildScrollView` 是结构性兜底：溢出的表现是「这一栏自己滚」
    // 而不是黄黑条纹。
    await pumpCalendar(tester, 'six_crew_three_shift',
        width: 1024, height: 480);
    final rail = tester.getRect(find.byKey(const Key('info-rail')));
    final card = tester.getRect(find.byKey(const Key('info-card-panel')));
    expect(card.height, lessThan(rail.height),
        reason: '最紧的宽横屏档下卡片 ${card.height} 高过了右栏 ${rail.height} —— '
            '这一档的「装得下」不再成立，要么调阈值、要么承认走滚动兜底');
    expect(rail.bottom - card.bottom, lessThanOrEqualTo(20),
        reason: '装得下的时候，卡片就该贴着这一栏的底边');
    await disposeCalendar(tester);
  });


  // ── 格子字号的上限按档位取（用户报的第 5 条） ────────────────────────

  test('格子字号上限按档位取：宽屏 1.7、其余 1.25', () {
    AppLayout at(double w, double h) => AppLayout(
        isNarrow: w < 360,
        isShort: h < 480,
        isWide: w >= 720,
        isWideLandscape: w >= 720 && h >= 480 && w > h,
        availableWidth: w,
        availableHeight: h);
    expect(cellMaxScale(at(420, 900)), 1.25);
    expect(cellMaxScale(at(200, 400)), 1.25);
    expect(cellMaxScale(at(1280, 800)), 1.7);
    expect(cellMaxScale(at(1920, 720)), 1.7);
    // ⚠️ 判据是 `isWide`（不是 `isWideLandscape`）：竖着的平板也吃到宽屏上限。
    expect(cellMaxScale(at(800, 1280)), 1.7);
    // 宽且矮那一档格子只有 41dp 高，上限根本不生效 —— 给它宽屏值只是少一个分支。
    expect(cellMaxScale(at(900, 420)), 1.7);
  });


  testWidgets('宽横屏下格子里的字真的更大', (tester) async {
    await pumpCalendar(tester, 'six_crew_three_shift',
        width: 1280, height: 800);
    final wide = tester.getSize(find.descendant(
        of: find.byKey(const ValueKey('day-card-13')),
        matching: find.text('13')));
    await disposeCalendar(tester);

    await pumpCalendar(tester, 'six_crew_three_shift',
        width: 420, height: 900);
    final phone = tester.getSize(find.descendant(
        of: find.byKey(const ValueKey('day-card-13')),
        matching: find.text('13')));

    // 字号是按 `s` 乘上去的，而格子里的 `FittedBox` 给子件的是**无界约束**
    // （缩放只改变绘制），所以这里量到的就是「按 s 排出来的自然尺寸」。
    expect(wide.height / phone.height, greaterThan(1.15),
        reason: '宽屏 ${wide.height} vs 手机 ${phone.height} —— 字没跟着档位长');
    await disposeCalendar(tester);
  });
}
