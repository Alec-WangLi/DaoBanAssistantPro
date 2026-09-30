import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'glass_nav_bar.dart';

import '../../core/app_info.dart';
import '../../core/l10n.dart';
import '../../core/update_checker.dart';
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
      bottomNavigationBar: GlassNavBar(
        // 给工装用：按图标找 tab 时得能把它和页面里的同名图标区分开 —— 信息卡上
        // 那个「N 项待办」徽章用的就是 `event_note_outlined`，与「待办」tab 同款。
        key: const Key('glass-nav-bar'),
        controller: _controller,
        items: _items,
      ),
    );
  }
}
