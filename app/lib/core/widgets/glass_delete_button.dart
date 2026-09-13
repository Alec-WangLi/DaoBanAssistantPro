import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../l10n.dart';
import 'app_icon.dart';

/// 统一「删除」按钮：红色调圆形玻璃底 + 删除图标，替换散落的裸删除 IconButton。
class GlassDeleteButton extends StatelessWidget {
  const GlassDeleteButton({
    super.key,
    required this.onPressed,
    this.tooltip,
    this.compact = false,
  });

  final VoidCallback? onPressed;
  final String? tooltip;

  /// 紧凑变体：**只留图标**，没有圆形底色、描边与投影，用在列表行/卡片行尾。
  ///
  /// 完整形态（默认）是个 48pt 的红圆，适合作为一屏的主删除动作；
  /// 放进密集的表单行或列表里会盖过主体内容，这时用紧凑形态降噪。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (compact) {
      return _CompactDeleteButton(tooltip: tooltip, onPressed: onPressed);
    }
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppTokens.danger.withValues(alpha: 0.32),
                  AppTokens.danger.withValues(alpha: 0.12),
                ]
              : [
                  AppTokens.danger.withValues(alpha: 0.15),
                  AppTokens.danger.withValues(alpha: 0.05),
                ],
        ),
        border: Border.all(
          color: AppTokens.danger.withValues(alpha: isDark ? 0.55 : 0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTokens.danger.withValues(alpha: isDark ? 0.28 : 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IconButton(
        tooltip: tooltip ?? L10n.delete,
        onPressed: onPressed,
        icon: const AppIcon(Icons.delete_outlined),
        color: AppTokens.danger,
      ),
    );
  }
}

/// 紧凑删除键：平时中性色，**按住时转危险红**。
///
/// 常驻的 danger 红在一屏 2~5 行的表单里等于每行一个警报，与「简洁 + 玻璃」
/// 的克制基调冲突；但整个去掉红色又丢了「这是危险操作」的提示。折中是
/// 平时中性、按下才转红 —— 危险语义只在该出现的那一刻出现。
///
/// 用 [InkResponse.onHighlightChanged] 而不是 `hoverColor` / `highlightColor`：
/// 后两个改的是水波纹的颜色，图标本身不跟着变。也不用 `IconButton` ——
/// 它在这个 Flutter 版本上不暴露 `onHighlightChanged`。
class _CompactDeleteButton extends StatefulWidget {
  const _CompactDeleteButton({this.tooltip, this.onPressed});

  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  State<_CompactDeleteButton> createState() => _CompactDeleteButtonState();
}

class _CompactDeleteButtonState extends State<_CompactDeleteButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final muted = AppTokens.inkMuted(context);
    return Tooltip(
      message: widget.tooltip ?? L10n.delete,
      child: InkResponse(
        onTap: widget.onPressed,
        onHighlightChanged: (v) {
          if (_pressed != v) setState(() => _pressed = v);
        },
        radius: 18,
        child: SizedBox(
          width: 36,
          height: 36,
          child: AppIcon(
            Icons.delete_outlined,
            size: AppTokens.iconMd,
            color: _pressed ? AppTokens.danger : muted,
          ),
        ),
      ),
    );
  }
}
