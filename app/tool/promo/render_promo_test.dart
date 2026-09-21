// app/tool/promo/render_promo_test.dart
//
// 出**宣传图**用的原始截图（README / 酷安），跟 `tool/visual` 的回归工装分开：
//
//   toolchain/flutter/bin/flutter test tool/promo/render_promo_test.dart
//
// 为什么不直接复用回归工装的那批图：
//   1. 假库里没有待办、没有自定义闹钟，拍出来是「还没有待办事项」——宣传图不能是空屏；
//   2. 回归工装按屏单独渲染，**不带底部悬浮胶囊**，跟真机看到的不一样；
//   3. 回归工装的当前排班「今天」落在中班（无闹钟），当天信息卡会写「闹钟：未开启」。
//
// 所以这里用自己的假库（在回归工装的种子之上补数据、换一套「今天正好是白班」的当前方案）
// 和自己的屏单，用 nav 图标切 tab 把胶囊带进画面。产物落 `build/promo/`，
// 再用 `scripts/make_promo_images.py` 套外框 / 出封面到 `docs/images/`。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/alarm/alarm_ringing_screen.dart';
import 'package:shiftassistantpro/features/calendar/schedule_editor_screen.dart';
import 'package:shiftassistantpro/features/calendar/shift_template_picker_screen.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';

import '../visual/visual_harness.dart';

/// 一屏宣传图。`beforeCapture` 用来在装配完、抓图前做交互（切 tab 等）。
typedef _Shot = ({
  String slug,
  String title,
  Future<Widget> Function(AppDatabase db) build,
  Brightness brightness,
  Size size,
  Future<void> Function(WidgetTester tester)? beforeCapture,
});

/// 切到某个底部导航 tab。
///
/// 用**图标**而不是文字定位：导航标签与页面标题有两处重名（「闹钟」「我的」），
/// `find.text` 会一次命中两个而抛错。
///
/// 但「四个导航图标各不相同」这句话**已经不再成立** —— v0.7.1 给日历信息卡加了
/// 「N 项待办」徽章，用的就是 `event_note_outlined`，与「待办」tab 同款。所以查找
/// 必须**限定在导航栏里**（导航栏带 `glass-nav-bar` 这个 key）。别再退回裸的
/// `find.byIcon`：那会在「待办」这张图上匹配到两个控件、直接抛错。
Future<void> _tapTab(WidgetTester tester, IconData icon) async {
  await tester.tap(find.descendant(
    of: find.byKey(const Key('glass-nav-bar')),
    matching: find.byIcon(icon),
  ));
}

/// 逐段移动的滚动手势。
///
/// 不用 `tester.dragFrom(…, 一次大位移)`：那一下实测不生效（列表纹丝不动，
/// 图拍出来和没滚动一样）。分多次 moveBy + 推帧才稳定被滚动识别器采纳。
Future<void> _scrollDown(WidgetTester tester, double dy) async {
  final gesture = await tester.startGesture(const Offset(210, 700));
  const steps = 14;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, -dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await settleVisual(tester);
}

/// 宣传用的假库：回归工装的种子 + 待办 + 自定义闹钟 + 一套「今天正好是白班」的当前方案。
Future<AppDatabase> promoDatabase() async {
  final db = await makeVisualDatabase();
  final repo = AppRepository(db);
  final today = dateOnly(DateTime.now());

  // 换成四班两倒，且让「今天」落在白班：当天信息卡才会显示「闹钟 07:00」，
  // 否则默认那套四班三倒的今天在中班（无联动闹钟），卡片上写着「未开启」。
  //
  // 时间与联动闹钟取的是 App 真正的默认值（见 `domain/shift_rotation.dart` 的
  // `defaultSchedule()`：白班 8:30–20:30 闹钟 7:00、上夜班 20:30–次日 8:30 闹钟 19:30），
  // 免得宣传图和用户装上之后看到的对不上。唯一不同的是简称：默认把「下夜班」和
  // 「大休」都简称作「休」（只靠颜色区分），这里按用户会怎么改写成「下夜」——
  // 这套方案的名字本来就写成「炼油三部 · 四班两倒」，是用户自己那套。
  const shifts = [
    ShiftClass(
        name: '白班',
        abbr: '白',
        startMinute: 8 * 60 + 30,
        endMinute: 20 * 60 + 30,
        color: 0xFF4C8DFF,
        alarmEnabled: true,
        alarms: [ShiftAlarm(minute: 7 * 60)]),
    ShiftClass(
        name: '上夜班',
        abbr: '夜',
        startMinute: 20 * 60 + 30,
        endMinute: 8 * 60 + 30,
        color: 0xFF7A5CFF,
        alarmEnabled: true,
        alarms: [ShiftAlarm(minute: 19 * 60 + 30)]),
    ShiftClass(
        name: '下夜班', abbr: '下夜', isRest: true, color: 0xFF9AA0B4),
    ShiftClass(name: '大休', abbr: '休', isRest: true, color: 0xFF5A5F73),
  ];
  await repo.saveSchedule(
    name: '炼油三部 · 四班两倒',
    anchorDate: today,
    classes: shifts,
    cycle: const [0, 1, 2, 3],
    makeCurrent: true,
    teamCount: 4,
    teamNames: L10n.defaultTeamNames(4),
    ourTeamIndex: 0,
    teamOffsets: const [0, 1, 2, 3],
  );

  // 待办：三条待办 + 一条已完成（已完成那条才有变暗 + 删除线可看）。
  await repo.addEvent(
      title: '和夜班同事交接班',
      date: today,
      timeMinute: 19 * 60,
      advanceRemindMinutes: 15);
  await repo.addEvent(
      title: '班前会 · 三楼会议室',
      date: today.add(const Duration(days: 1)),
      timeMinute: 8 * 60);
  await repo.addEvent(title: '交体检报告', date: today.add(const Duration(days: 3)));
  final doneId = await repo.addEvent(
      title: '领劳保手套',
      date: today,
      timeMinute: 9 * 60,
      advanceRemindMinutes: 15);
  final doneRow = await (db.select(db.scheduleEvents)
        ..where((t) => t.id.equals(doneId)))
      .getSingle();
  await repo.setEventCompleted(doneRow, true);

  // 自定义闹钟一条，免得「自定义闹钟」分区是空文案。
  await repo.addCustomAlarm(hour: 22, minute: 30, repeatType: 1);

  return db;
}

final List<_Shot> _shots = [
  (
    slug: '01_calendar_light',
    title: '日历 · 浅色',
    build: (db) async => const HomeShell(),
    brightness: Brightness.light,
    size: kVisualSize,
    beforeCapture: null,
  ),
  (
    slug: '02_alarm',
    title: '闹钟',
    build: (db) async => const HomeShell(),
    brightness: Brightness.light,
    size: kVisualSize,
    beforeCapture: (t) => _tapTab(t, Icons.alarm_outlined),
  ),
  (
    slug: '03_editor',
    title: '排班编辑器',
    build: (db) async =>
        ScheduleEditorScreen(scheduleId: await currentScheduleId(db)),
    brightness: Brightness.light,
    size: kVisualSize,
    beforeCapture: null,
  ),
  (
    slug: '04_todos',
    title: '待办',
    build: (db) async => const HomeShell(),
    brightness: Brightness.light,
    size: kVisualSize,
    beforeCapture: (t) => _tapTab(t, Icons.event_note_outlined),
  ),
  (
    slug: '05_ringing',
    title: '响铃界面',
    build: (db) async => const AlarmRingingScreen(label: '白班'),
    brightness: Brightness.light,
    size: kVisualSize,
    beforeCapture: null,
  ),
  (
    slug: '06_templates',
    title: '倒班方式模板',
    build: (db) async => const ShiftTemplatePickerScreen(),
    brightness: Brightness.light,
    size: kVisualSize,
    beforeCapture: null,
  ),
  (
    slug: '07_profile',
    title: '我的',
    build: (db) async => const HomeShell(),
    brightness: Brightness.light,
    size: kVisualSize,
    beforeCapture: (t) => _tapTab(t, Icons.person_outlined),
  ),
  (
    slug: '08_calendar_dark',
    title: '日历 · 深色',
    build: (db) async => const HomeShell(),
    brightness: Brightness.dark,
    size: kVisualSize,
    beforeCapture: null,
  ),
  (
    slug: '09_calendar_wide',
    title: '横屏 · 左右分栏',
    build: (db) async => const HomeShell(),
    brightness: Brightness.light,
    size: const Size(900, 420),
    beforeCapture: null,
  ),
  (
    // 权限卡在「我的」页的折叠线以下，直接拍首页拍不到它 —— 而它恰恰是
    // 国产 ROM 用户最在意的卖点（逐项自检 + 一键跳转）。
    slug: '10_profile_permissions',
    title: '我的 · 权限卡',
    build: (db) async => const HomeShell(),
    brightness: Brightness.light,
    size: kVisualSize,
    beforeCapture: (t) async {
      await _tapTab(t, Icons.person_outlined);
      // 等翻页动画停下来再拖：手势发在动画中间会被 PageView 吃掉。
      await settleVisual(t);
      await _scrollDown(t, 640);
    },
  ),
];

void main() {
  // 产物挪到 build/promo：kVisualOutDir 现在是变量，回归工装不受影响。
  kVisualOutDir = 'build/promo';

  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
    await ensureVisualFonts();
  });

  setUp(setUpVisualPrefs);

  for (final shot in _shots) {
    testWidgets(shot.title, (tester) async {
      failOnOverflow(tester);
      final db = await promoDatabase();
      addTearDown(db.close);
      await renderScreen(
        tester,
        name: shot.slug,
        home: await shot.build(db),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        brightness: shot.brightness,
        size: shot.size,
        extraPrefs: onboardingPrefs,
        beforeCapture: shot.beforeCapture,
      );
    });
  }
}
