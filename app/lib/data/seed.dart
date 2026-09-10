import 'package:drift/drift.dart';

import '../domain/shift_rotation.dart';
import 'app_database.dart';

/// 首次启动：若无任何排班方案，写入默认「四班两倒」。
Future<void> seedIfEmpty(AppDatabase db) async {
  final existing = await db.select(db.shiftScheduleRows).get();
  if (existing.isNotEmpty) return;

  final sched = defaultSchedule();
  final id = await db.into(db.shiftScheduleRows).insert(
        ShiftScheduleRowsCompanion.insert(
          name: sched.name,
          anchorDate: sched.anchorDate,
          isCurrent: const Value(true),
          teamCount: Value(sched.teamCount),
          teamNames: Value(sched.teamNames.join(',')),
          ourTeamIndex: Value(sched.ourTeamIndex),
          teamOffsets: Value(sched.teamOffsets.join(',')),
        ),
      );

  for (var i = 0; i < sched.cycle.length; i++) {
    final t = sched.classes[sched.cycle[i]];
    await db.into(db.shiftTypeRows).insert(
          ShiftTypeRowsCompanion.insert(
            scheduleId: id,
            order: i,
            name: t.name,
            startMinute: Value(t.startMinute),
            endMinute: Value(t.endMinute),
            isRest: Value(t.isRest),
            color: Value(t.color),
            alarmEnabled: Value(t.alarmEnabled),
            alarmMinute: Value(t.alarmMinute),
          ),
        );
  }
}
