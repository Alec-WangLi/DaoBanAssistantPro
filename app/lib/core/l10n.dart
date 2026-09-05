import 'package:intl/intl.dart';

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
  static String get ringtoneSubtitle => t('选择内置或系统铃声', 'Choose a built-in or system ringtone');
  static String get clearReset => t('清空重置', 'Clear & reset');
  static String get clearResetSubtitle => t('清空排班与日程，恢复默认四班两倒', 'Clear schedules & events, restore default rotation');
  static String get version => t('版本', 'Version');
  static String get changelog => t('版本更新', "What's new");
  static String get changelogSubtitle => t('查看本版本更新内容', 'View changes in this version');
  static String get checkUpdate => t('检查更新', 'Check for update');
  static String get checkUpdateSubtitle => t('获取正式版与测试版', 'Get stable & beta releases');
  static String get alreadyLatest => t('已是最新', 'Up to date');
  static String get updateCheckFailed => t('检查更新失败（网络异常，请稍后再试）', 'Update check failed (network error), try later');
  static String get stableChannel => t('正式版', 'Stable');
  static String get testChannel => t('测试版', 'Beta');
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

  // 待办（日程）
  static String get noEvents => t('还没有待办事项，点右下角添加', 'No todos yet, tap + to add');
  static String get addEvent => t('添加待办事项', 'Add todo');
  static String get editEvent => t('编辑待办事项', 'Edit todo');
  static String get title => t('标题', 'Title');
  static String get date => t('日期', 'Date');
  static String get timeOptional => t('时间（可选）', 'Time (optional)');
  static String get advanceRemindOptional => t('提前提醒（可选）', 'Remind ahead (optional)');
  static String get none => t('不设', 'None');
  static String advanceXMinutes(int n) => isEn ? '$n min ahead' : '提前$n分钟';

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
  static String get anchorDate => t('锚点日（参考日期）', 'Anchor date (reference)');
  static String get anchorHint => t('提示：先选一个参考日期，再在下方为每个班组指定「今天」的班。', 'Tip: pick a reference date, then assign each team its "today" shift below.');
  static String get teamSettings => t('班组设置', 'Teams');
  static String get teamName => t('班组名', 'Team name');
  static String get today => t('今天', 'Today');
  static String get myTeam => t('我的班', 'My team');
  static String get setAsMine => t('设为我', 'Set as mine');
  static String get teamHint => t('「今天」= 锚点日的班：为每个班组选好锚点日各自的班；「设为我」选中你所在的班。', '"Today" = the shift on the anchor date; "Set as mine" marks your team.');
  static String get restShift => t('休班', 'Rest');
  static String get rest => t('休息', 'Rest');
  static String get work => t('工作', 'Work');
  static String get workday => t('上班', 'Workday');
  static String get followHoliday => t('跟随法定节假日（无班次）', 'Follow legal holidays (no shifts)');
  static String get followHolidayHint => t('法定节假日休息，其余按上班', 'Rest on legal holidays, work otherwise');
  static String get holidayScheduleName => t('法定班次', 'Legal-holiday schedule');
  static String get shiftName => t('班次名称', 'Shift name');
  static String get start => t('开始', 'Start');
  static String get end => t('结束', 'End');
  static String get crossesMidnight => t('（结束早于开始 = 跨午夜）', '(end before start = crosses midnight)');
  static String get linkedAlarm => t('联动闹钟', 'Linked alarm');
  static String get alarmTime => t('响铃时间', 'Alarm time');
  static String get notSet => t('未设置', 'Not set');
  static String get schedule => t('排班', 'Schedule');
  static String dayN(int n) => isEn ? 'Day $n' : '第 $n 天';
  static String teamN(int n) => isEn ? '$n teams' : '$n 个班';

  // 排班管理
  static String get current => t('当前', 'current');
  static String get addSchedule => t('新增排班', 'New schedule');
  static String get deleteScheduleTitle => t('删除排班？', 'Delete schedule?');
  static String deleteScheduleContent(String name) => isEn
      ? 'Delete "$name"? This cannot be undone.'
      : '将删除「$name」，此操作不可撤销。';
  static String get newSchedule => t('新排班', 'New schedule');
  static String teamCountN(int n) => isEn ? '$n teams' : '$n 个班组';

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
  static String get otherTeamsPrefix => t('其他班组：', 'Other teams: ');
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
  static String get guideSchedTitle => t('排班设置', 'Schedule');
  static String get guideSchedDesc => t(
      '「我的 → 排班管理」可建/切多套排班；编辑时先选锚点日，给每个班指定「今天」的班，再「设为我」选中你所在的班；可选「法定班次」跟随节假日。',
      'Me → Schedule management: create/switch multiple schedules; pick an anchor date, assign each team its "today" shift, then "Set as mine"; optional "Legal-holiday schedule".');
  static String get guideAlarmTitle => t('闹钟', 'Alarms');
  static String get guideAlarmDesc => t(
      '白班/上夜班自动响铃（时间在排班编辑里改）；闹钟页显示未来 30 天、每天可单独开关；也可加自定义闹钟（一次性/每天/每周）。',
      'Day/night shifts ring automatically (set the time in schedule editing); the alarm page lists the next 30 days with per-day toggles; add custom alarms (once/daily/weekly).');
  static String get guideTodoTitle => t('待办', 'Todo');
  static String get guideTodoDesc => t(
      '记录交班/开会等事件，可设时间与提前提醒，完成后勾选（变暗 + 删除线）。',
      'Log handover/meeting events with optional time and reminders; tick when done (dims + strikethrough).');
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
  static String yearMonth(DateTime d) => isEn
      ? DateFormat('yyyy M', 'en').format(d)
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
  static String yearMonthDay(DateTime d) => isEn
      ? DateFormat('yyyy MMM d', 'en').format(d)
      : DateFormat('yyyy年 M月 d日', 'zh').format(d);
}
