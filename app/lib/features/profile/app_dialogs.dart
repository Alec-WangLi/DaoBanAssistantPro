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
'v0.12.6\n'
    '· 重复待办的「按班次」提醒现在按当天的值班时间算落在哪天：上夜班（20:30–次日 08:30）配凌晨 0 点的提醒，会落在次日 0 点，不再是上班当天凌晨；钟点不在值班时间里时，按离上班还是离下班近来定\n'
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
'v0.12.3\n'
    '· 重复待办新增「按班次」：从排班表的班次里多选（比如上夜班、下夜班），到这些班次那天自动出现。它按班次名字匹配，换排班表后只要新表里有同名班次就继续生效；名字对不上时「重复待办」面板会明确写出来\n'
    '· 「每月」现在能多选几天：比如每月 1 号、15 号各签一次记录；小月没有的日期落在当月最后一天，同一天只出现一次\n'
    '· 新建待办选「每周」时，七个星期格子排成一行等宽，不再挤成两行\n'
    '· 「重复待办」面板行尾的小铅笔去掉了 —— 整行点进去本来就是编辑\n'
    '· 修：在待办页新建的重复待办现在会立刻排上提醒，不用等下次打开 App\n'
    '\n'
'v0.12.2\n'
    '· 待办标题框改成 1~3 行自动长高（添加与编辑都有）：长标题以前只看得见尾巴，想改前面的内容得先把字滚回去\n'
    '· 已添加的重复待办现在能直接改规则了：在「重复待办」面板点任何一条，就能改标题、每天 / 每周 / 每月（每周可勾任意几天）、时间与提醒。就算它这一轮还没有「当前这一次」也改得动 —— 以前每月 1 号的系列在 1 号之前列表里没有那一条，点面板只会弹一句「没有下一次」\n'
    '· 面板每一行加了小铅笔、点整行都能进；只改标题时不会把你手工挪过的那一次拽回规则日\n'
    '\n'
'v0.12.1\n'
    '· 修：在「排班管理」里换「其余时间 / 全部日子」、增删改排班时段、或者删掉一套排班表之后，日历立刻变了，但系统里已经排好的闹钟没跟着变 —— 旧方案里的班次闹钟还按旧日子响。10 月 18 日晚上就是它：当天明明是白班，19:30 却响了旧方案里上夜班的闹钟。现在这三处一改就立刻重排全部闹钟\n'
    '· 修：全屏响铃界面上的时刻是 12 小时制却不写上午 / 下午 —— 20:10 的闹钟响起来，屏幕上写的是「08:10」。现在跟全 app 其余地方一样走 24 小时制\n'
    '\n'
'v0.12.0\n'
    '· 桌面小组件贴齐 App：今日卡补齐班次备注 / 其他班组 / 本月统计，主色竖条通到卡底；月历「今天」换成半透明块、周标题改单字、班次胶囊按文字宽现量；三张卡的字号不再跟系统字号走\n'
    '· 按月排班：每月 1 号重新开始的一套切法，编辑排班顶上在「周期 / 按月」之间切换，段可加可删\n'
    '· 班次颜色扩到 16 种，并能自己调：色相条 + 饱和度/明度方盘 + 十六进制，两颗日历小样当场变色\n'
    '· 待办自动归档：做完的收进「已完成 N 条」，主列表只留没做的；一次性待办能从归档里点回来\n'
    '· 字号四档，App 自己管、不跟系统字号走；日历顶栏与信息卡跟着重排，不省略\n'
    '· 横屏 / 平板 / 车机上日历改成左右两栏；底部弹层统一头部、按住往下一拉就关；全 app 的小节标题、空态、加载态与按压反馈收成一套\n'
    '· 闹钟落点扩到前一天 / 当天 / 次日三档，每个班次上限 6 → 10 条；贪睡时长可选 1 / 5 / 10 / 15 / 20 / 30 分钟\n'
    '· 修：浅色档下状态栏图标跟着主题走、输入框标签在真机字体下不再被压扁、实心主色面上改白字、底部导航彩边接缝、编辑排班的「每月第 N 天起」不再省略、待办勾选后的「撤销」在切页后仍然生效\n'
    '\n'
'v0.11.26\n'
    '· 今日卡最左边那条主色竖条通到卡片底了 —— 以前它只有「日期」那一行那么高\n'
    '· 今日卡「其他班组」换成了 App 里那种半透明胶囊（之前是圆点加光秃秃的文字），几颗紧挨着排左边\n'
    '\n'
'v0.11.25\n'
    '· 周条上「今天」那一块玻璃长高了：以前格子里那三行（周几 / 日期 / 班次）离块的上下边只剩一点点，看着像贴着边画的；现在上下多留出跟左右一样多的空隙\n'
    '· 今日卡的「其他班组」那一行字大了一档 —— 它原来比 App 里同一行、也比这张卡自己的「本月统计」小一号，是搬过来时掉了一级，不是没位置\n'
    '\n'
'v0.11.24\n'
    '· 桌面小组件的班次胶囊改成跟着文字宽窄走：以前是个一刀切的定值，格子一小它就顶满格子、跟格子边贴在一起；现在「白」是窄的、「大休」是宽的，左右都留出跟 App 里一样的间隙\n'
    '· 周条跟月历对齐了：今天那一列也换成半透明块（不再是实心一块），周标题改成「一 二 三 …日」\n'
    '· 编辑排班的「每月第 N 天起」不再出现省略号 —— 明明旁边还有位置，却被挤成了「每月第 3…」\n'
    '\n'
    ;

const String _changelogEn =
'v0.12.6\n'
    '· Reminders on shift-based repeating todos now follow the shift\'s working hours: a 00:00 reminder on a night shift (20:30 to 08:30 next morning) lands at 00:00 the next day instead of the small hours of the shift\'s starting day; moments outside the shift go to whichever side of it is nearer\n'
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
'v0.12.3\n'
    '· Repeating todos gain a "By shift" rule: pick shifts from your schedule (night, late and so on) and the todo shows up on those days. Matching is by shift name, so switching schedules keeps it working as long as the new one has the same name; when it does not, the Repeating panel says so\n'
    '· Monthly repeats can now pick several days at once, for example the 1st and the 15th; in shorter months those days fall on the last day, and never twice in one day\n'
    '· The weekday row in "Weekly" now fits seven equal cells on one line instead of wrapping to two\n'
    '· Removed the small pencil at the end of each Repeating panel row — tapping the row was already the edit button\n'
    '· Fix: a repeating todo created on the todo page now gets its reminder scheduled immediately instead of waiting for the next app launch\n'
    '\n'
'v0.12.2\n'
    '· The todo title field now grows from one to three lines (both adding and editing): long titles used to show only their tail, so fixing the beginning meant scrolling back first\n'
    '· Added recurring todos can now be edited directly: tap any row in the "Repeating" panel to change its title, daily / weekly / monthly rule (pick any weekdays), time and reminder. It works even when the series has no current occurrence right now — before, a monthly series due on the 1st had no row before that day, and tapping the panel only said "no current occurrence"\n'
    '· Each panel row now shows a small pencil and the whole row opens the editor; changing only the title no longer pulls an occurrence you moved by hand back to the rule date\n'
    '\n'
'v0.12.1\n'
    '· Fix: changing the fallback schedule (All days), adding, editing or deleting a schedule period, or deleting a schedule in Schedule management updated the calendar immediately, but alarms already set on the system did not follow - alarms from the old schedule still rang on their old days. That is what happened on the evening of 18 Oct: the day was a day shift, yet a night-shift alarm rang at 19:30. All three now re-plan every alarm immediately\n'
    '· Fix: the clock on the full-screen ringing page used a 12-hour hour without AM/PM - a 20:10 alarm showed "08:10". It now uses the same 24-hour format as the rest of the app\n'
    '\n'
'v0.12.0\n'
    '· Home-screen widgets now match the app: the today card gained the shift note, other crews and month tally, and the accent bar runs the full height; the month view marks today with the translucent block, uses single-character weekday headers and sizes shift chips to their text; none of the three cards follow the system font size any more\n'
    '· Monthly rosters: a schedule that starts over on the 1st of every month, switchable at the top of the editor, with addable and removable segments\n'
    '· Shift colours expanded to 16, plus a custom picker: hue bar, saturation/value square and hex input, with two live calendar samples\n'
    '· Todo auto-archive: completed items collect under "N completed" and the main list keeps only open ones; one-off items can be ticked back out of the archive\n'
    '· Four text sizes managed by the app rather than the system; the calendar header and info card reflow without ellipsis\n'
    '· The calendar becomes two columns in landscape, on tablets and car screens; bottom sheets share one header and can be pulled down to close; section headings, empty and loading states and press feedback are unified across the app\n'
    '· Alarm anchors now cover the day before, the same day and the next day; up to 10 alarms per shift; snooze length selectable from 1 to 30 minutes\n'
    '· Fixes: status-bar icons follow the theme in light mode, field labels are no longer squashed under the device font, white text on solid accent surfaces, the coloured rim seam on the nav bar, the editor no longer truncates "from day N of each month", and undo still works after switching tabs\n'
    '\n'
'v0.11.26\n'
    '· The accent bar on the left of the today card now runs the full height of the card - before it was only as tall as the date row\n'
    '· The Other crews row on the today card uses the same translucent capsules as the app, packed together on the left; it used to be bare dots with plain text\n'
    '\n'
'v0.11.25\n'
    '· The today block in the week strip is taller. The three rows inside it (weekday, date, shift) used to sit right against its top and bottom edges; they now keep the same breathing room all round as they do left and right\n'
    '· The Other crews row on the today card is one size larger. It had come over a step smaller than the same row in the app, and smaller than the month tally line on the same card - that was a slip when porting, not a lack of room\n'
    '\n'
'v0.11.24\n'
    '· The widget shift chips now follow how wide their text is: they used to be a fixed size, so in a small cell the chip filled it and touched both edges. A one-character shift is narrow and a two-character one is wide, each keeping the same gap the app leaves\n'
    '· The week strip now matches the month widget: its today column is a translucent block instead of a solid one, and the weekday header uses the single-character form\n'
    '· The editor no longer truncates “from day N of each month” — there was room beside it, and it still came out as “from day 3…”\n'
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
