import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/schedule_template.dart';
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

/// 活跃排班方案（当前方案行 + 班次定义 + 周期序列 + 按天改班覆盖）。
class ActiveSchedule {
  const ActiveSchedule({
    required this.schedule,
    required this.classes,
    required this.cycle,
    this.overrideRows = const [],
  });

  final ShiftScheduleRow schedule;
  final List<ShiftClassRow> classes;
  final List<ShiftCycleRow> cycle;

  /// 本方案的按天改班覆盖行（存的是 classId）。
  final List<ShiftDayOverride> overrideRows;

  ShiftSchedule toDomain() {
    final domainClasses = classes.map((c) => c.toDomain()).toList();
    // 库里存的是 classId，领域层要的是 classes 的下标。
    final indexById = {
      for (var i = 0; i < classes.length; i++) classes[i].id: i,
    };
    final domainCycle = cycle
        .map((r) => indexById[r.classId] ?? -1)
        .where((i) => i >= 0)
        .toList();
    // 同口径：覆盖行的 classId 也换算成 classes 下标。
    final dayOverrides = <int, int>{};
    for (final r in overrideRows) {
      final idx = indexById[r.classId];
      // 查不到的（班次被删、历史脏数据）直接忽略 —— 那天回退到轮转。
      if (idx != null) dayOverrides[r.day] = idx;
    }
    final n = schedule.teamCount;
    final names = parseTeamNames(schedule.teamNames);
    final offsets = parseTeamOffsets(schedule.teamOffsets);
    return ShiftSchedule(
      name: schedule.name,
      anchorDate: schedule.anchorDate,
      classes: domainClasses,
      cycle: domainCycle,
      teamCount: n,
      // 防御性补位到 teamCount：正常创建路径（`L10n.defaultTeamNames`）给的就是
      // 完整长度，只有库里的列表短于 teamCount（历史数据 / 外部构造）才会走到
      // 兜底分支 —— 所以这里用语言中性的值，不能再硬编码中文。
      teamNames: List.generate(
        n,
        (i) => i < names.length ? names[i] : 'Team ${i + 1}',
      ),
      ourTeamIndex: schedule.ourTeamIndex,
      teamOffsets: List.generate(
        n,
        (i) => i < offsets.length ? offsets[i] : (i - schedule.ourTeamIndex),
      ),
      dayOverrides: dayOverrides,
    );
  }
}

extension ShiftClassRowX on ShiftClassRow {
  ShiftClass toDomain() => ShiftClass(
        // id 必须带上：覆盖存的是 classId，丢了它整套覆盖都装配不出来。
        id: id,
        name: name,
        abbr: abbr,
        startMinute: startMinute,
        endMinute: endMinute,
        isRest: isRest,
        color: color,
        alarmEnabled: alarmEnabled,
        alarmMinute: alarmMinute,
      );
}

extension AppDatabaseQueries on AppDatabase {
  /// 监听当前排班方案及其班次、周期、按天覆盖（响应式）。
  ///
  /// **必须同时监听覆盖表**：只监听方案行的话，用户改完覆盖落库成功，
  /// 这个流不会重发，日历上**纹丝不动** —— 不报错、不崩溃，从界面上看不出
  /// 原因。班次 / 周期是随方案行一起改的（保存方案会 update 那一行），所以
  /// 它们靠方案行的通知就够了；覆盖是独立的行，得单独挂一条。
  Stream<ActiveSchedule?> watchActiveSchedule() {
    final schedQuery = select(shiftScheduleRows)
      ..where((s) => s.isCurrent.equals(true));
    final triggers = <Stream<Object?>>[
      schedQuery.watchSingleOrNull(),
      select(shiftDayOverrides).watch(),
    ];
    // 不用 rxdart（项目没有这个依赖）：手写一个「任一来源发值就置位」的触发流。
    return Stream<Object?>.multi((controller) {
      final subs = [for (final s in triggers) s.listen(controller.add)];
      controller.onCancel = () {
        for (final sub in subs) {
          sub.cancel();
        }
      };
    }).asyncMap((_) async {
      final sched = await schedQuery.getSingleOrNull();
      if (sched == null) return null;
      return _loadChildren(sched);
    });
  }

  Future<ActiveSchedule> _loadChildren(ShiftScheduleRow sched) async {
    final classes = await (select(shiftClassRows)
          ..where((t) => t.scheduleId.equals(sched.id))
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    final cycle = await (select(shiftCycleRows)
          ..where((t) => t.scheduleId.equals(sched.id))
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    final overrideRows = await (select(shiftDayOverrides)
          ..where((t) => t.scheduleId.equals(sched.id)))
        .get();
    return ActiveSchedule(
      schedule: sched,
      classes: classes,
      cycle: cycle,
      overrideRows: overrideRows,
    );
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

  /// 清空全部数据（排班方案 + 班次 + 日程 + 按天闹钟覆盖 + 按天改班覆盖），并恢复默认「四班两倒」。
  Future<void> clearAll() async {
    await db.transaction(() async {
      await db.delete(db.scheduleEvents).go();
      await db.delete(db.shiftAlarmOverrides).go();
      // 按天改班覆盖引用班次定义的 id，是班次的子表：与周期一样先于班次删。
      await db.delete(db.shiftDayOverrides).go();
      // 先删子表（周期）再删父表（班次定义）。
      await db.delete(db.shiftCycleRows).go();
      await db.delete(db.shiftClassRows).go();
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

  /// 取一套排班方案的完整领域模型（含班次定义与周期）。
  Future<ShiftSchedule?> getScheduleDomain(int id) async {
    final row = await (db.select(db.shiftScheduleRows)
          ..where((s) => s.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return (await db._loadChildren(row)).toDomain();
  }

  /// 立即读取当前方案领域模型（重排闹钟用，避免读 Riverpod 流拿到旧值）。
  Future<ShiftSchedule?> getActiveSchedule() async {
    final row = await (db.select(db.shiftScheduleRows)
          ..where((s) => s.isCurrent.equals(true)))
        .getSingleOrNull();
    if (row == null) return null;
    return (await db._loadChildren(row)).toDomain();
  }

  /// 删除一套排班方案（连带其班次定义、周期与按天改班覆盖），并保证始终有一套当前方案。
  Future<void> deleteSchedule(int id) async {
    await db.transaction(() async {
      await (db.delete(db.shiftCycleRows)
            ..where((t) => t.scheduleId.equals(id)))
          .go();
      await (db.delete(db.shiftDayOverrides)
            ..where((t) => t.scheduleId.equals(id)))
          .go();
      await (db.delete(db.shiftClassRows)
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

  // ---------------------------------------------------------------------------
  // 我的模板（自定义模板）
  //
  // 存的是一套方案的**结构**（班次定义 + 周期 + 班组错位），新建排班时可以再选。
  // 与内置模板的区别只在来源：内置那些是编译期常量，这些是用户自己存下来的。
  // ---------------------------------------------------------------------------

  /// 全部自定义模板，**新存的在前**（最近用过的多半最相关）。
  ///
  /// 一次性读取而不是流：选择页是短命页面，进来读一次就够 —— 页内的改名 / 删除
  /// 由调用方 `ref.invalidate` 重新读（见 `savedTemplatesProvider`）。**刻意不用
  /// `watch()`**：drift 的查询流在取消时会排一个零时长定时器清理缓存，而 widget
  /// 测试在测试体结束时立刻校验「没有待处理的定时器」—— 用流的话每条挂这个页面
  /// 的用例都要额外拆一次树（见 `calendar_screen_test.dart` 的 `_disposeCalendar`），
  /// 这里不必付这个代价。
  Future<List<ScheduleTemplate>> listTemplates() async {
    final q = db.select(db.customTemplates)
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    return _decodeTemplates(await q.get());
  }

  /// 存一份模板。[ScheduleTemplate.id] 会被忽略（永远是新增一条）——
  /// 同名再存一次就是两条，用户想合并自己在选择页删。
  Future<int> saveTemplate(ScheduleTemplate t) {
    return db.into(db.customTemplates).insert(
          CustomTemplatesCompanion.insert(
            name: t.name,
            classes: encodeTemplateClasses(t.classes),
            cycle: encodeTemplateCycle(t.cycle),
            teamCount: t.teamCount,
            teamOffsets: encodeTemplateOffsets(t.teamOffsets),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> renameTemplate(int id, String name) async {
    await (db.update(db.customTemplates)..where((t) => t.id.equals(id)))
        .write(CustomTemplatesCompanion(name: Value(name)));
  }

  Future<void> deleteTemplate(int id) async {
    await (db.delete(db.customTemplates)..where((t) => t.id.equals(id))).go();
  }

  /// 逐行解码，坏数据（班次定义解不出来）**跳过这一条**而不是抛 ——
  /// 一格坏 JSON 不该让整个模板库消失。
  List<ScheduleTemplate> _decodeTemplates(List<CustomTemplate> rows) {
    final out = <ScheduleTemplate>[];
    for (final r in rows) {
      final classes = decodeTemplateClasses(r.classes);
      if (classes.isEmpty) continue;
      out.add(ScheduleTemplate(
        id: r.id,
        name: r.name,
        classes: classes,
        cycle: decodeTemplateCycle(r.cycle),
        teamCount: r.teamCount,
        teamOffsets: decodeTemplateOffsets(r.teamOffsets),
      ));
    }
    return out;
  }

  /// 保存（新建或更新）一套排班方案并替换其班次。
  Future<int> saveSchedule({
    int? scheduleId,
    required String name,
    required DateTime anchorDate,
    required List<ShiftClass> classes,
    required List<int> cycle,
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
                // 必须跟着入参走：写死 true 时 makeCurrent:false 会跳过下面
                // 「清掉其他当前行」的分支，于是新旧两行同时 isCurrent，
                // watchActiveSchedule() 的 watchSingleOrNull() 直接往流里推错。
                isCurrent: Value(makeCurrent),
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

      // 重建班次定义与周期序列
      await (db.delete(db.shiftCycleRows)
            ..where((t) => t.scheduleId.equals(id)))
          .go();

      // 班次定义走**增量更新**，不再「删光重建」。
      //
      // 从前这里是把该方案的班次行全部删掉再逐条 insert，于是每次保存都拿到
      // 全新的自增 id —— 用户哪怕只是把方案名从「四班两倒」改成「我们组」，
      // 所有班次 id 也一起变。而 `shift_day_overrides.classId` 引用正是这个 id，
      // 一保存覆盖就全部指飞。
      //
      // 顺带这一改也贴回了两层模型的本意（`PRODUCT_SPEC.md` §3：「一个班次只
      // 定义一次」）—— 从前的实现每次保存都把班次当新的重新定义一遍。
      final classIds = <int>[];
      for (var i = 0; i < classes.length; i++) {
        final c = classes[i];
        if (c.id != null) {
          await (db.update(db.shiftClassRows)
                ..where((t) => t.id.equals(c.id!)))
              .write(ShiftClassRowsCompanion(
            scheduleId: Value(id),
            order: Value(i),
            name: Value(c.name),
            abbr: Value(c.abbr),
            startMinute: Value(c.startMinute),
            endMinute: Value(c.endMinute),
            isRest: Value(c.isRest),
            color: Value(c.color),
            alarmEnabled: Value(c.alarmEnabled),
            alarmMinute: Value(c.alarmMinute),
          ));
          classIds.add(c.id!);
        } else {
          classIds.add(await db.into(db.shiftClassRows).insert(
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
                  alarmMinute: Value(c.alarmMinute),
                ),
              ));
        }
      }

      // 库里不在新列表里的班次定义：删掉，并**连带删掉引用它的覆盖行**
      // （悬空引用留着只会在表里攒垃圾，渲染时还得再兜一次底）。
      final keptClassIds = classIds.toSet();
      final staleClasses = await (db.select(db.shiftClassRows)
            ..where((t) => t.scheduleId.equals(id)))
          .get();
      for (final row in staleClasses) {
        if (keptClassIds.contains(row.id)) continue;
        await (db.delete(db.shiftDayOverrides)
              ..where((t) => t.classId.equals(row.id)))
            .go();
        await (db.delete(db.shiftClassRows)..where((t) => t.id.equals(row.id)))
            .go();
      }

      for (var i = 0; i < cycle.length; i++) {
        final ci = cycle[i];
        if (ci < 0 || ci >= classIds.length) continue;
        await db.into(db.shiftCycleRows).insert(
              ShiftCycleRowsCompanion.insert(
                scheduleId: id,
                order: i,
                classId: classIds[ci],
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
    bool alarmEnabled = false,
  }) {
    return db.into(db.scheduleEvents).insert(
          ScheduleEventsCompanion.insert(
            title: title,
            date: dateOnly(date),
            timeMinute: Value(timeMinute),
            advanceRemindMinutes: Value(advanceRemindMinutes),
            alarmEnabled: Value(alarmEnabled),
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
    bool alarmEnabled = false,
  }) {
    return (db.update(db.scheduleEvents)..where((r) => r.id.equals(e.id)))
        .write(ScheduleEventsCompanion(
      title: Value(title),
      date: Value(dateOnly(date)),
      timeMinute: Value(timeMinute),
      advanceRemindMinutes: Value(advanceRemindMinutes),
      alarmEnabled: Value(alarmEnabled),
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

  /// 立即读取全部日程（重排提醒用，避免读 Riverpod 流拿到旧值）。
  Future<List<ScheduleEvent>> listEvents() {
    final q = db.select(db.scheduleEvents)
      ..orderBy([
        (t) => OrderingTerm.asc(t.date),
        (t) => OrderingTerm.asc(t.timeMinute),
      ]);
    return q.get();
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

  /// 当前方案的行 id；没有当前方案时返回 null。
  Future<int?> currentScheduleId() async {
    final row = await (db.select(db.shiftScheduleRows)
          ..where((s) => s.isCurrent.equals(true)))
        .getSingleOrNull();
    return row?.id;
  }

  /// 把 [dates] 这些天改成 [classId] 指定的班次（当前方案）。
  ///
  /// 一次写多天为什么不做成范围：底层就是一天一行（复合主键 `{scheduleId, day}`），
  /// 存范围反而要在读写两头各拆一次。连休三天就是三行，天然支持。
  ///
  /// 重复设置同一天走 `insertOnConflictUpdate`，是更新不是报错。
  Future<void> setDayOverrides(List<DateTime> dates,
      {required int classId}) async {
    final scheduleId = await currentScheduleId();
    if (scheduleId == null) return;
    await db.transaction(() async {
      for (final date in dates) {
        await db.into(db.shiftDayOverrides).insertOnConflictUpdate(
              ShiftDayOverridesCompanion.insert(
                scheduleId: scheduleId,
                day: dayNumber(date),
                classId: classId,
              ),
            );
      }
    });
  }

  /// 清掉 [dates] 这些天的覆盖，让它们回到按轮转算（当前方案）。
  Future<void> clearDayOverrides(List<DateTime> dates) async {
    final scheduleId = await currentScheduleId();
    if (scheduleId == null) return;
    await db.transaction(() async {
      for (final date in dates) {
        await (db.delete(db.shiftDayOverrides)
              ..where((t) =>
                  t.scheduleId.equals(scheduleId) &
                  t.day.equals(dayNumber(date))))
            .go();
      }
    });
  }

  /// 当前方案已设置的覆盖天数（编辑器顶部提示用）。
  Future<int> dayOverrideCount() async {
    final scheduleId = await currentScheduleId();
    if (scheduleId == null) return 0;
    final rows = await (db.select(db.shiftDayOverrides)
          ..where((t) => t.scheduleId.equals(scheduleId)))
        .get();
    return rows.length;
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

/// 「我的模板」列表 —— 新建排班的选择页用它多渲染一组卡片。
///
/// 一次性读（不是流）：页内改名 / 删除之后由那两处 `ref.invalidate` 重新读，
/// 用流的代价见 `AppRepository.listTemplates` 的说明。
final savedTemplatesProvider = FutureProvider<List<ScheduleTemplate>>((ref) {
  return ref.watch(appRepositoryProvider).listTemplates();
});

final eventsProvider = StreamProvider<List<ScheduleEvent>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchEvents();
});

/// 一条日程是不是「属于 [day] 且未完成」。
///
/// 日历信息卡的「N 项待办」徽章（`calendar_screen.dart`）与桌面小组件快照里的
/// 今日待办数（`home_shell.dart` 的 `_pushWidgetSnapshot`）共用这一个口径 ——
/// 桌面上的数与日历上的数必须一致，而这个判定此前在两处各写了一份。抽成一处是
/// 为了让「同一个口径」由结构保证，而不是靠两处各自自觉。
///
/// [ScheduleEvent.date] 是 `dateOnly` 存的 UTC 纯日期，比「同一天」必须走
/// [isSameDay]（不能用 `==`，它连 `isUtc` 一起比，同一天也会判成不等）。
bool isPendingTodoOn(ScheduleEvent e, DateTime day) =>
    !e.isCompleted && isSameDay(e.date, day);

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
