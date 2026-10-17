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
'v0.12.0\n'
    '· 桌面小组件贴齐 App：今日卡补齐班次备注 / 其他班组 / 本月统计，主色竖条通到卡底；月历「今天」换成半透明块、周标题改单字、班次胶囊按文字宽现量；三张卡的字号不再跟系统字号走\n'
    '· 按月排班：每月 1 号重新开始的一套切法，编辑排班顶上在「周期 / 按月」之间切换，段可加可删\n'
    '· 班次颜色扩到 16 种，并能自己调：色相条 + 饱和度/明度方盘 + 十六进制，两颗日历小样当场变色\n'
    '· 待办自动归档：做完的收进「已完成 N 条」，主列表只留没做的；一次性待办能从归档里点回来\n'
    '· 字号四档，App 自己管、不跟系统字号走；日历顶栏与信息卡跟着重排，不省略\n'
    '· 横屏 / 平板 / 车机上日历改成左右两栏；底部弹层统一头部、按住往下一拉就关；全 app 的小节标题、空态、加载态与按压反馈收成一套\n'
    '· 闹钟落点扩到前一天 / 当天 / 次日三档，每个班次上限 6 → 10 条；贪睡时长可选 1 / 5 / 10 / 15 / 20 / 30 分钟\n'
    '· 修：浅色档下状态栏图标跟着主题走、输入框标签在真机字体下不再被压扁、实心主色面上改白字、底部导航彩边接缝、编辑排班的「每月第 N 天起」不再省略\n'
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
'v0.11.23\n'
    '· 底部导航滑块滑动时那圈彩色光晕，右边不再有「一刀切」的硬边：以前那圈颜色绕一圈到右边时接不上、差了 60 度，看着像被切开。分段器、开关、日历那枚块共用同一份，一处修全都好\n'
    '· 桌面小组件不再跟着系统字体大小变：系统字号调到 200% 时，今日卡的时间行与「其他班组」那一行会被切掉、周条的星期几挤成一团；现在三张卡的尺寸和字都不随系统字号动\n'
    '· 月历小组件的周标题改成「一 二 三 四 五 六 日」（与 App 日历页同一份），以前是「周一 周二 …」，宽度差一倍、那一行比 App 抢眼得多\n'
    '· 月历里「今天」那一格改成 App 同款的半透明块（主色淡染 + 主色描边），不再是实心一块；那天要是法定节假日，农历的红色也回来了\n'
    '· 今日卡补齐了 App 信息卡上有的三行：班次后面那句备注（「休息日 · 不响闹钟」/「闹钟 07:00」）、「其他班组」四个字、以及「本月 大休13 · 白7 · 上夜6 · 下夜5」\n'
    '· 顺带：那三行补上之后今日卡上下的空白小了一半；月历格子里的班次胶囊也跟着格子大小缩放了，不再是一成不变的小号\n'
    '\n'
'v0.11.22\n'
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
    ;

const String _changelogEn =
'v0.12.0\n'
    '· Home-screen widgets now match the app: the today card gained the shift note, other crews and month tally, and the accent bar runs the full height; the month view marks today with the translucent block, uses single-character weekday headers and sizes shift chips to their text; none of the three cards follow the system font size any more\n'
    '· Monthly rosters: a schedule that starts over on the 1st of every month, switchable at the top of the editor, with addable and removable segments\n'
    '· Shift colours expanded to 16, plus a custom picker: hue bar, saturation/value square and hex input, with two live calendar samples\n'
    '· Todo auto-archive: completed items collect under "N completed" and the main list keeps only open ones; one-off items can be ticked back out of the archive\n'
    '· Four text sizes managed by the app rather than the system; the calendar header and info card reflow without ellipsis\n'
    '· The calendar becomes two columns in landscape, on tablets and car screens; bottom sheets share one header and can be pulled down to close; section headings, empty and loading states and press feedback are unified across the app\n'
    '· Alarm anchors now cover the day before, the same day and the next day; up to 10 alarms per shift; snooze length selectable from 1 to 30 minutes\n'
    '· Fixes: status-bar icons follow the theme in light mode, field labels are no longer squashed under the device font, white text on solid accent surfaces, the coloured rim seam on the nav bar, and the editor no longer truncates "from day N of each month"\n'
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
'v0.11.23\n'
    '· The coloured rim on the bottom-nav slider no longer has a hard edge on the right: the hues went 300 degrees around and did not meet, leaving a 60-degree step that read as a cut. The segment control, the switch and the calendar block share the same gradient, so all of them are fixed at once\n'
    '· Desktop widgets no longer scale with the system font size. At 200% the today card had its time row and the other-crews row clipped, and the week strip squeezed its weekday labels together; all three cards now keep their layout and their type whatever the system font size is\n'
    '· The month widget header now reads the single-character 一 二 三 form, the same one the app calendar page uses, instead of 周一 周二 … — twice as wide and far more prominent than the app row\n'
    '· The month widget marks today with the same translucent block the app uses (accent wash plus accent outline) instead of a solid fill; and if that day is a public holiday, the lunar date is red again\n'
    '· The today card gained the three rows the app info card has: the note after the shift name (Rest day · no alarm / Alarm 07:00), the Other crews label, and the month tally (This month · 13 off · 7 day · …)\n'
    '· Along the way: with those three rows the card top and bottom gaps are about half what they were, and the shift chips in the month grid now scale with the cell instead of staying one small size\n'
    '\n'
'v0.11.22\n'
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
