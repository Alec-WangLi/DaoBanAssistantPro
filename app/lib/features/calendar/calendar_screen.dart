import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../data/app_repository.dart';
import '../../domain/lunar_info.dart';
import '../../domain/shift_rotation.dart';
import '../../state/app_settings.dart';
import '../alarm/alarm_service.dart';
import 'schedule_editor_screen.dart';

/// 月历主界面：简约灰白背景 + 磨砂卡片日期格 + 农历 + 可拖拽玻璃选择块 + 底部信息卡。
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  static const _hPad = 12.0; // 网格左右留白
  static const _weekdayH = 26.0; // 周标题行高
  static const _aspect = 0.78; // 越小格子越高（0.78：格子加高，小屏 6 行放不下时网格自动滚动）
  static const _cellInset = 2.0; // 格子/玻璃块统一内缩

  late DateTime _month; // 显示月的 1 号
  late DateTime _selected; // 选中的日期（默认今天）

  bool _pressed = false; // 按下膨胀
  bool _dragActive = false; // 拖拽中（跟手，无过渡）
  double _visualCol = 0; // 选中块视觉列（连续小数，拖动时用）
  double _visualRow = 0; // 选中块视觉行（连续小数，拖动时用）
  double _grabCol = 0; // 手指相对选中块左缘的抓取偏移（列）
  double _grabRow = 0; // 手指相对选中块上缘的抓取偏移（行）

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month, 1);
    _selected = dateOnly(n);
  }

  void _prev() =>
      setState(() => _month = DateTime(_month.year, _month.month - 1, 1));
  void _next() =>
      setState(() => _month = DateTime(_month.year, _month.month + 1, 1));
  void _today() {
    final n = DateTime.now();
    setState(() {
      _month = DateTime(n.year, n.month, 1);
      _selected = dateOnly(n);
    });
  }

  Future<void> _showMonthPicker() async {
    final picked = await showGlassMonthPicker(context, initialMonth: _month);
    if (picked != null && mounted) {
      setState(() => _month = DateTime(picked.year, picked.month, 1));
    }
  }

  int get _leading => DateTime(_month.year, _month.month, 1).weekday - 1;
  int get _daysInMonth => DateTime(_month.year, _month.month + 1, 0).day;

  /// 选中日期在网格中的槽位矩形；不在本月返回 null。
  Rect? _selectedRect(double cellW, double cellH) {
    final first = DateTime(_month.year, _month.month, 1);
    final index = daysBetween(first, _selected) + _leading;
    if (index < _leading || index >= _leading + _daysInMonth) return null;
    final row = index ~/ 7;
    final col = index % 7;
    return Rect.fromLTWH(
        _hPad + col * cellW, _weekdayH + row * cellH, cellW, cellH);
  }

  /// 手指位置 → 选中日期（2D 拖拽/点按）。
  void _selectFromPosition(Offset pos, double cellW, double cellH) {
    final col = ((pos.dx - _hPad) / cellW).floor();
    final row = ((pos.dy - _weekdayH) / cellH).floor();
    if (col < 0 || col > 6 || row < 0) return;
    final index = row * 7 + col;
    if (index < _leading) return;
    final day = index - _leading + 1;
    if (day < 1 || day > _daysInMonth) return;
    final date = DateTime(_month.year, _month.month, day);
    if (date != _selected) setState(() => _selected = date);
  }

  /// 松手时：由选中块的连续视觉位置吸附到最近一格，返回该格日期（越界/空格返回 null）。
  DateTime? _nearestDateFromVisual() {
    final col = _visualCol.round();
    final row = _visualRow.round();
    if (col < 0 || col > 6 || row < 0) return null;
    final index = row * 7 + col;
    if (index < _leading) return null;
    final day = index - _leading + 1;
    if (day < 1 || day > _daysInMonth) return null;
    return DateTime(_month.year, _month.month, day);
  }

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(activeScheduleProvider);
    final schedule = scheduleAsync.valueOrNull?.toDomain();
    ref.watch(appSettingsProvider); // 语言切换时重建

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: scheduleAsync.isLoading && schedule == null
                  ? const Center(child: CircularProgressIndicator())
                  // 网格可滚动：格子保持全尺寸，小屏 6 行放不下时滚动而非被裁切，
                  // 避免底部行与信息卡重叠。
                  : SingleChildScrollView(
                      child: _buildGrid(context, schedule),
                    ),
            ),
            _infoCard(context, schedule),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          _circleIcon(
              context, Icons.chevron_left_outlined, L10n.prevMonth, _prev),
          const SizedBox(width: 6),
          Expanded(
            child: _glassPill(
              context,
              onTap: _showMonthPicker,
              child: Text(
                L10n.yearMonth(_month),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _circleIcon(
              context, Icons.chevron_right_outlined, L10n.nextMonth, _next),
          const SizedBox(width: 6),
          // 切换排班：纯图标圆形钮（省宽，保证年月完整显示）
          _circleIcon(context, Icons.swap_vert_outlined, L10n.switchSchedule,
              _showScheduleSwitcher),
          const SizedBox(width: 6),
          _glassPill(
            context,
            onTap: _today,
            accent: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.today_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  L10n.today,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 统一 40px 高的玻璃胶囊（accent=true 为主色调渐变，用于「今天」）。
  Widget _glassPill(
    BuildContext context, {
    VoidCallback? onTap,
    required Widget child,
    bool accent = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final decoration = accent
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusL),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primary.withValues(alpha: 0.30),
                primary.withValues(alpha: 0.14),
              ],
            ),
            border: Border.all(color: primary.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          )
        : BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusL),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.22),
                      Colors.white.withValues(alpha: 0.06),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.95),
                      Colors.white.withValues(alpha: 0.55),
                    ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.28 : 0.95),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: decoration,
          child: child,
        ),
      ),
    );
  }

  Widget _circleIcon(
      BuildContext context, IconData icon, String tooltip, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0.06),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.95),
                        Colors.white.withValues(alpha: 0.55),
                      ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.28 : 0.95),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
      ),
    );
  }

  Future<void> _switchSchedule(int id) async {
    final repo = ref.read(appRepositoryProvider);
    await repo.setCurrentSchedule(id);
    final sched = await repo.getScheduleDomain(id);
    if (sched != null && mounted) {
      final alarms = await repo.listCustomAlarms();
      final overrides = await repo.listShiftAlarmOverrides();
      await AlarmService.reschedule(sched, alarms, overrides: overrides);
    }
  }

  Future<void> _showScheduleSwitcher() async {
    // 预加载排班列表，避免弹窗内 ref.watch 不刷新导致列表为空
    final schedules = await ref.read(schedulesProvider.future);
    if (!mounted) return;
    final current = ref.read(activeScheduleProvider).valueOrNull;
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (context) {
        return GlassPanel(
          solid: true,
          margin: const EdgeInsets.all(12),
          borderRadius: const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L10n.switchSchedule,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ...schedules.map((s) {
                          final selected = s.id == current?.schedule.id;
                          return GlassPressable(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                selected
                                    ? Icons.check_circle_outlined
                                    : Icons.circle_outlined,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              title: Text(s.name),
                              subtitle: Text(L10n.teamCountN(
                                  parseTeamNames(s.teamNames).length)),
                              onTap: () async {
                                final name = s.name;
                                Navigator.pop(context); // 关弹窗，退回日历
                                await _switchSchedule(s.id);
                                if (mounted) {
                                  showGlassSnack(
                                    this.context,
                                    L10n.switchedTo(name),
                                    icon: Icons.swap_horiz_outlined,
                                  );
                                }
                              },
                            ),
                          );
                        }),
                        GlassPressable(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.add_outlined),
                            title: Text(L10n.addSchedule),
                            onTap: () async {
                              final d = defaultSchedule();
                              await ref
                                  .read(appRepositoryProvider)
                                  .saveSchedule(
                                    name: L10n.newSchedule,
                                    anchorDate: dateOnly(DateTime.now()),
                                    types: d.shiftTypes,
                                    makeCurrent: true,
                                  );
                              if (context.mounted) {
                                Navigator.pop(context);
                                final saved = await Navigator.of(context).push<bool>(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const ScheduleEditorScreen()));
                                if (saved == true && context.mounted) {
                                  showGlassSnack(
                                    context,
                                    L10n.savedAndRescheduled,
                                    icon: Icons.check_circle_outlined,
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGrid(BuildContext context, ShiftSchedule? schedule) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW = (constraints.maxWidth - _hPad * 2) / 7;
        final cellH = cellW / _aspect;
        final selectedRect = _selectedRect(cellW, cellH);
        final showBlock = _dragActive || selectedRect != null;
        final blockLeft = _dragActive
            ? _hPad + _visualCol * cellW
            : (selectedRect?.left ?? 0);
        final blockTop = _dragActive
            ? _weekdayH + _visualRow * cellH
            : (selectedRect?.top ?? 0);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            setState(() {
              _pressed = true;
              _dragActive = false;
            });
            _selectFromPosition(d.localPosition, cellW, cellH);
          },
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () {},
          onPanStart: (d) {
            final rect = _selectedRect(cellW, cellH);
            double startCol, startRow;
            if (rect != null) {
              startCol = (rect.left - _hPad) / cellW;
              startRow = (rect.top - _weekdayH) / cellH;
            } else {
              startCol =
                  ((d.localPosition.dx - _hPad) / cellW).floor().toDouble();
              startRow = ((d.localPosition.dy - _weekdayH) / cellH)
                  .floor()
                  .toDouble();
            }
            setState(() {
              _pressed = true;
              _dragActive = true;
              _visualCol = startCol;
              _visualRow = startRow;
              _grabCol = (d.localPosition.dx - _hPad) / cellW - startCol;
              _grabRow = (d.localPosition.dy - _weekdayH) / cellH - startRow;
            });
          },
          onPanUpdate: (d) {
            setState(() {
              _visualCol = (d.localPosition.dx - _hPad) / cellW - _grabCol;
              _visualRow = (d.localPosition.dy - _weekdayH) / cellH - _grabRow;
            });
          },
          onPanEnd: (_) {
            final date = _nearestDateFromVisual();
            setState(() {
              _pressed = false;
              _dragActive = false;
              if (date != null) _selected = date;
            });
          },
          child: ClipRect(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _hPad),
                  child: Column(
                    children: [
                      _weekdayRow(context, cellW),
                      ..._dayRows(context, cellW, cellH, schedule),
                    ],
                  ),
                ),
                if (showBlock)
                  AnimatedPositioned(
                    duration: _dragActive
                        ? Duration.zero
                        : AppTokens.durMed,
                    curve: Curves.easeOutCubic,
                    left: blockLeft,
                    top: blockTop,
                    width: cellW,
                    height: cellH,
                    child: AnimatedScale(
                      scale: _pressed ? 1.22 : 1.0,
                      duration: AppTokens.durMed,
                      curve: Curves.easeOutBack,
                      child: _glassBlock(context),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _weekdayRow(BuildContext context, double cellW) {
    final labels = L10n.weekdays;
    return SizedBox(
      height: _weekdayH,
      child: Row(
        children: List.generate(7, (i) => SizedBox(
              width: cellW,
              child: Center(
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ),
            )),
      ),
    );
  }

  List<Widget> _dayRows(
      BuildContext context, double cellW, double cellH, ShiftSchedule? schedule) {
    final today = dateOnly(DateTime.now());
    final cells = <Widget>[];
    for (var i = 0; i < _leading; i++) {
      cells.add(SizedBox(width: cellW, height: cellH));
    }
    for (var d = 1; d <= _daysInMonth; d++) {
      final date = DateTime(_month.year, _month.month, d);
      cells.add(_dayCell(context, date, schedule?.shiftOn(date), lunarOf(date),
          cellW, cellH, date == today));
    }
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      final chunk = cells.sublist(i, math.min(i + 7, cells.length));
      rows.add(Row(children: chunk));
    }
    return rows;
  }

  /// 磨砂卡片日期格。
  Widget _dayCell(BuildContext context, DateTime date, ShiftType? shift,
      LunarInfo lunar, double cellW, double cellH, bool isToday) {
    final lunarColor = lunar.isLegalHoliday
        ? AppTokens.holiday
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);

    return Container(
      width: cellW,
      height: cellH,
      child: Container(
        margin: const EdgeInsets.all(_cellInset),
        decoration: _cardDecoration(context),
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (shift != null)
                    Text(
                      _shortLabel(shift),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(shift.color),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (lunar.isMakeupWorkday)
                            TextSpan(
                              text: '班 ',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          TextSpan(text: lunar.shortLabel),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: lunarColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 信息卡上的「法定节假日 · 名称」红色胶囊。
  Widget _holidayBadge(BuildContext context, String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTokens.holiday.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        border: Border.all(color: AppTokens.holiday.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.celebration_outlined, size: 14, color: AppTokens.holiday),
          const SizedBox(width: 5),
          Text(
            '${L10n.legalHoliday} · $name',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTokens.holiday),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(AppTokens.radiusM),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.06),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  /// 可拖拽的玻璃选择块（与格子同 inset，精确覆盖）。
  Widget _glassBlock(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.all(_cellInset),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        color: accent.withValues(alpha: 0.13),
        border: Border.all(color: accent, width: 2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  /// 底部玻璃信息卡（完整分行）。
  Widget _infoCard(BuildContext context, ShiftSchedule? schedule) {
    final lunar = lunarOf(_selected);
    final shift = schedule?.shiftOn(_selected);
    final isToday = _selected == dateOnly(DateTime.now());
    final muted = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: 0.6);
    final accent = shift != null
        ? Color(shift.color)
        : Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      child: Stack(
        children: [
          GlassTile(
            padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(
              children: [
                Text(
                  L10n.monthDayWeekday(_selected),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
                if (isToday) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppTokens.radiusL),
                    ),
                    child: Text(
                      L10n.today,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            if (lunar.isLegalHoliday) ...[
              _holidayBadge(context, lunar.legalHolidayName),
              const SizedBox(height: 6),
            ],
            Text(
              lunar.fullDescription,
              style: TextStyle(
                fontSize: 13,
                color: lunar.isLegalHoliday ? AppTokens.holiday : muted,
              ),
            ),
            const SizedBox(height: 12),
            if (shift != null)
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: Color(shift.color), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    shift.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(shift.color),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (shift.startMinute != null && shift.endMinute != null)
                    Text(
                      _timeRange(shift),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                ],
              )
            else if (schedule != null && schedule.isBlank)
              Text(
                lunar.isLegalHoliday ? L10n.rest : L10n.workday,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: lunar.isLegalHoliday ? AppTokens.holiday : muted,
                ),
              )
            else
              Text(L10n.noSchedule,
                  style: TextStyle(fontSize: 13, color: muted)),
            const SizedBox(height: 8),
            if (shift != null)
              Text(
                _alarmText(shift),
                style: TextStyle(fontSize: 13, color: muted),
              ),
            if (schedule != null && schedule.teamCount > 1) ...[
              const SizedBox(height: 8),
              Text(
                _otherTeamsText(schedule, _selected),
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ],
        ),
      ),
          Positioned(
            left: 0,
            top: 18,
            bottom: 18,
            width: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    ),
    );
  }
}

String _shortLabel(ShiftType t) {
  if (t.isRest) return '休';
  if (t.name.contains('白') || t.name.contains('早')) return '白';
  if (t.name.contains('夜')) return '夜';
  return t.name.characters.first;
}

String _fmt(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

String _timeRange(ShiftType t) {
  final s = _fmt(t.startMinute!);
  final e = _fmt(t.endMinute!);
  if (t.crossesMidnight) return '$s – 次日$e';
  return '$s – $e';
}

String _alarmText(ShiftType t) {
  if (t.isRest) return L10n.restNoAlarm;
  if (!t.alarmEnabled || t.alarmMinute == null) return L10n.alarmOff;
  return L10n.alarmAt(_fmt(t.alarmMinute!));
}

String _otherTeamsText(ShiftSchedule schedule, DateTime date) {
  final parts = <String>[];
  for (var i = 0; i < schedule.teamCount; i++) {
    if (i == schedule.ourTeamIndex) continue;
    final t = schedule.teamShift(i, date);
    if (t == null) continue;
    final name = i < schedule.teamNames.length
        ? schedule.teamNames[i]
        : (L10n.isEn ? 'Team ${i + 1}' : '${i + 1}班');
    parts.add('$name·${t.name}');
  }
  return parts.isEmpty
      ? ''
      : '${L10n.otherTeamsPrefix}${parts.join(L10n.isEn ? '  ' : '　')}';
}
