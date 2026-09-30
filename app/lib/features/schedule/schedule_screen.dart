import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/layout.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_delete_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_pill.dart';
import '../../core/widgets/glass_segment.dart';
import '../../core/widgets/glass_switch.dart';
import '../../core/widgets/glass_weekday_picker.dart';
import '../../data/app_repository.dart';
import '../../domain/recurring_todo.dart';
import '../../domain/shift_rotation.dart';
import '../../state/app_settings.dart';
import '../alarm/alarm_service.dart';
import 'recurring_panel.dart';

/// 日程：最简事件（标题 + 日期 + 可选时间 + 可选提前提醒 + 完成勾选）。
///
/// 是 `StatefulWidget` 的原因只有一个：要挂 `WidgetsBindingObserver`，在**回到
/// 前台**时补跑一次重复待办的生成器（见 [_ScheduleScreenState.didChangeAppLifecycleState]）。
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 进页面就补一次（放在帧后：写库会触发 drift 流重发，等这一帧建完更稳）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _advanceRecurring());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // **回到前台要补跑一次**：App 一直没关、跨过午夜的情况下，列表是 drift 流、
    // 不写库就不会重发，界面上会一直挂着昨天的日期 —— 而用户只会觉得「今天这条
    // 待办没出现」。（与 `alarm_screen` 回到前台重建「今天」是同一个场景。）
    if (state == AppLifecycleState.resumed) _advanceRecurring();
  }

  /// 跑一遍重复待办的生成器，再重排提醒（改完「当前这一次」提醒也要跟着走）。
  Future<void> _advanceRecurring() async {
    final repo = ref.read(appRepositoryProvider);
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    await _rescheduleReminders(ref);
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsProvider);
    final events = eventsAsync.valueOrNull ?? const [];
    ref.watch(appSettingsProvider); // 语言切换时重建

    return Scaffold(
      body: SafeArea(
        child: CenteredContent(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  // `Expanded`（而不是 `Flexible`）把入口**推到最右边** —— 用户
                  // 2026-09-30 反馈「可以移到右上角，感觉这样美观一些」：原先它
                  // 紧贴在标题右边，看着像标题的一部分。标题此时拿到的是**有界宽**，
                  // 窄窗里照样省略号收尾（与 `Flexible` 同一层兜底）。
                  Expanded(
                    child: Text(
                      L10n.titleTodo,
                      style: AppTokens.pageTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  // 「重复待办」管理面板的入口。**实心主色胶囊** —— 与日历顶栏
                  // 那颗「今天」同一个件（`GlassPill`），因为两者承担的是同一类
                  // 角色：一个页面级的动作入口。
                  //
                  // **窄窗（< 360dp）只留图标**：那一档里标题加这四个字必然放不下，
                  // 而入口又不能藏（那是唯一的管理路径）—— 于是把**文字**收掉，
                  // 与「小窗里不显示时间副标题 / 不显示待办徽章」是同一条取舍。
                  GlassPill(
                    onTap: () => showRecurringTodosDialog(context),
                    accent: true,
                    // 比顶栏那颗矮一档：这一行旁边是页面标题，不是年月胶囊。
                    height: 36,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppIcon(
                          Icons.repeat,
                          size: AppTokens.iconMd,
                          color: Colors.white,
                        ),
                        if (!AppLayout.of(context).isNarrow) ...[
                          const SizedBox(width: 4),
                          Text(
                            L10n.recurring,
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
            ),
            Expanded(
              child: events.isEmpty
                  ? Center(
                      // 左右留白 + 居中换行：小窗（200 宽）里这一句话比屏还宽，
                      // 居中之后两头都被切掉 —— Text 的横向溢出不是 RenderFlex
                      // 溢出，工装的 failOnOverflow 抓不到，只能靠出图看。
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          L10n.noEvents,
                          textAlign: TextAlign.center,
                          style: AppTokens.rowSecondary
                              .copyWith(color: AppTokens.inkMuted(context)),
                        ),
                      ),
                    )
                  : ListView.builder(
                      // 底部留白走 `kFloatingActionInset`：这一页的「新建」按钮是
                      // **悬浮**在列表之上的，96 那一档下最后一行会被它压住
                      // （删除键点不到 —— 2026-10-01 用户反馈）。
                      padding: const EdgeInsets.fromLTRB(
                          16, 8, 16, kFloatingActionInset),
                      itemCount: events.length,
                      itemBuilder: (context, i) {
                        final e = events[i];
                        return _eventTile(context, ref, e);
                      },
                    ),
            ),
          ],
        ),
      )),
      floatingActionButtonLocation: const _AboveCapsuleFabLocation(),
      floatingActionButton: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.72),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _showAddDialog(context, ref),
            child: const AppIcon(Icons.add_outlined,
                color: Colors.white, size: AppTokens.iconLg),
          ),
        ),
      ),
    );
  }

  Widget _eventTile(BuildContext context, WidgetRef ref, ScheduleEvent e) {
    final subtitle = [
      L10n.monthDayWeekday(e.date),
      if (e.timeMinute != null) _fmt(e.timeMinute!),
      if (e.advanceRemindMinutes != null)
        L10n.remindOptionLabel(e.advanceRemindMinutes!),
    ].join(' · ');

    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GlassTile(
      enableBlur: false,
      // 卡片之间：分隔两条待办（两个板块），归节奏档。
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      onTap: () => showEditEventDialog(context, ref, e),
      child: Row(
        children: [
          GlassSwitch(
            value: e.isCompleted,
            onChanged: (v) async {
              // 这里**不**加 `Haptics.commit()`：勾选的载体是 `GlassSwitch`，
              // Task 4 已经让它在自己的 `onTap` 里发一次 `select()`（「选中变了」
              // 正是它的语义）。再加一次就是每拨一下震两下 —— 两下比一下信息量
              // **更少**，正是这套设计要消灭的噪音。spec §4.2 那张表原来点了这
              // 一行，已作废：**§4.1 覆盖过的控件不再进 §4.2 的表**。
              await ref.read(appRepositoryProvider).setEventCompleted(e, v);
              await _rescheduleReminders(ref);
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  style: AppTokens.titleStrong.copyWith(
                    color: e.isCompleted
                        ? AppTokens.inkFaint(context)
                        : onSurface,
                    decoration:
                        e.isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTokens.microText.copyWith(
                          color: e.isCompleted
                              ? AppTokens.inkFaint(context)
                              : AppTokens.inkMuted(context),
                        ),
                      ),
                    ),
                    // 重复项：一眼看出「这不是一次性待办」。已完成的不给 ——
                    // 那一条是历史，标着「它会再来」反而让人以为还没完。
                    if (e.seriesId != null && !e.isCompleted) ...[
                      const SizedBox(width: AppTokens.gapIconText),
                      AppIcon(Icons.repeat,
                          size: AppTokens.iconSm,
                          color: AppTokens.inkMuted(context)),
                    ],
                    // 开了联动闹钟的待办给个小铃铛：不用点进去就知道哪条会响。
                    // 已完成的不给 —— 它不会再响了。
                    if (e.alarmEnabled && !e.isCompleted) ...[
                      const SizedBox(width: AppTokens.gapIconText),
                      AppIcon(Icons.alarm_outlined,
                          size: AppTokens.iconSm,
                          color: AppTokens.inkMuted(context)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          GlassDeleteButton(
            // 列表行尾部用紧凑形态：完整形态是个 48pt 的红圆，一屏五行就是五个
            // 警报，盖过待办本身（组件注释里写明了这个分工）。
            compact: true,
            onPressed: () async {
              final repo = ref.read(appRepositoryProvider);
              final sid = e.seriesId;
              if (sid == null) {
                // 一次性待办：照旧直接删（一个字都不用问）。
                await repo.deleteEvent(e);
              } else {
                // 重复项要问：直接删掉的话，生成器下一次打开 App 又会把它补出来
                //（用户看到的是「删不掉」）；而直接删整个系列又会把「这周不做」
                // 变成「以后都不做了」。
                final choice = await _askDeleteRecurring(context, e.title);
                if (choice == null || !context.mounted) return;
                if (choice == _DeleteChoice.series) {
                  await repo.deleteRecurringTodo(sid);
                } else {
                  // 只跳过这一次：记下这次的日子，生成器在那天之前不再补
                  await repo.skipRecurringOccurrence(sid, e.date);
                  await repo.deleteEvent(e);
                }
              }
              await _rescheduleReminders(ref);
            },
          ),
        ],
      ),
    );
  }

  /// 待办增删改之后立刻重排提醒。
  ///
  /// **不重排的话要等到下次开 App 才排**，而那时候提醒时间早就过去了 ——
  /// 用户看到的就是「设了提前提醒，却什么都不会发生」。
  ///
  /// 只重排待办提醒，不动班次闹钟：勾一个复选框不该把上千条班次闹钟全扫一遍。
  Future<void> _rescheduleReminders(WidgetRef ref) async {
    final repo = ref.read(appRepositoryProvider);
    await AlarmService.rescheduleEventReminders(await repo.listEvents());
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final titleCtrl = TextEditingController();
    final fields = _EventFields(date: dateOnly(DateTime.now()));

    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // 「关掉本弹窗」的回调：navigator 与 route 都在这儿（**await 之前**）
            // 取好，且只在自己这层还是最上层时才真的 pop —— 见 `dialogCloser`。
            final close = dialogCloser(context);
            return GlassDialog(
              title: L10n.addEvent,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    autofocus: true,
                    decoration: glassInputDecoration(context, L10n.title),
                  ),
                  const SizedBox(height: 12),
                  ...fields.build(context, setState),
                ],
              ),
              actions: [
                GlassActionButton(
                  onPressed: close,
                  label: L10n.cancel,
                ),
                const SizedBox(width: 8),
                GlassActionButton(
                  variant: GlassActionVariant.primary,
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    // 标题为空 = 这一下什么也没做，按钮的锁当帧就放开（同步返回，
                    // 见 `GlassActionButton._fire`）。
                    if (title.isEmpty) return;
                    await fields.commit(ref, title: title);
                    await _rescheduleReminders(ref);
                    close();
                  },
                  label: L10n.add,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// 待办弹窗里那几个可编辑字段：日期 / 时间 / 提醒档位 / 联动闹钟。
///
/// **「添加」与「编辑」两个弹窗共用同一份实现**。v0.7.1 就是在这里出的岔子：
/// 两处各写了一遍，改提醒档位时只改到「添加」，编辑弹窗还停在旧的两档开关上
/// （点它只在「不设 / 15 分钟」之间跳）。现在只有一个来源，改一处两处都对。
class _EventFields {
  _EventFields({
    required this.date,
    this.timeMinute,
    this.advance,
    this.alarm = false,
    this.repeat,
    this.weekdays = 0,
    this.monthDay = 1,
    this.seriesId,
  });

  DateTime date;

  /// 分钟自午夜；null = 没设时间。
  int? timeMinute;

  /// 提醒档位：null = 不设，0 = 准时，其余为提前的分钟数。
  int? advance;

  /// 到点走**闹钟**（全屏 + 循环铃声）而不是只弹一条通知。
  bool alarm;

  /// 重复周期；null = 不重复（这条是一次性待办）。
  RecurRepeat? repeat;

  /// 每周的位掩码（`1 << (weekday - 1)`）。
  int weekdays;

  /// 每月的第几天（1..31）。
  int monthDay;

  /// 这条行属于哪个系列；null = 一次性待办。编辑既有行时带进来。
  int? seriesId;

  List<Widget> build(BuildContext context, StateSetter setState) {
    return [
      // 重复：四档胶囊。与闹钟弹窗的「一次性 / 每天 / 每周」同一个控件、同一套
      // 字重规则（选中 w700、未选中 w500）—— 那是最靠近的同类件。
      GlassSegment(
        count: 4,
        selectedIndex: repeat == null ? 0 : repeat!.index + 1,
        onSelected: (i) => setState(() {
          repeat = i == 0 ? null : RecurRepeat.values[i - 1];
          // **「每周」至少得有一天**：掩码为空时 `occurrenceOnOrBefore` 返回 null，
          // 生成器会当它是脏数据、一条都不生成 —— 而界面上完全看不出来，
          // 用户只会觉得「选了每周却什么都没发生」。默认勾上今天那一天，他再改。
          if (repeat == RecurRepeat.weekly && weekdays == 0) {
            weekdays = 1 << (date.weekday - 1);
          }
        }),
        itemBuilder: (i, selected) => Text(
          [
            L10n.repeatNone,
            L10n.repeatDaily,
            L10n.repeatWeekly,
            L10n.repeatMonthly,
          ][i],
          style: AppTokens.labelSecondary.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
      if (repeat == RecurRepeat.weekly)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
          child: GlassWeekdayPicker(
            value: weekdays,
            // **这里不补触觉**：控件自己已经发了一记（`Haptics.select()`），
            // 调用点再补就是一次操作震两下 —— 两下比一下信息量更少。
            onChanged: (v) => setState(() => weekdays = v),
          ),
        ),
      if (repeat == RecurRepeat.monthly)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(L10n.repeatMonthly),
          trailing: Text('$monthDay'),
          onTap: () async {
            final picked = await showGlassOptionPicker<int>(
              context,
              title: L10n.repeatMonthly,
              options: [for (var d = 1; d <= 31; d++) d],
              labelOf: (d) => '$d',
              selected: monthDay,
            );
            if (picked != null) setState(() => monthDay = picked);
          },
        ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        // 重复项那一行不叫「日期」：它的意思是「从哪天开始生效」，之后的日期由
        // 规则算出来，用户改不了单次（想改就改这一次那条行本身）。
        title: Text(repeat == null ? L10n.date : L10n.startsOn),
        trailing: Text(L10n.monthDay(date)),
        onTap: () async {
          final p = await showGlassDatePicker(
            context,
            initialDate: date,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (p != null) setState(() => date = dateOnly(p));
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.timeOptional),
        trailing: Text(timeMinute == null ? L10n.none : _fmt(timeMinute!)),
        onTap: () async {
          final p = await showGlassTimePicker(
            context,
            initialTime: timeMinute == null
                ? TimeOfDay.now()
                : TimeOfDay(hour: timeMinute! ~/ 60, minute: timeMinute! % 60),
          );
          if (p != null) setState(() => timeMinute = p.hour * 60 + p.minute);
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.advanceRemindOptional),
        trailing: Text(L10n.remindOptionLabel(advance ?? L10n.remindNone)),
        onTap: () async {
          final picked = await showGlassOptionPicker<int>(
            context,
            title: L10n.advanceRemindOptional,
            options: L10n.remindOptions,
            labelOf: L10n.remindOptionLabel,
            selected: advance ?? L10n.remindNone,
          );
          // null = 点外面关掉了，保持原值不动。
          if (picked == null) return;
          setState(() {
            advance = picked < 0 ? null : picked;
            // 「不设」的意思就是别提醒我 —— 联动闹钟跟着关掉。不然开关开着、
            // 却没有可响的时刻，用户会以为它会响（而它永远不会）。
            if (advance == null) alarm = false;
          });
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.linkAlarm),
        subtitle: Text(L10n.linkAlarmHint),
        trailing: GlassSwitch(
          value: alarm,
          onChanged: (v) => setState(() {
            alarm = v;
            // 开着闹钟就得有个可响的时点：提醒是「不设」时自动补成「准时」。
            if (v) advance ??= 0;
          }),
        ),
      ),
    ];
  }

  /// 把这一组字段落到库里：需要时先建 / 改系列，再建 / 改那条行。
  ///
  /// **收在一处是有意的**：这段有四个分支（新建一次性 / 新建重复 / 编辑一次性 /
  /// 编辑重复），抄两遍必然有一遍漏掉某个分支 —— 而漏掉不会报错，只是「改成重复
  /// 之后不生效」或者「解绑了系列还留着」。
  ///
  /// [existing] 为 null 表示新建。
  Future<void> commit(
    WidgetRef ref, {
    required String title,
    ScheduleEvent? existing,
  }) async {
    final repo = ref.read(appRepositoryProvider);
    var sid = seriesId;

    if (repeat == null) {
      // 从重复改回不重复：**解绑 + 删系列定义，一条待办都不删**。
      //
      // 这里**不能**用 `deleteRecurringTodo`（它连带删行）—— 那会把用户正在
      // 编辑的这条待办本身也删掉，而他想要的只是「以后别再自动出现」。
      if (sid != null) {
        await repo.unlinkRecurringSeries(sid);
        sid = null;
      }
    } else if (sid == null) {
      // 一次性改成重复（或新建一个重复的）：建系列
      sid = await repo.addRecurringTodo(
        title: title,
        repeat: repeat!,
        startDate: date,
        timeMinute: timeMinute,
        advanceRemindMinutes: advance,
        alarmEnabled: alarm,
        weekdays: weekdays,
        monthDay: monthDay,
      );
    } else {
      // 编辑既有系列：**显式全字段构造，不用 `copyWith`** —— 那是 `?? this.x`，
      // 没有把可空字段清成 null 的通道，用户把提醒从「提前 5 分钟」改回「不设」
      // 时 `advanceRemindMinutes: null` 会被丢掉、旧值原样留着。
      final s =
          (await repo.listRecurringTodos()).firstWhere((x) => x.id == sid);
      await repo.updateRecurringTodo(RecurringTodo(
        id: s.id,
        title: title,
        repeat: repeat!,
        // **起点原样带过去，不要写成 `date`**：`date` 是「当前这一次」的日子，
        // 拿它当起点会让下面那步对齐整个失效 —— `occurrenceOnOrBefore` 有一道
        // `daysBetween(start, 候选) >= 0` 的闸门（它本来是给生成器用的：不许造出
        // 起始日之前的行），而「把每周三改成每周五」要回退到**本周之前的那个
        // 周五**，起点一变成今天，那个周五就早于起点、被判定为「不合法」→ 返回
        // null → 静默不对齐。
        //
        // 症状是**按星期几现形**的：今天若是周三或周四，「最近一个周五」落在
        // 起点之前，这条路径整天失灵（2026-09-30 跑全套测试时逮到 —— 用例
        // `recurring_dialog_test` 那条「改成每周五」在周三/周四必红，其余五天绿）。
        startDate: s.startDate,
        timeMinute: timeMinute,
        advanceRemindMinutes: advance,
        alarmEnabled: alarm,
        weekdays: weekdays,
        monthDay: monthDay,
        // 这两个不属于这个弹窗管的字段，原样带过去（不然会被清掉）。
        skipThrough: s.skipThrough,
        enabled: s.enabled,
      ));
    }

    if (existing == null) {
      await repo.addEvent(
        title: title,
        date: date,
        timeMinute: timeMinute,
        advanceRemindMinutes: advance,
        alarmEnabled: alarm,
        seriesId: sid,
      );
    } else {
      await repo.updateEvent(
        existing,
        title: title,
        date: date,
        timeMinute: timeMinute,
        advanceRemindMinutes: advance,
        alarmEnabled: alarm,
        seriesId: sid,
      );
    }

    // 改完周期要把「当前这一次」对齐到新规则的最近一次发生日（spec §4.2 末段）。
    //
    // **这一步生成器不会替我们做**：它只往前顺延、永不回退（用户手工把这一次
    // 挪到别的日子时不许被拽回来），而「把每周三改成每周五」恰恰需要回退。
    // 两条路径的分工写在这里，免得后人把哪一边当成 bug 去改。
    if (sid != null) {
      final s = (await repo.listRecurringTodos()).firstWhere((x) => x.id == sid);
      final occ = occurrenceOnOrBefore(s, dateOnly(DateTime.now()));
      if (occ != null) {
        for (final r in (await repo.listEvents())
            .where((e) => e.seriesId == sid && !e.isCompleted)) {
          if (!isSameDay(r.date, occ)) await repo.setEventDate(r.id, occ);
        }
      }
    }
  }
}

Future<void> showEditEventDialog(
    BuildContext context, WidgetRef ref, ScheduleEvent e) async {
  // 这条行属于某个系列时，弹窗里编的其实是**那个系列**（标题 / 时间 / 提醒 /
  // 周期都写回系列，见 `_EventFields.commit`），所以得先把系列读出来。
  RecurringTodo? series;
  if (e.seriesId != null) {
    for (final s
        in await ref.read(appRepositoryProvider).listRecurringTodos()) {
      if (s.id == e.seriesId) {
        series = s;
        break;
      }
    }
  }
  if (!context.mounted) return;

  final titleCtrl = TextEditingController(text: e.title);
  final fields = _EventFields(
    date: e.date,
    timeMinute: e.timeMinute,
    advance: e.advanceRemindMinutes,
    alarm: e.alarmEnabled,
    repeat: series?.repeat,
    weekdays: series?.weekdays ?? 0,
    monthDay: series?.monthDay ?? 1,
    seriesId: e.seriesId,
  );

  if (!context.mounted) return;
  showDialog(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          // 同「添加」弹窗：closer 在 await 之前取好，且只在自己这层还是最上层
          // 时才 pop —— 连点「保存」或点完保存点取消都不会把最后一层路由弹掉。
          final close = dialogCloser(context);
          return GlassDialog(
            title: L10n.editEvent,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration: glassInputDecoration(context, L10n.title),
                ),
                const SizedBox(height: 12),
                ...fields.build(context, setState),
              ],
            ),
            actions: [
              GlassActionButton(
                onPressed: close,
                label: L10n.cancel,
              ),
              const SizedBox(width: 8),
              GlassActionButton(
                variant: GlassActionVariant.primary,
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty) return;
                  await fields.commit(ref, title: title, existing: e);
                  await AlarmService.rescheduleEventReminders(
        await ref.read(appRepositoryProvider).listEvents());
                  close();
                },
                label: L10n.save,
              ),
            ],
          );
        },
      );
    },
  );
}

String _fmt(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

enum _DeleteChoice { once, series }

/// 删一条重复待办时的二选一。
///
/// **必须问**：直接删掉的话，生成器下一次打开 App 又会把它补出来（用户看到的是
/// 「删不掉」）；而直接删整个系列又会把「我这周不做」变成「以后都不做了」。
///
/// 两个回调都是**同步** `pop`（不 await 任何东西），所以不需要 `dialogCloser`
/// —— 那个是给「await 之后才关窗」的保存类动作准备的。
Future<_DeleteChoice?> _askDeleteRecurring(BuildContext context, String name) {
  return showDialog<_DeleteChoice>(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) => GlassDialog(
      title: L10n.deleteRecurringTitle,
      content: Text(L10n.deleteRecurringContent(name)),
      actions: [
        GlassActionButton(
          onPressed: () => Navigator.pop(context, _DeleteChoice.once),
          label: L10n.skipThisOccurrence,
        ),
        const SizedBox(width: 8),
        GlassActionButton(
          variant: GlassActionVariant.danger,
          onPressed: () => Navigator.pop(context, _DeleteChoice.series),
          label: L10n.deleteWholeSeries,
        ),
      ],
    ),
  );
}

/// FAB 上移，避开底部悬浮玻璃胶囊。
class _AboveCapsuleFabLocation extends FloatingActionButtonLocation {
  const _AboveCapsuleFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final base = FloatingActionButtonLocation.endFloat.getOffset(geometry);
    return Offset(base.dx, base.dy - 76);
  }
}
