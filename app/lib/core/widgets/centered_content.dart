import 'package:flutter/material.dart';

import '../layout.dart';

/// 宽屏下把内容限宽并居中，窄屏原样透传。
///
/// 表单在 1280 宽的车机上拉满整屏会难以阅读：「标签在左、值在右」的行两端
/// 离得太远，眼睛要在一条长线上来回找。限宽居中是宽屏表单的通行做法。
///
/// **窄屏下必须是零介入**（直接返回 child，不套任何额外的盒子），否则会在
/// 竖屏上多出一层约束，把「竖屏逐像素不变」破坏掉。
class CenteredContent extends StatelessWidget {
  const CenteredContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AppLayout.of(context).isWide) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
        child: child,
      ),
    );
  }
}
