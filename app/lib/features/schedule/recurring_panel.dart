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
import '../../core/layout.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_delete_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_loading.dart';
import '../../core/widgets/glass_switch.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/app_repository.dart';
import '../../domain/recurring_todo.dart';
import '../../domain/shift_rotation.dart';
import '../alarm/alarm_service.dart';
import 'recurring_series_editor.dart';

/// 弹出「重复待办」管理面板。
///
/// **只收 `context`**：视觉工装要把弹层塞进 `_DialogHost` 才拍得到（弹层是命令式
/// 的、没有可渲染的 widget），而那个薄壳只给 context。里面用 `Consumer` 取
/// provider，所以不需要外传 `ref`。
Future<void> showRecurringTodosDialog(BuildContext context) {
  return showGlassDialog<void>(
    context: context,
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
        child: GlassLoading(),
      );
    }
    if (series.isEmpty) {
      return EmptyState(L10n.recurringEmpty);
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
    // v0.11.12 起**窄屏也走这一支**：320dp 上这一行即使两行封顶，英文那串
    // （`Every day · 07:00 · Next Oct 14`）仍然装不下 —— 而「把标题与副标题拿回
    // 整行宽度」正是这一支本来要解决的问题，只是从前只按 260 这个像素阈值判。
    final bool tight =
        MediaQuery.sizeOf(context).width < 260 || AppLayout.of(context).isNarrow;

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
        // 两行封顶、不省略（设计 §6.3）：`每天 · 07:00 · 下次 10月14日` 这一串
        // 在窄屏大字号下装不下，吃掉尾段比换行难读得多。
        Text(s.title, maxLines: 2, style: AppTokens.rowPrimary),
        Text(parts.join(' · '),
            maxLines: 2, style: AppTokens.microText.copyWith(color: muted)),
      ],
    );

    return GlassTile(
      translucentFill: false,
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceSm, vertical: AppTokens.spaceXs),
      // 点整行 = 打开**系列编辑器**（不依赖「当前这一次」是否存在）。
      // 2026-10-21 用户真机：「已添加的重复待办，它不能修改，也找不到编辑」——
      // 从前这里编的是当前那一条，没有那一条就只弹一句提示。
      onTap: () => showRecurringSeriesEditor(context, s),
      child: tight
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 窄窗这一行**不放那颗铅笔**：开关 56 + 删除钮已经把这行占满，
                // 再加一颗就横向溢出（200×400 实测溢 22px）。整行本来就可点，
                // 提示在宽松版式里给就够了。
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
                // 行本身可点（打开系列编辑器），这颗小铅笔只是把「这里能点」
                // 说出来 —— 在这一版之前，整行可点却没有任何暗示。
                editHint,
                const SizedBox(width: AppTokens.gapIconText),
                deleteTile,
              ],
            ),
    );
  }

  /// 行尾那颗小铅笔：把「点进去能改」说出来。
  ///
  /// **不是独立按钮** —— 它躺在整行可点的 `GlassTile` 里，点它等于点行
  /// （再叠一个 `onTap` 会在手势竞技场里和父层抢，反而可能两边都不触发）。
  Widget get editHint => const AppIcon(
        Icons.edit_outlined,
        size: AppTokens.iconSm,
      );

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

  Future<void> _delete(
      BuildContext context, WidgetRef ref, RecurringTodo s) async {
    final n = (await ref.read(appRepositoryProvider).listEvents())
        .where((e) => e.seriesId == s.id)
        .length;
    if (!context.mounted) return;
    final ok = await showGlassDialog<bool>(
      context: context,
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
