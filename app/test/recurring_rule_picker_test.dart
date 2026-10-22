// app/test/recurring_rule_picker_test.dart
//
// 规则选择器（五档 + 按班次 chips）的独立用例。
//
// 走整页（`ScheduleScreen`）的用例在 `recurring_dialog_test.dart`；这里只钉控件
// 自己的行为：五档都画得出来、切到按班次会列出班次、缺名与无班次各有提示。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/schedule/recurring_fields.dart';

ShiftClass _cls(String name) => ShiftClass(
      name: name,
      abbr: name.substring(0, 1),
      startMinute: 480,
      endMinute: 1200,
    );

/// 有状态的宿主：选择器自己不持有状态，点一下要由父层重建 —— 真界面里是
/// 弹窗的 `setState`，测试里就用这个。
class _Host extends StatefulWidget {
  const _Host({
    required this.initial,
    required this.choices,
    this.fallbackShiftName,
    this.validationMessage,
    this.onValue,
  });

  final RecurRuleValue initial;
  final List<ShiftClass> choices;
  final String? fallbackShiftName;
  final String? validationMessage;
  final ValueChanged<RecurRuleValue>? onValue;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late RecurRuleValue value = widget.initial;

  @override
  Widget build(BuildContext context) => RecurringRulePicker(
        value: value,
        shiftChoices: widget.choices,
        fallbackDay: DateTime(2026, 9, 23),
        fallbackShiftName: widget.fallbackShiftName,
        validationMessage: widget.validationMessage,
        onChanged: (v) {
          setState(() => value = v);
          widget.onValue?.call(v);
        },
      );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() => L10n.locale = 'zh');

  testWidgets('五档都在；切到按班次后列出班次，点一下回传名字', (tester) async {
    RecurRuleValue? out;
    await _pump(
      tester,
      _Host(
        initial: const RecurRuleValue(repeat: RecurRepeat.daily),
        choices: [_cls('白班'), _cls('上夜班')],
        fallbackShiftName: '白班',
        onValue: (v) => out = v,
      ),
    );

    for (final label in [
      L10n.repeatNone,
      L10n.repeatDaily,
      L10n.repeatWeekly,
      L10n.repeatMonthly,
      L10n.repeatShift,
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text(L10n.repeatShift));
    await tester.pumpAndSettle();
    expect(find.text('白班'), findsOneWidget);
    expect(find.text('上夜班'), findsOneWidget);
    expect(find.text(L10n.shiftRuleHint), findsOneWidget);
    // 切过来默认勾当天班次（fallbackShiftName）。
    expect(out!.shiftNames, ['白班']);

    await tester.tap(find.text('上夜班'));
    await tester.pumpAndSettle();
    expect(out!.shiftNames, containsAll(<String>['白班', '上夜班']));
  });


  testWidgets('每月多选 1 与 15；点掉最后一天不生效', (tester) async {
    RecurRuleValue? out;
    await _pump(
      tester,
      _Host(
        initial: const RecurRuleValue(repeat: RecurRepeat.monthly, monthDays: 1),
        choices: const [],
        onValue: (v) => out = v,
      ),
    );
    expect(find.text(L10n.monthDaysHint), findsOneWidget);

    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    expect(out!.monthDays, (1 << 0) | (1 << 14));

    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(out!.monthDays, 1 << 14);

    // 最后一个已选项不许被点掉（空月日 = 永不触发，而界面上看不出来）。
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    expect(out!.monthDays, 1 << 14);
  });

  testWidgets('切到每月且一天都没选：默认勾当天', (tester) async {
    RecurRuleValue? out;
    await _pump(
      tester,
      _Host(
        initial: const RecurRuleValue(repeat: RecurRepeat.daily, monthDays: 0),
        choices: const [],
        onValue: (v) => out = v,
      ),
    );
    await tester.tap(find.text(L10n.repeatMonthly));
    await tester.pumpAndSettle();
    // fallbackDay 是 2026-09-23 → 第 23 天。
    expect(out!.monthDays, 1 << 22);
  });
  testWidgets('一个班次都没有：给指路；校验提示可见', (tester) async {
    await _pump(
      tester,
      _Host(
        initial: const RecurRuleValue(repeat: RecurRepeat.shift),
        choices: const [],
        validationMessage: L10n.ruleNeedsShift,
      ),
    );
    expect(find.text(L10n.shiftRuleNoSchedule), findsOneWidget);
    expect(find.text(L10n.ruleNeedsShift), findsOneWidget);
  });

  testWidgets('选中的班次在当前排班表里找不到：仍然显示，并给出缺名提示', (tester) async {
    await _pump(
      tester,
      _Host(
        initial: const RecurRuleValue(
            repeat: RecurRepeat.shift, shiftNames: ['旧夜班']),
        choices: [_cls('白班')],
        fallbackShiftName: '白班',
      ),
    );
    expect(find.text('旧夜班'), findsOneWidget);
    expect(find.text(L10n.shiftRuleMissing(['旧夜班'])), findsOneWidget);
  });
}
