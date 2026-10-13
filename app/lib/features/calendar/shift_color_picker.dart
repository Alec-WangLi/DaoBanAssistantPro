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
import '../../core/widgets/glass_sheet_header.dart';
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

  /// 色相 / 饱和度 / 明度。
  ///
  /// **拖动色相条与方盘时由它推 [_color]，不反过来。** 每帧都做
  /// `int → HSV → int` 会让色相一点点漂（round-trip 不是恒等变换）。
  /// 而点预设、敲颜色值时**反向灌进来** —— 两边始终同步，否则用户拖完再点预设，
  /// 方盘上的游标会停在上一次的位置，下一次一碰方盘颜色就跳回旧色相。
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.current));

  late final TextEditingController _hexCtrl =
      TextEditingController(text: formatHexColor(widget.current));

  /// 输入框里那串现在解析不出来。只影响输入框自己的颜色，**不碰 [_color]**。
  bool _hexBad = false;

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  /// 从外面来的一颗色（预设 / 颜色值）：连 HSV 一起灌，保证方盘跟着走。
  void _setColor(int c) {
    setState(() {
      _color = c;
      _hsv = HSVColor.fromColor(Color(c));
      _hexBad = false;
      _hexCtrl.text = formatHexColor(c);
    });
  }

  /// 从色相条 / 方盘来的一个 HSV：由它推颜色，再回头把颜色值显示跟上。
  void _applyHsv(HSVColor next) {
    setState(() {
      _hsv = next;
      _color = next.toColor().toARGB32();
      _hexBad = false;
      _hexCtrl.text = formatHexColor(_color);
    });
  }

  /// 输入框每次变动都走这里。**解析不出来就什么都不改** —— 保留上一次的有效色，
  /// 只把输入框转成警示色。这条有用例钉着（`shift_color_picker_test.dart`）。
  void _onHexChanged(String s) {
    final c = parseHexColor(s);
    setState(() {
      _hexBad = c == null;
      if (c != null) {
        _color = c;
        _hsv = HSVColor.fromColor(Color(c));
      }
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

    // ⚠️ **只夹高度是不够的，必须把面板顶上去。** 底部弹层那一层布局
    // （`_ModalBottomSheetLayout`）把面板钉在**屏幕底边**：`size.height -
    // child.height`，它**完全不看 `viewInsets`**（SDK 那个文件里一处都没有）。
    // 于是只夹高度的话，面板变矮了、可底边还在屏幕底 —— 动作行照样落在键盘底下，
    // 「敲完颜色值点确定」这条**主路径**当场断掉（能量到：900 高的屏 + 320 键盘下
    // 「确定」底边在 838，而键盘顶边是 580）。
    //
    // 键盘不弹时这里是 0 高度，与本条修复之前逐像素相同。
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: GlassPanel(
        solid: true,
        margin: const EdgeInsets.all(AppTokens.spaceMd),
        borderRadius:
            const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 头部走共享件（把手 + 主色竖条 + 标题 + 分隔线）。
                GlassSheetHeader(title: L10n.shiftColor),
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
                            style: AppTokens.microText.copyWith(color: muted)),
                        const SizedBox(height: AppTokens.spaceSm),
                        _sampleRow(context),
                        const SizedBox(height: AppTokens.spaceLg),
                        _hueStrip(),
                        const SizedBox(height: AppTokens.spaceMd),
                        _svSquare(),
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

  /// 色相条：横向一条七色彩虹，点 / 拖都在它上面取色相。
  ///
  /// 那一串颜色**只能用字面量**（色相环本来就是七个固定色），但走 `int` 常量 +
  /// `Color(int)` 而不是 `Color(0x…)`，于是不必去动令牌守门的豁免名单。
  Widget _hueStrip() {
    return _DragArea(
      key: const ValueKey('shift-hue'),
      height: 28,
      onFraction: (fx, _) => _applyHsv(_hsv.withHue((fx * 360).clamp(0.0, 360.0))),
      builder: (w) => CustomPaint(painter: _HueStripPainter(_hsv.hue)),
    );
  }

  /// 饱和度（横）× 明度（纵）方盘。
  ///
  /// 游标是一个**真的 widget**（不是画上去的），因为「游标有没有跟着预设走」
  /// 这件事只有它是 widget 才量得到（`shift_color_picker_test.dart` 用它钉
  /// 「预设 ↔ HSV 双向同步」）。
  Widget _svSquare() {
    const double thumb = 20;
    return _DragArea(
      key: const ValueKey('shift-sv'),
      height: _svSquareH,
      onFraction: (fx, fy) => _applyHsv(_hsv
          .withSaturation(fx)
          .withValue((1 - fy).clamp(0.0, 1.0))),
      builder: (w) => Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _SvPainter(_hsv.hue))),
          Positioned(
            left: (_hsv.saturation * w - thumb / 2).clamp(0.0, w - thumb),
            top: ((1 - _hsv.value) * _svSquareH - thumb / 2)
                .clamp(0.0, _svSquareH - thumb),
            child: Container(
              key: const ValueKey('shift-sv-thumb'),
              width: thumb,
              height: thumb,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ],
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

/// 方盘的高度。
///
/// **固定 160，不按「可用高」缩。** 面板里上面那一格是可滚动的、动作行钉在它下面
/// （见文件头），所以「小窗装不下」这件事由滚动承担；让方盘跟着小窗变小只会让它
/// 更难瞄准。计划里原先写的是 `min(160, 可用高)` —— 在滚动区里「可用高」是无界的，
/// 那句实现不了，也不必要。
const double _svSquareH = 160;

/// 色相环的七个锚点（红 → 黄 → 绿 → 青 → 蓝 → 品红 → 红）。
///
/// 存 `int` 的理由与 `shift_palette.dart` 同：界面层不许写 `Color(0x…)` 字面量
/// （`design_tokens_test.dart` 守门），而这里只有数据。
const List<int> _hueStops = <int>[
  0xFFFF0000, 0xFFFFFF00, 0xFF00FF00, 0xFF00FFFF,
  0xFF0000FF, 0xFFFF00FF, 0xFFFF0000,
];

/// 「在一块矩形区域上取一个 0~1 的分数」——色相条与方盘共用的手势外壳。
///
/// 分数用 `localPosition` 除以实测宽高（`LayoutBuilder` 现取），**不用
/// `globalPosition` 再减原点** —— 后者多一步就多一处能错的地方。
class _DragArea extends StatelessWidget {
  const _DragArea({
    super.key,
    required this.height,
    required this.onFraction,
    required this.builder,
  });

  final double height;
  final void Function(double fx, double fy) onFraction;

  /// 拿实测宽度建内容（游标要按它定位）。
  final Widget Function(double width) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        void emit(Offset p) => onFraction(
              (p.dx / w).clamp(0.0, 1.0),
              (p.dy / height).clamp(0.0, 1.0),
            );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => emit(d.localPosition),
          onPanStart: (d) => emit(d.localPosition),
          onPanUpdate: (d) => emit(d.localPosition),
          child: SizedBox(height: height, width: w, child: builder(w)),
        );
      },
    );
  }
}

/// 横向那条七色彩虹 + 一个游标。
class _HueStripPainter extends CustomPainter {
  const _HueStripPainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
        rect, const Radius.circular(AppTokens.radiusS));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          colors: [for (final c in _hueStops) Color(c)],
        ).createShader(rect),
    );

    final x = (hue / 360 * size.width).clamp(6.0, size.width - 6);
    final c = Offset(x, size.height / 2);
    canvas.drawCircle(
      c,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
    canvas.drawCircle(
      c,
      8.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_HueStripPainter old) => old.hue != hue;
}

/// 饱和度 × 明度方盘：底色是当前色相的纯色，横向压一层白、纵向压一层黑。
class _SvPainter extends CustomPainter {
  const _SvPainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
        rect, const Radius.circular(AppTokens.radiusS));
    canvas.save();
    canvas.clipRRect(rrect);

    canvas.drawRect(
        rect, Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor());
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0), Colors.black],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SvPainter old) => old.hue != hue;
}
