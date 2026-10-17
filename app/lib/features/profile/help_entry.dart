import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/widgets/app_icon.dart';

/// 帮助里的一条：图标 + 标题 + 正文行。
///
/// 第一级《使用帮助》与「开始使用」弹窗共用这一份 —— 两处各画一遍的话，
/// 圆点尺寸、间距、图标圆钮的配方会慢慢漂开（它们本来就是同一件东西）。
///
/// [lines] 多于一行时每行前面加一个小圆点（参考条目是多项并列，得能扫）；
/// 只有一行、且是引导语时把 [bulleted] 关掉 —— 单条正文顶个圆点像没写完的列表。
///
/// **v0.11.17 之前它叫 `_GuideEntry`，私藏在 `app_dialogs.dart` 里**；
/// 第二轮（《使用帮助》变成整页）要复用它，才搬出来公开。搬运是逐像素不变的。
class HelpEntry extends StatelessWidget {
  const HelpEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.lines,
    this.bulleted = true,
  });

  final IconData icon;

  /// 条目标题。
  ///
  /// **v0.11.17 之前它是可空的** —— 当时「我的 → 桌面小组件」那个说明弹层复用
  /// 这个件、且不顶标题（弹窗标题已经把「是什么」说了）。那份弹层并进《使用帮助》
  /// 之后**没有任何调用点再传 null**，于是可空与那条分支一起删了：留着的话，
  /// 下一个人得先想一遍「什么时候会没有标题」才能改这一行。
  final String title;
  final List<String> lines;
  final bool bulleted;

  /// 条目宽度窄于这个数就换成「图标在上、文字在下」。
  ///
  /// 并排时图标吃掉 38 + 12 = 50dp。小窗（200×400）里「开始使用」那个弹窗的内宽
  /// 只有约 112dp，文字只剩 62dp ≈ 每行四五个字 —— 2026-10-15 用户报的
  /// 「正文挤到没法读」正是它（v0.9.5 就记下了这条，当时留待拍板）。
  ///
  /// 260 的来历：并排之后文字还想剩 ~210dp（≈16 个汉字一行）才值当并排，
  /// 210 + 50 = 260。**不看屏幕宽**而看这一条自己拿到多宽 —— 弹窗内宽与窗口宽
  /// 不是一回事（同一个 420 的屏，弹窗里只有 372）。
  static const double _stackBelow = 260;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return constraints.maxWidth < _stackBelow ? _stacked(context) : _sideBySide(context);
    });
  }

  Widget _sideBySide(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _iconButton(context),
        const SizedBox(width: 12),
        Expanded(child: _texts(context)),
      ],
    );
  }

  /// 窄窗那一挡：图标自己站一行。换来的是**正文拿到整行宽度**（62 → 112dp）。
  Widget _stacked(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _iconButton(context),
        const SizedBox(height: AppTokens.spaceSm),
        _texts(context),
      ],
    );
  }

  Widget _iconButton(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.28),
            accent.withValues(alpha: 0.10),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: AppIcon(icon, size: AppTokens.iconMd, color: accent),
    );
  }

  Widget _texts(BuildContext context) {
    final muted = AppTokens.inkMuted(context);
    final body = AppTokens.rowSecondary.copyWith(height: 1.45, color: muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTokens.labelStrong),
        const SizedBox(height: AppTokens.padChipV),
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: AppTokens.spaceXs),
          if (!bulleted)
            Text(lines[i], style: body)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 圆点用固定 4dp（设计语言里「被改过的那天」也是这个尺寸），
                // 不跟字号缩放 —— 小窗下缩到 1~2px 就等于没有。
                // 上边距是把它压到首行文字中线上（spaceSm = 8），
                // 7 那种值不上 4px 栅格，会打红 design_tokens_test。
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(top: AppTokens.spaceSm),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: muted.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(width: 8),
                // 走 Expanded 而不是给整段加「· 」前缀：英文条目会折行，
                // 前缀写法的第二行会顶到最左边、看不出是同一条。
                Expanded(child: Text(lines[i], style: body)),
              ],
            ),
        ],
      ],
    );
  }
}
