// app/lib/features/stats/export_sheet.dart
//
// 统计数据的导出弹层：选区间 + 勾字段 → 生成 CSV。
//
// 只负责**拼出 CSV**（纯函数在 `domain/stats_export.dart`）。真正的落盘与
// 系统「保存到」选择器在调用方（`stats_screen.dart`），这样这一层可以单测、
// 也不碰平台通道。
import 'package:flutter/material.dart';

import '../../core/clock.dart';
import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_choice_chip.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_sheet_panel.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_pill.dart';
import '../../core/widgets/glass_sheet_header.dart';
import '../../domain/day_extra.dart';
import '../../domain/schedule_chain.dart';
import '../../domain/shift_rotation.dart';
import '../../domain/stats_export.dart';

/// 弹出导出设置层。用户确认返回 [StatsCsvResult]；取消返回 null。
Future<StatsCsvResult?> showStatsExportSheet(
  BuildContext context, {
  required ScheduleChain? chain,
  required Map<int, DayExtra> extras,
  required DateTime from,
  required DateTime to,
}) {
  return showGlassSheet<StatsCsvResult>(
    context: context,
    // 字段 chip 在窄窗会折好几行；不放开高度会被压到 9/16。
    isScrollControlled: true,
    builder: (_) => _StatsExportSheet(
      chain: chain,
      extras: extras,
      from: from,
      to: to,
    ),
  );
}

class _StatsExportSheet extends StatefulWidget {
  const _StatsExportSheet({
    required this.chain,
    required this.extras,
    required this.from,
    required this.to,
  });

  final ScheduleChain? chain;
  final Map<int, DayExtra> extras;
  final DateTime from;
  final DateTime to;

  @override
  State<_StatsExportSheet> createState() => _StatsExportSheetState();
}

class _StatsExportSheetState extends State<_StatsExportSheet> {
  late DateTime _from;
  late DateTime _to;
  late Set<StatsExportField> _fields;

  /// 两个日期选择器的上界：**今天**（issue #13）。
  ///
  /// 导出的是已经发生的事，未来日期没有数据。以前 `_pickTo` 干脆没传
  /// `lastDate`，选择器回落到 2100 —— 未来那几天和其他日期长得一模一样，
  /// 用户以为能选、选了导出一堆空行。上界交给选择器后它自己会置灰禁点
  /// （`glass_pickers.dart` 的 `enabled` 判据），不用在这里另写一套。
  late final DateTime _maxDate;

  @override
  void initState() {
    super.initState();
    _from = widget.from;
    _to = widget.to;
    _fields = {...StatsExportField.values};
    _maxDate = dateOnly(appNow());
  }

  Future<void> _pickFrom() async {
    final picked = await showGlassDatePicker(
      context,
      initialDate: _from,
      // 开始日期不能晚于结束日期；结束日期的上界已经夹到今天了。
      lastDate: _to.isAfter(_maxDate) ? _maxDate : _to,
    );
    if (picked == null || !mounted) return;
    setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final picked = await showGlassDatePicker(
      context,
      initialDate: _to,
      firstDate: _from,
      lastDate: _maxDate,
    );
    if (picked == null || !mounted) return;
    setState(() => _to = picked);
  }

  void _toggle(StatsExportField f) {
    setState(() {
      if (_fields.contains(f)) {
        _fields.remove(f);
      } else {
        _fields.add(f);
      }
    });
  }

  void _selectAll() => setState(() {
        _fields = {...StatsExportField.values};
      });

  void _generate() {
    if (_fields.isEmpty) return;
    final result = buildStatsCsv(
      chain: widget.chain,
      extras: widget.extras,
      from: _from,
      to: _to,
      fields: _fields,
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppTokens.inkMuted(context);
    final primary = Theme.of(context).colorScheme.primary;
    final allOn = _fields.length == StatsExportField.values.length;

    return GlassSheetPanel(
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassSheetHeader(
              title: L10n.exportTitle,
              subtitle: '${L10n.isoDate(_from)} – ${L10n.isoDate(_to)}',
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg,
                    AppTokens.spaceSm, AppTokens.spaceLg, AppTokens.spaceLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(L10n.exportRange,
                        style: AppTokens.labelSecondary.copyWith(color: muted)),
                    const SizedBox(height: AppTokens.spaceXs),
                    Row(
                      children: [
                        Expanded(
                          child: GlassPill(
                            onTap: _pickFrom,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${L10n.exportStart} ${L10n.isoDate(_from)}',
                                maxLines: 1,
                                style: AppTokens.labelSecondary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTokens.spaceSm),
                        Expanded(
                          child: GlassPill(
                            onTap: _pickTo,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${L10n.exportEnd} ${L10n.isoDate(_to)}',
                                maxLines: 1,
                                style: AppTokens.labelSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.spaceLg),
                    Row(
                      children: [
                        Expanded(
                          child: Text(L10n.exportFields,
                              style: AppTokens.labelSecondary
                                  .copyWith(color: muted)),
                        ),
                        GlassChoiceChip(
                          label: L10n.exportAll,
                          color: primary,
                          selected: allOn,
                          onTap: _selectAll,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.spaceXs),
                    Wrap(
                      spacing: AppTokens.spaceSm,
                      runSpacing: AppTokens.spaceXs,
                      children: [
                        for (final f in StatsExportField.values)
                          GlassChoiceChip(
                            label: statsExportChipHeader(f),
                            color: primary,
                            selected: _fields.contains(f),
                            onTap: () => _toggle(f),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.spaceLg),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppTokens.spaceSm,
                      runSpacing: AppTokens.spaceSm,
                      children: [
                        GlassActionButton(
                          label: L10n.cancel,
                          onPressed: () => Navigator.pop(context),
                        ),
                        GlassActionButton(
                          variant: GlassActionVariant.primary,
                          label: L10n.exportGenerate,
                          // 一列都不选时禁用：空表头的 CSV 没有意义。
                          onPressed: _fields.isEmpty ? null : _generate,
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
