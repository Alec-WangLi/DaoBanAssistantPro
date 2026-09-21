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

const String _changelogZh = 'v0.9.2\n'
    '· 新增：每个班次最多可以配 6 个联动闹钟，每条还能起个名字（「起床」「午休」）。响铃标题会写明是哪一条（「白班 · 午休」）；不填名字就还是「白班提醒」\n'
    '· 修好一个会把闹钟排错天的问题：钟点落在值班时间之内的闹钟（白班的午休、零点班班中那次）从前被排到前一天同一钟点 —— 等于提前二十来小时响。现在这类算班次当天；起床闹钟那种（早于上班、或零点班的前一晚）照旧\n'
    '· 班次编辑页的闹钟区跟着改了：一条一行（时间 + 名字 + 删除），下面有「添加闹钟」；到 6 个上限时收掉按钮、给一行说明\n'
    '· 闹钟页「未来 30 天」一个班次当天有几条就列几行，「前一天」那条各自标；日历信息卡写「闹钟 06:30 等 2 个」\n'
    '· 数据库版本 9 → 10（班次闹钟单独一张表），老数据自动搬过去，配过的闹钟一条不丢（开关关着但时间还留着的也搬）\n\n'

    'v0.9.1\n'
    '· 修好一个用户反馈的问题：添加待办时快速连点「添加」，整个界面会变黑 —— App 本身没死也没卡住（状态栏还在、也能切走），只是界面被「关到底」了，只能杀掉重开。原因是这类保存要过一小会儿才落定，这段窗口里再点一次就会多存一条待办、并且多关一层 —— 多关掉的那一层正是 App 唯一剩下的主界面。现在连点只存一条，界面也不会再被关空\n'
    '· 同一道护栏也盖住了另外两条能把界面点黑的路径：「点完添加马上点取消」、以及闹钟弹窗里的「添加 / 保存」\n\n'

    'v0.9.0\n'
    '· 正式稳定版，归纳 0.8.1 到 0.8.12 的全部更新\n'
    '· 桌面小组件：三张固定尺寸的卡 —— 本周条（4×1，今天所在这一周）、今日卡（4×3，底栏那张信息卡的完整版）、整月（4×5，42 格月历）。放置后不能拉伸，在 App 里改了排班桌面立刻跟着变，点某一天直接跳到那天的日历。升级后桌面上原有的旧小组件会消失，需要在桌面重新添加一次（小米 / HyperOS 在「支持小部件的应用 → 安卓小部件」里找）\n'
    '· 日历上可以单独改某几天的班了：点底栏那行班次、或长按格子拖选一段（可跨周、不跨月），就能给这几天单独指定班次（请假、跟同事换班都行），不动整套排班。被改过的那天格子上有个小圆点、信息卡写着「已调班」，选择层里可一键「恢复轮转」\n'
    '· 新增「我的模板」：调好一套排班之后，在编辑器右上角点「存为模板」，下次新建排班时直接在「我的模板」里选它，不用每次从头搭\n'
    '· 新增「五班三倒 · 10 天一轮」模板；触觉反馈（切换开关、选中、拖选与改班时轻微震动，可在「我的 → 外观」里关掉）\n'
    '· 修好两个用户反馈的问题：① 零点班（00:00 上班）的联动闹钟从前排在班次当天 —— 那会儿班已经结束 15 小时了，现在排在上班前 1 小时（前一天晚上），界面上写明「前一天」；② 把 5 天一轮的排班改成 10 天之后，同一天会出现两个班组上同一个班 —— 现在编辑器的「周期设置」里会点出相撞的两个班组，并给一个按钮按周期长度均分各组的起始日\n'
    '· 修好「存了模板在新建排班时看不到」：如果这一趟先打开过「新建排班」，之后存的模板要等重启 App 才出现 —— 现在每次打开都会重新读\n'
    '· 一批小组件与界面的修复：大卡上「今天」的标记、待办数徽章跟着变、删掉小组件后不再后台刷新；小窗（高 < 480dp）改为只显示今日信息卡；横竖屏与宽屏布局收口；调整班次的选择层重排、色点与信息卡统一成 12dp\n'
    '· 内置倒班方式模板共 20 种；数据库版本 8 → 9（新增「我的模板」一张表，原有排班与待办一条不丢）\n\n'

    'v0.8.12\n'
    '· 修好「存了模板却在新建排班时看不到」：如果这一趟开 App 时先打开过一次「新建排班」（那时还没有模板），之后存下的模板要等重启 App 才出现 —— 现在每次打开都会重新读\n'
    '· 存完模板的提示补了一句去哪儿找：「新建排班时可选」\n\n'
    'v0.8.11\n'
    '· 新增「我的模板」：调好一套排班之后，在编辑器右上角点「存为模板」，下次新建排班时直接在「我的模板」里选它 —— 自己厂里的班表不用每次从头搭\n'
    '· 存下的模板可以在选择页点「管理」改名或删除；每张卡片上写着几天一轮、几个班组\n\n'
    'v0.8.10\n'
    '· 新增「五班三倒 · 10 天一轮」模板：早班两天、中班两天、休一天、夜班两天，然后休三天。此前只有 5 天一轮的那套，10 天一轮得自己搭 —— 内置模板现在共 20 种\n'
    '· 修好「把 5 天一轮的排班改成 10 天之后，同一天有两个班组上同一个班」：各组的周期起始日此前不跟着周期长度走。现在编辑器的「周期设置」里会直接点出撞班的两个班组，并给一个按钮把各组起始日按周期长度一键均分（你自己那一组不动）\n\n'
    'v0.8.9\n'
    '· 修好零点班（00:00 上班）的联动闹钟排晚了整整一天：响铃设成 23:00 时，以前排在班次当天晚上 23:00 —— 那时这个班已经结束 15 个小时；现在排在「前一天」晚上 23:00，也就是上班前 1 小时。早班、中班这些上班前设响铃的班次不受影响\n'
    '· 闹钟落在上班前一天的，界面上会写明「前一天」：班次设置里响铃那一块写成「前一天 23:00」并附一行说明，闹钟页的列表和日历信息卡同样标出来 —— 以前只写「23:00」，看不出是哪一天\n\n'
    'v0.8.8\n'
    '· 桌面小组件改成三张固定尺寸的卡，放置之后不能再拉伸：本周条（4×1，今天所在这一周的七天）、今日卡（4×3，App 底栏那张信息卡的完整版）、整月（4×5，月份标题 + 周几行 + 42 格）\n'
    '· 三张卡的视觉跟着 App 的设计语言走：班次胶囊从实心改成淡染底 + 同色描边（那天没班次就不画），去掉「白卡里再套白卡」的双层\n'
    '· 升级后桌面上原有的旧小组件会消失，需要在桌面重新添加\n\n'
    'v0.8.7\n'
    '· 修好桌面小组件上那枚「N 项待办」徽章不跟着变：在 App 里勾掉或新增今天的待办之后，此前要等到下次打开 App 它才更新，现在会跟着一起变\n'
    '· 内部：推送路径上新加的一处数据库读取补上了错误处理 —— 此前读失败一次会中断整次推送刷新\n\n'
    'v0.8.6\n'
    '· 桌面小组件按尺寸重做了版式：矮的时候是一列班次，按高度显示今天起 2 / 3 / 5 天；高的时候是一周或两周的网格，网格下面附一张今日卡片，写着农历、其他班组当天的班次和当天有几项待办\n'
    '· 改的原因是原来三个版式要摊到七个高度上：拉高或压扁之后行高会被拉长、格子显得又大又空。现在每个高度都有一版对得上的版式\n';
const String _changelogEn = 'v0.9.2\n'
    '· New: each shift can carry up to 6 linked alarms, and each one can have a name ("Wake up", "Nap"). The ringing screen says which one it is ("Day shift · Nap"); leave the name empty and it stays "Day shift alarm"\n'
    '· Fixed alarms landing on the wrong day: an alarm whose clock time falls inside the shift (a lunch nap on a day shift, a break during a midnight shift) used to be scheduled on the previous day at the same time — some 20 hours early. Those now ring on the shift\'s own day; wake-up alarms (before the shift, or the night-before case for midnight shifts) are unchanged\n'
    '· The shift editor\'s alarm section follows: one row per alarm (time + name + delete) with an "Add alarm" button; at the 6-alarm limit the button goes away and a line explains why\n'
    '· The alarm page lists every alarm a shift has that day, each carrying its own "day before" tag where it applies; the calendar info card reads "Alarm 06:30 (+1)"\n'
    '· Database version 9 → 10 (alarms get their own table); existing data moves over automatically and no alarm is lost — including times kept on shifts whose alarm switch is off\n\n'

    'v0.9.1\n'
    '· Fixed an issue reported by users: tapping "Add" twice in a row while adding a todo turned the whole screen black — the app itself was neither dead nor frozen (the status bar was still there, you could still switch apps), the UI had simply been dismissed one screen too far, and only killing the app brought it back. The save takes a moment to land, and a second tap inside that window stored a duplicate todo and dismissed an extra screen — that extra one being the app\'s only remaining screen. A rapid double-tap now stores a single todo and leaves the UI alone\n'
    '· The same guard covers two other ways to black out the screen: tapping "Add" and then "Cancel" right away, and the "Add / Save" buttons in the alarm dialog\n\n'

    'v0.9.0\n'
    '· Stable release — merges everything from 0.8.1 through 0.8.12\n'
    '· Home-screen widgets: three fixed-size cards — a week strip (4×1, the current week), a today card (4×3, the full version of the info card at the bottom of the app) and a month view (4×5, a 42-cell calendar). They cannot be resized once placed, follow any schedule change you make in the app, and tapping a day jumps to that date in the calendar. After upgrading, the old widget disappears from your home screen — add it again (on Xiaomi / HyperOS it lives under "Apps that support widgets → Android widgets")\n'
    '· Override individual days on the calendar: tap the shift row in the bottom bar, or long-press a cell and drag to pick a range (across weeks, not months), to give just those days a shift of their own — a day off, or swapping with a colleague — without touching the rest of the rotation. An overridden day carries a small dot in the grid and reads "Shift changed" on the info card, and the picker offers a one-tap "Restore rotation"\n'
    '· New "My templates": once a schedule looks right, tap "Save as template" in the editor and pick it next time you create one — no more rebuilding your own roster from scratch\n'
    '· New "5-crew 3-shift · 10-day cycle" template; haptic feedback (a light buzz when you flip a switch, pick an option, drag-select or apply a day change — turn it off under Me → Appearance)\n'
    '· Fixed two issues reported by users: (1) shift alarms for midnight shifts (00:00 start) used to be scheduled on the shift\'s own day — by then that shift had been over for 15 hours; they now ring one hour before the shift starts, the evening before, and the UI says so; (2) after changing a 5-day cycle into a 10-day one, two crews ended up on the same shift on the same day — the editor\'s cycle section now names the colliding crews and offers a button that spreads their start dates evenly\n'
    '· Fixed "saved templates not showing up when creating a schedule": if you had opened "New schedule" earlier in the same session, a template saved afterwards only appeared after restarting the app — the list is now re-read every time\n'
    '· A batch of widget and UI fixes: the "today" marker on the large card, the todo-count badge keeping up, no more background refresh after you remove the widget; small windows (under 480dp tall) now show only today\'s info card; landscape and wide-screen layouts tightened up; the adjust-shift sheet reworked with the colour dot unified to 12dp\n'
    '· 20 built-in shift-pattern templates; database version 8 → 9 (one new table for "My templates" — no existing schedules or todos are lost)\n\n'

    'v0.8.12\n'
    '· Fixed saved templates not showing up in the picker: if you had opened "New schedule" once earlier in the same app session (back when you had no templates yet), a template saved afterwards only appeared after restarting the app. The list is now re-read every time you open it\n'
    '· The confirmation shown after saving now says where to find it ("pick it when creating a schedule")\n\n'
    'v0.8.11\n'
    '· New "My templates": once a schedule looks right, tap "Save as template" in the editor\'s top-right corner and pick it the next time you create a schedule — no more rebuilding your own roster from scratch\n'
    '· Saved templates can be renamed or deleted from "Manage" on the picker; each card shows the cycle length and team count\n\n'
    'v0.8.10\n'
    '· New "5-crew 3-shift · 10-day cycle" template: two mornings, two afternoons, one off, two nights, then three off. Until now only the 5-day version existed, so a 10-day roster had to be built by hand — there are now 20 built-in templates\n'
    '· Fixed two crews landing on the same shift on the same day after changing a 5-day cycle into a 10-day one: the crew start dates never followed the cycle length. The editor\'s cycle section now names the two crews that collide and offers a button that spreads every crew start date evenly across the cycle (your own crew stays put)\n\n'
    'v0.8.9\n'
    '· Fixed shift alarms for midnight shifts (00:00 start) landing a full day late: an alarm set to 23:00 used to be scheduled for 23:00 on the shift\'s own day — by then that shift had been over for 15 hours. It now rings at 23:00 the day before, one hour before the shift starts. Morning and afternoon shifts, whose alarm already sits before the start, are unaffected\n'
    '· When an alarm falls the day before a shift the app now says so: the shift editor shows "23:00 (day before)" with a line explaining why, and the alarm list and the calendar info card are tagged the same way — a bare "23:00" never told you which day it was\n\n'
    'v0.8.8\n'
    '· The home-screen widget is now three fixed-size cards that cannot be resized once placed: a week strip (4×1 — the seven days of the current week), a today card (4×3 — the full version of the info card at the bottom of the app), and a month view (4×5 — month title, day-of-week row and a 6×7 grid)\n'
    '· Their look now follows the app\'s design language: shift chips went from solid fills to a tinted background with a matching outline (a day with no shift stays blank), and the "white card inside a white card" double container is gone\n'
    '· After upgrading, the old widget on your home screen will disappear — you will need to add it again\n\n'
    'v0.8.7\n'
    '· Fixed the "N todos" badge on the home-screen widget not keeping up: after you tick off or add a todo for today in the app, the badge used to stay put until the next time you opened the app — it now follows along\n'
    '· Internal: a database read on the widget-push path gained error handling — one failed read used to abort the whole push refresh\n\n'
    'v0.8.6\n'
    '· The home-screen widget was rebuilt around size: when it is short it shows a single column of shifts — 2, 3 or 5 days from today, depending on how tall it is; when it is tall it shows a one- or two-week grid with today\'s card below it, listing the lunar date, the other teams\' shifts for the day and how many todos the day has\n'
    '· The reason: the three old layouts had to stretch across seven possible heights, so raising or squashing the widget stretched the row height and left the cells large and empty. Each height now has a layout that fits it\n';

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

void showUsageGuideDialog(BuildContext context) {
  final items = [
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

  showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) {
      final accent = Theme.of(context).colorScheme.primary;
      final muted = AppTokens.inkMuted(context);
      return GlassDialog(
        title: L10n.usageGuide,
        showClose: true,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final it in items) ...[
                  Row(
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
                          border: Border.all(
                              color: accent.withValues(alpha: 0.35)),
                        ),
                        child: AppIcon(it.$1,
                            size: AppTokens.iconMd, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.$2, style: AppTokens.labelStrong),
                            const SizedBox(height: AppTokens.padChipV),
                            Text(it.$3,
                                style: AppTokens.rowSecondary
                                    .copyWith(height: 1.45, color: muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
        actions: [
          GlassActionButton(
            variant: GlassActionVariant.primary,
            onPressed: () => Navigator.pop(context),
            label: L10n.ok,
          ),
        ],
      );
    },
  );
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
