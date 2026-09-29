import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/recurring_todo.dart';
import '../domain/schedule_chain.dart';
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
    this.classAlarms = const {},
  });

  final ShiftScheduleRow schedule;
  final List<ShiftClassRow> classes;
  final List<ShiftCycleRow> cycle;

  /// 本方案的按天改班覆盖行（存的是 classId）。
  final List<ShiftDayOverride> overrideRows;

  /// 各班次的闹钟行：key = classId，value 已按 `order` 排好（顺序即原生 id 的序号）。
  final Map<int, List<ShiftAlarm>> classAlarms;

  ShiftSchedule toDomain() {
    final domainClasses = classes
        .map((c) => c.toDomain(alarms: classAlarms[c.id] ?? const []))
        .toList();
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

/// 时间线上的全部方案（已装配成领域模型）+ 按天解析面。
///
/// 与单套的 [ActiveSchedule] 是两个类型，别混：编辑器 / 管理页 / 模板那边要的是
/// **某一套**（按 id 查，见 `getScheduleDomain`），而日历 / 闹钟 / 桌面小组件要的是
/// [chain] —— 「一个能回答某天什么班的东西」。
class ActiveSchedules {
  const ActiveSchedules({required this.all, required this.chain});

  /// 全部方案（按 id 升序）。装配 [chain] 的原料，界面要「列出所有方案」时也用它。
  final List<ActiveSchedule> all;

  /// 按天解析面。
  final ScheduleChain chain;

  /// 当前方案（`isCurrent`）。没有就返回 null。
  ActiveSchedule? get current {
    for (final a in all) {
      if (a.schedule.isCurrent) return a;
    }
    return null;
  }

  /// 当前方案的领域模型。
  ShiftSchedule? get currentDomain => current?.toDomain();

  /// 当前方案的行 id。
  ///
  /// 单拎出来是因为有三处（编辑器的「新建」路径、管理页的「当前」标记、切换弹窗的
  /// 选中态）都要它，各写一遍 `current?.schedule.id` 迟早写歪。
  int? get currentScheduleId => current?.schedule.id;
}

extension ShiftClassRowX on ShiftClassRow {
  /// [alarms] 由调用方从 `shift_class_alarms` 取好传进来（本行没有那张表的信息）。
  ShiftClass toDomain({List<ShiftAlarm> alarms = const []}) => ShiftClass(
        // id 必须带上：覆盖存的是 classId，丢了它整套覆盖都装配不出来。
        id: id,
        name: name,
        abbr: abbr,
        startMinute: startMinute,
        endMinute: endMinute,
        isRest: isRest,
        color: color,
        alarmEnabled: alarmEnabled,
        alarms: alarms,
      );
}

/// `RecurringTodos` 一行 → 领域形态。
extension RecurringSeriesRowX on RecurringSeriesRow {
  RecurringTodo toDomain() => RecurringTodo(
        id: id,
        title: title,
        // 库里存的是 int（0/1/2）。越界值（脏数据 / 将来可能加的第 4 种周期）
        // 落回「每天」：静默当每天比抛异常好 —— 用户至少还看得见这一条并去改它。
        repeat: RecurRepeat.values[
            repeatType >= 0 && repeatType < RecurRepeat.values.length
                ? repeatType
                : 0],
        startDate: startDate,
        timeMinute: timeMinute,
        advanceRemindMinutes: advanceRemindMinutes,
        alarmEnabled: alarmEnabled,
        weekdays: weekdays,
        monthDay: monthDay,
        skipThrough: skipThrough,
        enabled: enabled,
      );
}

extension AppDatabaseQueries on AppDatabase {
  /// 监听**全部**排班方案（含各自的班次、闹钟、周期、按天覆盖），装配成
  /// [ActiveSchedules]（响应式）。
  ///
  /// **方案表那条触发源不能少**：少了它，改一套方案的时段 / 班次不会让这条流重发，
  /// 日历、闹钟、桌面小组件全都不动，**不报错**（与「按天覆盖没挂 watch」那次完全
  /// 同一条，那次也是静默不刷新）。由 `schedule_chain_repository_test` 的
  /// 「改非当前方案 → 重发」钉住，**已反向验证**（把这一条从 triggers 里删掉，
  /// 用例立刻变红：`Expected: <1> Actual: <0>`）。
  ///
  /// 顺带一条实测的细节，免得后人误判：**从前那个 `watchSingleOrNull()` 其实也会
  /// 在整表任意一行变动时重发**（drift 对带 `where` 的查询不加行级过滤）——所以
  /// 「改非当前方案看不见」的根因不是触发源，而是**装配**只装了 `isCurrent` 那一套
  /// （`_loadChildren(sched)`）。改成整表 `.watch()` 是为了换来另外两件事：装配得
  /// 到全部方案，以及**再也不会在出现两行 `isCurrent` 时往流里推错**
  /// （`save_schedule_current_test` 记的正是那个坑）。
  ///
  /// 覆盖表与闹钟表是独立的子表，各挂一条；班次 / 周期跟着方案行一起改
  /// （`saveSchedule` 会 update 那一行），靠方案行的通知就够了。
  Stream<ActiveSchedules?> watchActiveSchedule() {
    final triggers = <Stream<Object?>>[
      select(shiftScheduleRows).watch(),
      select(scheduleSpanRows).watch(),
      select(shiftDayOverrides).watch(),
      select(shiftClassAlarms).watch(),
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
      final rows = await (select(shiftScheduleRows)
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
      if (rows.isEmpty) return null;
      return assembleSchedules(rows);
    });
  }

  /// 把一行行方案装配成 [ActiveSchedules]。
  ///
  /// 每套方案的 children 各查一次 —— [_loadChildren] 按 `scheduleId` 过滤，
  /// 天然是单套的（所以这里能直接复用，不必为多套另写一套查询）。
  ///
  /// 公开是因为 `AppRepository.getActiveSchedules()` 与两个 `*ForTesting` 都要它；
  /// 生产路径只走 [watchActiveSchedule]。
  Future<ActiveSchedules> assembleSchedules(List<ShiftScheduleRow> rows) async {
    final all = <ActiveSchedule>[];
    for (final r in rows) {
      all.add(await _loadChildren(r));
    }
    ActiveSchedule? current;
    for (final a in all) {
      if (a.schedule.isCurrent) {
        current = a;
        break;
      }
    }
    // 段表独立：一套方案可以出现在多段上。**关联不到方案的段跳过**
    // （方案被删之后的脏数据），而不是让整条装配崩掉。
    final spanRows = await select(scheduleSpanRows).get();
    final byId = {for (final a in all) a.schedule.id: a};
    final spans = <ScheduleSpan>[
      for (final s in spanRows)
        if (byId[s.scheduleId] != null)
          ScheduleSpan(
            id: s.id,
            scheduleId: s.scheduleId,
            schedule: byId[s.scheduleId]!.toDomain(),
            from: s.startDate,
            to: s.endDate,
          ),
    ];
    // 排序只为了让界面与日志有个稳定顺序 —— 解析规则自己显式比起点，不靠顺序。
    // 与时间线的显示顺序、以及冲突提示的报出顺序**共用同一条比较**（三处不一致
    // 的话，「界面上看到的顺序」与「提示里点名的那个」会对不上）。
    spans.sort(compareSpansByStart);
    return ActiveSchedules(
      all: all,
      chain: ScheduleChain(
        spans: spans,
        fallback: current?.toDomain(),
        // 兜底那套的**行 id** 要单独递进去：`ShiftSchedule` 是领域模型、不带 id，
        // 而「写按天覆盖该记在哪套名下」得靠它（见 `ScheduleChain.scheduleIdOn`）。
        fallbackId: current?.schedule.id,
      ),
    );
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
    // 闹钟表**没有 scheduleId**（它的存在只对班次定义负责），按本方案的 classId 取；
    // 按 `order` 升序 —— 那个顺序就是原生 id 里的「序号」。
    final classIds = classes.map((c) => c.id).toList();
    final alarmRows = classIds.isEmpty
        ? const <ShiftClassAlarm>[]
        : await (select(shiftClassAlarms)
              ..where((t) => t.classId.isIn(classIds))
              ..orderBy([(t) => OrderingTerm.asc(t.order)]))
            .get();
    final alarmsByClass = <int, List<ShiftAlarm>>{};
    for (final r in alarmRows) {
      (alarmsByClass[r.classId] ??= [])
          .add(ShiftAlarm(minute: r.minute, label: r.label));
    }
    return ActiveSchedule(
      schedule: sched,
      classes: classes,
      cycle: cycle,
      overrideRows: overrideRows,
      classAlarms: alarmsByClass,
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

  /// 测试专用：按当前方案装配一次 [ActiveSchedule]（不经过 Riverpod 流）。
  ///
  /// 迁移测试要验「闹钟搬进了新表、覆盖还指得对」，直接装配一次最短。
  Future<ActiveSchedule?> loadActiveScheduleForTesting() async {
    final rows = await (select(shiftScheduleRows)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    if (rows.isEmpty) return null;
    return (await assembleSchedules(rows)).current;
  }

  /// 测试专用：装配整条链。
  ///
  /// 「时段两列为 null → 不参与衔接」这条得整条链才看得见（单套装配体里没有它）。
  Future<ActiveSchedules?> loadActiveSchedulesForTesting() async {
    final rows = await (select(shiftScheduleRows)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    if (rows.isEmpty) return null;
    return assembleSchedules(rows);
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
      // 班次闹钟同理：+`class_id` 指着班次定义。
      await db.delete(db.shiftClassAlarms).go();
      // 先删子表（周期）再删父表（班次定义）。
      await db.delete(db.shiftCycleRows).go();
      // 时间线上的段指着方案行，也是子表。
      await db.delete(db.scheduleSpanRows).go();
      await db.delete(db.shiftClassRows).go();
      await db.delete(db.shiftScheduleRows).go();
      // 重复待办的**系列定义**。它的「行」就是 `schedule_events`，上面已经删了 ——
      // 这里只清系列本身；漏了的话，下次打开 App 生成器会照着老系列再建出行来，
      // 用户看到的就是「清空重置之后待办又冒出来了」。
      await db.delete(db.recurringSeriesRows).go();
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

  /// 立即读取整条链（重排闹钟用，避免读 Riverpod 流拿到旧值）。
  Future<ActiveSchedules?> getActiveSchedules() async {
    final rows = await (db.select(db.shiftScheduleRows)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    if (rows.isEmpty) return null;
    return db.assembleSchedules(rows);
  }

  // ---------------------------------------------------------------------------
  // 时间线上的「段」（多排班表按日期衔接）
  //
  // 段独立成表而不是方案行上的两列：**一套方案可以出现在多段上** ——
  // 「9 月临时换成别的班表、之后换回来」那种排法需要它。
  //
  // 段与段**不许重叠**，但这一层**不校验**（它要拿全量 spans 比，而那是界面的
  // 事）—— 这里只负责「把自己那一行写对」。
  // ---------------------------------------------------------------------------

  /// 在时间线上加一段。
  ///
  /// **空值必须显式构造 `Value(...)`**：`Value.absent()` 表达不了「这一端留空」
  /// （不限起点 / 一直持续），会静默保留列默认值。
  Future<int> addSpan(int scheduleId, {DateTime? from, DateTime? to}) {
    return db.into(db.scheduleSpanRows).insert(
          ScheduleSpanRowsCompanion.insert(
            scheduleId: scheduleId,
            startDate: Value(from == null ? null : dateOnly(from)),
            endDate: Value(to == null ? null : dateOnly(to)),
          ),
        );
  }

  /// 改一段：起止（**段 id**），或者把它改指到另一套方案。
  ///
  /// `scheduleId` 传 null 表示**不动**它 —— 段必须指向一套方案（列非空），
  /// 所以这里用 `Value.absent()` 而不是 `Value(null)`；那两列可空，**必须显式
  /// 构造 `Value`**（`Value.absent()` 表达不了「清回留空」）。
  Future<void> updateSpan(int spanId,
      {int? scheduleId, DateTime? from, DateTime? to}) async {
    await (db.update(db.scheduleSpanRows)..where((t) => t.id.equals(spanId)))
        .write(ScheduleSpanRowsCompanion(
      scheduleId:
          scheduleId == null ? const Value.absent() : Value(scheduleId),
      startDate: Value(from == null ? null : dateOnly(from)),
      endDate: Value(to == null ? null : dateOnly(to)),
    ));
  }

  /// 删掉一段（**段 id**）。
  Future<void> deleteSpan(int spanId) async {
    await (db.delete(db.scheduleSpanRows)..where((t) => t.id.equals(spanId)))
        .go();
  }

  /// 把「其余时间」设成**无**：所有方案都不再是 `isCurrent`。
  ///
  /// 与 [setCurrentSchedule] 配套 —— 后者永远是「设成某一套」，这个是「一套都不设」。
  /// 于是没被任何段覆盖的日子在日历上**真的没有排班**。
  ///
  /// **只有「排班时段」那一节的「设为无」会调它** —— 删掉一套方案时仍然自动把
  /// 其余时间交给列表里的第一套（[deleteSchedule]），否则「删掉默认那套」会让整张
  /// 日历变空，那是个惊悚结果。
  Future<void> setRemainingNone() async {
    await db.update(db.shiftScheduleRows).write(
          const ShiftScheduleRowsCompanion(isCurrent: Value(false)),
        );
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

  /// 删除一套排班方案（连带其班次定义、周期、按天改班覆盖与班次闹钟），
  /// 并保证始终有一套当前方案。
  Future<void> deleteSchedule(int id) async {
    await db.transaction(() async {
      // 闹钟表**没有 scheduleId**，得先捞出这套方案的班次 id 再删（子表先走）。
      final classIds = (await (db.select(db.shiftClassRows)
                ..where((t) => t.scheduleId.equals(id)))
              .get())
          .map((c) => c.id)
          .toList();
      if (classIds.isNotEmpty) {
        await (db.delete(db.shiftClassAlarms)
              ..where((t) => t.classId.isIn(classIds)))
            .go();
      }
      await (db.delete(db.shiftCycleRows)
            ..where((t) => t.scheduleId.equals(id)))
          .go();
      await (db.delete(db.shiftDayOverrides)
            ..where((t) => t.scheduleId.equals(id)))
          .go();
      // 时间线上的段也指着这套方案 —— 它同样是子表，先于方案行删。
      await (db.delete(db.scheduleSpanRows)
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
        final int classId;
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
          ));
          classId = c.id!;
        } else {
          classId = await db.into(db.shiftClassRows).insert(
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
        }
        classIds.add(classId);

        // 闹钟**整组重写**：条数少（≤ `maxAlarmsPerShift`）、没有任何东西引用
        // 单条闹钟，删了重建比逐条对账简单得多。顺序按列表落 —— **它就是原生 id
        // 里的「序号」**，所以别排序、别去重。（班次那条链走增量是因为按天覆盖
        // 引用了 classId；闹钟没有这层引用，见 `app_database.dart` 的注释。）
        await (db.delete(db.shiftClassAlarms)
              ..where((t) => t.classId.equals(classId)))
            .go();
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

      // 库里不在新列表里的班次定义：删掉，并**连带删掉引用它的覆盖行与它的闹钟**
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
        await (db.delete(db.shiftClassAlarms)
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

  /// 测试专用：给**当前方案**第 [classIndex] 个班次（按 `order`）设一组闹钟，
  /// 顺带打开总开关。
  ///
  /// 按下标取而不是按名字 —— 班次名是用户改得的（模板里的名字还跟着语言变），
  /// 测试别赌它叫什么。
  Future<void> setClassAlarmsForTesting(
      int classIndex, List<ShiftAlarm> alarms) async {
    final rows = await (db.select(db.shiftClassRows)
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    if (classIndex < 0 || classIndex >= rows.length) return;
    final classId = rows[classIndex].id;
    await (db.update(db.shiftClassRows)..where((t) => t.id.equals(classId)))
        .write(const ShiftClassRowsCompanion(alarmEnabled: Value(true)));
    await (db.delete(db.shiftClassAlarms)
          ..where((t) => t.classId.equals(classId)))
        .go();
    for (var k = 0; k < alarms.length; k++) {
      await db.into(db.shiftClassAlarms).insert(
            ShiftClassAlarmsCompanion.insert(
              classId: classId,
              order: k,
              minute: alarms[k].minute,
              label: Value(alarms[k].label),
            ),
          );
    }
  }

  Future<int> addEvent({
    required String title,
    required DateTime date,
    int? timeMinute,
    int? advanceRemindMinutes,
    bool alarmEnabled = false,
    int? seriesId,
  }) {
    return db.into(db.scheduleEvents).insert(
          ScheduleEventsCompanion.insert(
            title: title,
            date: dateOnly(date),
            timeMinute: Value(timeMinute),
            advanceRemindMinutes: Value(advanceRemindMinutes),
            alarmEnabled: Value(alarmEnabled),
            seriesId: Value(seriesId),
            createdAt: DateTime.now(),
          ),
        );
  }

  /// 全字段覆盖式更新。
  ///
  /// ⚠️ **只改某一个字段别用它**：没传的那几项会被写成默认值（`null` / `false`）。
  /// 只改日期要用 [setEventDate]。
  Future<void> updateEvent(
    ScheduleEvent e, {
    required String title,
    required DateTime date,
    int? timeMinute,
    int? advanceRemindMinutes,
    bool alarmEnabled = false,
    int? seriesId,
  }) {
    return (db.update(db.scheduleEvents)..where((r) => r.id.equals(e.id)))
        .write(ScheduleEventsCompanion(
      title: Value(title),
      date: Value(dateOnly(date)),
      timeMinute: Value(timeMinute),
      advanceRemindMinutes: Value(advanceRemindMinutes),
      alarmEnabled: Value(alarmEnabled),
      seriesId: Value(seriesId),
    ));
  }

  /// **只**改某条行的日期。
  ///
  /// 不走 [updateEvent]：那个是全字段覆盖，只传日期会把这条的时间 / 提醒 /
  /// 联动闹钟一起抹成默认值 —— 它名字看着像「更新这一条」，实际语义是「用这组
  /// 字段替换这一条」。目前只有一处用它：改完重复周期之后把「当前这一次」对齐到
  /// 新规则的最近一次发生日（见 `schedule_screen.dart` 的 `_EventFields.commit`）。
  Future<void> setEventDate(int id, DateTime date) {
    return (db.update(db.scheduleEvents)..where((r) => r.id.equals(id)))
        .write(ScheduleEventsCompanion(date: Value(dateOnly(date))));
  }

  /// 勾选 / 取消勾选。
  ///
  /// **勾掉一条重复项时，顺手把「这一次已经了结」记到系列上**（`skipThrough`）：
  /// 不记的话，下一次跑生成器时它一看「这个系列没有未完成的行、而这次的发生日
  /// 正好是今天」，会**立刻补出一条一模一样的新行** —— 用户勾完、下次打开 App
  /// 它又回来了。这与「删掉又回来」是同一个洞，所以用同一个标记
  /// （[skipRecurringOccurrence]）：在生成器眼里「勾掉」与「删掉」都是
  /// 「这次已经了结」，下一次 occurrence 一到自然又出现。
  ///
  /// 取消勾选**不撤销**那个标记：撤销了反而是「取消勾选 = 把它标成还没了结」——
  /// 那条行本来就在列表里，改回未勾就够了。
  Future<void> setEventCompleted(ScheduleEvent e, bool done) async {
    await (db.update(db.scheduleEvents)..where((r) => r.id.equals(e.id)))
        .write(ScheduleEventsCompanion(isCompleted: Value(done)));
    final sid = e.seriesId;
    if (done && sid != null) {
      await skipRecurringOccurrence(sid, e.date);
    }
  }

  Future<void> deleteEvent(ScheduleEvent e) {
    return (db.delete(db.scheduleEvents)..where((r) => r.id.equals(e.id)))
        .go();
  }

  // ---------------------------------------------------------------------------
  // 重复待办（系列定义）
  //
  // 表里存的是**系列**，不是实例；「当前这一次」是 `schedule_events` 里挂着
  // `seriesId` 的那一行。两者的关系由 `advanceRecurringTodos` 维持。
  //
  // 两个删除语义**不能混**：
  //  - `unlinkRecurringSeries` —— 「以后不再重复」：行解绑、一条待办都不删；
  //  - `deleteRecurringTodo`   —— 「删除这个重复」：连它的行一起删。
  // ---------------------------------------------------------------------------

  Future<int> addRecurringTodo({
    required String title,
    required RecurRepeat repeat,
    required DateTime startDate,
    int? timeMinute,
    int? advanceRemindMinutes,
    bool alarmEnabled = false,
    int weekdays = 0,
    int monthDay = 1,
  }) {
    return db.into(db.recurringSeriesRows).insert(
          RecurringSeriesRowsCompanion.insert(
            title: title,
            repeatType: Value(repeat.index),
            startDate: dateOnly(startDate),
            timeMinute: Value(timeMinute),
            advanceRemindMinutes: Value(advanceRemindMinutes),
            alarmEnabled: Value(alarmEnabled),
            weekdays: Value(weekdays),
            monthDay: Value(monthDay),
            enabled: const Value(true),
            createdAt: DateTime.now(),
          ),
        );
  }

  /// 覆盖式更新（`RecurringTodo` 全字段）。
  ///
  /// 逐个 `Value(...)` 显式给，所以 **`advanceRemindMinutes` 能真的写成 null** ——
  /// 调用方要显式构造一个 `RecurringTodo`，别用 `copyWith(advanceRemindMinutes:
  /// null)`（那个清不掉，见 `RecurringTodo.copyWith` 的注释）。
  Future<void> updateRecurringTodo(RecurringTodo s) {
    return (db.update(db.recurringSeriesRows)..where((t) => t.id.equals(s.id!)))
        .write(RecurringSeriesRowsCompanion(
      title: Value(s.title),
      repeatType: Value(s.repeat.index),
      startDate: Value(dateOnly(s.startDate)),
      timeMinute: Value(s.timeMinute),
      advanceRemindMinutes: Value(s.advanceRemindMinutes),
      alarmEnabled: Value(s.alarmEnabled),
      weekdays: Value(s.weekdays),
      monthDay: Value(s.monthDay),
      skipThrough: Value(s.skipThrough),
      enabled: Value(s.enabled),
    ));
  }

  Future<void> setRecurringEnabled(int id, bool enabled) {
    return (db.update(db.recurringSeriesRows)..where((t) => t.id.equals(id)))
        .write(RecurringSeriesRowsCompanion(enabled: Value(enabled)));
  }

  /// 「这次不要了」：记下那天的 `dayNumber`，生成器在那天之前不再补出来。
  ///
  /// 不写这个标记的话，在列表里删掉当前那条之后，下一次打开 App 生成器又会把它
  /// 补出来 —— 用户看到的就是「删不掉」。
  Future<void> skipRecurringOccurrence(int seriesId, DateTime occ) {
    return (db.update(db.recurringSeriesRows)..where((t) => t.id.equals(seriesId)))
        .write(RecurringSeriesRowsCompanion(skipThrough: Value(dayNumber(occ))));
  }

  /// 删一个系列，**连带删它的行**（当前那条与已完成的历史都算它的）。
  ///
  /// 留下孤儿行的话，列表里会出现几条还原不回去的「历史」；而系列一回来
  /// （用户又建了一个同样的），它们又会莫名其妙地挂上去。
  ///
  /// ⚠️ **「以后不再重复」不能走这个方法**：那会把用户正在编辑的这条待办本身也
  /// 删掉。那种情形用 [unlinkRecurringSeries]。
  Future<void> deleteRecurringTodo(int id) async {
    await db.transaction(() async {
      await (db.delete(db.scheduleEvents)..where((e) => e.seriesId.equals(id)))
          .go();
      await (db.delete(db.recurringSeriesRows)..where((t) => t.id.equals(id))).go();
    });
  }

  /// 「以后不再重复」：**把行解绑、把系列定义删掉，但一条待办都不删。**
  ///
  /// 与 [deleteRecurringTodo] 的差别正是这一条：用户说的是「别再自动出现了」，
  /// 不是「把我这条待办删了」。已完成的那些历史也解绑成普通待办留着 —— 它们本来
  /// 就是做过的事，列表里一直看得见，用户想清自己删。
  Future<void> unlinkRecurringSeries(int id) async {
    await db.transaction(() async {
      await (db.update(db.scheduleEvents)..where((e) => e.seriesId.equals(id)))
          .write(const ScheduleEventsCompanion(seriesId: Value(null)));
      await (db.delete(db.recurringSeriesRows)..where((t) => t.id.equals(id))).go();
    });
  }

  /// 全部系列（按创建时间升序）。
  Future<List<RecurringTodo>> listRecurringTodos() async {
    final rows = await (db.select(db.recurringSeriesRows)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows.map((r) => r.toDomain()).toList();
  }

  /// 把每个重复待办的「当前这一次」推进到今天该有的样子。
  ///
  /// [today] 由调用方注入，**不读 `DateTime.now()`** —— 读时钟的话，月末、跨年、
  /// 起始日这些边界全都测不成（与 `planShiftAlarms(from:)` 同一条理由）。
  ///
  /// 一个事务里做完：这份数据的不变量是「一个系列至多一条未完成的行」，
  /// 中途失败留下两条就破了。
  ///
  /// 跑在三个时点：App 启动、回到前台、改完系列之后（见 `home_shell.dart` 与
  /// `schedule_screen.dart`）。列表是 drift 流，**不写库就不会重发**，所以
  /// 「一直没关过的 App 跨过午夜」那条路径必须靠「回到前台」这一下。
  Future<void> advanceRecurringTodos({required DateTime today}) async {
    await db.transaction(() async {
      final series = await listRecurringTodos();
      final rows = await listEvents();
      for (final s in series) {
        // 停用：不生成也不顺延。已经出现的那条留着 —— 那是用户还没做的一件事，
        // 替他删掉他就再也看不见了。
        if (!s.enabled) continue;

        final occ = occurrenceOnOrBefore(s, today);
        if (occ == null) continue; // 还没到起始日
        // 「这次不要了」：跳过标记与 occurrence 都是「自 epoch 天数」。
        // 直接拿 DateTime 比 int 是拿毫秒去比天数，恒不成立 —— 那正是「删了又回来」。
        if (s.skipThrough != null && dayNumber(occ) <= s.skipThrough!) continue;

        final live = rows
            .where((r) => r.seriesId == s.id && !r.isCompleted)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

        if (live.isEmpty) {
          await db.into(db.scheduleEvents).insert(
                ScheduleEventsCompanion.insert(
                  title: s.title,
                  date: occ,
                  timeMinute: Value(s.timeMinute),
                  advanceRemindMinutes: Value(s.advanceRemindMinutes),
                  alarmEnabled: Value(s.alarmEnabled),
                  seriesId: Value(s.id),
                  createdAt: DateTime.now(),
                ),
              );
          continue;
        }

        // 多条未完成是脏数据：留日期最新的那条，其余按已完成处理（留下痕迹，
        // 但不再参与「当前那一条」的判定）。
        for (final extra in live.take(live.length - 1)) {
          await (db.update(db.scheduleEvents)
                ..where((r) => r.id.equals(extra.id)))
              .write(const ScheduleEventsCompanion(isCompleted: Value(true)));
        }
        final keep = live.last;
        // **只往前顺延**：用户手工把这一次改到别的日子（这周的会挪到周五）之后，
        // 生成器不许把它拽回来。这是有意的 —— 代价是「改周期」那条路径要自己把
        // 当前那条对齐（见 `_EventFields.commit`），别把哪一边当 bug 改。
        if (daysBetween(keep.date, occ) > 0) {
          await (db.update(db.scheduleEvents)
                ..where((r) => r.id.equals(keep.id)))
              .write(ScheduleEventsCompanion(date: Value(occ)));
        }
      }
    });
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

  /// 把 [dates] 这些天改成 [classId] 指定的班次。
  ///
  /// 一次写多天为什么不做成范围：底层就是一天一行（复合主键 `{scheduleId, day}`），
  /// 存范围反而要在读写两头各拆一次。连休三天就是三行，天然支持。
  ///
  /// 重复设置同一天走 `insertOnConflictUpdate`，是更新不是报错。
  ///
  /// **每一天记在「那天所属方案」名下**（`ScheduleChain.scheduleIdOn`），不是
  /// 「当前方案」名下：有了时段衔接之后，用户可以在日历上选中属于**非当前**方案的
  /// 那天去调整 —— 记在当前方案名下的话那条覆盖**既查不出来、也不报错**，用户
  /// 看到的是「改了班，日历纹丝不动」。老库没有时段时两者恒等，行为与从前一致。
  Future<void> setDayOverrides(List<DateTime> dates,
      {required int classId}) async {
    final chain = (await getActiveSchedules())?.chain;
    if (chain == null) return;
    await db.transaction(() async {
      for (final date in dates) {
        final scheduleId = chain.scheduleIdOn(date);
        if (scheduleId == null) continue;
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

  /// 清掉 [dates] 这些天的覆盖，让它们回到按轮转算。
  ///
  /// 同 [setDayOverrides]：逐天找「那天所属方案」再删。跨两套方案的一段日子由界面
  /// 拦住（`calendar_screen.dart` 的 `adjustDays` 里那句说明），但仓库这一层照样
  /// 各删各的 —— 撤回本来就不需要 `classId`，没有理由只删一半。
  Future<void> clearDayOverrides(List<DateTime> dates) async {
    final chain = (await getActiveSchedules())?.chain;
    if (chain == null) return;
    await db.transaction(() async {
      for (final date in dates) {
        final scheduleId = chain.scheduleIdOn(date);
        if (scheduleId == null) continue;
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

final activeScheduleProvider =
    StreamProvider<ActiveSchedules?>((ref) async* {
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

/// 时间线上的全部段（**按起点升序，起点为空的排最前** —— 与
/// `compareSpansByStart` 同一条口径）。
///
/// 「排班时段」那一节与日历那个总览弹层都读它；两处各自的「按方案数几段」也从
/// 它算，免得各写一份。
final scheduleSpansProvider = StreamProvider<List<ScheduleSpanRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.scheduleSpanRows)
        ..orderBy([
          (t) => OrderingTerm.asc(t.startDate),
          (t) => OrderingTerm.asc(t.id),
        ]))
      .watch();
});

/// 「我的模板」列表 —— 新建排班的选择页用它多渲染一组卡片。
///
/// 一次性读（不是流，理由见 `AppRepository.listTemplates`），但**必须
/// `autoDispose`**：不带它的 FutureProvider 会把第一次读到的结果缓存一整个
/// 会话 —— 用户先开过一次「新建排班」（那时还没有模板），之后在编辑器里存下
/// 一份，再回来**看不到**那一组，直到重启 App。2026-09-21 用户反馈的
/// 「我保存模板后，没看到呀」就是它（当时先开过选择页）。
/// autoDispose 之后离开页面即丢缓存，下次进来重新读；页内的改名 / 删除仍由
/// `ref.invalidate` 即时刷新。
final savedTemplatesProvider =
    FutureProvider.autoDispose<List<ScheduleTemplate>>((ref) {
  return ref.watch(appRepositoryProvider).listTemplates();
});

final eventsProvider = StreamProvider<List<ScheduleEvent>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchEvents();
});

/// 全部重复待办（系列定义）。管理面板用它。
///
/// **一次性读 + `autoDispose`**，不是流 —— 与 `savedTemplatesProvider` 同一套
/// 理由与坑：
///  - 用流的话，每条挂这个弹窗的 widget 用例都会在拆树时报
///    「A Timer is still pending」（drift 取消查询流时排的零时长定时器）；
///  - 而 `autoDispose` 是**必需**的：面板里改完 / 删完之后由调用点
///    `ref.invalidate` 重读，不 autoDispose 的话第一次读到的结果会被缓存一整个
///    会话（v0.8.11 那个「存完模板看不到」就是这么来的）。
final recurringTodosProvider =
    FutureProvider.autoDispose<List<RecurringTodo>>((ref) {
  return ref.watch(appRepositoryProvider).listRecurringTodos();
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
