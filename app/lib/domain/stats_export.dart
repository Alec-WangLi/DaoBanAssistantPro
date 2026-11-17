// app/lib/domain/stats_export.dart
//
// 统计数据的 CSV 导出：纯函数，不碰文件系统，可直接单测。
//
// 口径与统计页**同源**（`shift_stats.dart`）：逐天判「上班 / 休息 / 整天请假 /
// 无班次 / 未排班」，工时 = 班次时长 − 请假；跨午夜的夜班整段算在上班开始那天。
// 差别只有一个：这里逐日出行，统计页是汇总。
//
// 表头与枚举顺序固定：字段勾选只决定**出现哪几列**，不改变列序 —— 同一个 App
// 导出的两份 CSV 永远能拼在一起。
import '../core/l10n.dart';
import 'day_extra.dart';
import 'lunar_info.dart';
import 'schedule_chain.dart';
import 'shift_rotation.dart';
import 'shift_stats.dart';

/// 可勾选的导出字段。声明顺序 = 列顺序。
enum StatsExportField {
  date,
  weekday,
  status,
  shift,
  times,
  hours,
  leaveKind,
  leave,
  overtime,
  night,
  holiday,
  note,
}

/// 导出结果：文件名、CSV 正文（带 BOM）、数据行数。
class StatsCsvResult {
  const StatsCsvResult({
    required this.fileName,
    required this.csv,
    required this.rowCount,
  });

  final String fileName;
  final String csv;
  final int rowCount;
}

String statsExportHeader(StatsExportField f) => switch (f) {
      StatsExportField.date => L10n.exportFieldDate,
      StatsExportField.weekday => L10n.exportFieldWeekday,
      StatsExportField.status => L10n.exportFieldStatus,
      StatsExportField.shift => L10n.exportFieldShift,
      StatsExportField.times => L10n.exportFieldTimes,
      StatsExportField.hours => L10n.exportFieldHours,
      StatsExportField.leaveKind => L10n.exportFieldLeaveKind,
      StatsExportField.leave => L10n.exportFieldLeave,
      StatsExportField.overtime => L10n.exportFieldOvertime,
      StatsExportField.night => L10n.exportFieldNight,
      StatsExportField.holiday => L10n.exportFieldHoliday,
      StatsExportField.note => L10n.exportFieldNote,
    };

/// 选择条上的**短标签**。
///
/// CSV 表头可以写全（「工时（小时）」），但字段 chip 在 200dp 小窗里只有约 76dp
/// 的内容宽 —— 5 个汉字就横向溢出。这里一律压到 4 个汉字 / 短英文，含义靠
/// 「导出统计」这个上下文自己说清楚。
String statsExportChipHeader(StatsExportField f) => switch (f) {
      StatsExportField.date => L10n.t('日期', 'Date'),
      StatsExportField.weekday => L10n.t('星期', 'Weekday'),
      StatsExportField.status => L10n.t('状态', 'Status'),
      StatsExportField.shift => L10n.t('班次', 'Shift'),
      StatsExportField.times => L10n.t('时间', 'Times'),
      StatsExportField.hours => L10n.t('工时', 'Hours'),
      StatsExportField.leaveKind => L10n.t('请假类型', 'Leave'),
      StatsExportField.leave => L10n.t('请假时长', 'Leave h'),
      StatsExportField.overtime => L10n.t('加班时长', 'Overtime'),
      StatsExportField.night => L10n.t('夜班', 'Night'),
      StatsExportField.holiday => L10n.t('节假日', 'Holiday'),
      StatsExportField.note => L10n.t('备注', 'Note'),
    };

/// 生成 [from]..[to]（闭区间）的逐日 CSV。
///
/// 空字段集仍会写表头：调用方禁止「一列都不选」（界面层拦），这里只做兜底。
StatsCsvResult buildStatsCsv({
  required ScheduleChain? chain,
  required Map<int, DayExtra> extras,
  required DateTime from,
  required DateTime to,
  required Set<StatsExportField> fields,
}) {
  final start = dayNumber(from);
  final end = dayNumber(to);
  final ordered = [
    for (final f in StatsExportField.values)
      if (fields.contains(f)) f,
  ];
  final rows = <String>[
    ordered.map((f) => _cell(statsExportHeader(f))).join(','),
  ];
  var count = 0;

  for (var n = start; n <= end; n++) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      n * Duration.millisecondsPerDay,
      isUtc: true,
    );
    final extra = extras[n];
    final leave = extra?.leaveMinutes ?? 0;
    final overtime = extra?.overtimeMinutes ?? 0;
    final shift = chain?.shiftOn(date);

    String status;
    int? worked;
    if (shift == null) {
      status = (chain?.hasScheduleOn(date) ?? false)
          ? L10n.exportStatusBlank
          : L10n.exportStatusUnscheduled;
    } else if (shift.isRest) {
      status = L10n.exportStatusRest;
    } else {
      final duration = shiftDurationMinutes(shift);
      final attended = duration == null || leave < duration;
      status =
          attended ? L10n.exportStatusWork : L10n.exportStatusFullLeave;
      if (attended && duration != null) {
        final w = duration - leave;
        worked = w > 0 ? w : 0;
      }
    }

    final values = <StatsExportField, String>{
      StatsExportField.date: L10n.isoDate(date),
      StatsExportField.weekday: L10n.weekdayShort(date),
      StatsExportField.status: status,
      StatsExportField.shift: shift?.name ?? '',
      StatsExportField.times: _timeRange(shift),
      StatsExportField.hours: worked == null ? '' : _hours(worked),
      StatsExportField.leaveKind:
          leave > 0 ? (L10n.leaveKindLabel(extra?.leaveKind) ?? '') : '',
      StatsExportField.leave: leave > 0 ? _hours(leave) : '',
      StatsExportField.overtime: overtime > 0 ? _hours(overtime) : '',
      StatsExportField.night: shift == null
          ? ''
          : (shift.isNight ? L10n.exportYes : L10n.exportNo),
      StatsExportField.holiday: holidayNameOf(date) ?? '',
      StatsExportField.note:
          L10n.dayExtraNoteLine(extra?.leaveNote, extra?.overtimeNote) ?? '',
    };

    rows.add(ordered.map((f) => _cell(values[f] ?? '')).join(','));
    count++;
  }

  // UTF-8 BOM：Windows 版 Excel 双击打开不认无 BOM 的 UTF-8 中文。
  final csv = '﻿${rows.join('\r\n')}\r\n';
  return StatsCsvResult(
    fileName: 'shift-stats-${L10n.isoDate(from)}_${L10n.isoDate(to)}.csv',
    csv: csv,
    rowCount: count,
  );
}

/// 分钟 → 小时。整小时不写 `.00`，半小时写 `.5`。
String _hours(int minutes) {
  final h = minutes / 60;
  final s = h.toStringAsFixed(2);
  return s
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// `08:00–20:00`；跨午夜在末尾标「（次日）」。
String _timeRange(ShiftClass? c) {
  final s = c?.startMinute, e = c?.endMinute;
  if (s == null || e == null) return '';
  final nextDay = e > 1440 || e < s;
  final endClock = formatClock(e > 1440 ? e - 1440 : e);
  final suffix = nextDay ? (L10n.isEn ? ' (+1d)' : '（次日）') : '';
  return '${formatClock(s)}–$endClock$suffix';
}

/// CSV 单元格转义：只在真的需要时加引号（Excel 对多余引号很敏感）。
String _cell(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n') ||
      s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}
