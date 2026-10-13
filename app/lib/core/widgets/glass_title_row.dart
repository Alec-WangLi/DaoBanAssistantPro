import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 弹窗 / 弹层共用的标题行 —— 全 app 唯一实现。
///
/// 一行结构：`主色竖条 + 间距 + 标题（+ 可选副标题）+ 可选尾部控件`。
/// 从前这份结构只长在 `GlassDialog` 里，底部弹层各自另写标题；v0.12.0 把它抽出来，
/// 好让两边复用同一份。**抽出来本身不改观感** —— `GlassDialog` 换用它之后逐像素
/// 不变（竖条尺寸与间距一字未动）。
///
/// 竖条与间距的数值照抄 `glass_dialog.dart` 原来那一份：`4 × 18` 主色圆角条
/// （[AppTokens.radiusS]）+ [AppTokens.gapIconTextLg]。
class GlassTitleRow extends StatelessWidget {
  const GlassTitleRow({
    super.key,
    required this.title,
    this.titleStyle,
    this.subtitle,
    this.trailing,
  });

  final String title;

  /// 标题用的排版角色。默认 [AppTokens.titleStrong]；弹窗传 [AppTokens.dialogTitle]。
  final TextStyle? titleStyle;

  /// 可空的副标题：非空时排在标题下面、间距 [AppTokens.spaceXs]、排版
  /// [AppTokens.labelSecondary] + [AppTokens.inkMuted]。给了才画那一行。
  final Widget? subtitle;

  /// 可空的尾部控件（弹窗传关闭钮；弹层一律不传）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final titleText = Text(title, style: titleStyle ?? AppTokens.titleStrong);
    // 没有副标题时**直接**放这一句 Text（不套 Column）—— 与 `GlassDialog`
    // 原来那一份逐字一致，多包一层 Column 会让行高/基线有微小偏移。
    final Widget headline = subtitle == null
        ? titleText
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleText,
              const SizedBox(height: AppTokens.spaceXs),
              // 副标题的排版由本件统一给（调用点传裸 `Text` 也行）：次要说明
              // 那一档字号 + 次要文字明度，全 app 一处。
              DefaultTextStyle(
                style: AppTokens.labelSecondary
                    .copyWith(color: AppTokens.inkMuted(context)),
                child: subtitle!,
              ),
            ],
          );
    return Row(
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
        Expanded(child: headline),
        if (trailing != null) trailing!,
      ],
    );
  }
}
