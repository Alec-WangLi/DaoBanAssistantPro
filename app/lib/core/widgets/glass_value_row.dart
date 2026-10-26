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
    return GlassPressable(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
          child: Row(
            children: [
              Expanded(
                // 标签允许折两行（设计 §6.4）：这一行**不允许**出现省略号。
                child: Text(label, maxLines: 2, style: AppTokens.rowPrimary),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Flexible(
                // 值按可用宽度**等比缩小**，不省略 —— 它短、且是这一行的主角。
                // `FittedBox(scaleDown)` 只在装不下时才动手，装得下逐像素不变。
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: valueStyle ??
                        (mutedValue
                            ? AppTokens.rowSecondary.copyWith(color: muted)
                            : AppTokens.labelStrong),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.gapIconText),
              // 默认给一个「点进去」的箭头；时段那两行传自己的尾部（有值时是清空钮）。
              trailing ??
                  Icon(Icons.chevron_right_outlined,
                      size: AppTokens.iconSm, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
