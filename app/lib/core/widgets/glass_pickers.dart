import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../glass/glass.dart';
import '../l10n.dart';
import 'glass_action_button.dart';

/// 玻璃时间选择器：底部玻璃弹层 + 时/分滚轮 + Q弹按钮。
Future<TimeOfDay?> showGlassTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black26,
    builder: (context) => _GlassTimePickerSheet(initialTime: initialTime),
  );
}

class _GlassTimePickerSheet extends StatefulWidget {
  const _GlassTimePickerSheet({required this.initialTime});
  final TimeOfDay initialTime;

  @override
  State<_GlassTimePickerSheet> createState() => _GlassTimePickerSheetState();
}

class _GlassTimePickerSheetState extends State<_GlassTimePickerSheet> {
  late int _hour = widget.initialTime.hour;
  late int _minute = widget.initialTime.minute;

  Widget _wheel({
    required int itemCount,
    required int initialItem,
    required ValueChanged<int> onChanged,
  }) {
    return CupertinoPicker(
      scrollController: FixedExtentScrollController(initialItem: initialItem),
      itemExtent: 40,
      onSelectedItemChanged: onChanged,
      selectionOverlay: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
          ),
        ),
      ),
      children: List.generate(itemCount, (i) {
        return Center(
          child: Text(
            '$i'.padLeft(2, '0'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      solid: true,
      margin: const EdgeInsets.all(12),
      borderRadius: const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                L10n.selectTime,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 180,
                child: Row(
                  children: [
                    Expanded(
                      child: _wheel(
                        itemCount: 24,
                        initialItem: _hour,
                        onChanged: (i) => _hour = i,
                      ),
                    ),
                    const Text(':',
                        style:
                            TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    Expanded(
                      child: _wheel(
                        itemCount: 60,
                        initialItem: _minute,
                        onChanged: (i) => _minute = i,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GlassActionButton(
                    onPressed: () => Navigator.pop(context),
                    label: L10n.cancel,
                  ),
                  GlassActionButton(
                    variant: GlassActionVariant.primary,
                    onPressed: () => Navigator.pop(
                        context, TimeOfDay(hour: _hour, minute: _minute)),
                    label: L10n.confirm,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 玻璃日期选择器：底部玻璃弹层 + 迷你日历网格（点选即返回）。
Future<DateTime?> showGlassDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black26,
    builder: (context) => _GlassDatePickerSheet(
      initialDate: initialDate,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime(2100),
    ),
  );
}

class _GlassDatePickerSheet extends StatefulWidget {
  const _GlassDatePickerSheet({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_GlassDatePickerSheet> createState() => _GlassDatePickerSheetState();
}

class _GlassDatePickerSheetState extends State<_GlassDatePickerSheet> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialDate.year, widget.initialDate.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final leading = DateTime(_month.year, _month.month, 1).weekday - 1;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final selected = widget.initialDate;

    final rows = <Widget>[];
    var rowCells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      rowCells.add(const Expanded(child: SizedBox()));
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_month.year, _month.month, d);
      final enabled = !date.isBefore(widget.firstDate) &&
          !date.isAfter(widget.lastDate);
      final isSelected = date.year == selected.year &&
          date.month == selected.month &&
          date.day == selected.day;
      rowCells.add(Expanded(
        child: GestureDetector(
          onTap: enabled ? () => Navigator.pop(context, date) : null,
          child: Container(
            height: 40,
            margin: const EdgeInsets.all(2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTokens.radiusS),
            ),
            child: Text(
              '$d',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (enabled
                        ? onSurface
                        : onSurface.withValues(alpha: 0.3)),
              ),
            ),
          ),
        ),
      ));
      if (rowCells.length == 7) {
        rows.add(Row(children: rowCells));
        rowCells = <Widget>[];
      }
    }
    if (rowCells.isNotEmpty) {
      while (rowCells.length < 7) {
        rowCells.add(const Expanded(child: SizedBox()));
      }
      rows.add(Row(children: rowCells));
    }

    return GlassPanel(
      solid: true,
      margin: const EdgeInsets.all(12),
      borderRadius: const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_outlined),
                    onPressed: () => setState(() => _month = DateTime(
                        _month.year, _month.month - 1, 1)),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        L10n.yearMonth(_month),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_outlined),
                    onPressed: () => setState(() => _month = DateTime(
                        _month.year, _month.month + 1, 1)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: List.generate(7, (i) {
                  return Expanded(
                    child: Center(
                      child: Text(
                        L10n.weekdays[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 4),
              ...rows,
            ],
          ),
        ),
      ),
    );
  }
}

/// 玻璃年月选择器：底部玻璃弹层 + 年份滚轮 + 4×3 月份网格（点选即返回）。
Future<DateTime?> showGlassMonthPicker(
  BuildContext context, {
  required DateTime initialMonth,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black26,
    builder: (context) => _GlassMonthPickerSheet(initialMonth: initialMonth),
  );
}

class _GlassMonthPickerSheet extends StatefulWidget {
  const _GlassMonthPickerSheet({required this.initialMonth});
  final DateTime initialMonth;

  @override
  State<_GlassMonthPickerSheet> createState() => _GlassMonthPickerSheetState();
}

class _GlassMonthPickerSheetState extends State<_GlassMonthPickerSheet> {
  static const _minYear = 2000;
  static const _maxYear = 2100;
  late int _year = widget.initialMonth.year;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentMonth = widget.initialMonth.month;

    return GlassPanel(
      solid: true,
      margin: const EdgeInsets.all(12),
      borderRadius: const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                L10n.jumpToMonth,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              // 年份滚轮
              SizedBox(
                height: 120,
                child: CupertinoPicker(
                  scrollController: FixedExtentScrollController(
                      initialItem: _year - _minYear),
                  itemExtent: 40,
                  onSelectedItemChanged: (i) =>
                      setState(() => _year = _minYear + i),
                  selectionOverlay: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTokens.radiusM),
                      border: Border.all(color: accent.withValues(alpha: 0.25)),
                    ),
                  ),
                  children: List.generate(_maxYear - _minYear + 1, (i) {
                    return Center(
                      child: Text(
                        '${_minYear + i}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 12),
              // 4×3 月份网格
              Column(
                children: List.generate(4, (r) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: List.generate(3, (c) {
                        final month = r * 3 + c + 1;
                        final isCurrent = month == currentMonth;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                Navigator.pop(context, DateTime(_year, month, 1)),
                            child: Container(
                              height: 40,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isCurrent ? accent : Colors.transparent,
                                borderRadius: BorderRadius.circular(AppTokens.radiusS),
                                border: isCurrent
                                    ? null
                                    : Border.all(
                                        color: Colors.white.withValues(
                                            alpha: isDark ? 0.12 : 0.6),
                                      ),
                              ),
                              child: Text(
                                L10n.monthShort(month),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isCurrent
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isCurrent ? Colors.white : onSurface,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
