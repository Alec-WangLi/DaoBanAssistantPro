import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 页面级小节标题 —— 全 app 唯一实现。
///
/// 一个页面里「一组行」上面那句标题（「外观」「排班」「关于」……）曾经散在
/// **四个文件、五份私有函数**里各写各的：`profile_screen` 的 `_sectionTitle`、
/// `alarm_screen` 的 `_sectionTitleRow` + `_sectionTitle`（两处）、
/// `schedule_management_screen` 的 `_sectionHeading`、`help_faq_screen` 的
/// `_groupHeading`。同一个角色三副面孔：排班管理与使用帮助走 `sectionTitle`
/// （18/w700）、闹钟走 `titleStrong`（16/w700）、「我的」页走
/// `labelSecondary` + 灰（13/w400）。用户在界面上一眼就看得出「不像一套东西」。
///
/// v0.12.0 收口到这里，标准由用户拍板为 [AppTokens.titleStrong]。**「我的」页
/// 那几行因此明显变大变黑**，那正是这一条要的效果、不是回归。
///
/// 只负责排：左右各留 [AppTokens.spaceXs]、下留 [AppTokens.spaceSm]（沿用
/// 收口前各处的 `fromLTRB(spaceXs, 0, spaceXs, spaceSm)`）。要额外的水平内缩
/// （例如闹钟页那种整行 16 的留白）由调用点自己套一层 `Padding`。
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.spaceXs, 0, AppTokens.spaceXs, AppTokens.spaceSm),
      child: Text(title, style: AppTokens.titleStrong),
    );
  }
}
