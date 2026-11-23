// app/lib/features/stats/stats_section_header.dart
//
// 统计页卡片的分节标题：**图标在前** + 标题 + 可选尾部。
//
// 2026-11-23 用户要求「图标优先放到前面」。只在这一页用，所以留在 features（E18）。
//
// **不给图标垫染色芯片**：那会再立一套「淡染圆底」配方（D4 的配方只许一份），
// 而图标本身已经担起识别；配色只走语义色（主色 / 琥珀 / 紫 / 中性灰），
// 由调用方按卡片的含义挑。
import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/widgets/app_icon.dart';

class StatsSectionHeader extends StatelessWidget {
  const StatsSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.iconColor,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Color iconColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 图标用 titleStrong 的行盒高度对齐，避免比标题高半行（视觉上「浮起来」）。
        Padding(
          padding: const EdgeInsets.only(top: AppTokens.gapHair),
          child: AppIcon(icon, size: AppTokens.iconSm, color: iconColor),
        ),
        const SizedBox(width: AppTokens.gapIconText),
        Expanded(
          // 不限制行数：英文长标题（How it is calculated）在 320 + 特大字号下
          // 宁可折行也不许截断（D12）。
          child: Text(title, style: AppTokens.titleStrong),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppTokens.spaceSm),
          trailing!,
        ],
      ],
    );
  }
}
