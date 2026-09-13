import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 可选中的彩色 chip：一排平铺出来，点一下就选中。
///
/// 用在「选项少、且要一眼看全」的地方（如排班周期里「这一天上什么班」）——
/// 比下拉少一层界面，也比下拉更容易比较各选项的颜色。
///
/// 选中态是色块**实心底**，文字色由 [AppTokens.onSolid] 按底色取 ——
/// 恒定白字在调色板的浅色（橙 2.23:1、绿、灰）上读不出来。
class GlassChoiceChip extends StatelessWidget {
  const GlassChoiceChip({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.semanticsLabel,
  });

  final String label;

  /// 班次色：未选中时作圆点色，选中时作实心底与描边色。
  final Color color;

  final bool selected;
  final VoidCallback onTap;

  /// 读屏用的完整标签；缺省时用 [label]。
  final String? semanticsLabel;

  /// 视觉高度。
  static const double visualHeight = 32;

  /// 外层补的竖向内边距：把**命中区**补到 44，视觉上仍是 32 的小 chip。
  /// 手指够得着，也为以后的车机留余量。
  // design-tokens-ignore: 命中区补到 44dp 触摸目标的推导值，不是设计间距
  static const double _hitPad = 6;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel ?? label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusS),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: _hitPad),
            child: Container(
              height: visualHeight,
              padding:
                  const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
              decoration: BoxDecoration(
                color: selected ? color : primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppTokens.radiusS),
                border: Border.all(
                  color: selected
                      ? color
                      : AppTokens.glassBorder(isDark)
                          .withValues(alpha: isDark ? 0.30 : 0.85),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!selected) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: AppTokens.spaceSm),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTokens.rowSecondary.copyWith(
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AppTokens.onSolid(color)
                          : AppTokens.inkMuted(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
