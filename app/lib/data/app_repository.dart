import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/shift_rotation.dart';
import 'app_database.dart';
import 'seed.dart';

export 'app_database.dart';

List<String> parseTeamNames(String s) => s.split(',');

String joinTeamNames(List<String> names) => names.join(',');

List<int> parseTeamOffsets(String s) {
  if (s.trim().isEmpty) return const [];
  return s
      .split(',')
      .map((e) => int.tryParse(e.trim()) ?? 0)
      .toList();
}

String joinTeamOffsets(List<int> offsets) => offsets.join(',');

/// 活跃排班方案（当前方案行 + 有序班次行）。
class ActiveSchedule {
  const ActiveSchedule({required this.schedule, required this.shiftTypes});

  final ShiftScheduleRow schedule;
  final List<ShiftTypeRow> shiftTypes;

  ShiftSchedule toDomain() => ShiftSchedule(
        name: schedule.name,
        anchorDate: schedule.anchorDate,
        shiftTypes: shiftTypes.map((t) => t.toDomain()).toList(),
        teamCount: schedule.teamCount,
        teamNames: parseTeamNames(schedule.teamNames),
        ourTeamIndex: schedule.ourTeamIndex,
        teamOffsets: parseTeamOffsets(schedule.teamOffsets),
      );
}

extension ShiftTypeRowX on ShiftTypeRow {
  ShiftType toDomain() => ShiftType(
        order: order,
        name: name,
        startMinute: startMinute,
        endMinute: endMinute,
        isRest: isRest,
        color: color,
        alarmEnabled: alarmEnabled,
        alarmMinute: alarmMinute,
      );
}

extension AppDatabaseQueries on AppDatabase {
  /// 监听当前排班方案及其班次（响应式）。
  Stream<ActiveSchedule?> watchActiveSchedule() {
    final schedQuery = select(shiftScheduleRows)
      ..where((s) => s.isCurrent.equals(true));
    return schedQuery.watchSingleOrNull().asyncMap((sched) async {
      if (sched == null) return null;
      final types = await (select(shiftTypeRows)
            ..where((t) => t.scheduleId.equals(sched.id))
            ..orderBy([(t) => OrderingTerm.asc(t.order)]))
          .get();
      return ActiveSchedule(schedule: sched, shiftTypes: types);
    });
  }

  /// 监听全部日程（按日期+时间升序）。
  Stream<List<ScheduleEvent>> watchEvents() {
    final q = select(scheduleEvents)
      ..orderBy([
        (t) => OrderingTerm.asc(t.date),
        (t) => OrderingTerm.asc(t.timeMinute),
      ]);
    return q.watch();
  }
}

/// 数据访问仓库。
class AppRepository {
  AppRepository(this.db);

  final AppDatabase db;

  Future<void> ensureSeeded() => seedIfEmpty(db);

  /// 清空全部数据（排班方案 + 班次 + 日程 + 按天闹钟覆盖），并恢复默认「四班两倒」。
  Future<void> clearAll() async {
    await db.transaction(() async {
      await db.delete(db.scheduleEvents).go();
      await db.delete(db.shiftAlarmOverrides).go();
      await db.delete(db.shiftTypeRows).go();
      await db.delete(db.shiftScheduleRows).go();
    });
    await seedIfEmpty(db);
  }

  /// 所有排班方案（按 id 升序）。
  Future<List<ShiftScheduleRow>> listSchedules() {
    final q = db.select(db.shiftScheduleRows)
      ..orderBy([(t) => OrderingTerm.asc(t.id)]);
    return q.get();
  }

  /// 切换当前排班方案。
  Future<void> setCurrentSchedule(int id) async {
    await db.transaction(() async {
      await db.update(db.shiftScheduleRows).write(
            const ShiftScheduleRowsCompanion(isCurrent: Value(false)),
          );
      await (db.update(db.shiftScheduleRows)..where((s) => s.id.equals(id)))
          .write(const ShiftScheduleRowsCompanion(isCurrent: Value(true)));
    });
  }

  /// 取一套排班方案的完整领域模型（含班次）。
  Future<ShiftSchedule?> getScheduleDomain(int id) async {
    final row = await (db.select(db.shiftScheduleRows)
          ..where((s) => s.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    final types = await (db.select(db.shiftTypeRows)
          ..where((t) => t.scheduleId.equals(id))
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    return ActiveSchedule(schedule: row, shiftTypes: types).toDomain();
  }

  /// 立即读取当前方案领域模型（重排闹钟用，避免读 Riverpod 流拿到旧值）。
  Future<ShiftSchedule?> getActiveSchedule() async {
    final row = await (db.select(db.shiftScheduleRows)
          ..where((s) => s.isCurrent.equals(true)))
        .getSingleOrNull();
    if (row == null) return null;
    final types = await (db.select(db.shiftTypeRows)
          ..where((t) => t.scheduleId.equals(row.id))
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    return ActiveSchedule(schedule: row, shiftTypes: types).toDomain();
  }

  /// 删除一套排班方案（连带其班次），并保证始终有一套当前方案。
  Future<void> deleteSchedule(int id) async {
    await db.transaction(() async {
      await (db.delete(db.shiftTypeRows)
            ..where((t) => t.scheduleId.equals(id)))
          .go();
      await (db.delete(db.shiftScheduleRows)..where((s) => s.id.equals(id)))
          .go();
    });
    final remaining = await listSchedules();
    if (remaining.isEmpty) {
      await seedIfEmpty(db);
    } else if (!remaining.any((s) => s.isCurrent)) {
      await setCurrentSchedule(remaining.first.id);
    }
  }

  /// 保存（新建或更新）一套排班方案并替换其班次。
  Future<int> saveSchedule({
    int? scheduleId,
    required String name,
    required DateTime anchorDate,
    required List<ShiftType> types,
    bool makeCurrent = true,
    int teamCount = 4,
    List<String> teamNames = const ['一班', '二班', '三班', '四班'],
    int ourTeamIndex = 0,
    List<int> teamOffsets = const [],
  }) {
    return db.transaction(() async {
      late int id;
      if (scheduleId == null) {
        id = await db.into(db.shiftScheduleRows).insert(
              ShiftScheduleRowsCompanion.insert(
                name: name,
                anchorDate: anchorDate,
                isCurrent: const Value(true),
                teamCount: Value(teamCount),
                teamNames: Value(joinTeamNames(teamNames)),
                ourTeamIndex: Value(ourTeamIndex),
                teamOffsets: Value(joinTeamOffsets(teamOffsets)),
              ),
            );
      } else {
        id = scheduleId;
        await (db.update(db.shiftScheduleRows)
              ..where((s) => s.id.equals(id)))
            .write(ShiftScheduleRowsCompanion(
          name: Value(name),
          anchorDate: Value(anchorDate),
          teamCount: Value(teamCount),
          teamNames: Value(joinTeamNames(teamNames)),
          ourTeamIndex: Value(ourTeamIndex),
          teamOffsets: Value(joinTeamOffsets(teamOffsets)),
        ));
      }

      if (makeCurrent) {
        await db.update(db.shiftScheduleRows).write(
              const ShiftScheduleRowsCompanion(isCurrent: Value(false)),
            );
        await (db.update(db.shiftScheduleRows)
              ..where((s) => s.id.equals(id)))
            .write(const ShiftScheduleRowsCompanion(isCurrent: Value(true)));
      }

      // 重建班次
      await (db.delete(db.shiftTypeRows)
            ..where((t) => t.scheduleId.equals(id)))
          .go();
      for (final t in types) {
        await db.into(db.shiftTypeRows).insert(
              ShiftTypeRowsCompanion.insert(
                scheduleId: id,
                order: t.order,
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
      return id;
    });
  }

  Future<int> addEvent({
    required String title,
    required DateTime date,
    int? timeMinute,
    int? advanceRemindMinutes,
  }) {
    return db.into(db.scheduleEvents).insert(
          ScheduleEventsCompanion.insert(
            title: title,
            date: dateOnly(date),
            timeMinute: Value(timeMinute),
            advanceRemindMinutes: Value(advanceRemindMinutes),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> updateEvent(
    ScheduleEvent e, {
    required String title,
    required DateTime date,
    int? timeMinute,
    int? advanceRemindMinutes,
  }) {
    return (db.update(db.scheduleEvents)..where((r) => r.id.equals(e.id)))
        .write(ScheduleEventsCompanion(
      title: Value(title),
      date: Value(dateOnly(date)),
      timeMinute: Value(timeMinute),
      advanceRemindMinutes: Value(advanceRemindMinutes),
    ));
  }

  Future<void> setEventCompleted(ScheduleEvent e, bool done) {
    return (db.update(db.scheduleEvents)..where((r) => r.id.equals(e.id)))
        .write(ScheduleEventsCompanion(isCompleted: Value(done)));
  }

  Future<void> deleteEvent(ScheduleEvent e) {
    return (db.delete(db.scheduleEvents)..where((r) => r.id.equals(e.id)))
        .go();
  }

  Future<int> addCustomAlarm({
    required int hour,
    required int minute,
    required int repeatType,
    DateTime? onceDate,
    int weekdays = 0,
  }) {
    return db.into(db.customAlarms).insert(
          CustomAlarmsCompanion.insert(
            hour: hour,
            minute: minute,
            repeatType: Value(repeatType),
            onceDate: Value(onceDate),
            weekdays: Value(weekdays),
            enabled: const Value(true),
          ),
        );
  }

  Future<void> setCustomAlarmEnabled(CustomAlarm a, bool enabled) {
    return (db.update(db.customAlarms)..where((r) => r.id.equals(a.id)))
        .write(CustomAlarmsCompanion(enabled: Value(enabled)));
  }

  Future<void> updateCustomAlarm(
    CustomAlarm a, {
    required int hour,
    required int minute,
    required int repeatType,
    DateTime? onceDate,
    int weekdays = 0,
  }) {
    return (db.update(db.customAlarms)..where((r) => r.id.equals(a.id)))
        .write(CustomAlarmsCompanion(
      hour: Value(hour),
      minute: Value(minute),
      repeatType: Value(repeatType),
      onceDate: Value(onceDate),
      weekdays: Value(weekdays),
    ));
  }

  Future<void> deleteCustomAlarm(CustomAlarm a) {
    return (db.delete(db.customAlarms)..where((r) => r.id.equals(a.id))).go();
  }

  /// 立即读取当前全部自定义闹钟（重排闹钟用，避免读 Riverpod 流拿到旧值）。
  Future<List<CustomAlarm>> listCustomAlarms() {
    final q = db.select(db.customAlarms)
      ..orderBy([
        (t) => OrderingTerm.asc(t.hour),
        (t) => OrderingTerm.asc(t.minute),
      ]);
    return q.get();
  }

  /// 设置某天的班次闹钟开关覆盖（true=开，false=关）。
  Future<void> setShiftAlarmOverride(DateTime date, bool enabled) {
    return db
        .into(db.shiftAlarmOverrides)
        .insertOnConflictUpdate(ShiftAlarmOverridesCompanion.insert(
          day: Value(dayNumber(date)),
          enabled: Value(enabled),
        ));
  }

  /// 读取全部按天覆盖（day → enabled）。
  Future<Map<int, bool>> listShiftAlarmOverrides() async {
    final rows = await db.select(db.shiftAlarmOverrides).get();
    return {for (final r in rows) r.day: r.enabled};
  }

  /// 删除已响过的一次性自定义闹钟（fireAt 已过去）。
  Future<void> deleteExpiredOnceAlarms() async {
    final now = DateTime.now();
    final alarms = await listCustomAlarms();
    for (final a in alarms) {
      if (a.repeatType != 0 || a.onceDate == null) continue;
      final od = a.onceDate!;
      final fire = DateTime(od.year, od.month, od.day, a.hour, a.minute);
      if (fire.isBefore(now)) {
        await deleteCustomAlarm(a);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final appRepositoryProvider = Provider<AppRepository>((ref) {
  return AppRepository(ref.watch(databaseProvider));
});

final activeScheduleProvider = StreamProvider<ActiveSchedule?>((ref) async* {
  final db = ref.watch(databaseProvider);
  await seedIfEmpty(db);
  yield* db.watchActiveSchedule();
});

final schedulesProvider = StreamProvider<List<ShiftScheduleRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.shiftScheduleRows)
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .watch();
});

final eventsProvider = StreamProvider<List<ScheduleEvent>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchEvents();
});

final customAlarmsProvider = StreamProvider<List<CustomAlarm>>((ref) {
  final db = ref.watch(databaseProvider);
  final q = db.select(db.customAlarms)
    ..orderBy([
      (t) => OrderingTerm.asc(t.hour),
      (t) => OrderingTerm.asc(t.minute),
    ]);
  return q.watch();
});

final shiftAlarmOverridesProvider = StreamProvider<Map<int, bool>>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .select(db.shiftAlarmOverrides)
      .watch()
      .map((rows) => {for (final r in rows) r.day: r.enabled});
});
