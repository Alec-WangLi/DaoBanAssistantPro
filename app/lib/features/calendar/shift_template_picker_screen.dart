import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/glass/glass.dart';
import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/widgets/centered_content.dart';
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

  /// 搜索：当前语言的标题/副标题/分组名 + id + 别名（中英混收）。
  ///
  /// 别名表里中英关键词都有，所以中文用户搜「四班三倒」、英文用户搜
  /// `4-crew` 都能中，不需要按语言分支。id 也参与匹配 —— 英文用户看到
  /// `dupont` 这类 id 时能直接搜到。
  bool _matches(ShiftTemplate t) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return t.title.toLowerCase().contains(q) ||
        t.subtitle.toLowerCase().contains(q) ||
        // 分组名走本地化显示名，不用原始键 —— 键是 `h12` 这种，对用户没有
        // 意义；换成本地化显示名后「常白」仍然搜得到，与改动前一致。
        L10n.templateGroup(t.groupKey).toLowerCase().contains(q) ||
        t.id.toLowerCase().contains(q) ||
        t.aliases.any((a) => a.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final matched =
        shiftTemplates.where(_matches).toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(L10n.pickShiftPattern)),
      body: CenteredContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              L10n.pickShiftPatternHint,
              style: TextStyle(
                fontSize: AppTokens.fontSupport,
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
      ),
    );
  }

  List<Widget> _buildGrouped(BuildContext context, List<ShiftTemplate> matched) {
    final out = <Widget>[];
    for (final group in shiftTemplateGroups) {
      final inGroup = matched.where((t) => t.groupKey == group).toList();
      if (inGroup.isEmpty) continue;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(L10n.templateGroup(group),
            style: const TextStyle(fontSize: AppTokens.fontSupport, fontWeight: FontWeight.w700)),
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
                _cycleStrip(context, t),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          style: const TextStyle(
                              fontSize: AppTokens.fontLead, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(t.subtitle,
                          style: TextStyle(fontSize: AppTokens.fontSupport, color: muted)),
                      if (t.teamCount > 1) ...[
                        const SizedBox(height: 4),
                        Text(
                          L10n.crewsOnDutyCount(t.workingTeamsPerDay),
                          style: TextStyle(fontSize: AppTokens.fontCaption, color: muted),
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
                              fontSize: AppTokens.fontLead, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        L10n.customPatternHint,
                        style: TextStyle(
                            fontSize: AppTokens.fontSupport,
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

/// 色条要画的东西：前 N 个班次的颜色，以及是否被截断。
///
/// 抽成顶层纯函数是为了能直接断言「28 天的模板画出 13 格 + 1 个省略标记」，
/// 而不必去数 widget 树里的色块。
///
/// 为什么留最后一格做省略标记、而不是把整条周期画完：周期上限 60 天，
/// 卡片高度会随模板剧烈起伏，且 60 个色块在手机宽度下每个不到 5px，
/// 认不出任何东西。7×2 是「够认出是哪一种」的尺寸。
({List<int> colors, bool truncated}) cycleStripPlan(ShiftTemplate t) {
  const maxSlots = 14; // 7 列 × 2 行
  final truncated = t.cycleLength > maxSlots;
  final visible = truncated ? maxSlots - 1 : t.cycleLength;
  final classes = t.classes; // 只解析一次：它是现算的列表，别在循环里反复取
  return (
    colors: [for (var i = 0; i < visible; i++) classes[t.cycle[i]].color],
    truncated: truncated,
  );
}

/// 一排小色块，就是把周期表画出来；最多画 14 格，够认出是哪一种。
///
/// 超过 14 天时最后一格画成省略标记 —— 28 天的 DuPont 原来会静默只剩半截，
/// 看不出「后面还有」。副标题里写着周期天数，有了这个标记它就从
/// 「唯一线索」退回「补充说明」，这是它该有的位置。
Widget _cycleStrip(BuildContext context, ShiftTemplate t) {
  const dot = 14.0;
  const spacing = 2.0;
  const perRow = 7;
  final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
  final plan = cycleStripPlan(t);
  return SizedBox(
    // 按实际间距算，别写死 —— 改间距时宽度才不会对不上。
    width: dot * perRow + spacing * (perRow - 1),
    child: Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final color in plan.colors)
          Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: Color(color),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        if (plan.truncated)
          Container(
            key: const Key('cycle-strip-more'),
            width: dot,
            height: dot,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: muted.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('…',
                // 画在 14×14 色块里的省略号字形，不是正文排版 —— 提到 12 会顶出格子。
                style: TextStyle(fontSize: 10, height: 1, color: muted)),
          ),
      ],
    ),
  );
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
  final teamCount = picked?.teamCount ?? d.teamCount;
  return ref.read(appRepositoryProvider).saveSchedule(
        name: picked?.subtitle ?? L10n.newSchedule,
        anchorDate: dateOnly(DateTime.now()),
        classes: picked?.classes ?? d.classes,
        cycle: picked?.cycle ?? d.cycle,
        makeCurrent: makeCurrent,
        teamCount: teamCount,
        // 必须给满 teamCount 个名字：模板只带 4 个默认名，多班组模板
        // （五班三倒 5 组、六班三倒 6 组…）靠数据库出口补位就会漏出中文。
        teamNames: L10n.defaultTeamNames(teamCount),
        ourTeamIndex: 0,
        teamOffsets: picked?.teamOffsets ?? d.teamOffsets,
      );
}
