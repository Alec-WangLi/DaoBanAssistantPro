import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/widgets/glass_pressable.dart';
import 'help_entry.dart';
import 'help_faq_screen.dart';

/// 《使用帮助》第一级：整页。
///
/// 三段 —— **一段整体简介**（这是什么、由哪几块组成，不是目录）、**九条功能块
/// 简介**（保持简介粒度：说的是「有这么个功能、在哪儿」，怎么用归第二层）、
/// **一颗进第二层的入口**。
///
/// v0.11.17 之前这一屏是个弹窗。改成整页的理由是它多了整整一层：简介 + 九条 +
/// 入口在窄屏上要滚很长，而「书」本来就该是一页。
///
/// [scrollToWidgets] 给「我的 → 桌面」那一行用：它从前弹出自己那份小组件说明，
/// 现在改成**跳进这里并翻到「桌面小组件」那一节**（全 app 只剩一份文案）。
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key, this.scrollToWidgets = false});

  /// 进页面后直接滚到「桌面小组件」那一条。
  final bool scrollToWidgets;

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _widgetsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (!widget.scrollToWidgets) return;
    // **必须等这一帧布局完**：`ensureVisible` 要的是已经挂载、且已排过版的
    // 上下文；在 initState 里直接调会拿不到 currentContext（那一帧树还没建）。
    //
    // 只在挂载时滚一次，之后用户自己滑走不会再被拽回来 —— 所以用
    // `addPostFrameCallback` 而不是在 build 里判。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _widgetsKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx,
          duration: AppTokens.durMed, alignment: 0.1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(L10n.usageGuide)),
      ),
      body: CenteredContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg,
              AppTokens.spaceSm, AppTokens.spaceLg, AppTokens.space2xl),
          children: [
            Text(
              L10n.helpIntro,
              style: AppTokens.rowSecondary
                  .copyWith(height: 1.45, color: AppTokens.inkMuted(context)),
            ),
            const SizedBox(height: AppTokens.spaceXl),
            _entries(),
            const SizedBox(height: AppTokens.spaceXl),
            _faqEntry(context),
          ],
        ),
      ),
    );
  }

  /// 九条功能块简介。
  ///
  /// **每条必须是一个 widget 而不是数据行** —— 「桌面小组件」那一条要挂
  /// [GlobalKey]（[scrollToWidgets] 的落点），而 key 是建 widget 时给的。
  Widget _entries() {
    final entries = <Widget>[
      HelpEntry(
          icon: Icons.calendar_month_outlined,
          title: L10n.guideCalTitle,
          lines: L10n.guideCalDesc),
      HelpEntry(
          icon: Icons.tune_outlined,
          title: L10n.guideSchedTitle,
          lines: L10n.guideSchedDesc),
      HelpEntry(
          icon: Icons.alarm_outlined,
          title: L10n.guideAlarmTitle,
          lines: L10n.guideAlarmDesc),
      HelpEntry(
          icon: Icons.event_note_outlined,
          title: L10n.guideTodoTitle,
          lines: L10n.guideTodoDesc),
      HelpEntry(
          key: _widgetsKey,
          icon: Icons.widgets_outlined,
          title: L10n.guideWidgetTitle,
          lines: L10n.guideWidgetDesc),
      HelpEntry(
          icon: Icons.palette_outlined,
          title: L10n.guideAppearanceTitle,
          lines: L10n.guideAppearanceDesc),
      HelpEntry(
          icon: Icons.aspect_ratio_outlined,
          title: L10n.guideLayoutTitle,
          lines: L10n.guideLayoutDesc),
      HelpEntry(
          icon: Icons.shield_outlined,
          title: L10n.guidePermTitle,
          lines: L10n.guidePermDesc),
      HelpEntry(
          icon: Icons.system_update_outlined,
          title: L10n.guideUpdateTitle,
          lines: L10n.guideUpdateDesc),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: AppTokens.spaceLg),
          entries[i],
        ],
      ],
    );
  }

  /// 进第二层的入口。配方与「我的」页每一行逐字一致 —— 它是这一页上唯一可点的
  /// 东西，本身就够显眼，不必再另造一个「主操作」的形态。
  Widget _faqEntry(BuildContext context) => GlassTile(
        translucentFill: false,
        padding: EdgeInsets.zero,
        child: GlassPressable(
          child: ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(L10n.faqEntryTitle),
            subtitle: Text(L10n.faqEntrySubtitle),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HelpFaqScreen()),
            ),
          ),
        ),
      );
}
