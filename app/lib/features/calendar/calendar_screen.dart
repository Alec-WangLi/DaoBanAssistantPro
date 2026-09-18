import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design_tokens.dart';
import '../../core/haptics.dart';
import '../../core/glass/glass.dart';
import '../../core/layout.dart';
import '../../core/l10n.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../data/app_repository.dart';
import '../../domain/lunar_info.dart';
import '../../domain/shift_rotation.dart';
import '../../state/app_settings.dart';
import '../alarm/alarm_service.dart';
import 'info_card_metrics.dart';
import 'schedule_editor_screen.dart';
import 'shift_override_picker.dart';
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
  static const _cellInset = AppTokens.gapHair; // 格子/玻璃块统一内缩

  /// 格子卡片与选中块的圆角：**必须同源**。
  ///
  /// 选中块就盖在同一格上（同 inset、同尺寸），圆角差一档，四个角就会露出底下
  /// 的卡片。v0.7.3 真机实测正是如此：块是 `radiusL`(22)、卡片是 `radiusM`(16)，
  /// 四个角各露出一条约 4dp 的月牙，看起来就是「滑块没把格子盖住」。
  ///
  /// 两处都从这一个来源取，`calendar_screen_test` 里另有一条用例钉着两者相等
  /// —— 光靠自觉，这两个数迟早还会各走各的。
  static BorderRadius get _cellRadius =>
      BorderRadius.circular(AppTokens.radiusM);

  late DateTime _month; // 显示月的 1 号
  late DateTime _selected; // 选中的日期（默认今天）

  bool _pressed = false; // 按下膨胀
  bool _dragActive = false; // 拖拽中（跟手，无过渡）
  double _visualCol = 0; // 选中块视觉列（连续小数，拖动时用）
  double _visualRow = 0; // 选中块视觉行（连续小数，拖动时用）
  double _grabCol = 0; // 手指相对选中块左缘的抓取偏移（列）
  double _grabRow = 0; // 手指相对选中块上缘的抓取偏移（行）

  /// 长按拖选：起点与当前终点（null = 不在范围选择态）。
  DateTime? _rangeAnchor;
  DateTime? _rangeFocus;

  /// 底栏信息卡高度的**上一次**计算结果。
  ///
  /// 高度只跟「月份 / 排班 / 宽度 / 语言 / 系统字号」有关，跟选中哪天无关 ——
  /// 这正是它不随点日期抖动的原因。而这几样在一次拖动里都不会变，所以量一次
  /// 缓存住即可：`_dayRows` 每帧都重建，量一次要排三十来个 `TextPainter`。
  /// 只留一条（同时只会显示一个月的卡片），键变了就重量。
  String? _cardHeightKey;
  double? _cardHeight;

  /// 本月里有没有**未完成**的待办。
  ///
  /// 信息卡日期行上的「N 项待办」徽章只在有待办的日子画，而卡片是定高的 ——
  /// 高度必须按**月**预留（有一天可能有就留），按天算的话点一天高度变一次，
  /// 上面的网格跟着抖。
  bool get _monthHasPendingTodos {
    final events = ref.watch(eventsProvider).valueOrNull;
    if (events == null) return false;
    // `e.date` 是 `dateOnly` 存的 UTC 纯日期，年月日与本地日期一致，直接取用。
    return events.any((e) =>
        !e.isCompleted &&
        e.date.year == _month.year &&
        e.date.month == _month.month);
  }

  /// 底栏信息卡该多高：取本月最满的一天（见 `info_card_metrics.dart`）。
  double _bottomCardHeight(BuildContext context, ShiftSchedule? schedule,
      double cardOuterWidth) {
    final hasTodoHint = _monthHasPendingTodos;
    final key = [
      _month.year,
      _month.month,
      cardOuterWidth.toStringAsFixed(1),
      L10n.isEn,
      // 系统字号：`TextScaler` 可能是非线性的，拿某一档的实际缩放当代表值。
      MediaQuery.textScalerOf(context).scale(14).toStringAsFixed(3),
      schedule?.teamCount,
      schedule?.ourTeamIndex,
      schedule?.isBlank,
      schedule?.teamNames.join('/'),
      // 色块上写的是「组名 + 班次简称」，简称改了高度也可能变（比如从 1 字变
      // 2 字、窄屏多折一行）。
      schedule?.classes.map((c) => c.shortLabel).join('/'),
      // 有待办的那天日期行要多留一点（徽章比日期字高），按月参与。
      hasTodoHint,
    ].join('|');
    if (key == _cardHeightKey && _cardHeight != null) return _cardHeight!;
    final h = measureBottomInfoCardHeight(
      context: context,
      cardOuterWidth: cardOuterWidth,
      schedule: schedule,
      month: _month,
      hasTodoHint: hasTodoHint,
    );
    _cardHeightKey = key;
    _cardHeight = h;
    return h;
  }

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

  /// 手指位置 → 那一格的日期（越界 / 空格 / 不是本月都返回 null）。
  DateTime? _dateFromPosition(Offset pos, double cellW, double cellH) {
    final col = ((pos.dx - _hPad) / cellW).floor();
    final row = ((pos.dy - _weekdayH) / cellH).floor();
    if (col < 0 || col > 6 || row < 0) return null;
    final index = row * 7 + col;
    if (index < _leading) return null;
    final day = index - _leading + 1;
    if (day < 1 || day > _daysInMonth) return null;
    return DateTime(_month.year, _month.month, day);
  }

  /// 手指位置 → 选中日期（2D 拖拽/点按）。
  void _selectFromPosition(Offset pos, double cellW, double cellH) {
    final date = _dateFromPosition(pos, cellW, cellH);
    if (date != null && date != _selected) {
      // 与长按拖选同一口径：**吸附到的格子真的变了**才震。原地按一下不震。
      Haptics.select();
      setState(() => _selected = date);
    }
  }

  /// [date] 是否落在长按拖选的范围里（闭区间，两端谁前谁后都算）。
  bool _inSelectedRange(DateTime date) {
    final a = _rangeAnchor, b = _rangeFocus;
    if (a == null || b == null) return false;
    final lo = daysBetween(a, b) >= 0 ? a : b;
    final hi = daysBetween(a, b) >= 0 ? b : a;
    return daysBetween(lo, date) >= 0 && daysBetween(date, hi) >= 0;
  }

  /// 长按被取消时的统一收尾：滑块那套与范围态一起熄掉。
  ///
  /// 走到这儿的都是真·取消（切前台、来电）。长按赢下竞技场之后框架只把
  /// `PointerUp` 送进 `onLongPressEnd`，取消那一支只发 `onLongPressCancel` ——
  /// 不接它，那片范围淡染会一直挂在屏幕上，直到下一次长按。
  void _clearGestureState() {
    if (!_pressed &&
        !_dragActive &&
        _rangeAnchor == null &&
        _rangeFocus == null) {
      return; // 没有状态可清：不为一次无关的取消白白重建整棵网格
    }
    setState(() {
      _pressed = false;
      _dragActive = false;
      _rangeAnchor = null;
      _rangeFocus = null;
    });
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
    // 上下留白归到节奏档：10 → spaceMd(12)、6 → spaceSm(8)。
    const pad =
        EdgeInsets.fromLTRB(12, AppTokens.spaceMd, 12, AppTokens.spaceSm);
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
                      style: AppTokens.titleStrong,
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
                  child: const AppIcon(
                    Icons.today_outlined,
                    size: AppTokens.iconMd,
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
          const SizedBox(width: AppTokens.gapIconText),
          Expanded(
            child: _glassPill(
              context,
              onTap: _showMonthPicker,
              child: Text(
                L10n.yearMonth(_month),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTokens.titleStrong,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.gapIconText),
          _circleIcon(
              context, Icons.chevron_right_outlined, L10n.nextMonth, _next),
          const SizedBox(width: AppTokens.gapIconText),
          // 切换排班：纯图标圆形钮（省宽，保证年月完整显示）
          _circleIcon(context, Icons.swap_vert_outlined, L10n.switchSchedule,
              _showScheduleSwitcher),
          const SizedBox(width: AppTokens.gapIconText),
          _glassPill(
            context,
            onTap: _today,
            accent: true,
            // accent 变体是实心主色底，内容用白（别再跟着 colorScheme.primary，
            // 那样就是主色字压在主色底上）。
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(
                  Icons.today_outlined,
                  size: AppTokens.iconMd,
                  color: Colors.white,
                ),
                // 320 宽下「今天」两个字会挤掉年月的显示宽度，窄屏只留图标。
                if (!AppLayout.of(context).isNarrow) ...[
                  const SizedBox(width: 4),
                  Text(
                    L10n.today,
                    // 压在实心主色胶囊上的白字，「前景色已定」，不归明度两档。
                    style: AppTokens.labelStrong.copyWith(
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
            child: AppIcon(icon,
                size: AppTokens.iconMd,
                color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
      ),
    );
  }

  Future<void> _switchSchedule(int id) async {
    final repo = ref.read(appRepositoryProvider);
    await repo.setCurrentSchedule(id);
    // 方案真的换过去了 —— 这是「动作落实」，不是「选中变了」，所以是 `commit`
    // 而不是 `select`。放在写库**之后**：写失败就不该报「落实了」。
    Haptics.commit();
    // 重排读的是库里**刚设成当前**的那套方案（`rescheduleAll` 自己读），
    // 所以这里不用先把领域模型取出来。
    if (mounted) await AlarmService.rescheduleAll(repo);
  }

  /// 弹「调整班次」选择层，把 [from]..[to] 这段日子改掉（或恢复轮转）。
  ///
  /// 改完必须重排闹钟：这天可能从工作班变成休班（不该响），或从休班变成夜班
  /// （要响）—— 不重排的话闹钟跟日历就对不上了。
  Future<void> adjustDays(DateTime from, DateTime to) async {
    final schedule = ref.read(activeScheduleProvider).valueOrNull?.toDomain();
    if (schedule == null || schedule.isBlank || schedule.classes.isEmpty) {
      // 空白表（跟随法定节假日）没有班次定义可挑，入口本来就不该出现；
      // 这里再兜一次，免得别处误调。
      return;
    }
    final days = <DateTime>[];
    final span = daysBetween(from, to);
    for (var i = 0; i <= span; i++) {
      days.add(dateOnly(DateTime(from.year, from.month, from.day + i)));
    }

    final hasOverride =
        days.any((d) => schedule.dayOverrides.containsKey(dayNumber(d)));
    final current =
        days.length == 1 ? schedule.shiftOn(days.single) : null;

    final choice = await showShiftOverridePicker(
      context,
      schedule: schedule,
      from: from,
      to: to,
      currentClass: hasOverride ? current : null,
      canRestore: hasOverride,
    );
    if (choice == null || !mounted) return;

    final repo = ref.read(appRepositoryProvider);
    if (choice.restore) {
      await repo.clearDayOverrides(days);
    } else {
      await repo.setDayOverrides(days, classId: choice.shift!.id!);
    }
    // 「应用改班 / 恢复轮转」落在写库之后 ——「改班」是词汇表里点名的 commit
    // 语义（`haptics.dart` 的 `commit()` 文档）。写失败就走不到这一步。
    Haptics.commit();
    await AlarmService.rescheduleAll(repo);
    if (!mounted) return;
    showGlassSnack(
      context,
      choice.restore
          ? L10n.restoredRotation(days.length)
          : L10n.adjustedDays(days.length, choice.shift!.name),
    );
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
                  // 底部弹层标题走 `dialogTitle`（规格 §3.2「弹窗与**底部弹层**
                  // 标题」），与 `glass_dialog` 里那些弹窗同角色 —— 原为
                  // 18/w700，本轮统一成 20/w600。
                  Text(L10n.switchSchedule, style: AppTokens.dialogTitle),
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
            // 与 `_selectFromPosition` 同一口径：**吸附到的格子真的变了**才震。
            // 快甩（100ms 内就超过 slop）这一路 `onTapDown` 从来没响过 ——
            // 竞技场里 Pan 先赢、Tap 直接被判负，所以「拖到新的一格」的触觉
            // 只有这儿发得出来；慢按起手那一下则由 `_selectFromPosition` 负责。
            // `changed` 要先取：下面 `setState` 会把 `_selected` 改成 `date`。
            final changed = date != null && date != _selected;
            setState(() {
              _pressed = false;
              _dragActive = false;
              if (date != null) _selected = date;
            });
            if (changed) Haptics.select();
          },
          // 长按拖选：按住不动约 500ms 长按赢，立刻滑动仍然是上面的 Pan 赢 ——
          // 两套手势在竞技场里天然分流，互不顶掉（`_pressed` / `_dragActive` 是
          // 两套状态，长按起手时要把滑块那套先熄掉，免得玻璃块跟长按同时亮）。
          onLongPressStart: (d) {
            // 空白表方案（跟随法定节假日）没有班次定义可挑，长按不该进入范围态
            // （spec §7.3）—— 否则用户拖出一片淡染、松手却什么也不发生。判据
            // 与信息卡入口、`adjustDays` 内部那一处同源。
            final canPick = schedule != null && schedule.classes.isNotEmpty;
            final date =
                canPick ? _dateFromPosition(d.localPosition, cellW, cellH) : null;
            setState(() {
              // 长按赢下竞技场之后 `onTapUp` / `onPanEnd` 都不会再来，滑块那套
              // 状态必须在这儿熄掉 —— 不然玻璃块停在按下的放大态，或者跟范围
              // 淡染一起亮。落在本月之外的空白格时 `date` 是 null，范围态因此
              // 保持为空（后续 moveUpdate / end 都空转），但这一下同样要把上面
              // 那两个标志清掉。
              _pressed = false;
              _dragActive = false;
              _rangeAnchor = date;
              _rangeFocus = date;
            });
            // 进入多选态那一下**更明显**，好跟后面每进一格的轻震分开（spec §4.3）。
            // 放在 `setState` 之外：它的回调必须同步且无副作用，触觉是副作用。
            Haptics.modeEnter();
          },
          onLongPressMoveUpdate: (d) {
            if (_rangeAnchor == null) return;
            final date = _dateFromPosition(d.localPosition, cellW, cellH);
            if (date == null || date == _rangeFocus) return;
            // 吸附到的格子真的变了才震 —— 原地抖一下不响；范围往回缩时同样会响，
            // 两个方向一致（spec §4.3）。
            Haptics.select();
            setState(() => _rangeFocus = date);
          },
          onLongPressEnd: (_) {
            final from = _rangeAnchor;
            final to = _rangeFocus;
            setState(() {
              _rangeAnchor = null;
              _rangeFocus = null;
            });
            if (from == null || to == null) return;
            // 起点终点谁在前都行，调换成正序 —— `adjustDays` 不认 `from > to`，
            // 传反了它会静默拼出空列表、弹一条误导的提示。
            final a = daysBetween(from, to) >= 0 ? from : to;
            final b = daysBetween(from, to) >= 0 ? to : from;
            adjustDays(a, b);
          },
          // 手指被系统取消（切前台、来电 —— 网格外面就是滚动容器）：
          // `onLongPressEnd` 只在 `PointerUp` 时发，取消只有这一条回调。
          // 注意长按赢下竞技场之后它**照样**会发：`GestureRecognizerState`
          // 只有 ready/possible/defunct 三档，accept 不改 state，所以
          // `_checkLongPressCancel` 的 `state == possible` 仍然成立。
          onLongPressCancel: _clearGestureState,
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
                  style: AppTokens.labelSecondary
                      .copyWith(color: AppTokens.inkMuted(context)),
                ),
              ),
            )),
      ),
    );
  }

  List<Widget> _dayRows(
      BuildContext context, double cellW, double cellH, ShiftSchedule? schedule) {
    // 比「同一天」用 `isSameDay` 而不是 `==`：`dateOnly` 是 UTC 日期、这里的
    // `date` 是本地日期，`DateTime.==` 连 `isUtc` 一起比，`==` 恒为假
    // （「今天」的日期因此一直没加粗过）。
    final today = DateTime.now();
    // 班次胶囊画成实心的那一格 = 滑块当前吸附到的格。拖动中跟 `_visual` 走而不是
    // 跟 `_selected`：`_selected` 要松手才更新，跟它的话，手指滑过的中间格会停在
    // 「淡染胶囊压在淡主色底上」的糊态；跟吸附格则滑块盖住的格子永远是实心的。
    // 吸附用的是松手时同一个函数，所以「实心 → 松手落地」不会跳格。
    final blockDate = _dragActive ? _nearestDateFromVisual() : _selected;
    final cells = <Widget>[];
    for (var i = 0; i < _leading; i++) {
      cells.add(SizedBox(width: cellW, height: cellH));
    }
    for (var d = 1; d <= _daysInMonth; d++) {
      final date = DateTime(_month.year, _month.month, d);
      cells.add(_dayCell(
          context,
          date,
          schedule?.shiftOn(date),
          lunarOf(date),
          cellW,
          cellH,
          isSameDay(date, today),
          blockDate != null && isSameDay(date, blockDate),
          schedule?.dayOverrides.containsKey(dayNumber(date)) ?? false,
          _rangeAnchor != null &&
              _rangeFocus != null &&
              _inSelectedRange(date)));
    }
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      final chunk = cells.sublist(i, math.min(i + 7, cells.length));
      rows.add(Row(children: chunk));
    }
    return rows;
  }

  /// 磨砂卡片日期格。
  ///
  /// 排布按**这天有没有班次**分两种，一个方案要么整月有班次、要么整月没有，
  /// 所以两种排布不会混在同一个月里：
  ///
  /// 三行**全部居中**：日期 / 班次 / 农历。日历里最该一眼看到的是「哪天是什么
  /// 班」，所以班次做成带底色的胶囊占中位，日期与农历都不抢戏。
  ///
  /// 日期曾经缩到左上角当定位标记 —— 收回居中，因为格子是**圆角**矩形，左上角
  /// 那一小块是被切掉的：日期贴着内容框的左缘，就会蹭到圆角的弧度外，看起来像
  /// 溢出了格子（班组多、卡片更高、格子更矮时最明显）。
  ///
  /// 「无班次」（「跟随法定节假日（无班次）」那套方案，以及还没建排班）只是少画
  /// 中间那一行，三行居中的骨架不变。
  ///
  /// 格子里的字按**格子高度**等比缩放（[AppTokens.scaled]）：格子高是按剩余
  /// 空间算出来的，长高时字不跟着长，格子里就空出一大块、字显得小。
  ///
  /// [solid] 表示这格的班次胶囊要画成实心（滑块当前吸附的那一格）。
  ///
  /// [adjusted] 表示这天被「按天改班」覆盖过，胶囊右上角点一个小圆点。
  /// [inRange] 表示这天落在长按拖选的范围里，整格铺一层主色淡染。
  Widget _dayCell(BuildContext context, DateTime date, ShiftClass? shift,
      LunarInfo lunar, double cellW, double cellH, bool isToday, bool solid,
      bool adjusted, bool inRange) {
    final lunarColor = lunar.isLegalHoliday
        ? AppTokens.holiday
        : AppTokens.inkMuted(context);
    final surface = Theme.of(context).colorScheme.surface;
    final primary = Theme.of(context).colorScheme.primary;

    // 缩放系数按**去掉格子内缩后的可用高**算：内容排在被 `_cellInset` 收窄的
    // 盒子里，用 cellH 直接算会让内容恒比盒子高一点点，外层的 FittedBox 每次
    // 都缩回去一档，等于缩放没生效。
    final s =
        ((cellH - _cellInset * 2) / _cellDesignH).clamp(1.0, _cellMaxScale);
    final contentW = cellW - _cellInset * 2;
    // 太窄就画不出胶囊（小窗里格宽只有 25），退回彩色文字。
    final chip = shift != null && contentW >= _chipMinContentW;

    final dateLine = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '${date.day}',
        maxLines: 1,
        // `cellDateSm` 自带 height 1.15：M3 默认行高 1.5，三行文字的行盒加起来
        // 比格子可用高度多出几个像素，真机上每个格子都会 BOTTOM OVERFLOWED。
        // 今天加粗走同一角色的 `copyWith`，不另立令牌。
        style: AppTokens.scaled(AppTokens.cellDateSm, s).copyWith(
          fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );

    final lunarStyle = AppTokens.scaled(AppTokens.tinyLabel, s);
    final lunarLine = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Text.rich(
        TextSpan(
          children: [
            if (lunar.isMakeupWorkday)
              TextSpan(
                text: '班 ',
                // 调休日的「班」标记：与农历同一角色，转主色 + 加粗区分。
                // 单行写法是守门测试的要求：`fontWeight` 字面量只有与
                // `copyWith` 同行才豁免。
                style: lunarStyle
                    .copyWith(color: primary, fontWeight: FontWeight.w700),
              ),
            TextSpan(text: lunar.shortLabel),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: lunarStyle.copyWith(color: lunarColor),
      ),
    );

    final children = <Widget>[dateLine];
    if (shift != null) {
      children.add(const SizedBox(height: AppTokens.gapHair));
      children.add(chip
          // 两侧留硬边距：胶囊再宽也碰不到格子边（更碰不到选中滑块）。
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: _chipSideGap),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _shiftChip(context, shift, s, solid,
                      ValueKey('day-chip-${date.day}')),
                  if (adjusted)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        key: ValueKey('day-adjusted-${date.day}'),
                        // spec §7.4：**固定在 3–4dp、不跟格子高度缩放** ——
                        // 格子里的字是按格子高等比缩放的，小窗里缩到 1–2px 就
                        // 等于没有。这里借间距刻度上的 4dp 一档（`spaceXs`）：
                        // 光学刻度（`gapHair` / `padChipV` …）最高的 3dp 也在
                        // 区间内，但它们表达的是"控件内部两个元素贴合的微距"，
                        // 用在标记的**尺寸**上语义不对。
                        width: AppTokens.spaceXs,
                        height: AppTokens.spaceXs,
                        decoration: BoxDecoration(
                          color: Color(shift.color),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            )
          : Text(
              shift.shortLabel,
              // 窄到画不出胶囊时的退路：班次色是给色块用的强色，当文字色太浅
              // （橙 2.06:1、灰 2.60:1），要按格子底色算一版可读的。
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTokens.scaled(AppTokens.microStrong, s).copyWith(
                color: AppTokens.inkFor(Color(shift.color), surface),
              ),
            ));
    }
    children
      ..add(const SizedBox(height: AppTokens.gapHair))
      ..add(lunarLine);

    return SizedBox(
      width: cellW,
      height: cellH,
      child: Container(
        key: ValueKey('day-card-${date.day}'),
        margin: const EdgeInsets.all(_cellInset),
        decoration: _cardDecoration(context),
        child: Stack(
          children: [
            // 长按拖选时，圈住的日子铺一层主色淡染（画在内容下面，不挡字）。
            // 逐格画而不是画一个外接矩形：日期区间在月历里是折行的（周五到
            // 下周二），外接矩形会把区间之外整整一行都染上。
            if (inRange)
              Positioned.fill(
                child: DecoratedBox(
                  // 有 key 是为了让「圈住了哪几格」可断言 —— 淡染本身没有文字，
                  // 只能靠 key 找（`_rangeSpan` 那几条用例）。
                  key: ValueKey('day-range-${date.day}'),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.18),
                    borderRadius: _cellRadius,
                  ),
                ),
              ),
            Positioned.fill(
              // 整格内容一起可缩，而不是让某一行自己想办法。
              //
              // 字号已按格子高度缩放，这一层只是**兜底**：用户把系统字号调到
              // 1.2 倍以上时三行字仍可能高过格子，Column 会报 BOTTOM OVERFLOWED、
              // release 下被裁字。外层的滚动容器救不了这里：它管的是「整个网格
              // 高过视口」，管不到「字高过格子」。
              //
              // 宽度给死值，所以 scaleDown 只在**高度**不够时才动手。
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: contentW,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: children,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 日历格子里的班次胶囊。
  ///
  /// 配方与信息卡的「其他班组」色块、「法定节假日」徽章**同一套**：班次色淡染底
  /// + 同色描边 + [AppTokens.inkFor] 文字。同一个「信息胶囊」在应用里只该有一套
  /// 长相，不因为进了日历就换配方。
  ///
  /// [solid] 为真时底色换成班次色实心、文字走 [AppTokens.onSolid]，用于滑块当前
  /// 吸附的那一格 —— 那一格是全屏唯一需要「一眼锁定」的。**只换颜色，不换几何**
  /// （描边宽度、内边距、字号一律不动），所以胶囊尺寸与内容高度不随选中态变化，
  /// 不会连带触发布局跳动。
  ///
  /// 底色走 [AnimatedContainer]，选中/取消时渐变过去而不是硬切；文字色是跳变的
  /// —— 两个候选（`inkFor` 与 `onSolid`）各自在对应底色上可读，中间态可接受，
  /// 而 Color.lerp 两个可读色反而会穿过不可读区。
  Widget _shiftChip(BuildContext context, ShiftClass shift, double s,
      bool solid, Key key) {
    final color = Color(shift.color);
    final fill = solid ? 1.0 : 0.14;
    final ink = solid
        ? AppTokens.onSolid(color)
        : AppTokens.inkFor(
            color,
            Color.alphaBlend(
                color.withValues(alpha: fill),
                Theme.of(context).colorScheme.surface));
    final label = shift.shortLabel;

    return AnimatedContainer(
      key: key,
      duration: AppTokens.durMed,
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(
          horizontal: _chipPadH * s, vertical: AppTokens.padChipV * s),
      decoration: BoxDecoration(
        color: color.withValues(alpha: fill),
        borderRadius: BorderRadius.circular(AppTokens.radiusS),
        border: Border.all(
            color: solid ? color : color.withValues(alpha: 0.45)),
      ),
      // 文字套一层 `scaleDown`：简称是用户可改的（可能两个字、三个字），系统
      // 字号也可能被放大 —— 光按「字数 × 基准字号」算可用宽度是**零余量**的，
      // 差一点点就退化成省略号，再多一点整串字都放不下、只剩一个空胶囊
      // （v0.7.1 真机实测：两字简称显示成「上…」，系统字号放大后直接空白）。
      // 交给 FittedBox 按实际排版缩，放得下就一个像素都不缩。
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: AppTokens.scaled(AppTokens.cellShift, s).copyWith(color: ink),
        ),
      ),
    );
  }

  /// 信息卡日期行上的「N 项待办」提示。
  ///
  /// 形状与同一行的「今天」徽章对齐（同内边距、同圆角），颜色走「信息胶囊」那套
  /// 淡染配方（14% 底 + 45% 描边 + `inkFor` 文字）—— 同一行两个徽章等高等形，
  /// 只有轻重不同。高度与「今天」徽章一样是 12px 文字那一档，所以日期行的高度
  /// 不因它而变。
  Widget _todoHintBadge(BuildContext context, int count) {
    final accent = Theme.of(context).colorScheme.primary;
    final ink = AppTokens.inkFor(
        accent,
        Color.alphaBlend(accent.withValues(alpha: 0.14),
            Theme.of(context).colorScheme.surface));
    return Container(
      key: const Key('info-card-todo-hint'),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceSm, vertical: AppTokens.padChipV),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(Icons.event_note_outlined,
              size: AppTokens.iconSm, color: ink),
          const SizedBox(width: AppTokens.gapIconText),
          Text(L10n.todoCount(count),
              style: AppTokens.microStrong.copyWith(color: ink)),
        ],
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
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: AppTokens.padChipV),
      decoration: BoxDecoration(
        color: AppTokens.holiday.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTokens.radiusS),
        border: Border.all(color: AppTokens.holiday.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(Icons.celebration_outlined, size: AppTokens.iconSm, color: ink),
          const SizedBox(width: AppTokens.gapIconText),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: L10n.legalHoliday,
                    style: AppTokens.microLabel.copyWith(color: ink),
                  ),
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: name,
                    style: AppTokens.labelStrong.copyWith(color: ink),
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
      borderRadius: _cellRadius,
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

  /// 可拖拽的玻璃选择块（与格子同 inset、同圆角，精确覆盖）。
  Widget _glassBlock(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      key: const Key('calendar-selection-block'),
      margin: const EdgeInsets.all(_cellInset),
      decoration: BoxDecoration(
        borderRadius: _cellRadius,
        color: accent.withValues(alpha: 0.13),
        border: Border.all(color: accent, width: 2),
        // **没有 boxShadow**，这是有意的，别加回来。
        //
        // 这一层画在网格**之上**（Stack 的后一个 child），所以它必须是半透明的
        // —— 不透明就把选中那格的日期、班次胶囊、农历全糊掉了（试过，格子直接
        // 变空）。而正因为它是半透明的，一旦有 `boxShadow`（主色 25%），阴影就会
        // 从块**内部**透出来再叠一层：格子内部实际吃到约 33% 的主色，而不是
        // 设计要的 13%。
        //
        // 后果是选中那格的**实心班次胶囊被洗掉色相**：橙 `#FF9F0A` 洗成棕
        // `#C28758`，蓝 `#4C8DFF` 会和主色块糊成一片。而「选中那格的班次最抢眼」
        // 正是实心胶囊的全部意义。
        //
        // 想在块外留光晕也不行：阴影只能画在内容之上，才会被看得见；画在内容
        // 之下就会被格子自身近乎不透明的卡片底（白 92%）盖住。所以这里二选一，
        // 选保住胶囊的色相 —— 「选中」这个信号由 2px 主色描边 + 13% 淡染承担，
        // 它们本来就扛得住。
      ),
    );
  }

  /// 底部玻璃信息卡（完整分行）。
  Widget _infoCard(BuildContext context, ShiftSchedule? schedule,
      {bool inSidePane = false, bool compact = false}) {
    final lunar = lunarOf(_selected);
    final shift = schedule?.shiftOn(_selected);
    final isToday = _selected == dateOnly(DateTime.now());
    final muted = AppTokens.inkMuted(context);
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
        // 与完整信息卡那行班次同源：套 `GlassPressable` 承载点击（它自己没
        // `onTap`），内层 `InkWell` 负责手势 —— 见上面完整卡那段的说明。
        child: GlassPressable(
          child: InkWell(
            onTap: (schedule == null || schedule.classes.isEmpty)
                ? null
                : () => adjustDays(_selected, _selected),
            child: GlassTile(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMd, vertical: AppTokens.spaceMd),
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
                  const SizedBox(width: AppTokens.gapIconTextLg),
                  Expanded(
                    child: Text(
                      [
                        L10n.monthDayWeekday(_selected),
                        if (shift != null) shift.name,
                        if (timeText != null) timeText,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTokens.labelSecondary,
                    ),
                  ),
                  if (shift != null && shift.alarmEnabled)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: AppIcon(Icons.alarm_outlined,
                          size: AppTokens.iconSm, color: muted),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 选中那天还没完成的待办条数。只说数量，不列内容（用户要的只是「今天有
    // 待办」这一眼）。`e.date` 是 `dateOnly` 存的 UTC 日期，比「同一天」要走
    // `isSameDay`，不能直接用 `==`。
    final pendingTodos = ref
            .watch(eventsProvider)
            .valueOrNull
            ?.where((e) => !e.isCompleted && isSameDay(e.date, _selected))
            .length ??
        0;

    final content = Column(
      key: const Key('info-card-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              L10n.monthDayWeekday(_selected),
              // 设计规格把字重收成「标题 w700 / 强调 w600 / 正文 w500」，
              // w800 只留给响铃大时钟与角标「今天」，所以日期行走 w700 的
              // sectionTitle。
              style: AppTokens.sectionTitle,
            ),
            if (isToday) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceSm, vertical: AppTokens.padChipV),
                decoration: BoxDecoration(
                  // 实心主色 + 白字。原来是「主色 14% 淡底 + 主色字」，
                  // 实测对比度 3.84:1（深色下 2.93:1），低于 AA 的 4.5:1。
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(AppTokens.radiusL),
                ),
                child: Text(
                  L10n.today,
                  style: AppTokens.microStrong.copyWith(color: Colors.white),
                ),
              ),
            ],
            // 待办提示塞在**这一行**里，不新占一行：这一行本来就有个和它一样高的
            // 「今天」徽章，所以卡片高度（进而格子高度）一像素都不动 —— 信息卡是
            // 定高的，多一行会让六个格子集体矮一截（见 `info_card_metrics.dart`）。
            //
            // 窄屏不显示：三个元素并排在这点宽度里放不下，而挤掉日期的字比少一条
            // 提示更糟（紧凑卡片分支同样把农历、今天徽章都收起来了）。
            //
            // 侧栏（横屏的左右分栏）同样不显示 —— 那一栏比竖屏底栏还窄，
            // 实测这一行会横向溢出 24px。
            if (pendingTodos > 0 &&
                !inSidePane &&
                !AppLayout.of(context).isNarrow) ...[
              const SizedBox(width: AppTokens.spaceSm),
              _todoHintBadge(context, pendingTodos),
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
          style: AppTokens.rowSecondary.copyWith(
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
        if (shift != null && schedule != null)
          // `GlassPressable` **没有 `onTap`** —— 它只是个按压缩放的视觉包装
          // （`Listener` + `QScale`），点击一律由子 widget 承载。所以这里套
          // `InkWell`（`GlassPressable` 内部已经给了 `Material`，水波纹拿得到），
          // 与 `glass_pickers.dart` 里 `GlassPressable(child: ListTile(onTap: …))`
          // 是同一套做法。
          //
          // 空白表方案没有班次定义可挑，入口不给（spec §7.3）—— 传 null 禁用它。
          // 已知小瑕疵：`GlassPressable` 的按压缩放挡不住，空白表下按这行仍会
          // 缩一下。不值得为它再加一层条件包装。
          GlassPressable(
            key: const Key('info-card-shift-entry'),
            child: InkWell(
              onTap: schedule.classes.isEmpty
                  ? null
                  : () => adjustDays(_selected, _selected),
              child: Row(
                children: [
                  Container(
                    // 保持原来的 12 不动 —— 这个色点的尺寸不是本任务要改的东西，
                    // 换成 `AppTokens.iconSm`（16）会白白把点撑大一圈。
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
                            style: AppTokens.titleStrong.copyWith(
                              color: AppTokens.inkFor(Color(shift.color),
                                  Theme.of(context).colorScheme.surface),
                            ),
                          ),
                          if (shift.startMinute != null &&
                              shift.endMinute != null)
                            TextSpan(
                              text: '  ${_timeRange(shift)}',
                              style: AppTokens.rowPrimary,
                            ),
                          TextSpan(
                            text: '   ${_alarmText(shift)}',
                            style:
                                AppTokens.rowSecondary.copyWith(color: muted),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 这天被单独调整过（spec §7.4）：给一句文字说明，让用户第一眼
                  // 看见日历上那个小圆点时能对上号。
                  if (schedule.dayOverrides
                      .containsKey(dayNumber(_selected)))
                    Padding(
                      padding:
                          const EdgeInsets.only(left: AppTokens.spaceSm),
                      child: Text(
                        L10n.adjusted,
                        key: const Key('info-card-adjusted'),
                        style: AppTokens.microStrong.copyWith(
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                ],
              ),
            ),
          )
        else if (schedule != null && schedule.isBlank)
          Text(
            lunar.isLegalHoliday ? L10n.rest : L10n.workday,
            style: AppTokens.labelStrong.copyWith(
              color: lunar.isLegalHoliday ? AppTokens.holiday : muted,
            ),
          )
        else
          Text(L10n.noSchedule,
              style: AppTokens.rowSecondary.copyWith(color: muted)),
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
                // 4 与色块文字的实际起点（padChipV 3 + 描边 1）对齐。
                padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                child: Text(L10n.otherCrews,
                    style: AppTokens.microText.copyWith(color: muted)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: AppTokens.spaceSm,
                  runSpacing: AppTokens.gapIconText,
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
    // `Positioned(top/bottom: spaceLg)`，量的却是外面那个定高盒子 —— 两边
    // 各按各的高度走，色条就比卡片长出几十 dp、垂在空白里（v0.6.6 用户
    // 实测：卡片 126 高，色条 212 高）。给面板一层定高，两者才对得上。
    //
    // 右栏那份反过来要贴内容高度：那边没有「撑满」的必要，也就没有空档，
    // 所以不套这层，色条跟着面板走本来就是对的。
    final panel = GlassTile(
      key: const Key('info-card-panel'),
      padding: const EdgeInsets.fromLTRB(AppTokens.spaceXl, AppTokens.spaceLg,
          AppTokens.spaceLg, AppTokens.spaceLg),
      child: inSidePane
          ? content
          // 兜底：字号被系统放大到装不下时，卡片内部滚动，而不是溢出成
          // 黄黑条纹。正常字号下内容矮于卡片，这一层不产生任何滚动。
          : SingleChildScrollView(child: content),
    );

    final padding = inSidePane
        ? const EdgeInsets.fromLTRB(0, 8, 16, 16)
        // 底栏时要给悬浮胶囊让出高度（竖屏 96，短屏 76）；右栏时胶囊在
        // 屏幕底部、与这一栏无关，只需要常规留白。竖屏的 96 = 胶囊高 64
        // + 32 余量：84 时卡片底边几乎贴在胶囊上（v0.6.7 用户实测），
        // 又放开了 12。
        : const EdgeInsets.fromLTRB(16, 8, 16, 96);

    // 卡片外框宽度要量出来才能算高度（内容区宽度决定农历与色块折几行），
    // 而宽度只有这里才知道 —— 所以在内边距**里面**再套一层 LayoutBuilder。
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            SizedBox(
              key: const Key('info-card-box'),
              height: inSidePane
                  ? null
                  : _bottomCardHeight(context, schedule, constraints.maxWidth),
              child: panel,
            ),
            Positioned(
              left: 0,
              // 上下与面板内边距（spaceLg）一致，色条才是「卡片内高」而不是靠边。
              top: AppTokens.spaceLg,
              bottom: AppTokens.spaceLg,
              width: 6,
              child: DecoratedBox(
                key: const Key('info-card-accent-bar'),
                decoration: BoxDecoration(
                  color: accent,
                  // 6dp 宽的细长条就是胶囊：圆角取高度的一半。
                  borderRadius: AppTokens.pillOf(6),
                ),
              ),
            ),
          ],
        ),
      ),
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
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: AppTokens.padChipV),
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
            const SizedBox(width: AppTokens.gapIconText),
            Text('$name ${t.shortLabel}',
                style: AppTokens.microLabel.copyWith(
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

/// 信息卡（完整版）在**底栏**时的高度不再是写死的常数，改成按当前月最满的
/// 一天算出来 —— 实现在 `info_card_metrics.dart`，那里写了为什么。
///
/// 这里只留一条约束给下游：**高度必须与「选中哪天」无关**。竖屏下这一页是
/// `Column[顶栏, Expanded(网格), 信息卡]`，格子高度按**剩余空间**算
/// （`calendarCellHeight(availHeight:)`），卡片只要随当天内容长高一像素，
/// 六个格子就集体矮一像素、选下一天再弹回来 —— 点一天晃一次。
///
/// 也不能反过来把网格与卡片解耦（留白、或让网格自己滚动）：v0.6.1 刚把
/// 「网格与信息卡之间的一条空带」消掉，那条空带是明确不接受的。所以卡片
/// 始终撑满自己的盒子，多出来的空间留在卡片内部 —— 它是一块面板，不是一条
/// 会伸缩的条。
///
/// 高度算得准不准由 `calendar_screen_test.dart` 的「点开某天」用例盯着：它把
/// 整月每一天都点一遍，断言高度不变、内容装得下、且贴得够紧。

// 格子高宽比：0.78 = 自然比例，0.62 = 「不许再瘦」的下限比例（越小格子越高）。
const double _cellAspect = 0.78;
const double _cellAspectMin = 0.62;

/// 格子内容在**设计尺寸**下的自然高度：日期 `cellDateSm` 13×1.15 + `gapHair` +
/// 班次胶囊（`cellShift` 13×1.15 + 上下 `padChipV` 各 3 + 描边 1×2）+ `gapHair`
/// + 农历 `tinyLabel` 11×1.15 ≈ 54.6。
///
/// 格子里的字按 `(cellH − 内缩) / 这个值` 等比缩放（见 `_dayCell`），所以它就是
/// 「缩放系数 1.0」的那把尺子。
const double _cellDesignH = 55;

/// 格子字号的缩放上限。再大就喧宾夺主：格子被字填满、格子之间的呼吸感没了。
/// 1.25 是 v0.7.2 从 1.35 调下来的（配合 `cellShift` 15→13），单字胶囊的字号
/// 上限从 20.25 降到 16.25。
const double _cellMaxScale = 1.25;

/// 班次胶囊的左右内边距。用最小的一档栅格（4）：这里装的是 1–2 个字的简称，
/// 信息卡色块那 8 会让单字胶囊的宽度接近文字的两倍，手机上（格内容宽约 52）
/// 就装不下。v0.7.3 从 6 收到 4 —— 配合字号 13→12，让两个字也留得出余量。
const double _chipPadH = AppTokens.spaceXs;

/// 胶囊与格子左右边缘的**硬边距**。
///
/// 简称是用户可改的（两个字、甚至三个字），胶囊宽度会随字号缩放长到「内容宽」
/// 为止 —— 那样它就**贴住格子边**，与选中滑块一起看很挤（用户实测反馈）。
/// 这里两侧各留一条硬边距，放不下就由胶囊内的 `FittedBox` 缩文字，而不是撑满。
const double _chipSideGap = 4;

/// 画胶囊所需的最小内容宽度。单字胶囊在设计尺寸下自然宽
/// `_chipPadH`×2 + 描边 1×2 + 13 = 27，留一点余量取 34。
/// 小窗（200 宽）格子内容宽只有 21，落到这条线以下就退回纯色文字。
const double _chipMinContentW = 34;

/// 格子高的下限 = **格子里的三行字实测要多高**。
///
/// 不画胶囊的那一支（无班次方案、小窗）是日期 `cellDateSm` 13 + `gapHair` 2 +
/// 班次简称 `microStrong` 12 + `gapHair` 2 + 农历 `tinyLabel` 11，三者都自带
/// `height: 1.15` 压过行盒：≈ 45.4，再加格子自身 `_cellInset` 上下各 2 一共 4
/// —— 约 49.4，稳稳落在 58 之内。
///
/// 画胶囊那一支高一些（内容 ≈ 54.6、加内缩约 58.6），**正好贴着这道下限**：
/// 多出来的零点几像素由 `_dayCell` 那层 `FittedBox` 按需缩掉，肉眼看不出来，
/// 所以这里不为它抬低下限。
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
