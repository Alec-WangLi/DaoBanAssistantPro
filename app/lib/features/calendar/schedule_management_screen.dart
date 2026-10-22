import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/layout.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/glass_delete_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_loading.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../core/widgets/section_heading.dart';
import '../../data/app_repository.dart';
import '../../domain/schedule_chain.dart';
import '../../domain/shift_rotation.dart';
import '../alarm/alarm_service.dart';
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

    // 按月方案那一行要印「每月几段」—— 段表在装配好的那一份里（`ActiveSchedules.all`），
    // 方案行上没有。就地做一次 id → 段数的映射，不为它再查一次库。
    final monthSegCounts = <int, int>{
      for (final a in current?.all ?? const <ActiveSchedule>[])
        a.schedule.id: a.monthSegments.length,
    };

    return Scaffold(
      // 标题按宽度缩小而不是省略（设计 §2）：AppBar 的工具条高度是定死的，
      // 折不了行 —— 窄屏 + 大字号 + 英文下「Schedule management」会超出去。
      appBar: AppBar(
          title: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(L10n.scheduleManagement))),
      body: async.isLoading && schedules.isEmpty
          ? const GlassLoading()
          : CenteredContent(
            child: ListView(
              // 底部让位：主操作改成**贴屏幕底部**的悬浮按钮条之后（见
              // `_bottomActionBar`），不留白的话列表最后一行会被它压住、
              // 删除键点不到。常量是 `kFloatingBarInset`（= 16 边距 + 56 条高
              // + 12 呼吸）—— **不是** `kFloatingActionInset`（160）：那一档多
              // 出来的 76 是给**底部导航胶囊**让位的，而这一页底下没有胶囊
              // （2026-10-15 用户报的「按钮偏高」就是按那一档摆的后果）。
              //
              // **要叠系统栏**：按钮条跟着手势条一起上移，测试视口都没有系统栏，
              // 这类错只能靠算式堵（叠 `MediaQuery.paddingOf` 而不是写死一个数）。
              //
              // **不给短屏/窄屏再叠一层 156**（闹钟页在那边叠了）：那一页是
              // **不滚动**的 Column（两段列表各自 Expanded），不留白正文就会被
              // 压住；这一页是**单一可滚列表**，`kFloatingBarInset` 已经够让
              // 最后一行滑到按钮条之上 —— 再叠 156 反而把最后一行顶出屏幕：实测
              // 200×400 下（一行 249 高、视口 344）叠完之后滑到底时最后一行只剩
              // 顶上 28px 露在屏里、它的删除键整个跑到视口上方去了，
              // `schedule_management_test.dart` 那条几何用例当场照出来。
              padding: EdgeInsets.fromLTRB(16, 8, 16,
                  MediaQuery.paddingOf(context).bottom + kFloatingBarInset),
              children: [
                // 两节各带一个标题（2026-09-30 用户反馈：「排班管理页面有点乱，
                // 应该分成两个功能区……现在它们连在一起，感觉有点混乱」）。
                // 标题在卡片**外面**、两节同一种写法 —— 一节有标题、另一节没有
                // 正是「连在一起」的来源。
                SectionHeading(L10n.scheduleTimeline),
                _TimelineSection(
                  schedules: schedules,
                  current: current,
                  spans: spans,
                ),
                const SizedBox(height: AppTokens.spaceMd),
                SectionHeading(L10n.schedulesSection),
                ...schedules.map((s) {
                  final isCurrent = s.id == current?.currentScheduleId;
                  return GlassTile(
                    translucentFill: false,
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
                            '${scheduleRoleLabel(s, spanCount: spanCountOf(spans, s.id), isCurrent: isCurrent, hasPeriods: spans.isNotEmpty)} · '
                            '${L10n.teamCountN(parseTeamNames(s.teamNames).length)} · '
                            // 按月那套印切法摘要，**不印基准日** —— 按月不用它
                            // （每月 1 号恒等于第一段），印出来是个不生效的值。
                            '${s.monthly ? L10n.scheduleMonthlySummary(monthSegCounts[s.id] ?? 0) : L10n.monthDay(s.anchorDate)}'
                            // 一个段都没有时左边的标签已经写着「正在使用」了，
                            // 尾巴上再挂一个「当前」是同一件事说两遍。
                            '${isCurrent && spans.isNotEmpty ? ' · ${L10n.current}' : ''}'),
                        trailing: GlassDeleteButton(
                          compact: true,
                          onPressed: () => _deleteSchedule(context, ref, s),
                        ),
                        onTap: () => _openEditor(context, ref, s.id),
                      ),
                    ),
                  );
                }),
              ],
            ),
            ),
      // 主操作与闹钟页同一套：底部悬浮按钮条 + 共用的落点。**但这一页底下没有
      // 底部导航胶囊**（它是 push 出来的整页），所以传 `aboveCapsule: false` ——
      // 按钮条贴屏幕底部，不再往上抬那 76。
      // **不是** `bottomNavigationBar` + `extendBody` —— 那是编辑器那颗
      // 「保存并重排闹钟」胶囊的路子（那边要正文铺到屏幕底）。这一页要的是
      // 「新建」在三个列表页里是同一个东西：待办页的 FAB、闹钟页的按钮条、
      // 这一页的按钮条。
      floatingActionButtonLocation:
          const AboveCapsuleLocation.bar(aboveCapsule: false),
      floatingActionButton: _bottomActionBar(context, ref),
    );
  }

  /// 底部按钮条：一颗通栏的「新增排班」。
  ///
  /// 从前它是 ListView 的**最后一个孩子** —— 只有一两套方案时它会悬在页面中间、
  /// 下面留一大片空白（用户看到的正是这个）。改成悬浮按钮条之后，页面再短、
  /// 主操作也稳稳贴在底部。
  Widget _bottomActionBar(BuildContext context, WidgetRef ref) {
    // 宽屏下正文被 `CenteredContent` 限宽 720 并居中，这条按钮条也要跟着那个栏宽
    // —— 不然它在 1280 的车机上从左边缘铺到右边缘（与闹钟页逐字同一条）。
    final contentW = math.min(
        MediaQuery.sizeOf(context).width, AppLayout.maxContentWidth.toDouble());
    return SizedBox(
      // 工装 / 用例量它落点的抓手。
      key: const Key('management-action-bar'),
      width: contentW - 32,
      height: 56,
      child: GlassButton(
        primary: true,
        icon: const Icon(Icons.add_outlined),
        onPressed: () => _addSchedule(context, ref),
        child: Text(L10n.addSchedule),
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
    final confirmed = await showGlassDialog<bool>(
      context: context,
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
      await _replanAlarms(ref);
    }
  }
}

/// 排班结构一变，「今天归哪套」跟着变 —— 日历立刻跟上，**原生闹钟与按班次的
/// 重复待办都不会**。所以这里不是只重排闹钟：先让生成器把按班次的「当前这一次」
/// 对齐，再整链重排（`AlarmService.replanAfterScheduleChange`）。
///
/// 换「其余时间」归属、增删改排班时段、删掉一套方案，都会让未来几十天里某些天的
/// 班次换成另一套（甚至换成「无」）。不重排闹钟的话，**旧计划里的班次闹钟照旧
/// 在原定时刻响**：用户 2026-10-18 真机反馈「今天是白班，晚上 19:30 却响了上夜班
/// 的闹钟」—— 就是切回本套方案时没重排，而旧方案（按月排班）里今天正是上夜班，
/// 那一条 19:30 的上夜班闹钟是更早一次重排留下的。
///
/// 与「编辑排班页保存」「日历调整班次」两条路保持一致：写库之后立刻整链重排。
/// 调用点都在**关窗之后**——那串原生调用真机上要几百毫秒，别让弹层陪着卡。
Future<void> _replanAlarms(WidgetRef ref) =>
    AlarmService.replanAfterScheduleChange(ref.read(appRepositoryProvider));

/// 排班管理页顶部那一节「排班时段」。
///
/// 形态与「其余时间」这个概念配套：**永远列出「其余时间」那一行**，没有段时就
/// 只有它 —— 所以不必为「有没有段」写两套版式（少一个要维护、要出图的状态）。
///
/// **但一个段都没有时，那一行的话要换**（2026-09-30）：没有「这一段」，「其余」
/// 就没有着落 —— 那句「其余时间 · 五班三倒」会被读成「这是默认的意思吗」。
/// 那一种情形整行写「全部日子」，说明也直说（见 `L10n.allDates*`）。
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
    final hasPeriods = spans.isNotEmpty;

    return GlassTile(
      translucentFill: false,
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasPeriods
                ? L10n.remainingHint
                : (remaining == null
                    ? L10n.allDatesNoneHint
                    : L10n.allDatesHint),
            style: AppTokens.rowSecondary.copyWith(color: muted),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          _row(
            context,
            label: hasPeriods ? L10n.remainingTime : L10n.allDates,
            value: remaining?.schedule.name ?? L10n.remainingNone,
            mutedValue: remaining == null,
            onTap: () => showRemainingPicker(context, ref,
                // 弹层标题跟着那一行的说法走：一个段都没有时写「全部日子」，
                // 否则「其余时间」（与行标签同源，别各写一份）。
                label: hasPeriods ? L10n.remainingTime : L10n.allDates),
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

  /// 时间线上的一行：[左边是日期 / 「其余时间」] + [右边它指向的方案名] + 箭头。
  ///
  /// 实现见文件末尾的 [_labelValueRow]（时段弹层里那行也用它 —— 两处同一份）。
  Widget _row(
    BuildContext context, {
    required String label,
    required String value,
    required bool mutedValue,
    required VoidCallback onTap,
  }) =>
      _labelValueRow(context,
          label: label, value: value, mutedValue: mutedValue, onTap: onTap);
}

/// 「其余时间」（一个段都没有时是「全部日子」）用哪一套 —— 选一套，或者「无」。
///
/// 「无」是这个模型里**唯一**能到达「没有默认」的入口（删掉一套方案时仍然自动
/// 把其余时间交给列表里的第一套，否则删掉默认那套会让整张日历变空）。
Future<void> showRemainingPicker(
  BuildContext context,
  WidgetRef ref, {
  String? label,
}) async {
  final schedules = await ref.read(schedulesProvider.future);
  if (!context.mounted) return;
  final currentId =
      ref.read(activeScheduleProvider).valueOrNull?.currentScheduleId;

  await showGlassDialog<void>(
    context: context,
    builder: (dialogContext) => GlassDialog(
      title: label ?? L10n.remainingTime,
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
                await _replanAlarms(ref);
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
              await _replanAlarms(ref);
            },
          ),
        ],
      ),
      actions: [
        GlassActionButton(
          // `dialogCloser` **返回**闭包，所以这里直接把它当成 `onPressed`。
          // **别写成 `() => dialogCloser(context)`** —— 那等于把闭包造出来又扔掉，
          // 点了没反应（Dart 允许「返回函数的函数」赋给 `void Function()`，所以
          // 既编译得过、也不报错）。v0.9.14 这一节就是栽在这上面。
          onPressed: dialogCloser(dialogContext),
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

  await showGlassDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) => GlassDialog(
        title: existing == null ? L10n.addSpan : spanRangeLabel(from, to),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 与时间线上那几行**同一份**实现（`_labelValueRow`）：标签走
            // `rowPrimary`（14/w500）—— 打开这个弹层的那一行也是它。此前这里是
            // `ListTile` + `rowSecondary`（13/w400），两个毛病叠在一起：字小一档
            // （用户 2026-10-01 反馈「字体有点小」），而且**窄弹层里 ListTile 的
            // trailing 会吃掉整行宽度、当场抛断言** —— 后者是补进屏单当天抓到的
            // （200×400 那一屏）。
            _labelValueRow(
              dialogContext,
              label: L10n.schedule,
              value: picked.name,
              mutedValue: false,
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
          // 三颗钮的间隔**得自己给**（`GlassDialog` 的 actions 是一个光秃秃的
          // `Row`，它不插间隔）—— 全仓其余弹窗都写了这一行，这一节当初漏了，
          // 真机上三颗钮贴着，用户直接反馈「间隔太紧凑」（2026-09-30）。
          if (existing != null) ...[
            GlassActionButton(
              variant: GlassActionVariant.danger,
              label: L10n.delete,
              onPressed: () async {
                await ref.read(appRepositoryProvider).deleteSpan(existing.id);
                // `dialogCloser` **返回**闭包（用法是 `onPressed: dialogCloser(ctx)`）——
                // 这里在 await 之后调，所以要再 () 一下才真的关窗。
                if (dialogContext.mounted) dialogCloser(dialogContext)();
                await _replanAlarms(ref);
              },
            ),
            const SizedBox(width: 8),
          ],
          GlassActionButton(
            onPressed: dialogCloser(dialogContext),
            label: L10n.cancel,
          ),
          const SizedBox(width: 8),
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
              await _replanAlarms(ref);
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
  // 与时间线、与同一个弹层里「排班」那行**同一份**实现（`_labelValueRow`）。
  //
  // 这里原来是 `ListTile` + 一排 `trailing`（日期 + 清空钮）—— 同样的两个毛病：
  // 窄弹层里 `ListTile` 先吃掉 `minLeadingWidth` + `horizontalTitleGap` 那 56，
  // 剩下给 trailing 的放不下，**200×400 那一屏实测溢出 23px**（补进屏单当天抓到）。
  return _labelValueRow(
    context,
    label: label,
    value: value == null ? emptyText : L10n.monthDay(value),
    mutedValue: value == null,
    onTap: () async {
      final picked = await showGlassDatePicker(
        context,
        initialDate: value ?? dateOnly(DateTime.now()),
      );
      if (picked != null) onChanged(picked);
    },
    // 有值时给一颗清空钮（「留空 = 不限」是这一行的第二个动作）；没值时回到默认箭头。
    trailing: value == null
        ? null
        : IconButton(
            onPressed: () => onChanged(null),
            icon: const Icon(Icons.close_outlined),
            iconSize: AppTokens.iconSm,
            color: muted,
          ),
  );
}

/// 「左边一个标签、右边一个取值、尾巴一个箭头」的一行 —— **手搓 `Row` 而不是
/// `ListTile`**。
///
/// 为什么不用 `ListTile`：它的 `trailing` 在窄窗口里会**吃掉整行宽度** ——
/// `minLeadingWidth`（默认 40）与 `horizontalTitleGap`（默认 16）先拿走一块，
/// 再给 trailing 一个 `ConstrainedBox(maxWidth: 140)`，200 宽的弹层里就超了，
/// 框架直接抛 `Trailing widget consumes the entire tile width`。手搓这版两边都是
/// flex（`Expanded` + `Flexible`）、各自省略号，任何宽度都不溢。
///
/// 这条是**两次踩出来的**：先是排班管理页那条时间线（v0.9.14 工装的小窗那一屏
/// 红了），再是时段弹层里那行 —— 后者到 2026-10-01 才现形，因为那一屏此前**根本
/// 不在屏单里**（补上 `33_span_editor` 的当天它就抛了断言）。
///
/// 点击用 `GestureDetector` 承载（`GlassPressable` **没有 `onTap`**，它只是个
/// 按压缩放的包装）—— 与日历信息卡那行班次同一套写法。
Widget _labelValueRow(
  BuildContext context, {
  required String label,
  required String value,
  required bool mutedValue,
  required VoidCallback onTap,
  Widget? trailing,
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
              // 标签允许折两行（设计 §6.4）：这一行**不允许**出现省略号。
              child: Text(label,
                  maxLines: 2, style: AppTokens.rowPrimary),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            Flexible(
              // 值按可用宽度**等比缩小**，不省略 —— 它短、且是这一行的主角。
              // `FittedBox(scaleDown)` 只在装不下时才动手，装得下逐像素不变。
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: mutedValue
                      ? AppTokens.rowSecondary.copyWith(color: muted)
                      : AppTokens.labelStrong,
                ),
              ),
            ),
            const SizedBox(width: AppTokens.gapIconText),
            // 默认给一个「点进去」的箭头；时段那两行传自己的尾部（有值时是清空钮）。
            trailing ??
                Icon(Icons.chevron_right_outlined,
                    size: AppTokens.iconSm, color: muted),
          ],
        ),
      ),
    ),
  );
}
