import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 带标签的输入框：**标签画在框的上方，位置/字号/颜色全由我们自己控制**。
///
/// ## 为什么不用 Material 的浮动标签（`labelText`）
///
/// 2026-10-15 用户真机（小米，MiSans 字体）截图显示：那个浮动标签被**压成了半截**
/// （量过：宽度正常、高度只剩六成多，看着像被框线切了一半）。本地查下来的结论：
///
///   · 工装里**一切正常** —— 同一个 decoration、同一个字号，标签的墨迹与同等效
///     字号的纯文本逐像素一致；
///   · 换 `labelStyle` / `filled` / `floatingLabelStyle` / 字号档位 / 弹键盘，
///     全都不复现；`_kFinalLabelScale`（0.75 缩小）与 `_getFloatingLabelStyle`
///     结尾那句 `.copyWith(height: 1)`（行盒被强制成 1em）是唯一两处「不寻常」，
///     而它们在 Windows 的 flutter_tester 上与在设备上表现不同 —— 那是**平台
///     渲染路径的差别**，不是我们能从这边调平的参数。
///
/// 所以干脆不用它：标签自己画一行 `Text`，输入框自己画。这条路径没有任何平台
/// 相关行为，也不再依赖 Material 的浮动几何。观感也与 app 自己的表单一致 ——
/// 编辑排班页的「开始 / 结束 / 响铃」那几行本来就是「标签在上、值在下」。
///
/// ## 用法
///
/// ```dart
/// GlassField(
///   label: L10n.title,
///   child: TextField(
///     controller: ctrl,
///     decoration: glassInputDecoration(context),
///   ),
/// )
/// ```
///
/// [child] 由调用点自己建：`TextField` 上的各种参数（controller / maxLength /
/// textAlign / style / 键盘类型…）不下沉到这里，**只包一层布局** —— 下沉的话
/// 十个调用点各有各的参数，这个件会长成一棵瑞士军刀。
class GlassField extends StatelessWidget {
  const GlassField({
    super.key,
    required this.label,
    required this.child,
    this.isDense = false,
  });

  final String label;

  /// 调用点建好的输入框（decoration 走 [glassInputDecoration]）。
  final Widget child;

  /// 紧凑档：标签与框之间的间距收一档（编辑器里一行并排几个控件那种）。
  final bool isDense;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标签用**次要说明那一档 + 次要文字明度**（与「我的」页那些行内标签同一档）。
        // `maxLines: 1` + 省略号：窄窗（200dp）里「班次名称」这种四字标签要能收。
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTokens.labelSecondary.copyWith(
            color: AppTokens.inkMuted(context),
          ),
        ),
        SizedBox(height: isDense ? AppTokens.spaceXs : AppTokens.gapIconText),
        // 无障碍：屏幕阅读器读到的名字仍然来自这个标签。
        // 以前它是 `labelText`，Material 会把它挂到输入框的语义节点上；换成自画的
        // 标签之后那条链断了，用一层 `Semantics` 补回来。
        Semantics(label: label, child: child),
      ],
    );
  }
}
