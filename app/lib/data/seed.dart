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

  final classIds = <int>[];
  for (var i = 0; i < sched.classes.length; i++) {
    final c = sched.classes[i];
    final classId = await db.into(db.shiftClassRows).insert(
          ShiftClassRowsCompanion.insert(
            scheduleId: id,
            order: i,
            name: c.name,
            abbr: Value(c.abbr),
            startMinute: Value(c.startMinute),
            endMinute: Value(c.endMinute),
            isRest: Value(c.isRest),
            color: Value(c.color),
            alarmEnabled: Value(c.alarmEnabled),
          ),
        );
    classIds.add(classId);
    // 闹钟落进 v10 那张表；顺序即列表顺序（= 原生 id 的「序号」）。
    for (var k = 0; k < c.alarms.length; k++) {
      await db.into(db.shiftClassAlarms).insert(
            ShiftClassAlarmsCompanion.insert(
              classId: classId,
              order: k,
              minute: c.alarms[k].minute,
              label: Value(c.alarms[k].label),
            ),
          );
    }
  }
  for (var i = 0; i < sched.cycle.length; i++) {
    await db.into(db.shiftCycleRows).insert(
          ShiftCycleRowsCompanion.insert(
            scheduleId: id,
            order: i,
            classId: classIds[sched.cycle[i]],
          ),
        );
  }
}
