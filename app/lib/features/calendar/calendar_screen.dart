import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design_tokens.dart';
import '../../core/haptics.dart';
import '../../core/glass/glass.dart';
import '../../core/glass/liquid_lens.dart';
import '../../core/layout.dart';
import '../../core/l10n.dart';
import '../../core/theme/animated_background.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_pill.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../data/app_repository.dart';
import '../../domain/lunar_info.dart';
import '../../domain/schedule_chain.dart';
import '../../domain/shift_rotation.dart';
import '../../state/app_settings.dart';
import '../alarm/alarm_service.dart';
import '../widget/widget_service.dart';
import 'info_card_metrics.dart';
import 'calendar_lens.dart';
import 'schedule_management_screen.dart';
import 'schedule_span_label.dart';
import 'shift_override_picker.dart';

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

  /// 这一页光晕背景的强度（`FlowingBackground.intensity`）。
  ///
  /// 响铃界面用满 1.0 —— 那是它的主角、只出现几秒。日历页是天天停留的一页，而且
  /// **大半被 92% 不透明的格子盖住**（浅色下格底是 `Colors.white` 0.92），光晕主要
  /// 从三处透出来：格子之间的缝、网格四周的留白、以及**信息卡那块真正的磨砂**
  /// （它是全页最大的一片 `BackdropFilter`）。深色下格底只有 6% 白，光晕透得更足，
  /// 所以同一档强度在深色里本来就更明显 —— 这也是它先按浅色调、再回来看深色的原因。
  static const double _bgIntensity = 0.65;

  late DateTime _month; // 显示月的 1 号
  late DateTime _selected; // 选中的日期（默认今天）

  bool _pressed = false; // 按下膨胀
  bool _dragActive = false; // 拖拽中（跟手，无过渡）
  double _visualCol = 0; // 选中块视觉列（连续小数，拖动时用）
  double _visualRow = 0; // 选中块视觉行（连续小数，拖动时用）
  double _grabCol = 0; // 手指相对选中块左缘的抓取偏移（列）
  double _grabRow = 0; // 手指相对选中块上缘的抓取偏移（行）

  /// 选中块的拖动速度（px/s，逻辑像素）—— 帧间差分 ÷ 真实帧间隔（`lensVelocityStep`，
  /// 一处实现、带低通）。**只有液态档那枚块读它**：标准档那枚是等比放大，不吃速度。
  double _vx = 0;
  double _vy = 0;

  /// 上一帧的帧戳与「那一帧块在哪一格」。`null` = 这一段拖动还没量过速度。
  Duration? _lastFrameStamp;
  double _lastVelCol = 0;
  double _lastVelRow = 0;

  /// 长按拖选：起点与当前终点（null = 不在范围选择态）。
  DateTime? _rangeAnchor;
  DateTime? _rangeFocus;

  /// 底栏信息卡高度的**上一次**计算结果。
  ///
  /// 高度只跟「月份 / 排班 / 宽度 / 语言 / 系统字号」有关，跟选中哪天无关 ——
  /// 这正是它不随点日期抖动的原因。而这几样在一次拖动里都不会变，所以量一次
  /// 缓存住即可：`_dayRows` 每帧都重建，量一次要排三十来个 `TextPainter`。
  /// 只留一条（同时只会显示一个月的卡片），键变了就重量。
  String? _cardMetricsKey;
  InfoCardMetrics? _cardMetrics;

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

  /// 本月里有没有被**按天调整过**的日子。
  ///
  /// 与 `_monthHasPendingTodos` 同一个道理：班次行尾巴上的「已调班」胶囊只在被
  /// 改过的那天画，而信息卡是定高的 —— 高度必须按**月**预留（这个月有被调过就
  /// 留），按天算的话点一天高度变一次，上面的网格跟着抖。
  ///
  /// 判定挪进 `ScheduleChain.monthHasOverrideHint`：跨时段的一个月里被改过的那天
  /// 可能归**另一套**方案，得逐天问「那天归哪套」—— 那正是链才知道的事。
  bool _monthHasOverrideHint(ScheduleChain? chain) =>
      chain?.monthHasOverrideHint(_month) ?? false;

  /// 底栏信息卡该多高、以及本月每一天各自的内容高度（见 `info_card_metrics.dart`）。
  InfoCardMetrics _cardMetricsFor(
      BuildContext context, ScheduleChain? chain, double cardOuterWidth) {
    final hasTodoHint = _monthHasPendingTodos;
    final hasOverrideHint = _monthHasOverrideHint(chain);
    final key = [
      _month.year,
      _month.month,
      cardOuterWidth.toStringAsFixed(1),
      L10n.isEn,
      // 系统字号：`TextScaler` 可能是非线性的，拿某一档的实际缩放当代表值。
      MediaQuery.textScalerOf(context).scale(14).toStringAsFixed(3),
      // **整条链**的指纹：哪几套方案、各自的时段与内容（组名、班次简称、是否
      // 空白表）。少了它，跨时段时会拿到上一条链算出来的高度 —— 而卡片装不下时
      // **只在卡内静默滚动**（末行被裁掉，没有任何报错）。
      chain?.cacheKey ?? '-',
      // 有待办的那天日期行要多留一点（徽章比日期字高），按月参与。
      hasTodoHint,
      // 这个月有被按天调过的日子时，班次行要给「已调班」胶囊留高度，也按月。
      hasOverrideHint,
    ].join('|');
    if (key == _cardMetricsKey && _cardMetrics != null) return _cardMetrics!;
    final m = measureBottomInfoCardHeight(
      context: context,
      cardOuterWidth: cardOuterWidth,
      chain: chain,
      month: _month,
      hasTodoHint: hasTodoHint,
      hasOverrideHint: hasOverrideHint,
    );
    _cardMetricsKey = key;
    _cardMetrics = m;
    return m;
  }

  /// 信息卡最后那行「本月 早12 · 午8 · 夜8 · 休6」：**整个月**各上几天什么班。
  ///
  /// 数整月而不是数到今天为止 —— 于是同一月里每天这一行完全一样、量出来的高度也
  /// 一样，判定它画不画的时候不必按天重量。班次用 `shortLabel`（日历格子里那个
  /// 一到两个字的简称：早 / 午 / 夜 / 休，英文是 M / A / N / O），一行放得下；
  /// 班次多的排班会折到第二行，折行的高度也照量（见 `measureInfoCardLine`）。
  ///
  /// **按简称累加、不按 `classes` 下标计数**：跨时段的一个月里两套方案的班次定义
  /// 不同，按下标数会把 A 的第 0 个班次和 B 的第 0 个班次算成同一个 —— 数字会错得
  /// 看不出来（spec §7.1）。跨方案时同名的「休」合并成一个数，本来就该合。
  ///
  /// 没有排班、或整月都没有班次（空白表跟随法定节假日）时返回 null。
  String? _monthTally(ScheduleChain? chain) {
    if (chain == null) return null;
    final counts = <String, int>{};
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    for (var d = 1; d <= days; d++) {
      final shift = chain.shiftOn(DateTime(_month.year, _month.month, d));
      if (shift == null) continue;
      counts.update(shift.shortLabel, (n) => n + 1, ifAbsent: () => 1);
    }
    if (counts.isEmpty) return null;
    final parts = [for (final e in counts.entries) '${e.key}${e.value}'];
    return '${L10n.monthTally} ${parts.join(' · ')}';
  }

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month, 1);
    _selected = dateOnly(n);
    WidgetService.widgetLaunchRequested.addListener(_onWidgetLaunchRequested);
    // 冷启动 / 小组件点击时本页尚未挂载（HomeShell 先 `jumpToPage(0)`、下一帧才建出
    // 本页）：那一刻的通知没人接，值会滞留在 notifier 上。这里补一次同步读取，
    // 把「已经落在 notifier 里的跳转意图」落到网格上 —— 否则热启动从别的 tab 切回
    // 日历时选中的还是今天。**不走 `_onWidgetLaunchRequested`**：那里 `setState` 在
    // `initState` 里是多余的（首帧本来就要 build），直接赋值即可。
    final pending = WidgetService.widgetLaunchRequested.value;
    if (pending != null) {
      WidgetService.widgetLaunchRequested.value = null;
      _month = DateTime(pending.year, pending.month, 1);
      _selected = dateOnly(pending);
    }
  }

  @override
  void dispose() {
    WidgetService.widgetLaunchRequested.removeListener(_onWidgetLaunchRequested);
    super.dispose();
  }

  /// 用户在桌面小组件上点了某一天。
  ///
  /// 消费完由**这里**把 notifier 置回 null（不是 HomeShell）—— HomeShell 只负责
  /// 切到日历页，切完还得有人把日期落到网格上。置回会再触发一次监听，
  /// 靠开头那句「值为 null 就返回」兜住，不会递归。
  void _onWidgetLaunchRequested() {
    final d = WidgetService.widgetLaunchRequested.value;
    if (d == null) return;
    WidgetService.widgetLaunchRequested.value = null;
    if (!mounted) return;
    setState(() {
      _month = DateTime(d.year, d.month, 1);
      _selected = dateOnly(d);
    });
  }

  /// 换月动画的方向：`+1` 往后的月份、`-1` 往前的月份。
  ///
  /// 换月动画要「往哪翻就从哪边进来」，所以方向不能写死。`_today` 与月份选择器
  /// 可能一次跳好几个月，一律按实际前后关系定，不按点了哪个键。
  int _monthRoll = 1;

  /// 换月都要走这里：定方向 + 换月。月份没变就什么都不做（`_today` 在本月内点
  /// 一下不该触发一次动画）。
  void _setMonth(DateTime m) {
    final next = DateTime(m.year, m.month, 1);
    if (next == _month) return;
    setState(() {
      _monthRoll = next.isAfter(_month) ? 1 : -1;
      _month = next;
    });
  }

  void _prev() => _setMonth(DateTime(_month.year, _month.month - 1, 1));
  void _next() => _setMonth(DateTime(_month.year, _month.month + 1, 1));
  void _today() {
    final n = DateTime.now();
    setState(() {
      // 今天跳回本月要不要滑、往哪边滑，同样按前后关系定。
      _monthRoll = DateTime(n.year, n.month, 1).isAfter(_month) ? 1 : -1;
      _month = DateTime(n.year, n.month, 1);
      _selected = dateOnly(n);
    });
  }

  Future<void> _showMonthPicker() async {
    final picked = await showGlassMonthPicker(context, initialMonth: _month);
    if (picked != null && mounted) {
      _setMonth(picked);
    }
  }

  /// 换月那一下位移：往前翻往左走、往后翻往右走，两头都带淡入淡出。
  ///
  /// **只包「随月份变的那部分」** —— 网格，以及年月胶囊里那几个字。顶栏那几个圆形
  /// 按钮不包：它们不随月份变，跟着一起滑会显得整条顶栏在晃。
  ///
  /// 换月只有「‹ ›」和月份选择器两条路径（网格上没有横向手势，横向拖动归底栏导航），
  /// 所以这个位移不会跟任何手势打架。
  Widget _monthSlide({
    required DateTime month,
    required String tag,
    required Widget child,
  }) =>
      AnimatedSwitcher(
        duration: AppTokens.durMed,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        // 默认把两个孩子**居中**堆叠；5 行的月份换 6 行的月份时两者高度不同，居中
        // 会让旧的那版上下错开半行。按上沿对齐才是「一页换一页」。
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, animation) {
          // 进来的那个是当前月份（从翻页那一侧滑入），出去的是上一个月（往反方向
          // 滑走）—— 两个孩子方向相反，而 `AnimatedSwitcher` 给它们的 `animation`
          // 是同一个（一个正向、一个反向），光看 `animation` 分不出谁是谁，所以让
          // 每个孩子自己带上月份来分（[_MonthPane]）。
          final pane = child as _MonthPane;
          final dir = pane.month == month ? _monthRoll : -_monthRoll;
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                // 位移只要一小段（卡片宽度的 6%），其余观感交给淡入淡出 —— 整屏
                // 宽度那种滑法在月历上太闹。
                begin: Offset(0.06 * dir, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: _MonthPane(
          key: ValueKey('$tag-${month.year}-${month.month}'),
          month: month,
          child: child,
        ),
      );

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

  /// 点按位置 → 选中日期。**只接点按**（唯一调用点是 `onTapDown`）。
  ///
  /// 滑块「拖到新的一格」不经过这里：拖拽那一路由 `onPanEnd` 吸附
  /// （走 `_nearestDateFromVisual`），触觉也在那边发。旧注释写成「2D 拖拽/点按」，
  /// 正是这种「看着也管拖拽」的措辞把触觉引到了错的落点。
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
    // 整页按**天**解析：某天归哪套方案由链回答（spec §2 ②），所以下面
    // 「网格 / 信息卡 / 本月统计 / 已调班」全都只认它，不再认「当前方案」。
    final chain = scheduleAsync.valueOrNull?.chain;
    ref.watch(appSettingsProvider); // 语言切换时重建

    return Scaffold(
      // 玻璃要有东西可透（见 `FlowingBackground`）：底色仍是主题给的那块平坦中性色，
      // 光晕叠在它上面。在此之前整页唯一的「流光」只出现在响铃界面，日历页是一块纯色
      // —— 满页磨砂其实没在磨东西，只靠高光与描边撑着。
      //
      // 包在 `SafeArea` **外面**：它是整页的底，不该被安全区切掉边。两层包在一行里，
      // 好让下面这一大段内容保持原缩进、不制造一片只有空白的 diff。
      body: FlowingBackground(
        intensity: _bgIntensity,
        // 这一页天天停留，「高级材质」一关就别再推动背景了（见那个参数的说明）。
        freezeWhenBlurDisabled: true,
        child: SafeArea(child: Builder(builder: (context) {
          final layout = AppLayout.of(context);
          final gridArea = Expanded(
            // 网格区高度要先量出来，才能决定格子长多高（见 _buildGrid）。
            child: LayoutBuilder(
              builder: (context, c) => scheduleAsync.isLoading && chain == null
                  ? const Center(child: CircularProgressIndicator())
                  // 网格可滚动：格子保持全尺寸，小屏 6 行放不下时滚动而非被裁切，
                  // 避免底部行与信息卡重叠。
                  : SingleChildScrollView(
                      child: _monthSlide(
                        month: _month,
                        tag: 'grid',
                        child: _buildGrid(context, chain, c.maxHeight),
                      ),
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
                          child: _infoCard(context, chain, inSidePane: true),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                // **小窗（高 < 480dp）不画网格，只留今日信息卡。**
                //
                // 这个尺寸下两者都想要的结果是两者都看不清：200×400 的窗口里
                // 网格只塞得下两三行格子、还被压扁，而「哪天被调过」这个标记
                // 本来就在信息卡上 —— 卡留下、信息就齐了。
                // 各机型小窗的默认尺寸 400×640 高 640 > 480，**不受影响**。
                if (!layout.isShort) gridArea,
                _infoCard(context, chain, compact: layout.isShort),
              ],
            ],
          );
        })),
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
                  child: GlassPill(
                    onTap: _showMonthPicker,
                    height: narrowSide,
                    // 年月这几个字跟着网格一起滑（见 `_monthSlide`），方向才一致。
                    child: _monthSlide(
                      month: _month,
                      tag: 'pill',
                      child: Text(
                        L10n.yearMonth(_month),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTokens.titleStrong,
                      ),
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
                _circleIcon(context, Icons.timeline, L10n.scheduleTimeline,
                    _showTimeline, size: narrowSide),
                const Spacer(),
                GlassPill(
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
            child: GlassPill(
              onTap: _showMonthPicker,
              // 年月这几个字跟着网格一起滑（见 `_monthSlide`），方向才一致。
              child: _monthSlide(
                month: _month,
                tag: 'pill',
                child: Text(
                  L10n.yearMonth(_month),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTokens.titleStrong,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.gapIconText),
          _circleIcon(
              context, Icons.chevron_right_outlined, L10n.nextMonth, _next),
          const SizedBox(width: AppTokens.gapIconText),
          // 切换排班：纯图标圆形钮（省宽，保证年月完整显示）
          _circleIcon(context, Icons.timeline, L10n.scheduleTimeline,
              _showTimeline),
          const SizedBox(width: AppTokens.gapIconText),
          GlassPill(
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

  /// 弹「调整班次」选择层，把 [from]..[to] 这段日子改掉（或恢复轮转）。
  ///
  /// 改完必须重排闹钟：这天可能从工作班变成休班（不该响），或从休班变成夜班
  /// （要响）—— 不重排的话闹钟跟日历就对不上了。
  Future<void> adjustDays(DateTime from, DateTime to) async {
    // 过渡态：跨时段边界要**拦住**是下一个任务；此刻先按**起点那天**所属的方案
    // 办事，与从前在「只有一套」时完全一致。
    final chain = ref.read(activeScheduleProvider).valueOrNull?.chain;
    final schedule = chain?.scheduleOn(from);
    if (chain == null ||
        schedule == null ||
        schedule.isBlank ||
        schedule.classes.isEmpty) {
      // 空白表（跟随法定节假日）没有班次定义可挑，入口本来就不该出现；
      // 这里再兜一次，免得别处误调。
      return;
    }
    final days = <DateTime>[];
    final span = daysBetween(from, to);
    for (var i = 0; i <= span; i++) {
      days.add(dateOnly(DateTime(from.year, from.month, from.day + i)));
    }

    // 拖选跨了时段边界 → **拦住**。
    //
    // 选择层列的是**某一套**的班次定义，而覆盖表的主键是 `{scheduleId, day}`、
    // 按天归属 —— 放过去只能得到「列了 A 的班次、却只对 A 的日子生效」这种
    // **静默半生效**，正是最难查的那类 bug。拦住是不让用户走进那个状态，
    // 代价只是一句话。（与「不跨月拖选」同一条思路。）
    //
    // 判等用 `identical` 而不是 `==`：`ShiftSchedule` 没有 `operator ==`，
    // 两份内容相同的不同实例会被 `==` 判成不等 —— 这里问的是「是不是**同一套**」。
    for (var i = 1; i < days.length; i++) {
      final before = chain.scheduleOn(days[i - 1]);
      final here = chain.scheduleOn(days[i]);
      if (!identical(before, here)) {
        if (mounted) {
          showGlassSnack(
            context,
            L10n.spansTwoSchedules(here?.name ?? '', L10n.monthDay(days[i])),
            icon: Icons.info_outline,
          );
        }
        return;
      }
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

  /// 「排班时段」只读总览。
  ///
  /// **只读是有意的**：原来那个「切换排班」点一行就把 `isCurrent` 换过去，可它改的
  /// 只是「没被时段覆盖时的兜底」—— 时段盖满之后点它什么也不会变，用户以为按钮
  /// 坏了（那正是这一轮重做的起因）。现在它只回答「这段时间在用哪套、今天在哪一
  /// 段」，要改就去排班管理页那条时间线。
  Future<void> _showTimeline() async {
    final schedules = await ref.read(schedulesProvider.future);
    final spans = await ref.read(scheduleSpansProvider.future);
    if (!mounted) return;
    final current = ref.read(activeScheduleProvider).valueOrNull;
    final remaining = current?.current;
    final today = dayNumber(dateOnly(DateTime.now()));

    // 今天落在哪一段上（段之间不重叠，所以至多一段）—— 给那一行打勾。
    int? todaySpanId;
    for (final s in spans) {
      final from = s.startDate == null ? null : dayNumber(s.startDate!);
      final to = s.endDate == null ? null : dayNumber(s.endDate!);
      if ((from == null || today >= from) && (to == null || today <= to)) {
        todaySpanId = s.id;
        break;
      }
    }
    final byId = {for (final s in schedules) s.id: s};
    final hasPeriods = spans.isNotEmpty;

    await showGlassSheet<void>(
      context: context,
      builder: (sheetContext) => GlassPanel(
        solid: true,
        margin: const EdgeInsets.all(12),
        borderRadius:
            const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 底部弹层标题走 `dialogTitle`，与其它弹层同角色。
                Text(L10n.scheduleTimeline, style: AppTokens.dialogTitle),
                const SizedBox(height: 4),
                // 说法与排班管理页那条时间线**同源**：一个段都没有时不说「其余
                // 时间」（没有「这一段」，「其余」就没有着落），整行写「全部
                // 日子」。两处各写一份的话，同一个状态会有两种解释。
                Text(hasPeriods
                    ? L10n.remainingHint
                    : (remaining == null
                        ? L10n.allDatesNoneHint
                        : L10n.allDatesHint),
                    style: AppTokens.rowSecondary
                        .copyWith(color: AppTokens.inkMuted(sheetContext))),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _timelineLine(
                        sheetContext,
                        label: hasPeriods ? L10n.remainingTime : L10n.allDates,
                        value: remaining?.schedule.name ?? L10n.remainingNone,
                        mutedValue: remaining == null,
                        // 今天没落在任何段上 → 今天归「其余时间」。
                        isToday: todaySpanId == null,
                      ),
                      for (final s in spans)
                        _timelineLine(
                          sheetContext,
                          label: spanRangeLabel(s.startDate, s.endDate),
                          value: byId[s.scheduleId]?.name ?? L10n.remainingNone,
                          mutedValue: byId[s.scheduleId] == null,
                          isToday: s.id == todaySpanId,
                        ),
                      const Divider(height: 1),
                      GlassPressable(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(L10n.manageTimeline),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) =>
                                    const ScheduleManagementScreen()));
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
      ),
    );
  }

  /// 总览里的一行：左边的勾（今天所在的那一段）+ 日期 / 「其余时间」 + 方案名。
  ///
  /// 两边都是 flex、各自省略号 —— 与排班管理页那一节同一套写法（`ListTile` 的
  /// `trailing` 在 200dp 小窗下会横向溢出）。
  Widget _timelineLine(
    BuildContext context, {
    required String label,
    required String value,
    required bool mutedValue,
    required bool isToday,
  }) {
    final muted = AppTokens.inkMuted(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
      child: Row(
        children: [
          SizedBox(
            width: AppTokens.iconMd,
            child: isToday
                ? AppIcon(Icons.check_circle_outlined,
                    size: AppTokens.iconMd,
                    color: Theme.of(context).colorScheme.primary)
                : null,
          ),
          const SizedBox(width: AppTokens.gapIconText),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTokens.rowPrimary),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: mutedValue
                  ? AppTokens.rowSecondary.copyWith(color: muted)
                  : AppTokens.labelStrong,
            ),
          ),
        ],
      ),
    );
  }

  /// 网格 + （整月都没排班时）一层指路。
  ///
  /// **指路那一层必须 `IgnorePointer`**：不加的话它会吃掉网格的手势 —— 点日期、
  /// 长按拖选全失灵，而「盖了一层透明东西导致交互没了」在 widget 测试里默认照不
  /// 出来（除非专门去点一下）。用例里就是**真的点某天**再断言信息卡变了。
  Widget _buildGrid(
      BuildContext context, ScheduleChain? chain, double availHeight) {
    final body = _gridBody(context, chain, availHeight);
    if (!_monthHasNoSchedule(chain, _month)) return body;
    final muted = AppTokens.inkMuted(context);
    return Stack(
      children: [
        body,
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceXl),
                // **必须是一张（近）不透明的面板**：直接铺两行字会压在格子的
                // 日期与农历上，两边都看不清（出图当场看出来的）。
                child: GlassPanel(
                  solid: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceLg,
                      vertical: AppTokens.spaceMd),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(L10n.noScheduleHere,
                          textAlign: TextAlign.center,
                          style: AppTokens.sectionTitle),
                      const SizedBox(height: AppTokens.spaceXs),
                      Text(L10n.noScheduleHereHint,
                          textAlign: TextAlign.center,
                          style:
                              AppTokens.rowSecondary.copyWith(color: muted)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 这个月是不是**一天班表都没有**（「其余时间」设成了「无」、又没有任何段覆盖）。
  ///
  /// 逐天问一遍：一个月最多 31 次，可以忽略；而判「中点那天」会在跨段边界的
  /// 月份上判错。
  ///
  /// **判据是「这天有没有班表在管」（`chain.hasScheduleOn`），不是「这天画得出什么」**。
  /// 两者在空白表（跟随法定节假日）上分家：那套班表**天天都在管**，`shiftOn` 却恒为
  /// null（它没有班次定义）。用后者就会把「只有一套法定班次」误判成空库、整张日历被
  /// 这层指路盖住 —— v0.9.14 真机反馈的正是它；v0.9.15 一度改成「给空白表合成一个
  /// 上班 / 休息班次」来绕开，那是拿**显示**去迁就**判据**，用户当即指出「确实不应该
  /// 显示上班，它本质上就是一张日历」。判据归判据、显示归显示。
  bool _monthHasNoSchedule(ScheduleChain? chain, DateTime month) {
    if (chain == null) return true;
    final days = DateTime(month.year, month.month + 1, 0).day;
    for (var d = 1; d <= days; d++) {
      if (chain.hasScheduleOn(DateTime(month.year, month.month, d))) return false;
    }
    return true;
  }

  Widget _gridBody(
      BuildContext context, ScheduleChain? chain, double availHeight) {
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
              // 速度从这一格起算：上一段拖动的尾巴不许再算进来。
              _vx = 0;
              _vy = 0;
              _lastFrameStamp = null;
              _lastVelCol = startCol;
              _lastVelRow = startRow;
            });
          },
          onPanUpdate: (d) {
            final double col = (d.localPosition.dx - _hPad) / cellW - _grabCol;
            final double row = (d.localPosition.dy - _weekdayH) / cellH - _grabRow;
            // 速度：**位置的帧间差分 ÷ 真实的帧间隔**（`lensVelocityStep`，带低通）。
            // 与底栏 / 分段器 / 开关 / 响铃那枚药丸同一套 —— **别退回 `delta × 60`**：
            // 120Hz 上每帧位移只有一半、形变也就只有一半（v0.10.6 与 v0.10.14 各踩过一次）。
            //
            // ⚠️ **只在帧戳真的变了时才算**：同一帧 rebuild 多次是常态（指针事件不按帧到达），
            // 第二遍进来位移已经被吃掉、算出来是 0，而低通会把那个 0 当真。
            final Duration stamp =
                SchedulerBinding.instance.currentSystemFrameTimeStamp;
            if (stamp != _lastFrameStamp) {
              final Duration? prev = _lastFrameStamp;
              _lastFrameStamp = stamp;
              if (prev != null) {
                _vx = lensVelocityStep(
                    deltaPage: col - _lastVelCol,
                    itemW: cellW,
                    dt: stamp - prev,
                    previous: _vx);
                _vy = lensVelocityStep(
                    deltaPage: row - _lastVelRow,
                    itemW: cellH,
                    dt: stamp - prev,
                    previous: _vy);
              }
              _lastVelCol = col;
              _lastVelRow = row;
            }
            setState(() {
              _visualCol = col;
              _visualRow = row;
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
              // ⚠️ **不要把 `_vx` / `_vy` 归零**：松手之后那枚块还要靠最后一次速度
              // 把形变**收回去**（`CalendarLens` 自己按帧衰减）。归零的话形变会
              // 「啪」地消失，而不是收回去。下一次 `onPanStart` 才清它。
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
            //
            // 整条链上有一套「有周期」的就能进 —— 具体那天归哪套、能不能挑，
            // 由 `adjustDays` 按起点那天再判一次。
            final canPick = chain?.hasCycle ?? false;
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
            //
            // 但**没进入多选态就不许响**：长按落在空白格 / 周标题上，或整张空白表
            // 方案（`canPick` 为假，spec §7.3）时 `date` 是 null、`_rangeAnchor`
            // 也没设上 —— 那一下什么也没发生，却发一记「进入多选态」的强震，
            // 正是这套设计要避免的「震了却不携带信息」。
            if (date != null) Haptics.modeEnter();
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
                      ..._dayRows(context, cellW, cellH, chain,
                          // 液态档才有：那枚块**当前的中心**（格子层坐标）。
                          // 「内容被它挤」用得到，标准档传 null（一层都不算）。
                          lensCenter: showBlock && liquidGlassActive.value
                              ? Offset(blockLeft + cellW / 2, blockTop + cellH / 2)
                              : null),
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
                      // ⚠️ 液态档**钉在 1.0**：按住那个动作改由「四面鼓出 + 浮起阴影」
                      // 承担（`CalendarLens` 的升程），两个叠在一起就重了。
                      // 标准档一个字不改 —— 它靠的正是这 1.22。
                      scale: _pressed && !liquidGlassActive.value ? 1.22 : 1.0,
                      duration: AppTokens.durMed,
                      curve: Curves.easeOutBack,
                      child: _glassBlock(context, cellW, cellH),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 周标题行。
  ///
  /// 每个标签**包一层 `FittedBox(scaleDown)`**：`_weekdayH` 是个固定常数（26），
  /// 而这一行的字号是 `labelSecondary` **再乘系统字号** —— 系统字号放到 2×，字高
  /// 约 30dp 就顶出这条 26dp 的带了，`Center` 不裁也不省略，于是这行字**压进下面
  /// 第一行格子里**（2026-09-29 用户截图里那行看着「挤」的就是它）。
  ///
  /// **有意不去按系统字号长高 `_weekdayH`**：那个常量同时被 `_buildGrid` 的命中
  /// 测试算式用（`d.localPosition.dy - _weekdayH`，六处），改成逐帧算的值要让那些
  /// 算式一起跟着走 —— 漏一处就是「系统字号调大之后点哪一格都不对」。而且换来的
  /// 高度换不成更大的字：格子里的字是按**格子高度**缩放的，网格本身是定尺的。
  ///
  /// 这条与整格那层 `FittedBox` 是同一条设计规则：**网格是定尺的点阵，字一律归一到
  /// 格子里**；真正按系统字号长的是底栏信息卡（`info_card_metrics.dart` 用
  /// `textScaler` 实测高度）。
  Widget _weekdayRow(BuildContext context, double cellW) {
    final labels = L10n.weekdays;
    return SizedBox(
      height: _weekdayH,
      child: Row(
        children: List.generate(7, (i) => SizedBox(
              width: cellW,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    labels[i],
                    style: AppTokens.labelSecondary
                        .copyWith(color: AppTokens.inkMuted(context)),
                  ),
                ),
              ),
            )),
      ),
    );
  }

  List<Widget> _dayRows(
      BuildContext context, double cellW, double cellH, ScheduleChain? chain,
      {Offset? lensCenter}) {
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
      // 这一格的内容被透镜边缘挤成什么样（液态档才有；`null` = 一层都不套）。
      final int slot = _leading + d - 1;
      final Matrix4? warp = lensCenter == null
          ? null
          : _cellWarp(
              cellCenter: Offset(_hPad + (slot % 7 + 0.5) * cellW,
                  _weekdayH + (slot ~/ 7 + 0.5) * cellH),
              lensCenter: lensCenter,
              cellW: cellW,
              cellH: cellH,
            );
      cells.add(_dayCell(
          context,
          date,
          // 真值：空白表（跟随法定节假日）那套没有班次定义，这里就是 null ——
          // 格子只画日期与农历，**不替它断言今天上不上班**（v0.9.16 用户反馈）。
          // 「有没有班表在管」是另一件事，由 `chain.hasScheduleOn` 回答。
          chain?.shiftOn(date),
          lunarOf(date),
          cellW,
          cellH,
          isSameDay(date, today),
          blockDate != null && isSameDay(date, blockDate),
          chain?.scheduleOn(date)?.dayOverrides.containsKey(dayNumber(date)) ??
              false,
          _rangeAnchor != null &&
              _rangeFocus != null &&
              _inSelectedRange(date),
          warp: warp));
    }
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      final chunk = cells.sublist(i, math.min(i + 7, cells.length));
      rows.add(Row(children: chunk));
    }
    return rows;
  }

  /// 这一格的**内容**被透镜边缘挤成什么样 —— 液态档才有。
  ///
  /// 用二维版 `lensIconWarp2d`（一维版只认 x，给底栏 / 分段器那种「一排」的控件）。
  ///
  /// ⚠️ 半宽半高取**静止那一档**（内盒的一半），**不是**「满升程 + 满形变」那一档。
  /// 一维版那边两者只差约 5%（照最大值取无所谓），而这里从静止到满形变，透镜的宽会从
  /// 52 涨到 74（**+43%**）—— 照最大值取的话，`t` 会把**静止时**的相邻格子也算成
  /// 「在透镜里」，于是日历的常态画面上就带着一层变形（**逐张比基线时当场抓到的**：
  /// 差异掩码里相邻两格的字整片亮起）。照静止那一档取，静止时相邻格子 `t ≈ 2.2`、
  /// 权重见底、一层都不套；拖动到两格之间时 `t ≈ 1.08`、权重 ≈ 0.97 —— 正好。
  ///
  /// 恒等时返回 `null`：**一层恒等的 `Transform` 都不套**（它也是要付代价的）。
  Matrix4? _cellWarp({
    required Offset cellCenter,
    required Offset lensCenter,
    required double cellW,
    required double cellH,
  }) {
    final double hw = (cellW - 2 * _cellInset) / 2;
    final double hh = (cellH - 2 * _cellInset) / 2;
    final ({double scaleRadial, double scaleTangent, double dx, double dy,
        double angle}) w = lensIconWarp2d(
      itemCenterX: cellCenter.dx,
      itemCenterY: cellCenter.dy,
      lensCenterX: lensCenter.dx,
      lensCenterY: lensCenter.dy,
      lensHalfWidth: hw,
      lensHalfHeight: hh,
    );
    if (w.scaleRadial == 1.0 && w.dx == 0.0 && w.dy == 0.0) return null;
    // 沿径向压扁、垂直方向拉长，再朝远离透镜中心的方向推一点。
    return Matrix4.identity()
      ..translateByDouble(w.dx, w.dy, 0, 1)
      ..rotateZ(w.angle)
      ..scaleByDouble(w.scaleRadial, w.scaleTangent, 1, 1)
      ..rotateZ(-w.angle);
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
  ///
  /// [warp] 是液态档那枚透镜把它**内容**挤了一下的仿射变换（`null` = 不套）。
  /// 只套内容、**不套卡片**：卡片动了就成了「格子自己在扭」，而用户要的是
  /// 「一枚玻璃压过去」。`Transform` 只改绘制、不改布局，所以字的排版不会跟着变。
  Widget _dayCell(BuildContext context, DateTime date, ShiftClass? shift,
      LunarInfo lunar, double cellW, double cellH, bool isToday, bool solid,
      bool adjusted, bool inRange, {Matrix4? warp}) {
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
    // 农历这行**必须有自己的 `FittedBox`**，与上面的日期行同一个写法。
    //
    // 它原来是 `maxLines: 1` + `ellipsis`，而整格外面那层 `FittedBox` 救不了它：
    // 外层给这一行的约束是**固定的 `contentW` 宽**，文字先按那个宽度排好、省略号
    // 已经烘进结果里了，之后外层再等比缩小也变不回来（缩小不能「取消省略」）。
    // 日期与班次胶囊没这个问题，正因为它们各自有一层 `FittedBox`：文字在**无界宽**
    // 下自然排布，再由那层按需缩放。
    //
    // 症状（2026-09-29 用户反馈的截图）：「财神节 / 地藏节 / 中秋节」这类**三个字
    // 以上**的节日名被截成「财…」「地…」。两个字的「廿一」放得下、三个字放不下，
    // 正是「格内容宽 44dp 上下 + 字号 13.75px」这条线上发生的事；**系统字号一放大
    // 就更容易撞上**（App 全app 都没有钳制 `textScaler`，而这一行的字号是在令牌
    // 基础上再乘系统缩放）。所以它不是「窄屏专属」，窄屏只是让它更早出现。
    //
    // 去掉 `ellipsis` 而不是留着：无界宽下它永远不会触发，留着会让人以为这里
    // 还有一条省略的退路。
    final lunarLine = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: FittedBox(
        fit: BoxFit.scaleDown,
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
              // `cellLabel` 而不是 `shortLabel`：格子装不下 4 个字以上的节日名，
              // 而把长名字丢给上面那层 `FittedBox` 缩会变成 6px 的糊字（完整但
              // 没人看得见）。两者的分工见 `LunarInfo.cellLabel` 的说明。
              TextSpan(text: lunar.cellLabel),
            ],
          ),
          maxLines: 1,
          style: lunarStyle.copyWith(color: lunarColor),
        ),
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
          : FittedBox(
              // 与日期、农历、周标题同一条规则：文字在**无界宽**下排好，再由这层
              // 按需缩小 —— 有 `ellipsis` 的话，省略号会先按 `contentW` 烘进结果，
              // 外层再怎么缩也变不回来（农历那一行的原话见 `lunarLine` 上面）。
              fit: BoxFit.scaleDown,
              child: Text(
                shift.shortLabel,
                // 窄到画不出胶囊时的退路：班次色是给色块用的强色，当文字色太浅
                // （橙 2.06:1、灰 2.60:1），要按格子底色算一版可读的。
                maxLines: 1,
                style: AppTokens.scaled(AppTokens.microStrong, s).copyWith(
                  color: AppTokens.inkFor(Color(shift.color), surface),
                ),
              ),
            ));
    }
    children
      ..add(const SizedBox(height: AppTokens.gapHair))
      ..add(lunarLine);

    // 内容那一层（日期 + 班次胶囊 + 农历）。抽出来是为了让「挤那一下」能套在它外面。
    final Widget fittedContent = FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: contentW,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: children,
        ),
      ),
    );

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
                    // 14% 是全 app 的淡染约定值（同一行「已调整」胶囊、待办徽章
                    // 都用它）—— 原来是 18%，是这里唯一一处 18% 的染色。
                    color: primary.withValues(alpha: 0.14),
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
              //
              // 外面那层 `Transform` 是液态档「内容被透镜边缘挤」——
              // **`warp == null` 时一层都不套**（恒等的 Transform 也是要付代价的），
              // 而套上时它只改绘制：`Transform` 不动布局，字的排版与换行都不变。
              child: warp == null
                  ? fittedContent
                  : Transform(
                      alignment: Alignment.center,
                      transform: warp,
                      child: fittedContent,
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

  /// 「今天」徽章：实心主色 + 白字。
  ///
  /// 完整信息卡与小窗那张精简卡**共用** —— 两处各写一份的话，迟早长成两个样。
  Widget _todayBadge(BuildContext context) => Container(
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
      );

  /// 「已调班」徽章：这天被单独调动过。
  ///
  /// 形状抄同一行的邻居 —— **「N 项待办」徽章那套配方**（14% 淡染底 + 45% 同色
  /// 描边 + `radiusL` + `inkFor` 文字，见 `_todoHintBadge`），只是不带图标。
  /// 原来这里是一句**裸 `Text`**，而同一行另外两个徽章（「今天」「N 项待办」）
  /// 都是胶囊 —— 三种形状并排看着就散。
  ///
  /// 完整卡与小窗的精简卡**共用**。小窗那张尤其需要它：那里格子窄到画不出胶囊、
  /// 圆点根本不会出现，信息卡是唯一还能承载这个标记的地方。
  ///
  /// 胶囊比裸文字高，所以它在**完整卡**里的高度必须进定高模型：见
  /// `info_card_metrics.dart` 的 `_adjustedBadgeH` 与 `hasOverrideHint`。
  Widget _adjustedBadge(BuildContext context, Color primary) => Container(
        key: const Key('info-card-adjusted'),
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceSm, vertical: AppTokens.padChipV),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppTokens.radiusL),
          border: Border.all(color: primary.withValues(alpha: 0.45)),
        ),
        child: Text(
          L10n.adjusted,
          style: AppTokens.microStrong.copyWith(
              color: AppTokens.inkFor(
                  primary,
                  Color.alphaBlend(primary.withValues(alpha: 0.14),
                      Theme.of(context).colorScheme.surface))),
        ),
      );

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
  Widget _glassBlock(BuildContext context, double cellW, double cellH) {
    final accent = Theme.of(context).colorScheme.primary;
    // 液态档：一枚真的玻璃透镜（按住四面鼓出、拖动跟速度形变、边缘挤过格子里的字）。
    // 它替下的是那个 1.22 的等比放大 —— 标准档那棵树上那条路径一个字没动。
    if (liquidGlassActive.value) {
      return CalendarLens(
        // 与标准档那一枚**同一个 key**：它就是「选中块」这一个东西，
        // 两个档位各是一棵树，但对外（单测、工装）是同一个身份。
        key: const Key('calendar-selection-block'),
        size: Size(cellW, cellH),
        liftTarget: (_pressed || _dragActive) ? 1 : 0,
        dragging: _dragActive,
        velocity: Offset(_vx, _vy),
        isDark: Theme.of(context).brightness == Brightness.dark,
        accent: accent,
      );
    }
    return Container(
      key: const Key('calendar-selection-block'),
      margin: const EdgeInsets.all(_cellInset),
      decoration: BoxDecoration(
        borderRadius: _cellRadius,
        // 14% 是全 app 的淡染约定值。这里从前是 13% —— 拖动选范围时
        // 范围底色（14%）会紧贴这一块，两个值同屏只显得脏。
        color: accent.withValues(alpha: 0.14),
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
  Widget _infoCard(BuildContext context, ScheduleChain? chain,
      {bool inSidePane = false, bool compact = false}) {
    final lunar = lunarOf(_selected);
    // 这一屏讲的是**选中那天**，所以取那天所属的方案；下面「班次行 / 已调班 /
    // 空白表 / 其他班组」四处全用它。跨时段之后**不能再认「当前方案」** ——
    // 「今天归哪套」是链才知道的事。
    final daySchedule = chain?.scheduleOn(_selected);
    // 真值：空白表（跟随法定节假日）**没有班次定义**，这里就是 null —— 于是
    // 信息卡、小窗精简卡都不替它写「上班」。
    //
    // 别退回「给空白表合成一个班次」那一版（v0.9.15 试过）：那是拿显示去迁就判据。
    // 「有没有班表在管」是**另一件事**，由 `chain.hasScheduleOn` 回答（只有
    // 「整月没有任何班表」时才写「这段时间没有排班」）。
    final shift = chain?.shiftOn(_selected);
    final isToday = _selected == dateOnly(DateTime.now());
    final muted = AppTokens.inkMuted(context);
    final accent = shift != null
        ? Color(shift.color)
        : Theme.of(context).colorScheme.primary;
    // 「信息胶囊」那套配方一律走主色（「今天」「N 项待办」「已调整」同一族），
    // 与上面的 `accent`（跟着当天班次色走）不是一回事。
    final primary = Theme.of(context).colorScheme.primary;

    // 短屏（手机横屏 / 小窗）走单行紧凑版：360×360 这类窗口里网格才是主角，
    // 完整信息卡（约 340 高）会把网格挤到只剩一条缝。这里保留
    // 「哪天 · 什么班 · 几点到几点」，带上闹钟图标；农历、今天徽章与其他
    // 班组收起来 —— 网格上本来就直接画着班次与农历，信息没有丢。
    if (compact) {
      final timeText =
          (shift != null && shift.startMinute != null && shift.endMinute != null)
              ? _timeRange(shift)
              : null;
      final isAdjusted =
          daySchedule?.dayOverrides.containsKey(dayNumber(_selected)) ?? false;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 76),
        // 与完整信息卡那行班次同源：套 `GlassPressable` 承载点击（它自己没
        // `onTap`），内层 `InkWell` 负责手势 —— 见上面完整卡那段的说明。
        child: GlassPressable(
          child: InkWell(
            onTap: (daySchedule == null || daySchedule.classes.isEmpty)
                ? null
                : () => adjustDays(_selected, _selected),
            child: GlassTile(
              padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg,
                  AppTokens.spaceMd, AppTokens.spaceMd, AppTokens.spaceMd),
              // 小窗这一档**同时**意味着「不画网格」（见 build 里那条 `isShort`），
              // 所以这张卡就是屏幕上唯一的内容 —— 它得把该说的都说清楚，而不是
              // 像从前那样只挤一行「日期 · 班次 · 时间」。
              //
              // **「已调班」徽章必须在这里。** 小窗下格子里那个圆点根本画不出来
              // （格子窄到画不出胶囊），信息卡是唯一还能承载标记的地方；不给它，
              // 小窗里被调过的日子在界面上就完全没有痕迹了。
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 18,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusS),
                        ),
                      ),
                      const SizedBox(width: AppTokens.gapIconTextLg),
                      Flexible(
                        child: Text(
                          // 200dp 宽下带星期那份（「9月18日 星期五」）会被截成
                          // 「9月18…」，读不出日期；今天与否由旁边的徽章说。
                          // 完整卡仍然带星期。
                          L10n.monthDay(_selected),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTokens.sectionTitle,
                        ),
                      ),
                      if (isToday) ...[
                        const SizedBox(width: AppTokens.spaceSm),
                        _todayBadge(context),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(
                    // 用格子用的那个短农历（「初八」），不用 `fullDescription`
                    // —— 后者在 200dp 宽下要三行、截出来是「九…」这种半截字。
                    // 窄窗里要的是「哪天、什么班、调没调过」，农历是点缀。
                    lunar.shortLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTokens.rowSecondary.copyWith(
                      color: lunar.isLegalHoliday ? AppTokens.holiday : muted,
                    ),
                  ),
                  if (shift != null) ...[
                    const SizedBox(height: AppTokens.spaceSm),
                    Row(
                      // 顶上对齐：左边色点、右边「名 + 徽章」一行、时间再一行。
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.only(top: AppTokens.padChipV),
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                                color: Color(shift.color),
                                shape: BoxShape.circle),
                          ),
                        ),
                        const SizedBox(width: AppTokens.gapIconText),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      shift.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTokens.rowPrimary,
                                    ),
                                  ),
                                  if (isAdjusted) ...[
                                    const SizedBox(
                                        width: AppTokens.gapIconText),
                                    _adjustedBadge(context, accent),
                                  ],
                                ],
                              ),
                              // 时间另起一行而不是与班次名挤同一行：200dp 宽下
                              // 挤一起的结果是「白班 0…」—— 时间全被截掉。
                              if (timeText != null) ...[
                                const SizedBox(height: AppTokens.gapHair),
                                Text(
                                  timeText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTokens.labelSecondary,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 选中那天还没完成的待办条数。只说数量，不列内容（用户要的只是「今天有
    // 待办」这一眼）。口径抽在 `isPendingTodoOn`（`app_repository.dart`）里 ——
    // 桌面小组件快照的今日待办数与这里必须是同一个判定。
    final pendingTodos = ref
            .watch(eventsProvider)
            .valueOrNull
            ?.where((e) => isPendingTodoOn(e, _selected))
            .length ??
        0;

    // 卡片内容。做成**闭包**而不是直接赋值：最后那行「本月统计」画不画，要等
    // `LayoutBuilder` 量出卡片宽度、拿到当天的富余才知道（见 `_tallyFits`），而闭包
    // 顺手把上面这些派生值都捕获了，不必为此抽一层参数长长的私有方法。
    Widget buildContent(String? tally) => Column(
      key: const Key('info-card-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // **必须能收窄。** 这一行是「日期 + 今天徽章 + 待办徽章」三个并排，
            // 而日期这一串（「9月29日 星期二」）没有弹性 —— 系统字号一放大
            // （1.8× 实测）它就顶穿卡片右边缘 76px，把「N 项待办」徽章整个挤出去。
            //
            // 用 `FittedBox(scaleDown)` 而不是 `Flexible + ellipsis`：这一行里
            // 日期与两个徽章都要紧（徽章分别说「今天」和「有几件待办」），
            // 谁也丢不得。放不下时**缩日期**、三个元素全留着；放得下时它一像素
            // 都不动（`scaleDown` 只缩不放）。
            //
            // 高度方向也因此是安全的：`info_card_metrics.dart` 是**按缩放大小的
            // 字号**量这一行的，这里缩完只会更矮，不会把定高撑破。
            //
            // 与紧凑卡那一支（`Flexible` + 省略号）有意不同：那一支窄到 200dp，
            // 缩到那个宽度日期就没法看了，宁可直接省略（那边另有说明）。
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  L10n.monthDayWeekday(_selected),
                  // 设计规格把字重收成「标题 w700 / 强调 w600 / 正文 w500」，
                  // w800 只留给响铃大时钟与角标「今天」，所以日期行走 w700 的
                  // sectionTitle。
                  style: AppTokens.sectionTitle,
                ),
              ),
            ),
            if (isToday) ...[
              const SizedBox(width: 8),
              _todayBadge(context),
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
        // `shift` 是真值：空白表（跟随法定节假日）这天是 null，走下面「有班表、
        // 但没班次」那一支（什么都不写）。
        if (shift != null && daySchedule != null)
          // `GlassPressable` **没有 `onTap`** —— 它只是个按压缩放的视觉包装
          // （`Listener` + `QScale`），点击一律由子 widget 承载。这里用
          // `GestureDetector` 只拿点击：全 app 的按压反馈就是玻璃的 Q 弹缩放，
          // 水波纹只该出现在弹层的 `ListTile` 里（那里 `GlassPressable` 垫的
          // `Material` 让波纹浮在玻璃之上，是有意的）；这张玻璃卡套 `InkWell`
          // 会凭空多出一圈水波纹，最扎眼（spec §7.2）。
          //
          // `opaque`：行内元素之间有空隙（圆点、间距、`Expanded` 文字），不加这个
          // 点在空隙上不响应。
          //
          // 空白表方案没有班次定义可挑，入口不给（spec §7.3）—— 传 null 禁用它。
          // 已知小瑕疵：`GlassPressable` 的按压缩放挡不住，空白表下按这行仍会
          // 缩一下。不值得为它再加一层条件包装。
          GlassPressable(
            key: const Key('info-card-shift-entry'),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: daySchedule.classes.isEmpty
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
                  // 这天被单独调动过：形状抄同一行的邻居，理由见 `_adjustedBadge`。
                  // （外层 `if (shift != null && daySchedule != null)` 已经把它收窄了。）
                  if (daySchedule.dayOverrides.containsKey(dayNumber(_selected)))
                    Padding(
                      padding: const EdgeInsets.only(left: AppTokens.spaceSm),
                      child: _adjustedBadge(context, primary),
                    ),
                ],
              ),
            ),
          )
        // 判据是「**这天有没有班表在管**」，不是「这天有没有班次」：
        //   · 「其余时间」是「无」、又没有段覆盖 → 真的没有排班，写那句说明；
        //   · 有班表在管、只是那天没有班次定义（空白表 = 跟随法定节假日）
        //     → **什么都不写**。那套班表的语义就是「当日历看」：日期、农历、
        //       法定节假日标红都在，不替它断言今天上不上班（v0.9.16 用户反馈）。
        // 写成 `shift == null` 会把第二种误判成第一种 —— 那正是 v0.9.14 用户报的
        // 「一直弹窗提示这段时间没有排班，可我们是按法定节假日上班的」。
        else if (daySchedule == null)
          Text(L10n.noSchedule,
              style: AppTokens.rowSecondary.copyWith(color: muted)),
        if (daySchedule != null && daySchedule.teamCount > 1) ...[
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
                  children: _otherCrewChips(daySchedule, _selected),
                ),
              ),
            ],
          ),
        ],
        // 「本月 早12 · 午8 · 夜8 · 休6」—— 只在**这天还有富余**时才画。
        //
        // 卡片高度是按月定死的（`info_card_metrics.dart`）：最满的那天（通常是有
        // 法定节假日、农历又占两行的日子）正好占满，普通日子则空出 32~51dp。与其
        // 把高度改小 —— 那会把上面的网格带得一起抖，用户明确不要 —— 不如把这截富余
        // 用起来：够就画这一行，不够（比如节假日那天）就不画，**绝不为它动卡片高度**。
        // 判定见 `_tallyFits`，差一两个 dp 也算得出来。
        if (tally != null) ...[
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            tally,
            key: const Key('info-card-month-tally'),
            // 班次多、简称长的排班会折到第二行；折行的高度已由 `_tallyFits` 计入。
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTokens.microText.copyWith(color: muted),
          ),
        ],
      ],
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
    //
    // 内容也在这里面才建出来：那行「本月统计」画不画，取决于「卡片内高 − 当天内容
    // 高度」这截富余（`infoCardTallyFits`），而富余也要先知道卡片宽度。`buildContent`
    // 是闭包，所以搬进来不必给内容补一长串参数。
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final metrics = inSidePane
              ? null
              : _cardMetricsFor(context, chain, constraints.maxWidth);
          final tally = _monthTally(chain);
          final showTally = tally != null &&
              infoCardTallyFits(
                context: context,
                metrics: metrics,
                tally: tally,
                cardOuterWidth: constraints.maxWidth,
                dayOfMonth: _selected.day,
              );

          final content = buildContent(showTally ? tally : null);

          // 底栏时面板必须**撑满**那个定高盒子。`Stack` 默认 `StackFit.loose`，
          // 只给非定位子节点松约束，面板于是缩到内容高度；而左侧色条是
          // `Positioned(top/bottom: spaceLg)`，量的却是外面那个定高盒子 —— 两边
          // 各按各的高度走，色条就比卡片长出几十 dp、垂在空白里（v0.6.6 用户
          // 实测：卡片 126 高，色条 212 高）。给面板一层定高，两者才对得上。
          //
          // 右栏那份反过来要贴内容高度：那边没有「撑满」的必要，也就没有空档，
          // 所以不套这层（`metrics` 为 null → 高度交给内容），色条跟着面板走本来就是对的。
          final panel = GlassTile(
            key: const Key('info-card-panel'),
            padding: const EdgeInsets.fromLTRB(AppTokens.spaceXl,
                AppTokens.spaceLg, AppTokens.spaceLg, AppTokens.spaceLg),
            child: inSidePane
                ? content
                // 兜底：字号被系统放大到装不下时，卡片内部滚动，而不是溢出成
                // 黄黑条纹。正常字号下内容矮于卡片，这一层不产生任何滚动。
                : SingleChildScrollView(child: content),
          );

          return Stack(
            children: [
              SizedBox(
                key: const Key('info-card-box'),
                height: metrics?.outerHeight,
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
          );
        },
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
  if (!t.alarmEnabled || t.alarms.isEmpty) return L10n.alarmOff;
  final alarm = t.alarms.first;
  final clock = formatClock(alarm.minute);
  // 落在上班**前一天**的（00:00 上班的夜班）必须标出来：不标的话，这一行会跟
  // 前面的「00:00 – 08:00」读成同一天的两件事。
  final shown =
      alarmFallsOnPreviousDay(t, alarm) ? L10n.clockPrevDay(clock) : clock;
  // 多条的只写首条 + 「等 N 个」：这一行本来就是 `maxLines: 1` + 省略号，把每条
  // 时刻都铺开会把后面的内容挤掉 —— 而卡片是**定高**的，多一行就顶高卡片、
  // 连带把日历网格挤矮（`info_card_metrics.dart` 那边的前提）。
  return t.alarms.length == 1
      ? L10n.alarmAt(shown)
      : L10n.alarmFirstOfMany(shown, t.alarms.length);
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

/// 换月动画里的一「页」（网格，或年月胶囊里那几个字），带着**它自己那个月**。
///
/// 带月份只为一件事：`_monthSlide` 的 `transitionBuilder` 一次拿到两个孩子 —— 进来
/// 的新月份、出去的旧月份 —— 而两者的滑动方向相反（进来的从翻页那一侧滑入，出去的
/// 往另一侧滑走）。`AnimatedSwitcher` 给两个孩子的 `animation` 是同一个（一个正向、
/// 一个反向），`animation` 本身分不出谁是谁，让每个孩子自己带上月份就分得清了。
class _MonthPane extends StatelessWidget {
  const _MonthPane({super.key, required this.month, required this.child});

  final DateTime month;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

