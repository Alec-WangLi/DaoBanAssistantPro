import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_info.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/layout.dart';
import '../../core/l10n.dart';
import '../../core/motion.dart';
import '../../core/update_checker.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/app_repository.dart';
import '../../domain/shift_rotation.dart';
import '../../state/app_settings.dart';
import '../alarm/alarm_ringing_screen.dart';
import '../alarm/alarm_screen.dart';
import '../alarm/alarm_service.dart';
import '../calendar/calendar_screen.dart';
import '../profile/app_dialogs.dart';
import '../profile/profile_screen.dart';
import '../schedule/schedule_screen.dart';
import '../widget/widget_service.dart';

/// 底部导航壳：悬浮液态玻璃胶囊（点击切整数 tab，拖拽松手停在手指位置）。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  late final PageController _controller;
  bool _startupRescheduled = false;

  static List<(IconData, String)> get _items => [
        (Icons.calendar_month_outlined, L10n.navCalendar),
        (Icons.alarm_outlined, L10n.navAlarm),
        (Icons.event_note_outlined, L10n.navTodo),
        (Icons.person_outlined, L10n.navProfile),
      ];

  static const _screens = [
    CalendarScreen(),
    AlarmScreen(),
    ScheduleScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // 监听生命周期：切回前台时再推一次小组件快照（见 didChangeAppLifecycleState）。
    WidgetsBinding.instance.addObserver(this);
    _controller = PageController();
    // 首帧后再请求权限（Activity 就绪后请求才会弹系统对话框）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AlarmService.requestPermissions();
      // 冷启动由闹钟通知拉起的情况
      if (AlarmService.ringingAlarm.value != null) _showRinging();
      // 冷启动由待办提醒的通知拉起的情况：直接落到「待办」页
      if (AlarmService.openTodoRequested.value) _openTodoPage();
      _maybeShowLaunchDialogs();
      _maybeAutoCheckUpdate();
      // 冷启动由桌面小组件拉起：读一次「要跳到哪天」。
      WidgetService.consumeLaunchDay();
      // 首帧推一次快照，桌面上的卡片立刻与 App 对齐。
      _pushWidgetSnapshot();
    });
    AlarmService.ringingAlarm.addListener(_onRingingChanged);
    AlarmService.openTodoRequested.addListener(_onTodoRequested);
    // 排班数据与外观设置任一变化就重推快照 —— 这是「改完排班桌面立刻变」的那条路。
    ref.listenManual(activeScheduleProvider, (_, __) => _pushWidgetSnapshot());
    ref.listenManual(appSettingsProvider, (_, __) => _pushWidgetSnapshot());
    // 待办变化也要重推：徽章上的「N 项待办」是快照里的一个数，而这条流
    // （eventsProvider）此前**没有任何推送触发** —— 勾掉一条待办之后桌面上的
    // 数字会一整天不动，直到改排班/改外观/下次冷启动。（冷启动那次重复推送无害。）
    ref.listenManual(eventsProvider, (_, __) => _pushWidgetSnapshot());
    WidgetService.widgetLaunchRequested.addListener(_onWidgetDayRequested);
  }

  /// 首次使用弹「开始使用」；每次更新后弹「版本更新」简介。
  ///
  /// 首启弹的是**精简版**（三条），不是完整的「使用帮助」—— 见
  /// `showGettingStartedDialog` 的说明。
  Future<void> _maybeShowLaunchDialogs() async {
    final sp = await SharedPreferences.getInstance();
    final onboarded = sp.getBool('onboarded') ?? false;
    if (!onboarded) {
      await sp.setBool('onboarded', true);
      await sp.setString('lastSeenVersion', appVersion);
      if (mounted) showGettingStartedDialog(context);
      return;
    }
    final lastSeen = sp.getString('lastSeenVersion');
    if (lastSeen != appVersion) {
      await sp.setString('lastSeenVersion', appVersion);
      if (mounted) showChangelogDialog(context);
    }
  }

  /// 冷启动静默检查更新：同一天最多查一次，只有发现新正式版才弹窗（测试版走手动面板）。
  Future<void> _maybeAutoCheckUpdate() async {
    final sp = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayKey = now.year * 10000 + now.month * 100 + now.day;
    if (sp.getInt('lastUpdateCheckDay') == todayKey) return;
    await sp.setInt('lastUpdateCheckDay', todayKey);
    final r = await UpdateChecker.checkUpdates();
    if (!mounted || r.error) return;
    final stable = r.latestStable;
    if (stable != null &&
        UpdateChecker.compareVersion(stable.version, appVersion) > 0) {
      showUpdateDialog(context, r);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AlarmService.ringingAlarm.removeListener(_onRingingChanged);
    AlarmService.openTodoRequested.removeListener(_onTodoRequested);
    WidgetService.widgetLaunchRequested.removeListener(_onWidgetDayRequested);
    _controller.dispose();
    super.dispose();
  }

  /// 切回前台时再推一次小组件快照。
  ///
  /// 冷启动那次已经推过了（见 `initState` 的后帧回调），这里补的是**重试**：
  /// `WidgetService.push` 是 fire-and-forget，失败只留一条日志（它的 catch 里写得
  /// 很清楚），而失败的表现是「卡片停在上一次渲染的样子」—— 用户看到的就是
  /// 「我明明打开过 App，桌面却没变，得重启桌面才行」。
  ///
  /// 一条用户反馈（2026-10-01）是这条的起因。它的**根因**没法在原生侧解决：小组件
  /// 的数据只能由 App 算（原生不查库），所以「装完新版先打开一次 App」这句必须写进
  /// 更新简介；而这里保证「打开了就该生效」，不让用户卡在一个没有出口的状态里。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _pushWidgetSnapshot();
  }

  void _onRingingChanged() {
    if (AlarmService.ringingAlarm.value != null) _showRinging();
  }

  /// 用户点了待办提醒的通知：切到「待办」页，并把请求清掉。
  ///
  /// 清位会再触发一次监听，靠开头那句「值为假就直接返回」兜住，不会递归。
  void _onTodoRequested() {
    if (!AlarmService.openTodoRequested.value) return;
    _openTodoPage();
  }

  /// 切到「待办」页。下标 2 与 `_items` / `_screens` 的顺序绑定
  /// （0 日历、1 闹钟、2 待办、3 我的），改那一组时这里要跟着改。
  void _openTodoPage() {
    AlarmService.openTodoRequested.value = false;
    if (!mounted || !_controller.hasClients) return;
    _controller.jumpToPage(2);
  }

  /// 用户在桌面小组件上点了某一天：切到日历页，再让 CalendarScreen 跳到那天。
  ///
  /// **不在这里把 notifier 置回 null** —— CalendarScreen 还要读它。由那边收尾。
  void _onWidgetDayRequested() {
    if (WidgetService.widgetLaunchRequested.value == null) return;
    if (!mounted || !_controller.hasClients) return;
    _controller.jumpToPage(0); // 0 = 日历，与 _items/_screens 的顺序绑定
  }

  /// 把当前排班与外观算成快照推给原生。
  ///
  /// `hasValue` 那道闸门是必需的：`activeScheduleProvider` 是 StreamProvider，
  /// 首帧还没读到库时 `.value` 是 null，此时推会把「有一定有排班」误报成
  /// 「没有排班」，桌面上闪一下空表提示。等它真下发（哪怕下发的就是 null）再推。
  Future<void> _pushWidgetSnapshot() async {
    final async = ref.read(activeScheduleProvider);
    if (!async.hasValue) return;
    // 今日未完成待办数：与日历信息卡上那个「N 项待办」徽章同一个口径
    // （同一天、`completed == false`）。
    final today = DateTime.now();
    // 待办数读失败不能让整次推送中断 —— `WidgetService.push` 自己的错误处理
    // 在下面，读失败就根本走不到那儿。读不到就按 0 计（徽章不显示），
    // 并留一条痕（「桌面怎么没变」只能靠日志查）。
    var todoCount = 0;
    try {
      final events = await ref.read(appRepositoryProvider).listEvents();
      todoCount = events.where((e) => isPendingTodoOn(e, today)).length;
    } catch (e) {
      await WidgetService.logInfo('widget push: 待办数读取失败，按 0 计: $e');
    }
    if (!mounted) return;
    await WidgetService.push(
      // 推的是**整条链**：快照窗口是一个多月，跨时段边界是常态。
      // 原生侧不受影响 —— 它本来只照着 `days[]` 排版。
      chain: async.value?.chain,
      settings: ref.read(appSettingsProvider),
      todayTodoCount: todoCount,
    );
  }

  void _showRinging() {
    final ring = AlarmService.ringingAlarm.value;
    if (ring == null || !mounted) return;
    AlarmService.logInfo('HomeShell: 弹出全屏响铃界面 label=${ring.title}');
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            AlarmRingingScreen(label: ring.title, detail: ring.detail),
      ),
    );
  }

  Future<void> _tryStartupReschedule() async {
    if (_startupRescheduled) return;
    // 重排要的是**整条链**，不只是当前方案：未来 60 天里可能跨时段边界，
    // 边界之后那几天的班属于别的方案。
    final chain = ref.read(activeScheduleProvider).valueOrNull?.chain;
    final alarms = ref.read(customAlarmsProvider).valueOrNull;
    // 待办也要等流到齐再排，理由同前两个：`activeScheduleProvider` 会先
    // `seedIfEmpty`，这几个流非空就说明首启播种已经完成、库可以读了。
    final events = ref.read(eventsProvider).valueOrNull;
    if (chain == null || alarms == null || events == null) return;
    _startupRescheduled = true;
    final repo = ref.read(appRepositoryProvider);
    // **先生成、再重排**：重复待办的提醒要按「今天该有的那一条」来排，顺序反了
    // 会拿上一轮的日期去算。
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    final overrides = await repo.listShiftAlarmOverrides();
    // 待办**重新读一次**：上面那个 `events` 是生成**之前**的快照，直接用它排会漏掉
    // 刚建出来的那几条（重复待办的提醒走另一条链路，但一次性待办的那几条不能少）。
    AlarmService.reschedule(
      chain,
      alarms,
      overrides: overrides,
      events: await repo.listEvents(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeScheduleProvider, (_, __) => _tryStartupReschedule());
    ref.listen(customAlarmsProvider, (_, __) => _tryStartupReschedule());
    // 待办的流也要听：三个流谁最后到齐都要能触发那次重排，漏掉这一个会出现
    // 「待办先到、另两个后到，于是重排跑了但没排待办」——不报错，只是提醒不发。
    ref.listen(eventsProvider, (_, __) => _tryStartupReschedule());
    ref.watch(appSettingsProvider); // 语言切换时重建导航标签
    return Scaffold(
      extendBody: true,
      // 去掉底部安全区：让页面内容无遮挡地铺满到底、从悬浮胶囊下方穿过，
      // 避免胶囊四周露出不透明的空背景（像一层「蒙版」）。
      body: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: PageView(
          controller: _controller,
          physics: const NeverScrollableScrollPhysics(), // 关闭内容区左右滑动
          children: _screens,
        ),
      ),
      bottomNavigationBar: _GlassNavBar(
        // 给工装用：按图标找 tab 时得能把它和页面里的同名图标区分开 —— 信息卡上
        // 那个「N 项待办」徽章用的就是 `event_note_outlined`，与「待办」tab 同款。
        key: const Key('glass-nav-bar'),
        controller: _controller,
        items: _items,
      ),
    );
  }
}

/// 悬浮液态玻璃胶囊导航：点击切整数 tab，拖拽跟手、松手停在手指位置。
class _GlassNavBar extends StatefulWidget {
  const _GlassNavBar({
    super.key,
    required this.controller,
    required this.items,
  });

  final PageController controller;
  final List<(IconData, String)> items;

  @override
  State<_GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<_GlassNavBar> {
  static const _outerPad = 24.0;
  static const _innerPad = AppTokens.gapIconText;
  static const _capsuleHeight = 64.0;

  /// 短屏（可用高 < 480）用的紧凑尺寸：横屏下 64 高的胶囊约占可用高度的
  /// 六分之一，而它悬浮在内容之上，太占地方。
  static const _capsuleHeightShort = 52.0;
  static const _outerPadShort = 16.0;

  bool _pressed = false;
  bool _dragging = false; // 是否处于拖动中（区别于点按，取消时据此决定是否回退）
  int _committedIndex = 0; // 已提交（正在显示）的功能区
  int? _previewIndex; // 按下/拖动时预览的功能区（松手才提交）
  double _visualPage = 0; // 滑块左缘位置（以功能区宽度为单位，可为小数）
  double _grabOffset = 0; // 手指相对滑块左缘的抓取偏移（跟手不跳的关键）

  /// 本控件正在自己驱动页面（`_release` 里那段翻页动画）。
  ///
  /// 用来把「手势翻页」和「外部程序化切页」分开：动画期间控制器会持续上报
  /// 中间位置，若照单全收，滑块会跟着动画往回滑一下再过去，与「松手即吸附」
  /// 的既有手感打架。
  bool _drivingPage = false;

  PageController get controller => widget.controller;
  List<(IconData, String)> get items => widget.items;

  @override
  void initState() {
    super.initState();
    _committedIndex = controller.initialPage;
    _visualPage = _committedIndex.toDouble();
    // 外部程序化切页（点了待办提醒的通知 → 跳到待办页）不经过这里的手势处理，
    // 所以还要听控制器：不听的话页面已经翻过去了、底部高亮还停在原来那一格。
    controller.addListener(_syncFromController);
  }

  @override
  void dispose() {
    controller.removeListener(_syncFromController);
    super.dispose();
  }

  /// 页面被外部改了就跟着对齐高亮。自己驱动的动画不上报（见 [_drivingPage]）。
  void _syncFromController() {
    if (_drivingPage || !controller.hasClients) return;
    final page = controller.page;
    if (page == null) return;
    final i = page.round();
    if (i == _committedIndex && (page - _visualPage).abs() < 0.001) return;
    setState(() {
      _committedIndex = i;
      _visualPage = page;
      _previewIndex = null;
    });
  }

  int _indexForDx(double dx, double itemW) {
    var i = (dx / itemW).floor();
    if (i < 0) i = 0;
    if (i > items.length - 1) i = items.length - 1;
    return i;
  }

  double _clampPage(double p) {
    if (p < 0) p = 0;
    if (p > items.length - 1) p = (items.length - 1).toDouble();
    return p;
  }

  int _nearestIndex(double p) {
    var i = p.round();
    if (i < 0) i = 0;
    if (i > items.length - 1) i = items.length - 1;
    return i;
  }

  // 点按落下：吸附到手指所在的功能区（整格）
  void _press(double dx, double itemW) {
    final i = _indexForDx(dx, itemW);
    setState(() {
      _pressed = true;
      _previewIndex = i;
      _visualPage = i.toDouble();
    });
  }

  // 拖动开始：记录抓取偏移，切换到连续跟手（不跳）
  void _dragStart(double dx, double itemW) {
    _grabOffset = dx / itemW - _visualPage;
    _dragUpdate(dx, itemW);
  }

  // 拖动中：1:1 跟手（连续小数位置），高亮跟随最近功能区
  void _dragUpdate(double dx, double itemW) {
    final p = _clampPage(dx / itemW - _grabOffset);
    setState(() {
      _pressed = true;
      _dragging = true;
      _previewIndex = _nearestIndex(p);
      _visualPage = p;
    });
  }

  // 松手：吸附到最近功能区并切换页面
  void _release() {
    final target = _nearestIndex(_visualPage);
    setState(() {
      _pressed = false;
      _dragging = false;
      _previewIndex = null;
      _committedIndex = target;
      _visualPage = target.toDouble();
    });
    if (controller.hasClients) {
      _drivingPage = true;
      controller
          .animateToPage(
        target,
        duration: AppTokens.durMed,
        curve: Curves.easeOutCubic,
      )
          .whenComplete(() => _drivingPage = false);
    }
  }

  // 取消：仅当真正处于拖动中才回退（点按结束触发的 onCancel 不回退）
  void _cancel() {
    if (!_dragging) return;
    setState(() {
      _pressed = false;
      _dragging = false;
      _previewIndex = null;
      _visualPage = _committedIndex.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isShort = AppLayout.of(context).isShort;
    final capsuleH = isShort ? _capsuleHeightShort : _capsuleHeight;
    final outerPad = isShort ? _outerPadShort : _outerPad;
    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = AppTokens.navInactiveForeground(context, isDark: isDark);
    final fg = AppTokens.navForeground(isDark, activeColor); // 滑块上选中项前景
    final selectedIndex = _previewIndex ?? _committedIndex;

    // 胶囊本体：按下轻微放大，松手弹簧回弹
    return QScale(
      pressed: _pressed,
      scale: AppTokens.pillGrow,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: outerPad),
        child: GlassRim(
          radius: capsuleH / 2,
          isDark: isDark,
          // 底栏是小控件，同一圈宽度在这里相对更显眼，单收一档。
          compact: true,
          // 「光跟随滑块」：光源位置 + 轨道几何，交给 painter 按实际尺寸换算。
          // 1.22 与下面那张 AnimatedScale 的按下缩放是同一个值（本仓既有的字面量）。
          sliderIndex: _visualPage + 0.5,
          tabCount: items.length,
          trackPad: _innerPad,
          sliderScale: _pressed ? 1.22 : 1.0,
          // 探针：透镜凸出胶囊、本体由 GlassRim 画在胶囊之下（见那边的说明）。
          // 凸出量 0 = 不凸，等于原来那个躺在胶囊里的滑块。
          lensFill: activeColor,
          lensProtrude: AppTokens.navLensProtrude,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(capsuleH / 2),
            child: GlassBlur(
              sigma: AppTokens.blurPanel,
              child: Container(
                height: capsuleH,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(capsuleH / 2),
                  border: Border.all(color: AppTokens.navBorder(isDark)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: AppTokens.navFill(isDark),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(_innerPad),
                  child: LayoutBuilder(
                    builder: (context, c) {
                    final itemW = c.maxWidth / items.length;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _press(d.localPosition.dx, itemW),
                      onTapUp: (_) => _release(),
                      onTapCancel: () {},
                      onHorizontalDragStart: (d) =>
                          _dragStart(d.localPosition.dx, itemW),
                      onHorizontalDragUpdate: (d) =>
                          _dragUpdate(d.localPosition.dx, itemW),
                      onHorizontalDragEnd: (_) => _release(),
                      onHorizontalDragCancel: _cancel,
                      child: Stack(
                        children: [
                          // 滑块：平滑吸附到最近功能区，按下放大、松手弹簧回弹
                          AnimatedPositioned(
                            key: const Key('nav-highlight'),
                            duration: _dragging
                                ? Duration.zero
                                : AppTokens.durFast,
                            curve: Curves.easeOutCubic,
                            left: _visualPage * itemW,
                            top: 0,
                            bottom: 0,
                            width: itemW,
                            child: AnimatedScale(
                              scale: _pressed ? 1.22 : 1.0,
                              duration: AppTokens.durMed,
                              curve: Curves.easeOutBack,
                              child: Container(
                                // 探针下把外观全摘掉 —— 那一档的滑块由 GlassRim 画在
                                // 胶囊**之下**、并凸出胶囊之外（见那边的说明）。
                                // 用「摘装饰」而不是「不渲染」：探测脚本靠
                                // `nav-highlight` 这个 key 找它的位置来起手拖动。
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(AppTokens.radiusL),
                                  gradient: liquidGlassActive.value
                                      ? null
                                      : LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: AppTokens
                                              .accentGradient(activeColor)
                                              .colors,
                                        ),
                                  border: liquidGlassActive.value
                                      ? null
                                      : Border.all(
                                          color: Colors.white.withValues(
                                              alpha: isDark ? 0.28 : 0.85),
                                        ),
                                  boxShadow: liquidGlassActive.value
                                      ? null
                                      : <BoxShadow>[
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.12),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: List.generate(items.length, (i) {
                              final selected = i == selectedIndex;
                              return Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // 导航项图标：常规态归 iconLg（规格 §3.6，出图对比：
                                    // 24 在 64dp 胶囊里站得住、20 偏小）。矮屏 52dp
                                    // 胶囊的竖向预算更小，回落到 iconMd —— 这是原设计
                                    // （`isShort ? 20 : 22`）「矮屏用小一号图标」的忠实
                                    // 翻译，属同一角色按布局档位的个别变化：不新增令牌，
                                    // 也不违背「导航项归 iconLg」。
                                    AppIcon(
                                      items[i].$1,
                                      size: isShort
                                          ? AppTokens.iconMd
                                          : AppTokens.iconLg,
                                      color: selected ? fg : inactiveColor,
                                    ),
                                    const SizedBox(height: AppTokens.gapHair),
                                    Text(
                                      items[i].$2,
                                      // 迁移前的基线字号是 10（现为 tinyLabel 11/w400）；
                                      // 未选中 w500、选中 w700，两个分支都由这里显式给字重，按规格走 copyWith。
                                      style: AppTokens.tinyLabel.copyWith(
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: selected ? fg : inactiveColor,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }
}
