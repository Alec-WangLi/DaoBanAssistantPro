// 「重复待办」的**系列编辑器**。
//
// 为什么需要它：待办列表里那条重复待办编的是**「当前这一次」**（顺带把标题 /
// 规则写回系列）。但系列是按规则到点才生成那一行的 —— 每月 1 号的系列，在 1 号
// 之前列表里什么都没有，于是**没有入口可点**。2026-10-21 用户真机就是这么卡住的：
// 「已添加的重复待办，它不能修改，也找不到编辑」。面板里那一行当时只弹一句
// 「这个重复现在没有『下一次』」，不给编辑。
//
// 这个弹窗直接编系列本身，**不依赖有没有当前这一次**：
//   · 有当前这一次：保存时连同那一条一起更新，并把它对齐到新规则的最近一次；
//   · 没有：只改系列，下次到点按新规则出现。
//
// 「开始日期」有意不放进这个弹窗：它只决定第一次出现的那道闸门，用户这一轮
// 要改的是标题与规则；放进来反而会与「当前这一次」的日期混淆。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_field.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/l10n.dart';
import '../../data/app_repository.dart';
import '../../domain/recurring_todo.dart';
import '../../domain/shift_rotation.dart';
import '../alarm/alarm_service.dart';
import 'recurring_fields.dart';

/// 打开一个系列的编辑器。面板里点任意一行都走这里。
Future<void> showRecurringSeriesEditor(
    BuildContext context, RecurringTodo series) {
  return showGlassDialog<void>(
    context: context,
    builder: (_) => _SeriesEditor(series: series),
  );
}

class _SeriesEditor extends ConsumerStatefulWidget {
  const _SeriesEditor({required this.series});

  final RecurringTodo series;

  @override
  ConsumerState<_SeriesEditor> createState() => _SeriesEditorState();
}

class _SeriesEditorState extends ConsumerState<_SeriesEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.series.title);
  late RecurRepeat? _repeat = widget.series.repeat;
  late int _weekdays = widget.series.weekdays;
  late int _monthDay = widget.series.monthDay;
  late int? _timeMinute = widget.series.timeMinute;
  late int? _advance = widget.series.advanceRemindMinutes;
  late bool _alarm = widget.series.alarmEnabled;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// 保存：写系列 → 生成器把「当前这一次」补出来 → 对齐到新规则最近一次。
  ///
  /// 对齐这一步**生成器不会替我们做**：它只往前顺延、永不回退，而「每周三改成
  /// 每周五」要回退到本周之前的那个周五（与待办编辑弹窗的 `_EventFields.commit`
  /// 同一条理由、同一套做法）。
  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final repo = ref.read(appRepositoryProvider);
    final id = widget.series.id!;

    if (_repeat == null) {
      // 「以后不再重复」：解绑并删系列定义，已经出现的行都留着（与待办编辑弹窗
      // 同一语义 —— 用户要的是「别再自动出现」，不是「把这条待办删掉」）。
      await repo.unlinkRecurringSeries(id);
    } else {
      // 规则有没有真的变 —— 只有变了才把「当前这一次」对齐到新规则。
      // 只改标题 / 时间时对齐会把用户手工挪过的这一次（这周的会挪到周五）
      // 拽回规则上的日子，而用户并没有要求改规则。
      final ruleChanged = _repeat != widget.series.repeat ||
          _weekdays != widget.series.weekdays ||
          _monthDay != widget.series.monthDay;
      await repo.updateRecurringTodo(RecurringTodo(
        id: id,
        title: title,
        repeat: _repeat!,
        // 起点原样带过去（`copyWith` 清不掉可空字段，这里同样显式构造）。
        startDate: widget.series.startDate,
        timeMinute: _timeMinute,
        advanceRemindMinutes: _advance,
        alarmEnabled: _alarm,
        weekdays: _weekdays,
        monthDay: _monthDay,
        skipThrough: widget.series.skipThrough,
        enabled: widget.series.enabled,
      ));
      final today = dateOnly(DateTime.now());
      // 规则换了之后「当前这一次」可能根本不存在（比如从每月 1 号改成每周三，
      // 而最近一个周三已经过去）—— 这一步把它补出来。
      await repo.advanceRecurringTodos(today: today);
      final s =
          (await repo.listRecurringTodos()).firstWhere((x) => x.id == id);
      final occ =
          ruleChanged ? occurrenceOnOrBefore(s, today) : null;
      for (final r in (await repo.listEvents())
          .where((e) => e.seriesId == id && !e.isCompleted)) {
        await repo.updateEvent(
          r,
          title: title,
          // `occ` 为空 = 规则没动，日期保持原样（可能正是用户手工挪过的那天）。
          date: occ ?? r.date,
          timeMinute: _timeMinute,
          advanceRemindMinutes: _advance,
          alarmEnabled: _alarm,
          seriesId: id,
        );
      }
    }

    await AlarmService.rescheduleAll(repo);
    ref.invalidate(recurringTodosProvider);
  }

  @override
  Widget build(BuildContext context) {
    final close = dialogCloser(context);
    return GlassDialog(
      title: L10n.editRecurring,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassField(
            label: L10n.title,
            child: TextField(
              controller: _title,
              // 不自动聚焦：从面板进来通常是想改规则，键盘一弹就把下面几行盖住了。
              minLines: 1,
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              decoration: glassInputDecoration(context),
            ),
          ),
          const SizedBox(height: 12),
          RecurringRulePicker(
            repeat: _repeat,
            weekdays: _weekdays,
            monthDay: _monthDay,
            // 掩码为空时先勾今天（脏数据会让生成器一条都不生成）。
            fallbackWeekday: DateTime.now().weekday,
            onChanged: (r, w, m) => setState(() {
              _repeat = r;
              _weekdays = w;
              _monthDay = m;
            }),
          ),
          EventTimingPicker(
            timeMinute: _timeMinute,
            advance: _advance,
            alarm: _alarm,
            onChanged: (t, a, link) => setState(() {
              _timeMinute = t;
              _advance = a;
              _alarm = link;
            }),
          ),
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
            await _save();
            close();
          },
          label: L10n.save,
        ),
      ],
    );
  }
}
