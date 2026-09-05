import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_delete_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../data/app_repository.dart';
import '../../domain/shift_rotation.dart';
import 'schedule_editor_screen.dart';

/// 排班管理：列出所有排班表，可单独编辑、新增、删除。
class ScheduleManagementScreen extends ConsumerWidget {
  const ScheduleManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(schedulesProvider);
    final schedules = async.valueOrNull ?? const <ShiftScheduleRow>[];
    final current = ref.watch(activeScheduleProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(L10n.scheduleManagement)),
      body: async.isLoading && schedules.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                ...schedules.map((s) {
                  final isCurrent = s.id == current?.schedule.id;
                  return GlassTile(
                    enableBlur: false,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: EdgeInsets.zero,
                    child: GlassPressable(
                      child: ListTile(
                        leading: Icon(
                          isCurrent
                              ? Icons.check_circle_outlined
                              : Icons.calendar_month_outlined,
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(s.name),
                        subtitle: Text(
                            '${L10n.teamCountN(parseTeamNames(s.teamNames).length)} · '
                            '${L10n.monthDay(s.anchorDate)}'
                            '${isCurrent ? ' · ${L10n.current}' : ''}'),
                        trailing: GlassDeleteButton(
                          onPressed: () => _deleteSchedule(context, ref, s),
                        ),
                        onTap: () => _openEditor(context, ref, s.id),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _addSchedule(context, ref),
                  icon: const Icon(Icons.add_outlined),
                  label: Text(L10n.addSchedule),
                ),
              ],
            ),
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref, int id) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ScheduleEditorScreen(scheduleId: id)),
    );
    if (saved == true && context.mounted) {
      showGlassSnack(context, L10n.savedAndRescheduled,
          icon: Icons.check_circle_outlined);
    }
  }

  Future<void> _addSchedule(BuildContext context, WidgetRef ref) async {
    final d = defaultSchedule();
    final id = await ref.read(appRepositoryProvider).saveSchedule(
          name: L10n.newSchedule,
          anchorDate: dateOnly(DateTime.now()),
          types: d.shiftTypes,
          makeCurrent: false,
        );
    if (context.mounted) await _openEditor(context, ref, id);
  }

  Future<void> _deleteSchedule(
      BuildContext context, WidgetRef ref, ShiftScheduleRow s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => GlassDialog(
        title: L10n.deleteScheduleTitle,
        content: Text(L10n.deleteScheduleContent(s.name)),
        actions: [
          GlassActionButton(
            onPressed: () => Navigator.pop(context, false),
            label: L10n.cancel,
          ),
          const SizedBox(width: 8),
          GlassActionButton(
            variant: GlassActionVariant.danger,
            onPressed: () => Navigator.pop(context, true),
            label: L10n.delete,
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(appRepositoryProvider).deleteSchedule(s.id);
    }
  }
}
