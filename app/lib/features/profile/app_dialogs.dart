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

const String _changelogZh = 'v0.6.3\n'
    '· 排班编辑界面的字号与全 App 统一：此前班次名称与简称输入框被单独压小了一号，同一张卡片里的方案名称输入框却是一号大\n'
    '· 周期设置改成**行内直接点选班次**：每个可选班次平铺成一个彩色小块，点一下就换，不再弹出下拉菜单\n'
    '· 选中的班次块用班次色实心填充，文字颜色按底色自动取白或黑，浅色班次上的字不再糊得读不出来\n'
    '· 班次简称输入框加宽，两个汉字（如「大夜」）不会被裁掉\n'
    '· 删除班次改为低调图标（不再每行一个红点），按下时变红，并在真正删除前先确认一次\n\n'
    'v0.6.2\n'
    '· 英文界面：倒班方式模板的标题与副标题改为模板自带双语，不再漏出中文\n'
    '· 英文界面：从模板新建的排班，方案名与班次名（白班 / 夜班 / 休班 等）按你的语言生成，日历格子里的简称随之变成 D / N / O\n'
    '· 英文界面：默认排班与首次启动自动生成的班表同样按语言生成；模板可用英文关键词搜索（如 4-crew、dupont）\n'
    '· 周期色条超过 14 天时末格显示省略标记，不再静默截断（DuPont 这类 28 天周期一眼能看出后面还有）\n\n'
    'v0.6.1\n'
    '· 日历：日期格按屏幕高度自适应长高，不再在网格与底部信息卡之间留一条空带\n'
    '· 日历：格子里的班次简称按底色自动调整明度，浅色班次（橙、灰）不再糊在白格子上\n'
    '· 对比度：「今天」按钮与信息卡「今天」徽章改为实心主色 + 白字，实测对比度由 2.7:1 提升到 5.3:1\n'
    '· 我的：主色调选中项加白色描边——此前选中色块与选中药丸同色，等于看不出选了哪个\n'
    '· 英文界面修正：月份标题（此前显示为「2026 9」）、起始日日期格式、被裁切的班次简称标签、未跟随语言的倒班方式分组标题\n\n'
    'v0.6.0\n'
    '· 排班编辑器重写为两层轮换模型：班次定义（配一次，时间 / 颜色 / 联动闹钟都挂在上面）+ 周期表（长度即周期，1–60 天）\n'
    '· 内置 19 种常见倒班方式模板：新建排班时选一个最像的即可起步\n'
    '· 班组用「周期起始日」表达，各班组错位一目了然；编辑器未来 14 天实时预览\n'
    '· 日历格子简称改由班次自带；查看其他班组改为色块列表\n'
    '· 24 小时值班正确显示「08:00 – 次日 08:00」；旧数据自动升级（v5 → v6），重复班次自动合并\n\n'
    'v0.5.0\n'
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
    '· 应用图标重绘：中性底色 + 主色渐变玻璃符号，统一设计语言\n\n';

const String _changelogEn = 'v0.6.3\n'
    '· Schedule editor typography now matches the rest of the app (input fields were a size smaller — two fields on the same card did not even match each other)\n'
    '· The cycle section now lets you pick a shift inline: every option is a coloured chip you tap, with no dropdown to open\n'
    '· A selected chip is filled with its shift colour, and its text is picked as white or black for readability — pale shifts are no longer washed out\n'
    '· The shift-abbreviation field is wider, so two characters are no longer clipped\n'
    '· Deleting a shift uses a quieter icon (no red dot on every row) that turns red while pressed, and asks for confirmation first\n\n'
    'v0.6.2\n'
    '· English UI: shift-pattern templates now carry their own bilingual titles and subtitles — no more Chinese leaking through\n'
    '· English UI: a schedule created from a template gets its name and shift names (Day shift / Night shift / …) in your language, and calendar cells use D / N / O\n'
    '· English UI: the default schedule and the one seeded on first launch are generated in your language; templates can be searched with English keywords (4-crew, dupont)\n'
    '· The cycle colour strip now shows an ellipsis in its last cell when a pattern runs past 14 days, instead of truncating silently\n\n'
    'v0.6.1\n'
    '· Calendar: day cells now grow to fill the screen height — the empty band between the grid and the info card is gone\n'
    '· Calendar: shift labels are lightness-adjusted against their backdrop, so pale shifts (amber, grey) no longer wash out on white cells\n'
    '· Contrast: the "Today" button and the info-card "Today" badge are now solid accent with white text (measured 2.7:1 -> 5.3:1)\n'
    '· Me: the selected accent swatch gets a white ring — previously it shared its colour with its own selection pill and was invisible\n'
    '· English UI fixes: month header (showed "2026 9"), start-date format, the clipped shift-abbr label, and pattern group headings that stayed Chinese\n\n'
    'v0.6.0\n'
    '· Schedule editor rewritten around a two-layer rotation model: shift definitions (configure once — time / color / linked alarm live on them) + a cycle table (its length is the cycle, 1–60 days)\n'
    '· 19 built-in shift-pattern templates: pick the closest one when creating a schedule\n'
    '· Teams are phased by a "cycle start date"; live 14-day preview inside the editor\n'
    '· Calendar cell labels now come from each shift; other teams shown as a color-block list\n'
    '· 24-hour duty shifts show "08:00 – next day 08:00"; old data auto-upgrades (v5 → v6) with duplicate shifts merged\n\n'
    'v0.5.0\n'
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
    '· Redesigned the app icon: neutral background with an accent-gradient glass mark, matching the design language\n\n';

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
