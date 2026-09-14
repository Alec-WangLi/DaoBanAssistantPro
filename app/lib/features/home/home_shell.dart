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
import '../../state/app_settings.dart';
import '../alarm/alarm_ringing_screen.dart';
import '../alarm/alarm_screen.dart';
import '../alarm/alarm_service.dart';
import '../calendar/calendar_screen.dart';
import '../profile/app_dialogs.dart';
import '../profile/profile_screen.dart';
import '../schedule/schedule_screen.dart';

/// 底部导航壳：悬浮液态玻璃胶囊（点击切整数 tab，拖拽松手停在手指位置）。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
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
    });
    AlarmService.ringingAlarm.addListener(_onRingingChanged);
    AlarmService.openTodoRequested.addListener(_onTodoRequested);
  }

  /// 首次使用弹「使用帮助」；每次更新后弹「版本更新」简介。
  Future<void> _maybeShowLaunchDialogs() async {
    final sp = await SharedPreferences.getInstance();
    final onboarded = sp.getBool('onboarded') ?? false;
    if (!onboarded) {
      await sp.setBool('onboarded', true);
      await sp.setString('lastSeenVersion', appVersion);
      if (mounted) showUsageGuideDialog(context);
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
    AlarmService.ringingAlarm.removeListener(_onRingingChanged);
    AlarmService.openTodoRequested.removeListener(_onTodoRequested);
    _controller.dispose();
    super.dispose();
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
    final sched = ref.read(activeScheduleProvider).valueOrNull?.toDomain();
    final alarms = ref.read(customAlarmsProvider).valueOrNull;
    // 待办也要等流到齐再排，理由同前两个：`activeScheduleProvider` 会先
    // `seedIfEmpty`，这几个流非空就说明首启播种已经完成、库可以读了。
    final events = ref.read(eventsProvider).valueOrNull;
    if (sched == null || alarms == null || events == null) return;
    _startupRescheduled = true;
    final overrides =
        await ref.read(appRepositoryProvider).listShiftAlarmOverrides();
    AlarmService.reschedule(sched, alarms, overrides: overrides, events: events);
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
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(AppTokens.radiusL),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: AppTokens.accentGradient(activeColor)
                                      .colors,
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(
                                      alpha: isDark ? 0.28 : 0.85),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
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
    );
  }
}
