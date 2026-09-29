/// 星期多选：一排七个胶囊，点一下 toggle 一位。
///
/// [value] 是位掩码 `1 << (weekday - 1)`（周一 = 1），与 `DateTime.weekday`、
/// `CustomAlarms.weekdays`、`RecurringTodo.weekdays` 同一约定 —— **四处同序是
/// 这套东西能对上的前提**，所以位序只写在这里一次，调用点不许自己移位。
///
/// 重复待办弹窗（「每周」）与自定义闹钟弹窗（「每周」）共用它。抽出来之前它是
/// `alarm_screen.dart` 弹窗里内联的一段 —— 待办弹窗再抄一份就是第二份实现，
/// 而这类配方抄歪了**不会报错**：只是某个星期永远选不上。
///
/// **它自己发触觉**（`Haptics.select()`，语义是「选中变了」）：词汇表里
/// 「选项胶囊选中」本来就在 `select()` 那一档，而最近的同类件 `GlassChoiceChip`
/// 正是这么做的。所以**调用点不许再补一记** —— 一次操作震两下比一下信息量更少。
library;

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../haptics.dart';
import '../l10n.dart';

class GlassWeekdayPicker extends StatelessWidget {
  const GlassWeekdayPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// 位掩码：`1 << (weekday - 1)`，周一 = 1。
  final int value;

  /// 新的掩码。
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: AppTokens.gapIconText,
      children: List.generate(7, (i) {
        final bit = 1 << i;
        final selected = (value & bit) != 0;
        return GestureDetector(
          onTap: () {
            Haptics.select();
            onChanged(selected ? value & ~bit : value | bit);
          },
          child: AnimatedContainer(
            duration: AppTokens.durMed,
            curve: Curves.easeOutBack,
            padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMd, vertical: AppTokens.spaceSm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.radiusL),
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.72)),
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white.withValues(alpha: isDark ? 0.16 : 0.65),
              ),
            ),
            child: Text(
              L10n.weekday(i),
              // 基线 13px：未选中 w500、选中 w700（与 `alarm_screen` 原来那段同值）。
              style: AppTokens.labelSecondary.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        );
      }),
    );
  }
}
