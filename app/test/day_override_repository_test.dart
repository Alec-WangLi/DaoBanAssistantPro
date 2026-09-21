// app/test/day_override_repository_test.dart
//
// 按天改班的仓库层：装配（存的是 classId，领域层要的是下标）、班次带 id、
// 以及最要命的一条 —— 覆盖表变化时 `watchActiveSchedule()` 必须重新发值。
// 最后这条如果不成立，用户改完覆盖落库成功、日历却纹丝不动，**不报错、
// 只是不动**，从界面上根本看不出原因。
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

void main() {
  late AppDatabase db;
  late AppRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppRepository(db);
  });

  tearDown(() => db.close());

  /// 建一套四班两倒，返回 (scheduleId, 大休那个班次的 id)。
  Future<(int, int)> seed() async {
    final d = defaultSchedule();
    final id = await repo.saveSchedule(
      name: d.name,
      anchorDate: d.anchorDate,
      classes: d.classes,
      cycle: d.cycle,
      makeCurrent: true,
      teamCount: d.teamCount,
      teamNames: d.teamNames,
      ourTeamIndex: d.ourTeamIndex,
      teamOffsets: d.teamOffsets,
    );
    final classes = await (db.select(db.shiftClassRows)
          ..where((t) => t.scheduleId.equals(id))
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    final rest = classes.firstWhere((c) => c.isRest);
    return (id, rest.id);
  }

  test('从库里读出来的班次必须带 id', () async {
    final (_, restId) = await seed();
    final d = (await repo.getActiveSchedule())!;
    expect(d.classes.every((c) => c.id != null), isTrue,
        reason: '不带 id 的话 saveSchedule 会永远当新班次插，覆盖一保存就指飞');
    expect(d.classes.map((c) => c.id), contains(restId));
  });

  test('覆盖装配成 classes 下标，shiftOn 命中', () async {
    final (scheduleId, _) = await seed();
    final day = DateTime(2026, 9, 20);
    final classes = await (db.select(db.shiftClassRows)
          ..where((t) => t.scheduleId.equals(scheduleId))
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    // 目标挑「大休」（最后一个），**不要**用 `firstWhere((c) => c.isRest)`：
    // 后者拿到的是「下夜班」，而 2026-09-20 那天的轮转结果**正好也是下夜班**
    // （anchor 2025-01-06 → 差 622 天，622 mod 4 = 2 → cycle[2] = classes[2]），
    // 两边同名，下面那条 isNot 断言会假失败。
    final target = classes.last;
    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: scheduleId,
            day: dayNumber(day),
            classId: target.id,
          ),
        );

    final d = (await repo.getActiveSchedule())!;
    expect(d.shiftOn(day)!.name, target.name, reason: '覆盖要命中');
    expect(d.shiftOn(day)!.name, isNot(d.teamShift(0, day)!.name),
        reason: '覆盖应当与那天的轮转结果不同（这天才选得有代表性）');
  });

  test('覆盖指向不存在的班次时忽略它，回退到轮转', () async {
    final (scheduleId, _) = await seed();
    final day = DateTime(2026, 9, 20);
    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: scheduleId,
            day: dayNumber(day),
            classId: 99999, // 悬空
          ),
        );

    final d = (await repo.getActiveSchedule())!;
    expect(d.dayOverrides, isEmpty, reason: '查不到的脏数据不该进领域模型');
    expect(d.shiftOn(day)!.name, d.teamShift(0, day)!.name);
  });

  test('覆盖表变化时 watchActiveSchedule 重新发值', () async {
    final (scheduleId, restId) = await seed();
    final day = DateTime(2026, 9, 20);

    final seen = <int>[];
    final sub = db.watchActiveSchedule().listen((s) {
      seen.add(s?.toDomain().dayOverrides.length ?? -1);
    });
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(seen, isNotEmpty, reason: '订阅时应该先发一次');
    expect(seen.last, 0);

    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: scheduleId,
            day: dayNumber(day),
            classId: restId,
          ),
        );
    await pumpEventQueue();

    expect(seen.last, 1,
        reason: '覆盖落库后流必须重发 —— 不重发的话日历纹丝不动，且不报错');
  });

  test('改方案名不动班次 id（从前会全变）', () async {
    final (scheduleId, _) = await seed();
    Future<List<int>> ids() async => (await (db.select(db.shiftClassRows)
              ..where((t) => t.scheduleId.equals(scheduleId))
              ..orderBy([(t) => OrderingTerm.asc(t.order)]))
            .get())
        .map((c) => c.id)
        .toList();

    final before = await ids();
    final d = (await repo.getActiveSchedule())!;
    await repo.saveSchedule(
      scheduleId: scheduleId,
      name: '我们组', // 只改名字
      anchorDate: d.anchorDate,
      classes: d.classes,
      cycle: d.cycle,
      teamCount: d.teamCount,
      teamNames: d.teamNames,
      ourTeamIndex: d.ourTeamIndex,
      teamOffsets: d.teamOffsets,
    );
    expect(await ids(), before,
        reason: '只改方案名却换了班次 id 的话，已设置的覆盖会全部指飞');
  });

  test('改班次时间也不动 id', () async {
    final (scheduleId, _) = await seed();
    final d = (await repo.getActiveSchedule())!;
    final edited = [...d.classes];
    edited[0] = edited[0].copyWith(startMinute: 9 * 60);
    await repo.saveSchedule(
      scheduleId: scheduleId,
      name: d.name,
      anchorDate: d.anchorDate,
      classes: edited,
      cycle: d.cycle,
      teamCount: d.teamCount,
      teamNames: d.teamNames,
      ourTeamIndex: d.ourTeamIndex,
      teamOffsets: d.teamOffsets,
    );
    final after = (await repo.getActiveSchedule())!;
    expect(after.classes[0].id, d.classes[0].id);
    expect(after.classes[0].startMinute, 9 * 60, reason: '改动本身要落库');
  });

  test('删掉一个班次时，引用它的覆盖连带被清掉', () async {
    final (scheduleId, restId) = await seed();
    final day = DateTime(2026, 9, 20);
    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: scheduleId,
            day: dayNumber(day),
            classId: restId,
          ),
        );

    final d = (await repo.getActiveSchedule())!;
    final kept = d.classes.where((c) => c.id != restId).toList();
    // 周期里指向被删班次的下标要跟着重映射，否则这次保存本身就坏了
    final keptIndex = {for (var i = 0; i < kept.length; i++) kept[i].id!: i};
    final cycle = d.cycle
        .map((ci) => keptIndex[d.classes[ci].id])
        .whereType<int>()
        .toList();
    await repo.saveSchedule(
      scheduleId: scheduleId,
      name: d.name,
      anchorDate: d.anchorDate,
      classes: kept,
      cycle: cycle,
      teamCount: d.teamCount,
      teamNames: d.teamNames,
      ourTeamIndex: d.ourTeamIndex,
      teamOffsets: d.teamOffsets,
    );

    expect(await db.select(db.shiftDayOverrides).get(), isEmpty,
        reason: '悬空的覆盖行要清掉，否则表里攒一堆指着空气的记录');
  });

  test('删方案 / 清空数据时连带删覆盖', () async {
    final (scheduleId, restId) = await seed();
    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: scheduleId,
            day: dayNumber(DateTime(2026, 9, 20)),
            classId: restId,
          ),
        );
    await repo.deleteSchedule(scheduleId);
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty);

    // clearAll 这条路也走一遍。**先重新挂一条覆盖**：deleteSchedule 之后
    // `seedIfEmpty` 重建的方案里本来就没有覆盖，不挂的话下面那句「empty」
    // 无论 clearAll 删没删覆盖都能通过 —— 断言不可能失败，等于没测。
    final reseeded = await db.select(db.shiftScheduleRows).getSingle();
    final rescheduledClass = (await (db.select(db.shiftClassRows)
              ..where((t) => t.scheduleId.equals(reseeded.id)))
            .get())
        .first;
    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: reseeded.id,
            day: dayNumber(DateTime(2026, 9, 22)),
            classId: rescheduledClass.id,
          ),
        );
    expect(await db.select(db.shiftDayOverrides).get(), isNotEmpty,
        reason: '先确认覆盖确实挂上了，否则下面那句断言不可能失败');

    await repo.clearAll();
    expect(await db.select(db.shiftDayOverrides).get(), isEmpty);
  });

  test('删班次的连带清理只作用于本方案，不碰别的方案', () async {
    // 方案 A（当前方案），并在它的「大休」班次上挂一条覆盖。
    final (aId, aRestId) = await seed();
    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: aId,
            day: dayNumber(DateTime(2026, 9, 20)),
            classId: aRestId,
          ),
        );

    // 方案 B（非当前方案）：自己的班次 + 自己的覆盖行。
    final b = defaultSchedule();
    final bId = await repo.saveSchedule(
      name: '乙方案',
      anchorDate: b.anchorDate,
      classes: b.classes,
      cycle: b.cycle,
      makeCurrent: false,
      teamCount: b.teamCount,
      teamNames: b.teamNames,
      ourTeamIndex: b.ourTeamIndex,
      teamOffsets: b.teamOffsets,
    );
    final bClasses = await (db.select(db.shiftClassRows)
          ..where((t) => t.scheduleId.equals(bId)))
        .get();
    final bRestId = bClasses.firstWhere((c) => c.isRest).id;
    await db.into(db.shiftDayOverrides).insert(
          ShiftDayOverridesCompanion.insert(
            scheduleId: bId,
            day: dayNumber(DateTime(2026, 9, 21)),
            classId: bRestId,
          ),
        );

    // 从 A 删掉「大休」并保存：悬空清理必须只扫 A 自己的班次。
    final d = (await repo.getActiveSchedule())!;
    final kept = d.classes.where((c) => c.id != aRestId).toList();
    final keptIndex = {for (var i = 0; i < kept.length; i++) kept[i].id!: i};
    final cycle = d.cycle
        .map((ci) => keptIndex[d.classes[ci].id])
        .whereType<int>()
        .toList();
    await repo.saveSchedule(
      scheduleId: aId,
      name: d.name,
      anchorDate: d.anchorDate,
      classes: kept,
      cycle: cycle,
      teamCount: d.teamCount,
      teamNames: d.teamNames,
      ourTeamIndex: d.ourTeamIndex,
      teamOffsets: d.teamOffsets,
    );

    final aOverrides = await (db.select(db.shiftDayOverrides)
          ..where((t) => t.scheduleId.equals(aId)))
        .get();
    expect(aOverrides, isEmpty, reason: 'A 上指向被删班次的覆盖要清掉');

    final bOverrides = await (db.select(db.shiftDayOverrides)
          ..where((t) => t.scheduleId.equals(bId)))
        .get();
    expect(bOverrides, hasLength(1),
        reason: '清理不能跨方案 —— 一句不带 where 的 delete 就会误删 B 的覆盖');

    final bAfter = await (db.select(db.shiftClassRows)
          ..where((t) => t.scheduleId.equals(bId)))
        .get();
    expect(bAfter.map((c) => c.id), contains(bRestId),
        reason: 'stale 查询若没按 scheduleId 过滤，会把 B 的班次行一起删掉');
  });

  test('setDayOverrides 一次写多天，clearDayOverrides 只清给定那几天', () async {
    final (_, restId) = await seed();
    final days = [
      DateTime(2026, 9, 18),
      DateTime(2026, 9, 19),
      DateTime(2026, 9, 20),
    ];
    await repo.setDayOverrides(days, classId: restId);

    final d = (await repo.getActiveSchedule())!;
    for (final day in days) {
      expect(d.dayOverrides.containsKey(dayNumber(day)), isTrue,
          reason: '${day.day} 号应当被覆盖');
    }
    expect(await repo.dayOverrideCount(), 3);

    await repo.clearDayOverrides([days.first]);
    expect(await repo.dayOverrideCount(), 2);
    final d2 = (await repo.getActiveSchedule())!;
    expect(d2.dayOverrides.containsKey(dayNumber(days.first)), isFalse);
    expect(d2.dayOverrides.containsKey(dayNumber(days[1])), isTrue,
        reason: '不在清理列表里的那天要保持原样');
  });

  test('setDayOverrides 覆盖已有的同一天（幂等更新，不报主键冲突）', () async {
    final (_, restId) = await seed();
    final day = DateTime(2026, 9, 18);
    await repo.setDayOverrides([day], classId: restId);
    await repo.setDayOverrides([day], classId: restId);
    expect(await repo.dayOverrideCount(), 1);
  });

  test('没有当前方案时 setDayOverrides 静默返回，不抛异常', () async {
    // 不 seed，库里空空如也
    await repo.setDayOverrides([DateTime(2026, 9, 18)], classId: 1);
    expect(await repo.dayOverrideCount(), 0);
  });

  // 闹钟的**顺序**是有意义的：它就是原生 id 里的「序号」。所以落库/读回都不许排序
  // —— 排序会让「重排之后 id 换号」，用户设过的响铃记录跟着错位（spec §6）。
  test('班次闹钟：按列表顺序落库、按 order 读回来，不许被排序', () async {
    await repo.saveSchedule(
      name: '两条闹钟',
      anchorDate: dateOnly(DateTime.now()),
      classes: const [
        ShiftClass(
          name: '白班',
          startMinute: 8 * 60 + 30,
          endMinute: 20 * 60 + 30,
          alarmEnabled: true,
          // **故意不按时钟顺序**：12:30 在 06:30 前面
          alarms: [
            ShiftAlarm(minute: 12 * 60 + 30, label: '午休'),
            ShiftAlarm(minute: 6 * 60 + 30, label: '起床'),
            ShiftAlarm(minute: 17 * 60 + 30),
          ],
        ),
      ],
      cycle: const [0],
      makeCurrent: true,
      teamCount: 1,
      teamNames: const ['我'],
      teamOffsets: const [0],
    );

    final s = (await repo.getActiveSchedule())!;
    expect(s.classes.single.alarms.map((a) => a.minute).toList(),
        [12 * 60 + 30, 6 * 60 + 30, 17 * 60 + 30],
        reason: '顺序 = 原生 id 的「序号」，排序会把它换掉');
    expect(s.classes.single.alarms.map((a) => a.label).toList(),
        ['午休', '起床', null], reason: '名字要原样回来');
    expect(s.classes.single.alarmEnabled, isTrue);
  });
}
