// app/test/monthly_schedule_editor_test.dart
//
// 编辑页的「按周期 / 按月」两种模式：切换、段列表、种段、预览。
//
// 两条最要紧的：
//  · **切换模式不丢数据**（两边各存各的，切回来周期还在），
//  · 而且**当前模式说了算** —— `monthly = false` 时哪怕段表非空也必须走周期。
//    （拿「段表空不空」去猜模式的实现会在这里红，那正是 spec §3.5 要挡的静默错。）
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/monthly_pattern.dart';
import 'package:shiftassistantpro/domain/schedule_chain.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/calendar/schedule_editor_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

class _Saved {
  _Saved({
    required this.monthly,
    required this.monthSegments,
    required this.teamSegOffsets,
    required this.cycle,
  });

  final bool monthly;
  final List<MonthlySegment> monthSegments;
  final List<int> teamSegOffsets;
  final List<int> cycle;
}

class _FakeRepository extends AppRepository {
  _FakeRepository(super.db, this.domain);

  final ShiftSchedule domain;
  _Saved? saved;

  @override
  Future<ShiftSchedule?> getScheduleDomain(int id) async => domain;

  @override
  Future<ActiveSchedules?> getActiveSchedules() async => ActiveSchedules(
        all: const [],
        chain: ScheduleChain(fallback: domain, fallbackId: 1),
      );

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
    bool monthly = false,
    List<MonthlySegment> monthSegments = const [],
    List<int> teamSegOffsets = const [],
  }) async {
    saved = _Saved(
      monthly: monthly,
      monthSegments: List.of(monthSegments),
      teamSegOffsets: List.of(teamSegOffsets),
      cycle: List.of(cycle),
    );
    return 7;
  }
}

/// 三班倒那三个班次（简称就是断言里用的字），外加一个休班 —— 有它，「4 组 4 段」
/// 才排得开（真实默认方案就是 4 个班次定义，其中两个是休班）。
const _zhong = ShiftClass(name: '中班', abbr: '中', color: 0xFF00AA00);
const _bai = ShiftClass(name: '白班', abbr: '白', color: 0xFF0055FF);
const _ye = ShiftClass(name: '夜班', abbr: '夜', color: 0xFFFF8800);
const _xiu = ShiftClass(name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4);

ShiftSchedule _domain({
  bool monthly = false,
  List<MonthlySegment> monthSegments = const [],
  List<int> teamSegOffsets = const [],
  int teamCount = 4,
}) =>
    ShiftSchedule(
      name: '测试排班',
      anchorDate: DateTime.utc(2025, 6, 1),
      classes: const [_zhong, _bai, _ye, _xiu],
      // 周期与段表**同时非空**：这正是「切换模式不丢数据」之后库里的样子。
      cycle: const [0, 1, 2],
      monthly: monthly,
      monthlySegments: monthSegments,
      teamCount: teamCount,
      teamNames: L10n.defaultTeamNames(teamCount),
      ourTeamIndex: 0,
      teamOffsets: const [0, 1, 2, 3],
      teamSegOffsets: teamSegOffsets,
    );

Future<_FakeRepository> _pumpEditor(WidgetTester tester, ShiftSchedule domain,
    {Size size = const Size(900, 4600)}) async {
  tester.view.physicalSize = size;
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

/// 切到「按月」。
Future<void> _switchToMonthly(WidgetTester tester) async {
  await tester.tap(find.text(L10n.scheduleModeMonthly));
  await tester.pumpAndSettle();
}

/// 顶部那张卡的保存胶囊。
Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text(L10n.saveAndReschedule));
  await tester.pumpAndSettle();
}

/// 按月段列表里每一行左边的日号（第一行恒为 1）。
List<int> _rowDays(WidgetTester tester) {
  final out = <int>[];
  for (var i = 0; i < 40; i++) {
    final key = monthRowDayKey(i);
    if (find.byKey(key).evaluate().isEmpty) break;
    final text = tester
        .widget<Text>(find.descendant(
            of: find.byKey(key), matching: find.byType(Text)))
        .data!;
    out.add(int.parse(RegExp(r'\d+').firstMatch(text)!.group(0)!));
  }
  return out;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
  });
  setUp(() => L10n.locale = 'zh');

  testWidgets('切到「按月」出段列表、周期行消失；切回去周期还在', (tester) async {
    final repo = await _pumpEditor(tester,
        _domain(monthly: true, monthSegments: const [
          MonthlySegment(startDay: 1, classIndex: 0),
          MonthlySegment(startDay: 11, classIndex: 1),
          MonthlySegment(startDay: 21, classIndex: 2),
        ], teamSegOffsets: const [0, 1, 2]));

    // 进来就是按月：段列表在、周期那一行不在
    expect(_rowDays(tester), [1, 11, 21]);
    expect(find.text(L10n.monthlySection), findsOneWidget);
    expect(find.text(L10n.cycleSection), findsNothing,
        reason: '按月模式不画「周期设置」那一行');

    // 切回按周期：周期那一行回来（**周期没被清掉** —— 切换不丢数据）
    await tester.tap(find.text(L10n.scheduleModeCycle));
    await tester.pumpAndSettle();
    expect(find.text(L10n.cycleSection), findsOneWidget);
    expect(_rowDays(tester), isEmpty);

    await _save(tester);
    expect(repo.saved!.monthly, isFalse);
    expect(repo.saved!.cycle, [0, 1, 2]);
    // **段表原样带着** —— 切回来没有被清掉，下次切过去还在
    expect(repo.saved!.monthSegments.map((s) => s.startDay), [1, 11, 21]);
  });

  testWidgets('第一次切到按月：按班组数种段，而且不撞班', (tester) async {
    await _pumpEditor(tester, _domain(teamCount: 4));
    await _switchToMonthly(tester);

    // 4 个班组 → 4 段（`defaultMonthlySegments(4)` = 1/9/17/24）
    expect(_rowDays(tester), [1, 9, 17, 24]);
    expect(find.byKey(const Key('month-add-segment')), findsOneWidget);
    expect(find.byKey(const Key('editor-crew-clash-hint')), findsNothing,
        reason: '4 组 4 段均分之后没有任何一组撞班');
  });

  testWidgets('第一次切到按月：班组数 1 时退化成一段', (tester) async {
    await _pumpEditor(tester, _domain(teamCount: 1));
    await _switchToMonthly(tester);
    expect(_rowDays(tester), [1]);
  });

  testWidgets('按月模式的预览条逐格等于领域层算出来的班次', (tester) async {
    final domain = _domain(monthly: true, monthSegments: const [
      MonthlySegment(startDay: 1, classIndex: 0),
      MonthlySegment(startDay: 11, classIndex: 1),
      MonthlySegment(startDay: 21, classIndex: 2),
    ]);
    await _pumpEditor(tester, domain);

    // 预览条是第一张卡；它 14 格里画出来的简称，按格序与领域层逐个比。
    final preview = find.byType(GlassTile).first;
    final abbrs = tester
        .widgetList<Text>(
            find.descendant(of: preview, matching: find.byType(Text)))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => const ['中', '白', '夜'].contains(s))
        .toList();

    final today = dateOnly(DateTime.now());
    final want = [
      for (var i = 0; i < 14; i++)
        domain.shiftOn(DateTime(today.year, today.month, today.day + i))!.shortLabel,
    ];
    expect(abbrs, want, reason: '预览条必须与 shiftOn 一格一格对上');
  });

  testWidgets('删中间一段：并进上一段，总覆盖不出现空档', (tester) async {
    final repo = await _pumpEditor(tester, _domain(teamCount: 4));
    await _switchToMonthly(tester);
    expect(_rowDays(tester), [1, 9, 17, 24]);

    // 删第 2 行（第 9 天起的那个）—— 确认框里点「删除」
    await tester.tap(find.byKey(monthRowDeleteKey(1)));
    await tester.pumpAndSettle();
    expect(find.text(L10n.monthlyDeleteSegmentTitle), findsOneWidget);
    await tester.tap(find.text(L10n.delete));
    await tester.pumpAndSettle();

    expect(_rowDays(tester), [1, 17, 24], reason: '第 9 天那一段没了，1–16 天归第一段');

    await _save(tester);
    final segs = repo.saved!.monthSegments;
    expect(segs.map((s) => s.startDay), [1, 17, 24]);
    expect(segs.length, 3);
  });

  testWidgets('第一行不给删除键（第一段恒从 1 日起，删了就没有 1 号）', (tester) async {
    await _pumpEditor(tester, _domain(teamCount: 3));
    await _switchToMonthly(tester);
    expect(_rowDays(tester), [1, 11, 22]);
    // 第一行没有删除键，后两行有
    expect(find.byKey(monthRowDeleteKey(0)), findsNothing);
    expect(find.byKey(monthRowDeleteKey(1)), findsOneWidget);
    expect(find.byKey(monthRowDeleteKey(2)), findsOneWidget);
  });

  testWidgets('「添加一段」：新段接在最后、且起始日合法', (tester) async {
    final repo = await _pumpEditor(tester, _domain(teamCount: 3));
    await _switchToMonthly(tester);
    expect(_rowDays(tester), [1, 11, 22]);

    await tester.tap(find.byKey(const Key('month-add-segment')));
    await tester.pumpAndSettle();
    final days = _rowDays(tester);
    expect(days.length, 4);
    expect(days.first, 1);
    // 严格递增、且最后一段不越过 31（段表的合法性由 `validMonthlySegments` 保证）
    for (var i = 1; i < days.length; i++) {
      expect(days[i], greaterThan(days[i - 1]));
    }
    expect(days.last, lessThanOrEqualTo(31));

    await _save(tester);
    expect(repo.saved!.monthly, isTrue);
    expect(validMonthlySegments(repo.saved!.monthSegments), isTrue);
  });

  testWidgets('日号选项器只列合法值（严格递增、给后面的段留位置）', (tester) async {
    await _pumpEditor(tester, _domain(teamCount: 3));
    await _switchToMonthly(tester);
    expect(_rowDays(tester), [1, 11, 22]);

    // 点第 2 行的日号 → 弹选项器
    await tester.tap(find.byKey(monthRowDayKey(1)));
    await tester.pumpAndSettle();
    // 上一段是 1，所以最小是 2；后面还剩 1 段（它自己要占一天），所以最大 30
    expect(find.text(L10n.monthlyFromDay(2)), findsWidgets);
    await tester.tap(find.text(L10n.monthlyFromDay(5)).last);
    await tester.pumpAndSettle();
    expect(_rowDays(tester), [1, 5, 22]);
  });
}
