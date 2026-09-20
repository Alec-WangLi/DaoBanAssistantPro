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

const String _changelogZh = 'v0.8.9\n'
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
    '· 改的原因是原来三个版式要摊到七个高度上：拉高或压扁之后行高会被拉长、格子显得又大又空。现在每个高度都有一版对得上的版式\n\n'
    'v0.8.5\n'
    '· 修好大卡上「今天」那格没有标记：它的日期现在用主色 + 加粗，跟 App 日历里今天那格的做法一样（此前计划里要做的标记没落地，那格和别的格子看着一样）\n'
    '· 修好删掉小组件之后它还在后台每天自动刷新一次 —— 桌面上没有小组件时，不再排下一次刷新\n'
    '· 修好小卡在「还没有排班」变成「已排班」之后，班次名、日期、色条和分隔线一直不显示 —— 现在会正常出现\n'
    '· 内部：补了 2 条测试（跨天的 24 小时班、按天改班反映到小组件快照），给一处过长的文字补上省略\n\n'
    'v0.8.4\n'
    '· 新增桌面小组件：小/中/大三档尺寸，一眼看到今天、未来三天或一周的班次\n'
    '· 跨天自动翻页；在 App 里改了排班，桌面立刻跟着变\n'
    '· 点小组件上的某一天，直接跳到那天的日历\n'
    '· 小米 / HyperOS 机型上，小部件要进「支持小部件的应用」→「安卓小部件」才找得到（长按桌面空白处 → 添加小部件）；添加后没看到它，不代表功能没生效\n\n'
    'v0.8.3\n'
    '· 「调整班次」那个选择层重排了一遍：标题不再居中、行距收紧、色点与信息卡统一成 12dp、底部「恢复轮转」用一条分隔线单独隔开（不再看着像第五个班次）\n'
    '· 小窗（高 < 480dp）里改成只显示今日信息卡、不再画日历网格 —— 那个尺寸下两者都看不清；信息卡同时补上「已调班」标记，所以小窗里也看得出哪天被调过\n'
    '· 「已调整」改叫「已调班」（请假和换班都说得通）\n'
    '· 修好窄弹层里班次名被挤成一行一个字，以及横屏下色点被裁成半圆\n\n'
    'v0.8.2\n'
    '· 加了触觉反馈：切换开关、选中、删除确认时会轻微震动，长按拖选日子时还会逐格轻震一下。可在「我的 → 外观」里关掉\n'
    '· 修好了几处界面对不齐：信息卡上「已调整」现在与同一行的徽章是同一款胶囊；信息卡那行按下去的反馈改回与全 app 一致的玻璃缩放（不再是水波纹）\n\n'
    'v0.8.1\n'
    '· 日历上可以单独改某一天的班次了：点底栏那行班次，或长按格子拖选一段日子，就能给这几天单独指定班次（请假、跟同事调班都行），不改整套排班\n'
    '· 被单独改过的那天，格子上有个小圆点，信息卡上写着「已调整」；选择层里可以一键「恢复轮转」\n'
    '· 编辑排班不再重建班次定义，改方案名不会影响已设置的按天调整\n\n'
    'v0.8.0\n'
    '· 正式稳定版，归纳 0.7.1 到 0.7.5 的全部更新\n'
    '· 小米机型锁屏 / 后台弹出响铃界面 —— 现在真的可以了：真因是 MIUI 把「后台弹出界面」单独设成一项权限，不开时系统会静默拒绝从后台拉起界面（连通知那条全屏通道也一起拒），表现就是闹钟只响、不弹。实测两项都开之后：退到后台会自动拉回前台，锁屏会点亮屏幕并顶掉锁屏\n'
    '· 重启手机后闹钟与待办提醒都不再丢：排定时落盘一份清单，开机后自动排回去（重复的顺延到下一次；关机期间已经错过的不补响、也不补发提醒）\n'
    '· 修掉一个隐私隐患：关掉响铃界面后，App 主界面会留在锁屏上（锁屏下能直接看到并操作）；现在响铃一停就把锁屏盖回来，响铃期间也屏蔽了系统返回手势\n'
    '· 权限页重做：分组改成「基础提醒 / 弹出响铃界面 / 后台与开机」，每行说明改成「不开会怎样」；原来那行「后台弹出界面」其实是 Android 的「显示悬浮窗」（中文名套错了小米的说法），已正名；小米机型新增「后台弹出界面（小米）」与「锁屏显示（小米）」两行引导\n'
    '· 日历：格子改成带底色的班次胶囊；选中那天的滑块与格子圆角对齐（此前差一档，四个角会露出底下的卡片）；两个字的简称不再被省略、日期回到居中\n'
    '· 待办：提醒真正生效（此前设了提前提醒也不会有任何反应）；新增「联动闹钟」，到点像班次闹钟一样全屏响铃；日历信息卡上显示当天有几项待办\n'
    '· 修好「添加 / 编辑待办」点了没反应：键盘弹起时弹窗按钮被挤出卡片，现在内容多了会在卡片内滚动\n'
    '· 闹钟铃声可从手机里自选（内置 / 系统 / 自己的音频文件），自选文件损坏或丢失时自动回落到内置铃声，而不是一声不出\n'
    '· 修好「关掉闹钟后重新进入 App，响铃界面又弹一次、而且没有声音」：界面被一个陈旧的暂存值唤醒，实际上根本没有闹钟在响\n';
const String _changelogEn = 'v0.8.9\n'
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
    '· The reason: the three old layouts had to stretch across seven possible heights, so raising or squashing the widget stretched the row height and left the cells large and empty. Each height now has a layout that fits it\n\n'
    'v0.8.5\n'
    '· Fixed the missing marker on the large widget\'s "today" cell: its date now uses the accent colour and bold, matching how the app\'s own calendar marks today (the marker was dropped along the way, so the cell looked like every other one)\n'
    '· Fixed the widget still scheduling its once-a-day refresh in the background after you removed it — with no widget on the home screen, the next refresh is no longer scheduled\n'
    '· Fixed the small widget losing its shift name, date, colour bar and dividers for good once "no schedule yet" turned into a real schedule — they show up again now\n'
    '· Internal: two more tests (a 24-hour shift spanning midnight, and a per-day override reaching the widget snapshot), plus an ellipsis for one overlong label\n\n'
    'v0.8.4\n'
    '· New home screen widget: small / medium / large, showing today, the next three days or a whole week of shifts at a glance\n'
    '· It flips over the day automatically, and follows any change you make to your schedule in the app right away\n'
    '· Tap a day on the widget to jump straight to that date in the calendar\n'
    '· On Xiaomi / HyperOS devices the widget lives under "Apps that support widgets" → "Android widgets" (long-press an empty spot on the home screen → Add widgets); not seeing it there does not mean the feature failed\n\n'
    'v0.8.3\n'
    '· Reworked the "Adjust shift" sheet: the title is no longer centred, the rows are tighter, the colour dot now matches the info card at 12dp, and "Restore rotation" sits below a divider instead of looking like a fifth shift\n'
    '· In a small window (under 480dp tall) the calendar now shows only today\'s info card and no grid — at that size you cannot really read both. The card gained the "Shift changed" badge, so an overridden day stays visible there too\n'
    '· "Adjusted" is now "Shift changed" (it reads right for both a day off and a swap)\n'
    '· Fixed shift names wrapping one character per line in a narrow sheet, and the colour dot being clipped to a half-circle in landscape\n\n'
    'v0.8.2\n'
    '· Added haptic feedback: a light buzz when you flip a switch, make a selection or confirm a delete, and a tick per day as you long-press and drag to select a range. Turn it off under Me → Appearance\n'
    '· Fixed a couple of alignment details: "Adjusted" on the info card now uses the same capsule as the badges on its row, and the info card\'s row taps use the app-wide glass scale again (no longer a ripple)\n\n'
    'v0.8.1\n'
    '· You can now override a single day\'s shift on the calendar: tap the shift row in the bottom bar, or long-press a cell and drag to select a range of days, to give just those days a shift of their own (a day off, or swapping with a colleague) without changing the whole schedule\n'
    '· A day you have overridden carries a small dot in the grid and reads "Adjusted" on the info card; the picker sheet offers a one-tap "Restore rotation"\n'
    '· Editing a schedule no longer rebuilds its shift definitions, so renaming a schedule leaves your per-day overrides intact\n\n'
    'v0.8.0\n'
    '· Stable release — merges everything from 0.7.1 through 0.7.5\n'
    '· Xiaomi devices can now genuinely pop up the alarm screen over the lock screen: the real cause turned out to be a Xiaomi-private permission ("Open new windows while running in the background"). With it off, MIUI silently refuses to launch the UI from the background — the notification\'s full-screen channel is blocked along with it — so the alarm rings with nothing to show. With that toggle and "Show on Lock screen" both on, the app pulls itself back to the front from the background, and lights up and dismisses the lock screen\n'
    '· Alarms and todo reminders now survive a reboot: a persisted list lets them be re-scheduled right after boot (repeating alarms roll forward to their next occurrence; anything missed while the phone was off is neither replayed nor re-sent)\n'
    '· Fixed a privacy hole: after dismissing an alarm the app\'s main UI stayed on top of the lock screen, where it could be read and operated. It now hands the lock screen back, and the ringing screen blocks the system back gesture\n'
    '· Permissions page reworked: grouped into "Core alerts / Pop up the alarm screen / Background & boot", each row now says what breaks without it, the mislabelled "Display over other apps" row was renamed, and Xiaomi devices get two extra guided rows\n'
    '· Calendar: cells became tinted shift chips; the selection block now matches the cell\'s corner radius (they differed by one step, letting the cell show through at all four corners); two-character abbreviations are no longer truncated and the date is centred again\n'
    '· Todos: reminders actually fire now (setting one previously did nothing at all); a todo can ring as an alarm like a shift does; the calendar\'s info card shows how many todos the day has\n'
    '· Fixed "Add / Save" doing nothing in the todo dialogs: with the keyboard up the buttons were pushed out of the card; the content now scrolls inside it\n'
    '· Alarm sounds can be picked from your phone (built-in / system / your own audio file), falling back to the built-in one if the file is damaged or missing instead of going silent\n'
    '· Fixed the ringing screen popping up a second time — and silently — when you reopened the app after dismissing an alarm: the screen had been woken by a stale value while nothing was actually ringing\n';

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
