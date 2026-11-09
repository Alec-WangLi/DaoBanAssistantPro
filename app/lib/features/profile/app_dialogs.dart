import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/update_checker.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_loading.dart';
import '../alarm/alarm_service.dart';
import 'help_entry.dart';

/// 统一风格的应用弹窗（版本更新），配色跟随主题主色。
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

const String _changelogZh =
'v0.13.1\n'
    '· 官网与国内下载镜像上线：APK 现在有一份放在国内能访问的站点上，不必再走 github.com 慢慢等\n'
    '· 「检查更新」改成先读官网的发布清单，读不到才回退到 GitHub —— 国内网络下不再先卡满 8 秒超时\n'
    '· 更新日志、截图与下载入口都在官网上，国内打开更快\n'
    '\n'
'v0.13.0\n'
    '· 重复待办这一轮整体收口：可以按班次重复（上夜班 / 下夜班那天自动出现）、每月多选几天、随时改规则；提醒按当天值班时间落在前一天 / 当天 / 次日；行回到它属于的班次那天，副标题写「上夜班 · 次日 00:00」；勾掉或删掉之后那一次不再响，勾错了点「撤销」提醒会回来；冷启动也会把提醒重新排上\n'
    '· 桌面小组件：三张固定尺寸的卡（本周条 / 今日卡 / 整月），现在会跟着系统的深浅色自动切换；同步失败会自己重试，字号不跟系统字号走\n'
    '· 排班：班组卡排版收口（输入框收窄、周期起始日不再又长又矮）；排班管理与编辑排班里的箭头去掉，整行仍然可点\n'
    '· 液态玻璃：底栏胶囊的真折射与彩边、开关与分段器的液态档、滑块两端真圆\n'
    '· 待办：勾完收进「已完成 N 条」，点回勾就回到主列表；行尾的编辑笔去掉\n'
    '· 外观：字号四档、深色模式、16 种班次色 + 自定义取色\n'
    '· 修：冷启动后重复待办的提醒会重新排上；签名校验默认硬拦，避免装出「签名冲突」的包\n'
    '\n'
'v0.12.11\n'
    '· 桌面小组件现在会跟着系统的深浅色自动切换了：App 里选「跟随系统」时，系统切到深色 / 浅色，三张卡当场换色，不用再打开 App\n'
    '· 重复待办的行回到它属于的那个班次那天：上夜班 20:30–次日 08:30 配 02:00 的待办，行挂在上夜班那天，提醒仍在次日 02:00；副标题把「上夜班 · 次日 02:00」一起写出来\n'
    '· 修：勾选（或删掉）重复待办之后，那一次的提醒不再弹出 —— 以前打勾了，到点还会响\n'
    '· 修：勾错了点「撤销」，那一次的提醒会跟着回来\n'
    '· 修：App 冷启动后会重新排上重复待办的提醒 —— 以前要打开待办页才回来\n'
    '· 说明：旧版跨午夜的重复待办在升级后会挪回班次那天；极少数旧系列在升级后可能少出现一次，再下一次就恢复正常\n'
    '\n'
'v0.12.10\n'
    '· 底栏那圈边光重新配了亮度：深色档下不再白得发亮，浅色档下那条细边也终于看得清 —— 以前它几乎融进底色里\n'
    '· 按住开关拖动、上滑关闹钟的时候，那颗圆钮的两头一直是真圆了：之前会被拉成一头尖一头胖的椭圆\n'
    '\n'
'v0.12.9\n'
    '· 底栏那圈彩色边缘回来了 —— 上一版把它让给了「弯折」那层，可那层只有部分机型画得出来，于是没轮到的人看到的是一枚既没有颜色、也没有弯折的胶囊。现在彩边一直画着，弯折在支持的机型上叠在上面，两者不再互相顶掉\n'
    '· 桌面小组件不再是白块：同步没成功时它自己重试两次，还不行就在你下次打开 App 时提示一次；实在拿不到数据时写「打开 App 同步排班」，而不是一片空白\n'
    '· 极端字号下月历格每行只差一两个像素时，不再因此多出一条滚动条（差得多时照样会滚，格子的最小高度没让步）\n'
    '· 待办行右边那颗铅笔去掉了 —— 整行本来就能点开编辑，那颗图标只会让人以为这里有两件事\n'
    '· 夜班的重复待办挂到了它真正要提醒的那天 —— 比如 20:30 上班、提醒设在 0 点，以前行在上班当天就冒出来，现在跟提醒一起落在次日；行上那条「次日 00:00」的小字也随之不再需要\n'
    '\n'
'v0.12.8\n'
    '· 底栏那枚玻璃胶囊的边缘现在会把背后的内容轻轻「弯」过去一点 —— 它读起来像一块有厚度的玻璃，而不是一张磨砂纸。这一层只在给得住它的手机上出现，别的机型与以前一模一样\n'
    '· 顺着这条，胶囊边缘那圈画出来的彩色收掉了：真玻璃几乎没有虹彩，那圈颜色在咱们这套极简黑白底上只能靠画。方向感现在由上面那层弯折承担\n'
    '· 分段器与开关一个像素都没动 —— 它们小得多，同一套弯折放到 46dp 的开关上会让整颗钮抖起来\n'
    '\n'
'v0.12.7\n'
    '· 修：编辑排班的班组卡里，「周期起始日」与箭头现在贴住右边（之前整组停在半路，右边空出一大截）；宽屏 / 横屏下「我的班」芯片也不再漂在卡片中间\n'
    '· 修：待办行的「次日 00:00」标记只在真的会响时显示 —— 系列停用、或没设提醒时不显示\n'
    '· 文案：帮助与更新说明里「钟点不在值班时间里」的说法改准 —— 晚于上班时间又不在值班窗口里时落在前一天（上班前），早于上班时间时按离上班 / 下班哪边近来定\n'
    '· 无障碍：班组卡里那两行值行重新被读成按钮\n'
    '\n'
'v0.12.6\n'
    '· 重复待办的「按班次」提醒现在按当天的值班时间算落在哪天：上夜班（20:30–次日 08:30）配凌晨 0 点的提醒，会落在次日 0 点，不再是上班当天凌晨；钟点晚于上班时间、又不在值班窗口里时落在前一天（上班前），早于上班时间时按离上班还是离下班近来定\n'
    '· 待办列表那一行会标出落点（「次日 00:00」/「前一天 23:00」），与闹钟列表同一套说法\n'
    '· 「按班次」规则的说明里补了一句落点规则\n'
    '· 编辑排班 → 班组设置：「班组名」输入框不再占掉大半行；「周期起始日」那一行加高了（约 44dp），点起来不再发虚\n'
    '\n'
'v0.12.5\n'
    '· 修：弹窗里的值行（待办的时间与提醒、闹钟的时间与日期）右侧的值与箭头现在贴齐右边；200dp 小窗下标签与值改成上下两行，标签不再被截掉\n'
    '· 修：班组设置折叠时那行班组名，8 个长名字装不下会改成「N 个班组 · 点开可改名」，不再把字裁掉；清空的班组名也不会留下「 · 二班」这种空段\n'
    '· 修：小窗 + 特大字号下，调过班的那天信息卡不再把班次名截成「白…」\n'
    '· 无障碍：弹窗里的值行重新被读成按钮\n'
    '\n'
'v0.12.4\n'
    '· 班组名现在看得出来能改了：编辑排班里每个班组是一只有框的输入框（之前是个光秃秃的文本框，读起来像固定的名单）；「班组设置」折叠时也会把当前班组名列出来，并写着「点开可改名」\n'
    '· 全 app 统一了「哪些东西能点」的提示：铅笔表示点开进入编辑（待办、自定义闹钟、我的模板）；箭头表示点开打开选择器、页面或弹窗（弹窗里的时间与日期、日历信息卡那行班次、排班管理里每套方案、我的页那几个入口、窄屏的模板卡）\n'
    '· 日历底下那张信息卡与小窗模式都补上了箭头；小窗里的时间改成按宽度缩小，不再被省略号吃掉\n'
    '· 班组设置的「周期起始日」与「从第 N 段入场」改成箭头；「每月第 N 天起」与「我这组从这个周期开始」也改箭头，铅笔从此只表示「进入编辑」\n'
    '· 修：窄屏下「周期起始日」那一行加箭头后会横向溢出；现在标签与日期会一起按宽缩小\n'
    '\n'
    ;

const String _changelogEn =
'v0.13.1\n'
    '· A download mirror is live: the APK is also served from a site that is reachable from mainland China, so installing no longer means waiting on github.com\n'
    '· Check for updates now reads the mirror manifest first and only falls back to GitHub when that fails, so it no longer burns the full 8-second timeout on a slow network\n'
    '· The changelog, screenshots and download link all live on the site too\n'
    '\n'
'v0.13.0\n'
    '· Recurring todos are rounded out: repeat by shift (night / late), pick several days of the month, edit the rule any time; reminders land on the previous / same / next day per the shift window; the row sits on its shift day with a subtitle like "Night - next day 00:00"; checking or deleting an occurrence stops its reminder, Undo brings it back, and a cold start re-schedules them\n'
    '· Home-screen widgets: three fixed-size cards (week strip / today / month) now follow the system light and dark theme; a failed sync retries on its own; the font size does not follow the system setting\n'
    '· Schedule: the crew card layout is tightened; the arrows in Schedule management and the editor are gone, while the whole row stays tappable\n'
    '· Liquid glass: real refraction and the colour rim on the nav capsule, liquid segments and switches, round slider ends\n'
    '· Todos: completed items move into "N completed" and come back when unchecked; the edit pencil is gone\n'
    '· Appearance: four font sizes, dark mode, 16 shift colours plus a custom picker\n'
    '· Fixes: recurring reminders are re-scheduled after a cold start; the signature check now fails closed, so a mismatched APK cannot be published\n'
    '\n'
'v0.12.11\n'
    '· The home-screen widgets now follow the system light / dark theme: with the app set to Follow system, all three cards switch as soon as the system does, without opening the app\n'
    '· A recurring todo now sits on the shift day it belongs to: a 02:00 todo on a 20:30-08:30 night shift lives on the shift day, while its reminder still fires at 02:00 the next day; the subtitle spells out "Night - next day 02:00"\n'
    '· Fix: checking off (or deleting) a recurring todo now stops that occurrence from ringing - it used to fire anyway\n'
    '· Fix: tapping Undo after a mistaken check restores that reminder\n'
    '· Fix: a cold start now re-schedules recurring reminders - before, they only came back after opening the todo page\n'
    '· Note: existing cross-midnight todos move back to their shift day on upgrade; a rare old series may skip one occurrence once, then continue normally\n'
    '\n'
'v0.12.10\n'
    '· The rim along the nav bar has been re-lit: in the dark theme it no longer glows white, and in the light theme the thin edge is finally visible - it used to blend into the background\n'
    '· Hold and drag the switch, or swipe up to stop an alarm, and the knob now stays properly round at both ends instead of being pulled into a lopsided oval\n'
    '\n'
'v0.12.9\n'
    '· The colour rim on the nav bar capsule is back. The last version handed that job to the bending layer, but that layer only exists on some phones - everyone else got a capsule with neither colour nor bending. The rim is drawn again, always, and the bending stacks on top where it is available\n'
    '· The home-screen widget no longer goes blank: a failed sync retries twice on its own and then says so once the next time you open the app; when there is really no data it reads "Open the app to sync" instead of an empty card\n'
    '· At very large text sizes the calendar no longer grows a scrollbar over a one- or two-pixel shortfall per row (a larger shortfall still scrolls - the minimum cell height is unchanged)\n'
    '· The pencil on todo rows is gone - the whole row already opens the editor, and the icon only suggested there were two things to tap\n'
    '· A recurring todo on a night shift now sits on the day it really reminds you: with a 20:30 shift and a 00:00 reminder the row used to appear on the shift day and now appears with the reminder on the next day. The small "next day 00:00" label on such rows is gone with it\n'
    '\n'
'v0.12.8\n'
    '· The edge of the nav bar capsule now bends the content behind it a little, so it reads as a piece of glass with thickness rather than a sheet of frosted paper. That layer only appears on phones that can render it; everything else looks exactly as before\n'
    '· The painted colour rim along that capsule is gone with it: real glass has almost no iridescence, and on this flat black-and-white background that ring could only ever be drawn. The sense of direction now comes from the bending layer\n'
    '· Segments and switches are unchanged to the pixel - they are far smaller, and the same bending on a 46 dp switch would make the whole knob wobble\n'
    '\n'
'v0.12.7\n'
    '· Fix: in the crew card, the cycle start date and its chevron now sit flush right (the pair used to stop mid-row with a wide gap); on landscape and tablet widths the Set as mine chip no longer floats in the middle of the card\n'
    '· Fix: the next-day / day-before marker on a todo row now only shows when a reminder can actually fire — a paused series or one with no reminder shows none\n'
    '· Copy: the help and release notes now describe the landing rule accurately: a moment later than the shift start but outside the window lands on the day before (ahead of the shift); earlier moments go to whichever side is nearer\n'
    '· Accessibility: the two value rows in the crew card are read as buttons again\n'
    '\n'
'v0.12.6\n'
    '· Reminders on shift-based repeating todos now follow the shift\'s working hours: a 00:00 reminder on a night shift (20:30 to 08:30 next morning) lands at 00:00 the next day instead of the small hours of the shift\'s starting day; moments later than the shift start but outside the window land on the day before, ahead of the shift; earlier moments go to whichever side is nearer\n'
    '· The todo row now marks that landing (next-day 00:00 / day-before 23:00), the same wording the alarm list uses\n'
    '· The By shift hint now says how the landing is decided\n'
    '· Edit schedule > crew settings: the name field no longer takes most of the row, and the cycle start date row is taller (about 44 dp), so it reads as tappable\n'
    '\n'
'v0.12.5\n'
    '· Fix: value rows in dialogs (todo time and reminder, alarm time and date) now put the value and arrow flush right; at 200 dp the label and value stack into two lines instead of the label being clipped\n'
    '· Fix: the collapsed crew subtitle falls back to "N crews · tap to rename" when eight long custom names do not fit, instead of clipping; an emptied name no longer leaves a stray separator\n'
    '· Fix: in a small window at the largest text size, the info card no longer cuts the shift name to "D…" on an adjusted day\n'
    '· Accessibility: value rows in dialogs are announced as buttons again\n'
    '\n'
'v0.12.4\n'
    '· Crew names now look editable: each crew in the editor is a labelled input field, where it used to be a bare text box that read like a fixed list. The Crews section also lists the current crew names while collapsed, with "tap to rename"\n'
    '· One rule now tells you what can be tapped: a pencil opens an editor (todos, custom alarms, my templates); an arrow opens a picker, a page or a dialog (times and dates in dialogs, the shift row on the calendar info card, each schedule in Schedule management, the entries on Me, and template cards on narrow screens)\n'
    '· The calendar info card and the small-window card both gained the arrow; the time in the small-window card now shrinks to fit instead of being cut off with an ellipsis\n'
    '· Crew cycle start and segment start now use arrows; so do "from day N of each month" and "my crew starts this cycle on", leaving the pencil to mean "opens an editor" only\n'
    '· Fix: on narrow screens the crew cycle-start row overflowed once it had an arrow; the label and date now shrink together\n'
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
/// **《使用帮助》自 v0.11.17 起不再是弹窗**（它是整页了，见
/// `help_center_screen.dart`），「桌面小组件」那份说明也并进了它 ——
/// 于是这个壳子只剩「开始使用」一个用户。**留着它**：那是全 app 唯一一个
/// 「内容是一份短条目清单」的弹窗，下一个要弹类似东西的人照它办，
/// 而不是又造一套圆角 / 滚动上限 / 按钮措辞。
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
        HelpEntry(
            icon: Icons.edit_calendar_outlined,
            title: L10n.gettingStartedSchedTitle,
            lines: [L10n.gettingStartedSchedBody],
            bulleted: false),
        const SizedBox(height: 16),
        HelpEntry(
            icon: Icons.shield_outlined,
            title: L10n.gettingStartedPermTitle,
            lines: [L10n.gettingStartedPermBody],
            bulleted: false),
        const SizedBox(height: 16),
        HelpEntry(
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
              child: GlassLoading(size: 24),
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
