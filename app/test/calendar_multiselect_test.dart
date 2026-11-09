// app/test/calendar_multiselect_test.dart
//
// 长按拖选：范围态、空白表三态、系统取消、触觉、以及小窗那一档。
//
// 由 app/test/calendar_screen_test.dart 按被测对象切分而来：断言与用例名一字未改，
// 夹具与 helper 在 support/calendar_test_support.dart。

import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
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


  testWidgets('长按拖选一段日子后弹层改多天', (tester) async {
    final db = await pumpCalendar(tester, 'day_night_rest_rest');

    // 长按「8 日」那格，往下拖一格 → 圈住 8…15 共 8 天
    await longPressDragCell(tester, rangeFirstDay, 1);

    // 弹层出来了，标题是「起点 – 终点 · 8 天」
    expect(find.textContaining('$rangeSpan 天'), findsOneWidget);

    final classes = await db.select(db.shiftClassRows).get();
    await tester.tap(find.text(classes.first.name).last);
    await tester.pumpAndSettle();

    // 圈住的那 8 天都要落库，而且**就是这 8 天**（不是数目对、日子错）。
    final rows = await db.select(db.shiftDayOverrides).get();
    final now = appNow();
    expect(
        rows.map((r) => r.day).toSet(),
        {
          for (var d = rangeFirstDay; d <= rangeLastDay; d++)
            dayNumber(DateTime(now.year, now.month, d)),
        },
        reason: '圈住的 8…15 每一天都要落库');
    expect(rows.map((r) => r.classId).toSet(), {classes.first.id});

    await disposeCalendar(tester);
  });


  testWidgets('长按向上拖选：起点在终点之后，区间要归一成正序', (tester) async {
    // 拖回去（15 日 → 8 日）时 `_rangeAnchor` 是**后**一天、`_rangeFocus` 是
    // **前**一天。`adjustDays` 不认 `from > to`（会静默拼出空列表、弹一条
    // 误导的提示），所以松手前必须把两端调换成正序 —— 这条用例钉住那步。
    final db = await pumpCalendar(tester, 'day_night_rest_rest');

    await longPressDragCell(tester, rangeLastDay, -1); // 往上拖一格

    expect(find.textContaining('$rangeSpan 天'), findsOneWidget,
        reason: '起点在后、终点在前，区间跨度仍是 8 天');

    final classes = await db.select(db.shiftClassRows).get();
    await tester.tap(find.text(classes.first.name).last);
    await tester.pumpAndSettle();

    final now = appNow();
    final rows = await db.select(db.shiftDayOverrides).get();
    expect(
        rows.map((r) => r.day).toSet(),
        {
          for (var d = rangeFirstDay; d <= rangeLastDay; d++)
            dayNumber(DateTime(now.year, now.month, d)),
        },
        reason: '归一之后落的还是 8…15 这 8 天，不是空区间');

    await disposeCalendar(tester);
  });


  // 长按拖选（LongPress）与滑块（Pan）挂在**同一个** `GestureDetector` 上，
  // 靠竞技场分流：按住不动约 500ms 长按赢，立刻滑动超过 touch slop 则是 Pan 赢。
  // 上面两条钉住长按那一支；这条钉住 Pan 那一支没被长按顶掉 —— 顶掉了日历就
  // 没法拖着滑块选日子了，而这是这一页最早的交互。
  testWidgets('长按手势没顶掉单格滑块：立刻滑动仍是拖拽选中', (tester) async {
    final db = await pumpCalendar(tester, 'day_night_rest_rest');

    // 先点中 8 日：滑块落在它上面（拖拽的基准是**滑块**，不是手指按下的地方）。
    await tester.tap(find.text('$rangeFirstDay').first);
    await tester.pumpAndSettle();

    // 卡片外面还裹着一层 `_cellInset`（= gapHair）的四边内缩，所以格子高 =
    // 卡片高 + 2×gapHair。滑块走的是「松手位置 − 起手位置」，位移给满一格。
    final card = find.byKey(const ValueKey('day-card-$rangeFirstDay'));
    final cellH = tester.getSize(card).height + AppTokens.gapHair * 2;

    final gesture = await tester.startGesture(tester.getCenter(card));
    // 第一下先走掉 touch slop（这一下只让 Pan 赢得竞技场，滑块纹丝不动），
    // 第二下才是真正的位移。
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(Offset(0, cellH));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 滑块吸附到下一行那一格 → 选中日变成 15 日，且那一格的胶囊是实心的。
    final now = appNow();
    expect(
        find.text(L10n.monthDayWeekday(
            DateTime(now.year, now.month, rangeLastDay))),
        findsOneWidget,
        reason: '立刻滑动仍要吸附到下一行那一格');
    final chip = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('day-chip-$rangeLastDay')));
    expect((chip.decoration! as BoxDecoration).color!.a, closeTo(1.0, 1e-6),
        reason: '松手后滑块落在那格，胶囊要实心');
    // 而且这一下**不是**长按拖选：没弹改班层，也就没落任何覆盖。
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty,
        reason: '立刻滑动不该被当成长按拖选');

    await disposeCalendar(tester);
  });


  // ── spec §7.3：空白表方案（跟随法定节假日）下长按不进入范围态 ──
  //
  // 空白表没有班次定义可挑：让用户拖出一片淡染、松手却什么也不发生，是死的
  // 交互。信息卡那个入口（Task 8）已经按同一条判据灰掉了，这条钉住长按这一路
  // 也跟上 —— 两处判据必须同源。
  //
  // 断言写在**拖动中**（`midDrag`）：范围淡染松手就收，等 `longPressDragCell`
  // 跑完再看是看不到它的，那条断言会变成一句永远为真的空话（我第一版就是
  // 这么写的，靠"把闸门拆掉跑一遍"才照出来）。
  testWidgets('空白表方案：长按不进入范围态，也不落覆盖', (tester) async {
    final db = await pumpCalendar(tester, 'day_night_rest_rest', blank: true);

    // 触觉一起钉：`onLongPressStart` 里的 `modeEnter()` 挂在 `if (date != null)`
    // 之下 —— 这一下压根没进入多选态，就不许发那记「进入多选态」的强震。
    // 少了这条，「闸门」没人看着，下次谁把条件删掉都不会有人知道。
    // （起手那一下**可能**会有一次 selectionClick：长按满 100ms 时 Tap 的 deadline
    // 到点，`onTapDown` → `_selectFromPosition` 把选中挪到按下的那格 —— 那是
    // 真的变了，该响。但若按下的那格**本来就是当前选中**（本月 8 号恰是今天时），
    // 那一下是无变化的 no-op，一条也没有。所以下面的断言是「不含 mediumImpact」
    // 而不是「为空」—— 它不依赖起手有没有那一记。）
    final fired = <Object?>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
      return null;
    });
    addTearDown(() => messenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await longPressDragCell(tester, rangeFirstDay, 1, midDrag: () async {
      expect(rangeTintCount(tester), 0, reason: '空白表下长按不该画范围淡染');
      expect(blockScale(tester), 1.0, reason: '空白表下这一下也不该点亮玻璃块');
    });

    expect(fired, isNot(contains('HapticFeedbackType.mediumImpact')),
        reason: '空白表下压根没进入多选态，不该发 modeEnter 那记强震');

    expect(find.textContaining('$rangeSpan 天'), findsNothing,
        reason: '空白表下不该弹改班层');
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty,
        reason: '空白表下不该落任何覆盖');

    await disposeCalendar(tester);
  });


  // ── 空白表方案：整月一天胶囊都不画，但**也不说「没有排班」** ──
  //
  // 这一版把两条判据拆开了，两条各钉一遍（它们曾经被搅在一起）：
  //   · **画什么** —— 空白表（跟随法定节假日）没有班次定义，格子只画日期与农历，
  //     不替它断言今天上不上班。2026-09-30 用户原话：「确实不应该显示上班嘛，它
  //     本质上可能就想当个日历看」。v0.9.15 一度给它合成了「上班 / 休息」两个
  //     合成班次，那是**拿显示去迁就判据**，已回退。
  //   · **说不说「没有排班」** —— 判据是「这天有没有班表在管」
  //     （`ScheduleChain.hasScheduleOn`），空白表**天天都在管**，所以那句指路
  //     不该出现。v0.9.14 用的正是 `shiftOn == null`，于是只有一套法定班次的人
  //     整张日历被它盖住 —— 那才是这一对的起因。
  // 反面（真的没有任何班表时照旧盖）由 `calendar_chain_test` 的
  // 「其余时间为无 + 没有段」那条罩着。
  testWidgets('空白表方案：整月一天胶囊都不画，但也不说「没有排班」', (tester) async {
    await pumpCalendar(tester, 'day_night_rest_rest', blank: true);

    expect(find.text(L10n.noScheduleHere), findsNothing,
        reason: '有班表在管（跟随法定节假日），不该说「这段时间没有排班」');
    expect(find.text(L10n.noSchedule), findsNothing,
        reason: '信息卡里那句同样不该出现');

    final today = appNow();
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
    for (var d = 1; d <= daysInMonth; d++) {
      expect(find.byKey(ValueKey('day-chip-$d'), skipOffstage: false),
          findsNothing, reason: '$d 日不该画任何班次胶囊 —— 空白表就是一张日历');
    }
    // 格子还在（不是一张空网格）：日期与农历照旧。
    expect(find.byKey(const ValueKey('day-card-1')), findsOneWidget);

    await disposeCalendar(tester);
  });


  // ── 长按落在本月之外的空白格 ──
  //
  // 选星期表头那一条：`_dateFromPosition` 的 `row < 0` 分支（表头中心 y ≈ 13，
  // 减掉 `_weekdayH` 26 之后是负行）。这一下不是范围选择，但它是**被长按赢下**
  // 的手势 —— `onTapUp` / `onPanEnd` 都不会再来，不在这儿把 `_pressed` 熄掉，
  // 玻璃块会一直停在按下的放大态（1.22）直到下一次触点。
  testWidgets('长按落在本月之外的空白格：不画范围，玻璃块也不能卡在放大态', (tester) async {
    final db = await pumpCalendar(tester, 'day_night_rest_rest');

    final gesture = await tester.startGesture(
        tester.getCenter(find.text(L10n.weekdays.first)));
    await tester.pump(const Duration(milliseconds: 600)); // 过长按判定
    await gesture.up();
    await tester.pumpAndSettle();

    expect(rangeTintCount(tester), 0);
    expect(blockScale(tester), 1.0,
        reason: '长按在空白格上也要把玻璃块收回去');
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty);

    await disposeCalendar(tester);
  });


  // ── 长按拖到一半，手指被系统取消 ──
  //
  // 长按赢下竞技场之后框架只把 `PointerUp` 送进 `onLongPressEnd`；取消走的是
  // 另一条回调 `onLongPressCancel`（长按已经 accept 也照样会发 ——
  // `GestureRecognizerState` 只有 ready/possible/defunct 三档，accept 不改
  // state，所以 `_checkLongPressCancel` 那道 `state == possible` 的闸门仍然
  // 放行）。两条回调缺一条，那片淡染就会一直挂在屏幕上。
  testWidgets('长按拖到一半被系统取消：范围淡染要收干净', (tester) async {
    final db = await pumpCalendar(tester, 'day_night_rest_rest');

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('day-card-$rangeFirstDay'))));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();

    // 拖动中就圈住 8…15 这 8 格：逐格画，所以正好 8 个 —— 画成外接矩形的话
    // 会多出整整一行（14 个）。
    expect(rangeTintCount(tester), rangeSpan,
        reason: '拖选中：8…15 逐格淡染，一个不多一个不少');

    await gesture.cancel(); // 切前台、来电之类的系统取消
    await tester.pumpAndSettle();

    expect(rangeTintCount(tester), 0, reason: '取消之后不该留下任何范围淡染');
    expect(blockScale(tester), 1.0);
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty,
        reason: '取消不是「松手」，不该落库');

    await disposeCalendar(tester);
  });


  // ── spec §4.3：日历手势的触觉 ──
  //
  // 用户 v0.8.1 的原话：「长按这个滑块的时候，它不是会触发这个连选吗？那它触发
  // 的时候能不能加个震动反馈啊，这样区分更明显一点」。长按因此分两级：进入多选态
  // 那一下要「更明显」（`modeEnter`），之后每进一格再轻震一下（`select`）——
  // 用户在两档里选了「进入时震 + 每进一格再轻震」。
  //
  // 拦截平台通道来断言：三档触觉都走 `SystemChannels.platform` 的
  // `HapticFeedback.vibrate`，只是参数字符串不同（与 `haptics_test.dart` 同一招）。

  testWidgets('长按进入多选态震一次，每进一格再震一次', (tester) async {
    final fired = <Object?>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
      return null;
    });
    addTearDown(() => messenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpCalendar(tester, 'day_night_rest_rest');
    fired.clear(); // 建树过程本身不该有触觉

    final start =
        tester.getCenter(find.byKey(const ValueKey('day-card-8')));
    // 格子节距 = 卡片高 + 上下各一条发丝间隙（与上面那条滑块用例同一算式）。
    // 用节距而不是写死 60：一次 move 正好跨一行，落点是确定的。
    final cellH =
        tester.getSize(find.byKey(const ValueKey('day-card-8'))).height +
            AppTokens.gapHair * 2;

    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600)); // 过长按判定

    // 起手那一下的账先单独记：Tap 的 deadline 到点会走一次 `_selectFromPosition`
    // （把选中挪到按下的那格，真的变了、该响），紧接着是 `modeEnter`。此后
    // **只数 move 的贡献**，断言就不依赖「今天是不是正好 8 号」这种日期脸色。
    final selBefore =
        fired.where((f) => f == 'HapticFeedbackType.selectionClick').length;
    expect(fired.where((f) => f == 'HapticFeedbackType.mediumImpact'), hasLength(1),
        reason: '进入多选态在起手那一刻发一记 modeEnter');

    await gesture.moveBy(Offset(0, cellH)); // 8 → 15
    await tester.pump();
    await gesture.moveBy(Offset(0, cellH)); // 15 → 22
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // **精确计数**，不是 `contains`：后者在 `onLongPressMoveUpdate` 那一行被删掉
    // 时依然由起手那记 select 满足 —— 于是「长按拖选每进一格」这个落点没有任何
    // 东西看着（正是 spec 警告过的「两个落点别只改一个」的镜像）。
    final selAfter =
        fired.where((f) => f == 'HapticFeedbackType.selectionClick').length;
    expect(selAfter - selBefore, 2,
        reason: '长按拖过两格 → 恰好两记 select：每进一格一记，多一下少一下都说明落点不对');
    expect(fired.where((f) => f == 'HapticFeedbackType.mediumImpact'), hasLength(1),
        reason: '整场手势只该进入一次多选态');

    await disposeCalendar(tester);
  });


  testWidgets('单格滑块拖到新的一格时震，没换格不震', (tester) async {
    final fired = <Object?>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
      return null;
    });
    addTearDown(() => messenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpCalendar(tester, 'day_night_rest_rest');
    fired.clear();

    final cellH =
        tester.getSize(find.byKey(const ValueKey('day-card-8'))).height;
    final start = tester.getCenter(find.byKey(const ValueKey('day-card-8')));

    // 先把滑块钉在 8 日再动它。拖拽的基准是**滑块**、不是手指按下的地方
    // （`onPanStart` 读的是 `_selectedRect`）—— 不先钉住的话，「往下拖一格」落到
    // 的是「今天 + 7」，而今天落在月末那几天就掉出本月、`_nearestDateFromVisual`
    // 返回 null，选中其实一步没动，这条用例会在每个月的某些日子随机转红。
    // 钉在 8 日则是 8 日（第 2 行）→ 15 日（第 3 行），任何月份都成立（见文件头）。
    await tester.tapAt(start);
    await tester.pumpAndSettle();

    // 原地轻点（还是 8 日，没有换格）→ 不震
    fired.clear();
    await tester.tapAt(start);
    await tester.pumpAndSettle();
    expect(fired, isEmpty, reason: '选中没变不该震');

    // 拖一格 → 选中变了 → 震
    var gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, 20)); // 过 slop
    await tester.pump();
    await gesture.moveBy(Offset(0, cellH)); // 落到下一行
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fired, isNotEmpty, reason: '选中换了格该震');

    // 拖出去又拖回来（松手还落回原来那格）→ 同样「没换格」，不震
    fired.clear();
    gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, 20)); // 过 slop，Pan 赢下竞技场
    await tester.pump();
    await gesture.moveBy(const Offset(0, -20)); // 拖回原格
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fired, isEmpty, reason: '拖回原来那格不该震');

    // 点按**另一格** → 恰好一记 select。
    //
    // 用**精确列表**而不是 `isNotEmpty`：上面每一条都由旁边的拖拽（`onPanEnd`）
    // 一路满足，所以 `_selectFromPosition` 里那行 `Haptics.select()` 被删掉时
    // 套件照样全绿 —— 点选这个落点没有任何东西看着。这条会红。
    fired.clear();
    await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('day-card-9'))));
    await tester.pumpAndSettle();
    expect(fired, ['HapticFeedbackType.selectionClick'],
        reason: '点按换了格：恰好一记 select（多一记少一记都说明点选落点不对）');

    await disposeCalendar(tester);
  });


  testWidgets('小窗（高 < 480dp）：网格让位，只留信息卡；「已调班」还在', (tester) async {
    // 200×400 是各机型小窗的默认尺寸（也是我们真机上量到的那档）。
    final db = await pumpCalendar(tester, 'day_night_rest_rest',
        width: 200, height: 400);

    // 先确认这个尺寸确实落进了小窗那一档：网格不画了。
    expect(find.byKey(const ValueKey('day-card-8')), findsNothing,
        reason: '小窗下两者都想要的结果是两者都看不清 —— 格子让位给信息卡');

    // 给「今天」上一条按天调整，标记必须出现在信息卡上。
    final classes = await db.select(db.shiftClassRows).get();
    await AppRepository(db)
        .setDayOverrides([dateOnly(appNow())], classId: classes.first.id);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('info-card-adjusted')), findsOneWidget,
        reason: '小窗里格子窄到画不出胶囊、圆点根本不会出现，'
            '信息卡是唯一还能承载这个标记的地方');

    await disposeCalendar(tester);
  });


  // 空白表（跟随法定节假日）在小窗那一档：**不画网格**，信息卡是屏幕上唯一的内容。
  //
  // 那两个字（上班 / 休息）在 v0.9.16 撤掉了，而**「没有排班」那句同样不能有** ——
  // 这是两条判据的分工在小窗上的样子：不替它断言，但也不说它没排班。
  testWidgets('空白表方案：小窗那一档不写「上班」，也不说「没有排班」', (tester) async {
    await pumpCalendar(tester, 'day_night_rest_rest',
        blank: true, width: 200, height: 400);

    expect(find.byKey(const ValueKey('day-card-8')), findsNothing,
        reason: '确认这个尺寸确实落进了小窗那一档（网格让位）');
    expect(find.text(L10n.workday), findsNothing);
    expect(find.text(L10n.rest), findsNothing);
    expect(find.text(L10n.noSchedule), findsNothing);
    // 日期还在（卡片不是空的，只是不再多说什么）。
    expect(find.text(L10n.monthDay(dateOnly(appNow()))), findsOneWidget);

    await disposeCalendar(tester);
  });


  testWidgets('400×640 那档小窗不受影响：网格与「已调班」都还在', (tester) async {
    // 各机型小窗的默认尺寸，高 640 > 480，**不该**被上面那条规则收走网格。
    final today = dateOnly(appNow());
    final db = await pumpCalendar(tester, 'day_night_rest_rest',
        width: 400, height: 640);

    expect(find.byKey(ValueKey('day-card-${today.day}')), findsWidgets,
        reason: '这档是主流小窗尺寸，必须保持网格 + 完整信息卡');

    final classes = await db.select(db.shiftClassRows).get();
    await AppRepository(db).setDayOverrides([today], classId: classes.first.id);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('info-card-adjusted')), findsOneWidget);

    await disposeCalendar(tester);
  });
}
