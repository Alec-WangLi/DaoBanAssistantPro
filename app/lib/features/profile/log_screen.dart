// app/lib/features/profile/log_screen.dart
//
// 「查看日志」整页（v0.13.20 从 360dp 高的弹窗升级而来）。
//
// 四条要求来自用户：「展示是一部分，同时还可以导出详细日志，这样才能全覆盖」。
// 于是这一页做三件事：
//   · 按天翻（原生侧日志从这一版起按天归档、保留 7 天 —— 报「偶尔没响」的人
//     往往隔一两天才反馈，单文件 128KB 早把出事那段裁掉了）；
//   · 能搜（一个 id、一个关键字就能把那几行捞出来）；
//   · 能导出诊断包（日志 + 设备权限 + 原生落盘清单 + App 算出来的计划）。
//
// 不做的：解析成结构化表格。日志的自由文本正是它覆盖面广的原因，做窄了反而漏。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_choice_chip.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../data/app_repository.dart';
import '../alarm/alarm_service.dart';
import '../backup/backup_io.dart';
import 'diagnostic_bundle.dart';

class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  List<LogFileInfo> _files = const <LogFileInfo>[];
  int _index = 0;
  String _text = '';
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<LogFileInfo> files = await AlarmService.listLogFiles();
    final String text = files.isEmpty
        ? await AlarmService.readLog() // 老版本还没有 listLogFiles 时的兜底
        : await AlarmService.readLogFile(files[_index].name);
    if (!mounted) return;
    setState(() {
      _files = files;
      _text = text;
      _loading = false;
    });
    if (!mounted) return;
    // 最新的在最后一行 —— 打开就落到末尾，不用手动滑。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  Future<void> _selectFile(int i) async {
    if (i == _index || i >= _files.length) return;
    setState(() {
      _index = i;
      _loading = true;
    });
    final String text = await AlarmService.readLogFile(_files[i].name);
    if (!mounted) return;
    setState(() {
      _text = text;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  /// 搜索命中后的行（保持原顺序）。空查询返回全文。
  String get _shown {
    final String q = _queryCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _text;
    final List<String> hit = <String>[
      for (final String line in _text.split('\n'))
        if (line.toLowerCase().contains(q)) line,
    ];
    return hit.join('\n');
  }

  int get _lineCount => _text.isEmpty ? 0 : _text.split('\n').length;
  int get _shownLineCount => _shown.isEmpty ? 0 : _shown.split('\n').length;

  @override
  Widget build(BuildContext context) {
    final Color muted = AppTokens.inkMuted(context);
    return Scaffold(
      appBar: AppBar(title: Text(L10n.log)),
      body: CenteredContent(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceLg, 0, AppTokens.spaceLg, AppTokens.spaceSm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_files.length > 1)
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    key: const Key('log-day-chips'),
                    scrollDirection: Axis.horizontal,
                    itemCount: _files.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: AppTokens.spaceSm),
                    itemBuilder: (context, i) => Center(
                      child: GlassChoiceChip(
                        label: i == 0 ? L10n.today : _files[i].day,
                        color: Theme.of(context).colorScheme.primary,
                        selected: i == _index,
                        onTap: () => _selectFile(i),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppTokens.spaceSm),
              TextField(
                key: const Key('log-search'),
                controller: _queryCtrl,
                onChanged: (_) => setState(() {}),
                style: AppTokens.rowSecondary,
                decoration: glassInputDecoration(context, isDense: true)
                    .copyWith(
                  hintText: L10n.logSearchHint,
                  prefixIcon: AppIcon(Icons.search,
                      size: AppTokens.iconMd, color: muted),
                  suffixIcon: _queryCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: AppIcon(Icons.close,
                              size: AppTokens.iconMd, color: muted),
                          onPressed: () {
                            _queryCtrl.clear();
                            setState(() {});
                          },
                        ),
                ),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceXs),
                child: Text(
                  L10n.logLineCount(_lineCount, _shownLineCount),
                  style: AppTokens.microText.copyWith(color: muted),
                ),
              ),
              const SizedBox(height: AppTokens.spaceXs),
              Expanded(
                child: GlassPanel(
                  solid: true,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.all(AppTokens.spaceMd),
                          child: SelectableText(
                            _shown.isEmpty ? L10n.noLog : _shown,
                            key: const Key('log-body'),
                            style: AppTokens.microText
                                .copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: GlassActionButton(
                      variant: GlassActionVariant.secondary,
                      onPressed: _copy,
                      label: L10n.copy,
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  Expanded(
                    flex: 2,
                    child: GlassActionButton(
                      variant: GlassActionVariant.primary,
                      onPressed: _busy ? null : _export,
                      label: L10n.logExportBundle,
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  Expanded(
                    child: GlassActionButton(
                      variant: GlassActionVariant.danger,
                      onPressed: _clear,
                      label: L10n.clear,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _shown));
    if (!mounted) return;
    showGlassSnack(context, L10n.logCopied, icon: Icons.content_copy_outlined);
  }

  Future<void> _export() async {
    // **隐私先说清楚**：日志里有用户写的待办标题与班次备注。
    if (!await _confirm(
      title: L10n.logExportBundle,
      message: L10n.logExportPrivacy,
      action: L10n.export,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final Directory dir = await getTemporaryDirectory();
      final String path = await DiagnosticBundle.build(
          ref.read(appRepositoryProvider),
          dir: dir);
      final String? saved = await BackupIo.save(
        suggestedName: p.basename(path),
        sourcePath: path,
        mime: 'application/zip',
      );
      if (!mounted) return;
      if (saved != null) {
        showGlassSnack(context, L10n.logExported,
            icon: Icons.file_download_outlined);
      }
    } catch (e) {
      if (mounted) showGlassSnack(context, '${L10n.logExportFailed}$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (!await _confirm(
      title: L10n.clear,
      message: L10n.logClearConfirm,
      action: L10n.clear,
      danger: true,
    )) {
      return;
    }
    await AlarmService.clearLog();
    if (!mounted) return;
    setState(() {
      _index = 0;
      _text = '';
      _files = const <LogFileInfo>[];
    });
    await _load();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool danger = false,
  }) async {
    final bool? ok = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: title,
        showClose: true,
        content: SizedBox(
          width: double.maxFinite,
          child: Text(message,
              style: AppTokens.rowSecondary
                  .copyWith(color: AppTokens.inkMuted(dialogContext))),
        ),
        actions: <Widget>[
          GlassActionButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            label: L10n.cancel,
          ),
          const SizedBox(width: 8),
          GlassActionButton(
            variant: danger
                ? GlassActionVariant.danger
                : GlassActionVariant.primary,
            onPressed: () => Navigator.pop(dialogContext, true),
            label: action,
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
