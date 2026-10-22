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
import '../../core/haptics.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_choice_chip.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_segment.dart';
import '../../core/widgets/glass_switch.dart';
import '../../core/widgets/glass_weekday_picker.dart';
import '../../domain/recurring_todo.dart';
import '../../domain/shift_rotation.dart' show formatClock, ShiftClass;

/// 规则的一组值：周期 + 星期掩码 + 每月掩码 + 按班次的名字。
///
/// 抽成值对象是因为回调从三个参数长到了四个 —— 参数汤容易让两个调用点各记错
/// 一个位置，而这类错误**不会报错**（只是某个星期 / 某一天永远选不上）。
class RecurRuleValue {
  const RecurRuleValue({
    required this.repeat,
    this.weekdays = 0,
    this.monthDays = 0,
    this.shiftNames = const [],
  });

  /// null = 不重复。
  final RecurRepeat? repeat;

  /// 每周的位掩码（`1 << (weekday - 1)`）。
  final int weekdays;

  /// 每月选中的日子（1..31 的位掩码）。
  final int monthDays;

  /// 按班次：选中的班次名字（`ShiftClass.name`）。
  final List<String> shiftNames;

  RecurRuleValue copyWith({
    RecurRepeat? repeat,
    int? weekdays,
    int? monthDays,
    List<String>? shiftNames,
  }) =>
      RecurRuleValue(
        repeat: repeat ?? this.repeat,
        weekdays: weekdays ?? this.weekdays,
        monthDays: monthDays ?? this.monthDays,
        shiftNames: shiftNames ?? this.shiftNames,
      );
}

class RecurringRulePicker extends StatelessWidget {
  const RecurringRulePicker({
    super.key,
    required this.value,
    required this.shiftChoices,
    required this.fallbackDay,
    required this.fallbackShiftName,
    required this.onChanged,
    this.validationMessage,
  });

  final RecurRuleValue value;

  /// 当前排班链上「从今天起还可能生效」的班次（`classChoicesFrom`）。
  final List<ShiftClass> shiftChoices;

  /// 切到「每周 / 每月 / 按班次」而还没有选择时，默认按哪一天补。
  ///
  /// 待办弹窗传当前选中日期、系列编辑器传今天 —— 两者都只是「先给一个，
  /// 用户再改」。**空掩码 / 空名字是脏数据**：生成器一条都不生成，而界面上
  /// 看不出任何异常。
  final DateTime fallbackDay;

  /// [fallbackDay] 那天我们班组的班次名；没有班表时为 null。
  final String? fallbackShiftName;

  final ValueChanged<RecurRuleValue> onChanged;

  /// 保存被挡下时显示的一行提示（由调用点在点「保存」后传入）。
  final String? validationMessage;

  void _select(int i) {
    final next = i == 0 ? null : RecurRepeat.values[i - 1];
    var w = value.weekdays;
    var m = value.monthDays;
    var names = value.shiftNames;
    if (next == RecurRepeat.weekly && w == 0) {
      w = 1 << (fallbackDay.weekday - 1);
    }
    if (next == RecurRepeat.monthly && m == 0) {
      m = 1 << (fallbackDay.day - 1);
    }
    if (next == RecurRepeat.shift && names.isEmpty) {
      final choiceNames = {for (final c in shiftChoices) c.name};
      final fallback = fallbackShiftName;
      if (fallback != null && choiceNames.contains(fallback)) {
        names = [fallback];
      } else if (shiftChoices.isNotEmpty) {
        names = [shiftChoices.first.name];
      }
    }
    onChanged(RecurRuleValue(
        repeat: next, weekdays: w, monthDays: m, shiftNames: names));
  }

  void _toggleShift(String name) {
    final next = [...value.shiftNames];
    if (next.contains(name)) {
      // **不许清空到最后一项**：空名字的规则一条都不生成，而界面上看不出来。
      if (next.length == 1) return;
      next.remove(name);
    } else {
      next.add(name);
    }
    onChanged(value.copyWith(shiftNames: next));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 与闹钟弹窗的「一次性 / 每天 / 每周」同一个控件、同一套字重规则
        // （选中 w700、未选中 w500）。
        //
        // 五档之后每格只占约 56dp，英文「Does not repeat」缩到 0.6 倍也只有
        // 8px 高 —— 所以 `repeatNone` 的英文改成了 `Never`（中文不变）。
        GlassSegment(
          count: 5,
          selectedIndex: value.repeat == null ? 0 : value.repeat!.index + 1,
          onSelected: _select,
          itemBuilder: (i, selected) => FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              [
                L10n.repeatNone,
                L10n.repeatDaily,
                L10n.repeatWeekly,
                L10n.repeatMonthly,
                L10n.repeatShift,
              ][i],
              style: AppTokens.labelSecondary.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
        if (value.repeat == RecurRepeat.weekly)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
            child: GlassWeekdayPicker(
              value: value.weekdays,
              // **这里不补触觉**：控件自己已经发了一记（`Haptics.select()`），
              // 调用点再补就是一次操作震两下 —— 两下比一下信息量更少。
              onChanged: (v) => onChanged(value.copyWith(weekdays: v)),
            ),
          ),
        if (value.repeat == RecurRepeat.monthly)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MonthDayGrid(
                  value: value.monthDays,
                  onChanged: (v) => onChanged(value.copyWith(monthDays: v)),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      L10n.monthDaysHint,
                      style: AppTokens.microText
                          .copyWith(color: AppTokens.inkMuted(context)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (value.repeat == RecurRepeat.shift) _buildShift(context),
        if (validationMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.spaceSm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                validationMessage!,
                style: AppTokens.microText
                    .copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
      ],
    );
  }

  /// 「按班次」那一块：班次 chips + 匹配口径说明 + 缺名提示。
  Widget _buildShift(BuildContext context) {
    final choiceNames = {for (final c in shiftChoices) c.name};
    final missing = [
      for (final n in value.shiftNames)
        if (!choiceNames.contains(n)) n,
    ];
    final muted = AppTokens.inkMuted(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (shiftChoices.isNotEmpty || missing.isNotEmpty)
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              children: [
                for (final c in shiftChoices)
                  GlassChoiceChip(
                    label: c.name,
                    color: Color(c.color),
                    selected: value.shiftNames.contains(c.name),
                    onTap: () => _toggleShift(c.name),
                  ),
                // 选过、但当前排班表里找不到的班次也要显示出来（否则用户不知道
                // 自己选的是哪一条），用错误色 + 缺名提示一起说清楚。
                for (final n in missing)
                  GlassChoiceChip(
                    label: n,
                    color: Theme.of(context).colorScheme.error,
                    selected: true,
                    onTap: () => _toggleShift(n),
                  ),
              ],
            ),
          if (shiftChoices.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceXs),
              child: Text(
                L10n.shiftRuleNoSchedule,
                style: AppTokens.microText.copyWith(color: muted),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.spaceXs),
            child: Text(
              L10n.shiftRuleHint,
              style: AppTokens.microText.copyWith(color: muted),
            ),
          ),
          if (missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceXs),
              child: Text(
                L10n.shiftRuleMissing(missing),
                style: AppTokens.microText
                    .copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
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

/// 每月多选的 31 格网格（7 列 × 5 行）。
///
/// **点掉最后一个已选项不生效**：空月日的规则一条都不生成，而界面上完全看不出
/// 异常（与「每周」那边遗留的允许清空不同，这一档从第一天就守住）。
/// 交接给调用点之前自己做三维度判断 —— 触觉也只在这里发一记（`Haptics.select()`）。
class _MonthDayGrid extends StatelessWidget {
  const _MonthDayGrid({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  void _toggle(int day) {
    final bit = 1 << (day - 1);
    final isOn = (value & bit) != 0;
    final next = isOn ? value & ~bit : value | bit;
    if (isOn && next == 0) return;
    Haptics.select();
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < 5; row++)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : AppTokens.spaceXs),
            child: Row(
              children: [
                for (var col = 0; col < 7; col++) ...[
                  if (col > 0) const SizedBox(width: 4),
                  Expanded(
                    child: Builder(builder: (context) {
                      final day = row * 7 + col + 1;
                      if (day > 31) return const SizedBox.shrink();
                      final selected = (value & (1 << (day - 1))) != 0;
                      return GestureDetector(
                        onTap: () => _toggle(day),
                        child: AnimatedContainer(
                          duration: AppTokens.durMed,
                          curve: Curves.easeOutBack,
                          padding: const EdgeInsets.symmetric(
                              vertical: AppTokens.spaceSm),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusS),
                            color: selected
                                ? primary
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.white.withValues(alpha: 0.72)),
                            border: Border.all(
                              color: selected
                                  ? primary
                                  : Colors.white
                                      .withValues(alpha: isDark ? 0.16 : 0.65),
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$day',
                              style: AppTokens.labelSecondary.copyWith(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
