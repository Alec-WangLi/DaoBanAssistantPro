import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'glass_title_row.dart';

/// **底部弹层的统一头部** —— 标题行 + 分隔线。
///
/// **把手不在这一件里**（2026-11-25 起）：它搬进了 `GlassSheetPanel`，因为
/// 「有没有把手」不该取决于这一屏有没有标题 —— 时间 / 日期 / 月份 / 年份四个
/// 选择器没有标题头，原来就漏了把手（用户：「有的有，有的没有」）。现在把手
/// 由外壳统一给，这一件只剩标题行与分隔线。
///
/// 标题行本身由 [GlassTitleRow] 统一（与弹窗同源）。此前五个弹层里各写各的
/// 那份头部只画一行标题，**没有弹窗那份主色竖条** —— 用户 2026-10-13 一眼看出
/// 问题：「它那个标题怎么就左对齐了？……看着很容易以为是下面的内容」。
///
/// ## 三件事写死在这里
///
/// 1. **关闭钮一律不给。** 弹窗右上角那颗 ✕（`GlassDialog` 的 `showClose`）在
///    弹层里是多余的 —— 弹层的语义就是「往下拖 / 点遮罩关掉」，多一颗 ✕ 反而
///    让人以为不点它关不掉。[GlassTitleRow] 的 `trailing` 因此恒不传。
/// 2. **副标题槽是给「内容」留的**，不是装饰。调班弹层那行日期区间
///   （`10月5日 – 10月7日 · 3 天`）与时段总览那行「全部日子 / 其余时间…」
///    都在这一槽里 —— 它们回答的是「这次改哪几天 / 现在是什么安排」，丢了就是
///    缺陷（`task-3-brief` 的裁定 3）。
/// 3. **标题走 `titleStrong`（16），不是弹窗的 `dialogTitle`（20）。** 弹窗是
///    居中的模态，弹层是贴底的抽屉 —— 后者的标题不该跟前者的标题一样重。
///    （时段总览那一处此前误用了 `dialogTitle`，本轮统一到 16。）
class GlassSheetHeader extends StatelessWidget {
  const GlassSheetHeader({super.key, required this.title, this.subtitle});

  final String title;

  /// 非空时排在标题下面，用 [AppTokens.labelSecondary] + [AppTokens.inkMuted]。
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      // **必须 stretch。** 弹层自己的 `Column` 有的用 `stretch`、有的用 `start`
      //（时段总览那处是 `start`）—— 靠外层对齐的话，标题会被父层按内容宽度
      // 居中、分隔线也会跟着缩短。自带 `stretch` 与父层怎么对齐无关。
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg, AppTokens.spaceSm,
              AppTokens.spaceLg, AppTokens.spaceSm),
          child: GlassTitleRow(
            title: title,
            // 裸 `Text` 就行 —— [GlassTitleRow] 的副标题槽自己把排版（次要说明那一档
            // 字号 + 次要文字明度）**叠在环境样式之上**（`DefaultTextStyle.merge`），
            // 字体族因此跟得住、工装里不会渲成豆腐块。
            subtitle: subtitle == null ? null : Text(subtitle!),
          ),
        ),
        // 全 app 那个分隔线配方（`const Divider(height: 1)`）。
        const Divider(height: 1),
      ],
    );
  }
}
