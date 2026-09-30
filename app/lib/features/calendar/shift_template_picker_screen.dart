import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/glass/glass.dart';
import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_delete_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../data/app_repository.dart';
import '../../domain/schedule_template.dart';
import '../../domain/shift_rotation.dart';
import '../../domain/shift_templates.dart';

/// 选择页的返回值。
///
/// 不能只用 `ShiftTemplate?`：那样「我自己排」（null）与「按返回键放弃」
/// （push 也返回 null）无法区分，用户一按返回就会凭空多出一套排班。
class ShiftTemplateChoice {
  const ShiftTemplateChoice.template(ShiftTemplate this.template)
      : savedTemplate = null,
        custom = false;
  const ShiftTemplateChoice.saved(ScheduleTemplate this.savedTemplate)
      : template = null,
        custom = false;
  const ShiftTemplateChoice.custom()
      : template = null,
        savedTemplate = null,
        custom = true;

  /// 选中的内置模板；其余两种情形为 null。
  final ShiftTemplate? template;

  /// 选中的「我的模板」；其余两种情形为 null。
  final ScheduleTemplate? savedTemplate;

  /// 用户选了「我自己排」。
  final bool custom;
}

/// 「选择你的倒班方式」：卡片网格 + 搜索，选中后返回该模板。
///
/// 返回 null 表示用户按返回键放弃，调用方应直接 return。
class ShiftTemplatePickerScreen extends ConsumerStatefulWidget {
  const ShiftTemplatePickerScreen({super.key});

  @override
  ConsumerState<ShiftTemplatePickerScreen> createState() =>
      _ShiftTemplatePickerScreenState();
}

class _ShiftTemplatePickerScreenState
    extends ConsumerState<ShiftTemplatePickerScreen> {
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

  /// 「我的模板」的搜索口径：模板名 + 分组名（搜「我的」能搜到自己存的那些）。
  bool _matchesSaved(ScheduleTemplate t) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return t.name.toLowerCase().contains(q) ||
        L10n.myTemplates.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final matched =
        shiftTemplates.where(_matches).toList(growable: false);
    final saved =
        ref.watch(savedTemplatesProvider).valueOrNull ?? const <ScheduleTemplate>[];

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
            ..._buildGrouped(context, matched, saved),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGrouped(BuildContext context, List<ShiftTemplate> matched,
      List<ScheduleTemplate> saved) {
    final out = <Widget>[];

    // 「我的模板」排在最前：自己存的那套多半比内置的更贴近你的班表。
    // 一条都没有时整组不出现（首启的用户看不到一个空分组）。
    final mine = saved.where(_matchesSaved).toList(growable: false);
    if (mine.isNotEmpty) {
      out.add(_groupHeader(context, L10n.myTemplates,
          onManage: () => _manageTemplates(context, saved)));
      for (final t in mine) {
        out.add(_savedCard(context, t));
      }
      out.add(const SizedBox(height: 8));
    }

    for (final group in shiftTemplateGroups) {
      final inGroup = matched.where((t) => t.groupKey == group).toList();
      if (inGroup.isEmpty) continue;
      out.add(_groupHeader(context, L10n.templateGroup(group)));
      for (final t in inGroup) {
        out.add(_templateCard(context, t));
      }
      out.add(const SizedBox(height: 8));
    }
    if (matched.isEmpty && mine.isEmpty) {
      // 两行：一句「没找到」，一句「那接下来怎么办」。只有前一句时这里是个
      // 死胡同 —— 而用户是照着搜索框的提示语（「搜索，如…上24休48」）搜过来的。
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(8, 28, 8, 24),
        child: Column(
          children: [
            Text(
              L10n.noPatternMatch,
              textAlign: TextAlign.center,
              style: AppTokens.rowPrimary
                  .copyWith(color: AppTokens.inkMuted(context)),
            ),
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              L10n.noPatternMatchHint,
              textAlign: TextAlign.center,
              style: AppTokens.rowSecondary
                  .copyWith(color: AppTokens.inkMuted(context)),
            ),
          ],
        ),
      ));
    }
    out.add(_customCard(context));
    return out;
  }

  /// 分组标题行；「我的模板」那组右边多一个「管理」（改名 / 删）。
  Widget _groupHeader(BuildContext context, String title,
      {VoidCallback? onManage}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                // 分组标题：下面每张卡片的副标题是 w400，标题原本就是 w700 用来压住
                // 一组卡片，13 档最重只到 w600，按 spec 的 copyWith 保住 w700。
                style: AppTokens.labelSecondary
                    .copyWith(fontWeight: FontWeight.w700)),
          ),
          if (onManage != null)
            TextButton(
              onPressed: onManage,
              child: Text(L10n.manageTemplates),
            ),
        ],
      ),
    );
  }

  /// 模板卡片的**统一配方**：色条 + 标题 + 副标题 + 每天在岗数。
  ///
  /// 内置模板与「我的模板」共用它 —— 两边只有数据来源不同，卡片长得不一样的话
  /// 用户会以为「我的模板」是另一种东西。
  Widget _patternCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<ShiftClass> classes,
    required List<int> cycle,
    required int workingTeamsPerDay,
    required VoidCallback onTap,
  }) {
    final muted = AppTokens.inkMuted(context);
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTokens.titleStrong),
        const SizedBox(height: 4),
        Text(subtitle,
            style: AppTokens.rowSecondary.copyWith(color: muted)),
        if (workingTeamsPerDay > 1) ...[
          const SizedBox(height: 4),
          Text(
            L10n.crewsOnDutyCount(workingTeamsPerDay),
            // 基线是 12/**w400**（跟上面 13/w400 的副标题同重），microText 精确匹配；
            // 写成 microLabel 会让这行比副标题还重，把层次弄反。
            style: AppTokens.microText.copyWith(color: muted),
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
          onTap: onTap,
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
                    _cycleStrip(context, classes: classes, cycle: cycle),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cycleStrip(context, classes: classes, cycle: cycle),
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

  Widget _templateCard(BuildContext context, ShiftTemplate t) => _patternCard(
        context,
        title: t.title,
        subtitle: t.subtitle,
        classes: t.classes,
        cycle: t.cycle,
        workingTeamsPerDay: t.workingTeamsPerDay,
        onTap: () =>
            Navigator.of(context).pop(ShiftTemplateChoice.template(t)),
      );

  Widget _savedCard(BuildContext context, ScheduleTemplate t) => _patternCard(
        context,
        title: t.name,
        subtitle: L10n.savedTemplateSubtitle(t.cycleLength, t.teamCount),
        classes: t.classes,
        cycle: t.cycle,
        workingTeamsPerDay: t.workingTeamsPerDay,
        onTap: () => Navigator.of(context).pop(ShiftTemplateChoice.saved(t)),
      );

  // ---------------------------------------------------------------------------
  // 「我的模板」的管理：改名 / 删除
  // ---------------------------------------------------------------------------

  /// 管理弹窗：一列自己的模板，点行进改名、尾部按钮删。
  ///
  /// 行配方照抄排班管理页（`GlassTile` 行 + 紧凑删除钮 + 点行进编辑），只是
  /// 装在弹窗里 —— 模板没有自己的详情页，为它单开一页不值得。
  Future<void> _manageTemplates(
      BuildContext context, List<ScheduleTemplate> saved) async {
    if (saved.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: L10n.myTemplates,
        showClose: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 行配方与排班管理页逐字一致（GlassTile + GlassPressable + ListTile
            // + 紧凑删除钮 + 点行进编辑），只是装在弹窗里。
            for (final t in saved)
              GlassTile(
                enableBlur: false,
                margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                padding: EdgeInsets.zero,
                child: GlassPressable(
                  child: ListTile(
                    title: Text(t.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      L10n.savedTemplateSubtitle(t.cycleLength, t.teamCount),
                    ),
                    trailing: GlassDeleteButton(
                      compact: true,
                      onPressed: () {
                        // 先关掉管理弹窗再弹确认：嵌套两层弹窗时，
                        // 底下那层的按钮位置会随上面那层开合而跳。
                        Navigator.of(dialogContext).pop();
                        _deleteTemplate(context, t);
                      },
                    ),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      _renameTemplate(context, t);
                    },
                  ),
                ),
              ),
          ],
        ),
        actions: [
          GlassActionButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: L10n.close,
          ),
        ],
      ),
    );
  }

  Future<void> _renameTemplate(
      BuildContext context, ScheduleTemplate t) async {
    final id = t.id;
    if (id == null) return;
    // 控制器不 dispose（与待办弹窗同一套写法）：提前 dispose 会在弹窗退场
    // 动画里被 TextField 再读一次，直接抛「used after being disposed」。
    final ctrl = TextEditingController(text: t.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: L10n.renameTemplate,
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: glassInputDecoration(context, L10n.templateName),
        ),
        actions: [
          GlassActionButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: L10n.cancel,
          ),
          const SizedBox(width: 8),
          GlassActionButton(
            variant: GlassActionVariant.primary,
            onPressed: () =>
                Navigator.of(dialogContext).pop(ctrl.text.trim()),
            label: L10n.save,
          ),
        ],
      ),
    );
    // 空名字当没改：模板名是卡片上唯一的识别信息，留空比不改更糟。
    if (name == null || name.isEmpty || !context.mounted) return;
    await ref.read(appRepositoryProvider).renameTemplate(id, name);
    // 卡片上的名字跟着变（provider 是一次性读，见 savedTemplatesProvider）
    ref.invalidate(savedTemplatesProvider);
  }

  Future<void> _deleteTemplate(
      BuildContext context, ScheduleTemplate t) async {
    final id = t.id;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: L10n.deleteTemplateTitle,
        content: Text(L10n.deleteTemplateContent(t.name)),
        actions: [
          GlassActionButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: L10n.cancel,
          ),
          const SizedBox(width: 8),
          GlassActionButton(
            variant: GlassActionVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: L10n.delete,
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(appRepositoryProvider).deleteTemplate(id);
    ref.invalidate(savedTemplatesProvider);
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
({List<int> colors, bool truncated}) cycleStripPlan(ShiftTemplate t) =>
    cycleStripPlanOf(t.classes, t.cycle);

/// 同上，但收班次定义与周期本身 —— 「我的模板」（`ScheduleTemplate`）也走它，
/// 免得同一套画法为两种数据各写一遍。
({List<int> colors, bool truncated}) cycleStripPlanOf(
    List<ShiftClass> classes, List<int> cycle) {
  const maxSlots = 14; // 7 列 × 2 行
  final truncated = cycle.length > maxSlots;
  final visible = truncated ? maxSlots - 1 : cycle.length;
  return (
    colors: [for (var i = 0; i < visible; i++) classes[cycle[i]].color],
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
const double _stripSpacing = AppTokens.gapHair;
const int _stripPerRow = 7;

/// 色条宽度：按实际间距算，别写死 —— 改间距时宽度才不会对不上。
const double _cycleStripWidth =
    _stripDot * _stripPerRow + _stripSpacing * (_stripPerRow - 1);

/// 卡片右侧箭头的占位宽（`Icon` 默认 24）。
const double _chevronWidth = 24;

Widget _cycleStrip(BuildContext context,
    {required List<ShiftClass> classes, required List<int> cycle}) {
  const dot = _stripDot;
  const spacing = _stripSpacing;
  final muted = AppTokens.inkMuted(context);
  final plan = cycleStripPlanOf(classes, cycle);
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
              // 14% 是全 app 的淡染约定值（见 calendar_screen 的说明）
              color: muted.withValues(alpha: 0.14),
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
  // 三选一：内置模板 / 我的模板 / 我自己排（后者缺省到默认四班两倒）。
  final picked = choice.template;
  final mine = choice.savedTemplate;
  final teamCount = picked?.teamCount ?? mine?.teamCount ?? d.teamCount;
  return ref.read(appRepositoryProvider).saveSchedule(
        name: mine?.name ?? picked?.subtitle ?? L10n.newSchedule,
        anchorDate: dateOnly(DateTime.now()),
        classes: picked?.classes ?? mine?.classes ?? d.classes,
        cycle: picked?.cycle ?? mine?.cycle ?? d.cycle,
        makeCurrent: makeCurrent,
        teamCount: teamCount,
        // 必须给满 teamCount 个名字：模板只带 4 个默认名，多班组模板
        // （五班三倒 5 组、六班三倒 6 组…）靠数据库出口补位就会漏出中文。
        teamNames: L10n.defaultTeamNames(teamCount),
        // 「我的模板」在保存时已把「我们班组」归一化到第 0 位、错位归零
        // （见 `ScheduleTemplate.fromSchedule`），所以与内置模板同一条约定：
        // 新方案的「我们班组」从周期第 1 天开始。相位要改，在编辑器里点
        // 「我这组从这个周期开始」即可。
        ourTeamIndex: 0,
        teamOffsets: picked?.teamOffsets ?? mine?.teamOffsets ?? d.teamOffsets,
      );
}
