// app/test/recurring_unlink_test.dart
//
// 「以后不再重复」解绑后，当前那一行变成一次性待办。
//
// 新模型下行日期 = 发生日（班次那天），而一次性提醒走
// `eventReminderTime = 行日期 + 钟点`，不看 `alarmDayAnchor`。所以解绑时必须把
// 行日期改到**提醒落地日**，否则夜班 02:00 的待办会提前 24 小时响。
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

void main() {
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
    await repo.saveSchedule(
      name: '夜班轮转',
      anchorDate: DateTime(2026, 9, 23),
      classes: const [
        ShiftClass(name: '夜班', abbr: '夜', startMinute: 1230, endMinute: 510),
        ShiftClass(name: '休班', abbr: '休', isRest: true),
      ],
      cycle: const [0, 1],
      makeCurrent: true,
      teamCount: 1,
      teamNames: const ['我'],
      ourTeamIndex: 0,
      teamOffsets: const [0],
    );
  });
  tearDown(() => db.close());

  test('夜班 02:00 的系列解绑后，一次性提醒仍在次日 02:00', () async {
    final sid = await repo.addRecurringTodo(
      title: '写台账',
      repeat: RecurRepeat.shift,
      startDate: DateTime(2026, 9, 23),
      shiftNames: const ['夜班'],
      timeMinute: 2 * 60,
      advanceRemindMinutes: 0,
    );
    await repo.advanceRecurringTodos(today: DateTime(2026, 9, 23));
    await repo.unlinkRecurringSeries(sid);

    final row = (await repo.listEvents()).single;
    expect(row.seriesId, isNull);
    expect(AlarmService.eventReminderTime(row), DateTime(2026, 9, 24, 2, 0),
        reason: '解绑不能把提醒挪 24 小时');
  });
}
