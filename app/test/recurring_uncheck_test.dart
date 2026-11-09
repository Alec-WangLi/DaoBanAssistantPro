// app/test/recurring_uncheck_test.dart
//
// 「勾错了 → 撤销 / 取消勾选」之后，那一次的提醒必须回来。
//
// 排提醒现在读 `skipThrough`（打勾 / 删掉都会写它）。如果取消勾选不清水位线，
// 用户看到的是：勾错了、点撤销，行回来了，但提醒永远不响 —— 一个不报错的洞。
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/data/app_database.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/fixed_clock.dart';

void main() {
  useFixedNow();

  setUpAll(() async {
    await initializeDateFormatting('zh');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late AppRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(
        NativeDatabase.opened(sqlite3.sqlite3.openInMemory()));
    repo = AppRepository(db);
    await repo.ensureSeeded();
  });
  tearDown(() => db.close());

  test('勾上再取消：水位线清掉，计划里那一次回来', () async {
    await repo.addRecurringTodo(
      title: '每天晚上写台账',
      repeat: RecurRepeat.daily,
      startDate: dateOnly(kAnchor),
      timeMinute: 23 * 60,
      advanceRemindMinutes: 0,
    );
    await repo.advanceRecurringTodos(today: dateOnly(kAnchor));
    final row = (await repo.listEvents()).single;
    final from = DateTime(kAnchor.year, kAnchor.month, kAnchor.day, 8);

    await repo.setEventCompleted(row, true);
    var series = (await repo.listRecurringTodos()).single;
    expect(series.skipThrough, dayNumber(dateOnly(kAnchor)));
    var plans = planRecurringReminders([series], from: from);
    expect(plans.single.fireAt,
        DateTime(kAnchor.year, kAnchor.month, kAnchor.day + 1, 23));

    await repo.setEventCompleted(row, false);
    series = (await repo.listRecurringTodos()).single;
    expect(series.skipThrough, isNull, reason: '取消勾选要把这一次的水位线撤掉');
    plans = planRecurringReminders([series], from: from);
    expect(plans.single.fireAt,
        DateTime(kAnchor.year, kAnchor.month, kAnchor.day, 23),
        reason: '撤销之后提醒要回来');
  });
}
