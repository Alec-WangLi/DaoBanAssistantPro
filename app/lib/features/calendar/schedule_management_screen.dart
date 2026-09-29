import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_delete_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../data/app_repository.dart';
import '../../domain/schedule_chain.dart';
import '../../domain/shift_rotation.dart';
import 'schedule_editor_screen.dart';
import 'schedule_span_label.dart';
import 'shift_template_picker_screen.dart';

/// 排班管理：列出所有排班表，可单独编辑、新增、删除。
class ScheduleManagementScreen extends ConsumerWidget {
  const ScheduleManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(schedulesProvider);
    final schedules = async.valueOrNull ?? const <ShiftScheduleRow>[];
    final current = ref.watch(activeScheduleProvider).valueOrNull;
    // 每套方案被多少段引用 —— 身份标签要用（「已排入时段」还是「未使用」）。
    final spans =
        ref.watch(scheduleSpansProvider).valueOrNull ?? const <ScheduleSpanRow>[];

    return Scaffold(
      appBar: AppBar(title: Text(L10n.scheduleManagement)),
      body: async.isLoading && schedules.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : CenteredContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _TimelineSection(
                  schedules: schedules,
                  current: current,
                  spans: spans,
                ),
                ...schedules.map((s) {
                  final isCurrent = s.id == current?.currentScheduleId;
                  return GlassTile(
                    enableBlur: false,
                    margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
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
                            '${scheduleRoleLabel(s, spanCount: spanCountOf(spans, s.id), isCurrent: isCurrent)} · '
                            '${L10n.teamCountN(parseTeamNames(s.teamNames).length)} · '
                            '${L10n.monthDay(s.anchorDate)}'
                            '${isCurrent ? ' · ${L10n.current}' : ''}'),
                        trailing: GlassDeleteButton(
                          compact: true,
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
    // 先选倒班方式；按返回键放弃则 id 为 null，既不建方案也不进编辑器。
    final id = await createScheduleFromTemplatePicker(context, ref,
        makeCurrent: false);
    if (id == null || !context.mounted) return;
    await _openEditor(context, ref, id);
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

/// 排班管理页顶部那一节「排班时段」。
///
/// 形态与「其余时间」这个概念配套：**永远列出「其余时间」那一行**，没有段时就
/// 只有它 —— 所以不必为「有没有段」写两套版式（少一个要维护、要出图的状态）。
///
/// 行按**起点升序**（起点为空排最前），与 `compareSpansByStart`、与解析规则同一条
/// 口径 —— 三处不一致的话，「界面上看到的顺序」与「提示里点名的那个」会对不上。
class _TimelineSection extends ConsumerWidget {
  const _TimelineSection({
    required this.schedules,
    required this.current,
    required this.spans,
  });

  final List<ShiftScheduleRow> schedules;
  final ActiveSchedules? current;
  final List<ScheduleSpanRow> spans;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = AppTokens.inkMuted(context);
    final byId = {for (final s in schedules) s.id: s};
    final remaining = current?.current;

    return GlassTile(
      enableBlur: false,
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L10n.scheduleTimeline, style: AppTokens.sectionTitle),
          const SizedBox(height: AppTokens.spaceXs),
          Text(L10n.remainingHint,
              style: AppTokens.rowSecondary.copyWith(color: muted)),
          const SizedBox(height: AppTokens.spaceXs),
          _row(
            context,
            label: L10n.remainingTime,
            value: remaining?.schedule.name ?? L10n.remainingNone,
            mutedValue: remaining == null,
            onTap: () => showRemainingPicker(context, ref),
          ),
          for (final span in spans)
            _row(
              context,
              label: spanRangeLabel(span.startDate, span.endDate),
              value: byId[span.scheduleId]?.name ?? L10n.remainingNone,
              mutedValue: byId[span.scheduleId] == null,
              onTap: () => showSpanEditor(context, ref, existing: span),
            ),
          GlassPressable(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_outlined),
              title: Text(L10n.addSpan),
              onTap: () => showSpanEditor(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  /// 一行：[左边是这一段的日期 / 「其余时间」] + [右边它指向的方案名] + 箭头。
  ///
  /// **手搓 `Row` 而不是 `ListTile`**：`ListTile` 的 `trailing` 在 200dp 小窗下会
  /// 横向溢出（`minLeadingWidth`/`horizontalTitleGap` 先吃掉一块，剩下给 trailing
  /// 的还不够放一个名字加箭头）—— 工装的小窗那一屏就是这么红的。手搓的这版
  /// 两边都是 flex，各自省略号，任何宽度都不溢。
  ///
  /// 点击用 `GestureDetector` 承载（`GlassPressable` **没有 `onTap`**，它只是个
  /// 按压缩放的包装）—— 与日历信息卡那行班次同一套写法。
  Widget _row(
    BuildContext context, {
    required String label,
    required String value,
    required bool mutedValue,
    required VoidCallback onTap,
  }) {
    final muted = AppTokens.inkMuted(context);
    return GlassPressable(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
          child: Row(
            children: [
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
              const SizedBox(width: AppTokens.gapIconText),
              Icon(Icons.chevron_right_outlined,
                  size: AppTokens.iconSm, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「其余时间」用哪一套 —— 选一套，或者「无」。
///
/// 「无」是这个模型里**唯一**能到达「没有默认」的入口（删掉一套方案时仍然自动
/// 把其余时间交给列表里的第一套，否则删掉默认那套会让整张日历变空）。
Future<void> showRemainingPicker(BuildContext context, WidgetRef ref) async {
  final schedules = await ref.read(schedulesProvider.future);
  if (!context.mounted) return;
  final currentId =
      ref.read(activeScheduleProvider).valueOrNull?.currentScheduleId;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (dialogContext) => GlassDialog(
      title: L10n.remainingTime,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in schedules)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                s.id == currentId
                    ? Icons.check_circle_outlined
                    : Icons.circle_outlined,
                color: s.id == currentId
                    ? Theme.of(dialogContext).colorScheme.primary
                    : null,
              ),
              title: Text(s.name),
              onTap: () async {
                await ref.read(appRepositoryProvider).setCurrentSchedule(s.id);
                // `dialogCloser` **返回**闭包（用法是 `onPressed: dialogCloser(ctx)`）——
                // 这里在 await 之后调，所以要再 () 一下才真的关窗。
                if (dialogContext.mounted) dialogCloser(dialogContext)();
              },
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              currentId == null
                  ? Icons.check_circle_outlined
                  : Icons.circle_outlined,
              color: currentId == null
                  ? Theme.of(dialogContext).colorScheme.primary
                  : null,
            ),
            title: Text(L10n.remainingNone),
            onTap: () async {
              await ref.read(appRepositoryProvider).setRemainingNone();
              // `dialogCloser` **返回**闭包（用法是 `onPressed: dialogCloser(ctx)`）——
                // 这里在 await 之后调，所以要再 () 一下才真的关窗。
                if (dialogContext.mounted) dialogCloser(dialogContext)();
            },
          ),
        ],
      ),
      actions: [
        GlassActionButton(
          onPressed: () => dialogCloser(dialogContext),
          label: L10n.cancel,
        ),
      ],
    ),
  );
}

/// 加一段 / 改一段。
///
/// **重叠校验放在写库之前**：把「本次要写的那一段」与库里其余的段一起交给
/// [conflictingSpans]，撞上就弹一句点名并直接返回（**不写库**）。这与 v0.9.12
/// 那次「允许重叠、让起点晚的赢」是相反的做法 —— 用户要的是「不许我犯错」，
/// 不是「替我选一个」。
Future<void> showSpanEditor(
  BuildContext context,
  WidgetRef ref, {
  ScheduleSpanRow? existing,
}) async {
  final schedules = await ref.read(schedulesProvider.future);
  final spans = await ref.read(scheduleSpansProvider.future);
  if (!context.mounted || schedules.isEmpty) return;

  var picked = existing == null
      ? schedules.first
      : schedules.firstWhere((s) => s.id == existing.scheduleId,
          orElse: () => schedules.first);
  var from = existing?.startDate;
  var to = existing?.endDate;

  /// 一套只为了取名与比较的壳 —— `conflictingSpans` 只看 `from`/`to`，而提示里
  /// 要写**对方的名字**，所以名字必须是真的。
  ScheduleSpan shell(int? id, int scheduleId, DateTime? f, DateTime? t) =>
      ScheduleSpan(
        id: id,
        scheduleId: scheduleId,
        schedule: ShiftSchedule(
          name: schedules
              .firstWhere((s) => s.id == scheduleId,
                  orElse: () => schedules.first)
              .name,
          anchorDate: DateTime.utc(2000),
          classes: const [],
          cycle: const [],
        ),
        from: f,
        to: t,
      );

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) => GlassDialog(
        title: existing == null ? L10n.addSpan : spanRangeLabel(from, to),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(L10n.schedule, style: AppTokens.rowSecondary),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(picked.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTokens.labelStrong),
              ),
              onTap: () async {
                final chosen = await showGlassOptionPicker<ShiftScheduleRow>(
                  dialogContext,
                  title: L10n.schedule,
                  options: schedules,
                  labelOf: (s) => s.name,
                  selected: picked,
                );
                if (chosen != null) setLocal(() => picked = chosen);
              },
            ),
            _spanDateRow(dialogContext, L10n.spanFrom, from, L10n.spanUnbounded,
                (d) => setLocal(() => from = d)),
            _spanDateRow(dialogContext, L10n.spanTo, to, L10n.spanForever,
                (d) => setLocal(() => to = d)),
          ],
        ),
        actions: [
          if (existing != null)
            GlassActionButton(
              variant: GlassActionVariant.danger,
              label: L10n.delete,
              onPressed: () async {
                await ref.read(appRepositoryProvider).deleteSpan(existing.id);
                // `dialogCloser` **返回**闭包（用法是 `onPressed: dialogCloser(ctx)`）——
                // 这里在 await 之后调，所以要再 () 一下才真的关窗。
                if (dialogContext.mounted) dialogCloser(dialogContext)();
              },
            ),
          GlassActionButton(
            onPressed: () => dialogCloser(dialogContext),
            label: L10n.cancel,
          ),
          GlassActionButton(
            variant: GlassActionVariant.primary,
            label: L10n.save,
            onPressed: () async {
              // 撞上就不写库，并点名 —— 一天只能有一套排班。
              final self = shell(existing?.id, picked.id, from, to);
              final others = [
                for (final s in spans)
                  if (s.id != existing?.id)
                    shell(s.id, s.scheduleId, s.startDate, s.endDate),
              ];
              final clash = conflictingSpans(others, self);
              if (clash.isNotEmpty) {
                showGlassSnack(
                  context,
                  L10n.spanConflicts(clash.first.schedule.name,
                      spanRangeLabel(clash.first.from, clash.first.to)),
                  icon: Icons.error_outline,
                );
                return;
              }
              final repo = ref.read(appRepositoryProvider);
              if (existing == null) {
                await repo.addSpan(picked.id, from: from, to: to);
              } else {
                await repo.updateSpan(existing.id,
                    scheduleId: picked.id, from: from, to: to);
              }
              // `dialogCloser` **返回**闭包（用法是 `onPressed: dialogCloser(ctx)`）——
                // 这里在 await 之后调，所以要再 () 一下才真的关窗。
                if (dialogContext.mounted) dialogCloser(dialogContext)();
            },
          ),
        ],
      ),
    ),
  );
}

/// 时段弹层里「从 / 到」那一行：可点选日期，右边一个清除钮（清空 = 留空）。
///
/// 日期选择器是**选择器的提交点**，它自己会发 `Haptics.select()` —— 这里不补触觉。
Widget _spanDateRow(
  BuildContext context,
  String label,
  DateTime? value,
  String emptyText,
  ValueChanged<DateTime?> onChanged,
) {
  final muted = AppTokens.inkMuted(context);
  return ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: AppTokens.rowSecondary),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value == null ? emptyText : L10n.monthDay(value),
          style: value == null
              ? AppTokens.rowSecondary.copyWith(color: muted)
              : AppTokens.labelStrong,
        ),
        if (value != null)
          IconButton(
            onPressed: () => onChanged(null),
            icon: const Icon(Icons.close_outlined),
            iconSize: AppTokens.iconSm,
            color: muted,
          ),
      ],
    ),
    onTap: () async {
      final picked = await showGlassDatePicker(
        context,
        initialDate: value ?? dateOnly(DateTime.now()),
      );
      if (picked != null) onChanged(picked);
    },
  );
}
