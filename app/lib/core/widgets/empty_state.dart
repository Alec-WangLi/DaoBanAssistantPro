import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 空态：一句话（次要文字色）+ 统一留白 —— 全 app 唯一实现。
///
/// **这一版之前空态从没进过屏单**（工装 41 屏里零覆盖），所以它是一类
/// **没人看过的界面** —— 而同 app 里它曾经散着四五份手写实现、连留白都不一致
/// （有的上下 16、有的统统 24），既没有共享件、也没有护栏。这正是 v0.8.1 那次的
/// 同一类：四处设计跑偏过了三道评审，根因就是「没进屏单 = 没人真正看过」。
/// 收口到这一处之后，`visual_screens.dart` 里补上了空态屏（`62_alarm_empty` /
/// `63_todos_empty`），这一类的样子从此有人盯着。
///
/// 形态定为「一句话 + 统一留白」，**不配插图**（全 app 没有插图传统，见设计
/// §⑥）。次要文字色走 [AppTokens.rowSecondary]，颜色取 [AppTokens.inkMuted]
/// —— 与全 app 那句「层级只靠字号、字重、明度」一致。
///
/// [alignment] 默认 [Alignment.topCenter]：四处里三处（闹钟页的小节内、重复待办
/// 面板、待办页折叠区上方那一句）本来就是顶对齐；只有「整页没有任何待办」那处
/// 原来是垂直居中的，它显式传 [Alignment.center] —— 整页空态居中读起来才像
/// 空态，顶到最上面反而像漏了一行。
class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.alignment = Alignment.topCenter});

  final String message;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style:
              AppTokens.rowSecondary.copyWith(color: AppTokens.inkMuted(context)),
        ),
      ),
    );
  }
}
