import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/widgets/app_icon.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/app_info.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/update_checker.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_segment.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../core/widgets/glass_switch.dart';
import '../../core/theme/app_colors.dart';
import '../../data/app_repository.dart';
import '../../state/app_settings.dart';
import '../alarm/alarm_service.dart';
import '../calendar/schedule_management_screen.dart';
import 'app_dialogs.dart';

/// 「我的」页：外观（主题/主色调）、数据（清空重置）、关于。
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      body: SafeArea(
        child: CenteredContent(child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          physics: const BouncingScrollPhysics(),
          children: [
            Text(L10n.titleProfile, style: AppTokens.pageTitle),
            const SizedBox(height: 16),
            _sectionTitle(context, L10n.sectionAppearance),
            GlassTile(
              enableBlur: false,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L10n.themeMode, style: AppTokens.labelStrong),
                  const SizedBox(height: 8),
                  GlassSegment(
                    count: 3,
                    selectedIndex: settings.themeMode.index,
                    onSelected: (i) => ref
                        .read(appSettingsProvider.notifier)
                        .setThemeMode(AppThemeMode.values[i]),
                    itemBuilder: (i, selected) => Text(
                      [L10n.followSystem, L10n.light, L10n.dark][i],
                      // 基线 13px：未选中 w500、选中 w700。13 档最重的角色是 w600 的
                      // labelSecondary，两个分支都由这里显式给字重，按 spec 走 copyWith。
                      style: AppTokens.labelSecondary.copyWith(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(L10n.accentColor, style: AppTokens.labelStrong),
                  const SizedBox(height: 12),
                  GlassSegment(
                    height: 40,
                    count: AppColors.accentPalette.length,
                    selectedIndex: settings.accentIndex,
                    onSelected: (i) => ref
                        .read(appSettingsProvider.notifier)
                        .setAccentIndex(i),
                    // 选中态用一圈白色描边，而不是只靠背后的药丸。
                    // 药丸的颜色就是「当前主色」，选中那格色块的填充色跟它一模一样 ——
                    // 只给药丸的话，用户反而看不见自己选中了什么颜色。
                    itemBuilder: (i, selected) => Container(
                      width: 26,
                      height: 26,
                      padding: const EdgeInsets.all(AppTokens.gapHair),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.accentPalette[i],
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(L10n.language, style: AppTokens.labelStrong),
                  const SizedBox(height: 8),
                  GlassSegment(
                    count: 2,
                    selectedIndex: settings.language == 'en' ? 1 : 0,
                    onSelected: (i) => ref
                        .read(appSettingsProvider.notifier)
                        .setLanguage(i == 0 ? 'zh' : 'en'),
                    itemBuilder: (i, selected) => Text(
                      i == 0 ? '中文' : 'English',
                      // 基线 13px：未选中 w500、选中 w700。13 档最重的角色是 w600 的
                      // labelSecondary，两个分支都由这里显式给字重，按 spec 走 copyWith。
                      style: AppTokens.labelSecondary.copyWith(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(L10n.advancedMaterial,
                                style: AppTokens.labelStrong),
                            const SizedBox(height: AppTokens.gapHair),
                            Text(L10n.advancedMaterialHint,
                                style: AppTokens.microText
                                    .copyWith(color: AppTokens.inkMuted(context))),
                          ],
                        ),
                      ),
                      GlassSwitch(
                        value: settings.advancedMaterial,
                        onChanged: (v) => ref
                            .read(appSettingsProvider.notifier)
                            .setAdvancedMaterial(v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(L10n.hapticFeedback,
                                style: AppTokens.labelStrong),
                            const SizedBox(height: AppTokens.gapHair),
                            Text(L10n.hapticFeedbackHint,
                                style: AppTokens.microText
                                    .copyWith(color: AppTokens.inkMuted(context))),
                          ],
                        ),
                      ),
                      GlassSwitch(
                        value: settings.hapticsEnabled,
                        onChanged: (v) => ref
                            .read(appSettingsProvider.notifier)
                            .setHapticsEnabled(v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle(context, L10n.sectionSchedule),
            GlassTile(
              enableBlur: false,
              padding: EdgeInsets.zero,
              child: GlassPressable(
                child: ListTile(
                  leading: const Icon(Icons.tune_outlined),
                  title: Text(L10n.scheduleManagement),
                  subtitle: Text(L10n.scheduleManagementSubtitle),
                  trailing: const Icon(Icons.chevron_right_outlined),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const ScheduleManagementScreen()),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle(context, L10n.sectionAlarm),
            GlassTile(
              enableBlur: false,
              padding: EdgeInsets.zero,
              child: GlassPressable(
                child: ListTile(
                  leading: const Icon(Icons.music_note_outlined),
                  title: Text(L10n.ringtone),
                  subtitle: Text(L10n.ringtoneSubtitle),
                  trailing: const Icon(Icons.chevron_right_outlined),
                  onTap: () => _showRingtonePicker(context, ref),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle(context, L10n.sectionData),
            GlassTile(
              enableBlur: false,
              padding: EdgeInsets.zero,
              child: GlassPressable(
                child: ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined,
                      color: AppTokens.danger),
                  title: Text(L10n.clearReset),
                  subtitle: Text(L10n.clearResetSubtitle),
                  onTap: () => _confirmReset(context, ref),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle(context, L10n.sectionPermission),
            const _PermissionCheck(),
            const SizedBox(height: 16),
            _sectionTitle(context, L10n.sectionAbout),
            GlassTile(
              enableBlur: false,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outlined),
                    title: Text(L10n.version),
                    trailing: const Text('v$appVersion'),
                  ),
                  GlassPressable(
                    child: ListTile(
                      leading: const Icon(Icons.system_update_outlined),
                      title: Text(L10n.checkUpdate),
                      subtitle: Text(L10n.checkUpdateSubtitle),
                      onTap: () => _checkUpdate(context),
                    ),
                  ),
                  GlassPressable(
                    child: ListTile(
                      leading: const Icon(Icons.new_releases_outlined),
                      title: Text(L10n.changelog),
                      subtitle: Text(L10n.changelogSubtitle),
                      onTap: () => showChangelogDialog(context),
                    ),
                  ),
                  GlassPressable(
                    child: ListTile(
                      leading: const Icon(Icons.help_outlined),
                      title: Text(L10n.usageGuide),
                      onTap: () => showUsageGuideDialog(context),
                    ),
                  ),
                  GlassPressable(
                    child: ListTile(
                      leading: const Icon(Icons.bug_report_outlined),
                      title: Text(L10n.viewLog),
                      subtitle: Text(L10n.viewLogSubtitle),
                      onTap: () => _showLog(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      )),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        title,
        style: AppTokens.labelSecondary
            .copyWith(color: AppTokens.inkMuted(context)),
      ),
    );
  }

  Future<void> _checkUpdate(BuildContext context) async {
    final r = await UpdateChecker.checkUpdates();
    if (!context.mounted) return;
    if (r.error) {
      showGlassSnack(
        context,
        L10n.updateCheckFailed,
        icon: Icons.error_outlined,
        iconColor: AppTokens.danger,
      );
      return;
    }
    showUpdateDialog(context, r);
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (dialogContext) => GlassDialog(
        title: L10n.confirmResetTitle,
        content: Text(L10n.confirmResetContent),
        actions: [
          GlassActionButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            label: L10n.cancel,
          ),
          const SizedBox(width: 8),
          GlassActionButton(
            variant: GlassActionVariant.danger,
            onPressed: () => Navigator.pop(dialogContext, true),
            label: L10n.confirmResetAction,
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final repo = ref.read(appRepositoryProvider);
      await repo.clearAll();
      await AlarmService.rescheduleAll(repo);
      if (context.mounted) {
        showGlassSnack(context, L10n.resetDone, icon: Icons.check_circle_outlined);
      }
    }
  }

  Future<void> _showLog(BuildContext context) async {
    final log = await AlarmService.readLog();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (dialogContext) => GlassDialog(
        title: L10n.log,
        showClose: true,
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: SingleChildScrollView(
            child: SelectableText(
              log.isEmpty ? L10n.noLog : log,
              style: AppTokens.microText.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          GlassActionButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: log));
              if (dialogContext.mounted) {
                showGlassSnack(dialogContext, L10n.logCopied,
                    icon: Icons.content_copy_outlined);
              }
            },
            label: L10n.copy,
          ),
          const SizedBox(width: 8),
          GlassActionButton(
            onPressed: () async {
              await AlarmService.clearLog();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            label: L10n.clear,
          ),
        ],
      ),
    );
  }

  /// 选择器里「不是铃声 URI」的两个动作。带 `action:` 前缀，不会和系统铃声的
  /// `content://` 或自选铃声的 `file://` 撞上。
  static const String _actionPickFile = 'action:pickFile';
  static const String _actionRemoveFile = 'action:removeFile';

  Future<void> _showRingtonePicker(BuildContext context, WidgetRef ref) async {
    final sp = await SharedPreferences.getInstance();
    // 没存 = 内置铃声（不是存了 'builtin'，见下面写入的分支）。
    final current = sp.getString('ringtoneUri');
    final currentTitle = sp.getString('ringtoneTitle');
    final ringtones = await AlarmService.listRingtones();
    if (!context.mounted) return;

    final selection = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (sheetContext) => GlassPanel(
        solid: true,
        margin: const EdgeInsets.all(12),
        borderRadius: const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(L10n.ringtone, style: AppTokens.titleStrong),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    GlassPressable(
                      child: ListTile(
                        leading: const Icon(Icons.alarm_outlined),
                        title: Text(L10n.builtinRingtone),
                        subtitle: Text(L10n.builtinRingtoneSubtitle),
                        trailing: _ringtoneTrailing(
                          context,
                          selected: current == null,
                          onPreview: () => AlarmService.playRingtone(null),
                        ),
                        onTap: () => Navigator.pop(sheetContext, 'builtin'),
                      ),
                    ),
                    // 自选铃声：只在真的设过时出现，免得平时多占一行。
                    if (_isFileRingtone(current))
                      GlassPressable(
                        child: ListTile(
                          leading: const Icon(Icons.music_note_outlined),
                          title: Text(
                            (currentTitle == null || currentTitle.isEmpty)
                                ? L10n.myRingtone
                                : currentTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(L10n.myRingtone),
                          trailing: _ringtoneTrailing(
                            context,
                            selected: true,
                            onPreview: () => AlarmService.playRingtone(current),
                            onRemove: () =>
                                Navigator.pop(sheetContext, _actionRemoveFile),
                          ),
                          onTap: () => Navigator.pop(sheetContext, current),
                        ),
                      ),
                    GlassPressable(
                      child: ListTile(
                        leading: const Icon(Icons.folder_open_outlined),
                        title: Text(L10n.pickRingtoneFromFile),
                        // 复制进私有目录这件事要写明白：用户有权知道选中的文件
                        // 被怎么处理了。
                        subtitle: Text(L10n.pickRingtonePrivacy),
                        onTap: () =>
                            Navigator.pop(sheetContext, _actionPickFile),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(L10n.systemRingtones,
                          style: AppTokens.labelStrong),
                    ),
                    ...ringtones.map((r) => GlassPressable(
                          child: ListTile(
                            leading: const Icon(Icons.music_note_outlined),
                            title: Text(r.title),
                            trailing: _ringtoneTrailing(
                              context,
                              selected: current == r.uri,
                              onPreview: () => AlarmService.playRingtone(r.uri),
                            ),
                            onTap: () => Navigator.pop(sheetContext, r.uri),
                          ),
                        )),
                    if (ringtones.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(L10n.noRingtones),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await AlarmService.stopRingtone();
    if (selection == null || !context.mounted) return;

    if (selection == _actionPickFile) {
      await _pickRingtoneFile(context, ref, sp);
      return;
    }

    if (selection == _actionRemoveFile) {
      await AlarmService.clearRingtoneFile();
      await sp.remove('ringtoneUri');
      await sp.remove('ringtoneTitle');
      await _rescheduleAlarms(ref);
      if (context.mounted) {
        showGlassSnack(context, L10n.ringtoneFileRemoved,
            icon: Icons.delete_outline);
      }
      return;
    }

    if (selection == 'builtin') {
      // 换回内置铃声：把复制进来的文件删掉，别在私有目录里留垃圾。
      await AlarmService.clearRingtoneFile();
      await sp.remove('ringtoneUri');
      await sp.remove('ringtoneTitle');
    } else if (_isFileRingtone(selection)) {
      await sp.setString('ringtoneUri', selection);
    } else {
      // 系统铃声：同样清掉自选文件。
      await AlarmService.clearRingtoneFile();
      await sp.setString('ringtoneUri', selection);
      await sp.remove('ringtoneTitle');
    }
    await _rescheduleAlarms(ref);
    if (context.mounted) {
      showGlassSnack(
        context,
        selection == 'builtin' ? L10n.setBuiltinRingtone : L10n.ringtoneSet,
        icon: Icons.music_note_outlined,
      );
    }
  }

  /// 「我的铃声」那一行的判断依据：自选铃声存的是 `file://` 路径，
  /// 内置是没存、系统铃声是 `content://`。
  static bool _isFileRingtone(String? uri) =>
      uri != null && uri.startsWith('file://');

  /// 列表行右侧：试听按钮 +（自选铃声那行再加一个）移除按钮 + 选中对勾。
  Widget _ringtoneTrailing(
    BuildContext context, {
    required bool selected,
    required VoidCallback onPreview,
    VoidCallback? onRemove,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.play_circle_outlined),
          tooltip: L10n.preview,
          onPressed: onPreview,
        ),
        if (onRemove != null)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: L10n.removeRingtone,
            onPressed: onRemove,
          ),
        if (selected)
          AppIcon(Icons.check,
              size: AppTokens.iconMd,
              color: Theme.of(context).colorScheme.primary),
      ],
    );
  }

  Future<void> _pickRingtoneFile(
      BuildContext context, WidgetRef ref, SharedPreferences sp) async {
    try {
      final picked = await AlarmService.pickRingtoneFile();
      // 用户按返回取消了 —— 什么都不做，也不提示。
      if (picked == null || !context.mounted) return;
      // 这里**不要**再调 clearRingtoneFile：原生侧复制新文件之前已经把旧的那份
      // 删掉了，再清一次会把刚复制进来的这个也删掉。
      await sp.setString('ringtoneUri', picked.uri);
      await sp.setString('ringtoneTitle', picked.name);
      await _rescheduleAlarms(ref);
      if (context.mounted) {
        showGlassSnack(context, L10n.ringtoneSet,
            icon: Icons.music_note_outlined);
      }
    } on RingtonePickException catch (e) {
      // 「太大」和「读不出来」要说成两句不同的话，否则用户只会反复重试同一个文件。
      if (!context.mounted) return;
      showGlassSnack(
        context,
        e.isTooLarge ? L10n.ringtoneTooLarge : L10n.ringtoneCopyFailed,
        icon: Icons.error_outline,
      );
    }
  }

  Future<void> _rescheduleAlarms(WidgetRef ref) async {
    await AlarmService.rescheduleAll(ref.read(appRepositoryProvider));
  }
}

/// 权限检测卡：展示通知 + 精确闹钟权限状态，未开启时可一键跳转系统开启。
class _PermissionCheck extends ConsumerStatefulWidget {
  const _PermissionCheck();

  @override
  ConsumerState<_PermissionCheck> createState() => _PermissionCheckState();
}

class _PermissionCheckState extends ConsumerState<_PermissionCheck>
    with WidgetsBindingObserver {
  bool? _notif;
  bool? _exact;
  bool? _overlay;
  bool? _fsi;
  bool? _battery;
  bool? _miui;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从系统设置页返回（App 回到前台）时，重新检测权限，保证状态实时。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final (notif, exact) = await AlarmService.checkPermissions();
    final overlay = await AlarmService.checkOverlayPermission();
    final fsi = await AlarmService.checkFullScreenIntentPermission();
    final battery = await AlarmService.checkBatteryOptimization();
    final miui = await AlarmService.checkMiuiPermissionPage();
    if (!mounted) return;
    setState(() {
      _notif = notif;
      _exact = exact;
      _overlay = overlay;
      _fsi = fsi;
      _battery = battery;
      _miui = miui;
    });
  }

  Future<void> _openNotifications() async {
    await AlarmService.requestNotificationsPermission();
    await _refresh();
  }

  Future<void> _openExactAlarms() async {
    await AlarmService.requestExactAlarmsPermission();
    await _refresh();
  }

  Future<void> _openAutoStart() async {
    await AlarmService.openAppSettings();
  }

  /// 小米那项「后台弹出界面」读不到状态，只能送到那个页面让用户自己开；
  /// 万一页面打不开（非小米或 ROM 拦了），落回系统「应用信息」页。
  Future<void> _openMiuiPermissionPage() async {
    final ok = await AlarmService.openMiuiPermissionPage();
    if (!ok) await AlarmService.openAppSettings();
  }

  Future<void> _openOverlay() async {
    await AlarmService.openOverlaySettings();
    await _refresh();
  }

  Future<void> _openFullScreenIntent() async {
    await AlarmService.openFullScreenIntentSettings();
    await _refresh();
  }

  Future<void> _openBattery() async {
    await AlarmService.requestIgnoreBatteryOptimizations();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appSettingsProvider); // 语言切换时重建（权限卡文案也要实时刷新）
    final loading = _notif == null ||
        _exact == null ||
        _overlay == null ||
        _fsi == null ||
        _battery == null;
    return GlassTile(
      enableBlur: false,
      padding: const EdgeInsets.fromLTRB(
          4, AppTokens.gapIconText, 4, AppTokens.gapIconText),
      child: loading
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(L10n.permChecking),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _groupHeader(context, L10n.permGroupBasic),
                _permTile(
                  icon: _notif!
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  title: L10n.permNotif,
                  subtitle: _notif! ? L10n.enabled : L10n.permNotifOff,
                  enabled: _notif!,
                  onOpen: _openNotifications,
                ),
                const Divider(height: 1),
                _permTile(
                  icon: _exact! ? Icons.alarm_on_outlined : Icons.alarm_off_outlined,
                  title: L10n.permExact,
                  subtitle: _exact! ? L10n.enabled : L10n.permExactOff,
                  enabled: _exact!,
                  onOpen: _openExactAlarms,
                ),
                _groupHeader(context, L10n.permGroupFullscreen),
                _permTile(
                  icon: Icons.aspect_ratio_outlined,
                  title: L10n.permOverlay,
                  subtitle: _overlay! ? L10n.enabled : L10n.permOverlayHint,
                  enabled: _overlay!,
                  onOpen: _openOverlay,
                ),
                const Divider(height: 1),
                _permTile(
                  icon: Icons.fullscreen_outlined,
                  title: L10n.permFsi,
                  subtitle: _fsi! ? L10n.enabled : L10n.permFsiHint,
                  enabled: _fsi!,
                  onOpen: _openFullScreenIntent,
                ),
                // 下面两行只在小米机型出现：它们是 MIUI 私有的权限，别家没有，摆出来
                // 只会让人白跑一趟。状态都读不到（没有公开 API），所以是「去查看」
                // 而不是开关态 —— 也正是因此要**分成两行**：一个的症状是「退到后台
                // 不弹」，另一个是「锁屏不弹」，用户能各自对号入座。
                if (_miui == true) ...[
                  const Divider(height: 1),
                  _permTile(
                    icon: Icons.open_in_new_outlined,
                    title: L10n.permMiuiPopup,
                    subtitle: L10n.permMiuiPopupHint,
                    enabled: null,
                    onOpen: _openMiuiPermissionPage,
                    actionLabel: L10n.goCheck,
                  ),
                  const Divider(height: 1),
                  _permTile(
                    icon: Icons.screen_lock_portrait_outlined,
                    title: L10n.permMiuiLockScreen,
                    subtitle: L10n.permMiuiLockScreenHint,
                    enabled: null,
                    onOpen: _openMiuiPermissionPage,
                    actionLabel: L10n.goCheck,
                  ),
                ],
                _groupHeader(context, L10n.permGroupBackground),
                _permTile(
                  icon: Icons.power_settings_new_outlined,
                  title: L10n.permAutoStart,
                  subtitle: L10n.permAutoStartHint,
                  enabled: null, // 系统不提供检测，始终显示「去查看」
                  onOpen: _openAutoStart,
                  actionLabel: L10n.goCheck,
                ),
                const Divider(height: 1),
                _permTile(
                  icon: Icons.battery_saver_outlined,
                  title: L10n.permBattery,
                  subtitle: _battery! ? L10n.enabled : L10n.permBatteryHint,
                  enabled: _battery!,
                  onOpen: _openBattery,
                ),
              ],
            ),
    );
  }

  Widget _groupHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: AppTokens.labelSecondary
            .copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _permTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool? enabled,
    required VoidCallback onOpen,
    String? actionLabel,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: enabled == true
          ? null
          : TextButton(
              onPressed: onOpen,
              child: Text(actionLabel ?? L10n.goEnable),
            ),
    );
  }
}
