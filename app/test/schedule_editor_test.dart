// app/test/schedule_editor_test.dart
//
// 排班编辑器（班次定义 + 周期表 + 班组起始日）的界面行为测试。
//
// 本机没有可运行目标（无 Android 设备 / 无 VS 工具链 / web 被本地通知插件挡住），
// 所以界面行为全部靠 widget 测试覆盖。
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_delete_button.dart';
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
  _FakeRepository(super.db, this.domain);

  final ShiftSchedule domain;
  _Saved? saved;

  @override
  Future<ShiftSchedule?> getScheduleDomain(int id) async => domain;

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
}) {
  return ShiftSchedule(
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
    teamCount: 4,
    teamNames: const ['一班', '二班', '三班', '四班'],
    ourTeamIndex: 0,
    teamOffsets: teamOffsets ?? const [0, 1, 2, 3],
  );
}

/// 从一个宿主页 push 编辑器（这样保存后的 pop 有地方可回）。
Future<_FakeRepository> _pumpEditor(
    WidgetTester tester, ShiftSchedule domain) async {
  // 编辑器是一整页长列表：给足高度，让周期里的每一行都真的被构建出来，
  // 否则 ListView 只会懒构建视口内的那几行，find 就找不到。
  tester.view.physicalSize = const Size(900, 4600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);
  final repo = _FakeRepository(db, domain);

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
Finder _plus() =>
    find.widgetWithIcon(IconButton, Icons.add_circle_outline_outlined);

/// 某个 ListTile（按标题文字找）的副标题文本。
String _subtitleOf(WidgetTester tester, String title) {
  final texts = tester.widgetList<Text>(find.descendant(
    of: find.widgetWithText(ListTile, title),
    matching: find.byType(Text),
  ));
  return texts.last.data!;
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

  testWidgets('周期某天下拉换班次后，该行右侧时间文本跟着变', (tester) async {
    // 第 1 天引用白班，另外两天都是休班 —— 这样「夜班」的时间文本只会出现一次
    await _pumpEditor(tester, _domain(cycle: const [0, 2, 2]));

    // 第 1 天引用白班（08:30–20:30）
    expect(find.text('08:30 – 20:30'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<int>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('夜班').last);
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

    final before = _subtitleOf(tester, L10n.start);
    expect(before, '08:30');

    // 点开班次定义里的「开始」，把小时轮往下拨
    await tester.tap(find.text(L10n.start));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CupertinoPicker).first, const Offset(0, 80));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();

    final after = _subtitleOf(tester, L10n.start);
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

    // 删没被引用的「休班」→ 成功
    await tester.tap(find.byType(GlassDeleteButton).at(2));
    await tester.pumpAndSettle();
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

    await tester.tap(find.widgetWithText(ListTile, L10n.myCycleStart));
    await tester.pumpAndSettle();
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

    // 周期没引用新班次 → 删除成功
    await tester.tap(find.byType(GlassDeleteButton).at(3));
    await tester.pumpAndSettle();
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
    expect(find.text(L10n.start), findsOneWidget);
    expect(find.text(L10n.rest), findsOneWidget); // 第 2 天的休班

    final classSwitches = find.descendant(
      of: find.widgetWithText(GlassTile, L10n.shiftClasses),
      matching: find.byType(GlassSwitch),
    );
    await tester.tap(classSwitches.first);
    await tester.pumpAndSettle();

    // 时间条目整段消失 —— copyWith 清不掉可空字段，这里是直接构造的新班次
    expect(find.text(L10n.start), findsNothing);
    expect(find.text('08:30 – 20:30'), findsNothing);
    // 周期里引用它的两行都变成「休息」
    expect(find.text(L10n.rest), findsNWidgets(2));
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
}
