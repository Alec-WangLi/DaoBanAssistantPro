import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'glass_title_row.dart';

/// **底部弹层的统一头部** —— 拖拽把手 + 标题行 + 分隔线。
///
/// 它替代的是五个弹层里各写各的那份头部（`shift_override_picker` /
/// `profile_screen` 的铃声 / `glass_pickers` 的选项 / `shift_color_picker` /
/// `calendar_screen` 的时段总览）。此前五处都只画一行标题，**没有弹窗那份主色
/// 竖条** —— 用户 2026-10-13 一眼看出问题：「它那个标题怎么就左对齐了？……看着
/// 很容易以为是下面的内容」。标题行本身由 [GlassTitleRow] 统一（与弹窗同源），
/// 这一件只管弹层专属的两样：**把手**（下拉关闭的抓手）与**分隔线**（把标题与
/// 列表内容切开）。
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

  /// 把手的宽与高。
  ///
  /// 36 是**字面量**而不是令牌 —— `AppTokens` 的刻度里没有这一档，而 36 落在
  /// 4px 栅格上、`design_tokens_test` 也不扫 `Container(width:)`；这是有据可查的
  /// 决定（与 `_ClassDot` 的 12dp、信息卡色点同一回事）。高度走 [AppTokens.spaceXs]。
  static const double _handleW = 36;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      // **必须 stretch。** 弹层自己的 `Column` 有的用 `stretch`、有的用 `start`
      //（时段总览那处是 `start`）—— 靠外层对齐的话，把手那层 `Center` 会随父层
      // 收缩到内容宽度、于是把手跑到左边去。自带 `stretch` 与父层怎么对齐无关。
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 拖拽把手：36×4 的圆角条，居中。
        Padding(
          padding: const EdgeInsets.only(
              top: AppTokens.spaceSm, bottom: AppTokens.gapHair),
          child: Center(
            child: Container(
              width: _handleW,
              height: AppTokens.spaceXs,
              decoration: BoxDecoration(
                // **用令牌推进来的颜色、不写死** —— 把手是中性灰条，两档主题
                // 下都从 `onSurface` 派生；写死 `Color(0x…)` 会被令牌守门打红，
                // 且深浅两档下必然有一档读不出来。
                color: AppTokens.inkMuted(context).withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppTokens.gapHair),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg, AppTokens.spaceSm,
              AppTokens.spaceLg, AppTokens.spaceSm),
          child: GlassTitleRow(
            title: title,
            subtitle:
                subtitle == null ? null : Text(subtitle!, style: _subtitleStyle(context)),
          ),
        ),
        // 全 app 那个分隔线配方（`const Divider(height: 1)`）。
        const Divider(height: 1),
      ],
    );
  }

  /// 副标题的排版。
  ///
  /// ⚠️ **不能只往 [GlassTitleRow] 的副标题槽里塞个裸 `Text`。** 那个槽用的是
  /// `DefaultTextStyle(style: …)` —— 它是**替换**、而不是 `DefaultTextStyle.merge`，
  /// 于是**主题那层的 `fontFamily` 会一起被丢掉**。生产上几乎看不出（本 App 没有
  /// 自定义字体族，`fontFamily: null` 落回平台默认，与别处同一个字体），但工装里
  /// 一望即知：字体是 `visual_harness` 用 `textTheme.apply(fontFamily: …)` 注入的，
  /// 掉了就渲染成**豆腐块** —— 实测 `11_override_picker_dark` 那行日期区间整行成了
  /// 方块，而它上面的标题（`Text` 会与祖先 merge）照旧正常，同一屏里两种字。
  ///
  /// 因此在**调用点**先把当前环境那层接住、再叠上副标题的角色令牌，字体族就跟着走了。
  /// （根治是 `glass_title_row.dart` 那行改成 `DefaultTextStyle.merge` —— 那是 Task 2
  /// 的文件，本轮不动，已在 `task-3-report.md` 里单列。）
  TextStyle _subtitleStyle(BuildContext context) =>
      DefaultTextStyle.of(context).style.merge(AppTokens.labelSecondary).copyWith(
          color: AppTokens.inkMuted(context));
}
