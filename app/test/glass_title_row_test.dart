// GlassTitleRow —— 弹窗 / 弹层共用的标题行。
//
// 这一件是从 `GlassDialog` 里抽出来的（v0.12.0），抽出来本身不改观感；
// 两条用例只钉它自己的两个契约：副标题可选、以及标题的默认排版角色。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/widgets/glass_title_row.dart';

void main() {
  testWidgets('传了 subtitle 就排在标题下面，不传就只有标题', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: GlassTitleRow(title: '调整班次', subtitle: Text('10月13日')))));
    expect(find.text('调整班次'), findsOneWidget);
    expect(find.text('10月13日'), findsOneWidget);
    final t = tester.getRect(find.text('调整班次'));
    final s = tester.getRect(find.text('10月13日'));
    expect(t.bottom, lessThanOrEqualTo(s.top));

    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: GlassTitleRow(title: '调整班次'))));
    expect(find.text('10月13日'), findsNothing);
  });

  testWidgets('titleStyle 不给时默认 titleStrong', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: GlassTitleRow(title: '调整班次'))));
    final text = tester.widget<Text>(find.text('调整班次'));
    expect(text.style?.fontSize, AppTokens.titleStrong.fontSize);
  });

  // ── 竖条的落点 ────────────────────────────────────────────────────────────
  //
  // 2026-10-15 用户真机反馈：「调整班次那个界面，徽章（标题左边那根竖条）位置
  // 有点偏」。量出来是**竖条的垂直中心比标题字形的中心高 1.75dp** —— 同一根竖条
  // 在弹窗里只差 0.75dp、看着是正的，所以问题只出在「有副标题 → `start`」这一档。
  //
  // 机制：字是**在行盒里居中**的，而 `start` 把竖条的**顶边**对齐到行盒顶；
  // 弹层标题是 16sp（`titleStrong` 不带 height），行盒 ≈ 21dp 比竖条（18）高，
  // 于是竖条被顶到了字形中心的上面。
  testWidgets('有副标题时，竖条与标题「首行」垂直居中', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: GlassTitleRow(title: '调整班次', subtitle: Text('10月15日')))));
    final bar = tester.getRect(find.byKey(GlassTitleRow.barKey));
    final title = tester.getRect(find.text('调整班次'));
    expect((bar.center.dy - title.center.dy).abs(), lessThan(0.5),
        reason: '竖条要跟着**标题那一行**居中；顶到行盒顶就会比字形高半个行距');
    expect(bar.height, 18, reason: '竖条自己的尺寸不许跟着这次修复变');
    expect(bar.width, 4);
  });

  testWidgets('副标题折两行时，竖条仍留在标题那一行里（不被压到第二行旁边）',
      (tester) async {
    // 窄到副标题必须折行 —— 这一条是当年给这一行走 `start` 的理由，修复不许
    // 把它退回去（退回 `center` 的话竖条会跟着「标题 + 两行副标题」整块居中）。
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 120,
      child: GlassTitleRow(
          title: '调整班次',
          subtitle: Text('10月15日 – 10月31日 · 这段时间都用这一套')),
    ))));
    final bar = tester.getRect(find.byKey(GlassTitleRow.barKey));
    final title = tester.getRect(find.text('调整班次'));
    final sub = tester.getRect(find.text('10月15日 – 10月31日 · 这段时间都用这一套'));
    expect(sub.height, greaterThan(title.height),
        reason: '前提：这段副标题真的折了两行以上，用例才有鉴别力');
    expect(bar.bottom, lessThanOrEqualTo(title.bottom + 0.5),
        reason: '竖条不许越过标题那一行、跑到副标题旁边去');
  });
}
