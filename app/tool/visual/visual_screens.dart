// app/tool/visual/visual_screens.dart
//
// 「要渲染/审计哪些界面、各出哪些变体」只有一份定义，出图与对比度审计共用。
// 两边各写一份清单的话，迟早会有一边漏掉某屏，而漏掉是不会报错的。

import 'package:flutter/material.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/alarm/alarm_ringing_screen.dart';
import 'package:shiftassistantpro/features/alarm/alarm_screen.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/features/calendar/schedule_editor_screen.dart';
import 'package:shiftassistantpro/features/calendar/schedule_management_screen.dart';
import 'package:shiftassistantpro/features/calendar/shift_override_picker.dart';
import 'package:shiftassistantpro/features/calendar/shift_template_picker_screen.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';
import 'package:shiftassistantpro/features/profile/app_dialogs.dart';
import 'package:shiftassistantpro/features/profile/profile_screen.dart';
import 'package:shiftassistantpro/features/schedule/recurring_panel.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';

import 'visual_harness.dart';

/// 一屏的渲染参数。`build` 是异步的，因为编辑器要先把 id 从库里查出来。
typedef VisualScreen = ({
  String slug,
  String title,
  Future<Widget> Function(AppDatabase db) build,
  bool needsOnboardingPrefs,
});

final List<VisualScreen> visualScreens = [
  (
    slug: '00_home_shell',
    title: '主壳',
    build: (db) async => const HomeShell(),
    // 首启弹「使用帮助」、版本变了弹「更新简介」——不置这两个标记，
    // 弹窗会把整个界面盖住，拍到的就不是壳了。
    needsOnboardingPrefs: true,
  ),
  (
    slug: '01_calendar',
    title: '日历',
    build: (db) async => const CalendarScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    slug: '02_editor',
    title: '排班编辑器',
    build: (db) async =>
        ScheduleEditorScreen(scheduleId: await currentScheduleId(db)),
    needsOnboardingPrefs: false,
  ),
  (
    slug: '03_management',
    title: '排班管理',
    build: (db) async => const ScheduleManagementScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    slug: '04_template_picker',
    title: '倒班方式选择',
    build: (db) async => const ShiftTemplatePickerScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    slug: '05_todos',
    title: '待办事项',
    build: (db) async => const ScheduleScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    // 「今天有一条重复待办」的待办页：循环标记、标题旁的「重复待办」入口、
    // 以及已完成的历史那一条（带删除线）都在这屏。
    slug: '24_todos_recurring',
    title: '待办 · 含重复项',
    build: (db) async {
      await seedRecurringTodo(db);
      return const ScheduleScreen();
    },
    needsOnboardingPrefs: false,
  ),
  (
    // 管理面板是**弹层**（命令式、没有可渲染的 widget），要一层薄壳把它弹出来
    // —— 与「开始使用」「使用帮助」那两张同一套路。
    slug: '25_recurring_panel',
    title: '重复待办 · 管理面板',
    build: (db) async {
      await seedRecurringTodo(db);
      return const _DialogHost(showRecurringTodosDialog);
    },
    needsOnboardingPrefs: false,
  ),
  (
    slug: '06_alarm',
    title: '闹钟',
    build: (db) async => const AlarmScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    slug: '07_profile',
    title: '我的',
    build: (db) async => const ProfileScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    // 响铃屏是推在栈顶的全屏页，平时只有闹钟真响才看得到 —— 正因如此，
    // 它的布局（尤其是底部「上滑关闭」滑块）此前没有任何可重复的看图手段。
    slug: '08_ringing',
    title: '响铃',
    build: (db) async => const AlarmRingingScreen(label: '早班'),
    needsOnboardingPrefs: false,
  ),
  (
    // 「今天带一条按天覆盖」的日历：格子上该有 4dp 小圆点、信息卡班次行该多一颗
    // 「已调整」胶囊。这两处 v0.8.1 出过设计语言偏差（裸文字 vs 胶囊），三道评审
    // 都没拦住 —— 根因就是它们**从没进过屏单，没人真正看过**。这一条补上那个眼睛。
    slug: '10_calendar_adjusted',
    title: '日历 · 已调整',
    build: (db) async {
      await seedTodayOverride(db);
      return const CalendarScreen();
    },
    needsOnboardingPrefs: false,
  ),
  (
    // 「调整班次」是**弹层**不是页面：`showShiftOverridePicker` 命令式弹出、没有
    // 可渲染的 widget，所以要一层薄壳把它弹出来（见 `_OverridePickerHost`）。
    slug: '11_override_picker',
    title: '调整班次',
    build: (db) async {
      await seedTodayOverride(db);
      final schedule = await AppRepository(db).getActiveSchedule();
      if (schedule == null) {
        throw StateError('工装种子库里没有当前方案，「调整班次」弹层无从渲染。');
      }
      final today = dateOnly(DateTime.now());
      // 判据照抄 `calendar_screen.dart` 的 `adjustDays`（单日区间那一支）：
      // 这一天被覆盖过 → 命中的那行打勾，底部多一条「恢复轮转」。
      final hasOverride =
          schedule.dayOverrides.containsKey(dayNumber(today));
      return _OverridePickerHost(
        schedule: schedule,
        from: today,
        to: today,
        currentClass: hasOverride ? schedule.shiftOn(today) : null,
        canRestore: hasOverride,
      );
    },
    needsOnboardingPrefs: false,
  ),
  (
    // 「响铃排在上班前一天」的三处标记（班次编辑的钟点块、闹钟列表行、日历
    // 信息卡）只在零点班这类班次上画得出来，而种子库里的夜班是 20:30 上班
    // （当天）—— 不换一套方案，这三处改了也拍不到。见 `makeMidnightShiftCurrent`。
    slug: '12_calendar_midnight',
    title: '日历 · 零点班（响铃在前一天）',
    build: (db) async {
      await makeMidnightShiftCurrent(db);
      return const CalendarScreen();
    },
    needsOnboardingPrefs: false,
  ),
  (
    slug: '13_editor_midnight',
    title: '排班编辑器 · 零点班',
    build: (db) async {
      await makeMidnightShiftCurrent(db);
      return ScheduleEditorScreen(scheduleId: await currentScheduleId(db));
    },
    needsOnboardingPrefs: false,
  ),
  (
    slug: '14_alarm_midnight',
    title: '闹钟 · 零点班',
    build: (db) async {
      await makeMidnightShiftCurrent(db);
      return const AlarmScreen();
    },
    needsOnboardingPrefs: false,
  ),
  (
    // 撞班提示与「按周期长度均分各组起始日」只在这个状态下画得出来
    // （周期 10 天、各班组仍按 1 天错开），见 `makeCrewClashCurrent`。
    slug: '15_editor_crew_clash',
    title: '排班编辑器 · 班组撞班',
    build: (db) async {
      await makeCrewClashCurrent(db);
      return ScheduleEditorScreen(scheduleId: await currentScheduleId(db));
    },
    needsOnboardingPrefs: false,
  ),
  (
    // 「我的模板」那一组只在库里有模板时才出现（首启的用户看不到空分组），
    // 所以要预置两条才拍得到：分组标题旁的「管理」、卡片上现算出来的
    // 「N 天一轮 · N 个班组」副标题。见 `seedMyTemplates`。
    slug: '16_template_picker_mine',
    title: '倒班方式选择 · 我的模板',
    build: (db) async {
      await seedMyTemplates(db);
      return const ShiftTemplatePickerScreen();
    },
    needsOnboardingPrefs: false,
  ),
  (
    slug: '20_editor_alarm_one',
    title: '排班编辑器 · 一个闹钟',
    build: (db) async {
      await makeAlarmShowcase(db, count: 1);
      return ScheduleEditorScreen(scheduleId: await currentScheduleId(db));
    },
    needsOnboardingPrefs: false,
  ),
  (
    slug: '21_editor_alarm_three',
    title: '排班编辑器 · 三个闹钟（含命名）',
    build: (db) async {
      await makeAlarmShowcase(db, count: 3);
      return ScheduleEditorScreen(scheduleId: await currentScheduleId(db));
    },
    needsOnboardingPrefs: false,
  ),
  (
    slug: '22_editor_alarm_max',
    title: '排班编辑器 · 闹钟到上限（6 个）',
    build: (db) async {
      await makeAlarmShowcase(db, count: maxAlarmsPerShift);
      return ScheduleEditorScreen(scheduleId: await currentScheduleId(db));
    },
    needsOnboardingPrefs: false,
  ),
  (
    slug: '23_alarm_two_per_shift',
    title: '闹钟 · 一个班次两个闹钟（含「前一天」）',
    build: (db) async {
      await makeAlarmShowcase(db, count: 2, nightShift: true);
      return const AlarmScreen();
    },
    needsOnboardingPrefs: false,
  ),
  (
    // 首启弹的那份（三条），与「我的 → 使用帮助」那份完整说明是**两套内容** ——
    // 2026-09-23 之前首启弹的是后者，等于把说明书当欢迎页。
    slug: '17_getting_started',
    title: '开始使用（首启）',
    build: (db) async => const _DialogHost(showGettingStartedDialog),
    needsOnboardingPrefs: false,
  ),
  (
    // 完整说明。正文从「一整段」改成了「短句 + 圆点」，是最容易在版式上跑偏的
    // 一处 —— 圆点的对齐、英文条目折行后的缩进，只有看图才知道对不对。
    slug: '18_usage_guide',
    title: '使用帮助',
    build: (db) async => const _DialogHost(showUsageGuideDialog),
    needsOnboardingPrefs: false,
  ),
  (
    // 多排班表按日期衔接：种子给第二套方案一个时段、边界落在**本月 15 日** ——
    // 于是同一张图上左半月的格子画第一套、右半月的画第二套。这一屏是检验
    // 「按天解析」的唯一一只眼睛（单测只看得到断言，看不到「两半张得一样」）。
    slug: '27_calendar_chained',
    title: '日历 · 排班衔接',
    build: (db) async {
      await seedScheduleChain(db);
      return const CalendarScreen();
    },
    needsOnboardingPrefs: false,
  ),
  (
    // 排班时段那一节：**其余时间 + 两段**，三种日期说法各出现一次
    //（「其余时间」/「9月15日 ～ 9月30日」/「10月1日 起」），下面接现有的排班表
    // 列表 —— 一页看完「有哪些班表 + 它们怎么排」，正是这一节并进管理页的理由。
    slug: '30_management_timeline',
    title: '排班管理 · 排班时段',
    build: (db) async {
      await seedScheduleChain(db);
      return const ScheduleManagementScreen();
    },
    needsOnboardingPrefs: false,
  ),
  (
    // 整月一天班都没有（其余时间设成「无」、又没有段）—— 网格上叠一句指路。
    // 这一屏要看的是：那句指路盖在网格上居中、不压顶栏与信息卡、两层文字不打
    // 架，而且网格的日期与农历仍然看得见（它只是叠了一层说明，不是替换）。
    slug: '31_calendar_no_schedule',
    title: '日历 · 这段时间没有排班',
    build: (db) async {
      await seedNoScheduleAtAll(db);
      return const CalendarScreen();
    },
    needsOnboardingPrefs: false,
  ),
  (
    // 只有一套「法定班次」（跟随法定节假日）：整月每天都画得出「上班 / 休息」，
    // **不盖指路**（指路只留给真的没有班表的那种）。
    //
    // 这一屏要看的是：那两个字压在 40dp 的格子里放不放得下、上班与休息的颜色
    // 分不分得开、法定节假日那几天红色标记还看不看得见、以及整月一片「上班」
    // 会不会太吵。2026-09-30 用户反馈的那一整类问题（这种班表被当成「没有排班」）
    // 此前**没有任何一屏拍得出来**。
    slug: '32_calendar_blank_schedule',
    title: '日历 · 法定班次（跟随法定节假日）',
    build: (db) async {
      await seedBlankSchedule(db);
      return const CalendarScreen();
    },
    needsOnboardingPrefs: false,
  ),
];

/// 「调整班次」选择层的宿主 —— **只为工装存在，不进 `lib/`**。
///
/// `showShiftOverridePicker` 是命令式的：调一下就弹、返回一个 Future，没有可以
/// 直接放进 `home:` 的 widget。所以这层薄壳在首帧后把弹层弹出来，`build` 只交一个
/// 空的 `Scaffold` 让弹层浮在它上面。参数原样透传，判据的算法留在调用处（照
/// `adjustDays`），壳本身不做决定。
class _OverridePickerHost extends StatefulWidget {
  const _OverridePickerHost({
    required this.schedule,
    required this.from,
    required this.to,
    this.currentClass,
    this.canRestore = false,
  });

  final ShiftSchedule schedule;
  final DateTime from;
  final DateTime to;
  final ShiftClass? currentClass;
  final bool canRestore;

  @override
  State<_OverridePickerHost> createState() => _OverridePickerHostState();
}

class _OverridePickerHostState extends State<_OverridePickerHost> {
  @override
  void initState() {
    super.initState();
    // 必须等首帧：`showModalBottomSheet` 要用 `context` 的 `Overlay`，而
    // `initState` 里 context 还没挂进树。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showShiftOverridePicker(
        context,
        schedule: widget.schedule,
        from: widget.from,
        to: widget.to,
        currentClass: widget.currentClass,
        canRestore: widget.canRestore,
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}

/// 命令式弹窗的宿主 —— **只为工装存在，不进 `lib/`**。
///
/// 「开始使用」「使用帮助」都是 `showXxxDialog(context)` 这种命令式 API：调一下
/// 就弹、返回一个 Future，没有可以放进 `home:` 的 widget。这层薄壳在首帧后把它
/// 弹出来，`build` 只交一个空 `Scaffold` 让弹窗浮在上面（与 `_OverridePickerHost`
/// 同一套路）。
class _DialogHost extends StatefulWidget {
  const _DialogHost(this.show);

  final void Function(BuildContext context) show;

  @override
  State<_DialogHost> createState() => _DialogHostState();
}

class _DialogHostState extends State<_DialogHost> {
  @override
  void initState() {
    super.initState();
    // 必须等首帧：`showDialog` 要用 `context` 的 `Overlay`，而 `initState` 里
    // context 还没挂进树。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.show(context);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}

/// 每个界面要出的变体。
///
/// 英文那张不是凑数：文案漏翻、英文顶到边、日期格式在英文下串成
/// 「2026 9」这类问题，只有在英文界面上才看得见。
///
/// 横屏与小窗两张同样不是凑数：它们的尺寸正是用户反馈「几乎无法使用」的
/// 那两种形态 —— 工装过去只拍 420×900，所以那些缺陷一张图都拍不到。
///
/// 小窗的尺寸必须是**量出来的**，不能估。v0.6.4 在这里填了 360×360，
/// 而小米小窗在参考机（Redmi K90 Pro Max，1200×2608 @480dpi）上实际给
/// 应用的是 200×400 逻辑像素：
///
/// ```
/// adb shell dumpsys activity com.daoban.shiftassistantpro
///   → mCurrentConfig={… sw200dp w200dp h400dp 480dpi … mWindowingMode=freeform}
/// ```
///
/// 系统随后把它放大 1.43 倍显示，所以肉眼看不出它有这么小 —— 光看屏幕
/// 估尺寸必然估大（360 是 200 的 1.8 倍，足够把溢出全藏起来）。
final List<
    ({
      String suffix,
      String label,
      Brightness brightness,
      String language,
      Size size,
    })> visualVariants = [
  (
    suffix: 'light',
    label: '浅色',
    brightness: Brightness.light,
    language: 'zh',
    size: kVisualSize,
  ),
  (
    suffix: 'dark',
    label: '深色',
    brightness: Brightness.dark,
    language: 'zh',
    size: kVisualSize,
  ),
  (
    suffix: 'en',
    label: '英文',
    brightness: Brightness.light,
    language: 'en',
    size: kVisualSize,
  ),
  (
    suffix: 'landscape',
    label: '横屏 900×420',
    brightness: Brightness.light,
    language: 'zh',
    size: const Size(900, 420),
  ),
  (
    suffix: 'small',
    label: '小窗 200×400',
    brightness: Brightness.light,
    language: 'zh',
    size: const Size(200, 400),
  ),
];

/// 要额外出一张「向下滚动后」的屏：slug → 往下拖多少逻辑像素。
///
/// 此前工装只拍第一屏，**首屏之下的内容从来没被拍过**。代价很实：「我的」页的
/// 权限卡恰好卡在折线下方，于是那行名不副实的文案（「后台弹出界面」其实是
/// Android 的「显示悬浮窗」）活了三个版本没人看见 —— 图里压根没有它。
///
/// 只列**确实有下半屏内容**的屏：没列的屏拖了也是同一张图，白出一份；
/// 顺带逼着加新屏的人想一下「这屏下面还有东西吗」。
const Map<String, double> visualScrollDown = {
  '07_profile': 620, // 权限卡 + 关于
  '06_alarm': 360, // 自定义闹钟那一段
  '03_management': 280, // 排班列表
  '13_editor_midnight': 900, // 零点班那张班次卡（响铃时间块与它的说明在这下面）
  // 闹钟列表在那张班次卡更下面：滚过头会钳到页尾（周期表那段），所以只滚到
  // 露得出「添加闹钟」/到上限那行说明就够 —— 三个屏各自差一行多点的高度。
  '20_editor_alarm_one': 420,
  '21_editor_alarm_three': 520,
  '22_editor_alarm_max': 620,
  // 撞班提示挂在「周期设置」卡的末尾，10 行周期表的下面；给足量让它滚到底，
  // 靠到底后的钳位保证那张卡的下半段（提示 + 均分按钮）在画面里。
  '15_editor_crew_clash': 2400,
};
