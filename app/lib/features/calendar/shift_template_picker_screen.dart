import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../data/app_repository.dart';
import '../../domain/shift_rotation.dart';
import '../../domain/shift_templates.dart';

/// 选择页的返回值。
///
/// 不能只用 `ShiftTemplate?`：那样「我自己排」（null）与「按返回键放弃」
/// （push 也返回 null）无法区分，用户一按返回就会凭空多出一套排班。
class ShiftTemplateChoice {
  const ShiftTemplateChoice.template(ShiftTemplate this.template) : custom = false;
  const ShiftTemplateChoice.custom()
      : template = null,
        custom = true;

  /// 选中的模板；[custom] 为 true 时为 null。
  final ShiftTemplate? template;

  /// 用户选了「我自己排」。
  final bool custom;
}

/// 「选择你的倒班方式」：卡片网格 + 搜索，选中后返回该模板。
///
/// 返回 null 表示用户按返回键放弃，调用方应直接 return。
class ShiftTemplatePickerScreen extends StatefulWidget {
  const ShiftTemplatePickerScreen({super.key});

  @override
  State<ShiftTemplatePickerScreen> createState() =>
      _ShiftTemplatePickerScreenState();
}

class _ShiftTemplatePickerScreenState
    extends State<ShiftTemplatePickerScreen> {
  String _query = '';

  bool _matches(ShiftTemplate t) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return t.title.toLowerCase().contains(q) ||
        t.subtitle.toLowerCase().contains(q) ||
        t.group.toLowerCase().contains(q) ||
        t.aliases.any((a) => a.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final matched =
        shiftTemplates.where(_matches).toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(L10n.pickShiftPattern)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            L10n.pickShiftPatternHint,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: glassInputDecoration(context, L10n.searchPattern),
          ),
          const SizedBox(height: 16),
          ..._buildGrouped(context, matched),
        ],
      ),
    );
  }

  List<Widget> _buildGrouped(BuildContext context, List<ShiftTemplate> matched) {
    final out = <Widget>[];
    for (final group in shiftTemplateGroups) {
      final inGroup = matched.where((t) => t.group == group).toList();
      if (inGroup.isEmpty) continue;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(group,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ));
      for (final t in inGroup) {
        out.add(_templateCard(context, t));
      }
      out.add(const SizedBox(height: 8));
    }
    if (matched.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            L10n.noPatternMatch,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
          ),
        ),
      ));
    }
    out.add(_customCard(context));
    return out;
  }

  /// 一排小色块，就是把周期表画出来；最多画前 14 天，够认出是哪一种。
  Widget _cycleStrip(ShiftTemplate t) {
    const dot = 14.0;
    return SizedBox(
      width: dot * 7 + 12,
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [
          for (final i in t.cycle.take(14))
            Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: Color(t.classes[i].color),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _templateCard(BuildContext context, ShiftTemplate t) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return GlassTile(
      enableBlur: false,
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.zero,
      child: GlassPressable(
        child: InkWell(
          onTap: () =>
              Navigator.of(context).pop(ShiftTemplateChoice.template(t)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cycleStrip(t),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(t.subtitle,
                          style: TextStyle(fontSize: 12, color: muted)),
                      if (t.teamCount > 1) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${L10n.crewsOnDuty} ${t.workingTeamsPerDay} '
                          '${L10n.crewUnit}',
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_outlined, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _customCard(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GlassTile(
      enableBlur: false,
      padding: EdgeInsets.zero,
      child: GlassPressable(
        child: InkWell(
          onTap: () => Navigator.of(context).pop(const ShiftTemplateChoice.custom()),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.tune_outlined, color: primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(L10n.customPattern,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        L10n.customPatternHint,
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_outlined, color: primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹出「选择你的倒班方式」，按选择建出一套方案并返回新方案 id。
/// 用户按返回键放弃时返回 null（不建方案）。
///
/// 这是全应用**新增排班**的唯一入口逻辑 —— 我的 → 排班管理与
/// 日历 → 切换排班 → 新增排班 都调它，两条路径共用同一段逻辑。
Future<int?> createScheduleFromTemplatePicker(
  BuildContext context,
  WidgetRef ref, {
  required bool makeCurrent,
}) async {
  final choice = await Navigator.of(context).push<ShiftTemplateChoice>(
    MaterialPageRoute(builder: (_) => const ShiftTemplatePickerScreen()),
  );
  // 按返回键放弃：不建方案
  if (choice == null || !context.mounted) return null;

  final d = defaultSchedule();
  final picked = choice.template;
  return ref.read(appRepositoryProvider).saveSchedule(
        name: picked?.subtitle ?? L10n.newSchedule,
        anchorDate: dateOnly(DateTime.now()),
        classes: picked?.classes ?? d.classes,
        cycle: picked?.cycle ?? d.cycle,
        makeCurrent: makeCurrent,
        teamCount: picked?.teamCount ?? d.teamCount,
        teamNames: d.teamNames,
        ourTeamIndex: 0,
        teamOffsets: picked?.teamOffsets ?? d.teamOffsets,
      );
}
