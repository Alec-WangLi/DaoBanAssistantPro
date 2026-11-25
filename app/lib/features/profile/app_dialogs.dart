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
'v0.13.24\n'
    '· 每个从下面滑上来的弹层，顶上都有那只「往下拖」的小短横了 —— 时间 / 日期 / 月份 / 年份选择器以前漏了它，和别的弹层对不上\n'
    '· 修：深色模式下还有些图标是黑的 —— 根因是主题没给图标兜底色，没单独取色的图标一律被画成纯黑；现在跟随正文（深色下近白），「关于」页、我的页那些列表图标都恢复可见\n'
    '· 修：时间 / 年份选择器在小窗里会差几个像素溢出；滚轮高度改成按剩余空间自适应\n'
    '\n'
'v0.13.23\n'
    '· 日期选择（统计导出的起止日期、新建闹钟、添加待办、添加时段）翻月快了：点中间的年月标题直接弹出月份选择，不用再一下一下点箭头\n'
    '· 同一处的左右箭头换成了玻璃圆钮，与统计页顶栏一套；深色下不再发黑 —— 原来是黑箭头压在深底上，几乎看不见\n'
    '· 修：这些弹层翻月时高度不再跟着 30 / 31 天跳来跳去，固定按六周排\n'
    '\n'
'v0.13.22\n'
    '· 「某条闹钟没响」现在能一眼看出是谁丢的：每次启动都会在重排之前记下「系统认为下一次闹钟是几点」和「我们清单里最早那条」。两边对不上＝记录被系统删了；对得上（哪怕是已经过期的时间）＝广播被拦了下来，闹钟根本没能进来\n'
    '· 同时记下上一次进程是怎么没的：被强行停止 / 一键清理，还是被系统的冻结器杀掉 —— 这两种在日志里原本一模一样\n'
    '· 修：巡检（给被丢掉的闹钟兜底的那条闹钟）会被每次重排往后推 6 小时，等于一直没按时跑过；现在只往前挪，并且提前到最早那条闹钟前 1 小时\n'
    '· 一加 / OPPO 机型在「我的 → 权限」里多了一行「自启动 / 后台运行」，可以直接跳到系统的自启动管理页\n'
    '· 诊断包里的说明重写了：先看「启动快照」那两行，再看「重排完成 … 撤 N 条」\n'
    '\n'
'v0.13.21\n'
    '· 修：闹钟页「下一次响铃」关掉某一天的闹钟后不跟着跳 —— 它没看「按天开关」。现在关掉哪条就跳到下一条\n'
    '· 修：没有自定义闹钟时，那一块终于真的贴到底部（上一版它和上面的班次列表平分剩余空间，提示停在屏幕中间）\n'
    '· 编辑排班里的「夜班」开关下面加了一行说明：它只算进统计页的「夜班天数」，不影响轮转与闹钟；与「联动闹钟」之间也拉开了\n'
    '\n'
'v0.13.20\n'
    '· 闹钟页顶部多了一行「下一次响铃」：几月几日几点、哪条班次闹钟，还有几小时几分\n'
    '· 没有自定义闹钟时那一块不再占半个屏幕：提示贴到底部，未来 30 天的班次闹钟回到整块空间\n'
    '· 统计页年月份下面那颗小箭头去掉了\n'
    '· 「调整班次」弹层加了备注：换班、调休写一句，日历信息卡里看得见（本次升级会新建一张表）\n'
    '· 「查看日志」从弹窗改成整页：按天翻（日志现在按天归档、保留 7 天）、能搜索、能一键导出诊断包（日志 + 设备权限 + 已排闹钟清单 + 未来 7 天计划）\n'
    '· 报「偶尔没响」时把诊断包发来：里面有 App 认为该响的清单，一眼分得清是没排、还是被系统丢了\n'
    '\n'
'v0.13.19\n'
    '· 统计页年视图：点年份直接弹出年份选择器，跨十年不用再点十下箭头\n'
    '· 翻月 / 翻年 / 「今天」，以及年视图点某个月，都会震一记；已经停在本月 / 今年时不震\n'
    '· 期间条那三颗玻璃钮亮了一档；左右箭头的颜色也修了 —— 深色下它们原本被画成黑色，你看到的「有点暗」就是它\n'
    '· 统计页统一「图标在前」：月 / 年分段、四格指标、每张卡片的分节标题、出勤亮点的四行，都带上了语义色图标\n'
    '· 图表精修：环图加了底轨、圆头分段与真实缝隙（只有一天的小段也不会消失）；出勤构成条分段留缝；月度工时柱改成底轨 + 顶圆角渐变柱 + 均值虚线（只统计有工时的月份）+ 当月高亮，切年时从基线长出来\n'
    '· 请假构成每个类型多了一条占比细条；统计口径补了一条「月度均值线只统计工时 > 0 的月份」\n'
    '\n'
'v0.13.18\n'
    '· 修：个别机型（三星这类）偶尔有某一条班次闹钟不响。根因是重排闹钟时先清空系统里已排的那一批、再一条条排回来，中间有几秒一条闹钟都没有；而每次闹钟响都会拉起 App 重排一轮，这时 App 若被划掉或被系统清理，就停在「撤完了、还没排上」\n'
    '· 现在顺序反过来了：先把新的一批排上、再撤多余的。重排过程中系统里始终有一批闹钟（升级后的首次清扫是唯一的一次例外）\n'
    '· 新增闹钟巡检：每 6 小时照排班把系统里缺的补回来。厂商把 App 的闹钟整条取消时（三星「休眠应用」就是这样），靠它补回，不必等下次打开 App\n'
    '· 日志现在能一眼定位：进程启动只写一次设备与权限，之后每条都短；每条「收到闹钟」后面跟一行「下一跳是几月几日几点、哪个 id」——报障时把日志复制过来，就能分清是系统没递过来、还是 App 根本没排它。铃声那一行也不再打出让人误解的「file://」\n'
    '· 重排本身也快了：一次只走一次原生调用、只落一次盘（原来是每条闹钟各来一次），冷启动不再卡\n'
    '\n'
'v0.13.17\n'
    '· 统计页更好看也更好用了：班次分布换成环形图，新增「出勤构成」分段条与年视图的月度工时柱状图；底部多了一张「统计口径」，点开就能看到每个数字是怎么算的\n'
    '· 统计页去掉了「排班时段」入口；要看时段总览仍可从「我的 → 排班管理」进\n'
    '· 统计入口的图标换成饼图，不再和翻月箭头长得像；顶栏排成两行时，它与「今天」在同一侧\n'
    '· 新增「导出统计数据」：任选起止日期、勾选要的字段（日期 / 班次 / 工时 / 请假类型 / 请假时长 / 加班 / 备注等），生成 CSV，Excel 直接能打开\n'
    '· 请假现在能选类型：年假、事假、病假、调休、其他，也能自己加类型；长按自定义类型可删除，已有记录会保留原来的名字\n'
    '· 请假 / 加班都能写备注，日历信息卡上多一行「请假备注：…」；统计页新增「请假构成」，按类型列出时长\n'
    '\n'
'v0.13.16\n'
    '· 修：重复待办还在起点之前就出现在列表里 —— 上一版把第一条直接建在「新起点之后的第一次」上，于是「每月 17 号、从 11/21 起」在建好的当下就躺进了列表。现在重复待办要到它那一天才出现，上一版留下的那几条会在打开待办页时自动收走\n'
    '· 打赏收款码换成经营码：支付宝与微信两张都换了，支付宝的「打开支付宝」也指向新码\n'
    '\n'
'v0.13.15\n'
    '· 修：编辑重复待办时把「从这天起」改到别的日子，它当天照样提醒 —— 那一行只挪了当前这一条，系列的起点没跟着走（提醒正是按起点算的）\n'
    '· 「我的 → 权限」新增「休眠应用（三星）」：电池 → 后台使用限制里把本 App 从「睡眠应用 / 深度休眠应用」去掉。进了名单的 App，系统会连闹钟一起取消，症状就是几天偶尔漏响一次\n'
    '· 闹钟链路的关键步骤现在都写进「我的 → 查看日志」：收到闹钟、响铃服务起来、声音真的开始放。漏响时看有没有「AlarmReceiver.onReceive」那一行，就能分出是系统没递过来、还是响铃界面被拦、还是音源的问题\n'
    '· 日志瘦身：冷启动不再每次往日志里塞一行振动能力探针（没有振动器这类真问题照旧记）\n'
    '\n'
    ;
const String _changelogEn =
'v0.13.24\n'
    '· Every sheet that slides up from the bottom now has the little drag handle at the top — the time / date / month / year pickers were missing it and looked different from the rest\n'
    '· Fix: some icons were still black in dark mode — the theme never set a fallback icon colour, so every icon without an explicit colour was drawn pure black; icons now follow the body ink (near white in dark), bringing back the row icons on About, My and elsewhere\n'
    '· Fix: the time / year pickers could overflow by a few pixels in small windows; the wheel now takes the remaining space\n'
    '\n'
'v0.13.23\n'
    '· Date picking (export range, new alarm, new todo, new shift span) is faster: tap the year-month title to jump straight to a month instead of stepping with the arrows\n'
    '· The arrows there are now glass step buttons, the same as the Statistics period bar, and no longer turn black in dark mode — they used to be black on a dark sheet, nearly invisible\n'
    '· Fix: those sheets no longer change height as a month goes from 30 to 31 days — the grid is pinned at six weeks\n'
    '\n'
'v0.13.22\n'
    '· "An alarm did not ring" now shows whose fault it was at a glance: on every launch, before any rescheduling, the app records what the system thinks the next alarm is and what its own list says. Mismatch = the system deleted the record; match (even a time already past) = the broadcast was blocked and never reached the app\n'
    '· It also records how the previous process died: force-stopped / cleaned up, or killed by the system freezer - the two used to look identical in the log\n'
    '· Fix: the watchdog (the safety net for dropped alarms) was pushed 6 hours out by every reschedule, so it never actually ran on time; it now only moves earlier, and fires one hour before the next alarm\n'
    '· OnePlus / OPPO phones get an "Auto-launch" row under My > Permissions that opens the system auto-launch page\n'
    '· The diagnostics bundle README is rewritten: read the startup snapshot lines first, then the "withdrew N" counter\n'
    '\n'
'v0.13.21\n'
    '· Fix: "Next alarm" on the alarm page did not move on when you switched a day off - it ignored the per-day switches. It now skips to the next one\n'
    '· Fix: with no custom alarms, that section finally sits at the bottom (the previous build split the leftover space with the shift list, leaving the hint mid-screen)\n'
    '· The "Night shift" switch in the schedule editor now explains itself: it only counts towards night days in Statistics, and no longer crowds the linked-alarm row\n'
    '\n'
'v0.13.20\n'
    '· The alarm page gains a "Next alarm" line: the date and time, which shift alarm it is, and how long to go\n'
    '· With no custom alarms, that section no longer takes half the screen - the hint sits at the bottom and the 30-day shift alarms get the whole area\n'
    '· The little arrow under the year / month title on Statistics is gone\n'
    '· "Adjust shift" now takes a note: a swap or a day off, one line, shown on the calendar info card (this update adds one table)\n'
    '· "View log" is now a full page: per-day logs (rotated daily, 7 days kept), search, and a one-tap diagnostics bundle (logs + device permissions + the scheduled alarm list + the next 7 days of plan)\n'
    '· Reporting "it did not ring": send the bundle - it lists what the app thinks should ring, so it is obvious whether it was never scheduled or dropped by the system\n'
    '\n'
'v0.13.19\n'
    '· Statistics, year view: tap the year to open a year picker - no more ten arrow taps to cross a decade\n'
    '· Month / year switching, Today, and tapping a month in the year view each tick once; tapping Today while already there stays silent\n'
    '· The three glass buttons on the period bar are a notch brighter; the arrow colour is fixed too - in dark mode they were drawn black, which is the "looks dim" you saw\n'
    '· Statistics now leads with icons: the month / year segment, the four metric tiles, every card header and the four highlight rows all carry a semantic-coloured icon\n'
    '· Charts refined: the donut gains a track, round segment caps and real gaps (a one-day segment no longer vanishes); the composition bar has gaps between segments; monthly hours become track + rounded gradient bars + a dashed average line (months with hours only) + current-month highlight, growing from the baseline when the year changes\n'
    '· Leave by type gains a share bar per row; "How it is calculated" explains that the monthly average line only counts months with hours > 0\n'
    '\n'
'v0.13.18\n'
    '· Fix: on some devices (Samsung among them) an occasional shift alarm did not ring. Alarms were re-planned by clearing everything already scheduled and then adding them back one by one, leaving a few seconds with no alarm at all; and every alarm that rings brings the app up for a full re-plan, so if the app is swiped away or cleaned up meanwhile it stays at "cleared, not yet re-added"\n'
    '· The order is reversed: the new batch is scheduled first, then the leftovers are cancelled. A full set of alarms stays scheduled throughout a re-plan (the one-time sweep after upgrading is the only exception)\n'
    '· New alarm check-up every 6 hours re-adds whatever the system dropped. When an OEM cancels an app\'s alarms outright (Samsung\'s sleeping apps do), this brings them back without waiting for the next app launch\n'
    '· The log now pinpoints the problem at a glance: device and permissions are written once per process and later lines are short; every "alarm received" line is followed by "next up: date, time, id" - paste the log and it is clear whether the system never delivered it or the app never scheduled it. The ringtone line no longer prints a misleading "file://"\n'
    '· Re-planning is faster too: one native call and one disk write per batch instead of one per alarm, so cold starts no longer stall\n'
    '\n'
'v0.13.17\n'
    '· The Statistics page looks and reads better: by-shift is now a donut chart, day composition is a segmented bar, and the year view gains monthly hour bars; a new "How it is calculated" card at the bottom spells out every number\n'
    '· The schedule-timeline entry is gone from Statistics; the overview still lives under Me > Schedule management\n'
    '· The Statistics icon is now a pie chart, no longer confusable with the month arrows; in the two-row header it sits next to Today\n'
    '· New "Export statistics": pick any date range and fields (date / shift / hours / leave type / leave hours / overtime / note, ...), create a CSV that opens directly in Excel\n'
    '· Leave now has a type: annual, personal, sick, time off in lieu, other, plus your own custom types; long-press a custom type to delete it, and existing records keep the old name\n'
    '· Leave and overtime both take a note, shown as an extra line on the calendar info card; Statistics gains "Leave by type" with hours per type\n'
    '\n'
'v0.13.16\n'
    '· Fix: a repeating todo showed up before its start date - the previous build created the first row on "the first occurrence after the new start", so a monthly todo starting 11/21 was already in the list. Repeating todos now appear on their own day, and rows left behind by the previous build are removed when the todo page opens\n'
    '· Donation QR codes replaced with the new merchant codes (Alipay and WeChat); the "Open Alipay" action points at the new code too\n'
    '\n'
'v0.13.15\n'
    '· Fix: editing a repeating todo and moving "Starts on" to another day still reminded you on the old day - only the current row moved, the series start (which drives reminders) did not\n'
    '· Me > Permissions gains "Sleeping apps (Samsung)": remove the app from Sleeping / Deep sleeping apps under Battery > Background usage limits. Apps on those lists have their alarms cancelled by the system, which shows up as an alarm missing every few days\n'
    '· The alarm chain now logs each key step to Me > View log: alarm received, ring service started, sound actually playing. When one goes missing, look for the "AlarmReceiver.onReceive" line to tell "the system never delivered it" from "the screen was blocked" and "the sound failed"\n'
    '· Less log noise: the cold-start vibration capability probe no longer writes a line every launch (a real "no vibrator" finding still does)\n'
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

/// 检查更新失败的提示：三条通道（官网清单 / 仓库清单 / GitHub API）都失败才会出现。
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
