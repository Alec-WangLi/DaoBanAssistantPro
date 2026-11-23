// app/lib/features/stats/stats_period_header.dart
//
// 统计页顶部的期间条：月/年分段器 + ‹ 标题 › + 导出 / 今天。
//
// 2026-11-23 用户三条反馈里两条落在这块：
//   ① 年视图的年份只能点箭头切 → 标题本身变成可点入口（月视图开月份弹层、
//      年视图开年份弹层，尾部给一颗 expand_more 作 D7 的「点开」暗示）；
//   ② 箭头没有触觉、颜色发暗 → 触觉统一挂在 `_StatsScreenState._setPeriod`
//      （一次期间变化恰好一记），箭头改成 44dp 的强调档玻璃钮并**显式给图标色**。
//
// **「发暗」的根因不是玻璃，是图标色**：根主题的 `iconTheme` 只写了 size，
// 裸 `AppIcon` 的颜色会落到 `IconThemeData.fallback` 的纯黑 —— 深色下就是黑压黑。
// 这次所有图标一律显式取色；浅色下用 `solidAccent`（压过的主色，对白玻璃够 3:1），
// 深色下用 `onSurface`（近白）。
//
// 从 `stats_screen.dart` 拆出来是 E14 的要求（那个文件超了 800 行）。
import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/layout.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/glass_pill.dart';
import '../../core/widgets/glass_segment.dart';

class StatsPeriodHeader extends StatelessWidget {
  const StatsPeriodHeader({
    super.key,
    required this.yearMode,
    required this.title,
    required this.onModeChanged,
    required this.onPrev,
    required this.onNext,
    required this.onPickPeriod,
    required this.onExport,
    required this.onToday,
  });

  final bool yearMode;
  final String title;
  final ValueChanged<int> onModeChanged;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPickPeriod;
  final VoidCallback onExport;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = AppTokens.inkMuted(context);
    final arrowInk = isDark
        ? Theme.of(context).colorScheme.onSurface
        : AppTokens.solidAccent(Theme.of(context).colorScheme.primary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassSegment(
          count: 2,
          selectedIndex: yearMode ? 1 : 0,
          onSelected: onModeChanged,
          itemBuilder: (i, selected) => Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  i == 0
                      ? Icons.calendar_view_month_outlined
                      : Icons.date_range_outlined,
                  size: AppTokens.iconSm,
                  // GlassSegment 只把**文字**包成白色，图标不跟着变 ——
                  // 选中格必须显式给白，否则是实心主色块上的灰图标
                  // （v0.11.21 同类事故，对比度约 1.5:1）。
                  color: selected ? Colors.white : muted,
                ),
                const SizedBox(width: AppTokens.gapIconText),
                Text(
                  i == 0 ? L10n.statsMonth : L10n.statsYear,
                  style: AppTokens.labelSecondary.copyWith(
                    color: selected ? Colors.white : muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Row(
          children: [
            _stepPill(context, Icons.chevron_left_outlined, onPrev, arrowInk),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: GlassPill(
                onTap: onPickPeriod,
                emphasis: true,
                height: 44,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(title, style: AppTokens.titleStrong),
                      ),
                    ),
                    const SizedBox(width: AppTokens.spaceXs),
                    AppIcon(Icons.expand_more,
                        size: AppTokens.iconSm, color: muted),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            _stepPill(context, Icons.chevron_right_outlined, onNext, arrowInk),
          ],
        ),
        const SizedBox(height: AppTokens.spaceSm),
        // 靠右用 `Row` + `mainAxisAlignment.end`，**不要用 `Wrap` / `Align`**：
        // 它们给子件的是**有界宽度**，而 `GlassPill` 里的 Container 带 `alignment`、
        // 在有界约束下会撑满整行（出图里那颗「导出」就这样成了一条通栏按钮，
        // 2026-11-17 出图当场看见）。Row 给非 flex 子件无界宽度，pill 才会按内容
        // 收缩；窄屏（<360）把「导出」的文字也收掉，只留图标 —— 与「今天」同理。
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Tooltip(
              message: L10n.statsExport,
              child: GlassPill(
                onTap: onExport,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(Icons.file_download_outlined,
                        size: AppTokens.iconMd, color: muted),
                    if (!AppLayout.of(context).isNarrow) ...[
                      const SizedBox(width: AppTokens.spaceXs),
                      Text(L10n.statsExport, style: AppTokens.labelStrong),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            GlassPill(
              accent: true,
              onTap: onToday,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppIcon(Icons.today_outlined,
                      size: AppTokens.iconMd, color: Colors.white),
                  const SizedBox(width: AppTokens.spaceXs),
                  Text(
                    yearMode ? L10n.statsThisYear : L10n.statsThisMonth,
                    style: AppTokens.labelStrong.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 左右箭头：20 的图标 + 12×2 的内边距 = 44，命中区正好 44×44（D15）。
  ///
  /// 复用 `GlassPill` 而不是新造一枚圆钮件：圆角 `radiusL`(22) 在 44 高处正好是
  /// 正圆，而新件必然再抄一套玻璃配方（D4 已经有一处「第四套配方」的欠账）。
  Widget _stepPill(
    BuildContext context,
    IconData icon,
    VoidCallback onTap,
    Color ink,
  ) {
    return GlassPill(
      onTap: onTap,
      emphasis: true,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
      child: AppIcon(icon, size: AppTokens.iconMd, color: ink),
    );
  }
}
