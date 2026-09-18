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

const String _changelogZh = 'v0.8.5\n'
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
    '· 修好「关掉闹钟后重新进入 App，响铃界面又弹一次、而且没有声音」：界面被一个陈旧的暂存值唤醒，实际上根本没有闹钟在响\n\n'
    'v0.7.5\n'
    '· 修好「关掉响铃界面后重新进入 App，响铃界面又弹一次、而且没有声音」：根因是热启动那条路把闹钟标签留在了原生侧没人清，下一次 App 界面重建时被当成一个新闹钟读了出来 —— 界面被一个陈旧的值唤醒，而根本没有闹钟在响\n'
    '· 重启手机后闹钟不再丢：此前重启会清空系统里排定的闹钟，要等你下次打开 App 才会重排。现在多了一份落盘的闹钟清单，开机后自动把闹钟排回去（重复的顺延到下一次；关机期间已经错过的一次性闹钟不会补响）\n'
    '· 内部：视觉工装新增「向下滚动后」的图 —— 首屏之下的内容（权限卡就是其中之一）此前从来没被拍过，上一版那行名不副实的「后台弹出界面」正是这样活下来的\n\n'
    'v0.7.4\n'
    '· 修好一个隐患：关掉响铃界面之后，App 主界面会留在锁屏上（锁屏下能直接看到并操作 App 内容）。原因是「可以盖在锁屏上」这个状态只有打开、从来没撤回过 —— 现在响铃一停就撤销，关掉闹钟回到的就是锁屏\n'
    '· 修好「日历里选中那天的滑块没把格子盖住」：滑块与格子的圆角差了一档（22 与 16），四个角各露出一条底下的卡片。现在两者同源，并加了一条测试钉着它们相等\n'
    '· 响铃界面屏蔽系统返回手势：此前响铃时一次返回就会退回主界面（锁屏下等于把 App 内容露出来），现在只保留「上滑关闭」与「再睡一会」两个出口\n'
    '· 权限页正名：「后台弹出界面」那一行其实是 Android 的「显示悬浮窗」权限，名字套用了小米的说法、名不副实；现在改叫「显示悬浮窗」，与英文界面一致\n'
    '· 权限页新增「后台弹出界面（小米）」一行（仅小米机型显示），一键跳到系统的应用权限页。这一项不开的话，闹钟到点只会响、不会弹出响铃界面 —— 它是小米私有的权限，此前中文名的误会让人以为已经开过了\n'
    '· 使用帮助的权限一节同步写清小米机型要额外开的两项\n\n'
    'v0.7.3\n'
    '· 修好「添加待办」「编辑待办」点了没反应：键盘弹起时，弹窗内容把底部的「添加 / 保存」按钮挤出了卡片 —— 按钮还画在屏幕上，却已经点不到了，手指落下去穿到遮罩上，于是弹窗关掉、什么都没存。现在内容多了会在卡片内滚动，底部按钮永远点得到\n'
    '· 日历格子：班次胶囊再收一档（字号小一档、内边距收窄，并给左右各留一点边距），两个字的简称不再贴住格子边缘，也不会碰到选中那格的滑块\n'
    '· 待办与自定义闹钟列表的删除键改成紧凑形态：只剩图标、平时中性色、按下才转红。此前用的是 48pt 大红圆，那是给「一屏的主删除动作」准备的，一屏几行挂满红圈既盖过内容也像一排警报\n'
    '· 弹窗内容区此前用「猜一个高度上限」的写法给内容留空间，实际根本没生效（在纵向排布里拿到的是无穷高度）—— 这就是上面第一条的根因，现在改成按剩余空间滚动\n\n'
    'v0.7.2\n'
    '· 日历格子：班次的字号调小一档；两个字的简称（如「上夜」「下夜」）不再被省略成「上…」，系统字号放大时也不会整串字消失\n'
    '· 日历格子：日期回到居中。此前它贴在左上角，会蹭到格子的圆角外、看起来像溢出了格子（班组多的方案上最明显）\n'
    '· 修好「编辑待办事项」弹窗里的提醒：此前点它只会在「不设 / 15 分钟」两档之间跳、弹不出选择界面（同一个弹窗在「添加待办事项」里是好的）\n'
    '· 待办新增联动闹钟开关：打开后到点像班次闹钟一样全屏响铃，关掉则只弹一条通知（二选一）；响铃界面会显示这条待办的日期与时间，不用猜是什么事\n'
    '· 待办列表里开了联动闹钟的那条带一个小铃铛图标，不用点进去就知道哪条会响\n'
    '· 内部：两个待办弹窗的字段合成一份实现（v0.7.1 就是两处各写一遍，才漏改了编辑那个）\n\n';
const String _changelogEn = 'v0.8.5\n'
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
    '· Fixed the ringing screen popping up a second time — and silently — when you reopened the app after dismissing an alarm: the screen had been woken by a stale value while nothing was actually ringing\n\n'
    'v0.7.5\n'
    '· Fixed the ringing screen popping up a second time — and silently — when you reopened the app after dismissing an alarm: the warm-start path left the alarm label behind on the native side with nobody to clear it, so the next time the app\'s UI was recreated it was read back as a brand-new alarm. Nothing was ringing; the screen had just been woken by a stale value\n'
    '· Alarms now survive a reboot: restarting the phone used to wipe every scheduled alarm, and only opening the app put them back. A persisted alarm list now lets the app re-schedule everything right after boot (repeating alarms roll forward to their next occurrence; one-shot alarms missed while the phone was off are not replayed)\n'
    '· Internal: the visual harness gained a "scrolled down" image — content below the fold (the permissions card among it) had never been photographed, which is how last release\'s mislabelled row survived so long\n\n'
    'v0.7.4\n'
    '· Fixed a privacy hole: after you dismissed the ringing screen, the app\'s main UI stayed on top of the lock screen, where anyone could read and operate it. The "show over the lock screen" state was only ever switched on and never released — it is now released the moment the alarm stops, so dismissing an alarm lands you back on the lock screen\n'
    '· Fixed the calendar selection block not covering the day cell: the block and the cell used different corner radii (22 vs 16), leaving a sliver of the cell showing at each of the four corners. Both now share one source, with a test pinning them together\n'
    '· The ringing screen now blocks the system back gesture: one back press used to drop you into the main UI (which, on the lock screen, means exposing the app\'s content). Only "slide to dismiss" and "snooze" remain\n'
    '· Permissions page renamed: the row labelled "后台弹出界面" was actually Android\'s "Display over other apps" — it borrowed MIUI\'s wording, which made it look like the MIUI toggle was already covered. The English label was right all along; the Chinese one now matches it\n'
    '· New "Background pop-up (MIUI)" row on the permissions page (Xiaomi devices only), jumping straight to the system app-permission page. With that toggle off, an alarm only rings and never pops up its screen — it is a Xiaomi-private permission, and the mislabelled row above is why it looked enabled\n'
    '· The permissions section of the usage guide now spells out the two extra toggles Xiaomi devices need\n\n'
    'v0.7.3\n'
    '· Fixed "Add todo" and "Save" in the edit dialog doing nothing: with the keyboard up, the dialog\'s content pushed the Add / Save buttons out of the panel — they were still drawn on screen but no longer tappable, so your finger landed on the scrim, the dialog closed and nothing was saved. The content now scrolls inside the card and the buttons are always reachable\n'
    '· Calendar cells: the shift chip is one step narrower again (smaller label, tighter padding, plus a small margin on each side), so two-character abbreviations no longer touch the cell edge — nor the selection block\n'
    '· Delete buttons in the todo and custom-alarm lists are now the compact form: icon only, neutral colour, turning red only while pressed. The 48pt red circle is meant for a screen\'s primary delete action; a screenful of them buried the content and read as a row of alarms\n'
    '· The dialog content area used to guess a height budget that never took effect (it receives an unbounded height in a column) — that was the root cause of the first item above; it now scrolls into whatever space is left\n\n'
    'v0.7.2\n'
    '· Calendar cells: the shift label is one step smaller, and two-character abbreviations (like "上夜" / "下夜") are no longer shortened to "上…" — nor do they vanish entirely when the system font is enlarged\n'
    '· Calendar cells: the date is centred again. It used to sit in the top-left corner, where it collided with the cell\'s rounded corner and looked like it spilled out of the cell (most visible on schedules with many crews)\n'
    '· Fixed the reminder row in the Edit todo dialog: it only toggled between "none" and "15 min ahead" instead of opening the picker (the same row works in Add todo)\n'
    '· Todos gained a Ring as alarm switch: when on, the todo rings full-screen like a shift alarm at its time; when off it posts a notification only (either/or). The ringing screen shows the todo\'s date and time, so you know what it is about\n'
    '· Todos that ring as an alarm carry a small bell icon in the list, so you can tell which ones will ring without opening them\n'
    '· Internal: the two todo dialogs now share one implementation (v0.7.1 had them written twice, which is how the edit dialog got missed)\n\n';

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
