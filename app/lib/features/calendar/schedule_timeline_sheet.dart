// app/lib/features/calendar/schedule_timeline_sheet.dart
//
// 「排班时段」只读总览：这段时间在用哪套、今天落在哪一段。
//
// 从 `calendar_screen.dart` 的私有方法原样搬出来（行为一字未改）—— 日历顶栏
// 那颗按钮已经换成「统计」，这个弹层改由统计页头部「使用中：<方案名> ›」打开。
// 总览仍然只读：要改时段去排班管理页那条时间线。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_sheet_header.dart';
import '../../data/app_repository.dart';
import '../../domain/shift_rotation.dart';
import 'schedule_management_screen.dart';
import 'schedule_span_label.dart';

Future<void> showScheduleTimelineSheet(
    BuildContext context, WidgetRef ref) async {
  final schedules = await ref.read(schedulesProvider.future);
  final spans = await ref.read(scheduleSpansProvider.future);
  if (!context.mounted) return;
  final current = ref.read(activeScheduleProvider).valueOrNull;
  final remaining = current?.current;
  final today = dayNumber(dateOnly(appNow()));

  // 今天落在哪一段上（段之间不重叠，所以至多一段）—— 给那一行打勾。
  int? todaySpanId;
  for (final s in spans) {
    final from = s.startDate == null ? null : dayNumber(s.startDate!);
    final to = s.endDate == null ? null : dayNumber(s.endDate!);
    if ((from == null || today >= from) && (to == null || today <= to)) {
      todaySpanId = s.id;
      break;
    }
  }
  final byId = {for (final s in schedules) s.id: s};
  final hasPeriods = spans.isNotEmpty;

  await showGlassSheet<void>(
    context: context,
    builder: (sheetContext) => GlassPanel(
      solid: true,
      margin: const EdgeInsets.all(12),
      borderRadius: const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // **`stretch` 而不是 `start`。** 头部下面那块内容自带一圈
          // `Padding(all: 16)`，而 `start` 给子件的是**松宽度约束** —— ListView
          // （视口）会一路撑到 `maxWidth`、Padding 再给它加出左右各 16，直接横向
          // 溢出。`stretch` 给的是紧宽度，Padding 减掉 32 之后才是 ListView 该有的宽。
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部走共享件（把手 + 主色竖条 + 标题 + 分隔线）。
            //
            // ⚠️ **那圈 16 的 padding 只能包住头部以下的内容，不能包住整个
            // Column**（本轮修的就是它）。原来它包在最外层，于是 `GlassSheetHeader`
            // 被**二次内缩**：分隔线比另外四个弹层窄 16dp、把手低 16dp、标题也跟着
            // 与下面的行错开 —— 「五处统一头部」只成四成不算成。
            GlassSheetHeader(
              title: L10n.scheduleTimeline,
              // 说法与排班管理页那条时间线**同源**：一个段都没有时不说「其余
              // 时间」（没有「这一段」，「其余」就没有着落），整行写「全部
              // 日子」。两处各写一份的话，同一个状态会有两种解释。
              subtitle: hasPeriods
                  ? L10n.remainingHint
                  : (remaining == null
                      ? L10n.allDatesNoneHint
                      : L10n.allDatesHint),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.spaceLg),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _timelineLine(
                      sheetContext,
                      label: hasPeriods ? L10n.remainingTime : L10n.allDates,
                      value: remaining?.schedule.name ?? L10n.remainingNone,
                      mutedValue: remaining == null,
                      // 今天没落在任何段上 → 今天归「其余时间」。
                      isToday: todaySpanId == null,
                    ),
                    for (final s in spans)
                      _timelineLine(
                        sheetContext,
                        label: spanRangeLabel(s.startDate, s.endDate),
                        value: byId[s.scheduleId]?.name ?? L10n.remainingNone,
                        mutedValue: byId[s.scheduleId] == null,
                        isToday: s.id == todaySpanId,
                      ),
                    const Divider(height: 1),
                    GlassPressable(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(L10n.manageTimeline),
                        trailing: const Icon(Icons.chevron_right_outlined,
                            key: Key('manage-timeline-chevron')),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) =>
                                  const ScheduleManagementScreen()));
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 总览里的一行：左边的勾（今天所在的那一段）+ 日期 / 「其余时间」 + 方案名。
///
/// 两边都是 flex、各自省略号 —— 与排班管理页那一节同一套写法（`ListTile` 的
/// `trailing` 在 200dp 小窗下会横向溢出）。
Widget _timelineLine(
  BuildContext context, {
  required String label,
  required String value,
  required bool mutedValue,
  required bool isToday,
}) {
  final muted = AppTokens.inkMuted(context);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
    child: Row(
      children: [
        SizedBox(
          width: AppTokens.iconMd,
          child: isToday
              ? AppIcon(Icons.check_circle_outlined,
                  size: AppTokens.iconMd,
                  color: Theme.of(context).colorScheme.primary)
              : null,
        ),
        const SizedBox(width: AppTokens.gapIconText),
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
      ],
    ),
  );
}
