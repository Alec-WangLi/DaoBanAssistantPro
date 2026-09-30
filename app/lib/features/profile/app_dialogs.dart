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

const String _changelogZh = 'v0.10.3\n'
    '· 底栏滑块重做：按住它时会吸附到手指上、放大成一枚真的玻璃滴，拖得越快形状拉得越长，松手带一点回弹地落回那一格\n'
    '· 它的边缘现在有一圈跟着主色调走的彩色折射光；凸出胶囊时，胶囊那条边会在它里面被折进去\n'
    '· 点一下照旧：滑块滑过去、切页，不提起 —— 凸起是「按住」专属的\n'
    '· 关掉液态玻璃时，玻璃的观感与上一版一致\n\n'

    'v0.10.2\n'
    '· 底栏选中滑块不再比胶囊大 —— 按住时才凸出来成一枚透镜，松手缩回\n'
    '· 滑块的吸附恢复了磨砂玻璃那种平滑（之前是瞬移）；开关现在能按住拖动；主题模式 / 主色调这些分段选择器也带上了同一层效果\n'
    '· 修好几处光加错了地方：待办、闹钟列表的每一行都被描了一圈边（那些行本来就没有模糊）\n'
    '· 使用帮助弹窗底下不再多出一截空白（按钮真正浮在正文上）\n'
    '· 深色下底栏选中那一格的白字对比度回到达标\n\n'
    'v0.10.1\n'
    '· 「我的 → 外观」里那颗「高级材质」换成了「液态玻璃」，默认关。打开之后玻璃边缘带上一层光；底栏的选中滑块与开关在你按住时鼓起成一枚透镜 —— 玻璃件凸出容器之外，光才有边可落\n'
    '· 关掉就是现在这个样子（磨砂玻璃），只是名字与说明跟着改了\n'
    '· 内存小于 4GB 的机器一律保持关闭\n\n'
    'v0.10.0\n'
    '· 桌面小组件三张卡都在了：本周条、今日卡、整月。整月那张把上个月下个月连起来画，标题行两边的箭头能翻前后各三个月；在 App 里改了排班，桌面立刻跟着变\n'
    '· 每个班次最多能挂 6 条闹钟，每条可以起名字 —— 「起床」「午休」分开响\n'
    '· 排班时段重做：在「排班管理」页的一条时间线上排「哪几天用哪套班表」，两段不许重叠，其余时间可以设成「无」（领导真给休息几天时，不必专门再建一套休息班表）。一套班表还能出现在多段上 —— 9 月临时换、10 月换回来\n'
    '· 多套班表按日期衔接：日历、闹钟、桌面小组件都按天取「那天归哪套」，翻回历史看到的也是那时的班、不是现在的\n'
    '· 重复待办：每周三的会到点自己冒出来，勾掉的留成历史；提醒由系统自己续排，App 长期不开也照常响\n'
    '· 「法定班次」（跟随法定节假日）现在就是一张日历：只画日期与农历，不再替它写「上班 / 休息」\n'
    '· 日历上能单独改某几天的班（请假、跟同事换班）：点信息卡那行班次，或长按格子拖选一段；改过的那天有标记，也能一键恢复轮转\n'
    '· 「我的模板」：调好的班表存下来，下次新建排班直接从最上面那组里选\n'
    '· 闹钟铃声多了一档「仅震动」，也能从手机里自选音频\n'
    '· 修好一批评测里报上来的毛病：桌面小组件的字重影、系统字号放大后日历文字被截、待办与闹钟列表最后一行被悬浮按钮压住、弹窗按钮跑到左边、弹层里正文被按钮拦腰切断、零点班（00:00 上班）的闹钟排在班次当天而不是上班前一晚……\n'
    '· 「我的」页的说明重写了一遍，并多了一条「桌面小组件」（怎么加到桌面、装完新版为什么要先打开一次 App）\n'
    '· 清空重置现在真的回到刚安装的样子：排班、日程、闹钟、模板、你保存的铃声与外观设置一起清掉\n'
    '\n'

    'v0.9.19\n'
    '· 修好弹窗里的按钮跑到左边：上一版为了让小窗（200×400）下「删除 / 取消 / 保存」这种多按钮弹窗不横向溢出，动了弹窗共用的按钮行 —— 结果全 App 的弹窗（版本更新、删除确认、排班时段……）的按钮都变成了靠左。现在恢复靠右，小窗该折行的照样折行\n'
    '· 编辑排班页底部那颗「保存并重排闹钟」不再垫着一条挡板：它是浮在正文上的，界面滑到它下面时能看见内容从底下穿过去（此前正文到那条按钮带的上沿就被硬切，下面露出一整片平色）。滑到底时最后一张卡会整个抬到按钮上面，不会被压住\n'
    '\n'

    'v0.9.18\n'
    '· 桌面小组件那张月历能翻的范围，从「前后各一个月」放宽到「前后各三个月」—— 标题行两边的箭头点一下翻一月。顺带一个好处：你更久不开 App，卡片上的数据也还够用\n'
    '· 装完新版请先打开一次 App：小组件上的班次是 App 上次运行时算好的，不打开的话卡片还是旧样子（重启桌面也能让它重画，但没必要）。这条从这一版起写进更新说明，免得你以为升级把桌面弄乱了\n'
    '· 修好待办与闹钟列表的一个毛病：条目多的时候，最后一行会被右下角那颗悬浮按钮（以及闹钟页底部那条按钮条）压住，删除键点不到。现在滑到底能把它绕到按钮上面\n'
    '· 「排班时段 → 添加时段」那个弹层的字体与同一页对齐了：里面三个标签原来又小又轻一档（13/w400），现在与打开它的那一行一样（14/w500）\n'
    '· 顺手修掉小窗（200×400）下这个弹层的两处布局毛病：三个按钮挤不下时横向溢出、日期那两行的取值放不下\n'
    '\n'

    'v0.9.17\n'
    '· 桌面小组件那张月历（最大的那张）现在把上个月和下个月的日子连起来一起画了：月头月尾那几格不再是空的，相邻的日数字淡一档、班次照常显示，整张卡读起来是一段连续的日子\n'
    '· 那张卡的标题行多了左右两个箭头：点一下翻上 / 下月，翻到没有数据的月份那侧会变灰；点中间的月份文字回到今天那个月\n'
    '· 翻到你关注的月份之后，跨天、跨月都不会把你拽回来 —— 停在你翻到的那个月，直到你自己点回今天\n'
    '\n'

    'v0.9.16\n'
    '· 「法定班次」（跟随法定节假日）不再写「上班 / 休息」了：这种班表在日历格子、小窗那张信息卡与桌面小组件上都只画日期与农历 —— 法定节假日照旧标红、调休照旧打「班」。它本质上就是一张日历，上一版替它标上「上班」是我想多了\n'
    '· 顺带：这种班表下信息卡不再为那一行留高度，卡片矮约 16dp，上面六个格子相应高一点\n'
    '· 上一版改对的那一半照旧：「这段时间没有排班」那句只在真的没有任何班表盖着这些天时才出现 —— 判定它的是「这天有没有班表在管」，与「这天画不画得出东西」从此分开看\n'
    '\n'

    'v0.9.15\n'
    '· 「法定班次」（跟随法定节假日）不再被当成「没有排班」了：这种班表每一天都画得出来 —— 法定节假日写「休息」、其余日子写「上班」，日历格子、小窗那张信息卡与桌面小组件同一个口径。此前只有一套这种班表时，整张日历被「这段时间没有排班」盖住，可你明明是按法定节假日上班的\n'
    '· 排班管理页分成两节：「排班时段」在上、「排班表」在下，各带一个标题，不再挤成一片\n'
    '· 一个时段都没有时，那行改说「全部日子」，不再说「其余时间」：「其余」得有「这一段」才有意义，一段都没有时那句话会被读成「这是默认一直用它的意思吗」\n'
    '· 修好「排班时段」弹层里的「取消」：点了没有任何反应。顺手把「删除 / 取消 / 保存」三颗钮之间补上间隔（原先紧挨着）\n'
    '· 待办页那个「重复待办」入口挪到了右上角（原来紧贴在标题后面，看着像标题的一部分）\n'
    '· 修好更新说明里的 markdown 标记：像「两段时间不许重叠」那种加粗写法会原样带上两个星号。更新日志走的是纯文本渲染，标记不会被解析；这回补了一条用例盯着，再混进去就直接失败\n'
    '· 修好「把每周三改成每周五」这条路径在周三、周四不生效：编辑一个重复待办时会把系列的起始日改写成「当前这一次」的日期，于是「最近的那个周五」被算成早于起始日、静默不对齐\n\n'

    'v0.9.14\n'
    '· 「排班时段」不再设在排班编辑器里了：现在在「排班管理」页顶部，一条时间线由上到下 —— 头一行是「其余时间」（没被时段覆盖的日子归它管），下面是你排的每一段，点任意一行就能改\n'
    '· 两段时间不许重叠：一天只能有一套排班。撞上了会告诉你跟哪一段撞的、撞的是哪几天。（从前允许重叠，结果设了两套都占 9 月、出来的是其中一套，说不清为什么）\n'
    '· 「其余时间」可以设成「无」：两个班表之间领导真给休息几天时，直接留空就行，不必再专门建一套「休息」的班表。那些天在日历上会写一句「这段时间没有排班」，告诉你去哪加一段\n'
    '· 日历顶栏那个「切换排班」按钮改成了「排班时段」：点开是一张只读的时间线，能看到这段时间在用哪套、今天落在哪一段，要改就点底下的「管理排班时段」。原来那个按钮在时段盖满日子之后就什么也改不动，看着像坏了\n'
    '· 一套班表现在可以出现在多段上（9 月临时换成别的班表、10 月再换回来），从前那种「一套只占一段」的写法表达不了\n\n'
;

const String _changelogEn = 'v0.10.3\n'
    '· The tab pill has been rebuilt: hold it and it sticks to your finger, swelling into a real droplet of glass that stretches the faster you drag and springs back into place when you let go\n'
    '· Its rim now carries a prismatic edge that follows your accent colour, and the bar edge bends through it while lifted\n'
    '· A tap still just slides the pill across and switches pages; lifting belongs to holding\n'
    '· With liquid glass off, the frosted look is pixel-identical to the previous version\n\n'

    'v0.10.2\n'
    '· The tab bar\'s selection slider is no longer larger than the bar at rest — it bulges out into a lens only while you hold it\n'
    '· The slider snaps smoothly again (it used to jump); the switch can now be dragged; the segmented pickers (theme, accent colour) got the same treatment\n'
    '· Fixed several places where the rim landed on rows that are not glass at all (the todo and alarm lists were outlined row by row)\n'
    '· The help dialog no longer leaves a gap below its text — the button now really floats over it\n'
    '· White text on the selected tab meets contrast requirements again in dark mode\n\n'
    'v0.10.1\n'
    '· "Advanced material" in Me → Appearance is now "Liquid glass", off by default. Turn it on and the glass gains a lit rim; the tab bar\'s selection slider and the switch swell into a lens while you press them — they bulge out of the container, which is where the light finally has an edge to catch\n'
    '· Off is exactly what you see today (frosted glass); only the name and the wording changed\n'
    '· Devices with under 4GB of RAM always keep it off\n\n'
    'v0.10.0\n'
    '· All three home-screen cards are in: the week strip, the today card and the month view. The month card draws the neighbouring months as well, its title arrows step three months either way, and any schedule change in the app shows up on the cards\n'
    '· A shift can now carry up to 6 alarms, each with a name — "Wake up" and "Nap" ring separately\n'
    '· Schedule periods rebuilt: arrange which schedule covers which dates on a single timeline on the Schedules page. Periods may not overlap, "Other dates" can be set to none (for the days your manager really does give you off, without building a rest schedule), and one schedule can appear in several periods — swap away for September and swap back in October\n'
    '· Schedules chain by date: the calendar, the alarms and the home-screen cards all work out day by day which schedule a date belongs to, so history shows the schedule that was in force back then\n'
    '· Repeating todos: a Wednesday meeting shows up on its own, ticking it keeps it as history, and the system re-arms the reminder, so it still rings after the app has been closed for a long while\n'
    '· A "legal-holiday schedule" (follow the public holidays) is just a calendar now: dates and lunar lines, no invented "Workday / Rest"\n'
    '· Change a few days on their own (a day off, or swapping with a colleague): tap the shift row on the info card, or long-press a cell and drag. An adjusted day is marked and one tap restores the rotation\n'
    '· "My templates": save a schedule you like and pick it first next time you create one\n'
    '· A "Vibrate only" ringtone, and you can pick your own audio file\n'
    '· Fixed a batch of issues from testing: overlapping text in the widget, calendar text cut off with a large system font, the last row of the todo and alarm lists sitting under the floating button, dialog buttons jumping to the left, dialog text sliced off by the button row, and a midnight shift\'s alarm landing on the shift day instead of the evening before\n'
    '· The Me page descriptions were rewritten, with a new "Home-screen widgets" entry (how to add the cards, and why an update needs one app launch)\n'
    '· Clear & reset really does return the app to a fresh install: schedules, events, alarms, templates, the ringtone you saved and the appearance settings all go\n'
    '\n'

    'v0.9.19\n'
    '· Fixed dialog buttons moving to the left: the last version changed the shared button row so that dialogs with several buttons (Delete / Cancel / Save) would not overflow in a small window (200×400) — which pushed the actions of every dialog in the app (update notes, delete confirmations, schedule periods…) to the left. They are right-aligned again, and still wrap on narrow windows\n'
    '· The "Save & reschedule alarms" button at the bottom of the schedule editor no longer sits on a plate: it floats over the page, so content scrolls underneath it (until now the list was cut off at the top edge of that bar with a flat band below it). Scrolling to the end now lifts the last card clear of the button\n'
    '\n'

    'v0.9.18\n'
    '· The month widget now steps three months back or forward instead of one: tap the arrows either side of its title. As a bonus, the card keeps working for longer while the app stays closed\n'
    '· Open the app once after an update: the shifts on the card are worked out the last time the app ran, so until you do, the card still shows the old picture. (Restarting the launcher redraws it too, but that is not needed.) That note now lives in the update notes, so an update never looks like it broke your home screen\n'
    '· Fixed the end of the todo and alarm lists: once there are enough entries, the last row sat under the floating button (or the button bar on the alarm page) and its delete button could not be tapped. Scrolling to the end now lifts it clear\n'
    '· The "Add a period" dialog now matches the row that opens it: its three labels were a size and a weight lighter (13/w400) and are now 14/w500, like the rest of the page\n'
    '· Also fixed two layout faults in that dialog in a small window (200×400): its buttons overflowed sideways, and the date rows could not fit their value\n'
    '\n'

    'v0.9.17\n'
    '· The month widget (the largest one) now draws the previous and next month as well: the empty slots at the start and end of the month are gone, the neighbouring days show a lighter date and their shifts as usual, and the whole card reads as one continuous run of days\n'
    '· Its title row now has a left and a right arrow: tap to step a month back or forward, and the side with no data left greys out; tap the month name in the middle to jump back to today\n'
    '· Once you have stepped away, a new day or a new month will not drag you back — you stay on the month you picked until you tap back to today\n'
    '\n'

    'v0.9.16\n'
    '· A "legal-holiday schedule" (follow the public holidays) no longer writes "Workday / Rest": on the calendar grid, on the info card in a small window and on the home-screen widget it now draws only the date and the lunar line — public holidays are still marked red and makeup workdays still tagged. It really is just a calendar, and labelling those days "Workday" was overreach on my part\n'
    '· As a result the info card no longer reserves a line for it: the card is about 16dp shorter and the grid above it gains that height\n'
    '· The half of that change that was right stays: "No schedule for these dates" appears only when no schedule covers those days at all — the test for it is now "is a schedule in force on this day", separate from "does this day draw anything"\n'
    '\n'

    'v0.9.15\n'
    '· A "legal-holiday schedule" (follow the public holidays) is no longer treated as "no schedule": every day of one now draws something — "Rest" on a public holiday, "Workday" otherwise, the same on the calendar grid, the info card in a small window, and the home-screen widget. Until now, with only one such schedule, the whole calendar was covered by "No schedule for these dates" while you were in fact working to the public-holiday calendar\n'
    '· The Schedules page is split into two sections: "Schedule timeline" on top, "Schedules" below, each with its own heading instead of running together\n'
    '· With no periods at all, that line now reads "All dates" instead of "Other dates" — "other" needs a period to be other than, and on its own the line read like "so is this the default, always?"\n'
    '· Fixed the Cancel button in the period dialog, which did nothing at all, and put a gap between the Delete / Cancel / Save buttons, which were touching\n'
    '· The "Repeating" entry on the todo screen moved to the top right corner (it used to sit right after the title, looking like part of it)\n'
    '· Fixed markdown markers leaking into the update notes: bold text showed up with its two asterisks. The in-app changelog is plain text and never parses markup; a test now fails if any gets in again\n'
    '· Fixed "change a weekly Wednesday todo to Friday" doing nothing on Wednesdays and Thursdays: editing a repeating todo rewrote the series start date to the current occurrence, so the most recent Friday came out before the start and the alignment was silently skipped\n\n'

    'v0.9.14\n'
    '· The schedule timeline no longer lives in the schedule editor: it is now the top section of the Schedules page, one line per period from top to bottom — the first line is "Other dates" (which covers whatever no period covers), then each period you placed. Tap any line to edit it\n'
    '· Periods may not overlap: a day can only belong to one schedule. If they clash, the app names the period you clashed with and the dates involved. (Overlaps used to be allowed, and two schedules both covering September silently resolved to one of them)\n'
    '· "Other dates" can be set to none: when your manager really does give you a few days off between two schedules, just leave it blank instead of building a "rest" schedule for it. Those days say "No schedule for these dates" on the calendar, pointing at where to add a period\n'
    '· The calendar\'s "Switch schedule" button is now "Schedule timeline": a read-only overview showing which schedule is in force, which period contains today, and a "Manage the timeline" entry. The old button could not change anything once periods covered the dates, so it looked broken\n'
    '· A schedule can now appear in several periods (switch away for September, switch back in October) — the old one-period-per-schedule shape could not express that\n\n'
;
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
  showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
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
