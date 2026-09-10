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

/// 班次定义表：一个班次只定义一次（属于某套排班方案）。
class ShiftClassRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get scheduleId => integer()();
  IntColumn get order => integer()();
  TextColumn get name => text()();

  /// 日历格子里的 1~2 字简称；为空时按名称推断。
  TextColumn get abbr => text().nullable()();
  IntColumn get startMinute => integer().nullable()();
  IntColumn get endMinute => integer().nullable()();
  BoolColumn get isRest => boolean().withDefault(const Constant(false))();
  IntColumn get color => integer().withDefault(const Constant(0xFF5B7FFF))();
  BoolColumn get alarmEnabled => boolean().withDefault(const Constant(false))();
  IntColumn get alarmMinute => integer().nullable()();
}

/// 周期序列表：第 N 天用哪个班次定义。
class ShiftCycleRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get scheduleId => integer()();
  IntColumn get order => integer()();
  IntColumn get classId => integer()();
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
  ShiftClassRows,
  ShiftCycleRows,
  ScheduleEvents,
  CustomAlarms,
  ShiftAlarmOverrides,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'shiftassistantpro'));

  /// 测试专用：接外部注入的 QueryExecutor（内存库 / 迁移 fixture）。
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 6;

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
            // 这张历史形态的表已不在当前 schema 里，用原始 DDL 重建
            // （列与 v2~v5 生成代码完全一致），后续 from < 6 才读得到。
            await customStatement(
              'CREATE TABLE IF NOT EXISTS shift_type_rows ('
              'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
              'schedule_id INTEGER NOT NULL, "order" INTEGER NOT NULL, '
              'name TEXT NOT NULL, start_minute INTEGER NULL, '
              'end_minute INTEGER NULL, '
              'is_rest INTEGER NOT NULL DEFAULT 0, '
              'color INTEGER NOT NULL DEFAULT 4284186623, '
              'alarm_enabled INTEGER NOT NULL DEFAULT 0, '
              'alarm_minute INTEGER NULL'
              ')',
            );
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
          // 必须最后跑：要读的是上面各分支整理完的 v5 形态表。
          if (from < 6) {
            await m.createTable(shiftClassRows);
            await m.createTable(shiftCycleRows);
            await _migrateRowsToTwoTier();
          }
        },
      );

  /// v5 → v6：把「每天一行」的班次拆成
  /// 班次定义（shift_class_rows）+ 周期序列（shift_cycle_rows）。
  ///
  /// 字段完全相同的行合并成同一个定义 —— 12 天里 4 个「白班」迁完只剩 1 个。
  Future<void> _migrateRowsToTwoTier() async {
    final rows = await customSelect(
      'SELECT schedule_id, "order", name, start_minute, end_minute, is_rest, '
      'color, alarm_enabled, alarm_minute FROM shift_type_rows '
      'ORDER BY schedule_id, "order"',
    ).get();

    final idBySignature = <String, int>{};
    final definitionsInSchedule = <int, int>{};
    var nextClassId = 1;

    for (final r in rows) {
      final scheduleId = r.read<int>('schedule_id');
      final name = r.read<String>('name');
      final startMinute = r.read<int?>('start_minute');
      final endMinute = r.read<int?>('end_minute');
      final isRest = r.read<int>('is_rest') != 0;
      final color = r.read<int>('color');
      final alarmEnabled = r.read<int>('alarm_enabled') != 0;
      final alarmMinute = r.read<int?>('alarm_minute');
      final order = r.read<int>('order');

      final signature = <Object?>[
        scheduleId,
        name,
        startMinute,
        endMinute,
        isRest,
        color,
        alarmEnabled,
        alarmMinute,
      ].join('|');

      var classId = idBySignature[signature];
      if (classId == null) {
        classId = nextClassId++;
        idBySignature[signature] = classId;
        final orderInList = definitionsInSchedule[scheduleId] ?? 0;
        definitionsInSchedule[scheduleId] = orderInList + 1;
        await customInsert(
          'INSERT INTO shift_class_rows '
          '(id, schedule_id, "order", name, abbr, start_minute, end_minute, '
          'is_rest, color, alarm_enabled, alarm_minute) '
          'VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withInt(classId),
            Variable.withInt(scheduleId),
            Variable.withInt(orderInList),
            Variable.withString(name),
            // ⚠️ Variable.withInt 的形参是非空 int，插可空列必须用
            //    Variable<int>(null) 这种构造，否则编译不过。
            Variable<int>(startMinute),
            Variable<int>(endMinute),
            Variable.withInt(isRest ? 1 : 0),
            Variable.withInt(color),
            Variable.withInt(alarmEnabled ? 1 : 0),
            Variable<int>(alarmMinute),
          ],
        );
      }

      await customInsert(
        'INSERT INTO shift_cycle_rows (schedule_id, "order", class_id) '
        'VALUES (?, ?, ?)',
        variables: [
          Variable.withInt(scheduleId),
          Variable.withInt(order),
          Variable.withInt(classId),
        ],
      );
    }

    await customStatement('DROP TABLE IF EXISTS shift_type_rows');
  }
}
