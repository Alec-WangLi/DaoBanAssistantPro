// 重复待办的管理面板：列出全部系列，能改 / 停用 / 删。
//
// 形态是**弹窗**不是整页（照「我的模板」那个管理弹窗那套配方）：系列通常只有
// 几个，为它单开一页反而要多一次进出。
//
// 数据走 `recurringTodosProvider`（一次性读 + autoDispose）—— **用流的话每条挂
// 这个弹窗的 widget 用例都会在拆树时报「A Timer is still pending」**
// （drift 取消查询流时排的零时长定时器），而且面板是个短命弹层，没必要挂流。
// 页内改 / 删之后由 `ref.invalidate` 重读。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_delete_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../core/widgets/glass_switch.dart';
import '../../data/app_repository.dart';
import '../../domain/recurring_todo.dart';
import '../../domain/shift_rotation.dart';
import '../alarm/alarm_service.dart';
import 'schedule_screen.dart';

/// 弹出「重复待办」管理面板。
///
/// **只收 `context`**：视觉工装要把弹层塞进 `_DialogHost` 才拍得到（弹层是命令式
/// 的、没有可渲染的 widget），而那个薄壳只给 context。里面用 `Consumer` 取
/// provider，所以不需要外传 `ref`。
Future<void> showRecurringTodosDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) => GlassDialog(
      title: L10n.recurring,
      showClose: true,
      content: const _RecurringList(),
      actions: const [],
    ),
  );
}

class _RecurringList extends ConsumerWidget {
  const _RecurringList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(recurringTodosProvider).valueOrNull;
    if (series == null) {
      return const Padding(
        padding: EdgeInsets.all(AppTokens.spaceLg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (series.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Text(
          L10n.recurringEmpty,
          style:
              AppTokens.rowSecondary.copyWith(color: AppTokens.inkMuted(context)),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [for (final s in series) _row(context, ref, s)],
    );
  }

  /// 一行一个系列。行的配方**照排班管理页**（`GlassTile(enableBlur: false,
  /// padding: EdgeInsets.zero)` + `GlassPressable` + `ListTile` + 尾部紧凑删除钮）
  /// —— 那是全 app 的列表行做法。
  Widget _row(BuildContext context, WidgetRef ref, RecurringTodo s) {
    final today = dateOnly(DateTime.now());
    final next =
        occurrenceOnOrBefore(s, today) ?? nextOccurrenceAfter(s, today);
    final parts = [
      s.ruleLabel,
      if (s.timeLabel.isNotEmpty) s.timeLabel,
      if (next != null) L10n.nextTime(L10n.monthDay(next)),
    ];
    final muted = AppTokens.inkMuted(context);
    return GlassTile(
      enableBlur: false,
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: EdgeInsets.zero,
      child: GlassPressable(
        child: ListTile(
          leading: AppIcon(Icons.repeat,
              size: AppTokens.iconMd,
              color: s.enabled ? Theme.of(context).colorScheme.primary : muted),
          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(parts.join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassSwitch(
                value: s.enabled,
                onChanged: (v) => _setEnabled(ref, s, v),
              ),
              GlassDeleteButton(
                compact: true,
                onPressed: () => _delete(context, ref, s),
              ),
            ],
          ),
          onTap: () => _edit(context, ref, s),
        ),
      ),
    );
  }

  /// 停用 / 启用。
  ///
  /// 两边都要跑一次生成器：**启用之后要让「当前这一次」立刻出现在列表里**，
  /// 停用之后要把那一串提醒撤掉（不然它还会照响）。
  Future<void> _setEnabled(WidgetRef ref, RecurringTodo s, bool v) async {
    final repo = ref.read(appRepositoryProvider);
    await repo.setRecurringEnabled(s.id!, v);
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));
    await AlarmService.rescheduleAll(repo);
    ref.invalidate(recurringTodosProvider);
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, RecurringTodo s) async {
    final repo = ref.read(appRepositoryProvider);
    final live = (await repo.listEvents())
        .where((e) => e.seriesId == s.id && !e.isCompleted)
        .toList();
    if (!context.mounted) return;
    if (live.isEmpty) {
      // 没有「当前这一次」就没地方挂那个编辑弹窗（它编的是**行**，顺带写回系列）。
      // 不另做一个只编系列的界面：那种情况很少（起始日在将来 / 刚跳过），明说
      // 一句比多一套界面划算。
      showGlassSnack(context, L10n.recurringNoCurrent,
          icon: Icons.info_outline);
      return;
    }
    await showEditEventDialog(context, ref, live.single);
    ref.invalidate(recurringTodosProvider);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, RecurringTodo s) async {
    final n = (await ref.read(appRepositoryProvider).listEvents())
        .where((e) => e.seriesId == s.id)
        .length;
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => GlassDialog(
        title: L10n.deleteRecurringTitle,
        content: Text(L10n.deleteSeriesContent(s.title, n)),
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
    if (ok != true) return;
    final repo = ref.read(appRepositoryProvider);
    await repo.deleteRecurringTodo(s.id!);
    await AlarmService.rescheduleAll(repo);
    ref.invalidate(recurringTodosProvider);
  }
}
