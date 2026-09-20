// app/test/saved_template_test.dart
//
// 「我的模板」：编辑器存一份 → 选择页里出现 → 选它建出新方案；以及改名 / 删除。
//
// 用假仓库（不碰真库）：这里要断言的是**界面把什么交给了仓库**，
// 真库那一层由 `schedule_template_test.dart`（纯函数）与
// `migration_v8_to_v9_test.dart`（落库往返）覆盖。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_delete_button.dart';
import 'package:shiftassistantpro/core/widgets/glass_dialog.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/schedule_template.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/calendar/schedule_editor_screen.dart';
import 'package:shiftassistantpro/features/calendar/shift_template_picker_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 记住界面交下来的东西：存模板、改名、删、以及「用模板建方案」的入参。
class _FakeRepo extends AppRepository {
  _FakeRepo(super.db, {required this.domain, List<ScheduleTemplate> initial = const []})
      : templates = List.of(initial);

  final ShiftSchedule domain;
  final List<ScheduleTemplate> templates;

  ScheduleTemplate? savedTemplate;
  String? renamedTo;
  int? deletedId;
  String? createdName;
  List<ShiftClass> createdClasses = const [];
  List<int> createdCycle = const [];
  int createdTeamCount = 0;
  List<int> createdOffsets = const [];

  @override
  Future<ShiftSchedule?> getScheduleDomain(int id) async => domain;

  @override
  Future<List<ScheduleTemplate>> listTemplates() async => List.of(templates);

  @override
  Future<int> saveTemplate(ScheduleTemplate t) async {
    savedTemplate = t;
    templates.insert(0, t);
    return templates.length;
  }

  @override
  Future<void> renameTemplate(int id, String name) async {
    renamedTo = name;
    final i = templates.indexWhere((t) => t.id == id);
    if (i >= 0) {
      final o = templates[i];
      templates[i] = ScheduleTemplate(
          id: o.id,
          name: name,
          classes: o.classes,
          cycle: o.cycle,
          teamCount: o.teamCount,
          teamOffsets: o.teamOffsets);
    }
  }

  @override
  Future<void> deleteTemplate(int id) async {
    deletedId = id;
    templates.removeWhere((t) => t.id == id);
  }

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
    createdName = name;
    createdClasses = List.of(classes);
    createdCycle = List.of(cycle);
    createdTeamCount = teamCount;
    createdOffsets = List.of(teamOffsets);
    return 1;
  }
}

/// 用户那套：五班三倒 10 天一轮。
ShiftSchedule _domain() => ShiftSchedule(
      name: '五班三倒 · 10 天一轮',
      anchorDate: DateTime.utc(2026, 9, 21),
      classes: const [
        ShiftClass(
            name: '白班',
            abbr: '白',
            startMinute: 8 * 60 + 30,
            endMinute: 20 * 60 + 30,
            color: 0xFF4C8DFF,
            alarmEnabled: true,
            alarmMinute: 7 * 60),
        ShiftClass(name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4),
      ],
      cycle: const [0, 0, 1, 1, 1],
      teamCount: 5,
      teamNames: const ['一班', '二班', '三班', '四班', '五班'],
      ourTeamIndex: 0,
      teamOffsets: const [0, 2, 4, 6, 8],
    );

ScheduleTemplate _template({int id = 1, String name = '我的零点班'}) =>
    ScheduleTemplate(
      id: id,
      name: name,
      classes: _domain().classes,
      cycle: _domain().cycle,
      teamCount: 5,
      teamOffsets: const [0, 2, 4, 6, 8],
    );

Future<_FakeRepo> _pump(
  WidgetTester tester,
  Widget child, {
  List<ScheduleTemplate> initial = const [],
}) async {
  tester.view.physicalSize = const Size(900, 4600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);
  final repo = _FakeRepo(db, domain: _domain(), initial: initial);

  await tester.pumpWidget(ProviderScope(
    overrides: [appRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(home: child),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
  });

  testWidgets('编辑器「存为模板」：把草稿存下来，名字可改', (tester) async {
    final repo = await _pump(tester, const ScheduleEditorScreen(scheduleId: 7));

    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pumpAndSettle();

    // 弹窗里改名再存
    await tester.enterText(
        find.descendant(of: find.byType(GlassDialog), matching: find.byType(TextField)),
        '炼油三部 · 零点班');
    await tester.tap(find.descendant(
        of: find.byType(GlassDialog), matching: find.text(L10n.save)));
    await tester.pumpAndSettle();

    final saved = repo.savedTemplate;
    expect(saved, isNotNull);
    expect(saved!.name, '炼油三部 · 零点班');
    expect(saved.cycle, [0, 0, 1, 1, 1]);
    expect(saved.teamCount, 5);
    expect(saved.teamOffsets, [0, 2, 4, 6, 8],
        reason: '我们班组是第 0 位，错位归零后其余按原间隔排');
    expect(saved.classes.map((c) => c.name), ['白班', '休班']);
  });

  testWidgets('选择页：多出「我的模板」一组，点它返回一个 saved 选择', (tester) async {
    await _pump(tester, const ShiftTemplatePickerScreen(),
        initial: [_template(name: '我的零点班')]);

    expect(find.text(L10n.myTemplates), findsOneWidget);
    expect(find.text('我的零点班'), findsOneWidget);
    expect(find.text(L10n.savedTemplateSubtitle(5, 5)), findsOneWidget);

    // 一条都没有时，整组不出现（首启的用户看不到空分组）
    await _pump(tester, const ShiftTemplatePickerScreen());
    expect(find.text(L10n.myTemplates), findsNothing);
  });

  testWidgets('用「我的模板」建方案：班次 / 周期 / 错位 / 名字都来自模板', (tester) async {
    final repo = await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Consumer(builder: (context, ref, _) {
            return ElevatedButton(
              onPressed: () => createScheduleFromTemplatePicker(context, ref,
                  makeCurrent: true),
              child: const Text('new'),
            );
          }),
        ),
      ),
      initial: [_template(name: '我的零点班')],
    );

    await tester.tap(find.text('new'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的零点班'));
    await tester.pumpAndSettle();

    expect(repo.createdName, '我的零点班', reason: '新方案直接用模板名');
    expect(repo.createdCycle, [0, 0, 1, 1, 1]);
    expect(repo.createdTeamCount, 5);
    expect(repo.createdOffsets, [0, 2, 4, 6, 8],
        reason: '错位在存模板时已归一化，建方案时原样装上');
    expect(repo.createdClasses.map((c) => c.name), ['白班', '休班']);
  });

  testWidgets('管理：改名与删除都落到仓库，卡片跟着变', (tester) async {
    final repo = await _pump(tester, const ShiftTemplatePickerScreen(),
        initial: [_template(name: '旧名字')]);

    await tester.tap(find.text(L10n.manageTemplates));
    await tester.pumpAndSettle();
    // 卡片上也有同样的名字，所以点的是弹窗里那一行
    await tester.tap(find.descendant(
        of: find.byType(GlassDialog), matching: find.text('旧名字')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.descendant(of: find.byType(GlassDialog), matching: find.byType(TextField)),
        '新名字');
    await tester.tap(find.descendant(
        of: find.byType(GlassDialog), matching: find.text(L10n.save)));
    await tester.pumpAndSettle();

    expect(repo.renamedTo, '新名字');
    expect(find.text('新名字'), findsOneWidget, reason: '改名后卡片要跟着变');
    expect(find.text('旧名字'), findsNothing);

    // 删掉：确认之后卡片消失
    await tester.tap(find.text(L10n.manageTemplates));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(GlassDialog), matching: find.byType(GlassDeleteButton)));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(GlassDialog), matching: find.text(L10n.delete)));
    await tester.pumpAndSettle();

    expect(repo.deletedId, 1);
    expect(find.text('新名字'), findsNothing);
    expect(find.text(L10n.myTemplates), findsNothing, reason: '一条不剩时整组收起');
  });

  testWidgets('回归：先开过选择页（那时还没有模板），存完再回来必须看得到', (tester) async {
    // 2026-09-21 用户反馈「我保存模板后，没看到呀」：第一次读的结果被
    // FutureProvider 缓存了一整个会话，之后存下的模板要重启 App 才出现。
    // savedTemplatesProvider 因此改成 autoDispose（见它的说明）。
    final raw = sqlite3.sqlite3.openInMemory();
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);
    final repo = _FakeRepo(db, domain: _domain());

    Widget picker() => ProviderScope(
          overrides: [appRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: ShiftTemplatePickerScreen()),
        );
    Widget elsewhere() => ProviderScope(
          overrides: [appRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: Scaffold()),
        );

    await tester.pumpWidget(picker());
    await tester.pumpAndSettle();
    expect(find.text(L10n.myTemplates), findsNothing, reason: '这时还没有模板');

    // 离开选择页，期间存下一份（等价于在编辑器里点「存为模板」）
    await tester.pumpWidget(elsewhere());
    await tester.pumpAndSettle();
    await repo.saveTemplate(_template(id: 9, name: '刚存的模板'));

    await tester.pumpWidget(picker());
    await tester.pumpAndSettle();
    expect(find.text(L10n.myTemplates), findsOneWidget,
        reason: '回到选择页必须重新读，不能拿上一次的缓存');
    expect(find.text('刚存的模板'), findsOneWidget);
  });
}
