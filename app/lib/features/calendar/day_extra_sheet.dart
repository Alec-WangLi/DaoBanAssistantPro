// app/lib/features/calendar/day_extra_sheet.dart
//
// 「请假 / 加班」时长选择层 —— 与「调整班次」同一个玻璃弹层配方。
//
// v0.13.17 起多了两样：
//   · **请假类型**（内置五类 + 用户自定义，存的是键，名字跟着记录走）；
//   · **备注**（请假 / 加班各一行各一份）。
//
// 为什么不用输入框做时长：底部弹层里的 TextField 会被软键盘盖住 —— 所以时长仍是
// 「几个常见档 + 30 分钟加减」，只有备注才真的要打字，并按 `viewInsets.bottom`
// 把整块面板顶上去（照 `shift_color_picker.dart` 那条唯一先例）。
//
// 返回值：`null` = 取消；`DayExtraSelection.fullDay()` = 按每天班次时长算；
// `.minutes(n)` = 每天 n 分钟；`.clear()` = 清除已有记录。
import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_choice_chip.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_sheet_panel.dart';
import '../../core/widgets/glass_field.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/glass_pill.dart';
import '../../core/widgets/glass_sheet_header.dart';
import '../../domain/day_extra.dart';
import '../../domain/shift_rotation.dart';

/// 弹层的结果。`minutes == 0 && !clear` 表示「整天」（按每天各自的班次时长算）。
class DayExtraSelection {
  const DayExtraSelection.minutes(this.minutes, {this.leaveKind, this.note})
      : clear = false;
  const DayExtraSelection.fullDay({this.leaveKind, this.note})
      : minutes = 0,
        clear = false;
  const DayExtraSelection.clear()
      : minutes = 0,
        clear = true,
        leaveKind = null,
        note = null;

  final int minutes;
  final bool clear;

  /// 请假类型键；加班或没选时为 null。
  final String? leaveKind;

  /// 备注（已 trim）；没写时为 null。
  final String? note;

  bool get isFullDay => !clear && minutes == 0;
}

/// 弹「请假 / 加班」时长选择层。
///
/// [existingMinutes] 是**单日**已有记录的分钟数（多天时传 null）；[hasExisting]
/// 为真时底部出现「清除」。 [fullDayMinutes] 是单日班次时长，用来给「整天 / 半天」
/// 一个默认值；多天时为 null，界面上「整天」仍可选，写库时逐天算。
///
/// [initialLeaveKind] / [initialNote] 是这天的已有值（多天区间里各天不一致时传
/// null）。[customLeaveTypes] 是用户自定义的类型名；[onCustomLeaveTypesChanged]
/// 在增删类型时回调（调用方负责写进设置）。
Future<DayExtraSelection?> showDayExtraSheet(
  BuildContext context, {
  required DayExtraKind kind,
  required DateTime from,
  required DateTime to,
  required int dayCount,
  int? existingMinutes,
  int? fullDayMinutes,
  bool hasExisting = false,
  String? initialLeaveKind,
  String? initialNote,
  List<String> customLeaveTypes = const <String>[],
  ValueChanged<List<String>>? onCustomLeaveTypesChanged,
}) {
  final range = isSameDay(from, to)
      ? L10n.monthDay(from)
      : '${L10n.monthDay(from)} – ${L10n.monthDay(to)}';
  return showGlassSheet<DayExtraSelection>(
    context: context,
    // 与四个选择器同理：不开这个开关，弹层会被压到屏幕的 9/16。
    isScrollControlled: true,
    builder: (sheetContext) => _DayExtraSheet(
      kind: kind,
      range: range,
      dayCount: dayCount,
      existingMinutes: existingMinutes,
      fullDayMinutes: fullDayMinutes,
      hasExisting: hasExisting,
      initialLeaveKind: initialLeaveKind,
      initialNote: initialNote,
      customLeaveTypes: customLeaveTypes,
      onCustomLeaveTypesChanged: onCustomLeaveTypesChanged,
    ),
  );
}

class _DayExtraSheet extends StatefulWidget {
  const _DayExtraSheet({
    required this.kind,
    required this.range,
    required this.dayCount,
    required this.existingMinutes,
    required this.fullDayMinutes,
    required this.hasExisting,
    required this.initialLeaveKind,
    required this.initialNote,
    required this.customLeaveTypes,
    required this.onCustomLeaveTypesChanged,
  });

  final DayExtraKind kind;
  final String range;
  final int dayCount;
  final int? existingMinutes;
  final int? fullDayMinutes;
  final bool hasExisting;
  final String? initialLeaveKind;
  final String? initialNote;
  final List<String> customLeaveTypes;
  final ValueChanged<List<String>>? onCustomLeaveTypesChanged;

  @override
  State<_DayExtraSheet> createState() => _DayExtraSheetState();
}

class _DayExtraSheetState extends State<_DayExtraSheet> {
  late bool _fullDay;
  bool _halfDay = false;
  late int _minutes;
  String? _leaveKind;
  late final TextEditingController _noteCtrl;
  late List<String> _customTypes;

  bool get _isLeave => widget.kind == DayExtraKind.leave;

  /// 「整天」要有得算：单日需要知道班次时长；多日按每天各自的时长算。
  /// 单日的休息日 / 空白表没有时长 —— 那时候不显示「整天」，免得选了等于没记。
  bool get _canFullDay => widget.fullDayMinutes != null || widget.dayCount > 1;

  /// 「半天」的分钟数：单日按班次时长的一半，多日按 4 小时这个常见档。
  int get _halfMinutes => ((widget.fullDayMinutes ?? 480) ~/ 2).clamp(30, 1440);

  @override
  void initState() {
    super.initState();
    final existing = widget.existingMinutes;
    _fullDay = existing == null && _isLeave && _canFullDay;
    _minutes = existing ??
        widget.fullDayMinutes ??
        (_isLeave ? 480 : 120);
    _leaveKind = _isLeave ? widget.initialLeaveKind : null;
    _noteCtrl = TextEditingController(text: widget.initialNote ?? '');
    _customTypes = List<String>.of(widget.customLeaveTypes);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  void _selectFullDay() => setState(() {
        _fullDay = true;
        _halfDay = false;
      });

  void _selectHalfDay() => setState(() {
        _fullDay = false;
        _halfDay = true;
        _minutes = _halfMinutes;
      });

  void _selectMinutes(int minutes) => setState(() {
        _fullDay = false;
        _halfDay = false;
        _minutes = minutes;
      });

  void _toggleKind(String key) => setState(() {
        // 再点一次已选中的类型 = 取消选择（类型本来就可以不选）。
        _leaveKind = _leaveKind == key ? null : key;
      });

  void _step(int delta) => setState(() {
        // 整天状态下第一次点加减，从「当天班次时长」起步；其余情况从当前值走。
        final base = _fullDay ? (widget.fullDayMinutes ?? _minutes) : _minutes;
        _fullDay = false;
        _halfDay = false;
        _minutes = (base + delta).clamp(30, 1440);
      });

  Future<void> _addCustomType() async {
    final name = await showGlassDialog<String>(
      context: context,
      builder: (_) => _AddLeaveTypeDialog(existing: _customTypes),
    );
    if (name == null || !mounted) return;
    if (!_customTypes.contains(name)) {
      setState(() => _customTypes = [..._customTypes, name]);
      widget.onCustomLeaveTypesChanged?.call(_customTypes);
    }
    setState(() => _leaveKind = customLeaveKindKey(name));
  }

  Future<void> _removeCustomType(String name) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: L10n.leaveKindDeleteTitle,
        content: Text(L10n.leaveKindDeleteBody),
        actions: [
          GlassActionButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            label: L10n.cancel,
          ),
          const SizedBox(width: AppTokens.spaceSm),
          GlassActionButton(
            variant: GlassActionVariant.danger,
            onPressed: () => Navigator.pop(dialogContext, true),
            label: L10n.delete,
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _customTypes = _customTypes.where((n) => n != name).toList();
      if (_leaveKind == customLeaveKindKey(name)) _leaveKind = null;
    });
    widget.onCustomLeaveTypesChanged?.call(_customTypes);
  }

  DayExtraSelection _result() {
    final note = _noteCtrl.text.trim();
    final noteOrNull = note.isEmpty ? null : note;
    if (_fullDay) {
      return DayExtraSelection.fullDay(
          leaveKind: _leaveKind, note: noteOrNull);
    }
    return DayExtraSelection.minutes(
      _minutes,
      leaveKind: _leaveKind,
      note: noteOrNull,
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppTokens.inkMuted(context);
    final primary = Theme.of(context).colorScheme.primary;
    final quick = _isLeave
        ? const [60, 120, 240, 480]
        : const [60, 120, 180, 240, 480];

    // 键盘弹起来时面板要整体上移（底部弹层那层布局不看 viewInsets，见
    // `shift_color_picker.dart` 的说明与 AGENTS.md 第 6 条）。不弹时这里是 0 高，
    // 与加备注之前逐像素相同。
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: GlassSheetPanel(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassSheetHeader(
                title: _isLeave ? L10n.leave : L10n.overtime,
                subtitle: widget.range,
              ),
              // 头部以下才加左右内边距 —— 与「排班时段」弹层同一条：包住整层会让
              // 头部被二次内缩、分隔线比别的弹层窄 16dp。
              //
              // **必须能滚**：200×400 的小窗里这列内容约 570dp，固定高度会直接溢
              // 出 236px（工装小窗那一屏当场报红）。与时段弹层同样是
              // `Flexible` + 滚动容器。
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg,
                      AppTokens.spaceSm, AppTokens.spaceLg, AppTokens.spaceLg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isLeave ? L10n.leaveHint : L10n.overtimeHint,
                        style: AppTokens.microText.copyWith(color: muted),
                      ),
                      if (_isLeave) ...[
                        const SizedBox(height: AppTokens.spaceMd),
                        Text(L10n.leaveKindTitle,
                            style: AppTokens.labelSecondary
                                .copyWith(color: muted)),
                        const SizedBox(height: AppTokens.spaceXs),
                        _leaveKindChips(primary),
                        const SizedBox(height: AppTokens.spaceXs),
                        Text(
                          _customTypes.isEmpty
                              ? L10n.leaveKindHint
                              : '${L10n.leaveKindHint} · ${L10n.leaveKindLongPressHint}',
                          style: AppTokens.microText.copyWith(color: muted),
                        ),
                      ],
                      const SizedBox(height: AppTokens.spaceMd),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: [
                          if (_isLeave && _canFullDay)
                            GlassChoiceChip(
                              label: L10n.fullDay,
                              color: primary,
                              selected: _fullDay,
                              onTap: _selectFullDay,
                            ),
                          if (_isLeave)
                            GlassChoiceChip(
                              label: L10n.halfDay,
                              color: primary,
                              selected: _halfDay,
                              onTap: _selectHalfDay,
                            ),
                          for (final m in quick)
                            GlassChoiceChip(
                              label: L10n.durationText(m),
                              color: primary,
                              selected: !_fullDay && !_halfDay && _minutes == m,
                              onTap: () => _selectMinutes(m),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceLg),
                      Row(
                        children: [
                          GlassPill(
                            onTap: () => _step(-30),
                            child: const AppIcon(Icons.remove_outlined),
                          ),
                          Expanded(
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _fullDay
                                      ? L10n.fullDay
                                      : L10n.durationText(_minutes),
                                  style: AppTokens.sectionTitle,
                                ),
                              ),
                            ),
                          ),
                          GlassPill(
                            onTap: () => _step(30),
                            child: const AppIcon(Icons.add_outlined),
                          ),
                        ],
                      ),
                      if (widget.dayCount > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: AppTokens.spaceSm),
                          child: Text(
                            L10n.statsDays(widget.dayCount),
                            textAlign: TextAlign.center,
                            style: AppTokens.microText.copyWith(color: muted),
                          ),
                        ),
                      const SizedBox(height: AppTokens.spaceLg),
                      GlassField(
                        label: L10n.note,
                        child: TextField(
                          controller: _noteCtrl,
                          maxLength: 40,
                          maxLines: 1,
                          textInputAction: TextInputAction.done,
                          style: AppTokens.rowPrimary,
                          decoration: _noteDecoration(context, primary).copyWith(
                            hintText: L10n.noteHint,
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceLg),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: [
                          if (widget.hasExisting)
                            GlassActionButton(
                              variant: GlassActionVariant.danger,
                              label: L10n.clear,
                              onPressed: () => Navigator.pop(
                                  context, const DayExtraSelection.clear()),
                            ),
                          GlassActionButton(
                            variant: GlassActionVariant.primary,
                            label: L10n.confirm,
                            onPressed: () => Navigator.pop(context, _result()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 备注框的装饰：**在实心白面板上也要看得见**。
  ///
  /// `glassInputDecoration` 的填充与描边都是「白上白」—— 编辑器那页靠卡片自身的
  /// 浅灰底把框衬出来，而这个弹层是 `solid:true` 的白面板，直接用等于画了个隐形框
  /// （2026-11-17 出图第一版就是这样）。这里改用与未选中 chip 同一套配方：
  /// 主色 6% 填充 + 白描边压到 85%，既看得见又不抢眼。
  InputDecoration _noteDecoration(BuildContext context, Color primary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusM),
      borderSide: BorderSide(
        color: AppTokens.glassBorder(isDark)
            .withValues(alpha: isDark ? 0.30 : 0.85),
      ),
    );
    return glassInputDecoration(context).copyWith(
      fillColor: primary.withValues(alpha: 0.06),
      border: border,
      enabledBorder: border,
    );
  }

  /// 请假类型的选择条：内置五类 + 自定义 + 「＋ 自定义」。
  ///
  /// 自定义类型长按删除 —— 删除**不动历史记录**（记录里存的是名字），确认弹窗
  /// 里写明了这一点。
  Widget _leaveKindChips(Color primary) {    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: [
        for (final key in kBuiltInLeaveKindKeys)
          GlassChoiceChip(
            label: L10n.leaveKindLabel(key)!,
            color: primary,
            selected: _leaveKind == key,
            onTap: () => _toggleKind(key),
          ),
        for (final name in _customTypes)
          GlassChoiceChip(
            label: name,
            color: primary,
            selected: _leaveKind == customLeaveKindKey(name),
            onTap: () => _toggleKind(customLeaveKindKey(name)),
            onLongPress: () => _removeCustomType(name),
          ),
        GlassChoiceChip(
          label: L10n.leaveKindAdd,
          color: primary,
          selected: false,
          onTap: _addCustomType,
        ),
      ],
    );
  }
}

/// 给自定义请假类型起名的小弹窗。返回 trim 过的名字；取消返回 null。
class _AddLeaveTypeDialog extends StatefulWidget {
  const _AddLeaveTypeDialog({required this.existing});

  final List<String> existing;

  @override
  State<_AddLeaveTypeDialog> createState() => _AddLeaveTypeDialogState();
}

class _AddLeaveTypeDialogState extends State<_AddLeaveTypeDialog> {
  final TextEditingController _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = L10n.leaveKindNameHint);
      return;
    }
    // 名字进库时是 `custom:<name>`，而键存在同一个 text 列里 —— 冒号会让它
    // 读回来时错位，所以不让它出现在名字里。
    if (name.contains(':')) {
      setState(() => _error = L10n.leaveKindNameHint);
      return;
    }
    if (widget.existing.contains(name)) {
      // 重名就直接用已有的那一条，不再建第二个同名的。
      Navigator.pop(context, name);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: L10n.leaveKindAddTitle,
      content: GlassField(
        label: L10n.leaveKindTitle,
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: 8,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          style: AppTokens.rowPrimary,
          decoration: glassInputDecoration(context).copyWith(
            hintText: L10n.leaveKindNameHint,
            counterText: '',
            errorText: _error,
          ),
        ),
      ),
      actions: [
        GlassActionButton(
          onPressed: () => Navigator.pop(context),
          label: L10n.cancel,
        ),
        const SizedBox(width: AppTokens.spaceSm),
        GlassActionButton(
          variant: GlassActionVariant.primary,
          onPressed: _submit,
          label: L10n.confirm,
        ),
      ],
    );
  }
}
