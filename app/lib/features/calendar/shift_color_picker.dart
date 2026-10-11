// app/lib/features/calendar/shift_color_picker.dart
//
// 班次配色的那一层：预览 + 两颗真的日历小样 + 16 颗预设 + 十六进制输入 + 确定/取消。
//
// ## 为什么它要单独一个文件
//
// 原来这一层是 `schedule_editor_screen.dart` 里 `_pickColor` 的一个内联 `Wrap`
// —— 点一颗就 `pop` 关窗。加了输入框与方盘之后它有三百行上下，留在编辑器里会把
// 那一页淹掉。搬出来之后，编辑器只剩「把当前色传进来、把结果写回」两件事。
//
// ## 为什么「确定」被钉在底部、不在滚动区里
//
// 小窗（200×400）里整层装不下，内容必须能滚。但**动作按钮绝不能跟着滚走** ——
// `GlassDialog` 那次「正文被按钮拦腰切断 / 按钮画在屏幕上却点不到」的教训
// （见 `AGENTS.md`）就是这个形状。所以动作行是 `Column` 的固定一格，
// 滚动只发生在它上面那一格里。
//
// ## 一处与旧版不同的交互
//
// 旧版是「点一颗预设 = 立即应用并关窗」。加了输入框与方盘之后，「点一下就提交」
// 与「拖着调」混在一层里会有歧义，所以这一版统一成**选完点「确定」**（规格 §5）。
import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/hex_color.dart';
import '../../core/l10n.dart';
import '../../core/shift_palette.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/glass/glass.dart';

/// 打开班次配色层。
///
/// 返回用户选定的**不透明 ARGB**；取消 / 点外面关掉返回 `null`。
/// [current] 是当前色（**可能不在盘里** —— `0xFF5B7FFF` 那个默认色就不在任何一版
/// 盘里，那时一颗预设都不高亮，但预览与小样照常显示它）。
/// [sampleLabel] 是画在日历小样上的字（班次简称），不给就画一个「班」。
Future<int?> showShiftColorPicker(
  BuildContext context, {
  required int current,
  String? sampleLabel,
}) {
  return showGlassSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => ShiftColorPickerBody(
      current: current,
      sampleLabel: sampleLabel,
    ),
  );
}

class ShiftColorPickerBody extends StatefulWidget {
  const ShiftColorPickerBody({
    super.key,
    required this.current,
    this.sampleLabel,
  });

  final int current;
  final String? sampleLabel;

  @override
  State<ShiftColorPickerBody> createState() => _ShiftColorPickerBodyState();
}

class _ShiftColorPickerBodyState extends State<ShiftColorPickerBody> {
  /// 当前选中的颜色。**这是唯一真源** —— 预览、小样、预设的选中描边都由它推。
  late int _color = widget.current;

  late final TextEditingController _hexCtrl =
      TextEditingController(text: formatHexColor(widget.current));

  /// 输入框里那串现在解析不出来。只影响输入框自己的颜色，**不碰 [_color]**。
  bool _hexBad = false;

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _setColor(int c) {
    setState(() {
      _color = c;
      _hexBad = false;
      _hexCtrl.text = formatHexColor(c);
    });
  }

  /// 输入框每次变动都走这里。**解析不出来就什么都不改** —— 保留上一次的有效色，
  /// 只把输入框转成警示色。这条有用例钉着（`shift_color_picker_test.dart`）。
  void _onHexChanged(String s) {
    final c = parseHexColor(s);
    setState(() {
      _hexBad = c == null;
      if (c != null) _color = c;
    });
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = AppTokens.inkMuted(context);

    // 键盘弹起来的时候那截高度不能让面板顶出屏幕 —— 与 v0.7.3 那个坑同一类。
    final maxH = MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom -
        AppTokens.spaceMd * 2;

    return GlassPanel(
      solid: true,
      margin: const EdgeInsets.all(AppTokens.spaceMd),
      borderRadius: const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg,
                    AppTokens.spaceLg, AppTokens.spaceLg, AppTokens.spaceSm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(L10n.shiftColor, style: AppTokens.titleStrong),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg, 0,
                      AppTokens.spaceLg, AppTokens.spaceMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _previewRow(context, onSurface),
                      const SizedBox(height: AppTokens.spaceLg),
                      Text(L10n.shiftColorPreview,
                          style:
                              AppTokens.microText.copyWith(color: muted)),
                      const SizedBox(height: AppTokens.spaceSm),
                      _sampleRow(context),
                      const SizedBox(height: AppTokens.spaceLg),
                      _presetGrid(context, onSurface),
                    ],
                  ),
                ),
              ),
              _actionsRow(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 当前色一颗大圆点 + 颜色值输入框。
  Widget _previewRow(BuildContext context, Color onSurface) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Color(_color),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTokens.glassBorder(
                  Theme.of(context).brightness == Brightness.dark),
            ),
          ),
        ),
        const SizedBox(width: AppTokens.spaceMd),
        Expanded(
          child: TextField(
            controller: _hexCtrl,
            onChanged: _onHexChanged,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            style: AppTokens.rowPrimary.copyWith(color: onSurface),
            decoration: glassInputDecoration(context, L10n.shiftColorHex)
                .copyWith(
              errorText: _hexBad ? L10n.shiftColorCustomHint : null,
            ),
          ),
        ),
      ],
    );
  }

  /// 两颗**真的**日历小样：浅色卡一颗、深色卡一颗，走的是与日历格子完全同一套
  /// 配方（14% 淡染 + 45% 描边 + `inkFor` 的字）。用户自己挑的颜色好不好看，
  /// 在这里当场看得见 —— 规格 §4 末尾那条拍板（不拦你，但也不让你蒙着选）就是它。
  Widget _sampleRow(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _sampleChip(context, kShiftCardAppLight)),
        const SizedBox(width: AppTokens.spaceMd),
        Expanded(child: _sampleChip(context, kShiftCardAppDark)),
      ],
    );
  }

  Widget _sampleChip(BuildContext context, int card) {
    final fill = Color(compoundOver(_color, card, kShiftChipTintAlpha));
    final stroke = Color(compoundOver(_color, card, kShiftChipStrokeAlpha));
    return Container(
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppTokens.radiusS),
        border: Border.all(color: stroke),
      ),
      child: Text(
        widget.sampleLabel ?? '班',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTokens.labelSecondary.copyWith(color: AppTokens.inkFor(stroke, fill)),
      ),
    );
  }

  Widget _presetGrid(BuildContext context, Color onSurface) {
    return Wrap(
      spacing: AppTokens.spaceLg,
      runSpacing: AppTokens.spaceLg,
      children: [
        for (var i = 0; i < kShiftPalette.length; i++)
          GestureDetector(
            onTap: () => _setColor(kShiftPalette[i]),
            child: Container(
              key: ValueKey('shift-preset-$i'),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Color(kShiftPalette[i]),
                shape: BoxShape.circle,
                border: _color == kShiftPalette[i]
                    ? Border.all(color: onSurface, width: 3)
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  /// 动作行：**钉在面板底部**，不随上面那一格滚动（见文件头）。
  /// 形态照 `GlassDialog` 那一套（`Align(centerRight)` 套 `Wrap`，两层缺一不可）。
  Widget _actionsRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg, 0,
          AppTokens.spaceLg, AppTokens.spaceLg),
      child: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceSm,
          children: [
            GlassActionButton(
              onPressed: () => Navigator.pop(context),
              label: L10n.cancel,
            ),
            GlassActionButton(
              variant: GlassActionVariant.primary,
              onPressed: () => Navigator.pop(context, _color),
              label: L10n.confirm,
            ),
          ],
        ),
      ),
    );
  }
}
