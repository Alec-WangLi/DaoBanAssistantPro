import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'app_icon.dart';

/// 通用玻璃弹窗：玻璃容器 + 主色标题条 + 内容 + 底部操作按钮。
///
/// 用于统一各处的弹窗风格（待办、闹钟、确认、日志等）。
/// [showClose] 为 true 时，标题栏右上角显示玻璃 ✕ 关闭按钮（适合单操作弹窗）。
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.showClose = false,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusXL),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(AppTokens.radiusS),
                  ),
                ),
                const SizedBox(width: AppTokens.gapIconTextLg),
                Expanded(
                  child: Text(
                    title,
                    style: AppTokens.dialogTitle,
                  ),
                ),
                if (showClose) const _GlassCloseButton(),
              ],
            ),
            const SizedBox(height: 16),
            // 内容过高时滚动而不是溢出。上限取弹窗自己的预算减去标题行
            // 与按钮行 —— `Dialog` 的 insetPadding 已被 LayoutBuilder 扣掉。
            // 弹窗本来矮时不会因此被撑高（外层 Column 是 min）。
            LayoutBuilder(
              builder: (context, constraints) => ConstrainedBox(
                constraints:
                    BoxConstraints(maxHeight: constraints.maxHeight - 100),
                child: SingleChildScrollView(child: content),
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

/// 标题栏右上角的玻璃圆形 ✕ 关闭按钮。
class _GlassCloseButton extends StatelessWidget {
  const _GlassCloseButton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.pop(context),
        child: Ink(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppTokens.glassTint(isDark, true),
            ),
            border: Border.all(color: AppTokens.glassBorder(isDark)),
          ),
          child: AppIcon(Icons.close_outlined,
              size: AppTokens.iconMd, color: onSurface),
        ),
      ),
    );
  }
}
