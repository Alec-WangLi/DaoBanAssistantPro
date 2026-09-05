import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/update_checker.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../alarm/alarm_service.dart';

/// 统一风格的应用弹窗（版本更新 / 使用帮助），配色跟随主题主色。
void showAppInfoDialog(
  BuildContext context, {
  required String title,
  required String content,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (dialogContext) => GlassDialog(
      title: title,
      showClose: true,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: SingleChildScrollView(
          child: Text(
            content,
            style: const TextStyle(fontSize: 13.5, height: 1.55),
          ),
        ),
      ),
      actions: [
        GlassActionButton(
          variant: GlassActionVariant.primary,
          onPressed: () => Navigator.pop(dialogContext),
          label: L10n.ok,
        ),
      ],
    ),
  );
}

const String _changelogZh = 'v0.5.0\n'
    '· 正式稳定版（归纳 0.4.1~0.5.0 全部更新）\n'
    '· 开源：仓库公开（MIT 许可）；检查更新改为公开无鉴权接口，限流时自动回退发布清单；应用内直接下载安装\n'
    '· 视觉统一：悬浮玻璃胶囊导航、极简黑白背景 + 5 色主色、统一线性图标、弹簧 Q 弹动效\n'
    '· 外观：新增「高级材质」开关；低端机（内存 <4GB）自动关闭真实模糊\n'
    '· 响铃界面液态玻璃化：流动光晕 + 玻璃标签 + 跟手滑块关闭\n'
    '· 应用图标重绘；日历今日信息卡上移避让悬浮胶囊\n'
    '· 安装包：arm64 单 ABI 约 21MB（−65%）；独立正式签名、关闭 allowBackup\n'
    '· 修复：后台弹出界面权限、排班编辑间距、日历文字偏移、重启崩溃等\n\n'
    'v0.4.9\n'
    '· 底部胶囊浅色模式更清晰：柔和深色细描边 + 填充微调；胶囊略收窄、更适单手\n'
    '· 5 个主题色微调更沉稳协调；胶囊滑块上图标/文字改为自动对比色，任何颜色都清晰\n\n'
    'v0.4.8\n'
    '· 日历今日信息卡上移、不再被悬浮胶囊遮挡；胶囊通透度再微调\n\n'
    'v0.4.7\n'
    '· 底部胶囊更通透、内容无遮挡穿过：去掉浮层四周的空背景「蒙版」\n\n'
    'v0.4.6\n'
    '· 底部导航胶囊改回半透明磨砂玻璃：内容滑过若隐若现，去掉投影和左上角高光\n\n'
    'v0.4.5\n'
    '· 底部导航改为悬浮胶囊：去掉磨砂蒙版，内容滑动时清晰分离、从胶囊下方穿过\n'
    '· 移除随手机倾斜流动的动态光线（实测观感不佳），玻璃恢复静态高光\n'
    '· 应用图标重绘：中性底色 + 主色渐变玻璃符号，统一设计语言\n\n'
    'v0.4.4\n'
    '· 视觉大一统——极简黑白背景(自动深浅)+ 5 色主色只染强调点，液态玻璃统一配方并新增随手机倾斜流动的动态光线，图标统一线性，动效全面换弹簧 Q 弹。\n\n'
    'v0.4.3\n'
    '· 修复：排班编辑「班次名称」与「第几天/工作」标签间距过紧\n'
    '· 响铃界面：时间改粗体；「上滑关闭」改为跟随手指的滑块（拖到阈值触发、未到位回弹）\n'
    '· 新增「高级材质」开关（我的 → 外观）：默认开启，关闭后全 App 去真实模糊、模拟低端机\n\n'
    'v0.4.2\n'
    '· 修复：恢复「后台弹出界面」权限（v0.4.1 误删，导致 App 从系统列表消失、锁屏全屏闹钟可能弹不出）\n'
    '· 使用帮助按最新版重写（日历/排班/闹钟/待办/权限/更新 6 条）\n'
    '· 响铃界面液态玻璃化：深空蓝紫流动光晕 + 玻璃胶囊标签 + 玻璃按钮 + Q弹入场\n\n'
    'v0.4.1\n'
    '· 发布切 arm64 单 ABI：安装包 60.8MB → 约 21MB（−65%），仅 64 位设备\n'
    '· 玻璃模糊降级：低端机（内存 <4GB）自动关真实模糊；闹钟/待办/我的/排班列表行不再逐行模糊\n'
    '· 安全：release 改用独立正式签名（脱离 debug 证书，需卸载重装一次）；关闭 allowBackup；删除未使用的悬浮窗权限；下载文件名消毒\n\n';

const String _changelogEn = 'v0.5.0\n'
    '· Stable release (consolidating v0.4.1–v0.5.0)\n'
    '· Open source: repository made public (MIT); update check uses the public unauthenticated API with an automatic release-manifest fallback on rate limits; direct in-app download\n'
    '· Visual unification: floating glass capsule nav, monochrome background + 5 accent colors, outlined icons, spring motion\n'
    '· Appearance: "Advanced material" toggle; low-end devices (<4GB RAM) auto-disable real blur\n'
    '· Ringing screen in liquid glass: flowing glow + glass label + finger-tracking slider\n'
    '· App icon redrawn; calendar today-card raised above the floating capsule\n'
    '· Package: arm64-only ~21MB (−65%); independent release signing, allowBackup off\n'
    '· Fixes: overlay permission, schedule-editor spacing, cell text offset, restart crash, etc.\n\n'
    'v0.4.9\n'
    '· Bottom capsule clearer in light mode: subtle dark hairline outline + tuned fill; capsule slightly narrower for one-hand use\n'
    '· 5 accent colors refined; capsule slider icons/text now use an auto-contrast color, readable on any accent\n\n'
    'v0.4.8\n'
    '· Raised the calendar today-info card so the floating capsule no longer covers it; capsule translucency tuned slightly\n\n'
    'v0.4.7\n'
    '· More translucent bottom capsule, content flows underneath unobstructed — removed the empty “mask” band around it\n\n'
    'v0.4.6\n'
    '· Bottom nav capsule back to translucent frosted glass (content shows through while scrolling), removed its shadow and the top-left highlight\n\n'
    'v0.4.5\n'
    '· Floating bottom nav capsule: frosted-mask look gone, content cleanly passes under it while scrolling\n'
    '· Removed the tilt-reactive dynamic light (felt off in practice); glass highlight back to static\n'
    '· Redesigned the app icon: neutral background with an accent-gradient glass mark, matching the design language\n\n'
    'v0.4.4\n'
    '· Unified visual language — monochrome light/dark background, accent color confined to interactive highlights, unified glass recipe with tilt-reactive dynamic light, outlined icons, spring-based motion throughout.\n\n'
    'v0.4.3\n'
    '· Fixed: schedule editor spacing between "Shift name" and the day/work labels\n'
    '· Ringing screen: bolder clock; "Swipe up to dismiss" is now a finger-tracking slider (threshold to trigger, springs back if released early)\n'
    '· New "Advanced material" toggle (Me → Appearance): on by default; turn it off to remove all real blur and preview the low-end effect\n\n'
    'v0.4.2\n'
    '· Fixed: restored "Display over other apps" permission (removed by mistake in v0.4.1, hiding the app from the system list and possibly blocking the lock-screen alarm)\n'
    '· Usage guide rewritten for the latest version (calendar/schedule/alarm/todo/permissions/update)\n'
    '· Ringing screen in liquid glass: flowing deep-space gradient, glass label capsule, glass button, springy entrance\n\n'
    'v0.4.1\n'
    '· Release builds target arm64 only: APK 60.8MB → ~21MB (−65%), 64-bit devices only\n'
    '· Glass blur fallback: low-end devices (<4GB RAM) auto-disable real blur; alarm/todo/profile/schedule list rows no longer blur per-row\n'
    '· Security: independent release signing (no more debug key; one-time reinstall required), allowBackup off, unused overlay permission removed, download filename sanitized\n\n';

String get appChangelog => L10n.isEn ? _changelogEn : _changelogZh;

void showChangelogDialog(BuildContext context) {
  showAppInfoDialog(context, title: L10n.changelog, content: appChangelog);
}

/// 检查更新结果弹窗：展示正式版与测试版两个通道，各自可下载（仅当比当前新）。
void showUpdateDialog(BuildContext context, UpdateCheckResult result) {
  const current = appVersion;
  showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (dialogContext) => GlassDialog(
      title: L10n.checkUpdate,
      showClose: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${L10n.version}：v$current',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          Text(
            L10n.currentVersionHint,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(dialogContext)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
          ),
          _updateChannelRow(context, dialogContext, L10n.stableChannel,
              L10n.stableChannelHint, result.latestStable, current),
          _updateChannelRow(context, dialogContext, L10n.testChannel,
              L10n.testChannelHint, result.latestPrerelease, current),
        ],
      ),
      actions: const [],
    ),
  );
}

Widget _updateChannelRow(
    BuildContext outer, BuildContext ctx, String label, String hint,
    UpdateInfo? info, String current) {
  final muted = Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.55);
  final downloadable = info == null
      ? null
      : (UpdateChecker.compareVersion(info.version, current) > 0 ? info : null);
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(
                info == null ? L10n.none : 'v${info.version}',
                style: TextStyle(fontSize: 13, color: muted),
              ),
              Text(hint, style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
        ),
        if (downloadable != null)
          GlassActionButton(
            variant: GlassActionVariant.primary,
            onPressed: () {
              Navigator.pop(ctx);
              _downloadAndInstall(outer, downloadable);
            },
            label: L10n.download,
          )
        else
          Text(L10n.alreadyLatest, style: TextStyle(fontSize: 13, color: muted)),
      ],
    ),
  );
}

void showUsageGuideDialog(BuildContext context) {
  final items = [
    (Icons.calendar_month_outlined, L10n.guideCalTitle, L10n.guideCalDesc),
    (Icons.tune_outlined, L10n.guideSchedTitle, L10n.guideSchedDesc),
    (Icons.alarm_outlined, L10n.guideAlarmTitle, L10n.guideAlarmDesc),
    (Icons.event_note_outlined, L10n.guideTodoTitle, L10n.guideTodoDesc),
    (Icons.shield_outlined, L10n.guidePermTitle, L10n.guidePermDesc),
    (Icons.system_update_outlined, L10n.guideUpdateTitle, L10n.guideUpdateDesc),
  ];

  showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) {
      final accent = Theme.of(context).colorScheme.primary;
      final muted = Theme.of(context)
          .colorScheme
          .onSurface
          .withValues(alpha: 0.6);
      return GlassDialog(
        title: L10n.usageGuide,
        showClose: true,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final it in items) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent.withValues(alpha: 0.28),
                              accent.withValues(alpha: 0.10),
                            ],
                          ),
                          border: Border.all(
                              color: accent.withValues(alpha: 0.35)),
                        ),
                        child: Icon(it.$1, size: 20, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.$2,
                                style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text(it.$3,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.45,
                                    color: muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
        actions: [
          GlassActionButton(
            variant: GlassActionVariant.primary,
            onPressed: () => Navigator.pop(context),
            label: L10n.ok,
          ),
        ],
      );
    },
  );
}

/// 关闭更新弹窗后，弹出下载进度弹窗（内部完成下载并自动拉起系统安装器）。
void _downloadAndInstall(BuildContext context, UpdateInfo info) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black26,
    builder: (_) => _DownloadProgressDialog(info: info),
  );
}

/// 下载进度玻璃弹窗：实时百分比；下载完自动关闭并拉起安装，失败则就地提示。
class _DownloadProgressDialog extends StatefulWidget {
  const _DownloadProgressDialog({required this.info});

  final UpdateInfo info;

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  /// -1 = 不确定进度（转圈），0–100 = 百分比。
  int _percent = -1;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final file = await UpdateChecker.downloadApk(widget.info, onProgress: (p) {
      if (mounted) setState(() => _percent = p);
    });
    if (!mounted) return;
    if (file != null) {
      Navigator.pop(context);
      await AlarmService.installApk(file.path);
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: 0.6);
    return GlassDialog(
      title: L10n.downloadingUpdate,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'v${widget.info.version}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          if (_failed)
            Text(L10n.downloadFailed, style: TextStyle(fontSize: 13, color: muted))
          else if (_percent >= 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.radiusS),
              child: LinearProgressIndicator(
                value: _percent / 100,
                minHeight: 6,
                color: accent,
                backgroundColor: accent.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 8),
            Text('$_percent%',
                style: TextStyle(fontSize: 13, color: muted)),
          ] else ...[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(height: 10),
            Text(L10n.downloadingUpdate,
                style: TextStyle(fontSize: 13, color: muted)),
          ],
        ],
      ),
      actions: [
        if (_failed)
          GlassActionButton(
            onPressed: () => Navigator.pop(context),
            label: L10n.close,
          ),
      ],
    );
  }
}
