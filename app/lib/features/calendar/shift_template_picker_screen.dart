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
              style: AppTokens.rowSecondary
                  .copyWith(color: AppTokens.inkMuted(context)),
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
            style: AppTokens.rowSecondary),
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
            style: AppTokens.rowPrimary
                .copyWith(color: AppTokens.inkMuted(context)),
          ),
        ),
      ));
    }
    out.add(_customCard(context));
    return out;
  }

  Widget _templateCard(BuildContext context, ShiftTemplate t) {
    final muted = AppTokens.inkMuted(context);
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.title, style: AppTokens.titleStrong),
        const SizedBox(height: 4),
        Text(t.subtitle,
            style: AppTokens.rowSecondary.copyWith(color: muted)),
        if (t.teamCount > 1) ...[
          const SizedBox(height: 4),
          Text(
            L10n.crewsOnDutyCount(t.workingTeamsPerDay),
            style: AppTokens.microLabel.copyWith(color: muted),
          ),
        ],
      ],
    );

    return GlassTile(
      enableBlur: false,
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: EdgeInsets.zero,
      child: GlassPressable(
        child: InkWell(
          onTap: () =>
              Navigator.of(context).pop(ShiftTemplateChoice.template(t)),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            child: LayoutBuilder(builder: (context, c) {
              // 卡片正文宽度 = 卡片宽 − 左右内边距。
              final inner = c.maxWidth - AppTokens.spaceMd * 2;
              // 色条、色条后的间距、右侧箭头都是**固定**宽度，只有标题那一栏
              // 是可伸缩的。小窗（实测 200 逻辑像素宽）里卡片只有 168 宽，
              // inner 就 144，三者相加 146 —— 标题被挤到 0 宽，整行溢出。
              //
              // 所以这里不按屏宽分档，按**卡片自己拿到的宽度**判断：放不下
              // 一整列可读的标题时，改成上下排（文字占满整行，色条挪到下面）。
              // 用真实的 availableWidth 而不是断点，是因为卡片在弹层里，
              // 弹层两侧的边距不由它决定，按屏宽推会推错。
              const minTextWidth = 96.0;
              final stacked = inner <
                  _cycleStripWidth + 12 + _chevronWidth + minTextWidth;

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    texts,
                    const SizedBox(height: AppTokens.spaceMd),
                    _cycleStrip(context, t),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cycleStrip(context, t),
                  const SizedBox(width: 12),
                  Expanded(child: texts),
                  Icon(Icons.chevron_right_outlined, color: muted),
                ],
              );
            }),
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
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            child: Row(
              children: [
                Icon(Icons.tune_outlined, color: primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(L10n.customPattern,
                          style: AppTokens.titleStrong),
                      const SizedBox(height: 4),
                      Text(
                        L10n.customPatternHint,
                        style: AppTokens.rowSecondary
                            .copyWith(color: AppTokens.inkMuted(context)),
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
/// 周期色条的固定几何（`_templateCard` 判断能不能与标题并排时要用到宽度）。
const double _stripDot = 14;
const double _stripSpacing = 2;
const int _stripPerRow = 7;

/// 色条宽度：按实际间距算，别写死 —— 改间距时宽度才不会对不上。
const double _cycleStripWidth =
    _stripDot * _stripPerRow + _stripSpacing * (_stripPerRow - 1);

/// 卡片右侧箭头的占位宽（`Icon` 默认 24）。
const double _chevronWidth = 24;

Widget _cycleStrip(BuildContext context, ShiftTemplate t) {
  const dot = _stripDot;
  const spacing = _stripSpacing;
  final muted = AppTokens.inkMuted(context);
  final plan = cycleStripPlan(t);
  return SizedBox(
    width: _cycleStripWidth,
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
              borderRadius: AppTokens.pillOf(dot),
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
              borderRadius: AppTokens.pillOf(dot),
            ),
            child: Text('…',
                // 画在 14×14 色块里的省略号字形，不是正文排版 ——
                // 令牌里最小的一档 11 已经是这个格子放得下的上限。
                style: AppTokens.tinyLabel.copyWith(color: muted)),
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
