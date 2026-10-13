import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/update_checker.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../alarm/alarm_service.dart';
import 'help_entry.dart';

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

const String _changelogZh = 'v0.11.16\n'
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

    'v0.11.12\n'
    '· 字号改成只由 App 自己决定：我的 → 外观 → 字体大小，小 / 标准 / 大 / 特大四档。系统字体调多大都不再影响界面（桌面小组件除外 —— 它是原生绘制的，仍跟随系统）\n'
    '· 起因是有人反馈「系统字号调大之后，日历顶栏的月份被截成 2026年1…」。实拍下来，系统调到 200% 时信息卡会吃掉半个屏、日历网格只剩三行\n'
    '· 代价说在明处：把系统字号调到 150%~200% 的人，在这个 App 里拿不到那个大小 —— 最大就到「特大」\n'
    '· 顺带把全 App 的「字被悄悄省略」收干净：顶栏年月、信息卡那两行、列表副标题、编辑器的标签与值、14 天预览条、几个整页的标题\n'
    '· 窄屏或大字号下会自动换版式（顶栏改两行、副标题折行、定尺的地方等比缩小），而不是把字吃掉\n'
    '\n'

    'v0.11.11\n'
    '· 修一条状态栏的毛病：浅色主题下进「排班管理」，状态栏那几个图标会反成白的、退回来也不恢复；深色主题下没事。根子是我们从来没自己声明过这件事，一直靠各家系统的默认值，所以同一版在有的手机上出、有的手机上不出\n'
    '· 现在它跟着「主题模式」那一档走：浅色档配深色图标、深色档配白色图标，判据全 app 只有一处\n'
    '· 响铃界面顺带修了：它是整屏深色，浅色档下从前会压一排看不见的深图标\n'
    '\n'

    'v0.11.10\n'
    '· 内部收口，界面看不出变化：上一版那三张卡里有几处边角没算干净，这一版补齐\n'
    '· 卡片底板那层浅灰的暗端，与落在它上面的灰字差了 0.01（4.49 对标准的 4.5），已经调过来\n'
    '· 桌面小组件重绘时少做 41 次跨进程查询（原先每一格都要问一次屏幕尺寸）\n'
    '· 又补了三条自动护栏，把「块的图层顺序」「块尺寸必须按真实格子算」「渐变的每个端色都要过对比度」都钉住了\n'
    '\n'

    'v0.11.9\n'
    '· 桌面小组件贴齐了 App：月历卡恢复成「每一格一张白卡」（底板改成页面那样的浅灰，卡片才显出来），今天那一格变成一块实心主色块，格子里的班次胶囊也跟着转实心\n'
    '· 周条里今天那一列同样铺一块实心主色；今日卡上那枚「今天」也从淡染改成实心主色 —— 三处现在是同一件事\n'
    '· 块上的字按对比度自己挑黑或白（青、橙那两档主色调下会挑黑字），不用你操心\n'
    '· 说明一句：桌面上没有实时的背景模糊，那点玻璃感只能靠描边、圆角与渐变去近似，卡片不会真的透出壁纸\n'
    '\n'

    'v0.11.8\n'
    '· 「再睡一会」的时长可以自己定了：我的 → 闹钟 → 贪睡时长，可选 1 / 5 / 10 / 15 / 20 / 30 分钟（默认仍是 5 分钟，不动它就跟以前一样）\n'
    '· 响铃界面那颗按钮上现在写着时长（「再睡一会 · 10 分钟」），按下之前就知道会睡多久\n'
    '\n'

    'v0.11.7\n'
    '· 修好一处「颜色值填好了，却点不到确定」：软键盘弹起来的时候，会正好盖住取色层底下那颗「确定」按钮（填写颜色值本来是这一层的主要入口，键盘一弹按钮就落在键盘底下了）\n'
    '· 现在键盘弹起来，整块取色面板会顶到键盘上面去\n'
    '\n'

        '\n'
;

const String _changelogEn = 'v0.11.16\n'
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

    'v0.11.12\n'
    '· Text size is now decided by the app alone: Me → Appearance → Text size, with Small / Standard / Large / XL. The system font setting no longer affects the interface (the home-screen widgets are the exception — they are drawn natively and still follow it)\n'
    '· It started from a report that the month in the calendar header was cut to 2026年1… when the system font was large. Measured at 200%: the info card ate half the screen and the calendar grid kept only three rows\n'
    '· The cost, said plainly: anyone who set the system font to 150-200% will not get that size here — XL is the ceiling\n'
    '· Also cleaned up every place the app quietly ate text: the header month, the two info-card lines, list subtitles, the editor labels and values, the 14-day preview strip, and three page titles\n'
    '· On narrow screens or at larger text sizes the layout changes instead (a two-row header, wrapping subtitles, fixed-size bits scaled down) rather than dropping characters\n'
    '\n'

    'v0.11.11\n'
    '· Fixed a status-bar glitch: with the light theme, opening Schedule management turned the status-bar icons white and they stayed that way after going back. The dark theme was unaffected. It happened because the app never declared this itself and left it to each phone maker\'s default, which is why the same build showed it on some phones and not others\n'
    '· It now follows your Theme mode: dark icons in the light theme, white icons in the dark theme, decided in one place\n'
    '· The ringing screen got the same fix: it is dark all over, so in the light theme it used to show dark icons you could not read\n'
    '\n'

    'v0.11.10\n'
    '· An internal tidy-up; nothing looks different: a few edges left over from the previous version are now closed\n'
    '· The dark end of the panel gradient was 4.49:1 against the grey text on it, just under the 4.5 bar — that is fixed\n'
    '· Redrawing the home-screen widgets now makes 41 fewer cross-process queries (it used to ask for the screen size once per day cell)\n'
    '· Three more automated guards now pin the block layer order, the block sizing, and the contrast of every gradient end\n'
    '\n'

    'v0.11.9\n'
    '· The home-screen widgets now match the app: the month card is back to one white card per day (its panel became the page colour, which is what makes the cards read as cards), and today is a solid accent block with the shift chip inside it going solid too\n'
    '· The week strip marks today with the same solid block, and the today card\'s "Today" pill went from a washed-out tint to solid accent — the three now look like the same thing\n'
    '· Text on those blocks picks black or white by contrast (it picks black on the teal and orange accents), so you do not have to think about it\n'
    '· One note: there is no live background blur on the home screen, so that bit of glass can only be approximated with borders, corners and gradients — the cards do not really show the wallpaper through\n'
    '\n'

    'v0.11.8\n'
    '· You can now choose how long Snooze waits: Me → Alarm → Snooze length, with 1 / 5 / 10 / 15 / 20 or 30 minutes (the default is still 5, so leaving it alone changes nothing)\n'
    '· The snooze button now shows that length ("Snooze · 10 min"), so you know how long you are getting before you tap it\n'
    '\n'

    'v0.11.7\n'
    '· Fixed "the color value is typed, but OK cannot be tapped": with the software keyboard up, it covered the OK button at the bottom of the color picker (typing a value is the main way into that screen, and the button landed right underneath the keyboard)\n'
    '· The whole picker panel now rides up above the keyboard\n'
    '\n'

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

/// 「我的 → 桌面小组件」那一行的说明弹层。
///
/// 正文与《使用帮助》里的同一条目**共用一份文案**（`L10n.guideWidgetDesc`）——
/// 各写一份的话，改了这边忘了那边，就成了「说明书和 App 说的不一样」。
/// 弹窗标题已经把「是什么」说了，条目里不再顶一行标题（`title: null`）。
void showWidgetGuideDialog(BuildContext context) {
  _showHelpDialog(
    context,
    title: L10n.guideWidgetTitle,
    content: HelpEntry(
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
          HelpEntry(icon: it.$1, title: it.$2, lines: it.$3),
          const SizedBox(height: 16),
        ],
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
