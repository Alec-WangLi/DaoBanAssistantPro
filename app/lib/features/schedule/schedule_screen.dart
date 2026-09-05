import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(L10n.titleTodo,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: events.isEmpty
                  ? Center(
                      child: Text(
                        L10n.noEvents,
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
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
      ),
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
            child:
                const Icon(Icons.add_outlined, color: Colors.white, size: 28),
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
        L10n.advanceXMinutes(e.advanceRemindMinutes!),
    ].join(' · ');

    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GlassTile(
      enableBlur: false,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      onTap: () => _showEditDialog(context, ref, e),
      child: Row(
        children: [
          GlassSwitch(
            value: e.isCompleted,
            onChanged: (v) =>
                ref.read(appRepositoryProvider).setEventCompleted(e, v),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: e.isCompleted
                        ? onSurface.withValues(alpha: 0.45)
                        : onSurface,
                    decoration:
                        e.isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: e.isCompleted
                        ? onSurface.withValues(alpha: 0.35)
                        : onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          GlassDeleteButton(
            onPressed: () =>
                ref.read(appRepositoryProvider).deleteEvent(e),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final titleCtrl = TextEditingController();
    DateTime date = dateOnly(DateTime.now());
    int? timeMinute;
    int? advance;

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
                    trailing: Text(
                        timeMinute == null ? L10n.none : _fmt(timeMinute!)),
                    onTap: () async {
                      final p = await showGlassTimePicker(
                        context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (p != null)
                        setState(
                            () => timeMinute = p.hour * 60 + p.minute);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(L10n.advanceRemindOptional),
                    trailing: Text(advance == null
                        ? L10n.none
                        : (L10n.isEn ? '$advance min' : '$advance 分钟')),
                    onTap: () => setState(
                        () => advance = advance == null ? 15 : null),
                  ),
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
                  onPressed: () {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) return;
                    ref.read(appRepositoryProvider).addEvent(
                          title: title,
                          date: date,
                          timeMinute: timeMinute,
                          advanceRemindMinutes: advance,
                        );
                    Navigator.pop(context);
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
    DateTime date = e.date;
    int? timeMinute = e.timeMinute;
    int? advance = e.advanceRemindMinutes;

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
                    title: const Text('时间（可选）'),
                    trailing:
                        Text(timeMinute == null ? '不设' : _fmt(timeMinute!)),
                    onTap: () async {
                      final p = await showGlassTimePicker(
                        context,
                        initialTime: timeMinute == null
                            ? TimeOfDay.now()
                            : TimeOfDay(
                                hour: timeMinute! ~/ 60,
                                minute: timeMinute! % 60),
                      );
                      if (p != null)
                        setState(() => timeMinute = p.hour * 60 + p.minute);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('提前提醒（可选）'),
                    trailing: Text(advance == null ? '不设' : '$advance 分钟'),
                    onTap: () =>
                        setState(() => advance = advance == null ? 15 : null),
                  ),
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
                  onPressed: () {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) return;
                    ref.read(appRepositoryProvider).updateEvent(
                          e,
                          title: title,
                          date: date,
                          timeMinute: timeMinute,
                          advanceRemindMinutes: advance,
                        );
                    Navigator.pop(context);
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
