// app/test/support/calendar_test_support.dart
//
// 日历页 widget 测试共用的夹具与 helper（原 calendar_screen_test.dart 前 233 行）。
//
// 五个必须一起搬的东西，动之前先读：
//   1. 每个用例文件都要自己调一次 `useFixedNow()`；
//   2. `pinNow` 的 tearDown 还原的是夹具锚点 `kAnchor`，不是 `DateTime.now`；
//   3. `pumpCalendar` 会写模块级 `liquidGlassActive`，tearDown 归 false；
//   4. `disposeCalendar` 不调会报「A Timer is still pending…」（drift 的 Timer.run）；
//   5. `setUpAll`（intl zh + drift 静音）与 `setUp`（prefs 清空）由各用例文件的 main 负责。
//
// ⚠️ 关于第 1 条，2026-11-06 实测过一件反直觉的事：**这 86 条里 `useFixedNow()` 是
//    ② 静默空转，不是保护伞。** 七个新文件把 `useFixedNow()` 全删掉，仍然 `+86` 全绿；
//    把原 `calendar_screen_test.dart` 里那唯一一处删掉、换回原文件跑，同样 `+86` 全绿。
//    也就是说这批用例根本不读时钟 —— 它们要的是「排班/网格的形状」，形状与真实日期无关。
//    调用保留（以后往里加日期敏感用例时它就是必需的），但**别把「每个文件都调了
//    useFixedNow」当成「时间已被钉住」的证据**：真正有鉴别力的只有 `setUpAll` 与
//    `disposeCalendar` 两处（各自改坏都会立刻转红）。
//
//    第 2 条那个 tearDown 是同一性质：把它改成 `DateTime.now` 仍 `+6` 全绿 —— 真正
//    每用例兜底的是 `fixed_clock.dart` 里的 `setUp`/`tearDown`（重新钉 `kAnchor`、
//    结束时还给真实时钟），不是这一句。规矩照旧（别改它），但别当它在守什么。
//
// ignore_for_file: unused_element — 这里的 helper 只被各用例文件按需调用，
// 库内自然「没有调用点」；逐个 rename 成公有会改掉用例体的表达式，所以留 ignore。

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/domain/lunar_info.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:shiftassistantpro/core/clock.dart';
import 'fixed_clock.dart';

ShiftTemplate templateOf(String id) =>
    shiftTemplates.firstWhere((t) => t.id == id);

/// 把「今天」临时钉到 [when]（用例结束时还原成夹具锚点 `kAnchor`）。
///
/// 这几条用例要的是**一个具体形状的月份**：那个月里有法定节假日，或者信息卡里
/// 装得下「本月统计」那一行。全局锚点一旦换到没有节假日的月份（比如 3 月），
/// 它们的前提就不成立了 —— 与其赌锚点正好是哪个月，不如用例自己把那个月点名要过来。
void pinNow(DateTime when) {
  appNow = () => when;
  addTearDown(() => appNow = () => kAnchor);
}
/// 色块 chip 的文本形状：`组名 简称`（例：`二班 休`）。

final chipPattern = RegExp(r'^[一二三四五六七八九]班 [早中夜休值晚]$');

/// 长按拖选用例圈住的那一段日子（闭区间 8…15）。
///
/// 锚点固定取每月的 8 日 / 15 日那两格，**不取「今天」**：今天可能落在网格的
/// 最后一行，往下拖就掉出本月（`_dateFromPosition` 返回 null），区间会只剩一天，
/// 用例于是随机某天转红。而 8 日 → 槽位 `leading + 7` → 网格第 1 行、15 日 →
/// 槽位 `leading + 14` → 第 2 行 —— 任何月份、任何月初偏移下都成立，两格永远
/// 相差一行（= 7 天），所以「往下拖一格」圈住的正是这 8 天。
const int rangeFirstDay = 8;
const int rangeLastDay = 15;
const int rangeSpan = rangeLastDay - rangeFirstDay + 1;

/// 找一个「往下拖一格、再往右越一格」都成立的起点：
/// ① 它右边还有同类格子（不在最后一列 —— 2026-02 的 8 日就是周日，往右拖直接出网格，
///    焦点不挪、末端不动，那是几何不是 bug）；
/// ② 它往后 8 天还在本月（末端才落得进网格）。
int dragStartDay(WidgetTester tester) {
  final int days = DateTime(appNow().year, appNow().month + 1, 0).day;
  Rect? rectOf(int d) {
    final Finder f = find.byKey(ValueKey('day-card-$d'));
    return f.evaluate().isEmpty ? null : tester.getRect(f);
  }

  for (int s = 1; s <= days - 8; s++) {
    final Rect? here = rectOf(s);
    final Rect? next = rectOf(s + 1);
    if (here == null || next == null) continue;
    if ((next.top - here.top).abs() > 0.5) continue; // s 在最后一列
    return s;
  }
  fail('这个月找不到可拖的起点 —— 网格行数或列数不对');
}

/// 玻璃块（选中滑块）当前的缩放：按住/拖拽时 1.22，松手后回到 1.0。
///
/// 用「块的祖先里的 `AnimatedScale`」定位，而不是 `find.byType(AnimatedScale)`：
/// 整页里不止这一处 `AnimatedScale`。
double blockScale(WidgetTester tester) => tester
    .widget<AnimatedScale>(find.ancestor(
      of: find.byKey(const Key('calendar-selection-block')),
      matching: find.byType(AnimatedScale),
    ))
    .scale;

/// 屏幕上还剩几格范围淡染 —— 只数 8…15 这 8 格，所以 `rangeSpan` 既表示
/// 「8 格都在」也表示「没有多画」。
int rangeTintCount(WidgetTester tester) {
  var n = 0;
  for (var d = rangeFirstDay; d <= rangeLastDay; d++) {
    if (tester.any(find.byKey(ValueKey('day-range-$d')))) n++;
  }
  return n;
}

List<String> chipTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where(chipPattern.hasMatch)
    .toList();

/// 信息卡「班次名 · 时间 · 闹钟」那一行的纯文本。
///
/// 三段并成了一段富文本（为了让省略号从尾部、也就是最不重要的闹钟开始截），
/// 所以整行内容要从 `textSpan` 上取，不能按独立 `Text` 去找。
String shiftLine(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('info-card-shift-line')))
    .textSpan!
    .toPlainText();

/// 造一套真库（内存）+ 一套当前排班，再渲染日历页。
///
/// 落库方式照抄 `createScheduleFromTemplatePicker`：模板提供
/// classes/cycle/班组数/偏移，班组名由创建路径按 teamCount 给满
/// （`L10n.defaultTeamNames`）—— 库出口的补位只是防御性兜底。
///
/// **注意**：`template.classes` 的班次名按 `L10n.locale` 生成，而这里是先
/// 落库再渲染。所以任何改动语言的用例都必须自己还原，否则漏出去的语言会
/// 让下一个用例存下另一种语言的班次名（英文名更长，可能把卡片挤溢出）。
///
/// [width] 是逻辑宽度。默认 420（窄屏手机），色块换行的场景用它；
/// 时间串的场景要给宽一点：测试字体每个字符都占满一个字身，英文的
/// `08:00 – 08:00 (next day)` 在测试里比真机宽得多，窄屏会被那个等宽字体
/// 挤出假溢出。
///
/// [blank] 造「跟随法定节假日（无班次）」那种空白表：形状照抄编辑器的
/// `_followHolidayCard`（周期为空 → `isBlank`，班组收敛成「我」一个人）。
Future<AppDatabase> pumpCalendar(WidgetTester tester, String templateId,
    {double width = 420,
    double height = 1600,
    bool blank = false,
    bool liquid = false}) async {
  final template = templateOf(templateId);

  // ⚠️ **液态档不能只靠模块级标志**：`appSettingsProvider._load()` 会拿 prefs 里的
  // `liquidGlass` 去 `recomputeGlassTiers()`（默认 false），先设标志的话会被它覆盖
  // 回去 —— 表现是「液态档那几条跑出来与标准档一模一样」。v0.10.1 与 v0.10.13 各踩过
  // 一次（都在出图上现形）。日历页读了那个 provider，所以 prefs 一定盖得住。
  //
  // ⚠️ **只在 liquid 时动 prefs**：非液态那几条里有依赖「调用方先设好 prefs」的
  // （英文界面那条就是），无条件重置会把它们冲掉。
  if (liquid) {
    SharedPreferences.setMockInitialValues(
        <String, Object>{'liquidGlass': true});
  }
  // 收尾拨回去：标志是模块级的，会漏到下一个用例。
  liquidGlassActive.value = liquid;
  addTearDown(() => liquidGlassActive.value = false);

  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  await AppRepository(db).saveSchedule(
    name: blank ? L10n.holidayScheduleName : template.subtitle,
    anchorDate: dateOnly(appNow()),
    classes: blank ? const [] : template.classes,
    cycle: blank ? const [] : template.cycle,
    makeCurrent: true,
    teamCount: blank ? 1 : template.teamCount,
    teamNames: blank
        ? [L10n.isEn ? 'Me' : '我']
        : L10n.defaultTeamNames(template.teamCount),
    ourTeamIndex: 0,
    teamOffsets: blank ? const [] : template.teamOffsets,
  );

  // 日历页的数据源是 databaseProvider（activeScheduleProvider 直接 watch 它），
  // 所以要换掉数据库本身，而不是 appRepositoryProvider。
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: CalendarScreen()),
  ));
  await tester.pumpAndSettle();
  return db;
}

/// 库里现有几套排班方案。
Future<int> scheduleCount(AppDatabase db) async =>
    (await db.select(db.shiftScheduleRows).get()).length;

/// 收尾：主动拆掉界面，并推一下时钟让 drift 取消查询流时排的那个零时长
/// 定时器真的跑掉。
///
/// 不这么做，框架会在测试体结束时自己拆树，随即报
/// 「A Timer is still pending even after the widget tree was disposed」
/// —— drift 的 `StreamQueryStore.markAsClosed` 用 `Timer.run` 延迟清理缓存。
Future<void> disposeCalendar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

/// 光晕走到哪一相位（0..1）。读的是 `_WavePainter.debugPhase`（`@visibleForTesting`）。
double glowPhase(WidgetTester tester) =>
    (tester
            .widget<CustomPaint>(find.byKey(const Key('flowing-background')))
            .painter! as dynamic)
        .debugPhase as double;

/// 推若干帧（一帧 16ms）。**不用 `pumpAndSettle`**：光晕那个定时器会一直调度下一帧。
Future<void> pumpFrames(WidgetTester tester, int frames) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// 顶栏的「下一月」圆钮。**别用 `find.byIcon`**：信息卡那一行也有一颗
/// chevron_right（v0.12.4 加的「点开调整班次」暗示，16dp），按图标找会 ambiguous。
/// 顶栏那两颗圆钮里的图标恒为 `iconMd`（20），按尺寸区分。
Finder nextMonth() => find.byWidgetPredicate((w) =>
    w is Icon &&
    w.icon == Icons.chevron_right_outlined &&
    w.size == AppTokens.iconMd);

// ---- 从 calendar_screen_test.dart 原位搬来的局部 helper（原为 main() 内函数）----

Future<DateTime> seekHolidayMonth(WidgetTester tester) async {
  final now = appNow();
  final start = DateTime(now.year, now.month, 1);
  for (var i = 0; i < 24; i++) {
    if (i > 0) {
      await tester.tap(nextMonth());
      await tester.pumpAndSettle();
    }
    final m = DateTime(start.year, start.month + i, 1);
    final days = DateTime(m.year, m.month + 1, 0).day;
    final has = List.generate(days, (k) => lunarOf(DateTime(m.year, m.month, k + 1)))
        .any((l) => l.isLegalHoliday);
    if (has) return m;
  }
  fail('两年内总该有一个月有法定节假日');
}

Future<bool> tapDay(WidgetTester tester, int day) async {
  await tester.tap(find.text('$day').first);
  await tester.pump();
  return find.byKey(const Key('info-card-month-tally')).evaluate().isNotEmpty;
}

Future<void> longPressDragCell(
    WidgetTester tester, int fromDay, int stepRows,
    {Future<void> Function()? midDrag}) async {
  final start = tester.getCenter(find.byKey(ValueKey('day-card-$fromDay')));
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 600)); // 过长按判定
  await gesture.moveBy(Offset(0, 60.0 * stepRows));      // 每 60 ≈ 一行
  await tester.pump();
  if (midDrag != null) await midDrag();
  await gesture.up();
  await tester.pumpAndSettle();
}
