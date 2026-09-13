import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/update_checker.dart';
import '../../core/widgets/app_icon.dart';
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
            style: AppTokens.rowSecondary.copyWith(height: 1.55),
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

const String _changelogZh = 'v0.6.11\n'
    '· 全 App 的排版、间距与图标收敛到一套统一的设计规范：同一个用途的字号、字重、行高、透明度、间距从此只有一个来源，不会再各自跑偏\n'
    '· 次要文字的透明度此前散着 0.45 / 0.5 / 0.55 / 0.6 四种，现在统一到两档（常规 0.55、更淡的 0.35），同一个层级在哪个页面看都一样\n'
    '· 图标尺寸统一到三档（16 / 20 / 24），不再各处写 14 / 18 / 22 / 28\n'
    '· 卡片圆角由 20 归到 22，与列表行、提示条同档\n'
    '· 外观上的变化很轻：14 处字号、约 12 处字重各只动了一档，其余都只是内部换了写法\n\n'
    'v0.6.10\n'
    '· 修好「我的 → 关于」里的版本号：它从 v0.6.5 起就没再更新过，一直显示 v0.6.5。现在显示的是真实版本，而且升级到新版后「版本更新」简介会重新弹出（此前它一直不弹）\n'
    '· 「检查更新」里的「当前版本」不再显示错，也不会再给已经装上的版本挂「下载」按钮\n'
    '· 日历：当天信息卡的高度改为按**本月实际最满的一天**算出来，不再写死。没有法定节假日的月份卡片会明显变矮，省下的高度全部给日期网格\n'
    '· 更新日志补回 v0.6.6~v0.6.9 四条（此前只到 v0.6.5）\n'
    '· 使用帮助新增「外观」与「横屏 · 宽屏 · 小窗」两节，并把与实际界面不一致的「排班设置」正名为「排班管理」\n\n'
    'v0.6.9\n'
    '· 「法定节假日」徽章收成一行：图标 + 「法定节假日」+ 节日名一行放下，不再上下两行\n'
    '· 徽章的节日名更清楚了：此前原色红压在淡红底上，浅色 3.46:1、深色 3.37:1，都低于无障碍标准要求的 4.5:1；现在和「其他班组」色块走同一套文字取色规则，两套主题都过线\n'
    '· 徽章与「其他班组」色块统一成同一套外观：底色淡染、描边、圆角（12）现在完全一致\n'
    '· 卡片内的段落间距收进 4px 栅格（6→8、10→12）；日期那一行的字重收轻一档\n\n'
    'v0.6.8\n'
    '· 撤掉了卡片底部那层柔和底光\n'
    '· 卡片与底部导航胶囊之间放开了距离（从约 10dp 放到约 22dp）\n'
    '· 「法定节假日」徽章不再把农历挤到右边：徽章自占一行、农历独占下一行，长农历也能完整显示\n'
    '· 「其他班组」标签移到色块那一行左侧，不再独占一行；闹钟并进当天班次那一行\n'
    '· 顺带修好一个一直存在的问题：六班组那种排满的日子，卡片最后一行其实早就被底边裁掉了一截\n\n'
    'v0.6.7\n'
    '· 信息卡左侧那根颜色条不再错位：此前它比卡片本身长出一大截、垂在空白里（内容少的日子差得最多，能差 80 多 dp）。现在它两端与卡片严丝合缝，也跟着卡片一起变高变矮\n'
    '· 内容偏少的日子，卡片下部不再空荡荡\n\n'
    'v0.6.6\n'
    '· 日历最后一行不再被信息卡压住：五行的月份裁掉一条、六行的月份整个 31 号看不见，要靠滚动才露出来。真因是「格子高度的下限」还停在旧值 —— 比格子里的三行字实际需要的还高，等于让网格自己撑破屏幕\n'
    '· 节假日农历描述不再被截成省略号：「中秋节 · 农历八月十五」这类长名字此前单行显示，尾部被吃掉；现在允许两行\n'
    '· 信息卡底下的留白收窄，卡片贴近悬浮胶囊，省下的高度还给了日期网格\n'
    '· 系统字号放大时日历格子不再裁字：格子高度按屏幕剩余空间均分、不会跟着字号长，现在格子里的内容按需整体微缩\n\n'
    'v0.6.5\n'
    '· 小窗（小米小窗 / 分屏）修好：系统在小窗里把「顶部系统栏高度」报成整个窗口的高度，每一页的顶部安全区因此把整屏吃掉 —— 日历只剩一片背景色，只看得到底部那条胶囊。现在会先给系统栏数据做一道体检，小窗下七个界面全部正常\n'
    '· 小窗按实测尺寸（200×400）重新适配：日历顶栏改两行、日期格不再互相叠、倒班方式卡片改成上下排、闹钟页底部按钮不再压住正文\n'
    '· 日历：今日信息卡改为定高，点选不同日期时上方的日期格不再跟着一涨一缩\n'
    '· 日历：法定节假日徽章与农历说明并成一行，信息卡更紧凑\n'
    '· 小窗里两位数的日期不再折成上下两行；清除全部代码检查提示\n\n'
    'v0.6.4\n'
    '· 适配手机横屏与小窗：时间 / 日期 / 月份三个选择弹层此前在横屏下会溢出，现在按可用高度自适应\n'
    '· 日历在横屏与宽屏下改为左右分栏：左边日期网格、右边当天信息，格子不再被压成一屏只看得到一行\n'
    '· 小窗下信息卡压成一行（哪天 · 什么班 · 几点到几点），把高度让给日期网格\n'
    '· 悬浮导航胶囊在矮屏下自动收紧，各页底部留白同步收窄\n'
    '· 平板与车机等宽屏设备：内容限宽居中，不再横向拉满整屏\n'
    '· 窄屏下编辑器卡片内边距收紧，字号不缩\n\n'
    'v0.6.3\n'
    '· 排班编辑界面的字号与全 App 统一：此前班次名称与简称输入框被单独压小了一号，同一张卡片里的方案名称输入框却是一号大\n'
    '· 周期设置改成**行内直接点选班次**：每个可选班次平铺成一个彩色小块，点一下就换，不再弹出下拉菜单\n'
    '· 选中的班次块用班次色实心填充，文字颜色按底色自动取白或黑，浅色班次上的字不再糊得读不出来\n'
    '· 班次简称输入框加宽，两个汉字（如「大夜」）不会被裁掉\n'
    '· 删除班次改为低调图标（不再每行一个红点），按下时变红，并在真正删除前先确认一次\n\n'
    'v0.6.2\n'
    '· 英文界面：倒班方式模板的标题与副标题改为模板自带双语，不再漏出中文\n'
    '· 英文界面：从模板新建的排班，方案名与班次名（白班 / 夜班 / 休班 等）按你的语言生成，日历格子里的简称随之变成 D / N / O\n'
    '· 英文界面：默认排班与首次启动自动生成的班表同样按语言生成；模板可用英文关键词搜索（如 4-crew、dupont）\n'
    '· 周期色条超过 14 天时末格显示省略标记，不再静默截断（DuPont 这类 28 天周期一眼能看出后面还有）\n';

const String _changelogEn = 'v0.6.11\n'
    '· Typography, spacing and icons across the app now come from one shared design system: a single source per role for size, weight, line height, opacity and spacing, so they can no longer drift apart\n'
    '· Secondary text opacity used to be scattered across four values (0.45 / 0.5 / 0.55 / 0.6). It is now two tiers — 0.55 regular and 0.35 for the faintest — so the same level looks the same on every screen\n'
    '· Icon sizes are down to three steps (16 / 20 / 24) instead of ad-hoc 14 / 18 / 22 / 28\n'
    '· Card corners moved from 20 to 22, matching list rows and the snackbar\n'
    '· The visible change is subtle: 14 text sizes and about 12 font weights each moved one step, and the rest is only a change in how it is written internally\n\n'
    'v0.6.10\n'
    '· Fixed the version number in Me → About: it had not been updated since v0.6.5 and kept showing v0.6.5. It now shows the real version, and the "what\'s new" dialog reappears after an update (it had stopped appearing entirely)\n'
    '· The "current version" in Check for updates is no longer wrong, and it no longer offers a "Download" button for a version you already have\n'
    '· Calendar: the day card\'s height is now computed from the fullest day of the displayed month instead of being hard-coded. Months without a public holiday get a noticeably shorter card, and the freed height all goes to the date grid\n'
    '· The changelog now includes v0.6.6–v0.6.9 (it previously stopped at v0.6.5)\n'
    '· The usage guide gains "Appearance" and "Landscape · wide screens · small windows" sections, and "排班设置" is renamed to match the actual screen\n\n'
    'v0.6.9\n'
    '· The public-holiday badge is now a single row (icon + "法定节假日" + holiday name) instead of two\n'
    '· The holiday name in that badge is readable now: the raw red on pale red measured 3.46:1 in light and 3.37:1 in dark, both under the 4.5:1 accessibility bar; it now uses the same colour rule as the other-crew chips and passes in both themes\n'
    '· The badge and the other-crew chips now share one look: same tint, border and 12 radius\n'
    '· Section gaps inside the card moved onto the 4px grid (6→8, 10→12); the date row uses one lighter weight\n\n'
    'v0.6.8\n'
    '· Removed the soft glow at the bottom of the card\n'
    '· More space between the card and the floating nav capsule (about 10dp → 22dp)\n'
    '· The public-holiday badge no longer squeezes the lunar line: the badge takes its own row and the lunar line gets the next one, so long descriptions fit\n'
    '· The "other teams" label moved onto the chip row, and the alarm moved onto the shift line\n'
    '· Fixed a long-standing issue: on a full six-team day the card\'s last row was being clipped by its bottom edge\n\n'
    'v0.6.7\n'
    '· The colour bar on the left of the day card is aligned again: it used to run far past the card and hang in the empty space (up to 80-odd dp on light days). It now matches the card exactly at both ends and grows and shrinks with it\n'
    '· Days with little content no longer leave the card looking empty at the bottom\n\n'
    'v0.6.6\n'
    '· The calendar\'s last row is no longer covered by the day card: five-row months lost a row and six-row months lost the 31st entirely, reachable only by scrolling. The real cause was the day-cell minimum height, left at an old value higher than three lines of text actually need — which pushed the grid past the viewport\n'
    '· Long lunar descriptions are no longer truncated: names like "中秋节 · 农历八月十五" were shown on one line with an ellipsis; two lines are now allowed\n'
    '· Less dead space under the day card, so it sits closer to the floating capsule and the freed height goes back to the grid\n'
    '· Day cells no longer clip text at large system font sizes: cell height is divided from the space left over and does not grow with the font, so cell contents now scale down together instead\n\n'
    'v0.6.5\n'
    '· Small windows (Xiaomi floating window / split screen) are fixed: the system reports the top system-bar height as the whole window height there, so every page\'s top safe area swallowed the entire screen — the calendar showed nothing but background, with only the bottom capsule visible. System-bar data is now sanity-checked, and all seven screens work in a small window\n'
    '· The small-window layout was re-fitted to its measured size (200×400): the calendar header is two rows, day cells no longer overlap, pattern cards stack their colour strip below the text, and the alarm page\'s bottom buttons no longer cover the content\n'
    '· Calendar: the day card is now a fixed-height panel, so the day cells above it no longer grow and shrink as you tap through dates\n'
    '· Calendar: the public-holiday badge and the lunar line now share one row, making the card more compact\n'
    '· Two-digit dates no longer wrap onto two lines in a small window; all analyzer findings cleared\n\n'
    'v0.6.4\n'
    '· Phone landscape and small windows are now usable: the time, date and month pickers adapt to the available height instead of overflowing\n'
    '· On landscape and wide screens the calendar becomes two panes — month grid on the left, day details on the right — so day cells are no longer squashed\n'
    '· In a small window the day card collapses to a single line (date · shift · hours), giving the height back to the grid\n'
    '· The floating nav capsule shrinks on short screens, and pages reserve less space beneath it\n'
    '· On tablets and car head units the content is centred with a maximum width instead of stretching across the screen\n'
    '· Narrow screens get tighter editor paddings (text sizes unchanged)\n\n'
    'v0.6.3\n'
    '· Schedule editor typography now matches the rest of the app (input fields were a size smaller — two fields on the same card did not even match each other)\n'
    '· The cycle section now lets you pick a shift inline: every option is a coloured chip you tap, with no dropdown to open\n'
    '· A selected chip is filled with its shift colour, and its text is picked as white or black for readability — pale shifts are no longer washed out\n'
    '· The shift-abbreviation field is wider, so two characters are no longer clipped\n'
    '· Deleting a shift uses a quieter icon (no red dot on every row) that turns red while pressed, and asks for confirmation first\n\n'
    'v0.6.2\n'
    '· English UI: shift-pattern templates now carry their own bilingual titles and subtitles — no more Chinese leaking through\n'
    '· English UI: a schedule created from a template gets its name and shift names (Day shift / Night shift / …) in your language, and calendar cells use D / N / O\n'
    '· English UI: the default schedule and the one seeded on first launch are generated in your language; templates can be searched with English keywords (4-crew, dupont)\n'
    '· The cycle colour strip now shows an ellipsis in its last cell when a pattern runs past 14 days, instead of truncating silently\n';

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
            style: AppTokens.labelStrong,
          ),
          Text(
            L10n.currentVersionHint,
            style: AppTokens.tinyLabel
                .copyWith(color: AppTokens.inkMuted(dialogContext)),
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
  final muted = AppTokens.inkMuted(ctx);
  final downloadable = info == null
      ? null
      : (UpdateChecker.compareVersion(info.version, current) > 0 ? info : null);
  return Padding(
    padding: const EdgeInsets.only(top: AppTokens.spaceMd),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTokens.labelStrong),
              Text(
                info == null ? L10n.none : 'v${info.version}',
                style: AppTokens.rowSecondary.copyWith(color: muted),
              ),
              Text(hint, style: AppTokens.tinyLabel.copyWith(color: muted)),
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
          Text(L10n.alreadyLatest,
              style: AppTokens.rowSecondary.copyWith(color: muted)),
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
    (Icons.palette_outlined, L10n.guideAppearanceTitle,
        L10n.guideAppearanceDesc),
    (Icons.aspect_ratio_outlined, L10n.guideLayoutTitle, L10n.guideLayoutDesc),
    (Icons.shield_outlined, L10n.guidePermTitle, L10n.guidePermDesc),
    (Icons.system_update_outlined, L10n.guideUpdateTitle,
        L10n.guideUpdateDesc),
  ];

  showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) {
      final accent = Theme.of(context).colorScheme.primary;
      final muted = AppTokens.inkMuted(context);
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
                        child: AppIcon(it.$1,
                            size: AppTokens.iconMd, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.$2, style: AppTokens.labelStrong),
                            const SizedBox(height: AppTokens.padChipV),
                            Text(it.$3,
                                style: AppTokens.rowSecondary
                                    .copyWith(height: 1.45, color: muted)),
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
    final muted = AppTokens.inkMuted(context);
    return GlassDialog(
      title: L10n.downloadingUpdate,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'v${widget.info.version}',
            style: AppTokens.labelSecondary,
          ),
          const SizedBox(height: 16),
          if (_failed)
            Text(L10n.downloadFailed,
                style: AppTokens.rowSecondary.copyWith(color: muted))
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
                style: AppTokens.rowSecondary.copyWith(color: muted)),
          ] else ...[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(height: AppTokens.gapIconTextLg),
            Text(L10n.downloadingUpdate,
                style: AppTokens.rowSecondary.copyWith(color: muted)),
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
