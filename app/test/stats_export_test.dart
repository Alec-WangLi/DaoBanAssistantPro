// app/test/stats_export_test.dart
//
// 统计数据导出的纯函数：列序固定、每天一行、CSV 转义、字段勾选只改列不改口径。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/day_extra.dart';
import 'package:shiftassistantpro/domain/schedule_chain.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/stats_export.dart';

ShiftClass _work() => const ShiftClass(
    name: '白班', abbr: '白', startMinute: 480, endMinute: 1200);

ShiftClass _rest() => const ShiftClass(name: '休息', abbr: '休', isRest: true);

ShiftSchedule _sched() => ShiftSchedule(
      name: 't',
      anchorDate: DateTime.utc(2026, 11, 1),
      classes: [_work(), _rest()],
      cycle: const [0, 1],
      teamCount: 1,
      teamNames: const ['一班'],
      ourTeamIndex: 0,
      teamOffsets: const [0],
    );

DateTime _d(int day) => DateTime.utc(2026, 11, day);

void main() {
  final chain = ScheduleChain(fallback: _sched());
  final extras = <int, DayExtra>{
    dayNumber(_d(2)):
        const DayExtra(overtimeMinutes: 120, overtimeNote: '替班,两小时'),
    dayNumber(_d(3)): const DayExtra(
        leaveMinutes: 720, leaveKind: 'annual', leaveNote: '说"好"的假'),
  };

  StatsCsvResult run(Set<StatsExportField> fields) => buildStatsCsv(
        chain: chain,
        extras: extras,
        from: _d(1),
        to: _d(4),
        fields: fields,
      );

  test('BOM + 表头列序固定 + 每天一行', () {
    final r = run({...StatsExportField.values});
    expect(r.csv.startsWith('﻿'), isTrue, reason: 'Excel 认 BOM');
    final lines = r.csv.substring(1).trim().split('\r\n');
    expect(lines.length, 5, reason: '表头 + 4 天');
    expect(r.rowCount, 4);

    final header = lines.first.split(',');
    expect(header, [
      for (final f in StatsExportField.values) statsExportHeader(f),
    ]);
    expect(header.first, L10n.exportFieldDate);
  });

  test('上班 / 休息 / 整天请假 / 加班 / 备注都落对列', () {
    final r = run({...StatsExportField.values});
    final rows = r.csv.substring(1).trim().split('\r\n').skip(1).toList();
    final byDate = {
      for (final line in rows) line.split(',')[0]: line,
    };

    expect(byDate['2026-11-01'], contains(',${L10n.exportStatusWork},'));
    expect(byDate['2026-11-01'], contains(',12,'));
    expect(byDate['2026-11-02'], contains(',${L10n.exportStatusRest},'));
    expect(byDate['2026-11-02'], contains('"加班备注：替班,两小时"'),
        reason: '逗号必须进引号，否则 Excel 会多拆一列');
    expect(byDate['2026-11-03'], contains(',${L10n.exportStatusFullLeave},'));
    expect(byDate['2026-11-03'], contains(L10n.leaveKindLabel('annual')!));
    expect(byDate['2026-11-03'], contains('"请假备注：说""好""的假"'),
        reason: '引号按 CSV 规矩双写');
    expect(byDate['2026-11-04'], contains(',${L10n.exportStatusRest},'));
  });

  test('勾选字段只改列，不改变顺序', () {
    final r = run({
      StatsExportField.hours,
      StatsExportField.date,
    });
    final lines = r.csv.substring(1).trim().split('\r\n');
    expect(lines.first, '${L10n.exportFieldDate},${L10n.exportFieldHours}');
    expect(lines[1], '2026-11-01,12');
    expect(lines[2], '2026-11-02,');
  });

  test('跨午夜班次标「次日」，文件名叫 shift-stats-起_止.csv', () {
    final night = ShiftSchedule(
      name: 'n',
      anchorDate: DateTime.utc(2026, 11, 1),
      classes: const [
        ShiftClass(
            name: '夜班',
            abbr: '夜',
            startMinute: 1230,
            endMinute: 510,
            isNight: true),
      ],
      cycle: const [0],
      teamCount: 1,
      teamNames: const ['一班'],
      ourTeamIndex: 0,
      teamOffsets: const [0],
    );
    final r = buildStatsCsv(
      chain: ScheduleChain(fallback: night),
      extras: const {},
      from: _d(1),
      to: _d(1),
      fields: {StatsExportField.times, StatsExportField.hours},
    );
    expect(r.fileName, 'shift-stats-2026-11-01_2026-11-01.csv');
    final row = r.csv.substring(1).trim().split('\r\n')[1];
    expect(row, contains('20:30–08:30'));
    // 后缀本身也要钉住：只断言时间范围的话，把「（次日）」改坏这条用例照样绿
    // （独立审查 v0.14.0 抓到的）。
    expect(row, contains('（次日）'));
    expect(row, contains('12'));

    // 英文档用的是另一套标记（` (+1d)`），同样钉住 —— 帮助页里写的就是它。
    L10n.locale = 'en';
    addTearDown(() => L10n.locale = 'zh');
    final rEn = buildStatsCsv(
      chain: ScheduleChain(fallback: night),
      extras: const {},
      from: _d(1),
      to: _d(1),
      fields: {StatsExportField.times, StatsExportField.hours},
    );
    final rowEn = rEn.csv.substring(1).trim().split('\r\n')[1];
    expect(rowEn, contains('20:30–08:30 (+1d)'));
  });
}
