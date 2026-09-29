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

const String _changelogZh = 'v0.9.12\n'
    '· 排班表可以「衔接」了：每套方案能设一个生效时段（从几号到几号，两端都可以留空 —— 留空就是「不限起点」或「一直持续」）。日历、闹钟、桌面小组件从此都按天取「那天归哪一套」，翻回历史看到的也是当时的班\n'
    '· 设在排班编辑器里新的一节「生效时段」（在「班组设置」下面）。没设过时段的方案不参与衔接，一切照旧 —— 升级后什么都不用做\n'
    '· 顶栏「切换排班」现在写明每套方案管哪些日子：设了时段的写时段；没设时段又正在用的那套标「其余日子」（没被时段覆盖的日子就归它管）\n'
    '· 日历上长按选一段日子改班时，如果这段跨了两套排班，会提示你分开调整 —— 从前那样只会改到一半，另一半悄没声地不动\n\n'

    'v0.9.11\n'
    '· 待办能重复了：新建待办时选「每天 / 每周几 / 每月某日」，它就会按时自己出现 —— 不用每周手动建一次。勾掉之后留成历史（带删除线），下一次到点自动来一条新的\n'
    '· 一个重复待办同时只占一行：永远是「当前这一次」。过期没勾的，下一次到点时就地顺延，不会堆出一串「上周三的会」\n'
    '· 删一条重复待办时会问一句：是「只这一次不要了」，还是「删除整个重复」—— 前者只是跳过这一次（下次照常出现），后者连它已完成的历史一起删掉\n'
    '· 待办页右上角多了「重复待办」入口（小窗里只剩图标）：能看到有哪些重复项、各自的下一次是什么时候，能改周期、能停用、能删。停用之后当前那条会留着 —— 那是你还没做的一件事，不替你收走\n'
    '· 重复待办的提醒由系统自己接着排，**App 长期不开也照常响**，不是「等你下次打开才补上」\n\n'

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

    'v0.9.6\n'
    '· 新建自定义闹钟的默认重复方式从「每天」改成「一次性」：加一条闹钟十有八九是响这一次，响过之后它自己就消失了，不用你回来删。要天天响的，点一下「每天」\n'
    '· 修好一个会让一次性闹钟「加了就没」的坑：新建时时间和日期默认都是「此刻」「今天」，两个默认叠在一起，那一刻在按下「添加」之前已经过去了 —— 这种闹钟既不会响，还会在下次进闹钟页时被自动清掉。现在日期取的是这个钟点的下一次出现：今天还没到就是今天，已经过了就顺延到明天；日期那一行写的永远是你真正会听到它的那天\n\n'

    'v0.9.5\n'
    '· 新用户第一次打开 App 弹的那个弹窗重做了：从前直接弹整份《使用帮助》（九个条目、上千字），现在只讲三件事 —— 先把班排上、把权限开齐、临时请假或换班怎么操作。完整说明仍在「我的 → 使用帮助」\n'
    '· 《使用帮助》九条全部改写：从一整段长句改成一条条短句，原先夹在括号里的细节拆出来独立成条，能扫着读了\n'
    '· 搜索倒班方式没搜到时，不再只写一句「没找到匹配的倒班方式」就结束 —— 补上了下一步：换个说法再搜，或者从下面挑一个最接近的进去改\n'
    '· 修好一处自相矛盾的文案：「我自己排」的英文标题原标题是 Start from scratch（从零开始），但它其实是给你一套默认的四班两倒起步，中文副标题一直是对的\n\n'

    'v0.9.4\n'
    '· 修好「检查更新」经常失败：更新检查以前先打 GitHub 的接口，那个接口对未登录的请求限制 60 次/小时，很容易被用光——用光之后其实一直在走备用的另一条路。现在改成先读发布清单（静态文件，不限次数），顺带也快了一点\n'
    '· 「检查更新」和「下载」失败时不再只弹一句「网络异常，请稍后再试」（这句只停 2 秒，看完也来不及做什么），改为弹窗说清楚：连不上 GitHub 服务器，国内网络通常需要开启代理或加速器后重试。\n\n'

    'v0.9.3\n'
    '· 修好 0.9.2 里漏掉的一类班次：12 小时制的夜班（20:30 上班那种）配一个落在值班时间之内的闹钟，从前会被排到前一天同一钟点 —— 0.9.2 只修好了「00:00 上班」那种写法，这类没修到。现在两种写法都算班次当天\n'
    '· 修好闹钟页把整行藏早了一点：那天的第一个闹钟响过之后，整行（连同后面还没到的那条）就看不见了，也没法在那行关掉当天剩下的闹钟。现在只要那天还有没响的闹钟，那一行就留着\n'
    '· 闹钟名字最多 12 个字（太长会把闹钟页那一行撑坏）\n\n';

const String _changelogEn = 'v0.9.12\n'
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

    'v0.9.6\n'
    '· New custom alarms now default to "Once" instead of "Daily": an alarm you add is usually a one-off, and once it has rung it clears itself away so you never have to come back and delete it. For one that repeats every day, tap "Daily"\n'
    '· Fixed a hole that made a one-off alarm vanish the moment you added it: a new alarm defaulted to today at the current time, so that moment had already passed by the time you tapped "Add" — such an alarm never rang, and was quietly deleted the next time you opened the alarm page. The date is now the next time that clock time comes around: today if it is still ahead, tomorrow if it has passed. The date row always shows the day you will actually hear it\n\n'

    'v0.9.5\n'
    '· Reworked the dialog shown on first launch: it used to open the entire Usage guide (nine sections, over a thousand characters) — it now covers just three things: setting up your schedule, turning on the permissions, and changing a day or two. The full guide is still under Me → Usage guide\n'
    '· Rewrote all nine Usage guide sections from long single paragraphs into short scannable lines, pulling the details back out of their parentheses\n'
    '· Searching for a shift pattern with no matches no longer dead-ends on "No matching pattern" — it now says what to try next: another name, or start from the closest match below\n'
    '· Fixed a self-contradicting label: the English title for "Build my own" read "Start from scratch", but the route actually starts you off with the default 4-crew rotation — the Chinese subtitle had it right all along\n\n'

    'v0.9.4\n'
    '· Fixed "Check for update" failing so often: it used to call a GitHub API first, and that API allows only 60 unauthenticated requests per hour — easy to exhaust, after which checks were silently running on the fallback route all along. It now reads the release manifest first (a static file with no such limit), which is also a little faster\n'
    '· A failed update check or download no longer shows just "network error, try later" — that line stayed up for 2 seconds, too short to act on. A dialog now says it plainly: GitHub is unreachable, and in mainland China a proxy or accelerator is usually required.\n\n'

    'v0.9.3\n'
    '· Fixed a class of shifts missed in 0.9.2: a 12-hour night shift (the 20:30-start kind) with an alarm set inside the shift was still scheduled on the previous day at the same clock time — 0.9.2 only fixed the "midnight start" shape. Both shapes now ring on the shift\'s own day\n'
    '· Fixed the alarm page hiding a day too early: once that day\'s first alarm had rung, the whole row (including alarms still to come that day) disappeared, and the rest of the day could no longer be muted from it. The row now stays as long as some alarm is still coming\n'
    '· Alarm names are capped at 12 characters (a longer one used to break the alarm page row)\n\n';

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
