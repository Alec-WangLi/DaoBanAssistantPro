// app/test/calendar_day_extra_test.dart
//
// 从日历走完整条请假链路：信息卡 → 调整班次 → 请假 → 确定 → 落库 + 当天卡片出现
// 「请假 N小时」→ 再打开可清除。这是「整天请假」那条边界在界面上的回归。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/day_extra.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

import 'support/fixed_clock.dart';
import 'support/calendar_test_support.dart';

String _shiftLine(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('info-card-shift-line')))
    .textSpan!
    .toPlainText();

Future<void> _openLeave(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('info-card-shift-entry')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('shift-override-leave')));
  await tester.pumpAndSettle();
}

void main() {
  useFixedNow();
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('请假整天：落库为当天班次时长，信息卡出现「请假 N小时」', (tester) async {
    final db = await pumpCalendar(tester, 'day_night_rest_rest');
    final day = dayNumber(DateTime(2026, 10, 15));

    await _openLeave(tester);
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();

    final extras = await AppRepository(db).listDayExtras();
    expect(extras[day]!.leaveMinutes, 720,
        reason: 'anchor 那天是 08:30–20:30 的白班，整天请假 = 720 分钟');
    expect(_shiftLine(tester), contains(L10n.extraLeaveLine(720)));

    await disposeCalendar(tester);
  });

  testWidgets('已有请假记录时可以清除', (tester) async {
    final db = await pumpCalendar(tester, 'day_night_rest_rest');
    final day = dayNumber(DateTime(2026, 10, 15));
    await AppRepository(db).setDayExtra(day, DayExtraKind.leave, 240);
    await tester.pumpAndSettle();

    await _openLeave(tester);
    await tester.tap(find.text(L10n.clear));
    await tester.pumpAndSettle();

    final extras = await AppRepository(db).listDayExtras();
    expect(extras[day], isNull);
    expect(_shiftLine(tester), isNot(contains(L10n.extraLeaveLine(240))));

    await disposeCalendar(tester);
  });
}
