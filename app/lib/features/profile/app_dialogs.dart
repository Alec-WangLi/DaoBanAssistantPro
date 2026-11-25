import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/design_tokens.dart';
import '../../core/haptics.dart';
import '../../core/l10n.dart';
import '../../core/update_checker.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_loading.dart';
import '../../core/widgets/glass_pill.dart';
import '../alarm/alarm_service.dart';
import 'help_entry.dart';

/// 统一风格的应用弹窗（版本更新），配色跟随主题主色。
void showAppInfoDialog(
  BuildContext context, {
  required String title,
  String? content,
  Widget? body,
}) {
  assert(content != null || body != null, '正文总得给一份');
  showGlassDialog<void>(
    context: context,
    builder: (dialogContext) => GlassDialog(
      title: title,
      showClose: true,
      // **不要再套一层 `ConstrainedBox(420) + SingleChildScrollView`**：那会造出
      // 第二个、更小的视口，正文仍然在它自己的底边被切断（而且切在按钮上方一点点，
      // 看着还是像有块板子）。`GlassDialog` 现在自己就是「整块面板高的滚动区 +
      // 浮在上面的动作行」，交给它就行。
      //
      // `body` 给需要自己管状态/排版的正文（更新日志的「展开更早的」）；
      // 其余调用点还是传字符串，样式在这里统一。
      content: body ??
          Text(
            content!,
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
'v0.14.0\n'
    '· 统计页（新）：月 / 年两种视图，实际在岗、正常工时、上班 / 休息天数、请假、加班、夜班、最长连班 / 连休都算好了；环形图、出勤构成条、月度工时柱；点年月标题直接跳\n'
    '· 请假与加班：日历上任意一天记时长、类型（也能自己起名）和备注；整天请假会自动压掉那天的班次闹钟。出勤表可以导出 CSV，拿去算工资或交班\n'
    '· 数据备份：「我的 → 数据备份」导出 .dshbackup（排班 + 待办 + 模板 + 闹钟 + 设置 + 自己的铃声），换机或重装后导入即恢复\n'
    '· 闹钟这一轮的重点是「不丢」：重排改成先排后清，不再有几秒钟一条闹钟都没有；每 6 小时巡检一次，被系统清掉的自动补回；闹钟页顶部多一行「下一次响铃」\n'
    '· 「查看日志」从弹窗改成整页：按天翻（保留 7 天）、能搜索、能一键导出诊断包\n'
    '· 权限页按品牌给入口：三星「休眠应用」、一加 / OPPO「自启动」，直接跳到系统的设置页\n'
    '· 顺带的一批：法定节假日自动更新（「关于」页也能手动刷一次）；「调整班次」能写备注；触觉走设备自己的预定义效果；选择器顶上都补了下拉短横，日期弹层点年月标题直接跳月，深色下箭头看得见了；深色下不再有黑压压的图标；底栏滑块跟手；「版本更新」先给最近三版\n'
    '· 「我的」新增「关于」整页（版本 / 开源地址 / 隐私说明）与打赏入口，打赏后可解锁「支持者专属」里的一封信\n'
    '· 修：HarmonyOS 3.0（荣耀 10、畅享 20 Pro 一类）一开就闪退；用系统文件管理器选铃声返回后没反应；重复待办改「从这天起」不生效；导入备份后点重启拉不起来\n'
    '\n'
'v0.13.27\n'
    '· 「版本更新」这个弹窗现在先给最近三版，更早的点下面的「展开更早的」再看 —— 十条长文一次画出来，对老机型是实打实的压力：有用户反复开关三四次之后，弹窗里的字碎成一片、接着整页上下翻转（重启就恢复）。收起来之后，这一屏也读得清爽些\n'
    '\n'
'v0.13.26\n'
    '· 修：快速滑动底栏滑块时，它总落后手指一截、跟不上 —— 现在透镜与手指的位置 1:1（分段器、开关同样受益）\n'
    '· 恢复上一版误改的「滑动时不提起」：滑动时仍会像以前一样鼓起来（上一版判断错了，问题在跟手，不在鼓起）\n'
    '\n'
'v0.13.25\n'
    '· 修：底栏滑块（分段器、开关也一样）一滑就鼓成一枚球、顶出胶囊 —— 现在只有「按住」才鼓起来，普通滑动只在轨道里跟着走\n'
    '\n'
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
    ;
const String _changelogEn =
'v0.14.0\n'
    '· Statistics (new): monthly and yearly views for hours on duty, normal hours, work / rest days, leave, overtime, night shifts and the longest work / rest streak, with a donut, an attendance bar and monthly hour columns; tap the year-month title to jump\n'
    '· Leave and overtime: record hours, a type (you can name your own) and a note on any calendar day; a full-day leave also cancels that day shift alarm. The attendance table exports to CSV for payroll or handover\n'
    '· Backup: My > Backup exports a .dshbackup file (schedules + todos + templates + alarms + settings + your own ringtones); import it after a reinstall or on a new phone and everything is back\n'
    '· Alarms this round are about not losing one: re-planning schedules the new batch before cancelling the old, a check-up every 6 hours restores whatever the system dropped, and the alarm page gains a next-alarm line\n'
    '· View log is now a full page: per-day logs (7 days kept), search, and a one-tap diagnostics bundle\n'
    '· Permissions gains brand entries: Samsung Sleeping apps, OnePlus / OPPO Auto-launch, each opening the right system screen\n'
    '· Along the way: public holidays update themselves (About can refresh them by hand too); Adjust shift takes a note; haptics use the built-in predefined effects; every sheet has the drag handle, date sheets jump to a month from their title and their arrows are visible in dark mode; no more black icons in dark mode; the sliders track your finger; the update log opens with the latest three versions\n'
    '· My gains a full About page (version / source / privacy) and a tip entry; tipping unlocks a letter under Supporter\n'
    '· Fix: instant crash on HarmonyOS 3.0 (Honor 10, Enjoy 20 Pro and the like); picking a ringtone with the system file manager did nothing on return; changing a recurring to-do starting day had no effect; tapping restart after a backup import brought nothing back\n'
    '\n'
'v0.13.27\n'
    '· The update log now opens with the latest three versions; tap "Show earlier versions" underneath for the rest. Drawing ten long entries at once is real pressure on older phones - one user saw the text break into fragments and then the whole page flip, three or four opens in a row (a restart clears it). It also reads more clearly this way\n'
    '\n'
'v0.13.26\n'
    '· Fix: when swiping the bottom slider quickly it lagged behind your finger - the lens now sits 1:1 under your finger (same for the segmented control and switches)\n'
    '· Restored the previous build\'s accidental change: the lens lifts while sliding again, as it always did (that diagnosis was wrong - the problem was tracking, not the lift)\n'
    '\n'
'v0.13.25\n'
    '· Fix: the bottom slider (and the segmented control / switches) ballooned out of its track as soon as you swiped - now it only lifts while you press and hold, and a normal slide just travels inside the track\n'
    '\n'
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
    ;
String get appChangelog => L10n.isEn ? _changelogEn : _changelogZh;

/// 折叠态下先画几版，剩下的点「展开更早的」再看。
///
/// **为什么不把十条一次全画**：这个弹窗是全 app 中文最密的一面（十条、每条一两行
/// 长句，一次要光栅化上千个不同字形）。2026-11-25 一位用户反馈「反复点开、关掉
/// 这个弹窗三四次之后，弹窗里的字变成错位的碎片，接着整页上下翻转」—— 查下来是
/// 字形图集被压满后采样错位（Impeller 在老机型驱动上的老问题，Flutter 上游
/// #195594 / #190519 同款），不是我们的逻辑。首屏压到三版，把这一次的字形量砍掉
/// 七成；顺带这个面板也更好读了。数据仍是十条，只是分批呈现。
const int kChangelogPreviewCount = 3;

/// 把更新日志切成一条条，每条从 `vX.Y.Z` 那一行开始。
///
/// 条目之间靠空行分隔，末尾的空行归到上一条里一并 trim 掉。
/// `app/test/changelog_window_test.dart` 也用它数条数。
List<String> splitChangelogVersions(String text) {
  final out = <String>[];
  final buf = StringBuffer();
  final head = RegExp(r'^v\d+\.\d+\.\d+$');
  for (final line in text.split('\n')) {
    if (head.hasMatch(line.trim()) && buf.length > 0) {
      out.add(buf.toString().trimRight());
      buf.clear();
    }
    buf.writeln(line);
  }
  final tail = buf.toString().trimRight();
  if (tail.isNotEmpty) out.add(tail);
  return out;
}

void showChangelogDialog(BuildContext context) {
  showAppInfoDialog(context, title: L10n.changelog, body: const _ChangelogBody());
}

/// 更新日志正文：先给最近 [kChangelogPreviewCount] 版，其余的收在一颗胶囊后面。
class _ChangelogBody extends StatefulWidget {
  const _ChangelogBody();

  @override
  State<_ChangelogBody> createState() => _ChangelogBodyState();
}

class _ChangelogBodyState extends State<_ChangelogBody> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final versions = splitChangelogVersions(appChangelog);
    final shown =
        _expanded ? versions : versions.take(kChangelogPreviewCount).toList();
    final hidden = versions.length - shown.length;
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          shown.join('\n\n'),
          style: AppTokens.rowSecondary.copyWith(height: 1.55),
        ),
        if (hidden > 0 || _expanded) ...[
          const SizedBox(height: AppTokens.spaceMd),
          // 三层，缺一层就出毛病（都真踩过）：
          //   · `GlassPill` 的 `Container` 带 `alignment`，等于里面垫了一层
          //     `Align` —— 它会吃满可用宽度，胶囊就**铺成整行**（真机截图确认）；
          //     所以必须在外层套 `IntrinsicWidth`，把宽度收到「文字 + 图标」的
          //     内在宽（挤不下时收到可用宽）。
          //   · `Align` 那层给的是松约束，右/中轴对齐才有意义。
          //   · 里面的 `Flexible` 不能删：Row 给非 flex 孩子的是**无界主轴约束**，
          //     文字按整行内在宽铺开，200dp 小窗 + 标准字号下横向溢出 29px
          //     （`text_fit_guard_test` 报的就是它）。
          // 合起来的效果：常态下胶囊缩到文字，挤不下时先截文字、图标留在原位。
          Align(
            alignment: Alignment.centerLeft,
            child: IntrinsicWidth(
              child: GlassPill(
                onTap: () {
                  Haptics.select();
                  setState(() => _expanded = !_expanded);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _expanded
                            ? L10n.t('收起', 'Collapse')
                            : L10n.t('展开更早的 $hidden 版',
                                'Show $hidden earlier versions'),
                        style: AppTokens.labelStrong.copyWith(color: primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppTokens.spaceXs),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: AppTokens.iconSm,
                      color: primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
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
