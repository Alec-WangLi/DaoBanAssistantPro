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
}
