import 'package:intl/intl.dart';

/// 一段双语文案的持有者。
///
/// 用在**数据层需要持有文案**的地方（倒班方式模板）：模板是编译期常量，
/// 定义时不能调 `L10n.t`，只能先把两种语言都存下来、读取时再按当前语言取。
///
/// 英文缺省时**不回退中文** —— 悄悄回退会让漏翻在英文界面上伪装成正常
/// 内容，而缺失本该被测试抓出来。
class L10nText {
  const L10nText(this.zh, this.en);

  final String zh;
  final String en;

  String get value => L10n.isEn ? en : zh;
}

/// 极简多语言：全局 [locale]（'zh' / 'en'），静态 getter 返回对应文案。
class L10n {
  L10n._();

  static String locale = 'zh';
  static bool get isEn => locale == 'en';

  static String t(String zh, String en) => isEn ? en : zh;

  // 底部导航
  static String get navCalendar => t('日历', 'Calendar');
  static String get navAlarm => t('闹钟', 'Alarm');
  static String get navTodo => t('待办', 'Todo');
  static String get navProfile => t('我的', 'Me');

  // 页面标题
  static String get titleAlarm => t('闹钟', 'Alarm');
  static String get titleTodo => t('待办事项', 'Todo List');
  static String get titleProfile => t('我的', 'Me');

  // 「我的」页分区
  static String get sectionAppearance => t('外观', 'Appearance');
  static String get sectionSchedule => t('排班', 'Schedule');
  static String get sectionAlarm => t('闹钟', 'Alarm');
  static String get sectionData => t('数据', 'Data');
  static String get sectionPermission => t('权限', 'Permissions');
  static String get sectionAbout => t('关于', 'About');

  // 权限卡
  static String get permChecking => t('正在检测权限…', 'Checking permissions…');
  static String get permGroupBasic => t('基础提醒', 'Core alerts');
  static String get permGroupFullscreen => t('锁屏全屏响铃', 'Lock-screen fullscreen');
  static String get permGroupBackground => t('后台保活', 'Background reliability');
  static String get permNotif => t('通知权限', 'Notifications');
  static String get permNotifOff => t('未开启时收不到任何提醒', 'No alerts at all when off');
  static String get permExact => t('闹钟和提醒权限', 'Alarms & reminders');
  static String get permExactOff => t('未开启时闹钟可能不准时', 'Alarms may be delayed when off');
  static String get permAutoStart => t('自启动', 'Auto-start');
  static String get permAutoStartHint => t('小米/华为等机型需手动开启', 'Enable manually on MIUI/HyperOS');
  static String get goCheck => t('去查看', 'Check');
  static String get permOverlay => t('后台弹出界面', 'Display over other apps');
  static String get permOverlayHint => t('锁屏时全屏响铃需要', 'Needed for lock-screen fullscreen alarm');
  static String get permFsi => t('全屏通知', 'Full-screen notifications');
  static String get permFsiHint => t('否则只弹一条通知，不弹全屏响铃', 'Otherwise only a notification shows');
  static String get permBattery => t('电池优化', 'Battery optimization');
  static String get permBatteryHint => t('设为「不限制」，否则后台可能不响', 'Set "Unrestricted", or alarms may not fire');
  static String get enabled => t('已开启', 'Enabled');
  static String get goEnable => t('去开启', 'Enable');
  static String get goSettings => t('去设置', 'Settings');

  // 常用按钮
  static String get save => t('保存', 'Save');
  static String get cancel => t('取消', 'Cancel');
  static String get ok => t('知道了', 'Got it');
  static String get add => t('添加', 'Add');
  static String get delete => t('删除', 'Delete');
  static String get copy => t('复制', 'Copy');
  static String get clear => t('清空', 'Clear');
  static String get close => t('关闭', 'Close');
  static String get back => t('返回', 'Back');
  static String get newAlarm => t('新建闹钟', 'New alarm');
  static String get testAlarm => t('测试闹钟（10 秒后响）', 'Test alarm (rings in 10s)');
  static String get testAlarmShort => t('测试闹钟', 'Test alarm');
  static String get selectTime => t('选择时间', 'Select time');
  static String get selectDate => t('选择日期', 'Select date');
  static String get confirm => t('确定', 'OK');

  // 外观
  static String get themeMode => t('主题模式', 'Theme');
  static String get followSystem => t('跟随系统', 'System');
  static String get light => t('浅色', 'Light');
  static String get dark => t('深色', 'Dark');
  static String get accentColor => t('主色调', 'Accent color');
  static String get language => t('语言', 'Language');

  // 「我的」页其他
  static String get scheduleManagement => t('排班管理', 'Schedule management');
  static String get scheduleManagementSubtitle => t('管理、编辑你的排班表', 'Manage and edit your schedules');
  static String get ringtone => t('闹钟铃声', 'Alarm ringtone');
  static String get ringtoneSubtitle => t('选择内置、系统或你的铃声', 'Choose a built-in, system, or your own ringtone');
  static String get clearReset => t('清空重置', 'Clear & reset');
  static String get clearResetSubtitle => t('清空排班与日程，恢复默认四班两倒', 'Clear schedules & events, restore default rotation');
  static String get version => t('版本', 'Version');
  static String get changelog => t('版本更新', "What's new");
  static String get changelogSubtitle => t('查看最近版本的更新内容', 'Release notes for recent versions');
  static String get checkUpdate => t('检查更新', 'Check for update');
  static String get checkUpdateSubtitle => t('获取正式版与测试版', 'Get stable & beta releases');
  static String get alreadyLatest => t('已是最新', 'Up to date');
  static String get updateCheckFailed => t('检查更新失败（网络异常，请稍后再试）', 'Update check failed (network error), try later');
  static String get stableChannel => t('正式版', 'Stable');
  static String get testChannel => t('测试版', 'Beta');
  // 渠道没有发布时的占位。不要复用 `none`（「不设」，说的是「这个可选字段留空」）——
  // 摆在「测试版」后面会读成「App 决定不给你测试版」，而意思是「当前没有」。
  static String get channelNone => t('暂无', 'None yet');
  static String get legalHoliday => t('法定节假日', 'Legal holiday');
  static String get currentVersionHint => t('你手机上安装的版本', 'The version installed on this device');
  static String get stableChannelHint => t('稳定版本，推荐日常使用', 'Stable build, recommended for daily use');
  static String get testChannelHint => t('抢先体验新功能，可能有小问题', 'Early access to new features, may have minor issues');
  static String get download => t('去下载', 'Download');
  static String get downloadingUpdate => t('正在下载新版本', 'Downloading update');
  static String get downloadFailed => t('下载失败，请检查网络后重试', 'Download failed, check your connection and retry');
  static String get jumpToMonth => t('跳转月份', 'Jump to month');
  static String get usageGuide => t('使用帮助', 'Usage guide');
  static String get viewLog => t('查看日志', 'View log');
  static String get viewLogSubtitle => t('排错时把这里的内容复制给我', 'Copy the log here for debugging');
  static String get confirmResetTitle => t('确认清空重置？', 'Clear & reset?');
  static String get confirmResetContent => t('将清空所有排班与日程数据，恢复默认「四班两倒」配置。此操作不可撤销。', 'All schedules and events will be cleared and the default rotation restored. This cannot be undone.');
  static String get confirmResetAction => t('确认清空', 'Clear');
  static String get resetDone => t('已清空并恢复默认排班', 'Cleared and restored default schedule');
  static String get log => t('日志', 'Log');
  static String get noLog => t('（暂无日志）', '(no log)');
  static String get logCopied => t('日志已复制到剪贴板', 'Log copied to clipboard');
  static String get builtinRingtone => t('内置铃声（默认）', 'Built-in (default)');
  static String get builtinRingtoneSubtitle => t('叮咚数字闹钟声', 'Ding-dong digital alarm');
  static String get preview => t('试听', 'Preview');
  static String get noRingtones => t('没有读取到系统铃声，请选择内置铃声', 'No system ringtones found, choose the built-in one');
  static String get setBuiltinRingtone => t('已设为内置铃声', 'Set to built-in ringtone');
  static String get ringtoneSet => t('铃声已设置，下次响铃生效', 'Ringtone set, takes effect next alarm');
  static String get myRingtone => t('我的铃声', 'My ringtone');
  static String get pickRingtoneFromFile => t('从文件中选择…', 'Choose from files…');
  static String get pickRingtonePrivacy => t(
      '选中的音频会被复制到应用内部。不会上传，也不会读取其他文件。',
      'The audio you pick is copied into the app. Nothing is uploaded, and no other file is read.');
  static String get systemRingtones => t('系统铃声', 'System ringtones');
  static String get removeRingtone => t('移除', 'Remove');
  static String get ringtoneFileRemoved => t('已移除自选铃声', 'Custom ringtone removed');
  static String get ringtoneTooLarge => t(
      '这个文件太大了（上限 32 MB），换一个小一点的音频',
      'That file is too large (32 MB max), pick a smaller one');
  static String get ringtoneCopyFailed =>
      t('没能读取这个文件，换一个试试', "Couldn't read that file, try another one");

  // 待办（日程）
  static String get noEvents => t('还没有待办事项，点右下角添加', 'No todos yet, tap + to add');
  static String get addEvent => t('添加待办事项', 'Add todo');
  static String get editEvent => t('编辑待办事项', 'Edit todo');
  static String get title => t('标题', 'Title');
  static String get date => t('日期', 'Date');
  static String get timeOptional => t('时间（可选）', 'Time (optional)');
  static String get advanceRemindOptional => t('提醒（可选）', 'Remind (optional)');
  static String get none => t('不设', 'None');

  /// 「不设」在选择器里的取值。
  ///
  /// 用 -1 而不是 null：选择器靠「返回 null = 用户取消 / 点外面关掉」来判断，
  /// 选项本身不能再是 null，否则「选不设」和「直接关掉」分不开。
  static const int remindNone = -1;

  /// 提醒档位：-1 = 不设，0 = 准时（事件当时提醒），其余为提前的分钟数。
  ///
  /// 「准时」是特意留的一档：只有「不设 / 提前 15 分钟」两档时，不想提前、
  /// 只想在事件当时被叫一下的人只能选「不设」，等于没有提醒。
  static const List<int> remindOptions = [remindNone, 0, 5, 15, 30, 60, 1440];

  /// 提醒档位的显示文案。[v] 取 [remindOptions] 里的值。
  static String remindOptionLabel(int v) {
    if (v < 0) return none;
    if (v == 0) return t('准时', 'On time');
    if (v % 1440 == 0) {
      final d = v ~/ 1440;
      return isEn ? '$d d ahead' : '提前$d天';
    }
    if (v % 60 == 0) {
      final h = v ~/ 60;
      return isEn ? '$h h ahead' : '提前$h小时';
    }
    return isEn ? '$v min ahead' : '提前$v分钟';
  }

  /// 没设时间的待办在通知里显示的时间段。
  static String get allDay => t('全天', 'All day');

  /// 信息卡日期行上的待办提示：只说有几项，不列内容。
  static String todoCount(int n) =>
      isEn ? (n == 1 ? '1 todo' : '$n todos') : '$n 项待办';

  /// 待办提醒的通知通道名（在系统「通知」设置里显示给用户的那个名字）。
  static String get todoReminderChannel => t('待办提醒', 'Todo reminders');

  // 闹钟
  static String get customAlarms => t('自定义闹钟', 'Custom alarms');
  static String get noCustomAlarms => t('还没有自定义闹钟，点下方「新建闹钟」添加。', 'No custom alarms yet, tap "New alarm" below.');
  static String get upcoming30 => t('未来 30 天班次闹钟', 'Shift alarms in next 30 days');
  static String get noUpcoming30 => t('近 30 天无班次闹钟', 'No shift alarms in next 30 days');
  static String get testAlarmScheduled => t('已排定测试闹钟，10 秒后响铃', 'Test alarm set, rings in 10s');
  static String get testAlarmFailed => t('测试闹钟排定失败：', 'Test alarm failed: ');
  static String get editAlarm => t('编辑闹钟', 'Edit alarm');
  static String get time => t('时间', 'Time');
  static String get once => t('一次性', 'Once');
  static String get daily => t('每天', 'Daily');
  static String get weekly => t('每周', 'Weekly');
  static String weekday(int i) {
    const zh = ['一', '二', '三', '四', '五', '六', '日'];
    const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return isEn ? en[i] : '周${zh[i]}';
  }

  // 排班编辑
  static String get editSchedule => t('编辑排班', 'Edit schedule');
  static String get scheduleNotFound => t('该排班不存在，可能已被删除', 'Schedule not found, may have been deleted');
  static String get saveAndReschedule => t('保存并重排闹钟', 'Save & reschedule alarms');
  static String get scheduleName => t('方案名称', 'Schedule name');
  static String get teamSettings => t('班组设置', 'Teams');
  static String get teamName => t('班组名', 'Team name');
  static String get today => t('今天', 'Today');
  static String get myTeam => t('我的班', 'My team');
  static String get setAsMine => t('设为我', 'Set as mine');
  static String get teamHint => t('为每个班组选一个「周期起始日」——那天它从周期第 1 天开始；「设为我」选中你所在的班。', 'Give each team a "cycle start date" — on that day it begins at cycle day 1; "Set as mine" marks your team.');
  static String get rest => t('休息', 'Rest');
  static String get work => t('工作', 'Work');
  static String get workday => t('上班', 'Workday');
  static String get followHoliday => t('跟随法定节假日（无班次）', 'Follow legal holidays (no shifts)');
  static String get followHolidayHint => t('法定节假日休息，其余按上班', 'Rest on legal holidays, work otherwise');
  static String get holidayScheduleName => t('法定班次', 'Legal-holiday schedule');
  static String get shiftName => t('班次名称', 'Shift name');
  static String get start => t('开始', 'Start');
  static String get end => t('结束', 'End');
  static String get crossesMidnight => t('（结束早于开始，或晚于 24:00 = 跨午夜）', '(ends before start, or past 24:00 = crosses midnight)');
  static String get linkedAlarm => t('联动闹钟', 'Linked alarm');
  static String get alarmTime => t('响铃时间', 'Alarm time');
  static String get notSet => t('未设置', 'Not set');
  static String get schedule => t('排班', 'Schedule');
  static String dayN(int n) => isEn ? 'Day $n' : '第 $n 天';

  /// 第 [i] 个班组的默认名（[i] 从 0 起）。
  ///
  /// 唯一来源：编辑器的班组步进器与「新建排班」的创建路径都调它，
  /// 免得两处各写一份、英文界面下漏出中文。
  static String defaultTeamName(int i) {
    if (isEn) return 'Team ${i + 1}';
    const names = ['一', '二', '三', '四', '五', '六', '七', '八'];
    return i < names.length ? '${names[i]}班' : '${i + 1}班';
  }

  /// [n] 个班组的完整默认名列表。
  ///
  /// 创建方案时必须传完整长度：多班组模板（五班三倒、六班三倒…）只带 4 个
  /// 默认名，靠数据库出口补位的话就得到了一份绕过本地化的名字。
  static List<String> defaultTeamNames(int n) =>
      List.generate(n, defaultTeamName);

  // 编辑器
  static String get shiftClasses => t('班次设置', 'Shift types');
  static String get shiftClassesHint =>
      t('先把你的班次各定义一次，下面周期里直接引用', 'Define each shift once, then reuse it in the cycle');
  static String get addShiftClass => t('添加班次', 'Add shift');
  static String get deleteShiftClassInUse =>
      t('周期里还有 {n} 天在用这个班次，先把它们改成别的', 'Still used by {n} day(s) in the cycle');
  static String get deleteShiftClassTitle =>
      t('删除这个班次？', 'Delete this shift?');
  static String deleteShiftClassContent(String name) => isEn
      ? 'Delete "$name"? This cannot be undone.'
      : '将删除「$name」，此操作不可撤销。';
  static String get cycleSection => t('周期设置', 'Cycle');
  static String get cycleLengthUnit => t('天', 'days');
  static String get myCycleStart => t('我这组从这个周期开始', 'My crew starts this cycle on');
  static String get crewCycleStart => t('周期起始日', 'Cycle start date');
  // 英文用 'Abbr' 而不是 'Short'：这个标签浮在 60pt 宽的窄输入框上，
  // 'Short'（5 字）会被裁成「Sh…」，'Abbr'（4 字）放得下且更准确。
  static String get abbrLabel => t('简称', 'Abbr');
  static String get crewSettingsOptional =>
      t('班组设置（可选，用于查看其他班组）', 'Crews (optional, to see other crews)');

  /// 「结束时间落在次日」的前缀（中文直接接钟点，英文要留空格）。
  ///
  /// 只作前缀用；成串的「开始 – 结束」走 [timeRange]，那里中英语序不同。
  static String get nextDay => t('次日', 'next day ');

  /// 「开始 – 结束」；跨午夜时中文插「次日」、英文在括号里注明。
  ///
  /// 中英两种语序不同，所以整串交给 [t] 而不是拼接前缀 ——
  /// 直接拼 `'次日'` 会在英文界面下露出中文。
  static String timeRange(String start, String end, bool crossesMidnight) =>
      crossesMidnight
          ? t('$start – 次日$end', '$start – $end (next day)')
          : '$start – $end';
  static String get newShiftName => t('新班次', 'New shift');
  static String get shiftColor => t('班次颜色', 'Shift color');
  static String get previewNext14 => t('未来 14 天', 'Next 14 days');

  // 排班管理
  static String get current => t('当前', 'current');
  static String get addSchedule => t('新增排班', 'New schedule');
  static String get deleteScheduleTitle => t('删除排班？', 'Delete schedule?');
  static String deleteScheduleContent(String name) => isEn
      ? 'Delete "$name"? This cannot be undone.'
      : '将删除「$name」，此操作不可撤销。';
  static String get newSchedule => t('新排班', 'New schedule');
  static String teamCountN(int n) => isEn ? '$n teams' : '$n 个班组';

  // 选择倒班方式
  static String get pickShiftPattern => t('选择你的倒班方式', 'Pick your shift pattern');
  static String get pickShiftPatternHint =>
      t('选一个和你班表最像的，建好之后还能随时改', 'Pick the closest one — you can tweak it anytime');
  static String get searchPattern => t('搜索，如「四班三倒」「上24休48」', 'Search, e.g. "4-crew 3-shift"');
  static String get customPattern => t('我自己排', 'Start from scratch');

  /// 倒班方式列表的分组标题。
  ///
  /// 分组在数据层是**语言无关键**（`ShiftTemplate.groupKey`），这里映射到
  /// 当前语言的显示名。键与显示名都必须与 `shiftTemplateGroups` 对得上 ——
  /// 对不上的键会走 `_ => key` 原样露出，英文界面上就会冒出一个 `h12`。
  ///
  /// 模板自身的标题/副标题**不在这里** —— 那是内容文案，跟着模板数据走，
  /// 见 `domain/shift_templates.dart`。
  static String templateGroup(String key) => switch (key) {
        'h12' => t('12 小时制', '12-hour shifts'),
        'h8' => t('8 小时制', '8-hour shifts'),
        'h6' => t('6 小时制', '6-hour shifts'),
        'duty' => t('值班制', '24-hour duty'),
        'office' => t('常白', 'Day shift only'),
        _ => key,
      };
  static String get customPatternHint => t('从默认四班两倒开始，边看边改', 'Start from the default and edit as you go');
  static String get noPatternMatch => t('没找到匹配的倒班方式', 'No matching pattern');
  /// 模板卡片底部那行「每天在岗 N 个班组」。
  ///
  /// 中英语序不同（中文把数量放中间、英文放句首），整串交给 [t] ——
  /// 拿「每天在岗」+ 数字 + 「个班组」拼出来的英文是「on duty 2 crews」。
  static String crewsOnDutyCount(int n) =>
      isEn ? '$n crews on duty' : '每天在岗 $n 个班组';

  // 日历
  static String get prevMonth => t('上个月', 'Previous month');
  static String get nextMonth => t('下个月', 'Next month');
  static String get switchSchedule => t('切换排班', 'Switch schedule');
  static String get switchScheduleShort => t('切换', 'Switch');
  static String get manageSchedule => t('管理排班', 'Manage schedules');
  static String get noSchedule => t('尚未配置排班，请到「我的」页编辑排班。', 'No schedule yet, edit in "Me".');
  static String get restNoAlarm => t('休息日 · 不响闹钟', 'Rest day · no alarm');
  static String get alarmOff => t('闹钟：未开启', 'Alarm: off');
  static String alarmAt(String time) => isEn ? 'Alarm $time' : '闹钟 $time';
  static String get otherCrews => t('其他班组', 'Other crews');
  static String get savedAndRescheduled => t('已保存并重排闹钟', 'Saved & alarms rescheduled');
  static String switchedTo(String name) => isEn ? 'Switched to $name' : '已切换到 $name';
  static List<String> get weekdays => isEn
      ? const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
      : const ['一', '二', '三', '四', '五', '六', '日'];

  // 使用帮助（图标化条目）
  static String get guideCalTitle => t('日历', 'Calendar');
  static String get guideCalDesc => t(
      '查看每日班次（日期/班次/农历/星期）；法定节假日整段标红、调休上班日带「班」标记；顶栏可切换排班、跳转年月；点某天看详情。',
      'View daily shifts (date/shift/lunar/weekday); statutory holidays marked red, makeup workdays tagged "班"; switch schedules and jump year/month from the toolbar; tap a day for details.');
  static String get guideSchedTitle => t('排班管理', 'Schedule management');
  static String get guideSchedDesc => t(
      '「我的 → 排班管理」可新建 / 编辑 / 删除多套排班；新建时先选一个内置倒班方式模板（19 种常见倒班方式，可用关键词搜索），再改班次时间、周期表与各班组周期起始日；打开「跟随法定节假日（无班次）」可得到一张只随节假日休班的空白表。要换成哪一套上场，走日历顶栏的「切换排班」。',
      'Me → Schedule management: create / edit / delete multiple schedules; start from a built-in shift-pattern template (19 common patterns, searchable), then tweak shift times, the cycle table and each team\'s cycle start date; turn on "Follow legal holidays (no shifts)" for a blank schedule that simply rests on legal holidays. To change which schedule is active, use "Switch schedule" in the calendar toolbar.');
  static String get guideAlarmTitle => t('闹钟', 'Alarms');
  static String get guideAlarmDesc => t(
      '白班/上夜班自动响铃（时间在排班编辑里改）；闹钟页显示未来 30 天、每天可单独开关；也可加自定义闹钟（一次性/每天/每周）。',
      'Day/night shifts ring automatically (set the time in schedule editing); the alarm page lists the next 30 days with per-day toggles; add custom alarms (once/daily/weekly).');
  static String get guideTodoTitle => t('待办', 'Todo');
  static String get guideTodoDesc => t(
      '记录交班/开会等事件，可设时间与提醒档位（准时 / 提前若干时间），到点会在通知栏弹出提醒；完成后勾选（变暗 + 删除线）。当天有待办时，日历底栏的信息卡上也会显示「N 项待办」。',
      'Log handover/meeting events with an optional time and a reminder (on time, or some time ahead); a notification appears at that moment. Tick an item when done (dims + strikethrough). When the selected day has todos, the calendar\'s info card also shows "N todos".');
  static String get guideAppearanceTitle => t('外观', 'Appearance');
  static String get guideAppearanceDesc => t(
      '「我的 → 外观」可切跟随系统/浅色/深色，选 5 种主色调，中英文切换；「高级材质」关掉后全 App 取消背景模糊，省电、低端机更流畅。',
      'Me → Appearance: follow the system / light / dark, pick one of 5 accent colours, and switch between Chinese and English. Turning "Advanced material" off removes background blur app-wide — lighter on battery and smoother on low-end devices.');
  static String get guideLayoutTitle =>
      t('横屏 · 宽屏 · 小窗', 'Landscape · wide screens · small windows');
  static String get guideLayoutDesc => t(
      '手机横屏、平板与车机等宽屏上，日历改为左右分栏：左边日期网格、右边当天信息；正文限宽居中，不再横向拉满。小米小窗 / 分屏下各页同样可用。',
      'On phone landscape and wide screens (tablets, car head units) the calendar becomes two panes — month grid on the left, day details on the right — and content is centred with a maximum width instead of stretching across. All pages also work in a Xiaomi floating window or split screen.');
  static String get guidePermTitle => t('权限', 'Permissions');
  static String get guidePermDesc => t(
      '首次使用务必到「我的 → 权限」开齐：通知、闹钟和提醒（精确闹钟）、自启动、后台弹出界面、全屏通知、电池优化，否则闹钟可能不响或锁屏不弹全屏。',
      'On first use, enable all in Me → Permissions: notifications, alarms & reminders (exact alarm), auto-start, display-over-other-apps, full-screen notifications, battery optimization — or alarms may not ring or pop over the lock screen.');
  static String get guideUpdateTitle => t('更新', 'Update');
  static String get guideUpdateDesc => t(
      '「我的 → 检查更新」查看最新正式版/测试版，应用内下载并自动拉起安装。',
      'Me → Check for updates shows the latest stable/beta builds; download and install in-app.');

  // 响铃界面
  static String get snooze => t('再睡一会', 'Snooze');
  static String get swipeUpToDismiss => t('上滑关闭', 'Swipe up to dismiss');

  // 外观设置
  static String get advancedMaterial => t('高级材质', 'Advanced material');
  static String get advancedMaterialHint => t(
      '关闭后去除真实背景模糊，模拟低端机效果', 'Turn off to remove real blur and preview the low-end effect');

  // 日期格式
  // 英文下月份要带出来：`yyyy M` 会渲染成「2026 9」，读不出是哪个月。
  // 用缩写月（Sep 2026）而不是全称，跟中文「2026年9月」的紧凑度对齐，
  // 顶部那颗胶囊才放得下。
  static String yearMonth(DateTime d) => isEn
      ? DateFormat('MMM yyyy', 'en').format(d)
      : DateFormat('yyyy年M月', 'zh').format(d);
  static String monthDay(DateTime d) => isEn
      ? DateFormat('MMM d', 'en').format(d)
      : DateFormat('M月d日', 'zh').format(d);
  static String monthShort(int month) {
    final d = DateTime(2000, month, 1);
    return isEn ? DateFormat('MMM', 'en').format(d) : DateFormat('M月', 'zh').format(d);
  }
  static String monthDayWeekday(DateTime d) => isEn
      ? DateFormat('EEE, MMM d', 'en').format(d)
      : DateFormat('M月d日 EEEE', 'zh').format(d);
  // 英文按 'Sep 9, 2026' 的顺序；`yyyy MMM d` 会串成「2026 Sep 9」，不像英文。
  static String yearMonthDay(DateTime d) => isEn
      ? DateFormat('MMM d, yyyy', 'en').format(d)
      : DateFormat('yyyy年 M月 d日', 'zh').format(d);
}
