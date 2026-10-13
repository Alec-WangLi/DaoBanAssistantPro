import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/widgets/section_heading.dart';
import 'help_content.dart';

/// 《使用帮助》第二层：「遇到问题怎么解决」。
///
/// 内容全在 [helpFaqGroups]（纯数据，`help_content.dart`）—— 这一层只负责排。
/// 两组：**「我想办一件事」**（用户带着诉求来的）与**「它不对劲」**（带着症状
/// 来的）。分开摆是有理由的：前者要的是「去哪一步」，后者要的是「逐条对症状」，
/// 混在一起会互相冲淡。
class HelpFaqScreen extends StatelessWidget {
  const HelpFaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 标题按宽度缩小而不是省略 —— AppBar 的工具条高度是定死的、折不了行，
      // 窄屏 + 大字号 + 英文下「How to get things done」会超出去。
      appBar: AppBar(
        title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(L10n.faqTitle)),
      ),
      body: CenteredContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg,
              AppTokens.spaceSm, AppTokens.spaceLg, AppTokens.space2xl),
          children: [
            for (final group in helpFaqGroups) ...[
              SectionHeading(group.title.value),
              for (final section in group.sections) ...[
                _sectionCard(context, section),
                const SizedBox(height: AppTokens.spaceMd),
              ],
              const SizedBox(height: AppTokens.spaceSm),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一个小节 = 一张卡。`heading` 为 null 时不画小节标题（「它不对劲」那一组不分小节）。
Widget _sectionCard(BuildContext context, HelpFaqSection section) {
  final items = section.items;
  return GlassTile(
    translucentFill: false,
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.heading != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg,
                AppTokens.spaceMd, AppTokens.spaceLg, 0),
            child: Text(
              section.heading!.value,
              style: AppTokens.microStrong
                  .copyWith(color: AppTokens.inkMuted(context)),
            ),
          ),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          _item(context, items[i]),
        ],
      ],
    ),
  );
}

Widget _item(BuildContext context, HelpFaqItem item) => Padding(
      padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg, AppTokens.spaceMd,
          AppTokens.spaceLg, AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 问句用用户的说法（「我这个月跟下个月不一样」），所以它得是一眼里
          // 最重的那一行 —— 用户是**照着这句话**找到自己那一条的。
          Text(item.question.value, style: AppTokens.labelStrong),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            item.answer.value,
            style: AppTokens.rowSecondary
                .copyWith(height: 1.45, color: AppTokens.inkMuted(context)),
          ),
        ],
      ),
    );
