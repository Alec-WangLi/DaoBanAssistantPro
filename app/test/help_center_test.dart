// app/test/help_center_test.dart
//
// 第一级《使用帮助》（整页）。三件事要钉：
//   1. 简介与九条功能简介都在（九条是从弹窗搬过来的，搬丢了没人会报错）；
//   2. 那颗入口真的能进第二层；
//   3. **九条里的数字与实现一致** —— 这一版的起因之一就是文案漂了：
//      帮助里写着「一个班次最多挂 6 条闹钟」，而 v0.11.1 早就放到 10 条了。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/profile/help_center_screen.dart';
import 'package:shiftassistantpro/features/profile/help_faq_screen.dart';

/// 视口开得很高：这一批用例问的是「东西在不在页面上」，不是「版式对不对」
/// （版式归视觉工装）。矮视口下 `ListView` 只挂载可见元素，后面几条就找不到了。
Future<void> _pump(WidgetTester tester,
    {Size size = const Size(420, 6000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
  await tester.pumpAndSettle();
}

List<String> get _guideTitles => [
      L10n.guideCalTitle,
      L10n.guideSchedTitle,
      L10n.guideAlarmTitle,
      L10n.guideTodoTitle,
      L10n.guideWidgetTitle,
      L10n.guideAppearanceTitle,
      L10n.guideLayoutTitle,
      L10n.guidePermTitle,
      L10n.guideUpdateTitle,
    ];

void main() {
  testWidgets('简介与九条功能简介都在', (tester) async {
    L10n.locale = 'zh';
    await _pump(tester);
    expect(find.text(L10n.helpIntro), findsOneWidget);
    for (final t in _guideTitles) {
      expect(find.text(t), findsOneWidget, reason: '九条里少了「$t」');
    }
  });

  testWidgets('点那个入口进第二层', (tester) async {
    L10n.locale = 'zh';
    await _pump(tester);
    expect(find.text(L10n.faqEntryTitle), findsOneWidget);
    await tester.tap(find.text(L10n.faqEntryTitle));
    await tester.pumpAndSettle();
    expect(find.byType(HelpFaqScreen), findsOneWidget);
  });

  test('闹钟那一条的条数与 maxAlarmsPerShift 一致', () {
    L10n.locale = 'zh';
    expect(L10n.guideAlarmDesc.join(), contains('$maxAlarmsPerShift'),
        reason: '帮助里写着「最多挂 6 条」而实现是 10 条 —— 这条护栏就是为它加的');
    L10n.locale = 'en';
    expect(L10n.guideAlarmDesc.join(), contains('$maxAlarmsPerShift'));
    L10n.locale = 'zh';
  });

  test('九条功能简介里不许出现 markdown 标记', () {
    final bad = RegExp(r'\*\*|`|^#|\[[^\]]+\]\([^)]+\)', multiLine: true);
    for (final locale in const ['zh', 'en']) {
      L10n.locale = locale;
      final all = [
        ...L10n.guideCalDesc,
        ...L10n.guideSchedDesc,
        ...L10n.guideAlarmDesc,
        ...L10n.guideTodoDesc,
        ...L10n.guideWidgetDesc,
        ...L10n.guideAppearanceDesc,
        ...L10n.guideLayoutDesc,
        ...L10n.guidePermDesc,
        ...L10n.guideUpdateDesc,
      ];
      for (final s in all) {
        expect(bad.hasMatch(s), isFalse, reason: '$locale 命中 markdown：$s');
      }
    }
    L10n.locale = 'zh';
  });

  // 「我的 → 桌面」那一行从「弹自己那份小组件说明」改成「跳进这里并翻到
  // 『桌面小组件』那一节」（全 app 只剩一份文案）。这两条钉住那一次滚动 ——
  // 视口必须**矮到装不下**，否则整页都在屏里、滚不滚都一样。
  testWidgets('scrollToWidgets 一路滚到「桌面小组件」那一条', (tester) async {
    L10n.locale = 'zh';
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
        home: HelpCenterScreen(scrollToWidgets: true)));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.text(L10n.guideWidgetTitle));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(800),
        reason: '滚完之后「桌面小组件」那一条必须真的在视口里');
  });

  testWidgets('不传 scrollToWidgets 时停在页首', (tester) async {
    L10n.locale = 'zh';
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
    await tester.pumpAndSettle();
    expect(find.text(L10n.helpIntro), findsOneWidget);
  });
}
