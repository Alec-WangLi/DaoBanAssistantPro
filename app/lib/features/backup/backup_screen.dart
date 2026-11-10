// app/lib/features/backup/backup_screen.dart
//
// 「我的 → 数据备份」：导出 / 导入。
//
// 导入不在这里直接换库：先暂存，再冷重启，由 `main()` 在任何数据库打开之前
// 完成替换（见 `backup_service.dart` 顶部说明）。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/clock.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/haptics.dart';
import '../../core/l10n.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_loading.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../data/app_repository.dart';
import 'backup_format.dart';
import 'backup_io.dart';
import 'backup_service.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  String _busyLabel = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.dataBackup)),
      body: CenteredContent(
        child: Stack(
          children: <Widget>[
            ListView(
              padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg,
                  AppTokens.spaceSm, AppTokens.spaceLg, AppTokens.space2xl),
              children: <Widget>[
                Text(
                  L10n.backupIntro,
                  style: AppTokens.rowSecondary.copyWith(
                      height: 1.5, color: AppTokens.inkMuted(context)),
                ),
                const SizedBox(height: AppTokens.spaceXl),
                GlassTile(
                  translucentFill: false,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      GlassPressable(
                        child: ListTile(
                          leading: const Icon(Icons.save_alt_outlined),
                          title: Text(L10n.backupExport),
                          subtitle: Text(L10n.backupExportSubtitle),
                          trailing: const Icon(Icons.chevron_right_outlined),
                          onTap: _busy ? null : _export,
                        ),
                      ),
                      const Divider(height: 1),
                      GlassPressable(
                        child: ListTile(
                          leading:
                              const Icon(Icons.settings_backup_restore_outlined),
                          title: Text(L10n.backupImport),
                          subtitle: Text(L10n.backupImportSubtitle),
                          trailing: const Icon(Icons.chevron_right_outlined),
                          onTap: _busy ? null : _import,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.spaceXl),
                Text(
                  L10n.backupHint,
                  style: AppTokens.rowSecondary.copyWith(
                      height: 1.5, color: AppTokens.inkMuted(context)),
                ),
              ],
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context)
                      .colorScheme
                      .scrim
                      .withValues(alpha: 0.18),
                  child: Center(
                    child: GlassPanel(
                      solid: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.spaceXl,
                          vertical: AppTokens.spaceLg),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const GlassLoading(size: 24),
                          const SizedBox(width: AppTokens.spaceMd),
                          Text(_busyLabel, style: AppTokens.rowPrimary),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyLabel = L10n.backupExporting;
    });
    File? temp;
    try {
      final bytes = await BackupService(db: ref.read(databaseProvider))
          .createBackup();
      final Directory dir = await getTemporaryDirectory();
      temp = File(p.join(dir.path,
          'shiftassistant-backup-${_stamp()}.$kBackupExtension'));
      await temp.writeAsBytes(bytes, flush: true);

      final String? uri = await BackupIo.save(
        suggestedName: p.basename(temp.path),
        sourcePath: temp.path,
      );
      if (!mounted) return;
      // 只有真的存出去了才算「动作落实」；用户在系统选择器里取消（uri == null）
      // 什么都没发生，不该震。
      if (uri != null) Haptics.commit();
      showGlassSnack(
        context,
        uri == null ? L10n.backupCanceled : L10n.backupSaved,
        icon: uri == null ? null : Icons.check_circle_outline,
      );
    } on PlatformException catch (e) {
      if (mounted) showGlassSnack(context, _platformError(e));
    } catch (e) {
      if (mounted) showGlassSnack(context, L10n.backupFailed);
    } finally {
      if (temp != null && await temp.exists()) {
        await temp.delete();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;

    final String? path;
    try {
      path = await BackupIo.pick();
    } on PlatformException catch (e) {
      if (mounted) showGlassSnack(context, _platformError(e));
      return;
    }
    if (path == null) {
      if (mounted) showGlassSnack(context, L10n.backupCanceled);
      return;
    }

    setState(() {
      _busy = true;
      _busyLabel = L10n.backupImporting;
    });
    try {
      final bytes = await File(path).readAsBytes();
      final BackupArchive archive = decodeBackup(
        bytes,
        maxSchemaVersion: AppDatabase.schemaVersionNumber,
      );

      if (!mounted) return;
      setState(() => _busy = false);
      final bool? confirmed = await showGlassDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => GlassDialog(
          title: L10n.backupConfirmTitle,
          content: Text(L10n.backupConfirmContent(
            archive.manifest.appVersion,
            _formatTime(archive.manifest.exportedAt.toLocal()),
          )),
          actions: <Widget>[
            GlassActionButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              label: L10n.cancel,
            ),
            const SizedBox(width: AppTokens.spaceSm),
            GlassActionButton(
              variant: GlassActionVariant.danger,
              onPressed: () => Navigator.pop(dialogContext, true),
              label: L10n.backupConfirmAction,
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      setState(() {
        _busy = true;
        _busyLabel = L10n.backupImporting;
      });
      await BackupService(db: ref.read(databaseProvider)).stageRestore(bytes);
      if (!mounted) return;
      // 走到这里说明备份已经校验通过、写进待恢复目录 —— 导入真正落实了。
      // 后面那个「立即重启」只是生效方式，震在这里而不是按钮上。
      Haptics.commit();
      setState(() => _busy = false);

      final bool? restart = await showGlassDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => GlassDialog(
          title: L10n.backupRestartTitle,
          content: Text(L10n.backupRestartContent),
          actions: <Widget>[
            GlassActionButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              label: L10n.backupLater,
            ),
            const SizedBox(width: AppTokens.spaceSm),
            GlassActionButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              label: L10n.backupRestartNow,
            ),
          ],
        ),
      );
      if (restart == true) {
        await BackupIo.restart();
      } else if (mounted) {
        showGlassSnack(context, L10n.backupRestartManually);
      }
    } on BackupFormatException catch (e) {
      if (mounted) showGlassSnack(context, _formatError(e));
    } on PlatformException catch (e) {
      if (mounted) showGlassSnack(context, _platformError(e));
    } catch (e) {
      if (mounted) showGlassSnack(context, L10n.backupFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatError(BackupFormatException e) {
    if (e.code == 'schema_too_new' || e.code == 'format_too_new') {
      return L10n.backupTooNew;
    }
    return L10n.backupInvalid;
  }

  String _platformError(PlatformException e) {
    if (e.code == 'BACKUP_TOO_LARGE') return L10n.backupTooLarge;
    return L10n.backupFailed;
  }

  String _stamp() {
    final DateTime now = appNow();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}';
  }

  String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
