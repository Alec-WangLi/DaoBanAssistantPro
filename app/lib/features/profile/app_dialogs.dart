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

const String _changelogZh = 'v0.11.12\n'
    '· 字号改成只由 App 自己决定：我的 → 外观 → 字体大小，小 / 标准 / 大 / 特大四档。系统字体调多大都不再影响界面\n'
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

    'v0.11.6\n'
    '· 班次颜色从 8 种扩到 16 种：色相铺满一圈，红、品红、琥珀、深橙、深绿、深青、棕、粉是这一版新加的（原来那 8 种一颗没动）\n'
    '· 新增「自定义颜色」：点班次行末那颗色点，里面有色相条和一块饱和度/明度方盘，也可以直接填颜色值（例如 #4C8DFF）\n'
    '· 取色的时候旁边摆着两颗真的日历小样，能当场看到这个颜色落到日历上是什么样\n'
    '· 那 16 种默认颜色都保证在日历格子与桌面小组件上看得清（这一版为此逐颗量过，并有测试盯着）\n'
    '\n'

    'v0.11.5\n'
    '· 修好一处崩溃：重复待办的管理面板在极少数情况下点开就闪退（那个系列短时间里有两条「没做完」的行时，比如刚把当前那一条勾回来、而生成器还没跑）\n'
    '· 勾完那条「已划掉 · 撤销」的提示条，点完「撤销」会自己收掉 —— 之前它会继续挂在那里，说的还是反话\n'
    '\n'

    'v0.11.4\n'
    '· 已完成的待办现在可以直接取消勾选、放回列表 —— 一次性待办在「已完成」里也带勾选框了（重复待办的旧记录仍然只有删除键：那个系列可能已经走到下一次，放回来会同时有两条没做完的）\n'
    '· 勾错了不用去那堆淡掉的行里找：勾完底下会弹一条「已划掉 · 撤销」，点一下就退回来\n'
    '· 修好一处像「点了没反应」的：在主列表里取消勾选的那一瞬间，那一条会先跳走再跳回来\n'
    '· 「已完成 N 条」那一行从一行灰字换成一颗胶囊，跟「今天」「重复待办」那些入口同一款\n'
    '· 同一天里的多条待办，归档时改成按钟点从晚到早排（原来是按行号倒着来的）\n'
    '\n'

    'v0.11.3\n'
    '· 待办勾完不再一直堆在列表里了：主列表只列没做完的，做完的收进列表底部一条「已完成 N 条」里（点一下展开，看得出之前干完了什么）。勾完那一刻它仍留在原地、划掉，下次进这一页才收走\n'
    '· 归档最多留 100 条，更早的自己消失 —— 所以这个列表会一直干干净净\n'
    '· 顺带修好一处：删掉一条「重复待办」之后它又被自己补回来（从归档里删更旧的历史会踩到）\n'
    '\n'


        '\n'
;

const String _changelogEn = 'v0.11.12\n'
    '· Text size is now decided by the app alone: Me → Appearance → Text size, with Small / Standard / Large / XL. The system font setting no longer affects the interface\n'
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

    'v0.11.6\n'
    '· Shift colors go from 8 to 16: the full hue circle, with red, magenta, amber, deep orange, deep green, deep teal, brown and pink added (the original 8 are untouched)\n'
    '· New custom colors: tap the color dot on a shift row for a hue strip, a saturation/brightness pad, and a field for typing a value such as #4C8DFF\n'
    '· Two live calendar samples sit next to the picker, so you can see how the color will look on a real cell\n'
    '· All 16 built-in colors are guaranteed readable on calendar cells and on the desktop widget (each one measured, with a test keeping watch)\n'
    '\n'

    'v0.11.5\n'
    '· Fixed a crash: the recurring-todo panel could crash on open in a rare case (when a series briefly holds two unfinished rows — for example right after you un-tick the current one and the generator has not run yet)\n'
    '· The "Marked done · Undo" bar now dismisses itself once you tap Undo — it used to linger and keep saying the opposite\n'
    '\n'

    'v0.11.4\n'
    '· Completed todos can now be un-ticked straight back into the list — one-off todos get a check box under "completed" too (older entries of a recurring todo still only offer delete: that series may already have rolled on to its next occurrence, and bringing the old one back would leave two open rows for the same series)\n'
    '· Mis-tapped one? No need to dig through the faded rows: an "Marked done · Undo" bar appears at the bottom and one tap puts it back\n'
    '· Fixed something that read as a dead tap: un-ticking from the main list used to make the row jump away and then jump back\n'
    '· The "N completed" row is now a capsule, matching the other entries such as "Today" and "Recurring"\n'
    '· Several todos on the same day now sort by time of day, latest first (they used to come out in reverse row order)\n'
    '\n'

    'v0.11.3\n'
    '· Completed todos no longer pile up in the list: the main list shows only what is still open, and finished ones move into an "N completed" row at the bottom (tap it to expand and see what you got done). The moment you tick one it stays where it was, struck through, and only moves down there the next time you open this page\n'
    '· The archive keeps the latest 100; older ones drop off on their own, so this list stays tidy\n'
    '· Also fixed: deleting a recurring todo used to bring it straight back (it could happen when deleting an older occurrence from the archive)\n'
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
