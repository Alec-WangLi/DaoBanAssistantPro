// app/test/calendar_day_cell_test.dart
//
// 格子胶囊与选中块（实心/淡染、onSolid、圆角同源、FittedBox）、
// 点开某天与调班弹层、以及从日历走进排班时段的那条路径。
//
// 由 app/test/calendar_screen_test.dart 按被测对象切分而来：断言与用例名一字未改，
// 夹具与 helper 在 support/calendar_test_support.dart。

import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_sheet_header.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/schedule_chain.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';
import 'package:shiftassistantpro/features/calendar/info_card_metrics.dart';
import 'package:shiftassistantpro/features/calendar/schedule_editor_screen.dart';
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


  // ---------------------------------------------------------------------------
  // 日历 → 切换排班 → 新增排班：必须和「我的 → 排班管理」一样走模板选择页。
  // 修前这条路径直接 saveSchedule(defaultSchedule()) 并开一个没有 scheduleId 的
  // 编辑器 —— 从日历进来的用户永远看不到 19 种模板。
  // ---------------------------------------------------------------------------

  testWidgets('日历 → 排班时段 → 管理排班时段 → 新增排班：弹「选择你的倒班方式」；返回键放弃不建方案',
      (tester) async {
    final db = await pumpCalendar(tester, 'day_night_rest_rest');
    expect(await scheduleCount(db), 1, reason: '进入前只有种子方案');

    // 顶栏那颗按钮现在是**只读**的「排班时段」总览（v0.9.14 起不再「切换」——
    // 它改的只是「没被时段覆盖时的兜底」，时段盖满之后点它什么也不会变），
    // 底部一个「管理排班时段」跳到排班管理页；新增排班在那页上。
    await tester.tap(find.byTooltip(L10n.scheduleTimeline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.manageTimeline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.addSchedule));
    await tester.pumpAndSettle();

    // 关键：日历这条路径现在也弹模板选择页，而不是直接把默认方案落库
    expect(find.text(L10n.pickShiftPattern), findsOneWidget);

    // 按返回键放弃 → 不建方案
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(L10n.pickShiftPattern), findsNothing);
    expect(await scheduleCount(db), 1,
        reason: '按返回键放弃后不该凭空多出一套方案');

    await disposeCalendar(tester);
  });


  testWidgets('（同一条新路径）选中的模板真的落库，并进入带 id 的编辑器',
      (tester) async {
    final db = await pumpCalendar(tester, 'day_night_rest_rest');

    await tester.tap(find.byTooltip(L10n.scheduleTimeline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.manageTimeline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.addSchedule));
    await tester.pumpAndSettle();
    expect(find.text(L10n.pickShiftPattern), findsOneWidget);

    // 选「四班三倒」：周期 8 天，与默认的四班两倒（4 天）不同，能证明用的是模板。
    final target = findTemplate('four_crew_three_shift')!;
    await tester.enterText(find.byType(TextField), '四班三倒');
    await tester.pumpAndSettle();
    await tester.tap(find.text(target.title));
    await tester.pumpAndSettle();

    // 新方案按模板落库：名字 = 模板副标题，周期长度 = 模板周期。
    expect(await scheduleCount(db), 2);
    final rows = await db.select(db.shiftScheduleRows).get();
    final created = rows.firstWhere((r) => r.name == target.subtitle);
    final domain = await AppRepository(db).getScheduleDomain(created.id);
    expect(domain, isNotNull);
    expect(domain!.cycleLength, target.cycle.length);

    // 弹层关闭，改用带 scheduleId 的编辑器（不再靠 makeCurrent 的隐式约定）。
    expect(find.byType(ScheduleEditorScreen), findsOneWidget);

    await disposeCalendar(tester);
  });


  // 「五处弹层统一头部」那条要求：**时段总览这屏的头部必须与另外四处同内缩。**
  //
  // 它一度保留着外层 `Padding(all: 16)` 包住整个 `Column`，于是
  // `GlassSheetHeader` 被**二次内缩** —— 分隔线比另外四个弹层窄 16dp、把手低
  // 16dp、标题也跟着与下面的行错开（出图量到的）。那种错**任何一条既有用例都照
  // 不出来**（弹层仍然打得开、内容仍然对），所以按几何钉住：头部那条分隔线要贴到
  // `GlassPanel` 的内容盒左缘。
  testWidgets('时段总览：头部与另外四处同内缩（分隔线贴面板内容盒左缘）',
      (tester) async {
    await pumpCalendar(tester, 'day_night_rest_rest');

    await tester.tap(find.byTooltip(L10n.scheduleTimeline));
    await tester.pumpAndSettle();

    final sheet = find.byType(GlassSheetHeader);
    final panel = find.ancestor(of: sheet, matching: find.byType(GlassPanel));
    final headerDivider =
        find.descendant(of: sheet, matching: find.byType(Divider));
    expect(headerDivider, findsOneWidget);

    // 面板**内容盒**的左缘 = 面板缘 + 12 的 margin + 1 的描边 + `GlassPanel` 自己的
    // `spaceXl` 内边距。头部那条分隔线要**贴到它** —— 再往里缩 16 就是被外面那圈
    // padding 二次缩进了（那正是这一屏原来的样子：分隔线比另外四个弹层窄 16、
    // 把手低 16、标题与下面的行错开）。
    final panelRect = tester.getRect(panel);
    final contentLeft =
        panelRect.left + AppTokens.spaceMd + 1 + AppTokens.spaceXl;
    final header = tester.getRect(headerDivider);
    expect(header.left, moreOrLessEquals(contentLeft, epsilon: 1.0),
        reason: '头部的分隔线要贴面板内容盒的左缘（$contentLeft），实测 ${header.left}；'
            '多出 16 就是头部被二次内缩了');

    // 关掉弹层：点遮罩。
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await disposeCalendar(tester);
  });


  testWidgets('格子班次胶囊：选中那天实心（班次色 100%），其余淡染', (tester) async {
    await pumpCalendar(tester, 'white_white_night_night_rest_rest');

    // 胶囊底色 = 班次色按 alpha 合成，所以 alpha 就是「实心 / 淡染」的判据。
    // 读 `AnimatedContainer` 上的 `decoration`（目标值）：补间进行中也断言目标，
    // 与「落地后应该是什么」一致。
    BoxDecoration chipDeco(int day) =>
        tester.widget<AnimatedContainer>(find.byKey(ValueKey('day-chip-$day')))
            .decoration! as BoxDecoration;
    double chipAlpha(int day) => chipDeco(day).color!.a;

    final today = appNow().day;
    final other = today == 1 ? 2 : 1;

    // 初始选中「今天」（`initState` 就把 `_selected` 设成今天）。
    expect(chipAlpha(today), closeTo(1.0, 1e-6),
        reason: '选中那天的胶囊要实心 —— 首帧就选中的日子也必须生效，'
            '这里曾经因为底色走 AnimatedContainer 而停在淡染');
    expect(chipAlpha(other), closeTo(0.14, 1e-6), reason: '没选中的那天要淡染');

    // 换选一天：实心跟着走。
    await tester.tap(find.text('$other').first);
    await tester.pumpAndSettle();
    expect(chipAlpha(other), closeTo(1.0, 1e-6));
    expect(chipAlpha(today), closeTo(0.14, 1e-6));

    await disposeCalendar(tester);
  });


  testWidgets('格子班次胶囊：实心时文字色取 onSolid，且与底色过 AA', (tester) async {
    await pumpCalendar(tester, 'white_white_night_night_rest_rest');
    final today = appNow().day;

    final chip = tester.widget<AnimatedContainer>(
        find.byKey(ValueKey('day-chip-$today')));
    final deco = chip.decoration! as BoxDecoration;
    final ink = tester
        .widget<Text>(find.descendant(
            of: find.byKey(ValueKey('day-chip-$today')),
            matching: find.byType(Text)))
        .style!
        .color!;

    // 实心胶囊只有「白或黑」两种文字色（`onSolid`），且对任何底色都 ≥ 4.58:1。
    expect(ink, AppTokens.onSolid(deco.color!));
    expect(AppTokens.contrastRatio(ink, deco.color!), greaterThanOrEqualTo(4.5));

    await disposeCalendar(tester);
  });


  testWidgets('选中块：不能带 boxShadow —— 阴影会从半透明块内透出来洗掉胶囊色相',
      (tester) async {
    await pumpCalendar(tester, 'white_white_night_night_rest_rest');

    final block = tester
        .widget<Container>(find.byKey(const Key('calendar-selection-block')));
    final deco = block.decoration! as BoxDecoration;

    // 这一层画在网格之上，必须半透明（不透明会把选中那格的内容整个糊掉），
    // 于是任何 boxShadow 都会从块内部透出来再叠一层主色：实测格子内部吃到
    // 约 33% 主色，橙 `#FF9F0A` 的实心胶囊被洗成棕 `#C28758`。
    expect(deco.boxShadow, anyOf(isNull, isEmpty),
        reason: '选中块只留 2px 主色描边 + 13% 淡染，不要阴影');
    expect(deco.color!.a, lessThan(1.0), reason: '填充必须半透明，内容才看得见');

    await disposeCalendar(tester);
  });


  testWidgets('选中块：圆角必须与格子卡片同源 —— 差一档就从四个角露出卡片',
      (tester) async {
    // v0.7.3 真机实测：块走 radiusL(22)、卡片走 radiusM(16)，两者尺寸与位置
    // 完全一致（同 inset、同一格），于是四个角各露出一条约 4dp 的月牙 ——
    // 看起来就是「滑块没把日期格子盖住」。两处现在都取 `_cellRadius`，
    // 这条用例钉着它们相等：哪天有人只改其中一边，这里会红。
    await pumpCalendar(tester, 'white_white_night_night_rest_rest');
    final today = appNow().day;

    final blockRadius = (tester
            .widget<Container>(find.byKey(const Key('calendar-selection-block')))
            .decoration! as BoxDecoration)
        .borderRadius;
    final cardRadius = (tester
            .widget<Container>(find.byKey(ValueKey('day-card-$today')))
            .decoration! as BoxDecoration)
        .borderRadius;

    expect(blockRadius, cardRadius,
        reason: '选中块盖在同一格上，圆角大一点就会在四个角露出底下的卡片');

    await disposeCalendar(tester);
  });


  testWidgets('格子班次胶囊：简称套在 FittedBox 里，不靠算宽度', (tester) async {
    // v0.7.1 的坑：胶囊字号原本按「字数 × 基准字号」硬算可用宽度，是**零余量**
    // 的 —— 两字简称差一点点就退化成「上…」，系统字号一放大整串字都没了
    // （真机实测）。改成让 FittedBox 按实际排版缩，这里钉住那个兜底还在。
    await pumpCalendar(tester, 'white_white_night_night_rest_rest');

    final chip = find.byKey(ValueKey('day-chip-${appNow().day}'));
    expect(chip, findsOneWidget, reason: '今天那格应该有班次胶囊');
    expect(find.descendant(of: chip, matching: find.byType(FittedBox)),
        findsOneWidget,
        reason: '胶囊文字必须套 FittedBox 兜底（宽度算不准，让排版自己缩）');

    await disposeCalendar(tester);
  });


  testWidgets('信息卡那行班次可点，弹层选中后日历跟着变', (tester) async {
    final db = await pumpCalendar(tester, 'day_night_rest_rest');
    final today = dateOnly(appNow());

    // 点开入口
    await tester.tap(find.byKey(const Key('info-card-shift-line')));
    await tester.pumpAndSettle();
    expect(find.text(L10n.adjustShift), findsOneWidget,
        reason: '弹层要自己说明是干什么的 —— 2026-10-13 反馈：只写日期区间，'
            '长按弹出的那一屏没有任何一处说它是「调整班次」');

    // 挑一个与当前不同的班次
    final before = shiftLine(tester);
    final classes = await db.select(db.shiftClassRows).get();
    final target = classes.firstWhere((c) => !before.contains(c.name));

    await tester.tap(find.text(target.name).last);
    await tester.pumpAndSettle();

    // 落库了
    final rows = await db.select(db.shiftDayOverrides).get();
    expect(rows, hasLength(1));
    expect(rows.single.day, dayNumber(today));
    expect(rows.single.classId, target.id);

    // 界面上那天换了班
    expect(shiftLine(tester), contains(target.name));
    // 并且带上「已调整」标记
    expect(find.text(L10n.adjusted), findsWidgets);

    await disposeCalendar(tester);
  });


  // ── spec §11：唯一一条撤掉按天调整的路 —— 「恢复轮转」 ──
  //
  // 改班那条路（`setDayOverrides`）上面已经钉住了；撤回来这条（`choice.restore`
  // → `repo.clearDayOverrides(days)`，`adjustDays` 里那两行）此前**一次也没跑过**。
  // 它要是接错了（比如清了别的日子、或者干脆没清），日历上那天会一直挂着
  // 「已调整」，用户再也回不到轮转。
  testWidgets('信息卡弹层选「恢复轮转」：覆盖行清掉，「已调整」也不再显示',
      (tester) async {
    final db = await pumpCalendar(tester, 'day_night_rest_rest');
    final today = dateOnly(appNow());

    // 先造出「今天被单独改过」的状态
    final classes = await db.select(db.shiftClassRows).get();
    await AppRepository(db).setDayOverrides([today], classId: classes.first.id);
    await tester.pumpAndSettle();

    expect(await db.select(db.shiftDayOverrides).get(), hasLength(1));
    expect(find.byKey(const Key('info-card-adjusted')), findsOneWidget);
    expect(find.byKey(ValueKey('day-adjusted-${today.day}')), findsOneWidget);

    // 点开信息卡那行（入口就是它），底部弹层里挑「恢复轮转」
    await tester.tap(find.byKey(const Key('info-card-shift-entry')));
    await tester.pumpAndSettle();
    expect(find.text(L10n.restoreRotation), findsOneWidget,
        reason: '这天被覆盖过，弹层才该给这条退路');

    await tester.tap(find.text(L10n.restoreRotation));
    await tester.pumpAndSettle();

    // 覆盖行清干净，界面回到轮转态
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty,
        reason: '「恢复轮转」要把这天的覆盖行真的删掉');
    expect(find.byKey(const Key('info-card-adjusted')), findsNothing,
        reason: '覆盖没了，「已调整」这句说明也要跟着消失');
    expect(find.byKey(ValueKey('day-adjusted-${today.day}')), findsNothing,
        reason: '格子上的小圆点同理');
    // 这里不断「已把 1 天恢复为轮转」那条提示：`adjustDays` 走完
    // `clearDayOverrides` 之后还要 `await AlarmService.rescheduleAll(repo)`，
    // 而那一串原生插件调用在 flutter_test 里不会 resolve（上一版我试着多
    // `pump` 了 20 秒假时钟，SnackBar 依然是 0 —— 换成「改班」那条路同样为 0，
    // 所以是环境如此，不是恢复这条路的毛病）。提示条因此测不到，覆盖行与
    // 「已调整」标记这两条是这条用例真正要钉住的东西。

    await disposeCalendar(tester);
  });


  testWidgets('没被覆盖过的那天：弹层不给「恢复轮转」', (tester) async {
    await pumpCalendar(tester, 'day_night_rest_rest');

    await tester.tap(find.byKey(const Key('info-card-shift-entry')));
    await tester.pumpAndSettle();

    expect(find.text(L10n.restoreRotation), findsNothing,
        reason: '本来就在轮转上，没有可恢复的东西 —— 这条由 canRestore 把住');

    await disposeCalendar(tester);
  });


  testWidgets('被覆盖的那天在格子上有小圆点标记', (tester) async {
    final db = await pumpCalendar(tester, 'day_night_rest_rest');
    final today = dateOnly(appNow());

    expect(find.byKey(ValueKey('day-adjusted-${today.day}')), findsNothing);

    final classes = await db.select(db.shiftClassRows).get();
    final repo = AppRepository(db);
    await repo.setDayOverrides([today], classId: classes.first.id);
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('day-adjusted-${today.day}')), findsOneWidget,
        reason: '被调整过的那天要有可辨认的标记');

    // spec §7.4：小圆点**固定在 3–4dp、不跟格子高度缩放**。这里断的是规格
    // 区间而不是复述令牌 —— 上一版用的 `gapHair`（2）正好落在规格点名的
    // 「小窗里缩到 1–2px 就等于没有」那一段里，这条断言能把它拦下来。
    final dot =
        tester.getSize(find.byKey(ValueKey('day-adjusted-${today.day}')));
    expect(dot.width, inInclusiveRange(3, 4));
    expect(dot.height, inInclusiveRange(3, 4));

    await disposeCalendar(tester);
  });



  // 设计语言：新加的东西要抄**最近的同类件配方**。
  //
  // 「已调整」原先是班次行里唯一的**裸文字** —— 而同一页的两个邻居（日期行上的
  // 「今天」「N 项待办」徽章）都是胶囊。三种形状并排，看着就散。所以它改抄
  // `_todoHintBadge` 的配方（14% 淡染底 + 45% 同色描边 + `radiusL` + `inkFor`），
  // 只是不带图标。
  //
  // ⚠️ 这条用例**只**钉形状，**不**钉「卡片高度不因标记而变」—— 那个说法是错的：
  // 高度按**月**预留（`hasOverrideHint`，与 `hasTodoHint` 同一条路），所以「本月
  // 一天覆盖也没有」与「本月有被调过的日子」两个月份之间高度**本来就该不一样**。
  // 写成「加覆盖前后高度相同」等于断言那条按月闸门的反面，而且它还会绿 ——
  // 只因测试字体下胶囊（21.8）比班次行（22.88）矮；等哪天有人把胶囊做高一点，
  // 它会红，下一个人就会去「修」掉按月预留下来。形状与模型分开钉，各钉各的。
  testWidgets('「已调整」是胶囊而不是裸文字', (tester) async {
    final db = await pumpCalendar(tester, 'day_night_rest_rest');

    final classes = await db.select(db.shiftClassRows).get();
    final repo = AppRepository(db);
    final today = dateOnly(appNow());
    await repo.setDayOverrides([today], classId: classes.first.id);
    await tester.pumpAndSettle();

    // 标记还在，而且**它自己**就是一颗胶囊（不是裸 Text）。
    //
    // 注意 key 就挂在那个 Container 上，所以要用 `tester.widget<Container>` 直接
    // 看它自己 —— `find.ancestor(of: marker, …)` 找的是它的**祖先**，不含它本身，
    // 那样写会恒为空、用例假失败。
    final marker = find.byKey(const Key('info-card-adjusted'));
    expect(marker, findsOneWidget);
    final deco =
        tester.widget<Container>(marker).decoration as BoxDecoration?;
    expect(deco?.borderRadius, isNotNull,
        reason: '「已调整」要与同一行另外两个徽章一样是胶囊');
    expect(deco?.border, isNotNull, reason: '信息胶囊是「淡染底 + 同色描边」两件套');

    await disposeCalendar(tester);
  });


  // 「胶囊高度真的进了定高模型」这件事在这里量 —— 界面侧量不到它。
  //
  // 界面侧量不到的原因是个字体巧合：`DefaultTextStyle` 走的 Material 排版表行高
  // 1.43，班次行是 16px 的一行字 → 22.88，而胶囊是 12px×1.15 + 上下内边距 6 +
  // 描边 2 = 21.8 —— 胶囊**比班次行还矮**，顶不动行高，所以界面高度对「模型有
  // 没有算它」逐像素不敏感。（真机上字体行高比例一变，胶囊就会成为行里的最高件，
  // 那时它必须已经被算进取大。）
  //
  // 所以这里直接调 `measureBottomInfoCardHeight`，并换一个**紧行高**的
  // `DefaultTextStyle` 把差别放大出来：行高压到 1.0 后班次行只有 16.0，胶囊 21.8
  // 成了行里最高件 —— `hasOverrideHint` 的取舍立刻可见、也确实能失败（把
  // `_adjustedBadgeH` 从取大列表里拿掉，这条即红）。
  //
  // **残留缺口**（控制器已知并记在账上）：它证明的是「模型的这一项是通的」，
  // 而**不**证明「同一个月里换选中哪天高度不变」—— 后者在本夹具里被同一个字体
  // 巧合遮住（高度对逐日差异不敏感），本套件不钉。
  testWidgets('定高模型：「本月有被调整的日子」要为「已调整」胶囊多留高度', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: DefaultTextStyle(
        // 只压行高，字号/字重照旧走角色令牌（模型内部自带）。
        style: const TextStyle(height: 1.0),
        child: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ),
    ));

    // ⚠️ **必须挂一套真排班**（v0.9.16 改的）：班次行的高度从这一版起是**逐日算**的，
    // 而 `hasOverrideHint` 只在「那天有班次」时才参与取大。挂 `chain: null` 的话，
    // 那一天走的是「这段时间没有排班」那一支，两种输入量出来一模一样 —— 这条用例
    // 换个写法立刻会变成一句永远为真的空话。（「空白表那天不占这一行」由
    // `info_card_chain_test.dart` 那条新的用例钉住。）
    //
    // 一套单班组、两天一轮的排班：不挂多班组就没有色块那一段的干扰，而每天都排得上
    // 班次（白 / 休交替），那一行天天在。
    final chain = ScheduleChain(
      fallback: ShiftSchedule(
        name: '两天一轮',
        anchorDate: DateTime.utc(2026, 1, 1),
        classes: const [
          ShiftClass(name: '白班', abbr: '白', startMinute: 480, endMinute: 1080),
          ShiftClass(name: '休班', abbr: '休', isRest: true),
        ],
        cycle: const [0, 1],
        teamCount: 1,
        teamNames: const ['我'],
        teamOffsets: const [0],
      ),
    );
    double cardH({required bool hasOverrideHint}) => measureBottomInfoCardHeight(
          context: ctx,
          cardOuterWidth: 420,
          chain: chain,
          month: DateTime(2026, 9, 1),
          hasTodoHint: false,
          hasOverrideHint: hasOverrideHint,
        ).outerHeight;

    expect(cardH(hasOverrideHint: true), greaterThan(cardH(hasOverrideHint: false)),
        reason: '这个月有被按天调过的日子时，班次行要按「已调整」胶囊的高度预留 —— '
            '少了这一步，真机上有标记的那天卡片内容会顶出定高');

    await disposeCalendar(tester);
  });

  // ── 信息卡最后那行「本月统计」 ──
  //
  // 它填的是卡片**按月定高**留下的那截富余：最满的一天（有法定节假日、农历又占两行
  // 的日子）正好占满，普通日子空出 32~51dp。**卡片高度一像素都不能为此动** —— 动了
  // 上面六个格子就跟着抖，而用户明确不要那个抖动。所以判定只能是「这天的富余装得下
  // 就画」，下面两条一条盯「装不下真的不画、画了真的不裁」，一条盯「数字对不对」。

  /// 往后翻，找到第一个**有法定节假日**的月份（只有这种月份才有富余可填；没有节假日
  /// 的月份，卡片是按普通日子的高度定的，几乎没有空档）。

  /// 点开这一天，并回答「统计行画着没有」。
}
