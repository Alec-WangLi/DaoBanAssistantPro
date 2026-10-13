// app/test/monthly_schedule_repository_test.dart
//
// 按月段表的仓库层：装配（库里存 classId、领域层要的是下标）、往返、
// 以及两条连带删除（删班次 / 删方案 / 清空重置）。
//
// 这里最要紧的是**装配**那一步：段行引用的 classId 要换算成 classes 下标，
// 换错了的症状是「日历上那几天显示成别的班」，不报错、也不崩。
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/monthly_pattern.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

void main() {
  late AppDatabase db;
  late AppRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppRepository(db);
  });

  tearDown(() => db.close());

  ShiftClass zhong() => const ShiftClass(name: '中班', abbr: '中');
  ShiftClass bai() => const ShiftClass(name: '白班', abbr: '白');
  ShiftClass ye() => const ShiftClass(name: '夜班', abbr: '夜');

  const threeSegs = [
    MonthlySegment(startDay: 1, classIndex: 0),
    MonthlySegment(startDay: 11, classIndex: 1),
    MonthlySegment(startDay: 21, classIndex: 2),
  ];

  /// 存一套按月方案；[classes] / [segments] / [teamSegOffsets] 可覆盖。
  Future<int> saveMonthly({
    int? scheduleId,
    List<ShiftClass>? classes,
    List<MonthlySegment> segments = threeSegs,
    int teamCount = 3,
    List<int> teamSegOffsets = const [0, 1, 2],
    bool makeCurrent = true,
  }) =>
      repo.saveSchedule(
        scheduleId: scheduleId,
        name: '按月排班',
        anchorDate: dateOnly(DateTime(2026, 1, 1)),
        classes: classes ?? [zhong(), bai(), ye()],
        cycle: const [],
        monthly: true,
        monthSegments: segments,
        teamCount: teamCount,
        teamNames: ['甲班', '乙班', '丙班'].take(teamCount).toList(),
        teamSegOffsets: teamSegOffsets,
        makeCurrent: makeCurrent,
      );

  test('往返：存一套按月方案，读回来逐项一致', () async {
    final id = await saveMonthly();
    final d = (await repo.getScheduleDomain(id))!;

    expect(d.monthly, isTrue);
    expect(d.cycle, isEmpty);
    expect(d.monthlySegments, threeSegs);
    expect(d.teamSegOffsets, [0, 1, 2]);
    expect(d.classes.map((c) => c.name), ['中班', '白班', '夜班']);
    // **下标换算对了**才有这个结果（库里存的是 classId，乱一位就显示成别的班）
    expect(d.shiftOn(DateTime(2026, 12, 1))!.name, '中班');
    expect(d.shiftOn(DateTime(2026, 12, 11))!.name, '白班');
    expect(d.shiftOn(DateTime(2026, 12, 21))!.name, '夜班');
    expect(d.shiftOn(DateTime(2026, 12, 31))!.name, '夜班');
    // 班组也串得对
    expect(d.teamShift(1, DateTime(2026, 12, 1))!.name, '白班');
    expect(d.teamShift(2, DateTime(2026, 12, 1))!.name, '夜班');
  });

  test('往返：改一次段表再存，读回来是新的那一份', () async {
    final id = await saveMonthly();
    await saveMonthly(
      scheduleId: id,
      segments: const [
        MonthlySegment(startDay: 1, classIndex: 2),
        MonthlySegment(startDay: 16, classIndex: 0),
      ],
    );
    final d = (await repo.getScheduleDomain(id))!;
    expect(d.monthlySegments.length, 2);
    expect(d.shiftOn(DateTime(2026, 12, 1))!.name, '夜班');
    expect(d.shiftOn(DateTime(2026, 12, 15))!.name, '夜班');
    expect(d.shiftOn(DateTime(2026, 12, 16))!.name, '中班');
  });

  test('往返：周期方案与按月方案在同一条时间线上各归各的', () async {
    final cycleId = await repo.saveSchedule(
      name: '四班两倒',
      anchorDate: dateOnly(DateTime(2026, 1, 6)),
      classes: [zhong(), bai()],
      cycle: const [0, 1],
      makeCurrent: false,
    );
    final monthId = await saveMonthly();
    final cycle = (await repo.getScheduleDomain(cycleId))!;
    final month = (await repo.getScheduleDomain(monthId))!;
    expect(cycle.monthly, isFalse);
    expect(cycle.monthlySegments, isEmpty);
    expect(cycle.isBlank, isFalse);
    expect(month.monthly, isTrue);
    expect(month.cycle, isEmpty);
    expect(month.isBlank, isFalse, reason: '按月方案不是空白表');
  });

  // RF-4：删掉一个还被段引用着的班次 —— 段行不许留下悬空的 classId
  test('删掉一个班次再存：引用它的段行一并清掉，库里没有悬空引用', () async {
    final id = await saveMonthly();
    final before = await db.select(db.shiftClassRows).get();
    final yeId = before.firstWhere((c) => c.name == '夜班').id;

    // 编辑器会先把引用它的那一段删掉（`_deleteClass` 在那儿拦着），这里模拟
    // 「班次没了、段表也重排过」之后的一次保存。
    await saveMonthly(
      scheduleId: id,
      classes: [zhong(), bai()],
      segments: const [
        MonthlySegment(startDay: 1, classIndex: 0),
        MonthlySegment(startDay: 16, classIndex: 1),
      ],
    );

    expect(await db.select(db.shiftClassRows).get(), hasLength(2));
    final segs = await db.select(db.scheduleMonthSegmentRows).get();
    expect(segs.map((s) => s.classId), isNot(contains(yeId)));
    final liveClassIds =
        (await db.select(db.shiftClassRows).get()).map((c) => c.id).toSet();
    for (final s in segs) {
      expect(liveClassIds, contains(s.classId), reason: '悬空的 classId');
    }
    final d = (await repo.getScheduleDomain(id))!;
    expect(d.monthlySegments.length, 2);
    expect(d.shiftOn(DateTime(2026, 12, 1))!.name, '中班');
  });

  test('deleteSchedule：这套方案的段行一起删掉', () async {
    final keep = await repo.saveSchedule(
      name: '另一套',
      anchorDate: dateOnly(DateTime(2026, 1, 1)),
      classes: [zhong()],
      cycle: const [0],
      makeCurrent: false,
    );
    final id = await saveMonthly();
    expect(await db.select(db.scheduleMonthSegmentRows).get(), hasLength(3));

    await repo.deleteSchedule(id);
    final left = await db.select(db.scheduleMonthSegmentRows).get();
    expect(left.where((s) => s.scheduleId == id), isEmpty);
    expect(await repo.getScheduleDomain(id), isNull);
    expect((await repo.getScheduleDomain(keep))!.monthly, isFalse);
  });

  test('clearAll：段行清空', () async {
    await saveMonthly();
    await repo.clearAll();
    expect(await db.select(db.scheduleMonthSegmentRows).get(), isEmpty);
  });

  test('段行按 order 读回来：顺序与存进去的一致', () async {
    final id = await saveMonthly(
      segments: const [
        MonthlySegment(startDay: 1, classIndex: 2),
        MonthlySegment(startDay: 6, classIndex: 0),
        MonthlySegment(startDay: 25, classIndex: 1),
      ],
    );
    final rows = await (db.select(db.scheduleMonthSegmentRows)
          ..where((t) => t.scheduleId.equals(id))
          ..orderBy([(t) => OrderingTerm.asc(t.order)]))
        .get();
    expect(rows.map((r) => r.startDay), [1, 6, 25]);
    final d = (await repo.getScheduleDomain(id))!;
    expect(d.monthlySegments.map((s) => s.startDay), [1, 6, 25]);
    expect(d.monthlySegments.map((s) => s.classIndex), [2, 0, 1]);
  });
}
