// 「重复规则」与「时间 / 提醒 / 联动闹钟」这两组字段。
//
// **两份实现共用同一份**：
//   · 待办的新建 / 编辑弹窗（`schedule_screen.dart` 的 `_EventFields`）；
//   · 「重复待办」面板点进去的系列编辑器（`recurring_series_editor.dart`）。
//
// 抄两遍的代价是走样：v0.7.1 就在「添加 / 编辑」两个待办弹窗上栽过一次 ——
// 提醒档位只改了其中一处，另一处静默停在旧行为。这两组里各有一条容易漏的耦合：
//   · 切换「每周」时要把空的星期掩码补成一天，否则生成器把系列当脏数据、
//     一条都不生成，而界面上完全看不出来；
//   · 提醒改成「不设」时必须顺手把联动闹钟关掉 —— 不然开关开着却没有可响的
//     时刻，用户会以为它会响（而它永远不会）。
// 所以两条耦合都只留在这一处。
//
// 两个件都**不持有状态**：值由调用点给，改动经回调一次性回传完整的一组值。
// 状态留在弹窗那一层，是因为保存时要把这几样与标题一起提交。
import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_segment.dart';
import '../../core/widgets/glass_switch.dart';
import '../../core/widgets/glass_weekday_picker.dart';
import '../../domain/recurring_todo.dart';
import '../../domain/shift_rotation.dart' show formatClock;

class RecurringRulePicker extends StatelessWidget {
  const RecurringRulePicker({
    super.key,
    required this.repeat,
    required this.weekdays,
    required this.monthDays,
    required this.fallbackWeekday,
    required this.onChanged,
  });

  /// null = 不重复。
  final RecurRepeat? repeat;

  /// 每周的位掩码（`1 << (weekday - 1)`）。
  final int weekdays;

  /// 每月选中的日子（1..31 的位掩码）。
  final int monthDays;

  /// 切到「每周」而掩码还是空的时候，默认勾哪一天（1 = 周一）。
  ///
  /// 待办弹窗传当前选中日期、系列编辑器传今天 —— 两者都只是「先给一天，
  /// 用户再改」。**掩码为空是脏数据**：`occurrenceOnOrBefore` 返回 null，
  /// 生成器一条都不生成，界面上看不出任何异常。
  final int fallbackWeekday;

  final void Function(RecurRepeat? repeat, int weekdays, int monthDays) onChanged;

  /// 多选网格之前的过渡：旧版「每月」是单选，这里取掩码里最小的那一天显示。
  /// 多选网格在下一轮替换掉这段 ListTile。
  int get _monthDayShown {
    for (var d = 1; d <= 31; d++) {
      if ((monthDays & (1 << (d - 1))) != 0) return d;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 与闹钟弹窗的「一次性 / 每天 / 每周」同一个控件、同一套字重规则
        // （选中 w700、未选中 w500）。
        GlassSegment(
          count: 4,
          selectedIndex: repeat == null ? 0 : repeat!.index + 1,
          onSelected: (i) {
            final next = i == 0 ? null : RecurRepeat.values[i - 1];
            var w = weekdays;
            if (next == RecurRepeat.weekly && w == 0) {
              w = 1 << (fallbackWeekday - 1);
            }
            onChanged(next, w, monthDays);
          },
          itemBuilder: (i, selected) => FittedBox(
            // 英文「Does not repeat」在 320dp × 大字号下比一格还宽 —— 直接交给
            // `Text` 会被容器裁短（字号护栏抓的就是这一种）。与 v0.11.12 收
            // 字号档位那一处同一条做法：按宽缩小，不省略、不裁。
            fit: BoxFit.scaleDown,
            child: Text(
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
        ),
        if (repeat == RecurRepeat.weekly)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
            child: GlassWeekdayPicker(
              value: weekdays,
              // **这里不补触觉**：控件自己已经发了一记（`Haptics.select()`），
              // 调用点再补就是一次操作震两下 —— 两下比一下信息量更少。
              onChanged: (v) => onChanged(repeat, v, monthDays),
            ),
          ),
        if (repeat == RecurRepeat.monthly)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(L10n.repeatMonthly),
            trailing: Text('$_monthDayShown'),
            onTap: () async {
              final picked = await showGlassOptionPicker<int>(
                context,
                title: L10n.repeatMonthly,
                options: [for (var d = 1; d <= 31; d++) d],
                labelOf: (d) => '$d',
                selected: _monthDayShown,
              );
              if (picked != null) {
                onChanged(repeat, weekdays, 1 << (picked - 1));
              }
            },
          ),
      ],
    );
  }
}

/// 「时间（可选）」「提醒（可选）」「联动闹钟」这三行。
///
/// 与 [RecurringRulePicker] 一样由两个弹窗共用，理由见文件头。
class EventTimingPicker extends StatelessWidget {
  const EventTimingPicker({
    super.key,
    required this.timeMinute,
    required this.advance,
    required this.alarm,
    required this.onChanged,
  });

  /// 分钟自午夜；null = 没设时间。
  final int? timeMinute;

  /// 提醒档位：null = 不设，0 = 准时，其余为提前的分钟数。
  final int? advance;

  /// 到点走**闹钟**（全屏 + 循环铃声）而不是只弹一条通知。
  final bool alarm;

  /// 三样一起回传 —— 「不设提醒就关掉联动闹钟」那条耦合因此只在这一处。
  final void Function(int? timeMinute, int? advance, bool alarm) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(L10n.timeOptional),
          trailing: Text(timeMinute == null ? L10n.none : formatClock(timeMinute!)),
          onTap: () async {
            final p = await showGlassTimePicker(
              context,
              initialTime: timeMinute == null
                  ? TimeOfDay.now()
                  : TimeOfDay(
                      hour: timeMinute! ~/ 60, minute: timeMinute! % 60),
            );
            if (p != null) onChanged(p.hour * 60 + p.minute, advance, alarm);
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
            if (picked < 0) {
              // 「不设」的意思就是别提醒我 —— 联动闹钟跟着关掉。不然开关开着、
              // 却没有可响的时刻，用户会以为它会响（而它永远不会）。
              onChanged(timeMinute, null, false);
            } else {
              onChanged(timeMinute, picked, alarm);
            }
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(L10n.linkAlarm),
          subtitle: Text(L10n.linkAlarmHint),
          trailing: GlassSwitch(
            value: alarm,
            onChanged: (v) {
              // 开着闹钟就得有个可响的时点：提醒是「不设」时自动补成「准时」。
              onChanged(timeMinute, v ? (advance ?? 0) : advance, v);
            },
          ),
        ),
      ],
    );
  }
}
