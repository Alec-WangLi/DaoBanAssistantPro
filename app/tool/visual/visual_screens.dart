// app/tool/visual/visual_screens.dart
//
// 「要渲染/审计哪些界面、各出哪些变体」只有一份定义，出图与对比度审计共用。
// 两边各写一份清单的话，迟早会有一边漏掉某屏，而漏掉是不会报错的。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_pickers.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/alarm/alarm_ringing_screen.dart';
import 'package:shiftassistantpro/features/alarm/alarm_screen.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/features/calendar/schedule_editor_screen.dart';
import 'package:shiftassistantpro/features/calendar/schedule_management_screen.dart';
import 'package:shiftassistantpro/features/calendar/shift_color_picker.dart';
import 'package:shiftassistantpro/features/calendar/shift_override_picker.dart';
import 'package:shiftassistantpro/features/calendar/shift_template_picker_screen.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';
import 'package:shiftassistantpro/features/profile/app_dialogs.dart';
import 'package:shiftassistantpro/features/profile/help_center_screen.dart';
import 'package:shiftassistantpro/features/profile/help_faq_screen.dart';
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

/// 某些屏需要额外的 prefs。用一张**按 slug 查的小表**，而不是往 [VisualScreen]
/// 记录里加字段 —— 只有两屏要它，为它去改三十条记录不划算。
///
/// 液态档那两屏必须走 prefs（而不是只调 `useLiquidGlassTier()`）：屏幕一
/// `ref.watch(appSettingsProvider)` 就会建 notifier → `_load()` 读 prefs →
/// **把档位标志覆盖回去**。这条坑真踩过 —— v0.10.1 收口时那四张「液态档」图
/// 与各自的标准档**逐字节相同**，等于这一档从没被渲染过。
Map<String, Object> screenExtraPrefs(String slug) => switch (slug) {
      '36_home_shell_liquid' ||
      '37_profile_liquid' ||
      '38_alarm_liquid' ||
      '39_todos_liquid' ||
      '47_ringing_liquid' ||
      '48_calendar_lens' =>
        const <String, Object>{'liquidGlass': true},
      _ => const <String, Object>{},
    };

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
    // **新加的那几颗色落到日历格子上**（v0.11.6）。单测只量得出「描边对卡底的
    // 对比度」，量不出「一整张日历排在一起好不好认」—— 那件事只有出图看得见。
    slug: '56_calendar_new_colors',
    title: '日历 · 新配色',
    build: (db) async {
      await makeNewPaletteShiftCurrent(db);
      return const CalendarScreen();
    },
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
    // 响铃页的**液态档**（v0.10.13）：那枚「上滑关闭」从手搓的白圆钮换成了真的玻璃药丸。
    // 单开一屏的理由与 `36_home_shell_liquid` 同一套 —— 液态档**必须走 prefs** 才拍得到，
    // 而这一屏的形状（凸出轨道、折边、竖着走的头大尾轻）正是这一轮改的东西。
    slug: '47_ringing_liquid',
    title: '响铃 · 液态玻璃',
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
    title: '排班编辑器 · 闹钟到上限（$maxAlarmsPerShift 个）',
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
    // 三档落点在编辑页的读法：**前一天 / 次日 / 不标**三种同屏。v0.11.1 新加的
    // 界面状态，令牌守门看不出「那一行会不会被日前缀挤掉」——只有出图能看。
    slug: '53_editor_alarm_tri_tier',
    title: '排班编辑器 · 闹钟三档落点（前一天 / 当天 / 次日）',
    build: (db) async {
      await makeTriTierAlarmShowcase(db);
      return ScheduleEditorScreen(scheduleId: await currentScheduleId(db));
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
    // 《使用帮助》自 v0.11.17 起是**整页**（从前是弹窗）：一段整体简介 + 九条
    // 功能简介 + 一个进第二层的入口。它是全 app 最长的一屏之一，窄屏上滚起来
    // 才对 —— 弹窗那个形态早该换了。
    slug: '18_help_center',
    title: '使用帮助',
    build: (db) async => const HelpCenterScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    // 第二层「遇到问题怎么解决」：31 条按用户的诉求排。
    //
    // 这一屏的风险全在长文案上 —— 答案句子比第一级那九条任何一句都长，
    // 窄屏 + 大字号下会不会被吃掉、英文折行后问题与答案还分不分得开，
    // 单测只量得出「两个 Text 的 top 不同」，看不出「读起来乱不乱」。
    slug: '59_help_faq',
    title: '使用帮助 · 遇到问题',
    build: (db) async => const HelpFaqScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    // **版本更新**（更新日志）。它是全 app 内容最长的弹窗（十条版本说明），
    // 也一直是「动作行压在正文上」那条毛病的**最坏样本** —— 而它此前
    // **从没进过屏单**：2026-10-01 用户报「它底下有个类似蒙版的东西挡住了正文」，
    // 单测只看得出几何，看不出「正文被齐刷刷切断」有多难看。这一条补上那只眼睛。
    slug: '34_app_info',
    title: '版本更新（更新日志）',
    build: (db) async => const _DialogHost(showChangelogDialog),
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
  (
    // 时段弹层（「添加时段」/ 编辑某一段）。
    //
    // **此前没进过屏单** —— 所以「里面那三个标签比同一页打开它的那行还小一档」
    // 一路没人看见，直到用户 2026-10-01 说「字体是不是好像有点小了」。这条按
    // 「新界面一律补进屏单」那条规矩补上：弹层是命令式的、没有可渲染 widget，
    // 得包一层薄壳把它弹出来。
    slug: '33_span_editor',
    title: '排班管理 · 时段弹层',
    build: (db) async => const _SpanEditorHost(),
    needsOnboardingPrefs: false,
  ),
  (
    // 液态玻璃档（「我的 → 外观」里那颗开关，默认关）。要拍它是因为这一档的观感
    // 从来没在**正式代码路径**下被看过（见 `screenExtraPrefs` 的说明）。
    // 它同时也是对比度审计的覆盖对象 —— 那正是这条当初漏掉的地方。
    slug: '36_home_shell_liquid',
    title: '主壳 · 液态玻璃',
    build: (db) async => const HomeShell(),
    needsOnboardingPrefs: true,
  ),
  (
    slug: '37_profile_liquid',
    title: '我的 · 液态玻璃',
    build: (db) async => const ProfileScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    // 列表行是 `enableBlur: false` 的**平填充**，不是玻璃 —— 液态档**不该**给它们
    // 加边光。上一版加了，闹钟页 / 待办页于是变成「一排描了边的框」（用户
    // 2026-10-01 反馈的「边缘不知道是什么情况，有点丑」）。这两屏是那条判据的
    // 常驻护栏。
    slug: '38_alarm_liquid',
    title: '闹钟 · 液态玻璃',
    build: (db) async => const AlarmScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    slug: '39_todos_liquid',
    title: '待办 · 液态玻璃',
    build: (db) async => const ScheduleScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    // 日历那枚**选中块**在液态档下的样子（v0.10.15）。加了它之后，「液态档里有透镜」
    // 这件事就不再只属于底栏了 —— `glass_tier_test` 里那条原来拿全页数的用例因此
    // 改成了限定在 `glass-nav-bar` 里（红过一次，改的就是那里）。
    //
    // 静止这一屏只是**基线**：这一轮真正要看的是按住与拖动中那两档，
    // 它们在 `render_screens_test.dart` 里（要真手势，进不了这份屏单）。
    slug: '48_calendar_lens',
    title: '日历 · 液态档选中块',
    build: (db) async => const CalendarScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    // 按月排班（v0.11.15）：编辑器那一屏拍的是**按月那一支**——顶上的二选一分段器、
    // 「每月第 N 天起」的段列表、以及下面几张卡。段列表在班次卡之下，所以它同时
    // 进了 `visualScrollDown`（不滚只看得到预览条与名称卡）。
    slug: '57_editor_monthly',
    title: '排班编辑器 · 按月',
    build: (db) async {
      await makeMonthlyScheduleCurrent(db);
      return ScheduleEditorScreen(scheduleId: await currentScheduleId(db));
    },
    needsOnboardingPrefs: false,
  ),
  (
    // 选择页最底下那两张「从零开始」的卡（按月排班 / 我自己排）。它们在 20 来个
    // 模板卡之后，首屏拍不到 —— 所以这一屏也是靠 `visualScrollDown` 滚到底。
    slug: '58_template_picker_monthly',
    title: '倒班方式选择 · 按月排班',
    build: (db) async => const ShiftTemplatePickerScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    // 选项弹层（`showGlassOptionPicker`）——**一个件带六个调用点**：贪睡时长、
    // 待办提醒档位（新建 / 编辑各一处）、编辑器两处、待办两处，所以它的头部一改
    // 六处一起变。而它此前**从没有过可看的图**：命令式弹层（静止帧拍不到），
    // 六个调用点又都藏在「点某一行下拉」之后。按「新界面一律补进屏单」那条规矩
    // 补上这只眼睛（v0.12.0 统一了它内部那份头部）。
    slug: '60_option_picker',
    title: '选项弹层（贪睡时长那种）',
    build: (db) async => const _OptionPickerHost(),
    needsOnboardingPrefs: false,
  ),
  (
    // 取色层（`showShiftColorPicker`）。
    //
    // `render_screens_test.dart` 里有**两条手写的** `visualTest` 渲它（浅色 / 深色，
    // 点班次行末那颗色点弹出来、**背后是编辑器现场**），但它们是临时用例、**不在本
    // 清单里** —— 而**对比度审计只扫这份清单**。于是取色层**至今没进过对比度审计**，
    // 正是 AGENTS.md 里 v0.11.7 记下的那句「取色层那两屏没进对比度审计的屏单」。
    // 这一条把它并进共享清单（背后是空棚架，形态与手写那两条不同 —— 那两条要留着，
    // 它们带 `beforeCapture` 交互，替代不了）。
    //
    // ⚠️ **slug 不能取 `57_shift_color_picker`。** 共享清单出的文件名是
    // `'${slug}_${variant.suffix}'`，而手写那条正好也会写出 `57_shift_color_picker_dark.png`
    // —— 两条同屏但现场不同，谁后跑谁覆盖，图会随机变成另一个样子。所以另起一号。
    slug: '61_shift_color_picker',
    title: '取色层（对比度审计）',
    build: (db) async => const _ColorPickerHost(),
    needsOnboardingPrefs: false,
  ),
];

/// 「添加时段」弹层的宿主 —— **只为工装存在，不进 `lib/`**。
///
/// 与 `_DialogHost` 同一个套路，差别只在它是 `ConsumerStatefulWidget`：
/// `showSpanEditor` 要一个 `WidgetRef`。
class _SpanEditorHost extends ConsumerStatefulWidget {
  const _SpanEditorHost();

  @override
  ConsumerState<_SpanEditorHost> createState() => _SpanEditorHostState();
}

class _SpanEditorHostState extends ConsumerState<_SpanEditorHost> {
  @override
  void initState() {
    super.initState();
    // 必须等首帧：`showDialog` 要用 `context` 的 `Overlay`。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showSpanEditor(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}

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

/// 「选项弹层」的宿主 —— **只为工装存在，不进 `lib/`**。
///
/// `showGlassOptionPicker` 与别处一样是命令式的：调一下就弹、返回一个 Future，
/// 没有可以直接放进 `home:` 的 widget。这一层薄壳在首帧后把它弹出来，`build` 只交
/// 一个空 `Scaffold` 让弹层浮在它上面（与 `_OverridePickerHost` 同一套路）。
/// 取贪睡时长那一档当样本：标题 + 六个选项 + 当前项打勾，正是那六个调用点的形态。
class _OptionPickerHost extends StatefulWidget {
  const _OptionPickerHost();

  @override
  State<_OptionPickerHost> createState() => _OptionPickerHostState();
}

class _OptionPickerHostState extends State<_OptionPickerHost> {
  @override
  void initState() {
    super.initState();
    // 必须等首帧：`showModalBottomSheet` 要用 `context` 的 `Overlay`，而
    // `initState` 里 context 还没挂进树。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showGlassOptionPicker<int>(
        context,
        title: L10n.snoozeDuration,
        options: L10n.snoozeOptions,
        labelOf: L10n.snoozeOptionLabel,
        selected: L10n.snoozeOptions[1],
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}

/// 取色层的宿主 —— **只为工装存在，不进 `lib/`**。
///
/// 与 `_OptionPickerHost` 同一套路：`showShiftColorPicker` 是命令式的，没有可以
/// 直接放进 `home:` 的 widget。首帧后把它弹出来，`build` 只交一个空 `Scaffold`。
class _ColorPickerHost extends StatefulWidget {
  const _ColorPickerHost();

  @override
  State<_ColorPickerHost> createState() => _ColorPickerHostState();
}

class _ColorPickerHostState extends State<_ColorPickerHost> {
  @override
  void initState() {
    super.initState();
    // 必须等首帧：`showModalBottomSheet` 要用 `context` 的 `Overlay`，而
    // `initState` 里 context 还没挂进树。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showShiftColorPicker(context, current: 0xFF4C8DFF, sampleLabel: '早');
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
  // 《使用帮助》整页：九条功能简介之后才是那颗进第二层的入口，而首屏只露得出
  // 前三条。**这一条不加的话，本轮新加的那个入口在任何一张图上都看不到。**
  '18_help_center': 3000,
  '07_profile': 620, // 权限卡 + 关于
  '06_alarm': 360, // 自定义闹钟那一段
  '03_management': 280, // 排班列表
  '13_editor_midnight': 900, // 零点班那张班次卡（响铃时间块与它的说明在这下面）
  // 闹钟列表在那张班次卡更下面：滚过头会钳到页尾（周期表那段），所以只滚到
  // 露得出「添加闹钟」/到上限那行说明就够 —— 三个屏各自差一行多点的高度。
  '20_editor_alarm_one': 420,
  '21_editor_alarm_three': 520,
  '22_editor_alarm_max': 620,
  // 三档那张的「前一天」那一档在**第二个班次卡**（夜班）上，首屏只露得出中班
  // 那张卡 —— 不滚就看不到三档里的第一档。
  '53_editor_alarm_tri_tier': 760,
  // 撞班提示挂在「周期设置」卡的末尾，10 行周期表的下面；给足量让它滚到底，
  // 靠到底后的钳位保证那张卡的下半段（提示 + 均分按钮）在画面里。
  '15_editor_crew_clash': 2400,
  // 按月那一支：班次卡下面才是段列表（顶上两张卡占掉一屏），再往下是班组卡。
  '57_editor_monthly': 1500,
  // 选择页那两张「从零开始」的卡在 20 来个模板之后，滚到底才看得到。
  '58_template_picker_monthly': 4000,
};
