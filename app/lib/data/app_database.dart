import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// 排班方案表（一套轮换周期 + 班组）。
class ShiftScheduleRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get anchorDate => dateTime()();
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();

  // 班组（四班两倒 = 4 个班错开）
  IntColumn get teamCount => integer().withDefault(const Constant(4))();
  TextColumn get teamNames =>
      text().withDefault(const Constant('一班,二班,三班,四班'))();
  IntColumn get ourTeamIndex => integer().withDefault(const Constant(0))();

  // 每个班组在锚点日的班次下标（逗号分隔，如 "0,1,2,3"）
  TextColumn get teamOffsets => text().withDefault(const Constant(''))();
}

/// 班次类型表（属于某套排班方案，按 order 排序成周期）。
class ShiftTypeRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get scheduleId => integer()();
  IntColumn get order => integer()();
  TextColumn get name => text()();
  IntColumn get startMinute => integer().nullable()();
  IntColumn get endMinute => integer().nullable()();
  BoolColumn get isRest => boolean().withDefault(const Constant(false))();
  IntColumn get color => integer().withDefault(const Constant(0xFF5B7FFF))();
  BoolColumn get alarmEnabled => boolean().withDefault(const Constant(false))();
  IntColumn get alarmMinute => integer().nullable()();
}

/// 日程事件表。
class ScheduleEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  DateTimeColumn get date => dateTime()();
  IntColumn get timeMinute => integer().nullable()();
  IntColumn get advanceRemindMinutes => integer().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
}

/// 自定义闹钟表（独立于排班）。
class CustomAlarms extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get hour => integer()();
  IntColumn get minute => integer()();

  /// 0=一次性，1=每天，2=每周。
  IntColumn get repeatType => integer().withDefault(const Constant(1))();

  /// 一次性闹钟的日期（repeatType=0 时用）。
  DateTimeColumn get onceDate => dateTime().nullable()();

  /// 每周重复的星期几位掩码（1<<(weekday-1)），repeatType=2 时用。
  IntColumn get weekdays => integer().withDefault(const Constant(0))();

  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
}

/// 班次闹钟「按天覆盖」表：用户可对某一天单独开关班次闹钟。
///
/// [day] 为纯日期自 epoch 的天数（UTC），作主键；[enabled] 覆盖该天班次类型
/// 默认的 alarmEnabled。无记录 = 跟随班次类型默认设置。
class ShiftAlarmOverrides extends Table {
  IntColumn get day => integer()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {day};
}

@DriftDatabase(tables: [
  ShiftScheduleRows,
  ShiftTypeRows,
  ScheduleEvents,
  CustomAlarms,
  ShiftAlarmOverrides,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'shiftassistantpro'));

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 5) {
            await m.createTable(shiftAlarmOverrides);
          }
          if (from < 4) {
            await m.addColumn(shiftScheduleRows, shiftScheduleRows.teamOffsets);
          }
          if (from < 3) {
            await m.createTable(customAlarms);
          }
          if (from < 2) {
            // 1) shift_type_rows 去掉 3 列（提前提醒/贪睡）：重建表
            await customStatement(
                'ALTER TABLE shift_type_rows RENAME TO shift_type_rows_old');
            await m.createTable(shiftTypeRows);
            await customStatement(
              'INSERT INTO shift_type_rows (id, schedule_id, "order", name, '
              'start_minute, end_minute, is_rest, color, alarm_enabled, alarm_minute) '
              'SELECT id, schedule_id, "order", name, start_minute, end_minute, '
              'is_rest, color, alarm_enabled, alarm_minute FROM shift_type_rows_old',
            );
            await customStatement('DROP TABLE shift_type_rows_old');

            // 2) shift_schedule_rows 加 3 个班组列
            await m.addColumn(shiftScheduleRows, shiftScheduleRows.teamCount);
            await m.addColumn(shiftScheduleRows, shiftScheduleRows.teamNames);
            await m.addColumn(
                shiftScheduleRows, shiftScheduleRows.ourTeamIndex);
          }
        },
      );
}
