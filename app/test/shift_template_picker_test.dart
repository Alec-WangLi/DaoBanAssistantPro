// app/test/shift_template_picker_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';
import 'package:shiftassistantpro/features/calendar/schedule_management_screen.dart';
import 'package:shiftassistantpro/features/calendar/shift_template_picker_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 记录是否有人调过 saveSchedule —— 用来验证「放弃选择」不会落库，
/// 并记下创建路径传下来的班组名。
class _RecordingRepository extends AppRepository {
  _RecordingRepository(super.db);

  int saveCalls = 0;
  int lastTeamCount = 0;
  List<String> lastTeamNames = const [];

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
    saveCalls++;
    lastTeamCount = teamCount;
    lastTeamNames = List.of(teamNames);
    return 1;
  }
}

/// 从一个宿主页 push 选择页，并把 pop 的返回值收进 [results]。
Future<void> _openPicker(WidgetTester tester, List<Object?> results) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              results.add(await Navigator.of(context).push<ShiftTemplateChoice>(
                MaterialPageRoute(
                    builder: (_) => const ShiftTemplatePickerScreen()),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  // 管理页用 L10n.monthDay（intl DateFormat 'zh'）渲染日期，测试里要自己初始化。
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
  });

  test('每个模板的 groupKey 都在分组列表里，不会静默消失', () {
    // 选择页按 shiftTemplateGroups 分组渲染：键写错会让该模板
    // 从「选择你的倒班方式」页上无声消失。
    for (final t in shiftTemplates) {
      expect(shiftTemplateGroups, contains(t.groupKey),
          reason: '模板 ${t.id} 的 groupKey「${t.groupKey}」不在分组列表里，会被静默丢弃');
    }
    for (final g in shiftTemplateGroups) {
      expect(shiftTemplates.any((t) => t.groupKey == g), isTrue,
          reason: '分组「$g」没有任何模板，分组标题永远不会出现');
    }
  });

  testWidgets('首屏列出模板卡片', (tester) async {
    await _openPicker(tester, <Object?>[]);
    expect(find.text(L10n.pickShiftPattern), findsOneWidget);
    expect(find.text(shiftTemplates.first.title), findsOneWidget);
  });

  testWidgets('搜索「四班三倒」只剩匹配卡片', (tester) async {
    await _openPicker(tester, <Object?>[]);
    await tester.enterText(find.byType(TextField), '四班三倒');
    await tester.pumpAndSettle();

    final target = findTemplate('four_crew_three_shift')!;
    expect(find.text(target.title), findsOneWidget);
    // 不相关的卡片被过滤掉。
    expect(find.text(shiftTemplates.first.title), findsNothing);
    expect(find.text('DuPont · 28 天周期'), findsNothing);
    // 「我自己排」始终在。
    expect(find.text(L10n.customPattern), findsOneWidget);
  });

  testWidgets('搜不到时显示空状态，「我自己排」仍在', (tester) async {
    await _openPicker(tester, <Object?>[]);
    await tester.enterText(find.byType(TextField), 'zzzzzz');
    await tester.pumpAndSettle();
    expect(find.text(L10n.noPatternMatch), findsOneWidget);
    expect(find.text(L10n.customPattern), findsOneWidget);
  });

  testWidgets('点模板卡片返回携带该模板的 ShiftTemplateChoice', (tester) async {
    final results = <Object?>[];
    await _openPicker(tester, results);
    await tester.tap(find.text(shiftTemplates.first.title));
    await tester.pumpAndSettle();

    final choice = results.single as ShiftTemplateChoice;
    expect(choice.template, same(shiftTemplates.first));
    expect(choice.custom, isFalse);
  });

  testWidgets('点「我自己排」返回 custom 选择', (tester) async {
    final results = <Object?>[];
    await _openPicker(tester, results);
    // 先过滤，把「我自己排」卡片带进首屏。
    await tester.enterText(find.byType(TextField), 'zzzzzz');
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.customPattern));
    await tester.pumpAndSettle();

    final choice = results.single as ShiftTemplateChoice;
    expect(choice.custom, isTrue);
    expect(choice.template, isNull);
  });

  testWidgets('「我自己排」与「按返回键放弃」不再无法区分', (tester) async {
    // 修复核心：过去两者都 pop(null)，调用方只能靠 null 判断，
    // 于是用户一按返回就会凭空多出一套排班。
    final custom = <Object?>[];
    await _openPicker(tester, custom);
    await tester.enterText(find.byType(TextField), 'zzzzzz');
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.customPattern));
    await tester.pumpAndSettle();

    final dismissed = <Object?>[];
    await _openPicker(tester, dismissed);
    await tester.pageBack(); // 系统返回键 / AppBar 返回。
    await tester.pumpAndSettle();

    expect(custom.single, isNotNull);
    expect(dismissed.single, isNull);
    expect(custom.single, isNot(dismissed.single));
  });

  testWidgets('按返回键放弃不会凭空多建一套排班', (tester) async {
    // 直接驱动 ScheduleManagementScreen._addSchedule，验证被放弃的选择
    // 既不落库、也不进编辑器。
    final raw = sqlite3.sqlite3.openInMemory();
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);
    final repo = _RecordingRepository(db);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appRepositoryProvider.overrideWithValue(repo),
        // 绕过真实数据流，让首帧直接有值（否则会卡在 loading 转圈）。
        schedulesProvider
            .overrideWith((ref) => Stream.value(const <ShiftScheduleRow>[])),
        activeScheduleProvider
            .overrideWith((ref) => Stream<ActiveSchedule?>.value(null)),
      ],
      child: const MaterialApp(home: ScheduleManagementScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text(L10n.addSchedule), findsOneWidget);

    await tester.tap(find.text(L10n.addSchedule));
    await tester.pumpAndSettle();
    expect(find.text(L10n.pickShiftPattern), findsOneWidget);

    await tester.pageBack(); // 系统返回键 / AppBar 返回。
    await tester.pumpAndSettle();

    expect(find.text(L10n.pickShiftPattern), findsNothing);
    expect(repo.saveCalls, 0, reason: '按返回键放弃后不应调用 saveSchedule');
  });

  testWidgets('多班组模板：创建路径给出完整长度、走 L10n 的班组名', (tester) async {
    // 模板只带 4 个默认班组名，而五班三倒 / 六班三倒 是 5~6 个班组。
    // 补位若落到数据库出口（app_repository 的兜底分支），英文界面下
    // 用户就会看到「五班」「六班」。
    final prev = L10n.locale;
    L10n.locale = 'en';
    addTearDown(() => L10n.locale = prev);

    final raw = sqlite3.sqlite3.openInMemory();
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);
    final repo = _RecordingRepository(db);

    await tester.pumpWidget(ProviderScope(
      overrides: [appRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => createScheduleFromTemplatePicker(context, ref,
                    makeCurrent: false),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '六班三倒');
    await tester.pumpAndSettle();
    final six = findTemplate('six_crew_three_shift')!;
    await tester.tap(find.text(six.title));
    await tester.pumpAndSettle();

    expect(repo.saveCalls, 1);
    expect(repo.lastTeamCount, 6);
    expect(repo.lastTeamNames, hasLength(6),
        reason: '班组名必须给满 teamCount 个，不能只给 4 个再靠兜底补位');
    expect(repo.lastTeamNames.any((n) => n.contains('班')), isFalse,
        reason: '英文界面下不该出现中文班组名');
  });

  test('每个分组标题都有英文映射，不会原样露出中文键', () {
    // 上面的 widget 测试只能看到「已经构建出来」的那几个分组（长列表懒构建），
    // 这里直接对映射函数本身全覆盖。
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);
    L10n.locale = 'en';
    for (final g in shiftTemplateGroups) {
      expect(L10n.templateGroup(g), isNot(g),
          reason: '分组「$g」没有英文映射，英文界面会原样露出中文');
    }
  });

  testWidgets('英文界面：分组标题跟着语言走，不露出中文', (tester) async {
    // 分组在数据层是语言无关键（`ShiftTemplate.groupKey`），显示层靠
    // L10n.templateGroup 映射；漏掉任何一支，英文界面上就会原样冒出中文标题。
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);
    L10n.locale = 'en';

    await _openPicker(tester, <Object?>[]);

    for (final group in shiftTemplateGroups) {
      expect(find.text(group), findsNothing,
          reason: '英文界面下的分组标题「$group」应该换成英文');
    }
    expect(find.text(L10n.templateGroup(shiftTemplateGroups.first)),
        findsOneWidget);
  });

  test('分组键是语言无关键，且中英都有显示名', () {
    // 键本身不该被当成显示名露出去 —— 英文界面上冒出一个「h12」，
    // 中文界面上冒出原样的键，都是同一类缺陷。
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);

    for (final locale in ['zh', 'en']) {
      L10n.locale = locale;
      for (final key in shiftTemplateGroups) {
        expect(L10n.templateGroup(key), isNot(key),
            reason: '分组键「$key」在 $locale 下没有显示名，会原样露出');
        expect(L10n.templateGroup(key).trim(), isNotEmpty,
            reason: '分组键「$key」在 $locale 下显示名为空');
      }
    }
  });
}
