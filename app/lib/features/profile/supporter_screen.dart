// app/lib/features/profile/supporter_screen.dart
//
// 支持者专属页。v0.13.3 的第一项内容是一封短信；这一页的结构就是给以后的
// 「专属功能」留的坑 —— 新内容继续往这个 ListView 里加卡片即可。
import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/centered_content.dart';

class SupporterScreen extends StatelessWidget {
  const SupporterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(L10n.supporterTitle),
        ),
      ),
      body: CenteredContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg,
              AppTokens.spaceSm, AppTokens.spaceLg, AppTokens.space2xl),
          children: [
            GlassTile(
              translucentFill: false,
              padding: const EdgeInsets.all(AppTokens.spaceXl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.mail_outline,
                      size: AppTokens.iconLg * 2, color: primary),
                  const SizedBox(height: AppTokens.spaceMd),
                  Text(L10n.supporterLetterTitle,
                      style: AppTokens.titleStrong),
                  const SizedBox(height: AppTokens.spaceLg),
                  Text(
                    L10n.supporterLetterBody,
                    style: AppTokens.rowSecondary.copyWith(height: 1.65),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.spaceLg),
            Text(
              L10n.supporterMoreComing,
              style: AppTokens.microText
                  .copyWith(color: AppTokens.inkMuted(context)),
            ),
          ],
        ),
      ),
    );
  }
}
