// app/test/calendar_liquid_test.dart
//
// 液态档：滑块那枚块、多选水带、光晕在交互时暂停。
//
// 由 app/test/calendar_screen_test.dart 按被测对象切分而来：断言与用例名一字未改，
// 夹具与 helper 在 support/calendar_test_support.dart。

import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/features/calendar/calendar_lens.dart';
import 'package:shiftassistantpro/features/calendar/calendar_range_band.dart';
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


  // ── 液态档那枚块（v0.10.15）─────────────────────────────────────────────
  //
  // 判据只出现在 `calendar_screen.dart` 那两处岔口（`_glassBlock` 与 `AnimatedScale`）。
  // **标准档必须一点没变** —— 那是这一轮唯一的硬验收（出图逐张比在 Task 8 兜着），
  // 这里先用几何钉住两条最容易破的：树上有没有那两枚东西、按住那个倍率还是不是 1.22。
  group('液态档那枚块', () {
    testWidgets('标准档与液态档是两棵树', (tester) async {
      await pumpCalendar(tester, 'four_crew_three_shift');
      expect(find.byType(CalendarLens), findsNothing);
      expect(find.byType(LiquidLens), findsNothing);
      await disposeCalendar(tester);

      await pumpCalendar(tester, 'four_crew_three_shift', liquid: true);
      expect(find.byType(CalendarLens), findsOneWidget);
      expect(find.byType(LiquidLens), findsOneWidget);
      await disposeCalendar(tester);
    });

    testWidgets('液态档按住的倍率恒为 1.0（按住那个动作由四面鼓出承担）',
        (tester) async {
      await pumpCalendar(tester, 'four_crew_three_shift', liquid: true);
      final TestGesture g = await tester.startGesture(tester.getCenter(
          find.byKey(ValueKey('day-card-${appNow().day}'))));
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(blockScale(tester), 1.0,
          reason: '液态档还留着 1.22 —— 那会与「四面鼓出」叠成两层');
      await g.up();
      await tester.pumpAndSettle();
      await disposeCalendar(tester);
    });

    testWidgets('挤字只变换绘制、不改布局', (tester) async {
      await pumpCalendar(tester, 'four_crew_three_shift', liquid: true);

      // ⚠️ **锚点不取「今天」**（与上面拖选那几条同一个理由，见 `rangeFirstDay`）：
      // 这一条要的是「透镜卡在两格之间、**右邻那格**被挤」，而「今天」在月历里的列
      // 位置逐日不同 —— 锚在它身上只有每月头两天才成立。2026-10-10 实测：它红了，
      // 而且与任何改动无关（干净树上一样红）。8 日永远落在第 1 行，右邻是 9 日；
      // 只有月初偏移为 6（1 号是周日）那种月份 8 / 9 不同行，那种月份改取 9 / 10。
      final DateTime now = appNow();
      final int leading = DateTime(now.year, now.month, 1).weekday - 1;
      final int anchor = leading == 6 ? 9 : 8;
      final Finder anchorCard = find.byKey(ValueKey('day-card-$anchor'));
      final Finder neighbour = find.byKey(ValueKey('day-card-${anchor + 1}'));

      // 拖动是从**选中那格**起算的（`onPanStart` 读 `_selectedRect`），所以先选中锚点。
      await tester.tap(anchorCard);
      await tester.pumpAndSettle();

      final Size before = tester.getSize(neighbour);
      // 按住锚点那格，往右拖**半格**（48px = 半格 28 + 被吃掉的 18px slop）——
      // 透镜正好卡在两格之间，右边那格的内容才会被它的边缘挤到。
      final TestGesture g = await tester.startGesture(tester.getCenter(anchorCard));
      for (int i = 0; i < 8; i++) {
        await g.moveBy(const Offset(6, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.descendant(of: neighbour, matching: find.byType(Transform)),
          findsWidgets,
          reason: '那格的内容没被挤 —— 要么透镜没走到两格之间，要么挤字没接上');
      expect(tester.getSize(neighbour), before,
          reason: '挤字只该变换绘制，不该改布局（改了就会把字挤出格子）');
      await g.up();
      await tester.pumpAndSettle();
      await disposeCalendar(tester);
    });

    testWidgets('窄屏（260×900）：格子只有 33 宽，形状退回胶囊那支、不崩',
        (tester) async {
      // ⚠️ 高度给 900 而不是 400：`AppLayout.isShort`（高 < 480）那一档**不画网格**、
      // 只有今日信息卡 —— 那样根本测不到这枚块。
      // ⚠️ 宽度取 260 而不是 200：**200 宽在标准档下自己就溢出 8px**（顶栏那行胶囊），
      // 是既有问题、与本轮无关（实测过：同一个尺寸、非液态档，同样三条溢出）。
      await pumpCalendar(tester, 'four_crew_three_shift',
          width: 260, height: 900, liquid: true);
      expect(tester.takeException(), isNull);
      expect(find.byType(CalendarLens), findsOneWidget);
      // 格宽 33.7 → 内盒 29.7 → cornerR(16) 比半宽 14.85 还大：形状退回胶囊那支
      // （端头半径 = 半宽，而不是那个 cornerR）。
      final LiquidLensShape sh =
          tester.widget<LiquidLens>(find.byType(LiquidLens)).shape;
      expect(sh.leftRadius, lessThan(AppTokens.radiusM));
      expect(sh.leftRadius,
          closeTo(sh.toPath().getBounds().width / 2, 0.5));
      await disposeCalendar(tester);
    });

    testWidgets('拖到本月之外的空白格：不崩、块照旧跟着走', (tester) async {
      await pumpCalendar(tester, 'four_crew_three_shift', liquid: true);
      final TestGesture g = await tester.startGesture(tester.getCenter(
          find.byKey(ValueKey('day-card-${appNow().day}'))));
      for (int i = 0; i < 20; i++) {
        await g.moveBy(const Offset(20, 0)); // 一路拖出行尾
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(CalendarLens), findsOneWidget);
      await g.up();
      await tester.pumpAndSettle();
      await disposeCalendar(tester);
    });

    // ── 滑行：点日期 / 点「今天」那一下，那枚块是**飞过去的** ──────────────
    //
    // 用户 2026-10-01：「点击当月的其他日期之后，再点『今天』，返回的动画也应该像
    // 底部导航栏点击时那样，加上该有的光晕，以及『头大尾轻』之类的特效。现在看起来
    // 还是以前那种效果。」
    //
    // 根因是三处同源：位置由 `AnimatedPositioned` 隐式走 → 拿不到中间位置 →
    // ① 速度恒为 0（形变与彩边都不发生）② 挤压场一直盯着**终点那一格**（块飞过的
    // 格子一点反应都没有）。现在位置由我们自己算，三件事从同一个数推出来。
    testWidgets('点「今天」：那枚块真的**滑行**过去，不是瞬移', (tester) async {
      await pumpCalendar(tester, 'four_crew_three_shift', liquid: true);
      final int today = appNow().day;
      final int other = today >= 15 ? today - 10 : today + 10; // 一定在 1..25 里
      final Finder block = find.byKey(const Key('calendar-selection-block'));
      final Finder todayBtn = find.byIcon(Icons.today_outlined);

      // 先飞一次到「今天」，把**终点**量出来（那枚块的左上角）。
      await tester.tap(todayBtn);
      await tester.pumpAndSettle();
      final Offset end = tester.getTopLeft(block);

      // 再点到远处那一格，然后点「今天」飞回来。
      await tester.tap(find.byKey(ValueKey('day-card-$other')));
      await tester.pumpAndSettle();
      final Offset start = tester.getTopLeft(block);
      expect(start, isNot(end));

      await tester.tap(todayBtn);
      await tester.pump(); // 起跑
      // 逐帧推（一帧 16ms）：滑行按帧走，一次 `pump(80ms)` 只会让 ticker 跑一帧。
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16)); // 中途
      }
      final Offset mid = tester.getTopLeft(block);
      final Offset d = end - start;
      final Offset m = mid - start;
      final double along = (m.dx * d.dx + m.dy * d.dy) / d.distanceSquared;
      expect(along, greaterThan(0.05),
          reason: '那一帧还停在起点 —— 位置是瞬移过去、中间没有帧（$mid）');
      expect(along, lessThan(0.95),
          reason: '那一帧已经到终点了 —— 同上（$mid）');

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(block), end);
      await disposeCalendar(tester);
    });

    testWidgets('滑行中：挤压场跟着那枚块走，不是一直盯着终点', (tester) async {
      await pumpCalendar(tester, 'four_crew_three_shift', liquid: true);
      final int today = appNow().day;
      final int other = today >= 15 ? today - 10 : today + 10;
      final Finder todayBtn = find.byIcon(Icons.today_outlined);

      /// 全月有多少格的内容被透镜挤了（`Transform` 只在液态档、且只在非恒等时套）。
      int warpedCells() {
        var n = 0;
        final int days = DateTime(appNow().year, appNow().month + 1, 0)
            .day;
        for (var d = 1; d <= days; d++) {
          if (tester.any(find.descendant(
              of: find.byKey(ValueKey('day-card-$d')),
              matching: find.byType(Transform)))) {
            n++;
          }
        }
        return n;
      }

      await tester.tap(todayBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('day-card-$other')));
      await tester.pumpAndSettle();
      expect(warpedCells(), 0, reason: '静止时不该有被挤的格子（v0.10.15 那条）');

      await tester.tap(todayBtn);
      await tester.pump();
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // 块正卡在格子之间，它扫过的那几格的内容该被挤。
      expect(warpedCells(), greaterThan(0),
          reason: '滑行中一格都没被挤 —— 挤压场还盯着终点那一格，没跟着那枚块走');

      await tester.pumpAndSettle();
      expect(warpedCells(), 0, reason: '落定之后该收干净');
      await disposeCalendar(tester);
    });

    testWidgets('滑行中：彩边亮起来（块在动），落定之后熄灭', (tester) async {
      await pumpCalendar(tester, 'four_crew_three_shift', liquid: true);
      final int today = appNow().day;
      final int other = today >= 15 ? today - 10 : today + 10;
      final Finder todayBtn = find.byIcon(Icons.today_outlined);
      double motion() =>
          tester.widget<LiquidLens>(find.byType(LiquidLens)).shape.motion;

      await tester.tap(find.byKey(ValueKey('day-card-$other')));
      await tester.pumpAndSettle();
      await tester.tap(todayBtn);
      await tester.pump();
      // ⚠️ **逐帧推**（一帧 16ms）：滑行是按帧走的，一次性 `pump(100ms)` 只会让
      // ticker 跑一帧（`maxStep` 那条封顶），量到的是「刚起步」。
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(motion(), greaterThan(0.5),
          reason: '滑行中彩边没亮 —— 速度还是恒为 0（那正是「以前那种效果」）');

      await tester.pumpAndSettle();
      expect(motion(), closeTo(0, 0.02));
      // 滑行结束之后**不许再推帧**（常驻动画会让整套 widget 测试在 pumpAndSettle
      // 上集体超时 —— 日历页 v0.9.8 吃过这个亏）。
      expect(tester.binding.hasScheduledFrame, isFalse);
      await disposeCalendar(tester);
    });

    testWidgets('两棵树：标准档仍是 AnimatedPositioned，液态档的位置由我们算',
        (tester) async {
      final Finder block = find.byKey(const Key('calendar-selection-block'));
      await pumpCalendar(tester, 'four_crew_three_shift');
      expect(find.ancestor(of: block, matching: find.byType(AnimatedPositioned)),
          findsOneWidget,
          reason: '标准档那棵树一个字都不许动');
      await disposeCalendar(tester);

      await pumpCalendar(tester, 'four_crew_three_shift', liquid: true);
      expect(find.ancestor(of: block, matching: find.byType(AnimatedPositioned)),
          findsNothing);
      expect(find.ancestor(of: block, matching: find.byType(Positioned)),
          findsWidgets);
      await disposeCalendar(tester);
    });
  });


  // ── 液态档那条水带（长按拖选）────────────────────────────────────────
  //
  // 今天那层是**逐格各画一块** 14% 圆角方，格子之间 4px 的缝谁也盖不住 —— 所以
  // 「连成一条」在今天的结构里做不到：带子只能是网格之上的一层（与那枚单格块同层位）。
  group('液态档那条水带', () {
    /// 那一格的内容有没有被透镜挤（`Transform` 只在液态档、且只在非恒等时套）。
    bool warped(WidgetTester tester, int day) => tester.any(find.descendant(
        of: find.byKey(ValueKey('day-card-$day')),
        matching: find.byType(Transform)));

    testWidgets('液态档：多选态不画逐格淡染，改用一枚带子', (tester) async {
      await pumpCalendar(tester, 'day_night_rest_rest', liquid: true);
      await longPressDragCell(tester, rangeFirstDay, 1, midDrag: () async {
        expect(find.byKey(const ValueKey('day-range-10')), findsNothing,
            reason: '液态档还在逐格画淡染 —— 那就不叫「连成一条」了');
        expect(find.byType(CalendarRangeBand), findsOneWidget);
      });
      await disposeCalendar(tester);
    });

    testWidgets('标准档：还是逐格淡染（对照组，一个字没改）', (tester) async {
      await pumpCalendar(tester, 'day_night_rest_rest');
      await longPressDragCell(tester, rangeFirstDay, 1, midDrag: () async {
        expect(find.byKey(const ValueKey('day-range-10')), findsOneWidget);
        expect(find.byType(CalendarRangeBand), findsNothing);
      });
      await disposeCalendar(tester);
    });

    testWidgets('只挤**流动那一端**：带子内部那些格不套 Transform', (tester) async {
      await pumpCalendar(tester, 'day_night_rest_rest', liquid: true);
      // 长按 8 日 → 往下拖一格（到 15 日）→ 再往右拖半格。
      //
      // ⚠️ 后半截是必需的：挤压场只够到一格的半径，末端**停在格正中**时连它自己
      // 那一格都不套 Transform（t≈0）。要它挤，末端得卡在**两格之间** ——
      // 既有的「挤字只变换绘制」那条也是这么拖的（半格）。
      // ⚠️ 起点与步长都从**这一帧的格子尺寸**来，不写死 8 日与 60/34 像素：
      // 8 日可能正好在最后一列（2026-02 的 8 日是周日），往右拖会出网格；
      // 格子高度也随「这个月几行」而变，写死的 60 在 6 行月里跨不过一行。
      final int startDay = dragStartDay(tester);
      final Size cell =
          tester.getSize(find.byKey(ValueKey('day-card-$startDay')));
      final Offset start =
          tester.getCenter(find.byKey(ValueKey('day-card-$startDay')));
      final TestGesture g = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600)); // 过长按判定
      await g.moveBy(Offset(0, cell.height)); // 下一行 → 末端 startDay + 7
      await tester.pump();
      // ⚠️ 要**跨过格界**才算挪一格：0.6 格宽（比半格多留一点余量 —— 半格差 0.3px
      // 的那次就是没跨过去，焦点仍停着，末端一动不动）。
      await g.moveBy(Offset(cell.width * 0.6, 0)); // 跨过格界 → 末端淌过去
      // ⚠️ 推**三帧**：ticker 的第一帧在下一帧才跑，一帧之后末端还停在原处 ——
      // 那时场心正好压在 15 日正中（`t≈0`，什么都不套），这条就测不到东西。
      for (int i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(warped(tester, startDay + 7) || warped(tester, startDay + 8), isTrue,
          reason: '流动那一端旁边那几格没被挤 —— 挤压场没跟着末端走');
      expect(warped(tester, startDay + 2), isFalse,
          reason: '带子内部（已经圈住的日子）也被挤了 —— spec §4.5：那里面不该动');
      expect(warped(tester, startDay + 3), isFalse, reason: '同上（再往深一格）');

      await g.up();
      await tester.pumpAndSettle();
      await disposeCalendar(tester);
    });

    testWidgets('长按落在周标题上：不进入多选态、一层带子都不画', (tester) async {
      await pumpCalendar(tester, 'day_night_rest_rest', liquid: true);
      // 周标题那一行：它的中心落在 `_weekdayH` 之内 → `_dateFromPosition` 给出
      // 负的行号 → `date == null` → 范围态保持为空。（别拿格子的 top 减几像素去凑 ——
      // 格高是按剩余空间算的，减多少才落在标题行里得靠算。）
      final TestGesture g = await tester
          .startGesture(tester.getCenter(find.text(L10n.weekdays.first)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(CalendarRangeBand), findsNothing);
      await g.up();
      await tester.pumpAndSettle();
      await disposeCalendar(tester);
    });

    testWidgets('拖选当中换月（另一根手指点 ‹）：不许崩', (tester) async {
      // 独立审查抓的那条：`showBand` 只看「在不在多选态」，而带子的落点
      // (`bandTipRect` = `_cellRect(bandFocus)`) 在**换月之后就是 null** ——
      // 下一帧那个 `!` 会当场抛。
      await pumpCalendar(tester, 'day_night_rest_rest', liquid: true);
      final TestGesture g = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('day-card-$rangeFirstDay'))));
      await tester.pump(const Duration(milliseconds: 600)); // 进多选态
      await tester.tap(find.byIcon(Icons.chevron_left_outlined)); // 换月
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull,
          reason: '拖选当中换月把带子画崩了（落点算不出来时还硬要画）');
      await g.up();
      await tester.pumpAndSettle();
      await disposeCalendar(tester);
    });

    testWidgets('松手之后静止：带子收干净、没有待处理的帧', (tester) async {
      await pumpCalendar(tester, 'day_night_rest_rest', liquid: true);
      await longPressDragCell(tester, rangeFirstDay, 1);
      expect(find.byType(CalendarRangeBand), findsNothing,
          reason: '松手之后带子还挂着（那时该已经弹选择层了）');
      // 常驻动画会让整套 widget 测试在 `pumpAndSettle` 上集体超时（v0.9.8 的老账）。
      expect(tester.binding.hasScheduledFrame, isFalse);
      await disposeCalendar(tester);
    });
  });


  // ── 光晕在交互时暂停（v0.10.20；判据在 v0.10.22 收紧）────────────────────
  //
  // 光晕每 340ms 走一步。它走的那一步在 v0.10.20 里已经不牵动整页了，但拖动时它
  // 仍然每 340ms 触发一次「光晕那一帧」、与拖动帧撞在一起 —— 那是**每 340ms 一次
  // 固定掉帧**。所以有东西在动的时候把它停掉（`_t` 不推进 ⇒ 恢复时从原处续上、不跳回）。
  //
  // ⚠️ **判据是「这一帧有没有东西在产出」，不是「手指按着」**（v0.10.21 之前是后者，
  // 那是错的）：手指按住不动时屏幕上没有任何东西在变，把光晕也冻住没有理由。
  group('光晕在交互时暂停', () {
    Future<TestGesture> pressToday(WidgetTester tester) async {
      final TestGesture g = await tester.startGesture(tester.getCenter(
          find.byKey(ValueKey('day-card-${appNow().day}'))));
      // 走掉 18px 的 slop 之后 Pan 才赢下竞技场
      for (int i = 0; i < 6; i++) {
        await g.moveBy(const Offset(5, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      return g;
    }

    testWidgets('按住**不动**时光晕接着走 —— 「按着」不等于「在动」', (tester) async {
      await pumpCalendar(tester, 'four_crew_three_shift', liquid: true);
      final TestGesture g = await pressToday(tester);

      final double t0 = glowPhase(tester);
      await pumpFrames(tester, 44); // 约 700ms，够走两步
      expect(glowPhase(tester), isNot(t0),
          reason: '手指按住不动 ⇒ 屏幕上没有任何东西在变 ⇒ 光晕没有理由冻住。'
              'v0.10.21 之前这里判的是 `_dragActive`，按住就停');

      await g.up();
      await disposeCalendar(tester);
    });

    testWidgets('拖动中（每帧都有位移）光晕停；停手之后接着走', (tester) async {
      await pumpCalendar(tester, 'four_crew_three_shift', liquid: true);
      final TestGesture g = await pressToday(tester);

      // 每帧都推一点位移 —— 这才是「在动」
      final double t0 = glowPhase(tester);
      for (int i = 0; i < 44; i++) {
        await g.moveBy(const Offset(3, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(glowPhase(tester), t0,
          reason: '拖动中它不该动 —— 那正是每 340ms 一次固定掉帧的来源');

      // 停手不动 → 恢复
      final double afterStop = glowPhase(tester);
      await pumpFrames(tester, 44);
      expect(glowPhase(tester), isNot(afterStop), reason: '停手之后要接着走');

      await g.up();
      await disposeCalendar(tester);
    });

    testWidgets('换月：动画跑着的那一段光晕不走（而且这条有鉴别力）', (tester) async {
      // ⚠️ **第一版这条是句空话**（最终审查抓出来的）：它只推 10 帧（160ms）就断言
      // 「光晕没动」，而换月动画只有 `durMed`(220ms)、光晕一步是 `durSlow`(340ms) ——
      // **即使完全不暂停，160ms 内它本来也不会走**。判据要落在「本来该走一步、
      // 却没走」那一刻上。
      //
      // 计时：不暂停的话，点 ‹ 那一帧会把光晕的 340ms 定时器重置 ⇒ 约 340ms 后走一步；
      // 暂停的话，定时器要到动画结束（220ms）才重启 ⇒ 约 560ms 后才走。
      // 所以**推 380ms** 正好落在两者之间。
      await pumpCalendar(tester, 'four_crew_three_shift', liquid: true);
      await pumpFrames(tester, 2);

      await tester.tap(find.byIcon(Icons.chevron_left_outlined));
      await tester.pump(const Duration(milliseconds: 16));
      final double t0 = glowPhase(tester);

      await pumpFrames(tester, 24); // 384ms —— 不暂停的话这一步早该走了
      expect(glowPhase(tester), t0,
          reason: '换月动画在跑的这几帧里光晕该停住 —— 不然它会与换月动画撞在一起');

      await pumpFrames(tester, 26); // 再 416ms，动画早结束、定时器也重启过了
      expect(glowPhase(tester), isNot(t0), reason: '换月落定之后要接着走');

      await disposeCalendar(tester);
    });
  });
}
