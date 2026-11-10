// app/lib/features/profile/about_screen.dart
//
// 「关于」整页：作者、版本、官网、开源仓库、问题反馈、隐私说明。
//
// 为什么是整页而不是弹窗：这几行都要能被复制/点开，信息量比一个确认弹窗大；
// 《使用帮助》从弹窗改成整页之后，这一屏沿用同一套骨架（Scaffold + AppBar +
// CenteredContent + ListView），窄屏与横屏都不用另写一套。
import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/update_checker.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../core/widgets/section_heading.dart';
import '../alarm/alarm_service.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(L10n.aboutTitle),
        ),
      ),
      body: CenteredContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg,
              AppTokens.spaceSm, AppTokens.spaceLg, AppTokens.space2xl),
          children: [
            _brandCard(context),
            const SizedBox(height: AppTokens.spaceLg),
            _infoCard(context),
            const SizedBox(height: AppTokens.spaceLg),
            SectionHeading(L10n.aboutPrivacyTitle),
            GlassTile(
              translucentFill: false,
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              child: Text(
                L10n.aboutPrivacyBody,
                style: AppTokens.rowSecondary
                    .copyWith(height: 1.5, color: AppTokens.inkMuted(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 品牌块：不引入图片资源。用当前主色画一枚圆角方块 + 白色日历图标，
  /// 与官网 favicon 同形；五种主色、深浅两档都成立，也不给 APK 增体积。
  Widget _brandCard(BuildContext context) {
    final solid = AppTokens.solidAccent(Theme.of(context).colorScheme.primary);
    const mark = AppTokens.iconLg * 3;
    return GlassTile(
      translucentFill: false,
      padding: const EdgeInsets.fromLTRB(
          AppTokens.spaceXl, AppTokens.space2xl, AppTokens.spaceXl,
          AppTokens.space2xl),
      child: Column(
        children: [
          Container(
            width: mark,
            height: mark,
            decoration: BoxDecoration(
              color: solid,
              borderRadius: BorderRadius.circular(AppTokens.radiusL),
            ),
            child: Icon(
              Icons.calendar_month_rounded,
              size: AppTokens.iconLg * 2,
              color: AppTokens.onSolid(solid),
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          // 品牌名在 320dp + 特大 + 英文下比卡片宽，缩到放得下为止；
          // 这一档只有名字会缩，下面的版本号与简介照常换行。
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(L10n.appName, style: AppTokens.pageTitle),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            'v$appVersion',
            style: AppTokens.labelSecondary
                .copyWith(color: AppTokens.inkMuted(context)),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            L10n.aboutTagline,
            textAlign: TextAlign.center,
            style: AppTokens.rowSecondary
                .copyWith(height: 1.45, color: AppTokens.inkMuted(context)),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(BuildContext context) {
    return GlassTile(
      translucentFill: false,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _developerRow(context),
          const Divider(height: 1),
          _linkRow(
            context: context,
            key: const Key('about-row-license'),
            icon: Icons.code_outlined,
            title: L10n.aboutLicense,
            subtitle: L10n.aboutLicenseValue,
            onTap: () => _open(context, UpdateChecker.licenseUrl),
          ),
          const Divider(height: 1),
          _linkRow(
            context: context,
            key: const Key('about-row-website'),
            icon: Icons.public_outlined,
            title: L10n.aboutWebsite,
            subtitle: UpdateChecker.siteBase,
            onTap: () => _open(context, UpdateChecker.siteBase),
          ),
          const Divider(height: 1),
          _linkRow(
            context: context,
            key: const Key('about-row-repo'),
            icon: Icons.source_outlined,
            title: L10n.aboutRepository,
            subtitle: UpdateChecker.repoUrl,
            onTap: () => _open(context, UpdateChecker.repoUrl),
          ),
          const Divider(height: 1),
          _linkRow(
            context: context,
            key: const Key('about-row-issues'),
            icon: Icons.bug_report_outlined,
            title: L10n.aboutIssues,
            subtitle: L10n.aboutIssuesValue,
            onTap: () => _open(context, UpdateChecker.issuesUrl),
          ),
        ],
      ),
    );
  }

  /// 开发者这一行。宽度不够（200dp 小窗）时把名字折到标题下面 ——
  /// 用 `ListTile.trailing` 装名字的话，标题那一列会被挤到只剩一个字宽，
  /// 「开发者」会被拆成竖排（v0.13.2 工装实测）。
  Widget _developerRow(BuildContext context) {
    final muted = AppTokens.inkMuted(context);
    return LayoutBuilder(builder: (context, constraints) {
      final title = Text(L10n.aboutDeveloper, style: AppTokens.rowPrimary);
      final value = Text(
        L10n.aboutDeveloperName,
        style: AppTokens.rowSecondary.copyWith(color: muted),
      );
      final stacked = constraints.maxWidth < 260;
      return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceLg, vertical: AppTokens.spaceMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: AppTokens.gapHair),
              child: Icon(Icons.person_outline, size: AppTokens.iconLg),
            ),
            const SizedBox(width: AppTokens.spaceLg),
            Expanded(
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: AppTokens.gapHair),
                        value,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: AppTokens.spaceSm),
                        value,
                      ],
                    ),
            ),
          ],
        ),
      );
    });
  }

  Widget _linkRow({
    required BuildContext context,
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final muted = AppTokens.inkMuted(context);
    // **不用 `ListTile.subtitle` 装长地址**：给它 `maxLines: 1 + ellipsis`
    // 会在「320/360 + 特大字号」下把 URL 吃掉（text_fit_guard 实测抓了 4 处）；
    // 不设 maxLines 又会被 ListTile 的高度裁掉。这里改成自绘行，副标题随宽度
    // 换行、想占几行占几行 —— 完整地址永远看得见，代价只是那一行会变高。
    return GlassPressable(
      key: key,
      onTap: onTap,
      child: Semantics(
        button: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg, vertical: AppTokens.spaceMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: AppTokens.gapHair),
                child: Icon(icon, size: AppTokens.iconLg),
              ),
              const SizedBox(width: AppTokens.spaceLg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTokens.rowPrimary),
                    const SizedBox(height: AppTokens.gapHair),
                    Text(subtitle,
                        style: AppTokens.rowSecondary.copyWith(color: muted)),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              const Icon(Icons.chevron_right_outlined),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开外链。原生侧 `openUrl` 会吞掉异常并回传成败 —— 失败时给一条明确提示，
  /// 不让用户点了没反应还以为是 App 卡了。
  Future<void> _open(BuildContext context, String url) async {
    final ok = await AlarmService.openUrl(url);
    if (ok || !context.mounted) return;
    showGlassSnack(context, L10n.aboutOpenFailed, icon: Icons.error_outline);
  }
}
