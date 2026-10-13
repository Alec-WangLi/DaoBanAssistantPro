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
              //
              // ⚠️ **必须是 `DefaultTextStyle.merge`，不能是 `DefaultTextStyle`。**
              // 后者是**替换**环境那层样式，于是主题的 `fontFamily` /
              // `fontFamilyFallback` 会一起丢掉（落到 `fontFamily: null`）。生产上
              // 几乎看不出（本 App 没设自定义字体族，`null` 落回平台默认），但**工装
              // 里一望即知**：字体是 `visual_harness` 用 `textTheme.apply(fontFamily: …)`
              // 注入的，丢了就渲染成**豆腐块** —— 实测 `11_override_picker_dark` 那行
              // 日期区间整行成了方块，而同一屏的标题（`Text` 会与祖先 merge）照旧正常。
              // `merge` 保留环境那层、再叠上副标题的角色令牌，字体族因此跟得住。
              DefaultTextStyle.merge(
                style: AppTokens.labelSecondary
                    .copyWith(color: AppTokens.inkMuted(context)),
                child: subtitle!,
              ),
            ],
          );
    return Row(
      // **有副标题时竖条与「标题第一行」对齐**（`start`），没有副标题时保持默认的
      // `center`。
      //
      // 默认的 `center` 是对**整个「标题 + 副标题」块**居中：副标题只有一行时肉眼看
      // 不出问题（与 `start` 差不到 1px），但**折成两行时竖条会被压到第二行旁边**
      // （实测 `28_calendar_timeline` 那行「没被时段覆盖的日子…」折两行，竖条离开了
      // 标题）。
      //
      // **无副标题那一档必须逐像素不变** —— 那是弹窗在走（`GlassDialog` 从不传
      // 副标题），单行标题下 `center` 与 `start` 差的那不到 1px 会改掉二十来个弹窗
      // 的图，所以这里写成条件式、不是一律 `start`。
      crossAxisAlignment: subtitle == null
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
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
