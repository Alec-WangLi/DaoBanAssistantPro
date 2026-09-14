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

const String _changelogZh = 'v0.8.0\n'
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
    '· 内部：两个待办弹窗的字段合成一份实现（v0.7.1 就是两处各写一遍，才漏改了编辑那个）\n\n'
    'v0.7.1\n'
    '· 日历格子重做：班次变成带底色的胶囊，一眼就能扫出哪天是什么班；日期收成左上角的小字，农历留在底部。格子里的字现在跟着格子高度一起放大（此前格子会长高、字不变，格子里空着一大块、字显得小）\n'
    '· 选中那天的班次胶囊变成实心，滑块落在哪格一眼就能锁定\n'
    '· 「跟随法定节假日（无班次）」那套方案保持原来的居中排布，不受上面两条影响\n'
    '· 闹钟铃声现在可以从手机里挑自己的音频了（此前只能选内置与系统的）。选中后会把文件复制到应用内部保存，换回内置或系统铃声时自动清掉，不会留下占地方的副本；自选文件万一损坏或丢失，会自动回落到内置铃声接着响，而不是一声不出\n'
    '· 修好待办提醒一直没生效的问题：此前「提前提醒」设了也只是在列表里显示一行字，到点什么都不会发生。现在会真的在通知栏弹出提醒（标题是待办名，点开直接进待办页）；增删改待办后立刻重排，不必等下次开 App\n'
    '· 提醒档位新增「准时」，并可以选提前 5 分钟 / 15 分钟 / 30 分钟 / 1 小时 / 1 天（此前只有「提前 15 分钟」和「不设」两档）\n'
    '· 日历当天信息卡上会显示「N 项待办」，不用翻到待办页就知道今天有事\n'
    '· 顺带修好一个一直存在的问题：日历格子里「今天」的日期从来没加粗过\n'
    '· 铃声选择器标出当前用的是哪一个，不用再靠记忆\n\n'
    'v0.7.0\n'
    '· 正式稳定版（归纳 0.6.1~0.6.13 全部更新）\n'
    '· 应用图标重画为「日历 + 换班箭头」，并补上 Android 自适应图标 —— 图标从此跟随系统的形状与配色（含 Android 13+ 的「主题图标」），在会统一图标形状的启动器上不再被缩到一块白底上、显得又小又淡\n'
    '· 全 App 的排版、间距与图标收敛到一套统一的设计规范：同一个用途的字号、字重、行高、透明度、间距从此只有一个来源，不会再各自跑偏。外观上的变化很轻，14 处字号、约 12 处字重各只动一档\n'
    '· 横屏、平板/车机等宽屏、小米小窗三种形态全面适配：日历在宽屏改为左右分栏，小窗按实测尺寸（200×400）重做，各页在矮屏下自动收紧，正文限宽居中不再横向拉满\n'
    '· 日历底栏信息卡连续修整：高度按本月实际最满的一天实测（不再写死），左侧色条与卡片对齐、底栏留白收窄、系统字号放大也不再裁字；日期网格的最后一行不再被卡片压住\n'
    '· 法定节假日徽章改用淡染底色 + 描边，节日名对比度达到无障碍标准；调休上班日带「班」标记\n'
    '· 英文界面大幅补完：月份标题、日期格式、班次简称、倒班方式模板与分组标题、从模板新建的方案与班次名都按当前语言生成，模板可用英文关键词搜索\n'
    '· 排班编辑器的周期设置改为行内直接点选班次（不再弹下拉），编辑界面的字号与全 App 统一\n'
    '· 响铃界面：「上滑关闭」滑块加宽（轨道 56→72，手指真正能拖中的范围放宽到 112），并修好横屏与小窗下会溢出画面的问题\n'
    '· 修好「我的 → 关于」里的版本号（从 v0.6.5 起就没再更新过），以及「检查更新」给已装版本挂「下载」按钮\n'
    '· 内部：新增设计守门测试（界面层写死字号 / 字重 / 圆角 / 图标尺寸等即测试失败）；应用图标改为全脚本生成\n\n'
    'v0.6.13\n'
    '· 应用图标重画：变成「日历 + 换班箭头」。此前只有一张方图，在会统一图标形状的启动器上会被缩到一块白底上，显得又小又淡；现在补上了 Android 自适应图标（含 Android 13+「主题图标」用的单色层），图标能跟着系统的形状与配色走\n'
    '· 响铃界面的「上滑关闭」滑块加宽：轨道 56→72，手指真正能拖中的范围放宽到 112，不用再瞄着戳\n'
    '· 修好响铃界面在手机横屏、以及 200×400 小窗下会溢出画面的问题（小窗里时钟会折成两行，把整列顶出屏幕）\n'
    '· 内部整理：通知小图标改回正确的 drawable（此前指向启动器图标，不是通知该用的资源）\n\n'
    'v0.6.12\n'
    '· 底部导航的四个图标调大一档，在胶囊里更醒目、与文字的比例更接近常见底栏\n'
    '· 内部整理：把设计规范里几处说法与实际不符的地方改正（导航图标的尺寸档位、小尺寸元素的圆角规则）\n\n'
    'v0.6.11\n'
    '· 全 App 的排版、间距与图标收敛到一套统一的设计规范：同一个用途的字号、字重、行高、透明度、间距从此只有一个来源，不会再各自跑偏\n'
    '· 次要文字的透明度此前散着 0.45 / 0.5 / 0.55 / 0.6 四种，现在统一到两档（常规 0.62、更淡的 0.35），同一个层级在哪个页面看都一样\n'
    '· 图标尺寸统一到三档（16 / 20 / 24），不再各处写 14 / 18 / 22 / 28\n'
    '· 卡片圆角由 20 归到 22，与列表行、提示条同档\n'
    '· 外观上的变化很轻：14 处字号、约 12 处字重各只动了一档，其余都只是内部换了写法\n';
const String _changelogEn = 'v0.8.0\n'
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
    '· Internal: the two todo dialogs now share one implementation (v0.7.1 had them written twice, which is how the edit dialog got missed)\n\n'
    'v0.7.1\n'
    '· Calendar cells reworked: each shift is now a filled chip, so you can see at a glance which shift a day is; the date shrinks into the top-left corner and the lunar date stays at the bottom. Cell text now scales with the cell height (previously cells grew taller while the text stayed put, leaving a large empty area and making the text look small)\n'
    '· The selected day\'s shift chip turns solid, so it is obvious where the selection block landed\n'
    '· Schedules set to "follow legal holidays (no shifts)" keep their centred layout, unaffected by the two changes above\n'
    '· The alarm ringtone can now be your own audio file (previously only built-in and system ringtones). The file is copied into the app; switching back to a built-in or system ringtone removes that copy, so no space is wasted. If the file is ever damaged or lost, the alarm falls back to the built-in ringtone instead of ringing silently\n'
    '· Fixed todo reminders never firing: "remind ahead" was only shown as a line of text and did nothing at the time. It now posts a real notification (titled with the todo, tapping it opens the todo list), and reminders are rescheduled the moment you add, edit, complete or delete a todo instead of waiting for the next app launch\n'
    '· New "on time" reminder option, plus 5 / 15 / 30 minutes, 1 hour and 1 day ahead (previously only "15 min ahead" and "none")\n'
    '· The calendar\'s info card now shows "N todos" for the selected day, so you know there is something today without opening the todo list\n'
    '· Also fixed a long-standing issue: today\'s date in the calendar grid was never bolded\n'
    '· The ringtone picker marks which one is currently in use\n\n'
    'v0.7.0\n'
    '· Stable release (consolidating v0.6.1–v0.6.13)\n'
    '· The app icon is redrawn as a calendar with shift-cycle arrows, and now ships an Android adaptive icon — it follows the system\'s shape and tint (including Android 13+ themed icons) instead of being shrunk onto a white plate by launchers that unify icon shapes\n'
    '· Typography, spacing and icons across the app now come from one shared design system: a single source per role for size, weight, line height, opacity and spacing, so they can no longer drift apart. The visible change is subtle — 14 text sizes and about 12 font weights each moved one step\n'
    '· Landscape phones, wide screens (tablets, car head units) and Xiaomi floating windows are all properly supported: the calendar becomes two panes when wide, the floating window was rebuilt around its measured 200×400 size, short screens tighten up automatically, and content is centred with a maximum width instead of stretching\n'
    '· Sustained fixes to the calendar\'s info card: its height is measured against the busiest day of the month (no longer hard-coded), the colour bar lines up with the card, the space beneath is tighter, and enlarged system text no longer clips; the last row of the month grid is no longer hidden behind the card\n'
    '· The legal-holiday badge uses a tinted fill with an outline, and its holiday name now passes the accessibility contrast threshold; makeup workdays carry a "班" mark\n'
    '· The English UI is largely completed: month headings, date formats, shift abbreviations, pattern templates and their group headings, and the schedules and shifts created from a template are all generated in your language, and templates are searchable with English keywords\n'
    '· The schedule editor\'s cycle section now lets you pick a shift inline instead of opening a dropdown, and its typography matches the rest of the app\n'
    '· Ringing screen: the "swipe up to dismiss" slider is wider (track 56 → 72, and the area your finger can grab is 112), and it no longer overflows in landscape or in a small window\n'
    '· Fixed the version number in Me → About (it had not been updated since v0.6.5) and the "Download" button that Check for updates offered for a version you already had\n'
    '· Internal: a design guard test now fails the build when UI code hard-codes sizes, weights, radii or icon sizes; the app icon is generated entirely from a script\n\n'
    'v0.6.13\n'
    '· The app icon is redrawn: a calendar with shift-cycle arrows. It used to be a single square bitmap, which launchers that unify icon shapes would shrink onto a white plate, leaving it small and washed out. It now ships an Android adaptive icon (with a monochrome layer for Android 13+ themed icons), so it follows the system\'s shape and tint\n'
    '· The "swipe up to dismiss" slider on the ringing screen is wider: the visible track goes 56 → 72 and the area your finger can actually grab is 112, so there is nothing to aim at\n'
    '· Fixed the ringing screen overflowing on landscape phones and in 200×400 small windows, where the clock wrapped to two lines and pushed the column off screen\n'
    '· Internal: the notification small icon now points at a proper drawable instead of the launcher icon\n\n'
    'v0.6.12\n'
    '· The four bottom-nav icons are one step larger — more present in the capsule, and closer to the usual tab-bar ratio against their labels\n'
    '· Internal cleanup: corrected a few mismatches between the design spec and the actual code (the nav icon\'s size tier, and the rule for small elements\' corner radius)\n\n'
    'v0.6.11\n'
    '· Typography, spacing and icons across the app now come from one shared design system: a single source per role for size, weight, line height, opacity and spacing, so they can no longer drift apart\n'
    '· Secondary text opacity used to be scattered across four values (0.45 / 0.5 / 0.55 / 0.6). It is now two tiers — 0.62 regular and 0.35 for the faintest — so the same level looks the same on every screen\n'
    '· Icon sizes are down to three steps (16 / 20 / 24) instead of ad-hoc 14 / 18 / 22 / 28\n'
    '· Card corners moved from 20 to 22, matching list rows and the snackbar\n'
    '· The visible change is subtle: 14 text sizes and about 12 font weights each moved one step, and the rest is only a change in how it is written internally\n';

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
