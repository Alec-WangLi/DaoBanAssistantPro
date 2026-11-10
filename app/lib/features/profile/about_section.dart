// app/lib/features/profile/about_section.dart
//
// 「我的 → 关于」与「我的 → 支持」两张卡。
//
// 从 `profile_screen.dart` 抽出来，有两个原因：
//   1. 新加的「关于倒班助手Pro」入口要有位置，而 `profile_screen.dart` 已在
//      E14 的超 800 行台账里，不能再往上堆；
//   2. 检查更新与查看日志本来就只属于「关于」这一块，搬出去之后 profile 只留
//      外观 / 排班 / 桌面 / 闹钟 / 数据 / 权限六块。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_info.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/update_checker.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../alarm/alarm_service.dart';
import 'about_screen.dart';
import 'app_dialogs.dart';
import 'donate_sheet.dart';
import 'help_center_screen.dart';
import 'supporter_screen.dart';
import 'supporter_store.dart';

/// 「关于」卡：关于页入口 + 检查更新 + 版本更新 + 使用帮助 + 查看日志。
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassTile(
      translucentFill: false,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          GlassPressable(
            child: ListTile(
              leading: const Icon(Icons.info_outlined),
              title: Text(L10n.aboutApp),
              subtitle: Text(L10n.aboutAppSubtitle(appVersion)),
              trailing: const Icon(Icons.chevron_right_outlined,
                  key: Key('profile-chevron-about')),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
            ),
          ),
          const Divider(height: 1),
          GlassPressable(
            child: ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: Text(L10n.checkUpdate),
              subtitle: Text(L10n.checkUpdateSubtitle),
              trailing: const Icon(Icons.chevron_right_outlined,
                  key: Key('profile-chevron-update')),
              onTap: () => _checkUpdate(context),
            ),
          ),
          const Divider(height: 1),
          GlassPressable(
            child: ListTile(
              leading: const Icon(Icons.new_releases_outlined),
              title: Text(L10n.changelog),
              subtitle: Text(L10n.changelogSubtitle),
              trailing: const Icon(Icons.chevron_right_outlined,
                  key: Key('profile-chevron-changelog')),
              onTap: () => showChangelogDialog(context),
            ),
          ),
          const Divider(height: 1),
          GlassPressable(
            child: ListTile(
              leading: const Icon(Icons.help_outlined),
              title: Text(L10n.usageGuide),
              subtitle: Text(L10n.usageGuideSubtitle),
              trailing: const Icon(Icons.chevron_right_outlined,
                  key: Key('profile-chevron-help')),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HelpCenterScreen()),
              ),
            ),
          ),
          const Divider(height: 1),
          GlassPressable(
            child: ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: Text(L10n.viewLog),
              subtitle: Text(L10n.viewLogSubtitle),
              trailing: const Icon(Icons.chevron_right_outlined,
                  key: Key('profile-chevron-log')),
              onTap: () => _showLog(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkUpdate(BuildContext context) async {
    final r = await UpdateChecker.checkUpdates();
    if (!context.mounted) return;
    if (r.error) {
      showUpdateFailedDialog(context);
      return;
    }
    showUpdateDialog(context, r);
  }

  Future<void> _showLog(BuildContext context) async {
    final log = await AlarmService.readLog();
    if (!context.mounted) return;
    await showGlassDialog<void>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: L10n.log,
        showClose: true,
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: SingleChildScrollView(
            child: SelectableText(
              log.isEmpty ? L10n.noLog : log,
              style: AppTokens.microText.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          GlassActionButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: log));
              if (dialogContext.mounted) {
                showGlassSnack(dialogContext, L10n.logCopied,
                    icon: Icons.content_copy_outlined);
              }
            },
            label: L10n.copy,
          ),
          const SizedBox(width: 8),
          GlassActionButton(
            onPressed: () async {
              await AlarmService.clearLog();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            label: L10n.clear,
          ),
        ],
      ),
    );
  }
}

/// 「支持」卡：打赏入口 + 支持者专属入口。
///
/// 支持者专属当前是「打赏后自报解锁」：个人收款码没有支付回调，App 不可能
/// 知道钱到没到账，所以只认用户在打赏弹层里点的「我已完成支付」。这是有意
/// 的取舍 —— 打赏是自愿的，未支付也不影响任何功能，这一行只决定显示锁还是信。
class SupportSection extends StatefulWidget {
  const SupportSection({super.key});

  @override
  State<SupportSection> createState() => _SupportSectionState();
}

class _SupportSectionState extends State<SupportSection> {
  bool _unlocked = false;

  /// 打赏弹层开着 / 刚解锁正在推信 —— 防止连点叠两层。
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final unlocked = await readSupporterUnlocked();
    if (!mounted) return;
    setState(() => _unlocked = unlocked);
  }

  Future<void> _openDonate() async {
    if (_opening) return;
    _opening = true;
    try {
      final unlocked = await showDonateSheet(context);
      if (!mounted) return;
      await _load();
      if (unlocked != true || !mounted) return;
      showGlassSnack(context, L10n.donateUnlocked,
          icon: Icons.favorite_outline);
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SupporterScreen()),
      );
    } finally {
      _opening = false;
    }
  }

  void _openSupporter() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SupporterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassTile(
      translucentFill: false,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          GlassPressable(
            child: ListTile(
              leading: const Icon(Icons.local_cafe_outlined),
              title: Text(L10n.supportDeveloper),
              subtitle: Text(L10n.supportDeveloperSubtitle),
              trailing: const Icon(Icons.chevron_right_outlined,
                  key: Key('profile-chevron-donate')),
              onTap: _openDonate,
            ),
          ),
          const Divider(height: 1),
          GlassPressable(
            child: ListTile(
              leading: Icon(_unlocked
                  ? Icons.workspace_premium_outlined
                  : Icons.lock_outline),
              title: Text(L10n.supporterOnly),
              subtitle: Text(_unlocked
                  ? L10n.supportUnlockedHint
                  : L10n.supportUnlockHint),
              trailing: const Icon(Icons.chevron_right_outlined,
                  key: Key('profile-chevron-supporter')),
              onTap: _unlocked ? _openSupporter : _openDonate,
            ),
          ),
        ],
      ),
    );
  }
}
