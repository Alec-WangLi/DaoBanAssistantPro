// app/test/calendar_screen_test.dart
//
// 日历日详情卡片的界面行为测试：
//   - 「其他班组」从一整行文字改成色块列表（6 班组场景不溢出）
//   - 跨午夜班次的时间走 L10n.timeRange，英文界面下不露出中文
//
// 本机没有可运行目标（无 Android 设备 / 无 VS 工具链 / web 被本地通知插件挡住），
// 所以界面行为全部靠 widget 测试覆盖。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

ShiftTemplate _template(String id) =>
    shiftTemplates.firstWhere((t) => t.id == id);

/// 色块 chip 的文本形状：`组名 简称`（例：`二班 休`）。
final _chipPattern = RegExp(r'^[一二三四五六七八九]班 [早中夜休值晚]$');

List<String> _chipTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where(_chipPattern.hasMatch)
    .toList();

/// 造一套真库（内存）+ 一套当前排班，再渲染日历页。
///
/// 落库方式照抄 `schedule_management_screen.dart` 的 `_addSchedule`：
/// 模板只提供 classes/cycle/班组数/偏移，班组名沿用默认的四班名 ——
/// 多出来的班组由 `ActiveSchedule.toDomain()` 补位（否则消费方按 teamCount
/// 索引会越界，正是这次要适配的场景）。
///
/// [width] 是逻辑宽度。默认 420（窄屏手机），色块换行的场景用它；
/// 时间串的场景要给宽一点：测试字体每个字符都占满一个字身，英文的
/// `08:00 – 08:00 (next day)` 在测试里比真机宽得多，窄屏会被那个等宽字体
/// 挤出假溢出。
Future<void> _pumpCalendar(WidgetTester tester, String templateId,
    {double width = 420}) async {
  final template = _template(templateId);

  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  await AppRepository(db).saveSchedule(
    name: template.subtitle,
    anchorDate: dateOnly(DateTime.now()),
    classes: template.classes,
    cycle: template.cycle,
    makeCurrent: true,
    teamCount: template.teamCount,
    teamNames: defaultSchedule().teamNames,
    ourTeamIndex: 0,
    teamOffsets: template.teamOffsets,
  );

  // 日历页的数据源是 databaseProvider（activeScheduleProvider 直接 watch 它），
  // 所以要换掉数据库本身，而不是 appRepositoryProvider。
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: CalendarScreen()),
  ));
  await tester.pumpAndSettle();
}

/// 收尾：主动拆掉界面，并推一下时钟让 drift 取消查询流时排的那个零时长
/// 定时器真的跑掉。
///
/// 不这么做，框架会在测试体结束时自己拆树，随即报
/// 「A Timer is still pending even after the widget tree was disposed」
/// —— drift 的 `StreamQueryStore.markAsClosed` 用 `Timer.run` 延迟清理缓存。
Future<void> _disposeCalendar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  setUpAll(() async {
    // L10n.yearMonth 用 intl DateFormat('zh')，测试里要自己初始化。
    await initializeDateFormatting('zh');
    // 每个测试各建一个内存库做隔离，drift 会为「同名库建了多次」刷警告，这里静音。
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  // 语言从 SharedPreferences 读；默认不写 key → 'zh'。
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('六班三倒（6 个班组）：其他班组渲染 5 个色块，不再拼成一整行',
      (tester) async {
    // 窄屏：6 个色块必须换行，而不是把卡片撑破。
    await _pumpCalendar(tester, 'six_crew_three_shift');

    expect(find.text(L10n.otherCrews), findsOneWidget);

    // 我们是第 1 组 → 剩下 5 组各一个色块（休班的组也要列出）
    final chips = _chipTexts(tester);
    expect(chips, hasLength(5), reason: '6 个班组应当出 5 个色块');
    expect(chips.toSet(), hasLength(5), reason: '每个班组一个色块');
    // 一班是「我」，不该出现；五班/六班的名字来自 toDomain 的补位
    expect(chips.map((c) => c.split(' ').first).toSet(),
        {'二班', '三班', '四班', '五班', '六班'});

    // 旧的「一整行文字」形状：`其他班组：组名·班次名　…` 已不复存在
    expect(find.textContaining('${L10n.otherCrews}：'), findsNothing);

    // 窄屏 + 换行布局：不应有 RenderFlex overflow
    expect(tester.takeException(), isNull);

    await _disposeCalendar(tester);
  });

  testWidgets('上 24 休 48：值班当天时间走 L10n，中文界面显示「次日」',
      (tester) async {
    await _pumpCalendar(tester, 'duty_24_48', width: 640);

    expect(L10n.isEn, isFalse);
    expect(find.text('08:00 – 次日08:00'), findsOneWidget);

    await _disposeCalendar(tester);
  });

  testWidgets('上 24 休 48 英文界面：时间用 (next day) 且不露出中文',
      (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await _pumpCalendar(tester, 'duty_24_48', width: 640);

    expect(L10n.isEn, isTrue, reason: '语言应当已从设置里读成 en');
    final time = find.text('08:00 – 08:00 (next day)');
    expect(time, findsOneWidget);

    // 时间这一条里不能有中文（旧实现硬编码「次日」就会漏出来）
    final rendered = tester.widget<Text>(time).data!;
    expect(RegExp(r'[一-鿿]').hasMatch(rendered), isFalse);
    expect(find.textContaining('次日'), findsNothing);

    await _disposeCalendar(tester);
  });

  testWidgets('单班组排班：不渲染「其他班组」那一段', (tester) async {
    await _pumpCalendar(tester, 'standard_week');

    expect(find.text(L10n.otherCrews), findsNothing);
    expect(_chipTexts(tester), isEmpty);

    await _disposeCalendar(tester);
  });
}
