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
  showGlassDialog<void>(
    context: context,
    builder: (dialogContext) => GlassDialog(
      title: title,
      showClose: true,
      // **不要再套一层 `ConstrainedBox(420) + SingleChildScrollView`**：那会造出
      // 第二个、更小的视口，正文仍然在它自己的底边被切断（而且切在按钮上方一点点，
      // 看着还是像有块板子）。`GlassDialog` 现在自己就是「整块面板高的滚动区 +
      // 浮在上面的动作行」，交给它就行。
      content: Text(
        content,
        style: AppTokens.rowSecondary.copyWith(height: 1.55),
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

const String _changelogZh = 'v0.10.22\n'
    '· 滑动更跟手了：真正的开销一直在「画面合成」那一侧，这一版把其中最贵的一道工序省掉了 —— 编辑排班、日历、闹钟、待办这几页每帧的合成开销降到原来的三分之一上下（编辑排班 13.1ms → 6.0ms、日历 10.4ms → 2.3ms）\n'
    '· 手指按住不动时，背景那层光晕不再冻住（之前是按着就停）\n'
    '· 顺手把「换月」也算进光晕该停的那一刻\n'
    '· 拨一下触觉开关不再把整个界面重建一遍\n'
    '· 待办 / 闹钟 / 排班上的日期文案不再每次重算\n'
    '· 响铃 15 分钟没人管会自己停（之前会一直响、一直震）\n'
    '· 排闹钟不再一条一条写盘（一次重排从 62 次降到 4 次）\n'
    '· 桌面小组件的刷新改用非精确闹钟，少占一份系统唤醒额度\n'

    'v0.10.21\n'
    '· 修好上一版带进来的三处「改完之后界面没跟上」：调整某一天的班次、或者换语言之后，桌面小组件现在会跟着变（之前会一直停着旧的）\n'
    '· 调整班次、改周期之后，信息卡那行「本月统计」现在会跟着变（之前还是旧数字）\n'
    '· 长按拖选一段日子时，日历不再每一帧重算整页 —— 上一版的更新说明里写了这一条，当时其实还没做到\n\n'

    'v0.10.20\n'
    '· 更顺了：点日期、「今天」飞回去、按住拖动那枚选中的块、长按拖选一段日子时，日历不再每帧重算整页\n'
    '· 更省电了：那层缓缓流动的光晕不再牵着整页一起重画（你按住拖动的时候它会停一下、松手接着走 —— 观感上几乎看不出来）\n'
    '· 打开 App 快了一点；翻月、勾待办、改排班之后的卡顿也少了\n'
    '· 桌面小组件：内容没变时不再重复推一遍（从后台切回来不再白算一次整月数据）\n\n'

    'v0.10.19\n'
    '· 修好一处崩溃：长按拖选当中用另一根手指点 ‹ / › 换月，日历会当场报错（那一段的日子不在新月里，落点算不出来却还在硬画那条带子）\n'
    '· 上一版那枚水带「按住四面鼓起来」的判据补严了一格：它本来就画得出来，但一直靠同层里阴影顺带重画 —— 现在把它算进「该不该重画」\n\n'

    'v0.10.18\n'
    '· 长按拖选一段日子时，那层逐格的淡色小方块换成了一条连着的水带：同一周内是一整条，格子之间的缝也盖住了\n'
    '· 按住那一下它会四面鼓起来、像水一样漫上来；拖动时末端淌到新的一格，它探进哪一格、那一格的字就被轻轻挤一下\n'
    '· 水带的两端是圆的；跨周时那两头切平（月历里跨周不是相邻的格子，是从最右列跳到下一行的最左列）\n'
    '· 液态玻璃关着的时候，拖选与之前一模一样（逐格淡色方块，一个像素都没动）\n\n'

    'v0.10.17\n'
    '· 日历上那枚选中的块，点别的日期、再点「今天」时，现在是飞回去的：飞的时候一圈彩色折射光亮起来，形状按飞行的方向拉长、变扁\n'
    '· 它飞过哪几格，那几格的字就被轻轻挤一下（之前被挤的是终点那一格 —— 块还在半路上，终点就已经先动了）\n'
    '· 落定之后这些自己收回去，静止时与之前一样\n'
    '· 拖动那枚块时，形状是「开」出来的，不再一下拉满（与底栏滑块同一套手感）\n\n'

    'v0.10.16\n'
    '· 修好上一版带进来的一处问题：拖完日历上那枚选中的块、再点一下日期，它会自己抽一下（陈旧的速度被反复灌回来）\n'
    '· 按住那枚块不动时，它的形变现在会自己收回去（之前会一直挂着）\n\n'

    'v0.10.15\n'
    '· 日历上那枚选中的方块，在「液态玻璃」档下变成一枚真的玻璃透镜：按住时四面鼓出来、底下浮起一层影子\n'
    '· 拖动时它跟着手指的方向拉长、变扁，边上带一圈彩色折射光（停下就没了）\n'
    '· 它扫过哪一天，那一天的字（日期 / 班次 / 农历）就被它的边缘轻轻挤一下\n'
    '· 液态玻璃关着的时候，日历与之前一模一样（一个像素都没动）\n\n'

    'v0.10.14\n'
    '· 修好上一版带进来的一处问题：弹窗会顶到状态栏 / 手势条里（21 个弹窗都受影响）\n'
    '· 底部弹层往下拖着要关掉时，不再被压暗、发糊\n'
    '· 响铃页那枚「上滑关闭」的形变在高刷新率屏幕上不再只有一半（同一个拖动速度应当有同一个形状）\n'
    '· 四个弹窗的遮罩浓度统一成与其余弹窗一样（模板管理 / 改名 / 删除、存为模板）\n\n'

    'v0.10.13\n'
    '· 开关拖动时，背景色跟着滑块一起变（之前要松手那一刻才跳变）：颜色从一边漫过去、边界就压在滴下面\n'
    '· 弹窗与底部弹层出现时从模糊里凝出来、关掉时化开散掉（之前是生硬地淡入）\n'
    '· 响铃页的「上滑关闭」：圆钮换成一枚玻璃药丸，按住会变大、凸出轨道，轨道那两条边被折进它里面\n'
    '· 修好一处「折边」在竖直面上一直没生效的问题（响铃页那枚药丸、以及小窗里的底栏滑块）\n\n'

        '\n'
;

const String _changelogEn = 'v0.10.22\n'
    '· Smoother scrolling: the real cost was on the compositing side, and this version drops the most expensive step of it — per-frame compositing on the editor, calendar, alarm and todo screens is now about a third of what it was (editor 13.1ms → 6.0ms, calendar 10.4ms → 2.3ms)\n'
    '· The background glow no longer freezes while you simply hold your finger down\n'
    '· Month switching is now part of when the glow pauses, too\n'
    '· Toggling the haptics switch no longer rebuilds the whole interface\n'
    '· Date strings on the todo, alarm and schedule screens are no longer rebuilt every time\n'
    '· A ringing alarm stops itself after 15 minutes if nobody attends to it (it used to ring and buzz forever)\n'
    '· Scheduling alarms no longer writes to disk once per alarm (62 writes per reschedule → 4)\n'
    '· The home-screen widget refresh now uses an inexact alarm, spending less of the system wake-up budget\n'

    'v0.10.21\n'
    '· Fixed three "the screen did not keep up" cases from the previous version: after adjusting a single day or switching language the home-screen widget now updates (it used to stay on the old shifts)\n'
    '· After adjusting a day or editing the cycle, the info card\'s monthly tally now updates (it used to keep the old numbers)\n'
    '· Long-press selecting a run of days no longer rebuilds the whole calendar every frame — the previous release notes claimed this, but it was not actually done yet\n\n'

    'v0.10.20\n'
    '· Smoother: tapping a date, flying back to Today, dragging the selection block and long-press selecting a run of days no longer rebuild the whole calendar every frame\n'
    '· Lighter on the battery: the slowly drifting glow no longer repaints the page along with it (it pauses while you drag and carries on after — you will not notice)\n'
    '· Faster start-up, and less stutter after switching months, ticking a to-do or saving a schedule\n'
    '· Home-screen widgets: an unchanged snapshot is no longer pushed again (returning to the app no longer recomputes the whole month for nothing)\n\n'

    'v0.10.19\n'
    '· Fixed a crash: with a range drag in progress, using a second finger to tap the month arrows left the calendar throwing errors (those days are not in the new month, so the band had nothing to anchor to yet was still drawn)\n'
    '· Tightened one repaint criterion for the previous version water band: the press swell did render, but only because the shadow in the same layer happened to repaint alongside it — it is now part of the check\n\n'

    'v0.10.18\n'
    '· Long-pressing to select a run of days now draws one continuous water band instead of a pale block per cell — within a week it is a single strip that covers the gaps between cells\n'
    '· Pressing swells it on all four sides, like water rising; dragging lets the tip flow into the next cell, and the day it reaches gets a slight squeeze\n'
    '· The band ends are round; where it wraps to the next week the two ends are cut flat (in a month grid a week wrap is not an adjacent cell)\n'
    '· With Liquid Glass off, selection is exactly as before (a pale block per cell, pixel for pixel)\n\n'

    'v0.10.17\n'
    '· The calendar selection block now flies back when you tap another date and then Today: a prismatic rim lights up on the way, and the shape stretches along its direction of travel\n'
    '· The days it sweeps over get a slight squeeze (before, the squeeze sat on the destination while the block was still in mid-air)\n'
    '· All of it settles back once it lands — at rest it looks exactly as before\n'
    '· While dragging, the shape blooms instead of snapping to full (the same feel as the tab bar pill)\n\n'

    'v0.10.16\n'
    '· Fixed a regression from the previous version: after dragging the calendar selection block, tapping a day made it stretch and flash once (a stale drag velocity was re-applied)\n'
    '· Holding the block still now lets its stretch relax (it used to stay stretched)\n\n'

    'v0.10.15\n'
    '· The selected day block on the calendar becomes a real glass lens in the Liquid Glass tier: it bulges out on all four sides while held, with a lifted shadow\n'
    '· While you drag it stretches along the direction of travel and flattens, with a prismatic rim that only shows while it is moving\n'
    '· As it sweeps over a day, that day text (date / shift / lunar) gets a slight squeeze at its edge\n'
    '· With Liquid Glass off the calendar is pixel-for-pixel what it was\n\n'

    'v0.10.14\n'
    '· Fixed a regression from the previous version: dialogs could sit under the status bar or gesture bar (21 of them were affected)\n'
    '· A bottom sheet no longer dims and blurs while you drag it down to dismiss it\n'
    '· The ringing screen pill deforms correctly on high-refresh-rate screens (the same drag speed now gives the same shape)\n'
    '· Four dialogs\' backdrop dim now matches the rest (template manage / rename / delete, save as template)\n\n'

    'v0.10.13\n'
    '· The switch track now tints as you drag (it used to jump the moment you let go): the colour sweeps in from one side, its edge tucked under the knob\n'
    '· Dialogs and bottom sheets condense out of blur and dissolve away, instead of just fading in\n'
    '· The ringing screen\'s "swipe up to dismiss" knob is now a glass pill: hold it and it grows past the track, and the track\'s edges fold into it\n'
    '· Fixed the folded-edge effect never lighting up on vertical drops (the ringing pill, and the tab bar slider in a small window)\n\n'

        '\n'
;
String get appChangelog => L10n.isEn ? _changelogEn : _changelogZh;

void showChangelogDialog(BuildContext context) {
  showAppInfoDialog(context, title: L10n.changelog, content: appChangelog);
}

/// 检查更新结果弹窗：展示正式版与测试版两个通道，各自可下载（仅当比当前新）。
void showUpdateDialog(BuildContext context, UpdateCheckResult result) {
  const current = appVersion;
  showGlassDialog<void>(
    context: context,
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

/// 检查更新失败的提示：说清「连不上 GitHub、国内要开代理」。
///
/// 走弹窗而不是 snack —— snack 只停 2 秒，这条提示却要用户读完再去做一件事。
void showUpdateFailedDialog(BuildContext context) {
  showAppInfoDialog(
    context,
    title: L10n.checkUpdate,
    content: L10n.updateCheckFailed,
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
                info == null ? L10n.channelNone : 'v${info.version}',
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

/// 帮助类弹窗的公共外壳：同一个 [GlassDialog]、同样的滚动上限与「知道了」。
///
/// 「开始使用」与「使用帮助」只有内容不同，壳子必须一模一样 —— 各写一套的话
/// 两个弹窗的圆角、滚动上限、按钮措辞会慢慢漂开。
void _showHelpDialog(
  BuildContext context, {
  required String title,
  required Widget content,
}) {
  showGlassDialog<void>(
    context: context,
    builder: (dialogContext) => GlassDialog(
      title: title,
      showClose: true,
      // **不要再套 `ConstrainedBox(maxHeight: …) + SingleChildScrollView`。**
      // 它造出**第二个更小的视口**：正文在那个高度就结束，面板底下空一截，
      // 用户读成「按钮没浮起来、底下压着一层蒙版」（2026-10-01 反馈）。
      // `GlassDialog` 自己的内容区就铺满面板、并负责滚动，动作行由它用
      // `Positioned` 浮在上面 —— 这里只要把 content 原样交给它。
      // （v0.10.0 从 `showAppInfoDialog` 里拆掉的就是这两层，这个调用点当时漏了。）
      content: content,
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

/// 首次启动弹的「开始使用」。
///
/// **不要退回成直接弹「使用帮助」**（2026-09-23 改的）：那份是九个条目、
/// 一千多字的说明书，当欢迎页用等于没写 —— 新用户第一眼要知道的是「现在该
/// 干什么」。完整说明仍在「我的 → 使用帮助」里，这条路径由最后一句话指出去。
void showGettingStartedDialog(BuildContext context) {
  final muted = AppTokens.inkMuted(context);
  _showHelpDialog(
    context,
    title: L10n.gettingStarted,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.gettingStartedLead,
            style: AppTokens.rowSecondary.copyWith(height: 1.45, color: muted)),
        const SizedBox(height: 16),
        _GuideEntry(
            icon: Icons.edit_calendar_outlined,
            title: L10n.gettingStartedSchedTitle,
            lines: [L10n.gettingStartedSchedBody],
            bulleted: false),
        const SizedBox(height: 16),
        _GuideEntry(
            icon: Icons.shield_outlined,
            title: L10n.gettingStartedPermTitle,
            lines: [L10n.gettingStartedPermBody],
            bulleted: false),
        const SizedBox(height: 16),
        _GuideEntry(
            icon: Icons.touch_app_outlined,
            title: L10n.gettingStartedOverrideTitle,
            lines: [L10n.gettingStartedOverrideBody],
            bulleted: false),
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Text(L10n.gettingStartedMore,
            style: AppTokens.rowSecondary.copyWith(height: 1.45, color: muted)),
      ],
    ),
  );
}

/// 「我的 → 桌面小组件」那一行的说明弹层。
///
/// 正文与《使用帮助》里的同一条目**共用一份文案**（`L10n.guideWidgetDesc`）——
/// 各写一份的话，改了这边忘了那边，就成了「说明书和 App 说的不一样」。
/// 弹窗标题已经把「是什么」说了，条目里不再顶一行标题（`title: null`）。
void showWidgetGuideDialog(BuildContext context) {
  _showHelpDialog(
    context,
    title: L10n.guideWidgetTitle,
    content: _GuideEntry(
      icon: Icons.widgets_outlined,
      title: null,
      lines: L10n.guideWidgetDesc,
    ),
  );
}

void showUsageGuideDialog(BuildContext context) {
  final items = <(IconData, String, List<String>)>[
    (Icons.calendar_month_outlined, L10n.guideCalTitle, L10n.guideCalDesc),
    (Icons.tune_outlined, L10n.guideSchedTitle, L10n.guideSchedDesc),
    (Icons.alarm_outlined, L10n.guideAlarmTitle, L10n.guideAlarmDesc),
    (Icons.event_note_outlined, L10n.guideTodoTitle, L10n.guideTodoDesc),
    (Icons.widgets_outlined, L10n.guideWidgetTitle, L10n.guideWidgetDesc),
    (Icons.palette_outlined, L10n.guideAppearanceTitle,
        L10n.guideAppearanceDesc),
    (Icons.aspect_ratio_outlined, L10n.guideLayoutTitle, L10n.guideLayoutDesc),
    (Icons.shield_outlined, L10n.guidePermTitle, L10n.guidePermDesc),
    (Icons.system_update_outlined, L10n.guideUpdateTitle,
        L10n.guideUpdateDesc),
  ];

  _showHelpDialog(
    context,
    title: L10n.usageGuide,
    content: Column(
      children: [
        for (final it in items) ...[
          _GuideEntry(icon: it.$1, title: it.$2, lines: it.$3),
          const SizedBox(height: 16),
        ],
      ],
    ),
  );
}

/// 帮助弹窗里的一条：图标 + 标题 + 正文行。
///
/// [lines] 多于一行时每行前面加一个小圆点（参考条目是多项并列，得能扫）；
/// 只有一行、且是引导语时把 [bulleted] 关掉 —— 单条正文顶个圆点像没写完的列表。
class _GuideEntry extends StatelessWidget {
  const _GuideEntry({
    required this.icon,
    required this.title,
    required this.lines,
    this.bulleted = true,
  });

  final IconData icon;

  /// 条目标题。**为空时整行标题不画**（连那 8dp 间距一起）—— 「我的 → 桌面小组件」
  /// 那个说明弹层只有一份并列的短句，弹窗标题已经说了是什么，条目再顶一行标题
  /// 就是同一句话说两遍。
  final String? title;
  final List<String> lines;
  final bool bulleted;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final muted = AppTokens.inkMuted(context);
    final body =
        AppTokens.rowSecondary.copyWith(height: 1.45, color: muted);
    return Row(
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
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: AppIcon(icon, size: AppTokens.iconMd, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(title!, style: AppTokens.labelStrong),
                const SizedBox(height: AppTokens.padChipV),
              ],
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) const SizedBox(height: AppTokens.spaceXs),
                if (!bulleted)
                  Text(lines[i], style: body)
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 圆点用固定 4dp（设计语言里「被改过的那天」也是这个尺寸），
                      // 不跟字号缩放 —— 小窗下缩到 1~2px 就等于没有。
                      // 上边距是把它压到首行文字中线上（spaceSm = 8），
                      // 7 那种值不上 4px 栅格，会打红 design_tokens_test。
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(top: AppTokens.spaceSm),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: muted.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 走 Expanded 而不是给整段加「· 」前缀：英文条目会折行，
                      // 前缀写法的第二行会顶到最左边、看不出是同一条。
                      Expanded(child: Text(lines[i], style: body)),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 关闭更新弹窗后，弹出下载进度弹窗（内部完成下载并自动拉起系统安装器）。
void _downloadAndInstall(BuildContext context, UpdateInfo info) {
  showGlassDialog<void>(
    context: context,
    // 下载做到一半不许被点掉。
    barrierDismissible: false,
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
