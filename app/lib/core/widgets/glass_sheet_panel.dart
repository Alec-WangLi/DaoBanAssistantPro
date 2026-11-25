// app/lib/core/widgets/glass_sheet_panel.dart
//
// **底部弹层的统一外壳**：玻璃面板 + 拖拽把手（下拉关闭的抓手）。
//
// 为什么要有这一件：把手原先长在 `GlassSheetHeader` 里，于是「用了那个头」的
// 七个弹层有把手，时间 / 日期 / 月份 / 年份四个选择器没有 —— 用户 2026-11-25
// 一眼看出「有的有，有的没有」。把手是**弹层这个形态本身的暗示**，不该跟标题
// 走；收进外壳之后，新弹层只要用它就自动有，想漏也漏不掉。
//
// **只管两样**：面板配方（`solid` + 外边距 `spaceMd` + 圆角 `radiusXL`，全 app
// 的弹层本来就是这个，11 处逐字重复，E19）与那只把手。`SafeArea` 仍留在各弹层
// 自己的 `child` 里 —— 有的弹层要 `SafeArea(top: false)`（打赏），统一收进来
// 反而要开一个口子。
//
// 尺寸写死在这里的：把手 36×4、居中、`inkMuted` 35%。36 落在 4px 栅格上但
// `AppTokens` 没有这一档，与 `GlassSheetHeader` 原来那份是同一个决定
// （`design_tokens_test` 也不扫 `Container(width:)`）。
//
// ⚠️ **内容必须用 `Flexible` 包住、不能直接塞进 Column**：Column 给非弹性子件
// 的是**无界高度**，而几个选择器在 `LayoutBuilder` 里按 `maxHeight` 算滚轮
// 高度（`(constraints.maxHeight - 106).clamp(...)`）—— 拿到 infinity 会被
// clamp 到上限，矮屏直接溢出。Flexible 保住有界约束。
import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../glass/glass.dart';

/// 把手的 Key —— 行为用例靠它找「恰好一只」。
const Key kGlassSheetHandleKey = ValueKey('glass-sheet-handle');

class GlassSheetPanel extends StatelessWidget {
  const GlassSheetPanel({super.key, required this.child});

  /// 弹层自己的内容（通常是一层 `SafeArea`）。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      solid: true,
      margin: const EdgeInsets.all(AppTokens.spaceMd),
      borderRadius: const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
                top: AppTokens.spaceSm, bottom: AppTokens.gapHair),
            child: Center(
              child: Container(
                key: kGlassSheetHandleKey,
                width: 36,
                height: AppTokens.spaceXs,
                decoration: BoxDecoration(
                  // 两档主题下都从 `onSurface` 派生 —— 写死一个灰会在某一档
                  // 读不出来（与 `GlassSheetHeader` 原来那条同一个理由）。
                  color: AppTokens.inkMuted(context).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppTokens.gapHair),
                ),
              ),
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}
