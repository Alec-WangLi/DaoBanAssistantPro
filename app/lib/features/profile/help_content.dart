import '../../core/l10n.dart';

/// 《使用帮助》第二层（「遇到问题怎么解决」）的全部内容。
///
/// 三条规矩，改之前先读：
///
/// 1. **按用户的诉求排，不按功能块排。** 用户是带着一句话来的
///    （「我这个月跟下个月不一样」），不是带着模块名来的 —— 按模块分的目录
///    装不下这类问题（「每月排班不一样」的答案一半在编辑页、一半在排班管理页）。
/// 2. **问句用用户的说法，不用我们的术语。** 「零点班配 23:00，到底响在哪天」
///    是用户会问的；「`alarmDayAnchor` 的落点档位」不是。
/// 3. **每条自己把话说完，不许互相指路**（「详见『临时改班』那一条」这种）。
///    互相指路会把一份清单变成一张网，点两下就迷路。
///
/// **文案为什么用 `L10nText` 而不是 `L10n.xxx` getter**：这是一整块内容、
/// 三十来条，写成 getter 是六十多个只有一行的方法；而 `L10nText` 本来就是仓库
/// 为「数据层持有文案」准备的东西（见 `domain/shift_templates.dart` 的用法）。
///
/// 条目里出现数字的（闹钟条数、天数、档位），一律对着实现常量核 ——
/// `test/help_content_test.dart` 里有一条用例钉着闹钟那个（它真漂过）。
typedef HelpFaqItem = ({L10nText question, L10nText answer});

/// 一组里的一个小节；`heading` 为 null 时不画小节标题（「它不对劲」那一组
/// 不分小节）。
typedef HelpFaqSection = ({L10nText? heading, List<HelpFaqItem> items});

/// 页面级的一组。顺序即渲染顺序。
typedef HelpFaqGroup = ({L10nText title, List<HelpFaqSection> sections});

const List<HelpFaqGroup> helpFaqGroups = [
  (
    title: L10nText('我想办一件事', 'I want to…'),
    sections: [
      (
        heading: L10nText('排班', 'Shifts'),
        items: [
          (
            question: L10nText('我这个月跟下个月不一样', 'This month is not the same as next month'),
            answer: L10nText(
              '编辑排班页最上面那个分段器切到「按月」，然后按当月排；也可以去「我的 → 排班管理 → 排班时段」给不同的月份指定不同的班表。',
              'Switch the segmented control at the top of the schedule editor to "By month", then set the month up day by day. Or open Me → Schedule management → Schedule timeline and give different months different schedules.',
            ),
          ),
          (
            question: L10nText('我们跟着法定节假日休，没有固定轮转',
                'We follow the public holidays, there is no fixed rotation'),
            answer: L10nText(
              '编辑排班页最下面打开「跟随法定节假日（无班次）」。这样日历上只画日期和农历，法定节假日照旧标红。',
              'Turn on "Follow legal holidays (no shifts)" at the bottom of the schedule editor. The calendar then shows only dates and lunar days; public holidays are still marked in red.',
            ),
          ),
          (
            question: L10nText('我们上 12 休 24 这种不规则的',
                'Our pattern is uneven, like 12 hours on and 24 off'),
            answer: L10nText(
              '用「周期设置」，一天一天把班排出来。周期长度可以拉到 60 天，什么样的轮法都排得下。',
              'Use Cycle and lay the shifts out day by day. A cycle can be up to 60 days long, so any rotation fits.',
            ),
          ),
          (
            question: L10nText('想给班次换个颜色', 'I want a different colour for a shift'),
            answer: L10nText(
              '编辑排班页上，班次卡里那个色点点一下就是颜色盘：16 颗现成的颜色，也可以自己调 —— 拖色相条和方盘，或者直接填十六进制，下面两颗日历小样会跟着变；选好点「确定」。',
              'On a shift card in the schedule editor, tap the colour dot to open the palette: 16 ready-made colours, or mix your own by dragging the hue bar and the square, or typing a hex value. The two little calendar samples update as you go — tap Done when it looks right.',
            ),
          ),
          (
            question: L10nText('我们班组从哪天开始、怎么跟别的班组错开',
                'When does my crew start, and how do the crews offset each other'),
            answer: L10nText(
              '「班组设置」里填每个班组从哪天起算。填的起始日跟周期长度对不上时会提示「撞班」，那里有一个按钮可以按周期长度自动均分。',
              'Under "Crews" set the day each crew starts from. If a start date does not line up with the cycle length the app warns about clashing days, and there is a button to spread the crews evenly across the cycle.',
            ),
          ),
          (
            question: L10nText('我想看别的班组那天上什么班',
                'I want to see what the other crews are on'),
            answer: L10nText(
              '也是在「班组设置」里给每个班组起个名字，日历那一栏就会把它们列出来。',
              'Also under "Crews" — give each crew a name and the calendar will list them for the day you are looking at.',
            ),
          ),
          (
            question: L10nText('我这套排班只用一段时间，之后换另一套',
                'One schedule only covers a stretch of time, then another takes over'),
            answer: L10nText(
              '「我的 → 排班管理 → 排班时段」加两段，各指定用哪套班表。',
              'Open Me → Schedule management → Schedule timeline and add two periods, each naming the schedule it uses.',
            ),
          ),
          (
            question: L10nText('这套排班我以后还要用', 'I will want this schedule again later'),
            answer: L10nText(
              '编辑排班页右上角那个书签按钮，「存为模板」。下次新建排班时它排在最前面的「我的模板」里。',
              'Use the bookmark button at the top right of the schedule editor — "Save as template". Next time you create a schedule it sits at the top, under "My templates".',
            ),
          ),
        ],
      ),
      (
        heading: L10nText('临时改班', 'One-off changes'),
        items: [
          (
            question: L10nText('这天我请假、或者跟同事换了班',
                'I am taking a day off, or swapping with a colleague'),
            answer: L10nText(
              '在日历上点底栏那张信息卡里的班次那一行；要改连着好几天，就长按某一天往旁边拖，把一段日子圈出来。',
              'In the calendar, tap the shift row on the info card at the bottom. To change several days in a row, long-press one day and drag sideways to ring a stretch of dates.',
            ),
          ),
          (
            question: L10nText('改错了想改回去', 'I changed the wrong day and want it back'),
            answer: L10nText(
              '再点一次那几天，选择层最上面有「恢复轮转」。',
              'Tap those days again — "Restore rotation" is at the top of the picker.',
            ),
          ),
        ],
      ),
      (
        heading: L10nText('闹钟', 'Alarms'),
        items: [
          (
            question: L10nText('一个班想响两次（起床一次、出门一次）',
                'I want two alarms for one shift'),
            answer: L10nText(
              '在编辑排班页那一班的卡片里，点「添加闹钟」。一个班最多配 10 条，每条可以起名字。',
              'On that shift\'s card in the schedule editor, tap "Add alarm". A shift can carry up to 10 alarms, and each one can have a name.',
            ),
          ),
          (
            question: L10nText('夜班要提前叫我', 'The night shift needs an earlier wake-up'),
            answer: L10nText(
              '也是在那张卡片里，把闹钟的钟点填成你要的时间就行。',
              'Same card — just set the alarm\'s time to whatever you want.',
            ),
          ),
          (
            question: L10nText('零点班配 23:00，到底响在哪天',
                'A midnight shift with a 23:00 alarm — which day does it ring on'),
            answer: L10nText(
              '列表里写着「前一天」或「次日」，那是按上班时间算出来的，不用自己判断。',
              'The list says "day before" or "next day" — that is worked out from the shift times, so you do not have to reason about it.',
            ),
          ),
          (
            question: L10nText('哪天我不想被吵', 'I do not want to be woken on a particular day'),
            answer: L10nText(
              '闹钟页列着未来 30 天，每一天都能单独关掉。',
              'The alarm page lists the next 30 days, and each day can be switched off on its own.',
            ),
          ),
          (
            question: L10nText('早上想多躺十分钟', 'I want ten more minutes in the morning'),
            answer: L10nText(
              '「我的 → 闹钟 → 贪睡时长」，1 / 5 / 10 / 15 / 20 / 30 分钟。',
              'Me → Alarm → Snooze length — 1, 5, 10, 15, 20 or 30 minutes.',
            ),
          ),
          (
            question: L10nText('想用自己手机里的歌、或者只想要震动',
                'I want my own music as the alarm, or just vibration'),
            answer: L10nText(
              '「我的 → 闹钟 → 闹钟铃声」，可以选内置、系统铃声，或者从手机里挑一首；不想出声就选「仅震动」。',
              'Me → Alarm → Alarm ringtone — pick a built-in or system ringtone, or choose a track from your phone. For no sound at all, pick "Vibrate only".',
            ),
          ),
          (
            question: L10nText('睡前想确认明天几点响', 'I want to check tonight what time it rings tomorrow'),
            answer: L10nText(
              '闹钟页最上面那份「未来 30 天」的列表，按天列着。',
              'The "Shift alarms in next 30 days" list at the top of the alarm page lays it out day by day.',
            ),
          ),
        ],
      ),
      (
        heading: L10nText('待办', 'Todo'),
        items: [
          (
            question: L10nText('明天交班要提醒我', 'Remind me about the handover tomorrow'),
            answer: L10nText(
              '待办页右下角新建一条，填上时间，再把「提醒」设成提前多久。到点会弹通知。',
              'Add one from the button at the bottom right of the todo page, set its time, then set "Remind" to how far ahead you want. You get a notification at that moment.',
            ),
          ),
          (
            question: L10nText('每周三开会，不想每周手填一遍',
                'A meeting every Wednesday — I do not want to type it in each week'),
            answer: L10nText(
              '新建待办时把「重复」选上，可以按天、按星期几（能多选，比如周一三五）、按每月哪几天（比如 1 号和 15 号）、或者按班次（比如每次上夜班）自动出现。建好之后想改：待办页右上角的「重复待办」，点那一条就能改标题和规则。',
              'When you create the todo, turn on "Repeating" — it can repeat daily, on any chosen weekdays, on several days of the month (say the 1st and 15th), or on chosen shifts (say every night shift). To change one later: open "Repeating" at the top right of the todo page and tap it.',
            ),
          ),
          (
            question: L10nText('每次上夜班都要提醒我带工牌',
                'Remind me to bring my badge on every night shift'),
            answer: L10nText(
              '新建待办时把「重复」选到「按班次」，勾上夜班（可以多选）。它按班次名字匹配：换了排班表，只要新表里还有同名班次就继续生效；名字对不上时，「重复待办」面板会明确写出来。',
              'Choose "By shift" as the repeat, then tick the night shift (several allowed). It matches by shift name — after switching schedules it keeps working as long as the new one has the same name; if not, the Repeating panel says so.',
            ),
          ),
          (
            question: L10nText('到点只想要通知、不要全屏闹钟',
                'I want a notification, not a full-screen alarm'),
            answer: L10nText(
              '那条待办里的「联动闹钟」关掉就行；开着的话它会像班次闹钟一样全屏响。',
              'Turn off "Linked alarm" on that todo. With it on, it rings full-screen exactly like a shift alarm.',
            ),
          ),
          (
            question: L10nText('做完的不想在列表里碍眼', 'Done items clutter the list'),
            answer: L10nText(
              '勾掉之后它会自己收进列表最下面那个「已完成 N 条」里。',
              'Tick one off and it drops into the "completed" section at the bottom of the list by itself.',
            ),
          ),
        ],
      ),
      (
        heading: L10nText('外观与设置', 'Look and settings'),
        items: [
          (
            question: L10nText('字太小', 'The text is too small'),
            answer: L10nText(
              '「我的 → 外观 → 字体大小」，四档，App 自己管，不跟系统走。',
              'Me → Appearance → Text size. Four steps, managed by the app rather than by the system setting.',
            ),
          ),
          (
            question: L10nText('想换深色 / 主题色 / 想用英文',
                'I want dark mode, another accent colour, or English'),
            answer: L10nText(
              '也在「我的 → 外观」。',
              'Also Me → Appearance.',
            ),
          ),
          (
            question: L10nText('手机发热、费电', 'The phone gets warm and the battery drains'),
            answer: L10nText(
              '「我的 → 外观」里把「液态玻璃」关掉。那个效果是最好看也最费电的一项。',
              'Under Me → Appearance, turn "Liquid glass" off. It is the nicest-looking effect and also the most expensive one.',
            ),
          ),
          (
            question: L10nText('想从头来一遍', 'I want to start over'),
            answer: L10nText(
              '「我的 → 数据 → 清空重置」，会回到刚装好的样子。',
              'Me → Data → Clear & reset takes the app back to how it looked when you first installed it.',
            ),
          ),
          (
            question: L10nText('换了手机，怎么把排班搬过去',
                'I got a new phone — how do I move my schedule over'),
            answer: L10nText(
              '目前不支持。数据只存在这台手机上，没有云同步也没有导出，换手机要重新排一遍。',
              'Not supported yet. Everything lives on this phone only — there is no cloud sync and no export — so a new phone means setting it up again.',
            ),
          ),
        ],
      ),
    ],
  ),
  (
    title: L10nText('它不对劲', 'Something looks wrong'),
    sections: [
      (
        heading: null,
        items: [
          (
            question: L10nText('闹钟到点只响、不弹响铃界面',
                'The alarm rings but no full-screen alarm appears'),
            answer: L10nText(
              '去「我的 → 权限」逐项开齐。小米手机还要单独开「后台弹出界面」和「锁屏显示」这两项，不开的话系统会拦掉响铃界面。',
              'Open Me → Permissions and turn everything on. On Xiaomi phones also turn on "Background pop-up (MIUI)" and "Show on Lock screen (MIUI)" — without those the system blocks the alarm screen.',
            ),
          ),
          (
            question: L10nText('重启手机后闹钟没恢复', 'Alarms did not come back after a restart'),
            answer: L10nText(
              '「我的 → 权限」里的「自启动」没开。开着它，重启后闹钟才排得回来。',
              '"Auto-start" under Me → Permissions is off. With it on, the alarms are scheduled again after a restart.',
            ),
          ),
          (
            question: L10nText('桌面小组件还是升级前的样子',
                'The home-screen widget still shows the old thing'),
            answer: L10nText(
              '打开一次 App 就好。卡片上的班次是上次打开 App 时算好的。',
              'Open the app once. The shifts on the card were worked out the last time the app ran.',
            ),
          ),
          (
            question: L10nText('小米桌面找不到小组件在哪加',
                'Can\'t find where to add the widget on a Xiaomi phone'),
            answer: L10nText(
              '长按桌面空白处 → 添加小部件 → 「支持小部件的应用」→「安卓小部件」。小米把它们藏在二级分类里。',
              'Long-press an empty spot on the home screen → Add widgets → "Apps that support widgets" → "Android widgets". Xiaomi hides them one level down.',
            ),
          ),
          (
            question: L10nText('日历上整月没有班次 / 某几天突然没了',
                'A whole month shows no shifts, or a few days suddenly went empty'),
            answer: L10nText(
              '去「我的 → 排班管理 → 排班时段」，看那几天归哪套班表。也可能是那段日子被设成了「无」。',
              'Open Me → Schedule management → Schedule timeline and see which schedule covers those days. It may also be that those dates were set to "none".',
            ),
          ),
          (
            question: L10nText('横屏、平板、车机上日历变成了左右两栏',
                'On a tablet, car screen or in landscape the calendar splits into two columns'),
            answer: L10nText(
              '这是正常的：屏幕够宽时左边是日期网格、右边是当天详情；窗口很矮（高不到 480dp）时只显示当天那张卡，因为那个尺寸下网格看不清。',
              'That is intended: on a wide screen the month grid sits on the left and the day\'s details on the right. In a very short window (under 480dp tall) only the day card shows, because the grid is unreadable at that size.',
            ),
          ),
        ],
      ),
    ],
  ),
];
