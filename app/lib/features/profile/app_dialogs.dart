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

const String _changelogZh = 'v0.9.16\n'
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

    'v0.9.13\n'
    '· 待办页右上角那个「重复待办」入口重新做了：原来是几个小字，现在是实心主色胶囊（与日历右上角那颗「今天」同一个形态），一眼看得出是个按钮。窄屏上仍只留图标，位置不变\n\n'

    'v0.9.12\n'
    '· 排班表可以「衔接」了：每套方案能设一个生效时段（从几号到几号，两端都可以留空 —— 留空就是「不限起点」或「一直持续」）。日历、闹钟、桌面小组件从此都按天取「那天归哪一套」，翻回历史看到的也是当时的班\n'
    '· 设在排班编辑器里新的一节「生效时段」（在「班组设置」下面）。没设过时段的方案不参与衔接，一切照旧 —— 升级后什么都不用做\n'
    '· 顶栏「切换排班」现在写明每套方案管哪些日子：设了时段的写时段；没设时段又正在用的那套标「其余日子」（没被时段覆盖的日子就归它管）\n'
    '· 日历上长按选一段日子改班时，如果这段跨了两套排班，会提示你分开调整 —— 从前那样只会改到一半，另一半悄没声地不动\n\n'

    'v0.9.11\n'
    '· 待办能重复了：新建待办时选「每天 / 每周几 / 每月某日」，它就会按时自己出现 —— 不用每周手动建一次。勾掉之后留成历史（带删除线），下一次到点自动来一条新的\n'
    '· 一个重复待办同时只占一行：永远是「当前这一次」。过期没勾的，下一次到点时就地顺延，不会堆出一串「上周三的会」\n'
    '· 删一条重复待办时会问一句：是「只这一次不要了」，还是「删除整个重复」—— 前者只是跳过这一次（下次照常出现），后者连它已完成的历史一起删掉\n'
    '· 待办页右上角多了「重复待办」入口（小窗里只剩图标）：能看到有哪些重复项、各自的下一次是什么时候，能改周期、能停用、能删。停用之后当前那条会留着 —— 那是你还没做的一件事，不替你收走\n'
    '· 重复待办的提醒由系统自己接着排，App 长期不开也照常响，不是「等你下次打开才补上」\n\n'

    'v0.9.10\n'
    '· 桌面小组件（4×5 整月那张）里超过三个字的农历节日名，现在与 App 里的日历显示一致：前三个字加省略号。上一版只改了 App 里的日历，桌面那张卡漏掉了 —— 同一天两个界面显示得不一样\n'
    '· 顺带补了几条自查用例：桌面小组件「先清空再填」的顺序、以及更新日志固定 10 条这两件长期规则，此前只靠人记，现在漏了会直接测试失败\n\n'

    'v0.9.9\n'
    '· 修好桌面小组件的字重影：把某天的班按天改成休班之后，有的手机上小组件的旧内容会压在新内容上（日期、班次、周几叠成一团）。成因是小组件每次刷新都往同一个格子里再叠一份、从来不先清空 —— 多数手机上系统会替你清掉，所以一直没露出来，只在 OPPO / vivo 这类机型上现形\n'
    '· 闹钟铃声多了一档「仅震动」：不想被响醒的时候选它，到点只震动、一点声音都没有。在「我的 → 闹钟铃声」里，与内置铃声并排；那一行现在也会显示当前选的是哪一档（从前永远是一句固定提示），因为这一档设没设成功光靠听是确认不了的\n'
    '· 修好系统字号调大之后日历显示不全：农历那一行会被截成「财…」「地…」（节日名比「初一」长），周标题那一行还会挤进下面的格子。现在格子里的字一律缩到放得下、不再截断；超过三个字的节日名在格子里显示前三个字加省略号，信息卡里仍写完整的\n'
    '· 顺带给视觉工装加了一档「大字号」的屏 —— 此前每一屏都只在默认字号下出图，「系统字号放大之后文字被截」这类问题在图上根本看不见（这一轮的日历截断就是这么漏掉的）\n\n'

    'v0.9.8\n'
    '· 日历页的背景不再是死板的纯色：加了一层极慢的流光（26 秒才挪一小段）。压在上面的磨砂卡片这下「有东西可磨」了 —— 在这之前整页只有响铃界面有那层光，日历是一块平色，玻璃只看得见高光与白描边。浅色主题下它很轻（格子几乎是实心白，光主要从格子缝里和信息卡的磨砂上透出来），深色主题下更明显\n'
    '· 这层光是按最慢的节奏推进的，不是每帧重画：它 26 秒才漂 46dp，逐帧画每帧只动 0.03dp、没人看得出来，却会让整页永远不空闲、把压在背景上的每一层模糊拖着每帧重算\n'
    '· 「我的 → 外观 → 高级材质」关掉时，这层光会停下 —— 那个开关的意思就是「这台机器不做贵的合成」，不该一边关模糊一边还在推背景\n\n'

    'v0.9.7\n'
    '· 信息卡底下那截空白用起来了：卡片是按「本月最满的一天」定高的 —— 这样点日期时上面的日历格子不会跟着伸缩 —— 于是普通日子底下会空出三四十 dp。现在那里写一行本月统计，比如「本月 早12 · 午8 · 夜8 · 休6」，一眼看出这个月上了几个什么班。装得下才画：节假日那种最满的日子它自动不出现，卡片高度一个像素都没动\n'
    '· 换月加了一点方向感：往前翻往左滑、往后翻往右滑，顶栏的「年月」跟着一起动；以前是硬切\n\n'

;

const String _changelogEn = 'v0.9.16\n'
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

    'v0.9.13\n'
    '· The "Repeating" entry at the top of the todo screen has been redone: it was a few small characters, and is now a solid accent pill (the same shape as the "Today" button on the calendar), so it reads as a button at a glance. In a narrow window it still shows just the icon, in the same place\n\n'

    'v0.9.12\n'
    '· Schedules can now be chained: each one can carry an active period (from a date to a date, either end may be left empty — empty means "any time" or "ongoing"). The calendar, the alarms and the home-screen widget now resolve day by day which schedule a date belongs to, and history shows the schedule that was in force back then\n'
    '· Where to set it: the new "Active period" section in the schedule editor (under "Crews"). Schedules without a period take no part in chaining, so nothing changes until you set one\n'
    '· The "Switch schedule" sheet now spells out which days each schedule covers: the ones with a period show it, and the one currently in use without a period is marked "Other days" — those are the days it covers\n'
    '· Adjusting a dragged range of days on the calendar now tells you to adjust separately when the range crosses two schedules, instead of quietly changing only half of it\n\n'

    'v0.9.11\n'
    '· Todos can repeat now: pick "every day / weekly (choose the days) / monthly (pick a day)" when adding one and it shows up on its own — no more creating it by hand every week. Ticking it keeps it as history (struck through), and the next occurrence arrives on time\n'
    '· A repeating todo only ever takes one line: the current occurrence. Miss one and it rolls forward in place at the next occurrence, instead of piling up a stack of "last Wednesday\'s meeting"\n'
    '· Deleting a repeating todo asks which you mean: "skip this one" (the next occurrence still comes) or "delete the whole repeat" (its completed history goes too)\n'
    '· The todo screen now has a "Repeating" entry (an icon in a small window): see your repeating todos and when each next occurs, and edit / pause / delete them. Pausing keeps the current entry — that is something you have not done yet, and the app will not take it away for you\n'
    '· Their reminders are re-armed by the system itself, so they still ring after the app has been closed for a long time — not "fixed up the next time you open it"\n\n'

    'v0.9.10\n'
    '· Lunar festival names longer than three characters now read the same on the 4×5 month widget as they do in the app\'s calendar (first three characters plus an ellipsis). The last version only fixed the in-app calendar and missed that card, so the same day looked different in the two places\n'
    '· A couple of long-standing rules now have failing tests behind them instead of living in someone\'s memory: the widget clearing each slot before filling it, and the changelog keeping exactly 10 entries\n\n'

    'v0.9.9\n'
    '· Fixed overlapping text in the home-screen widget: after changing a day\'s shift to a rest day, on some phones the old content was drawn on top of the new one (dates, shifts and weekdays piling up). The widget added a fresh copy into the same slot on every refresh without clearing it first — most launchers clear it for us, which is why it only showed up on OPPO / vivo devices\n'
    '· Added a "Vibrate only" ringtone: the alarm vibrates without making a sound. Pick it in Me → Alarm ringtone, next to the built-in one. That row now also shows which option is active (it used to show a fixed hint) — with this option you cannot confirm it by ear until the next alarm rings\n'
    '· Fixed the calendar being cut off with a large system font: the lunar line was truncated to "财…" / "地…" (festival names are longer than "初一"), and the weekday row bled into the grid below. Text in the cells now shrinks to fit instead of being cut off; festival names longer than three characters show their first three plus an ellipsis in the grid, and stay complete in the info card\n'
    '· The visual harness now renders a large-font screen too. Every screen used to be captured at the default font size only, so "text cut off when the system font is enlarged" was structurally invisible in the images — which is how this round\'s calendar truncation slipped through\n\n'

    'v0.9.8\n'
    '· The calendar no longer sits on a flat colour: a very slow drift of light moves behind it (a full lap takes 26 seconds). The frosted cards now have something to frost — until now the only place with that drifting light was the ringing screen, so on the calendar the glass showed nothing but its highlight and hairline border. It is subtle in the light theme (the cells are almost solid white, so the light mostly shows between them and through the info card) and clearly visible in the dark one\n'
    '· That layer advances at the slowest pace rather than being redrawn every frame: it travels 46dp in 26 seconds, so per-frame it would move 0.03dp — invisible, while keeping the whole page permanently busy and forcing every blur above it to recompute each frame\n'
    '· With "Advanced materials" switched off under Me → Appearance, the light stops — that switch means "this device does not do expensive compositing", so it should not keep pushing a background while the blur is off\n\n'

    'v0.9.7\n'
    '· The empty space under the info card now says something: the card is sized to the fullest day of the month — that way tapping a day never makes the calendar grid above it resize — which leaves roughly 30-50dp empty on ordinary days. That line now carries a tally of the month, such as "This month  M12 · A8 · N8 · O6", so you can see at a glance how many of each shift you have. It only shows when there is room: on the fullest days (public holidays) it stays out, and the card never grows a pixel for it\n'
    '· Changing months now has a sense of direction: going back slides left, going forward slides right, with the month label travelling along. It used to be an instant swap\n\n'

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
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: SingleChildScrollView(child: content),
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
  final String title;
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
              Text(title, style: AppTokens.labelStrong),
              const SizedBox(height: AppTokens.padChipV),
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
