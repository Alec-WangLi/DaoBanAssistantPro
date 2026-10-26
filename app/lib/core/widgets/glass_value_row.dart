import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'glass_pressable.dart';

/// 「左边一个标签、右边一个取值、尾巴一个箭头」的一行 —— **手搓 `Row` 而不是
/// `ListTile`**。
///
/// 为什么不用 `ListTile`：它的 `trailing` 在窄窗口里会**吃掉整行宽度** ——
/// `minLeadingWidth`（默认 40）与 `horizontalTitleGap`（默认 16）先拿走一块，
/// 再给 trailing 一个 `ConstrainedBox(maxWidth: 140)`，200 宽的弹层里就超了，
/// 框架直接抛 `Trailing widget consumes the entire tile width`。手搓这版两边都是
/// flex（`Expanded` + `Flexible`）、值用 `FittedBox(scaleDown)` 缩，任何宽度都不溢。
///
/// 这条是**两次踩出来的**：先是排班管理页那条时间线（v0.9.14 工装的小窗那一屏
/// 红了），再是时段弹层里那行 —— 后者到 2026-10-01 才现形，因为那一屏此前**根本
/// 不在屏单里**（补上 `33_span_editor` 的当天它就抛了断言）。
///
/// 点击用 `GestureDetector` 承载（`GlassPressable` **没有 `onTap`**，它只是个
/// 按压缩放的包装）—— 与日历信息卡那行班次同一套写法。
///
/// **默认尾巴是一颗箭头**：这一行的语义是「点开会打开别的东西」（选择器 / 页面 /
/// 弹窗）。要换成别的尾部（例如「清空」钮）就传 [trailing]；要强调「点开是进入
/// 编辑这条内容」而不是「打开别的东西」时，用铅笔的调用点自己传。
class GlassValueRow extends StatelessWidget {
  const GlassValueRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.mutedValue = false,
    this.valueStyle,
    this.trailing,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  /// 值为「未设置」一类占位文案时用次要色。
  final bool mutedValue;

  /// 覆盖默认值样式。默认：`mutedValue ? rowSecondary + 次要色 : labelStrong`。
  ///
  /// 闹钟弹窗的「时间」是那个弹窗的主角（与闹钟列表的大号时间同一档），传
  /// `AppTokens.sectionTitle` 即可 —— 不要为了统一把主数字降到 14。
  final TextStyle? valueStyle;

  /// 行尾控件；不传时画默认箭头。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = AppTokens.inkMuted(context);
    final effectiveValueStyle = valueStyle ??
        (mutedValue
            ? AppTokens.rowSecondary.copyWith(color: muted)
            : AppTokens.labelStrong);
    final labelWidget =
        Text(label, maxLines: 2, style: AppTokens.rowPrimary);
    final valueWidget = Text(
      value,
      maxLines: 1,
      textAlign: TextAlign.right,
      style: effectiveValueStyle,
    );
    final arrow = trailing ??
        Icon(Icons.chevron_right_outlined,
            size: AppTokens.iconSm, color: muted);

    return Semantics(
      button: true,
      child: GlassPressable(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
            // 宽档：标签按自然宽（可折两行），右侧的「值 + 箭头」**贴着内容右缘**
            // 排成一列 —— 别让 `Flexible` 没吃完的份额落到箭头右边（那会在默认
            // 宽度下留出 60~120dp 的死区，三行的值与箭头参差不齐）。
            //
            // 窄档（200dp 的弹窗 / 小窗）：一行塞不下「7 字标签 + 值 + 箭头」，
            // 塞下去的结果是标签被 `maxLines: 2` 硬裁（实测 128dp 宽时 6 处）。
            // 按本仓既有的降级顺序「折行 > 按宽缩小 > 换短串」，这里改成上下两行：
            // 标签整行折，值 + 箭头在第二行贴右。
            //
            // 阈值取 200 而不是「像 HelpEntry 那样 260」：320dp 屏上管理页时间线的
            // 内容宽约 240，260 会把那几行也切成两行（实测整屏 55% 像素变化）——
            // 那里标签与值并排本来就放得下，窄档只该服务真正的小窗弹窗。
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 200) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      labelWidget,
                      const SizedBox(height: AppTokens.gapHair),
                      Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: valueWidget,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTokens.gapIconText),
                          arrow,
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    // 标签**不做弹性子件**：弹性子件没吃满的份额会留在行尾，
                    // 把箭头推到半空。自然宽 + 55% 上限，剩下的全给右边那组。
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth * 0.55),
                      child: labelWidget,
                    ),
                    const SizedBox(width: AppTokens.spaceSm),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: valueWidget,
                            ),
                          ),
                          const SizedBox(width: AppTokens.gapIconText),
                          arrow,
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
