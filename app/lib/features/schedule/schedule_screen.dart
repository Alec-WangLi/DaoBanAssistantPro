import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_delete_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_switch.dart';
import '../../data/app_repository.dart';
import '../../domain/shift_rotation.dart';
import '../../state/app_settings.dart';
import '../alarm/alarm_service.dart';

/// 日程：最简事件（标题 + 日期 + 可选时间 + 可选提前提醒 + 完成勾选）。
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              child: Text(L10n.titleTodo, style: AppTokens.pageTitle),
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
                          style: TextStyle(color: AppTokens.inkMuted(context)),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
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
      onTap: () => _showEditDialog(context, ref, e),
      child: Row(
        children: [
          GlassSwitch(
            value: e.isCompleted,
            onChanged: (v) async {
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
              await ref.read(appRepositoryProvider).deleteEvent(e);
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
                  onPressed: () => Navigator.pop(context),
                  label: L10n.cancel,
                ),
                const SizedBox(width: 8),
                GlassActionButton(
                  variant: GlassActionVariant.primary,
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) return;
                    // 异步之前先把 navigator 抓住：await 之后再碰 context 不安全
                    // （`if (context.mounted)` 在某些时机下会判假，弹窗就永远关不掉）。
                    final navigator = Navigator.of(context);
                    await ref.read(appRepositoryProvider).addEvent(
                          title: title,
                          date: fields.date,
                          timeMinute: fields.timeMinute,
                          advanceRemindMinutes: fields.advance,
                          alarmEnabled: fields.alarm,
                        );
                    await _rescheduleReminders(ref);
                    navigator.pop();
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

  void _showEditDialog(BuildContext context, WidgetRef ref, ScheduleEvent e) {
    final titleCtrl = TextEditingController(text: e.title);
    final fields = _EventFields(
      date: e.date,
      timeMinute: e.timeMinute,
      advance: e.advanceRemindMinutes,
      alarm: e.alarmEnabled,
    );

    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
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
                  onPressed: () => Navigator.pop(context),
                  label: L10n.cancel,
                ),
                const SizedBox(width: 8),
                GlassActionButton(
                  variant: GlassActionVariant.primary,
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) return;
                    final navigator = Navigator.of(context);
                    await ref.read(appRepositoryProvider).updateEvent(
                          e,
                          title: title,
                          date: fields.date,
                          timeMinute: fields.timeMinute,
                          advanceRemindMinutes: fields.advance,
                          alarmEnabled: fields.alarm,
                        );
                    await _rescheduleReminders(ref);
                    navigator.pop();
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
  });

  DateTime date;

  /// 分钟自午夜；null = 没设时间。
  int? timeMinute;

  /// 提醒档位：null = 不设，0 = 准时，其余为提前的分钟数。
  int? advance;

  /// 到点走**闹钟**（全屏 + 循环铃声）而不是只弹一条通知。
  bool alarm;

  List<Widget> build(BuildContext context, StateSetter setState) {
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.date),
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
}

String _fmt(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
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
