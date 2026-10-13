import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/monthly_pattern.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

void main() {
  const zhong = ShiftClass(name: '中班', abbr: '中', color: 0xFF00AA00);
  const bai = ShiftClass(name: '白班', abbr: '白', color: 0xFF0055FF);
  const ye = ShiftClass(name: '夜班', abbr: '夜', color: 0xFFFF8800);
  const xiu = ShiftClass(name: '休班', abbr: '休', isRest: true);

  const threeSegs = [
    MonthlySegment(startDay: 1, classIndex: 0),
    MonthlySegment(startDay: 11, classIndex: 1),
    MonthlySegment(startDay: 21, classIndex: 2),
  ];

  ShiftSchedule monthSchedule({
    List<MonthlySegment> segments = threeSegs,
    List<ShiftClass> classes = const [zhong, bai, ye],
    List<int> segOffsets = const [],
    int teams = 1,
  }) =>
      ShiftSchedule(
        name: '按月',
        // 按月模式不读基准日，随便给一个 —— 它必须仍在，因为列不是可空的。
        anchorDate: DateTime.utc(2020, 1, 1),
        classes: classes,
        cycle: const [],
        monthly: true,
        monthlySegments: segments,
        teamCount: teams,
        ourTeamIndex: 0,
        teamSegOffsets: segOffsets,
      );

  test('用户报的那个现象：12 月 1 日必须是中班，且整月切法正确', () {
    final s = monthSchedule();
    expect(s.shiftOn(DateTime(2026, 12, 1))!.name, '中班');
    expect(s.shiftOn(DateTime(2026, 12, 10))!.name, '中班');
    expect(s.shiftOn(DateTime(2026, 12, 11))!.name, '白班');
    expect(s.shiftOn(DateTime(2026, 12, 20))!.name, '白班');
    expect(s.shiftOn(DateTime(2026, 12, 21))!.name, '夜班');
    expect(s.shiftOn(DateTime(2026, 12, 31))!.name, '夜班');
  });

  test('四种月长下切法完全一样（31 / 30 / 28 / 闰年 29）', () {
    final s = monthSchedule();
    for (final m in [
      DateTime(2026, 1), // 31 天
      DateTime(2026, 4), // 30 天
      DateTime(2026, 2), // 28 天
      DateTime(2028, 2), // 闰年 29 天
    ]) {
      final days = DateTime(m.year, m.month + 1, 0).day;
      for (var d = 1; d <= days; d++) {
        final want = d <= 10 ? '中班' : (d <= 20 ? '白班' : '夜班');
        expect(s.shiftOn(DateTime(m.year, m.month, d))!.name, want,
            reason: '${m.year}-${m.month}-$d');
      }
    }
  });

  test('每月 1 日恒落在第一段', () {
    final s = monthSchedule();
    for (var m = 1; m <= 12; m++) {
      expect(s.shiftOn(DateTime(2026, m, 1))!.name, '中班', reason: '$m 月');
    }
  });

  // RF-1：起始日 29 的段在 2 月整月不出现，那些天落在**上一段**（不是空、不是别的班）
  test('起始日 29 的段遇上 2 月：整月都归上一段', () {
    final s = monthSchedule(segments: const [
      MonthlySegment(startDay: 1, classIndex: 0),
      MonthlySegment(startDay: 29, classIndex: 1),
    ]);
    for (var d = 1; d <= 28; d++) {
      expect(s.shiftOn(DateTime(2026, 2, d))!.name, '中班', reason: '2/$d');
    }
    expect(s.shiftOn(DateTime(2026, 1, 28))!.name, '中班');
    expect(s.shiftOn(DateTime(2026, 1, 29))!.name, '白班');
    expect(s.shiftOn(DateTime(2026, 1, 31))!.name, '白班');
  });

  test('单段：整月同一个班次', () {
    final s = monthSchedule(
        segments: const [MonthlySegment(startDay: 1, classIndex: 2)]);
    for (var d = 1; d <= 31; d++) {
      expect(s.shiftOn(DateTime(2026, 3, d))!.name, '夜班');
    }
  });

  test('段指到一个不存在的班次下标：返回 null，不抛', () {
    final s = monthSchedule(
        segments: const [MonthlySegment(startDay: 1, classIndex: 9)]);
    expect(s.shiftOn(DateTime(2026, 3, 3)), isNull);
  });

  test('段表全指向休班：不报撞班', () {
    final s = monthSchedule(
      segments: const [
        MonthlySegment(startDay: 1, classIndex: 0),
        MonthlySegment(startDay: 11, classIndex: 0),
      ],
      classes: const [xiu],
      teams: 3,
      segOffsets: const [0, 1],
    );
    expect(crewClashes(s), isEmpty);
  });

  // ── isBlank：这是 spec §3.5 那个坑的护栏 ──────────────────────────────────
  test('isBlank：按月模式下看段表，周期模式下只看周期 —— 两边可以同时非空', () {
    expect(monthSchedule().isBlank, isFalse);
    expect(monthSchedule(segments: const []).isBlank, isTrue, reason: '有模式没内容 = 空白表');

    // 切到按月、又切回按周期：段表还留在库里，而 monthly = false。
    // 这时候**必须走周期** —— 拿「段表非空」去猜模式就会让日历无视用户的选择。
    final backToCycle = ShiftSchedule(
      name: '切回周期',
      anchorDate: DateTime.utc(2025, 1, 6),
      classes: const [zhong, bai],
      cycle: const [0, 1],
      monthly: false,
      monthlySegments: threeSegs,
      teamSegOffsets: const [0, 1, 2],
    );
    expect(backToCycle.isBlank, isFalse);
    expect(backToCycle.shiftOn(DateTime(2025, 1, 6))!.name, '中班');
    expect(backToCycle.shiftOn(DateTime(2025, 1, 7))!.name, '白班');
    expect(backToCycle.shiftOn(DateTime(2025, 1, 8))!.name, '中班');
    // 2/6 距基准日 31 天（奇数），两天一倒 → 落在白班。走的确实是周期。
    expect(backToCycle.shiftOn(DateTime(2025, 2, 6))!.name, '白班');
  });

  // ── 班组按段错开：spec §3.3 那条推演的护栏 ────────────────────────────────
  test('三组三段：扫一整年，每天三组的班次两两不同且都非空', () {
    final s = monthSchedule(teams: 3, segOffsets: const [0, 1, 2]);
    for (var day = DateTime(2026, 1, 1);
        day.isBefore(DateTime(2027, 1, 1));
        day = DateTime(day.year, day.month, day.day + 1)) {
      final names = [for (var t = 0; t < 3; t++) s.teamShift(t, day)?.name];
      expect(names.whereType<String>().length, 3, reason: '$day 有人没班');
      expect(names.toSet().length, 3, reason: '$day 撞班：$names');
    }
    expect(crewClashes(s), isEmpty);
  });

  test('四组三段：报得出撞班，且当日号数落在 1..31', () {
    final s = monthSchedule(teams: 4, segOffsets: const [0, 1, 2, 3]);
    final clashes = crewClashes(s);
    expect(clashes, isNotEmpty);
    for (final c in clashes) {
      expect(c.cycleDay, inInclusiveRange(1, 31));
      expect(c.teamA, lessThan(c.teamB));
    }
  });

  test('单组（班组数 1）：永远不撞班', () {
    expect(crewClashes(monthSchedule()), isEmpty);
  });
}
