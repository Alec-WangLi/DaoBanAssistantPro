import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/layout.dart';
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
import 'shift_template_picker_screen.dart';

/// 月历主界面：简约灰白背景 + 磨砂卡片日期格 + 农历 + 可拖拽玻璃选择块 + 底部信息卡。
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  static const _hPad = 12.0; // 网格左右留白
  static const _weekdayH = 26.0; // 周标题行高
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

  /// 本月网格占几行（含月初的空格）。
  int get _weekRows => (_leading + _daysInMonth + 6) ~/ 7;

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
        child: Builder(builder: (context) {
          final layout = AppLayout.of(context);
          final gridArea = Expanded(
            // 网格区高度要先量出来，才能决定格子长多高（见 _buildGrid）。
            child: LayoutBuilder(
              builder: (context, c) => scheduleAsync.isLoading && schedule == null
                  ? const Center(child: CircularProgressIndicator())
                  // 网格可滚动：格子保持全尺寸，小屏 6 行放不下时滚动而非被裁切，
                  // 避免底部行与信息卡重叠。
                  : SingleChildScrollView(
                      child: _buildGrid(context, schedule, c.maxHeight),
                    ),
            ),
          );

          return Column(
            children: [
              _header(context),
              // 宽屏左右分栏：网格与信息卡并排，网格拿到的可用高度从
              // 「减去底部信息卡」变成「整屏高度」，格子不用再被压扁。
              if (layout.isWide)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      gridArea,
                      const SizedBox(width: AppTokens.spaceMd),
                      SizedBox(
                        width: 300,
                        child: SingleChildScrollView(
                          child: _infoCard(context, schedule, inSidePane: true),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                gridArea,
                _infoCard(context, schedule, compact: layout.isShort),
              ],
            ],
          );
        }),
      ),
    );
  }

  Widget _header(BuildContext context) {
    const pad = EdgeInsets.fromLTRB(12, 10, 12, 6);
    // 窄档（小窗实测 200 逻辑像素宽）一行放不下 —— 四个圆形钮加年月胶囊的
    // **固定**宽度是 184，而 200 宽的屏扣掉左右留白只剩 176：年月那个
    // Expanded 会被挤成 0 宽，整行溢出。
    // 拆成两行：上行只放「‹ 年月 ›」（年月能拿到 104），下行放「切换排班 / 今天」。
    // 控件收到 32 见方：一是给年月腾出完整显示「2026年9月」的宽度（36 见方时
    // 真机上只剩 76 可用，MiSans 下会被省略成「2026年…」），二是省下 10px 高度。
    if (AppLayout.of(context).isNarrow) {
      const narrowSide = 32.0;
      const narrowGap = 4.0;
      return Padding(
        padding: pad,
        child: Column(
          children: [
            Row(
              children: [
                _circleIcon(context, Icons.chevron_left_outlined, L10n.prevMonth,
                    _prev, size: narrowSide),
                const SizedBox(width: narrowGap),
                Expanded(
                  child: _glassPill(
                    context,
                    onTap: _showMonthPicker,
                    height: narrowSide,
                    child: Text(
                      L10n.yearMonth(_month),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: narrowGap),
                _circleIcon(context, Icons.chevron_right_outlined, L10n.nextMonth,
                    _next, size: narrowSide),
              ],
            ),
            const SizedBox(height: narrowGap),
            Row(
              children: [
                _circleIcon(context, Icons.swap_vert_outlined,
                    L10n.switchSchedule, _showScheduleSwitcher, size: narrowSide),
                const Spacer(),
                _glassPill(
                  context,
                  onTap: _today,
                  accent: true,
                  height: narrowSide,
                  // 窄档连年月都要省着放，「今天」只留图标（整屏的窄档同样如此）。
                  child: const Icon(
                    Icons.today_outlined,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: pad,
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
            // accent 变体是实心主色底，内容用白（别再跟着 colorScheme.primary，
            // 那样就是主色字压在主色底上）。
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.today_outlined,
                  size: 18,
                  color: Colors.white,
                ),
                // 320 宽下「今天」两个字会挤掉年月的显示宽度，窄屏只留图标。
                if (!AppLayout.of(context).isNarrow) ...[
                  const SizedBox(width: 4),
                  Text(
                    L10n.today,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.98),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 统一 40px 高的玻璃胶囊（accent=true 为主色调渐变，用于「今天」）。
  /// 窄档传 36 —— 小窗里每一像素都要省。
  Widget _glassPill(
    BuildContext context, {
    VoidCallback? onTap,
    required Widget child,
    bool accent = false,
    double height = 40,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final decoration = accent
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusL),
            // 实心主色 + 白字。原来是「主色 30% 透明度的底 + 主色字」——
            // 同一个色相只差透明度，实测对比度浅色 3.0:1、深色 2.7:1，都低于
            // WCAG AA 要求的 4.5:1，深色下那两个字几乎看不见。
            // 改成实心后是 5.3:1（渐变深处 7:1），也跟主按钮（新增排班、
            // 保存并重排闹钟）的实心主色形态一致。
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primary,
                Color.lerp(primary, Colors.black, 0.18)!,
              ],
            ),
            border: Border.all(color: primary),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: isDark ? 0.45 : 0.28),
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
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: decoration,
          child: child,
        ),
      ),
    );
  }

  Widget _circleIcon(BuildContext context, IconData icon, String tooltip,
      VoidCallback onTap,
      {double size = 40}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
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
                              // 与「我的 → 排班管理 → 新增排班」共用同一条
                              // 选择倒班方式的入口，日历进来的用户也能看到模板库。
                              final id = await createScheduleFromTemplatePicker(
                                  context, ref,
                                  makeCurrent: true);
                              if (id == null || !mounted) return;
                              final nav = Navigator.of(this.context);
                              nav.pop(); // 关弹窗，退回日历
                              final saved = await nav.push<bool>(
                                  MaterialPageRoute(
                                      builder: (_) => ScheduleEditorScreen(
                                          scheduleId: id)));
                              if (saved == true && mounted) {
                                showGlassSnack(
                                  this.context,
                                  L10n.savedAndRescheduled,
                                  icon: Icons.check_circle_outlined,
                                );
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

  Widget _buildGrid(
      BuildContext context, ShiftSchedule? schedule, double availHeight) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW = (constraints.maxWidth - _hPad * 2) / 7;
        final cellH = calendarCellHeight(
          cellW: cellW,
          // 预留 2px：cellH 按剩余空间均分算出来后，网格内容的高度就
          // **正好等于**可用高度，一行都不多 —— 真机上一旦有亚像素取整，
          // 最后一行就会被滚动容器裁掉一条。留 2px 让内容稳稳落在视口内。
          // （真正的大头是 _minCellH 曾经顶得比视口还高，见那里的说明。）
          availHeight: availHeight - 2,
          weekRows: _weekRows,
          weekdayH: _weekdayH,
          // 窄屏 / 短屏上格子可以更「瘦高」一些：格子本来就窄，再按 0.62
          // 卡住高度就装不下三行字了。竖屏不传这个参数，用的还是 0.62。
          aspectMin: (AppLayout.of(context).isNarrow ||
                  AppLayout.of(context).isShort)
              ? 0.46
              : _cellAspectMin,
        );
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
  Widget _dayCell(BuildContext context, DateTime date, ShiftClass? shift,
      LunarInfo lunar, double cellW, double cellH, bool isToday) {
    final lunarColor = lunar.isLegalHoliday
        ? AppTokens.holiday
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    // 班次色是给色块用的强色，当 12px 文字色会太浅（橙 2.06:1、灰 2.60:1），
    // 得按格子底色算一版可读的。
    final surface = Theme.of(context).colorScheme.surface;

    return SizedBox(
      width: cellW,
      height: cellH,
      child: Container(
        margin: const EdgeInsets.all(_cellInset),
        decoration: _cardDecoration(context),
        child: Stack(
          children: [
            Positioned.fill(
              // 整格内容一起可缩，而不是让某一行自己想办法。
              //
              // 格子高度是按**剩余空间**均分的（`calendarCellHeight`），并不会
              // 跟着系统字号长 —— 用户把字号调到 1.2 倍以上，三行字就高过
              // 格子，Column 报 BOTTOM OVERFLOWED、release 下被裁字。外层的
              // 滚动容器救不了这里：它管的是「整个网格高过视口」，管不到
              // 「字高过格子」。
              //
              // 宽度给死值，所以 scaleDown 只在**高度**不够时才动手；正常
              // 字号下一像素都不缩，和没有这一层完全一样。
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: cellW - _cellInset * 2,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 两位数在小窗格子里会折成两行（「10」变「1」「0」）——
                      // 小窗格子只有 ~25 宽，18px 的两个数字刚好卡在边界上，
                      // 换个字体就翻过去。用 FittedBox 按需缩，不赌字体宽度。
                      // 竖屏/横屏格子够宽，缩放不生效，仍是原来的 18px。
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${date.day}',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 18,
                            // 显式压紧行盒：M3 默认行高 1.5，三行文字的行盒加起来
                            // 比格子可用高度多出几个像素，真机上每个格子都会
                            // BOTTOM OVERFLOWED（content 被裁）。
                            height: 1.15,
                            fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (shift != null)
                        Text(
                          shift.shortLabel,
                          // 简称上限是 1–2 字，但格宽固定，多一个字就会撑破竖向
                          // 节奏；单行 + 省略号让任何长度都不破版。
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            color: AppTokens.inkFor(Color(shift.color), surface),
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
                          style:
                              TextStyle(fontSize: 11, height: 1.15, color: lunarColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 信息卡上的「法定节假日 + 节日名」红色胶囊。
  ///
  /// **配方与「其他班组」色块同一套**（14% 淡染底 / 45% 描边 / `radiusS` /
  /// 文字走 [AppTokens.inkFor]）—— 两者是同一类「信息胶囊」，没理由两套。
  /// 这里原来单独一套（12% / 35% / `radiusL` / 原色字），原色红压在同色淡底
  /// 上只有 3.46:1（浅色）/ 3.37:1（深色），两套主题都够不到 AA 的 4.5:1；
  /// 调度色块那条路径正是为此才走 `inkFor`。
  ///
  /// 图标 + 「法定节假日」+ 节日名**一行**放下：徽章自占一行，宽度不再是稀缺
  /// 资源，不必再拆成上下两行、也不必把标签缩到 9px。大小与字重（12/w600 对
  /// 14/w700）留给主次关系。
  Widget _holidayBadge(BuildContext context, String name) {
    final surface = Theme.of(context).colorScheme.surface;
    final ink = AppTokens.inkFor(
        AppTokens.holiday,
        Color.alphaBlend(
            AppTokens.holiday.withValues(alpha: 0.14), surface));
    return Container(
      key: const Key('info-card-holiday-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTokens.holiday.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTokens.radiusS),
        border: Border.all(color: AppTokens.holiday.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.celebration_outlined, size: 14, color: ink),
          const SizedBox(width: 5),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: L10n.legalHoliday,
                    style: TextStyle(
                      fontSize: AppTokens.fontCaption,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: name,
                    style: TextStyle(
                      fontSize: AppTokens.fontBody,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
  Widget _infoCard(BuildContext context, ShiftSchedule? schedule,
      {bool inSidePane = false, bool compact = false}) {
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

    // 短屏（手机横屏 / 小窗）走单行紧凑版：360×360 这类窗口里网格才是主角，
    // 完整信息卡（约 340 高）会把网格挤到只剩一条缝。这里保留
    // 「哪天 · 什么班 · 几点到几点」，带上闹钟图标；农历、今天徽章与其他
    // 班组收起来 —— 网格上本来就直接画着班次与农历，信息没有丢。
    if (compact) {
      final timeText =
          (shift != null && shift.startMinute != null && shift.endMinute != null)
              ? _timeRange(shift)
              : null;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 76),
        child: GlassTile(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(AppTokens.radiusS),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  [
                    L10n.monthDayWeekday(_selected),
                    if (shift != null) shift.name,
                    if (timeText != null) timeText,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: AppTokens.fontSupport,
                      fontWeight: FontWeight.w600),
                ),
              ),
              if (shift != null && shift.alarmEnabled)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.alarm_outlined, size: 16, color: muted),
                ),
            ],
          ),
        ),
      );
    }

    final content = Column(
      key: const Key('info-card-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              L10n.monthDayWeekday(_selected),
              // w700 而不是 w800：设计规格第 3.7 节把字重收成「标题 w700 /
              // 强调 w600 / 正文 w500」，w800 只留给响铃大时钟。
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (isToday) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  // 实心主色 + 白字。原来是「主色 14% 淡底 + 主色字」，
                  // 实测对比度 3.84:1（深色下 2.93:1），低于 AA 的 4.5:1。
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(AppTokens.radiusL),
                ),
                child: Text(
                  L10n.today,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppTokens.spaceSm),
        // 节假日徽章自占一行、农历独占下一行。
        //
        // 这两条曾经并排过，理由是「徽章自占一行的话，放假那天卡片凭空高 24，
        // 上面六个格子就集体矮一截」。但卡片 v0.6.6 起是**定高**的，多出来的
        // 内容由定高吸收、网格不再跟着抖 —— 那条理由已经不成立。代价却是实打
        // 实的：徽章连图标带「法定节假日 · 」有一百多 dp 宽，把农历挤到右边只
        // 剩一半宽度，两行都显示不全（v0.6.7 用户实测）。
        if (lunar.isLegalHoliday) ...[
          _holidayBadge(context, lunar.legalHolidayName),
          // 徽章是给下面这行农历作注解的，贴紧一点成一组。
          const SizedBox(height: AppTokens.spaceXs),
        ],
        Text(
          lunar.fullDescription,
          // 两行封顶：整行宽度下通常一行就够，窄屏最多两行，再长就省略号。
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: lunar.isLegalHoliday ? AppTokens.holiday : muted,
          ),
        ),
        // 段与段之间一律用栅格上的 12（原来这里是 10，不在 4px 栅格上）。
        const SizedBox(height: AppTokens.spaceMd),
        // 班次名、时间、闹钟**同一行**。分开写要两行（一行文字 + 它的间距，
        // 约 26dp），而卡片内部可用高度只有 210dp —— 六班组那种排满的日子
        // 本来就已经被底边裁掉一截（v0.6.7 实测 224dp）。
        //
        // 三段并成一段富文本，是为了让省略号落对地方：各自 Flexible 的话，
        // 剩余宽度会被三等分，最长的时间串（「20:30 – 次日08:30」）反而先
        // 被截掉。并成一段后按「班次名 → 时间 → 闹钟」的顺序从尾部省略，
        // 优先级正好反过来。
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
              Expanded(
                child: Text.rich(
                  key: const Key('info-card-shift-line'),
                  TextSpan(
                    children: [
                      TextSpan(
                        text: shift.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.inkFor(Color(shift.color),
                              Theme.of(context).colorScheme.surface),
                        ),
                      ),
                      if (shift.startMinute != null && shift.endMinute != null)
                        TextSpan(
                          text: '  ${_timeRange(shift)}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      TextSpan(
                        text: '   ${_alarmText(shift)}',
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
          Text(L10n.noSchedule, style: TextStyle(fontSize: 13, color: muted)),
        if (schedule != null && schedule.teamCount > 1) ...[
          const SizedBox(height: AppTokens.spaceMd),
          // 标签与色块同一行：标签独占一行要白占 12 + 16 + 6 = 34dp，而
          // 6 个班组要**两行**色块 —— 那两行必须留得住，否则最后一行会被
          // 卡片底边裁掉（正是 v0.6.7 实测到的问题）。标签还在、还在左边，
          // 只是不再独占一行。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(L10n.otherCrews,
                    style: TextStyle(fontSize: 12, color: muted)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _otherCrewChips(schedule, _selected),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    // 底栏时面板必须**撑满**那个定高盒子。`Stack` 默认 `StackFit.loose`，
    // 只给非定位子节点松约束，面板于是缩到内容高度；而左侧色条是
    // `Positioned(top: 18, bottom: 18)`，量的却是外面那个定高盒子 —— 两边
    // 各按各的高度走，色条就比卡片长出几十 dp、垂在空白里（v0.6.6 用户
    // 实测：卡片 126 高，色条 212 高）。给面板一层定高，两者才对得上。
    //
    // 右栏那份反过来要贴内容高度：那边没有「撑满」的必要，也就没有空档，
    // 所以不套这层，色条跟着面板走本来就是对的。
    final panel = GlassTile(
      key: const Key('info-card-panel'),
      padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
      child: inSidePane
          ? content
          // 兜底：字号被系统放大到装不下时，卡片内部滚动，而不是溢出成
          // 黄黑条纹。正常字号下内容矮于卡片，这一层不产生任何滚动。
          : SingleChildScrollView(child: content),
    );

    final card = Stack(
      children: [
        SizedBox(
          key: const Key('info-card-box'),
          height: inSidePane ? null : _infoCardHeight,
          child: panel,
        ),
        Positioned(
          left: 0,
          top: 18,
          bottom: 18,
          width: 6,
          child: DecoratedBox(
            key: const Key('info-card-accent-bar'),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
    );

    return Padding(
      // 底栏时要给悬浮胶囊让出高度（竖屏 96，短屏 76）；右栏时胶囊在
      // 屏幕底部、与这一栏无关，只需要常规留白。竖屏的 96 = 胶囊高 64
      // + 32 余量：84 时卡片底边几乎贴在胶囊上（v0.6.7 用户实测），
      // 又放开了 12。上界是网格给的：再往上加，6 行的月份会被挤出视口。
      padding: inSidePane
          ? const EdgeInsets.fromLTRB(0, 8, 16, 16)
          : const EdgeInsets.fromLTRB(16, 8, 16, 96),
      child: card,
    );
  }


  /// 其他班组当天班次：色点 + 组名 + 简称，横向换行，6 个班组也放得下。
  List<Widget> _otherCrewChips(ShiftSchedule schedule, DateTime date) {
    final chips = <Widget>[];
    for (var i = 0; i < schedule.teamCount; i++) {
      if (i == schedule.ourTeamIndex) continue;
      final t = schedule.teamShift(i, date);
      if (t == null) continue;
      final name = i < schedule.teamNames.length
          ? schedule.teamNames[i]
          : (L10n.isEn ? 'Team ${i + 1}' : '${i + 1}班');
      chips.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Color(t.color).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppTokens.radiusS),
          border: Border.all(color: Color(t.color).withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: Color(t.color), shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text('$name ${t.shortLabel}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    // 色块底是班次色 14% 的淡染，字要按它算可读版本。
                    color: AppTokens.inkFor(
                        Color(t.color),
                        Color.alphaBlend(
                            Color(t.color).withValues(alpha: 0.14),
                            Theme.of(context).colorScheme.surface)))),
          ],
        ),
      ));
    }
    return chips;
  }
}

String _timeRange(ShiftClass t) {
  var e = t.endMinute!;
  final nextDay = e > 1440 || e < t.startMinute!;
  if (e > 1440) e -= 1440;
  return L10n.timeRange(formatClock(t.startMinute!), formatClock(e), nextDay);
}

String _alarmText(ShiftClass t) {
  if (t.isRest) return L10n.restNoAlarm;
  if (!t.alarmEnabled || t.alarmMinute == null) return L10n.alarmOff;
  return L10n.alarmAt(formatClock(t.alarmMinute!));
}

/// 信息卡（完整版）在**底栏**时的固定高度。
///
/// 为什么必须是定值：竖屏下这一页是
/// `Column[顶栏, Expanded(网格), 信息卡]`，而格子高度是按**剩余空间**算的
/// （`calendarCellHeight(availHeight:)`）。信息卡只要随当天内容长高一像素，
/// 六个格子就集体矮一像素、选下一天再弹回来 —— 点一天晃一次。
///
/// 也不能反过来把网格与卡片解耦（留白、或让网格自己滚动）：v0.6.1 刚把
/// 「网格与信息卡之间的一条空带」消掉，那条空带是明确不接受的。所以只能让
/// 卡片自己定高，把多出来的空间留在卡片内部 —— 它是一块面板，不是一条
/// 会伸缩的条。
///
/// 取值 = 内容最坏情况（今天徽章 + 两行法定节假日（v0.6.6 起农历描述
/// 允许换行）+ 班次 + 闹钟 + 其他班组色块换到第二行）在 420 宽、标准字号
/// 下的高度，再留一点余量。字号被系统放大到装不下时，由卡片内部的滚动
/// 兜底，不会溢出。
///
/// 定高的下界由 `calendar_screen_test.dart` 的「点开某天」用例盯着：它把整月
/// 每一天都点一遍，断言内容装得下、且不要留太多空白。
const double _infoCardHeight = 248;

// 格子高宽比：0.78 = 自然比例，0.62 = 「不许再瘦」的下限比例（越小格子越高）。
const double _cellAspect = 0.78;
const double _cellAspectMin = 0.62;

/// 格子高的下限 = **格子里的三行字实测要多高**。
///
/// 三行都是单行文字（日期 18、班次简称 12、农历 11，各自 `height: 1.15`
/// 压过行盒）：18×1.15 + 2 + 12×1.15 + 2 + 11×1.15 ≈ 51.5，再加格子自身
/// `_cellInset` 上下各 2 一共 4 —— 约 55.5。取 58，留 2.5 的字体度量余量。
///
/// **曾经是 80**，那是 `height: 1.15` 压行盒之前按 M3 默认行高 1.5 标定的
/// （27 + 2 + 18 + 2 + 16.5 + 4 ≈ 70，再垫到 80）。行盒压紧后这个数一直没
/// 跟着降，于是下限反过来把**网格**顶出了视口：400×869 的手机上网格视口
/// 只有 405dp，五行的月份被顶到 26+5×80=426（溢出 21dp）、六行的顶到 506
/// （溢出 101dp），最后一行被 `SingleChildScrollView` 裁在信息卡上沿 ——
/// 用户看到的就是「最后一行被卡片压住」（v0.6.5 实测）。
///
/// 下限只该管「三行字装不装得下」，不管别的；把它抬到内容需求之上，就等于
/// 让网格自己制造溢出。真正的兜底是外层那个滚动容器：空间确实不够时滚动，
/// 而不是把每一格都撑破视口。
///
/// 字号被系统放大时格子**不会**跟着长高，那是 `_dayCell` 里那层
/// `FittedBox` 的事 —— 内容按需缩，不由这个下限兜。
const double _minCellH = 58;

/// 日历格子高度：**宽高共同决定**。
///
/// 抽成顶层纯函数是为了能直接断言「横屏进入压缩分支」——
/// `SingleChildScrollView` 的尺寸是它的视口（等于可用高度），不是内容高度，
/// 拿它测不出压缩。
///
/// 空间富余时拉高，但不超过 [_cellAspectMin] 那道「不许再瘦」的比例；
/// 空间不足时**压缩到够用**，但不低于可读下限。
///
/// 原来空间不足时直接取 `cellW / _cellAspect`（只按宽度算）：横屏下 cellW 大
/// → 格子高 160 → 一个月六行要 960px，一屏只看得到一行多。那道「不许再瘦」
/// 的下限只在富余时生效、不足时反而没有任何压缩通道，逻辑正好反了。
///
/// [_minCellH] 那道下限**必须作用在最终值上**，不能只挂在其中一个分支里。
/// 宽屏上 `cellW / aspectMin` 大，走富余分支不会低于下限；窄屏（小窗 200 宽
/// 时 cellW ≈ 25）上它只有 54，于是富余分支返回一个**比格子里的三行字还矮**
/// 的高度 —— 每个格子都会 BOTTOM OVERFLOWED。下限是「装不下三行字」这件事
/// 决定的，跟走哪个分支无关。
double calendarCellHeight({
  required double cellW,
  required double availHeight,
  required int weekRows,
  required double weekdayH,
  double aspectMin = _cellAspectMin,
}) {
  final naturalCellH = cellW / _cellAspect;
  final fillCellH = (availHeight - weekdayH) / weekRows;
  final shrunk = fillCellH >= naturalCellH
      ? math.min(fillCellH, cellW / aspectMin)
      : fillCellH;
  return math.max(shrunk, _minCellH);
}
