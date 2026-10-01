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
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_delete_button.dart';
import '../../core/widgets/glass_dialog.dart';
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

  /// 一行一个系列。
  ///
  /// **手搓 `Row` 而不是 `ListTile`** —— 照闹钟页那个「自定义闹钟」行
  /// （`alarm_screen.dart` 的 `_alarmTile`）：`ListTile` 的 `minLeadingWidth`(40)
  /// + `horizontalTitleGap`(16) + `contentPadding` 在**窄弹层**里光内边距就吃掉
  /// 五六十 dp，而这一行尾部要放一个开关加一个删除钮，200×400 小窗实测尾部
  /// 直接溢出（视觉工装的 `failOnOverflow` 抓的）。中间那一段用 `Expanded`
  /// 兜底：实在放不下时先牺牲标题与副标题的宽度（它们本来就是省略号结尾）。
  Widget _row(BuildContext context, WidgetRef ref, RecurringTodo s) {
    final today = dateOnly(DateTime.now());
    // 「下次」要的是**严格晚于今天**的那一次。用 `occurrenceOnOrBefore` 兜底是错的：
    // 那给出的是「已经过去的那一次」（比如今天是周二、系列是每周三，它给上周三），
    // 而那一行此刻就在列表里躺着 —— 面板上再把它写成「下次 9月23日」是在说反话。
    final next = nextOccurrenceAfter(s, today);
    final parts = [
      s.ruleLabel,
      if (s.timeLabel.isNotEmpty) s.timeLabel,
      if (next != null) L10n.nextTime(L10n.monthDay(next)),
    ];
    final muted = AppTokens.inkMuted(context);
    // **窄窗（窗口宽 < 260）这一行排两行。**
    //
    // v0.10.10 把开关从 46 加宽到 56 之后，这一行在 200×400 下先溢出了 6px；收掉
    // 内缩与间距能止住溢出，但独立审查**量**出来：标题只剩 **14px**，而一个汉字
    // 加省略号要 ≈28px —— Flutter 索性什么都不画，行读起来是 `[开关] [垃圾桶]`，
    // 看不出自己在开关哪一条规则（**那不是这一版弄坏的**，v0.10.9 只剩 4px）。
    //
    // 所以窄窗改成两行排：开关与删除键一行、标题与副标题**拿回整行宽度**在下一行。
    // **一个控件都没有摘**（对比：摘掉那个删除键也能腾出 36px，但那是交互改动）。
    final bool tight = MediaQuery.sizeOf(context).width < 260;

    final Widget switchTile = GlassSwitch(
      value: s.enabled,
      onChanged: (v) => _setEnabled(ref, s, v),
    );
    final Widget deleteTile = GlassDeleteButton(
      compact: true,
      onPressed: () => _delete(context, ref, s),
    );
    final Widget texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.title,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTokens.rowPrimary),
        Text(parts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTokens.microText.copyWith(color: muted)),
      ],
    );

    return GlassTile(
      enableBlur: false,
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceSm, vertical: AppTokens.spaceXs),
      onTap: () => _edit(context, ref, s),
      child: tight
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [switchTile, const Spacer(), deleteTile]),
                const SizedBox(height: AppTokens.spaceXs),
                texts,
              ],
            )
          : Row(
              children: [
                switchTile,
                const SizedBox(width: AppTokens.gapIconText),
                Expanded(child: texts),
                deleteTile,
              ],
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
