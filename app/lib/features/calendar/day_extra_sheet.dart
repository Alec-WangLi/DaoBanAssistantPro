// app/lib/features/calendar/day_extra_sheet.dart
//
// 「请假 / 加班」时长选择层 —— 与「调整班次」同一个玻璃弹层配方。
//
// 为什么不用输入框：底部弹层里的 TextField 会被软键盘盖住，而这里只需要
// 「几个常见档 + 30 分钟加减」，既少一层键盘、也不用背 `viewInsets` 那套坑。
//
// 返回值：`null` = 取消；`DayExtraSelection.fullDay()` = 按每天班次时长算；
// `.minutes(n)` = 每天 n 分钟；`.clear()` = 清除已有记录。
import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_choice_chip.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_pill.dart';
import '../../core/widgets/glass_sheet_header.dart';
import '../../domain/day_extra.dart';
import '../../domain/shift_rotation.dart';

/// 弹层的结果。`minutes == 0 && !clear` 表示「整天」（按每天各自的班次时长算）。
class DayExtraSelection {
  const DayExtraSelection.minutes(this.minutes) : clear = false;
  const DayExtraSelection.fullDay()
      : minutes = 0,
        clear = false;
  const DayExtraSelection.clear()
      : minutes = 0,
        clear = true;

  final int minutes;
  final bool clear;

  bool get isFullDay => !clear && minutes == 0;
}

/// 弹「请假 / 加班」时长选择层。
///
/// [existingMinutes] 是**单日**已有记录的分钟数（多天时传 null）；[hasExisting]
/// 为真时底部出现「清除」。 [fullDayMinutes] 是单日班次时长，用来给「整天 / 半天」
/// 一个默认值；多天时为 null，界面上「整天」仍可选，写库时逐天算。
Future<DayExtraSelection?> showDayExtraSheet(
  BuildContext context, {
  required DayExtraKind kind,
  required DateTime from,
  required DateTime to,
  required int dayCount,
  int? existingMinutes,
  int? fullDayMinutes,
  bool hasExisting = false,
}) {
  final range = isSameDay(from, to)
      ? L10n.monthDay(from)
      : '${L10n.monthDay(from)} – ${L10n.monthDay(to)}';
  return showGlassSheet<DayExtraSelection>(
    context: context,
    // 与四个选择器同理：不开这个开关，弹层会被压到屏幕的 9/16。
    isScrollControlled: true,
    builder: (sheetContext) => _DayExtraSheet(
      kind: kind,
      range: range,
      dayCount: dayCount,
      existingMinutes: existingMinutes,
      fullDayMinutes: fullDayMinutes,
      hasExisting: hasExisting,
    ),
  );
}

class _DayExtraSheet extends StatefulWidget {
  const _DayExtraSheet({
    required this.kind,
    required this.range,
    required this.dayCount,
    required this.existingMinutes,
    required this.fullDayMinutes,
    required this.hasExisting,
  });

  final DayExtraKind kind;
  final String range;
  final int dayCount;
  final int? existingMinutes;
  final int? fullDayMinutes;
  final bool hasExisting;

  @override
  State<_DayExtraSheet> createState() => _DayExtraSheetState();
}

class _DayExtraSheetState extends State<_DayExtraSheet> {
  late bool _fullDay;
  bool _halfDay = false;
  late int _minutes;

  bool get _isLeave => widget.kind == DayExtraKind.leave;

  /// 「整天」要有得算：单日需要知道班次时长；多日按每天各自的时长算。
  /// 单日的休息日 / 空白表没有时长 —— 那时候不显示「整天」，免得选了等于没记。
  bool get _canFullDay => widget.fullDayMinutes != null || widget.dayCount > 1;

  /// 「半天」的分钟数：单日按班次时长的一半，多日按 4 小时这个常见档。
  int get _halfMinutes => ((widget.fullDayMinutes ?? 480) ~/ 2).clamp(30, 1440);

  @override
  void initState() {
    super.initState();
    final existing = widget.existingMinutes;
    _fullDay = existing == null && _isLeave && _canFullDay;
    _minutes = existing ??
        widget.fullDayMinutes ??
        (_isLeave ? 480 : 120);
  }

  void _selectFullDay() => setState(() {
        _fullDay = true;
        _halfDay = false;
      });

  void _selectHalfDay() => setState(() {
        _fullDay = false;
        _halfDay = true;
        _minutes = _halfMinutes;
      });

  void _selectMinutes(int minutes) => setState(() {
        _fullDay = false;
        _halfDay = false;
        _minutes = minutes;
      });

  void _step(int delta) => setState(() {
        // 整天状态下第一次点加减，从「当天班次时长」起步；其余情况从当前值走。
        final base = _fullDay ? (widget.fullDayMinutes ?? _minutes) : _minutes;
        _fullDay = false;
        _halfDay = false;
        _minutes = (base + delta).clamp(30, 1440);
      });

  @override
  Widget build(BuildContext context) {
    final muted = AppTokens.inkMuted(context);
    final primary = Theme.of(context).colorScheme.primary;
    final quick = _isLeave
        ? const [60, 120, 240, 480]
        : const [60, 120, 180, 240, 480];

    return GlassPanel(
      solid: true,
      margin: const EdgeInsets.all(12),
      borderRadius: const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassSheetHeader(
              title: _isLeave ? L10n.leave : L10n.overtime,
              subtitle: widget.range,
            ),
            // 头部以下才加左右内边距 —— 与「排班时段」弹层同一条：包住整层会让
            // 头部被二次内缩、分隔线比别的弹层窄 16dp。
            //
            // **必须能滚**：200×400 的小窗里这列内容约 570dp，固定高度会直接溢
            // 出 236px（工装小窗那一屏当场报红）。与时段弹层同样是
            // `Flexible` + 滚动容器。
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceLg, AppTokens.spaceSm, AppTokens.spaceLg,
                    AppTokens.spaceLg),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isLeave ? L10n.leaveHint : L10n.overtimeHint,
                    style: AppTokens.microText.copyWith(color: muted),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  Wrap(
                    spacing: AppTokens.spaceSm,
                    runSpacing: AppTokens.spaceSm,
                    children: [
                      if (_isLeave && _canFullDay)
                        GlassChoiceChip(
                          label: L10n.fullDay,
                          color: primary,
                          selected: _fullDay,
                          onTap: _selectFullDay,
                        ),
                      if (_isLeave)
                        GlassChoiceChip(
                          label: L10n.halfDay,
                          color: primary,
                          selected: _halfDay,
                          onTap: _selectHalfDay,
                        ),
                      for (final m in quick)
                        GlassChoiceChip(
                          label: L10n.durationText(m),
                          color: primary,
                          selected: !_fullDay && !_halfDay && _minutes == m,
                          onTap: () => _selectMinutes(m),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceLg),
                  Row(
                    children: [
                      GlassPill(
                        onTap: () => _step(-30),
                        child: const AppIcon(Icons.remove_outlined),
                      ),
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _fullDay
                                  ? L10n.fullDay
                                  : L10n.durationText(_minutes),
                              style: AppTokens.sectionTitle,
                            ),
                          ),
                        ),
                      ),
                      GlassPill(
                        onTap: () => _step(30),
                        child: const AppIcon(Icons.add_outlined),
                      ),
                    ],
                  ),
                  if (widget.dayCount > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: AppTokens.spaceSm),
                      child: Text(
                        L10n.statsDays(widget.dayCount),
                        textAlign: TextAlign.center,
                        style: AppTokens.microText.copyWith(color: muted),
                      ),
                    ),
                  const SizedBox(height: AppTokens.spaceLg),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppTokens.spaceSm,
                    runSpacing: AppTokens.spaceSm,
                    children: [
                      if (widget.hasExisting)
                        GlassActionButton(
                          variant: GlassActionVariant.danger,
                          label: L10n.clear,
                          onPressed: () => Navigator.pop(
                              context, const DayExtraSelection.clear()),
                        ),
                      GlassActionButton(
                        variant: GlassActionVariant.primary,
                        label: L10n.confirm,
                        onPressed: () => Navigator.pop(
                          context,
                          _fullDay
                              ? const DayExtraSelection.fullDay()
                              : DayExtraSelection.minutes(_minutes),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}
