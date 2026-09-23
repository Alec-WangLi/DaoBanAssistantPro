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

  // 每个班组相对基准日的**天数偏移**（逗号分隔，如 "0,1,2,3"）。
  // 第 i 组在某天的周期下标 = (目标日 − 基准日 + offsets[i]) mod 周期长度。
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
  // `alarm_minute` 在 v10 迁进 `ShiftClassAlarms` 后从本表删掉了（见 onUpgrade
  // 的 `from < 10` 分支与 TableMigration）—— 不留死列，免得下一个人从两个来源里
  // 挑错那个。
}

/// 周期序列表：第 N 天用哪个班次定义。
class ShiftCycleRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get scheduleId => integer()();
  IntColumn get order => integer()();
  IntColumn get classId => integer()();
}

/// 班次闹钟表：一个班次可以挂多条联动闹钟（上限 `maxAlarmsPerShift`）。
///
/// **不设自增 id**：没有任何东西引用单条闹钟（「按天关闹钟」是按天、不是按闹钟；
/// 模板不存身份），所以它跟 [ShiftDayOverrides] 不是一类东西 —— 那边要稳定 id
/// 是因为覆盖要指得住班次定义。别为了对称给它加 id。
///
/// `order` 是用户在编辑页里的顺序，**同时也是原生 id 里的「序号」**
/// （见 `AlarmService._shiftDaysHorizon`）。总开关在 [ShiftClassRows.alarmEnabled]
/// 上 —— 关掉开关**不清空**这里的时间（用户手滑关一下不该丢配置）。
class ShiftClassAlarms extends Table {
  IntColumn get classId => integer()();
  IntColumn get order => integer()();
  IntColumn get minute => integer()();
  TextColumn get label => text().nullable()();

  @override
  Set<Column> get primaryKey => {classId, order};
}

/// 日程事件表。
class ScheduleEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  DateTimeColumn get date => dateTime()();
  IntColumn get timeMinute => integer().nullable()();
  IntColumn get advanceRemindMinutes => integer().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();

  /// 到点是否走**闹钟**那条链路（全屏 + 循环铃声），而不是只弹一条通知。
  ///
  /// 与 [advanceRemindMinutes] 耦合：闹钟要有可响的时点，所以「不设提醒」的待办
  /// 不可能开着闹钟（界面上这两者联动，见 `schedule_screen.dart`）。
  BoolColumn get alarmEnabled => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
}

/// 自定义闹钟表（独立于排班）。
class CustomAlarms extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get hour => integer()();
  IntColumn get minute => integer()();

  /// 0=一次性，1=每天，2=每周。
  ///
  /// 这里那个默认值 1 是**建表时的**，与界面无关：界面新建时一律显式传值
  /// （v0.9.6 起新建默认 0=一次性，见 `alarm_screen.dart` 的 `_showAlarmDialog`），
  /// 只有绕开 `addCustomAlarm` 直接插行才会用到它。改它要动 schema 版本与迁移，
  /// 没必要 —— 别把这两个默认值当成一处。
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

/// 按天改班表：用户对某一天单独指定班次（换班 / 请假覆盖）。
///
/// 复合主键 `{scheduleId, day}`，覆盖**跟着方案走** —— 切到别的方案时这套覆盖
/// 不生效（「这天是什么班」整个都变了），删方案时连带删掉。
///
/// [day] 与 [ShiftAlarmOverrides.day] 同一个口径：纯日期自 epoch 的天数，
/// 由 `dayNumber()` 计算。[classId] 指向 `shift_class_rows.id`。
///
/// **与 [ShiftAlarmOverrides] 有意不一致**：那张表是全局的（只有 `day` 一个主键），
/// 因为它表达的是「那天别响」，跨方案也说得通；本表表达的是「那天上哪个班」，
/// 必然依附于某套方案的班次定义。别顺手把两者统一。
class ShiftDayOverrides extends Table {
  IntColumn get scheduleId => integer()();
  IntColumn get day => integer()();
  IntColumn get classId => integer()();

  @override
  Set<Column> get primaryKey => {scheduleId, day};
}

/// 「我的模板」表：把一套方案的**结构**（班次定义 + 周期 + 班组错位）存成快照，
/// 新建排班时可以再选它。见 `domain/schedule_template.dart`（那边的值类型与
/// 编解码是纯函数，可直接单测）。
///
/// 为什么整块存进一列而不是像方案那样拆成三张表：模板是只读快照 —— 没有按字段
/// 查询、没有跨表引用、也不与任何行共享身份，拆表只会多两张表和一套装配代码。
/// （方案那边拆表是因为**按天改班的覆盖要引用稳定的 classId**，模板没有这个需求。）
class CustomTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// 班次定义数组（JSON；见 `encodeTemplateClasses`）。**不含班次 id**。
  TextColumn get classes => text()();

  /// 周期下标序列（逗号分隔；见 `encodeTemplateCycle`）。
  TextColumn get cycle => text()();

  IntColumn get teamCount => integer()();

  /// 班组错位（逗号分隔）。保存时已归一化成「我们班组在第 0 位、错位 0」。
  TextColumn get teamOffsets => text()();

  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(tables: [
  ShiftScheduleRows,
  ShiftClassRows,
  ShiftCycleRows,
  ShiftClassAlarms,
  ScheduleEvents,
  CustomAlarms,
  ShiftAlarmOverrides,
  ShiftDayOverrides,
  CustomTemplates,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'shiftassistantpro'));

  /// 测试专用：接外部注入的 QueryExecutor（内存库 / 迁移 fixture）。
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 10) {
            // 班次闹钟：一个钟点（`alarm_minute` 列）→ 一张表（一组有序闹钟）。
            await m.createTable(shiftClassAlarms);
            // ⚠️ 只有 v6 及以后才有 `shift_class_rows`（它是 `from < 6` 那段建的）。
            // 从 v5 或更早升上来时这一段先跑，那时表还不存在 —— 硬插会
            // 「no such table: shift_class_rows」（`migration_v5_to_v6_test.dart`
            // 正是拦这个的）。那种老库的闹钟由 `from < 6` 那段直接落进新表。
            if (from >= 6) {
              // 条件只看 alarm_minute：**开关关着但时间还留着的行同样要搬** ——
              // 只挑 alarm_enabled = 1 等于把用户配好的时间吞了，界面上看不出来。
              await customStatement(
                'INSERT INTO shift_class_alarms (class_id, "order", minute, label) '
                'SELECT id, 0, alarm_minute, NULL FROM shift_class_rows '
                'WHERE alarm_minute IS NOT NULL',
              );
              // 删掉旧列（重建表）。**id 必须原样带过去** —— shift_cycle_rows 与
              // shift_day_overrides 都指着它，一变就集体指飞（不报错，只是那天
              // 变成别的班）。回归测试在 `migration_v9_to_v10_test.dart`。
              //
              // `TableMigration` 在 drift 里标着 experimental（API 可能变），这里
              // 仍然用它：它按**当前 schema 的生成代码**重建表，列定义不会写歪；
              // 手抄 DDL 那一套（v1→v2 分支那种）更适合已经不在 schema 里的历史表。
              // ignore: experimental_member_use
              await m.alterTable(TableMigration(shiftClassRows));
            }
          }
          if (from < 9) {
            // 「我的模板」（自定义模板）。纯新增一张表，不碰任何既有数据。
            await m.createTable(customTemplates);
          }
          if (from < 8) {
            // 按天改班（换班 / 请假覆盖）。纯新增一张表，不碰任何既有数据。
            await m.createTable(shiftDayOverrides);
          }
          if (from < 7) {
            // 待办的「联动闹钟」开关。默认关 = 保持旧行为（只弹通知）。
            await m.addColumn(scheduleEvents, scheduleEvents.alarmEnabled);
          }
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
          'is_rest, color, alarm_enabled) '
          'VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?)',
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
          ],
        );
        // 闹钟落进 v10 那张新表。**`from < 10` 那段排在 `from < 6` 之前**，
        // 所以从 v5 一升上来时新表已经建好了；顺序一颠倒这段就会打到不存在的表上。
        if (alarmMinute != null) {
          await customInsert(
            'INSERT INTO shift_class_alarms (class_id, "order", minute, label) '
            'VALUES (?, 0, ?, NULL)',
            variables: [
              Variable.withInt(classId),
              Variable.withInt(alarmMinute),
            ],
          );
        }
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
