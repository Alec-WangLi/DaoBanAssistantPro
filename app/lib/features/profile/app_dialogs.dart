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

const String _changelogZh = 'v0.10.9\n'
    '· 液态玻璃推广到另外两个面：分段器（主题模式 / 主色调 / 语言那几排）与开关\n'
    '· 分段器选中那一块现在是一枚玻璃滴：按住会提起来、拖动跟手、边缘带一圈彩色折射光\n'
    '· 开关改成玻璃轨道：开着的时候玻璃里透着一层主色；按住时那枚钮会纵向拉长（宽度不变，参考 iOS 26）\n'
    '· 关掉液态玻璃时，这两处与之前一模一样\n'
    '\n'

    'v0.10.8\n'
    '· 底栏滑块那圈彩色的范围收紧了：外面那层从伸出约 33px 收到约 12px，里面也收了一半 —— 之前散得太开，像一片光雾\n'
    '· 彩边改成渐入渐出：手一动约 0.2 秒亮起来，手停下约 0.4 秒淡下去，不再是一动就「啪」地出现、一停就突然没了\n'
    '· 静止时依旧一点彩色都没有\n'
    '\n'

    'v0.10.7\n'
    '· 底栏滑块那圈彩色边缘重做成一层折射光晕：不再是贴在边上的那条彩带，而是从边缘往玻璃里化开、也往外面散一点的一层光\n'
    '· 彩色不再是只有左边和上边有 —— 之前另外三个方向几乎是空的，现在四面八方都有颜色，左上略亮\n'
    '· 静止时依然一个彩色像素都没有\n'
    '\n'

    'v0.10.6\n'
    '· 浅色下底栏胶囊的左右两边现在一样清楚（之前左边那圈白光把轮廓盖掉了，看着像只有右边有镜片）\n'
    '· 底栏那圈彩色折射光改成一动就满 —— 之前要滑得很快才明显，正常拖动基本看不出来\n'
    '· 按住拖动时滑块不再随着速度沉回胶囊，「按住」那个凸起全程都在\n'
    '· 滑块的形变改了走弹簧，起步与停下更顺，不再跟着速度硬切\n'
    '· 120Hz 屏幕上「速度被算成一半」的毛病修好了（拖动时形状大小不稳就是它）\n'
    '\n'

    'v0.10.5\n'
    '· 底栏滑块的手感重调：提起与落下用上了两条不同的弹簧（落下明显更从容），点按之后滑过去也慢了一档\n'
    '· 那圈彩色折射光现在只在动的时候亮 —— 完全停下时一个彩色像素都没有；同时加宽了一圈\n'
    '· 滑块边缘扫过图标时，图标与它下面的字会被轻轻挤一下（被罩在透镜正中时几乎不变，所以照样看得清）\n'
    '· 头大尾小那个形变更容易出现了 —— 不用滑那么快\n'
    '· 底栏每一帧只重画透镜那一层，不再整条重建\n\n'

    'v0.10.4\n'
    '· 修好窄窗口下的一处严重问题：拖动底栏滑块时它会整个消失、还一闪一没（窗口宽度不够时那个形状算不出来）\n'
    '· 点待办提醒的通知切到待办页时，底栏滑块也跟着走过去（之前页面翻过去了、滑块还留在原处）\n\n'

    'v0.10.3\n'
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

;

const String _changelogEn = 'v0.10.9\n'
    '· Liquid glass now covers two more surfaces: the segmented controls (theme mode, accent colour, language) and the switches\n'
    '· A segment’s selected block is now a glass droplet: it lifts when held, follows your drag, and carries a rim of chromatic light\n'
    '· Switches are now a glass track, tinted with the accent when on; press and the knob stretches vertically (same width, after iOS 26)\n'
    '· With liquid glass off, both look exactly as they did before\n'
    '\n'

    'v0.10.8\n'
    '· The coloured rim on the tab pill is much tighter: the outer spread went from about 33px to about 12px, and the inner one came in by half — it used to read as a haze of light rather than glass\n'
    '· The rim now fades in and out: about 0.2s to light up when you start moving, about 0.4s to fade when you stop, instead of snapping on and off\n'
    '· Still nothing coloured at all while the pill is at rest\n'
    '\n'

    'v0.10.7\n'
    '· The tab pill’s coloured edge is now a refractive halo — light spreading into the glass and a little beyond it, instead of a ribbon stuck along the rim\n'
    '· The colour now wraps the whole rim: before, only the left and top had any (the lower right was essentially empty)\n'
    '· Still nothing coloured at all while the pill is at rest\n'
    '\n'

    'v0.10.6\n'
    '· In light mode both ends of the tab capsule are equally visible now (a white rim used to erase the outline on the left, so only the right end looked like glass)\n'
    '· The prismatic rim is at full strength the moment the pill moves — before, you had to drag very fast to see it at all\n'
    '· While you hold and drag, the pill no longer sinks back inside the capsule, so the lifted bump stays for the whole drag\n'
    '· The pill’s shape now eases along a spring instead of snapping straight to the raw speed\n'
    '· Fixed the speed being computed as half its real value on 120Hz displays (that was the shape wobbling as you dragged)\n'
    '\n'

    'v0.10.5\n'
    '· Reshaped the tab pill: lifting and dropping now use two different springs (the drop is noticeably more unhurried), and a tap slides it across one notch slower\n'
    '· The prismatic rim now only lights up while the pill is moving — nothing coloured at all when it is still — and it is a bit wider\n'
    '· As the rim sweeps past an icon, the icon and its label get a slight squeeze (almost none when the pill sits right on top, so it stays readable)\n'
    '· The head-big tail-small stretch shows up sooner — no need to drag as fast\n'
    '· The tab bar now repaints only the lens layer each frame, not the whole bar\n\n'

    'v0.10.4\n'
    '· Fixed a serious bug in narrow windows: the tab pill could vanish entirely — and flicker — while you dragged it\n'
    '· Tapping a todo reminder now carries the tab pill along when the app jumps to the todo page (previously the page moved but the pill stayed put)\n\n'

    'v0.10.3\n'
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
