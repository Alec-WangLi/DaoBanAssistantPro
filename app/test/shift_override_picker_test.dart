// app/test/shift_override_picker_test.dart
//
// 「调整班次」选择层：列全本方案的班次定义、当前值打勾、可选「恢复轮转」。
// 本机没有可运行目标，界面行为全靠 widget 测试覆盖。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/calendar/shift_override_picker.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
  });

  Future<ShiftOverrideChoice?> pumpPicker(
    WidgetTester tester, {
    ShiftSchedule? schedule,
    ShiftClass? current,
    bool canRestore = false,
  }) async {
    ShiftOverrideChoice? result;
    // 打勾走 `identical` 判等，所以想给 `current` 的用例**必须**把自己那份
    // schedule 一起传进来：默认这份是每次调用新造的，从中取不到「同一实例」的
    // 班次，`current` 会静默不打勾。
    final s = schedule ?? defaultSchedule();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showShiftOverridePicker(
                  context,
                  schedule: s,
                  from: DateTime(2026, 9, 18),
                  to: DateTime(2026, 9, 20),
                  canRestore: canRestore,
                  currentClass: current,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('列出本方案全部班次定义', (tester) async {
    await pumpPicker(tester);
    for (final c in defaultSchedule().classes) {
      expect(find.text(c.name), findsOneWidget, reason: '${c.name} 应当可选');
    }
  });

  testWidgets('多日时标题写「起 – 止 · N 天」', (tester) async {
    await pumpPicker(tester);
    expect(find.textContaining('3 天'), findsOneWidget);
  });

  testWidgets('选中一项后返回「改成这个班次」', (tester) async {
    final schedule = defaultSchedule();
    ShiftOverrideChoice? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showShiftOverridePicker(
                  context,
                  schedule: schedule,
                  from: DateTime(2026, 9, 18),
                  to: DateTime(2026, 9, 18),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(schedule.classes[3].name));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.restore, isFalse);
    expect(result!.shift!.name, schedule.classes[3].name);
  });

  testWidgets('当前班次那一行打勾，且只打那一行', (tester) async {
    final schedule = defaultSchedule();
    final current = schedule.classes[2];
    await pumpPicker(tester, schedule: schedule, current: current);

    // 有且只有一处勾 —— 「每行都打」与「一行都不打」这两种实现都在这里红。
    expect(find.byIcon(Icons.check), findsOneWidget);

    // 勾落在当前班次那一行：承载勾的那个 ListTile 里应当写着这一项的名字 ——
    // 「打错行」的实现（比如恒打首行 / 恒打末行）在这里红。
    final currentRow = find.ancestor(
      of: find.byIcon(Icons.check),
      matching: find.byType(ListTile),
    );
    expect(currentRow, findsOneWidget);
    expect(find.descendant(of: currentRow, matching: find.text(current.name)),
        findsOneWidget);

    // 其余每一行都不带勾。
    for (final c in schedule.classes) {
      if (identical(c, current)) continue;
      final otherRow = find.ancestor(
        of: find.text(c.name),
        matching: find.byType(ListTile),
      );
      expect(find.descendant(of: otherRow, matching: find.byIcon(Icons.check)),
          findsNothing, reason: '${c.name} 不该打勾');
    }
  });

  testWidgets('canRestore 为假时不出现「恢复轮转」', (tester) async {
    await pumpPicker(tester);
    expect(find.text(L10n.restoreRotation), findsNothing);
  });

  testWidgets('canRestore 为真时出现且返回「恢复轮转」', (tester) async {
    final schedule = defaultSchedule();
    ShiftOverrideChoice? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showShiftOverridePicker(
                  context,
                  schedule: schedule,
                  from: DateTime(2026, 9, 18),
                  to: DateTime(2026, 9, 18),
                  canRestore: true,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(L10n.restoreRotation), findsOneWidget);

    await tester.tap(find.text(L10n.restoreRotation));
    await tester.pumpAndSettle();
    expect(result!.restore, isTrue);
  });
}
