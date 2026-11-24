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
'v0.13.14\n'
    '· 新增「统计」页：日历右上角那颗按钮点开就是它，可以按月 / 按年看实际上班工时、正常工时、平均每班、上班与休息天数\n'
    '· 统计里还有请假、加班、法定节假日上班、夜班天数、最长连班 / 最长连休；年视图列出 12 个月，点一行就跳到那个月\n'
    '· 「调整班次」弹层新增「请假」「加班」：时长可以选整天 / 半天或按小时记；整天请假会自动取消那天的班次闹钟，日历格子和信息卡上会标「假 / 加」\n'
    '· 班次编辑里新增「夜班」开关，统计的夜班天数只认这个标记；内置模板的夜班已自动标好\n'
    '\n'
'v0.13.13\n'
    '· 修：在「系统铃声」里选中自己加过的铃声（比如把某首歌设成了系统铃声）之后，闹钟响的还是内置那一声 —— 现在选中就把它复制进应用内部，不再依赖系统的媒体权限\n'
    '· 之前存过的旧设置会在启动时自动修一次：能读的复制进来，读不到的退回内置铃声（日志里写明原因）\n'
    '· 铃声选择和响铃失败的原因现在都会写进「我的 → 查看日志」，报障时能直接看到是哪一步出了问题\n'
    '\n'
'v0.13.12\n'
    '· 法定节假日数据会自己更新了：每次冷启动在后台拉一次（一天最多一次），国务院发布新一年的放假安排后不用等发版；离线或被墙时照旧用 App 内置的那份\n'
    '· 「我的 → 关于」多了一行「更新法定节假日数据」，副标题写着已覆盖到哪一年，点一下立刻重拉\n'
    '· 自定义闹钟那一行的编辑笔去掉了：整行点开就是编辑，与待办一致\n'
    '· 修：用某些文件管理器（比如安卓原生那个）选铃声时，选完返回什么都没有；现在几种回传方式都认，真失败也会说清原因\n'
    '\n'
'v0.13.11\n'
    '· 修：Android 8~10 的手机（荣耀 10、畅享 20 Pro 这类 HarmonyOS 3 机型）装上上一版后一开就闪退；振动能力自查收紧了系统版本判断，老系统上不再调用它没有的接口\n'
    '· 顺带：Android 8 / 9 上点按的触觉改用 20ms 单次波形，不再落到最弱的兜底档\n'
    '\n'
    ;
const String _changelogEn =
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
'v0.13.14\n'
    '· New Statistics page: the calendar top-right button opens it, with month / year views of actual hours worked, regular hours, average per shift, and work / rest days\n'
    '· It also covers leave, overtime, holiday work, night shifts and the longest work / rest streaks; the year view lists all 12 months and a tap jumps to that month\n'
    '· The Adjust shift sheet gains Leave and Overtime: record a full day, half day or any number of hours; a full-day leave also cancels that day\'s shift alarm, and the calendar cell and info card show a leave / overtime mark\n'
    '· The shift editor gains a Night shift switch — the night-shift count uses only this marker; built-in templates already set it\n'
    '\n'
'v0.13.13\n'
    '· Fix: after choosing one of your own ringtones from the system ringtone list (a song you had set as a system ringtone, say), the alarm still played the built-in sound — the pick is now copied into the app instead of relying on system media permissions\n'
    '· Settings saved by older versions repair themselves once at launch: readable ones get copied in, unreadable ones fall back to the built-in ringtone (with the reason in the log)\n'
    '· Ringtone pick and playback failures now land in My > View log, so a report shows exactly which step failed\n'
    '\n'
'v0.13.12\n'
    '· Public holiday data now updates itself: a background fetch on each cold start (at most once a day), so a new year\'s arrangement no longer waits for an app release; offline or blocked networks keep using the built-in table\n'
    '· About gains an "Update public holiday data" row whose subtitle says which year the data covers; tap it to fetch immediately\n'
    '· The pencil on custom alarm rows is gone: tapping the row opens the editor, same as todos\n'
    '· Fix: picking a ringtone through some file managers (the stock Android one, for instance) returned to the app with nothing happening; all common result shapes are handled now, and a real failure says why\n'
    '\n'
'v0.13.11\n'
    '· Fix: phones on Android 8-10 (Honor 10, Changxiang 20 Pro and other HarmonyOS 3 devices) crashed on launch with the previous build; the vibration capability check now respects the system version and no longer calls APIs those systems lack\n'
    '· Android 8 / 9 now use a 20 ms one-shot for taps instead of the weakest fallback\n'
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
