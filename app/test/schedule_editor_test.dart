// app/test/schedule_editor_test.dart
//
// 排班编辑器（班次定义 + 周期表 + 班组起始日）的界面行为测试。
//
// 本机没有可运行目标（无 Android 设备 / 无 VS 工具链 / web 被本地通知插件挡住），
// 所以界面行为全部靠 widget 测试覆盖。
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_choice_chip.dart';
import 'package:shiftassistantpro/core/widgets/glass_delete_button.dart';
import 'package:shiftassistantpro/core/widgets/glass_dialog.dart';
import 'package:shiftassistantpro/core/widgets/glass_pressable.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/calendar/schedule_editor_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 记录一次 saveSchedule 调用，便于断言「落库的到底是什么形状」。
class _Saved {
  _Saved({
    required this.name,
    required this.anchorDate,
    required this.classes,
    required this.cycle,
    required this.teamCount,
    required this.teamNames,
    required this.ourTeamIndex,
    required this.teamOffsets,
  });

  final String name;
  final DateTime anchorDate;
  final List<ShiftClass> classes;
  final List<int> cycle;
  final int teamCount;
  final List<String> teamNames;
  final int ourTeamIndex;
  final List<int> teamOffsets;
}

class _FakeRepository extends AppRepository {
  _FakeRepository(super.db, this.domain, {this.active});

  final ShiftSchedule domain;

  /// 库里的「当前方案」。与 [domain]（正在编辑的那套）不同时，用来验证
  /// 保存后重排闹钟用的是当前方案，而不是编辑器手里这套。
  final ShiftSchedule? active;

  _Saved? saved;

  @override
  Future<ShiftSchedule?> getScheduleDomain(int id) async => domain;

  @override
  Future<ShiftSchedule?> getActiveSchedule() async => active ?? domain;

  @override
  Future<int> saveSchedule({
    int? scheduleId,
    required String name,
    required DateTime anchorDate,
    required List<ShiftClass> classes,
    required List<int> cycle,
    bool makeCurrent = true,
    int teamCount = 4,
    List<String> teamNames = const ['一班', '二班', '三班', '四班'],
    int ourTeamIndex = 0,
    List<int> teamOffsets = const [],
  }) async {
    saved = _Saved(
      name: name,
      anchorDate: anchorDate,
      classes: List.of(classes),
      cycle: List.of(cycle),
      teamCount: teamCount,
      teamNames: List.of(teamNames),
      ourTeamIndex: ourTeamIndex,
      teamOffsets: List.of(teamOffsets),
    );
    return 7;
  }

  @override
  Future<List<CustomAlarm>> listCustomAlarms() async => const [];

  @override
  Future<Map<int, bool>> listShiftAlarmOverrides() async => const {};
}

ShiftSchedule _domain({
  List<ShiftClass>? classes,
  List<int>? cycle,
  DateTime? anchor,
  List<int>? teamOffsets,
  Map<int, int>? dayOverrides,
  int teamCount = 4,
  List<String>? teamNames,
}) {
  return ShiftSchedule(
    dayOverrides: dayOverrides ?? const {},
    name: '测试排班',
    anchorDate: anchor ?? DateTime.utc(2025, 6, 1),
    classes: classes ??
        const [
          ShiftClass(
              name: '白班',
              abbr: '白',
              startMinute: 8 * 60 + 30,
              endMinute: 20 * 60 + 30,
              color: 0xFF4C8DFF),
          ShiftClass(
              name: '夜班',
              abbr: '夜',
              startMinute: 20 * 60 + 30,
              endMinute: 8 * 60 + 30,
              color: 0xFF7A5CFF),
          ShiftClass(name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4),
        ],
    cycle: cycle ?? const [0, 0, 1, 1, 2, 2],
    teamCount: teamCount,
    teamNames: teamNames ?? L10n.defaultTeamNames(teamCount),
    ourTeamIndex: 0,
    teamOffsets: teamOffsets ?? const [0, 1, 2, 3],
  );
}

/// 只有一个非休息班次 + 一个休班的方案：页面上只有一条「结束」时间行。
ShiftSchedule _oneShift(ShiftClass c) => _domain(
      classes: [c, const ShiftClass(name: '休息', abbr: '休', isRest: true)],
      cycle: const [0, 1],
    );

/// 24 小时值班：08:00 → 次日 08:00（Task 1 把分钟域扩到 2880 的起因）。
const _duty24 = ShiftClass(
    name: '值班',
    abbr: '值',
    startMinute: 8 * 60,
    endMinute: 32 * 60,
    color: 0xFFFF375F);

/// 中班：16:00 → 24:00（endMinute 恰好 1440）。
const _mid24 = ShiftClass(
    name: '中班',
    abbr: '中',
    startMinute: 16 * 60,
    endMinute: 24 * 60,
    color: 0xFFFF9F0A);

/// 从一个宿主页 push 编辑器（这样保存后的 pop 有地方可回）。
Future<_FakeRepository> _pumpEditor(
  WidgetTester tester,
  ShiftSchedule domain, {
  ShiftSchedule? active,
}) async {
  // 编辑器是一整页长列表：给足高度，让周期里的每一行都真的被构建出来，
  // 否则 ListView 只会懒构建视口内的那几行，find 就找不到。
  tester.view.physicalSize = const Size(900, 4600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);
  final repo = _FakeRepository(db, domain, active: active);

  await tester.pumpWidget(ProviderScope(
    overrides: [appRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute(
                    builder: (_) => const ScheduleEditorScreen(scheduleId: 7)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

Finder _minus() => find.widgetWithIcon(
    IconButton, Icons.remove_circle_outline_outlined);

/// 点删除并在确认框里确认。
///
/// 未被周期引用的班次会走这条路；被引用的那条由 [_deleteClass] 直接拦下，
/// 根本不弹确认框，所以这里不覆盖。
Future<void> _tapDeleteAndConfirm(
    WidgetTester tester, Finder deleteButton) async {
  await tester.tap(deleteButton);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(
    of: find.byType(GlassDialog),
    matching: find.text(L10n.delete),
  ));
  await tester.pumpAndSettle();
}
Finder _plus() =>
    find.widgetWithIcon(IconButton, Icons.add_circle_outline_outlined);

/// 某个时间块（按标签文字找）当前显示的值文本。
///
/// 时间块的结构是 `GlassPressable ▸ 标签 Text + 值 Text`，所以取该块内
/// 最后一个 Text；标签文案在整页里唯一，不会找错块。
String _chipValueOf(WidgetTester tester, String label) {
  final texts = tester.widgetList<Text>(find.descendant(
    of: find.ancestor(
        of: find.text(label), matching: find.byType(GlassPressable)),
    matching: find.byType(Text),
  ));
  return texts.last.data!;
}

/// 顶部「我这组从这个周期开始」那一行里显示的日期。
String _myCrewStartText(WidgetTester tester) {
  final texts = tester.widgetList<Text>(find.descendant(
    of: find.ancestor(
        of: find.text(L10n.myCycleStart), matching: find.byType(InkWell)),
    matching: find.byType(Text),
  ));
  return texts.last.data!;
}

/// 点开顶部「我这组从这个周期开始」的日期选择器。
Future<void> _tapMyCrewStart(WidgetTester tester) async {
  await tester.tap(find.ancestor(
      of: find.text(L10n.myCycleStart), matching: find.byType(InkWell)));
  await tester.pumpAndSettle();
}

// -----------------------------------------------------------------------------
// 顶部预览条（未来 14 天）
// -----------------------------------------------------------------------------

/// 预览条那个 GlassTile。
Finder _strip() => find.widgetWithText(GlassTile, L10n.previewNext14);

List<String> _stripTexts(WidgetTester tester) => tester
    .widgetList<Text>(
        find.descendant(of: _strip(), matching: find.byType(Text)))
    .map((t) => t.data ?? '')
    .toList();

/// 预览条 14 格的班次简称。第 0 项是标题，之后每格两项（日期 + 简称）。
List<String> _cellLabels(WidgetTester tester) {
  final texts = _stripTexts(tester);
  return [for (var i = 0; i < 14; i++) texts[2 + 2 * i]];
}

/// 预览条 14 格的日期文本（`M/D`），按格子顺序。
List<String> _cellDates(WidgetTester tester) => _stripTexts(tester)
    .where((s) => RegExp(r'^\d{1,2}/\d{1,2}$').hasMatch(s))
    .toList();

/// 用真引擎算出的「未来 14 天简称」，作为预览条断言的参照（而不是在测试里
/// 重算一遍 mod 周期）。
List<String> _expectedLabels(ShiftSchedule d) {
  final today = dateOnly(DateTime.now());
  return [
    for (var i = 0; i < 14; i++)
      d.shiftOn(today.add(Duration(days: i)))?.shortLabel ?? '—',
  ];
}

void main() {
  // L10n.yearMonthDay / yearMonth 用 intl DateFormat('zh')，测试里要自己初始化。
  setUpAll(() async {
    await initializeDateFormatting('zh');
  });

  testWidgets('周期长度步进器：−/+ 改变行数，到 1 与 60 时对应按钮置灰',
      (tester) async {
    await _pumpEditor(tester, _domain(cycle: const [0, 0, 1, 1, 2, 2]));

    expect(find.text(L10n.dayN(6)), findsOneWidget);
    expect(find.text(L10n.dayN(7)), findsNothing);

    // + 变长
    await tester.tap(_plus());
    await tester.pumpAndSettle();
    expect(find.text(L10n.dayN(7)), findsOneWidget);
    expect(find.text(L10n.dayN(8)), findsNothing);

    // 一路减到 1 天，- 置灰
    for (var i = 0; i < 6; i++) {
      await tester.tap(_minus());
      await tester.pumpAndSettle();
    }
    expect(find.text(L10n.dayN(1)), findsOneWidget);
    expect(find.text(L10n.dayN(2)), findsNothing);
    expect(tester.widget<IconButton>(_minus()).onPressed, isNull);
    expect(tester.widget<IconButton>(_plus()).onPressed, isNotNull);
  });

  testWidgets('周期长度上限 60：到顶后 + 置灰，减一次又可用', (tester) async {
    await _pumpEditor(
        tester, _domain(cycle: List.generate(59, (i) => i % 3)));

    await tester.tap(_plus());
    await tester.pumpAndSettle();
    expect(find.text(L10n.dayN(60)), findsOneWidget);
    expect(tester.widget<IconButton>(_plus()).onPressed, isNull);

    await tester.tap(_minus());
    await tester.pumpAndSettle();
    expect(find.text(L10n.dayN(60)), findsNothing);
    expect(tester.widget<IconButton>(_plus()).onPressed, isNotNull);
  });

  testWidgets('周期某天换成别的班次后，该行右侧时间文本跟着变', (tester) async {
    // 第 1 天引用白班，另外两天都是休班 —— 这样「夜班」的时间文本只会出现一次
    await _pumpEditor(tester, _domain(cycle: const [0, 2, 2]));

    // 第 1 天引用白班（08:30–20:30）
    expect(find.text('08:30 – 20:30'), findsOneWidget);

    // 第 1 天的 chip 换成「夜班」（下标 1）
    await tester.tap(find.byKey(cycleChipKey(0, 1)));
    await tester.pumpAndSettle();

    expect(find.text('08:30 – 20:30'), findsNothing);
    expect(find.text('20:30 – 次日08:30'), findsOneWidget);
  });

  testWidgets('改「白班」的开始时间，周期里所有引用白班的行同步变', (tester) async {
    // 只留「白班 + 休班」两个定义，页面上就只有一个「开始」时间条目
    await _pumpEditor(
      tester,
      _domain(
        classes: const [
          ShiftClass(
              name: '白班',
              abbr: '白',
              startMinute: 8 * 60 + 30,
              endMinute: 20 * 60 + 30,
              color: 0xFF4C8DFF),
          ShiftClass(name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4),
        ],
        cycle: const [0, 0, 1],
      ),
    );
    expect(find.text('08:30 – 20:30'), findsNWidgets(2));

    final before = _chipValueOf(tester, L10n.start);
    expect(before, '08:30');

    // 点开班次定义里的「开始」，把小时轮往下拨
    await tester.tap(find.text(L10n.start));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CupertinoPicker).first, const Offset(0, 80));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();

    final after = _chipValueOf(tester, L10n.start);
    expect(after, isNot(before), reason: '时间选择器应当真的改了开始时间');

    // 两行引用白班的周期行同时更新，且旧时间消失
    expect(find.text('08:30 – 20:30'), findsNothing);
    expect(find.text('$after – 20:30'), findsNWidgets(2));
  });

  testWidgets('删除仍被引用的班次定义被拦下，未被引用的可以删', (tester) async {
    // 休班（下标 2）没有被周期引用
    await _pumpEditor(tester, _domain(cycle: const [0, 1, 1]));
    expect(find.byType(GlassDeleteButton), findsNWidgets(3));

    // 删被引用的「白班」→ 拦下并提示
    await tester.tap(find.byType(GlassDeleteButton).at(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text(L10n.deleteShiftClassInUse.replaceAll('{n}', '1')),
      findsOneWidget,
    );
    expect(find.byType(GlassDeleteButton), findsNWidgets(3),
        reason: '被拦下时不能真的删掉定义');

    // 让提示条自己消失，清掉它的定时器
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // 周期没有被静默改掉
    expect(find.text(L10n.dayN(3)), findsOneWidget);

    // 删没被引用的「休班」→ 确认后成功
    await _tapDeleteAndConfirm(
        tester, find.byType(GlassDeleteButton).at(2));
    expect(find.byType(GlassDeleteButton), findsNWidgets(2));
    expect(find.text(L10n.dayN(3)), findsOneWidget);
  });

  testWidgets('打开「跟随法定节假日」后班次与周期清空', (tester) async {
    final repo = await _pumpEditor(tester, _domain(cycle: const [0, 1, 2]));
    expect(find.byType(GlassDeleteButton), findsNWidgets(3));
    expect(find.text(L10n.dayN(3)), findsOneWidget);

    final sw = find.descendant(
      of: find.widgetWithText(GlassTile, L10n.followHoliday),
      matching: find.byType(GlassSwitch),
    );
    await tester.tap(sw);
    await tester.pumpAndSettle();

    // 班次设置与周期设置整段收起
    expect(find.byType(GlassDeleteButton), findsNothing);
    expect(find.text(L10n.dayN(1)), findsNothing);

    // 落库的就是空白表（classes / cycle 都为空）
    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();
    expect(repo.saved, isNotNull);
    expect(repo.saved!.classes, isEmpty);
    expect(repo.saved!.cycle, isEmpty);
  });

  testWidgets('保存写入两层形状的 classes + cycle（不再是旧的一天一班）',
      (tester) async {
    final repo = await _pumpEditor(tester, _domain(cycle: const [0, 0, 1, 1, 2, 2]));

    // 周期 6 → 7 天，新一天沿用最后一天的班次
    await tester.tap(_plus());
    await tester.pumpAndSettle();

    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();

    final saved = repo.saved!;
    expect(saved.cycle, [0, 0, 1, 1, 2, 2, 2]);
    expect(saved.classes.map((c) => c.name), ['白班', '夜班', '休班']);
    expect(saved.anchorDate, DateTime.utc(2025, 6, 1));
  });

  testWidgets('改「我这组从这个周期开始」→ 基准日整体平移，班组相对错位不变',
      (tester) async {
    final repo = await _pumpEditor(
      tester,
      _domain(anchor: DateTime.utc(2025, 6, 1), teamOffsets: const [0, 1, 2, 3]),
    );
    expect(find.text(L10n.yearMonthDay(DateTime.utc(2025, 6, 1))),
        findsOneWidget);

    await _tapMyCrewStart(tester);
    await tester.tap(find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('10'),
    ));
    await tester.pumpAndSettle();

    expect(find.text(L10n.yearMonthDay(DateTime.utc(2025, 6, 10))),
        findsOneWidget);

    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();

    expect(repo.saved!.anchorDate, DateTime.utc(2025, 6, 10));
    // 各班组相对错位保持不变（否则整个日历会多平移一份）
    expect(repo.saved!.teamOffsets, [0, 1, 2, 3]);
  });

  testWidgets('添加班次：新增一条定义，周期里没引用所以可以删掉', (tester) async {
    await _pumpEditor(tester, _domain(cycle: const [0, 0, 1, 1, 2, 2]));
    expect(find.byType(GlassDeleteButton), findsNWidgets(3));

    await tester.tap(find.text(L10n.addShiftClass));
    await tester.pumpAndSettle();
    expect(find.byType(GlassDeleteButton), findsNWidgets(4));

    // 周期没引用新班次 → 确认后删除成功
    await _tapDeleteAndConfirm(
        tester, find.byType(GlassDeleteButton).at(3));
    expect(find.byType(GlassDeleteButton), findsNWidgets(3));
  });

  testWidgets('把班次切成休息：时间被清空，周期里引用它的行显示「休息」',
      (tester) async {
    await _pumpEditor(
      tester,
      _domain(
        classes: const [
          ShiftClass(
              name: '白班',
              abbr: '白',
              startMinute: 8 * 60 + 30,
              endMinute: 20 * 60 + 30,
              color: 0xFF4C8DFF),
          ShiftClass(name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4),
        ],
        cycle: const [0, 1],
      ),
    );

    expect(find.text('08:30 – 20:30'), findsOneWidget);
    expect(
        find.descendant(
            of: find.widgetWithText(GlassTile, L10n.shiftClasses),
            matching: find.text(L10n.start)),
        findsOneWidget);

    final classSegments = find.descendant(
      of: find.widgetWithText(GlassTile, L10n.shiftClasses),
      matching: find.text(L10n.rest),
    );
    await tester.tap(classSegments.first);
    await tester.pumpAndSettle();

    // 时间块整段消失 —— copyWith 清不掉可空字段，这里是直接构造的新班次
    expect(
        find.descendant(
            of: find.widgetWithText(GlassTile, L10n.shiftClasses),
            matching: find.text(L10n.start)),
        findsNothing);
    expect(find.text('08:30 – 20:30'), findsNothing);
    // 周期里引用它的两行都变成「休息」
    expect(
        find.descendant(
            of: find.widgetWithText(GlassTile, L10n.cycleSection),
            matching: find.text(L10n.rest)),
        findsNWidgets(2));
  });

  testWidgets('周期长度与班组数是两个彼此独立的步进器', (tester) async {
    await _pumpEditor(tester, _domain(cycle: const [0, 0, 1, 1, 2, 2]));
    expect(find.text(L10n.dayN(6)), findsOneWidget);

    // 展开「班组设置」
    await tester.tap(find.text(L10n.crewSettingsOptional));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.event_outlined), findsNWidgets(4));

    // 班组 +1：只多一个班组，周期长度不动
    await tester.tap(_plus().last);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.event_outlined), findsNWidgets(5));
    expect(find.text(L10n.dayN(6)), findsOneWidget);
    expect(find.text(L10n.dayN(7)), findsNothing);

    // 周期 +1：轮到周期步进器，班组数不动
    await tester.tap(_plus().first);
    await tester.pumpAndSettle();
    expect(find.text(L10n.dayN(7)), findsOneWidget);
    expect(find.byIcon(Icons.event_outlined), findsNWidgets(5));
  });

  testWidgets('点「设为我」选中其他班组后，顶部显示日期与该班组行一致',
      (tester) async {
    await _pumpEditor(
      tester,
      _domain(anchor: DateTime.utc(2025, 6, 1), teamOffsets: const [0, 1, 2, 3]),
    );
    // 初始我这一组 = 0，顶部显示基准日
    expect(_myCrewStartText(tester),
        L10n.yearMonthDay(DateTime.utc(2025, 6, 1)));

    // 展开班组设置，把第 3 组（下标 2）设为「我」
    await tester.tap(find.text(L10n.crewSettingsOptional));
    await tester.pumpAndSettle();
    expect(find.text(L10n.setAsMine), findsNWidgets(3));
    await tester.tap(find.text(L10n.setAsMine).at(1));
    await tester.pumpAndSettle();

    // 我这一组的起始日 = 基准日 − offsets[2] = 06-01 − 2 天 = 05-30
    final expected = L10n.yearMonthDay(DateTime.utc(2025, 5, 30));
    expect(_myCrewStartText(tester), expected,
        reason: '顶部必须读我这一组的起始日，而不是基准日');
    // 班组区里该组的「周期起始日」显示同一日期 → 两处一致（修前这里是 0 处）
    expect(find.text(expected), findsNWidgets(2));
    // 顶部不再显示基准日，只剩第 1 组那行「周期起始日」还显示它
    expect(find.text(L10n.yearMonthDay(DateTime.utc(2025, 6, 1))),
        findsOneWidget);
  });

  testWidgets('改顶部起始日后，新日期的班次是周期第 1 天，且各组相对错位不变',
      (tester) async {
    final repo = await _pumpEditor(
      tester,
      _domain(anchor: DateTime.utc(2025, 6, 1), teamOffsets: const [0, 1, 2, 3]),
    );

    // 先把第 3 组（下标 2）设为「我」——这步只改 _ourTeamIndex、不动偏移，
    // 于是我的基线偏移 = offsets[2] = 2，重锚定时必须扣掉它。
    await tester.tap(find.text(L10n.crewSettingsOptional));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.setAsMine).at(1));
    await tester.pumpAndSettle();

    const before = [0, 1, 2, 3];

    // 顶部选择器现在打开在我这一组的起始日（05-30），点 10 号 → 2025-05-10
    await _tapMyCrewStart(tester);
    await tester.tap(find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('10'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();

    final saved = repo.saved!;
    final newDate = DateTime.utc(2025, 5, 10);
    expect(saved.anchorDate, newDate);

    // 我的基线偏移归零，其余偏移整体减去它 → [-2,-1,0,1]
    expect(saved.teamOffsets, [-2, -1, 0, 1]);

    // 各班组两两错位与改之前完全相同
    for (var i = 0; i < before.length; i++) {
      for (var j = 0; j < before.length; j++) {
        expect(saved.teamOffsets[i] - saved.teamOffsets[j],
            before[i] - before[j],
            reason: '第 $i 组与第 $j 组的相对错位不该变');
      }
    }

    // 我的班组在新起始日恰好处于周期第 0 项
    final sched = ShiftSchedule(
      name: saved.name,
      anchorDate: saved.anchorDate,
      classes: saved.classes,
      cycle: saved.cycle,
      teamCount: saved.teamCount,
      teamNames: saved.teamNames,
      ourTeamIndex: saved.ourTeamIndex,
      teamOffsets: saved.teamOffsets,
    );
    expect(sched.shiftOn(newDate), saved.classes[saved.cycle[0]]);
  });

  testWidgets('预览条：从今天起渲染 14 格，简称与引擎算出来的一致', (tester) async {
    final domain = _domain(cycle: const [0, 1, 2, 2]);
    await _pumpEditor(tester, domain);

    expect(find.text(L10n.previewNext14), findsOneWidget);

    final today = dateOnly(DateTime.now());
    final expectedDates = List.generate(14, (i) {
      final d = today.add(Duration(days: i));
      return '${d.month}/${d.day}';
    });
    expect(_cellDates(tester), expectedDates,
        reason: '14 格应当从今天起逐日排列');
    expect(_cellLabels(tester), _expectedLabels(domain));
  });

  testWidgets('改周期里某天引用的班次，预览条对应格子跟着变', (tester) async {
    final domain = _domain(cycle: const [0, 1, 2, 2]);
    await _pumpEditor(tester, domain);
    final before = _cellLabels(tester);
    expect(before, _expectedLabels(domain));

    // 第 1 天从「白班」改成「夜班」（下标 1）
    await tester.tap(find.byKey(cycleChipKey(0, 1)));
    await tester.pumpAndSettle();

    final after = _cellLabels(tester);
    expect(after, _expectedLabels(_domain(cycle: const [1, 1, 2, 2])));
    expect(after, isNot(equals(before)), reason: '换了班次，预览必须真的变');
  });

  testWidgets('改「我的班组起始日」→ 整条预览往前移一格', (tester) async {
    await _pumpEditor(
      tester,
      _domain(anchor: DateTime.utc(2025, 6, 1), cycle: const [0, 1, 2, 2]),
    );
    final before = _cellLabels(tester);
    expect(before.toSet().length, greaterThan(1), reason: '一片相同的班次测不出移位');

    // 起始日 06-01 → 06-02（基准日 +1 天）
    await _tapMyCrewStart(tester);
    await tester.tap(find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('2'),
    ));
    await tester.pumpAndSettle();
    expect(_myCrewStartText(tester),
        L10n.yearMonthDay(DateTime.utc(2025, 6, 2)));

    final after = _cellLabels(tester);
    // 基准日 +1 → 每格的周期下标 −1，于是第 i 格显示原来的第 i−1 格
    expect(after.sublist(1), before.sublist(0, 13));
    expect(after, isNot(equals(before)));
  });

  testWidgets('空白表（跟随法定节假日）预览条 14 格全显示 —', (tester) async {
    await _pumpEditor(tester, _domain(cycle: const [0, 1, 2, 2]));
    expect(_cellLabels(tester).contains('—'), isFalse);

    final sw = find.descendant(
      of: find.widgetWithText(GlassTile, L10n.followHoliday),
      matching: find.byType(GlassSwitch),
    );
    await tester.tap(sw);
    await tester.pumpAndSettle();

    expect(_cellDates(tester), hasLength(14), reason: '空白表也要有 14 格');
    expect(_cellLabels(tester), List.filled(14, '—'));
  });

  test('L10n.timeRange：英文界面下不露出「次日」', () {
    final prev = L10n.locale;
    addTearDown(() => L10n.locale = prev);

    L10n.locale = 'zh';
    expect(L10n.timeRange('20:30', '08:30', true), '20:30 – 次日08:30');
    expect(L10n.timeRange('08:30', '20:30', false), '08:30 – 20:30');

    L10n.locale = 'en';
    final en = L10n.timeRange('20:30', '08:30', true);
    expect(en, '20:30 – 08:30 (next day)');
    expect(en.contains('次日'), isFalse);
    expect(L10n.timeRange('08:30', '20:30', false), '08:30 – 20:30');
  });

  // ---------------------------------------------------------------------------
  // C1：编辑器必须能表达 endMinute >= 1440（24 小时值班 / 中班 24:00）
  //
  // 分钟域在 Task 1 扩到了 2880，但编辑器的时间行一度仍假设 0..1439：
  // 显示上 1920 被 formatClock 静默回绕成 08:00，选择器上 hour=32 越出
  // 00..23 的滚轮 → 用户一确认，24 小时值班就被静默降级成当天结束。
  // ---------------------------------------------------------------------------

  testWidgets('值班（08:00–次日08:00）：结束时间选择器停在 08:00，确认后仍是 1920',
      (tester) async {
    final repo = await _pumpEditor(tester, _oneShift(_duty24));

    await tester.tap(find.text(L10n.end));
    await tester.pumpAndSettle();

    // 小时滚轮必须停在钟面值 08，而不是越界的 32（越界时轮子会被夹到 23，
    // 用户一确认就把 24 小时值班改成了 23:00）
    final wheels = tester
        .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
        .toList();
    expect(wheels, hasLength(2), reason: '时、分两个滚轮');
    expect(
      (wheels[0].scrollController as FixedExtentScrollController).initialItem,
      8,
      reason: '结束时间是 1920 → 钟面 08:00，滚轮初始位置必须是 8',
    );

    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();

    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();

    expect(repo.saved!.classes.first.endMinute, 1920,
        reason: '原样确认不该改动 24 小时值班的结束时间');
  });

  testWidgets('值班的结束时间在班次设置里显示「次日08:00」，而不是被回绕成 08:00',
      (tester) async {
    await _pumpEditor(tester, _oneShift(_duty24));

    expect(_chipValueOf(tester, L10n.end), '${L10n.nextDay}08:00');
    expect(_chipValueOf(tester, L10n.end), '次日08:00');
    // 同一屏的周期行也得说同一件事：08:00 – 次日08:00
    expect(find.text('08:00 – 次日08:00'), findsOneWidget);
    expect(_chipValueOf(tester, L10n.start), '08:00');
  });

  testWidgets('中班（16:00–24:00）：显示 24:00，滚轮停在 00 且确认后仍是 1440',
      (tester) async {
    final repo = await _pumpEditor(tester, _oneShift(_mid24));

    // 1440 与「次日 00:00」是同一时刻；这里与周期行、日历一致地写成 24:00
    expect(_chipValueOf(tester, L10n.end), '24:00');
    expect(find.text('16:00 – 24:00'), findsOneWidget);

    await tester.tap(find.text(L10n.end));
    await tester.pumpAndSettle();
    final wheels = tester
        .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
        .toList();
    expect(
      (wheels[0].scrollController as FixedExtentScrollController).initialItem,
      0,
    );
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();

    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();

    expect(repo.saved!.classes.first.endMinute, 1440,
        reason: '中班的 24:00 不能被降级成 00:00');
  });

  testWidgets('上夜班（20:30–次日08:30）：靠 e < s 跨午夜，确认后不被抬高到 1440 以上',
      (tester) async {
    const night = ShiftClass(
        name: '上夜班',
        abbr: '夜',
        startMinute: 20 * 60 + 30,
        endMinute: 8 * 60 + 30);
    final repo = await _pumpEditor(tester, _oneShift(night));

    expect(_chipValueOf(tester, L10n.end), '次日08:30');

    await tester.tap(find.text(L10n.end));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();

    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();

    expect(repo.saved!.classes.first.endMinute, 8 * 60 + 30);
  });

  // ---------------------------------------------------------------------------
  // I1：保存后重排必须用「当前方案」，不能用刚编辑的这套
  // ---------------------------------------------------------------------------

  testWidgets('保存一套非当前方案后，重排闹钟用的是当前方案', (tester) async {
    // 两个通道都要接住：settings 是我们自己的原生通道，local_notifications
    // 是 flutter_local_notifications 的 —— 后者没接住的话 cancelAll 在测试
    // 环境里永远不会完成，后面的排定循环根本不会跑。
    const settings = MethodChannel('com.daoban.shiftassistantpro/settings');
    const notifications =
        MethodChannel('dexterous.com/flutter/local_notifications');
    final labels = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(settings, (call) async {
      if (call.method == 'scheduleNativeAlarm') {
        labels.add(((call.arguments as Map)['label']) as String);
      }
      return null;
    });
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (call) async => null);
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(settings, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(notifications, null);
    });

    // 闹钟时间取 23:59，保证未来 60 天里至少排得进一条。
    const at2359 = 23 * 60 + 59;
    ShiftSchedule withName(String name) => _domain(
          classes: [
            ShiftClass(
                name: name,
                abbr: '·',
                startMinute: 8 * 60,
                endMinute: 20 * 60,
                alarmEnabled: true,
                alarmMinute: at2359),
            const ShiftClass(name: '休班', abbr: '休', isRest: true),
          ],
          cycle: const [0, 1],
        );

    await _pumpEditor(tester, withName('编辑中'), active: withName('当前班表'));
    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();

    expect(labels, isNotEmpty, reason: '重排应当真的排了班次闹钟');
    expect(labels.every((l) => l.startsWith('当前班表')), isTrue,
        reason: '重排必须按当前方案，按编辑中那套排会把闹钟排到错的班表上');
  });

  // ---------------------------------------------------------------------------
  // M7：删除中间的班次定义时，周期里更大的下标必须前移
  // ---------------------------------------------------------------------------

  testWidgets('删未被引用的班次：先确认，取消则不删', (tester) async {
    final repo = await _pumpEditor(
      tester,
      _domain(
        classes: const [
          ShiftClass(name: 'A班', abbr: 'A'),
          ShiftClass(name: 'B班', abbr: 'B'),
          ShiftClass(name: 'C班', abbr: 'C'),
        ],
        cycle: const [0, 2],
      ),
    );
    expect(find.byType(GlassDeleteButton), findsNWidgets(3));

    // 删中间的 B（下标 1，周期没引用它）
    await tester.tap(find.byType(GlassDeleteButton).at(1));
    await tester.pumpAndSettle();
    expect(find.text(L10n.deleteShiftClassTitle), findsOneWidget,
        reason: '删除要先确认 —— 删错了没法靠重加复原');

    await tester.tap(find.text(L10n.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(GlassDeleteButton), findsNWidgets(3),
        reason: '取消后班次必须还在');

    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();
    expect(repo.saved!.classes.map((c) => c.name), ['A班', 'B班', 'C班']);
  });

  testWidgets('删未被引用的班次：确认后删除，周期下标整体前移一位',
      (tester) async {
    final repo = await _pumpEditor(
      tester,
      _domain(
        classes: const [
          ShiftClass(name: 'A班', abbr: 'A'),
          ShiftClass(name: 'B班', abbr: 'B'),
          ShiftClass(name: 'C班', abbr: 'C'),
        ],
        cycle: const [0, 2],
      ),
    );

    await _tapDeleteAndConfirm(
        tester, find.byType(GlassDeleteButton).at(1));
    expect(find.byType(GlassDeleteButton), findsNWidgets(2));

    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();

    expect(repo.saved!.classes.map((c) => c.name), ['A班', 'C班']);
    expect(repo.saved!.cycle, [0, 1],
        reason: 'C 的下标要从 2 前移到 1，否则周期会指向不存在的班次定义');
  });

  testWidgets('删仍被周期引用的班次：拦下并提示，不弹确认框', (tester) async {
    await _pumpEditor(tester, _domain(cycle: const [0, 0, 2]));
    // 下标 0 被周期用了 2 天
    await tester.tap(find.byType(GlassDeleteButton).first);
    await tester.pumpAndSettle();

    expect(find.byType(GlassDialog), findsNothing,
        reason: '这条路径本来就删不掉，再问一次是多余的');
    expect(find.text(L10n.deleteShiftClassInUse.replaceAll('{n}', '2')),
        findsOneWidget);
    expect(find.byType(GlassDeleteButton), findsNWidgets(3));
  });

  testWidgets('输入框字号与主题默认一致，不再被显式压小', (tester) async {
    // 「字体比其他界面小一圈」的直接成因：班次名称/简称输入框上写了
    // fontSize: fontBody(14)，把 M3 默认的 16 盖掉了 —— 而同一张卡片里的
    // 方案名称输入框没有显式字号、就是 16，于是同屏两个输入框不一样大。
    await _pumpEditor(tester, _domain());

    final editables = tester.widgetList<EditableText>(find.byType(EditableText));
    expect(editables, isNotEmpty);
    for (final e in editables) {
      expect(e.style.fontSize, AppTokens.titleStrong.fontSize,
          reason:
              '输入框字号应为 ${AppTokens.titleStrong.fontSize}，实际 ${e.style.fontSize}');
    }
  });

  testWidgets('卡片标题与行内标签落在统一档位', (tester) async {
    await _pumpEditor(tester, _domain());

    double sizeOf(String text) =>
        tester.widget<Text>(find.text(text)).style!.fontSize!;

    expect(sizeOf(L10n.shiftClasses), AppTokens.titleStrong.fontSize); // 卡片标题
    expect(sizeOf(L10n.cycleSection), AppTokens.titleStrong.fontSize); // 卡片标题

    // 行内标签（第 N 天）落在 13 档里带强调的那一支：labelSecondary = 13/w600。
    // 迁移时如果只对字号不对字重，会掉到 w400 的 rowSecondary —— 这正是要钉住的。
    final dayLabel = tester.widget<Text>(find.text(L10n.dayN(1)));
    expect(dayLabel.style!.fontSize, AppTokens.labelSecondary.fontSize);
    expect(dayLabel.style!.fontWeight, AppTokens.labelSecondary.fontWeight);

    // 分段器「工作/休息」原本就是 w700，13 档没有更重角色 → 走 copyWith 保住
    final segmentLabel = tester.widget<Text>(find.text(L10n.work).first);
    expect(segmentLabel.style!.fontSize, AppTokens.labelSecondary.fontSize);
    expect(segmentLabel.style!.fontWeight, FontWeight.w700);

    // 预览条是唯一被压到最低一档的地方（7 列网格，再大就换行破版）。基线是
    // 12/w700 —— microStrong 精确匹配，别写成 12/w600 的 microLabel。
    final previewTitle = tester.widget<Text>(find.text(L10n.previewNext14));
    expect(previewTitle.style!.fontSize, AppTokens.microStrong.fontSize);
    expect(previewTitle.style!.fontWeight, AppTokens.microStrong.fontWeight);
  });

  testWidgets('14 档的读数没被摊平成 w500：周期长度与时间值都是 labelStrong',
      (tester) async {
    await _pumpEditor(tester, _domain());

    // 周期长度读数（基线的裸 `TextStyle(fontWeight: w600)`，字号随主题 = 14）
    final readout = tester.widget<Text>(find.text('6${L10n.cycleLengthUnit}'));
    expect(readout.style!.fontSize, AppTokens.labelStrong.fontSize);
    expect(readout.style!.fontWeight, AppTokens.labelStrong.fontWeight);

    // 时间 chip 的值（基线 14/w600）。08:30 同时是白班的开始与夜班的结束，
    // 两处都该落在同一档上。
    final times = tester.widgetList<Text>(find.text('08:30')).toList();
    expect(times, isNotEmpty, reason: '时间 chip 的值应该在树上');
    for (final t in times) {
      expect(t.style!.fontSize, AppTokens.labelStrong.fontSize);
      expect(t.style!.fontWeight, AppTokens.labelStrong.fontWeight);
    }
  });

  testWidgets('班组行里的标签保留各自的字重：chip 是 w700，日期值是 w600',
      (tester) async {
    await _pumpEditor(
      tester,
      _domain(anchor: DateTime.utc(2025, 6, 1), teamOffsets: const [0, 1, 2, 3]),
    );
    await tester.tap(find.text(L10n.crewSettingsOptional));
    await tester.pumpAndSettle();

    // 「我的班组」chip：可点按钮的标签，13 档里没有 w700，走 copyWith
    final chip = tester.widget<Text>(find.text(L10n.myTeam));
    expect(chip.style!.fontSize, AppTokens.labelSecondary.fontSize);
    expect(chip.style!.fontWeight, FontWeight.w700);

    // 班组数（基线就是 14/w700）→ labelStrong 精确匹配
    final teamCount = tester.widget<Text>(find.text(L10n.teamCountN(4)));
    expect(teamCount.style!.fontSize, AppTokens.labelStrong.fontSize);
    expect(teamCount.style!.fontWeight, AppTokens.labelStrong.fontWeight);

    // 第 2 组（下标 1）的「周期起始日」= 基准日 − offsets[1] = 05-31，只在这一行
    // 出现；原来是 w600，labelSecondary 正好是 13/w600，不需要 copyWith。
    final dateText = tester
        .widget<Text>(find.text(L10n.yearMonthDay(DateTime.utc(2025, 5, 31))));
    expect(dateText.style!.fontSize, AppTokens.labelSecondary.fontSize);
    expect(dateText.style!.fontWeight, AppTokens.labelSecondary.fontWeight);
  });

  testWidgets('周期行把可选班次铺成 chip，点一下就切换', (tester) async {
    await _pumpEditor(tester, _domain(cycle: const [0, 1, 1]));

    // 3 天 × 3 个班次定义 = 9 个 chip
    expect(find.byType(GlassChoiceChip), findsNWidgets(9));
    expect(
        tester.widget<GlassChoiceChip>(find.byKey(cycleChipKey(0, 0))).selected,
        isTrue);
    expect(
        tester.widget<GlassChoiceChip>(find.byKey(cycleChipKey(0, 1))).selected,
        isFalse);

    // 第 1 天从「班次 0」改成「班次 2」
    await tester.tap(find.byKey(cycleChipKey(0, 2)));
    await tester.pumpAndSettle();

    expect(
        tester.widget<GlassChoiceChip>(find.byKey(cycleChipKey(0, 0))).selected,
        isFalse);
    expect(
        tester.widget<GlassChoiceChip>(find.byKey(cycleChipKey(0, 2))).selected,
        isTrue);
  });

  testWidgets('周期行不再有下拉控件', (tester) async {
    // 二级弹层是这次要消掉的东西：Material 的方角下拉与全 App 的玻璃
    // 弹层完全不同源。用「找不到 DropdownButton」把这件事钉住。
    await _pumpEditor(tester, _domain());
    expect(find.byType(DropdownButton<int>), findsNothing);
  });

  testWidgets('chip 带上班次色与名称', (tester) async {
    await _pumpEditor(
      tester,
      _oneShift(const ShiftClass(name: '白班', abbr: '白', color: 0xFF4C8DFF)),
    );

    final chip = tester.widget<GlassChoiceChip>(find.byKey(cycleChipKey(0, 0)));
    expect(chip.selected, isTrue);
    expect(chip.label, '白班');
    expect(chip.color, const Color(0xFF4C8DFF));
  });

  test('周期行放不下时隐藏只读时间', () {
    // 三张 chip 与「20:30 – 次日08:00」在手机宽度下互斥：并存会把 chip
    // 挤成半个，看起来像坏了而不是像能滑。时间在上一张「班次设置」卡里
    // 逐条列着，隐藏不丢信息。
    const names = ['白班', '中班', '夜班'];

    expect(
      cycleRowFitsTime(
          rowWidth: 356, classNames: names, timeText: '20:30 – 次日08:00'),
      isFalse,
      reason: '手机宽度（420 视口下卡片内约 356）放不下三张 chip 加长时间串',
    );
    expect(
      cycleRowFitsTime(
          rowWidth: 900, classNames: names, timeText: '20:30 – 次日08:00'),
      isTrue,
      reason: '宽屏应当放得下',
    );
    expect(
      cycleRowFitsTime(
          rowWidth: 356, classNames: const ['白班'], timeText: '08:00 – 18:00'),
      isTrue,
      reason: '只有一个班次定义时，窄屏也该放得下',
    );
  });

  // ---------------------------------------------------------------------------
  // 按天改班：编辑器改班次定义时必须把 id 原样交还给保存
  //
  // 覆盖表（shift_day_overrides）引用的是班次行 id，而 saveSchedule 是增量更新：
  // 没有 id 的班次走 INSERT，库里不在新列表里的旧行连同引用它的覆盖一起被删。
  // 所以编辑器一旦丢 id，用户只是改个简称就会把自己的按天调整全部弄丢。
  // ---------------------------------------------------------------------------

  testWidgets('改班次简称不会丢掉它的 id（丢了的话覆盖会指飞）', (tester) async {
    // 三个班次都带上库里已有的行 id —— 编辑器必须原样交还给 saveSchedule。
    final domain = _domain(
      classes: const [
        ShiftClass(
            id: 11,
            name: '白班',
            abbr: '白',
            startMinute: 8 * 60 + 30,
            endMinute: 20 * 60 + 30,
            color: 0xFF4C8DFF),
        ShiftClass(
            id: 12,
            name: '夜班',
            abbr: '夜',
            startMinute: 20 * 60 + 30,
            endMinute: 8 * 60 + 30,
            color: 0xFF7A5CFF),
        ShiftClass(
            id: 13, name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4),
      ],
    );
    final repo = await _pumpEditor(tester, domain);
    final before = domain.classes.map((c) => c.id).toList();

    // 只改第一个班次的简称：这正是「改一个字段就丢 id」的最小复现。
    await tester.enterText(
        find.widgetWithText(TextField, L10n.abbrLabel).first, 'X');
    await tester.pumpAndSettle();

    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();

    final after = repo.saved!.classes;
    expect(after.map((c) => c.abbr), ['X', '夜', '休'], reason: '改动本身要落进保存');
    expect(after.map((c) => c.id).toList(), before,
        reason: 'id 集合必须逐位不变 —— 少一个，saveSchedule 就会把这个班次当成'
            '新班次 INSERT，并把旧行连同引用它的按天覆盖一起删掉');
  });

  testWidgets('预览不叠按天覆盖，并在有覆盖时给出提示', (tester) async {
    final today = dateOnly(DateTime.now());
    final domain = _domain(
      classes: const [
        ShiftClass(name: '甲班', abbr: '甲', color: 0xFF4C8DFF),
        ShiftClass(name: '乙班', abbr: '乙', color: 0xFF7A5CFF),
      ],
      cycle: const [0], // 轮转恒为「甲班」，今天那格有没有被覆盖一眼可辨
      dayOverrides: {dayNumber(today): 1}, // 今天单独改成「乙班」
    );
    await _pumpEditor(tester, domain);

    expect(find.text(L10n.previewHasOverrides(1)), findsOneWidget,
        reason: '预览不再叠覆盖，必须告诉用户「日历上跟这里不一样」');

    // 14 格都按轮转显示「甲班」；预览若把覆盖叠了进来，今天会显示「乙班」。
    expect(find.descendant(of: _strip(), matching: find.text('甲')),
        findsNWidgets(14));
    expect(find.descendant(of: _strip(), matching: find.text('乙')),
        findsNothing);
  });

  // ---------------------------------------------------------------------------
  // 两条「会静默毁掉按天覆盖」的编辑器动作
  //
  // `saveSchedule` 的悬空清理会连带删掉引用被删班次的覆盖行（spec §4.2），
  // 而覆盖没有「重加回去」这条路 —— 删班次是 removeAt、切空白表恢复的是
  // 全新 id 的默认四班两倒。所以这两条路都必须先把天数说清楚。
  // ---------------------------------------------------------------------------

  testWidgets('删班次时确认框点名会连带丢掉多少天的按天调整', (tester) async {
    final d1 = DateTime(2026, 9, 20);
    final d2 = DateTime(2026, 9, 21);
    await _pumpEditor(
      tester,
      _domain(
        // 带 id：覆盖的计数按 classId 走（没落库的班次不会有覆盖指着它）。
        classes: const [
          ShiftClass(id: 11, name: 'A班', abbr: 'A'),
          ShiftClass(id: 12, name: 'B班', abbr: 'B'),
          ShiftClass(id: 13, name: 'C班', abbr: 'C'),
        ],
        cycle: const [0, 2],
        // 有两天单独改成了 B 班（下标 1）
        dayOverrides: {dayNumber(d1): 1, dayNumber(d2): 1},
      ),
    );

    // 删 B（下标 1，周期没引用它 → 会走确认框那条路）
    await tester.tap(find.byType(GlassDeleteButton).at(1));
    await tester.pumpAndSettle();

    expect(find.text(L10n.deleteShiftClassTitle), findsOneWidget);
    expect(find.text(L10n.deleteShiftClassOverridesLost(2)), findsOneWidget,
        reason: '引用它的那 2 天覆盖会随定义一起消失，确认框必须说出来');

    // 这条确认框只提时间 / 颜色 / 闹钟，一个字没提覆盖 —— 加这一句正是 I1。
    expect(find.text(L10n.deleteShiftClassContent('B班')), findsOneWidget);

    await tester.tap(find.text(L10n.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(GlassDeleteButton), findsNWidgets(3));
  });

  testWidgets('删没被覆盖过的班次：确认框不提按天调整', (tester) async {
    final d1 = DateTime(2026, 9, 20);
    await _pumpEditor(
      tester,
      _domain(
        classes: const [
          ShiftClass(id: 11, name: 'A班', abbr: 'A'),
          ShiftClass(id: 12, name: 'B班', abbr: 'B'),
          ShiftClass(id: 13, name: 'C班', abbr: 'C'),
        ],
        cycle: const [0, 1], // A、B 被周期引用，C 空着
        dayOverrides: {dayNumber(d1): 0}, // 那一天改成的是 A，不是 C
      ),
    );

    // 删 C（下标 2，没被周期引用，也没有任何覆盖指着它）
    await tester.tap(find.byType(GlassDeleteButton).at(2));
    await tester.pumpAndSettle();

    expect(find.text(L10n.deleteShiftClassTitle), findsOneWidget);
    expect(find.textContaining('还有'), findsNothing,
        reason: '警告只该给「真会丢覆盖」的那个班次，不能见谁都报一句');

    await tester.tap(find.text(L10n.cancel));
    await tester.pumpAndSettle();
  });

  testWidgets('打开「跟随法定节假日」会丢掉按天调整：先确认；取消则开关不动',
      (tester) async {
    final d1 = DateTime(2026, 9, 20);
    final d2 = DateTime(2026, 9, 21);
    await _pumpEditor(
      tester,
      _domain(
        classes: const [
          ShiftClass(id: 11, name: 'A班', abbr: 'A'),
          ShiftClass(id: 12, name: 'B班', abbr: 'B'),
          ShiftClass(id: 13, name: 'C班', abbr: 'C'),
        ],
        dayOverrides: {dayNumber(d1): 0, dayNumber(d2): 1},
      ),
    );

    final sw = find.descendant(
      of: find.widgetWithText(GlassTile, L10n.followHoliday),
      matching: find.byType(GlassSwitch),
    );

    await tester.tap(sw);
    await tester.pumpAndSettle();

    expect(find.text(L10n.followHolidayConfirmTitle), findsOneWidget,
        reason: '打开它会把全部班次定义清空，连带丢掉这几天，必须先问一次');
    expect(find.text(L10n.followHolidayDropsOverrides(2)), findsOneWidget,
        reason: '要说清楚会丢几天');

    // 取消：什么都不变，而且开关**没有**先乐观地翻过去
    await tester.tap(find.text(L10n.cancel));
    await tester.pumpAndSettle();
    expect(tester.widget<GlassSwitch>(sw).value, isFalse,
        reason: '先确认再翻开关：取消时开关的视觉状态不该动过');
    expect(find.byType(GlassDeleteButton), findsNWidgets(3),
        reason: '取消后班次定义要还在');

    // 确认：真的切到空白表
    await tester.tap(sw);
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();
    expect(tester.widget<GlassSwitch>(sw).value, isTrue);
    expect(find.byType(GlassDeleteButton), findsNothing,
        reason: '确认后班次设置整段收起');
  });

  // ---------------------------------------------------------------------------
  // 撞班：周期长度与各班组起始日的间隔对不上时，同一天会出现两个班组上同一个班
  //
  // 2026-09-21 用户反馈：五班三倒改成 10 天一轮（每个班连排两天）之后，各班组
  // 还按 1 天错开 —— 信息卡上「三班 中 / 四班 中」同天同班。起因是
  // `_setCycleLength` 只管周期、不碰班组的周期起始日。
  // ---------------------------------------------------------------------------

  /// 用户那套：白白中中休夜夜休休休，5 个班组。
  ShiftSchedule tenDayFiveCrews({List<int> teamOffsets = const [0, 1, 2, 3, 4]}) =>
      _domain(
        classes: const [
          ShiftClass(
              name: '白班',
              abbr: '白',
              startMinute: 8 * 60 + 30,
              endMinute: 20 * 60 + 30,
              color: 0xFF4C8DFF),
          ShiftClass(
              name: '中班',
              abbr: '中',
              startMinute: 16 * 60,
              endMinute: 24 * 60,
              color: 0xFFFF9F0A),
          ShiftClass(
              name: '夜班',
              abbr: '夜',
              startMinute: 0,
              endMinute: 8 * 60,
              color: 0xFF7A5CFF),
          ShiftClass(name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4),
        ],
        cycle: const [0, 0, 1, 1, 3, 2, 2, 3, 3, 3],
        teamCount: 5,
        teamOffsets: teamOffsets,
      );

  testWidgets('撞班：提示点名相撞的班组，一键均分后提示消失、我组起始日不动',
      (tester) async {
    final repo = await _pumpEditor(tester, tenDayFiveCrews());

    final hint = find.byKey(const Key('editor-crew-clash-hint'));
    expect(hint, findsOneWidget, reason: '1 天错开在 10 天周期上必然撞班');
    final text = tester.widget<Text>(hint).data!;
    expect(text.contains('一班'), isTrue, reason: '要点名相撞的两个班组：$text');
    expect(text.contains('二班'), isTrue, reason: text);

    await tester.tap(find.text(L10n.evenCrewStarts));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('editor-crew-clash-hint')), findsNothing,
        reason: '均分之后一对都不该撞');

    await tester.tap(find.text(L10n.saveAndReschedule));
    await tester.pumpAndSettle();
    expect(repo.saved!.teamOffsets, [0, 2, 4, 6, 8]);
    expect(repo.saved!.anchorDate, DateTime.utc(2025, 6, 1),
        reason: '我们班组的周期起始日不能被这条修复顺手挪走');
  });

  testWidgets('不撞班的方案不出现这行提示', (tester) async {
    await _pumpEditor(tester, tenDayFiveCrews(teamOffsets: const [0, 2, 4, 6, 8]));
    expect(find.byKey(const Key('editor-crew-clash-hint')), findsNothing);
    expect(find.text(L10n.evenCrewStarts), findsNothing);
  });
}
