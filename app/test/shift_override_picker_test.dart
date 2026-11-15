// app/test/shift_override_picker_test.dart
//
// 「调整班次」弹层新增的两行动作：请假 / 加班。它们不是班次，返回的是 intent。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/calendar/shift_override_picker.dart';

final _schedule = ShiftSchedule(
  name: '测试',
  anchorDate: DateTime.utc(2026, 11, 1),
  classes: const [
    ShiftClass(
        name: '白班',
        abbr: '白',
        startMinute: 8 * 60,
        endMinute: 20 * 60),
    ShiftClass(name: '休息', abbr: '休', isRest: true),
  ],
  cycle: const [0, 1],
  teamCount: 1,
  teamNames: const ['我'],
  teamOffsets: const [0],
);

Future<void> _pumpHost(
  WidgetTester tester, {
  required void Function(ShiftOverrideChoice?) onResult,
  Size size = const Size(420, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final r = await showShiftOverridePicker(
              context,
              schedule: _schedule,
              from: DateTime(2026, 11, 12),
              to: DateTime(2026, 11, 12),
            );
            onResult(r);
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
  });

  testWidgets('请假行返回 leave intent', (tester) async {
    ShiftOverrideChoice? result;
    await _pumpHost(tester, onResult: (r) => result = r);

    await tester.tap(find.byKey(const Key('shift-override-leave')));
    await tester.pumpAndSettle();

    expect(result!.intent, ShiftOverrideIntent.leave);
    expect(result!.shift, isNull);
    expect(result!.restore, isFalse);
  });

  testWidgets('加班行返回 overtime intent', (tester) async {
    ShiftOverrideChoice? result;
    await _pumpHost(tester, onResult: (r) => result = r);

    await tester.tap(find.byKey(const Key('shift-override-overtime')));
    await tester.pumpAndSettle();

    expect(result!.intent, ShiftOverrideIntent.overtime);
  });

  testWidgets('班次行仍返回 change，且两行动作同时在场', (tester) async {
    ShiftOverrideChoice? result;
    await _pumpHost(tester, onResult: (r) => result = r);

    expect(find.byKey(const Key('shift-override-leave')), findsOneWidget);
    expect(find.byKey(const Key('shift-override-overtime')), findsOneWidget);
    expect(find.text(L10n.leave), findsOneWidget);
    expect(find.text(L10n.overtime), findsOneWidget);

    await tester.tap(find.text('白班'));
    await tester.pumpAndSettle();
    expect(result!.intent, ShiftOverrideIntent.change);
    expect(result!.shift!.name, '白班');
  });

  testWidgets('320 宽：弹层不溢出', (tester) async {
    await _pumpHost(tester, size: const Size(320, 640), onResult: (_) {});
    expect(tester.takeException(), isNull);
  });
}
