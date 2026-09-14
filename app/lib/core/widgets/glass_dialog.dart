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
        // 给测试一个抓手：断言「操作按钮在面板里」（见 todo_dialog_test.dart
        // 的键盘用例 —— 按钮被挤出面板时，点它只会点到遮罩）。
        key: const Key('glass-dialog-panel'),
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
            // 内容过长时**卡内滚动**，而不是把弹窗撑到屏幕外。
            //
            // 这里曾经是 `LayoutBuilder` + `ConstrainedBox(maxHeight - 100)`：
            // 想给内容留个上限，但 Column 给子组件的是**无界高度** ——
            // `constraints.maxHeight` 是无穷，那个上限根本不生效。于是键盘弹起、
            // 可用高度变小时，内容把底部的操作按钮**挤出面板**：按钮还画在屏幕上，
            // 却已经不在弹窗的可点区域内，手指点下去穿到遮罩上 ——
            // **弹窗关闭、什么都没存**。v0.7.2 真机实测到的「待办填好了点添加 /
            // 点保存没反应、待办也没出现」就是这个（像素采样：面板底边 y≈1486，
            // 而按钮画在 1458~1595）。
            //
            // `Flexible` 让内容只吃「标题行与按钮行之外剩下多少」，不够就在卡内
            // 滚动，底部按钮因此**永远在面板里、永远点得到**。
            Flexible(
              child: SingleChildScrollView(child: content),
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
