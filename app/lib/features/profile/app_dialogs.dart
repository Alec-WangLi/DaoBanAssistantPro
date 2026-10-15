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

const String _changelogZh =         'v0.11.22\n'
    '· 修上一版带出来的一处：浅色模式下，压在实心主色上的字是黑的 —— 底部导航选中的那两个字、「我的」页那几条分段器（主题模式 / 语言 / 字体大小）都读不清，现在一律白字\n'
    '· 压深改成「够用就好」：以前不管原来多浅都再压掉四成，默认那颗蓝明明够亮也被压成近黑；现在只有真不够的（青、橙）才压，而且压到刚读得清就停\n'
    '· 于是胶囊、按钮、导航、开关这几处的颜色都回到了接近「我的 → 外观」里那颗主色 —— 上一版说的「实心面比主色深一档」那个代价，现在只在青和橙上还看得到\n'
    '\n'
'v0.11.21\n'
    '· 实心主色面换成深一档的主色：主按钮、弹窗按钮、导航选中、开关、勾选、待办那颗悬浮按钮、顶栏的实心胶囊 —— 以前白字压在原主色上，teal 只有 2.6:1、orange 2.6:1，等于读不清；现在五种主色都在 5.9:1 以上\n'
    '· 顺带修掉一件更早就有的毛病：那层实心填充原来是半透明的（85% 到 50%），压在白底上连默认蓝的渐变尽头都只有 2.1:1\n'
    '· 代价：实心面比「我的 → 外观」里那颗主色深一档（大致是同一个色更暗一截），字保持白\n'
    '\n'
'v0.11.20\n'
    '· 输入框的名字改成写在框的上方 —— 你截图里那两个字被压成半截，是 Android 上 Material「浮动标签」在系统字体（MiSans）下的毛病，这边复现不出、也没法从参数上调平，就干脆不用它了\n'
    '· 日历格子上那个「有闹钟」的小圆点去掉了 —— 挂过闹钟的日子接近一半，半个网格都顶着一个小点，是不好看；「这天调过班」那个点还在（右上角那个）\n'
    '· 顺带：所有输入框会比以前高一点点（名字从压在框线上，变成框上面单独一行）\n'
    '\n'
'v0.11.19\n'
    '· 「调整班次」弹层里，标题左边那根主色竖条往下挪了一点：以前它比标题的字高半行，看着有点歪\n'
    '· 排班管理页的「新增排班」按钮落到了屏幕底部：上一版把它抬高了 76，而那一抬是给主界面底部的导航胶囊让位的，这一页底下没有胶囊\n'
    '· 日历格子上能看出哪天有闹钟了：班次挂过闹钟的那天，胶囊左上角有个小圆点（右上角那个仍然是「这天调过班」）\n'
    '· 自定义班次颜色时，色值前面带 0x 的写法也认了（以前只认 #）\n'
    '· 小窗（分屏）下帮助界面的正文不再被左边的圆图标挤成四五个字一行：一窄，图标就自己站一行\n'
    '\n'
'v0.11.18\n'
    '· 「同一个东西长得不一样」的地方收了一批：底部弹层的标题现在跟弹窗一样带主色竖条，还能往下拉关闭；小节标题全 App 统一成一档（「我的」页那几个会比以前大一点、黑一点）；空态与加载中各自收成一个样子；卡片和列表行按下的反馈也统一了\n'
    '· 两颗最显眼的主操作按钮换回自家的玻璃件：编辑排班页的「保存并重排闹钟」和排班管理页的「新增排班」，以前用的是系统按钮（按下是水波纹，跟别处不一致）\n'
    '· 排班管理页的「新增排班」从列表末尾挪到了屏幕底部，跟另外两页一个位置，不再悬在页面中间\n'
    '· 「管理模板」与权限卡里的「去开启」从裸文字换成胶囊 —— 全 App 的入口都是胶囊，裸文字读起来像正文\n'
    '\n'
    'v0.11.17\n'
    '· 「使用帮助」从弹窗改成整页：开头一段整体简介，下面每个功能块一句简介，再往下是一个入口\n'
    '· 新的下一层「遇到问题怎么解决」：按你想干的事分两组（「我想办一件事」/「它不对劲」），三十来条，每条说清去哪一页、点什么\n'
    '· 修好帮助里已经过时的说法：「一个班次最多挂 6 条闹钟」其实早就放到 10 条了；零点班的响铃到底落在哪一天也讲清楚了\n'
    '· 补上四个此前在帮助里一个字都没提过的功能：重复待办、字体大小、按月排班、待办自动归档\n'
    '· 「我的 → 桌面」那一行改成跳进使用帮助的「桌面小组件」那一节，全 app 只剩一份说明\n'
    '\n'
    'v0.11.16\n'
    '· 新建排班时，「按月排班」和「我自己排」有了自己的分组「从零开始」—— 以前它们头上没有组名，看起来像是归在「常白」那一类里的\n'
    '· 「按月排班」那张卡片不再写「每天在岗 2 个班组」：按月的段长短随月份变，这个数没有单一答案\n'
    '· 长按某天弹出的调班界面补上了标题「调整班次」—— 以前只有一行日期，看不出这一屏是干嘛的\n'
    '· 日历上长按拖选一段日子时，那条选中带子不再上下鼓起：以前它比一格还高，跨周时相邻两行的带子会叠在一起\n'
    '\n'

    'v0.11.15\n'
    '· 排班方案多了一种规则：按月排班 —— 每月 1 号重新开始，比如「1–10 号中班、11–20 号白班、21 号到月底夜班」\n'
    '· 以前只能按固定周期轮，而月份长度不一样（28 / 29 / 30 / 31 天），走过几个月就会错一天，12 月 1 日会显示成夜班\n'
    '· 想切几段就切几段：加一段、删一段、改「每月第几天起」都行；删掉的那一段并进上一段，不会留出空档\n'
    '· 多班组按段错开（甲班从第 1 段、乙班从第 2 段……），都在同一天换班、只是换到不同的班次上\n'
    '· 新建排班时多一张「按月排班」的卡片；老的周期排班一点没变，两种规则在编辑器顶上切换，来回切都不会丢\n'
    '\n'

    'v0.11.14\n'
    '· 横屏（平板 / 车机）重新适配：日历页在横屏下改成左右两栏 —— 顶栏收进左栏不再横跨整屏、今日信息卡贴到右下角、日期网格不再被底部胶囊压住\n'
    '· 格子里的字在宽屏上放大一档：车机上格子本来就大，而字一直卡在手机那一档的上限，屏幕再大也不会变大\n'
    '· 底部导航胶囊在宽屏上不再铺满整屏（限到 440、居中）；待办那颗「＋」与闹钟页底部那两颗按钮也跟着内容栏对齐了\n'
    '· 手机竖屏与小窗的版式一个像素都没动\n'
    '\n'

    'v0.11.13\n'
    '· 收上一版那份独立审查抓出的四处。主要一条是小窗里的日期与待办副标题在省略 —— 它们其实从上一版之前就在省略了，只是没人盯着小窗那一档\n'
    '· 日历页「一屏构图」的保证线写准了：常见高度（360×780 及以上）四档都成立；矮屏（640 高）走既有的网格滚动兜底 —— 那里从最小档 0.9 就开始滚，是高度不够，与字号档位无关\n'
    '· 常设护栏补上小窗与 420×900 两档（原先漏了）。小窗里仍会省略的那几处每次跑都会打在输出里，只是不判失败 —— 故意不查的东西要看得见\n'
    '· 更新日志那句「系统字体调多大都不再影响界面」补上例外：桌面小组件是原生绘制的，仍跟随系统\n'
    '\n'

    ;

const String _changelogEn =         'v0.11.22\n'
    '· Fixed what the previous release brought in: in light mode the text on solid accent surfaces was dark, so the selected bottom-nav item and the segments on Me (theme mode / language / font size) were hard to read. They are white now\n'
    '· Darkening is now "just enough". It used to take 40% off the accent no matter how dark it already was, which crushed the default blue into near-black; now only the accents that genuinely need it (teal, orange) are darkened, and only until white text just passes\n'
    '· So pills, buttons, the nav item and switches are back near the accent you picked under Me, Appearance. The "one step darker" trade-off from the last release only shows on teal and orange now\n'
    '\n'
'v0.11.21\n'
    '· Solid accent surfaces now use a one-step darker accent: primary buttons, dialog buttons, the selected nav item, switches, checkboxes, the todo floating button and the top-bar accent pills. White text on the original accent was only 2.6:1 for teal and orange — effectively unreadable; all five accents are now 5.9:1 or better\n'
    '· Fixed a longer-standing problem on the way: that fill used to be semi-transparent (85% to 50%), which left even the default blue at 2.1:1 at the far end against a white card\n'
    '· The trade-off: solid surfaces are one step darker than the accent shown under Me > Appearance; the text stays white\n'
    '\n'
'v0.11.20\n'
    '· Field labels are now drawn above the box instead of floating on its border. The two squashed characters in your screenshot come from Android\'s Material floating label under the system font (MiSans): it does not reproduce here and cannot be tuned away from our side, so the app no longer uses it\n'
    '· Removed the little "has an alarm" dot from the calendar cells — nearly half the days carry alarms, so half the grid was speckled. The "shift was adjusted" dot (top-right) stays\n'
    '· Side effect: every input box is a little taller, because the label now takes its own line above the box\n'
    '\n'
'v0.11.19\n'
    '· In the "Adjust shift" sheet the accent bar left of the title moved down a little: it used to sit half a line above the title text\n'
    '· "Add schedule" on the Schedule management page dropped to the bottom of the screen: the previous release lifted it by 76, which is what the main screen\'s nav capsule needs — this page has no capsule\n'
    '· The calendar grid now shows which days carry alarms: a dot at the top-left of the shift chip (the top-right one still means the day was adjusted)\n'
    '· Custom shift colours now accept a 0x prefix as well as #\n'
    '· In a small window the round icon no longer squeezes help text into four or five characters a line — it moves onto its own line\n'
    '\n'
'v0.11.18\n'
    '· A sweep of the places where the same thing looked different: bottom sheets now carry the same accent-barred title as dialogs (and can be pulled down to close), section headings use one size everywhere (the ones on the Me page are a little larger and darker than before), empty states and loading spinners each have a single look, and pressing a card or a row now feels the same everywhere\n'
    '· The two most prominent primary buttons went back to the app\'s own glass button: the editor\'s "Save and reschedule" and the management page\'s "Add schedule" used to be plain system buttons with a water-ripple press\n'
    '· The management page\'s "Add schedule" moved from the end of its list to the bottom of the screen — the same place as on the other two pages, instead of floating in the middle of a short page\n'
    '· "Manage templates" and the permission card\'s "Go enable" went from bare text to pills: every entry point in the app is a pill, because bare text reads like body copy\n'
    '\n'
    'v0.11.17\n'
    '· The usage guide is now a full page instead of a dialog: a short intro, a line for each feature, and one way in\n'
    '· A new level under it, "How to get things done", sorted by what you are trying to do ("I want to…" / "Something looks wrong") — thirty-odd entries, each saying which page to open and what to tap\n'
    '· Fixed wording in the guide that had gone stale: it claimed a shift carries at most 6 alarms, when the limit has been 10 for a while; which day a midnight shift\'s alarm falls on is spelled out too\n'
    '· Added four features the guide had never mentioned: repeating todos, text size, monthly rosters and todo auto-archiving\n'
    '· The "Me → Home screen" row now jumps into the guide\'s widget section, so there is only one copy of that explanation\n'
    '\n'
    'v0.11.16\n'
    '· "Monthly roster" and "Build my own" now sit under their own heading, "Start from scratch" - before, they had no heading and looked like part of "Day shift only"\n'
    '· The "Monthly roster" card no longer says "2 crews on duty": a monthly roster\'s segments vary in length, so that number has no single answer\n'
    '· The sheet that opens when you long-press a day now has a title, "Adjust shift" - it used to show only a date\n'
    '· The band drawn while you drag-select days no longer bulges up and down: it used to be taller than one cell, so bands in neighbouring weeks overlapped\n'
    '\n'

    'v0.11.15\n'
    '· Schedules can now be driven by the month: the pattern resets on the 1st, for example days 1-10 on the middle shift, 11-20 on days, and the rest on nights\n'
    '· Until now only a fixed-length cycle was possible, and since months differ in length (28 / 29 / 30 / 31 days) the cycle drifted within a few months — December 1 came out as a night shift\n'
    '· Split the month into as many segments as you like: add one, remove one, or change the day it starts on. A removed segment merges into the previous one, so no day is ever left out\n'
    '· Crews offset by segment (crew A enters at segment 1, crew B at segment 2, ...), so every crew changes shift on the same day — just onto a different shift\n'
    '· A new "Monthly roster" card when you create a schedule. Existing cycle schedules are untouched, and the editor switches between the two rules without losing either\n'
    '\n'

    'v0.11.14\n'
    '· Landscape adapted for tablets and car head units: the calendar page goes two-column — the toolbar moves into the left column instead of spanning the whole screen, the today card pins to the bottom right, and the date grid is no longer covered by the floating capsule\n'
    '· The text inside the day cells steps up a size on wide screens: the cells are bigger there, but the text was pinned to the phone cap and never grew\n'
    '· The bottom navigation capsule no longer stretches across the whole screen on wide displays (capped at 440, centred); the todo "+" button and the two buttons at the bottom of the alarm page line up with the content column too\n'
    '· Phone portrait and small-window layouts are unchanged, pixel for pixel\n'
    '\n'

    'v0.11.13\n'
    '· Closes the four items the independent review of the last version turned up. The main one: the date and the to-do subtitles were being clipped in the small-window mode — they had been clipping since before the last version; nobody was watching that size\n'
    '· The calendar page promise of everything-on-one-screen is now stated precisely: it holds at every text size on ordinary heights (360x780 and up); on short screens (640 tall) the grid falls back to the scrolling it always had — there it scrolls even at the smallest text size, because it is about height, not text size\n'
    '· The standing guard now also covers the small window and 420x900 (it had missed both). The few places the small window still clips are printed on every run instead of failing — anything deliberately left unchecked has to be visible\n'
    '· The changelog line saying the system font setting no longer affects the interface now carries its exception: the home-screen widgets are drawn natively and still follow it\n'
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
